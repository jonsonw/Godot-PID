class_name FrameDef
extends Resource

# Frame definition for one sheet: sheet size (A1 default), border style, title block
# fields, revision table. Serialized into the same *.pid.json with PIDDocument.
# 图框定义（每张图一份）：幅面（默认 A1）、边框样式、标题栏字段、版次表；
# 随 PIDDocument 序列化进同一 *.pid.json。
# See Dev Guide §4.5 / §4.6.2.
# 见开发指南 §4.5 / §4.6.2。

var sheet_size: Vector2 = Vector2(841, 594)  # A1 in mm / A1 幅面（毫米）
var border_style: Dictionary = {}            # Border line width / margin / columns / 边框线宽/留边/分栏
var title_block: Dictionary = {}             # Project/no/design/check/date/scale/revision / 标题栏字段
var revision_table: Array[Dictionary] = []   # Revision history rows / 版次表行

# Serialize to dictionary.
# 序列化为字典。
func _to_dict() -> Dictionary:
	return {}

# Restore from dictionary.
# 从字典还原。
func _from_dict(data: Dictionary) -> void:
	pass

# Apply an enterprise frame template by name.
# 按名称套用企业图框模板。
func apply_preset(name: String) -> void:
	pass
