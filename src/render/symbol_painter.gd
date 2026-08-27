class_name GPSymbolPainter
extends RefCounted

# Shared vector-shape renderer for symbols on the canvas and in the palette.
# 供画布与图元库共享的矢量形状渲染器。
# Keeps drawing logic in one place so canvas symbols and palette thumbnails look the same.
# 将绘制逻辑集中在一处，使画布图元与库缩略图外观一致。

# Draw a normalized symbol shape into the given local rectangle, UNIFORMLY scaled.
# 将归一化的图元形状均匀缩放后绘制到指定的本地矩形内。
# Coordinates live in a 100x100 unit box (see GPSymbolDef.gpShape). The glyph's own unit-space
# bounding box is carried in gpShape["box"] = [x, y, w, h]; the scale factor is
# min(rect.w / box.w, rect.h / box.h), so the glyph keeps its aspect ratio, stays centered in
# the rectangle, and touches the envelope on its dominant axis (which is what makes the
# category standard ports land exactly on the drawn endpoints).
# 坐标位于 100x100 单位框内（见 GPSymbolDef.gpShape）。字形自身的单位空间包围盒存于
# gpShape["box"] = [x, y, w, h]；缩放系数取 min(rect.w / box.w, rect.h / box.h)，从而字形
# 保持长宽比、在矩形内居中、并在主轴方向贴合包络（这正是类别标准端口能精确落在绘制端点上的原因）。
# When "box" is absent (hand-authored legacy shapes) the whole 100x100 box is assumed.
# 若缺少 "box"（手写的历史形状），则按整个 100x100 单位框处理。
# [param gpCanvas] The CanvasItem that provides draw_* methods.
# [param gpCanvas] 提供 draw_* 方法的 CanvasItem。
# [param gpShape]  Symbol shape dictionary produced by the generator or the symbol editor.
# [param gpShape]  由生成器或图元编辑器产出的图元形状字典。
# [param gpRect]   Target rectangle in local coordinates (the nominal envelope).
# [param gpRect]   本地坐标系中的目标矩形（标称包络）。
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
	# Uniform scale + centering offsets derived from the glyph's unit-space box.
	# 由字形单位空间包围盒推导出的均匀缩放系数与居中偏移。
	var gpBox: Rect2 = gpUnitBox(gpShape)
	var gpK: float = gpFitScale(gpBox, gpRect.size)
	var gpBoxCtr: Vector2 = gpBox.get_center()
	var gpCtr: Vector2 = gpRect.get_center()

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
			var gpVx: float = gpCtr.x + (float(gpPt[0]) - gpBoxCtr.x) * gpK
			var gpVy: float = gpCtr.y + (float(gpPt[1]) - gpBoxCtr.y) * gpK
			gpVecs.append(Vector2(gpVx, gpVy))
		gpCanvas.draw_polyline(gpVecs, gpStroke, gpLineWidth)

	# Draw circles (filled then outlined). Radius uses the same uniform factor, so circles
	# stay circles regardless of the envelope aspect ratio.
	# 绘制圆（先填充再描边）。半径使用同一均匀系数，因此无论包络长宽比如何，圆始终是圆。
	var gpCircles: Array = gpShape.get("circles", [])
	for gpC in gpCircles:
		var gpCx: float = gpCtr.x + (float(gpC["c"][0]) - gpBoxCtr.x) * gpK
		var gpCy: float = gpCtr.y + (float(gpC["c"][1]) - gpBoxCtr.y) * gpK
		var gpCircleCtr: Vector2 = Vector2(gpCx, gpCy)
		var gpR: float = float(gpC["r"]) * gpK
		gpCanvas.draw_circle(gpCircleCtr, gpR, gpFill, true)
		gpCanvas.draw_circle(gpCircleCtr, gpR, gpStroke, false, gpLineWidth)

	# Draw rectangles (filled then outlined).
	# 绘制矩形（先填充再描边）。
	var gpRects: Array = gpShape.get("rects", [])
	for gpRd in gpRects:
		var gpRx: float = gpCtr.x + (float(gpRd["pos"][0]) - gpBoxCtr.x) * gpK
		var gpRy: float = gpCtr.y + (float(gpRd["pos"][1]) - gpBoxCtr.y) * gpK
		var gpRw: float = float(gpRd["size"][0]) * gpK
		var gpRh: float = float(gpRd["size"][1]) * gpK
		var gpRRect: Rect2 = Rect2(Vector2(gpRx, gpRy), Vector2(gpRw, gpRh))
		gpCanvas.draw_rect(gpRRect, gpFill, true)
		gpCanvas.draw_rect(gpRRect, gpStroke, false, gpLineWidth)


# Read the glyph's unit-space bounding box out of a shape dictionary.
# 从形状字典中读取字形的单位空间包围盒。
# Falls back to the full 100x100 unit box when the shape carries no "box" entry.
# 当形状未携带 "box" 时，回退为完整的 100x100 单位框。
static func gpUnitBox(gpShape: Dictionary) -> Rect2:
	if gpShape.has("box"):
		var gpB: Array = gpShape["box"]
		if gpB.size() >= 4:
			var gpW: float = maxf(float(gpB[2]), 0.001)
			var gpH: float = maxf(float(gpB[3]), 0.001)
			return Rect2(Vector2(float(gpB[0]), float(gpB[1])), Vector2(gpW, gpH))
	return Rect2(Vector2.ZERO, Vector2(100.0, 100.0))


# Uniform scale factor that fits a unit-space box into a target size without distortion.
# 将单位空间包围盒无变形地塞入目标尺寸的均匀缩放系数。
static func gpFitScale(gpBox: Rect2, gpTarget: Vector2) -> float:
	var gpBw: float = maxf(gpBox.size.x, 0.001)
	var gpBh: float = maxf(gpBox.size.y, 0.001)
	return minf(gpTarget.x / gpBw, gpTarget.y / gpBh)


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
