class_name PIDNode
extends RefCounted

# One symbol instance on the canvas (not a Resource; serialized via self-managed to_dict).
# 画布上的一个图元实例（非 Resource，序列化走自管 to_dict）。
# See Dev Guide §4.5.
# 见开发指南 §4.5。

var instance_id: String = ""          # Unique instance id, e.g. "u-1" / 唯一实例 id，如 "u-1"
var symbol_id: String = ""            # SymbolDef id this node instantiates / 该节点实例化的 SymbolDef id
var tag: String = ""                  # Process tag, e.g. "FV-101" / 工艺位号，如 "FV-101"
var position: Vector2 = Vector2.ZERO  # World position / 世界坐标
var rotation_deg: float = 0.0         # Rotation in degrees / 旋转角度（度）
var flipped: bool = false             # Mirror horizontally / 水平翻转
var attr_values: Dictionary = {}      # User-set attribute values (diff from SymbolDef defaults) / 用户设置的属性值（相对 SymbolDef 默认值的差异）

# TODO: to_dict() / from_dict()
# TODO：to_dict() / from_dict()
