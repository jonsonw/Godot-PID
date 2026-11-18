extends "res://tests/gp_test.gd"
# Headless regression tests for identity: password hashing (core), the credential store
# (io), the member roster CRUD + archive apply blade (io), and the enabled-member
# projection used by the login flow (W14 T4a/T4b, ADR-40 D2/D3/D4).
# 身份的 headless 回归测试：密码哈希（core）、凭据库（io）、成员名单 CRUD + 存档落盘刀
#（io）、登录流程使用的启用成员投影（W14 T4a/T4b，ADR-40 D2/D3/D4）。

const GP_STORE_PATH: String = "user://gp_test_credentials.json"
const GP_ARCHIVE_PATH: String = "user://gp_test_identity.pid.json"


# Clean both scratch files. / 清理两个临时文件。
func _gpCleanup() -> void:
	for gpPath in [GP_STORE_PATH, GP_ARCHIVE_PATH, GP_ARCHIVE_PATH + ".bak", GP_ARCHIVE_PATH + ".tmp"]:
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


# ============================ credential store (io) ============================
# ============================ 凭据库（io） ============================

# Set / has / verify / display-name / remove round-trip on an ISOLATED store path
# (never the real user://credentials.json).
# 在**隔离**库路径上的设 / 查 / 校验 / 显示名 / 删除往返（绝不触碰真实 user://credentials.json）。
func gpTestStoreRoundTrip() -> void:
	_gpCleanup()
	gpCheck(not GPCredentialStore.gpHasUser("alice", GP_STORE_PATH),
		"a fresh store must not know alice")
	gpCheck(GPCredentialStore.gpSetCredential("alice", "hunter2!", "Alice Chen", GP_STORE_PATH),
		"setting a credential must succeed")
	gpCheck(GPCredentialStore.gpHasUser("alice", GP_STORE_PATH), "alice must now exist")
	gpCheck(GPCredentialStore.gpVerifyLogin("alice", "hunter2!", GP_STORE_PATH),
		"the right password must verify through the store")
	gpCheck(not GPCredentialStore.gpVerifyLogin("alice", "wrong!", GP_STORE_PATH),
		"a wrong password must fail through the store")
	gpEq(str(GPCredentialStore.gpUserRecord("alice", GP_STORE_PATH).get("display_name", "")),
		"Alice Chen", "the display name must survive the round-trip")
	gpCheck(GPCredentialStore.gpSetDisplayName("alice", "Alice C.", GP_STORE_PATH),
		"updating the display name must succeed")
	gpEq(str(GPCredentialStore.gpUserRecord("alice", GP_STORE_PATH).get("display_name", "")),
		"Alice C.", "the display-name update must persist")
	gpCheck(GPCredentialStore.gpRemoveUser("alice", GP_STORE_PATH), "removing alice must succeed")
	gpCheck(not GPCredentialStore.gpHasUser("alice", GP_STORE_PATH),
		"alice must be gone after removal")
	_gpCleanup()


# A corrupt store degrades to fresh (never crashes the login path).
# 损坏的库降级为全新（登录路径永不崩溃）。
func gpTestCorruptStoreDegrades() -> void:
	_gpCleanup()
	var gpAbs: String = ProjectSettings.globalize_path(GP_STORE_PATH)
	var gpF: FileAccess = FileAccess.open(gpAbs, FileAccess.WRITE)
	gpF.store_string("{ corrupt json")
	gpF.close()
	gpCheck(not GPCredentialStore.gpHasUser("bob", GP_STORE_PATH),
		"a corrupt store must degrade to fresh, not crash")
	_gpCleanup()


# Credentials NEVER enter the project archive: write an archive and grep its text — the
# D4 guarantee the whole model rests on.
# 凭据**绝不**进工程存档：写出存档并检查其文本 —— 这是整个模型立足的 D4 保证。
func gpTestCredentialsNeverInArchive() -> void:
	_gpCleanup()
	GPCredentialStore.gpSetCredential("carol", "secret-pw", "", GP_STORE_PATH)
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-101", Vector2(10, 20)))
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpGraph = gpG
	gpEq(GPProjectIO.gpWriteSheets([gpSheet], GP_ARCHIVE_PATH, []), OK,
		"the archive write must succeed")
	var gpText: String = FileAccess.get_file_as_string(GP_ARCHIVE_PATH)
	gpCheck(not gpText.contains("secret-pw"), "the archive must not carry the password")
	gpCheck(not gpText.contains("credentials.json"), "the archive must not reference the store")
	_gpCleanup()


# ============================ member roster (io) ============================
# ============================ 成员名单（io） ============================

# Add / duplicate / bad-roles / set-enabled / set-roles / remove, all pure.
# 添加 / 重复 / 非法角色 / 启停 / 改角色 / 移除，全部纯函数。
func gpTestRosterCrud() -> void:
	var gpMembers: Array = []
	gpCheck(bool(GPCMemberRoster.gpAdd(gpMembers, "alice", ["manager"]).get("ok", false)),
		"adding alice as manager must succeed")
	gpCheck(not bool(GPCMemberRoster.gpAdd(gpMembers, "alice", ["designer"]).get("ok", false)),
		"a duplicate user must be rejected")
	gpEq(str(GPCMemberRoster.gpAdd(gpMembers, "alice", ["designer"]).get("code", "")),
		GPCMemberRoster.GP_ERR_DUPLICATE, "the duplicate must carry its machine code")
	gpCheck(not bool(GPCMemberRoster.gpAdd(gpMembers, "bob", []).get("ok", false)),
		"an empty role set must be rejected")
	gpCheck(not bool(GPCMemberRoster.gpAdd(gpMembers, "bob", ["admin"]).get("ok", false)),
		"an out-of-vocabulary role must be rejected")
	gpCheck(not bool(GPCMemberRoster.gpAdd(gpMembers, "  ", ["designer"]).get("ok", false)),
		"a blank username must be rejected")
	gpCheck(bool(GPCMemberRoster.gpAdd(gpMembers, "bob", ["designer", "reviewer"]).get("ok", false)),
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
