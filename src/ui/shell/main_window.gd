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
# 文件生命周期协调者（保存/打开/导入/导出/关闭拦截）。
# File lifecycle coordinator (save/open/import/export/close guard).
var gpFileCoord: GPFileCoordinator = null

# GPRibbonCoordinator（Ribbon 与工具栏的构建、样式、模式映射与工具选中转发）。
# Ribbon and toolbar construction, styling, mode mapping and tool-selection forwarding.
var gpRibbonCoord: GPRibbonCoordinator = null

# GPSymbolLibraryCoordinator（图元库级联删除、替换与重命名、漂移对账、用户包加载与符号编辑器宿主）。
# Symbol library cascade delete, swap/rename, drift reconciliation, user packs and the symbol editor host.
var gpSymbolLibCoord: GPSymbolLibraryCoordinator = null

# GPSelectionCoordinator（图与面板的双向同步桥：订阅事件总线刷新属性面板与状态栏，并把面板改值经命令层回写）。
# Graph-to-panel sync bridge: subscribes to the event bus, refreshes inspector and status bar, writes panel edits back through the command layer.
var gpSelCoord: GPSelectionCoordinator = null

# GPTagRuleCoordinator（位号规则对话框编排与重编号工作流）。
# Tag-rule dialog orchestration and the renumber workflow.
var gpTagCoord: GPTagRuleCoordinator = null

# GPLayoutCoordinator（分隔条比例、DPI 缩放、窗口尺寸响应与最大化）。
# Splitter ratios, DPI scaling, window resize handling and maximised start-up.
var gpLayoutCoord: GPLayoutCoordinator = null

# GPMenuCoordinator（菜单分发、撤销/重做与设置对话框；文件类动作转发给 GPFileCoordinator）。
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

# bus, the active graph and the unsaved-dirty flag, replacing the old GPAppState autoload stub.
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

# Hierarchy outline panel (mount tree of the active sheet). Added as the fourth tab of the right
# dock at runtime, so scenes/main.tscn keeps its exact byte shape.
# 层级大纲面板（当前图纸的挂载树）。运行时作为右栏第四个标签加入，故 scenes/main.tscn 字节不变。
var gpOutline: GPOutlinePanel = null

# The symbol backpack popup (A11). Null until assembly; created once and reused, so opening it a
# hundred times does not rebuild a hundred popups.
# 图元背包弹窗（A11）。装配前为 null；创建一次并复用，使开一百次也不会建一百个弹窗。
var gpBackpack: GPSymbolBackpack = null

# The DRC panel (B2): fifth dock tab, created at assembly like the outline.
# DRC 面板（B2）：第五个停靠页，与大纲一样在装配时创建。
var gpDrcPanel: GPDRCPanel = null

# The top-toolbar DRC result dialog (ADR-39 UI). Lazily created; non-modal so the user can
# inspect the drawing while it stays open.
# 顶部工具栏的 DRC 结果弹窗（ADR-39 UI）。懒创建；非模态，用户可一边看图一边点行。
var gpDrcDialog: GPDRCDialog = null

# Live DRC scheduler (E02): debounced engine run after every graph change.
# 实时 DRC 调度（E02）：每次图变化后去抖跑一次引擎。
var gpRuleScheduler: GPRuleScheduler = null

# Screen-space DRC badges above the active canvas.
# 活动画布之上的屏幕空间 DRC 角标。
var gpRuleOverlay: GPRuleOverlay = null

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

# gpSelectionChanged directly, so this cached id has no consumer left.
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
# Left dock INITIAL width in pixels: wide enough that the symbol palette lays out
# 3 thumbnails per row on first launch (the grid derives columns from this width).
# Kept above GP_LEFT_MIN so the startup layout honours the "3 per row" default while
# the user can still drag the dock narrower (down to GP_LEFT_MIN = 2 per row).
# 左停靠栏**初始**宽度（像素）：足以让图元库在首次启动时每行排 3 个缩略图（网格据此宽度推导列数）。
# 刻意高于 GP_LEFT_MIN，使启动布局满足「每行 3 个」默认；用户仍可将停靠栏拖窄（下限 GP_LEFT_MIN = 每行 2 个）。
const GP_LEFT_DEFAULT: float = 200.0
# Right dock minimum width in pixels (matches RightDock.custom_minimum_size.x).
# 右停靠栏最小宽度（像素，与 RightDock.custom_minimum_size.x 一致）。
const GP_RIGHT_MIN: float = 160.0
# Right dock INITIAL width in pixels (2026-09-25 request: start at 200).
# 右停靠栏**初始**宽度（像素）（2026-09-25 需求：初始 200）。
const GP_RIGHT_DEFAULT: float = 200.0

# Current left-dock width in pixels; seeded from GP_LEFT_DEFAULT (3-per-row layout) and updated by drags.
# 当前左停靠栏宽度（像素）；以 GP_LEFT_DEFAULT（每行 3 个）初始化，拖拽时更新。
var gpLeftWidthPx: float = GP_LEFT_DEFAULT
# Current right-dock width in pixels; seeded from GP_RIGHT_DEFAULT (200) and updated by drags.
# 当前右停靠栏宽度（像素）；以 GP_RIGHT_DEFAULT（200）初始化，拖拽时更新。
var gpRightWidthPx: float = GP_RIGHT_DEFAULT

# Standalone top command toolbar row (below the menu bar, horizontally centred).
# It carries the former left-palette EDIT block plus the quick file/zoom icons;
# actions reuse menu ids and route through gpMenuCoord.gpOnMenu.
# 独立的顶部命令工具栏行（菜单栏正下方、水平居中）。承载原左栏「编辑」块与
# 文件/缩放快捷图标；动作复用菜单 id，经 gpMenuCoord.gpOnMenu 路由。
var gpQuickBar: GPPIDQuickToolbar = null


# Wire the static scene together and set up initial state.
# 将静态场景拼接起来并设置初始状态。
func _ready() -> void:
	# Assembly order is load-bearing: coordinators first (every later step connects a signal
	# to one), then the library, then the static nodes, then the panels that consume them, and
	# the first sheet LAST because creating it refreshes the inspector immediately.
	# 装配顺序是有意义的：先协调者（后续每步都要把信号连到它），再图元库，再静态节点，
	# 然后是消费它们的面板；首张图纸放最后，因为创建它会立刻刷新属性面板。
	_gpAssembleCoordinators()
	_gpLoadSymbolLibrary()
	_gpFetchStaticNodes()
	_gpAssembleCenter()
	_gpAssemblePalette()
	_gpAssembleInspector()
	_gpAssembleOutline()
	_gpAssembleBackpack()
	_gpAssembleDrc()
	_gpAssembleMenu()
	_gpAssembleFileDialog()
	_gpBindWindowSignals()


# Owns the OS close guard + instantiates every coordinator. MUST run before the other
# assembly steps, because all of them connect signals to these objects.
# 负责 OS 关闭拦截 + 实例化全部协调者。必须先于其他装配步骤 —— 其余每步都要把信号连到这些对象上。
func _gpAssembleCoordinators() -> void:
	# 武装关闭拦截：接管 OS 关闭请求，使窗口不会自行退出。下方的
	# _notification(NOTIFICATION_WM_CLOSE_REQUEST) 才拥有决定权（干净→退出，
	# 脏→三选一）。缺此一行，引擎会在派发通知后立刻退出，未保存对话框虽被创建却
	# 永无机会显示，改动被静默丢失。
	# Intercept the OS window-close via the root Window's close_requested signal (the
	# reliable, signal-based path in Godot 4). A plain _notification(NOTIFICATION_WM_CLOSE_
	# REQUEST) on a Control root is NOT reliably delivered, so the three-way dialog would
	# never appear on a red-X click.
	# 用根 Window 的 close_requested 信号拦截 OS 关闭（Godot 4 中可靠、基于信号的做法）。
	# 在 Control 根上用 _notification(NOTIFICATION_WM_CLOSE_REQUEST) 并不可靠地送达，
	# 红叉点击时三选一对话框因此从不出现。close_requested 在真正的 Window 上触发，
	# 由我们决定（干净→退出，脏→三选一）而非引擎自退。
	get_tree().auto_accept_quit = false
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
	gpRuleScheduler = GPRuleScheduler.new()
	gpRuleScheduler.name = "DRCScheduler"
	add_child(gpRuleScheduler)
	gpRuleScheduler.gpFindingsReady.connect(_gpOnLiveDrc)
	gpRuleOverlay = GPRuleOverlay.new()
	gpRuleOverlay.name = "DrcOverlay"
	add_child(gpRuleOverlay)
	get_window().close_requested.connect(gpFileCoord.gpOnCloseRequested)
	# Autosave: build its timer now; it stays idle until the first manual save arms it (ADR-9).
	# 自动保存：现在构建其计时器；在首次手动保存启用它之前保持空闲（ADR-9）。
	gpFileCoord.gpSetupAutoSave()


# Reload user-exported symbol packs, then publish the live default defs to gpDefs.
# 重新载入用户导出的图元包，并把当前默认定义发布到 gpDefs。
func _gpLoadSymbolLibrary() -> void:
	# Restore any symbol packs the user exported in a previous session so they
	# re-appear in the palette and on the canvas after a restart.
	# 恢复用户在上一次会话中导出的图元包，使重启后它们重新出现在图元库与画布中。
	GPSymbolLibrary.gpLoadUserPacks()
	gpDefs = GPSymbolLibrary.gpDefaultDefs()


# Cache the scene-tree nodes this host drives, and wire the splitter drag.
# 缓存宿主所驱动的静态场景节点，并接上分隔条拖拽。
func _gpFetchStaticNodes() -> void:
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


# Wire the tabbed drawing area and create the FIRST sheet. Runs after the inspector and
# status labels exist, because adding a tab refreshes the inspector immediately.
# 接上多标签绘图区并创建首张图纸。须在属性面板与状态标签就位之后运行，
# 因为新建标签会立刻刷新属性面板。
func _gpAssembleCenter() -> void:
	gpCenter = $VLayout/Body/Center
	# The status bar moves INTO the center column: it now spans the drawing area
	# only, so the LEFT PALETTE extends all the way to the bottom of the window
	# and the status bar no longer eats into the palette's height.
	# 状态栏移入中心列：只横跨绘图区，左侧图元库因此直通窗口底部，
	# 状态栏不再占用图元库的高度。
	var gpStatus: HBoxContainer = $VLayout/StatusBar
	$VLayout.remove_child(gpStatus)
	gpCenter.add_child(gpStatus)
	gpCenter.add_theme_constant_override("separation", 0)
	gpCenter.gpSetDefs(gpDefs)
	gpCenter.gpOnCanvasReady.connect(_gpOnCanvasReady)
	gpCenter.gpActiveChanged.connect(_gpOnActiveTabChanged)
	gpCenter.gpFullscreenToggled.connect(_gpOnFullscreen)
	gpCenter.gpAddTab()


# Inject the symbol buttons into the left palette and route its picks / deletions.
# 向左图元库注入图元按钮，并接管其选取 / 删除请求。
func _gpAssemblePalette() -> void:
	# ---- left palette: inject symbol buttons ----
	# ---- 左侧图元库：注入图元按钮 ----
	gpLeftDock.gpPopulate(gpDefs)
	gpLeftDock.gpSymbolPicked.connect(gpRibbonCoord.gpOnSymbolPicked)
	# A tile was DRAGGED (not clicked). Distinct from a pick: a drag arms the attachment gesture on
	# the active canvas so the very next click on a host mounts the part there (规划 §15 mode 1).
	# 某图块被**拖动**（而非点击）。与点选不同：拖动会在活动画布上给附件手势上膛，
	# 使用户随后在宿主上的一次点击即把该部件装到那里（规划 §15 模式一）。
	gpLeftDock.gpSymbolDragStarted.connect(gpRibbonCoord.gpOnSymbolDragStarted)
	# Tool-block commands (canvas modes / undo / redo / delete / settings) reuse the
	# old Ribbon action ids and route through the SAME handler that served the Ribbon.
	# 工具块命令（画布模式 / 撤销 / 重做 / 删除 / 设置）复用旧 Ribbon 动作 id，
	# 经当年服务 Ribbon 的同一处理器路由。
	gpLeftDock.gpActionRequested.connect(gpRibbonCoord.gpOnToolBarPressed)
	# Symbol deletion is owned here: scan every sheet, cascade-remove canvas instances if
	# the symbol is in use, then drop it from the live library and re-render the palette.
	# 图元删除在此负责：扫描所有图纸，若图元在用则级联清理画布实例，再从活动库移除并重渲染。
	gpLeftDock.gpSymbolDeleteRequested.connect(gpSymbolLibCoord.gpOnSymbolDeleteRequested)


# Route inspector edits to the selection / symbol-library coordinators.
# 把属性面板的编辑请求路由到选中 / 图元库协调者。
func _gpAssembleInspector() -> void:
	# ---- inspector ----
	# ---- 属性面板 ----
	gpInspector.gpAttrChanged.connect(gpSelCoord.gpOnAttrChanged)
	gpInspector.gpEdgeAttrChanged.connect(gpSelCoord.gpOnEdgeAttrChanged)
	gpInspector.gpLineAttrsRequested.connect(_gpOnInspectorLineAttrs)
	gpInspector.gpLineRerenderRequested.connect(_gpOnInspectorRerenderLine)
	# ADR-43 / S4-4: the connector's link section (2026-11-04: the contract fields and the
	# sync button left the panel — line attrs live on the edges; the dropdown re-connects).
	# ADR-43 / S4-4：连接符的 link 段（2026-11-04：契约字段与同步按钮离开面板 —— 管线属性
	# 归边所有；下拉改为重连）。
	gpInspector.gpLinksProvider = Callable(gpCenter, "gpOffPageLinksList")
	# U3 action row (user feedback 2026-11-04): jump / unlink / delete.
	# U3 动作行（用户反馈 2026-11-04）：跳转 / 断开 / 删除。
	gpInspector.gpJumpToPeerRequested.connect(_gpOnJumpToPeer)
	gpInspector.gpUnlinkRequested.connect(_gpOnInspectorUnlink)
	gpInspector.gpLinkDeleteRequested.connect(_gpOnInspectorLinkDelete)
	# The peer-sheet dropdown's data source + the pick hand-off (user feedback 2026-11-03).
	# 对端图纸下拉的数据源与选择移交（用户反馈 2026-11-03）。
	gpInspector.gpSheetsProvider = func() -> Dictionary:
		var gpCur: GPSheet = gpCenter.gpActiveSheet()
		return {"sheets": gpCenter.gpToSheets(),
			"current": gpCur.gpId if gpCur != null else ""}
	gpInspector.gpConnectPickRequested.connect(_gpOnInspectorConnectPick)
	# Cross-sheet inherit checkbox on the continuation edge (user feedback 2026-11-04):
	# the shell computes visibility (B-side continuation only) and current follow state;
	# the toggle lands back here.
	# 延续边上的跨图纸继承勾选框（用户反馈 2026-11-04）：外壳计算可见性（仅 B 端延续段）
	# 与当前跟随状态；开关动作落回此处。
	gpInspector.gpEdgeInheritProvider = _gpEdgeInheritInfo
	gpInspector.gpEdgeInheritToggled.connect(_gpOnEdgeInheritToggled)
	# the panel owns no graph, so a symbol swap is announced and executed here.
	# 面板不持有图，故「更换图元」在此被宣告并执行。
	gpInspector.gpSymbolSwapRequested.connect(gpSymbolLibCoord.gpOnSymbolSwap)
	# a batched edit arrives once with the whole id set, so it becomes one undo step.
	# 批量编辑连同整个 id 集合一次性送达，故只产生一个撤销步。
	gpInspector.gpBatchAttrChanged.connect(gpSelCoord.gpOnBatchAttrChanged)
	# orphaned values may only be dropped on an explicit request from the panel.
	# 孤儿值仅在面板明确请求时才可被清除。
	gpInspector.gpCleanOrphansRequested.connect(gpSymbolLibCoord.gpOnCleanOrphans)
	# annotation-shape fields (A2): name / layer edits become one undoable command each.
	# 注释图形字段（A2）：名称 / 图层编辑各成一条可撤销命令。
	gpInspector.gpShapePropChanged.connect(gpSelCoord.gpOnShapePropChanged)
	# The inspector owns no graph; give it the ACTIVE canvas's project standard for the code
	# pickers (medium / pipe class / insulation). Pulled lazily so tab switches need no re-wiring.
	# 属性面板不持有图；把**活动画布**的项目标准给它用于代号下拉（介质 / 管道等级 / 保温）。
	# 惰性取值，切换标签页无需重新接线。
	gpInspector.gpStandardProvider = func() -> GPProjectStandard:
		var gpCanvas: GPCanvas2D = gpActiveCanvas()
		if gpCanvas == null or gpCanvas.gpGraph == null:
			return null
		if gpCanvas.gpGraph.gpStandard != null:
			return gpCanvas.gpGraph.gpStandard
		# Same split as the re-render path: the registry may hold the standard the numbering
		# actually used, and the center owns the project-level one. Without these fallbacks the
		# pickers silently degrade to text boxes (the reported "still an input box").
		# 与重渲染路径同样的分裂：注册器可能持有铸造真正用的标准，中心持有工程级那一份。
		# 没有这两级兜底，下拉会静默退化成文本框（用户报告的「还是输入框」）。
		if gpCanvas.gpActions != null and gpCanvas.gpActions.gpCtx != null \
				and gpCanvas.gpActions.gpCtx.gpTags != null \
				and gpCanvas.gpActions.gpCtx.gpTags.gpStandard != null:
			return gpCanvas.gpActions.gpCtx.gpTags.gpStandard as GPProjectStandard
		if gpCenter != null:
			return gpCenter.gpProjectStandardOrCreate()
		return null
	# custom-entry CRUD (Rev.3 stage 1.5, R2): add / rename / delete, instance level.
	# 自定义条目增删改（Rev.3 阶段 1.5，R2）：新增 / 改名 / 删除，仅实例级。
	gpInspector.gpPropAddRequested.connect(gpSelCoord.gpOnPropAdd)
	gpInspector.gpPropRenamed.connect(gpSelCoord.gpOnPropRename)
	gpInspector.gpPropDeleteRequested.connect(gpSelCoord.gpOnPropDelete)
	gpInspector.gpDefs = gpDefs


