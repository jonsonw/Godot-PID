extends Node
# Copyright © 2026 Jonson Wang
# D06: deterministic 900-node model benchmark. Headless cannot honestly measure GPU draw calls
# or 60 fps panning, so this records the parts a headless run CAN prove: build, serialize,
# parse and a synthetic edit pass. The docs must state that boundary.
# D06：可复现的 900 节点模型基准。headless 无法诚实测量 GPU draw call 或 60fps 平移，
# 故只记录 headless 能证明的部分：构建、序列化、解析、一次合成编辑；文档必须写明边界。
#
# Usage:
#   HOME=/tmp/gpidhome godot --headless --script res://tools/gp_bench.gd

const NODE_COUNT: int = 900
const EDGE_COUNT: int = 450
const SHAPE_COUNT: int = 30


func _ready() -> void:
	_gpRun()


func _gpRun() -> void:
	var gpT0: int = Time.get_ticks_usec()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpIds: Array[String] = []
	for gpI in range(NODE_COUNT):
		var gpId: String = "N%04d" % gpI
		var gpN: GPPIDNode = gpG.gpNewNode(gpId, "DPUMP001", "P-%04d" % gpI,
			Vector2(float(gpI % 60) * 14.0, float(gpI / 60) * 12.0))
		gpG.gpAddNode(gpN)
		gpIds.append(gpId)
	var gpBuildUs: int = Time.get_ticks_usec() - gpT0
	var gpT1: int = Time.get_ticks_usec()
	for gpI in range(EDGE_COUNT):
		var gpA: String = gpIds[gpI % NODE_COUNT]
		var gpB: String = gpIds[(gpI * 7 + 3) % NODE_COUNT]
		var gpE: GPPIDEdge = gpG.gpNewEdgeEx("E%04d" % gpI,
			{"node_id": gpA, "port_id": "out"}, {"node_id": gpB, "port_id": "in"},
			GPPIDEdge.GP_PROCESS, "", "L-%04d" % gpI)
		gpG.gpAddEdge(gpE)
	var gpEdgeUs: int = Time.get_ticks_usec() - gpT1
	for gpI in range(SHAPE_COUNT):
		gpG.gpAddShape(GPShape.gpLine(
			Vector2(float(gpI) * 20.0, 0.0), Vector2(float(gpI) * 20.0 + 10.0, 10.0)))
	var gpT2: int = Time.get_ticks_usec()
	var gpDict: Dictionary = gpG.gpToDict()
	var gpSerializeUs: int = Time.get_ticks_usec() - gpT2
	var gpT3: int = Time.get_ticks_usec()
	var gpBack: GPPIDGraph = GPPIDGraph.gpFromDict(gpDict)
	var gpParseUs: int = Time.get_ticks_usec() - gpT3
	var gpT4: int = Time.get_ticks_usec()
	var gpEditCount: int = 0
	for gpI in range(100):
		var gpN: GPPIDNode = gpBack.gpGetNode("N%04d" % gpI)
		if gpN != null:
			gpN.gpPosition += Vector2(1, 1)
			gpBack.gpBumpRevision()
			gpEditCount += 1
	var gpEditUs: int = Time.get_ticks_usec() - gpT4
	var gpOut: Dictionary = {
		"nodes": NODE_COUNT, "edges": EDGE_COUNT, "shapes": SHAPE_COUNT,
		"build_us": gpBuildUs, "edges_us": gpEdgeUs,
		"serialize_us": gpSerializeUs, "parse_us": gpParseUs,
		"edit_100_us": gpEditUs, "edit_count": gpEditCount,
		"roundtrip_nodes": gpBack.gpNodes.size(), "roundtrip_edges": gpBack.gpEdges.size(),
		"revision": gpBack.gpRevision,
		"note": "headless model benchmark; no GPU draw-call / 60fps claim",
	}
	print(JSON.stringify(gpOut, "\t", true))
	get_tree().quit()
