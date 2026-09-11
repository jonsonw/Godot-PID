class_name GPTagRuleDialog
extends ConfirmationDialog
# Copyright © 2026 Jonson Wang
# "Project > Tag numbering rules" dialog (M9b).
# 「项目 > 位号编号规则」对话框（M9b）。
#
# Design notes / 设计说明:
#   - Every keystroke re-validates and re-renders the preview through GPTagRuleService, so
#     the user never has to press OK to find out the template is illegal.
#     每次按键都经 GPTagRuleService 重新校验并重算预览，用户无需按「确定」才发现模板非法。
#   - The dialog edits a COPY. Nothing touches the document until the user confirms, which
#     is what makes Cancel a true no-op.
#     对话框编辑的是副本。用户确认前不触碰文档，这才使「取消」成为真正的空操作。
#   - Rules are project configuration and travel with the *.pid.json, so this dialog is also
#     the only place a project can diverge from the factory convention.
#     规则是工程配置且随 *.pid.json 走，故本对话框也是工程偏离出厂约定的唯一入口。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Emitted on confirm: the new rules and whether to renumber every existing instance.
# 确认时发出：新规则，以及是否重排全部现有实例。
signal gpRulesApplied(gpRules: GPProjectTagRules, gpRenumber: bool)

# The rules being edited. A working copy; the document keeps the old one until confirm.
# 正在编辑的规则。为工作副本；确认前文档保留旧的那份。
var gpRules: GPProjectTagRules = null

# How many instances a full renumber would touch (0 when unknown).
# 全量重编号将影响多少实例（未知时为 0）。
var gpInstanceCount: int = 0

# ---- widgets ----
var _gpTemplate: LineEdit = null
var _gpStart: SpinBox = null
var _gpStep: SpinBox = null
var _gpDigits: SpinBox = null
var _gpSource: OptionButton = null
var _gpFixed: LineEdit = null
var _gpPreview: Label = null
var _gpError: Label = null
var _gpRenumber: CheckBox = null
var _gpPrefixEdits: Dictionary = {}


# Build the form once. / 一次性构建表单。
func _ready() -> void:
	title = I18n.gpTr("tag_rule.title")
	ok_button_text = I18n.gpTr("dialog.ok")
	cancel_button_text = I18n.gpTr("dialog.cancel")
	_gpBuild()
	# Re-validate after the built-in buttons exist, so an invalid initial state disables OK.
	# 在内建按钮存在后再校验，使非法初始态能禁用「确定」。
	_gpOnChanged("")


