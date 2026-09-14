class_name GPEdgeGripOps
extends RefCounted

# Edge PATH editing for GPCanvas2D (P3-4, revised for orthogonal editing).
# 边的「路径」编辑（P3-4，为正交编辑修订）。
#
# THE MODEL / 模型
# Two distinct edit gestures on a SELECTED edge:
#   0) 蓝色段中点抓取点（每个横/竖线段一个，位于中点）。拖动它 = 该线段整体平移（两端点按同一位移移动，
#      衔接处的角点随之移动），整条线保持正交，且抓取点始终跟在光标下。
#      Blue midpoint grip (one per segment, at its midpoint). Dragging it TRANSLATES that whole
#      segment rigidly (both its endpoints move by the same delta); the shared corners follow, so the
#      line stays orthogonal and the grab point tracks the cursor.
#   1) 橙色锚点（右键任意线段生成）。它在点击处插入一个轴对齐「帐篷」鼓包；橙色锚点位于鼓包顶点，
#      本身可左键拖动以重塑鼓包。右键在边线上永远不再是上下文菜单。
#      Orange bump anchor (created by RIGHT-CLICKING anywhere on a segment). It inserts an axis-aligned
#      "tent" bump at that point; the orange anchor sits at the apex and is itself draggable (left-drag)
#      to re-shape the bump. Right-click is never a context menu on an edge. The anchor's apex is DERIVED
#      from the routing pair it owns, so it ALWAYS rides the line (never floats off) as the edge moves;
#      a right-click on an existing anchor instead opens a delete menu, and a selected anchor is deleted
#      by the Del key. / 锚点顶点由其拥有的 routing 对推导，故无论连线如何移动都「永远贴线」；
#      右键命中既有锚点改为弹出删除菜单，选中锚点可按 Del 删除。
#
# 端口到端口的直线（单段、端点锁死在端口）无法靠蓝色抓取点平移——此时用线体拖拽（整线平移）。
# A port-to-port straight line (one segment, both ends locked to ports) cannot translate via its blue
# grip; for that case the body drag (whole-line move) still works.

# Grip kind: a segment midpoint (rigid translate). / 抓取点角色：段中点（刚体平移）。
const GP_KIND_MID: String = "mid"

# Grip kind: an orange bump anchor (right-click create / left-drag reshape). / 橙色鼓包锚点（右键生成 / 左键重塑）。
const GP_KIND_BUMP: String = "bump"

# Screen-pixel size of a grip square. / 抓取点方块的屏幕像素尺寸。
const GP_GRIP_SIZE: float = 9.0

# Midpoint grip colour (matches the selection-highlight blue). / 段中点抓取点配色（与选中高亮蓝一致）。
const GP_COL_MID: Color = Color(0.20, 0.50, 1.0)

# Bump-anchor colour — distinct from the blue midpoint grips. / 鼓包锚点配色——与蓝色中点抓取点区分。
const GP_COL_BUMP: Color = Color(1.0, 0.62, 0.0)

# Faint colour for the cross guide drawn while dragging a grip. / 拖动抓取点时绘制的十字辅助线淡色。
const GP_GUIDE_COL: Color = Color(0.35, 0.62, 1.0, 0.55)

# A drag shallower than this (world units) is treated as "no bend" so we never store a micro-bump.
# 小于此值的拖拽视为「不鼓出」，避免存入微小鼓包。
const GP_BUMP_MIN: float = 2.0

# Geometry epsilon shared with GPEdgeRoute (axis-alignment tolerance). / 与 GPEdgeRoute 共用的几何容差。
const GP_EPS: float = 0.5


# The canvas we edit on. / 被编辑的画布。
var gpCv: GPCanvas2D

# Active grip drag; empty dict = nothing in flight. / 进行中的抓取点拖拽；空字典表示无。
var _gpGrip: Dictionary = {}

# Edge id being dragged. / 正在被拖动的边 id。
var _gpEdgeId: String = ""

# Snapshot of the routing at drag start (so the commit restores the original on undo).
# 拖拽开始时的路由快照（提交时供撤销还原到原值）。
var _gpOrigRouting: Array[Vector2] = []

# Segment index (in the resolved polyline) of the blue grip being dragged. / 被拖蓝色抓取点所在（已解析折线）段下标。
var _gpSeg: int = 0

# Endpoints of that segment, captured at drag start (world coords, stable during the drag).
# 该段两端点，于拖拽开始时捕获（世界坐标，拖拽中稳定不变）。
var _gpSegA: Vector2 = Vector2.ZERO
var _gpSegB: Vector2 = Vector2.ZERO

# Segment midpoint at drag start (so the grip follows the cursor by the rigid delta, no drift).
# 拖拽开始时该段中点（使抓取点按刚体位移跟光标，无漂移）。
var _gpSegOrigMid: Vector2 = Vector2.ZERO

# Cursor position at drag start (to measure the rigid translate delta). / 拖拽开始时光标位置（测刚性位移）。
var _gpPressWorld: Vector2 = Vector2.ZERO

# Bump reshape: index of the FIRST of the two routing waypoints that form the bump being reshaped.
# 鼓包重塑：正被重塑的鼓包之两个路由拐点中、第一个的下标。
var _gpBumpIdx: int = -1

