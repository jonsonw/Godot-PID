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

# Flow-arrow geometry, in world units (mm), straight from the reference drawing.
# 流向箭头几何，世界单位（mm），直接取自参照图。
# WHY THESE EXACT NUMBERS / 为何是这两个数：
# DEXPI Example C01 draws the flow marker as a 5.0 x 2.5 unit triangle placed by
# `transform="translate(x,y) rotate(r) scale(0.70,0.70)"`, i.e. 3.5 mm long and 1.75 mm wide overall
# — and the pack's own manifest records the same (`direction_of_flow_for_primary_segment`,
# size_mm = [1.75, 3.5]). Half-width is therefore 0.875 mm.
# DEXPI Example C01 的流向标记是一个 5.0×2.5 单位的三角形，由
# `transform="translate(x,y) rotate(r) scale(0.70,0.70)"` 放置，即整体 3.5mm 长、1.75mm 宽 ——
# 图元包清单记录的尺寸完全一致（`direction_of_flow_for_primary_segment`，size_mm = [1.75, 3.5]）。
# 故半宽为 0.875mm。
# The previous values (10.0 / 4.5) were pixel-era numbers, and once the world unit became 1 mm they
# meant a 10 x 9 mm arrow — 2.9x too long and 5.1x too wide, i.e. the reported "the arrow is far too
# big compared with the standard drawing".
# 此前的数值（10.0 / 4.5）是像素时代的数字；世界单位改为 1mm 后，它们意味着 10×9mm 的箭头 ——
# 长 2.9 倍、宽 5.1 倍，正是用户报告的「箭头比标准图大太多」。
const GP_ARROW_LEN: float = 3.5
const GP_ARROW_HALF: float = 0.875

# ---- Dangling-end ring / 悬空端圆环 ----------------------------------------
# Radius in MILLIMETRES (1 world unit = 1 mm), i.e. a 10 mm ring. Deliberately NOT reduced to a
# "standard-drawing" size: the marker's job is to be unmissable, and its 10 mm diameter reads
# clearly on an A3 sheet. The `_MM` suffix is the point of the name — every length in this file is
# millimetres, and a bare `5.0` was ambiguous enough that it had been read as a pixel-era leftover.
# 半径以**毫米**计（1 世界单位 = 1mm），即 10mm 的圆环。刻意**不**按「标准图」尺寸缩小：标记的任务
# 是不可忽略，而 10mm 直径在 A3 图幅上足够清晰。`_MM` 后缀正是名字的意义 —— 本文件所有长度都是毫米，
# 而裸写 `5.0` 的歧义足以让人把它读成像素时代的遗留值。
# On screen it is 5 mm x zoom (a real drawing feature, so it scales with the sheet, unlike the
# STROKE below which stays screen-constant). / 屏幕上为 5mm × 缩放（它是真实图面要素，故随图幅缩放 ——
# 与下方**屏幕恒定**的描边不同）。
const GP_DANGLING_R_MM: float = 5.0

# Dangling-end ring stroke — two tiers, exactly the shape GPEdgeStyle.gpStyleFor uses: a WORLD-unit
# width (so a plotted sheet carries a real ISO-tier line) plus a screen-space floor (so the marker
# never vanishes when zoomed out).
# 悬空端圆环描边 —— 两层，与 GPEdgeStyle.gpStyleFor 结构完全一致：一个**世界单位**线宽（使出图时是
# 真实的 ISO 档线宽）＋ 一个屏幕下限（使缩小时标记不消失）。
# 0.35 mm is the heavy end of this project's ISO series (the symbol-outline tier), which suits a
# marker whose job is to say "this end is unfinished" — it must read at least as strongly as the pipe.
# 0.35mm 是本项目 ISO 系列的粗端（图元描边档），适合表达「此端未完成」的标记 —— 它至少要与管线同强。
const GP_DANGLING_WIDTH_MM: float = 0.35

