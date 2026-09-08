# ============================================================================
# GPSymbolMoveShapeCommand — 移动图形（M7）
# Move a shape by shifting its points (M7).
#
# 捕获前后点集与半径，使撤销 / 重做恢复确切几何。执行时若无变化（前后一致）返回 false，栈将丢弃它，
# 不产生幽灵撤销步（普通单击 / 零位移均如此）。
# Captures before/after points + radius so undo/redo restore the exact geometry. When nothing
# changed (before == after) gpExecute returns false so the stack drops it — no phantom undo step
# for a plain click or a zero delta.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolMoveShapeCommand
extends GPCommand

var _gpShapes: Array[GPShape] = []
var _gpIdx: int = -1
var _gpBefore: PackedVector2Array = PackedVector2Array()
var _gpBeforeR: float = 0.0
var _gpAfter: PackedVector2Array = PackedVector2Array()
var _gpAfterR: float = 0.0


func _init(gpInShapes: Array[GPShape], gpInIdx: int, gpInBefore: PackedVector2Array, gpInBeforeR: float, gpInAfter: PackedVector2Array, gpInAfterR: float) -> void:
	_gpShapes = gpInShapes
	_gpIdx = gpInIdx
	_gpBefore = gpInBefore.duplicate()
	_gpBeforeR = gpInBeforeR
	_gpAfter = gpInAfter.duplicate()
	_gpAfterR = gpInAfterR
	gpLabel = "移动图形"


func gpExecute(_gpCtx: GPCommandContext) -> bool:
	if _gpShapes.size() <= _gpIdx or _gpIdx < 0:
		return false
	var gpS: GPShape = _gpShapes[_gpIdx]
	if _gpPointsEqual(gpS.gpPoints, _gpAfter) and is_equal_approx(gpS.gpRadius, _gpAfterR):
		return false
	gpS.gpPoints = _gpAfter.duplicate()
	gpS.gpRadius = _gpAfterR
	return true


func gpUndo(_gpCtx: GPCommandContext) -> void:
	if _gpShapes.size() <= _gpIdx or _gpIdx < 0:
		return
	var gpS: GPShape = _gpShapes[_gpIdx]
	gpS.gpPoints = _gpBefore.duplicate()
	gpS.gpRadius = _gpBeforeR


func gpRedo(_gpCtx: GPCommandContext) -> void:
	if _gpShapes.size() <= _gpIdx or _gpIdx < 0:
		return
	var gpS: GPShape = _gpShapes[_gpIdx]
	gpS.gpPoints = _gpAfter.duplicate()
	gpS.gpRadius = _gpAfterR


func _gpPointsEqual(gpA: PackedVector2Array, gpB: PackedVector2Array) -> bool:
	if gpA.size() != gpB.size():
		return false
	for gpI in range(gpA.size()):
		if not gpA[gpI].is_equal_approx(gpB[gpI]):
			return false
	return true
