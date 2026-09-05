extends GPGTest
# Geometry module regression tests: distance, corners, shift, hit-test, Bézier sampling.
# 几何模块回归测试：点线距、角点、平移、命中、贝塞尔采样。

# Point-to-segment distance (GPGeometry.gpDistPointSeg).
func gpTestDistPointSeg() -> void:
	# Point exactly on a horizontal segment -> distance 0.
	gpApprox(GPGeometry.gpDistPointSeg(Vector2(50, 0), Vector2(0, 0), Vector2(100, 0)), 0.0, 1e-4, "point on segment dist 0")
	# Point above the middle -> distance = its y.
	gpApprox(GPGeometry.gpDistPointSeg(Vector2(50, 30), Vector2(0, 0), Vector2(100, 0)), 30.0, 1e-4, "point above segment")
	# Point beyond an endpoint clamps to the endpoint distance.
	gpApprox(GPGeometry.gpDistPointSeg(Vector2(150, 0), Vector2(0, 0), Vector2(100, 0)), 50.0, 1e-4, "point past end clamps to endpoint")
	# Diagonal segment (0,0)->(100,100): a point on the line is ~0 away, a point off is >0.
	gpApprox(GPGeometry.gpDistPointSeg(Vector2(50, 50), Vector2(0, 0), Vector2(100, 100)), 0.0, 1e-4, "point on diagonal dist 0")
	gpApprox(GPGeometry.gpDistPointSeg(Vector2(0, 100), Vector2(0, 0), Vector2(100, 100)), sqrt(5000.0), 1e-3, "point off diagonal")

# Rect corners in TL/TR/BR/BL order.
func gpTestRectCorners() -> void:
	var gpCorners: PackedVector2Array = GPGeometry.gpRectCorners(Rect2(Vector2(10, 20), Vector2(100, 50)))
	gpEq(gpCorners.size(), 4, "four corners")
	gpEq(gpCorners[0], Vector2(10, 20), "corner 0 TL")
	gpEq(gpCorners[1], Vector2(110, 20), "corner 1 TR")
	gpEq(gpCorners[2], Vector2(110, 70), "corner 2 BR")
	gpEq(gpCorners[3], Vector2(10, 70), "corner 3 BL")

# Shift a points array by a delta (used for whole-shape move).
func gpTestShiftPoints() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(100, 50)])
	var gpOut: PackedVector2Array = GPGeometry.gpShiftPoints(gpPts, Vector2(20, -10))
	gpEq(gpOut[0], Vector2(20, -10), "first point shifted")
	gpEq(gpOut[1], Vector2(120, 40), "second point shifted")

# Bézier handle sampling: a pulled-out handle makes the segment curve.
func gpTestBezierRender() -> void:
	var gpL: GPShape = GPShape.gpLine(Vector2(0, 0), Vector2(200, 0))
	gpL.gpSetHandle(0, 1, Vector2(100, -80))  # pull out-handle of v0 up (negative y in godot = up when y grows down, just use +y)
	gpL.gpSetHandle(1, 0, Vector2(100, -80))
	var gpPts: PackedVector2Array = GPGeometry.gpRenderPoints(gpL, 8)
	# straight line without handles samples to just endpoints, but with handles should curve
	gpCheck(gpPts.size() >= 8, "curved line samples many points")
	# Midpoint of a straight (0,0)-(200,0) line is (100,0); a pulled handle should deviate.
	var gpMid: Vector2 = gpPts[int(gpPts.size() / 2)]
	gpCheck(absf(gpMid.y) > 1.0, "pulled handle bends the line off-axis (mid.y=%f)" % gpMid.y)

# Arc sampling via gpRenderPoints is dense and adaptive.
func gpTestArcRender() -> void:
	var gpA: GPShape = GPShape.gpArc(Vector2(0, 0), Vector2(200, 0), Vector2(0, 200))
	var gpPts: PackedVector2Array = GPGeometry.gpRenderPoints(gpA, 8)
	gpCheck(gpPts.size() >= 16, "arc render samples densely (got %d)" % gpPts.size())
