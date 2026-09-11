class_name GPEdgeAutoRoute
extends RefCounted
# Copyright © 2026 Jonson Wang
# Obstacle-avoiding ORTHOGONAL routing on a Hanan grid (A* with a turn penalty).
# 基于 Hanan 网格的「避障正交布线」（带拐弯惩罚的 A*）。
#
# Why a Hanan grid and not a uniform raster / 为何用 Hanan 网格而非均匀栅格：
#   An optimal orthogonal route only ever turns on a line that touches an obstacle edge. Building
#   the candidate coordinates from the obstacle envelopes (plus the two endpoints) yields a grid
#   of a few thousand cells instead of millions, so A* finishes instantly AND the result is still
#   an optimal orthogonal path in that graph.
#   最优正交路径只会在「贴着障碍物边」的直线上拐弯。用障碍物包络（加两个端点）构造候选坐标，
#   网格只有几千格而非几百万，A* 瞬时完成，结果仍是该图上的最优正交路径。
#
# Why A* state carries a direction / 为何 A* 状态要带方向：
#   Cost depends on whether the move is a TURN, which is a property of the previous move, not of
#   the cell. Encoding orientation in the state is what makes the turn penalty correct.
#   代价取决于这一步是否为「拐弯」，而那是「上一步」的属性而非格子的属性。把朝向编进状态，
#   拐弯惩罚才正确。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Clearance kept between a routed line and any symbol envelope (world units).
# 布线与任意图元包络之间保留的间隙（世界单位）。
const GP_MARGIN: float = 12.0

# Cost of one 90-degree turn. Tuned against a typical leg length so the router prefers one long
# detour over a zig-zag of the same total length.
# 一次 90° 拐弯的代价。相对典型段长调校，使布线器宁可绕一段长路，也不走等长的锯齿。
const GP_TURN_COST: float = 60.0

# Cost of running collinear on top of an EXISTING line. Large enough to be avoided whenever any
# alternative exists, soft enough that a hopeless sheet still gets a path instead of nothing.
# 与「已有连线」共线重叠的代价。大到只要有替代就必被避开，又软到在走投无路时仍能给出路径。
const GP_OVERLAP_COST: float = 600.0

# Coordinate dedupe / intersection tolerance (world units).
# 坐标去重 / 相交容差（世界单位）。
const GP_EPS: float = 0.5

# Safety cap on grid cells; above it the exact search is abandoned for the cheap L/Z/U router.
# 网格格数上限；超过则放弃精确搜索，改用廉价的 L/Z/U 布线。
const GP_MAX_CELLS: int = 60000


# ============================ 公开接口 ============================

# World-space envelopes of every node, EXCLUDING the given ids. The caller excludes the two
# endpoint nodes: a pipe must be allowed to touch the very symbols it connects.
# 每个节点的世界坐标包络，排除给定 id。调用方排除两个端点节点：管线必须被允许接触它所连接的图元。
static func gpObstacles(gpGraph: GPPIDGraph, gpDefLookup: Callable,
		gpSkipIds: Array[String] = []) -> Array[Rect2]:
	var gpOut: Array[Rect2] = []
	if gpGraph == null:
		return gpOut
	for gpN in gpGraph.gpNodes:
		if gpSkipIds.has(gpN.gpInstanceId):
			continue
		var gpDef: GPSymbolDef = null
		if gpDefLookup.is_valid():
			gpDef = gpDefLookup.call(gpN.gpSymbolId) as GPSymbolDef
		var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
		gpOut.append(Rect2(gpN.gpPosition - gpSz / 2.0, gpSz))
	return gpOut


