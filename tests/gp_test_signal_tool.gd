extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# B5: end-to-end tests for the SIGNAL-LINE tool (GPSignalTool).
# B5：信号线工具（GPSignalTool）的端到端测试。
#
# Why this suite exists / 本套件存在的原因：
# Before it, the signal tool had ZERO tests while the pipe tool had nine. The tool is three
# overrides on top of the pipe tool (edge kind / accepted port types / default signal type) —
# exactly the kind of thin subclass whose three lines nobody notices breaking, and which the AI
# phase will start generating in bulk.
# 在此之前，管道工具九项测试，**信号工具零测试**。它只是管道工具上的三条覆写（边类型 / 可接受端口
# 类型 / 默认信号类型）—— 正是那种"三行薄子类"：坏了没人发现，而 AI 阶段会开始大量生成它。
#
# The four promises / 四条承诺：
#   1. IT CREATES SIGNAL EDGES, ELECTRIC BY DEFAULT — that pair is what the style table keys off.
#      **它建的是信号线、默认电气** —— 样式表正是按这对值取线型的。
#   2. IT NEVER TOUCHES A PROCESS NOZZLE — the refusal must name the reason, not fail vaguely.
#      **它绝不接工艺管口** —— 拒绝必须给出原因码，而不是含糊失败。
#   3. IT TAKES A TERMINAL — off-page / marshalling terminals are how a signal leaves a sheet.
#      **它接受通用端点** —— 跨页 / 端子排正是信号离开一张图纸的路径。
#   4. IT MINTED NO LINE NUMBER — signal circuits carry a LOOP number, not a pipe number
#      (that gap is I14's business, not a licence to auto-number signals as pipes).
#      **它不铸线号** —— 信号回路带的是回路号，不是管线号（这个缺口属于 I14，不是"给信号线也编管号"的理由）。


# ---- pure overrides / 纯覆写 ----

func gpTestKindIsSignal() -> void:
	var gpTool: GPSignalTool = GPSignalTool.new()
	gpEq(gpTool._gpKind(), GPPIDEdge.GP_SIGNAL, "信号工具建 SIGNAL 边 / the tool creates SIGNAL edges")


func gpTestDefaultSignalTypeIsElectric() -> void:
	var gpTool: GPSignalTool = GPSignalTool.new()
	gpEq(gpTool._gpDefaultSignalType(), "ELECTRIC", "默认电气 / electric by default")


func gpTestWantedTypesExcludeNozzles() -> void:
	var gpTool: GPSignalTool = GPSignalTool.new()
	var gpWant: Array[String] = gpTool._gpWantTypes()
	gpCheck(gpWant.has(GPPort.GP_SIGNAL), "接受信号端口 / accepts signal ports")
	gpCheck(gpWant.has(GPPort.GP_ACTUATOR), "接受执行机构 / accepts actuator ports")
	gpCheck(gpWant.has(GPPort.GP_TERMINAL), "接受通用端点 / accepts terminals")
	gpCheck(not gpWant.has(GPPort.GP_NOZZLE),
		"不接受工艺管口 / refuses a process nozzle (that is the whole point)")


# ---- pair validation / 配对校验 ----

func gpTestPairAcceptsSignalToActuator() -> void:
	var gpTool: GPSignalTool = GPSignalTool.new()
	gpEq(gpTool._gpValidatePair(
		{"node_id": "N1", "port_id": "out", "type": GPPort.GP_SIGNAL},
		{"node_id": "N2", "port_id": "in", "type": GPPort.GP_ACTUATOR}),
		"", "信号端口 → 执行机构合法 / signal to actuator is a legal signal run")


func gpTestPairRefusesNozzleEnd() -> void:
	var gpTool: GPSignalTool = GPSignalTool.new()
	# A nozzle on EITHER end is refused, and the reason is the shared port-type key.
	# 任一端是工艺管口都被拒，且原因是共用的端口类型码。
	gpEq(gpTool._gpValidatePair(
		{"node_id": "N1", "port_id": "nout", "type": GPPort.GP_NOZZLE},
		{"node_id": "N2", "port_id": "in", "type": GPPort.GP_SIGNAL}),
		"port_type_mismatch", "起点接工艺管口被拒 / a nozzle at the start is refused")
	gpEq(gpTool._gpValidatePair(
		{"node_id": "N1", "port_id": "out", "type": GPPort.GP_SIGNAL},
		{"node_id": "N2", "port_id": "nin", "type": GPPort.GP_NOZZLE}),
		"port_type_mismatch", "终点接工艺管口被拒 / a nozzle at the end is refused")


