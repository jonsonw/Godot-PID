class_name GPGeometry
extends RefCounted

## Pure 2D geometry helpers shared by every canvas (main P&ID view + symbol editor).
## 各画布（主 P&ID 视图与符号编辑器）共用的纯 2D 几何助手。
## Centralizing here removes the duplicated copies that previously lived in canvas_2d.gd and
## glyph_canvas.gd — one source of truth, headless-unit-testable, no Control instance needed.
## 集中于此可消除原本散落在两处画布的重复实现：单一事实来源、可在 headless 下单测、无需实例化 Control。


# Distance from point gpP to segment AB (clamped to the segment interior).
# 点 gpP 到线段 AB 的距离（夹取到线段内部）。
static func gpDistPointSeg(gpP: Vector2, gpA: Vector2, gpB: Vector2) -> float:
	if gpA.is_equal_approx(gpB):
		return gpP.distance_to(gpA)
	var gpAB: Vector2 = gpB - gpA
	var gpLen2: float = gpAB.length_squared()
	if gpLen2 < 1e-9:
		return gpP.distance_to(gpA)
	var gpT: float = clampf(gpAB.dot(gpP - gpA) / gpLen2, 0.0, 1.0)
	return gpP.distance_to(gpA + gpAB * gpT)


# The four AABB corners of gpR, in TL / TR / BR / BL order.
# gpR 的四个轴对齐角点，顺序为 左上 / 右上 / 右下 / 左下。
static func gpRectCorners(gpR: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		gpR.position,
		Vector2(gpR.end.x, gpR.position.y),
		gpR.end,
		Vector2(gpR.position.x, gpR.end.y),
	])


# Shift a point list by gpDelta (pure helper for whole-shape moves).
# 把点列整体平移 gpDelta（整体移动用的纯助手）。
static func gpShiftPoints(gpPts: PackedVector2Array, gpDelta: Vector2) -> PackedVector2Array:
	var gpOut: PackedVector2Array = PackedVector2Array()
	for gpP in gpPts:
		gpOut.append(gpP + gpDelta)
	return gpOut


# Cubic Bézier point at parameter gpU (0..1) through gpP0 / gpC1 / gpC2 / gpP1.
# 过 gpP0 / gpC1 / gpC2 / gpC1 的三次贝塞尔在参数 gpU（0..1）处的点。
static func gpCubic(gpP0: Vector2, gpC1: Vector2, gpC2: Vector2, gpP1: Vector2, gpU: float) -> Vector2:
	var gpV: float = 1.0 - gpU
	var gpA: float = gpV * gpV * gpV
	var gpB: float = 3.0 * gpV * gpV * gpU
	var gpC: float = 3.0 * gpV * gpU * gpU
	var gpD: float = gpU * gpU * gpU
	return gpP0 * gpA + gpC1 * gpB + gpC2 * gpC + gpP1 * gpD


# Does the segment leaving vertex gpI curve (i.e. is any of the two adjacent handles pulled out)?
# 从顶点 gpI 出发的段是否为曲线（即两个相邻手柄中是否有一个被拉出）？
static func gpSegmentCurved(gpS: GPShape, gpI: int) -> bool:
	if gpS.gpKind != GPShape.GPKind.GP_POLYLINE and gpS.gpKind != GPShape.GPKind.GP_LINE:
		return false
	var gpN: int = gpS.gpPoints.size()
	var gpJ: int = gpI + 1
	if gpJ >= gpN:
		if gpS.gpClosed:
			gpJ = 0
		else:
			return false
	if gpI < gpS.gpHandles.size() and gpS.gpHandles[gpI].size() >= 2:
		if not gpS.gpHandles[gpI][1].is_equal_approx(Vector2.ZERO):
			return true
	if gpJ < gpS.gpHandles.size() and gpS.gpHandles[gpJ].size() >= 2:
		if not gpS.gpHandles[gpJ][0].is_equal_approx(Vector2.ZERO):
			return true
	return false


