class_name GPDRCDialog
extends AcceptDialog
# Copyright © 2026 Jonson Wang
#
# The top-toolbar DRC result window (ADR-39 UI). It is deliberately NON-modal: clicking a row
# must take the user to the canvas / property panel while the list stays open for the next row.
# 顶部工具栏的 DRC 结果窗口（ADR-39 UI）。刻意**非模态**：点一行要把用户带到画布/属性面板，
# 同时列表保持打开，方便继续点下一行。
#
# Difference from the right dock panel / 与右侧停靠面板的差别：
# - dialog row: locate + select + switch the right dock to the PROPERTY tab;
# - dock row:   locate + select, never change the visible tab.
# - 弹窗行：定位 + 选中 + 右侧切到**属性**页；
# - 停靠行：定位 + 选中，绝不改当前页。
# The dialog will not close on a row click; the user closes it explicitly.
# 点行不会关闭弹窗；由用户显式关闭。
#
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

signal gpFindingActivated(gpFinding: GPFinding)

const GP_MIN_LOGICAL: Vector2i = Vector2i(560, 420)
const GP_MAX_LOGICAL: Vector2i = Vector2i(980, 760)

var _gpCanvas: GPCanvas2D = null
var _gpSheetsProvider: Callable = Callable()
var _gpFindings: Array[GPFinding] = []
var _gpSheetNames: Dictionary = {}

var _gpSummary: Label = null
var _gpList: ItemList = null
var _gpHint: Label = null
var _gpProjectMode: CheckBox = null
var _gpFilter: OptionButton = null
var _gpRunBtn: Button = null
var _gpJsonBtn: Button = null
var _gpWaiveBtn: Button = null
var _gpRevokeBtn: Button = null
var _gpWaiverDialog: GPWaiverDialog = null
var _gpRepairBtn: Button = null
var _gpRepairDialog: GPRepairPlanDialog = null


func _ready() -> void:
	if _gpList != null:
		return
	title = I18n.gpTr("drc.dialog_title")
	ok_button_text = I18n.gpTr("drc.dialog_close") if I18n.GP_STRINGS.has("drc.dialog_close") \
		else "Close"
	exclusive = false
	transient = true
	unresizable = false
	wrap_controls = false
	min_size = GP_MIN_LOGICAL
	_gpBuild()


func _gpBuild() -> void:
	if _gpList != null:
		return
	var gpMargin: MarginContainer = MarginContainer.new()
	gpMargin.add_theme_constant_override("margin_left", 12)
	gpMargin.add_theme_constant_override("margin_right", 12)
	gpMargin.add_theme_constant_override("margin_top", 10)
	gpMargin.add_theme_constant_override("margin_bottom", 10)
	add_child(gpMargin)
	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.add_theme_constant_override("separation", 8)
	gpMargin.add_child(gpRoot)

	_gpSummary = Label.new()
	_gpSummary.text = I18n.gpTr("drc.never_run")
	_gpSummary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpRoot.add_child(_gpSummary)

	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 6)
	gpRoot.add_child(gpRow)
	_gpRunBtn = Button.new()
	_gpRunBtn.text = I18n.gpTr("drc.dialog_rerun")
	_gpRunBtn.pressed.connect(gpRun)
	gpRow.add_child(_gpRunBtn)
	_gpProjectMode = CheckBox.new()
	_gpProjectMode.text = I18n.gpTr("drc.dialog_all_project")
	_gpProjectMode.toggled.connect(func(_on: bool) -> void: gpRun())
	gpRow.add_child(_gpProjectMode)
	_gpFilter = OptionButton.new()
	_gpFilter.add_item(I18n.gpTr("drc.dialog_filter_all"), 0)
	_gpFilter.add_item(I18n.gpTr("drc.dialog_filter_error"), 1)
	_gpFilter.add_item(I18n.gpTr("drc.dialog_filter_warning"), 2)
	_gpFilter.add_item(I18n.gpTr("drc.dialog_filter_info"), 3)
	_gpFilter.item_selected.connect(func(_idx: int) -> void: _gpRebuild())
	gpRow.add_child(_gpFilter)
	_gpWaiveBtn = Button.new()
	_gpWaiveBtn.text = I18n.gpTr("drc.waive_request")
	_gpWaiveBtn.pressed.connect(_gpOnWaiverPressed)
	gpRow.add_child(_gpWaiveBtn)
	_gpRevokeBtn = Button.new()
	_gpRevokeBtn.text = I18n.gpTr("drc.waive_revoke")
	_gpRevokeBtn.pressed.connect(_gpOnRevokePressed)
	gpRow.add_child(_gpRevokeBtn)
	_gpRepairBtn = Button.new()
	_gpRepairBtn.text = I18n.gpTr("drc.repair_title")
	_gpRepairBtn.pressed.connect(_gpShowRepairPlan)
	gpRow.add_child(_gpRepairBtn)
	_gpJsonBtn = Button.new()
	_gpJsonBtn.text = I18n.gpTr("drc.dialog_export_json")
	_gpJsonBtn.pressed.connect(_gpExportJson)
	gpRow.add_child(_gpJsonBtn)

	_gpList = ItemList.new()
	_gpList.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_gpList.select_mode = ItemList.SELECT_SINGLE
	_gpList.allow_reselect = true
	_gpList.item_selected.connect(_gpOnRowSelected)
	# `item_selected` does NOT fire when the user clicks the already-selected row again, so a
	# second click after panning away would not re-centre. `item_clicked` is the always-fire port.
	# `item_selected` 在重复点击已选中行时**不**触发，故平移走后第二次点击不会重新居中。
	# `item_clicked` 是始终触发的端口。
	_gpList.item_clicked.connect(_gpOnRowClicked)
	gpRoot.add_child(_gpList)

	_gpHint = Label.new()
	_gpHint.text = I18n.gpTr("drc.dialog_hint")
	_gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gpHint.modulate = Color(0.62, 0.7, 0.85)
	gpRoot.add_child(_gpHint)


