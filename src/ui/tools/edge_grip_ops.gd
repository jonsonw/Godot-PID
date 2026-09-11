class_name GPEdgeGripOps
extends RefCounted

# Edge-endpoint / routing-vertex editing for GPCanvas2D (P3-4). Pure orchestration over the
# live graph: it resolves an edge's endpoints through GPPortResolver, draws the grips for a
# selected edge, and on drag mutates gpRouting / reconnects an end through the canvas's edit
# ports (so every change is ONE undo step).
# 边的端点 / 路由顶点编辑（P3-4）。对实时图的纯编排：经 GPPortResolver 解析端点、为选中边绘制抓取点，
# 拖拽时改写 gpRouting / 改接端点（均经画布编辑端口，故每次改动合成一个撤销步）。
#
# Why a canvas delegate (not a free module) / 为何是画布委托：
# grip edits mutate gpGraph.gpRouting / the edge refs IN PLACE and need the canvas to redraw and
# broadcast, just like GPAnnotationEditor. The transient drag state lives here (not on the
# canvas) so select_tool can dispatch to it through one port, mirroring the annotation pattern.
# 抓取点编辑就地改写 gpGraph.gpRouting / 边引用并需画布重绘与广播，与 GPAnnotationEditor 同理。
# 瞬态拖拽状态存于此（而非画布），使选择工具能经一个端口分派，与注释编辑保持同一形状。

# Grip (handle) kinds. / 抓取点角色。
const GP_KIND_END: String = "end"      # an endpoint (reconnect / dangle) / 端点（改接 / 悬空）
const GP_KIND_VERTEX: String = "vertex"  # a routing waypoint (move) / 路由拐点（移动）
const GP_KIND_INSERT: String = "insert"  # a segment midpoint (add a waypoint) / 段中点（新增拐点）

# Screen-pixel size of a grip square. / 抓取点方块的屏幕像素尺寸。
const GP_GRIP_SIZE: float = 9.0

# Grip (handle) role colours, matching the annotation grips' blue-on-white.
# 抓取点配色，与注释抓取点的「蓝描边白填充」保持一致。
const GP_COL_VERTEX: Color = Color(0.20, 0.50, 1.0)
const GP_COL_INSERT: Color = Color(1.0, 0.60, 0.20)


# The canvas we edit on. / 被编辑的画布。
var gpCv: GPCanvas2D

# Active grip drag; empty dict = nothing in flight.
# 进行中的抓取点拖拽；空字典表示无。
var _gpGrip: Dictionary = {}

# Edge id being dragged. / 正在被拖动的边 id。
var _gpEdgeId: String = ""

# Snapshot of the routing at drag start (so the commit restores the original on undo).
# 拖拽开始时的路由快照（提交时供撤销还原到原值）。
var _gpOrigRouting: Array[Vector2] = []

# Pending endpoint ref while dragging an end (committed on release).
# 拖拽端点期间待提交的端点引用（松手时提交）。
var _gpPendingRef: Dictionary = {}


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# True while a grip drag is in flight. / 抓点拖拽进行中返回真。
func gpIsDragging() -> bool:
	return not _gpGrip.is_empty()


# The edge id whose grip is currently being dragged (empty when nothing is in flight). Used by the
# canvas to flag that edge as "editing" so its highlight differs from a plain selection.
# 当前正被拖拽抓取点的边 id（无进行时返回空）。供画布把该边标记为「编辑中」，使其高亮区别于普通选中。
func gpDraggingEdgeId() -> String:
	return _gpEdgeId


# The port purposes an end of this edge may bind to (drives snapping + reconnect validation).
# 该边端点可绑定的端口用途（决定吸附与改接校验）。
func _gpWantType(gpE: GPPIDEdge) -> String:
	if gpE.gpKind == GPPIDEdge.GP_SIGNAL:
		return ""
	return GPPort.GP_NOZZLE


# The port purposes an end of this edge may bind to, as a typed array (for GPSnapResolver).
# 该边端点可绑定的端口用途（类型化数组，供 GPSnapResolver 使用）。
func _gpWantTypes(gpE: GPPIDEdge) -> Array[String]:
	if gpE.gpKind == GPPIDEdge.GP_SIGNAL:
		return [GPPort.GP_SIGNAL, GPPort.GP_ACTUATOR, GPPort.GP_TERMINAL]
	return [GPPort.GP_NOZZLE]


