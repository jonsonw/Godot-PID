class_name GPCMemberRoster
extends RefCounted
# Copyright © 2026 Jonson Wang
# Pure member-roster CRUD + the archive-level apply blade (W14 T4b, ADR-40 D3; v1.3
# credential model). Credential hashes live INSIDE the member entries — the manager
# assigns username + initial password + roles, and the archive carries them to every
# workstation via the shared NAS file.
# 纯成员名单增删改查 + 存档级落盘刀（W14 T4b，ADR-40 D3；v1.3 凭据模型）。凭据哈希**内嵌**
# 成员条目 —— 管理者分配用户名 + 初始密码 + 角色，存档经 NAS 共享把凭据带到每个工作站。
#
# v1.3 MODEL / v1.3 模型（2026-11-18 用户拍板）：the manager IS the registrar — no
# first-login set-password. Each member entry carries {user, roles, enabled, display_name,
# salt, hash, iterations}. Trust level stays "anti-mistake, not anti-malicious" (ADR-40
# D8): a shared hash can be brute-forced offline if the password is weak; the cloud phase
# replaces this with server-side auth.
# v1.3 模型（2026-11-18 用户拍板）：管理者**就是**登记人 —— 没有首登设密。每个成员条目
# 携带 {user, roles, enabled, display_name, salt, hash, iterations}。信任等级保持
# 「防误操作、不防恶意」（ADR-40 D8）：共享哈希在弱密码下可被离线爆破；云端阶段换服务端认证。
#
# LAYER RULE / 分层约束：the CRUD is pure-dict static (headless-testable); gpApplyToArchive
# is the ONE place that reads an archive, swaps members, re-stamps the revision (members
# ARE hashed, so a roster edit without a re-stamp would fail GPRevision.gpVerify) and
# writes atomically. No autoload.
# 增删改查为纯 dict 静态（headless 可测）；gpApplyToArchive 是唯一「读档 → 换名单 →
# 重盖修订（members **参与哈希**，改名单不重盖会使 GPRevision.gpVerify 失败）→ 原子写」
# 的地方。零 autoload。

# Machine-readable codes (ADR-12 semantics).
# 机器可读码（ADR-12 语义）。
const GP_ERR_BAD_USER: String = "roster.bad_user"
const GP_ERR_BAD_PASSWORD: String = "roster.bad_password"
const GP_ERR_DUPLICATE: String = "roster.duplicate"
const GP_ERR_BAD_ROLES: String = "roster.bad_roles"
const GP_ERR_NOT_FOUND: String = "roster.not_found"
const GP_ERR_DISABLED: String = "roster.disabled"
const GP_ERR_NO_CREDENTIAL: String = "roster.no_credential"
const GP_ERR_ARCHIVE_FAIL: String = "roster.archive_fail"


# Locate one member entry ({} when absent). / 定位单个成员条目（缺失时为空字典）。
static func gpFind(gpMembers: Array, gpUser: String) -> Dictionary:
	for gpRaw in gpMembers:
		if gpRaw is Dictionary and str((gpRaw as Dictionary).get("user", "")) == gpUser:
			return gpRaw as Dictionary
	return {}


# Are all roles inside the frozen vocabulary? / 全部角色都在冻结词表内？
static func gpRolesValid(gpRoles: Array) -> bool:
	if gpRoles.is_empty():
		return false
	for gpR in gpRoles:
		if not GPProjectContainerV4.GP_ROLES.has(str(gpR)):
			return false
	return true


# Add a member WITH its assigned credential (v1.3: the manager sets the initial password).
# 添加成员**并分配凭据**（v1.3：管理者设初始密码）。
static func gpAdd(gpMembers: Array, gpUser: String, gpPassword: String, gpRoles: Array,
		gpDisplayName: String = "", gpEnabled: bool = true, gpEmail: String = "") -> Dictionary:
	var gpName: String = gpUser.strip_edges()
	if gpName == "":
		return {"ok": false, "code": GP_ERR_BAD_USER}
	if not GPIdentityCredentials.gpIsValidPassword(gpPassword):
		return {"ok": false, "code": GP_ERR_BAD_PASSWORD}
	if gpFind(gpMembers, gpName) != {}:
		return {"ok": false, "code": GP_ERR_DUPLICATE}
	if not gpRolesValid(gpRoles):
		return {"ok": false, "code": GP_ERR_BAD_ROLES}
	var gpSalt: String = GPIdentityCredentials.gpNewSalt()
	gpMembers.append({
		"user": gpName,
		"roles": gpRoles.duplicate(true),
		"enabled": gpEnabled,
		"display_name": gpDisplayName,
		"email": gpEmail,
		"salt": gpSalt,
		"hash": GPIdentityCredentials.gpHashPassword(gpPassword, gpSalt),
		"iterations": GPIdentityCredentials.GP_ITERATIONS,
	})
	return {"ok": true, "code": ""}


