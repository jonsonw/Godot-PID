extends "res://tests/gp_test.gd"
# M10 symbol swap (GPReplaceSymbolCommand via GPEditService): change the type, keep the identity.
# M10 图元更换（经 GPEditService 的 GPReplaceSymbolCommand）：换类型，不换身份。
#
# The contract under test / 被测契约：
#   1. gpUid / gpTag / gpProps / position survive — a pump that becomes another model is still
#      the same piece of equipment, with the same tag on the drawing and in the DCS point list.
#      gpUid / 位号 / 属性 / 坐标全部保留 —— 换了型号的泵仍是同一台设备，
#      图纸上与 DCS 点表里的位号都不变。
#   2. An edge whose port name the NEW symbol does not declare DOWNGRADES to the node centre
#      (still connected) and is reported in gpLastSwapWarning — decided 2026-09-09.
#      新图元未声明其端口名的边**降级**到图元中心（仍连通），并记入 gpLastSwapWarning
#      —— 2026-09-09 拍板。
#   3. Undo restores both the symbol id and every port name verbatim.
#      撤销同时还原图元 id 与每个端口名。


func _gpDef(gpId: String, gpPortNames: Array[String]) -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = gpId
	gpD.gpDisplayName = gpId
	for gpN in gpPortNames:
		var gpP: GPPort = GPPort.new()
		gpP.gpName = gpN
		gpD.gpPorts.append(gpP)
	return gpD


# N1 is a "pumpA" (ports in/out); two pipes leave it, one on each port.
# N1 是一台 "pumpA"（端口 in/out）；两条管线从它出发，各占一个端口。
func _mkSvc() -> Array:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pumpA", "P-1001", Vector2(10, 10)))
	g.gpAddNode(g.gpNewNode("N2", "valve", "V-2001", Vector2(100, 10)))
	var svc: GPEditService = GPEditService.new()
	svc.gpBindGraph(g, GPIdGen.new())
	var gpA: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "out"},
		{"node_id": "N2", "port_id": "p1"}, GPPIDEdge.GP_PROCESS)
	var gpB: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "in"},
		{"node_id": "N2", "port_id": "p2"}, GPPIDEdge.GP_PROCESS)
	var gpOut: Array = [g, svc, gpA, gpB]
	return gpOut


# ---- 1. identity survives / 身份保留 ----

func gpTestSwapKeepsUidTagAndProps() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var gpN: GPPIDNode = g.gpGetNode("N1")
	gpN.gpUid = "doc1-n17"
	gpN.gpProps["rated_flow"] = 80.0
	svc.gpReplaceSymbol("N1", _gpDef("pumpB", ["in", "out"]))
	gpEq(gpN.gpSymbolId, "pumpB", "the symbol changed")
	gpEq(gpN.gpUid, "doc1-n17", "uid is untouched — edges and off-page refs still resolve")
	gpEq(gpN.gpTag, "P-1001", "the tag is untouched — the DCS point list still matches")
	gpEq(float(gpN.gpProps["rated_flow"]), 80.0, "property values survive the swap")
	gpEq(gpN.gpPosition, Vector2(10, 10), "the instance does not move")


func gpTestSwappingOntoTheSameSymbolIsANoOp() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	gpEq(svc.gpReplaceSymbol("N1", _gpDef("pumpA", ["in", "out"])), false,
		"re-selecting the current symbol produces no undo step")


# ---- 2. port reconciliation / 端口对账 ----

func gpTestMatchingPortsAreKept() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	svc.gpReplaceSymbol("N1", _gpDef("pumpB", ["in", "out"]))
	gpEq(str(g.gpGetEdge(f[2]).gpFromRef.get("port_id", "")), "out",
		"a port the new symbol still declares keeps its exact nozzle")
	gpEq(svc.gpLastSwapWarning.size(), 0, "no warning when every port matches")


# "Allowed but warned": the pipe keeps its node reference and merely loses the nozzle, so the
# connection is never silently severed — the user decides whether to re-seat it.
# 「允许但警告」：管线保住节点引用，只是失去了管口，连接绝不会被静默切断
# —— 是否重新落位由用户决定。
func gpTestMissingPortDowngradesToCentreAndWarns() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	# pumpC has "in" but NOT "out": the pipe drawn on "out" must degrade, not disappear.
	# pumpC 有 "in" 但没有 "out"：画在 "out" 上的那条管线必须降级，而不是消失。
	svc.gpReplaceSymbol("N1", _gpDef("pumpC", ["in"]))
	gpEq(str(g.gpGetEdge(f[2]).gpFromRef.get("port_id", "")), "",
		"the missing port is cleared — GPPortResolver then falls back to the node centre")
	gpEq(str(g.gpGetEdge(f[2]).gpFromRef.get("node_id", "")), "N1",
		"and the edge still points at the node: the connection is NOT severed")
	gpEq(str(g.gpGetEdge(f[3]).gpFromRef.get("port_id", "")), "in",
		"the port that still exists is untouched")
	gpEq(svc.gpLastSwapWarning.size(), 1, "exactly one downgrade is reported for the shell to warn about")


# ---- 3. undo / redo / 撤销与重做 ----

func gpTestUndoRestoresSymbolAndPorts() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	svc.gpReplaceSymbol("N1", _gpDef("pumpC", ["in"]))
	svc.gpUndo()
	gpEq(g.gpGetNode("N1").gpSymbolId, "pumpA", "undo restores the old symbol")
	gpEq(str(g.gpGetEdge(f[2]).gpFromRef.get("port_id", "")), "out",
		"undo restores the downgraded port name verbatim")
	gpEq(str(g.gpGetEdge(f[3]).gpFromRef.get("port_id", "")), "in", "and leaves the other one alone")


func gpTestRedoReappliesTheSwap() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	svc.gpReplaceSymbol("N1", _gpDef("pumpC", ["in"]))
	svc.gpUndo()
	svc.gpRedo()
	gpEq(g.gpGetNode("N1").gpSymbolId, "pumpC", "redo re-applies the new symbol")
	gpEq(str(g.gpGetEdge(f[2]).gpFromRef.get("port_id", "")), "",
		"redo downgrades the missing port again")


# ---- 4. guards / 护栏 ----

func gpTestGuardsRejectBadInput() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	gpEq(svc.gpReplaceSymbol("", _gpDef("pumpB", ["in"])), false, "an empty node id is refused")
	gpEq(svc.gpReplaceSymbol("N1", null), false, "a null symbol is refused")
	gpEq(svc.gpReplaceSymbol("NOPE", _gpDef("pumpB", ["in"])), false, "an unknown node is refused")


func gpTestSwapOntoAPortlessSymbolDowngradesEverything() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	svc.gpReplaceSymbol("N1", _gpDef("tank", []))
	gpEq(svc.gpLastSwapWarning.size(), 2, "both pipes degrade when the new symbol has no ports")
	gpEq(str(g.gpGetEdge(f[2]).gpFromRef.get("node_id", "")), "N1", "but both are still connected")
	gpEq(str(g.gpGetEdge(f[3]).gpFromRef.get("node_id", "")), "N1", "…to the same node")
