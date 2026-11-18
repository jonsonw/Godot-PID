class_name GPLoginDialog
extends Window
# Copyright © 2026 Jonson Wang
# Login dialog (W14 T4a, ADR-40 D2; v1.3 credential model, ADR-48 rules).
# 登录对话框（W14 T4a，ADR-40 D2；v1.3 凭据模型，遵守 ADR-48 准则）。
#
# v1.3 MODEL / v1.3 模型：VERIFY only — the manager assigns the username AND the password,
# and the credential hash lives in the member entry (carried by the archive).
# 纯验证 —— 管理者分配用户名与密码，凭据哈希在成员条目里（随存档走）。
#
# LIVE ROSTER / 实时名单（on-device fix 2026-11-18）：every submit RE-READS the header
# from disk. The manager may edit the roster (identity panel) WHILE this dialog is open —
# a roster captured at open time went stale and answered "no such member" to a freshly
# added user.
# 每次提交都**重读**盘上头部。本对话框打开期间管理者可能正在身份面板改名单 ——
# 打开时捕获的名单会陈旧，对新加的用户答「没有该人员」。
#
# ADR-48 compliance / 遵守 ADR-48：
# - a Window node defaults to visible=true — created hidden, shown ONLY via popup_centered;
# - Window 节点默认 visible=true —— 创建即隐藏，显示恒走 popup_centered；
# - unresizable=false explicitly; content root FULL_RECT via set_anchors_and_offsets_preset (R8).
# - unresizable=false 显式声明；内容根 FULL_RECT 用 set_anchors_and_offsets_preset（R8）。
#
# R7: callbacks are member functions, no lambda held across frames.
# R7：回调一律成员函数，跨帧不持 lambda。

# Emitted once per attempt outcome; "" user = cancelled / failed. The coordinator decides
# what happens next (session user, status line, or the exit back to the manager) — the
# dialog only reports.
# 每次尝试产出一次信号；gpUser 为空串 = 取消 / 失败。后续（会话用户、状态行、退回管理
# 器）归协调者 —— 对话框只上报。
signal gpLoginDone(gpUser: String, gpOk: bool)

# The archive whose (live-re-read) roster authenticates this login.
# 由该存档（实时重读）的名单鉴权本次登录。
var gpArchivePath: String = ""

var gpUserEdit: LineEdit
var gpPassEdit: LineEdit
var gpInfoLabel: Label


# Build the form. gpPrefill = the first enabled roster user at open time (typical case:
# one workstation, one primary user) — prefill ONLY, never the source of truth.
# 构建表单。gpPrefill = 打开时的第一个启用成员（典型：一机一主用户）—— **仅预填**，
# 绝不作鉴权依据。
func gpSetup(gpArchivePath: String, gpPrefill: String) -> void:
	gpArchivePath = gpArchivePath
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
	gpUserEdit.text = gpPrefill


# Submit: re-read the roster from disk, then verify against the member entries
# (enabled → credential → hash). / 提交：重读盘上名单，然后对成员条目验证
#（启用 → 凭据 → 哈希）。
func _gpOnSubmit() -> void:
	var gpUser: String = gpUserEdit.text.strip_edges()
	var gpHeader: GPIOResult = GPProjectIO.gpReadHeader(gpArchivePath)
	if not gpHeader.gpIsOk():
		_gpSay("identity.roster_apply_fail")
		return
	var gpMembers: Array = []
	var gpRaw: Variant = (gpHeader.gpPayload as Dictionary).get("members", null)
	if gpRaw is Array:
		gpMembers = gpRaw as Array
	if not GPIdentityCoordinator.gpEnabledOf(gpMembers).has(gpUser):
		_gpSay("identity.not_member")
		return
	var gpVerdict: Dictionary = GPCMemberRoster.gpVerifyLogin(gpMembers, gpUser,
		gpPassEdit.text)
	if bool(gpVerdict.get("ok", false)):
		_gpFinish(gpUser)
	else:
		_gpSay("identity.err_" + str(gpVerdict.get("code", "")).replace(".", "_"))


# Cancel / close: report honestly; the coordinator exits back to the manager (v1.3: a
# multi-user project has no "local" bypass).
# 取消 / 关闭：如实上报；协调者退回项目管理器（v1.3：多人工程没有「本地」旁路）。
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
