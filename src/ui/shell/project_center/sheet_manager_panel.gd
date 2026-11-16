# Copyright 2026 G-PID Contributors. MIT License. See LICENSE.
class_name GPSheetManagerPanel
extends Control

# The sheet manager panel (W13 T5 / ADR-47: new logic lives in a new file): the sheet list on
# the left, the preview + major-equipment panel on the right, and CRUD on the list — add via
# the center's existing gpAddTab, rename via the model + gpSyncTabTitles, open via
# gpActivateSheet, delete via THE ONE real-deletion blade (GPSheetLifecycle) — plan, confirm,
# apply, refresh in the confirmed callback so the list can never show a ghost.
# 图纸管理面板（W13 T5 / ADR-47：新逻辑住新文件）：左侧图纸列表、右侧预览 + 主要设备面板、
# 列表上的增删改查 —— 增走 center 既有 gpAddTab；改走模型 + gpSyncTabTitles；打开走
# gpActivateSheet；删走真删除**唯一一把刀**（GPSheetLifecycle）—— 计划、确认、执行，
# 在确认回调里刷新，列表永远不显示幽灵行。
#
# Contract holder per the shell rule: a ui/shell class reaching the host declares it.
# 按外壳规则：触达宿主的 ui/shell 类显式声明契约持有者。
var gpHost: GPShellHost = null

# ============================ injected furniture / 注入的陈设 ============================
var gpList: ItemList
var gpPreview: GPSheetPreview
# Rename dialog state: the sheet id being renamed ("" = none). The dialog is rebuilt per
# request — a member var, not a lambda capture (R7). W13 fix: it now edits NAME *and* NUMBER
# (the number had no editing surface anywhere — user feedback 2026-11-11).
# 重命名弹窗状态：正在改名的图纸 id（"" = 无）。弹窗按次重建 —— 用成员变量而非 lambda
# 捕获（R7）。W13 修复：现在同时编辑**名称与编号**（此前编号在任何界面都无从编辑 ——
# 用户反馈 2026-11-11）。
var _gpRenameId: String = ""
var _gpRenameEdit: LineEdit
var _gpNumberEdit: LineEdit
# Atlas export: the dir picker is created lazily and only PICKS a directory (ui may);
# the writing belongs to the io layer (GPAtlasExporter, W13 T3).
# 图册导出：目录选择器惰性创建、只负责**选目录**（ui 允许）；写盘归 io 层
#（GPAtlasExporter，W13 T3）。
var gpAtlasDialog: FileDialog


# ============================ pure row model (testable) ============================
# ============================ 纯行模型（可测） ============================
# One list row per sheet: text = name (+ number when present), uid = sheet id. Null sheets are
# skipped; order follows gpToSheets().
# 每张图纸一行：text = 名称（有编号时附上），uid = 图纸 id。null 图纸被跳过；顺序跟随
# gpToSheets()。
static func gpBuildRows(gpSheets: Array) -> Array[Dictionary]:
	var gpRows: Array[Dictionary] = []
	for gpSheet in gpSheets:
		var gpS: GPSheet = gpSheet as GPSheet
		if gpS == null:
			continue
		var gpText: String = gpS.gpName
		if not gpS.gpNumber.is_empty():
			gpText += "  ·  " + gpS.gpNumber
		gpRows.append({"uid": gpS.gpId, "text": gpText})
	return gpRows


