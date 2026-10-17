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

@warning_ignore("unused_signal")
# Emitted when the user double-clicks the TITLE BLOCK: the host opens the existing frame /
# title-block dialog (the same entry the menu uses). The block has no in-place editor — its
# 13 fields live in the dialog — so a double click opening that dialog is the smallest honest
# answer to "I cannot edit the block" (2026-10-16 user report).
# 用户**双击图签**时发出：宿主打开既有的图框 / 图签对话框（与菜单同一入口）。图签没有就地编辑
# 器 —— 它的 13 个字段都在对话框里 —— 故「双击打开该对话框」是对「图签改不了」（2026-10-16 用户
# 报告）的最小且诚实的回答。
signal gpTitleBlockEditRequested()

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

# Drawing-frame (图框) grab / drag delegate . Rev.3 stage 0c: the frame's four lines form a grab
# band, and its four side midpoints are resize handles. Mirrors gpLabelGrips — the transient drag
# state lives here, and the COMMIT travels through the command layer as one undo step.
# 图框抓取 / 拖拽委托。Rev.3 阶段 0c：图框的四条线构成抓取带，四边中点为改尺寸手柄。与
# gpLabelGrips 同形 —— 瞬态拖拽状态存于此，而**提交**经命令层作为**一个**撤销步。
var gpFrameGrips: GPFrameGripOps = null

# Title-block (图签) grab / drag delegate . Rev.3 stage 1: the block is an object with its own extent, so
# its WHOLE area is the target (there is no "click anywhere" ambiguity to remove, unlike the frame).
# Mirrors gpFrameGrips in shape and in one more respect — this is the second, and so far last, interaction
# whose COMMIT writes a SHEET rather than the graph.
# 图签抓取 / 拖拽委托。Rev.3 阶段 1：图签是一个有自身范围的对象，故它**整块**都是目标（与图框不同，这里没有
# 「点哪都选中」的歧义要消除）。形态与 gpFrameGrips 同，还有一点也相同 —— 这是第二个、也是目前最后一个
# **提交**写的是**图纸**而非图的交互。
var gpTitleBlockGrips: GPTitleBlockGripOps = null

# Grid-table column-boundary drag delegate. Stage 3 S4: a press on a single-selected table's
# internal vertical separator drags the widths of the two columns it separates. Mirrors
# gpFrameGrips — transient drag state lives here, the COMMIT travels through the command
# layer as one undo step (a graph write, unlike the title block's sheet write).
# grid 表格列边界拖拽委托。阶段 3 S4：在**单选**表格的内部竖向分隔线上按下，即拖动其两侧
# 两列的宽度。与 gpFrameGrips 同形 —— 瞬态拖拽状态存于此，**提交**经命令层作为**一个**撤销步
#（写的是图，不同于图签写的图纸）。
var gpTableGrips: GPTableGripOps = null

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

# Node tag in-place editor delegate (Rev.3 stage 1.5, R1): a floating LineEdit opened by
# double-clicking a node's LABEL TEXT, committing through the command layer as one undo step.
# Created in _ready() with this canvas, mirroring gpEdgeEditor.
# 图元位号就地编辑器委托（Rev.3 阶段 1.5，R1）：双击图元**标签文字**时打开的浮层 LineEdit，
# 经命令层以一个撤销步提交。在 _ready() 中以本画布创建，与 gpEdgeEditor 同形。
var gpNodeEditor: GPNodeTextEditor = null

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
# Sheet rendering coordinator: owns the sheet itself plus its frame and background renderers.
# See sheet_layer.gd — the root keeps only assembly and forwarding for this use case.
# 图纸渲染协调者：持有图纸本体及其图框、背景渲染器。见 sheet_layer.gd ——
# 根类对本用例只保留装配与转发。
var gpSheetLayer: GPCanvasSheetLayer = null

