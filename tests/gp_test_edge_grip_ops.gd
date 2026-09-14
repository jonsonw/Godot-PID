extends "res://tests/gp_test.gd"
# Headless tests for the revised edge-grip model (F23 / scheme a+b):
#   a) Every SELECTED edge exposes one BLUE square at the midpoint of each horizontal/vertical
#      segment. Dragging a blue grip RIGIDLY TRANSLATES that whole segment (both its routing
#      endpoints move by the same delta); the dangling/port ends are NOT routing vertices, so
#      they stay put and the line remains orthogonal. Interior segments (both ends are routing
#      waypoints) translate cleanly; a port-locked boundary segment falls back to the body-drag.
#   b) RIGHT-CLICK anywhere on a segment inserts an ORANGE bump anchor (a localised orthogonal
#      "tent"); the orange anchor is itself left-draggable to re-shape the bump. Right-click on
#      an edge body is never a context menu.
# 修订后边抓取点模型（F23 / 方案 a+b）的 headless 测试：
#   a) 选中边在每段横/竖线段中点显示一个蓝色方块；拖动蓝色方块「刚体平移」整段（其两端路由拐点同位移）；
#      悬空/端口端不在路由中故不动，整线保持正交。内部段（两端皆为路由拐点）平移干净；端口锁死的边界段
#      退化为线体拖拽。
#   b) 在任意线段右键插入橙色鼓包锚点（局部正交「帐篷」）；橙色锚点可左键拖动以重塑鼓包。边上右键永非菜单。
#
# Regression guards this pins / 本套件钉住的回归:
#   - 部分边选中后无可见可拖编辑点（现每段中点恒有抓取点）
#   - 顶点抓取点自由拖动产生非正交偏移（现段中点 + 刚体平移，结果恒正交）
#   - 往回拉时端点出现 14px 回折 / 小缺口（现局部帐篷避开引出段，无回折）

# Build a dangling-ended edge (no symbol defs needed -> resolver returns the point directly).
# 构造一条悬空端边（无需图元定义 -> 解析器直接返回该点）。
func _mkEdge(gpFrom: Vector2, gpTo: Vector2, gpRouting: Array[Vector2] = []) -> GPPIDEdge:
	var e: GPPIDEdge = GPPIDEdge.new()
	e.gpInstanceId = "e1"
	e.gpFromRef = {"node_id": "", "port_id": "", "point": [gpFrom.x, gpFrom.y]}
	e.gpToRef = {"node_id": "", "port_id": "", "point": [gpTo.x, gpTo.y]}
	e.gpKind = "PROCESS"
	e.gpRouting = gpRouting
	return e


# Resolved polyline = [danglingFrom] + routing + [danglingTo]. / 已解析折线。
func _poly(gpE: GPPIDEdge) -> PackedVector2Array:
	var p: PackedVector2Array = PackedVector2Array()
	p.append(gpE.gpDanglingPoint(true))
	for r in gpE.gpRouting:
		p.append(r)
	p.append(gpE.gpDanglingPoint(false))
	return p


# Fully routable polyline for a dangling-ended edge: route the stored waypoints through
# GPEdgeRoute.gpRoute (no stubs, since dangling ends have none) so the result is the SAME orthogonal
# polyline the renderer draws. Used to test the bump shape after the "localised tent" fix, where the
# raw [from]+routing+[to] concatenation is no longer axis-aligned on its own.
# 悬空端边的「可渲染」折线：把已存折点经 GPEdgeRoute.gpRoute 布线（无引出段），得到与渲染器一致的
# 正交折线。用于在「局部帐篷」修复后验证鼓包形状。
func _routed(gpE: GPPIDEdge) -> PackedVector2Array:
	return GPEdgeRoute.gpRoute(
		{"pos": gpE.gpDanglingPoint(true), "dir": Vector2.ZERO, "bound": false},
		{"pos": gpE.gpDanglingPoint(false), "dir": Vector2.ZERO, "bound": false},
		gpE.gpRouting, gpE.gpOrtho)


