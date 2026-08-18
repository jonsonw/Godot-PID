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

var gpGraph: GPPIDGraph
var gpDefs: Array[GPSymbolDef] = []

# ---- static node references (frozen in the scene) ----
# ---- 静态节点引用（固化于场景） ----
var gpMenuBar: GPPIDMenuBar
var gpLeftDock: GPPIDToolbar
var gpCanvas: GPCanvas2D
var gpTabs: TabContainer
var gpInspector: GPInspector
var gpInfoLabel: Label
var gpDocLabel: Label
var gpSelLabel: Label
var gpCoordLabel: Label
var gpZoomLabel: Label
var gpStateLabel: Label

var gpLastSel: String = ""
var gpLastStatus: Dictionary = {"selection": "", "zoom": 1.0, "world": Vector2.ZERO}
var gpStateKey: String = "status.ready"
var gpStateArgs: Array = []

# Last known screen index, used to detect a cross-monitor drag so we can refresh
# the UI at the new monitor's density.
# 上一次所在的屏幕索引，用于检测跨显示器拖拽，从而按新显示器密度刷新 UI。
var gpLastScreen: int = -1

# Split containers that let the user drag the left/right dock widths.
# 供用户拖动左/右停靠栏宽度的分隔容器。
var gpBodySplit: HSplitContainer
var gpCenterRightSplit: HSplitContainer

# Previous window content width, used to scale dock sizes proportionally on resize.
# 上一次窗口内容宽度，用于缩放时按比例调整停靠栏大小。
var gpPrevWidth: int = 0

# Dock width ratios of the *total* window width. Left = 1/5, right = 1/5, center
# canvas = 3/5. These are the single source of truth; split offsets are always
# derived from them so resizing is idempotent and a pure height change leaves the
# widths untouched. Manual drags update these ratios so the user's layout sticks.
# 停靠栏占*总*窗口宽度的比例。左 1/5、右 1/5、中间 3/5。它们是一致性来源，
# 分隔偏移始终由其推导，使缩放幂等、纯高度变化不改变宽度。手动拖拽会更新这些
# 比例以保留用户布局。
var gpLeftRatio: float = 0.2
var gpRightRatio: float = 0.2


func _ready() -> void:
	gpGraph = GPPIDGraph.new()
	gpDefs = GPSymbolLibrary.gpDefaultDefs()

	gpMenuBar = $VLayout/MenuBar
	gpLeftDock = $VLayout/Body/LeftDock
	gpBodySplit = $VLayout/Body
	gpCenterRightSplit = $VLayout/Body/CenterRightSplit
	gpBodySplit.dragged.connect(_gpOnBodyDragged)
	gpCenterRightSplit.dragged.connect(_gpOnCenterRightDragged)
	gpCanvas = $VLayout/Body/CenterRightSplit/Center/Canvas
	gpTabs = $VLayout/Body/CenterRightSplit/RightDock/InspectorTabs
	gpInspector = $VLayout/Body/CenterRightSplit/RightDock/InspectorTabs/PropTab
	gpInfoLabel = $VLayout/Body/CenterRightSplit/RightDock/InspectorTabs/InfoTab/InfoLabel
	gpDocLabel = $VLayout/Body/CenterRightSplit/RightDock/InspectorTabs/DocTab/DocLabel
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

	# ---- initial dock proportions: left 1/5, right 1/5, center 3/5 ----
	# ---- 初始停靠栏比例：左 1/5、右 1/5、中间画布 3/5 ----
	_gpInitSplits()

	# initial status
	# 初始状态
	_gpOnStatus(gpLastStatus)


# ============================ localization refresh ============================
# ============================ 本地化刷新 ============================
func _gpOnLocaleChanged(gpLocale: String) -> void:
	_gpRefreshStaticText()
	_gpOnStatus(gpLastStatus)
	_gpRefreshSelection()


func _gpRefreshStaticText() -> void:
	gpTabs.set_tab_title(0, I18n.gpTr("prop.title"))
	gpTabs.set_tab_title(1, I18n.gpTr("prop.info"))
	gpTabs.set_tab_title(2, I18n.gpTr("prop.doc"))
	gpDocLabel.text = I18n.gpTr("doc.info")
	_gpSetState(gpStateKey, gpStateArgs)


