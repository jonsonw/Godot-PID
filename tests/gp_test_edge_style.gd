extends "res://tests/gp_test.gd"
# Headless tests for GPEdgeStyle (P1 of the connection feature).
# 连线功能 P1 —— GPEdgeStyle 的 headless 测试。
#
# Drafting rule under test (see docs/ADR/2026-09-11-ADR-UI-02-线型语义.md):
#   - PROCESS stays a SOLID CONTINUOUS line; line weight is its only visual distinction.
#   - UTILITY adopts the AutoCAD DASHED convention so utility mains read as dashed.
# The style sheet is a pure function so that restyling is a one-line edit instead of a
# migration over every saved archive.
# 被测的制图规则（见 docs/ADR/2026-09-11-ADR-UI-02-线型语义.md）：
#   - PROCESS 仍用实线 CONTINUOUS，线宽是其唯一可见区分手段。
#   - UTILITY 采用 AutoCAD DASHED 惯例，使公用工程主线呈虚线。
# 样式表是纯函数，改样式即一行编辑，不必遍历每个存档做迁移。


func gpTestMainProcessIsThickerThanUtility() -> void:
	# Sample at a zoom where the 1.2px screen floor does NOT engage, so the declared
	# millimetre widths (ISO multi-weight) pass through verbatim. At 100% zoom both widths
	# fall under the floor and would be lifted to the same pixel width.
	# 在屏幕下限（1.2px）不生效的缩放下取样，使声明的毫米线宽（ISO 多级）原样透传。
	# 100% 缩放下两者都低于下限，会被抬到同一像素宽度。
	var gpZoom: float = 5.0
	var gpMain: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_PROCESS, "", gpZoom)
	var gpUtil: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_UTILITY, "", gpZoom)
	gpApprox(float(gpMain["width"]), 0.30, 0.0001, "main process line is 0.30 mm wide")
	gpApprox(float(gpUtil["width"]), 0.25, 0.0001, "utility line is 0.25 mm wide")
	gpCheck(float(gpMain["width"]) > float(gpUtil["width"]),
		"the main line must be visibly thicker than the utility line")


# Per ADR-UI-02: PROCESS is solid (CONTINUOUS), UTILITY is dashed (DASHED).
# 按 ADR-UI-02：PROCESS 实线（CONTINUOUS），UTILITY 虚线（DASHED）。
func gpTestProcessSolidAndUtilityDashed() -> void:
	var gpMain: PackedFloat32Array = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_PROCESS, "", 1.0)["pattern"]
	var gpUtil: PackedFloat32Array = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_UTILITY, "", 1.0)["pattern"]
	gpCheck((gpMain as PackedFloat32Array).is_empty(),
		"process lines stay solid (CONTINUOUS)")
	gpCheck(not (gpUtil as PackedFloat32Array).is_empty(),
		"utility lines are dashed (DASHED, per ADR-UI-02)")


func gpTestSignalLineTypes() -> void:
	gpEq(GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "ELECTRIC", 1.0)["pattern"],
		PackedFloat32Array([10.0, 3.0, 2.0, 3.0]), "electric is dash-dot")
	gpEq(GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "PNEUMATIC", 1.0)["pattern"],
		PackedFloat32Array([6.0, 4.0]), "pneumatic is a short dash")
	gpEq(GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "HYDRAULIC", 1.0)["pattern"],
		PackedFloat32Array([10.0, 3.0, 2.0, 3.0, 2.0, 3.0]), "hydraulic is dash-dot-dot")
	gpEq(GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "DATA", 1.0)["pattern"],
		PackedFloat32Array([2.0, 4.0]), "DCS data link is a dense dot")
	gpEq(GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "CAPILLARY", 1.0)["pattern"],
		PackedFloat32Array([12.0, 4.0]), "capillary is a long dash")


# Unknown input must still produce something drawable, and never an empty dictionary.
# 未知输入必须仍能产出可绘制的样式，且绝不返回空字典。
func gpTestUnknownKindFallsBack() -> void:
	var gpS: Dictionary = GPEdgeStyle.gpStyleFor("WHATEVER", "", 1.0)
	gpCheck(gpS.has("width") and gpS.has("color") and gpS.has("pattern"),
		"the fallback style still carries all three keys")
	gpCheck(float(gpS["width"]) > 0.0, "the fallback width is positive")
	gpCheck((gpS["pattern"] as PackedFloat32Array).is_empty(), "the fallback is a solid line")
	var gpS2: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "UNKNOWN_MEDIUM", 1.0)
	gpCheck(float(gpS2["width"]) > 0.0, "an unknown signal type still draws")
	gpCheck(not (gpS2["pattern"] as PackedFloat32Array).is_empty(),
		"an unknown signal type keeps a pattern so it reads as a signal line")


