class_name GPCMemberRoster
extends RefCounted
# Copyright © 2026 Jonson Wang
# Pure member-roster CRUD + the archive-level apply blade (W14 T4b, ADR-40 D3/D4).
# 纯成员名单增删改查 + 存档级落盘刀（W14 T4b，ADR-40 D3/D4）。
#
# SEMANTICS / 语义（「注册」的项目侧一半）：
# The roster in the plaintext header IS the approval — being added by the manager means
# the user may register credentials on their own machine (first-login set-password).
# Roles are the frozen GP_ROLES vocabulary; the role CAPABILITY matrix is W15 — this file
# only manages the DATA.
# 明文头部的名单**就是**审批 —— 被管理者加入即可在自己机器上注册凭据（首登设密）。
# 角色取冻结的 GP_ROLES 词表；角色**能力**矩阵是 W15 —— 本文件只管数据。
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
const GP_ERR_DUPLICATE: String = "roster.duplicate"
const GP_ERR_BAD_ROLES: String = "roster.bad_roles"
const GP_ERR_NOT_FOUND: String = "roster.not_found"
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


# Add a member. Returns {ok: bool, code: String} — ok=false carries the machine code.
# 添加成员。返回 {ok, code} —— ok=false 时携带机器可读码。
static func gpAdd(gpMembers: Array, gpUser: String, gpRoles: Array, gpEnabled: bool = true) -> Dictionary:
	var gpName: String = gpUser.strip_edges()
	if gpName == "":
		return {"ok": false, "code": GP_ERR_BAD_USER}
	if gpFind(gpMembers, gpName) != {}:
		return {"ok": false, "code": GP_ERR_DUPLICATE}
	if not gpRolesValid(gpRoles):
		return {"ok": false, "code": GP_ERR_BAD_ROLES}
	gpMembers.append({"user": gpName, "roles": gpRoles.duplicate(true), "enabled": gpEnabled})
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
