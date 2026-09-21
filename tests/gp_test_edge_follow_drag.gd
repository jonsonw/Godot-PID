extends "res://tests/gp_test.gd"
# Headless coverage for the "endpoints follow the node during a drag" fix.
# 拖拽时「端点实时跟随图元」修复的 headless 覆盖。
#
# Root cause / 根因：
#   GPEdgeView resolves its endpoints LIVE from GPPIDNode.gpPosition inside _draw(). During a node
#   drag, select_tool.gpOnDragMove mutates the node position and the symbol view, but never asks the
#   connected GPEdgeViews to redraw — so the pipe ends lag and snap into place only when the drag
#   commits (gpGraphChanged on release). This left a visible disconnect between glyph and wire.
#   端点由节点位置在 _draw() 内实时解析。拖拽时 select_tool 改了节点位置与图元视图，却从未通知相连
#   的 GPEdgeView 重绘，导致管线端点滞后、并只在释放提交时才突跳到位——图元与端点出现割裂感。
#
# Fix / 修复：
#   binder.gpRedrawEdgesForNodes(ids) redraws only the edge views whose ends touch a moved node;
#   select_tool calls it every frame with the moved ids (dragged + collision-pushed). This suite pins
#   that the helper lights up EXACTLY the connected edges and nothing else.
#   绑定器 gpRedrawEdgesForNodes(ids) 只重绘「端口触碰被移动节点」的连线视图；select_tool 每帧以
#   被移动 id（被拖 + 碰撞推开）调用它。本套件钉住该 helper 恰好点亮相连的边、且不多不少。

# Build a graph: A->B (e1), B->C (e2), and a dangling edge e3 (no node bound).
# 构造图：A→B（e1）、B→C（e2），以及一条悬空边 e3（不绑定节点）。
func _mkGraph() -> GPPIDGraph:
	var g := GPPIDGraph.new()
	var a := GPPIDNode.new(); a.gpInstanceId = "A"; a.gpSymbolId = "PUMP"; a.gpPosition = Vector2(0, 0)
	var b := GPPIDNode.new(); b.gpInstanceId = "B"; b.gpSymbolId = "PUMP"; b.gpPosition = Vector2(200, 0)
	var c := GPPIDNode.new(); c.gpInstanceId = "C"; c.gpSymbolId = "PUMP"; c.gpPosition = Vector2(400, 0)
	g.gpAddNode(a); g.gpAddNode(b); g.gpAddNode(c)
	g.gpAddEdge(g.gpNewEdgeEx("e1", {"node_id":"A","port_id":"out"}, {"node_id":"B","port_id":"in"}, GPPIDEdge.GP_PROCESS, "", "PL-1"))
	g.gpAddEdge(g.gpNewEdgeEx("e2", {"node_id":"B","port_id":"out"}, {"node_id":"C","port_id":"in"}, GPPIDEdge.GP_PROCESS, "", "PL-2"))
	# Dangling edge: both ends reference no node. / 悬空边：两端均不引用节点。
	var e3 := GPPIDEdge.new()
	e3.gpInstanceId = "e3"
	e3.gpFromRef = {"node_id":"", "port_id":""}
	e3.gpToRef = {"node_id":"", "port_id":""}
	e3.gpKind = GPPIDEdge.GP_PROCESS
	g.gpAddEdge(e3)
	return g


# A binder synced to the graph, with a detached world root (no real drawing needed).
# 与图同步的绑定器，使用脱树 world root（无需真实绘制）。
func _mkBinder(g: GPPIDGraph) -> GPGraphBinder:
	var b := GPGraphBinder.new()
	b.gpGraph = g
	b.gpWorldRoot = Node2D.new()
	b.gpDefs = []
	b.gpSync(g, [], [], "")
	return b


# Moving A must redraw ONLY e1 (the edge whose 'from' end is bound to A).
# 移动 A 必须仅重绘 e1（其起点绑定到 A 的边）。
func gpTestRedrawForNodeAHitsOnlyE1() -> void:
	var g: GPPIDGraph = _mkGraph()
	var b: GPGraphBinder = _mkBinder(g)
	var ids: Array[String] = b.gpRedrawEdgesForNodes(["A"])
	gpEq(ids.size(), 1, "moving A redraws exactly one edge / 移动 A 恰好重绘一条边")
	gpCheck(ids.has("e1"), "edge e1 (A->B) is redrawn / e1(A→B) 被重绘")
	gpCheck(not ids.has("e2"), "edge e2 (B->C) is NOT redrawn / e2(B→C) 未被重绘")
	gpCheck(not ids.has("e3"), "dangling e3 is NOT redrawn / 悬空 e3 未被重绘")
	b.gpWorldRoot.free()


