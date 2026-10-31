class_name GPDRCGeometry
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Small, pure geometry helpers shared by DRC rules (ADR-39). Kept separate from the snapshot so
# rules can be unit-tested without a graph.
# DRC 规则共享的小型纯几何工具（ADR-39）。与快照分开，使规则可以脱离图做单测。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_EPS: float = 0.001


# Whether a segment enters a rect (endpoints inside count).
# 线段是否进入矩形（端点在内部也算）。
static func gpSegmentHitsRect(gpP0: Vector2, gpP1: Vector2, gpRect: Rect2) -> bool:
	if gpRect.size.x <= 0.0 or gpRect.size.y <= 0.0:
		return false
	if gpRect.has_point(gpP0) or gpRect.has_point(gpP1):
		return true
	var gpA: Vector2 = gpRect.position
	var gpB: Vector2 = Vector2(gpRect.end.x, gpRect.position.y)
	var gpC: Vector2 = gpRect.end
	var gpD: Vector2 = Vector2(gpRect.position.x, gpRect.end.y)
	return Geometry2D.segment_intersects_segment(gpP0, gpP1, gpA, gpB) != null \
		or Geometry2D.segment_intersects_segment(gpP0, gpP1, gpB, gpC) != null \
		or Geometry2D.segment_intersects_segment(gpP0, gpP1, gpC, gpD) != null \
		or Geometry2D.segment_intersects_segment(gpP0, gpP1, gpD, gpA) != null


# Whether any segment of a polyline enters a rect.
# 折线任一段是否进入矩形。
static func gpPolylineHitsRect(gpPts: PackedVector2Array, gpRect: Rect2) -> bool:
	if gpRect.size.x <= 0.0 or gpRect.size.y <= 0.0:
		return false
	for gpI in range(gpPts.size() - 1):
		if gpSegmentHitsRect(gpPts[gpI], gpPts[gpI + 1], gpRect):
			return true
	return false


# Intersection point of two segments, or Vector2.INF when they do not cross at a single point.
# 两条线段的交点；不在单点相交时返回 Vector2.INF。
static func gpSegmentIntersection(gpA0: Vector2, gpA1: Vector2, gpB0: Vector2,
		gpB1: Vector2) -> Vector2:
	var gpP: Variant = Geometry2D.segment_intersects_segment(gpA0, gpA1, gpB0, gpB1)
	return gpP as Vector2 if gpP != null else Vector2.INF


# Distance from a point to a segment.
# 点到线段的距离。
static func gpPointSegmentDistance(gpP: Vector2, gpA: Vector2, gpB: Vector2) -> float:
	var gpAb: Vector2 = gpB - gpA
	var gpLen2: float = gpAb.length_squared()
	if gpLen2 <= GP_EPS:
		return gpP.distance_to(gpA)
	var gpT: float = clampf((gpP - gpA).dot(gpAb) / gpLen2, 0.0, 1.0)
	return gpP.distance_to(gpA + gpAb * gpT)


# Length of the collinear overlap of two segments (0 when not collinear / not overlapping).
# 两条线段共线重叠的长度（不共线 / 不重叠时为 0）。
static func gpCollinearOverlap(gpA0: Vector2, gpA1: Vector2, gpB0: Vector2,
		gpB1: Vector2) -> float:
	var gpDa: Vector2 = gpA1 - gpA0
	var gpDb: Vector2 = gpB1 - gpB0
	var gpLa: float = gpDa.length()
	var gpLb: float = gpDb.length()
	if gpLa <= GP_EPS or gpLb <= GP_EPS:
		return 0.0
	var gpNa: Vector2 = gpDa / gpLa
	var gpNb: Vector2 = gpDb / gpLb
	if absf(gpNa.cross(gpNb)) > 0.02:
		return 0.0
	if absf((gpB0 - gpA0).cross(gpNa)) > 0.5:
		return 0.0
	var gpTa0: float = (gpB0 - gpA0).dot(gpNa)
	var gpTa1: float = gpTa0 + gpLb * gpNb.dot(gpNa)
	var gpLo: float = maxf(gpTa0, gpTa1)
	var gpHi: float = minf(gpTa0, gpTa1)
	var gpStart: float = maxf(0.0, minf(gpLo, gpHi))
	var gpEnd: float = minf(gpLa, maxf(gpLo, gpHi))
	return maxf(0.0, gpEnd - gpStart)


# Whether a point lies on a segment (within tolerance), excluding its two endpoints.
# 点是否落在线段内部（容差内，排除两端点）。
static func gpPointOnSegmentInterior(gpP: Vector2, gpA: Vector2, gpB: Vector2,
		gpTol: float = 0.5) -> bool:
	if gpP.distance_to(gpA) <= gpTol or gpP.distance_to(gpB) <= gpTol:
		return false
	if gpPointSegmentDistance(gpP, gpA, gpB) > gpTol:
		return false
	return true


# Minimum distance between two segments (0 when they intersect).
# 两条线段的最小距离（相交时为 0）。
static func gpSegmentDistance(gpA0: Vector2, gpA1: Vector2, gpB0: Vector2,
		gpB1: Vector2) -> float:
	if gpSegmentIntersection(gpA0, gpA1, gpB0, gpB1) != Vector2.INF:
		return 0.0
	return minf(
		minf(gpPointSegmentDistance(gpA0, gpB0, gpB1), gpPointSegmentDistance(gpA1, gpB0, gpB1)),
		minf(gpPointSegmentDistance(gpB0, gpA0, gpA1), gpPointSegmentDistance(gpB1, gpA0, gpA1)))


# Bounding rect of a polyline.
# 折线的包围盒。
static func gpPolylineRect(gpPts: PackedVector2Array) -> Rect2:
	if gpPts.is_empty():
		return Rect2()
	var gpRect: Rect2 = Rect2(gpPts[0], Vector2.ZERO)
	for gpP in gpPts:
		gpRect = gpRect.expand(gpP)
	return gpRect


# Parallelism / distance / projection overlap of two segments. `parallel` is false when the
# directions differ by more than ~1.1 degrees.
# 两条线段的平行性 / 间距 / 投影重叠长度。方向差超过约 1.1 度时 parallel=false。
static func gpParallelRun(gpA0: Vector2, gpA1: Vector2, gpB0: Vector2,
		gpB1: Vector2) -> Dictionary:
	var gpDa: Vector2 = gpA1 - gpA0
	var gpDb: Vector2 = gpB1 - gpB0
	var gpLa: float = gpDa.length()
	var gpLb: float = gpDb.length()
	if gpLa <= GP_EPS or gpLb <= GP_EPS:
		return {"parallel": false, "dist": 0.0, "overlap": 0.0}
	var gpNa: Vector2 = gpDa / gpLa
	var gpNb: Vector2 = gpDb / gpLb
	if absf(gpNa.cross(gpNb)) > 0.02:
		return {"parallel": false, "dist": 0.0, "overlap": 0.0}
	var gpDist: float = absf((gpB0 - gpA0).cross(gpNa))
	var gpT0: float = (gpB0 - gpA0).dot(gpNa)
	var gpT1: float = (gpB1 - gpA0).dot(gpNa)
	var gpLo: float = maxf(0.0, minf(gpT0, gpT1))
	var gpHi: float = minf(gpLa, maxf(gpT0, gpT1))
	return {"parallel": true, "dist": gpDist, "overlap": maxf(0.0, gpHi - gpLo)}
