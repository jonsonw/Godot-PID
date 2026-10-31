class_name GPDrcSnapshot
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Resolved, read-only drawing snapshot for DRC (ADR-39 D1). Every geometric question a rule may
# ask — where is a node, where does a pipe end, which assembly does a part belong to — is answered
# HERE, once, through the same resolvers the renderer uses. Rules never read raw gpPosition /
# gpRouting / gpParentUid again.
# DRC 的已解析只读快照（ADR-39 D1）。规则可能问的每个几何问题 —— 图元在哪、管线端在哪、
# 部件属于哪个装配体 —— 都在**这里**通过渲染器同款解析器一次算好。规则不再裸读
# gpPosition / gpRouting / gpParentUid。
#
# Why this exists / 为何存在：
# the 2026-10-28 incident (18 false warnings on one line + two devices) was not one bad rule; it
# was every rule interpreting raw fields differently. One snapshot makes that class of bug
# structurally impossible.
# 2026-10-28 的事故（一根线 + 两台设备报 18 条假警告）不是某条规则写错，而是每条规则各自解释
# 原始字段。快照层让这一类缺陷在结构上不可能再出现。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var graph: GPPIDGraph = null
var sheet: GPSheet = null
var std: GPProjectStandard = null

# Symbol-definition lookup, as the two geometry resolvers expect it.
# 图元定义查询，供两个几何解析器使用。
var def_lookup: Callable = Callable()

# id -> definition (dictionary form, for O(1) reads and old call sites).
# id -> 定义（字典形态，供 O(1) 读取与旧调用点）。
var defs: Dictionary = {}

# id -> {node, def, uid, origin, rot, rect, root, is_part, label, label_rect, ports}
# id -> {node, def, uid, origin, rot, rect, root, is_part, label, label_rect, ports}
var nodes: Dictionary = {}

# id -> {edge, uid, from, to, polyline, label, from_id, to_id}
# id -> {edge, uid, from, to, polyline, label, from_id, to_id}
var edges: Dictionary = {}

# Annotation shapes, in graph order (the shape index is their handle).
# 注释图形，按图顺序（下标即句柄）。
var shapes: Array = []

# Normalised tag -> Array of node / edge ids (project uniqueness is audited elsewhere; this is
# only for the cheap local checks).
# 归一化位号 -> 节点 / 连线 id 数组（工程唯一性由别处审计；这里只服务本地廉价检查）。
var tag_index: Dictionary = {}

# "node_id/port_id" -> Array of edge ids.
# "node_id/port_id" -> 连线 id 数组。
var port_edges: Dictionary = {}

# Sheet identifiers and rectangles, in world millimetres.
# 图纸标识与世界毫米矩形。
var sheet_id: String = ""
var paper_rect: Rect2 = Rect2()
var frame_rect: Rect2 = Rect2()
var title_rect: Rect2 = Rect2()

const GP_LABEL_CHAR_W: float = 3.2
const GP_LABEL_H: float = 6.0


# Build the snapshot for one sheet. Pure: reads the graph, never mutates it.
# 为一张图纸构建快照。纯函数：只读图，绝不修改。
static func gpBuild(gpGraph: GPPIDGraph, gpSheet: GPSheet,
		gpDefs: Array[GPSymbolDef] = [], gpStd: GPProjectStandard = null) -> GPDrcSnapshot:
	var gpS: GPDrcSnapshot = GPDrcSnapshot.new()
	gpS.graph = gpGraph
	gpS.sheet = gpSheet
	gpS.std = gpStd
	for gpD in gpDefs:
		if gpD != null:
			gpS.defs[gpD.gpId] = gpD
	gpS.def_lookup = func(gpId: String) -> GPSymbolDef:
		return gpS.defs.get(gpId) as GPSymbolDef
	if gpGraph == null:
		return gpS
	if gpSheet != null:
		gpS.sheet_id = gpSheet.gpId
		if gpSheet.gpWidthMM > 0.0 and gpSheet.gpHeightMM > 0.0:
			gpS.paper_rect = Rect2(Vector2.ZERO,
				Vector2(gpSheet.gpWidthMM, gpSheet.gpHeightMM))
		if gpSheet.gpHeightMM > 0.0:
			gpS.frame_rect = GPFrameGeometry.gpFrameRect(gpSheet)
			gpS.title_rect = GPFrameGeometry.gpTitleBlockRect(gpSheet)
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		gpS._gpBuildNode(gpN)
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		gpS._gpBuildEdge(gpE)
	gpS.shapes = gpGraph.gpShapes.duplicate()
	return gpS


