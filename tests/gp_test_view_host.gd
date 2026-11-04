extends "res://tests/gp_test.gd"
# A1 (W12 closure plan §4.1, R3): the GPViewHostModel pure decision functions — the ONE
# entry for pane+window host state. These tests pin the invariants that killed the
# D02/D04/D05 bug family, so a regression has to walk straight into them.
# A1（W12 收口方案 §4.1，R3）：GPViewHostModel 纯决策函数 —— 窗格+窗口宿主状态的唯一入口。
# 本套件钉住终结 D02/D04/D05 bug 家族的不变量，回归必然正面撞上它们。
#
# Failure modes being guarded against: (1) a sheet held by TWO hosts at once (pane and
# window fight over one canvas — the D02 root shape); (2) a pane left blank by a bind
# that could swap (D05); (3) the window host NOT following a tab close (pop-state pointing
# at a dead index); (4) the popped sheet entering the pane pool on refill/resize (the
# window would lose its canvas); (5) an impure function mutating its input.
# 所防范的失效模式：(1) 同一图纸被**两个**宿主持有（窗格与窗口争抢画布 —— D02 病根形状）；
# (2) 可以交换的绑定把窗格留白（D05）；(3) 关标签后窗口宿主不跟随（弹窗状态指向死下标）；
# (4) 回填/重排时已摘出图纸混进窗格池（窗口会失去画布）；(5) 函数不纯、原地改输入。

# A three-pane rig: pane0=sheet0, pane1=sheet1, pane2=empty, window=EMPTY.
# 三窗格夹具：窗格0=图纸0，窗格1=图纸1，窗格2=空，窗口=无。
func _gpRig() -> Dictionary:
	var gpB: Array[int] = [0, 1, GPPaneLayout.GP_EMPTY]
	return {"b": gpB, "pop": GPPaneLayout.GP_EMPTY}


# ---- gpCanBind ----

func gpTestCanBindRefusesPoppedAndRange() -> void:
	var gpR: Dictionary = _gpRig()
	gpEq(GPViewHostModel.gpCanBind(gpR["b"], gpR["pop"], 2, 2), "",
		"legal bind returns empty / 合法绑定返回空串")
	gpEq(GPViewHostModel.gpCanBind(gpR["b"], 1, 2, 1), "view.host_popped",
		"popped sheet is refused / 已摘出图纸被拒")
	gpEq(GPViewHostModel.gpCanBind(gpR["b"], gpR["pop"], 9, 2), "view.host_range",
		"pane out of range is refused / 窗格越界被拒")
	gpEq(GPViewHostModel.gpCanBind(gpR["b"], gpR["pop"], 2, -1), "",
		"clearing a pane (sheet<0) is legal / 清空窗格（sheet<0）合法")


# ---- gpActivate (D02 as a model case) ----

func gpTestActivateFocusesWindowForPoppedSheet() -> void:
	var gpR: Dictionary = _gpRig()
	var gpAct: Dictionary = GPViewHostModel.gpActivate(gpR["b"], 1, 0, 1)
	gpEq(gpAct["action"], "focus_window", "popped sheet focuses the window / 已摘出图纸聚焦窗口")
	gpEq(gpAct["pane"], -1, "no pane involved / 不涉及窗格")
	# The state MUST NOT change: a rebind here is the D02 bug shape.
	# 状态**绝不能**变：此处重绑正是 D02 的病灶形状。
	gpCheck((gpAct["bindings"] as Array[int]) == (gpR["b"] as Array[int]),
		"bindings untouched on focus_window / focus_window 不动绑定")
	gpEq(gpAct["popSheet"], 1, "popSheet untouched / popSheet 不变")


func gpTestActivateBindsIntoActivePane() -> void:
	var gpR: Dictionary = _gpRig()
	# Sheet 2 shows nowhere: activate = bind into the active pane (2), uniqueness moves it.
	# 图纸 2 无人显示：激活 = 绑入活动窗格（2），唯一性由绑定保证。
	var gpAct: Dictionary = GPViewHostModel.gpActivate(gpR["b"], gpR["pop"], 2, 2)
	gpEq(gpAct["action"], "bind", "unshown sheet binds / 无人显示的图纸走绑定")
	gpEq(gpAct["pane"], 2, "into the active pane / 绑入活动窗格")
	gpEq((gpAct["bindings"] as Array[int])[2], 2, "pane 2 now shows sheet 2 / 窗格 2 显示图纸 2")


