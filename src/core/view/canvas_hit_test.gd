class_name GPCanvasHitTest
extends RefCounted
# Pure hit-testing + node geometry lookup for the P&ID canvas . Holds NO Control /
# Node dependency and no camera state, so it is fully headless-testable and reusable by any view
# that needs to ask "what is under this world point?" without dragging in the canvas god-object.
# P&ID 画布的纯命中测试 + 节点几何查找。无 Control/Node 依赖、无相机状态，可 headless
# 单测，任何需要「这个点下是什么？」的视图都能复用，而无需拖入画布 god-object。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Find the world center of a node by id. Returns Vector2.INF when not found.
# 按 id 查找节点的世界中心；未找到返回 Vector2.INF。
#
# MOUNT-AWARE / 感知挂载：
# A mounted child's gpPosition is NOT its world location — that is derived from the parent chain
# (see GPMountResolver). Reading the raw field would make a nozzle hittable at its stale
# coordinate (usually the sheet origin) and NOT where the user sees it, so "select the nozzle and
# edit its DN" would be impossible. The lookup is OPTIONAL so every pre-existing caller keeps the
# exact old answer for an unmounted node, and a missing/invalid lookup degrades to the own frame
# exactly as before.
# 挂载子件的 gpPosition **不是**它的世界位置 —— 那是从父链推导的（见 GPMountResolver）。读原始
# 字段会让管口在它过期的坐标（通常是图纸原点）处可命中，而**不是**在用户看到的位置，于是
# 「选中管口改 DN」根本无法完成。查找器是**可选**的，故每个既有调用方对未挂载节点得到与旧实现
# 完全相同的答案；查找器缺失 / 无效时亦如旧地降级为自身坐标系。
static func gpNodeCenter(gpGraph: GPPIDGraph, gpId: String,
		gpDefLookup: Callable = Callable()) -> Vector2:
	for gpN in gpGraph.gpNodes:
		if gpN.gpInstanceId == gpId:
			return GPPortResolver.gpNodeWorldOrigin(gpGraph, gpDefLookup, gpN)
	return Vector2.INF


# World-space bounding rect of a node, from its definition's nominal envelope (fallback 64x48).
# 节点的世界坐标包围矩形，取自其定义标称包络（缺省回退 64x48）。
# Mount-aware: the rect is centred on the node's DERIVED world origin (see gpNodeCenter()).
# 感知挂载：矩形以节点**推导**的世界原点为中心（见 gpNodeCenter()）。
static func gpNodeRect(gpGraph: GPPIDGraph, gpBinder: GPGraphBinder, gpId: String) -> Rect2:
	if gpGraph == null or gpBinder == null:
		return Rect2()
	for gpN in gpGraph.gpNodes:
		if gpN.gpInstanceId == gpId:
			var gpDef: GPSymbolDef = gpBinder.gpDefFor(gpN.gpSymbolId)
			var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
			var gpOrigin: Vector2 = _gpWorldOrigin(gpGraph, gpBinder, gpN)
			return Rect2(gpOrigin - gpSz / 2.0, gpSz)
	return Rect2()


# Topmost node id under the given world point, or "". Hit area = node rect.
# 指定世界点下最上层节点 id，无则 ""。命中区域 = 节点矩形。
#
# MOUNT-AWARE PRIORITY / 感知挂载的优先级：
# A mounted child overlaps its host by construction (an actuator SITS ON the valve), so the two
# rects hit at the same point. The rule is "the DEEPER node wins": a part beats the thing it is
# mounted on, which is what makes a nozzle / actuator selectable at all — and it is what lets the
# user edit the nozzle's own DN instead of re-selecting the vessel.
# 挂载子件按构造就与其宿主重叠（执行机构**坐**在阀门上），故两者在同一点击处都会命中。
# 规则是「**更深**的节点胜出」：部件胜过它所安装的物件 —— 这正是管口 / 执行机构可被选中的前提，
# 也是用户能编辑管口自身 DN 而非反复选到设备的原因。
#
# LEGACY PRESERVED ON TIES / 平局时保持既有行为：
# Equal depth keeps the FIRST node in graph order, exactly as before this change. Only a strictly
# deeper node displaces an already-found hit, so drawings without mounts hit-test identically.
# 同深度仍取图声明顺序中的**第一个**节点，与本改动之前完全一致。只有**严格更深**的节点才会
# 顶替已找到的命中，故没有挂载的图纸命中结果不变。
static func gpHitNode(gpGraph: GPPIDGraph, gpBinder: GPGraphBinder, gpWorld: Vector2) -> String:
	if gpGraph == null:
		return ""
	var gpLookup: Callable = gpBinder.gpDefFor if gpBinder != null else Callable()
	var gpBest: String = ""
	var gpBestDepth: int = -1
	for gpN in gpGraph.gpNodes:
		var gpDef: GPSymbolDef = gpBinder.gpDefFor(gpN.gpSymbolId) if gpBinder != null else null
		var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
		var gpOrigin: Vector2 = GPPortResolver.gpNodeWorldOrigin(gpGraph, gpLookup, gpN)
		if not Rect2(gpOrigin - gpSz / 2.0, gpSz).has_point(gpWorld):
			continue
		var gpDepth: int = _gpMountDepth(gpGraph, gpN)
		if gpDepth > gpBestDepth:
			gpBestDepth = gpDepth
			gpBest = gpN.gpInstanceId
	return gpBest


