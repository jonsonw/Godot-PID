class_name GPLabelSlot
extends Resource

# Copyright © 2026 Jonson Wang
# ONE text slot of a symbol definition — the upgrade that turns a symbol's SINGLE canvas label
# into N independent pieces of text, each with its own anchor / tier / value mapping.
# 图元定义的**一个**文本槽 —— 把图元**单个**画布标签升级为 N 段互相独立的文本，
# 每段自带锚点 / 字高档 / 取值映射。
#
# Why this exists / 为何存在：
# A nozzle must show TWO lines (its number above, its DN below) and a valve actuator must show
# its fail action (F.C. / F.O.). Those are not one string with a newline — they sit on opposite
# sides of the symbol and are filled from different properties. The reference drawing already
# lists them as two independent annotation groups (nozzlestandardlabel / failactionlabel), so
# this is completing a measured standard rather than inventing a mechanism (see 规划 §13/§14).
# 管口必须显示**两行**（上=编号、下=DN），阀门执行机构必须显示故障位（F.C. / F.O.）。
# 它们不是「带换行的同一个字符串」—— 它们分居图元两侧、且取自不同属性。参照图本就把它们
# 列为两个独立标注组（nozzlestandardlabel / failactionlabel），故这是补全已实测的标准，
# 而不是发明机制（见规划 §13/§14）。
#
# BACKWARD COMPATIBILITY IS THE LOAD-BEARING PROPERTY: when a definition's gpLabelSlots is EMPTY
# the renderer takes the original single-label path, so every existing symbol pack and every
# existing archive behaves exactly as before.
# **向后兼容是承重属性**：当定义的 gpLabelSlots 为**空**时，渲染器走原单标签分支，
# 故所有既有图元包与既有存档的行为完全不变。

# Text tiers, mapping onto GPTextRole's canvas tiers (never invent a new size — 规划 §13).
# 字高档，对应 GPTextRole 的画布档位（绝不新增字号 —— 规划 §13）。
const GP_TIER_EQUIPMENT: String = "equipment"   # 设备名档（图面 4.5mm） / equipment tier (4.5mm)
const GP_TIER_INLINE: String = "inline"         # 在管档（图面 3.0mm） / in-line tier (3.0mm)

# Slot name, unique within one definition, e.g. "nozzle_no" / "dn" / "fail_action".
# 槽名，同一定义内唯一，如 "nozzle_no" / "dn" / "fail_action"。
var gpKey: String = ""

# Value template. Supports {tag} / {name} / {prop:<key>} — resolved by GPPropertyResolver, the
# same language the single-label gpLabelFormat already uses.
# 取值模板。支持 {tag} / {name} / {prop:<key>} —— 由 GPPropertyResolver 解析，
# 与既有单标签 gpLabelFormat 用的是同一套语言。
var gpFormat: String = "{tag}"

# GPPropertyResolver.GP_DEFAULT_LABEL_FORMAT equivalent for a slot with no explicit format.
# 槽未显式给出格式时的等价值（与 GPPropertyResolver.GP_DEFAULT_LABEL_FORMAT 一致）。
const GP_DEFAULT_SLOT_FORMAT: String = "{tag}"

# Anchor for this slot (GPLabelAnchor.GP_*). Reuses the existing enum + clamping rules, so a
# slot can dodge a crowded nozzle but can never wander onto the neighbour's equipment.
# 本槽的锚点（GPLabelAnchor.GP_*）。复用既有枚举与夹取规则，故槽可避开密集管口，
# 但绝不会漂到隔壁设备上被误读。
var gpAnchor: int = GPLabelAnchor.GPAnchor.GP_BELOW

# Default offset, NORMALISED (1.0 = half the envelope) — never pixels, or it drifts on zoom.
# 默认偏移，**归一化**（1.0 = 半个包络）—— 绝不是像素，否则缩放时会漂移。
var gpOffset: Vector2 = Vector2.ZERO

# Text tier: GP_TIER_EQUIPMENT / GP_TIER_INLINE.
# 字高档：GP_TIER_EQUIPMENT / GP_TIER_INLINE。
var gpTier: String = GP_TIER_INLINE

