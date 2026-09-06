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

# (Minimum marquee drag distance now lives on GPCanvasMarquee.GP_MIN_DRAG, next to the
# window/crossing rule it belongs with.)
# （框选最小拖拽距离现位于 GPCanvasMarquee.GP_MIN_DRAG，与它所属的窗口/交叉规则放在一起。）


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
#
# The enum itself now lives on GPCanvasInteractState (core/view) so the P2 tool layer can receive
# it without importing this Control. This alias keeps the public `GPCanvas2D.GPMode.GP_*`
# spelling used by the shell compiling unchanged.
# 枚举现定义于 GPCanvasInteractState（core/view），使 P2 工具层无需引入本 Control 即可使用。
# 本别名保持外壳所用的 `GPCanvas2D.GPMode.GP_*` 写法继续编译通过。
const GPMode = GPCanvasInteractState.GPMode

# Set the interaction mode and notify listeners (the toolbar) so highlights stay correct.
# 设置交互模式并通知监听者（工具栏），使高亮保持正确。
func gpSetMode(gpM: int) -> void:
	# The mode switch itself (including "entering a drawing tool clears the node selection") is a
	# state invariant owned by GPCanvasInteractState; this shell only re-emits and repaints.
	# 模式切换本身（含「进入绘图工具清空节点选择」）是 GPCanvasInteractState 持有的状态不变式；
	# 本外壳只负责转发信号与重绘。
	if not _gpState.gpSetMode(gpM):
		return
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

# ---- shared interaction state ----
# ---- 共享交互状态 ----
# Composition root for everything the canvas remembers between events: camera, selection,
# marquee, id counter, mode and the pending symbol. Grouping them under one RefCounted is what
# lets P2 hand "the canvas state" to a tool object without leaking this Control.
# 画布在事件之间所记住的一切的组合根：相机、选择集、框选、id 计数器、模式与待放置图元。
# 把它们归拢到一个 RefCounted 之下，正是 P2 能把「画布状态」交给工具对象而不泄漏本 Control 的前提。
var _gpState: GPCanvasInteractState = GPCanvasInteractState.new()

# Drawing delegate (P2 split): owns the background overlay paint, reads live state from this
# canvas. Created in _ready() once the canvas is a valid CanvasItem.
# 绘制委托（P2 拆分）：持有背景覆盖层绘制逻辑，从本画布读取实时状态。在 _ready() 中创建。
var _gpOverlay: GPCanvasOverlay = null

# Annotation-shape editing delegate (P2 split): grip / whole-shape / vertex / Bézier editing and
# "promote shapes to symbol". Created in _ready() with this canvas as its state owner.
# 注释图形编辑委托（P2 拆分）：锚点 / 整图形 / 顶点 / 贝塞尔编辑与「提升为图元」。在 _ready() 中
# 以本画布作为状态持有者创建。
var _gpAnno: GPAnnotationEditor = null

# Right-click context-menu delegate (P2 split): hit-test / menu build / action dispatch, plus the
# menu's hit state (_gpCtxHit / _gpCtxVertex, now owned by GPCanvasContextMenu). Created in _ready()
# with this canvas as its state owner.
# 右键上下文菜单委托（P2 拆分）：命中判定 / 菜单构建 / 动作分发，以及菜单命中状态（现由
# GPCanvasContextMenu 持有）。在 _ready() 中以本画布作为状态持有者创建。
var _gpCtx: GPCanvasContextMenu = null

# Canvas interaction tools (P2 split): one RefCounted delegate per interaction mode, dispatched
# through _gpRegistry by GPMode. Each tool reads/writes live canvas state via gpCtx.gpCv; the canvas
# keeps all transient drag state + orchestration. See docs/架构优化方案 §5.
# 画布交互工具（P2 拆分）：每种交互模式一个 RefCounted 委托，经 _gpRegistry 按 GPMode 分派。
# 各工具经 gpCtx.gpCv 读写画布实时状态；画布保留全部瞬态拖拽状态与编排逻辑。见 docs/架构优化方案 §5。
var _gpToolCtx: GPCanvasToolContext = null
var _gpRegistry: GPCanvasToolRegistry = null
var _gpSelectTool: GPSelectTool = null
var _gpPlaceTool: GPPlaceTool = null
var _gpDrawTool: GPDrawShapeTool = null
var _gpGripTool: GPGripTool = null

# Monotonically increasing id counter for new nodes and edges — proxies GPIdGen via the state.
# 新节点与新边的单调递增 id 计数器 —— 经状态对象代理 GPIdGen。
var gpNextId: int:
	get: return _gpState.gpIds.gpCounter
	set(gpV): _gpState.gpIds.gpCounter = gpV

