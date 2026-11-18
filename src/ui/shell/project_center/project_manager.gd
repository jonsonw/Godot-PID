class_name GPProjectManager
extends Control

# The project manager MAIN SCREEN (W13 user feedback 2026-11-09): Godot-project-manager
# layout, adapted to P&ID. Replaces the old floating GPProjectCenterWindow — at boot the
# manager IS the app (boot_root.gpEnterManager); opening a project swaps it for the editor.
# 项目管理器**主屏**（W13 实机反馈 2026-11-09）：Godot 项目管理器布局，适配 P&ID。
# 取代旧的浮动式 GPProjectCenterWindow —— 启动时管理器**就是**应用（boot_root.gpEnterManager）；
# 打开工程后由编辑器换入。
#
# LAYOUT (mirrors the Godot PM, P&ID-adapted) / 布局（对照 Godot 管理器，P&ID 适配）：
# - Top bar: brand + section tabs (项目 live / 资产 W21+ / 身份 W14).
# - Toolbar: 创建 / 导入 / 扫描 / 筛选 / 排序（最近编辑 | 名称）.
# - Body: card list (scan ∪ recents, merged by the io layer) + right action rail
#   (打开图纸绘制 / 重命名 / 在文件夹中显示). The rail is the future home of the
#   项目运营管理 entry — that button ships when the ops module exists (A10: no lying UI);
#   the sidebar slot is reserved, not faked.
#   （右栏是将来「项目运营管理」入口的家 —— 该按钮随运营模块落地（A10：界面不撒谎）；
#   栏位预留，不做假按钮。）
# - Bottom bar: scan dir + honest count.
#
# DIFFERENTIATORS vs Godot / 与 Godot 的刻意差异：
# cards show PROJECT attributes (owner / sheets / members), never an engine version.
# 卡片显示**工程属性**（业主 / 图纸 / 成员），绝不显示「引擎版本号」。
#
# i18n: static chrome rides the locale-change batch (gpTextBindings); cards are short-lived
# and translate at build time. / 静态陈设挂语言变更批刷；卡片短命、构建期翻译。

signal gp_open_project_requested(gpArchivePath: String)

const GP_SORT_RECENT: String = "recent"
const GP_SORT_NAME: String = "name"

var gpEntries: Array[Dictionary] = []
var gpSelectedPath: String = ""
var gpSortMode: String = GP_SORT_RECENT
var gpFilterText: String = ""

var gpCardsBox: VBoxContainer
var gpFilterEdit: LineEdit
var gpDirLabel: Label
var gpCountLabel: Label
var gpSideOpenBtn: Button
var gpSideRenameBtn: Button
var gpSideRevealBtn: Button
var gpSideDeleteBtn: Button
var gpSaveDialog: FileDialog
var gpOpenDialog: FileDialog
var gpRenameDialog: AcceptDialog
var gpRenameEdit: LineEdit
var gpDeleteDialog: ConfirmationDialog
var gpCtxMenu: PopupMenu
# Locale bindings for static texts: {node, prop, key, suffix?}.
# 静态文案的语言绑定：{node, prop, key, suffix?}。
var gpTextBindings: Array[Dictionary] = []


func _ready() -> void:
	# set_anchors_AND_OFFSETS_preset: anchors alone keep a fresh control at 0x0 — the
	# content then piles up min-size in the top-left (W13 on-device bug 2026-11-09).
	# set_anchors_AND_OFFSETS_preset：只设锚点时新控件仍是 0 尺寸，内容按最小尺寸堆在
	# 左上角（W13 实机缺陷 2026-11-09）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gpBuildUi()
	gpApplyStaticTexts()
	gpRefreshCards()
	I18n.gpLocaleChanged.connect(_gpOnLocaleChanged)


# Paint the chrome background, same tone family as the editor shell.
# 画 chrome 背景，与编辑器外壳同一色调族。
func _draw() -> void:
	GPChromeStyle.gpDraw(self, GPChromeStyle.GP_CHROME_BG, 0)


