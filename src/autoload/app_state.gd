extends Node

# Global singleton (Autoload): current project manager + selection + project switching.
# 全局单例（Autoload）：当前工程管理器 + 选中态 + 工程切换。
# See Dev Guide §4.5 / §4.12.
# 见开发指南 §4.5 / §4.12。

var current_manager = null       # Active PIDDocumentManager / 当前 PIDDocumentManager
var selected: Array = []         # Selected node ids / 选中的节点 id 列表
var is_dirty: bool = false       # Unsaved changes flag / 是否有未保存改动

signal selection_changed()       # Selection changed / 选中变化
signal doc_changed()             # Document changed / 文档变化
signal project_changed()         # Project changed / 工程变化

# Open a project from a path.
# 从路径打开工程。
func open_project(path: String) -> void:
	pass

# Create a new project.
# 新建工程。
func new_project() -> void:
	pass

# Switch to another project (prompt save if dirty).
# 切换到另一工程（若脏则先提示保存）。
func switch_project(path: String) -> void:
	pass

# Close the current project.
# 关闭当前工程。
func close_project() -> void:
	pass
