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

# Vector shape primitives for native rendering, in a 100x100 UNIT BOX.
# 用于原生渲染的矢量形状原语，位于 100x100 单位框内。
# UNIFIED MODEL (P0 refactor): the symbol editor and the main canvas now share this single
# GPShape type, so grip / hit-test / geometry utilities can be reused across both. The
# legacy dict spec (paths/circles/rects/box) is only a derived render spec — see gpShapeSpec().
# 统一模型（P0 重构）：图元编辑器与主画布现共用这一 GPShape 类型，使抓取点 / 命中 /
# 几何工具可在两处复用。历史字典规格（paths/circles/rects/box）仅是派生的渲染规格 —— 见 gpShapeSpec()。
@export var gpShapes: Array[GPShape] = []

# Connection ports, normalized 0..1 against the nominal envelope.
# 连接端口，位置相对标称包络归一化到 0..1。
# (0,0) = envelope top-left, (1,1) = bottom-right; "dir" is the optional outward normal.
# (0,0) = 包络左上角，(1,1) = 右下角；"dir" 为可选的向外法线。
@export var gpPorts: Array[GPPort] = []

# Attribute template the user can fill in.
# 用户可填写的属性模板。
@export var gpAttrsSchema: Dictionary = {}

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


# Convert one port into a local offset (in pixels) relative to the node center.
# 将一个端口换算为相对节点中心的本地偏移（像素）。
# Normalized 0..1 input is folded around the envelope center: (pos - (0.5,0.5)) * gpDefaultSize.
# 归一化 0..1 输入以包络中心折算：(pos - (0.5,0.5)) * gpDefaultSize。
func gpPortLocal(gpPort: GPPort) -> Vector2:
	var gpPos: Vector2 = gpPort.gpPos
	var gpX: float = gpPos.x
	var gpY: float = gpPos.y
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


# Derived render spec: rebuild the legacy {paths,circles,rects,box} dict from gpShapes.
# 派生渲染规格：由 gpShapes 重建历史 {paths,circles,rects,box} 字典。
# Kept so the mature, ISO-compliant painter / normalizer keep working unchanged.
# 保留此规格，使已成熟、符合 ISO 的渲染器 / 归一化器无需改动即可继续工作。
func gpShapeSpec() -> Dictionary:
	return GPShapeSpec.gpBuild(gpShapes)


# Serialize this symbol definition to a dictionary.
# 将本图元定义序列化为字典。
func gpToDict() -> Dictionary:
	var gpShapesOut: Array = []
	for gpS in gpShapes:
		gpShapesOut.append(gpS.gpToDict())
	var gpPortsOut: Array = []
	for gpP in gpPorts:
		gpPortsOut.append(gpP.gpToDict())
	return {
		"id": gpId,
		"display_name": gpDisplayName,
		"category": gpCategory,
		"icon_path": gpIconPath,
		"default_size": [gpDefaultSize.x, gpDefaultSize.y],
		"shapes": gpShapesOut,
		"ports": gpPortsOut,
		"attrs_schema": gpAttrsSchema.duplicate(true),
		"builtin": gpBuiltin,
	}


# Rebuild this symbol definition from a dictionary (inverse of gpToDict).
# 从字典重建本图元定义（gpToDict 的逆操作）。
# Accepts the new "shapes" (Array[GPShape dict]) / "ports" (Array[dict]) form, OR the legacy
# "shape" dict / top-level paths-circles-rects spec, so existing packs still load.
# 接受新格式 "shapes"（GPShape 字典数组）/ "ports"（字典数组），或历史 "shape" 字典 /
# 顶层 paths-circles-rects 规格，从而已生成的图元包仍可加载。
func gpFromDict(gpD: Dictionary) -> void:
	gpId = gpD.get("id", "")
	gpDisplayName = gpD.get("display_name", "")
	gpCategory = gpD.get("category", "general")
	gpIconPath = gpD.get("icon_path", "")
	var gpSz: Array = gpD.get("default_size", [64.0, 64.0])
	gpDefaultSize = Vector2(float(gpSz[0]), float(gpSz[1]))

	# Shapes: new "shapes" array, or legacy "shape" / paths-circles-rects spec.
	# 形状：新格式 "shapes" 数组，或历史 "shape" / paths-circles-rects 规格。
	var gpShapesArr: Array = gpD.get("shapes", [])
	if gpShapesArr is Array and (gpShapesArr as Array).size() > 0:
		gpShapes = GPShapeSpec.gpFromDicts(gpShapesArr as Array)
	elif gpD.has("shape") and (gpD["shape"] is Dictionary):
		gpShapes = GPShapeSpec.gpFromSpec(gpD["shape"] as Dictionary)
	elif gpD.has("paths") or gpD.has("circles") or gpD.has("rects"):
		gpShapes = GPShapeSpec.gpFromSpec({
			"paths": gpD.get("paths", []),
			"circles": gpD.get("circles", []),
			"rects": gpD.get("rects", []),
		})
	else:
		gpShapes = []

	# Ports: new "ports" array of dicts, or legacy "ports" dict array.
	# 端口：新格式 "ports" 字典数组，或历史 "ports" 字典数组。
	gpPorts = GPPortSpec.gpFromDicts(gpD.get("ports", []))

	gpAttrsSchema = gpD.get("attrs_schema", {})
	gpBuiltin = gpD.get("builtin", false)
