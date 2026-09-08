extends "res://tests/gp_test.gd"
# Headless tests for GPEditService (M4 续): every user edit the canvas used to perform
# inline — place / connect / draw-commit / delete / duplicate / move — plus undo/redo.
# GPEditService 的 headless 测试（M4 续）：画布原先内联完成的每一项用户编辑
# （放置 / 连线 / 提交绘图 / 删除 / 复制 / 移动），外加撤销与重做。
#
# The point of these tests / 这些测试的意义:
#   The service is the seam where "what the user asked for" stops being mixed with "how the
#   canvas repaints". It depends on nothing but GPPIDGraph + GPIdGen, so an entire edit
#   round-trip is verifiable without a scene tree — and, crucially, WITHOUT a canvas.
#   本服务正是「用户要什么」与「画布如何重绘」不再混在一起的那条缝。它只依赖
#   GPPIDGraph + GPIdGen，因此一次完整的编辑往返无需场景树即可验证 —— 更重要的是，
#   无需画布。

# Fixture: two nodes joined by one edge, wired into a fresh service.
# 夹具：两个节点由一条边相连，接入一个全新的服务。
func _mkSvc() -> Array:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-101", Vector2(10, 10)))
	g.gpAddNode(g.gpNewNode("N2", "valve", "V-201", Vector2(100, 10)))
	g.gpAddEdge(g.gpNewEdge("E1", "N1", "N2"))
	var svc: GPEditService = GPEditService.new()
	svc.gpBindGraph(g, GPIdGen.new())
	var gpOut: Array = [g, svc]
	return gpOut


# ---------------------------------------------------------------- place / 放置

func gpTestPlaceNodeIsUndoable() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var nid: String = svc.gpPlaceNode("tank", Vector2(50, 50))
	gpCheck(nid != "", "placing returns a node id")
	# Regression: the id prefix is the project-wide "n". An upper-case "N" here would fork
	# the id namespace away from every existing saved file.
	# 回归：id 前缀是全项目统一的 "n"。此处若用大写 "N" 会让 id 命名空间与所有既有存档分叉。
	gpCheck(nid.begins_with("n"), "node id uses the lower-case n prefix")
	gpEq(g.gpNodes.size(), 3, "node was added")
	gpEq(svc.gpUndo(), true, "undo is available")
	gpEq(g.gpNodes.size(), 2, "undo removed the placed node")
	gpEq(svc.gpRedo(), true, "redo is available")
	gpEq(g.gpNodes.size(), 3, "redo put it back")


func gpTestPlaceNodeKeepsIdOnRedo() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var nid: String = svc.gpPlaceNode("tank", Vector2(50, 50))
	svc.gpUndo()
	svc.gpRedo()
	# Same id after a full undo/redo cycle: an edge or an external reference to this node
	# must not be silently orphaned by re-minting the id.
	# 完整撤销/重做后 id 不变：指向该节点的边或外部引用绝不能因重新生成 id 而被静默孤立。
	gpCheck(g.gpGetNode(nid) != null, "redo reuses the original node id")


func gpTestPlaceNodeRejectsEmptySymbol() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	gpEq(svc.gpPlaceNode("", Vector2(0, 0)), "", "empty symbol id is refused")
	gpEq(g.gpNodes.size(), 2, "nothing was added")
	gpEq(svc.gpCanUndo(), false, "a refused edit records no undo step")


# ---------------------------------------------------------------- connect / 连线

func gpTestConnectIsUndoable() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var nid: String = svc.gpPlaceNode("tank", Vector2(50, 50))
	gpEq(svc.gpConnect("N1", nid), true, "connect succeeds")
	gpEq(g.gpEdges.size(), 2, "edge was added")
	svc.gpUndo()
	gpEq(g.gpEdges.size(), 1, "undo removed the edge")
	svc.gpRedo()
	gpEq(g.gpEdges.size(), 2, "redo restored the edge")


func gpTestConnectRefusesSelfAndEmpty() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	gpEq(svc.gpConnect("N1", "N1"), false, "self-connection is refused")
	gpEq(svc.gpConnect("", "N2"), false, "empty endpoint is refused")
	gpEq(g.gpEdges.size(), 1, "no edge was added")
	gpEq(svc.gpCanUndo(), false, "a refused connection records no undo step")


# ---------------------------------------------------------------- shapes / 图形

func gpTestAddShapeIsUndoable() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var idx: int = svc.gpAddShape(GPShape.gpLine(Vector2(0, 0), Vector2(10, 10)))
	gpEq(idx, 0, "shape landed at index 0")
	gpEq(g.gpShapes.size(), 1, "shape was added")
	svc.gpUndo()
	gpEq(g.gpShapes.size(), 0, "undo removed the shape")
	svc.gpRedo()
	gpEq(g.gpShapes.size(), 1, "redo restored the shape")


func gpTestShapeDeleteRestoresZOrder() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	svc.gpAddShape(GPShape.gpLine(Vector2(0, 0), Vector2(1, 1)))      # 0
	svc.gpAddShape(GPShape.gpCircle(Vector2(5, 5), 4.0))              # 1
	svc.gpAddShape(GPShape.gpRect(Vector2(0, 0), Vector2(9, 9)))      # 2
	var mid: GPShape = g.gpShapes[1]
	# Delete the MIDDLE shape: restoring it must land back at index 1, not at the end, or
	# undo would silently restack the drawing order.
	# 删除「中间」那枚图形：恢复它必须回到下标 1 而非末尾，否则撤销会静默改变叠放顺序。
	gpEq(svc.gpDeleteSelection([], [1]), true, "shape delete succeeds")
	gpEq(g.gpShapes.size(), 2, "middle shape removed")
	svc.gpUndo()
	gpEq(g.gpShapes.size(), 3, "undo restored all three")
	gpEq(g.gpShapes[1], mid, "restored at its original index (z-order preserved)")


