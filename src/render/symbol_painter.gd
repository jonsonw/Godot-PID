class_name GPSymbolPainter
extends RefCounted

# Shared vector-shape renderer for symbols on the canvas and in the palette.
# 供画布与图元库共享的矢量形状渲染器。
# Keeps drawing logic in one place so canvas symbols and palette thumbnails look the same.
# 将绘制逻辑集中在一处，使画布图元与库缩略图外观一致。

# Draw a normalized symbol shape (0..100 per axis) into the given local rectangle.
# 将归一化的图元形状（每轴 0..100）绘制到指定的本地矩形内。
# [param gpCanvas] The CanvasItem that provides draw_* methods.
# [param gpCanvas] 提供 draw_* 方法的 CanvasItem。
# [param gpShape]  Symbol shape dictionary produced by gen_openpid_defs.py.
# [param gpShape]  由 gen_openpid_defs.py 生成的图元形状字典。
# [param gpRect]   Target rectangle in local coordinates.
# [param gpRect]   本地坐标系中的目标矩形。
# [param gpFill]   Fill color for closed shapes.
# [param gpFill]   闭合形状的填充色。
# [param gpStroke] Line / outline color.
# [param gpStroke] 线条/描边颜色。
# [param gpLineWidth] Stroke width in pixels (world units for canvas, screen units for palette).
# [param gpLineWidth] 描边宽度（画布用世界单位，图元库用屏幕单位）。
static func gpDrawShape(
	gpCanvas: CanvasItem,
	gpShape: Dictionary,
	gpRect: Rect2,
	gpFill: Color,
	gpStroke: Color,
	gpLineWidth: float
) -> void:
	# Independent x/y scale from the normalized 0..100 box to the target rectangle.
	# 从归一化 0..100 方框到目标矩形的独立 x/y 缩放系数。
	var gpKx: float = gpRect.size.x / 100.0
	var gpKy: float = gpRect.size.y / 100.0
	var gpOx: float = gpRect.position.x
	var gpOy: float = gpRect.position.y

	# Draw paths as polylines. We intentionally do not fill closed paths here because
	# many P&ID line-art shapes are self-intersecting and would fail polygon triangulation.
	# 以折线方式绘制路径。此处故意不填充闭合路径，因为很多 P&ID 线形符号自相交，
	# 会导致多边形三角化失败。
	var gpPaths: Array = gpShape.get("paths", [])
	for gpP in gpPaths:
		var gpPts: Array = gpP.get("pts", [])
		if gpPts.is_empty():
			continue
		var gpVecs: PackedVector2Array = PackedVector2Array()
		for gpPt in gpPts:
			var gpVx: float = gpOx + float(gpPt[0]) * gpKx
			var gpVy: float = gpOy + float(gpPt[1]) * gpKy
			gpVecs.append(Vector2(gpVx, gpVy))
		gpCanvas.draw_polyline(gpVecs, gpStroke, gpLineWidth)

	# Draw circles (filled then outlined).
	# 绘制圆（先填充再描边）。
	var gpCircles: Array = gpShape.get("circles", [])
	for gpC in gpCircles:
		var gpCx: float = gpOx + float(gpC["c"][0]) * gpKx
		var gpCy: float = gpOy + float(gpC["c"][1]) * gpKy
		var gpCtr: Vector2 = Vector2(gpCx, gpCy)
		var gpR: float = float(gpC["r"]) * gpKy
		gpCanvas.draw_circle(gpCtr, gpR, gpFill, true)
		gpCanvas.draw_circle(gpCtr, gpR, gpStroke, false, gpLineWidth)

	# Draw rectangles (filled then outlined).
	# 绘制矩形（先填充再描边）。
	var gpRects: Array = gpShape.get("rects", [])
	for gpRd in gpRects:
		var gpRx: float = gpOx + float(gpRd["pos"][0]) * gpKx
		var gpRy: float = gpOy + float(gpRd["pos"][1]) * gpKy
		var gpRw: float = float(gpRd["size"][0]) * gpKx
		var gpRh: float = float(gpRd["size"][1]) * gpKy
		var gpRRect: Rect2 = Rect2(Vector2(gpRx, gpRy), Vector2(gpRw, gpRh))
		gpCanvas.draw_rect(gpRRect, gpFill, true)
		gpCanvas.draw_rect(gpRRect, gpStroke, false, gpLineWidth)


# Map a symbol category string to a base fill color.
# 将图元类目字符串映射到基础填充色。
static func gpCategoryColor(gpCat: String) -> Color:
	match gpCat:
		"pump":       return Color(0.30, 0.62, 0.95)
		"tank":       return Color(0.40, 0.80, 0.55)
		"valve":      return Color(0.95, 0.65, 0.25)
		"instrument": return Color(0.85, 0.45, 0.85)
		"heat":       return Color(0.95, 0.45, 0.45)
		_:            return Color(0.65, 0.68, 0.75)
