class_name GPProjectStandardDialog
extends ConfirmationDialog
# Copyright © 2026 Jonson Wang
#
# B: the PROJECT STANDARD editor (ADR-36). One dialog, four tabs: numbering classes and their
# rules, the code tables, the classification map, and the portable package.
# B：**项目标准**编辑器（ADR-36）。一个对话框、四个页：编号类别与规则、代号表、分类映射、标准包。
#
# It edits a COPY. Nothing reaches the document until the user confirms — that is what makes
# Cancel a true no-op, and what lets the import preview show a diff before anything changes.
# 编辑的是**副本**。确认前不触碰文档 —— 这才使「取消」成为真空操作，也才使导入预览能在任何改动
# 之前先给出差异。
#
# Collect-on-switch / 切换即收集：
# each tab's controls write back into the working copy when the user switches class / table or
# confirms. Keeping every keystroke synchronised would rebuild widgets under the caret; that
# fights the user and loses focus mid-typing.
# 各页控件在用户切换类别 / 表或点确定时写回工作副本。逐键同步会在光标下重建控件 —— 那是在跟
# 用户较劲，还会在打字途中丢焦点。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Emitted on confirm: the edited standard and whether to renumber existing tags.
# 确认时发出：编辑后的标准，以及是否重排现有位号。
signal gpStandardApplied(gpStd: GPProjectStandard, gpRenumber: bool)

# Emitted when the user asks to renumber every sheet from tab order (ADR-38).
# 用户要求按标签顺序重编全部图纸编号时发出（ADR-38）。
signal gpSheetsRenumberRequested

# Shown when the package cannot be read (the dialog stays open so the user can retry).
# 标准包读不了时显示（对话框保持打开，便于重试）。
signal gpStatus(gpKey: String, gpArgs: Array)

var _gpStd: GPProjectStandard = null
var _gpCurrentClass: String = ""
var _gpCurrentTable: String = ""

# Working copy of the edited class's rule widgets. / 当前类别规则控件的引用。
var _gpTemplate: LineEdit = null
var _gpStart: SpinBox = null
var _gpStep: SpinBox = null
var _gpDigits: SpinBox = null
var _gpFixed: LineEdit = null
var _gpSeparator: LineEdit = null
var _gpSegmentRows: Array[Dictionary] = []

var _gpClassName: OptionButton = null
var _gpEnabled: CheckBox = null
var _gpRuleBox: VBoxContainer = null
var _gpPreviewLabel: Label = null

var _gpTablePick: OptionButton = null
var _gpTableRows: VBoxContainer = null
var _gpTableEdits: Array[Dictionary] = []
# Default tables first, then tables referenced by user-created fields / already stored.
# 先默认表，再是用户新建字段引用 / 已存储的表。
var _gpTableIds: Array[String] = []

var _gpClassifyBox: VBoxContainer = null
var _gpClassifyRows: Array[Dictionary] = []
var _gpClassifyDirty: bool = false

var _gpDiffText: TextEdit = null
var _gpRenumber: CheckBox = null
var _gpInfoEdits: Dictionary = {}
var _gpNoTemplate: LineEdit = null
var _gpNoStart: SpinBox = null
var _gpNoStep: SpinBox = null
var _gpNoPreview: Label = null
var _gpSheetRenumber: CheckBox = null

# Last size we applied ourselves, so a MANUAL resize is respected (we stop auto-fitting once
# the user has taken over).
# 上一次由我们设置的尺寸；用户手动改过之后就不再自动贴合。
var _gpLastFit: Vector2i = Vector2i.ZERO


func _ready() -> void:
	title = I18n.gpTr("standard.title")
	ok_button_text = I18n.gpTr("dialog.ok")
	cancel_button_text = I18n.gpTr("dialog.cancel")
	confirmed.connect(_gpOnConfirmed)
	# A modest floor, NOT a screen-sized default. The old code asked for 72% of the screen and
	# an 860x620 minimum, so a project with three code rows got a mostly-empty window.
	# 只要一个很小的下限，**不要**整屏大小的默认值。旧代码要 72% 屏幕、最小 860×620。
	min_size = Vector2i(560, 360)
	# ⚠️ `wrap_controls` (ON by default for AcceptDialog on some builds) makes the window follow
	# the CONTENT's minimum size. With expand-flagged children inside the tabs that minimum can
	# exceed the screen, which is exactly how the dialog ended up full-height. Turning it off
	# means OUR size wins; the tabs' own scroll areas handle overflow.
	# ⚠️ `wrap_controls`（AcceptDialog 在某些构建上默认开启）会让窗口跟着**内容**最小尺寸长。
	# 标签页里有 expand 子控件时，那个最小尺寸可能超过屏幕 —— 对话框正是这样变成满屏高的。
	# 关掉它意味着**我们给的尺寸**说了算；内容溢出由各页自己的滚动区处理。
	wrap_controls = false
	unresizable = false


# Show the dialog for a standard (a deep copy is edited, never the caller's object).
# 为某套标准显示对话框（编辑深拷贝，绝不动调用方的对象）。
func gpShowStandard(gpIn: GPProjectStandard) -> void:
	_gpStd = gpIn.gpClone() if gpIn != null else GPProjectStandard.gpDefaultStandard()
	_gpCurrentClass = ""
	_gpCurrentTable = ""
	_gpBuild()
	_gpRefreshAll()
	_gpRefreshProjectInfo()
	# Size to CONTENT and cap by the screen: small projects get a small window, big ones stop at
	# 70% of the usable area instead of filling the screen. `wrap_controls` is OFF (see _ready) —
	# with it on, expand-flagged children made the window grow to the screen height and IGNORE
	# this size entirely, which is exactly what the user saw.
	# 按**内容**定尺寸，并按屏幕封顶：小工程得小窗，大工程停在可用面积的 70%，而不是占满屏幕。
	# `wrap_controls` 已关（见 _ready）—— 开着时，带 expand 的子控件会让窗口长到屏幕高，并**完全忽略**
	# 这里给的尺寸，这正是用户看到的现象。
	var gpHost: Window = null
	if get_parent() != null:
		gpHost = get_parent().get_window()
	GPWindowFit.gpPopupContentFitted(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL)
	_gpLastFit = size


# ============================ build / 构建 ============================

func _gpBuild() -> void:
	for gpChild in get_children():
		if gpChild is MarginContainer:
			gpChild.queue_free()
	var gpMargin: MarginContainer = MarginContainer.new()
	gpMargin.add_theme_constant_override("margin_left", 8)
	gpMargin.add_theme_constant_override("margin_right", 8)
	gpMargin.add_theme_constant_override("margin_top", 6)
	gpMargin.add_theme_constant_override("margin_bottom", 6)
	add_child(gpMargin)
	var gpTabs: TabContainer = TabContainer.new()
	gpTabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpMargin.add_child(gpTabs)
	_gpBuildClassesTab(gpTabs)
	_gpBuildProjectTab(gpTabs)
	_gpBuildTablesTab(gpTabs)
	_gpBuildClassifyTab(gpTabs)
	_gpBuildPackageTab(gpTabs)
	# A field added on the Classes tab can introduce a NEW code-table id; refresh the table
	# picker when the user opens the Tables tab instead of requiring a dialog reopen.
	# 在「编号类别」页新增字段可能引入新的代号表 id；切到「代号表」页时刷新选择器，
	# 不必关闭再打开对话框。
	gpTabs.tab_changed.connect(func(gpIdx: int) -> void:
		if gpIdx == 2:
			_gpRefreshTablePicker())


