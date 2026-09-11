class_name GPResnapEdgeCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Re-resolve an edge's ends to real ports (P4). Legacy files store an end as node_id with an
# empty port_id, which the live resolver downgrades to the node CENTRE; this snaps it to the
# first matching port so the pipe visibly connects to the symbol's port instead of its middle.
# 把一条边的两端重新吸附到真实端口（P4）。老档把端点存为 node_id + 空 port_id，实时解析器会
# 退化到节点「中心」；本命令将其吸附到首个匹配端口，使管线明显连到图元端口而非正中。
#
# Only the port_id is rewritten; the geometry the resolver computes live is untouched, so an
# already-port-bound end is left exactly as-is (idempotent, one undo step).
# 只改写 port_id，不碰解析器实时计算的几何，故已端口绑定的端原样保留（幂等、一个撤销步）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpEdgeId: String = ""
var _gpDefLookup: Callable = Callable()
var _gpOldFrom: Dictionary = {}
var _gpOldTo: Dictionary = {}
var _gpChanged: bool = false


func _init(gpInEdgeId: String, gpInDefLookup: Callable) -> void:
	gpEdgeId = gpInEdgeId
	_gpDefLookup = gpInDefLookup
	gpLabel = "重新吸附端点"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	_gpOldFrom = gpE.gpFromRef.duplicate()
	_gpOldTo = gpE.gpToRef.duplicate()
	_gpChanged = false
	gpE.gpFromRef = GPPortResolver.gpSnapRef(gpCtx.gpGraph, _gpDefLookup, gpE, true)
	gpE.gpToRef = GPPortResolver.gpSnapRef(gpCtx.gpGraph, _gpDefLookup, gpE, false)
	_gpChanged = (gpE.gpFromRef != _gpOldFrom) or (gpE.gpToRef != _gpOldTo)
	if not _gpChanged:
		# Restore so undo/redo stay no-ops. / 还原，使撤销/重做为空操作。
		gpE.gpFromRef = _gpOldFrom
		gpE.gpToRef = _gpOldTo
		return false
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	gpE.gpFromRef = _gpOldFrom.duplicate()
	gpE.gpToRef = _gpOldTo.duplicate()
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
