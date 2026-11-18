class_name GPIdentityPanel
extends Window
# Copyright © 2026 Jonson Wang
# Identity panel (W14 T4b, v1.3 credential model): the manager-side roster view of the
# SELECTED archive — member table (user / roles / enabled / display name), add-with-
# password, apply-changes on the selected row (password / display name / roles), and
# enable-disable / remove.
# 身份面板（W14 T4b，v1.3 凭据模型）：对**选中存档**的管理者侧名单视图 —— 成员表
#（用户 / 角色 / 启停 / 显示名）、带密码添加、对选中行「应用变更」（密码 / 显示名 / 角色），
# 以及启停 / 移除。
#
# v1.3 MODEL / v1.3 模型（2026-11-18 用户拍板）：the manager IS the registrar — adding a
# member assigns username + initial password + roles at once; the credential hash lives
# in the member entry and travels with the archive (every workstation can verify it).
# The table stays READ-ONLY (a Tree is not a spreadsheet) — all edits go through the
# controls below, applied to the SELECTED row.
# v1.3 模型（2026-11-18 用户拍板）：管理者**就是**登记人 —— 添加成员即同时分配用户名 +
# 初始密码 + 角色；凭据哈希在成员条目里、随存档走（每个工作站都能验证）。表格保持**只读**
#（Tree 不是电子表格）—— 所有编辑经下方控件作用于**选中行**。
#
# SAFETY / 安全：every change goes through GPCMemberRoster.gpApplyToArchive (read → swap
# members → RE-STAMP the revision — the roster participates in the content hash → atomic
# write). The panel never edits the sheet payload.
# 安全：每次变更都经 GPCMemberRoster.gpApplyToArchive（读 → 换名单 → **重盖修订**
#（名单参与内容哈希）→ 原子写）。面板绝不触碰图纸载荷。
#
# ADR-48: created hidden, shown via popup_centered, unresizable=false, content root
# FULL_RECT (R8). R7: member-function callbacks, no lambdas across frames.
# ADR-48：创建即隐藏、显示走 popup_centered、unresizable=false、内容根 FULL_RECT（R8）。
# R7：成员函数回调，跨帧不持 lambda。

var gpArchivePath: String = ""
# Working copy of the roster — mutations land on disk ONLY via the apply blade.
# 名单工作副本 —— 变更**只有**经落盘刀才落盘。
var gpMembers: Array = []

var gpTable: Tree
var gpUserEdit: LineEdit
var gpPassEdit: LineEdit
var gpNewPassEdit: LineEdit
var gpDisplayEdit: LineEdit
var gpRoleChecks: Dictionary = {}
var gpInfoLabel: Label