# Screen-space floor for the ring, in PIXELS. Deliberately its OWN constant rather than the shared
# GPEdgeStyle.GP_MIN_PX: a marker wants a slightly stronger minimum than a line does.
# 圆环的屏幕下限（像素）。刻意单列而不复用 GPEdgeStyle.GP_MIN_PX —— 标记所需的最小可见度略高于线条。
const GP_DANGLING_MIN_PX: float = 1.5

# Target chord length, in SCREEN pixels, between two vertices of the ring's polygon approximation.
# 圆环多边形逼近中相邻顶点的目标弦长（**屏幕**像素）。
# draw_arc() takes a fixed segment count, so a count picked for a small ring turns visibly polygonal
# once the ring is drawn large: at 8x the radius is 40 screen px, where the previous fixed 16
# segments left a sagitta of ~0.77 px — a visible 16-gon rather than a circle. Sizing the count from
# the ON-SCREEN radius keeps the chord (and therefore the sagitta) constant instead.
# draw_arc() 只接受固定段数，故为小圆环选的段数在圆环画大后会显出多边形感：8× 时屏幕半径 40px，
# 原先固定的 16 段留下约 0.77px 的矢高 —— 是一个看得出的十六边形而非圆。改为按**屏幕**半径取段数，
# 使弦长（从而矢高）保持恒定。
const GP_DANGLING_CHORD_PX: float = 3.0

# Segment count bounds. The floor keeps a zoomed-out ring round; the ceiling bounds the vertex count
# so a degenerate zoom cannot ask draw_arc() for an unbounded polygon.
# 段数上下限。下限保证缩小后仍是圆的；上限约束顶点数，使退化缩放不会向 draw_arc() 索取无界多边形。
const GP_DANGLING_SEG_MIN: int = 16
const GP_DANGLING_SEG_MAX: int = 128

# Leader-line weight, in mm — the THINNEST tier of the ISO 128 line-width series, one step below
# the 0.18 mm signal line. A callout must never compete with the drawing it annotates, so the
# leader is deliberately thinner than every line kind it can point at.
# 引出线线宽（mm）—— ISO 128 线宽系列中**最细**的一档，比 0.18mm 的信号线还细一档。
# 标注绝不能与其所标注的图争抢视觉，故引出线刻意比它能指向的任何线型都细。
const GP_LEADER_WIDTH_MM: float = 0.13

# Screen-space floor for the leader, deliberately BELOW GPEdgeStyle.GP_MIN_PX (1.2 px).
# 引出线的屏幕下限，刻意低于 GPEdgeStyle.GP_MIN_PX（1.2px）。
# WHY A SEPARATE FLOOR / 为何单列一个下限：
# the shared 1.2 px floor would make the leader exactly as thick as the thinnest pipe, and the
# earlier `maxf(1.0, 1.0 / zoom)` used world units — so at the default fit-to-sheet zoom (~2.8x)
# it rendered ~2.8 px, THICKER than the 1.2 px pipe it pointed at. Equal-or-thicker is precisely
# what "引出线应该是最细的" reports.
# 共用的 1.2px 下限会使引出线与最细的管线一样粗；而早先的 `maxf(1.0, 1.0 / zoom)` 用的是世界单位
# —— 在默认「适配图幅」缩放（约 2.8×）下会渲染成约 2.8px，比它所指向的 1.2px 管线还粗。
# 「一样粗或更粗」正是「引出线应该是最细的」所报告的问题。
const GP_LEADER_MIN_PX: float = 1.0

# Text outline, so a number stays legible over grid lines and crossing pipes.
# 文字描边，使编号在网格线与交叉管线之上依然清晰。
const GP_TEXT_OUTLINE: int = 2


