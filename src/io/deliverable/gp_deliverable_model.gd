class_name GPDeliverableModel
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Builds the four Excel deliverable row sets from live sheets. Pure functions only: it reads
# GPPIDGraph / GPSheet / GPSymbolDef and returns plain Dictionaries. No FileAccess, no I18n,
# no Node — so every rule here is headless-testable.
# 从活动图纸构建四类 Excel 交付行集。纯函数：只读 GPPIDGraph / GPSheet / GPSymbolDef，
# 返回普通 Dictionary。不碰 FileAccess / I18n / Node —— 故这里每条规则都可 headless 测试。
#
# ROW CONTRACT / 行契约：
#   {no, sheet, ...catalogue fields..., props, _node_id/_sheet_id or _edge_ids/_sheet_ids}
# `props` is the node's full effective schema values; `_*` keys are internal handles for the
# write-back phase and MUST NOT be mapped by a template (the catalogue has no such fields).
# `props` 是节点全部有效 schema 值；`_*` 是回写阶段用的内部句柄，模板**不得**映射
# （字段目录里没有这些键）。
#
# LINE RULE / 管线规则：
# one row per line number, not per edge. A valve splits a pipe into several edges; the line
# list must still show one line. Valves are listed in the `valves` column; fittings are not
# exported at all (user decision 2026-10-19).
# 一个管线号一行，不是一条边一行。阀门把管子切成多条边，清单仍是一根线；阀门进 `valves` 列，
# 管件完全不导出（用户 2026-10-19 拍板）。
#
# Coding rule: every variable declares its type explicitly; every function is static (pure).
# 编码规范：所有变量显式声明类型；函数全部静态（纯函数）。

const GP_SEVERITY_WARNING: String = "warning"
const GP_SEVERITY_INFO: String = "info"

const GP_EMPTY_LINE_PREFIX: String = "__empty_line__:"


# ==================== public entry points / 公开入口 ====================

# All four lists at once. Returned dictionary: {line, equipment, instrument, valve, issues}.
# 一次构建四张表。返回：{line, equipment, instrument, valve, issues}。
static func gpBuildAll(gpSheets: Array, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary = {}) -> Dictionary:
	var gpCtx: Dictionary = _gpContext(gpSheets, gpDefs, gpOptions)
	var gpOut: Dictionary = {}
	gpOut[GPDeliverableFields.GP_LIST_LINE] = _gpBuildLines(gpCtx)
	gpOut[GPDeliverableFields.GP_LIST_EQUIPMENT] = _gpBuildEquipment(gpCtx)
	gpOut[GPDeliverableFields.GP_LIST_INSTRUMENT] = _gpBuildInstruments(gpCtx)
	gpOut[GPDeliverableFields.GP_LIST_VALVE] = _gpBuildValves(gpCtx)
	var gpAllIssues: Array = []
	for gpList in GPDeliverableFields.gpListIds():
		var gpResult: Dictionary = gpOut[gpList] as Dictionary
		gpAllIssues.append_array(gpResult.get("issues", []) as Array)
	gpOut["issues"] = gpAllIssues
	return gpOut


# One list. Unknown list id returns an empty result rather than crashing the caller.
# 单张表。未知清单 id 返回空结果，而不是让调用方崩溃。
static func gpBuildList(gpList: String, gpSheets: Array, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary = {}) -> Dictionary:
	if not GPDeliverableFields.gpIsKnownList(gpList):
		return {"list": gpList, "rows": [], "issues": [], "count": 0}
	var gpCtx: Dictionary = _gpContext(gpSheets, gpDefs, gpOptions)
	match gpList:
		GPDeliverableFields.GP_LIST_LINE:
			return _gpBuildLines(gpCtx)
		GPDeliverableFields.GP_LIST_EQUIPMENT:
			return _gpBuildEquipment(gpCtx)
		GPDeliverableFields.GP_LIST_INSTRUMENT:
			return _gpBuildInstruments(gpCtx)
		GPDeliverableFields.GP_LIST_VALVE:
			return _gpBuildValves(gpCtx)
	return {"list": gpList, "rows": [], "issues": [], "count": 0}


static func gpBuildLines(gpSheets: Array, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary = {}) -> Dictionary:
	return _gpBuildLines(_gpContext(gpSheets, gpDefs, gpOptions))


static func gpBuildEquipment(gpSheets: Array, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary = {}) -> Dictionary:
	return _gpBuildEquipment(_gpContext(gpSheets, gpDefs, gpOptions))


static func gpBuildInstruments(gpSheets: Array, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary = {}) -> Dictionary:
	return _gpBuildInstruments(_gpContext(gpSheets, gpDefs, gpOptions))


static func gpBuildValves(gpSheets: Array, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary = {}) -> Dictionary:
	return _gpBuildValves(_gpContext(gpSheets, gpDefs, gpOptions))


# ==================== context / 上下文 ====================

static func _gpContext(gpSheets: Array, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary) -> Dictionary:
	var gpDefsAll: Array[GPSymbolDef] = gpDefs
	if gpDefsAll.is_empty():
		gpDefsAll = GPSymbolLibrary.gpDefaultDefs()
	var gpDefById: Dictionary = {}
	for gpDef in gpDefsAll:
		if gpDef != null and gpDef.gpId != "":
			gpDefById[gpDef.gpId] = gpDef
	var gpLookup: Callable = func(gpId: String) -> GPSymbolDef:
		return gpDefById.get(gpId) as GPSymbolDef
	return {
		"sheets": gpSheets,
		"defs": gpDefById,
		"lookup": gpLookup,
		"locale": str(gpOptions.get("locale", "zh")),
		"type_labels": gpOptions.get("type_labels", {}) as Dictionary,
		"options": gpOptions,
	}


# ==================== line list / 管线表 ====================

