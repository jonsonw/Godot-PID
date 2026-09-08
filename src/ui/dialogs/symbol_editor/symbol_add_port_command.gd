# ============================================================================
# GPSymbolAddPortCommand — 添加连接端口（M7）
# Add a connection port to the symbol's working port list (M7).
#
# 与 GPAddShapeCommand 同构，但作用于 _gpPorts 数组。保留端口对象，重做重插入同一实例。
# Same shape as GPAddShapeCommand but operates on the _gpPorts array. The port object is kept so redo
# re-inserts the same instance.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolAddPortCommand
extends GPCommand

var _gpPorts: Array[GPPort] = []
var _gpPort: GPPort = null


func _init(gpInPorts: Array[GPPort], gpInPort: GPPort) -> void:
	_gpPorts = gpInPorts
	_gpPort = gpInPort
	gpLabel = "添加端口"


func gpExecute(_gpCtx: GPCommandContext) -> bool:
	if _gpPort == null or _gpPorts.has(_gpPort):
		return false
	_gpPorts.append(_gpPort)
	return true


func gpUndo(_gpCtx: GPCommandContext) -> void:
	if _gpPorts.has(_gpPort):
		_gpPorts.erase(_gpPort)


func gpRedo(_gpCtx: GPCommandContext) -> void:
	if not _gpPorts.has(_gpPort):
		_gpPorts.append(_gpPort)
