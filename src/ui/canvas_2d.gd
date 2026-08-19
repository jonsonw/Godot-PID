class_name GPCanvas2D
extends Control

# Preloaded view class used for symbol view type annotation.
# 图元视图类型注解所用的视图类（预加载）。
const GPSymbolView := preload("res://src/render/symbol_view.gd")

# 2D canvas implemented with a Node2D world_root.
# 2D 画布：使用 Node2D 作为 world_root 实现。
# Symbols are real GPSymbolView nodes under world_root; edges are GPEdgeView nodes.
# 图元是挂在 world_root 下的真实 GPSymbolView 节点；连线是 GPEdgeView 节点。
# Pan and zoom are achieved by moving/scaling world_root.
# 平移与缩放通过移动/缩放 world_root 实现。
# Coding rule: every variable must declare its type explicitly (including container types).
# 编码规范：所有变量均显式声明类型（含容器类型）。

# Emitted when the graph data changes (node added, moved, edge added, etc.).
# 图数据变化时发出（节点新增、移动、连线新增等）。
signal gpGraphChanged

# Status snapshot for the bottom status bar: selection id, zoom, cursor world pos.
# 底部状态栏用的状态快照：选中 id、缩放、光标世界坐标。
signal gpStatusUpdated(info: Dictionary)

# Interaction modes: select/move symbols or connect them with edges.
# 交互模式：选择/移动图元，或为图元连线。
enum GPMode { GP_SELECT, GP_CONNECT }

# The topology graph this canvas displays and edits.
# 本画布显示并编辑的拓扑图。
var gpGraph: GPPIDGraph

# Available symbol definitions used to create new nodes.
# 用于创建新节点的可用图元定义。
var gpDefs: Array[GPSymbolDef] = []

# Graph binder that owns the incremental view caches and sync logic (composition child).
# 持有增量视图缓存与同步逻辑的图绑定器（组合子节点）。
var gpBinder: GPGraphBinder = null

# Monotonically increasing id counter for new nodes and edges.
# 新节点与新边的单调递增 id 计数器。
var gpNextId: int = 1

# ---- world root ----
# ---- 世界根节点 ----
# Node2D that holds all symbol/edge view nodes and carries the camera transform.
# 承载所有图元/连线视图节点并承载相机变换的 Node2D。
var gpWorldRoot: Node2D = null

# ---- camera ----
# ---- 相机 ----
# Canvas pixel offset of the world origin (0,0).
# 世界原点 (0,0) 在画布上的像素偏移。
var gpViewOffset: Vector2 = Vector2.ZERO

# Current zoom factor (1.0 = 100%).
# 当前缩放系数（1.0 = 100%）。
var gpViewZoom: float = 1.0

# ---- interaction state ----
# ---- 交互状态 ----
# Current interaction mode.
# 当前交互模式。
var gpMode: int = GPMode.GP_SELECT

# Symbol definition waiting to be placed by the next left click.
# 等待下一次左键放置的图元定义。
var gpPendingDef: GPSymbolDef = null

# Id of the currently selected node.
# 当前选中节点的 id。
var gpSelectedId: String = ""

# Id of the node selected as the connection source.
# 被选为连线起点的节点 id。
var gpConnectFrom: String = ""

# Whether the user is currently middle-button panning.
# 用户是否正在中键平移。
var _gpPanning: bool = false

# Mouse position where panning started.
# 开始平移时的鼠标位置。
var _gpPanStart: Vector2 = Vector2.ZERO

# View offset when panning started.
# 开始平移时的视图偏移。
var _gpPanOffsetStart: Vector2 = Vector2.ZERO

# Id of the node being dragged.
# 正在被拖拽的节点 id。
var _gpDragId: String = ""

# Offset from node center to mouse when dragging started.
# 开始拖拽时节点中心到鼠标的偏移。
var _gpDragOffset: Vector2 = Vector2.ZERO

# Last known mouse position in world coordinates.
# 最近一次鼠标在世界坐标系中的位置。
var _gpLastMouseWorld: Vector2 = Vector2.ZERO


