extends "res://tests/gp_test.gd"
# Headless tests for GPPortResolver (P1 of the connection feature).
# 连线功能 P1 —— GPPortResolver 的 headless 测试。
#
# Two promises are guarded here:
# 此处守护两条承诺：
#   1. Port geometry has ONE owner. GPSymbolView draws the dot and GPEdgeView draws the pipe
#      end; if they computed the rotation/flip themselves they would drift apart the moment
#      either was fixed. / 端口几何只有一个持有者。
#   2. Resolution NEVER fails. A renamed or missing port degrades the pipe's look instead of
#      making the pipe vanish — that is what keeps "editing a symbol's ports cannot silently
#      break a connection" true even though edges now store port names.
#      解析绝不失败。端口改名或缺失只是让管线外观降级，而不是让管线消失 ——
#      这正是「边开始存端口名之后，编辑图元端口仍不会静默断连」成立的原因。


# A 64x48 valve with the standard in/out nozzles.
# 一台 64x48 的阀门，带标准 in/out 管口。
func _gpValveDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "valve_test"
	gpD.gpCategory = "valve"
	gpD.gpDefaultSize = Vector2(64.0, 48.0)
	gpD.gpPorts = [
		GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
	]
	return gpD


func _gpDefLookup() -> Callable:
	return func(gpSymbolId: String) -> GPSymbolDef:
		return _gpValveDef()


func _gpGraphWithNode(gpNode: GPPIDNode) -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpNode)
	return gpG


# ---- rotation and flip ----

# A valve rotated 90 degrees: "out" sits at local (32, 0), so in world space it must be
# (0, +32) below the node centre — not still off to the right.
# 旋转 90° 的阀门："out" 本地在 (32, 0)，故世界坐标应是节点中心正下方 (0, +32)，
# 而不是仍在右侧。
func gpTestRotatedPortWorldPosition() -> void:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "n1"
	gpN.gpSymbolId = "valve_test"
	gpN.gpPosition = Vector2(100.0, 100.0)
	gpN.gpRotationDeg = 90.0
	var gpG: GPPIDGraph = _gpGraphWithNode(gpN)
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpFromRef = {"node_id": "n1", "port_id": "out"}
	var gpR: Dictionary = GPPortResolver.gpResolveEnd(gpG, _gpDefLookup(), gpE, true,
		GPPort.GP_NOZZLE)
	gpApprox((gpR["pos"] as Vector2).x, 100.0, 0.001, "rotated out port keeps x at the centre")
	gpApprox((gpR["pos"] as Vector2).y, 132.0, 0.001, "rotated out port sits 32 below the centre")
	gpEq(str(gpR["why"]), "port", "an exact port id hit is reported as 'port'")


# Mirroring swaps left and right: "in" moves to where "out" used to be.
# 镜像使左右互换："in" 移到原本 "out" 的位置。
func gpTestFlippedPortSwapsSides() -> void:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "n1"
	gpN.gpSymbolId = "valve_test"
	gpN.gpPosition = Vector2(200.0, 200.0)
	gpN.gpFlipped = true
	var gpG: GPPIDGraph = _gpGraphWithNode(gpN)
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpFromRef = {"node_id": "n1", "port_id": "in"}
	gpE.gpToRef = {"node_id": "n1", "port_id": "out"}
	var gpA: Dictionary = GPPortResolver.gpResolveEnd(gpG, _gpDefLookup(), gpE, true,
		GPPort.GP_NOZZLE)
	var gpB: Dictionary = GPPortResolver.gpResolveEnd(gpG, _gpDefLookup(), gpE, false,
		GPPort.GP_NOZZLE)
	gpApprox((gpA["pos"] as Vector2).x, 232.0, 0.001, "flipped 'in' moves to the right side")
	gpApprox((gpB["pos"] as Vector2).x, 168.0, 0.001, "flipped 'out' moves to the left side")
	# The outward normals must flip too, or the pipe leaves the symbol on the wrong side.
	# 向外法线也必须翻转，否则管线会从错误的一侧离开图元。
	gpApprox((gpA["dir"] as Vector2).x, 1.0, 0.001, "flipped 'in' normal points right")
	gpApprox((gpB["dir"] as Vector2).x, -1.0, 0.001, "flipped 'out' normal points left")


# ---- the degradation ladder ----

