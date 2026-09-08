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
	# M2: mode is a state broadcast like any other, so it travels on the bus as well.
	# M2：模式与其他状态广播一样，同样走总线。
	gpEvents.gpModeChanged.emit(gpMode)
	# Entering a drawing tool clears the node selection inside GPCanvasInteractState, which
	# writes the selection object directly and therefore never passes _gpSetSelection.
	# Announce it here, otherwise subscribers (inspector) keep showing a node that is no
	# longer selected — a stale-UI bug that the explicit event channel now makes visible.
	# 进入绘图工具会在 GPCanvasInteractState 内部清空节点选中，它直写选择对象、
	# 不经过 _gpSetSelection。此处补发事件，否则订阅者（属性面板）仍显示已取消选中的节点
	# —— 这个界面陈旧缺陷正是被显式事件通道暴露出来的。
	if _gpState.gpIsDrawMode():
		gpEvents.gpSelectionChanged.emit(gpSelection)
	queue_redraw()

# App-layer event channel for THIS sheet (M2). One bus per canvas: a single global bus
# would make every open sheet react to another sheet's change.
# 本图纸的应用层事件通道（M2）。每画布一条总线：全局单条会让所有图纸互相串扰。
# Since M6 the bus is OWNED by the GPAppDocumentManager (the composition root injects it via
# gpBindDocument); the canvas only borrows it. A private fallback keeps the canvas usable when
# no manager is bound yet (standalone tool tests, the construction window before bind).
# 自 M6 起总线由 GPAppDocumentManager 持有（组合根经 gpBindDocument 注入）；画布只借用。
# 私有回退使画布在无管理器绑定时仍可用（独立工具测试、绑定前的构造期）。
var _gpEventBusFallback: GPEventBus = GPEventBus.new()
var _gpDocMgr: GPAppDocumentManager = null
var gpEvents: GPEventBus:
	get:
		if _gpDocMgr != null and _gpDocMgr.gpBus != null:
			return _gpDocMgr.gpBus
		return _gpEventBusFallback

# Bind the document manager (M6). From now on the canvas forwards graph / selection / status /
# mode events onto the manager's bus, and marks the document dirty on edits.
# 绑定文档管理器（M6）。此后画布将图/选中/状态/模式事件转发到管理器的总线，并在编辑时标记脏。
func gpBindDocument(gpMgr: GPAppDocumentManager) -> void:
	_gpDocMgr = gpMgr

# Application editing service (M4 续): the canvas asks it for every user edit (delete /
# duplicate / place / connect / draw-commit / move) and gets plain values back. It owns the
# per-document command context and undo stack, so the canvas itself holds no command
# machinery — it only forwards intent and applies the view-side consequences.
# 应用编辑服务（M4 续）：画布向它请求每一项用户编辑（删除 / 复制 / 放置 / 连线 / 提交绘图 /
# 移动），只拿回普通值。它持有「每文档」的命令上下文与撤销栈，画布自身不再持有任何命令
# 机制 —— 只负责转发意图并处理视图侧后果。
# Per-sheet editing collaborator. It stays on the canvas because the canvas is the one that
# issues edit intents; the document manager (M6) owns the graph / bus / dirty state, not the service.
# 每图纸的编辑协作者。它留在画布上，因为正是画布发出编辑意图；文档管理器（M6）持有图 / 总线 /
# 脏标记状态，而非这个服务。
var gpActions: GPEditService = GPEditService.new()

# Backing field for the gpGraph property. Kept explicit so the setter cannot recurse.
# gpGraph 属性的后备字段。显式保留以避免 setter 递归。
var _gpGraphRef: GPPIDGraph

# The topology graph this canvas displays and edits.
# Assigning it (re)binds the core gpGraphChanged signal so programmatic mutations
# (add/remove node, add shape, cascade delete) reach the UI through the same channel
# as interactive ones. Before M2 that core signal was emitted 7x with zero subscribers.
# 本画布显示并编辑的拓扑图。
# 赋值时会（重新）绑定 core 的 gpGraphChanged 信号，使程序化改动（增删节点、加图形、
# 级联删除）与交互改动走同一通道。M2 之前该 core 信号发射 7 处却零订阅者。
var gpGraph: GPPIDGraph:
	get:
		return _gpGraphRef
	set(gpValue):
		_gpSetGraph(gpValue)

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