func _gpBuildClassesTab(gpTabs: TabContainer) -> void:
	var gpPage: VBoxContainer = VBoxContainer.new()
	gpPage.name = I18n.gpTr("standard.tab_classes")
	gpPage.add_theme_constant_override("separation", 8)
	gpTabs.add_child(gpPage)
	var gpTop: HBoxContainer = HBoxContainer.new()
	gpTop.add_theme_constant_override("separation", 10)
	gpPage.add_child(gpTop)
	gpTop.add_child(_gpLabel("standard.class", true))
	_gpClassName = OptionButton.new()
	for gpClass in GPProjectStandard.GP_CLASS_IDS:
		_gpClassName.add_item(GPProjectStandard.gpClassLabel(gpClass))
	gpTop.add_child(_gpClassName)
	_gpClassName.item_selected.connect(_gpOnClassPicked)
	_gpEnabled = CheckBox.new()
	_gpEnabled.text = I18n.gpTr("standard.enabled")
	gpTop.add_child(_gpEnabled)
	_gpEnabled.toggled.connect(_gpOnEnabledToggled)
	# The segment editor is a long row of small fields; let it scroll sideways instead of
	# forcing the whole window wider than the screen.
	# 分段编辑器是一长排小控件；让它横向滚动，而不是把整个窗口撑到屏幕外。
	var gpRuleScroll: ScrollContainer = ScrollContainer.new()
	gpRuleScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpRuleScroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	gpPage.add_child(gpRuleScroll)
	_gpRuleBox = VBoxContainer.new()
	_gpRuleBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpRuleScroll.add_child(_gpRuleBox)
	# The preview sits on its OWN row and is given a real minimum width. An autowrap Label in a
	# horizontal container reports min width 1 and min height "everything wrapped at 1px" — the
	# label alone was reporting 1323px of minimum height, which is how the whole dialog ended up
	# full-height regardless of the size we asked for.
	# 预览独占一行，并给一个真实的最小宽度。autowrap 的 Label 放在水平容器里时，最小宽度报 1、
	# 最小高度报「按 1px 宽折行后的全部高度」—— 这一个标签就报了 1323px，于是无论我们给什么尺寸，
	# 整个对话框都被顶成全屏高。
	var gpBottom: VBoxContainer = VBoxContainer.new()
	gpPage.add_child(gpBottom)
	gpBottom.add_child(_gpLabel("standard.preview", true))
	_gpPreviewLabel = Label.new()
	_gpPreviewLabel.custom_minimum_size = Vector2(320, 0)
	_gpPreviewLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gpPreviewLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpBottom.add_child(_gpPreviewLabel)


# Project information + drawing-number rule (ADR-38). Filled ONCE per project; every sheet's
# title block inherits it (empty fields only).
# 项目信息 + 图纸编号规则（ADR-38）。一个工程填**一次**；每张图纸的标题栏继承它（仅空缺字段）。
func _gpBuildProjectTab(gpTabs: TabContainer) -> void:
	var gpPage: VBoxContainer = VBoxContainer.new()
	gpPage.name = I18n.gpTr("standard.tab_project")
	gpPage.add_theme_constant_override("separation", 6)
	gpTabs.add_child(gpPage)
	var gpGrid: GridContainer = GridContainer.new()
	gpGrid.columns = 2
	gpPage.add_child(gpGrid)
	for gpField in [["owner", "standard.info.owner"], ["project_name", "standard.info.project"],
			["project_no", "standard.info.project_no"], ["stage", "standard.info.stage"],
			["company", "standard.info.company"], ["designed", "standard.info.designed"],
			["checked", "standard.info.checked"], ["approved", "standard.info.approved"]]:
		gpGrid.add_child(_gpLabel(str(gpField[1]), false))
		var gpEdit: LineEdit = LineEdit.new()
		gpEdit.text = str(_gpStd.gpInfo(str(gpField[0]))) if _gpStd != null else ""
		gpEdit.custom_minimum_size = Vector2(280, 0)
		gpGrid.add_child(gpEdit)
		_gpInfoEdits[str(gpField[0])] = gpEdit
	# Drawing-number rule / 图纸编号规则
	gpPage.add_child(_gpLabel("standard.sheet_no_rule", false))
	var gpNoRow: HBoxContainer = HBoxContainer.new()
	gpNoRow.add_theme_constant_override("separation", 8)
	gpPage.add_child(gpNoRow)
	gpNoRow.add_child(_gpLabel("tag_rule.template", false))
	_gpNoTemplate = LineEdit.new()
	_gpNoTemplate.custom_minimum_size = Vector2(260, 0)
	_gpNoTemplate.text = str((_gpStd.gpSheetNoRule as Dictionary).get("template",
		"{project_no}-{seq:3}")) if _gpStd != null else "{project_no}-{seq:3}"
	_gpNoTemplate.text_changed.connect(func(_gpText: String) -> void: _gpRefreshSheetNoPreview())
	gpNoRow.add_child(_gpNoTemplate)
	gpNoRow.add_child(_gpLabel("tag_rule.start", false))
	_gpNoStart = _gpSpin(int((_gpStd.gpSheetNoRule as Dictionary).get("start", 0))
		if _gpStd != null else 0, 0)
	gpNoRow.add_child(_gpNoStart)
	gpNoRow.add_child(_gpLabel("tag_rule.step", false))
	_gpNoStep = _gpSpin(int((_gpStd.gpSheetNoRule as Dictionary).get("step", 1))
		if _gpStd != null else 1, 1)
	gpNoRow.add_child(_gpNoStep)
	_gpNoPreview = Label.new()
	_gpNoPreview.add_theme_font_size_override("font_size", 12)
	_gpNoPreview.custom_minimum_size = Vector2(320, 0)
	gpPage.add_child(_gpNoPreview)
	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("standard.info.hint")
	gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpHint.custom_minimum_size = Vector2(320, 0)
	gpHint.add_theme_font_size_override("font_size", 12)
	gpHint.modulate = Color(1, 1, 1, 0.7)
	gpPage.add_child(gpHint)
	_gpSheetRenumber = CheckBox.new()
	_gpSheetRenumber.text = I18n.gpTr("standard.sheet_renumber")
	gpPage.add_child(_gpSheetRenumber)
	_gpRefreshSheetNoPreview()