# Initialize the canvas: create world root and connect global signals.
# 初始化画布：创建世界根节点并连接全局信号。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	# Create the world root. All symbol/edge views live here so they share one transform.
	# 创建世界根节点。所有图元/连线视图都挂在此处，共享同一变换。
	gpWorldRoot = Node2D.new()
	gpWorldRoot.name = "WorldRoot"
	add_child(gpWorldRoot)
	# Create the graph binder that owns view-sync logic and caches.
	# 创建持有视图同步逻辑与缓存的图绑定器。
	gpBinder = GPGraphBinder.new()
	gpBinder.name = "GraphBinder"
	add_child(gpBinder)
	gpBinder.gpWorldRoot = gpWorldRoot
	# Subscribe to language and font changes so symbol labels stay in sync.
	# 订阅语言与字体变化，保持图元文字同步。
	I18n.gpLocaleChanged.connect(_gpOnLocaleChanged)
	Settings.gpSymbolStyleChanged.connect(_gpOnSymbolStyleChanged)
	_gpResetView()


# React to language change by refreshing symbol labels.
# 语言变化时刷新图元标签。
func _gpOnLocaleChanged(_gpLocale: String) -> void:
	_gpRefreshSymbols()


# React to symbol font/style change by refreshing symbol labels.
# 图元字体/样式变化时刷新图元标签。
func _gpOnSymbolStyleChanged() -> void:
	_gpRefreshSymbols()


# Build and emit a status snapshot for the status bar.
# 构造并发送状态栏快照。
func _gpEmitStatus() -> void:
	gpStatusUpdated.emit({
		"selection": gpSelectedId,
		"zoom": gpViewZoom,
		"world": _gpLastMouseWorld,
	})


# ============================ camera / transform ============================
# ============================ 相机 / 坐标变换 ============================
# Reset the camera to 100% zoom and center the world origin.
# 将相机重置为 100% 缩放并把世界原点居中。
func _gpResetView() -> void:
	gpViewZoom = 1.0
	gpViewOffset = size / 2.0
	_gpApplyCamera()


# Apply gpViewOffset and gpViewZoom to the world root.
# 将 gpViewOffset 与 gpViewZoom 应用到世界根节点。
func _gpApplyCamera() -> void:
	if gpWorldRoot == null:
		return
	gpWorldRoot.position = gpViewOffset
	gpWorldRoot.scale = Vector2(gpViewZoom, gpViewZoom)


# Convert a world coordinate to a screen coordinate.
# 将世界坐标转换为屏幕坐标。
func gpScreenFromWorld(w: Vector2) -> Vector2:
	return w * gpViewZoom + gpViewOffset


# Convert a screen coordinate to a world coordinate.
# 将屏幕坐标转换为世界坐标。
func gpWorldFromScreen(gpS: Vector2) -> Vector2:
	return (gpS - gpViewOffset) / gpViewZoom


# ============================ drawing (background only) ============================
# ============================ 绘制（仅背景） ============================
# Godot calls this when the canvas needs to redraw the background overlay.
# Godot 在需要重绘背景覆盖层时调用此方法。
func _draw() -> void:
	# Sync the node tree with the graph before drawing the background overlay.
	# 在绘制背景覆盖层之前，先把节点树与图数据同步。
	_gpSyncViews()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.14, 0.18))
	_gpDrawGrid()
	_gpDrawConnectPreview()


# Draw the background grid aligned to the world coordinate system.
# 绘制与世界坐标系对齐的背景网格。
func _gpDrawGrid() -> void:
	var gpStep: float = 50.0 * gpViewZoom
	if gpStep < 8.0:
		return
	var gpStartX: int = int(fmod(gpViewOffset.x, gpStep))
	var gpStartY: int = int(fmod(gpViewOffset.y, gpStep))
	var gpCol: Color = Color(0.22, 0.24, 0.30, 0.6)
	# Vertical grid lines.
	# 垂直网格线。
	var x: int = gpStartX
	while x < int(size.x):
		draw_line(Vector2(x, 0), Vector2(x, size.y), gpCol, 1.0)
		x += int(gpStep)
	# Horizontal grid lines.
	# 水平网格线。
	var y: int = gpStartY
	while y < int(size.y):
		draw_line(Vector2(0, y), Vector2(size.x, y), gpCol, 1.0)
		y += int(gpStep)


