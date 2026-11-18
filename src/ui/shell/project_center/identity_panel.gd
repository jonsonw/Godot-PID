class_name GPIdentityPanel
extends Window
# Copyright © 2026 Jonson Wang
# Identity panel (W14 T4b): the manager-side roster view of the SELECTED archive — member
# table (user / roles / enabled / local display name), add / enable-disable / remove, and
# the personal display-name editor for the session user.
# 身份面板（W14 T4b）：对**选中存档**的管理者侧名单视图 —— 成员表（用户 / 角色 / 启停 /
# 本机显示名）、添加 / 启停 / 移除，以及本人显示名编辑。
#
# REGISTRATION SEMANTICS / 注册语义（v1.2 方案 §2）：the roster IS the approval — the
# manager adds a member here; that person sets a password on their own machine at first
# login ("在册即批准"). Role CAPABILITY enforcement is W15 — until then this panel is
# gated by GPPermissions.gpCanManageMembers() only, and says so honestly in the info line.
# 名单**就是**审批 —— 管理者在此添加成员；对方在首次登录时于本机设密（「在册即批准」）。
# 角色**能力**强制是 W15 —— 届时本面板仅由 GPPermissions.gpCanManageMembers() 闸控，
# 并在提示行如实说明。
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
	# Info line: the honest W14 boundary. / 提示行：诚实的 W14 边界。
	gpInfoLabel = Label.new()
	gpInfoLabel.text = I18n.gpTr("identity.panel_info")
	gpInfoLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpRoot.add_child(gpInfoLabel)
	# Roster table. / 名单表。
	gpTable = Tree.new()
	gpTable.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpTable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpRoot.add_child(gpTable)
	gpTable.columns = 4
	gpTable.set_column_title(0, I18n.gpTr("identity.user"))
	gpTable.set_column_title(1, I18n.gpTr("identity.roles"))
	gpTable.set_column_title(2, I18n.gpTr("identity.enabled"))
	gpTable.set_column_title(3, I18n.gpTr("identity.display_name"))
	gpTable.set_column_titles_visible(true)
	# Add row: username + three role checkboxes + button. / 添加行：用户名 + 三个角色勾选 + 按钮。
	var gpAddRow: HBoxContainer = HBoxContainer.new()
	gpRoot.add_child(gpAddRow)
	gpUserEdit = LineEdit.new()
	gpUserEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpUserEdit.placeholder_text = I18n.gpTr("identity.user")
	gpAddRow.add_child(gpUserEdit)
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
		# Display name is a LOCAL credential-store fact (D4), shown read-only.
		# 显示名是**本机**凭据库事实（D4），只读呈现。
		gpItem.set_text(3, str(GPCredentialStore.gpUserRecord(gpUser).get("display_name", "")))


# Add: validate via the pure CRUD, then apply to the archive.
# 添加：经纯 CRUD 校验，然后落盘。
func _gpOnAdd() -> void:
	var gpRoles: Array = []
	for gpRole in GPProjectContainerV4.GP_ROLES:
		if (gpRoleChecks[str(gpRole)] as CheckBox).button_pressed:
			gpRoles.append(str(gpRole))
	var gpPlan: Dictionary = GPCMemberRoster.gpAdd(gpMembers, gpUserEdit.text, gpRoles)
	if not bool(gpPlan.get("ok", false)):
		_gpSay(str(gpPlan.get("code", "")))
		return
	_gpApply()


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
