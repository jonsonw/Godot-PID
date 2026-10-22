class_name GPRulePack
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# The seven DRC rules (B1 / E01). Pure functions over a graph snapshot: no Node, no autoload,
# no viewport — so the same pack runs in the GUI panel, in a headless test and (later) in the
# CLI gate.
# 七条 DRC 规则（B1 / E01）。对图快照的纯函数：不碰 Node、不碰 autoload、不碰视口 ——
# 故同一份规则包既能在界面面板里跑、也能在 headless 测试与（将来）CLI 门禁里跑。
#
# THE CRITERION OF THE WHOLE PACK / 整包的判据：
# every rule judges "is this drawing correct", never "is this design correct". The latter needs
# process expertise and is explicitly out of scope (功能说明 §09).
# 每条规则只判断「这张图画得对不对」，绝不判断「这个设计对不对」。后者需要工艺专业知识，
# 明确不在范围内（功能说明 §09）。
#
# WHAT IS DELIBERATELY CONSERVATIVE / 刻意保守之处：
#   * rule 2 only reports ports the SYMBOL marks `gpRequired` — spare nozzles are normal;
#   * rule 3 excludes mounted parts (identified by nozzle_id, not by a tag, ADR-23) and signal
#     lines (circuits carry a loop number, which is I14's gap, not a missing pipe number);
#   * rule 5's overlap check ignores a child over its own host (mounting is meant to nest).
#   * 规则 2 只报**图元自己标记**为必需的端口 —— 空置管口是常态；
#   * 规则 3 排除挂载部件（凭 nozzle_id 标识而非位号，ADR-23）与信号线（回路号属 I14 的缺口，
#     不是缺管线号）；
#   * 规则 5 的重叠检查忽略「子件压在自己的宿主上」（挂载本就意味着嵌套）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Rule ids (stable; exported verbatim into reports).
# 规则号（稳定；原样写进报告）。
const GP_RULE_DANGLING: String = "drc.dangling_end"
const GP_RULE_PORT: String = "drc.port_unconnected"
const GP_RULE_TAG: String = "drc.tag"
const GP_RULE_PROPS: String = "drc.required_props"
const GP_RULE_LAYOUT: String = "drc.layout"
const GP_RULE_EDGE_ATTRS: String = "drc.edge_attrs"
const GP_RULE_SHEET_FIT: String = "drc.sheet_fit"

# Edge attribute keys that a process / utility line must carry (rule 6).
# 工艺 / 公用线必须携带的边属性键（规则 6）。
const GP_REQUIRED_EDGE_ATTRS: Array[String] = ["dn", "medium", "spec"]

# Used-area ratio below which a sheet is reported as sparse, and above which as crowded (rule 7).
# 图纸「过空」与「过挤」的已用面积比例阈值（规则 7）。
const GP_FIT_SPARSE: float = 0.02

# Crowded threshold.
# 「过挤」阈值。
const GP_FIT_CROWDED: float = 0.6


# Run all seven rules. Deterministic order: by rule id, then by position, then by object id — so
# two runs on the same graph produce byte-identical reports (E01's acceptance).
# 跑全部七条。顺序确定：先规则号、再位置、再对象 id —— 故同一张图两次运行产出逐字节相同的报告
#（E01 的验收项）。
static func gpRun(gpGraph: GPPIDGraph, gpSheet: GPSheet,
		gpDefs: Array[GPSymbolDef] = []) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	if gpGraph == null:
		return gpOut
	var gpLookup: Dictionary = {}
	for gpD in gpDefs:
		if gpD != null:
			gpLookup[gpD.gpId] = gpD
	_gpRuleDangling(gpGraph, gpOut)
	_gpRulePorts(gpGraph, gpLookup, gpOut)
	_gpRuleTags(gpGraph, gpLookup, gpOut)
	_gpRuleProps(gpGraph, gpLookup, gpOut)
	_gpRuleLayout(gpGraph, gpLookup, gpSheet, gpOut)
	_gpRuleEdgeAttrs(gpGraph, gpOut)
	_gpRuleSheetFit(gpGraph, gpLookup, gpSheet, gpOut)
	gpOut.sort_custom(func(gpA: GPFinding, gpB: GPFinding) -> bool:
		if gpA.gpRuleId != gpB.gpRuleId:
			return gpA.gpRuleId < gpB.gpRuleId
		if gpA.gpWorld != gpB.gpWorld:
			if gpA.gpWorld == Vector2.INF:
				return false
			if gpB.gpWorld == Vector2.INF:
				return true
			if gpA.gpWorld.x != gpB.gpWorld.x:
				return gpA.gpWorld.x < gpB.gpWorld.x
			return gpA.gpWorld.y < gpB.gpWorld.y
		if gpA.gpNodeId != gpB.gpNodeId:
			return gpA.gpNodeId < gpB.gpNodeId
		return gpA.gpEdgeId < gpB.gpEdgeId)
	return gpOut


