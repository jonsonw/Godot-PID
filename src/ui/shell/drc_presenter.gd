class_name GPDrcPresenter
extends Node
# Copyright © 2026 Jonson Wang
# DRC presentation domain: the dock panel (B2), the toolbar result dialog (ADR-39), the
# screen-space badges (E03) and the live scheduler (E02) — everything the user SEES of the rule
# engine, and nothing about how the rules are computed (that is GPDrcEngine, core).
# DRC 呈现域：停靠面板（B2）、工具栏结果弹窗（ADR-39）、屏幕空间角标（E03）与实时调度器
#（E02）—— 用户**看见**的规则引擎，全部在此；规则如何计算不在此（那是 core 的 GPDrcEngine）。
#
# WHY THIS EXISTS / 为何存在：
# These 15 functions / 244 lines owned four pieces of furniture (panel / dialog / scheduler /
# overlay) and 13 members of the root. Measured before cutting: the block's external surface is
# ONLY gpTabs, gpCenter, the definition table and the status bar — exactly the four things the
# cross-sheet controller already takes. Nothing outside reached its private slots, and the two
# public entries (gpRunDrc / gpShowDrcDialog) are reached through ONE caller: the menu.
# 这 15 个函数 / 244 行持有四件陈设（面板 / 弹窗 / 调度器 / 角标）与根类的 13 个成员。切前测量：
# 该块对外面**只有** gpTabs、gpCenter、定义表与状态栏 —— 正是跨图纸控制器已经拿走的那四样。
# 块外无人触达其私有槽，两个公开入口（gpRunDrc / gpShowDrcDialog）只有一个调用方：菜单。
#
# S3 of stage 2 also closed the last two holes in GPShellHost: those two entries used to be
# `push_error` stubs for the root to override. Now they are relays to this class, so the shell
# no longer knows that DRC furniture exists.
# 阶段 2 的 S3 同时补上了 GPShellHost 最后两个洞：那两个入口原先是留给根类覆写的
# `push_error` 空体。现在是通往本类的中继，外壳因此**不再知道** DRC 陈设的存在。
#
# Interaction / 交互方式：
# - the composition root creates this node and injects four things: gpTabs, gpCenter,
#   gpDefsProvider (a Callable, NOT the array) and gpStateSink;
# 组合根创建本节点并注入四样东西：gpTabs、gpCenter、gpDefsProvider（是 Callable，**不是**数组）
# 与 gpStateSink；
# - two assembly phases, because each half needs a different world: gpCreateRuntime() builds the
#   scheduler + overlay BEFORE the first sheet exists (its canvas-ready signal binds them), and
#   gpCreatePanel() adds the dock tab AFTER it — the panel ends by binding the ACTIVE canvas, and
#   the right dock expects DRC to be its LAST tab, right after the outline.
# 装配分两步，因为两半需要不同的世界：gpCreateRuntime() 在首张图纸存在**之前**建调度器与角标
#（其 canvas-ready 信号要绑它们），gpCreatePanel() 在其**之后**加停靠页 —— 面板结尾要绑**活动**
# 画布，而右栏要求 DRC 是**最后一页**（紧跟大纲）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The right dock's TabContainer: the panel is one of its tabs, and "bring the tab forward" is
# part of what makes a check visible.
# 右栏 TabContainer：面板是其中一页，而「把页切到前面」正是「体检可见」的一部分。
var gpTabs: TabContainer = null

# Multi-sheet container: sheets table, link table, active canvas, sheet activation.
# 多图纸容器：图纸表、link 表、活动画布、图纸激活。
var gpCenter: GPCenterArea = null

# Symbol-definition provider (Callable -> Array[GPSymbolDef]). A Callable, NOT the array:
# gpDefs is reassigned six times at runtime (project import / symbol delete).
# 图元定义提供者（Callable -> Array[GPSymbolDef]）。传 Callable 而非数组：gpDefs 在运行期会被
# 重新赋值六次（导入工程 / 删图元）。
var gpDefsProvider: Callable = Callable()

# Status-bar sink (Callable -> void, signature (key: String, args: Array)).
# 状态栏接收端（Callable -> void，签名 (key: String, args: Array)）。
var gpStateSink: Callable = Callable()

# ---- furniture owned here / 此处持有的陈设 ----

# The DRC dock panel (B2): fifth dock tab, created at assembly.
# DRC 停靠面板（B2）：第五个停靠页，装配时创建。
var gpPanel: GPDRCPanel = null

