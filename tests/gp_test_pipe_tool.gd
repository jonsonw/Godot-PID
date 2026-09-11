extends "res://tests/gp_test.gd"
# Headless tests for the two-press pipe tool (P3): its snap-to-ref builder and pair validator
# (pure, no canvas) plus the full two-press connect flow driven through a canvas + edit service.
# 管道两段式工具（P3）的 headless 测试：吸附→引用构造器与端点配对校验器（纯、无画布），
# 以及经「画布 + 编辑服务」驱动的完整两段式连线流程。

# ---- pure helper checks (no canvas needed) / 纯辅助检查（无需画布） ----

func gpTestRefFromPort() -> void:
	var tool: GPPipeTool = GPPipeTool.new()
	var gpRef: Dictionary = tool._gpRefFrom({"node_id": "N1", "port_id": "p1", "pos": Vector2(1, 2)})
	gpEq(str(gpRef.get("node_id")), "N1", "port ref keeps the node id")
	gpEq(str(gpRef.get("port_id")), "p1", "port ref keeps the port id")
	gpCheck(not gpRef.has("point"), "a port ref carries no dangling point")


func gpTestRefFromDangling() -> void:
	var tool: GPPipeTool = GPPipeTool.new()
	var gpRef: Dictionary = tool._gpRefFrom({"node_id": "", "pos": Vector2(5, 6)})
	gpEq(str(gpRef.get("node_id")), "", "dangling ref has empty node id")
	gpEq(str(gpRef.get("port_id")), "", "dangling ref has empty port id")
	gpEq(gpRef.get("point"), [5.0, 6.0], "dangling ref stores the world point")


func gpTestValidateAcceptsTwoNodes() -> void:
	var tool: GPPipeTool = GPPipeTool.new()
	gpEq(tool._gpValidatePair({"node_id": "N1", "port_id": ""}, {"node_id": "N2", "port_id": ""}),
		"", "two distinct nodes are an acceptable pair")


func gpTestValidateRefusesSelfLoop() -> void:
	var tool: GPPipeTool = GPPipeTool.new()
	gpEq(tool._gpValidatePair({"node_id": "N1", "port_id": "p1"}, {"node_id": "N1", "port_id": "p1"}),
		"edge_self_loop", "same port on same node is refused (self-loop)")


func gpTestValidateRefusesBothDangling() -> void:
	var tool: GPPipeTool = GPPipeTool.new()
	gpEq(tool._gpValidatePair({"node_id": "", "point": [0, 0]}, {"node_id": "", "point": [1, 1]}),
		"pipe_needs_one_bound", "both ends free is refused (not a pipe)")


func gpTestKindAndWantedPorts() -> void:
	var tool: GPPipeTool = GPPipeTool.new()
	gpEq(tool._gpKind(), GPPIDEdge.GP_PROCESS, "pipe tool creates PROCESS edges")
	var gpWant: Array[String] = tool._gpWantTypes()
	gpCheck(gpWant.has(GPPort.GP_NOZZLE), "pipe tool wants nozzles")
	gpCheck(gpWant.has(GPPort.GP_TERMINAL), "pipe tool also accepts generic terminals")


# ---- full two-press flow through a canvas / 经画布的完整两段式流程 ----

# Build a canvas in-tree (so _ready wires the binder) with two port-less nodes. With no defs the
# resolver snaps to node centres, which is enough to exercise the connect path headlessly.
# 在树中构建画布（使 _ready 接好 binder），含两个无端口节点。无定义时解析器吸附到节点中心，
# 足以在无界面下走通连线路径。
func _mkCanvas() -> GPCanvas2D:
	var cv: GPCanvas2D = GPCanvas2D.new()
	add_child(cv)
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-101", Vector2(100, 100)))
	g.gpAddNode(g.gpNewNode("N2", "valve", "V-201", Vector2(300, 100)))
	cv.gpGraph = g
	return cv


func gpTestTwoPressCreatesPipe() -> void:
	var cv: GPCanvas2D = _mkCanvas()
	var g: GPPIDGraph = cv.gpGraph
	var ctx: GPCanvasToolContext = GPCanvasToolContext.new(cv)
	var tool: GPPipeTool = GPPipeTool.new()
	tool.gpCtx = ctx
	# First press anchors at N1, second commits to N2. / 第一次按下锚定 N1，第二次提交到 N2。
	tool.gpOnPress(Vector2(100, 100), false, false)
	tool.gpOnPress(Vector2(300, 100), false, false)
	gpEq(g.gpEdges.size(), 1, "two presses on two nodes create one pipe")
	if g.gpEdges.size() == 1:
		gpEq(g.gpEdges[0].gpKind, GPPIDEdge.GP_PROCESS, "created edge is a PROCESS pipe")
	# One undo step removes it. / 一个撤销步移除它。
	gpEq(cv.gpActions.gpUndo(), true, "pipe creation is undoable")
	gpEq(g.gpEdges.size(), 0, "undo removed the pipe")
	cv.queue_free()


func gpTestTwoPressSameNodeRefuses() -> void:
	var cv: GPCanvas2D = _mkCanvas()
	var g: GPPIDGraph = cv.gpGraph
	var ctx: GPCanvasToolContext = GPCanvasToolContext.new(cv)
	var tool: GPPipeTool = GPPipeTool.new()
	tool.gpCtx = ctx
	tool.gpOnPress(Vector2(100, 100), false, false)
	tool.gpOnPress(Vector2(100, 100), false, false)  # same node again -> self-loop
	gpEq(g.gpEdges.size(), 0, "two presses on the SAME node create no pipe")
	gpEq(tool.gpRefusal, "edge_self_loop", "refusal is the self-loop key")
	cv.queue_free()


func gpTestTwoPressBothDanglingRefuses() -> void:
	var cv: GPCanvas2D = _mkCanvas()
	var g: GPPIDGraph = cv.gpGraph
	var ctx: GPCanvasToolContext = GPCanvasToolContext.new(cv)
	var tool: GPPipeTool = GPPipeTool.new()
	tool.gpCtx = ctx
	# Two presses in empty space -> both ends are grid (dangling). / 空白处两次按下 -> 两端皆网格（悬空）。
	tool.gpOnPress(Vector2(1000, 1000), false, false)
	tool.gpOnPress(Vector2(1100, 1000), false, false)
	gpEq(g.gpEdges.size(), 0, "two dangling presses create no pipe")
	gpEq(tool.gpRefusal, "pipe_needs_one_bound", "refusal is the needs-one-bound key")
	cv.queue_free()
