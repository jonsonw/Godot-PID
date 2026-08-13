class_name GPFrameDef
extends Resource

# Frame definition for one sheet: sheet size (A1 default), border style, title block
# fields, revision table. Serialized into the same *.pid.json with PIDDocument.
# 图框定义（每张图一份）：幅面（默认 A1）、边框样式、标题栏字段、版次表；
# 随 PIDDocument 序列化进同一 *.pid.json。
# See Dev Guide §4.5 / §4.6.2.
# 见开发指南 §4.5 / §4.6.2。

# A1 in mm / A1
# 幅面（毫米）
var gpSheetSize: Vector2 = Vector2(841, 594)
# Border line width / margin / columns
# 边框线宽/留边/分栏
var gpBorderStyle: Dictionary = {}
# Project/no/design/check/date/scale/revision
# 标题栏字段
var gpTitleBlock: Dictionary = {}
# Revision history rows
# 版次表行
var gpRevisionTable: Array[Dictionary] = []

# Serialize to dictionary.
# 序列化为字典。
func _gpToDict() -> Dictionary:
	return {}

# Restore from dictionary.
# 从字典还原。
func _gpFromDict(gpData: Dictionary) -> void:
	pass

# Apply an enterprise frame template by name.
# 按名称套用企业图框模板。
func gpApplyPreset(gpName: String) -> void:
	pass
