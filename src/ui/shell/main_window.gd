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
# same VBox slot; emits gpActionTriggered, which routes to _gpOnToolBarPressed.
# Ribbon 命令栏（P0 / ADR-UI-01），在原 DrawToolBar 同位置取代它；发射 gpActionTriggered
# 并路由到 _gpOnToolBarPressed。回退只需恢复 _gpBuildToolBar 调用（见下方注释）。
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
	gpBodySplit.dragged.connect(_gpOnBodyDragged)
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
	gpLeftDock.gpSymbolPicked.connect(_gpOnSymbolPicked)
	gpLeftDock.gpToolSelected.connect(_gpOnToolSelected)
	# Symbol deletion is owned here: scan every sheet, cascade-remove canvas instances if
	# the symbol is in use, then drop it from the live library and re-render the palette.
	# 图元删除在此负责：扫描所有图纸，若图元在用则级联清理画布实例，再从活动库移除并重渲染。
	gpLeftDock.gpSymbolDeleteRequested.connect(_gpOnSymbolDeleteRequested)

	# ---- inspector ----
	# ---- 属性面板 ----
	gpInspector.gpAttrChanged.connect(_gpOnAttrChanged)
	gpInspector.gpEdgeAttrChanged.connect(_gpOnEdgeAttrChanged)
	# M10: the panel owns no graph, so a symbol swap is announced and executed here.
	# M10：面板不持有图，故「更换图元」在此被宣告并执行。
	gpInspector.gpSymbolSwapRequested.connect(_gpOnSymbolSwap)
	# M11: a batched edit arrives once with the whole id set, so it becomes one undo step.
	# M11：批量编辑连同整个 id 集合一次性送达，故只产生一个撤销步。
	gpInspector.gpBatchAttrChanged.connect(_gpOnBatchAttrChanged)
	# M12: orphaned values may only be dropped on an explicit request from the panel.
	# M12：孤儿值仅在面板明确请求时才可被清除。
	gpInspector.gpCleanOrphansRequested.connect(_gpOnCleanOrphans)
	gpInspector.gpDefs = gpDefs

	# ---- menu ----
	# ---- 菜单 ----
	gpMenuBar.gpActionTriggered.connect(_gpOnMenu)
	# Ask the host to refresh enabled states right before a popup opens.
	# 菜单展开前向宿主请求刷新启用状态。
	gpMenuBar.gpMenuOpening.connect(_gpOnMenuOpening)

	# ---- Ribbon command bar under the menu bar (P0 / ADR-UI-01) ----
	# ---- 菜单栏下方的 Ribbon 命令栏（P0 / ADR-UI-01） ----
	_gpBuildRibbon()
	_gpStyleChrome()

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
		gpWin.size_changed.connect(_gpOnWindowChanged)
		gpWin.size_changed.connect(_gpOnResized)
		gpWin.focus_entered.connect(_gpOnWindowChanged)
		gpLastScreen = gpWin.current_screen
		gpPrevWidth = int(gpWin.size.x)
		_gpApplyDpiScale()
		# Open the main window MAXIMIZED so it fills the current monitor. The UI is designed at a
		# fixed 1600x900 base; with stretch mode "canvas_items" Godot then scales that design canvas
		# to the real window, so the interface always matches the monitor's own scale instead of
		# opening at the raw base size. Without this the window stays 1600x900 "design points", which
		# overflows a Retina logical screen (~1440x932) and makes the UI look too big / off-screen.
		# 主窗口默认「最大化」以铺满当前显示器。UI 以固定 1600x900 基准设计；配合 stretch 模式
		# canvas_items，Godot 会把这 1600x900 的设计画布缩放到真实窗口，使界面始终匹配显示器自身
		# 的缩放比，而非以原始基准尺寸打开。否则窗口保持 1600x900「设计点」，会超出 Retina 逻辑屏
		# （约 1440x932），导致 UI 显得过大 / 超出屏幕。
		_gpOpenMaximized(gpWin)

	# ---- initial dock widths: pin both docks to their floor, canvas fills rest ----
	# ---- 初始停靠栏宽度：两栏钉到下限，画布填满剩余空间 ----
	_gpInitSplits()

	# initial status
	# 初始状态
	_gpOnStatus(gpLastStatus)


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
	gpBus.gpGraphChanged.connect(_gpOnGraphChanged)
	gpBus.gpSelectionChanged.connect(_gpOnSelectionChanged)
	gpBus.gpStatusUpdated.connect(_gpOnStatus)
	gpBus.gpModeChanged.connect(_gpSyncToolBar)
	# Announce the document already loaded onto this canvas so bus subscribers (title bar,
	# project tree) bind to the correct graph in one place, and the dirty flag resets.
	# 通告本画布已载入的文档，使总线订阅者（标题栏、工程树）在一处绑定到正确的图，并重置脏标记。
	gpDocManager.gpSetGraph(gpCanvas.gpGraph)
	# Double click / context menu on a symbol asks for in-place geometry editing.
	# 图元上的双击 / 右键菜单会请求就地编辑几何。
	gpCanvas.gpSymbolEditRequested.connect(_gpOnSymbolEditRequested)
	# Promote selected annotation shapes into a real symbol: open the Make-Symbol dialog.
	# 把选中的注释图形提升为真正图元：打开「生成图元」对话框。
	gpCanvas.gpMakeSymbolRequested.connect(_gpOnMakeSymbolFromShapes)
	# (M2) gpModeChanged is now a bus event; the legacy canvas connection above would
	# fire the toolbar sync twice, so it is intentionally not connected here.
	# （M2）模式变化已改为总线事件；上面若再连旧画布信号会导致工具栏同步触发两次，
	# 故此处有意不再连接。
	# A brand-new sheet has an empty undo stack: make the 编辑 menu agree with it right away.
	# 新建图纸的撤销栈为空：让「编辑」菜单立即与之保持一致。
	_gpRefreshEditMenu()


# The active sheet changed (add / switch / close): refresh the inspector for the
# newly active selection.
# 活动图纸已切换（新建 / 切换 / 关闭）：刷新新活动页的选中属性。
func _gpOnActiveTabChanged() -> void:
	_gpRefreshSelection()
	_gpSyncToolBar()


# Fullscreen toggle from the center header: hide/show the side docks so the canvas
# fills the window, then re-apply the splits when leaving fullscreen.
# 中心头部触发的全屏切换：隐藏/显示左右停靠栏使画布占满窗口，退出时重新应用分隔。
func _gpOnFullscreen(gpOn: bool) -> void:
	gpLeftDock.visible = not gpOn
	gpRightDock.visible = not gpOn
	_gpApplySplits()

# ============================ localization refresh ============================
# ============================ 本地化刷新 ============================
# React to locale change: refresh all static UI text and current panels.
# 响应语言变化：刷新所有静态 UI 文本与当前面板。
func _gpOnLocaleChanged(_gpLocale: String) -> void:
	_gpRefreshStaticText()
	_gpOnStatus(gpLastStatus)
	_gpRefreshSelection()


# Refresh static labels that are not driven by individual widgets.
# 刷新那些不由单个控件自行驱动的静态标签。
func _gpRefreshStaticText() -> void:
	gpTabs.set_tab_title(0, I18n.gpTr("prop.title"))
	gpTabs.set_tab_title(1, I18n.gpTr("prop.info"))
	gpTabs.set_tab_title(2, I18n.gpTr("prop.doc"))
	gpDocLabel.text = I18n.gpTr("doc.info")
	_gpSetState(gpStateKey, gpStateArgs)


# ============================ left palette ============================
# ============================ 左侧图元库 ============================
# A symbol was picked from the left palette: switch to placement mode.
# 从左侧图元库选中图元：切换到放置模式。
func _gpOnSymbolPicked(gpTypeId: String) -> void:
	gpActiveCanvas().gpPendingDef = _gpDefFor(gpTypeId)
	gpActiveCanvas().gpSetMode(GPCanvas2D.GPMode.GP_SELECT)
	gpActiveCanvas().gpConnectFrom = ""
	var gpDef: GPSymbolDef = _gpDefFor(gpTypeId)
	var gpName: String = gpDef.gpDisplayName if gpDef else gpTypeId
	_gpSetState("status.symbol_picked", [gpName])


