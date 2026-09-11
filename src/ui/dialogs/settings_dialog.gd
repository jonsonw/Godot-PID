class_name GPSettingsDialog
extends Window

# Settings popup: UI font size, UI font family, symbol font size, symbol font
# family and language. Changes are applied immediately and persisted to
# user://settings.cfg.
# 设置弹窗：界面字号、界面字体、图元字号、图元字体与语言。更改即时应用并持久化到
# user://settings.cfg。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Dialog title label.
# 对话框标题标签。
var gpTitle: Label

# UI font size label.
# 界面字号标签。
var gpFontLabel: Label

# UI font size spin box.
# 界面字号选择框。
var gpFontSpin: SpinBox

# UI font family label.
# 界面字体标签。
var gpUIFontLabel: Label

# UI font family dropdown.
# 界面字体下拉框。
var gpUIFontOption: OptionButton

# Symbol font size label.
# 图元字号标签。
var gpSymSizeLabel: Label

# Symbol font size spin box.
# 图元字号选择框。
var gpSymSizeSpin: SpinBox

# Symbol font family label.
# 图元字体标签。
var gpSymFontLabel: Label

# Symbol font family dropdown.
# 图元字体下拉框。
var gpSymFontOption: OptionButton

# Language label.
# 语言标签。
var gpLangLabel: Label

# Language dropdown.
# 语言下拉框。
var gpLangOption: OptionButton

# Auto-scale dock widths label.
# 停靠栏自动缩放标签。
var gpAutoScaleLabel: Label

# Auto-scale dock widths checkbox.
# 停靠栏自动缩放复选框。
var gpAutoScaleCheck: CheckBox

# Pipe line-number rotation label (added programmatically; lives in no .tscn node).
# 管线位号旋转标签（动态添加，不在 .tscn 节点中）。
var gpPipeRotateLabel: Label

# Pipe line-number rotation checkbox.
# 管线位号旋转复选框。
var gpPipeRotateCheck: CheckBox

# Pipe line-number font size label (added programmatically).
# 管线位号字号标签（动态添加）。
var gpPipeFontSizeLabel: Label

# Pipe line-number font size spin box.
# 管线位号字号选择框。
var gpPipeFontSizeSpin: SpinBox

# OK button.
# 确定按钮。
var gpOk: Button


# Comfortable range of the settings layout, in logical UI units. A small dialog should track the
# monitor's scale (so it is not a postage stamp on HiDPI) without eating a share of a huge screen.
# 设置布局的舒适尺寸区间，单位为逻辑 UI 单位。小对话框应跟随显示器缩放（避免在 HiDPI 上小如
# 邮票），但不应按比例吃掉大屏的一大块。
const GP_MIN_LOGICAL: Vector2i = Vector2i(400, 430)
const GP_MAX_LOGICAL: Vector2i = Vector2i(470, 530)

# Preloaded rather than referenced by class_name (script load order safety).
# 用 preload 而非 class_name 引用（规避脚本加载顺序问题）。
const GP_WINDOW_FIT := preload("res://src/ui/dialogs/window_fit.gd")


# The window that owns this dialog (the main app window); the dialog pops up over it.
# 拥有本对话框的窗口（主程序窗口）；对话框弹在其上。
func _gpHostWindow() -> Window:
	var gpParent: Node = get_parent()
	if gpParent == null:
		return null
	return gpParent.get_window()


# Show the dialog as a movable, resizable window centered over the main window. Callers must use
# this instead of the bare `popup_centered()`, which ignores `size` and falls back to `min_size`.
# 以可移动、可缩放的窗口居中显示在主窗口之上。调用方须用本方法而非裸 `popup_centered()`
# ——后者会忽略 `size` 并退回 `min_size`。
func gpPopupOverHost() -> void:
	GP_WINDOW_FIT.gpPopupFitted(self, _gpHostWindow(), GP_MIN_LOGICAL, GP_MAX_LOGICAL)