# ============================ build / 构建 ============================
func _ready() -> void:
	# Full-rect from the start: set_anchors_preset alone would NOT reset offsets (R8).
	# 一开始就撑满：裸 set_anchors_preset 不会重设偏移（R8）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gpSplit: HSplitContainer = HSplitContainer.new()
	gpSplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpSplit.split_offset = 260
	add_child(gpSplit)
	# Left: list + action row. / 左：列表 + 动作行。
	var gpLeft: VBoxContainer = VBoxContainer.new()
	gpLeft.custom_minimum_size = Vector2(230, 0)
	gpSplit.add_child(gpLeft)
	gpList = ItemList.new()
	gpList.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpList.select_mode = ItemList.SELECT_SINGLE
	gpLeft.add_child(gpList)
	gpList.item_selected.connect(_gpOnSelected)
	gpList.item_activated.connect(_gpOnActivated)
	var gpBtnRow: HBoxContainer = HBoxContainer.new()
	gpLeft.add_child(gpBtnRow)
	var gpBNew: Button = Button.new()
	gpBNew.text = I18n.gpTr("sm.new")
	gpBNew.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBtnRow.add_child(gpBNew)
	gpBNew.pressed.connect(gpOnAddPressed)
	var gpBRename: Button = Button.new()
	gpBRename.text = I18n.gpTr("sm.rename")
	gpBRename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBtnRow.add_child(gpBRename)
	gpBRename.pressed.connect(_gpOnRenamePressed)
	var gpBtnRow2: HBoxContainer = HBoxContainer.new()
	gpLeft.add_child(gpBtnRow2)
	var gpBOpen: Button = Button.new()
	gpBOpen.text = I18n.gpTr("sm.open")
	gpBOpen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBtnRow2.add_child(gpBOpen)
	gpBOpen.pressed.connect(_gpOnOpenPressed)
	var gpBDel: Button = Button.new()
	gpBDel.text = I18n.gpTr("sm.delete")
	gpBDel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBtnRow2.add_child(gpBDel)
	gpBDel.pressed.connect(gpOnDeletePressed)
	var gpBtnRow3: HBoxContainer = HBoxContainer.new()
	gpLeft.add_child(gpBtnRow3)
	var gpBAtlas: Button = Button.new()
	gpBAtlas.text = I18n.gpTr("sm.export_atlas")
	gpBAtlas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBtnRow3.add_child(gpBAtlas)
	gpBAtlas.pressed.connect(_gpOnAtlasPressed)
	# Right: preview. / 右：预览。
	gpPreview = GPSheetPreview.new()
	gpPreview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpPreview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The thumbnail eats the print-model geometry, so it needs the LIVE defs: a member-Callable
	# relay (no lambda, R7) — the same snapshot the cross-sheet controller and DRC consume.
	# 缩略图吃打印模型几何，因此需要**实时** defs：成员 Callable 中继（无 lambda，R7）——
	# 与跨图纸控制器、DRC 消费的同一份快照。
	if gpHost != null:
		gpPreview.gpDefsProvider = Callable(gpHost, "gpDefsSnapshot")
	gpSplit.add_child(gpPreview)


# Rebuild the list from the live sheets, keeping the current selection when possible.
# 从实时图纸重建列表；尽量保持当前选中。
func gpRefresh() -> void:
	if gpHost == null or gpHost.gpCenter == null or gpList == null:
		return
	var gpRows: Array[Dictionary] = gpBuildRows(gpHost.gpCenter.gpToSheets())
	var gpKeepId: String = _gpSelectedId()
	gpList.clear()
	for gpRow in gpRows:
		gpList.add_item(str(gpRow.get("text", "")), null, true)
		gpList.set_item_metadata(gpList.item_count - 1, str(gpRow.get("uid", "")))
	if not gpKeepId.is_empty():
		for gpI: int in gpList.item_count:
			if str(gpList.get_item_metadata(gpI)) == gpKeepId:
				gpList.select(gpI)
				break
	gpSyncPreview()


# The id of the currently selected row; "" if none. / 当前选中行的 id；无则 ""。
func _gpSelectedId() -> String:
	if gpList == null or gpList.get_selected_items().is_empty():
		return ""
	return str(gpList.get_item_metadata(gpList.get_selected_items()[0]))


# Push the selected sheet into the preview; nothing selected -> empty state.
# 把选中的图纸推进预览；无选中 -> 空态。
func gpSyncPreview() -> void:
	if gpHost == null or gpHost.gpCenter == null or gpPreview == null:
		return
	var gpId: String = _gpSelectedId()
	for gpSheet in gpHost.gpCenter.gpToSheets():
		var gpS: GPSheet = gpSheet as GPSheet
		if gpS != null and gpS.gpId == gpId:
			gpPreview.gpShowSheet(gpS)
			return
	gpPreview.gpClear()


# ============================ CRUD / 增删改查 ============================

# ADD: the center's own add path (fresh sheet + tab + activate), then dirty + refresh.
# 增：走 center 自己的新建路径（新图纸 + 新标签 + 激活），随后置脏 + 刷新。
func gpOnAddPressed() -> void:
	if gpHost == null or gpHost.gpCenter == null:
		return
	gpHost.gpCenter.gpAddTab()
	if gpHost.gpDocManager != null:
		gpHost.gpDocManager.gpMarkDirty()
	gpRefresh()


# OPEN: activate the selected sheet in the editor. / 打开：在编辑器中激活选中的图纸。
func _gpOnOpenPressed() -> void:
	if gpHost == null or gpHost.gpCenter == null:
		return
	var gpId: String = _gpSelectedId()
	if not gpId.is_empty():
		gpHost.gpCenter.gpActivateSheet(gpId)


func _gpOnSelected(_gpIndex: int) -> void:
	gpSyncPreview()


# Double-click opens too. / 双击同样打开。
func _gpOnActivated(_gpIndex: int) -> void:
	_gpOnOpenPressed()


