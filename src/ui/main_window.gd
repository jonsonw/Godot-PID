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

# Active topology graph edited by the user.
# 用户正在编辑的活动拓扑图。
var gpGraph: GPPIDGraph


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

# Main canvas control.
# 主画布控件。
var gpCanvas: GPCanvas2D

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
const GP_LEFT_MIN: float = 220.0
# Right dock minimum width in pixels (matches RightDock.custom_minimum_size.x).
# 右停靠栏最小宽度（像素，与 RightDock.custom_minimum_size.x 一致）。
const GP_RIGHT_MIN: float = 220.0

# Current left-dock width in pixels; seeded from GP_LEFT_MIN and updated by drags.
# 当前左停靠栏宽度（像素）；以 GP_LEFT_MIN 初始化，拖拽时更新。
var gpLeftWidthPx: float = GP_LEFT_MIN
# Current right-dock width in pixels; seeded from GP_RIGHT_MIN and updated by drags.
# 当前右停靠栏宽度（像素）；以 GP_RIGHT_MIN 初始化，拖拽时更新。
var gpRightWidthPx: float = GP_RIGHT_MIN


# Wire the static scene together and set up initial state.
# 将静态场景拼接起来并设置初始状态。
func _ready() -> void:
	gpGraph = GPPIDGraph.new()
	# Restore any symbol packs the user exported in a previous session so they
	# re-appear in the palette and on the canvas after a restart.
	# 恢复用户在上一次会话中导出的图元包，使重启后它们重新出现在图元库与画布中。
	GPSymbolLibrary.gpLoadUserPacks()
	gpDefs = GPSymbolLibrary.gpDefaultDefs()

	# Fetch static nodes from the scene tree.
	# 从场景树获取静态节点。
	gpMenuBar = $VLayout/MenuBar
	gpLeftDock = $VLayout/Body/LeftDock
	gpBodySplit = $VLayout/Body
	gpBodySplit.dragged.connect(_gpOnBodyDragged)
	gpCanvas = $VLayout/Body/Center/Canvas
	gpTabs = $VLayout/Body/RightDock/InspectorTabs
	gpInspector = $VLayout/Body/RightDock/InspectorTabs/PropTab
	gpInfoLabel = $VLayout/Body/RightDock/InspectorTabs/InfoTab/InfoLabel
	gpDocLabel = $VLayout/Body/RightDock/InspectorTabs/DocTab/DocLabel
	gpSelLabel = $VLayout/StatusBar/SelLabel
	gpCoordLabel = $VLayout/StatusBar/CoordLabel
	gpZoomLabel = $VLayout/StatusBar/ZoomLabel
	gpStateLabel = $VLayout/StatusBar/StateLabel

	# ---- canvas ----
	# ---- 画布 ----
	gpCanvas.gpGraph = gpGraph
	gpCanvas.gpDefs = gpDefs
	gpCanvas.gpGraphChanged.connect(_gpOnGraphChanged)
	gpCanvas.gpStatusUpdated.connect(_gpOnStatus)

	# ---- left palette: inject symbol buttons ----
	# ---- 左侧图元库：注入图元按钮 ----
	gpLeftDock.gpPopulate(gpDefs)
	gpLeftDock.gpSymbolPicked.connect(_gpOnSymbolPicked)
	gpLeftDock.gpToolSelected.connect(_gpOnToolSelected)

	# ---- inspector ----
	# ---- 属性面板 ----
	gpInspector.gpAttrChanged.connect(_gpOnAttrChanged)

	# ---- menu ----
	# ---- 菜单 ----
	gpMenuBar.gpActionTriggered.connect(_gpOnMenu)

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

	# ---- initial dock widths: pin both docks to their floor, canvas fills rest ----
	# ---- 初始停靠栏宽度：两栏钉到下限，画布填满剩余空间 ----
	_gpInitSplits()

	# initial status
	# 初始状态
	_gpOnStatus(gpLastStatus)


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
	gpCanvas.gpPendingDef = _gpDefFor(gpTypeId)
	gpCanvas.gpMode = GPCanvas2D.GPMode.GP_SELECT
	gpCanvas.gpConnectFrom = ""
	var gpDef: GPSymbolDef = _gpDefFor(gpTypeId)
	var gpName: String = gpDef.gpDisplayName if gpDef else gpTypeId
	_gpSetState("status.symbol_picked", [gpName])


