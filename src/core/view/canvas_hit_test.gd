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