# A tool button was pressed: select / connect / custom.
# 工具按钮被按下：选择 / 连线 / 自定义。
func _gpOnToolSelected(gpType: String) -> void:
	if gpType == "select":
		gpActiveCanvas().gpSetMode(GPCanvas2D.GPMode.GP_SELECT)
		gpActiveCanvas().gpConnectFrom = ""
		_gpSetState("status.mode_select")
	elif gpType == "connect":
		gpActiveCanvas().gpSetMode(GPCanvas2D.GPMode.GP_CONNECT)
		_gpSetState("status.mode_connect")
	elif gpType == "custom":
		_gpSetState("status.custom_pending")


# A symbol was requested for deletion from the left library. The symbol may be placed on
# ANY sheet, so scan every canvas: if it is in use, ask for confirmation and cascade-remove
# the placed instances; otherwise delete it from the library directly.
# 左侧图元库请求删除某图元。该图元可能位于任意图纸，故扫描所有画布：若正在使用则确认后
# 级联清理画布实例；否则直接从图元库删除。
func _gpOnSymbolDeleteRequested(gpId: String) -> void:
	var gpTotal: int = 0
	for gpC in gpCenter.gpAllCanvases():
		if gpC.gpGraph != null:
			gpTotal += gpC.gpGraph.gpCountSymbolInstances(gpId)
	if gpTotal == 0:
		_gpDeleteSymbolAndRefresh(gpId)
		return
	_gpConfirmCascadeDelete(gpId, gpTotal)


# Ask the user to confirm deletion when the symbol is in use on the canvas. Cascade removal
# of placed instances happens only after the user confirms (no silent data loss).
# 图元正在画布使用时，征求删除确认。仅在用户确认后才级联清理画布实例（避免静默丢数据）。
func _gpConfirmCascadeDelete(gpId: String, gpTotal: int) -> void:
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("symbol_lib.delete_title")
	gpDlg.dialog_text = I18n.gpTr("symbol_lib.delete_used_confirm") % [gpTotal]
	# Confirmed carries no argument, so capture gpId in the callback. Free the dialog either way.
	# confirmed 信号不带参数，故在回调中捕获 gpId。无论确认或取消都释放对话框。
	gpDlg.confirmed.connect(func():
		_gpCascadeDeleteSymbol(gpId)
		gpDlg.queue_free()
	)
	gpDlg.canceled.connect(gpDlg.queue_free)
	add_child(gpDlg)
	gpDlg.popup_centered()


# Remove every placed instance of the symbol from all sheets (and their edges), then delete
# it from the library and refresh the palette.
# 从所有图纸移除该图元的全部已放置实例（及其连线），再从图元库删除并重渲染图元库。
func _gpCascadeDeleteSymbol(gpId: String) -> void:
	for gpC in gpCenter.gpAllCanvases():
		if gpC.gpGraph != null:
			var gpRemoved: int = gpC.gpGraph.gpRemoveSymbolInstances(gpId)
			if gpRemoved > 0:
				gpC.gpClearSelection()
				gpC.queue_redraw()
				# (M2) No manual emit any more: gpRemoveSymbolInstances emits the core graph
				# signal, and the canvas now binds that signal and funnels it to the bus.
				# Previously the UI had to remember to emit "on behalf of" the data layer.
				# （M2）不再手动发射：gpRemoveSymbolInstances 会发射 core 图信号，画布已绑定
				# 该信号并汇入总线。此前 UI 必须记得「代数据层」发射一次。
	_gpDeleteSymbolAndRefresh(gpId)


# Delete a symbol from the library and re-render the left palette. gpDefs shares identity
# with the live library array, so it already shrank; gpPopulate re-renders the views.
# 从图元库删除图元并重渲染左侧图元库。gpDefs 与活动库数组共享身份、已随之缩减；gpPopulate 重渲染。
func _gpDeleteSymbolAndRefresh(gpId: String) -> void:
	GPSymbolLibrary.gpDeleteDef(gpId)
	gpLeftDock.gpPopulate(gpDefs)
	_gpSetState("status.symbol_deleted", [gpId])


# ============================ canvas changes ============================
# ============================ 画布变化 ============================
# React to graph changes by refreshing the inspector for the current selection.
# 图变化时刷新当前选中的属性面板。
func _gpOnGraphChanged(_gpGraph: GPPIDGraph = null) -> void:
	_gpRefreshSelection()


# M2: selection is a first-class event again. Previously it was smuggled to the host inside
# the status snapshot, and _gpOnStatus had to diff the "selection" string to guess whether
# the inspector needed a refresh. The canvas now emits gpSelectionChanged explicitly.
# M2：选择重新成为一等事件。此前它被塞进状态快照，_gpOnStatus 必须比对 "selection"
# 字符串来猜测是否需要刷新属性面板；现在画布显式发射 gpSelectionChanged。
func _gpOnSelectionChanged(_gpIds: Array[String] = []) -> void:
	_gpRefreshSelection()


# Update the status bar from a canvas status snapshot.
# 根据画布状态快照更新状态栏。
func _gpOnStatus(gpInfo: Dictionary) -> void:
	# No active sheet yet (e.g. very first frame before the initial tab exists): keep
	# the last snapshot and skip, to avoid touching a null canvas.
	# 尚无活动图纸（如首帧初始标签建立前）：保留上次快照并跳过，避免触碰空画布。
	if gpActiveCanvas() == null:
		return
	gpLastStatus = gpInfo
	var gpSel: String = gpInfo.get("selection", "")
	gpSelLabel.text = I18n.gpTr("status.selected") % (gpSel if gpSel != "" else I18n.gpTr("status.none"))

	var gpWorld: Vector2 = gpInfo.get("world", Vector2.ZERO)
	gpCoordLabel.text = I18n.gpTr("status.coord") % [int(gpWorld.x), int(gpWorld.y)]

	var gpZoom: float = gpInfo.get("zoom", 1.0)
	gpZoomLabel.text = I18n.gpTr("status.zoom") % [int(gpZoom * 100.0)]
	# (M2) The old "diff the selection string, then refresh the inspector" block is gone:
	# selection changes now arrive as their own gpSelectionChanged event, so this handler
	# is once again ONLY about the status bar (its actual single responsibility).
	# （M2）原先「比对选中字符串再刷新属性面板」的代码块已删除：选中变化由独立的
	# gpSelectionChanged 事件送达，本处理函数恢复为只负责状态栏（真正的单一职责）。


# ============================ selection / inspector ============================
# ============================ 选中 / 属性面板 ============================
# Refresh the inspector and info tab for the currently selected node.
# 为当前选中节点刷新属性面板与信息标签页。
func _gpRefreshSelection() -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	# No active sheet (or nothing selected): clear the inspector.
	# 无活动图纸（或无选中）：清空属性面板。
	if gpCanvas == null:
		if gpInspector != null:
			gpInspector.gpShow(null, null)
		if gpInfoLabel != null:
			gpInfoLabel.text = I18n.gpTr("symbol_lib.no_selection")
		return
	var gpId: String = gpCanvas.gpSelectedId
	if gpId == "":
		# No node selected: before clearing the panel, show a single selected edge's form if any.
		# 未选中节点：在清空面板前，若单选了一条边则显示其表单。
		if gpCanvas.gpEdgeSel.size() == 1 and gpCanvas.gpGraph != null:
			var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpCanvas.gpEdgeSel[0])
			if gpEdge != null:
				gpInspector.gpShowEdge(gpEdge)
				var gpType: String = I18n.gpTr(GPEdgeStyle.gpLineTypeKey(gpEdge.gpKind, gpEdge.gpSignalType))
				gpInfoLabel.text = "%s：%s\n%s：%s" % [
					I18n.gpTr("info.id"), gpEdge.gpInstanceId,
					I18n.gpTr("edge.kind"), gpType]
				return
		gpInspector.gpShow(null, null)
		gpInfoLabel.text = I18n.gpTr("symbol_lib.no_selection")
		return

	var gpNode: GPPIDNode = _gpNodeFor(gpId)
	if gpNode == null:
		gpInspector.gpShow(null, null)
		gpInfoLabel.text = I18n.gpTr("symbol_lib.no_selection")
		return

	var gpDef: GPSymbolDef = _gpDefFor(gpNode.gpSymbolId)

	# Multi-select (M10): when every selected instance instantiates the SAME symbol, the panel
	# edits them as one batch. A mixed selection falls back to the primary node — writing a
	# property onto instances that never declared it would be silent data damage.
	# 多选（M10）：当所有选中实例实例化的是**同一**图元时，面板按批量编辑。
	# 混合选择回落到主节点 —— 把某属性写到从未声明它的实例上属于静默的数据破坏。
	var gpBatch: Array[GPPIDNode] = []
	var gpSameSymbol: bool = true
	for gpSelId in gpCanvas.gpSelection:
		var gpSelNode: GPPIDNode = _gpNodeFor(gpSelId)
		if gpSelNode == null:
			continue
		if gpSelNode.gpSymbolId != gpNode.gpSymbolId:
			gpSameSymbol = false
			break
		gpBatch.append(gpSelNode)
	if gpBatch.size() > 1 and gpSameSymbol:
		gpInspector.gpShowMulti(gpDef, gpBatch)
	else:
		gpInspector.gpShow(gpDef, gpNode)

	var gpCat: String = I18n.gpTr(gpDef.gpCategory) if gpDef else "—"
	var gpSize: String = str(gpDef.gpDefaultSize) if gpDef else "—"
	gpInfoLabel.text = "%s：%s\n%s：%s\n%s：%s\n%s：%s" % [
		I18n.gpTr("info.id"), gpId,
		I18n.gpTr("info.type"), gpNode.gpSymbolId,
		I18n.gpTr("info.category"), gpCat,
		I18n.gpTr("info.size"), gpSize]


