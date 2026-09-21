class_name GPEdgeGripGeometry
extends RefCounted
# Copyright © 2026 Jonson Wang
# Stateless geometry helpers for edge grips: polyline ortho routing, midpoint grip
# placement, nearest-segment lookup, routing insert index, rect hit tests and the
# split-port picker. Pure functions — they hold no drag state, which is why they can
# live apart from GPEdgeGripOps (the drag state machine).
# 连线抓取点的无状态几何助手：折线正交化、中点抓取点布置、最近线段查找、routing
# 插入下标、矩形命中测试与拆分端口挑选。均为纯函数 —— 不持有任何拖拽状态，
# 故可从 GPEdgeGripOps（拖拽状态机）中独立出来。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Geometry epsilon shared with GPEdgeRoute (axis-alignment tolerance). / 与 GPEdgeRoute 共用的几何容差。
const GP_EPS: float = GPConstants.GP_EPS
# Grip kind: a segment midpoint (rigid translate). / 抓取点角色：段中点（刚体平移）。
const GP_KIND_MID: String = "mid"

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

static func gpFindNearestSegment(gpPts: PackedVector2Array, gpWorld: Vector2) -> int:
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
# (GPEdgeView.gpPolyline()) and the hit-test (GPCanvasHitTest.gpHitEdge()): GPEdgeRoute.gpRoute(). Otherwise
# the grips are computed on a raw [endA]+routing+[endB] line that only matches the visible pipe when
# there is no waypoint AND orthogonal routing is off — for every real orthogonal P&ID pipe the grips
# would land on a straight diagonal that never touches the drawn L/Z/U path, so they would be invisible.
# 构造一条边的「已解析世界折线」。必须与渲染器（GPEdgeView.gpPolyline()）和命中测试（GPCanvasHitTest.gpHitEdge()）
# 共用同一套布线例程 GPEdgeRoute.gpRoute()。否则抓取点会落在「[端A]+折点+[端B]」的裸直线上，而该直线仅在「无折点且关闭正交」
# 时才与可见管线重合 —— 对任意真实的正交 P&ID 管线，抓取点会落在一条根本碰不到可见 L/Z/U 路径的斜线上，从而不可见。

static func gpRoutingInsertIndex(gpP0: PackedVector2Array, gpR0: Array[Vector2], gpSeg: int) -> int:
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




# World midpoint of an edge (used to anchor the in-place tag editor). Vector2.INF when the
# edge is missing. / 一条边的世界中点（用于锚定就地位号编辑器）。边缺失时返回 Vector2.INF。

static func gpPolylineHitsRect(gpPts: PackedVector2Array, gpRect: Rect2) -> bool:
	if gpPts.size() < 2:
		return false
	var gpC: Array[Vector2] = [
		gpRect.position,
		Vector2(gpRect.end.x, gpRect.position.y),
		gpRect.end,
		Vector2(gpRect.position.x, gpRect.end.y),
	]
	for gpI in range(gpPts.size() - 1):
		var gpA: Vector2 = gpPts[gpI]
		var gpB: Vector2 = gpPts[gpI + 1]
		if gpRect.has_point(gpA) or gpRect.has_point(gpB):
			return true
		for gpJ in range(4):
			var gpD: Vector2 = gpC[gpJ]
			var gpE: Vector2 = gpC[(gpJ + 1) % 4]
			if Geometry2D.segment_intersects_segment(gpA, gpB, gpD, gpE) != null:
				return true
	return false


# Id of the first edge running under gpNode, or "" when none does. Measures the ROUTED polyline
# (what is actually drawn) against the SAME node-rect helper the hit-test uses, so detection can
# never drift from what the user sees. / 从 gpNode 下方穿过的第一条边的 id，无则 ""。以「实际绘制的
# 已布线折线」对「命中测试所用的同一节点矩形助手」度量，故检测永不会与用户所见失步。

