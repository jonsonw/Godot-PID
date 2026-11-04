class_name GPViewHostModel
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# A1 (W12 closure plan §4.1, R3): THE single decision entry for view-host state. A "host"
# is either a PANE or the (single) pop-out WINDOW; every binding decision — bind, swap,
# close, resize, pop out, return, activate — must go through here, so the invariants hold
# across BOTH host kinds and can never drift apart in two call sites (the D02/D04/D05
# family). GPPaneLayout is ABSORBED as the internal pane-arithmetic layer: its pure
# functions are reused, never bypassed; nothing outside this model and GPCenterArea's
# mount code may call them.
# A1（W12 收口方案 §4.1，R3）：视图宿主状态的**唯一**决策入口。「宿主」= 窗格或（唯一的）
# 摘出窗口；一切绑定决策 —— 绑定、交换、关闭、重排、摘出、归位、激活 —— 必须经过此处，
# 使不变量横跨**两种**宿主成立，且不可能在两个调用点各自分家（D02/D04/D05 家族）。
# GPPaneLayout 被**吸收**为内部的窗格算术层：其纯函数被复用而不被绕过；除本模型与
# GPCenterArea 的挂载代码外，任何地方不得直接调用它们。
#
# State shape (session-only; iron rule 74 / ADR-44 D5 — never enters the document):
#   gpBindings : Array[int]  one slot per PANE (tab index or GP_EMPTY)
#   gpPopSheet : int         the WINDOW host's sheet tab index, or GP_EMPTY
# 状态形状（仅会话内；铁律 74 / ADR-44 D5 —— 绝不进入文档）：
#   gpBindings：每窗格一槽（标签下标或 GP_EMPTY）；gpPopSheet：窗口宿主的图纸下标或 GP_EMPTY。
#
# Every function is PURE: inputs are never mutated; results come back as Dictionaries so
# callers can adopt the whole new state in one assignment.
# 所有函数皆**纯**：输入绝不被原地修改；结果以 Dictionary 返回，调用方一次赋值即可整体换状态。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Binding invariant across BOTH host kinds (ADR-44 D2, extended by A1): a sheet is shown
# in AT MOST ONE host — pane OR window. This is the one-line answer to "can two hosts
# fight over one canvas": they cannot, because every decision here checks both.
# 横跨两种宿主的绑定不变量（ADR-44 D2，A1 扩展）：一张图纸至多出现在**一个**宿主 ——
# 窗格或窗口。这就是「两个宿主能否争抢同一画布」的一行答案：不能，因为这里每个决策
# 都同时检查两者。


# gpCanBind — the pre-flight check (D6 drag & future callers). Returns "" when binding
# [param gpSheetIdx] into pane [param gpPaneIdx] is legal, else a refusal key:
#   "view.host_popped"  the sheet lives in the WINDOW (focus it instead of rebinding — D02)
#   "view.host_range"   gpPaneIdx is out of range
# gpCanBind —— 预检（D6 拖拽与未来调用方）。把 [param gpSheetIdx] 绑入窗格
# [param gpPaneIdx] 合法时返回 ""，否则返回拒绝键：sheet 已住**窗口**（应聚焦而非重绑 ——
# D02）；窗格下标越界。
static func gpCanBind(gpBindings: Array[int], gpPopSheet: int, gpPaneIdx: int,
		gpSheetIdx: int) -> String:
	if gpSheetIdx >= 0 and gpSheetIdx == gpPopSheet:
		return "view.host_popped"
	if gpPaneIdx < 0 or gpPaneIdx >= gpBindings.size():
		return "view.host_range"
	return ""


# D02 as a model case: activating the popped sheet is a WINDOW FOCUS, never a rebind.
# Returns action = "focus_window" | "focus_pane" | "bind".
#   focus_window — gpTabIdx is popped; the caller must run its single popout-focus path.
#   focus_pane   — the sheet already shows in pane [gpPane]; just make that pane active.
#   bind         — bind into pane [gpPane] (the caller's active pane); uniqueness upheld.
# D02 成为模型 case：激活已摘出图纸 = **聚焦窗口**，绝不重绑。action = focus_window（弹窗
# 聚焦）/ focus_pane（图纸已在窗格 gpPane，激活该窗格即可）/ bind（绑入窗格 gpPane，唯一性由模型保证）。
static func gpActivate(gpBindings: Array[int], gpPopSheet: int, gpActivePane: int,
		gpTabIdx: int) -> Dictionary:
	if gpTabIdx == gpPopSheet:
		return {"bindings": gpBindings, "popSheet": gpPopSheet,
			"action": "focus_window", "pane": -1}
	var gpHolder: int = gpBindings.find(gpTabIdx)
	if gpHolder >= 0:
		return {"bindings": gpBindings, "popSheet": gpPopSheet,
			"action": "focus_pane", "pane": gpHolder}
	var gpBind: Array[int] = GPPaneLayout.gpBind(gpBindings, gpActivePane, gpTabIdx)
	return {"bindings": gpBind, "popSheet": gpPopSheet,
		"action": "bind", "pane": gpActivePane}