# Forwarding property for the sheet. The sheet lives on the sheet layer, but outside callers
# (e.g. GPCanvasViewController) read gpHost.gpSheet, so the root must keep this port.
# 图纸的转发属性。图纸实体存放在图纸层，但外部调用方（如 GPCanvasViewController）会读
# gpHost.gpSheet，故根类必须保留此端口。
var gpSheet: GPSheet:
	get:
		return gpSheetLayer.gpSheet if gpSheetLayer != null else null
	set(gpValue):
		gpSetSheet(gpValue)

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

# Pending ATTACH interaction (规划 §15). Proxy into the pure state object so a headless test can arm
# it without a Control. Empty dictionary = idle; see GPCanvasInteractState for the keys.
# 待处理的**挂载**交互（规划 §15）。代理进纯状态对象，使 headless 测试无需 Control 即可上膛。
# 空字典 = 空闲；键的含义见 GPCanvasInteractState。
var gpPendingAttach: Dictionary:
	get: return _gpState.gpPendingAttach
	set(gpV): _gpState.gpPendingAttach = gpV

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
	gpSheetLayer = GPCanvasSheetLayer.new()
	gpSheetLayer.gpHost = self


# Initialize the canvas: create world root and connect global signals.
# 初始化画布：创建世界根节点并连接全局信号。
func _ready() -> void:
	# Assembly order is load-bearing: configure the Control first, then the world root every child
	# hangs from, then the layers and delegates that draw into it, and the graph / autoload wiring
	# LAST because those callbacks can fire the moment they are connected.
	# 装配顺序是有意义的：先配置控件自身，再建所有子节点的挂点 world_root，
	# 然后是绘制到它上面的各层与委托；图 / 自动加载的接线放最后 —— 因为那些回调一连接就可能触发。
	_gpSetupControl()
	_gpBuildWorldRoot()
	_gpBuildSheetLayer()
	_gpBuildBinder()
	_gpBuildDelegates()
	_gpBuildInputTools()
	_gpSubscribeAutoloads()
	_gpWireGraphSignals()
	_gpArmFit()


# Own Control settings: input, clipping, focus and text rasterisation.
# 本控件的自身设置：输入、裁剪、焦点与文字光栅化。
func _gpSetupControl() -> void:
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


# The world root: every symbol / edge view hangs here so they share one transform.
# 世界根节点：所有图元 / 连线视图都挂在此处，共享同一变换。
func _gpBuildWorldRoot() -> void:
	gpWorldRoot = Node2D.new()
	gpWorldRoot.name = "WorldRoot"
	add_child(gpWorldRoot)
	gpWorldRoot.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED


# Build the frame + background through the sheet layer, then replay the sheet binding.
# 经图纸层构建图框与背景，再重放图纸绑定。
func _gpBuildSheetLayer() -> void:
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
	# Frame and background are built by the sheet layer, background FIRST — both use z_index 0,
	# so stacking depends entirely on child order (see sheet_layer.gd header).
	# 图框与背景由图纸层构建，**背景在前** —— 二者均用 z_index 0，
	# 层叠完全依赖子节点顺序（见 sheet_layer.gd 文件头）。
	gpSheetLayer.gpBuild(gpWorldRoot)
	# Re-apply the sheet NOW that the frame renderer exists. The host binds the sheet through
	# gpSetSheet() BEFORE this Control is added to the tree (center_area builds the canvas, binds
	# the sheet, then adds the canvas), so at that moment the frame is still null and the assignment
	# is swallowed — which is exactly why no frame was ever drawn. Replaying it here is idempotent
	# and covers every ordering.
	# 在渲染器存在后立刻重申图纸。宿主经 gpSetSheet() 绑定图纸的时机早于本控件入树
	#（center_area 先建画布、绑图纸、再把画布入树），当时图框仍为 null，赋值被吞 —— 这正是
	# 图框从未画出的原因。此处重放是幂等的，可覆盖任何装配顺序。
	gpSetSheet(gpSheet)