# Public port: the shared interaction state (mode / selection / camera / marquee / id counter).
# Exposed read-only so delegates and tools reach it without touching this private field.
# 公开端口：共享交互状态（模式 / 选择 / 相机 / 框选 / id 计数器）。只读暴露，使委托与工具
# 无需触碰本私有字段即可取用。
var gpState: GPCanvasInteractState:
	get: return _gpState

# Drawing delegate (P2 split): owns the background overlay paint, reads live state from this
# canvas. Created in _ready() once the canvas is a valid CanvasItem.
# 绘制委托（P2 拆分）：持有背景覆盖层绘制逻辑，从本画布读取实时状态。在 _ready() 中创建。
var _gpOverlay: GPCanvasOverlay = null

# Annotation-shape editing delegate (P2 split): grip / whole-shape / vertex / Bézier editing and
# "promote shapes to symbol". Created in _ready() with this canvas as its state owner.
# 注释图形编辑委托（P2 拆分）：锚点 / 整图形 / 顶点 / 贝塞尔编辑与「提升为图元」。在 _ready() 中
# 以本画布作为状态持有者创建。
# M3: public because it is a shared collaborator — tools (via gpCtx.gpAnno) and the context menu
# both drive it. Exposing the collaborator beats exposing the canvas internals it touches.
# M3：公开，因为它是共享协作者——工具（经 gpCtx.gpAnno）与右键菜单都要驱动它。暴露协作者优于
# 暴露它所触碰的画布内部实现。
var gpAnno: GPAnnotationEditor = null

# Right-click context-menu delegate (P2 split): hit-test / menu build / action dispatch, plus the
# menu's hit state (_gpCtxHit / _gpCtxVertex, now owned by GPCanvasContextMenu). Created in _ready()
# with this canvas as its state owner.
# 右键上下文菜单委托（P2 拆分）：命中判定 / 菜单构建 / 动作分发，以及菜单命中状态（现由
# GPCanvasContextMenu 持有）。在 _ready() 中以本画布作为状态持有者创建。
var _gpShortcuts: GPCanvasShortcuts = null
var _gpCtx: GPCanvasContextMenu = null

# Canvas interaction tools (P2 split): one RefCounted delegate per interaction mode, dispatched
# through _gpRegistry by GPMode. Each tool reads/writes live canvas state via gpCtx.gpCv; the canvas
# keeps all transient drag state + orchestration. See docs/架构优化方案 §5.
# 画布交互工具（P2 拆分）：每种交互模式一个 RefCounted 委托，经 _gpRegistry 按 GPMode 分派。
# 各工具经 gpCtx.gpCv 读写画布实时状态；瞬态拖拽状态现由工具自持，画布仅保留组合编排逻辑。见 docs/架构优化方案 §5。
var _gpToolCtx: GPCanvasToolContext = null
var _gpRegistry: GPCanvasToolRegistry = null
var _gpSelectTool: GPSelectTool = null
var _gpPlaceTool: GPPlaceTool = null
var _gpDrawTool: GPDrawShapeTool = null
var _gpGripTool: GPGripTool = null

# Id counter for new nodes/edges — proxy to state.gpIds (GPIdGen). / 新节点/边 id 计数器 —— 代理 state.gpIds。
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
# Camera proxy: math lives in GPCanvasCamera (core/view); reads stay hot-path friendly. / 相机代理：数学在 GPCanvasCamera，直读保持热路径友好。
var _gpCam: GPCanvasCamera:
	get: return _gpState.gpCam

# World-origin pixel offset — proxy to camera. / 世界原点像素偏移 —— 代理相机。
var gpViewOffset: Vector2:
	get:
		return _gpCam.gpOffset
	set(gpV):
		_gpCam.gpOffset = gpV

# Zoom factor (1.0 = 100%) — proxy to camera. / 缩放系数（1.0 = 100%）—— 代理相机。
var gpViewZoom: float:
	get:
		return _gpCam.gpZoom
	set(gpV):
		_gpCam.gpZoom = gpV

# ---- interaction state (mode / pending symbol) ----
# ---- 交互状态（模式 / 待放置图元） ----
# Interaction mode — proxy to state. / 交互模式 —— 代理 state。
var gpMode: int:
	get: return _gpState.gpMode
	set(gpV): _gpState.gpMode = gpV