func _gpBuildUi() -> void:
	var gpMargin: MarginContainer = MarginContainer.new()
	gpMargin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpMargin.add_theme_constant_override("margin_left", 24)
	gpMargin.add_theme_constant_override("margin_right", 24)
	gpMargin.add_theme_constant_override("margin_top", 12)
	gpMargin.add_theme_constant_override("margin_bottom", 10)
	add_child(gpMargin)
	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.add_theme_constant_override("separation", 10)
	gpMargin.add_child(gpRoot)
	# --- top bar: brand + section tabs / 顶栏：品牌 + 分区 Tab ---
	var gpTop: HBoxContainer = HBoxContainer.new()
	gpTop.add_theme_constant_override("separation", 24)
	gpRoot.add_child(gpTop)
	var gpBrand: Label = Label.new()
	gpBrand.text = "G-PID"
	gpBrand.add_theme_font_size_override("font_size", 20)
	gpTop.add_child(gpBrand)
	var gpTopSpacer: Control = Control.new()
	gpTopSpacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpTop.add_child(gpTopSpacer)
	gpTop.add_child(_gpTabLabel("pc.tab_projects", true, ""))
	gpTop.add_child(_gpTabLabel("pc.tab_assets", false, " · W21+"))
	gpTop.add_child(_gpTabLabel("pc.tab_identity", false, " · W14"))
	# --- toolbar: create / import / scan / filter / sort / 工具栏：创建/导入/扫描/筛选/排序 ---
	var gpBar: HBoxContainer = HBoxContainer.new()
	gpBar.add_theme_constant_override("separation", 8)
	gpRoot.add_child(gpBar)
	var gpCreateBtn: Button = Button.new()
	gpCreateBtn.pressed.connect(_gpOnNewProject)
	gpCreateBtn.disabled = not GPPermissions.gpCanCreateProject()
	gpBar.add_child(gpCreateBtn)
	gpTextBindings.append({"node": gpCreateBtn, "prop": "text", "key": "pc.create"})
	gpTextBindings.append({"node": gpCreateBtn, "prop": "tooltip_text", "key": "pc.create_tip"})
	var gpImportBtn: Button = Button.new()
	gpImportBtn.pressed.connect(_gpOnImportProject)
	gpImportBtn.disabled = not GPPermissions.gpCanCreateProject()
	gpBar.add_child(gpImportBtn)
	gpTextBindings.append({"node": gpImportBtn, "prop": "text", "key": "pc.import"})
	gpTextBindings.append({"node": gpImportBtn, "prop": "tooltip_text", "key": "pc.import_tip"})
	var gpScanBtn: Button = Button.new()
	gpScanBtn.pressed.connect(gpRefreshCards)
	gpBar.add_child(gpScanBtn)
	gpTextBindings.append({"node": gpScanBtn, "prop": "text", "key": "pc.scan"})
	gpFilterEdit = LineEdit.new()
	gpFilterEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpFilterEdit.text_changed.connect(_gpOnFilterChanged)
	gpBar.add_child(gpFilterEdit)
	gpTextBindings.append({"node": gpFilterEdit, "prop": "placeholder_text", "key": "pc.filter_ph"})
	var gpSortLbl: Label = Label.new()
	gpBar.add_child(gpSortLbl)
	gpTextBindings.append({"node": gpSortLbl, "prop": "text", "key": "pc.sort"})
	var gpSortOpt: OptionButton = OptionButton.new()
	gpSortOpt.add_item(I18n.gpTr("pc.sort_recent"), 0)
	gpSortOpt.add_item(I18n.gpTr("pc.sort_name"), 1)
	gpSortOpt.item_selected.connect(_gpOnSortChanged)
	gpBar.add_child(gpSortOpt)
	# --- body: card list + action rail / 主体：卡片列表 + 动作栏 ---
	var gpBody: HSplitContainer = HSplitContainer.new()
	gpBody.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpBody.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBody.split_offset = -190
	gpBody.add_theme_constant_override("separation", 12)
	gpRoot.add_child(gpBody)
	var gpScroll: ScrollContainer = ScrollContainer.new()
	gpScroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpScroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gpBody.add_child(gpScroll)
	gpCardsBox = VBoxContainer.new()
	gpCardsBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpCardsBox.add_theme_constant_override("separation", 6)
	gpScroll.add_child(gpCardsBox)
	var gpRail: VBoxContainer = VBoxContainer.new()
	gpRail.custom_minimum_size = Vector2(170, 0)
	gpRail.add_theme_constant_override("separation", 8)
	gpBody.add_child(gpRail)
	gpSideOpenBtn = Button.new()
	gpSideOpenBtn.pressed.connect(_gpOnOpenSelected)
	gpRail.add_child(gpSideOpenBtn)
	gpTextBindings.append({"node": gpSideOpenBtn, "prop": "text", "key": "pc.open_draw"})
	gpSideRenameBtn = Button.new()
	gpSideRenameBtn.pressed.connect(_gpOnRenameSelected)
	gpRail.add_child(gpSideRenameBtn)
	gpTextBindings.append({"node": gpSideRenameBtn, "prop": "text", "key": "pc.rename"})
	gpSideRevealBtn = Button.new()
	gpSideRevealBtn.pressed.connect(_gpOnRevealSelected)
	gpRail.add_child(gpSideRevealBtn)
	gpTextBindings.append({"node": gpSideRevealBtn, "prop": "text", "key": "pc.reveal"})
	# W14 T4b: the identity entry — the W13 reserved hook (pc.tab_identity) lands here as
	# a rail action on the SELECTED archive; the panel reads/edits its plaintext header.
	# W14 T4b：身份入口 —— W13 预留挂点（pc.tab_identity）落为右栏动作，作用于**选中**
	# 存档；面板读写其明文头部。
	var gpIdentityBtn: Button = Button.new()
	gpIdentityBtn.pressed.connect(_gpOnIdentitySelected)
	gpIdentityBtn.disabled = not GPPermissions.gpCanManageMembers()
	gpRail.add_child(gpIdentityBtn)
	gpTextBindings.append({"node": gpIdentityBtn, "prop": "text", "key": "pc.identity"})
	# Delete = a destructive action on user data: kept as its own rail button + context
	# menu entry, and ALWAYS behind a confirmation dialog (trash is recoverable, but the
	# surprise is not).
	# 删除 = 对用户数据的破坏性动作：独立右栏按钮 + 上下文菜单项，**永远**过确认弹窗
	#（废纸篓可恢复，但「惊吓」不可撤销）。
	gpSideDeleteBtn = Button.new()
	gpSideDeleteBtn.pressed.connect(_gpOnDeleteSelected)
	gpRail.add_child(gpSideDeleteBtn)
	gpTextBindings.append({"node": gpSideDeleteBtn, "prop": "text", "key": "pc.delete"})
	gpTextBindings.append({"node": gpSideDeleteBtn, "prop": "tooltip_text", "key": "pc.delete_tip"})
	# Reserved slot for the future 项目运营管理 entry (A10: ships with the module, not before).
	# 将来「项目运营管理」入口的预留栏位（A10：随模块落地，绝不提前造假按钮）。
	var gpRailSpacer: Control = Control.new()
	gpRailSpacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpRail.add_child(gpRailSpacer)
	_gpSetRailEnabled(false)
	# --- bottom bar: scan dir + count / 底栏：扫描目录 + 计数 ---
	var gpBottom: HBoxContainer = HBoxContainer.new()
	gpBottom.add_theme_constant_override("separation", 12)
	gpRoot.add_child(gpBottom)
	gpDirLabel = Label.new()
	gpDirLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpDirLabel.clip_text = true
	gpDirLabel.modulate = Color(1, 1, 1, 0.55)
	gpDirLabel.add_theme_font_size_override("font_size", 11)
	gpBottom.add_child(gpDirLabel)
	gpCountLabel = Label.new()
	gpCountLabel.modulate = Color(1, 1, 1, 0.6)
	gpCountLabel.add_theme_font_size_override("font_size", 11)
	gpBottom.add_child(gpCountLabel)


