class_name GPCanvas2D
extends Control

const GPSymbolView := preload("res://src/render/symbol_view.gd")
const GPEdgeView := preload("res://src/render/edge_view.gd")

# 2D canvas implemented with a Node2D world_root.
# 2D 画布：使用 Node2D 作为 world_root 实现。
# Symbols are real GPSymbolView nodes under world_root; edges are GPEdgeView nodes.
# 图元是挂在 world_root 下的真实 GPSymbolView 节点；连线是 GPEdgeView 节点。
# Pan and zoom are achieved by moving/scaling world_root.
# 平移与缩放通过移动/缩放 world_root 实现。
# Coding rule: every variable must declare its type explicitly (including container types).
# 编码规范：所有变量均显式声明类型（含容器类型）。

signal gpGraphChanged

# Status snapshot for the bottom status bar: selection id, zoom, cursor world pos.
# 底部状态栏用的状态快照：选中 id、缩放、光标世界坐标。
signal gpStatusUpdated(info: Dictionary)

enum GPMode { GP_SELECT, GP_CONNECT }

var gpGraph: GPPIDGraph
var gpDefs: Array[GPSymbolDef] = []
var gpNextId: int = 1

# ---- world root ----
# ---- 世界根节点 ----
var gpWorldRoot: Node2D = null

# ---- camera ----
# ---- 相机 ----
var gpViewOffset: Vector2 = Vector2.ZERO
var gpViewZoom: float = 1.0

# ---- interaction state ----
# ---- 交互状态 ----
var gpMode: int = GPMode.GP_SELECT
var gpPendingDef: GPSymbolDef = null
var gpSelectedId: String = ""
var gpConnectFrom: String = ""

var _gpPanning: bool = false
var _gpPanStart: Vector2 = Vector2.ZERO
var _gpPanOffsetStart: Vector2 = Vector2.ZERO
var _gpDragId: String = ""
var _gpDragOffset: Vector2 = Vector2.ZERO
var _gpLastMouseWorld: Vector2 = Vector2.ZERO

# View caches: id -> view node. Used for incremental sync instead of full rebuild.
# 视图缓存：id → 视图节点。用于增量同步而非全量重建。
var _gpSymbolViews: Dictionary = {}
var _gpEdgeViews: Dictionary = {}


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	# Create the world root. All symbol/edge views live here so they share one transform.
	# 创建世界根节点。所有图元/连线视图都挂在此处，共享同一变换。
	gpWorldRoot = Node2D.new()
	gpWorldRoot.name = "WorldRoot"
	add_child(gpWorldRoot)
	# Subscribe to language and font changes so symbol labels stay in sync.
	# 订阅语言与字体变化，保持图元文字同步。
	I18n.gpLocaleChanged.connect(_gpOnLocaleChanged)
	Settings.gpSymbolStyleChanged.connect(_gpOnSymbolStyleChanged)
	_gpResetView()


func _gpOnLocaleChanged(_gpLocale: String) -> void:
	_gpRefreshSymbols()


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
func _gpResetView() -> void:
	gpViewZoom = 1.0
	gpViewOffset = size / 2.0
	_gpApplyCamera()


func _gpApplyCamera() -> void:
	if gpWorldRoot == null:
		return
	gpWorldRoot.position = gpViewOffset
	gpWorldRoot.scale = Vector2(gpViewZoom, gpViewZoom)


func gpScreenFromWorld(w: Vector2) -> Vector2:
	return w * gpViewZoom + gpViewOffset


func gpWorldFromScreen(gpS: Vector2) -> Vector2:
	return (gpS - gpViewOffset) / gpViewZoom


# ============================ drawing (background only) ============================
# ============================ 绘制（仅背景） ============================
func _draw() -> void:
	# Sync the node tree with the graph before drawing the background overlay.
	# 在绘制背景覆盖层之前，先把节点树与图数据同步。
	_gpSyncViews()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.14, 0.18))
	_gpDrawGrid()
	_gpDrawConnectPreview()


func _gpDrawGrid() -> void:
	var gpStep: float = 50.0 * gpViewZoom
	if gpStep < 8.0:
		return
	var gpStartX: int = int(fmod(gpViewOffset.x, gpStep))
	var gpStartY: int = int(fmod(gpViewOffset.y, gpStep))
	var gpCol: Color = Color(0.22, 0.24, 0.30, 0.6)
	var x: int = gpStartX
	while x < int(size.x):
		draw_line(Vector2(x, 0), Vector2(x, size.y), gpCol, 1.0)
		x += int(gpStep)
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
func _gpSyncViews() -> void:
	if gpGraph == null or gpWorldRoot == null:
		return
	_gpSyncSymbolViews()
	_gpSyncEdgeViews()


func _gpSyncSymbolViews() -> void:
	var gpFresh: Dictionary = {}
	for gpN in gpGraph.gpNodes:
		var gpId: String = gpN.get("id", "")
		if gpId == "":
			continue
		var gpV: GPSymbolView = null
		if _gpSymbolViews.has(gpId):
			gpV = _gpSymbolViews[gpId] as GPSymbolView
			gpV.gpNode = gpN
			gpV.gpUpdateTransform()
		else:
			gpV = GPSymbolView.new()
			var gpDef: GPSymbolDef = _gpDefFor(gpN.get("type", ""))
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


