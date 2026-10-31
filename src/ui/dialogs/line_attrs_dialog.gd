class_name GPLineAttrsDialog
extends ConfirmationDialog
# Copyright © 2026 Jonson Wang
#
# The "line attributes" panel shown right after a NEW pipe is drawn (ADR-36 D9, ADR-37).
# 新画完一根管线后弹出的「管线属性」小面板（ADR-36 D9、ADR-37）。
#
# WHY A PANEL AT ALL / 为何要有这个面板：
# the line number is built FROM these attributes (size / medium / material / insulation). At the
# moment the pipe is drawn they are all unknown, so the drawing would either show a meaningless
# placeholder forever or the number would change later without anyone noticing.
# 管线号是**从这些属性**生成的（管径 / 介质 / 材料 / 保温）。线刚画完的这一刻它们都还未知，
# 不填的结果要么是永远挂着一串无意义的占位，要么是以后某天号在无人察觉时变了。
#
# CODE FIELDS ARE PICKERS, NOT FREE TEXT / 代号字段是**选择器**，不是自由文本：
# medium / material / insulation must come from the project's code tables, otherwise two
# draughtsmen type "CWR" and "循环冷却水" for the same line and the number stops being a code.
# The picker's items ARE the tables — adding a medium code is done in the standard dialog, once.
# 介质 / 材料 / 保温必须来自工程的代号表，否则两个人对同一根管写 "CWR" 与 "循环冷却水"，
# 号就不再是代号。选择器的条目**就是**代号表 —— 加一个介质代号在标准对话框里做一次。
#
# SIZE (ADR-37) / 尺寸（ADR-37）：
# content-adaptive and resizable; a fixed 420x200 (or any ratio) is not allowed.
# 按内容自适应且可拖动；固定 420×200（或任何比例）都不允许。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

signal gpApplied(gpAttrs: Dictionary)

var _gpRule: GPTagRule = null
var _gpStd: GPProjectStandard = null
var _gpRoot: VBoxContainer = null
var _gpPreview: Label = null
var _gpRows: Dictionary = {}
var _gpEdgeTag: String = ""
var _gpEdgeAttrs: Dictionary = {}


func _ready() -> void:
	title = I18n.gpTr("line_attrs.title")
	ok_button_text = I18n.gpTr("line_attrs.apply")
	cancel_button_text = I18n.gpTr("line_attrs.later")
	confirmed.connect(_gpOnConfirmed)
	min_size = Vector2i(380, 260)


# Show the panel for one edge.
# 为某条边显示面板。
func gpShowFor(gpEdge: GPPIDEdge, gpRule: GPTagRule, gpStd: GPProjectStandard) -> void:
	_gpRule = gpRule
	_gpStd = gpStd
	_gpEdgeTag = gpEdge.gpTag if gpEdge != null else ""
	_gpEdgeAttrs = gpEdge.gpAttrs.duplicate(true) if gpEdge != null else {}
	_gpBuild()
	var gpHost: Window = null
	if get_parent() != null:
		gpHost = get_parent().get_window()
	GPWindowFit.gpPopupContentFitted(self, gpHost, Vector2i(420, 300), Vector2i(700, 620))


# Pickable codes for a segment, straight from the project standard. Empty for non-code segments
# or an empty table (the panel then keeps a text field, so the user is never blocked).
# 某段可选的代号，直接取自项目标准。非代号段或空表时返回空（此时面板保留文本框，绝不把用户卡住）。
static func gpChoicesFor(gpSeg: GPTagSegment, gpStd: GPProjectStandard) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpSeg == null or gpStd == null:
		return gpOut
	# A code table makes the field a picker EVEN WHEN the segment source is ATTR /
	# ATTR_DIGITS: `dn` is an ATTR_DIGITS segment by default, but once the project defines
	# a `dn` table the diameter must be chosen, never typed. The table id is the segment's
	# explicit gpTable when present, otherwise the attribute key itself.
	# 代号表存在时，即使是 ATTR / ATTR_DIGITS 段也必须变成下拉：`dn` 默认是数字段，
	# 但项目一旦定义了 `dn` 代号表，管径就只能选、不能手输。表 id 优先取段的 gpTable，
	# 否则取属性键本身。
	var gpTable: String = gpSeg.gpTable
	if gpTable == "":
		gpTable = gpSeg.gpAttrKey()
	if gpTable == "" or gpStd.gpCodeTable(gpTable).is_empty():
		return gpOut
	for gpRowRaw in gpStd.gpCodeTable(gpTable):
		if not (gpRowRaw is Dictionary):
			continue
		var gpRow: Dictionary = gpRowRaw as Dictionary
		var gpCode: String = str(gpRow.get("code", "")).strip_edges()
		if gpCode == "":
			continue
		gpOut.append({"code": gpCode, "label": str(gpRow.get("label", ""))})
	return gpOut