# Open for a canvas / sheet provider. Re-runs on every open so the list is never stale.
# 为某画布 / 图纸来源打开。每次打开都重跑，故列表绝不会过期。
func gpOpenFor(gpCanvas: GPCanvas2D, gpSheetsProvider: Callable = Callable()) -> void:
	if _gpList == null:
		_gpBuild()
	_gpCanvas = gpCanvas
	_gpSheetsProvider = gpSheetsProvider
	gpRun()
	var gpHost: Window = get_parent().get_window() if get_parent() != null else null
	GPWindowFit.gpPopupContentFitted(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL)
	show()


# Run the engine on the current mode.
# 按当前模式跑引擎。
func gpRun() -> void:
	_gpFindings = []
	_gpSheetNames.clear()
	if _gpCanvas == null or _gpCanvas.gpGraph == null:
		_gpSummary.text = I18n.gpTr("drc.no_canvas")
		_gpRebuild()
		return
	if _gpProjectMode != null and _gpProjectMode.button_pressed and _gpSheetsProvider.is_valid():
		var gpSheets: Array = _gpSheetsProvider.call()
		for gpSheetRaw in gpSheets:
			var gpSheet: GPSheet = gpSheetRaw as GPSheet
			if gpSheet != null:
				_gpSheetNames[gpSheet.gpId] = gpSheet.gpName
		_gpFindings = GPDrcEngine.gpRunProject(gpSheets, _gpCanvas.gpDefs,
			_gpCanvas.gpGraph.gpStandard)
	else:
		_gpFindings = GPDrcEngine.gpRunSheet(_gpCanvas.gpGraph, _gpCanvas.gpSheet,
			_gpCanvas.gpDefs, _gpCanvas.gpGraph.gpStandard)
	_gpSummary.text = GPDRCReport.gpSummary(_gpFindings)
	_gpJsonBtn.disabled = _gpFindings.is_empty()
	_gpRebuild()


# Rebuild the list under the current severity filter.
# 按当前级别筛选重建列表。
func _gpRebuild() -> void:
	if _gpList == null:
		return
	_gpList.clear()
	var gpWant: int = _gpFilter.get_selected_id() if _gpFilter != null else 0
	for gpF in _gpFindings:
		if gpF == null:
			continue
		if gpWant == 1 and gpF.gpSeverity != GPFinding.GP_ERROR:
			continue
		if gpWant == 2 and gpF.gpSeverity != GPFinding.GP_WARNING:
			continue
		if gpWant == 3 and gpF.gpSeverity != GPFinding.GP_INFO:
			continue
		var gpPrefix: String = I18n.gpTr("drc.waived") + "  " if gpF.gpWaived else ""
		var gpSheet: String = ""
		if gpF.gpSheetId != "" and _gpSheetNames.has(gpF.gpSheetId):
			gpSheet = "[" + str(_gpSheetNames[gpF.gpSheetId]) + "] "
		var gpText: String = "%s  %s%s%s" % [_gpSeverityMark(gpF.gpSeverity), gpSheet,
			gpPrefix, gpF.gpText()]
		var gpIdx: int = _gpList.add_item(gpText)
		_gpList.set_item_metadata(gpIdx, gpF)
		_gpList.set_item_custom_fg_color(gpIdx, _gpSeverityColor(gpF.gpSeverity))
	if _gpList.item_count == 0:
		var gpEmpty: int = _gpList.add_item(I18n.gpTr("drc.dialog_empty"))
		_gpList.set_item_selectable(gpEmpty, false)
		_gpList.set_item_custom_fg_color(gpEmpty, Color(0.55, 0.8, 0.6))


# A row was clicked: emit the finding; the HOST decides locate/select/tab behaviour.
# 某行被点击：发出发现；由**宿主**决定定位/选中/切页行为。
func _gpOnRowSelected(gpIdx: int) -> void:
	_gpActivateRow(gpIdx)


func _gpOnRowClicked(gpIdx: int, _gpAt: Vector2, gpButton: int) -> void:
	if gpButton == MOUSE_BUTTON_LEFT:
		_gpActivateRow(gpIdx)


