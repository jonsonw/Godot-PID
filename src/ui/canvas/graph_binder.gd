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

# Injected render-style snapshot. Passed to every view so the render layer
# stays autoload-free; rebuilt and re-pushed by the owning canvas on locale / font change.
# 注入的渲染样式快照。传给每个视图，使 render 层不依赖 autoload；
# 语言 / 字号变化时由所属画布重建并重推。
var gpStyle: GPRenderStyle = null

# Incremental view caches: id -> view node. Used for sync instead of full rebuild.
# 增量视图缓存：id → 视图节点。用于增量同步而非全量重建。
var _gpSymbolViews: Dictionary = {}
var _gpEdgeViews: Dictionary = {}

# Find a symbol definition by its id.
# 按 id 查找图元定义。
func gpDefFor(gpTypeId: String) -> GPSymbolDef:
	for gpD in gpDefs:
		if gpD.gpId == gpTypeId:
			return gpD
	return null

# Callable wrapper of gpDefFor(), handed to GPEdgeView so it can resolve port positions without
# knowing the binder or the library.
# gpDefFor() 的 Callable 包装，交给 GPEdgeView，使其无需知晓绑定器或图元库即可解析端口位置。
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

# Incrementally sync symbol view nodes with gpGraph.gpNodes().
# 增量同步图元视图节点与 gpGraph.gpNodes()。
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
			gpV.gpStyle = gpStyle
			# Tags are text: oversample them for the camera scale so an N mm tag is rasterised at
			# its on-screen size instead of being magnified from N pixels. The property is an ENUM
			# (`= true` coerces to 1 = DISABLED), hence the constant.
			# 位号是文字：按相机缩放过采样，使 N mm 的位号按屏幕实际尺寸光栅化，而非由 N 像素放大。
			# 该属性是**枚举**（写 `= true` 会被强转为 1 = DISABLED），故用常量。
			gpV.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
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
			gpV.gpStyle = gpStyle
			# Pipe line numbers are text too — same oversampling reason and enum caveat as above.
			# 管线位号同样是文字 —— 过采样理由与枚举注意事项同上。
			gpV.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
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


# Redraw only the edge views whose ends touch one of the given nodes, and return their ids.
# 仅重绘「端口触碰给定节点集中任一节点」的连线视图，并返回其 id 列表。
#
# Why this exists / 为何需要它：
# An edge's endpoints are resolved LIVE from node positions inside GPEdgeView._draw(), so a node
# that moves during a drag must redraw its own pipes too — otherwise the pipe ends lag behind the
# symbol and then snap to the final position only when the drag commits (gpGraphChanged on release).
# 连线端点是在 GPEdgeView._draw() 内依节点位置实时解析的，故拖拽中被移动的图元必须让其管线
# 同步重绘，否则管线端点会滞后于图元、直到拖拽提交（释放时的 gpGraphChanged）才突跳到位。
# Redrawing the whole sheet every frame would work but is wasteful; this touches only the affected
# edges. Returning the id list lets callers assert / observe exactly which edges were marked.
# 每帧全图重绘虽可行但浪费，本函数只触碰受影响的边。返回 id 列表便于调用方精确断言 / 观察。
func gpRedrawEdgesForNodes(gpNodeIds: Array[String]) -> Array[String]:
	var gpOut: Array[String] = []
	if gpNodeIds.is_empty() or _gpEdgeViews.is_empty():
		return gpOut
	var gpTouched: Dictionary = {}
	for gpId in gpNodeIds:
		gpTouched[gpId] = true
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		var gpFrom: String = str((gpE.gpFromRef if gpE.gpFromRef != null else {}).get("node_id", ""))
		var gpTo: String = str((gpE.gpToRef if gpE.gpToRef != null else {}).get("node_id", ""))
		if gpTouched.has(gpFrom) or gpTouched.has(gpTo):
			var gpV: GPEdgeView = _gpEdgeViews.get(gpE.gpInstanceId, null) as GPEdgeView
			if gpV != null:
 # Synchronous: push the live polyline into the GPU ink line now, so the
 # endpoint follows the node this very frame with no redraw-timing dependency.
 # 同步半边：立刻把实时折线写入 GPU 墨线，使端点当帧即跟随图元，不依赖重绘时序。
				gpV.gpApplyGeometry()
 # Deferred: also request _draw() for the CPU (selected-edge) path.
 # 延迟半边：同时请求 _draw()，覆盖 CPU（选中边）路径。
				gpV.queue_redraw()
				gpOut.append(gpE.gpInstanceId)
	return gpOut

# 重新注入渲染样式快照（语言 / 字号变化时由画布调用）。
# 把新快照写入所有已有视图并显式请求重绘，使切换语言后旧视图不残留旧字号 / 文字。
# Re-push a fresh render-style snapshot (called by the canvas on locale / font change):
# write it into every existing view and request a repaint so stale views never linger.
func gpApplyStyle(gpNewStyle: GPRenderStyle) -> void:
	gpStyle = gpNewStyle
	for gpId in _gpSymbolViews.keys():
		var gpV: GPSymbolView = _gpSymbolViews[gpId] as GPSymbolView
		if gpV == null:
			continue
		gpV.gpStyle = gpStyle
		gpV.gpRepaint()
	for gpId in _gpEdgeViews.keys():
		var gpV: GPEdgeView = _gpEdgeViews[gpId] as GPEdgeView
		if gpV == null:
			continue
		gpV.gpStyle = gpStyle
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
