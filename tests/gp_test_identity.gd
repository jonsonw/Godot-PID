extends "res://tests/gp_test.gd"
# Headless regression tests for identity: password hashing (core), the member-embedded
# credential model (v1.3: hashes live in member entries and travel with the archive),
# the roster CRUD + archive apply blade (io), and the enabled-member projection used by
# the login flow (W14 T4a/T4b, ADR-40 D2/D3; v1.3 manager-assigns model).
# 身份的 headless 回归测试：密码哈希（core）、成员内嵌凭据模型（v1.3：哈希在成员条目里、
# 随存档走）、名单 CRUD + 存档落盘刀（io）、登录流程使用的启用成员投影
#（W14 T4a/T4b，ADR-40 D2/D3；v1.3 管理者分配模型）。

const GP_ARCHIVE_PATH: String = "user://gp_test_identity.pid.json"


# Clean the scratch files. / 清理临时文件。
func _gpCleanup() -> void:
	for gpPath in [GP_ARCHIVE_PATH, GP_ARCHIVE_PATH + ".bak", GP_ARCHIVE_PATH + ".tmp"]:
		var gpAbs: String = ProjectSettings.globalize_path(gpPath)
		if FileAccess.file_exists(gpAbs):
			DirAccess.remove_absolute(gpAbs)


# ============================ credentials (core) ============================
# ============================ 凭据哈希（core） ============================

# Hash/verify round-trip: the right password verifies, a wrong one does not.
# 哈希/校验往返：正确密码通过，错误密码不通过。
func gpTestHashVerifyRoundTrip() -> void:
	var gpSalt: String = GPIdentityCredentials.gpNewSalt()
	var gpHash: String = GPIdentityCredentials.gpHashPassword("correct horse", gpSalt)
	gpCheck(GPIdentityCredentials.gpVerify("correct horse", gpSalt, gpHash),
		"the correct password must verify")
	gpCheck(not GPIdentityCredentials.gpVerify("wrong horse", gpSalt, gpHash),
		"a wrong password must NOT verify")
	gpEq(gpHash.length(), 64, "the hash must be a 64-char sha256 hex digest")


# The iteration count is the FROZEN constant (changing it invalidates stored hashes).
# 迭代次数是**冻结**常量（改动会使已存哈希全部失效）。
func gpTestIterationsFrozen() -> void:
	gpEq(GPIdentityCredentials.GP_ITERATIONS, 4096, "the iteration count must stay frozen at 4096")


# Salts are per-user random: two calls never coincide.
# 盐按用户随机：两次调用绝不相同。
func gpTestSaltRandom() -> void:
	gpCheck(GPIdentityCredentials.gpNewSalt() != GPIdentityCredentials.gpNewSalt(),
		"two salts must never coincide")


# The same password under two salts produces two different hashes (per-user salt, D4).
# 同一密码在两个盐下产生两个不同哈希（每用户独立盐，D4）。
func gpTestSaltChangesHash() -> void:
	var gpHashA: String = GPIdentityCredentials.gpHashPassword("pw", GPIdentityCredentials.gpNewSalt())
	var gpHashB: String = GPIdentityCredentials.gpHashPassword("pw", GPIdentityCredentials.gpNewSalt())
	gpCheck(gpHashA != gpHashB, "the same password under different salts must hash differently")


# The minimum-length gate. / 最短长度闸。
func gpTestPasswordRules() -> void:
	gpCheck(not GPIdentityCredentials.gpIsValidPassword(""), "an empty password must be rejected")
	gpCheck(not GPIdentityCredentials.gpIsValidPassword("12345"), "a 5-char password must be rejected")
	gpCheck(GPIdentityCredentials.gpIsValidPassword("123456"), "a 6-char password must be accepted")


# ===================== member-embedded credentials (v1.3) =====================
# ===================== 成员内嵌凭据（v1.3） =====================