func _gpActivateRow(gpIdx: int) -> void:
	if gpIdx < 0 or gpIdx >= _gpList.item_count:
		return
	var gpF: GPFinding = _gpList.get_item_metadata(gpIdx) as GPFinding
	if gpF != null:
		gpFindingActivated.emit(gpF)


# Ask for a waiver on the currently selected finding. The waiver is stored in the project
# standard (`validation.waivers[]`) with a stable entity uid and a required reason/approver.
# 为当前选中发现申请豁免。豁免写入项目标准 `validation.waivers[]`，用稳定 uid，理由/批准人必填。
func _gpOnWaiverPressed() -> void:
	var gpF: GPFinding = _gpSelectedFinding()
	if gpF == null:
		_gpHint.text = I18n.gpTr("drc.waive_no_finding")
		return
	var gpStd: GPProjectStandard = _gpStd()
	if gpStd == null or gpF.gpEntityUid == "":
		_gpHint.text = I18n.gpTr("drc.waive_no_std")
		return
	if _gpWaiverDialog == null:
		_gpWaiverDialog = GPWaiverDialog.new()
		add_child(_gpWaiverDialog)
		_gpWaiverDialog.gpWaiverAccepted.connect(func(gpReason: String, gpApprover: String) -> void:
			_gpApplyWaiver(gpF, gpReason, gpApprover))
	var gpRule: String = gpF.gpCheckId if gpF.gpCheckId != "" else gpF.gpRuleId
	_gpWaiverDialog.gpShowFor(gpRule, gpF.gpEntityUid)


# Store one waiver and re-run. Returns true when it was written.
# 写入一条豁免并重跑。写入成功返回 true。
func _gpApplyWaiver(gpF: GPFinding, gpReason: String, gpApprover: String) -> bool:
	var gpStd: GPProjectStandard = _gpStd()
	if gpStd == null or gpF == null or gpF.gpEntityUid == "":
		return false
	if not GPWaiverDialog.gpIsValid(gpReason, gpApprover):
		return false
	if not GPDRCConfig.gpAddWaiver(gpStd, gpF, gpReason, gpApprover):
		return false
	_gpHint.text = I18n.gpTr("drc.waive_saved")
	gpRun()
	return true


func _gpShowRepairPlan() -> void:
	if _gpRepairDialog == null:
		_gpRepairDialog = GPRepairPlanDialog.new()
		add_child(_gpRepairDialog)
	_gpRepairDialog.gpOpenFor(_gpFindings)


func _gpOnRevokePressed() -> void:
	var gpF: GPFinding = _gpSelectedFinding()
	if gpF == null or not gpF.gpWaived:
		_gpHint.text = I18n.gpTr("drc.waive_not_waived")
		return
	var gpStd: GPProjectStandard = _gpStd()
	if gpStd == null or not GPDRCConfig.gpRemoveWaiver(gpStd, gpF):
		_gpHint.text = I18n.gpTr("drc.waive_not_waived")
		return
	_gpHint.text = I18n.gpTr("drc.waive_removed")
	gpRun()


func _gpStd() -> GPProjectStandard:
	if _gpCanvas == null or _gpCanvas.gpGraph == null:
		return null
	return _gpCanvas.gpGraph.gpStandard


func _gpSelectedFinding() -> GPFinding:
	if _gpList == null:
		return null
	var gpSel: PackedInt32Array = _gpList.get_selected_items()
	if gpSel.is_empty():
		return null
	var gpIdx: int = gpSel[0]
	if gpIdx < 0 or gpIdx >= _gpList.item_count:
		return null
	return _gpList.get_item_metadata(gpIdx) as GPFinding


func _gpExportJson() -> void:
	if _gpFindings.is_empty():
		return
	var gpDir: String = "user://drc_reports"
	var gpBase: String = "drc-%s" % Time.get_datetime_string_from_system().replace(":", "-")
	var gpStd: GPProjectStandard = _gpStd()
	var gpMeta: Dictionary = {
		"mode": "project" if _gpProjectMode.button_pressed else "sheet",
		"doc_hash": GPExportGate.gpDocHash([_gpCanvas.gpSheet] if _gpCanvas != null else []),
		"rules_hash": GPExportGate.gpRulesHash(gpStd),
	}
	var gpPath: String = GPDRCReport.gpWriteJson(_gpFindings, gpDir, gpBase, gpMeta)
	if gpPath != "":
		_gpSummary.text = "%s\n%s" % [GPDRCReport.gpSummary(_gpFindings), gpPath]


static func _gpSeverityMark(gpSev: String) -> String:
	match gpSev:
		GPFinding.GP_ERROR:
			return "●"
		GPFinding.GP_WARNING:
			return "▲"
		_:
			return "·"


static func _gpSeverityColor(gpSev: String) -> Color:
	match gpSev:
		GPFinding.GP_ERROR:
			return Color(0.95, 0.45, 0.45)
		GPFinding.GP_WARNING:
			return Color(0.95, 0.78, 0.35)
		_:
			return Color(0.62, 0.7, 0.85)