# The top-toolbar result dialog (ADR-39). Lazily created; non-modal so the user can inspect the
# drawing while it stays open.
# 顶部工具栏结果弹窗（ADR-39）。懒创建；非模态，用户可一边看图一边点行。
var gpDialog: GPDRCDialog = null

# Live DRC scheduler (E02): debounced engine run after every graph change.
# 实时 DRC 调度（E02）：每次图变化后去抖跑一次引擎。
var gpScheduler: GPRuleScheduler = null

# Screen-space badges above the active canvas.
# 活动画布之上的屏幕空间角标。
var gpOverlay: GPRuleOverlay = null


# The live definition table, resolved on every call so it can never go stale.
# 实时图元定义表；每次调用都重新求值，故永不过期。
func _gpDefs() -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	if not gpDefsProvider.is_valid():
		return gpOut
	var gpV: Variant = gpDefsProvider.call()
	if gpV is Array:
		for gpD in gpV:
			if gpD is GPSymbolDef:
				gpOut.append(gpD)
	return gpOut


# Forward a status-bar update to the root (the label lives there).
# 把状态栏更新转发给根类（标签归它所有）。
func _gpSetState(gpKey: String, gpArgs: Array = []) -> void:
	if gpStateSink.is_valid():
		gpStateSink.call(gpKey, gpArgs)


# The active canvas, via the container that owns it.
# 活动画布，经持有它的容器取得。
func _gpActiveCanvas() -> GPCanvas2D:
	if gpCenter == null:
		return null
	return gpCenter.gpActiveCanvas()


# ---- assembly phase 1: runtime (before the first sheet) / 装配第一步：运行时（首张图纸之前）----

# Build the live scheduler and the screen-space badges. MUST run BEFORE the first sheet is
# added: creating it fires canvas-ready, which is where the scheduler gets bound.
# 建实时调度器与屏幕空间角标。必须在首张图纸加入**之前**运行：创建它就会触发 canvas-ready，
# 而调度器正是在那里被绑定。
func gpCreateRuntime() -> void:
	if gpScheduler != null:
		return
	gpScheduler = GPRuleScheduler.new()
	gpScheduler.name = "DRCScheduler"
	add_child(gpScheduler)
	gpScheduler.gpFindingsReady.connect(_gpOnLiveDrc)
	gpOverlay = GPRuleOverlay.new()
	gpOverlay.name = "DrcOverlay"
	add_child(gpOverlay)


# A new canvas appeared: connect the scheduler to its graph-changed bus once, and attach the
# badges when this canvas is the ACTIVE one. Called from the root's canvas-ready handler.
# 新画布出现：一次性把调度器接到它的图变化总线；若该画布是**活动**画布则挂上角标。
# 由根类的 canvas-ready 处理器调用。
func gpOnCanvasReady(gpCanvas: GPCanvas2D) -> void:
	if gpScheduler == null or gpCanvas == null:
		return
	# The bus is SHARED across sheets, so a second tab would re-connect the same callable and
	# spam "already connected" errors. Guard every connect with is_connected.
	# 总线**跨图纸共享**，第二个标签页会重复连接同一可调用对象并刷出「already connected」。
	# 每条连接都加 is_connected 守卫。
	var gpBus: GPEventBus = gpCanvas.gpEvents
	if gpBus != null and not gpBus.gpGraphChanged.is_connected(gpScheduler.gpMarkDirty):
		gpBus.gpGraphChanged.connect(gpScheduler.gpMarkDirty)
	if _gpActiveCanvas() == gpCanvas:
		_gpBindScheduler(gpCanvas)
		if gpOverlay != null:
			gpOverlay.gpAttach(gpCanvas)


# The active sheet changed: point the panel at the new canvas, rebind the scheduler and clear
# the badges (they belong to the sheet the user just left).
# 活动图纸切换：把面板指向新画布、重绑调度器并清空角标（它们属于用户刚离开的那张图纸）。
func gpOnActiveSheetChanged() -> void:
	gpBindActive()
	_gpBindScheduler(_gpActiveCanvas())
	if gpOverlay != null and _gpActiveCanvas() != null:
		gpOverlay.gpAttach(_gpActiveCanvas())
		gpOverlay.gpShow([], _gpActiveSheetId())

