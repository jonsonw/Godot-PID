extends "res://tests/gp_test.gd"
# Headless tests for the six P3 edge commands (via GPEditService): connect / set-tag / set-routing
# / reconnect / delete-edges. Each is verified to round-trip through undo/redo, and the
# "pipe needs one bound end" refusal is checked. No canvas required (the service is the seam).
# 六个 P3 边命令（经 GPEditService）的 headless 测试：连线 / 改号 / 改布线 / 改接 / 删除边。
# 逐一验证可经撤销/重做往返，并检查「管道至少一端须连接」的拒绝。无需画布（服务即那条缝）。

func _mkSvc() -> Array:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-101", Vector2(10, 10)))
	g.gpAddNode(g.gpNewNode("N2", "valve", "V-201", Vector2(100, 10)))
	var svc: GPEditService = GPEditService.new()
	svc.gpBindGraph(g, GPIdGen.new())
	var gpOut: Array = [g, svc]
	return gpOut


# A connected PROCESS pipe mints a line number; a SIGNAL line does not (by convention).
# 一条 PROCESS 管道会铸出管线号；SIGNAL 线按惯例不带号。
func gpTestConnectProcessMintsTag() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var id: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "p1"},
		{"node_id": "N2", "port_id": "p2"}, GPPIDEdge.GP_PROCESS)
	gpCheck(id != "", "process pipe created")
	gpEq(g.gpEdges.size(), 1, "one edge in the graph")
	var e: GPPIDEdge = g.gpGetEdge(id)
	gpEq(e.gpKind, GPPIDEdge.GP_PROCESS, "kind is PROCESS")
	gpCheck(e.gpTag != "", "process pipe mints a line number")


func gpTestConnectSignalNoTag() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var id: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "s1"},
		{"node_id": "N2", "port_id": "s2"}, GPPIDEdge.GP_SIGNAL, "ELECTRIC")
	var e: GPPIDEdge = g.gpGetEdge(id)
	gpEq(e.gpKind, GPPIDEdge.GP_SIGNAL, "kind is SIGNAL")
	gpEq(e.gpSignalType, "ELECTRIC", "signal medium stored on the edge")
	gpEq(e.gpTag, "", "signal line carries no line number")


func gpTestSetEdgeTagUndoable() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var id: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "p1"},
		{"node_id": "N2", "port_id": "p2"}, GPPIDEdge.GP_PROCESS)
	var e: GPPIDEdge = g.gpGetEdge(id)
	var gpFirst: String = e.gpTag
	svc.gpSetEdgeTag(id, "PL-999")
	gpEq(e.gpTag, "PL-999", "tag is set")
	gpEq(e.gpAttrs.get("tag_manual", false), true, "a manual tag is flagged so renumber skips it")
	svc.gpUndo()
	gpEq(e.gpTag, gpFirst, "undo restores the original (minted) tag")
	svc.gpRedo()
	gpEq(e.gpTag, "PL-999", "redo re-applies the manual tag")


func gpTestSetEdgeRoutingUndoable() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var id: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "p1"},
		{"node_id": "N2", "port_id": "p2"}, GPPIDEdge.GP_PROCESS)
	var e: GPPIDEdge = g.gpGetEdge(id)
	svc.gpSetEdgeRouting(id, [Vector2(50, 50), Vector2(50, 60)])
	gpEq(e.gpRouting.size(), 2, "routing waypoints set")
	svc.gpUndo()
	gpEq(e.gpRouting.size(), 0, "undo clears the routing")
	svc.gpRedo()
	gpEq(e.gpRouting.size(), 2, "redo restores the routing")


func gpTestReconnectEdgeUndoable() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var id: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "p1"},
		{"node_id": "N2", "port_id": "p2"}, GPPIDEdge.GP_PROCESS)
	var e: GPPIDEdge = g.gpGetEdge(id)
	# Reconnect the FROM end to a dangling point. / 把起点改接到一个悬空点。
	svc.gpReconnectEdge(id, true, {"node_id": "", "port_id": "", "point": [200.0, 200.0]})
	gpCheck(e.gpIsDangling(true), "from end is now dangling")
	gpEq(str(e.gpToRef.get("node_id")), "N2", "the other end is untouched")
	svc.gpUndo()
	gpEq(str(e.gpFromRef.get("node_id")), "N1", "undo restores the original from-ref")
	svc.gpRedo()
	gpCheck(e.gpIsDangling(true), "redo re-dangles the from end")


func gpTestDeleteEdgesUndoable() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var id: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "p1"},
		{"node_id": "N2", "port_id": "p2"}, GPPIDEdge.GP_PROCESS)
	svc.gpDeleteEdges([id])
	gpEq(g.gpEdges.size(), 0, "edge deleted")
	svc.gpUndo()
	gpEq(g.gpEdges.size(), 1, "undo restores the edge")
	svc.gpRedo()
	gpEq(g.gpEdges.size(), 0, "redo removes the edge again")


func gpTestConnectRefusesBothDangling() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var id: String = svc.gpConnectEdge({"node_id": "", "port_id": "", "point": [0.0, 0.0]},
		{"node_id": "", "port_id": "", "point": [1.0, 1.0]}, GPPIDEdge.GP_PROCESS)
	gpEq(id, "", "both ends dangling is refused")
	gpEq(g.gpEdges.size(), 0, "no edge was added")
	gpEq(svc.gpCanUndo(), false, "a refused connect records no undo step")


# W4: deleting a SELECTED edge via the mixed-selection command is ONE undo step (Del on a pipe).
# W4：经混合选择命令删除「选中的边」是一个撤销步（在管线上按 Del）。
func gpTestDeleteSelectionDeletesEdgeInOneStep() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var id: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "p1"},
		{"node_id": "N2", "port_id": "p2"}, GPPIDEdge.GP_PROCESS)
	gpEq(g.gpEdges.size(), 1, "one edge before delete")
	# Select the edge only (no node) and delete it: must be a SINGLE undo step.
	# 仅选中该边（不含节点）并删除：必须是一个撤销步。
	svc.gpDeleteSelection([], [], [id])
	gpEq(g.gpEdges.size(), 0, "edge removed by selection delete")
	gpCheck(svc.gpCanUndo(), "one undo step is recorded")
	svc.gpUndo()
	gpEq(g.gpEdges.size(), 1, "undo restores the edge (single step)")
	gpEq(g.gpGetEdge(id).gpInstanceId, id, "restored edge keeps its id")
	svc.gpRedo()
	gpEq(g.gpEdges.size(), 0, "redo removes the edge again")


# W4: a node + a standalone edge delete together in one step; the edge reappears on undo.
# W4：节点与一条独立边一同删除为一步；撤销后该边重新出现。
func gpTestDeleteSelectionNodeAndEdgeOneStep() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var id: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "p1"},
		{"node_id": "N2", "port_id": "p2"}, GPPIDEdge.GP_PROCESS)
	# Delete node N1 (which also drops its attached edge) together with nothing else.
	# 删除节点 N1（其附属边一并移除）。
	svc.gpDeleteSelection(["N1"], [], [])
	gpEq(g.gpGetNode("N1") == null, true, "node N1 removed")
	gpEq(g.gpEdges.size(), 0, "attached edge removed with the node")
	svc.gpUndo()
	gpEq(g.gpGetNode("N1") != null, true, "undo restores the node")
	gpEq(g.gpEdges.size(), 1, "undo restores the attached edge")
	gpEq(g.gpGetEdge(id).gpInstanceId, id, "restored edge keeps its id")