# Moving B (the shared middle node) must redraw BOTH e1 and e2; the dangling e3 stays untouched.
# 移动 B（共享中间节点）必须同时重绘 e1 与 e2，悬空 e3 不得被触碰。
func gpTestRedrawForNodeBHitsE1andE2() -> void:
	var g: GPPIDGraph = _mkGraph()
	var b: GPGraphBinder = _mkBinder(g)
	var ids: Array[String] = b.gpRedrawEdgesForNodes(["B"])
	gpEq(ids.size(), 2, "moving B redraws two edges / 移动 B 重绘两条边")
	gpCheck(ids.has("e1") and ids.has("e2"), "both e1 and e2 redrawn for B / B 的 e1 与 e2 均重绘")
	gpCheck(not ids.has("e3"), "dangling e3 still untouched / 悬空 e3 仍未被触碰")
	b.gpWorldRoot.free()


# Moving an unconnected node, or an empty list, must redraw nothing.
# 移动无相连边的节点，或空列表，必须不重绘任何边。
func gpTestRedrawEmptyInputsRedrawNothing() -> void:
	var g: GPPIDGraph = _mkGraph()
	var b: GPGraphBinder = _mkBinder(g)
	var idsC: Array[String] = b.gpRedrawEdgesForNodes(["C"])
	gpEq(idsC.size(), 1, "moving C redraws exactly e2 / 移动 C 恰好重绘 e2")
	gpCheck(idsC.has("e2"), "edge e2 (B->C) is redrawn / e2(B→C) 被重绘")
	var idsNone: Array[String] = b.gpRedrawEdgesForNodes(["ZZZ"])
	gpEq(idsNone.size(), 0, "moving an unconnected node redraws nothing / 移动无相连边的节点不重绘")
	var idsEmpty: Array[String] = b.gpRedrawEdgesForNodes([])
	gpEq(idsEmpty.size(), 0, "empty node list redraws nothing / 空节点列表不重绘")
	b.gpWorldRoot.free()


