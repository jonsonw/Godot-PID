class_name PIDDocumentManager
extends RefCounted

# Multi-P&ID document manager (tabs) + cross-sheet connections.
# 多 P&ID 文档管理（标签页）+ PID 间跨图纸连接。
# See Dev Guide §4.5 / §4.6.2.
# 见开发指南 §4.5 / §4.6.2。

var documents: Dictionary = {}   # doc_id -> PIDDocument / 文档 id → PIDDocument
var active_id: String = ""      # Active document id / 当前活动文档 id
var cross_links: Array = []     # Cross-sheet links / 跨图连接

signal active_changed()         # Active document changed / 活动文档变化
signal cross_link_added()       # A cross link was added / 跨图连接新增
signal project_saved()          # Project saved / 工程已保存

# Open a document by id.
# 按 id 打开文档。
func open(doc_id: String) -> void:
	pass

# Close a document by id.
# 按 id 关闭文档。
func close(doc_id: String) -> void:
	pass

# Switch the active document.
# 切换活动文档。
func switch_active(doc_id: String) -> void:
	pass

# Add a cross-sheet connection between two nodes in different documents.
# 在两张不同文档的节点间加一条跨图连接。
func add_cross_link(from_doc: String, from_node: String, to_doc: String, to_node: String) -> Dictionary:
	return {}

# Save the whole project (all documents + cross links) to one file.
# 将整个工程（全部文档 + 跨图连接）存为一个文件。
func save_project(path: String) -> bool:
	return false

# Load a project from one file.
# 从单文件载入工程。
func load_project(path: String) -> bool:
	return false