# The SHIPPED default super-admin: username admin, password admin — INVALID by design
# (5 < 6 chars) so the first-run dialog can never be skipped legitimately. It seeds the
# roster at archive creation and gpIsDefaultAdmin() detects it on every open.
# 出厂默认超级管理员：用户名 admin、密码 admin —— **刻意**不合法（5 < 6 位），使首登
# 强制改密在逻辑上无法被正当跳过。创建存档时种入名单，gpIsDefaultAdmin() 在每次打开时检测。
static func gpSeedAdmin(gpMembers: Array) -> void:
	var gpSalt: String = GPIdentityCredentials.gpNewSalt()
	gpMembers.append({
		"user": "admin",
		"roles": ["manager"],
		"enabled": true,
		"display_name": "Administrator",
		"email": "",
		"salt": gpSalt,
		"hash": GPIdentityCredentials.gpHashPassword("admin", gpSalt),
		"iterations": GPIdentityCredentials.GP_ITERATIONS,
	})


# Is the archive still on its SHIPPED default admin credential (admin/admin)? The first-run
# forced change triggers exactly on this — and only on this.
# 存档是否仍在**出厂默认** admin/admin 凭据上？首登强制改密只在此时触发。
static func gpIsDefaultAdmin(gpMembers: Array) -> bool:
	var gpM: Dictionary = gpFind(gpMembers, "admin")
	if gpM.is_empty():
		return false
	return GPIdentityCredentials.gpVerify("admin", str(gpM.get("salt", "")),
		str(gpM.get("hash", "")))


# Update a member's credential / display name / roles / email (the panel's apply-changes
# blade, the self-service password change and the first-run dialog). An EMPTY password
# keeps the current hash; an EMPTY email keeps the current address.
# 更新成员的凭据 / 显示名 / 角色 / 邮箱（面板「应用变更」刀、自助改密与首登对话框）。
# **空**密码保持现有哈希；**空**邮箱保持现有地址。
static func gpSetCredential(gpMembers: Array, gpUser: String, gpPassword: String,
		gpDisplayName: String, gpRoles: Array, gpEmail: String = "") -> Dictionary:
	var gpM: Dictionary = gpFind(gpMembers, gpUser)
	if gpM.is_empty():
		return {"ok": false, "code": GP_ERR_NOT_FOUND}
	if not gpRolesValid(gpRoles):
		return {"ok": false, "code": GP_ERR_BAD_ROLES}
	if gpPassword != "":
		if not GPIdentityCredentials.gpIsValidPassword(gpPassword):
			return {"ok": false, "code": GP_ERR_BAD_PASSWORD}
		var gpSalt: String = GPIdentityCredentials.gpNewSalt()
		gpM["salt"] = gpSalt
		gpM["hash"] = GPIdentityCredentials.gpHashPassword(gpPassword, gpSalt)
		gpM["iterations"] = GPIdentityCredentials.GP_ITERATIONS
	gpM["display_name"] = gpDisplayName
	gpM["roles"] = gpRoles.duplicate(true)
	if gpEmail != "":
		gpM["email"] = gpEmail
	return {"ok": true, "code": ""}


# Rename a member IN PLACE: the credential hash, roles, enabled flag and display name
# all stay untouched (the inline table edit needs this — renaming must not cost a
# password re-assignment).
# 原地改名：凭据哈希、角色、启停与显示名**全部保留**（表格内联编辑需要 ——
# 改名绝不能顺带要求重设密码）。
static func gpRenameUser(gpMembers: Array, gpOld: String, gpNew: String) -> Dictionary:
	var gpName: String = gpNew.strip_edges()
	if gpName == "":
		return {"ok": false, "code": GP_ERR_BAD_USER}
	var gpM: Dictionary = gpFind(gpMembers, gpOld)
	if gpM.is_empty():
		return {"ok": false, "code": GP_ERR_NOT_FOUND}
	var gpClash: Dictionary = gpFind(gpMembers, gpName)
	if gpName != gpOld and gpClash != {}:
		return {"ok": false, "code": GP_ERR_DUPLICATE}
	gpM["user"] = gpName
	return {"ok": true, "code": ""}