# React to an attribute edit in the inspector, and to the batched form of the same edit.
# 响应属性面板中的属性编辑，以及同一次编辑的批量形式。
# Reserved keys (M10): "tag", "name:<locale>", "label_anchor"; anything else is a property key.
# The historical "label" key is still accepted as a tag, so an older panel keeps working.
# 保留键（M10）："tag"、"name:<语种>"、"label_anchor"；其余一律视为属性键。
# 历史上的 "label" 键仍按位号处理，使旧面板继续可用。
#
# M11: every one of these now travels through an undoable command on the edit service, so
# Ctrl+Z reverses it and the dirty flag is set exactly once (driven by gpGraphChanged).
# M11：它们现在都经编辑服务上的可撤销命令落地，故 Ctrl+Z 可撤销，
# 且脏标记恰好置一次（由 gpGraphChanged 驱动）。
func _gpOnAttrChanged(gpId: String, gpKey: String, gpVal) -> void:
	var gpIds: Array[String] = [gpId]
	_gpApplyAttr(gpIds, gpKey, gpVal)


func _gpOnBatchAttrChanged(gpIds: Array[String], gpKey: String, gpVal) -> void:
	_gpApplyAttr(gpIds, gpKey, gpVal)


# Route one edit (single or batched) to the matching undoable intent on the edit service.
# 把一次编辑（单选或批量）路由到编辑服务上对应的可撤销意图。
func _gpApplyAttr(gpIds: Array[String], gpKey: String, gpVal: Variant) -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null or gpIds.is_empty() or gpKey == "":
		return
	var gpActs: GPEditService = gpCanvas.gpActions
	var gpOk: bool = false
	if gpIds.size() == 1:
		var gpId: String = gpIds[0]
		if gpKey == "tag" or gpKey == "label":
			gpOk = gpActs.gpSetTag(gpId, str(gpVal))
		elif gpKey == "label_anchor":
			gpOk = gpActs.gpSetLabelAnchor(gpId, int(gpVal))
		elif gpKey.begins_with(GPInspector.GP_NAME_PREFIX):
			# "name:zh_CN" -> the locale is everything after the prefix.
			# "name:zh_CN" -> 前缀之后的部分即语种。
			gpOk = gpActs.gpSetName(gpId,
				gpKey.substr(GPInspector.GP_NAME_PREFIX.length()), str(gpVal))
		else:
			gpOk = gpActs.gpSetProperty(gpId, gpKey, gpVal)
	else:
		gpOk = gpActs.gpBatchSetProperty(gpIds, gpKey, gpVal)
	if gpOk:
		return
	# A refused edit explains itself (e.g. a duplicate tag); "nothing changed" stays silent.
	# 被拒绝的编辑会自己说明原因（如位号重复）；「无实际变化」则保持安静。
	if gpActs.gpLastRefusal != "":
		_gpSetState(gpActs.gpLastRefusal)


# Swap one instance onto another symbol (M10). uid, tag, property values and every
# connection survive; only gpSymbolId changes. Missing ports are downgraded to the node
# centre rather than severed, and the count is surfaced as a warning.
# 把某个实例换到另一个图元上（M10）。uid、位号、属性值与全部连接都保留，只有 gpSymbolId 变更。
# 缺失的端口降级到图元中心而非被切断，并把数量以警告形式告知用户。
func _gpOnSymbolSwap(gpNodeId: String, gpNewSymbolId: String) -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpNewDef: GPSymbolDef = _gpDefFor(gpNewSymbolId)
	if gpNewDef == null:
		_gpSetState("swap.no_such_symbol", [gpNewSymbolId])
		return
	if not gpCanvas.gpActions.gpReplaceSymbol(gpNodeId, gpNewDef):
		return
	gpCanvas.queue_redraw()
	_gpRefreshSelection()
	# "Allowed but warned" (decided 2026-09-09): the pipes still connect, they just lost the
	# exact nozzle they were drawn onto — the user decides whether to re-seat them.
	# 「允许但警告」（2026-09-09 拍板）：管路仍然连通，只是失去了原本吸附的管口
	# —— 是否重新落位由用户决定。
	var gpDowngraded: Array[String] = gpCanvas.gpActions.gpLastSwapWarning
	if gpDowngraded.size() > 0:
		_gpSetState("swap.warn_ports", [gpDowngraded.size()])
	else:
		_gpSetState("swap.done", [I18n.gpTr(gpNewDef.gpDisplayName, gpNewDef.gpDisplayName)])


# Hand the live library to the inspector so its "更换图元" dropdown follows every reload.
# 把活动库交给属性面板，使其「更换图元」下拉跟随每次库重载。
func _gpSyncInspectorDefs() -> void:
	if gpInspector != null:
		gpInspector.gpDefs = gpDefs


# M12: reconcile a freshly opened drawing against the CURRENT library. Renamed fields carry
# their values across; deleted fields leave ORPHANS that are kept (never swept) and merely
# counted, so the user decides whether to clean them.
# M12：把刚打开的图纸与**当前**图元库对账。改名字段带着取值迁移；删除字段留下孤儿值
# —— 保留（绝不自动清扫）并只做计数，是否清理由用户决定。
func _gpReconcileLibraryDrift(gpGraph: GPPIDGraph) -> void:
	if gpGraph == null:
		return
	var gpLive: Dictionary = GPPropertyResolver.gpFingerprintsFor(gpDefs)
	var gpDrift: Array[String] = GPPropertyResolver.gpDriftedSymbols(
		gpLive, gpGraph.gpSchemaFingerprints)
	# Adopt the live fingerprints: from here on this drawing is "as of this library".
	# 采用当前指纹：从此本图纸即「对应此版本的库」。
	gpGraph.gpSchemaFingerprints = gpLive.duplicate()
	if gpDrift.is_empty():
		return
	var gpMigrated: int = GPPropertyResolver.gpMigrateGraph(gpGraph, gpDefs)
	var gpOrphans: int = GPPropertyResolver.gpOrphanCount(gpGraph, gpDefs)
	_gpSetState("lib.drift", [gpDrift.size(), gpMigrated, gpOrphans])


# M12: drop the orphaned values of one instance, on the user's explicit request.
# M12：按用户明确请求，清除某个实例上的孤儿值。
func _gpOnCleanOrphans(gpNodeId: String) -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpNode: GPPIDNode = _gpNodeFor(gpNodeId)
	if gpNode == null:
		return
	var gpDef: GPSymbolDef = _gpDefFor(gpNode.gpSymbolId)
	var gpSchema: GPPropertySchema = gpDef.gpSchema if gpDef != null else null
	var gpRemoved: int = GPPropertyResolver.gpCleanOrphans(gpNode, gpSchema)
	if gpRemoved <= 0:
		return
	gpCanvas.gpGraph.gpGraphChanged.emit()
	gpCanvas.queue_redraw()
	_gpRefreshSelection()
	_gpSetState("lib.orphans_cleaned", [gpRemoved])