func _gpRefreshSheetNoPreview() -> void:
	if _gpNoPreview == null or _gpStd == null:
		return
	var gpProbe: GPProjectStandard = _gpStd.gpClone()
	_gpCollectProjectInfo(gpProbe)
	var gpBase: int = int(_gpNoStart.value) if _gpNoStart != null else 0
	_gpNoPreview.text = I18n.gpTr("standard.sheet_no_preview") % [
		gpProbe.gpSheetNumberFor(gpBase + 1), gpProbe.gpSheetNumberFor(gpBase + 2)]


# Read the project tab into a standard (defaults to the working copy).
# 把项目信息页读进某套标准（默认读进工作副本）。
func _gpCollectProjectInfo(gpTarget: GPProjectStandard = null) -> void:
	var gpStd: GPProjectStandard = gpTarget if gpTarget != null else _gpStd
	if gpStd == null:
		return
	for gpKeyRaw in _gpInfoEdits.keys():
		var gpEdit: LineEdit = _gpInfoEdits[gpKeyRaw] as LineEdit
		if gpEdit != null:
			gpStd.gpProjectInfo[str(gpKeyRaw)] = gpEdit.text.strip_edges()
	if _gpNoTemplate != null:
		gpStd.gpSheetNoRule["template"] = _gpNoTemplate.text.strip_edges()
	if _gpNoStart != null:
		gpStd.gpSheetNoRule["start"] = int(_gpNoStart.value)
	if _gpNoStep != null:
		gpStd.gpSheetNoRule["step"] = int(_gpNoStep.value)


# Push the working copy's project info into the project tab's widgets (after an import).
# 把工作副本的项目信息填进项目信息页的控件（导入之后用）。
func _gpRefreshProjectInfo() -> void:
	if _gpStd == null:
		return
	for gpKeyRaw in _gpInfoEdits.keys():
		var gpEdit: LineEdit = _gpInfoEdits[gpKeyRaw] as LineEdit
		if gpEdit != null:
			gpEdit.text = _gpStd.gpInfo(str(gpKeyRaw))
	if _gpNoTemplate != null:
		_gpNoTemplate.text = str((_gpStd.gpSheetNoRule as Dictionary).get("template",
			"{project_no}-{seq:3}"))
	if _gpNoStart != null:
		_gpNoStart.value = int((_gpStd.gpSheetNoRule as Dictionary).get("start", 0))
	if _gpNoStep != null:
		_gpNoStep.value = int((_gpStd.gpSheetNoRule as Dictionary).get("step", 1))
	_gpRefreshSheetNoPreview()


func _gpBuildTablesTab(gpTabs: TabContainer) -> void:
	var gpPage: VBoxContainer = VBoxContainer.new()
	gpPage.name = I18n.gpTr("standard.tab_tables")
	gpPage.add_theme_constant_override("separation", 8)
	gpTabs.add_child(gpPage)
	var gpTop: HBoxContainer = HBoxContainer.new()
	gpPage.add_child(gpTop)
	_gpTablePick = OptionButton.new()
	gpTop.add_child(_gpTablePick)
	_gpFillTablePicker()
	_gpTablePick.item_selected.connect(_gpOnTablePicked)
	var gpAdd: Button = Button.new()
	gpAdd.text = I18n.gpTr("standard.add_row")
	gpAdd.pressed.connect(_gpOnAddTableRow)
	gpTop.add_child(gpAdd)
	# One click fills an EMPTY table with the factory rows — the migration covers old projects,
	# but a user who cleared a table needs a way back that is not hand-typing four codes.
	# 一键把**空表**填上出厂行 —— 迁移覆盖旧工程，而「自己清空过表」的用户也要有一条不必手打
	# 四个代号的回头路。
	var gpSeed: Button = Button.new()
	gpSeed.text = I18n.gpTr("standard.seed")
	gpSeed.pressed.connect(_gpOnSeedTable)
	gpTop.add_child(gpSeed)
	var gpScroll: ScrollContainer = ScrollContainer.new()
	gpScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpPage.add_child(gpScroll)
	_gpTableRows = VBoxContainer.new()
	_gpTableRows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpScroll.add_child(_gpTableRows)


func _gpBuildClassifyTab(gpTabs: TabContainer) -> void:
	var gpPage: VBoxContainer = VBoxContainer.new()
	gpPage.name = I18n.gpTr("standard.tab_classify")
	gpTabs.add_child(gpPage)
	var gpScroll: ScrollContainer = ScrollContainer.new()
	gpScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpScroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpPage.add_child(gpScroll)
	_gpClassifyBox = VBoxContainer.new()
	_gpClassifyBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpScroll.add_child(_gpClassifyBox)


func _gpBuildPackageTab(gpTabs: TabContainer) -> void:
	var gpPage: VBoxContainer = VBoxContainer.new()
	gpPage.name = I18n.gpTr("standard.tab_package")
	gpPage.add_theme_constant_override("separation", 8)
	gpTabs.add_child(gpPage)
	var gpTop: HBoxContainer = HBoxContainer.new()
	gpTop.add_theme_constant_override("separation", 12)
	gpPage.add_child(gpTop)
	var gpExport: Button = Button.new()
	gpExport.text = I18n.gpTr("standard.export")
	gpExport.pressed.connect(_gpOnExport)
	gpTop.add_child(gpExport)
	var gpImport: Button = Button.new()
	gpImport.text = I18n.gpTr("standard.import")
	gpImport.pressed.connect(_gpOnImport)
	gpTop.add_child(gpImport)
	_gpRenumber = CheckBox.new()
	_gpRenumber.text = I18n.gpTr("standard.renumber")
	gpPage.add_child(_gpRenumber)
	gpPage.add_child(_gpLabel("standard.diff_title", false))
	_gpDiffText = TextEdit.new()
	_gpDiffText.editable = false
	_gpDiffText.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpPage.add_child(_gpDiffText)


# ============================ classes tab / 类别页 ============================

func _gpOnClassPicked(_gpIdx: int) -> void:
	_gpCollectRule()
	_gpCurrentClass = GPProjectStandard.GP_CLASS_IDS[_gpClassName.selected]
	_gpRebuildRule()


func _gpOnEnabledToggled(gpOn: bool) -> void:
	if _gpCurrentClass != "":
		_gpStd.gpSetEnabled(_gpCurrentClass, gpOn)


func _gpRebuildRule() -> void:
	for gpChild in _gpRuleBox.get_children():
		_gpRuleBox.remove_child(gpChild)
		gpChild.queue_free()
	_gpTemplate = null
	_gpSegmentRows = []
	_gpSeparator = null
	if _gpCurrentClass == "":
		return
	_gpEnabled.set_pressed_no_signal(_gpStd.gpEnabled(_gpCurrentClass))
	var gpRules: GPProjectTagRules = _gpStd.gpRulesOf(_gpCurrentClass)
	var gpRule: GPTagRule = gpRules.gpDefault
	if gpRule.gpUsesSegments():
		_gpBuildSegmentEditor(gpRule)
	else:
		_gpBuildTemplateEditor(gpRule)
	_gpRefreshPreview()
	_gpFitToContent()


