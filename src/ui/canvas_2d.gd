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
# Vertex-only actions on the selected annotation polyline (only offered when the cursor sits on
# a vertex / handle grip of a single selected polyline). Pulled out of the running 0..7 range so
# they cannot collide with the shape/node actions above.
# 仅针对折线顶点的操作（仅当光标位于「单选折线」的顶点 / 手柄抓取点上时提供）。取值避开 0..7，
# 避免与上面的图形/图元动作冲突。
const GP_CTX_SMOOTH_VERTEX: int = 12
const GP_CTX_DELETE_VERTEX: int = 13
const GP_CTX_CORNER_VERTEX: int = 14

# Grip (handle) roles for annotation-shape editing — mirrors AutoCAD grips: a selected shape
# shows small squares at its anchor / vertex points; dragging one reshapes or resizes it.
# 注释图形编辑用的锚点（手柄）角色 —— 对齐 AutoCAD 夹点：选中图形后在其锚点 / 顶点处显示小方块，
# 拖动即可重塑或缩放图形。
# Grip roles are defined once in GPShapeGripEditor (shared with the symbol editor).
# 锚点角色统一在 GPShapeGripEditor 中定义（与符号编辑器共用）。

# Interaction modes: select/move symbols, connect them with edges, or draw annotation shapes.
# 交互模式：选择/移动图元、为图元连线，或直接绘制注释图形。
# Drawing modes are appended last so the legacy SELECT/CONNECT values (0/1) stay unchanged.
# 绘图模式置于末尾，使旧的选择/连线取值（0/1）保持不变。
enum GPMode { GP_SELECT, GP_CONNECT, GP_DRAW_LINE, GP_DRAW_CIRCLE, GP_DRAW_RECT, GP_DRAW_POLYLINE, GP_DRAW_ARC }

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
# The camera is a pure pan/zoom module (GPCanvasCamera, core/) that owns the offset+zoom state
# and the world<->screen transform / zoom-at-point math. gpViewOffset / gpViewZoom below are thin
# proxy properties over it so the many direct reads in the drawing / grid / hit-test hot paths keep
# working unchanged, while the actual math lives in one headless-testable place.
# 相机是纯平移/缩放模块（GPCanvasCamera，core/），拥有 offset+zoom 状态与坐标变换/定点缩放数学。
# 下方 gpViewOffset / gpViewZoom 是其代理属性，使绘制 / 网格 / 命中测试热路径里的众多直读保持不改，
# 而真正数学收敛到一处可 headless 单测的地方。
var _gpCam: GPCanvasCamera = GPCanvasCamera.new()

# Canvas pixel offset of the world origin (0,0) — proxies the camera.
# 世界原点 (0,0) 在画布上的像素偏移 —— 代理相机。
var gpViewOffset: Vector2:
	get:
		return _gpCam.gpOffset
	set(gpV):
		_gpCam.gpOffset = gpV

# Current zoom factor (1.0 = 100%) — proxies the camera.
# 当前缩放系数（1.0 = 100%）—— 代理相机。
var gpViewZoom: float:
	get:
		return _gpCam.gpZoom
	set(gpV):
		_gpCam.gpZoom = gpV

# ---- interaction state ----
# ---- 交互状态 ----
# Current interaction mode.
# 当前交互模式。
var gpMode: int = GPMode.GP_SELECT

# Symbol definition waiting to be placed by the next left click.
# 等待下一次左键放置的图元定义。
var gpPendingDef: GPSymbolDef = null

# Authoritative selection-state owner (pure module, headless-testable). gpSelection / gpSelectedId
# below are proxy properties into _gpSel so every existing read site (binder, inspector, status,
# marquee) keeps compiling unchanged while the mutual-exclusion + primary-sync invariants live in
# the tested module. gpShapeSel (annotation shapes) stays a direct array: its in-place mutations
# are each an intentional single/multi/marquee/delete context, and proxying would silently break
# the node<->shape mutual exclusion.
# 权威选择状态源（纯模块，可 headless 单测）。下方 gpSelection / gpSelectedId 是 _gpSel 的代理属性，
# 使既有读点（绑定层/属性面板/状态栏/框选）零改动编译，而互斥 + 主选项同步不变式落在已测模块中。
# gpShapeSel（注释图形）保持直接数组：其就地变更各自是明确的单选/多选/框选/删除语境，代理会破坏节点<->图形互斥。
var _gpSel: GPCanvasSelection = GPCanvasSelection.new()

