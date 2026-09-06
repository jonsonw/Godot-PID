class_name GPListBasic
extends RefCounted

# Basic lists: equipment / pipe / valve / instrument CSV or JSON, bucketed by category.
# 基础清单：设备/管线/阀门/仪表的 CSV 或 JSON，按 category 自动分桶。
# See Dev Guide §4.1 / §4.6.2.
# 见开发指南 §4.1 / §4.6.2。

# Export equipment/pipe/valve/instrument lists; returns the four file paths.
# 导出设备/管线/阀门/仪表清单，返回四个文件路径。
func gpExportLists(gpDoc, gpDir: String) -> Dictionary:
	return {}
