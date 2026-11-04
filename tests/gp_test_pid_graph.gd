extends "res://tests/gp_test.gd"
# Headless regression tests for GPPIDGraph object graph (migrated from the legacy
# GUT stub tests/test_pid_graph.gd, which was never discovered by the runner because
# it does not match the gp_test_*.gd prefix).
# GPPIDGraph 对象图的 headless 回归测试（自遗留 GUT 桩 tests/test_pid_graph.gd 迁移而来；
# 该桩因不匹配 gp_test_*.gd 前缀而从未被运行器发现）。


# Ensure a node can be added and found (object graph, not dictionary).
# 验证节点可被新增并检索（对象图，而非字典）。
func gpTestAddNode() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-101", Vector2(10, 20)))
	gpCheck(gpG.gpNodes.size() == 1, "node count should be 1")
	gpCheck(gpG.gpNodes[0].gpInstanceId == "n1", "first node id should be n1")
	gpCheck(gpG.gpNodes[0].gpSymbolId == "pump", "first node symbol should be pump")
	gpCheck(gpG.gpNodes[0].gpPosition == Vector2(10, 20), "first node position should be (10,20)")


# Ensure an edge can be added and found (object graph, not dictionary).
# 验证连线可被新增并检索（对象图，而非字典）。
func gpTestAddEdge() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-101"))
	gpG.gpAddNode(gpG.gpNewNode("n2", "tank", "V-101"))
	gpG.gpAddEdge(gpG.gpNewEdge("e1", "n1", "n2"))
	gpCheck(gpG.gpEdges.size() == 1, "edge count should be 1")
	gpCheck(gpG.gpEdges[0].gpFromRef.get("node_id", "") == "n1", "edge from should be n1")
	gpCheck(gpG.gpEdges[0].gpToRef.get("node_id", "") == "n2", "edge to should be n2")


# Ensure to_dict / from_dict round-trips through the object graph.
# 验证 to_dict / from_dict 可经对象图往返。
func gpTestRoundTrip() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-101", Vector2(1, 2)))
	var gpD: Dictionary = gpG.gpToDict()
	gpCheck(gpD["nodes"][0]["instance_id"] == "n1", "dict node id should be n1")
	var gpG2: GPPIDGraph = GPPIDGraph.gpFromDict(gpD)
	gpCheck(gpG2.gpNodes.size() == 1, "restored node count should be 1")
	gpCheck(gpG2.gpNodes[0].gpInstanceId == "n1", "restored node id should be n1")
	gpCheck(gpG2.gpNodes[0].gpPosition == Vector2(1, 2), "restored node position should be (1,2)")


# Ensure removing a node also removes its edges.
# 验证删除节点会同时删除其关联边。
func gpTestRemoveWithEdges() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-101"))
	gpG.gpAddNode(gpG.gpNewNode("n2", "tank", "V-101"))
	gpG.gpAddEdge(gpG.gpNewEdge("e1", "n1", "n2"))
	gpG.gpRemoveNodeWithEdges("n1")
	gpCheck(gpG.gpNodes.size() == 1, "one node should remain")
	gpCheck(gpG.gpEdges.size() == 0, "edge touching n1 should be removed")


# Duplicate appends are refused (root cause of the 2026-11-04 move_child OOB: a duplicated
# entry makes the render binder's paint order longer than its distinct view set).
# 拒绝重复追加（2026-11-04 move_child 越界的根因：重复条目使渲染绑定器的绘制序
# 长于其去重视图集）。
func gpTestAddNodeRefusesDuplicates() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = gpG.gpNewNode("n1", "pump", "P-101")
	gpCheck(gpG.gpAddNode(gpN), "first add of a fresh node succeeds")
	# Same object twice.
	# 同一对象追加两次。
	gpCheck(not gpG.gpAddNode(gpN), "re-adding the SAME object is refused")
	gpCheck(gpG.gpNodes.size() == 1, "and the list is unchanged")
	# A different object claiming an occupied instance id is equally corrupting.
	# 另一对象占用已占用的实例 id 同样是污染。
	var gpClone: GPPIDNode = gpG.gpNewNode("n1", "pump", "P-101-COPY")
	gpCheck(not gpG.gpAddNode(gpClone), "a second object with the same id is refused")
	gpCheck(gpG.gpNodes.size() == 1, "still unchanged")
	# Undo compatibility: after a REAL remove, re-adding the same object must work.
	# 撤销兼容：真正删除之后，重加同一对象必须可行。
	gpG.gpRemoveNode("n1")
	gpCheck(gpG.gpAddNode(gpN), "re-add after remove succeeds (undo path)")
	gpCheck(gpG.gpNodes.size() == 1, "and the node is back exactly once")
