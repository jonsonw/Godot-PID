extends "res://tests/gp_test.gd"
# Headless tests for GPSnapResolver (P3): the single place that turns a raw world click into
# "what did the user mean to connect to?". Pure graph function, no canvas — so it runs without a
# scene tree. Covers the priority ladder: typed port > any port > node centre > grid, plus the
# "wrong-kind port still snaps so the tool can refuse" rule.
# GPSnapResolver 的 headless 测试（P3）：把一次原始世界点击换算为「用户想连到哪里」的唯一场所。
# 纯图函数、无画布，无需场景树。覆盖优先级阶梯：类型端口 > 任意端口 > 节点中心 > 网格，以及
# 「类型不符的端口仍吸附，使工具得以拒绝」的规则。

# A graph with two ported symbols and one port-less symbol, plus a def lookup.
# 含两个带端口图元与一个无端口图元的图，外加定义查找。
#   N1 "pump"  @ (100,100), envelope 80x40, nozzle "in"  at right-middle  -> world (140,100)
#   N2 "valve" @ (300,100), envelope 60x40, nozzle "out" at right-middle  -> world (330,100)
#                                      actuator "act" at left-middle   -> world (270,100)
#   N3 "tank"  @ (500,500), no def -> node-centre snap only
func _mkPorted() -> Array:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-101", Vector2(100, 100)))
	g.gpAddNode(g.gpNewNode("N2", "valve", "V-201", Vector2(300, 100)))
	g.gpAddNode(g.gpNewNode("N3", "tank", "T-301", Vector2(500, 500)))
	var gpPump: GPSymbolDef = GPSymbolDef.new()
	gpPump.gpId = "pump"
	gpPump.gpDefaultSize = Vector2(80.0, 40.0)
	gpPump.gpPorts = [GPPort.gpMake("in", Vector2(1.0, 0.5), Vector2.RIGHT, GPPort.GP_NOZZLE)]
	var gpValve: GPSymbolDef = GPSymbolDef.new()
	gpValve.gpId = "valve"
	gpValve.gpDefaultSize = Vector2(60.0, 40.0)
	gpValve.gpPorts = [
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2.RIGHT, GPPort.GP_NOZZLE),
		GPPort.gpMake("act", Vector2(0.0, 0.5), Vector2.LEFT, GPPort.GP_ACTUATOR),
	]
	var gpDefs: Dictionary = {"pump": gpPump, "valve": gpValve}
	var gpLookup: Callable = func(gpId: String) -> GPSymbolDef:
		return gpDefs.get(gpId, null)
	var gpOut: Array = [g, gpLookup]
	return gpOut


func gpTestSnapGridFarFromAll() -> void:
	var f: Array = _mkPorted()
	var g: GPPIDGraph = f[0]
	var gpLookup: Callable = f[1]
	# (1000,1000) is far from every node centre and port. / 远离所有节点与端口。
	var gpS: Dictionary = GPSnapResolver.gpSnap(g, gpLookup, Vector2(1000, 1000), 1.0, [])
	gpEq(gpS.get("kind"), GPSnapResolver.GP_GRID, "far click snaps to the grid")
	gpApprox(float(gpS.get("pos").x), 1000.0, 0.01, "grid x is the nearest 50-step")
	gpApprox(float(gpS.get("pos").y), 1000.0, 0.01, "grid y is the nearest 50-step")
	gpEq(gpS.get("bound"), false, "a grid (dangling) end is not bound")


func gpTestSnapNodeNoPorts() -> void:
	var f: Array = _mkPorted()
	var g: GPPIDGraph = f[0]
	var gpLookup: Callable = f[1]
	# N3 "tank" has no def, so clicking its centre returns the node (legacy symbols w/o ports).
	# N3 无定义，点到其中心返回节点（兼容无端口的老图元）。
	var gpS: Dictionary = GPSnapResolver.gpSnap(g, gpLookup, Vector2(500, 500), 1.0, [])
	gpEq(gpS.get("kind"), GPSnapResolver.GP_NODE, "port-less node snaps to its centre")
	gpEq(str(gpS.get("node_id")), "N3", "the snapped node is N3")