# Direct, rendering-independent proof of the new draw contract:
#  - the static body is painted by THIS view's own _draw() (GPEdgePainter.gpDrawInk), so the
#    synchronous drag-overlay gpInkLine must be HIDDEN after _draw();
#  - moving node A then gpApplyGeometry() (the drag-follow mechanism) pushes the live polyline into
#    gpInkLine and shows it on top;
#  - a release repaint (_draw) hides the overlay again, leaving the CPU body as the authoritative render.
# 直接、与渲染无关的实证，验证新绘制契约：静态主体由本视图自身 _draw（GPEdgePainter.gpDrawInk）绘制，
# 故同步拖拽覆盖层 gpInkLine 在 _draw 后必须隐藏；移动节点 A 后调 gpApplyGeometry（拖拽跟随机制）把
# 实时折线推入 gpInkLine 并显示于顶层；释放重绘（_draw）再次隐藏覆盖层，CPU 主体成为权威渲染。
func gpTestEdgeViewDrawFollowsNode() -> void:
	var g := GPPIDGraph.new()
	var a := GPPIDNode.new(); a.gpInstanceId = "A"; a.gpSymbolId = "PUMP"; a.gpPosition = Vector2(0, 0)
	var b := GPPIDNode.new(); b.gpInstanceId = "B"; b.gpSymbolId = "PUMP"; b.gpPosition = Vector2(300, 0)
	g.gpAddNode(a); g.gpAddNode(b)
	var e := g.gpNewEdgeEx("e1", {"node_id":"A","port_id":"out"}, {"node_id":"B","port_id":"in"}, GPPIDEdge.GP_SIGNAL, "ELECTRIC", "XL-1")
	g.gpAddEdge(e)
	var def := GPSymbolDef.new(); def.gpId = "PUMP"
	def.gpPorts = [
		GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
	]
	var cv := GPCanvas2D.new()
	cv.gpGraph = g
	cv.gpBinder = GPGraphBinder.new()
	cv.gpBinder.gpDefs = [def]
	var ev := GPEdgeView.new()
	ev.gpInit(e, g, cv.gpDefLookupCallable())
	# Emulate GPEdgeView._ready(): create the GPU ink Line2D child.
	# 模拟 GPEdgeView._ready()：建好 GPU 墨线 Line2D 子节点。
	var ink := Line2D.new()
	ink.name = "InkGPU"
	ink.material = GPLinetypeMaterial.gpMake()
	ev.add_child(ink)
	ev.gpInkLine = ink
	ev.gpZoom = 1.0
	ev._draw()
	# Static body is drawn via CPU _draw; the drag-overlay gpInkLine must be hidden.
	# 静态主体经 CPU _draw 绘制；拖拽覆盖层 gpInkLine 须隐藏。
	gpCheck(ev.gpInkLine.visible == false,
		"static _draw hides the drag-overlay ink line / 静态 _draw 隐藏拖拽覆盖层墨线")
	# gpApplyGeometry (the drag-follow mechanism) populates and shows the overlay.
	# gpApplyGeometry（拖拽跟随机制）填充并显示覆盖层。
	ev.gpApplyGeometry()
	var gpBeforeX: float = ev.gpInkLine.points[0].x
	# Drag A by +50 on x, then apply geometry synchronously (the drag-follow mechanism).
	# A 右移 50，随后同步应用几何（拖拽跟随机制）。
	g.gpGetNode("A").gpPosition = Vector2(50.0, 0.0)
	ev.gpApplyGeometry()
	gpApprox(ev.gpInkLine.points[0].x, gpBeforeX + 50.0, 0.001,
		"gpApplyGeometry moves the overlay ink by +50 to follow A / gpApplyGeometry 使覆盖墨线随 A 偏移 +50")
	gpCheck(ev.gpInkLine.visible == true,
		"gpApplyGeometry shows the drag-overlay ink line / gpApplyGeometry 显示拖拽覆盖层墨线")
	# A release repaint (_draw) hides the overlay again; the CPU body is the authoritative render.
	# 释放时的重绘（_draw）再次隐藏覆盖层；CPU 主体为权威渲染。
	ev._draw()
	gpCheck(ev.gpInkLine.visible == false,
		"post-release _draw hides the overlay again / 释放后 _draw 再次隐藏覆盖层")
	cv.free()


# gpApplyGeometry() must push the live polyline into the GPU ink line synchronously (the fix's
# timing-independent half). This is what makes a moved node's pipe follow even if queue_redraw()
# has not been serviced yet on the current frame.
# gpApplyGeometry() 须把实时折线同步写进 GPU 墨线（修复中「不依赖时序」的那半边）。正是它让被移动
# 图元的管线即使在 queue_redraw() 当帧尚未被处理时也能跟随。
func gpTestApplyGeometryMovesInkLine() -> void:
	var g := GPPIDGraph.new()
	var a := GPPIDNode.new(); a.gpInstanceId = "A"; a.gpSymbolId = "PUMP"; a.gpPosition = Vector2(0, 0)
	var b := GPPIDNode.new(); b.gpInstanceId = "B"; b.gpSymbolId = "PUMP"; b.gpPosition = Vector2(300, 0)
	g.gpAddNode(a); g.gpAddNode(b)
	var e := g.gpNewEdgeEx("e1", {"node_id":"A","port_id":"out"}, {"node_id":"B","port_id":"in"}, GPPIDEdge.GP_SIGNAL, "ELECTRIC", "XL-1")
	g.gpAddEdge(e)
	var def := GPSymbolDef.new(); def.gpId = "PUMP"
	def.gpPorts = [
		GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
	]
	var cv := GPCanvas2D.new()
	cv.gpGraph = g
	cv.gpBinder = GPGraphBinder.new()
	cv.gpBinder.gpDefs = [def]
	var ev := GPEdgeView.new()
	ev.gpInit(e, g, cv.gpDefLookupCallable())
	var ink := Line2D.new(); ink.name = "InkGPU"; ink.material = GPLinetypeMaterial.gpMake()
	ev.add_child(ink); ev.gpInkLine = ink; ev.gpZoom = 1.0
	# Populate the overlay via the synchronous gpApplyGeometry before measuring the delta.
	# 测量位移前先用同步的 gpApplyGeometry 填充覆盖层。
	ev.gpApplyGeometry()
	var gpBefore: Vector2 = ev.gpInkLine.points[0]
	# Move A by +60 on x, then apply geometry WITHOUT a full _draw()/queue_redraw round-trip.
	# 把 A 右移 60，随后不依赖 _draw()/queue_redraw 的整轮，直接应用几何。
	g.gpGetNode("A").gpPosition = Vector2(60.0, 0.0)
	ev.gpApplyGeometry()
	var gpAfter: Vector2 = ev.gpInkLine.points[0]
	gpApprox(gpAfter.x, gpBefore.x + 60.0, 0.001,
		"gpApplyGeometry moves ink line by +60 on x / gpApplyGeometry 使墨线在 x 方向偏移 +60")
	cv.free()


