extends "res://tests/gp_test.gd"
# Headless tests for the revised edge-grip model (F23, corner model):
#   a) Every SELECTED edge exposes one BLUE square at the midpoint of each horizontal/vertical
#      segment. Dragging a blue grip RIGIDLY TRANSLATES that whole segment (both its routing
#      endpoints move by the same delta); the dangling/port ends are NOT routing vertices, so
#      they stay put and the line remains orthogonal. A straight port-to-port edge (no routing
#      vertex to translate) falls back to inserting a corner and dragging it, so it stays draggable.
#   b) RIGHT-CLICK anywhere on a segment inserts an ORANGE CORNER (a SINGLE routing vertex, offset
#      perpendicular by GP_CORNER_OFFSET so it is a real bend). The corner is itself left-draggable to
#      MOVE that vertex; gpRoute re-orthogonalizes the two legs. RIGHT-CLICK on an EXISTING corner opens
#      a "delete corner" menu; a selected corner is also deleted by the Del key. Deleting the vertex
#      removes the corner and gpRoute reconnects the section orthogonally.
# 修订后边抓取点模型（F23，角点模型）的 headless 测试：
#   a) 选中边在每段横/竖线段中点显示一个蓝色方块；拖动蓝色方块「刚体平移」整段（其两端路由拐点同位移）；
#      悬空/端口端不在路由中故不动，整线保持正交。纯直线端口边（无可平移环路点）退化为「插入角点并拖动」，
#      故仍可被拖动。
#   b) 在任意线段右键插入橙色角点（单个 routing 顶点，沿垂直方向偏移 GP_CORNER_OFFSET 成为真实拐角）；
#      角点可左键拖动以移动该顶点，gpRoute 自动正交化两条腿。右键命中既有角点弹「删除角点」菜单；选中
#      角点按 Del 亦可删除。删除顶点即删角点，gpRoute 自动把该段重新正交连接。
#
# Regression guards this pins / 本套件钉住的回归:
#   - 部分边选中后无可见可拖编辑点（现每段中点恒有抓取点）
#   - 顶点抓取点自由拖动产生非正交偏移（现段中点 + 刚体平移，结果恒正交）
#   - 纯直线边不可拖动（现线体按下即插入角点并拖动，始终可拖）
#   - 橙色角点删除无响应（现角点 = 单顶点，右键菜单 / Del 双通道均经命令层可撤销）

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


# A corner inserted on a horizontal, a vertical, or a near-diagonal segment keeps the path orthogonal.
# gpRoute re-orthogonalizes through the corner vertex, so even an off-axis cursor yields an orthogonal pipe.
# 在水平/垂直/近斜段上插入角点均保持正交：gpRoute 经该顶点把路径重新正交化，即便光标离轴也得正交管线。
func gpTestCornerOrthogonalAllOrientations() -> void:
	# Horizontal straight edge. / 直水平边。
	var gh: GPPIDGraph = GPPIDGraph.new()
	var eh: GPPIDEdge = _mkEdge(Vector2(0, 0), Vector2(200, 0), [])
	gh.gpAddEdge(eh)
	var cvh: GPCanvas2D = GPCanvas2D.new()
	cvh.gpGraph = gh
	var gripsh: GPEdgeGripOps = GPEdgeGripOps.new(cvh)
	gripsh.gpStartBump("e1", Vector2(100, 30))  # click 30px below the run / 落在线段下方 30px
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(gripsh._gpPolyline(eh)),
		"horizontal: corner keeps orthogonal / 水平段角点恒正交")
	cvh.free()
	# Vertical straight edge. / 直垂直边。
	var gv: GPPIDGraph = GPPIDGraph.new()
	var ev: GPPIDEdge = _mkEdge(Vector2(0, 0), Vector2(0, 200), [])
	gv.gpAddEdge(ev)
	var cvv: GPCanvas2D = GPCanvas2D.new()
	cvv.gpGraph = gv
	var gripsv: GPEdgeGripOps = GPEdgeGripOps.new(cvv)
	gripsv.gpStartBump("e1", Vector2(30, 100))  # click 30px right of the run / 落在线段右侧 30px
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(gripsv._gpPolyline(ev)),
		"vertical: corner keeps orthogonal / 垂直段角点恒正交")
	cvv.free()
	# Near-diagonal segment (only the corner insertion cares; gpRoute re-orthogonalizes the whole path).
	# 近斜段（仅角点插入关心方向；gpRoute 把整条路径重新正交化）。
	var gd: GPPIDGraph = GPPIDGraph.new()
	var ed: GPPIDEdge = _mkEdge(Vector2(0, 0), Vector2(200, 200), [])
	gd.gpAddEdge(ed)
	var cvd: GPCanvas2D = GPCanvas2D.new()
	cvd.gpGraph = gd
	var gripsd: GPEdgeGripOps = GPEdgeGripOps.new(cvd)
	gripsd.gpStartBump("e1", Vector2(120, 150))  # off the diagonal, below-right / 偏到斜线右下
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(gripsd._gpPolyline(ed)),
		"diagonal: corner keeps orthogonal / 斜段角点恒正交")
	cvd.free()


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

