class_name GPProjectImport
extends RefCounted

# Read any G-PID archive (v1/v2/v3) and merge it into a live graph NON-DESTRUCTIVELY.
# 读取任意 G-PID 存档（v1/v2/v3）并以**非破坏**方式合并进活动图。
#
# THE ONE INVARIANT / 唯一不变式：
# a default import never DECREASES the data already in the target. Conflicts are resolved by
# deriving new identities for the INCOMING side, never by overwriting the existing one. A
# P&ID is an engineering deliverable — one accidental overwrite can erase a tag the site
# already signed off on (ADR-6).
# 默认导入**永不减少**目标中已有的数据。冲突通过为**导入方**派生新标识来解决，
# 绝不覆盖既有内容。P&ID 是工程交付物 —— 一次误覆盖就可能抹掉现场已确认的位号（ADR-6）。
# "replace" exists, but only when the caller asks for it by name.
# "replace" 模式存在，但仅在调用方显式指名时生效。
# See 持久化实现方案 §9 (导入流程) / 见「持久化实现方案」§9。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

const GP_MODE_MERGE: String = "merge"
const GP_MODE_REPLACE: String = "replace"

# Suffix appended to a colliding tag. Deliberately visible: a silent renumber would hide
# the fact that two devices now share a function.
# 冲突位号追加的后缀。刻意做成显眼：静默重编号会掩盖「两个设备现在功能重复」这一事实。
const GP_DUP_SUFFIX: String = "-dup"


# Read + identify + migrate. Returns the v3 container in gpPayload.
# 读取 + 识别 + 迁移。gpPayload 中为 v3 容器。
# Failure codes: io.open_failed / io.parse_failed / io.unknown_format / io.future_version.
# 失败码：io.open_failed / io.parse_failed / io.unknown_format / io.future_version。
static func gpReadArchive(gpPath: String) -> GPIOResult:
	if not FileAccess.file_exists(gpPath):
		return GPIOResult.gpFailure("io.open_failed", "status.load_fail", gpPath)
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
	if not gpRead.gpIsOk():
		return gpRead
	var gpRaw: Dictionary = gpRead.gpPayload as Dictionary
	# An empty file is a NEW project, not a corrupt one (E8): the "create" path and the
	# "open" path then share one code route.
	# 空文件是**新工程**而非损坏文件（E8）：于是「新建」与「打开」共用一条代码路径。
	if gpRaw.is_empty():
		return GPIOResult.gpSuccessWith({}, "io.loaded", gpPath)
	if not GPSchemaMigrate.gpIsGPidArchive(gpRaw):
		return GPIOResult.gpFailure("io.unknown_format", "status.import_unknown", gpPath)
	var gpVersion: int = int(gpRaw.get("format_version", GPSchemaMigrate.GP_FORMAT_VERSION))
	if gpVersion > GPSchemaMigrate.GP_MAX_SUPPORTED:
		return GPIOResult.gpFailure("io.future_version", "status.import_future", gpPath)
	return GPIOResult.gpSuccessWith(GPSchemaMigrate.gpMigrate(gpRaw), "io.loaded", gpPath)


