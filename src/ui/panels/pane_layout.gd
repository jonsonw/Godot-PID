class_name GPPaneLayout
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# The MULTI-VIEW pane model as PURE functions (ADR-44, W13-S6). The layout itself lives in
# GPCenterArea's containers; this class owns only the DECISIONS — how many panes a mode has,
# and the pane<->sheet binding invariants — so they are testable headless and the container
# code cannot quietly grow a second, drifting copy of them.
# 多视图窗格模型的**纯函数**部分（ADR-44，W13-S6）。布局本体住在 GPCenterArea 的容器里；
# 本类只管**判定** —— 每种模式有几个窗格、窗格与图纸绑定的不变量 —— 使其可 headless 测试，
# 容器代码也不可能悄悄长出第二份会分家的副本。
#
# Binding invariant (ADR-44 D2, user decision ⑤): a sheet is shown in AT MOST ONE pane.
# Bindings are an Array[int] with one slot per pane; a slot holds the SHEET TAB INDEX or
# GP_EMPTY when the pane shows nothing.
# 绑定不变量（ADR-44 D2，用户拍板⑤）：一张图纸至多出现在**一个**窗格。绑定是每窗格一个槽位的
# Array[int]；槽位存图纸标签下标，空窗格为 GP_EMPTY。
#
# View state NEVER enters the document (iron rule 74, ADR-44 D5): these structures are
# session-only; only the MODE survives into Settings.
# 视图状态**绝不**进入文档（铁律 74，ADR-44 D5）：以下结构仅活在会话内；只有**模式**进 Settings。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Layout modes. 1 = stacked (the historical look); 2 = side-by-side; 3 = one large pane +
# two stacked on the other side; 4 = the 2x2 grid (nested splits, draggable dividers).
# 布局模式。1 = 堆叠（历史外观）；2 = 左右二分；3 = 一大窗格 + 另一侧上下两小格；4 = 2×2
#（嵌套 split，分隔条可拖动）。
const GP_SINGLE: int = 1
const GP_SIDE: int = 2
const GP_BIG2: int = 3
const GP_GRID: int = 4

# The slot value of an EMPTY pane (shows the placeholder, hosts no canvas).
# 空窗格的槽位值（显示占位符，不承载画布）。
const GP_EMPTY: int = -1

# The pane count of a mode; 0 for an invalid mode (callers then keep the old layout).
# 某模式的窗格数；非法模式为 0（调用方保持原布局不变）。
static func gpPaneCount(gpMode: int) -> int:
	match gpMode:
		GP_SINGLE:
			return 1
		GP_SIDE:
			return 2
		GP_BIG2:
			return 3
		GP_GRID:
			return 4
	return 0


# Whether gpMode is one of the four supported layouts.
# gpMode 是否为四种受支持布局之一。
static func gpIsValid(gpMode: int) -> bool:
	return gpPaneCount(gpMode) > 0


# Bind gpSheetIdx into gpPaneIdx. Enforces the uniqueness invariant: whatever pane currently
# shows that sheet is emptied first. Returns the NEW array (pure — the caller replaces its
# state with the return value; the input is never mutated).
# 把 gpSheetIdx 绑定到 gpPaneIdx。强制唯一性不变量：当前显示该图纸的窗格先被清空。
# 返回**新**数组（纯函数 —— 调用方用返回值替换自身状态；输入绝不被原地修改）。
static func gpBind(gpBindings: Array[int], gpPaneIdx: int, gpSheetIdx: int) -> Array[int]:
	var gpOut: Array[int] = gpBindings.duplicate()
	if gpPaneIdx < 0 or gpPaneIdx >= gpOut.size() or gpSheetIdx < 0:
		return gpOut
	# Uniqueness: only one pane may hold this sheet. / 唯一性：该图纸只允许出现在一个窗格。
	for gpI in range(gpOut.size()):
		if gpOut[gpI] == gpSheetIdx:
			gpOut[gpI] = GP_EMPTY
	gpOut[gpPaneIdx] = gpSheetIdx
	return gpOut