# Ids of the currently selected nodes. Proxies into _gpSel.gpNodeIds.
# 当前选中节点的 id 集合。代理到 _gpSel.gpNodeIds。
var gpSelection: Array[String]:
	get: return _gpSel.gpNodeIds
	set(gpV): _gpSel.gpSetNodes(gpV)

# Id of the currently selected node (primary entry of gpSelection, "" when none). Proxies into
# _gpSel.gpPrimaryNodeId.
# 当前选中节点的 id（gpSelection 的主选项，无选中时为空）。代理到 _gpSel.gpPrimaryNodeId。
var gpSelectedId: String:
	get: return _gpSel.gpPrimaryNodeId
	set(gpV): _gpSel.gpSetPrimary(gpV)

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

# Vertex index the right-click menu was opened on, for a single selected annotation polyline
# (only meaningful when the cursor hit one of its vertex / handle grips). -1 = none.
# 右键菜单打开时所处的「单选注释折线」顶点下标（仅当光标命中其顶点 / 手柄抓取点时才有意义）。-1 = 无。
var _gpCtxVertex: int = -1

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
	_gpCam.gpReset(size / 2.0)
	_gpApplyCamera()


# Apply gpViewOffset and gpViewZoom to the world root.
# 将 gpViewOffset 与 gpViewZoom 应用到世界根节点。
func _gpApplyCamera() -> void:
	if gpWorldRoot == null:
		return
	gpWorldRoot.position = gpViewOffset
	gpWorldRoot.scale = Vector2(gpViewZoom, gpViewZoom)


# Convert a world coordinate to a screen coordinate (delegates to GPCanvasCamera).
# 将世界坐标转换为屏幕坐标（委托 GPCanvasCamera）。
func gpScreenFromWorld(w: Vector2) -> Vector2:
	return _gpCam.gpScreenFromWorld(w)


# Convert a screen coordinate to a world coordinate (delegates to GPCanvasCamera).
# 将屏幕坐标转换为世界坐标（委托 GPCanvasCamera）。
func gpWorldFromScreen(gpS: Vector2) -> Vector2:
	return _gpCam.gpWorldFromScreen(gpS)


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
		# Double-clicking a vertex / handle grip of the single selected annotation polyline toggles
		# Bézier handles (corner <-> smooth). Intercept BEFORE the hit/move logic below so a double
		# click edits the vertex instead of starting a whole-shape move.
		# 双击「单选注释折线」的顶点 / 手柄抓取点：切换贝塞尔手柄（拐角 <-> 平滑）。须在下方命中/移动
		# 逻辑之前拦截，使双击编辑顶点而非开始整枚图形的移动。
		if gpDouble and _gpOnShapeGripDoubleClick(gpWorld):
			return
		# When a single shape is selected, try to grab one of ITS grips first. A pulled-out Bézier
		# handle end often sits OUTSIDE the polyline stroke, so testing shape-line hit first would
		# miss it and fall through to a marquee — making handles appear but not draggable. Testing the
		# grips independently (regardless of whether the cursor is on the stroke) fixes that.
		# 当单选一枚图形时，先尝试命中它自己的抓取点。拉出的贝塞尔手柄末端常位于折线墨线之外，若先按
		# 线段命中，会漏判并落入框选——造成句柄可见却拖不动。独立命中抓取点（不要求光标在线段上）可修复。
		if gpShapeSel.size() == 1:
			var gpGripAny: Dictionary = _gpHitGrip(gpWorld, gpShapeSel[0])
			if not gpGripAny.is_empty():
				_gpStartGripDrag(gpGripAny)
				return
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
	return gpMode >= GPMode.GP_DRAW_LINE and gpMode <= GPMode.GP_DRAW_ARC


