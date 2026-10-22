class_name GPImportListsDialog
extends Window
# Copyright © 2026 Jonson Wang
#
# Classified-list import dialog: pick an edited .xlsx, preview old→new/clear changes, then
# apply them as ONE undo step per drawing. It never creates/deletes entities and never writes
# tags/line numbers/geometry.
# 分类清单导入对话框：选改过的 .xlsx、预览 old→new/清空，然后按图纸各一条撤销步应用。
# 绝不新建/删除实体，绝不写位号/管线号/几何。
#
# WHY PREVIEW FIRST / 为何先预览：
# Excel is a free-form editor; the same file can contain stale rows, unknown tags and cleared
# cells. Applying directly would make the drawing change before the user can see what will
# happen. The preview is the contract.
# Excel 是自由编辑器；同一文件可能含过期行、未知位号与空单元格。直接应用会让图纸在用户看到
# 后果之前就改变。预览就是契约。
#
# Coding rule: every variable declares its type explicitly. / 编码规范：变量显式类型。

const GP_WINDOW_FIT := preload("res://src/ui/dialogs/window_fit.gd")
const GP_MIN_LOGICAL: Vector2i = Vector2i(900, 620)
const GP_MAX_LOGICAL: Vector2i = Vector2i(1180, 840)

var gpSheets: Array = []
var gpDefs: Array[GPSymbolDef] = []
var gpCenter: GPCenterArea = null
var gpLocale: String = "zh"

var gpFileEdit: LineEdit = null
var gpListOption: OptionButton = null
var gpTree: Tree = null
var gpStatusLabel: Label = null
var gpApplyButton: Button = null
var gpReadButton: Button = null
var gpFileDialog: FileDialog = null
var gpSheetChecks: Dictionary = {}

var gpChanges: Array = []
var gpIssues: Array = []
var _gpBuilt: bool = false


func gpConfigure(gpSheetsIn: Array, gpDefsIn: Array[GPSymbolDef], gpCenterIn: GPCenterArea,
		gpLocaleIn: String = "") -> void:
	gpSheets = gpSheetsIn
	gpDefs = gpDefsIn
	gpCenter = gpCenterIn
	gpLocale = gpLocaleIn if gpLocaleIn != "" else I18n.gpLocale


func gpPopupOverHost() -> void:
	var gpParent: Node = get_parent()
	var gpHost: Window = gpParent.get_window() if gpParent != null else null
	GP_WINDOW_FIT.gpPopupFitted(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL)


func _ready() -> void:
	title = I18n.gpTr("xlsx.import_title")
	close_requested.connect(queue_free)
	var gpParent: Node = get_parent()
	var gpHost: Window = gpParent.get_window() if gpParent != null else null
	GP_WINDOW_FIT.gpApply(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL, false)
	_gpBuild()
	_gpBuilt = true


# Set a file path programmatically (used by the visual preview); does not auto-read.
# 程序化设置文件路径（可视化预览用）；不自动读取。
func gpSetFilePath(gpPath: String) -> void:
	gpFileEdit.text = gpPath


# Read the current file and populate the preview. Public so the preview tool can drive the
# same path as the button.
# 读取当前文件并填充预览。公开以便可视化工具走与按钮相同的路径。
func gpReadPreview() -> void:
	gpChanges = []
	gpIssues = []
	gpTree.clear()
	gpApplyButton.disabled = true
	var gpPath: String = gpFileEdit.text.strip_edges()
	if gpPath == "":
		gpStatusLabel.text = I18n.gpTr("xlsx.import_no_file")
		return
	var gpSelected: Array = _gpSelectedSheets()
	if gpSelected.is_empty():
		gpStatusLabel.text = I18n.gpTr("xlsx.no_sheets")
		return
	var gpList: String = ""
	if gpListOption.selected > 0:
		gpList = str(gpListOption.get_item_metadata(gpListOption.selected))
	gpStatusLabel.text = "…"
	var gpRead: Dictionary = GPXlsxImport.gpRead([{"path": gpPath, "list": gpList}],
		gpSelected, gpDefs, {"locale": gpLocale, "type_labels": _gpTypeLabels()})
	gpChanges = gpRead.get("changes", []) as Array
	gpIssues = gpRead.get("issues", []) as Array
	_gpFillTree()
	gpApplyButton.disabled = gpChanges.is_empty()
	if gpChanges.is_empty():
		gpStatusLabel.text = I18n.gpTr("xlsx.import_no_changes")
	else:
		gpStatusLabel.text = I18n.gpTr("xlsx.import_ready") % gpChanges.size()


