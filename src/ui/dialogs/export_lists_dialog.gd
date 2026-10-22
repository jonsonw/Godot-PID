class_name GPExportListsDialog
extends Window
# Copyright © 2026 Jonson Wang
#
# Classified list export dialog: choose drawings, choose the four lists, choose a template
# per list, choose the output folder, then run GPXlsxExport. Result rows stay in the dialog.
# 分类清单导出对话框：选图纸、选四类清单、每类选模板、选输出目录，然后跑 GPXlsxExport；
# 结果行留在对话框里。
#
# WHY CODE-BUILT / 为何代码构建：
# the rows are data-driven (four lists, N sheets), and the dialog must stay usable when the
# default template assets change. A hand-authored .tscn would silently drift; the same reason
# title_block_dialog.gd is code-built.
# 行是数据驱动的（四类清单、N 张图纸），且默认模板资产变化时对话框必须仍可用。手写 .tscn
# 会静默失同步；同 title_block_dialog.gd 的理由。
#
# LAYERING / 分层：
# UI reads GPDeliverablePrefs / GPXlsxTemplate / GPXlsxExport (all io), never FileAccess for
# project data. The dialog does open FileDialog windows — that is UI, not file I/O.
# UI 只读 GPDeliverablePrefs / GPXlsxTemplate / GPXlsxExport（均在 io），不直接读写工程数据。
# 对话框会打开 FileDialog 窗口 —— 那是 UI，不是文件 I/O。
#
# Coding rule: every variable declares its type explicitly. / 编码规范：变量显式类型。

const GP_WINDOW_FIT := preload("res://src/ui/dialogs/window_fit.gd")
const GP_MIN_LOGICAL: Vector2i = Vector2i(820, 620)
const GP_MAX_LOGICAL: Vector2i = Vector2i(1120, 840)

var gpSheets: Array = []
var gpDefs: Array[GPSymbolDef] = []
var gpLocale: String = "zh"

# Sheet index -> CheckBox. / 图纸下标 -> 复选框。
var gpSheetChecks: Dictionary = {}
# List id -> CheckBox. / 清单 -> 复选框。
var gpListChecks: Dictionary = {}
# List id -> custom template path ("" = default). / 清单 -> 自定义模板路径（空=默认）。
var gpTemplatePaths: Dictionary = {}
# List id -> status Label. / 清单 -> 状态标签。
var gpTemplateLabels: Dictionary = {}
# List id -> count Label. / 清单 -> 计数标签。
var gpListCounts: Dictionary = {}
var gpCounts: Dictionary = {}

var gpOutputEdit: LineEdit = null
var gpPrefixEdit: LineEdit = null
var gpIncludeEmpty: CheckBox = null
var gpSummaryLabel: Label = null
var gpStatusLabel: Label = null
var gpResultTree: Tree = null
var gpExportButton: Button = null
var gpCloseButton: Button = null

var gpTemplateDialog: FileDialog = null
var gpDirDialog: FileDialog = null
var gpPendingList: String = ""

var _gpBuilt: bool = false
var _gpExporting: bool = false


# Bind data before adding to the tree; _ready() builds against it.
# 进树前绑定数据；_ready() 依据它构建。
func gpConfigure(gpSheetsIn: Array, gpDefsIn: Array[GPSymbolDef],
		gpLocaleIn: String = "") -> void:
	gpSheets = gpSheetsIn
	gpDefs = gpDefsIn
	gpLocale = gpLocaleIn if gpLocaleIn != "" else I18n.gpLocale


func gpPopupOverHost() -> void:
	var gpParent: Node = get_parent()
	var gpHost: Window = gpParent.get_window() if gpParent != null else null
	GP_WINDOW_FIT.gpPopupFitted(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL)


func _ready() -> void:
	title = I18n.gpTr("xlsx.dialog_title")
	close_requested.connect(queue_free)
	var gpParent: Node = get_parent()
	var gpHost: Window = gpParent.get_window() if gpParent != null else null
	GP_WINDOW_FIT.gpApply(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL, false)
	_gpBuild()
	_gpLoadPrefs()
	_gpRefreshTemplateStatus()
	_gpRefreshCounts()
	_gpBuilt = true


