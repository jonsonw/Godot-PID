class_name GPPIDNode
extends RefCounted

# One symbol instance on the canvas (not a Resource; serialized via self-managed to_dict).
# 画布上的一个图元实例（非 Resource，序列化走自管 to_dict）。
# See Dev Guide §4.5 and 从零落地架构_分步实施.md Step 1.2.
# 见开发指南 §4.5 与「从零落地架构_分步实施.md」Step 1.2。

# Unique instance id, e.g. "u-1"
# 唯一实例 id，如 "u-1"
var gpInstanceId: String = ""

# SymbolDef id this node instantiates
# 该节点实例化的 SymbolDef id
var gpSymbolId: String = ""

# Process tag / label, e.g. "FV-101". Empty means "render the localized type name".
# 工艺位号 / 标签，如 "FV-101"。为空时显示本地化的类型名。
var gpTag: String = ""

# World position of the node center
# 节点中心的世界坐标
var gpPosition: Vector2 = Vector2.ZERO

# Rotation in degrees
# 旋转角度（度）
var gpRotationDeg: float = 0.0

# Mirror horizontally
# 水平翻转
var gpFlipped: bool = false

# User-set attribute values (diff from SymbolDef defaults)
# 用户设置的属性值（相对 SymbolDef 默认值的差异）
var gpAttrValues: Dictionary = {}


# Serialize this node to a plain dictionary (object graph -> dict graph).
# 将本节点序列化为普通字典（对象图 → 字典图）。
# The shape matches docs/samples/pani_detox.pid.json so JSON stays forward-compatible.
# 该形状与 docs/samples/pani_detox.pid.json 一致，保证 JSON 向前兼容。
func gpToDict() -> Dictionary:
	return {
		"instance_id": gpInstanceId,
		"symbol_id": gpSymbolId,
		"tag": gpTag,
		"position": [gpPosition.x, gpPosition.y],
		"rotation_deg": gpRotationDeg,
		"flipped": gpFlipped,
		"attr_values": gpAttrValues.duplicate(),
	}


# Restore this node from a dictionary (inverse of gpToDict).
# 从字典还原本节点（gpToDict 的逆操作）。
# Tolerant of the old dictionary-graph shape (id/type/label/pos/attrs) so legacy
# *.pid.json files still load.
# 兼容旧字典图形状（id/type/label/pos/attrs），使旧版 *.pid.json 仍可载入。
func gpFromDict(gpD: Dictionary) -> void:
	# New object-graph key first, fall back to the old dictionary-graph key.
	# 优先用对象图新键，再兜底旧字典图键。
	gpInstanceId = gpD.get("instance_id", gpD.get("id", ""))
	gpSymbolId = gpD.get("symbol_id", gpD.get("type", ""))
	gpTag = gpD.get("tag", gpD.get("label", ""))
	var gpP: Array = gpD.get("position", gpD.get("pos", [0.0, 0.0]))
	gpPosition = Vector2(float(gpP[0]), float(gpP[1]))
	gpRotationDeg = float(gpD.get("rotation_deg", 0.0))
	gpFlipped = bool(gpD.get("flipped", false))
	gpAttrValues = gpD.get("attr_values", gpD.get("attrs", {}))