# Count findings of one severity.
# 统计某一严重度的条数。
static func gpCount(gpFindings: Array[GPFinding], gpSeverity: String) -> int:
	var gpN: int = 0
	for gpF in gpFindings:
		if gpF.gpSeverity == gpSeverity:
			gpN += 1
	return gpN


# Rule 1 — open ends must carry a note (ADR-33 / ADR-34).
# 规则 1 —— 开口端必须带注记（ADR-33 / ADR-34）。
# Three distinct causes, three message keys, so the panel can offer the right fix:
#   * no reference at all            -> end_note_missing
#   * reference to a deleted object  -> end_note_missing_object
#   * reference whose text is blank  -> end_note_empty_text
# 三种不同原因、三条不同消息键，面板才能给出对的修复动作。
static func _gpRuleDangling(gpGraph: GPPIDGraph, gpOut: Array[GPFinding]) -> void:
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		for gpIsFrom in [true, false]:
			if not gpE.gpIsDangling(gpIsFrom):
				continue
			var gpUid: String = gpE.gpEndNoteUid(gpIsFrom)
			var gpWorld: Vector2 = gpE.gpDanglingPoint(gpIsFrom)
			var gpSide: String = "from" if gpIsFrom else "to"
			if gpUid == "":
				gpOut.append(GPFinding.gpMake(GP_RULE_DANGLING, GPFinding.GP_ERROR,
					"drc.end_note_missing", [gpE.gpInstanceId, gpSide]).gpOnEdge(
						gpE.gpInstanceId, gpWorld))
				continue
			var gpNote: GPShape = _gpFindShape(gpGraph, gpUid)
			if gpNote == null:
				gpOut.append(GPFinding.gpMake(GP_RULE_DANGLING, GPFinding.GP_ERROR,
					"drc.end_note_missing_object", [gpE.gpInstanceId, gpSide]).gpOnEdge(
						gpE.gpInstanceId, gpWorld))
			elif gpNote.gpText.strip_edges() == "":
				gpOut.append(GPFinding.gpMake(GP_RULE_DANGLING, GPFinding.GP_ERROR,
					"drc.end_note_empty_text", [gpE.gpInstanceId, gpSide]).gpOnEdge(
						gpE.gpInstanceId, gpWorld))


