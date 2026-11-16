# Copyright 2026 G-PID Contributors. MIT License. See LICENSE.
class_name GPSheetLifecycle
extends RefCounted

# REAL sheet deletion (W13 T4 / ADR-47: new logic lives in a new file). Closing a tab only
# HIDES a sheet (user feedback 2026-11-04); this class is the ONE knife that truly deletes
# one, with the cross-sheet cascade confirmation — and T5's sheet manager panel reuses the
# SAME blade instead of a second copy.
# 图纸**真删除**（W13 T4 / ADR-47：新逻辑住新文件）。关闭标签只是**隐藏**图纸
#（用户反馈 2026-11-04）；本类是真删除的**唯一一把刀**，带跨图纸连接级联确认 ——
# T5 的图纸管理面板复用同一把刀，绝不写第二份。
#
# WHY PLAN/APPLY SPLIT / 为何「计划/执行」两段：
# gpPlanDelete() is PURE (dict in the sense of typed models only, no UI, no tree) so the
# gate can pin the cascade math headless; gpApplyPlan() is the ONLY place that mutates the
# shell, and it walks EXISTING public surface of GPCenterArea only — the frozen center file
# (budget: shrink-only, ADR-47) grows by zero lines.
# gpPlanDelete() 是**纯函数**（只吃类型化模型，零 UI、零场景树），门禁可 headless 钉死级联
# 数学；gpApplyPlan() 是**唯一**改外壳的地方，且只走 GPCenterArea **既有的公共面** ——
# 冻结的 center 文件（预算只减不增，ADR-47）零行增长。
#
# MECHANICS / 机制（all through existing public API / 全部经既有公共 API）：
# 1. Cascade: every link touching the sheet is removed via GPOffPageStore.gpRemove() —
#    the store's gpChanged fires the dirty mark + snapshot republish from ONE place (A2).
#    级联：触碰该图纸的每条 link 经 GPOffPageStore.gpRemove() 移除 —— store 的 gpChanged
#    从**一个**地方驱动脏标记 + 快照重发（A2）。
# 2. Sheets: survivors = gpToSheets() minus the deleted, rebuilt via gpLoadSheets(). That
#    call resets the shared project standard (it is built for project OPEN), so the holder
#    snapshots it and re-applies with gpApplyStandard() — the standard must outlive a delete.
#    图纸：幸存者 = gpToSheets() 去掉被删者，经 gpLoadSheets() 重建。该调用会清空共享工程
#    标准（它是为**打开工程**设计的），故执行前快照、再用 gpApplyStandard() 套回 ——
#    标准必须比一次删除活得更久。
# 3. Honest cost: gpLoadSheets rebuilds canvases, so surviving tabs' view (zoom/pan) resets.
#    Accepted for W13: data (graphs/sheets/links/standard) is untouched.
#    诚实的代价：gpLoadSheets 重建画布，幸存标签的视图（缩放/平移）会复位。W13 接受：
#    数据（图 / 图纸 / link / 标准）分毫不动。
#
# Coding rule: every variable declares its type explicitly. / 编码规范：所有变量均显式声明类型。

# ============================ pure core / 纯函数核心 ============================

# Does a link reference the given sheet on EITHER end? Pure; null-safe; an empty target id
# never matches (a deletion request without an id is a bug, not a cascade).
# link 的**任一端**引用该图纸？纯函数、null 安全；空目标 id 永不命中（无 id 的删除请求
# 是调用方 bug，不是级联）。
static func gpLinkTouchesSheet(gpLink: GPOffPageLink, gpSheetId: String) -> bool:
	if gpLink == null or gpSheetId.is_empty():
		return false
	return str(gpLink.gpA.get(GPOffPageLink.GP_KEY_SHEET, "")) == gpSheetId \
		or str(gpLink.gpB.get(GPOffPageLink.GP_KEY_SHEET, "")) == gpSheetId


# Build the deletion plan. Reasons: "ok" / "missing" (no sheet carries the id) / "last"
# (the project must keep at least one sheet). The survivors keep their order and their
# GPSheet models verbatim (gpToSheets reuses each tab's own sheet), so a reload is lossless
# for the kept sheets.
# 构建删除计划。reason：ok / missing（无图纸持该 id）/ last（工程至少保留一张图纸）。
# 幸存者保持原顺序、原 GPSheet 模型（gpToSheets 复用各标签自己的 sheet），故重建对保留
# 的图纸无损。
static func gpPlanDelete(gpSheets: Array[GPSheet], gpLinks: Array[GPOffPageLink],
		gpSheetId: String) -> Dictionary:
	if gpSheetId.is_empty():
		return {"ok": false, "reason": "missing", "sheet_id": gpSheetId}
	var gpSurvivors: Array[GPSheet] = []
	var gpTitle: String = ""
	var gpFound: bool = false
	for gpSheet in gpSheets:
		if gpSheet == null:
			continue
		if gpSheet.gpId == gpSheetId:
			gpFound = true
			gpTitle = gpSheet.gpName
		else:
			gpSurvivors.append(gpSheet)
	if not gpFound:
		return {"ok": false, "reason": "missing", "sheet_id": gpSheetId}
	if gpSurvivors.is_empty():
		return {"ok": false, "reason": "last", "sheet_id": gpSheetId}
	var gpAffected: Array[GPOffPageLink] = []
	for gpLink in gpLinks:
		if gpLinkTouchesSheet(gpLink, gpSheetId):
			gpAffected.append(gpLink)
	return {
		"ok": true, "reason": "ok", "sheet_id": gpSheetId, "title": gpTitle,
		"survivors": gpSurvivors, "affected": gpAffected,
	}