# Open on one archive. / 面向某个存档打开。
func gpSetup(gpPath: String) -> void:
	gpArchivePath = gpPath
	title = I18n.gpTr("identity.panel_title")
	visible = false
	unresizable = false
	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(gpRoot)
	# Info line: the honest W14/v1.3 boundary. / 提示行：诚实的 W14/v1.3 边界。
	gpInfoLabel = Label.new()
	gpInfoLabel.text = I18n.gpTr("identity.panel_info")
	gpInfoLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpRoot.add_child(gpInfoLabel)
	# Roster table. hide_root kills the phantom blank first row (on-device bug
	# 2026-11-18: the invisible Tree root painted as an un-editable "member").
	# 名单表。hide_root 消灭幻影空首行（实机缺陷 2026-11-18：不可见的 Tree 根
	# 被画成一行「不可编辑的成员」）。
	gpTable = Tree.new()
	gpTable.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpTable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpTable.hide_root = true
	gpRoot.add_child(gpTable)
	gpTable.columns = 4
	gpTable.set_column_title(0, I18n.gpTr("identity.user"))
	gpTable.set_column_title(1, I18n.gpTr("identity.roles"))
	gpTable.set_column_title(2, I18n.gpTr("identity.enabled"))
	gpTable.set_column_title(3, I18n.gpTr("identity.display_name_col"))
	gpTable.set_column_titles_visible(true)
	# Selecting a row mirrors its roles + display name into the edit controls (R7:
	# member-function callback). / 选中行时把该行角色与显示名镜像进编辑控件
	#（R7：成员函数回调）。
	gpTable.item_selected.connect(_gpOnRowSelected)
	# Add row: username + initial password + role checkboxes + button (v1.3: the manager
	# assigns the credential). / 添加行：用户名 + 初始密码 + 角色勾选 + 按钮
	#（v1.3：管理者分配凭据）。
	var gpAddRow: HBoxContainer = HBoxContainer.new()
	gpRoot.add_child(gpAddRow)
	gpUserEdit = LineEdit.new()
	gpUserEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpUserEdit.placeholder_text = I18n.gpTr("identity.user")
	gpAddRow.add_child(gpUserEdit)
	gpPassEdit = LineEdit.new()
	gpPassEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpPassEdit.secret = true
	gpPassEdit.placeholder_text = I18n.gpTr("identity.password_initial")
	gpAddRow.add_child(gpPassEdit)
	for gpRole in GPProjectContainerV4.GP_ROLES:
		var gpCheck: CheckBox = CheckBox.new()
		gpCheck.text = I18n.gpTr("identity.role_" + str(gpRole))
		if str(gpRole) == "designer":
			gpCheck.button_pressed = true
		gpAddRow.add_child(gpCheck)
		gpRoleChecks[str(gpRole)] = gpCheck
	var gpAddBtn: Button = Button.new()
	gpAddBtn.text = I18n.gpTr("identity.roster_add")
	gpAddBtn.disabled = not GPPermissions.gpCanManageMembers()
	gpAddBtn.pressed.connect(_gpOnAdd)
	gpAddRow.add_child(gpAddBtn)
	# Edit row: new password (blank = keep) + display name + apply-to-selected.
	# 编辑行：新密码（空 = 不改）+ 显示名 + 应用到选中行。
	var gpEditRow: HBoxContainer = HBoxContainer.new()
	gpRoot.add_child(gpEditRow)
	gpNewPassEdit = LineEdit.new()
	gpNewPassEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpNewPassEdit.secret = true
	gpNewPassEdit.placeholder_text = I18n.gpTr("identity.new_password")
	gpEditRow.add_child(gpNewPassEdit)
	gpDisplayEdit = LineEdit.new()
	gpDisplayEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpDisplayEdit.placeholder_text = I18n.gpTr("identity.display_name_col")
	gpEditRow.add_child(gpDisplayEdit)
	var gpApplyBtn: Button = Button.new()
	gpApplyBtn.text = I18n.gpTr("identity.roster_apply_changes")
	gpApplyBtn.disabled = not GPPermissions.gpCanManageMembers()
	gpApplyBtn.pressed.connect(_gpOnApplyChanges)
	gpEditRow.add_child(gpApplyBtn)
	# Action row: enable-disable / remove. / 动作行：启停 / 移除。
	var gpActRow: HBoxContainer = HBoxContainer.new()
	gpActRow.alignment = BoxContainer.ALIGNMENT_END
	gpRoot.add_child(gpActRow)
	var gpToggleBtn: Button = Button.new()
	gpToggleBtn.text = I18n.gpTr("identity.roster_toggle")
	gpToggleBtn.disabled = not GPPermissions.gpCanManageMembers()
	gpToggleBtn.pressed.connect(_gpOnToggle)
	gpActRow.add_child(gpToggleBtn)
	var gpRemoveBtn: Button = Button.new()
	gpRemoveBtn.text = I18n.gpTr("identity.roster_remove")
	gpRemoveBtn.disabled = not GPPermissions.gpCanManageMembers()
	gpRemoveBtn.pressed.connect(_gpOnRemove)
	gpActRow.add_child(gpRemoveBtn)
	var gpCloseBtn: Button = Button.new()
	gpCloseBtn.text = I18n.gpTr("dialog.close")
	gpCloseBtn.pressed.connect(queue_free)
	gpActRow.add_child(gpCloseBtn)
	gpReload()


# Re-read the roster from the archive and rebuild the table.
# 从存档重读名单并重建表格。
func gpReload() -> void:
	gpMembers = []
	gpTable.clear()
	var gpRootItem: TreeItem = gpTable.create_item()
	var gpHeader: GPIOResult = GPProjectIO.gpReadHeader(gpArchivePath)
	if gpHeader.gpIsOk():
		var gpRaw: Variant = (gpHeader.gpPayload as Dictionary).get("members", null)
		if gpRaw is Array:
			gpMembers = gpRaw as Array
	for gpM in gpMembers:
		if not (gpM is Dictionary):
			continue
		var gpMDict: Dictionary = gpM
		var gpUser: String = str(gpMDict.get("user", ""))
		var gpItem: TreeItem = gpTable.create_item(gpRootItem)
		gpItem.set_text(0, gpUser)
		var gpRoleTexts: PackedStringArray = PackedStringArray()
		var gpRolesRaw: Variant = gpMDict.get("roles", null)
		if gpRolesRaw is Array:
			for gpR in gpRolesRaw as Array:
				gpRoleTexts.append(I18n.gpTr("identity.role_" + str(gpR)))
		gpItem.set_text(1, " / ".join(gpRoleTexts))
		gpItem.set_text(2, I18n.gpTr("identity.yes") if bool(gpMDict.get("enabled", true)) else I18n.gpTr("identity.no"))
		# v1.3: the display name is a manager-assigned fact in the member entry.
		# v1.3：显示名是成员条目里管理者分配的事实。
		gpItem.set_text(3, str(gpMDict.get("display_name", "")))


