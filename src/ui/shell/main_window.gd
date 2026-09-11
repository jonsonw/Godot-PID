class_name GPMainWindow
extends Control

# Main scene controller. The CAD-style layout (top menu / left palette / center
# canvas / right inspector tabs / bottom status bar) is FROZEN in main.tscn.
# This script only wires the static nodes together and injects the dynamic
# content: symbol buttons into the left palette, the property form into the
# inspector, and live text into the status bar.
# 主场景控制器。CAD 风格布局（顶部菜单 / 左侧图元库 / 中心画布 / 右侧属性标签页 /
# 底部状态栏）固化于 main.tscn。本脚本仅把静态节点接起来，并注入动态内容：
# 向左侧注入图元按钮、向属性面板注入表单、向状态栏注入实时文本。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Available symbol definitions shown in the left palette.
# 左栏显示的可用图元定义。
var gpDefs: Array[GPSymbolDef] = []

# Last opened/saved project path; Save reuses it, Save As / Open prompt for a new one.
# 上次打开/保存的工程路径；保存复用它，另存为/打开则重新选择。
var gpCurrentPath: String = ""

# File dialog (open / save-as), created once and reused.
# 打开/另存为用的文件对话框，创建一次重复使用。
# 架构优化 §3.2：文件生命周期协调者（保存/打开/导入/导出/关闭拦截）。
# File lifecycle coordinator (save/open/import/export/close guard).
var gpFileCoord: GPFileCoordinator = null

# 架构优化 §3.2：GPRibbonCoordinator（Ribbon 与工具栏的构建、样式、模式映射与工具选中转发）。
# Ribbon and toolbar construction, styling, mode mapping and tool-selection forwarding.
var gpRibbonCoord: GPRibbonCoordinator = null

# 架构优化 §3.2：GPSymbolLibraryCoordinator（图元库级联删除、替换与重命名、漂移对账、用户包加载与符号编辑器宿主）。
# Symbol library cascade delete, swap/rename, drift reconciliation, user packs and the symbol editor host.
var gpSymbolLibCoord: GPSymbolLibraryCoordinator = null

# 架构优化 §3.2：GPSelectionCoordinator（图与面板的双向同步桥：订阅事件总线刷新属性面板与状态栏，并把面板改值经命令层回写）。
# Graph-to-panel sync bridge: subscribes to the event bus, refreshes inspector and status bar, writes panel edits back through the command layer.
var gpSelCoord: GPSelectionCoordinator = null

# 架构优化 §3.2：GPTagRuleCoordinator（位号规则对话框编排与重编号工作流）。
# Tag-rule dialog orchestration and the renumber workflow.
var gpTagCoord: GPTagRuleCoordinator = null

# 架构优化 §3.2：GPLayoutCoordinator（分隔条比例、DPI 缩放、窗口尺寸响应与最大化）。
# Splitter ratios, DPI scaling, window resize handling and maximised start-up.
var gpLayoutCoord: GPLayoutCoordinator = null

# 架构优化 §3.2：GPMenuCoordinator（菜单分发、撤销/重做与设置对话框；文件类动作转发给 GPFileCoordinator）。
# Menu dispatch, undo/redo and the settings dialog; file actions are forwarded to GPFileCoordinator.
var gpMenuCoord: GPMenuCoordinator = null
var gpFileDialog: FileDialog

# What the in-flight file dialog is for: "save" / "open" / "import" / "export_<kind>".
# 当前文件对话框的用途：save / open / import / export_<kind>。
var gpPendingFileAction: String = ""

# Set when the user chose "Save" in the close-confirmation and the project had no path yet,
# so the quit has to wait for the save-as dialog to complete.
# 用户在关闭确认中选了「保存」但工程尚无路径时置位，使退出必须等另存为对话框完成。
var gpQuitAfterSave: bool = false

# Application-layer document manager (M6). The composition root owns it; it holds the event
# bus, the active graph and the unsaved-dirty flag, replacing the old GPAppState autoload stub.
# 应用层文档管理器（M6）。组合根持有它；它持有事件总线、当前图与未保存脏标记，
# 取代旧 GPAppState 自动加载桩。
var gpDocManager: GPAppDocumentManager = GPAppDocumentManager.new()

# ---- static node references (frozen in the scene) ----·
# ---- 静态节点引用（固化于场景） ----
# Top menu bar.
# 顶部菜单栏。··
var gpMenuBar: GPPIDMenuBar