# The graph binder plus the render-style snapshot it consumes.
# 图绑定器，以及它消费的渲染样式快照。
func _gpBuildBinder() -> void:
	# Create the graph binder that owns view-sync logic and caches.
	# 创建持有视图同步逻辑与缓存的图绑定器。
	gpBinder = GPGraphBinder.new()
	gpBinder.name = "GraphBinder"
	add_child(gpBinder)
	gpBinder.gpWorldRoot = gpWorldRoot
	# Build the render-style snapshot and inject it so the render layer stays autoload-free;
	# locale / font / pipe-tag changes rebuild + re-push it (see _gpSubscribeAutoloads()).
	# 构造渲染样式快照并注入绑定器，使 render 层不读 autoload；
	# 语言 / 字号 / 位号样式变化会重建并显式重推（见 _gpSubscribeAutoloads()）。
	gpRenderStyle = gpBuildRenderStyle()
	gpBinder.gpStyle = gpRenderStyle


# Editing delegates. They own their own transient state, which is why the canvas stays thin.
# 各编辑委托。它们各自持有自己的瞬态状态，这正是画布能保持轻薄的原因。
func _gpBuildDelegates() -> void:
	# Create the drawing delegate. It borrows this Control as its CanvasItem.
	# 创建绘制委托。它以本 Control 作为绘制目标 CanvasItem。
	_gpOverlay = GPCanvasOverlay.new(self)
	# Create the annotation-shape editing delegate, owner = this canvas.
	# 创建注释图形编辑委托，状态持有者为本画布。
	gpAnno = GPAnnotationEditor.new(self)
	# Create the edge editing delegates, owner = this canvas. They are reached by the
	# select tool through gpCtx (mirroring gpAnno), so transient edge-edit state never lives here.
	# 创建边编辑委托，状态持有者为本画布。选择工具经 gpCtx 访问它们（与 gpAnno 同形），
	# 故边的瞬态编辑状态不落在本画布上。
	gpEdgeEditor = GPEdgeTagEditor.new(self)
	# Node tag in-place editor (Rev.3 stage 1.5, R1). Same delegate shape as the edge's editor.
	# 图元位号就地编辑器（Rev.3 阶段 1.5，R1）。与边编辑器同一委托形态。
	gpNodeEditor = GPNodeTextEditor.new(self)
	gpEdgeGrips = GPEdgeGripOps.new(self)
	# The tag label gets the same grip treatment as an edge vertex.
	# 位号标签获得与边拐点相同的抓取点待遇。
	gpLabelGrips = GPLabelGripOps.new(self)
	# Edge line-number grip: the pipe's number is itself draggable, with a leader line drawn
	# back to the pipe when dragged far enough. / 边管线号抓取点：管线编号可拖动，拖远时画引出线。
	gpEdgeTagGrips = GPEdgeTagGripOps.new(self)
	# Drawing-frame grab band / side handles (Rev.3 stage 0c). Same shape as the grips above; its
	# COMMIT is the only one that has to reach the command layer with a SHEET rather than a graph.
	# 图框抓取带 / 侧手柄（Rev.3 阶段 0c）。与上方各抓取点同形；唯它的**提交**必须携带**图纸**
	# 而非图进入命令层。
	gpFrameGrips = GPFrameGripOps.new(self)
	# Title-block whole-block drag (Rev.3 stage 1). Built after the frame's grips because the press chain
	# tests it FIRST — the two targets overlap along the frame's bottom-right corner (see the class header).
	# 图签整块拖拽（Rev.3 阶段 1）。在图框抓取之后构造，因为按下链**先**测它 —— 两个目标沿图框右下角
	# 重叠（见该类文件头）。
	gpTitleBlockGrips = GPTitleBlockGripOps.new(self)
	# Grid-table column-boundary drag (stage 3 S4). Built last among the delegates: its press
	# probe runs INSIDE the node-hit branch (the separator sits on the table's body), after
	# the sheet furniture above.
	# grid 表格列边界拖拽（阶段 3 S4）。在各委托中最后构造：它的按下探测跑在**图元命中分支内**
	#（分隔线就在表格本体上），位于上方各图纸陈设之后。
	gpTableGrips = GPTableGripOps.new(self)
	# Endpoint-anchor interaction delegate (highlight / pick / drag-to-connect).
	# 端点锚点交互委托（高亮 / 拾取 / 拖拽连线）。
	gpPortOps = GPPortConnectOps.new(self)