# Build a REAL port-to-port edge (n1.out -> n2.in) with a symbol def carrying in/out nozzles.
# Unlike the dangling edges above, this exercises GPPortResolver.gpResolveEnd through the def
# lookup — the exact path the LIVE editor uses, and the path that the F23 unit tests missed.
# 构造真实「端口到端口」边（n1.out -> n2.in）及带 in/out 接嘴的图元定义。与上方悬空边不同，本构造
# 经定义查找走通 GPPortResolver.gpResolveEnd —— 正是活动编辑器所用的路径。
func _mkRealEdge() -> Dictionary:
	var def := GPSymbolDef.new()
	def.gpId = "PUMP"
	def.gpPorts = [
		GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
	]
	var g := GPPIDGraph.new()
	var n1 := GPPIDNode.new()
	n1.gpInstanceId = "n1"; n1.gpSymbolId = "PUMP"; n1.gpPosition = Vector2(0.0, 0.0)
	g.gpAddNode(n1)
	var n2 := GPPIDNode.new()
	n2.gpInstanceId = "n2"; n2.gpSymbolId = "PUMP"; n2.gpPosition = Vector2(320.0, 160.0)
	g.gpAddNode(n2)
	# gpOrtho defaults true (orthogonal P&ID pipe). / gpOrtho 默认 true（正交 P&ID 管线）。
	var e := g.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": "out"}, {"node_id": "n2", "port_id": "in"},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	g.gpAddEdge(e)
	# off-tree the canvas' binder is null, so seed it so gpDefLookupCallable can resolve the def.
	# off-tree 时画布绑定器为 null，故注入定义使 gpDefLookupCallable 能解析。
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	cv.gpBinder = GPGraphBinder.new()
	cv.gpBinder.gpDefs = [def]
	return {"cv": cv, "g": g, "def": def, "e": e}


# Find the midpoint grip of an axis-aligned run (horizontal when gpHorizontal, else vertical) whose
# length exceeds gpMinLen. Returns an empty dict when none qualifies. Used by the bump tests so they
# click a real run instead of a short stub. / 在已解析折线上找一条「横/竖、长度>阈值」段的段中点抓取点。
func _gpFindRunGrip(gpPts: PackedVector2Array, gpHorizontal: bool, gpMinLen: float) -> Dictionary:
	var gs: Array[Dictionary] = GPEdgeGripOps.gpMidpointGrips(gpPts)
	for gpG in gs:
		var gpS: int = int(gpG.get("seg", -1))
		if gpS < 0 or gpS + 1 >= gpPts.size():
			continue
		var gpA: Vector2 = gpPts[gpS]
		var gpB: Vector2 = gpPts[gpS + 1]
		var gpAligned: bool = (gpHorizontal and absf(gpA.y - gpB.y) <= 0.5) or (not gpHorizontal and absf(gpA.x - gpB.x) <= 0.5)
		if gpAligned and gpA.distance_to(gpB) >= gpMinLen:
			return gpG
	return {}


# --- pure static geometry ---

# One grip per segment, exactly at the midpoint, kind "mid". / 每段一个抓取点，恰在段中点，kind 为 mid。
func gpTestMidpointGripsPerSegment() -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(200, 100)])
	var gs: Array[Dictionary] = GPEdgeGripOps.gpMidpointGrips(pts)
	gpEq(gs.size(), 3, "3 segments -> 3 midpoint grips / 3 段得 3 个中点抓取点")
	for gpI in range(gs.size()):
		gpEq(str(gs[gpI]["kind"]), "mid", "grip kind is mid / 抓取点类型 mid")
		gpEq(int(gs[gpI]["seg"]), gpI, "grip seg index matches order / 段下标与顺序一致")
		var m: Vector2 = gs[gpI]["pos"]
		var gpExp: Vector2 = (pts[gpI] + pts[gpI + 1]) * 0.5
		gpApprox(m.x, gpExp.x, 0.001, "grip x at segment midpoint / 抓取点 x 在段中点")
		gpApprox(m.y, gpExp.y, 0.001, "grip y at segment midpoint / 抓取点 y 在段中点")