# Fill gpReport with every anomaly found. NEVER aborts: entries are kept, not dropped.
# 把发现的每个异常填入 gpReport。永不中断：条目保留而非丢弃。
static func gpValidate(gpV3: Dictionary, gpReport: GPImportReport) -> void:
	var gpSheets: Array = []
	if gpV3.get("sheets") is Array:
		gpSheets = gpV3.get("sheets") as Array
	gpReport.gpStats["sheets"] = gpSheets.size()
	var gpSeenUids: Dictionary = {}
	var gpSeenTags: Dictionary = {}
	var gpIndex: int = 0
	for gpS in gpSheets:
		var gpSheet: Dictionary = gpS as Dictionary
		var gpNodes: Array = []
		if gpSheet.get("nodes") is Array:
			gpNodes = gpSheet.get("nodes") as Array
		for gpN in gpNodes:
			var gpNode: Dictionary = gpN as Dictionary
			gpReport.gpStats["nodes"] = int(gpReport.gpStats.get("nodes", 0)) + 1
			var gpUid: String = str(gpNode.get("uid", ""))
			if gpUid.is_empty():
				gpReport.gpAddError("import.uid_missing", "node#" + str(gpIndex))
			elif gpSeenUids.has(gpUid):
				gpReport.gpAddError("import.uid_duplicate", gpUid)
			else:
				gpSeenUids[gpUid] = true
			var gpTag: String = str(gpNode.get("tag", ""))
			if not gpTag.is_empty():
				if gpSeenTags.has(gpTag):
					gpReport.gpAddWarning("import.tag_duplicate", gpTag)
				else:
					gpSeenTags[gpTag] = true
			# A symbol the current library does not define is kept as-is and drawn as a
			# placeholder — deleting it would be data loss.
			# 当前库未定义的图元原样保留并渲染为占位符 —— 删除它就是数据丢失。
			var gpSymbolId: String = str(gpNode.get("symbol_id", ""))
			if not gpSymbolId.is_empty() and GPSymbolLibrary.gpFindById(gpSymbolId) == null:
				gpReport.gpAddError("import.symbol_missing", gpSymbolId)
			gpIndex += 1
		# Edge ends must resolve; a dangling end is tolerated but reported.
		# 边端点必须可解析；悬空端被容忍但要报告。
		var gpEdges: Array = []
		if gpSheet.get("edges") is Array:
			gpEdges = gpSheet.get("edges") as Array
		for gpE in gpEdges:
			var gpEdge: Dictionary = gpE as Dictionary
			gpReport.gpStats["edges"] = int(gpReport.gpStats.get("edges", 0)) + 1
			for gpSide in ["from_ref", "to_ref"]:
				var gpNodeId: String = gpRefOf(gpEdge, gpSide)
				if gpNodeId.is_empty():
					continue
				if not gpSeenUids.has(gpNodeId):
					gpReport.gpAddError("import.edge_dangling",
						str(gpEdge.get("instance_id", "")) + "/" + gpSide)
			if str(gpEdge.get("instance_id", "")) == "":
				gpReport.gpAddWarning("import.edge_no_id", "")
			var gpFromId: String = gpRefOf(gpEdge, "from_ref")
			var gpToId: String = gpRefOf(gpEdge, "to_ref")
			if not gpFromId.is_empty() and gpFromId == gpToId:
				gpReport.gpAddWarning("import.edge_self_loop",
					str(gpEdge.get("instance_id", "")))
		var gpShapes: Array = []
		if gpSheet.get("shapes") is Array:
			gpShapes = gpSheet.get("shapes") as Array
		gpReport.gpStats["shapes"] = int(gpReport.gpStats.get("shapes", 0)) + gpShapes.size()
	if gpV3.get("library") is Dictionary:
		gpReport.gpStats["packs"] = ((gpV3.get("library") as Dictionary).get("packs", []) as Array).size()


# node_id of one edge side, or "" when absent.
# 边某一侧的 node_id，缺失时为 ""。
static func gpRefOf(gpEdge: Dictionary, gpSide: String) -> String:
	var gpRef: Variant = gpEdge.get(gpSide, null)
	if gpRef is Dictionary:
		return str((gpRef as Dictionary).get("node_id", ""))
	return ""