# Persistent orange bump anchors per edge id: Array[int] of ROUTING-PAIR INDICES. Each int i means the
# bump's tent is formed by routing[i] and routing[i+1]; the apex (where the orange square is drawn) is
# DERIVED as (routing[i]+routing[i+1])*0.5. Storing the index — not a world coord — makes the anchor ALWAYS
# ride the line: any whole-line / segment / reshape move mutates routing, so the derived apex follows
# automatically and can never detach (satisfies "anchors never float off the line").
# 每边的持久橙色鼓包锚点：ROUTING 对下标数组。每个整数 i 表示该鼓包帐篷由 routing[i]、routing[i+1] 构成；
# 橙色方块所在顶点由 (routing[i]+routing[i+1])*0.5 推导。存下标（而非世界坐标）使锚点「永远贴线」——
# 整线/段/重塑任一移动都会改写 routing，推导顶点自动跟随、绝不脱离（满足「锚点永不离线」）。
var _gpBumpAnchors: Dictionary = {}

# Currently-selected bump anchor (for delete via right-click menu / Del key): {"eid": String, "ai": int}.
# Empty dict = nothing selected. / 当前选中的鼓包锚点（供右键菜单 / Del 删除）：{eid, ai}；空 = 无。
var _gpSelBump: Dictionary = {}

# Mark a bump anchor as selected (ai = array index into _gpBumpAnchors[eid]). / 标记某鼓包锚点为选中。
func gpSelectBump(gpEdgeId: String, gpAi: int) -> void:
	_gpSelBump = {"eid": gpEdgeId, "ai": gpAi}

# The selected bump anchor, or an empty dict when none. / 当前选中的鼓包锚点；无则返回空字典。
func gpSelectedBump() -> Dictionary:
	return _gpSelBump

# Drop the bump-anchor selection (called when the user clicks elsewhere). / 清除鼓包锚点选择（点别处时调用）。
func gpClearBumpSelection() -> void:
	_gpSelBump = {}

# Whole-edge translate drag (body click, NOT a grip). / 整线平移拖拽（线体点击，非抓取点）。
var _gpMoveEdge: String = ""
# World position where the translate started (to measure the delta). / 平移开始的摩丝坐标（测位移）。
var _gpMoveStart: Vector2 = Vector2.ZERO
# Snapshot of the routing at drag start (so the commit restores the original on undo). / 拖拽开始时的路由快照。
var _gpMoveOrigRouting: Array[Vector2] = []
# Dangling-end world position at drag start, or Vector2.INF when that end is port-bound.
# 拖拽开始时悬空端的世界坐标；该端绑定到端口时为 Vector2.INF。
var _gpMoveDangFrom: Vector2 = Vector2.INF
var _gpMoveDangTo: Vector2 = Vector2.INF


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# True while a grip drag is in flight. / 抓点拖拽进行中返回真。
func gpIsDragging() -> bool:
	return not _gpGrip.is_empty()


# True while a whole-edge translate drag is in flight. / 整线平移拖拽进行中返回真。
func gpIsMoving() -> bool:
	return _gpMoveEdge != ""


# The edge id whose grip is currently being dragged (empty when nothing is in flight).
# 当前正被拖拽抓取点的边 id（无进行时返回空）。
func gpDraggingEdgeId() -> String:
	return _gpEdgeId


# ============================ pure geometry (headless-testable) ============================

# The two waypoints that bend segment A->B orthogonally towards cursor C. The result is always
# axis-aligned: a horizontal run bumps vertically, a vertical run bumps horizontally. A near-diagonal
# segment is bumped along its wider axis. The bump is a LOCALISED symmetric "tent" centred on the
# cursor's perpendicular coordinate, never a full-width tray reaching the ports (which would collide
# with the 14px stub and backtrack). / 把段 A→B 按正交方向朝光标 C「鼓出」所需的两个拐点。结果恒轴对齐：
# 水平段纵向鼓、垂直段横向鼓；近斜段沿其较宽轴鼓出。鼓包是「以光标垂线坐标为中心的局部对称帐篷」，
# 而非横贯 A..B 的整段托盘（后者会压到端口、与 14px 引出段打架产生回折）。
static func gpBumpWaypoints(gpA: Vector2, gpB: Vector2, gpCursor: Vector2) -> Array[Vector2]:
	var gpOut: Array[Vector2] = []
	var gpHalf: float = 30.0
	if absf(gpA.y - gpB.y) <= absf(gpA.x - gpB.x):
		# Horizontal segment: bump vertically, centred at the cursor's x. / 水平段：纵向鼓出，以光标 x 为中心。
		var gpLo: float = gpA.x + GPEdgeRoute.GP_STUB + 2.0
		var gpHi: float = gpB.x - GPEdgeRoute.GP_STUB - 2.0
		if gpLo > gpHi:
			gpLo = (gpLo + gpHi) * 0.5
			gpHi = gpLo
		gpHalf = minf(gpHalf, maxf(0.0, (gpHi - gpLo) * 0.5 - 2.0))
		var gpCx: float = (gpLo + gpHi) * 0.5
		if (gpHi - gpLo) >= 2.0 * gpHalf:
			gpCx = clampf(gpCursor.x, gpLo + gpHalf, gpHi - gpHalf)
		gpCx = clampf(gpCx, gpLo, gpHi)
		var gpDepth: float = gpCursor.y - gpA.y
		gpOut.append(Vector2(gpCx - gpHalf, gpA.y + gpDepth))
		gpOut.append(Vector2(gpCx + gpHalf, gpA.y + gpDepth))
	else:
		# Vertical segment: bump horizontally, centred at the cursor's y. / 垂直段：横向鼓出，以光标 y 为中心。
		var gpLo: float = gpA.y + GPEdgeRoute.GP_STUB + 2.0
		var gpHi: float = gpB.y - GPEdgeRoute.GP_STUB - 2.0
		if gpLo > gpHi:
			gpLo = (gpLo + gpHi) * 0.5
			gpHi = gpLo
		gpHalf = minf(gpHalf, maxf(0.0, (gpHi - gpLo) * 0.5 - 2.0))
		var gpCy: float = (gpLo + gpHi) * 0.5
		if (gpHi - gpLo) >= 2.0 * gpHalf:
			gpCy = clampf(gpCursor.y, gpLo + gpHalf, gpHi - gpHalf)
		gpCy = clampf(gpCy, gpLo, gpHi)
		var gpDepth: float = gpCursor.x - gpA.x
		gpOut.append(Vector2(gpA.x + gpDepth, gpCy - gpHalf))
		gpOut.append(Vector2(gpA.x + gpDepth, gpCy + gpHalf))
	return gpOut