# Build the resolved world polyline of an edge (endpoints + routing waypoints).
# 构造一条边的「已解析世界折线」（端点 + 路由拐点）。
func _gpPolyline(gpE: GPPIDEdge) -> PackedVector2Array:
	var gpDefs: Callable = gpCv.gpDefLookupCallable()
	var gpA: Dictionary = GPPortResolver.gpResolveEnd(gpCv.gpGraph, gpDefs, gpE, true, _gpWantType(gpE))
	var gpB: Dictionary = GPPortResolver.gpResolveEnd(gpCv.gpGraph, gpDefs, gpE, false, _gpWantType(gpE))
	var gpPts: PackedVector2Array = PackedVector2Array()
	gpPts.append(gpA["pos"])
	for gpR in gpE.gpRouting:
		gpPts.append(gpR)
	gpPts.append(gpB["pos"])
	return gpPts


# Return the grip under the world point for the given edge, or an empty dict.
# 返回世界点下该边的抓取点，未命中返回空字典。
# [param gpWorld] world position of the cursor / 光标世界坐标
# [param gpEdgeId] edge id whose grips are tested / 被测抓取点的边 id
func gpHitGrip(gpWorld: Vector2, gpEdgeId: String) -> Dictionary:
	if gpCv.gpGraph == null:
		return {}
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return {}
	var gpPts: PackedVector2Array = _gpPolyline(gpE)
	var gpTol: float = 6.0 / gpCv.gpViewZoom
	# Endpoints (highest priority — they are the ends of the line).
	# 端点（最高优先：它们是连线的两端）。
	if gpPts.size() >= 1 and gpWorld.distance_to(gpPts[0]) <= gpTol:
		return {"kind": GP_KIND_END, "isFrom": true, "pos": gpPts[0]}
	if gpPts.size() >= 2 and gpWorld.distance_to(gpPts[gpPts.size() - 1]) <= gpTol:
		return {"kind": GP_KIND_END, "isFrom": false, "pos": gpPts[gpPts.size() - 1]}
	# Routing vertices.
	# 路由拐点。
	for gpI in range(gpE.gpRouting.size()):
		if gpWorld.distance_to(gpE.gpRouting[gpI]) <= gpTol:
			return {"kind": GP_KIND_VERTEX, "idx": gpI, "pos": gpE.gpRouting[gpI]}
	# Insert grips at segment midpoints (add a waypoint on grab).
	# 段中点插入抓取点（抓取即新增拐点）。
	for gpS in range(gpPts.size() - 1):
		var gpMid: Vector2 = (gpPts[gpS] + gpPts[gpS + 1]) * 0.5
		if gpWorld.distance_to(gpMid) <= gpTol:
			return {"kind": GP_KIND_INSERT, "seg": gpS, "pos": gpMid}
	return {}


# Begin dragging the given grip of the given edge. An "insert" grip immediately becomes a
# vertex drag by splicing a waypoint into gpRouting at the segment index.
# 开始拖动给定边的给定抓取点。插入抓取点会立即在段下标处把拐点拼入 gpRouting，转为顶点拖拽。
func gpStartGripDrag(gpEdgeId: String, gpGrip: Dictionary) -> void:
	_gpEdgeId = gpEdgeId
	_gpGrip = gpGrip.duplicate()
	if _gpGrip.get("kind", "") == GP_KIND_INSERT:
		var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
		if gpE != null:
			var gpS: int = clampi(int(_gpGrip.get("seg", 0)), 0, gpE.gpRouting.size())
			gpE.gpRouting.insert(gpS, _gpGrip["pos"])
			_gpOrigRouting = gpE.gpRouting.duplicate()
			_gpGrip = {"kind": GP_KIND_VERTEX, "idx": gpS, "pos": _gpGrip["pos"]}
			gpCv.queue_redraw()
			return
	if _gpGrip.get("kind", "") == GP_KIND_VERTEX:
		var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
		if gpE != null:
			_gpOrigRouting = gpE.gpRouting.duplicate()
	_gpPendingRef = {}
	gpCv.queue_redraw()


# Live-update the grip being dragged. A vertex mutates gpRouting in place (for feedback); an
# end resolves the cursor against the graph and stores the pending ref (drawn as a preview).
# 实时更新被拖动的抓取点。顶点就地改写 gpRouting（给反馈）；端点把光标解析到图上并记下待提交引用（画成预览）。
func gpOnGripMove(gpWorld: Vector2) -> void:
	if _gpGrip.is_empty():
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null:
		return
	var gpKind: String = _gpGrip.get("kind", "")
	if gpKind == GP_KIND_VERTEX:
		var gpI: int = int(_gpGrip.get("idx", 0))
		if gpI >= 0 and gpI < gpE.gpRouting.size():
			gpE.gpRouting[gpI] = gpWorld
			gpCv.queue_redraw()
	elif gpKind == GP_KIND_END:
		var gpSnap: Dictionary = GPSnapResolver.gpSnap(gpCv.gpGraph, gpCv.gpDefLookupCallable(),
			gpWorld, gpCv.gpViewZoom, _gpWantTypes(gpE))
		_gpPendingRef = _gpRefFromSnap(gpSnap)
		_gpGrip["pos"] = gpSnap.get("pos", gpWorld)
		gpCv.queue_redraw()


