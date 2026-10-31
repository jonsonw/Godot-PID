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
#   * rule 5 judges RESOLVED geometry (mount chain + port anchors + the same ortho router the
#     renderer uses) and treats one mount assembly as a rigid body: a child over its host, two
#     sibling nozzles, and a pipe meeting its own nozzle are nesting, not overlaps / crossings.
#   * 规则 2 只报**图元自己标记**为必需的端口 —— 空置管口是常态；
#   * 规则 3 排除挂载部件（凭 nozzle_id 标识而非位号，ADR-23）与信号线（回路号属 I14 的缺口，
#     不是缺管线号）；
#   * 规则 5 判**已解析**几何（挂载父链 + 端口锚点 + 渲染同款正交布线），并把一个挂载装配体
#     当作刚体：子件压宿主、兄弟管口相邻、管线接自己的管口，都属嵌套而非重叠 / 穿越。
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

# Layout tolerance in millimetres: envelopes closer than this are treated as touching, not
# overlapping, and a line running exactly along a symbol's edge is not "inside" it. Chosen well
# below the smallest real symbol (a nozzle is 8 x 4 mm), so it can only absorb float noise and
# deliberate flush mounting.
# 布局容差（毫米）：包络相距小于此值视作相切而非重叠；沿图元边缘走的线也不算「进入」。取值
# 远小于最小真实图元（管口 8 x 4 mm），故只会吸收浮点噪声与刻意的贴壁安装。
const GP_LAYOUT_TOL: float = 0.5


# Run all seven rules. Deterministic order: by rule id, then by position, then by object id — so
# two runs on the same graph produce byte-identical reports (E01's acceptance).
# 跑全部七条。顺序确定：先规则号、再位置、再对象 id —— 故同一张图两次运行产出逐字节相同的报告
#（E01 的验收项）。
# `gpSkipTags` lets the PROJECT audit own rule 3 (see gpRunProject): running both would report
# every within-sheet duplicate twice.
# `gpSkipTags` 让**工程**审计接管规则 3（见 gpRunProject）：两者都跑会把同页重复报两遍。
static func gpRun(gpGraph: GPPIDGraph, gpSheet: GPSheet,
		gpDefs: Array[GPSymbolDef] = [], gpSkipTags: bool = false) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	if gpGraph == null:
		return gpOut
	var gpLookup: Dictionary = {}
	for gpD in gpDefs:
		if gpD != null:
			gpLookup[gpD.gpId] = gpD
	_gpRuleDangling(gpGraph, gpLookup, gpOut)
	_gpRulePorts(gpGraph, gpLookup, gpOut)
	if not gpSkipTags:
		_gpRuleTags(gpGraph, gpLookup, gpOut)
	_gpRuleProps(gpGraph, gpLookup, gpOut)
	_gpRuleLayout(gpGraph, gpLookup, gpSheet, gpOut)
	_gpRuleEdgeAttrs(gpGraph, gpLookup, gpOut)
	_gpRuleSheetFit(gpGraph, gpLookup, gpSheet, gpOut)
	gpOut.sort_custom(_gpSortLess)
	return gpOut


# Run every rule over EVERY sheet, with the project-wide tag audit standing in for rule 3.
# 在**每张**图纸上跑全部规则，并由工程级位号审计接管规则 3。
# Why rule 3 is swapped out / 为何换掉规则 3：
# uniqueness is a project property. Keeping the per-sheet version would (a) report within-sheet
# duplicates twice and (b) miss every cross-sheet duplicate — the exact defect this work exists
# to catch.
# 唯一性是工程属性。保留逐图纸版本会（a）把同页重复报两遍、（b）漏掉所有跨页重复 ——
# 而后者正是这轮工作要抓的缺陷。
static func gpRunProject(gpSheets: Array, gpDefs: Array[GPSymbolDef] = [],
		gpStd: GPProjectStandard = null) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null or gpSheet.gpGraph == null:
			continue
		gpOut.append_array(gpRun(gpSheet.gpGraph, gpSheet, gpDefs, true))
	gpOut.append_array(GPTagAudit.gpRun(gpSheets, gpDefs, gpStd))
	gpOut.sort_custom(_gpSortLess)
	return gpOut


