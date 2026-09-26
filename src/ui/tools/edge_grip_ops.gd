class_name GPEdgeGripOps
extends RefCounted

# Edge PATH editing for GPCanvas2D .
# 边的「路径」编辑。
#
# THE MODEL / 模型
# Two distinct edit gestures on a SELECTED edge:
# 0) 蓝色段中点抓取点（每个横/竖线段一个，位于中点）。拖动它 = 该线段整体平移（两端点按同一位移移动，
# 衔接处的角点随之移动），整条线保持正交，且抓取点始终跟在光标下。
# Blue midpoint grip (one per segment, at its midpoint). Dragging it TRANSLATES that whole
# segment rigidly (both its endpoints move by the same delta); the shared corners follow, so the
# line stays orthogonal and the grab point tracks the cursor.
# 1) 橙色角点（右键任意线段生成）。它在最近线段处插入「一个」折线角点（单个 routing 顶点）；橙色角点
# 位于该顶点本身，可直接左键拖动以移动这个角点。右键在边线上默认生成角点；右键命中既有橙色角点
# 则弹出「删除角点」菜单；选中橙色角点后按 Del 也可删除。删除角点后该段经 gpRoute() 自动重新正交连接。
# Orange CORNER (created by RIGHT-CLICKING anywhere on a segment). It inserts ONE polyline corner
# (a single routing vertex) on the nearest segment; the orange marker sits ON that vertex and is
# itself left-draggable to MOVE the corner. Right-click on an edge body creates a corner; right-click
# on an EXISTING orange corner opens a "delete corner" menu instead; a selected corner is also deleted
# by the Del key. After deletion the section re-orthogonalizes through gpRoute() automatically.
#
# 角点索引模型 / Corner index model:
# GPEdgeBumpAnchors 中每边存的是「该角点所在 routing 顶点的下标」(Array[int])，而非世界坐标，故无论连线
# 如何平移/整线移动/段平移，角点恒在线上（推导位置 = routing[idx]，绝不孤悬）。删除该顶点即删除角点，
# 后续角点下标整体 -1；整线/段移动平移 routing 后推导位置自动跟随。
# GPEdgeBumpAnchors stores per edge the ROUTING-INDEX of the corner's vertex (Array[int]), NOT a world coord,
# so the corner ALWAYS rides the line as the edge is moved/translated (its position is derived from
# routing[idx] and can never float off). Deleting that vertex removes the corner; later indices shift -1.
#
# 端口到端口的直线（单段、端点锁死在端口）若无折点则无自由几何可平移——此时线体拖拽改走「在按下处插入
# 角点并立即角点拖拽」(gpStartCornerDrag())，使纯直线也可被拖动；gpRoute() 的引出段(stub)始终沿端口法线，
# 故与图元连接处永远保留一段垂直直连。
# A port-to-port straight line (no waypoints, both ends locked) has no free geometry to translate — its
# body drag instead inserts a corner at the press point and drags it (gpStartCornerDrag()), so even a bare
# straight edge is draggable; the port stub (always along the port normal via gpRoute()) keeps a perpendicular
# straight connection to the symbol.

# Grip kind: a segment midpoint (rigid translate). / 抓取点角色：段中点（刚体平移）。
const GP_KIND_MID: String = "mid"

# Grip kind: an orange corner anchor (right-click create / left-drag move the corner). / 橙色角点锚点（右键生成 / 左键移动该角点）。
const GP_KIND_BUMP: String = "bump"

# Screen-pixel size of a grip square. / 抓取点方块的屏幕像素尺寸。
const GP_GRIP_SIZE: float = 9.0

# Midpoint grip colour (matches the selection-highlight blue). / 段中点抓取点配色（与选中高亮蓝一致）。
const GP_COL_MID: Color = Color(0.20, 0.50, 1.0)

# Bump-anchor colour — distinct from the blue midpoint grips. / 鼓包锚点配色——与蓝色中点抓取点区分。
const GP_COL_BUMP: Color = Color(1.0, 0.62, 0.0)