# Build the dialog controls and bind signals.
# 构建对话框控件并绑定信号。
func _ready() -> void:
	close_requested.connect(queue_free)
	# Establish a `min_size` that provably fits the area we pop up in, replacing the hard-coded
	# size stored in the scene file. Final size / position comes from gpPopupOverHost().
	# 确立一个确定放得下的 `min_size`，替代场景文件里写死的尺寸；最终尺寸与位置由
	# gpPopupOverHost() 设定。
	GP_WINDOW_FIT.gpApply(self, _gpHostWindow(), GP_MIN_LOGICAL, GP_MAX_LOGICAL, false)

	# Fetch nodes from the scene tree.
	# 从场景树获取节点。
	gpTitle = $Panel/VBox/Title
	gpFontLabel = $Panel/VBox/UIRow/FontLabel
	gpFontSpin = $Panel/VBox/UIRow/FontSpin
	gpUIFontLabel = $Panel/VBox/UIFontRow/UIFontLabel
	gpUIFontOption = $Panel/VBox/UIFontRow/UIFontOption
	gpSymSizeLabel = $Panel/VBox/SymSizeRow/SymSizeLabel
	gpSymSizeSpin = $Panel/VBox/SymSizeRow/SymSizeSpin
	gpSymFontLabel = $Panel/VBox/SymFontRow/SymFontLabel
	gpSymFontOption = $Panel/VBox/SymFontRow/SymFontOption
	gpLangLabel = $Panel/VBox/LangRow/LangLabel
	gpLangOption = $Panel/VBox/LangRow/LangOption
	gpAutoScaleLabel = $Panel/VBox/AutoScaleRow/AutoScaleLabel
	gpAutoScaleCheck = $Panel/VBox/AutoScaleRow/AutoScaleCheck
	gpOk = $Panel/VBox/OK

	# UI font size spinner.
	# 界面字号选择器。
	gpFontSpin.min_value = 8
	gpFontSpin.max_value = 32
	gpFontSpin.step = 1
	gpFontSpin.value = Settings.gpFontSize
	gpFontSpin.value_changed.connect(_gpOnFontChanged)

	# Font dropdowns.
	# 字体下拉框。
	_gpFillFontOptions(gpUIFontOption, Settings.gpFontKey, _gpOnUIFontSelected)
	_gpFillFontOptions(gpSymFontOption, Settings.gpSymbolFontKey, _gpOnSymFontSelected)

	# Symbol font size spinner.
	# 图元字号选择器。
	gpSymSizeSpin.min_value = 8
	gpSymSizeSpin.max_value = 48
	gpSymSizeSpin.step = 1
	gpSymSizeSpin.value = Settings.gpSymbolFontSize
	gpSymSizeSpin.value_changed.connect(_gpOnSymSizeChanged)

	# Language dropdown.
	# 语言下拉框。
	gpLangOption.clear()
	gpLangOption.add_item(I18n.gpTr("settings.lang_zh"), 0)
	gpLangOption.set_item_metadata(0, "zh")
	gpLangOption.add_item(I18n.gpTr("settings.lang_en"), 1)
	gpLangOption.set_item_metadata(1, "en")
	_gpSelectLocale(Settings.gpLocale)
	gpLangOption.item_selected.connect(_gpOnLangSelected)

	# Auto-scale checkbox.
	# 自动缩放复选框。
	gpAutoScaleCheck.button_pressed = Settings.gpAutoScale
	gpAutoScaleCheck.toggled.connect(_gpOnAutoScaleToggled)

	# Pipe line-number style rows (added programmatically so the .tscn is untouched).
	# 管线位号样式两行（动态添加，不改动 .tscn）。
	_gpBuildPipeTagRows()

	gpOk.pressed.connect(queue_free)

	I18n.gpLocaleChanged.connect(_gpRefreshText)
	_gpRefreshText(I18n.gpLocale)


