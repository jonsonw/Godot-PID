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