# ============================ left palette ============================
# ============================ 左侧图元库 ============================
func _gpOnSymbolPicked(gpTypeId: String) -> void:
	gpCanvas.gpPendingDef = _gpDefFor(gpTypeId)
	gpCanvas.gpMode = GPCanvas2D.GPMode.GP_SELECT
	gpCanvas.gpConnectFrom = ""
	var gpDef: GPSymbolDef = _gpDefFor(gpTypeId)
	var gpName: String = gpDef.gpDisplayName if gpDef else gpTypeId
	_gpSetState("status.symbol_picked", [gpName])


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
func _gpOnGraphChanged() -> void:
	_gpRefreshSelection()


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
func _gpRefreshSelection() -> void:
	var gpId: String = gpCanvas.gpSelectedId
	if gpId == "":
		gpInspector.gpShow(null, {})
		gpInfoLabel.text = I18n.gpTr("symbol_lib.no_selection")
		return

	var gpNode: Dictionary = _gpNodeFor(gpId)
	if gpNode.is_empty():
		gpInspector.gpShow(null, {})
		gpInfoLabel.text = I18n.gpTr("symbol_lib.no_selection")
		return

	var gpDef: GPSymbolDef = _gpDefFor(gpNode["type"])
	gpInspector.gpShow(gpDef, gpNode)

	var gpCat: String = I18n.gpTr(gpDef.gpCategory) if gpDef else "—"
	var gpSize: String = str(gpDef.gpDefaultSize) if gpDef else "—"
	gpInfoLabel.text = "%s：%s\n%s：%s\n%s：%s\n%s：%s" % [
		I18n.gpTr("info.id"), gpId,
		I18n.gpTr("info.type"), gpNode["type"],
		I18n.gpTr("info.category"), gpCat,
		I18n.gpTr("info.size"), gpSize]


func _gpOnAttrChanged(gpId: String, gpKey: String, gpVal) -> void:
	var gpNode: Dictionary = _gpNodeFor(gpId)
	if gpNode.is_empty():
		return
	if gpKey == "label":
		gpNode["label"] = gpVal
	else:
		if not gpNode.has("attrs"):
			gpNode["attrs"] = {}
		gpNode["attrs"][gpKey] = gpVal
	gpCanvas.queue_redraw()
	_gpRefreshSelection()


# ============================ menu ============================
# ============================ 菜单 ============================
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
		_:
			_gpSetState("status.feature_todo", [gpAction])


func _gpOpenSettings() -> void:
	var gpDlg = load("res://scenes/settings_dialog.tscn").instantiate()
	add_child(gpDlg)
	gpDlg.popup_centered()


func _gpDeleteSelected() -> void:
	var gpId: String = gpCanvas.gpSelectedId
	gpGraph.gpNodes = gpGraph.gpNodes.filter(func(gpN): return gpN["id"] != gpId)
	gpGraph.gpEdges = gpGraph.gpEdges.filter(func(gpE): return gpE["from"] != gpId and gpE["to"] != gpId)
	gpCanvas.gpSelectedId = ""
	gpCanvas.gpConnectFrom = ""
	gpCanvas.queue_redraw()


# ============================ state helper ============================
# ============================ 状态栏辅助 ============================
func _gpSetState(gpKey: String, gpArgs: Array = []) -> void:
	gpStateKey = gpKey
	gpStateArgs = gpArgs
	var gpFmt: String = I18n.gpTr(gpKey)
	gpStateLabel.text = gpFmt % gpArgs if gpArgs.size() > 0 else gpFmt


# ============================ HiDPI / multi-monitor ============================
# ============================ HiDPI / 多显示器 ============================
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


func _gpOnWindowChanged() -> void:
	var gpWin: Window = get_window()
	if gpWin == null:
		return
	var gpScreen: int = gpWin.current_screen
	if gpScreen == gpLastScreen:
		return
	gpLastScreen = gpScreen
	_gpApplyDpiScale()


# Responsive layout: when the window is resized, the dock widths are re-derived
# from gpLeftRatio / gpRightRatio (proportional to the *current* container
# width). This depends only on width, so a pure height change leaves the docks
# untouched. Only active when Settings.gpAutoScale is on; when off, manually
# dragged widths are kept. The UI font is never scaled (see settings.gd).
# 响应式布局：窗口缩放时，停靠栏宽度按 gpLeftRatio / gpRightRatio（相对*当前*
# 容器宽度）重新推导。它只依赖宽度，因此纯高度变化不改变停靠栏。仅在
# Settings.gpAutoScale 开启时生效；关闭时保留用户拖拽后的宽度。界面字号不随
# 窗口缩放（见 settings.gd）。
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
	if Settings.gpAutoScale:
		_gpApplySplits()
	gpPrevWidth = gpW


