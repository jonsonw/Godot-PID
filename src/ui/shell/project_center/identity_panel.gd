class_name GPIdentityPanel
extends Window
# Copyright © 2026 Jonson Wang
# Identity panel (W14 T4b, v1.3 credential model, inline-edit iteration): the manager-side
# roster view of the SELECTED archive. The table IS the editor (user request 2026-11-18):
# username / enabled / display name edit in place, roles pick from a dropdown, and the
# password column shows a mask — password changes ride the dedicated row below.
# 身份面板（W14 T4b，v1.3 凭据模型，内联编辑迭代）：对**选中存档**的管理者侧名单视图。
# 表格**就是**编辑器（用户要求 2026-11-18）：用户名 / 启用 / 显示名就地编辑，角色走下拉，
# 密码列显示遮罩 —— 改密码走下方专用行。
#
# v1.3 MODEL / v1.3 模型：the manager IS the registrar — adding a member assigns
# username + initial password + roles; the credential hash lives in the member entry and
# travels with the archive. Every change still goes through GPCMemberRoster.gpApplyToArchive
# (read → swap → RE-STAMP revision → atomic write).
# 管理者**就是**登记人 —— 添加成员即分配用户名 + 初始密码 + 角色；凭据哈希随存档走。
# 所有变更仍经 GPCMemberRoster.gpApplyToArchive（读 → 换 → 重盖修订 → 原子写）。
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
var gpRoleOption: OptionButton
var gpNewPassEdit: LineEdit
var gpInfoLabel: Label
var gpRoleMenu: PopupMenu
# The user name the roles popup currently targets. / 角色弹出菜单当前指向的用户名。
var _gpRoleMenuUser: String = ""


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
	# Roster table: username / roles / enabled / display name / password mask.
	# hide_root kills the phantom blank first row (on-device bug 2026-11-18).
	# 名单表：用户名 / 角色 / 启用 / 显示名 / 密码遮罩。hide_root 消灭幻影空首行
	#（实机缺陷 2026-11-18）。
	gpTable = Tree.new()
	gpTable.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpTable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpTable.hide_root = true
	gpRoot.add_child(gpTable)
	gpTable.columns = 5
	gpTable.set_column_title(0, I18n.gpTr("identity.user"))
	gpTable.set_column_title(1, I18n.gpTr("identity.roles"))
	gpTable.set_column_title(2, I18n.gpTr("identity.enabled"))
	gpTable.set_column_title(3, I18n.gpTr("identity.display_name_col"))
	gpTable.set_column_title(4, I18n.gpTr("identity.password"))
	gpTable.set_column_titles_visible(true)
	# R7: member-function callbacks. Inline edits and the roles dropdown both land here.
	# R7：成员函数回调。内联编辑与角色下拉都汇到这里。
	gpTable.item_edited.connect(_gpOnEdited)
	gpTable.cell_selected.connect(_gpOnCellSelected)
	# The roles dropdown (one PopupMenu per panel, shown per click — R7, no closures).
	# 角色下拉（每面板一个 PopupMenu，按次显示 —— R7，不用闭包）。
	gpRoleMenu = PopupMenu.new()
	add_child(gpRoleMenu)
	for gpI in range(GPProjectContainerV4.GP_ROLES.size()):
		gpRoleMenu.add_item(I18n.gpTr("identity.role_" + str(GPProjectContainerV4.GP_ROLES[gpI])), gpI)
	gpRoleMenu.id_pressed.connect(_gpOnRolePicked)
	# Add row: username + initial password + roles dropdown + button (v1.3: the manager
	# assigns the credential). / 添加行：用户名 + 初始密码 + 角色下拉 + 按钮
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
	gpRoleOption = OptionButton.new()
	for gpI in range(GPProjectContainerV4.GP_ROLES.size()):
		gpRoleOption.add_item(I18n.gpTr("identity.role_" + str(GPProjectContainerV4.GP_ROLES[gpI])), gpI)
	gpRoleOption.select(1)  # designer / 设计者
	gpAddRow.add_child(gpRoleOption)
	var gpAddBtn: Button = Button.new()
	gpAddBtn.text = I18n.gpTr("identity.roster_add")
	gpAddBtn.disabled = not GPPermissions.gpCanManageMembers()
	gpAddBtn.pressed.connect(_gpOnAdd)
	gpAddRow.add_child(gpAddBtn)
	# Password row: re-assign the password of the SELECTED row (the mask column is
	# read-only on purpose — a password never sits in an inline table).
	# 密码行：重设**选中行**的密码（遮罩列刻意只读 —— 密码绝不进内联表格）。
	var gpPassRow: HBoxContainer = HBoxContainer.new()
	gpRoot.add_child(gpPassRow)
	gpNewPassEdit = LineEdit.new()
	gpNewPassEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpNewPassEdit.secret = true
	gpNewPassEdit.placeholder_text = I18n.gpTr("identity.new_password")
	gpPassRow.add_child(gpNewPassEdit)
	var gpPassBtn: Button = Button.new()
	gpPassBtn.text = I18n.gpTr("identity.roster_reset_pw")
	gpPassBtn.disabled = not GPPermissions.gpCanManageMembers()
	gpPassBtn.pressed.connect(_gpOnResetPassword)
	gpPassRow.add_child(gpPassBtn)
	# Action row: remove / close. / 动作行：移除 / 关闭。
	var gpActRow: HBoxContainer = HBoxContainer.new()
	gpActRow.alignment = BoxContainer.ALIGNMENT_END
	gpRoot.add_child(gpActRow)
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
	if gpRootItem == null:
		return
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
		if gpItem == null:
			continue
		# The identity anchor: inline edits resolve through it even after a rename.
		# 身份锚点：改名后内联编辑仍能据此定位。
		gpItem.set_meta("gp_user", gpUser)
		gpItem.set_text(0, gpUser)
		gpItem.set_editable(0, true)
		var gpRoleTexts: PackedStringArray = PackedStringArray()
		var gpRolesRaw: Variant = gpMDict.get("roles", null)
		if gpRolesRaw is Array:
			for gpR in gpRolesRaw as Array:
				gpRoleTexts.append(I18n.gpTr("identity.role_" + str(gpR)))
		gpItem.set_text(1, " / ".join(gpRoleTexts))
		# Enabled = a real checkbox cell; the toggle rides item_edited. / 启用 = 真勾选
		# 单元格；切换经 item_edited。
		gpItem.set_cell_mode(2, TreeItem.CELL_MODE_CHECK)
		gpItem.set_checked(2, bool(gpMDict.get("enabled", true)))
		gpItem.set_editable(2, true)
		gpItem.set_text(3, str(gpMDict.get("display_name", "")))
		gpItem.set_editable(3, true)
		# Password mask: readable-only on purpose. / 密码遮罩：刻意只读。
		gpItem.set_text(4, "●●●●●●" if str(gpMDict.get("hash", "")) != "" else "—")