# ---- gpBindOrSwap (D05 as a model case) ----

func gpTestBindPlainWhenUnshown() -> void:
	var gpR: Dictionary = _gpRig()
	var gpOut: Dictionary = GPViewHostModel.gpBindOrSwap(gpR["b"], gpR["pop"], 2, 2)
	gpEq(gpOut["swapped"], false, "unshown sheet is a plain bind / 无人显示是普通绑定")
	gpEq((gpOut["bindings"] as Array[int])[2], 2, "pane 2 got the sheet / 窗格 2 拿到图纸")
	gpEq((gpOut["bindings"] as Array[int])[0], 0, "pane 0 untouched / 窗格 0 不受影响")


func gpTestBindSwapsWhenHeldByAnotherPane() -> void:
	var gpR: Dictionary = _gpRig()
	# Pane 2 picks sheet 0 (held by pane 0): the panes SWAP — pane 2 gets sheet 0, pane 0
	# gets pane 2's sheet... which is EMPTY, so the swap hands sheet 0 to pane 2 and
	# GP_EMPTY to pane 0. No OTHER pane is displaced.
	# 窗格 2 选图纸 0（窗格 0 持有）：两窗格**交换** —— 窗格 2 得图纸 0，窗格 0 接收窗格 2
	# 的内容（空）。没有其它窗格被挤走。
	var gpOut: Dictionary = GPViewHostModel.gpBindOrSwap(gpR["b"], gpR["pop"], 2, 0)
	gpEq(gpOut["swapped"], true, "held sheet triggers a swap / 被持有的图纸触发交换")
	gpEq((gpOut["bindings"] as Array[int])[2], 0, "pane 2 now shows sheet 0 / 窗格 2 显示图纸 0")
	gpEq((gpOut["bindings"] as Array[int])[0], GPPaneLayout.GP_EMPTY,
		"pane 0 received pane 2's old content (empty) / 窗格 0 接收窗格 2 的旧内容（空）")


func gpTestBindRefusedForPoppedSheet() -> void:
	var gpR: Dictionary = _gpRig()
	# Sheet 1 lives in the WINDOW: binding it into a pane is refused (state unchanged) —
	# the caller must focus the window instead.
	# 图纸 1 住在**窗口**：绑入窗格被拒（状态不变）—— 调用方应改为聚焦窗口。
	var gpOut: Dictionary = GPViewHostModel.gpBindOrSwap(gpR["b"], 1, 0, 1)
	gpCheck((gpOut["bindings"] as Array[int]) == (gpR["b"] as Array[int]),
		"bindings unchanged for a popped pick / 对已摘出图纸的选取不动绑定")


# ---- gpAfterSheetClosed ----

func gpTestCloseShiftsPanesAndBindings() -> void:
	var gpR: Dictionary = _gpRig()
	# Typed assignment: a bare literal into a Dictionary slot would arrive UNTYPED at the
	# model's Array[int] parameter (a real GUT-run failure — keep the type all the way).
	# 类型化赋值：裸字面量写进 Dictionary 槽位后，到达模型的 Array[int] 参数时已**失去
	# 类型**（GUT 实跑翻车的真实形态 —— 类型全程保住）。
	var gpBIn: Array[int] = [0, 2, 1]
	gpR["b"] = gpBIn
	# Close sheet index 1 (shown in pane 2): pane 2 empties, no shift for pane 1 (2>1 → 1).
	# 关闭下标 1 的图纸（窗格 2 显示中）：窗格 2 清空；窗格 1 的 2>1 前移为 1。
	var gpOut: Dictionary = GPViewHostModel.gpAfterSheetClosed(gpR["b"], gpR["pop"], 1)
	var gpB: Array[int] = gpOut["bindings"]
	gpEq(gpB[0], 0, "pane 0 keeps sheet 0 / 窗格 0 保持图纸 0")
	gpEq(gpB[1], 1, "pane 1 shifted down (2→1) / 窗格 1 前移（2→1）")
	gpEq(gpB[2], GPPaneLayout.GP_EMPTY, "pane 2 emptied / 窗格 2 清空")


