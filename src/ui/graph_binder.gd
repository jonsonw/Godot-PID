class_name GPGraphBinder
extends Node

# Binds a GPPIDGraph data model to the Node2D view tree under a world root.
# 把 GPPIDGraph 数据模型绑定到 world root 下的 Node2D 视图树。
# This component owns the incremental view caches and the sync logic so the
# canvas can stay focused on input, camera and coordinate transforms.
# 本组件持有增量视图缓存与同步逻辑，使画布只专注于输入、相机与坐标变换。
# Coding rule: every variable must declare its type explicitly (including container types).
# 编码规范：所有变量均显式声明类型（含容器类型）。

# Preloaded view classes used for incremental node/edge rendering.
# 增量式图元/连线渲染所用的视图类（预加载）。
const GPSymbolView := preload("res://src/render/symbol_view.gd")
# Preloaded edge view class for incremental edge rendering.
# 增量式连线渲染所用的连线视图类（预加载）。
const GPEdgeView := preload("res://src/render/edge_view.gd")

# Data model and definitions injected by the owning canvas before each sync.
# 由所属画布在每次同步前注入的数据模型与图元定义。
var gpGraph: GPPIDGraph = null
var gpDefs: Array[GPSymbolDef] = []

# Node2D that holds all symbol/edge view nodes and carries the camera transform.
# 承载所有图元/连线视图节点并承载相机变换的 Node2D。
var gpWorldRoot: Node2D = null

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


# Return the symbol view node for an id, or null if not present.
# 按 id 返回图元视图节点；不存在则返回 null。
func gpGetSymbolView(gpId: String) -> GPSymbolView:
	return _gpSymbolViews.get(gpId, null) as GPSymbolView


# Sync both symbol and edge views to the current graph state.
# 将图元与连线视图同步到当前图状态。
# [param gpG] the topology graph to render.
# [param gpD] available symbol definitions.
# [param gpSelectedId] currently selected node id (for highlight).
# [param gpConnectFrom] current connect-source node id (for highlight).
func gpSync(gpG: GPPIDGraph, gpD: Array[GPSymbolDef], gpSelectedId: String, gpConnectFrom: String) -> void:
	gpGraph = gpG
	gpDefs = gpD
	if gpGraph == null or gpWorldRoot == null:
		return
	_gpSyncSymbolViews(gpSelectedId, gpConnectFrom)
	_gpSyncEdgeViews()


# Incrementally sync symbol view nodes with gpGraph.gpNodes.
# 增量同步图元视图节点与 gpGraph.gpNodes。
func _gpSyncSymbolViews(gpSelectedId: String, gpConnectFrom: String) -> void:
	var gpFresh: Dictionary = {}
	for gpN in gpGraph.gpNodes:
		var gpId: String = gpN.gpInstanceId
		if gpId == "":
			continue
		var gpV: GPSymbolView = null
		if _gpSymbolViews.has(gpId):
			# Reuse existing view and update its bound data.
			# 复用已有视图并更新绑定数据。
			gpV = _gpSymbolViews[gpId] as GPSymbolView
			gpV.gpNode = gpN
			gpV.gpUpdateTransform()
		else:
			# Create a new view for this node.
			# 为该节点创建新视图。
			gpV = GPSymbolView.new()
			var gpDef: GPSymbolDef = gpDefFor(gpN.gpSymbolId)
			gpV.gpInit(gpN, gpDef)
			gpWorldRoot.add_child(gpV)
		gpV.gpSetSelected(gpId == gpSelectedId)
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
func _gpSyncEdgeViews() -> void:
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
			gpV.gpInit(gpE, gpGraph)
			gpWorldRoot.add_child(gpV)
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
		gpV.queue_redraw()


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