# Deterministic ordering shared by both entry points: rule id, world position, node id, edge id.
# 两个入口共用的确定排序：规则号、位置、节点 id、连线 id。
static func _gpSortLess(gpA: GPFinding, gpB: GPFinding) -> bool:
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
	return gpA.gpEdgeId < gpB.gpEdgeId


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
static func _gpRuleDangling(gpGraph: GPPIDGraph, gpLookup: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		var gpEdgeLabel: String = _gpEdgeLabel(gpGraph, gpLookup, gpE)
		for gpIsFrom in [true, false]:
			if not gpE.gpIsDangling(gpIsFrom):
				continue
			var gpUid: String = gpE.gpEndNoteUid(gpIsFrom)
			var gpWorld: Vector2 = gpE.gpDanglingPoint(gpIsFrom)
			var gpSide: String = "from" if gpIsFrom else "to"
			if gpUid == "":
				gpOut.append(GPFinding.gpMake(GP_RULE_DANGLING, GPFinding.GP_ERROR,
					"drc.end_note_missing", [gpEdgeLabel, gpSide]).gpOnEdge(
						gpE.gpInstanceId, gpWorld))
				continue
			var gpNote: GPShape = _gpFindShape(gpGraph, gpUid)
			if gpNote == null:
				gpOut.append(GPFinding.gpMake(GP_RULE_DANGLING, GPFinding.GP_ERROR,
					"drc.end_note_missing_object", [gpEdgeLabel, gpSide]).gpOnEdge(
						gpE.gpInstanceId, gpWorld))
			elif gpNote.gpText.strip_edges() == "":
				gpOut.append(GPFinding.gpMake(GP_RULE_DANGLING, GPFinding.GP_ERROR,
					"drc.end_note_empty_text", [gpEdgeLabel, gpSide]).gpOnEdge(
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
				"drc.port_unconnected", [_gpNodeLabel(gpGraph, gpLookup, gpN.gpInstanceId),
					gpP.gpName]).gpOnNode(gpN.gpInstanceId, gpN.gpPosition))


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
				"drc.tag_missing", [_gpNodeLabel(gpGraph, gpLookup, gpN.gpInstanceId)]).gpOnNode(
					gpN.gpInstanceId, gpN.gpPosition))
			continue
		if gpSeen.has(gpTag):
			gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_ERROR,
				"drc.tag_duplicate", [gpTag, _gpNodeLabel(gpGraph, gpLookup,
					str(gpSeen[gpTag])), _gpNodeLabel(gpGraph, gpLookup, gpN.gpInstanceId)]).gpOnNode(
					gpN.gpInstanceId, gpN.gpPosition))
		else:
			gpSeen[gpTag] = gpN.gpInstanceId
	for gpE in gpGraph.gpEdges:
		if gpE == null or gpE.gpKind == GPPIDEdge.GP_SIGNAL:
			continue
		if gpE.gpTag.strip_edges() == "":
			gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_WARNING,
				"drc.edge_tag_missing", [_gpEdgeLabel(gpGraph, gpLookup, gpE)]).gpOnEdge(
					gpE.gpInstanceId, _gpEdgeMid(gpGraph, gpLookup, gpE)))


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
					"drc.required_prop_missing", [_gpNodeLabel(gpGraph, gpLookup, gpN.gpInstanceId),
						gpKey]).gpOnNode(gpN.gpInstanceId,
							_gpNodeWorld(gpGraph, gpLookup, gpN)))


