class_name GPCrossSheetController
extends Node
# Copyright © 2026 Jonson Wang
# Cross-sheet link domain: connect / inherit / navigate / sync / delete across sheets,
# plus the two drag gestures that create such links (connector drag and port drag).
# 跨图纸连接域：跨图纸的连接 / 继承 / 跳转 / 同步 / 删除，以及创建它们的两类拖拽手势
#（连接符拖拽与管口拖拽）。
#
# WHY THIS EXISTS / 为何存在：
# GPMainWindow had grown to 2,472 lines / 100 functions. Measurement, not taste, picked
# this block: 44 functions / 1,223 lines whose external surface is only gpCenter,
# gpInspector, the symbol-definition table and the status bar. Every one of the 12 pieces
# of private state it keeps (_gpRubber*, _gpDrag*, _gpCross*) was referenced ZERO times
# outside the block, and no coordinator ever called back into it. That makes it a seam,
# not a slice of a monolith.
# GPMainWindow 已长到 2,472 行 / 100 函数。切这里靠的是**测量**而非偏好：44 个函数 /
# 1,223 行的对外面只有 gpCenter、gpInspector、图元定义表与状态栏。它持有的 12 份私有状态
#（_gpRubber* / _gpDrag* / _gpCross*）在块外被引用**零**次，也没有任何协调者回调它 ——
# 这是接缝，不是把巨石切了一块。
#
# Interaction / 交互方式：
# - the composition root creates this node and injects four things: gpCenter, gpInspector,
#   gpDefsProvider (a Callable, NOT the array) and gpStateSink;
# 组合根创建本节点并注入四样东西：gpCenter、gpInspector、gpDefsProvider（是 Callable，
# **不是**数组）与 gpStateSink；
# - gpDefsProvider is deliberately a Callable: gpDefs is reassigned six times at runtime
#   (import / symbol delete), so a captured array would silently go stale and the peer-sheet
#   dropdown would list wrong symbol names with no test turning red.
# gpDefsProvider 刻意是 Callable：gpDefs 在运行期会被重新赋值六次（导入 / 删图元），
# 直接捕获数组会静默过期，使对端图纸下拉列出错误的图元名，且没有任何测试会红；
# - the root binds canvas / inspector signals to the gp* entry points here; this class never
#   reaches back into menus, docks or the file coordinator.
# 根类把画布 / 面板信号接到本类的 gp* 入口；本类绝不回指菜单、停靠栏或文件协调者。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Multi-sheet container: the ONLY heavy dependency (sheet table, active canvas, link table,
# screen-point hit test). 多图纸容器：**唯一**的重依赖（图纸表 / 活动画布 / link 表 / 屏幕点命中）。
var gpCenter: GPCenterArea = null

# Property inspector — needed by "jump to peer" alone, to show the peer edge's form.
# 属性面板 —— 仅「跳转到对端」需要它显示对端边的表单。
var gpInspector: GPInspector = null

# Symbol-definition provider (Callable -> Array[GPSymbolDef]). See the note above.
# 图元定义提供者（Callable -> Array[GPSymbolDef]）。原因见上方说明。
var gpDefsProvider: Callable = Callable()

# Status-bar sink (Callable -> void, signature (key: String, args: Array)).
# 状态栏接收端（Callable -> void，签名 (key: String, args: Array)）。
var gpStateSink: Callable = Callable()


# The live symbol-definition table, resolved on every call so it can never go stale.
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


# Look up one definition by id, mirroring GPMainWindow.gpDefFor.
# 按 id 查一个定义，与 GPMainWindow.gpDefFor 同义。
func _gpDefOf(gpTypeId: String) -> GPSymbolDef:
	for gpD in _gpDefs():
		if gpD.gpId == gpTypeId:
			return gpD
	return null


# Forward a status-bar update to the root (the label lives there).
# 把状态栏更新转发给根类（标签归它所有）。
func _gpSetState(gpKey: String, gpArgs: Array = []) -> void:
	if gpStateSink.is_valid():
		gpStateSink.call(gpKey, gpArgs)


# ============================ cross-sheet domain / 跨图纸连接域 ============================

# ============================ per-canvas wiring / 逐画布接线 ============================

# Wire every cross-sheet hook of ONE canvas. Called from the shell's canvas-ready handler, so
# each new sheet announces itself to this domain exactly once.
# 为**单张**画布接上全部跨图纸钩子。由外壳的 canvas-ready 处理器调用，故每张新图纸只向本域报到一次。
#
# WHY IT LIVES HERE / 为何放在这里：
# These 63 lines used to be the tail of `GPMainWindow._gpOnCanvasReady` — 11 signals plus the
# container link store — while the HANDLERS they connect to were already in this file (S1). The
# logic had moved; the wiring had not. That split made the root the only place where a new
# gesture could be registered, and it buried the `is_connected` bookkeeping among 11 unrelated
# connects (defs / document / selection / ribbon / symbol edit / title block / line attributes),
# where a missing one is invisible: the feature simply does nothing on sheet 2 and every sheet
# after it — no error, no failing test, just a gesture that stopped answering.
# 这 63 行原先是 `GPMainWindow._gpOnCanvasReady` 的尾部 —— 11 个信号加容器 link store —— 而它们
# 连接到的处理器早已在本文件里（S1）。逻辑搬走了，接线没搬。这个割裂使根类成为**唯一**能登记新
# 手势的地方，也把 `is_connected` 记账埋进了 11 条无关连接（定义 / 文档 / 选中 / Ribbon / 图元编辑 /
# 图签 / 管线属性）之中 —— 少一条是看不见的：该功能在第二张及之后的图纸上单纯不再响应，
# 没有报错、没有失败的测试，只有一个不再应答的手势。
#
# Idempotent / 幂等：a canvas may be announced twice when a tab is re-added, so every connect is
# guarded by is_connected.
# 画布可能被通告两次（标签页被重新加入），故每条连接都加 is_connected 守卫。
#
# Every signal below is declared on GPCanvas2D or GPEditService; the architecture test pins this
# list against both files, so a renamed signal cannot leave a silently dangling wire.
# 下列每个信号都声明在 GPCanvas2D 或 GPEditService 上；架构测试把清单与这两个文件对钉，
# 故信号改名不会留下一根**静默**的断线。
func gpWireCanvas(gpCanvas: GPCanvas2D) -> void:
	if gpCanvas == null:
		return
	# ADR-43 / S3: cross-sheet gestures, peer navigation / sync, and history settle — each
	# wired per canvas so the dialog and the snapshot always target the RIGHT sheet.
	# ADR-43 / S3：跨图纸手势、对端跳转 / 同步与历史落定 —— 逐画布接线，
	# 使对话框与快照永远作用于**正确的**那张图纸。
	if not gpCanvas.gpCrossSheetRequested.is_connected(gpOnCrossSheetRequested):
		gpCanvas.gpCrossSheetRequested.connect(gpOnCrossSheetRequested.bind(gpCanvas))
	if not gpCanvas.gpJumpToPeerRequested.is_connected(gpOnJumpToPeer):
		gpCanvas.gpJumpToPeerRequested.connect(gpOnJumpToPeer)
	if not gpCanvas.gpSyncToPeerRequested.is_connected(gpOnSyncToPeer):
		gpCanvas.gpSyncToPeerRequested.connect(gpOnSyncToPeer)
	if not gpCanvas.gpCrossSheetHistoryChanged.is_connected(gpCenter.gpOnCrossSheetHistory):
		gpCanvas.gpCrossSheetHistoryChanged.connect(gpCenter.gpOnCrossSheetHistory)
	# A2: inject the container link-store into THIS canvas's service, so every successful
	# cross-sheet command ends with ONE gpTouch() and the store's signal drives refreshes.
	# A2：把容器 link store 注入**本**画布的服务，使每条成功的跨图纸命令以一次 gpTouch()
	# 收尾，由 store 信号统一驱动刷新。
	gpCanvas.gpActions.gpLinkStore = gpCenter.gpLinkStore()
	if not gpCanvas.gpCrossSheetDeleteRequested.is_connected(gpOnCrossSheetDelete):
		gpCanvas.gpCrossSheetDeleteRequested.connect(gpOnCrossSheetDelete.bind(gpCanvas))
	# Cross-sheet line-number propagation (user feedback 2026-11-04): when THIS sheet's
	# line number is committed, the shell forwards it to the continuation edge on the peer
	# sheet. Bound per canvas so the SOURCE sheet is known without a second lookup.
	# 跨图纸管线号传播（用户反馈 2026-11-04）：**本**图纸的管线号落账时，外壳把它转发到
	# 对端图纸的延续边。逐画布绑定，无需二次查找即知**源**图纸。
	var gpTagCb: Callable = gpOnEdgeTagCommitted.bind(gpCanvas)
	if not gpCanvas.gpActions.gpEdgeTagCommitted.is_connected(gpTagCb):
		gpCanvas.gpActions.gpEdgeTagCommitted.connect(gpTagCb)
	# Cross-sheet attribute propagation (user feedback 2026-11-04, round 2): when THIS
	# sheet's line attributes are committed, the shell forwards the inheritable ones to the
	# continuation edge on the peer sheet. Bound per canvas, same shape as the tag signal.
	# 跨图纸属性传播（用户反馈 2026-11-04 第二轮）：**本**图纸的管线属性落账时，外壳把可继承
	# 的那些转发到对端图纸的延续边。逐画布绑定，与编号信号同构。
	var gpAttrsCb: Callable = gpOnEdgeAttrsCommitted.bind(gpCanvas)
	if not gpCanvas.gpActions.gpEdgeAttrsCommitted.is_connected(gpAttrsCb):
		gpCanvas.gpActions.gpEdgeAttrsCommitted.connect(gpAttrsCb)
	# Draw-time follow pull (user feedback 2026-11-04, round 3): when a pipe is DRAWN on
	# this sheet, the shell checks whether it feeds a B-end twin and pulls the source's
	# block + number at once — follow mode is on by default, so the very first auto number
	# must never linger on the canvas while the panel shows the source values.
	# 画线即拉取（用户反馈 2026-11-04 第三轮）：**本**图纸画成一条管线时，外壳检查它是否
	# 馈送某个 B 端孪生体并立刻拉取源端属性块与编号 —— 跟随默认开启，首个自动编号绝不能
	# 在画布上滞留而面板却显示源端值。
	var gpCreatedCb: Callable = gpOnEdgeCreated.bind(gpCanvas)
	if not gpCanvas.gpActions.gpEdgeCreated.is_connected(gpCreatedCb):
		gpCanvas.gpActions.gpEdgeCreated.connect(gpCreatedCb)
	# W13-S8 (user request 2026-11-03): the cross-pane drag-to-connect gesture — wired per
	# canvas so the SOURCE canvas is known at drop time without a second lookup.
	# W13-S8（用户需求 2026-11-03）：跨窗格拖拽连线手势 —— 逐画布接线，
	# 使落点时刻无需二次查找即知**源**画布。
	if not gpCanvas.gpCrossPaneDragUpdated.is_connected(gpOnCrossPaneDragUpdated):
		gpCanvas.gpCrossPaneDragUpdated.connect(gpOnCrossPaneDragUpdated.bind(gpCanvas))
	if not gpCanvas.gpCrossPaneDropped.is_connected(gpOnCrossPaneDropped):
		gpCanvas.gpCrossPaneDropped.connect(gpOnCrossPaneDropped.bind(gpCanvas))
	if not gpCanvas.gpCrossPaneDragEnded.is_connected(gpOnCrossPaneDragEnded):
		gpCanvas.gpCrossPaneDragEnded.connect(gpOnCrossPaneDragEnded)
	# ADR-46 entry 2 (user request 2026-11-06): the cross-pane PORT link gesture — pulling
	# from a nozzle of a selected symbol across panes. Wired per canvas for the same reason
	# as W13-S8: the source canvas must be known at drop time.
	# ADR-46 入口 2（用户需求 2026-11-06）：跨窗格**端口**连线手势 —— 从已选中图元的管口
	# 拖出、跨越窗格。与 W13-S8 同理逐画布接线：落点时刻即知**源**画布。
	if not gpCanvas.gpPortLinkUpdated.is_connected(gpOnPortLinkUpdated):
		gpCanvas.gpPortLinkUpdated.connect(gpOnPortLinkUpdated.bind(gpCanvas))
	if not gpCanvas.gpPortLinkDropped.is_connected(gpOnPortLinkDropped):
		gpCanvas.gpPortLinkDropped.connect(gpOnPortLinkDropped.bind(gpCanvas))
	if not gpCanvas.gpPortLinkEnded.is_connected(gpOnPortLinkEnded):
		gpCanvas.gpPortLinkEnded.connect(gpOnPortLinkEnded)


