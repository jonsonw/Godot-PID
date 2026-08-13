class_name GPProjectRegistry
extends RefCounted

# Lightweight registry (NOT a database): recent list + known project index (user://recent.json).
# 轻量登记（非数据库）：最近列表 + 已知工程索引（user://recent.json）。
# See Dev Guide §4.12.
# 见开发指南 §4.12。

# Registry changed
# 登记变化
signal gpRegistryChanged()

# List known projects.
# 列出已知工程。
func gpListProjects() -> Array:
	return []

# Register a project path.
# 登记一个工程路径。
func gpRegister(gpPath: String) -> void:
	pass

# Unregister a project path.
# 注销一个工程路径。
func gpUnregister(gpPath: String) -> void:
	pass

# Recent project paths (most recent first).
# 最近打开的工程路径（最新在前）。
func gpRecent() -> Array[String]:
	return []