# Perpendicular offset (world units) applied to a freshly created corner so it is a REAL (non-collinear)
# vertex. Without it gpRoute()/gpClean() would fold a collinear waypoint away and the corner would be invisible.
# 新建角点沿垂直方向偏移的世界单位量，使其成为一个「真实」（非共线）顶点。若不偏移，gpRoute()/gpClean()
# 会把共线折点折叠掉，角点便不可见。
const GP_CORNER_OFFSET: float = 18.0

# Faint colour for the cross guide drawn while dragging a grip. / 拖动抓取点时绘制的十字辅助线淡色。
const GP_GUIDE_COL: Color = Color(0.35, 0.62, 1.0, 0.55)

# Geometry epsilon shared with GPEdgeRoute (axis-alignment tolerance). / 与 GPEdgeRoute 共用的几何容差。
const GP_EPS: float = GPConstants.GP_EPS


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

# Corner drag: routing index of the single vertex being moved (the orange anchor's vertex).
# 角点拖动：正被移动的「单个 routing 顶点」的下标（即橙色锚点对应的顶点）。
var _gpBumpIdx: int = -1

# Persistent corner anchors and their selection live in their own coordinator
# (see edge_bump_anchors.gd). It answers "where are the corners" and "change the corner set";
# this class keeps only the DRAG state — which corner is in flight right now.
# 持久角点锚点及其选中由独立协调者持有（见 edge_bump_anchors.gd）。它回答「角点在哪里」
# 与「增删角点集合」；本类只保留**拖拽状态** —— 当前正在移动哪个角点。
var gpAnchors: GPEdgeBumpAnchors = null

# Select a corner anchor (ai = array index into gpAnchors.gpAnchorsFor(eid)).
# 选中某角点锚点（ai = gpAnchors.gpAnchorsFor(eid) 的数组下标）。
func gpSelectBump(gpEdgeId: String, gpAi: int) -> void:
	gpAnchors.gpSelectBump(gpEdgeId, gpAi)


# The selected corner anchor, or an empty dict when none. / 选中的角点锚点；无则返回空字典。
func gpSelectedBump() -> Dictionary:
	return gpAnchors.gpSelectedBump()


# Drop the corner selection (called when the user clicks elsewhere). / 清除角点选择（点别处时调用）。
func gpClearBumpSelection() -> void:
	gpAnchors.gpClearBumpSelection()

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
	gpAnchors = GPEdgeBumpAnchors.new(gpCv)


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

# True when every consecutive pair in gpPts shares an x or a y (axis-aligned polyline).
# 当 gpPts 中相邻两点恒共 x 或共 y（轴对齐折线）时为真。
static func gpPolylineOrtho(gpPts: PackedVector2Array) -> bool:
	return GPEdgeGripGeometry.gpPolylineOrtho(gpPts)

static func gpMidpointGrips(gpPts: PackedVector2Array) -> Array[Dictionary]:
	return GPEdgeGripGeometry.gpMidpointGrips(gpPts)

static func _gpFindNearestSegment(gpPts: PackedVector2Array, gpWorld: Vector2) -> int:
	return GPEdgeGripGeometry.gpFindNearestSegment(gpPts, gpWorld)

func _gpPolyline(gpE: GPPIDEdge) -> PackedVector2Array:
	return GPEdgeGripGeometry.gpPolyline(gpCv, gpE)


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


# Return the orange corner anchor under the world point for the given edge, or an empty dict.
# "anchor" is the ARRAY index into gpAnchors.gpAnchorsFor(gpEdgeId) (used for deletion); the position IS the
# routing vertex at that index, so it is always on the line. / 返回世界点下该边的橙色角点，未命中返回空字典。
# "anchor" 是 gpAnchors.gpAnchorsFor(gpEdgeId) 的数组下标（供删除用）；位置即该下标处 routing 顶点，恒在线上。
func gpHitBump(gpWorld: Vector2, gpEdgeId: String) -> Dictionary:
	return gpAnchors.gpHitBump(gpWorld, gpEdgeId)


