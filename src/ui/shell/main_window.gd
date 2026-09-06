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
var gpFileDialog: FileDialog

# What the in-flight file dialog is for: "save" or "open".
# 当前文件对话框的用途：save 或 open。
var gpPendingFileAction: String = ""

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

# Last selected node id, used to detect selection changes.
# 上一次选中的节点 id，用于检测选中变化。
var gpLastSel: String = ""

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


# Wire the static scene together and set up initial state.
# 将静态场景拼接起来并设置初始状态。
func _ready() -> void:
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

	# ---- menu ----
	# ---- 菜单 ----
	gpMenuBar.gpActionTriggered.connect(_gpOnMenu)

	# ---- drawing toolbar row under the menu bar ----
	# ---- 菜单栏下方的绘图工具栏行 ----
	_gpBuildToolBar()

	# ---- file dialog (open / save-as) ----
	# ---- 文件对话框（打开 / 另存为） ----
	gpFileDialog = FileDialog.new()
	gpFileDialog.access = FileDialog.ACCESS_FILESYSTEM
	gpFileDialog.add_filter("*.pid.json", I18n.gpTr("doc.pid_filter"))
	gpFileDialog.file_selected.connect(_gpOnFileSelected)
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
	gpCanvas.gpGraphChanged.connect(_gpOnGraphChanged)
	gpCanvas.gpStatusUpdated.connect(_gpOnStatus)
	# Double click / context menu on a symbol asks for in-place geometry editing.
	# 图元上的双击 / 右键菜单会请求就地编辑几何。
	gpCanvas.gpSymbolEditRequested.connect(_gpOnSymbolEditRequested)
	# Promote selected annotation shapes into a real symbol: open the Make-Symbol dialog.
	# 把选中的注释图形提升为真正图元：打开「生成图元」对话框。
	gpCanvas.gpMakeSymbolRequested.connect(_gpOnMakeSymbolFromShapes)
	# Keep the drawing toolbar highlight in sync when the mode changes (e.g. via context menu).
	# 模式变化时（如右键菜单）同步绘图工具栏高亮。
	gpCanvas.gpModeChanged.connect(_gpSyncToolBar)


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
				gpC.gpGraphChanged.emit()
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
func _gpOnGraphChanged() -> void:
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

	if gpSel != gpLastSel:
		gpLastSel = gpSel
		_gpRefreshSelection()


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
		gpInspector.gpShow(null, null)
		gpInfoLabel.text = I18n.gpTr("symbol_lib.no_selection")
		return

	var gpNode: GPPIDNode = _gpNodeFor(gpId)
	if gpNode == null:
		gpInspector.gpShow(null, null)
		gpInfoLabel.text = I18n.gpTr("symbol_lib.no_selection")
		return

	var gpDef: GPSymbolDef = _gpDefFor(gpNode.gpSymbolId)
	gpInspector.gpShow(gpDef, gpNode)

	var gpCat: String = I18n.gpTr(gpDef.gpCategory) if gpDef else "—"
	var gpSize: String = str(gpDef.gpDefaultSize) if gpDef else "—"
	gpInfoLabel.text = "%s：%s\n%s：%s\n%s：%s\n%s：%s" % [
		I18n.gpTr("info.id"), gpId,
		I18n.gpTr("info.type"), gpNode.gpSymbolId,
		I18n.gpTr("info.category"), gpCat,
		I18n.gpTr("info.size"), gpSize]


# React to an attribute edit in the inspector.
# 响应属性面板中的属性编辑。
func _gpOnAttrChanged(gpId: String, gpKey: String, gpVal) -> void:
	var gpNode: GPPIDNode = _gpNodeFor(gpId)
	if gpNode == null:
		return
	if gpKey == "label":
		gpNode.gpTag = gpVal
	else:
		gpNode.gpAttrValues[gpKey] = gpVal
	gpActiveCanvas().queue_redraw()
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
			_gpSaveProject(false)
		"file_save_as":
			_gpSaveProject(true)
		"file_open":
			_gpOpenProject()
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
		"tool_settings":
			_gpOpenSettings()
		_:
			_gpSetState("status.feature_todo", [gpAction])