func gpTestCloseEmptiesWindowWhenPoppedSheetClosed() -> void:
	var gpR: Dictionary = _gpRig()
	# The WINDOW holds sheet 1 and sheet 1 is closed: the window slot MUST empty (a pop
	# state pointing at a dead index is the exact bug the model absorbs).
	# 窗口持有图纸 1 而图纸 1 被关：窗口槽位**必须**清空（弹窗状态指向死下标正是模型
	# 吸收的那个 bug）。
	var gpOut: Dictionary = GPViewHostModel.gpAfterSheetClosed(gpR["b"], 1, 1)
	gpEq(gpOut["popSheet"], GPPaneLayout.GP_EMPTY, "window slot emptied / 窗口槽位清空")
	gpEq(gpOut["bindings"][0], 0, "pane 0 untouched / 窗格 0 不受影响")


func gpTestCloseShiftsWindowIndex() -> void:
	var gpR: Dictionary = _gpRig()
	# The window holds sheet 2; sheet 0 closes → the window's sheet shifts down to 1.
	# 窗口持有图纸 2；图纸 0 关闭 → 窗口的图纸前移为 1。
	var gpOut: Dictionary = GPViewHostModel.gpAfterSheetClosed(gpR["b"], 2, 0)
	gpEq(gpOut["popSheet"], 1, "window host follows the shift / 窗口宿主随之前移")
	# Pane 1 kept showing the SAME sheet (old index 1) — it just renumbered to 0.
	# 窗格 1 仍显示**同一张**图纸（旧下标 1）—— 只是下标前移为 0。
	gpEq(gpOut["bindings"][1], 0, "pane 1 still shows the same sheet / 窗格 1 仍显示原图纸")


# ---- gpPopOut ----

func gpTestPopOutMovesSheetToWindow() -> void:
	var gpR: Dictionary = _gpRig()
	var gpOut: Dictionary = GPViewHostModel.gpPopOut(gpR["b"], 1)
	gpEq(gpOut["poppedSheet"], 1, "sheet 1 popped / 图纸 1 被摘出")
	gpEq((gpOut["bindings"] as Array[int])[1], GPPaneLayout.GP_EMPTY,
		"pane 1 emptied / 窗格 1 清空")
	gpEq((gpOut["bindings"] as Array[int])[0], 0, "pane 0 untouched / 窗格 0 不受影响")


func gpTestPopOutEmptyPaneIsRefused() -> void:
	var gpR: Dictionary = _gpRig()
	var gpOut: Dictionary = GPViewHostModel.gpPopOut(gpR["b"], 2)
	gpEq(gpOut["poppedSheet"], GPPaneLayout.GP_EMPTY,
		"popping an empty pane is refused / 摘出空窗格被拒")
	gpOut = GPViewHostModel.gpPopOut(gpR["b"], 9)
	gpEq(gpOut["poppedSheet"], GPPaneLayout.GP_EMPTY,
		"popping an out-of-range pane is refused / 摘出越界窗格被拒")


# ---- gpReturn ----

func gpTestReturnBindsHomeAndRefills() -> void:
	var gpR: Dictionary = _gpRig()
	# Sheet 2 was popped (pane 1 emptied beforehand); home = pane 1. Return binds it back
	# and refills pane 2 with the first unbound sheet.
	# 图纸 2 已摘出（窗格 1 事先清空）；home = 窗格 1。归位绑回并回填窗格 2。
	var gpB: Array[int] = [0, GPPaneLayout.GP_EMPTY, GPPaneLayout.GP_EMPTY]
	var gpOut: Dictionary = GPViewHostModel.gpReturn(gpB, 2, 1, 3)
	gpEq((gpOut["bindings"] as Array[int])[1], 2, "sheet 2 back in its home pane / 图纸 2 回到 home 窗格")
	gpEq((gpOut["bindings"] as Array[int])[2], 1, "pane 2 refilled with sheet 1 / 窗格 2 回填图纸 1")
	gpEq(gpOut["popSheet"], GPPaneLayout.GP_EMPTY, "window slot cleared / 窗口槽位清空")