static func gpPickSplitPorts(gpSym: GPPIDNode, gpDef: GPSymbolDef, gpA: Vector2, gpB: Vector2) -> Dictionary:
	var gpBestIn: String = ""
	var gpBestOut: String = ""
	var gpBestScore: float = INF
	for gpI in range(gpDef.gpPorts.size()):
		var gpPI: GPPort = gpDef.gpPorts[gpI]
 # Reuse the renderer's own transform order (mirror first, then rotate) — never re-derive it,
 # or a flipped-and-rotated symbol's ports would land on the wrong side.
 # 复用渲染器自身的变换顺序（先镜像、再旋转）——绝不另行推导，否则「翻转+旋转」图元的端口会跑错侧。
		var gpWA: Vector2 = gpSym.gpPosition + GPPortResolver.gpPortLocalOriented(gpDef, gpSym, gpPI)
		var gpDi: float = gpWA.distance_to(gpA)
		for gpJ in range(gpDef.gpPorts.size()):
			if gpJ == gpI:
				continue
			var gpPJ: GPPort = gpDef.gpPorts[gpJ]
			var gpWB: Vector2 = gpSym.gpPosition + GPPortResolver.gpPortLocalOriented(gpDef, gpSym, gpPJ)
			var gpScore: float = gpDi + gpWB.distance_to(gpB)
			if gpScore < gpBestScore:
				gpBestScore = gpScore
				gpBestIn = gpPI.gpName
				gpBestOut = gpPJ.gpName
	if gpBestIn == "":
 # Unreachable: caller guarantees >=2 ports. / 不可达：调用方已保证 >=2 端口。
		gpBestIn = gpDef.gpPorts[0].gpName
		gpBestOut = gpDef.gpPorts[1].gpName
	return {"in": gpBestIn, "out": gpBestOut}


# Resolved world polyline of an edge — static twin of GPEdgeGripOps._gpPolyline(), used by the
# stateless queries above so they need no instance. Same want-type as the renderer, so any
# geometry derived from it lines up with what the user actually sees.
# 一条边的已解析世界折线 —— GPEdgeGripOps._gpPolyline() 的 static 对等物，供上方无状态查询使用，
# 使其无需实例。使用与渲染器相同的「期望端口用途」，故由其推导的几何与用户所见一致。
static func gpPolyline(gpCv: GPCanvas2D, gpE: GPPIDEdge) -> PackedVector2Array:
	var gpDefs: Callable = gpCv.gpDefLookupCallable()
	var gpWant: String = GPPortResolver.gpWantTypeFor(gpE)
	var gpA: Dictionary = GPPortResolver.gpResolveEnd(gpCv.gpGraph, gpDefs, gpE, true, gpWant)
	var gpB: Dictionary = GPPortResolver.gpResolveEnd(gpCv.gpGraph, gpDefs, gpE, false, gpWant)
	return GPEdgeRoute.gpRoute(gpA, gpB, gpE.gpRouting, gpE.gpOrtho)


static func gpEdgeUnderNode(gpCv: GPCanvas2D,gpNode: GPPIDNode) -> String:
	if gpNode == null or gpCv.gpGraph == null:
		return ""
	var gpRect: Rect2 = GPCanvasHitTest.gpNodeRect(gpCv.gpGraph, gpCv.gpBinder, gpNode.gpInstanceId)
	if gpRect == Rect2():
		return ""
	for gpE in gpCv.gpGraph.gpEdges:
		if GPEdgeGripGeometry.gpPolylineHitsRect(gpPolyline(gpCv, gpE), gpRect):
			return gpE.gpInstanceId
	return ""


# All edge ids running under gpNode (possibly empty). Same detection as gpEdgeUnderNode() but returns
# EVERY edge, not just the first — used when a symbol is MOVED so each line it now covers can be
# offered its own reroute/split choice.
# 从 gpNode 下方穿过的全部边 id（可能为空）。检测同 gpEdgeUnderNode()，但返回所有边而非第一条
# —— 用于「移动」图元时，使其此刻压到的每条线都能被提出各自的选择。