# Symbol definition waiting to be placed by the next left click.
# 等待下一次左键放置的图元定义。
var gpPendingDef: GPSymbolDef:
	get: return _gpState.gpPendingDef
	set(gpV): _gpState.gpPendingDef = gpV

# Selection state owner (pure, headless-testable) reached via GPCanvasInteractState. gpSelection /
# gpSelectedId are proxies into it; gpShapeSel stays a direct array (node<->shape mutual exclusion).
# 选择状态源（纯模块，可 headless 单测）经 GPCanvasInteractState 访问。gpSelection / gpSelectedId 为
# 代理；gpShapeSel 保持直接数组（节点<->图形互斥，代理会破坏）。
var _gpSel: GPCanvasSelection:
	get: return _gpState.gpSel

# Selected node ids — proxy to selection. / 选中节点 id 集合 —— 代理选择。
var gpSelection: Array[String]:
	get: return _gpSel.gpNodeIds
	set(gpV): _gpSel.gpSetNodes(gpV)

# Primary selected node id ("" when none) — proxy to selection. / 主选项 id（无则 ""）—— 代理选择。
var gpSelectedId: String:
	get: return _gpSel.gpPrimaryNodeId
	set(gpV): _gpSel.gpSetPrimary(gpV)

# Id of the node selected as the connection source.
# 被选为连线起点的节点 id。
var gpConnectFrom: String = ""

# Rubber-band marquee (owned by GPCanvasMarquee via state): active flag + screen endpoints + rule.
# 橡皮筋框选（经状态由 GPCanvasMarquee 持有）：进行中标记 + 屏幕端点 + 窗口/交叉规则。
var gpMarq: GPCanvasMarquee:
	get: return _gpState.gpMarquee


# Whether the user is currently middle-button panning.
# 用户是否正在中键平移。
var _gpPanning: bool = false

# Mouse position where panning started.
# 开始平移时的鼠标位置。
var _gpPanStart: Vector2 = Vector2.ZERO

# View offset when panning started.
# 开始平移时的视图偏移。
var _gpPanOffsetStart: Vector2 = Vector2.ZERO


# Indices of the currently selected annotation shapes (mirror of gpSelection for the node layer).
# 当前选中注释图形的下标（与图元层的 gpSelection 对应的镜像）。
var gpShapeSel: Array[int] = []

# M3: the drawing transient state (_gpDrawFrom / _gpDrawTo / _gpDrawActive / _gpPolyPts) and the
# three drawing verbs (_gpOnDrawDown / _gpCommitDraw / _gpFinishPolyline) moved into GPDrawShapeTool,
# which now also paints its own rubber band via the gpDrawOverlay hook (declared in P2, never wired).
# M3：绘图瞬态状态（_gpDrawFrom / _gpDrawTo / _gpDrawActive / _gpPolyPts）与三个绘图动作
# （_gpOnDrawDown / _gpCommitDraw / _gpFinishPolyline）已迁入 GPDrawShapeTool；该工具现亦经
# gpDrawOverlay 钩子自绘橡皮筋（此钩子 P2 即已声明，但从未接线）。

# Last known mouse position in world coordinates.
# 最近一次鼠标在世界坐标系中的位置。
var _gpLastMouseWorld: Vector2 = Vector2.ZERO

