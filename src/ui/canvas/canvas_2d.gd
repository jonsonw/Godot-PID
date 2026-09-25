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

# Public API signal: emitted by external callers (double-click in select_tool, right-click
# edit menu in canvas_context_menu) and connected by the host in main_window. The GDScript
# analyzer cannot see cross-class usage, hence the explicit ignore below.
# 公开 API 信号：由外部调用方发射（select_tool 双击、canvas_context_menu 右键编辑菜单）、
# 宿主在 main_window 中连接；静态分析器看不到跨类用途，故显式忽略。
@warning_ignore("unused_signal")
# 请求宿主为某个图元类型打开图元编辑（弹出 Make-Symbol 对话框，预填该图元几何）。
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
	# mode is a state broadcast like any other, so it travels on the bus as well.
	# 模式与其他状态广播一样，同样走总线。
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

# would make every open sheet react to another sheet's change.
# Since M6 the bus is OWNED by the GPAppDocumentManager (the composition root injects it via
# gpBindDocument()); the canvas only borrows it. A private fallback keeps the canvas usable when
# no manager is bound yet (standalone tool tests, the construction window before bind).
# 自 M6 起总线由 GPAppDocumentManager 持有（组合根经 gpBindDocument() 注入）；画布只借用。
# 私有回退使画布在无管理器绑定时仍可用（独立工具测试、绑定前的构造期）。
var _gpEventBusFallback: GPEventBus = GPEventBus.new()
var _gpDocMgr: GPAppDocumentManager = null
var gpEvents: GPEventBus:
	get:
		if _gpDocMgr != null and _gpDocMgr.gpBus != null:
			return _gpDocMgr.gpBus
		return _gpEventBusFallback

# mode events onto the manager's bus, and marks the document dirty on edits.
func gpBindDocument(gpMgr: GPAppDocumentManager) -> void:
	_gpDocMgr = gpMgr

# Application editing service : the canvas asks it for every user edit (delete /
# duplicate / place / connect / draw-commit / move) and gets plain values back. It owns the
# per-document command context and undo stack, so the canvas itself holds no command
# machinery — it only forwards intent and applies the view-side consequences.
# 应用编辑服务：画布向它请求每一项用户编辑（删除 / 复制 / 放置 / 连线 / 提交绘图 /
# 移动），只拿回普通值。它持有「每文档」的命令上下文与撤销栈，画布自身不再持有任何命令
# 机制 —— 只负责转发意图并处理视图侧后果。
# Per-sheet editing collaborator. It stays on the canvas because the canvas is the one that
# 脏标记状态，而非这个服务。
var gpActions: GPEditService = GPEditService.new()

# places and duplicates instances; it rebinds to the graph's rules on every document swap, so
# the sequence marks stay the ones the file serialises.
# 每次切换文档时它都会重新绑定到图的规则上，使序号水位线始终是文件会序列化的那一份。
var gpTags: GPTagRegistry = GPTagRegistry.new()

# Tag (位号) label grip / drag delegate . Mirrors gpEdgeGrips: the transient drag state
# lives here, not on the canvas.
# 位号标签抓取点 / 拖拽委托。与 gpEdgeGrips 同形：瞬态拖拽状态存于此，不在画布上。
var gpLabelGrips: GPLabelGripOps = null

# Edge line-number (管线号) grip / drag delegate . The number on a pipe is itself draggable;
# this holds the transient drag state (which edge, where it started) off the canvas, exactly like
# gpLabelGrips does for node tags.
# 边管线号抓取点 / 拖拽委托。管线上的编号本身可拖动；瞬态拖拽状态（哪条边、从哪开始）
# 寄于此，与图元位号之于 gpLabelGrips 同形。
var gpEdgeTagGrips: GPEdgeTagGripOps = null

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

# Injected render-style snapshot. Built from Settings / I18n at assembly and
# pushed into the binder; rebuilt + re-pushed whenever locale / font / pipe-tag style changes so
# the render layer never reads an autoload. Null only when the canvas is used headlessly without
# a live app (the views then fall back to their own defaults).
# 注入的渲染样式快照。在装配时由 Settings / I18n 构造并推入绑定器；
# 语言 / 字号 / 位号样式变化时重建并重推，使 render 层永不读 autoload。仅当画布在脱离
# 现场环境下使用（视图回落自身默认值）时为 null。
var gpRenderStyle: GPRenderStyle = null

# ---- 四个实现类（1 root + 4 impl，非破坏性） ----
# ---- the four implementation classes (1 root + 4 impl, non-breaking) ----
# Each one owns one responsibility end to end and reaches the canvas only through its public
# ports. The root keeps EVERY public port it had before as a one-line forward, so callers
# outside the canvas (main_window, inspector, tools) need no change at all.
# 每个类端到端接管一项职责，仅经画布的公开端口访问它。根类保留其原有的每一个公开端口
# （单行转发），故画布外部调用方（main_window、属性面板、工具）零改动。
#
# View / 视图：相机变换、缩放平移、坐标换算。
var gpViewController: GPCanvasViewController = null
# Input / 输入：事件路由、活动工具分派、平移与框选。
var gpInputRouter: GPCanvasInputRouter = null
# Edit facade / 编辑门面：全部 gpRequest* 意图 + 撤销重做。
var gpEditFacade: GPCanvasEditFacade = null
# Symbol layer / 符号图层：视图同步、几何查询、命中测试。
var gpSymbolLayer: GPCanvasSymbolLayer = null

