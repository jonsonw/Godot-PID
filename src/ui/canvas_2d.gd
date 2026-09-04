class_name GPCanvas2D
extends Control

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

# Emitted to ask the host to open an in-place (isolated) editor for one symbol type.
# Carried on the canvas rather than the node so the host decides where to mount the editor.
# 请求宿主为某个图元类型打开就地（隔离）编辑器时发出。
# 挂在画布而非节点上，由宿主决定把编辑器挂到哪里。
signal gpSymbolEditRequested(gpSymbolId: String)

# Emitted whenever the interaction mode (select / connect) changes so the host toolbar
# keeps its highlight in sync with the canvas (e.g. when toggled from the context menu).
# 交互模式（选择 / 连线）变化时发出，使宿主工具栏与画布保持高亮同步（例如右键菜单切换时）。
signal gpModeChanged(gpNewMode: int)

# Emitted when the user asks to "promote" the selected annotation shapes into a real symbol.
# Carries the geometry as an author-space shape dict (paths / circles / rects), ready to be
# loaded into the isolation editor's glyph canvas. The host opens the editor pre-seeded.
# 用户要把选中的注释图形「提升」为真正图元时发出。携带的图形为作者空间字典
# （paths / circles / rects），可直接载入隔离编辑器的几何画板。宿主打开预装好的编辑器。
signal gpMakeSymbolRequested(gpDraft: Dictionary)

# Emitted when the user asks to create a brand-new (blank) symbol straight from the canvas
# context menu on empty space. Carries no payload — the host opens the isolation editor in
# CREATE mode (the very same editor the toolbar "New Symbol…" button opens).
# 用户在空白处右键菜单要求直接「创建图元」（空白新图元）时发出。无载荷——宿主以「新建」模式
# 打开隔离编辑器（与工具栏「新建图元…」按钮打开的编辑器完全相同）。
signal gpNewSymbolRequested

# Minimum drag distance (screen px) before a press becomes a marquee instead of a click.
# 按下后要成为框选（而非单击）所需的最小拖拽距离（屏幕像素）。
const GP_MARQUEE_MIN: float = 4.0

# Context-menu action ids. Ids (not positions) keep the handlers correct when optional
# items are inserted, because PopupMenu ids do not shift the way indices do.
# 右键菜单动作 id。用 id（而非位置）可在插入可选项后仍保持处理正确，
# 因为 PopupMenu 的 id 不会像下标那样位移。
const GP_CTX_EDIT: int = 0
const GP_CTX_DUPLICATE: int = 1
const GP_CTX_DELETE: int = 2
const GP_CTX_SELECT_ALL: int = 3
const GP_CTX_DESELECT: int = 4
const GP_CTX_CONNECT: int = 5
const GP_CTX_MAKE_SYMBOL: int = 6
const GP_CTX_NEW_SYMBOL: int = 7

# Grip (handle) roles for annotation-shape editing — mirrors AutoCAD grips: a selected shape
# shows small squares at its anchor / vertex points; dragging one reshapes or resizes it.
# 注释图形编辑用的锚点（手柄）角色 —— 对齐 AutoCAD 夹点：选中图形后在其锚点 / 顶点处显示小方块，
# 拖动即可重塑或缩放图形。
const GP_GRIP_ENDPOINT: int = 1   # 直线端点 / line endpoint
const GP_GRIP_CENTER: int = 2     # 圆心 / circle center (move)
const GP_GRIP_RADIUS: int = 3     # 圆半径手柄 / circle radius handle
const GP_GRIP_CORNER: int = 4     # 矩形角点 / rectangle corner (resize)
const GP_GRIP_VERTEX: int = 5     # 折线顶点 / polyline vertex

# Interaction modes: select/move symbols, connect them with edges, or draw annotation shapes.
# 交互模式：选择/移动图元、为图元连线，或直接绘制注释图形。
# Drawing modes are appended last so the legacy SELECT/CONNECT values (0/1) stay unchanged.
# 绘图模式置于末尾，使旧的选择/连线取值（0/1）保持不变。
enum GPMode { GP_SELECT, GP_CONNECT, GP_DRAW_LINE, GP_DRAW_CIRCLE, GP_DRAW_RECT, GP_DRAW_POLYLINE }

# Set the interaction mode and notify listeners (the toolbar) so highlights stay correct.
# 设置交互模式并通知监听者（工具栏），使高亮保持正确。
func gpSetMode(gpM: int) -> void:
	if gpM != gpMode:
		gpMode = gpM
		# Entering a drawing tool clears any node selection so a left click draws instead of
		# re-selecting a symbol; the shape selection is left intact for marquee-style editing.
		# 进入绘图工具时清空图元选择，使左键变为绘制而非再次选中图元；图形选择保留以便框选式编辑。
		if gpM >= GPMode.GP_DRAW_LINE:
			gpSelection.clear()
			gpSelectedId = ""
		gpModeChanged.emit(gpMode)
		queue_redraw()

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

# Ids of the currently selected nodes. This is the SINGLE source of truth for selection;
# gpSelectedId below mirrors the primary entry so single-selection consumers (the inspector,
# the status bar) keep working unchanged.
# 当前选中节点的 id 集合。这是选择状态的唯一数据源；下面的 gpSelectedId 镜像主选项，
# 使单选消费者（属性面板、状态栏）无需改动即可继续工作。
var gpSelection: Array[String] = []

# Id of the currently selected node (primary entry of gpSelection, "" when none).
# 当前选中节点的 id（gpSelection 的主选项，无选中时为空）。
var gpSelectedId: String = ""

# Id of the node selected as the connection source.
# 被选为连线起点的节点 id。
var gpConnectFrom: String = ""

# Whether a marquee selection is in progress.
# 是否正在进行框选。
var _gpMarqueeing: bool = false

# Marquee endpoints in SCREEN space (drawn directly; converted to world on commit).
# 框选端点，屏幕空间（直接绘制；提交时换算到世界空间）。
var _gpMarqueeFrom: Vector2 = Vector2.ZERO
var _gpMarqueeTo: Vector2 = Vector2.ZERO

# Whether the in-progress marquee adds to the current selection (Shift held).
# 进行中的框选是否为追加模式（按住 Shift）。
var _gpMarqueeAdd: bool = false

# World position where the current multi-node drag started.
# 当前多节点拖拽开始时的世界坐标。
var _gpDragStartWorld: Vector2 = Vector2.ZERO

# Original world position of every dragged node, captured once at drag start. Replaying from
# these (instead of accumulating per-frame deltas) keeps the group from drifting.
# 每个被拖拽节点的原始世界坐标，在拖拽开始时一次性记下。由这些原始值重放（而非逐帧累加
# 增量）可避免整组漂移。
var _gpDragOrigins: Dictionary = {}

# Node id the right-click menu was opened on ("" when the click missed everything).
# 右键菜单打开时所处的节点 id（未命中任何节点时为空）。
var _gpCtxHit: String = ""

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

# Indices of the currently selected annotation shapes (mirror of gpSelection for the node layer).
# 当前选中注释图形的下标（与图元层的 gpSelection 对应的镜像）。
var gpShapeSel: Array[int] = []

# Anchor point (world) of the in-progress line / circle / rect drag.
# 进行中的直线/圆/矩形拖拽的锚点（世界坐标）。
var _gpDrawFrom: Vector2 = Vector2.ZERO

# Live cursor (world) of the in-progress shape drag, for the rubber-band preview.
# 进行中图形拖拽的实时光标（世界坐标），用于橡皮筋预览。
var _gpDrawTo: Vector2 = Vector2.ZERO