# ---- world root ----
# ---- 世界根节点 ----
# Node2D that holds all symbol/edge view nodes and carries the camera transform.
# 承载所有图元/连线视图节点并承载相机变换的 Node2D。
var gpWorldRoot: Node2D = null

# ---- camera ----
# ---- 相机 ----
# The camera is a pure pan/zoom module (GPCanvasCamera, core/) that owns the offset+zoom state
# and the world<->screen transform / zoom-at-point math. gpViewOffset / gpViewZoom below are thin
# ...but it is now owned by GPCanvasInteractState and exposed here as a read-only proxy, so the
# many direct reads in the drawing / grid / hit-test hot paths keep working unchanged while the
# math stays in one headless-testable place.
# 相机是纯平移/缩放模块（GPCanvasCamera，core/），拥有 offset+zoom 状态与坐标变换/定点缩放数学；
# 现由 GPCanvasInteractState 持有并在此以只读代理暴露，使绘制 / 网格 / 命中测试热路径里的众多
# 直读保持不改，而数学收敛到一处可 headless 单测的地方。
var _gpCam: GPCanvasCamera:
	get: return _gpState.gpCam

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

# ---- interaction state (mode / pending symbol) ----
# ---- 交互状态（模式 / 待放置图元） ----
# Current interaction mode. Proxies GPCanvasInteractState so the mode has one owner even though
# ~20 call sites read it as a plain field.
# 当前交互模式。代理到 GPCanvasInteractState，使模式即便被约 20 处当作普通字段读取也只有一个持有者。
var gpMode: int:
	get: return _gpState.gpMode
	set(gpV): _gpState.gpMode = gpV

# Symbol definition waiting to be placed by the next left click.
# 等待下一次左键放置的图元定义。
var gpPendingDef: GPSymbolDef:
	get: return _gpState.gpPendingDef
	set(gpV): _gpState.gpPendingDef = gpV

# Authoritative selection-state owner (pure module, headless-testable), now reached through
# GPCanvasInteractState. gpSelection / gpSelectedId below are proxy properties into it so every
# existing read site (binder, inspector, status, marquee) keeps compiling unchanged while the
# mutual-exclusion + primary-sync invariants live in the tested module. gpShapeSel (annotation
# shapes) stays a direct array: its in-place mutations are each an intentional single/multi/
# marquee/delete context, and proxying would silently break the node<->shape mutual exclusion.
# 权威选择状态源（纯模块，可 headless 单测），现经 GPCanvasInteractState 访问。下方 gpSelection /
# gpSelectedId 是它的代理属性，使既有读点（绑定层/属性面板/状态栏/框选）零改动编译，而互斥 +
# 主选项同步不变式落在已测模块中。gpShapeSel（注释图形）保持直接数组：其就地变更各自是明确的
# 单选/多选/框选/删除语境，代理会破坏节点<->图形互斥。
var _gpSel: GPCanvasSelection:
	get: return _gpState.gpSel

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

# The rubber-band marquee (active flag, endpoints in SCREEN space, additive flag) is owned by
# GPCanvasMarquee via the state; the window/crossing rule lives there too, so the drawer and the
# commit path can never disagree about which one they applied.
# 橡皮筋框选（进行中标记、屏幕空间端点、追加标记）经状态对象由 GPCanvasMarquee 持有；
# 窗口 / 交叉规则也在其中，使绘制路径与提交路径永不会在「应用了哪条规则」上分歧。
var _gpMarq: GPCanvasMarquee:
	get: return _gpState.gpMarquee

# World position where the current multi-node drag started.
# 当前多节点拖拽开始时的世界坐标。
var _gpDragStartWorld: Vector2 = Vector2.ZERO