# Right-clicking a segment inserts ONE orange CORNER (a single routing vertex, offset perpendicular by
# GP_CORNER_OFFSET) and records its routing index, without disturbing the rest of the routing.
# 右键点击线段插入「一个」橙色角点（单个 routing 顶点，沿垂直方向偏移 GP_CORNER_OFFSET）并记下其路由下标，
# 且不扰动其余路由。
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
	gpEq(e.gpRouting.size(), gpBefore + 1, "right-click inserts ONE corner vertex / 右键插入一个角点顶点")
	gpCheck(grips._gpBumpAnchors.has("e1"), "an orange corner is recorded / 已记录橙色角点")
	gpEq(grips._gpBumpAnchors["e1"].size(), 1, "exactly one corner recorded / 恰记录一枚角点")
	# The recorded anchor stores the routing-vertex index; the corner IS that vertex, so it sits at a
	# perpendicular offset (GP_CORNER_OFFSET) below the clicked run. / 记录的锚点存的是 routing 顶点下标；
	# 角点即该顶点本身，故落在被点线段下方垂直偏移 GP_CORNER_OFFSET 处。
	var gpRIdx: int = int(grips._gpBumpAnchors["e1"][0])
	gpEq(gpRIdx, 0, "corner recorded at routing index 0 / 角点记于 routing 下标 0")
	var gpCorner: Vector2 = e.gpRouting[gpRIdx]
	gpApprox(gpCorner.x, gpClick.x, 1.0, "corner x tracks the click x / 角点 x 跟随点击 x")
	gpApprox(gpCorner.y, gpMid.y + 18.0, 2.0, "corner offset perpendicular by GP_CORNER_OFFSET / 角点垂直偏移 GP_CORNER_OFFSET")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)),
		"corner keeps the path orthogonal / 角点后路径仍正交")
	cv.free()


