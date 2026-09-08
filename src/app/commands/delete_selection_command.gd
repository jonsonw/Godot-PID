class_name GPDeleteSelectionCommand
extends GPCommand
# Delete a MIXED selection (nodes + annotation shapes) as ONE undo step (M4).
# 把混合选择集（节点 + 注释图形）作为「一个撤销步」删除（M4）。
#
# Why a composite / 为何做成组合命令:
#   A marquee can catch nodes and shapes at once. Pushing two separate commands would make
#   the user press Ctrl+Z twice to undo what looked like a single Delete — the classic
#   "undo granularity must match the perceived action" rule.
#   一次框选可以同时框住节点与图形。若压入两条独立命令，用户要按两次 Ctrl+Z 才能撤销
#   看起来是一次删除的动作 —— 违反了「撤销粒度必须与感知到的一次操作对齐」这条经典规则。

# Node half of the deletion (nodes + their touching edges).
# 删除的节点部分（节点 + 其关联边）。
var _gpNodes: GPDeleteNodesCommand = null

# Annotation-shape half of the deletion.
# 删除的注释图形部分。
var _gpShapes: GPDeleteShapesCommand = null


# Build the command from the current selection: node ids and shape indices.
# 由当前选择集构造命令：节点 id 与图形下标。
func _init(gpInNodeIds: Array[String], gpInShapeIdxs: Array[int]) -> void:
	_gpNodes = GPDeleteNodesCommand.new(gpInNodeIds)
	_gpShapes = GPDeleteShapesCommand.new(gpInShapeIdxs)
	gpLabel = "删除"


# Run both halves. Returns true when either of them actually removed something.
# 执行两个部分。任一部分确实删掉了东西即返回 true。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null:
		return false
	var gpA: bool = _gpNodes.gpExecute(gpCtx)
	var gpB: bool = _gpShapes.gpExecute(gpCtx)
	return gpA or gpB


# Restore both halves. Shapes first, then nodes: independent of each other, but this order
# keeps the annotation layer valid while the topology is being put back.
# 恢复两个部分。先图形后节点：二者互不依赖，但此顺序可在拓扑回放期间保持注释层有效。
func gpUndo(gpCtx: GPCommandContext) -> void:
	_gpShapes.gpUndo(gpCtx)
	_gpNodes.gpUndo(gpCtx)


# Re-apply both halves.
# 重新应用两个部分。
func gpRedo(gpCtx: GPCommandContext) -> void:
	_gpNodes.gpRedo(gpCtx)
	_gpShapes.gpRedo(gpCtx)
