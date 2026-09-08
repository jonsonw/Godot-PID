# ============================================================================
# GPSymbolDeleteShapesCommand — 按下标删除图元（M7）
# Delete shapes by index (M7).
#
# 与画布 GPDeleteShapesCommand 同构。图形无 id，故下标是唯一句柄；命令在执行时按对象同一性快照真实
# 对象，并在撤销时按下标放回以恢复叠放顺序。降序删除，循环中不破坏低下标。
# Same shape as the canvas GPDeleteShapesCommand. Shapes have no id, so the index is the only handle;
# the command snapshots the real objects by identity at execute time and restores them at their
# original indices on undo to preserve z-order. Descending removal keeps low indices valid.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolDeleteShapesCommand
extends GPCommand

var _gpShapes: Array[GPShape] = []
var _gpIdx: Array[int] = []
var _gpSnapShapes: Array[GPShape] = []
var _gpSnapAt: Array[int] = []


func _init(gpInShapes: Array[GPShape], gpInIdx: Array[int]) -> void:
	_gpShapes = gpInShapes
	_gpIdx = gpInIdx.duplicate()
	gpLabel = "删除图形"


func gpExecute(_gpCtx: GPCommandContext) -> bool:
	_gpSnapShapes.clear()
	_gpSnapAt.clear()
	for gpI in _gpIdx:
		if gpI >= 0 and gpI < _gpShapes.size():
			if not _gpSnapAt.has(gpI):
				_gpSnapAt.append(gpI)
				_gpSnapShapes.append(_gpShapes[gpI])
	if _gpSnapAt.is_empty():
		return false
	_gpRemoveDescending()
	return true


func gpUndo(_gpCtx: GPCommandContext) -> void:
	var gpOrder: Array[int] = _gpSnapAt.duplicate()
	gpOrder.sort()
	for gpI in gpOrder:
		var gpK: int = _gpSnapAt.find(gpI)
		if gpK < 0:
			continue
		var gpS: GPShape = _gpSnapShapes[gpK]
		if _gpShapes.has(gpS):
			continue
		_gpShapes.insert(gpI, gpS)


func gpRedo(_gpCtx: GPCommandContext) -> void:
	_gpRemoveDescending()


func _gpRemoveDescending() -> void:
	for gpS in _gpSnapShapes:
		var gpAt: int = _gpShapes.find(gpS)
		if gpAt >= 0:
			_gpShapes.remove_at(gpAt)
