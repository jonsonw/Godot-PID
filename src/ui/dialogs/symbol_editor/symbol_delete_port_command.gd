# ============================================================================
# GPSymbolDeletePortCommand — 按下标删除端口（M7）
# Delete ports by index (M7).
#
# 与 GPDeleteShapesCommand 同构，作用于 _gpPorts 数组。按下标快照对象，撤销时按下标放回。
# Same shape as GPDeleteShapesCommand, operates on the _gpPorts array. Snapshots by index, restores
# at the original index on undo.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolDeletePortCommand
extends GPCommand

var _gpPorts: Array[GPPort] = []
var _gpIdx: Array[int] = []
var _gpSnapPorts: Array[GPPort] = []
var _gpSnapAt: Array[int] = []


func _init(gpInPorts: Array[GPPort], gpInIdx: Array[int]) -> void:
	_gpPorts = gpInPorts
	_gpIdx = gpInIdx.duplicate()
	gpLabel = "删除端口"


func gpExecute(_gpCtx: GPCommandContext) -> bool:
	_gpSnapPorts.clear()
	_gpSnapAt.clear()
	for gpI in _gpIdx:
		if gpI >= 0 and gpI < _gpPorts.size():
			if not _gpSnapAt.has(gpI):
				_gpSnapAt.append(gpI)
				_gpSnapPorts.append(_gpPorts[gpI])
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
		var gpP: GPPort = _gpSnapPorts[gpK]
		if _gpPorts.has(gpP):
			continue
		_gpPorts.insert(gpI, gpP)


func gpRedo(_gpCtx: GPCommandContext) -> void:
	_gpRemoveDescending()


func _gpRemoveDescending() -> void:
	for gpP in _gpSnapPorts:
		var gpAt: int = _gpPorts.find(gpP)
		if gpAt >= 0:
			_gpPorts.remove_at(gpAt)