# Draw the ink (solid or dashed) of one edge.
# 绘制一条边的墨线（实线或虚线）。
# [param gpPattern] empty = solid / 为空表示实线
static func gpDrawInk(gpCv: CanvasItem, gpPts: PackedVector2Array, gpColor: Color,
		gpWidth: float, gpPattern: PackedFloat32Array) -> void:
	if gpCv == null or gpPts.size() < 2:
		return
	if gpPattern.is_empty():
		gpCv.draw_polyline(gpPts, gpColor, gpWidth)
		return
	var gpSegs: PackedVector2Array = GPEdgeDash.gpSegments(gpPts, gpPattern)
	var gpI: int = 0
	while gpI + 1 < gpSegs.size():
		gpCv.draw_line(gpSegs[gpI], gpSegs[gpI + 1], gpColor, gpWidth)
		gpI += 2


# Draw a soft halo UNDER the ink so selecting a 1.4-wide signal line is actually visible.
# 在墨线「之下」画一层柔和光晕，使选中 1.4 宽的细信号线也能被看见。
# Always solid: a dashed halo reads as noise and hides the dash pattern it surrounds.
# 恒为实线：虚线光晕看起来像噪点，还会盖住它所环绕的虚线图案。
static func gpDrawHalo(gpCv: CanvasItem, gpPts: PackedVector2Array, gpColor: Color,
		gpWidth: float) -> void:
	if gpCv == null or gpPts.size() < 2:
		return
	gpCv.draw_polyline(gpPts, gpColor, gpWidth)


# Resolve the dangling-ring stroke width for a zoom, in WORLD units (mm).
# 按缩放解析悬空端圆环的描边宽度，世界单位（mm）。
# [return] max(GP_DANGLING_WIDTH_MM, GP_DANGLING_MIN_PX / zoom) — i.e. `GP_DANGLING_MIN_PX` screen
#   pixels for every zoom below the crossover (~4.29x), and the real millimetre width above it.
# [return] max(GP_DANGLING_WIDTH_MM, GP_DANGLING_MIN_PX / zoom) —— 交叉点（约 4.29×）以下恒为
#   `GP_DANGLING_MIN_PX` 屏幕像素，交叉点以上为真实毫米宽度。
# WHY A FUNCTION AND NOT AN INLINE maxf / 为何做成函数而非内联 maxf：
# the previous inline form was `maxf(1.5, 1.5 / zoom)`. The 1.5 on the LEFT is a WORLD-unit floor, so
# at zoom >= 1 it always won and the ring rendered 1.5 x zoom SCREEN pixels — ~4.2 px at the default
# fit-to-sheet zoom (~2.8x). The marker therefore got THICKER as you zoomed IN, the exact opposite of
# a screen-constant marker, and with NO error and NO symptom at zoom ~1 (where both forms agree at
# 1 px) it could pass review unnoticed. Extracting it lets several zooms be asserted headlessly, which
# the inline form could not.
# 此前的内联写法是 `maxf(1.5, 1.5 / zoom)`。左侧的 1.5 是**世界单位**地板，缩放 ≥1 时恒胜出，故圆环
# 渲染为 1.5 × zoom **屏幕像素** —— 默认「适配图幅」缩放（约 2.8×）下约 4.2px。即标记随放大**变粗**，
# 与「屏幕恒定的标记」完全相反；且 zoom≈1 时两种写法同为 1px，无报错、无征兆，极易通过审查。
# 抽成函数后可跨多个缩放做 headless 断言，内联写法做不到。
static func gpDanglingWidth(gpZoom: float) -> float:
	var gpZ: float = maxf(gpZoom, 0.01)
	return maxf(GP_DANGLING_WIDTH_MM, GP_DANGLING_MIN_PX / gpZ)