# Press handler for the drawing tools. Two-point tools (line / circle / rect) anchor on press
# and commit on release; the polyline appends a vertex per click and finishes on double click.
# 绘图工具的按下处理。两点工具（直线/圆/矩形）按下锚定、松开提交；折线每次点击追加一个顶点，
# 双击结束。
func _gpOnDrawDown(gpWorld: Vector2, gpDouble: bool) -> void:
	match gpMode:
		GPMode.GP_DRAW_LINE, GPMode.GP_DRAW_CIRCLE, GPMode.GP_DRAW_RECT, GPMode.GP_DRAW_ARC:
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
		GPMode.GP_DRAW_ARC:
			# A press-drag-release defines the arc's end points; the center is their midpoint so
			# the result is the minor arc between them (half-circle when dragged straight).
			# 按下拖到松开定义弧的起止点；圆心取二者中点，故结果为二者间的劣弧（竖直拖出为半圆）。
			if _gpDrawFrom.distance_to(gpTo) >= 2.0:
				var gpCtr: Vector2 = (_gpDrawFrom + gpTo) * 0.5
				gpS = GPShape.gpArc(gpCtr, _gpDrawFrom, gpTo)
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
			var gpGrips: Array[Dictionary] = GPShapeGripEditor.gpGrips(gpGraph.gpShapes[gpSelIdx])
			var gpGs: float = 8.0
			# Vertex grips first (drawn as plain squares); handle grips get a tie-line to their
			# owning vertex drawn first so the squares sit on top of the line.
			# 先处理顶点抓取点（普通方块）；手柄抓取点先画到所属顶点的连线，使方块盖在连线上。
			for gpG in gpGrips:
				var gpP: Vector2 = gpScreenFromWorld(gpG["pos"])
				var gpRect: Rect2 = Rect2(gpP - Vector2(gpGs * 0.5, gpGs * 0.5), Vector2(gpGs, gpGs))
				if int(gpG["role"]) == GPShapeGripEditor.GP_GRIP_HANDLE_IN or int(gpG["role"]) == GPShapeGripEditor.GP_GRIP_HANDLE_OUT:
					# The handle grip is stored as a RELATIVE offset on its vertex, so the owner of the
					# tie-line is the vertex itself (gpPoints[gi]); the grip position is the handle end.
					# 手柄以「相对所属顶点的偏移」存储，故连线的所属端点就是顶点本身（gpPoints[gi]），
					# 抓取点位置则是手柄末端。
					var gpOwner: Vector2 = gpGraph.gpShapes[gpSelIdx].gpPoints[int(gpG["gi"])]
					draw_line(gpScreenFromWorld(gpOwner), gpP, Color(gpSelCol, 0.5), 1.0)
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
			# Sample the polyline (Bézier-handle aware) so pulled-out handles render as curves.
			# 沿折线采样（感知贝塞尔手柄），使拉出的手柄渲染成曲线。
			var gpSamp: PackedVector2Array = GPGeometry.gpRenderPoints(gpS, 8)
			var gpV: PackedVector2Array = PackedVector2Array()
			for gpP in gpSamp:
				gpV.append(gpScreenFromWorld(gpP))
			if gpS.gpClosed and gpV.size() >= 2:
				gpV.append(gpV[0])
			if gpV.size() >= 2:
				draw_polyline(gpV, gpInk, 2.0)
		GPShape.GPKind.GP_ARC:
			# Sample the arc through the shared renderer (gpArcSample) so it matches the painter.
			# 经共享渲染器（gpArcSample）采样圆弧，使主画布与符号绘制器表现一致。
			var gpArcPts: PackedVector2Array = GPGeometry.gpRenderPoints(gpS, 8)
			var gpArcV: PackedVector2Array = PackedVector2Array()
			for gpP in gpArcPts:
				gpArcV.append(gpScreenFromWorld(gpP))
			if gpArcV.size() >= 2:
				draw_polyline(gpArcV, gpInk, 2.0)


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
	return GPGeometry.gpShapeHit(gpWorld, gpS, gpTol)