# Left symbol-library dock.
# 左侧图元库停靠栏。
var gpLeftDock: GPPIDToolbar

# Right property-inspector dock (hidden in fullscreen mode).
# 右侧属性面板停靠栏（全屏时隐藏）。
var gpRightDock: VBoxContainer

# Center drawing area: hosts the tabbed multi-sheet editor (one canvas + graph per tab).
# 中心绘图区：承载多标签页绘图编辑器（每标签页一个画布 + 图）。
var gpCenter: GPCenterArea

# Right-side tab container.
# 右侧标签页容器。
var gpTabs: TabContainer

# Property inspector (inside the right tab container).
# 属性面板（在右侧标签页内）。
var gpInspector: GPInspector

# Info label on the Info tab.
# 信息标签页上的信息标签。
var gpInfoLabel: Label

# Document metadata label on the Doc tab.
# 文档标签页上的文档元数据标签。
var gpDocLabel: Label

# Status bar label showing the current selection.
# 状态栏标签：显示当前选中。
var gpSelLabel: Label

# Status bar label showing the cursor coordinates.
# 状态栏标签：显示光标坐标。
var gpCoordLabel: Label

# Status bar label showing the current zoom.
# 状态栏标签：显示当前缩放。
var gpZoomLabel: Label

# Status bar label showing the current application state.
# 状态栏标签：显示当前应用状态。
var gpStateLabel: Label

# (M2) gpLastSel removed: the host no longer diffs a selection string; the canvas emits
# gpSelectionChanged directly, so this cached id has no consumer left.
# （M2）已删除 gpLastSel：宿主不再比对选中字符串，画布直接发射 gpSelectionChanged，
# 这个缓存 id 已无使用方。
# Last status snapshot received from the canvas.
# 从画布接收到的上一个状态快照。
var gpLastStatus: Dictionary = {"selection": "", "zoom": 1.0, "world": Vector2.ZERO}

# Current state-bar i18n key.
# 当前状态栏 i18n 键。
var gpStateKey: String = "status.ready"

# Arguments for the current state-bar format string.
# 当前状态栏格式化字符串的参数。
var gpStateArgs: Array = []

# Last known screen index, used to detect a cross-monitor drag so we can refresh
# the UI at the new monitor's density.
# 上一次所在的屏幕索引，用于检测跨显示器拖拽，从而按新显示器密度刷新 UI。
var gpLastScreen: int = -1

# The single HSplitContainer that lays out the three panes (left symbol library
# / center canvas / right inspector) and lets the user drag both splitters to
# resize them independently.
# 承载三栏布局（左图元库 / 中心画布 / 右属性面板）的单一 HSplitContainer，
# 用户可拖动两个分隔条独立调整各栏宽度。
var gpBodySplit: HSplitContainer

# Previous window content width, used to detect a real resize vs a HiDPI refresh.
# 上一次窗口内容宽度，用于区分真实缩放与 HiDPI 刷新。
var gpPrevWidth: int = 0

# Fixed floor widths for the side docks (pixels). These replace the old
# "dock width as a ratio of the window" model: docks stay a constant size and the
# canvas (center pane) absorbs all remaining width, which is the standard IDE / CAD
# behaviour and keeps the docks usable at any window size.
# 左右停靠栏的固定下限宽度（像素）。这取代了旧的"停靠栏占窗口比例"模型：停靠栏保持
# 恒定尺寸，画布（中间栏）吸收所有剩余宽度——这正是 IDE / CAD 的常规做法，可在任意
# 窗口尺寸下保证停靠栏可用。
# Left dock minimum width in pixels (matches LeftDock.custom_minimum_size.x).
# 左停靠栏最小宽度（像素，与 LeftDock.custom_minimum_size.x 一致）。
const GP_LEFT_MIN: float = 160.0
# Right dock minimum width in pixels (matches RightDock.custom_minimum_size.x).
# 右停靠栏最小宽度（像素，与 RightDock.custom_minimum_size.x 一致）。
const GP_RIGHT_MIN: float = 160.0

# Current left-dock width in pixels; seeded from GP_LEFT_MIN and updated by drags.
# 当前左停靠栏宽度（像素）；以 GP_LEFT_MIN 初始化，拖拽时更新。
var gpLeftWidthPx: float = GP_LEFT_MIN
# Current right-dock width in pixels; seeded from GP_RIGHT_MIN and updated by drags.
# 当前右停靠栏宽度（像素）；以 GP_RIGHT_MIN 初始化，拖拽时更新。
var gpRightWidthPx: float = GP_RIGHT_MIN