# M3: the annotation grip / whole-shape drag state (_gpShapeDragIdx / _gpShapeDragStart /
# _gpShapeDragOrigPts / _gpShapeDragOrigR / _gpGripDrag) moved OUT of the canvas into
# GPAnnotationEditor, which is the only party that consumes it. It is reached through the
# gpIsDragging / gpStartShapeDrag / gpEnd*Drag port declared there.
# M3：注释锚点 / 整图形拖拽状态（_gpShapeDragIdx / _gpShapeDragStart / _gpShapeDragOrigPts /
# _gpShapeDragOrigR / _gpGripDrag）已迁出画布，改由 GPAnnotationEditor 持有——它是唯一消费该
# 状态的一方。外部经该文件声明的 gpIsDragging / gpStartShapeDrag / gpEnd*Drag 端口访问。
# Note: _gpShapeDragOrigR was write-only (set and cleared, never read) — circle radius does not
# change under translation — so it was dropped rather than moved.
# 注：_gpShapeDragOrigR 只写不读（平移不改变圆半径），故删除而非搬迁。




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
	gpAnno = GPAnnotationEditor.new(self)
	# Create the right-click context-menu delegate (P2 split), owner = this canvas.
	# 创建右键上下文菜单委托（P2 拆分），状态持有者为本画布。
	_gpCtx = GPCanvasContextMenu.new(self)
	# Create the keyboard-shortcut delegate (M4 续). Shared shortcuts and the progressive-ESC
	# chain used to be inline methods of this canvas.
	# 创建键盘快捷键委托（M4 续）。共享快捷键与渐进式 ESC 链原先是本画布的内联方法。
	_gpShortcuts = GPCanvasShortcuts.new(self)
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
	# Bridge the canvas's own gpGraphChanged funnel into the app event bus (M2): one channel, so
	# the tool layer keeps emitting unchanged while new subscribers listen on the bus. The core
	# GPPIDGraph emits a raw signal; the canvas is the single place that maps it onto the bus
	# (now owned by the document manager, M6). The funnel stays — the graph does not emit the bus.
	# 把画布自身的 gpGraphChanged 漏斗桥入应用事件总线（M2）：单一通道，工具层照旧发射，
	# 新订阅者监听总线。core 的 GPPIDGraph 发射的是原始信号；画布是把它映射到总线的唯一位置
	# （总线现由文档管理器持有，M6）。漏斗保留——图本身不发射总线。
	gpGraphChanged.connect(_gpForwardGraphChanged)
	# Re-assert the core-graph binding (idempotent; covers a graph assigned before _ready).
	# 重申 core 图绑定（幂等，覆盖在 _ready 之前就被赋值的图）。
	if _gpGraphRef != null and not _gpGraphRef.gpGraphChanged.is_connected(_gpOnGraphDataChanged):
		_gpGraphRef.gpGraphChanged.connect(_gpOnGraphDataChanged)
	_gpResetView()


# (Re)bind the core graph's change signal. Called from the gpGraph setter.
# 由 gpGraph 的 setter 调用，用于（重新）绑定 core 图的变化信号。
func _gpSetGraph(gpValue: GPPIDGraph) -> void:
	if _gpGraphRef == gpValue:
		return
	if _gpGraphRef != null and _gpGraphRef.gpGraphChanged.is_connected(_gpOnGraphDataChanged):
		_gpGraphRef.gpGraphChanged.disconnect(_gpOnGraphDataChanged)
	_gpGraphRef = gpValue
	if _gpGraphRef != null and not _gpGraphRef.gpGraphChanged.is_connected(_gpOnGraphDataChanged):
		_gpGraphRef.gpGraphChanged.connect(_gpOnGraphDataChanged)
	# Rebuild the command context for the new graph and drop the old history: undo must
	# never reach back into a graph that is no longer displayed.
	# 为新图重建命令上下文并丢弃旧历史：撤销绝不能回到已不再显示的图。
	gpActions.gpBindGraph(_gpGraphRef, _gpState.gpIds)


# Core graph mutated programmatically (gpAddNode / gpRemoveNodeWithEdges /
# gpRemoveSymbolInstances / gpAddShape ...). Funnel it into the canvas signal so that
# interactive and programmatic changes reach listeners through ONE path.
# core 图被程序化改动（gpAddNode / gpRemoveNodeWithEdges / gpRemoveSymbolInstances /
# gpAddShape 等）。汇入画布信号，使交互改动与程序化改动走同一路径。
func _gpOnGraphDataChanged() -> void:
	gpGraphChanged.emit()
	# M6: any model mutation means there is unsaved work; let the document manager own the
	# dirty flag rather than a global singleton. No-op until a manager is bound.
	# M6：任何模型改动都意味着未保存；让文档管理器持有脏标记，而非全局单例。未绑定时为空操作。
	if _gpDocMgr != null:
		_gpDocMgr.gpMarkDirty()
	# M4: a programmatic model change must repaint too. Without this, any command that
	# mutates the graph (delete, move) updates the model but leaves stale pixels on
	# screen whenever the caller forgets an explicit queue_redraw().
	# M4：程序化改模型同样必须重绘。否则命令（删除、移动）改了模型却留下残影，
	# 只要调用方忘了显式 queue_redraw()，画面就是旧的。
	queue_redraw()