# ============================ executor / 执行器 ============================
# Contract holder per the shell rule: a ui/shell class reaching the host declares it.
# 按外壳规则：触达宿主的 ui/shell 类显式声明契约持有者。
var gpHost: GPShellHost = null


# Menu entry (T4): delete the ACTIVE sheet. T5's panel will call gpRequestDelete(id) for
# any sheet through the same dialog.
# 菜单入口（T4）：删除**活动**图纸。T5 面板将经同一弹窗以 gpRequestDelete(id) 删除任意图纸。
func gpDeleteActiveSheet() -> void:
	if gpHost == null or gpHost.gpCenter == null:
		return
	var gpSheet: GPSheet = gpHost.gpCenter.gpActiveSheet()
	if gpSheet == null:
		return
	gpRequestDelete(gpSheet.gpId)


# Any-sheet entry (T4 menu + T5 panel): plan, then confirm, then apply. A refused plan
# reports honestly on the status bar — silence is the worse failure.
# 任意图纸入口（T4 菜单 + T5 面板）：计划 -> 确认 -> 执行。被拒的计划如实上状态栏 ——
# 沉默才是更糟的失败。
func gpRequestDelete(gpSheetId: String) -> void:
	if gpHost == null or gpHost.gpCenter == null:
		return
	var gpPlan: Dictionary = gpPlanDelete(gpHost.gpCenter.gpToSheets(),
		gpHost.gpCenter.gpOffPageLinksList(), gpSheetId)
	if not bool(gpPlan.get("ok", false)):
		gpHost.gpSetState("status.sheet_" + str(gpPlan.get("reason", "missing")))
		return
	gpConfirmAndApply(gpPlan)


# The confirmation dialog. Member-function Callable with .bind() — NO lambda (R7: a
# Callable held across frames must not be a lambda stored on a foreign static; bind on a
# signal is safe and keeps the detector quiet).
# 确认弹窗。成员函数 Callable 加 .bind() —— **不用 lambda**（R7：跨帧持有的 Callable
# 不得是存到外来静态上的 lambda；信号上 bind 安全且让检测器保持沉默）。
func gpConfirmAndApply(gpPlan: Dictionary) -> void:
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("sl.confirm_title")
	var gpBody: String = I18n.gpTr("sl.confirm_body") % str(gpPlan.get("title", ""))
	var gpAffected: Array = gpPlan.get("affected", []) as Array
	if gpAffected.size() > 0:
		gpBody += "\n" + (I18n.gpTr("sl.confirm_links") % gpAffected.size())
	gpDlg.dialog_text = gpBody
	gpDlg.ok_button_text = I18n.gpTr("sl.ok")
	gpDlg.cancel_button_text = I18n.gpTr("sl.cancel")
	gpHost.add_child(gpDlg)
	gpDlg.confirmed.connect(gpApplyPlan.bind(gpPlan))
	gpDlg.confirmed.connect(gpDlg.queue_free)
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.popup_centered()


# THE mutation: cascade links through the store, reload survivors, restore the standard,
# mark dirty. Only reached from the confirmed dialog (or a caller that already decided).
# **唯一**的变更路径：link 经 store 级联移除、重建幸存图纸、套回标准、置脏。只从确认后
# 的弹窗抵达（或已替用户做出决定的调用方）。
func gpApplyPlan(gpPlan: Dictionary) -> void:
	if gpHost == null or gpHost.gpCenter == null:
		return
	if not bool(gpPlan.get("ok", false)):
		return
	var gpCenter: GPCenterArea = gpHost.gpCenter
	# 1. Cascade through the store (each removal fires gpChanged -> dirty + republish).
	#    经 store 级联（每次移除发 gpChanged -> 置脏 + 重发）。
	for gpLink in gpPlan.get("affected", []) as Array:
		gpCenter.gpLinkStore().gpRemove(gpLink as GPOffPageLink)
	# 2. Reload the survivors; snapshot + re-apply the shared standard (gpLoadSheets is
	#    built for project OPEN and drops it — a delete must not).
	#    重建幸存图纸；快照并**套回**共享标准（gpLoadSheets 为「打开工程」设计会丢掉它
	#    —— 删除不该丢）。
	var gpStd: GPProjectStandard = gpCenter.gpProjectStandard
	gpCenter.gpLoadSheets(gpPlan.get("survivors", []) as Array)
	gpCenter.gpApplyStandard(gpStd)
	# 3. Dirty + honest status. / 置脏 + 如实状态。
	if gpHost.gpDocManager != null:
		gpHost.gpDocManager.gpMarkDirty()
	gpHost.gpSetState("status.sheet_deleted", [str(gpPlan.get("title", ""))])
