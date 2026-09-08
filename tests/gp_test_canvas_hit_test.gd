extends "res://tests/gp_test.gd"
# Headless tests for GPCanvasHitTest (P5 extraction): node center / rect / hit, and annotation
# shape hit. Pure geometry, no Control/Node dependency, so it runs without a scene tree.
# GPCanvasHitTest 的 headless 测试（P5 抽取）：节点中心 / 矩形 / 命中，以及注释图形命中。纯几何、无
# Control/Node 依赖，无需场景树即可运行。

# A one-node graph with the node centered at (10,10).
# 单节点图，节点中心位于 (10,10)。
func _mkGraph() -> GPPIDGraph:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-101", Vector2(10, 10)))
	return g


# A binder whose only def ("pump") has a 80x40 envelope.
# 仅含一个定义（"pump"）的绑定器，包络 80x40。
func _mkBinder() -> GPGraphBinder:
	var b: GPGraphBinder = GPGraphBinder.new()
	var d: GPSymbolDef = GPSymbolDef.new()
	d.gpId = "pump"
	d.gpDefaultSize = Vector2(80.0, 40.0)
	b.gpDefs = [d]
	return b


func gpTestNodeCenter() -> void:
	var g: GPPIDGraph = _mkGraph()
	gpEq(GPCanvasHitTest.gpNodeCenter(g, "N1"), Vector2(10, 10), "node center is its position")
	gpEq(GPCanvasHitTest.gpNodeCenter(g, "NOPE"), Vector2.INF, "missing node -> INF")


func gpTestNodeRectUsesDefSize() -> void:
	var g: GPPIDGraph = _mkGraph()
	var b: GPGraphBinder = _mkBinder()
	var r: Rect2 = GPCanvasHitTest.gpNodeRect(g, b, "N1")
	gpEq(r.position, Vector2(10 - 40, 10 - 20), "rect top-left = center - half size")
	gpEq(r.size, Vector2(80, 40), "rect size from def envelope")
	b.free()  # GPGraphBinder 是 Node，不计引用，须显式释放以免 GUT 报 orphan


func gpTestNodeRectFallbackWhenDefMissing() -> void:
	var g: GPPIDGraph = _mkGraph()
	var b: GPGraphBinder = GPGraphBinder.new()  # no defs -> gpDefFor returns null
	var r: Rect2 = GPCanvasHitTest.gpNodeRect(g, b, "N1")
	gpEq(r.size, Vector2(64, 48), "missing def falls back to 64x48")
	b.free()  # GPGraphBinder 是 Node，不计引用，须显式释放以免 GUT 报 orphan


func gpTestNodeRectNullBinderIsEmpty() -> void:
	var g: GPPIDGraph = _mkGraph()
	var r: Rect2 = GPCanvasHitTest.gpNodeRect(g, null, "N1")
	gpEq(r, Rect2(), "null binder -> empty rect (matches prior canvas behaviour)")


func gpTestHitNode() -> void:
	var g: GPPIDGraph = _mkGraph()
	var b: GPGraphBinder = _mkBinder()
	gpEq(GPCanvasHitTest.gpHitNode(g, b, Vector2(10, 10)), "N1", "point on node hits it")
	gpEq(GPCanvasHitTest.gpHitNode(g, b, Vector2(9999, 9999)), "", "far point hits nothing")
	b.free()  # GPGraphBinder 是 Node，不计引用，须显式释放以免 GUT 报 orphan


func gpTestHitShape() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	var s: GPShape = GPShape.new()
	s.gpKind = GPShape.GPKind.GP_CIRCLE
	s.gpPoints = [Vector2(100, 100)]
	s.gpRadius = 20.0
	g.gpShapes.append(s)
	gpEq(GPCanvasHitTest.gpHitShape(g, Vector2(100, 100), 1.0), 0, "point at center hits shape 0")
	gpEq(GPCanvasHitTest.gpHitShape(g, Vector2(118, 100), 1.0), 0, "point within radius+tol hits")
	gpEq(GPCanvasHitTest.gpHitShape(g, Vector2(999, 999), 1.0), -1, "far point hits nothing")
