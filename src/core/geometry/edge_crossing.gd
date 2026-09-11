class_name GPEdgeCrossing
extends RefCounted
# Copyright © 2026 Jonson Wang
# Crossing detection + the "which line breaks" priority rules. RENDERING ONLY: the topology of
# two crossing pipes is untouched — they simply do not connect, exactly as on paper.
# 交叉检测 + 「哪条线断」的优先级规则。仅影响渲染：两条交叉管线的拓扑完全不变 ——
# 它们本就不相连，正如纸面图纸一样。
#
# The three drafting rules / 三条制图规则：
#   a. 主工艺 vs 主工艺：竖向那条断（跳线/断口），横向保持连续。
#      PROCESS vs PROCESS: the VERTICAL run breaks, the horizontal one stays continuous.
#   b. 次要管线 vs 任意主工艺管线：无论横竖，次要管线一律断。
#      UTILITY vs any PROCESS: the UTILITY line always breaks, whatever its orientation.
#   c. 信号线 vs 任意工艺管道：信号线恒断。
#      SIGNAL vs any process pipe: the SIGNAL line always breaks.
#
# All three collapse into one rule: the LOWER-priority kind breaks; on a tie the VERTICAL run
# breaks. Ranking PROCESS > UTILITY > SIGNAL makes (b) and (c) fall out automatically.
# 三条规则可归约为一条：优先级低者断；同级则竖向者断。以 PROCESS > UTILITY > SIGNAL 排序，
# (b) 与 (c) 自动成立。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Length of the visible gap (断口) centred on the crossing, in world units.
# 以交叉点为中心的可见断口长度（世界单位）。
const GP_BREAK_GAP: float = 10.0

# Intersection tolerance: endpoints shared by two lines (a tee onto one port) are NOT crossings.
# 相交容差：两条线共用的端点（同一端口上的两支）不算交叉。
const GP_EPS: float = 0.5

# Which side of a crossing breaks. / 交叉处哪一侧断开。
const GP_SIDE_A: String = "a"
const GP_SIDE_B: String = "b"


# ============================ 优先级 ============================

# Drafting priority of an edge kind. Higher wins (stays continuous).
# 连线类型的制图优先级。高者胜（保持连续）。
static func gpKindRank(gpKind: String) -> int:
	match gpKind:
		GPPIDEdge.GP_PROCESS:
			return 3
		GPPIDEdge.GP_UTILITY:
			return 2
		GPPIDEdge.GP_SIGNAL:
			return 1
		_:
			return 0


# Is this run vertical? A leg is axis-aligned by construction (GPEdgeRoute), so the test is exact.
# 这一段是竖向的吗？各段按构造即轴对齐（GPEdgeRoute），故该判定是精确的。
static func gpIsVertical(gpA: Vector2, gpB: Vector2) -> bool:
	return absf(gpB.x - gpA.x) <= GP_EPS and absf(gpB.y - gpA.y) > GP_EPS


# Decide which of two crossing lines shows the break.
# 判定交叉的两条线中哪一条显示为断线。
# [return] "a" or "b" (see GP_SIDE_*).
static func gpBreakSide(gpKindA: String, gpA1: Vector2, gpA2: Vector2, gpKindB: String,
		gpB1: Vector2, gpB2: Vector2) -> String:
	var gpRa: int = gpKindRank(gpKindA)
	var gpRb: int = gpKindRank(gpKindB)
	# Different priority: the LESS important line yields. / 优先级不同：次要者让。
	if gpRa != gpRb:
		return GP_SIDE_A if gpRa < gpRb else GP_SIDE_B
	# Same kind: the vertical run breaks, the horizontal one keeps drawing.
	# 同类：竖向段断开，横向段继续画。
	return GP_SIDE_A if gpIsVertical(gpA1, gpA2) else GP_SIDE_B


# ============================ 相交检测 ============================