# React to an attribute edit in the edge form: route each key to the matching undoable
# intent on the edit service, then repaint and rebuild the form (so kind-dependent fields
# like signal_type vs dn/medium/insulation show or hide according to the new kind).
# 响应边表单中的属性编辑：把每个键路由到编辑服务上对应的可撤销意图，随后重绘并重建表单
#（使依赖类型的字段——signal_type 与 dn/medium/insulation——按新类型正确显隐）。
func _gpOnEdgeAttrChanged(gpEdgeId: String, gpKey: String, gpVal) -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	match gpKey:
		"kind":
			# A SIGNAL edge must carry a signal type; default to ELECTRIC on the form's behalf.
			# 信号线必带信号类型；代表单默认取 ELECTRIC。
			if gpVal == GPPIDEdge.GP_SIGNAL:
				gpCanvas.gpActions.gpSetEdgeKind(gpEdgeId, GPPIDEdge.GP_SIGNAL, "ELECTRIC")
			else:
				gpCanvas.gpActions.gpSetEdgeKind(gpEdgeId, gpVal)
		"signal_type":
			var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
			var gpKind: String = gpEdge.gpKind if gpEdge != null else GPPIDEdge.GP_SIGNAL
			gpCanvas.gpActions.gpSetEdgeKind(gpEdgeId, gpKind, gpVal)
		"tag":
			gpCanvas.gpActions.gpSetEdgeTag(gpEdgeId, str(gpVal))
		_:
			gpCanvas.gpActions.gpSetEdgeAttr(gpEdgeId, gpKey, gpVal)
	gpCanvas.queue_redraw()
	# Re-show the form so kind-dependent fields update (e.g. switching to SIGNAL hides dn/medium).
	# 重新显示表单，使依赖类型的字段随新类型更新（如切到信号线时隐藏 dn/medium）。
	_gpRefreshSelection()


# ============================ menu ============================
# ============================ 菜单 ============================
# Dispatch menu actions.
# 分发菜单动作。
func _gpOnMenu(gpAction: String) -> void:
	match gpAction:
		"file_new", "edit_clear":
			gpActiveGraph().gpNodes.clear()
			gpActiveGraph().gpEdges.clear()
			gpActiveGraph().gpShapes.clear()
			gpActiveCanvas().gpNextId = 1
			gpActiveCanvas().gpClearSelection()
			gpActiveCanvas().gpConnectFrom = ""
			gpActiveCanvas().gpPendingDef = null
			gpActiveCanvas().queue_redraw()
			_gpSetState("status.cleared")
		"file_save":
			gpFileCoord.gpSaveProject(false)
		"file_save_as":
			gpFileCoord.gpSaveProject(true)
		"file_open":
			gpFileCoord.gpOpenProject()
		"file_import":
			gpFileCoord.gpImportProject()
		"file_quit":
			# Route through the SAME close guard as the OS window-close button so the
			# unsaved-changes dialog behaves identically whether the user clicks the red X
			# or picks Quit from the menu. Used to diagnose whether the red X reaches
			# NOTIFICATION_WM_CLOSE_REQUEST at all.
			# 走与 OS 关闭按钮**完全相同**的关闭护栏，使未保存对话框在「点红 X」与
			# 「菜单退出」两种入口下表现一致。用于排查红 X 是否真的触发了关闭通知。
			gpFileCoord.gpOnCloseRequested()
		"export_project":
			gpFileCoord.gpPickExportPath("project")
		"export_library":
			gpFileCoord.gpPickExportPath("library")
		"export_config":
			gpFileCoord.gpPickExportPath("config")
		"view_zoom_in":
			gpActiveCanvas().gpZoomStep(1.0)
		"view_zoom_out":
			gpActiveCanvas().gpZoomStep(-1.0)
		"view_fit":
			gpActiveCanvas().gpResetView()
			_gpSetState("status.view_reset")
		"edit_delete":
			if gpActiveCanvas().gpSelectedId != "":
				_gpDeleteSelected()
		"edit_undo":
			_gpMenuUndo()
		"edit_redo":
			_gpMenuRedo()
		"tool_settings":
			_gpOpenSettings()
		"project_tag_rules":
			_gpOpenTagRuleDialog()
		_:
			_gpSetState("status.feature_todo", [gpAction])


# Menu 项目 / 位号编号规则 (M9b). The dialog edits a copy and hands it back; renumbering
# is a separate, confirmed, single-undo-step operation.
# 菜单「项目 / 位号编号规则」（M9b）。对话框编辑副本并交回；重编号是独立的、
# 需确认的、单撤销步操作。
func _gpOpenTagRuleDialog() -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null:
		return
	var gpDlg: GPTagRuleDialog = GPTagRuleDialog.new()
	add_child(gpDlg)
	gpDlg.gpRulesApplied.connect(_gpOnTagRulesApplied)
	gpDlg.gpShowRules(gpCanvas.gpActions.gpTagRules(), gpCanvas.gpGraph.gpNodes.size())
	# Free the dialog on close either way; it is a one-shot editor, not a panel.
	# 无论何种关闭方式都释放对话框：它是一次性编辑器，而非常驻面板。
	gpDlg.close_requested.connect(gpDlg.queue_free)
	gpDlg.confirmed.connect(gpDlg.queue_free)
	gpDlg.canceled.connect(gpDlg.queue_free)


# Apply the edited rules, then optionally renumber (with a confirmation, because a tag ends
# up on a physical nameplate and in the DCS point list).
# 应用编辑后的规则；可选地随后重编号（需确认，因为位号会落到现场标牌与 DCS 点表上）。
func _gpOnTagRulesApplied(gpRules: GPProjectTagRules, gpRenumber: bool) -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null:
		return
	gpCanvas.gpActions.gpSetTagRules(gpRules)
	if not gpRenumber:
		_gpSetState("tag_rule.applied")
		return
	_gpConfirmRenumberTags()


# Ask before renumbering: the change is reversible in the app but NOT on a printed
# nameplate, so the user must see the count first.
# 重编号前先询问：本改动在软件内可撤销，但在已印好的标牌上不可撤销，
# 故必须先让用户看到数量。
func _gpConfirmRenumberTags() -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null:
		return
	var gpCount: int = gpCanvas.gpGraph.gpNodes.size()
	if gpCount == 0:
		_gpSetState("tag_rule.applied")
		return
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("tag_rule.confirm_title")
	gpDlg.dialog_text = I18n.gpTr("tag_rule.renumber_confirm") % [gpCount]
	add_child(gpDlg)
	gpDlg.confirmed.connect(func():
		_gpDoRenumberTags()
		gpDlg.queue_free())
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.popup_centered()


# Run the renumber command and report how many tags changed.
# 执行重编号命令并报告变动了多少位号。
func _gpDoRenumberTags() -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null:
		return
	if not gpCanvas.gpActions.gpRenumberTags():
		_gpSetState("tag_rule.applied")
		return
	var gpChanged: int = GPTagRuleService.gpChangedCount(gpCanvas.gpActions.gpLastTagMapping)
	_gpSetState("tag_rule.renumbered", [gpChanged])
	gpCanvas.queue_redraw()
	_gpRefreshSelection()


# Refresh 编辑 menu items against the live undo stack, called just before the popup
# opens. The menu bar itself never learns what a canvas is; it only asks.
# 在菜单展开前依据实时撤销栈刷新「编辑」菜单项。菜单栏本身不需要知道画布是什么，
# 它只是发问。
func _gpOnMenuOpening(gpTitleKey: String) -> void:
	if gpTitleKey != "menu.edit":
		return
	_gpRefreshEditMenu()


# Sync 撤销 / 重做 enabled state with the active sheet. No sheet means nothing to undo.
# 同步「撤销 / 重做」的可用状态与活动图纸。没有图纸即无可撤销。
func _gpRefreshEditMenu() -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	var gpCanUndo: bool = gpCanvas != null and gpCanvas.gpCanUndo()
	var gpCanRedo: bool = gpCanvas != null and gpCanvas.gpCanRedo()
	gpMenuBar.gpSetActionEnabled("edit_undo", gpCanUndo)
	gpMenuBar.gpSetActionEnabled("edit_redo", gpCanRedo)


