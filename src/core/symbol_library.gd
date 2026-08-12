class_name SymbolLibrary
extends RefCounted

# Symbol library: returns the default set of symbol definitions.
# 符号库：返回默认的符号定义集合。
# The renderer matches by category / id; later this can load from res://assets/symbols/
# or project.pid.json. We ship a minimal built-in set so the app starts with no assets.
# 渲染层按 category / id 匹配绘制；日后可改为从 res://assets/symbols/ 或
# project.pid.json 加载。这里先用代码内置一套最小可用集，便于无素材起步。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

static func default_defs() -> Array[SymbolDef]:
	var out: Array[SymbolDef] = []
	out.append(_mk("pump",       "泵",       "pump",       Vector2(80, 56), [{"name": "in", "pos": [-40, 0]}, {"name": "out", "pos": [40, 0]}]))
	out.append(_mk("tank",       "储罐",     "tank",       Vector2(80, 80), [{"name": "in", "pos": [0, -40]}, {"name": "out", "pos": [0, 40]}]))
	out.append(_mk("valve",      "阀门",     "valve",      Vector2(48, 48), [{"name": "in", "pos": [-24, 0]}, {"name": "out", "pos": [24, 0]}]))
	out.append(_mk("instrument", "仪表",     "instrument", Vector2(56, 56), [{"name": "in", "pos": [-28, 0]}]))
	out.append(_mk("heatex",     "换热器",   "heat",       Vector2(84, 64), [{"name": "in", "pos": [-42, 0]}, {"name": "out", "pos": [42, 0]}]))
	return out


static func _mk(id: String, name: String, cat: String, size: Vector2, ports: Array[Dictionary]) -> SymbolDef:
	var d: SymbolDef = SymbolDef.new()
	d.id = id
	d.display_name = name
	d.category = cat
	d.default_size = size
	d.ports = ports
	return d

# TODO: discover_packs() — scan built-in / project / user symbol_packs dirs (Dev Guide §4.2.2).
# TODO：discover_packs() —— 扫描内置/项目/用户三处 symbol_packs 目录（见开发指南 §4.2.2）。
