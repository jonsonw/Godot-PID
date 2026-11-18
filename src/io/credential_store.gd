class_name GPCredentialStore
extends RefCounted
# Copyright © 2026 Jonson Wang
# Local credential store for user identity (ADR-40 D4; W14). THE one place credentials live.
# 用户身份的本机凭据库（ADR-40 D4；W14）。凭据**唯一**的存放之处。
#
# WHY user:// / 为何在 user://：
# Credentials (salt + hash) live on EACH user's own machine; the shared project file never
# carries them, so a leaked share exposes no offline-crackable material (D4's core trade:
# switching machines means re-registering — accepted and documented).
# 凭据（盐 + 哈希）存于**每个用户自己的机器**；共享的工程文件绝不携带它们，
# 故共享盘泄露不暴露任何可离线爆破的材料（D4 的核心取舍：换机需重新登记 ——
# 已接受并写进文档）。
#
# SHAPE / 形态：{"version": 1, "users": { "<user>": {salt, hash, iterations, display_name,
# created_at, updated_at} }}. Corrupt / missing files degrade to a fresh empty store.
# 损坏 / 缺失的文件降级为全新的空库。
#
# LAYER RULE / 分层约束：the ONLY FileAccess use here routes through GPAtomicFile (ADR-4
# atomic write — a half-written credential store must never exist). Pure-dict static API;
# every function takes an optional path so tests stay isolated from the real store.
# 此处对 FileAccess 的唯一使用经 GPAtomicFile（ADR-4 原子写 —— 凭据库绝不能出现写一半的
# 状态）。纯 dict 静态 API；每个函数都带可选路径参数，使测试与真实库隔离。

const GP_STORE_PATH: String = "user://credentials.json"
const GP_FORMAT_VERSION: int = 1


# Load the store (missing / corrupt -> fresh empty store).
# 读取库（缺失 / 损坏 -> 全新空库）。
static func gpLoad(gpPath: String = GP_STORE_PATH) -> Dictionary:
	if not FileAccess.file_exists(gpPath):
		return _gpFresh()
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
	if not gpRead.gpIsOk():
		return _gpFresh()
	var gpDict: Dictionary = gpRead.gpPayload as Dictionary
	if not (gpDict.get("users") is Dictionary):
		return _gpFresh()
	return gpDict


# Persist the store atomically. / 原子持久化库。
static func gpSave(gpStore: Dictionary, gpPath: String = GP_STORE_PATH) -> bool:
	if not (gpStore.get("users") is Dictionary):
		return false
	gpStore["version"] = GP_FORMAT_VERSION
	return GPAtomicFile.gpWriteJsonAtomic(gpPath, gpStore).gpIsOk()


# Does this user have a LOCAL credential here? (Roster membership lives in the project
# file; this only answers "can this user log in on this machine".)
# 该用户在本机是否有凭据？（在册名单在工程文件里；这里只回答「本机能否登录」。）
static func gpHasUser(gpUser: String, gpPath: String = GP_STORE_PATH) -> bool:
	return gpUserRecord(gpUser, gpPath).has("hash")


# One user's record ({} when absent). / 单个用户的记录（缺失时为空字典）。
static func gpUserRecord(gpUser: String, gpPath: String = GP_STORE_PATH) -> Dictionary:
	var gpUsers: Dictionary = (gpLoad(gpPath).get("users", {}) as Dictionary)
	var gpRaw: Variant = gpUsers.get(gpUser, null)
	return (gpRaw as Dictionary).duplicate(true) if (gpRaw is Dictionary) else {}


# Create / replace a user's credential. / 创建 / 替换用户凭据。
static func gpSetCredential(gpUser: String, gpPassword: String, gpDisplayName: String = "",
		gpPath: String = GP_STORE_PATH) -> bool:
	if gpUser.strip_edges() == "" or not GPIdentityCredentials.gpIsValidPassword(gpPassword):
		return false
	var gpStore: Dictionary = gpLoad(gpPath)
	var gpUsers: Dictionary = gpStore.get("users", {}) as Dictionary
	var gpOld: Dictionary = {}
	var gpRaw: Variant = gpUsers.get(gpUser, null)
	if gpRaw is Dictionary:
		gpOld = gpRaw as Dictionary
	var gpNow: String = Time.get_datetime_string_from_system()
	var gpSalt: String = str(gpOld.get("salt", ""))
	if gpSalt == "":
		gpSalt = GPIdentityCredentials.gpNewSalt()
	gpUsers[gpUser] = {
		"salt": gpSalt,
		"hash": GPIdentityCredentials.gpHashPassword(gpPassword, gpSalt),
		"iterations": GPIdentityCredentials.GP_ITERATIONS,
		"display_name": gpDisplayName,
		"created_at": str(gpOld.get("created_at", gpNow)),
		"updated_at": gpNow,
	}
	return gpSave(gpStore, gpPath)


# Verify a login attempt. / 校验一次登录尝试。
static func gpVerifyLogin(gpUser: String, gpPassword: String, gpPath: String = GP_STORE_PATH) -> bool:
	var gpRec: Dictionary = gpUserRecord(gpUser, gpPath)
	if gpRec.is_empty():
		return false
	return GPIdentityCredentials.gpVerify(gpPassword, str(gpRec.get("salt", "")),
		str(gpRec.get("hash", "")))


# Update the display name only. / 仅更新显示名。
static func gpSetDisplayName(gpUser: String, gpDisplayName: String, gpPath: String = GP_STORE_PATH) -> bool:
	var gpRec: Dictionary = gpUserRecord(gpUser, gpPath)
	if gpRec.is_empty():
		return false
	gpRec["display_name"] = gpDisplayName
	var gpStore: Dictionary = gpLoad(gpPath)
	var gpUsers: Dictionary = gpStore.get("users", {}) as Dictionary
	gpUsers[gpUser] = gpRec
	return gpSave(gpStore, gpPath)


# Remove a local credential (the "reset my password on this machine" blade — the roster
# entry in the project file is untouched).
# 删除本机凭据（「在本机重设密码」的那把刀 —— 工程文件里的在册条目不受影响）。
static func gpRemoveUser(gpUser: String, gpPath: String = GP_STORE_PATH) -> bool:
	var gpStore: Dictionary = gpLoad(gpPath)
	var gpUsers: Dictionary = gpStore.get("users", {}) as Dictionary
	if not gpUsers.has(gpUser):
		return true
	gpUsers.erase(gpUser)
	return gpSave(gpStore, gpPath)


# A brand-new empty store. / 全新的空库。
static func _gpFresh() -> Dictionary:
	return {"version": GP_FORMAT_VERSION, "users": {}}