# Millimetre widths shrink with zoom; without a floor a 0.30 mm main line would be 0.075px at
# 25% and indistinguishable from a utility line.
# 毫米线宽随缩放变细；没有下限，0.30 mm 的主管线在 25% 时只有 0.075px，与公用工程线无法区分。
func gpTestScreenFloorAppliesWhenZoomedOut() -> void:
	var gpS: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_UTILITY, "", 0.25)
	gpCheck(float(gpS["width"]) * 0.25 >= GPEdgeStyle.GP_MIN_PX - 0.0001,
		"the on-screen width never drops below the floor")
	var gpS2: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "ELECTRIC", 0.1)
	for gpV in (gpS2["pattern"] as PackedFloat32Array):
		gpCheck(gpV * 0.1 >= GPEdgeStyle.GP_MIN_DASH_PX - 0.0001,
			"a single dash never drops below the pixel floor")


func gpTestFloorDoesNotInflateAtNormalZoom() -> void:
	var gpS: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "ELECTRIC", 1.0)
	gpEq(gpS["pattern"], PackedFloat32Array([10.0, 3.0, 2.0, 3.0]),
		"at 100% the declared dash lengths are used verbatim")


func gpTestPortColorsAreDistinct() -> void:
	gpCheck(GPEdgeStyle.gpPortColor(GPPort.GP_NOZZLE) != GPEdgeStyle.gpPortColor(GPPort.GP_SIGNAL),
		"a process nozzle and a signal terminal must not share a colour")
	gpCheck(GPEdgeStyle.gpPortColor(GPPort.GP_ACTUATOR) != GPEdgeStyle.gpPortColor(GPPort.GP_SIGNAL),
		"an actuator and a signal terminal must not share a colour")
	gpCheck(GPEdgeStyle.gpPortColor("NONSENSE") == GPEdgeStyle.gpPortColor(GPPort.GP_TERMINAL),
		"an unknown purpose falls back to the generic terminal colour")


func gpTestLineTypeKeys() -> void:
	gpEq(GPEdgeStyle.gpLineTypeKey(GPPIDEdge.GP_PROCESS, ""), "line_type_process",
		"process lines have their own i18n key")
	gpEq(GPEdgeStyle.gpLineTypeKey(GPPIDEdge.GP_SIGNAL, "PNEUMATIC"), "line_type_pneumatic",
		"pneumatic signal lines have their own i18n key")


# The dangling-end ring is a MARKER: its stroke must hold a constant on-screen weight instead of
# fattening as the view zooms in. The earlier inline `maxf(1.5, 1.5 / zoom)` put a WORLD-unit floor
# on the LEFT of the maxf, so at zoom >= 1 it always won and the ring rendered `1.5 * zoom` SCREEN
# pixels — ~4.2 px at the default fit-to-sheet zoom (~2.8x) versus ~1.5 px intended.
# 悬空端圆环是**标记**：其描边在屏幕上应保持恒定粗细，而非随视图放大变粗。此前的内联
# `maxf(1.5, 1.5 / zoom)` 把**世界单位**地板放在 maxf **左侧**，缩放 ≥1 时恒胜出，故圆环渲染为
# `1.5 × zoom` **屏幕像素** —— 默认「适配图幅」缩放（约 2.8×）下约 4.2px，而设计意图是约 1.5px。
func gpTestDanglingRingStaysScreenConstant() -> void:
	# Every zoom below the crossover, including the 2.8x the app fits an A3 sheet with.
	# 取交叉点以下的各档缩放，含应用适配 A3 图幅所用的约 2.8×。
	var gpZooms: Array[float] = [0.5, 1.0, 2.0, 2.8, 4.0]
	for gpZoom: float in gpZooms:
		var gpW: float = GPEdgePainter.gpDanglingWidth(gpZoom)
		gpApprox(gpW * gpZoom, GPEdgePainter.GP_DANGLING_MIN_PX, 1e-4,
			"ring stroke holds its pixel floor at zoom %.1f" % gpZoom)
	# Regression guard for the defective form: it returned the SAME world width at every zoom, so the
	# on-screen weight grew linearly with zoom. The corrected rule must therefore return a world
	# width that SHRINKS as zoom grows.
	# 缺陷写法的回归守卫：它在任何缩放下都返回同一个**世界**宽度，故屏幕宽度随缩放线性增长。修正后
	# 的规则因此必须返回一个随缩放**变小**的世界宽度。
	gpCheck(GPEdgePainter.gpDanglingWidth(2.8) < GPEdgePainter.gpDanglingWidth(1.0),
		"world width shrinks as zoom grows (i.e. the screen weight is constant)")
	# The concrete symptom the user would have seen: at fit-to-sheet zoom the ring used to be far
	# thicker than the 1.2 px floor that the thinnest pipe is allowed to reach.
	# 用户会看到的具体症状：适配图幅缩放下，圆环此前远粗于最细管线所允许达到的 1.2px 下限。
	gpCheck(GPEdgePainter.gpDanglingWidth(2.8) * 2.8 < GPEdgeStyle.GP_MIN_PX * 2.0,
		"the ring no longer renders several times the thinnest pipe's width")


