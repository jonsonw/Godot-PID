class_name GPMainWindow
extends GPShellHost
# Copyright © 2026 Jonson Wang
# Main scene controller: ASSEMBLY ONLY. The CAD-style layout (top menu / left palette / center
# canvas / right inspector tabs / bottom status bar) is FROZEN in main.tscn. This script wires
# the static nodes together, builds the coordinators, and injects the dynamic content.
# 主场景控制器：**只做装配**。CAD 风格布局（顶部菜单 / 左侧图元库 / 中心画布 / 右侧属性标签页 /
# 底部状态栏）固化于 main.tscn。本脚本把静态节点接起来、构建协调者、并注入动态内容。
#
# WHAT STAYED / 留下了什么：
# Only what the ROOT alone touches: its own furniture (outline / backpack / DRC panel / DRC
# dialog / rule scheduler / rule overlay) and the cross-sheet controller it assembles. Every
# member a coordinator reaches now lives in GPShellHost, so this file cannot silently become
# the API again — an undeclared reach is a parse error, not a code review miss.
# 只留**根类独享**的东西：它自己的陈设（大纲 / 背包 / DRC 面板 / DRC 弹窗 / 规则调度器 /
# 规则角标）以及它装配的跨图纸控制器。协调者会触达的每个成员现在都在 GPShellHost 里，
# 故本文件不可能再次悄悄变成 API —— 未声明的伸手是解析错误，而不是评审疏忽。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Right property-inspector dock (hidden in fullscreen mode).
# 右侧属性面板停靠栏（全屏时隐藏）。
var gpRightDock: VBoxContainer

# GPRibbonCoordinator（Ribbon 与工具栏的构建、样式、模式映射与工具选中转发）。
# Ribbon and toolbar construction, styling, mode mapping and tool-selection forwarding.
# ⚠️ ROOT-PRIVATE: no coordinator reaches it and no contract relay uses it, so it stays here
# under contract rule 1. / 根类私有：无协调者触达、也无契约中继使用，按契约规则 1 留在根类。
var gpRibbonCoord: GPRibbonCoordinator = null

# GPLayoutCoordinator（分隔条比例、DPI 缩放、窗口尺寸响应与最大化）。
# Splitter ratios, DPI scaling, window resize handling and maximised start-up.
var gpLayoutCoord: GPLayoutCoordinator = null

# Document metadata label on the Doc tab.
# 文档标签页上的文档元数据标签。
var gpDocLabel: Label

# Hierarchy outline panel (mount tree of the active sheet). Added as the fourth tab of the right
# dock at runtime, so scenes/main.tscn keeps its exact byte shape.
# 层级大纲面板（当前图纸的挂载树）。运行时作为右栏第四个标签加入，故 scenes/main.tscn 字节不变。
# ⚠️ ROOT-PRIVATE: no coordinator reaches it; the mirror is published through
# gpOnSelectionMirrored(). / 根类私有：无协调者触达；镜像经 gpOnSelectionMirrored() 发布。
var gpOutline: GPOutlinePanel = null

# The symbol backpack popup (A11). Null until assembly; created once and reused, so opening it a
# hundred times does not rebuild a hundred popups.
# 图元背包弹窗（A11）。装配前为 null；创建一次并复用，使开一百次也不会建一百个弹窗。
var gpBackpack: GPSymbolBackpack = null


# GPCrossSheetController（跨图纸连接域：连接 / 继承 / 跳转 / 同步 / 删除，以及两类拖拽手势）。
# 本类只持有它、装配它、把画布与面板的信号接上去 —— 跨图纸的**逻辑**不在本文件里。
# Cross-sheet link domain (connect / inherit / navigate / sync / delete + the two drag
# gestures). This class only owns it, assembles it and binds signals to it — the cross-sheet
# LOGIC does not live in this file any more.
var gpCrossSheet: GPCrossSheetController = null

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
	_gpAssembleDrcPanel()
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
	get_window().close_requested.connect(gpFileCoord.gpOnCloseRequested)
	# Autosave: build its timer now; it stays idle until the first manual save arms it (ADR-9).
	# 自动保存：现在构建其计时器；在首次手动保存启用它之前保持空闲（ADR-9）。
	gpFileCoord.gpSetupAutoSave()