func gpApplyPreview() -> void:
	if gpChanges.is_empty():
		return
	if gpCenter == null:
		gpStatusLabel.text = I18n.gpTr("xlsx.import_failed") % "no_center"
		return
	var gpBySheet: Dictionary = {}
	for gpChangeRaw in gpChanges:
		var gpChange: Dictionary = gpChangeRaw as Dictionary
		var gpSheetId: String = str(gpChange.get("sheet_id", ""))
		if not gpBySheet.has(gpSheetId):
			gpBySheet[gpSheetId] = []
		(gpBySheet[gpSheetId] as Array).append(gpChange)
	var gpAppliedSheets: int = 0
	var gpAppliedChanges: int = 0
	var gpStaleChanges: int = 0
	var gpFailed: int = 0
	for gpSheetIdRaw in gpBySheet.keys():
		var gpSheetId: String = str(gpSheetIdRaw)
		var gpCanvas: GPCanvas2D = _gpCanvasOf(gpSheetId)
		if gpCanvas == null:
			gpFailed += 1
			continue
		var gpCmd: GPApplyListChangesCommand = GPApplyListChangesCommand.new(
			gpBySheet[gpSheetId] as Array)
		if gpCanvas.gpActions.gpExecuteCommand(gpCmd):
			gpAppliedSheets += 1
			gpAppliedChanges += (gpBySheet[gpSheetId] as Array).size()
		gpStaleChanges += gpCmd.gpStale.size()
	if gpAppliedSheets > 0:
		gpStatusLabel.text = I18n.gpTr("xlsx.import_applied") % [gpAppliedChanges, gpAppliedSheets]
		if gpStaleChanges > 0:
			gpStatusLabel.text += " " + (I18n.gpTr("xlsx.import_stale") % gpStaleChanges)
		gpApplyButton.disabled = true
	else:
		gpStatusLabel.text = I18n.gpTr("xlsx.import_failed") % str(gpFailed)


func _gpCanvasOf(gpSheetId: String) -> GPCanvas2D:
	if gpCenter == null:
		return null
	for gpTabRaw in gpCenter.gpTabs:
		var gpTab: Dictionary = gpTabRaw as Dictionary
		var gpSheet: GPSheet = gpTab.get("sheet") as GPSheet
		if gpSheet != null and gpSheet.gpId == gpSheetId:
			return gpTab.get("canvas") as GPCanvas2D
	return null


# ==================== build / 构建 ====================

