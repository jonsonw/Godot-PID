class_name GPAtomicFile
extends RefCounted

# Crash-safe file writing for *.pid.json and every other JSON archive.
# *.pid.json 及其他 JSON 存档的崩溃安全写入。
# WHY THIS EXISTS / 为何存在：
# writing straight into the target path (FileAccess.open(WRITE) + store_string) leaves a
# TRUNCATED file whenever the process dies mid-write — power loss, a crash, a force quit.
# The archive is then unparseable and the drawing is gone. The only reliable fix is to never
# write in place: build a complete temporary file, then rename it over the target. rename()
# within one filesystem is atomic, so at every instant the target path holds either the old
# complete file or the new complete file — never a half-written one.
# 直接写目标路径（FileAccess.open(WRITE) + store_string）在写入途中进程死亡时会留下
# **被截断的文件** —— 断电、崩溃、强制退出皆然。存档随即无法解析，图纸就此丢失。
# 唯一可靠的修正是「绝不原地写」：先写出一个完整的临时文件，再 rename 覆盖目标。
# 同一文件系统内的 rename() 是原子的，因而目标路径在任意时刻都持有「旧的完整文件」
# 或「新的完整文件」，绝不可能是写了一半的东西。
#
# LAYER RULE / 分层约束：this is the ONLY place allowed to touch FileAccess / DirAccess for
# archives. Everything above it (GPProjectIO, export, session services) talks in GPIOResult.
# 本类是唯一被允许为存档触碰 FileAccess / DirAccess 的地方。其上的一切
# （GPProjectIO、导出、会话服务）一律用 GPIOResult 交流。
# See 架构/交付/持久化实现方案_2026-09-11.md §5.3 and ADR-4.
# 见「持久化实现方案」§5.3 与 ADR-4。


# Suffix for the in-progress temporary file.
# 进行中的临时文件后缀。
const GP_TMP_SUFFIX: String = ".tmp"

# Suffix for the previous good copy.
# 上一份完好副本的后缀。
const GP_BAK_SUFFIX: String = ".bak"

# Keep the previous good copy after a successful write. Losing it means a bad-but-parseable
# save has no fallback; keeping it costs one extra file next to the archive.
# 写入成功后保留上一份完好副本。丢掉它意味着「写坏但能解析」的存档没有退路；
# 保留它的代价只是存档旁多一个文件。
const GP_KEEP_BACKUP: bool = true


# Write text atomically: tmp -> verify -> (bak) -> rename over the target.
# 原子写入文本：tmp -> 校验 ->（bak）-> rename 覆盖目标。
# On ANY failure the target is left untouched (or restored from .bak) and the temp file is
# removed, so a failed save can never destroy an existing archive.
# 任何失败下目标都保持原样（或由 .bak 复原）且临时文件被清除，故失败的保存
# 永不损毁既有存档。
# Returns GPIOResult with gpDetail = the final path on success, the failing path on failure.
# 返回 GPIOResult：成功时 gpDetail 为最终路径，失败时为出错的路径。
static func gpWriteAtomic(gpPath: String, gpText: String) -> GPIOResult:
	if gpPath == "":
		return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpPath)
	var gpTmpPath: String = gpPath + GP_TMP_SUFFIX
	var gpBakPath: String = gpPath + GP_BAK_SUFFIX

	# ---- 1) build the complete temporary file / 写出完整的临时文件 ----
	var gpOut: FileAccess = FileAccess.open(gpTmpPath, FileAccess.WRITE)
	if gpOut == null:
		return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpTmpPath)
	gpOut.store_string(gpText)
	gpOut.flush()
	var gpWriteErr: int = gpOut.get_error()
	gpOut.close()
	if gpWriteErr != OK:
		_gpRemoveFile(gpTmpPath)
		return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpTmpPath)

	# ---- 2) verify the temp file is complete (catches a full disk / quota) ----
	# ---- 2) 校验临时文件完整（可抓住磁盘满 / 配额超限）----
	# A partial write is the silent killer: store_string reports no error on a full disk
	# until the flush fails, so compare the byte count actually on disk against the payload.
	# 部分写入是静默杀手：磁盘满时 store_string 在 flush 失败前并不报错，
	# 故需把磁盘上的实际字节数与载荷比对。
	var gpWantBytes: int = gpText.to_utf8_buffer().size()
	var gpGotBytes: int = _gpFileSize(gpTmpPath)
	if gpGotBytes != gpWantBytes:
		_gpRemoveFile(gpTmpPath)
		return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpTmpPath)

	# ---- 3) move the old file aside / 把旧文件挪到一旁 ----
	var gpHadTarget: bool = FileAccess.file_exists(gpPath)
	if gpHadTarget:
		_gpRemoveFile(gpBakPath)
		if DirAccess.rename_absolute(gpPath, gpBakPath) != OK:
			_gpRemoveFile(gpTmpPath)
			return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpBakPath)

	# ---- 4) rename the temp file into place (the atomic step) ----
	# ---- 4) 把临时文件 rename 到位（原子那一步）----
	if DirAccess.rename_absolute(gpTmpPath, gpPath) != OK:
		# Roll back: put the old file back, then drop the temp file.
		# 回滚：先把旧文件放回去，再删掉临时文件。
		if gpHadTarget and FileAccess.file_exists(gpBakPath):
			DirAccess.rename_absolute(gpBakPath, gpPath)
		_gpRemoveFile(gpTmpPath)
		return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpTmpPath)

	# ---- 5) tidy up / 收尾 ----
	if not GP_KEEP_BACKUP:
		_gpRemoveFile(gpBakPath)
	return GPIOResult.gpSuccess("io.saved", gpPath)