# Resolve the vertex count for the dangling-ring approximation at a zoom.
# 按缩放解析悬空端圆环逼近所用的顶点数。
# [return] ceil(2*PI*r_screen / GP_DANGLING_CHORD_PX), clamped to
#   [GP_DANGLING_SEG_MIN, GP_DANGLING_SEG_MAX].
# [return] ceil(2π·屏幕半径 / GP_DANGLING_CHORD_PX)，并夹在
#   [GP_DANGLING_SEG_MIN, GP_DANGLING_SEG_MAX] 内。
# WHY NOT A FIXED COUNT / 为何不用固定段数：
# a fixed 16 looks fine while the ring is small but turns visibly polygonal as it grows, because the
# sagitta scales with the radius: R*(1 - cos(PI/N)). Deriving the count from the ON-SCREEN radius
# holds the chord constant, so the sagitta SHRINKS as the ring grows — at 8x (radius 40 px,
# 84 segments) it is ~0.03 px, well under a pixel, versus ~0.77 px before.
# 固定的 16 在圆环小时看着没问题，但圆环变大后会显出多边形感 —— 因为矢高随半径线性增长：
# R*(1 - cos(π/N))。按**屏幕**半径取段数使弦长恒定，故矢高随圆环变大而**更小**：8× 时（屏幕半径
# 40px、84 段）约 0.03px，远低于 1 像素，而此前约 0.77px。
static func gpDanglingSegments(gpZoom: float) -> int:
	var gpZ: float = maxf(gpZoom, 0.01)
	var gpScreenR: float = GP_DANGLING_R_MM * gpZ
	var gpWant: int = int(ceil(TAU * gpScreenR / GP_DANGLING_CHORD_PX))
	return clampi(gpWant, GP_DANGLING_SEG_MIN, GP_DANGLING_SEG_MAX)


# Mark a free (dangling) end with a hollow ring — the drafting convention for "continues
# elsewhere / to be connected later", and the only way to SEE that an end is unbound.
# 用空心圆环标记悬空端 —— 这是「延续他页 / 待接」的制图约定，也是唯一能「看见」某端未绑定的方式。
# The stroke comes from gpDanglingWidth(), so the ring holds a constant on-screen weight instead of
# fattening as the view zooms in; the segment count comes from gpDanglingSegments(), so it stays
# round instead of turning into a polygon as the ring grows. Antialiased because that stroke weight
# is only ~1.5 px, where a non-antialiased arc reads as jagged.
# 描边取自 gpDanglingWidth()，故圆环屏幕宽度恒定、不随视图放大变粗；段数取自 gpDanglingSegments()，
# 故圆环画大后仍是圆而非多边形。开启抗锯齿是因为该描边宽度仅约 1.5px，非抗锯齿的圆弧会读作锯齿状。
static func gpDrawDangling(gpCv: CanvasItem, gpPos: Vector2, gpColor: Color, gpZoom: float) -> void:
	if gpCv == null:
		return
	var gpW: float = gpDanglingWidth(gpZoom)
	gpCv.draw_arc(gpPos, GP_DANGLING_R_MM, 0.0, TAU, gpDanglingSegments(gpZoom), gpColor, gpW, true)


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


