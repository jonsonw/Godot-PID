extends "res://tests/gp_test.gd"
# Headless tests for the two "symbol dropped/moved onto a line" features (Feature 1 = move
# offers the same reroute/split choice as placement; Feature 2 = deleting such a symbol
# restores the original line in ONE undo step).
# 「图元压到连线」两项功能的 headless 测试（功能 1：移动图元与放置一样弹出「绕行 / 拆分」选择；
# 功能 2：删除此类图元在「一个撤销步」内还原原始连线）。
#
# UI-coupled pieces (gpRerouteAround / gpSplitThroughSymbol / the move-detection in select_tool)
# are exercised through their pure model/command consequences here; the wiring that calls them
# is covered by the compile gate.
# 与 UI 耦合的部分（gpRerouteAround / gpSplitThroughSymbol / select_tool 的移动检测）在此只测其
# 纯模型 / 命令结果；调用它们的接线由编译门禁覆盖。

# Fixture: N1 -(E)- N2 plus a symbol S sitting on the line. / 夹具：N1 -(E)- N2，线上还有一个图元 S。
func _mkLine() -> Array:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-101", Vector2(0, 0)))
	g.gpAddNode(g.gpNewNode("N2", "valve", "V-201", Vector2(100, 0)))
	g.gpAddEdge(g.gpNewEdge("E", "N1", "N2"))
	g.gpAddNode(g.gpNewNode("S", "vessel", "T-1", Vector2(50, 0)))
	var svc: GPEditService = GPEditService.new()
	svc.gpBindGraph(g, GPIdGen.new())
	var ctx: GPCommandContext = svc.gpCtx
	var gpOut: Array = [g, svc, ctx]
	return gpOut


# A split state: the original E is gone, replaced by E1 (N1 -> S.in) and E2 (S.out -> N2).
# 拆分态：原边 E 已不在，被 E1 (N1 -> S.in) 与 E2 (S.out -> N2) 取代。
func _mkSplitState(g: GPPIDGraph) -> Dictionary:
	g.gpRemoveEdge("E")
	g.gpAddEdge(g.gpNewEdgeEx("E1", {"node_id": "N1", "port_id": ""},
		{"node_id": "S", "port_id": "in"}, "PROCESS"))
	g.gpAddEdge(g.gpNewEdgeEx("E2", {"node_id": "S", "port_id": "out"},
		{"node_id": "N2", "port_id": ""}, "PROCESS"))
	# The original edge's saved dict + z-index, captured at split time.
	# 拆分时捕获的原边字典与层序。
	var gpOrig: Dictionary = g.gpNewEdge("E", "N1", "N2").gpToDict()
	return {"orig": gpOrig, "index": 0}


# ---------------------------------------------------------------- registry helpers / 注册表

func gpTestRecordDropAndRemove() -> void:
	# gpRecordDrop stamps a monotonic "_rid"; gpRemoveDrop clears exactly that record.
	# gpRecordDrop 盖上单调 "_rid"；gpRemoveDrop 精确清除该记录。
	var f: Array = _mkLine()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var gpRid: int = g.gpRecordDrop("S", {"kind": "reroute", "edge_id": "E", "orig_routing": []})
	gpEq(g.gpDropRecords("S").size(), 1, "record present after gpRecordDrop")
	gpEq(int(g.gpDropRecords("S")[0].get("_rid", -1)), gpRid, "record carries the stamped rid")
	g.gpRemoveDrop("S", gpRid)
	gpEq(g.gpDropRecords("S").size(), 0, "record gone after gpRemoveDrop")


func gpTestClearDrops() -> void:
	# gpClearDrops removes every record for a symbol (called once the delete has replayed them).
	# gpClearDrops 移除某图元的全部记录（删除重放后调用）。
	var f: Array = _mkLine()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	g.gpRecordDrop("S", {"kind": "reroute", "edge_id": "E", "orig_routing": []})
	g.gpRecordDrop("S", {"kind": "split", "orig": {}, "orig_index": 0})
	gpEq(g.gpDropRecords("S").size(), 2, "two records recorded")
	g.gpClearDrops("S")
	gpEq(g.gpDropRecords("S").size(), 0, "both cleared by gpClearDrops")


# ---------------------------------------------------------------- record command undo / 落点记录命令撤销

