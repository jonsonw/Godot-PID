# ============================================================================
# GPSymbolMovePortCommand — 移动端口（M7）
# Move a port (M7).
#
# 捕获前后归一化位置，使撤销 / 重做恢复确切位置。无变化（前后一致）时返回 false，栈丢弃之。
# Captures before/after normalized positions so undo/redo restore the exact location. Returns false
# (and the stack drops it) when nothing changed.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolMovePortCommand
extends GPCommand

var _gpPorts: Array[GPPort] = []
var _gpIdx: int = -1
var _gpBefore: Vector2 = Vector2.ZERO
var _gpAfter: Vector2 = Vector2.ZERO


func _init(gpInPorts: Array[GPPort], gpInIdx: int, gpInBefore: Vector2, gpInAfter: Vector2) -> void:
	_gpPorts = gpInPorts
	_gpIdx = gpInIdx
	_gpBefore = gpInBefore
	_gpAfter = gpInAfter
	gpLabel = "移动端口"


func gpExecute(_gpCtx: GPCommandContext) -> bool:
	if _gpPorts.size() <= _gpIdx or _gpIdx < 0:
		return false
	if _gpPorts[_gpIdx].gpPos.is_equal_approx(_gpAfter):
		return false
	_gpPorts[_gpIdx].gpPos = _gpAfter
	return true


func gpUndo(_gpCtx: GPCommandContext) -> void:
	if _gpPorts.size() <= _gpIdx or _gpIdx < 0:
		return
	_gpPorts[_gpIdx].gpPos = _gpBefore


func gpRedo(_gpCtx: GPCommandContext) -> void:
	if _gpPorts.size() <= _gpIdx or _gpIdx < 0:
		return
	_gpPorts[_gpIdx].gpPos = _gpAfter