# The orange corner anchors of an edge (for drawing). Each is a SINGLE routing vertex, so its position
# IS that vertex — it always sits on the line (never floats off). / 一条边的橙色角点（绘制用）。每个角点
# 是「单个 routing 顶点」，故其位置即该顶点本身——恒在线上、绝不脱离。
func gpBumpGrips(gpEdgeId: String) -> Array[Dictionary]:
	return gpAnchors.gpBumpGrips(gpEdgeId)


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
 # The grip dict carries the anchor ARRAY index (gpHitBump() returns it), so resolve the
 # routing-vertex index directly — no proximity search() needed.
 # 抓取点字典携带锚点的数组下标（gpHitBump() 返回），故直接定位 routing 顶点下标，无需邻近搜索。
			var gpAi: int = int(_gpGrip.get("anchor", -1))
			var gpList: Array = gpAnchors.gpAnchorsFor(gpEdgeId)
			if gpAi >= 0 and gpAi < gpList.size():
				_gpBumpIdx = int(gpList[gpAi])
				_gpGrip["pos"] = gpE.gpRouting[_gpBumpIdx] if (_gpBumpIdx >= 0 and _gpBumpIdx < gpE.gpRouting.size()) else Vector2.ZERO
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
 # A straight port-to-port edge has no routing vertex to translate, so the segment-translate
 # above would be a no-op ("line can't be dragged"). Fall back to inserting a corner at this
 # segment and dragging it, so the blue grip is always draggable.
 # 直连端口端口的边没有可平移的路由顶点，上面的段平移会成为空操作（「线不可拖动」）。退化为在该段
 # 插入一个角点并拖动它，使蓝色抓取点始终可拖。
		if gpE.gpRouting.is_empty() and not gpE.gpIsDangling(true) and not gpE.gpIsDangling(false):
			gpStartCornerDrag(gpEdgeId, _gpSegOrigMid)
			return
	gpCv.queue_redraw()


# Right-click on a segment -> create an orange corner anchor there (insert ONE routing vertex, commit
# immediately and remember the anchor so it can be re-dragged later). The vertex is the click projected
# onto the segment, offset perpendicular by GP_CORNER_OFFSET so it is a REAL corner (gpRoute()/gpClean()
# would otherwise fold a collinear point away). Dragging the corner later moves that vertex.
# 右键点击线段 -> 在该处生成橙色角点锚点（插入「一个」routing 顶点，立即提交并记下锚点，便于日后重新拖动）。
# 该顶点是点击投影到线段上的点、沿垂直方向偏移 GP_CORNER_OFFSET，使其成为「真实」角点（否则 gpRoute()/gpClean()
# 会把共线点折叠掉）。日后拖动角点即移动该顶点。
func gpStartBump(gpEdgeId: String, gpWorld: Vector2) -> void:
	# The corner geometry and the anchor bookkeeping are the anchors coordinator's job; only the
	# apply + commit belong here. / 角点几何与锚点登记属锚点协调者；此处只负责应用与提交。
	var gpR: Dictionary = gpAnchors.gpInsertCorner(gpEdgeId, gpWorld)
	if not bool(gpR.get("ok", false)):
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	# Live-apply (so headless tests see it) AND commit through the command layer (so the editor undoes).
	# 实时应用（使 headless 测试可见）并经命令层提交（使编辑器可撤销）。
	var gpNew: Array[Vector2] = gpR.get("routing", [])
	gpE.gpRouting = gpNew
	gpCv.gpRequestSetEdgeRouting(gpEdgeId, gpNew)
	gpCv.queue_redraw()


# Left-drag an existing orange anchor -> move that corner. gpAnchorIdx is the ARRAY index into
# gpAnchors.gpAnchorsFor(gpEdgeId) (gpHitBump() returns it), so we resolve the routing-vertex index directly
# without a proximity search(). / 左键拖动既有橙色锚点 -> 移动该角点。gpAnchorIdx 为
# gpAnchors.gpAnchorsFor(gpEdgeId) 的数组下标（gpHitBump() 返回），直接定位 routing 顶点，免去邻近搜索。
func gpStartBumpDrag(gpEdgeId: String, gpAnchorIdx: int) -> void:
	_gpEdgeId = gpEdgeId
	_gpGrip = {"kind": GP_KIND_BUMP, "anchor": gpAnchorIdx, "pos": Vector2.ZERO}
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	var gpList: Array = gpAnchors.gpAnchorsFor(gpEdgeId)
	if gpE != null and gpAnchorIdx >= 0 and gpAnchorIdx < gpList.size():
		var gpRIdx: int = int(gpList[gpAnchorIdx])
		_gpBumpIdx = gpRIdx
		_gpOrigRouting = gpE.gpRouting.duplicate()
		if gpRIdx >= 0 and gpRIdx < gpE.gpRouting.size():
			_gpGrip["pos"] = gpE.gpRouting[gpRIdx]
	gpCv.queue_redraw()