# Lay out every control. / 排布所有控件。
func _gpBuild() -> void:
	var gpRoot: VBoxContainer = VBoxContainer.new()
	add_child(gpRoot)

	gpRoot.add_child(_gpSectionLabel("tag_rule.template"))
	_gpTemplate = LineEdit.new()
	_gpTemplate.text_submitted.connect(_gpOnChanged)
	_gpTemplate.text_changed.connect(_gpOnChanged)
	gpRoot.add_child(_gpTemplate)

	gpRoot.add_child(_gpSectionLabel("tag_rule.numbers"))
	var gpNumRow: HBoxContainer = HBoxContainer.new()
	_gpStart = _gpSpin(gpNumRow, "tag_rule.start", 0, 999999, 1)
	_gpStep = _gpSpin(gpNumRow, "tag_rule.step", 1, 100, 1)
	_gpDigits = _gpSpin(gpNumRow, "tag_rule.digits", 0, 8, 1)
	gpRoot.add_child(gpNumRow)

	gpRoot.add_child(_gpSectionLabel("tag_rule.source"))
	_gpSource = OptionButton.new()
	_gpSource.add_item(I18n.gpTr("tag_rule.by_category"), 0)
	_gpSource.add_item(I18n.gpTr("tag_rule.by_symbol"), 1)
	_gpSource.add_item(I18n.gpTr("tag_rule.fixed"), 2)
	_gpSource.item_selected.connect(_gpOnSourceChanged)
	gpRoot.add_child(_gpSource)

	gpRoot.add_child(_gpSectionLabel("tag_rule.fixed_prefix"))
	_gpFixed = LineEdit.new()
	_gpFixed.text_changed.connect(_gpOnChanged)
	gpRoot.add_child(_gpFixed)

	gpRoot.add_child(_gpSectionLabel("tag_rule.prefix_table"))
	for gpCat in _gpCategories():
		var gpRow: HBoxContainer = HBoxContainer.new()
		var gpLbl: Label = Label.new()
		gpLbl.text = gpCat
		gpLbl.custom_minimum_size = Vector2(120.0, 0.0)
		gpRow.add_child(gpLbl)
		var gpEdit: LineEdit = LineEdit.new()
		gpEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gpEdit.text_changed.connect(_gpOnChanged)
		gpRow.add_child(gpEdit)
		gpRoot.add_child(gpRow)
		_gpPrefixEdits[gpCat] = gpEdit

	gpRoot.add_child(_gpSectionLabel("tag_rule.preview"))
	_gpPreview = Label.new()
	_gpPreview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpRoot.add_child(_gpPreview)

	_gpError = Label.new()
	_gpError.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gpError.add_theme_color_override("font_color", Color(0.72, 0.15, 0.15))
	gpRoot.add_child(_gpError)

	_gpRenumber = CheckBox.new()
	_gpRenumber.text = I18n.gpTr("tag_rule.renumber_now")
	gpRoot.add_child(_gpRenumber)

	confirmed.connect(_gpOnConfirmed)


# A small bold section caption. / 小号加粗的分区标题。
func _gpSectionLabel(gpKey: String) -> Label:
	var gpL: Label = Label.new()
	gpL.text = I18n.gpTr(gpKey)
	return gpL


# One labelled spin box appended to a row. / 往一行追加一个带标签的微调框。
func _gpSpin(gpRow: HBoxContainer, gpKey: String, gpMin: int, gpMax: int,
		gpStepVal: int) -> SpinBox:
	var gpLbl: Label = Label.new()
	gpLbl.text = I18n.gpTr(gpKey)
	gpRow.add_child(gpLbl)
	var gpSpin: SpinBox = SpinBox.new()
	gpSpin.min_value = float(gpMin)
	gpSpin.max_value = float(gpMax)
	gpSpin.step = float(gpStepVal)
	gpSpin.value_changed.connect(func(_gpV: float): _gpOnChanged(""))
	gpRow.add_child(gpSpin)
	return gpSpin


# Categories shown in the prefix table. / 前缀表中显示的类别。
func _gpCategories() -> Array[String]:
	var gpOut: Array[String] = []
	for gpRow in GPTagRuleService.gpPreviewRows(GPProjectTagRules.gpDefaultRules(), 1):
		gpOut.append(str(gpRow.get(GPTagRuleService.GP_ROW_CATEGORY, "")))
	if gpOut.is_empty():
		gpOut.append("general")
	return gpOut


# Show the dialog for a set of rules (a copy is edited, never the caller's object).
# 为一组规则显示对话框（编辑的是副本，绝不动调用方的对象）。
func gpShowRules(gpInRules: GPProjectTagRules, gpInInstanceCount: int = 0) -> void:
	gpRules = GPProjectTagRules.gpFromDict(gpInRules.gpToDict())
	gpInstanceCount = gpInInstanceCount
	_gpLoadIntoForm()
	popup_centered_ratio(0.5)


