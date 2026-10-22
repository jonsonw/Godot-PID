extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Headless tests for the app-wide clipboard and cross-sheet paste (A6).
# 应用级剪贴板与跨图纸粘贴（A6）的 headless 测试。
#
# Four promises are guarded here / 此处守护四条承诺：
#   1. THE CLIPBOARD OUTLIVES THE SHEET. It stores VALUE objects, so two graphs never share a
#      node — the defect that would otherwise make editing one drawing silently edit the other.
#      **剪贴板比图纸活得久**。它存的是**值对象**，故两张图绝不共享节点 —— 否则改一张图会静默
#      改到另一张。
#   2. PASTE IS ONE UNDO STEP. Everything a paste creates is removed again by a single undo.
#      **粘贴是一步撤销**。一次粘贴创建的东西由单次撤销全部移除。
#   3. DANGLING AND DANGLING-ISH ENDS ARE NOT INVENTED. An edge whose end is a free point, or
#      whose other end was not copied, is skipped rather than pasted as a line to nowhere.
#      **不臆造端点**。端点悬空的边、或另一端未被复制的边，一律跳过，而不是粘成一条通往虚无的线。
#   4. A SECOND COPY REPLACES THE FIRST. Copy A, copy B → paste pastes B, never B+A.
#      **第二次复制替换第一次**。复制 A、再复制 B → 粘贴的是 B，绝不是 B+A。

const GP_EPS: float = 0.0001


# A two-node graph with one edge between them, plus one annotation shape.
# 一张两节点图，其间一条连线，外加一个注释图形。
func _gpGraphA() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN1: GPPIDNode = GPPIDNode.new()
	gpN1.gpInstanceId = "n1"
	gpN1.gpSymbolId = "sym"
	gpN1.gpPosition = Vector2(10.0, 10.0)
	gpG.gpAddNode(gpN1)
	var gpN2: GPPIDNode = GPPIDNode.new()
	gpN2.gpInstanceId = "n2"
	gpN2.gpSymbolId = "sym"
	gpN2.gpPosition = Vector2(60.0, 10.0)
	gpG.gpAddNode(gpN2)
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": "p1"}, {"node_id": "n2", "port_id": "p1"},
		GPPIDEdge.GP_PROCESS, "", "PL-0001")
	gpG.gpAddEdge(gpE)
	gpG.gpAddShape(GPShape.gpLine(Vector2(0.0, 0.0), Vector2(10.0, 0.0)))
	return gpG


func _gpCtx(gpGraph: GPPIDGraph) -> GPCommandContext:
	return GPCommandContext.new(gpGraph, GPIdGen.new(), null)


func _gpClearClipboard() -> void:
	GPClipboard.gpClear()


# ---------------------------------------------------------------------------
# Capture
# 捕获
# ---------------------------------------------------------------------------

func gpTestCopyCapturesNodesEdgesShapes() -> void:
	_gpClearClipboard()
	var gpG: GPPIDGraph = _gpGraphA()
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), null)
	var gpIdx: Array[int] = [0]
	var gpCount: int = gpSvc.gpCopySelection(["n1", "n2"], gpIdx)
	gpEq(gpCount, 4, "2 节点 + 1 连线 + 1 图形 = 4 项 / two nodes + one edge + one shape")
	gpEq(GPClipboard.gpNodes().size(), 2, "捕获两个节点 / two nodes captured")
	gpEq(GPClipboard.gpEdges().size(), 1, "捕获一条内部连线 / the internal edge captured")
	gpEq(GPClipboard.gpShapes().size(), 1, "捕获一个图形 / one shape captured")
	gpCheck(GPClipboard.gpHas(), "剪贴板非空 / clipboard is non-empty")