# Merge gpV3 into gpTarget. Returns GPIOResult with the report in gpPayload.
# 把 gpV3 合并进 gpTarget。返回 GPIOResult，gpPayload 中为报告。
# [param gpMode] "merge" (default, non-destructive) or "replace" (clears the target first).
# [param gpMode] "merge"（默认，非破坏）或 "replace"（先清空目标）。
# [param gpSheetIndex] which sheet to take; -1 merges EVERY sheet (used by P2).
# [param gpSheetIndex] 取哪一页图纸；-1 合并**全部**图纸（P2 使用）。
static func gpMergeInto(gpTarget: GPPIDGraph, gpV3: Dictionary, gpMode: String = GP_MODE_MERGE,
		gpSheetIndex: int = 0) -> GPIOResult:
	var gpReport: GPImportReport = GPImportReport.new()
	if gpTarget == null:
		return GPIOResult.gpFailure("io.apply_failed", "status.import_fail", "")
	if gpV3.is_empty():
		return GPIOResult.gpSuccessWith(gpReport, "status.imported", "")
	gpValidate(gpV3, gpReport)

	if gpMode == GP_MODE_REPLACE:
		gpTarget.gpNodes.clear()
		gpTarget.gpEdges.clear()
		gpTarget.gpShapes.clear()

	# Existing identities the incoming data must not collide with.
	# 导入数据不得与之冲突的既有标识。
	var gpUsedUids: Dictionary = {}
	var gpUsedTags: Dictionary = {}
	for gpN in gpTarget.gpNodes:
		var gpExisting: GPPIDNode = gpN as GPPIDNode
		if not gpExisting.gpUid.is_empty():
			gpUsedUids[gpExisting.gpUid] = true
		if not gpExisting.gpTag.is_empty():
			gpUsedTags[gpExisting.gpTag] = true
	var gpDocId: String = str(gpV3.get("doc_id", ""))
	if gpDocId.is_empty():
		gpDocId = GPIdGen.gpNewDocId()

	# --- 1) symbols: same id + same content -> reuse; same id + different content -> derive
	# --- 1) 图元：id 相同且内容相同 -> 复用；id 相同但内容不同 -> 为导入方派生新 id
	var gpSymbolMap: Dictionary = {}
	var gpNewDefs: Array[GPSymbolDef] = []
	if gpV3.get("library") is Dictionary:
		var gpPacks: Array = ((gpV3.get("library") as Dictionary).get("packs", []) as Array)
		for gpP in gpPacks:
			var gpPack: GPSymbolPack = GPSymbolPack.new()
			gpPack.gpFromDict(gpP as Dictionary)
			for gpSym in gpPack.gpSymbols:
				var gpDef: GPSymbolDef = gpSym as GPSymbolDef
				var gpExistingDef: GPSymbolDef = GPSymbolLibrary.gpFindById(gpDef.gpId)
				if gpExistingDef == null:
					gpNewDefs.append(gpDef)
					gpReport.gpAddInfo("import.symbol_added", gpDef.gpId)
					continue
				if gpFingerprint(gpExistingDef.gpToDict()) == gpFingerprint(gpDef.gpToDict()):
					gpReport.gpAddInfo("import.symbol_reused", gpDef.gpId)
					continue
				# Same identity, different content: the incoming one is re-identified so
				# BOTH survive. Overwriting would silently change existing drawings.
				# 同一标识、不同内容：为导入方重新分配 id，使**两者**都存活。
				# 覆盖会静默改动既有图纸。
				var gpNewId: String = GPSymbolLibrary.gpAllocateCustomId(gpDef.gpCategory)
				gpSymbolMap[gpDef.gpId] = gpNewId
				gpDef.gpId = gpNewId
				gpNewDefs.append(gpDef)
				gpReport.gpAddWarning("import.symbol_renamed",
					str(gpExistingDef.gpId) + " -> " + gpNewId)
	if gpNewDefs.size() > 0:
		GPSymbolLibrary.gpRegisterDefs(gpNewDefs)

	# --- 2) geometry / 几何 ---
	var gpSheets: Array = []
	if gpV3.get("sheets") is Array:
		gpSheets = gpV3.get("sheets") as Array
	if gpSheets.is_empty():
		gpReport.gpAddWarning("import.no_sheet", "")
		return GPIOResult.gpSuccessWith(gpReport, "status.imported", "")
	var gpPick: Array = []
	if gpSheetIndex < 0:
		gpPick = gpSheets
	else:
		gpPick = [gpSheets[clampi(gpSheetIndex, 0, gpSheets.size() - 1)]]

	var gpUidMap: Dictionary = {}
	for gpS in gpPick:
		var gpSheet: Dictionary = gpS as Dictionary
		var gpNodes: Array = []
		if gpSheet.get("nodes") is Array:
			gpNodes = gpSheet.get("nodes") as Array
		for gpN in gpNodes:
			var gpNd: Dictionary = (gpN as Dictionary).duplicate(true)
			var gpOldUid: String = str(gpNd.get("uid", ""))
			var gpNewUid: String = gpOldUid
			if gpNewUid.is_empty() or gpUsedUids.has(gpNewUid):
				gpNewUid = _gpFreshUid(gpDocId, str(gpNd.get("instance_id", "n")), gpUsedUids)
				gpReport.gpAddWarning("import.uid_reassigned", gpOldUid + " -> " + gpNewUid)
			gpUsedUids[gpNewUid] = true
			gpUidMap[gpOldUid] = gpNewUid
			gpNd["uid"] = gpNewUid
			# Symbol remap (only when the id was re-derived above).
			# 图元重映射（仅当上面重新派生了 id 时）。
			var gpSymId: String = str(gpNd.get("symbol_id", ""))
			if gpSymbolMap.has(gpSymId):
				gpNd["symbol_id"] = str(gpSymbolMap[gpSymId])
			# Tag collision: keep the incoming device, rename it, and say so (E27 context).
			# 位号冲突：保留导入的设备、重命名它并明确告知。
			var gpTag: String = str(gpNd.get("tag", ""))
			if not gpTag.is_empty() and gpUsedTags.has(gpTag):
				var gpNewTag: String = gpTag + GP_DUP_SUFFIX
				var gpK: int = 2
				while gpUsedTags.has(gpNewTag):
					gpNewTag = gpTag + GP_DUP_SUFFIX + str(gpK)
					gpK += 1
				gpReport.gpAddWarning("import.tag_renamed", gpTag + " -> " + gpNewTag)
				gpNd["tag"] = gpNewTag
				gpTag = gpNewTag
			if not gpTag.is_empty():
				gpUsedTags[gpTag] = true
			var gpNode: GPPIDNode = GPPIDNode.new()
			gpNode.gpFromDict(gpNd)
			gpTarget.gpAddNode(gpNode)
		# Edges AFTER nodes, so every uid remap is already known.
		# 边在节点**之后**处理，使全部 uid 重映射均已就绪。
		var gpEdges: Array = []
		if gpSheet.get("edges") is Array:
			gpEdges = gpSheet.get("edges") as Array
		for gpE in gpEdges:
			var gpEd: Dictionary = (gpE as Dictionary).duplicate(true)
			gpEd["from_ref"] = _gpRemapRef((gpEd.get("from_ref", {}) as Dictionary).duplicate(),
				gpUidMap, gpReport)
			gpEd["to_ref"] = _gpRemapRef((gpEd.get("to_ref", {}) as Dictionary).duplicate(),
				gpUidMap, gpReport)
			var gpEdge: GPPIDEdge = GPPIDEdge.new()
			gpEdge.gpFromDict(gpEd)
			gpTarget.gpAddEdge(gpEdge)
		var gpShapes: Array = []
		if gpSheet.get("shapes") is Array:
			gpShapes = gpSheet.get("shapes") as Array
		for gpSh in gpShapes:
			var gpShape: GPShape = GPShape.new()
			gpShape.gpFromDict(gpSh as Dictionary)
			gpTarget.gpAddShape(gpShape)
	return GPIOResult.gpSuccessWith(gpReport, "status.imported", "")


