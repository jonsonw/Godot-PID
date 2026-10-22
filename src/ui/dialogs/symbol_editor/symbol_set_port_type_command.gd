class_name GPSymbolSetPortTypeCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Change ONE symbol port's PURPOSE (nozzle / actuator / signal / generic terminal) as one undoable
# step — A12.
# 改变一个图元端口的**用途**（工艺管口 / 执行机构 / 信号 / 通用端点）作为一步可撤销编辑 —— A12。
#
# WHY THIS IS THE MISSING PIECE / 为何这是缺失的那一块：
# A port created by the editor's port tool took the model default (NOZZLE, a process nozzle), and
# the signal-line tool REFUSES process nozzles by design. So a user-authored instrument symbol
# could never be wired with a signal line: the symbol was complete, the drawing looked right, and
# the one thing a P&ID exists to do — connect — silently refused. Same shape as GPAddPortCommand:
# keep the port object, snapshot the previous value, restore it on undo.
# 编辑器的端口工具建的端口取模型默认值（NOZZLE，工艺管口），而信号线工具**按设计**拒绝工艺管口。
# 于是用户自建的仪表图元永远接不上信号线：图元完整、图纸看着对，而 P&ID 存在的唯一目的 —— 连线 ——
# 被静默拒绝。与 GPAddPortCommand 同构：保留端口对象、快照旧值、撤销时还原。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The editor's working port array (mutated in place, like every symbol-editor command).
# 编辑器的工作端口数组（与其它图元编辑器命令一样就地修改）。
var _gpPorts: Array[GPPort] = []

# Index of the port being changed.
# 被改端口的下标。
var _gpIdx: int = -1

# Target purpose (one of GPPort.GP_NOZZLE / GP_ACTUATOR / GP_SIGNAL / GP_TERMINAL).
# 目标用途（GPPort.GP_NOZZLE / GP_ACTUATOR / GP_SIGNAL / GP_TERMINAL 之一）。
var _gpType: String = ""

# Previous purpose, captured on the FIRST execute so undo is exact across redo.
# 先前用途，首次执行时捕获，使跨重做的撤销精确。
var _gpBefore: String = ""

# Whether the previous value was captured already.
# 是否已捕获先前值。
var _gpSnapped: bool = false


# Build from the port array, the index and the target purpose.
# 由端口数组、下标与目标用途构造。
func _init(gpInPorts: Array[GPPort], gpInIdx: int, gpInType: String) -> void:
	_gpPorts = gpInPorts
	_gpIdx = gpInIdx
	_gpType = gpInType
	gpLabel = "改端口用途"


# Write the purpose. Returns false for a stale index or a no-op, so re-picking the current entry
# records no undo step.
# 写入用途。下标失效或空操作时返回 false，使重选当前项不产生撤销步。
func gpExecute(_gpCtx: GPCommandContext) -> bool:
	if _gpIdx < 0 or _gpIdx >= _gpPorts.size() or _gpType == "":
		return false
	var gpP: GPPort = _gpPorts[_gpIdx]
	if gpP == null:
		return false
	if not _gpSnapped:
		_gpSnapped = true
		_gpBefore = gpP.gpType
	if gpP.gpType == _gpType:
		return false
	gpP.gpType = _gpType
	return true


# Put the previous purpose back.
# 把先前用途放回去。
func gpUndo(_gpCtx: GPCommandContext) -> void:
	if _gpIdx < 0 or _gpIdx >= _gpPorts.size():
		return
	var gpP: GPPort = _gpPorts[_gpIdx]
	if gpP == null:
		return
	gpP.gpType = _gpBefore


# Re-apply the target purpose (redo replays the recorded value, never re-derives).
# 重新应用目标用途（重做重放记录值，绝不重新推导）。
func gpRedo(_gpCtx: GPCommandContext) -> void:
	if _gpIdx < 0 or _gpIdx >= _gpPorts.size():
		return
	var gpP: GPPort = _gpPorts[_gpIdx]
	if gpP == null:
		return
	gpP.gpType = _gpType