# Right-click context menu instance, wired by the input router when it builds the delegates.
# Exposed here so tools (e.g. GPPlaceTool) can open a purpose-specific popup — currently the
# "dropped onto a line" choice — without owning any popup code themselves.
# 右键上下文菜单实例，由输入路由在构建委托时接线。暴露于此使工具（如 GPPlaceTool）能打开
# 特定用途的弹窗（当前为「落到连线上」的选择），而无需自身持有任何弹窗代码。
var gpContextMenu: GPCanvasContextMenu = null

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

# Drawing delegate : owns the background overlay paint, reads live state from this
# canvas. Created in _ready() once the canvas is a valid CanvasItem.
# 绘制委托：持有背景覆盖层绘制逻辑，从本画布读取实时状态。在 _ready() 中创建。
var _gpOverlay: GPCanvasOverlay = null

# Annotation-shape editing delegate : grip / whole-shape / vertex / Bézier editing and
# "promote shapes to symbol". Created in _ready() with this canvas as its state owner.
# 注释图形编辑委托：锚点 / 整图形 / 顶点 / 贝塞尔编辑与「提升为图元」。在 _ready() 中
# 以本画布作为状态持有者创建。
# public because it is a shared collaborator — tools (via gpCtx.gpAnno) and the context menu
# both drive it. Exposing the collaborator beats exposing the canvas internals it touches.
# 公开，因为它是共享协作者——工具（经 gpCtx.gpAnno）与右键菜单都要驱动它。暴露协作者优于
# 暴露它所触碰的画布内部实现。
var gpAnno: GPAnnotationEditor = null

# Edge line-number editor delegate : a floating LineEdit opened by double-clicking an edge,
# committing through the command layer as one undo step. Created in _ready() with this canvas.
# 边管线号编辑器委托：双击边时打开的浮层 LineEdit，经命令层以一个撤销步提交。在 _ready() 中以
# 本画布创建。
var gpEdgeEditor: GPEdgeTagEditor = null

# Edge grip / route editing delegate : drag an endpoint to reconnect or a vertex to re-route,
# each commit going through the command layer as one undo step. Created in _ready() with this canvas.
# 边抓取点 / 布线编辑委托：拖端点改接或拖顶点改布线，每次提交经命令层成为一个撤销步。
# 在 _ready() 中以本画布创建。
var gpEdgeGrips: GPEdgeGripOps = null

# Endpoint (anchor) highlight / pick / drag-to-connect delegate. Mirrors gpEdgeGrips: the
# transient port state never lands on the canvas.
# 端点（锚点）高亮 / 拾取 / 拖拽连线委托。与 gpEdgeGrips 同形：瞬态端点状态从不落在画布上。
var gpPortOps: GPPortConnectOps = null

# 右键菜单委托、快捷键委托、工具注册表与六个模式工具已随「输入路由」迁出，
# 现由 GPCanvasInputRouter（gpInputRouter.gpBuildTools()）持有 —— 它们只被输入分派使用。
# the context-menu delegate, the shortcut delegate, the tool registry and the
# six mode tools moved out with the input router; only input dispatch ever touches them.

# Id counter for new nodes/edges — proxy to state.gpIds (GPIdGen). / 新节点/边 id 计数器 —— 代理 state.gpIds。
var gpNextId: int:
	get: return _gpState.gpIds.gpCounter
	set(gpV): _gpState.gpIds.gpCounter = gpV

# 节点移动统一走 GPEditService.gpMoveNodes()。
# deleted rather than moved; node moves go through GPEditService.gpMoveNodes().

# ---- world root ----
# ---- 世界根节点 ----
# Node2D that holds all symbol/edge view nodes and carries the camera transform.
# 承载所有图元/连线视图节点并承载相机变换的 Node2D。
var gpWorldRoot: Node2D = null

# ---- sheet / drawing frame ----
# ---- 图纸 / 图框 ----
# The sheet this canvas is showing: supplies the frame size, title block and the
# drawing-text language mode (see plan Phase 2). Null until the host assigns one.
# 本画布正在显示的图纸：提供图幅、标题栏与图纸文字语言模式（见计划 Phase 2）。
# 宿主赋值前为 null。
var gpSheet: GPSheet = null

# Frame renderer, a child of world_root placed BEHIND every symbol (z_index -1).
# 图框渲染器，挂在 world_root 下且位于所有图元**之下**（z_index = -1）。
var gpFrame: GPFrameView = null

# Tracing underlay (background reference image), created in _ready() (v0.1 Phase 5).
# 追踪底图（背景参考图），在 _ready() 中创建（v0.1 Phase 5）。
var gpBackground: GPBackgroundView = null

# True until the sheet has been fitted into the viewport once (see _gpFitIfReady()). Kept as a
# one-shot so a late-arriving control size still fits the drawing, yet the user's own pan/zoom is
# never overridden afterwards.
# 为 true 时表示「尚未把图幅适配进视口一次」（见 _gpFitIfReady()）。以一次性标志实现，使
# 迟到的控件尺寸仍能触发适配，而此后用户自己的平移/缩放永不被覆盖。
var _gpNeedFit: bool = true

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
#
# 放置虚影预览的光标兜底：进入放置态（非空）光标变手型，离开（放置完成 / ESC / 切换工具）恢复
# 默认箭头。这是「态变化」那一刻的保证；持续增长的手型重申由 GPPlaceTool.gpOnMove() 每帧负责。
# Cursor fallback for the place-ghost preview: a hand while placing (non-null) and the default
# arrow once leaving (placed / ESC / tool switch). This guarantees the transition itself; keeping
# the hand afterwards is GPPlaceTool.gpOnMove()'s job, which re-asserts it every move.
var gpPendingDef: GPSymbolDef:
	get: return _gpState.gpPendingDef
	set(gpV):
		_gpState.gpPendingDef = gpV
		if gpV != null:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		else:
			mouse_default_cursor_shape = Control.CURSOR_ARROW

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


