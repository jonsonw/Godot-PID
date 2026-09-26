class_name GPEdgeBumpAnchors
extends RefCounted
# Copyright © 2026 Jonson Wang
# The persistent ORANGE CORNER anchors of edges: which edges own which corners, which one is
# selected, and the create / hit-test / delete operations on them.
# 各边持久的**橙色角点锚点**：哪些边拥有哪些角点、当前选中哪一个，以及其创建 / 命中 / 删除操作。
#
# It owns NO drag state. A drag in flight (which corner is being moved right now) belongs to
# GPEdgeGripOps; this class only answers "where are the corners" and "change the corner set".
# That split is what keeps the two halves independently testable.
# 本类**不持有任何拖拽状态**。「当前正在移动哪个角点」属于 GPEdgeGripOps；本类只回答
# 「角点在哪里」与「增删角点集合」。正是这一划分使两半各自可独立测试。
#
# Index model / 索引模型:
# An anchor is the ROUTING-VERTEX INDEX of its corner (Array[int] per edge id), never a world
# coordinate — so the corner always rides the line when the edge moves, and can never float off.
# 锚点存的是角点所在 routing 顶点的**下标**（每边一个 Array[int]），而非世界坐标 ——
# 故边移动时角点恒在线上，绝不孤悬。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Grip kind: an orange corner anchor. / 抓取点角色：橙色角点锚点。
const GP_KIND_BUMP: String = "bump"

# Perpendicular offset (world units) applied to a freshly created corner so it is a REAL
# (non-collinear) vertex. Without it gpRoute() would fold a collinear waypoint away.
# 新建角点沿垂直方向偏移的世界单位量，使其成为「真实」（非共线）顶点。
# 若不偏移，gpRoute() 会把共线折点折叠掉，角点便不可见。
const GP_CORNER_OFFSET: float = 18.0

# The canvas we edit on. / 被编辑的画布。
var gpCv: GPCanvas2D

# edge id -> Array[int] of ROUTING-VERTEX INDICES. / 边 id -> routing 顶点下标数组。
var _gpAnchors: Dictionary = {}

# Currently-selected corner anchor: {"eid": String, "ai": int}; empty = none.
# 当前选中的角点锚点：{"eid", "ai"}；空 = 无。
var _gpSelected: Dictionary = {}


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# The anchor indices of an edge (may be empty). The caller must not mutate the returned array.
# 一条边的锚点下标（可为空）。调用方不得修改返回的数组。
func gpAnchorsFor(gpEdgeId: String) -> Array:
	return _gpAnchors.get(gpEdgeId, [])


# Replace the whole anchor list of an edge. Exists for two callers: tests that pre-seed corners
# to bypass geometry, and a future "load anchors from the archive" path.
# 整体替换一条边的锚点表。有两个调用方：预置角点以绕过几何的测试，
# 以及将来「从存档恢复锚点」的路径。
func gpSetAnchors(gpEdgeId: String, gpList: Array) -> void:
	_gpAnchors[gpEdgeId] = gpList.duplicate()


# Mark a corner anchor as selected (ai = array index into gpAnchorsFor(eid)).
# 标记某角点锚点为选中（ai = gpAnchorsFor(eid) 的数组下标）。
func gpSelectBump(gpEdgeId: String, gpAi: int) -> void:
	_gpSelected = {"eid": gpEdgeId, "ai": gpAi}


# The selected corner anchor, or an empty dict when none. / 选中的角点锚点；无则返回空字典。
func gpSelectedBump() -> Dictionary:
	return _gpSelected


# Drop the corner selection (called when the user clicks elsewhere). / 清除角点选择（点别处时调用）。
func gpClearBumpSelection() -> void:
	_gpSelected = {}


# Return the orange corner anchor under the world point for the given edge, or an empty dict.
# "anchor" is the ARRAY index into gpAnchorsFor(gpEdgeId) (used for deletion); the position IS the
# routing vertex at that index, so it is always on the line.
# 返回世界点下该边的橙色角点，未命中返回空字典。"anchor" 是 gpAnchorsFor(gpEdgeId) 的数组下标
# （供删除用）；位置即该下标处的 routing 顶点，恒在线上。
func gpHitBump(gpWorld: Vector2, gpEdgeId: String) -> Dictionary:
	if not _gpAnchors.has(gpEdgeId):
		return {}
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return {}
	var gpTol: float = 9.0 / gpCv.gpViewZoom
	var gpList: Array = _gpAnchors[gpEdgeId]
	for gpAi in range(gpList.size()):
		var gpRIdx: int = int(gpList[gpAi])
		if gpRIdx < 0 or gpRIdx >= gpE.gpRouting.size():
			continue
		var gpPos: Vector2 = gpE.gpRouting[gpRIdx]
		if gpWorld.distance_to(gpPos) <= gpTol:
			return {"kind": GP_KIND_BUMP, "pos": gpPos, "anchor": gpAi}
	return {}