# True when every consecutive pair in gpPts shares an x or a y (axis-aligned polyline).
# 当 gpPts 中相邻两点恒共 x 或共 y（轴对齐折线）时为真。
static func gpPolylineOrtho(gpPts: PackedVector2Array) -> bool:
	for gpI in range(gpPts.size() - 1):
		var gpD: Vector2 = gpPts[gpI + 1] - gpPts[gpI]
		if absf(gpD.x) > GP_EPS and absf(gpD.y) > GP_EPS:
			return false
	return true


# One grip per segment, each exactly at the segment midpoint (skips zero-length segments).
# 每个线段一个抓取点，均恰在段中点（跳过零长段）。
static func gpMidpointGrips(gpPts: PackedVector2Array) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	for gpS in range(gpPts.size() - 1):
		var gpA: Vector2 = gpPts[gpS]
		var gpB: Vector2 = gpPts[gpS + 1]
		if gpA.distance_to(gpB) <= GP_EPS:
			continue
		var gpMid: Vector2 = (gpA + gpB) * 0.5
		gpOut.append({"kind": GP_KIND_MID, "seg": gpS, "pos": gpMid})
	return gpOut


# Index of the polyline segment whose perpendicular distance to gpWorld is smallest (or -1 if none).
# 返回离 gpWorld 垂线距离最小的（已解析折线）段下标（无则 -1）。
static func _gpFindNearestSegment(gpPts: PackedVector2Array, gpWorld: Vector2) -> int:
	var gpBest: int = -1
	var gpBestD: float = INF
	for gpS in range(gpPts.size() - 1):
		var gpA: Vector2 = gpPts[gpS]
		var gpB: Vector2 = gpPts[gpS + 1]
		if gpA.distance_to(gpB) <= GP_EPS:
			continue
		var gpT: float = clampf(((gpWorld - gpA).dot(gpB - gpA)) / maxf((gpB - gpA).length_squared(), 1e-6), 0.0, 1.0)
		var gpProj: Vector2 = gpA + (gpB - gpA) * gpT
		var gpD: float = gpWorld.distance_to(gpProj)
		if gpD < gpBestD:
			gpBestD = gpD
			gpBest = gpS
	return gpBest


# ============================ live orchestration over the graph ============================

# Build the resolved world polyline of an edge. MUST use the SAME routing routine as the renderer
# (GPEdgeView.gpPolyline) and the hit-test (GPCanvasHitTest.gpHitEdge): GPEdgeRoute.gpRoute. Otherwise
# the grips are computed on a raw [endA]+routing+[endB] line that only matches the visible pipe when
# there is no waypoint AND orthogonal routing is off — for every real orthogonal P&ID pipe the grips
# would land on a straight diagonal that never touches the drawn L/Z/U path, so they would be invisible.
# 构造一条边的「已解析世界折线」。必须与渲染器（GPEdgeView.gpPolyline）和命中测试（GPCanvasHitTest.gpHitEdge）
# 共用同一套布线例程 GPEdgeRoute.gpRoute。否则抓取点会落在「[端A]+折点+[端B]」的裸直线上，而该直线仅在「无折点且关闭正交」
# 时才与可见管线重合 —— 对任意真实的正交 P&ID 管线，抓取点会落在一条根本碰不到可见 L/Z/U 路径的斜线上，从而不可见。
func _gpPolyline(gpE: GPPIDEdge) -> PackedVector2Array:
	var gpDefs: Callable = gpCv.gpDefLookupCallable()
	# Resolve ends with the SAME want-type the renderer uses, so grips sit on the drawn line.
	# 用与渲染器相同的「期望端口用途」解析端点，使抓取点落在已绘制的线上。
	var gpWant: String = GPPortResolver.gpWantTypeFor(gpE)
	var gpA: Dictionary = GPPortResolver.gpResolveEnd(gpCv.gpGraph, gpDefs, gpE, true, gpWant)
	var gpB: Dictionary = GPPortResolver.gpResolveEnd(gpCv.gpGraph, gpDefs, gpE, false, gpWant)
	return GPEdgeRoute.gpRoute(gpA, gpB, gpE.gpRouting, gpE.gpOrtho)


# Return the blue midpoint grip under the world point for the given edge, or an empty dict.
# 返回世界点下该边的段中点抓取点，未命中返回空字典。
func gpHitGrip(gpWorld: Vector2, gpEdgeId: String) -> Dictionary:
	if gpCv.gpGraph == null:
		return {}
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return {}
	var gpPts: PackedVector2Array = _gpPolyline(gpE)
	var gpTol: float = 8.0 / gpCv.gpViewZoom
	for gpG in gpMidpointGrips(gpPts):
		if gpWorld.distance_to(gpG["pos"]) <= gpTol:
			return gpG
	return {}


