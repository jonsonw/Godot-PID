class_name GPLoginDialog
extends Window
# Copyright © 2026 Jonson Wang
# Login / first-time credential setup dialog (W14 T4a/T4b, ADR-40 D2/D4, ADR-48 rules).
# 登录 / 首次凭据设置对话框（W14 T4a/T4b，ADR-40 D2/D4，遵守 ADR-48 准则）。
#
# MODES / 两种模式（per submit, resolved from the store）：
# - VERIFY: the user has a local credential -> password is checked against it.
# - SETUP: the user is on the roster but has NO local credential -> "在册即批准"：
#   first-time set-password (confirm field + minimum length), then the credential is
#   created and the login succeeds.
# - VERIFY：用户在本机有凭据 -> 密码与凭据比对。
# - SETUP：用户在名单上但本机无凭据 -> 「在册即批准」：首次设密（确认输入 + 最短长度），
#   凭据创建后即登录成功。
#
# ADR-48 compliance / 遵守 ADR-48：
# - a Window node defaults to visible=true — created hidden, shown ONLY via popup_centered;
# - Window 节点默认 visible=true —— 创建即隐藏，显示恒走 popup_centered；
# - unresizable=false explicitly; content root FULL_RECT via set_anchors_and_offsets_preset (R8).
# - unresizable=false 显式声明；内容根 FULL_RECT 用 set_anchors_and_offsets_preset（R8）。
#
# R7: callbacks are member functions, no lambda held across frames. The credential store
# path is an injectable var (test seam) so tests never touch the real user:// store.
# R7：回调一律成员函数，跨帧不持 lambda。凭据库路径为可注入成员（测试缝），
# 测试绝不触碰真实 user:// 库。

# Emitted once per attempt outcome; "" user = cancelled / failed. The coordinator decides
# what happens next (session user, status line) — the dialog only reports.
# 每次尝试产出一次信号；gpUser 为空串 = 取消 / 失败。后续（会话用户、状态行）归协调者
# —— 对话框只上报。
signal gpLoginDone(gpUser: String, gpOk: bool)

# Roster users allowed to sign in (enabled members of the open archive).
# 允许登录的名单用户（打开工程的启用成员）。
var gpAllowedUsers: Array[String] = []

# Test seam: the credential store path (never the real store in tests).
# 测试缝：凭据库路径（测试绝不触碰真实库）。
var gpStorePath: String = GPCredentialStore.GP_STORE_PATH

var gpUserEdit: LineEdit
var gpPassEdit: LineEdit
var gpConfirmEdit: LineEdit
var gpDisplayEdit: LineEdit
var gpInfoLabel: Label


# Build the form. / 构建表单。
func gpSetup(gpAllowed: Array[String]) -> void:
	gpAllowedUsers = gpAllowed
	title = I18n.gpTr("identity.login_title")
	# ADR-48: created hidden; shown via popup_centered by the caller. Resizable per准则.
	# ADR-48：创建即隐藏；显示由调用方走 popup_centered。按准则可缩放。
	visible = false
	unresizable = false
	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(gpRoot)
	var gpForm: GridContainer = GridContainer.new()
	gpForm.columns = 2
	gpRoot.add_child(gpForm)
	gpUserEdit = LineEdit.new()
	_gpAddRow(gpForm, "identity.user", gpUserEdit)
	gpPassEdit = LineEdit.new()
	gpPassEdit.secret = true
	_gpAddRow(gpForm, "identity.password", gpPassEdit)
	gpConfirmEdit = LineEdit.new()
	gpConfirmEdit.secret = true
	_gpAddRow(gpForm, "identity.password_confirm", gpConfirmEdit)
	gpDisplayEdit = LineEdit.new()
	_gpAddRow(gpForm, "identity.display_name", gpDisplayEdit)
	gpInfoLabel = Label.new()
	gpInfoLabel.text = I18n.gpTr("identity.login_prompt")
	gpInfoLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpRoot.add_child(gpInfoLabel)
	var gpButtons: HBoxContainer = HBoxContainer.new()
	gpButtons.alignment = BoxContainer.ALIGNMENT_END
	gpRoot.add_child(gpButtons)
	var gpOk: Button = Button.new()
	gpOk.text = I18n.gpTr("identity.login")
	gpOk.pressed.connect(_gpOnSubmit)
	gpButtons.add_child(gpOk)
	var gpCancel: Button = Button.new()
	gpCancel.text = I18n.gpTr("dialog.cancel")
	gpCancel.pressed.connect(_gpOnCancel)
	gpButtons.add_child(gpCancel)
	# R7: member-function connection, no lambda across frames.
	# R7：成员函数连接，跨帧不持 lambda。
	close_requested.connect(_gpOnCancel)
	# The first enabled roster user prefills the field (typical case: one workstation,
	# one primary user). / 第一个启用成员预填输入框（典型情形：一机一主用户）。
	if not gpAllowedUsers.is_empty():
		gpUserEdit.text = gpAllowedUsers[0]


# Submit: resolve mode from the store, then verify or set up.
# 提交：按库解析模式，然后校验或设置。
func _gpOnSubmit() -> void:
	var gpUser: String = gpUserEdit.text.strip_edges()
	if not gpAllowedUsers.has(gpUser):
		_gpSay("identity.not_member")
		return
	var gpPassword: String = gpPassEdit.text
	if GPCredentialStore.gpHasUser(gpUser, gpStorePath):
		# VERIFY. / 校验。
		if GPCredentialStore.gpVerifyLogin(gpUser, gpPassword, gpStorePath):
			_gpFinish(gpUser)
		else:
			_gpSay("identity.bad_credentials")
		return
	# SETUP ("在册即批准"): confirm + minimum length, then create the credential.
	# 设置（「在册即批准」）：确认输入 + 最短长度，然后创建凭据。
	if gpPassword != gpConfirmEdit.text:
		_gpSay("identity.mismatch")
		return
	if not GPIdentityCredentials.gpIsValidPassword(gpPassword):
		_gpSay("identity.too_short", [GPIdentityCredentials.GP_MIN_PASSWORD_LEN])
		return
	if GPCredentialStore.gpSetCredential(gpUser, gpPassword,
			gpDisplayEdit.text.strip_edges(), gpStorePath):
		_gpFinish(gpUser)
	else:
		_gpSay("identity.store_fail")


# Cancel / close: report honestly, the coordinator keeps the "local" identity.
# 取消 / 关闭：如实上报，协调者保持「本地」身份。
func _gpOnCancel() -> void:
	gpLoginDone.emit("", false)
	queue_free()


# Success: report and close. / 成功：上报并关闭。
func _gpFinish(gpUser: String) -> void:
	gpLoginDone.emit(gpUser, true)
	queue_free()


# Show a reason in the info line (i18n key + optional args; never a bare literal).
# 在提示行显示原因（i18n 键 + 可选参数；绝不用裸字面串）。
func _gpSay(gpKey: String, gpArgs: Array = []) -> void:
	gpInfoLabel.text = I18n.gpTr(gpKey) % gpArgs if not gpArgs.is_empty() else I18n.gpTr(gpKey)


# One label+edit row in the grid. / 网格中的一行标签 + 输入框。
func _gpAddRow(gpGrid: GridContainer, gpLabelKey: String, gpEdit: LineEdit) -> void:
	var gpLabel: Label = Label.new()
	gpLabel.text = I18n.gpTr(gpLabelKey)
	gpGrid.add_child(gpLabel)
	gpEdit.custom_minimum_size = Vector2(180, 0)
	gpGrid.add_child(gpEdit)