# Finish the drag: commit one undo step. A vertex drag rewinds the live-mutated routing and
# re-applies it through the command; an end drag reconnects the pending ref.
# 结束拖拽：提交一个撤销步。顶点拖拽把实时改写的路由回退、再经命令重新施加；端点拖拽改接待提交引用。
func gpEndGripDrag() -> void:
	if _gpGrip.is_empty():
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(_gpEdgeId)
	if gpE != null:
		var gpKind: String = _gpGrip.get("kind", "")
		if gpKind == GP_KIND_VERTEX:
			# Rewind the live mutation, then re-apply it as a command so undo restores the original.
			# 回退实时改动，再以命令重新施加，使撤销能还原到原值。
			var gpFinal: Array[Vector2] = gpE.gpRouting.duplicate()
			gpE.gpRouting = _gpOrigRouting.duplicate()
			gpCv.gpRequestSetEdgeRouting(_gpEdgeId, gpFinal)
		elif gpKind == GP_KIND_END:
			if not _gpPendingRef.is_empty():
				gpCv.gpRequestReconnectEdge(_gpEdgeId, bool(_gpGrip.get("isFrom", true)), _gpPendingRef)
	_gpGrip = {}
	_gpPendingRef = {}
	_gpOrigRouting = []
	_gpEdgeId = ""
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()


# Abandon any in-flight drag without applying anything (ESC / cancel path).
# 放弃进行中的拖拽，不应用任何改动（ESC / 取消路径）。
func gpEndDrag() -> void:
	_gpGrip = {}
	_gpPendingRef = {}
	_gpOrigRouting = []
	_gpEdgeId = ""
	gpCv.queue_redraw()


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


# Build an edge ref dict from a snap result. / 由吸附结果构造边的端点引用字典。
func _gpRefFromSnap(gpSnap: Dictionary) -> Dictionary:
	var gpKind: String = gpSnap.get("kind", "")
	if gpKind == GPSnapResolver.GP_PORT:
		return {"node_id": str(gpSnap.get("node_id", "")), "port_id": str(gpSnap.get("port_id", ""))}
	if gpKind == GPSnapResolver.GP_NODE:
		return {"node_id": str(gpSnap.get("node_id", "")), "port_id": ""}
	# GP_GRID (dangling): store the world point. / 网格（悬空）：存世界坐标。
	var gpPos: Vector2 = gpSnap.get("pos", Vector2.ZERO)
	return {"node_id": "", "port_id": "", "point": [gpPos.x, gpPos.y]}


# Paint the grips for the selected edge (and the end-drag preview). Called from the select
# tool's overlay hook, which only runs in SELECT mode.
# 为选中边绘制抓取点（及端点拖拽预览）。由选择工具的覆盖层钩子调用，仅在选择模式运行。
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
	# Endpoints + routing vertices as squares. / 端点 + 路由拐点画方块。
	for gpP in gpPts:
		var gpRect: Rect2 = Rect2(gpItem.gpScreenFromWorld(gpP) - Vector2(gpGs * 0.5, gpGs * 0.5), Vector2(gpGs, gpGs))
		gpItem.draw_rect(gpRect, Color(1.0, 1.0, 1.0), true)
		gpItem.draw_rect(gpRect, GP_COL_VERTEX, false, 1.5)
	# Insert grips as small triangles at segment midpoints. / 段中点插入抓取点画小三角。
	for gpS in range(gpPts.size() - 1):
		var gpMid: Vector2 = (gpPts[gpS] + gpPts[gpS + 1]) * 0.5
		var gpMs: Vector2 = gpItem.gpScreenFromWorld(gpMid)
		var gpTri: PackedVector2Array = PackedVector2Array([
			gpMs + Vector2(0.0, -gpGs * 0.6),
			gpMs + Vector2(gpGs * 0.6, gpGs * 0.5),
			gpMs + Vector2(-gpGs * 0.6, gpGs * 0.5),
		])
		gpItem.draw_colored_polygon(gpTri, GP_COL_INSERT)
	# End-drag preview: a rubber line from the fixed end to the snapped cursor.
	# 端点拖拽预览：从固定端到吸附光标的橡皮筋。
	if gpIsDragging() and _gpGrip.get("kind", "") == GP_KIND_END:
		var gpFixed: Vector2 = gpPts[gpPts.size() - 1] if bool(_gpGrip.get("isFrom", true)) else gpPts[0]
		var gpTo: Vector2 = _gpGrip.get("pos", gpFixed)
		gpItem.draw_line(gpItem.gpScreenFromWorld(gpFixed), gpItem.gpScreenFromWorld(gpTo),
			Color(0.45, 0.75, 1.0, 0.8), 1.5)