# Rule 2 — a port the SYMBOL marks required must be wired.
# 规则 2 —— 图元标记为必需的端口必须接线。
static func _gpRulePorts(gpGraph: GPPIDGraph, gpLookup: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	# Which (node, port) pairs are referenced by some edge end.
	# 哪些（节点, 端口）对被某条边的端点引用。
	var gpWired: Dictionary = {}
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		_gpNoteWired(gpWired, gpE.gpFromRef)
		_gpNoteWired(gpWired, gpE.gpToRef)
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		var gpDef: GPSymbolDef = gpLookup.get(gpN.gpSymbolId) as GPSymbolDef
		if gpDef == null:
			continue
		# A mounted PART is not wired on its own behalf: its host's port is what the network
		# connects to. Reporting its spare nozzles would flood every vessel with findings.
		# 挂载**部件**不为它自己接线：网络接的是宿主的端口。报它的空管口会让每台设备都爆红。
		if gpN.gpParentUid != "":
			continue
		for gpP in gpDef.gpPorts:
			if gpP == null or not gpP.gpRequired:
				continue
			if gpWired.has(gpN.gpInstanceId + "/" + gpP.gpName):
				continue
			gpOut.append(GPFinding.gpMake(GP_RULE_PORT, GPFinding.GP_ERROR,
				"drc.port_unconnected", [gpN.gpInstanceId, gpP.gpName]).gpOnNode(
					gpN.gpInstanceId, gpN.gpPosition))


# Rule 3 — tags: missing (where one is due) or duplicated.
# 规则 3 —— 位号：该有时缺失，或重复。
static func _gpRuleTags(gpGraph: GPPIDGraph, gpLookup: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	var gpSeen: Dictionary = {}
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		# Mounted parts are identified by nozzle_id, not by a tag (ADR-23 D6).
		# 挂载部件凭 nozzle_id 标识而非位号（ADR-23 D6）。
		var gpIsPart: bool = gpN.gpParentUid != ""
		var gpDef: GPSymbolDef = gpLookup.get(gpN.gpSymbolId) as GPSymbolDef
		# Presentation-only symbols (flow arrows, frames) have no tag by design.
		# 纯呈现图元（流向箭头、图框）本来就无位号。
		var gpIsPresentation: bool = gpDef != null and gpDef.gpCategory == "annotation"
		if gpIsPart or gpIsPresentation:
			continue
		var gpTag: String = gpN.gpTag.strip_edges()
		if gpTag == "":
			gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_ERROR,
				"drc.tag_missing", [gpN.gpInstanceId]).gpOnNode(gpN.gpInstanceId, gpN.gpPosition))
			continue
		if gpSeen.has(gpTag):
			gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_ERROR,
				"drc.tag_duplicate", [gpTag, str(gpSeen[gpTag]), gpN.gpInstanceId]).gpOnNode(
					gpN.gpInstanceId, gpN.gpPosition))
		else:
			gpSeen[gpTag] = gpN.gpInstanceId
	for gpE in gpGraph.gpEdges:
		if gpE == null or gpE.gpKind == GPPIDEdge.GP_SIGNAL:
			continue
		if gpE.gpTag.strip_edges() == "":
			gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_WARNING,
				"drc.edge_tag_missing", [gpE.gpInstanceId]).gpOnEdge(gpE.gpInstanceId,
					_gpEdgeMid(gpGraph, gpE)))