# Rule 5 — layout: overlapping symbols, symbols off the sheet, lines cutting through symbols.
# 规则 5 —— 布局：图元重叠、越出图纸、连线穿越图元。
#
# ★ THE ONE RULE THAT MUST USE RESOLVED GEOMETRY / ★ 最必须使用「已解析几何」的一条规则：
# a mounted child stores NO world coordinate — its origin and rotation are derived from the host
# chain (GPMountResolver). Reading `gpN.gpPosition` here is what made a real drawing report ten
# overlaps between sibling nozzles and six lines "crossing" their own vessel: every nozzle of a
# host carried the SAME stale point. Edge geometry has the mirror-image trap: `gpRouting` holds
# only the MIDDLE waypoints, so joining it (or node centres) is not the line the user sees. This
# rule therefore goes through the same two resolvers the renderer uses (GPPortResolver +
# GPEdgeRoute), and treats nodes of ONE mount assembly as a single rigid body.
# 挂载子件**不存**世界坐标 —— 原点与朝向由宿主父链推导（GPMountResolver）。在此读取
# `gpN.gpPosition` 正是真实图纸报出「兄弟管口两两重叠」与「六条线穿过自己容器」的原因：
# 同一宿主的每个管口都带着**同一个**过期点。连线几何有镜像陷阱：`gpRouting` 只存**中间**折点，
# 故直接拼接它（或节点中心）并不是用户看到的那条线。因此本条规则走渲染器同款的两个解析器
#（GPPortResolver + GPEdgeRoute），并把**同一挂载装配体**的节点视为一个刚体。
static func _gpRuleLayout(gpGraph: GPPIDGraph, gpLookup: Dictionary, gpSheet: GPSheet,
		gpOut: Array[GPFinding]) -> void:
	var gpDefLookup: Callable = _gpDefLookup(gpLookup)
	var gpRects: Dictionary = {}
	# Mount-assembly root per node: all parts of one host share a root. Overlap between two
	# members of one assembly is NESTING (mounting is meant to nest), not a layout defect.
	# 每个节点的挂载装配体根：同一宿主的所有部件共享一个根。同一装配体内两成员的重叠是**嵌套**
	#（挂载本就意味着嵌套），不是布局缺陷。
	var gpRoots: Dictionary = {}
	var gpIds: Array[String] = []
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		gpRects[gpN.gpInstanceId] = _gpNodeRect(gpGraph, gpDefLookup, gpN)
		gpRoots[gpN.gpInstanceId] = _gpAssemblyRootId(gpGraph, gpN)
		gpIds.append(gpN.gpInstanceId)
	# Overlaps: every unordered pair of DIFFERENT assemblies.
	# 重叠：每个**不同装配体**之间的无序对。
	for gpI in range(gpIds.size()):
		for gpJ in range(gpI + 1, gpIds.size()):
			var gpAId: String = gpIds[gpI]
			var gpBId: String = gpIds[gpJ]
			if gpRoots[gpAId] == gpRoots[gpBId]:
				continue
			var gpA: Rect2 = gpRects[gpAId] as Rect2
			var gpB: Rect2 = gpRects[gpBId] as Rect2
			# Shrink by the tolerance so two envelopes that merely TOUCH (a nozzle flush on a
			# vessel wall, a part sitting on a neighbour) are not reported as overlapping.
			# 按容差收缩，使「仅仅相切」的包络（贴壁的管口、靠着邻件的部件）不算重叠。
			if gpA.grow(-GP_LAYOUT_TOL).intersects(gpB.grow(-GP_LAYOUT_TOL)):
				gpOut.append(GPFinding.gpMake(GP_RULE_LAYOUT, GPFinding.GP_WARNING,
					"drc.symbols_overlap", [_gpNodeLabel(gpGraph, gpLookup, gpAId),
						_gpNodeLabel(gpGraph, gpLookup, gpBId)]).gpOnNode(gpAId,
							gpA.get_center()))
	# Off-sheet: the frame is the deliverable's edge. Resolved rects, so a part hanging over the
	# frame is judged by where it actually IS.
	# 越出图纸：图框就是交付物的边界。用已解析矩形，故挂在图框外的部件按它**实际所在**判定。
	if gpSheet != null and gpSheet.gpWidthMM > 0.0:
		var gpSheetRect: Rect2 = Rect2(Vector2.ZERO, Vector2(gpSheet.gpWidthMM, gpSheet.gpHeightMM))
		for gpId in gpIds:
			var gpR: Rect2 = gpRects[gpId] as Rect2
			if not gpSheetRect.encloses(gpR):
				gpOut.append(GPFinding.gpMake(GP_RULE_LAYOUT, GPFinding.GP_WARNING,
					"drc.symbol_off_sheet", [_gpNodeLabel(gpGraph, gpLookup, gpId)]).gpOnNode(
						gpId, gpR.get_center()))
	# Lines cutting through symbols. Excluded: the edge's endpoint assemblies — a pipe that
	# terminates on a nozzle is ALLOWED to meet that nozzle, its host and its sibling parts; the
	# connection point is on them by definition.
	# 连线穿越图元。排除：连线端点所属的**整个装配体** —— 接在管口上的管线本就允许接触该管口、
	# 其宿主与其兄弟部件；连接点按定义就在它们身上。
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		var gpPts: PackedVector2Array = _gpEdgePolyline(gpGraph, gpDefLookup, gpE)
		if gpPts.size() < 2:
			continue
		var gpSkipRoots: Dictionary = {}
		for gpEndKey in ["from", "to"]:
			var gpRef: Dictionary = gpE.gpFromRef if gpEndKey == "from" else gpE.gpToRef
			var gpEndId: String = str(gpRef.get("node_id", ""))
			if gpRoots.has(gpEndId):
				gpSkipRoots[gpRoots[gpEndId]] = true
		for gpId in gpIds:
			if gpSkipRoots.has(gpRoots[gpId]):
				continue
			var gpR2: Rect2 = gpRects[gpId] as Rect2
			if _gpPolylineHitsRect(gpPts, gpR2.grow(-GP_LAYOUT_TOL)):
				gpOut.append(GPFinding.gpMake(GP_RULE_LAYOUT, GPFinding.GP_WARNING,
					"drc.edge_crosses_symbol", [_gpEdgeLabel(gpGraph, gpLookup, gpE),
						_gpNodeLabel(gpGraph, gpLookup, gpId)]).gpOnEdge(
							gpE.gpInstanceId, gpR2.get_center()))


