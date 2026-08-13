class_name GPPersistence
extends RefCounted

# Save/load module (single-file format): the whole project = one *.pid.json.
# 存档/读档模块（独档格式）：整个工程 = 一个 *.pid.json。
# See Dev Guide §4.10 / §4.6.2.
# 见开发指南 §4.10 / §4.6.2。

# Save the whole project (all documents + cross links) to a single file.
# 将整个工程（全部文档 + 跨图连接）存为单文件。
func gpSaveProject(gpMgr, gpPath: String) -> bool:
	return false

# Load a project from a single file -> manager.
# 从单文件载入工程 → 管理器。
func gpLoadProject(gpPath: String):
	return null

# Auto-save (debounced timer) triggered by graph_changed.
# 自动保存（防抖定时器），由 graph_changed 触发。
func gpAutoSave(gpMgr) -> void:
	pass

# Migrate an old schema dict to the current version (pid-1.0 -> pid-1.1).
# 将旧 schema 字典迁移到当前版本（pid-1.0 → pid-1.1）。
func gpMigrate(gpDict: Dictionary) -> Dictionary:
	return gpDict

# Write a *.bak snapshot before overwriting.
# 覆盖写前写 *.bak 快照。
func gpBackup(gpPath: String) -> void:
	pass