# Return the orange bump anchor under the world point for the given edge, or an empty dict.
# "anchor" is the ARRAY index into _gpBumpAnchors[gpEdgeId] (used for deletion); the apex is DERIVED
# from the routing pair so it is always on the line. / 返回世界点下该边的橙色鼓包锚点，未命中返回空字典。
# "anchor" 是 _gpBumpAnchors[gpEdgeId] 的数组下标（供删除用）；顶点由 routing 对推导，恒在线上。
func gpHitBump(gpWorld: Vector2, gpEdgeId: String) -> Dictionary:
	if not _gpBumpAnchors.has(gpEdgeId):
		return {}
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return {}
	var gpTol: float = 9.0 / gpCv.gpViewZoom
	var gpList: Array = _gpBumpAnchors[gpEdgeId]
	for gpAi in range(gpList.size()):
		var gpRIdx: int = int(gpList[gpAi])
		if gpRIdx + 1 >= gpE.gpRouting.size():
			continue
		var gpPos: Vector2 = (gpE.gpRouting[gpRIdx] + gpE.gpRouting[gpRIdx + 1]) * 0.5
		if gpWorld.distance_to(gpPos) <= gpTol:
			return {"kind": GP_KIND_BUMP, "pos": gpPos, "anchor": gpAi}
	return {}