# Whether a line / circle / rect drag is active. Polyline uses _gpPolyPts instead.
# 直线/圆/矩形拖拽是否进行中。折线用 _gpPolyPts 而非此标记。
var _gpDrawActive: bool = false

# Committed-so-far polyline vertices (world) for the polyline drawing tool.
# 折线绘图工具已落定的顶点（世界坐标）。
var _gpPolyPts: Array[Vector2] = []

# Last known mouse position in world coordinates.
# 最近一次鼠标在世界坐标系中的位置。
var _gpLastMouseWorld: Vector2 = Vector2.ZERO

# Index of the annotation shape currently being moved as a whole (SELECT mode, -1 = none).
# 当前正被整体拖动的注释图形下标（选择模式，-1 表示无）。
var _gpShapeDragIdx: int = -1

# World position where a whole-shape move started (to measure the drag delta).
# 整体拖动开始时的世界坐标（用于测量拖拽位移）。
var _gpShapeDragStart: Vector2 = Vector2.ZERO

# Snapshot of the dragged shape's points/radius at drag start, so the move replays rigidly.
# 拖拽开始时图形点位 / 半径的快照，使整体移动无漂移地重放。
var _gpShapeDragOrigPts: PackedVector2Array = PackedVector2Array()
var _gpShapeDragOrigR: float = 0.0

# Active grip (handle) drag: {"shape": int, "role": int, "idx": int}; empty dict = none.
# 进行中的锚点（手柄）拖拽：{"shape": 下标, "role": 角色, "idx": 顶点/角点序号}；空字典表示无。
var _gpGripDrag: Dictionary = {}




# Initialize the canvas: create world root and connect global signals.
# 初始化画布：创建世界根节点并连接全局信号。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	# Confine all drawing (background grid, annotation shapes, world_root symbols and
	# grips) to this control's rect. Otherwise a panned/zoomed WorldRoot paints outside
	# the middle column and bleeds over the menu, symbol library, inspector and status
	# bar. clip_contents clips the whole canvas-item subtree (including the Node2D
	# WorldRoot), giving a proper AutoCAD-style viewport that never overflows.
	# 将所有绘制（背景网格、注释图形、world_root 图元与抓取点）限制在本控件矩形内。
	# 否则平移/缩放后的 WorldRoot 会画到中列之外，盖住菜单、图元库、属性面板与状态栏。
	# clip_contents 会裁剪整个 canvas-item 子树（含 Node2D 的 WorldRoot），形成不会溢出的
	# 类 AutoCAD 视口。
	clip_contents = true
	# Keyboard shortcuts (Delete / Ctrl+A / ESC) arrive through _gui_input, which requires focus.
	# 键盘快捷键（Delete / Ctrl+A / ESC）经 _gui_input 送达，而这需要焦点。
	focus_mode = Control.FOCUS_CLICK
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
		"count": gpSelection.size(),
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
	_gpDrawShapes()
	_gpDrawMarquee()
	_gpDrawConnectPreview()


# Draw the rubber-band marquee. CAD convention: dragging left->right is a WINDOW (only fully
# enclosed symbols are selected, blue); right->left is a CROSSING (anything touched, green).
# 绘制橡皮筋框选框。CAD 惯例：左→右为窗口模式（仅选中完全包含的图元，蓝色）；
# 右→左为交叉模式（碰到即选中，绿色）。
func _gpDrawMarquee() -> void:
	if not _gpMarqueeing:
		return
	var gpA: Vector2 = _gpMarqueeFrom.min(_gpMarqueeTo)
	var gpB: Vector2 = _gpMarqueeFrom.max(_gpMarqueeTo)
	var gpRect: Rect2 = Rect2(gpA, gpB - gpA)
	var gpWindow: bool = _gpMarqueeTo.x >= _gpMarqueeFrom.x
	var gpCol: Color = Color(0.30, 0.65, 1.0) if gpWindow else Color(0.30, 1.0, 0.50)
	draw_rect(gpRect, Color(gpCol.r, gpCol.g, gpCol.b, 0.15), true)
	draw_rect(gpRect, gpCol, false, 1.0)


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
	gpBinder.gpSync(gpGraph, gpDefs, gpSelection, gpConnectFrom)




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


# World-space bounding rectangle of a node, from its definition's nominal envelope.
# 节点在世界坐标系中的包围矩形，取自其定义的标称包络。
func _gpNodeRect(gpId: String) -> Rect2:
	if gpGraph == null or gpBinder == null:
		return Rect2()
	for gpN in gpGraph.gpNodes:
		if gpN.gpInstanceId == gpId:
			var gpDef: GPSymbolDef = gpBinder.gpDefFor(gpN.gpSymbolId)
			var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
			return Rect2(gpN.gpPosition - gpSz / 2.0, gpSz)
	return Rect2()


# Hit-test: return the id of the topmost node under the given world point.
# 命中测试：返回指定世界坐标点下最上层节点的 id。
func _gpHitTest(gpWorld: Vector2) -> String:
	if gpGraph == null:
		return ""
	var gpBest: String = ""
	for gpN in gpGraph.gpNodes:
		if _gpNodeRect(gpN.gpInstanceId).has_point(gpWorld):
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
# Handle all mouse and keyboard input for the canvas.
# 处理画布的全部鼠标与键盘输入。
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
				_gpOnLeftDown(gpMouseEvent.position, gpMouseEvent.shift_pressed, gpMouseEvent.double_click)
			else:
				_gpOnLeftUp(gpMouseEvent.position)
			accept_event()
			return
		# Right button opens the context menu.
		# 右键打开上下文菜单。
		if gpMouseEvent.button_index == MOUSE_BUTTON_RIGHT:
			if gpMouseEvent.pressed:
				_gpOnRightDown(gpMouseEvent.position)
			accept_event()
			return

	# Keyboard shortcuts (Delete / Ctrl+A / ESC).
	# 键盘快捷键（Delete / Ctrl+A / ESC）。
	if gpEvent is InputEventKey:
		var gpKey: InputEventKey = gpEvent as InputEventKey
		if gpKey.pressed and not gpKey.echo and _gpOnKey(gpKey):
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
		# Marquee in progress: track the rubber band.
		# 正在框选：跟踪橡皮筋。
		if _gpMarqueeing:
			_gpMarqueeTo = gpMotion.position
			queue_redraw()
			accept_event()
			return
		# Dragging the whole selection.
		# 正在拖拽整个选择集。
		if _gpDragId != "":
			_gpOnDragMove(gpMotion.position)
			accept_event()
			return
		# Dragging a grip (handle) of the selected annotation shape reshapes / resizes it.
		# 拖动选中注释图形的锚点（手柄）以重塑 / 缩放图形。
		if not _gpGripDrag.is_empty():
			_gpOnGripMove(gpWorldFromScreen(gpMotion.position))
			accept_event()
			return
		# Dragging the whole selected annotation shape moves it.
		# 拖动整枚选中的注释图形以移动之。
		if _gpShapeDragIdx >= 0:
			_gpOnShapeMove(gpWorldFromScreen(gpMotion.position))
			accept_event()
			return
		# Moving the mouse may update the connect-preview rubber band.
		# 移动鼠标可能更新连接预览橡皮筋。
		if gpMode == GPMode.GP_CONNECT and gpConnectFrom != "":
			queue_redraw()
		# While drawing a shape, the rubber band follows the cursor.
		# 绘制图形时橡皮筋跟随光标。
		if _gpDrawActive or not _gpPolyPts.is_empty():
			_gpDrawTo = gpWorldFromScreen(gpMotion.position)
			queue_redraw()
			accept_event()
			return


