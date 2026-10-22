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


# ---------------------------------------------------------------------------
# A1: the status snapshot must describe every selection family
# A1：状态快照必须描述每一种选择
# ---------------------------------------------------------------------------
# History / 历史：the snapshot carried only nodes, so selecting an annotation shape or an edge
# made the status bar print "—" while the canvas drew the highlight. Two different lies, one cause.
# 历史：快照只带节点，故选中注释图形或连线时，画布在画高亮、状态栏却打「—」。两种谎，同一个原因。

# A canvas that never entered the tree still answers its status snapshot.
# 从未入树的画布也仍能产出状态快照。
func gpTestStatusSnapshotCarriesAllThreeFamilies() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	# A ONE-ELEMENT BOX, not a plain local: a GDScript lambda captures by VALUE, so assigning to a
	# captured local would silently leave the outer variable untouched (and the test would then
	# assert on an empty dictionary and blame production code). Appending to a captured Array works
	# because the array itself is shared.
	# 用**单元素盒子**而不是裸局部变量：GDScript 的 lambda 按**值**捕获，给被捕获的局部变量赋值
	# 不会改到外层（于是测试会对着空字典断言、并把锅甩给产品代码）。往被捕获的 Array 里 append
	# 是可行的，因为数组本身是共享的。
	var gpBox: Array = []
	gpCv.gpStatusUpdated.connect(func(gpIn: Dictionary) -> void: gpBox.append(gpIn))
	gpCv.gpEmitStatus()
	gpCheck(not gpBox.is_empty(), "探针：快照已发出 / probe: a snapshot was emitted")
	var gpInfo: Dictionary = gpBox[0] as Dictionary
	gpCheck(gpInfo.has("shapes"), "快照带图形计数 / snapshot carries shape count")
	gpCheck(gpInfo.has("edges"), "快照带连线计数 / snapshot carries edge count")
	gpEq(int(gpInfo.get("count", -1)), 0, "空选择节点计数为 0 / empty node count is 0")

	# One shape selected, no node: the family that used to be invisible.
	# 选中一个图形、无节点：此前完全不可见的那个族。
	gpCv.gpShapeSel = [0]
	gpCv.gpEmitStatus()
	# Read the LATEST snapshot, not the first one: gpInfo is a value copy taken above.
	# 读**最新**快照而非第一份：上面的 gpInfo 是值拷贝。
	var gpShapeInfo: Dictionary = gpBox[gpBox.size() - 1] as Dictionary
	gpEq(int(gpShapeInfo.get("shapes", -1)), 1, "图形计数为 1 / one shape reported")
	gpEq(str(gpShapeInfo.get("selection", "x")), "", "图形选择不伪造节点 id / shape selection fakes no node id")

	# One edge selected.
	# 选中一条连线。
	gpCv.gpShapeSel = []
	gpCv.gpEdgeSel = ["e1"]
	gpCv.gpEmitStatus()
	var gpEdgeInfo: Dictionary = gpBox[gpBox.size() - 1] as Dictionary
	gpEq(int(gpEdgeInfo.get("edges", -1)), 1, "连线计数为 1 / one edge reported")
	gpCv.free()


# The label composition rule: nodes win, then edges, then shapes; never two families at once.
# 文案合成规则：节点优先，其次连线，最后图形；绝不同时描述两族。
func gpTestSelectionTextPrecedence() -> void:
	var gpText: String = GPSelectionCoordinator.gpSelectionText({})
	gpEq(gpText, I18n.gpTr("status.selected") % I18n.gpTr("status.none"),
		"全空显示「—」/ empty shows the dash")

	gpText = GPSelectionCoordinator.gpSelectionText({"shapes": 2})
	gpEq(gpText, I18n.gpTr("status.selected_shapes") % 2,
		"图形选择有话说 / a shape selection now says something")

	gpText = GPSelectionCoordinator.gpSelectionText({"edges": 3})
	gpEq(gpText, I18n.gpTr("status.selected_edges") % 3,
		"连线选择有话说 / an edge selection says its own count")

	gpText = GPSelectionCoordinator.gpSelectionText({"selection": "P-1001", "count": 1})
	gpEq(gpText, I18n.gpTr("status.selected") % "P-1001",
		"单选节点显示位号 / one node shows its tag")

	gpText = GPSelectionCoordinator.gpSelectionText({"selection": "P-1001", "count": 3})
	gpEq(gpText, I18n.gpTr("status.selected_multi") % 3,
		"多选节点显示数量 / several nodes show a count")

	# Precedence: a node id always wins, even if stale counts of another family linger.
	# 优先级：只要节点 id 在，就压过其它族的残留计数。
	gpText = GPSelectionCoordinator.gpSelectionText({"selection": "V-1", "count": 1, "shapes": 4})
	gpEq(gpText, I18n.gpTr("status.selected") % "V-1",
		"节点优先于图形 / a node outranks a shape")