# ==================== build / 构建 ====================

func _gpBuild() -> void:
	# The main app is dark; a code-built Window inherits the default (light) theme and would
	# render black text on the dark panel. Paint an explicit dark background and set a compact
	# theme so labels/buttons/inputs/tree stay legible in both zh and en.
	# 主程序是深色；代码构建的 Window 继承默认（浅色）主题，会在深色面板上渲染黑字。显式铺深色
	# 背景并设置一套紧凑主题，使中英文标签/按钮/输入框/结果树都清晰。
	var gpBg: Panel = Panel.new()
	gpBg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpBg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gpBgStyle: StyleBoxFlat = StyleBoxFlat.new()
	gpBgStyle.bg_color = Color(0.105, 0.125, 0.155)
	gpBgStyle.border_color = Color(0.22, 0.26, 0.32)
	gpBgStyle.set_border_width_all(1)
	gpBgStyle.set_corner_radius_all(4)
	gpBg.add_theme_stylebox_override("panel", gpBgStyle)
	add_child(gpBg)
	var gpMargin: MarginContainer = MarginContainer.new()
	gpMargin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpMargin.add_theme_constant_override("margin_left", 14)
	gpMargin.add_theme_constant_override("margin_right", 14)
	gpMargin.add_theme_constant_override("margin_top", 12)
	gpMargin.add_theme_constant_override("margin_bottom", 12)
	gpMargin.theme = _gpTheme()
	add_child(gpMargin)
	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.add_theme_constant_override("separation", 8)
	gpMargin.add_child(gpRoot)

	var gpTitle: Label = Label.new()
	gpTitle.text = I18n.gpTr("xlsx.dialog_title")
	gpTitle.add_theme_font_size_override("font_size", 18)
	gpRoot.add_child(gpTitle)
	var gpSub: Label = Label.new()
	gpSub.text = I18n.gpTr("xlsx.dialog_subtitle")
	gpSub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpSub.modulate = Color(1, 1, 1, 0.75)
	gpRoot.add_child(gpSub)

	var gpBody: HBoxContainer = HBoxContainer.new()
	gpBody.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpBody.add_theme_constant_override("separation", 10)
	gpRoot.add_child(gpBody)

	# Left: drawings. / 左：图纸。
	var gpLeft: PanelContainer = PanelContainer.new()
	gpLeft.custom_minimum_size = Vector2(250, 0)
	gpLeft.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpBody.add_child(gpLeft)
	var gpLeftBox: VBoxContainer = VBoxContainer.new()
	gpLeftBox.add_theme_constant_override("separation", 6)
	gpLeft.add_child(gpLeftBox)
	var gpLeftHead: HBoxContainer = HBoxContainer.new()
	gpLeftBox.add_child(gpLeftHead)
	var gpLeftTitle: Label = Label.new()
	gpLeftTitle.text = I18n.gpTr("xlsx.section_drawings")
	gpLeftTitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpLeftHead.add_child(gpLeftTitle)
	var gpAllBtn: Button = Button.new()
	gpAllBtn.text = I18n.gpTr("xlsx.select_all")
	_gpLightButton(gpAllBtn)
	gpAllBtn.pressed.connect(_gpSetAllSheets.bind(true))
	gpLeftHead.add_child(gpAllBtn)
	var gpNoneBtn: Button = Button.new()
	gpNoneBtn.text = I18n.gpTr("xlsx.select_none")
	_gpLightButton(gpNoneBtn)
	gpNoneBtn.pressed.connect(_gpSetAllSheets.bind(false))
	gpLeftHead.add_child(gpNoneBtn)
	var gpScroll: ScrollContainer = ScrollContainer.new()
	gpScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpLeftBox.add_child(gpScroll)
	var gpSheetBox: VBoxContainer = VBoxContainer.new()
	gpSheetBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpScroll.add_child(gpSheetBox)
	for gpI in range(gpSheets.size()):
		var gpSheet: GPSheet = gpSheets[gpI] as GPSheet
		if gpSheet == null:
			continue
		var gpCheck: CheckBox = CheckBox.new()
		var gpName: String = gpSheet.gpName.strip_edges()
		if gpName == "":
			gpName = "图纸 %d" % (gpI + 1)
		gpCheck.text = "%02d  %s" % [gpI + 1, gpName]
		gpCheck.button_pressed = true
		gpCheck.toggled.connect(_gpOnAnyToggle)
		gpSheetBox.add_child(gpCheck)
		gpSheetChecks[gpI] = gpCheck

	# Right: lists / templates / output / result. / 右：清单/模板/输出/结果。
	var gpRight: VBoxContainer = VBoxContainer.new()
	gpRight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpRight.add_theme_constant_override("separation", 6)
	gpBody.add_child(gpRight)

	var gpListsTitle: Label = Label.new()
	gpListsTitle.text = I18n.gpTr("xlsx.section_lists")
	gpRight.add_child(gpListsTitle)
	for gpList in GPDeliverableFields.gpListIds():
		gpRight.add_child(_gpBuildListRow(gpList))

	var gpOutputRow: HBoxContainer = HBoxContainer.new()
	gpOutputRow.add_theme_constant_override("separation", 6)
	gpRight.add_child(gpOutputRow)
	var gpOutLabel: Label = Label.new()
	gpOutLabel.text = I18n.gpTr("xlsx.output_dir")
	gpOutLabel.custom_minimum_size = Vector2(92, 0)
	gpOutputRow.add_child(gpOutLabel)
	gpOutputEdit = LineEdit.new()
	gpOutputEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpOutputRow.add_child(gpOutputEdit)
	var gpOutBtn: Button = Button.new()
	gpOutBtn.text = I18n.gpTr("xlsx.browse")
	gpOutBtn.pressed.connect(_gpBrowseOutput)
	gpOutputRow.add_child(gpOutBtn)

	var gpPrefixRow: HBoxContainer = HBoxContainer.new()
	gpPrefixRow.add_theme_constant_override("separation", 6)
	gpRight.add_child(gpPrefixRow)
	var gpPrefixLabel: Label = Label.new()
	gpPrefixLabel.text = I18n.gpTr("xlsx.prefix")
	gpPrefixLabel.custom_minimum_size = Vector2(92, 0)
	gpPrefixRow.add_child(gpPrefixLabel)
	gpPrefixEdit = LineEdit.new()
	gpPrefixEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpPrefixEdit.placeholder_text = I18n.gpTr("xlsx.prefix_hint")
	gpPrefixRow.add_child(gpPrefixEdit)
	gpIncludeEmpty = CheckBox.new()
	gpIncludeEmpty.text = I18n.gpTr("xlsx.include_empty")
	gpIncludeEmpty.button_pressed = false
	gpIncludeEmpty.add_theme_color_override("font_color", Color(0.92, 0.94, 0.97))
	gpIncludeEmpty.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	gpPrefixRow.add_child(gpIncludeEmpty)

	gpSummaryLabel = Label.new()
	gpSummaryLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpSummaryLabel.modulate = Color(1, 1, 1, 0.78)
	gpRight.add_child(gpSummaryLabel)

	var gpResultTitle: Label = Label.new()
	gpResultTitle.text = I18n.gpTr("xlsx.result_title")
	gpRight.add_child(gpResultTitle)
	gpResultTree = Tree.new()
	gpResultTree.hide_root = true
	gpResultTree.column_titles_visible = true
	gpResultTree.columns = 4
	gpResultTree.set_column_title(0, I18n.gpTr("xlsx.col_list"))
	gpResultTree.set_column_title(1, I18n.gpTr("xlsx.col_file"))
	gpResultTree.set_column_title(2, I18n.gpTr("xlsx.col_rows"))
	gpResultTree.set_column_title(3, I18n.gpTr("xlsx.col_status"))
	gpResultTree.set_column_expand(0, false)
	gpResultTree.set_column_expand(1, true)
	gpResultTree.set_column_expand(2, false)
	gpResultTree.set_column_expand(3, false)
	gpResultTree.set_column_custom_minimum_width(0, 150)
	gpResultTree.set_column_custom_minimum_width(2, 70)
	gpResultTree.set_column_custom_minimum_width(3, 90)
	gpResultTree.custom_minimum_size = Vector2(0, 150)
	gpResultTree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpRight.add_child(gpResultTree)

	var gpBottom: HBoxContainer = HBoxContainer.new()
	gpBottom.add_theme_constant_override("separation", 8)
	gpRoot.add_child(gpBottom)
	gpStatusLabel = Label.new()
	gpStatusLabel.text = I18n.gpTr("xlsx.status_ready")
	gpStatusLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpStatusLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpBottom.add_child(gpStatusLabel)
	gpCloseButton = Button.new()
	gpCloseButton.text = I18n.gpTr("xlsx.close")
	gpCloseButton.pressed.connect(queue_free)
	gpBottom.add_child(gpCloseButton)
	gpExportButton = Button.new()
	gpExportButton.text = I18n.gpTr("xlsx.export")
	gpExportButton.pressed.connect(_gpOnExport)
	gpBottom.add_child(gpExportButton)

	# File dialogs are children of this window and non-native so layout/automation is stable.
	# 文件对话框是本窗口子节点且非原生，布局/自动化稳定。
	gpTemplateDialog = FileDialog.new()
	gpTemplateDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	gpTemplateDialog.access = FileDialog.ACCESS_FILESYSTEM
	gpTemplateDialog.use_native_dialog = false
	gpTemplateDialog.filters = PackedStringArray(["*.xlsx ; Excel Workbook"])
	gpTemplateDialog.file_selected.connect(_gpOnTemplateSelected)
	add_child(gpTemplateDialog)
	gpDirDialog = FileDialog.new()
	gpDirDialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	gpDirDialog.access = FileDialog.ACCESS_FILESYSTEM
	gpDirDialog.use_native_dialog = false
	gpDirDialog.dir_selected.connect(_gpOnDirSelected)
	add_child(gpDirDialog)