# Original world position of every dragged node, captured once at drag start. Replaying from
# these (instead of accumulating per-frame deltas) keeps the group from drifting.
# 每个被拖拽节点的原始世界坐标，在拖拽开始时一次性记下。由这些原始值重放（而非逐帧累加
# 增量）可避免整组漂移。
var _gpDragOrigins: Dictionary = {}


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
	# Create the drawing delegate (P2 split). It borrows this Control as its CanvasItem.
	# 创建绘制委托（P2 拆分）。它以本 Control 作为绘制目标 CanvasItem。
	_gpOverlay = GPCanvasOverlay.new(self)
	# Create the annotation-shape editing delegate (P2 split), owner = this canvas.
	# 创建注释图形编辑委托（P2 拆分），状态持有者为本画布。
	_gpAnno = GPAnnotationEditor.new(self)
	# Create the right-click context-menu delegate (P2 split), owner = this canvas.
	# 创建右键上下文菜单委托（P2 拆分），状态持有者为本画布。
	_gpCtx = GPCanvasContextMenu.new(self)
	# Create the interaction-tool registry and the four mode tools (P2 split). The context wraps
	# this canvas; every tool reads/writes live state through it. CONNECT shares the select tool.
	# 创建交互工具注册表与四种模式工具（P2 拆分）。上下文封装本画布，各工具经其读写实时状态；
	# 连线模式复用选择工具。
	_gpToolCtx = GPCanvasToolContext.new(self)
	_gpRegistry = GPCanvasToolRegistry.new()
	_gpSelectTool = GPSelectTool.new()
	_gpPlaceTool = GPPlaceTool.new()
	_gpDrawTool = GPDrawShapeTool.new()
	_gpGripTool = GPGripTool.new()
	for gpT in [_gpSelectTool, _gpPlaceTool, _gpDrawTool, _gpGripTool]:
		gpT.gpCtx = _gpToolCtx
	_gpRegistry.gpRegister(GPMode.GP_SELECT, _gpSelectTool)
	_gpRegistry.gpRegister(GPMode.GP_CONNECT, _gpSelectTool)
	_gpRegistry.gpRegister(GPMode.GP_DRAW_LINE, _gpDrawTool)
	_gpRegistry.gpRegister(GPMode.GP_DRAW_CIRCLE, _gpDrawTool)
	_gpRegistry.gpRegister(GPMode.GP_DRAW_RECT, _gpDrawTool)
	_gpRegistry.gpRegister(GPMode.GP_DRAW_POLYLINE, _gpDrawTool)
	_gpRegistry.gpRegister(GPMode.GP_DRAW_ARC, _gpDrawTool)
	# Subscribe to language and font changes so symbol labels stay in sync.
	# 订阅语言与字体变化，保持图元文字同步。
	# Headless-resilient guard: `I18n` / `Settings` are autoloads and are NOT present when the
	# canvas is exercised outside the live app (e.g. `--script` regression checkers). Skip the
	# connection when the singleton is absent — the real app always has them, so behavior is
	# identical there. This is what lets the P2 tool layer be validated headlessly without a GUI.
	# 无界面容错护栏：I18n / Settings 是自动加载单例，在画布脱离活动现场运行（如 `--script` 回归检查
	# 器）时并不存在。单例缺失时跳过连接——真实应用永远具备它们，故行为零变更。正是这一步让 P2 工具
	# 层可在无 GUI 环境下 headless 校验。
	var _gpI18n: Object = get_node_or_null("/root/I18n")
	if _gpI18n != null and _gpI18n.has_signal("gpLocaleChanged"):
		_gpI18n.gpLocaleChanged.connect(_gpOnLocaleChanged)
	var _gpSettings: Object = get_node_or_null("/root/Settings")
	if _gpSettings != null and _gpSettings.has_signal("gpSymbolStyleChanged"):
		_gpSettings.gpSymbolStyleChanged.connect(_gpOnSymbolStyleChanged)
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
	# The background overlay paint is delegated to GPCanvasOverlay (P2 split) — same math,
	# same draw order, so the visual result is byte-for-byte identical.
	# 背景覆盖层绘制委托给 GPCanvasOverlay（P2 拆分）——同一套数学、同一绘制顺序，观感完全一致。
	_gpOverlay.gpDraw()


# The background overlay paint (grid / shapes / grips / marquee / connect-preview) now lives in
# GPCanvasOverlay — this Control only triggers _gpSyncViews() then delegates to it in _draw().
# 背景覆盖层绘制（网格 / 图形 / 抓取点 / 框选 / 连线预览）现位于 GPCanvasOverlay——
# 本 Control 仅先触发 _gpSyncViews() 再在 _draw() 中委托给它。


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
				_gpCtx.gpOnRightDown(gpMouseEvent.position)
			accept_event()
			return

	# Keyboard shortcuts (Delete / Ctrl+A / ESC).
	# 键盘快捷键（Delete / Ctrl+A / ESC）。
	if gpEvent is InputEventKey:
		var gpKey: InputEventKey = gpEvent as InputEventKey
		if gpKey.pressed and not gpKey.echo:
			# The active tool gets first crack (e.g. Enter confirms a polyline); the canvas then
			# handles the shared shortcuts (Delete / Ctrl+A / ESC).
			# 活动工具优先处理（如 Enter 确认折线）；随后画布处理共享快捷键（Delete / Ctrl+A / ESC）。
			if _gpActiveTool().gpOnKey(gpKey):
				accept_event()
				return
			if _gpOnKey(gpKey):
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
		if _gpMarq.gpActive:
			_gpMarq.gpUpdate(gpMotion.position)
			queue_redraw()
			accept_event()
			return
		# Dragging the whole selection.
		# 正在拖拽整个选择集。
		if _gpDragId != "":
			_gpOnDragMove(gpMotion.position)
			accept_event()
			return
		# Grip / whole-shape drag is owned by GPGripTool (P2 split).
		# 锚点 / 整图形拖拽由 GPGripTool 负责（P2 拆分）。
		if not _gpGripDrag.is_empty() or _gpShapeDragIdx >= 0:
			_gpGripTool.gpOnMove(gpWorldFromScreen(gpMotion.position))
			accept_event()
			return
		# Tool-specific rubber band / connect preview (select = connect preview, draw = rubber band).
		# The tool returns true when it consumed the motion (e.g. rubber band) so we accept it.
		# 工具专属橡皮筋 / 连接预览（select=连接预览，draw=橡皮筋）。工具消费了移动事件时返回
		# true，画布据此 accept_event()。
		if _gpActiveTool().gpOnMove(gpWorldFromScreen(gpMotion.position)):
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
	_gpActiveTool().gpOnPress(gpWorldFromScreen(gpScreen), gpShift, gpDouble)