# Queue redraw on all edge views (delegates to binder).
# 令所有连线视图重新绘制（委托给绑定器）。
func _gpRefreshEdges() -> void:
	if gpBinder != null:
		gpBinder.gpRefreshEdges()


# Handle a left mouse button press.
# 处理鼠标左键按下。
# [param gpShift] Shift held -> additive selection instead of a fresh one.
# [param gpShift] 按住 Shift → 追加选择而非重新选择。
# [param gpDouble] second click of a double click -> open the in-place block editor.
# [param gpDouble] 双击的第二次点击 → 打开就地块编辑器。
func _gpOnLeftDown(gpScreen: Vector2, gpShift: bool, gpDouble: bool) -> void:
	var gpWorld: Vector2 = gpWorldFromScreen(gpScreen)

	# Drawing tools draw annotation shapes directly on the canvas (not in the symbol editor).
	# 绘图工具在主画布上直接绘制注释图形（而非在符号编辑器里）。
	if _gpIsDrawMode():
		_gpOnDrawDown(gpWorld, gpDouble)
		return

	# If a symbol is pending from the palette, place it now.
	# 如果调色板有等待放置的图元，立即放置。
	if gpPendingDef != null:
		var gpNid: String = "n%d" % gpNextId
		gpNextId += 1
		# Leave the label empty so the canvas renders the localized type name and
		# it switches with the UI language. The user can still type a custom label.
		# 标签留空，使画布显示本地化的类型名并随界面语言切换；用户仍可在属性面板填自定义标签。
		gpGraph.gpAddNode(gpGraph.gpNewNode(gpNid, gpPendingDef.gpId, "", gpWorld, {}))
		gpPendingDef = null
		_gpSetSelection([gpNid])
		queue_redraw()
		gpGraphChanged.emit()
		_gpEmitStatus()
		return

	var gpHit: String = _gpHitTest(gpWorld)

	# Double click edits the symbol's geometry in place (AutoCAD BEDIT entry point).
	# 双击就地编辑图元几何（AutoCAD BEDIT 入口）。
	if gpDouble and gpHit != "":
		var gpDblNode: GPPIDNode = gpGraph.gpGetNode(gpHit)
		if gpDblNode != null:
			gpSymbolEditRequested.emit(gpDblNode.gpSymbolId)
		return

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

	# SELECT mode: hit -> select (Shift toggles); miss -> start a marquee.
	# 选择模式：命中 → 选择（Shift 切换）；落空 → 开始框选。
	if gpHit != "":
		if gpShift:
			if gpSelection.has(gpHit):
				gpSelection.erase(gpHit)
			else:
				gpSelection.append(gpHit)
			_gpSetSelection(gpSelection)
		elif not gpSelection.has(gpHit):
			_gpSetSelection([gpHit])
		# Start a group drag only when the pressed node belongs to the selection. A Shift-click
		# that just removed it must not start moving the rest of the group.
		# 仅当按下的节点属于选择集时才开始整组拖拽。刚刚把它移除的 Shift 点击不应拖动余下的组。
		if gpSelection.has(gpHit):
			_gpDragId = gpHit
			_gpDragStartWorld = gpWorld
			_gpDragOrigins.clear()
			for gpId in gpSelection:
				var gpN: GPPIDNode = gpGraph.gpGetNode(gpId)
				if gpN != null:
					_gpDragOrigins[gpId] = gpN.gpPosition
		else:
			_gpDragId = ""
	else:
		# No symbol hit: try an annotation shape (grip editing has priority when one is selected).
		# 未命中图元：改试注释图形（选中一枚时锚点编辑优先）。
		var gpSh: int = _gpHitShape(gpWorld)
		if gpSh >= 0:
			if gpShapeSel.size() == 1:
				var gpGrip: Dictionary = _gpHitGrip(gpWorld, gpShapeSel[0])
				if not gpGrip.is_empty():
					_gpStartGripDrag(gpGrip)
					return
			if gpShift:
				if gpShapeSel.has(gpSh):
					gpShapeSel.erase(gpSh)
				else:
					gpShapeSel.append(gpSh)
			elif not gpShapeSel.has(gpSh):
				gpShapeSel = [gpSh]
				_gpSetSelection([])
			queue_redraw()
			# Begin a whole-shape move, replaying rigidly from the start snapshot.
			# 从此图形开始整体移动，由起始快照无漂移重放。
			_gpShapeDragIdx = gpSh
			_gpShapeDragStart = gpWorld
			if gpSh >= 0 and gpSh < gpGraph.gpShapes.size():
				_gpShapeDragOrigPts = gpGraph.gpShapes[gpSh].gpPoints.duplicate()
				_gpShapeDragOrigR = gpGraph.gpShapes[gpSh].gpRadius
			return
		# Empty space: clear selection and start a marquee.
		# 空白处：清空选择并开始框选。
		if not gpShift:
			_gpSetSelection([])
			gpShapeSel.clear()
		_gpMarqueeing = true
		_gpMarqueeFrom = gpScreen
		_gpMarqueeTo = gpScreen
		_gpMarqueeAdd = gpShift
	queue_redraw()
	_gpEmitStatus()


# Handle a left mouse button release: finish a marquee, a grip drag, a shape move or a group drag.
# 处理鼠标左键释放：结束框选、锚点拖拽、图形移动或整组拖拽。
func _gpOnLeftUp(gpScreen: Vector2) -> void:
	# Finish a grip (handle) drag — geometry already mutated live during the drag.
	# 结束锚点（手柄）拖拽——几何已在拖拽过程中实时变更。
	if not _gpGripDrag.is_empty():
		_gpGripDrag.clear()
		gpGraphChanged.emit()
		_gpEmitStatus()
		return
	# Finish a whole-shape move.
	# 结束整枚图形的移动。
	if _gpShapeDragIdx >= 0:
		_gpShapeDragIdx = -1
		_gpShapeDragOrigPts = PackedVector2Array()
		_gpShapeDragOrigR = 0.0
		gpGraphChanged.emit()
		_gpEmitStatus()
		return
	if _gpDrawActive:
		# Commit the line / circle / rect drag as a new annotation shape, then auto-select it
		# and return to SELECT so its grips appear immediately (AutoCAD-like direct edit).
		# 把直线/圆/矩形拖拽提交为新的注释图形，随后自动选中并切回选择模式，使其锚点立即出现。
		var gpNewIdx: int = _gpCommitDraw(gpWorldFromScreen(gpScreen))
		_gpDrawActive = false
		if gpNewIdx >= 0:
			gpShapeSel = [gpNewIdx]
			_gpSetSelection([])
			gpSetMode(GPMode.GP_SELECT)
		queue_redraw()
		gpGraphChanged.emit()
		_gpEmitStatus()
		return
	if _gpMarqueeing:
		_gpMarqueeing = false
		# A press/release without movement is a plain click, already handled on press.
		# 未产生位移的按下/释放只是普通单击，已在按下时处理过。
		if gpScreen.distance_to(_gpMarqueeFrom) > GP_MARQUEE_MIN:
			_gpCommitMarquee()
		queue_redraw()
		_gpEmitStatus()
		return
	if _gpDragId != "":
		_gpDragId = ""
		_gpDragOrigins.clear()
		gpGraphChanged.emit()
		_gpEmitStatus()