# The roles dropdown: clicked the roles cell of a row -> offer the three roles.
# Godot 4's cell_selected emits ZERO arguments — the selected cell comes from
# get_selected()/get_selected_column() (arg mismatch = the callable aborts and the
# dropdown never opens, on-device bug 2026-11-18).
# 角色下拉：点击某行的角色单元格 -> 弹出三角色。Godot 4 的 cell_selected **零参数**，
# 选中单元格经 get_selected()/get_selected_column() 取（参数不匹配 = 回调中断、下拉弹不出，
# 实机缺陷 2026-11-18）。
func _gpOnCellSelected() -> void:
	var gpItem: TreeItem = gpTable.get_selected()
	if gpItem == null or gpTable.get_selected_column() != 1:
		return
	_gpRoleMenuUser = str(gpItem.get_meta("gp_user", ""))
	if _gpRoleMenuUser == "":
		return
	gpRoleMenu.position = gpTable.get_screen_position() + gpTable.get_local_mouse_position()
	gpRoleMenu.popup()


# A role picked from the dropdown -> single-role assignment on the targeted row.
# 下拉选定角色 -> 对目标行做**单角色**赋值。
func _gpOnRolePicked(gpId: int) -> void:
	if _gpRoleMenuUser == "":
		return
	var gpPlan: Dictionary = GPCMemberRoster.gpSetRoles(gpMembers, _gpRoleMenuUser,
		[str(GPProjectContainerV4.GP_ROLES[gpId])])
	_gpRoleMenuUser = ""
	if not bool(gpPlan.get("ok", false)):
		_gpSay(str(gpPlan.get("code", "")))
		return
	_gpApply()


