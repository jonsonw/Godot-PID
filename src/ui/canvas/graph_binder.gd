class_name GPGraphBinder
extends Node

# Binds a GPPIDGraph data model to the Node2D view tree under a world root.
# 把 GPPIDGraph 数据模型绑定到 world root 下的 Node2D 视图树。
# This component owns the incremental view caches and the sync logic so the
# canvas can stay focused on input, camera and coordinate transforms.
# 本组件持有增量视图缓存与同步逻辑，使画布只专注于输入、相机与坐标变换。
# Coding rule: every variable must declare its type explicitly (including container types).
# 编码规范：所有变量均显式声明类型（含容器类型）。
# GPSymbolView / GPEdgeView are global class_name — no preload constant needed.
# GPSymbolView / GPEdgeView 是全局 class_name，无需 preload 常量。

# Data model and definitions injected by the owning canvas before each sync.
# 由所属画布在每次同步前注入的数据模型与图元定义。
var gpGraph: GPPIDGraph = null
var gpDefs: Array[GPSymbolDef] = []

# Node2D that holds all symbol/edge view nodes and carries the camera transform.
# 承载所有图元/连线视图节点并承载相机变换的 Node2D。
var gpWorldRoot: Node2D = null

# Current canvas zoom, pushed by the owning canvas. Edge views need it to keep line widths,
# dashes, arrowheads and halos above their screen-space floors.
# 由所属画布推送的当前缩放。连线视图需要它来把线宽、虚线、箭头与光晕保持在屏幕空间下限之上。
var gpZoom: float = 1.0

# Incremental view caches: id -> view node. Used for sync instead of full rebuild.
# 增量视图缓存：id → 视图节点。用于增量同步而非全量重建。
var _gpSymbolViews: Dictionary = {}
var _gpEdgeViews: Dictionary = {}

# Signature of the geometry the crossing pass depends on. Crossing detection is the only O(n^2)
# step on the sheet, so it runs ONLY when the geometry actually moved — not on every repaint.
# 交叉计算所依赖几何的签名。交叉检测是图纸上唯一的 O(n^2) 步骤，故仅在几何真正变化时运行，
# 而非每次重绘都跑。
var _gpCrossSig: String = ""

# Whether crossing breaks are painted at all (host toggle; default on).
# 是否绘制断口（宿主开关；默认开启）。
var gpCrossBreaksEnabled: bool = true


# Find a symbol definition by its id.
# 按 id 查找图元定义。
func gpDefFor(gpTypeId: String) -> GPSymbolDef:
	for gpD in gpDefs:
		if gpD.gpId == gpTypeId:
			return gpD
	return null


# Callable wrapper of gpDefFor, handed to GPEdgeView so it can resolve port positions without
# knowing the binder or the library.
# gpDefFor 的 Callable 包装，交给 GPEdgeView，使其无需知晓绑定器或图元库即可解析端口位置。
func _gpLookupDef(gpTypeId: String) -> GPSymbolDef:
	return gpDefFor(gpTypeId)


# Return the symbol view node for an id, or null if not present.
# 按 id 返回图元视图节点；不存在则返回 null。
func gpGetSymbolView(gpId: String) -> GPSymbolView:
	return _gpSymbolViews.get(gpId, null) as GPSymbolView


# Return the edge view node for an id, or null if not present.
# 按 id 返回连线视图节点；不存在则返回 null。
func gpGetEdgeView(gpId: String) -> GPEdgeView:
	return _gpEdgeViews.get(gpId, null) as GPEdgeView


# Every routed polyline already on the sheet (optionally skipping one id). Handed to the
# auto-router so a new pipe prefers a corridor no other line has taken.
# 图纸上已有的每条已布线折线（可跳过某个 id）。交给自动布线器，使新管线优先选择
# 别处尚未占用的通道。
func gpExistingPolylines(gpSkipId: String = "") -> Array[PackedVector2Array]:
	var gpOut: Array[PackedVector2Array] = []
	for gpId in _gpEdgeViews.keys():
		if gpId == gpSkipId:
			continue
		var gpV: GPEdgeView = _gpEdgeViews[gpId] as GPEdgeView
		if gpV == null:
			continue
		var gpPts: PackedVector2Array = gpV.gpPolyline()
		if gpPts.size() >= 2:
			gpOut.append(gpPts)
	return gpOut


