class_name GPTitleBlockDialog
extends Window

# Title-block / drawing-frame editor for one sheet (v0.1 Phase 2).
# 单张图纸的标题栏 / 图框编辑器（v0.1 Phase 2）。
# WHY BUILT ENTIRELY IN CODE: the dialog's rows are derived from
# GPSheet.GP_TB_FIELDS, so its shape must follow that table rather than a hand-authored
# .tscn that would silently drift whenever a field is added.
# 为何完全用代码构建：对话框的行是由 GPSheet.GP_TB_FIELDS 推导出来的，其形态必须随该表变化，
# 而不是手写的 .tscn —— 后者在新增字段时会静默失同步。
# Edits apply IMMEDIATELY (like the settings dialog): the frame repaints as you type, so
# "中英对照" stacking and per-cell overflow are visible before you commit to them.
# 编辑**即时生效**（同设置对话框）：边打字边重绘图框，以便在确定之前就能看到「中英对照」的
# 叠行效果与各格是否溢出。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

# Comfortable size range in logical UI units (see GPWindowFit).
# 逻辑 UI 单位下的舒适尺寸区间（见 GPWindowFit）。
const GP_MIN_LOGICAL: Vector2i = Vector2i(540, 560)
const GP_MAX_LOGICAL: Vector2i = Vector2i(660, 720)

# The sheet being edited. / 正在编辑的图纸。
var gpSheet: GPSheet = null

# Canvas to repaint after every change; null is fine (headless / no viewer).
# 每次改动后重绘的画布；为 null 亦可（headless / 无视图）。
var gpTarget: GPCanvas2D = null

# Show-frame checkbox. / 「显示图框」复选框。
var gpFrameCheck: CheckBox = null

# Sheet-size dropdown. / 图幅下拉框。
var gpSizeOption: OptionButton = null

# Drawing-text language dropdown. / 图纸文字语言下拉框。
var gpModeOption: OptionButton = null

# field key -> { "zh": LineEdit, "en": LineEdit }.
# 字段键 -> { "zh": 中文输入框, "en": 英文输入框 }。
var gpEdits: Dictionary = {}

# Tracing-underlay controls (v0.1 Phase 5). / 追踪底图控件（v0.1 Phase 5）。
var gpFileDialog: FileDialog = null
var gpBgPathEdit: LineEdit = null


# Bind the sheet and the canvas to repaint; call before showing.
# 绑定要编辑的图纸与要重绘的画布；显示前调用。
# [param gpS] the sheet to edit / 待编辑的图纸
# [param gpCanvas] canvas to repaint (may be null) / 需要重绘的画布（可为 null）
func gpConfigure(gpS: GPSheet, gpCanvas: GPCanvas2D = null) -> void:
	gpSheet = gpS
	gpTarget = gpCanvas


# Show the dialog centered over the host window.
# 居中显示在宿主窗口之上。
func gpPopupOverHost() -> void:
	var gpParent: Node = get_parent()
	var gpHost: Window = gpParent.get_window() if gpParent != null else null
	GPWindowFit.gpPopupFitted(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL)


func _ready() -> void:
	title = I18n.gpTr("frame.title")
	close_requested.connect(queue_free)
	var gpHost: Window = null
	var gpParent: Node = get_parent()
	if gpParent != null:
		gpHost = gpParent.get_window()
	GPWindowFit.gpApply(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL, false)
	_gpBuild()


