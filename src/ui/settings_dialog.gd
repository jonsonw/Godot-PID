class_name GPSettingsDialog
extends Window

# Settings popup: UI font size, UI font family, symbol font size, symbol font
# family and language. Changes are applied immediately and persisted to
# user://settings.cfg.
# 设置弹窗：界面字号、界面字体、图元字号、图元字体与语言。更改即时应用并持久化到
# user://settings.cfg。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpTitle: Label
var gpFontLabel: Label
var gpFontSpin: SpinBox
var gpUIFontLabel: Label
var gpUIFontOption: OptionButton
var gpSymSizeLabel: Label
var gpSymSizeSpin: SpinBox
var gpSymFontLabel: Label
var gpSymFontOption: OptionButton
var gpLangLabel: Label
var gpLangOption: OptionButton
var gpOk: Button


func _ready() -> void:
	close_requested.connect(queue_free)

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
	gpOk = $Panel/VBox/OK

	gpFontSpin.min_value = 8
	gpFontSpin.max_value = 32
	gpFontSpin.step = 1
	gpFontSpin.value = Settings.gpFontSize
	gpFontSpin.value_changed.connect(_gpOnFontChanged)

	_gpFillFontOptions(gpUIFontOption, Settings.gpFontKey, _gpOnUIFontSelected)
	_gpFillFontOptions(gpSymFontOption, Settings.gpSymbolFontKey, _gpOnSymFontSelected)

	gpSymSizeSpin.min_value = 8
	gpSymSizeSpin.max_value = 48
	gpSymSizeSpin.step = 1
	gpSymSizeSpin.value = Settings.gpSymbolFontSize
	gpSymSizeSpin.value_changed.connect(_gpOnSymSizeChanged)

	gpLangOption.clear()
	gpLangOption.add_item(I18n.gpTr("settings.lang_zh"), 0)
	gpLangOption.set_item_metadata(0, "zh")
	gpLangOption.add_item(I18n.gpTr("settings.lang_en"), 1)
	gpLangOption.set_item_metadata(1, "en")
	_gpSelectLocale(Settings.gpLocale)
	gpLangOption.item_selected.connect(_gpOnLangSelected)

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


func _gpOnFontChanged(gpVal: float) -> void:
	Settings.gpFontSize = int(gpVal)
	Settings.gpApplyFontSize()
	Settings.gpSave()


func _gpOnUIFontSelected(gpIdx: int) -> void:
	var gpKey: String = gpUIFontOption.get_item_metadata(gpIdx)
	if gpKey == Settings.gpFontKey:
		return
	Settings.gpFontKey = gpKey
	Settings.gpApplyFontSize()
	Settings.gpSave()


func _gpOnSymSizeChanged(gpVal: float) -> void:
	Settings.gpSymbolFontSize = int(gpVal)
	Settings.gpApplySymbolStyle()
	Settings.gpSave()


func _gpOnSymFontSelected(gpIdx: int) -> void:
	var gpKey: String = gpSymFontOption.get_item_metadata(gpIdx)
	if gpKey == Settings.gpSymbolFontKey:
		return
	Settings.gpSymbolFontKey = gpKey
	Settings.gpApplySymbolStyle()
	Settings.gpSave()


func _gpOnLangSelected(gpIdx: int) -> void:
	var gpCode: String = gpLangOption.get_item_metadata(gpIdx)
	if gpCode == Settings.gpLocale:
		return
	Settings.gpLocale = gpCode
	Settings.gpApplyLocale()
	Settings.gpSave()


func _gpSelectLocale(gpCode: String) -> void:
	for gpI in range(gpLangOption.item_count):
		if gpLangOption.get_item_metadata(gpI) == gpCode:
			gpLangOption.selected = gpI
			return


func _gpRefreshText(gpLocale: String) -> void:
	gpTitle.text = I18n.gpTr("settings.title")
	gpFontLabel.text = I18n.gpTr("settings.font_size")
	gpUIFontLabel.text = I18n.gpTr("settings.ui_font")
	gpSymSizeLabel.text = I18n.gpTr("settings.symbol_font_size")
	gpSymFontLabel.text = I18n.gpTr("settings.symbol_font")
	gpLangLabel.text = I18n.gpTr("settings.language")
	gpOk.text = I18n.gpTr("settings.ok")
	# Update the language item labels themselves so they match the new locale.
	# 更新语言下拉项本身的文本，使其与新语言一致。
	gpLangOption.set_item_text(0, I18n.gpTr("settings.lang_zh"))
	gpLangOption.set_item_text(1, I18n.gpTr("settings.lang_en"))
	# Refresh the font option labels so they match the new locale.
	# 刷新字体下拉项文本以匹配当前语言。
	_gpRefreshFontOptionLabels(gpUIFontOption)
	_gpRefreshFontOptionLabels(gpSymFontOption)


func _gpRefreshFontOptionLabels(gpOpt: OptionButton) -> void:
	for gpI in range(gpOpt.item_count):
		var gpKey: String = gpOpt.get_item_metadata(gpI)
		var gpSpec: Dictionary = Settings.GP_FONT_PRESETS.get(gpKey, {})
		gpOpt.set_item_text(gpI, gpSpec.get(I18n.gpLocale, gpKey))
