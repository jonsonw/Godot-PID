class_name GPDeleteEdgesCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Delete one or more edges as a single undo step, restoring them at their original indices (P3).
# 把一条或多条边作为一步删除，并按原下标恢复（P3）。
#
# Why indices matter / 为何下标要紧：
#   Pipes are drawn in creation order, so the array order IS the paint order. Restoring a
#   deleted pipe by appending it would make it jump in front of everything drawn since — a
#   visible reordering the user never asked for. This mirrors GPDeleteNodesCommand's contract.
#   管线按创建顺序绘制，故数组次序就是绘制次序。若用追加方式恢复一条被删的管线，它会跳到此后
#   绘制的一切之前 —— 这是用户从未要求的可见重排。此处与 GPDeleteNodesCommand 的契约一致。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Ids of the edges to remove. / 待删除边的 id。
var gpEdgeIds: Array[String] = []

# Captured at execute time: {"edge": GPPIDEdge, "at": int} in ascending index order.
# 执行时捕获：按下标升序的 {"edge": 边, "at": 下标}。
var _gpRemoved: Array[Dictionary] = []


func _init(gpInEdgeIds: Array[String]) -> void:
	gpEdgeIds = gpInEdgeIds.duplicate()
	gpLabel = "删除连线"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	_gpRemoved = []
	for gpId in gpEdgeIds:
		var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpId)
		if gpE == null:
			continue
		var gpAt: int = gpCtx.gpGraph.gpEdges.find(gpE)
		_gpRemoved.append({"edge": gpE, "at": gpAt})
	if _gpRemoved.is_empty():
		return false
	# Ascending index order, so undo can replay the insertions left to right.
	# 升序排列，使撤销能从左到右重放插入。
	_gpRemoved.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
		return int(gpA.get("at", 0)) < int(gpB.get("at", 0)))
	for gpRec in _gpRemoved:
		gpCtx.gpGraph.gpRemoveEdge((gpRec.get("edge") as GPPIDEdge).gpInstanceId)
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpRec in _gpRemoved:
		var gpAt: int = int(gpRec.get("at", -1))
		gpCtx.gpGraph.gpInsertEdge(gpRec.get("edge") as GPPIDEdge, gpAt)


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpRec in _gpRemoved:
		gpCtx.gpGraph.gpRemoveEdge((gpRec.get("edge") as GPPIDEdge).gpInstanceId)