func gpTestReturnSwapsWhenHomeMovedOn() -> void:
	var gpR: Dictionary = _gpRig()
	# Defensive D05 symmetry: the home pane picked up sheet 0 while the window was open.
	# Returning sheet 2 to it SWAPS — pane 0 gets sheet 2, the home keeps sheet 0's place…
	# actually the swap exchanges CONTENTS: home(pane 1) had sheet 0, so pane 1 keeps
	# showing sheet 0? No — swap exchanges pane1<->pane0? Verify the exact contract:
	# swapOrBind(bind into pane 1, sheet 2) — sheet 2 shows NOWHERE, so it is a PLAIN
	# bind and pane 1 simply gets sheet 2 (sheet 0 is NOT displaced — it shows in pane 0).
	# 防御性 D05 对称：窗口打开期间 home 窗格拿了图纸 0。图纸 2 归位——图纸 2 无人显示，
	# 走**普通**绑定，窗格 1 直接拿到图纸 2（窗格 0 的图纸 0 不受影响）。
	var gpB: Array[int] = [0, 0, GPPaneLayout.GP_EMPTY]
	# (pane 1 showing sheet 0 duplicates pane 0 — a hostile input the refill would fix;
	# the model must still not corrupt anything.)
	#（窗格 1 与窗格 0 都显示图纸 0 —— 回填会修复的敌意输入；模型仍不得破坏任何东西。）
	var gpOut: Dictionary = GPViewHostModel.gpReturn(gpB, 2, 1, 3)
	gpEq((gpOut["bindings"] as Array[int])[1], 2, "home pane got the returned sheet / home 窗格拿到归位图纸")
	gpEq((gpOut["bindings"] as Array[int])[0], 0, "pane 0 untouched / 窗格 0 不受影响")


# ---- gpResized ----

func gpTestResizeShrinksKeepsActiveAndExcludesPop() -> void:
	var gpR: Dictionary = _gpRig()
	# 3 panes → 1 pane. The ACTIVE sheet (gpKeepSheet=1) must win the surviving slot;
	# the popped sheet (2) must NOT enter the pane pool.
	# 3 窗格 → 1 窗格。**活动**图纸（keepSheet=1）必须赢得存活槽位；已摘出图纸（2）不得
	# 进窗格池。
	var gpB: Array[int] = [0, 1, GPPaneLayout.GP_EMPTY]
	var gpOut: Dictionary = GPViewHostModel.gpResized(gpB, 2, 1, 1, 3)
	var gpB1: Array[int] = gpOut["bindings"]
	gpEq(gpB1.size(), 1, "one pane slot / 一个窗格槽位")
	gpEq(gpB1[0], 1, "the ACTIVE sheet won the slot / 活动图纸赢得槽位")


func gpTestResizeGrowsAndRefills() -> void:
	var gpR: Dictionary = _gpRig()
	# 3 panes → 4 panes; sheets 0,1 shown, sheet 2 unbound → pane 3 refills with sheet 2.
	# 3 窗格 → 4 窗格；图纸 0、1 已显示，图纸 2 无人绑 → 窗格 3 回填图纸 2。
	var gpB: Array[int] = [0, 1, GPPaneLayout.GP_EMPTY]
	var gpOut: Dictionary = GPViewHostModel.gpResized(gpB, GPPaneLayout.GP_EMPTY, 4, 0, 3)
	var gpB4: Array[int] = gpOut["bindings"]
	gpEq(gpB4.size(), 4, "four pane slots / 四个窗格槽位")
	gpEq(gpB4[2], 2, "pane 2 refilled with the unbound sheet / 窗格 2 回填未绑图纸")


# ---- gpRefillAll ----

func gpTestRefillFillsEmptyAndSkipsPopped() -> void:
	var gpR: Dictionary = _gpRig()
	# Panes: sheet0, empty, empty. Window holds sheet 1. Refill must give the empties the
	# sheets NOTHING shows (2 is out of range for 3 tabs; so only… tab count 3: sheets
	# 0,1,2 — sheet 1 is the WINDOW's, so the pool is {2}; one empty gets 2, the other
	# stays empty (pool drained).
	# 窗格：图纸0、空、空。窗口持有图纸 1。回填必须把「无人显示」的图纸给空窗格
	#（3 张标签：0,1,2 —— 图纸 1 在窗口，池 = {2}；一个空窗格得 2，另一个保持空）。
	var gpB: Array[int] = [0, GPPaneLayout.GP_EMPTY, GPPaneLayout.GP_EMPTY]
	var gpOut: Dictionary = GPViewHostModel.gpRefillAll(gpB, 1, 3)
	var gpB2: Array[int] = gpOut["bindings"]
	gpEq(gpB2[1], 2, "first empty refilled from the pool / 第一个空窗格从池回填")
	gpEq(gpB2[2], GPPaneLayout.GP_EMPTY, "pool drained: second empty stays / 池已尽：第二个空窗格保持空")
	# THE invariant: the popped sheet never entered a pane.
	# **核心不变量**：已摘出图纸绝不出现在窗格里。
	gpCheck(not gpB2.has(1), "the window's sheet stays out of the panes / 窗口图纸不进窗格")