# A tool button was pressed: select / connect / custom.
# 工具按钮被按下：选择 / 连线 / 自定义。
func _gpOnToolSelected(gpType: String) -> void:
	if gpType == "select":
		gpCanvas.gpMode = GPCanvas2D.GPMode.GP_SELECT
		gpCanvas.gpConnectFrom = ""
		_gpSetState("status.mode_select")
	elif gpType == "connect":
		gpCanvas.gpMode = GPCanvas2D.GPMode.GP_CONNECT
		_gpSetState("status.mode_connect")
	elif gpType == "custom":
		_gpSetState("status.custom_pending")


# ============================ canvas changes ============================
# ============================ 画布变化 ============================
# React to graph changes by refreshing the inspector for the current selection.
# 图变化时刷新当前选中的属性面板。
func _gpOnGraphChanged() -> void:
	_gpRefreshSelection()


# Update the status bar from a canvas status snapshot.
# 根据画布状态快照更新状态栏。
func _gpOnStatus(gpInfo: Dictionary) -> void:
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
	gpCanvas.queue_redraw()
	_gpRefreshSelection()


# ============================ menu ============================
# ============================ 菜单 ============================
# Dispatch menu actions.
# 分发菜单动作。
func _gpOnMenu(gpAction: String) -> void:
	match gpAction:
		"file_new", "edit_clear":
			gpGraph.gpNodes.clear()
			gpGraph.gpEdges.clear()
			gpCanvas.gpNextId = 1
			gpCanvas.gpSelectedId = ""
			gpCanvas.gpConnectFrom = ""
			gpCanvas.gpPendingDef = null
			gpCanvas.queue_redraw()
			_gpSetState("status.cleared")
		"file_save":
			_gpSaveProject(false)
		"file_save_as":
			_gpSaveProject(true)
		"file_open":
			_gpOpenProject()
		"view_zoom_in":
			gpCanvas.gpZoomStep(1.0)
		"view_zoom_out":
			gpCanvas.gpZoomStep(-1.0)
		"view_fit":
			gpCanvas.gpResetView()
			_gpSetState("status.view_reset")
		"edit_delete":
			if gpCanvas.gpSelectedId != "":
				_gpDeleteSelected()
		"tool_settings":
			_gpOpenSettings()
		"tool_symbol_editor":
			_gpOpenSymbolEditor()
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
func _gpWriteProject(gpPath: String) -> void:
	# Force the .pid.json extension so the file is recognized on reopen.
	# 强制扩展名为 .pid.json，便于重新打开时识别。
	if not gpPath.ends_with(".pid.json"):
		gpPath += ".pid.json"
	# Embed custom user packs so the file is self-contained (data sovereignty).
	# 嵌入用户自定义图元包，使文件自包含（数据主权）。
	gpGraph.gpEmbedUserPacks(GPSymbolLibrary.gpUserPacks())
	var gpText: String = JSON.stringify(gpGraph.gpToDict(), "", true)
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.WRITE)
	if gpF == null:
		_gpSetState("status.save_fail", [gpPath])
		return
	gpF.store_string(gpText)
	gpF.close()
	gpCurrentPath = gpPath
	var gpPackCount: int = gpGraph.gpUserSymbolPacks.size()
	_gpSetState("status.saved_with_packs", [gpPath, gpPackCount])