# Populate a font OptionButton from the preset registry and select the active key.
# 用预设登记表填充字体下拉框并选中当前键。
func _gpFillFontOptions(gpOpt: OptionButton, gpCurrentKey: String, gpCb: Callable) -> void:
	gpOpt.clear()
	var gpKeys: Array = Settings.GP_FONT_PRESETS.keys()
	var gpSel: int = 0
	for gpI in range(gpKeys.size()):
		var gpKey: String = gpKeys[gpI]
		var gpSpec: Dictionary = Settings.GP_FONT_PRESETS[gpKey]
		gpOpt.add_item(gpSpec.get(I18n.gpLocale, gpKey))
		gpOpt.set_item_metadata(gpI, gpKey)
		if gpKey == gpCurrentKey:
			gpSel = gpI
	gpOpt.selected = gpSel
	gpOpt.item_selected.connect(gpCb)


# Handle UI font size changes.
# 处理界面字号变化。
func _gpOnFontChanged(gpVal: float) -> void:
	Settings.gpFontSize = int(gpVal)
	Settings.gpApplyFontSize()
	Settings.gpSave()


# Handle UI font family selection.
# 处理界面字体选择。
func _gpOnUIFontSelected(gpIdx: int) -> void:
	var gpKey: String = gpUIFontOption.get_item_metadata(gpIdx)
	if gpKey == Settings.gpFontKey:
		return
	Settings.gpFontKey = gpKey
	Settings.gpApplyFontSize()
	Settings.gpSave()


# Handle symbol font size changes.
# 处理图元字号变化。
func _gpOnSymSizeChanged(gpVal: float) -> void:
	Settings.gpSymbolFontSize = int(gpVal)
	Settings.gpApplySymbolStyle()
	Settings.gpSave()


# Handle symbol font family selection.
# 处理图元字体选择。
func _gpOnSymFontSelected(gpIdx: int) -> void:
	var gpKey: String = gpSymFontOption.get_item_metadata(gpIdx)
	if gpKey == Settings.gpSymbolFontKey:
		return
	Settings.gpSymbolFontKey = gpKey
	Settings.gpApplySymbolStyle()
	Settings.gpSave()


# Handle language selection.
# 处理语言选择。
func _gpOnLangSelected(gpIdx: int) -> void:
	var gpCode: String = gpLangOption.get_item_metadata(gpIdx)
	if gpCode == Settings.gpLocale:
		return
	Settings.gpLocale = gpCode
	Settings.gpApplyLocale()
	Settings.gpSave()


# Handle auto-scale toggle.
# 处理自动缩放切换。
func _gpOnAutoScaleToggled(gpOn: bool) -> void:
	Settings.gpAutoScale = gpOn
	Settings.gpApplyFontSize()
	Settings.gpSave()


# Build the pipe line-number style rows (rotation + font size) and insert them into the
# VBox just before the OK button. Done in code so the scene file needs no edit.
# 构建管线位号样式两行（旋转 + 字号）并插入 VBox、紧邻「确定」按钮之前。以代码完成，
# 故无需改动场景文件。
func _gpBuildPipeTagRows() -> void:
	var gpVBox: VBoxContainer = $Panel/VBox

	# Rotation row: label + checkbox. / 旋转行：标签 + 复选框。
	var gpRotRow: HBoxContainer = HBoxContainer.new()
	gpPipeRotateLabel = Label.new()
	gpPipeRotateLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpPipeRotateCheck = CheckBox.new()
	gpPipeRotateCheck.button_pressed = Settings.gpPipeTagRotate
	gpPipeRotateCheck.toggled.connect(_gpOnPipeRotateToggled)
	gpRotRow.add_child(gpPipeRotateLabel)
	gpRotRow.add_child(gpPipeRotateCheck)

	# Font-size row: label + spin box. / 字号行：标签 + 选择框。
	var gpSizeRow: HBoxContainer = HBoxContainer.new()
	gpPipeFontSizeLabel = Label.new()
	gpPipeFontSizeLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpPipeFontSizeSpin = SpinBox.new()
	gpPipeFontSizeSpin.min_value = 0
	gpPipeFontSizeSpin.max_value = 48
	gpPipeFontSizeSpin.step = 1
	gpPipeFontSizeSpin.value = Settings.gpPipeTagFontSize
	gpPipeFontSizeSpin.value_changed.connect(_gpOnPipeFontSizeChanged)
	gpSizeRow.add_child(gpPipeFontSizeLabel)
	gpSizeRow.add_child(gpPipeFontSizeSpin)

	# Insert both rows right before the OK button. / 把两行插到「确定」按钮之前。
	var gpOkIdx: int = gpVBox.get_children().find(gpOk)
	gpVBox.add_child(gpRotRow)
	gpVBox.move_child(gpRotRow, gpOkIdx)
	gpVBox.add_child(gpSizeRow)
	gpVBox.move_child(gpSizeRow, gpOkIdx)