# GPCanvasInputRouter —— 它由输入事件驱动，只被输入路由消费。
# middle-button pan transient state moved into GPCanvasInputRouter.


# Indices of the currently selected annotation shapes (mirror of gpSelection for the node layer).
# 当前选中注释图形的下标（与图元层的 gpSelection 对应的镜像）。
var gpShapeSel: Array[int] = []

# selection are mutually exclusive in practice, and a proxy into GPCanvasSelection would force the
# node/shape/edge three-way rule into that class before it is understood.
# 而代理进 GPCanvasSelection 会迫使「节点/图形/边」三方互斥规则提前进入那个类。
var gpEdgeSel: Array[String] = []

# Anchor currently under the cursor (""-keyed empty dictionary when none). Written by
# GPPortConnectOps so the hover highlight and the pick logic share one owner.
# 光标下当前的锚点（无则为空字典）。由 GPPortConnectOps 写入，使悬停高亮与拾取逻辑共用一个持有者。
var gpHoverPort: Dictionary = {}

# The two endpoints picked for "auto-connect" (in click order, at most two).
# 为「自动连线」拾取的两个端点（按点击顺序，最多两个）。
var gpPortPick: Array[Dictionary] = []

# the drawing transient state (_gpDrawFrom / _gpDrawTo / _gpDrawActive / _gpPolyPts) and the
# three drawing verbs (_gpOnDrawDown() / _gpCommitDraw() / _gpFinishPolyline()) moved into GPDrawShapeTool,
# which now also paints its own rubber band via the gpDrawOverlay() hook (declared in P2, never wired).
# 绘图瞬态状态（_gpDrawFrom / _gpDrawTo / _gpDrawActive / _gpPolyPts）与三个绘图动作
# gpDrawOverlay() 钩子自绘橡皮筋（此钩子 P2 即已声明，但从未接线）。

# Last known mouse position in world coordinates.
# 最近一次鼠标在世界坐标系中的位置。
var _gpLastMouseWorld: Vector2 = Vector2.ZERO

# the annotation grip / whole-shape drag state (_gpShapeDragIdx / _gpShapeDragStart /
# _gpShapeDragOrigPts / _gpShapeDragOrigR / _gpGripDrag) moved OUT of the canvas into
# GPAnnotationEditor, which is the only party that consumes it. It is reached through the
# gpIsDragging() / gpStartShapeDrag() / gpEnd*Drag port declared there.
# 注释锚点 / 整图形拖拽状态（_gpShapeDragIdx / _gpShapeDragStart / _gpShapeDragOrigPts /
# 状态的一方。外部经该文件声明的 gpIsDragging() / gpStartShapeDrag() / gpEnd*Drag 端口访问。
# Note: _gpShapeDragOrigR was write-only (set and cleared, never read) — circle radius does not
# change under translation — so it was dropped rather than moved.
# 注：_gpShapeDragOrigR 只写不读（平移不改变圆半径），故删除而非搬迁。