func _gpLightButton(gpButton: Button) -> void:
	gpButton.add_theme_color_override("font_color", Color(0.92, 0.94, 0.97))
	gpButton.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	gpButton.add_theme_color_override("font_pressed_color", Color(0.8, 0.9, 1.0))


func _gpTheme() -> Theme:
	var gpTheme: Theme = Theme.new()
	var gpText: Color = Color(0.92, 0.94, 0.97)
	var gpMuted: Color = Color(0.75, 0.79, 0.85)
	gpTheme.set_color("font_color", "Label", gpText)
	gpTheme.set_color("font_color", "CheckBox", gpText)
	gpTheme.set_color("font_color", "Button", gpText)
	gpTheme.set_color("font_hover_color", "Button", Color(1.0, 1.0, 1.0))
	gpTheme.set_color("font_pressed_color", "Button", Color(0.8, 0.9, 1.0))
	gpTheme.set_color("font_color", "LineEdit", gpText)
	gpTheme.set_color("font_color", "Tree", gpText)
	gpTheme.set_color("font_selected_color", "Tree", Color(1.0, 1.0, 1.0))
	gpTheme.set_color("title_button_color", "Tree", gpMuted)
	gpTheme.set_color("font_color", "FileDialog", gpText)
	return gpTheme


func _gpBuildListRow(gpList: String) -> HBoxContainer:
	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 6)
	var gpCheck: CheckBox = CheckBox.new()
	gpCheck.text = I18n.gpTr("xlsx.list." + gpList)
	gpCheck.custom_minimum_size = Vector2(150, 0)
	gpCheck.button_pressed = true
	gpCheck.toggled.connect(_gpOnAnyToggle)
	gpRow.add_child(gpCheck)
	gpListChecks[gpList] = gpCheck
	var gpCount: Label = Label.new()
	gpCount.custom_minimum_size = Vector2(62, 0)
	gpRow.add_child(gpCount)
	gpListCounts[gpList] = gpCount
	var gpStatus: Label = Label.new()
	gpStatus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpStatus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpStatus.modulate = Color(1, 1, 1, 0.78)
	gpRow.add_child(gpStatus)
	gpTemplateLabels[gpList] = gpStatus
	var gpBrowse: Button = Button.new()
	gpBrowse.text = I18n.gpTr("xlsx.template_browse")
	gpBrowse.pressed.connect(_gpBrowseTemplate.bind(gpList))
	gpRow.add_child(gpBrowse)
	var gpClear: Button = Button.new()
	gpClear.text = I18n.gpTr("xlsx.template_clear")
	gpClear.pressed.connect(_gpClearTemplate.bind(gpList))
	gpRow.add_child(gpClear)
	return gpRow


