class_name GPChangePasswordDialog
extends Window
# Copyright © 2026 Jonson Wang
# Self-service password change (v1.3.1, user request 2026-11-18): the logged-in user
# re-assigns their OWN password from the editor status bar chip. Roles / display name /
# email are NOT touchable here — capability management stays manager-only (W15 matrix).
# 自助改密（v1.3.1，用户要求 2026-11-18）：已登录用户从编辑器状态栏的用户铭牌进入，
# 重设**自己的**密码。角色 / 显示名 / 邮箱在此**不可触碰** —— 能力管理仍归管理者（W15 矩阵）。
#
# ADR-48: created hidden, shown via popup_centered, unresizable=false, content root
# FULL_RECT (R8). R7: member-function callbacks, no lambdas across frames.
# ADR-48：创建即隐藏、显示走 popup_centered、unresizable=false、内容根 FULL_RECT（R8）。
# R7：成员函数回调，跨帧不持 lambda。

# Emitted once per outcome (success OR failure — the dialog never blocks the editor).
# 每次尝试产出一次信号（成功或失败 —— 本对话框永不阻塞编辑器）。
signal gpChangeDone(gpOk: bool)

var gpArchivePath: String = ""
var gpUser: String = ""

var gpOldEdit: LineEdit
var gpPassEdit: LineEdit
var gpConfirmEdit: LineEdit
var gpInfoLabel: Label


# Build the form. Param names gpPath/gpName dodge member shadowing (silent self-assign).
# 构建表单。参数名 gpPath/gpName 刻意避开成员名（参数遮蔽 = 静默自赋值）。
func gpSetup(gpPath: String, gpName: String) -> void:
	gpArchivePath = gpPath
	gpUser = gpName
	title = I18n.gpTr("identity.change_pw_title")
	visible = false
	unresizable = false
	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(gpRoot)
	gpInfoLabel = Label.new()
	gpInfoLabel.text = I18n.gpTr("identity.change_pw_prompt")
	gpInfoLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpRoot.add_child(gpInfoLabel)
	var gpForm: GridContainer = GridContainer.new()
	gpForm.columns = 2
	gpRoot.add_child(gpForm)
	gpOldEdit = LineEdit.new()
	gpOldEdit.secret = true
	_gpAddRow(gpForm, "identity.old_password", gpOldEdit)
	gpPassEdit = LineEdit.new()
	gpPassEdit.secret = true
	_gpAddRow(gpForm, "identity.new_password2", gpPassEdit)
	gpConfirmEdit = LineEdit.new()
	gpConfirmEdit.secret = true
	_gpAddRow(gpForm, "identity.password_confirm", gpConfirmEdit)
	var gpButtons: HBoxContainer = HBoxContainer.new()
	gpButtons.alignment = BoxContainer.ALIGNMENT_END
	gpRoot.add_child(gpButtons)
	var gpOk: Button = Button.new()
	gpOk.text = I18n.gpTr("identity.change_pw_apply")
	gpOk.pressed.connect(_gpOnSubmit)
	gpButtons.add_child(gpOk)
	var gpCancel: Button = Button.new()
	gpCancel.text = I18n.gpTr("dialog.cancel")
	gpCancel.pressed.connect(_gpOnCancel)
	gpButtons.add_child(gpCancel)
	close_requested.connect(_gpOnCancel)


# Submit: live-read the roster, verify the OLD password, then re-credential the OWN entry
# with roles / display name / email carried through untouched (they are read back from the
# entry, never from the dialog — the dialog has no fields for them).
# 提交：实时重读名单，验证**旧**密码，然后重设**自己**条目的凭据 —— 角色 / 显示名 / 邮箱
# 从条目**原样带回**（绝不来自对话框 —— 对话框没有这些字段）。
func _gpOnSubmit() -> void:
	var gpHeader: GPIOResult = GPProjectIO.gpReadHeader(gpArchivePath)
	if not gpHeader.gpIsOk():
		_gpSay("identity.roster_apply_fail")
		return
	var gpMembers: Array = []
	var gpRaw: Variant = (gpHeader.gpPayload as Dictionary).get("members", null)
	if gpRaw is Array:
		gpMembers = gpRaw as Array
	var gpVerdict: Dictionary = GPCMemberRoster.gpVerifyLogin(gpMembers, gpUser, gpOldEdit.text)
	if not bool(gpVerdict.get("ok", false)):
		_gpSay("identity.old_pw_wrong")
		return
	if not GPIdentityCredentials.gpIsValidPassword(gpPassEdit.text):
		_gpSay("identity.too_short_fmt")
		return
	if gpPassEdit.text != gpConfirmEdit.text:
		_gpSay("identity.mismatch")
		return
	var gpM: Dictionary = GPCMemberRoster.gpFind(gpMembers, gpUser)
	var gpRoles: Array = []
	var gpRolesRaw: Variant = gpM.get("roles", null)
	if gpRolesRaw is Array:
		gpRoles = (gpRolesRaw as Array).duplicate(true)
	var gpSet: Dictionary = GPCMemberRoster.gpSetCredential(gpMembers, gpUser,
		gpPassEdit.text, str(gpM.get("display_name", "")), gpRoles,
		str(gpM.get("email", "")))
	if not bool(gpSet.get("ok", false)):
		_gpSay("identity." + str(gpSet.get("code", "")).replace(".", "_"))
		return
	var gpRes: GPIOResult = GPCMemberRoster.gpApplyToArchive(gpArchivePath, gpMembers, gpUser)
	if not gpRes.gpIsOk():
		_gpSay(gpRes.gpMessageKey)
		return
	gpChangeDone.emit(true)
	queue_free()


func _gpOnCancel() -> void:
	gpChangeDone.emit(false)
	queue_free()


# Show a reason in the info line (i18n key; never a bare literal).
# 在提示行显示原因（i18n 键；绝不用裸字面串）。
func _gpSay(gpKey: String) -> void:
	gpInfoLabel.text = I18n.gpTr(gpKey)


# One label+edit row in the grid. / 网格中的一行标签 + 输入框。
func _gpAddRow(gpGrid: GridContainer, gpLabelKey: String, gpEdit: LineEdit) -> void:
	var gpLabel: Label = Label.new()
	gpLabel.text = I18n.gpTr(gpLabelKey)
	gpGrid.add_child(gpLabel)
	gpEdit.custom_minimum_size = Vector2(220, 0)
	gpGrid.add_child(gpEdit)
