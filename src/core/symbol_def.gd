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

# Nominal envelope size on canvas, in pixels — comes from GPSymbolCategories.gpSizeFor().
# 画布上的标称包络尺寸（像素）—— 取自 GPSymbolCategories.gpSizeFor()。
# It is a CATEGORY property, not a per-glyph property, so a family renders at one size.
# 它是「类别」属性而非单个字形属性，因此同族图元以同一尺寸渲染。
@export var gpDefaultSize: Vector2 = Vector2(64, 64)

# Port list with positions NORMALIZED 0..1 against the nominal envelope.
# 端口列表，位置相对标称包络归一化到 0..1。
# (0,0) = envelope top-left, (1,1) = bottom-right; "dir" is the optional outward normal.
# (0,0) = 包络左上角，(1,1) = 右下角；"dir" 为可选的向外法线。
# Example: [{"name":"in","pos":[0.0,0.5],"dir":[-1,0]},{"name":"out","pos":[1.0,0.5],"dir":[1,0]}]
# 示例：[{"name":"in","pos":[0.0,0.5],"dir":[-1,0]},{"name":"out","pos":[1.0,0.5],"dir":[1,0]}]
# Normalized ports keep every family member's ports aligned and survive any resize.
# 归一化端口使同族成员端口天然对齐，且在任意缩放下依然成立。
@export var gpPorts: Array[Dictionary] = []

# Attribute template the user can fill in.
# 用户可填写的属性模板。
@export var gpAttrsSchema: Dictionary = {}

# Vector shape spec for native rendering; empty means "draw the default rectangle fallback".
# 矢量形状规格用于原生渲染；为空表示「绘制默认矩形兜底」。
# Coordinates live in a 100x100 UNIT BOX and are scaled UNIFORMLY (aspect ratio preserved):
# the glyph bbox is fitted into the unit box on its dominant axis and centered, so a wide
# valve and a tall tank both stay undistorted.
# 坐标位于 100x100 单位框内，并按均匀缩放（保留长宽比）：字形包围盒沿主轴塞入单位框并居中，
# 因此扁宽的阀门与瘦高的储罐都不会变形。
# Keys: paths[{pts:[[x,y]...], closed:bool}], circles[{c:[cx,cy], r}],
#       rects[{pos:[x,y], size:[w,h]}], box:[x,y,w,h].
# 键：paths[{pts:[[x,y]...], closed:bool}]、circles[{c:[cx,cy], r}]、
#     rects[{pos:[x,y], size:[w,h]}]、box:[x,y,w,h]。
# "box" is the glyph's own unit-space bbox; GPSymbolPainter derives the uniform scale from it
# (min(rect.w / box.w, rect.h / box.h)) so the glyph touches the envelope on its dominant axis.
# "box" 为字形自身的单位空间包围盒；GPSymbolPainter 据此推导均匀缩放系数
# （min(rect.w / box.w, rect.h / box.h)），使字形沿主轴贴合包络。
@export var gpShape: Dictionary = {}

# Built-in flag (decision D3): ISO library symbols are read-only; the in-place editor derives a
# custom_<id> copy instead of overwriting the original. User-authored symbols are not built-in.
# 内置标志（决策 D3）：ISO 库图元只读；就地编辑器派生 custom_<id> 副本而非覆盖原图元。
# 用户自建图元非内置。
@export var gpBuiltin: bool = false


# Legacy guard: normalized port coordinates never exceed this magnitude.
# 兼容护栏：归一化端口坐标绝不会超过此量级。
# Older packs stored ports as raw pixel offsets (e.g. -35.5); anything beyond the threshold is
# therefore treated as legacy pixel data and used as-is instead of being scaled again.
# 旧图元包以原始像素偏移存储端口（如 -35.5）；超出阈值即视为历史像素数据，直接使用而不再缩放。
const GP_UNIT_PORT_LIMIT: float = 2.0


# Convert one port entry into a local offset (in pixels) relative to the node center.
# 将一个端口条目换算为相对节点中心的本地偏移（像素）。
# Normalized 0..1 input is folded around the envelope center: (pos - (0.5,0.5)) * gpDefaultSize.
# 归一化 0..1 输入以包络中心折算：(pos - (0.5,0.5)) * gpDefaultSize。
func gpPortLocal(gpPort: Dictionary) -> Vector2:
	var gpPos: Array = gpPort.get("pos", [0.5, 0.5])
	var gpX: float = float(gpPos[0])
	var gpY: float = float(gpPos[1])
	if absf(gpX) > GP_UNIT_PORT_LIMIT or absf(gpY) > GP_UNIT_PORT_LIMIT:
		# Legacy pixel offset — already node-centered, pass through unchanged.
		# 历史像素偏移 —— 已是节点中心坐标，原样透传。
		return Vector2(gpX, gpY)
	return (Vector2(gpX, gpY) - Vector2(0.5, 0.5)) * gpDefaultSize


# Convenience: local offsets of every port, in declaration order.
# 便捷方法：按声明顺序返回所有端口的本地偏移。
func gpPortLocals() -> Array[Vector2]:
	var gpOut: Array[Vector2] = []
	for gpP in gpPorts:
		gpOut.append(gpPortLocal(gpP))
	return gpOut


# Serialize this symbol definition to a dictionary.
# 将本图元定义序列化为字典。
func gpToDict() -> Dictionary:
	return {
		"id": gpId,
		"display_name": gpDisplayName,
		"category": gpCategory,
		"icon_path": gpIconPath,
		"default_size": [gpDefaultSize.x, gpDefaultSize.y],
		"ports": gpPorts.duplicate(true),
		"attrs_schema": gpAttrsSchema.duplicate(true),
		"shape": gpShape.duplicate(true),
		"builtin": gpBuiltin,
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
	# Rebuild a strongly typed port array; a raw untyped Array cannot be assigned directly.
	# 重建强类型端口数组；无类型 Array 不能直接赋给 Array[Dictionary]。
	var gpRawPorts: Array = gpD.get("ports", [])
	var gpTypedPorts: Array[Dictionary] = []
	for gpP in gpRawPorts:
		gpTypedPorts.append((gpP as Dictionary).duplicate(true))
	gpPorts = gpTypedPorts
	gpAttrsSchema = gpD.get("attrs_schema", {})
	gpShape = gpD.get("shape", {})
	gpBuiltin = gpD.get("builtin", false)