# Bump stays orthogonal for horizontal, vertical, and near-diagonal segments — even with an
# off-axis (diagonal) cursor. / 水平/垂直/近斜段鼓出均保持正交，即便光标离轴（斜向）。
func gpTestBumpOrthogonalAllOrientations() -> void:
	var gpWh: Array[Vector2] = GPEdgeGripOps.gpBumpWaypoints(Vector2(0, 0), Vector2(100, 0), Vector2(80, 30))
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(GPEdgeRoute.gpRoute(
		{"pos": Vector2(0, 0), "dir": Vector2(1, 0), "bound": false},
		{"pos": Vector2(100, 0), "dir": Vector2(-1, 0), "bound": false}, gpWh, true)),
		"horizontal bump stays orthogonal / 水平段鼓出恒正交")
	var gpWv: Array[Vector2] = GPEdgeGripOps.gpBumpWaypoints(Vector2(0, 0), Vector2(0, 100), Vector2(30, 80))
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(GPEdgeRoute.gpRoute(
		{"pos": Vector2(0, 0), "dir": Vector2(0, 1), "bound": false},
		{"pos": Vector2(0, 100), "dir": Vector2(0, -1), "bound": false}, gpWv, true)),
		"vertical bump stays orthogonal / 垂直段鼓出恒正交")
	var gpWd: Array[Vector2] = GPEdgeGripOps.gpBumpWaypoints(Vector2(0, 0), Vector2(100, 100), Vector2(50, 80))
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(GPEdgeRoute.gpRoute(
		{"pos": Vector2(0, 0), "dir": Vector2(0.7071, 0.7071), "bound": false},
		{"pos": Vector2(100, 100), "dir": Vector2(-0.7071, -0.7071), "bound": false}, gpWd, true)),
		"diagonal segment bump stays orthogonal / 斜段鼓出恒正交")


# --- scheme a: blue midpoint grip = rigid segment translate ---

# A straight horizontal edge exposes exactly one midpoint grip at its centre. / 直水平边恰在中心暴露一个中点抓取点。
func gpTestStraightEdgeHasOneMidGrip() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	var e: GPPIDEdge = _mkEdge(Vector2(0, 0), Vector2(100, 0), [])
	g.gpAddEdge(e)
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var hit: Dictionary = grips.gpHitGrip(Vector2(50, 0), "e1")
	gpCheck(not hit.is_empty(), "grip hit on the straight edge / 直边命中抓取点")
	gpEq(str(hit.get("kind", "")), "mid", "grip kind is 'mid' / 抓取点类型为 mid")
	gpEq(int(hit.get("seg", -1)), 0, "single segment index 0 / 单段下标 0")
	var ms: Vector2 = hit.get("pos", Vector2.ZERO)
	gpApprox(ms.x, 50.0, 0.001, "midpoint x at 50 / 中点 x=50")
	gpApprox(ms.y, 0.0, 0.001, "midpoint y at 0 / 中点 y=0")
	cv.free()


# Dragging the blue grip of an INTERIOR VERTICAL run (both ends are routing waypoints) shifts the
# whole run sideways; both routing vertices move by the same delta, the dangling ends are untouched,
# and the path stays orthogonal. / 拖动「内部竖段」（两端皆为路由拐点）的蓝色抓取点使整段横向平移；
# 两路由拐点同位移、悬空端不动、路径保持正交。
func gpTestInteriorVerticalSegmentTranslate() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	# (0,0)->(100,0)->(100,200)->(300,200): seg1 (100,0)->(100,200) is the interior vertical run.
	# (0,0)->(100,0)->(100,200)->(300,200)：seg1 (100,0)->(100,200) 为内部竖段。
	var e: GPPIDEdge = _mkEdge(Vector2(0, 0), Vector2(300, 200), [Vector2(100, 0), Vector2(100, 200)])
	g.gpAddEdge(e)
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var hit: Dictionary = grips.gpHitGrip(Vector2(100, 100), "e1")  # midpoint of the vertical run / 竖段中点
	gpCheck(not hit.is_empty(), "grip hit on the vertical run / 命中竖段抓取点")
	gpEq(int(hit.get("seg", -1)), 1, "vertical run is segment index 1 / 竖段为段下标 1")
	grips.gpStartGripDrag("e1", hit)
	grips.gpOnGripMove(Vector2(140, 100))  # shift the run right by 40 / 整段右移 40
	gpApprox(e.gpRouting[0].x, 140.0, 0.001, "waypoint (100,0) moved to x=140 / 拐点(100,0) 移到 x=140")
	gpApprox(e.gpRouting[1].x, 140.0, 0.001, "waypoint (100,200) moved to x=140 / 拐点(100,200) 移到 x=140")
	gpApprox(e.gpRouting[0].y, 0.0, 0.001, "first waypoint y unchanged / 首拐点 y 不变")
	gpApprox(e.gpRouting[1].y, 200.0, 0.001, "second waypoint y unchanged / 次拐点 y 不变")
	gpApprox(e.gpDanglingPoint(true).x, 0.0, 0.001, "dangling from x unchanged / 悬空起点 x 不变")
	gpApprox(e.gpDanglingPoint(false).x, 300.0, 0.001, "dangling to x unchanged / 悬空终点 x 不变")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)),
		"path stays orthogonal after vertical-run translate / 竖段平移后路径仍正交")
	cv.free()