# Sample gpS into a drawable polyline point list. Straight segments stay as their two endpoints;
# curved (handle-pulled) segments become gpSteps Bézier samples; arcs get sampled too. This is the
# SINGLE place that knows how to flatten a GPShape for rendering / hit-testing, so the main canvas,
# the symbol editor and the symbol painter all stay in sync.
# 把 gpS 采样为可绘制的折线点列。直线段仍取两端点；被拉出手柄的曲线段变为 gpSteps 个贝塞尔采样；
# 弧同样采样。这是「如何把 GPShape 展平用于渲染 / 命中」的唯一所在，使主画布、符号编辑器与图元
# 渲染器保持一致。
static func gpRenderPoints(gpS: GPShape, gpSteps: int = 8) -> PackedVector2Array:
	var gpOut: PackedVector2Array = PackedVector2Array()
	if gpS.gpKind == GPShape.GPKind.GP_ARC:
		return gpS.gpArcSample(0)  # adaptive by arc length / 按弧长自适应
	var gpN: int = gpS.gpPoints.size()
	if gpN == 0:
		return gpOut
	# A GP_LINE is an open 2-vertex chain and, when its Bézier handles are pulled out, must sample
	# as a curve too (a 2-point line with handles renders as a cubic). Circle / rect stay raw
	# vertices (their callers draw them natively).
	# GP_LINE 是开放的 2 顶点链，当其贝塞尔手柄被拉出时同样须按曲线采样（带手柄的 2 点直线渲染为
	# 三次贝塞尔）。圆 / 矩形仍返回原始顶点（由各自调用方按原生方式绘制）。
	var gpIsCurvable: bool = gpS.gpKind == GPShape.GPKind.GP_POLYLINE or gpS.gpKind == GPShape.GPKind.GP_LINE
	if not gpIsCurvable:
		return gpS.gpPoints.duplicate()
	for gpI in range(gpN):
		if gpI == 0:
			gpOut.append(gpS.gpPoints[0])
		var gpJ: int = gpI + 1
		if gpJ >= gpN:
			if gpS.gpClosed:
				gpJ = 0
			else:
				break
		if gpSegmentCurved(gpS, gpI):
			var gpCtrl: PackedVector2Array = gpS.gpSegmentControls(gpI)
			if gpCtrl.size() == 4:
				# Subdivide adaptively so a curve stays visually smooth at any zoom: pick a segment
				# count that keeps successive sample points close together. The subdivision count is
				# driven by the cubic's control-polygon length, floored so short bulges never look
				# faceted. This is what removes the "angular / not smooth enough" appearance.
				# 自适应细分，使曲线在任何缩放下都保持视觉顺滑：细分数量由三次贝塞尔控制多边形长度决定，
				# 并设下限使小幅凸起也不会呈块状——这正是消除「有棱角/不够顺」观感的关键。
				var gpLen: float = gpCtrl[0].distance_to(gpCtrl[1]) + gpCtrl[1].distance_to(gpCtrl[2]) + gpCtrl[2].distance_to(gpCtrl[3])
				var gpSub: int = maxi(16, int(ceilf(gpLen / 2.0)))
				gpSub = mini(gpSub, 256)
				for gpT in range(1, gpSub + 1):
					var gpU: float = float(gpT) / float(gpSub)
					gpOut.append(gpCubic(gpCtrl[0], gpCtrl[1], gpCtrl[2], gpCtrl[3], gpU))
				continue
		gpOut.append(gpS.gpPoints[gpJ])
	return gpOut


# Does gpPt fall on / inside gpS (within gpTol)? Pure — operates directly on a GPShape, so the
# main canvas and the symbol editor share one hit-test for annotation geometry.
# gpPt 是否落在图形 gpS 上 / 内（在容差 gpTol 内）？纯函数，直接作用于一枚 GPShape，
# 使主画布与符号编辑器共用同一套注释图形命中测试。
static func gpShapeHit(gpPt: Vector2, gpS: GPShape, gpTol: float) -> bool:
	match gpS.gpKind:
		GPShape.GPKind.GP_CIRCLE:
			if gpS.gpPoints.size() >= 1:
				return gpPt.distance_to(gpS.gpPoints[0]) <= gpS.gpRadius + gpTol
		GPShape.GPKind.GP_RECT:
			if gpS.gpPoints.size() >= 2:
				return Rect2(gpS.gpPoints[0], (gpS.gpPoints[1] - gpS.gpPoints[0]).abs()).grow(gpTol).has_point(gpPt)
		_:
			# Sample first: a curved polyline's raw vertices are only its control nodes, so the
			# distance test must run against the flattened curve, not the vertex polygon.
			# 先采样：曲线折线的原始顶点只是其控制节点，故距离测试须针对展平后的曲线，而非顶点多边形。
			var gpPts: PackedVector2Array = gpRenderPoints(gpS, 8)
			for gpI in range(gpPts.size() - 1):
				if gpDistPointSeg(gpPt, gpPts[gpI], gpPts[gpI + 1]) <= gpTol:
					return true
			if gpS.gpClosed and gpPts.size() >= 3:
				if gpDistPointSeg(gpPt, gpPts[gpPts.size() - 1], gpPts[0]) <= gpTol:
					return true
	return false