# ==================== prefs / counts / status ====================

func _gpLoadPrefs() -> void:
	var gpPrefs: Dictionary = GPDeliverablePrefs.gpLoad()
	gpOutputEdit.text = str(gpPrefs.get("output_dir", GPDeliverablePrefs.gpDefaultOutputDir()))
	gpPrefixEdit.text = str(gpPrefs.get("name_prefix", "G-PID"))
	var gpTpl: Dictionary = gpPrefs.get("templates", {}) as Dictionary
	for gpList in GPDeliverableFields.gpListIds():
		gpTemplatePaths[gpList] = str(gpTpl.get(gpList, ""))


func _gpSavePrefs() -> void:
	var gpTpl: Dictionary = {}
	for gpList in GPDeliverableFields.gpListIds():
		var gpPath: String = str(gpTemplatePaths.get(gpList, ""))
		if gpPath != "":
			gpTpl[gpList] = gpPath
	GPDeliverablePrefs.gpSave(gpOutputEdit.text.strip_edges(),
		gpPrefixEdit.text.strip_edges(), gpTpl)


func _gpSelectedSheets() -> Array:
	var gpOut: Array = []
	for gpI in range(gpSheets.size()):
		var gpCheck: CheckBox = gpSheetChecks.get(gpI, null) as CheckBox
		if gpCheck != null and gpCheck.button_pressed:
			gpOut.append(gpSheets[gpI])
	return gpOut