# Forward canvas graph changes onto the app event bus (M2 bridge).
# 把画布的图变化转发到应用事件总线（M2 桥接）。
func _gpForwardGraphChanged() -> void:
	gpEvents.gpGraphChanged.emit(_gpGraphRef)


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
func gpEmitStatus() -> void:
	var gpInfo: Dictionary = {
		"selection": gpSelectedId,
		"count": gpSelection.size(),
		"zoom": gpViewZoom,
		"world": _gpLastMouseWorld,
	}
	gpStatusUpdated.emit(gpInfo)
	# M2: same snapshot on the app bus; new subscribers listen here, not on the signal.
	# M2：同一份快照也发到应用总线；新订阅者监听这里而非画布信号。
	gpEvents.gpStatusUpdated.emit(gpInfo)


# ============================ camera / transform ============================
# ============================ 相机 / 坐标变换 ============================
# Reset the camera to 100% zoom and center the world origin.
# 将相机重置为 100% 缩放并把世界原点居中。
func _gpResetView() -> void:
	_gpCam.gpReset(size / 2.0)
	_gpApplyCamera()


# Apply the camera (offset + zoom) to the world root; the transform math lives in GPCanvasCamera.
# 将相机（偏移 + 缩放）应用到世界根节点；变换数学位于 GPCanvasCamera。
func _gpApplyCamera() -> void:
	_gpCam.gpApplyTo(gpWorldRoot)


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
	# M3: the active tool paints its OWN transient visuals (draw rubber band, in-progress polyline)
	# after the shared overlay, preserving the previous z-order — the band was already the last
	# thing GPCanvasOverlay drew. The hook existed since P2 but was never wired.
	# M3：活动工具在共享覆盖层之后绘制「自己的」瞬态视觉（绘图橡皮筋、进行中的折线），沿用原有
	# 层序——橡皮筋此前本就是 GPCanvasOverlay 最后绘制的内容。此钩子自 P2 起即已声明，但从未接线。
	_gpActiveTool().gpDrawOverlay(self)


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
# --- lookup ports delegate to GPCanvasHitTest (P5 extraction) ---
# --- 查找端口委托给 GPCanvasHitTest（P5 抽取）---
func gpNodeCenter(gpId: String) -> Vector2:
	return GPCanvasHitTest.gpNodeCenter(gpGraph, gpId)

func gpNodeRect(gpId: String) -> Rect2:
	return GPCanvasHitTest.gpNodeRect(gpGraph, gpBinder, gpId)

func gpHitTest(gpWorld: Vector2) -> String:
	return GPCanvasHitTest.gpHitNode(gpGraph, gpBinder, gpWorld)


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
			if _gpShortcuts.gpHandleKey(gpKey):
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
			gpEmitStatus()
			accept_event()
			return
		# Marquee in progress: track the rubber band.
		# 正在框选：跟踪橡皮筋。
		if gpMarq.gpActive:
			gpMarq.gpUpdate(gpMotion.position)
			queue_redraw()
			accept_event()
			return
		# Grip / whole-shape drag is owned by GPGripTool (P2 split).
		# 锚点 / 整图形拖拽由 GPGripTool 负责（P2 拆分）。
		if gpAnno.gpIsDragging():
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
# canvas exposes only public ports now that transient drag state lives in each tool.
# 返回当前分派目标的交互工具：调色板待放置优先于模式；否则注册表按 GPMode 映射（CONNECT 复用
# 选择工具）。瞬态拖拽状态现由各工具自持，画布仅经 gpCtx.gpCv 暴露公开端口。
func _gpActiveTool() -> GPCanvasTool:
	if gpPendingDef != null:
		return _gpPlaceTool
	return _gpRegistry.gpGet(gpMode)

func _gpOnLeftUp(gpScreen: Vector2) -> void:
	var gpWorld: Vector2 = gpWorldFromScreen(gpScreen)
	# Grip / whole-shape drag belongs to GPGripTool (P2 split).
	# 锚点 / 整图形拖拽由 GPGripTool 负责（P2 拆分）。
	if gpAnno.gpIsDragging():
		_gpGripTool.gpOnRelease(gpWorld)
		return
	# Everything else (draw commit / marquee / group drag) is dispatched to the active tool.
	# 其余（提交绘图 / 框选 / 整组拖拽）分派给活动工具。
	_gpActiveTool().gpOnRelease(gpWorld)

