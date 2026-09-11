class_name GPSetEdgeRoutingCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Replace an edge's intermediate waypoints (P3). Driven by dragging a vertex grip.
# 替换一条边的中间拐点（P3）。由拖动拐点抓取点驱动。
#
# Waypoints only — never the endpoints / 仅拐点 —— 绝不含端点：
#   gpRouting deliberately stores neither end (see GPPIDEdge). Endpoints are resolved live from
#   the port refs, so moving a symbol drags its pipe along. This command must therefore never
#   write an endpoint into gpRouting, or it would freeze the pipe at one position and tear it
#   away from its symbol the next time the symbol moves.
#   gpRouting 刻意不存任一端点（见 GPPIDEdge）。端点由端口引用实时解析，故移动图元时管线自动
#   跟随。因此本命令绝不能把端点写进 gpRouting，否则会把管线冻结在某个位置，图元下次移动时
#   管线就与图元脱开。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpEdgeId: String = ""
var gpNewRouting: Array[Vector2] = []

# Previous waypoints, captured at execute time. / 执行时捕获的原拐点。
var _gpOldRouting: Array[Vector2] = []


func _init(gpInEdgeId: String, gpInNewRouting: Array[Vector2]) -> void:
	gpEdgeId = gpInEdgeId
	gpNewRouting = gpInNewRouting.duplicate()
	gpLabel = "调整连线"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	if _gpSame(gpE.gpRouting, gpNewRouting):
		return false
	_gpOldRouting = gpE.gpRouting.duplicate()
	gpE.gpRouting = gpNewRouting.duplicate()
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	gpE.gpRouting = _gpOldRouting.duplicate()
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)


func _gpSame(gpA: Array[Vector2], gpB: Array[Vector2]) -> bool:
	if gpA.size() != gpB.size():
		return false
	for gpI in range(gpA.size()):
		if not gpA[gpI].is_equal_approx(gpB[gpI]):
			return false
	return true