# Menu 编辑 / 撤销. The canvas owns the stack, so all this does is ask and report.
# 菜单「编辑 / 撤销」。撤销栈归画布所有，故此处只负责发问与报告。
func _gpMenuUndo() -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null:
		return
	if gpCanvas.gpUndo():
		_gpSetState("status.undone")
	else:
		_gpSetState("status.nothing_to_undo")
	_gpRefreshEditMenu()


# Menu 编辑 / 重做.
# 菜单「编辑 / 重做」。
func _gpMenuRedo() -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null:
		return
	if gpCanvas.gpRedo():
		_gpSetState("status.redone")
	else:
		_gpSetState("status.nothing_to_redo")
	_gpRefreshEditMenu()


# ============================ close guard ============================
# ============================ 关闭拦截 ============================
# Intercept the window close so an unsaved drawing is never lost silently.
# 拦截窗口关闭，使未保存的图纸永不静默丢失。
# WHY THIS IS NEEDED / 为何需要：saving is explicit (ADR-7: Ctrl+S is the only save path),
# which means a user who simply forgets to press it would lose everything with no warning.
# The guard is the safety net that makes an explicit-save model safe to adopt.
# 保存是显式的（ADR-7：Ctrl+S 是唯一保存路径），这意味着仅仅**忘记按**的用户会
# 毫无警告地丢失全部内容。这道护栏正是让「显式保存」模型可以被安全采用的安全网。
#
# NOTE / 注：the close is intercepted through get_window().close_requested (wired in
# _ready), NOT _notification(NOTIFICATION_WM_CLOSE_REQUEST). On a Control scene root the
# WM notification is not reliably delivered in Godot 4, so the dialog would silently fail
# to appear. The signal fires on the real Window and is the canonical interception point.
# 关闭经由 get_window().close_requested（在 _ready 接线）拦截，而非
# _notification(NOTIFICATION_WM_CLOSE_REQUEST)。在 Control 场景根上该 WM 通知在 Godot 4
# 中不可靠地送达，对话框会静默不出现。信号在真正的 Window 上触发，是权威拦截点。


# Close path: clean -> quit immediately; dirty -> ask, never decide for the user.
# 关闭路径：干净 -> 立即退出；脏 -> 询问，绝不替用户决定。
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
	var gpDlg: GPSettingsDialog = (load("res://scenes/settings_dialog.tscn") as PackedScene).instantiate()
	add_child(gpDlg)
	# gpPopupOverHost() sizes the dialog against the area that actually contains it; the bare
	# popup_centered() ignores `size` and can place an oversized dialog at a negative position.
	# gpPopupOverHost() 依据真正容纳它的区域取尺寸；裸 popup_centered() 会忽略 `size`，
	# 并可能把超大对话框放到负坐标。
	gpDlg.gpPopupOverHost()


# ============================ drawing toolbar ============================
# ============================ 绘图工具栏 ============================
# Build the Ribbon command bar and insert it between the menu bar and the body in the
# root VBox (the same slot the old DrawToolBar occupied). The Ribbon emits
# gpActionTriggered, which we route to the existing toolbar handler. To REVERT to the
# previous flat toolbar, rename this back to _gpBuildToolBar and restore that builder.
# 构建 Ribbon 命令栏并插入根 VBox 的菜单栏与主体之间（即原 DrawToolBar 的位置）。
# Ribbon 发射 gpActionTriggered，我们将其路由到既有的工具栏处理器。要回退旧平铺工具栏，
# 把本函数改回 _gpBuildToolBar 并恢复其构建体即可。
func _gpBuildRibbon() -> void:
	var gpVLayout: VBoxContainer = $VLayout
	gpRibbon = GPPIDRibbon.new()
	gpRibbon.name = "Ribbon"
	gpRibbon.gpActionTriggered.connect(_gpOnToolBarPressed)
	gpVLayout.add_child(gpRibbon)
	gpVLayout.move_child(gpRibbon, 1)
	_gpSyncToolBar()


# 视觉分层（精致化）：
# 右栏 TabContainer 背景（左边界交由顶层叠加层画发丝线，避免双线）；tab 按钮统一 DOCK 色，
# 未选中/hover 也带 1px 发丝底线，使选中 accent 成为"高亮"而非孤零零的粗线；
# 整排 tab 统一 1px 发丝底线；选中态靠 accent 颜色 + 略亮背景区分，不发粗线。
# 三栏分隔条引擎 grabber 设为透明（视觉交给 GPOverlayChrome）。
# The whole tab row shares a 1px hairline; the selected tab is told apart by accent
# colour + a slightly lighter fill — no thick line. The splitter grabber is made
# transparent (visuals delegated to GPOverlayChrome).
func _gpStyleChrome() -> void:
	if gpTabs != null:
		# 右边界接缝由 GPOverlayChrome 统一绘制，这里不再重复画左边框。
		gpTabs.add_theme_stylebox_override("panel",
			GPChromeStyle.gpStyleFor(GPChromeStyle.GP_DOCK_BG, 0))
		# 未选中 / hover 也带 1px 发丝底线，整排 tab 干净统一。
		var gpTabBg: StyleBoxFlat = GPChromeStyle.gpStyleFor(GPChromeStyle.GP_DOCK_BG, GPChromeStyle.SIDE_BOTTOM)
		gpTabs.add_theme_stylebox_override("tab_unselected", gpTabBg)
		gpTabs.add_theme_stylebox_override("tab_hovered", gpTabBg)
		# 选中态：1px accent 底线（与未选中同厚，仅颜色不同）+ 略亮背景，细腻区分。
		# Selected: a 1px accent underline (same thickness as unselected, colour only
		# differs) plus a slightly lighter fill — delicate distinction, no heavy line.
		var gpTabSel: StyleBoxFlat = StyleBoxFlat.new()
		gpTabSel.bg_color = Color(0.118, 0.131, 0.163)
		gpTabSel.border_color = GPChromeStyle.GP_ACCENT
		gpTabSel.border_width_bottom = 1
		gpTabs.add_theme_stylebox_override("tab_selected", gpTabSel)
	if gpBodySplit != null:
		# 引擎 grabber 透明：拖拽仍可用，但不再画粗亮块；接缝发丝线 + 悬停高亮
		# 由 GPOverlayChrome（顶层叠加层）绘制，细腻且不双重描边。
		var gpDrag: StyleBoxFlat = StyleBoxFlat.new()
		gpDrag.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		gpBodySplit.add_theme_stylebox_override("dragger", gpDrag)
		var gpGrab: StyleBoxFlat = StyleBoxFlat.new()
		gpGrab.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		gpBodySplit.add_theme_stylebox_override("grabber", gpGrab)


# Add one toolbar button. gpToggle buttons keep their pressed highlight and are tracked for sync.
# 添加一个工具栏按钮。gpToggle 按钮保持按下高亮并被记录以便同步。
func _gpAddToolBtn(gpAction: String, gpKey: String, gpToggle: bool) -> Button:
	var gpBtn: Button = Button.new()
	gpBtn.text = I18n.gpTr(gpKey)
	gpBtn.tooltip_text = I18n.gpTr(gpKey)
	gpBtn.focus_mode = Control.FOCUS_NONE
	if gpToggle:
		gpBtn.toggle_mode = true
	gpBtn.pressed.connect(_gpOnToolBarPressed.bind(gpAction))
	gpToolBar.add_child(gpBtn)
	if gpToggle:
		gpToolBtns[gpAction] = gpBtn
	return gpBtn


# Add a thin vertical separator between tool groups.
# 在工具组之间加一条细竖直分隔线。
func _gpAddSep() -> void:
	var gpSep: VSeparator = VSeparator.new()
	gpToolBar.add_child(gpSep)