# _gpIsDrawMode() removed here: GPCanvasInteractState.gpIsDrawMode() already owns that rule
# (gpSetMode calls it), and the canvas copy became unreachable once the keyboard section
# moved to GPCanvasShortcuts.
# 此处删除 _gpIsDrawMode()：GPCanvasInteractState.gpIsDrawMode() 已持有该规则（gpSetMode 调用它），
# 键盘段迁到 GPCanvasShortcuts 后画布这份再无调用者。

# ============================ drawing annotation shapes ============================


# M3: _gpOnDrawDown / _gpCommitDraw / _gpFinishPolyline moved into GPDrawShapeTool together with
# the state they operate on. The canvas now reaches them only through the GPCanvasTool interface
# (press / move / release / key / overlay) and the gpCancel() port used by the ESC path.
# M3：_gpOnDrawDown / _gpCommitDraw / _gpFinishPolyline 已连同其所操作的状态迁入 GPDrawShapeTool。
# 画布现仅经 GPCanvasTool 接口（按下 / 移动 / 释放 / 按键 / 覆盖层）与 ESC 路径所用的 gpCancel()
# 端口访问它们。






# _gpDrawShapes / _gpDrawOneShape moved to GPCanvasOverlay (P2 split). They are invoked through
# _gpOverlay.gpDraw() from _draw(), so the canvas no longer paints the overlay itself.
# _gpDrawShapes / _gpDrawOneShape 已移至 GPCanvasOverlay（P2 拆分），经 _draw() 中的
# _gpOverlay.gpDraw() 调用，画布不再自行绘制覆盖层。


# Hit-test: index of the topmost annotation shape under the world point, or -1. Delegates to
# GPCanvasHitTest (P5 extraction); tolerance scales with zoom (6px at 100%).
# 命中测试：世界点下最上层注释图形下标，未命中 -1。委托 GPCanvasHitTest（P5 抽取）；容差随缩放（100% 时 6px）。
func gpHitShape(gpWorld: Vector2) -> int:
	return GPCanvasHitTest.gpHitShape(gpGraph, gpWorld, gpViewZoom)





# Annotation-shape editing (grip / whole-shape / vertex / bezier / promote-to-symbol) now lives
# in GPAnnotationEditor (P2 split). The canvas delegates to it via gpAnno (created in _ready()).
# 注释图形编辑（锚点 / 整图形 / 顶点 / 贝塞尔 / 提升为图元）现位于 GPAnnotationEditor（P2 拆分），
# 画布经 _ready() 中创建的 gpAnno 委托给它。




# Move every selected node by the drag delta measured since drag start.
# 按拖拽开始以来测得的位移量移动所有选中节点。
# Replaying from captured origins (instead of accumulating per-frame deltas) keeps the group
# rigid and free of rounding drift.
# 由记下的原始位置重放（而非逐帧累加增量）可保持整组刚性且无舍入漂移。

# ============================ selection ============================
# ============================ 选择 ============================
# Replace the selection set and keep gpSelectedId (the primary entry) in sync.
# 替换选择集，并同步 gpSelectedId（主选项）。
func gpSetSelection(gpIds: Array[String]) -> void:
	gpSelection = gpIds.duplicate()
	gpSelectedId = gpSelection[0] if not gpSelection.is_empty() else ""
	queue_redraw()
	# M2: selection is a first-class event again. It used to be smuggled to the host inside
	# the status snapshot, where main_window diffed the "selection" string to decide whether
	# to refresh the inspector. Subscribers now react to this directly.
	# M2：选择重新成为一等事件。过去它被塞进状态快照，由 main_window 比对 "selection"
	# 字符串来决定是否刷新属性面板；订阅者现在直接响应本事件。
	gpEvents.gpSelectionChanged.emit(gpSelection)
	gpEmitStatus()


# Select every node on the sheet (Ctrl/Cmd+A).
# 选中图纸上的所有节点（Ctrl/Cmd+A）。
func gpRequestSelectAll() -> void:
	if gpGraph == null:
		return
	var gpAll: Array[String] = []
	for gpN in gpGraph.gpNodes:
		gpAll.append(gpN.gpInstanceId)
	gpSetSelection(gpAll)