# Route menu actions, then build and style the ribbon command bar.
# 接管菜单动作，随后构建并样式化 Ribbon 命令栏。
func _gpAssembleMenu() -> void:
	# ---- menu ----
	# ---- 菜单 ----
	gpMenuBar.gpActionTriggered.connect(gpMenuCoord.gpOnMenu)
	# Ask the host to refresh enabled states right before a popup opens.
	# 菜单展开前向宿主请求刷新启用状态。
	gpMenuBar.gpMenuOpening.connect(gpMenuCoord.gpOnMenuOpening)

	# The Ribbon left the top bar (2026-09-25, AutoCAD reference layout): its draw/edit
	# tools moved INTO the left palette and print/import/export into the menu bar's
	# quick-access icons. gpStyleChrome stays — it still dresses the right tabs and
	# the splitter.
	# Ribbon 已移出顶栏（2026-09-25，参照 AutoCAD 布局）：其绘图/编辑工具移入左侧图元库，
	# 打印/导入/导出移入菜单栏快捷图标。gpStyleChrome 保留 —— 它仍负责右栏标签与分隔条样式。
	gpRibbonCoord.gpStyleChrome()
	_gpAssembleQuickBar()


# Build the standalone command toolbar row and insert it DIRECTLY BELOW the menu
# bar (VLayout index 1), horizontally centred. Actions reuse menu action ids and
# route through the SAME gpOnMenu dispatcher as the menu popups, so no new routing
# exists. Also tighten the chrome: VLayout rows touch each other (no 4px default
# gaps) and the Body splitter gap shrinks to 2px — the reference image shows the
# docks and canvas butted together with no visible gap strip.
# 构建独立命令工具栏行并插入菜单栏**正下方**（VLayout 下标 1），水平居中。动作复用
# 菜单动作 id、经与菜单弹出项**相同**的 gpOnMenu 分发器路由，零新路由。同时收紧
# chrome：VLayout 各行相互贴合（消除默认 4px 缝），Body 分隔缝收窄到 2px —— 参考图
# 中侧栏与画布直接相接、无可见缝隙条。
func _gpAssembleQuickBar() -> void:
	var gpVLayout: VBoxContainer = $VLayout as VBoxContainer
	gpQuickBar = GPPIDQuickToolbar.new()
	gpQuickBar.name = "QuickToolbar"
	gpQuickBar.gpActionTriggered.connect(gpMenuCoord.gpOnMenu)
	gpVLayout.add_child(gpQuickBar)
	gpVLayout.move_child(gpQuickBar, 1)
	# Flush chrome rows: menu / toolbar / body / status sit back-to-back.
	# chrome 各行贴合：菜单 / 工具栏 / 主体 / 状态栏背靠背。
	gpVLayout.add_theme_constant_override("separation", 0)
	# Minimal but still-draggable splitter gap (dragging needs a non-zero grab band).
	# 最小但仍可拖拽的分隔缝（拖拽需要非零抓取带）。
	gpBodySplit.add_theme_constant_override("separation", 2)
	# The 2px splitter gap shows the root's own background; painting it DOCK-tinted
	# makes the left seam read as the dock simply extending to the canvas, and the
	# right seam as a hairline-thin band — matching the reference's butt joint.
	# 2px 分隔缝露出根节点自身背景；涂成 DOCK 色后，左缝读作「侧栏延伸到画布」，
	# 右缝读作发丝级窄带 —— 与参考图的直接拼接一致。
	resized.connect(queue_redraw)
	queue_redraw()


# Paint the root background in the DOCK tint so the splitter gap strips blend into
# the chrome instead of showing the engine's default clear colour.
# 根背景涂 DOCK 色，使分隔缝窄带融入 chrome，而非露出引擎默认清屏色。
func _draw() -> void:
	GPChromeStyle.gpDraw(self, GPChromeStyle.GP_DOCK_BG, 0)


# Create the open / save-as dialog, then bind locale changes to the static-text refresh.
# 创建打开 / 另存为对话框，并把语言切换接到静态文本刷新上。
func _gpAssembleFileDialog() -> void:
	# ---- file dialog (open / save-as) ----
	# ---- 文件对话框（打开 / 另存为） ----
	gpFileDialog = FileDialog.new()
	gpFileDialog.access = FileDialog.ACCESS_FILESYSTEM
	gpFileDialog.add_filter("*.pid.json", I18n.gpTr("doc.pid_filter"))
	gpFileDialog.file_selected.connect(gpFileCoord.gpOnFileSelected)
	gpFileDialog.dir_selected.connect(gpFileCoord.gpOnListDirSelected)
	add_child(gpFileDialog)

	I18n.gpLocaleChanged.connect(_gpOnLocaleChanged)
	_gpRefreshStaticText()


# Bind window-level signals for HiDPI / multi-monitor crispness and responsive resize.
# 绑定窗口级信号，用于多显示器清晰渲染（HiDPI）与响应式缩放。
func _gpBindWindowSignals() -> void:
	# ---- HiDPI / multi-monitor crispness + responsive resize ----
	# ---- 多显示器清晰渲染（HiDPI）+ 响应式缩放 ----
	var gpWin: Window = get_window()
	if gpWin != null:
		gpWin.size_changed.connect(gpLayoutCoord.gpOnWindowChanged)
		gpWin.size_changed.connect(gpLayoutCoord.gpOnResized)
		gpWin.focus_entered.connect(gpLayoutCoord.gpOnWindowChanged)
		gpLastScreen = gpWin.current_screen
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
	# the composition root owns the document manager + bus; hand it to the canvas BEFORE
	# reading gpEvents so the host subscribes to the manager's bus (not the fallback). The
	# canvas forwards every graph / selection / status / mode event onto that bus.
	# 组合根持有文档管理器与总线；在读取 gpEvents 之前先交给画布，使宿主订阅的是
	# 管理器的总线（而非回退总线）。画布将图/选中/状态/模式事件统一转发到该总线。
	gpCanvas.gpBindDocument(gpDocManager)
	# subscribe to the sheet's app event bus instead of the canvas signals. The canvas
	# keeps emitting its legacy signals (public API stays stable), but the host now listens
	# on ONE explicit channel: state broadcasts travel on the bus, host-directed requests
	# (open editor / promote shapes) stay on signals.
	# 订阅本图纸的应用事件总线而非画布信号。画布仍发射旧信号（公共 API 保持稳定），
	# 但宿主现在只监听一条显式通道：状态广播走总线，宿主定向请求（打开编辑器 / 提升图形）仍走信号。
	var gpBus: GPEventBus = gpCanvas.gpEvents
	# The bus is SHARED across sheets (the document manager's bus), so a second tab
	# would re-connect the same callables and spam engine "already connected" errors.
	# Guard every connect with is_connected (idempotent wiring).
	# 总线是**跨图纸共享**的（文档管理器总线），第二个标签页会重复连接同一可调用对象，
	# 刷出引擎「already connected」错误。每条连接都加 is_connected 守卫（幂等接线）。
	if not gpBus.gpGraphChanged.is_connected(gpSelCoord.gpOnGraphChanged):
		gpBus.gpGraphChanged.connect(gpSelCoord.gpOnGraphChanged)
	if not gpBus.gpSelectionChanged.is_connected(gpSelCoord.gpOnSelectionChanged):
		gpBus.gpSelectionChanged.connect(gpSelCoord.gpOnSelectionChanged)
	if not gpBus.gpStatusUpdated.is_connected(gpSelCoord.gpOnStatus):
		gpBus.gpStatusUpdated.connect(gpSelCoord.gpOnStatus)
	if not gpBus.gpModeChanged.is_connected(gpRibbonCoord.gpSyncToolBar):
		gpBus.gpModeChanged.connect(gpRibbonCoord.gpSyncToolBar)
	if gpRuleScheduler != null:
		if not gpBus.gpGraphChanged.is_connected(gpRuleScheduler.gpMarkDirty):
			gpBus.gpGraphChanged.connect(gpRuleScheduler.gpMarkDirty)
		if gpActiveCanvas() == gpCanvas:
			gpRuleScheduler.gpBind(gpCanvas, gpDefs)
			if gpRuleOverlay != null:
				gpRuleOverlay.gpAttach(gpCanvas)
	# Announce the document already loaded onto this canvas so bus subscribers (title bar,
	# project tree) bind to the correct graph in one place, and the dirty flag resets.
	# 通告本画布已载入的文档，使总线订阅者（标题栏、工程树）在一处绑定到正确的图，并重置脏标记。
	gpDocManager.gpSetGraph(gpCanvas.gpGraph)
	# Double click / context menu on a symbol asks the host to open the symbol editor
	# dialog (seeded with that symbol's geometry) — not in-place editing.
	# 图元上的双击 / 右键菜单请求宿主打开图元编辑对话框（预填该图元几何），非就地编辑。
	gpCanvas.gpSymbolEditRequested.connect(gpSymbolLibCoord.gpOnSymbolEditRequested)
	# Double click on the TITLE BLOCK opens the same frame / title-block dialog the menu uses
	# (2026-10-16: the block had no editable path on the canvas at all).
	# **双击图签**打开与菜单相同的图框 / 图签对话框（2026-10-16：此前图签在画布上完全没有可编辑路径）。
	gpCanvas.gpTitleBlockEditRequested.connect(gpMenuCoord.gpOpenFrameDialog)
	# Promote selected annotation shapes into a real symbol: open the Make-Symbol dialog.
	# 把选中的注释图形提升为真正图元：打开「生成图元」对话框。
	gpCanvas.gpMakeSymbolRequested.connect(gpSymbolLibCoord.gpOnMakeSymbolFromShapes)
	# ADR-36 D9: a NEW line opens the "line attributes" panel, so its number is generated from
	# real attributes instead of staying a placeholder. Bound per canvas so the panel always
	# targets the sheet the line was drawn on.
	# ADR-36 D9：新画出的管线打开「管线属性」面板，使号由真实属性生成而不是长期挂占位。
	# 逐画布绑定，故面板永远作用于画线的那张图纸。
	var gpLineCb: Callable = Callable(self, "_gpOnLineCreated").bind(gpCanvas)
	if not gpCanvas.gpLineCreated.is_connected(gpLineCb):
		gpCanvas.gpLineCreated.connect(gpLineCb)
	# ADR-43 / S3: cross-sheet gestures, peer navigation / sync, and history settle — each
	# wired per canvas so the dialog and the snapshot always target the RIGHT sheet.
	# ADR-43 / S3：跨图纸手势、对端跳转 / 同步与历史落定 —— 逐画布接线，
	# 使对话框与快照永远作用于**正确的**那张图纸。
	if not gpCanvas.gpCrossSheetRequested.is_connected(_gpOnCrossSheetRequested):
		gpCanvas.gpCrossSheetRequested.connect(_gpOnCrossSheetRequested.bind(gpCanvas))
	if not gpCanvas.gpJumpToPeerRequested.is_connected(_gpOnJumpToPeer):
		gpCanvas.gpJumpToPeerRequested.connect(_gpOnJumpToPeer)
	if not gpCanvas.gpSyncToPeerRequested.is_connected(_gpOnSyncToPeer):
		gpCanvas.gpSyncToPeerRequested.connect(_gpOnSyncToPeer)
	if not gpCanvas.gpCrossSheetHistoryChanged.is_connected(gpCenter.gpOnCrossSheetHistory):
		gpCanvas.gpCrossSheetHistoryChanged.connect(gpCenter.gpOnCrossSheetHistory)
	# A2: inject the container link-store into THIS canvas's service, so every successful
	# cross-sheet command ends with ONE gpTouch() and the store's signal drives refreshes.
	# A2：把容器 link store 注入**本**画布的服务，使每条成功的跨图纸命令以一次 gpTouch()
	# 收尾，由 store 信号统一驱动刷新。
	gpCanvas.gpActions.gpLinkStore = gpCenter.gpLinkStore()
	if not gpCanvas.gpCrossSheetDeleteRequested.is_connected(_gpOnCrossSheetDelete):
		gpCanvas.gpCrossSheetDeleteRequested.connect(_gpOnCrossSheetDelete.bind(gpCanvas))
	# Cross-sheet line-number propagation (user feedback 2026-11-04): when THIS sheet's
	# line number is committed, the shell forwards it to the continuation edge on the peer
	# sheet. Bound per canvas so the SOURCE sheet is known without a second lookup.
	# 跨图纸管线号传播（用户反馈 2026-11-04）：**本**图纸的管线号落账时，外壳把它转发到
	# 对端图纸的延续边。逐画布绑定，无需二次查找即知**源**图纸。
	var gpTagCb: Callable = Callable(self, "_gpOnEdgeTagCommitted").bind(gpCanvas)
	if not gpCanvas.gpActions.gpEdgeTagCommitted.is_connected(gpTagCb):
		gpCanvas.gpActions.gpEdgeTagCommitted.connect(gpTagCb)
	# Cross-sheet attribute propagation (user feedback 2026-11-04, round 2): when THIS
	# sheet's line attributes are committed, the shell forwards the inheritable ones to the
	# continuation edge on the peer sheet. Bound per canvas, same shape as the tag signal.
	# 跨图纸属性传播（用户反馈 2026-11-04 第二轮）：**本**图纸的管线属性落账时，外壳把可继承
	# 的那些转发到对端图纸的延续边。逐画布绑定，与编号信号同构。
	var gpAttrsCb: Callable = Callable(self, "_gpOnEdgeAttrsCommitted").bind(gpCanvas)
	if not gpCanvas.gpActions.gpEdgeAttrsCommitted.is_connected(gpAttrsCb):
		gpCanvas.gpActions.gpEdgeAttrsCommitted.connect(gpAttrsCb)
	# Draw-time follow pull (user feedback 2026-11-04, round 3): when a pipe is DRAWN on
	# this sheet, the shell checks whether it feeds a B-end twin and pulls the source's
	# block + number at once — follow mode is on by default, so the very first auto number
	# must never linger on the canvas while the panel shows the source values.
	# 画线即拉取（用户反馈 2026-11-04 第三轮）：**本**图纸画成一条管线时，外壳检查它是否
	# 馈送某个 B 端孪生体并立刻拉取源端属性块与编号 —— 跟随默认开启，首个自动编号绝不能
	# 在画布上滞留而面板却显示源端值。
	var gpCreatedCb: Callable = Callable(self, "_gpOnEdgeCreated").bind(gpCanvas)
	if not gpCanvas.gpActions.gpEdgeCreated.is_connected(gpCreatedCb):
		gpCanvas.gpActions.gpEdgeCreated.connect(gpCreatedCb)
	# W13-S8 (user request 2026-11-03): the cross-pane drag-to-connect gesture — wired per
	# canvas so the SOURCE canvas is known at drop time without a second lookup.
	# W13-S8（用户需求 2026-11-03）：跨窗格拖拽连线手势 —— 逐画布接线，
	# 使落点时刻无需二次查找即知**源**画布。
	if not gpCanvas.gpCrossPaneDragUpdated.is_connected(_gpOnCrossPaneDragUpdated):
		gpCanvas.gpCrossPaneDragUpdated.connect(_gpOnCrossPaneDragUpdated.bind(gpCanvas))
	if not gpCanvas.gpCrossPaneDropped.is_connected(_gpOnCrossPaneDropped):
		gpCanvas.gpCrossPaneDropped.connect(_gpOnCrossPaneDropped.bind(gpCanvas))
	if not gpCanvas.gpCrossPaneDragEnded.is_connected(_gpOnCrossPaneDragEnded):
		gpCanvas.gpCrossPaneDragEnded.connect(_gpOnCrossPaneDragEnded)
	# fire the toolbar sync twice, so it is intentionally not connected here.
	# 故此处有意不再连接。
	# A brand-new sheet has an empty undo stack: make the 编辑 menu agree with it right away.
	# 新建图纸的撤销栈为空：让「编辑」菜单立即与之保持一致。
	gpMenuCoord.gpRefreshEditMenu()
	# A brand-new sheet is a new graph: rebind the outline to it (it would otherwise keep showing
	# the previous sheet's tree).
	# 新图纸就是新图：把大纲重新绑到它（否则它会继续显示上一张图纸的树）。
	_gpBindOutline()