func _gpTabLabel(gpKey: String, gpActive: bool, gpSuffix: String) -> Label:
	var gpLbl: Label = Label.new()
	gpLbl.add_theme_font_size_override("font_size", 15)
	if not gpActive:
		gpLbl.modulate = Color(1, 1, 1, 0.4)
	gpTextBindings.append({"node": gpLbl, "prop": "text", "key": gpKey, "suffix": gpSuffix})
	return gpLbl


# Batch-apply every bound static text from the active locale.
# 按当前语言整批套用所有绑定的静态文案。
func gpApplyStaticTexts() -> void:
	for gpBind in gpTextBindings:
		var gpText: String = I18n.gpTr(str(gpBind.get("key", "")))
		var gpSuffix: String = str(gpBind.get("suffix", ""))
		gpBind.get("node").set(str(gpBind.get("prop", "text")), gpText + gpSuffix)


func _gpOnLocaleChanged(_gpLocale: String) -> void:
	gpApplyStaticTexts()
	gpRefreshCards()


# ==================== list rebuild / 列表重建 ====================

# Rebuild the card list: scan ∪ recents (io merge) -> filter -> sort -> cards.
# Corrupt archives still get a card (fallback title) — hiding a broken archive is the
# worse failure.
# 重建卡片列表：扫描 ∪ 最近（io 合并）-> 筛选 -> 排序 -> 卡片。
# 坏档同样出卡（兜底标题）—— 把坏档藏起来才是更糟的失败。
func gpRefreshCards() -> void:
	gpEntries = GPProjectLibrary.gpMergeProjectLists(
		GPProjectLibrary.gpScanDirectory(GPProjectLibrary.gpDefaultScanDir()),
		GPProjectLibrary.gpRecentLoad())
	for gpChild in gpCardsBox.get_children():
		gpChild.queue_free()
	if gpDirLabel != null:
		gpDirLabel.text = I18n.gpTr("pc.scan_dir") % GPProjectLibrary.gpDefaultScanDir()
	var gpShown: Array[Dictionary] = _gpFilteredEntries()
	if gpShown.is_empty():
		var gpEmpty: Label = Label.new()
		gpEmpty.text = I18n.gpTr("pc.empty")
		gpEmpty.modulate = Color(1, 1, 1, 0.5)
		gpCardsBox.add_child(gpEmpty)
	else:
		for gpEntry in gpShown:
			var gpPath: String = str(gpEntry.get("path", ""))
			var gpMeta: Dictionary = GPProjectLibrary.gpPeekMeta(gpPath)
			var gpCard: GPProjectCard = GPProjectCard.new()
			gpCard.gpPopulate(GPProjectCard.gpAssembleData(gpEntry, gpMeta))
			gpCard.gpSetSelected(gpPath == gpSelectedPath)
			gpCard.gp_selected.connect(gpOnCardSelected)
			gpCard.gp_open_requested.connect(gpOnCardOpen)
			gpCard.gp_context_requested.connect(gpOnCardContext)
			gpCardsBox.add_child(gpCard)
	if gpCountLabel != null:
		gpCountLabel.text = I18n.gpTr("pc.status_count") % [gpShown.size(), gpEntries.size()]


