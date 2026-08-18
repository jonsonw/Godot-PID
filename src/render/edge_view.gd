class_name GPEdgeView
extends Node2D

# Visual representation of one P&ID edge (pipe or connection).
# 一条 P&ID 连线（管道或连接）的可视化表示。
# Lives under the same world_root as GPSymbolView so it scales and pans automatically.
# 与 GPSymbolView 同处一个 world_root 下，因此自动随其缩放与平移。

var gpEdgeId: String = ""
var gpEdge: Dictionary = {}
var gpGraph: GPPIDGraph = null


# Bind this view to a graph edge.
# 将本视图绑定到一条图边。
func gpInit(gpE: Dictionary, gpG: GPPIDGraph) -> void:
	gpEdge = gpE
	gpEdgeId = gpE.get("id", "")
	gpGraph = gpG
	name = "Edge_" + gpEdgeId
	queue_redraw()


func _draw() -> void:
	if gpGraph == null or gpEdge.is_empty():
		return
	var gpA: Vector2 = _gpNodeCenter(gpEdge.get("from", ""))
	var gpB: Vector2 = _gpNodeCenter(gpEdge.get("to", ""))
	if gpA == Vector2.INF or gpB == Vector2.INF:
		return
	draw_line(gpA, gpB, Color(0.70, 0.75, 0.85), 2.0)


func _gpNodeCenter(gpId: String) -> Vector2:
	for gpN in gpGraph.gpNodes:
		if gpN.get("id", "") == gpId:
			var gpPos: Array = gpN.get("pos", [0.0, 0.0])
			return Vector2(float(gpPos[0]), float(gpPos[1]))
	return Vector2.INF
