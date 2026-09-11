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

# Attribute template the user can fill in (LEGACY, untyped). Kept for round-tripping old
# symbol packs; new code uses gpSchema below.
# 用户可填写的属性模板（历史遗留，无类型）。保留以兼容旧图元包往返；新代码用下方的 gpSchema。
@export var gpAttrsSchema: Dictionary = {}

# Typed property schema (M8). Field DEFINITIONS live here, in the TYPE layer, so editing the
# library propagates to every instance in every project — instances only store values.
# 类型化属性 schema（M8）。字段**定义**位于此处（类型层），故改库会传播到所有项目的所有实例
# —— 实例只存值。
@export var gpSchema: GPPropertySchema = null

# Tag prefix used by automatic numbering, e.g. "P" for pumps, "XV" for on/off valves.
# Overridable per project by the numbering rule panel (M9b).
# 自动编号所用的位号前缀，如泵的 "P"、开关阀的 "XV"。可由编号规则面板按项目覆盖（M9b）。
@export var gpTagPrefix: String = ""

# Canvas label template. DEFAULT SHOWS THE TAG ONLY — the library display name belongs to the
# inspector, never to the drawing. Supported tokens: {tag} and {name}.
# 画布标签模板。**默认只显示位号** —— 库的显示名属于属性面板，绝不属于图纸。
# 支持的占位符：{tag} 与 {name}。
@export var gpLabelFormat: String = GPPropertyResolver.GP_DEFAULT_LABEL_FORMAT

# Default label anchor for every instance of this symbol (GPLabelAnchor.GP_*).
# 本图元所有实例的默认标签锚点（GPLabelAnchor.GP_*）。
@export var gpLabelAnchor: int = GPLabelAnchor.GPAnchor.GP_BELOW

# Default label offset, NORMALISED (1.0 = half the envelope).
# 默认标签偏移，归一化（1.0 = 半个包络）。
@export var gpLabelOffset: Vector2 = Vector2.ZERO

# Built-in flag (decision D3): ISO library symbols are read-only; editing one derives a
# C-rule copy (C<CATEGORY><nnn>) instead of overwriting the original. User-authored
# symbols are not built-in.
# 内置标志（决策 D3）：ISO 库图元只读；编辑时派生 C 规则副本（C<类别码><三位序号>）
# 而非覆盖原图元。用户自建图元非内置。
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


# Look up a port by name. Returns null when there is no such port.
# 按名称查找端口；不存在时返回 null。
# INVARIANT: gpName is the "port_id" stored in GPPIDEdge.gpFromRef / gpToRef, and names must
# be unique within one definition — see gpPortNamesUnique(). The edge's port_id is a HINT,
# not a contract: GPPortResolver degrades gracefully when a name is missing or renamed, so
# editing a symbol's ports degrades a pipe's look instead of silently breaking the connection.
# 不变式：gpName 就是 GPPIDEdge.gpFromRef / gpToRef 里的 "port_id"，且同一定义内名称必须唯一
# —— 见 gpPortNamesUnique()。边上的 port_id 是「提示」而非「契约」：名称缺失或被改名时
# GPPortResolver 会优雅降级，故编辑图元端口只让管线外观降级，而不会静默断掉连接。
func gpPortByName(gpNameIn: String) -> GPPort:
	for gpP in gpPorts:
		if gpP.gpName == gpNameIn:
			return gpP
	return null


# Every port of the given purpose, in declaration order.
# 指定用途的全部端口，按声明顺序。
# [param gpTypeIn] one of GPPort.GP_NOZZLE / GP_ACTUATOR / GP_SIGNAL / GP_TERMINAL.
# [param gpTypeIn] 取 GPPort.GP_NOZZLE / GP_ACTUATOR / GP_SIGNAL / GP_TERMINAL 之一。
func gpPortsOfType(gpTypeIn: String) -> Array[GPPort]:
	var gpOut: Array[GPPort] = []
	for gpP in gpPorts:
		if gpP.gpType == gpTypeIn:
			gpOut.append(gpP)
	return gpOut


# Whether every port name is unique — the invariant that lets port_id be a plain name.
# 端口名是否全部唯一 —— 该不变式使 port_id 可以就是一个名字。
func gpPortNamesUnique() -> bool:
	var gpSeen: Dictionary = {}
	for gpP in gpPorts:
		if gpSeen.has(gpP.gpName):
			return false
		gpSeen[gpP.gpName] = true
	return true


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
	var gpOut: Dictionary = {
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
	if gpSchema != null:
		gpOut["schema"] = gpSchema.gpToDict()
	gpOut["tag_prefix"] = gpTagPrefix
	gpOut["label_format"] = gpLabelFormat
	gpOut["label_anchor"] = gpLabelAnchor
	gpOut["label_offset"] = [gpLabelOffset.x, gpLabelOffset.y]
	return gpOut


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

	# Typed schema (M8). Absent in every pre-M8 pack, hence the null default — this is the
	# "read new fields with .get(key, default)" rule that keeps old archives loadable.
	# 类型化 schema（M8）。M8 之前的图元包都没有，故默认 null —— 这正是
	# 「新增字段一律 .get(key, default) 读取」规则，保证旧存档仍可载入。
	gpSchema = null
	var gpSchemaIn: Variant = gpD.get("schema", null)
	if gpSchemaIn is Dictionary:
		var gpSc: GPPropertySchema = GPPropertySchema.new()
		gpSc.gpFromDict(gpSchemaIn as Dictionary)
		gpSchema = gpSc

	gpTagPrefix = gpD.get("tag_prefix", "")
	gpLabelFormat = gpD.get("label_format", GPPropertyResolver.GP_DEFAULT_LABEL_FORMAT)
	gpLabelAnchor = int(gpD.get("label_anchor", GPLabelAnchor.GPAnchor.GP_BELOW))
	var gpOff: Array = gpD.get("label_offset", [])
	if gpOff.size() >= 2:
		gpLabelOffset = Vector2(float(gpOff[0]), float(gpOff[1]))
	else:
		gpLabelOffset = Vector2.ZERO