# Filter (title / file name / path contains, case-insensitive) + sort (recent | name).
# 筛选（标题 / 文件名 / 路径包含，忽略大小写）+ 排序（最近 | 名称）。
func _gpFilteredEntries() -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	var gpNeedle: String = gpFilterText.to_lower()
	for gpEntry in gpEntries:
		if gpNeedle.is_empty():
			gpOut.append(gpEntry)
			continue
		var gpHaystack: String = ("%s %s %s" % [
			str(gpEntry.get("file_name", "")), str(gpEntry.get("path", "")),
			str(GPProjectLibrary.gpPeekMeta(str(gpEntry.get("path", ""))).get("title", "")),
		]).to_lower()
		if gpHaystack.contains(gpNeedle):
			gpOut.append(gpEntry)
	if gpSortMode == GP_SORT_NAME:
		gpOut.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
			return str(gpA.get("file_name", "")).to_lower() < str(gpB.get("file_name", "")).to_lower())
	return gpOut


func _gpOnFilterChanged(gpText: String) -> void:
	gpFilterText = gpText
	gpRefreshCards()


func _gpOnSortChanged(gpIdx: int) -> void:
	gpSortMode = GP_SORT_RECENT if gpIdx == 0 else GP_SORT_NAME
	gpRefreshCards()


# ==================== selection & actions / 选中与动作 ====================

func gpOnCardSelected(gpPath: String) -> void:
	gpSelectedPath = gpPath
	for gpChild in gpCardsBox.get_children():
		var gpCard := gpChild as GPProjectCard
		if gpCard != null:
			gpCard.gpSetSelected(str(gpCard.gpPath) == gpPath)
	_gpSetRailEnabled(true)


func _gpSetRailEnabled(gpOn: bool) -> void:
	gpSideOpenBtn.disabled = not gpOn
	# Rename/Delete are permission-gated mutations: a button may be enabled by selection
	# but disabled by the gate (the real permission system only edits GPPermissions).
	# 改名/删除是受权限闸管控的变更动作：选中让它可用，闸门可以让它不可用
	#（真正的权限系统落地时只改 GPPermissions）。
	gpSideRenameBtn.disabled = not gpOn or not GPPermissions.gpCanRenameProject()
	gpSideRevealBtn.disabled = not gpOn
	gpSideDeleteBtn.disabled = not gpOn or not GPPermissions.gpCanDeleteProject()