# The input router builds its context-menu delegate, shortcut delegate, tool registry and the
# mode tools — they are input-dispatch implementation details and stay out of the canvas.
# 输入路由自建右键菜单委托、快捷键委托、工具注册表与模式工具 ——
# 它们属于输入派发的实现细节，不落在画布上。
func _gpBuildInputTools() -> void:
	gpInputRouter.gpBuildTools()


# Subscribe to locale / font / pipe-tag changes so symbol labels stay in sync.
# 订阅语言、字体与位号样式变化，保持图元文字同步。
func _gpSubscribeAutoloads() -> void:
	# Headless-resilient guard: `I18n` / `Settings` are autoloads and are NOT present when the
	# canvas is exercised outside the live app (e.g. `--script` regression checkers). Skip the
	# connection when the singleton is absent — the real app always has them, so behavior is
	# identical there. This is what lets the tool layer be validated headlessly without a GUI.
	# 无界面容错护栏：I18n / Settings 是自动加载单例，在画布脱离活动现场运行（如 `--script` 回归检查
	# 器）时并不存在。单例缺失时跳过连接——真实应用永远具备它们，故行为零变更。正是这一步让工具
	# 层可在无 GUI 环境下 headless 校验。
	var _gpI18n: Object = get_node_or_null("/root/I18n")
	if _gpI18n != null and _gpI18n.has_signal("gpLocaleChanged"):
		_gpI18n.gpLocaleChanged.connect(_gpOnLocaleChanged)
	var _gpSettings: Object = get_node_or_null("/root/Settings")
	if _gpSettings != null and _gpSettings.has_signal("gpSymbolStyleChanged"):
		_gpSettings.gpSymbolStyleChanged.connect(_gpOnSymbolStyleChanged)
	if _gpSettings != null and _gpSettings.has_signal("gpPipeTagStyleChanged"):
		_gpSettings.gpPipeTagStyleChanged.connect(_gpOnTagStyleChanged)


# Funnel the core graph's raw signal onto the document bus; the graph itself does not emit it.
# 把 core 图的原始信号引入文档总线；图自身并不发射该总线信号。
func _gpWireGraphSignals() -> void:
	# The core GPPIDGraph emits a raw signal; the canvas is the single place that maps it onto the
	# bus. The funnel stays here — the graph does not emit the bus itself.
	# core 的 GPPIDGraph 发射的是原始信号；画布是把它映射到总线的唯一位置。
	# 漏斗保留在此 —— 图本身不发射总线。
	gpGraphChanged.connect(_gpForwardGraphChanged)
	# Re-assert the core-graph binding (idempotent; covers a graph assigned before _ready()).
	# 重申 core 图绑定（幂等，覆盖在 _ready() 之前就被赋值的图）。
	if _gpGraphRef != null and not _gpGraphRef.gpGraphChanged.is_connected(_gpOnGraphDataChanged):
		_gpGraphRef.gpGraphChanged.connect(_gpOnGraphDataChanged)


# Fit the sheet ONCE, as soon as the control has a real size.
# 在控件获得真实尺寸后**一次性**适配图幅。
func _gpArmFit() -> void:
	# _ready() usually runs while the host is still positioning this Control (size 0), and
	# gpResetCamera() would then place the world origin at the top-left corner — the drawing would
	# start off half off-screen. The resized signal covers the case where the size arrives later;
	# the flag makes it a one-shot so the user's own pan/zoom is never fought afterwards.
	# _ready() 执行时宿主往往仍在摆放本控件（尺寸为 0），
	# 此时 gpResetCamera() 会把世界原点放到左上角 —— 图纸一开始就偏出屏外。resized 信号覆盖
	# 「尺寸稍后才到」的情形；标志位保证只做一次，之后绝不与用户自己的平移/缩放争夺视图。
	resized.connect(_gpOnCanvasResized)
	_gpFitIfReady()