func _gpBuildTemplateEditor(gpRule: GPTagRule) -> void:
	var gpGrid: GridContainer = GridContainer.new()
	gpGrid.columns = 2
	_gpRuleBox.add_child(gpGrid)
	gpGrid.add_child(_gpLabel("tag_rule.template", false))
	_gpTemplate = LineEdit.new()
	_gpTemplate.text = gpRule.gpTemplate
	gpGrid.add_child(_gpTemplate)
	gpGrid.add_child(_gpLabel("tag_rule.start", false))
	_gpStart = _gpSpin(gpRule.gpStart, 1)
	gpGrid.add_child(_gpStart)
	gpGrid.add_child(_gpLabel("tag_rule.step", false))
	_gpStep = _gpSpin(gpRule.gpStep, 1)
	gpGrid.add_child(_gpStep)
	gpGrid.add_child(_gpLabel("tag_rule.digits", false))
	_gpDigits = _gpSpin(gpRule.gpDigits, 0, 8)
	gpGrid.add_child(_gpDigits)
	gpGrid.add_child(_gpLabel("tag_rule.fixed_prefix", false))
	_gpFixed = LineEdit.new()
	_gpFixed.text = gpRule.gpFixedPrefix
	gpGrid.add_child(_gpFixed)


func _gpBuildSegmentEditor(gpRule: GPTagRule) -> void:
	var gpSepRow: HBoxContainer = HBoxContainer.new()
	_gpRuleBox.add_child(gpSepRow)
	gpSepRow.add_child(_gpLabel("standard.separator", false))
	_gpSeparator = LineEdit.new()
	_gpSeparator.text = gpRule.gpSeparator
	_gpSeparator.custom_minimum_size = Vector2(60, 0)
	gpSepRow.add_child(_gpSeparator)
	var gpAddBtn: Button = Button.new()
	gpAddBtn.text = I18n.gpTr("standard.add_segment")
	gpAddBtn.pressed.connect(_gpOnAddSegment)
	gpSepRow.add_child(gpAddBtn)
	# A legend line, NOT a header row: control widths drift by a few pixels (an OptionButton's
	# natural width, a SpinBox's arrows), so a fake header sits visibly misaligned. A one-line
	# legend says what the nine fields are without pretending to line up.
	# 用一行**图例**而不是表头：控件宽度会飘几像素（OptionButton 的自然宽度、SpinBox 的箭头），
	# 假表头会明显错位。一行图例说明这九个字段是什么，且不假装对齐。
	var gpLegend: Label = Label.new()
	gpLegend.text = "列：%s · %s · %s · %s · %s · %s · %s · %s · %s" % [
		I18n.gpTr("segment.key"), I18n.gpTr("segment.label"), I18n.gpTr("segment.source"),
		I18n.gpTr("segment.attr"), I18n.gpTr("segment.table"), I18n.gpTr("segment.width"),
		I18n.gpTr("segment.min"), I18n.gpTr("segment.max"), I18n.gpTr("segment.fallback")]
	gpLegend.add_theme_font_size_override("font_size", 11)
	gpLegend.modulate = Color(1, 1, 1, 0.55)
	_gpRuleBox.add_child(gpLegend)
	var gpExample: Label = Label.new()
	gpExample.text = I18n.gpTr("standard.segment_example")
	gpExample.add_theme_font_size_override("font_size", 11)
	gpExample.modulate = Color(0.75, 0.85, 1.0, 0.8)
	gpExample.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpExample.custom_minimum_size = Vector2(420, 0)
	_gpRuleBox.add_child(gpExample)
	var gpSeqCount: int = 0
	for gpSegRaw in gpRule.gpSegments:
		var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
		if gpSeg != null and gpSeg.gpSource == GPTagSegment.GPSource.GP_SEQ:
			gpSeqCount += 1
		_gpAddSegmentRow(gpSeg)
	if gpSeqCount > 1:
		var gpWarn: Label = Label.new()
		gpWarn.text = I18n.gpTr("standard.multi_seq_warning")
		gpWarn.modulate = Color(0.95, 0.55, 0.45)
		gpWarn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gpWarn.custom_minimum_size = Vector2(420, 0)
		_gpRuleBox.add_child(gpWarn)


func _gpAddSegmentRow(gpSeg: GPTagSegment) -> void:
	var gpRow: HBoxContainer = HBoxContainer.new()
	_gpRuleBox.add_child(gpRow)
	var gpEntry: Dictionary = {"row": gpRow}
	var gpKey: LineEdit = _gpSmallEdit(gpRow, gpSeg.gpKey, 90,
		I18n.gpTr("standard.seg_key_ph"))
	gpEntry["key"] = gpKey
	var gpLabel: LineEdit = _gpSmallEdit(gpRow, gpSeg.gpLabel, 90,
		I18n.gpTr("standard.seg_name_ph"))
	gpEntry["label"] = gpLabel
	var gpSource: OptionButton = OptionButton.new()
	# Widths are FIXED so the header row above lines up with the controls below it.
	# 宽度固定，使上方表头与下方控件对齐。
	gpSource.custom_minimum_size = Vector2(104, 0)
	gpSource.add_item(I18n.gpTr("segment.src_fixed"))
	gpSource.add_item(I18n.gpTr("segment.src_seq"))
	gpSource.add_item(I18n.gpTr("segment.src_attr"))
	gpSource.add_item(I18n.gpTr("segment.src_digits"))
	gpSource.add_item(I18n.gpTr("segment.src_code"))
	gpSource.select(int(gpSeg.gpSource))
	gpRow.add_child(gpSource)
	gpEntry["source"] = gpSource
	gpEntry["attr"] = _gpSmallEdit(gpRow, gpSeg.gpAttr, 80,
		I18n.gpTr("standard.seg_attr_ph"))
	gpEntry["table"] = _gpSmallEdit(gpRow, gpSeg.gpTable, 80,
		I18n.gpTr("standard.seg_table_ph"))
	gpEntry["width"] = _gpSpin(gpSeg.gpWidth, 0, 12, 52)
	gpRow.add_child(gpEntry["width"])
	gpEntry["min"] = _gpSpin(gpSeg.gpMin, 0, 12, 52)
	gpRow.add_child(gpEntry["min"])
	gpEntry["max"] = _gpSpin(gpSeg.gpMax, 0, 12, 52)
	gpRow.add_child(gpEntry["max"])
	gpEntry["fallback"] = _gpSmallEdit(gpRow, gpSeg.gpFallback, 84,
		I18n.gpTr("standard.seg_fallback_ph"))
	var gpDel: Button = Button.new()
	gpDel.text = "×"
	gpDel.pressed.connect(func() -> void:
		_gpSegmentRows.erase(gpEntry)
		gpRow.queue_free())
	gpRow.add_child(gpDel)
	_gpSegmentRows.append(gpEntry)