# Dragging the blue grip of an INTERIOR HORIZONTAL run shifts it vertically; both routing vertices
# move, the boundary waypoints and dangling ends stay put, and the path stays orthogonal.
# 拖动「内部水平段」蓝色抓取点使整段纵向平移；两路由拐点移动、边界拐点与悬空端不动、路径保持正交。
func gpTestInteriorHorizontalSegmentTranslate() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	# (0,0)->(100,0)->(100,50)->(200,50)->(300,50): seg2 (100,50)->(200,50) is the interior horizontal run.
	# (0,0)->(100,0)->(100,50)->(200,50)->(300,50)：seg2 (100,50)->(200,50) 为内部水平段。
	# Step geometry so the interior horizontal run (100,50)->(200,50) is bounded by verticals on BOTH
	# sides and therefore cannot be collapsed by gpRoute's collinear-point removal.
	# 阶梯几何：内部水平段 (100,50)->(200,50) 两侧皆为竖段，故 gpRoute 的共线点剔除不会把它吞掉。
	var e: GPPIDEdge = _mkEdge(Vector2(0, 0), Vector2(300, 100),
		[Vector2(100, 0), Vector2(100, 50), Vector2(200, 50), Vector2(200, 100)])
	g.gpAddEdge(e)
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var hit: Dictionary = grips.gpHitGrip(Vector2(150, 50), "e1")  # midpoint of the horizontal run / 水平段中点
	gpCheck(not hit.is_empty(), "grip hit on the horizontal run / 命中水平段抓取点")
	gpEq(int(hit.get("seg", -1)), 2, "horizontal run is segment index 2 / 水平段为段下标 2")
	grips.gpStartGripDrag("e1", hit)
	grips.gpOnGripMove(Vector2(150, 90))  # shift the run down by 40 / 整段下移 40
	gpApprox(e.gpRouting[1].y, 90.0, 0.001, "waypoint (100,50) moved to y=90 / 拐点(100,50) 移到 y=90")
	gpApprox(e.gpRouting[2].y, 90.0, 0.001, "waypoint (200,50) moved to y=90 / 拐点(200,50) 移到 y=90")
	gpApprox(e.gpRouting[0].x, 100.0, 0.001, "boundary waypoint (100,0) unchanged / 边界拐点(100,0) 不变")
	gpApprox(e.gpRouting[0].y, 0.0, 0.001, "boundary waypoint y unchanged / 边界拐点 y 不变")
	gpApprox(e.gpDanglingPoint(false).y, 100.0, 0.001, "dangling to y unchanged / 悬空终点 y 不变")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)),
		"path stays orthogonal after horizontal-run translate / 水平段平移后路径仍正交")
	cv.free()


# A bent edge: translating one interior segment keeps the whole path orthogonal and the waypoint
# COUNT unchanged (translate never inserts vertices, unlike a bump). / 弯边：平移一内部段后整条路径仍正交，
# 且拐点数量不变（平移不像鼓包那样插入顶点）。
func gpTestBentEdgeInteriorSegmentTranslate() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	var e: GPPIDEdge = _mkEdge(Vector2(0, 0), Vector2(300, 200), [Vector2(100, 0), Vector2(100, 200)])
	g.gpAddEdge(e)
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var hit: Dictionary = grips.gpHitGrip(Vector2(100, 100), "e1")
	gpEq(int(hit.get("seg", -1)), 1, "interior segment hit (index 1) / 命中内部段（下标1）")
	var gpBefore: int = e.gpRouting.size()
	grips.gpStartGripDrag("e1", hit)
	grips.gpOnGripMove(Vector2(140, 100))
	gpEq(e.gpRouting.size(), gpBefore, "translate inserts no waypoints / 平移不插入拐点")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)),
		"bent edge path stays orthogonal after segment translate / 弯边段平移后路径仍正交")
	cv.free()