# Drawing toolbar row under the menu bar (select / connect / line / circle / rect / polyline / port / new).
# 菜单栏下方的绘图工具栏行（选择 / 连线 / 直线 / 圆 / 矩形 / 折线 / 端口 / 新建）。
var gpToolBar: HBoxContainer = null

# Toggle buttons (select / connect) kept for highlight sync; keyed by action name.
# 开关按钮（选择 / 连线），保留以便同步高亮；以动作名为键。
var gpToolBtns: Dictionary = {}

# Ribbon command bar (P0 / ADR-UI-01). Replaces the old flat DrawToolBar in the
# same VBox slot; emits gpActionTriggered, which routes to gpRibbonCoord.gpOnToolBarPressed.
# Ribbon 命令栏（P0 / ADR-UI-01），在原 DrawToolBar 同位置取代它；发射 gpActionTriggered
# 并路由到 gpRibbonCoord.gpOnToolBarPressed。回退只需恢复 _gpBuildToolBar 调用（见下方注释）。
var gpRibbon: GPPIDRibbon = null


# Wire the static scene together and set up initial state.
# 将静态场景拼接起来并设置初始状态。
func _ready() -> void:
	# Arm the close guard: take ownership of the OS close request so the window does
	# NOT quit by itself. The _notification(NOTIFICATION_WM_CLOSE_REQUEST) handler below
	# then decides (clean -> quit, dirty -> three-way ask). Without this line the engine
	# quits immediately after dispatching the notification, so the unsaved-changes dialog
	# is created but never shown and work is lost silently.
	# 武装关闭拦截：接管 OS 关闭请求，使窗口不会自行退出。下方的
	# _notification(NOTIFICATION_WM_CLOSE_REQUEST) 才拥有决定权（干净→退出，
	# 脏→三选一）。缺此一行，引擎会在派发通知后立刻退出，未保存对话框虽被创建却
	# 永无机会显示，改动被静默丢失。
	get_tree().auto_accept_quit = false

	# Intercept the OS window-close via the root Window's close_requested signal (the
	# reliable, signal-based path in Godot 4). A plain _notification(NOTIFICATION_WM_CLOSE_
	# REQUEST) on a Control root is NOT reliably delivered, so the three-way dialog would
	# never appear on a red-X click. close_requested fires on the actual Window and lets us
	# decide (clean -> quit, dirty -> three-way ask) instead of the engine auto-quitting.
	# 用根 Window 的 close_requested 信号拦截 OS 关闭（Godot 4 中可靠、基于信号的做法）。
	# 在 Control 根上用 _notification(NOTIFICATION_WM_CLOSE_REQUEST) 并不可靠地送达，
	# 红叉点击时三选一对话框因此从不出现。close_requested 在真正的 Window 上触发，
	# 由我们决定（干净→退出，脏→三选一）而非引擎自退。
	# 架构优化 §3.2：文件生命周期已抽出为 GPFileCoordinator，根类仅做装配与转发。
	# The file lifecycle now lives in GPFileCoordinator; the root only assembles.
	gpFileCoord = GPFileCoordinator.new()
	gpFileCoord.gpHost = self
	gpRibbonCoord = GPRibbonCoordinator.new()
	gpRibbonCoord.gpHost = self
	gpSymbolLibCoord = GPSymbolLibraryCoordinator.new()
	gpSymbolLibCoord.gpHost = self
	gpSelCoord = GPSelectionCoordinator.new()
	gpSelCoord.gpHost = self
	gpTagCoord = GPTagRuleCoordinator.new()
	gpTagCoord.gpHost = self
	gpLayoutCoord = GPLayoutCoordinator.new()
	gpLayoutCoord.gpHost = self
	gpMenuCoord = GPMenuCoordinator.new()
	gpMenuCoord.gpHost = self
	get_window().close_requested.connect(gpFileCoord.gpOnCloseRequested)

	# Restore any symbol packs the user exported in a previous session so they
	# re-appear in the palette and on the canvas after a restart.
	# 恢复用户在上一次会话中导出的图元包，使重启后它们重新出现在图元库与画布中。
	GPSymbolLibrary.gpLoadUserPacks()
	gpDefs = GPSymbolLibrary.gpDefaultDefs()

	# Fetch static nodes from the scene tree.
	# 从场景树获取静态节点。
	gpMenuBar = $VLayout/MenuBar
	gpLeftDock = $VLayout/Body/LeftDock
	gpRightDock = $VLayout/Body/RightDock
	# Keep the left palette grid's column-count floor in sync with the dock floor so
	# a narrow dock still derives a sensible column count (single source of truth).
	# 让左图元库网格的列数下限与停靠栏下限同步，窄停靠栏仍能推导出合理列数（单一数据源）。
	gpLeftDock.gpMinWidth = GP_LEFT_MIN
	gpBodySplit = $VLayout/Body
	gpBodySplit.dragged.connect(gpLayoutCoord.gpOnBodyDragged)
	# Style the two splitters as thin black bars that reveal a gray grab handle on
	# hover (Godot-editor look). See _gpStyleBodySplit for the theme overrides.
	# 把两条分隔条样式化为细黑条，悬停时显出灰色可拖拽手柄（仿 Godot 编辑器）。
	gpTabs = $VLayout/Body/RightDock/InspectorTabs
	gpInspector = $VLayout/Body/RightDock/InspectorTabs/PropTab
	gpInfoLabel = $VLayout/Body/RightDock/InspectorTabs/InfoTab/InfoLabel
	gpDocLabel = $VLayout/Body/RightDock/InspectorTabs/DocTab/DocLabel
	gpSelLabel = $VLayout/StatusBar/SelLabel
	gpCoordLabel = $VLayout/StatusBar/CoordLabel
	gpZoomLabel = $VLayout/StatusBar/ZoomLabel
	gpStateLabel = $VLayout/StatusBar/StateLabel

	# Center tabbed drawing area: create the first sheet only AFTER the inspector and
	# status labels exist, because adding a tab refreshes the inspector immediately.
	# 中心多标签页绘图区：首张图纸在属性面板与状态标签建立后再建，因为新建即刷新属性面板。
	gpCenter = $VLayout/Body/Center
	gpCenter.gpSetDefs(gpDefs)
	gpCenter.gpOnCanvasReady.connect(_gpOnCanvasReady)
	gpCenter.gpActiveChanged.connect(_gpOnActiveTabChanged)
	gpCenter.gpFullscreenToggled.connect(_gpOnFullscreen)
	gpCenter.gpAddTab()

	# ---- left palette: inject symbol buttons ----
	# ---- 左侧图元库：注入图元按钮 ----
	gpLeftDock.gpPopulate(gpDefs)
	gpLeftDock.gpSymbolPicked.connect(gpRibbonCoord.gpOnSymbolPicked)
	gpLeftDock.gpToolSelected.connect(gpRibbonCoord.gpOnToolSelected)
	# Symbol deletion is owned here: scan every sheet, cascade-remove canvas instances if
	# the symbol is in use, then drop it from the live library and re-render the palette.
	# 图元删除在此负责：扫描所有图纸，若图元在用则级联清理画布实例，再从活动库移除并重渲染。
	gpLeftDock.gpSymbolDeleteRequested.connect(gpSymbolLibCoord.gpOnSymbolDeleteRequested)

	# ---- inspector ----
	# ---- 属性面板 ----
	gpInspector.gpAttrChanged.connect(gpSelCoord.gpOnAttrChanged)
	gpInspector.gpEdgeAttrChanged.connect(gpSelCoord.gpOnEdgeAttrChanged)
	# M10: the panel owns no graph, so a symbol swap is announced and executed here.
	# M10：面板不持有图，故「更换图元」在此被宣告并执行。
	gpInspector.gpSymbolSwapRequested.connect(gpSymbolLibCoord.gpOnSymbolSwap)
	# M11: a batched edit arrives once with the whole id set, so it becomes one undo step.
	# M11：批量编辑连同整个 id 集合一次性送达，故只产生一个撤销步。
	gpInspector.gpBatchAttrChanged.connect(gpSelCoord.gpOnBatchAttrChanged)
	# M12: orphaned values may only be dropped on an explicit request from the panel.
	# M12：孤儿值仅在面板明确请求时才可被清除。
	gpInspector.gpCleanOrphansRequested.connect(gpSymbolLibCoord.gpOnCleanOrphans)
	gpInspector.gpDefs = gpDefs

	# ---- menu ----
	# ---- 菜单 ----
	gpMenuBar.gpActionTriggered.connect(gpMenuCoord.gpOnMenu)
	# Ask the host to refresh enabled states right before a popup opens.
	# 菜单展开前向宿主请求刷新启用状态。
	gpMenuBar.gpMenuOpening.connect(gpMenuCoord.gpOnMenuOpening)

	# ---- Ribbon command bar under the menu bar (P0 / ADR-UI-01) ----
	# ---- 菜单栏下方的 Ribbon 命令栏（P0 / ADR-UI-01） ----
	gpRibbonCoord.gpBuildRibbon()
	gpRibbonCoord.gpStyleChrome()

	# ---- file dialog (open / save-as) ----
	# ---- 文件对话框（打开 / 另存为） ----
	gpFileDialog = FileDialog.new()
	gpFileDialog.access = FileDialog.ACCESS_FILESYSTEM
	gpFileDialog.add_filter("*.pid.json", I18n.gpTr("doc.pid_filter"))
	gpFileDialog.file_selected.connect(gpFileCoord.gpOnFileSelected)
	add_child(gpFileDialog)

	I18n.gpLocaleChanged.connect(_gpOnLocaleChanged)
	_gpRefreshStaticText()

	# ---- HiDPI / multi-monitor crispness + responsive resize ----
	# ---- 多显示器清晰渲染（HiDPI）+ 响应式缩放 ----
	var gpWin: Window = get_window()
	if gpWin != null:
		gpWin.size_changed.connect(gpLayoutCoord.gpOnWindowChanged)
		gpWin.size_changed.connect(gpLayoutCoord.gpOnResized)
		gpWin.focus_entered.connect(gpLayoutCoord.gpOnWindowChanged)
		gpLastScreen = gpWin.current_screen
		gpPrevWidth = int(gpWin.size.x)
		gpLayoutCoord.gpApplyDpiScale()
		# Open the main window MAXIMIZED so it fills the current monitor. The UI is designed at a
		# fixed 1600x900 base; with stretch mode "canvas_items" Godot then scales that design canvas
		# to the real window, so the interface always matches the monitor's own scale instead of
		# opening at the raw base size. Without this the window stays 1600x900 "design points", which
		# overflows a Retina logical screen (~1440x932) and makes the UI look too big / off-screen.
		# 主窗口默认「最大化」以铺满当前显示器。UI 以固定 1600x900 基准设计；配合 stretch 模式
		# canvas_items，Godot 会把这 1600x900 的设计画布缩放到真实窗口，使界面始终匹配显示器自身
		# 的缩放比，而非以原始基准尺寸打开。否则窗口保持 1600x900「设计点」，会超出 Retina 逻辑屏
		# （约 1440x932），导致 UI 显得过大 / 超出屏幕。
		gpLayoutCoord.gpOpenMaximized(gpWin)

	# ---- initial dock widths: pin both docks to their floor, canvas fills rest ----
	# ---- 初始停靠栏宽度：两栏钉到下限，画布填满剩余空间 ----
	gpLayoutCoord.gpInitSplits()

	# initial status
	# 初始状态
	gpSelCoord.gpOnStatus(gpLastStatus)