func gpTestCopyExcludesEdgeWithOneEndOutside() -> void:
	_gpClearClipboard()
	var gpG: GPPIDGraph = _gpGraphA()
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), null)
	var gpNone: Array[int] = []
	# Only n1 is copied, so the n1–n2 edge has one end outside the set and must NOT be captured.
	# 只复制 n1，故 n1–n2 的边有一端在集合外，**不得**被捕获。
	gpSvc.gpCopySelection(["n1"], gpNone)
	gpEq(GPClipboard.gpNodes().size(), 1, "只捕获 n1 / only n1")
	gpEq(GPClipboard.gpEdges().size(), 0, "外部端点的边被排除 / edge with an outside end excluded")
	GPClipboard.gpClear()


func gpTestSecondCopyReplacesFirst() -> void:
	_gpClearClipboard()
	var gpG: GPPIDGraph = _gpGraphA()
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), null)
	var gpNone: Array[int] = []
	gpSvc.gpCopySelection(["n1"], gpNone)
	var gpRev: int = GPClipboard.gpRevision
	gpSvc.gpCopySelection(["n2"], gpNone)
	gpEq(GPClipboard.gpNodes().size(), 1, "仍是单节点 / still one node")
	gpCheck(GPClipboard.gpRevision > gpRev, "复制版本号递增 / the copy revision advanced")
	GPClipboard.gpClear()


# ---------------------------------------------------------------------------
# Paste into ANOTHER sheet
# 粘贴到**另一张**图纸
# ---------------------------------------------------------------------------

func gpTestPasteIntoAnotherSheetClonesIndependently() -> void:
	_gpClearClipboard()
	var gpA: GPPIDGraph = _gpGraphA()
	var gpSvcA: GPEditService = GPEditService.new()
	gpSvcA.gpBindGraph(gpA, GPIdGen.new(), null)
	gpSvcA.gpCopySelection(["n1", "n2"], [0])

	# A DIFFERENT graph: this is the cross-sheet case.
	# **另一张**图：这就是跨图纸的情形。
	var gpB: GPPIDGraph = GPPIDGraph.new()
	var gpCtxB: GPCommandContext = _gpCtx(gpB)
	var gpCmd: GPPasteClipboardCommand = GPPasteClipboardCommand.new(
		GPClipboard.gpNodes(), GPClipboard.gpEdges(), GPClipboard.gpShapes())
	gpCheck(gpCmd.gpExecute(gpCtxB), "粘贴成功 / paste succeeded")
	gpEq(gpB.gpNodes.size(), 2, "源图 2 节点被克隆 / both source nodes cloned")
	gpEq(gpB.gpEdges.size(), 1, "内部连线被克隆 / the internal edge cloned")
	gpEq(gpB.gpShapes.size(), 1, "图形被克隆 / the shape cloned")

	# Independence: mutating the paste must not touch the source, and vice versa.
	# 独立性：改粘贴结果不得改到源图，反之亦然。
	var gpPasted: GPPIDNode = gpB.gpNodes[0]
	gpPasted.gpTag = "P-9999"
	gpCheck(gpA.gpNodes[0].gpTag != "P-9999", "改副本不影响源图 / editing the clone leaves the source")
	gpCheck(gpPasted != gpA.gpNodes[0], "不是同一个对象 / a different object")


func gpTestPasteOffsetsTopLevelPositions() -> void:
	_gpClearClipboard()
	var gpA: GPPIDGraph = _gpGraphA()
	var gpSvcA: GPEditService = GPEditService.new()
	gpSvcA.gpBindGraph(gpA, GPIdGen.new(), null)
	gpSvcA.gpCopySelection(["n1"], [])
	var gpB: GPPIDGraph = GPPIDGraph.new()
	var gpCmd: GPPasteClipboardCommand = GPPasteClipboardCommand.new(
		GPClipboard.gpNodes(), GPClipboard.gpEdges(), GPClipboard.gpShapes())
	gpCmd.gpExecute(_gpCtx(gpB))
	gpEq(gpB.gpNodes.size(), 1, "一个节点 / one node")
	var gpPos: Vector2 = gpB.gpNodes[0].gpPosition
	gpApprox(gpPos.x, 10.0 + GPPasteClipboardCommand.GP_OFFSET.x, GP_EPS, "X 已偏移")
	gpApprox(gpPos.y, 10.0 + GPPasteClipboardCommand.GP_OFFSET.y, GP_EPS, "Y 已偏移")


