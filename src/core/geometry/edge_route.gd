class_name GPEdgeRoute
extends RefCounted
# Copyright © 2026 Jonson Wang
# Polyline routing for pipes and signal lines: orthogonal first, straight on demand.
# 管道与信号线的折线布线：默认正交，按需直连。
#
# Why routing is a PURE function of (end position, end normal, stored waypoints, ortho flag)
# and not stored geometry / 为何布线是「端点位置 + 端点法线 + 已存折点 + 正交开关」的纯函数而非存储几何：
#   the two endpoints are ALWAYS recomputed from the port refs every frame (see GPPortResolver),
#   so routing must be recomputed too — a cached polyline would tear the pipe off its symbol the
#   first time the symbol moves. Only the MIDDLE waypoints the user dragged are stored, and they
#   are stored as data (gpRouting), never baked into the render.
#   两个端点每帧都由端口引用重算（见 GPPortResolver），故布线也必须重算 —— 缓存折线会在图元首次
#   移动时把管线撕离图元。只有用户拖出来的「中间折点」才存储，且以数据形式存于 gpRouting，
#   绝不烘进渲染。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Length of the straight stub that leaves a port along its outward normal. Without it a pipe
# would clip the symbol's own outline the moment it turns.
# 沿端口外法线引出的直段长度。没有它，管线一拐弯就会切进图元自身的轮廓。
const GP_STUB: float = 14.0

# Lateral offset used when a route has to detour around a symbol (two ports facing the SAME way,
# or facing away from each other). Bigger than one symbol half-height on purpose.
# 需要绕开图元时的横向偏移量（两个端口同向，或彼此背对）。刻意取大于图元半高。
const GP_DETOUR: float = 26.0

# Points closer than this are the same point; legs shorter than this are dropped.
# 距离小于此值的点视作同一点；短于此值的段被丢弃。
const GP_EPS: float = 0.5


# Build the full polyline for one edge, endpoints INCLUDED.
# 构造一条边的完整折线，含两个端点。
# [param gpFrom]   resolved source end   {"pos", "dir", ...} from GPPortResolver.gpResolveEnd
# [param gpFrom]   已解析的起点端       来自 GPPortResolver.gpResolveEnd 的 {"pos", "dir", ...}
# [param gpTo]     resolved target end / 已解析的终点端
# [param gpRouting] user-dragged MIDDLE waypoints (empty = auto-route) / 用户拖出的中间折点（空 = 自动布线）
# [param gpOrtho]  false = straight line (Shift-drawn) / false = 直连（按 Shift 画出）
static func gpRoute(gpFrom: Dictionary, gpTo: Dictionary,
		gpRouting: Array[Vector2], gpOrtho: bool) -> PackedVector2Array:
	var gpA: Vector2 = gpFrom.get("pos", Vector2.ZERO)
	var gpB: Vector2 = gpTo.get("pos", Vector2.ZERO)
	# 1. The user owns the path when waypoints exist — never second-guess a dragged vertex.
	# 有折点时由用户决定路径 —— 绝不擅自改动用户拖过的顶点。
	if not gpRouting.is_empty():
		var gpUser: Array[Vector2] = [gpA]
		for gpP in gpRouting:
			gpUser.append(gpP)
		gpUser.append(gpB)
		return gpClean(gpUser)
	# 2. Straight (Shift) edges: two points, nothing to compute.
	# 直连（Shift）边：两点，无需计算。
	if not gpOrtho:
		return gpClean([gpA, gpB])
	# 3. Orthogonal auto-route driven by the two port normals.
	# 由两个端口法线驱动的正交自动布线。
	# A FREE end has no nozzle, so it gets no stub: the stored dangling point IS the end of the
	# pipe. Giving it a stub would stop the line short of the very point the user placed.
	# 悬空端没有管口，故没有引出段：用户存下的那个悬空点就是管线的端点。
	# 若也给它引出段，管线会在用户放置的那个点之前就停下。
	var gpStubA: float = GP_STUB if bool(gpFrom.get("bound", true)) else 0.0
	var gpStubB: float = GP_STUB if bool(gpTo.get("bound", true)) else 0.0
	return gpOrthoPath(gpA, gpFrom.get("dir", Vector2.ZERO), gpB,
		gpTo.get("dir", Vector2.ZERO), gpStubA, gpStubB)