# Dispatch an inline edit: 0 = rename, 2 = enabled, 3 = display name.
# The handler runs INSIDE the Tree's own item_edited emission — rebuilding the table
# there (clear + create_item) makes create_item return null and set_meta crashes
# (on-device bug 2026-11-18). So: snapshot PLAIN DATA here, defer every mutation and
# reload out of the emission frame.
# 分派内联编辑：0 = 改名，2 = 启停，3 = 显示名。
# 本回调运行在 Tree 自身 item_edited 发射**中途** —— 在这里重建表格（clear + create_item）
# 会让 create_item 返回 null、set_meta 崩溃（实机缺陷 2026-11-18）。因此：此处只快照
# **纯数据**，所有变更与重建延迟出信号帧。
func _gpOnEdited() -> void:
	var gpItem: TreeItem = gpTable.get_edited()
	if gpItem == null:
		return
	var gpCol: int = gpTable.get_edited_column()
	var gpOld: String = str(gpItem.get_meta("gp_user", ""))
	if gpOld == "":
		return
	call_deferred("_gpOnEditedDeferred", gpCol, gpOld, gpItem.get_text(0),
		gpItem.is_checked(2), gpItem.get_text(3))


# Deferred twin of _gpOnEdited: safe to rebuild the tree here — the emission is done.
# _gpOnEdited 的延迟孪生：此刻重建表格安全 —— 信号发射已结束。
func _gpOnEditedDeferred(gpCol: int, gpOld: String, gpNewUser: String,
		gpChecked: bool, gpDisplay: String) -> void:
	match gpCol:
		0:
			# No-op commit (double-click then Enter without a change): stay silent.
			# 无变化提交（双击后直接回车）：静默忽略。
			if gpNewUser == gpOld:
				return
			var gpPlan: Dictionary = GPCMemberRoster.gpRenameUser(gpMembers, gpOld,
				gpNewUser)
			if bool(gpPlan.get("ok", false)):
				_gpApply()
			else:
				_gpSay(str(gpPlan.get("code", "")))
				gpReload()
		2:
			var gpPlan: Dictionary = GPCMemberRoster.gpSetEnabled(gpMembers, gpOld,
				gpChecked)
			if bool(gpPlan.get("ok", false)):
				_gpApply()
			else:
				_gpSay(str(gpPlan.get("code", "")))
				gpReload()
		3:
			var gpM: Dictionary = GPCMemberRoster.gpFind(gpMembers, gpOld)
			if gpM.is_empty():
				return
			gpM["display_name"] = gpDisplay
			_gpApply()


# Add: validate via the pure CRUD (password included), then apply to the archive.
# 添加：经纯 CRUD 校验（含密码），然后落盘。
func _gpOnAdd() -> void:
	var gpPlan: Dictionary = GPCMemberRoster.gpAdd(gpMembers, gpUserEdit.text,
		gpPassEdit.text, [str(GPProjectContainerV4.GP_ROLES[gpRoleOption.selected])])
	if not bool(gpPlan.get("ok", false)):
		_gpSay(str(gpPlan.get("code", "")))
		return
	_gpApply()


# Re-assign the password of the SELECTED row; roles / display name / enabled stay.
# 重设**选中行**的密码；角色 / 显示名 / 启停保持不变。
func _gpOnResetPassword() -> void:
	var gpItem: TreeItem = gpTable.get_selected()
	if gpItem == null:
		_gpSay(GPCMemberRoster.GP_ERR_NOT_FOUND)
		return
	var gpUser: String = str(gpItem.get_meta("gp_user", ""))
	var gpM: Dictionary = GPCMemberRoster.gpFind(gpMembers, gpUser)
	if gpM.is_empty():
		_gpSay(GPCMemberRoster.GP_ERR_NOT_FOUND)
		return
	var gpRoles: Array = []
	var gpRolesRaw: Variant = gpM.get("roles", null)
	if gpRolesRaw is Array:
		gpRoles = (gpRolesRaw as Array).duplicate(true)
	var gpPlan: Dictionary = GPCMemberRoster.gpSetCredential(gpMembers, gpUser,
		gpNewPassEdit.text, str(gpM.get("display_name", "")), gpRoles)
	if not bool(gpPlan.get("ok", false)):
		_gpSay(str(gpPlan.get("code", "")))
		return
	gpNewPassEdit.text = ""
	_gpApply()


# Remove the selected member. / 移除选中成员。
func _gpOnRemove() -> void:
	var gpItem: TreeItem = gpTable.get_selected()
	if gpItem == null:
		_gpSay(GPCMemberRoster.GP_ERR_NOT_FOUND)
		return
	var gpPlan: Dictionary = GPCMemberRoster.gpRemove(gpMembers,
		str(gpItem.get_meta("gp_user", "")))
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


# Map a machine code to an honest info line. / 把机器码映射为如实的提示行。
func _gpSay(gpCode: String) -> void:
	var gpKey: String = "identity.err_" + gpCode.replace(".", "_")
	gpInfoLabel.text = I18n.gpTr(gpKey)