# Create a corner via right-click, then LEFT-DRAG its orange anchor: the corner MOVES (its single routing
# vertex is written to the cursor) while the vertex COUNT stays 1 and the path stays orthogonal.
# 右键生成角点后左键拖动其橙色锚点：角点移动（其单个 routing 顶点被写向光标），顶点数仍为 1 且路径正交。
func gpTestBumpAnchorDragReshapes() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)
	gpCheck(not gpG.is_empty(), "found a horizontal run / 找到水平段")
	grips.gpStartBump("e1", Vector2(gpG["pos"].x, gpG["pos"].y + 40.0))
	gpEq(e.gpRouting.size(), 1, "one corner = one vertex / 一个角点=一顶点")
	gpEq(int(grips._gpBumpAnchors["e1"][0]), 0, "corner at routing index 0 / 角点于 routing 下标 0")
	# Drag by ARRAY index (the value gpHitBump returns), not by world position.
	# 按数组下标（gpHitBump 返回的 anchor）拖动，而非世界坐标。
	grips.gpStartBumpDrag("e1", 0)
	grips.gpOnGripMove(Vector2(gpG["pos"].x, gpG["pos"].y + 70.0))  # deeper than the +18 at creation
	gpEq(e.gpRouting.size(), 1, "reshape keeps one vertex / 重塑后仍为一顶点")
	var gpRIdx: int = int(grips._gpBumpAnchors["e1"][0])
	var gpCorner: Vector2 = e.gpRouting[gpRIdx]
	gpApprox(gpCorner.x, gpG["pos"].x, 1.0, "corner x tracks drag x / 角点 x 跟随拖动 x")
	gpApprox(gpCorner.y, gpG["pos"].y + 70.0, 1.0, "corner y tracks drag depth / 角点 y 跟随拖动深度")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)),
		"reshaped corner stays orthogonal / 重塑后角点仍正交")
	cv.free()


# A shallow right-click corner (small perpendicular depth from the cursor) must still be orthogonal and must
# NOT create a port->stub->back-to-port backtrack at either end (no repeated vertex). The corner is offset
# by the fixed GP_CORNER_OFFSET (not the click depth), so even a tiny click makes a real bend.
# 浅右键角点（光标垂直深度很小）仍须正交，且两端不得出现「端口→伸出→折返端口」回折（无重复顶点）。角点沿
# 固定 GP_CORNER_OFFSET 偏移（而非点击深度），故即便点击极浅也形成真实拐角。
func gpTestSmallBumpNoEndpointBacktrack() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)
	gpCheck(not gpG.is_empty(), "found a horizontal run / 找到水平段")
	grips.gpStartBump("e1", Vector2(gpG["pos"].x, gpG["pos"].y + 8.0))  # shallow: 8px deep / 浅：仅 8px 深
	gpEq(e.gpRouting.size(), 1, "shallow corner still = one vertex / 浅角点仍为单顶点")
	var gpP: PackedVector2Array = grips._gpPolyline(e)
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(gpP), "shallow corner stays orthogonal / 浅角点仍正交")
	var gpSeen: Dictionary = {}
	for i in range(gpP.size()):
		var k: String = "%.2f,%.2f" % [gpP[i].x, gpP[i].y]
		gpCheck(not gpSeen.has(k), "no repeated vertex at index %d (no backtrack) / 第 %d 顶点无重复（无回折）" % [i, i])
		gpSeen[k] = true
	cv.free()


# Requirement: an orange corner must ALWAYS ride the line — a whole-line move must carry the corner with it
# (its position IS the routing vertex, which the move shifts rigidly).
# 需求：橙色角点须「永远贴线」——整线平移须带动角点（其位置即 routing 顶点，平移整体刚性移动 routing）。
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
	var gpCornerBefore: Vector2 = e.gpRouting[gpIdx]
	# Whole-line move by delta (+50, -25): the corner must ride the line. / 整线平移 delta=(+50,-25)：角点须随线移动。
	grips.gpStartEdgeMove("e1", Vector2(10, 10))
	grips.gpOnEdgeMove(Vector2(60, -15))
	var gpIdx2: int = int(grips._gpBumpAnchors["e1"][0])
	gpEq(gpIdx2, gpIdx, "corner vertex index is stable across a rigid move / 整线平移后角点顶点下标不变")
	var gpCornerAfter: Vector2 = e.gpRouting[gpIdx2]
	gpApprox(gpCornerAfter.x, gpCornerBefore.x + 50.0, 0.001, "corner x follows whole-line move / 角点 x 随整线平移")
	gpApprox(gpCornerAfter.y, gpCornerBefore.y - 25.0, 0.001, "corner y follows whole-line move / 角点 y 随整线平移")
	cv.free()


