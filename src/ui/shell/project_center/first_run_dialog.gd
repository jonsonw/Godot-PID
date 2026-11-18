class_name GPFirstRunDialog
extends Window
# Copyright © 2026 Jonson Wang
# First-run forced credential change (v1.3.1, user request 2026-11-18): the archive still
# sits on the SHIPPED admin/admin super-admin, so opening it demands a new username, a new
# password and a recovery email BEFORE anything else happens. Cancel / close exits back to
# the project manager — the default credential cannot enter the editor.
# 首登强制改密（v1.3.1，用户要求 2026-11-18）：存档仍在**出厂** admin/admin 超级管理员上，
# 打开即要求先设置新账户名、新密码与找回用的安全邮箱。取消 / 关闭即退回项目管理器 ——
# 默认凭据进不了编辑器。
#
# HONEST BOUNDARY / 如实边界：in the serverless NAS scenario the email is REGISTERED as the
# recovery contact (verified offline by the manager when resetting via gpSetCredential);
# self-service email recovery requires the cloud phase (server-side mail).
# 内网无服务器场景下，邮箱是**登记**的找回联系信息（管理员重置密码时线下核验）；
# 自助邮箱找回需要云端阶段（服务端发信）。
#
# ADR-48: created hidden, shown via popup_centered, unresizable=false, content root
# FULL_RECT (R8). R7: member-function callbacks, no lambdas across frames.
# ADR-48：创建即隐藏、显示走 popup_centered、unresizable=false、内容根 FULL_RECT（R8）。
# R7：成员函数回调，跨帧不持 lambda。

# Emitted once per outcome; "" user = cancelled (the coordinator exits to the manager).
# 每次尝试产出一次信号；gpUser 为空串 = 取消（协调者退回项目管理器）。
signal gpFirstRunDone(gpUser: String, gpOk: bool)

var gpArchivePath: String = ""

var gpUserEdit: LineEdit
var gpPassEdit: LineEdit
var gpConfirmEdit: LineEdit
var gpEmailEdit: LineEdit
var gpInfoLabel: Label


# Build the form. / 构建表单。参数名 gpPath 刻意避开成员名（参数遮蔽 = 静默自赋值）。
func gpSetup(gpPath: String) -> void:
	gpArchivePath = gpPath
	title = I18n.gpTr("identity.first_run_title")
	visible = false
	unresizable = false
	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(gpRoot)
	gpInfoLabel = Label.new()
	gpInfoLabel.text = I18n.gpTr("identity.first_run_prompt")
	gpInfoLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpRoot.add_child(gpInfoLabel)
	var gpForm: GridContainer = GridContainer.new()
	gpForm.columns = 2
	gpRoot.add_child(gpForm)
	gpUserEdit = LineEdit.new()
	_gpAddRow(gpForm, "identity.new_username", gpUserEdit)
	gpUserEdit.text = "admin"
	gpPassEdit = LineEdit.new()
	gpPassEdit.secret = true
	_gpAddRow(gpForm, "identity.new_password2", gpPassEdit)
	gpConfirmEdit = LineEdit.new()
	gpConfirmEdit.secret = true
	_gpAddRow(gpForm, "identity.password_confirm", gpConfirmEdit)
	gpEmailEdit = LineEdit.new()
	_gpAddRow(gpForm, "identity.email", gpEmailEdit)
	var gpButtons: HBoxContainer = HBoxContainer.new()
	gpButtons.alignment = BoxContainer.ALIGNMENT_END
	gpRoot.add_child(gpButtons)
	var gpOk: Button = Button.new()
	gpOk.text = I18n.gpTr("identity.first_run_apply")
	gpOk.pressed.connect(_gpOnSubmit)
	gpButtons.add_child(gpOk)
	var gpCancel: Button = Button.new()
	gpCancel.text = I18n.gpTr("dialog.cancel")
	gpCancel.pressed.connect(_gpOnCancel)
	gpButtons.add_child(gpCancel)
	close_requested.connect(_gpOnCancel)


# Submit: live-read the roster, validate in order, rename + re-credential + email, apply.
# 提交：实时重读名单，按序校验，改名 + 重设凭据 + 登记邮箱，落盘。
func _gpOnSubmit() -> void:
	var gpHeader: GPIOResult = GPProjectIO.gpReadHeader(gpArchivePath)
	if not gpHeader.gpIsOk():
		_gpSay("identity.roster_apply_fail")
		return
	var gpMembers: Array = []
	var gpRaw: Variant = (gpHeader.gpPayload as Dictionary).get("members", null)
	if gpRaw is Array:
		gpMembers = gpRaw as Array
	var gpName: String = gpUserEdit.text.strip_edges()
	if gpName == "":
		_gpSay("identity.err_roster_bad_user")
		return
	var gpEmail: String = gpEmailEdit.text.strip_edges()
	if not gpEmail.contains("@"):
		_gpSay("identity.email_bad")
		return
	if not GPIdentityCredentials.gpIsValidPassword(gpPassEdit.text):
		_gpSay("identity.too_short_fmt")
		return
	if gpPassEdit.text == "admin":
		_gpSay("identity.default_pw")
		return
	if gpPassEdit.text != gpConfirmEdit.text:
		_gpSay("identity.mismatch")
		return
	# Keeping "admin" as the name is allowed; a rename must not clash with another member.
	# 允许保留 admin 名；改名不得与其他成员撞名。
	if gpName != "admin" and GPCMemberRoster.gpFind(gpMembers, gpName) != {}:
		_gpSay("identity.err_roster_duplicate")
		return
	var gpPlan: Dictionary = GPCMemberRoster.gpRenameUser(gpMembers, "admin", gpName)
	if not bool(gpPlan.get("ok", false)):
		_gpSay("identity." + str(gpPlan.get("code", "")).replace(".", "_"))
		return
	var gpM: Dictionary = GPCMemberRoster.gpFind(gpMembers, gpName)
	var gpRoles: Array = []
	var gpRolesRaw: Variant = gpM.get("roles", null)
	if gpRolesRaw is Array:
		gpRoles = (gpRolesRaw as Array).duplicate(true)
	var gpSet: Dictionary = GPCMemberRoster.gpSetCredential(gpMembers, gpName,
		gpPassEdit.text, str(gpM.get("display_name", "")), gpRoles, gpEmail)
	if not bool(gpSet.get("ok", false)):
		_gpSay("identity." + str(gpSet.get("code", "")).replace(".", "_"))
		return
	var gpRes: GPIOResult = GPCMemberRoster.gpApplyToArchive(gpArchivePath, gpMembers, gpName)
	if not gpRes.gpIsOk():
		_gpSay(gpRes.gpMessageKey)
		return
	gpFirstRunDone.emit(gpName, true)
	queue_free()


# Cancel / close: report honestly; the coordinator exits back to the manager.
# 取消 / 关闭：如实上报；协调者退回项目管理器。
func _gpOnCancel() -> void:
	gpFirstRunDone.emit("", false)
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
