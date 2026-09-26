extends "res://tests/gp_test.gd"
# Guards the i18n keys that reach the UI through STATIC SPEC TABLES rather than literal
# gpTr("...") call sites. gpTr() falls back to the RAW KEY TEXT when a key is missing, so a
# stale id never raises an error — it silently prints "ribbon.grp_draw" on a button.
#
# Why a literal scan cannot cover this: these tables feed keys in as VARIABLES
# (gpTr(gpCat), gpTr(str(gpItem["key"]))), so the only checkable place is the DATA SOURCE.
# History: the tool-block header kept the id "ribbon.grp_draw" after GPPIDRibbon was removed
# in 2026-09-26; the key was deleted with the component but the reference was not, and every
# gate stayed green because no test reads UI text.
#
# 校验经**静态定义表**（而非字面量 gpTr("...") 调用点）进入界面的 i18n 键。
# gpTr() 在键缺失时回退为**裸键名**，故过时 id 从不报错 —— 它只会把
# "ribbon.grp_draw" 静默显示到按钮上。
# 为什么字面量扫描覆盖不到：这些表把键作为**变量**传入（gpTr(gpCat)、gpTr(str(gpItem["key"]))），
# 因此唯一可校验之处是**数据源本身**。
# 历史：2026-09-26 移除 GPPIDRibbon 后，工具块标题仍保留 id "ribbon.grp_draw" ——
# 键随组件被删而引用未删；由于没有测试读取界面文案，所有门禁照绿。

# Key prefixes belonging to components that no longer exist. A key must never be named after
# a dead component: gpTr()'s silent fallback turns such an id into user-visible raw text.
# 已移除组件的键前缀。键绝不可以按死组件命名：gpTr() 的静默回退会把这种 id 变成用户可见的裸文本。
const GP_DEAD_DOMAINS: Array[String] = ["ribbon."]


# Tool block headers + their items (left symbol dock).
# 工具块标题及其条目（左侧图元库）。
func gpTestToolBlockKeysBilingual() -> void:
	for gpBlock in GPPIDToolbar.GP_TOOL_BLOCKS:
		var gpB: Dictionary = gpBlock as Dictionary
		_gpAssertKey(str(gpB.get("title_key", "")), "toolbar block title")
		for gpItem in gpB.get("items", []):
			var gpI: Dictionary = gpItem as Dictionary
			_gpAssertKey(str(gpI.get("key", "")), "toolbar item")


# Quick command bar items + their nested submenu rows (entries may be null = separator).
# 顶部快捷命令条条目及其嵌套子菜单行（元素可能为 null = 分隔符）。
func gpTestQuickBarKeysBilingual() -> void:
	for gpEntry in GPPIDQuickToolbar.GP_ITEMS:
		if gpEntry == null:
			continue
		var gpE: Dictionary = gpEntry as Dictionary
		_gpAssertKey(str(gpE.get("key", "")), "quick bar item")
		var gpMenu: Array = gpE.get("menu", []) as Array
		for gpRow in gpMenu:
			if gpRow == null:
				continue
			var gpR: Array = gpRow as Array
			if gpR.is_empty():
				continue
			_gpAssertKey(str(gpR[0]), "quick bar submenu")


# Label anchor dropdown rows in the inspector.
# 属性面板中的标签锚点下拉选项。
func gpTestAnchorRowKeysBilingual() -> void:
	for gpRow in GPInspector.gpAnchorRows():
		var gpR: Dictionary = gpRow as Dictionary
		_gpAssertKey(str(gpR.get("key", "")), "anchor row")


# One key must be present in GP_STRINGS with non-empty zh AND en, and must not live in a
# dead component's naming domain. Failures name the key so the fix is a one-line edit.
# 单个键必须存在于 GP_STRINGS 且 zh 与 en 均非空，且不得位于死组件的命名域。
# 失败信息直接给出键名，使修复是一次单行编辑。
func _gpAssertKey(gpKey: String, gpWhere: String) -> void:
	gpCheck(gpKey != "", "non-empty i18n key in " + gpWhere)
	for gpDomain in GP_DEAD_DOMAINS:
		gpCheck(not gpKey.begins_with(gpDomain),
			"i18n key must not use a removed component's domain: " + gpKey)
	var gpMap: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
	gpCheck(not gpMap.is_empty(), "i18n key present in GP_STRINGS (" + gpWhere + "): " + gpKey)
	gpCheck(str(gpMap.get("zh", "")) != "", "zh non-empty for " + gpKey)
	gpCheck(str(gpMap.get("en", "")) != "", "en non-empty for " + gpKey)