# Fit the sheet into the viewport once the control has a measurable size (one-shot).
# 控件尺寸可测后把图幅适配进视口（仅一次）。
func _gpFitIfReady() -> void:
	# Delegated to the sheet layer; the size is passed in because that coordinator is a
	# RefCounted and cannot read Control.size itself.
	# 委托图纸层执行；尺寸由参数传入，因该协调者是 RefCounted，无法自行读取 Control.size。
	gpSheetLayer.gpFitIfReady(size)


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
	gpSheetLayer.gpSetSheet(gpValue)


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
	# Stage 3 S4 fix: a parent's queue_redraw() does NOT cascade to child CanvasItems (the
	# trap GPCanvasSymbolLayer's header documents), and the binder's rebind-repaint guard is
	# reference-based — an IN-PLACE mutation (grid-table structure op, cell text, tag edit,
	# and every command UNDO/REDO) keeps the same GPPIDNode object, so gpSync() never
	# repainted the view. The user saw "insert/delete row did nothing and text misaligned,
	# Ctrl+Z dead": the model was correct all along, only the pixels were stale — and the
	# live hit test then disagreed with the stale picture. Refresh the child views here so
	# EVERY command execute/undo/redo reaches the screen in one systemic place.
	# 阶段 3 S4 修复：父节点的 queue_redraw() **不会**级联到子 CanvasItem（GPCanvasSymbolLayer
	# 文件头已记载的陷阱），且绑定器的重绑-重绘判据是**引用相等** —— 原地变换（表格结构操作、
	# 格子文字、位号编辑，以及一切命令的撤销/重做）始终是同一个 GPPIDNode 对象，gpSync()
	# 因此从不重绘视图。用户看到的是「增删行列没反应、文字错位、Ctrl+Z 失灵」：模型一直是
	# 对的，只是像素是旧的 —— 而实时命中测试随即与陈旧画面相互矛盾。在此统一刷新子视图，
	# 使每条命令的执行/撤销/重做都经这一处系统性地到达屏幕。
	if gpSymbolLayer != null:
		gpRefreshSymbolViews()
		gpRefreshEdges()


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


# Repaint every edge view (Rev.3 stage 0d).
# 重绘每条边视图（Rev.3 阶段 0d）。
#
# WHY A CANVAS PORT AND NOT A REACH INTO gpSymbolLayer / 为何是画布端口、而不是直接伸手进 gpSymbolLayer：
# the whole-sheet drag moves every edge, so it must repaint them all — and a TOOL may only drive the host
# through its public ports (the rule GPCanvasSheetLayer's own header states). Reaching through
# `gpSymbolLayer` would make the tool depend on the layer's internal shape, which is exactly the coupling
# the 1-root + 4-impl split removed. This is the edge counterpart of gpRefreshSymbolViews().
# 整图拖拽会移动每一条边，故必须把全部边视图重绘一遍 —— 而**工具**只经宿主的公开端口驱动宿主（这是
# GPCanvasSheetLayer 自己所声明的规则）。穿透 `gpSymbolLayer` 会让工具依赖该层的内部形状，而那正是
# 「1 根 + 4 实现类」那次拆分所消除的耦合。它是 gpRefreshSymbolViews() 在边一侧的对应物。
func gpRefreshEdges() -> void:
	gpSymbolLayer.gpRefreshEdges()