# Orthogonal path between two ports: L (one corner), Z (one corner, offset ends) or U (detour).
# 两端口间的正交路径：L（一个拐点）、Z（一个拐点、两端错位）或 U（绕行）。
static func gpOrthoPath(gpA: Vector2, gpDirA: Vector2, gpB: Vector2, gpDirB: Vector2,
		gpStubA: float = GP_STUB, gpStubB: float = GP_STUB) -> PackedVector2Array:
	# Snap the normals to the dominant axis. A port that declares no normal borrows the
	# direction towards the other end, which is the least surprising guess.
	# 把法线吸附到主轴。未声明法线的端口借用「指向另一端」的方向，这是最不意外的猜测。
	var gpDa: Vector2 = gpAxisDir(gpDirA, gpB - gpA)
	var gpDb: Vector2 = gpAxisDir(gpDirB, gpA - gpB)
	var gpSa: Vector2 = gpA + gpDa * gpStubA
	var gpSb: Vector2 = gpB + gpDb * gpStubB
	var gpAHoriz: bool = gpIsHorizontal(gpDa)
	var gpBHoriz: bool = gpIsHorizontal(gpDb)

	# --- case 1: both ends on the same axis and already aligned -> one straight run ---
	# --- 情形 1：两端同轴且已对齐 -> 一条直段 ---
	# Aligned AND "walking in" is the test: same-direction normals on a collinear pair would
	# fold back over the symbol (the pipe would enter b from b's far side after crossing it).
	# 判据是「既对齐、又是走进去」：共线且法线同向会折返并压过图元（管子会穿过 b 后从其远侧进入）。
	if gpAHoriz == gpBHoriz:
		if gpAHoriz:
			if absf(gpSa.y - gpSb.y) <= GP_EPS:
				if (gpSb.x - gpSa.x) * gpDa.x > GP_EPS and (gpSb.x - gpSa.x) * -gpDb.x > GP_EPS:
					return gpClean([gpA, gpSa, gpSb, gpB])
				return gpDetour(gpA, gpSa, gpSb, gpB, true)
		elif absf(gpSa.x - gpSb.x) <= GP_EPS:
			if (gpSb.y - gpSa.y) * gpDa.y > GP_EPS and (gpSb.y - gpSa.y) * -gpDb.y > GP_EPS:
				return gpClean([gpA, gpSa, gpSb, gpB])
			return gpDetour(gpA, gpSa, gpSb, gpB, false)

	# --- case 2: one corner. Try the corner that continues the source normal first ---
	# --- 情形 2：一个拐点。优先尝试「延续起点法线」的那个拐点 ---
	# cHV: leave horizontally then turn / 先水平后垂直
	# cVH: leave vertically then turn / 先垂直后水平
	var gpCHV: Vector2 = Vector2(gpSb.x, gpSa.y)
	var gpCVH: Vector2 = Vector2(gpSa.x, gpSb.y)
	if gpAHoriz:
		# Leaving leg is horizontal: it must agree with the source normal.
		# 出线段为水平：必须与起点法线同向。
		if (gpCHV.x - gpSa.x) * gpDa.x > GP_EPS:
			return gpClean([gpA, gpSa, gpCHV, gpSb, gpB])
		# Otherwise turn immediately and come in along the target normal.
		# 否则立刻拐弯，并沿终点法线进入。
		if (gpSb.x - gpCVH.x) * -gpDb.x > GP_EPS:
			return gpClean([gpA, gpSa, gpCVH, gpSb, gpB])
		return gpDetour(gpA, gpSa, gpSb, gpB, true)
	# Leaving leg is vertical. / 出线段为垂直。
	if (gpCVH.y - gpSa.y) * gpDa.y > GP_EPS:
		return gpClean([gpA, gpSa, gpCVH, gpSb, gpB])
	if (gpSb.y - gpCHV.y) * -gpDb.y > GP_EPS:
		return gpClean([gpA, gpSa, gpCHV, gpSb, gpB])
	return gpDetour(gpA, gpSa, gpSb, gpB, false)