func _gpBuild() -> void:
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
	gpTitle.text = I18n.gpTr("xlsx.import_title")
	gpTitle.add_theme_font_size_override("font_size", 18)
	gpRoot.add_child(gpTitle)
	var gpSub: Label = Label.new()
	gpSub.text = I18n.gpTr("xlsx.import_subtitle")
	gpSub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpSub.modulate = Color(1, 1, 1, 0.75)
	gpRoot.add_child(gpSub)

	var gpFileRow: HBoxContainer = HBoxContainer.new()
	gpFileRow.add_theme_constant_override("separation", 6)
	gpRoot.add_child(gpFileRow)
	var gpFileLabel: Label = Label.new()
	gpFileLabel.text = I18n.gpTr("xlsx.import_file")
	gpFileLabel.custom_minimum_size = Vector2(70, 0)
	gpFileRow.add_child(gpFileLabel)
	gpFileEdit = LineEdit.new()
	gpFileEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpFileRow.add_child(gpFileEdit)
	var gpBrowse: Button = Button.new()
	gpBrowse.text = I18n.gpTr("xlsx.import_browse")
	gpBrowse.pressed.connect(_gpBrowse)
	gpFileRow.add_child(gpBrowse)
	var gpListLabel: Label = Label.new()
	gpListLabel.text = I18n.gpTr("xlsx.import_list")
	gpFileRow.add_child(gpListLabel)
	gpListOption = OptionButton.new()
	gpListOption.add_item(I18n.gpTr("xlsx.import_auto"), 0)
	gpListOption.set_item_metadata(0, "")
	for gpList in GPDeliverableFields.gpListIds():
		gpListOption.add_item(I18n.gpTr("xlsx.list." + gpList), gpListOption.item_count)
		gpListOption.set_item_metadata(gpListOption.item_count - 1, gpList)
	gpFileRow.add_child(gpListOption)
	gpReadButton = Button.new()
	gpReadButton.text = I18n.gpTr("xlsx.import_read")
	gpReadButton.pressed.connect(gpReadPreview)
	gpFileRow.add_child(gpReadButton)

	var gpBody: HBoxContainer = HBoxContainer.new()
	gpBody.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpBody.add_theme_constant_override("separation", 10)
	gpRoot.add_child(gpBody)

	var gpLeft: PanelContainer = PanelContainer.new()
	gpLeft.custom_minimum_size = Vector2(220, 0)
	gpLeft.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpBody.add_child(gpLeft)
	var gpLeftBox: VBoxContainer = VBoxContainer.new()
	gpLeft.add_child(gpLeftBox)
	var gpSheetsTitle: Label = Label.new()
	gpSheetsTitle.text = I18n.gpTr("xlsx.import_drawings")
	gpLeftBox.add_child(gpSheetsTitle)
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
		gpCheck.text = "%02d  %s" % [gpI + 1, gpSheet.gpName]
		gpCheck.button_pressed = true
		gpCheck.toggled.connect(func(_p: bool) -> void: gpReadPreview())
		gpSheetBox.add_child(gpCheck)
		gpSheetChecks[gpI] = gpCheck

	var gpRight: VBoxContainer = VBoxContainer.new()
	gpRight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBody.add_child(gpRight)
	gpTree = Tree.new()
	gpTree.hide_root = true
	gpTree.column_titles_visible = true
	gpTree.columns = 7
	var gpTitles: Array[String] = [
		I18n.gpTr("xlsx.import_col_drawing"), I18n.gpTr("xlsx.import_col_list"),
		I18n.gpTr("xlsx.import_col_target"), I18n.gpTr("xlsx.import_col_field"),
		I18n.gpTr("xlsx.import_col_old"), I18n.gpTr("xlsx.import_col_new"),
		I18n.gpTr("xlsx.import_col_status"),
	]
	for gpI in range(gpTitles.size()):
		gpTree.set_column_title(gpI, gpTitles[gpI])
		gpTree.set_column_custom_minimum_width(gpI, 70 if gpI < 6 else 90)
	gpTree.set_column_expand(2, true)
	gpTree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpRight.add_child(gpTree)

	var gpBottom: HBoxContainer = HBoxContainer.new()
	gpRoot.add_child(gpBottom)
	gpStatusLabel = Label.new()
	gpStatusLabel.text = I18n.gpTr("xlsx.import_initial")
	gpStatusLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpStatusLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpBottom.add_child(gpStatusLabel)
	var gpClose: Button = Button.new()
	gpClose.text = I18n.gpTr("xlsx.import_close")
	gpClose.pressed.connect(queue_free)
	gpBottom.add_child(gpClose)
	gpApplyButton = Button.new()
	gpApplyButton.text = I18n.gpTr("xlsx.import_apply")
	gpApplyButton.disabled = true
	gpApplyButton.pressed.connect(gpApplyPreview)
	gpBottom.add_child(gpApplyButton)

	gpFileDialog = FileDialog.new()
	gpFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	gpFileDialog.access = FileDialog.ACCESS_FILESYSTEM
	gpFileDialog.use_native_dialog = false
	gpFileDialog.filters = PackedStringArray(["*.xlsx ; Excel Workbook"])
	gpFileDialog.file_selected.connect(func(gpPath: String) -> void:
		gpFileEdit.text = gpPath
		gpReadPreview())
	add_child(gpFileDialog)