# Toolbar button handler: select / connect / drawing tools switch the canvas mode; the
# "New Symbol…" button opens the isolation editor for advanced symbol authoring.
# 工具栏按钮处理：选择/连线/绘图工具切换画布模式；「新建图元…」按钮打开隔离编辑器用于高级图元创作。
func _gpOnToolBarPressed(gpAction: String) -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null:
		return
	match gpAction:
		"select":
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_SELECT)
			gpCanvas.gpConnectFrom = ""
			_gpSetState("status.mode_select")
		"connect":
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_CONNECT)
			_gpSetState("status.mode_connect")
		"line":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_LINE)
			_gpSetState("status.mode_line")
		"circle":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_CIRCLE)
			_gpSetState("status.mode_circle")
		"rect":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_RECT)
			_gpSetState("status.mode_rect")
		"polyline":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_POLYLINE)
			_gpSetState("status.mode_polyline")
		"pipe":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_PIPE)
			_gpSetState("status.mode_pipe")
		"signal":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_SIGNAL)
			_gpSetState("status.mode_signal")
		# ---- view / edit commands surfaced on the Ribbon (P0) ----
		# ---- Ribbon 上暴露的视图/编辑命令（P0） ----
		"view_zoom_in":
			gpCanvas.gpZoomStep(1.0)
		"view_zoom_out":
			gpCanvas.gpZoomStep(-1.0)
		"view_fit":
			gpCanvas.gpResetView()
			_gpSetState("status.view_reset")
		"edit_undo":
			_gpMenuUndo()
		"edit_redo":
			_gpMenuRedo()
		"edit_delete":
			_gpDeleteSelected()
		"tool_settings":
			_gpOpenSettings()
	_gpSyncToolBar()


# Highlight the toggle button matching the active canvas mode (select / connect / draw tools).
# The optional gpMode parameter lets this serve as the gpModeChanged signal callback (1 arg)
# while remaining callable with 0 args elsewhere. When gpMode < 0 the live canvas mode is read.
# 高亮与当前画布模式匹配的开关按钮（选择 / 连线 / 绘图工具）。可选 gpMode 参数使其既能作为
# gpModeChanged 信号的 1 参回调，又能在别处 0 参调用；gpMode < 0 时读取画布实时模式。
func _gpSyncToolBar(gpMode: int = -1) -> void:
	# The Ribbon owns the mode highlight now; delegate to it (P0 / ADR-UI-01).
	# 模式高亮现由 Ribbon 负责，委托给它（P0 / ADR-UI-01）。
	if gpRibbon != null:
		var gpCanvas: GPCanvas2D = gpActiveCanvas()
		if gpMode < 0:
			gpMode = GPCanvas2D.GPMode.GP_SELECT if gpCanvas == null else gpCanvas.gpMode
		gpRibbon.gpSyncMode(gpMode)
		return
	if gpToolBar == null:
		return
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpMode < 0:
		gpMode = GPCanvas2D.GPMode.GP_SELECT if gpCanvas == null else gpCanvas.gpMode
	for gpAct in gpToolBtns.keys():
		var gpBtn: Button = gpToolBtns[gpAct]
		var gpM: int = _gpModeForAction(gpAct)
		gpBtn.button_pressed = (gpM >= 0 and gpMode == gpM)


# Map a toolbar action to its canvas mode, or -1 for non-mode buttons (e.g. "new").
# 把工具栏动作映射到对应画布模式；非模式按钮（如「新建」）返回 -1。
func _gpModeForAction(gpAction: String) -> int:
	match gpAction:
		"select":
			return GPCanvas2D.GPMode.GP_SELECT
		"connect":
			return GPCanvas2D.GPMode.GP_CONNECT
		"line":
			return GPCanvas2D.GPMode.GP_DRAW_LINE
		"circle":
			return GPCanvas2D.GPMode.GP_DRAW_CIRCLE
		"rect":
			return GPCanvas2D.GPMode.GP_DRAW_RECT
		"polyline":
			return GPCanvas2D.GPMode.GP_DRAW_POLYLINE
		"pipe":
			return GPCanvas2D.GPMode.GP_PIPE
		"signal":
			return GPCanvas2D.GPMode.GP_SIGNAL
	return -1


# ============================ in-place symbol editing ============================
# ============================ 就地图元编辑 ============================
# Open the isolation layer for one symbol type directly over the active canvas.
# 为某个图元类型在活动画布正上方打开隔离层。
# Open the "Make Symbol" dialog pre-loaded with the annotation-shape geometry the user promoted
# from the main canvas. On confirm it registers / persists a GPSymbolDef (same display-name ->
# overwrite existing, else new) and refreshes the palette + canvas.
# 打开「生成图元」对话框，预装主画布上被选中的注释图形几何。确定后注册并持久化一个
# GPSymbolDef（显示名相同则覆盖已有图元，否则新建）并刷新图元库与画布。
func _gpOnMakeSymbolFromShapes(gpDraft: Dictionary) -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null or gpCenter == null:
		return
	# gpOpen adds the dialog as a child Window, so hand it the actual main Window (not this Control).
	# gpOpen 会把对话框作为子 Window 添加，故传入真正的主 Window（而非本 Control）。
	var gpWin: Window = get_window()
	if gpWin == null:
		return
	_gpOpenMakeSymbolDialog(gpDraft, "", true)


# Open the Make-Symbol dialog converged from the two handlers (promote-from-shapes and
# edit-existing) that previously duplicated gpOpen + gpMadeSymbol.connect. gpOpen adds the
# dialog as a child Window, so it is handed the actual main Window (not this Control). On confirm
# the shared _gpOnSymbolSaved refreshes the palette + canvas.
# 打开「生成图元」对话框的收敛助手——统一了「从图形提升」与「编辑已有图元」两个处理器此前重复的
# gpOpen + gpMadeSymbol.connect 逻辑。gpOpen 把对话框作为子 Window 添加，故传入真正的主 Window
# （而非本 Control）。确定后由共享的 _gpOnSymbolSaved 刷新图元库与画布。
func _gpOpenMakeSymbolDialog(gpDraft: Dictionary, gpInitialName: String, gpAllowOverwrite: bool, gpInitialPorts: Array[GPPort] = [], gpInitialDisplay: String = "") -> void:
	var gpWin: Window = get_window()
	if gpWin == null or gpCenter == null:
		return
	var gpDlg: GPMakeSymbolDialog = GPMakeSymbolDialog.gpOpen(gpWin, gpDraft, gpInitialName, gpAllowOverwrite, gpInitialPorts, gpInitialDisplay)
	if gpDlg == null:
		return
	gpDlg.gpMadeSymbol.connect(_gpOnSymbolSaved)


func _gpOnSymbolEditRequested(gpSymbolId: String) -> void:
	# The in-place symbol editor was removed (P4 refactor). Editing an existing placed symbol now
	# re-opens the Make-Symbol dialog seeded with that symbol's geometry; confirming under the same
	# display name overwrites the def (built-ins derive a C-rule copy per decision D3).
	# 就地图元编辑器已移除（P4 重构）。编辑已放置图元改为用「生成图元」对话框带入该图元几何；
	# 以相同显示名确定即覆盖该 def（内置图元按决策 D3 派生 C 规则副本）。
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null or gpCenter == null:
		return
	var gpDef: GPSymbolDef = _gpDefFor(gpSymbolId)
	if gpDef == null:
		return
	# D3: built-in symbols are read-only → derive a copy under a fresh C-rule id
	# (C<CATEGORY><nnn>) so the original ISO glyph is never overwritten or re-fit.
	# 决策 D3：内置图元只读 → 以新的 C 规则 id（C<类别码><三位序号>）派生副本，
	# 绝不覆盖/重拟合原始 ISO 图元。
	var gpEditDef: GPSymbolDef = gpDef
	var gpAllowOverwrite: bool = true
	if gpDef.gpBuiltin:
		var gpDerivedId: String = GPSymbolLibrary.gpAllocateCustomId(gpDef.gpCategory)
		if gpDerivedId == "":
			push_warning("GPMainWindow: category %s has no free C-rule id left" % gpDef.gpCategory)
			return
		var gpCanon: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(
			GPSymbolNormalizer.gpDenormalizeSymbol(gpDef), gpDef.gpCategory, {})
		gpCanon.gpId = gpDerivedId
		gpCanon.gpBuiltin = false
		GPSymbolLibrary.gpRegisterDefs([gpCanon])
		gpDefs = GPSymbolLibrary.gpDefaultDefs()
		_gpSyncInspectorDefs()
		gpLeftDock.gpPopulate(gpDefs)
		gpCenter.gpSetDefs(gpDefs)
		gpEditDef = gpCanon
		gpAllowOverwrite = false
	# Convert the def's EDITABLE shape spec (raw control points + Bézier handles) into the dialog
	# draft, so editing an existing curved symbol keeps its curve control points. gpShapeSpec() is
	# the flattened render spec (painter); it would drop handles and degrade a curve to straight
	# segments. gpEditSpec() is the lossless inverse of what the dialog re-imports via gpFromSpec.
	# 把 def 的「可编辑」形状规格（原始控制点 + 贝塞尔手柄）转成对话框 draft，使编辑已有曲线图元时
	# 保留其曲线控制点。gpShapeSpec() 是给 painter 打平的渲染 spec，会丢手柄、把曲线退化成直线；
	# gpEditSpec() 是无损的，能被对话框经 gpFromSpec 无损还原。
	var gpDraft: Dictionary = GPShapeSpec.gpEditSpec(gpEditDef.gpShapes)
	gpDraft.erase("box")
	# Carry the symbol's current ports into the editor so editing preserves connection points
	# instead of silently dropping them (previously the dialog always started with zero ports).
	# 把图元当前端口带入编辑器，使编辑保留连接点而非静默丢弃（此前对话框总是从零端口起步）。
	# Seed the ID field with the symbol's real ID (uniqueness is judged by id, NOT display
	# name) and prefill the display-name field separately. A built-in's display name is an
	# i18n key (sym./iso. prefixed) — translate it so the derived copy stores human text.
	# 标识框预填图元真实 id（唯一性以 id 判定，非显示名），显示名单独预填。内置图元的
	# 显示名是 i18n 键（sym./iso. 前缀），先翻译，使派生副本保存为人类可读文本。
	var gpEditDisplay: String = gpEditDef.gpDisplayName
	if gpEditDisplay.begins_with("sym.") or gpEditDisplay.begins_with("iso."):
		gpEditDisplay = I18n.gpTr(gpEditDisplay)
	_gpOpenMakeSymbolDialog(gpDraft, gpEditDef.gpId, gpAllowOverwrite, gpEditDef.gpPorts, gpEditDisplay)


