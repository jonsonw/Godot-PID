class_name GPProjectIO
extends RefCounted

# Single source of truth for *.pid.json project loading/saving mechanics.
# *.pid.json 工程读写机制的单一事实来源。
# This is a pure filesystem/serialization helper: it knows nothing about the UI, the
# active canvas, the dock panels, or status messages. Those concerns stay in MainScene.
# 这是纯文件系统 / 序列化助手：它不感知 UI、活动画布、停靠面板或状态栏信息——这些关注点
# 留在主场景。数据主权（自包含文件）在「写入前由调用方把用户图元包嵌入图」这一约定下保持，
# 因为内嵌逻辑属于模型层（GPPIDGraph.gpEmbedUserPacks），而非文件 I/O 本身。
# See docs/架构评审_2026-09-04.md P3 (拆离工程 IO).
# 见「架构评审」P3（拆离工程 IO）。


# Force the canonical .pid.json extension on a raw path so the file is recognised on reopen.
# 给原始路径强制加上规范的 .pid.json 扩展名，便于重新打开时识别。
# Returns a NEW string (does not mutate the argument), so callers keep their raw path intact.
# 返回「新字符串」（不修改入参），调用方可保留原始路径。
static func gpEnsurePidExt(gpPath: String) -> String:
	if gpPath.ends_with(".pid.json"):
		return gpPath
	return gpPath + ".pid.json"


# Serialize gpGraph and write it to disk. The .pid.json extension is enforced automatically.
# 序列化 gpGraph 并写入磁盘；.pid.json 扩展名会被自动强制。
# Returns OK on success, or a FileAccess error code when the file cannot be opened for writing.
# 成功返回 OK，无法打开写文件时返回 FileAccess 错误码。
static func gpWriteProject(gpGraph: GPPIDGraph, gpPath: String) -> int:
	var gpFilePath: String = gpEnsurePidExt(gpPath)
	# The caller is expected to have embedded any user symbol packs already (via
	# GPPIDGraph.gpEmbedUserPacks), because gpToDict() serializes them verbatim.
	# 调用方应已先行内嵌用户图元包（经 GPPIDGraph.gpEmbedUserPacks），因为 gpToDict() 会原样序列化之。
	# ATOMIC WRITE (ADR-4): the text is built and verified in a temp file, then renamed over
	# the target. Writing straight into the target (the old behaviour) left a truncated,
	# unparseable archive whenever the process died mid-write. The previous good copy is kept
	# as <path>.bak so a bad save still has a fallback.
	# 原子写（ADR-4）：文本先在临时文件中构造并校验，再 rename 覆盖目标。
	# 直接写目标（旧行为）在进程写入途中死亡时会留下被截断、无法解析的存档。
	# 上一份完好副本保留为 <path>.bak，使一次失败的保存仍有退路。
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(gpFilePath, gpGraph.gpToDict())
	if not gpWrite.gpIsOk():
		return FAILED
	return OK


# Result-typed variant of gpWriteProject: reports WHY a write failed instead of a bare int.
# gpWriteProject 的结果类型版本：说明写入「为何」失败，而非仅返回裸 int。
# The legacy int API is preserved verbatim and reused, so no existing caller changes.
# 旧 int API 原样保留并被复用，故既有调用方无需改动。
static func gpWriteProjectResult(gpGraph: GPPIDGraph, gpPath: String) -> GPIOResult:
	var gpFilePath: String = gpEnsurePidExt(gpPath)
	var gpErr: int = gpWriteProject(gpGraph, gpPath)
	if gpErr != OK:
		return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpFilePath)
	return GPIOResult.gpSuccess("io.saved", gpFilePath)


# Read and reconstruct a project graph from gpPath. Returns null on any failure
# (missing file, malformed JSON, or a non-dictionary root).
# 从 gpPath 读取并重建工程图。任意失败（文件缺失、JSON 损坏、根非字典）均返回 null。
# NOTE: GPPIDGraph.gpFromDict() reconciles the embedded user packs back into the live
# symbol library, so custom symbols are available again after reopening — that side effect
# is part of "load project" semantics and lives on the model, not here.
# 注意：GPPIDGraph.gpFromDict() 会把内嵌用户图元包调和回活动图元库，使重新打开后自定义图元
# 再次可用——该副作用属于「载入工程」语义、位于模型层，而非本模块。
static func gpReadProject(gpPath: String) -> GPPIDGraph:
	# Delegated to GPAtomicFile so every archive read shares one failure taxonomy
	# (io.open_failed vs io.parse_failed) and one place to add BOM / encoding handling later.
	# 委派给 GPAtomicFile，使所有存档读取共用一套失败分类
	# （io.open_failed 与 io.parse_failed）与一处将来加 BOM / 编码处理的地方。
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
	if not gpRead.gpIsOk():
		return null
	return GPPIDGraph.gpFromDict(gpRead.gpPayload as Dictionary)