func gpOnCardOpen(gpPath: String) -> void:
	if gpPath.is_empty():
		return
	gp_open_project_requested.emit(gpPath)


func _gpOnOpenSelected() -> void:
	gpOnCardOpen(gpSelectedPath)


# W14 T4b: open the identity panel on the selected archive (fresh dialog per request, R7).
# W14 T4b：对选中存档打开身份面板（弹窗按次重建，R7）。
func _gpOnIdentitySelected() -> void:
	if gpSelectedPath.is_empty():
		return
	var gpPanel: GPIdentityPanel = GPIdentityPanel.new()
	gpPanel.gpSetup(gpSelectedPath)
	add_child(gpPanel)
	gpPanel.popup_centered(Vector2i(580, 440))


# Rename: dialog collects the new display name; the io layer rewrites the archive in
# place. Failures surface in the count label (the honest status line).
# 重命名：对话框收集新显示名；io 层原地改写存档。失败如实显示在计数标签（诚实状态行）。
func _gpOnRenameSelected() -> void:
	if _gpRefuseIfDenied(GPPermissions.gpCanRenameProject()):
		return
	if gpSelectedPath.is_empty():
		return
	if gpRenameDialog == null:
		gpRenameDialog = AcceptDialog.new()
		gpRenameDialog.ok_button_text = I18n.gpTr("pc.rename_ok")
		gpRenameDialog.confirmed.connect(_gpOnRenameConfirmed)
		gpRenameEdit = LineEdit.new()
		gpRenameEdit.custom_minimum_size = Vector2(320, 0)
		gpRenameDialog.add_child(gpRenameEdit)
		add_child(gpRenameDialog)
	gpRenameDialog.title = I18n.gpTr("pc.rename_title")
	gpRenameEdit.text = GPProjectLibrary.gpPeekMeta(gpSelectedPath).get("title", "")
	gpRenameDialog.popup_centered()


func _gpOnRenameConfirmed() -> void:
	var gpRes: GPIOResult = GPProjectLibrary.gpRenameArchiveV4(gpSelectedPath, gpRenameEdit.text)
	if not gpRes.gpOk:
		gpCountLabel.text = gpRes.gpText(I18n.gpTr)
		return
	gpCountLabel.text = gpRes.gpText(I18n.gpTr)
	gpRefreshCards()


func _gpOnRevealSelected() -> void:
	if not gpSelectedPath.is_empty():
		OS.shell_show_in_file_manager(gpSelectedPath)


# ==================== context menu & delete / 右键菜单与删除（W13 反馈 2026-11-11） ====================

# The card popup lives on the manager (cards are short-lived). Items are built at popup
# time so a locale switch between refreshes still reads correctly.
# 卡片右键弹窗住管理器层（卡片短命）。菜单项在弹出时构建 —— 刷新之间切语言也正确。
func gpOnCardContext(gpPath: String, gpScreenPos: Vector2) -> void:
	if gpPath.is_empty():
		return
	if gpCtxMenu == null:
		gpCtxMenu = PopupMenu.new()
		gpCtxMenu.id_pressed.connect(_gpOnCtxItem)
		add_child(gpCtxMenu)
	gpCtxMenu.clear()
	gpCtxMenu.add_item(I18n.gpTr("pc.ctx_open"), 0)
	gpCtxMenu.add_item(I18n.gpTr("pc.ctx_rename"), 1)
	gpCtxMenu.add_item(I18n.gpTr("pc.ctx_reveal"), 2)
	gpCtxMenu.add_separator()
	gpCtxMenu.add_item(I18n.gpTr("pc.ctx_delete"), 3)
	# popup() takes a Rect2i, not a point: set the window position, then show.
	# popup() 吃 Rect2i 不吃点：先设窗口位置，再弹出。
	gpCtxMenu.position = gpScreenPos
	gpCtxMenu.popup()


func _gpOnCtxItem(gpId: int) -> void:
	match gpId:
		0: gpOnCardOpen(gpSelectedPath)
		1: _gpOnRenameSelected()
		2: _gpOnRevealSelected()
		3: _gpOnDeleteSelected()


# Honest refusal line shared by all gated entries. Today NEVER taken (every gate returns
# true); the reverse-verification tests flip gpForceDeny to prove the wiring is live.
# 所有受闸入口共用的诚实拒绝行。今天**永不**触发（每道闸都放行）；反向验证测试翻转
# gpForceDeny 证明接线是活的。
func _gpRefuseIfDenied(gpAllowed: bool) -> bool:
	if gpAllowed:
		return false
	gpCountLabel.text = I18n.gpTr("pc.denied")
	return true