func _gpFillTree() -> void:
	var gpRootItem: TreeItem = gpTree.create_item()
	for gpChangeRaw in gpChanges:
		var gpChange: Dictionary = gpChangeRaw as Dictionary
		var gpItem: TreeItem = gpTree.create_item(gpRootItem)
		gpItem.set_text(0, str(gpChange.get("sheet_name", "")))
		gpItem.set_text(1, I18n.gpTr("xlsx.list." + str(gpChange.get("list", ""))))
		gpItem.set_text(2, str(gpChange.get("target_label", "")))
		gpItem.set_text(3, _gpFieldLabel(gpChange))
		var gpOld: Variant = gpChange.get("old", null)
		gpItem.set_text(4, "" if gpOld == null else str(gpOld))
		if bool(gpChange.get("clear", false)):
			gpItem.set_text(5, I18n.gpTr("xlsx.import_clear"))
			gpItem.set_custom_color(5, Color(0.95, 0.7, 0.4))
		else:
			gpItem.set_text(5, str(gpChange.get("new", "")))
		gpItem.set_text(6, I18n.gpTr("xlsx.import_change"))
		gpItem.set_custom_color(6, Color(0.55, 0.85, 0.6))
	for gpIssueRaw in gpIssues:
		var gpIssue: Dictionary = gpIssueRaw as Dictionary
		var gpItem: TreeItem = gpTree.create_item(gpRootItem)
		gpItem.set_text(0, "")
		gpItem.set_text(1, "")
		gpItem.set_text(2, "")
		gpItem.set_text(3, str(gpIssue.get("code", "")))
		gpItem.set_text(4, "")
		gpItem.set_text(5, "")
		gpItem.set_text(6, I18n.gpTr("xlsx.import_issue"))
		gpItem.set_custom_color(6, Color(0.95, 0.55, 0.55))


func _gpFieldLabel(gpChange: Dictionary) -> String:
	var gpField: String = str(gpChange.get("field", ""))
	if gpField == "name":
		return I18n.gpTr("xlsx.import_name")
	if gpField.begins_with("prop:"):
		return gpField.substr("prop:".length())
	return GPDeliverableFields.gpLabel(gpField, gpLocale)


func _gpSelectedSheets() -> Array:
	var gpOut: Array = []
	for gpI in range(gpSheets.size()):
		var gpCheck: CheckBox = gpSheetChecks.get(gpI, null) as CheckBox
		if gpCheck != null and gpCheck.button_pressed:
			gpOut.append(gpSheets[gpI])
	return gpOut


func _gpTypeLabels() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpDef in gpDefs:
		if gpDef == null:
			continue
		var gpLabel: String = I18n.gpTr(gpDef.gpDisplayName)
		gpOut[gpDef.gpId] = gpLabel if gpLabel != "" else gpDef.gpId
	return gpOut


func _gpBrowse() -> void:
	gpFileDialog.popup_centered_ratio(0.7)


func _gpTheme() -> Theme:
	var gpTheme: Theme = Theme.new()
	var gpText: Color = Color(0.92, 0.94, 0.97)
	gpTheme.set_color("font_color", "Label", gpText)
	gpTheme.set_color("font_color", "CheckBox", gpText)
	gpTheme.set_color("font_color", "Button", gpText)
	gpTheme.set_color("font_hover_color", "Button", Color(1, 1, 1))
	gpTheme.set_color("font_color", "LineEdit", gpText)
	gpTheme.set_color("font_color", "Tree", gpText)
	gpTheme.set_color("font_selected_color", "Tree", Color(1, 1, 1))
	gpTheme.set_color("title_button_color", "Tree", Color(0.75, 0.79, 0.85))
	return gpTheme