# The full credential round-trip on the ROSTER (v1.3: add-with-password, verify, re-set
# password, display name) — the manager-assigns model's data path.
# 名单上的完整凭据往返（v1.3：带密码添加、验证、重设密码、显示名）——
# 管理者分配模型的数据通路。
func gpTestMemberCredentialRoundTrip() -> void:
	var gpMembers: Array = []
	gpCheck(bool(GPCMemberRoster.gpAdd(gpMembers, "alice", "hunter2!", ["manager"],
			"Alice Chen").get("ok", false)),
		"adding alice with an assigned password must succeed")
	var gpEntry: Dictionary = GPCMemberRoster.gpFind(gpMembers, "alice")
	gpCheck(str(gpEntry.get("hash", "")) != "",
		"the entry must carry a credential hash")
	gpEq(str(gpEntry.get("display_name", "")), "Alice Chen",
		"the display name must ride the entry")
	gpCheck(bool(GPCMemberRoster.gpVerifyLogin(gpMembers, "alice", "hunter2!").get("ok", false)),
		"the assigned password must verify through the roster")
	gpCheck(not bool(GPCMemberRoster.gpVerifyLogin(gpMembers, "alice", "wrong!").get("ok", false)),
		"a wrong password must fail through the roster")
	gpCheck(bool(GPCMemberRoster.gpSetCredential(gpMembers, "alice", "",
			"Alice C.", ["manager"]).get("ok", false)),
		"a blank password must keep the hash (display-name edit only)")
	gpEq(str(GPCMemberRoster.gpFind(gpMembers, "alice").get("display_name", "")),
		"Alice C.", "the display-name update must persist")
	var gpOldHash: String = str(GPCMemberRoster.gpFind(gpMembers, "alice").get("hash", ""))
	gpCheck(bool(GPCMemberRoster.gpSetCredential(gpMembers, "alice", "new-pw-9",
			"Alice C.", ["manager"]).get("ok", false)),
		"re-assigning the password must succeed")
	gpCheck(str(GPCMemberRoster.gpFind(gpMembers, "alice").get("hash", "")) != gpOldHash,
		"the hash must change after a password re-assignment")
	gpCheck(not bool(GPCMemberRoster.gpVerifyLogin(gpMembers, "alice", "hunter2!").get("ok", false)),
		"the OLD password must stop verifying after the re-assignment")
	gpCheck(bool(GPCMemberRoster.gpVerifyLogin(gpMembers, "alice", "new-pw-9").get("ok", false)),
		"the NEW password must verify after the re-assignment")
	gpCheck(bool(GPCMemberRoster.gpRemove(gpMembers, "alice").get("ok", false)),
		"removing alice must succeed")
	gpEq(str(GPCMemberRoster.gpVerifyLogin(gpMembers, "alice", "new-pw-9").get("code", "")),
		GPCMemberRoster.GP_ERR_NOT_FOUND,
		"a removed member must fail with not_found")


# The honest failure codes: a legacy entry without a hash and a disabled member both
# refuse to sign in with DISTINCT machine codes. / 如实的失败码：无哈希的旧式条目与
# 停用成员都拒绝登录，且携带**不同**机器码。
func gpTestVerifyFailureCodes() -> void:
	var gpMembers: Array = [
		{"user": "legacy", "roles": ["designer"], "enabled": true},
		{"user": "ben", "roles": ["designer"], "enabled": false,
			"salt": "s", "hash": "h", "iterations": 4096},
	]
	var gpNoCred: Dictionary = GPCMemberRoster.gpVerifyLogin(gpMembers, "legacy", "any")
	gpCheck(not bool(gpNoCred.get("ok", false)),
		"a member without an assigned password must not verify")
	gpEq(str(gpNoCred.get("code", "")), GPCMemberRoster.GP_ERR_NO_CREDENTIAL,
		"the missing credential must carry its machine code")
	gpEq(str(GPCMemberRoster.gpVerifyLogin(gpMembers, "ben", "any").get("code", "")),
		GPCMemberRoster.GP_ERR_DISABLED,
		"a disabled member must be refused BEFORE the hash is even consulted")