# Repaint the sheet frame (and everything derived from the sheet: zone ruler, title block).
# 重绘图框（以及一切由图纸推导之物：坐标带、标题栏）。
#
# WHY THIS PORT EXISTS / 为何需要本端口：a frame DRAG writes the sheet's margins on every mouse move
# (see GPFrameGripOps.gpOnGripMove). Those writes are deliberately silent — the sheet signal fires once,
# on commit — so the drag needs a cheap repaint it can call without marking the document dirty dozens of
# times a second. This is the frame counterpart of gpRefreshSymbolViews().
# 图框**拖拽**每次鼠标移动都会写图纸边距（见 GPFrameGripOps.gpOnGripMove）。这些写入刻意保持静默 ——
# 图纸信号只在提交时发一次 —— 故拖拽需要一个廉价的、每秒调用数十次也不会把文档标脏的重绘入口。
# 它是 gpRefreshSymbolViews() 在图框一侧的对应物。
func gpRefreshSheetFrame() -> void:
	gpSheetLayer.gpRefreshFrame()


# A SHEET-level field changed (Rev.3 stage 0c): the frame margins moved, so this is a document edit.
# 图纸级字段发生变化（Rev.3 阶段 0c）：图框边距移动了，故这是一次文档编辑。
#
# It travels the DOCUMENT-CHANGED channel (gpGraphChanged -> the app bus -> the dirty flag) rather than
# a second one, because to the user "I moved the frame" and "I moved a valve" are the same fact: the
# drawing has unsaved work. The frame view is refreshed here too — a graph change never needs that,
# which is the only respect in which the two differ. The sheet layer subscribes to the sheet's signal
# and forwards here, so the ONE place that emits is the command (see GPSheet.gpSheetChanged).
# 它走**文档已变**这条通道（gpGraphChanged -> 应用总线 -> 脏标记），而不另开一条：对用户而言「我挪了图框」
# 与「我挪了阀门」是同一件事 —— 图纸有未保存的改动。此处同时刷新图框视图 —— 图变化从不需要这一步，
# 这正是二者唯一的差别。图纸层订阅图纸信号并转发到此处，故**唯一**的发射点是命令
# （见 GPSheet.gpSheetChanged）。
func gpOnSheetDataChanged() -> void:
	gpRefreshSheetFrame()
	_gpOnGraphDataChanged()


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
	gpSheetLayer.gpRefreshFrame()
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


# ============================ P2 挂载意图端口 ============================
# ============================ P2 attach intent ports ============================
# The two attach interactions of 规划 §15 reach the model only through these, plus the arming
# helpers that hand the interaction over to GPPlaceAttachTool.
# 规划 §15 的两种附件交互只经这些端口触达模型，另有把它交给 GPPlaceAttachTool 的上膛辅助。

# Arm mode 1: a library entry began being dragged. Refuses a definition that is not mountable, so a
# primary symbol can never be dropped into "attach" state (it would then have no anchor to find).
# 模式一上膛：库中某条开始被拖动。拒绝不可挂载的定义，使主图元绝不会进入「挂载」态
# （那样它将找不到任何锚点）。
func gpArmAttach(gpSymbolId: String) -> bool:
	return gpInputRouter.gpArmAttach(gpSymbolId)


# Arm mode 2 for an EXISTING node, entering the positioning drag (规划 §15.3 step 4).
# 为**既有**节点上膛模式二，进入拖动定位（规划 §15.3 第 4 步）。
func gpArmMountDrag(gpNodeId: String, gpUndoOnCancel: bool = false) -> bool:
	return gpInputRouter.gpArmMountDrag(gpNodeId, gpUndoOnCancel)


# Disarm both modes and restore the arrow cursor.
# 两种模式一并解除，并恢复箭头光标。
func gpClearPendingAttach() -> void:
	gpPendingAttach = {}
	mouse_default_cursor_shape = Control.CURSOR_ARROW


# Whether an attach interaction is armed / in flight — the toolbar and context menu use it to grey
# out entries instead of letting the user start a gesture that cannot complete.
# 是否有附件交互已上膛 / 进行中 —— 工具条与右键菜单据此置灰条目，而不是让用户开始一个无法完成的
# 手势。
func gpIsAttachPending() -> bool:
	return not gpPendingAttach.is_empty()