static func _gpBuildLines(gpCtx: Dictionary) -> Dictionary:
	var gpGroups: Dictionary = {}
	var gpGroupOrder: Array[String] = []
	var gpEmptySeq: int = 0
	var gpSheets: Array = gpCtx.get("sheets", []) as Array
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null or gpSheet.gpGraph == null:
			continue
		var gpGraph: GPPIDGraph = gpSheet.gpGraph
		var gpSheetKey: String = _gpSheetId(gpSheet)
		for gpEdgeRaw in gpGraph.gpEdges:
			var gpEdge: GPPIDEdge = gpEdgeRaw as GPPIDEdge
			if gpEdge == null:
				continue
			if gpEdge.gpKind != GPPIDEdge.GP_PROCESS and gpEdge.gpKind != GPPIDEdge.GP_UTILITY:
				continue
			var gpLineNo: String = gpEdge.gpTag.strip_edges()
			var gpKey: String = gpLineNo
			if gpKey == "":
				gpEmptySeq += 1
				gpKey = GP_EMPTY_LINE_PREFIX + gpSheetKey + ":" + gpEdge.gpInstanceId
			if not gpGroups.has(gpKey):
				gpGroups[gpKey] = {
					"line_no": gpLineNo,
					"empty": gpLineNo == "",
					"edges": [],
					"sheet_names": {},
					"sheet_ids": {},
					"sheet_index_by_name": {},
					"sheet_index_by_id": {},
					"min_index": gpSheet.gpIndex,
				}
				gpGroupOrder.append(gpKey)
			var gpGroup: Dictionary = gpGroups[gpKey] as Dictionary
			(gpGroup["edges"] as Array).append({
				"edge": gpEdge,
				"sheet": gpSheet,
				"graph": gpGraph,
			})
			var gpSheetName: String = _gpSheetName(gpSheet)
			(gpGroup["sheet_names"] as Dictionary)[gpSheetName] = true
			(gpGroup["sheet_ids"] as Dictionary)[_gpSheetId(gpSheet)] = true
			(gpGroup["sheet_index_by_name"] as Dictionary)[gpSheetName] = gpSheet.gpIndex
			(gpGroup["sheet_index_by_id"] as Dictionary)[_gpSheetId(gpSheet)] = gpSheet.gpIndex
			if gpSheet.gpIndex < int(gpGroup["min_index"]):
				gpGroup["min_index"] = gpSheet.gpIndex

	var gpRows: Array[Dictionary] = []
	var gpIssues: Array = []
	for gpKey in gpGroupOrder:
		var gpGroup: Dictionary = gpGroups[gpKey] as Dictionary
		gpRows.append(_gpLineRow(gpGroup, gpCtx, gpIssues))
	_gpSortRows(gpRows, true)
	return {"list": GPDeliverableFields.GP_LIST_LINE, "rows": gpRows,
		"issues": gpIssues, "count": gpRows.size()}


static func _gpLineRow(gpGroup: Dictionary, gpCtx: Dictionary, gpIssues: Array) -> Dictionary:
	var gpEdges: Array = gpGroup.get("edges", []) as Array
	var gpLineNo: String = str(gpGroup.get("line_no", ""))
	var gpRow: Dictionary = {
		"no": 0,
		"line_no": gpLineNo,
		"sheet": _gpJoinedSheetNames(gpGroup),
		"line_kind": _gpFirstLineKind(gpEdges, str(gpCtx.get("locale", "zh"))),
		"from": "",
		"to": "",
		"from_equipment": "",
		"to_equipment": "",
		"dn": _gpFirstAttr(gpEdges, "dn"),
		"spec": _gpFirstAttr(gpEdges, "spec"),
		"medium": _gpFirstAttr(gpEdges, "medium"),
		"insulation": _gpFirstAttr(gpEdges, "insulation"),
		"length_m": _gpLineLength(gpEdges, gpCtx),
		"valves": "",
		"valve_count": 0,
		"segment_count": gpEdges.size(),
		"props": {},
		"_sheet_ids": _gpSheetIdsOf(gpGroup),
		"_sheet_order": int(gpGroup.get("min_index", 999999)),
		"_edge_ids": _gpEdgeIdsOf(gpEdges),
	}

	var gpEndpoint: Dictionary = _gpLineEndpoints(gpEdges, gpCtx)
	var gpFrom: Dictionary = gpEndpoint.get("from", {}) as Dictionary
	var gpTo: Dictionary = gpEndpoint.get("to", {}) as Dictionary
	if gpFrom.is_empty() and gpTo.is_empty():
		gpRow["from"] = "（悬空）"
		gpRow["to"] = "（悬空）"
	else:
		gpRow["from"] = _gpEndpointTag(gpFrom) if not gpFrom.is_empty() else "（悬空）"
		gpRow["to"] = _gpEndpointTag(gpTo) if not gpTo.is_empty() else "（悬空）"
		gpRow["from_equipment"] = _gpEndpointHost(gpFrom, gpCtx)
		gpRow["to_equipment"] = _gpEndpointHost(gpTo, gpCtx)

	var gpTags: Array[String] = []
	for gpTagRaw in (gpEndpoint.get("tags", []) as Array):
		if not gpTags.has(str(gpTagRaw)):
			gpTags.append(str(gpTagRaw))
	if gpTags.size() > 2:
		gpIssues.append(_gpIssue("data.line_branch", GP_SEVERITY_INFO,
			{"line_no": gpLineNo, "tags": gpTags}))

	if bool(gpEndpoint.get("dangling", false)):
		gpIssues.append(_gpIssue("data.line_dangling", GP_SEVERITY_WARNING,
			{"line_no": gpLineNo}))

	if bool(gpGroup.get("empty", false)):
		gpIssues.append(_gpIssue("data.line_no_missing", GP_SEVERITY_WARNING,
			{"sheet": gpRow["sheet"]}))

	var gpValveInfo: Dictionary = _gpValvesOf(gpEdges, gpCtx)
	var gpValveTags: Array[String] = []
	for gpTagRaw in (gpValveInfo.get("tags", []) as Array):
		gpValveTags.append(str(gpTagRaw))
	gpRow["valves"] = _gpJoin(gpValveTags, ", ")
	gpRow["valve_count"] = gpValveTags.size()
	if int(gpValveInfo.get("untagged", 0)) > 0:
		gpIssues.append(_gpIssue("data.valve_untagged", GP_SEVERITY_WARNING,
			{"line_no": gpLineNo, "count": int(gpValveInfo.get("untagged", 0))}))
	return gpRow