# v1.3 reverses the D4 storage rule ON PURPOSE: the HASH travels inside the archive, but
# the PLAINTEXT password must never appear in the file text.
# v1.3 有意反转 D4 的存储规则：**哈希**随存档走，但**明文密码**绝不出现在文件文本里。
func gpTestHashTravelsPlaintextNever() -> void:
	_gpCleanup()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-101", Vector2(10, 20)))
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpGraph = gpG
	gpEq(GPProjectIO.gpWriteSheets([gpSheet], GP_ARCHIVE_PATH, []), OK,
		"the base archive must save")
	var gpMembers: Array = []
	gpCheck(bool(GPCMemberRoster.gpAdd(gpMembers, "carol", "secret-pw", ["designer"]).get("ok", false)),
		"adding carol with the plaintext under test must succeed")
	var gpRes: GPIOResult = GPCMemberRoster.gpApplyToArchive(GP_ARCHIVE_PATH, gpMembers, "carol")
	gpCheck(gpRes.gpIsOk(), "the archive write with the roster must succeed")
	var gpText: String = FileAccess.get_file_as_string(GP_ARCHIVE_PATH)
	gpCheck(not gpText.contains("secret-pw"),
		"the PLAINTEXT password must never enter the archive")
	gpCheck(gpText.contains("hash"),
		"the credential HASH must travel inside the archive (v1.3)")
	_gpCleanup()


# ============================ member roster (io) ============================
# ============================ 成员名单（io） ============================

# Add / duplicate / bad-roles / bad-password / set-enabled / set-roles / remove, all pure.
# 添加 / 重复 / 非法角色 / 非法密码 / 启停 / 改角色 / 移除，全部纯函数。
func gpTestRosterCrud() -> void:
	var gpMembers: Array = []
	gpCheck(bool(GPCMemberRoster.gpAdd(gpMembers, "alice", "pw-alice", ["manager"]).get("ok", false)),
		"adding alice as manager must succeed")
	gpCheck(not bool(GPCMemberRoster.gpAdd(gpMembers, "alice", "pw-alice", ["designer"]).get("ok", false)),
		"a duplicate user must be rejected")
	gpEq(str(GPCMemberRoster.gpAdd(gpMembers, "alice", "pw-alice", ["designer"]).get("code", "")),
		GPCMemberRoster.GP_ERR_DUPLICATE, "the duplicate must carry its machine code")
	gpCheck(not bool(GPCMemberRoster.gpAdd(gpMembers, "bob", "pw-bob", []).get("ok", false)),
		"an empty role set must be rejected")
	gpCheck(not bool(GPCMemberRoster.gpAdd(gpMembers, "bob", "pw-bob", ["admin"]).get("ok", false)),
		"an out-of-vocabulary role must be rejected")
	gpCheck(not bool(GPCMemberRoster.gpAdd(gpMembers, "bob", "12345", ["designer"]).get("ok", false)),
		"a too-short password must be rejected (v1.3)")
	gpEq(str(GPCMemberRoster.gpAdd(gpMembers, "bob", "12345", ["designer"]).get("code", "")),
		GPCMemberRoster.GP_ERR_BAD_PASSWORD,
		"the short password must carry its machine code")
	gpCheck(not bool(GPCMemberRoster.gpAdd(gpMembers, "  ", "pw-bob", ["designer"]).get("ok", false)),
		"a blank username must be rejected")
	gpCheck(bool(GPCMemberRoster.gpAdd(gpMembers, "bob", "pw-bob", ["designer", "reviewer"]).get("ok", false)),
		"stacked roles must be accepted (ADR-40 D3)")
	gpCheck(bool(GPCMemberRoster.gpSetEnabled(gpMembers, "bob", false).get("ok", false)),
		"disabling bob must succeed")
	gpCheck(not bool(GPCMemberRoster.gpSetEnabled(gpMembers, "ghost", true).get("ok", false)),
		"disabling an absent member must fail with not_found")
	gpCheck(bool(GPCMemberRoster.gpSetRoles(gpMembers, "bob", ["reviewer"]).get("ok", false)),
		"changing roles must succeed")
	var gpRemoval: Dictionary = GPCMemberRoster.gpRemove(gpMembers, "bob")
	gpCheck(bool(gpRemoval.get("ok", false)), "removing bob must succeed")
	gpEq(gpMembers.size(), 1, "only alice remains after the removal")


