class_name GPDeleteShapesCommand
extends GPCommand
# Delete annotation shapes by index (M4).
# 按下标删除注释图形（M4）。
#
# Why indices / 为何用下标:
#   The selection set of annotation shapes is index-based (gpShapeSel), because shapes have
#   no id. That makes index the only handle the UI can hand over, so the command snapshots
#   the real objects at execute time and restores them at their original indices.
#   注释图形的选择集是基于下标的（gpShapeSel），因为图形没有 id。因此下标是界面唯一能交出
#   的句柄；命令在执行时快照真实对象，并在撤销时按原下标放回。
#
# Descending removal / 降序删除:
#   Removing highest-index-first keeps the lower indices valid while the loop runs — the
#   classic "don't mutate the array you are indexing into" trap.
#   先删高下标可在循环过程中保持低下标有效 —— 即「不要边遍历边改数组」的经典陷阱。

# Indices to delete, as handed over by the selection.
# 待删除的下标，由选择集交出。
var _gpIdx: Array[int] = []

# Captured shape objects, parallel to _gpAt, for undo.
# 捕获的图形对象，与 _gpAt 平行，供撤销使用。
var _gpShapes: Array[GPShape] = []

# Captured original indices, parallel to _gpShapes, so undo restores the z-order.
# 捕获的原始下标，与 _gpShapes 平行，使撤销恢复叠放顺序。
var _gpAt: Array[int] = []


# Build the command from the shape indices to remove.
# 由待删除的图形下标构造命令。
func _init(gpInIdx: Array[int]) -> void:
	_gpIdx = gpInIdx.duplicate()
	gpLabel = "删除图形"


# Snapshot then remove, highest index first. Returns false when nothing was removable, so
# an empty or stale selection produces no undo step.
# 先快照再删除，高下标优先。无内容可删时返回 false，使空的或过期的选择集不产生撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	_gpShapes.clear()
	_gpAt.clear()
	for gpI in _gpIdx:
		if gpI >= 0 and gpI < gpCtx.gpGraph.gpShapes.size():
			if not _gpAt.has(gpI):
				_gpAt.append(gpI)
				_gpShapes.append(gpCtx.gpGraph.gpShapes[gpI])
	if _gpAt.is_empty():
		return false
	_gpRemoveDescending(gpCtx)
	return true


# Put the shapes back at their original indices (ascending, so earlier slots stay valid).
# 按原始下标放回图形（升序，使较低槽位保持有效）。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpOrder: Array[int] = _gpAt.duplicate()
	gpOrder.sort()
	for gpI in gpOrder:
		var gpK: int = _gpAt.find(gpI)
		if gpK < 0:
			continue
		var gpS: GPShape = _gpShapes[gpK]
		if gpCtx.gpGraph.gpShapes.find(gpS) >= 0:
			continue
		gpCtx.gpGraph.gpInsertShape(gpS, gpI)


# Remove the same objects again (the indices were restored by undo).
# 再次移除同一批对象（下标已由撤销恢复）。
func gpRedo(gpCtx: GPCommandContext) -> void:
	_gpRemoveDescending(gpCtx)


# ============================ private ============================

# Remove every captured shape, highest index first, by object identity so a shifted array
# can never remove the wrong element.
# 按对象同一性删除所有已捕获图形，高下标优先，使发生位移的数组绝不会删错元素。
func _gpRemoveDescending(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpS in _gpShapes:
		var gpAt: int = gpCtx.gpGraph.gpShapes.find(gpS)
		if gpAt >= 0:
			gpCtx.gpGraph.gpShapes.remove_at(gpAt)
