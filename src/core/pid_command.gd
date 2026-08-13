class_name GPPIDCommand
extends RefCounted

# Operation flow: every graph mutation goes through a PIDCommand (undo/redo + future
# collaboration share the same stream). See Dev Guide §4.11 seam ②.
# 操作流：所有图变更统一走 PIDCommand（撤销/重做与未来协同共用同一条流）。见开发指南 §4.11 接缝②。

# Apply this command to the graph.
# 将命令应用到图。
func gpApply(gpGraph: GPPIDGraph) -> void:
	pass

# Revert this command from the graph.
# 从图中撤销该命令。
func gpRevert(gpGraph: GPPIDGraph) -> void:
	pass