# All endpoint records of one line group, split into inline components and terminals.
# 一个管线组的全部端点记录，分为内联件与端点。
static func _gpLineEndpoints(gpEdges: Array, gpCtx: Dictionary) -> Dictionary:
	var gpDefs: Dictionary = gpCtx.get("defs", {}) as Dictionary
	var gpAll: Array = []
	var gpTerminals: Array = []
	var gpSeen: Dictionary = {}
	var gpDangling: bool = false
	for gpEntryRaw in gpEdges:
		var gpEntry: Dictionary = gpEntryRaw as Dictionary
		var gpEdge: GPPIDEdge = gpEntry.get("edge", null) as GPPIDEdge
		var gpGraph: GPPIDGraph = gpEntry.get("graph", null) as GPPIDGraph
		var gpSheet: GPSheet = gpEntry.get("sheet", null) as GPSheet
		if gpEdge == null or gpGraph == null:
			continue
		for gpIsFrom in [true, false]:
			var gpNode: GPPIDNode = _gpEdgeNode(gpGraph, gpEdge, gpIsFrom)
			if gpNode == null:
				gpDangling = true
				continue
			var gpKeyNode: String = _gpSheetId(gpSheet) + "|" + gpNode.gpInstanceId
			if gpSeen.has(gpKeyNode):
				continue
			gpSeen[gpKeyNode] = true
			var gpDef: GPSymbolDef = gpDefs.get(gpNode.gpSymbolId) as GPSymbolDef
			var gpClass: Dictionary = GPDeliverableRules.gpClassificationOf(gpDef)
			var gpRecord: Dictionary = {
				"node": gpNode,
				"def": gpDef,
				"kind": str(gpClass.get("kind", GPDeliverableRules.GP_KIND_UNKNOWN)),
				"graph": gpGraph,
				"sheet": gpSheet,
			}
			gpAll.append(gpRecord)
			if not GPDeliverableRules.gpIsInlineKind(str(gpRecord["kind"])):
				gpTerminals.append(gpRecord)

	if gpTerminals.is_empty():
		gpTerminals = gpAll
	_gpSortEndpointRecords(gpTerminals, gpCtx)

	var gpFrom: Dictionary = {}
	var gpTo: Dictionary = {}
	if not gpTerminals.is_empty():
		gpFrom = gpTerminals[0] as Dictionary
		gpTo = gpTerminals[gpTerminals.size() - 1] as Dictionary

	var gpTags: Array[String] = []
	for gpRecordRaw in gpTerminals:
		var gpRecord: Dictionary = gpRecordRaw as Dictionary
		var gpTag: String = _gpNodeTag(gpRecord.get("node", null) as GPPIDNode,
			gpRecord.get("def", null) as GPSymbolDef)
		if gpTag != "":
			gpTags.append(gpTag)
	return {
		"from": gpFrom,
		"to": gpTo,
		"all": gpAll,
		"terminals": gpTerminals,
		"dangling": gpDangling,
		"tags": gpTags,
	}


# Sort endpoints by page position (x then y); ties by tag so the result is deterministic.
# 按图面位置（先 x 后 y）排序；同位用位号兜底，保证确定性。
static func _gpSortEndpointRecords(gpRecords: Array, gpCtx: Dictionary) -> void:
	if gpRecords.size() < 2:
		return
	var gpLookup: Callable = gpCtx.get("lookup") as Callable
	gpRecords.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
		var gpNa: GPPIDNode = gpA.get("node", null) as GPPIDNode
		var gpNb: GPPIDNode = gpB.get("node", null) as GPPIDNode
		var gpGa: GPPIDGraph = gpA.get("graph", null) as GPPIDGraph
		var gpGb: GPPIDGraph = gpB.get("graph", null) as GPPIDGraph
		var gpPa: Vector2 = GPPortResolver.gpNodeWorldOrigin(gpGa, gpLookup, gpNa)
		var gpPb: Vector2 = GPPortResolver.gpNodeWorldOrigin(gpGb, gpLookup, gpNb)
		if absf(gpPa.x - gpPb.x) > 0.0001:
			return gpPa.x < gpPb.x
		if absf(gpPa.y - gpPb.y) > 0.0001:
			return gpPa.y < gpPb.y
		return _gpNodeTag(gpNa, gpA.get("def", null) as GPSymbolDef) < _gpNodeTag(gpNb, gpB.get("def", null) as GPSymbolDef))


# Valve records connected to any edge of the group (deduplicated; tags sorted naturally).
# 管线组任意边上的阀门记录（去重；位号自然排序）。
static func _gpValvesOf(gpEdges: Array, gpCtx: Dictionary) -> Dictionary:
	var gpDefs: Dictionary = gpCtx.get("defs", {}) as Dictionary
	var gpSeen: Dictionary = {}
	var gpRecords: Array = []
	var gpUntagged: int = 0
	for gpEntryRaw in gpEdges:
		var gpEntry: Dictionary = gpEntryRaw as Dictionary
		var gpEdge: GPPIDEdge = gpEntry.get("edge", null) as GPPIDEdge
		var gpGraph: GPPIDGraph = gpEntry.get("graph", null) as GPPIDGraph
		var gpSheet: GPSheet = gpEntry.get("sheet", null) as GPSheet
		if gpEdge == null or gpGraph == null:
			continue
		for gpIsFrom in [true, false]:
			var gpNode: GPPIDNode = _gpEdgeNode(gpGraph, gpEdge, gpIsFrom)
			if gpNode == null:
				continue
			var gpKeyNode: String = _gpSheetId(gpSheet) + "|" + gpNode.gpInstanceId
			if gpSeen.has(gpKeyNode):
				continue
			gpSeen[gpKeyNode] = true
			var gpDef: GPSymbolDef = gpDefs.get(gpNode.gpSymbolId) as GPSymbolDef
			var gpClass: Dictionary = GPDeliverableRules.gpClassificationOf(gpDef)
			if str(gpClass.get("kind", "")) != GPDeliverableRules.GP_KIND_VALVE:
				continue
			gpRecords.append({"node": gpNode, "def": gpDef})
	var gpTags: Array[String] = []
	for gpRecordRaw in gpRecords:
		var gpRecord: Dictionary = gpRecordRaw as Dictionary
		var gpNode: GPPIDNode = gpRecord.get("node", null) as GPPIDNode
		var gpDef: GPSymbolDef = gpRecord.get("def", null) as GPSymbolDef
		var gpTag: String = _gpNodeTag(gpNode, gpDef)
		if gpTag == "":
			gpUntagged += 1
			gpTags.append("<无位号:%s>" % _gpTypeLabel(gpCtx, gpNode.gpSymbolId, gpDef))
		else:
			gpTags.append(gpTag)
	_gpSortStrings(gpTags)
	return {"tags": gpTags, "records": gpRecords, "untagged": gpUntagged}