# 四个实现类在**构造期**装配，而非只在 _ready() 中。
# 画布常在脱离场景树的情况下被使用（headless 回归检查器直接 GPCanvas2D.new 后调用其
# 公开端口），那时 _ready() 永不触发 —— 若协调者只在 _ready() 里创建，转发壳会打到 null 上。
# the four implementation classes are assembled in _init(), not only in
# _ready(). A canvas is routinely used outside the scene tree (headless regression checkers
# call GPCanvas2D.new and then its public ports), where _ready() never fires; creating the
# coordinators there would make every forward shell hit null.
func _init() -> void:
	gpViewController = GPCanvasViewController.new()
	gpViewController.gpHost = self
	gpInputRouter = GPCanvasInputRouter.new()
	gpInputRouter.gpHost = self
	gpEditFacade = GPCanvasEditFacade.new()
	gpEditFacade.gpHost = self
	gpSymbolLayer = GPCanvasSymbolLayer.new()
	gpSymbolLayer.gpHost = self


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
	# Keyboard shortcuts (Delete / Ctrl+A / ESC) arrive through gpInputRouter.gpOnGuiInput(), which requires focus.
	# 键盘快捷键（Delete / Ctrl+A / ESC）经 gpInputRouter.gpOnGuiInput() 送达，而这需要焦点。
	focus_mode = Control.FOCUS_CLICK
	# Create the world root. All symbol/edge views live here so they share one transform.
	# 创建世界根节点。所有图元/连线视图都挂在此处，共享同一变换。
	gpWorldRoot = Node2D.new()
	gpWorldRoot.name = "WorldRoot"
	add_child(gpWorldRoot)
	# Rasterise text at the SCALE IT IS DRAWN AT. The canvas stretches its content and world_root
	# scales by the camera zoom, so with the default (PARENT_NODE = off at the root) an N mm glyph is
	# rasterised at N pixels and then magnified — the blurry "ghosted" tag text. Godot's per-item
	# oversampling re-rasterises the glyphs for the effective transform, keeping tags crisp at every
	# zoom. NOTE the property is an ENUM, not a bool: `= true` coerces to value 1, i.e. DISABLED.
	# 按「实际绘制缩放」光栅化文字。画布会拉伸内容、world_root 又按相机缩放，故在默认值
	#（PARENT_NODE，根节点处等价于关闭）下，N mm 的字形先以 N 像素光栅化再被放大 —— 正是发虚的
	# 位号文字。Godot 的逐项过采样会按有效变换重新光栅化字形，使位号在任意缩放下都清晰。
	# 注意此属性是**枚举**而非布尔：写 `= true` 会被强转为数值 1，即 DISABLED。
	oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
	gpWorldRoot.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
	# The tracing underlay must sit UNDER the frame and the symbols, but it still has to be ABOVE the
	# canvas' own background fill. It therefore uses z_index 0 and relies on child ORDER: it is added
	# first, so it paints first among world_root's children. A NEGATIVE z_index cannot be used here,
	# because the canvas paints its opaque background + grid from its own canvas item at z_index 0 —
	# anything below that is drawn beneath an opaque rectangle and is simply invisible (measured:
	# the frame was bound and positioned correctly yet never showed up until its z_index was raised).
	# 追踪底图必须位于图框与图元之下，但仍须高于画布自身的底色填充。故它使用 z_index 0 并依赖
	# **子节点顺序**：它最先加入，因此在 world_root 的子节点中最先绘制。**不可**用负 z_index：
	# 画布在其自身 canvas item 上以 z_index 0 绘制不透明底色与网格 —— 低于该值的任何内容都画在
	# 不透明矩形之下、根本不可见（实测：图框已正确绑定与定位，却直到提高 z_index 才显示）。
	gpBackground = GPBackgroundView.new()
	gpBackground.name = "BackgroundView"
	gpBackground.z_index = 0
	gpWorldRoot.add_child(gpBackground)
	# The frame also sits below every symbol by ORDER (added before the binder creates any symbol or
	# edge view), not by a negative z_index — see the note above.
	# 图框同样以**顺序**（早于绑定器创建任何图元/连线视图）位于所有图元之下，而非负 z_index ——
	# 见上方说明。
	gpFrame = GPFrameView.new()
	gpFrame.name = "FrameView"
	gpFrame.z_index = 0
	gpWorldRoot.add_child(gpFrame)
	# Re-apply the sheet NOW that the frame renderer exists. The host binds the sheet through
	# gpSetSheet() BEFORE this Control is added to the tree (center_area builds the canvas, binds
	# the sheet, then adds the canvas), so at that moment gpFrame is still null and the assignment
	# is swallowed — which is exactly why no frame was ever drawn. Replaying it here is idempotent
	# and covers every ordering.
	# 在渲染器存在后立刻重申图纸。宿主经 gpSetSheet() 绑定图纸的时机早于本控件入树
	#（center_area 先建画布、绑图纸、再把画布入树），当时 gpFrame 仍为 null，赋值被吞 —— 这正是
	# 图框从未画出的原因。此处重放是幂等的，可覆盖任何装配顺序。
	gpSetSheet(gpSheet)
	# Create the graph binder that owns view-sync logic and caches.
	# 创建持有视图同步逻辑与缓存的图绑定器。
	gpBinder = GPGraphBinder.new()
	gpBinder.name = "GraphBinder"
	add_child(gpBinder)
	gpBinder.gpWorldRoot = gpWorldRoot
	# 构造渲染样式快照并注入绑定器，使 render 层不读 autoload。
	# 订阅语言 / 字号 / 位号样式变化，变化时重建快照并显式重推（见下方三个回调）。
	# : build the render-style snapshot and inject it so the render layer
	# stays autoload-free; locale / font / pipe-tag changes rebuild + re-push it (see callbacks).
	gpRenderStyle = gpBuildRenderStyle()
	gpBinder.gpStyle = gpRenderStyle
	# Create the drawing delegate . It borrows this Control as its CanvasItem.
	# 创建绘制委托。它以本 Control 作为绘制目标 CanvasItem。
	_gpOverlay = GPCanvasOverlay.new(self)
	# Create the annotation-shape editing delegate , owner = this canvas.
	# 创建注释图形编辑委托，状态持有者为本画布。
	gpAnno = GPAnnotationEditor.new(self)
	# Create the edge editing delegates , owner = this canvas. They are reached by the
	# select tool through gpCtx (mirroring gpAnno), so transient edge-edit state never lives here.
	# 创建边编辑委托，状态持有者为本画布。选择工具经 gpCtx 访问它们（与 gpAnno 同形），
	# 故边的瞬态编辑状态不落在本画布上。
	gpEdgeEditor = GPEdgeTagEditor.new(self)
	gpEdgeGrips = GPEdgeGripOps.new(self)
	# M10b: the tag label gets the same grip treatment as an edge vertex.
	# M10b：位号标签获得与边拐点相同的抓取点待遇。
	gpLabelGrips = GPLabelGripOps.new(self)
	# Edge line-number grip: the pipe's number is itself draggable, with a leader line drawn
	# back to the pipe when dragged far enough. / 边管线号抓取点：管线编号可拖动，拖远时画引出线。
	gpEdgeTagGrips = GPEdgeTagGripOps.new(self)
	# Endpoint-anchor interaction delegate (highlight / pick / drag-to-connect).
	# 端点锚点交互委托（高亮 / 拾取 / 拖拽连线）。
	gpPortOps = GPPortConnectOps.new(self)
	# 右键菜单委托、快捷键委托、工具注册表与六个模式工具由输入路由自建。
	# : the input router builds its context-menu delegate, shortcut delegate,
	# tool registry and the six mode tools — they are input-dispatch implementation details.
	gpInputRouter.gpBuildTools()
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
	if _gpSettings != null and _gpSettings.has_signal("gpPipeTagStyleChanged"):
		_gpSettings.gpPipeTagStyleChanged.connect(_gpOnTagStyleChanged)
	# the tool layer keeps emitting unchanged while new subscribers listen on the bus. The core
	# GPPIDGraph emits a raw signal; the canvas is the single place that maps it onto the bus
	# (now owned by the document manager, M6). The funnel stays — the graph does not emit the bus.
	# 新订阅者监听总线。core 的 GPPIDGraph 发射的是原始信号；画布是把它映射到总线的唯一位置
	# （总线现由文档管理器持有，M6）。漏斗保留——图本身不发射总线。
	gpGraphChanged.connect(_gpForwardGraphChanged)
	# Re-assert the core-graph binding (idempotent; covers a graph assigned before _ready()).
	# 重申 core 图绑定（幂等，覆盖在 _ready() 之前就被赋值的图）。
	if _gpGraphRef != null and not _gpGraphRef.gpGraphChanged.is_connected(_gpOnGraphDataChanged):
		_gpGraphRef.gpGraphChanged.connect(_gpOnGraphDataChanged)
	# Fit the sheet ONCE, as soon as the control has a real size. _ready() usually runs while the
	# host is still positioning this Control (size 0), and gpResetCamera() would then place the
	# world origin at the top-left corner — the drawing would start off half off-screen. The
	# resized signal covers the case where the size arrives later; the flag makes it a one-shot so
	# the user's own pan/zoom is never fought afterwards.
	# 在控件获得真实尺寸后**一次性**适配图幅。_ready() 执行时宿主往往仍在摆放本控件（尺寸为 0），
	# 此时 gpResetCamera() 会把世界原点放到左上角 —— 图纸一开始就偏出屏外。resized 信号覆盖
	# 「尺寸稍后才到」的情形；标志位保证只做一次，之后绝不与用户自己的平移/缩放争夺视图。
	resized.connect(_gpOnCanvasResized)
	_gpFitIfReady()