# Above the crossover the screen floor stops dominating and the real millimetre width takes over, so
# a plotted sheet carries an ISO-tier line rather than a zoom-dependent hairline.
# 交叉点以上屏幕下限不再主导，由真实毫米宽度接管，使出图得到 ISO 档线宽而非随缩放漂移的细线。
func gpTestDanglingRingHasWorldFloorAtHighZoom() -> void:
	var gpCross: float = GPEdgePainter.GP_DANGLING_MIN_PX / GPEdgePainter.GP_DANGLING_WIDTH_MM
	gpCheck(gpCross > 1.0 and gpCross < 8.0,
		"the crossover sits inside the app's zoom range, so both tiers are reachable")
	gpApprox(GPEdgePainter.gpDanglingWidth(8.0), GPEdgePainter.GP_DANGLING_WIDTH_MM, 1e-4,
		"at maximum zoom the ring falls back to its real millimetre width")
	gpCheck(GPEdgePainter.GP_DANGLING_WIDTH_MM > 0.0
			and GPEdgePainter.GP_DANGLING_WIDTH_MM <= 0.5,
		"the world width is a plausible ISO tier, not a pixel-era leftover")
	# A degenerate zoom must not divide by zero. / 退化缩放不得除零。
	gpCheck(GPEdgePainter.gpDanglingWidth(0.0) > 0.0, "zoom 0 is clamped, not a division by zero")


# The rule lives in ONE function so it can be asserted at several zooms. Inlining a `maxf` back into
# the draw call would silently reintroduce the bug — its only symptom appears at zoom > 1.
# 该规则只存在于**一个**函数中，故可跨多个缩放断言。若把 `maxf` 重新内联回绘制调用，会静默复现该
# 缺陷 —— 其唯一征兆只在 zoom > 1 时出现。
func gpTestDanglingDrawCallUsesNamedRules() -> void:
	var gpSrc: String = FileAccess.get_file_as_string("res://src/render/edge_painter.gd")
	var gpAt: int = gpSrc.find("static func gpDrawDangling")
	gpCheck(gpAt >= 0, "gpDrawDangling is present in the painter")
	# Just the function body, stopping well before the next function (which has no maxf of its own).
	# 仅取函数体，远早于下一个函数（后者自身没有 maxf）处截断。
	var gpBody: String = gpSrc.substr(gpAt, 400)
	gpCheck(gpBody.contains("gpDanglingWidth(gpZoom)"),
		"the draw call takes its width from the single-source helper")
	gpCheck(gpBody.contains("gpDanglingSegments(gpZoom)"),
		"the draw call takes its segment count from the same single-source rule")
	gpCheck(not gpBody.contains("maxf(1.5"),
		"no world-unit floor literal is inlined in the draw call")
	# The radius must be passed by its mm-explicit constant: a bare `5.0` here is what let the unit
	# live only in a comment. / 半径必须由带 mm 的常量传入：此处裸写 `5.0` 正是「单位只存在于注释里」的成因。
	gpCheck(gpBody.contains("GP_DANGLING_R_MM"),
		"the radius is passed by its mm-explicit constant")
	gpCheck(not gpSrc.contains("GP_DANGLING_R:") and not gpSrc.contains("GP_DANGLING_R,"),
		"the unit-ambiguous bare constant name is retired")