# Display short-code map, e.g. {"FC 故障关": "F.C."} — the canvas shows the short code while the
# inspector keeps showing the full value, so the VALUE itself is never rewritten (规划 §14).
# 显示短码表，如 {"FC 故障关": "F.C."} —— 画布显示短码，属性面板仍显示全称，
# 故**取值本身**从不被改写（规划 §14）。
var gpShortMap: Dictionary = {}

# Optional visibility guard: show this slot only when this property condition holds, e.g.
# "fail_action != 不适用". "" = always visible.
# 可选可见性护栏：仅当该属性条件成立时才显示本槽，如 "fail_action != 不适用"。"" = 始终显示。
var gpVisibleWhen: String = ""


# Build a slot from its parts.
# 由各分量构造文本槽。
static func gpMake(gpKeyIn: String, gpFormatIn: String, gpAnchorIn: int,
		gpTierIn: String = GP_TIER_INLINE, gpOffsetIn: Vector2 = Vector2.ZERO) -> GPLabelSlot:
	var gpS: GPLabelSlot = GPLabelSlot.new()
	gpS.gpKey = gpKeyIn
	gpS.gpFormat = gpFormatIn
	gpS.gpAnchor = gpAnchorIn
	gpS.gpTier = gpTierIn
	gpS.gpOffset = gpOffsetIn
	return gpS


# Serialize to a dictionary (JSON-friendly). Default-valued keys are omitted so existing packs
# stay byte-stable; an empty slot list never reaches this function (see GPSymbolDef.gpToDict()).
# 序列化为字典（JSON 友好）。取默认值的键省略，使既有图元包保持字节稳定；
# 空槽列表绝不会进到这里（见 GPSymbolDef.gpToDict()）。
func gpToDict() -> Dictionary:
	var gpOut: Dictionary = {
		"key": gpKey,
		"format": gpFormat,
	}
	if gpAnchor != GPLabelAnchor.GPAnchor.GP_BELOW:
		gpOut["anchor"] = gpAnchor
	if gpOffset != Vector2.ZERO:
		gpOut["offset"] = [gpOffset.x, gpOffset.y]
	if gpTier != GP_TIER_INLINE:
		gpOut["tier"] = gpTier
	if not gpShortMap.is_empty():
		gpOut["short_map"] = gpShortMap.duplicate(true)
	if gpVisibleWhen != "":
		gpOut["visible_when"] = gpVisibleWhen
	return gpOut


# Restore from a dictionary (inverse of gpToDict()). Every key via get(key, default).
# 从字典还原（gpToDict() 的逆操作）。每个键均以 get(key, default) 读取。
func gpFromDict(gpD: Dictionary) -> void:
	gpKey = str(gpD.get("key", ""))
	gpFormat = str(gpD.get("format", GP_DEFAULT_SLOT_FORMAT))
	gpAnchor = int(gpD.get("anchor", GPLabelAnchor.GPAnchor.GP_BELOW))
	var gpOff: Array = gpD.get("offset", [])
	if gpOff.size() >= 2:
		gpOffset = Vector2(float(gpOff[0]), float(gpOff[1]))
	else:
		gpOffset = Vector2.ZERO
	gpTier = str(gpD.get("tier", GP_TIER_INLINE))
	var gpMap: Variant = gpD.get("short_map", {})
	gpShortMap = (gpMap as Dictionary).duplicate(true) if gpMap is Dictionary else {}
	gpVisibleWhen = str(gpD.get("visible_when", ""))


# Build an array of label slots from an array of dicts (mirrors GPPortSpec.gpFromDicts()).
# 由字典数组构建文本槽数组（镜像 GPPortSpec.gpFromDicts()）。
static func gpFromDicts(gpArr: Array) -> Array[GPLabelSlot]:
	var gpOut: Array[GPLabelSlot] = []
	for gpD in gpArr:
		if gpD is Dictionary:
			var gpS: GPLabelSlot = GPLabelSlot.new()
			gpS.gpFromDict(gpD as Dictionary)
			gpOut.append(gpS)
	return gpOut


# Serialize an array of label slots back to dicts. Inverse of gpFromDicts().
# 把文本槽数组序列化回字典数组。gpFromDicts() 的逆操作。
static func gpToDicts(gpSlots: Array[GPLabelSlot]) -> Array:
	var gpOut: Array = []
	for gpS in gpSlots:
		gpOut.append(gpS.gpToDict())
	return gpOut
