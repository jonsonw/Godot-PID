class_name GPLoginDialog
extends Window
# Copyright © 2026 Jonson Wang
# Login dialog (W14 T4a, ADR-40 D2; v1.3 credential model, ADR-48 rules).
# 登录对话框（W14 T4a，ADR-40 D2；v1.3 凭据模型，遵守 ADR-48 准则）。
#
# v1.3 MODEL / v1.3 模型（2026-11-18 用户拍板）：VERIFY only — the manager assigns the
# username AND the password, and the credential hash lives in the member entry (carried
# by the archive). There is NO first-login setup; the old confirm/display fields are gone.
# v1.3 模型（2026-11-18 用户拍板）：**纯验证** —— 管理者分配用户名与密码，凭据哈希在成员
# 条目里（随存档走）。没有首登设密；旧的确认/显示名输入框已移除。
#
# ADR-48 compliance / 遵守 ADR-48：
# - a Window node defaults to visible=true — created hidden, shown ONLY via popup_centered;
# - Window 节点默认 visible=true —— 创建即隐藏，显示恒走 popup_centered；
# - unresizable=false explicitly; content root FULL_RECT via set_anchors_and_offsets_preset (R8).
# - unresizable=false 显式声明；内容根 FULL_RECT 用 set_anchors_and_offsets_preset（R8）。
#
# R7: callbacks are member functions, no lambda held across frames. The member roster is
# an injectable var (test seam) so tests never depend on a real archive.
# R7：回调一律成员函数，跨帧不持 lambda。成员名单为可注入成员（测试缝），
# 测试绝不依赖真实存档。

# Emitted once per attempt outcome; "" user = cancelled / failed. The coordinator decides
# what happens next (session user, status line) — the dialog only reports.
# 每次尝试产出一次信号；gpUser 为空串 = 取消 / 失败。后续（会话用户、状态行）归协调者
# —— 对话框只上报。
signal gpLoginDone(gpUser: String, gpOk: bool)

# Roster users allowed to sign in (enabled members of the open archive).
# 允许登录的名单用户（打开工程的启用成员）。
var gpAllowedUsers: Array[String] = []

# Test seam: the FULL member roster (entries carry the credential hashes).
# 测试缝：完整成员名单（条目携带凭据哈希）。
var gpMembers: Array = []

var gpUserEdit: LineEdit
var gpPassEdit: LineEdit
var gpInfoLabel: Label


# Build the form. / 构建表单。
func gpSetup(gpAllowed: Array[String], gpMembers: Array) -> void:
	gpAllowedUsers = gpAllowed
	gpMembers = gpMembers
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


# Submit: pure verify against the member entries (in roster → enabled → hash).
# 提交：对成员条目做纯验证（在册 → 启用 → 哈希）。
func _gpOnSubmit() -> void:
	var gpUser: String = gpUserEdit.text.strip_edges()
	if not gpAllowedUsers.has(gpUser):
		_gpSay("identity.not_member")
		return
	var gpVerdict: Dictionary = GPCMemberRoster.gpVerifyLogin(gpMembers, gpUser,
		gpPassEdit.text)
	if bool(gpVerdict.get("ok", false)):
		_gpFinish(gpUser)
	else:
		_gpSay("identity.err_" + str(gpVerdict.get("code", "")).replace(".", "_"))


# Cancel / close: report honestly, the coordinator keeps the "local" identity.
# 取消 / 关闭：如实上报，协调者保持「本地」身份。
func _gpOnCancel() -> void:
	gpLoginDone.emit("", false)
	queue_free()


# Success: report and close. / 成功：上报并关闭。
func _gpFinish(gpUser: String) -> void:
	gpLoginDone.emit(gpUser, true)
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
	gpEdit.custom_minimum_size = Vector2(180, 0)
	gpGrid.add_child(gpEdit)