func _gpSelectedLists() -> Array[String]:
	var gpOut: Array[String] = []
	for gpList in GPDeliverableFields.gpListIds():
		var gpCheck: CheckBox = gpListChecks.get(gpList, null) as CheckBox
		if gpCheck != null and gpCheck.button_pressed:
			gpOut.append(gpList)
	return gpOut


func _gpOnAnyToggle(gpPressed: bool = false) -> void:
	_gpRefreshCounts()


func _gpSetAllSheets(gpOn: bool) -> void:
	for gpKey in gpSheetChecks.keys():
		var gpCheck: CheckBox = gpSheetChecks[gpKey] as CheckBox
		if gpCheck != null:
			gpCheck.set_pressed_no_signal(gpOn)
	_gpRefreshCounts()


func _gpTypeLabels() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpDef in gpDefs:
		if gpDef == null:
			continue
		var gpLabel: String = I18n.gpTr(gpDef.gpDisplayName)
		if gpLabel.strip_edges() == "":
			gpLabel = gpDef.gpId
		gpOut[gpDef.gpId] = gpLabel
	return gpOut


func _gpRefreshCounts() -> void:
	if not _gpBuilt and gpSummaryLabel == null:
		return
	var gpSelected: Array = _gpSelectedSheets()
	var gpCountsNow: Dictionary = {}
	if gpSelected.is_empty():
		for gpList in GPDeliverableFields.gpListIds():
			gpCountsNow[gpList] = 0
	else:
		var gpModel: Dictionary = GPDeliverableModel.gpBuildAll(gpSelected, gpDefs,
			{"locale": gpLocale, "type_labels": _gpTypeLabels()})
		for gpList in GPDeliverableFields.gpListIds():
			gpCountsNow[gpList] = int((gpModel.get(gpList, {}) as Dictionary).get("count", 0))
	gpCounts = gpCountsNow
	for gpList in GPDeliverableFields.gpListIds():
		var gpLabel: Label = gpListCounts.get(gpList, null) as Label
		if gpLabel != null:
			gpLabel.text = I18n.gpTr("xlsx.rows") % int(gpCountsNow.get(gpList, 0))
	var gpText: String = I18n.gpTr("xlsx.summary") % [
		gpSelected.size(), gpSheets.size(),
		int(gpCountsNow.get("line", 0)), int(gpCountsNow.get("equipment", 0)),
		int(gpCountsNow.get("instrument", 0)), int(gpCountsNow.get("valve", 0))]
	gpSummaryLabel.text = gpText
	if gpExportButton != null:
		gpExportButton.disabled = gpSelected.is_empty() or _gpSelectedLists().is_empty()