# Delete every selected node together with the edges attached to it.
# 删除所有选中节点及其附着的连线。
func gpRequestDeleteSelected() -> void:
	if gpGraph == null:
		return
	# Nodes AND shapes go in one request, so a mixed marquee delete stays ONE undo step.
	# 节点与图形同在一次请求中提交，故混合框选的删除仍是一个撤销步。
	if not gpActions.gpDeleteSelection(gpSelection, gpShapeSel):
		return
	gpShapeSel.clear()
	gpSetSelection([])
	queue_redraw()


# Undo the most recent user edit (Ctrl+Z). Returns false when there is nothing to undo.
# 撤销最近一次用户编辑（Ctrl+Z）。无可撤销时返回 false。
# Undo can remove the very things the selection still points at (undoing a place drops a
# node; undoing a shape insert shifts every later index). Pruning here means every caller
# — shortcut, menu, or a future script — gets a consistent selection for free.
# 撤销可能移除选择集仍指向的对象（撤销放置会移除节点；撤销插入图形会让后续下标整体前移）。
# 在此修剪，意味着所有调用方——快捷键、菜单或今后的脚本——都自动获得一致的选择集。
func gpUndo() -> bool:
	if not gpActions.gpUndo():
		return false
	_gpPruneSelection()
	return true


# Redo the most recently undone edit (Ctrl+Y / Ctrl+Shift+Z). Returns false when empty.
# 重做最近被撤销的编辑（Ctrl+Y / Ctrl+Shift+Z）。无可重做时返回 false。
func gpRedo() -> bool:
	if not gpActions.gpRedo():
		return false
	_gpPruneSelection()
	return true


# Whether an undo step is available (for enabling host menu items).
# 是否存在可撤销步骤（供宿主菜单项启用与否）。
func gpCanUndo() -> bool:
	return gpActions.gpCanUndo()


# Whether a redo step is available.
# 是否存在可重做步骤。
func gpCanRedo() -> bool:
	return gpActions.gpCanRedo()


# Drop selection entries that no longer resolve in the graph. Without this, undoing a place
# leaves gpSelection pointing at a node that is gone, and the inspector edits a ghost.
# 剔除图中已无法解析的选择项。否则撤销一次放置后，gpSelection 仍指向已消失的节点，
# 属性面板会去编辑一个幽灵对象。
func _gpPruneSelection() -> void:
	if gpGraph == null:
		return
	var gpKeep: Array[String] = []
	for gpId in gpSelection:
		if gpGraph.gpGetNode(gpId) != null:
			gpKeep.append(gpId)
	var gpShapeKeep: Array[int] = []
	for gpI in gpShapeSel:
		if gpI >= 0 and gpI < gpGraph.gpShapes.size():
			gpShapeKeep.append(gpI)
	if gpKeep.size() == gpSelection.size() and gpShapeKeep.size() == gpShapeSel.size():
		return
	gpShapeSel = gpShapeKeep
	gpSetSelection(gpKeep)


# Copy every selected node to a small offset, keeping its attributes and orientation.
# 把所有选中节点复制到小幅偏移处，保留其属性与朝向。
func gpRequestDuplicateSelected() -> void:
	if gpGraph == null or gpSelection.is_empty():
		return
	var gpCopies: Array[String] = gpActions.gpDuplicateSelection(gpSelection)
	if gpCopies.is_empty():
		return
	# Select the copies, not the originals: the natural next action is to drag them into place.
	# 选中副本而非原件：下一步自然是把它们拖到目标位置。
	gpSetSelection(gpCopies)
	queue_redraw()


# ============================ 编辑意图端口（M4 续） ============================
# ============================ edit intent ports (M4 cont) ============================
# Every user edit that changes the model goes through one of these ports. The canvas adds
# nothing to them: GPEditService turns the intent into a command, records it, and mutates
# the model. The view follows via GPPIDGraph.gpGraphChanged, already bridged (M2).
# 每一项改动模型的用户编辑都经这些端口之一。画布不附加任何逻辑：GPEditService 把意图变成
# 命令、记录它并改动模型；视图经 GPPIDGraph.gpGraphChanged（已在 M2 桥接）自动跟随。

# Place one symbol instance (palette click). Returns the new node id, "" on failure.
# 放置一个图元实例（调色板点击）。返回新节点 id，失败返回 ""。
func gpRequestPlaceNode(gpSymbolId: String, gpWorld: Vector2) -> String:
	return gpActions.gpPlaceNode(gpSymbolId, gpWorld)


