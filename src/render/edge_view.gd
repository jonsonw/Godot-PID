class_name GPEdgeView
extends Node2D

# Visual representation of one P&ID edge (pipe or connection).
# 一条 P&ID 连线（管道或连接）的可视化表示。
# Lives under the same world_root as GPSymbolView so it scales and pans automatically.
# 与 GPSymbolView 同处一个 world_root 下，因此自动随其缩放与平移。

# Bound graph edge id.
# 绑定的图边 id。
var gpEdgeId: String = ""

# Bound graph edge object (strongly typed; the single source of truth).
# 绑定的图边对象（强类型；唯一真相来源）。
var gpEdge: GPPIDEdge = null

# Reference to the parent graph (used to look up node positions).
# 父图引用（用于查找节点位置）。
var gpGraph: GPPIDGraph = null


# Bind this view to a graph edge.
# 将本视图绑定到一条图边。
func gpInit(gpE: GPPIDEdge, gpG: GPPIDGraph) -> void:
	gpEdge = gpE
	gpEdgeId = gpE.gpInstanceId
	gpGraph = gpG
	name = "Edge_" + gpEdgeId
	queue_redraw()


# Draw a straight line between the two connected node centers.
# 在相连两图元中心之间画一条直线。
func _draw() -> void:
	if gpGraph == null or gpEdge == null:
		return
	var gpA: Vector2 = _gpNodeCenter(gpEdge.gpFromRef.get("node_id", ""))
	var gpB: Vector2 = _gpNodeCenter(gpEdge.gpToRef.get("node_id", ""))
	if gpA == Vector2.INF or gpB == Vector2.INF:
		return
	draw_line(gpA, gpB, Color(0.70, 0.75, 0.85), 2.0)


# Look up the world center of a node by id.
# 按 id 查找节点的世界中心坐标。
func _gpNodeCenter(gpId: String) -> Vector2:
	for gpN in gpGraph.gpNodes:
		if gpN.gpInstanceId == gpId:
			return gpN.gpPosition
	return Vector2.INF
