extends "res://tests/gp_test.gd"
# Regression suite for GPCanvasSelection (P1-1b): mutual exclusion between node and shape
# selection, shift-toggle semantics, and primary-id mirror sync.
# GPCanvasSelection（P1-1b）回归套件：节点/图形选择的互斥、shift 切换语义、primary 镜像同步。

func gpTestSetNodesClearsShapes() -> void:
	var sel := GPCanvasSelection.new()
	sel.gpSetShapes([2, 5])
	gpCheck(sel.gpHasShape(2), "shape 2 selected")
	gpCheck(sel.gpHasShape(5), "shape 5 selected")
	var gpChanged: bool = sel.gpSetNodes(["n1", "n3"])
	gpCheck(gpChanged, "setNodes reports change")
	gpCheck(sel.gpHasNode("n1"), "node n1 selected")
	gpCheck(sel.gpHasNode("n3"), "node n3 selected")
	gpCheck(sel.gpShapes().is_empty(), "shapes cleared on setNodes")
	gpCheck(sel.gpPrimaryNodeId == "n1", "primary = first node")
	gpCheck(not sel.gpHasShape(2), "shape 2 gone")


func gpTestSetShapesClearsNodes() -> void:
	var sel := GPCanvasSelection.new()
	sel.gpSetNodes(["n1"])
	var gpChanged: bool = sel.gpSetShapes([7])
	gpCheck(gpChanged, "setShapes reports change")
	gpCheck(sel.gpNodes().is_empty(), "nodes cleared on setShapes")
	gpCheck(sel.gpPrimaryNodeId == "", "primary cleared with nodes")
	gpCheck(sel.gpHasShape(7), "shape 7 selected")


func gpTestNoChangeDetection() -> void:
	var sel := GPCanvasSelection.new()
	sel.gpSetNodes(["a"])
	var gpChanged: bool = sel.gpSetNodes(["a"])
	gpCheck(not gpChanged, "setting same nodes reports no change")
	sel.gpSetShapes([1])
	gpChanged = sel.gpSetShapes([1])
	gpCheck(not gpChanged, "setting same shape reports no change")


func gpTestToggleNodeSingle() -> void:
	var sel := GPCanvasSelection.new()
	# shift=false => single select
	sel.gpToggleNode("x", false)
	gpCheck(sel.gpNodes() == ["x"], "toggle node no-shift = [x]")
	gpCheck(sel.gpIsSingle(), "single selection")


func gpTestToggleNodeShiftAccumulate() -> void:
	var sel := GPCanvasSelection.new()
	sel.gpToggleNode("x", true)
	sel.gpToggleNode("y", true)
	gpCheck(sel.gpHasNode("x") and sel.gpHasNode("y"), "shift accumulate x,y")
	# shift-toggle off
	sel.gpToggleNode("x", true)
	gpCheck(not sel.gpHasNode("x"), "shift toggle removes x")
	gpCheck(sel.gpHasNode("y"), "y stays")
	gpCheck(sel.gpHasAny() and sel.gpIsSingle(), "y remains as a single selection")


func gpTestToggleShapeClearsNodesWhenEmpty() -> void:
	var sel := GPCanvasSelection.new()
	sel.gpSetNodes(["a", "b"])
	# shift add first shape clears node selection (was empty of shapes)
	sel.gpToggleShape(3, true)
	gpCheck(sel.gpNodes().is_empty(), "node selection cleared when adding first shape")
	gpCheck(sel.gpHasShape(3), "shape 3 added")
	gpCheck(sel.gpPrimaryNodeId == "", "primary cleared")


func gpTestClearAll() -> void:
	var sel := GPCanvasSelection.new()
	sel.gpSetNodes(["a"])
	sel.gpSetShapes([1, 2])
	sel.gpClearAll()
	gpCheck(not sel.gpHasAny(), "clear all empties both")
	gpCheck(sel.gpPrimaryNodeId == "", "primary cleared")


func gpTestIsSingle() -> void:
	var sel := GPCanvasSelection.new()
	gpCheck(not sel.gpHasAny() and not sel.gpIsSingle(), "empty not single")
	sel.gpToggleNode("n", true)
	gpCheck(sel.gpIsSingle(), "one node is single")
	sel.gpToggleNode("m", true)
	gpCheck(not sel.gpIsSingle(), "two nodes not single")
