class_name GPWaiverDialog
extends ConfirmationDialog
# Copyright © 2026 Jonson Wang
#
# "Request an exception" dialog (ADR-39 D3 / E04). A waiver is traceable by construction:
# the reason and the approver are REQUIRED; an empty form never produces a waiver.
# 「申请例外」对话框（ADR-39 D3 / E04）。豁免在构造上可追溯：理由与批准人**必填**；
# 空表单永远不会产出豁免。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

signal gpWaiverAccepted(gpReason: String, gpApprover: String)

var _gpRule: String = ""
var _gpEntity: String = ""
var _gpReason: LineEdit = null
var _gpApprover: LineEdit = null
var _gpError: Label = null


func _ready() -> void:
	title = I18n.gpTr("drc.waive_title")
	ok_button_text = I18n.gpTr("drc.waive_apply")
	cancel_button_text = I18n.gpTr("dialog.cancel")
	dialog_hide_on_ok = false
	min_size = Vector2i(380, 220)
	get_ok_button().pressed.connect(_gpOnOk)
	_gpBuild()


func _gpBuild() -> void:
	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.add_theme_constant_override("separation", 8)
	add_child(gpRoot)
	if _gpReason == null:
		_gpReason = LineEdit.new()
		_gpReason.placeholder_text = I18n.gpTr("drc.waive_reason")
		gpRoot.add_child(_gpReason)
	if _gpApprover == null:
		_gpApprover = LineEdit.new()
		_gpApprover.placeholder_text = I18n.gpTr("drc.waive_approver")
		gpRoot.add_child(_gpApprover)
	if _gpError == null:
		_gpError = Label.new()
		_gpError.modulate = Color(0.95, 0.45, 0.45)
		gpRoot.add_child(_gpError)


# Show for one finding. `gpRule` is the fine-grained check id; the entity uid is the stable key.
# 为一条发现显示。`gpRule` 是细分检查号；对象 uid 是稳定键。
func gpShowFor(gpRule: String, gpEntity: String) -> void:
	_gpRule = gpRule
	_gpEntity = gpEntity
	if _gpReason == null:
		_gpBuild()
	_gpReason.text = ""
	_gpApprover.text = ""
	_gpError.text = ""
	var gpHost: Window = null
	if get_parent() != null:
		gpHost = get_parent().get_window()
	GPWindowFit.gpPopupContentFitted(self, gpHost, Vector2i(380, 220), Vector2i(560, 360))
	show()


func _gpOnOk() -> void:
	var gpReason: String = _gpReason.text.strip_edges()
	var gpApprover: String = _gpApprover.text.strip_edges()
	if gpReason == "" or gpApprover == "":
		_gpError.text = I18n.gpTr("drc.waive_required")
		return
	gpWaiverAccepted.emit(gpReason, gpApprover)
	hide()


# Pure validation (used by tests and by the button handler).
# 纯校验（测试与按钮处理共用）。
static func gpIsValid(gpReason: String, gpApprover: String) -> bool:
	return gpReason.strip_edges() != "" and gpApprover.strip_edges() != ""