func _gpOnAddSegment() -> void:
	_gpCollectRule()
	# A new FIELD is an attribute segment, not another sequence: the latter silently adds a
	# `0000` to every number and has no input in the line-attribute panel (the exact symptom
	# reported as "I added 子项号 but got an extra 管线号").
	# 新字段默认是**属性段**，不是再加一个序号段：后者会给每个号多出 `0000`，且属性面板
	# 没有可填写入口（正是用户报告的「加子项号却多出一个管线号」）。
	var gpUsed: Dictionary = {}
	if _gpCurrentClass != "" and _gpStd != null:
		for gpSegRaw in _gpStd.gpRulesOf(_gpCurrentClass).gpDefault.gpSegments:
			var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
			if gpSeg != null:
				gpUsed[gpSeg.gpKey] = true
	var gpN: int = 1
	while gpUsed.has("field%d" % gpN):
		gpN += 1
	var gpNew: GPTagSegment = GPTagSegment.gpAttrText(
		"field%d" % gpN, "新字段", "field%d" % gpN, 1, 8,
		GPTagSegment.GPCharset.GP_ALNUM, "")
	_gpAddSegmentRow(gpNew)


# Read the class tab's widgets back into the working copy.
# 把类别页控件读回工作副本。
func _gpCollectRule() -> void:
	if _gpCurrentClass == "" or _gpStd == null:
		return
	var gpRules: GPProjectTagRules = _gpStd.gpRulesOf(_gpCurrentClass)
	var gpRule: GPTagRule = gpRules.gpDefault
	if _gpSegmentRows.is_empty():
		if _gpTemplate != null:
			gpRule.gpTemplate = _gpTemplate.text.strip_edges()
		if _gpStart != null:
			gpRule.gpStart = int(_gpStart.value)
		if _gpStep != null:
			gpRule.gpStep = maxi(1, int(_gpStep.value))
		if _gpDigits != null:
			gpRule.gpDigits = int(_gpDigits.value)
		if _gpFixed != null:
			gpRule.gpFixedPrefix = _gpFixed.text.strip_edges()
		return
	if _gpSeparator != null:
		gpRule.gpSeparator = _gpSeparator.text.strip_edges()
	if gpRule.gpSeparator == "":
		gpRule.gpSeparator = "-"
	var gpSegs: Array[GPTagSegment] = []
	for gpEntry in _gpSegmentRows:
		var gpSeg: GPTagSegment = GPTagSegment.new()
		gpSeg.gpKey = (gpEntry["key"] as LineEdit).text.strip_edges()
		gpSeg.gpLabel = (gpEntry["label"] as LineEdit).text.strip_edges()
		gpSeg.gpSource = (gpEntry["source"] as OptionButton).selected as GPTagSegment.GPSource
		gpSeg.gpAttr = (gpEntry["attr"] as LineEdit).text.strip_edges()
		gpSeg.gpTable = (gpEntry["table"] as LineEdit).text.strip_edges()
		gpSeg.gpWidth = int((gpEntry["width"] as SpinBox).value)
		gpSeg.gpMin = int((gpEntry["min"] as SpinBox).value)
		gpSeg.gpMax = int((gpEntry["max"] as SpinBox).value)
		gpSeg.gpFallback = (gpEntry["fallback"] as LineEdit).text.strip_edges()
		if gpSeg.gpSource == GPTagSegment.GPSource.GP_SEQ:
			gpSeg.gpCharset = GPTagSegment.GPCharset.GP_DIGIT
		elif gpSeg.gpSource == GPTagSegment.GPSource.GP_ATTR_DIGITS:
			gpSeg.gpCharset = GPTagSegment.GPCharset.GP_DIGIT
		else:
			gpSeg.gpCharset = GPTagSegment.GPCharset.GP_ALNUM
		gpSegs.append(gpSeg)
	gpRule.gpSegments = gpSegs


# Fit the window to the CURRENT page's content, while the user has not resized it by hand.
# 在用户尚未手动改尺寸时，把窗口贴合**当前页**的内容。
func _gpFitToContent() -> void:
	if not visible:
		return
	if _gpLastFit != Vector2i.ZERO and size != _gpLastFit:
		# The user dragged the window; their size wins from now on.
		# 用户拖过窗口；此后以用户的尺寸为准。
		return
	reset_size()
	var gpArea: Vector2i = GPWindowFit.gpCeilingSize(self, _gpHostWindow())
	var gpWant: Vector2i = GPWindowFit.gpContentSize(
		GPWindowFit.gpToWindowUnits(self, get_contents_minimum_size()), gpArea,
		GP_MIN_LOGICAL, GP_MAX_LOGICAL)
	_gpLastFit = gpWant
	size = gpWant


# ============================ tables tab / 代号表页 ============================

# Fill the picker from the live standard (built-ins + fields' tables + stored tables).
# 从实时标准填充下拉（内置 + 字段引用的表 + 已存储表）。
func _gpFillTablePicker() -> void:
	if _gpTablePick == null:
		return
	_gpTablePick.clear()
	_gpTableIds = _gpStd.gpTableIds() if _gpStd != null else GPProjectStandard.GP_TABLE_IDS.duplicate()
	for gpTable in _gpTableIds:
		var gpTableText: String = str(GPProjectStandard.GP_TABLE_LABELS.get(gpTable, ""))
		if gpTableText == "":
			gpTableText = I18n.gpTr("standard.table_custom")
		_gpTablePick.add_item("%s · %s" % [gpTable, gpTableText])


# Built-in tables get their own example / placeholders; a user-created table gets a neutral one.
# 内置表使用各自的示例与占位；用户新建的表使用中性占位，不再冒充管径/介质。
func _gpTableIsBuiltIn() -> bool:
	return GPProjectStandard.GP_TABLE_IDS.has(_gpCurrentTable)


func _gpTableCodePlaceholder() -> String:
	if not _gpTableIsBuiltIn():
		return I18n.gpTr("standard.code_ph_custom")
	match _gpCurrentTable:
		GPProjectStandard.GP_TABLE_DN:
			return "代号，如 50（写入编号/匹配用）"
		GPProjectStandard.GP_TABLE_MEDIUM:
			return "代号，如 CWR"
		GPProjectStandard.GP_TABLE_MATERIAL:
			return "代号，如 A1A"
		GPProjectStandard.GP_TABLE_INSULATION:
			return "代号，如 P"
		GPProjectStandard.GP_TABLE_DISCIPLINE:
			return "代号，如 PI"
		GPProjectStandard.GP_TABLE_AREA:
			return "代号，如 A1"
	return I18n.gpTr("standard.code_ph_custom")


func _gpTableLabelPlaceholder() -> String:
	if not _gpTableIsBuiltIn():
		return I18n.gpTr("standard.label_ph_custom")
	match _gpCurrentTable:
		GPProjectStandard.GP_TABLE_DN:
			return "名称，如 DN50（只显示）"
		GPProjectStandard.GP_TABLE_MEDIUM:
			return "名称，如 循环冷却水"
		GPProjectStandard.GP_TABLE_MATERIAL:
			return "名称，如 碳钢 20#"
		GPProjectStandard.GP_TABLE_INSULATION:
			return "名称，如 保冷"
		GPProjectStandard.GP_TABLE_DISCIPLINE:
			return "名称，如 工艺"
		GPProjectStandard.GP_TABLE_AREA:
			return "名称，如 一区"
	return I18n.gpTr("standard.label_ph_custom")