# Build the whole dialog: frame options, then one row per title-block field.
# 构建整个对话框：先是图框选项，再是标题栏每个字段一行。
func _gpBuild() -> void:
	var gpRoot: MarginContainer = MarginContainer.new()
	gpRoot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpRoot.add_theme_constant_override("margin_left", 12)
	gpRoot.add_theme_constant_override("margin_right", 12)
	gpRoot.add_theme_constant_override("margin_top", 12)
	gpRoot.add_theme_constant_override("margin_bottom", 12)
	add_child(gpRoot)
	var gpVBox: VBoxContainer = VBoxContainer.new()
	gpVBox.add_theme_constant_override("separation", 8)
	gpRoot.add_child(gpVBox)
	if gpSheet == null:
		return
	_gpBuildOptions(gpVBox)
	_gpBuildBackground(gpVBox)
	var gpScroll: ScrollContainer = ScrollContainer.new()
	gpScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpVBox.add_child(gpScroll)
	var gpGrid: GridContainer = GridContainer.new()
	gpGrid.columns = 3
	gpGrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpGrid.add_theme_constant_override("h_separation", 8)
	gpGrid.add_theme_constant_override("v_separation", 6)
	gpScroll.add_child(gpGrid)
	_gpBuildFieldRows(gpGrid)
	var gpOk: Button = Button.new()
	gpOk.text = I18n.gpTr("dialog.ok")
	gpOk.pressed.connect(queue_free)
	gpVBox.add_child(gpOk)


# Frame on/off, sheet size and label-mode controls.
# 图框开关、图幅与标签模式控件。
func _gpBuildOptions(gpVBox: VBoxContainer) -> void:
	gpFrameCheck = CheckBox.new()
	gpFrameCheck.text = I18n.gpTr("frame.show")
	gpFrameCheck.button_pressed = gpSheet.gpFrameOn
	gpFrameCheck.toggled.connect(_gpOnFrameToggled)
	gpVBox.add_child(gpFrameCheck)

	var gpSizeRow: HBoxContainer = HBoxContainer.new()
	var gpSizeLabel: Label = Label.new()
	gpSizeLabel.text = I18n.gpTr("frame.size")
	gpSizeLabel.custom_minimum_size = Vector2(120.0, 0.0)
	gpSizeRow.add_child(gpSizeLabel)
	gpSizeOption = OptionButton.new()
	gpSizeOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Biggest first, so "A3" (the default) is not buried at the end of the list.
	# 由大到小排列，使默认值 A3 不至于埋在列表末尾。
	for gpK in ["A0", "A1", "A2", "A3", "A4"]:
		gpSizeOption.add_item(gpK)
		gpSizeOption.set_item_metadata(gpSizeOption.item_count - 1, gpK)
	_gpSelectSize(gpKFor(gpSheet.gpWidthMM, gpSheet.gpHeightMM))
	gpSizeOption.item_selected.connect(_gpOnSizeSelected)
	gpSizeRow.add_child(gpSizeOption)
	gpVBox.add_child(gpSizeRow)

	var gpModeRow: HBoxContainer = HBoxContainer.new()
	var gpModeLabel: Label = Label.new()
	gpModeLabel.text = I18n.gpTr("frame.label_mode")
	gpModeLabel.custom_minimum_size = Vector2(120.0, 0.0)
	gpModeRow.add_child(gpModeLabel)
	gpModeOption = OptionButton.new()
	gpModeOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpModeOption.add_item(I18n.gpTr("frame.mode_zh"), GPSheet.GP_LABEL_ZH)
	gpModeOption.add_item(I18n.gpTr("frame.mode_en"), GPSheet.GP_LABEL_EN)
	gpModeOption.add_item(I18n.gpTr("frame.mode_both"), GPSheet.GP_LABEL_BOTH)
	gpModeOption.select(_gpModeIndex(gpSheet.gpLabelMode))
	gpModeOption.item_selected.connect(_gpOnModeSelected)
	gpModeRow.add_child(gpModeOption)
	gpVBox.add_child(gpModeRow)

	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("frame.mode_hint")
	gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpHint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	gpHint.custom_minimum_size = Vector2(0.0, 34.0)
	gpVBox.add_child(gpHint)