# Requirement: a corner anchor can be deleted, and deleting one shifts the LATER anchors' vertex indices
# by -1 (single vertex, not a pair). / 需求：角点锚点可删除；删除其一使后续锚点的顶点下标整体 -1（单顶点）。
func gpTestDeleteBumpAnchor() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	# Three pre-existing routing vertices (so we can verify a precise index shift). / 三个既有路由顶点（精确验证下标回移）。
	var e: GPPIDEdge = _mkEdge(Vector2(0, 0), Vector2(400, 400),
		[Vector2(100, 0), Vector2(100, 200), Vector2(300, 200)])
	g.gpAddEdge(e)
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	# Pre-seed two orange corners at routing indices 0 and 2 (bypasses geometry for a deterministic check).
	# 预置两角点于 routing 下标 0 与 2（绕过几何以做确定性检查）。
	grips._gpBumpAnchors["e1"] = [0, 2]
	grips.gpDeleteBump("e1", 0)
	gpEq(e.gpRouting.size(), 2, "deleting first corner removes ONE vertex (3 -> 2) / 删首角点移除一个顶点")
	gpEq(grips._gpBumpAnchors["e1"].size(), 1, "one corner remains / 剩一枚角点")
	gpEq(int(grips._gpBumpAnchors["e1"][0]), 1, "second corner's vertex index shifted down by 1 (2 -> 1) / 第二角点下标回移 1")
	# The surviving routing still holds the two undeleted vertices. / 剩余路由仍含两个未删顶点。
	gpEq(e.gpRouting[0], Vector2(100, 200), "surviving routing[0] is original vertex 1 / 剩余 routing[0] 为原顶点1")
	gpEq(e.gpRouting[1], Vector2(300, 200), "surviving routing[1] is original vertex 2 / 剩余 routing[1] 为原顶点2")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)), "path stays orthogonal after delete / 删除后仍正交")
	cv.free()


# Requirement: a SELECTED corner anchor can be deleted through the same path the Del key uses.
# 需求：选中的角点锚点可按 Del 键所用的同一路径删除。
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
	gpCheck(not grips.gpSelectedBump().is_empty(), "corner selected / 角点已选中")
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


# Requirement #1 regression: a port-to-port STRAIGHT edge (no free geometry to translate) must still be
# draggable. A body press inserts ONE corner at the press point and immediately enters corner-drag, so the
# line bends and follows the cursor instead of being frozen (the previous defect: "line shows a cross
# cursor but never moves"). / 需求一回归：纯直线端口边（无可平移几何）须可拖动。线体按下在按下处插入一个角点
# 并立即进入角点拖拽，使线被拖动而非卡死（旧缺陷：仅显示十字光标而线不动）。
func gpTestBodyDragCreatesCornerOnStraightEdge() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	gpEq(e.gpRouting.size(), 0, "real port-to-port edge starts with no routing vertex / 真实端口边初始无路由顶点")
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)
	gpCheck(not gpG.is_empty(), "found a horizontal run to press on / 找到可按下的水平段")
	var gpPress: Vector2 = gpG["pos"]
	# Simulate the select-tool body press -> gpStartCornerDrag inserts a corner and begins the drag.
	# 模拟选择工具的线体按下 -> gpStartCornerDrag 插入角点并进入拖拽。
	grips.gpStartCornerDrag("e1", gpPress)
	gpEq(e.gpRouting.size(), 1, "body press inserted ONE corner vertex / 线体按下插入一个角点顶点")
	gpEq(grips._gpBumpAnchors["e1"].size(), 1, "a corner anchor was recorded / 已记录一枚角点")
	gpEq(int(grips._gpBumpAnchors["e1"][0]), 0, "corner recorded at routing index 0 / 角点记于 routing 下标 0")
	# Now drag: the corner follows the cursor. / 拖动：角点跟随光标。
	grips.gpOnGripMove(Vector2(gpPress.x + 30.0, gpPress.y + 50.0))
	gpApprox(e.gpRouting[0].x, gpPress.x + 30.0, 1.0, "dragged corner x follows cursor / 拖动角点 x 跟随光标")
	gpApprox(e.gpRouting[0].y, gpPress.y + 50.0, 6.0, "dragged corner y follows cursor / 拖动角点 y 跟随光标")
	gpCheck(GPEdgeGripOps.gpPolylineOrtho(grips._gpPolyline(e)), "dragged line stays orthogonal / 拖动后线仍正交")
	# Finish: commit a single undo step (creation + move combined). / 结束：提交单个撤销步（创建+移动合一）。
	grips.gpEndGripDrag()
	gpEq(e.gpRouting.size(), 1, "corner survives the drag commit / 角点在拖拽提交后保留")
	cv.free()


