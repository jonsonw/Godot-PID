extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# UI reachability: every tool button the toolbar DECLARES must be reachable — the mode it names
# must exist, its icon must be on disk, and its label must be localized. A5 was exactly this
# class of defect: the arc mode and its drawing logic were complete, but no button existed, so
# the feature was unreachable from the product.
# 界面可达性：工具条**声明**的每个按钮都必须可达 —— 它点名的模式存在、图标在盘上、标签已本地化。
# A5 正是这一类缺陷：圆弧模式与绘制逻辑都完整，却没有按钮，于是该功能在产品里不可达。
#
# This suite is deliberately data-driven (it walks GP_TOOL_BLOCKS) so a tool added later without
# its icon / key / mode fails HERE instead of silently rendering an empty square.
# 本套件刻意**数据驱动**（遍历 GP_TOOL_BLOCKS），使日后新增工具若缺图标 / 词条 / 模式，
# 会在此处失败，而不是静默渲染成一个空方块。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Every draw-tool item id the toolbar block must carry (the block is the single source of truth
# for the canvas tool row).
# 工具块必须携带的绘图工具 action 全集（该块是画布工具行的唯一事实来源）。
const GP_EXPECTED_TOOLS: Array[String] = [
	"select", "connect", "line", "circle", "rect", "polyline", "arc", "pipe", "signal",
]


# Flatten the tool block's items into an action -> item dictionary.
# 把工具块条目摊平成 action → item 字典。
func _gpToolItems() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpBlock in GPPIDToolbar.GP_TOOL_BLOCKS:
		var gpB: Dictionary = gpBlock as Dictionary
		for gpItem in gpB.get("items", []):
			var gpI: Dictionary = gpItem as Dictionary
			gpOut[str(gpI.get("action", ""))] = gpI
	return gpOut


# Every expected tool is present exactly once, and nothing extra is silently added.
# 每个预期工具都在场，且没有多余条目被悄悄加进来。
func gpTestToolBlockCarriesEveryTool() -> void:
	var gpItems: Dictionary = _gpToolItems()
	for gpAction in GP_EXPECTED_TOOLS:
		gpCheck(gpItems.has(gpAction), "工具条含动作 / toolbar carries action: " + gpAction)
	gpEq(gpItems.size(), GP_EXPECTED_TOOLS.size(),
		"工具条条目数与预期一致 / item count matches the expected set")


# The ARC button (A5): present, pointing at the arc drawing mode, with a real icon and labels.
# 圆弧按钮（A5）：在场、指向圆弧绘制模式，且图标与标签都真实存在。
func gpTestArcToolIsReachable() -> void:
	var gpItems: Dictionary = _gpToolItems()
	gpCheck(gpItems.has("arc"), "工具条有圆弧按钮 / the toolbar has an arc button")
	var gpArc: Dictionary = gpItems.get("arc", {}) as Dictionary
	gpEq(int(gpArc.get("mode", -1)), GPCanvas2D.GPMode.GP_DRAW_ARC,
		"圆弧按钮指向 GP_DRAW_ARC / the arc button names the arc mode")
	gpCheck(bool(gpArc.get("toggle", false)), "圆弧按钮是切换态 / the arc button is a toggle")
	var gpKey: String = str(gpArc.get("key", ""))
	var gpPair: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
	gpCheck(not gpPair.is_empty(), "圆弧词条存在 / arc key present: " + gpKey)
	gpCheck(str(gpPair.get("en", "")) != "", "圆弧词条有英文 / arc key has en")


# Every tool's icon file exists. A missing icon renders as an empty square (no error), which is
# why this must be an assertion and not a hope.
# 每个工具的图标文件都存在。缺图标只会渲染成空方块（不报错），故这必须是断言而非指望。
func gpTestEveryToolIconExists() -> void:
	var gpItems: Dictionary = _gpToolItems()
	for gpAction in gpItems.keys():
		var gpItem: Dictionary = gpItems[gpAction] as Dictionary
		var gpIcon: String = str(gpItem.get("icon", ""))
		gpCheck(gpIcon != "", "图标名非空 / icon name present: " + str(gpAction))
		var gpPath: String = "res://assets/icons/%s.svg" % gpIcon
		gpCheck(FileAccess.file_exists(gpPath), "图标文件存在 / icon file exists: " + gpPath)


# Every tool label is localized in both languages.
# 每个工具标签在中英两种语言下都存在。
func gpTestEveryToolKeyBilingual() -> void:
	var gpItems: Dictionary = _gpToolItems()
	for gpAction in gpItems.keys():
		var gpItem: Dictionary = gpItems[gpAction] as Dictionary
		var gpKey: String = str(gpItem.get("key", ""))
		var gpPair: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
		gpCheck(not gpPair.is_empty(), "工具词条存在 / tool key present: " + gpKey)
		gpCheck(str(gpPair.get("zh", "")) != "", "工具词条有中文 / tool key has zh: " + gpKey)
		gpCheck(str(gpPair.get("en", "")) != "", "工具词条有英文 / tool key has en: " + gpKey)


# The arc status key exists too — the mode switch announces itself through it.
# 圆弧状态词条也必须存在 —— 模式切换经它宣告自己。
func gpTestArcStatusKeyPresent() -> void:
	var gpPair: Dictionary = I18n.GP_STRINGS.get("status.mode_arc", {})
	gpCheck(not gpPair.is_empty(), "status.mode_arc 存在 / arc status key present")
	gpCheck(str(gpPair.get("en", "")) != "", "status.mode_arc 有英文 / arc status key has en")