# Draw the line number. Reads its placement straight from the geometry record computed by
# GPEdgeView.gpTagGeometry() — text, font, fit, world position, rotation are all decided there,
# so the painter never re-measures or re-places; it just stamps the glyph.
# 绘制管线编号。其落位直接取自 GPEdgeView.gpTagGeometry() 算出的几何记录 —— 文字、字体、字号、
# 世界坐标与旋转都在那里决定，绘制器不再自行测量或落位，只负责「盖章」字形。
# [param gpGeo] placement record from GPEdgeView.gpTagGeometry
#   (keys: text / font / fit / scale / pos / rot / size) / 来自 GPEdgeView.gpTagGeometry 的落位记录
# [return] the text bounding rectangle in world coordinates, so callers can use it for
#   hit-testing or overlap avoidance.
# [return] 文字包围矩形（世界坐标），供调用方做命中测试或避让。
static func gpDrawTag(gpCv: CanvasItem, gpGeo: Dictionary, gpColor: Color) -> Rect2:
	if gpCv == null or gpGeo.is_empty():
		return Rect2()
	var gpText: String = str(gpGeo.get("text", ""))
	if gpText == "":
		return Rect2()
	var gpFont: Font = gpGeo.get("font", ThemeDB.fallback_font) as Font
	var gpFit: Vector2 = gpGeo.get("fit", Vector2.ONE)
	var gpPos: Vector2 = gpGeo.get("pos", Vector2.ZERO)
	var gpRot: float = float(gpGeo.get("rot", 0.0))
	var gpScale: float = float(gpGeo.get("scale", 1.0))
	var gpFontPx: int = int(gpFit.x)
	# One frame for both orientations: its ORIGIN is the placement (world units) and its unit is one
	# design pixel, so the glyph bitmap is produced at exactly the size it occupies on screen. The
	# rotation rides in the same transform, which is why the horizontal and vertical cases no longer
	# need separate draw paths. The transform also carries the rounding residual (see gpFontFit), so
	# the painted glyph height is the authored sheet height and not the integer it had to round to.
	# 两种朝向共用同一变换：原点为布局位置（世界单位），单位为 1 设计像素，故字模按其**实际屏幕
	# 尺寸**生成。旋转也由同一变换承载 —— 这正是水平与竖直两种情形不再需要分别绘制的原因。变换同时
	# 带上取整残差（见 gpFontFit），故画出的字高是作者设定的图面字高，而非不得不取整到的那个整数。
	gpCv.draw_set_transform(gpPos, gpRot, GPCanvasText.gpTextScale(gpFit, gpScale))
	gpCv.draw_string_outline(gpFont, Vector2.ZERO, gpText, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		gpFontPx, GP_TEXT_OUTLINE, Color(0.0, 0.0, 0.0, 0.65))
	gpCv.draw_string(gpFont, Vector2.ZERO, gpText, HORIZONTAL_ALIGNMENT_LEFT, -1.0, gpFontPx, gpColor)
	# Restore the identity so every later draw call on this canvas item is unaffected.
	# 复位为单位变换，使本画布项之后的每次绘制不受影响。
	gpCv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return Rect2(gpPos, gpGeo.get("size", Vector2.ZERO))


# Draw the LEADER of a dragged-away number: a slanted segment from the pipe down to a horizontal
# shoulder under the text, stroked as ONE polyline. An empty array draws nothing, so a number
# still sitting close to its pipe shows no spurious line.
# 绘制被拖离编号的引出线：自管线到文字下方水平肩线的斜段，作为**一条**折线描画。空数组不绘制，
# 使贴着管线的编号不会出现多余的线。
# [param gpLeader] polyline [point_on_pipe, shoulder_elbow, shoulder_tail] from GPEdgeTagLayout
#   / 来自 GPEdgeTagLayout 的折线 [管上点, 肩线拐点, 肩线末端]
# The line is in WORLD coordinates (the edge view draws in world units), so its width is divided by
# the zoom to hold a constant GP_LEADER_MIN_PX screen pixels — and being thinner than the shared
# GPEdgeStyle.GP_MIN_PX floor is what keeps it the lightest line on the sheet.
# 该线处于世界坐标（边视图以世界单位绘制），故宽度除以缩放以保持恒定的 GP_LEADER_MIN_PX 屏幕像素
# —— 且比共用的 GPEdgeStyle.GP_MIN_PX 下限更细，这正是使它成为图面上最轻线条的原因。
static func gpDrawLeader(gpCv: CanvasItem, gpLeader: PackedVector2Array, gpColor: Color, gpZoom: float) -> void:
	if gpCv == null or gpLeader.size() < 2:
		return
	var gpZ: float = maxf(gpZoom, 0.01)
	var gpW: float = maxf(GP_LEADER_WIDTH_MM, GP_LEADER_MIN_PX / gpZ)
	gpCv.draw_polyline(gpLeader, gpColor, gpW)