# The disabled member is kept on the roster (audit semantics, ADR-40 D4 comment).
# 停用成员保留在名单上（审计语义，ADR-40 D4 注释）。
func gpTestDisableKeepsEntry() -> void:
	var gpMembers: Array = [{"user": "dave", "roles": ["designer"], "enabled": true}]
	GPCMemberRoster.gpSetEnabled(gpMembers, "dave", false)
	gpEq(gpMembers.size(), 1, "a disabled member must stay on the roster")
	gpCheck(not bool((gpMembers[0] as Dictionary).get("enabled", true)),
		"the entry must carry enabled=false")


# Enabled projection: the login flow only offers ENABLED, named, unique users.
# 启用投影：登录流程只提供启用、有名字、去重的用户。
func gpTestEnabledProjection() -> void:
	var gpMembers: Array = [
		{"user": "alice", "roles": ["manager"], "enabled": true},
		{"user": "bob", "roles": ["designer"], "enabled": false},
		{"user": "carol", "roles": ["reviewer"]},  # missing enabled -> default true
		{"user": "alice", "roles": ["designer"], "enabled": true},  # duplicate name
		{"user": "", "roles": ["designer"], "enabled": true},  # blank name
		"not-a-dict",
	]
	var gpEnabled: Array[String] = GPIdentityCoordinator.gpEnabledOf(gpMembers)
	gpEq(gpEnabled.size(), 2, "only alice and carol must survive the projection")
	gpCheck(gpEnabled.has("alice") and gpEnabled.has("carol"),
		"the disabled, blank and malformed entries must be filtered out")


# Rename IN PLACE keeps the credential, roles and enabled flag (the inline table edit
# must not cost a password re-assignment).
# 原地改名保留凭据、角色与启停（内联表格编辑绝不能顺带要求重设密码）。
func gpTestRenameUserKeepsCredential() -> void:
	var gpMembers: Array = []
	gpCheck(bool(GPCMemberRoster.gpAdd(gpMembers, "alice", "pw-alice", ["designer"]).get("ok", false)),
		"adding alice must succeed")
	gpCheck(bool(GPCMemberRoster.gpRenameUser(gpMembers, "alice", "alicia").get("ok", false)),
		"renaming alice must succeed")
	gpEq(GPCMemberRoster.gpFind(gpMembers, "alice"), {},
		"the old name must be gone")
	var gpEntry: Dictionary = GPCMemberRoster.gpFind(gpMembers, "alicia")
	gpCheck(str(gpEntry.get("hash", "")) != "",
		"the credential hash must survive the rename")
	gpCheck(bool(GPCMemberRoster.gpVerifyLogin(gpMembers, "alicia", "pw-alice").get("ok", false)),
		"the assigned password must still verify under the new name")
	gpEq(str(GPCMemberRoster.gpRenameUser(gpMembers, "ghost", "x").get("code", "")),
		GPCMemberRoster.GP_ERR_NOT_FOUND, "renaming an absent member must fail")
	gpCheck(bool(GPCMemberRoster.gpAdd(gpMembers, "bob", "pw-bob", ["designer"]).get("ok", false)),
		"adding bob must succeed")
	gpEq(str(GPCMemberRoster.gpRenameUser(gpMembers, "alicia", "bob").get("code", "")),
		GPCMemberRoster.GP_ERR_DUPLICATE, "renaming onto an existing name must fail")