func _gpRefreshTemplateStatus() -> void:
	for gpList in GPDeliverableFields.gpListIds():
		var gpLabel: Label = gpTemplateLabels.get(gpList, null) as Label
		if gpLabel == null:
			continue
		var gpCustom: String = str(gpTemplatePaths.get(gpList, ""))
		var gpPath: String = gpCustom if gpCustom != "" else GPXlsxExport.gpDefaultTemplatePath(gpList)
		gpLabel.tooltip_text = gpPath
		var gpProbe: Dictionary = GPXlsxTemplate.gpProbe(gpPath, gpList, gpDefs,
			{"locale": gpLocale})
		if bool(gpProbe.get("ok", false)):
			gpLabel.text = (I18n.gpTr("xlsx.template_bound") % str(gpProbe.get("sheet_name", "")))
			gpLabel.modulate = Color(0.55, 0.85, 0.6)
		else:
			var gpWhy: String = str(gpProbe.get("error", "?"))
			if gpWhy == "no_key":
				gpLabel.text = I18n.gpTr("xlsx.err_no_key") % str(gpProbe.get("key", "tag"))
			elif gpWhy == "sample_row":
				gpLabel.text = I18n.gpTr("xlsx.err_sample_row") % [
					int(gpProbe.get("header_row", 0)), int(gpProbe.get("sample_row", 0))]
			else:
				gpLabel.text = I18n.gpTr("xlsx.template_unbound") % gpWhy
			gpLabel.modulate = Color(0.95, 0.55, 0.55)


# ==================== browse / export ====================

func _gpBrowseTemplate(gpList: String) -> void:
	gpPendingList = gpList
	var gpCur: String = str(gpTemplatePaths.get(gpList, ""))
	if gpCur == "":
		gpCur = GPXlsxExport.gpDefaultTemplatePath(gpList)
	gpTemplateDialog.current_file = gpCur
	gpTemplateDialog.popup_centered_ratio(0.7)


func _gpOnTemplateSelected(gpPath: String) -> void:
	if gpPendingList == "":
		return
	gpTemplatePaths[gpPendingList] = gpPath
	_gpRefreshTemplateStatus()


func _gpClearTemplate(gpList: String) -> void:
	gpTemplatePaths[gpList] = ""
	_gpRefreshTemplateStatus()


func _gpBrowseOutput() -> void:
	gpDirDialog.current_dir = gpOutputEdit.text.strip_edges()
	gpDirDialog.popup_centered_ratio(0.7)


func _gpOnDirSelected(gpDir: String) -> void:
	gpOutputEdit.text = gpDir