# The active sheet changed (add / switch / close): refresh the inspector for the
# newly active selection.
# 活动图纸已切换（新建 / 切换 / 关闭）：刷新新活动页的选中属性。
func _gpOnActiveTabChanged() -> void:
	gpSelCoord.gpRefreshSelection()
	gpRibbonCoord.gpSyncToolBar()
	_gpBindOutline()
	_gpBindDrc()
	if gpRuleScheduler != null:
		gpRuleScheduler.gpBind(gpActiveCanvas(), gpDefs)
	if gpRuleOverlay != null and gpActiveCanvas() != null:
		gpRuleOverlay.gpAttach(gpActiveCanvas())
		gpRuleOverlay.gpShow([], _gpActiveSheetId())


# Fullscreen toggle from the center header: hide/show the side docks so the canvas
# fills the window, then re-apply the splits when leaving fullscreen.
# 中心头部触发的全屏切换：隐藏/显示左右停靠栏使画布占满窗口，退出时重新应用分隔。
func _gpOnFullscreen(gpOn: bool) -> void:
	gpLeftDock.visible = not gpOn
	gpRightDock.visible = not gpOn
	gpLayoutCoord.gpApplySplits()

# Build the hierarchy outline as a fourth right-dock tab.
# 把层级大纲构建为右栏第四个标签。
# Why a right-dock tab and not a new pane: the dock already owns "what is selected" (inspector)
# and "what this sheet is" (info / doc). Which symbol sits on which is the same family of
# question, and adding a fourth pane would eat canvas width on every screen size.
# 为何是右栏标签而不是新开一栏：右栏已经承担「选中了什么」（属性）与「这张图是什么」
#（信息 / 说明）。「谁装在谁身上」属同一类问题，而新开第四栏会在任何屏宽下都吃掉画布宽度。
func _gpAssembleOutline() -> void:
	gpOutline = GPOutlinePanel.new()
	gpOutline.name = "OutlineTab"
	gpTabs.add_child(gpOutline)
	gpOutline.gpBuild()
	gpOutline.gpRefreshText()
	gpTabs.set_tab_title(gpTabs.get_tab_count() - 1, I18n.gpTr("outline.title"))
	_gpBindOutline()


# Point the outline at the active canvas and rebuild it.
# 把大纲指向活动画布并重建。
# Kept as one helper because THREE entry points need it (first assembly, new sheet, tab switch)
# and each of them can legitimately arrive with no canvas at all.
# 收成一个辅助函数，因为**三条**入口都需要它（首次装配、新建图纸、切换标签），
# 而其中任何一条都可能理直气壮地没有任何画布。
func _gpBindOutline() -> void:
	if gpOutline == null:
		return
	var gpCv: GPCanvas2D = gpActiveCanvas()
	if gpCv != null:
		gpOutline.gpBindCanvas(gpCv)
	_gpBindDrc()


# Build the backpack popup and wire the two ways it places a symbol.
# 构建背包弹窗，并接好它放置图元的两种方式。
func _gpAssembleBackpack() -> void:
	gpBackpack = GPSymbolBackpack.new()
	gpBackpack.name = "SymbolBackpack"
	add_child(gpBackpack)
	gpBackpack.gpBuild()
	# Click chooses: place at the centre of the ACTIVE view, which is where the user is looking.
	# 单击选中：放到**当前**视图中心，也就是用户正在看的地方。
	gpBackpack.gpSymbolChosen.connect(_gpOnBackpackChosen)


# Open / close the backpack (B key). Refreshes the pools each time so a symbol created a minute
# ago is already in it.
# 打开 / 关闭背包（B 键）。每次刷新两个池，使一分钟前刚建的图元也已在其中。
func gpToggleBackpack() -> void:
	if gpBackpack == null:
		return
	if gpBackpack.visible:
		gpBackpack.hide()
		return
	var gpSettings: Object = get_node_or_null("/root/Settings")
	var gpFav: Array[String] = []
	var gpRecent: Array[String] = []
	if gpSettings != null:
		gpFav = (gpSettings.gpBagFavorites as Array[String]).duplicate()
		gpRecent = (gpSettings.gpBagRecents as Array[String]).duplicate()
	gpBackpack.gpSetSymbols(gpDefs, gpFav, gpRecent)
	gpBackpack.gpOpen()


# Place the chosen symbol under the view centre and remember it as recently used.
# 把选中的图元放到视图中心下方，并记为最近使用。
func _gpOnBackpackChosen(gpSymbolId: String) -> void:
	var gpCv: GPCanvas2D = gpActiveCanvas()
	if gpCv == null:
		return
	# The centre of the VIEWPORT, converted to world space: the point the user is aiming at.
	# **视口**中心换算到世界坐标：正是用户瞄准的那一点。
	var gpWorld: Vector2 = gpCv.gpWorldFromScreen(gpCv.size * 0.5)
	gpCv.gpRequestPlaceNode(gpSymbolId, gpWorld)
	# Recents are persisted here (not inside the popup) so a later session starts with them.
	# 最近列表在此持久化（而非弹窗内部），使下次会话一开始就有它们。
	var gpSettings: Object = get_node_or_null("/root/Settings")
	if gpSettings != null:
		gpSettings.gpBagRecents = GPSymbolBackpack.gpPushRecent(
			gpSettings.gpBagRecents as Array[String], gpSymbolId)
		gpSettings.gpSave()
	gpSetState("status.bag_placed", [gpSymbolId])


# B toggles the backpack anywhere in the window EXCEPT while typing: an unhandled-key handler
# never sees a keystroke a focused LineEdit consumed, which is exactly the guard we want.
# B 在窗口内任意处切换背包，**输入时除外**：未处理按键只在聚焦控件未消费按键时到达，正是所要的护栏。
func _unhandled_key_input(gpEvent: InputEvent) -> void:
	if not (gpEvent is InputEventKey):
		return
	var gpKey: InputEventKey = gpEvent as InputEventKey
	if not gpKey.pressed or gpKey.echo:
		return
	# D22: Ctrl/Cmd+1..4 switches the multi-view layout from anywhere in the window —
	# the four header icons were the only entry before. (An unhandled-key handler never
	# sees keystrokes a focused LineEdit consumed, so typing "1" in a field is safe.)
	# D22：Ctrl/Cmd+1..4 在窗口任意处切换多视图布局 —— 此前唯一入口是头部四个图标。
	#（未处理按键不会收到聚焦输入框已消费的按键，因此在字段里打「1」是安全的。）
	if gpKey.ctrl_pressed or gpKey.meta_pressed:
		if not gpKey.alt_pressed:
			match gpKey.keycode:
				KEY_1, KEY_2, KEY_3, KEY_4:
					gpCenter.gpSetLayoutMode(int(gpKey.keycode) - int(KEY_1)
						+ GPPaneLayout.GP_SINGLE)
					get_viewport().set_input_as_handled()
		return
	if gpKey.alt_pressed:
		return
	if gpKey.keycode == KEY_B:
		gpToggleBackpack()
		get_viewport().set_input_as_handled()


# Build the DRC panel tab (B2).
# 构建 DRC 面板页（B2）。
func _gpAssembleDrc() -> void:
	gpDrcPanel = GPDRCPanel.new()
	gpDrcPanel.name = "DrcTab"
	gpTabs.add_child(gpDrcPanel)
	gpDrcPanel.gpBuild()
	gpTabs.set_tab_title(gpTabs.get_tab_count() - 1, I18n.gpTr("drc.panel_title"))
	gpDrcPanel.gpFindingActivated.connect(_gpOnDrcJump)
	gpDrcPanel.gpFindingActivatedFull.connect(_gpOnDrcFindingFromPanel)
	gpDrcPanel.gpFindingsChanged.connect(_gpOnDrcFindingsForOverlay)
	# ADR-36 C: "whole project" mode needs every sheet; the shell owns the tab bar.
	# ADR-36 C：「全工程」模式需要每张图纸；标签栏归外壳所有。
	gpDrcPanel.gpSetSheetsProvider(Callable(self, "_gpDrcSheets"))
	gpDrcPanel.gpSetLinksProvider(Callable(self, "_gpDrcLinks"))
	_gpBindDrc()


# A new process / utility line was created: open the line attributes panel (deferred, so the
# dialog does not open inside the tool's input handler).
# 新画出工艺 / 公用管线：打开管线属性面板（延后，避免在工具的输入处理过程中弹模态框）。
# Re-open the full line-attributes dialog for an EXISTING pipe from the inspector. The dialog
# used to be available only at creation time, so a project-standard field added later could not
# be filled on old lines.
# 从右侧属性面板重新打开已有管线的完整「管线属性」对话框。此前该对话框只在新画线时出现，
# 故后来在项目标准里新增的字段无法补填到旧管线上。
func _gpOnInspectorLineAttrs(gpEdgeId: String) -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
	if gpEdge == null:
		return
	var gpStd: GPProjectStandard = gpCanvas.gpGraph.gpStandard
	if gpStd == null:
		return
	var gpRule: GPTagRule = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpRuleFor(null)
	_gpOpenLineAttrs(gpCanvas, gpEdgeId, gpRule, gpStd)


# Repair path: re-render the line number from the current edge attributes without touching values.
# 修复路径：只按当前边属性重渲染管线号，不改值。
func _gpOnInspectorRerenderLine(gpEdgeId: String) -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	if not gpCanvas.gpActions.gpApplyLineAttrs(gpEdgeId, {}):
		gpSetState(gpCanvas.gpActions.gpLastRefusal,
			[gpCanvas.gpActions.gpLastRefusalDetail] if gpCanvas.gpActions.gpLastRefusalDetail != "" else [])
	gpCanvas.queue_redraw()
	gpCanvas.gpEmitStatus()
	gpRefreshSelection()


func _gpOnLineCreated(gpEdgeId: String, gpCanvas: GPCanvas2D) -> void:
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
	if gpEdge == null:
		return
	var gpStd: GPProjectStandard = gpCanvas.gpGraph.gpStandard
	if gpStd == null:
		return
	var gpRule: GPTagRule = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpRuleFor(null)
	if not gpRule.gpUsesSegments():
		return
	call_deferred("_gpOpenLineAttrs", gpCanvas, gpEdgeId, gpRule, gpStd)


func _gpOpenLineAttrs(gpCanvas: GPCanvas2D, gpEdgeId: String, gpRule: GPTagRule,
		gpStd: GPProjectStandard) -> void:
	var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
	if gpEdge == null:
		return
	# Deliberately UNTYPED + load(): annotating would pull the dialog into the startup graph.
	# 刻意不写类型并用 load()：标注会把该对话框拉进启动依赖图。
	var gpDlg = (load("res://src/ui/dialogs/line_attrs_dialog.gd") as GDScript).new()
	add_child(gpDlg)
	gpDlg.gpApplied.connect(func(gpAttrs: Dictionary) -> void:
		if not gpCanvas.gpActions.gpApplyLineAttrs(gpEdgeId, gpAttrs):
			var gpDetail: String = gpCanvas.gpActions.gpLastRefusalDetail
			gpSetState(gpCanvas.gpActions.gpLastRefusal,
				[gpDetail if gpDetail != "" else "-"] if gpCanvas.gpActions.gpLastRefusal != "" else [])
		gpCanvas.queue_redraw()
		gpCanvas.gpEmitStatus()
		# The dialog may have been opened from the inspector for an EXISTING line; refresh the
		# form so the new values are visible immediately (the graph signal alone does not rebuild
		# an already-open edge form).
		# 对话框可能是从右侧面板对**已有管线**打开的；这里刷新表单，使新值立即可见
		#（仅靠图信号不会重建已经打开的边表单）。
		gpRefreshSelection())
	gpDlg.confirmed.connect(gpDlg.queue_free)
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.gpShowFor(gpEdge, gpRule, gpStd)


# ---- ADR-43 / S3: cross-sheet connection ----
# ---- ADR-43 / S3：跨图纸连接 ----

# Lazily created "cross-sheet connection" dialog. Deliberately UNTYPED: annotating would
# pull the dialog into the startup dependency graph (same rule as _gpOpenLineAttrs).
# 惰性创建的「跨图纸连接」对话框。刻意不写类型：标注会把对话框拉进启动依赖图
#（与 _gpOpenLineAttrs 同一规则）。
var _gpOffPageDialog = null

# The gesture waiting for the dialog's answer: which canvas, which source ref, where.
# 等待对话框回答的手势：哪块画布、哪个源端、落点在哪。
var _gpCrossPending: Dictionary = {}