# Route one edge orthogonally, avoiding every obstacle and (where possible) every existing line.
# 正交布一条边，绕开所有障碍物，并尽可能避开所有已有连线。
# [param gpFrom]  resolved source end {"pos","dir","bound"} / 已解析起点
# [param gpTo]    resolved target end / 已解析终点
# [param gpObstacles] raw symbol envelopes to avoid (NOT yet inflated) / 待避开的图元包络（尚未外扩）
# [param gpExisting] polylines already on the sheet, penalised when collinear / 图纸上已有的折线，共线时被惩罚
# [param gpMargin] clearance added around each obstacle / 每个障碍物外扩的间隙
# [return] the full polyline INCLUDING both endpoints / 含两端的完整折线
static func gpRouteAuto(gpFrom: Dictionary, gpTo: Dictionary, gpObstacles: Array[Rect2],
		gpExisting: Array[PackedVector2Array] = [], gpMargin: float = GP_MARGIN) -> PackedVector2Array:
	var gpA: Vector2 = gpFrom.get("pos", Vector2.ZERO)
	var gpB: Vector2 = gpTo.get("pos", Vector2.ZERO)
	var gpBoundA: bool = bool(gpFrom.get("bound", true))
	var gpBoundB: bool = bool(gpTo.get("bound", true))
	# Axis-snapped exit normals: the first and last leg must leave along the port, exactly like
	# the manual router does, or the pipe would clip its own symbol.
	# 吸附到主轴的出线法线：首末段必须沿端口方向离开 —— 与手动布线完全一致，否则管线会切进自身图元。
	var gpDa: Vector2 = GPEdgeRoute.gpAxisDir(gpFrom.get("dir", Vector2.ZERO), gpB - gpA)
	var gpDb: Vector2 = GPEdgeRoute.gpAxisDir(gpTo.get("dir", Vector2.ZERO), gpA - gpB)
	var gpStubA: float = GPEdgeRoute.GP_STUB if gpBoundA else 0.0
	var gpStubB: float = GPEdgeRoute.GP_STUB if gpBoundB else 0.0
	var gpSa: Vector2 = gpA + gpDa * gpStubA
	var gpSb: Vector2 = gpB + gpDb * gpStubB
	# A free end has no port to leave from, so it gets no stub and no direction constraint.
	# 悬空端无端口可出，故无引出段、也无方向约束。
	if gpSa.distance_to(gpSb) <= GP_EPS:
		return GPEdgeRoute.gpClean([gpA, gpB])

	var gpBlockers: Array[Rect2] = []
	for gpR in gpObstacles:
		gpBlockers.append(gpR.grow(gpMargin))

	var gpXs: Array[float] = [gpSa.x, gpSb.x]
	var gpYs: Array[float] = [gpSa.y, gpSb.y]
	for gpR in gpObstacles:
		gpXs.append(gpR.position.x - gpMargin)
		gpXs.append(gpR.position.x + gpR.size.x + gpMargin)
		gpYs.append(gpR.position.y - gpMargin)
		gpYs.append(gpR.position.y + gpR.size.y + gpMargin)
	_gpDedupe(gpXs)
	_gpDedupe(gpYs)
	var gpNx: int = gpXs.size()
	var gpNy: int = gpYs.size()
	# Degenerate or oversized sheet: the exact search is not worth its cost.
	# 退化或过大的图纸：精确搜索不值当。
	if gpNx < 2 or gpNy < 2 or gpNx * gpNy > GP_MAX_CELLS:
		return GPEdgeRoute.gpOrthoPath(gpA, gpDa, gpB, gpDb, gpStubA, gpStubB)

	var gpSx: int = _gpIndexOf(gpXs, gpSa.x)
	var gpSy: int = _gpIndexOf(gpYs, gpSa.y)
	var gpGx: int = _gpIndexOf(gpXs, gpSb.x)
	var gpGy: int = _gpIndexOf(gpYs, gpSb.y)
	if gpSx < 0 or gpSy < 0 or gpGx < 0 or gpGy < 0:
		return GPEdgeRoute.gpOrthoPath(gpA, gpDa, gpB, gpDb, gpStubA, gpStubB)

	var gpPath: Array[Vector2] = _gpSearch(gpXs, gpYs, gpBlockers, gpExisting,
		Vector2i(gpSx, gpSy), Vector2i(gpGx, gpGy), gpDa, gpDb)
	if gpPath.is_empty():
		return GPEdgeRoute.gpOrthoPath(gpA, gpDa, gpB, gpDb, gpStubA, gpStubB)

	var gpOut: Array[Vector2] = [gpA]
	for gpP in gpPath:
		gpOut.append(gpP)
	gpOut.append(gpB)
	return GPEdgeRoute.gpClean(gpOut)