# ---- cross-host invariant sweeps ----

# After EVERY decision, a sheet must never be held by two hosts at once.
# 每个决策之后，同一图纸绝不被两个宿主同时持有。
func gpTestInvariantSheetNeverInTwoHosts() -> void:
	var gpB: Array[int] = [0, 1, 2]
	var gpCases: Array = [
		GPViewHostModel.gpBindOrSwap(gpB, GPPaneLayout.GP_EMPTY, 2, 0),
		GPViewHostModel.gpAfterSheetClosed(gpB, 2, 0),
		GPViewHostModel.gpPopOut(gpB, 1),
		GPViewHostModel.gpReturn(gpB, 2, 1, 3),
		GPViewHostModel.gpResized(gpB, 2, 2, 1, 3),
		GPViewHostModel.gpRefillAll(gpB, 2, 3),
		GPViewHostModel.gpActivate(gpB, GPPaneLayout.GP_EMPTY, 0, 1),
	]
	for gpI in range(gpCases.size()):
		var gpOut: Dictionary = gpCases[gpI]
		var gpB2: Array[int] = gpOut["bindings"]
		var gpPop: int = gpOut["popSheet"]
		if gpPop < 0:
			continue
		gpCheck(not gpB2.has(gpPop),
			"case %d: window sheet must not appear in panes / 用例 %d：窗口图纸不得出现在窗格" % [gpI, gpI])


# Purity: no decision function may mutate its inputs.
# 纯度：任何决策函数都不得原地修改输入。
func gpTestInputsNeverMutated() -> void:
	var gpB: Array[int] = [0, 1, 2]
	var gpBefore: Array[int] = gpB.duplicate()
	GPViewHostModel.gpBindOrSwap(gpB, GPPaneLayout.GP_EMPTY, 2, 0)
	GPViewHostModel.gpAfterSheetClosed(gpB, 2, 0)
	GPViewHostModel.gpPopOut(gpB, 1)
	GPViewHostModel.gpReturn(gpB, 2, 1, 3)
	GPViewHostModel.gpResized(gpB, 2, 2, 1, 3)
	GPViewHostModel.gpRefillAll(gpB, 2, 3)
	GPViewHostModel.gpActivate(gpB, GPPaneLayout.GP_EMPTY, 0, 1)
	gpCheck(gpB == gpBefore, "inputs survive every call unchanged / 输入经所有调用后原样不变")


# The window participates in the uniqueness domain end-to-end: pop sheet 2 out, then a
# bind of sheet 2 into any pane must leave the state untouched (the caller focuses).
# 窗口端到端参与唯一性判定域：摘出图纸 2 后，把图纸 2 绑入任何窗格都必须原样返回
#（调用方应聚焦）。
func gpTestPoppedSheetBindIsFullNoOp() -> void:
	var gpB: Array[int] = [0, 1, 2]
	var gpPop: Dictionary = GPViewHostModel.gpPopOut(gpB, 2)
	var gpB2: Array[int] = gpPop["bindings"]
	var gpPopped: int = gpPop["poppedSheet"]
	for gpI in range(3):
		var gpOut: Dictionary = GPViewHostModel.gpBindOrSwap(gpB2, gpPopped, gpI, gpPopped)
		gpCheck((gpOut["bindings"] as Array[int]) == gpB2,
			"bind of the popped sheet into pane %d is a no-op / 对已摘出图纸绑入窗格 %d 是空操作" % [gpI, gpI])
		gpEq(gpOut["popSheet"], gpPopped, "window still holds it / 窗口仍持有它")
