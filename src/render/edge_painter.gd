class_name GPEdgePainter
extends RefCounted
# Copyright © 2026 Jonson Wang
# Paint-only shell for edges: ink, selection halo, dangling-end marks, flow arrows, line numbers.
# 连线的「只画」外壳：墨线、选中光晕、悬空端标记、流向箭头、管线编号。
# Every geometric decision lives in GPEdgeRoute / GPEdgeDash / GPEdgeTagLayout; this class only
# calls draw_*. That split is what lets the routing and dashing be unit-tested headlessly.
# 所有几何决策都在 GPEdgeRoute / GPEdgeDash / GPEdgeTagLayout 中；本类只调用 draw_*。
# 正是这一拆分让布线与虚线可以 headless 单测。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Flow-arrow geometry (world units). / 流向箭头的几何尺寸（世界单位）。
const GP_ARROW_LEN: float = 10.0
const GP_ARROW_HALF: float = 4.5

# Dangling-end ring radius (world units). / 悬空端圆环半径（世界单位）。
const GP_DANGLING_R: float = 5.0

# Text outline, so a number stays legible over grid lines and crossing pipes.
# 文字描边，使编号在网格线与交叉管线之上依然清晰。
const GP_TEXT_OUTLINE: int = 2


# Draw the ink (solid or dashed) of one edge.
# 绘制一条边的墨线（实线或虚线）。
# [param gpPattern] empty = solid / 为空表示实线
# [param gpGaps] crossing points where this line must show a break (断口); EMPTY = draw it whole.
# [param gpGaps] 本线须显示为断口的交叉点；为空表示整条连通绘制。
static func gpDrawInk(gpCv: CanvasItem, gpPts: PackedVector2Array, gpColor: Color,
		gpWidth: float, gpPattern: PackedFloat32Array, gpGaps: Array[Vector2] = []) -> void:
	if gpCv == null or gpPts.size() < 2:
		return
	if gpGaps.is_empty():
		if gpPattern.is_empty():
			gpCv.draw_polyline(gpPts, gpColor, gpWidth)
			return
		var gpSegs: PackedVector2Array = GPEdgeDash.gpSegments(gpPts, gpPattern)
		var gpI: int = 0
		while gpI + 1 < gpSegs.size():
			gpCv.draw_line(gpSegs[gpI], gpSegs[gpI + 1], gpColor, gpWidth)
			gpI += 2
		return
	# Gapped: a solid run is split into pieces so the joins survive; a dashed run keeps its phase
	# by generating the dashes over the WHOLE polyline first and only then trimming them.
	# 带断口：实线切成分段以保留接缝；虚线则先沿整条折线生成划段（保留相位），之后才修剪。
	if gpPattern.is_empty():
		for gpPiece in GPEdgeCrossing.gpSplitByGaps(gpPts, gpGaps, GPEdgeCrossing.GP_BREAK_GAP):
			if gpPiece.size() >= 2:
				gpCv.draw_polyline(gpPiece, gpColor, gpWidth)
		return
	var gpTrimmed: PackedVector2Array = GPEdgeCrossing.gpClipSegsByGaps(
		GPEdgeDash.gpSegments(gpPts, gpPattern), gpGaps, GPEdgeCrossing.GP_BREAK_GAP)
	var gpJ: int = 0
	while gpJ + 1 < gpTrimmed.size():
		gpCv.draw_line(gpTrimmed[gpJ], gpTrimmed[gpJ + 1], gpColor, gpWidth)
		gpJ += 2


# Draw a soft halo UNDER the ink so selecting a 1.4-wide signal line is actually visible.
# 在墨线「之下」画一层柔和光晕，使选中 1.4 宽的细信号线也能被看见。
# Always solid: a dashed halo reads as noise and hides the dash pattern it surrounds.
# 恒为实线：虚线光晕看起来像噪点，还会盖住它所环绕的虚线图案。
# The halo is cut by the same gaps, otherwise it would fill the very break it surrounds.
# 光晕同样被断口切断，否则它会把本应留出的断口填满。
static func gpDrawHalo(gpCv: CanvasItem, gpPts: PackedVector2Array, gpColor: Color,
		gpWidth: float, gpGaps: Array[Vector2] = []) -> void:
	if gpCv == null or gpPts.size() < 2:
		return
	if gpGaps.is_empty():
		gpCv.draw_polyline(gpPts, gpColor, gpWidth)
		return
	for gpPiece in GPEdgeCrossing.gpSplitByGaps(gpPts, gpGaps, GPEdgeCrossing.GP_BREAK_GAP):
		if gpPiece.size() >= 2:
			gpCv.draw_polyline(gpPiece, gpColor, gpWidth)