# Left-press on the body of a straight (routing-empty, both-ends-bound) edge -> insert ONE corner at
# the press point and immediately enter corner-drag mode, so the line becomes draggable even with no
# pre-existing anchor (satisfies "横竖线也应可拖动"). The new corner is offset perpendicular by
# GP_CORNER_OFFSET (a real bend) and then tracks the cursor. The whole press-drag commits as ONE undo
# step because _gpOrigRouting snapshots the pre-insert routing and gpEndGripDrag() re-applies the net final.
# 在「无路由折点、两端绑定」的直边线体上按下 -> 在按下处插入「一个」角点并立即进入角点拖拽模式，
# 使该直线即使没有既有锚点也可被拖动（满足「横竖线也应可拖动」）。新角点沿垂直方向偏移 GP_CORNER_OFFSET
# （真实拐角）后跟随光标。整个「按下-拖拽」只提交一个撤销步：因为 _gpOrigRouting 快照的是插入前的路由，
# gpEndGripDrag() 重新施加净终值。
func gpStartCornerDrag(gpEdgeId: String, gpWorld: Vector2) -> void:
	# Same corner creation as gpStartBump(), but the press immediately enters corner-drag mode.
	# 与 gpStartBump() 相同的角点创建，但按下后立即进入角点拖拽模式。
	var gpR: Dictionary = gpAnchors.gpInsertCorner(gpEdgeId, gpWorld)
	if not bool(gpR.get("ok", false)):
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	# Snapshot the PRE-insert routing so gpEndGripDrag() commits exactly ONE undo step for the whole
	# press-drag (creation + any move combined). Live-apply only; do NOT commit here.
	# 快照「插入前」的路由，使 gpEndGripDrag() 为整个按下-拖拽只提交一个撤销步（创建+移动合一）。
	# 此处仅实时应用，不提交。
	_gpEdgeId = gpEdgeId
	_gpBumpIdx = int(gpR.get("insert", -1))
	_gpGrip = {"kind": GP_KIND_BUMP, "anchor": int(gpR.get("anchor", -1)),
		"pos": gpR.get("corner", Vector2.ZERO)}
	_gpOrigRouting = gpR.get("orig_routing", [])
	gpE.gpRouting = gpR.get("routing", [])
	gpCv.queue_redraw()


# Live-update the grip being dragged. / 实时更新被拖动的抓取点。
func gpOnGripMove(gpWorld: Vector2) -> void:
	if _gpGrip.is_empty():
		return
	if str(_gpGrip.get("kind", "")) == GP_KIND_BUMP:
		_gpApplyCornerMove(gpWorld)
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


# Move the dragged corner: write the cursor straight into the corner's routing vertex. gpRoute() then
# re-orthogonalizes the two legs through that vertex on the next redraw, so the orange anchor (drawn
# at routing[idx] in gpBumpGrips()) tracks the cursor exactly and the bend follows.
# 移动被拖的角点：把光标直写进该角点的 routing 顶点。下一次重绘时 gpRoute() 经该顶点把两条腿重新正交化，
# 于是（在 gpBumpGrips() 中按 routing[idx] 绘制的）橙色锚点精确跟随光标、拐点随之移动。
func _gpApplyCornerMove(gpWorld: Vector2) -> void:
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null or _gpBumpIdx < 0:
		return
	var gpNew: Array[Vector2] = gpE.gpRouting.duplicate()
	if _gpBumpIdx < gpNew.size():
		gpNew[_gpBumpIdx] = gpWorld
		gpE.gpRouting = gpNew
		_gpGrip["pos"] = gpWorld
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


