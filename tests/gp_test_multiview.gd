extends "res://tests/gp_test.gd"
# W13 multi-view (ADR-44): the pane LAYOUT MODEL and the cross-layer agreement pins.
# The layout lives in GPCenterArea's containers (untestable headless — it needs autoloads);
# every DECISION behind it lives in GPPaneLayout as pure functions and IS tested here:
# pane counts per mode, the one-sheet-one-pane uniqueness invariant, close/refill/resizing,
# and the Settings<->GPPaneLayout cross-side pin (the autoload may not reference the ui
# layer, so the two validity tables must be pinned EQUAL — iron rule 86 style).
# W13 多视图（ADR-44）：窗格**布局模型**与跨层一致性钉。布局本体在 GPCenterArea 的容器里
#（headless 不可测 —— 需要 autoload）；其背后的一切**判定**都是 GPPaneLayout 的纯函数，
# 在此受测：各模式窗格数、「一图一窗格」唯一性不变量、关闭 / 回填 / 收窄，以及
# Settings<->GPPaneLayout 跨侧钉（autoload 不得引用 ui 层，故两份合法性表必须被钉成
# **相等** —— 铁律 86 式）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


# ------------------------------------------------------------------ mode table
# 模式表

func gpTestModesDeclareTheirPaneCounts() -> void:
	gpEq(GPPaneLayout.gpPaneCount(GPPaneLayout.GP_SINGLE), 1, "single = 1 pane")
	gpEq(GPPaneLayout.gpPaneCount(GPPaneLayout.GP_SIDE), 2, "side-by-side = 2 panes")
	gpEq(GPPaneLayout.gpPaneCount(GPPaneLayout.GP_BIG2), 3, "one large + two small = 3 panes")
	gpEq(GPPaneLayout.gpPaneCount(GPPaneLayout.GP_GRID), 4, "2x2 grid = 4 panes")
	gpEq(GPPaneLayout.gpPaneCount(0), 0, "mode 0 is invalid")
	gpEq(GPPaneLayout.gpPaneCount(5), 0, "mode 5 is invalid (over 4 panes is YAGNI)")
	gpEq(GPPaneLayout.gpPaneCount(-1), 0, "a negative mode is invalid")


# The CROSS-SIDE PIN: Settings (autoload, may not reference ui) validates the stored layout
# mode against a literal 1..4 range; GPPaneLayout is the ui layer's own table. If the two
# ever disagree (a mode added to one and forgotten in the other), a stale config value would
# either be accepted into a broken first frame or silently downgrade a real layout.
# **跨侧钉**：Settings（autoload，不得引用 ui）以字面量 1..4 校验存档的布局模式；
# GPPaneLayout 是 ui 层自己的表。二者一旦分家（一侧加了模式、另一侧忘了），陈旧配置值
# 要么被接受进坏掉的第一帧，要么把真实布局悄悄降级。
func gpTestSettingsRangeAgreesWithTheLayoutTable() -> void:
	for gpMode in [1, 2, 3, 4]:
		gpCheck(GPPaneLayout.gpIsValid(gpMode),
			"the Settings literal range accepts only modes the layout table knows: %d" % gpMode)
	gpCheck(not GPPaneLayout.gpIsValid(0), "mode 0 is invalid on the layout side too")
	gpCheck(not GPPaneLayout.gpIsValid(5), "mode 5 is invalid on the layout side too")


# ------------------------------------------------------------------ binding invariant
# 绑定不变量

func gpTestBindEnforcesOneSheetOnePane() -> void:
	# Two panes, sheet 0 in pane 0. Binding sheet 0 into pane 1 must EMPTY pane 0 — a sheet
	# shown twice would need a cloned canvas (ADR-44 D2: refused by decision ⑤).
	# 两窗格，图纸 0 在窗格 0。把图纸 0 绑进窗格 1 必须清空窗格 0 —— 一张图显示两遍
	# 需要克隆画布（ADR-44 D2：用户拍板⑤拒绝）。
	var gpB: Array[int] = [0, GPPaneLayout.GP_EMPTY]
	gpB = GPPaneLayout.gpBind(gpB, 1, 0)
	gpEq(gpB[0], GPPaneLayout.GP_EMPTY, "the pane that showed the sheet first is emptied")
	gpEq(gpB[1], 0, "the newly aimed pane holds the sheet")
	# Purity: the input array must be untouched — the caller replaces its state with the
	# return value, so an in-place mutation would look like success while corrupting undo.
	# 纯性：输入数组必须原封不动 —— 调用方用返回值替换自身状态，原地修改会在看似成功时
	# 悄悄弄坏状态。
	var gpOrig: Array[int] = [0, GPPaneLayout.GP_EMPTY]
	GPPaneLayout.gpBind(gpOrig, 1, 0)
	gpEq(gpOrig[0], 0, "the input array is NOT mutated (pure function)")


func gpTestBindRejectsNonsense() -> void:
	var gpB: Array[int] = [0, GPPaneLayout.GP_EMPTY]
	gpB = GPPaneLayout.gpBind(gpB, 7, 1)
	gpEq(gpB[0], 0, "binding into a nonexistent pane changes nothing")
	gpB = GPPaneLayout.gpBind(gpB, 0, -1)
	gpEq(gpB[0], 0, "binding a negative sheet index changes nothing")


# ------------------------------------------------------------------ close / refill
# 关闭 / 回填

