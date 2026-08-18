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

# Unique symbol id, e.g. "pump".
# 唯一图元 id，如 "pump"。
@export var gpId: String = ""

# Human-readable display name, e.g. "泵".
# 人类可读的显示名，如 "泵"。
@export var gpDisplayName: String = ""

# Category bucket: general / valve / tank / pump / instrument ...
# 分类桶：general（通用）/ valve（阀门）/ tank（储罐）/ pump（泵）/ instrument（仪表）...
@export var gpCategory: String = "general"

# Path to an SVG/PNG icon, e.g. res://assets/symbols/xxx.svg
# 图标路径，如 res://assets/symbols/xxx.svg
@export var gpIconPath: String = ""

# Default size on canvas, in pixels.
# 画布上的默认尺寸，以像素为单位。
@export var gpDefaultSize: Vector2 = Vector2(64, 64)

# Port list: [{"name":"in","pos":[-32,0]},{"name":"out","pos":[32,0]}]
# 端口列表：[{"name":"in","pos":[-32,0]},{"name":"out","pos":[32,0]}]
@export var gpPorts: Array[Dictionary] = []

# Attribute template the user can fill in.
# 用户可填写的属性模板。
@export var gpAttrsSchema: Dictionary = {}

# Vector shape spec for native rendering; empty means "draw the default rectangle fallback".
# 矢量形状规格用于原生渲染；为空表示「绘制默认矩形兜底」。
# Coordinates are NORMALIZED PER AXIS into a 0..100 box: x = svgX / width * 100,
# y = svgY / height * 100 (see tools/gen_openpid_defs.py). GPSymbolView._gpDrawShape then
# scales each axis independently by gpDefaultSize/100 and centers on the node, so the symbol
# keeps its native aspect ratio and its ports line up with the drawn endpoints.
# 坐标按轴归一化到 0..100：x = svgX / width * 100、y = svgY / height * 100（见 tools/gen_openpid_defs.py）。
# GPSymbolView._gpDrawShape 随后按 gpDefaultSize/100 对各轴独立缩放并以节点居中，使图元保持原生比例、
# 且端口与绘制端点精确对齐。
# Keys: paths[{pts:[[x,y]...], closed:bool}], circles[{c:[cx,cy], r}], rects[{pos:[x,y], size:[w,h]}].
# 键：paths[{pts:[[x,y]...], closed:bool}]、circles[{c:[cx,cy], r}]、rects[{pos:[x,y], size:[w,h]}]。
@export var gpShape: Dictionary = {}


# Serialize this symbol definition to a dictionary.
# 将本图元定义序列化为字典。
func gpToDict() -> Dictionary:
	return {
		"id": gpId,
		"display_name": gpDisplayName,
		"category": gpCategory,
		"icon_path": gpIconPath,
		"default_size": [gpDefaultSize.x, gpDefaultSize.y],
		"ports": gpPorts.duplicate(),
		"attrs_schema": gpAttrsSchema.duplicate(),
		"shape": gpShape.duplicate(),
	}


# Rebuild this symbol definition from a dictionary (inverse of gpToDict).
# 从字典重建本图元定义（gpToDict 的逆操作）。
func gpFromDict(gpD: Dictionary) -> void:
	gpId = gpD.get("id", "")
	gpDisplayName = gpD.get("display_name", "")
	gpCategory = gpD.get("category", "general")
	gpIconPath = gpD.get("icon_path", "")
	var gpSz: Array = gpD.get("default_size", [64.0, 64.0])
	gpDefaultSize = Vector2(float(gpSz[0]), float(gpSz[1]))
	gpPorts = gpD.get("ports", [])
	gpAttrsSchema = gpD.get("attrs_schema", {})
	gpShape = gpD.get("shape", {})