# A REAL port-to-port edge with a bend: translating its interior vertical run keeps the whole route
# orthogonal — the regression guard for "连线拖动后不再正交". / 真实端口到端口弯边：平移其内竖段后整条布线
# 仍正交——针对「连线拖动后不再正交」的回归守卫。
func gpTestRealEdgeInteriorSegmentTranslate() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	# Add a bend so there is an interior vertical run at x=160. / 加一个弯，使 x=160 处有内部竖段。
	e.gpRouting = [Vector2(160, 0), Vector2(160, 160)]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, false, 80.0)  # vertical run, length >= 80 / 竖段
	gpCheck(not gpG.is_empty(), "real edge exposes an interior vertical run grip / 真实边暴露内部竖段抓取点")
	# The exact segment index depends on whether a 14px stub is emitted; assert the FOUND run is the
	# vertical one instead of hard-coding the index. / 段下标取决于是否长出 14px 引出段，故断言找到的段确为竖段，
	# 而非写死下标。
	var gpS: int = int(gpG.get("seg", -1))
	gpCheck(absf(pts[gpS].x - pts[gpS + 1].x) <= 0.5, "found run is vertical / 找到的段为竖段")
	grips.gpStartGripDrag("e1", gpG)
	grips.gpOnGripMove(Vector2(gpG["pos"].x + 40.0, gpG["pos"].y))
	gpEq(e.gpRouting.size(), 2, "translate keeps two waypoints / 平移后仍为两拐点")
	gpApprox(e.gpRouting[0].x, 200.0, 0.001, "waypoint (160,0) moved to x=200 / 拐点(160,0) 移到 x=200")
	gpApprox(e.gpRouting[1].x, 200.0, 0.001, "waypoint (160,160) moved to x=200 / 拐点(160,160) 移到 x=200")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)),
		"real-edge interior segment translate stays orthogonal / 真实边内部段平移保持正交")
	cv.free()


# --- F23 closure: real port-to-port edges (the LIVE path the dangling tests above never touch) ---