# Sync both symbol and edge views to the current graph state.
# 将图元与连线视图同步到当前图状态。
# [param gpG] the topology graph to render.
# [param gpD] available symbol definitions.
# [param gpSelection] ids of currently selected nodes (multi-select; drives the highlight).
# [param gpSelection] 当前选中节点的 id 集合（多选；驱动高亮）。
# [param gpConnectFrom] current connect-source node id (for highlight).
# [param gpZoomIn] current canvas zoom (drives the screen-space floors in GPEdgeStyle).
# [param gpZoomIn] 当前画布缩放（驱动 GPEdgeStyle 中的屏幕空间下限）。
# [param gpEdgeSelection] currently selected edge ids (drives edge halo; separate array from nodes).
# [param gpEdgeSelection] 当前选中的边 id 集合（驱动边光晕；与节点选择分属不同数组）。
# [param gpEditingEdgeId] edge whose grip is being dragged right now (edit-state highlight), or "".
# [param gpEditingEdgeId] 当前正被拖拽抓取点的边 id（编辑态高亮），无则 ""。
func gpSync(gpG: GPPIDGraph, gpD: Array[GPSymbolDef], gpSelection: Array[String],
		gpConnectFrom: String, gpZoomIn: float = 1.0,
		gpEdgeSelection: Array[String] = [], gpEditingEdgeId: String = "") -> void:
	gpGraph = gpG
	gpDefs = gpD
	gpZoom = maxf(gpZoomIn, 0.01)
	if gpGraph == null or gpWorldRoot == null:
		return
	_gpSyncSymbolViews(gpSelection, gpConnectFrom)
	_gpSyncEdgeViews(gpSelection, gpEdgeSelection, gpEditingEdgeId)
	_gpUpdateCrossings()


# Incrementally sync symbol view nodes with gpGraph.gpNodes.
# 增量同步图元视图节点与 gpGraph.gpNodes。
func _gpSyncSymbolViews(gpSelection: Array[String], gpConnectFrom: String) -> void:
	var gpFresh: Dictionary = {}
	for gpN in gpGraph.gpNodes:
		var gpId: String = gpN.gpInstanceId
		if gpId == "":
			continue
		var gpV: GPSymbolView = null
		if _gpSymbolViews.has(gpId):
			# Reuse existing view and rebind ALL authoritative data.
			# 复用已有视图并重绑全部权威数据。
			gpV = _gpSymbolViews[gpId] as GPSymbolView
			gpV.gpNode = gpN
			gpV.gpNodeId = gpId
			# Rebind the definition too. When a symbol is re-exported, gpRegisterDefs()
			# replaces the GPSymbolDef object behind the SAME id, so a view that keeps
			# its old reference would silently keep painting the stale geometry.
			# This single line is what makes "overwrite a symbol -> every placed
			# instance refreshes" actually work.
			# 同时重绑定义。重新导出图元时 gpRegisterDefs() 会替换同一 id 背后的
			# GPSymbolDef 对象，若视图保留旧引用，就会静默地继续绘制过期几何。
			# 这一行正是「覆盖图元 → 所有已放置实例同步刷新」得以生效的关键。
			gpV.gpDef = gpDefFor(gpN.gpSymbolId)
			gpV.gpUpdateTransform()
			# The definition drives the painted geometry, so a rebind needs a repaint of BOTH
			# layers (label on the view, glyph + ports on the body child).
			# 定义驱动所绘几何，故重绑后必须重绘「两层」（视图上的标签，body 子节点上的字形与端口）。
			gpV.gpRepaint()
		else:
			# Create a new view for this node.
			# 为该节点创建新视图。
			gpV = GPSymbolView.new()
			var gpDef: GPSymbolDef = gpDefFor(gpN.gpSymbolId)
			gpV.gpInit(gpN, gpDef)
			gpWorldRoot.add_child(gpV)
		# Multi-select: every id in the selection set lights up, not just the primary one.
		# 多选：选择集中的每个 id 都会高亮，而不只是主选项。
		gpV.gpSetSelected(gpSelection.has(gpId))
		gpV.gpSetConnectSource(gpId == gpConnectFrom)
		gpFresh[gpId] = gpV
	# Remove stale symbol views.
	# 删除已不存在的图元视图。
	for gpId in _gpSymbolViews.keys():
		if not gpFresh.has(gpId):
			var gpV: Node2D = _gpSymbolViews[gpId]
			gpV.queue_free()
	_gpSymbolViews = gpFresh