# D05 as a model case: bind into [param gpPaneIdx], but when the sheet already shows in
# ANOTHER pane the two panes SWAP (no pane goes blank). The WINDOW host participates in
# the uniqueness check: a popped sheet is refused (caller focuses instead — same contract
# as gpCanBind). Returns swapped = true when a swap happened (both panes moved — the
# caller must re-home every pane, not just one).
# D05 成为模型 case：绑入 [param gpPaneIdx]，但该图纸已显示在**另一个**窗格时两窗格
# **交换**（无窗格留白）。窗口宿主参与唯一性检查：已摘出图纸被拒（调用方应改为聚焦 ——
# 与 gpCanBind 同一契约）。swapped = true 表示发生了交换（两个窗格都动了 —— 调用方必须
# 全部重挂载，不能只挂一个）。
static func gpBindOrSwap(gpBindings: Array[int], gpPopSheet: int, gpPaneIdx: int,
		gpSheetIdx: int) -> Dictionary:
	# The window participates in the uniqueness check (same contract as gpCanBind): a
	# pick of the POPPED sheet is a full no-op — the caller focuses the window instead.
	# 窗口参与唯一性检查（与 gpCanBind 同一契约）：对**已摘出**图纸的选取是彻底的空操作
	# —— 调用方应改为聚焦窗口。
	if gpSheetIdx >= 0 and gpSheetIdx == gpPopSheet:
		return {"bindings": gpBindings.duplicate(), "popSheet": gpPopSheet,
			"swapped": false}
	var gpOut: Array[int] = GPPaneLayout.gpSwapOrBind(gpBindings, gpPaneIdx, gpSheetIdx)
	# A swap moved TWO panes; a plain bind moved one but may have EMPTIED the previous
	# holder (impossible with swapOrBind semantics — swapOrBind only binds when the sheet
	# shows nowhere, so no pane is displaced). Either way the caller re-homes all panes.
	# 交换移动了**两个**窗格；普通绑定只动一个且不会清空别的窗格（swapOrBind 语义：仅当
	# 图纸无人显示时才普通绑定，没有任何窗格被挤走）。无论如何调用方全部重挂载。
	var gpSwapped: bool = gpSheetIdx >= 0 and gpBindings.find(gpSheetIdx) >= 0 \
		and gpBindings.find(gpSheetIdx) != gpPaneIdx
	return {"bindings": gpOut, "popSheet": gpPopSheet, "swapped": gpSwapped}


# Sheet CLOSED as a model case (absorbs GPPaneLayout.gpAfterTabRemoved + the window
# host's bookkeeping): panes showing it empty, bindings behind it shift down, and the
# WINDOW host follows the same shift — or empties when the CLOSED sheet is the popped one.
# 关闭图纸成为模型 case（吸收 gpAfterTabRemoved + 窗口宿主记账）：显示它的窗格清空、其后
# 绑定整体前移，窗口宿主同样前移 —— 被关闭的正是已摘出图纸时窗口宿主清空。
static func gpAfterSheetClosed(gpBindings: Array[int], gpPopSheet: int,
		gpRemovedIdx: int) -> Dictionary:
	var gpOut: Array[int] = GPPaneLayout.gpAfterTabRemoved(gpBindings, gpRemovedIdx)
	var gpPop: int = gpPopSheet
	if gpPop == gpRemovedIdx:
		gpPop = GPPaneLayout.GP_EMPTY
	elif gpPop > gpRemovedIdx:
		gpPop -= 1
	# Defensive (hostile input): the shared "window wins" guard keeps "one sheet, one
	# host" alive even through an already-violating state.
	# 防御（敌意输入）：共享的「窗口获胜」守卫使「一图一宿主」即使在已违规状态下也存续。
	_gpEnforceWindowUniqueness(gpOut, gpPop)
	return {"bindings": gpOut, "popSheet": gpPop}