# Rule 6 — connection attribute completeness.
# 规则 6 —— 连线属性完整性。
static func _gpRuleEdgeAttrs(gpGraph: GPPIDGraph, gpLookup: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		var gpEdgeLabel: String = _gpEdgeLabel(gpGraph, gpLookup, gpE)
		if gpE.gpKind == GPPIDEdge.GP_SIGNAL:
			if gpE.gpSignalType.strip_edges() == "":
				gpOut.append(GPFinding.gpMake(GP_RULE_EDGE_ATTRS, GPFinding.GP_WARNING,
					"drc.signal_type_missing", [gpEdgeLabel]).gpOnEdge(gpE.gpInstanceId,
						_gpEdgeMid(gpGraph, gpLookup, gpE)))
			continue
		var gpMissing: Array[String] = []
		for gpKey in GP_REQUIRED_EDGE_ATTRS:
			if str(gpE.gpAttrs.get(gpKey, "")).strip_edges() == "":
				gpMissing.append(gpKey)
		if not gpMissing.is_empty():
			gpOut.append(GPFinding.gpMake(GP_RULE_EDGE_ATTRS, GPFinding.GP_WARNING,
				"drc.edge_attrs_missing", [gpEdgeLabel, ", ".join(gpMissing)]).gpOnEdge(
					gpE.gpInstanceId, _gpEdgeMid(gpGraph, gpLookup, gpE)))


# Rule 7 — sheet fit: too sparse or too crowded (info only: it is a judgement, not a defect).
# 规则 7 —— 图幅适配：过空或过挤（仅 info：这是判断，不是缺陷）。
static func _gpRuleSheetFit(gpGraph: GPPIDGraph, gpLookup: Dictionary, gpSheet: GPSheet,
		gpOut: Array[GPFinding]) -> void:
	if gpSheet == null or gpSheet.gpWidthMM <= 0.0 or gpSheet.gpHeightMM <= 0.0:
		return
	var gpDefLookup: Callable = _gpDefLookup(gpLookup)
	var gpSheetArea: float = gpSheet.gpWidthMM * gpSheet.gpHeightMM
	var gpUsed: Rect2 = Rect2()
	var gpFirst: bool = true
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		var gpR: Rect2 = _gpNodeRect(gpGraph, gpDefLookup, gpN)
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

# The definition lookup the two geometry resolvers expect.
# 两个几何解析器所需的「定义查询」函数。
static func _gpDefLookup(gpLookup: Dictionary) -> Callable:
	return func(gpSymbolId: String) -> GPSymbolDef:
		return gpLookup.get(gpSymbolId) as GPSymbolDef


# User-facing label for a node: "T-1002 (n1)", "T-1002/N1 (n2)", or the bare id when nothing
# better is known. The technical id is KEPT in parentheses so a support session can still find
# the object, while the electrician reading the report sees the tag.
# 节点的用户可读标签：「T-1002 (n1)」「T-1002/N1 (n2)」，无更好信息时用裸 id。
# 技术 id **保留**在括号里，便于支持时定位对象；看报告的人先看到位号。
static func _gpNodeLabel(gpGraph: GPPIDGraph, gpLookup: Dictionary, gpId: String) -> String:
	if gpId == "":
		return ""
	var gpN: GPPIDNode = gpGraph.gpGetNode(gpId)
	if gpN == null:
		return gpId
	var gpName: String = ""
	if gpN.gpParentUid != "":
		var gpParent: GPPIDNode = gpGraph.gpGetNode(gpN.gpParentUid)
		var gpHost: String = gpN.gpParentUid
		if gpParent != null and gpParent.gpTag.strip_edges() != "":
			gpHost = gpParent.gpTag
		var gpPart: String = str(gpN.gpProps.get("nozzle_id",
			gpN.gpProps.get("manhole_id", "")))
		if gpPart == "":
			gpPart = gpN.gpMountAnchor
		gpName = gpHost + "/" + gpPart if gpPart != "" else gpHost
	elif gpN.gpTag.strip_edges() != "":
		gpName = gpN.gpTag
	else:
		var gpDef: GPSymbolDef = gpLookup.get(gpN.gpSymbolId) as GPSymbolDef
		if gpDef != null and gpDef.gpDisplayName.strip_edges() != "":
			gpName = gpDef.gpDisplayName
		else:
			gpName = gpN.gpSymbolId
	if gpName == "" or gpName == gpId:
		return gpId
	return "%s (%s)" % [gpName, gpId]


# User-facing label for an edge: tag when it has one, otherwise the two end labels.
# 连线的用户可读标签：有号用号，否则用两端标签。
static func _gpEdgeLabel(gpGraph: GPPIDGraph, gpLookup: Dictionary,
		gpE: GPPIDEdge) -> String:
	var gpTag: String = gpE.gpTag.strip_edges()
	if gpTag != "":
		return "%s (%s)" % [gpTag, gpE.gpInstanceId]
	var gpFrom: String = _gpNodeLabel(gpGraph, gpLookup, str(gpE.gpFromRef.get("node_id", "")))
	var gpTo: String = _gpNodeLabel(gpGraph, gpLookup, str(gpE.gpToRef.get("node_id", "")))
	if gpFrom == "" and gpTo == "":
		return gpE.gpInstanceId
	return "%s (%s → %s)" % [gpE.gpInstanceId, gpFrom, gpTo]


# World origin of a node, mount chain folded in.
# 节点的世界原点，已计入挂载父链。
static func _gpNodeWorld(gpGraph: GPPIDGraph, gpLookup: Dictionary,
		gpN: GPPIDNode) -> Vector2:
	return GPPortResolver.gpNodeWorldOrigin(gpGraph, _gpDefLookup(gpLookup), gpN)


# Root of a node's mount assembly: walk parents with a cycle guard; a top-level node is its own
# root. Every part of one host shares the root, so "same root" == "one rigid assembly".
# 节点所属挂载装配体的根：带环护栏上溯父链；顶层节点的根就是它自己。同一宿主的所有部件共享
# 该根，故「同根」==「同一刚体装配」。
static func _gpAssemblyRootId(gpGraph: GPPIDGraph, gpN: GPPIDNode) -> String:
	var gpCur: GPPIDNode = gpN
	var gpSeen: Dictionary = {}
	while gpCur != null and gpCur.gpParentUid != "":
		if gpSeen.has(gpCur.gpInstanceId):
			break
		gpSeen[gpCur.gpInstanceId] = true
		var gpParent: GPPIDNode = gpGraph.gpGetNode(gpCur.gpParentUid)
		if gpParent == null:
			break
		gpCur = gpParent
	return gpCur.gpInstanceId if gpCur != null else gpN.gpInstanceId


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


# The world-space envelope rect of a node. Origin and rotation come from the mount chain; the
# size is the symbol's nominal envelope. A rotated symbol contributes its rotated AABB (still
# conservative, but no longer at a stale coordinate).
# 节点的**世界**包络矩形。原点与旋转取自挂载父链；尺寸取图元标称包络。旋转图元取旋转后的
# 轴对齐包围盒（仍是保守估计，但不再落在过期坐标上）。
static func _gpNodeRect(gpGraph: GPPIDGraph, gpDefLookup: Callable,
		gpN: GPPIDNode) -> Rect2:
	var gpDef: GPSymbolDef = GPMountResolver.gpDefFor(gpDefLookup, gpN.gpSymbolId)
	var gpSize: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(20.0, 20.0)
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpGraph, gpDefLookup, gpN)
	var gpOrigin: Vector2 = gpWT.get("origin", gpN.gpPosition)
	var gpRot: float = float(gpWT.get("rot_deg", 0.0))
	var gpHalf: Vector2 = gpSize * 0.5
	if is_zero_approx(gpRot):
		return Rect2(gpOrigin - gpHalf, gpSize)
	var gpMin: Vector2 = Vector2(INF, INF)
	var gpMax: Vector2 = Vector2(-INF, -INF)
	for gpSx in [-1.0, 1.0]:
		for gpSy in [-1.0, 1.0]:
			var gpP: Vector2 = gpOrigin + Vector2(gpHalf.x * gpSx, gpHalf.y * gpSy).rotated(
				deg_to_rad(gpRot))
			gpMin = gpMin.min(gpP)
			gpMax = gpMax.max(gpP)
	return Rect2(gpMin, gpMax - gpMin)