# Build the DRC panel tab (B2).
# 构建 DRC 面板页（B2）。
func gpCreatePanel() -> void:
	gpPanel = GPDRCPanel.new()
	gpPanel.name = "DrcTab"
	gpTabs.add_child(gpPanel)
	gpPanel.gpBuild()
	gpTabs.set_tab_title(gpTabs.get_tab_count() - 1, I18n.gpTr("drc.panel_title"))
	gpPanel.gpFindingActivated.connect(_gpOnDrcJump)
	gpPanel.gpFindingActivatedFull.connect(_gpOnDrcFindingFromPanel)
	gpPanel.gpFindingsChanged.connect(_gpOnDrcFindingsForOverlay)
	# ADR-36 C: "whole project" mode needs every sheet; the shell owns the tab bar.
	# ADR-36 C：「全工程」模式需要每张图纸；标签栏归外壳所有。
	gpPanel.gpSetSheetsProvider(Callable(self, "_gpSheets"))
	gpPanel.gpSetLinksProvider(Callable(self, "_gpLinks"))
	gpBindActive()


# All sheets, for the DRC's whole-project mode (and the export gate's equivalent check).
# 全部图纸，供 DRC 全工程模式（以及导出闸门的等价检查）使用。
func _gpSheets() -> Array:
	if gpCenter == null:
		return []
	return gpCenter.gpToSheets()


# Container link table for the DRC off-page audit (W12-S4).
# 供 DRC 跨图纸审计用的容器 link 表（W12-S4）。
func _gpLinks() -> Array[GPOffPageLink]:
	if gpCenter == null:
		return []
	return gpCenter.gpOffPageLinks


# Bind the DRC panel to the active canvas (called wherever the outline is bound, too).
# Bind the live DRC scheduler to a canvas's DATA. The scheduler is an app object and may not
# hold a GPCanvas2D (ADR-10), so this seam is the only place that converts view -> model.
# 把实时 DRC 调度器绑到画布的**数据**。调度器属 app，不可持有 GPCanvas2D（ADR-10），
# 故此处是「视图 → 模型」的唯一转换缝。
func _gpBindScheduler(gpCv: GPCanvas2D) -> void:
	if gpScheduler == null:
		return
	if gpCv == null:
		gpScheduler.gpBind(null, null, _gpDefs())
		return
	gpScheduler.gpBind(gpCv.gpGraph, gpCv.gpSheet, _gpDefs())


# 把 DRC 面板指向活动画布（与大纲绑定的每个入口一起调用）。
func gpBindActive() -> void:
	if gpPanel == null:
		return
	var gpCv: GPCanvas2D = _gpActiveCanvas()
	if gpCv != null:
		gpPanel.gpBindCanvas(gpCv)
		_gpBindScheduler(gpCv)


# Run the health check on the active sheet and expose the counts in the status bar.
# 对当前图纸跑体检，并把计数显示到状态栏。
#
# Public because the menu dispatcher calls it; keeping the tab-focusing here means every entry
# (menu, future shortcut) lands on the same visible surface instead of a silent background run.
# 设为公开供菜单分发调用；把「切到该页」放在这里，使每个入口（菜单、将来的快捷键）都落在同一个
# 可见界面上，而不是静默跑一次。
# Refresh the localised strings this panel owns (tab title + panel body). Called by the root's
# locale handler. The tab index is SEARCHED, not assumed: the root used to hard-code "last tab",
# which silently retitles the wrong tab the day another dock page is added after this one.
# 刷新本面板拥有的本地化文本（标签标题 + 面板正文）。由根类的语言切换处理器调用。
# 标签索引**靠查找**而非假定：根类原先硬编码「最后一页」，一旦本页之后再加一个停靠页，
# 就会静默改错页的标题。
func gpRefreshText() -> void:
	if gpPanel == null or gpTabs == null:
		return
	for gpI in range(gpTabs.get_tab_count()):
		if gpTabs.get_tab_control(gpI) == gpPanel:
			gpTabs.set_tab_title(gpI, I18n.gpTr("drc.panel_title"))
			break
	gpPanel.gpRefreshText()


func gpRun() -> void:
	if gpPanel == null:
		return
	gpBindActive()
	gpPanel.gpRun()
	# Bring the tab forward: a check whose result the user cannot see is not a check.
	# 把该页切到前面：用户看不见结果的体检不算体检。
	for gpI in range(gpTabs.get_tab_count()):
		if gpTabs.get_tab_control(gpI) == gpPanel:
			gpTabs.current_tab = gpI
			break
	var gpFound: Array[GPFinding] = gpPanel.gpFindings()
	_gpSetState("status.drc_done", [
		GPDrcEngine.gpCount(gpFound, GPFinding.GP_ERROR),
		GPDrcEngine.gpCount(gpFound, GPFinding.GP_WARNING),
		GPDrcEngine.gpCount(gpFound, GPFinding.GP_INFO),
	])


