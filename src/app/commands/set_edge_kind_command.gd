class_name GPSetEdgeKindCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Change an edge's kind (PROCESS / UTILITY / SIGNAL) and, for SIGNAL, its signal type (P4).
# 改变一条边的类型（PROCESS/UTILITY/SIGNAL），信号线另带信号类型（P4）。
#
# Why one command for both fields / 为何两字段合一命令：
#   kind and signal_type are mutually tied (a SIGNAL edge must carry a signal_type; the others
#   must not). Changing either is one user action and must be one undo step. The style table is a
#   pure function of (kind, signal_type), so the repaint after this command needs no data
#   migration — that is exactly the "change line type, repaint immediately" acceptance.
#   kind 与 signal_type 相互绑定（信号线必带信号类型，其余不可带）。改任一都是一次用户操作、
#   应是一个撤销步。样式表是 (kind, signal_type) 的纯函数，故本命令后重绘无需数据迁移 ——
#   那正是「改线型立即重绘」验收项的含义。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpEdgeId: String = ""
var gpNewKind: String = ""
var gpNewSignalType: String = ""

# Previous values, captured at execute time so undo is exact.
# 执行时捕获的原值，使撤销精确。
var _gpOldKind: String = ""
var _gpOldSignal: String = ""


func _init(gpInEdgeId: String, gpInKind: String, gpInSignalType: String = "") -> void:
	gpEdgeId = gpInEdgeId
	gpNewKind = gpInKind
	# A non-signal edge carries no signal type. / 非信号线不带信号类型。
	gpNewSignalType = gpInSignalType if gpInKind == GPPIDEdge.GP_SIGNAL else ""
	gpLabel = "修改连线类型"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	if gpE.gpKind == gpNewKind and gpE.gpSignalType == gpNewSignalType:
		return false
	_gpOldKind = gpE.gpKind
	_gpOldSignal = gpE.gpSignalType
	gpE.gpKind = gpNewKind
	gpE.gpSignalType = gpNewSignalType
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	gpE.gpKind = _gpOldKind
	gpE.gpSignalType = _gpOldSignal
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