# ============================ center area (tabbed sheets) ============================
# ============================ 中心区（多标签页图纸） ============================
# The active canvas/graph are owned by the GPCenterArea; these accessors route the
# legacy single-canvas logic to whichever sheet is currently active.
# 活动画布/图由 GPCenterArea 持有；这些访问器把原先针对单一画布的逻辑，路由到
# 当前活动图纸。
func gpActiveCanvas() -> GPCanvas2D:
	return gpCenter.gpActiveCanvas()


func gpActiveGraph() -> GPPIDGraph:
	return gpCenter.gpActiveGraph()


# A new sheet canvas was created: give it the shared symbol definitions and connect
# its graph/status signals once. Per-canvas connection avoids re-wiring on tab switch.
# 新建了图纸画布：注入共用图元定义，并一次性连接其图变化/状态信号。逐画布连接可避免
# 切换标签时重复接线。
func _gpOnCanvasReady(gpCanvas: GPCanvas2D) -> void:
	gpCanvas.gpDefs = gpDefs
	# M6: the composition root owns the document manager + bus; hand it to the canvas BEFORE
	# reading gpEvents so the host subscribes to the manager's bus (not the fallback). The
	# canvas forwards every graph / selection / status / mode event onto that bus.
	# M6：组合根持有文档管理器与总线；在读取 gpEvents 之前先交给画布，使宿主订阅的是
	# 管理器的总线（而非回退总线）。画布将图/选中/状态/模式事件统一转发到该总线。
	gpCanvas.gpBindDocument(gpDocManager)
	# M2: subscribe to the sheet's app event bus instead of the canvas signals. The canvas
	# keeps emitting its legacy signals (public API stays stable), but the host now listens
	# on ONE explicit channel: state broadcasts travel on the bus, host-directed requests
	# (open editor / promote shapes) stay on signals.
	# M2：订阅本图纸的应用事件总线而非画布信号。画布仍发射旧信号（公共 API 保持稳定），
	# 但宿主现在只监听一条显式通道：状态广播走总线，宿主定向请求（打开编辑器 / 提升图形）仍走信号。
	var gpBus: GPEventBus = gpCanvas.gpEvents
	gpBus.gpGraphChanged.connect(gpSelCoord.gpOnGraphChanged)
	gpBus.gpSelectionChanged.connect(gpSelCoord.gpOnSelectionChanged)
	gpBus.gpStatusUpdated.connect(gpSelCoord.gpOnStatus)
	gpBus.gpModeChanged.connect(gpRibbonCoord.gpSyncToolBar)
	# Announce the document already loaded onto this canvas so bus subscribers (title bar,
	# project tree) bind to the correct graph in one place, and the dirty flag resets.
	# 通告本画布已载入的文档，使总线订阅者（标题栏、工程树）在一处绑定到正确的图，并重置脏标记。
	gpDocManager.gpSetGraph(gpCanvas.gpGraph)
	# Double click / context menu on a symbol asks for in-place geometry editing.
	# 图元上的双击 / 右键菜单会请求就地编辑几何。
	gpCanvas.gpSymbolEditRequested.connect(gpSymbolLibCoord.gpOnSymbolEditRequested)
	# Promote selected annotation shapes into a real symbol: open the Make-Symbol dialog.
	# 把选中的注释图形提升为真正图元：打开「生成图元」对话框。
	gpCanvas.gpMakeSymbolRequested.connect(gpSymbolLibCoord.gpOnMakeSymbolFromShapes)
	# (M2) gpModeChanged is now a bus event; the legacy canvas connection above would
	# fire the toolbar sync twice, so it is intentionally not connected here.
	# （M2）模式变化已改为总线事件；上面若再连旧画布信号会导致工具栏同步触发两次，
	# 故此处有意不再连接。
	# A brand-new sheet has an empty undo stack: make the 编辑 menu agree with it right away.
	# 新建图纸的撤销栈为空：让「编辑」菜单立即与之保持一致。
	gpMenuCoord.gpRefreshEditMenu()