# Return the interaction tool for the current dispatch target: a pending palette placement wins
# over the mode; otherwise the registry maps GPMode -> tool (CONNECT shares the select tool). The
# canvas keeps all transient drag state; tools read/write it through gpCtx.gpCv.
# 返回当前分派目标的交互工具：调色板待放置优先于模式；否则注册表按 GPMode 映射（CONNECT 复用
# 选择工具）。画布保留全部瞬态拖拽状态，工具经 gpCtx.gpCv 读写。
func _gpActiveTool() -> GPCanvasTool:
	if gpPendingDef != null:
		return _gpPlaceTool
	return _gpRegistry.gpGet(gpMode)

func _gpOnLeftUp(gpScreen: Vector2) -> void:
	var gpWorld: Vector2 = gpWorldFromScreen(gpScreen)
	# Grip / whole-shape drag belongs to GPGripTool (P2 split).
	# 锚点 / 整图形拖拽由 GPGripTool 负责（P2 拆分）。
	if not _gpGripDrag.is_empty() or _gpShapeDragIdx >= 0:
		_gpGripTool.gpOnRelease(gpWorld)
		return
	# Everything else (draw commit / marquee / group drag) is dispatched to the active tool.
	# 其余（提交绘图 / 框选 / 整组拖拽）分派给活动工具。
	_gpActiveTool().gpOnRelease(gpWorld)

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


# _gpDrawShapes / _gpDrawOneShape moved to GPCanvasOverlay (P2 split). They are invoked through
# _gpOverlay.gpDraw() from _draw(), so the canvas no longer paints the overlay itself.
# _gpDrawShapes / _gpDrawOneShape 已移至 GPCanvasOverlay（P2 拆分），经 _draw() 中的
# _gpOverlay.gpDraw() 调用，画布不再自行绘制覆盖层。


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





# Annotation-shape editing (grip / whole-shape / vertex / bezier / promote-to-symbol) now lives
# in GPAnnotationEditor (P2 split). The canvas delegates to it via _gpAnno (created in _ready()).
# 注释图形编辑（锚点 / 整图形 / 顶点 / 贝塞尔 / 提升为图元）现位于 GPAnnotationEditor（P2 拆分），
# 画布经 _ready() 中创建的 _gpAnno 委托给它。




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
	var gpA: Vector2 = gpWorldFromScreen(_gpMarq.gpFrom)
	var gpB: Vector2 = gpWorldFromScreen(_gpMarq.gpTo)
	var gpRect: Rect2 = Rect2(gpA.min(gpB), (gpA - gpB).abs())
	# Left -> right is WINDOW (enclose); right -> left is CROSSING (touch). Same predicate the
	# drawer used for the band colour, so what you see is what you get.
	# 左→右为窗口（完全包含）；右→左为交叉（碰到即可）。与绘制选框颜色所用的同一判据，所见即所得。
	var gpWindow: bool = _gpMarq.gpIsWindow()
	var gpPicked: Array[String] = []
	for gpN in gpGraph.gpNodes:
		if GPCanvasMarquee.gpPicks(gpWindow, gpRect, _gpNodeRect(gpN.gpInstanceId)):
			gpPicked.append(gpN.gpInstanceId)
	# Annotation shapes are selected by the same marquee (Window/Crossing) rule.
	# 注释图形按相同的框选（包含/相交）规则被选中。
	var gpShapePicked: Array[int] = []
	for gpI in range(gpGraph.gpShapes.size()):
		if GPCanvasMarquee.gpPicks(gpWindow, gpRect, gpGraph.gpShapes[gpI].gpBBox()):
			gpShapePicked.append(gpI)
	if _gpMarq.gpAdditive:
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
		var gpNid: String = _gpState.gpIds.gpNext("n")
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
	if _gpMarq.gpActive:
		_gpMarq.gpCancel()
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
	_gpMarq.gpCancel()
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
