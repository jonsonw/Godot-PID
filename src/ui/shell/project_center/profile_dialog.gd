class_name GPProfileDialog
extends Window
# Copyright © 2026 Jonson Wang
# Session-user profile (v1.3.2, user request 2026-11-19): opened from the quick-toolbar
# user button (or the status-bar chip). Top half = READ-ONLY basic info (username /
# display name / roles / email — read live from the roster on open); bottom half = the
# self-service password change. Roles / display name / email are NOT touchable here —
# capability management stays manager-only (W15 matrix).
# 会话用户资料（v1.3.2，用户要求 2026-11-19）：从快捷工具栏用户按钮（或状态栏铭牌）进入。
# 上半 = **只读**基本信息（用户名 / 显示名 / 角色 / 邮箱 —— 打开时实时读名单）；
# 下半 = 自助改密。角色 / 显示名 / 邮箱在此**不可触碰** —— 能力管理仍归管理者（W15 矩阵）。
#
# ADR-48: created hidden, shown via popup_centered, unresizable=false, content root
# FULL_RECT (R8). R7: member-function callbacks, no lambdas across frames.
# ADR-48：创建即隐藏、显示走 popup_centered、unresizable=false、内容根 FULL_RECT（R8）。
# R7：成员函数回调，跨帧不持 lambda。

# Emitted once per outcome (success OR failure — the dialog never blocks the editor).
# 每次尝试产出一次信号（成功或失败 —— 本对话框永不阻塞编辑器）。
signal gpProfileDone(gpOk: bool)

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
	title = I18n.gpTr("identity.profile_title")
	visible = false
	unresizable = false
	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(gpRoot)
	# -- Read-only basic info, read LIVE from the current roster on open. --
	# -- 只读基本信息，打开时从**当前**名单实时读取。 --
	var gpInfo: GridContainer = GridContainer.new()
	gpInfo.columns = 2
	gpRoot.add_child(gpInfo)
	var gpHeader: GPIOResult = GPProjectIO.gpReadHeader(gpPath)
	var gpM: Dictionary = {}
	if gpHeader.gpIsOk():
		var gpRaw: Variant = (gpHeader.gpPayload as Dictionary).get("members", null)
		if gpRaw is Array:
			gpM = GPCMemberRoster.gpFind(gpRaw as Array, gpName)
	_gpAddInfoRow(gpInfo, "identity.user", gpName)
	_gpAddInfoRow(gpInfo, "identity.profile_display",
		str(gpM.get("display_name", "")) if not gpM.is_empty() else "—")
	_gpAddInfoRow(gpInfo, "identity.roles", _gpRolesText(gpM))
	_gpAddInfoRow(gpInfo, "identity.profile_email",
		str(gpM.get("email", "")) if not gpM.is_empty() else "—")
	var gpNote: Label = Label.new()
	gpNote.text = I18n.gpTr("identity.profile_note")
	gpNote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpRoot.add_child(gpNote)
	# -- Password change. / 改密段。 --
	var gpForm: GridContainer = GridContainer.new()
	gpForm.columns = 2
	gpRoot.add_child(gpForm)
	gpOldEdit = LineEdit.new()
	gpOldEdit.secret = true
	_gpAddEditRow(gpForm, "identity.old_password", gpOldEdit)
	gpPassEdit = LineEdit.new()
	gpPassEdit.secret = true
	_gpAddEditRow(gpForm, "identity.new_password2", gpPassEdit)
	gpConfirmEdit = LineEdit.new()
	gpConfirmEdit.secret = true
	_gpAddEditRow(gpForm, "identity.password_confirm", gpConfirmEdit)
	gpInfoLabel = Label.new()
	gpInfoLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpRoot.add_child(gpInfoLabel)
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
	gpProfileDone.emit(true)
	queue_free()


func _gpOnCancel() -> void:
	gpProfileDone.emit(false)
	queue_free()


# Localized role names, comma-joined (missing entry -> em dash, honest blank).
# 角色显示名逗号连接（无条目 -> 破折号，如实空白）。
func _gpRolesText(gpM: Dictionary) -> String:
	if gpM.is_empty():
		return "—"
	var gpOut: Array[String] = []
	var gpRolesRaw: Variant = gpM.get("roles", null)
	if gpRolesRaw is Array:
		for gpRole in gpRolesRaw as Array:
			gpOut.append(I18n.gpTr("identity.role_" + str(gpRole)))
	return ", ".join(gpOut) if not gpOut.is_empty() else "—"


# Show a reason in the info line (i18n key; never a bare literal).
# 在提示行显示原因（i18n 键；绝不用裸字面串）。
func _gpSay(gpKey: String) -> void:
	gpInfoLabel.text = I18n.gpTr(gpKey)


# One label+value row in the READ-ONLY info grid.
# 只读信息网格中的一行标签 + 值。
func _gpAddInfoRow(gpGrid: GridContainer, gpLabelKey: String, gpValue: String) -> void:
	var gpLabel: Label = Label.new()
	gpLabel.text = I18n.gpTr(gpLabelKey)
	gpGrid.add_child(gpLabel)
	var gpValue2: Label = Label.new()
	gpValue2.text = gpValue if gpValue != "" else "—"
	gpGrid.add_child(gpValue2)


# One label+edit row in the password grid. / 改密网格中的一行标签 + 输入框。
func _gpAddEditRow(gpGrid: GridContainer, gpLabelKey: String, gpEdit: LineEdit) -> void:
	var gpLabel: Label = Label.new()
	gpLabel.text = I18n.gpTr(gpLabelKey)
	gpGrid.add_child(gpLabel)
	gpEdit.custom_minimum_size = Vector2(220, 0)
	gpGrid.add_child(gpEdit)