# Whether any segment of a polyline enters the rect. Segment-vs-rect, NOT vertex-in-rect: a
# straight run through a symbol has no vertex inside it, which is precisely the case the old
# vertex-only test missed.
# 折线的任一段是否进入矩形。是「线段 × 矩形」而非「顶点落矩形内」：直穿图元的线段没有任何
# 顶点在其中 —— 这正是旧「仅顶点」判定漏掉的情形。
static func _gpPolylineHitsRect(gpPts: PackedVector2Array, gpRect: Rect2) -> bool:
	if gpRect.size.x <= 0.0 or gpRect.size.y <= 0.0:
		return false
	for gpI in range(gpPts.size() - 1):
		if _gpSegmentHitsRect(gpPts[gpI], gpPts[gpI + 1], gpRect):
			return true
	return false


# Whether one segment intersects (or lies inside) a rect.
# 一条线段是否与矩形相交（或落在矩形内）。
static func _gpSegmentHitsRect(gpP0: Vector2, gpP1: Vector2, gpRect: Rect2) -> bool:
	if gpRect.has_point(gpP0) or gpRect.has_point(gpP1):
		return true
	var gpA: Vector2 = gpRect.position
	var gpB: Vector2 = Vector2(gpRect.end.x, gpRect.position.y)
	var gpC: Vector2 = gpRect.end
	var gpD: Vector2 = Vector2(gpRect.position.x, gpRect.end.y)
	return Geometry2D.segment_intersects_segment(gpP0, gpP1, gpA, gpB) != null \
		or Geometry2D.segment_intersects_segment(gpP0, gpP1, gpB, gpC) != null \
		or Geometry2D.segment_intersects_segment(gpP0, gpP1, gpC, gpD) != null \
		or Geometry2D.segment_intersects_segment(gpP0, gpP1, gpD, gpA) != null


