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

# Per-sheet tag uniqueness guard (M9). The canvas owns it because the canvas is the one that
# places and duplicates instances; it rebinds to the graph's rules on every document swap, so
# the sequence marks stay the ones the file serialises.
# 每图纸的位号唯一性守卫（M9）。由画布持有，因为正是画布放置与复制实例；
# 每次切换文档时它都会重新绑定到图的规则上，使序号水位线始终是文件会序列化的那一份。
var gpTags: GPTagRegistry = GPTagRegistry.new()

# Tag (位号) label grip / drag delegate (M10b). Mirrors gpEdgeGrips: the transient drag state
# lives here, not on the canvas.
# 位号标签抓取点 / 拖拽委托（M10b）。与 gpEdgeGrips 同形：瞬态拖拽状态存于此，不在画布上。
var gpLabelGrips: GPLabelGripOps = null

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

# ---- 架构优化 §3.4：四个实现类（1 root + 4 impl，非破坏性） ----
# ---- Architecture §3.4: the four implementation classes (1 root + 4 impl, non-breaking) ----
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

# Edge line-number editor delegate (P3-4): a floating LineEdit opened by double-clicking an edge,
# committing through the command layer as one undo step. Created in _ready() with this canvas.
# 边管线号编辑器委托（P3-4）：双击边时打开的浮层 LineEdit，经命令层以一个撤销步提交。在 _ready() 中以
# 本画布创建。
var gpEdgeEditor: GPEdgeTagEditor = null

# Edge grip / route editing delegate (P3-4): drag an endpoint to reconnect or a vertex to re-route,
# each commit going through the command layer as one undo step. Created in _ready() with this canvas.
# 边抓取点 / 布线编辑委托（P3-4）：拖端点改接或拖顶点改布线，每次提交经命令层成为一个撤销步。
# 在 _ready() 中以本画布创建。
var gpEdgeGrips: GPEdgeGripOps = null

# Endpoint (anchor) highlight / pick / drag-to-connect delegate. Mirrors gpEdgeGrips: the
# transient port state never lands on the canvas.
# 端点（锚点）高亮 / 拾取 / 拖拽连线委托。与 gpEdgeGrips 同形：瞬态端点状态从不落在画布上。
var gpPortOps: GPPortConnectOps = null

# 架构优化 §3.4：右键菜单委托、快捷键委托、工具注册表与六个模式工具已随「输入路由」迁出，
# 现由 GPCanvasInputRouter（gpInputRouter.gpBuildTools()）持有 —— 它们只被输入分派使用。
# Architecture §3.4: the context-menu delegate, the shortcut delegate, the tool registry and the
# six mode tools moved out with the input router; only input dispatch ever touches them.

# Id counter for new nodes/edges — proxy to state.gpIds (GPIdGen). / 新节点/边 id 计数器 —— 代理 state.gpIds。
var gpNextId: int:
	get: return _gpState.gpIds.gpCounter
	set(gpV): _gpState.gpIds.gpCounter = gpV

# M0（架构优化 §3.4 前置）：_gpSetNodePos 是死代码（只声明、从未被调用），已删除而非搬迁；
# 节点移动统一走 GPEditService.gpMoveNodes。
# M0 (architecture §3.4 prep): _gpSetNodePos was dead code — declared, never called — so it was
# deleted rather than moved; node moves go through GPEditService.gpMoveNodes.

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


# 架构优化 §3.4：中键平移的瞬态状态（_gpPanning / _gpPanStart / _gpPanOffsetStart）已迁入
# GPCanvasInputRouter —— 它由输入事件驱动，只被输入路由消费。
# Architecture §3.4: middle-button pan transient state moved into GPCanvasInputRouter.


# Indices of the currently selected annotation shapes (mirror of gpSelection for the node layer).
# 当前选中注释图形的下标（与图元层的 gpSelection 对应的镜像）。
var gpShapeSel: Array[int] = []