func _gpTableAliasesPlaceholder() -> String:
	return I18n.gpTr("standard.aliases_ph")


func _gpTableExampleText() -> String:
	if not _gpTableIsBuiltIn():
		return I18n.gpTr("standard.table_example_custom")
	match _gpCurrentTable:
		GPProjectStandard.GP_TABLE_DN:
			return "示例：代号 50｜名称 DN50｜别名 DN50,50（代号写进编号/匹配，名称只显示）"
		GPProjectStandard.GP_TABLE_MEDIUM:
			return "示例：代号 CWR｜名称 循环冷却水｜别名 Cooling Water Return"
		GPProjectStandard.GP_TABLE_MATERIAL:
			return "示例：代号 A1A｜名称 碳钢 20#｜别名 碳钢, Carbon Steel"
		GPProjectStandard.GP_TABLE_INSULATION:
			return "示例：代号 P｜名称 保冷｜别名 Cold Insulation"
		GPProjectStandard.GP_TABLE_DISCIPLINE:
			return "示例：代号 PI｜名称 工艺｜别名 Process"
		GPProjectStandard.GP_TABLE_AREA:
			return "示例：代号 A1｜名称 一区｜别名 Area 1"
	return I18n.gpTr("standard.table_example_custom")


func _gpOnTablePicked(_gpIdx: int) -> void:
	_gpCollectTable()
	_gpCurrentTable = _gpTableIds[_gpTablePick.selected] if _gpTablePick.selected < _gpTableIds.size() else ""
	_gpRebuildTable()


func _gpRebuildTable() -> void:
	for gpChild in _gpTableRows.get_children():
		_gpTableRows.remove_child(gpChild)
		gpChild.queue_free()
	_gpTableEdits = []
	if _gpCurrentTable == "":
		return
	var gpLegend: Label = Label.new()
	gpLegend.text = "列：%s · %s · %s" % [I18n.gpTr("table.code"), I18n.gpTr("table.label"),
		I18n.gpTr("table.aliases")]
	gpLegend.add_theme_font_size_override("font_size", 11)
	gpLegend.modulate = Color(1, 1, 1, 0.55)
	_gpTableRows.add_child(gpLegend)
	var gpExample: Label = Label.new()
	gpExample.text = _gpTableExampleText()
	gpExample.add_theme_font_size_override("font_size", 11)
	gpExample.modulate = Color(0.75, 0.85, 1.0, 0.8)
	gpExample.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpExample.custom_minimum_size = Vector2(360, 0)
	_gpTableRows.add_child(gpExample)
	for gpRowRaw in _gpStd.gpCodeTable(_gpCurrentTable):
		if gpRowRaw is Dictionary:
			_gpAddTableRow(gpRowRaw as Dictionary)
	_gpFitToContent()


func _gpAddTableRow(gpRow: Dictionary) -> void:
	var gpBox: HBoxContainer = HBoxContainer.new()
	_gpTableRows.add_child(gpBox)
	var gpEntry: Dictionary = {"row": gpBox}
	gpEntry["code"] = _gpSmallEdit(gpBox, str(gpRow.get("code", "")), 90,
		_gpTableCodePlaceholder())
	gpEntry["label"] = _gpSmallEdit(gpBox, str(gpRow.get("label", "")), 160,
		_gpTableLabelPlaceholder())
	var gpAliases: Array = gpRow.get("aliases", []) as Array
	gpEntry["aliases"] = _gpSmallEdit(gpBox, ", ".join(gpAliases), 220,
		_gpTableAliasesPlaceholder())
	var gpDel: Button = Button.new()
	gpDel.text = "×"
	gpDel.pressed.connect(func() -> void:
		_gpTableEdits.erase(gpEntry)
		gpBox.queue_free())
	gpBox.add_child(gpDel)
	_gpTableEdits.append(gpEntry)


# Append factory rows that are missing from the current table (never overwrites user rows).
# 把当前表里**缺少**的出厂行补上（绝不覆盖用户已有的行）。
func _gpOnSeedTable() -> void:
	_gpCollectTable()
	if _gpCurrentTable == "":
		return
	var gpRows: Array = _gpStd.gpCodeTable(_gpCurrentTable).duplicate(true)
	var gpHave: Dictionary = {}
	for gpRowRaw in gpRows:
		if gpRowRaw is Dictionary:
			gpHave[str((gpRowRaw as Dictionary).get("code", "")).to_upper()] = true
	for gpRowRaw in GPProjectStandard.gpFactoryTable(_gpCurrentTable):
		if not (gpRowRaw is Dictionary):
			continue
		var gpCode: String = str((gpRowRaw as Dictionary).get("code", "")).to_upper()
		if gpCode != "" and not gpHave.has(gpCode):
			gpRows.append((gpRowRaw as Dictionary).duplicate(true))
			gpHave[gpCode] = true
	_gpStd.gpSetCodeTable(_gpCurrentTable, gpRows)
	_gpRebuildTable()


func _gpOnAddTableRow() -> void:
	_gpCollectTable()
	if _gpCurrentTable == "":
		return
	_gpAddTableRow({"code": "", "label": "", "aliases": []})


func _gpCollectTable() -> void:
	if _gpCurrentTable == "" or _gpStd == null:
		return
	var gpRows: Array = []
	for gpEntry in _gpTableEdits:
		var gpCode: String = (gpEntry["code"] as LineEdit).text.strip_edges()
		if gpCode == "":
			continue
		var gpAliases: Array = []
		for gpPart in (gpEntry["aliases"] as LineEdit).text.split(","):
			var gpText: String = str(gpPart).strip_edges()
			if gpText != "":
				gpAliases.append(gpText)
		gpRows.append({
			"code": gpCode,
			"label": (gpEntry["label"] as LineEdit).text.strip_edges(),
			"aliases": gpAliases,
		})
	_gpStd.gpSetCodeTable(_gpCurrentTable, gpRows)


# ============================ classification tab / 分类映射页 ============================

func _gpRebuildClassify() -> void:
	for gpChild in _gpClassifyBox.get_children():
		_gpClassifyBox.remove_child(gpChild)
		gpChild.queue_free()
	_gpClassifyRows = []
	if _gpStd == null:
		return
	_gpClassifySection("by_category", ["pump", "tank", "heat", "instrument", "valve"])
	_gpClassifySection("by_symbol", [])
	_gpClassifyValve()