# Reload user-exported symbol packs, then publish the live default defs to gpDefs.
# 重新载入用户导出的图元包，并把当前默认定义发布到 gpDefs。
func _gpLoadSymbolLibrary() -> void:
	# Install symbol persistence FIRST (ADR-2 / ADR-10). The library is core and may not open
	# user://; without this call every custom symbol would silently fail to reload — and the
	# failure would look like "the palette lost my symbols", not like a layering mistake.
	# 先装入图元持久化（ADR-2 / ADR-10）。图元库属 core，不可开 user://；缺这一句则所有自定义
	# 图元会**静默**加载失败 —— 而失败表现是「图元库丢了我的图元」，不像分层错误。
	GPSymbolPackStore.gpInstall()
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


# Build the cross-sheet controller and inject its four dependencies.
# 构建跨图纸控制器并注入它的四项依赖。
# Ordering: this MUST run after gpCenter / gpInspector / gpDefs exist and BEFORE gpAddTab(),
# because creating the first tab fires _gpOnCanvasReady, which binds that canvas's
# cross-sheet signals here. gpAddTab() is the last line of _gpAssembleCenter for that reason.
# 顺序：必须在 gpCenter / gpInspector / gpDefs 就位之后、gpAddTab() **之前**运行，因为
# 创建首个标签会触发 _gpOnCanvasReady，而它要在这里绑定该画布的跨图纸信号。
# gpAddTab() 因此是 _gpAssembleCenter 的最后一行。
func _gpAssembleCrossSheet() -> void:
	gpCrossSheet = GPCrossSheetController.new()
	gpCrossSheet.name = "CrossSheet"
	add_child(gpCrossSheet)
	gpCrossSheet.gpCenter = gpCenter
	gpCrossSheet.gpInspector = gpInspector
	# Deliberately a Callable, NOT the array: gpDefs is reassigned six times at runtime
	# (project import / symbol delete), so a captured array would silently go stale.
	# 刻意传 Callable 而非数组：gpDefs 在运行期会被重新赋值六次（导入工程 / 删图元），
	# 直接捕获数组会静默过期。
	gpCrossSheet.gpDefsProvider = Callable(self, "gpDefsSnapshot")
	gpCrossSheet.gpStateSink = Callable(self, "gpSetState")


# Build the DRC presenter and inject its four dependencies. MUST run after gpTabs / gpCenter
# exist and BEFORE gpAddTab(): creating the first sheet fires canvas-ready, and that is where the
# live scheduler is bound. The dock TAB is a separate phase for a frozen reason — see
# _gpAssembleDrcPanel.
# 构建 DRC 呈现器并注入四项依赖。必须在 gpTabs / gpCenter 就位后、gpAddTab() **之前**运行：
# 创建首张图纸会触发 canvas-ready，而实时调度器正是在那里被绑定。停靠**页**另起一步，
# 原因见 _gpAssembleDrcPanel。
func _gpAssembleDrc() -> void:
	gpDrc = GPDrcPresenter.new()
	gpDrc.name = "DrcPresenter"
	add_child(gpDrc)
	gpDrc.gpTabs = gpTabs
	gpDrc.gpCenter = gpCenter
	gpDrc.gpDefsProvider = Callable(self, "gpDefsSnapshot")
	gpDrc.gpStateSink = Callable(self, "gpSetState")
	gpDrc.gpCreateRuntime()


# Add the DRC dock tab. Two ordering constraints, both silent when broken:
#  1) AFTER the first sheet — gpCreatePanel() ends by binding the ACTIVE canvas; built earlier it
#     would sit unbound until the user happened to switch tabs;
#  2) AFTER the outline — the right dock reads Property / Info / Doc / Outline / DRC, and
#     _gpRefreshStaticText() addresses the outline as `count - 2`. Insert DRC earlier and the next
#     locale change silently gives the outline the DRC title.
# 加 DRC 停靠页。两条顺序约束，破了都是静默的：
#  1) 在首张图纸**之后** —— gpCreatePanel() 结尾要绑**活动**画布；更早构建会一直未绑定，
#     直到用户碰巧切页；
#  2) 在**大纲之后** —— 右栏顺序为 属性 / 信息 / 说明 / 大纲 / DRC，而 _gpRefreshStaticText()
#     按 `count - 2` 定位大纲。更早插入 DRC 页，下次切换语言时大纲会静默用上 DRC 的标题。
func _gpAssembleDrcPanel() -> void:
	if gpDrc != null:
		gpDrc.gpCreatePanel()