# ============================ drawing annotation shapes ============================
# ============================ 绘制注释图形 ============================
# True when the canvas is in one of the free-shape drawing modes.
# 画布处于某个自由图形绘图模式时返回真。
func _gpIsDrawMode() -> bool:
	return gpMode >= GPMode.GP_DRAW_LINE and gpMode <= GPMode.GP_DRAW_POLYLINE


# Press handler for the drawing tools. Two-point tools (line / circle / rect) anchor on press
# and commit on release; the polyline appends a vertex per click and finishes on double click.
# 绘图工具的按下处理。两点工具（直线/圆/矩形）按下锚定、松开提交；折线每次点击追加一个顶点，
# 双击结束。
func _gpOnDrawDown(gpWorld: Vector2, gpDouble: bool) -> void:
	match gpMode:
		GPMode.GP_DRAW_LINE, GPMode.GP_DRAW_CIRCLE, GPMode.GP_DRAW_RECT:
			_gpDrawFrom = gpWorld
			_gpDrawTo = gpWorld
			_gpDrawActive = true
			queue_redraw()
		GPMode.GP_DRAW_POLYLINE:
			if gpDouble:
				_gpFinishPolyline()
			else:
				_gpPolyPts.append(gpWorld)
				_gpDrawTo = gpWorld
				queue_redraw()


# Commit the in-progress line / circle / rect drag as a new annotation shape.
# 把进行中的直线/圆/矩形拖拽提交为一枚新的注释图形。
# Commit the in-progress line / circle / rect drag as a new annotation shape. Returns the new
# shape's index (or -1 when the drag was too small to be a real primitive).
# 把进行中的直线/圆/矩形拖拽提交为一枚新的注释图形。返回新图形的下标（过小则 -1）。
func _gpCommitDraw(gpTo: Vector2) -> int:
	var gpS: GPShape = null
	match gpMode:
		GPMode.GP_DRAW_LINE:
			if _gpDrawFrom.distance_to(gpTo) >= 2.0:
				gpS = GPShape.gpLine(_gpDrawFrom, gpTo)
		GPMode.GP_DRAW_CIRCLE:
			var gpR: float = _gpDrawFrom.distance_to(gpTo)
			if gpR >= 2.0:
				gpS = GPShape.gpCircle(_gpDrawFrom, gpR)
		GPMode.GP_DRAW_RECT:
			var gpR: Rect2 = Rect2(_gpDrawFrom, gpTo - _gpDrawFrom).abs()
			if gpR.size.x >= 2.0 and gpR.size.y >= 2.0:
				gpS = GPShape.gpRect(_gpDrawFrom, gpTo)
	if gpS != null:
		gpGraph.gpAddShape(gpS)
		return gpGraph.gpShapes.size() - 1
	return -1


# Finish a polyline drag: commit it as a new annotation shape when it has 2+ vertices.
# 结束折线拖拽：当顶点数 ≥ 2 时提交为一枚新的注释图形。
func _gpFinishPolyline() -> void:
	if _gpPolyPts.size() >= 2:
		gpGraph.gpAddShape(GPShape.gpPolyline(_gpPolyPts.duplicate(), false))
		var gpIdx: int = gpGraph.gpShapes.size() - 1
		gpShapeSel = [gpIdx]
		_gpSetSelection([])
		gpSetMode(GPMode.GP_SELECT)
		gpGraphChanged.emit()
	_gpPolyPts.clear()
	queue_redraw()
	_gpEmitStatus()


# Draw every annotation shape, its selection highlight and the in-progress rubber band.
# 绘制所有注释图形、其选择高亮与进行中的橡皮筋。
func _gpDrawShapes() -> void:
	if gpGraph == null:
		return
	var gpInk: Color = Color(0.92, 0.94, 0.98)
	var gpSelCol: Color = Color(0.45, 0.75, 1.0)
	for gpS in gpGraph.gpShapes:
		_gpDrawOneShape(gpS, gpInk)
	# Selection highlight (above the committed ink, below the rubber band).
	# 选择高亮（位于已绘制墨线之上、橡皮筋之下）。
	for gpIdx in gpShapeSel:
		if gpIdx >= 0 and gpIdx < gpGraph.gpShapes.size():
			var gpB: Rect2 = gpGraph.gpShapes[gpIdx].gpBBox()
			var gpPos: Vector2 = gpScreenFromWorld(gpB.position)
			var gpSize: Vector2 = gpB.size * gpViewZoom
			draw_rect(Rect2(gpPos, gpSize).grow(3.0), Color(gpSelCol, 0.9), false, 1.0)
	# Grips (handles) for the single selected shape — AutoCAD-style editing points the user can
	# drag to reshape / resize. Shown only for a single selection so a multi-pick drag stays a move.
	# 选中单枚图形时显示锚点（手柄）——用户可拖动的 AutoCAD 式编辑点，用于重塑 / 缩放。仅单选时显示，
	# 使多选拖拽保持为整体移动。
	if gpShapeSel.size() == 1:
		var gpSelIdx: int = gpShapeSel[0]
		if gpSelIdx >= 0 and gpSelIdx < gpGraph.gpShapes.size():
			var gpGrips: Array[Dictionary] = _gpShapeGrips(gpGraph.gpShapes[gpSelIdx])
			var gpGs: float = 8.0
			for gpG in gpGrips:
				var gpP: Vector2 = gpScreenFromWorld(gpG["pos"])
				var gpRect: Rect2 = Rect2(gpP - Vector2(gpGs * 0.5, gpGs * 0.5), Vector2(gpGs, gpGs))
				draw_rect(gpRect, Color(1.0, 1.0, 1.0), true)
				draw_rect(gpRect, Color(0.20, 0.50, 1.0), false, 1.5)
	# In-progress rubber band for line / circle / rect.
	# 直线/圆/矩形的进行中橡皮筋。
	if _gpDrawActive:
		var gpA: Vector2 = gpScreenFromWorld(_gpDrawFrom)
		var gpB: Vector2 = gpScreenFromWorld(_gpDrawTo)
		match gpMode:
			GPMode.GP_DRAW_LINE:
				draw_line(gpA, gpB, Color(1.0, 0.82, 0.25), 1.5)
			GPMode.GP_DRAW_CIRCLE:
				draw_circle(gpA, gpA.distance_to(gpB), Color(1.0, 0.82, 0.25, 0.7), false, 1.0)
			GPMode.GP_DRAW_RECT:
				draw_rect(Rect2(gpA, gpB - gpA).abs(), Color(1.0, 0.82, 0.25, 0.7), false, 1.0)
	# In-progress polyline: committed vertices + rubber band to the cursor.
	# 进行中的折线：已落定顶点 + 到光标的橡皮筋。
	if not _gpPolyPts.is_empty():
		var gpV: PackedVector2Array = PackedVector2Array()
		for gpP in _gpPolyPts:
			gpV.append(gpScreenFromWorld(gpP))
		if gpV.size() >= 2:
			draw_polyline(gpV, Color(1.0, 0.82, 0.25), 1.5)
		draw_line(gpScreenFromWorld(_gpPolyPts.back()), get_local_mouse_position(), Color(1.0, 0.82, 0.25, 0.6), 1.0)
		for gpP in _gpPolyPts:
			draw_circle(gpScreenFromWorld(gpP), 3.0, Color(1.0, 0.82, 0.25))