# The apply blade: read → swap members → RE-STAMP revision → atomic write; the archive
# verifies clean afterwards (the roster participates in the content hash).
# 落盘刀：读 → 换名单 → **重盖修订** → 原子写；随后存档校验干净
#（名单参与内容哈希）。
func gpTestApplyToArchiveRestamps() -> void:
	_gpCleanup()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-101", Vector2(10, 20)))
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpGraph = gpG
	gpEq(GPProjectIO.gpWriteSheets([gpSheet], GP_ARCHIVE_PATH, []), OK,
		"the base archive must save")
	var gpMembers: Array = [
		{"user": "alice", "roles": ["manager"], "enabled": true},
		{"user": "bob", "roles": ["designer"], "enabled": true},
	]
	var gpRes: GPIOResult = GPCMemberRoster.gpApplyToArchive(GP_ARCHIVE_PATH, gpMembers, "alice")
	gpCheck(gpRes.gpIsOk(), "the roster apply must succeed: " + gpRes.gpToString())
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(GP_ARCHIVE_PATH)
	gpCheck(gpRead.gpIsOk(), "the archive must parse after the apply")
	if gpRead.gpIsOk():
		var gpDict: Dictionary = gpRead.gpPayload as Dictionary
		gpEq((gpDict.get("members", []) as Array).size(), 2, "the roster must be persisted")
		gpEq(GPRevision.gpVerify(gpDict).size(), 0,
			"the archive must verify clean after a roster change (re-stamped)")
		gpEq(str(gpDict.get("last_saved_by", "")), "alice",
			"the roster edit must be stamped with its author")
	_gpCleanup()


# The W14 permission gate exists and answers like its siblings (test seam flips it).
# W14 权限闸存在且与其余闸门同样作答（测试缝可翻转）。
func gpTestManageMembersGate() -> void:
	gpCheck(GPPermissions.gpCanManageMembers(), "the gate must allow by default")
	GPPermissions.gpForceDeny = true
	gpCheck(not GPPermissions.gpCanManageMembers(), "the gate must deny under the test seam")
	GPPermissions.gpForceDeny = false
	gpCheck(GPPermissions.gpCanManageMembers(), "the gate must be restored")


# ============================ v1.3.1 default admin / first run ============================
# ============================ v1.3.1 默认管理员 / 首登 ============================

# The shipped seed is admin/admin and gpIsDefaultAdmin detects it — the forced first-run
# change triggers on exactly this state.
# 出厂种子是 admin/admin 且 gpIsDefaultAdmin 能检出 —— 首登强制改密恰在此状态触发。
func gpTestDefaultAdminSeedAndDetection() -> void:
	var gpMembers: Array = []
	GPCMemberRoster.gpSeedAdmin(gpMembers)
	gpEq(gpMembers.size(), 1, "the seed must add exactly one entry")
	gpEq(str((gpMembers[0] as Dictionary).get("user", "")), "admin",
		"the seeded username must be admin")
	gpCheck(bool(GPCMemberRoster.gpVerifyLogin(gpMembers, "admin", "admin").get("ok", false)),
		"the shipped password must be admin")
	gpCheck(GPCMemberRoster.gpIsDefaultAdmin(gpMembers),
		"the fresh seed must be detected as the default admin")
	gpCheck(bool(GPCMemberRoster.gpSetCredential(gpMembers, "admin", "s3cret-pw",
		"Administrator", ["manager"]).get("ok", false)),
		"re-credentialling the admin must succeed")
	gpCheck(not GPCMemberRoster.gpIsDefaultAdmin(gpMembers),
		"a changed password must clear the default-admin detection")