# ============================ annotation-shape grip editing ============================
# ============================ 注释图形锚点编辑 ============================
# Grip compute / drag mutation now lives in GPShapeGripEditor; point shifts in GPGeometry.
# 锚点计算 / 拖拽改写现统一在 GPShapeGripEditor；点列平移统一在 GPGeometry。



# Return the grip under the world point (within screen-tolerant distance), or an empty dict.
# 返回世界坐标点下的锚点（在屏幕容差距离内），未命中返回空字典。
func _gpHitGrip(gpWorld: Vector2, gpShapeIdx: int) -> Dictionary:
	if gpShapeIdx < 0 or gpShapeIdx >= gpGraph.gpShapes.size():
		return {}
	var gpTol: float = 6.0 / gpViewZoom
	for gpG in GPShapeGripEditor.gpGrips(gpGraph.gpShapes[gpShapeIdx]):
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
	# Delegate the geometry mutation to the shared grip editor (same code as the symbol editor).
	# 几何改写委托给共用的锚点编辑器（与符号编辑器同一份代码）。
	GPShapeGripEditor.gpApplyGrip(gpS, _gpGripDrag, gpWorld)
	queue_redraw()
	_gpEmitStatus()

# Live-update a whole-shape move by replaying from the start snapshot.
# 由起始快照重放，实时更新整枚图形的移动。
func _gpOnShapeMove(gpWorld: Vector2) -> void:
	if _gpShapeDragIdx < 0 or _gpShapeDragIdx >= gpGraph.gpShapes.size():
		return
	var gpDelta: Vector2 = gpWorld - _gpShapeDragStart
	var gpS: GPShape = gpGraph.gpShapes[_gpShapeDragIdx]
	gpS.gpPoints = GPGeometry.gpShiftPoints(_gpShapeDragOrigPts, gpDelta)
	# Circle radius is independent of translation (stored separately in gpRadius).
	# 圆的半径与平移无关（单独存于 gpRadius）。
	queue_redraw()
	_gpEmitStatus()


# ============================ annotation-polyline vertex / Bézier-handle editing ============================
# ============================ 注释折线顶点 / 贝塞尔手柄编辑 ============================
# Mirror of the symbol editor's glyph-level vertex editing, adapted to the main canvas model
# where the selection is a list of shape indices (gpShapeSel) into gpGraph.gpShapes.
# 符号编辑器「顶点级」编辑在主画布上的镜像实现，适配主画布模型——选择集为 gpShapeSel（gpGraph.gpShapes
# 的下标列表）。


# The single selected annotation shape, or null when zero / many are selected. Returns null unless
# exactly one shape is picked, because vertex editing targets one polyline at a time.
# 单选时返回那枚注释图形；零选 / 多选返回 null。顶点编辑一次只作用于一条折线，故要求严格单选。
func _gpSingleSelectedShape() -> GPShape:
	if gpShapeSel.size() != 1:
		return null
	var gpIdx: int = gpShapeSel[0]
	if gpIdx < 0 or gpIdx >= gpGraph.gpShapes.size():
		return null
	return gpGraph.gpShapes[gpIdx]


# Whether vertex gpGi of gpShape currently has any Bézier handle pulled out.
# gpShape 的顶点 gpGi 当前是否有被拉出的贝塞尔手柄。
func _gpVertexHasHandles(gpShape: GPShape, gpGi: int) -> bool:
	if gpGi < 0 or gpGi >= gpShape.gpHandles.size():
		return false
	if gpShape.gpHandles[gpGi].size() < 2:
		return false
	return (not gpShape.gpHandles[gpGi][0].is_equal_approx(Vector2.ZERO)) or (not gpShape.gpHandles[gpGi][1].is_equal_approx(Vector2.ZERO))


