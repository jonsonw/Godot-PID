extends "res://tests/gp_test.gd"
# ShapeSpec round-trip regression suite — locks the P0/P1 fix where Bézier handles must survive a
# path-dict round-trip (promote / save) instead of flattening back to straight ink.
# ShapeSpec 往返回归套件 —— 固化 P0/P1 修复：贝塞尔手柄须经 path 字典往返存活（提升 / 保存），
# 而非被展平成直线墨迹。

# Copyright © 2026 Jonson Wang


# A curved 3-vertex polyline -> gpFromSpec(dict with handles) -> handles restored & curve preserved.
# 3 顶点折线含手柄 -> gpFromSpec(带 handles 的字典) -> 手柄还原 & 曲线保留。
func gpTestHandlesSurviveFromSpec() -> void:
	_gpResetCounters()
	var gpS: GPShape = GPShape.gpPolyline([Vector2(0, 0), Vector2(200, 200), Vector2(400, 50)], false)
	gpS.gpEnsureHandles()
	var gpD: Vector2 = (gpS.gpPoints[2] - gpS.gpPoints[0]).normalized()
	var gpK: float = 0.3 * (gpS.gpPoints[2] - gpS.gpPoints[0]).length()
	gpS.gpSetHandle(1, 0, gpS.gpPoints[1] - gpD * gpK)
	gpS.gpSetHandle(1, 1, gpS.gpPoints[1] + gpD * gpK)
	gpCheck(gpS.gpHasCurve(), "source polyline has a pulled-out curve")
	# Build a path dict carrying the handles (mirror _gpShapesToDraft emit).
	# 构造携带 handles 的 path 字典（镜像 _gpShapesToDraft 输出）。
	var gpPts: Array = []
	for gpP in gpS.gpPoints:
		gpPts.append([gpP.x, gpP.y])
	var gpSpec: Dictionary = {"paths": [{"pts": gpPts, "closed": false, "handles": GPShapeSpec.gpEmitHandles(gpS)}]}
	var gpOut: Array[GPShape] = GPShapeSpec.gpFromSpec(gpSpec)
	gpCheck(gpOut.size() == 1, "one shape reconstructed")
	if gpOut.size() == 1:
		var gpR: GPShape = gpOut[0]
		gpCheck(gpR.gpHasCurve(), "reconstructed polyline keeps its curve (handles restored)")
		gpCheck(gpR.gpPoints.size() == 3, "vertex count preserved")
		# A curve should sample far more than 3 raw points when rendered.
		# 曲线渲染采样应远多于 3 个原始点。
		var gpSamp: PackedVector2Array = GPGeometry.gpRenderPoints(gpR, 8)
		gpCheck(gpSamp.size() > 20, "curved polyline renders densely (smooth curve)")


# Rect through gpFromSpec round-trips (two-corner rect stays a rect, bbox correct).
# 矩形经 gpFromSpec 往返（对角矩形仍是矩形，包围盒正确）。
func gpTestRectRoundTrip() -> void:
	_gpResetCounters()
	var gpSpec: Dictionary = {"rects": [{"pos": [10.0, 20.0], "size": [100.0, 60.0]}]}
	var gpOut: Array[GPShape] = GPShapeSpec.gpFromSpec(gpSpec)
	gpCheck(gpOut.size() == 1, "one rect reconstructed")
	if gpOut.size() == 1:
		var gpR: GPShape = gpOut[0]
		gpCheck(gpR.gpKind == GPShape.GPKind.GP_RECT, "kind is rect")
		var gpB: Rect2 = gpR.gpBBox()
		gpApprox(gpB.position.x, 10.0, 1e-3, "rect bbox min x")
		gpApprox(gpB.position.y, 20.0, 1e-3, "rect bbox min y")
		gpApprox(gpB.size.x, 100.0, 1e-3, "rect bbox width")
		gpApprox(gpB.size.y, 60.0, 1e-3, "rect bbox height")


# Circle through gpFromSpec keeps center + radius.
# 圆经 gpFromSpec 保留圆心 + 半径。
func gpTestCircleRoundTrip() -> void:
	_gpResetCounters()
	var gpSpec: Dictionary = {"circles": [{"c": [50.0, 40.0], "r": 25.0}]}
	var gpOut: Array[GPShape] = GPShapeSpec.gpFromSpec(gpSpec)
	gpCheck(gpOut.size() == 1, "one circle reconstructed")
	if gpOut.size() == 1:
		var gpC: GPShape = gpOut[0]
		gpCheck(gpC.gpKind == GPShape.GPKind.GP_CIRCLE, "kind is circle")
		gpApprox(gpC.gpPoints[0].x, 50.0, 1e-3, "circle center x")
		gpApprox(gpC.gpPoints[0].y, 40.0, 1e-3, "circle center y")
		gpApprox(gpC.gpRadius, 25.0, 1e-3, "circle radius")


# gpBuild of a mixed set yields paths/circles/rects with a derived box.
# gpBuild 对混合图形集生成 paths/circles/rects 并推导 box。
func gpTestBuildDerivesBox() -> void:
	_gpResetCounters()
	var gpShapes: Array[GPShape] = [
		GPShape.gpLine(Vector2(0, 0), Vector2(50, 0)),
		GPShape.gpCircle(Vector2(100, 100), 20.0),
	]
	var gpSpec: Dictionary = GPShapeSpec.gpBuild(gpShapes)
	gpCheck(gpSpec.has("paths"), "build has paths")
	gpCheck(gpSpec.has("circles"), "build has circles")
	gpCheck(gpSpec.has("box"), "build derives a box")
	var gpBox: Array = gpSpec["box"]
	gpCheck(gpBox.size() >= 4, "box has 4 entries")


# Handles emit/restore is symmetric: emit -> restore -> same relative offsets.
# 手柄 emit/restore 对称：emit -> restore -> 相对偏移一致。
func gpTestEmitRestoreSymmetric() -> void:
	_gpResetCounters()
	var gpS: GPShape = GPShape.gpPolyline([Vector2(10, 10), Vector2(90, 90), Vector2(180, 30)], false)
	gpS.gpEnsureHandles()
	var gpD: Vector2 = (gpS.gpPoints[2] - gpS.gpPoints[0]).normalized()
	var gpK: float = 12.0
	gpS.gpSetHandle(1, 0, gpS.gpPoints[1] - gpD * gpK)
	gpS.gpSetHandle(1, 1, gpS.gpPoints[1] + gpD * gpK)
	var gpRaw: Array = GPShapeSpec.gpEmitHandles(gpS)
	# A fresh copy with no handles.
	var gpFresh: GPShape = GPShape.gpPolyline([Vector2(10, 10), Vector2(90, 90), Vector2(180, 30)], false)
	GPShapeSpec.gpRestoreHandles(gpFresh, gpRaw)
	gpCheck(gpFresh.gpHandles.size() == 3, "three handle slots after restore")
	if gpFresh.gpHandles.size() == 3:
		var gpIn: Vector2 = gpFresh.gpHandles[1][0]
		var gpOut: Vector2 = gpFresh.gpHandles[1][1]
		gpApprox(gpIn.distance_to(Vector2.ZERO), gpK, 1e-3, "in-handle magnitude restored")
		gpApprox(gpOut.distance_to(Vector2.ZERO), gpK, 1e-3, "out-handle magnitude restored")
		gpCheck(not gpIn.is_equal_approx(Vector2.ZERO) and not gpOut.is_equal_approx(Vector2.ZERO), "handles non-collapsed")