func gpTestSetDropRestoreCommandUndoRedo() -> void:
	# The drop record is itself undoable, so undoing the drop also forgets the restore history.
	# 落点记录本身可撤销，故撤销落点也会一并清除恢复历史。
	var f: Array = _mkLine()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var svc: GPEditService = f[1] as GPEditService
	svc.gpRecordDrop("S", {"kind": "reroute", "edge_id": "E", "orig_routing": []})
	gpEq(g.gpDropRecords("S").size(), 1, "record present")
	svc.gpUndo()
	gpEq(g.gpDropRecords("S").size(), 0, "undo clears the record")
	svc.gpRedo()
	gpEq(g.gpDropRecords("S").size(), 1, "redo re-creates the record")


# ---------------------------------------------------------------- reroute restore / 绕行还原

func gpTestRerouteRestoreReplaysAndReverses() -> void:
	# Deleting a rerouted symbol restores the pre-drop routing; undo brings the reroute back.
	# 删除被绕行的图元会还原落点前走线；撤销再回到绕行态。
	var f: Array = _mkLine()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var ctx: GPCommandContext = f[2] as GPCommandContext
	var gpPre: Array[Vector2] = [Vector2(50, -40)]  # original (pre-drop) bent path
	var gpPost: Array[Vector2] = [Vector2(50, 40)]   # rerouted around the symbol
	g.gpGetEdge("E").gpRouting = gpPre.duplicate()
	var gpRec: Dictionary = {"kind": "reroute", "edge_id": "E", "orig_routing": gpPre.duplicate()}
	var gpCmd: GPRestoreDroppedEdgesCommand = GPRestoreDroppedEdgesCommand.new({"S": [gpRec]})
	# Simulate the drop having rerouted the edge. / 模拟落点已把边绕开。
	g.gpGetEdge("E").gpRouting = gpPost.duplicate()
	gpCmd.gpExecute(ctx)
	gpEq(g.gpGetEdge("E").gpRouting, gpPre, "restore returns the original routing")
	gpCmd.gpUndo(ctx)
	gpEq(g.gpGetEdge("E").gpRouting, gpPost, "undo re-applies the post-drop routing")
	gpCmd.gpRedo(ctx)
	gpEq(g.gpGetEdge("E").gpRouting, gpPre, "redo restores the original routing again")


# ---------------------------------------------------------------- split delete integration / 拆分删除集成

func gpTestSplitDeleteRestoresOriginalEdge() -> void:
	# Full path: a symbol that split a line, when deleted, becomes ONE undo step that recreates
	# the original single edge with both ends' connections preserved; undo returns the split.
	# 完整路径：把一条线拆分的图元被删除时，合并为「一个撤销步」重建原单一连线（两端连接保留）；
	# 撤销则回到拆分态。
	var f: Array = _mkLine()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var svc: GPEditService = f[1] as GPEditService
	var ctx: GPCommandContext = f[2] as GPCommandContext
	var gpSplit: Dictionary = _mkSplitState(g)
	# Record the drop so the delete command can find it by the symbol's id.
	# 记录落点，使删除命令能按图元 id 找到它。
	svc.gpRecordDrop("S", {"kind": "split", "orig": gpSplit["orig"], "orig_index": int(gpSplit["index"])})
	gpEq(g.gpEdges.size(), 2, "two child edges after the (simulated) split")
	# Delete the symbol. / 删除该图元。
	gpCheck(svc.gpDeleteSelection(["S"], [], []), "delete recorded")
	gpEq(g.gpGetNode("S"), null, "symbol removed")
	gpEq(g.gpGetEdge("E1"), null, "child edge 1 cascade-removed")
	gpEq(g.gpGetEdge("E2"), null, "child edge 2 cascade-removed")
	gpEq(g.gpGetEdge("E") != null, true, "original edge recreated")
	gpEq(str(g.gpGetEdge("E").gpFromRef.get("node_id", "")), "N1", "original from-end preserved")
	gpEq(str(g.gpGetEdge("E").gpToRef.get("node_id", "")), "N2", "original to-end preserved")
	gpEq(g.gpDropRecords("S").size(), 0, "restore history cleared with the symbol")
	# Undo: back to the split state. / 撤销：回到拆分态。
	svc.gpUndo()
	gpEq(g.gpGetNode("S") != null, true, "symbol restored by undo")
	gpEq(g.gpGetEdge("E1") != null, true, "child edge 1 restored")
	gpEq(g.gpGetEdge("E2") != null, true, "child edge 2 restored")
	gpEq(g.gpGetEdge("E"), null, "original edge removed again")
	gpEq(g.gpDropRecords("S").size(), 1, "restore history re-recorded by undo")
	# Redo: original line restored once more. / 重做：再次还原原连线。
	svc.gpRedo()
	gpEq(g.gpGetEdge("E") != null, true, "original edge recreated on redo")
	gpEq(g.gpGetEdge("E1"), null, "child edge gone on redo")