# Mark a free (dangling) end with a hollow ring — the drafting convention for "continues
# elsewhere / to be connected later", and the only way to SEE that an end is unbound.
# 用空心圆环标记悬空端 —— 这是「延续他页 / 待接」的制图约定，也是唯一能「看见」某端未绑定的方式。
static func gpDrawDangling(gpCv: CanvasItem, gpPos: Vector2, gpColor: Color, gpZoom: float) -> void:
	if gpCv == null:
		return
	var gpW: float = maxf(1.5, 1.5 / maxf(gpZoom, 0.01))
	gpCv.draw_arc(gpPos, GP_DANGLING_R, 0.0, TAU, 16, gpColor, gpW)


# Draw a flow arrow on the longest leg, pointing from source to target.
# 在最长段上画流向箭头，由起点指向终点。
static func gpDrawArrow(gpCv: CanvasItem, gpPts: PackedVector2Array, gpColor: Color) -> void:
	var gpI: int = GPEdgeTagLayout.gpLongestSegment(gpPts)
	if gpCv == null or gpI < 0:
		return
	var gpA: Vector2 = gpPts[gpI]
	var gpB: Vector2 = gpPts[gpI + 1]
	var gpLen: float = gpA.distance_to(gpB)
	# A leg shorter than the arrow would render as a blob; skip instead of shrinking.
	# 短于箭头的段画出来会成一团，故跳过而非缩小。
	if gpLen < GP_ARROW_LEN * 1.5:
		return
	var gpDir: Vector2 = (gpB - gpA) / gpLen
	var gpMid: Vector2 = (gpA + gpB) * 0.5
	var gpN: Vector2 = Vector2(-gpDir.y, gpDir.x)
	var gpTip: Vector2 = gpMid + gpDir * GP_ARROW_LEN * 0.5
	var gpTail: Vector2 = gpMid - gpDir * GP_ARROW_LEN * 0.5
	var gpTri: PackedVector2Array = PackedVector2Array([
		gpTip,
		gpTail + gpN * GP_ARROW_HALF,
		gpTail - gpN * GP_ARROW_HALF,
	])
	gpCv.draw_colored_polygon(gpTri, gpColor)


# Draw the line number. Rotates the text on a vertical run when gpRotate is set.
# 绘制管线编号。gpRotate 为真时在竖管上旋转文字。
# [return] the text bounding rectangle in world coordinates, so callers can use it for
#          hit-testing or overlap avoidance.
# [return] 文字包围矩形（世界坐标），供调用方做命中测试或避让。
static func gpDrawTag(gpCv: CanvasItem, gpPts: PackedVector2Array, gpText: String, gpFont: Font,
		gpFontSize: int, gpColor: Color, gpRotate: bool = true) -> Rect2:
	if gpCv == null or gpText == "" or gpPts.size() < 2:
		return Rect2()
	var gpSz: Vector2 = gpFont.get_string_size(gpText, HORIZONTAL_ALIGNMENT_LEFT, -1.0, gpFontSize)
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, gpSz.x, gpSz.y, gpRotate)
	var gpPos: Vector2 = gpPl.get("pos", Vector2.ZERO)
	var gpRot: float = float(gpPl.get("rot", 0.0))
	if is_zero_approx(gpRot):
		gpCv.draw_string_outline(gpFont, gpPos, gpText, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			gpFontSize, GP_TEXT_OUTLINE, Color(0.0, 0.0, 0.0, 0.65))
		gpCv.draw_string(gpFont, gpPos, gpText, HORIZONTAL_ALIGNMENT_LEFT, -1.0, gpFontSize, gpColor)
		return Rect2(gpPos, gpSz)
	# Rotated text: draw at the origin of a transformed frame, then restore the identity so
	# every later draw call on this canvas item is unaffected.
	# 旋转文字：在变换后的坐标系原点绘制，随后复位为单位变换，使本画布项之后的每次绘制不受影响。
	gpCv.draw_set_transform(gpPos, gpRot, Vector2.ONE)
	gpCv.draw_string_outline(gpFont, Vector2.ZERO, gpText, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		gpFontSize, GP_TEXT_OUTLINE, Color(0.0, 0.0, 0.0, 0.65))
	gpCv.draw_string(gpFont, Vector2.ZERO, gpText, HORIZONTAL_ALIGNMENT_LEFT, -1.0, gpFontSize, gpColor)
	gpCv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return Rect2(gpPos, gpSz)
