class_name PIDDocument
extends RefCounted

# Document aggregate + undo/redo stack.
# 文档聚合 + 撤销/重做栈。
# See Dev Guide §4.5.
# 见开发指南 §4.5。

var graph: PIDGraph                  # The topology graph for this sheet / 本图纸的拓扑图
var undo_stack: Array = []           # Undo command stack / 撤销命令栈
var redo_stack: Array = []           # Redo command stack / 重做命令栈
var frame: FrameDef = null           # Frame definition (A1 default) for this sheet / 本图纸的图框定义（默认 A1）

# Save this single document's graph to a path.
# 将本单文档的图写入路径。
func save(path: String) -> bool:
	return false

# Load a graph back from a path.
# 从路径读回 PIDGraph。
func load(path: String) -> bool:
	return false

# Undo the last command.
# 撤销上一步操作。
func undo() -> void:
	pass

# Redo the last undone command.
# 重做上一步撤销。
func redo() -> void:
	pass

# Commit a command (push to undo stack, clear redo).
# 提交一条命令（入撤销栈、清空重做栈）。
func commit(cmd) -> void:
	pass

# Set the frame for this sheet (A1 default; size/title block/revision can change).
# 设置当前图的图框（默认 A1，可改幅面/标题栏/版次表）。
func set_frame(f: FrameDef) -> void:
	frame = f

# TODO: integrate with PIDCommand (Dev Guide §4.11 seam ②).
# TODO：与 PIDCommand 结合（开发指南 §4.11 接缝②）。
