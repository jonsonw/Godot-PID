class_name GPLoginRemember
extends RefCounted
# Copyright © 2026 Jonson Wang
# v1.3.3 machine-local "skip sign-in for 24 hours" tokens (user request 2026-11-19):
# after a successful login WITH the remember box ticked, this machine records WHICH user
# logged into WHICH archive and WHEN — nothing else. The PASSWORD IS NEVER STORED; the
# token only skips the re-entry within its window on THIS machine (user:// is per-OS-user
# per-machine). Every project open still runs the full credential gate unless a VALID
# token exists (within GP_WINDOW_SECONDS, user still enabled).
# v1.3.3 本机「24 小时免登录」令牌（用户要求 2026-11-19）：勾选记住后，本机记录
# 「哪个用户在何时登录了哪个工程」—— 仅此而已。**密码绝不存储**；令牌只在本机、
# 只在窗口期内跳过重输（user:// 随操作系统用户与机器隔离）。每次打开工程仍走完整
# 凭据门，除非存在**有效**令牌（窗口期内且该用户仍启用）。
#
# Honesty boundary / 如实边界：this is convenience, NOT security — whoever controls the
# machine within the window enters as the remembered user. Same trust level as a browser
# cookie; expiry is enforced by wall-clock comparison, never by trust.
# 这是便利性而非安全性 —— 窗口期内控制本机者将以被记住的用户进入。与浏览器 cookie
# 同一信任等级；过期由时钟比对强制，绝无豁免。
#
# Storage is io-layer atomic write (ADR-2: the only FileAccess blades live in src/io).
# 存储走 io 层原子写（ADR-2：FileAccess 只出现在 src/io）。

# Machine-local store. / 本机存储路径。
const GP_STORE_PATH: String = "user://login_remember.json"

# The skip window: 24 hours, frozen. / 免输窗口：24 小时，冻结。
const GP_WINDOW_SECONDS: float = 86400.0


# Return the remembered user for this archive, or "" (absent / expired / malformed).
# Expired entries are pruned on read. gpNow is injected so tests stay deterministic.
# 返回该工程被记住的用户，否则 ""（无记录 / 已过期 / 形状不对）。读取时顺手清理过期
# 条目。gpNow 由调用方注入，测试保持确定性。
static func gpGet(gpArchivePath: String, gpNow: float, gpStorePath: String = GP_STORE_PATH) -> String:
	if gpArchivePath == "" or not FileAccess.file_exists(gpStorePath):
		return ""
	var gpHeader: GPIOResult = GPAtomicFile.gpReadJsonDict(gpStorePath)
	if not gpHeader.gpIsOk():
		return ""
	var gpData: Variant = gpHeader.gpPayload
	if not (gpData is Dictionary):
		return ""
	var gpEntries: Variant = (gpData as Dictionary).get("entries", null)
	if not (gpEntries is Dictionary):
		return ""
	var gpUser: String = ""
	var gpChanged: bool = false
	for gpKey in (gpEntries as Dictionary).keys():
		var gpEntry: Variant = (gpEntries as Dictionary)[gpKey]
		if not (gpEntry is Dictionary):
			continue
		var gpAt: float = float((gpEntry as Dictionary).get("at", -1.0))
		if gpNow - gpAt >= GP_WINDOW_SECONDS or gpAt > gpNow:
			(gpEntries as Dictionary).erase(gpKey)
			gpChanged = true
			continue
		if gpKey == gpArchivePath:
			gpUser = str((gpEntry as Dictionary).get("user", ""))
	if gpChanged:
		GPAtomicFile.gpWriteJsonAtomic(gpStorePath, gpData)
	return gpUser


# Record a successful login (remember box ticked). Writes only user + timestamp.
# 记录一次勾选了记住的成功登录。只写用户名 + 时间戳。
static func gpPut(gpArchivePath: String, gpUser: String, gpNow: float,
		gpStorePath: String = GP_STORE_PATH) -> bool:
	if gpArchivePath == "" or gpUser == "":
		return false
	var gpData: Dictionary = {}
	if FileAccess.file_exists(gpStorePath):
		var gpRaw: GPIOResult = GPAtomicFile.gpReadJsonDict(gpStorePath)
		if gpRaw.gpIsOk() and (gpRaw.gpPayload is Dictionary):
			gpData = gpRaw.gpPayload as Dictionary
	var gpEntries: Dictionary = {}
	var gpRawEntries: Variant = gpData.get("entries", null)
	if gpRawEntries is Dictionary:
		gpEntries = gpRawEntries as Dictionary
	gpEntries[gpArchivePath] = {"user": gpUser, "at": gpNow}
	gpData["entries"] = gpEntries
	return GPAtomicFile.gpWriteJsonAtomic(gpStorePath, gpData).gpIsOk()


# Drop ONE archive's token (e.g. the roster changed under it). Never fatal.
# 删除单个工程的令牌（如其名单发生变更时）。绝不致命。
static func gpDrop(gpArchivePath: String, gpStorePath: String = GP_STORE_PATH) -> void:
	if gpArchivePath == "" or not FileAccess.file_exists(gpStorePath):
		return
	var gpRaw: GPIOResult = GPAtomicFile.gpReadJsonDict(gpStorePath)
	if not gpRaw.gpIsOk() or not (gpRaw.gpPayload is Dictionary):
		return
	var gpData: Dictionary = gpRaw.gpPayload as Dictionary
	var gpEntries: Variant = gpData.get("entries", null)
	if gpEntries is Dictionary and (gpEntries as Dictionary).has(gpArchivePath):
		(gpEntries as Dictionary).erase(gpArchivePath)
		GPAtomicFile.gpWriteJsonAtomic(gpStorePath, gpData)
