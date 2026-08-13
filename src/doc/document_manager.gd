class_name GPPIDDocumentManager
extends RefCounted

# Multi-P&ID document manager (tabs) + cross-sheet connections.
# 多 P&ID 文档管理（标签页）+ PID 间跨图纸连接。
# See Dev Guide §4.5 / §4.6.2.
# 见开发指南 §4.5 / §4.6.2。

# doc_id -> PIDDocument
# 文档 id → PIDDocument
var gpDocuments: Dictionary = {}
# Active document id
# 当前活动文档 id
var gpActiveId: String = ""
# Cross-sheet links
# 跨图连接
var gpCrossLinks: Array = []

# Active document changed
# 活动文档变化
signal gpActiveChanged()
# A cross link was added
# 跨图连接新增
signal gpCrossLinkAdded()
# Project saved
# 工程已保存
signal gpProjectSaved()

# Open a document by id.
# 按 id 打开文档。
func gpOpen(gpDocId: String) -> void:
	pass

# Close a document by id.
# 按 id 关闭文档。
func gpClose(gpDocId: String) -> void:
	pass

# Switch the active document.
# 切换活动文档。
func gpSwitchActive(gpDocId: String) -> void:
	pass

# Add a cross-sheet connection between two nodes in different documents.
# 在两张不同文档的节点间加一条跨图连接。
func gpAddCrossLink(gpFromDoc: String, gpFromNode: String, gpToDoc: String, gpToNode: String) -> Dictionary:
	return {}

# Save the whole project (all documents + cross links) to one file.
# 将整个工程（全部文档 + 跨图连接）存为一个文件。
func gpSaveProject(gpPath: String) -> bool:
	return false

# Load a project from one file.
# 从单文件载入工程。
func gpLoadProject(gpPath: String) -> bool:
	return false