# The orange corner anchors of an edge (for drawing). Each is a SINGLE routing vertex, so its
# position IS that vertex — always on the line, never floating off.
# 一条边的橙色角点（绘制用）。每个角点是「单个 routing 顶点」，故其位置即该顶点本身 ——
# 恒在线上、绝不脱离。
func gpBumpGrips(gpEdgeId: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if not _gpAnchors.has(gpEdgeId):
		return gpOut
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return gpOut
	for gpRIdx in _gpAnchors[gpEdgeId]:
		var gpI: int = int(gpRIdx)
		if gpI >= 0 and gpI < gpE.gpRouting.size():
			gpOut.append({"kind": GP_KIND_BUMP, "pos": gpE.gpRouting[gpI]})
	return gpOut


# Compute a NEW corner at gpWorld for the given edge and register its anchor. Returns:
#   {"ok": false}                       — no edge / no segment to insert into
#   {"ok": true, "insert", "corner", "anchor", "routing", "orig_routing"}
# "insert" is the routing index of the fresh vertex; "anchor" is its ARRAY index in the anchor
# list; "routing" already contains it; "orig_routing" is the PRE-insert snapshot.
# 在 gpWorld 处为给定边计算一个**新角点**并登记其锚点。返回：
#   {"ok": false}                       —— 无边 / 无可插入线段
#   {"ok": true, "insert", "corner", "anchor", "routing", "orig_routing"}
# "insert" 是新顶点的 routing 下标；"anchor" 是它在锚点表中的数组下标；
# "routing" 已含该顶点；"orig_routing" 是插入**前**的快照。
#
# This is the single home for "project -> offset perpendicular -> insert -> shift anchors", so
# creating a corner (gpStartBump) and pressing a bare straight line (gpStartCornerDrag) share
# one implementation instead of duplicating it.
# 「投影 -> 垂直偏移 -> 插入 -> 移位锚点」只此一处，故「创建角点」与「按下纯直线」
# 两个入口共用一份实现，不再各自重复。
func gpInsertCorner(gpEdgeId: String, gpWorld: Vector2) -> Dictionary:
	var gpFail: Dictionary = {"ok": false}
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return gpFail
	var gpPts: PackedVector2Array = GPEdgeGripGeometry.gpPolyline(gpCv, gpE)
	var gpS: int = GPEdgeGripGeometry.gpFindNearestSegment(gpPts, gpWorld)
	if gpS < 0:
		return gpFail
	var gpA: Vector2 = gpPts[gpS]
	var gpB: Vector2 = gpPts[gpS + 1]
	var gpSegDir: Vector2 = gpB - gpA
	if gpSegDir.length_squared() < 1e-6:
		return gpFail
	# Project the click onto the segment, then offset perpendicular so the new vertex is a real bend.
	# 把点击投影到线段，再沿垂直方向偏移，使新顶点成为真实拐角。
	var gpT: float = clampf(((gpWorld - gpA).dot(gpSegDir)) / maxf(gpSegDir.length_squared(), 1e-6), 0.0, 1.0)
	var gpProj: Vector2 = gpA + gpSegDir * gpT
	var gpPerp: Vector2 = Vector2(-gpSegDir.y, gpSegDir.x).normalized()
	var gpSide: float = signf((gpWorld - gpProj).dot(gpPerp))
	if gpSide == 0.0:
		gpSide = 1.0
	var gpCorner: Vector2 = gpProj + gpPerp * GP_CORNER_OFFSET * gpSide
	var gpInsert: int = GPEdgeGripGeometry.gpRoutingInsertIndex(gpPts, gpE.gpRouting, gpS)
	var gpOrig: Array[Vector2] = gpE.gpRouting.duplicate()
	var gpNew: Array[Vector2] = gpOrig.duplicate()
	gpNew.insert(gpInsert, gpCorner)
	if not _gpAnchors.has(gpEdgeId):
		_gpAnchors[gpEdgeId] = []
	# Store the routing-vertex index of the new corner; shift any EXISTING anchor whose vertex index
	# is >= gpInsert by +1 (the inserted vertex pushes later indices up by one).
	# 记下新角点的 routing 顶点下标；既有锚点的顶点下标 >= gpInsert 者整体 +1。
	var gpShifted: Array = []
	for gpOld in _gpAnchors[gpEdgeId]:
		var gpV: int = int(gpOld)
		if gpV >= gpInsert:
			gpV += 1
		gpShifted.append(gpV)
	gpShifted.append(gpInsert)
	_gpAnchors[gpEdgeId] = gpShifted
	return {"ok": true, "insert": gpInsert, "corner": gpCorner,
		"anchor": gpShifted.size() - 1, "routing": gpNew, "orig_routing": gpOrig}


# Delete one corner: remove the routing vertex, drop the anchor and shift later indices down by
# one. Returns false when there is nothing to delete. Live-applies AND commits through the
# command layer so the editor can undo it.
# 删除一个角点：移除该 routing 顶点、丢弃锚点并把后续下标整体 -1。无可删时返回 false。
# 实时应用**并**经命令层提交，使编辑器可撤销。
func gpDeleteBump(gpEdgeId: String, gpAi: int) -> bool:
	if not _gpAnchors.has(gpEdgeId):
		return false
	var gpList: Array = _gpAnchors[gpEdgeId]
	if gpAi < 0 or gpAi >= gpList.size():
		return false
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	var gpRIdx: int = int(gpList[gpAi])
	if gpRIdx < 0 or gpRIdx >= gpE.gpRouting.size():
		# Routing lost the vertex (e.g. edge re-routed) — drop the stale anchor entry only.
		# routing 已无该顶点（如边被重布）→ 仅删锚点记录。
		gpList.remove_at(gpAi)
		_gpAnchors[gpEdgeId] = gpList
		gpClearBumpSelection()
		gpCv.queue_redraw()
		return true
	# Remove the single corner vertex; later anchor indices shift down by one.
	# 删除单个角点顶点；后续锚点下标整体 -1。
	var gpNew: Array[Vector2] = gpE.gpRouting.duplicate()
	gpNew.remove_at(gpRIdx)
	gpList.remove_at(gpAi)
	for gpI in range(gpList.size()):
		if int(gpList[gpI]) > gpRIdx:
			gpList[gpI] = int(gpList[gpI]) - 1
	_gpAnchors[gpEdgeId] = gpList
	gpE.gpRouting = gpNew
	gpCv.gpRequestSetEdgeRouting(gpEdgeId, gpNew)
	gpClearBumpSelection()
	gpCv.queue_redraw()
	return true