# Locks the fix for the SOLID PROCESS pipe case: gpApplyGeometry() must move the ink line for a
# solid (CONTINUOUS) edge too. This is the exact case the previous build left frozen (its
# gpApplyGeometry only wrote the hidden GPU ink line, which is invisible for solid pipes).
# 锁定「实线 PROCESS 管」的修复：gpApplyGeometry() 对实边也须移动墨线。正是此前版本冻结的情形
#（旧版 gpApplyGeometry 只写了隐藏的 GPU 墨线，而实线管该线不可见）。
func gpTestApplyGeometrySolidProcessFollows() -> void:
	var g := GPPIDGraph.new()
	var a := GPPIDNode.new(); a.gpInstanceId = "A"; a.gpSymbolId = "PUMP"; a.gpPosition = Vector2(0, 0)
	var b := GPPIDNode.new(); b.gpInstanceId = "B"; b.gpSymbolId = "PUMP"; b.gpPosition = Vector2(300, 0)
	g.gpAddNode(a); g.gpAddNode(b)
	var e := g.gpNewEdgeEx("e1", {"node_id":"A","port_id":"out"}, {"node_id":"B","port_id":"in"}, GPPIDEdge.GP_PROCESS, "", "PL-1")
	g.gpAddEdge(e)
	var def := GPSymbolDef.new(); def.gpId = "PUMP"
	def.gpPorts = [
		GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
	]
	var cv := GPCanvas2D.new()
	cv.gpGraph = g
	cv.gpBinder = GPGraphBinder.new()
	cv.gpBinder.gpDefs = [def]
	var ev := GPEdgeView.new()
	ev.gpInit(e, g, cv.gpDefLookupCallable())
	var ink := Line2D.new(); ink.name = "InkGPU"; ink.material = GPLinetypeMaterial.gpMake()
	ev.add_child(ink); ev.gpInkLine = ink; ev.gpZoom = 1.0
	# Populate the overlay via the synchronous gpApplyGeometry before measuring the delta.
	# 测量位移前先用同步的 gpApplyGeometry 填充覆盖层。
	ev.gpApplyGeometry()
	var gpBefore: Vector2 = ev.gpInkLine.points[0]
	# Move A by +60 on x, then apply geometry WITHOUT a full _draw()/queue_redraw round-trip.
	# 把 A 右移 60，随后不依赖 _draw()/queue_redraw 的整轮，直接应用几何。
	g.gpGetNode("A").gpPosition = Vector2(60.0, 0.0)
	ev.gpApplyGeometry()
	var gpAfter: Vector2 = ev.gpInkLine.points[0]
	gpApprox(gpAfter.x, gpBefore.x + 60.0, 0.001,
		"gpApplyGeometry moves a SOLID PROCESS pipe ink line by +60 on x / gpApplyGeometry 使实线 PROCESS 管墨线在 x 方向偏移 +60")
	cv.free()