# REGRESSION (github issue: line follows cursor forever until program close): a whole-edge TRANSLATE
# must reset its "moving" state on release. If gpEndEdgeMove is never called, _gpMoveEdge stays set and
# gpOnMove keeps forwarding motion, so the line tracks the cursor indefinitely.
# 回归（线跟随光标直到关闭程序）：整线平移必须在释放时清除「移动中」状态。若 gpEndEdgeMove 永不调用，
# _gpMoveEdge 残留、gpOnMove 持续转发，线会无限跟随光标。
func gpTestEdgeMoveReleaseClearsMovingState() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	# Give the edge a real routing so a translate is observable (and committable).
	# 给边一个真实路由，使平移可观察（且可提交）。
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)
	grips.gpStartBump("e1", Vector2(gpG["pos"].x, gpG["pos"].y + 40.0))
	gpCheck(e.gpRouting.size() >= 1, "edge now has routing to translate / 边已有可平移的路由")
	gpEq(grips.gpIsMoving(), false, "no move before press / 按下前无移动")
	gpEq(grips.gpIsDragging(), false, "no drag before press / 按下前无拖拽")
	# Capture the corner position right after creation (its perpendicular offset is GP_CORNER_OFFSET,
	# NOT the 40px click depth — the click only picks the side). / 捕捉创建后角点位置（垂直偏移是
	# GP_CORNER_OFFSET 而非 40px 点击深度——点击仅决定方向）。
	var gpCornerX: float = e.gpRouting[0].x
	var gpCornerY: float = e.gpRouting[0].y
	# Begin a whole-edge translate, move it. / 开始整线平移并移动。
	grips.gpStartEdgeMove("e1", Vector2(10, 10))
	gpEq(grips.gpIsMoving(), true, "moving set during translate / 平移中 moving 为真")
	grips.gpOnEdgeMove(Vector2(60, -15))  # delta (+50, -25)
	gpEq(grips.gpIsMoving(), true, "still moving mid-drag / 拖拽中仍 moving")
	# Release: must CLEAR moving so motion stops following. / 释放：须清除 moving 使跟随停止。
	grips.gpEndEdgeMove()
	gpEq(grips.gpIsMoving(), false, "moving CLEARED after release / 释放后 moving 已清除")
	gpEq(grips.gpIsDragging(), false, "drag also clear after release / 释放后拖拽亦清除")
	gpApprox(e.gpRouting[0].x, gpCornerX + 50.0, 1.0, "translate delta applied on x / 平移位移已作用到 x")
	gpApprox(e.gpRouting[0].y, gpCornerY - 25.0, 1.0, "translate delta applied on y / 平移位移已作用到 y")
	cv.free()