# Intersection of two segments, or Vector2.INF when they do not properly cross.
# 两线段的交点；未真正交叉时返回 Vector2.INF。
# Shared endpoints are excluded: two pipes landing on the same port touch but do not cross.
# 共用端点被排除：落在同一端口上的两条管线相接而非交叉。
static func gpSegCross(gpA1: Vector2, gpA2: Vector2, gpB1: Vector2, gpB2: Vector2) -> Vector2:
	var gpR: Vector2 = gpA2 - gpA1
	var gpS: Vector2 = gpB2 - gpB1
	var gpDen: float = gpR.cross(gpS)
	if absf(gpDen) <= 0.000001:
		return Vector2.INF  # parallel or collinear / 平行或共线
	var gpT: float = (gpB1 - gpA1).cross(gpS) / gpDen
	var gpU: float = (gpB1 - gpA1).cross(gpR) / gpDen
	if gpT <= GP_EPS / maxf(gpR.length(), 1.0) or gpT >= 1.0 - GP_EPS / maxf(gpR.length(), 1.0):
		return Vector2.INF
	if gpU <= GP_EPS / maxf(gpS.length(), 1.0) or gpU >= 1.0 - GP_EPS / maxf(gpS.length(), 1.0):
		return Vector2.INF
	return gpA1 + gpR * gpT


# Find every crossing among the given lines.
# 找出给定各条线之间的全部交叉。
# [param gpLines] array of {"id": String, "kind": String, "pts": PackedVector2Array}
# [return] array of {"a": idA, "b": idB, "point": Vector2, "broken": idString}
static func gpFindCrossings(gpLines: Array[Dictionary]) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	# Bounding boxes first: two lines whose envelopes do not overlap can never cross, and the
	# cheap reject turns an O(n^2) segment scan into almost-linear work on a real sheet.
	# 先算包围盒：包络不相交的两条线绝不会交叉，这个廉价剔除把 O(n^2) 的线段扫描
	# 在真实图纸上压到近似线性。
	var gpBoxes: Array[Rect2] = []
	for gpL in gpLines:
		gpBoxes.append(_gpBBox(gpL.get("pts", PackedVector2Array())))
	for gpI in range(gpLines.size()):
		var gpLa: Dictionary = gpLines[gpI]
		var gpPa: PackedVector2Array = gpLa.get("pts", PackedVector2Array())
		if gpPa.size() < 2:
			continue
		for gpJ in range(gpI + 1, gpLines.size()):
			if not gpBoxes[gpI].intersects(gpBoxes[gpJ]):
				continue
			var gpLb: Dictionary = gpLines[gpJ]
			var gpPb: PackedVector2Array = gpLb.get("pts", PackedVector2Array())
			if gpPb.size() < 2:
				continue
			for gpM in range(gpPa.size() - 1):
				for gpN in range(gpPb.size() - 1):
					var gpX: Vector2 = gpSegCross(gpPa[gpM], gpPa[gpM + 1], gpPb[gpN],
						gpPb[gpN + 1])
					if gpX == Vector2.INF:
						continue
					var gpIdA: String = str(gpLa.get("id", ""))
					var gpIdB: String = str(gpLb.get("id", ""))
					var gpSide: String = gpBreakSide(str(gpLa.get("kind", "")), gpPa[gpM],
						gpPa[gpM + 1], str(gpLb.get("kind", "")), gpPb[gpN], gpPb[gpN + 1])
					gpOut.append({
						"a": gpIdA,
						"b": gpIdB,
						"point": gpX,
						"broken": gpIdA if gpSide == GP_SIDE_A else gpIdB,
					})
	return gpOut


# The break points belonging to ONE edge, ready to be handed to the painter.
# 属于某一条边的全部断点，可直接交给绘制器。
static func gpBreaksFor(gpCrossings: Array[Dictionary], gpEdgeId: String) -> Array[Vector2]:
	var gpOut: Array[Vector2] = []
	for gpC in gpCrossings:
		if str(gpC.get("broken", "")) == gpEdgeId:
			gpOut.append(gpC.get("point", Vector2.ZERO) as Vector2)
	return gpOut


# ============================ 断口切分 ============================

# Bounding box of a polyline (a degenerate Rect2 for an empty one).
# 折线的包围盒（空折线返回退化矩形）。
static func _gpBBox(gpPts: PackedVector2Array) -> Rect2:
	if gpPts.is_empty():
		return Rect2()
	var gpMin: Vector2 = gpPts[0]
	var gpMax: Vector2 = gpPts[0]
	for gpP in gpPts:
		gpMin = gpMin.min(gpP)
		gpMax = gpMax.max(gpP)
	return Rect2(gpMin, gpMax - gpMin)


# Cumulative arc length at each vertex: gpCum[i] is the distance from the start to gpPts[i].
# 各顶点处的累计弧长：gpCum[i] 为从起点到 gpPts[i] 的距离。
static func gpArcLengths(gpPts: PackedVector2Array) -> Array[float]:
	var gpOut: Array[float] = [0.0]
	for gpI in range(gpPts.size() - 1):
		gpOut.append(gpOut[gpI] + gpPts[gpI].distance_to(gpPts[gpI + 1]))
	return gpOut