# Delete a corner anchor by its ARRAY index (ai) on an edge: remove the single corner vertex from the
# routing, drop the anchor entry, and shift later anchors' vertex indices by -1. Committed through the
# command layer so it is undoable; the corner selection is cleared afterwards. After deletion gpRoute()
# re-orthogonalizes the section automatically, so the pipe reconnects orthogonally.
# 按数组下标 ai 删除某边的角点锚点：从 routing 移除单个角点顶点、删去该锚点记录、后续锚点顶点下标 -1；
# 经命令层提交以便撤销，并清除角点选择。删除后 gpRoute() 自动把该段重新正交化，管线恢复正交连接。
func gpDeleteBump(gpEdgeId: String, gpAi: int) -> void:
	# Never mutate the corner set mid-gesture: a drag in flight commits its own routing on release,
	# and deleting a vertex underneath it would leave that commit pointing at a stale index.
	# 手势进行中绝不改动角点集合：进行中的拖拽会在释放时提交自己的路由，
	# 若在它下面删掉顶点，该提交将指向失效下标。
	if gpIsDragging() or gpIsMoving():
		return
	gpAnchors.gpDeleteBump(gpEdgeId, gpAi)


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
# diverge as soon as stubs or prior waypoints exist — this search() keeps them aligned.
# 把（已解析折线）「段下标」映射到 gpRouting 中该段鼓出所属的下标。折线 = [端A, 引A] + routing
#（+角点）+ [引B, 端B]，故一旦存在引出段或既有折点，二者即背离——本搜索使二者对齐。
static func _gpRoutingInsertIndex(gpP0: PackedVector2Array, gpR0: Array[Vector2], gpSeg: int) -> int:
	return GPEdgeGripGeometry.gpRoutingInsertIndex(gpP0, gpR0, gpSeg)

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


# ============================================================================
# 放置图元到连线：压线检测 / 绕行 / 拆分
# Drop a symbol onto a line: overlap detection / reroute / split.
#
# A freshly placed symbol landing ON an existing pipe offers the user two outcomes:
# ① the pipe routes AROUND the new symbol; ② the pipe SPLITS into two that connect to the
# symbol's two ports. Splitting needs >=2 ports — with fewer it refuses and the caller prompts
# "edit the symbol and add ports".
# 新放置的图元落到既有管线上时，给用户二选一：① 管线「绕开」新图元；② 管线「拆分」成两根、
# 分别接图元的两个端口。拆分需 >=2 端口 —— 不足则拒绝并由调用方提示「修改图元增加端点」。
# ============================================================================

# True when any polyline segment crosses the rect (the pipe pierces the node envelope).
# 折线任一段与该矩形相交即为真（管线穿透了节点包络）。
#
# Godot 4 的 Geometry2D 没有 segment_intersects_rect —— 只有 segment_intersects_segment，故拿矩形
# 的四条边逐边求交。此外一段「完全落在矩形内部」的管线与四边都不相交，会被漏检，所以用
# has_point 兜住任一端点在矩形内的情形（通常情况下管线两端在图元之外，至此已覆盖全部情形）。
# Geometry2D exposes no segment_intersects_rect, only segment_intersects_segment, so we test the
# four edges one by one. A segment lying wholly INSIDE the rect crosses none of them, which would
# be missed — has_point covers that case (pipe ends normally sit outside the symbol, so this closes
# the last gap).
static func _gpPolylineHitsRect(gpPts: PackedVector2Array, gpRect: Rect2) -> bool:
	return GPEdgeGripGeometry.gpPolylineHitsRect(gpPts, gpRect)

func gpEdgeUnderNode(gpNode: GPPIDNode) -> String:
	return GPEdgeGripGeometry.gpEdgeUnderNode(gpCv, gpNode)

func gpEdgesUnderNode(gpNode: GPPIDNode) -> Array[String]:
	return GPEdgeGripGeometry.gpEdgesUnderNode(gpCv, gpNode)

func gpRerouteAround(gpEdgeId: String, gpSymNid: String) -> void:
	return GPEdgeGripGeometry.gpRerouteAround(gpCv, gpEdgeId, gpSymNid)

func gpSplitThroughSymbol(gpEdgeId: String, gpSymNid: String) -> bool:
	return GPEdgeGripGeometry.gpSplitThroughSymbol(gpCv, gpEdgeId, gpSymNid)

static func _gpPickSplitPorts(gpSym: GPPIDNode, gpDef: GPSymbolDef, gpA: Vector2, gpB: Vector2) -> Dictionary:
	return GPEdgeGripGeometry.gpPickSplitPorts(gpSym, gpDef, gpA, gpB)