static func gpEdgesUnderNode(gpCv: GPCanvas2D,gpNode: GPPIDNode) -> Array[String]:
	if gpNode == null or gpCv.gpGraph == null:
		return []
	var gpRect: Rect2 = GPCanvasHitTest.gpNodeRect(gpCv.gpGraph, gpCv.gpBinder, gpNode.gpInstanceId)
	if gpRect == Rect2():
		return []
	var gpHits: Array[String] = []
	for gpE in gpCv.gpGraph.gpEdges:
		if GPEdgeGripGeometry.gpPolylineHitsRect(gpPolyline(gpCv, gpE), gpRect):
			gpHits.append(gpE.gpInstanceId)
	return gpHits


# ① Reroute the edge AROUND the newly placed symbol. Both ends keep their port refs — only the
# intermediate waypoints are recomputed, treating the new symbol as an obstacle.
# ① 重布该边以「绕过」新放置的图元。两端保留端口引用 —— 只重算中间折点，把新图元当作障碍。
#
# Best effort / 尽力而为：when nothing can go around, GPEdgeAutoRoute falls back to a near-straight
# path that may still graze the symbol. Expected — deliberately not special-cased.
# 实在绕不开时 GPEdgeAutoRoute 会退回近似直连、仍可能擦到图元。属预期，刻意不做特判。

static func gpRerouteAround(gpCv: GPCanvas2D,gpEdgeId: String, gpSymNid: String) -> void:
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	# Snapshot the pre-drop routing BEFORE rerouting, so deleting the symbol can restore it.
	# 重布之前先快照「落点前」走线，使删除图元时可还原。
	var gpOrigRouting: Array[Vector2] = gpE.gpRouting.duplicate()
	var gpLookup: Callable = gpCv.gpDefLookupCallable()
	var gpWant: String = GPPortResolver.gpWantTypeFor(gpE)
	var gpA: Dictionary = GPPortResolver.gpResolveEnd(gpCv.gpGraph, gpLookup, gpE, true, gpWant)
	var gpB: Dictionary = GPPortResolver.gpResolveEnd(gpCv.gpGraph, gpLookup, gpE, false, gpWant)
	# Skip ONLY the two original endpoint nodes: a pipe must be allowed to touch what it connects to.
	# The new symbol is deliberately NOT skipped -> it becomes the very obstacle routed around.
	# 仅排除「原边两端」节点：管线必须被允许接触它所连接的图元。刻意**不**排除新图元
	# —— 它正是要绕开的那个障碍。
	var gpSkip: Array[String] = [str(gpE.gpFromRef.get("node_id", "")), str(gpE.gpToRef.get("node_id", ""))]
	var gpObs: Array[Rect2] = GPEdgeAutoRoute.gpObstacles(gpCv.gpGraph, gpLookup, gpSkip)
	# Exclude this edge's own old polyline, or it would push the new route off its own previous path.
	# 排除本边的旧折线，否则它会把新路径从自己原先的走向上推开。
	var gpExisting: Array[PackedVector2Array] = gpCv.gpBinder.gpExistingPolylines(gpEdgeId)
	var gpPath: PackedVector2Array = GPEdgeAutoRoute.gpRouteAuto(gpA, gpB, gpObs, gpExisting)
	# Keep only INTERMEDIATE waypoints: both ends are always resolved live from their port refs and
	# are never stored in edge.gpRouting. / 只保留中间折点：两端始终由端口引用实时解析，从不存入 routing。
	var gpMid: Array[Vector2] = []
	for gpI in range(1, gpPath.size() - 1):
		gpMid.append(gpPath[gpI])
	gpCv.gpRequestSetEdgeRouting(gpEdgeId, gpMid)
	# Record the pre-drop line so deleting the symbol restores it (Feature 2).
	# 记录落点前的连线，使删除图元时可还原（功能 2）。
	gpCv.gpRequestRecordDrop(gpSymNid, {
		"kind": "reroute",
		"edge_id": gpEdgeId,
		"orig_routing": gpOrigRouting,
	})
	gpCv.queue_redraw()


