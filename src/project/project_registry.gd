class_name ProjectRegistry
extends RefCounted

# Lightweight registry (NOT a database): recent list + known project index (user://recent.json).
# 轻量登记（非数据库）：最近列表 + 已知工程索引（user://recent.json）。
# See Dev Guide §4.12.
# 见开发指南 §4.12。

signal registry_changed()  # Registry changed / 登记变化

# List known projects.
# 列出已知工程。
func list_projects() -> Array:
	return []

# Register a project path.
# 登记一个工程路径。
func register(path: String) -> void:
	pass

# Unregister a project path.
# 注销一个工程路径。
func unregister(path: String) -> void:
	pass

# Recent project paths (most recent first).
# 最近打开的工程路径（最新在前）。
func recent() -> Array[String]:
	return []