# Connect two nodes with an edge. Returns false for a self-connection or a missing graph.
# 在两个节点之间连线。自连接或缺图时返回 false。
func gpRequestConnect(gpFromId: String, gpToId: String) -> bool:
	return gpActions.gpConnect(gpFromId, gpToId)


# Commit a finished annotation shape. Returns its index in gpShapes, or -1 on failure.
# 提交一枚绘制完成的注释图形。返回它在 gpShapes 中的下标，失败返回 -1。
func gpRequestAddShape(gpShape: GPShape) -> int:
	return gpActions.gpAddShape(gpShape)


# Record a finished group drag as one undo step. The caller rewinds the nodes to their
# pre-drag positions first, so the command re-applies the move instead of doubling it.
# 把一次完成的整组拖拽记录为一个撤销步。调用方先把节点回退到拖拽前位置，
# 使命令重新应用这次移动而非叠加一次。
func gpRequestMoveNodes(gpNodeIds: Array[String], gpDelta: Vector2) -> bool:
	return gpActions.gpMoveNodes(gpNodeIds, gpDelta)


# Ask the active interaction tool to abandon its half-finished state (ESC path). One
# generic port, so the canvas never needs to know which tool is currently mounted.
# 请求活动交互工具放弃其半成品状态（ESC 路径）。一个通用端口，使画布无需知道当前挂的是哪个工具。
func gpCancelActiveTool() -> bool:
	return _gpActiveTool().gpCancel()


# ============================ context menu ============================


# Zoom in or out while keeping the world point under the cursor stable.
# 以光标下的世界点为中心进行缩放。
func _gpZoomAt(gpScreen: Vector2, gpFactor: float) -> void:
	if not _gpCam.gpZoomAt(gpScreen, gpFactor):
		return
	_gpApplyCamera()
	queue_redraw()
	gpEmitStatus()


# Public: delete the current selection together with its edges (menu 编辑 / 删除).
# 公开：删除当前选择集及其关联的边（菜单「编辑 / 删除」）。
func gpDeleteSelection() -> void:
	gpRequestDeleteSelected()


# Public: drop the selection set (used before swapping in another graph).
# 公开：清空选择集（用于换入另一张图之前）。
func gpClearSelection() -> void:
	gpMarq.gpCancel()
	if _gpSelectTool != null:
		_gpSelectTool.gpCancelDrag()
	gpShapeSel.clear()
	gpSetSelection([])


# Public: zoom by a step centered on the canvas (menu "放大/缩小").
# 公开：以画布中心为锚点缩放一步（菜单「放大/缩小」）。
func gpZoomStep(gpFactor: float) -> void:
	_gpZoomAt(size / 2.0, gpFactor)


# Public read port: a consistent snapshot of the canvas interaction state for tools / external
# consumers. Replaces ad-hoc peeking at private fields with one stable call.
# 公开只读端口：对外暴露画布交互状态的一致快照，取代对各私有字段的零散窥探。
# M3: part of the canvas port API (gpRequest* / gpSnapshot).
# M3：画布端口 API 的一部分（gpRequest* / gpSnapshot）。
func gpSnapshot() -> Dictionary:
	var gpSnap: Dictionary = {
		"mode": gpMode,
		"selection": gpSelection.duplicate(),
		"shape_sel": gpShapeSel.duplicate(),
		"connect_from": gpConnectFrom,
		"view_offset": gpViewOffset,
		"view_zoom": gpViewZoom,
		"marquee_active": gpMarq.gpActive,
		"has_pending_def": gpPendingDef != null,
	}
	if gpGraph != null:
		gpSnap["node_count"] = gpGraph.gpNodes.size()
		gpSnap["shape_count"] = gpGraph.gpShapes.size()
	else:
		gpSnap["node_count"] = 0
		gpSnap["shape_count"] = 0
	return gpSnap


# Public: reset view to 100% centered (menu "适应窗口").
# 公开：重置视图为 100% 居中（菜单「适应窗口」）。
func gpResetView() -> void:
	_gpResetView()
	queue_redraw()
	gpEmitStatus()


# Clean up cached references when the canvas leaves the tree.
# 画布离开场景树时清理缓存引用。
func _notification(gpWhat: int) -> void:
	if gpWhat == NOTIFICATION_PREDELETE:
		if gpBinder != null:
			gpBinder.gpClear()