# Centre the view on a finding (B2). Vector2.INF means "no location" and is ignored.
# 把视图对准某条发现（B2）。Vector2.INF 表示「无位置」，忽略。
func _gpOnDrcJump(gpWorld: Vector2) -> void:
	if gpWorld == Vector2.INF:
		return
	var gpCv: GPCanvas2D = _gpActiveCanvas()
	if gpCv == null:
		return
	gpCv.gpFocusWorld(gpWorld)


# Open the top-toolbar DRC result dialog (ADR-39 UI). It stays non-modal so clicking a row can
# take the user to the canvas and the property panel without closing the list.
# 打开顶部工具栏的 DRC 结果弹窗（ADR-39 UI）。非模态，故点行后用户能到画布/属性面板，列表不关。
func gpShowDialog() -> void:
	if gpDialog == null:
		gpDialog = GPDRCDialog.new()
		gpDialog.name = "DrcDialog"
		add_child(gpDialog)
		gpDialog.gpFindingActivated.connect(_gpOnDrcFindingFromDialog)
	gpDialog.gpOpenFor(_gpActiveCanvas(), Callable(self, "_gpSheets"),
		Callable(self, "_gpLinks"))


# A row in the DOCK panel: locate + select, but do NOT switch tabs (the user may be reading the
# DRC list and must stay there until they choose the property tab themselves).
# 停靠面板的行：定位 + 选中，但**不**切页（用户可能正在看 DRC 列表，应由他自己切属性页）。
func _gpOnDrcFindingFromPanel(gpFinding: GPFinding) -> void:
	_gpFocusFinding(gpFinding, false)


# A row in the DIALOG: locate + select + switch to the property tab.
# 弹窗的行：定位 + 选中 + 切到属性页。
func _gpOnDrcFindingFromDialog(gpFinding: GPFinding) -> void:
	_gpFocusFinding(gpFinding, true)


# Live DRC result: refresh the dock panel silently (never switch tabs). Project mode is a
# manual, whole-project run and must not be overwritten by a sheet-only live pass.
# 实时 DRC 结果：静默刷新右侧面板（绝不切页）。全工程模式是手动整包运行，不能被单页实时结果覆盖。
# Keep the screen-space badges in step with the panel's current list (manual or live run).
# 让屏幕空间角标与面板当前列表保持一致（手动或实时运行）。
func _gpOnDrcFindingsForOverlay(gpFindings: Array[GPFinding]) -> void:
	if gpOverlay != null:
		gpOverlay.gpShow(gpFindings, _gpActiveSheetId())


func _gpActiveSheetId() -> String:
	var gpSheet: GPSheet = gpCenter.gpActiveSheet() if gpCenter != null else null
	return gpSheet.gpId if gpSheet != null else ""


func _gpOnLiveDrc(gpFindings: Array[GPFinding], gpGraph: GPPIDGraph) -> void:
	# Correlation is by GRAPH, not by canvas object: the scheduler (app) may not name GPCanvas2D.
	# A pane showing the same graph shows the same sheet, so graph identity is the honest test —
	# and it drops findings that arrive for a sheet the user already left.
	# 相关性按**图**判定，而非画布对象：调度器（app）不可命名 GPCanvas2D。显示同一张图的窗格即同一张
	# 图纸，故以图身份判定是诚实的判据 —— 且能丢弃用户已离开那张图纸后到达的发现。
	var gpCv: GPCanvas2D = _gpActiveCanvas()
	if gpCv == null or gpCv.gpGraph != gpGraph:
		return
	if gpPanel == null or gpPanel.gpIsProjectMode():
		return
	gpPanel.gpBindCanvas(gpCv)
	gpPanel.gpShowFindings(gpFindings)
	if gpOverlay != null:
		gpOverlay.gpShow(gpFindings, _gpActiveSheetId())


