extends Node2D
# P2 render smoke test — kept as a permanent headless regression guard.
# 目的：证明 GPEdgeView._draw 与两层结构的 GPSymbolView 能在真实场景树中实际执行
# （autoload 与 RenderingServer 均在线），而不只是在隔离环境里。
# P2 渲染冒烟测试 —— 作为常驻的 headless 回归守卫保留。


func _ready() -> void:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "SMOKE_PUMP"
	gpDef.gpDisplayName = "Smoke Pump"
	gpDef.gpCategory = "pump"
	gpDef.gpPorts = [
		GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("sig", Vector2(0.5, 0.0), Vector2(0.0, -1.0), GPPort.GP_SIGNAL),
	]

	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	var gpN1: GPPIDNode = GPPIDNode.new()
	gpN1.gpInstanceId = "n1"
	gpN1.gpSymbolId = gpDef.gpId
	gpN1.gpPosition = Vector2(0.0, 0.0)
	gpN1.gpRotationDeg = 90.0
	gpGraph.gpAddNode(gpN1)
	var gpN2: GPPIDNode = GPPIDNode.new()
	gpN2.gpInstanceId = "n2"
	gpN2.gpSymbolId = gpDef.gpId
	gpN2.gpPosition = Vector2(320.0, 160.0)
	gpN2.gpFlipped = true
	gpGraph.gpAddNode(gpN2)

	# 1. Process pipe port-to-port / 工艺管道，端口到端口
	var gpE1: GPPIDEdge = gpGraph.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": "out"}, {"node_id": "n2", "port_id": "in"},
		GPPIDEdge.GP_PROCESS, "", "PL-1001")
	gpGraph.gpAddEdge(gpE1)
	# 2. Signal line (dashed) / 信号线（虚线）
	var gpE2: GPPIDEdge = gpGraph.gpNewEdgeEx("e2",
		{"node_id": "n1", "port_id": "sig"}, {"node_id": "n2", "port_id": "sig"},
		GPPIDEdge.GP_SIGNAL, "PNEUMATIC")
	gpGraph.gpAddEdge(gpE2)
	# 3. Dangling pipe (one free end) / 悬空管道（一端自由）
	var gpE3: GPPIDEdge = gpGraph.gpNewEdge("e3", "n2", "")
	gpE3.gpFromRef = {"node_id": "n2", "port_id": "out"}
	gpE3.gpToRef = {"node_id": "", "port_id": "", "point": [520.0, 160.0]}
	gpE3.gpTag = ""
	gpGraph.gpAddEdge(gpE3)

	var gpLookup: Callable = func(gpId: String) -> GPSymbolDef: return gpDef
	for gpN in gpGraph.gpNodes:
		var gpSV: GPSymbolView = GPSymbolView.new()
		gpSV.gpInit(gpN, gpDef)
		add_child(gpSV)
	for gpE in gpGraph.gpEdges:
		var gpEV: GPEdgeView = GPEdgeView.new()
		gpEV.gpInit(gpE, gpGraph, gpLookup)
		gpEV.gpSetView(1.0, gpE.gpInstanceId == "e1", false)
		add_child(gpEV)
		print("edge ", gpE.gpInstanceId, " polyline=", gpEV.gpPolyline())

	await get_tree().process_frame
	await get_tree().process_frame
	print("P2 SMOKE OK")
	get_tree().quit(0)
