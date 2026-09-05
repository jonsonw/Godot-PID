class_name GPGTestNormalizer
extends GPGTest
# Regression suite for the symbol normalizer, encoding the fix where a Bézier-curved spline
# survives the "make symbol" round-trip (the `_gpTransformShapes` handles-passthrough).
# 符号归一化器的回归套件——固化「贝塞尔弧线经生成图元往返不被拉直」的修复
# （`_gpTransformShapes` 对手柄 handles 的透传）。

# A draft path dict with pulled Bézier handles, mirroring what `_gpShapesToDraft` emits for a
# curved GP_POLYLINE on the main canvas.
# 带被拉出贝塞尔手柄的草稿 path dict，模拟主画布曲线折线经 `_gpShapesToDraft` 的输出。
func _gpCurvedDraft() -> Dictionary:
	var gpS: GPShape = GPShape.gpPolyline([Vector2(100, 100), Vector2(300, 300), Vector2(500, 150)], false)
	gpS.gpEnsureHandles()
	var gpDir: Vector2 = (gpS.gpPoints[2] - gpS.gpPoints[0]).normalized()
	var gpK: float = 0.3 * (gpS.gpPoints[2] - gpS.gpPoints[0]).length()
	gpS.gpSetHandle(1, 0, gpS.gpPoints[1] - gpDir * gpK)
	gpS.gpSetHandle(1, 1, gpS.gpPoints[1] + gpDir * gpK)
	var gpBb: Rect2 = gpS.gpBBox()
	var gpPts: Array = []
	for gpP in gpS.gpPoints:
		gpPts.append([gpP.x - gpBb.position.x, gpP.y - gpBb.position.y])
	return {"paths": [{"pts": gpPts, "closed": gpS.gpClosed, "handles": GPShapeSpec.gpEmitHandles(gpS)}], "circles": [], "rects": []}


# Normalizing a curved draft must yield a GPSymbolDef whose shapes still have curves.
# 归一化带曲线的草稿，生成的 GPSymbolDef 其图形必须仍含曲线（P0/P1 回归点）。
func gpTestNormalizeKeepsCurve() -> void:
	var gpRaw: Dictionary = {"id": "valve_rt", "display_name": "Valve RT", "category": "valve", "shapes": _gpCurvedDraft(), "ports": [], "attrs_schema": {}}
	var gpDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpRaw, "valve", {})
	gpCheck(gpDef != null, "normalize returns a def")
	gpCheck(gpDef.gpShapes.size() >= 1, "def has >= 1 shape")
	var gpHasCurve: bool = false
	for gpO in gpDef.gpShapes:
		if gpO.gpHasCurve():
			gpHasCurve = true
		gpCheck(gpO.gpKind == GPShape.GPKind.GP_POLYLINE or gpO.gpKind == GPShape.GPKind.GP_LINE, "shape is a path kind")
	gpCheck(gpHasCurve, "curved spline keeps its curve through normalization")


# The denormalize round-trip must also preserve curves (used by edit-from-def dialog seeding).
# 反归一化往返须同样保曲线（编辑既有图元、用其几何打开对话框时用）。
func gpTestDenormalizeKeepsCurve() -> void:
	var gpRaw: Dictionary = {"id": "pump_rt", "display_name": "Pump RT", "category": "pump", "shapes": _gpCurvedDraft(), "ports": [], "attrs_schema": {}}
	var gpDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpRaw, "pump", {})
	var gpBack: Dictionary = GPSymbolNormalizer.gpDenormalizeSymbol(gpDef)
	gpCheck(gpBack.has("shapes"), "denormalize returns shapes")
	var gpShapes: Dictionary = gpBack["shapes"] as Dictionary
	var gpPts: Array = gpShapes.get("paths", []) as Array
	gpCheck(gpPts.size() >= 1, "denormalized paths non-empty")
	# Re-import via gpFromSpec: curves must survive the full normalize→denormalize→reimport loop.
	var gpRe: Array[GPShape] = GPShapeSpec.gpFromSpec(gpShapes)
	var gpHasCurve: bool = false
	for gpO in gpRe:
		if gpO.gpHasCurve():
			gpHasCurve = true
	gpCheck(gpHasCurve, "denormalize→reimport keeps curve")


# A straight 2-point line (no handles) stays straight after normalization.
# 无手柄的直线经归一化后保持直线（不产生假曲线）。
func gpTestStraightStaysStraight() -> void:
	var gpLineS: GPShape = GPShape.gpLine(Vector2(0, 0), Vector2(200, 0))
	var gpBb: Rect2 = gpLineS.gpBBox()
	var gpPts: Array = []
	for gpP in gpLineS.gpPoints:
		gpPts.append([gpP.x - gpBb.position.x, gpP.y - gpBb.position.y])
	var gpDraft: Dictionary = {"paths": [{"pts": gpPts, "closed": false}], "circles": [], "rects": []}
	var gpDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(
		{"id": "line_rt", "display_name": "Line", "category": "general", "shapes": gpDraft, "ports": [], "attrs_schema": {}}, "general", {})
	var gpStraight: bool = true
	for gpO in gpDef.gpShapes:
		if gpO.gpHasCurve():
			gpStraight = false
	gpCheck(gpStraight, "straight line has no false curve after normalization")
