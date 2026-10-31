class_name GPRepairPlanDialog
extends AcceptDialog
# Copyright © 2026 Jonson Wang
#
# Read-only repair-plan viewer (ADR-39 P4). It shows the CLOSED action vocabulary produced by
# GPDRCRepair; it does not execute anything. Execution is a separate, undoable command step.
# 只读修复计划查看器（ADR-39 P4）。显示 GPDRCRepair 产出的**封闭动作集**；它不执行任何动作。
# 执行是独立的、可撤销的命令步骤。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_MIN_LOGICAL: Vector2i = Vector2i(520, 420)
const GP_MAX_LOGICAL: Vector2i = Vector2i(900, 720)

var _gpPlan: Array[Dictionary] = []
var _gpList: ItemList = null
var _gpSummary: Label = null


func _ready() -> void:
	title = I18n.gpTr("drc.repair_title")
	ok_button_text = I18n.gpTr("drc.dialog_close")
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
	_gpSummary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpRoot.add_child(_gpSummary)
	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRoot.add_child(gpRow)
	var gpExport: Button = Button.new()
	gpExport.text = I18n.gpTr("drc.repair_export")
	gpExport.pressed.connect(_gpExport)
	gpRow.add_child(gpExport)
	_gpList = ItemList.new()
	_gpList.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpRoot.add_child(_gpList)


func gpOpenFor(gpFindings: Array[GPFinding]) -> void:
	if _gpList == null:
		_gpBuild()
	_gpPlan = GPDRCRepair.gpPlan(gpFindings)
	_gpRebuild()
	var gpHost: Window = get_parent().get_window() if get_parent() != null else null
	GPWindowFit.gpPopupContentFitted(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL)
	show()


func _gpRebuild() -> void:
	_gpList.clear()
	var gpCounts: Dictionary = GPDRCRepair.gpCounts(_gpPlan)
	_gpSummary.text = I18n.gpTr("drc.repair_summary") % [_gpPlan.size(), str(gpCounts)]
	for gpE in _gpPlan:
		var gpText: String = "[%s] %s · %s" % [str(gpE.get("action", "")),
			str(gpE.get("check", "")), str(gpE.get("params", []))]
		var gpIdx: int = _gpList.add_item(gpText)
		_gpList.set_item_metadata(gpIdx, gpE)
		if str(gpE.get("severity", "")) == GPFinding.GP_ERROR:
			_gpList.set_item_custom_fg_color(gpIdx, Color(0.95, 0.45, 0.45))
		elif str(gpE.get("severity", "")) == GPFinding.GP_WARNING:
			_gpList.set_item_custom_fg_color(gpIdx, Color(0.95, 0.78, 0.35))
	if _gpPlan.is_empty():
		_gpList.add_item(I18n.gpTr("drc.dialog_empty"))


func _gpExport() -> void:
	if _gpPlan.is_empty():
		return
	var gpDir: String = "user://drc_reports"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(gpDir))
	var gpPath: String = gpDir.path_join("repair-%s.json" % Time.get_datetime_string_from_system().replace(":", "-"))
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.WRITE)
	if gpF == null:
		return
	gpF.store_string(JSON.stringify({"schema": "gpid.repair/1", "plan": _gpPlan}, "\t"))
	gpF.close()
	_gpSummary.text = gpPath