func gpTestTabCloseShiftsAndEmpties() -> void:
	# 3 sheets in 2 panes: pane0=0, pane1=2. Closing sheet 1 shifts sheet 2 down; the panes
	# keep showing THE SAME sheets, just renumbered.
	# 3 张图纸、2 个窗格：窗格0=0，窗格1=2。关闭图纸 1 后图纸 2 前移；窗格仍显示**同样的**
	# 图纸，只是编号变了。
	var gpB: Array[int] = [0, 2]
	gpB = GPPaneLayout.gpAfterTabRemoved(gpB, 1)
	gpEq(gpB[0], 0, "the pane before the removed sheet keeps its sheet")
	gpEq(gpB[1], 1, "the pane after the removed sheet follows the shift")
	# Closing a SHOWN sheet empties its pane (refill decides what appears there).
	# 关闭**正被显示**的图纸会清空其窗格（回填决定那里出现什么）。
	gpB = [1, GPPaneLayout.GP_EMPTY]
	gpB = GPPaneLayout.gpAfterTabRemoved(gpB, 1)
	gpEq(gpB[0], GPPaneLayout.GP_EMPTY, "the pane that showed the closed sheet goes empty")


func gpTestRefillDrainsLeftToRight() -> void:
	# 4 sheets, 2 panes, both empty -> pane0 gets 0, pane1 gets 1 (the ADR-44 reading order).
	# 4 张图纸、2 个空窗格 -> 窗格0 得 0、窗格1 得 1（ADR-44 阅读顺序）。
	var gpB: Array[int] = GPPaneLayout.gpRefill(
		[GPPaneLayout.GP_EMPTY, GPPaneLayout.GP_EMPTY], 4)
	gpEq(gpB[0], 0, "the first empty pane takes the first unbound sheet")
	gpEq(gpB[1], 1, "the next empty pane takes the next unbound sheet")
	# Fewer sheets than panes: no phantom bindings.
	# 图纸少于窗格：不得出现幻影绑定。
	gpB = GPPaneLayout.gpRefill([GPPaneLayout.GP_EMPTY, GPPaneLayout.GP_EMPTY], 1)
	gpEq(gpB[0], 0, "the only sheet fills the first pane")
	gpEq(gpB[1], GPPaneLayout.GP_EMPTY, "a pane with no sheet left stays honestly empty")
	# The EXCLUDE slot: the popped-out sheet (W13-S7) must never be refilled into a pane —
	# the window and the pane would fight over the same canvas.
	# **排除**槽：被摘出的图纸（W13-S7）绝不能被回填进窗格 —— 窗口与窗格会争抢同一块画布。
	gpB = GPPaneLayout.gpRefill([GPPaneLayout.GP_EMPTY, GPPaneLayout.GP_EMPTY], 3, 0)
	gpEq(gpB[0], 1, "the excluded sheet is skipped")
	gpEq(gpB[1], 2, "and the next one fills the second pane")


# ------------------------------------------------------------------ mode switch
# 切换模式

func gpTestResizeKeepsEveryVisibleSheetOrPrioritisesTheActiveOne() -> void:
	# 2 -> 4 panes: the bindings survive, new slots are empty.
	# 2 -> 4 窗格：绑定保留，新槽为空。
	var gpB: Array[int] = GPPaneLayout.gpResized([0, 1], 4, 0)
	gpEq(gpB[0], 0, "shrink-free resize keeps pane 0's sheet")
	gpEq(gpB[1], 1, "shrink-free resize keeps pane 1's sheet")
	gpEq(gpB[2], GPPaneLayout.GP_EMPTY, "the new pane starts empty")
	gpEq(gpB[3], GPPaneLayout.GP_EMPTY, "the new pane starts empty")
	# 4 -> 2 panes with 4 shown sheets: capacity is a HARD limit — only two sheets CAN be
	# visible. The first two bindings survive; the orphans cannot fit (the pickers stay the
	# honest way back to them).
	# 4 -> 2 窗格、4 张全显示：容量是**硬**限制 —— 只可能有两条图纸可见。前两个绑定存活；
	# 孤儿装不下（选择器是回到它们的诚实途径）。
	gpB = GPPaneLayout.gpResized([0, 1, 2, 3], 2, 0)
	gpEq(gpB.size(), 2, "the binding list is clamped to the new pane count")
	gpEq(gpB[0], 0, "the first binding keeps its pane")
	gpEq(gpB[1], 1, "the second binding keeps its pane")
	# An orphan DOES come back when a slot is free: [0, empty, 2] -> 2 panes brings sheet 2
	# into the freed slot — no sheet may vanish while a seat exists.
	# 有空槽时孤儿**必须**回来：[0, 空, 2] -> 2 窗格把图纸 2 放进空出的槽 —— 只要还有座位，
	# 就不许有图纸从视野里消失。
	gpB = GPPaneLayout.gpResized([0, GPPaneLayout.GP_EMPTY, 2], 2, 0)
	gpEq(gpB[0], 0, "the bound sheet keeps its pane")
	gpEq(gpB[1], 2, "the orphan takes the freed slot")
	# The ACTIVE sheet can never be the one that vanishes: with no free slot it displaces
	# pane 0's content. Every dock consumer reads the active pane's sheet, so losing IT
	# would break the whole UI.
	# **活动**图纸绝不能是被消失的那张：无空槽时它顶掉窗格 0 的内容。所有停靠消费方读的
	# 都是活动窗格的图纸，丢掉它整个 UI 就断了。
	gpB = GPPaneLayout.gpResized([2, 3], 1, 9)
	gpEq(gpB.size(), 1, "clamped to one pane")
	gpEq(gpB[0], 9, "the active sheet wins the last slot when nothing else is free")
	gpB = GPPaneLayout.gpResized([2, 3], 1, GPPaneLayout.GP_EMPTY)
	gpEq(gpB[0], 2, "with no active sheet to protect, the first binding survives")