# Pop OUT as a model case: the pane's sheet moves to the window host; the pane empties.
# Returns poppedSheet (< 0 when the pane had nothing to pop).
# 摘出成为模型 case：窗格的图纸移入窗口宿主，窗格清空。返回 poppedSheet（窗格本无内容时 < 0）。
static func gpPopOut(gpBindings: Array[int], gpPaneIdx: int) -> Dictionary:
	if gpPaneIdx < 0 or gpPaneIdx >= gpBindings.size() or gpBindings[gpPaneIdx] < 0:
		return {"bindings": gpBindings, "popSheet": GPPaneLayout.GP_EMPTY,
			"poppedSheet": GPPaneLayout.GP_EMPTY}
	var gpSheet: int = gpBindings[gpPaneIdx]
	var gpOut: Array[int] = gpBindings.duplicate()
	gpOut[gpPaneIdx] = GPPaneLayout.GP_EMPTY
	# Defensive (hostile input): no OTHER pane may keep showing the sheet that just moved
	# into the window — the window is its only host from here on.
	# 防御（敌意输入）：其它窗格不得继续显示刚移入窗口的图纸 —— 此刻起窗口是它唯一的宿主。
	for gpI in range(gpOut.size()):
		if gpI != gpPaneIdx and gpOut[gpI] == gpSheet:
			gpOut[gpI] = GPPaneLayout.GP_EMPTY
	# UNIFORM result shape: every decision function carries "popSheet" (sweeps and callers
	# may read the whole state without key checks).
	# **统一**返回形状：每个决策函数都带 popSheet（扫描与调用方可整份读状态而无需查键）。
	return {"bindings": gpOut, "popSheet": gpSheet, "poppedSheet": gpSheet}


# RETURN as a model case (absorbs the close-the-window bookkeeping): the popped sheet
# comes back into [param gpHomePane] with the SAME swap semantics as the picker (D05
# symmetry), then empty slots refill (the layout may have changed while the window was
# open). Nothing else may hold the sheet while the window does, so no other pane can
# displace it — the swap only fires in the defensive case where the layout moved it.
# 归位成为模型 case（吸收关窗记账）：已摘出图纸以与选择器**相同**的交换语义回到
# [param gpHomePane]（D05 对称性），随后回填空槽（窗口打开期间布局可能变过）。窗口持有
# 图纸期间无他人可持有，故交换只在布局移动过它的防御情形下触发。
static func gpReturn(gpBindings: Array[int], gpSheetIdx: int, gpHomePane: int,
		gpTabCount: int) -> Dictionary:
	var gpOut: Array[int] = GPPaneLayout.gpSwapOrBind(gpBindings, gpHomePane, gpSheetIdx)
	gpOut = GPPaneLayout.gpRefill(gpOut, gpTabCount, GPPaneLayout.GP_EMPTY)
	return {"bindings": gpOut, "popSheet": GPPaneLayout.GP_EMPTY, "homePane": gpHomePane}


# Layout RESIZE as a model case (absorbs gpResized + the refill whose exclude MUST be the
# window's sheet): sheets losing a pane come back into surviving slots; the popped sheet
# stays OUT of the pane pool (it already has a host).
# 布局重排成为模型 case（吸收 gpResized + 回填时 exclude **必须**是窗口图纸）：失去窗格的
# 图纸回到存活窗格；已摘出图纸**不**进窗格池（它已有宿主）。
static func gpResized(gpBindings: Array[int], gpPopSheet: int, gpNewCount: int,
		gpKeepSheet: int, gpTabCount: int) -> Dictionary:
	var gpOut: Array[int] = GPPaneLayout.gpResized(gpBindings, gpNewCount, gpKeepSheet)
	gpOut = GPPaneLayout.gpRefill(gpOut, gpTabCount, gpPopSheet)
	_gpEnforceWindowUniqueness(gpOut, gpPopSheet)
	return {"bindings": gpOut, "popSheet": gpPopSheet}


# REFILL as a model case: every empty pane takes the first unbound sheet; the window's
# sheet (if any) is excluded from the pool. Pure.
# 回填成为模型 case：每个空窗格拿第一个未显示图纸；窗口图纸（若有）不进池。纯函数。
static func gpRefillAll(gpBindings: Array[int], gpPopSheet: int, gpTabCount: int) -> Dictionary:
	var gpOut: Array[int] = GPPaneLayout.gpRefill(gpBindings, gpTabCount, gpPopSheet)
	_gpEnforceWindowUniqueness(gpOut, gpPopSheet)
	return {"bindings": gpOut, "popSheet": gpPopSheet}


# The shared "window wins" guard (hostile input): if a pane still shows the sheet the
# window already hosts, that pane empties — the invariant "one sheet, one host" survives
# even an already-violating state. Called at every model exit that can carry a clash.
# 共享的「窗口获胜」守卫（敌意输入）：若某窗格仍显示窗口已持有的图纸，该窗格清空 ——
# 「一图一宿主」不变量即使在已违规的状态下也得以存续。凡出口可能携带撞车的模型函数都调用。
static func _gpEnforceWindowUniqueness(gpOut: Array[int], gpPopSheet: int) -> void:
	if gpPopSheet < 0:
		return
	var gpClash: int = gpOut.find(gpPopSheet)
	if gpClash >= 0:
		gpOut[gpClash] = GPPaneLayout.GP_EMPTY
