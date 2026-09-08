class_name GPMoveNodesCommand
extends GPCommand
# Translate one or more nodes by a delta (M4).
# 按位移量平移一个或多个节点（M4）。
#
# Why it emits the signal itself / 为何自行发射信号:
#   GPPIDNode.gpPosition is a plain property, so writing it does not notify anyone.
#   Every other mutation goes through GPPIDGraph helpers that emit gpGraphChanged. To
#   keep "mutate the model, the view follows" true for dragging too, the command emits
#   the model signal once after the whole group has moved — one notification per
#   command, not one per node.
#   GPPIDNode.gpPosition 是普通属性，写入不会通知任何人。其它改动都经由会发射
#   gpGraphChanged 的 GPPIDGraph 辅助方法。为让「改模型、视图自随之」对拖拽同样成立，
#   命令在整组移动完成后发射一次模型信号——每条命令一次通知，而非每节点一次。

# Ids of the nodes to translate.
# 待平移的节点 id。
var _gpIds: Array[String] = []

# Offset to apply, in world coordinates.
# 要应用的位移量（世界坐标）。
var _gpDelta: Vector2 = Vector2.ZERO

# Guards against undoing a move that was never applied (defensive; the stack pairs
# calls correctly, but a direct caller could get it wrong).
# 防止撤销一次从未应用的移动（防御性：栈本身配对正确，但直接调用者可能用错）。
var _gpApplied: bool = false


# Build the command from the node ids and the world-space delta.
# 由节点 id 与世界坐标位移量构造命令。
func _init(gpInIds: Array[String], gpInDelta: Vector2) -> void:
	_gpIds = gpInIds.duplicate()
	_gpDelta = gpInDelta
	gpLabel = "移动节点"


# Apply the delta to every existing node. Returns false when the graph is missing;
# unknown ids are skipped rather than failing the whole move.
# 对每个存在的节点应用位移量。图缺失时返回 false；
# 未知 id 被跳过，而非让整次移动失败。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	for gpId in _gpIds:
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
		if gpN != null:
			gpN.gpPosition += _gpDelta
	_gpApplied = true
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


# Subtract the same delta, returning every node to its original position.
# 减去同一位移量，使每个节点回到原始位置。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if not _gpApplied or gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpId in _gpIds:
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
		if gpN != null:
			gpN.gpPosition -= _gpDelta
	_gpApplied = false
	gpCtx.gpGraph.gpGraphChanged.emit()


# Re-apply the same delta. Re-executing is idempotent here, so the default redo
# (which calls gpExecute) is already correct.
# 重新应用同一位移量。此处重执行是幂等的，因此默认重做（调用 gpExecute）即可。
func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