# Tracing-underlay section: image path + browse/clear, and an opacity slider.
# 追踪底图段落：图片路径 + 浏览/清除，以及透明度滑块。
func _gpBuildBackground(gpVBox: VBoxContainer) -> void:
	var gpSec: Label = Label.new()
	gpSec.text = I18n.gpTr("frame.bg.title")
	gpVBox.add_child(gpSec)

	# Path row: editable text + a file picker + a clear button.
	# 路径行：可编辑文本 + 文件选择器 + 清除按钮。
	var gpPathRow: HBoxContainer = HBoxContainer.new()
	gpBgPathEdit = LineEdit.new()
	gpBgPathEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBgPathEdit.placeholder = I18n.gpTr("frame.bg.path")
	gpBgPathEdit.text = gpSheet.gpBackgroundPath
	gpBgPathEdit.text_changed.connect(func(gpT: String) -> void: _gpOnBgPath(gpT))
	gpPathRow.add_child(gpBgPathEdit)
	var gpBrowse: Button = Button.new()
	gpBrowse.text = I18n.gpTr("frame.bg.browse")
	gpBrowse.pressed.connect(_gpOpenBrowse)
	gpPathRow.add_child(gpBrowse)
	var gpClear: Button = Button.new()
	gpClear.text = I18n.gpTr("frame.bg.clear")
	gpClear.pressed.connect(func() -> void: _gpOnBgPath(""))
	gpPathRow.add_child(gpClear)
	gpVBox.add_child(gpPathRow)

	# Opacity row: a slider in [0.05, 1.0] so the underlay stays a faint reference.
	# 透明度行：滑块范围 [0.05, 1.0]，使底图始终为淡参考。
	var gpAlphaRow: HBoxContainer = HBoxContainer.new()
	var gpAlphaLabel: Label = Label.new()
	gpAlphaLabel.text = I18n.gpTr("frame.bg.alpha")
	gpAlphaLabel.custom_minimum_size = Vector2(120.0, 0.0)
	gpAlphaRow.add_child(gpAlphaLabel)
	var gpAlpha: HSlider = HSlider.new()
	gpAlpha.min_value = 0.05
	gpAlpha.max_value = 1.0
	gpAlpha.step = 0.05
	gpAlpha.value = gpSheet.gpBackgroundAlpha
	gpAlpha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpAlpha.value_changed.connect(func(gpV: float) -> void: _gpOnBgAlpha(gpV))
	gpAlphaRow.add_child(gpAlpha)
	gpVBox.add_child(gpAlphaRow)

	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("frame.bg.hint")
	gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpHint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	gpHint.custom_minimum_size = Vector2(0.0, 30.0)
	gpVBox.add_child(gpHint)

	# File picker is a child so it is freed with this dialog.
	# 文件选择器作为子节点，随本对话框一并释放。
	gpFileDialog = FileDialog.new()
	gpFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	gpFileDialog.access = FileDialog.ACCESS_FILESYSTEM
	gpFileDialog.add_filter("*.png,*.jpg,*.jpeg,*.webp", "Image")
	gpFileDialog.file_selected.connect(_gpOnBgFilePicked)
	add_child(gpFileDialog)


# One row per standard field: bilingual caption, then the zh / en value inputs.
# 每个标准字段一行：双语字段名，后接中文 / 英文取值输入框。
func _gpBuildFieldRows(gpGrid: GridContainer) -> void:
	for gpF in GPSheet.GP_TB_FIELDS:
		var gpKey: String = str(gpF["key"])
		var gpCap: Label = Label.new()
		gpCap.text = I18n.gpTrBoth(str(gpF["cap"]))
		gpCap.custom_minimum_size = Vector2(110.0, 0.0)
		gpGrid.add_child(gpCap)
		var gpZh: LineEdit = LineEdit.new()
		gpZh.placeholder = I18n.gpTr("frame.col_zh")
		gpZh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gpZh.text = _gpValueOf(gpKey, "zh")
		gpZh.text_changed.connect(func(gpT: String) -> void: _gpOnValueChanged(gpKey, "zh", gpT))
		gpGrid.add_child(gpZh)
		var gpEn: LineEdit = LineEdit.new()
		gpEn.placeholder = I18n.gpTr("frame.col_en")
		gpEn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gpEn.text = _gpValueOf(gpKey, "en")
		gpEn.text_changed.connect(func(gpT: String) -> void: _gpOnValueChanged(gpKey, "en", gpT))
		gpGrid.add_child(gpEn)
		gpEdits[gpKey] = {"zh": gpZh, "en": gpEn}