# Item 1 (a user decision, not a defect): the radius is a MILLIMETRE dimension, and its value is
# deliberately NOT reduced to a "standard drawing" size. This test exists because the unit is the
# whole point — a bare `5.0` had been read as a pixel-era leftover precisely because the unit lived
# only in a comment.
# 第 1 点（用户决定，非缺陷）：半径是**毫米**量纲，其数值刻意**不**按「标准图」尺寸缩小。本测试的
# 意义在于单位本身 —— 此前裸写 `5.0` 正是因单位只存在于注释里而被读成像素时代的遗留值。
func gpTestDanglingRadiusIsMillimetres() -> void:
	gpApprox(GPEdgePainter.GP_DANGLING_R_MM, 5.0, 1e-6,
		"the radius keeps its value — a unit clarification, not a resize")
	gpCheck(GPEdgePainter.GP_DANGLING_R_MM > 1.0,
		"the radius is a drawing dimension in mm, not a pixel-era small value")
	# A drawing feature scales WITH the sheet: 5 mm x zoom on screen, unlike the screen-constant stroke.
	# 图面要素随图幅缩放：屏幕上为 5mm × 缩放，与屏幕恒定的描边不同。
	gpApprox(GPEdgePainter.GP_DANGLING_R_MM * 2.8, 14.0, 1e-4,
		"the ring spans 28 px at the default fit-to-sheet zoom")


# Item 2: draw_arc() takes a FIXED segment count, so a count chosen for a small ring turns visibly
# polygonal once the ring is drawn large — the sagitta grows with the radius as R*(1 - cos(PI/N)).
# Deriving the count from the ON-SCREEN radius holds the chord constant, so the ring stays round.
# 第 2 点：draw_arc() 只接受**固定**段数，故为小圆环选的段数在圆环画大后会显出多边形感 —— 矢高按
# R*(1 - cos(π/N)) 随半径增长。改为按**屏幕**半径推导，使弦长恒定，圆环因此保持圆形。
func gpTestDanglingSegmentsStayRoundAsRingGrows() -> void:
	var gpZooms: Array[float] = [0.5, 1.0, 2.8, 4.0, 8.0]
	var gpPrev: int = 0
	for gpZoom: float in gpZooms:
		var gpN: int = GPEdgePainter.gpDanglingSegments(gpZoom)
		gpCheck(gpN >= GPEdgePainter.GP_DANGLING_SEG_MIN,
			"never fewer than the floor at zoom %.1f" % gpZoom)
		gpCheck(gpN <= GPEdgePainter.GP_DANGLING_SEG_MAX,
			"never more than the ceiling at zoom %.1f" % gpZoom)
		gpCheck(gpN >= gpPrev, "the count never decreases as the ring grows (zoom %.1f)" % gpZoom)
		gpPrev = gpN
	# The count must actually grow, otherwise the fixed-count problem has merely been renamed.
	# 段数必须真的增长，否则只是把「固定段数」的问题改了名。
	gpCheck(GPEdgePainter.gpDanglingSegments(8.0) > GPEdgePainter.gpDanglingSegments(1.0) * 2,
		"the segment count scales with the on-screen radius")
	# The payoff, measured in pixels. / 以像素量化收益。
	var gpR: float = GPEdgePainter.GP_DANGLING_R_MM * 8.0
	var gpN8: float = float(GPEdgePainter.gpDanglingSegments(8.0))
	var gpSag: float = gpR * (1.0 - cos(PI / gpN8))
	gpCheck(gpSag < 0.1, "round to within a tenth of a pixel at maximum zoom")
	# And the superseded fixed 16 was demonstrably an order of magnitude coarser there — the reason
	# this change was made at all.
	# 且被取代的固定 16 段在该缩放下确实粗了一个数量级 —— 这正是本次改动的理由。
	gpCheck(gpR * (1.0 - cos(PI / 16.0)) > gpSag * 10.0,
		"the superseded fixed-16 count was far coarser at maximum zoom")
	# A degenerate zoom must not yield a zero / negative / unbounded count.
	# 退化缩放不得产生零 / 负 / 无界的段数。
	gpCheck(GPEdgePainter.gpDanglingSegments(0.0) >= GPEdgePainter.GP_DANGLING_SEG_MIN,
		"zoom 0 is clamped, not a zero count")