# Regression for the "selected edge shows no grips" defect (orthogonal port-to-port pipe). The grip
# polyline MUST be computed by GPEdgeRoute.gpRoute — the SAME routine the renderer and the hit-test use.
# 针对「选中边无抓取点」缺陷（正交端口到端口管线）的回归。抓取点折线必须经 GPEdgeRoute.gpRoute。
func gpTestRealPortEdgePolylineMatchesRenderer() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var g: GPPIDGraph = f["g"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var lookup: Callable = cv.gpDefLookupCallable()
	var want: String = GPPortResolver.gpWantTypeFor(e)
	var A: Dictionary = GPPortResolver.gpResolveEnd(g, lookup, e, true, want)
	var B: Dictionary = GPPortResolver.gpResolveEnd(g, lookup, e, false, want)
	var expected: PackedVector2Array = GPEdgeRoute.gpRoute(A, B, e.gpRouting, e.gpOrtho)
	gpEq(pts.size(), expected.size(),
		"real edge grip polyline uses GPEdgeRoute (vertex count matches renderer / 顶点数同渲染器)")
	for i in range(pts.size()):
		gpApprox(pts[i].x, expected[i].x, 0.001,
			"grip polyline x matches rendered polyline at vertex %d / 顶点 %d x 与渲染器一致" % [i, i])
		gpApprox(pts[i].y, expected[i].y, 0.001,
			"grip polyline y matches rendered polyline at vertex %d / 顶点 %d y 与渲染器一致" % [i, i])
	cv.free()


# Every midpoint grip of a real orthogonal edge must lie ON the edge's hittable line, so a click on
# the visible pipe both selects the edge and (via gpDrawGrips) draws the grips there.
# 真实正交边的每个中点抓取点都必须落在边的可命中线上，使点击可见管线既能选中边、又能绘出抓取点。
func gpTestRealPortEdgeGripsOnRenderedLine() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gs: Array[Dictionary] = GPEdgeGripOps.gpMidpointGrips(pts)
	gpCheck(gs.size() >= 1, "real orthogonal edge exposes >=1 midpoint grip / 真实正交边至少暴露一个中点抓取点")
	for gpG in gs:
		var p: Vector2 = gpG["pos"]
		var hit: String = cv.gpHitEdge(p)
		gpEq(hit, "e1", "grip at %s lies on the rendered edge and is hittable / 抓取点位于已渲染边且可命中" % str(p))
	cv.free()


# --- scheme b: right-click creates an orange bump anchor ---

# Right-clicking a segment inserts a localised orthogonal tent (two waypoints) AND records one orange
# anchor at the apex, without disturbing the rest of the routing. / 右键点击线段插入局部正交帐篷（两拐点）
# 并于顶点记下橙色锚点，且不扰动其余路由。
func gpTestRightClickCreatesBumpAnchor() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var gpBefore: int = e.gpRouting.size()
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)  # a long horizontal run / 一条较长水平段
	gpCheck(not gpG.is_empty(), "found a horizontal run to right-click / 找到可右键的水平段")
	var gpMid: Vector2 = gpG["pos"]
	var gpClick: Vector2 = Vector2(gpMid.x, gpMid.y + 40.0)  # 40px perpendicular depth / 垂直 40px 深
	grips.gpStartBump("e1", gpClick)
	gpEq(e.gpRouting.size(), gpBefore + 2, "right-click inserts two waypoints / 右键插入两个拐点")
	gpCheck(grips._gpBumpAnchors.has("e1"), "an orange anchor is recorded / 已记录橙色锚点")
	gpEq(grips._gpBumpAnchors["e1"].size(), 1, "exactly one anchor recorded / 恰记录一枚锚点")
	# The recorded anchor sits at the tent apex: same x as the click, y pushed to the cursor depth.
	# 记录的锚点位于帐篷顶点：x 同点击处，y 推到光标深度。
	# Index-based model: the stored value is the ROUTING-PAIR index; the apex is DERIVED from the
	# routing pair, so it always sits on the line. / 下标模型：存储值为 routing 对下标，顶点由 routing
	# 对推导，恒在线上。
	var gpRIdx: int = int(grips._gpBumpAnchors["e1"][0])
	gpCheck(gpRIdx + 1 < e.gpRouting.size(), "stored index points at a valid routing pair / 下标指向合法 routing 对")
	var gpApex: Vector2 = (e.gpRouting[gpRIdx] + e.gpRouting[gpRIdx + 1]) * 0.5
	gpApprox(gpApex.x, gpClick.x, 1.0, "apex x tracks the click x / 顶点 x 跟随点击 x")
	gpApprox(gpApex.y, gpClick.y, 1.0, "apex y equals cursor depth / 顶点 y 等于光标深度")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)),
		"bump keeps the path orthogonal / 鼓包后路径仍正交")
	cv.free()


# Create a bump via right-click, then LEFT-DRAG its orange anchor: the bump re-shapes (the two
# waypoints move to a fresh tent under the cursor) while the waypoint COUNT stays 2 and the path stays
# orthogonal. / 右键生成鼓包后左键拖动其橙色锚点：鼓包重塑（两拐点移到光标下新帐篷），拐点数仍为 2 且路径正交。
func gpTestBumpAnchorDragReshapes() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)
	gpCheck(not gpG.is_empty(), "found a horizontal run / 找到水平段")
	grips.gpStartBump("e1", Vector2(gpG["pos"].x, gpG["pos"].y + 40.0))
	gpEq(e.gpRouting.size(), 2, "one bump = two waypoints / 一个鼓包=两拐点")
	# Drag by ARRAY index (the value gpHitBump returns), not by world position.
	# 按数组下标（gpHitBump 返回的 anchor）拖动，而非世界坐标。
	grips.gpStartBumpDrag("e1", 0)
	grips.gpOnGripMove(Vector2(gpG["pos"].x, gpG["pos"].y + 70.0))  # deeper than the +40 at creation
	gpEq(e.gpRouting.size(), 2, "reshape keeps two waypoints / 重塑后仍为两拐点")
	var gpRIdx: int = int(grips._gpBumpAnchors["e1"][0])
	var gpApex: Vector2 = (e.gpRouting[gpRIdx] + e.gpRouting[gpRIdx + 1]) * 0.5
	gpApprox(gpApex.x, gpG["pos"].x, 1.0, "apex x tracks drag x / 顶点 x 跟随拖动 x")
	gpApprox(gpApex.y, gpG["pos"].y + 70.0, 6.0, "apex y tracks drag depth / 顶点 y 跟随拖动深度")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)),
		"reshaped bump stays orthogonal / 重塑后鼓包仍正交")
	cv.free()