# Read one language slot of one field, tolerating a missing entry.
# 读取某字段某一语言槽的值；条目缺失时容错。
func _gpValueOf(gpKey: String, gpLang: String) -> String:
	var gpEntry: Variant = gpSheet.gpTitleBlock.get(gpKey)
	if gpEntry == null:
		return ""
	var gpVal: Variant = (gpEntry as Dictionary).get("value")
	if gpVal == null:
		return ""
	return str((gpVal as Dictionary).get(gpLang, ""))


func _gpOnValueChanged(gpKey: String, gpLang: String, gpText: String) -> void:
	var gpEntry: Variant = gpSheet.gpTitleBlock.get(gpKey)
	if gpEntry == null:
		gpEntry = {"value": {"zh": "", "en": ""}}
		gpSheet.gpTitleBlock[gpKey] = gpEntry
	var gpVal: Variant = (gpEntry as Dictionary).get("value")
	if gpVal == null:
		gpVal = {"zh": "", "en": ""}
		(gpEntry as Dictionary)["value"] = gpVal
	(gpVal as Dictionary)[gpLang] = gpText
	_gpRepaint()


func _gpOnFrameToggled(gpOn: bool) -> void:
	gpSheet.gpFrameOn = gpOn
	_gpRepaint()


func _gpOnSizeSelected(_gpIdx: int) -> void:
	var gpK: String = str(gpSizeOption.get_selected_metadata())
	var gpV: Vector2 = GPSheet.GP_SHEET_PRESETS.get(gpK, GPSheet.GP_SHEET_PRESETS["A3"])
	gpSheet.gpWidthMM = gpV.x
	gpSheet.gpHeightMM = gpV.y
	# Keep the SIZE cell honest: it is derived from the real sheet, not typed by hand.
	# 让「图幅」格保持诚实：它由图幅推导，而非手填。
	gpSheet.gpSyncSheetSizeField()
	var gpE: Dictionary = gpEdits.get("sheet_size", {}) as Dictionary
	if gpE.has("zh"):
		(gpE["zh"] as LineEdit).text = gpK
		(gpE["en"] as LineEdit).text = gpK
	_gpRepaint()


func _gpOnModeSelected(gpIdx: int) -> void:
	gpSheet.gpLabelMode = int(gpModeOption.get_item_id(gpIdx))
	_gpRepaint()


func _gpOpenBrowse() -> void:
	if gpFileDialog != null:
		gpFileDialog.popup_centered(Vector2i(720, 480))


func _gpOnBgFilePicked(gpPath: String) -> void:
	gpSheet.gpBackgroundPath = gpPath
	if gpBgPathEdit != null:
		gpBgPathEdit.text = gpPath
	_gpRepaint()


func _gpOnBgPath(gpPath: String) -> void:
	gpSheet.gpBackgroundPath = gpPath
	_gpRepaint()


func _gpOnBgAlpha(gpV: float) -> void:
	gpSheet.gpBackgroundAlpha = gpV
	_gpRepaint()


# Push the edited sheet back to the canvas so the frame redraws.
# 把编辑后的图纸推回画布，使图框重绘。
func _gpRepaint() -> void:
	if gpTarget != null:
		gpTarget.gpSetSheet(gpSheet)


# Option-button row matching the sheet's current size.
# 选中与当前图幅匹配的下拉项。
func _gpSelectSize(gpK: String) -> void:
	for gpI in range(gpSizeOption.item_count):
		if str(gpSizeOption.get_item_metadata(gpI)) == gpK:
			gpSizeOption.select(gpI)
			return


func _gpModeIndex(gpMode: int) -> int:
	for gpI in range(gpModeOption.item_count):
		if gpModeOption.get_item_id(gpI) == gpMode:
			return gpI
	return 0


# Nearest preset name for a size; "" when the size is custom.
# 尺寸最接近的预设名；自定义尺寸时为空串。
static func gpKFor(gpW: float, gpH: float) -> String:
	for gpK in GPSheet.GP_SHEET_PRESETS:
		var gpV: Vector2 = GPSheet.GP_SHEET_PRESETS[gpK]
		if absf(gpV.x - gpW) < 0.5 and absf(gpV.y - gpH) < 0.5:
			return str(gpK)
	return ""