# The active sheet changed (add / switch / close): refresh the inspector for the
# newly active selection.
# 活动图纸已切换（新建 / 切换 / 关闭）：刷新新活动页的选中属性。
func _gpOnActiveTabChanged() -> void:
	gpSelCoord.gpRefreshSelection()
	gpRibbonCoord.gpSyncToolBar()


# Fullscreen toggle from the center header: hide/show the side docks so the canvas
# fills the window, then re-apply the splits when leaving fullscreen.
# 中心头部触发的全屏切换：隐藏/显示左右停靠栏使画布占满窗口，退出时重新应用分隔。
func _gpOnFullscreen(gpOn: bool) -> void:
	gpLeftDock.visible = not gpOn
	gpRightDock.visible = not gpOn
	gpLayoutCoord.gpApplySplits()

# ============================ localization refresh ============================
# ============================ 本地化刷新 ============================
# React to locale change: refresh all static UI text and current panels.
# 响应语言变化：刷新所有静态 UI 文本与当前面板。
func _gpOnLocaleChanged(_gpLocale: String) -> void:
	_gpRefreshStaticText()
	gpSelCoord.gpOnStatus(gpLastStatus)
	gpSelCoord.gpRefreshSelection()


# Refresh static labels that are not driven by individual widgets.
# 刷新那些不由单个控件自行驱动的静态标签。
func _gpRefreshStaticText() -> void:
	gpTabs.set_tab_title(0, I18n.gpTr("prop.title"))
	gpTabs.set_tab_title(1, I18n.gpTr("prop.info"))
	gpTabs.set_tab_title(2, I18n.gpTr("prop.doc"))
	gpDocLabel.text = I18n.gpTr("doc.info")
	_gpSetState(gpStateKey, gpStateArgs)