# ==================== equipment / 设备表 ====================

static func _gpBuildEquipment(gpCtx: Dictionary) -> Dictionary:
	var gpRows: Array[Dictionary] = []
	var gpIssues: Array = []
	var gpMissingTags: int = 0
	var gpUnknownDefs: int = 0
	var gpUnclassified: int = 0
	var gpSheets: Array = gpCtx.get("sheets", []) as Array
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null or gpSheet.gpGraph == null:
			continue
		var gpGraph: GPPIDGraph = gpSheet.gpGraph
		for gpNodeRaw in gpGraph.gpNodes:
			var gpNode: GPPIDNode = gpNodeRaw as GPPIDNode
			if gpNode == null or gpNode.gpParentUid != "":
				continue
			var gpDef: GPSymbolDef = _gpDefOf(gpCtx, gpNode)
			var gpClass: Dictionary = GPDeliverableRules.gpClassificationOf(gpDef)
			if gpDef == null:
				# Missing definition still gets a row: a deliverable must not silently drop it.
				# 定义缺失仍出行：交付物不能静默丢设备。
				gpUnknownDefs += 1
				gpClass = {"kind": GPDeliverableRules.GP_KIND_EQUIPMENT, "unknown": true}
			elif str(gpClass.get("kind", "")) != GPDeliverableRules.GP_KIND_EQUIPMENT:
				continue
			elif bool(gpClass.get("unknown", false)):
				gpUnclassified += 1
			var gpRow: Dictionary = _gpNodeRow(GPDeliverableFields.GP_LIST_EQUIPMENT,
				gpNode, gpDef, gpSheet, gpCtx)
			gpRows.append(gpRow)
			if str(gpRow.get("tag", "")).strip_edges() == "":
				gpMissingTags += 1
	_gpSortRows(gpRows, false)
	if gpMissingTags > 0:
		gpIssues.append(_gpIssue("data.tag_missing", GP_SEVERITY_WARNING,
			{"list": GPDeliverableFields.GP_LIST_EQUIPMENT, "count": gpMissingTags}))
	if gpUnknownDefs > 0:
		gpIssues.append(_gpIssue("data.unknown_symbol", GP_SEVERITY_WARNING,
			{"list": GPDeliverableFields.GP_LIST_EQUIPMENT, "count": gpUnknownDefs}))
	if gpUnclassified > 0:
		gpIssues.append(_gpIssue("data.unclassified_symbol", GP_SEVERITY_WARNING,
			{"list": GPDeliverableFields.GP_LIST_EQUIPMENT, "count": gpUnclassified}))
	_gpAddDuplicateIssues(gpRows, "tag", GPDeliverableFields.GP_LIST_EQUIPMENT, gpIssues)
	return {"list": GPDeliverableFields.GP_LIST_EQUIPMENT, "rows": gpRows,
		"issues": gpIssues, "count": gpRows.size()}


# ==================== instrument index / 仪表表 ====================

static func _gpBuildInstruments(gpCtx: Dictionary) -> Dictionary:
	var gpRows: Array[Dictionary] = []
	var gpIssues: Array = []
	var gpMissingTags: int = 0
	var gpUnconnected: int = 0
	var gpLoopUnresolved: int = 0
	var gpSheets: Array = gpCtx.get("sheets", []) as Array
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null or gpSheet.gpGraph == null:
			continue
		var gpGraph: GPPIDGraph = gpSheet.gpGraph
		for gpNodeRaw in gpGraph.gpNodes:
			var gpNode: GPPIDNode = gpNodeRaw as GPPIDNode
			if gpNode == null or gpNode.gpParentUid != "":
				continue
			var gpDef: GPSymbolDef = _gpDefOf(gpCtx, gpNode)
			if gpDef == null:
				continue
			var gpClass: Dictionary = GPDeliverableRules.gpClassificationOf(gpDef)
			if str(gpClass.get("kind", "")) != GPDeliverableRules.GP_KIND_INSTRUMENT:
				continue
			var gpRow: Dictionary = _gpNodeRow(GPDeliverableFields.GP_LIST_INSTRUMENT,
				gpNode, gpDef, gpSheet, gpCtx)
			gpRows.append(gpRow)
			if str(gpRow.get("tag", "")).strip_edges() == "":
				gpMissingTags += 1
			if str(gpRow.get("connected_line", "")).strip_edges() == "" \
					and str(gpRow.get("connected_equipment", "")).strip_edges() == "":
				gpUnconnected += 1
			if str(gpRow.get("loop_no", "")).strip_edges() == "":
				gpLoopUnresolved += 1
	_gpSortRows(gpRows, false)
	if gpMissingTags > 0:
		gpIssues.append(_gpIssue("data.tag_missing", GP_SEVERITY_WARNING,
			{"list": GPDeliverableFields.GP_LIST_INSTRUMENT, "count": gpMissingTags}))
	if gpUnconnected > 0:
		gpIssues.append(_gpIssue("data.instrument_unconnected", GP_SEVERITY_WARNING,
			{"count": gpUnconnected}))
	if gpLoopUnresolved > 0:
		gpIssues.append(_gpIssue("data.loop_unresolved", GP_SEVERITY_INFO,
			{"count": gpLoopUnresolved}))
	_gpAddDuplicateIssues(gpRows, "tag", GPDeliverableFields.GP_LIST_INSTRUMENT, gpIssues)
	return {"list": GPDeliverableFields.GP_LIST_INSTRUMENT, "rows": gpRows,
		"issues": gpIssues, "count": gpRows.size()}


