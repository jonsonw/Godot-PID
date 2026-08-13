class_name GPPIDGraph
extends Resource

# P&ID topology data core: a node-edge graph.
# P&ID 拓扑数据内核：节点-边图。
# The 2D canvas, 3D linkage and list export all read this resource.
# 2D 画布、3D 联动、清单导出都读取这个 Resource。

@export var gpMeta: Dictionary = {
	"version": "1.0",
	"title": "",
	"sheets": 1,
}

@export var gpNodes: Array[Dictionary] = []
@export var gpEdges: Array[Dictionary] = []


func gpAddNode(gpId: String, gpType: String, gpLabel: String, gpPos: Vector2 = Vector2.ZERO, gpAttrs: Dictionary = {}) -> void:
	gpNodes.append({
		"id": gpId,
		"type": gpType,
		"label": gpLabel,
		"pos": [gpPos.x, gpPos.y],
		"attrs": gpAttrs.duplicate(),
	})


func gpAddEdge(gpId: String, gpFromId: String, gpToId: String, gpAttrs: Dictionary = {}) -> void:
	gpEdges.append({
		"id": gpId,
		"from": gpFromId,
		"to": gpToId,
		"attrs": gpAttrs.duplicate(),
	})


func gpToDict() -> Dictionary:
	return {
		"meta": gpMeta.duplicate(),
		"nodes": gpNodes.duplicate(),
		"edges": gpEdges.duplicate(),
	}


static func gpFromDict(gpData: Dictionary) -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	if gpData.has("meta"): gpG.gpMeta = gpData["meta"].duplicate()
	if gpData.has("nodes"): gpG.gpNodes = gpData["nodes"].duplicate()
	if gpData.has("edges"): gpG.gpEdges = gpData["edges"].duplicate()
	return gpG