# Serialize a dictionary and write it atomically, verifying the text round-trips BEFORE it
# touches the target. This is the guard that keeps a malformed payload (e.g. NaN, which JSON
# cannot represent) from ever reaching disk as an unparseable archive.
# 序列化一个字典并原子写入，在触碰目标**之前**校验文本可否往返解析。
# 正是这道护栏使畸形载荷（如 JSON 无法表示的 NaN）永远不会以不可解析存档的形式落到磁盘上。
static func gpWriteJsonAtomic(gpPath: String, gpData: Dictionary) -> GPIOResult:
	var gpText: String = JSON.stringify(gpData, "", true)
	var gpCheck: Variant = JSON.parse_string(gpText)
	if gpCheck == null or not (gpCheck is Dictionary):
		return GPIOResult.gpFailure("io.serialize_failed", "status.save_fail", gpPath)
	return gpWriteAtomic(gpPath, gpText)


# Read a whole text file. Distinguishes "missing" from "unreadable" in gpCode.
# 读取整个文本文件。用 gpCode 区分「缺失」与「不可读」。
static func gpReadText(gpPath: String) -> GPIOResult:
	if not FileAccess.file_exists(gpPath):
		return GPIOResult.gpFailure("io.open_failed", "status.load_fail", gpPath)
	var gpIn: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpIn == null:
		return GPIOResult.gpFailure("io.open_failed", "status.load_fail", gpPath)
	var gpText: String = gpIn.get_as_text()
	gpIn.close()
	return GPIOResult.gpSuccessWith(gpText, "io.loaded", gpPath)


# Read and parse a JSON file whose root must be a Dictionary.
# 读取并解析一个根节点必须为字典的 JSON 文件。
# Failure codes: io.open_failed (missing/unreadable) vs io.parse_failed (malformed).
# 失败码：io.open_failed（缺失/不可读）与 io.parse_failed（损坏）。
static func gpReadJsonDict(gpPath: String) -> GPIOResult:
	var gpRead: GPIOResult = gpReadText(gpPath)
	if not gpRead.gpIsOk():
		return gpRead
	var gpParsed: Variant = JSON.parse_string(gpRead.gpPayload as String)
	if gpParsed == null or not (gpParsed is Dictionary):
		return GPIOResult.gpFailure("io.parse_failed", "status.load_fail", gpPath)
	return GPIOResult.gpSuccessWith(gpParsed, "io.loaded", gpPath)


# True when a crash left an unfinished temp file behind — the signal that the last save
# never completed and the target is still the previous good copy.
# 崩溃是否留下了未完成的临时文件 —— 这是「上次保存从未完成、目标仍是上一份完好副本」的信号。
static func gpHasTempRemains(gpPath: String) -> bool:
	return FileAccess.file_exists(gpPath + GP_TMP_SUFFIX)


# Path of the backup that sits next to an archive ("" when the constant changes shape).
# 存档旁的备份路径。
static func gpBackupPath(gpPath: String) -> String:
	return gpPath + GP_BAK_SUFFIX


# Discard a leftover temp file. Called on startup after a crash was detected.
# 清掉残留的临时文件。检测到崩溃后于启动时调用。
static func gpDiscardTempRemains(gpPath: String) -> void:
	_gpRemoveFile(gpPath + GP_TMP_SUFFIX)


# File size in bytes; -1 when it cannot be opened.
# 文件字节数；打不开时为 -1。
static func _gpFileSize(gpPath: String) -> int:
	var gpIn: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpIn == null:
		return -1
	var gpLen: int = gpIn.get_length()
	gpIn.close()
	return gpLen


# Delete a file when present. Never fatal: a cleanup failure must not fail a save.
# 文件存在则删除。绝不致命：清理失败不应让保存失败。
static func _gpRemoveFile(gpPath: String) -> void:
	if FileAccess.file_exists(gpPath):
		DirAccess.remove_absolute(gpPath)