# Draw one annotation shape in screen space (world coords transformed by the camera).
# 在屏幕空间绘制一枚注释图形（世界坐标经相机变换）。
func _gpDrawOneShape(gpS: GPShape, gpInk: Color) -> void:
	match gpS.gpKind:
		GPShape.GPKind.GP_LINE:
			if gpS.gpPoints.size() >= 2:
				draw_line(gpScreenFromWorld(gpS.gpPoints[0]), gpScreenFromWorld(gpS.gpPoints[1]), gpInk, 2.0)
		GPShape.GPKind.GP_CIRCLE:
			if gpS.gpPoints.size() >= 1:
				draw_circle(gpScreenFromWorld(gpS.gpPoints[0]), gpS.gpRadius * gpViewZoom, gpInk, false, 2.0)
		GPShape.GPKind.GP_RECT:
			if gpS.gpPoints.size() >= 2:
				var gpR: Rect2 = Rect2(gpScreenFromWorld(gpS.gpPoints[0]), (gpS.gpPoints[1] - gpS.gpPoints[0]).abs() * gpViewZoom)
				draw_rect(gpR, gpInk, false, 2.0)
		GPShape.GPKind.GP_POLYLINE:
			var gpV: PackedVector2Array = PackedVector2Array()
			for gpP in gpS.gpPoints:
				gpV.append(gpScreenFromWorld(gpP))
			if gpS.gpClosed and gpV.size() >= 2:
				gpV.append(gpV[0])
			if gpV.size() >= 2:
				draw_polyline(gpV, gpInk, 2.0)


# Hit-test: return the index of the topmost annotation shape under the world point, or -1.
# 命中测试：返回世界坐标点下最上层注释图形的下标，未命中返回 -1。
func _gpHitShape(gpWorld: Vector2) -> int:
	if gpGraph == null:
		return -1
	var gpTol: float = 6.0 / gpViewZoom
	for gpI in range(gpGraph.gpShapes.size() - 1, -1, -1):
		if _gpHitShapePrim(gpWorld, gpGraph.gpShapes[gpI], gpTol):
			return gpI
	return -1


# Does a world point fall on / inside one shape (within the hit tolerance)?
# 世界坐标点是否落在某图形上 / 内（在命中容差内）？
func _gpHitShapePrim(gpWorld: Vector2, gpS: GPShape, gpTol: float) -> bool:
	match gpS.gpKind:
		GPShape.GPKind.GP_CIRCLE:
			if gpS.gpPoints.size() >= 1:
				return gpWorld.distance_to(gpS.gpPoints[0]) <= gpS.gpRadius + gpTol
		GPShape.GPKind.GP_RECT:
			if gpS.gpPoints.size() >= 2:
				return Rect2(gpS.gpPoints[0], (gpS.gpPoints[1] - gpS.gpPoints[0]).abs()).grow(gpTol).has_point(gpWorld)
		_:
			var gpPts: PackedVector2Array = gpS.gpPoints
			for gpI in range(gpPts.size() - 1):
				if _gpDistPointSeg(gpWorld, gpPts[gpI], gpPts[gpI + 1]) <= gpTol:
					return true
			if gpS.gpClosed and gpPts.size() >= 3:
				if _gpDistPointSeg(gpWorld, gpPts[gpPts.size() - 1], gpPts[0]) <= gpTol:
					return true
	return false


# Distance from point gpP to segment AB.
# 点 gpP 到线段 AB 的距离。
static func _gpDistPointSeg(gpP: Vector2, gpA: Vector2, gpB: Vector2) -> float:
	if gpA.is_equal_approx(gpB):
		return gpP.distance_to(gpA)
	var gpAB: Vector2 = gpB - gpA
	var gpLen2: float = gpAB.length_squared()
	if gpLen2 < 1e-9:
		return gpP.distance_to(gpA)
	var gpT: float = clampf(gpAB.dot(gpP - gpA) / gpLen2, 0.0, 1.0)
	return gpP.distance_to(gpA + gpAB * gpT)


# ============================ annotation-shape grip editing ============================
# ============================ 注释图形锚点编辑 ============================
# Translate a point list by gpDelta (pure helper for whole-shape moves).
# 把点列整体平移 gpDelta（整体移动用的纯助手）。
static func _gpShiftPoints(gpPts: PackedVector2Array, gpDelta: Vector2) -> PackedVector2Array:
	var gpOut: PackedVector2Array = PackedVector2Array()
	for gpP in gpPts:
		gpOut.append(gpP + gpDelta)
	return gpOut

# The 4 axis-aligned corners of a rect shape's bbox, in order TL, TR, BR, BL.
# 矩形图形包围盒的四个轴对齐角点，顺序为 左上 / 右上 / 右下 / 左下。
static func _gpRectCorners(gpS: GPShape) -> PackedVector2Array:
	var gpB: Rect2 = gpS.gpBBox()
	return PackedVector2Array([
		gpB.position,
		gpB.position + Vector2(gpB.size.x, 0.0),
		gpB.end,
		gpB.position + Vector2(0.0, gpB.size.y),
	])

# Compute the grip (handle) list for one shape. Each grip carries its world position, role and
# index so a drag can mutate the right vertex / corner / radius.
# 计算一枚图形的锚点（手柄）列表。每个锚点带有世界坐标、角色与序号，便于拖拽时修改正确的
# 顶点 / 角点 / 半径。
func _gpShapeGrips(gpS: GPShape) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	match gpS.gpKind:
		GPShape.GPKind.GP_LINE:
			if gpS.gpPoints.size() >= 2:
				gpOut.append({"pos": gpS.gpPoints[0], "role": GP_GRIP_ENDPOINT, "idx": 0})
				gpOut.append({"pos": gpS.gpPoints[1], "role": GP_GRIP_ENDPOINT, "idx": 1})
		GPShape.GPKind.GP_CIRCLE:
			if gpS.gpPoints.size() >= 1:
				var gpC: Vector2 = gpS.gpPoints[0]
				gpOut.append({"pos": gpC, "role": GP_GRIP_CENTER, "idx": 0})
				gpOut.append({"pos": gpC + Vector2(gpS.gpRadius, 0.0), "role": GP_GRIP_RADIUS, "idx": 1})
		GPShape.GPKind.GP_RECT:
			var gpCorners: PackedVector2Array = _gpRectCorners(gpS)
			for gpI in range(4):
				gpOut.append({"pos": gpCorners[gpI], "role": GP_GRIP_CORNER, "idx": gpI})
		GPShape.GPKind.GP_POLYLINE:
			for gpI in range(gpS.gpPoints.size()):
				gpOut.append({"pos": gpS.gpPoints[gpI], "role": GP_GRIP_VERTEX, "idx": gpI})
	return gpOut

# Return the grip under the world point (within screen-tolerant distance), or an empty dict.
# 返回世界坐标点下的锚点（在屏幕容差距离内），未命中返回空字典。
func _gpHitGrip(gpWorld: Vector2, gpShapeIdx: int) -> Dictionary:
	if gpShapeIdx < 0 or gpShapeIdx >= gpGraph.gpShapes.size():
		return {}
	var gpTol: float = 6.0 / gpViewZoom
	for gpG in _gpShapeGrips(gpGraph.gpShapes[gpShapeIdx]):
		if gpWorld.distance_to(gpG["pos"]) <= gpTol:
			# Tag the hit grip with its owning shape index so the drag can address the model.
			# 给命中的锚点标注所属图形下标，使拖拽能定位到模型。
			var gpRes: Dictionary = gpG.duplicate()
			gpRes["shape"] = gpShapeIdx
			return gpRes
	return {}

