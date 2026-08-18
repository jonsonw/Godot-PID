class_name GPSymbolLibrary
extends RefCounted

# Symbol library: returns the default set of symbol definitions.
# 符号库：返回默认的符号定义集合。
# The renderer matches by category / id; later this can load from res://assets/symbols/
# or project.pid.json. We ship a minimal built-in set so the app starts with no assets.
# 渲染层按 category / id 匹配绘制；日后可改为从 res://assets/symbols/ 或
# project.pid.json 加载。这里先用代码内置一套最小可用集，便于无素材起步。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Return the default built-in symbol definitions.
# 返回默认内置图元定义。
static func gpDefaultDefs() -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	gpOut.append(_gpMk("pump",       "泵",       "pump",       Vector2(80, 56), [{"name": "in", "pos": [-40, 0]}, {"name": "out", "pos": [40, 0]}]))
	gpOut.append(_gpMk("tank",       "储罐",     "tank",       Vector2(80, 80), [{"name": "in", "pos": [0, -40]}, {"name": "out", "pos": [0, 40]}]))
	gpOut.append(_gpMk("valve",      "阀门",     "valve",      Vector2(48, 48), [{"name": "in", "pos": [-24, 0]}, {"name": "out", "pos": [24, 0]}]))
	gpOut.append(_gpMk("instrument", "仪表",     "instrument", Vector2(56, 56), [{"name": "in", "pos": [-28, 0]}]))
	gpOut.append(_gpMk("heatex",     "换热器",   "heat",       Vector2(84, 64), [{"name": "in", "pos": [-42, 0]}, {"name": "out", "pos": [42, 0]}]))
	return gpOut


# Helper: create one SymbolDef from raw parameters.
# 辅助函数：用原始参数构造一个 SymbolDef。
static func _gpMk(gpId: String, gpName: String, gpCat: String, gpSize: Vector2, gpPorts: Array[Dictionary]) -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = gpId
	gpD.gpDisplayName = gpName
	gpD.gpCategory = gpCat
	gpD.gpDefaultSize = gpSize
	gpD.gpPorts = gpPorts
	return gpD


# Group the default defs by category. The left palette injects one collapsible
# section per category from this map.
# 按类目分组默认图元。左栏据此为每个类目注入一个可折叠分组。
static func list_by_category() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpD in gpDefaultDefs():
		if not gpOut.has(gpD.gpCategory):
			gpOut[gpD.gpCategory] = []
		gpOut[gpD.gpCategory].append(gpD)
	return gpOut


# Fuzzy match by display name / id / category (case-insensitive substring).
# 按显示名 / id / 类目做不区分大小写的子串匹配。
static func search(gpQ: String) -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	var gpNeedle: String = gpQ.strip_edges().to_lower()
	if gpNeedle == "":
		return gpDefaultDefs()
	for gpD in gpDefaultDefs():
		var gpHay: String = "%s %s %s" % [gpD.gpDisplayName, gpD.gpId, gpD.gpCategory]
		if gpHay.to_lower().contains(gpNeedle):
			gpOut.append(gpD)
	return gpOut


# TODO: discover_packs() — scan built-in / project / user symbol_packs dirs (Dev Guide §4.2.2).
# TODO：discover_packs() —— 扫描内置/项目/用户三处 symbol_packs 目录（见开发指南 §4.2.2）。