# Shared focus/selection. `gpSwitchToProps` is the single behavioural difference between the
# dialog and the dock panel.
# 共用定位/选中。`gpSwitchToProps` 是弹窗与停靠面板唯一的行为差异。
func _gpFocusFinding(gpFinding: GPFinding, gpSwitchToProps: bool, gpRetry: bool = true) -> void:
	if gpFinding == null:
		return
	# Project mode may point at another sheet: activate it first, then use the (new) active canvas.
	# 全工程模式可能指向另一张图纸：先激活它，再用新的活动画布。
	if gpFinding.gpSheetId != "" and gpCenter != null:
		var gpBefore: GPSheet = gpCenter.gpActiveSheet()
		gpCenter.gpActivateSheet(gpFinding.gpSheetId)
		var gpAfter: GPSheet = gpCenter.gpActiveSheet()
		if gpAfter == null or gpAfter.gpId != gpFinding.gpSheetId:
			# TabBar may publish the change on the next frame; retry once instead of focusing
			# the previous sheet (which is exactly the "click does nothing" symptom).
			# TabBar 可能下一帧才发布切换；重试一次，避免聚焦上一张图纸（正是「点了没反应」）。
			if gpRetry:
				call_deferred("_gpFocusFinding", gpFinding, gpSwitchToProps, false)
			return
	var gpCv: GPCanvas2D = _gpActiveCanvas()
	if gpCv == null:
		return
	# Title block / frame findings belong to the SHEET, not to a graph node. Select/focus them
	# through the sheet-furniture rect and show the DOC tab (their real property page).
	# 图签 / 图框类发现属于**图纸**而非图节点。按图纸陈设矩形定位，并打开 DOC（它们真正的属性页）。
	if _gpIsSheetFurnitureFinding(gpFinding) and gpCv.gpSheet != null:
		var gpFurniture: Rect2 = GPFrameGeometry.gpFrameRect(gpCv.gpSheet) \
			if gpFinding.gpCheckId.find("frame") >= 0 \
			else GPFrameGeometry.gpTitleBlockRect(gpCv.gpSheet)
		gpCv.gpFocusRect(gpFurniture)
		if gpOverlay != null:
			gpOverlay.gpShowFocusRect(gpFurniture)
		if gpSwitchToProps:
			gpTabs.current_tab = 2
		return
	# Graph entity: fit its rect (edge / node) or a small window around a shape point.
	# 图实体：按矩形适配（连线 / 节点），注释图形则围绕其点开小窗。
	if gpOverlay != null:
		gpOverlay.gpShowFocusRect(Rect2())
	if gpFinding.gpEdgeId != "":
		var gpEdgeRect: Rect2 = gpCv.gpEdgeRect(gpFinding.gpEdgeId)
		if gpEdgeRect.size != Vector2.ZERO:
			gpCv.gpFocusRect(gpEdgeRect, 2.5)
		elif gpFinding.gpWorld != Vector2.INF:
			gpCv.gpFocusRect(Rect2(gpFinding.gpWorld - Vector2(50.0, 35.0), Vector2(100.0, 70.0)), 2.5)
	elif gpFinding.gpNodeId != "":
		var gpNodeRect: Rect2 = gpCv.gpNodeRect(gpFinding.gpNodeId)
		if gpNodeRect.size != Vector2.ZERO:
			gpCv.gpFocusRect(gpNodeRect, 2.5)
		elif gpFinding.gpWorld != Vector2.INF:
			gpCv.gpFocusRect(Rect2(gpFinding.gpWorld - Vector2(50.0, 35.0), Vector2(100.0, 70.0)), 2.5)
	elif gpFinding.gpWorld != Vector2.INF:
		gpCv.gpFocusWorld(gpFinding.gpWorld)
	var gpSelected: bool = false
	if gpFinding.gpEdgeId != "" and gpCv.gpGraph != null \
			and gpCv.gpGraph.gpGetEdge(gpFinding.gpEdgeId) != null:
		gpCv.gpSetEdgeSelection([gpFinding.gpEdgeId])
		gpSelected = true
	elif gpFinding.gpNodeId != "" and gpCv.gpGraph != null \
			and gpCv.gpGraph.gpGetNode(gpFinding.gpNodeId) != null:
		gpCv.gpEdgeSel.clear()
		gpCv.gpShapeSel.clear()
		gpCv.gpSetSelection([gpFinding.gpNodeId])
		gpSelected = true
	elif gpFinding.gpShapeIdx >= 0 and gpCv.gpGraph != null \
			and gpFinding.gpShapeIdx < gpCv.gpGraph.gpShapes.size():
		gpCv.gpEdgeSel.clear()
		gpCv.gpSelection.clear()
		gpCv.gpShapeSel = [gpFinding.gpShapeIdx]
		gpCv.gpAnnounceShapeSelection()
		gpSelected = true
	if gpSwitchToProps and gpSelected:
		gpTabs.current_tab = 0


# Whether a finding targets the sheet's title block / frame rather than a graph entity.
# 判断一条发现是否指向图纸的图签 / 图框，而非图实体。
func _gpIsSheetFurnitureFinding(gpFinding: GPFinding) -> bool:
	if gpFinding.gpNodeId != "" or gpFinding.gpEdgeId != "" or gpFinding.gpShapeIdx >= 0:
		return false
	var gpId: String = gpFinding.gpCheckId if gpFinding.gpCheckId != "" else gpFinding.gpRuleId
	return gpId.begins_with("drc.doc.") or gpFinding.gpRuleId == "drc.sheet_fit"