# Write a MULTI-SHEET project as a v3 container.
# 把**多图纸**工程写成 v3 容器。
# Single-sheet projects keep using gpWriteProject: it leaves the file in the v2 shape, which
# means every archive written before this feature stays byte-stable. Only a project that
# actually HAS several sheets is upgraded (see 持久化实现方案 §6.3).
# 单图纸工程继续使用 gpWriteProject：它让文件保持 v2 形态，
# 意味着本功能之前写出的每个存档都保持字节稳定。只有**确实**有多张图纸的工程才升格。
# Project-level data (meta / tag_rules / embedded packs) is taken from the FIRST sheet's
# graph, because that is where GPPIDGraph keeps it today.
# 工程级数据（meta / tag_rules / 内嵌图元包）取自**第一张**图纸的图，
# 因为 GPPIDGraph 目前就是把它存在那里的。
static func gpWriteSheets(gpSheets: Array, gpPath: String) -> int:
	if gpSheets.is_empty():
		return FAILED
	var gpFilePath: String = gpEnsurePidExt(gpPath)
	var gpFirst: GPSheet = gpSheets[0] as GPSheet
	var gpBase: Dictionary = {}
	if gpFirst != null and gpFirst.gpGraph != null:
		gpBase = gpFirst.gpGraph.gpToDict()
	var gpOut: Dictionary = GPSchemaMigrate.gpMigrate(gpBase)
	var gpSheetsOut: Array = []
	var gpI: int = 0
	for gpS in gpSheets:
		var gpSheet: GPSheet = gpS as GPSheet
		if gpSheet == null:
			continue
		var gpD: Dictionary = gpSheet.gpToDict()
		# Re-derive the index: a stale index survives a reordered tab bar and would put two
		# sheets in the same slot.
		# 重新推导 index：过期的 index 会在标签重排后存活，导致两张图纸落进同一个位置。
		gpD["index"] = gpI
		gpSheetsOut.append(gpD)
		gpI += 1
	if gpSheetsOut.is_empty():
		return FAILED
	gpOut["sheets"] = gpSheetsOut
	gpOut["kind"] = GPSchemaMigrate.GP_KIND_PROJECT
	gpOut["meta"]["sheets"] = gpSheetsOut.size()
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(gpFilePath, gpOut)
	if not gpWrite.gpIsOk():
		return FAILED
	return OK


# Result-typed variant of gpWriteSheets. / gpWriteSheets 的结果类型版本。
static func gpWriteSheetsResult(gpSheets: Array, gpPath: String) -> GPIOResult:
	var gpErr: int = gpWriteSheets(gpSheets, gpPath)
	if gpErr != OK:
		return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpPath)
	return GPIOResult.gpSuccess("io.saved", gpPath)


# Read a project as a list of sheets. Works for v1/v2/v3 alike: a single-sheet archive
# comes back as a ONE-element array, so callers need no special case.
# 把工程读成图纸列表。对 v1/v2/v3 一视同仁：单图纸存档返回**单元素**数组，
# 故调用方无需特例分支。
static func gpReadSheets(gpPath: String) -> GPIOResult:
	var gpRead: GPIOResult = GPProjectImport.gpReadArchive(gpPath)
	if not gpRead.gpIsOk():
		return gpRead
	var gpV3: Dictionary = gpRead.gpPayload as Dictionary
	if gpV3.is_empty():
		return GPIOResult.gpSuccessWith([GPSheet.gpNew("sheet-1", "", 0)], "io.loaded", gpPath)
	var gpSheetsOut: Array = []
	var gpI: int = 0
	for gpS in (gpV3.get("sheets", []) as Array):
		var gpD: Dictionary = (gpS as Dictionary).duplicate(true)
		gpD["index"] = gpI
		# Project-level data is copied onto every sheet so the graph rebuild can reconcile
		# embedded packs and numbering rules regardless of which tab is opened first.
		# 工程级数据复制到每张图纸上，使无论先打开哪一页，
		# 图重建都能调和内嵌图元包与编号规则。
		gpD["meta"] = (gpV3.get("meta", {}) as Dictionary).duplicate(true)
		gpD["user_symbol_packs"] = ((gpV3.get("library", {}) as Dictionary).get(
			"packs", []) as Array).duplicate(true)
		if gpV3.has("tag_rules"):
			gpD["tag_rules"] = (gpV3.get("tag_rules", {}) as Dictionary).duplicate(true)
		gpSheetsOut.append(GPSheet.gpFromDict(gpD))
		gpI += 1
	if gpSheetsOut.is_empty():
		gpSheetsOut.append(GPSheet.gpNew("sheet-1", str((gpV3.get("meta", {})
			as Dictionary).get("title", "")), 0))
	return GPIOResult.gpSuccessWith(gpSheetsOut, "io.loaded", gpPath)


# Result-typed variant of gpReadProject: distinguishes "file missing/unreadable" from
# "malformed JSON" and returns the reconstructed graph in gpPayload on success.
# gpReadProject 的结果类型版本：区分「文件缺失/不可读」与「JSON 损坏」，
# 并在成功时把重建出的图放入 gpPayload。
# The legacy GPPIDGraph API is preserved and reused, so no existing caller changes.
# 旧 GPPIDGraph API 原样保留并被复用，故既有调用方无需改动。
static func gpReadProjectResult(gpPath: String) -> GPIOResult:
	if not FileAccess.file_exists(gpPath):
		return GPIOResult.gpFailure("io.open_failed", "status.load_fail", gpPath)
	var gpGraph: GPPIDGraph = gpReadProject(gpPath)
	if gpGraph == null:
		return GPIOResult.gpFailure("io.parse_failed", "status.load_fail", gpPath)
	return GPIOResult.gpSuccessWith(gpGraph, "io.loaded", gpPath)