# Delete: confirm, then hand the file to the io layer (trash by default). The io result
# surfaces on the honest status line; refresh happens on success only.
# 删除：确认后交 io 层执行（默认入废纸篓）。io 结果如实上状态行；仅成功后刷新。
func _gpOnDeleteSelected() -> void:
	if _gpRefuseIfDenied(GPPermissions.gpCanDeleteProject()):
		return
	if gpSelectedPath.is_empty():
		return
	if gpDeleteDialog == null:
		gpDeleteDialog = ConfirmationDialog.new()
		gpDeleteDialog.ok_button_text = I18n.gpTr("pc.delete_ok")
		gpDeleteDialog.cancel_button_text = I18n.gpTr("pc.delete_cancel")
		gpDeleteDialog.confirmed.connect(_gpOnDeleteConfirmed)
		add_child(gpDeleteDialog)
	gpDeleteDialog.title = I18n.gpTr("pc.delete_title")
	var gpName: String = str(GPProjectLibrary.gpPeekMeta(gpSelectedPath).get("title", ""))
	if gpName.is_empty():
		gpName = gpSelectedPath.get_file()
	gpDeleteDialog.dialog_text = I18n.gpTr("pc.delete_body") % gpName
	gpDeleteDialog.popup_centered()


func _gpOnDeleteConfirmed() -> void:
	var gpRes: GPIOResult = GPProjectLibrary.gpDeleteArchiveV4(gpSelectedPath)
	gpCountLabel.text = gpRes.gpText(I18n.gpTr)
	if gpRes.gpOk:
		gpSelectedPath = ""
		gpRefreshCards()


# ==================== create & import / 新建与导入 ====================

# New project: pick a save path, then create + open. The FileDialog only PICKS a path
# (ui is allowed); the file is written by the io layer (gpCreateArchiveV4).
# 新建工程：选保存路径，然后创建 + 打开。FileDialog 只负责**选路径**（ui 允许）；
# 文件由 io 层写出（gpCreateArchiveV4）。
func _gpOnNewProject() -> void:
	if _gpRefuseIfDenied(GPPermissions.gpCanCreateProject()):
		return
	if gpSaveDialog == null:
		gpSaveDialog = FileDialog.new()
		gpSaveDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		gpSaveDialog.access = FileDialog.ACCESS_FILESYSTEM
		gpSaveDialog.filters = PackedStringArray(["*.pid.json"])
		gpSaveDialog.current_dir = GPProjectLibrary.gpDefaultScanDir()
		gpSaveDialog.file_selected.connect(_gpOnNewPathSelected)
		add_child(gpSaveDialog)
	gpSaveDialog.popup_centered(Vector2i(720, 480))


func _gpOnNewPathSelected(gpPath: String) -> void:
	var gpCreate: GPIOResult = GPProjectLibrary.gpCreateArchiveV4(
		gpPath, gpPath.get_file().trim_suffix(GPProjectLibrary.GP_ARCHIVE_SUFFIX))
	if not gpCreate.gpOk:
		gpCountLabel.text = gpCreate.gpText(I18n.gpTr)
		return
	gpSelectedPath = gpPath
	gpRefreshCards()
	gpOnCardOpen(gpPath)


# Import: an existing archive anywhere on disk joins the list via the recent store —
# the file itself is not copied nor opened (Godot semantics: import registers).
# 导入：磁盘上任意位置的既有存档经最近列表进入本列表 —— 文件既不复制也不打开
#（Godot 语义：导入＝登记）。
func _gpOnImportProject() -> void:
	if _gpRefuseIfDenied(GPPermissions.gpCanCreateProject()):
		return
	if gpOpenDialog == null:
		gpOpenDialog = FileDialog.new()
		gpOpenDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		gpOpenDialog.access = FileDialog.ACCESS_FILESYSTEM
		gpOpenDialog.filters = PackedStringArray(["*.pid.json"])
		gpOpenDialog.file_selected.connect(_gpOnImportPathSelected)
		add_child(gpOpenDialog)
	gpOpenDialog.popup_centered(Vector2i(720, 480))


func _gpOnImportPathSelected(gpPath: String) -> void:
	GPProjectLibrary.gpRecentTouch(gpPath)
	gpSelectedPath = gpPath
	gpRefreshCards()