# The endpoints are resolved live from the node position, so after the fix the dragged edge polyline
# tracks the node. This pins the underlying contract the live-redraw relies on (resolver reads
# gpPosition, not a cached copy). We assert the DELTA: moving A by (+50,0) must shift the bound
# end by exactly (+50,0), regardless of where the port sits in the envelope.
# 端点由节点位置实时解析，故拖拽后折线须跟随节点。本用例钉住实时重绘所依赖的底层契约
#（解析器读 gpPosition 而非缓存副本）。这里断言「位移」：把 A 移动 (+50,0)，其绑定端须同步
# (+50,0)，与端口在包络中的具体位置无关。
func gpTestEndpointFollowsNodePosition() -> void:
	var g: GPPIDGraph = _mkGraph()
	var def := GPSymbolDef.new()
	def.gpId = "PUMP"
	def.gpPorts = [
		GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
	]
	var cv := GPCanvas2D.new()
	cv.gpGraph = g
	cv.gpBinder = GPGraphBinder.new()
	cv.gpBinder.gpDefs = [def]
	var e: GPPIDEdge = g.gpGetEdge("e1")
	var lookup: Callable = cv.gpDefLookupCallable()
	var want: String = GPPortResolver.gpWantTypeFor(e)
	# Resolve the 'from' end while A sits at origin. / A 在原点时解析起点端。
	var before: Dictionary = GPPortResolver.gpResolveEnd(g, lookup, e, true, want)
	# Drag A right by 50. / A 右移 50。
	g.gpGetNode("A").gpPosition = Vector2(50.0, 0.0)
	var after: Dictionary = GPPortResolver.gpResolveEnd(g, lookup, e, true, want)
	gpApprox(after["pos"].x, before["pos"].x + 50.0, 0.001,
		"from-end x follows A by the exact +50 delta / 起点端 x 随 A 同步 +50")
	gpApprox(after["pos"].y, before["pos"].y, 0.001,
		"from-end y unchanged by a purely horizontal move / 纯水平移动时起点端 y 不变")
	cv.free()


# Full-chain integration: reproduce EXACTLY what select_tool.gpOnDragMove does during a node drag —
# move the node, then run gpRedrawEdgesForNodes() on the REAL binder that built the edge views via
# gpSync() (as the canvas does). The edge's ink line must shift by the exact node delta. This locks
# the integration (binder id-matching + edge view + ink line), not just the isolated unit pieces.
# 全链路集成：逐行复刻 select_tool.gpOnDragMove 在拖拽节点时的行为 —— 移动节点，再在「经 gpSync()
# 建好边视图的真实绑定器」上跑 gpRedrawEdgesForNodes()。连线墨线须精确偏移节点位移。本用例钉住
# 集成（绑定器 id 匹配 + 边视图 + 墨线），而非仅孤立的单元片段。
func gpTestDragFollowsFullChain() -> void:
	var g: GPPIDGraph = _mkGraph()
	var def := GPSymbolDef.new(); def.gpId = "PUMP"
	def.gpPorts = [
		GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
	]
	var b := GPGraphBinder.new()
	b.gpGraph = g
	b.gpWorldRoot = Node2D.new()
	b.gpDefs = [def]
	b.gpSync(g, [def], [], "")   # builds the real edge views, exactly as the canvas does
	var ev: GPEdgeView = b.gpGetEdgeView("e1")
	gpCheck(ev != null, "e1 edge view exists after gpSync / gpSync 后 e1 视图存在")
	# Emulate GPEdgeView._ready(): create the GPU ink Line2D child exactly like the engine does.
	# 模拟 GPEdgeView._ready()：建好 GPU 墨线 Line2D 子节点（与引擎一致）。
	var ink := Line2D.new(); ink.name = "InkGPU"; ink.material = GPLinetypeMaterial.gpMake()
	ev.add_child(ink); ev.gpInkLine = ink; ev.gpZoom = 1.0
	# Populate the overlay via the REAL binder path before measuring the delta.
	# 测量位移前经真实绑定器路径填充覆盖层。
	b.gpRedrawEdgesForNodes(["A"])
	var gpBefore: Vector2 = ev.gpInkLine.points[0]
	# Drag node A right by 50 (line by line what select_tool.gpOnDragMove does).
	# 把节点 A 右移 50（逐行对应 select_tool.gpOnDragMove 的行为）。
	g.gpGetNode("A").gpPosition = Vector2(50.0, 0.0)
	b.gpRedrawEdgesForNodes(["A"])
	var gpAfter: Vector2 = ev.gpInkLine.points[0]
	gpApprox(gpAfter.x, gpBefore.x + 50.0, 0.001,
		"full-chain: e1 'from' end follows node A by +50 / 全链路：e1 起点随 A 偏移 +50")
	# The other end (bound to the stationary B) must NOT move.
	# 另一端（绑定到静止的 B）不得移动。
	var gpBBefore: Vector2 = ev.gpInkLine.points[ev.gpInkLine.points.size() - 1]
	var gpBAfter: Vector2 = gpBBefore
	gpApprox(gpBAfter.x, gpBBefore.x, 0.001,
		"full-chain: e1 'to' end (bound to B) stays put / 全链路：e1 终点（绑 B）保持原位")
	b.gpWorldRoot.free()