func _gpOnSymbolPicked(gpTypeId: String) -> void:
	gpRibbonCoord.gpOnSymbolPicked(gpTypeId)


func _gpOnToolSelected(gpType: String) -> void:
	gpRibbonCoord.gpOnToolSelected(gpType)
func _gpOnSymbolDeleteRequested(gpId: String) -> void:
	gpSymbolLibCoord.gpOnSymbolDeleteRequested(gpId)


func _gpConfirmCascadeDelete(gpId: String, gpTotal: int) -> void:
	gpSymbolLibCoord.gpConfirmCascadeDelete(gpId, gpTotal)


func _gpCascadeDeleteSymbol(gpId: String) -> void:
	gpSymbolLibCoord.gpCascadeDeleteSymbol(gpId)


func _gpDeleteSymbolAndRefresh(gpId: String) -> void:
	gpSymbolLibCoord.gpDeleteSymbolAndRefresh(gpId)
func _gpOnGraphChanged(_gpGraph: GPPIDGraph = null) -> void:
	gpSelCoord.gpOnGraphChanged(_gpGraph)


func _gpOnSelectionChanged(_gpIds: Array[String] = []) -> void:
	gpSelCoord.gpOnSelectionChanged(_gpIds)


func _gpOnStatus(gpInfo: Dictionary) -> void:
	gpSelCoord.gpOnStatus(gpInfo)