# Route around a symbol: out along the source normal, sideways past it, back in.
# 绕开图元：沿起点法线出，横向绕过，再进入。
# [param gpAHoriz] the source normal is horizontal (detour vertically) / 起点法线水平（纵向绕行）
static func gpDetour(gpA: Vector2, gpSa: Vector2, gpSb: Vector2, gpB: Vector2,
		gpAHoriz: bool) -> PackedVector2Array:
	if gpAHoriz:
		var gpMidY: float = (gpSa.y + gpSb.y) * 0.5
		if absf(gpSb.y - gpSa.y) < GP_DETOUR:
			gpMidY = gpSa.y + GP_DETOUR
		return gpClean([gpA, gpSa, Vector2(gpSa.x, gpMidY), Vector2(gpSb.x, gpMidY), gpSb, gpB])
	var gpMidX: float = (gpSa.x + gpSb.x) * 0.5
	if absf(gpSb.x - gpSa.x) < GP_DETOUR:
		gpMidX = gpSa.x + GP_DETOUR
	return gpClean([gpA, gpSa, Vector2(gpMidX, gpSa.y), Vector2(gpMidX, gpSb.y), gpSb, gpB])


# Snap a direction to its dominant axis; fall back to the axis of gpFallback when empty.
# 把方向吸附到其主轴；为空时回退到 gpFallback 所在轴。
static func gpAxisDir(gpDir: Vector2, gpFallback: Vector2) -> Vector2:
	if gpDir.length_squared() > 0.0001:
		if gpIsHorizontal(gpDir):
			return Vector2(signf(gpDir.x) if not is_zero_approx(gpDir.x) else 1.0, 0.0)
		return Vector2(0.0, signf(gpDir.y) if not is_zero_approx(gpDir.y) else 1.0)
	if gpFallback.length_squared() < 0.0001:
		return Vector2(1.0, 0.0)
	if gpIsHorizontal(gpFallback):
		return Vector2(signf(gpFallback.x), 0.0)
	return Vector2(0.0, signf(gpFallback.y))


# True when a direction is closer to horizontal than vertical.
# 方向更接近水平时为真。
static func gpIsHorizontal(gpD: Vector2) -> bool:
	return absf(gpD.x) >= absf(gpD.y)


# Drop duplicate and collinear middle points. Keeps the first and last point always.
# 去掉重复点与共线中间点。首尾两点始终保留。
# Why: an L-route whose corner lands on the straight line between its neighbours is really a
# straight run, and a renderer that draws a 0-length leg wastes a draw call and can render a
# visible dot cap.
# 为何：拐点落在两邻点连线上的 L 路由其实是一条直段；绘制零长段既浪费一次绘制调用，
# 也可能画出一个可见的线帽圆点。
static func gpClean(gpPts: Array[Vector2]) -> PackedVector2Array:
	var gpOut: Array[Vector2] = []
	for gpP in gpPts:
		if not gpOut.is_empty() and gpOut[-1].distance_to(gpP) <= GP_EPS:
			continue
		gpOut.append(gpP)
	if gpOut.size() < 2:
		gpOut.append(gpOut[0] if not gpOut.is_empty() else Vector2.ZERO)
	var gpI: int = 1
	while gpI < gpOut.size() - 1:
		var gpU: Vector2 = (gpOut[gpI] - gpOut[gpI - 1]).normalized()
		var gpV: Vector2 = (gpOut[gpI + 1] - gpOut[gpI]).normalized()
		# Same direction (dot > 0) means the middle point adds nothing.
		# 同向（dot > 0）意味着中间点毫无贡献。
		if absf(gpU.cross(gpV)) < 0.01 and gpU.dot(gpV) > 0.5:
			gpOut.remove_at(gpI)
		else:
			gpI += 1
	var gpRes: PackedVector2Array = PackedVector2Array()
	for gpP in gpOut:
		gpRes.append(gpP)
	return gpRes


# Every leg axis-aligned? Used by tests and by the "is this still a P&ID" sanity check.
# 每一段是否都轴对齐？供测试与「这还像不像 P&ID」的健全性检查使用。
static func gpIsOrthogonal(gpPts: PackedVector2Array) -> bool:
	for gpI in range(gpPts.size() - 1):
		var gpD: Vector2 = gpPts[gpI + 1] - gpPts[gpI]
		if minf(absf(gpD.x), absf(gpD.y)) > GP_EPS:
			return false
	return true