# Wire the tabbed drawing area and create the FIRST sheet. Runs after the inspector and
# status labels exist, because adding a tab refreshes the inspector immediately.
# 接上多标签绘图区并创建首张图纸。须在属性面板与状态标签就位之后运行，
# 因为新建标签会立刻刷新属性面板。
func _gpAssembleCenter() -> void:
	gpCenter = $VLayout/Body/Center
	_gpAssembleCrossSheet()
	_gpAssembleDrc()
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
	# The panel's CROSS-SHEET face is wired by the controller that answers those questions:
	# off-page links, peer jump / unlink / delete, the peer-sheet dropdown, the inherit
	# checkbox. Eight wires used to sit here and only resembled shell work — every handler
	# on the right-hand side already lived in GPCrossSheetController, and the two providers
	# reach for gpCenter, which is that controller's own dependency.
	# 面板的**跨图纸**面由回答这些问题的控制器接线：跨页连接、对端跳转 / 断开 / 删除、
	# 对端图纸下拉、继承勾选框。原先此处有八条，看着像外壳的活 —— 而右侧每个处理器本就住在
	# GPCrossSheetController 里，两个 provider 要的 gpCenter 也是那个控制器自有的依赖。
	gpCrossSheet.gpWireInspector()
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
	# The live scheduler is bound to this canvas's DATA here (the view -> model conversion lives
	# in the presenter, which may not hold a canvas). Contract: gpDrc exists before the first tab.
	# 实时调度器在此绑到本画布的**数据**（视图 → 模型的转换在呈现器里，它不可持有画布）。
	# 契约：gpDrc 在首个标签页之前就已就位。
	gpDrc.gpOnCanvasReady(gpCanvas)
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
	# ADR-43/46 + W13-S8: the cross-sheet wiring — 11 canvas signals and the container link
	# store — is a named method on the controller that owns those handlers. S1 extracted the
	# cross-sheet LOGIC out of this file but left its WIRING here, so every new gesture still
	# meant editing the root. A signal added to GPCanvas2D now belongs in gpWireCanvas().
	# ADR-43/46 + W13-S8：跨图纸接线 —— 11 个画布信号与容器 link store —— 是持有这些处理器的
	# 控制器上的具名方法。S1 把跨图纸**逻辑**抽出了本文件，却把**接线**留在这里，故每加一个
	# 手势仍要改根类。今后画布新增信号，归宿是 gpWireCanvas()。
	gpCrossSheet.gpWireCanvas(gpCanvas)
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
	gpDrc.gpOnActiveSheetChanged()


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
	# The DRC panel follows the same three entry points (assembly / new sheet / tab switch), so
	# the bind lives here — but through the presenter's entry, not its furniture.
	# DRC 面板跟随同样这三条入口（装配 / 新建图纸 / 切换标签），故绑定放这里 ——
	# 但走呈现器的入口，不碰它的陈设。
	if gpDrc != null:
		gpDrc.gpBindActive()


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
	if gpDrc != null:
		gpDrc.gpRefreshText()
	if gpOutline != null:
		gpTabs.set_tab_title(gpTabs.get_tab_count() - 2, I18n.gpTr("outline.title"))
		gpOutline.gpRefreshText()
	gpDocLabel.text = I18n.gpTr("doc.info")
	gpSetState(gpStateKey, gpStateArgs)


# ============================ contract overrides ============================
# ============================ 契约覆写 ============================
# The shell contract refreshes the inspector and then asks the root to mirror the selection
# wherever else it must appear. This root mirrors it into the hierarchy outline.
# 外壳契约先刷新属性面板，再请根类把选中镜像到其它必须出现的位置。本根类镜像到大纲树。
func gpOnSelectionMirrored() -> void:
	if gpOutline != null:
		gpOutline.gpRefreshSelection()