func gpTestPairInheritsSelfLoopAndBothFreeRules() -> void:
	var gpTool: GPSignalTool = GPSignalTool.new()
	gpEq(gpTool._gpValidatePair({"node_id": "N1", "port_id": "p"},
		{"node_id": "N1", "port_id": "p"}),
		"edge_self_loop", "自环被拒（继承）/ self-loop refused (inherited)")
	gpEq(gpTool._gpValidatePair({"node_id": "", "point": [0, 0]}, {"node_id": "", "point": [1, 1]}),
		"pipe_needs_one_bound", "两端皆空被拒（继承）/ both ends free refused (inherited)")


# ---- full two-press flow through a canvas / 经画布的完整两段式流程 ----

# In-tree canvas with two port-less nodes: the resolver snaps to node centres, which is enough
# to drive the COMMIT path (kind / signal type / tag / undo) headlessly.
# 树内画布 + 两个无端口节点：解析器吸附到节点中心，足以在无界面下驱动**提交**路径
#（边类型 / 信号类型 / 线号 / 撤销）。
func _mkCanvas(gpY: float = 100.0) -> GPCanvas2D:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	add_child(gpCv)
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("N1", "pump", "P-101", Vector2(100, gpY)))
	gpG.gpAddNode(gpG.gpNewNode("N2", "valve", "V-201", Vector2(300, gpY)))
	gpCv.gpGraph = gpG
	return gpCv


func gpTestTwoPressCreatesElectricSignalLine() -> void:
	var gpCv: GPCanvas2D = _mkCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	var gpCtx: GPCanvasToolContext = GPCanvasToolContext.new(gpCv)
	var gpTool: GPSignalTool = GPSignalTool.new()
	gpTool.gpCtx = gpCtx
	gpTool.gpOnPress(Vector2(100, 100), false, false)
	gpTool.gpOnPress(Vector2(300, 100), false, false)
	gpEq(gpG.gpEdges.size(), 1, "两次按下建一条信号线 / two presses create one signal line")
	if gpG.gpEdges.size() == 1:
		var gpE: GPPIDEdge = gpG.gpEdges[0]
		gpEq(gpE.gpKind, GPPIDEdge.GP_SIGNAL, "边类型是 SIGNAL / the edge is SIGNAL")
		gpEq(gpE.gpSignalType, "ELECTRIC", "信号类型默认 ELECTRIC / signal type defaults to ELECTRIC")
		gpEq(gpE.gpTag, "", "信号线不铸线号 / no pipe number is minted for a signal line")
	gpEq(gpCv.gpActions.gpUndo(), true, "建线是一步撤销 / creation is one undo step")
	gpEq(gpG.gpEdges.size(), 0, "撤销后边消失 / undo removes the line")
	gpCv.queue_free()


func gpTestDuplicateSignalIsRefused() -> void:
	var gpCv: GPCanvas2D = _mkCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	var gpCtx: GPCanvasToolContext = GPCanvasToolContext.new(gpCv)
	var gpTool: GPSignalTool = GPSignalTool.new()
	gpTool.gpCtx = gpCtx
	gpTool.gpOnPress(Vector2(100, 100), false, false)
	gpTool.gpOnPress(Vector2(300, 100), false, false)
	# Same pair again: the command layer must refuse instead of stacking a second line on top.
	# 同一对端口再来一次：命令层必须拒绝，而不是叠出第二条线。
	gpTool.gpOnPress(Vector2(100, 100), false, false)
	gpTool.gpOnPress(Vector2(300, 100), false, false)
	gpEq(gpG.gpEdges.size(), 1, "重复连线被拒 / a duplicate signal line is refused")
	gpEq(gpCv.gpActions.gpLastRefusal, "edge_duplicate", "拒绝原因是 edge_duplicate / the reason is edge_duplicate")
	gpCv.queue_free()


func gpTestSignalAndPipeCoexistOnSamePair() -> void:
	# A signal line and a process pipe may legitimately connect the SAME two nodes (an instrument
	# symbol can be both an equipment neighbour and a signal source); the duplicate rule keys on
	# the pair AND the kind, so this must not be refused.
	# 信号线与工艺管线可以合法地连同一对节点（一个仪表图元既可能是设备邻居、也是信号源）；
	# 重复规则按「端对 + 类型」判断，故此情形不得被拒。
	var gpCv: GPCanvas2D = _mkCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	var gpCtx: GPCanvasToolContext = GPCanvasToolContext.new(gpCv)
	var gpPipe: GPPipeTool = GPPipeTool.new()
	gpPipe.gpCtx = gpCtx
	gpPipe.gpOnPress(Vector2(100, 100), false, false)
	gpPipe.gpOnPress(Vector2(300, 100), false, false)
	var gpSignal: GPSignalTool = GPSignalTool.new()
	gpSignal.gpCtx = gpCtx
	gpSignal.gpOnPress(Vector2(300, 100), false, false)
	gpSignal.gpOnPress(Vector2(100, 100), false, false)
	gpEq(gpG.gpEdges.size(), 2, "管线与信号线并存 / a pipe and a signal line coexist")
	gpCv.queue_free()