# Creation seeds the admin/admin roster (not the anonymous "local" any more).
# 新建工程种入 admin/admin 名单（不再使用匿名 "local"）。
func gpTestCreateArchiveSeedsAdmin() -> void:
	_gpCleanup()
	var gpRes: GPIOResult = GPProjectLibrary.gpCreateArchiveV4(GP_ARCHIVE_PATH, "探针工程")
	gpCheck(gpRes.gpIsOk(), "the v4 creation must succeed")
	var gpHeader: GPIOResult = GPProjectIO.gpReadHeader(GP_ARCHIVE_PATH)
	gpCheck(gpHeader.gpIsOk(), "the header must read back")
	var gpMembers: Array = (gpHeader.gpPayload as Dictionary).get("members", []) as Array
	gpCheck(gpMembers.size() >= 1 and str((gpMembers[0] as Dictionary).get("user", "")) == "admin",
		"the seeded roster must start with admin")
	gpCheck(GPCMemberRoster.gpIsDefaultAdmin(gpMembers),
		"a freshly created archive must be on the default credential (first run)")
	_gpCleanup()


# The email field: gpAdd stores it, gpSetCredential with "" keeps it, with a value sets it.
# 邮箱字段：gpAdd 落存；gpSetCredential 空串**保持**、有值**设置**。
func gpTestEmailFieldSemantics() -> void:
	var gpMembers: Array = []
	gpCheck(bool(GPCMemberRoster.gpAdd(gpMembers, "dave", "dave-pass", ["designer"],
		"", true, "dave@example.com").get("ok", false)),
		"adding dave with an email must succeed")
	gpEq(str(GPCMemberRoster.gpFind(gpMembers, "dave").get("email", "")), "dave@example.com",
		"the email must be stored in the member entry")
	gpCheck(bool(GPCMemberRoster.gpSetCredential(gpMembers, "dave", "new-pass-9",
		"", ["designer"]).get("ok", false)),
		"a credential update with an empty email must succeed")
	gpEq(str(GPCMemberRoster.gpFind(gpMembers, "dave").get("email", "")), "dave@example.com",
		"an empty email in gpSetCredential must KEEP the stored address")
	gpCheck(bool(GPCMemberRoster.gpSetCredential(gpMembers, "dave", "new-pass-9",
		"", ["designer"], "dave@new.example").get("ok", false)),
		"a credential update with a real email must succeed")
	gpEq(str(GPCMemberRoster.gpFind(gpMembers, "dave").get("email", "")), "dave@new.example",
		"a real email in gpSetCredential must overwrite the stored address")


# The self-service blade: roles/display/email ride through a password-only change.
# 自助改密刀：只改密码时角色 / 显示名 / 邮箱原样保留。
func gpTestSelfServicePasswordChangeKeepsRoles() -> void:
	var gpMembers: Array = []
	GPCMemberRoster.gpSeedAdmin(gpMembers)
	var gpM: Dictionary = GPCMemberRoster.gpFind(gpMembers, "admin")
	gpM["display_name"] = "Boss"
	gpM["email"] = "boss@example.com"
	gpCheck(bool(GPCMemberRoster.gpVerifyLogin(gpMembers, "admin", "admin").get("ok", false)),
		"the old password must verify before the change")
	gpCheck(bool(GPCMemberRoster.gpSetCredential(gpMembers, "admin", "boss-pw-77",
		str(gpM.get("display_name", "")), gpM.get("roles", []) as Array,
		str(gpM.get("email", ""))).get("ok", false)),
		"the password-only re-credential must succeed")
	var gpAfter: Dictionary = GPCMemberRoster.gpFind(gpMembers, "admin")
	gpEq(str(gpAfter.get("roles", []) as Array), str(["manager"] as Array),
		"the roles must ride through untouched")
	gpEq(str(gpAfter.get("display_name", "")), "Boss", "the display name must ride through")
	gpEq(str(gpAfter.get("email", "")), "boss@example.com", "the email must ride through")
	gpCheck(bool(GPCMemberRoster.gpVerifyLogin(gpMembers, "admin", "boss-pw-77").get("ok", false)),
		"the new password must verify")
	gpCheck(not GPCMemberRoster.gpVerifyLogin(gpMembers, "admin", "admin").get("ok", false),
		"the old password must stop verifying")