func gpTestSnapPortNozzle() -> void:
	var f: Array = _mkPorted()
	var g: GPPIDGraph = f[0]
	var gpLookup: Callable = f[1]
	# On the nozzle of N1 with a pipe tool (wants NOZZLE). / 用管道工具点到 N1 的管口。
	var gpS: Dictionary = GPSnapResolver.gpSnap(g, gpLookup, Vector2(140, 100), 1.0, [GPPort.GP_NOZZLE])
	gpEq(gpS.get("kind"), GPSnapResolver.GP_PORT, "click on a nozzle snaps to the port")
	gpEq(str(gpS.get("node_id")), "N1", "port belongs to N1")
	gpEq(str(gpS.get("port_id")), "in", "port name is 'in'")
	gpEq(gpS.get("bound"), true, "a port end is bound")


func gpTestSnapTypeMismatchReturnsPort() -> void:
	var f: Array = _mkPorted()
	var g: GPPIDGraph = f[0]
	var gpLookup: Callable = f[1]
	# A pipe tool near the valve's ACTUATOR must still snap to a port (so the tool can refuse it
	# with "port_type_mismatch") rather than silently falling through to a dangling grid end.
	# 管道工具点到阀门执行机构附近，仍须吸附到端口（使工具能以「类型不符」拒绝），
	# 而非静默落到悬空网格端。
	var gpS: Dictionary = GPSnapResolver.gpSnap(g, gpLookup, Vector2(270, 100), 1.0, [GPPort.GP_NOZZLE])
	gpEq(gpS.get("kind"), GPSnapResolver.GP_PORT, "wrong-kind port still snaps (so it can be refused)")
	gpEq(str(gpS.get("type")), GPPort.GP_ACTUATOR, "the snapped port is the actuator (type mismatch)")


func gpTestIsPortHelper() -> void:
	var f: Array = _mkPorted()
	var g: GPPIDGraph = f[0]
	var gpLookup: Callable = f[1]
	var gpPort: Dictionary = GPSnapResolver.gpSnap(g, gpLookup, Vector2(140, 100), 1.0, [GPPort.GP_NOZZLE])
	var gpGrid: Dictionary = GPSnapResolver.gpSnap(g, gpLookup, Vector2(1000, 1000), 1.0, [])
	gpEq(GPSnapResolver.gpIsPort(gpPort), true, "gpIsPort true for a port snap")
	gpEq(GPSnapResolver.gpIsPort(gpGrid), false, "gpIsPort false for a grid snap")


# ---- SnapState wiring tests (P3, item 2): the toggles must actually change behaviour. ----
# ---- SnapState 接线测试（P3 第 2 项）：开关必须真正改变行为。 ----

# A graph with two straight (ortho=false) dangling edges that cross at (200,200):
#   e1  (100,100) -> (300,300)      e2  (100,300) -> (300,100)
# Their resolved polylines are exact straight lines, so midpoints / feet / crossing are
# computable by hand and independent of any routing internals.
# 含两条直连（非正交）悬空边、在 (200,200) 交叉的图：
#   e1  (100,100) -> (300,300)      e2  (100,300) -> (300,100)
# 解析出的折线是精确直线，故中点 / 垂足 / 交点均可手算，与任何布线内部无关。
func _mkWithEdges() -> Array:
	var g: GPPIDGraph = GPPIDGraph.new()
	var e1: GPPIDEdge = GPPIDEdge.new()
	e1.gpInstanceId = "e1"
	e1.gpFromRef = {"node_id": "", "port_id": "", "point": [100.0, 100.0]}
	e1.gpToRef = {"node_id": "", "port_id": "", "point": [300.0, 300.0]}
	e1.gpOrtho = false
	e1.gpRouting = []
	var e2: GPPIDEdge = GPPIDEdge.new()
	e2.gpInstanceId = "e2"
	e2.gpFromRef = {"node_id": "", "port_id": "", "point": [100.0, 300.0]}
	e2.gpToRef = {"node_id": "", "port_id": "", "point": [300.0, 100.0]}
	e2.gpOrtho = false
	e2.gpRouting = []
	g.gpAddEdge(e1)
	g.gpAddEdge(e2)
	return [g]


func _gpNoLookup() -> Callable:
	return func(gpId: String) -> GPSymbolDef:
		return null