func _gpClassifySection(gpKey: String, gpDefaults: Array) -> void:
	var gpTitle: Label = Label.new()
	gpTitle.text = I18n.gpTr("standard.by_category") if gpKey == "by_category" \
		else I18n.gpTr("standard.by_symbol")
	gpTitle.add_theme_font_size_override("font_size", 12)
	_gpClassifyBox.add_child(gpTitle)
	var gpMap: Dictionary = _gpStd.gpClassification.get(gpKey, {}) as Dictionary
	var gpKeys: Array = []
	for gpK in gpMap.keys():
		gpKeys.append(str(gpK))
	for gpK in gpDefaults:
		if not gpMap.has(str(gpK)):
			gpKeys.append(str(gpK))
	gpKeys.sort()
	for gpK in gpKeys:
		_gpAddClassifyRow(gpKey, gpK, str(gpMap.get(gpK, "")))
	var gpAdd: Button = Button.new()
	gpAdd.text = I18n.gpTr("standard.add_row")
	gpAdd.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	gpAdd.pressed.connect(func() -> void:
		_gpAddClassifyRow(gpKey, "", ""))
	_gpClassifyBox.add_child(gpAdd)


func _gpAddClassifyRow(gpKey: String, gpFrom: String, gpTo: String) -> void:
	var gpRow: HBoxContainer = HBoxContainer.new()
	_gpClassifyBox.add_child(gpRow)
	var gpEntry: Dictionary = {"row": gpRow, "key": gpKey}
	gpEntry["from"] = _gpSmallEdit(gpRow, gpFrom, 150)
	var gpPick: OptionButton = OptionButton.new()
	gpPick.add_item("（不编号）")
	for gpClass in GPProjectStandard.GP_CLASS_IDS:
		gpPick.add_item(GPProjectStandard.gpClassLabel(gpClass))
	var gpIdx: int = 0
	if gpTo != "":
		gpIdx = GPProjectStandard.GP_CLASS_IDS.find(gpTo) + 1
	gpPick.select(gpIdx)
	gpRow.add_child(gpPick)
	gpEntry["to"] = gpPick
	var gpDel: Button = Button.new()
	gpDel.text = "×"
	gpDel.pressed.connect(func() -> void:
		_gpClassifyRows.erase(gpEntry)
		gpRow.queue_free())
	gpRow.add_child(gpDel)
	_gpClassifyRows.append(gpEntry)


func _gpClassifyValve() -> void:
	var gpTitle: Label = Label.new()
	gpTitle.text = I18n.gpTr("standard.valve")
	gpTitle.add_theme_font_size_override("font_size", 12)
	_gpClassifyBox.add_child(gpTitle)
	var gpMap: Dictionary = _gpStd.gpClassification.get("valve_by_actuator", {}) as Dictionary
	for gpAct in ["手动", "无", "气动", "电动", "液动"]:
		_gpAddValveRow(gpAct, str(gpMap.get(gpAct, "")))


func _gpAddValveRow(gpAct: String, gpTo: String) -> void:
	var gpRow: HBoxContainer = HBoxContainer.new()
	_gpClassifyBox.add_child(gpRow)
	var gpEntry: Dictionary = {"row": gpRow, "actuator": gpAct}
	var gpName: Label = Label.new()
	gpName.text = gpAct
	gpName.custom_minimum_size = Vector2(150, 0)
	gpRow.add_child(gpName)
	var gpPick: OptionButton = OptionButton.new()
	gpPick.add_item("（不编号）")
	for gpClass in GPProjectStandard.GP_CLASS_IDS:
		gpPick.add_item(GPProjectStandard.gpClassLabel(gpClass))
	gpPick.select(GPProjectStandard.GP_CLASS_IDS.find(gpTo) + 1 if gpTo != "" else 0)
	gpRow.add_child(gpPick)
	gpEntry["to"] = gpPick
	_gpClassifyRows.append(gpEntry)


func _gpCollectClassify() -> void:
	if _gpStd == null:
		return
	var gpByCategory: Dictionary = {}
	var gpBySymbol: Dictionary = {}
	var gpValve: Dictionary = {}
	for gpEntry in _gpClassifyRows:
		var gpKey: String = str(gpEntry.get("key", ""))
		var gpFrom: String = (gpEntry["from"] as LineEdit).text.strip_edges() \
			if gpEntry.has("from") else str(gpEntry.get("actuator", ""))
		var gpPick: OptionButton = gpEntry["to"] as OptionButton
		var gpTo: String = ""
		if gpPick.selected > 0:
			gpTo = GPProjectStandard.GP_CLASS_IDS[gpPick.selected - 1]
		if gpFrom == "":
			continue
		if gpKey == "by_category":
			gpByCategory[gpFrom] = gpTo
		elif gpKey == "by_symbol":
			gpBySymbol[gpFrom] = gpTo
		elif gpKey == "valve_by_actuator":
			gpValve[gpFrom] = gpTo
	_gpStd.gpClassification["by_category"] = gpByCategory
	_gpStd.gpClassification["by_symbol"] = gpBySymbol
	_gpStd.gpClassification["valve_by_actuator"] = gpValve


# ============================ package / 标准包 ============================

func _gpOnExport() -> void:
	var gpDlg: FileDialog = FileDialog.new()
	gpDlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	gpDlg.access = FileDialog.ACCESS_FILESYSTEM
	gpDlg.add_filter("*.gpstd.json", "G-PID standard")
	add_child(gpDlg)
	gpDlg.file_selected.connect(func(gpPath: String) -> void:
		_gpCollectAll()
		var gpText: String = GPTagRuleService.gpStandardToJson(_gpStd)
		var gpFile: FileAccess = FileAccess.open(gpPath, FileAccess.WRITE)
		if gpFile != null:
			gpFile.store_string(gpText)
			gpFile.close()
			gpStatus.emit("standard.io_saved", [gpPath]))
	gpDlg.popup_centered_ratio(0.6)


func _gpOnImport() -> void:
	var gpDlg: FileDialog = FileDialog.new()
	gpDlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	gpDlg.access = FileDialog.ACCESS_FILESYSTEM
	gpDlg.add_filter("*.json", "JSON")
	add_child(gpDlg)
	gpDlg.file_selected.connect(func(gpPath: String) -> void:
		var gpText: String = FileAccess.get_file_as_string(gpPath)
		var gpImported: GPProjectStandard = GPTagRuleService.gpStandardFromJson(gpText)
		if gpImported == null:
			gpStatus.emit("standard.io_failed", [gpPath])
			return
		_gpCollectAll()
		var gpRows: Array[Dictionary] = GPTagRuleService.gpStandardDiff(_gpStd, gpImported)
		_gpStd = gpImported
		_gpCurrentClass = ""
		_gpCurrentTable = ""
		_gpRefreshAll()
		_gpShowDiff(gpRows))
	gpDlg.popup_centered_ratio(0.6)


func _gpShowDiff(gpRows: Array[Dictionary]) -> void:
	var gpLines: Array[String] = []
	for gpRow in gpRows:
		gpLines.append(str(gpRow.get("text", "")))
	_gpDiffText.text = I18n.gpTr("standard.diff_empty") if gpLines.is_empty() \
		else "\n".join(gpLines)


# ============================ preview / 预览 ============================

