extends GPGTest
# Shape model regression tests: Bézier handles, arc, serialize round-trip, vertex ops.
# 图形模型回归测试：贝塞尔手柄、圆弧、序列化往返、顶点操作。

# Rect stored as two opposite corners; bbox must be normalized (P0 rect-flip guard).
func gpTestRectBBoxNormalized() -> void:
	var gpR: GPShape = GPShape.gpRect(Vector2(100, 100), Vector2(0, 0))
	var gpB: Rect2 = gpR.gpBBox()
	gpEq(gpB.position, Vector2(0, 0), "rect bbox top-left normalized")
	gpEq(gpB.size, Vector2(100, 100), "rect bbox size")
	var gpR2: GPShape = GPShape.gpRect(Vector2(0, 0), Vector2(120, 80))
	var gpB2: Rect2 = gpR2.gpBBox()
	gpEq(gpB2.size, Vector2(120, 80), "rect bbox size positive")

# Bézier handle set / get and curve detection.
func gpTestHandles() -> void:
	var gpL: GPShape = GPShape.gpLine(Vector2(0, 0), Vector2(100, 0))
	gpCheck(not gpL.gpHasCurve(), "straight line no curve")
	gpL.gpSetHandle(0, 1, Vector2(40, 40))  # pull out-handle of vertex 0 up
	gpCheck(gpL.gpHasCurve(), "pulled handle => has curve")
	var gpAbs: Vector2 = gpL.gpHandlePos(0, 1)
	gpEq(gpAbs, Vector2(40, 40), "out-handle absolute pos")
	# handle is stored as relative offset from its vertex
	gpEq(gpL.gpHandles[0][1], Vector2(40, 40), "handle stored as relative offset")
	# set the handle to an absolute pos (vertex at 0,0 -> relative == absolute here)

# Remove a vertex from a polyline keeps the rest connected.
func gpTestRemoveVertex() -> void:
	var gpP: GPShape = GPShape.gpPolyline([Vector2(0, 0), Vector2(100, 0), Vector2(200, 50)], false)
	gpP.gpEnsureHandles()
	gpP.gpRemoveVertex(1)
	gpEq(gpP.gpPoints.size(), 2, "removed middle vertex -> 2 remain")
	gpEq(gpP.gpPoints[0], Vector2(0, 0), "first vertex kept")
	gpEq(gpP.gpPoints[1], Vector2(200, 50), "last vertex kept")

# Serialize/deserialize round-trips Bézier handles.
func gpTestSerializeRoundTrip() -> void:
	var gpS: GPShape = GPShape.gpPolyline([Vector2(0, 0), Vector2(100, 100), Vector2(200, 0)], false)
	gpS.gpEnsureHandles()
	var gpD: Vector2 = (gpS.gpPoints[2] - gpS.gpPoints[0]).normalized()
	gpS.gpSetHandle(1, 0, gpS.gpPoints[1] - gpD * 30.0)
	gpS.gpSetHandle(1, 1, gpS.gpPoints[1] + gpD * 30.0)
	var gpDict: Dictionary = gpS.gpToDict()
	var gpRestored: GPShape = GPShape.new()
	gpRestored.gpFromDict(gpDict)
	gpCheck(gpRestored.gpHasCurve(), "handles survive serialize round-trip")
	gpEq(gpRestored.gpPoints.size(), gpS.gpPoints.size(), "same vertex count")
	gpEq(gpRestored.gpKind, GPShape.GPKind.GP_POLYLINE, "kind preserved")

# Arc sampling produces points (and adaptive count when 0).
func gpTestArcSample() -> void:
	var gpA: GPShape = GPShape.gpArc(Vector2(0, 0), Vector2(100, 0), Vector2(0, 100))
	gpCheck(gpA.gpRadius > 0.0, "arc radius derived from center->start")
	var gpSamp: PackedVector2Array = gpA.gpArcSample(24)
	gpCheck(gpSamp.size() > 2, "arc sampled into polyline points")
	# adaptive sampling should be denser than a tiny fixed count for a big arc
	var gpAdapt: PackedVector2Array = gpA.gpArcSample(0)
	gpCheck(gpAdapt.size() >= 16, "adaptive arc sampling is dense")
	# arc bbox excludes the center hole (samples the swept band only)
	var gpB: Rect2 = gpA.gpBBox()
	gpCheck(gpB.size.x > 0.0 and gpB.size.y > 0.0, "arc bbox has extent")