# Point at arc length gpS along the polyline.
# 折线上弧长 gpS 处的点。
static func gpPointAt(gpPts: PackedVector2Array, gpCum: Array[float], gpS: float) -> Vector2:
	if gpPts.is_empty():
		return Vector2.ZERO
	if gpPts.size() == 1:
		return gpPts[0]
	var gpTotal: float = gpCum[gpCum.size() - 1]
	if gpS <= 0.0:
		return gpPts[0]
	if gpS >= gpTotal:
		return gpPts[gpPts.size() - 1]
	for gpI in range(gpPts.size() - 1):
		if gpS <= gpCum[gpI + 1] + 0.0001:
			var gpLeg: float = gpCum[gpI + 1] - gpCum[gpI]
			if gpLeg <= 0.0001:
				return gpPts[gpI]
			return gpPts[gpI] + (gpPts[gpI + 1] - gpPts[gpI]) * ((gpS - gpCum[gpI]) / gpLeg)
	return gpPts[gpPts.size() - 1]


# Arc length of the point on the polyline nearest to gpP, or -1 when gpP is not on the line.
# 折线上距 gpP 最近之点的弧长；gpP 不在线上时返回 -1。
static func gpArcAt(gpPts: PackedVector2Array, gpCum: Array[float], gpP: Vector2) -> float:
	var gpBest: float = -1.0
	var gpBestD: float = GP_EPS * 2.0
	for gpI in range(gpPts.size() - 1):
		var gpA: Vector2 = gpPts[gpI]
		var gpB: Vector2 = gpPts[gpI + 1]
		var gpLen: float = gpA.distance_to(gpB)
		if gpLen <= 0.0001:
			continue
		var gpT: float = clampf((gpP - gpA).dot(gpB - gpA) / (gpLen * gpLen), 0.0, 1.0)
		var gpD: float = gpA.distance_to(gpA + (gpB - gpA) * gpT)
		if gpD <= gpBestD:
			gpBestD = gpD
			gpBest = gpCum[gpI] + gpLen * gpT
	return gpBest if gpBest >= 0.0 else -1.0


# Sub-polyline between two arc lengths (inclusive). Used to cut a gap out of a run.
# 两个弧长之间（含端点）的子折线。用于从一段线中切掉断口。
static func gpSubPoly(gpPts: PackedVector2Array, gpCum: Array[float], gpS0: float,
		gpS1: float) -> PackedVector2Array:
	var gpOut: PackedVector2Array = PackedVector2Array()
	if gpS1 - gpS0 <= 0.0001:
		return gpOut
	gpOut.append(gpPointAt(gpPts, gpCum, gpS0))
	for gpI in range(gpPts.size()):
		if gpCum[gpI] > gpS0 + 0.0001 and gpCum[gpI] < gpS1 - 0.0001:
			gpOut.append(gpPts[gpI])
	gpOut.append(gpPointAt(gpPts, gpCum, gpS1))
	return gpOut


# Cut every gap out of a polyline. Returns the remaining pieces (in order).
# 把折线上的每个断口切掉。返回剩余的各段（按序）。
static func gpSplitByGaps(gpPts: PackedVector2Array, gpGaps: Array[Vector2],
		gpGapLen: float) -> Array[PackedVector2Array]:
	if gpPts.size() < 2 or gpGaps.is_empty() or gpGapLen <= 0.0:
		return [gpPts]
	var gpCum: Array[float] = gpArcLengths(gpPts)
	var gpTotal: float = gpCum[gpCum.size() - 1]
	var gpIv: Array[Vector2] = []
	for gpG in gpGaps:
		var gpS: float = gpArcAt(gpPts, gpCum, gpG)
		if gpS < 0.0:
			continue
		var gpA: float = maxf(0.0, gpS - gpGapLen * 0.5)
		var gpB: float = minf(gpTotal, gpS + gpGapLen * 0.5)
		if gpB - gpA <= 0.001:
			continue
		gpIv.append(Vector2(gpA, gpB))
	if gpIv.is_empty():
		return [gpPts]
	gpIv.sort_custom(func(gpX: Vector2, gpY: Vector2) -> bool: return gpX.x < gpY.x)
	var gpMerged: Array[Vector2] = [gpIv[0]]
	for gpK in range(1, gpIv.size()):
		var gpLast: Vector2 = gpMerged[gpMerged.size() - 1]
		if gpIv[gpK].x <= gpLast.y:
			gpMerged[gpMerged.size() - 1] = Vector2(gpLast.x, maxf(gpLast.y, gpIv[gpK].y))
		else:
			gpMerged.append(gpIv[gpK])
	var gpOut: Array[PackedVector2Array] = []
	var gpCur: float = 0.0
	for gpM in gpMerged:
		if gpM.x > gpCur:
			var gpPiece: PackedVector2Array = gpSubPoly(gpPts, gpCum, gpCur, gpM.x)
			if gpPiece.size() >= 2:
				gpOut.append(gpPiece)
		gpCur = maxf(gpCur, gpM.y)
	if gpCur < gpTotal:
		var gpTail: PackedVector2Array = gpSubPoly(gpPts, gpCum, gpCur, gpTotal)
		if gpTail.size() >= 2:
			gpOut.append(gpTail)
	return gpOut