# ② Split the edge into two through the symbol. Returns false when the symbol has <2 ports, so the
# caller can prompt for editing the symbol. With >=2 ports it auto-picks the best-fitting pair; when
# there are MORE than two, the user can afterwards drag an endpoint onto another port with the
# ordinary reconnect command — no extra interaction surface needed.
# ② 把边拆成两根、经图元连接。端口 <2 时返回 false，供调用方提示修改图元。>=2 端口时自动挑选最贴合的
# 一对；端口多于两个时，用户随后可用普通重连命令把端点拖到其它端口 —— 无需额外交互面。

static func gpSplitThroughSymbol(gpCv: GPCanvas2D,gpEdgeId: String, gpSymNid: String) -> bool:
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	var gpSym: GPPIDNode = gpCv.gpGraph.gpGetNode(gpSymNid)
	if gpE == null or gpSym == null:
		return false
	# Snapshot the original edge (id + ends + routing + kind + tag) and its z-index BEFORE it is
	# deleted, so deleting the symbol can rebuild it as one continuous line (Feature 2).
	# 在原边被删之前先快照（id + 两端 + 走线 + 类型 + 位号）及其层序，
	# 使删除图元时可重建为一条连续连线（功能 2）。
	var gpOrig: Dictionary = gpE.gpToDict()
	var gpOrigIndex: int = gpCv.gpGraph.gpEdges.find(gpE)
	var gpDef: GPSymbolDef = gpCv.gpDefFor(gpSym.gpSymbolId)
	if gpDef == null or gpDef.gpPorts.size() < 2:
		return false
	# Original endpoints A (start) / B (end) drive the port pick. / 原边起点 A / 终点 B 决定端口挑选。
	var gpLookup: Callable = gpCv.gpDefLookupCallable()
	var gpWant: String = GPPortResolver.gpWantTypeFor(gpE)
	var gpA: Vector2 = GPPortResolver.gpResolveEnd(gpCv.gpGraph, gpLookup, gpE, true, gpWant).get("pos", gpSym.gpPosition)
	var gpB: Vector2 = GPPortResolver.gpResolveEnd(gpCv.gpGraph, gpLookup, gpE, false, gpWant).get("pos", gpSym.gpPosition)
	var gpPick: Dictionary = GPEdgeGripGeometry.gpPickSplitPorts(gpSym, gpDef, gpA, gpB)
	var gpIn: String = str(gpPick.get("in", ""))
	var gpOut: String = str(gpPick.get("out", ""))
	if gpIn == "" or gpOut == "":
		return false
	var gpFromRef: Dictionary = gpE.gpFromRef.duplicate()
	var gpToRef: Dictionary = gpE.gpToRef.duplicate()
	var gpKind: String = gpE.gpKind
	# Three commands (add E1, add E2, delete original) -> undo takes three steps. Known trade-off;
	# a composite command could collapse them later. / 三条命令（加 E1、加 E2、删原边）→ 撤销 3 步。
	# 已知权衡；日后可用复合命令合并。
	gpCv.gpRequestConnectEdge(gpFromRef, {"node_id": gpSymNid, "port_id": gpIn}, gpKind)
	gpCv.gpRequestConnectEdge({"node_id": gpSymNid, "port_id": gpOut}, gpToRef, gpKind)
	gpCv.gpRequestDeleteEdges([gpEdgeId])
	# Record the pre-split line so deleting the symbol restores the original single edge (Feature 2).
	# 记录拆分前的连线，使删除图元时还原为原本的单一连线（功能 2）。
	gpCv.gpRequestRecordDrop(gpSymNid, {
		"kind": "split",
		"orig": gpOrig,
		"orig_index": gpOrigIndex,
	})
	return true