# Attach one child onto a host anchor (规划 §15). Returns the new node's id, "" when refused.
# 把一个子件挂到宿主锚点上（规划 §15）。返回新节点 id；被拒时返回 ""。
func gpRequestAttachNode(gpSymbolId: String, gpParentUid: String, gpAnchor: String,
		gpOffset: Vector2 = Vector2.ZERO, gpAngleDeg: float = 0.0) -> String:
	return gpEditFacade.gpRequestAttachNode(gpSymbolId, gpParentUid, gpAnchor, gpOffset, gpAngleDeg)


# Mode 2 in one call: attach, then hand the new node straight to the positioning drag. Esc during
# that drag undoes the attach, which is exactly what "I did not mean to add it" should mean.
# 模式二一调用完成：先挂载，再把新节点直接交给拖动定位。该拖拽中按 Esc 会撤销这次挂载 ——
# 这正是「我本来不想加它」应有的含义。
func gpRequestAttachAndPosition(gpSymbolId: String, gpParentUid: String, gpAnchor: String) -> String:
	var gpNid: String = gpRequestAttachNode(gpSymbolId, gpParentUid, gpAnchor)
	if gpNid != "" and not gpArmMountDrag(gpNid, true):
		# Positioning could not start (the node vanished, or it is not mounted): leave the part
		# where it landed rather than half-armed.
		# 拖动定位无法启动（节点消失，或它并未挂载）：让部件停在落点上，而不是卡在半个状态。
		gpClearPendingAttach()
	return gpNid


# Detach the selected nodes from their hosts, keeping them visually where they are.
# 把选中节点从其宿主上卸下，并让它们在视觉上停在原处。
func gpRequestDetachSelected() -> bool:
	return gpEditFacade.gpRequestDetachSelected()


# Commit a finished mount drag as one undo step (the caller restores the pre-drag tuple first).
# 把一次完成的挂载拖拽提交为一步撤销（调用方须先恢复拖拽前的元组）。
func gpRequestSetMount(gpNodeIds: Array[String], gpTargets: Array[Dictionary]) -> bool:
	return gpEditFacade.gpRequestSetMount(gpNodeIds, gpTargets)


# Surface an attach refusal. Separate from gpReportRefusal() so the pinned single-argument arity of
# that port stays untouched, while attach keys keep their own i18n namespace.
# 呈现一条附件拒绝原因。与 gpReportRefusal() 分开，使该端口被钉死的单参形态保持不变，
# 同时附件键拥有自己的 i18n 命名空间。
func gpReportAttachRefusal(gpKey: String) -> void:
	gpEditFacade.gpReportRefusal(gpKey, "attach.")


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


# Set the frame margins of the displayed sheet as ONE undo step (Rev.3 stage 0c).
# 把所显示图纸的图框边距作为**一个**撤销步写入（Rev.3 阶段 0c）。
# The canvas supplies the sheet, so the caller never has to hold one — and the SHEET that is written is
# by construction the one on screen, which is what makes "the frame you dragged" and "the frame that
# gets undone" the same object.
# 图纸由画布提供，故调用方无需持有它 —— 而所写的那张图纸按构造就是屏幕上那张，这正是「你拖的那个图框」
# 与「被撤销的那个图框」是同一对象的原因。
func gpRequestSetFrameMargins(gpMargins: Array) -> bool:
	return gpEditFacade.gpRequestSetFrameMargins(gpMargins)


