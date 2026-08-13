class_name GPSymbolDef
extends Resource

# Symbol definition: data-driven, avoids creating one class per symbol.
# 图元定义：数据驱动，避免为每个符号建一个类。
# The symbol library is just an array of SymbolDef; the renderer matches by category + id.
# 符号库用 SymbolDef 数组即可；渲染层按 category + id 匹配绘制。

# Symbol category enum (see Dev Guide §4.2.1). The running prototype currently stores
# category as a plain String for simplicity; migrate to this enum as the model matures.
# 图元分类枚举（见开发指南 §4.2.1）。运行原型为简便暂用 String 存放 category，
# 待模型成熟后迁移到本枚举。
enum GPSymbolCategory { GP_EQUIPMENT, GP_VALVE, GP_PIPE, GP_FITTING, GP_INSULATION, GP_INSTRUMENT, GP_INSTRUMENT_SIGNAL, GP_ELECTRICAL, GP_ANNOTATION }

@export var gpId: String = ""
@export var gpDisplayName: String = ""
# Category bucket: general / valve / tank / pump / instrument ...
# 分类桶：general（通用）/ valve（阀门）/ tank（储罐）/ pump（泵）/ instrument（仪表）...
@export var gpCategory: String = "general"
# Path to an SVG/PNG icon, e.g. res://assets/symbols/xxx.svg
# 图标路径，如 res://assets/symbols/xxx.svg
@export var gpIconPath: String = ""
@export var gpDefaultSize: Vector2 = Vector2(64, 64)
# Port list: [{"name":"in","pos":[-32,0]},{"name":"out","pos":[32,0]}]
# 端口列表：[{"name":"in","pos":[-32,0]},{"name":"out","pos":[32,0]}]
@export var gpPorts: Array[Dictionary] = []
# Attribute template the user can fill in.
# 用户可填写的属性模板。
@export var gpAttrsSchema: Dictionary = {}


func gpToDict() -> Dictionary:
	return {
		"id": gpId,
		"display_name": gpDisplayName,
		"category": gpCategory,
		"icon_path": gpIconPath,
		"default_size": [gpDefaultSize.x, gpDefaultSize.y],
		"ports": gpPorts.duplicate(),
		"attrs_schema": gpAttrsSchema.duplicate(),
	}
