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


func _ready() -> void:
	gpGraph = GPPIDGraph.new()
	gpDefs = GPSymbolLibrary.gpDefaultDefs()

	gpMenuBar = $VLayout/MenuBar
	gpLeftDock = $VLayout/Body/LeftDock
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

	I18n.gpLocaleChanged.connect(_gpOnLocaleChanged)
	_gpRefreshStaticText()

	# ---- HiDPI / multi-monitor crispness ----
	# ---- 多显示器清晰渲染（HiDPI） ----
	var gpWin: Window = get_window()
	if gpWin != null:
		gpWin.size_changed.connect(_gpOnWindowChanged)
		gpWin.focus_entered.connect(_gpOnWindowChanged)
		gpLastScreen = gpWin.current_screen
		_gpApplyDpiScale()

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