# gpSnapEnabled = false must return the raw click, never pulled onto a port/grid/edge.
# gpSnapEnabled = false 必须返回原始点击，绝不吸附到端口/网格/边。
func gpTestSnapOffReturnsFree() -> void:
	var f: Array = _mkWithEdges()
	var g: GPPIDGraph = f[0]
	var gpS: Dictionary = GPSnapResolver.gpSnap(g, _gpNoLookup(), Vector2(200, 200), 1.0, [],
		false, GPSnapResolver.GP_KIND_ENDPOINT)
	gpEq(gpS.get("kind"), GPSnapResolver.GP_FREE, "disabled snap returns GP_FREE")
	gpApprox(float(gpS.get("pos").x), 200.0, 0.01, "free pos x is the raw click")
	gpApprox(float(gpS.get("pos").y), 200.0, 0.01, "free pos y is the raw click")


# gpSnapType = MIDPOINT snaps to the nearest edge midpoint.
# gpSnapType = MIDPOINT 吸附到最近边的中点。
func gpTestSnapMidpoint() -> void:
	var f: Array = _mkWithEdges()
	var g: GPPIDGraph = f[0]
	var gpS: Dictionary = GPSnapResolver.gpSnap(g, _gpNoLookup(), Vector2(200, 200), 1.0, [],
		true, GPSnapResolver.GP_KIND_MIDPOINT)
	gpEq(gpS.get("kind"), GPSnapResolver.GP_MID, "midpoint mode snaps to edge midpoint")
	gpApprox(float(gpS.get("pos").x), 200.0, 0.01, "mid x is the crossing point")
	gpApprox(float(gpS.get("pos").y), 200.0, 0.01, "mid y is the crossing point")
	gpEq(str(gpS.get("edge_id")), "e1", "midpoint belongs to e1 (first edge wins ties)")


# gpSnapType = PERPENDICULAR snaps to the nearest perpendicular foot on an edge.
# gpSnapType = PERPENDICULAR 吸附到边上最近的垂足。
func gpTestSnapPerpendicular() -> void:
	var f: Array = _mkWithEdges()
	var g: GPPIDGraph = f[0]
	var gpS: Dictionary = GPSnapResolver.gpSnap(g, _gpNoLookup(), Vector2(200, 210), 1.0, [],
		true, GPSnapResolver.GP_KIND_PERPENDICULAR)
	gpEq(gpS.get("kind"), GPSnapResolver.GP_PERP, "perp mode snaps to a perpendicular foot")
	gpApprox(float(gpS.get("pos").x), 205.0, 0.01, "perp foot x on e1 (y=x)")
	gpApprox(float(gpS.get("pos").y), 205.0, 0.01, "perp foot y on e1 (y=x)")


# gpSnapType = INTERSECTION snaps to the crossing of two edges.
# gpSnapType = INTERSECTION 吸附到两条边的交点。
func gpTestSnapIntersection() -> void:
	var f: Array = _mkWithEdges()
	var g: GPPIDGraph = f[0]
	var gpS: Dictionary = GPSnapResolver.gpSnap(g, _gpNoLookup(), Vector2(200, 200), 1.0, [],
		true, GPSnapResolver.GP_KIND_INTERSECTION)
	gpEq(gpS.get("kind"), GPSnapResolver.GP_INTER, "intersection mode snaps to crossing")
	gpApprox(float(gpS.get("pos").x), 200.0, 0.01, "inter x is the crossing")
	gpApprox(float(gpS.get("pos").y), 200.0, 0.01, "inter y is the crossing")


# When no feature is within reach, a feature mode falls back to the grid (consistent with
# ENDPOINT mode), so the click still lands on something aligned.
# 当附近无特征时，特征模式回落网格（与 ENDPOINT 模式一致），点击仍落在对齐的位置上。
func gpTestSnapFeatureFallbackToGrid() -> void:
	var f: Array = _mkWithEdges()
	var g: GPPIDGraph = f[0]
	var gpS: Dictionary = GPSnapResolver.gpSnap(g, _gpNoLookup(), Vector2(900, 900), 1.0, [],
		true, GPSnapResolver.GP_KIND_MIDPOINT)
	gpEq(gpS.get("kind"), GPSnapResolver.GP_GRID, "feature mode falls back to grid when nothing is near")
	gpApprox(float(gpS.get("pos").x), 900.0, 0.01, "grid x nearest 50-step")
	gpApprox(float(gpS.get("pos").y), 900.0, 0.01, "grid y nearest 50-step")