# Push the working copy into the widgets. / 把工作副本填入各控件。
func _gpLoadIntoForm() -> void:
	if gpRules == null:
		return
	var gpDef: GPTagRule = gpRules.gpDefault
	_gpTemplate.text = gpDef.gpTemplate
	_gpStart.value = float(gpDef.gpStart)
	_gpStep.value = float(gpDef.gpStep)
	_gpDigits.value = float(gpDef.gpDigits)
	_gpSource.select(int(gpDef.gpPrefixSource))
	_gpFixed.text = gpDef.gpFixedPrefix
	for gpCat in _gpPrefixEdits.keys():
		var gpEdit: LineEdit = _gpPrefixEdits[gpCat] as LineEdit
		gpEdit.text = str(gpDef.gpCategoryPrefixes.get(gpCat.to_lower(), ""))
	_gpRenumber.text = I18n.gpTr("tag_rule.renumber_now") % gpInstanceCount if gpInstanceCount > 0 else I18n.gpTr("tag_rule.renumber_none")


# Pull the widgets back into the working copy. / 把各控件读回工作副本。
func _gpReadForm() -> void:
	if gpRules == null:
		return
	var gpDef: GPTagRule = gpRules.gpDefault
	gpDef.gpTemplate = _gpTemplate.text
	gpDef.gpStart = int(_gpStart.value)
	gpDef.gpStep = int(_gpStep.value)
	gpDef.gpDigits = int(_gpDigits.value)
	gpDef.gpPrefixSource = _gpSource.get_selected_id() as GPTagRule.GPPrefixSource
	gpDef.gpFixedPrefix = _gpFixed.text
	gpDef.gpCategoryPrefixes = {}
	for gpCat in _gpPrefixEdits.keys():
		var gpEdit: LineEdit = _gpPrefixEdits[gpCat] as LineEdit
		if gpEdit.text.strip_edges() != "":
			gpDef.gpCategoryPrefixes[gpCat.to_lower()] = gpEdit.text.strip_edges()


# Re-validate and re-render on every change. / 每次改动都重新校验并重算预览。
func _gpOnChanged(_gpText: String) -> void:
	if gpRules == null or _gpError == null:
		return
	_gpReadForm()
	var gpRes: GPIOResult = gpRules.gpValidate()
	var gpOk: bool = gpRes.gpIsOk()
	if not gpOk:
		_gpError.text = I18n.gpTr(gpRes.gpMessageKey) + (" (%s)" % gpRes.gpDetail if gpRes.gpDetail != "" else "")
	else:
		_gpError.text = ""
	# The OK button is a child of the built-in HBox; disabling it is the honest way to say
	# "this configuration cannot be applied".
	# 「确定」按钮是内建 HBox 的子节点；禁用它是表达「此配置无法应用」的诚实方式。
	var gpBtn: Button = get_ok_button()
	if gpBtn != null:
		gpBtn.disabled = not gpOk
	_gpRenderPreview()


# The prefix-source choice decides whether the fixed-prefix field matters.
# 前缀来源的选择决定固定前缀字段是否有意义。
func _gpOnSourceChanged(_gpIdx: int) -> void:
	_gpOnChanged("")


# Render the live sample. / 渲染实时样例。
func _gpRenderPreview() -> void:
	if gpRules == null or _gpPreview == null:
		return
	var gpRows: Array[Dictionary] = GPTagRuleService.gpPreviewRows(gpRules, 1)
	if gpRows.is_empty():
		_gpPreview.text = "—"
		return
	var gpText: String = ""
	for gpRow in gpRows:
		if gpText != "":
			gpText += "   "
		gpText += "%s -> %s" % [
			str(gpRow.get(GPTagRuleService.GP_ROW_CATEGORY, "")),
			str(gpRow.get(GPTagRuleService.GP_ROW_SAMPLE, ""))]
	_gpPreview.text = gpText


# Confirm: hand the working copy to the host. / 确认：把工作副本交给宿主。
func _gpOnConfirmed() -> void:
	if gpRules == null:
		return
	_gpReadForm()
	if not gpRules.gpValidate().gpIsOk():
		return
	gpRulesApplied.emit(gpRules, _gpRenumber.button_pressed)