func _gpOnExport() -> void:
	if _gpExporting:
		return
	var gpSelected: Array = _gpSelectedSheets()
	if gpSelected.is_empty():
		gpStatusLabel.text = I18n.gpTr("xlsx.no_sheets")
		return
	var gpLists: Array[String] = _gpSelectedLists()
	if gpLists.is_empty():
		gpStatusLabel.text = I18n.gpTr("xlsx.no_lists")
		return
	var gpOutDir: String = gpOutputEdit.text.strip_edges()
	if gpOutDir == "":
		gpStatusLabel.text = I18n.gpTr("xlsx.err_output_dir")
		return
	_gpSavePrefs()
	var gpTpl: Dictionary = {}
	for gpList in GPDeliverableFields.gpListIds():
		var gpPath: String = str(gpTemplatePaths.get(gpList, ""))
		if gpPath != "":
			gpTpl[gpList] = gpPath
	var gpOptions: Dictionary = {
		"lists": gpLists,
		"templates": gpTpl,
		"output_dir": gpOutDir,
		"name_prefix": gpPrefixEdit.text.strip_edges(),
		"locale": gpLocale,
		"include_empty": gpIncludeEmpty.button_pressed,
		"type_labels": _gpTypeLabels(),
	}
	_gpExporting = true
	gpExportButton.disabled = true
	gpStatusLabel.text = "…"
	var gpResult: GPIOResult = GPXlsxExport.gpExportLists(gpSelected, gpDefs, gpOptions)
	_gpExporting = false
	_gpShowResult(gpResult)
	_gpRefreshCounts()


func _gpShowResult(gpResult: GPIOResult) -> void:
	gpResultTree.clear()
	var gpRootItem: TreeItem = gpResultTree.create_item()
	var gpPayload: Dictionary = gpResult.gpPayload as Dictionary if gpResult.gpPayload is Dictionary else {}
	var gpFiles: Array = gpPayload.get("files", []) as Array
	var gpOkCount: int = 0
	var gpFailCount: int = 0
	for gpFileRaw in gpFiles:
		var gpFile: Dictionary = gpFileRaw as Dictionary
		var gpItem: TreeItem = gpResultTree.create_item(gpRootItem)
		gpItem.set_text(0, I18n.gpTr("xlsx.list." + str(gpFile.get("list", ""))))
		gpItem.set_text(1, str(gpFile.get("path", "")).get_file())
		gpItem.set_text(2, str(int(gpFile.get("rows", 0))))
		var gpOk: bool = bool(gpFile.get("ok", false))
		var gpSkipped: bool = bool(gpFile.get("skipped", false))
		if gpOk and gpSkipped:
			gpItem.set_text(3, I18n.gpTr("xlsx.col_status_skip"))
			gpItem.set_custom_color(3, Color(0.9, 0.8, 0.4))
		elif gpOk:
			gpOkCount += 1
			gpItem.set_text(3, I18n.gpTr("xlsx.col_status_ok"))
			gpItem.set_custom_color(3, Color(0.55, 0.85, 0.6))
		else:
			gpFailCount += 1
			gpItem.set_text(3, I18n.gpTr("xlsx.col_status_error") + " · " + str(gpFile.get("error", "")))
			gpItem.set_custom_color(3, Color(0.95, 0.55, 0.55))
	if gpOkCount > 0 and gpFailCount == 0:
		gpStatusLabel.text = I18n.gpTr("xlsx.status_exported") % gpOkCount
	elif gpOkCount > 0:
		gpStatusLabel.text = I18n.gpTr("xlsx.status_partial") % [gpOkCount, gpFailCount]
	else:
		var gpWhy: String = I18n.gpTr(gpResult.gpMessageKey) if gpResult.gpMessageKey != "" else gpResult.gpCode
		gpStatusLabel.text = I18n.gpTr("xlsx.status_failed") % gpWhy


# ==================== static helpers (tested headless) ====================

static func gpDefaultListIds() -> Array[String]:
	return GPDeliverableFields.gpListIds()


static func gpCheckedListIds(gpChecks: Dictionary) -> Array[String]:
	var gpOut: Array[String] = []
	for gpList in GPDeliverableFields.gpListIds():
		if bool(gpChecks.get(gpList, false)):
			gpOut.append(gpList)
	return gpOut


static func gpCountSummary(gpCounts: Dictionary) -> String:
	return "line=%d equipment=%d instrument=%d valve=%d" % [
		int(gpCounts.get("line", 0)), int(gpCounts.get("equipment", 0)),
		int(gpCounts.get("instrument", 0)), int(gpCounts.get("valve", 0))]