# Collapse both handles of vertex gpGi back onto the vertex (making it a corner node).
# 把顶点 gpGi 的两侧手柄塌缩回顶点自身（使其成为拐角节点）。
func _gpCollapseHandles(gpShape: GPShape, gpGi: int) -> void:
	if gpShape == null or gpGi < 0 or gpGi >= gpShape.gpPoints.size():
		return
	gpShape.gpEnsureHandles()
	gpShape.gpHandles[gpGi] = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	queue_redraw()
	gpGraphChanged.emit()
	_gpEmitStatus()


# Pull BOTH Bézier handles out of vertex gpGi (AutoCAD-style "convert to smooth node"). The handles
# are seeded along the average direction of the neighbouring vertices so the curve appears at once.
# 从顶点 gpGi 拉出两侧贝塞尔手柄（AutoCAD 风格「转为平滑节点」）。手柄沿相邻顶点的平均方向初始化，
# 使曲线立即显现。
func _gpPullHandles(gpShape: GPShape, gpGi: int) -> void:
	if gpShape == null or (gpShape.gpKind != GPShape.GPKind.GP_POLYLINE and gpShape.gpKind != GPShape.GPKind.GP_LINE):
		return
	if gpGi < 0 or gpGi >= gpShape.gpPoints.size():
		return
	gpShape.gpEnsureHandles()
	var gpN: int = gpShape.gpPoints.size()
	var gpPrev: Vector2 = gpShape.gpPoints[gpGi]
	var gpNext: Vector2 = gpShape.gpPoints[gpGi]
	if gpGi > 0:
		gpPrev = gpShape.gpPoints[gpGi - 1]
	elif gpShape.gpClosed and gpN >= 2:
		gpPrev = gpShape.gpPoints[gpN - 1]
	if gpGi + 1 < gpN:
		gpNext = gpShape.gpPoints[gpGi + 1]
	elif gpShape.gpClosed and gpN >= 2:
		gpNext = gpShape.gpPoints[0]
	var gpHere: Vector2 = gpShape.gpPoints[gpGi]
	var gpDir: Vector2 = gpNext - gpPrev
	if gpDir.length_squared() < 1e-6:
		gpDir = Vector2(1.0, 0.0)
	gpDir = gpDir.normalized()
	var gpK: float = 0.3 * (gpNext - gpPrev).length()
	if gpK < 8.0:
		gpK = 8.0
	gpShape.gpSetHandle(gpGi, 0, gpHere - gpDir * gpK)
	gpShape.gpSetHandle(gpGi, 1, gpHere + gpDir * gpK)
	queue_redraw()
	gpGraphChanged.emit()
	_gpEmitStatus()


# Delete vertex gpGi of the selected polyline. When only two vertices remain, deleting one would
# leave a single, non-drawable point — so we delete the whole polyline instead.
# 删除选中折线的顶点 gpGi。当只剩两个顶点时，删除其一将留下无法绘制的单点，故改为删除整条折线。
func _gpRemoveVertex(gpShape: GPShape, gpGi: int) -> void:
	if gpShape == null or (gpShape.gpKind != GPShape.GPKind.GP_POLYLINE and gpShape.gpKind != GPShape.GPKind.GP_LINE):
		return
	if gpShape.gpPoints.size() <= 2:
		_gpDeleteSelected()
		return
	gpShape.gpRemoveVertex(gpGi)
	queue_redraw()
	gpGraphChanged.emit()
	_gpEmitStatus()