# Handle pipe line-number rotation toggle.
# 处理管线位号旋转切换。
func _gpOnPipeRotateToggled(gpOn: bool) -> void:
	Settings.gpPipeTagRotate = gpOn
	Settings.gpApplyPipeTagStyle()
	Settings.gpSave()


# Handle pipe line-number font size change.
# 处理管线位号字号变化。
func _gpOnPipeFontSizeChanged(gpVal: float) -> void:
	Settings.gpPipeTagFontSize = int(gpVal)
	Settings.gpApplyPipeTagStyle()
	Settings.gpSave()


# Select the language dropdown item matching the given locale code.
# 选中与给定语言代码匹配的语言下拉项。
func _gpSelectLocale(gpCode: String) -> void:
	for gpI in range(gpLangOption.item_count):
		if gpLangOption.get_item_metadata(gpI) == gpCode:
			gpLangOption.selected = gpI
			return


# Refresh all locale-dependent texts in the dialog.
# 刷新对话框中所有依赖语言的文本。
func _gpRefreshText(gpLocale: String) -> void:
	gpTitle.text = I18n.gpTr("settings.title")
	gpFontLabel.text = I18n.gpTr("settings.font_size")
	gpUIFontLabel.text = I18n.gpTr("settings.ui_font")
	gpSymSizeLabel.text = I18n.gpTr("settings.symbol_font_size")
	gpSymFontLabel.text = I18n.gpTr("settings.symbol_font")
	gpLangLabel.text = I18n.gpTr("settings.language")
	gpAutoScaleLabel.text = I18n.gpTr("settings.auto_scale")
	gpPipeRotateLabel.text = I18n.gpTr("settings.pipe_tag_rotate")
	gpPipeFontSizeLabel.text = I18n.gpTr("settings.pipe_tag_font_size")
	gpOk.text = I18n.gpTr("settings.ok")
	# Update the language item labels themselves so they match the new locale.
	# 更新语言下拉项本身的文本，使其与新语言一致。
	gpLangOption.set_item_text(0, I18n.gpTr("settings.lang_zh"))
	gpLangOption.set_item_text(1, I18n.gpTr("settings.lang_en"))
	# Refresh the font option labels so they match the new locale.
	# 刷新字体下拉项文本以匹配当前语言。
	_gpRefreshFontOptionLabels(gpUIFontOption)
	_gpRefreshFontOptionLabels(gpSymFontOption)


# Refresh the displayed labels of font dropdown items.
# 刷新字体下拉项的显示标签。
func _gpRefreshFontOptionLabels(gpOpt: OptionButton) -> void:
	for gpI in range(gpOpt.item_count):
		var gpKey: String = gpOpt.get_item_metadata(gpI)
		var gpSpec: Dictionary = Settings.GP_FONT_PRESETS.get(gpKey, {})
		gpOpt.set_item_text(gpI, gpSpec.get(I18n.gpLocale, gpKey))