# Selected edge ids (P3). Kept as a plain array next to gpShapeSel: an edge selection and a node
# selection are mutually exclusive in practice, and a proxy into GPCanvasSelection would force the
# node/shape/edge three-way rule into that class before it is understood.
# 选中的边 id（P3）。与 gpShapeSel 并列保持为普通数组：边选择与节点选择在实践上互斥，
# 而代理进 GPCanvasSelection 会迫使「节点/图形/边」三方互斥规则提前进入那个类。
var gpEdgeSel: Array[String] = []

# Anchor currently under the cursor (""-keyed empty dictionary when none). Written by
# GPPortConnectOps so the hover highlight and the pick logic share one owner.
# 光标下当前的锚点（无则为空字典）。由 GPPortConnectOps 写入，使悬停高亮与拾取逻辑共用一个持有者。
var gpHoverPort: Dictionary = {}

# The two endpoints picked for "auto-connect" (in click order, at most two).
# 为「自动连线」拾取的两个端点（按点击顺序，最多两个）。
var gpPortPick: Array[Dictionary] = []

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




# 架构优化 §3.4：四个实现类在**构造期**装配，而非只在 _ready 中。
# 画布常在脱离场景树的情况下被使用（headless 回归检查器直接 GPCanvas2D.new() 后调用其
# 公开端口），那时 _ready 永不触发 —— 若协调者只在 _ready 里创建，转发壳会打到 null 上。
# Architecture §3.4: the four implementation classes are assembled in _init, not only in
# _ready. A canvas is routinely used outside the scene tree (headless regression checkers
# call GPCanvas2D.new() and then its public ports), where _ready never fires; creating the
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
	# Keyboard shortcuts (Delete / Ctrl+A / ESC) arrive through gpInputRouter.gpOnGuiInput, which requires focus.
	# 键盘快捷键（Delete / Ctrl+A / ESC）经 gpInputRouter.gpOnGuiInput 送达，而这需要焦点。
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
	# Create the edge editing delegates (P3-4), owner = this canvas. They are reached by the
	# select tool through gpCtx (mirroring gpAnno), so transient edge-edit state never lives here.
	# 创建边编辑委托（P3-4），状态持有者为本画布。选择工具经 gpCtx 访问它们（与 gpAnno 同形），
	# 故边的瞬态编辑状态不落在本画布上。
	gpEdgeEditor = GPEdgeTagEditor.new(self)
	gpEdgeGrips = GPEdgeGripOps.new(self)
	# M10b: the tag label gets the same grip treatment as an edge vertex.
	# M10b：位号标签获得与边拐点相同的抓取点待遇。
	gpLabelGrips = GPLabelGripOps.new(self)
	# Endpoint-anchor interaction delegate (highlight / pick / drag-to-connect).
	# 端点锚点交互委托（高亮 / 拾取 / 拖拽连线）。
	gpPortOps = GPPortConnectOps.new(self)
	# 架构优化 §3.4：右键菜单委托、快捷键委托、工具注册表与六个模式工具由输入路由自建。
	# Architecture §3.4: the input router builds its context-menu delegate, shortcut delegate,
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
		_gpSettings.gpPipeTagStyleChanged.connect(gpSymbolLayer.gpRefreshEdges)
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
	gpViewController.gpResetCamera()


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
	# M9: hand the tag registry to the service so placement and duplication mint unique tags.
	# gpBindGraph re-derives the index from the graph, so a document edited before M9 starts
	# from the truth rather than an empty cache.
	# M9：把位号注册器交给编辑服务，使放置与复制能铸造唯一位号。
	# gpBindGraph 会从图重新推导索引，故 M9 之前编辑过的文档从真相出发而非空缓存。
	gpActions.gpBindGraph(_gpGraphRef, _gpState.gpIds, gpTags)


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
	gpSymbolLayer.gpRefreshSymbols()


# React to symbol font/style change by refreshing symbol labels.
# 图元字体/样式变化时刷新图元标签。
func _gpOnSymbolStyleChanged() -> void:
	gpSymbolLayer.gpRefreshSymbols()


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


func _gpResetView() -> void:
	gpViewController.gpResetCamera()


