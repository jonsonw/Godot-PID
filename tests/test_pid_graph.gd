# GUT test stub for PIDGraph (Dev Guide §4.5).
# PIDGraph 的 GUT 测试桩（开发指南 §4.5）。
# Intended runner is GUT. Until it is installed, this uses the built-in assert() so the
# script parses and can be run standalone. Once GUT is added, change `extends Node` back to
# `extends GutTest` and swap assert() for assert_eq()/assert_true().
# 预期测试运行器为 GUT。在 GUT 安装前，本脚本用内置 assert() 以便解析并能独立运行。
# 待 GUT 接入后，将 `extends Node` 改回 `extends GutTest`，并把 assert() 换回 assert_eq()/assert_true()。
extends Node

# Ensure a node can be added and found.
# 验证节点可被新增并检索。
func gpTestAddNode() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode("n1", "pump", "P-101", Vector2(10, 20))
	assert(gpG.gpNodes.size() == 1, "node count should be 1")
	assert(gpG.gpNodes[0]["id"] == "n1", "first node id should be n1")


# Ensure an edge can be added and found.
# 验证连线可被新增并检索。
func gpTestAddEdge() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode("n1", "pump", "P-101")
	gpG.gpAddNode("n2", "tank", "V-101")
	gpG.gpAddEdge("e1", "n1", "n2")
	assert(gpG.gpEdges.size() == 1, "edge count should be 1")
	assert(gpG.gpEdges[0]["from"] == "n1", "edge from should be n1")


# Ensure to_dict / from_dict round-trips.
# 验证 to_dict / from_dict 可往返。
func gpTestRoundTrip() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode("n1", "pump", "P-101", Vector2(1, 2))
	var gpD: Dictionary = gpG.gpToDict()
	var gpG2: GPPIDGraph = GPPIDGraph.gpFromDict(gpD)
	assert(gpG2.gpNodes.size() == 1, "restored node count should be 1")
	assert(gpG2.gpNodes[0]["id"] == "n1", "restored node id should be n1")