# Fit the sheet into the viewport once the control has a measurable size (one-shot).
# 控件尺寸可测后把图幅适配进视口（仅一次）。
func _gpFitIfReady() -> void:
	if not _gpNeedFit:
		return
	if size.x <= 1.0 or size.y <= 1.0:
		return
	if gpSheet != null:
		gpViewController.gpFitSheet(gpSheet.gpWidthMM, gpSheet.gpHeightMM)
	else:
		gpViewController.gpResetCamera()
	_gpNeedFit = false
	# The camera moved, so the on-canvas text must be rasterised at the new scale (gpFitSheet /
	# gpResetCamera already did that) and the status bar must show the resulting zoom.
	# 相机已移动，故画布文字须按新缩放重新光栅化（gpFitSheet / gpResetCamera 已完成），
	# 状态栏也须显示新的缩放值。
	gpEmitStatus()


# Re-run the one-shot fit when the size first becomes available.
# 尺寸首次可用时重跑一次性适配。
func _gpOnCanvasResized() -> void:
	_gpFitIfReady()


# Bind the sheet this canvas displays and repaint its frame (see plan Phase 2).
# WHY A SETTER AND NOT A PLAIN ASSIGNMENT: assigning gpSheet alone would leave the frame
# renderer holding the previous sheet, so the visible frame would silently disagree with
# the sheet the host thinks is open. The refresh is what keeps them in lockstep.
# 绑定本画布显示的图纸并重绘图框（见计划 Phase 2）。
# 为何用方法而非直接赋值：只赋 gpSheet 会让图框渲染器仍持旧图纸，可见图框会与宿主认为
# 打开的那张图纸静默不一致。重绘正是让二者保持同步的那一步。
func gpSetSheet(gpValue: GPSheet) -> void:
	gpSheet = gpValue
	if gpFrame != null:
		gpFrame.gpSheet = gpValue
		gpFrame.gpRefresh()
	if gpBackground != null:
		gpBackground.gpSheet = gpValue
		gpBackground.gpRefresh()


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
	# hand the tag registry to the service so placement and duplication mint unique tags.
	# gpBindGraph() re-derives the index from the graph, so a document edited before M9 starts
	# from the truth rather than an empty cache.
	# 把位号注册器交给编辑服务，使放置与复制能铸造唯一位号。
	# gpBindGraph() 会从图重新推导索引，故 M9 之前编辑过的文档从真相出发而非空缓存。
	gpActions.gpBindGraph(_gpGraphRef, _gpState.gpIds, gpTags)


# Core graph mutated programmatically (gpAddNode() / gpRemoveNodeWithEdges() /
# gpRemoveSymbolInstances() / gpAddShape() ...). Funnel it into the canvas signal so that
# interactive and programmatic changes reach listeners through ONE path.
# core 图被程序化改动（gpAddNode() / gpRemoveNodeWithEdges() / gpRemoveSymbolInstances() /
# gpAddShape() 等）。汇入画布信号，使交互改动与程序化改动走同一路径。
func _gpOnGraphDataChanged() -> void:
	gpGraphChanged.emit()
	# any model mutation means there is unsaved work; let the document manager own the
	# dirty flag rather than a global singleton. No-op until a manager is bound.
	# 任何模型改动都意味着未保存；让文档管理器持有脏标记，而非全局单例。未绑定时为空操作。
	if _gpDocMgr != null:
		_gpDocMgr.gpMarkDirty()
	# a programmatic model change must repaint too. Without this, any command that
	# mutates the graph (delete, move) updates the model but leaves stale pixels on
	# screen whenever the caller forgets an explicit queue_redraw.
	# 程序化改模型同样必须重绘。否则命令（删除、移动）改了模型却留下残影，
	# 只要调用方忘了显式 queue_redraw，画面就是旧的。
	queue_redraw()


# Forward canvas graph changes onto the app event bus .
# 把画布的图变化转发到应用事件总线。
func _gpForwardGraphChanged() -> void:
	gpEvents.gpGraphChanged.emit(_gpGraphRef)