# ==================== valve list / 阀门表 ====================

static func _gpBuildValves(gpCtx: Dictionary) -> Dictionary:
	var gpRows: Array[Dictionary] = []
	var gpIssues: Array = []
	var gpMissingTags: int = 0
	var gpNoLine: int = 0
	var gpSheets: Array = gpCtx.get("sheets", []) as Array
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null or gpSheet.gpGraph == null:
			continue
		var gpGraph: GPPIDGraph = gpSheet.gpGraph
		for gpNodeRaw in gpGraph.gpNodes:
			var gpNode: GPPIDNode = gpNodeRaw as GPPIDNode
			if gpNode == null or gpNode.gpParentUid != "":
				continue
			var gpDef: GPSymbolDef = _gpDefOf(gpCtx, gpNode)
			if gpDef == null:
				continue
			var gpClass: Dictionary = GPDeliverableRules.gpClassificationOf(gpDef)
			if str(gpClass.get("kind", "")) != GPDeliverableRules.GP_KIND_VALVE:
				continue
			var gpRow: Dictionary = _gpNodeRow(GPDeliverableFields.GP_LIST_VALVE,
				gpNode, gpDef, gpSheet, gpCtx)
			gpRows.append(gpRow)
			if str(gpRow.get("tag", "")).strip_edges() == "":
				gpMissingTags += 1
			if str(gpRow.get("line_no", "")).strip_edges() == "":
				gpNoLine += 1
	_gpSortRows(gpRows, false)
	if gpMissingTags > 0:
		gpIssues.append(_gpIssue("data.tag_missing", GP_SEVERITY_WARNING,
			{"list": GPDeliverableFields.GP_LIST_VALVE, "count": gpMissingTags}))
	if gpNoLine > 0:
		gpIssues.append(_gpIssue("data.valve_no_line", GP_SEVERITY_WARNING,
			{"count": gpNoLine}))
	_gpAddDuplicateIssues(gpRows, "tag", GPDeliverableFields.GP_LIST_VALVE, gpIssues)
	return {"list": GPDeliverableFields.GP_LIST_VALVE, "rows": gpRows,
		"issues": gpIssues, "count": gpRows.size()}


# ==================== one node row / 单节点行 ====================

static func _gpNodeRow(gpList: String, gpNode: GPPIDNode, gpDef: GPSymbolDef,
		gpSheet: GPSheet, gpCtx: Dictionary) -> Dictionary:
	var gpLocale: String = GPDeliverableFields.gpLocaleCode(str(gpCtx.get("locale", "zh")))
	var gpGraph: GPPIDGraph = gpSheet.gpGraph
	var gpProps: Dictionary = _gpPropsOf(gpNode, gpDef)
	var gpTypeLabel: String = _gpTypeLabel(gpCtx, gpNode.gpSymbolId, gpDef)
	var gpCategory: String = ""
	if gpDef != null:
		gpCategory = gpDef.gpCategory
	var gpRow: Dictionary = {
		"no": 0,
		"sheet": _gpSheetName(gpSheet),
		"tag": gpNode.gpTag,
		"name": GPPropertyResolver.gpDisplayName(gpNode.gpNames,
			gpTypeLabel, gpLocale, gpNode.gpTag),
		"type": gpTypeLabel,
		"class": GPDeliverableRules.gpClassNameOf(gpDef),
		"category": gpCategory,
		"qty": 1,
		"props": gpProps,
		"_node_id": gpNode.gpInstanceId,
		"_sheet_id": _gpSheetId(gpSheet),
		"_sheet_order": gpSheet.gpIndex,
	}
	var gpConnectivity: Dictionary = {}
	if gpList == GPDeliverableFields.GP_LIST_INSTRUMENT:
		gpConnectivity = _gpInstrumentConnectivity(gpGraph, gpNode, gpCtx)
	for gpKey in GPDeliverableFields.gpFieldsOf(gpList):
		if gpRow.has(gpKey):
			continue
		match gpKey:
			"nozzle_count":
				gpRow[gpKey] = _gpNozzleCount(gpGraph, gpNode, gpCtx)
			"line_no":
				gpRow[gpKey] = _gpValveLineNos(gpGraph, gpNode)
			"loop_no":
				gpRow[gpKey] = _gpFirstDigits(gpNode.gpTag)
			"signal_type":
				var gpSignal: String = GPDeliverableFields.gpValueText(
					gpProps.get("signal_type", ""))
				if gpSignal.strip_edges() == "":
					gpSignal = str(gpConnectivity.get("signal_type", ""))
				gpRow[gpKey] = gpSignal
			"connected_line":
				gpRow[gpKey] = str(gpConnectivity.get("line", ""))
			"connected_equipment":
				gpRow[gpKey] = str(gpConnectivity.get("equipment", ""))
			_:
				var gpSource: String = GPDeliverableFields.gpSource(gpKey)
				if gpSource.begins_with("prop:"):
					var gpPropKey: String = gpSource.substr("prop:".length())
					gpRow[gpKey] = GPDeliverableFields.gpCoerce(gpKey, gpProps.get(gpPropKey, null))
				else:
					gpRow[gpKey] = ""
	return gpRow


