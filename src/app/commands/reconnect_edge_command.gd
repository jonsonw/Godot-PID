class_name GPReconnectEdgeCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Move one END of an existing edge to a different port, node, or to a dangling point (P3).
# 把一条已有边的某一端改接到另一个端口、另一个节点，或改为悬空点（P3）。
#
# Why one command for "reconnect" and "make dangling" / 为何「改接」与「改为悬空」共用一个命令：
#   They are the same mutation — replace one end's ref dictionary. Dragging an end off its
#   symbol and dropping it on another nozzle are the same gesture with a different target, and
#   the user expects one undo step either way.
#   它们是同一个改动 —— 替换某一端的引用字典。把端点拖离图元与拖到另一个管口是同一手势、
#   不同目标，用户期望两种情形都只产一个撤销步。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Which end to move: true = from, false = to. / 要移动的端：true 为起点，false 为终点。
var gpIsFrom: bool = true

var gpEdgeId: String = ""

# The new end ref: {"node_id","port_id"} or {"node_id":"","port_id":"","point":[x,y]}.
# 新的端引用：端口绑定或悬空点。
var gpNewRef: Dictionary = {}

# Previous ref, captured at execute time. / 执行时捕获的原引用。
var _gpOldRef: Dictionary = {}


func _init(gpInEdgeId: String, gpInIsFrom: bool, gpInNewRef: Dictionary) -> void:
	gpEdgeId = gpInEdgeId
	gpIsFrom = gpInIsFrom
	gpNewRef = gpInNewRef.duplicate(true)
	gpLabel = "改接连线"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	_gpOldRef = (gpE.gpFromRef if gpIsFrom else gpE.gpToRef).duplicate(true)
	var gpNewNode: String = str(gpNewRef.get("node_id", ""))
	var gpNewPort: String = str(gpNewRef.get("port_id", ""))
	# Refuse a self-loop: the same port on the same node has no meaning on a P&ID.
	# 拒绝自环：同一节点的同一端口在 P&ID 上没有意义。
	var gpOtherNode: String = str((gpE.gpToRef if gpIsFrom else gpE.gpFromRef).get("node_id", ""))
	var gpOtherPort: String = str((gpE.gpToRef if gpIsFrom else gpE.gpFromRef).get("port_id", ""))
	if gpNewNode != "" and gpNewNode == gpOtherNode and gpNewPort == gpOtherPort:
		return false
	if gpIsFrom:
		gpE.gpFromRef = gpNewRef.duplicate(true)
	else:
		gpE.gpToRef = gpNewRef.duplicate(true)
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	if gpIsFrom:
		gpE.gpFromRef = _gpOldRef.duplicate(true)
	else:
		gpE.gpToRef = _gpOldRef.duplicate(true)
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