# React to language change: rebuild the style snapshot and re-push it into every view.
# 语言变化时重建样式快照并重新推入所有视图。
func _gpOnLocaleChanged(_gpLocale: String) -> void:
	_gpRebuildRenderStyle()


# React to symbol font/style change: rebuild the style snapshot and re-push it.
# 图元字体/样式变化时重建样式快照并重新推入。
func _gpOnSymbolStyleChanged() -> void:
	_gpRebuildRenderStyle()


# React to pipe-tag style change (rotate / font): rebuild + re-push, then the views repaint.
# 位号样式（旋转 / 字号）变化时重建并重新推入，视图随后重绘。
func _gpOnTagStyleChanged() -> void:
	_gpRebuildRenderStyle()


# 由 Settings / I18n 重建渲染样式快照，写回 gpRenderStyle 并显式重推给绑定器。
# 所有视图的 style 字段随之更新，旧视图不再残留旧字号 / 旧文字 —— 该行为由
# tests/gp_test_render_style_injection.gd 钉住（切换 locale 后所有视图 style 已更新）。
# rebuild the render-style snapshot from Settings / I18n, write it back into
# gpRenderStyle and re-push it to the binder. Every view's style updates, so stale views never
# linger — this is pinned by tests/gp_test_render_style_injection.gd.
func _gpRebuildRenderStyle() -> void:
	gpRenderStyle = gpBuildRenderStyle()
	if gpBinder != null:
		gpBinder.gpApplyStyle(gpRenderStyle)


# 从 Settings / I18n 读取当前渲染样式，构造纯数据快照后返回。
# 调用方持有 autoload 依赖，本方法只负责取值；autoload 缺失时（headless）回落安全默认值。
# read the current render style from Settings / I18n and return a pure-data
# snapshot. The caller owns the autoload dependency; this method only reads. Falls back to safe
# defaults when the autoloads are absent (headless).
func gpBuildRenderStyle() -> GPRenderStyle:
	return GPRenderStyle.gpFromSources(gpResolveAutoload(self, "Settings"), gpResolveAutoload(self, "I18n"))


# Resolve an autoload by name through the SCENE TREE, or null when there is none.
# 经**场景树**按名字解析自动加载单例；不存在时返回 null。
# ⚠️ This replaced an `Engine.has_singleton` / `Engine.get_singleton` pair that could NEVER
# succeed: in Godot 4 an autoload is a node under /root, not an Engine singleton. The failed lookup
# was silent, so inside the running app every setting degraded to its fallback — a vertical pipe
# number stayed horizontal with tag_rotate=true on disk, and font / font size / locale / tag size /
# screen-constant width were dead the same way. The signal hookups in _ready() already used this
# tree form (see the /root/I18n, /root/Settings lookups there); only the snapshot builder did not.
# ⚠️ 此处替换掉了一对**永远不可能成功**的 `Engine.has_singleton` / `Engine.get_singleton`：
# Godot 4 中 autoload 是 /root 下的节点，而非 Engine 单例。该查找失败时无声无息，于是应用内每一项设置
# 都退化为回落值 —— 磁盘上 tag_rotate=true，竖管编号却仍是水平文字；字体 / 字号 / 语言 / 位号字号 /
# 屏幕恒定线宽同样失效。_ready() 中的信号接线用的本就是这种场景树写法（见那里的 /root/I18n、
# /root/Settings），唯独构建快照这一处不是。
# static, so the resolution itself is testable without putting a canvas into a tree.
# 声明为 static，使该解析本身可在不把画布入树的前提下被测试。
# The is_inside_tree() guard keeps an out-of-tree caller (a bare `GPCanvas2D.new()` in a headless
# test) on the safe fallback path instead of tripping an absolute-path lookup with no tree to
# resolve against. / is_inside_tree() 护栏使树外调用方（headless 测试中裸 new 出的画布）留在安全
# 回落路径上，而不会在无树可解析时触发一次绝对路径查找。
static func gpResolveAutoload(gpHost: Node, gpName: String) -> Object:
	if gpHost == null or not gpHost.is_inside_tree():
		return null
	return gpHost.get_node_or_null("/root/" + gpName)


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
	# same snapshot on the app bus; new subscribers listen here, not on the signal.
	# 同一份快照也发到应用总线；新订阅者监听这里而非画布信号。
	gpEvents.gpStatusUpdated.emit(gpInfo)


func gpScreenFromWorld(w: Vector2) -> Vector2:
	return gpViewController.gpScreenFromWorld(w)


func gpWorldFromScreen(gpS: Vector2) -> Vector2:
	return gpViewController.gpWorldFromScreen(gpS)


# ============================ drawing (background only) ============================
# ============================ 绘制（仅背景） ============================
# Godot calls this when the canvas needs to redraw the background overlay.
# Godot 在需要重绘背景覆盖层时调用此方法。
func _draw() -> void:
	# Sync the node tree with the graph before drawing the background overlay.
	# 在绘制背景覆盖层之前，先把节点树与图数据同步。
	gpSymbolLayer.gpSyncViews()
	# The background overlay paint is delegated to GPCanvasOverlay — same math,
	# same draw order, so the visual result is byte-for-byte identical.
	# 背景覆盖层绘制委托给 GPCanvasOverlay——同一套数学、同一绘制顺序，观感完全一致。
	_gpOverlay.gpDraw()
	# the active tool paints its OWN transient visuals (draw rubber band, in-progress polyline)
	# after the shared overlay, preserving the previous z-order — the band was already the last
	# thing GPCanvasOverlay drew. The hook existed since P2 but was never wired.
	# 活动工具在共享覆盖层之后绘制「自己的」瞬态视觉（绘图橡皮筋、进行中的折线），沿用原有
	# 层序——橡皮筋此前本就是 GPCanvasOverlay 最后绘制的内容。此钩子自 P2 起即已声明，但从未接线。
	gpInputRouter.gpActiveTool().gpDrawOverlay(self)
	# Endpoint anchors sit on top of everything: they are the smallest, most precise targets on
	# the sheet and must never be hidden behind a rubber band or a pipe.
	# 端点锚点位于最上层：它们是图纸上最小、最需要精确点中的目标，绝不能被橡皮筋或管线遮住。
	if gpPortOps != null:
		gpPortOps.gpDrawPorts(self)