# The polyline the USER SEES: the same two resolvers the renderer uses. gpRouting alone is only
# the middle waypoints, and node centres are not the endpoints when a port is bound.
# 用户**看到**的折线：与渲染器同款的两个解析器。单用 gpRouting 只是中间折点；端口已绑定时，
# 节点中心也不是端点。
static func _gpEdgePolyline(gpGraph: GPPIDGraph, gpDefLookup: Callable,
		gpE: GPPIDEdge) -> PackedVector2Array:
	var gpWant: String = GPPortResolver.gpWantTypeFor(gpE)
	var gpA: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpDefLookup, gpE, true, gpWant)
	var gpB: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpDefLookup, gpE, false, gpWant)
	return GPEdgeRoute.gpRoute(gpA, gpB, gpE.gpRouting, gpE.gpOrtho)


# Middle of an edge, for "jump to" positioning.
# 边的中点，供「跳转到」定位。
static func _gpEdgeMid(gpGraph: GPPIDGraph, gpLookup: Dictionary, gpE: GPPIDEdge) -> Vector2:
	var gpPts: PackedVector2Array = _gpEdgePolyline(gpGraph, _gpDefLookup(gpLookup), gpE)
	if gpPts.is_empty():
		return Vector2.INF
	if gpPts.size() == 1:
		return gpPts[0]
	return (gpPts[0] + gpPts[gpPts.size() - 1]) * 0.5