# The orange bump anchors of an edge (for drawing). Positions are DERIVED from the current routing so
# they always sit on the line (never float off). / 一条边的橙色鼓包锚点（绘制用）。位置由当前 routing
# 推导，故恒在线上（绝不脱离）。
func gpBumpGrips(gpEdgeId: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if _gpBumpAnchors.has(gpEdgeId):
		var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
		if gpE != null:
			for gpRIdx in _gpBumpAnchors[gpEdgeId]:
				var gpI: int = int(gpRIdx)
				if gpI + 1 < gpE.gpRouting.size():
					var gpPos: Vector2 = (gpE.gpRouting[gpI] + gpE.gpRouting[gpI + 1]) * 0.5
					gpOut.append({"kind": GP_KIND_BUMP, "pos": gpPos})
	return gpOut


# Begin dragging the given BLUE midpoint grip: capture the segment + press point for a rigid translate.
# 开始拖动给定蓝色段中点抓取点：捕获段与按下点，准备刚体平移。
func gpStartGripDrag(gpEdgeId: String, gpGrip: Dictionary) -> void:
	_gpEdgeId = gpEdgeId
	_gpGrip = gpGrip.duplicate()
	# Orange anchor: a bump reshape (not a midpoint translate). Locate its two waypoints by
	# proximity to the anchor so we overwrite exactly that bump. / 橙色锚点：鼓包重塑。按锚点邻近度定位其
	# 两个拐点，从而精确覆盖该鼓包。
	if str(_gpGrip.get("kind", "")) == GP_KIND_BUMP:
		var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
		if gpE != null:
			_gpOrigRouting = gpE.gpRouting.duplicate()
			_gpBumpIdx = _gpFindBumpPair(gpE, _gpGrip.get("pos", Vector2.ZERO))
		gpCv.queue_redraw()
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE != null:
		var gpPts: PackedVector2Array = _gpPolyline(gpE)
		var gpS: int = clampi(int(_gpGrip.get("seg", 0)), 0, gpPts.size() - 2)
		_gpSeg = gpS
		_gpSegA = gpPts[gpS]
		_gpSegB = gpPts[gpS + 1]
		_gpSegOrigMid = (_gpSegA + _gpSegB) * 0.5
		_gpOrigRouting = gpE.gpRouting.duplicate()
		_gpPressWorld = _gpGrip.get("pos", _gpSegOrigMid)
	gpCv.queue_redraw()


# Right-click on a segment -> create an orange bump anchor there (insert a tent, commit immediately
# and remember the anchor so it can be re-dragged later). / 右键点击线段 -> 在该处生成橙色锚点（插入帐篷，
# 立即提交并记下锚点，便于日后重新拖动）。
func gpStartBump(gpEdgeId: String, gpWorld: Vector2) -> void:
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	var gpPts: PackedVector2Array = _gpPolyline(gpE)
	var gpS: int = _gpFindNearestSegment(gpPts, gpWorld)
	if gpS < 0:
		return
	var gpA: Vector2 = gpPts[gpS]
	var gpB: Vector2 = gpPts[gpS + 1]
	var gpW: Array[Vector2] = gpBumpWaypoints(gpA, gpB, gpWorld)
	var gpInsert: int = _gpRoutingInsertIndex(gpPts, gpE.gpRouting, gpS)
	var gpNew: Array[Vector2] = gpE.gpRouting.duplicate()
	gpNew.insert(gpInsert, gpW[0])
	gpNew.insert(gpInsert + 1, gpW[1])
	if not _gpBumpAnchors.has(gpEdgeId):
		_gpBumpAnchors[gpEdgeId] = []
	# Store the routing-pair index of the new bump; shift any EXISTING anchor whose pair index is
	# >= gpInsert by +2 (the two inserted waypoints push later pairs up by two).
	# 记下新鼓包的 routing 对下标；既有锚点的对下标 >= gpInsert 者整体 +2（插入两拐点把后续对推后两位）。
	var gpShifted: Array = []
	for gpOld in _gpBumpAnchors[gpEdgeId]:
		var gpV: int = int(gpOld)
		if gpV >= gpInsert:
			gpV += 2
		gpShifted.append(gpV)
	gpShifted.append(gpInsert)
	_gpBumpAnchors[gpEdgeId] = gpShifted
	# Live-apply (so headless tests see it) AND commit through the command layer (so the editor undoes).
	# 实时应用（使 headless 测试可见）并经命令层提交（使编辑器可撤销）。
	gpE.gpRouting = gpNew
	gpCv.gpRequestSetEdgeRouting(gpEdgeId, gpNew)
	gpCv.queue_redraw()


# Left-drag an existing orange anchor -> reshape that bump. gpAnchorIdx is the ARRAY index into
# _gpBumpAnchors[gpEdgeId] (gpHitBump returns it), so we resolve the routing-pair index directly
# without a proximity search. / 左键拖动既有橙色锚点 -> 重塑该鼓包。gpAnchorIdx 为
# _gpBumpAnchors[gpEdgeId] 的数组下标（gpHitBump 返回），直接定位 routing 对，免去邻近搜索。
func gpStartBumpDrag(gpEdgeId: String, gpAnchorIdx: int) -> void:
	_gpEdgeId = gpEdgeId
	_gpGrip = {"kind": GP_KIND_BUMP, "anchor": gpAnchorIdx, "pos": Vector2.ZERO}
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE != null and _gpBumpAnchors.has(gpEdgeId):
		var gpList: Array = _gpBumpAnchors[gpEdgeId]
		if gpAnchorIdx >= 0 and gpAnchorIdx < gpList.size():
			var gpRIdx: int = int(gpList[gpAnchorIdx])
			_gpBumpIdx = gpRIdx
			_gpOrigRouting = gpE.gpRouting.duplicate()
			if gpRIdx + 1 < gpE.gpRouting.size():
				_gpGrip["pos"] = (gpE.gpRouting[gpRIdx] + gpE.gpRouting[gpRIdx + 1]) * 0.5
	gpCv.queue_redraw()


# Live-update the grip being dragged. / 实时更新被拖动的抓取点。
func gpOnGripMove(gpWorld: Vector2) -> void:
	if _gpGrip.is_empty():
		return
	if str(_gpGrip.get("kind", "")) == GP_KIND_BUMP:
		_gpApplyBumpMove(gpWorld)
		return
	# Blue grip: rigidly translate the grabbed segment by the cursor delta (derived from the original
	# routing each call, so repeated moves never accumulate drift).
	# 蓝色抓取点：按光标位移刚体平移被抓段（每次都从原路由推导位移，故重复移动绝不累积漂移）。
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null:
		return
	var gpD: Vector2 = gpWorld - _gpPressWorld
	var gpNew: Array[Vector2] = _gpOrigRouting.duplicate()
	for gpI in range(gpNew.size()):
		# Move every routing vertex that coincides with an endpoint of the grabbed segment. Port-bound
		# and stub vertices are NOT routing entries, so they are left untouched (the line stays connected).
		# 平移所有与被抓段端点重合的路由顶点。绑定端口与引出段顶点不在路由中，故保持不动（线保持连接）。
		if gpNew[gpI].distance_to(_gpSegA) <= GP_EPS:
			gpNew[gpI] = gpNew[gpI] + gpD
		if gpNew[gpI].distance_to(_gpSegB) <= GP_EPS:
			gpNew[gpI] = gpNew[gpI] + gpD
	gpE.gpRouting = gpNew
	_gpGrip["pos"] = _gpSegOrigMid + gpD
	gpCv.queue_redraw()


# Reshape the bump: overwrite its two waypoints with a fresh tent centred on the cursor, reusing the
# SAME localised-tent routine used at creation (so the apex tracks the cursor and the bump stays clear
# of the 14px stubs). / 重塑鼓包：用「以光标为中心」的新帐篷覆盖其两个拐点，复用创建时的同一局部帐篷例程
# （顶点跟光标、且避开 14px 引出段）。
func _gpApplyBumpMove(gpWorld: Vector2) -> void:
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null or _gpBumpIdx < 0:
		return
	var gpPts: PackedVector2Array = _gpPolyline(gpE)
	var gpI0: int = _gpBumpIdx
	# Outer vertices bracketing the bump: pt[2+i0-1] (before the first waypoint) and pt[2+i0+2]
	# (after the second). Clamp to the polyline ends for an end-anchored bump.
	# 鼓包两侧的外顶点：第一个拐点前的 pt[2+i0-1] 与第二个后的 pt[2+i0+2]。端锚鼓包时钳到折线两端。
	var gpOuterA: Vector2 = gpPts[0] if (2 + gpI0 - 1) < 0 else gpPts[2 + gpI0 - 1]
	var gpOuterB: Vector2 = gpPts[gpPts.size() - 1] if (2 + gpI0 + 2) >= gpPts.size() else gpPts[2 + gpI0 + 2]
	var gpW: Array[Vector2] = gpBumpWaypoints(gpOuterA, gpOuterB, gpWorld)
	var gpNew: Array[Vector2] = gpE.gpRouting.duplicate()
	if gpI0 + 1 < gpNew.size():
		gpNew[gpI0] = gpW[0]
		gpNew[gpI0 + 1] = gpW[1]
		gpE.gpRouting = gpNew
		_gpGrip["pos"] = (gpW[0] + gpW[1]) * 0.5
		# The orange anchor position is DERIVED from routing[idx..idx+1] in gpBumpGrips, so it tracks
		# the apex automatically — no separate list to keep in sync. / 橙色锚点位置由 routing 推导，
		# 自动跟随顶点，无需再同步额外列表。
	gpCv.queue_redraw()


# Finish the drag: commit one undo step ONLY when the geometry actually changed. The live-mutated
# routing is rewound to the original, then re-applied through the command so undo restores it.
# 结束拖拽：仅当几何确有变化时提交一个撤销步。先把实时改写的路由回退到原值，再经命令重新施加，
# 使撤销能还原到原值。
func gpEndGripDrag() -> void:
	if _gpGrip.is_empty():
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(_gpEdgeId)
	var gpFinal: Array[Vector2] = [] if gpE == null else gpE.gpRouting.duplicate()
	if gpE != null:
		gpE.gpRouting = _gpOrigRouting.duplicate()
	if gpE != null and not _gpRoutingEqual(gpFinal, _gpOrigRouting):
		gpCv.gpRequestSetEdgeRouting(_gpEdgeId, gpFinal)
	_gpGrip = {}
	_gpEdgeId = ""
	_gpOrigRouting = []
	_gpSeg = 0
	_gpSegA = Vector2.ZERO
	_gpSegB = Vector2.ZERO
	_gpSegOrigMid = Vector2.ZERO
	_gpPressWorld = Vector2.ZERO
	_gpBumpIdx = -1
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()


# Abandon any in-flight drag without applying anything (ESC / cancel path).
# 放弃进行中的拖拽，不应用任何改动（ESC / 取消路径）。
func gpEndDrag() -> void:
	_gpGrip = {}
	_gpEdgeId = ""
	_gpOrigRouting = []
	_gpSeg = 0
	_gpSegA = Vector2.ZERO
	_gpSegB = Vector2.ZERO
	_gpSegOrigMid = Vector2.ZERO
	_gpPressWorld = Vector2.ZERO
	_gpBumpIdx = -1
	# Also abandon any in-flight whole-edge translate. / 同时放弃进行中的整线平移。
	_gpMoveEdge = ""
	_gpMoveStart = Vector2.ZERO
	_gpMoveOrigRouting = []
	_gpMoveDangFrom = Vector2.INF
	_gpMoveDangTo = Vector2.INF
	gpCv.queue_redraw()


# Begin a whole-edge translate: snapshot the FREE geometry (routing + any dangling ends) at the press
# point, so a live drag can replay it rigidly by the cursor delta. The line moves as ONE rigid body —
# the point under the cursor at press stays under it — instead of bending at the grab point. Port-bound
# ends are intentionally NOT snapshotted because they follow their symbol and must never be moved here.
# 开始整线平移：在按下点快照「自由几何」（路由 + 任意悬空端），使实时拖拽按光标位移刚性重放。
# 整条线作为「一个刚体」移动——按下时光标下的点始终停在光标下——而非在抓取点处折断。
# 端口端有意不纳入快照，因为它们跟随图元、绝不能在此被移动。
func gpStartEdgeMove(gpEdgeId: String, gpWorld: Vector2) -> void:
	_gpMoveEdge = gpEdgeId
	_gpMoveStart = gpWorld
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	_gpMoveOrigRouting = gpE.gpRouting.duplicate()
	_gpMoveDangFrom = gpE.gpDanglingPoint(true) if gpE.gpIsDangling(true) else Vector2.INF
	_gpMoveDangTo = gpE.gpDanglingPoint(false) if gpE.gpIsDangling(false) else Vector2.INF
	gpCv.queue_redraw()


# Live-apply the whole-edge translate: shift every routing waypoint AND every dangling end by the SAME
# delta, so the line moves rigidly. Port-bound ends are untouched (they follow their symbol). This is
# what makes dragging a pipe feel like moving the whole line, not bending it at the cursor.
# 实时应用整线平移：把每个路由拐点与每个悬空端都按「同一位移」平移，使线刚性移动。端口端不受影响
# （跟随图元）。这正使拖动管线表现为「整条线移动」，而非在光标处折断。
func gpOnEdgeMove(gpWorld: Vector2) -> void:
	if _gpMoveEdge == "":
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(_gpMoveEdge)
	if gpE == null:
		return
	var gpD: Vector2 = gpWorld - _gpMoveStart
	var gpNewRouting: Array[Vector2] = []
	for gpP in _gpMoveOrigRouting:
		gpNewRouting.append(gpP + gpD)
	gpE.gpRouting = gpNewRouting
	if _gpMoveDangFrom != Vector2.INF:
		gpE.gpSetDanglingPoint(true, _gpMoveDangFrom + gpD)
	if _gpMoveDangTo != Vector2.INF:
		gpE.gpSetDanglingPoint(false, _gpMoveDangTo + gpD)
	gpCv.queue_redraw()


# Finish a whole-edge translate: commit one undo step ONLY when geometry changed. The live mutation is
# rewound to the original, then re-applied through the command layer so undo restores it. A dangling
# end that moved is committed as a dangling reconnect (node_id "" + new point).
# 结束整线平移：仅当几何确有变化时提交一个撤销步。先把实时改写回退到原值，再经命令层重新施加以便撤销。
# 移动的悬空端以「改接为悬空」（node_id 为空 + 新点）提交。
func gpEndEdgeMove() -> void:
	if _gpMoveEdge == "":
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(_gpMoveEdge)
	var gpFinalRouting: Array[Vector2] = []
	var gpFinalFrom: Vector2 = Vector2.INF
	var gpFinalTo: Vector2 = Vector2.INF
	if gpE != null:
		gpFinalRouting = gpE.gpRouting.duplicate()
		gpFinalFrom = gpE.gpDanglingPoint(true) if gpE.gpIsDangling(true) else Vector2.INF
		gpFinalTo = gpE.gpDanglingPoint(false) if gpE.gpIsDangling(false) else Vector2.INF
		# Rewind live mutation before committing through the command layer.
		# 经命令层提交前先回退实时改写。
		gpE.gpRouting = _gpMoveOrigRouting.duplicate()
		if _gpMoveDangFrom != Vector2.INF:
			gpE.gpSetDanglingPoint(true, _gpMoveDangFrom)
		if _gpMoveDangTo != Vector2.INF:
			gpE.gpSetDanglingPoint(false, _gpMoveDangTo)
	var gpChanged: bool = (not _gpRoutingEqual(gpFinalRouting, _gpMoveOrigRouting)) \
		or (_gpMoveDangFrom != Vector2.INF and gpFinalFrom != _gpMoveDangFrom) \
		or (_gpMoveDangTo != Vector2.INF and gpFinalTo != _gpMoveDangTo)
	if gpChanged:
		gpCv.gpRequestSetEdgeRouting(_gpMoveEdge, gpFinalRouting)
		if _gpMoveDangFrom != Vector2.INF and gpFinalFrom != _gpMoveDangFrom:
			gpCv.gpRequestReconnectEdge(_gpMoveEdge, true,
				{"node_id": "", "port_id": "", "point": [gpFinalFrom.x, gpFinalFrom.y]})
		if _gpMoveDangTo != Vector2.INF and gpFinalTo != _gpMoveDangTo:
			gpCv.gpRequestReconnectEdge(_gpMoveEdge, false,
				{"node_id": "", "port_id": "", "point": [gpFinalTo.x, gpFinalTo.y]})
	_gpMoveEdge = ""
	_gpMoveStart = Vector2.ZERO
	_gpMoveOrigRouting = []
	_gpMoveDangFrom = Vector2.INF
	_gpMoveDangTo = Vector2.INF
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()


# Delete a bump anchor by its ARRAY index (ai) on an edge: remove the two tent waypoints from the
# routing, drop the anchor entry, and shift later anchors' pair indices by -2. Committed through the
# command layer so it is undoable; the bump selection is cleared afterwards.
# 按数组下标 ai 删除某边的鼓包锚点：从 routing 移除两个帐篷拐点、删去该锚点记录、后续锚点对下标 -2；
# 经命令层提交以便撤销，并清除锚点选择。
func gpDeleteBump(gpEdgeId: String, gpAi: int) -> void:
	if gpIsDragging() or gpIsMoving():
		return
	if not _gpBumpAnchors.has(gpEdgeId):
		return
	var gpList: Array = _gpBumpAnchors[gpEdgeId]
	if gpAi < 0 or gpAi >= gpList.size():
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	var gpRIdx: int = int(gpList[gpAi])
	if gpRIdx < 0 or gpRIdx + 1 >= gpE.gpRouting.size():
		# Routing lost the pair (e.g. edge re-routed) — drop the stale anchor entry only.
		# routing 已无该对（如边被重布）→ 仅删锚点记录。
		gpList.remove_at(gpAi)
		_gpBumpAnchors[gpEdgeId] = gpList
		gpClearBumpSelection()
		gpCv.queue_redraw()
		return
	var gpNew: Array[Vector2] = gpE.gpRouting.duplicate()
	gpNew.remove_at(gpRIdx)
	gpNew.remove_at(gpRIdx)
	gpList.remove_at(gpAi)
	for gpI in range(gpList.size()):
		if int(gpList[gpI]) > gpRIdx:
			gpList[gpI] = int(gpList[gpI]) - 2
	_gpBumpAnchors[gpEdgeId] = gpList
	gpE.gpRouting = gpNew
	gpCv.gpRequestSetEdgeRouting(gpEdgeId, gpNew)
	gpClearBumpSelection()
	gpCv.queue_redraw()


# Element-wise equality of two Vector2 routing arrays. / 两个 Vector2 路由数组逐元素相等。
func _gpRoutingEqual(gpA: Array[Vector2], gpB: Array[Vector2]) -> bool:
	if gpA.size() != gpB.size():
		return false
	for gpI in range(gpA.size()):
		if gpA[gpI] != gpB[gpI]:
			return false
	return true


# Map a resolved-polyline SEGMENT index to the index inside gpRouting where a bump for that segment
# belongs. The polyline = [endA, stubA] + routing (+ corners) + [stubB, endB], so the two indices
# diverge as soon as stubs or prior waypoints exist — this search keeps them aligned.
# 把（已解析折线）「段下标」映射到 gpRouting 中该段鼓出所属的下标。折线 = [端A, 引A] + routing
#（+角点）+ [引B, 端B]，故一旦存在引出段或既有折点，二者即背离——本搜索使二者对齐。
static func _gpRoutingInsertIndex(gpP0: PackedVector2Array, gpR0: Array[Vector2], gpSeg: int) -> int:
	var gpPIdx: Array[int] = []
	for gpR in gpR0:
		var gpFound: int = -1
		for gpI in range(gpP0.size()):
			if gpP0[gpI].distance_to(gpR) <= GP_EPS:
				gpFound = gpI
				break
		gpPIdx.append(gpFound)
	for gpJ in range(gpPIdx.size()):
		if gpSeg < gpPIdx[gpJ]:
			return gpJ
	return gpPIdx.size()


# Index of the bump whose apex is nearest gpAnchorPos (within a hard tolerance), or -1 if none.
# 返回顶点最接近 gpAnchorPos 的鼓包下标（在硬容差内），无则 -1。
func _gpFindBumpPair(gpE: GPPIDEdge, gpAnchorPos: Vector2) -> int:
	var gpR: Array[Vector2] = gpE.gpRouting
	var gpBest: int = -1
	var gpBestD: float = 14.0
	for gpI in range(gpR.size() - 1):
		var gpMid: Vector2 = (gpR[gpI] + gpR[gpI + 1]) * 0.5
		var gpD: float = gpMid.distance_to(gpAnchorPos)
		if gpD < gpBestD:
			gpBestD = gpD
			gpBest = gpI
	return gpBest


# World midpoint of an edge (used to anchor the in-place tag editor). Vector2.INF when the
# edge is missing. / 一条边的世界中点（用于锚定就地位号编辑器）。边缺失时返回 Vector2.INF。
func gpEdgeMidpointWorld(gpEdgeId: String) -> Vector2:
	if gpCv.gpGraph == null:
		return Vector2.INF
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return Vector2.INF
	var gpPts: PackedVector2Array = _gpPolyline(gpE)
	if gpPts.is_empty():
		return Vector2.INF
	# Endpoints are averaged (not the routing centroid) so the field sits on the visible line
	# even when there are no waypoints. / 取两端平均（而非拐点质心），使无拐点时字段仍落在可见线上。
	return (gpPts[0] + gpPts[gpPts.size() - 1]) * 0.5


# Paint the grips for the selected edge. Called from the select tool's overlay hook, which
# only runs in SELECT mode. Every segment shows one blue square at its midpoint; orange bump anchors
# (created by right-click) overlay their apexes. The actively dragged grip is filled to read as "engaged".
# 为选中边绘制抓取点。由选择工具的覆盖层钩子调用（仅选择模式）。每段在中心画一个蓝色方块；右键生成的
# 橙色鼓包锚点叠在其顶点。正在拖动的抓取点填充以示「已啮合」。
# [param gpItem] the canvas (a CanvasItem) to draw on / 被绘制的画布（CanvasItem）
# [param gpEdgeId] edge whose grips to draw, or "" for none / 要画抓取点的边 id；"" 表示无
func gpDrawGrips(gpItem: CanvasItem, gpEdgeId: String) -> void:
	if gpCv.gpGraph == null or gpEdgeId == "":
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	var gpPts: PackedVector2Array = _gpPolyline(gpE)
	var gpGs: float = GP_GRIP_SIZE
	var gpActiveSeg: int = int(_gpGrip.get("seg", -1)) if (gpIsDragging() and str(_gpGrip.get("kind", "")) == GP_KIND_MID) else -1
	# Blue midpoint grips (the segment-translate handles). / 蓝色段中点抓取点（段平移手柄）。
	for gpG in gpMidpointGrips(gpPts):
		var gpMs: Vector2 = gpItem.gpScreenFromWorld(gpG["pos"])
		var gpRect: Rect2 = Rect2(gpMs - Vector2(gpGs * 0.5, gpGs * 0.5), Vector2(gpGs, gpGs))
		if int(gpG["seg"]) == gpActiveSeg:
			gpItem.draw_rect(gpRect, GP_COL_MID, true)
			gpItem.draw_rect(gpRect, Color(1.0, 1.0, 1.0), false, 1.5)
		else:
			gpItem.draw_rect(gpRect, Color(1.0, 1.0, 1.0), true)
			gpItem.draw_rect(gpRect, GP_COL_MID, false, 1.5)
	# Orange bump anchors (right-click created). / 橙色鼓包锚点（右键生成）。
	for gpG in gpBumpGrips(gpEdgeId):
		var gpMs: Vector2 = gpItem.gpScreenFromWorld(gpG["pos"])
		var gpEs: float = gpGs + 2.0
		var gpRect: Rect2 = Rect2(gpMs - Vector2(gpEs * 0.5, gpEs * 0.5), Vector2(gpEs, gpEs))
		gpItem.draw_rect(gpRect, GP_COL_BUMP, true)
		gpItem.draw_rect(gpRect, Color(1.0, 1.0, 1.0), false, 1.5)
	# While dragging, draw the orthogonal guide cross / preview.
	# 拖拽中绘制正交辅助线 / 预览。
	if gpIsDragging() and not _gpGrip.is_empty():
		_gpDrawDragGuide(gpItem)


# Horizontal + vertical guide lines through the dragged grip — the "横竖辅助线" the editor is expected
# to show while reshaping a pipe. / 横竖辅助线：拖动抓取点时显示的正交参考线。
func _gpDrawDragGuide(gpItem: CanvasItem) -> void:
	var gpC: Vector2 = gpItem.gpScreenFromWorld(_gpGrip.get("pos", Vector2.ZERO))
	var gpSpan: float = 60.0
	gpItem.draw_line(gpC + Vector2(-gpSpan, 0.0), gpC + Vector2(gpSpan, 0.0), GP_GUIDE_COL, 1.0)
	gpItem.draw_line(gpC + Vector2(0.0, -gpSpan), gpC + Vector2(0.0, gpSpan), GP_GUIDE_COL, 1.0)