# ---------------------------------------------------------------- delete / 删除

func gpTestMixedDeleteIsOneUndoStep() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	svc.gpAddShape(GPShape.gpLine(Vector2(0, 0), Vector2(10, 10)))
	# One Delete over a node AND a shape must be one Ctrl+Z, not two — undo granularity
	# has to match the single action the user performed.
	# 一次删除同时涉及节点与图形时，必须只需一次 Ctrl+Z 而非两次 ——
	# 撤销粒度必须与用户执行的单次操作对齐。
	gpEq(svc.gpDeleteSelection(["N1"], [0]), true, "mixed delete succeeds")
	gpEq(g.gpNodes.size(), 1, "node removed")
	gpEq(g.gpEdges.size(), 0, "its edge was removed too")
	gpEq(g.gpShapes.size(), 0, "shape removed")
	svc.gpUndo()
	gpEq(g.gpNodes.size(), 2, "one undo restored the node")
	gpEq(g.gpEdges.size(), 1, "one undo restored the edge")
	gpEq(g.gpShapes.size(), 1, "one undo restored the shape")


func gpTestEmptyDeleteRecordsNothing() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	gpEq(svc.gpDeleteSelection([], []), false, "deleting nothing does nothing")
	gpEq(svc.gpCanUndo(), false, "no phantom undo step")


# ---------------------------------------------------------------- duplicate / 复制

func gpTestDuplicateSelection() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var src: GPPIDNode = g.gpGetNode("N1")
	var newIds: Array[String] = svc.gpDuplicateSelection(["N1"])
	gpEq(newIds.size(), 1, "one copy was made")
	gpEq(g.gpNodes.size(), 3, "copy added to the graph")
	var copy: GPPIDNode = g.gpGetNode(newIds[0])
	gpCheck(copy != null, "copy is retrievable by its new id")
	gpEq(copy.gpSymbolId, src.gpSymbolId, "copy keeps the symbol")
	gpEq(copy.gpTag, src.gpTag, "copy keeps the tag")
	gpEq(copy.gpPosition, src.gpPosition + GPDuplicateNodesCommand.GP_OFFSET, "copy is offset")
	# Deep-copied attributes: mutating the copy must not reach back into the original.
	# 属性为深拷贝：改动副本不应回写到原件。
	copy.gpAttrValues["k"] = 1
	gpEq(src.gpAttrValues.has("k"), false, "attributes are deep-copied, not aliased")


func gpTestDuplicateIsUndoable() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var newIds: Array[String] = svc.gpDuplicateSelection(["N1"])
	svc.gpUndo()
	gpEq(g.gpNodes.size(), 2, "undo removed the copy")
	svc.gpRedo()
	gpEq(g.gpNodes.size(), 3, "redo restored the copy")
	# Redo must reuse the same id, so anything referencing the copy still resolves.
	# 重做必须复用同一 id，使引用该副本的一切依然可解析。
	gpCheck(g.gpGetNode(newIds[0]) != null, "redo reuses the copy id")


# ---------------------------------------------------------------- move / 移动

func gpTestMoveNodesIsUndoable() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	svc.gpMoveNodes(["N1", "N2"], Vector2(20, -5))
	gpEq(g.gpGetNode("N1").gpPosition, Vector2(30, 5), "first node moved")
	gpEq(g.gpGetNode("N2").gpPosition, Vector2(120, 5), "second node moved by the same delta")
	svc.gpUndo()
	gpEq(g.gpGetNode("N1").gpPosition, Vector2(10, 10), "undo returned it")
	gpEq(g.gpGetNode("N2").gpPosition, Vector2(100, 10), "undo returned both (group is rigid)")


func gpTestZeroMoveRecordsNothing() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	# A click without a drag must not leave an undo step behind.
	# 只点不拖不应留下撤销步。
	gpEq(svc.gpMoveNodes(["N1"], Vector2.ZERO), false, "zero delta is refused")
	gpEq(svc.gpCanUndo(), false, "no undo step recorded")


# ---------------------------------------------------------------- history / 历史

func gpTestRebindDropsHistory() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	svc.gpPlaceNode("tank", Vector2(0, 0))
	gpEq(svc.gpCanUndo(), true, "history exists before the swap")
	# Undo must never reach back into a graph that is no longer displayed.
	# 撤销绝不能回到已不再显示的图。
	svc.gpBindGraph(GPPIDGraph.new(), GPIdGen.new())
	gpEq(svc.gpCanUndo(), false, "swapping the graph cleared the history")


func gpTestNewEditInvalidatesRedo() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	svc.gpPlaceNode("tank", Vector2(0, 0))
	svc.gpUndo()
	gpEq(svc.gpCanRedo(), true, "redo branch exists")
	svc.gpPlaceNode("pump", Vector2(5, 5))
	gpEq(svc.gpCanRedo(), false, "a fresh edit discarded the redo branch")


func gpTestUndoLabelsForMenus() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	gpEq(svc.gpUndoLabel(), "", "no label before any edit")
	svc.gpPlaceNode("tank", Vector2(0, 0))
	gpEq(svc.gpUndoLabel(), "添加节点", "undo label is human readable")
	svc.gpUndo()
	gpEq(svc.gpRedoLabel(), "添加节点", "redo label is human readable")