# ============================ A* ============================

# A* over (cell x, cell y, orientation). Returns the cell waypoints from start to goal, or an
# empty array when no route exists.
# 在（格 x, 格 y, 朝向）上的 A*。返回从起点到终点的格子途经点；无路径时返回空数组。
static func _gpSearch(gpXs: Array[float], gpYs: Array[float], gpBlockers: Array[Rect2],
		gpExisting: Array[PackedVector2Array], gpStart: Vector2i, gpGoal: Vector2i,
		gpDa: Vector2, gpDb: Vector2) -> Array[Vector2]:
	var gpNx: int = gpXs.size()
	var gpNy: int = gpYs.size()
	var gpStartDir: int = 0 if absf(gpDa.x) >= absf(gpDa.y) else 1
	var gpStartId: int = _gpStateId(gpStart.x, gpStart.y, gpStartDir, gpNx)
	var gpGScore: Dictionary = {gpStartId: 0.0}
	var gpCame: Dictionary = {}
	var gpClosed: Dictionary = {}
	var gpPrio: Array[float] = []
	var gpHeap: Array[int] = []
	_gpHeapPush(gpPrio, gpHeap, _gpHeuristic(gpXs, gpYs, gpStart, gpGoal), gpStartId)

	var gpGoalId: int = -1
	var gpGuard: int = 0
	var gpMaxSteps: int = gpNx * gpNy * 4 + 64
	while not gpPrio.is_empty() and gpGuard < gpMaxSteps:
		gpGuard += 1
		var gpCur: int = _gpHeapPop(gpPrio, gpHeap)
		if gpClosed.has(gpCur):
			continue
		gpClosed[gpCur] = true
		var gpCx: int = _gpStateX(gpCur, gpNx)
		var gpCy: int = _gpStateY(gpCur, gpNx)
		if gpCx == gpGoal.x and gpCy == gpGoal.y:
			gpGoalId = gpCur
			break
		var gpDir: int = gpCur % 2
		var gpG: float = float(gpGScore[gpCur])
		# Four neighbours: two horizontal (dir 0), two vertical (dir 1).
		# 四个邻居：两个水平（dir 0）、两个垂直（dir 1）。
		for gpK in range(4):
			var gpNewDir: int = 0 if gpK < 2 else 1
			var gpNx2: int = gpCx + (1 if gpK == 0 else (-1 if gpK == 1 else 0))
			var gpNy2: int = gpCy + (1 if gpK == 2 else (-1 if gpK == 3 else 0))
			if gpNx2 < 0 or gpNx2 >= gpNx or gpNy2 < 0 or gpNy2 >= gpNy:
				continue
			var gpP: Vector2 = Vector2(gpXs[gpCx], gpYs[gpCy])
			var gpQ: Vector2 = Vector2(gpXs[gpNx2], gpYs[gpNy2])
			if _gpBlocked(gpP, gpQ, gpBlockers):
				continue
			var gpMove: Vector2 = (gpQ - gpP).normalized()
			# Never fold the first leg back over its own symbol.
			# 绝不让首段折返、压回自己的图元上。
			if gpCx == gpStart.x and gpCy == gpStart.y and gpMove.dot(gpDa) < -0.001:
				continue
			# ...and never approach the target from its far side.
			# ……也绝不从目标的远侧绕进去。
			if gpNx2 == gpGoal.x and gpNy2 == gpGoal.y and gpMove.dot(gpDb) > 0.001:
				continue
			var gpStep: float = gpP.distance_to(gpQ)
			var gpCost: float = gpG + gpStep
			if gpNewDir != gpDir:
				gpCost += GP_TURN_COST
			if _gpOverlaps(gpP, gpQ, gpExisting):
				gpCost += GP_OVERLAP_COST
			var gpNid: int = _gpStateId(gpNx2, gpNy2, gpNewDir, gpNx)
			if gpClosed.has(gpNid):
				continue
			if gpGScore.has(gpNid) and float(gpGScore[gpNid]) <= gpCost:
				continue
			gpGScore[gpNid] = gpCost
			gpCame[gpNid] = gpCur
			_gpHeapPush(gpPrio, gpHeap, gpCost + _gpHeuristic(gpXs, gpYs,
				Vector2i(gpNx2, gpNy2), gpGoal), gpNid)

	if gpGoalId < 0:
		return []
	var gpOut: Array[Vector2] = []
	var gpWalk: int = gpGoalId
	var gpGuardBack: int = 0
	while gpGuardBack <= gpMaxSteps:
		gpGuardBack += 1
		gpOut.append(Vector2(gpXs[_gpStateX(gpWalk, gpNx)], gpYs[_gpStateY(gpWalk, gpNx)]))
		if gpWalk == gpStartId:
			break
		if not gpCame.has(gpWalk):
			return []
		gpWalk = int(gpCame[gpWalk])
	gpOut.reverse()
	return gpOut


