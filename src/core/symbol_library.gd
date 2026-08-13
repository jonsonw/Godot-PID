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

static func gpDefaultDefs() -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	gpOut.append(_gpMk("pump",       "泵",       "pump",       Vector2(80, 56), [{"name": "in", "pos": [-40, 0]}, {"name": "out", "pos": [40, 0]}]))
	gpOut.append(_gpMk("tank",       "储罐",     "tank",       Vector2(80, 80), [{"name": "in", "pos": [0, -40]}, {"name": "out", "pos": [0, 40]}]))
	gpOut.append(_gpMk("valve",      "阀门",     "valve",      Vector2(48, 48), [{"name": "in", "pos": [-24, 0]}, {"name": "out", "pos": [24, 0]}]))
	gpOut.append(_gpMk("instrument", "仪表",     "instrument", Vector2(56, 56), [{"name": "in", "pos": [-28, 0]}]))
	gpOut.append(_gpMk("heatex",     "换热器",   "heat",       Vector2(84, 64), [{"name": "in", "pos": [-42, 0]}, {"name": "out", "pos": [42, 0]}]))
	return gpOut


static func _gpMk(gpId: String, gpName: String, gpCat: String, gpSize: Vector2, gpPorts: Array[Dictionary]) -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = gpId
	gpD.gpDisplayName = gpName
	gpD.gpCategory = gpCat
	gpD.gpDefaultSize = gpSize
	gpD.gpPorts = gpPorts
	return gpD

# TODO: discover_packs() — scan built-in / project / user symbol_packs dirs (Dev Guide §4.2.2).
# TODO：discover_packs() —— 扫描内置/项目/用户三处 symbol_packs 目录（见开发指南 §4.2.2）。
