extends "res://tests/gp_test.gd"
# Headless tests for the port-aware edge model (P1 of the connection feature).
# 连线功能 P1 —— 端口感知边模型的 headless 测试。
#
# The load-bearing promise under test here is BACKWARD COMPATIBILITY: an archive written
# before P1 has edges with only {id, from, to}. Those must keep reading exactly as they did,
# because re-opening an old *.pid.json and silently shifting every pipe onto a port would be
# a data-integrity defect, not a cosmetic one.
# 此处承重的是「向后兼容」这一承诺：P1 之前写入的存档其边只有 {id, from, to}。它们读回来必须
# 与从前完全一致 —— 重新打开旧 *.pid.json 时把每条管线悄悄挪到端口上，是数据完整性缺陷，
# 而非外观问题。


# A legacy pack entry has no "type" key, so the purpose defaults to NOZZLE. That reproduces
# the pre-P1 behaviour: every port was a process nozzle and nothing was refused.
# 旧图元包条目无 "type" 键，故用途默认为 NOZZLE。这复现了 P1 之前的行为：
# 所有端口都是工艺管口，没有任何连接被拒绝。
func gpTestPortTypeDefaultsToNozzle() -> void:
	var gpP: GPPort = GPPort.new()
	gpP.gpFromDict({"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0]})
	gpEq(gpP.gpType, GPPort.GP_NOZZLE, "legacy port without a type key defaults to NOZZLE")


func gpTestPortRoundTripKeepsType() -> void:
	var gpP: GPPort = GPPort.gpMake("sig", Vector2(0.5, 0.0), Vector2(0.0, -1.0), GPPort.GP_SIGNAL)
	var gpP2: GPPort = GPPort.new()
	gpP2.gpFromDict(gpP.gpToDict())
	gpEq(gpP2.gpName, "sig", "name survives the round-trip")
	gpEq(gpP2.gpType, GPPort.GP_SIGNAL, "type survives the round-trip")
	gpApprox(gpP2.gpPos.x, 0.5, 0.0001, "pos.x survives the round-trip")
	gpApprox(gpP2.gpDir.y, -1.0, 0.0001, "dir.y survives the round-trip")


# The three-argument call sites that existed before P1 must keep meaning NOZZLE.
# P1 之前的三实参调用点必须仍表示 NOZZLE。
func gpTestPortMakeDefaults() -> void:
	gpEq(GPPort.gpMake("in", Vector2.ZERO).gpType, GPPort.GP_NOZZLE,
		"gpMake without a type still yields NOZZLE")


# ---- legacy archive shape ----

func gpTestLegacyEdgeReadsUnchanged() -> void:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpFromDict({"id": "e1", "from": "n1", "to": "n2"})
	gpEq(gpE.gpInstanceId, "e1", "legacy id key is honoured")
	gpEq(gpE.gpFromRef.get("node_id", ""), "n1", "legacy from becomes node_id")
	gpEq(gpE.gpFromRef.get("port_id", ""), "", "legacy edge has no port_id")
	gpEq(gpE.gpKind, GPPIDEdge.GP_PROCESS, "legacy edge defaults to PROCESS")
	gpEq(gpE.gpSignalType, "", "legacy edge has no signal type")
	gpCheck(gpE.gpOrtho, "legacy edge defaults to orthogonal routing")
	gpCheck(gpE.gpRouting.is_empty(), "legacy edge has no waypoints")


func gpTestLegacyEdgeRoundTripIsStable() -> void:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpFromDict({"id": "e1", "from": "n1", "to": "n2"})
	var gpD: Dictionary = gpE.gpToDict()
	# The old reader must still find what it needs in the new output.
	# 旧版读取器必须仍能在新版输出里找到它需要的字段。
	gpEq(gpD.get("instance_id", ""), "e1", "new shape keeps instance_id")
	gpEq((gpD.get("from_ref", {}) as Dictionary).get("node_id", ""), "n1",
		"new shape keeps the from node")


# ---- dangling ends ----

func gpTestDanglingEndRoundTrip() -> void:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpFromDict({
		"instance_id": "e9",
		"from_ref": {"node_id": "n1", "port_id": "out"},
		"to_ref": {"node_id": "", "port_id": "", "point": [120.0, 240.0]},
		"kind": "PROCESS",
	})
	gpCheck(gpE.gpIsDangling(false), "to end with no node but a point is dangling")
	gpCheck(not gpE.gpIsDangling(true), "from end bound to a node is not dangling")
	var gpP: Vector2 = gpE.gpDanglingPoint(false)
	gpApprox(gpP.x, 120.0, 0.0001, "dangling x survives the round-trip")
	gpApprox(gpP.y, 240.0, 0.0001, "dangling y survives the round-trip")
	# And it must serialize back out unchanged. / 且必须原样序列化回去。
	var gpOut: Dictionary = gpE.gpToDict()
	var gpToRef: Dictionary = gpOut.get("to_ref", {}) as Dictionary
	gpEq(str(gpToRef.get("node_id", "x")), "", "dangling end serializes with an empty node_id")
	gpCheck(gpToRef.has("point"), "dangling end serializes its point")


func gpTestSetDanglingPointMovesOnlyFreeEnds() -> void:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpFromRef = {"node_id": "n1", "port_id": "out"}
	gpE.gpToRef = {"node_id": "", "port_id": "", "point": [0.0, 0.0]}
	gpE.gpSetDanglingPoint(false, Vector2(10.0, 20.0))
	gpApprox(gpE.gpDanglingPoint(false).x, 10.0, 0.0001, "free end moves")
	gpE.gpSetDanglingPoint(true, Vector2(99.0, 99.0))
	gpCheck(not gpE.gpIsDangling(true), "a bound end cannot be turned into a free point")


# A half-written end (neither node nor point) must still load — as a dangling end at the
# origin — rather than producing an edge that can never be drawn.
# 半写的端点（既无 node 也无 point）必须仍能载入 —— 作为原点处的悬空端 ——
# 而不是产生一条永远无法绘制的边。
func gpTestBrokenEndSelfHeals() -> void:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpFromDict({"instance_id": "e7", "from_ref": {}, "to_ref": {}})
	gpCheck(gpE.gpIsDangling(true), "empty from_ref heals into a dangling end")
	gpCheck(gpE.gpIsDangling(false), "empty to_ref heals into a dangling end")
	gpCheck(bool(gpE.gpAttrs.get("broken_from", false)), "broken_from is flagged")
	gpCheck(bool(gpE.gpAttrs.get("broken_to", false)), "broken_to is flagged")
	gpCheck(gpE.gpDanglingPoint(true) != Vector2.INF, "healed end has a drawable position")


# ---- new fields ----

func gpTestSignalEdgeSerialization() -> void:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpInstanceId = "e3"
	gpE.gpKind = GPPIDEdge.GP_SIGNAL
	gpE.gpSignalType = "PNEUMATIC"
	gpE.gpOrtho = false
	var gpE2: GPPIDEdge = GPPIDEdge.new()
	gpE2.gpFromDict(gpE.gpToDict())
	gpEq(gpE2.gpKind, GPPIDEdge.GP_SIGNAL, "signal kind survives the round-trip")
	gpEq(gpE2.gpSignalType, "PNEUMATIC", "signal type survives the round-trip")
	gpCheck(not gpE2.gpOrtho, "straight-line flag survives the round-trip")


func gpTestWaypointsAreIntermediateOnly() -> void:
	# Documented invariant: gpRouting holds waypoints, never the endpoints. Endpoints are
	# resolved live from the ports, otherwise a moved symbol would tear its pipe away.
	# 记载下来的不变式：gpRouting 只存中间拐点，绝不存端点。端点由端口实时解析，
	# 否则移动图元会把管线从图元上撕开。
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpRouting = [Vector2(10, 0), Vector2(10, 50)]
	var gpE2: GPPIDEdge = GPPIDEdge.new()
	gpE2.gpFromDict(gpE.gpToDict())
	gpEq(gpE2.gpRouting.size(), 2, "two waypoints survive the round-trip")
	gpApprox(gpE2.gpRouting[1].y, 50.0, 0.0001, "waypoint coordinates survive")


# ---- graph factory ----

func gpTestNewEdgeExAcceptsEveryEndShape() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": "out"},
		{"node_id": "", "port_id": "", "point": [5.0, 6.0]},
		GPPIDEdge.GP_UTILITY, "", "PL-1001")
	gpEq(gpE.gpKind, GPPIDEdge.GP_UTILITY, "factory sets the kind")
	gpEq(gpE.gpTag, "PL-1001", "factory sets the tag")
	gpCheck(gpE.gpIsDangling(false), "factory keeps the dangling end")
	gpEq(gpE.gpFromRef.get("port_id", ""), "out", "factory keeps the port id")


func gpTestInsertEdgeRestoresIndex() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpA: GPPIDEdge = gpG.gpNewEdge("e1", "n1", "n2")
	var gpB: GPPIDEdge = gpG.gpNewEdge("e2", "n2", "n3")
	gpG.gpAddEdge(gpA)
	gpG.gpAddEdge(gpB)
	gpG.gpRemoveEdge("e1")
	gpEq(gpG.gpEdges.size(), 1, "one edge remains after removal")
	# Undo must put it back where it was, not at the end.
	# 撤销必须把它放回原处，而不是追加到末尾。
	gpG.gpInsertEdge(gpA, 0)
	gpEq(gpG.gpEdges.size(), 2, "edge is back")
	gpEq(gpG.gpEdges[0].gpInstanceId, "e1", "edge is back at its original index")


func gpTestMetaVersionBumped() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpEq(gpG.gpMeta.get("version", ""), "1.1", "new graphs are written as version 1.1")