# Wire the property panel's cross-sheet face. Same rule as the canvas: whoever owns the
# handlers owns the wiring. The panel is ONE instance shared by every sheet, so this runs
# once at assembly, and nothing here is per-sheet — the panel asks for the current sheet at
# CALL time (see gpSheetsProvider below), so a tab switch never needs a re-wire.
# 接上属性面板的**跨图纸**面。与画布同一条规矩：谁持有处理器，谁持有接线。面板为所有图纸
# 共用的**单一**实例，故装配时接一次；此处无一逐图纸，面板在**调用时**才取当前图纸
#（见下方 gpSheetsProvider），切换标签页永不需重接。
#
# WAS / 原在何处：these eight wires lived in GPMainWindow._gpAssembleInspector() and merely
# LOOKED like the shell's business — every handler on the right-hand side already lived in
# this class, and gpLinksProvider / gpSheetsProvider reach for gpCenter, which is this
# class's own dependency. Measuring found no new injection was needed to move them.
# 这八条接线原在 GPMainWindow._gpAssembleInspector()，看着像外壳的事 —— 而右侧每个处理器
# 本就在本类里，两个 provider 要的 gpCenter 也是本类自有依赖。测量表明搬迁**不需要**新注入。
func gpWireInspector() -> void:
	if gpInspector == null:
		return
	# Off-page link list for the selected symbol (the dropdown re-connects, ADR-43 / S4-4).
	# 选中图元的跨页连接列表（下拉即重连，ADR-43 / S4-4）。
	gpInspector.gpLinksProvider = Callable(gpCenter, "gpOffPageLinksList")
	# U3 action row (user feedback 2026-11-04): jump / unlink / delete.
	# U3 动作行（用户反馈 2026-11-04）：跳转 / 断开 / 删除。
	if not gpInspector.gpJumpToPeerRequested.is_connected(gpOnJumpToPeer):
		gpInspector.gpJumpToPeerRequested.connect(gpOnJumpToPeer)
	if not gpInspector.gpUnlinkRequested.is_connected(gpOnInspectorUnlink):
		gpInspector.gpUnlinkRequested.connect(gpOnInspectorUnlink)
	if not gpInspector.gpLinkDeleteRequested.is_connected(gpOnInspectorLinkDelete):
		gpInspector.gpLinkDeleteRequested.connect(gpOnInspectorLinkDelete)
	# The peer-sheet dropdown's data source + the pick hand-off (user feedback 2026-11-03).
	# A closure, not a captured table: sheets are added / deleted / renamed at runtime and a
	# snapshot would quietly list the wrong peers.
	# 对端图纸下拉的数据源与选择移交（用户反馈 2026-11-03）。用闭包而非捕获好的表：
	# 图纸在运行期增删改名，快照会静默列出错误的对端。
	gpInspector.gpSheetsProvider = func() -> Dictionary:
		var gpCur: GPSheet = gpCenter.gpActiveSheet()
		return {"sheets": gpCenter.gpToSheets(),
			"current": gpCur.gpId if gpCur != null else ""}
	if not gpInspector.gpConnectPickRequested.is_connected(gpOnInspectorConnectPick):
		gpInspector.gpConnectPickRequested.connect(gpOnInspectorConnectPick)
	# Cross-sheet inherit checkbox on the continuation edge (user feedback 2026-11-04):
	# visibility is a B-side-continuation question this controller already answers, and the
	# toggle lands back here.
	# 延续边上的跨图纸继承勾选框（用户反馈 2026-11-04）：可见性是「仅 B 端延续段」的判定，
	# 本就由本控制器回答；开关动作也落回此处。
	gpInspector.gpEdgeInheritProvider = Callable(self, "gpEdgeInheritInfo")
	if not gpInspector.gpEdgeInheritToggled.is_connected(gpOnEdgeInheritToggled):
		gpInspector.gpEdgeInheritToggled.connect(gpOnEdgeInheritToggled)


# ---- ADR-43 / S3: cross-sheet connection ----
# ---- ADR-43 / S3：跨图纸连接 ----

# Lazily created "cross-sheet connection" dialog. Deliberately UNTYPED: annotating would
# pull the dialog into the startup dependency graph (same rule as _gpOpenLineAttrs).
# 惰性创建的「跨图纸连接」对话框。刻意不写类型：标注会把对话框拉进启动依赖图
#（与 _gpOpenLineAttrs 同一规则）。
var _gpOffPageDialog = null

# The gesture waiting for the dialog's answer: which canvas, which source ref, where.
# 等待对话框回答的手势：哪块画布、哪个源端、落点在哪。
var _gpCrossPending: Dictionary = {}

# One-shot sheet preselect, set when the inspector's peer-sheet dropdown routes a pick here.
# 一次性图纸预选，属性面板的对端图纸下拉把选择路由进来时设置。
var _gpCrossPreselect: String = ""


# A line was dropped out of frame, or an existing connector asked for a peer: open the
# dialog for the CURRENT sheet list. The canvas stays a pure requester.
# 一条线落出图框，或既有连接符请求对端：为**当前**图纸列表打开对话框。
# 画布保持纯请求者身份。
func gpOnCrossSheetRequested(gpFromRef: Dictionary, gpWorld: Vector2, gpKind: String,
		gpSignalType: String, gpCanvas: GPCanvas2D) -> void:
	var gpPre: String = _gpCrossPreselect
	_gpCrossPreselect = ""
	_gpCrossPending = {"canvas": gpCanvas, "from_ref": gpFromRef, "world": gpWorld,
		"kind": gpKind, "signal_type": gpSignalType, "preselect": gpPre}
	if _gpOffPageDialog == null:
		_gpOffPageDialog = (load("res://src/ui/dialogs/off_page_connect_dialog.gd")
			as GDScript).new()
		add_child(_gpOffPageDialog)
		_gpOffPageDialog.gpConnectChosen.connect(_gpOnCrossSheetChosen)
	# D06: the excluded sheet is the one the SOURCE CANVAS shows — never "whatever tab is
	# active". In multi-view, a non-active pane's gesture used to offer its own sheet as a
	# target; confirming it silently did nothing.
	# D06：被排除的图纸是**源画布**所显示的那张 —— 绝不是「当前哪个标签活动」。多视图下
	# 非活动窗格的手势曾把本图列为可选目标，选中确认后静默无反应。
	var gpLocal: GPSheet = gpCanvas.gpSheet
	_gpOffPageDialog.gpSetup(gpCenter.gpToSheets(), _gpDefs(),
		gpLocal.gpId if gpLocal != null else "", gpPre)


# The inspector's peer-sheet dropdown picked a sheet for an UNLINKED connector: route the
# pick through the VERY same canvas gesture the context menu uses (one code path into the
# dialog and, behind it, the command), with the sheet handed over as a preselect.
# 属性面板的对端图纸下拉为未连线连接符选定了一张图纸：把该选择路由进与右键菜单
# **完全相同**的画布手势（进入对话框乃至其后的命令只有**一条**代码路径），图纸以预选
# 形式移交。
func gpOnInspectorConnectPick(gpNodeId: String, gpSheetId: String) -> void:
	var gpCanvas: GPCanvas2D = gpCenter.gpActiveCanvas()
	if gpCanvas == null:
		return
	# RE-CONNECT (user feedback 2026-11-04): the pick can come from a LINKED connector's
	# "跨图编号" dropdown. Break the old link FIRST (one undo step, both flags stay) — the
	# creation path only accepts an UNLINKED connector (mode B), and skipping this would
	# mint a duplicate connector + link. A cancelled dialog leaves the connector honestly
	# unlinked; Ctrl+Z restores the old connection.
	# **重连**（用户反馈 2026-11-04）：选择可能来自**已连接**连接符的「跨图编号」下拉。
	# 先断开旧连接（一个撤销步、两面旗标保留）—— 创建路径只接受**未连接**连接符（模式 B），
	# 跳过这步会铸出重复的连接符与 link。取消对话框则连接符诚实地回到未连接态；
	# Ctrl+Z 恢复旧连接。
	var gpNode: GPPIDNode = gpCanvas.gpGraph.gpGetNode(gpNodeId) \
		if gpCanvas.gpGraph != null else null
	var gpLinkId: String = str(gpNode.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")) \
		if gpNode != null else ""
	if gpLinkId != "":
		if not _gpBreakLinkForReconnect(gpLinkId, gpCanvas):
			return
	_gpCrossPreselect = gpSheetId
	gpCanvas.gpRequestCrossSheet(
		{"node_id": gpNodeId, "port_id": GPSymbolPackOffpage.GP_PORT_NAME},
		Vector2.ZERO, GPPIDEdge.GP_PROCESS, "")


# The reconnect half-step: unlink THIS link through the SAME command the 断开 button uses
# (both flags stay). The peer graph comes from the SHEET TABLE — a hidden (X-closed) peer
# sheet must not block a reconnect. False = refused, nothing opened.
# 重连的半步：经与「断开」按钮**同一条**命令断开本 link（两面旗标保留）。对端图取自
# **图纸表** —— 对端图纸被 X 隐藏时不得阻断重连。假 = 被拒，不打开对话框。
func _gpBreakLinkForReconnect(gpLinkId: String, gpCanvas: GPCanvas2D) -> bool:
	var gpLink: GPOffPageLink = _gpLinkById(gpLinkId)
	if gpLink == null or gpCanvas.gpActions == null or gpCanvas.gpGraph == null:
		return false
	var gpPeerSheetId: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_SHEET, ""))
	if str(gpLink.gpA.get(GPOffPageLink.GP_KEY_SHEET, "")) == gpCanvas.gpSheet.gpId:
		gpPeerSheetId = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_SHEET, ""))
	else:
		gpPeerSheetId = str(gpLink.gpA.get(GPOffPageLink.GP_KEY_SHEET, ""))
	var gpPeerGraph: GPPIDGraph = null
	for gpS in gpCenter.gpToSheets():
		if gpS.gpId == gpPeerSheetId:
			gpPeerGraph = gpS.gpGraph
	if gpPeerGraph == null:
		_gpSetState("offpage.refuse_sheet_missing", [])
		return false
	# gpKeepPeerClaim = true (user feedback 2026-11-05): the OLD target did not ask to be
	# unlinked — its flag keeps the stale claim, renders "?" with an amber line, and the DRC
	# strays rule reports it, so the orphaned continuation stays visible and checkable.
	# gpKeepPeerClaim = true（用户反馈 2026-11-05）：**原目标端**并没有要求被断开 ——
	# 它的旗标保留陈旧声称、渲染「?」、连线染琥珀色，DRC strays 规则照报，被遗弃的
	# 延续保持可见、可查。
	if gpCanvas.gpActions.gpUnlinkOffPage(gpLink, gpCenter.gpOffPageLinks,
			gpCanvas.gpGraph, gpPeerGraph, true):
		# A2: the store signal already refreshed/dirtied the canvases.
		# A2：store 信号已刷新并标脏画布。
		_gpSetState("offpage.unlink_done", [])
		return true
	_gpSetState("offpage.unlink_fail", [])
	return false


