class_name GPCanvasHitTest
extends RefCounted
# Pure hit-testing + node geometry lookup for the P&ID canvas (P5 extraction). Holds NO Control /
# Node dependency and no camera state, so it is fully headless-testable and reusable by any view
# that needs to ask "what is under this world point?" without dragging in the canvas god-object.
# P&ID 画布的纯命中测试 + 节点几何查找（P5 抽取）。无 Control/Node 依赖、无相机状态，可 headless
# 单测，任何需要「这个点下是什么？」的视图都能复用，而无需拖入画布 god-object。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Find the world center of a node by id. Returns Vector2.INF when not found.
# 按 id 查找节点的世界中心；未找到返回 Vector2.INF。
static func gpNodeCenter(gpGraph: GPPIDGraph, gpId: String) -> Vector2:
	for gpN in gpGraph.gpNodes:
		if gpN.gpInstanceId == gpId:
			return gpN.gpPosition
	return Vector2.INF


# World-space bounding rect of a node, from its definition's nominal envelope (fallback 64x48).
# 节点的世界坐标包围矩形，取自其定义标称包络（缺省回退 64x48）。
static func gpNodeRect(gpGraph: GPPIDGraph, gpBinder: GPGraphBinder, gpId: String) -> Rect2:
	if gpGraph == null or gpBinder == null:
		return Rect2()
	for gpN in gpGraph.gpNodes:
		if gpN.gpInstanceId == gpId:
			var gpDef: GPSymbolDef = gpBinder.gpDefFor(gpN.gpSymbolId)
			var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
			return Rect2(gpN.gpPosition - gpSz / 2.0, gpSz)
	return Rect2()


# Topmost node id under the given world point, or "". Hit area = node rect.
# 指定世界点下最上层节点 id，无则 ""。命中区域 = 节点矩形。
static func gpHitNode(gpGraph: GPPIDGraph, gpBinder: GPGraphBinder, gpWorld: Vector2) -> String:
	if gpGraph == null:
		return ""
	for gpN in gpGraph.gpNodes:
		if gpNodeRect(gpGraph, gpBinder, gpN.gpInstanceId).has_point(gpWorld):
			return gpN.gpInstanceId
	return ""


# Topmost edge id under the world point, or "".
# 世界点下最上层边的 id，未命中 ""。
#
# Hits the ROUTED polyline, not the raw from/to refs / 命中的是「已布线的折线」而非原始引用：
#   A pipe is drawn as an L or Z with corners. Testing the straight line between the two port
#   refs would make the user click where the pipe visibly IS and hit nothing. So the hit test
#   re-routes the edge exactly the way the renderer does and measures against that.
#   管线画出来是带拐角的 L 或 Z。若按两端口引用之间的直线判定，用户点管线「看起来在」的地方
#   会什么都点不中。因此命中测试按与渲染完全相同的方式重新布线，再依此度量。
#
# Self-contained on purpose / 刻意自足：
#   It needs no GPGraphBinder and no view nodes — just the graph and a def lookup. That keeps it
#   headless-testable and means the hit area can never fall out of sync with the renderer, because
#   both call the same GPEdgeRoute.
#   它不需要 GPGraphBinder，也不需要任何视图节点 —— 只要图与一个定义查找器。这既保持可 headless
#   单测，又使命中区永不会与渲染器失步，因为两者调的是同一个 GPEdgeRoute。
static func gpHitEdge(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2,
		gpZoom: float) -> String:
	if gpGraph == null:
		return ""
	var gpTol: float = 6.0 / maxf(gpZoom, 0.01)
	# Topmost first: later edges paint over earlier ones, so they win the click.
	# 自顶层起：后画的边盖在先画的之上，故优先获得点击。
	for gpI in range(gpGraph.gpEdges.size() - 1, -1, -1):
		var gpE: GPPIDEdge = gpGraph.gpEdges[gpI]
		var gpWant: String = GPPortResolver.gpWantTypeFor(gpE)
		var gpFrom: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpDefLookup, gpE, true, gpWant)
		var gpTo: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpDefLookup, gpE, false, gpWant)
		var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(gpFrom, gpTo, gpE.gpRouting, gpE.gpOrtho)
		if gpPolylineHit(gpWorld, gpPts, gpTol):
			return gpE.gpInstanceId
	return ""


# Is the world point within gpTol of any leg of the polyline?
# 世界点是否落在折线任一腿的 gpTol 范围内？
static func gpPolylineHit(gpWorld: Vector2, gpPts: PackedVector2Array, gpTol: float) -> bool:
	if gpPts.size() < 2:
		return false
	for gpI in range(gpPts.size() - 1):
		if GPGeometry.gpDistPointSeg(gpWorld, gpPts[gpI], gpPts[gpI + 1]) <= gpTol:
			return true
	return false


# Index of the topmost annotation shape under the world point, or -1. Tolerance scales with zoom
# (6px at 100%). Shared with the symbol editor via GPGeometry.gpShapeHit.
# 世界点下最上层注释图形下标，未命中 -1。容差随缩放（100% 时 6px）。经 GPGeometry.gpShapeHit
# 与符号编辑器共用。
static func gpHitShape(gpGraph: GPPIDGraph, gpWorld: Vector2, gpZoom: float) -> int:
	if gpGraph == null:
		return -1
	var gpTol: float = 6.0 / gpZoom
	for gpI in range(gpGraph.gpShapes.size() - 1, -1, -1):
		if GPGeometry.gpShapeHit(gpWorld, gpGraph.gpShapes[gpI], gpTol):
			return gpI
	return -1