func _gpRefreshAll() -> void:
	_gpRefreshClassPicker()
	_gpRefreshTablePicker()
	_gpRebuildClassify()
	_gpRefreshPreview()


func _gpRefreshClassPicker() -> void:
	if _gpClassName == null:
		return
	if _gpCurrentClass == "":
		_gpCurrentClass = GPProjectStandard.GP_CLASS_IDS[0]
	_gpClassName.select(GPProjectStandard.GP_CLASS_IDS.find(_gpCurrentClass))
	_gpRebuildRule()


func _gpRefreshTablePicker() -> void:
	if _gpTablePick == null:
		return
	# Switching tabs may arrive with unsaved table rows; write them back before rebuilding.
	# 切页时可能还有未写回的代号表行；先收集，再重建。
	if not _gpTableEdits.is_empty():
		_gpCollectTable()
	_gpFillTablePicker()
	if _gpCurrentTable == "":
		_gpCurrentTable = _gpTableIds[0] if not _gpTableIds.is_empty() else ""
	var gpIdx: int = _gpTableIds.find(_gpCurrentTable)
	if gpIdx < 0 and not _gpTableIds.is_empty():
		_gpCurrentTable = _gpTableIds[0]
		gpIdx = 0
	_gpTablePick.select(gpIdx)
	_gpRebuildTable()


func _gpRefreshPreview() -> void:
	if _gpPreviewLabel == null or _gpStd == null:
		return
	var gpParts: Array[String] = []
	for gpClass in GPProjectStandard.GP_CLASS_IDS:
		if not _gpStd.gpEnabled(gpClass):
			continue
		var gpRules: GPProjectTagRules = _gpStd.gpRulesOf(gpClass)
		var gpRule: GPTagRule = gpRules.gpDefault
		# A synthetic definition per class, so the sample shows "P-1001" instead of the
		# un-configured fallback "X-1001" — a preview that looks un-configured is worse than none.
		# 每类给一个合成定义，使样例显示 "P-1001" 而不是未配置的兜底 "X-1001" ——
		# 一个看起来「没配过」的预览比没有预览更糟。
		var gpDef: GPSymbolDef = _gpPreviewDef(gpClass)
		if gpRule.gpUsesSegments():
			var gpSample: String = gpRule.gpRender({
				"seq": gpRule.gpStart + gpRule.gpStep,
				"attrs": {"dn": "150", "medium": "CWR", "spec": "A1A", "insulation": "P",
					"area": "1200", "discipline": "PI"},
			}, _gpStd)
			gpParts.append("%s: %s" % [GPProjectStandard.gpClassLabel(gpClass),
				gpSample if gpSample != "" else "（不可渲染）"])
		else:
			gpParts.append("%s: %s" % [GPProjectStandard.gpClassLabel(gpClass),
				gpRule.gpFormat(gpRules.gpPrefixFor(gpDef),
					gpRule.gpStart + gpRule.gpStep)])
	_gpPreviewLabel.text = "   ".join(gpParts)


# ============================ collect / confirm ============================

func _gpCollectAll() -> void:
	# ⚠️ EVERY tab must be collected here. The project-info tab was added without this line once,
	# so confirming the dialog silently dropped the project info — the title block stayed empty
	# and nothing looked broken until a sheet was printed.
	# ⚠️ 每个页都必须在这里收集。项目信息页曾经加了控件却漏了这一步，于是点确定时项目信息被
	# **静默丢弃** —— 图框一直是空的，直到打印出来才看得出。
	_gpCollectRule()
	_gpCollectProjectInfo()
	_gpCollectTable()
	_gpCollectClassify()


func _gpOnConfirmed() -> void:
	if _gpStd == null:
		return
	_gpCollectAll()
	gpStandardApplied.emit(_gpStd, _gpRenumber != null and _gpRenumber.button_pressed)
	if _gpSheetRenumber != null and _gpSheetRenumber.button_pressed:
		gpSheetsRenumberRequested.emit()


# Representative symbol definition for a class, used ONLY by the preview.
# 某类别的代表图元定义，**仅**供预览使用。
static func _gpPreviewDef(gpClass: String) -> GPSymbolDef:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	match gpClass:
		GPProjectStandard.GP_CLASS_EQUIPMENT:
			gpDef.gpCategory = "pump"
			gpDef.gpTagPrefix = "P"
		GPProjectStandard.GP_CLASS_INSTRUMENT:
			gpDef.gpCategory = "instrument"
			gpDef.gpTagPrefix = "I"
		GPProjectStandard.GP_CLASS_MANUAL_VALVE:
			gpDef.gpCategory = "valve"
			gpDef.gpTagPrefix = "V"
	return gpDef


# ============================ small helpers / 小工具 ============================

func _gpLabel(gpKey: String, gpBold: bool) -> Label:
	var gpLabel: Label = Label.new()
	gpLabel.text = I18n.gpTr(gpKey)
	if gpBold:
		gpLabel.add_theme_font_size_override("font_size", 13)
	return gpLabel


func _gpSpin(gpValue: int, gpMin: int, gpMax: int = 999999,
		gpWidth: int = 64) -> SpinBox:
	var gpSpin: SpinBox = SpinBox.new()
	gpSpin.min_value = gpMin
	gpSpin.max_value = gpMax
	gpSpin.value = gpValue
	gpSpin.custom_minimum_size = Vector2(gpWidth, 0)
	return gpSpin


func _gpHeader(gpText: String, gpWidth: int) -> Label:
	var gpLabel: Label = Label.new()
	gpLabel.text = gpText
	gpLabel.add_theme_font_size_override("font_size", 11)
	gpLabel.custom_minimum_size = Vector2(gpWidth, 0)
	gpLabel.modulate = Color(1, 1, 1, 0.6)
	return gpLabel


func _gpSmallEdit(gpParent: HBoxContainer, gpText: String, gpWidth: int,
		gpPlaceholder: String = "") -> LineEdit:
	var gpEdit: LineEdit = LineEdit.new()
	gpEdit.text = gpText
	gpEdit.custom_minimum_size = Vector2(gpWidth, 0)
	if gpPlaceholder != "":
		gpEdit.placeholder_text = gpPlaceholder
	gpParent.add_child(gpEdit)
	return gpEdit


# The comfortable logical range of the four-tab layout (ADR-37 sizing contract).
# 四个标签页布局的舒适逻辑区间（ADR-37 尺寸契约）。
# Height floor covers the TALLEST tab (project info): a TabContainer's minimum tracks the
# current tab, so a floor sized to the shortest tab would clip the others.
# 高度下限覆盖**最高**的那一页（项目信息）：TabContainer 的最小尺寸跟随当前页，按最矮的页定下限
# 会把其它页裁掉。
const GP_MIN_LOGICAL: Vector2i = Vector2i(760, 520)
const GP_MAX_LOGICAL: Vector2i = Vector2i(1000, 720)


func _gpHostWindow() -> Window:
	var gpParent: Node = get_parent()
	return gpParent.get_window() if gpParent != null else null