# How many mount hops sit between a node and the top level (0 = top level).
# 节点与顶层之间的挂载跳数（0 = 顶层）。
# Cycle-safe: a hand-edited A-mounts-B-mounts-A pair terminates instead of looping forever.
# 环安全：手改出的 A 挂 B、B 挂 A 会终止而非死循环。
static func _gpMountDepth(gpGraph: GPPIDGraph, gpNode: GPPIDNode) -> int:
	var gpSeen: Dictionary = {}
	var gpCur: GPPIDNode = gpNode
	var gpDepth: int = 0
	while gpCur != null and gpCur.gpIsMounted() and not gpSeen.has(gpCur.gpInstanceId):
		gpSeen[gpCur.gpInstanceId] = true
		gpCur = gpGraph.gpGetNode(gpCur.gpParentUid)
		if gpCur != null:
			gpDepth += 1
	return gpDepth


# Derived world origin of a node through the binder's own definition lookup.
# 经绑定器自身的定义查找器求节点的推导世界原点。
static func _gpWorldOrigin(gpGraph: GPPIDGraph, gpBinder: GPGraphBinder,
		gpNode: GPPIDNode) -> Vector2:
	if gpBinder == null:
		return gpNode.gpPosition
	# Bare method reference: parse-time checked, rename-safe. / 裸方法引用：解析期受检，重命名安全。
	return GPPortResolver.gpNodeWorldOrigin(gpGraph, gpBinder.gpDefFor, gpNode)


# Topmost edge id under the world point, or "".
# 世界点下最上层边的 id，未命中 ""。
#
# Hits the ROUTED polyline, not the raw from/to refs / 命中的是「已布线的折线」而非原始引用：
# A pipe is drawn as an L or Z with corners. Testing the straight line between the two port
# refs would make the user click where the pipe visibly IS and hit nothing. So the hit test
# re-routes the edge exactly the way the renderer does and measures against that.
# 管线画出来是带拐角的 L 或 Z。若按两端口引用之间的直线判定，用户点管线「看起来在」的地方
# 会什么都点不中。因此命中测试按与渲染完全相同的方式重新布线，再依此度量。
#
# Self-contained on purpose / 刻意自足：
# It needs no GPGraphBinder and no view nodes — just the graph and a def lookup. That keeps it
# headless-testable and means the hit area can never fall out of sync with the renderer, because
# both call the same GPEdgeRoute.
# 它不需要 GPGraphBinder，也不需要任何视图节点 —— 只要图与一个定义查找器。这既保持可 headless
# 单测，又使命中区永不会与渲染器失步，因为两者调的是同一个 GPEdgeRoute。
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
# (6px at 100%). Shared with the symbol editor via GPGeometry.gpShapeHit().
# 世界点下最上层注释图形下标，未命中 -1。容差随缩放（100% 时 6px）。经 GPGeometry.gpShapeHit()
# 与符号编辑器共用。
static func gpHitShape(gpGraph: GPPIDGraph, gpWorld: Vector2, gpZoom: float) -> int:
	if gpGraph == null:
		return -1
	var gpTol: float = 6.0 / gpZoom
	for gpI in range(gpGraph.gpShapes.size() - 1, -1, -1):
		if GPGeometry.gpShapeHit(gpWorld, gpGraph.gpShapes[gpI], gpTol):
			return gpI
	return -1