# Read a project from disk and swap it into the active canvas.
# 从磁盘读入工程并替换为当前活动画布。
func _gpReadProject(gpPath: String) -> void:
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpF == null:
		_gpSetState("status.load_fail", [gpPath])
		return
	var gpText: String = gpF.get_as_text()
	gpF.close()
	var gpParsed: Variant = JSON.parse_string(gpText)
	if gpParsed == null or not (gpParsed is Dictionary):
		_gpSetState("status.load_fail", [gpPath])
		return
	# Rebuild the graph; gpFromDict also reconciles embedded user packs into the
	# live library so custom symbols are available again after reopening.
	# 重建图；gpFromDict 同时把内嵌用户包调和进活动图元库，使重新打开后自定义图元再次可用。
	var gpNewGraph: GPPIDGraph = GPPIDGraph.gpFromDict(gpParsed as Dictionary)
	gpGraph = gpNewGraph
	gpCanvas.gpGraph = gpGraph
	gpDefs = GPSymbolLibrary.gpDefaultDefs()
	gpLeftDock.gpPopulate(gpDefs)
	gpCanvas.gpDefs = gpDefs
	gpCanvas.gpSelectedId = ""
	gpCanvas.gpConnectFrom = ""
	gpCanvas.queue_redraw()
	gpCurrentPath = gpPath
	_gpSetState("status.loaded_with_packs", [gpPath, gpNewGraph.gpUserSymbolPacks.size()])


# Open the settings dialog.
# 打开设置对话框。
func _gpOpenSettings() -> void:
	var gpDlg: Window = (load("res://scenes/settings_dialog.tscn") as PackedScene).instantiate()
	add_child(gpDlg)
	gpDlg.popup_centered()


# Open the symbol editor wizard as a transient window.
# 打开符号编辑器向导（作为瞬态窗口）。
func _gpOpenSymbolEditor() -> void:
	var gpEditor: GPSymbolEditor = load("res://scenes/symbol_editor.tscn").instantiate()
	add_child(gpEditor)
	gpEditor.gpPackExported.connect(_gpOnPackExported)
	gpEditor.popup_centered()


# A symbol pack was exported from the editor: fold it into the live library and refresh the
# palette + canvas so the new symbol can be picked and placed at once.
# 图元编辑器导出了图元包：并入活动图元库并刷新面板与画布，使新图元可立即拾取放置。
func _gpOnPackExported(gpPack: GPSymbolPack) -> void:
	gpDefs = GPSymbolLibrary.gpDefaultDefs()
	gpLeftDock.gpPopulate(gpDefs)
	gpCanvas.gpDefs = gpDefs
	_gpSetState("symed.pack_added", [gpPack.gpName])


# Delete the currently selected node and any edges connected to it.
# 删除当前选中的节点及其关联的边。
func _gpDeleteSelected() -> void:
	var gpId: String = gpCanvas.gpSelectedId
	gpGraph.gpRemoveNodeWithEdges(gpId)
	gpCanvas.gpSelectedId = ""
	gpCanvas.gpConnectFrom = ""
	gpCanvas.queue_redraw()


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
# 将系统屏幕缩放比应用到 Godot 的 content_scale_factor 并刷新字体。
func _gpApplyDpiScale() -> void:
	# Explicitly sync Godot's content-scale factor to the OS-reported screen scale.
	# On Retina this is ~2.0; on a 1080p external monitor it is 1.0. Without this,
	# the window backing store may stay at the creation-time scale and macOS will
	# downsample it, making the whole UI (especially text) look blurry.
	# 显式把 Godot 的 content_scale_factor 同步到系统报告的屏幕缩放比。Retina 约 2.0，
	# 1080p 外接屏约 1.0；若不这样做，窗口缓冲可能停留在创建时的缩放比，macOS 会
	# 降采样，导致整窗（尤其文字）发虚。
	var gpWin: Window = get_window()
	if gpWin == null:
		return
	var gpScreen: int = gpWin.current_screen
	var gpScale: float = DisplayServer.screen_get_scale(gpScreen)
	if gpScale > 0.0 and not is_equal_approx(gpScale, gpWin.content_scale_factor):
		gpWin.content_scale_factor = gpScale
	# Re-apply the UI theme so controls relayout at the new monitor's density.
	# 重新应用界面主题，使控件按新显示器密度重排。
	Settings.gpApplyFontSize()


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
# (a few frames after _ready), then seed the stored widths from the docks' floors
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
	for gpN in gpGraph.gpNodes:
		if gpN.gpInstanceId == gpId:
			return gpN
	return null