# Double-click a grip of the single selected annotation polyline: toggle that vertex between a
# corner node (handles collapsed) and a smooth node (handles pulled out). Double-clicking a handle
# grip collapses it. Returns true when the gesture was consumed.
# 双击「单选注释折线」的一个抓取点：在拐角（手柄塌缩）与平滑（手柄拉出）间切换。双击手柄抓取点则塌缩。
# 手势被消费时返回 true。
func _gpOnShapeGripDoubleClick(gpWorld: Vector2) -> bool:
	var gpShape: GPShape = _gpSingleSelectedShape()
	if gpShape == null or (gpShape.gpKind != GPShape.GPKind.GP_POLYLINE and gpShape.gpKind != GPShape.GPKind.GP_LINE):
		return false
	var gpGrip: Dictionary = _gpHitGrip(gpWorld, gpShapeSel[0])
	if gpGrip.is_empty():
		return false
	var gpRole: int = int(gpGrip["role"])
	var gpGi: int = int(gpGrip["gi"])
	if gpRole == GPShapeGripEditor.GP_GRIP_VERTEX:
		if _gpVertexHasHandles(gpShape, gpGi):
			_gpCollapseHandles(gpShape, gpGi)
		else:
			_gpPullHandles(gpShape, gpGi)
		return true
	if gpRole == GPShapeGripEditor.GP_GRIP_HANDLE_IN or gpRole == GPShapeGripEditor.GP_GRIP_HANDLE_OUT:
		_gpCollapseHandles(gpShape, gpGi)
		return true
	return false


# The vertex grip (as a grip dict) under gpWorld for the single selected annotation polyline, or an
# empty dict. Used by the right-click menu to offer vertex-only actions when the cursor sits on a
# vertex grip of that polyline.
# gpWorld 下「单选注释折线」的顶点抓取点（以抓取点字典形式），未命中返回空字典。右键菜单据此在光标
# 位于折线顶点抓取点上时提供仅针对顶点的操作。
func _gpHitPolylineVertexGrip(gpWorld: Vector2) -> Dictionary:
	var gpShape: GPShape = _gpSingleSelectedShape()
	if gpShape == null or (gpShape.gpKind != GPShape.GPKind.GP_POLYLINE and gpShape.gpKind != GPShape.GPKind.GP_LINE):
		return {}
	var gpGrip: Dictionary = _gpHitGrip(gpWorld, gpShapeSel[0])
	if gpGrip.is_empty():
		return {}
	if int(gpGrip["role"]) != GPShapeGripEditor.GP_GRIP_VERTEX:
		return {}
	return gpGrip


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
						# Carry Bézier handles (relative offsets) so a curved spline survives promotion.
						# Relative offsets are translation-invariant, so -gpMin does not affect them.
						# 携带贝塞尔手柄（相对偏移），使曲线样条经提升后仍可继续编辑；相对偏移与平移无关。
						"handles": GPShapeSpec.gpEmitHandles(gpS),
					})
			GPShape.GPKind.GP_POLYLINE:
				var gpPts: Array = []
				for gpP in gpS.gpPoints:
					gpPts.append([gpP.x - gpMin.x, gpP.y - gpMin.y])
				var gpPathD: Dictionary = {"pts": gpPts, "closed": gpS.gpClosed}
				# Preserve Bézier handles so a curved polyline is not flattened on promotion.
				# 保留贝塞尔手柄，避免曲线折线在提升时被展平。
				gpPathD["handles"] = GPShapeSpec.gpEmitHandles(gpS)
				gpPaths.append(gpPathD)
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
		KEY_ENTER, KEY_KP_ENTER:
			# Confirm the in-progress polyline (Enter is the discoverable confirm key; double
			# click also works). No-op when fewer than two vertices exist yet.
			# 确认正在绘制的折线（Enter 是直观的确认键；双击亦可用）。顶点不足 2 个时为空操作。
			if not _gpPolyPts.is_empty():
				_gpFinishPolyline()
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
	_gpCtxVertex = -1
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
		# Remember which vertex of a single selected polyline was right-clicked so the menu can offer
		# vertex-only actions (smooth / corner / delete this vertex). Right-click on the empty inside
		# of the polyline leaves _gpCtxVertex = -1 (the shape-level menu shows instead).
		# 记住「单选折线」被右键点击的是哪个顶点，使菜单能提供仅针对顶点的操作（平滑 / 拐角 / 删除此顶点）。
		# 右键点在折线内部空白处时 _gpCtxVertex 保持 -1（显示图形级菜单）。
		var gpVGrip: Dictionary = _gpHitPolylineVertexGrip(gpWorld)
		if not gpVGrip.is_empty():
			_gpCtxVertex = int(gpVGrip["gi"])
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
	# Promote selected annotation shapes into a real symbol (only meaningful when shapes are picked).
	# 把选中的注释图形提升为真正图元（仅当选中图形时才有意义）。
	if not gpShapeSel.is_empty():
		gpMenu.add_item(I18n.gpTr("canvas.ctx_make_symbol"), GP_CTX_MAKE_SYMBOL)
	# Vertex-only actions on the right-clicked vertex of a single selected polyline (Bézier handles).
	# 对「单选折线」被右键顶点的顶点级操作（贝塞尔手柄）。镜像符号编辑器：平滑 = 拉手柄、拐角 = 收手柄。
	if _gpCtxVertex >= 0:
		var gpSelShape: GPShape = _gpSingleSelectedShape()
		if gpSelShape != null and _gpVertexHasHandles(gpSelShape, _gpCtxVertex):
			gpMenu.add_item(I18n.gpTr("canvas.ctx_corner_vertex"), GP_CTX_CORNER_VERTEX)
		else:
			gpMenu.add_item(I18n.gpTr("canvas.ctx_smooth_vertex"), GP_CTX_SMOOTH_VERTEX)
		gpMenu.add_item(I18n.gpTr("canvas.ctx_delete_vertex"), GP_CTX_DELETE_VERTEX)
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
	# Popup positioning is centralized in GPPopupHelper.gpPopupAtMouse (single source of truth for the
	# window-screen formula that was previously duplicated and error-prone across three call sites).
	# 菜单定位统一交由 GPPopupHelper.gpPopupAtMouse（窗口屏幕坐标公式的单一事实来源，此前在三处重复且易错）。
	GPPopupHelper.gpPopupAtMouse(gpMenu, self)
	# Free the menu after it closes; a leaked PopupMenu keeps its parent alive.
	# 关闭后释放菜单；泄漏的 PopupMenu 会让其父节点无法释放。
	gpMenu.popup_hide.connect(gpMenu.queue_free)