# ============================ project save / open ============================
# ============================ 工程存盘 / 打开 ============================
# Save the active project. Reuses the last path unless gpForcePick is true (Save As).
# 保存当前工程。除非 gpForcePick 为真（另存为），否则复用上次的路径。
func _gpSaveProject(gpForcePick: bool) -> void:
	if gpForcePick or gpCurrentPath == "":
		# No path yet (or Save As): ask the user via the file dialog.
		# 尚无路径（或另存为）：用文件对话框询问用户。
		gpPendingFileAction = "save"
		gpFileDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		gpFileDialog.popup_centered()
		return
	_gpWriteProject(gpCurrentPath)


# Open an existing project from disk.
# 从磁盘打开已有工程。
func _gpOpenProject() -> void:
	gpPendingFileAction = "open"
	gpFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	gpFileDialog.popup_centered()


# Forward the file-dialog result to the right handler.
# 把文件对话框的结果转交给对应处理。
func _gpOnFileSelected(gpPath: String) -> void:
	if gpPendingFileAction == "save":
		_gpWriteProject(gpPath)
	elif gpPendingFileAction == "open":
		_gpReadProject(gpPath)


# Serialize the active graph (with embedded user packs) and write it to disk.
# 把活动图（含内嵌用户图元包）序列化并写入磁盘。
# The actual file mechanics live in GPProjectIO (single source of truth for *.pid.json);
# this method only owns UI-side concerns (embedding packs, status, path bookkeeping).
# 真正的文件机制在 GPProjectIO（*.pid.json 的单一事实来源）；本方法仅负责 UI 关注点
# （嵌入图元包、状态栏、路径记账）。
func _gpWriteProject(gpPath: String) -> void:
	# Embed custom user packs so the file is self-contained (data sovereignty).
	# 嵌入用户自定义图元包，使文件自包含（数据主权）。
	gpActiveGraph().gpEmbedUserPacks(GPSymbolLibrary.gpUserPacks())
	var gpFilePath: String = GPProjectIO.gpEnsurePidExt(gpPath)
	var gpErr: int = GPProjectIO.gpWriteProject(gpActiveGraph(), gpFilePath)
	if gpErr != OK:
		_gpSetState("status.save_fail", [gpFilePath])
		return
	gpCurrentPath = gpFilePath
	var gpPackCount: int = gpActiveGraph().gpUserSymbolPacks.size()
	_gpSetState("status.saved_with_packs", [gpFilePath, gpPackCount])


# Read a project from disk and swap it into the active canvas.
# 从磁盘读入工程并替换为当前活动画布。
# File parsing/decoding is delegated to GPProjectIO; the graph-swap and UI refresh that
# follow remain here because they touch the canvas, dock and selection state.
# 文件解析/解码交给 GPProjectIO；其后的图切换与 UI 刷新仍在此处，因为它们涉及画布、停靠栏与选择状态。
func _gpReadProject(gpPath: String) -> void:
	var gpNewGraph: GPPIDGraph = GPProjectIO.gpReadProject(gpPath)
	if gpNewGraph == null:
		_gpSetState("status.load_fail", [gpPath])
		return
	# Rebuild the graph; gpFromDict also reconciles embedded user packs into the
	# live library so custom symbols are available again after reopening.
	# 重建图；gpFromDict 同时把内嵌用户包调和进活动图元库，使重新打开后自定义图元再次可用。
	gpCenter.gpSetActiveGraph(gpNewGraph)
	gpActiveCanvas().gpGraph = gpNewGraph
	gpDefs = GPSymbolLibrary.gpDefaultDefs()
	gpLeftDock.gpPopulate(gpDefs)
	gpActiveCanvas().gpDefs = gpDefs
	gpActiveCanvas().gpClearSelection()
	gpActiveCanvas().gpConnectFrom = ""
	gpActiveCanvas().gpShapeSel.clear()
	gpActiveCanvas().queue_redraw()
	gpCurrentPath = gpPath
	_gpSetState("status.loaded_with_packs", [gpPath, gpNewGraph.gpUserSymbolPacks.size()])