# Derive both split offsets from the stored ratios and the containers' real
# (already laid-out) widths. Idempotent: same widths -> same offsets, so calling
# it on every resize never drifts. Uses each container's own width rather than the
# window width to stay correct regardless of margins / chrome.
# 按存储比例与容器已布局的真实宽度推导两个分隔偏移。幂等：相同宽度得到相同
# 偏移，故每次缩放调用都不会漂移。使用各自容器宽度而非窗口宽度，避免边距/边框
# 导致偏差。
func _gpApplySplits() -> void:
	if gpBodySplit == null or gpCenterRightSplit == null:
		return
	var gpBW: float = gpBodySplit.size.x
	if gpBW <= 1.0:
		return
	# Left dock = gpLeftRatio of the body width.
	# 左栏 = 主体宽度的 gpLeftRatio。
	gpBodySplit.split_offset = int(round(gpLeftRatio * gpBW))
	# Center-right region width = (1 - gpLeftRatio) * gpBW. Within it the right
	# dock should be gpRightRatio of the total, so the inner split (center edge)
	# sits at (1 - gpLeftRatio - gpRightRatio) * gpBW from the body's left edge.
	# 中间-右侧区域宽度 = (1 - gpLeftRatio) * gpBW；其中右栏应为总宽的
	# gpRightRatio，故内部分隔（中间区右缘）位于距主体左缘
	# (1 - gpLeftRatio - gpRightRatio) * gpBW 处。
	gpCenterRightSplit.split_offset = int(round((1.0 - gpLeftRatio - gpRightRatio) * gpBW))


# Initial dock widths: left = 1/5, right = 1/5, center = 3/5 of the total. We wait
# until the split containers have a real laid-out width (a few frames after
# _ready), then derive the offsets from the containers themselves so the result is
# correct no matter what transient size the window had at startup.
# 初始停靠栏宽度：左 1/5、右 1/5、中间 3/5。等待容器获得已布局的真实宽度
#（_ready 后若干帧）后，用容器自身尺寸推导偏移，从而无论启动时窗口瞬时大小
# 如何都正确。
func _gpInitSplits() -> void:
	for _gpI in range(10):
		await get_tree().process_frame
		if gpBodySplit != null and gpBodySplit.size.x > 50.0:
			break
	_gpApplySplits()
	var gpWin: Window = get_window()
	gpPrevWidth = int(gpWin.size.x) if gpWin != null else 0


# Manual drag of the outer (left) split: capture the new ratio so a later window
# resize keeps the user's layout. The dragged offset is relative to the body
# width.
# 外侧（左）分隔被手动拖拽：记录新比例，使后续窗口缩放保留用户布局。拖拽偏移
# 相对主体宽度。
func _gpOnBodyDragged(gpOffset: int) -> void:
	var gpBW: float = gpBodySplit.size.x
	if gpBW > 1.0:
		gpLeftRatio = clampf(float(gpOffset) / gpBW, 0.05, 0.8)


# Manual drag of the inner (right) split: convert the inner split offset into the
# right-dock ratio of the total width and store it.
# 内侧（右）分隔被手动拖拽：把内部分隔偏移换算成右栏占总宽的比例并存储。
func _gpOnCenterRightDragged(gpOffset: int) -> void:
	var gpCRW: float = gpCenterRightSplit.size.x
	if gpCRW > 1.0:
		var gpCenterFracInCR: float = float(gpOffset) / gpCRW
		gpRightRatio = clampf((1.0 - gpCenterFracInCR) * (1.0 - gpLeftRatio), 0.05, 0.8)


# ============================ lookups ============================
# ============================ 查找 ============================
func _gpDefFor(gpTypeId: String) -> GPSymbolDef:
	for gpD in gpDefs:
		if gpD.gpId == gpTypeId:
			return gpD
	return null


func _gpNodeFor(gpId: String) -> Dictionary:
	for gpN in gpGraph.gpNodes:
		if gpN["id"] == gpId:
			return gpN
	return {}