func _gpApplyCamera() -> void:
	gpViewController.gpApplyCamera()


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
	# The background overlay paint is delegated to GPCanvasOverlay (P2 split) — same math,
	# same draw order, so the visual result is byte-for-byte identical.
	# 背景覆盖层绘制委托给 GPCanvasOverlay（P2 拆分）——同一套数学、同一绘制顺序，观感完全一致。
	_gpOverlay.gpDraw()
	# M3: the active tool paints its OWN transient visuals (draw rubber band, in-progress polyline)
	# after the shared overlay, preserving the previous z-order — the band was already the last
	# thing GPCanvasOverlay drew. The hook existed since P2 but was never wired.
	# M3：活动工具在共享覆盖层之后绘制「自己的」瞬态视觉（绘图橡皮筋、进行中的折线），沿用原有
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


func _gpSyncViews() -> void:
	gpSymbolLayer.gpSyncViews()




func _gpRefreshSymbols() -> void:
	gpSymbolLayer.gpRefreshSymbols()


func gpRefreshSymbolViews() -> void:
	gpSymbolLayer.gpRefreshSymbolViews()


func gpNodeCenter(gpId: String) -> Vector2:
	return gpSymbolLayer.gpNodeCenter(gpId)

func gpNodeRect(gpId: String) -> Rect2:
	return gpSymbolLayer.gpNodeRect(gpId)

func gpHitTest(gpWorld: Vector2) -> String:
	return gpSymbolLayer.gpHitTest(gpWorld)


func _gui_input(gpEvent: InputEvent) -> void:
	gpInputRouter.gpOnGuiInput(gpEvent)


func _gpRefreshEdges() -> void:
	gpSymbolLayer.gpRefreshEdges()


func _gpOnLeftDown(gpScreen: Vector2, gpShift: bool, gpDouble: bool) -> void:
	gpInputRouter.gpOnLeftDown(gpScreen, gpShift, gpDouble)


func _gpActiveTool() -> GPCanvasTool:
	return gpInputRouter.gpActiveTool()

func _gpOnLeftUp(gpScreen: Vector2) -> void:
	gpInputRouter.gpOnLeftUp(gpScreen)






# _gpDrawShapes / _gpDrawOneShape moved to GPCanvasOverlay (P2 split). They are invoked through
# _gpOverlay.gpDraw() from _draw(), so the canvas no longer paints the overlay itself.
# _gpDrawShapes / _gpDrawOneShape 已移至 GPCanvasOverlay（P2 拆分），经 _draw() 中的
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


func _gpPruneSelection() -> void:
	gpEditFacade.gpPruneSelection()


func gpRequestDuplicateSelected() -> void:
	gpEditFacade.gpRequestDuplicateSelected()


# ============================ 编辑意图端口（M4 续） ============================
# ============================ edit intent ports (M4 cont) ============================
# Every user edit that changes the model goes through one of these ports. The canvas adds
# nothing to them: GPEditService turns the intent into a command, records it, and mutates
# the model. The view follows via GPPIDGraph.gpGraphChanged, already bridged (M2).
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


func gpClearPortPick() -> void:
	gpEditFacade.gpClearPortPick()


func gpRequestAutoConnect() -> String:
	return gpEditFacade.gpRequestAutoConnect()


func gpHitEdge(gpWorld: Vector2) -> String:
	return gpSymbolLayer.gpHitEdge(gpWorld)


func gpReportRefusal(gpKey: String) -> void:
	gpEditFacade.gpReportRefusal(gpKey)


# ============================ context menu ============================


func _gpZoomAt(gpScreen: Vector2, gpFactor: float) -> void:
	gpViewController.gpZoomAt(gpScreen, gpFactor)


func gpDeleteSelection() -> void:
	gpEditFacade.gpDeleteSelection()


func gpClearSelection() -> void:
	gpInputRouter.gpClearSelection()


func gpZoomStep(gpFactor: float) -> void:
	gpViewController.gpZoomStep(gpFactor)


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


func gpResetView() -> void:
	gpViewController.gpResetView()


# Clean up cached references when the canvas leaves the tree.
# 画布离开场景树时清理缓存引用。
func _notification(gpWhat: int) -> void:
	if gpWhat == NOTIFICATION_PREDELETE:
		if gpBinder != null:
			gpBinder.gpClear()