# The edited geometry was re-registered under the SAME id, so every placed instance repaints.
# 编辑后的几何已按同一 id 重新注册，故所有已放置实例都会重绘。
# gpDefaultDefs() returns a stable-identity array that gpRegisterDefs patched in place, so the
# canvases already see the new object; only the palette and the paint need refreshing.
# gpDefaultDefs() 返回的数组身份稳定且已被 gpRegisterDefs 就地修补，故各画布已看到新对象；
# 只需刷新图元库与重绘。
func _gpOnSymbolSaved(gpSymbolId: String) -> void:
	gpDefs = GPSymbolLibrary.gpDefaultDefs()
	_gpSyncInspectorDefs()
	gpLeftDock.gpPopulate(gpDefs)
	gpCenter.gpSetDefs(gpDefs)
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas != null:
		gpCanvas.queue_redraw()
	_gpRefreshSelection()
	_gpSetState("status.symbol_saved", [gpSymbolId])


# Delete every selected node and any edges connected to them (menu 编辑 / 删除).
# 删除所有选中节点及其关联的边（菜单「编辑 / 删除」）。
# Delegated to the canvas so the multi-selection state lives in exactly one place.
# 委托给画布执行，使多选状态只有一处真相来源。
func _gpDeleteSelected() -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null:
		return
	gpCanvas.gpDeleteSelection()


# ============================ state helper ============================
# ============================ 状态栏辅助 ============================
# Set the status bar text by i18n key and optional format arguments.
# 通过 i18n 键与可选格式化参数设置状态栏文本。
func _gpSetState(gpKey: String, gpArgs: Array = []) -> void:
	gpStateKey = gpKey
	gpStateArgs = gpArgs
	var gpFmt: String = I18n.gpTr(gpKey)
	gpStateLabel.text = gpFmt % gpArgs if gpArgs.size() > 0 else gpFmt


# ============================ HiDPI / multi-monitor ============================
# ============================ HiDPI / 多显示器 ============================
# Apply the OS screen scale to Godot's content scale factor and refresh fonts.
# 将窗口内容缩放比固定为 1.0（正确适配 Retina/多显示器）并刷新字体。
func _gpApplyDpiScale() -> void:
	# KEEP content_scale_factor at 1.0. Godot 4 on macOS ALREADY reports window geometry in
	# LOGICAL POINTS and renders the backing store at the display's native pixel ratio (2x on
	# Retina). Forcing content_scale_factor = screen_get_scale() (=2.0 here) DOUBLE-COUNTS that
	# Retina scale: Godot then treats the visible logical viewport as design/csf = 1600/2 = 800
	# wide, so the whole 1600-wide UI is drawn 2x too large and clipped (measured: host window
	# 3024x1890 px @ csf 2.0 yields a logical viewport of only ~800x500). With csf pinned to 1.0
	# and stretch mode "canvas_items", the 1600x900 design canvas maps 1:1 in logical points and
	# the engine scales it to fill the maximized window, so menu / docks / property / status bar
	# keep correct proportions on ANY monitor / DPI. Text crispness is handled by the fonts'
	# oversampling (4.0) in their .import settings, not by content_scale_factor.
	# 把 content_scale_factor 固定为 1.0。Godot 4 在 macOS 上已用「逻辑点」报告窗口几何，并以显示器的
	# 原生像素比（Retina 为 2x）渲染背板。若再把 content_scale_factor 设成 screen_get_scale()（此处
	# =2.0），就会把 Retina 缩放算两遍：Godot 会把可见逻辑视口当作 design/csf = 1600/2 = 800 宽，
	# 整幅 1600 宽的界面被放大 2 倍并裁切（实测：宿主窗 3024x1890px、csf 2.0 时逻辑视口仅约 800x500）。
	# 把 csf 钉在 1.0 并配合 stretch 模式 canvas_items，1600x900 设计画布以 1:1 逻辑点映射，由引擎缩放到
	# 铺满的最大化窗口，从而在任何显示器 / DPI 下菜单 / 停靠栏 / 属性 / 状态栏比例都正确。文字清晰由
	# 字体的 oversampling(4.0)（见 .import）保证，而非 content_scale_factor。
	var gpWin: Window = get_window()
	if gpWin == null:
		return
	# Pin content_scale_factor to 1.0 (pure decision in GPDpiWindow — see that module for the
	# Retina double-scale rationale). 把 content_scale_factor 钉回 1.0（纯决策在 GPDpiWindow，
	# Retina 双重缩放原因见该模块注释）。
	GPDpiWindow.gpPinContentScale(gpWin)
	# Re-apply the UI theme so controls relayout at the new monitor's density.
	# 重新应用界面主题，使控件按新显示器密度重排。
	Settings.gpApplyFontSize()


# Open the main window maximized so the 1600x900 design canvas (stretch mode "canvas_items")
# is scaled by the engine to fill the real window. Maximize rather than a hand-computed size so
# the OS owns the geometry on every monitor / DPI combination: the window always fills the usable
# screen and the UI scale therefore tracks the monitor. Re-maximizing after a cross-monitor drag
# keeps it filling the newly-entered screen too.
# 将主窗口最大化，使 1600x900 的设计画布（stretch 模式 canvas_items）由引擎缩放铺满真实窗口。
# 用「最大化」而非手算尺寸，让操作系统在每台显示器 / 每种 DPI 组合下决定几何：窗口始终铺满
# 可用屏幕，UI 缩放比随之跟随显示器。跨屏拖拽后再次最大化，也能让窗口继续铺满新进入的屏幕。
func _gpOpenMaximized(gpWin: Window) -> void:
	if gpWin == null:
		return
	# Only maximize when the window isn't already maximized / fullscreen (e.g. the OS restored a
	# prior maximized state or the user is toggling fullscreen), to avoid fighting the OS. The
	# decision is the pure predicate in GPDpiWindow.
	# 仅在窗口尚未最大化 / 全屏时才最大化（例如 OS 已恢复上次最大化状态、或用户正切换全屏），
	# 以免与操作系统争夺状态。判定收敛到 GPDpiWindow 的纯谓词。
	if not GPDpiWindow.gpShouldMaximize(gpWin):
		return
	gpWin.mode = Window.MODE_MAXIMIZED