# The background overlay paint (grid / shapes / grips / marquee / connect-preview) now lives in
# GPCanvasOverlay — this Control only triggers gpSymbolLayer.gpSyncViews() then delegates to it in _draw().
# 背景覆盖层绘制（网格 / 图形 / 抓取点 / 框选 / 连线预览）现位于 GPCanvasOverlay——
# 本 Control 仅先触发 gpSymbolLayer.gpSyncViews() 再在 _draw() 中委托给它。


func gpRefreshSymbolViews() -> void:
	gpSymbolLayer.gpRefreshSymbolViews()


# Repaint everything whose appearance is baked from the camera scale: the symbol views, the edge
# views and the sheet frame. Call this from every code path that CHANGES THE ZOOM.
# 重绘一切「外观由相机缩放烘焙而成」之物：图元视图、连线视图与图幅图框。凡**改变缩放**的代码路径
# 都必须调用本方法。
# WHY IT IS NOT PART OF gpApplyCamera() / 为何不并入 gpApplyCamera()：
# Panning calls gpApplyCamera() on every mouse move and does not change the scale, so folding this in
# would re-rasterise the whole drawing's text for nothing. Zoom changes are rare and must pay for it.
# 平移在每次鼠标移动时都会调用 gpApplyCamera()，而它并不改变缩放；若并入其中，就会白白为整幅图
# 的文字重新光栅化。缩放变化很少，应当由它承担这个代价。
# WHY A PARENT queue_redraw() IS NOT ENOUGH / 为何父节点的 queue_redraw() 不够：
# The font size is chosen from the live scale inside each view's _draw(), and a parent's redraw never
# cascades to child CanvasItems — the same trap already documented on GPCanvasSymbolLayer. Without
# this call a zoom leaves the glyphs at the previous zoom's raster and magnifies them, which is
# exactly the blur this sizing scheme exists to remove.
# 字号由各视图 _draw() 内的实时缩放选定，而父节点的重绘不会级联到子 CanvasItem —— 与
# GPCanvasSymbolLayer 上已记载的陷阱相同。缺此调用，缩放后字形会停留在上一次缩放的密度上并被放大，
# 正是本字号方案所要消除的那种发虚。
func gpOnCameraChanged() -> void:
	if gpSymbolLayer != null:
		gpRefreshSymbolViews()
	if gpFrame != null:
		gpFrame.gpRefresh()
	queue_redraw()


func gpNodeCenter(gpId: String) -> Vector2:
	return gpSymbolLayer.gpNodeCenter(gpId)

func gpNodeRect(gpId: String) -> Rect2:
	return gpSymbolLayer.gpNodeRect(gpId)

func gpHitTest(gpWorld: Vector2) -> String:
	return gpSymbolLayer.gpHitTest(gpWorld)


func _gui_input(gpEvent: InputEvent) -> void:
	gpInputRouter.gpOnGuiInput(gpEvent)


func _gpOnLeftDown(gpScreen: Vector2, gpShift: bool, gpDouble: bool) -> void:
	gpInputRouter.gpOnLeftDown(gpScreen, gpShift, gpDouble)


func _gpActiveTool() -> GPCanvasTool:
	return gpInputRouter.gpActiveTool()

# _gpDrawShapes() / _gpDrawOneShape() moved to GPCanvasOverlay . They are invoked through
# _gpOverlay.gpDraw() from _draw(), so the canvas no longer paints the overlay itself.
# _gpDrawShapes() / _gpDrawOneShape() 已移至 GPCanvasOverlay，经 _draw() 中的
# _gpOverlay.gpDraw() 调用，画布不再自行绘制覆盖层。


func gpHitShape(gpWorld: Vector2) -> int:
	return gpSymbolLayer.gpHitShape(gpWorld)

func gpSetSelection(gpIds: Array[String]) -> void:
	gpEditFacade.gpSetSelection(gpIds)


func gpRequestSelectAll() -> void:
	gpEditFacade.gpRequestSelectAll()


func gpSetEdgeSelection(gpIds: Array[String]) -> void:
	gpEditFacade.gpSetEdgeSelection(gpIds)


func gpRequestDeleteSelected() -> void:
	gpEditFacade.gpRequestDeleteSelected()


func gpUndo() -> bool:
	return gpEditFacade.gpUndo()


func gpRedo() -> bool:
	return gpEditFacade.gpRedo()


func gpCanUndo() -> bool:
	return gpEditFacade.gpCanUndo()


func gpCanRedo() -> bool:
	return gpEditFacade.gpCanRedo()


func gpRequestDuplicateSelected() -> void:
	gpEditFacade.gpRequestDuplicateSelected()


