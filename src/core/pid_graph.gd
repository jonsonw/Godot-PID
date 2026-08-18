class_name GPPIDGraph
extends Resource

# P&ID topology data core: a node-edge graph.
# P&ID 拓扑数据内核：节点-边图。
# The 2D canvas, 3D linkage and list export all read this resource.
# 2D 画布、3D 联动、清单导出都读取这个 Resource。

# Project metadata stored inside the graph resource.
# 图资源内部保存的工程元数据。
@export var gpMeta: Dictionary = {
	"version": "1.0",
	"title": "",
	"sheets": 1,
}

# All symbol instances (nodes) in this sheet.
# 本图纸内所有图元实例（节点）。
@export var gpNodes: Array[Dictionary] = []

# All connections (edges) between nodes in this sheet.
# 本图纸内节点之间的所有连线（边）。
@export var gpEdges: Array[Dictionary] = []


# Add a node to the graph.
# 向图中添加一个节点。
func gpAddNode(gpId: String, gpType: String, gpLabel: String, gpPos: Vector2 = Vector2.ZERO, gpAttrs: Dictionary = {}) -> void:
	gpNodes.append({
		"id": gpId,
		"type": gpType,
		"label": gpLabel,
		"pos": [gpPos.x, gpPos.y],
		"attrs": gpAttrs.duplicate(),
	})


# Add an edge between two nodes.
# 在两个节点之间添加一条边。
func gpAddEdge(gpId: String, gpFromId: String, gpToId: String, gpAttrs: Dictionary = {}) -> void:
	gpEdges.append({
		"id": gpId,
		"from": gpFromId,
		"to": gpToId,
		"attrs": gpAttrs.duplicate(),
	})


# Serialize the graph to a plain dictionary.
# 将图序列化为普通字典。
func gpToDict() -> Dictionary:
	return {
		"meta": gpMeta.duplicate(),
		"nodes": gpNodes.duplicate(),
		"edges": gpEdges.duplicate(),
	}


# Restore a graph from a plain dictionary.
# 从普通字典还原图。
static func gpFromDict(gpData: Dictionary) -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	if gpData.has("meta"):
		gpG.gpMeta = gpData["meta"].duplicate()
	if gpData.has("nodes"):
		gpG.gpNodes = gpData["nodes"].duplicate()
	if gpData.has("edges"):
		gpG.gpEdges = gpData["edges"].duplicate()
	return gpG
