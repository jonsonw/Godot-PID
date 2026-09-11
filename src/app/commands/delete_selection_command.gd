class_name GPDeleteSelectionCommand
extends GPCommand
# Delete a MIXED selection (nodes + annotation shapes + edges) as ONE undo step (M4 + W4 edge delete).
# 把混合选择集（节点 + 注释图形 + 边）作为「一个撤销步」删除（M4 + W4 删边）。
#
# Why a composite / 为何做成组合命令:
#   A marquee can catch nodes and shapes at once. Pushing two separate commands would make
#   the user press Ctrl+Z twice to undo what looked like a single Delete — the classic
#   "undo granularity must match the perceived action" rule. The edge half is added in W4 so
#   pressing Del on a selected pipe is also one step.
#   一次框选可以同时框住节点与图形。若压入两条独立命令，用户要按两次 Ctrl+Z 才能撤销
#   看起来是一次删除的动作 —— 违反了「撤销粒度必须与感知到的一次操作对齐」这条经典规则。
#   边的部分于 W4 补入，使在选中管线上按 Del 同样只算一步。

# Node half of the deletion (nodes + their touching edges).
# 删除的节点部分（节点 + 其关联边）。
var _gpNodes: GPDeleteNodesCommand = null

# Annotation-shape half of the deletion.
# 删除的注释图形部分。
var _gpShapes: GPDeleteShapesCommand = null

# Edge half of the deletion (only edges NOT attached to a deleted node — those are removed by the
# node half, so including them here would double-delete and double-insert on undo).
# 删除的边部分（仅含未依附于被删节点的边 —— 依附者已由节点部分删除，重复纳入会双重删除并在撤销时
# 重复插入）。
var _gpEdges: GPDeleteEdgesCommand = null


# Build the command from the current selection: node ids, shape indices and edge ids.
# 由当前选择集构造命令：节点 id、图形下标与边 id。
func _init(gpInNodeIds: Array[String], gpInShapeIdxs: Array[int], gpInEdgeIds: Array[String] = []) -> void:
	_gpNodes = GPDeleteNodesCommand.new(gpInNodeIds)
	_gpShapes = GPDeleteShapesCommand.new(gpInShapeIdxs)
	# Only build the edge half when there is something to delete, so an edge-less selection stays
	# a pure node/shape composite (no empty no-op half).
	# 仅在确有边要删时才构建边部分，使不含边的选择仍是纯节点 / 图形复合体（不引入空的无效半步）。
	if gpInEdgeIds.size() > 0:
		_gpEdges = GPDeleteEdgesCommand.new(gpInEdgeIds)
	gpLabel = "删除"


# Run all halves. Returns true when any of them actually removed something.
# 执行所有部分。任一部分确实删掉了东西即返回 true。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null:
		return false
	var gpA: bool = _gpNodes.gpExecute(gpCtx)
	var gpB: bool = _gpShapes.gpExecute(gpCtx)
	var gpC: bool = (_gpEdges != null) and _gpEdges.gpExecute(gpCtx)
	return gpA or gpB or gpC


# Restore all halves. Shapes first, then edges (both endpoints still exist), then nodes — this keeps
# the annotation layer valid and every edge re-inserted before its endpoints could be touched.
# 恢复所有部分。先图形、再边（两端仍存在）、后节点 —— 既保持注释层有效，又让每条边在端点被触及前
# 已插回。
func gpUndo(gpCtx: GPCommandContext) -> void:
	_gpShapes.gpUndo(gpCtx)
	if _gpEdges != null:
		_gpEdges.gpUndo(gpCtx)
	_gpNodes.gpUndo(gpCtx)


# Re-apply all halves. Nodes first (which removes edges attached to them), then the standalone edges,
# then shapes.
# 重新应用所有部分。先节点（会移除依附其上的边），再独立边，后图形。
func gpRedo(gpCtx: GPCommandContext) -> void:
	_gpNodes.gpRedo(gpCtx)
	if _gpEdges != null:
		_gpEdges.gpRedo(gpCtx)
	_gpShapes.gpRedo(gpCtx)