# Dispatch a context-menu action.
# 分发右键菜单动作。
func _gpOnContext(gpId: int) -> void:
	match gpId:
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
		GP_CTX_SMOOTH_VERTEX:
			# Pull handles out of the right-clicked vertex (make it smooth). Only valid when a single
			# polyline is selected and that vertex was the right-click target.
			# 拉出被右键顶点的两侧手柄（转为平滑）。仅当单选折线且该顶点正是右键目标时有效。
			var gpSmoothShape: GPShape = _gpSingleSelectedShape()
			if gpSmoothShape != null and _gpCtxVertex >= 0:
				_gpPullHandles(gpSmoothShape, _gpCtxVertex)
			_gpCtxVertex = -1
		GP_CTX_CORNER_VERTEX:
			# Collapse the handles of the right-clicked vertex back onto it (make it a corner).
			# 收起被右键顶点的两侧手柄（转为拐角）。
			var gpCornerShape: GPShape = _gpSingleSelectedShape()
			if gpCornerShape != null and _gpCtxVertex >= 0:
				_gpCollapseHandles(gpCornerShape, _gpCtxVertex)
			_gpCtxVertex = -1
		GP_CTX_DELETE_VERTEX:
			# Remove just the right-clicked vertex, keeping the rest of the polyline connected.
			# 仅删除被右键的顶点，折线其余部分保持连接。
			var gpDelShape: GPShape = _gpSingleSelectedShape()
			if gpDelShape != null and _gpCtxVertex >= 0:
				_gpRemoveVertex(gpDelShape, _gpCtxVertex)
			_gpCtxVertex = -1
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
	if not _gpCam.gpZoomAt(gpScreen, gpFactor):
		return
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