# The user picked a target and confirmed. Resolve what the dialog cannot know (peer graph,
# drawing number) and hand the WHOLE gesture to the shared creation helper below.
# 用户选定目标并确认。解析对话框无法知晓的事实（对端图、图号），把整个手势交给下方的
# 共用创建助手。
func _gpOnCrossSheetChosen(gpTarget: Dictionary) -> void:
	var gpCanvas: GPCanvas2D = _gpCrossPending.get("canvas")
	if gpCanvas == null or gpTarget.is_empty():
		return
	_gpCreateCrossLink(gpCanvas, _gpCrossPending.get("from_ref", {}),
		str(_gpCrossPending.get("kind", GPPIDEdge.GP_PROCESS)),
		str(_gpCrossPending.get("signal_type", "")),
		_gpCrossPending.get("world", Vector2.ZERO),
		str(gpTarget.get("sheet_id", "")),
		{"node_id": str(gpTarget.get("node_id", "")),
			"port_id": str(gpTarget.get("port_id", ""))})


# THE one creation path for a cross-sheet link, shared by the dialog flow and the W13-S8
# cross-pane drag. Resolves the sheet-level facts (peer sheet, drawing number, twin landing
# slot), decides mode A/B from the fromRef node, runs the command, republishes the render
# snapshot and reports the result. Returns the link id ("" = refused).
# 跨图纸 link 的**唯一**创建路径，对话框流程与 W13-S8 跨窗格拖拽共用。解析图纸级事实
#（对端图、图号、孪生体落位槽）、按 fromRef 节点判定模式 A/B、执行命令、重发渲染快照并
# 报告结果。返回 link id（"" = 被拒）。
func _gpCreateCrossLink(gpCanvas: GPCanvas2D, gpFromRef: Dictionary, gpKind: String,
		gpSignalType: String, gpWorld: Vector2, gpPeerSheetId: String,
		gpServed: Dictionary) -> String:
	if gpCanvas == null or gpCanvas.gpActions == null or gpFromRef.is_empty():
		return ""
	# The LOCAL sheet is the one the SOURCE CANVAS shows — never "whatever tab is active":
	# with multi-view (W13) the two can differ the moment a second pane takes focus.
	# **本端图纸**是**源画布**所显示的那张 —— 绝不是「当前哪个标签活动」：多视图（W13）下
	# 一旦第二窗格获焦，二者就可能不同。
	var gpLocalSheet: GPSheet = gpCanvas.gpSheet
	# D06: every early exit maps to a readable status message — a silent return "" used to
	# leave the user with a closed dialog and zero feedback.
	# D06：每个早退分支都映射到一条可读状态消息 —— 过去静默 return ""，用户只看到对话框
	# 关闭而毫无反馈。
	if gpLocalSheet == null or gpPeerSheetId == "":
		_gpSetState("offpage.refuse_sheet_missing", [])
		return ""
	if gpPeerSheetId == gpLocalSheet.gpId:
		_gpSetState("offpage.refuse_same_sheet", [])
		return ""
	var gpPeerSheet: GPSheet = null
	for gpS in gpCenter.gpToSheets():
		if gpS.gpId == gpPeerSheetId:
			gpPeerSheet = gpS
	if gpPeerSheet == null:
		_gpSetState("offpage.refuse_sheet_missing", [])
		return ""
	if gpPeerSheet.gpGraph == null:
		_gpSetState("offpage.refuse_peer_graph_missing", [])
		return ""
	# The twin lands in the peer sheet's LEFT connector column (user feedback 2026-11-03:
	# always on the left, stacked top-down) — never at a bare drop point, and never as a
	# child of the target item.
	# 孪生体落在对端图纸**左侧的连接符列**（用户反馈 2026-11-03：永远在左侧、自上而下堆叠）
	# —— 绝不落在裸落点上，也绝不成为目标对象的子件。
	var gpEnv: Vector2 = GPSymbolCategories.gpSizeFor(GPSymbolPackOffpage.GP_CATEGORY)
	# D16: the column member test is the CATEGORY predicate (user-pack connectors stack too),
	# not a builtin symbol-id list. The shell's own def lookup covers user packs.
	# D16：列成员判定走**类别**判谓（用户包连接符同样参与堆叠），而非内置符号 id 名单。
	# 外壳自带的 def 查找覆盖用户包。
	var gpPeerLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		return _gpDefOf(gpSymId)
	var gpPeerPos: Vector2 = GPOffPageIndex.gpNextLeftSlot(gpPeerSheet.gpGraph,
		GPFrameGeometry.gpFrameRect(gpPeerSheet), gpEnv,
		func(gpN: GPPIDNode) -> bool:
			return GPOffPageIndex.gpIsConnectorNode(gpN, gpPeerLookup))
	# The pick is the item the twin serves — but only a node that REALLY exists there (a
	# stale pick degrades to a bare twin, exactly as the dialog path always did).
	# 所选即孪生体要**服务**的对象 —— 但只认对端图上**真实存在**的节点（陈旧所选退化为
	# 裸孪生体，与对话框路径的既有行为完全一致）。
	var gpServedFinal: Dictionary = {}
	if not gpServed.is_empty() \
			and gpPeerSheet.gpGraph.gpGetNode(str(gpServed.get("node_id", ""))) != null:
		gpServedFinal = gpServed
	# MODE B when the gesture started ON an unlinked connector: the link attaches to it and
	# no local node is created.
	# 手势始于**未连接的连接符**时走模式 B：link 直接挂它，不新建本端节点。
	var gpExistingLocal: String = ""
	var gpSourceId: String = str(gpFromRef.get("node_id", ""))
	var gpSource: GPPIDNode = gpCanvas.gpGraph.gpGetNode(gpSourceId) if gpSourceId != "" else null
	var gpSourceIsConnector: bool = gpSource != null \
		and (gpSource.gpSymbolId == GPSymbolPackOffpage.GP_ID_PIPE \
			or gpSource.gpSymbolId == GPSymbolPackOffpage.GP_ID_SIGNAL) \
		and str(gpSource.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")) == ""
	if gpSourceIsConnector:
		gpExistingLocal = gpSourceId
		# D07: the link kind follows the CONNECTOR's own port purpose, not the entry path's
		# guess — re-derived HERE for every entry path (context menu, inspector pick, drag),
		# so a signal connector always produces a SIGNAL link (the inspector used to
		# hardcode PROCESS and DRC immediately flagged kind_mismatch).
		# D07：link 类别跟随**连接符自身的端口用途**，而非入口路径的猜测 —— 在此为所有
		# 入口路径（右键菜单 / 属性面板 / 拖拽）单点重推导，信号连接符必然产出 SIGNAL
		# 连接（属性面板曾硬编码 PROCESS，DRC 立刻报 kind_mismatch）。
		gpKind = _gpKindForConnector(gpSource)
		if gpKind == GPPIDEdge.GP_SIGNAL and gpSignalType == "":
			gpSignalType = "ELECTRIC"
	var gpLinkId: String = gpCanvas.gpActions.gpCrossSheetCreate(gpFromRef, gpKind,
		gpSignalType, true, _gpSnapLocalFlag(gpWorld, gpLocalSheet, gpEnv), gpPeerPos,
		gpLocalSheet.gpId, gpPeerSheetId, gpPeerSheet.gpNumber, gpPeerSheet.gpGraph,
		gpCenter.gpOffPageLinks, gpExistingLocal, {}, gpServedFinal)
	if gpLinkId == "":
		# D24: cross-sheet refusal keys live under offpage.refuse_*, not edge.* — without
		# the prefix the status bar shows a raw key like "edge.same_sheet".
		# D24：跨图纸拒绝键在 offpage.refuse_* 名下而非 edge.* —— 不传前缀状态栏会显示
		# 「edge.same_sheet」这样的裸键。
		gpCanvas.gpReportRefusal(gpCanvas.gpActions.gpLastRefusal, "offpage.refuse_")
		return ""
	# The link table change is announced by the store's signal (A2): snapshot republish,
	# dirty marks and repaints follow from there — no manual refresh here.
	# link 表的变化由 store 信号通告（A2）：快照重发、脏标记与重绘都从那里跟随 —— 此处
	# 不再手工刷新。
	var gpTag: String = ""
	var gpNewLink: GPOffPageLink = null
	for gpL in gpCenter.gpOffPageLinks:
		if gpL != null and gpL.gpInstanceId == gpLinkId:
			gpTag = gpL.gpTag
			gpNewLink = gpL
	# ROUND 3 (user feedback 2026-11-04): a continuation edge may ALREADY stand on the B-end
	# sheet — drawn from the unlinked twin before this link existed (the inspector reconnect
	# flow draws nothing itself). Pull the source block + number through the B-side sheet's
	# own service, exactly as the draw-time pull would have. The mode-A peer connect (created
	# in the same command with the preset tag) no-ops on the tag but still receives the ATTRS.
	# 第三轮（用户反馈 2026-11-04）：B 端图纸上可能**早已立着**一条延续边 —— 本 link 存在前
	# 就从未连接的孪生体画好了（属性面板重连流自己不画线）。经 B 端图纸**自己的**服务拉取
	# 源端属性块与编号，与画线即拉取完全同构。模式 A 的对端连线（同一命令内以预置号创建）
	# 编号相等空转，但**属性**仍会被拉平。
	if gpNewLink != null:
		var gpBNodeId: String = str(gpNewLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
		var gpBSheetId: String = str(gpNewLink.gpB.get(GPOffPageLink.GP_KEY_SHEET, ""))
		if gpBNodeId != "":
			var gpBCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(gpBSheetId)
			if gpBCanvas != null and gpBCanvas.gpGraph != null:
				var gpBEdge: GPPIDEdge = _gpEdgeTouching(gpBCanvas.gpGraph, gpBNodeId)
				if gpBEdge != null:
					_gpPullFollowState(gpBCanvas, gpBEdge.gpInstanceId)
	# D18 (user feedback 2026-11-04): the creation must LAND visibly — flash both flags, and
	# when the peer sheet is not visible anywhere (no pane, not popped out), open it in the
	# first EMPTY pane so the user can see what just happened on the other sheet.
	# D18（用户反馈 2026-11-04）：创建必须有**落地感** —— 两端旗标短促高亮；对端图纸未在
	# 任何视图显示（无窗格、未摘出）时，打开进**第一个空窗格**，让用户看见对端那张图刚发生了什么。
	_gpFlashLinkEnds(gpLinkId)
	# D25 (ADR-46, 2026-11-05): the peer sheet must be SEEN — reveal it per the user's
	# priority (single view → side-by-side; multi-view → shown pane / empty pane / swap
	# into the non-active pane) and put the FOCUS on the revealing pane. Case ① (already
	# shown) still re-focuses, so the twin's flash lands where the user is looking.
	# D25（ADR-46，2026-11-05）：对端图纸必须**被看见** —— 按用户拍板的优先级揭示
	#（单视图 → 左右二分；多视图 → 已显示窗格 / 空窗格 / 换入非活动窗格），并把**焦点**
	# 放到揭示窗格。情形 ①（已显示）同样重新聚焦，让孪生体的高亮落在用户视线里。
	if gpCenter.gpRevealPeerSheet(gpPeerSheetId):
		_gpSetState("offpage.status_created_opened", [gpTag])
		return gpLinkId
	_gpSetState("offpage.status_created", [gpTag])
	return gpLinkId


# D18: flash BOTH ends of a fresh link — the drop-highlight rect on each end's own canvas,
# cleared after a beat. A token guards against clearing a NEWER highlight (a drag that
# started meanwhile) — only the newest flash may clear.
# D18：新 link 的**两端**短促高亮 —— 各自在所在画布上画落点高亮框，一拍半后清除。令牌防止
# 清掉**更新**的高亮（期间用户开始了拖拽）—— 只有最新一次闪光可以清除。
func _gpFlashLinkEnds(gpLinkId: String) -> void:
	var gpLink: GPOffPageLink = null
	for gpL in gpCenter.gpOffPageLinks:
		if gpL.gpInstanceId == gpLinkId:
			gpLink = gpL
			break
	if gpLink == null:
		return
	var gpEnds: Array = [gpLink.gpA, gpLink.gpB]
	_gpFlashToken += 1
	var gpToken: int = _gpFlashToken
	for gpEnd in gpEnds:
		var gpRef: Dictionary = gpEnd
		var gpCv: GPCanvas2D = gpCenter.gpCanvasForSheetId(
			str(gpRef.get(GPOffPageLink.GP_KEY_SHEET, "")))
		var gpNode: String = str(gpRef.get(GPOffPageLink.GP_KEY_NODE, ""))
		if gpCv != null and gpNode != "":
			gpCv.gpSetDropHighlight(gpNode)
	var gpClear: Callable = func() -> void:
		if gpToken != _gpFlashToken:
			return
		for gpEnd in gpEnds:
			var gpRef2: Dictionary = gpEnd
			var gpCv2: GPCanvas2D = gpCenter.gpCanvasForSheetId(
				str(gpRef2.get(GPOffPageLink.GP_KEY_SHEET, "")))
			var gpNode2: String = str(gpRef2.get(GPOffPageLink.GP_KEY_NODE, ""))
			if gpCv2 != null and is_instance_valid(gpCv2) and gpNode2 != "":
				gpCv2.gpSetDropHighlight("")
	get_tree().create_timer(1.4).timeout.connect(gpClear, CONNECT_ONE_SHOT)


# D07: derive the link kind from the connector's OWN port purpose — the single
# discriminator shared with the generator and the audit (no symbol-id lists anywhere).
# D07：由连接符**自身的端口用途**推导 link 类别 —— 与生成器、审计共用的唯一判据
#（代码里没有任何符号 id 名单）。
func _gpKindForConnector(gpNode: GPPIDNode) -> String:
	if gpNode == null:
		return GPPIDEdge.GP_PROCESS
	var gpDef: GPSymbolDef = _gpDefOf(gpNode.gpSymbolId)
	if gpDef != null and not gpDef.gpPortsOfType(GPPort.GP_SIGNAL).is_empty():
		return GPPIDEdge.GP_SIGNAL
	return GPPIDEdge.GP_PROCESS


# D17 minimal fix (user feedback 2026-11-04): the out-of-frame gesture DEFINES the drop
# point as outside the frame — clamp the local flag into the frame rect (pad = half an
# offpage envelope) so it can never print off-paper. The full edge-snapping stays in P3
# (R4); mode B (existing local connector) never consumes this position.
# D17 完整吸附（2026-11-04，R4）：出图框手势的松手点**只决定走向哪一侧** —— 本端旗标吸附
# 进最近图框边的连接符列/行（与对端左列同一套堆叠家族），绝不落在松手点上。退化情形
#（无图框）回落到钳制。模式 B（本端既有连接符）不消费该位置。
# D26 (2026-11-06 user feedback): the SOURCE flag ALWAYS lands in the RIGHT connector
# column — top-down stacking, ≈ 1/12 of the frame width inside the right border. The
# device/drop point no longer picks the side (supersedes D17-R4's nearest-edge choice);
# gpWorld only feeds the degenerate no-frame clamp.
# D26（2026-11-06 用户反馈）：**源端**旗标一律落**右列** —— 自上而下堆叠、距右内边框
# 约 1/12 图幅宽。设备/松手点不再选边（取代 D17-R4 的最近边选择）；gpWorld 仅用于
# 无图框退化回路的钳制。
func _gpSnapLocalFlag(gpWorld: Vector2, gpSheet: GPSheet, gpEnv: Vector2) -> Vector2:
	if gpSheet == null or gpSheet.gpGraph == null:
		return _gpClampIntoFrame(gpWorld, gpSheet, gpEnv)
	var gpLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		return _gpDefOf(gpSymId)
	return GPOffPageIndex.gpNextRightSlot(gpSheet.gpGraph,
		GPFrameGeometry.gpFrameRect(gpSheet), gpEnv,
		func(gpN: GPPIDNode) -> bool:
			return GPOffPageIndex.gpIsConnectorNode(gpN, gpLookup))


# D17 最小止血的几何钳制（保留为退化回路与模式 B 语义兜底）：把本端旗标钳进图框矩形
#（内边距 = 半个离页连接符包络）。
func _gpClampIntoFrame(gpWorld: Vector2, gpSheet: GPSheet, gpEnv: Vector2) -> Vector2:
	if gpSheet == null:
		return gpWorld
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(gpSheet)
	var gpPad: float = minf(gpEnv.x, gpEnv.y) * 0.5
	var gpLo: Vector2 = gpFrame.position + Vector2(gpPad, gpPad)
	var gpHi: Vector2 = gpFrame.end - Vector2(gpPad, gpPad)
	if gpHi.x <= gpLo.x or gpHi.y <= gpLo.y:
		return gpFrame.get_center()
	return gpWorld.clamp(gpLo, gpHi)


# ---- W13-S8: cross-pane drag-to-connect (the SECOND connection logic) ----
# ---- W13-S8：跨窗格拖拽连线（第二种连接逻辑）----

# The canvas currently showing a drop highlight, and the highlighted node ("" = none).
# 当前显示落点高亮的画布，与被高亮的图元（"" = 无）。
var _gpDragHlCanvas: GPCanvas2D = null
var _gpDragHlNode: String = ""

# D18: token of the newest link-end flash — only the newest may clear the highlights.
# D18：最新一次 link 端闪光令牌 —— 只有最新一次可以清除高亮。
var _gpFlashToken: int = 0

# D23: cross-pane RUBBER BAND — a full-rect, mouse-transparent overlay on the shell that
# draws the pending connection from the SOURCE flag to the pointer, across pane borders.
# D23：跨窗格**橡皮筋** —— 外壳上的满矩形、鼠标透明覆盖层，画出从**源**旗标到指针的
# 待定连接，跨越窗格边界。
var _gpRubber: Control = null
var _gpRubberActive: bool = false
var _gpRubberFrom: Vector2 = Vector2.ZERO
var _gpRubberTo: Vector2 = Vector2.ZERO

# D23: the dragged source connector (canvas + id) so its "connecting" feedback (dimmed
# view) can be restored whatever way the gesture ends.
# D23：被拖拽的源连接符（画布 + id），使它的「连线中」反馈（视图变暗）无论手势如何结束
# 都能恢复。
var _gpDragSrcCanvas: GPCanvas2D = null
var _gpDragSrcNode: String = ""


# A connector is being dragged across panes: highlight the node under the pointer in
# whichever OTHER canvas is under it. The source canvas never highlights itself.
# 连接符正被拖过窗格：在其下方的**另一块**画布中高亮指针下的图元。源画布永不高亮自己。
func gpOnCrossPaneDragUpdated(gpNodeId: String, gpScreen: Vector2,
		gpSource: GPCanvas2D) -> void:
	# D23: the source flag dims and the rubber band follows the pointer — the gesture is
	# now VISIBLE on the source side too, not just as a rectangle on the target.
	# D23：源旗标变暗、橡皮筋跟随指针 —— 手势在**源**一侧也可见，而不只是目标上的矩形。
	_gpSetDragSourceFeedback(gpSource, gpNodeId, true)
	_gpRubberUpdate(gpSource, gpNodeId, gpScreen)
	# A4: the drag point is SCREEN-space; the host lookup reads the same space.
	# A4：拖拽点是**屏幕**空间；宿主查找读同一空间。
	var gpTarget: GPCanvas2D = gpCenter.gpCanvasAtScreenPoint(gpScreen)
	if gpTarget == gpSource:
		gpTarget = null
	_gpClearDragHighlight()
	if gpTarget == null:
		return
	var gpWorld: Vector2 = gpTarget.gpWorldFromScreen(gpTarget.get_local_mouse_position())
	var gpHit: String = gpTarget.gpHitTest(gpWorld)
	# Same-sheet targets are refused by the creation helper anyway; refusing the HIGHLIGHT
	# too keeps what you see (an accent box) and what you get (a link) in agreement.
	# 同图纸目标本就会被创建助手拒绝；高亮同样拒绝，使「看到的」（accent 框）与「得到的」
	#（一条连接）始终一致。
	if gpHit != "" and gpTarget.gpSheet != null and gpSource.gpSheet != null \
			and gpTarget.gpSheet.gpId == gpSource.gpSheet.gpId:
		return
	_gpDragHlCanvas = gpTarget
	_gpDragHlNode = gpHit
	if gpHit != "":
		gpTarget.gpSetDropHighlight(gpHit)


# The drag was released over a point: resolve the target node and build the link through the
# ONE shared creation path. Kind/signal follow the CONNECTOR's family (pipe vs signal), the
# same defaults the tools use.
# 拖拽在一点上松手：解析目标图元，经**唯一**的共用创建路径建立连接。类型 / 信号随**连接符**
# 的族别（管 / 信号），与工具的默认一致。
func gpOnCrossPaneDropped(gpNodeId: String, gpScreen: Vector2, gpSource: GPCanvas2D) -> void:
	_gpClearDragHighlight()
	_gpRubberStop()
	_gpSetDragSourceFeedback(gpSource, gpNodeId, false)
	# A4: the drag point is SCREEN-space; the host lookup reads the same space.
	# A4：拖拽点是**屏幕**空间；宿主查找读同一空间。
	var gpTarget: GPCanvas2D = gpCenter.gpCanvasAtScreenPoint(gpScreen)
	# Dropped OUTSIDE every view (canvas + popup): a deliberate cancel — stay silent.
	# 落在所有视图（画布 + 弹窗）**之外**：刻意的取消 —— 保持沉默。
	if gpTarget == null:
		return
	var gpSrcSheet: GPSheet = gpSource.gpSheet
	var gpTgtSheet: GPSheet = gpTarget.gpSheet
	# D23: an invalid drop says WHY — dropping back on the source sheet is the same-sheet
	# refusal, not a silent nothing.
	# D23：无效落点要说明**原因** —— 落回源图纸就是「同图纸不能连」的拒绝，而非无声无息。
	if gpTarget == gpSource or (gpSrcSheet != null and gpTgtSheet != null \
			and gpSrcSheet.gpId == gpTgtSheet.gpId):
		_gpSetState("offpage.refuse_same_sheet", [])
		return
	var gpConn: GPPIDNode = gpSource.gpGraph.gpGetNode(gpNodeId)
	if gpConn == null:
		return
	# An ALREADY-LINKED connector cannot start a second link by dragging — the context menu's
	# sync/jump actions own that state. Say so instead of minting a surprise twin at (0,0).
	# **已连接**的连接符不能靠拖拽再起一条 link —— 该状态归右键菜单的同步 / 跳转所有。
	# 明说，而不是在 (0,0) 悄悄铸一个意外的孪生体。
	if str(gpConn.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")) != "":
		_gpSetState("offpage.drag_linked", [])
		return
	var gpWorld: Vector2 = gpTarget.gpWorldFromScreen(gpTarget.get_local_mouse_position())
	var gpHit: String = gpTarget.gpHitTest(gpWorld)
	# D23: blank canvas under the pointer is a reason too — point at the ITEM to serve.
	# D23：指针下的空白画布也是一个原因 —— 请指向要**服务**的图元。
	if gpHit == "":
		_gpSetState("offpage.drop_blank", [])
		return
	var gpKind: String = GPPIDEdge.GP_PROCESS
	var gpSignalType: String = ""
	if gpConn.gpSymbolId == GPSymbolPackOffpage.GP_ID_SIGNAL:
		gpKind = GPPIDEdge.GP_SIGNAL
		gpSignalType = "ELECTRIC"
	# The drop node is what the twin serves; its port is the def's FIRST (the dialog stays
	# the place for a considered port choice — the drag is the quick gesture).
	# 落点图元即孪生体的服务对象；端口取定义的**第一个**（深思的端口选择留给对话框 ——
	# 拖拽是快速手势）。
	var gpPort: String = ""
	var gpHitNode: GPPIDNode = gpTarget.gpGraph.gpGetNode(gpHit)
	var gpHitDef: GPSymbolDef = gpTarget.gpDefFor(gpHitNode.gpSymbolId) if gpHitNode != null else null
	if gpHitDef != null and not gpHitDef.gpPorts.is_empty():
		gpPort = gpHitDef.gpPorts[0].gpName
	_gpCreateCrossLink(gpSource,
		{"node_id": gpNodeId, "port_id": GPSymbolPackOffpage.GP_PORT_NAME},
		gpKind, gpSignalType, Vector2.ZERO, gpTgtSheet.gpId,
		{"node_id": gpHit, "port_id": gpPort})


# The gesture ended without a drop (ESC): clear the highlight.
# 手势未落点即结束（ESC）：清除高亮。
func gpOnCrossPaneDragEnded() -> void:
	_gpClearDragHighlight()
	_gpRubberStop()
	if _gpDragSrcCanvas != null and _gpDragSrcNode != "":
		_gpSetDragSourceFeedback(_gpDragSrcCanvas, _gpDragSrcNode, false)


# ---- ADR-46 entry 2: cross-pane PORT link (pull from a nozzle, drop on another sheet) ----
# ---- ADR-46 入口 2：跨窗格端口连线（从管口拖出，落到另一张图）----

# A port drag is crossing panes: rubber band from the SOURCE PORT, then highlight the node —
# and expose its anchors — on whichever OTHER canvas is under the pointer.
# 端口拖拽正跨越窗格：从**源端口**画橡皮筋，然后在指针下的**另一块**画布上高亮图元 ——
# 并暴露其锚点。
func gpOnPortLinkUpdated(gpFrom: Dictionary, gpScreen: Vector2,
		gpSource: GPCanvas2D) -> void:
	_gpRubberFromPort(gpSource, gpFrom, gpScreen)
	var gpTarget: GPCanvas2D = gpCenter.gpCanvasAtScreenPoint(gpScreen)
	if gpTarget == gpSource:
		gpTarget = null
	_gpClearDragHighlight()
	if gpTarget == null:
		return
	var gpWorld: Vector2 = _gpWorldOfScreen(gpTarget, gpScreen)
	var gpHit: String = gpTarget.gpHitTest(gpWorld)
	# The user aims at a NOZZLE TIP, which sits OUTSIDE the symbol body — a body-only hit
	# test would leave the gesture blind exactly where it needs to be precise. A port within
	# the pick radius counts as hovering its node too.
	# 用户瞄准的是**管口端头**，它位于图元本体**之外** —— 只认本体的命中判定恰在最需要
	# 精确的地方失明。拾取半径内的端口同样算作悬停其所属图元。
	if gpHit == "":
		var gpNear: Dictionary = GPPortAnchor.gpHitPort(gpTarget.gpGraph,
			gpTarget.gpDefLookupCallable(), gpWorld, gpTarget.gpViewZoom, [])
		if not gpNear.is_empty():
			gpHit = str(gpNear.get("node_id", ""))
	# Same-sheet targets are refused by the creation helper anyway; refusing the HIGHLIGHT
	# too keeps what you see and what you get in agreement (same rule as W13-S8).
	# 同图纸目标本就会被创建助手拒绝；高亮同样拒绝，使「看到的」与「得到的」始终一致
	#（与 W13-S8 同一条规则）。
	if gpHit != "" and gpTarget.gpSheet != null and gpSource.gpSheet != null \
			and gpTarget.gpSheet.gpId == gpSource.gpSheet.gpId:
		return
	_gpDragHlCanvas = gpTarget
	_gpDragHlNode = gpHit
	# The hint rides ALONG with the highlight: "" (blank under the pointer) clears it.
	# 提示**随**高亮走：空串（指针下为空白）即清除。
	gpTarget.gpPortLinkHint = gpHit
	if gpHit != "":
		gpTarget.gpSetDropHighlight(gpHit)


# The port drag was released: PORT-LEVEL landing — the nearest anchor within the pick
# radius wins, no fallback to the definition's first port (the gesture means "this
# nozzle"; a silent body landing is the misleading shape round 7 removed).
# 端口拖拽松手：**端口级**落点 —— 拾取半径内最近的锚点取胜，绝不回落到定义的第一个端口
#（手势意为「就是这个管口」；悄悄接到设备本体正是第七轮修掉的误导形状）。
func gpOnPortLinkDropped(gpFrom: Dictionary, gpScreen: Vector2,
		gpSource: GPCanvas2D) -> void:
	_gpClearDragHighlight()
	_gpRubberStop()
	var gpTarget: GPCanvas2D = gpCenter.gpCanvasAtScreenPoint(gpScreen)
	# Dropped OUTSIDE every view (canvas + popup): a deliberate cancel — stay silent.
	# 落在所有视图（画布 + 弹窗）**之外**：刻意的取消 —— 保持沉默。
	if gpTarget == null:
		return
	if gpTarget == gpSource or (gpSource.gpSheet != null and gpTarget.gpSheet != null \
			and gpSource.gpSheet.gpId == gpTarget.gpSheet.gpId):
		_gpSetState("offpage.refuse_same_sheet", [])
		return
	var gpWorld: Vector2 = _gpWorldOfScreen(gpTarget, gpScreen)
	# The landing anchor: mounted nozzles participate through gpServingPorts, so "nozzle
	# preferred" falls out of plain nearest-distance — the pointer IS the user's choice.
	# 落点锚点：挂载管口经 gpServingPorts 参与，「管口优先」由**普通最近距离**自然达成 ——
	# 指针本身就是用户的选择。
	var gpA: Dictionary = GPPortAnchor.gpHitPort(gpTarget.gpGraph,
		gpTarget.gpDefLookupCallable(), gpWorld, gpTarget.gpViewZoom, [])
	if gpA.is_empty():
		_gpSetState("offpage.drop_no_port", [])
		return
	# Type pairing follows the IN-CANVAS drag rule: a pipe port and a signal port refuse
	# out loud instead of minting a DRC-flagged link.
	# 类型配对沿用**画布内**拖拽规则：管口与信号口大声拒绝，而不是铸出一条等着 DRC 报错的连接。
	var gpKind: String = GPPortAnchor.gpConnectKindFor(str(gpFrom.get("type", "")),
		str(gpA.get("type", "")))
	if gpKind == "":
		_gpSetState("edge.port_type_mismatch", [])
		return
	var gpSignalType: String = "ELECTRIC" if gpKind == GPPIDEdge.GP_SIGNAL else ""
	_gpCreateCrossLink(gpSource,
		{"node_id": str(gpFrom.get("node_id", "")),
			"port_id": str(gpFrom.get("port_id", ""))},
		gpKind, gpSignalType,
		gpFrom.get("pos", Vector2.ZERO) as Vector2,
		gpTarget.gpSheet.gpId,
		{"node_id": str(gpA.get("node_id", "")), "port_id": str(gpA.get("port_id", ""))})


# The port link gesture ended without a drop (ESC): clear the highlights.
# 端口连线手势未落点即结束（ESC）：清除高亮。
func gpOnPortLinkEnded() -> void:
	_gpClearDragHighlight()
	_gpRubberStop()


# A4 roundtrip: the SCREEN point a canvas reported → that canvas's WORLD point. The exact
# inverse of GPCanvas2D.gpScreenMouse() (its own viewport transform + its global transform,
# both inverted) — the drop is resolved where the gesture HAPPENED, not where the mouse is
# now, and the whole path stays deterministic for probes.
# A4 往返：画布上报的**屏幕**点 → 该画布的**世界**点。与 GPCanvas2D.gpScreenMouse() 精确互逆
#（各自的 viewport 变换与全局变换，双双取逆）—— 落点解析在手势**发生**之处，而非鼠标此刻
# 所在之处，且整条路径对探针完全确定。
func _gpWorldOfScreen(gpCanvas: GPCanvas2D, gpScreen: Vector2) -> Vector2:
	var gpGlobal: Vector2 = gpCanvas.get_viewport().get_screen_transform().affine_inverse() \
		* gpScreen
	return gpCanvas.gpWorldFromScreen(gpCanvas.get_global_transform().affine_inverse() * gpGlobal)


# D23's rubber band, from a PORT world position instead of a connector node (the two entry
# paths share one visual language).
# D23 橡皮筋，从**端口**世界坐标出发而非连接符节点（两条入口共用一套视觉语言）。
func _gpRubberFromPort(gpSource: GPCanvas2D, gpFrom: Dictionary, gpScreen: Vector2) -> void:
	if gpSource == null:
		return
	var gpPos: Vector2 = gpFrom.get("pos", Vector2.ZERO)
	_gpRubberFrom = gpSource.get_global_transform() * gpSource.gpScreenFromWorld(gpPos)
	# A4: the drag point arrives in SCREEN space; the overlay paints in the MAIN window's
	# global space — convert through the main window's screen transform.
	# A4：拖拽点以**屏幕**空间到达；覆盖层在**主窗**全局空间绘制 —— 经主窗 screen transform 换算。
	_gpRubberTo = get_viewport().get_screen_transform().affine_inverse() * gpScreen
	_gpRubberActive = true
	_gpEnsureRubber().queue_redraw()


# Clear the drop highlight (idempotent).
# 清除落点高亮（幂等）。
func _gpClearDragHighlight() -> void:
	if _gpDragHlCanvas != null and is_instance_valid(_gpDragHlCanvas):
		_gpDragHlCanvas.gpSetDropHighlight("")
		# ADR-46 entry 2: the anchor hint (exposed ports on the target canvas) dies with
		# the highlight — the two are one and the same visual contract.
		# ADR-46 入口 2：锚点提示（目标画布暴露的端口）随高亮一同清除 —— 二者是同一个视觉契约。
		_gpDragHlCanvas.gpPortLinkHint = ""
	_gpDragHlCanvas = null
	_gpDragHlNode = ""


# D23: dim ("connecting…") or restore the dragged SOURCE connector's view. Idempotent; the
# remembered source refs are set here so ANY ending path can restore them.
# D23：把被拖拽**源**连接符的视图调暗（「连线中」）或恢复。幂等；源引用在此记忆，
# 使任何结束路径都能恢复。
func _gpSetDragSourceFeedback(gpCanvas: GPCanvas2D, gpNodeId: String, gpOn: bool) -> void:
	if gpCanvas == null or gpCanvas.gpBinder == null or gpNodeId == "":
		return
	if gpOn:
		_gpDragSrcCanvas = gpCanvas
		_gpDragSrcNode = gpNodeId
	var gpView: GPSymbolView = gpCanvas.gpBinder.gpGetSymbolView(gpNodeId)
	if gpView != null and is_instance_valid(gpView):
		gpView.modulate = Color(1.0, 1.0, 1.0, 0.55) if gpOn else Color.WHITE
	if not gpOn:
		_gpDragSrcCanvas = null
		_gpDragSrcNode = ""


# D23: lazily create the rubber-band overlay (full-rect, mouse-transparent, topmost).
# D23：惰性创建橡皮筋覆盖层（满矩形、鼠标透明、最顶层）。
func _gpEnsureRubber() -> Control:
	if _gpRubber != null and is_instance_valid(_gpRubber):
		return _gpRubber
	var gpOv: Control = Control.new()
	gpOv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gpOv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpOv.draw.connect(_gpOnRubberDraw)
	add_child(gpOv)
	gpOv.move_to_front()
	_gpRubber = gpOv
	return gpOv


# The rubber band paint: accent line source→pointer plus a pointer dot, in GLOBAL space
# mapped into the overlay's local frame (the overlay spans the whole shell).
# 橡皮筋绘制：源→指针的 accent 线加指针圆点，**全局**空间映射进覆盖层的本地坐标系
#（覆盖层横跨整个外壳）。
func _gpOnRubberDraw() -> void:
	if not _gpRubberActive or _gpRubber == null:
		return
	var gpInv: Transform2D = _gpRubber.get_global_transform().affine_inverse()
	var gpA: Vector2 = gpInv * _gpRubberFrom
	var gpB: Vector2 = gpInv * _gpRubberTo
	_gpRubber.draw_line(gpA, gpB, Color(1.0, 0.62, 0.20, 0.85), 2.0)
	_gpRubber.draw_circle(gpB, 4.0, Color(1.0, 0.62, 0.20, 0.9))


# D23: refresh the rubber band from the source flag's global position to the pointer.
# D23：把橡皮筋从源旗标的**全局**位置刷新到指针。
func _gpRubberUpdate(gpSource: GPCanvas2D, gpNodeId: String, gpScreen: Vector2) -> void:
	if gpSource == null or gpSource.gpGraph == null:
		return
	var gpConn: GPPIDNode = gpSource.gpGraph.gpGetNode(gpNodeId)
	if gpConn == null:
		return
	_gpRubberFrom = gpSource.get_global_transform() * gpSource.gpScreenFromWorld(gpConn.gpPosition)
	# A4: the drag point arrives in SCREEN space; the overlay paints in the MAIN window's
	# global space — convert through the main window's screen transform.
	# A4：拖拽点以**屏幕**空间到达；覆盖层在**主窗**全局空间绘制 —— 经主窗 screen transform 换算。
	_gpRubberTo = get_viewport().get_screen_transform().affine_inverse() * gpScreen
	_gpRubberActive = true
	_gpEnsureRubber().queue_redraw()


# D23: stop the rubber band. / D23：停止橡皮筋。
func _gpRubberStop() -> void:
	if not _gpRubberActive:
		return
	_gpRubberActive = false
	if _gpRubber != null and is_instance_valid(_gpRubber):
		_gpRubber.queue_redraw()


# Navigation: switch to the peer sheet and select the peer connector.
# 导航：切到对端图纸并选中对端连接符。
func gpOnJumpToPeer(gpNodeId: String) -> void:
	if not gpCenter.gpJumpToPeerConnector(gpNodeId):
		_gpSetState("offpage.jump_missing", [])


# "Sync to peer": make the PEER end match THIS end, through the link's contract snapshot,
# as one undoable step. Reading the values from the local edge keeps one rule: the local
# sheet is where the edit happened.
# 「同步到对端」：经 link 的契约快照让**对端**与本端一致，一步可撤销。值取自本端边
# 保持了单一规则：编辑发生在本端图纸。
func gpOnSyncToPeer(gpNodeId: String) -> void:
	var gpCanvas: GPCanvas2D = gpCenter.gpActiveCanvas()
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpLink: GPOffPageLink = GPOffPageIndex.gpLinkForNode(gpNodeId)
	if gpLink == null:
		return
	var gpLocalEdge: GPPIDEdge = _gpEdgeTouching(gpCanvas.gpGraph, gpNodeId)
	var gpPeer: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpNodeId)
	var gpPeerGraph: GPPIDGraph = null
	for gpS in gpCenter.gpToSheets():
		if gpS.gpId == str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")):
			gpPeerGraph = gpS.gpGraph
	var gpPeerEdge: GPPIDEdge = _gpEdgeTouching(gpPeerGraph,
		str(gpPeer.get(GPOffPageLink.GP_KEY_NODE, "")))
	var gpEdges: Array[GPPIDEdge] = [gpLocalEdge, gpPeerEdge]
	var gpValues: Dictionary = {}
	if gpLocalEdge != null:
		for gpKey in GPCrossSheetSyncCommand.GP_CONTRACT_KEYS:
			if (gpLocalEdge.gpAttrs as Dictionary).has(gpKey):
				gpValues[gpKey] = gpLocalEdge.gpAttrs[gpKey]
	if gpCanvas.gpActions.gpCrossSheetSync(gpLink, gpValues, gpEdges, gpPeerGraph):
		# A2: the store signal already refreshed/dirtied both canvases.
		# A2：store 信号已刷新并标脏两端画布。
		_gpSetState("offpage.sync_done", [])


# Every B-side continuation edge fed by the edge with this id on this canvas: one entry per
# link whose A-end connector the edge feeds — {"link", "canvas", "edge"}. Shared by the tag
# and the attribute propagation handlers, so both walk the SAME list (one definition of
# "what follows this line").
# 本画布上由该 id 的边馈送的每条 B 端延续边：接入本边（A 端连接符）的 link 各一条 ——
# {"link", "canvas", "edge"}。编号与属性两个传播处理器共用，走**同一**份清单
# （「什么跟随这条线」只有一个定义）。
func _gpBsideContinuations(gpCanvas: GPCanvas2D, gpEdgeId: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return gpOut
	var gpLocalSheetId: String = gpCanvas.gpSheet.gpId if gpCanvas.gpSheet != null else ""
	if gpLocalSheetId == "":
		return gpOut
	for gpLink in gpCenter.gpOffPageLinks:
		if gpLink == null:
			continue
		var gpA: Dictionary = gpLink.gpA
		if str(gpA.get(GPOffPageLink.GP_KEY_SHEET, "")) != gpLocalSheetId:
			continue
		var gpANodeId: String = str(gpA.get(GPOffPageLink.GP_KEY_NODE, ""))
		# The edited edge must be the line that feeds THIS link's A-end connector.
		# 被改的边必须是接入本 link A 端连接符的那条线。
		if not _gpEdgeTouchesNode(gpCanvas.gpGraph, gpEdgeId, gpANodeId):
			continue
		var gpPeer: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpANodeId)
		var gpPeerCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(
			str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")))
		if gpPeerCanvas == null or gpPeerCanvas.gpGraph == null:
			continue
		var gpPeerEdge: GPPIDEdge = _gpEdgeTouching(gpPeerCanvas.gpGraph,
			str(gpPeer.get(GPOffPageLink.GP_KEY_NODE, "")))
		if gpPeerEdge == null:
			continue
		gpOut.append({"link": gpLink, "canvas": gpPeerCanvas, "edge": gpPeerEdge})
	return gpOut


# ROUND 3 PULL (user feedback 2026-11-04): when a B-side continuation edge FIRST exists —
# drawn after the link was made, or already standing when the link was created (the inspector
# reconnect flow) — its local state is still the freshly minted defaults while follow mode is
# already ON (tag_manual absent). The locked panel displays the SOURCE values, so only the
# canvas exposes the drift. One pull, through the edge's OWN sheet service (its undo stack,
# its dirty flag, B3): the inheritable attribute block blind-written as ONE step, then the
# source number through the dedicated tag path (propagated, so the follow chain stays alive).
# Both writes are idempotent — equality guards make a repeated pull a no-op, which is what
# keeps the created-signal → pull → tag-commit → pull chain terminating.
# 第三轮拉取（用户反馈 2026-11-04）：B 端延续边**首次**存在时 —— link 建好后才画的线，或
# link 建立（属性面板重连流）时就已立在那里的线 —— 本地状态还是刚铸的默认值，而跟随模式
# 已经开启（无 tag_manual）。锁定面板显示**源端**值，只有画布暴露漂移。拉取一次，走这条边
# **自己**图纸的服务（它的撤销栈、它的脏标记，B3）：可继承属性块一步盲写，随后源端编号走
# 专用编号通道（带传播标记，跟随链保持存活）。两次写入皆幂等 —— 相等守卫使重复拉取成为
# 空转，这正是「画成信号 → 拉取 → 编号落账 → 再拉取」链条能够收敛的原因。
func _gpPullFollowState(gpCanvas: GPCanvas2D, gpEdgeId: String) -> void:
	if gpCanvas == null or gpCanvas.gpGraph == null or gpCanvas.gpActions == null:
		return
	var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
	if gpEdge == null or gpEdge.gpKind == GPPIDEdge.GP_SIGNAL:
		return
	# Opted out: the block is deliberate, never touched again.
	# 已选择退出：整个属性块是刻意选择，此后绝不再碰。
	if bool(gpEdge.gpAttrs.get("tag_manual", false)):
		return
	var gpSrc: Dictionary = _gpSourceOfBSideEdge(gpCanvas, gpEdgeId)
	var gpVals: Dictionary = gpSrc.get("values", {}) as Dictionary
	var gpSrcTag: String = str(gpSrc.get("tag", ""))
	if not gpVals.is_empty():
		gpCanvas.gpActions.gpSetEdgeAttrs(gpEdgeId, gpVals)
	if gpSrcTag != "" and gpEdge.gpTag != gpSrcTag:
		if gpCanvas.gpActions.gpSetEdgeTag(gpEdgeId, gpSrcTag, true):
			_gpSetState("offpage.inherit_done", [gpSrcTag])
		else:
			_gpSetState("offpage.inherit_fail",
				[I18n.gpTr(gpCanvas.gpActions.gpLastRefusal)])


# An edge was DRAWN on some sheet (gpEdgeCreated): if it feeds a B-end twin, pull now.
# 某张图纸画成了一条边（gpEdgeCreated）：若它馈送某个 B 端孪生体，此刻即拉取。
func gpOnEdgeCreated(gpEdgeId: String, gpCanvas: GPCanvas2D) -> void:
	_gpPullFollowState(gpCanvas, gpEdgeId)


# A line number was committed on SOME sheet: propagate it to every cross-sheet continuation
# edge that follows this sheet (the A side), unless the peer edge opted out
# (attrs["tag_manual"], user feedback 2026-11-04). Refusals (rule / on-sheet duplicate) are
# reported without blocking the source edit — the source sheet stays authoritative.
# 某张图纸的管线号落账：把它传播到跟随本图纸（A 端）的每一条跨图纸延续边，除非对端边
# 已选择退出（attrs["tag_manual"]，用户反馈 2026-11-04）。拒绝（规则 / 同图重号）只报告、
# 不阻塞源端编辑 —— 源图纸始终是权威侧。
func gpOnEdgeTagCommitted(gpEdgeId: String, _gpOldTag: String, gpNewTag: String,
		gpCanvas: GPCanvas2D) -> void:
	if gpNewTag == "" or gpCanvas == null or gpCanvas.gpGraph == null:
		return
	for gpCont in _gpBsideContinuations(gpCanvas, gpEdgeId):
		var gpPeerEdge: GPPIDEdge = gpCont["edge"] as GPPIDEdge
		var gpPeerCanvas: GPCanvas2D = gpCont["canvas"] as GPCanvas2D
		# Opted out (the checkbox): the number is deliberate, never touched again.
		# 已选择退出（勾选框）：编号是刻意选择，此后绝不再碰。
		if bool(gpPeerEdge.gpAttrs.get("tag_manual", false)):
			continue
		if gpPeerEdge.gpTag == gpNewTag:
			continue
		# The retag goes through the PEER sheet's own edit service: its undo stack, its
		# dirty flag, its notify (B3). gpPropagated keeps the follow alive.
		# 改号走**对端**图纸自己的编辑服务：它的撤销栈、它的脏标记、它的通知（B3）。
		# gpPropagated 使跟随关系保持存活。
		if gpPeerCanvas.gpActions.gpSetEdgeTag(gpPeerEdge.gpInstanceId, gpNewTag, true):
			_gpSetState("offpage.inherit_done", [gpNewTag])
		else:
			_gpSetState("offpage.inherit_fail",
				[I18n.gpTr(gpPeerCanvas.gpActions.gpLastRefusal)])


# Line ATTRIBUTES were committed on SOME sheet (user feedback 2026-11-04, round 2): forward
# the INHERITABLE ones to every followed continuation edge this edge feeds, then keep the
# peer's number in step — an attribute edit re-renders the SOURCE number, and the peer's
# number is the inherited one, so a drift is pulled back here. Peer writes go through the
# PEER sheet's own service (its undo stack, its dirty flag, B3): ONE batch blind-write that
# never re-renders the number, and the batch command never re-emits — no recursion.
# 某张图纸的管线**属性**落账（用户反馈 2026-11-04 第二轮）：把**可继承**的那些转发给本边
# 馈送的每条跟随中的延续边，并让对端号保持同步 —— 属性编辑会重渲染**源端**号，而对端号是
# 继承值，故在此拉平漂移。对端写入走**对端**图纸自己的服务（它的撤销栈、脏标记，B3）：
# 一次批量盲写、绝不重渲染号；批量命令绝不再发射 —— 无递归。
func gpOnEdgeAttrsCommitted(gpEdgeId: String, gpKeys: Array[String],
		gpCanvas: GPCanvas2D) -> void:
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpSrcEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
	if gpSrcEdge == null:
		return
	var gpInheritable: Dictionary = {}
	for gpKey in GPInspector.gpEdgeInheritKeys(gpSrcEdge, gpCanvas.gpGraph.gpStandard):
		gpInheritable[gpKey] = true
	var gpValues: Dictionary = {}
	for gpKey in gpKeys:
		if not gpInheritable.has(gpKey):
			continue
		if gpSrcEdge.gpAttrs.has(gpKey):
			gpValues[gpKey] = gpSrcEdge.gpAttrs[gpKey]
		else:
			# The source CLEARED the key (blank = clear): erase it on the peer too.
			# 源端**清除**了该键（空白 = 清除）：对端同步清除。
			gpValues[gpKey] = null
	for gpCont in _gpBsideContinuations(gpCanvas, gpEdgeId):
		var gpPeerEdge: GPPIDEdge = gpCont["edge"] as GPPIDEdge
		var gpPeerCanvas: GPCanvas2D = gpCont["canvas"] as GPCanvas2D
		# Opted out: the whole block is deliberate, never touched again.
		# 已选择退出：整个属性块是刻意选择，此后绝不再碰。
		if bool(gpPeerEdge.gpAttrs.get("tag_manual", false)):
			continue
		var gpPeerId: String = gpPeerEdge.gpInstanceId
		if not gpValues.is_empty():
			if gpPeerCanvas.gpActions.gpSetEdgeAttrs(gpPeerId, gpValues):
				_gpSetState("offpage.attr_inherit_done", [", ".join(gpValues.keys())])
		# The source's number may have been re-rendered by this attribute edit: pull the
		# peer number back in step (the dedicated tag path, propagated).
		# 本次属性编辑可能已重渲染源端号：把对端号拉回同步（走专用编号通道，带传播标记）。
		if gpSrcEdge.gpTag != "" and gpPeerEdge.gpTag != gpSrcEdge.gpTag:
			if not gpPeerCanvas.gpActions.gpSetEdgeTag(gpPeerId, gpSrcEdge.gpTag, true):
				_gpSetState("offpage.inherit_fail",
					[I18n.gpTr(gpPeerCanvas.gpActions.gpLastRefusal)])
		# Live refresh: when the peer edge currently on show IS this one, rebuild its form.
		# 实时刷新：若当前显示的对端边**正是**这条，重建其表单。
		if gpInspector.gpCurrentEdge != null \
				and gpInspector.gpCurrentEdge.gpInstanceId == gpPeerId:
			gpInspector.gpShowEdge(gpPeerEdge)


# Visibility + follow state of the inherit checkbox for ONE edge: shown only on a B-side
# continuation (the edge touching a link's B-end connector); the A side IS the authority and
# has nothing to inherit. In follow mode it also carries the source's CURRENT number and
# attribute block, so the locked form displays the source rather than a possibly stale local
# copy (user feedback 2026-11-04, round 2). Pure glue over the container link table.
# 单条边的继承勾选框可见性与跟随状态：仅在 B 端延续段（触及 link B 端连接符的边）显示；
# A 端本身就是权威侧，无继承可言。跟随模式下还携带源端**当前**的编号与属性块，使锁定表单
# 显示源端而非可能过期的本地副本（用户反馈 2026-11-04 第二轮）。容器 link 表之上的纯粘合。
func gpEdgeInheritInfo(gpEdgeId: String) -> Dictionary:
	var gpOut: Dictionary = {"show": false, "follow": false, "src_tag": "", "src_attrs": {}}
	for gpT in gpCenter.gpTabs:
		var gpCanvas: GPCanvas2D = gpT.get("canvas") as GPCanvas2D
		if gpCanvas == null or gpCanvas.gpGraph == null:
			continue
		var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
		if gpEdge == null:
			continue
		for gpLink in gpCenter.gpOffPageLinks:
			if gpLink == null:
				continue
			var gpBNode: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
			if gpBNode != "" and _gpEdgeTouchesNode(gpCanvas.gpGraph, gpEdgeId, gpBNode):
				gpOut["show"] = true
				gpOut["follow"] = not bool(gpEdge.gpAttrs.get("tag_manual", false))
				var gpPeer: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpBNode)
				var gpSrcCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(
					str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")))
				if gpSrcCanvas != null and gpSrcCanvas.gpGraph != null:
					var gpSrcEdge: GPPIDEdge = _gpEdgeTouching(gpSrcCanvas.gpGraph,
						str(gpPeer.get(GPOffPageLink.GP_KEY_NODE, "")))
					if gpSrcEdge != null:
						gpOut["src_tag"] = gpSrcEdge.gpTag
						gpOut["src_attrs"] = gpSrcEdge.gpAttrs.duplicate(true)
				return gpOut
	return gpOut


# The source edge's CURRENT number + inheritable attribute block for a B-side edge, resolved
# through its link: {"tag", "values"} (values empty when no source is resolvable). Used by
# the inherit checkbox: snapshot on opt-out, full pull on re-follow.
# 经 link 解析 B 端边源端的**当前**编号＋可继承属性块：{"tag", "values"}（解析不出源端时
# values 为空）。供继承勾选框使用：退出时快照，恢复跟随时全量拉取。
func _gpSourceOfBSideEdge(gpCanvas: GPCanvas2D, gpEdgeId: String) -> Dictionary:
	var gpOut: Dictionary = {"tag": "", "values": {}}
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return gpOut
	var gpLink: GPOffPageLink = _gpLinkForBSideEdge(gpCanvas.gpGraph, gpEdgeId)
	if gpLink == null:
		return gpOut
	var gpBNode: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
	var gpPeer: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpBNode)
	var gpSrcCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(
		str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")))
	if gpSrcCanvas == null or gpSrcCanvas.gpGraph == null:
		return gpOut
	var gpSrcEdge: GPPIDEdge = _gpEdgeTouching(gpSrcCanvas.gpGraph,
		str(gpPeer.get(GPOffPageLink.GP_KEY_NODE, "")))
	if gpSrcEdge == null:
		return gpOut
	gpOut["tag"] = gpSrcEdge.gpTag
	for gpKey in GPInspector.gpEdgeInheritKeys(gpSrcEdge,
			gpSrcCanvas.gpGraph.gpStandard):
		if gpSrcEdge.gpAttrs.has(gpKey):
			gpOut["values"][gpKey] = gpSrcEdge.gpAttrs[gpKey]
	return gpOut


# The checkbox toggled on a B-side continuation edge (user feedback 2026-11-04, round 2).
# Off: the number AND the attribute block become manual — the source's CURRENT values are
# snapshotted first (one undo step), so the segment keeps showing what the source showed and
# is now independently editable. On: the flag is cleared and the CURRENT source number AND
# the whole attribute block are pulled immediately, so "re-follow" never leaves a stale
# value anywhere.
# B 端延续边上的勾选框开关（用户反馈 2026-11-04 第二轮）。取消：编号**与属性块**都转为手选
# —— 先快照源端**当前**值（一个撤销步），本段继续显示源端所显示的内容、从此可独立编辑。
# 勾选：清除标记并**立即**拉取源端当前编号**与整个属性块** —— 「恢复跟随」绝不在任何地方
# 留下过期值。
func gpOnEdgeInheritToggled(gpEdgeId: String, gpFollow: bool) -> void:
	var gpCanvas: GPCanvas2D = _gpCanvasOfEdgeId(gpEdgeId)
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
	if gpEdge == null:
		return
	var gpSrc: Dictionary = _gpSourceOfBSideEdge(gpCanvas, gpEdgeId)
	var gpVals: Dictionary = gpSrc.get("values", {}) as Dictionary
	if not gpFollow:
		gpCanvas.gpActions.gpSetEdgeAttr(gpEdgeId, "tag_manual", true)
		if not gpVals.is_empty():
			gpCanvas.gpActions.gpSetEdgeAttrs(gpEdgeId, gpVals)
		_gpSetState("offpage.inherit_off", [])
		return
	# Resume following: clear the flag (null = erase, per GPSetEdgeAttrCommand), then pull.
	# 恢复跟随：清除标记（null = 删除，见 GPSetEdgeAttrCommand），然后拉取。
	gpCanvas.gpActions.gpSetEdgeAttr(gpEdgeId, "tag_manual", null)
	if not gpVals.is_empty():
		gpCanvas.gpActions.gpSetEdgeAttrs(gpEdgeId, gpVals)
	var gpSrcTag: String = str(gpSrc.get("tag", ""))
	if gpSrcTag == "" or gpEdge.gpTag == gpSrcTag:
		_gpSetState("offpage.inherit_on", [gpSrcTag])
		return
	if gpCanvas.gpActions.gpSetEdgeTag(gpEdgeId, gpSrcTag, true):
		_gpSetState("offpage.inherit_done", [gpSrcTag])
	else:
		_gpSetState("offpage.inherit_fail", [I18n.gpTr(gpCanvas.gpActions.gpLastRefusal)])


# The link whose B-end connector the edge feeds, or null.
# 该边接入其 B 端连接符的 link，否则 null。
func _gpLinkForBSideEdge(gpG: GPPIDGraph, gpEdgeId: String) -> GPOffPageLink:
	if gpG == null:
		return null
	for gpLink in gpCenter.gpOffPageLinks:
		if gpLink == null:
			continue
		var gpBNode: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
		if gpBNode != "" and _gpEdgeTouchesNode(gpG, gpEdgeId, gpBNode):
			return gpLink
	return null


# The canvas whose graph holds this edge (tab scan; the sheet count is small).
# 图中持有这条边的画布（扫描标签页；图纸数量很小）。
func _gpCanvasOfEdgeId(gpEdgeId: String) -> GPCanvas2D:
	for gpT in gpCenter.gpTabs:
		var gpCanvas: GPCanvas2D = gpT.get("canvas") as GPCanvas2D
		if gpCanvas == null or gpCanvas.gpGraph == null:
			continue
		if gpCanvas.gpGraph.gpGetEdge(gpEdgeId) != null:
			return gpCanvas
	return null


# Whether the edge with this id touches the node with this id.
# 该 id 的边是否触及该 id 的节点。
static func _gpEdgeTouchesNode(gpG: GPPIDGraph, gpEdgeId: String, gpNodeId: String) -> bool:
	if gpG == null or gpNodeId == "":
		return false
	var gpE: GPPIDEdge = gpG.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	return str(gpE.gpFromRef.get("node_id", "")) == gpNodeId \
		or str(gpE.gpToRef.get("node_id", "")) == gpNodeId


# Deletion case ① (ADR-43 §2.5): connectors are in the delete selection. Resolve each one's
# link + peer, show ONE confirmation naming the peer sheets, then cascade the whole
# connection in one command per link. Connectors WITHOUT a resolvable link fall back to the
# plain delete — a dangling flag is a local object, nothing to cascade.
# 删除情形①（ADR-43 §2.5）：删除选择集中出现了连接符。解析每个的 link 与对端，
# 弹**一个**确认框列出对端图纸，确认后每条 link 一个命令级联删除。解析不出 link 的
# 连接符回退普通删除 —— 悬空旗标是本地对象，无级联可言。
func gpOnCrossSheetDelete(gpConnectorIds: Array[String], gpCanvas: GPCanvas2D) -> void:
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpPlans: Array[Dictionary] = []
	var gpDangling: Array[String] = []
	for gpNid in gpConnectorIds:
		var gpN: GPPIDNode = gpCanvas.gpGraph.gpGetNode(gpNid)
		if gpN == null:
			continue
		var gpLink: GPOffPageLink = null
		for gpL in gpCenter.gpOffPageLinks:
			if gpL != null and gpL.gpInstanceId == str(gpN.gpProps.get(
					GPOffPageLink.GP_KEY_LINK_ID, "")):
				gpLink = gpL
				break
		if gpLink == null:
			gpDangling.append(gpNid)
			continue
		gpPlans.append({"link": gpLink, "local": gpNid})
	if gpDangling.size() > 0:
		gpCanvas.gpActions.gpDeleteSelection(gpDangling, [], [],
			gpCanvas.gpDefLookupCallable())
	if gpPlans.is_empty():
		return
	# One line per link: tag + peer sheet label (number, else tab name).
	# 每 link 一行：编号 + 对端图纸标签（图号，否则标签名）。
	var gpLines: String = ""
	for gpPlan in gpPlans:
		var gpLink: GPOffPageLink = gpPlan["link"] as GPOffPageLink
		gpLines += I18n.gpTr("offpage.del_line") % [_gpLinkTag(gpLink),
			_gpPeerSheetLabel(gpLink, gpCanvas.gpSheet.gpId if gpCanvas.gpSheet != null else "")] + "\n"
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("offpage.del_title")
	gpDlg.dialog_text = I18n.gpTr("offpage.del_text") % [gpLines.strip_edges()]
	gpDlg.ok_button_text = I18n.gpTr("dialog.ok")
	gpDlg.cancel_button_text = I18n.gpTr("dialog.cancel")
	add_child(gpDlg)
	gpDlg.confirmed.connect(_gpOnCrossSheetDeleteConfirmed.bind(gpPlans, gpCanvas))
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.popup_centered()


# The confirmed half: run one cascade command per link, then refresh the snapshot.
# 确认后的半步：每条 link 一个级联命令，然后刷新快照。
func _gpOnCrossSheetDeleteConfirmed(gpPlans: Array[Dictionary], gpCanvas: GPCanvas2D) -> void:
	var gpLookup: Callable = gpCanvas.gpDefLookupCallable()
	for gpPlan in gpPlans:
		var gpLink: GPOffPageLink = gpPlan["link"] as GPOffPageLink
		var gpLocalId: String = str(gpPlan["local"])
		var gpPeerRef: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpLocalId)
		var gpPeerId: String = str(gpPeerRef.get(GPOffPageLink.GP_KEY_NODE, ""))
		var gpPeerGraph: GPPIDGraph = null
		for gpS in gpCenter.gpToSheets():
			if gpS.gpId == str(gpPeerRef.get(GPOffPageLink.GP_KEY_SHEET, "")):
				gpPeerGraph = gpS.gpGraph
		if gpPeerGraph == null or gpPeerId == "":
			continue
		gpCanvas.gpActions.gpCrossSheetDelete(gpLink, [gpLocalId], [gpPeerId],
			gpPeerGraph, gpCenter.gpOffPageLinks, gpLookup)
	# A2: deletions were announced through the link store; nothing to refresh by hand.
	# A2：删除已通过 link store 通告；无需手工刷新。
	gpCanvas.gpEditFacade.gpSetSelection([])
	_gpSetState("offpage.del_done", [])


# The tag for display: the manual tag when set, else the instance id.
# 显示用编号：有手改编号用编号，否则用实例 id。
static func _gpLinkTag(gpLink: GPOffPageLink) -> String:
	return gpLink.gpTag if gpLink.gpTag != "" else gpLink.gpInstanceId


# U3: UNLINK from the inspector action row — the link leaves the container table, both
# connector flags stay on their sheets as honest unlinked placeholders, one undo step.
# U3：属性面板动作行的「断开」—— link 离开容器表，两面连接符旗标留在各自图纸上成为
# 诚实的未连接占位，一个撤销步。
func gpOnInspectorUnlink(gpLinkId: String) -> void:
	var gpLink: GPOffPageLink = _gpLinkById(gpLinkId)
	if gpLink == null:
		return
	var gpLocalCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(
		str(gpLink.gpA.get(GPOffPageLink.GP_KEY_SHEET, "")))
	var gpPeerCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(
		str(gpLink.gpB.get(GPOffPageLink.GP_KEY_SHEET, "")))
	if gpLocalCanvas == null or gpLocalCanvas.gpActions == null \
			or gpPeerCanvas == null or gpPeerCanvas.gpGraph == null:
		return
	if gpLocalCanvas.gpActions.gpUnlinkOffPage(gpLink, gpCenter.gpOffPageLinks,
			gpLocalCanvas.gpGraph, gpPeerCanvas.gpGraph):
		# A2: the store signal already refreshed/dirtied the canvases.
		# A2：store 信号已刷新并标脏画布。
		_gpSetState("offpage.unlink_done", [])
	else:
		_gpSetState("offpage.unlink_fail", [])


# U3: DELETE the whole pair from the inspector action row — same confirmed cascade as the
# canvas context menu, pre-planned for THIS link only (the user aimed at one link).
# U3：属性面板动作行的「删除」—— 与画布右键菜单相同的**确认后**级联，但只预计划本条
# link（用户瞄准的就是这一条）。
func gpOnInspectorLinkDelete(gpLinkId: String) -> void:
	var gpLink: GPOffPageLink = _gpLinkById(gpLinkId)
	if gpLink == null:
		return
	var gpLocalSheetId: String = str(gpLink.gpA.get(GPOffPageLink.GP_KEY_SHEET, ""))
	var gpCanvas: GPCanvas2D = gpCenter.gpCanvasForSheetId(gpLocalSheetId)
	if gpCanvas == null:
		return
	var gpPlans: Array[Dictionary] = [{"link": gpLink,
		"local": str(gpLink.gpA.get(GPOffPageLink.GP_KEY_NODE, ""))}]
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("offpage.del_title")
	gpDlg.dialog_text = I18n.gpTr("offpage.del_text") % [I18n.gpTr("offpage.del_line")
		% [_gpLinkTag(gpLink), _gpPeerSheetLabel(gpLink, gpLocalSheetId)]]
	gpDlg.ok_button_text = I18n.gpTr("dialog.ok")
	gpDlg.cancel_button_text = I18n.gpTr("dialog.cancel")
	add_child(gpDlg)
	gpDlg.confirmed.connect(_gpOnCrossSheetDeleteConfirmed.bind(gpPlans, gpCanvas))
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.popup_centered()


# The link with this instance id in the container table, or null.
# 容器表中该实例 id 的 link，否则 null。
func _gpLinkById(gpLinkId: String) -> GPOffPageLink:
	for gpL in gpCenter.gpOffPageLinks:
		if gpL != null and gpL.gpInstanceId == gpLinkId:
			return gpL
	return null


# Peer sheet label for confirm dialogs: the end that is NOT the local sheet (D08: the old
# first-hit loop always returned the LOCAL sheet — gpA is the local end by construction —
# the exact reverse of what the user must confirm).
# 确认框的对端图纸标签：取**非本端图纸**的那一端（D08：旧的「首个命中」循环恒返回本端
# —— gpA 按构造就是本端 —— 与用户要确认的信息正好相反）。
func _gpPeerSheetLabel(gpLink: GPOffPageLink, gpLocalSheetId: String) -> String:
	for gpEnd in [gpLink.gpB, gpLink.gpA]:
		var gpSheetId: String = str((gpEnd as Dictionary).get(GPOffPageLink.GP_KEY_SHEET, ""))
		if gpSheetId == gpLocalSheetId:
			continue
		for gpS in gpCenter.gpToSheets():
			if gpS.gpId == gpSheetId:
				return gpS.gpNumber if gpS.gpNumber != "" else gpS.gpName
	return GPOffPageIndex.GP_UNRESOLVED_TEXT


# The first edge that touches a node, or null. Good enough for a contract sync: a connector
# has at most one line INTO it on each sheet.
# 触及某节点的第一条边，否则 null。对契约同步足够：一只连接符在每张图纸上至多有一条接入线。
static func _gpEdgeTouching(gpG: GPPIDGraph, gpNodeId: String) -> GPPIDEdge:
	if gpG == null or gpNodeId == "":
		return null
	for gpE in gpG.gpEdges:
		if str(gpE.gpFromRef.get("node_id", "")) == gpNodeId \
				or str(gpE.gpToRef.get("node_id", "")) == gpNodeId:
			return gpE
	return null