# REGRESSION: dragging an ORANGE corner anchor (gpStartBumpDrag) must reset the dragging state on
# release, so a subsequent cursor move no longer mutates the routing. / 回归：拖动橙色角点锚点
# （gpStartBumpDrag）须在释放时清除拖拽状态，使后续光标移动不再改写路由。
func gpTestCornerDragReleaseClearsDraggingState() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	var pts: PackedVector2Array = grips._gpPolyline(e)
	var gpG: Dictionary = _gpFindRunGrip(pts, true, 80.0)
	grips.gpStartBump("e1", Vector2(gpG["pos"].x, gpG["pos"].y + 40.0))
	gpEq(grips._gpBumpAnchors["e1"].size(), 1, "one orange corner recorded / 已记录一枚橙色角点")
	# Start dragging the orange corner, move it. / 开始拖动橙色角点并移动。
	grips.gpStartBumpDrag("e1", 0)
	gpEq(grips.gpIsDragging(), true, "dragging set during corner drag / 角点拖拽中 dragging 为真")
	grips.gpOnGripMove(Vector2(gpG["pos"].x + 25.0, gpG["pos"].y + 70.0))
	gpEq(grips.gpIsDragging(), true, "still dragging mid-move / 拖动中仍 dragging")
	# Release: must CLEAR dragging. / 释放：须清除 dragging。
	grips.gpEndGripDrag()
	gpEq(grips.gpIsDragging(), false, "dragging CLEARED after release / 释放后 dragging 已清除")
	gpEq(grips.gpIsMoving(), false, "moving also clear after release / 释放后移动亦清除")
	cv.free()


# ============================================================================
# 放置图元到连线（绕行 / 拆分）的 headless 测试
# Drop-symbol-onto-line (reroute / split) — headless coverage.
# ============================================================================

# Pure geometry: a polyline that pierces a rect edge, lies wholly inside it, and is clear of it.
# 纯几何：折线穿过矩形边、完全落在矩形内、与矩形无交，三种情形分别判定。
func gpTestPolylineHitsRect() -> void:
	var rect: Rect2 = Rect2(100.0, 100.0, 100.0, 100.0)  # [100,200] x [100,200]
	# Crossing: segment (0,150)->(300,150) slices through the rect's left/right edges.
	# 穿过：段从矩形左缘穿到右缘。
	gpCheck(GPEdgeGripOps._gpPolylineHitsRect(
		PackedVector2Array([Vector2(0, 150), Vector2(300, 150)]), rect),
		"horizontal line through the rect is a hit / 横穿矩形算命中")
	# Inside: both endpoints sit inside the rect, crossing no edge — must still register.
	# 内部：两端点都在矩形内、与四边不相交，仍须判为命中。
	gpCheck(GPEdgeGripOps._gpPolylineHitsRect(
		PackedVector2Array([Vector2(120, 130), Vector2(180, 170)]), rect),
		"segment fully inside the rect is a hit / 完全落在矩形内的段算命中")
	# Clear: well outside. / 无交：远在矩形外。
	gpCheck(not GPEdgeGripOps._gpPolylineHitsRect(
		PackedVector2Array([Vector2(0, 0), Vector2(50, 0)]), rect),
		"distant line is NOT a hit / 远离的线不算命中")


# A node whose rect overlaps the drawn pipe returns that edge id; a far-away node returns "".
# 矩形与绘制管线重叠的节点返回该边 id；远处的节点返回 ""。
func gpTestEdgeUnderNodeDetectsCrossing() -> void:
	var f: Dictionary = _mkRealEdge()
	var cv: GPCanvas2D = f["cv"]
	var g: GPPIDGraph = f["g"]
	var e: GPPIDEdge = f["e"]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	# Drop a node exactly on the routed pipe midpoint. / 把节点落在已布管线的中点上。
	var pts: PackedVector2Array = grips._gpPolyline(e)
	gpCheck(pts.size() >= 2, "edge polyline resolved / 边折线已解析")
	var gpMid: Vector2 = pts[pts.size() / 2]
	var n3: GPPIDNode = GPPIDNode.new()
	n3.gpInstanceId = "n3"
	n3.gpSymbolId = "PUMP"  # same def -> binder resolves the 64x64 envelope / 同定义 -> 绑定器解析 64x64 包络
	n3.gpPosition = gpMid
	g.gpAddNode(n3)
	gpEq(grips.gpEdgeUnderNode(n3), "e1", "node on the pipe detects edge e1 / 落在管线上的节点检出边 e1")
	# A node parked far away must not match. / 远处的节点不得命中。
	var n4: GPPIDNode = GPPIDNode.new()
	n4.gpInstanceId = "n4"
	n4.gpSymbolId = "PUMP"
	n4.gpPosition = Vector2(5000.0, 5000.0)
	g.gpAddNode(n4)
	gpEq(grips.gpEdgeUnderNode(n4), "", "far node matches no edge / 远处节点不匹配任何边")
	cv.free()


