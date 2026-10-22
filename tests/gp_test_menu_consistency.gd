extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Menu / dispatch consistency (A10): every action the menu bar or the quick bar can emit must have
# a real branch in GPMenuCoordinator.gpOnMenu().
# 菜单 / 分发一致性（A10）：菜单栏或快捷条能发出的每个动作，都必须在 GPMenuCoordinator.gpOnMenu()
# 里有真实分支。
#
# WHY THIS GATE EXISTS / 本门禁存在的原因：
# The old one-way test only proved "a registered format has a menu item". Nothing checked the OTHER
# direction, so nine menu items shipped that fell through to the single `_:` branch printing
# "feature pending". The user found them by clicking. This test finds them at gate time.
# 旧测试只做了单向（「已注册格式必须有菜单项」），没有任何东西检查**反方向**，于是有九个菜单项
# 一路落到唯一的 `_:` 分支，打出「功能待接入」。用户靠点击才发现它们。本测试在门禁时发现。
#
# HOW IT READS THE DISPATCH / 如何读取分发：
# There is no reflection into a `match`, so the gate reads the ONE function's source and extracts
# its case labels. That couples the test to the source shape, which is acceptable and deliberate:
# the alternative is a hand-maintained id list that drifts from the code it claims to describe.
# `match` 无法反射，故门禁读取**这一个函数**的源码并提取 case 标签。这确实把测试耦合到了源码形态，
# 但这是可接受且刻意的：替代方案是一份手工维护的 id 清单，它会与被描述的代码悄悄脱节。

# The dispatcher file, and the function whose case labels are the "handled set".
# 分发文件，以及「已处理集合」= 其 case 标签的那个函数。
const GP_DISPATCH_SRC: String = "res://src/ui/shell/menu_coordinator.gd"
const GP_DISPATCH_FN: String = "func gpOnMenu("

# Actions intentionally allowed to lack a branch. MUST stay empty: every entry here is a menu item
# the user can click and nothing will happen. Adding one requires a comment explaining the exit.
# 允许没有分支的动作。必须保持为空：这里每一条都是用户能点、却什么也不会发生的菜单项。
# 新增一条必须写明「为何可以没有」的注释。
const GP_DEAD_WHITELIST: Array[String] = []


# Extract the quoted tokens that appear as case labels of gpOnMenu().
# 提取 gpOnMenu() 作为 case 标签出现的引号串。
# Only lines that are a LABEL shape are considered: two tabs of indent, ending in ':', not a
# comment. Nested labels inside a branch are deeper, so they cannot masquerade as top-level ones.
# 只考虑**标签形态**的行：两个制表符缩进、以 ':' 结尾、且不是注释。分支内部的嵌套标签缩进更深，
# 因而无法冒充顶层标签。
func _gpHandledActions() -> Dictionary:
	var gpOut: Dictionary = {}
	var gpText: String = FileAccess.get_file_as_string(GP_DISPATCH_SRC)
	gpCheck(gpText != "", "能读到分发文件 / the dispatcher source is readable")
	if gpText == "":
		return gpOut
	var gpStart: int = gpText.find(GP_DISPATCH_FN)
	gpCheck(gpStart >= 0, "能找到 gpOnMenu / gpOnMenu() found")
	if gpStart < 0:
		return gpOut
	var gpNext: int = gpText.find("\nfunc ", gpStart + GP_DISPATCH_FN.length())
	var gpBody: String = gpText.substr(gpStart,
		(gpNext - gpStart) if gpNext > gpStart else (gpText.length() - gpStart))
	var gpRe: RegEx = RegEx.new()
	gpRe.compile("\"([a-z0-9_]+)\"")
	for gpLine in gpBody.split("\n"):
		if not gpLine.begins_with("\t\t"):
			continue
		if not gpLine.strip_edges().ends_with(":"):
			continue
		if gpLine.strip_edges().begins_with("#"):
			continue
		for gpM in gpRe.search_all(gpLine):
			gpOut[gpM.get_string(1)] = true
	return gpOut


# Every action id the menu bar can emit.
# 菜单栏能发出的每个动作 id。
func _gpMenuActions() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpTitle in GPPIDMenuBar.GP_MENUS.keys():
		_gpCollectMenuEntries(GPPIDMenuBar.GP_MENUS[gpTitle] as Array, gpOut)
	return gpOut