# Enable / disable a member (a disabled member stays on the roster for audit — ADR-40 D4
# entry comment: 停用成员保留名单便于审计). / 启停成员（停用者保留名单便于审计）。
static func gpSetEnabled(gpMembers: Array, gpUser: String, gpEnabled: bool) -> Dictionary:
	var gpM: Dictionary = gpFind(gpMembers, gpUser)
	if gpM.is_empty():
		return {"ok": false, "code": GP_ERR_NOT_FOUND}
	gpM["enabled"] = gpEnabled
	return {"ok": true, "code": ""}


# Set roles. / 设置角色。
static func gpSetRoles(gpMembers: Array, gpUser: String, gpRoles: Array) -> Dictionary:
	var gpM: Dictionary = gpFind(gpMembers, gpUser)
	if gpM.is_empty():
		return {"ok": false, "code": GP_ERR_NOT_FOUND}
	if not gpRolesValid(gpRoles):
		return {"ok": false, "code": GP_ERR_BAD_ROLES}
	gpM["roles"] = gpRoles.duplicate(true)
	return {"ok": true, "code": ""}


# Remove a member entirely (confirm dialog lives in the UI; this is the data blade).
# 彻底移除成员（确认弹窗在 UI 层；这里是数据刀）。
static func gpRemove(gpMembers: Array, gpUser: String) -> Dictionary:
	for gpI in range(gpMembers.size()):
		var gpRaw: Variant = gpMembers[gpI]
		if gpRaw is Dictionary and str((gpRaw as Dictionary).get("user", "")) == gpUser:
			gpMembers.remove_at(gpI)
			return {"ok": true, "code": ""}
	return {"ok": false, "code": GP_ERR_NOT_FOUND}


# The pure verify blade behind the login dialog: membership → enabled → credential →
# hash. Every failure carries its machine code (the UI maps it to an honest line).
# 登录对话框背后的纯验证刀：在册 → 启用 → 凭据 → 哈希。每个失败都携带机器码
#（UI 把它映射为如实的提示行）。
static func gpVerifyLogin(gpMembers: Array, gpUser: String, gpPassword: String) -> Dictionary:
	var gpM: Dictionary = gpFind(gpMembers, gpUser)
	if gpM.is_empty():
		return {"ok": false, "code": GP_ERR_NOT_FOUND}
	if not bool(gpM.get("enabled", true)):
		return {"ok": false, "code": GP_ERR_DISABLED}
	if str(gpM.get("hash", "")) == "":
		return {"ok": false, "code": GP_ERR_NO_CREDENTIAL}
	if GPIdentityCredentials.gpVerify(gpPassword, str(gpM.get("salt", "")),
			str(gpM.get("hash", ""))):
		return {"ok": true, "code": ""}
	return {"ok": false, "code": GP_ERR_BAD_PASSWORD}


# THE apply blade: read the archive, swap the members, re-stamp the revision (the roster
# participates in the content hash), write atomically. author stamps last_saved_by.
# 落盘刀：读档 → 换名单 → 重盖修订（名单参与内容哈希）→ 原子写。author 盖进 last_saved_by。
static func gpApplyToArchive(gpPath: String, gpMembers: Array, gpAuthor: String) -> GPIOResult:
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
	if not gpRead.gpIsOk():
		return GPIOResult.gpFailure(GP_ERR_ARCHIVE_FAIL, "identity.roster_apply_fail", gpPath)
	var gpDict: Dictionary = gpRead.gpPayload as Dictionary
	for gpM in gpMembers:
		if not (gpM is Dictionary) or str((gpM as Dictionary).get("user", "")) == "":
			return GPIOResult.gpFailure(GP_ERR_BAD_USER, "identity.roster_apply_fail", gpPath)
	gpDict["members"] = gpMembers.duplicate(true)
	GPRevision.gpStampRevision(gpDict, gpAuthor, Time.get_datetime_string_from_system())
	if not GPAtomicFile.gpWriteJsonAtomic(gpPath, gpDict).gpIsOk():
		return GPIOResult.gpFailure("io.write_failed", "identity.roster_apply_fail", gpPath)
	return GPIOResult.gpSuccess("identity.roster_applied", gpPath)