func _gpBuild() -> void:
	if _gpRoot != null and is_instance_valid(_gpRoot):
		_gpRoot.queue_free()
	_gpRows = {}
	_gpRoot = VBoxContainer.new()
	_gpRoot.add_theme_constant_override("separation", 6)
	add_child(_gpRoot)
	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("line_attrs.hint")
	gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A real minimum width: an autowrap Label's minimum height is "everything wrapped at 1px"
	# otherwise, which inflates the whole window (ADR-37).
	# 真实的最小宽度：否则 autowrap Label 的最小高度是「按 1px 折行的全高」，会把窗口撑爆（ADR-37）。
	gpHint.custom_minimum_size = Vector2(320, 0)
	gpHint.add_theme_font_size_override("font_size", 12)
	_gpRoot.add_child(gpHint)
	if _gpRule == null:
		return
	var gpSeen: Dictionary = {}
	for gpSegRaw in _gpRule.gpSegments:
		var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
		if gpSeg == null:
			continue
		if gpSeg.gpSource != GPTagSegment.GPSource.GP_ATTR \
				and gpSeg.gpSource != GPTagSegment.GPSource.GP_ATTR_DIGITS \
				and gpSeg.gpSource != GPTagSegment.GPSource.GP_CODE_TABLE:
			continue
		var gpAttrKey: String = gpSeg.gpAttrKey()
		if gpAttrKey == "":
			continue
		if gpSeen.has(gpAttrKey):
			continue
		gpSeen[gpAttrKey] = true
		_gpAddRow(gpSeg)
	_gpPreview = Label.new()
	_gpPreview.add_theme_font_size_override("font_size", 12)
	_gpPreview.custom_minimum_size = Vector2(320, 0)
	_gpPreview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gpRoot.add_child(_gpPreview)
	_gpRefreshPreview()
	reset_size()


func _gpAddRow(gpSeg: GPTagSegment) -> void:
	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 8)
	_gpRoot.add_child(gpRow)
	var gpLabel: Label = Label.new()
	gpLabel.text = gpSeg.gpLabel
	gpLabel.custom_minimum_size = Vector2(96, 0)
	gpRow.add_child(gpLabel)
	var gpAttrKey: String = gpSeg.gpAttrKey()
	var gpCurrent: String = str(_gpEdgeAttrs.get(gpAttrKey, "")).strip_edges()
	var gpChoices: Array[Dictionary] = gpChoicesFor(gpSeg, _gpStd)
	if not gpChoices.is_empty():
		# Picker: the table's codes ARE the options; a missing/unknown value stays selectable as
		# "（空缺）" so an old drawing can be edited without inventing data.
		# 选择器：表里的代号**就是**选项；缺失/未知值以「（空缺）」保留，使旧图可改而不臆造数据。
		var gpPick: OptionButton = OptionButton.new()
		gpPick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gpPick.add_item(I18n.gpTr("line_attrs.empty_choice"))
		gpPick.set_item_metadata(0, "")
		var gpSel: int = 0
		for gpI in range(gpChoices.size()):
			var gpItem: Dictionary = gpChoices[gpI]
			var gpCode: String = str(gpItem.get("code", ""))
			var gpLabelText: String = str(gpItem.get("label", ""))
			gpPick.add_item("%s · %s" % [gpCode, gpLabelText] if gpLabelText != "" else gpCode)
			gpPick.set_item_metadata(gpI + 1, gpCode)
			if gpCode == gpCurrent:
				gpSel = gpI + 1
		if gpSel == 0 and gpCurrent != "":
			# Keep an unknown legacy value visible instead of silently clearing it.
			# 保留未知的旧值可见，而不是静默清空它。
			gpPick.add_item(I18n.gpTr("line_attrs.current_choice") % gpCurrent)
			gpPick.set_item_metadata(gpPick.item_count - 1, gpCurrent)
			gpSel = gpPick.item_count - 1
		gpPick.select(gpSel)
		gpPick.item_selected.connect(func(_gpI: int) -> void: _gpRefreshPreview())
		gpRow.add_child(gpPick)
		_gpRows[gpAttrKey] = {"kind": "code", "control": gpPick, "segment": gpSeg}
		return
	# Text field (size, or a code table that has no rows yet).
	# 文本框（管径，或尚无条目的代号表）。
	var gpEdit: LineEdit = LineEdit.new()
	gpEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpEdit.text = gpCurrent
	gpEdit.placeholder_text = _gpHintFor(gpSeg)
	gpEdit.text_changed.connect(func(_gpText: String) -> void: _gpRefreshPreview())
	gpRow.add_child(gpEdit)
	_gpRows[gpAttrKey] = {"kind": "text", "control": gpEdit, "segment": gpSeg}


func _gpHintFor(gpSeg: GPTagSegment) -> String:
	if gpSeg.gpSource == GPTagSegment.GPSource.GP_ATTR_DIGITS:
		return I18n.gpTr("line_attrs.digits_hint") % "150"
	return ""


# Current values, keyed by attribute name. Empty string means "leave it blank" (placeholder).
# 当前取值，按属性名。空串表示「留空」（用占位代号）。
func _gpCollect() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpAttrRaw in _gpRows.keys():
		var gpRow: Dictionary = _gpRows[gpAttrRaw] as Dictionary
		var gpControl: Node = gpRow["control"] as Node
		if gpRow["kind"] == "code":
			var gpPick: OptionButton = gpControl as OptionButton
			gpOut[str(gpAttrRaw)] = str(gpPick.get_item_metadata(gpPick.selected))
		else:
			gpOut[str(gpAttrRaw)] = (gpControl as LineEdit).text.strip_edges()
	return gpOut


func _gpRefreshPreview() -> void:
	if _gpPreview == null or _gpRule == null or _gpStd == null:
		return
	var gpMerged: Dictionary = _gpEdgeAttrs.duplicate(true)
	var gpNow: Dictionary = _gpCollect()
	for gpKey in gpNow.keys():
		gpMerged[gpKey] = gpNow[gpKey]
	var gpSeq: int = _gpRule.gpSequenceOf(_gpEdgeTag)
	if gpSeq < 0:
		gpSeq = _gpRule.gpStart + maxi(1, _gpRule.gpStep)
	var gpSample: String = _gpRule.gpRender({"seq": gpSeq, "attrs": gpMerged}, _gpStd)
	_gpPreview.text = I18n.gpTr("line_attrs.preview") % (gpSample if gpSample != "" else "—")
	reset_size()


func _gpOnConfirmed() -> void:
	gpApplied.emit(_gpCollect())