# Draw the rubber-band line when connecting two symbols.
# 连接两个图元时绘制橡皮筋线。
func _gpDrawConnectPreview() -> void:
	if gpMode != GPMode.GP_CONNECT or gpConnectFrom == "":
		return
	var gpC: Vector2 = _gpNodeCenter(gpConnectFrom)
	if gpC == Vector2.INF:
		return
	draw_line(gpScreenFromWorld(gpC), get_local_mouse_position(), Color(0.30, 1.0, 0.40), 1.5)


# ============================ view sync ============================
# ============================ 视图同步 ============================
# Sync both symbol views and edge views to the current graph state.
# 将图元视图与连线视图同步到当前图状态。
func _gpSyncViews() -> void:
	if gpBinder == null:
		return
	gpBinder.gpSync(gpGraph, gpDefs, gpSelectedId, gpConnectFrom)




# Queue redraw on all symbol views (delegates to binder).
# 令所有图元视图重新绘制（委托给绑定器）。
func _gpRefreshSymbols() -> void:
	if gpBinder != null:
		gpBinder.gpRefreshSymbols()


# ============================ lookup ============================
# ============================ 查找 ============================
# Find the world center of a node by id.
# 按 id 查找节点的世界中心。
func _gpNodeCenter(gpId: String) -> Vector2:
	for gpN in gpGraph.gpNodes:
		if gpN.gpInstanceId == gpId:
			return gpN.gpPosition
	return Vector2.INF


# Hit-test: return the id of the topmost node under the given world point.
# 命中测试：返回指定世界坐标点下最上层节点的 id。
func _gpHitTest(gpWorld: Vector2) -> String:
	var gpBest: String = ""
	for gpN in gpGraph.gpNodes:
		var gpDef: GPSymbolDef = gpBinder.gpDefFor(gpN.gpSymbolId)
		var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
		var gpC: Vector2 = gpN.gpPosition
		var gpRect: Rect2 = Rect2(gpC - gpSz / 2.0, gpSz)
		if gpRect.has_point(gpWorld):
			gpBest = gpN.gpInstanceId
	return gpBest


# Update the position of a graph node in-place.
# 就地更新图节点的位置。
func _gpSetNodePos(gpId: String, gpWorld: Vector2) -> void:
	for gpN in gpGraph.gpNodes:
		if gpN.gpInstanceId == gpId:
			gpN.gpPosition = gpWorld
			return


# ============================ input ============================
# ============================ 输入 ============================
# Handle all mouse input events for the canvas.
# 处理画布的所有鼠标输入事件。
func _gui_input(gpEvent: InputEvent) -> void:
	if gpEvent is InputEventMouseButton:
		var gpMouseEvent: InputEventMouseButton = gpEvent as InputEventMouseButton
		# Mouse wheel zooms in/out at the cursor position.
		# 鼠标滚轮在光标位置缩放。
		if gpMouseEvent.button_index == MOUSE_BUTTON_WHEEL_UP or gpMouseEvent.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if gpMouseEvent.pressed:
				var gpFactor: float = 1.0 if gpMouseEvent.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				_gpZoomAt(gpMouseEvent.position, gpFactor)
			accept_event()
			return
		# Middle button starts/ends panning.
		# 中键开始/结束平移。
		if gpMouseEvent.button_index == MOUSE_BUTTON_MIDDLE:
			if gpMouseEvent.pressed:
				_gpPanning = true
				_gpPanStart = gpMouseEvent.position
				_gpPanOffsetStart = gpViewOffset
			else:
				_gpPanning = false
			accept_event()
			return
		# Left button places, selects or connects symbols.
		# 左键放置、选择或连接图元。
		if gpMouseEvent.button_index == MOUSE_BUTTON_LEFT:
			if gpMouseEvent.pressed:
				_gpOnLeftDown(gpMouseEvent.position)
			else:
				_gpDragId = ""
			accept_event()
			return

	if gpEvent is InputEventMouseMotion:
		var gpMotion: InputEventMouseMotion = gpEvent as InputEventMouseMotion
		_gpLastMouseWorld = gpWorldFromScreen(gpMotion.position)
		# Panning in progress.
		# 正在平移。
		if _gpPanning:
			gpViewOffset = _gpPanOffsetStart + (gpMotion.position - _gpPanStart)
			_gpApplyCamera()
			queue_redraw()
			_gpEmitStatus()
			accept_event()
			return
		# Dragging a selected node.
		# 正在拖拽选中节点。
		if _gpDragId != "":
			var gpWorld: Vector2 = gpWorldFromScreen(gpMotion.position)
			_gpSetNodePos(_gpDragId, gpWorld + _gpDragOffset)
			var gpV: GPSymbolView = gpBinder.gpGetSymbolView(_gpDragId)
			if gpV != null:
				gpV.gpUpdateTransform()
			# Edge views depend on node positions, so redraw them too.
			# 边视图依赖节点位置，因此也重绘它们。
			_gpRefreshEdges()
			queue_redraw()
			_gpEmitStatus()
			accept_event()
			return
		# Moving the mouse may update the connect-preview rubber band.
		# 移动鼠标可能更新连接预览橡皮筋。
		if gpMode == GPMode.GP_CONNECT and gpConnectFrom != "":
			queue_redraw()