# One-shot sheet preselect, set when the inspector's peer-sheet dropdown routes a pick here.
# 一次性图纸预选，属性面板的对端图纸下拉把选择路由进来时设置。
var _gpCrossPreselect: String = ""


# A line was dropped out of frame, or an existing connector asked for a peer: open the
# dialog for the CURRENT sheet list. The canvas stays a pure requester.
# 一条线落出图框，或既有连接符请求对端：为**当前**图纸列表打开对话框。
# 画布保持纯请求者身份。
func _gpOnCrossSheetRequested(gpFromRef: Dictionary, gpWorld: Vector2, gpKind: String,
		gpSignalType: String, gpCanvas: GPCanvas2D) -> void:
	var gpPre: String = _gpCrossPreselect
	_gpCrossPreselect = ""
	_gpCrossPending = {"canvas": gpCanvas, "from_ref": gpFromRef, "world": gpWorld,
		"kind": gpKind, "signal_type": gpSignalType, "preselect": gpPre}
	if _gpOffPageDialog == null:
		_gpOffPageDialog = (load("res://src/ui/dialogs/off_page_connect_dialog.gd")
			as GDScript).new()
		add_child(_gpOffPageDialog)
		_gpOffPageDialog.gpConnectChosen.connect(_gpOnCrossSheetChosen)
	# D06: the excluded sheet is the one the SOURCE CANVAS shows — never "whatever tab is
	# active". In multi-view, a non-active pane's gesture used to offer its own sheet as a
	# target; confirming it silently did nothing.
	# D06：被排除的图纸是**源画布**所显示的那张 —— 绝不是「当前哪个标签活动」。多视图下
	# 非活动窗格的手势曾把本图列为可选目标，选中确认后静默无反应。
	var gpLocal: GPSheet = gpCanvas.gpSheet
	_gpOffPageDialog.gpSetup(gpCenter.gpToSheets(), gpDefs,
		gpLocal.gpId if gpLocal != null else "", gpPre)


# The inspector's peer-sheet dropdown picked a sheet for an UNLINKED connector: route the
# pick through the VERY same canvas gesture the context menu uses (one code path into the
# dialog and, behind it, the command), with the sheet handed over as a preselect.
# 属性面板的对端图纸下拉为未连线连接符选定了一张图纸：把该选择路由进与右键菜单
# **完全相同**的画布手势（进入对话框乃至其后的命令只有**一条**代码路径），图纸以预选
# 形式移交。
func _gpOnInspectorConnectPick(gpNodeId: String, gpSheetId: String) -> void:
	var gpCanvas: GPCanvas2D = gpCenter.gpActiveCanvas()
	if gpCanvas == null:
		return
	# RE-CONNECT (user feedback 2026-11-04): the pick can come from a LINKED connector's
	# "跨图编号" dropdown. Break the old link FIRST (one undo step, both flags stay) — the
	# creation path only accepts an UNLINKED connector (mode B), and skipping this would
	# mint a duplicate connector + link. A cancelled dialog leaves the connector honestly
	# unlinked; Ctrl+Z restores the old connection.
	# **重连**（用户反馈 2026-11-04）：选择可能来自**已连接**连接符的「跨图编号」下拉。
	# 先断开旧连接（一个撤销步、两面旗标保留）—— 创建路径只接受**未连接**连接符（模式 B），
	# 跳过这步会铸出重复的连接符与 link。取消对话框则连接符诚实地回到未连接态；
	# Ctrl+Z 恢复旧连接。
	var gpNode: GPPIDNode = gpCanvas.gpGraph.gpGetNode(gpNodeId) \
		if gpCanvas.gpGraph != null else null
	var gpLinkId: String = str(gpNode.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")) \
		if gpNode != null else ""
	if gpLinkId != "":
		if not _gpBreakLinkForReconnect(gpLinkId, gpCanvas):
			return
	_gpCrossPreselect = gpSheetId
	gpCanvas.gpRequestCrossSheet(
		{"node_id": gpNodeId, "port_id": GPSymbolPackOffpage.GP_PORT_NAME},
		Vector2.ZERO, GPPIDEdge.GP_PROCESS, "")


# The reconnect half-step: unlink THIS link through the SAME command the 断开 button uses
# (both flags stay). The peer graph comes from the SHEET TABLE — a hidden (X-closed) peer
# sheet must not block a reconnect. False = refused, nothing opened.
# 重连的半步：经与「断开」按钮**同一条**命令断开本 link（两面旗标保留）。对端图取自
# **图纸表** —— 对端图纸被 X 隐藏时不得阻断重连。假 = 被拒，不打开对话框。
func _gpBreakLinkForReconnect(gpLinkId: String, gpCanvas: GPCanvas2D) -> bool:
	var gpLink: GPOffPageLink = _gpLinkById(gpLinkId)
	if gpLink == null or gpCanvas.gpActions == null or gpCanvas.gpGraph == null:
		return false
	var gpPeerSheetId: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_SHEET, ""))
	if str(gpLink.gpA.get(GPOffPageLink.GP_KEY_SHEET, "")) == gpCanvas.gpSheet.gpId:
		gpPeerSheetId = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_SHEET, ""))
	else:
		gpPeerSheetId = str(gpLink.gpA.get(GPOffPageLink.GP_KEY_SHEET, ""))
	var gpPeerGraph: GPPIDGraph = null
	for gpS in gpCenter.gpToSheets():
		if gpS.gpId == gpPeerSheetId:
			gpPeerGraph = gpS.gpGraph
	if gpPeerGraph == null:
		gpSetState("offpage.refuse_sheet_missing", [])
		return false
	if gpCanvas.gpActions.gpUnlinkOffPage(gpLink, gpCenter.gpOffPageLinks,
			gpCanvas.gpGraph, gpPeerGraph):
		# A2: the store signal already refreshed/dirtied the canvases.
		# A2：store 信号已刷新并标脏画布。
		gpSetState("offpage.unlink_done", [])
		return true
	gpSetState("offpage.unlink_fail", [])
	return false


# The user picked a target and confirmed. Resolve what the dialog cannot know (peer graph,
# drawing number) and hand the WHOLE gesture to the shared creation helper below.
# 用户选定目标并确认。解析对话框无法知晓的事实（对端图、图号），把整个手势交给下方的
# 共用创建助手。
func _gpOnCrossSheetChosen(gpTarget: Dictionary) -> void:
	var gpCanvas: GPCanvas2D = _gpCrossPending.get("canvas")
	if gpCanvas == null or gpTarget.is_empty():
		return
	_gpCreateCrossLink(gpCanvas, _gpCrossPending.get("from_ref", {}),
		str(_gpCrossPending.get("kind", GPPIDEdge.GP_PROCESS)),
		str(_gpCrossPending.get("signal_type", "")),
		_gpCrossPending.get("world", Vector2.ZERO),
		str(gpTarget.get("sheet_id", "")),
		{"node_id": str(gpTarget.get("node_id", "")),
			"port_id": str(gpTarget.get("port_id", ""))})