# Rule 4 — required properties of the symbol schema must be filled.
# 规则 4 —— 图元 schema 中标记为必需的属性必须填写。
static func _gpRuleProps(gpGraph: GPPIDGraph, gpLookup: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		var gpDef: GPSymbolDef = gpLookup.get(gpN.gpSymbolId) as GPSymbolDef
		if gpDef == null or gpDef.gpSchema == null:
			continue
		for gpKey in gpDef.gpSchema.gpKeys():
			var gpF: GPPropertyDef = gpDef.gpSchema.gpFieldByKey(gpKey)
			if gpF == null or not gpF.gpRequired:
				continue
			if gpF.gpIsEmpty(gpN.gpProps.get(gpKey, null)):
				gpOut.append(GPFinding.gpMake(GP_RULE_PROPS, GPFinding.GP_ERROR,
					"drc.required_prop_missing", [gpN.gpInstanceId, gpKey]).gpOnNode(
						gpN.gpInstanceId, gpN.gpPosition))


# Rule 5 — layout: overlapping symbols, symbols off the sheet, lines cutting through symbols.
# 规则 5 —— 布局：图元重叠、越出图纸、连线穿越图元。
static func _gpRuleLayout(gpGraph: GPPIDGraph, gpLookup: Dictionary, gpSheet: GPSheet,
		gpOut: Array[GPFinding]) -> void:
	var gpRects: Dictionary = {}
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		gpRects[gpN.gpInstanceId] = _gpNodeRect(gpN, gpLookup)
	# Overlaps: every unordered pair, skipping mount parent/child (nesting is intended).
	# 重叠：每个无序对，跳过挂载父子（嵌套是刻意的）。
	var gpIds: Array[String] = []
	for gpId in gpRects.keys():
		gpIds.append(str(gpId))
	for gpI in range(gpIds.size()):
		for gpJ in range(gpI + 1, gpIds.size()):
			var gpAId: String = gpIds[gpI]
			var gpBId: String = gpIds[gpJ]
			if _gpIsMountRelated(gpGraph, gpAId, gpBId):
				continue
			var gpA: Rect2 = gpRects[gpAId] as Rect2
			var gpB: Rect2 = gpRects[gpBId] as Rect2
			if gpA.intersects(gpB):
				gpOut.append(GPFinding.gpMake(GP_RULE_LAYOUT, GPFinding.GP_WARNING,
					"drc.symbols_overlap", [gpAId, gpBId]).gpOnNode(gpAId, gpA.get_center()))
	# Off-sheet: the frame is the deliverable's edge.
	# 越出图纸：图框就是交付物的边界。
	if gpSheet != null and gpSheet.gpWidthMM > 0.0:
		var gpSheetRect: Rect2 = Rect2(Vector2.ZERO, Vector2(gpSheet.gpWidthMM, gpSheet.gpHeightMM))
		for gpId in gpIds:
			var gpR: Rect2 = gpRects[gpId] as Rect2
			if not gpSheetRect.encloses(gpR):
				gpOut.append(GPFinding.gpMake(GP_RULE_LAYOUT, GPFinding.GP_WARNING,
					"drc.symbol_off_sheet", [gpId]).gpOnNode(gpId, gpR.get_center()))
	# Lines cutting through symbols (other than their own endpoints).
	# 连线穿越图元（端点所属图元除外）。
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		var gpPts: PackedVector2Array = _gpEdgePolyline(gpGraph, gpE)
		if gpPts.size() < 2:
			continue
		var gpEndNodes: Array[String] = [str(gpE.gpFromRef.get("node_id", "")),
			str(gpE.gpToRef.get("node_id", ""))]
		for gpId in gpIds:
			if gpEndNodes.has(gpId):
				continue
			var gpR2: Rect2 = gpRects[gpId] as Rect2
			for gpK in range(gpPts.size() - 1):
				if gpR2.grow(-1.0).has_point(gpPts[gpK]) or gpR2.grow(-1.0).has_point(gpPts[gpK + 1]):
					gpOut.append(GPFinding.gpMake(GP_RULE_LAYOUT, GPFinding.GP_WARNING,
						"drc.edge_crosses_symbol", [gpE.gpInstanceId, gpId]).gpOnEdge(
							gpE.gpInstanceId, gpR2.get_center()))
					break


# Rule 6 — connection attribute completeness.
# 规则 6 —— 连线属性完整性。
static func _gpRuleEdgeAttrs(gpGraph: GPPIDGraph, gpOut: Array[GPFinding]) -> void:
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		if gpE.gpKind == GPPIDEdge.GP_SIGNAL:
			if gpE.gpSignalType.strip_edges() == "":
				gpOut.append(GPFinding.gpMake(GP_RULE_EDGE_ATTRS, GPFinding.GP_WARNING,
					"drc.signal_type_missing", [gpE.gpInstanceId]).gpOnEdge(gpE.gpInstanceId,
						_gpEdgeMid(gpGraph, gpE)))
			continue
		var gpMissing: Array[String] = []
		for gpKey in GP_REQUIRED_EDGE_ATTRS:
			if str(gpE.gpAttrs.get(gpKey, "")).strip_edges() == "":
				gpMissing.append(gpKey)
		if not gpMissing.is_empty():
			gpOut.append(GPFinding.gpMake(GP_RULE_EDGE_ATTRS, GPFinding.GP_WARNING,
				"drc.edge_attrs_missing", [gpE.gpInstanceId, ", ".join(gpMissing)]).gpOnEdge(
					gpE.gpInstanceId, _gpEdgeMid(gpGraph, gpE)))


# Rule 7 — sheet fit: too sparse or too crowded (info only: it is a judgement, not a defect).
# 规则 7 —— 图幅适配：过空或过挤（仅 info：这是判断，不是缺陷）。
static func _gpRuleSheetFit(gpGraph: GPPIDGraph, gpLookup: Dictionary, gpSheet: GPSheet,
		gpOut: Array[GPFinding]) -> void:
	if gpSheet == null or gpSheet.gpWidthMM <= 0.0 or gpSheet.gpHeightMM <= 0.0:
		return
	var gpSheetArea: float = gpSheet.gpWidthMM * gpSheet.gpHeightMM
	var gpUsed: Rect2 = Rect2()
	var gpFirst: bool = true
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		var gpR: Rect2 = _gpNodeRect(gpN, gpLookup)
		if gpFirst:
			gpUsed = gpR
			gpFirst = false
		else:
			gpUsed = gpUsed.merge(gpR)
	if gpFirst:
		return
	var gpRatio: float = (gpUsed.size.x * gpUsed.size.y) / gpSheetArea
	if gpRatio < GP_FIT_SPARSE:
		gpOut.append(GPFinding.gpMake(GP_RULE_SHEET_FIT, GPFinding.GP_INFO,
			"drc.sheet_sparse", [int(gpRatio * 100.0)]))
	elif gpRatio > GP_FIT_CROWDED:
		gpOut.append(GPFinding.gpMake(GP_RULE_SHEET_FIT, GPFinding.GP_INFO,
			"drc.sheet_crowded", [int(gpRatio * 100.0)]))


# --- helpers / 辅助 ---

# Note a wired (node, port) pair, ignoring entries without a real port.
# 记录一个已接线的（节点, 端口）对，忽略没有真实端口的条目。
static func _gpNoteWired(gpWired: Dictionary, gpRef: Dictionary) -> void:
	var gpNode: String = str(gpRef.get("node_id", ""))
	var gpPort: String = str(gpRef.get("port_id", ""))
	if gpNode != "" and gpPort != "":
		gpWired[gpNode + "/" + gpPort] = true


# Find an annotation by uid.
# 按 uid 找注释。
static func _gpFindShape(gpGraph: GPPIDGraph, gpUid: String) -> GPShape:
	for gpS in gpGraph.gpShapes:
		if gpS != null and gpS.gpUid == gpUid:
			return gpS
	return null


# The envelope rect of a node, from its symbol's default size (centre = gpPosition).
# 节点的包络矩形，取图元标称尺寸（中心 = gpPosition）。
static func _gpNodeRect(gpN: GPPIDNode, gpLookup: Dictionary) -> Rect2:
	var gpDef: GPSymbolDef = gpLookup.get(gpN.gpSymbolId) as GPSymbolDef
	var gpSize: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(20.0, 20.0)
	return Rect2(gpN.gpPosition - gpSize * 0.5, gpSize)


# Whether two nodes are mount-related in either direction.
# 两个节点是否为任一方向的挂载关系。
static func _gpIsMountRelated(gpGraph: GPPIDGraph, gpAId: String, gpBId: String) -> bool:
	var gpA: GPPIDNode = gpGraph.gpGetNode(gpAId)
	var gpB: GPPIDNode = gpGraph.gpGetNode(gpBId)
	if gpA == null or gpB == null:
		return false
	return gpA.gpParentUid == gpBId or gpB.gpParentUid == gpAId


# A rough polyline for an edge: routing when present, else node centres joined.
# 边的粗略折线：有走线用走线，否则直接连两节点中心。
static func _gpEdgePolyline(gpGraph: GPPIDGraph, gpE: GPPIDEdge) -> PackedVector2Array:
	if not gpE.gpRouting.is_empty():
		return gpE.gpRouting
	var gpFrom: String = str(gpE.gpFromRef.get("node_id", ""))
	var gpTo: String = str(gpE.gpToRef.get("node_id", ""))
	if gpFrom == "" or gpTo == "":
		return PackedVector2Array()
	var gpA: GPPIDNode = gpGraph.gpGetNode(gpFrom)
	var gpB: GPPIDNode = gpGraph.gpGetNode(gpTo)
	if gpA == null or gpB == null:
		return PackedVector2Array()
	return PackedVector2Array([gpA.gpPosition, gpB.gpPosition])


# Middle of an edge, for "jump to" positioning.
# 边的中点，供「跳转到」定位。
static func _gpEdgeMid(gpGraph: GPPIDGraph, gpE: GPPIDEdge) -> Vector2:
	var gpPts: PackedVector2Array = _gpEdgePolyline(gpGraph, gpE)
	if gpPts.is_empty():
		return Vector2.INF
	if gpPts.size() == 1:
		return gpPts[0]
	return (gpPts[0] + gpPts[gpPts.size() - 1]) * 0.5