# Clip flat segment pairs [a0,b0, a1,b1, ...] against the gap discs. Dash PHASE is preserved:
# the dashes are generated over the whole polyline first and only then trimmed.
# 用断口圆盘裁剪扁平线段对 [a0,b0, a1,b1, ...]。虚线「相位」得以保留：
# 先沿整条折线生成划段，之后才做修剪。
static func gpClipSegsByGaps(gpSegs: PackedVector2Array, gpGaps: Array[Vector2],
		gpGapLen: float) -> PackedVector2Array:
	if gpGaps.is_empty() or gpGapLen <= 0.0:
		return gpSegs
	var gpOut: PackedVector2Array = PackedVector2Array()
	var gpR: float = gpGapLen * 0.5
	var gpI: int = 0
	while gpI + 1 < gpSegs.size():
		var gpPieces: Array[Vector2] = [gpSegs[gpI], gpSegs[gpI + 1]]
		gpI += 2
		for gpG in gpGaps:
			var gpNext: Array[Vector2] = []
			for gpK in range(0, gpPieces.size(), 2):
				_gpClipOne(gpPieces[gpK], gpPieces[gpK + 1], gpG, gpR, gpNext)
			gpPieces = gpNext
			if gpPieces.is_empty():
				break
		for gpK in range(0, gpPieces.size(), 2):
			gpOut.append(gpPieces[gpK])
			gpOut.append(gpPieces[gpK + 1])
	return gpOut


# Remove the part of segment (gpA, gpB) that falls inside the disc (gpC, gpR), pushing whatever
# survives onto gpOut as flat point pairs.
# 去掉线段 (gpA, gpB) 落在圆盘 (gpC, gpR) 内的部分，把幸存部分作为扁平点对压入 gpOut。
static func _gpClipOne(gpA: Vector2, gpB: Vector2, gpC: Vector2, gpR: float,
		gpOut: Array[Vector2]) -> void:
	var gpD: Vector2 = gpB - gpA
	var gpAa: float = gpD.dot(gpD)
	if gpAa <= 0.000001:
		return
	var gpF: Vector2 = gpA - gpC
	var gpBb: float = 2.0 * gpF.dot(gpD)
	var gpCc: float = gpF.dot(gpF) - gpR * gpR
	var gpDisc: float = gpBb * gpBb - 4.0 * gpAa * gpCc
	# No real roots: the segment misses the disc entirely. / 无实根：线段完全未进入圆盘。
	if gpDisc <= 0.0:
		gpOut.append(gpA)
		gpOut.append(gpB)
		return
	var gpSq: float = sqrt(gpDisc)
	var gpT0: float = (-gpBb - gpSq) / (2.0 * gpAa)
	var gpT1: float = (-gpBb + gpSq) / (2.0 * gpAa)
	var gpLo: float = clampf(minf(gpT0, gpT1), 0.0, 1.0)
	var gpHi: float = clampf(maxf(gpT0, gpT1), 0.0, 1.0)
	if gpHi <= 0.0 or gpLo >= 1.0:
		gpOut.append(gpA)
		gpOut.append(gpB)
		return
	if gpLo > 0.0:
		gpOut.append(gpA)
		gpOut.append(gpA + gpD * gpLo)
	if gpHi < 1.0:
		gpOut.append(gpA + gpD * gpHi)
		gpOut.append(gpB)