static func _gpPropsOf(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> Dictionary:
	if gpNode == null:
		return {}
	if gpDef != null and gpDef.gpSchema != null:
		return GPPropertyResolver.gpEffectiveProps(gpDef.gpSchema, gpNode.gpProps)
	return gpNode.gpProps.duplicate(true)


# ==================== computed helpers / 计算辅助 ====================

# Nozzle count: mounted children whose own mount kind is NOZZLE.
# 管口数：挂载子件中自身 mount kind 为 NOZZLE 的数量。
static func _gpNozzleCount(gpGraph: GPPIDGraph, gpNode: GPPIDNode, gpCtx: Dictionary) -> int:
	if gpGraph == null or gpNode == null:
		return 0
	var gpChildren: Array[GPPIDNode] = GPMountResolver.gpChildrenOf(gpGraph, gpNode.gpInstanceId)
	var gpCount: int = 0
	for gpChild in gpChildren:
		if gpChild == null:
			continue
		var gpDef: GPSymbolDef = _gpDefOf(gpCtx, gpChild)
		if gpDef != null and gpDef.gpMountKind == "NOZZLE":
			gpCount += 1
	return gpCount


# Line numbers of the PROCESS/UTILITY edges incident to a valve (deduplicated, natural order).
# 阀门所连 PROCESS/UTILITY 边的管线号（去重、自然排序）。
static func _gpValveLineNos(gpGraph: GPPIDGraph, gpNode: GPPIDNode) -> String:
	if gpGraph == null or gpNode == null:
		return ""
	var gpTags: Array[String] = []
	for gpEdgeRaw in gpGraph.gpEdges:
		var gpEdge: GPPIDEdge = gpEdgeRaw as GPPIDEdge
		if gpEdge == null:
			continue
		if gpEdge.gpKind != GPPIDEdge.GP_PROCESS and gpEdge.gpKind != GPPIDEdge.GP_UTILITY:
			continue
		if not _gpEdgeTouchesNode(gpEdge, gpNode):
			continue
		var gpTag: String = gpEdge.gpTag.strip_edges()
		if gpTag != "" and not gpTags.has(gpTag):
			gpTags.append(gpTag)
	_gpSortStrings(gpTags)
	return _gpJoin(gpTags, ", ")


# Instrument connectivity: process lines + host equipment + first signal edge type.
# 仪表连接：工艺管线 + 宿主设备 + 第一条信号边类型。
static func _gpInstrumentConnectivity(gpGraph: GPPIDGraph, gpNode: GPPIDNode,
		gpCtx: Dictionary) -> Dictionary:
	var gpLines: Array[String] = []
	var gpEquipment: Array[String] = []
	var gpSignalType: String = ""
	if gpGraph == null or gpNode == null:
		return {"line": "", "equipment": "", "signal_type": ""}
	for gpEdgeRaw in gpGraph.gpEdges:
		var gpEdge: GPPIDEdge = gpEdgeRaw as GPPIDEdge
		if gpEdge == null or not _gpEdgeTouchesNode(gpEdge, gpNode):
			continue
		if gpEdge.gpKind == GPPIDEdge.GP_SIGNAL and gpSignalType == "":
			gpSignalType = _gpSignalTypeText(gpEdge.gpSignalType,
				str(gpCtx.get("locale", "zh")))
		if (gpEdge.gpKind == GPPIDEdge.GP_PROCESS or gpEdge.gpKind == GPPIDEdge.GP_UTILITY):
			var gpTag: String = gpEdge.gpTag.strip_edges()
			if gpTag != "" and not gpLines.has(gpTag):
				gpLines.append(gpTag)
		var gpOther: GPPIDNode = _gpOtherNode(gpGraph, gpEdge, gpNode)
		var gpHostTag: String = _gpHouseTag(gpGraph, gpOther, gpCtx)
		if gpHostTag != "" and not gpEquipment.has(gpHostTag):
			gpEquipment.append(gpHostTag)
	_gpSortStrings(gpLines)
	_gpSortStrings(gpEquipment)
	return {"line": _gpJoin(gpLines, ", "), "equipment": _gpJoin(gpEquipment, ", "),
		"signal_type": gpSignalType}


# ==================== row sorting / 行排序 ====================

static func _gpSortRows(gpRows: Array[Dictionary], gpIsLine: bool) -> void:
	if gpRows.is_empty():
		return
	gpRows.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
		var gpSheetA: int = int(gpA.get("_sheet_order", 999999))
		var gpSheetB: int = int(gpB.get("_sheet_order", 999999))
		if gpSheetA != gpSheetB:
			return gpSheetA < gpSheetB
		var gpKeyA: String = _gpRowSortKey(gpA, gpIsLine)
		var gpKeyB: String = _gpRowSortKey(gpB, gpIsLine)
		var gpEmptyA: bool = gpKeyA.strip_edges() == ""
		var gpEmptyB: bool = gpKeyB.strip_edges() == ""
		if gpEmptyA != gpEmptyB:
			return not gpEmptyA
		if _gpNaturalLess(gpKeyA, gpKeyB):
			return true
		if _gpNaturalLess(gpKeyB, gpKeyA):
			return false
		return str(gpA.get("_node_id", "")) < str(gpB.get("_node_id", "")))
	for gpI in range(gpRows.size()):
		var gpRow: Dictionary = gpRows[gpI]
		gpRow["no"] = gpI + 1


# ==================== generic helpers / 通用辅助 ====================

static func _gpRowSortKey(gpRow: Dictionary, gpIsLine: bool) -> String:
	if gpIsLine:
		return str(gpRow.get("line_no", ""))
	return str(gpRow.get("tag", ""))

static func _gpDefOf(gpCtx: Dictionary, gpNode: GPPIDNode) -> GPSymbolDef:
	if gpNode == null:
		return null
	var gpDefs: Dictionary = gpCtx.get("defs", {}) as Dictionary
	return gpDefs.get(gpNode.gpSymbolId) as GPSymbolDef


static func _gpDefDisplay(gpDef: GPSymbolDef) -> String:
	if gpDef == null:
		return ""
	return gpDef.gpDisplayName


# Localised type label: UI passes I18n-resolved names in options.type_labels; headless
# falls back to the library display name (which may itself be an i18n key).
# 本地化类型名：UI 经 options.type_labels 传入 I18n 结果；headless 回落库显示名（可能是 i18n 键）。
static func _gpTypeLabel(gpCtx: Dictionary, gpSymbolId: String, gpDef: GPSymbolDef) -> String:
	var gpLabels: Dictionary = gpCtx.get("type_labels", {}) as Dictionary
	if gpLabels.has(gpSymbolId):
		return str(gpLabels[gpSymbolId])
	return _gpDefDisplay(gpDef)


static func _gpEdgeNode(gpGraph: GPPIDGraph, gpEdge: GPPIDEdge, gpIsFrom: bool) -> GPPIDNode:
	if gpGraph == null or gpEdge == null:
		return null
	var gpRef: Dictionary = gpEdge.gpFromRef if gpIsFrom else gpEdge.gpToRef
	var gpNodeId: String = str(gpRef.get("node_id", ""))
	if gpNodeId == "":
		return null
	return gpGraph.gpGetNode(gpNodeId)