# Walk one menu level: [label_key, action] pairs, nulls (separators), and Dictionaries that are
# SUBMENUS ({"title":…, "items":[…]}) — the export submenu is one, and skipping it would silently
# shrink the set the gate checks.
# 遍历一层菜单：[label_key, action] 对、null（分隔符）、以及作为**子菜单**的字典
#（{"title":…, "items":[…]}）—— 导出子菜单就是其一，跳过它会静默缩小门禁检查的集合。
func _gpCollectMenuEntries(gpEntries: Array, gpOut: Dictionary) -> void:
	for gpEntry in gpEntries:
		if gpEntry == null:
			continue
		if gpEntry is Dictionary:
			var gpSub: Dictionary = gpEntry as Dictionary
			_gpCollectMenuEntries(gpSub.get("items", []) as Array, gpOut)
			continue
		if not (gpEntry is Array):
			continue
		var gpPair: Array = gpEntry as Array
		if gpPair.size() >= 2:
			gpOut[str(gpPair[1])] = true


# Every action id the quick command bar can emit (its nested export submenu included — those are
# real menu ids too and were part of the original nine).
# 快捷命令条能发出的每个动作 id（含嵌套的导出子菜单 —— 它们也是真菜单 id，且属最初那九个的一部分）。
func _gpQuickActions() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpEntry in GPPIDQuickToolbar.GP_ITEMS:
		if gpEntry == null:
			continue
		var gpSpec: Dictionary = gpEntry as Dictionary
		# A container button (one with a nested "menu") does not dispatch an action itself: it
		# OPENS a submenu. Requiring a gpOnMenu branch for it would demand dead code forever.
		# 带嵌套 "menu" 的容器按钮本身不分发动作：它**打开子菜单**。要求它有 gpOnMenu 分支
		# 等于永远索要一段死代码。
		if gpSpec.has("action") and not gpSpec.has("menu"):
			gpOut[str(gpSpec["action"])] = true
		# Nested submenu rows: either [label_key, action] pairs or nulls.
		# 嵌套子菜单行：或为 [label_key, action] 对，或为 null。
		for gpRow in (gpSpec.get("menu", []) as Array):
			if gpRow == null:
				continue
			var gpPair: Array = gpRow as Array
			if gpPair.size() >= 2:
				gpOut[str(gpPair[1])] = true
	return gpOut


# THE GATE: no clickable action may fall through to the "feature pending" default.
# 门禁本体：任何可点击的动作都不得落到「功能待接入」的默认分支。
func gpTestNoDeadMenuActions() -> void:
	var gpHandled: Dictionary = _gpHandledActions()
	var gpWanted: Dictionary = _gpMenuActions()
	for gpKey in _gpQuickActions().keys():
		gpWanted[gpKey] = true
	var gpDead: Array[String] = []
	for gpAction in gpWanted.keys():
		if gpHandled.has(gpAction):
			continue
		if GP_DEAD_WHITELIST.has(str(gpAction)):
			continue
		gpDead.append(str(gpAction))
	gpDead.sort()
	gpEq(gpDead.size(), 0, "死菜单为零（未处理动作：%s）/ no dead menu actions left: %s" % [gpDead, gpDead])


# The whitelist itself must stay empty — it is an escape hatch, not a parking lot.
# 白名单本身必须为空 —— 它是应急口，不是停车场。
func gpTestDeadWhitelistIsEmpty() -> void:
	gpEq(GP_DEAD_WHITELIST.size(), 0, "死菜单白名单为空 / the dead-action whitelist is empty")


# A sanity probe on the reader itself: a bogus action must NOT be reported as handled, or the gate
# above would pass by accident (a reader that returns "everything" also returns "nothing is dead").
# 对读取器本身的健全性探针：一个不存在动作**不得**被判为已处理，否则上面的门禁会侥幸通过
#（一个「什么都说已处理」的读取器同样会说「没有死菜单」）。
func gpTestReaderDoesNotOverReport() -> void:
	var gpHandled: Dictionary = _gpHandledActions()
	gpCheck(gpHandled.has("file_save"), "读取器找得到真实分支 / the reader sees a real branch")
	gpCheck(not gpHandled.has("totally_made_up_action"),
		"读取器不认识假动作 / the reader does not invent labels")


# The AI unit-operation entry is intentionally absent until stage C: a menu item whose only
# possible answer is "not available yet" is the pattern this stage removes.
# AI 单元操作条目在阶段 C 之前刻意缺席：一个只能回答「暂不可用」的菜单项，正是本阶段要清除的模式。
func gpTestAiUnitOpNotAdvertised() -> void:
	var gpActions: Dictionary = _gpMenuActions()
	gpCheck(not gpActions.has("tool_ai_unitop"),
		"AI 单元操作不在菜单里 / the AI unit-op entry is not in the menu")