# Dock the title block to a corner at an offset, as ONE undo step (Rev.3 stage 1).
# 把图签停靠到某个角、并带上偏移，作为**一个**撤销步（Rev.3 阶段 1）。
#
# WHY A SEPARATE PORT FROM gpRequestSetFrameMargins / 为何与 gpRequestSetFrameMargins 分开：the margins
# describe the FRAME, the docking pair describes the TITLE BLOCK. Sharing one port would force the two
# gestures to share an undo label ("调整图框" on a title-block drag reads as a lie) and would tie two
# unrelated key sets to one entry point, so that adding a third would have to widen the first.
# 边距描述的是**图框**，停靠对描述的是**图签**。共用一个端口会迫使两种手势共用一个撤销标签（在拖图签时显示
# 「调整图框」就是谎报），并把两组无关的键绑到同一个入口，使将来加第三组时必须把第一个撑开。
func gpRequestSetTitleBlockPlacement(gpAnchor: int, gpOffset: Vector2) -> bool:
	return gpEditFacade.gpRequestSetTitleBlockPlacement(gpAnchor, gpOffset)


# Move the WHOLE SHEET (paper + frame + every graphic) as ONE undo step (Rev.3 stage 0d).
# 平移**整张图纸**（纸面 + 图框 + 全部图形）作为**一个**撤销步（Rev.3 阶段 0d）。
#
# WHY A SEPARATE PORT FROM gpRequestSetFrameMargins / 为何与 gpRequestSetFrameMargins 分开：
# the margin write reaches only GPSheet, while this one also transforms every absolute coordinate on
# the GRAPH (nodes, edges, shapes). They are different edits with different undo labels and different
# refusal conditions (a zero delta here, no paper bound there), so folding them into one port would
# force one of the two to lie about what it did.
# 边距写入只触及 GPSheet，而本次还会变换**图**上的每一个绝对坐标（图元、边、图形）。它们是不同的编辑
# —— 撤销标签不同、拒绝条件也不同（此处是零位移，那边是纸面约束）—— 合成一个端口就会迫使其中之一
# 谎报自己做了什么。
func gpRequestTranslateSheet(gpDelta: Vector2) -> bool:
	return gpEditFacade.gpRequestTranslateSheet(gpDelta)


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


# Rename one NODE's tag (Rev.3 stage 1.5, R1): the in-place editor's commit port, mirroring
# gpRequestSetEdgeTag. One undo step; duplicates are refused by the service.
# 修改一个**图元**的位号（Rev.3 阶段 1.5，R1）：就地编辑器的提交端口，与 gpRequestSetEdgeTag
# 同形。一个撤销步；重复位号由服务拒绝。
func gpRequestSetNodeTag(gpNodeId: String, gpTag: String) -> bool:
	return gpEditFacade.gpRequestSetNodeTag(gpNodeId, gpTag)


# Set one property value of one node (stage 2): mirrors gpRequestSetNodeTag for GENERATOR
# text blocks whose content lives in gpProps. One undo step.
# 设置某节点的一个属性值（阶段 2）：与 gpRequestSetNodeTag 同形，服务内容存于 gpProps 的
# GENERATOR 文本块。一个撤销步。
func gpRequestSetNodeProp(gpNodeId: String, gpKey: String, gpValue: Variant) -> bool:
	return gpEditFacade.gpRequestSetNodeProp(gpNodeId, gpKey, gpValue)


# Stage 3 (S3): grid-table row/col structure ops, routed to the edit service through the
# facade (same layering as every other canvas request — the canvas never touches the
# command stack directly).
# 阶段 3（S3）：grid 表格行/列结构操作，经 facade 路由到编辑服务（与其余画布请求同一
# 分层 —— 画布绝不直接触碰命令栈）。
func gpRequestTableOp(gpOp: String, gpNodeId: String, gpRow: int, gpCol: int) -> bool:
	return gpEditFacade.gpRequestTableOp(gpOp, gpNodeId, gpRow, gpCol)


# Stage 3 (S4): commit a grid-table props snapshot pair (the column-width drag's commit),
# same layering as gpRequestTableOp.
# 阶段 3（S4）：提交一对 grid 表格 props 快照（列宽拖拽的提交），与 gpRequestTableOp 同一分层。
func gpRequestTableSnapshot(gpNodeId: String, gpBefore: Dictionary,
		gpAfter: Dictionary) -> bool:
	return gpEditFacade.gpRequestTableSnapshot(gpNodeId, gpBefore, gpAfter)


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