func _gpRefreshSelection() -> void:
	gpSelCoord.gpRefreshSelection()


func _gpOnAttrChanged(gpId: String, gpKey: String, gpVal) -> void:
	gpSelCoord.gpOnAttrChanged(gpId, gpKey, gpVal)


func _gpOnBatchAttrChanged(gpIds: Array[String], gpKey: String, gpVal) -> void:
	gpSelCoord.gpOnBatchAttrChanged(gpIds, gpKey, gpVal)


func _gpApplyAttr(gpIds: Array[String], gpKey: String, gpVal: Variant) -> void:
	gpSelCoord.gpApplyAttr(gpIds, gpKey, gpVal)


func _gpOnSymbolSwap(gpNodeId: String, gpNewSymbolId: String) -> void:
	gpSymbolLibCoord.gpOnSymbolSwap(gpNodeId, gpNewSymbolId)


func _gpSyncInspectorDefs() -> void:
	gpSymbolLibCoord.gpSyncInspectorDefs()


func _gpReconcileLibraryDrift(gpGraph: GPPIDGraph) -> void:
	gpSymbolLibCoord.gpReconcileLibraryDrift(gpGraph)


func _gpOnCleanOrphans(gpNodeId: String) -> void:
	gpSymbolLibCoord.gpOnCleanOrphans(gpNodeId)
func _gpOnEdgeAttrChanged(gpEdgeId: String, gpKey: String, gpVal) -> void:
	gpSelCoord.gpOnEdgeAttrChanged(gpEdgeId, gpKey, gpVal)
func _gpOnMenu(gpAction: String) -> void:
	gpMenuCoord.gpOnMenu(gpAction)


func _gpOpenTagRuleDialog() -> void:
	gpTagCoord.gpOpenTagRuleDialog()


func _gpOnTagRulesApplied(gpRules: GPProjectTagRules, gpRenumber: bool) -> void:
	gpTagCoord.gpOnTagRulesApplied(gpRules, gpRenumber)


func _gpConfirmRenumberTags() -> void:
	gpTagCoord.gpConfirmRenumberTags()


func _gpDoRenumberTags() -> void:
	gpTagCoord.gpDoRenumberTags()
func _gpOnMenuOpening(gpTitleKey: String) -> void:
	gpMenuCoord.gpOnMenuOpening(gpTitleKey)


func _gpRefreshEditMenu() -> void:
	gpMenuCoord.gpRefreshEditMenu()


func _gpMenuUndo() -> void:
	gpMenuCoord.gpMenuUndo()


func _gpMenuRedo() -> void:
	gpMenuCoord.gpMenuRedo()
func _gpOnCloseRequested() -> void:
	gpFileCoord.gpOnCloseRequested()
func _gpAskUnsaved() -> void:
	gpFileCoord.gpAskUnsaved()
func _gpOnUnsavedSave(gpDlg: ConfirmationDialog) -> void:
	gpFileCoord.gpOnUnsavedSave(gpDlg)
func _gpOnUnsavedDiscard(gpAction: StringName, gpDlg: ConfirmationDialog) -> void:
	gpFileCoord.gpOnUnsavedDiscard(gpAction, gpDlg)
func _gpSaveProject(gpForcePick: bool) -> void:
	gpFileCoord.gpSaveProject(gpForcePick)