# One edge endpoint, with its node_id rewritten through the uid remap.
# 单个边端点，其 node_id 经 uid 重映射改写。
static func _gpRemapRef(gpRef: Dictionary, gpUidMap: Dictionary,
		gpReport: GPImportReport) -> Dictionary:
	var gpNodeId: String = str(gpRef.get("node_id", ""))
	if gpNodeId.is_empty():
		return gpRef
	if gpUidMap.has(gpNodeId):
		gpRef["node_id"] = str(gpUidMap[gpNodeId])
	elif gpReport != null:
		gpReport.gpAddWarning("import.edge_unresolved", gpNodeId)
	return gpRef


# A uid that is unique against everything seen so far.
# 对目前所见一切均唯一的 uid。
static func _gpFreshUid(gpDocId: String, gpInstanceId: String, gpUsed: Dictionary) -> String:
	var gpBase: String = gpDocId + "-" + gpInstanceId
	var gpCandidate: String = gpBase
	var gpK: int = 2
	while gpUsed.has(gpCandidate):
		gpCandidate = gpBase + "-" + str(gpK)
		gpK += 1
	return gpCandidate


# Content fingerprint: the same bytes means the same symbol, whatever its id is.
# 内容指纹：字节相同即意味着同一个图元，无论其 id 是什么。
static func gpFingerprint(gpDict: Dictionary) -> String:
	return str(JSON.stringify(gpDict).hash())