# Detect when the window is dragged to another monitor.
# 检测窗口被拖到另一台显示器时。
func _gpOnWindowChanged() -> void:
	var gpWin: Window = get_window()
	if gpWin == null:
		return
	var gpScreen: int = gpWin.current_screen
	if gpScreen == gpLastScreen:
		return
	gpLastScreen = gpScreen
	_gpApplyDpiScale()
	# After the window lands on a new monitor, re-maximize so it keeps filling that screen and the
	# canvas_items stretch re-scales the design to the new monitor's size / DPI.
	# 窗口落到新显示器后再次最大化，使其继续铺满该屏，canvas_items 拉伸随之按新屏尺寸 / DPI 重缩放。
	_gpOpenMaximized(gpWin)


# Responsive layout: when the window is resized we re-apply the splits so the
# canvas (center) keeps absorbing the new width. The dock widths themselves stay
# fixed (snapped to their floor when auto-scale is on, or kept at the user-dragged
# size when off). Depends only on width, so a pure height change leaves docks
# untouched. The UI font is never scaled (see settings.gd).
# 响应式布局：窗口缩放时重新应用分隔，使画布（中间）持续吸收新增宽度。停靠栏宽度
# 始终使用当前存储的像素值（启动时为下限，拖拽后为用户设定值）。只依赖宽度，
# 故纯高度变化不改变停靠栏。界面字号不随窗口缩放（见 settings.gd）。
func _gpOnResized() -> void:
	var gpWin: Window = get_window()
	if gpWin == null:
		return
	var gpW: int = int(gpWin.size.x)
	if gpW <= 0:
		return
	if gpPrevWidth <= 0:
		gpPrevWidth = gpW
		return
	if gpW == gpPrevWidth:
		return
	gpPrevWidth = gpW
	# Defer the split re-apply so HSplitContainer has finished its own layout pass
	# and gpBodySplit.size.x reflects the new window width. Applying immediately
	# uses the stale body width and makes the docks stick to the old offsets.
	# 延迟重应用分隔，让 HSplitContainer 先完成自身布局，使 gpBodySplit.size.x 反映新窗口宽度。
	# 立即应用会使用旧的主体宽度，导致停靠栏粘在老偏移上。
	call_deferred("_gpApplySplits")


# Pin both docks to their stored pixel widths and let the canvas (center) absorb
# everything else. No window-ratio is involved, so resizing only changes the center
# pane. The stored widths are seeded from the floors at startup and updated by drag.
# Idempotent: given the same dock widths it always yields the same offsets.
# 将左右两栏钉到当前存储的像素宽度，画布（中间）吸收其余全部空间。不涉及窗口比例，
# 故缩放只改变中间栏。存储宽度在启动时以下限初始化、拖拽时更新。幂等：相同停靠栏
# 宽度必得相同偏移。
func _gpApplySplits() -> void:
	if gpBodySplit == null:
		return
	var gpBW: float = gpBodySplit.size.x
	if gpBW <= 1.0:
		return
	# Use the session-only pixel widths. They start at the floors on launch and are
	# overwritten by splitter drags, so the user's layout survives every resize until
	# the next restart (when the script variables reset to the floors again).
	# 使用仅会话有效的像素宽度。启动时为下限，拖拽分隔条后被覆盖，因此用户布局在
	# 每次缩放时都保持，直到下次重启（脚本变量重新回退到下限）。
	var gpL: float = gpLeftWidthPx
	var gpR: float = gpRightWidthPx
	# Pin the palette grid's minimum width to the target left width FIRST, so the
	# left dock's combined minimum equals gpL and the splitter is never clamped
	# above gpL (otherwise a wide grid min would lock the dock at its old width).
	# 先把图元网格最小宽钉到目标左栏宽，使左停靠栏合并最小宽等于 gpL、分隔条不会被
	# 钳到 gpL 以上（否则网格的旧大最小宽会把停靠栏锁在旧宽度）。
	if gpLeftDock != null and gpLeftDock.has_method("_gpReflow"):
		gpLeftDock._gpReflow(gpL)
	# Split 0 sits at the left dock's right edge; split 1 sits one right-dock
	# width back from the body's right edge, leaving the center to fill the gap.
	# 分隔条 0 位于左栏右缘；分隔条 1 距主体右缘一个右栏宽度，中间栏填满缝隙。
	var gpOffsets: PackedInt32Array = PackedInt32Array()
	gpOffsets.append(int(round(gpL)))
	gpOffsets.append(int(round(gpBW - gpR)))
	gpBodySplit.split_offsets = gpOffsets


# Initial dock widths: wait until the split container has a real laid-out width
# (a few frames after _ready), then· seed the stored widths from the docks' floors
# and pin both docks so the canvas fills the rest.
# 初始停靠栏宽度：等待分隔容器获得已布局的真实宽度（_ready 后若干帧），再用两栏
# 下限初始化存储宽度，并钉死两栏使画布填满剩余空间。
func _gpInitSplits() -> void:
	for _gpI in range(10):
		await get_tree().process_frame
		if gpBodySplit != null and gpBodySplit.size.x > 50.0:
			break
	# Seed the stored widths from the declared floors so the first apply pins both
	# docks to their minimum and the canvas gets everything else.
	# 用声明下限初始化存储宽度，使首次应用把两栏钉到最小、画布取得其余空间。
	gpLeftWidthPx = GP_LEFT_MIN
	gpRightWidthPx = GP_RIGHT_MIN
	_gpApplySplits()
	var gpWin: Window = get_window()
	gpPrevWidth = int(gpWin.size.x) if gpWin != null else 0


# A splitter in the three-pane body was dragged. Godot 4.7's SplitContainer.dragged
# signal only carries the splitter offset (distance from the body's left edge); it
# does NOT carry a splitter index even with three children. We therefore decide which
# splitter moved by comparing the new offset to the stored left/right splitter
# positions; the closer one wins. This keeps both docks resizable and lets the
# palette grid reflow as the left dock is widened or narrowed.
# 三栏主体中某个分隔条被拖动。Godot 4.7 的 SplitContainer.dragged 信号只带分隔条偏移
#（距主体左缘的距离），即便有三个子节点也**不带索引**。因此通过比较新偏移与当前存
# 储的左/右分隔条位置来判断拖的是哪条；离谁近就是谁。这样左右两栏都可调，左栏变
# 宽/窄时图元网格也能随之重排。
func _gpOnBodyDragged(gpOffset: int) -> void:
	var gpBW: float = gpBodySplit.size.x
	if gpBW <= 1.0:
		return
	var gpOffsetF: float = float(gpOffset)
	# Determine which splitter is being dragged by proximity to the current positions.
	# 通过离当前位置的远近判断正在拖哪条分隔条。
	var gpLeftPos: float = gpLeftWidthPx
	var gpRightPos: float = gpBW - gpRightWidthPx
	var gpLeftDist: float = absf(gpOffsetF - gpLeftPos)
	var gpRightDist: float = absf(gpOffsetF - gpRightPos)
	if gpLeftDist < gpRightDist:
		# Left splitter: offset == left-dock width. Feed the new width to the palette
		# grid so it recomputes its column count immediately.
		# 左分隔条：偏移即左栏宽度。把新宽度传给图元网格，使其立即重算列数。
		gpLeftWidthPx = clampf(gpOffsetF, GP_LEFT_MIN, gpBW - GP_RIGHT_MIN - 80.0)
		if gpLeftDock != null and gpLeftDock.has_method("_gpReflow"):
			gpLeftDock._gpReflow(gpLeftWidthPx)
	else:
		# Right splitter: offset == left+center span, so right width = body - offset.
		# 右分隔条：偏移即左+中跨度，故右栏宽度 = 主体宽度 - 偏移。
		var gpRightPx: float = gpBW - gpOffsetF
		gpRightWidthPx = clampf(gpRightPx, GP_RIGHT_MIN, gpBW - GP_LEFT_MIN - 80.0)
	# Re-apply the split immediately so the splitter position and the palette reflow
	# match the dragged width on the spot (and a later resize keeps it, since the
	# stored pixel widths now reflect the drag). Idempotent: it just writes the same
	# offsets Godot set during the drag.
	# 立即重应用分隔，使分隔条位置与图元库重排当场贴合拖出宽度（后续缩放也能保留，
	# 因为存储像素宽现已反映本次拖拽）。幂等：写入的即 Godot 拖拽时已设的偏移。
	_gpApplySplits()


# ============================ lookups ============================
# ============================ 查找 ============================
# Find a symbol definition by its id.
# 按 id 查找图元定义。
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