# Step 2: the stored port name no longer exists -> fall back to the wanted purpose.
# 第 2 级：存下来的端口名已不存在 -> 退化为期望用途的首个端口。
func gpTestUnknownPortNameFallsBackByType() -> void:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "x"
	gpD.gpDefaultSize = Vector2(56.0, 56.0)
	gpD.gpPorts = [
		GPPort.gpMake("proc", Vector2(0.5, 1.0), Vector2(0.0, 1.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("sig", Vector2(0.5, 0.0), Vector2(0.0, -1.0), GPPort.GP_SIGNAL),
	]
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "n1"
	gpN.gpPosition = Vector2(300.0, 300.0)
	var gpG: GPPIDGraph = _gpGraphWithNode(gpN)
	var gpLookup: Callable = func(gpId: String) -> GPSymbolDef:
		return gpD
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpKind = GPPIDEdge.GP_SIGNAL
	gpE.gpFromRef = {"node_id": "n1", "port_id": "renamed_by_user"}
	var gpR: Dictionary = GPPortResolver.gpResolveEnd(gpG, gpLookup, gpE, true, GPPort.GP_SIGNAL)
	gpEq(str(gpR["why"]), "typed", "a missing port name degrades to the wanted purpose")
	# sig is at normalized (0.5, 0), i.e. 28 above the centre of a 56-tall envelope.
	# sig 归一化在 (0.5, 0)，即 56 高包络中心上方 28。
	gpApprox((gpR["pos"] as Vector2).y, 272.0, 0.001, "the signal terminal is above the centre")


# Step 3: a symbol with no ports at all (legacy pack, or a legend glyph) degrades to the
# node centre — which is exactly how pre-P1 edges were drawn.
# 第 3 级：完全没有端口的图元（老包 / 图例符号）退化为节点中心 —— 这正是 P1 之前画边的方式。
func gpTestPortlessSymbolFallsBackToCentre() -> void:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "legend"
	gpD.gpPorts = []
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "n1"
	gpN.gpPosition = Vector2(400.0, 250.0)
	var gpG: GPPIDGraph = _gpGraphWithNode(gpN)
	var gpLookup: Callable = func(gpId: String) -> GPSymbolDef:
		return gpD
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpFromRef = {"node_id": "n1", "port_id": ""}
	var gpR: Dictionary = GPPortResolver.gpResolveEnd(gpG, gpLookup, gpE, true, GPPort.GP_NOZZLE)
	gpEq(str(gpR["why"]), "center", "a port-less symbol degrades to the node centre")
	gpEq(gpR["pos"], Vector2(400.0, 250.0), "the centre is the node position")
	gpCheck(bool(gpR["bound"]), "the end is still reported as bound to a node")


# ---- the never-fail contract ----

func gpTestResolutionNeverReturnsInf() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpNode: GPPIDNode = GPPIDNode.new()
	gpNode.gpInstanceId = "n1"
	gpNode.gpSymbolId = "valve_test"
	gpG.gpAddNode(gpNode)
	var gpLookup: Callable = _gpDefLookup()
	var gpCases: Array[Dictionary] = [
		{"node_id": "", "port_id": "", "point": [1.0, 2.0]},   # dangling / 悬空
		{"node_id": "ghost", "port_id": "out"},                 # node deleted / 节点已删
		{"node_id": "n1", "port_id": "does_not_exist"},         # renamed port / 端口改名
		{"node_id": "n1", "port_id": ""},                        # legacy edge / 老档边
		{},                                                      # hand-edited JSON / 手改 JSON
	]
	for gpRef in gpCases:
		var gpE: GPPIDEdge = GPPIDEdge.new()
		gpE.gpFromRef = (gpRef as Dictionary).duplicate()
		var gpR: Dictionary = GPPortResolver.gpResolveEnd(gpG, gpLookup, gpE, true,
			GPPort.GP_NOZZLE)
		gpCheck(gpR["pos"] != Vector2.INF, "no end shape may resolve to Vector2.INF: %s" % str(gpRef))


func gpTestNullEdgeIsSafe() -> void:
	var gpR: Dictionary = GPPortResolver.gpResolveEnd(null, Callable(), null, true, "")
	gpCheck(gpR["pos"] != Vector2.INF, "a null edge still resolves to a drawable position")
	gpEq(str(GPPortResolver.gpWantTypeFor(null)), GPPort.GP_NOZZLE, "a null edge wants a nozzle")


func gpTestWantTypeForKind() -> void:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpKind = GPPIDEdge.GP_SIGNAL
	gpEq(GPPortResolver.gpWantTypeFor(gpE), GPPort.GP_SIGNAL, "signal edges want a signal port")
	gpE.gpKind = GPPIDEdge.GP_UTILITY
	gpEq(GPPortResolver.gpWantTypeFor(gpE), GPPort.GP_NOZZLE, "utility pipes still want a nozzle")