func gpTestPasteUndoRemovesEverything() -> void:
	_gpClearClipboard()
	var gpA: GPPIDGraph = _gpGraphA()
	var gpSvcA: GPEditService = GPEditService.new()
	gpSvcA.gpBindGraph(gpA, GPIdGen.new(), null)
	gpSvcA.gpCopySelection(["n1", "n2"], [0])
	var gpB: GPPIDGraph = GPPIDGraph.new()
	var gpCmd: GPPasteClipboardCommand = GPPasteClipboardCommand.new(
		GPClipboard.gpNodes(), GPClipboard.gpEdges(), GPClipboard.gpShapes())
	var gpCtx: GPCommandContext = _gpCtx(gpB)
	gpCmd.gpExecute(gpCtx)
	gpCmd.gpUndo(gpCtx)
	gpEq(gpB.gpNodes.size(), 0, "撤销移除节点 / undo removes the nodes")
	gpEq(gpB.gpEdges.size(), 0, "撤销移除连线 / undo removes the edges")
	gpEq(gpB.gpShapes.size(), 0, "撤销移除图形 / undo removes the shapes")
	gpCmd.gpRedo(gpCtx)
	gpEq(gpB.gpNodes.size(), 2, "重做恢复节点 / redo restores the nodes")
	gpEq(gpB.gpEdges.size(), 1, "重做恢复连线 / redo restores the edge")


func gpTestPasteSkipsDanglingEdge() -> void:
	_gpClearClipboard()
	# A payload whose edge has a POINT end (dangling): it belongs to the source sheet.
	# 载荷中的边有一个**悬空**端点：它属于源图纸。
	var gpNodes: Array = [{"instance_id": "n1", "symbol_id": "sym", "tag": "", "position": [0.0, 0.0]}]
	var gpEdges: Array = [{
		"instance_id": "e1",
		"from_ref": {"node_id": "n1", "port_id": "p1"},
		"to_ref": {"point": [50.0, 50.0]},
		"kind": GPPIDEdge.GP_PROCESS, "signal_type": "", "tag": "", "ortho": true,
		"routing": [], "attrs": {},
	}]
	var gpB: GPPIDGraph = GPPIDGraph.new()
	var gpCmd: GPPasteClipboardCommand = GPPasteClipboardCommand.new(gpNodes, gpEdges, [])
	gpCmd.gpExecute(_gpCtx(gpB))
	gpEq(gpB.gpNodes.size(), 1, "节点仍粘贴 / the node is pasted")
	gpEq(gpB.gpEdges.size(), 0, "悬空端点的边被跳过 / a dangling-ended edge is skipped")


func gpTestPasteEmptyClipboardIsRefused() -> void:
	_gpClearClipboard()
	var gpB: GPPIDGraph = GPPIDGraph.new()
	var gpCmd: GPPasteClipboardCommand = GPPasteClipboardCommand.new([], [], [])
	gpCheck(not gpCmd.gpExecute(_gpCtx(gpB)), "空载荷被拒 / an empty payload is refused")


func gpTestPasteOrphanBecomesTopLevel() -> void:
	_gpClearClipboard()
	# The child's host is NOT in the payload: keeping the stale parent would mount it on nothing.
	# 子件的宿主**不在**载荷里：保留过期父件等于把节点挂在虚空上。
	var gpNodes: Array = [
		{"instance_id": "child", "symbol_id": "sym", "tag": "", "position": [0.0, 0.0],
			"parent_uid": "host_on_other_sheet", "mount_anchor": "top"},
	]
	var gpB: GPPIDGraph = GPPIDGraph.new()
	var gpCmd: GPPasteClipboardCommand = GPPasteClipboardCommand.new(gpNodes, [], [])
	gpCmd.gpExecute(_gpCtx(gpB))
	gpEq(gpB.gpNodes.size(), 1, "子件仍粘贴 / the child is pasted")
	gpEq(gpB.gpNodes[0].gpParentUid, "", "宿主缺失时降为顶层 / an absent host makes it top-level")