# Re-bindings after the sheet tab at gpRemovedIdx was CLOSED. Panes that showed it become
# empty; every binding pointing BEHIND it shifts down by one so the other panes keep showing
# the same sheets (tab indexes just moved).
# 关闭下标 gpRemovedIdx 的图纸标签后的重绑。显示它的窗格变空；指向其**后**的绑定整体前移一位，
# 使其它窗格仍显示原来的图纸（只是标签下标移动了）。
static func gpAfterTabRemoved(gpBindings: Array[int], gpRemovedIdx: int) -> Array[int]:
	var gpOut: Array[int] = []
	for gpB in gpBindings:
		if gpB == gpRemovedIdx:
			gpOut.append(GP_EMPTY)
		elif gpB > gpRemovedIdx:
			gpOut.append(gpB - 1)
		else:
			gpOut.append(gpB)
	return gpOut


# The first sheet tab index NOT shown in any pane (or GP_EMPTY when every sheet is shown).
# [param gpExclude] a sheet index that must not be picked (e.g. one living in the pop-out
# window — binding it to a pane would fight the window for the same canvas).
# Used to refill an empty pane with something useful instead of leaving it blank.
# 未被任何窗格显示的第一个图纸标签下标（全部已显示则为 GP_EMPTY）。
# [param gpExclude] 不可被选中的图纸下标（例如已住进摘出窗口的那张 —— 把它绑给窗格会与
# 窗口争抢同一块画布）。用于把空窗格填充成有用的内容，而非留白。
static func gpFirstUnboundSheet(gpBindings: Array[int], gpTabCount: int,
		gpExclude: int = GP_EMPTY) -> int:
	for gpS in range(gpTabCount):
		if gpS == gpExclude:
			continue
		if not gpBindings.has(gpS):
			return gpS
	return GP_EMPTY


# Refill every empty pane with the first unbound sheet (draining left to right). Pure.
# 用「第一个未显示的图纸」回填每个空窗格（自左向右消耗）。纯函数。
static func gpRefill(gpBindings: Array[int], gpTabCount: int,
		gpExclude: int = GP_EMPTY) -> Array[int]:
	var gpOut: Array[int] = gpBindings.duplicate()
	for gpI in range(gpOut.size()):
		if gpOut[gpI] == GP_EMPTY:
			var gpS: int = gpFirstUnboundSheet(gpOut, gpTabCount, gpExclude)
			if gpS == GP_EMPTY:
				break
			gpOut[gpI] = gpS
	return gpOut


# Clamp bindings to a NEW pane count (a mode switch may shrink/grow the pane list). Sheets
# that lose their pane are preserved by appending them to the surviving panes' empty slots;
# if there is no room, the ACTIVE sheet wins a slot first (the caller passes it), because
# every consumer reads the active pane's sheet — losing IT would break the whole UI.
# 把绑定收窄/扩展到**新的**窗格数（切换模式会增减窗格）。失去窗格的图纸优先补进存活窗格的
# 空槽；没有空槽时**活动**图纸优先占位（由调用方传入）—— 所有消费方读的都是活动窗格的图纸，
# 丢掉它整个 UI 就断了。
static func gpResized(gpBindings: Array[int], gpNewCount: int, gpKeepSheet: int) -> Array[int]:
	var gpOut: Array[int] = []
	for gpI in range(gpNewCount):
		gpOut.append(gpBindings[gpI] if gpI < gpBindings.size() else GP_EMPTY)
	# Sheets orphaned by the shrink (and indexes now out of range) must come back or the
	# user's sheets disappear from view.
	# 因收窄而失去窗格的图纸（以及越界下标）必须回来，否则用户的图纸会从视野里消失。
	for gpB in gpBindings:
		if gpB >= 0 and not gpOut.has(gpB):
			var gpSlot: int = gpOut.find(GP_EMPTY)
			if gpSlot < 0:
				# No free slot: the ACTIVE sheet replaces whatever pane 0 shows — it is the
				# one sheet every consumer reads, so it can never be the one that vanishes.
				# 无空槽：**活动**图纸顶掉窗格 0 的内容 —— 它是所有消费方都在读的那张，
				# 绝不能是被消失的那张。
				gpOut[0] = gpKeepSheet if gpKeepSheet >= 0 else gpOut[0]
				break
			gpOut[gpSlot] = gpB
	return gpOut