# Build one node entry (resolved through the mount chain).
# 构建一个节点条目（经挂载父链解析）。
func _gpBuildNode(gpN: GPPIDNode) -> void:
	var gpDef: GPSymbolDef = defs.get(gpN.gpSymbolId) as GPSymbolDef
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(graph, def_lookup, gpN)
	var gpOrigin: Vector2 = gpWT.get("origin", gpN.gpPosition)
	var gpRot: float = float(gpWT.get("rot_deg", 0.0))
	var gpSize: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(20.0, 20.0)
	var gpRect: Rect2 = gpRectAt(gpOrigin, gpSize, gpRot)
	var gpLabel: String = gpNodeLabel(gpN.gpInstanceId)
	var gpEntry: Dictionary = {
		"node": gpN,
		"def": gpDef,
		"uid": gpN.gpRefId(),
		"origin": gpOrigin,
		"rot": gpRot,
		"rect": gpRect,
		"root": _gpRootOf(gpN),
		"is_part": gpN.gpParentUid != "",
		"label": gpLabel,
		"label_rect": gpLabelRect(gpRect, gpLabel),
		"ports": {},
	}
	if gpDef != null:
		for gpP in gpDef.gpPorts:
			if gpP == null:
				continue
			var gpPos: Vector2 = GPPortResolver.gpPortWorld(graph, def_lookup, gpDef, gpN, gpP)
			var gpDir: Vector2 = GPPortResolver.gpPortWorldDir(graph, def_lookup, gpN, gpP)
			(gpEntry["ports"] as Dictionary)[gpP.gpName] = {
				"port": gpP, "pos": gpPos, "dir": gpDir, "type": gpP.gpType,
			}
	nodes[gpN.gpInstanceId] = gpEntry


# Build one edge entry (resolved through ports + the same router the renderer uses).
# 构建一个连线条目（经端口 + 渲染器同款布线解析）。
func _gpBuildEdge(gpE: GPPIDEdge) -> void:
	var gpWant: String = GPPortResolver.gpWantTypeFor(gpE)
	var gpFrom: Dictionary = GPPortResolver.gpResolveEnd(graph, def_lookup, gpE, true, gpWant)
	var gpTo: Dictionary = GPPortResolver.gpResolveEnd(graph, def_lookup, gpE, false, gpWant)
	var gpPoly: PackedVector2Array = GPEdgeRoute.gpRoute(gpFrom, gpTo, gpE.gpRouting, gpE.gpOrtho)
	var gpFromId: String = str(gpE.gpFromRef.get("node_id", ""))
	var gpToId: String = str(gpE.gpToRef.get("node_id", ""))
	var gpEntry: Dictionary = {
		"edge": gpE,
		"uid": gpE.gpInstanceId,
		"from": gpFrom,
		"to": gpTo,
		"polyline": gpPoly,
		"label": gpEdgeLabel(gpE.gpInstanceId),
		"from_id": gpFromId,
		"to_id": gpToId,
	}
	edges[gpE.gpInstanceId] = gpEntry
	if gpE.gpTag.strip_edges() != "":
		var gpNorm: String = GPTagRegistry.gpNormalize(gpE.gpTag)
		if not tag_index.has(gpNorm):
			tag_index[gpNorm] = []
		(tag_index[gpNorm] as Array).append(gpE.gpInstanceId)
	for gpRef in [gpE.gpFromRef, gpE.gpToRef]:
		var gpNid: String = str((gpRef as Dictionary).get("node_id", ""))
		var gpPid: String = str((gpRef as Dictionary).get("port_id", ""))
		if gpNid != "" and gpPid != "":
			var gpKey: String = gpNid + "/" + gpPid
			if not port_edges.has(gpKey):
				port_edges[gpKey] = []
			(port_edges[gpKey] as Array).append(gpE.gpInstanceId)


# Node entry, or null.
# 节点条目，或 null。
func gpNode(gpId: String) -> Dictionary:
	return nodes.get(gpId, {}) as Dictionary


# Edge entry, or null.
# 连线条目，或 null。
func gpEdge(gpId: String) -> Dictionary:
	return edges.get(gpId, {}) as Dictionary


# Resolved rect of a node.
# 节点的已解析矩形。
func gpRect(gpId: String) -> Rect2:
	var gpE: Dictionary = gpNode(gpId)
	return gpE.get("rect", Rect2()) as Rect2


# Resolved polyline of an edge.
# 连线的已解析折线。
func gpPolyline(gpId: String) -> PackedVector2Array:
	var gpE: Dictionary = gpEdge(gpId)
	return gpE.get("polyline", PackedVector2Array()) as PackedVector2Array


# User-facing label for a node: "T-1002 (n1)", "T-1002/N1 (n2)".
# 节点的用户可读标签。
func gpNodeLabel(gpId: String) -> String:
	if gpId == "":
		return ""
	var gpN: GPPIDNode = graph.gpGetNode(gpId) if graph != null else null
	if gpN == null:
		return gpId
	var gpName: String = ""
	if gpN.gpParentUid != "":
		var gpParent: GPPIDNode = graph.gpGetNode(gpN.gpParentUid)
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
		var gpDef: GPSymbolDef = defs.get(gpN.gpSymbolId) as GPSymbolDef
		if gpDef != null and gpDef.gpDisplayName.strip_edges() != "":
			gpName = gpDef.gpDisplayName
		else:
			gpName = gpN.gpSymbolId
	if gpName == "" or gpName == gpId:
		return gpId
	return "%s (%s)" % [gpName, gpId]