# The roles currently ticked in the shared checkbox row. / 共用勾选行当前勾中的角色。
func _gpTickedRoles() -> Array:
	var gpRoles: Array = []
	for gpRole in GPProjectContainerV4.GP_ROLES:
		if (gpRoleChecks[str(gpRole)] as CheckBox).button_pressed:
			gpRoles.append(str(gpRole))
	return gpRoles


# Add: validate via the pure CRUD (password included), then apply to the archive. The
# optional display name rides the shared display-name field.
# 添加：经纯 CRUD 校验（含密码），然后落盘。可选显示名复用共用显示名框。
func _gpOnAdd() -> void:
	var gpPlan: Dictionary = GPCMemberRoster.gpAdd(gpMembers, gpUserEdit.text,
		gpPassEdit.text, _gpTickedRoles(), gpDisplayEdit.text.strip_edges())
	if not bool(gpPlan.get("ok", false)):
		_gpSay(str(gpPlan.get("code", "")))
		return
	_gpApply()


# Apply changes to the SELECTED row: new password (blank = keep), display name, roles.
# 对**选中行**应用变更：新密码（空 = 不改）、显示名、角色。
func _gpOnApplyChanges() -> void:
	var gpUser: String = _gpSelectedUser()
	if gpUser == "":
		_gpSay(GPCMemberRoster.GP_ERR_NOT_FOUND)
		return
	var gpPlan: Dictionary = GPCMemberRoster.gpSetCredential(gpMembers, gpUser,
		gpNewPassEdit.text, gpDisplayEdit.text.strip_edges(), _gpTickedRoles())
	if not bool(gpPlan.get("ok", false)):
		_gpSay(str(gpPlan.get("code", "")))
		return
	gpNewPassEdit.text = ""
	_gpApply()


# Mirror the selected row's roles + display name into the edit controls, so "apply
# changes" edits what the user sees. / 把选中行的角色与显示名镜像进编辑控件，
# 让「应用变更」编辑的就是用户看到的内容。
func _gpOnRowSelected() -> void:
	var gpUser: String = _gpSelectedUser()
	if gpUser == "":
		return
	var gpM: Dictionary = GPCMemberRoster.gpFind(gpMembers, gpUser)
	if gpM.is_empty():
		return
	var gpRolesRaw: Variant = gpM.get("roles", null)
	for gpRole in GPProjectContainerV4.GP_ROLES:
		var gpTick: bool = false
		if gpRolesRaw is Array:
			gpTick = (gpRolesRaw as Array).has(str(gpRole))
		(gpRoleChecks[str(gpRole)] as CheckBox).button_pressed = gpTick
	gpDisplayEdit.text = str(gpM.get("display_name", ""))
	gpNewPassEdit.text = ""


# Toggle the selected member's enabled flag. / 启停选中成员。
func _gpOnToggle() -> void:
	var gpUser: String = _gpSelectedUser()
	if gpUser == "":
		return
	var gpM: Dictionary = GPCMemberRoster.gpFind(gpMembers, gpUser)
	var gpPlan: Dictionary = GPCMemberRoster.gpSetEnabled(gpMembers, gpUser,
		not bool(gpM.get("enabled", true)))
	if not bool(gpPlan.get("ok", false)):
		_gpSay(str(gpPlan.get("code", "")))
		return
	_gpApply()


# Remove the selected member. / 移除选中成员。
func _gpOnRemove() -> void:
	var gpUser: String = _gpSelectedUser()
	if gpUser == "":
		return
	var gpPlan: Dictionary = GPCMemberRoster.gpRemove(gpMembers, gpUser)
	if not bool(gpPlan.get("ok", false)):
		_gpSay(str(gpPlan.get("code", "")))
		return
	_gpApply()


# The apply blade + refresh INSIDE the success path, so the table never shows a ghost.
# 落盘刀 + 成功路径内刷新，表格永不显示幽灵行。
func _gpApply() -> void:
	var gpRes: GPIOResult = GPCMemberRoster.gpApplyToArchive(gpArchivePath, gpMembers,
		"local")
	if not gpRes.gpIsOk():
		_gpSay(gpRes.gpCode)
		return
	gpUserEdit.text = ""
	gpPassEdit.text = ""
	gpReload()


# The user name of the selected row. / 选中行的用户名。
func _gpSelectedUser() -> String:
	var gpItem: TreeItem = gpTable.get_selected()
	if gpItem == null:
		return ""
	return gpItem.get_text(0)


# Map a machine code to an honest info line. / 把机器码映射为如实的提示行。
func _gpSay(gpCode: String) -> void:
	var gpKey: String = "identity.err_" + gpCode.replace(".", "_")
	gpInfoLabel.text = I18n.gpTr(gpKey)