# ============================ 几何判定 ============================

# Does an axis-aligned segment cut through the interior of any blocker?
# 轴对齐线段是否切进了任一障碍物的内部？
static func _gpBlocked(gpA: Vector2, gpB: Vector2, gpBlockers: Array[Rect2]) -> bool:
	var gpLoX: float = minf(gpA.x, gpB.x)
	var gpHiX: float = maxf(gpA.x, gpB.x)
	var gpLoY: float = minf(gpA.y, gpB.y)
	var gpHiY: float = maxf(gpA.y, gpB.y)
	var gpHoriz: bool = absf(gpB.y - gpA.y) <= GP_EPS
	for gpR in gpBlockers:
		var gpRx0: float = gpR.position.x
		var gpRx1: float = gpR.position.x + gpR.size.x
		var gpRy0: float = gpR.position.y
		var gpRy1: float = gpR.position.y + gpR.size.y
		if gpHoriz:
			# A horizontal run only clashes when it is strictly between the rect's top and bottom.
			# 水平段只有严格夹在矩形上下边之间时才冲突。
			if gpA.y <= gpRy0 + GP_EPS or gpA.y >= gpRy1 - GP_EPS:
				continue
			if minf(gpHiX, gpRx1) - maxf(gpLoX, gpRx0) > GP_EPS:
				return true
		else:
			if gpA.x <= gpRx0 + GP_EPS or gpA.x >= gpRx1 - GP_EPS:
				continue
			if minf(gpHiY, gpRy1) - maxf(gpLoY, gpRy0) > GP_EPS:
				return true
	return false


# Length of the collinear overlap between two axis-aligned segments (0 when not collinear).
# 两条轴对齐线段共线重叠的长度（不共线时为 0）。
static func _gpOverlapLen(gpA: Vector2, gpB: Vector2, gpC: Vector2, gpD: Vector2) -> float:
	var gpH1: bool = absf(gpB.y - gpA.y) <= GP_EPS
	var gpH2: bool = absf(gpD.y - gpC.y) <= GP_EPS
	if gpH1 != gpH2:
		return 0.0
	if gpH1:
		if absf(gpA.y - gpC.y) > GP_EPS:
			return 0.0
		return minf(maxf(gpA.x, gpB.x), maxf(gpC.x, gpD.x)) - maxf(minf(gpA.x, gpB.x),
			minf(gpC.x, gpD.x))
	if absf(gpA.x - gpC.x) > GP_EPS:
		return 0.0
	return minf(maxf(gpA.y, gpB.y), maxf(gpC.y, gpD.y)) - maxf(minf(gpA.y, gpB.y),
		minf(gpC.y, gpD.y))