# A shallow right-click bump (small perpendicular depth) must still be orthogonal and must NOT create
# a port->stub->back-to-port backtrack at either end (no repeated vertex). / 浅右键鼓包（小垂直深度）仍须正交，
# 且两端不得出现「端口→伸出→折返端口」回折（无重复顶点）。
func gpTestSmallBumpNoEndpointBacktrack() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)
	gpCheck(not gpG.is_empty(), "found a horizontal run / 找到水平段")
	grips.gpStartBump("e1", Vector2(gpG["pos"].x, gpG["pos"].y + 8.0))  # shallow: 8px deep / 浅：仅 8px 深
	gpEq(e.gpRouting.size(), 2, "shallow bump still = two waypoints / 浅鼓包仍为两拐点")
	var gpP: PackedVector2Array = grips._gpPolyline(e)
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(gpP), "shallow bump stays orthogonal / 浅鼓包仍正交")
	var gpSeen: Dictionary = {}
	for i in range(gpP.size()):
		var k: String = "%.2f,%.2f" % [gpP[i].x, gpP[i].y]
		gpCheck(not gpSeen.has(k), "no repeated vertex at index %d (no backtrack) / 第 %d 顶点无重复（无回折）" % [i, i])
		gpSeen[k] = true
	cv.free()


# Requirement: an orange bump anchor must ALWAYS ride the line — a whole-line move must carry the anchor
# with it (its apex is DERIVED from the routing, which the move shifts rigidly).
# 需求：橙色鼓包锚点须「永远贴线」——整线平移须带动锚点（其顶点由 routing 推导，平移整体刚性移动 routing）。
func gpTestBumpAnchorFollowsWholeLineMove() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)
	gpCheck(not gpG.is_empty(), "found a horizontal run / 找到水平段")
	grips.gpStartBump("e1", Vector2(gpG["pos"].x, gpG["pos"].y + 40.0))
	var gpIdx: int = int(grips._gpBumpAnchors["e1"][0])
	var gpApexBefore: Vector2 = (e.gpRouting[gpIdx] + e.gpRouting[gpIdx + 1]) * 0.5
	# Whole-line move by delta (+50, -25): the bump anchor must ride the line.
	# 整线平移 delta=(+50,-25)：锚点须随线移动。
	grips.gpStartEdgeMove("e1", Vector2(10, 10))
	grips.gpOnEdgeMove(Vector2(60, -15))
	var gpIdx2: int = int(grips._gpBumpAnchors["e1"][0])
	gpEq(gpIdx2, gpIdx, "bump pair index is stable across a rigid move / 整线平移后鼓包对下标不变")
	var gpApexAfter: Vector2 = (e.gpRouting[gpIdx2] + e.gpRouting[gpIdx2 + 1]) * 0.5
	gpApprox(gpApexAfter.x, gpApexBefore.x + 50.0, 0.001, "apex x follows whole-line move / 顶点 x 随整线平移")
	gpApprox(gpApexAfter.y, gpApexBefore.y - 25.0, 0.001, "apex y follows whole-line move / 顶点 y 随整线平移")
	cv.free()


# Requirement: a bump anchor can be deleted, and deleting one shifts the LATER anchors' pair indices.
# 需求：鼓包锚点可删除；删除其一会使后续锚点的对下标回移。
func gpTestDeleteBumpAnchor() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)
	gpCheck(not gpG.is_empty(), "found a horizontal run / 找到水平段")
	# Two bumps so we can also verify the SECOND one's index shifts after the FIRST is deleted.
	# 建两个鼓包，以便验证删除第一个后第二个的下标会回移。
	grips.gpStartBump("e1", Vector2(gpG["pos"].x, gpG["pos"].y + 40.0))
	grips.gpStartBump("e1", Vector2(gpG["pos"].x + 40.0, gpG["pos"].y + 40.0))
	gpEq(e.gpRouting.size(), 4, "two bumps = four waypoints / 两鼓包=四拐点")
	gpEq(grips._gpBumpAnchors["e1"].size(), 2, "two anchors recorded / 两锚点已记录")
	var gpSecIdx: int = int(grips._gpBumpAnchors["e1"][1])
	grips.gpDeleteBump("e1", 0)
	gpEq(e.gpRouting.size(), 2, "deleting first bump removes two waypoints / 删首鼓包移除两拐点")
	gpEq(grips._gpBumpAnchors["e1"].size(), 1, "one anchor remains / 剩一枚锚点")
	gpEq(int(grips._gpBumpAnchors["e1"][0]), gpSecIdx - 2, "second bump's pair index shifted down by 2 / 第二鼓包对下标回移 2")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)), "path stays orthogonal after delete / 删除后仍正交")
	cv.free()