func _gpSyncEdgeViews() -> void:
	var gpFresh: Dictionary = {}
	for gpE in gpGraph.gpEdges:
		var gpId: String = gpE.get("id", "")
		if gpId == "":
			continue
		var gpV: GPEdgeView = null
		if _gpEdgeViews.has(gpId):
			gpV = _gpEdgeViews[gpId] as GPEdgeView
			gpV.gpEdge = gpE
			gpV.queue_redraw()
		else:
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


func _gpRefreshSymbols() -> void:
	for gpId in _gpSymbolViews.keys():
		var gpV: GPSymbolView = _gpSymbolViews[gpId] as GPSymbolView
		gpV.queue_redraw()


# ============================ lookup ============================
# ============================ 查找 ============================
func _gpDefFor(gpTypeId: String) -> GPSymbolDef:
	for gpD in gpDefs:
		if gpD.gpId == gpTypeId:
			return gpD
	return null


func _gpNodeCenter(gpId: String) -> Vector2:
	for gpN in gpGraph.gpNodes:
		if gpN.get("id", "") == gpId:
			var gpPos: Array = gpN.get("pos", [0.0, 0.0])
			return Vector2(float(gpPos[0]), float(gpPos[1]))
	return Vector2.INF


func _gpHitTest(gpWorld: Vector2) -> String:
	var gpBest: String = ""
	for gpN in gpGraph.gpNodes:
		var gpDef: GPSymbolDef = _gpDefFor(gpN.get("type", ""))
		var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
		var gpPos: Array = gpN.get("pos", [0.0, 0.0])
		var gpC: Vector2 = Vector2(float(gpPos[0]), float(gpPos[1]))
		var gpRect: Rect2 = Rect2(gpC - gpSz / 2.0, gpSz)
		if gpRect.has_point(gpWorld):
			gpBest = gpN.get("id", "")
	return gpBest


func _gpSetNodePos(gpId: String, gpWorld: Vector2) -> void:
	for gpN in gpGraph.gpNodes:
		if gpN.get("id", "") == gpId:
			gpN["pos"] = [gpWorld.x, gpWorld.y]
			return


# ============================ input ============================
# ============================ 输入 ============================
func _gui_input(gpEvent: InputEvent) -> void:
	if gpEvent is InputEventMouseButton:
		var gpMouseEvent: InputEventMouseButton = gpEvent as InputEventMouseButton
		if gpMouseEvent.button_index == MOUSE_BUTTON_WHEEL_UP or gpMouseEvent.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if gpMouseEvent.pressed:
				var gpFactor: float = 1.0 if gpMouseEvent.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				_gpZoomAt(gpMouseEvent.position, gpFactor)
			accept_event()
			return
		if gpMouseEvent.button_index == MOUSE_BUTTON_MIDDLE:
			if gpMouseEvent.pressed:
				_gpPanning = true
				_gpPanStart = gpMouseEvent.position
				_gpPanOffsetStart = gpViewOffset
			else:
				_gpPanning = false
			accept_event()
			return
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
		if _gpPanning:
			gpViewOffset = _gpPanOffsetStart + (gpMotion.position - _gpPanStart)
			_gpApplyCamera()
			queue_redraw()
			_gpEmitStatus()
			accept_event()
			return
		if _gpDragId != "":
			var gpWorld: Vector2 = gpWorldFromScreen(gpMotion.position)
			_gpSetNodePos(_gpDragId, gpWorld + _gpDragOffset)
			var gpV: GPSymbolView = _gpSymbolViews.get(_gpDragId, null) as GPSymbolView
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


func _gpRefreshEdges() -> void:
	for gpId in _gpEdgeViews.keys():
		var gpV: GPEdgeView = _gpEdgeViews[gpId] as GPEdgeView
		gpV.queue_redraw()


func _gpOnLeftDown(gpScreen: Vector2) -> void:
	var gpWorld: Vector2 = gpWorldFromScreen(gpScreen)

	if gpPendingDef != null:
		var gpNid: String = "n%d" % gpNextId
		gpNextId += 1
		# Leave the label empty so the canvas renders the localized type name and
		# it switches with the UI language. The user can still type a custom label.
		# 标签留空，使画布显示本地化的类型名并随界面语言切换；用户仍可在属性面板填自定义标签。
		gpGraph.gpAddNode(gpNid, gpPendingDef.gpId, "", gpWorld, {})
		gpSelectedId = gpNid
		gpPendingDef = null
		queue_redraw()
		gpGraphChanged.emit()
		_gpEmitStatus()
		return

	var gpHit: String = _gpHitTest(gpWorld)

	if gpMode == GPMode.GP_CONNECT:
		if gpHit != "":
			if gpConnectFrom == "":
				gpConnectFrom = gpHit
			else:
				if gpConnectFrom != gpHit:
					var gpEid: String = "e%d" % gpNextId
					gpNextId += 1
					gpGraph.gpAddEdge(gpEid, gpConnectFrom, gpHit, {})
					gpGraphChanged.emit()
				gpConnectFrom = ""
			queue_redraw()
		return

	# SELECT
	# 选择模式
	gpSelectedId = gpHit
	if gpHit != "":
		_gpDragId = gpHit
		_gpDragOffset = _gpNodeCenter(gpHit) - gpWorld
	queue_redraw()
	_gpEmitStatus()


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


func _notification(gpWhat: int) -> void:
	# Clean up cached references when the canvas leaves the tree.
	# 画布离开场景树时清理缓存引用。
	if gpWhat == NOTIFICATION_PREDELETE:
		_gpSymbolViews.clear()
		_gpEdgeViews.clear()