# Begin dragging the given grip (clears any whole-shape move so only the grip acts).
# 开始拖拽给定锚点（清除整图形移动，使仅锚点生效）。
func _gpStartGripDrag(gpGrip: Dictionary) -> void:
	_gpGripDrag = gpGrip.duplicate()
	_gpShapeDragIdx = -1
	queue_redraw()

# Live-update the shape geometry while a grip is being dragged.
# 拖拽锚点期间实时更新图形几何。
func _gpOnGripMove(gpWorld: Vector2) -> void:
	if _gpGripDrag.is_empty():
		return
	var gpIdx: int = int(_gpGripDrag["shape"])
	if gpIdx < 0 or gpIdx >= gpGraph.gpShapes.size():
		return
	var gpS: GPShape = gpGraph.gpShapes[gpIdx]
	var gpRole: int = int(_gpGripDrag["role"])
	var gpI: int = int(_gpGripDrag["idx"])
	match gpRole:
		GP_GRIP_ENDPOINT, GP_GRIP_VERTEX:
			if gpI >= 0 and gpI < gpS.gpPoints.size():
				gpS.gpPoints[gpI] = gpWorld
		GP_GRIP_CENTER:
			if gpS.gpPoints.size() >= 1:
				gpS.gpPoints[0] = gpWorld
		GP_GRIP_RADIUS:
			if gpS.gpPoints.size() >= 1:
				gpS.gpRadius = maxf(1.0, gpWorld.distance_to(gpS.gpPoints[0]))
		GP_GRIP_CORNER:
			# Keep the opposite corner fixed and rebuild the rect from the two opposite corners.
			# 保持对顶角固定，由两对顶角重建矩形。
			var gpCorners: PackedVector2Array = _gpRectCorners(gpS)
			var gpFixed: Vector2 = gpCorners[(gpI + 2) % 4]
			gpS.gpPoints = [gpFixed, gpWorld]
	queue_redraw()
	_gpEmitStatus()

# Live-update a whole-shape move by replaying from the start snapshot.
# 由起始快照重放，实时更新整枚图形的移动。
func _gpOnShapeMove(gpWorld: Vector2) -> void:
	if _gpShapeDragIdx < 0 or _gpShapeDragIdx >= gpGraph.gpShapes.size():
		return
	var gpDelta: Vector2 = gpWorld - _gpShapeDragStart
	var gpS: GPShape = gpGraph.gpShapes[_gpShapeDragIdx]
	gpS.gpPoints = _gpShiftPoints(_gpShapeDragOrigPts, gpDelta)
	# Circle radius is independent of translation (stored separately in gpRadius).
	# 圆的半径与平移无关（单独存于 gpRadius）。
	queue_redraw()
	_gpEmitStatus()


# Convert selected annotation shapes into an author-space shape dict (paths / circles / rects)
# for the isolation editor. All geometry is shifted so the combined bbox top-left is at the
# origin — GPSymbolNormalizer only keeps RELATIVE geometry, so absolute position is irrelevant.
# 把选中的注释图形转成作者空间形状字典（paths / circles / rects）供隔离编辑器使用。
# 所有几何都平移到「包围盒左上角位于原点」——GPSymbolNormalizer 只保留相对几何，绝对位置无关紧要。
func _gpShapesToDraft(gpShapes: Array[GPShape]) -> Dictionary:
	var gpMin := Vector2(INF, INF)
	for gpS in gpShapes:
		var gpB: Rect2 = gpS.gpBBox()
		gpMin = gpMin.min(gpB.position)
	var gpPaths: Array = []
	var gpCircles: Array = []
	var gpRects: Array = []
	for gpS in gpShapes:
		match gpS.gpKind:
			GPShape.GPKind.GP_LINE:
				if gpS.gpPoints.size() >= 2:
					gpPaths.append({
						"pts": [
							[gpS.gpPoints[0].x - gpMin.x, gpS.gpPoints[0].y - gpMin.y],
							[gpS.gpPoints[1].x - gpMin.x, gpS.gpPoints[1].y - gpMin.y],
						],
						"closed": false,
					})
			GPShape.GPKind.GP_POLYLINE:
				var gpPts: Array = []
				for gpP in gpS.gpPoints:
					gpPts.append([gpP.x - gpMin.x, gpP.y - gpMin.y])
				gpPaths.append({"pts": gpPts, "closed": gpS.gpClosed})
			GPShape.GPKind.GP_CIRCLE:
				if gpS.gpPoints.size() >= 1:
					gpCircles.append({"c": [gpS.gpPoints[0].x - gpMin.x, gpS.gpPoints[0].y - gpMin.y], "r": gpS.gpRadius})
			GPShape.GPKind.GP_RECT:
				if gpS.gpPoints.size() >= 2:
					var gpR: Rect2 = Rect2(gpS.gpPoints[0], (gpS.gpPoints[1] - gpS.gpPoints[0]).abs())
					gpRects.append({"pos": [gpR.position.x - gpMin.x, gpR.position.y - gpMin.y], "size": [gpR.size.x, gpR.size.y]})
	return {"paths": gpPaths, "circles": gpCircles, "rects": gpRects}


# Promote the selected annotation shapes into a real symbol: emit the geometry dict so the
# host opens the isolation editor pre-loaded with the same drawing.
# 把选中的注释图形提升为真正的图元：发射几何字典，使宿主打开已预装相同图形的隔离编辑器。
func _gpMakeSymbolFromShapes() -> void:
	var gpShapes: Array[GPShape] = []
	for gpIdx in gpShapeSel:
		if gpIdx >= 0 and gpIdx < gpGraph.gpShapes.size():
			gpShapes.append(gpGraph.gpShapes[gpIdx])
	if gpShapes.is_empty():
		return
	gpMakeSymbolRequested.emit(_gpShapesToDraft(gpShapes))




# Move every selected node by the drag delta measured since drag start.
# 按拖拽开始以来测得的位移量移动所有选中节点。
# Replaying from captured origins (instead of accumulating per-frame deltas) keeps the group
# rigid and free of rounding drift.
# 由记下的原始位置重放（而非逐帧累加增量）可保持整组刚性且无舍入漂移。
func _gpOnDragMove(gpScreen: Vector2) -> void:
	var gpDelta: Vector2 = gpWorldFromScreen(gpScreen) - _gpDragStartWorld
	for gpId in _gpDragOrigins.keys():
		var gpN: GPPIDNode = gpGraph.gpGetNode(gpId)
		if gpN == null:
			continue
		gpN.gpPosition = (_gpDragOrigins[gpId] as Vector2) + gpDelta
		var gpV: GPSymbolView = gpBinder.gpGetSymbolView(gpId)
		if gpV != null:
			gpV.gpUpdateTransform()
	# Edge views depend on node positions, so redraw them too.
	# 边视图依赖节点位置，因此也重绘它们。
	_gpRefreshEdges()
	queue_redraw()
	_gpEmitStatus()