# THE one creation path for a cross-sheet link, shared by the dialog flow and the W13-S8
# cross-pane drag. Resolves the sheet-level facts (peer sheet, drawing number, twin landing
# slot), decides mode A/B from the fromRef node, runs the command, republishes the render
# snapshot and reports the result. Returns the link id ("" = refused).
# 跨图纸 link 的**唯一**创建路径，对话框流程与 W13-S8 跨窗格拖拽共用。解析图纸级事实
#（对端图、图号、孪生体落位槽）、按 fromRef 节点判定模式 A/B、执行命令、重发渲染快照并
# 报告结果。返回 link id（"" = 被拒）。
func _gpCreateCrossLink(gpCanvas: GPCanvas2D, gpFromRef: Dictionary, gpKind: String,
		gpSignalType: String, gpWorld: Vector2, gpPeerSheetId: String,
		gpServed: Dictionary) -> String:
	if gpCanvas == null or gpCanvas.gpActions == null or gpFromRef.is_empty():
		return ""
	# The LOCAL sheet is the one the SOURCE CANVAS shows — never "whatever tab is active":
	# with multi-view (W13) the two can differ the moment a second pane takes focus.
	# **本端图纸**是**源画布**所显示的那张 —— 绝不是「当前哪个标签活动」：多视图（W13）下
	# 一旦第二窗格获焦，二者就可能不同。
	var gpLocalSheet: GPSheet = gpCanvas.gpSheet
	# D06: every early exit maps to a readable status message — a silent return "" used to
	# leave the user with a closed dialog and zero feedback.
	# D06：每个早退分支都映射到一条可读状态消息 —— 过去静默 return ""，用户只看到对话框
	# 关闭而毫无反馈。
	if gpLocalSheet == null or gpPeerSheetId == "":
		gpSetState("offpage.refuse_sheet_missing", [])
		return ""
	if gpPeerSheetId == gpLocalSheet.gpId:
		gpSetState("offpage.refuse_same_sheet", [])
		return ""
	var gpPeerSheet: GPSheet = null
	for gpS in gpCenter.gpToSheets():
		if gpS.gpId == gpPeerSheetId:
			gpPeerSheet = gpS
	if gpPeerSheet == null:
		gpSetState("offpage.refuse_sheet_missing", [])
		return ""
	if gpPeerSheet.gpGraph == null:
		gpSetState("offpage.refuse_peer_graph_missing", [])
		return ""
	# The twin lands in the peer sheet's LEFT connector column (user feedback 2026-11-03:
	# always on the left, stacked top-down) — never at a bare drop point, and never as a
	# child of the target item.
	# 孪生体落在对端图纸**左侧的连接符列**（用户反馈 2026-11-03：永远在左侧、自上而下堆叠）
	# —— 绝不落在裸落点上，也绝不成为目标对象的子件。
	var gpEnv: Vector2 = GPSymbolCategories.gpSizeFor(GPSymbolPackOffpage.GP_CATEGORY)
	# D16: the column member test is the CATEGORY predicate (user-pack connectors stack too),
	# not a builtin symbol-id list. The shell's own def lookup covers user packs.
	# D16：列成员判定走**类别**判谓（用户包连接符同样参与堆叠），而非内置符号 id 名单。
	# 外壳自带的 def 查找覆盖用户包。
	var gpPeerLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		return gpDefFor(gpSymId)
	var gpPeerPos: Vector2 = GPOffPageIndex.gpNextLeftSlot(gpPeerSheet.gpGraph,
		GPFrameGeometry.gpFrameRect(gpPeerSheet), gpEnv,
		func(gpN: GPPIDNode) -> bool:
			return GPOffPageIndex.gpIsConnectorNode(gpN, gpPeerLookup))
	# The pick is the item the twin serves — but only a node that REALLY exists there (a
	# stale pick degrades to a bare twin, exactly as the dialog path always did).
	# 所选即孪生体要**服务**的对象 —— 但只认对端图上**真实存在**的节点（陈旧所选退化为
	# 裸孪生体，与对话框路径的既有行为完全一致）。
	var gpServedFinal: Dictionary = {}
	if not gpServed.is_empty() \
			and gpPeerSheet.gpGraph.gpGetNode(str(gpServed.get("node_id", ""))) != null:
		gpServedFinal = gpServed
	# MODE B when the gesture started ON an unlinked connector: the link attaches to it and
	# no local node is created.
	# 手势始于**未连接的连接符**时走模式 B：link 直接挂它，不新建本端节点。
	var gpExistingLocal: String = ""
	var gpSourceId: String = str(gpFromRef.get("node_id", ""))
	var gpSource: GPPIDNode = gpCanvas.gpGraph.gpGetNode(gpSourceId) if gpSourceId != "" else null
	var gpSourceIsConnector: bool = gpSource != null \
		and (gpSource.gpSymbolId == GPSymbolPackOffpage.GP_ID_PIPE \
			or gpSource.gpSymbolId == GPSymbolPackOffpage.GP_ID_SIGNAL) \
		and str(gpSource.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")) == ""
	if gpSourceIsConnector:
		gpExistingLocal = gpSourceId
		# D07: the link kind follows the CONNECTOR's own port purpose, not the entry path's
		# guess — re-derived HERE for every entry path (context menu, inspector pick, drag),
		# so a signal connector always produces a SIGNAL link (the inspector used to
		# hardcode PROCESS and DRC immediately flagged kind_mismatch).
		# D07：link 类别跟随**连接符自身的端口用途**，而非入口路径的猜测 —— 在此为所有
		# 入口路径（右键菜单 / 属性面板 / 拖拽）单点重推导，信号连接符必然产出 SIGNAL
		# 连接（属性面板曾硬编码 PROCESS，DRC 立刻报 kind_mismatch）。
		gpKind = _gpKindForConnector(gpSource)
		if gpKind == GPPIDEdge.GP_SIGNAL and gpSignalType == "":
			gpSignalType = "ELECTRIC"
	var gpLinkId: String = gpCanvas.gpActions.gpCrossSheetCreate(gpFromRef, gpKind,
		gpSignalType, true, _gpSnapLocalFlag(gpWorld, gpLocalSheet, gpEnv), gpPeerPos,
		gpLocalSheet.gpId, gpPeerSheetId, gpPeerSheet.gpNumber, gpPeerSheet.gpGraph,
		gpCenter.gpOffPageLinks, gpExistingLocal, {}, gpServedFinal)
	if gpLinkId == "":
		# D24: cross-sheet refusal keys live under offpage.refuse_*, not edge.* — without
		# the prefix the status bar shows a raw key like "edge.same_sheet".
		# D24：跨图纸拒绝键在 offpage.refuse_* 名下而非 edge.* —— 不传前缀状态栏会显示
		# 「edge.same_sheet」这样的裸键。
		gpCanvas.gpReportRefusal(gpCanvas.gpActions.gpLastRefusal, "offpage.refuse_")
		return ""
	# The link table change is announced by the store's signal (A2): snapshot republish,
	# dirty marks and repaints follow from there — no manual refresh here.
	# link 表的变化由 store 信号通告（A2）：快照重发、脏标记与重绘都从那里跟随 —— 此处
	# 不再手工刷新。
	var gpTag: String = ""
	var gpNewLink: GPOffPageLink = null
	for gpL in gpCenter.gpOffPageLinks:
		if gpL != null and gpL.gpInstanceId == gpLinkId:
			gpTag = gpL.gpTag
			gpNewLink = gpL
	# ROUND 3 (user feedback 2026-11-04): a continuation edge may ALREADY stand on the B-end
	# sheet — drawn from the unlinked twin before this link existed (the inspector reconnect
	# flow draws nothing itself). Pull the source block + number through the B-side sheet's
	# own service, exactly as the draw-time pull would have. The mode-A peer connect (created
	# in the same command with the preset tag) no-ops on the tag but still receives the ATTRS.
	# 第三轮（用户反馈 2026-11-04）：B 端图纸上可能**早已立着**一条延续边 —— 本 link 存在前
	# 就从未连接的孪生体画好了（属性面板重连流自己不画线）。经 B 端图纸**自己的**服务拉取
	# 源端属性块与编号，与画线即拉取完全同构。模式 A 的对端连线（同一命令内以预置号创建）
	# 编号相等空转，但**属性**仍会被拉平。
	if gpNewLink != null:
		var gpBNodeId: String = str(gpNewLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
		var gpBSheetId: String = str(gpNewLink.gpB.get(GPOffPageLink.GP_KEY_SHEET, ""))
		if gpBNodeId != "":
			var gpBCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(gpBSheetId)
			if gpBCanvas != null and gpBCanvas.gpGraph != null:
				var gpBEdge: GPPIDEdge = _gpEdgeTouching(gpBCanvas.gpGraph, gpBNodeId)
				if gpBEdge != null:
					_gpPullFollowState(gpBCanvas, gpBEdge.gpInstanceId)
	# D18 (user feedback 2026-11-04): the creation must LAND visibly — flash both flags, and
	# when the peer sheet is not visible anywhere (no pane, not popped out), open it in the
	# first EMPTY pane so the user can see what just happened on the other sheet.
	# D18（用户反馈 2026-11-04）：创建必须有**落地感** —— 两端旗标短促高亮；对端图纸未在
	# 任何视图显示（无窗格、未摘出）时，打开进**第一个空窗格**，让用户看见对端那张图刚发生了什么。
	_gpFlashLinkEnds(gpLinkId)
	if not gpCenter.gpSheetVisible(gpPeerSheetId) \
			and gpCenter.gpOpenSheetInEmptyPane(gpPeerSheetId):
		gpSetState("offpage.status_created_opened", [gpTag])
		return gpLinkId
	gpSetState("offpage.status_created", [gpTag])
	return gpLinkId


# D18: flash BOTH ends of a fresh link — the drop-highlight rect on each end's own canvas,
# cleared after a beat. A token guards against clearing a NEWER highlight (a drag that
# started meanwhile) — only the newest flash may clear.
# D18：新 link 的**两端**短促高亮 —— 各自在所在画布上画落点高亮框，一拍半后清除。令牌防止
# 清掉**更新**的高亮（期间用户开始了拖拽）—— 只有最新一次闪光可以清除。
func _gpFlashLinkEnds(gpLinkId: String) -> void:
	var gpLink: GPOffPageLink = null
	for gpL in gpCenter.gpOffPageLinks:
		if gpL.gpInstanceId == gpLinkId:
			gpLink = gpL
			break
	if gpLink == null:
		return
	var gpEnds: Array = [gpLink.gpA, gpLink.gpB]
	_gpFlashToken += 1
	var gpToken: int = _gpFlashToken
	for gpEnd in gpEnds:
		var gpRef: Dictionary = gpEnd
		var gpCv: GPCanvas2D = gpCenter.gpCanvasForSheetId(
			str(gpRef.get(GPOffPageLink.GP_KEY_SHEET, "")))
		var gpNode: String = str(gpRef.get(GPOffPageLink.GP_KEY_NODE, ""))
		if gpCv != null and gpNode != "":
			gpCv.gpSetDropHighlight(gpNode)
	var gpClear: Callable = func() -> void:
		if gpToken != _gpFlashToken:
			return
		for gpEnd in gpEnds:
			var gpRef2: Dictionary = gpEnd
			var gpCv2: GPCanvas2D = gpCenter.gpCanvasForSheetId(
				str(gpRef2.get(GPOffPageLink.GP_KEY_SHEET, "")))
			var gpNode2: String = str(gpRef2.get(GPOffPageLink.GP_KEY_NODE, ""))
			if gpCv2 != null and is_instance_valid(gpCv2) and gpNode2 != "":
				gpCv2.gpSetDropHighlight("")
	get_tree().create_timer(1.4).timeout.connect(gpClear, CONNECT_ONE_SHOT)


# D07: derive the link kind from the connector's OWN port purpose — the single
# discriminator shared with the generator and the audit (no symbol-id lists anywhere).
# D07：由连接符**自身的端口用途**推导 link 类别 —— 与生成器、审计共用的唯一判据
#（代码里没有任何符号 id 名单）。
func _gpKindForConnector(gpNode: GPPIDNode) -> String:
	if gpNode == null:
		return GPPIDEdge.GP_PROCESS
	var gpDef: GPSymbolDef = gpDefFor(gpNode.gpSymbolId)
	if gpDef != null and not gpDef.gpPortsOfType(GPPort.GP_SIGNAL).is_empty():
		return GPPIDEdge.GP_SIGNAL
	return GPPIDEdge.GP_PROCESS


# D17 minimal fix (user feedback 2026-11-04): the out-of-frame gesture DEFINES the drop
# point as outside the frame — clamp the local flag into the frame rect (pad = half an
# offpage envelope) so it can never print off-paper. The full edge-snapping stays in P3
# (R4); mode B (existing local connector) never consumes this position.
# D17 完整吸附（2026-11-04，R4）：出图框手势的松手点**只决定走向哪一侧** —— 本端旗标吸附
# 进最近图框边的连接符列/行（与对端左列同一套堆叠家族），绝不落在松手点上。退化情形
#（无图框）回落到钳制。模式 B（本端既有连接符）不消费该位置。
func _gpSnapLocalFlag(gpWorld: Vector2, gpSheet: GPSheet, gpEnv: Vector2) -> Vector2:
	if gpSheet == null or gpSheet.gpGraph == null:
		return _gpClampIntoFrame(gpWorld, gpSheet, gpEnv)
	var gpLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		return gpDefFor(gpSymId)
	return GPOffPageIndex.gpSnapSlotFor(gpWorld, gpSheet.gpGraph,
		GPFrameGeometry.gpFrameRect(gpSheet), gpEnv,
		func(gpN: GPPIDNode) -> bool:
			return GPOffPageIndex.gpIsConnectorNode(gpN, gpLookup))


# D17 最小止血的几何钳制（保留为退化回路与模式 B 语义兜底）：把本端旗标钳进图框矩形
#（内边距 = 半个离页连接符包络）。
func _gpClampIntoFrame(gpWorld: Vector2, gpSheet: GPSheet, gpEnv: Vector2) -> Vector2:
	if gpSheet == null:
		return gpWorld
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(gpSheet)
	var gpPad: float = minf(gpEnv.x, gpEnv.y) * 0.5
	var gpLo: Vector2 = gpFrame.position + Vector2(gpPad, gpPad)
	var gpHi: Vector2 = gpFrame.end - Vector2(gpPad, gpPad)
	if gpHi.x <= gpLo.x or gpHi.y <= gpLo.y:
		return gpFrame.get_center()
	return gpWorld.clamp(gpLo, gpHi)


# ---- W13-S8: cross-pane drag-to-connect (the SECOND connection logic) ----
# ---- W13-S8：跨窗格拖拽连线（第二种连接逻辑）----

# The canvas currently showing a drop highlight, and the highlighted node ("" = none).
# 当前显示落点高亮的画布，与被高亮的图元（"" = 无）。
var _gpDragHlCanvas: GPCanvas2D = null
var _gpDragHlNode: String = ""

# D18: token of the newest link-end flash — only the newest may clear the highlights.
# D18：最新一次 link 端闪光令牌 —— 只有最新一次可以清除高亮。
var _gpFlashToken: int = 0

# D23: cross-pane RUBBER BAND — a full-rect, mouse-transparent overlay on the shell that
# draws the pending connection from the SOURCE flag to the pointer, across pane borders.
# D23：跨窗格**橡皮筋** —— 外壳上的满矩形、鼠标透明覆盖层，画出从**源**旗标到指针的
# 待定连接，跨越窗格边界。
var _gpRubber: Control = null
var _gpRubberActive: bool = false
var _gpRubberFrom: Vector2 = Vector2.ZERO
var _gpRubberTo: Vector2 = Vector2.ZERO

# D23: the dragged source connector (canvas + id) so its "connecting" feedback (dimmed
# view) can be restored whatever way the gesture ends.
# D23：被拖拽的源连接符（画布 + id），使它的「连线中」反馈（视图变暗）无论手势如何结束
# 都能恢复。
var _gpDragSrcCanvas: GPCanvas2D = null
var _gpDragSrcNode: String = ""


# A connector is being dragged across panes: highlight the node under the pointer in
# whichever OTHER canvas is under it. The source canvas never highlights itself.
# 连接符正被拖过窗格：在其下方的**另一块**画布中高亮指针下的图元。源画布永不高亮自己。
func _gpOnCrossPaneDragUpdated(gpNodeId: String, gpScreen: Vector2,
		gpSource: GPCanvas2D) -> void:
	# D23: the source flag dims and the rubber band follows the pointer — the gesture is
	# now VISIBLE on the source side too, not just as a rectangle on the target.
	# D23：源旗标变暗、橡皮筋跟随指针 —— 手势在**源**一侧也可见，而不只是目标上的矩形。
	_gpSetDragSourceFeedback(gpSource, gpNodeId, true)
	_gpRubberUpdate(gpSource, gpNodeId, gpScreen)
	# A4: the drag point is SCREEN-space; the host lookup reads the same space.
	# A4：拖拽点是**屏幕**空间；宿主查找读同一空间。
	var gpTarget: GPCanvas2D = gpCenter.gpCanvasAtScreenPoint(gpScreen)
	if gpTarget == gpSource:
		gpTarget = null
	_gpClearDragHighlight()
	if gpTarget == null:
		return
	var gpWorld: Vector2 = gpTarget.gpWorldFromScreen(gpTarget.get_local_mouse_position())
	var gpHit: String = gpTarget.gpHitTest(gpWorld)
	# Same-sheet targets are refused by the creation helper anyway; refusing the HIGHLIGHT
	# too keeps what you see (an accent box) and what you get (a link) in agreement.
	# 同图纸目标本就会被创建助手拒绝；高亮同样拒绝，使「看到的」（accent 框）与「得到的」
	#（一条连接）始终一致。
	if gpHit != "" and gpTarget.gpSheet != null and gpSource.gpSheet != null \
			and gpTarget.gpSheet.gpId == gpSource.gpSheet.gpId:
		return
	_gpDragHlCanvas = gpTarget
	_gpDragHlNode = gpHit
	if gpHit != "":
		gpTarget.gpSetDropHighlight(gpHit)


# The drag was released over a point: resolve the target node and build the link through the
# ONE shared creation path. Kind/signal follow the CONNECTOR's family (pipe vs signal), the
# same defaults the tools use.
# 拖拽在一点上松手：解析目标图元，经**唯一**的共用创建路径建立连接。类型 / 信号随**连接符**
# 的族别（管 / 信号），与工具的默认一致。
func _gpOnCrossPaneDropped(gpNodeId: String, gpScreen: Vector2, gpSource: GPCanvas2D) -> void:
	_gpClearDragHighlight()
	_gpRubberStop()
	_gpSetDragSourceFeedback(gpSource, gpNodeId, false)
	# A4: the drag point is SCREEN-space; the host lookup reads the same space.
	# A4：拖拽点是**屏幕**空间；宿主查找读同一空间。
	var gpTarget: GPCanvas2D = gpCenter.gpCanvasAtScreenPoint(gpScreen)
	# Dropped OUTSIDE every view (canvas + popup): a deliberate cancel — stay silent.
	# 落在所有视图（画布 + 弹窗）**之外**：刻意的取消 —— 保持沉默。
	if gpTarget == null:
		return
	var gpSrcSheet: GPSheet = gpSource.gpSheet
	var gpTgtSheet: GPSheet = gpTarget.gpSheet
	# D23: an invalid drop says WHY — dropping back on the source sheet is the same-sheet
	# refusal, not a silent nothing.
	# D23：无效落点要说明**原因** —— 落回源图纸就是「同图纸不能连」的拒绝，而非无声无息。
	if gpTarget == gpSource or (gpSrcSheet != null and gpTgtSheet != null \
			and gpSrcSheet.gpId == gpTgtSheet.gpId):
		gpSetState("offpage.refuse_same_sheet", [])
		return
	var gpConn: GPPIDNode = gpSource.gpGraph.gpGetNode(gpNodeId)
	if gpConn == null:
		return
	# An ALREADY-LINKED connector cannot start a second link by dragging — the context menu's
	# sync/jump actions own that state. Say so instead of minting a surprise twin at (0,0).
	# **已连接**的连接符不能靠拖拽再起一条 link —— 该状态归右键菜单的同步 / 跳转所有。
	# 明说，而不是在 (0,0) 悄悄铸一个意外的孪生体。
	if str(gpConn.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")) != "":
		gpSetState("offpage.drag_linked", [])
		return
	var gpWorld: Vector2 = gpTarget.gpWorldFromScreen(gpTarget.get_local_mouse_position())
	var gpHit: String = gpTarget.gpHitTest(gpWorld)
	# D23: blank canvas under the pointer is a reason too — point at the ITEM to serve.
	# D23：指针下的空白画布也是一个原因 —— 请指向要**服务**的图元。
	if gpHit == "":
		gpSetState("offpage.drop_blank", [])
		return
	var gpKind: String = GPPIDEdge.GP_PROCESS
	var gpSignalType: String = ""
	if gpConn.gpSymbolId == GPSymbolPackOffpage.GP_ID_SIGNAL:
		gpKind = GPPIDEdge.GP_SIGNAL
		gpSignalType = "ELECTRIC"
	# The drop node is what the twin serves; its port is the def's FIRST (the dialog stays
	# the place for a considered port choice — the drag is the quick gesture).
	# 落点图元即孪生体的服务对象；端口取定义的**第一个**（深思的端口选择留给对话框 ——
	# 拖拽是快速手势）。
	var gpPort: String = ""
	var gpHitNode: GPPIDNode = gpTarget.gpGraph.gpGetNode(gpHit)
	var gpHitDef: GPSymbolDef = gpTarget.gpDefFor(gpHitNode.gpSymbolId) if gpHitNode != null else null
	if gpHitDef != null and not gpHitDef.gpPorts.is_empty():
		gpPort = gpHitDef.gpPorts[0].gpName
	_gpCreateCrossLink(gpSource,
		{"node_id": gpNodeId, "port_id": GPSymbolPackOffpage.GP_PORT_NAME},
		gpKind, gpSignalType, Vector2.ZERO, gpTgtSheet.gpId,
		{"node_id": gpHit, "port_id": gpPort})


# The gesture ended without a drop (ESC): clear the highlight.
# 手势未落点即结束（ESC）：清除高亮。
func _gpOnCrossPaneDragEnded() -> void:
	_gpClearDragHighlight()
	_gpRubberStop()
	if _gpDragSrcCanvas != null and _gpDragSrcNode != "":
		_gpSetDragSourceFeedback(_gpDragSrcCanvas, _gpDragSrcNode, false)


# Clear the drop highlight (idempotent).
# 清除落点高亮（幂等）。
func _gpClearDragHighlight() -> void:
	if _gpDragHlCanvas != null and is_instance_valid(_gpDragHlCanvas):
		_gpDragHlCanvas.gpSetDropHighlight("")
	_gpDragHlCanvas = null
	_gpDragHlNode = ""


# D23: dim ("connecting…") or restore the dragged SOURCE connector's view. Idempotent; the
# remembered source refs are set here so ANY ending path can restore them.
# D23：把被拖拽**源**连接符的视图调暗（「连线中」）或恢复。幂等；源引用在此记忆，
# 使任何结束路径都能恢复。
func _gpSetDragSourceFeedback(gpCanvas: GPCanvas2D, gpNodeId: String, gpOn: bool) -> void:
	if gpCanvas == null or gpCanvas.gpBinder == null or gpNodeId == "":
		return
	if gpOn:
		_gpDragSrcCanvas = gpCanvas
		_gpDragSrcNode = gpNodeId
	var gpView: GPSymbolView = gpCanvas.gpBinder.gpGetSymbolView(gpNodeId)
	if gpView != null and is_instance_valid(gpView):
		gpView.modulate = Color(1.0, 1.0, 1.0, 0.55) if gpOn else Color.WHITE
	if not gpOn:
		_gpDragSrcCanvas = null
		_gpDragSrcNode = ""


# D23: lazily create the rubber-band overlay (full-rect, mouse-transparent, topmost).
# D23：惰性创建橡皮筋覆盖层（满矩形、鼠标透明、最顶层）。
func _gpEnsureRubber() -> Control:
	if _gpRubber != null and is_instance_valid(_gpRubber):
		return _gpRubber
	var gpOv: Control = Control.new()
	gpOv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gpOv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpOv.draw.connect(_gpOnRubberDraw)
	add_child(gpOv)
	gpOv.move_to_front()
	_gpRubber = gpOv
	return gpOv


# The rubber band paint: accent line source→pointer plus a pointer dot, in GLOBAL space
# mapped into the overlay's local frame (the overlay spans the whole shell).
# 橡皮筋绘制：源→指针的 accent 线加指针圆点，**全局**空间映射进覆盖层的本地坐标系
#（覆盖层横跨整个外壳）。
func _gpOnRubberDraw() -> void:
	if not _gpRubberActive or _gpRubber == null:
		return
	var gpInv: Transform2D = _gpRubber.get_global_transform().affine_inverse()
	var gpA: Vector2 = gpInv * _gpRubberFrom
	var gpB: Vector2 = gpInv * _gpRubberTo
	_gpRubber.draw_line(gpA, gpB, Color(1.0, 0.62, 0.20, 0.85), 2.0)
	_gpRubber.draw_circle(gpB, 4.0, Color(1.0, 0.62, 0.20, 0.9))


# D23: refresh the rubber band from the source flag's global position to the pointer.
# D23：把橡皮筋从源旗标的**全局**位置刷新到指针。
func _gpRubberUpdate(gpSource: GPCanvas2D, gpNodeId: String, gpScreen: Vector2) -> void:
	if gpSource == null or gpSource.gpGraph == null:
		return
	var gpConn: GPPIDNode = gpSource.gpGraph.gpGetNode(gpNodeId)
	if gpConn == null:
		return
	_gpRubberFrom = gpSource.get_global_transform() * gpSource.gpScreenFromWorld(gpConn.gpPosition)
	# A4: the drag point arrives in SCREEN space; the overlay paints in the MAIN window's
	# global space — convert through the main window's screen transform.
	# A4：拖拽点以**屏幕**空间到达；覆盖层在**主窗**全局空间绘制 —— 经主窗 screen transform 换算。
	_gpRubberTo = get_viewport().get_screen_transform().affine_inverse() * gpScreen
	_gpRubberActive = true
	_gpEnsureRubber().queue_redraw()


# D23: stop the rubber band. / D23：停止橡皮筋。
func _gpRubberStop() -> void:
	if not _gpRubberActive:
		return
	_gpRubberActive = false
	if _gpRubber != null and is_instance_valid(_gpRubber):
		_gpRubber.queue_redraw()


# Navigation: switch to the peer sheet and select the peer connector.
# 导航：切到对端图纸并选中对端连接符。
func _gpOnJumpToPeer(gpNodeId: String) -> void:
	if not gpCenter.gpJumpToPeerConnector(gpNodeId):
		gpSetState("offpage.jump_missing", [])


# "Sync to peer": make the PEER end match THIS end, through the link's contract snapshot,
# as one undoable step. Reading the values from the local edge keeps one rule: the local
# sheet is where the edit happened.
# 「同步到对端」：经 link 的契约快照让**对端**与本端一致，一步可撤销。值取自本端边
# 保持了单一规则：编辑发生在本端图纸。
func _gpOnSyncToPeer(gpNodeId: String) -> void:
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpLink: GPOffPageLink = GPOffPageIndex.gpLinkForNode(gpNodeId)
	if gpLink == null:
		return
	var gpLocalEdge: GPPIDEdge = _gpEdgeTouching(gpCanvas.gpGraph, gpNodeId)
	var gpPeer: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpNodeId)
	var gpPeerGraph: GPPIDGraph = null
	for gpS in gpCenter.gpToSheets():
		if gpS.gpId == str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")):
			gpPeerGraph = gpS.gpGraph
	var gpPeerEdge: GPPIDEdge = _gpEdgeTouching(gpPeerGraph,
		str(gpPeer.get(GPOffPageLink.GP_KEY_NODE, "")))
	var gpEdges: Array[GPPIDEdge] = [gpLocalEdge, gpPeerEdge]
	var gpValues: Dictionary = {}
	if gpLocalEdge != null:
		for gpKey in GPCrossSheetSyncCommand.GP_CONTRACT_KEYS:
			if (gpLocalEdge.gpAttrs as Dictionary).has(gpKey):
				gpValues[gpKey] = gpLocalEdge.gpAttrs[gpKey]
	if gpCanvas.gpActions.gpCrossSheetSync(gpLink, gpValues, gpEdges, gpPeerGraph):
		# A2: the store signal already refreshed/dirtied both canvases.
		# A2：store 信号已刷新并标脏两端画布。
		gpSetState("offpage.sync_done", [])


# Every B-side continuation edge fed by the edge with this id on this canvas: one entry per
# link whose A-end connector the edge feeds — {"link", "canvas", "edge"}. Shared by the tag
# and the attribute propagation handlers, so both walk the SAME list (one definition of
# "what follows this line").
# 本画布上由该 id 的边馈送的每条 B 端延续边：接入本边（A 端连接符）的 link 各一条 ——
# {"link", "canvas", "edge"}。编号与属性两个传播处理器共用，走**同一**份清单
# （「什么跟随这条线」只有一个定义）。
func _gpBsideContinuations(gpCanvas: GPCanvas2D, gpEdgeId: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return gpOut
	var gpLocalSheetId: String = gpCanvas.gpSheet.gpId if gpCanvas.gpSheet != null else ""
	if gpLocalSheetId == "":
		return gpOut
	for gpLink in gpCenter.gpOffPageLinks:
		if gpLink == null:
			continue
		var gpA: Dictionary = gpLink.gpA
		if str(gpA.get(GPOffPageLink.GP_KEY_SHEET, "")) != gpLocalSheetId:
			continue
		var gpANodeId: String = str(gpA.get(GPOffPageLink.GP_KEY_NODE, ""))
		# The edited edge must be the line that feeds THIS link's A-end connector.
		# 被改的边必须是接入本 link A 端连接符的那条线。
		if not _gpEdgeTouchesNode(gpCanvas.gpGraph, gpEdgeId, gpANodeId):
			continue
		var gpPeer: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpANodeId)
		var gpPeerCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(
			str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")))
		if gpPeerCanvas == null or gpPeerCanvas.gpGraph == null:
			continue
		var gpPeerEdge: GPPIDEdge = _gpEdgeTouching(gpPeerCanvas.gpGraph,
			str(gpPeer.get(GPOffPageLink.GP_KEY_NODE, "")))
		if gpPeerEdge == null:
			continue
		gpOut.append({"link": gpLink, "canvas": gpPeerCanvas, "edge": gpPeerEdge})
	return gpOut


# ROUND 3 PULL (user feedback 2026-11-04): when a B-side continuation edge FIRST exists —
# drawn after the link was made, or already standing when the link was created (the inspector
# reconnect flow) — its local state is still the freshly minted defaults while follow mode is
# already ON (tag_manual absent). The locked panel displays the SOURCE values, so only the
# canvas exposes the drift. One pull, through the edge's OWN sheet service (its undo stack,
# its dirty flag, B3): the inheritable attribute block blind-written as ONE step, then the
# source number through the dedicated tag path (propagated, so the follow chain stays alive).
# Both writes are idempotent — equality guards make a repeated pull a no-op, which is what
# keeps the created-signal → pull → tag-commit → pull chain terminating.
# 第三轮拉取（用户反馈 2026-11-04）：B 端延续边**首次**存在时 —— link 建好后才画的线，或
# link 建立（属性面板重连流）时就已立在那里的线 —— 本地状态还是刚铸的默认值，而跟随模式
# 已经开启（无 tag_manual）。锁定面板显示**源端**值，只有画布暴露漂移。拉取一次，走这条边
# **自己**图纸的服务（它的撤销栈、它的脏标记，B3）：可继承属性块一步盲写，随后源端编号走
# 专用编号通道（带传播标记，跟随链保持存活）。两次写入皆幂等 —— 相等守卫使重复拉取成为
# 空转，这正是「画成信号 → 拉取 → 编号落账 → 再拉取」链条能够收敛的原因。
func _gpPullFollowState(gpCanvas: GPCanvas2D, gpEdgeId: String) -> void:
	if gpCanvas == null or gpCanvas.gpGraph == null or gpCanvas.gpActions == null:
		return
	var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
	if gpEdge == null or gpEdge.gpKind == GPPIDEdge.GP_SIGNAL:
		return
	# Opted out: the block is deliberate, never touched again.
	# 已选择退出：整个属性块是刻意选择，此后绝不再碰。
	if bool(gpEdge.gpAttrs.get("tag_manual", false)):
		return
	var gpSrc: Dictionary = _gpSourceOfBSideEdge(gpCanvas, gpEdgeId)
	var gpVals: Dictionary = gpSrc.get("values", {}) as Dictionary
	var gpSrcTag: String = str(gpSrc.get("tag", ""))
	if not gpVals.is_empty():
		gpCanvas.gpActions.gpSetEdgeAttrs(gpEdgeId, gpVals)
	if gpSrcTag != "" and gpEdge.gpTag != gpSrcTag:
		if gpCanvas.gpActions.gpSetEdgeTag(gpEdgeId, gpSrcTag, true):
			gpSetState("offpage.inherit_done", [gpSrcTag])
		else:
			gpSetState("offpage.inherit_fail",
				[I18n.gpTr(gpCanvas.gpActions.gpLastRefusal)])


# An edge was DRAWN on some sheet (gpEdgeCreated): if it feeds a B-end twin, pull now.
# 某张图纸画成了一条边（gpEdgeCreated）：若它馈送某个 B 端孪生体，此刻即拉取。
func _gpOnEdgeCreated(gpEdgeId: String, gpCanvas: GPCanvas2D) -> void:
	_gpPullFollowState(gpCanvas, gpEdgeId)


# A line number was committed on SOME sheet: propagate it to every cross-sheet continuation
# edge that follows this sheet (the A side), unless the peer edge opted out
# (attrs["tag_manual"], user feedback 2026-11-04). Refusals (rule / on-sheet duplicate) are
# reported without blocking the source edit — the source sheet stays authoritative.
# 某张图纸的管线号落账：把它传播到跟随本图纸（A 端）的每一条跨图纸延续边，除非对端边
# 已选择退出（attrs["tag_manual"]，用户反馈 2026-11-04）。拒绝（规则 / 同图重号）只报告、
# 不阻塞源端编辑 —— 源图纸始终是权威侧。
func _gpOnEdgeTagCommitted(gpEdgeId: String, _gpOldTag: String, gpNewTag: String,
		gpCanvas: GPCanvas2D) -> void:
	if gpNewTag == "" or gpCanvas == null or gpCanvas.gpGraph == null:
		return
	for gpCont in _gpBsideContinuations(gpCanvas, gpEdgeId):
		var gpPeerEdge: GPPIDEdge = gpCont["edge"] as GPPIDEdge
		var gpPeerCanvas: GPCanvas2D = gpCont["canvas"] as GPCanvas2D
		# Opted out (the checkbox): the number is deliberate, never touched again.
		# 已选择退出（勾选框）：编号是刻意选择，此后绝不再碰。
		if bool(gpPeerEdge.gpAttrs.get("tag_manual", false)):
			continue
		if gpPeerEdge.gpTag == gpNewTag:
			continue
		# The retag goes through the PEER sheet's own edit service: its undo stack, its
		# dirty flag, its notify (B3). gpPropagated keeps the follow alive.
		# 改号走**对端**图纸自己的编辑服务：它的撤销栈、它的脏标记、它的通知（B3）。
		# gpPropagated 使跟随关系保持存活。
		if gpPeerCanvas.gpActions.gpSetEdgeTag(gpPeerEdge.gpInstanceId, gpNewTag, true):
			gpSetState("offpage.inherit_done", [gpNewTag])
		else:
			gpSetState("offpage.inherit_fail",
				[I18n.gpTr(gpPeerCanvas.gpActions.gpLastRefusal)])


# Line ATTRIBUTES were committed on SOME sheet (user feedback 2026-11-04, round 2): forward
# the INHERITABLE ones to every followed continuation edge this edge feeds, then keep the
# peer's number in step — an attribute edit re-renders the SOURCE number, and the peer's
# number is the inherited one, so a drift is pulled back here. Peer writes go through the
# PEER sheet's own service (its undo stack, its dirty flag, B3): ONE batch blind-write that
# never re-renders the number, and the batch command never re-emits — no recursion.
# 某张图纸的管线**属性**落账（用户反馈 2026-11-04 第二轮）：把**可继承**的那些转发给本边
# 馈送的每条跟随中的延续边，并让对端号保持同步 —— 属性编辑会重渲染**源端**号，而对端号是
# 继承值，故在此拉平漂移。对端写入走**对端**图纸自己的服务（它的撤销栈、脏标记，B3）：
# 一次批量盲写、绝不重渲染号；批量命令绝不再发射 —— 无递归。
func _gpOnEdgeAttrsCommitted(gpEdgeId: String, gpKeys: Array[String],
		gpCanvas: GPCanvas2D) -> void:
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpSrcEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
	if gpSrcEdge == null:
		return
	var gpInheritable: Dictionary = {}
	for gpKey in GPInspector.gpEdgeInheritKeys(gpSrcEdge, gpCanvas.gpGraph.gpStandard):
		gpInheritable[gpKey] = true
	var gpValues: Dictionary = {}
	for gpKey in gpKeys:
		if not gpInheritable.has(gpKey):
			continue
		if gpSrcEdge.gpAttrs.has(gpKey):
			gpValues[gpKey] = gpSrcEdge.gpAttrs[gpKey]
		else:
			# The source CLEARED the key (blank = clear): erase it on the peer too.
			# 源端**清除**了该键（空白 = 清除）：对端同步清除。
			gpValues[gpKey] = null
	for gpCont in _gpBsideContinuations(gpCanvas, gpEdgeId):
		var gpPeerEdge: GPPIDEdge = gpCont["edge"] as GPPIDEdge
		var gpPeerCanvas: GPCanvas2D = gpCont["canvas"] as GPCanvas2D
		# Opted out: the whole block is deliberate, never touched again.
		# 已选择退出：整个属性块是刻意选择，此后绝不再碰。
		if bool(gpPeerEdge.gpAttrs.get("tag_manual", false)):
			continue
		var gpPeerId: String = gpPeerEdge.gpInstanceId
		if not gpValues.is_empty():
			if gpPeerCanvas.gpActions.gpSetEdgeAttrs(gpPeerId, gpValues):
				gpSetState("offpage.attr_inherit_done", [", ".join(gpValues.keys())])
		# The source's number may have been re-rendered by this attribute edit: pull the
		# peer number back in step (the dedicated tag path, propagated).
		# 本次属性编辑可能已重渲染源端号：把对端号拉回同步（走专用编号通道，带传播标记）。
		if gpSrcEdge.gpTag != "" and gpPeerEdge.gpTag != gpSrcEdge.gpTag:
			if not gpPeerCanvas.gpActions.gpSetEdgeTag(gpPeerId, gpSrcEdge.gpTag, true):
				gpSetState("offpage.inherit_fail",
					[I18n.gpTr(gpPeerCanvas.gpActions.gpLastRefusal)])
		# Live refresh: when the peer edge currently on show IS this one, rebuild its form.
		# 实时刷新：若当前显示的对端边**正是**这条，重建其表单。
		if gpInspector.gpCurrentEdge != null \
				and gpInspector.gpCurrentEdge.gpInstanceId == gpPeerId:
			gpInspector.gpShowEdge(gpPeerEdge)


# Visibility + follow state of the inherit checkbox for ONE edge: shown only on a B-side
# continuation (the edge touching a link's B-end connector); the A side IS the authority and
# has nothing to inherit. In follow mode it also carries the source's CURRENT number and
# attribute block, so the locked form displays the source rather than a possibly stale local
# copy (user feedback 2026-11-04, round 2). Pure glue over the container link table.
# 单条边的继承勾选框可见性与跟随状态：仅在 B 端延续段（触及 link B 端连接符的边）显示；
# A 端本身就是权威侧，无继承可言。跟随模式下还携带源端**当前**的编号与属性块，使锁定表单
# 显示源端而非可能过期的本地副本（用户反馈 2026-11-04 第二轮）。容器 link 表之上的纯粘合。
func _gpEdgeInheritInfo(gpEdgeId: String) -> Dictionary:
	var gpOut: Dictionary = {"show": false, "follow": false, "src_tag": "", "src_attrs": {}}
	for gpT in gpCenter.gpTabs:
		var gpCanvas: GPCanvas2D = gpT.get("canvas") as GPCanvas2D
		if gpCanvas == null or gpCanvas.gpGraph == null:
			continue
		var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
		if gpEdge == null:
			continue
		for gpLink in gpCenter.gpOffPageLinks:
			if gpLink == null:
				continue
			var gpBNode: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
			if gpBNode != "" and _gpEdgeTouchesNode(gpCanvas.gpGraph, gpEdgeId, gpBNode):
				gpOut["show"] = true
				gpOut["follow"] = not bool(gpEdge.gpAttrs.get("tag_manual", false))
				var gpPeer: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpBNode)
				var gpSrcCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(
					str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")))
				if gpSrcCanvas != null and gpSrcCanvas.gpGraph != null:
					var gpSrcEdge: GPPIDEdge = _gpEdgeTouching(gpSrcCanvas.gpGraph,
						str(gpPeer.get(GPOffPageLink.GP_KEY_NODE, "")))
					if gpSrcEdge != null:
						gpOut["src_tag"] = gpSrcEdge.gpTag
						gpOut["src_attrs"] = gpSrcEdge.gpAttrs.duplicate(true)
				return gpOut
	return gpOut


# The source edge's CURRENT number + inheritable attribute block for a B-side edge, resolved
# through its link: {"tag", "values"} (values empty when no source is resolvable). Used by
# the inherit checkbox: snapshot on opt-out, full pull on re-follow.
# 经 link 解析 B 端边源端的**当前**编号＋可继承属性块：{"tag", "values"}（解析不出源端时
# values 为空）。供继承勾选框使用：退出时快照，恢复跟随时全量拉取。
func _gpSourceOfBSideEdge(gpCanvas: GPCanvas2D, gpEdgeId: String) -> Dictionary:
	var gpOut: Dictionary = {"tag": "", "values": {}}
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return gpOut
	var gpLink: GPOffPageLink = _gpLinkForBSideEdge(gpCanvas.gpGraph, gpEdgeId)
	if gpLink == null:
		return gpOut
	var gpBNode: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
	var gpPeer: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpBNode)
	var gpSrcCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(
		str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")))
	if gpSrcCanvas == null or gpSrcCanvas.gpGraph == null:
		return gpOut
	var gpSrcEdge: GPPIDEdge = _gpEdgeTouching(gpSrcCanvas.gpGraph,
		str(gpPeer.get(GPOffPageLink.GP_KEY_NODE, "")))
	if gpSrcEdge == null:
		return gpOut
	gpOut["tag"] = gpSrcEdge.gpTag
	for gpKey in GPInspector.gpEdgeInheritKeys(gpSrcEdge,
			gpSrcCanvas.gpGraph.gpStandard):
		if gpSrcEdge.gpAttrs.has(gpKey):
			gpOut["values"][gpKey] = gpSrcEdge.gpAttrs[gpKey]
	return gpOut


# The checkbox toggled on a B-side continuation edge (user feedback 2026-11-04, round 2).
# Off: the number AND the attribute block become manual — the source's CURRENT values are
# snapshotted first (one undo step), so the segment keeps showing what the source showed and
# is now independently editable. On: the flag is cleared and the CURRENT source number AND
# the whole attribute block are pulled immediately, so "re-follow" never leaves a stale
# value anywhere.
# B 端延续边上的勾选框开关（用户反馈 2026-11-04 第二轮）。取消：编号**与属性块**都转为手选
# —— 先快照源端**当前**值（一个撤销步），本段继续显示源端所显示的内容、从此可独立编辑。
# 勾选：清除标记并**立即**拉取源端当前编号**与整个属性块** —— 「恢复跟随」绝不在任何地方
# 留下过期值。
func _gpOnEdgeInheritToggled(gpEdgeId: String, gpFollow: bool) -> void:
	var gpCanvas: GPCanvas2D = _gpCanvasOfEdgeId(gpEdgeId)
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
	if gpEdge == null:
		return
	var gpSrc: Dictionary = _gpSourceOfBSideEdge(gpCanvas, gpEdgeId)
	var gpVals: Dictionary = gpSrc.get("values", {}) as Dictionary
	if not gpFollow:
		gpCanvas.gpActions.gpSetEdgeAttr(gpEdgeId, "tag_manual", true)
		if not gpVals.is_empty():
			gpCanvas.gpActions.gpSetEdgeAttrs(gpEdgeId, gpVals)
		gpSetState("offpage.inherit_off", [])
		return
	# Resume following: clear the flag (null = erase, per GPSetEdgeAttrCommand), then pull.
	# 恢复跟随：清除标记（null = 删除，见 GPSetEdgeAttrCommand），然后拉取。
	gpCanvas.gpActions.gpSetEdgeAttr(gpEdgeId, "tag_manual", null)
	if not gpVals.is_empty():
		gpCanvas.gpActions.gpSetEdgeAttrs(gpEdgeId, gpVals)
	var gpSrcTag: String = str(gpSrc.get("tag", ""))
	if gpSrcTag == "" or gpEdge.gpTag == gpSrcTag:
		gpSetState("offpage.inherit_on", [gpSrcTag])
		return
	if gpCanvas.gpActions.gpSetEdgeTag(gpEdgeId, gpSrcTag, true):
		gpSetState("offpage.inherit_done", [gpSrcTag])
	else:
		gpSetState("offpage.inherit_fail", [I18n.gpTr(gpCanvas.gpActions.gpLastRefusal)])


# The link whose B-end connector the edge feeds, or null.
# 该边接入其 B 端连接符的 link，否则 null。
func _gpLinkForBSideEdge(gpG: GPPIDGraph, gpEdgeId: String) -> GPOffPageLink:
	if gpG == null:
		return null
	for gpLink in gpCenter.gpOffPageLinks:
		if gpLink == null:
			continue
		var gpBNode: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
		if gpBNode != "" and _gpEdgeTouchesNode(gpG, gpEdgeId, gpBNode):
			return gpLink
	return null


# The canvas whose graph holds this edge (tab scan; the sheet count is small).
# 图中持有这条边的画布（扫描标签页；图纸数量很小）。
func _gpCanvasOfEdgeId(gpEdgeId: String) -> GPCanvas2D:
	for gpT in gpCenter.gpTabs:
		var gpCanvas: GPCanvas2D = gpT.get("canvas") as GPCanvas2D
		if gpCanvas == null or gpCanvas.gpGraph == null:
			continue
		if gpCanvas.gpGraph.gpGetEdge(gpEdgeId) != null:
			return gpCanvas
	return null


# Whether the edge with this id touches the node with this id.
# 该 id 的边是否触及该 id 的节点。
static func _gpEdgeTouchesNode(gpG: GPPIDGraph, gpEdgeId: String, gpNodeId: String) -> bool:
	if gpG == null or gpNodeId == "":
		return false
	var gpE: GPPIDEdge = gpG.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	return str(gpE.gpFromRef.get("node_id", "")) == gpNodeId \
		or str(gpE.gpToRef.get("node_id", "")) == gpNodeId


# Deletion case ① (ADR-43 §2.5): connectors are in the delete selection. Resolve each one's
# link + peer, show ONE confirmation naming the peer sheets, then cascade the whole
# connection in one command per link. Connectors WITHOUT a resolvable link fall back to the
# plain delete — a dangling flag is a local object, nothing to cascade.
# 删除情形①（ADR-43 §2.5）：删除选择集中出现了连接符。解析每个的 link 与对端，
# 弹**一个**确认框列出对端图纸，确认后每条 link 一个命令级联删除。解析不出 link 的
# 连接符回退普通删除 —— 悬空旗标是本地对象，无级联可言。
func _gpOnCrossSheetDelete(gpConnectorIds: Array[String], gpCanvas: GPCanvas2D) -> void:
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpPlans: Array[Dictionary] = []
	var gpDangling: Array[String] = []
	for gpNid in gpConnectorIds:
		var gpN: GPPIDNode = gpCanvas.gpGraph.gpGetNode(gpNid)
		if gpN == null:
			continue
		var gpLink: GPOffPageLink = null
		for gpL in gpCenter.gpOffPageLinks:
			if gpL != null and gpL.gpInstanceId == str(gpN.gpProps.get(
					GPOffPageLink.GP_KEY_LINK_ID, "")):
				gpLink = gpL
				break
		if gpLink == null:
			gpDangling.append(gpNid)
			continue
		gpPlans.append({"link": gpLink, "local": gpNid})
	if gpDangling.size() > 0:
		gpCanvas.gpActions.gpDeleteSelection(gpDangling, [], [],
			gpCanvas.gpDefLookupCallable())
	if gpPlans.is_empty():
		return
	# One line per link: tag + peer sheet label (number, else tab name).
	# 每 link 一行：编号 + 对端图纸标签（图号，否则标签名）。
	var gpLines: String = ""
	for gpPlan in gpPlans:
		var gpLink: GPOffPageLink = gpPlan["link"] as GPOffPageLink
		gpLines += I18n.gpTr("offpage.del_line") % [_gpLinkTag(gpLink),
			_gpPeerSheetLabel(gpLink, gpCanvas.gpSheet.gpId if gpCanvas.gpSheet != null else "")] + "\n"
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("offpage.del_title")
	gpDlg.dialog_text = I18n.gpTr("offpage.del_text") % [gpLines.strip_edges()]
	gpDlg.ok_button_text = I18n.gpTr("dialog.ok")
	gpDlg.cancel_button_text = I18n.gpTr("dialog.cancel")
	add_child(gpDlg)
	gpDlg.confirmed.connect(_gpOnCrossSheetDeleteConfirmed.bind(gpPlans, gpCanvas))
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.popup_centered()


# The confirmed half: run one cascade command per link, then refresh the snapshot.
# 确认后的半步：每条 link 一个级联命令，然后刷新快照。
func _gpOnCrossSheetDeleteConfirmed(gpPlans: Array[Dictionary], gpCanvas: GPCanvas2D) -> void:
	var gpLookup: Callable = gpCanvas.gpDefLookupCallable()
	for gpPlan in gpPlans:
		var gpLink: GPOffPageLink = gpPlan["link"] as GPOffPageLink
		var gpLocalId: String = str(gpPlan["local"])
		var gpPeerRef: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpLocalId)
		var gpPeerId: String = str(gpPeerRef.get(GPOffPageLink.GP_KEY_NODE, ""))
		var gpPeerGraph: GPPIDGraph = null
		for gpS in gpCenter.gpToSheets():
			if gpS.gpId == str(gpPeerRef.get(GPOffPageLink.GP_KEY_SHEET, "")):
				gpPeerGraph = gpS.gpGraph
		if gpPeerGraph == null or gpPeerId == "":
			continue
		gpCanvas.gpActions.gpCrossSheetDelete(gpLink, [gpLocalId], [gpPeerId],
			gpPeerGraph, gpCenter.gpOffPageLinks, gpLookup)
	# A2: deletions were announced through the link store; nothing to refresh by hand.
	# A2：删除已通过 link store 通告；无需手工刷新。
	gpCanvas.gpEditFacade.gpSetSelection([])
	gpSetState("offpage.del_done", [])


# The tag for display: the manual tag when set, else the instance id.
# 显示用编号：有手改编号用编号，否则用实例 id。
static func _gpLinkTag(gpLink: GPOffPageLink) -> String:
	return gpLink.gpTag if gpLink.gpTag != "" else gpLink.gpInstanceId


# U3: UNLINK from the inspector action row — the link leaves the container table, both
# connector flags stay on their sheets as honest unlinked placeholders, one undo step.
# U3：属性面板动作行的「断开」—— link 离开容器表，两面连接符旗标留在各自图纸上成为
# 诚实的未连接占位，一个撤销步。
func _gpOnInspectorUnlink(gpLinkId: String) -> void:
	var gpLink: GPOffPageLink = _gpLinkById(gpLinkId)
	if gpLink == null:
		return
	var gpLocalCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(
		str(gpLink.gpA.get(GPOffPageLink.GP_KEY_SHEET, "")))
	var gpPeerCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(
		str(gpLink.gpB.get(GPOffPageLink.GP_KEY_SHEET, "")))
	if gpLocalCanvas == null or gpLocalCanvas.gpActions == null \
			or gpPeerCanvas == null or gpPeerCanvas.gpGraph == null:
		return
	if gpLocalCanvas.gpActions.gpUnlinkOffPage(gpLink, gpCenter.gpOffPageLinks,
			gpLocalCanvas.gpGraph, gpPeerCanvas.gpGraph):
		# A2: the store signal already refreshed/dirtied the canvases.
		# A2：store 信号已刷新并标脏画布。
		gpSetState("offpage.unlink_done", [])
	else:
		gpSetState("offpage.unlink_fail", [])


# U3: DELETE the whole pair from the inspector action row — same confirmed cascade as the
# canvas context menu, pre-planned for THIS link only (the user aimed at one link).
# U3：属性面板动作行的「删除」—— 与画布右键菜单相同的**确认后**级联，但只预计划本条
# link（用户瞄准的就是这一条）。
func _gpOnInspectorLinkDelete(gpLinkId: String) -> void:
	var gpLink: GPOffPageLink = _gpLinkById(gpLinkId)
	if gpLink == null:
		return
	var gpLocalSheetId: String = str(gpLink.gpA.get(GPOffPageLink.GP_KEY_SHEET, ""))
	var gpCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(gpLocalSheetId)
	if gpCanvas == null:
		return
	var gpPlans: Array[Dictionary] = [{"link": gpLink,
		"local": str(gpLink.gpA.get(GPOffPageLink.GP_KEY_NODE, ""))}]
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("offpage.del_title")
	gpDlg.dialog_text = I18n.gpTr("offpage.del_text") % [I18n.gpTr("offpage.del_line")
		% [_gpLinkTag(gpLink), _gpPeerSheetLabel(gpLink, gpLocalSheetId)]]
	gpDlg.ok_button_text = I18n.gpTr("dialog.ok")
	gpDlg.cancel_button_text = I18n.gpTr("dialog.cancel")
	add_child(gpDlg)
	gpDlg.confirmed.connect(_gpOnCrossSheetDeleteConfirmed.bind(gpPlans, gpCanvas))
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.popup_centered()


# The link with this instance id in the container table, or null.
# 容器表中该实例 id 的 link，否则 null。
func _gpLinkById(gpLinkId: String) -> GPOffPageLink:
	for gpL in gpCenter.gpOffPageLinks:
		if gpL != null and gpL.gpInstanceId == gpLinkId:
			return gpL
	return null


# Peer sheet label for confirm dialogs: the end that is NOT the local sheet (D08: the old
# first-hit loop always returned the LOCAL sheet — gpA is the local end by construction —
# the exact reverse of what the user must confirm).
# 确认框的对端图纸标签：取**非本端图纸**的那一端（D08：旧的「首个命中」循环恒返回本端
# —— gpA 按构造就是本端 —— 与用户要确认的信息正好相反）。
func _gpPeerSheetLabel(gpLink: GPOffPageLink, gpLocalSheetId: String) -> String:
	for gpEnd in [gpLink.gpB, gpLink.gpA]:
		var gpSheetId: String = str((gpEnd as Dictionary).get(GPOffPageLink.GP_KEY_SHEET, ""))
		if gpSheetId == gpLocalSheetId:
			continue
		for gpS in gpCenter.gpToSheets():
			if gpS.gpId == gpSheetId:
				return gpS.gpNumber if gpS.gpNumber != "" else gpS.gpName
	return GPOffPageIndex.GP_UNRESOLVED_TEXT


# The first edge that touches a node, or null. Good enough for a contract sync: a connector
# has at most one line INTO it on each sheet.
# 触及某节点的第一条边，否则 null。对契约同步足够：一只连接符在每张图纸上至多有一条接入线。
static func _gpEdgeTouching(gpG: GPPIDGraph, gpNodeId: String) -> GPPIDEdge:
	if gpG == null or gpNodeId == "":
		return null
	for gpE in gpG.gpEdges:
		if str(gpE.gpFromRef.get("node_id", "")) == gpNodeId \
				or str(gpE.gpToRef.get("node_id", "")) == gpNodeId:
			return gpE
	return null


# All sheets, for the DRC's whole-project mode (and the export gate's equivalent check).
# 全部图纸，供 DRC 全工程模式（以及导出闸门的等价检查）使用。
func _gpDrcSheets() -> Array:
	if gpCenter == null:
		return []
	return gpCenter.gpToSheets()


# Container link table for the DRC off-page audit (W12-S4).
# 供 DRC 跨图纸审计用的容器 link 表（W12-S4）。
func _gpDrcLinks() -> Array[GPOffPageLink]:
	if gpCenter == null:
		return []
	return gpCenter.gpOffPageLinks


# Bind the DRC panel to the active canvas (called wherever the outline is bound, too).
# 把 DRC 面板指向活动画布（与大纲绑定的每个入口一起调用）。
func _gpBindDrc() -> void:
	if gpDrcPanel == null:
		return
	var gpCv: GPCanvas2D = gpActiveCanvas()
	if gpCv != null:
		gpDrcPanel.gpBindCanvas(gpCv)
		if gpRuleScheduler != null:
			gpRuleScheduler.gpBind(gpCv, gpDefs)


# Run the health check on the active sheet and expose the counts in the status bar.
# 对当前图纸跑体检，并把计数显示到状态栏。
#
# Public because the menu dispatcher calls it; keeping the tab-focusing here means every entry
# (menu, future shortcut) lands on the same visible surface instead of a silent background run.
# 设为公开供菜单分发调用；把「切到该页」放在这里，使每个入口（菜单、将来的快捷键）都落在同一个
# 可见界面上，而不是静默跑一次。
func gpRunDrc() -> void:
	if gpDrcPanel == null:
		return
	_gpBindDrc()
	gpDrcPanel.gpRun()
	# Bring the tab forward: a check whose result the user cannot see is not a check.
	# 把该页切到前面：用户看不见结果的体检不算体检。
	for gpI in range(gpTabs.get_tab_count()):
		if gpTabs.get_tab_control(gpI) == gpDrcPanel:
			gpTabs.current_tab = gpI
			break
	var gpFound: Array[GPFinding] = gpDrcPanel.gpFindings()
	gpSetState("status.drc_done", [
		GPDrcEngine.gpCount(gpFound, GPFinding.GP_ERROR),
		GPDrcEngine.gpCount(gpFound, GPFinding.GP_WARNING),
		GPDrcEngine.gpCount(gpFound, GPFinding.GP_INFO),
	])


# Centre the view on a finding (B2). Vector2.INF means "no location" and is ignored.
# 把视图对准某条发现（B2）。Vector2.INF 表示「无位置」，忽略。
func _gpOnDrcJump(gpWorld: Vector2) -> void:
	if gpWorld == Vector2.INF:
		return
	var gpCv: GPCanvas2D = gpActiveCanvas()
	if gpCv == null:
		return
	gpCv.gpFocusWorld(gpWorld)


# Open the top-toolbar DRC result dialog (ADR-39 UI). It stays non-modal so clicking a row can
# take the user to the canvas and the property panel without closing the list.
# 打开顶部工具栏的 DRC 结果弹窗（ADR-39 UI）。非模态，故点行后用户能到画布/属性面板，列表不关。
func gpShowDrcDialog() -> void:
	if gpDrcDialog == null:
		gpDrcDialog = GPDRCDialog.new()
		gpDrcDialog.name = "DrcDialog"
		add_child(gpDrcDialog)
		gpDrcDialog.gpFindingActivated.connect(_gpOnDrcFindingFromDialog)
	gpDrcDialog.gpOpenFor(gpActiveCanvas(), Callable(self, "_gpDrcSheets"),
		Callable(self, "_gpDrcLinks"))


# A row in the DOCK panel: locate + select, but do NOT switch tabs (the user may be reading the
# DRC list and must stay there until they choose the property tab themselves).
# 停靠面板的行：定位 + 选中，但**不**切页（用户可能正在看 DRC 列表，应由他自己切属性页）。
func _gpOnDrcFindingFromPanel(gpFinding: GPFinding) -> void:
	_gpFocusFinding(gpFinding, false)


# A row in the DIALOG: locate + select + switch to the property tab.
# 弹窗的行：定位 + 选中 + 切到属性页。
func _gpOnDrcFindingFromDialog(gpFinding: GPFinding) -> void:
	_gpFocusFinding(gpFinding, true)


# Live DRC result: refresh the dock panel silently (never switch tabs). Project mode is a
# manual, whole-project run and must not be overwritten by a sheet-only live pass.
# 实时 DRC 结果：静默刷新右侧面板（绝不切页）。全工程模式是手动整包运行，不能被单页实时结果覆盖。
# Keep the screen-space badges in step with the panel's current list (manual or live run).
# 让屏幕空间角标与面板当前列表保持一致（手动或实时运行）。
func _gpOnDrcFindingsForOverlay(gpFindings: Array[GPFinding]) -> void:
	if gpRuleOverlay != null:
		gpRuleOverlay.gpShow(gpFindings, _gpActiveSheetId())


func _gpActiveSheetId() -> String:
	var gpSheet: GPSheet = gpCenter.gpActiveSheet() if gpCenter != null else null
	return gpSheet.gpId if gpSheet != null else ""


func _gpOnLiveDrc(gpFindings: Array[GPFinding], gpCanvas: GPCanvas2D) -> void:
	if gpCanvas == null or gpCanvas != gpActiveCanvas():
		return
	if gpDrcPanel == null or gpDrcPanel.gpIsProjectMode():
		return
	gpDrcPanel.gpBindCanvas(gpCanvas)
	gpDrcPanel.gpShowFindings(gpFindings)
	if gpRuleOverlay != null:
		gpRuleOverlay.gpShow(gpFindings, _gpActiveSheetId())


# Shared focus/selection. `gpSwitchToProps` is the single behavioural difference between the
# dialog and the dock panel.
# 共用定位/选中。`gpSwitchToProps` 是弹窗与停靠面板唯一的行为差异。
func _gpFocusFinding(gpFinding: GPFinding, gpSwitchToProps: bool, gpRetry: bool = true) -> void:
	if gpFinding == null:
		return
	# Project mode may point at another sheet: activate it first, then use the (new) active canvas.
	# 全工程模式可能指向另一张图纸：先激活它，再用新的活动画布。
	if gpFinding.gpSheetId != "" and gpCenter != null:
		var gpBefore: GPSheet = gpCenter.gpActiveSheet()
		gpCenter.gpActivateSheet(gpFinding.gpSheetId)
		var gpAfter: GPSheet = gpCenter.gpActiveSheet()
		if gpAfter == null or gpAfter.gpId != gpFinding.gpSheetId:
			# TabBar may publish the change on the next frame; retry once instead of focusing
			# the previous sheet (which is exactly the "click does nothing" symptom).
			# TabBar 可能下一帧才发布切换；重试一次，避免聚焦上一张图纸（正是「点了没反应」）。
			if gpRetry:
				call_deferred("_gpFocusFinding", gpFinding, gpSwitchToProps, false)
			return
	var gpCv: GPCanvas2D = gpActiveCanvas()
	if gpCv == null:
		return
	# Title block / frame findings belong to the SHEET, not to a graph node. Select/focus them
	# through the sheet-furniture rect and show the DOC tab (their real property page).
	# 图签 / 图框类发现属于**图纸**而非图节点。按图纸陈设矩形定位，并打开 DOC（它们真正的属性页）。
	if _gpIsSheetFurnitureFinding(gpFinding) and gpCv.gpSheet != null:
		var gpFurniture: Rect2 = GPFrameGeometry.gpFrameRect(gpCv.gpSheet) \
			if gpFinding.gpCheckId.find("frame") >= 0 \
			else GPFrameGeometry.gpTitleBlockRect(gpCv.gpSheet)
		gpCv.gpFocusRect(gpFurniture)
		if gpRuleOverlay != null:
			gpRuleOverlay.gpShowFocusRect(gpFurniture)
		if gpSwitchToProps:
			gpTabs.current_tab = 2
		return
	# Graph entity: fit its rect (edge / node) or a small window around a shape point.
	# 图实体：按矩形适配（连线 / 节点），注释图形则围绕其点开小窗。
	if gpRuleOverlay != null:
		gpRuleOverlay.gpShowFocusRect(Rect2())
	if gpFinding.gpEdgeId != "":
		var gpEdgeRect: Rect2 = gpCv.gpEdgeRect(gpFinding.gpEdgeId)
		if gpEdgeRect.size != Vector2.ZERO:
			gpCv.gpFocusRect(gpEdgeRect, 2.5)
		elif gpFinding.gpWorld != Vector2.INF:
			gpCv.gpFocusRect(Rect2(gpFinding.gpWorld - Vector2(50.0, 35.0), Vector2(100.0, 70.0)), 2.5)
	elif gpFinding.gpNodeId != "":
		var gpNodeRect: Rect2 = gpCv.gpNodeRect(gpFinding.gpNodeId)
		if gpNodeRect.size != Vector2.ZERO:
			gpCv.gpFocusRect(gpNodeRect, 2.5)
		elif gpFinding.gpWorld != Vector2.INF:
			gpCv.gpFocusRect(Rect2(gpFinding.gpWorld - Vector2(50.0, 35.0), Vector2(100.0, 70.0)), 2.5)
	elif gpFinding.gpWorld != Vector2.INF:
		gpCv.gpFocusWorld(gpFinding.gpWorld)
	var gpSelected: bool = false
	if gpFinding.gpEdgeId != "" and gpCv.gpGraph != null \
			and gpCv.gpGraph.gpGetEdge(gpFinding.gpEdgeId) != null:
		gpCv.gpSetEdgeSelection([gpFinding.gpEdgeId])
		gpSelected = true
	elif gpFinding.gpNodeId != "" and gpCv.gpGraph != null \
			and gpCv.gpGraph.gpGetNode(gpFinding.gpNodeId) != null:
		gpCv.gpEdgeSel.clear()
		gpCv.gpShapeSel.clear()
		gpCv.gpSetSelection([gpFinding.gpNodeId])
		gpSelected = true
	elif gpFinding.gpShapeIdx >= 0 and gpCv.gpGraph != null \
			and gpFinding.gpShapeIdx < gpCv.gpGraph.gpShapes.size():
		gpCv.gpEdgeSel.clear()
		gpCv.gpSelection.clear()
		gpCv.gpShapeSel = [gpFinding.gpShapeIdx]
		gpCv.gpAnnounceShapeSelection()
		gpSelected = true
	if gpSwitchToProps and gpSelected:
		gpTabs.current_tab = 0


# Whether a finding targets the sheet's title block / frame rather than a graph entity.
# 判断一条发现是否指向图纸的图签 / 图框，而非图实体。
func _gpIsSheetFurnitureFinding(gpFinding: GPFinding) -> bool:
	if gpFinding.gpNodeId != "" or gpFinding.gpEdgeId != "" or gpFinding.gpShapeIdx >= 0:
		return false
	var gpId: String = gpFinding.gpCheckId if gpFinding.gpCheckId != "" else gpFinding.gpRuleId
	return gpId.begins_with("drc.doc.") or gpFinding.gpRuleId == "drc.sheet_fit"


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
	if gpDrcPanel != null:
		gpTabs.set_tab_title(gpTabs.get_tab_count() - 1, I18n.gpTr("drc.panel_title"))
	if gpDrcPanel != null:
		gpDrcPanel.gpRefreshText()
	if gpOutline != null:
		gpTabs.set_tab_title(gpTabs.get_tab_count() - 2, I18n.gpTr("outline.title"))
		gpOutline.gpRefreshText()
	gpDocLabel.text = I18n.gpTr("doc.info")
	gpSetState(gpStateKey, gpStateArgs)


func _gpOnGraphChanged(_gpGraph: GPPIDGraph = null) -> void:
	gpSelCoord.gpOnGraphChanged(_gpGraph)
	if gpOutline != null:
		gpOutline.gpRefresh()


func _gpOnStatus(gpInfo: Dictionary) -> void:
	gpSelCoord.gpOnStatus(gpInfo)


# 宿主对外端口（Host service ports）
# 下列方法把各协调者的服务中继给「兄弟协调者」，由宿主充当中介，使协调者之间无需互相持有。
# 它们刻意不加下划线前缀 —— 调用方是其它类，属于公开 API，而非类内私有实现。
# The methods below relay a coordinator's service to sibling coordinators; the host acts as
# the mediator so no coordinator ever holds another directly. They are deliberately NOT
# underscore-prefixed: their callers are other classes, so they are public API rather than
# class-private implementation.
func gpRefreshSelection() -> void:
	gpSelCoord.gpRefreshSelection()
	# The tree mirrors the selection; without this, picking a symbol on the canvas leaves the
	# outline pointing at whatever was selected before.
	# 树镜像选择；少了这一步，在画布上点选图元后大纲会停在之前选中的行。
	if gpOutline != null:
		gpOutline.gpRefreshSelection()


func gpSyncInspectorDefs() -> void:
	gpSymbolLibCoord.gpSyncInspectorDefs()


func gpReconcileLibraryDrift(gpGraph: GPPIDGraph) -> void:
	gpSymbolLibCoord.gpReconcileLibraryDrift(gpGraph)


func gpMenuUndo() -> void:
	gpMenuCoord.gpMenuUndo()


func gpMenuRedo() -> void:
	gpMenuCoord.gpMenuRedo()


func gpOpenSettings() -> void:
	gpMenuCoord.gpOpenSettings()


func gpDeleteSelected() -> void:
	gpMenuCoord.gpDeleteSelected()


func gpSetState(gpKey: String, gpArgs: Array = []) -> void:
	gpStateKey = gpKey
	gpStateArgs = gpArgs
	var gpFmt: String = I18n.gpTr(gpKey)
	gpStateLabel.text = gpFmt % gpArgs if gpArgs.size() > 0 else gpFmt


func gpDefFor(gpTypeId: String) -> GPSymbolDef:
	for gpD in gpDefs:
		if gpD.gpId == gpTypeId:
			return gpD
	return null


# Find a graph node by its id.
# 按 id 查找图节点。
func gpNodeFor(gpId: String) -> GPPIDNode:
	var gpG: GPPIDGraph = gpActiveGraph()
	if gpG == null:
		return null
	for gpN in gpG.gpNodes:
		if gpN.gpInstanceId == gpId:
			return gpN
	return null