# The split port picker must respect direction: the port nearer the ORIGINAL START becomes the input.
# 拆分端口挑选须尊重方向：更靠近原「起点」的端口成为入端。
func gpTestPickSplitPortsDirection() -> void:
	var def: GPSymbolDef = GPSymbolDef.new()
	def.gpId = "VALVE"
	def.gpPorts = [
		GPPort.gpMake("left", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("right", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
	]
	var sym: GPPIDNode = GPPIDNode.new()
	sym.gpInstanceId = "sv"
	sym.gpSymbolId = "VALVE"
	sym.gpPosition = Vector2(1000.0, 1000.0)
	# left port world = (1000-32, 1000) ; right port world = (1032, 1000).
	# 左端口世界坐标 = (968,1000)，右端口 = (1032,1000)。
	var gpLeft: Vector2 = Vector2(968.0, 1000.0)
	var gpRight: Vector2 = Vector2(1032.0, 1000.0)
	# A near left, B near right -> in=left, out=right. / A 近左、B 近右 -> 入=左、出=右。
	var p1: Dictionary = GPEdgeGripOps._gpPickSplitPorts(sym, def, gpLeft, gpRight)
	gpEq(str(p1.get("in")), "left", "nearer-to-A port is the input / 近 A 端为入端")
	gpEq(str(p1.get("out")), "right", "nearer-to-B port is the output / 近 B 端为出端")
	gpCheck(str(p1.get("in")) != str(p1.get("out")), "in != out / 入端 != 出端")
	# Reversed pipeline -> direction flips. / 管线反向 -> 方向随之翻转。
	var p2: Dictionary = GPEdgeGripOps._gpPickSplitPorts(sym, def, gpRight, gpLeft)
	gpEq(str(p2.get("in")), "right", "reversed pipeline flips input to the right port / 反向管线入端翻为右端口")
	gpEq(str(p2.get("out")), "left", "reversed pipeline output is the left port / 反向管线出端为左端口")


# Split refuses a symbol with <2 ports (caller then prompts "edit symbol to add ports").
# 端口 <2 时拆分拒绝（调用方随后提示「修改图元增加端点」）。
func gpTestSplitThroughSymbolRefusesFewPorts() -> void:
	var def: GPSymbolDef = GPSymbolDef.new()
	def.gpId = "DOT"
	def.gpPorts = [GPPort.gpMake("p", Vector2(0.5, 0.5), Vector2(0.0, 1.0), GPPort.GP_NOZZLE)]
	var g: GPPIDGraph = GPPIDGraph.new()
	var n: GPPIDNode = GPPIDNode.new()
	n.gpInstanceId = "ns"; n.gpSymbolId = "DOT"; n.gpPosition = Vector2(0.0, 0.0)
	g.gpAddNode(n)
	var e: GPPIDEdge = g.gpNewEdgeEx("e1",
		{"node_id": "", "port_id": "", "point": [0.0, 0.0]},
		{"node_id": "", "port_id": "", "point": [300.0, 200.0]},
		GPPIDEdge.GP_PROCESS, "", "PL-x")
	g.gpAddEdge(e)
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	cv.gpBinder = GPGraphBinder.new()
	cv.gpBinder.gpDefs = [def]
	var grips: GPEdgeGripOps = GPEdgeGripOps.new(cv)
	gpEq(grips.gpSplitThroughSymbol("e1", "ns"), false, "split refused for <2 ports / 端口不足时拆分被拒")
	cv.free()