# Apply the finished marquee to the selection set.
# 把完成的框选应用到选择集。
func _gpCommitMarquee() -> void:
	var gpA: Vector2 = gpWorldFromScreen(_gpMarqueeFrom)
	var gpB: Vector2 = gpWorldFromScreen(_gpMarqueeTo)
	var gpRect: Rect2 = Rect2(gpA.min(gpB), (gpA - gpB).abs())
	# Left -> right is WINDOW (enclose); right -> left is CROSSING (touch). See _gpDrawMarquee.
	# 左→右为窗口（完全包含）；右→左为交叉（碰到即可）。见 _gpDrawMarquee。
	var gpEnclose: bool = gpB.x >= gpA.x
	var gpPicked: Array[String] = []
	for gpN in gpGraph.gpNodes:
		var gpR: Rect2 = _gpNodeRect(gpN.gpInstanceId)
		var gpIn: bool = gpRect.encloses(gpR) if gpEnclose else gpRect.intersects(gpR)
		if gpIn:
			gpPicked.append(gpN.gpInstanceId)
	# Annotation shapes are selected by the same marquee (Window/Crossing) rule.
	# 注释图形按相同的框选（包含/相交）规则被选中。
	var gpShapePicked: Array[int] = []
	for gpI in range(gpGraph.gpShapes.size()):
		var gpBBox: Rect2 = gpGraph.gpShapes[gpI].gpBBox()
		var gpInS: bool = gpRect.encloses(gpBBox) if gpEnclose else gpRect.intersects(gpBBox)
		if gpInS:
			gpShapePicked.append(gpI)
	if _gpMarqueeAdd:
		for gpId in gpPicked:
			if not gpSelection.has(gpId):
				gpSelection.append(gpId)
		_gpSetSelection(gpSelection)
		for gpI in gpShapePicked:
			if not gpShapeSel.has(gpI):
				gpShapeSel.append(gpI)
	else:
		_gpSetSelection(gpPicked)
		gpShapeSel = gpShapePicked
	queue_redraw()


# ============================ selection ============================
# ============================ 选择 ============================
# Replace the selection set and keep gpSelectedId (the primary entry) in sync.
# 替换选择集，并同步 gpSelectedId（主选项）。
func _gpSetSelection(gpIds: Array[String]) -> void:
	gpSelection = gpIds.duplicate()
	gpSelectedId = gpSelection[0] if not gpSelection.is_empty() else ""
	queue_redraw()
	_gpEmitStatus()


# Select every node on the sheet (Ctrl/Cmd+A).
# 选中图纸上的所有节点（Ctrl/Cmd+A）。
func _gpSelectAll() -> void:
	if gpGraph == null:
		return
	var gpAll: Array[String] = []
	for gpN in gpGraph.gpNodes:
		gpAll.append(gpN.gpInstanceId)
	_gpSetSelection(gpAll)


# Delete every selected node together with the edges attached to it.
# 删除所有选中节点及其附着的连线。
func _gpDeleteSelected() -> void:
	if gpGraph == null:
		return
	# Remove selected annotation shapes (descending index so earlier ones stay valid).
	# 删除选中的注释图形（按下标降序，使较低下标保持有效）。
	if not gpShapeSel.is_empty():
		var gpIdxs: Array[int] = gpShapeSel.duplicate()
		gpIdxs.sort()
		gpIdxs.reverse()
		for gpI in gpIdxs:
			if gpI >= 0 and gpI < gpGraph.gpShapes.size():
				gpGraph.gpShapes.remove_at(gpI)
		gpShapeSel.clear()
	if not gpSelection.is_empty():
		for gpId in gpSelection:
			gpGraph.gpRemoveNodeWithEdges(gpId)
		_gpSetSelection([])
	queue_redraw()
	gpGraphChanged.emit()


# Copy every selected node to a small offset, keeping its attributes and orientation.
# 把所有选中节点复制到小幅偏移处，保留其属性与朝向。
func _gpDuplicateSelected() -> void:
	if gpGraph == null or gpSelection.is_empty():
		return
	var gpCopies: Array[String] = []
	for gpId in gpSelection:
		var gpN: GPPIDNode = gpGraph.gpGetNode(gpId)
		if gpN == null:
			continue
		var gpNid: String = "n%d" % gpNextId
		gpNextId += 1
		var gpCopy: GPPIDNode = gpGraph.gpNewNode(
			gpNid, gpN.gpSymbolId, gpN.gpTag,
			gpN.gpPosition + Vector2(24.0, 24.0),
			gpN.gpAttrValues.duplicate(true))
		gpCopy.gpRotationDeg = gpN.gpRotationDeg
		gpCopy.gpFlipped = gpN.gpFlipped
		gpGraph.gpAddNode(gpCopy)
		gpCopies.append(gpNid)
	# Select the copies, not the originals: the natural next action is to drag them into place.
	# 选中副本而非原件：下一步自然是把它们拖到目标位置。
	_gpSetSelection(gpCopies)
	queue_redraw()
	gpGraphChanged.emit()


# ============================ keyboard ============================
# ============================ 键盘 ============================
# Handle a keyboard shortcut. Returns true when the event was consumed.
# 处理键盘快捷键。事件被消费时返回 true。
func _gpOnKey(gpKey: InputEventKey) -> bool:
	var gpCtrl: bool = gpKey.ctrl_pressed or gpKey.meta_pressed
	match gpKey.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			_gpDeleteSelected()
			return true
		KEY_A:
			if gpCtrl:
				_gpSelectAll()
				return true
		KEY_ESCAPE:
			_gpOnEscape()
			return true
	return false


# Progressive ESC: cancel the innermost pending action first, and only clear the selection
# when nothing else is pending. Returning early is what keeps a half-drawn state recoverable.
# 渐进式 ESC：先取消最内层的待处理动作，只有在别无待处理项时才清空选择。提前返回正是
# 让半完成状态可回退的原因。
func _gpOnEscape() -> void:
	if gpPendingDef != null:
		gpPendingDef = null
		queue_redraw()
		return
	if _gpDrawActive:
		_gpDrawActive = false
		queue_redraw()
		return
	if not _gpPolyPts.is_empty():
		# Cancel the half-drawn polyline (do not commit); start fresh next click.
		# 取消半截折线（不提交）；下次点击从头开始。
		_gpPolyPts.clear()
		queue_redraw()
		return
	if not _gpGripDrag.is_empty():
		_gpGripDrag.clear()
		queue_redraw()
		return
	if _gpShapeDragIdx >= 0:
		_gpShapeDragIdx = -1
		_gpShapeDragOrigPts = PackedVector2Array()
		_gpShapeDragOrigR = 0.0
		queue_redraw()
		return
	if _gpMarqueeing:
		_gpMarqueeing = false
		queue_redraw()
		return
	if gpConnectFrom != "":
		gpConnectFrom = ""
		queue_redraw()
		return
	if not gpSelection.is_empty() or not gpShapeSel.is_empty():
		_gpSetSelection([])
		gpShapeSel.clear()


# ============================ context menu ============================
# ============================ 右键菜单 ============================
# Right click: make the click target the selection, then open the menu.
# 右键：让被点击的对象成为选择，随后打开菜单。
# Selecting first is what makes "delete" unambiguous — the user sees exactly what the menu
# is about to act on.
# 先选中是让「删除」无歧义的原因 —— 用户能明确看到菜单将要作用于什么。
func _gpOnRightDown(gpScreen: Vector2) -> void:
	var gpWorld: Vector2 = gpWorldFromScreen(gpScreen)
	var gpHit: String = _gpHitTest(gpWorld)
	if gpHit != "":
		if not gpSelection.has(gpHit):
			_gpSetSelection([gpHit])
		_gpCtxHit = gpHit
		_gpShowContextMenu(gpHit)
		return
	# No symbol hit: try an annotation shape instead.
	# 未命中图元：改试注释图形。
	var gpSh: int = _gpHitShape(gpWorld)
	if gpSh >= 0:
		if not gpShapeSel.has(gpSh):
			gpShapeSel = [gpSh]
			_gpSetSelection([])
		_gpCtxHit = ""
		_gpShowContextMenu("")
		return
	# Empty area: open the menu against the current selection (no new hit target).
	# 空白处：基于当前选择打开菜单（无新命中目标）。
	_gpCtxHit = ""
	_gpShowContextMenu(_gpCtxHit)