# Incrementally sync edge view nodes with gpGraph.gpEdges.
# 增量同步连线视图节点与 gpGraph.gpEdges。
# [param gpSelection] selected node ids / 选中的节点 id
# [param gpEdgeSelection] selected edge ids / 选中的边 id
# [param gpEditingEdgeId] edge being grip-dragged (edit highlight) / 正被拖拽的边 id（编辑高亮）
func _gpSyncEdgeViews(gpSelection: Array[String], gpEdgeSelection: Array[String] = [],
		gpEditingEdgeId: String = "") -> void:
	var gpFresh: Dictionary = {}
	for gpE in gpGraph.gpEdges:
		var gpId: String = gpE.gpInstanceId
		if gpId == "":
			continue
		var gpV: GPEdgeView = null
		if _gpEdgeViews.has(gpId):
			# Reuse existing view and update its bound data.
			# 复用已有视图并更新绑定数据。
			gpV = _gpEdgeViews[gpId] as GPEdgeView
			gpV.gpEdge = gpE
			gpV.queue_redraw()
		else:
			# Create a new view for this edge.
			# 为该连线创建新视图。
			gpV = GPEdgeView.new()
			gpV.gpInit(gpE, gpGraph, Callable(self, "_gpLookupDef"))
			gpWorldRoot.add_child(gpV)
		# Edge ids live in their OWN selection array (gpEdgeSel), so selection must be tested against
		# BOTH the node set and the edge set — otherwise an edge's halo never lights up and the user
		# only sees the grip triangles. Edit state is set when this edge is the one being dragged.
		# 边 id 存于独立的选择数组（gpEdgeSel），故需同时比对节点集与边集 —— 否则边的光晕永远不亮，
		# 用户只会看到抓取点三角。编辑态在本边正是被拖拽的那条时置真。
		var gpIsSel: bool = gpSelection.has(gpId) or gpEdgeSelection.has(gpId)
		gpV.gpSetView(gpZoom, gpIsSel, false, gpId == gpEditingEdgeId)
		gpFresh[gpId] = gpV
	# Remove stale edge views.
	# 删除已不存在的连线视图。
	for gpId in _gpEdgeViews.keys():
		if not gpFresh.has(gpId):
			var gpV: Node2D = _gpEdgeViews[gpId]
			gpV.queue_free()
	_gpEdgeViews = gpFresh


# Recompute the "which line breaks at a crossing" pass and push the results onto the edge views.
# 重算「交叉处哪条线断」这一遍，并把结果推送到各连线视图。
# Only the binder can do this: an edge view sees itself, never the line it crosses.
# 只有绑定器能做这件事：连线视图只看得到自己，看不到它所交叉的那条线。
func _gpUpdateCrossings() -> void:
	if gpGraph == null:
		return
	var gpSig: String = _gpCrossSignature()
	if gpSig == _gpCrossSig:
		return
	_gpCrossSig = gpSig
	var gpLines: Array[Dictionary] = []
	for gpE in gpGraph.gpEdges:
		var gpV: GPEdgeView = _gpEdgeViews.get(gpE.gpInstanceId, null) as GPEdgeView
		if gpV == null:
			continue
		gpLines.append({
			"id": gpE.gpInstanceId,
			"kind": gpE.gpKind,
			"pts": gpV.gpPolyline(),
		})
	var gpCross: Array[Dictionary] = []
	if gpCrossBreaksEnabled:
		gpCross = GPEdgeCrossing.gpFindCrossings(gpLines)
	for gpE2 in gpGraph.gpEdges:
		var gpV2: GPEdgeView = _gpEdgeViews.get(gpE2.gpInstanceId, null) as GPEdgeView
		if gpV2 == null:
			continue
		gpV2.gpSetBreaks(GPEdgeCrossing.gpBreaksFor(gpCross, gpE2.gpInstanceId))


# A cheap fingerprint of everything crossing detection depends on: node transforms, edge kinds
# and every stored waypoint. Zoom is NOT part of it — crossings are a world-space fact.
# 交叉检测所依赖的一切的廉价指纹：节点变换、边类型与每个已存折点。缩放不在其中 ——
# 交叉是世界坐标下的事实。
func _gpCrossSignature() -> String:
	if gpGraph == null:
		return ""
	var gpS: String = str(gpGraph.gpNodes.size()) + "/" + str(gpGraph.gpEdges.size())
	for gpN in gpGraph.gpNodes:
		gpS += "|" + gpN.gpInstanceId + ":" + str(gpN.gpPosition.x) + "," + str(gpN.gpPosition.y)
		gpS += "," + str(gpN.gpRotationDeg) + "," + str(gpN.gpFlipped)
	for gpE in gpGraph.gpEdges:
		gpS += "|" + gpE.gpInstanceId + ":" + gpE.gpKind + "," + str(gpE.gpSignalType)
		gpS += "," + str(gpE.gpOrtho) + "," + str(gpE.gpRouting.size())
		for gpP in gpE.gpRouting:
			gpS += "," + str(gpP.x) + "," + str(gpP.y)
	return gpS


# Queue redraw on all symbol views.
# 令所有图元视图重新绘制。
func gpRefreshSymbols() -> void:
	for gpId in _gpSymbolViews.keys():
		var gpV: GPSymbolView = _gpSymbolViews[gpId] as GPSymbolView
		gpV.gpRepaint()


# Queue redraw on all edge views.
# 令所有连线视图重新绘制。
func gpRefreshEdges() -> void:
	for gpId in _gpEdgeViews.keys():
		var gpV: GPEdgeView = _gpEdgeViews[gpId] as GPEdgeView
		gpV.queue_redraw()


# Remove all view nodes and clear caches. Call before teardown or graph reload.
# 移除所有视图节点并清空缓存。销毁前或重新载入图前调用。
func gpClear() -> void:
	for gpV in _gpSymbolViews.values():
		(gpV as Node2D).queue_free()
	for gpV in _gpEdgeViews.values():
		(gpV as Node2D).queue_free()
	_gpSymbolViews.clear()
	_gpEdgeViews.clear()
	_gpCrossSig = ""