static func _gpEdgeTouchesNode(gpEdge: GPPIDEdge, gpNode: GPPIDNode) -> bool:
	if gpEdge == null or gpNode == null:
		return false
	return str(gpEdge.gpFromRef.get("node_id", "")) == gpNode.gpInstanceId \
		or str(gpEdge.gpToRef.get("node_id", "")) == gpNode.gpInstanceId


static func _gpOtherNode(gpGraph: GPPIDGraph, gpEdge: GPPIDEdge, gpNode: GPPIDNode) -> GPPIDNode:
	if gpGraph == null or gpEdge == null or gpNode == null:
		return null
	var gpFromId: String = str(gpEdge.gpFromRef.get("node_id", ""))
	if gpFromId == gpNode.gpInstanceId:
		var gpToId: String = str(gpEdge.gpToRef.get("node_id", ""))
		return gpGraph.gpGetNode(gpToId) if gpToId != "" else null
	return gpGraph.gpGetNode(gpFromId) if gpFromId != "" else null


static func _gpNodeTag(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> String:
	if gpNode == null:
		return ""
	var gpTag: String = gpNode.gpTag.strip_edges()
	if gpTag != "":
		return gpTag
	return _gpDefDisplay(gpDef)


static func _gpEndpointTag(gpRecord: Dictionary) -> String:
	var gpNode: GPPIDNode = gpRecord.get("node", null) as GPPIDNode
	if gpNode == null:
		return ""
	return _gpNodeTag(gpNode, gpRecord.get("def", null) as GPSymbolDef)


static func _gpEndpointHost(gpRecord: Dictionary, gpCtx: Dictionary) -> String:
	var gpNode: GPPIDNode = gpRecord.get("node", null) as GPPIDNode
	var gpKind: String = str(gpRecord.get("kind", ""))
	if gpNode == null or GPDeliverableRules.gpIsInlineKind(gpKind):
		return ""
	var gpGraph: GPPIDGraph = gpRecord.get("graph", null) as GPPIDGraph
	return _gpHouseTag(gpGraph, gpNode, gpCtx)


# Top-level host tag: a nozzle answers with its equipment, a top-level node answers itself.
# 顶层宿主位号：管口回答其设备，顶层节点回答自己。
static func _gpHouseTag(gpGraph: GPPIDGraph, gpNode: GPPIDNode, gpCtx: Dictionary) -> String:
	if gpGraph == null or gpNode == null:
		return ""
	var gpHost: GPPIDNode = _gpHostNode(gpGraph, gpNode)
	if gpHost == null:
		return ""
	return _gpNodeTag(gpHost, _gpDefOf(gpCtx, gpHost))


static func _gpHostNode(gpGraph: GPPIDGraph, gpNode: GPPIDNode) -> GPPIDNode:
	if gpGraph == null or gpNode == null:
		return null
	var gpCur: GPPIDNode = gpNode
	var gpSeen: Dictionary = {}
	while gpCur != null and gpCur.gpParentUid != "":
		if gpSeen.has(gpCur.gpInstanceId):
			break
		gpSeen[gpCur.gpInstanceId] = true
		var gpParent: GPPIDNode = gpGraph.gpGetNode(gpCur.gpParentUid)
		if gpParent == null:
			break
		gpCur = gpParent
	return gpCur


static func _gpFirstAttr(gpEdges: Array, gpKey: String) -> String:
	for gpEntryRaw in gpEdges:
		var gpEntry: Dictionary = gpEntryRaw as Dictionary
		var gpEdge: GPPIDEdge = gpEntry.get("edge", null) as GPPIDEdge
		if gpEdge == null:
			continue
		var gpValue: String = str(gpEdge.gpAttrs.get(gpKey, "")).strip_edges()
		if gpValue != "":
			return gpValue
	return ""


static func _gpFirstLineKind(gpEdges: Array, gpLocale: String) -> String:
	for gpEntryRaw in gpEdges:
		var gpEntry: Dictionary = gpEntryRaw as Dictionary
		var gpEdge: GPPIDEdge = gpEntry.get("edge", null) as GPPIDEdge
		if gpEdge != null:
			return _gpLineKindText(gpEdge.gpKind, gpLocale)
	return ""


static func _gpLineLength(gpEdges: Array, gpCtx: Dictionary) -> float:
	var gpLookup: Callable = gpCtx.get("lookup") as Callable
	var gpTotal: float = 0.0
	for gpEntryRaw in gpEdges:
		var gpEntry: Dictionary = gpEntryRaw as Dictionary
		var gpEdge: GPPIDEdge = gpEntry.get("edge", null) as GPPIDEdge
		var gpGraph: GPPIDGraph = gpEntry.get("graph", null) as GPPIDGraph
		if gpEdge == null or gpGraph == null:
			continue
		var gpFrom: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpLookup, gpEdge, true)
		var gpTo: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpLookup, gpEdge, false)
		var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(gpFrom, gpTo,
			gpEdge.gpRouting, gpEdge.gpOrtho)
		for gpI in range(1, gpPts.size()):
			gpTotal += gpPts[gpI - 1].distance_to(gpPts[gpI])
	return round(gpTotal / 1000.0 * 100.0) / 100.0


static func _gpLineKindText(gpKind: String, gpLocale: String) -> String:
	if gpKind == GPPIDEdge.GP_PROCESS:
		return "Process line" if gpLocale == "en" else "工艺管线"
	if gpKind == GPPIDEdge.GP_UTILITY:
		return "Utility line" if gpLocale == "en" else "公用工程管线"
	if gpKind == GPPIDEdge.GP_SIGNAL:
		return "Signal line" if gpLocale == "en" else "信号线"
	return gpKind