# Build and pop up the context menu at the cursor.
# 在光标处构建并弹出上下文菜单。
func _gpShowContextMenu(gpNodeHit: String) -> void:
	_gpCtxHit = gpNodeHit
	var gpMenu: PopupMenu = PopupMenu.new()
	# Empty canvas: offer to create a brand-new (blank) symbol directly — the same CREATE-mode
	# editor the toolbar "New Symbol…" button opens. Only shown when neither a node nor an
	# annotation shape is targeted, so it reads as a true "empty space" action.
	# 空白处：提供直接「创建图元」（空白新图元）——与工具栏「新建图元…」按钮打开的「新建」模式
	# 编辑器相同。仅在既不命中图元也不命中注释图形时显示，故读作纯粹的「空白处」动作。
	if gpNodeHit == "" and gpShapeSel.is_empty():
		gpMenu.add_item(I18n.gpTr("canvas.ctx_new_symbol"), GP_CTX_NEW_SYMBOL)
		gpMenu.add_separator()
	# Promote selected annotation shapes into a real symbol (only meaningful when shapes are picked).
	# 把选中的注释图形提升为真正图元（仅当选中图形时才有意义）。
	if not gpShapeSel.is_empty():
		gpMenu.add_item(I18n.gpTr("canvas.ctx_make_symbol"), GP_CTX_MAKE_SYMBOL)
	# Node-targeted actions need a node hit or an existing node selection.
	# 针对图元的动作需要命中图元或已有图元选择。
	var gpNodeCtx: bool = (gpNodeHit != "" or not gpSelection.is_empty())
	if gpNodeCtx:
		gpMenu.add_item(I18n.gpTr("canvas.ctx_edit_symbol"), GP_CTX_EDIT)
		gpMenu.add_item(I18n.gpTr("canvas.ctx_duplicate"), GP_CTX_DUPLICATE)
	# Delete applies to either shapes or nodes.
	# 删除可同时作用于图形或图元。
	var gpCanDelete: bool = gpNodeCtx or (not gpShapeSel.is_empty())
	if gpCanDelete:
		gpMenu.add_item(I18n.gpTr("canvas.ctx_delete"), GP_CTX_DELETE)
	gpMenu.add_separator()
	gpMenu.add_item(I18n.gpTr("canvas.ctx_select_all"), GP_CTX_SELECT_ALL)
	gpMenu.add_item(I18n.gpTr("canvas.ctx_deselect"), GP_CTX_DESELECT)
	gpMenu.add_separator()
	gpMenu.add_check_item(I18n.gpTr("canvas.ctx_connect_mode"), GP_CTX_CONNECT)
	# Disable by id, looked up through get_item_index: positional disabling breaks as soon as a
	# conditional item is inserted above. Items that were not added are skipped (index -1).
	# 按 id 禁用，并用 get_item_index 反查位置：一旦上方插入了条件项，按位置禁用就会错位。
	# 未添加的条目（下标 -1）直接跳过。
	if gpMenu.get_item_index(GP_CTX_EDIT) >= 0:
		gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_EDIT), gpNodeHit == "")
	if gpMenu.get_item_index(GP_CTX_DUPLICATE) >= 0:
		gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DUPLICATE), gpSelection.is_empty())
	if gpMenu.get_item_index(GP_CTX_DELETE) >= 0:
		gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DELETE), gpSelection.is_empty() and gpShapeSel.is_empty())
	gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DESELECT), gpSelection.is_empty() and gpShapeSel.is_empty())
	gpMenu.set_item_checked(gpMenu.get_item_index(GP_CTX_CONNECT), gpMode == GPMode.GP_CONNECT)
	gpMenu.id_pressed.connect(_gpOnContext)
	add_child(gpMenu)
	# Godot 4's PopupMenu/Popup exposes NO popup_at_cursor(); the only positioning entry is popup(), and
	# when popups are NOT embedded (embed_subwindows=false, the default) its .position is interpreted in
	# GLOBAL SCREEN coordinates. get_viewport().get_mouse_position() already returns the cursor in
	# WINDOW-LOCAL pixel coordinates (post-stretch), so adding the main window's screen position yields
	# the true OS-cursor screen coordinate. This is exactly the Godot-CAD reference pattern; the menu's
	# top-left anchors at the pointer and opens down-right (the convention). (2,2) nudges the cursor off.
	# Godot 4 的 PopupMenu/Popup 没有 popup_at_cursor()，仅 popup() 可定位；「非嵌入」（默认值）时其
	# .position 取「全局屏幕」坐标。get_viewport().get_mouse_position() 已返回「窗口内」像素坐标（已含
	# 拉伸缩放），叠加主窗口屏幕位置即得到 OS 光标的真实屏幕坐标——此即 Godot-CAD 参考实现的做法；菜单
	# 左上角锚定在指针、向右下展开（符合惯例）。(2,2) 微调让光标落在菜单角外侧。
	var gpMouseWin: Vector2i = get_viewport().get_mouse_position()
	gpMenu.position = Vector2i(get_window().position) + gpMouseWin + Vector2i(2, 2)
	gpMenu.popup()
	# Free the menu after it closes; a leaked PopupMenu keeps its parent alive.
	# 关闭后释放菜单；泄漏的 PopupMenu 会让其父节点无法释放。
	gpMenu.popup_hide.connect(gpMenu.queue_free)


# Dispatch a context-menu action.
# 分发右键菜单动作。
func _gpOnContext(gpId: int) -> void:
	match gpId:
		GP_CTX_NEW_SYMBOL:
			gpNewSymbolRequested.emit()
		GP_CTX_MAKE_SYMBOL:
			_gpMakeSymbolFromShapes()
		GP_CTX_EDIT:
			var gpN: GPPIDNode = gpGraph.gpGetNode(_gpCtxHit) if gpGraph != null else null
			if gpN != null:
				gpSymbolEditRequested.emit(gpN.gpSymbolId)
		GP_CTX_DUPLICATE:
			_gpDuplicateSelected()
		GP_CTX_DELETE:
			_gpDeleteSelected()
		GP_CTX_SELECT_ALL:
			_gpSelectAll()
		GP_CTX_DESELECT:
			_gpSetSelection([])
			gpShapeSel.clear()
			queue_redraw()
		GP_CTX_CONNECT:
			gpSetMode(GPMode.GP_SELECT if gpMode == GPMode.GP_CONNECT else GPMode.GP_CONNECT)
			gpConnectFrom = ""
			queue_redraw()


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


# Public: delete the current selection together with its edges (menu 编辑 / 删除).
# 公开：删除当前选择集及其关联的边（菜单「编辑 / 删除」）。
func gpDeleteSelection() -> void:
	_gpDeleteSelected()


# Public: drop the selection set (used before swapping in another graph).
# 公开：清空选择集（用于换入另一张图之前）。
func gpClearSelection() -> void:
	_gpMarqueeing = false
	_gpDragId = ""
	_gpDragOrigins.clear()
	gpShapeSel.clear()
	_gpSetSelection([])


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