# Open the settings dialog.
# 打开设置对话框。
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
# Build the toolbar row and insert it between the menu bar and the body in the root VBox.
# 构建工具栏行并插入到根 VBox 的菜单栏与主体之间。
# Drawing tools (line / circle / rectangle / polyline) switch the canvas into a direct-draw
# mode — annotation shapes are drawn on the main canvas, and can then be promoted into a real
# symbol (select → right-click "Make Symbol").
# 绘图工具（直线 / 圆 / 矩形 / 折线）把画布切到直接绘制模式——注释图形画在主画布上，
# 选中后可用右键「生成图元」提升为真正图元。
func _gpBuildToolBar() -> void:
	var gpVLayout: VBoxContainer = $VLayout
	gpToolBar = HBoxContainer.new()
	gpToolBar.name = "DrawToolBar"
	gpToolBar.add_theme_constant_override("separation", 6)
	var gpStyle: StyleBoxFlat = StyleBoxFlat.new()
	gpStyle.bg_color = Color(0.13, 0.14, 0.18)
	gpStyle.content_margin_left = 6.0
	gpStyle.content_margin_right = 6.0
	gpStyle.content_margin_top = 3.0
	gpStyle.content_margin_bottom = 3.0
	gpToolBar.add_theme_stylebox_override("panel", gpStyle)
	gpVLayout.add_child(gpToolBar)
	gpVLayout.move_child(gpToolBar, 1)
	_gpAddToolBtn("select", "symbol_lib.tool_select", true)
	_gpAddToolBtn("connect", "symbol_lib.tool_connect", true)
	_gpAddSep()
	_gpAddToolBtn("line", "canvas.tool_line", true)
	_gpAddToolBtn("circle", "canvas.tool_circle", true)
	_gpAddToolBtn("rect", "canvas.tool_rect", true)
	_gpAddToolBtn("polyline", "canvas.tool_polyline", true)
	_gpSyncToolBar()


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
	_gpSyncToolBar()


# Highlight the toggle button matching the active canvas mode (select / connect / draw tools).
# The optional gpMode parameter lets this serve as the gpModeChanged signal callback (1 arg)
# while remaining callable with 0 args elsewhere. When gpMode < 0 the live canvas mode is read.
# 高亮与当前画布模式匹配的开关按钮（选择 / 连线 / 绘图工具）。可选 gpMode 参数使其既能作为
# gpModeChanged 信号的 1 参回调，又能在别处 0 参调用；gpMode < 0 时读取画布实时模式。
func _gpSyncToolBar(gpMode: int = -1) -> void:
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
	# display name overwrites the def (built-ins derive a custom_ copy per decision D3).
	# 就地图元编辑器已移除（P4 重构）。编辑已放置图元改为用「生成图元」对话框带入该图元几何；
	# 以相同显示名确定即覆盖该 def（内置图元按决策 D3 派生 custom_ 副本）。
	var gpCanvas: GPCanvas2D = gpActiveCanvas()
	if gpCanvas == null or gpCenter == null:
		return
	var gpDef: GPSymbolDef = _gpDefFor(gpSymbolId)
	if gpDef == null:
		return
	# D3: built-in symbols are read-only → derive a custom_<id> copy so the original ISO glyph is
	# never overwritten or re-fit.
	# 决策 D3：内置图元只读 → 派生 custom_<id> 副本，绝不覆盖/重拟合原始 ISO 图元。
	var gpEditDef: GPSymbolDef = gpDef
	var gpAllowOverwrite: bool = true
	if gpDef.gpBuiltin:
		var gpCanon: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(
			GPSymbolNormalizer.gpDenormalizeSymbol(gpDef), gpDef.gpCategory, {})
		gpCanon.gpId = "custom_" + gpDef.gpId
		gpCanon.gpBuiltin = false
		GPSymbolLibrary.gpRegisterDefs([gpCanon])
		gpDefs = GPSymbolLibrary.gpDefaultDefs()
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