# Requirement: a SELECTED bump anchor can be deleted through the same path the Del key uses.
# 需求：选中的鼓包锚点可按 Del 键所用的同一路径删除。
func gpTestDeleteBumpAnchorViaSelection() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)
	gpCheck(not gpG.is_empty(), "found a horizontal run / 找到水平段")
	grips.gpStartBump("e1", Vector2(gpG["pos"].x, gpG["pos"].y + 40.0))
	grips.gpSelectBump("e1", 0)
	gpCheck(not grips.gpSelectedBump().is_empty(), "bump selected / 锚点已选中")
	var gpB: Dictionary = grips.gpSelectedBump()
	grips.gpDeleteBump(gpB.get("eid", ""), int(gpB.get("ai", -1)))
	gpEq(grips._gpBumpAnchors["e1"].size(), 0, "anchor gone after delete / 删除后锚点消失")
	gpCheck(grips.gpSelectedBump().is_empty(), "selection cleared after delete / 删除后选择清空")
	cv.free()


# Regression guard for the "drag splits the line at the cursor" defect: dragging the BODY of an edge
# must translate the whole line rigidly — every routing waypoint shifts by the SAME delta, no new
# vertices are inserted — instead of bending at the click point (which is what the midpoint grip does).
# 回归守卫「拖动把线在光标处折断」：拖动边的线体须整条刚性平移——每个路由拐点按同一位移平移、不插入
# 新顶点 —— 而非在点击处折断。
func gpTestWholeLineMoveTranslatesRouting() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	var e: GPPIDEdge = _mkEdge(Vector2(0, 0), Vector2(200, 200),
		[Vector2(100, 0), Vector2(100, 100)])
	g.gpAddEdge(e)
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	grips.gpStartEdgeMove("e1", Vector2(50, 0))
	grips.gpOnEdgeMove(Vector2(90, -25))
	gpEq(e.gpRouting.size(), 2, "body drag does not insert vertices / 线体拖动不插入顶点")
	gpApprox(e.gpRouting[0].x, 140.0, 0.001, "waypoint 0 x shifted by +40 / 拐点0 x 平移 +40")
	gpApprox(e.gpRouting[0].y, -25.0, 0.001, "waypoint 0 y shifted by -25 / 拐点0 y 平移 -25")
	gpApprox(e.gpRouting[1].x, 140.0, 0.001, "waypoint 1 x shifted by +40 / 拐点1 x 平移 +40")
	gpApprox(e.gpRouting[1].y, 75.0, 0.001, "waypoint 1 y shifted by -25 / 拐点1 y 平移 -25")
	gpApprox(e.gpRouting[0].x, e.gpRouting[1].x, 0.001, "relative layout preserved / 相对布局保持")
	cv.free()


# A body drag also carries a dangling END along rigidly with the rest of the line.
# 线体拖动也会把悬空端随整条线一起刚性带走。
func gpTestWholeLineMoveCarriesDanglingEnd() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	var e: GPPIDEdge = _mkEdge(Vector2(0, 0), Vector2(200, 0), [Vector2(100, 0)])
	g.gpAddEdge(e)
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	gpCheck(e.gpIsDangling(true), "from-end is dangling before move / 移动前起点悬空")
	grips.gpStartEdgeMove("e1", Vector2(50, 0))
	grips.gpOnEdgeMove(Vector2(70, 30))
	var gpNewFrom: Vector2 = e.gpDanglingPoint(true)
	gpApprox(gpNewFrom.x, 20.0, 0.001, "dangling from x shifted by +20 / 悬空起点 x 平移 +20")
	gpApprox(gpNewFrom.y, 30.0, 0.001, "dangling from y shifted by +30 / 悬空起点 y 平移 +30")
	gpApprox(e.gpRouting[0].x, 120.0, 0.001, "waypoint x shifted by +20 / 拐点 x 平移 +20")
	gpApprox(e.gpRouting[0].y, 30.0, 0.001, "waypoint y shifted by +30 / 拐点 y 平移 +30")
	cv.free()