# Queue redraw on all edge views (delegates to binder).
# 令所有连线视图重新绘制（委托给绑定器）。
func _gpRefreshEdges() -> void:
	if gpBinder != null:
		gpBinder.gpRefreshEdges()


# Handle a left mouse button press.
# 处理鼠标左键按下。
func _gpOnLeftDown(gpScreen: Vector2) -> void:
	var gpWorld: Vector2 = gpWorldFromScreen(gpScreen)

	# If a symbol is pending from the palette, place it now.
	# 如果调色板有等待放置的图元，立即放置。
	if gpPendingDef != null:
		var gpNid: String = "n%d" % gpNextId
		gpNextId += 1
		# Leave the label empty so the canvas renders the localized type name and
		# it switches with the UI language. The user can still type a custom label.
		# 标签留空，使画布显示本地化的类型名并随界面语言切换；用户仍可在属性面板填自定义标签。
		gpGraph.gpAddNode(gpGraph.gpNewNode(gpNid, gpPendingDef.gpId, "", gpWorld, {}))
		gpSelectedId = gpNid
		gpPendingDef = null
		queue_redraw()
		gpGraphChanged.emit()
		_gpEmitStatus()
		return

	var gpHit: String = _gpHitTest(gpWorld)

	# Connect mode: pick source then destination.
	# 连线模式：先选起点再选终点。
	if gpMode == GPMode.GP_CONNECT:
		if gpHit != "":
			if gpConnectFrom == "":
				gpConnectFrom = gpHit
			else:
				if gpConnectFrom != gpHit:
					var gpEid: String = "e%d" % gpNextId
					gpNextId += 1
					gpGraph.gpAddEdge(gpGraph.gpNewEdge(gpEid, gpConnectFrom, gpHit, {}))
					gpGraphChanged.emit()
				gpConnectFrom = ""
			queue_redraw()
		return

	# SELECT mode.
	# 选择模式。
	gpSelectedId = gpHit
	if gpHit != "":
		_gpDragId = gpHit
		_gpDragOffset = _gpNodeCenter(gpHit) - gpWorld
	queue_redraw()
	_gpEmitStatus()


# Zoom in or out while keeping the world point under the cursor stable.
# 以光标下的世界点为中心进行缩放。
func _gpZoomAt(gpScreen: Vector2, gpFactor: float) -> void:
	var gpWorldBefore: Vector2 = gpWorldFromScreen(gpScreen)
	gpViewZoom *= (1.0 + 0.12 * gpFactor)
	gpViewZoom = clampf(gpViewZoom, 0.25, 4.0)
	var gpScreenAfter: Vector2 = gpScreenFromWorld(gpWorldBefore)
	gpViewOffset += gpScreen - gpScreenAfter
	_gpApplyCamera()
	queue_redraw()
	_gpEmitStatus()


# Public: zoom by a step centered on the canvas (menu "放大/缩小").
# 公开：以画布中心为锚点缩放一步（菜单「放大/缩小」）。
func gpZoomStep(gpFactor: float) -> void:
	_gpZoomAt(size / 2.0, gpFactor)


# Public: reset view to 100% centered (menu "适应窗口").
# 公开：重置视图为 100% 居中（菜单「适应窗口」）。
func gpResetView() -> void:
	_gpResetView()
	queue_redraw()
	_gpEmitStatus()


# Clean up cached references when the canvas leaves the tree.
# 画布离开场景树时清理缓存引用。
func _notification(gpWhat: int) -> void:
	if gpWhat == NOTIFICATION_PREDELETE:
		if gpBinder != null:
			gpBinder.gpClear()