# User-facing label for an edge: tag, else the two end labels.
# 连线的用户可读标签。
func gpEdgeLabel(gpId: String) -> String:
	var gpE: GPPIDEdge = graph.gpGetEdge(gpId) if graph != null else null
	if gpE == null:
		return gpId
	if gpE.gpTag.strip_edges() != "":
		return "%s (%s)" % [gpE.gpTag, gpE.gpInstanceId]
	var gpFrom: String = gpNodeLabel(str(gpE.gpFromRef.get("node_id", "")))
	var gpTo: String = gpNodeLabel(str(gpE.gpToRef.get("node_id", "")))
	if gpFrom == "" and gpTo == "":
		return gpE.gpInstanceId
	return "%s (%s → %s)" % [gpE.gpInstanceId, gpFrom, gpTo]


# Stable uid of a node / edge, or "".
# 节点 / 连线的稳定 uid。
func gpNodeUid(gpId: String) -> String:
	var gpE: Dictionary = gpNode(gpId)
	return str(gpE.get("uid", "")) if not gpE.is_empty() else ""


func gpEdgeUid(gpId: String) -> String:
	var gpE: Dictionary = gpEdge(gpId)
	return str(gpE.get("uid", "")) if not gpE.is_empty() else ""


# Assembly root of a node (top-level nodes are their own root).
# 节点的装配体根（顶层节点即自身）。
func gpRoot(gpId: String) -> String:
	var gpE: Dictionary = gpNode(gpId)
	return str(gpE.get("root", gpId)) if not gpE.is_empty() else gpId


# Port entry for a node, or {}.
# 节点的端口条目。
func gpPort(gpNodeId: String, gpPortId: String) -> Dictionary:
	var gpE: Dictionary = gpNode(gpNodeId)
	if gpE.is_empty():
		return {}
	return (gpE.get("ports", {}) as Dictionary).get(gpPortId, {}) as Dictionary


# Edges attached to a node / port.
# 接到某节点 / 端口的连线。
func gpEdgesAtPort(gpNodeId: String, gpPortId: String) -> Array:
	var gpList: Variant = port_edges.get(gpNodeId + "/" + gpPortId, [])
	return (gpList as Array).duplicate() if gpList is Array else []


# Whether a node id exists.
# 节点 id 是否存在。
func gpHasNode(gpId: String) -> bool:
	return nodes.has(gpId)


# Approximate label box: anchored at the node's top-left, width from character count. It is a
# CONSERVATIVE text envelope until a real font-metrics service lands; rules that use it are gated
# behind `label_gap_mm` and skip rather than guess when the tag is empty.
# 近似标称盒：以图元左上角为锚，宽度按字符数估算。在真正的字体度量服务落地前这是**保守**
# 文字包络；使用它的规则受 `label_gap_mm` 约束，空位号时跳过而不是猜。
func gpLabelRect(gpRect: Rect2, gpLabel: String) -> Rect2:
	if gpLabel.strip_edges() == "":
		return Rect2()
	var gpW: float = maxf(8.0, float(gpLabel.length()) * GP_LABEL_CHAR_W)
	return Rect2(Vector2(gpRect.position.x, gpRect.position.y - GP_LABEL_H - 1.0),
		Vector2(gpW, GP_LABEL_H))


# Axis-aligned rect at an origin, rotated by gpRot degrees (AABB of the rotated envelope).
# 以原点为中心、旋转 gpRot 度后的轴对齐包络。
static func gpRectAt(gpOrigin: Vector2, gpSize: Vector2, gpRotDeg: float) -> Rect2:
	if is_zero_approx(gpRotDeg):
		return Rect2(gpOrigin - gpSize * 0.5, gpSize)
	var gpHalf: Vector2 = gpSize * 0.5
	var gpMin: Vector2 = Vector2(INF, INF)
	var gpMax: Vector2 = Vector2(-INF, -INF)
	for gpSx in [-1.0, 1.0]:
		for gpSy in [-1.0, 1.0]:
			var gpP: Vector2 = gpOrigin + Vector2(gpHalf.x * gpSx, gpHalf.y * gpSy).rotated(
				deg_to_rad(gpRotDeg))
			gpMin = gpMin.min(gpP)
			gpMax = gpMax.max(gpP)
	return Rect2(gpMin, gpMax - gpMin)


# Root of a node's mount tree (cycle-safe).
# 节点挂载树的根（带环护栏）。
func _gpRootOf(gpN: GPPIDNode) -> String:
	var gpCur: GPPIDNode = gpN
	var gpSeen: Dictionary = {}
	while gpCur != null and gpCur.gpParentUid != "":
		if gpSeen.has(gpCur.gpInstanceId):
			break
		gpSeen[gpCur.gpInstanceId] = true
		var gpParent: GPPIDNode = graph.gpGetNode(gpCur.gpParentUid)
		if gpParent == null:
			break
		gpCur = gpParent
	return gpCur.gpInstanceId if gpCur != null else gpN.gpInstanceId