# ---------------------------------------------------------------- serialization / 序列化

func gpTestDropRestoreSerializes() -> void:
	# The registry round-trips through gpToDict / gpFromDict so a save+reload still restores.
	# 注册表经 gpToDict / gpFromDict 往返，使存档重载后删除仍可还原。
	var f: Array = _mkLine()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	g.gpRecordDrop("S", {"kind": "reroute", "edge_id": "E", "orig_routing": [Vector2(50, 50)]})
	g.gpRecordDrop("S", {"kind": "split", "orig": g.gpNewEdge("E", "N1", "N2").gpToDict(), "orig_index": 0})
	var gpDict: Dictionary = g.gpToDict()
	gpEq(gpDict.has("drop_restore"), true, "drop_restore written to the archive")
	var gpReload: GPPIDGraph = GPPIDGraph.gpFromDict(gpDict)
	gpEq(gpReload.gpDropRecords("S").size(), 2, "records reloaded")
	# The reroute routing survives as [x,y] pairs. / 绕行走线以 [x,y] 数组对留存。
	var gpFound: bool = false
	for gpR in gpReload.gpDropRecords("S"):
		if gpR.get("kind", "") == "reroute":
			gpFound = (gpR.get("orig_routing", []) as Array[Vector2]) == [Vector2(50, 50)]
	gpCheck(gpFound, "reroute routing round-trips as Vector2")
	# A freshly recorded entry must not collide with the loaded rids. / 新记录 id 不得与载入 rid 冲突。
	var gpBefore: int = gpReload.gpDropRecords("S")[0].get("_rid", 0)
	gpReload.gpRecordDrop("S", {"kind": "reroute", "edge_id": "E", "orig_routing": []})
	var gpAfter: int = gpReload.gpDropRecords("S")[-1].get("_rid", 0)
	gpCheck(gpAfter > gpBefore, "new record id exceeds the max loaded rid")


# ---------------------------------------------------------------- reroute delete integration / 绕行删除集成

func gpTestRerouteDeleteRestoresRouting() -> void:
	# Full path for a REROUTE: deleting the symbol that a line was rerouted around restores the
	# pre-drop routing in one undo step; both ends are unchanged (they were never touched).
	# 绕行的完整路径：删除被绕开的图元在「一个撤销步」内还原落点前走线；两端不变（从未被触及）。
	var f: Array = _mkLine()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var svc: GPEditService = f[1] as GPEditService
	var gpPre: Array[Vector2] = [Vector2(50, -40)]
	var gpPost: Array[Vector2] = [Vector2(50, 40)]
	g.gpGetEdge("E").gpRouting = gpPre.duplicate()
	# Simulate the drop having rerouted the edge around the symbol. / 模拟落点已把边绕开图元。
	g.gpGetEdge("E").gpRouting = gpPost.duplicate()
	svc.gpRecordDrop("S", {"kind": "reroute", "edge_id": "E", "orig_routing": gpPre.duplicate()})
	gpCheck(svc.gpDeleteSelection(["S"], [], []), "delete recorded")
	gpEq(g.gpGetNode("S"), null, "symbol removed")
	gpEq(g.gpGetEdge("E") != null, true, "edge still present (ends unchanged)")
	gpEq(g.gpGetEdge("E").gpRouting, gpPre, "original routing restored on delete")
	gpEq(g.gpDropRecords("S").size(), 0, "restore history cleared with the symbol")
	svc.gpUndo()
	gpEq(g.gpGetNode("S") != null, true, "symbol restored by undo")
	gpEq(g.gpGetEdge("E").gpRouting, gpPost, "undo re-applies the rerouted routing")
	svc.gpRedo()
	gpEq(g.gpGetEdge("E").gpRouting, gpPre, "redo restores the original routing")


# ---------------------------------------------------------------- no-record delete unaffected / 无记录删除不受影响

func gpTestPlainDeleteWithoutRecordIsUnchanged() -> void:
	# A delete with NO drop history must behave exactly as before: one step, no extra replay.
	# 无落点历史的删除必须与从前完全一致：一步，无额重放。
	var f: Array = _mkLine()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var svc: GPEditService = f[1] as GPEditService
	gpEq(g.gpDropRecords("S").size(), 0, "no records to start")
	gpCheck(svc.gpDeleteSelection(["S"], [], []), "delete recorded")
	gpEq(g.gpGetNode("S"), null, "symbol removed")
	gpEq(g.gpGetEdge("E") != null, true, "line untouched by deleting an unrelated symbol")
	gpEq(g.gpEdges.size(), 1, "edge count unchanged")