static func _gpSignalTypeText(gpType: String, gpLocale: String) -> String:
	var gpEn: bool = gpLocale == "en"
	match gpType:
		"ELECTRIC":
			return "Electric" if gpEn else "电气"
		"PNEUMATIC":
			return "Pneumatic" if gpEn else "气动"
		"HYDRAULIC":
			return "Hydraulic" if gpEn else "液压"
		"DATA":
			return "Data" if gpEn else "数据"
		"CAPILLARY":
			return "Capillary" if gpEn else "毛细管"
	return gpType


static func _gpFirstDigits(gpText: String) -> String:
	var gpOut: String = ""
	var gpStarted: bool = false
	for gpI in range(gpText.length()):
		var gpC: String = gpText.substr(gpI, 1)
		if gpC.is_valid_int():
			gpOut += gpC
			gpStarted = true
		elif gpStarted:
			break
	return gpOut


static func _gpJoinedSheetNames(gpGroup: Dictionary) -> String:
	var gpNames: Array[String] = []
	var gpIndexByName: Dictionary = gpGroup.get("sheet_index_by_name", {}) as Dictionary
	for gpNameRaw in (gpGroup.get("sheet_names", {}) as Dictionary).keys():
		gpNames.append(str(gpNameRaw))
	gpNames.sort_custom(func(gpA: String, gpB: String) -> bool:
		return int(gpIndexByName.get(gpA, 999999)) < int(gpIndexByName.get(gpB, 999999)))
	return _gpJoin(gpNames, ", ")


static func _gpSheetIdsOf(gpGroup: Dictionary) -> Array:
	var gpOut: Array = []
	var gpIds: Dictionary = gpGroup.get("sheet_ids", {}) as Dictionary
	var gpIndexById: Dictionary = gpGroup.get("sheet_index_by_id", {}) as Dictionary
	var gpRows: Array = []
	for gpIdRaw in gpIds.keys():
		var gpId: String = str(gpIdRaw)
		gpRows.append({"id": gpId, "order": int(gpIndexById.get(gpId, 999999))})
	gpRows.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
		return int(gpA["order"]) < int(gpB["order"]))
	for gpRowRaw in gpRows:
		gpOut.append(str((gpRowRaw as Dictionary)["id"]))
	return gpOut


static func _gpEdgeIdsOf(gpEdges: Array) -> Array:
	var gpOut: Array = []
	for gpEntryRaw in gpEdges:
		var gpEntry: Dictionary = gpEntryRaw as Dictionary
		var gpEdge: GPPIDEdge = gpEntry.get("edge", null) as GPPIDEdge
		if gpEdge == null:
			continue
		gpOut.append({"sheet_id": _gpSheetId(gpEntry.get("sheet", null) as GPSheet),
			"edge_id": gpEdge.gpInstanceId})
	return gpOut


static func _gpSheetName(gpSheet: GPSheet) -> String:
	if gpSheet == null:
		return ""
	var gpName: String = gpSheet.gpName.strip_edges()
	if gpName != "":
		return gpName
	return "图纸 %d" % (gpSheet.gpIndex + 1)


static func _gpSheetId(gpSheet: GPSheet) -> String:
	if gpSheet == null:
		return ""
	var gpId: String = gpSheet.gpId.strip_edges()
	if gpId != "":
		return gpId
	return "sheet-%d" % (gpSheet.gpIndex + 1)


static func _gpIssue(gpCode: String, gpSeverity: String, gpParams: Dictionary) -> Dictionary:
	return {"code": gpCode, "severity": gpSeverity, "params": gpParams}


static func _gpAddDuplicateIssues(gpRows: Array[Dictionary], gpKey: String,
		gpList: String, gpIssues: Array) -> void:
	var gpCounts: Dictionary = {}
	for gpRow in gpRows:
		var gpValue: String = str(gpRow.get(gpKey, "")).strip_edges()
		if gpValue == "":
			continue
		gpCounts[gpValue] = int(gpCounts.get(gpValue, 0)) + 1
	var gpDups: Array[String] = []
	for gpValueRaw in gpCounts.keys():
		if int(gpCounts[gpValueRaw]) > 1:
			gpDups.append(str(gpValueRaw))
	_gpSortStrings(gpDups)
	for gpValue in gpDups:
		gpIssues.append(_gpIssue("data.tag_duplicate", GP_SEVERITY_WARNING,
			{"list": gpList, "tag": gpValue, "count": int(gpCounts[gpValue])}))


static func _gpJoin(gpParts: Array[String], gpSep: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpParts.size()):
		if gpI > 0:
			gpOut += gpSep
		gpOut += gpParts[gpI]
	return gpOut


static func _gpSortStrings(gpParts: Array[String]) -> void:
	gpParts.sort_custom(func(gpA: String, gpB: String) -> bool:
		return _gpNaturalLess(gpA, gpB))


# Natural comparison: digit runs compare numerically (P-2 before P-10); everything else
# case-insensitively. Used for deterministic row order and valve tag order.
# 自然比较：数字段按数值（P-2 在 P-10 前），其余按大小写不敏感。用于确定性行序与阀门位号序。
static func _gpNaturalLess(gpA: String, gpB: String) -> bool:
	var gpI: int = 0
	var gpJ: int = 0
	while gpI < gpA.length() and gpJ < gpB.length():
		var gpCA: String = gpA.substr(gpI, 1)
		var gpCB: String = gpB.substr(gpJ, 1)
		if gpCA.is_valid_int() and gpCB.is_valid_int():
			var gpNA: int = 0
			var gpIA: int = gpI
			while gpIA < gpA.length() and gpA.substr(gpIA, 1).is_valid_int():
				gpNA = gpNA * 10 + int(gpA.substr(gpIA, 1))
				gpIA += 1
			var gpNB: int = 0
			var gpIB: int = gpJ
			while gpIB < gpB.length() and gpB.substr(gpIB, 1).is_valid_int():
				gpNB = gpNB * 10 + int(gpB.substr(gpIB, 1))
				gpIB += 1
			if gpNA != gpNB:
				return gpNA < gpNB
			gpI = gpIA
			gpJ = gpIB
			continue
		var gpLA: String = gpCA.to_lower()
		var gpLB: String = gpCB.to_lower()
		if gpLA != gpLB:
			return gpLA < gpLB
		gpI += 1
		gpJ += 1
	return gpA.length() < gpB.length()