# Does the candidate segment run on top of any existing line?
# 候选线段是否压在任一已有连线上？
static func _gpOverlaps(gpA: Vector2, gpB: Vector2, gpExisting: Array[PackedVector2Array]) -> bool:
	for gpPts in gpExisting:
		var gpI: int = 0
		while gpI + 1 < gpPts.size():
			if _gpOverlapLen(gpA, gpB, gpPts[gpI], gpPts[gpI + 1]) > GP_EPS:
				return true
			gpI += 1
	return false


# ============================ 网格工具 ============================

static func _gpStateId(gpX: int, gpY: int, gpDir: int, gpNx: int) -> int:
	return (gpY * gpNx + gpX) * 2 + gpDir


static func _gpStateX(gpId: int, gpNx: int) -> int:
	return (gpId / 2) % gpNx


static func _gpStateY(gpId: int, gpNx: int) -> int:
	return (gpId / 2) / gpNx


# Manhattan distance to the goal: admissible because every move costs at least its length.
# 到终点的曼哈顿距离：可采纳，因为每次移动的代价至少为其长度。
static func _gpHeuristic(gpXs: Array[float], gpYs: Array[float], gpAt: Vector2i,
		gpGoal: Vector2i) -> float:
	return absf(gpXs[gpAt.x] - gpXs[gpGoal.x]) + absf(gpYs[gpAt.y] - gpYs[gpGoal.y])


# Sort in place and drop coordinates closer than GP_EPS.
# 就地排序并剔除间距小于 GP_EPS 的坐标。
static func _gpDedupe(gpArr: Array[float]) -> void:
	gpArr.sort()
	var gpI: int = gpArr.size() - 1
	while gpI > 0:
		if gpArr[gpI] - gpArr[gpI - 1] <= GP_EPS:
			gpArr.remove_at(gpI)
		gpI -= 1


static func _gpIndexOf(gpArr: Array[float], gpV: float) -> int:
	for gpI in range(gpArr.size()):
		if absf(gpArr[gpI] - gpV) <= GP_EPS:
			return gpI
	return -1


# ============================ 二叉堆 ============================

static func _gpHeapPush(gpPrio: Array, gpState: Array, gpP: float, gpS: int) -> void:
	gpPrio.append(gpP)
	gpState.append(gpS)
	var gpI: int = gpPrio.size() - 1
	while gpI > 0:
		var gpPar: int = (gpI - 1) / 2
		if gpPrio[gpPar] <= gpPrio[gpI]:
			break
		_gpSwap(gpPrio, gpState, gpPar, gpI)
		gpI = gpPar


static func _gpHeapPop(gpPrio: Array, gpState: Array) -> int:
	var gpTop: int = int(gpState[0])
	var gpLastP: float = gpPrio[gpPrio.size() - 1]
	var gpLastS: int = int(gpState[gpState.size() - 1])
	gpPrio.remove_at(gpPrio.size() - 1)
	gpState.remove_at(gpState.size() - 1)
	if gpPrio.is_empty():
		return gpTop
	gpPrio[0] = gpLastP
	gpState[0] = gpLastS
	var gpI: int = 0
	var gpN: int = gpPrio.size()
	while true:
		var gpL: int = gpI * 2 + 1
		var gpR: int = gpI * 2 + 2
		var gpM: int = gpI
		if gpL < gpN and gpPrio[gpL] < gpPrio[gpM]:
			gpM = gpL
		if gpR < gpN and gpPrio[gpR] < gpPrio[gpM]:
			gpM = gpR
		if gpM == gpI:
			break
		_gpSwap(gpPrio, gpState, gpM, gpI)
		gpI = gpM
	return gpTop


# Swap the parallel heap entries (priorities in gpA, state ids in gpB).
# 交换堆中成对的元素（gpA 存优先级，gpB 存状态 id）。
static func _gpSwap(gpA: Array, gpB: Array, gpI: int, gpJ: int) -> void:
	var gpT: float = float(gpA[gpI])
	gpA[gpI] = gpA[gpJ]
	gpA[gpJ] = gpT
	var gpU: int = int(gpB[gpI])
	gpB[gpI] = gpB[gpJ]
	gpB[gpJ] = gpU