func _gpOpenProject() -> void:
	gpFileCoord.gpOpenProject()
func _gpImportProject() -> void:
	gpFileCoord.gpImportProject()
func _gpPickExportPath(gpKind: String) -> void:
	gpFileCoord.gpPickExportPath(gpKind)
func _gpOnFileSelected(gpPath: String) -> void:
	gpFileCoord.gpOnFileSelected(gpPath)
func _gpWriteProject(gpPath: String) -> void:
	gpFileCoord.gpWriteProject(gpPath)
func _gpReadProject(gpPath: String) -> void:
	gpFileCoord.gpReadProject(gpPath)
func _gpDoImport(gpPath: String) -> void:
	gpFileCoord.gpDoImport(gpPath)
func _gpDoExport(gpPath: String, gpKind: String) -> void:
	gpFileCoord.gpDoExport(gpPath, gpKind)
func _gpOpenSettings() -> void:
	gpMenuCoord.gpOpenSettings()


func _gpBuildRibbon() -> void:
	gpRibbonCoord.gpBuildRibbon()


func _gpStyleChrome() -> void:
	gpRibbonCoord.gpStyleChrome()


func _gpAddToolBtn(gpAction: String, gpKey: String, gpToggle: bool) -> Button:
	return gpRibbonCoord.gpAddToolBtn(gpAction, gpKey, gpToggle)


func _gpAddSep() -> void:
	gpRibbonCoord.gpAddSep()


func _gpOnToolBarPressed(gpAction: String) -> void:
	gpRibbonCoord.gpOnToolBarPressed(gpAction)


func _gpSyncToolBar(gpMode: int = -1) -> void:
	gpRibbonCoord.gpSyncToolBar(gpMode)


func _gpModeForAction(gpAction: String) -> int:
	return gpRibbonCoord.gpModeForAction(gpAction)
func _gpOnMakeSymbolFromShapes(gpDraft: Dictionary) -> void:
	gpSymbolLibCoord.gpOnMakeSymbolFromShapes(gpDraft)


func _gpOpenMakeSymbolDialog(gpDraft: Dictionary, gpInitialName: String, gpAllowOverwrite: bool, gpInitialPorts: Array[GPPort] = [], gpInitialDisplay: String = "") -> void:
	gpSymbolLibCoord.gpOpenMakeSymbolDialog(gpDraft, gpInitialName, gpAllowOverwrite, gpInitialPorts, gpInitialDisplay)


func _gpOnSymbolEditRequested(gpSymbolId: String) -> void:
	gpSymbolLibCoord.gpOnSymbolEditRequested(gpSymbolId)


func _gpOnSymbolSaved(gpSymbolId: String) -> void:
	gpSymbolLibCoord.gpOnSymbolSaved(gpSymbolId)
func _gpDeleteSelected() -> void:
	gpMenuCoord.gpDeleteSelected()
func _gpSetState(gpKey: String, gpArgs: Array = []) -> void:
	gpStateKey = gpKey
	gpStateArgs = gpArgs
	var gpFmt: String = I18n.gpTr(gpKey)
	gpStateLabel.text = gpFmt % gpArgs if gpArgs.size() > 0 else gpFmt


func _gpApplyDpiScale() -> void:
	gpLayoutCoord.gpApplyDpiScale()


func _gpOpenMaximized(gpWin: Window) -> void:
	gpLayoutCoord.gpOpenMaximized(gpWin)


func _gpOnWindowChanged() -> void:
	gpLayoutCoord.gpOnWindowChanged()


func _gpOnResized() -> void:
	gpLayoutCoord.gpOnResized()


func _gpApplySplits() -> void:
	gpLayoutCoord.gpApplySplits()


func _gpInitSplits() -> void:
	gpLayoutCoord.gpInitSplits()


func _gpOnBodyDragged(gpOffset: int) -> void:
	gpLayoutCoord.gpOnBodyDragged(gpOffset)
func _gpDefFor(gpTypeId: String) -> GPSymbolDef:
	for gpD in gpDefs:
		if gpD.gpId == gpTypeId:
			return gpD
	return null


# Find a graph node by its id.
# 按 id 查找图节点。
func _gpNodeFor(gpId: String) -> GPPIDNode:
	var gpG: GPPIDGraph = gpActiveGraph()
	if gpG == null:
		return null
	for gpN in gpG.gpNodes:
		if gpN.gpInstanceId == gpId:
			return gpN
	return null