# RENAME: rebuild the dialog per request; confirmed lands in _gpOnRenameConfirmed.
# 改名：按次重建弹窗；确认落在 _gpOnRenameConfirmed。
func _gpOnRenamePressed() -> void:
	if gpHost == null or gpHost.gpCenter == null:
		return
	var gpId: String = _gpSelectedId()
	if gpId.is_empty():
		return
	for gpSheet in gpHost.gpCenter.gpToSheets():
		var gpS: GPSheet = gpSheet as GPSheet
		if gpS != null and gpS.gpId == gpId:
			_gpRenameId = gpId
			var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
			gpDlg.title = I18n.gpTr("sm.rename_title")
			gpDlg.ok_button_text = I18n.gpTr("sl.ok")
			gpDlg.cancel_button_text = I18n.gpTr("sl.cancel")
			# Name + NUMBER fields. Number writes go through gpAssignNumber so the ADR-38
			# hand-edit-survival semantics and the title-block drawing_no cell stay consistent.
			# 名称 + **编号**两个字段。编号写入经 gpAssignNumber，与 ADR-38 手改存活语义
			# 及图签「图号」单元格保持一致。
			var gpForm: VBoxContainer = VBoxContainer.new()
			var gpNameLbl: Label = Label.new()
			gpNameLbl.text = I18n.gpTr("sm.field_name")
			gpForm.add_child(gpNameLbl)
			_gpRenameEdit = LineEdit.new()
			_gpRenameEdit.text = gpS.gpName
			gpForm.add_child(_gpRenameEdit)
			var gpNumLbl: Label = Label.new()
			gpNumLbl.text = I18n.gpTr("sm.field_number")
			gpForm.add_child(gpNumLbl)
			_gpNumberEdit = LineEdit.new()
			_gpNumberEdit.text = gpS.gpNumber
			gpForm.add_child(_gpNumberEdit)
			gpDlg.add_child(gpForm)
			add_child(gpDlg)
			gpDlg.confirmed.connect(_gpOnRenameConfirmed)
			gpDlg.confirmed.connect(gpDlg.queue_free)
			gpDlg.canceled.connect(gpDlg.queue_free)
			gpDlg.popup_centered(Vector2i(420, 220))
			return


func _gpOnRenameConfirmed() -> void:
	if gpHost == null or gpHost.gpCenter == null or _gpRenameId.is_empty():
		return
	var gpNewName: String = _gpRenameEdit.text.strip_edges()
	var gpNewNumber: String = _gpNumberEdit.text.strip_edges()
	if gpNewName.is_empty():
		return
	for gpSheet in gpHost.gpCenter.gpToSheets():
		var gpS: GPSheet = gpSheet as GPSheet
		if gpS != null and gpS.gpId == _gpRenameId:
			gpS.gpName = gpNewName
			gpHost.gpSetState("status.sheet_renamed", [gpNewName])
			# Empty input = a deliberate CLEAR (an honest no-number state; the list row
			# then shows the bare name). gpAssignNumber keeps block and field in step.
			# 空输入＝刻意清号（诚实的无号状态；列表行退回裸名）。gpAssignNumber 使
			# 图签单元格与字段同步。
			if gpNewNumber != gpS.gpNumber:
				gpS.gpAssignNumber(gpNewNumber)
				gpHost.gpSetState("status.sheet_number_set",
					[gpNewNumber if not gpNewNumber.is_empty() else I18n.gpTr("sm.number_cleared")])
			gpHost.gpCenter.gpSyncTabTitles()
			gpHost.gpCenter.gpRefreshOffPageContext()
			if gpHost.gpDocManager != null:
				gpHost.gpDocManager.gpMarkDirty()
			break
	_gpRenameId = ""
	gpRefresh()