# ============================ 编辑意图端口 ============================
# ============================ edit intent ports ============================
# Every user edit that changes the model goes through one of these ports. The canvas adds
# nothing to them: GPEditService turns the intent into a command, records it, and mutates
# 每一项改动模型的用户编辑都经这些端口之一。画布不附加任何逻辑：GPEditService 把意图变成
# 命令、记录它并改动模型；视图经 GPPIDGraph.gpGraphChanged（已在 M2 桥接）自动跟随。

func gpRequestPlaceNode(gpSymbolId: String, gpWorld: Vector2) -> String:
	return gpEditFacade.gpRequestPlaceNode(gpSymbolId, gpWorld)


func gpRequestConnect(gpFromId: String, gpToId: String) -> bool:
	return gpEditFacade.gpRequestConnect(gpFromId, gpToId)


func gpRequestAddShape(gpShape: GPShape) -> int:
	return gpEditFacade.gpRequestAddShape(gpShape)


func gpRequestMoveNodes(gpNodeIds: Array[String], gpDelta: Vector2) -> bool:
	return gpEditFacade.gpRequestMoveNodes(gpNodeIds, gpDelta)


# Commit absolute node positions as one undo step (collision-avoidance push during place/drag).
# 一步提交节点绝对位置（放置 / 拖拽时的碰撞避让推送）。
func gpRequestSetNodePositions(gpTargets: Dictionary) -> bool:
	return gpEditFacade.gpRequestSetNodePositions(gpTargets)


func gpCancelActiveTool() -> bool:
	return gpInputRouter.gpCancelActiveTool()


# ============================ P3 连线意图端口 ============================
# ============================ P3 edge intent ports ============================
# The pipe / signal tools and the edge editor reach the model only through these. As with the
# node ports above, the canvas adds nothing: GPEditService turns the intent into a command.
# 管道 / 信号线工具与连线编辑器只经这些端口触达模型。与上面的节点端口一样，画布不附加逻辑：
# GPEditService 把意图变成命令。

func gpDefLookupCallable() -> Callable:
	return gpSymbolLayer.gpDefLookupCallable()


func _gpDefLookup(gpSymbolId: String) -> GPSymbolDef:
	return gpSymbolLayer.gpDefLookup(gpSymbolId)


func gpRequestSetLabelOffset(gpNodeId: String, gpOffset: Vector2) -> bool:
	return gpEditFacade.gpRequestSetLabelOffset(gpNodeId, gpOffset)


func gpRequestSetEdgeTagOffset(gpEdgeId: String, gpOffset: Vector2) -> bool:
	return gpEditFacade.gpRequestSetEdgeTagOffset(gpEdgeId, gpOffset)


func gpDefFor(gpSymbolId: String) -> GPSymbolDef:
	return gpSymbolLayer.gpDefFor(gpSymbolId)


func gpRequestConnectEdge(gpFromRef: Dictionary, gpToRef: Dictionary, gpKind: String,
		gpSignalType: String = "", gpOrtho: bool = true) -> String:
	return gpEditFacade.gpRequestConnectEdge(gpFromRef, gpToRef, gpKind, gpSignalType, gpOrtho)


func gpRequestDeleteEdges(gpEdgeIds: Array[String]) -> bool:
	return gpEditFacade.gpRequestDeleteEdges(gpEdgeIds)


func gpRequestSetEdgeTag(gpEdgeId: String, gpTag: String) -> bool:
	return gpEditFacade.gpRequestSetEdgeTag(gpEdgeId, gpTag)


func gpRequestReconnectEdge(gpEdgeId: String, gpIsFrom: bool, gpNewRef: Dictionary) -> bool:
	return gpEditFacade.gpRequestReconnectEdge(gpEdgeId, gpIsFrom, gpNewRef)


func gpRequestSetEdgeRouting(gpEdgeId: String, gpRouting: Array[Vector2]) -> bool:
	return gpEditFacade.gpRequestSetEdgeRouting(gpEdgeId, gpRouting)


# Record a drop-on-edge restore entry as its own undo step (Feature 2: delete restores the line).
# 把「落点恢复记录」作为独立撤销步写入（功能 2：删除还原连线）。
func gpRequestRecordDrop(gpSymNid: String, gpRecord: Dictionary) -> void:
	gpEditFacade.gpRequestRecordDrop(gpSymNid, gpRecord)


func gpClearPortPick() -> void:
	gpEditFacade.gpClearPortPick()


func gpRequestAutoConnect() -> String:
	return gpEditFacade.gpRequestAutoConnect()


func gpHitEdge(gpWorld: Vector2) -> String:
	return gpSymbolLayer.gpHitEdge(gpWorld)


func gpReportRefusal(gpKey: String) -> void:
	gpEditFacade.gpReportRefusal(gpKey)


# ============================ context menu ============================


func gpDeleteSelection() -> void:
	gpEditFacade.gpDeleteSelection()


func gpClearSelection() -> void:
	gpInputRouter.gpClearSelection()


func gpZoomStep(gpFactor: float) -> void:
	gpViewController.gpZoomStep(gpFactor)


# Public read port: a consistent snapshot of the canvas interaction state for tools / external
# consumers. Replaces ad-hoc peeking at private fields with one stable call.
# 公开只读端口：对外暴露画布交互状态的一致快照，取代对各私有字段的零散窥探。
# part of the canvas port API (gpRequest* / gpSnapshot()).
# 画布端口 API 的一部分（gpRequest* / gpSnapshot()）。
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


func gpResetView() -> void:
	gpViewController.gpResetView()


# Clean up cached references when the canvas leaves the tree.
# 画布离开场景树时清理缓存引用。
func _notification(gpWhat: int) -> void:
	if gpWhat == NOTIFICATION_PREDELETE:
		if gpBinder != null:
			gpBinder.gpClear()
