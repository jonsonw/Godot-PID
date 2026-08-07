class_name PIDGraph
extends Resource

## P&ID 拓扑数据内核：节点-边图。
## 2D 画布、3D 联动、清单导出都读取这个 Resource。

@export var meta: Dictionary = {
	"version": "1.0",
	"title": "",
	"sheets": 1,
}

@export var nodes: Array[Dictionary] = []
@export var edges: Array[Dictionary] = []


func add_node(id: String, type: String, label: String, pos: Vector2 = Vector2.ZERO, attrs: Dictionary = {}) -> void:
	nodes.append({
		"id": id,
		"type": type,
		"label": label,
		"pos": [pos.x, pos.y],
		"attrs": attrs.duplicate(),
	})


func add_edge(id: String, from_id: String, to_id: String, attrs: Dictionary = {}) -> void:
	edges.append({
		"id": id,
		"from": from_id,
		"to": to_id,
		"attrs": attrs.duplicate(),
	})


func to_dict() -> Dictionary:
	return {
		"meta": meta.duplicate(),
		"nodes": nodes.duplicate(),
		"edges": edges.duplicate(),
	}


static func from_dict(data: Dictionary) -> PIDGraph:
	var g := PIDGraph.new()
	if data.has("meta"): g.meta = data["meta"].duplicate()
	if data.has("nodes"): g.nodes = data["nodes"].duplicate()
	if data.has("edges"): g.edges = data["edges"].duplicate()
	return g