# DELETE: the ONE blade — plan, confirm, apply via GPSheetLifecycle, then refresh INSIDE the
# confirmed callback so the list never shows a ghost row.
# 删除：唯一一把刀 —— 经 GPSheetLifecycle 计划、确认、执行，并在确认回调**内部**刷新，
# 列表永不显示幽灵行。
func gpOnDeletePressed() -> void:
	if gpHost == null or gpHost.gpCenter == null:
		return
	var gpId: String = _gpSelectedId()
	if gpId.is_empty():
		return
	var gpLifecycle: GPSheetLifecycle = gpHost.gpSheetLifecycleEnsure()
	var gpPlan: Dictionary = GPSheetLifecycle.gpPlanDelete(gpHost.gpCenter.gpToSheets(),
		gpHost.gpCenter.gpOffPageLinksList(), gpId)
	if not bool(gpPlan.get("ok", false)):
		gpHost.gpSetState("status.sheet_" + str(gpPlan.get("reason", "missing")))
		return
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("sl.confirm_title")
	var gpBody: String = I18n.gpTr("sl.confirm_body") % str(gpPlan.get("title", ""))
	var gpAffected: Array = gpPlan.get("affected", []) as Array
	if gpAffected.size() > 0:
		gpBody += "\n" + (I18n.gpTr("sl.confirm_links") % gpAffected.size())
	gpDlg.dialog_text = gpBody
	gpDlg.ok_button_text = I18n.gpTr("sl.ok")
	gpDlg.cancel_button_text = I18n.gpTr("sl.cancel")
	add_child(gpDlg)
	gpDlg.confirmed.connect(_gpOnDeleteConfirmed.bind(gpLifecycle, gpPlan))
	gpDlg.confirmed.connect(gpDlg.queue_free)
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.popup_centered()


# Member-function callback (R7: no lambda held across frames). Apply, then refresh.
# 成员函数回调（R7：跨帧不持 lambda）。先执行，后刷新。
func _gpOnDeleteConfirmed(gpLifecycle: GPSheetLifecycle, gpPlan: Dictionary) -> void:
	gpLifecycle.gpApplyPlan(gpPlan)
	gpRefresh()


# ============================ atlas export / 图册导出（W13 T3） ============================

# ATLAS: export the WHOLE sheet set as one PDF per sheet + a catalog page. The SAME DRC
# delivery gate guards it as the single-sheet PDF path (ADR-39 E05); the dialog only PICKS
# a directory — writing belongs to the io layer.
# 图册：整套图纸导出为每张一个 PDF + 一页目录。与单图 PDF 路径共用**同一道** DRC 交付闸
#（ADR-39 E05）；对话框只负责**选目录** —— 写盘归 io 层。
func _gpOnAtlasPressed() -> void:
	if gpHost == null or gpHost.gpCenter == null:
		return
	var gpValid: Array[GPSheet] = _gpLiveSheets()
	if gpValid.is_empty():
		gpHost.gpSetState("atlas.no_sheets")
		return
	var gpStd: GPProjectStandard = null
	if gpValid[0].gpGraph != null:
		gpStd = gpValid[0].gpGraph.gpStandard
	var gpGate: Dictionary = GPExportGate.gpCheck(gpValid, gpHost.gpDefs, gpStd)
	if bool(gpGate.get("blocked", false)):
		gpHost.gpSetState("drc.export_blocked", [int(gpGate.get("errors", 0))])
		return
	if gpAtlasDialog == null:
		gpAtlasDialog = FileDialog.new()
		gpAtlasDialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		gpAtlasDialog.access = FileDialog.ACCESS_FILESYSTEM
		gpAtlasDialog.dir_selected.connect(_gpOnAtlasDirSelected)
		add_child(gpAtlasDialog)
	gpAtlasDialog.popup_centered(Vector2i(720, 480))


func _gpOnAtlasDirSelected(gpDirPath: String) -> void:
	# gpCaption stays the default Callable and gpDefs empty — the SAME convention the
	# registry's single-sheet PDF path uses (the live default library), so the atlas pages
	# and a one-sheet export never disagree about geometry.
	# gpCaption 保持缺省 Callable、gpDefs 传空 —— 与注册表单图 PDF 路径**同一约定**
	#（活动默认库），使图册页面与单图导出在几何上永不分家。
	var gpRes: GPIOResult = GPAtlasExporter.gpExportAtlas(_gpLiveSheets(), gpDirPath,
		Callable(), [], "", Callable(I18n, "gpTr"))
	if not gpRes.gpOk:
		gpHost.gpSetState(gpRes.gpMessageKey)
		return
	var gpStats: Dictionary = gpRes.gpPayload as Dictionary
	if gpStats == null:
		gpStats = {}
	gpHost.gpSetState("status.atlas_done", [int(gpStats.get("count", 0)),
		int(gpStats.get("total", 0)), float(int(gpStats.get("elapsed_ms", 0))) / 1000.0,
		str(gpStats.get("dir", ""))])


# The live non-null sheets, in tab order. / 实时非空图纸，按标签顺序。
func _gpLiveSheets() -> Array[GPSheet]:
	var gpOut: Array[GPSheet] = []
	if gpHost == null or gpHost.gpCenter == null:
		return gpOut
	for gpSheet in gpHost.gpCenter.gpToSheets():
		var gpS: GPSheet = gpSheet as GPSheet
		if gpS != null:
			gpOut.append(gpS)
	return gpOut
