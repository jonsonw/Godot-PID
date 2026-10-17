extends "res://tests/gp_test.gd"
# Frame geometry tests (Rev.3 stages 0a + 0b) — the PURE "where is the frame?" module.
# 图框几何测试（Rev.3 阶段 0a + 0b）—— 纯函数模块「图框在哪？」。
# The failure modes being guarded against:
# 所防范的失效模式：
# 1. The frame rectangle gets re-derived at each call site, so the renderer strokes one rectangle
#    and the hit-test reasons about another — the user then grabs something invisible.
#    图框矩形在每个调用点各推一次，导致渲染器描一个矩形、命中判定依据另一个 —— 用户抓到一个
#    看不见的东西。
# 2. The frame escapes the paper: dragged off the edge, or carrying an out-of-range archive value.
#    图框跑出纸面：被拖到边上，或带着越界的存档取值。
# 3. The title block's DEFAULT position silently shifts, so every existing drawing moves.
#    图签**默认**位置被悄悄挪动，使每一张既有图纸发生位移。
# 4. The ZONE RULER drifts away from the frame it hangs off — ticks bolted to the paper while the
#    frame slides, or a division count that no longer matches the reference drawing.
#    坐标带与所依附的图框脱节 —— 刻度钉在纸上而图框滑走，或分格数与参照图不再一致。
# These are the only assertions about this module's geometry, so it is headless and needs no canvas.
# 这是本模块几何的唯一断言来源，故可 headless 运行、无需画布。

const GP_A3_W: float = 420.0
const GP_A3_H: float = 297.0
const GP_EPS: float = 0.0001

# The reference drawing's own margins: a symmetric 4 mm template (DEXPI Example C01), NOT this
# project's 25/5/5/5 binding-edge default. Every "reference" assertion below uses this one, so the
# measured numbers from `图框及注释/05_输入/图框.svg` can be compared directly.
# 参照图自己的边距：对称 4mm 模板（DEXPI 示例 C01），**不是**本项目的 25/5/5/5 装订边默认值。
# 下文每条「参照」断言都用它，以便与 `图框及注释/05_输入/图框.svg` 的实测数值直接比对。
const GP_REF_MARGINS: Array = [4.0, 4.0, 4.0, 4.0]

# A fresh A3 sheet with the standard margins. / 带标准边距的全新 A3 图纸。
# ⚠️ A1 REBASE (2026-10-16): gpNew() now starts on A1 (841 x 594, margins 25/10/10/10), but every
# assertion in this file reasons about the A3-ERA reference drawing — paper size and margins are
# INPUTS here, not defaults under test. The helper therefore pins A3 explicitly, and the NEW
# default's own contract is pinned by gpTestNewDefaultSheetIsA1 in gp_test_sheet_frame.gd.
# ⚠️ A1 重定基（2026-10-16）：gpNew() 现以 A1 起步（841×594，边距 25/10/10/10），但本文件每条断言
# 都以 A3 时代参照图推理 —— 纸幅与边距在此是**输入**、不是被测的默认值。故本 helper 显式钉回 A3；
# 新默认自身的契约由 gp_test_sheet_frame.gd 的 gpTestNewDefaultSheetIsA1 钉住。
func _gpA3() -> GPSheet:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpWidthMM = GP_A3_W
	gpS.gpHeightMM = GP_A3_H
	gpS.gpSetFrameMargins(GPSheet.GP_FRAME_MARGINS_DEFAULT)
	return gpS


# A fresh A3 sheet carrying the reference drawing's margins. / 带参照图边距的全新 A3 图纸。
func _gpA3Ref() -> GPSheet:
	var gpS: GPSheet = _gpA3()
	gpS.gpSetFrameMargins(GP_REF_MARGINS)
	return gpS


# Element-wise margin comparison with a tolerance. Written out rather than using `==` so the test
# does not depend on Array equality semantics, and so float noise cannot make it flaky.
# 逐项比较边距（带容差）。显式写出而不用 `==`，使测试不依赖 Array 的相等语义，也避免浮点噪声
# 造成偶发失败。
func _gpSameMargins(gpGot: Array, gpWant: Array) -> bool:
	if gpGot.size() != gpWant.size():
		return false
	for gpI in gpWant.size():
		if absf(float(gpGot[gpI]) - float(gpWant[gpI])) > GP_EPS:
			return false
	return true


# A3 with the standard margins: 420-25-5 = 390 wide, 297-5-5 = 287 tall, top-left at (25, 5).
# A3 + 标准边距：宽 420−25−5 = 390，高 297−5−5 = 287，左上角 (25, 5)。
func gpTestDefaultFrameRectIsA3Inner() -> void:
	var gpR: Rect2 = GPFrameGeometry.gpFrameRect(_gpA3())
	gpApprox(gpR.position.x, 25.0, GP_EPS, "内框左边界应为装订边 25mm")
	gpApprox(gpR.position.y, 5.0, GP_EPS, "内框上边界应为 5mm")
	gpApprox(gpR.size.x, 390.0, GP_EPS, "内框宽应为 390mm")
	gpApprox(gpR.size.y, 287.0, GP_EPS, "内框高应为 287mm")


# The frame IS the paper minus the margins — one derivation, no call-site arithmetic.
# 内框**就是**纸面减去边距 —— 一处推导，调用点不做算术。
func gpTestFrameRectIsPaperMinusMargins() -> void:
	var gpS: GPSheet = _gpA3()
	gpS.gpSetFrameMargins([12.0, 7.0, 9.0, 4.0])
	var gpR: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	gpApprox(gpR.position.x, 12.0, GP_EPS, "内框左 = 左边距")
	gpApprox(gpR.position.y, 7.0, GP_EPS, "内框上 = 上边距")
	gpApprox(gpR.size.x, GP_A3_W - 12.0 - 9.0, GP_EPS, "内框宽 = 纸宽 − 左 − 右")
	gpApprox(gpR.size.y, GP_A3_H - 7.0 - 4.0, GP_EPS, "内框高 = 纸高 − 上 − 下")


# The frame IS the paper minus the margins — and since the 2026-10-16 amendment it may lie OUTSIDE the
# paper, so what is pinned here is the DERIVATION for values that put it there, not a paper bound.
# 内框**就是**纸面减去边距 —— 且自 2026-10-16 修正起它可以落在纸面**之外**，故此处钉的是这条推导在「把
# 图框推到纸外」的取值下依然成立，而不是一道纸面约束。
#
# ⚠️ THIS REPLACED gpTestFrameRectNeverEscapesThePaper, WHICH ASSERTED THE OPPOSITE (2026-10-16). That
# test required every margin, however absurd, to be clamped until the rectangle was a subset of the
# paper. It is now false BY DESIGN: the user asked for free movement with no limits (「自由移动，没有限制」),
# so the paper stopped being a container. The guarantee that survives is the frame's own consistency —
# the inner rectangle must not turn inside out (pinned by gpTestFrameMayCrossTheTrimLineAndNeverCollapses).
# ⚠️ 本测试替代 gpTestFrameRectNeverEscapesThePaper，后者断言的是相反的东西（2026-10-16）。它要求任何
# 荒唐边距都被钳到矩形成为纸面子集为止。如今这**按设计为假**：用户要求无限制的自由移动（「自由移动，没有
# 限制」），纸面因此不再是容器。活下来的保证是图框自身的自洽 —— 内框不得内翻（由
# gpTestFrameMayCrossTheTrimLineAndNeverCollapses 钉住）。
func gpTestFrameRectFollowsTheMarginsOffThePaper() -> void:
	var gpCases: Array = [
		[[0.0, 0.0, 0.0, 0.0], Rect2(0.0, 0.0, 420.0, 297.0)],
		[[12.0, 7.0, 9.0, 4.0], Rect2(12.0, 7.0, 399.0, 286.0)],
		[[-100.0, -100.0, -100.0, -100.0], Rect2(-100.0, -100.0, 620.0, 497.0)],
		[[-50.0, 5.0, 5.0, 5.0], Rect2(-50.0, 5.0, 465.0, 287.0)],
		[[500.0, 5.0, -400.0, 5.0], Rect2(500.0, 5.0, 320.0, 287.0)],
	]
	for gpC in gpCases:
		var gpWant: Rect2 = gpC[1]
		var gpR: Rect2 = GPFrameGeometry.gpInnerRect(GP_A3_W, GP_A3_H, gpC[0])
		gpApprox(gpR.position.x, gpWant.position.x, GP_EPS,
			"边距 %s：内框左 = 左边距（可为负）" % [str(gpC[0])])
		gpApprox(gpR.position.y, gpWant.position.y, GP_EPS,
			"边距 %s：内框上 = 上边距（可为负）" % [str(gpC[0])])
		gpApprox(gpR.size.x, gpWant.size.x, GP_EPS,
			"边距 %s：内框宽 = 纸宽 − 左 − 右" % [str(gpC[0])])
		gpApprox(gpR.size.y, gpWant.size.y, GP_EPS,
			"边距 %s：内框高 = 纸高 − 上 − 下" % [str(gpC[0])])
	# A frame genuinely off the paper is not a hypothetical: the last case has its left edge at 500 mm on a
	# 420 mm sheet, i.e. the WHOLE rectangle lies to the right of the paper — which is what "free movement"
	# looks like once it is spelled out.
	# 图框真的落在纸外不是假设：最后一种情形的左边在 420mm 的纸上位于 500mm 处，即**整个**矩形都在纸右 ——
	# 这就是「自由移动」摊开来说的样子。
	var gpOff: Rect2 = GPFrameGeometry.gpInnerRect(GP_A3_W, GP_A3_H, gpCases[4][0])
	gpCheck(gpOff.position.x > GP_A3_W,
		"左边距 500mm 时整个内框应在纸右之外（实测左边 %.1f > 纸宽 %.1f）" % [gpOff.position.x, GP_A3_W])
	# And the outward-expanded case WRAPS the paper instead of fitting inside it.
	# 而「向外扩张」的情形把纸面**包在内部**，而不是装在里面。
	var gpWrap: Rect2 = GPFrameGeometry.gpInnerRect(GP_A3_W, GP_A3_H, gpCases[2][0])
	gpCheck(gpWrap.position.x < 0.0 and gpWrap.end.x > GP_A3_W,
		"四边均为 −100mm 时内框应把纸面包在内部（实测 %.1f .. %.1f）"
			% [gpWrap.position.x, gpWrap.end.x])

	# ⚠️ THE COLLAPSE GUARD IS THE ONLY THING STILL APPLIED, AND IT IS APPLIED TO THE PAIR — not to any
	# single margin. 800 + 800 on a 420 sheet leaves nothing, so the pair is scaled back until the inner
	# width is exactly the minimum; each margin stays far above it, which is precisely why this rule
	# cannot be written as a per-element clamp.
	# ⚠️ 仍在生效的只剩**防塌缩**那道护栏，且它作用于**成对**边距 —— 不是任何单条边距。420 纸上 800+800
	# 什么都不剩，故该对被回缩到内框宽恰好等于最小值；而单看每条边距都远高于它 —— 这正是这条规则无法写成
	# 逐元素钳制的原因。
	var gpFat: Rect2 = GPFrameGeometry.gpInnerRect(GP_A3_W, GP_A3_H, [800.0, 0.0, 800.0, 0.0])
	gpApprox(gpFat.size.x, GPSheet.GP_FRAME_MIN_SIZE_MM, GP_EPS,
		"800+800 应被回缩到恰好留下最小内框宽")
	gpCheck(float(GPSheet.gpClampMargins([800.0, 0.0, 800.0, 0.0], GP_A3_W, GP_A3_H)[0]) > 1.0,
		"回缩后单条左边距应远高于最小值 —— 故该规则不可能写成逐元素下限")


# The clamp is idempotent, which is what lets callers clamp defensively without changing the answer.
# 钳制是幂等的 —— 这正是调用方可以放心地再钳一次而答案不变的原因。
func gpTestMarginClampIsIdempotent() -> void:
	var gpCases: Array = [
		[25.0, 5.0, 5.0, 5.0],
		[300.0, 300.0, 300.0, 300.0],
		[-5.0, -5.0, -5.0, -5.0],
	]
	for gpC in gpCases:
		var gpOnce: Array = GPSheet.gpClampMargins(gpC, GP_A3_W, GP_A3_H)
		var gpTwice: Array = GPSheet.gpClampMargins(gpOnce, GP_A3_W, GP_A3_H)
		gpCheck(_gpSameMargins(gpOnce, gpTwice),
			"边距 %s 钳制两次应与钳制一次相同" % [str(gpC)])


# A malformed margins array degrades to the standard default instead of poisoning every consumer.
# 格式不对的边距数组应回落到标准默认值，而不是污染每个消费方。
func gpTestMalformedMarginsFallBackToDefault() -> void:
	gpCheck(_gpSameMargins(GPFrameGeometry.gpMargins(null), GPSheet.GP_FRAME_MARGINS_DEFAULT),
		"无图纸时应回落默认边距")
	var gpS: GPSheet = _gpA3()
	gpS.gpFrameMargins = [1.0, 2.0]
	gpCheck(_gpSameMargins(GPFrameGeometry.gpMargins(gpS), GPSheet.GP_FRAME_MARGINS_DEFAULT),
		"长度不足的边距数组应回落默认，而非产出错误矩形")
	gpEq(GPFrameGeometry.gpFrameRect(null), Rect2(), "无图纸时内框矩形应为空")
	gpEq(GPFrameGeometry.gpTitleBlockRect(null), Rect2(), "无图纸时图签矩形应为空")


# The title block's DEFAULT position: hugging the inner frame's bottom-right corner, exactly where
# v0.1 put it. Rev.3 stage 1 generalises this into "anchor corner + offset"; THIS assertion is what
# forces that generalisation to reduce to today's drawing for a zero offset on the bottom-right.
# 图签的**默认**位置：贴住内框右下角，与 v0.1 完全一致。Rev.3 阶段 1 把它推广为「锚角 + 偏移」；
# **本断言**正是迫使该推广在「右下角 + 零偏移」时退化为今天的图形。
func gpTestTitleBlockDefaultsToFrameBottomRight() -> void:
	var gpS: GPSheet = _gpA3()
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	var gpBlock: Rect2 = GPFrameGeometry.gpTitleBlockRect(gpS)
	gpApprox(gpBlock.size.x, GPSheet.GP_TB_BLOCK_W, GP_EPS, "图签宽应为标准值")
	gpApprox(gpBlock.size.y, GPSheet.GP_TB_BLOCK_H, GP_EPS, "图签高应为标准值")
	gpApprox(gpBlock.end.x, gpFrame.end.x, GP_EPS, "图签右边应贴合内框右边")
	gpApprox(gpBlock.end.y, gpFrame.end.y, GP_EPS, "图签下边应贴合内框下边")
	gpApprox(gpBlock.position.x, gpFrame.end.x - GPSheet.GP_TB_BLOCK_W, GP_EPS,
		"图签左上角 x = 内框右 − 图签宽（即 v0.1 的 gpOX）")
	gpApprox(gpBlock.position.y, gpFrame.end.y - GPSheet.GP_TB_BLOCK_H, GP_EPS,
		"图签左上角 y = 内框下 − 图签高")


# The margins are the ONLY input: the block is derived from the frame and never positioned
# absolutely, so moving the frame carries the block with it. This is the geometric half of Rev.3's
# core requirement ("a dragged title block must follow its frame"), and it is provable here, before
# any drag interaction exists.
# 边距是**唯一**输入：图签由图框推导、从不用绝对定位，故图框一动、图签随之而动。这是 Rev.3 核心
# 要求（「被拖过的图签必须跟着图框走」）的几何那一半，且在拖拽交互存在之前即可在此证明。
#
# ⚠️ DIRECTION MATTERS, and an earlier version of this test got it wrong: the block hugs the frame's
# BOTTOM-RIGHT corner, so only the RIGHT / BOTTOM margins can move it. Narrowing the binding edge
# moves the frame's LEFT edge and must leave the block exactly where it was. Both halves are
# asserted, because the second one is what proves the position is DERIVED rather than an absolute
# coordinate that merely happens to look right today.
# ⚠️ 方向很关键，本测试的初版就在这里判断错了：图签贴的是内框**右下**角，故只有**右 / 下**边距
# 能让它动。收窄装订边移动的是内框**左**边，图签必须原地不动。两半都断言，因为第二半才证明位置是
# **推导**出来的，而不是一个「今天恰好看着对」的绝对坐标。
func gpTestTitleBlockFollowsTheFrame() -> void:
	var gpS: GPSheet = _gpA3()
	var gpBefore: Rect2 = GPFrameGeometry.gpTitleBlockRect(gpS)
	# Right + bottom moved: the block must move with them, by exactly the same amount.
	# 右、下边距改变：图签必须同步移动，且位移量完全一致。
	gpS.gpSetFrameMargins([25.0, 5.0, 10.0, 12.0])
	var gpAfter: Rect2 = GPFrameGeometry.gpTitleBlockRect(gpS)
	gpApprox(gpAfter.end.x - gpBefore.end.x, -5.0, GP_EPS,
		"右边距由 5mm 增至 10mm，图签右边界应左移 5mm")
	gpApprox(gpAfter.end.y - gpBefore.end.y, -7.0, GP_EPS,
		"下边距由 5mm 增至 12mm，图签下边应上移 7mm")
	# The mirror case: moving ONLY the binding edge must NOT move the block.
	# 反向情形：只动装订边时图签**不得**移动。
	var gpS2: GPSheet = _gpA3()
	gpS2.gpSetFrameMargins([5.0, 5.0, 5.0, 5.0])
	var gpAfter2: Rect2 = GPFrameGeometry.gpTitleBlockRect(gpS2)
	gpApprox(gpAfter2.end.x, gpBefore.end.x, GP_EPS, "只缩短装订边时图签右边界不应移动")
	gpApprox(gpAfter2.end.y, gpBefore.end.y, GP_EPS, "只缩短装订边时图签下边不应移动")


# ---------------------------------------------------------------------------
# Zone ruler (分区格网) — Rev.3 stage 0b
# 分区格网 —— Rev.3 阶段 0b
# ---------------------------------------------------------------------------

# Is this point on the border of the rectangle? Written out rather than using Rect2.has_point(),
# whose edge semantics EXCLUDE the far edges — exactly the edges the ruler hangs off.
# 该点是否落在矩形边界上？显式写出而不用 Rect2.has_point()：后者的边界语义**排除**远边，而那正是
# 坐标带所依附的边。
func _gpOnFrameBorder(gpP: Vector2, gpFrame: Rect2) -> bool:
	var gpOnX: bool = absf(gpP.x - gpFrame.position.x) <= GP_EPS \
		or absf(gpP.x - gpFrame.end.x) <= GP_EPS
	var gpOnY: bool = absf(gpP.y - gpFrame.position.y) <= GP_EPS \
		or absf(gpP.y - gpFrame.end.y) <= GP_EPS
	var gpSpanX: bool = gpP.x >= gpFrame.position.x - GP_EPS and gpP.x <= gpFrame.end.x + GP_EPS
	var gpSpanY: bool = gpP.y >= gpFrame.position.y - GP_EPS and gpP.y <= gpFrame.end.y + GP_EPS
	return (gpOnX and gpSpanY) or (gpOnY and gpSpanX)


# Is this segment present in the list, in either direction?
# 该线段是否出现在列表中（方向不限）？
func _gpHasSegment(gpSegs: Array, gpA: Vector2, gpB: Vector2) -> bool:
	for gpS in gpSegs:
		var gpP: Vector2 = gpS[0]
		var gpQ: Vector2 = gpS[1]
		if gpP.distance_to(gpA) <= GP_EPS and gpQ.distance_to(gpB) <= GP_EPS:
			return true
		if gpP.distance_to(gpB) <= GP_EPS and gpQ.distance_to(gpA) <= GP_EPS:
			return true
	return false


# The division count must reproduce the reference drawing: A3 at its own 4 mm margins gives an inner
# frame of 412 x 289 mm, which the reference divides into 12 x 8. Both reference files agree on those
# numbers (`图框.svg`, and `svg_full_pid.svg`'s 40 grid labels), so this is a measurement, not a taste
# call — and it is the one assertion that would catch a "tidy up the count" refactor.
# 分格数必须复现参照图：A3 在其自身的 4mm 边距下内框为 412×289mm，参照图将其分为 12×8。两份参照
# 文件在这组数字上完全一致（`图框.svg`，以及 `svg_full_pid.svg` 的 40 个格网标号），故这是实测而
# 非口味问题 —— 也是唯一能抓住「顺手把分格数整理一下」这类重构的断言。
func gpTestZoneCountsReproduceTheReferenceDrawing() -> void:
	var gpF: Rect2 = GPFrameGeometry.gpFrameRect(_gpA3Ref())
	gpApprox(gpF.size.x, 412.0, GP_EPS, "参照图内框宽应为 412mm（420 − 4 − 4）")
	gpApprox(gpF.size.y, 289.0, GP_EPS, "参照图内框高应为 289mm（297 − 4 − 4）")
	gpEq(GPFrameGeometry.gpZoneCounts(gpF), Vector2i(12, 8),
		"参照图框的 A3 分区应为 12 列 × 8 行")
	# Field sizes follow from the counts: 34.333 x 36.125 mm, both inside ISO 5457's 25..75 mm range.
	# 分格边长由分格数导出：34.333 × 36.125mm，两者都在 ISO 5457 的 25–75mm 区间内。
	gpApprox(gpF.size.x / 12.0, 34.3333, 0.001, "列宽应约 34.333mm")
	gpApprox(gpF.size.y / 8.0, 36.125, 0.001, "行高应约 36.125mm")


# The count is always even (so a division falls on the paper's centre line, where the centring arrows
# point) and never below the minimum. Swept across the real sheet presets as well as tiny and absurd
# margins, because the frame is draggable as of Rev.3 and the count follows it.
# 分格数恒为偶数（使分界线落在纸面中线上，即对中箭头所指处），且恒不低于最小值。扫过真实图幅预设
# 以及极小与荒唐的边距，因为自 Rev.3 起图框可拖动、分格数随之变化。
func gpTestZoneCountsAreEvenAndBounded() -> void:
	var gpSheets: Array = [100.0, 297.0, 420.0, 594.0, 841.0, 1189.0]
	var gpMarginSets: Array = [GP_REF_MARGINS, [25.0, 5.0, 5.0, 5.0], [1.0, 1.0, 1.0, 1.0], [40.0, 40.0, 40.0, 40.0]]
	for gpW in gpSheets:
		for gpM in gpMarginSets:
			var gpF: Rect2 = GPFrameGeometry.gpInnerRect(gpW, gpW * 0.7071, gpM)
			var gpN: Vector2i = GPFrameGeometry.gpZoneCounts(gpF)
			gpCheck(gpN.x % 2 == 0 and gpN.y % 2 == 0,
				"纸宽 %.0f / 边距 %s：分格数必须为偶数（%s）" % [gpW, str(gpM), str(gpN)])
			gpCheck(gpN.x >= GPFrameGeometry.GP_ZONE_MIN_COUNT
					and gpN.y >= GPFrameGeometry.GP_ZONE_MIN_COUNT,
				"纸宽 %.0f / 边距 %s：分格数不得低于最小值（%s）" % [gpW, str(gpM), str(gpN)])


# Every division tick touches the frame line at one end and runs OUTWARD by the standard depth at the
# other — and the count is (columns-1 + rows-1) doubled, i.e. 36 on the reference (22 vertical + 14
# horizontal), which is precisely what was measured off `图框.svg`.
# 每条分格刻度一端落在图框线上、另一端**向外**延伸出标准深度；条数为（列数−1 + 行数−1）×2，
# 参照图上即 36 条（22 竖 + 14 横）—— 与 `图框.svg` 实测完全一致。
func gpTestZoneTicksHangOutwardOffTheFrameLine() -> void:
	var gpS: GPSheet = _gpA3Ref()
	var gpF: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	var gpTicks: Array = GPFrameGeometry.gpZoneTicks(gpS)
	gpEq(gpTicks.size(), (12 - 1) * 2 + (8 - 1) * 2, "参照图框应共 36 条分区刻度线")
	var gpDepth: float = GPFrameGeometry.GP_ZONE_TICK_MM
	for gpSeg in gpTicks:
		var gpA: Vector2 = gpSeg[0]
		var gpB: Vector2 = gpSeg[1]
		gpApprox(gpA.distance_to(gpB), gpDepth, GP_EPS, "每条刻度长应为标准深度 3mm")
		var gpAOn: bool = _gpOnFrameBorder(gpA, gpF)
		var gpBOn: bool = _gpOnFrameBorder(gpB, gpF)
		gpCheck(gpAOn != gpBOn, "刻度必有一端、且仅一端落在图框线上（%s→%s）" % [str(gpA), str(gpB)])
		var gpFar: Vector2 = gpB if gpAOn else gpA
		gpCheck(not gpF.has_point(gpFar), "刻度的另一端必须在图框**之外**（%s）" % str(gpFar))
	# The first vertical tick sits exactly one column width in from the left frame line, and the last
	# one column width in from the right — the ruler has no tick ON the frame's own corners.
	# 首条竖刻线恰距左图框线一个列宽，末条恰距右图框线一个列宽 —— 坐标带不在图框自身的角上有刻度。
	var gpFirst: Vector2 = gpTicks[0][0]
	gpApprox(gpFirst.x, gpF.position.x + gpF.size.x / 12.0, GP_EPS,
		"首条竖刻线应在距左图框线一个列宽处")
	var gpLast: Vector2 = gpTicks[(12 - 1) * 2 - 1][0]
	gpApprox(gpLast.x, gpF.end.x - gpF.size.x / 12.0, GP_EPS,
		"末条竖刻线应在距右图框线一个列宽处")


# The ruler runs OUTWARD from the frame line, never inside it, and its excursion never exceeds the
# standard tick depth — the two properties the band owes the drawing, wherever the frame happens to be.
# 坐标带自图框线**向外**、绝不进入其内，且外伸量永不超过标准刻度深度 —— 这是坐标带对图形所欠的两条性质，
# 与图框位于何处无关。
#
# ⚠️ THIS REPLACED gpTestZoneMarksNeverLeaveThePaper (2026-10-16), which asserted every mark stayed on the
# sheet. That is false by design now: with free movement a frame line can sit outside the paper and its
# ruler follows the line, so a mark CAN be off the sheet. "The ruler went with the frame" is the correct
# behaviour, not a leak — the old assertion would have read it as a defect.
# ⚠️ 本测试替代 gpTestZoneMarksNeverLeaveThePaper（2026-10-16），后者断言所有标记都在纸上。如今这按设计
# 为假：自由移动下图框线可以位于纸外、其坐标带跟着线走，故标记**可以**在纸外。「坐标带跟着图框去了」是正确
# 行为、不是泄漏 —— 旧的断言会把它读成缺陷。
func gpTestZoneMarksRunOutwardOnly() -> void:
	var gpTextMM: float = 2.85
	var gpMarginSets: Array = [GP_REF_MARGINS, [25.0, 5.0, 5.0, 5.0], [1.0, 1.0, 1.0, 1.0],
		[40.0, 40.0, 40.0, 40.0], [300.0, 200.0, 300.0, 200.0]]
	for gpM in gpMarginSets:
		var gpS: GPSheet = _gpA3()
		gpS.gpSetFrameMargins(gpM)
		var gpF: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
		for gpSeg in GPFrameGeometry.gpZoneTicks(gpS) + GPFrameGeometry.gpZoneArrows(gpS):
			for gpP in gpSeg:
				gpCheck(not _gpStrictlyInside(gpP, gpF),
					"边距 %s：坐标带端点 %s 不得落入图框**内部**（坐标带只向外长）" % [str(gpM), str(gpP)])
				gpCheck(_gpOutward(gpP, gpF) <= GPFrameGeometry.GP_ZONE_TICK_MM + GP_EPS,
					"边距 %s：坐标带端点 %s 外伸 %.4f 不得超过刻度深度 %.4f"
						% [str(gpM), str(gpP), _gpOutward(gpP, gpF),
							GPFrameGeometry.GP_ZONE_TICK_MM])

	# A side whose band cannot exist emits NOTHING rather than marks floating in empty canvas: with a
	# negative margin the frame line is off the sheet, so there is no gap between it and the paper edge.
	# 一条不可能存在带的边**不发出任何标记**，而不是把标记悬浮在空画布上：负边距时图框线在纸外，它与纸边
	# 之间根本没有间隙。
	var gpOff: GPSheet = _gpA3()
	gpOff.gpSetFrameMargins([-50.0, -50.0, -50.0, -50.0])
	gpEq(GPFrameGeometry.gpZoneTicks(gpOff).size(), 0, "四边全在纸外时不应发出任何刻度")
	gpEq(GPFrameGeometry.gpZoneLabels(gpOff, gpTextMM).size(), 0, "四边全在纸外时不应发出任何标号")

	# Where the band DOES exist inside the paper the old containment still holds, so the property is not
	# quietly lost where it remains meaningful. Kept only for the margins that are comfortably inside.
	# 带确实存在且在纸内的情形下，旧的包含性仍然成立，使这条性质不会在有意义的地方悄悄丢掉。只对「稳在纸内」
	# 的边距保留。
	for gpM in [GP_REF_MARGINS, [25.0, 5.0, 5.0, 5.0], [40.0, 40.0, 40.0, 40.0]]:
		var gpIn: GPSheet = _gpA3()
		gpIn.gpSetFrameMargins(gpM)
		var gpPaper: Rect2 = GPFrameGeometry.gpPaperRect(gpIn)
		for gpSeg in GPFrameGeometry.gpZoneTicks(gpIn) + GPFrameGeometry.gpZoneArrows(gpIn):
			for gpP in gpSeg:
				gpCheck(gpP.x >= gpPaper.position.x - GP_EPS and gpP.x <= gpPaper.end.x + GP_EPS
						and gpP.y >= gpPaper.position.y - GP_EPS and gpP.y <= gpPaper.end.y + GP_EPS,
					"边距 %s（稳在纸内）：坐标带端点 %s 仍应留在纸内" % [str(gpM), str(gpP)])
		for gpL in GPFrameGeometry.gpZoneLabels(gpIn, gpTextMM):
			var gpAt: Vector2 = gpL["at"]
			gpCheck(gpAt.x >= gpPaper.position.x - GP_EPS and gpAt.x <= gpPaper.end.x + GP_EPS
					and gpAt.y >= gpPaper.position.y - GP_EPS and gpAt.y <= gpPaper.end.y + GP_EPS,
				"边距 %s（稳在纸内）：标号锚点 %s 仍应留在纸内" % [str(gpM), str(gpAt)])


# The centring marks are arrows: apex ON the frame line at each side's midpoint, two arms running back
# out to the tick end at ±1.5 mm. All eight segments are pinned against the coordinates actually
# measured in `图框.svg` — which is what proves the arrow is "half of a V", not, say, a full cross.
# 对中符号是箭头：顶点落于各边中点的**图框线上**，两臂回到刻度末端、横向 ±1.5mm。八条线段全部按
# `图框.svg` 的实测坐标钉住 —— 这正是「箭头是半个 V、而非整条十字线」的证据。
func gpTestZoneArrowsSitOnTheFourSideMidpoints() -> void:
	var gpS: GPSheet = _gpA3Ref()
	var gpArrows: Array = GPFrameGeometry.gpZoneArrows(gpS)
	gpEq(gpArrows.size(), 8, "四边中点各一对斜臂，共 8 条")
	var gpMidX: float = 210.0
	var gpMidY: float = 148.5
	gpCheck(_gpHasSegment(gpArrows, Vector2(gpMidX, 4.0), Vector2(208.5, 1.0)),
		"上边中点应有一条指向纸外的左臂")
	gpCheck(_gpHasSegment(gpArrows, Vector2(gpMidX, 4.0), Vector2(211.5, 1.0)),
		"上边中点应有一条指向纸外的右臂")
	gpCheck(_gpHasSegment(gpArrows, Vector2(gpMidX, 293.0), Vector2(208.5, 296.0)),
		"下边中点应有一条指向纸外的左臂")
	gpCheck(_gpHasSegment(gpArrows, Vector2(gpMidX, 293.0), Vector2(211.5, 296.0)),
		"下边中点应有一条指向纸外的右臂")
	gpCheck(_gpHasSegment(gpArrows, Vector2(4.0, gpMidY), Vector2(1.0, 147.0)),
		"左边中点应有一条指向纸外的上臂")
	gpCheck(_gpHasSegment(gpArrows, Vector2(4.0, gpMidY), Vector2(1.0, 150.0)),
		"左边中点应有一条指向纸外的下臂")
	gpCheck(_gpHasSegment(gpArrows, Vector2(416.0, gpMidY), Vector2(419.0, 147.0)),
		"右边中点应有一条指向纸外的上臂")
	gpCheck(_gpHasSegment(gpArrows, Vector2(416.0, gpMidY), Vector2(419.0, 150.0)),
		"右边中点应有一条指向纸外的下臂")
	# Every apex must be ON the frame line — the arms start at the frame, not beside it.
	# 每个顶点都必须落在图框线上 —— 两臂起于图框，而非其旁。
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	for gpSeg in gpArrows:
		var gpOn: bool = _gpOnFrameBorder(gpSeg[0], gpFrame) or _gpOnFrameBorder(gpSeg[1], gpFrame)
		gpCheck(gpOn, "对中箭头的顶点必须落在图框线上（%s→%s）" % [str(gpSeg[0]), str(gpSeg[1])])


# The label set: 40 on the reference (numbers 1..12 top AND bottom, letters A..H down BOTH sides),
# with A at the TOP row — the reference's own orientation, and the opposite of "count up from the
# bottom corner" that a naive implementation produces.
# 标号集合：参照图上为 40 个（数字 1..12 上下各一遍，字母 A..H 左右各一遍），且 A 在**顶行** ——
# 这是参照图自身的朝向，也与「自下角往上数」这种朴素实现相反。
func gpTestZoneLabelsCoverBothSidesWithAAtTheTop() -> void:
	var gpS: GPSheet = _gpA3Ref()
	var gpLabels: Array = GPFrameGeometry.gpZoneLabels(gpS, 2.85)
	gpEq(gpLabels.size(), 2 * 12 + 2 * 8, "参照图框应共 40 个分区标号（上下 12 + 左右 8）")
	var gpTexts: Dictionary = {}
	for gpL in gpLabels:
		var gpKey: String = str(gpL["text"])
		gpTexts[gpKey] = int(gpTexts.get(gpKey, 0)) + 1
	for gpN in 12:
		gpEq(int(gpTexts.get(str(gpN + 1), 0)), 2, "数字 %d 应上下各出现一次" % (gpN + 1))
	for gpL2 in 8:
		gpEq(int(gpTexts.get(GPFrameGeometry.gpZoneRowLabel(gpL2), 0)), 2,
			"字母 %s 应左右各出现一次" % GPFrameGeometry.gpZoneRowLabel(gpL2))
	gpEq(gpTexts.size(), 20, "标号共有 12 个数字 + 8 个字母，不应多出别的字符")
	# Orientation: 'A' sits in the FIRST row band (y ≈ 23), 'H' in the LAST (y ≈ 276).
	# 朝向：'A' 位于**第一**行带（y ≈ 23），'H' 位于**最后**一行带（y ≈ 276）。
	var gpAy: float = _gpLabelBaseline(gpLabels, "A")
	var gpHy: float = _gpLabelBaseline(gpLabels, "H")
	gpCheck(gpHy > gpAy + 200.0, "H 应在 A 之下 200mm 以上（A 在上、H 在下）")
	gpCheck(gpAy < GP_A3_H * 0.5 and gpHy > GP_A3_H * 0.5, "A 应在上半幅、H 应在下半幅")


# A side whose band is narrower than the text must degrade to "ruler without numerals" rather than
# spill ink off the sheet. This case was FOUND BY the sweep above (a 1 mm margin put a baseline at
# y = 297.44 on a 297 mm sheet); it is pinned separately so the intent is on the record, not just the
# consequence.
# 带宽窄于字高的边必须降级为「无数字的坐标带」，而不是把墨迹洒出纸面。本例正是被上方那条遍历
# **发现**的（1mm 边距使基线落在 297mm 图纸的 y=297.44）—— 单独钉住它，是为了让**意图**入档，
# 而不只是记录后果。
func gpTestZoneLabelsAreOmittedWhenTheBandCannotHoldThem() -> void:
	var gpS: GPSheet = _gpA3()
	gpS.gpSetFrameMargins([1.0, 1.0, 1.0, 1.0])
	gpEq(GPFrameGeometry.gpZoneLabels(gpS, 2.85).size(), 0,
		"1mm 的带放不下 2.85mm 的字：四边都不应出标号")
	gpCheck(GPFrameGeometry.gpZoneTicks(gpS).size() > 0, "刻度仍应绘制（受深度约束、留在纸内）")
	gpEq(GPFrameGeometry.gpZoneArrows(gpS).size(), 8, "对中箭头仍应绘制")
	# The gate is per side: room on ONE axis keeps exactly that axis' labels.
	# 闸门逐边生效：只有一条轴放得下时，只保留那条轴的标号。
	var gpS2: GPSheet = _gpA3()
	gpS2.gpSetFrameMargins([1.0, 4.0, 1.0, 4.0])
	var gpCounts: Vector2i = GPFrameGeometry.gpZoneCounts(GPFrameGeometry.gpFrameRect(gpS2))
	gpEq(GPFrameGeometry.gpZoneLabels(gpS2, 2.85).size(), 2 * gpCounts.x,
		"左右带被压到 1mm 时，只应留下上下两排数字")


# The baseline offset reproduces the reference's own text placement. Each expected value below is the
# number MEASURED from `图框.svg` (text y + 0.5em of its 2.85mm font), NOT a value copied out of the
# implementation — a test that reads its expectation from the code it tests proves nothing.
# 基线偏移复现参照图自身的文字排布。下列期望值是**实测**自 `图框.svg` 的数值（文字 y + 其 2.85mm
# 字号的 0.5em），而**不是**从实现里抄来的 —— 从被测代码抄期望值的测试什么也证明不了。
func gpTestZoneLabelBaselinesReproduceTheReference() -> void:
	var gpTextMM: float = 2.85
	var gpLabels: Array = GPFrameGeometry.gpZoneLabels(_gpA3Ref(), gpTextMM)
	# Measured: top numbers y=3.3655, bottom numbers y=295.516, row A y=23.003, row H y=275.878.
	# 实测：上数字 y=3.3655，下数字 y=295.516，行 A y=23.003，行 H y=275.878。
	gpCheck(absf(_gpLabelBaselineTop(gpLabels, gpTextMM) - 3.3655) <= 0.1,
		"上一排数字的基线应复现参照图的 3.3655mm（容差 0.1mm）")
	gpCheck(absf(_gpLabelBaselineBottom(gpLabels, gpTextMM) - 295.516) <= 0.1,
		"下一排数字的基线应复现参照图的 295.516mm（容差 0.1mm）")
	gpCheck(absf(_gpLabelBaseline(gpLabels, "A") - 23.003) <= 0.1,
		"行 A 的基线应复现参照图的 23.003mm（容差 0.1mm）")
	gpCheck(absf(_gpLabelBaseline(gpLabels, "H") - 275.878) <= 0.1,
		"行 H 的基线应复现参照图的 275.878mm（容差 0.1mm）")
	# The non-circular half: whatever the ratio, a baseline must stay INSIDE the band it labels.
	# 非循环论证的那一半：无论比例取值如何，基线必须留在它所标注的那条带**内**。
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(_gpA3Ref())
	var gpDepth: float = GPFrameGeometry.GP_ZONE_TICK_MM
	for gpL in gpLabels:
		var gpAt: Vector2 = gpL["at"]
		if absf(gpAt.y - (gpFrame.position.y - gpDepth * 0.5)) < 1.0:
			gpCheck(gpAt.y > gpFrame.position.y - gpDepth and gpAt.y < gpFrame.position.y,
				"上带标号的基线应落在带内（%s）" % str(gpAt))
		elif absf(gpAt.y - (gpFrame.end.y + gpDepth * 0.5)) < 1.0:
			gpCheck(gpAt.y > gpFrame.end.y and gpAt.y < gpFrame.end.y + gpDepth,
				"下带标号的基线应落在带内（%s）" % str(gpAt))


# Baseline y of the FIRST label whose text matches — one anchor per zone per side, so any match works.
# 首个文字匹配的标号的基线 y —— 每区每边一个锚点，故任取其一即可。
func _gpLabelBaseline(gpLabels: Array, gpText: String) -> float:
	for gpL in gpLabels:
		if str(gpL["text"]) == gpText:
			return float(gpL["at"].y)
	return -1.0


# Baseline y of a TOP-band number: the first label whose anchor sits above the frame.
# 上带数字的基线 y：锚点位于图框之上的首个标号。
func _gpLabelBaselineTop(gpLabels: Array, gpTextMM: float) -> float:
	return _gpLabelBaselineBand(gpLabels, gpTextMM, true)


# Baseline y of a BOTTOM-band number. / 下带数字的基线 y。
func _gpLabelBaselineBottom(gpLabels: Array, gpTextMM: float) -> float:
	return _gpLabelBaselineBand(gpLabels, gpTextMM, false)


# Shared band probe: the frame line is always 5 mm inside the paper on an A3 with the reference's
# margins, so "which band" is decided by comparing against the frame rectangle.
# 共用的带探测：A3 + 参照边距下，图框线恒在纸面内 5mm 之内，故「哪条带」由图框矩形比较得出。
func _gpLabelBaselineBand(gpLabels: Array, _gpTextMM: float, gpTop: bool) -> float:
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(_gpA3Ref())
	for gpL in gpLabels:
		var gpAt: Vector2 = gpL["at"]
		var gpIsNumber: bool = str(gpL["text"]).is_valid_int()
		if not gpIsNumber:
			continue
		if gpTop and gpAt.y < gpFrame.position.y:
			return gpAt.y
		if not gpTop and gpAt.y > gpFrame.end.y:
			return gpAt.y
	return -1.0


# ---------------------------------------------------------------------------
# Trim line (裁边线) — Rev.3 stage 0c
# 裁边线 —— Rev.3 阶段 0c
# ---------------------------------------------------------------------------
# WHY THESE EXIST / 为何有这几条：the sheet-edge line stopped being drawn on the paper edge and now
# sits INSIDE it by the amount measured off the reference drawing. That is a visible change to every
# existing sheet, so the number must be pinned as a MEASUREMENT — and the one thing that could go
# wrong silently is the frame's lower bound drifting below the trim inset, which would put the frame
# line outside the trim line on a dragged sheet.
# 纸边线不再画在纸边上，而是按其自参照图**实测**的内缩量画在纸内。这是对每一张既有图纸的可见改变，
# 故该数值必须作为**实测值**钉住 —— 而唯一会静默出错的，是图框下限掉到裁边线内缩量之下，从而在
# 被拖过的图纸上让图框线落到裁边线之外。


# The trim line reproduces the reference drawing: 1 mm inside every edge.
# 裁边线复现参照图：每边内缩 1mm。
func gpTestTrimRectMatchesTheReferenceDrawing() -> void:
	var gpR: Rect2 = GPFrameGeometry.gpTrimRect(_gpA3())
	gpApprox(gpR.position.x, 1.0, GP_EPS, "裁边线左边应内缩 1mm（参照图实测：420×297 上 1..419）")
	gpApprox(gpR.position.y, 1.0, GP_EPS, "裁边线上边应内缩 1mm（参照图实测：1..-296）")
	gpApprox(gpR.size.x, 418.0, GP_EPS, "裁边线宽应为 420 − 1 − 1 = 418mm")
	gpApprox(gpR.size.y, 295.0, GP_EPS, "裁边线高应为 297 − 1 − 1 = 295mm")
	gpEq(GPFrameGeometry.gpTrimRect(null), Rect2(), "无图纸时裁边线矩形应为空")


# An absurd paper degrades to a DEGENERATE rectangle, never to a mirrored (negative-size) one.
# 荒唐的纸幅退化为**退化**矩形，绝不成为**镜像**（负尺寸）矩形。
func gpTestTrimRectNeverMirrors() -> void:
	for gpSide in [1.0, 0.4, 0.0, -5.0]:
		var gpS: GPSheet = _gpA3()
		gpS.gpWidthMM = gpSide
		gpS.gpHeightMM = gpSide
		var gpR: Rect2 = GPFrameGeometry.gpTrimRect(gpS)
		gpCheck(gpR.size.x >= 0.0 and gpR.size.y >= 0.0,
			"纸幅 %.2f：裁边线尺寸不得为负（内缩量以短边一半为上限）" % gpSide)


# The frame is NOT required to stay inside the trim line (裁边线) any more, and it must never collapse.
# 图框**不再**被要求留在裁边线之内，且永不得塌缩。
#
# ⚠️ THIS DELIBERATELY OVERTURNS A PINNED ORDERING (2026-10-16). The retired test
# (gpTestFrameNeverFallsOutsideTheTrimLine) asserted `GP_FRAME_MARGIN_MIN >= GP_TRIM_INSET_MM` and that
# the frame rectangle is always a SUBSET of the trim rectangle. With free movement both are false BY
# DESIGN: a margin may be 0 or negative, so a frame line may land on the trim line or cross it. What
# replaces them is the property that genuinely still holds — the inner rectangle never turns inside out.
# ⚠️ 这是**刻意**推翻一条已钉住的偏序（2026-10-16）。被退役的测试（gpTestFrameNeverFallsOutsideTheTrimLine）
# 断言 `GP_FRAME_MARGIN_MIN >= GP_TRIM_INSET_MM`、且图框矩形恒为裁边线矩形的**子集**。自自由移动起两条都
# **按设计为假**：边距可以为 0 或负，故图框线可以压在裁边线上、也可以与它交叉。取而代之的是真正仍然成立的
# 性质 —— 内框永不会内翻。
func gpTestFrameMayCrossTheTrimLineAndNeverCollapses() -> void:
	var gpS: GPSheet = _gpA3()
	# Zero margins put the frame line ON THE PAPER EDGE — i.e. OUTSIDE the trim line, not pushed onto it.
	# 零边距把图框线放在**纸边**上 —— 即裁边线**之外**，而不是被推到裁边线上。
	gpS.gpSetFrameMargins([0.0, 0.0, 0.0, 0.0])
	gpApprox(GPFrameGeometry.gpFrameRect(gpS).position.x, 0.0, GP_EPS,
		"零边距时图框线应在纸边（0mm），而非被推到裁边线的 1mm 处")
	# The trim line is a property of the PAPER alone: no margin can move it.
	# 裁边线只是**纸面**的性质：任何边距都动不了它。
	gpS.gpSetFrameMargins([-30.0, -30.0, -30.0, -30.0])
	var gpTrim: Rect2 = GPFrameGeometry.gpTrimRect(gpS)
	gpApprox(gpTrim.position.x, GPFrameGeometry.GP_TRIM_INSET_MM, GP_EPS,
		"负边距不得移动裁边线（它只由纸幅与内缩常量决定）")
	var gpOut: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	gpCheck(gpOut.position.x < gpTrim.position.x - GP_EPS,
		"负边距应把图框线推到裁边线之外（实测 %.1f 应小于 %.1f）"
			% [gpOut.position.x, gpTrim.position.x])
	# The one thing that must NEVER happen: an inside-out frame.
	# 唯一绝不能发生的事：图框内翻。
	var gpCases: Array = [[0.0, 0.0, 0.0, 0.0], [-100.0, -100.0, -100.0, -100.0],
		[300.0, 300.0, 300.0, 300.0], [900.0, 900.0, 900.0, 900.0],
		[800.0, 0.0, 800.0, 0.0], [0.0, 800.0, 0.0, 800.0]]
	for gpM in gpCases:
		var gpR: Rect2 = GPFrameGeometry.gpInnerRect(GP_A3_W, GP_A3_H, gpM)
		gpCheck(gpR.size.x >= GPSheet.GP_FRAME_MIN_SIZE_MM - GP_EPS
				and gpR.size.y >= GPSheet.GP_FRAME_MIN_SIZE_MM - GP_EPS,
			"边距 %s：内框宽高不得小于 %.1fmm（实测 %.4f × %.4f）"
				% [str(gpM), GPSheet.GP_FRAME_MIN_SIZE_MM, gpR.size.x, gpR.size.y])


# ---------------------------------------------------------------------------
# Frame dragging arithmetic (图框拖动算术) — Rev.3 stage 0c
# 图框拖动算术 —— Rev.3 阶段 0c
# ---------------------------------------------------------------------------
# WHY THESE EXIST / 为何有这几条：a drag is a TRANSFORMATION OF THE MARGINS, and the canvas must never
# compute it on its own (then the frame you drag and the frame you see would be derived twice). Two
# failure modes are pinned here: the translate accidentally RESIZING the frame (clamping the margins
# one by one instead of the delta), and the grab band swallowing clicks INSIDE the frame.
# 拖拽是一次**边距变换**，画布绝不自行计算（否则「你拖的框」与「你看到的框」会各推导一次）。此处钉住两个
# 失效模式：平移**悄悄改了尺寸**（逐条钳制边距而非钳制位移）、以及抓取带吞掉**框内**的点击。


# Margin equality must be TOLERANT AND TYPE-AGNOSTIC. This test records the MEASURED semantics of
# Array `==` (2026-10-15) rather than a belief about it — an earlier draft of the implementation
# claimed `==` compares by reference, which measurement disproved.
# 边距相等必须**带容差、且不区分数值类型**。本测试记录 Array `==` 的**实测**语义（2026-10-15），
# 而不是对它的信念 —— 实现的一稿曾声称 `==` 按引用比较，实测已证伪。
func gpTestSameMarginsComparesByValueWithTolerance() -> void:
	gpCheck(GPFrameGeometry.gpSameMargins([25.0, 5.0, 5.0, 5.0], [25.0, 5.0, 5.0, 5.0]),
		"两个等值的独立数组必须判为相同")
	var gpA: Array = [25.0, 5.0, 5.0, 5.0]
	var gpB: Array = gpA.duplicate()
	gpCheck(gpA == gpB, "探针（实测）：Array == 是按**值**比较，等值副本相等 —— 不是按引用")
	# Reason 1: `==` is EXACT, and margin values carry arithmetic noise.
	# 理由一：`==` 是**精确**相等，而边距取值带算术噪声。
	gpCheck(not ([25.0 + 1.0e-12, 5.0, 5.0, 5.0] == gpA),
		"探针（实测）：== 是精确相等，1e-12 的噪声即判为不同")
	gpCheck(GPFrameGeometry.gpSameMargins([25.0 + 1.0e-12, 5.0, 5.0, 5.0], gpA),
		"1e-12 的噪声之内必须判为相同（否则每次点击都留下一个幽灵撤销步）")
	# Reason 2: `==` is TYPE-STRICT per element, and margins arrive from JSON / dialogs as INTs.
	# 理由二：`==` 逐元素**类型严格**，而边距会以 INT 形式来自 JSON / 对话框。
	gpCheck(not ([25, 5, 5, 5] == gpA),
		"探针（实测）：[25,5,5,5]（整数）与 [25.0,…]（浮点）判为不同")
	gpCheck(GPFrameGeometry.gpSameMargins([25, 5, 5, 5], gpA),
		"整数与浮点写法必须判为相同（JSON 读回的整数不得被报成一次编辑）")
	gpCheck(not GPFrameGeometry.gpSameMargins(gpA, [25.0, 5.0, 5.0, 5.5]),
		"任一项超差即判为不同")
	gpCheck(not GPFrameGeometry.gpSameMargins([25.0, 5.0], gpA), "长度不同即判为不同")
	gpCheck(GPFrameGeometry.gpSameMargins(gpA, [25.00001, 5.0, 5.0, 5.0]),
		"浮点噪声之内仍应判为相同")


# Test-local by-value comparison, so the assertion above does not depend on the implementation it pins.
# 测试自带的按值比较，使上方断言不依赖它所钉的实现。
# (This file already owns `_gpSameMargins`, used from the very first tests — reused, not duplicated.)
# （本文件已有 `_gpSameMargins`，从最早的几条测试起就在用 —— 复用，不再抄一份。）


# The four side handles sit at the midpoints of the four frame lines, in margin order.
# 四个侧手柄位于四条图框线的中点，顺序与边距一致。
func gpTestSideMidpointsFollowTheFrame() -> void:
	var gpS: GPSheet = _gpA3()
	var gpF: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	var gpM: Array = GPFrameGeometry.gpSideMidpoints(gpS)
	gpEq(gpM.size(), 4, "四条边各有中点")
	var gpMidX: float = (gpF.position.x + gpF.end.x) * 0.5
	var gpMidY: float = (gpF.position.y + gpF.end.y) * 0.5
	_gpCheckPoint(gpM[GPSheet.GP_MARGIN_LEFT], Vector2(gpF.position.x, gpMidY), "左中点应位于图框左边中点")
	_gpCheckPoint(gpM[GPSheet.GP_MARGIN_TOP], Vector2(gpMidX, gpF.position.y), "上中点应位于图框上边中点")
	_gpCheckPoint(gpM[GPSheet.GP_MARGIN_RIGHT], Vector2(gpF.end.x, gpMidY), "右中点应位于图框右边中点")
	_gpCheckPoint(gpM[GPSheet.GP_MARGIN_BOTTOM], Vector2(gpMidX, gpF.end.y), "下中点应位于图框下边中点")
	# The midpoints must MOVE with the frame — the handles are derived, not baked.
	# 中点必须随图框移动 —— 手柄是推导出来的，不是烘死的。
	gpS.gpSetFrameMargins([12.0, 7.0, 9.0, 4.0])
	var gpM2: Array = GPFrameGeometry.gpSideMidpoints(gpS)
	gpCheck(not _gpSamePoint(gpM2[0], gpM[0]), "改边距后左中点必须随之移动")
	_gpCheckPoint(gpM2[0], Vector2(12.0, (7.0 + 297.0 - 4.0) * 0.5), "新左边距下左中点应落在新的左边中点")
	gpEq(GPFrameGeometry.gpSideMidpoints(null).size(), 0, "无图纸时不应给出中点")


# A side handle is a DISC of radius gpTol around that side's midpoint — and it is a strict SUBSET of
# that side's grab band, which is what makes "handle first" a meaningful test in the band probe.
# 侧手柄是侧中点周围半径 gpTol 的**圆盘**，且是该边抓取带的严格子集 —— 这正是「先测手柄」在带探测里
# 具有意义的原因。
func gpTestSideHandleHitIsADiscAtEachMidpoint() -> void:
	var gpS: GPSheet = _gpA3()
	var gpM: Array = GPFrameGeometry.gpSideMidpoints(gpS)
	for gpI in gpM.size():
		gpEq(GPFrameGeometry.gpHitSideHandle(gpS, gpM[gpI] as Vector2, 2.0), gpI,
			"第 %d 条边的中点必须命中该边手柄" % gpI)
		gpEq(GPFrameGeometry.gpHitSideHandle(gpS, (gpM[gpI] as Vector2) + Vector2(1.5, 0.0), 2.0),
			gpI, "第 %d 条边中点旁 1.5mm（容差 2mm）仍应命中" % gpI)
	gpEq(GPFrameGeometry.gpHitSideHandle(gpS, (gpM[0] as Vector2) + Vector2(3.0, 0.0), 2.0),
		GPFrameGeometry.GP_SIDE_NONE, "超出容差即不命中")
	gpEq(GPFrameGeometry.gpHitSideHandle(gpS, Vector2(220.0, 148.5), 2.0),
		GPFrameGeometry.GP_SIDE_NONE, "图框正中心不命中任何手柄")


# ⚠️ THE PROPERTY THAT MAKES THIS FEATURE SAFE: the band is `gpTol`-wide around each LINE, and the
# frame's INTERIOR never grabs. A 420x297 rectangle that answered "yes" anywhere inside would hijack
# every click on the sheet and no symbol could be picked.
# ⚠️ 本功能安全性的**核心属性**：抓取带是每条线两侧 gpTol 宽的带状区，图框**内部**一律不抓。
# 一个「框内任何位置都回答是」的 420×297 矩形会吃掉图纸上的每一次点击，图元全都拾取不了。
func gpTestFrameBandNeverGrabsInsideTheFrame() -> void:
	var gpS: GPSheet = _gpA3()
	var gpF: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	var gpT: float = 1.0
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(220.0, 148.5), gpT),
		GPFrameGeometry.GP_SIDE_NONE, "图框正中心不得命中")
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(gpF.position.x + 30.0, gpF.position.y + 30.0), gpT),
		GPFrameGeometry.GP_SIDE_NONE, "框内靠角处不得命中")
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(220.0, gpF.position.y - 5.0), gpT),
		GPFrameGeometry.GP_SIDE_NONE, "距图框线 5mm 之外不得命中")
	# And the four lines DO grab, at a point well away from the handles.
	# 而四条线本身确实可抓 —— 取远离手柄的点。
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(gpF.position.x, 100.0), gpT),
		GPSheet.GP_MARGIN_LEFT, "左边线上应命中左边")
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(100.0, gpF.position.y), gpT),
		GPSheet.GP_MARGIN_TOP, "上边线上应命中上边")
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(gpF.end.x, 100.0), gpT),
		GPSheet.GP_MARGIN_RIGHT, "右边线上应命中右边")
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(100.0, gpF.end.y), gpT),
		GPSheet.GP_MARGIN_BOTTOM, "下边线上应命中下边")
	# The band is exactly +-gpTol: half of it hits, twice it does not.
	# 带宽恰为 ±gpTol：一半仍命中，两倍不命中。
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(gpF.position.x + gpT * 0.5, 100.0), gpT),
		GPSheet.GP_MARGIN_LEFT, "带内（+0.5 tol）应命中")
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(gpF.position.x + gpT * 2.0, 100.0), gpT),
		GPFrameGeometry.GP_SIDE_NONE, "带外（+2 tol）不命中")
	# A point ON the left line but far beyond its ends is NOT on the band: the span is bounded too.
	# 落在左边线上、但远远超出该边端点之外的点**不属于**抓取带：跨度同样有界。
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(gpF.position.x, gpF.position.y - 50.0), gpT),
		GPFrameGeometry.GP_SIDE_NONE, "延长线上的点不得命中（跨度有界）")


# Ties (exactly on a corner diagonal) resolve to the LOWEST margin index — deterministic and recorded,
# rather than "whatever the loop happened to do".
# 平局（恰在角平分线上）取**最小**边距下标 —— 确定且入档，而不是「循环碰巧怎么走」。
func gpTestFrameBandTiesResolveToTheLowestSide() -> void:
	var gpS: GPSheet = _gpA3()
	var gpF: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	var gpT: float = 1.0
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, gpF.position, gpT), GPSheet.GP_MARGIN_LEFT,
		"左上角的平局应取最小下标（左 = 0）")
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, Vector2(gpF.end.x, gpF.position.y), gpT),
		GPSheet.GP_MARGIN_TOP, "右上角的平局应取上（1 < 右 2）")
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, gpF.end, gpT), GPSheet.GP_MARGIN_RIGHT,
		"右下角的平局应取右（2 < 下 3）")
	gpEq(GPFrameGeometry.gpFrameSideAt(gpS, gpF.position + Vector2(gpF.size.x, 0.0) * 0.5, gpT),
		GPSheet.GP_MARGIN_TOP, "上边非角处命中上边")
	# A corner reached from OUTSIDE is still reachable (the span is extended by the same tolerance).
	# 自**外侧**够角点仍可达（跨度同样外扩一个容差）。
	gpCheck(GPFrameGeometry.gpFrameSideAt(gpS,
			gpF.position + Vector2(-gpT * 0.5, -gpT * 0.5), gpT) != GPFrameGeometry.GP_SIDE_NONE,
		"从图框角外侧应能抓到边")


# ⚠️ THE SIZE INVARIANT OF A TRANSLATE: `left + d` and `right - d` mean the frame keeps its WIDTH
# exactly. Clamping the four margins individually (via gpClampMargins) would let one hit the minimum
# while the other kept moving — i.e. the frame would silently GROW or SHRINK while the user is trying
# to move it. The admissible delta is therefore derived per axis.
# ⚠️ 平移的**尺寸不变量**：`left + d` 与 `right − d` 使图框宽度精确不变。逐条钳制边距
# （经 gpClampMargins）会让一条撞下限而另一条继续走 —— 用户想挪框，框却悄悄胀大/缩小。故位移按轴推导。
func gpTestPanKeepsTheFrameSizeExactly() -> void:
	var gpSets: Array = [[25.0, 5.0, 5.0, 5.0], [4.0, 4.0, 4.0, 4.0], [1.0, 1.0, 1.0, 1.0],
		[40.0, 40.0, 40.0, 40.0]]
	var gpDeltas: Array = [Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(-3.0, 0.0),
		Vector2(0.0, 3.0), Vector2(0.0, -3.0), Vector2(5000.0, 0.0), Vector2(-5000.0, 0.0),
		Vector2(0.0, 5000.0), Vector2(0.0, -5000.0), Vector2(5000.0, -5000.0)]
	for gpM in gpSets:
		for gpD in gpDeltas:
			var gpS: GPSheet = _gpA3()
			gpS.gpSetFrameMargins(gpM)
			var gpBefore: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
			var gpNew: Array = GPFrameGeometry.gpPanMargins(gpS, gpD)
			gpS.gpSetFrameMargins(gpNew)
			var gpAfter: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
			gpApprox(gpAfter.size.x, gpBefore.size.x, GP_EPS,
				"边距 %s / 位移 %s：平移不得改变图框宽" % [str(gpM), str(gpD)])
			gpApprox(gpAfter.size.y, gpBefore.size.y, GP_EPS,
				"边距 %s / 位移 %s：平移不得改变图框高" % [str(gpM), str(gpD)])


# A translate is UNBOUNDED since 2026-10-16, and the delta is applied IN FULL — so the frame lands
# exactly where the user pointed, including right off the sheet.
# 自 2026-10-16 起平移**无界**，且位移被**完整**施加 —— 故图框精确落在用户所指之处，包括一路落到纸外。
#
# ⚠️ THIS REPLACED gpTestPanIntervalMatchesThePlan (2026-10-16), which recorded the admissible delta
# interval the paper bound produced: [-24, +4] mm horizontally and [-4, +4] mm vertically on the A3
# default. Those numbers are gone with the bound — and they were the reason the frame felt "stuck", since
# a 5 mm right margin left only 4 mm of travel. What matters now is that NO delta is reduced, so the same
# idea is asserted as "the delta comes back in full".
# ⚠️ 本测试替代 gpTestPanIntervalMatchesThePlan（2026-10-16）：后者记录的是纸面约束产生的允许位移区间 ——
# A3 默认下水平 [−24, +4]mm、竖直 [−4, +4]mm。那些数字已随约束一并消失 —— 而它们正是图框「挪不动」的原因，
# 因为 5mm 的右边距只留下 4mm 行程。如今要紧的是**任何位移都不会被削减**，故同一思路改写成「位移原样回来」。
func gpTestPanIsUnboundedAndKeepsTheSize() -> void:
	var gpS: GPSheet = _gpA3()
	var gpStart: Array = GPSheet.GP_FRAME_MARGINS_DEFAULT.duplicate()
	var gpDeltas: Array = [Vector2(1000.0, 0.0), Vector2(-1000.0, 0.0), Vector2(0.0, 1000.0),
		Vector2(0.0, -1000.0), Vector2(5000.0, 5000.0), Vector2(-5000.0, -5000.0)]
	for gpD in gpDeltas:
		var gpV: Vector2 = gpD
		var gpM: Array = GPFrameGeometry.gpPanMargins(gpS, gpV)
		gpApprox(float(gpM[GPSheet.GP_MARGIN_LEFT]), float(gpStart[GPSheet.GP_MARGIN_LEFT]) + gpV.x,
			GP_EPS, "位移 %s：左边距应原样加上位移" % str(gpV))
		gpApprox(float(gpM[GPSheet.GP_MARGIN_TOP]), float(gpStart[GPSheet.GP_MARGIN_TOP]) + gpV.y,
			GP_EPS, "位移 %s：上边距应原样加上位移" % str(gpV))
		gpApprox(float(gpM[GPSheet.GP_MARGIN_RIGHT]), float(gpStart[GPSheet.GP_MARGIN_RIGHT]) - gpV.x,
			GP_EPS, "位移 %s：右边距应原样减去位移" % str(gpV))
		gpApprox(float(gpM[GPSheet.GP_MARGIN_BOTTOM]), float(gpStart[GPSheet.GP_MARGIN_BOTTOM]) - gpV.y,
			GP_EPS, "位移 %s：下边距应原样减去位移" % str(gpV))

	# ±1000 mm is plenty to park the frame wholly off the sheet: the sign of a margin flips, which is
	# the honest encoding of "that frame line is now outside the paper".
	# ±1000mm 足以把图框整块停到纸外：边距变号，而这正是「该条图框线现在位于纸外」的诚实编码。
	var gpFar: Array = GPFrameGeometry.gpPanMargins(gpS, Vector2(1000.0, 0.0))
	gpCheck(float(gpFar[GPSheet.GP_MARGIN_RIGHT]) < 0.0,
		"向右平移 1000mm 后右边距应为负（实测 %.1f）" % float(gpFar[GPSheet.GP_MARGIN_RIGHT]))
	gpCheck(float(gpFar[GPSheet.GP_MARGIN_LEFT]) > gpS.gpWidthMM,
		"向右平移 1000mm 后左边距应大于纸宽（实测 %.1f > %.1f）"
			% [float(gpFar[GPSheet.GP_MARGIN_LEFT]), gpS.gpWidthMM])
	gpS.gpSetFrameMargins(gpFar)
	var gpPaper: Rect2 = GPFrameGeometry.gpPaperRect(gpS)
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	gpCheck(gpFrame.position.x > gpPaper.end.x,
		"平移 1000mm 之后图框确实整体落在纸右缘之外（实测左边 %.1f > 纸右 %.1f）—— 按设计如此"
			% [gpFrame.position.x, gpPaper.end.x])


# A side drag changes EXACTLY ONE margin — the opposite side is untouched. That is what makes it read
# as a RESIZE rather than as a second pan.
# 拖动一条边**恰好**改一个边距 —— 对边不动。这正是它读作**改尺寸**而非第二次平移的原因。
#
# ⚠️ THE FOUR "CURSOR" VALUES ARE WORLD COORDINATES, AND THE TWO RIGHTMOST PAIRS CHANGED ON 2026-10-16
# (Rev.3 stage 0d) / ⚠️ 四个「光标」值都是**世界坐标**，且最右两对已于 2026-10-16（Rev.3 阶段 0d）更改：
# the right and bottom handles used to compute `margin = cursor`, which placed the dragged line at
# `span - cursor` — 375 mm away from a 35 mm motion, and a collapse on the first frame. The expected
# margins (20 mm each) are unchanged and are DERIVED from the geometric intent — "the right frame line
# ends up 20 mm from the right paper edge" — so the cursor has to be at `420 - 20 = 400` (and
# `297 - 20 = 277`) for that to be the honest answer. LEFT/TOP keep the old numbers because there the
# margin and the line's own coordinate coincide.
# 右 / 下两个手柄原本算 `margin = 光标`，那会把被拖的线放到 `span − 光标` 处 —— 35mm 的动作偏离 375mm，
# 且第一帧就压扁图框。期望边距（均为 20mm）未变，且是自**几何意图**推导的 —— 「右边那条图框线最终距纸
# 右缘 20mm」—— 故光标必须位于 `420 − 20 = 400`（下边则为 `297 − 20 = 277`）才是诚实的答案。左 / 上保留
# 原数值，因为在它们那边边距与线自身的坐标恰好重合。
func gpTestDragSideChangesExactlyOneMargin() -> void:
	var gpS: GPSheet = _gpA3()
	var gpCases: Array = [
		# [side, cursor world coordinate on that side's axis, index, the margin it must produce]
		# [边, 该边轴上的光标世界坐标, 下标, 它必须产生的边距]
		[GPSheet.GP_MARGIN_LEFT, 30.0, 0, 30.0],
		[GPSheet.GP_MARGIN_TOP, 12.0, 1, 12.0],
		[GPSheet.GP_MARGIN_RIGHT, GP_A3_W - 20.0, 2, 20.0],
		[GPSheet.GP_MARGIN_BOTTOM, GP_A3_H - 20.0, 3, 20.0],
	]
	for gpC in gpCases:
		var gpSide: int = int(gpC[0])
		var gpNew: Array = GPFrameGeometry.gpDragSideMargins(gpS, gpSide, float(gpC[1]))
		var gpChanged: int = 0
		for gpI in 4:
			if absf(float(gpNew[gpI]) - float(GPSheet.GP_FRAME_MARGINS_DEFAULT[gpI])) > GP_EPS:
				gpChanged += 1
		gpEq(gpChanged, 1, "拖动第 %d 条边只应改变它自己" % gpSide)
		gpApprox(float(gpNew[gpSide]), float(gpC[3]), GP_EPS,
			"拖动第 %d 条边应落到指定值" % gpSide)
		# The dragged LINE must land on the cursor — asserted on the GEOMETRY, not only on the margin,
		# so a mirrored margin cannot pass by being self-consistent with a mirrored rectangle. The line
		# is derived by hand from the RETURNED margins (this sheet sits at the world origin), never by
		# writing them onto the shared sheet: this function must not disturb the cases that follow it.
		# 被拖的**线**必须落在光标处 —— 断言落在**几何**上、而不只是边距上，使镜像的边距无法靠「与镜像的
		# 矩形自洽」而通过。线由**返回的**边距手工推导（本图纸位于世界原点），绝不把它们写到共享的图纸上：
		# 本函数不得扰动它后面的用例。
		var gpLine: float = GP_A3_W - float(gpNew[GPSheet.GP_MARGIN_RIGHT])
		if gpSide == GPSheet.GP_MARGIN_LEFT:
			gpLine = float(gpNew[GPSheet.GP_MARGIN_LEFT])
		elif gpSide == GPSheet.GP_MARGIN_TOP:
			gpLine = float(gpNew[GPSheet.GP_MARGIN_TOP])
		elif gpSide == GPSheet.GP_MARGIN_BOTTOM:
			gpLine = GP_A3_H - float(gpNew[GPSheet.GP_MARGIN_BOTTOM])
		gpApprox(gpLine, float(gpC[1]), GP_EPS,
			"第 %d 条边被拖后，图框线应落在光标 %.1f 处" % [gpSide, float(gpC[1])])
	# Dragging a side OUTWARD past the paper edge is free: the margin simply goes negative. It used to be
	# raised to a 1 mm floor (the paper bound), which was retired on 2026-10-16.
	# 把一条边向**外**拖出纸边是自由的：边距直接变负。从前它会被抬到 1mm 下限（即纸面约束），该约束已于
	# 2026-10-16 退役。
	var gpLow: Array = GPFrameGeometry.gpDragSideMargins(gpS, GPSheet.GP_MARGIN_LEFT, -50.0)
	gpApprox(float(gpLow[GPSheet.GP_MARGIN_LEFT]), -50.0, GP_EPS,
		"拖到 −50mm 应原样取 −50mm（负边距合法）")
	gpApprox(float(gpLow[GPSheet.GP_MARGIN_RIGHT]), 5.0, GP_EPS,
		"向**外**拖左边仍不得改动右边距")
	# GP_SIDE_NONE is not a side: the margins come back clamped and otherwise untouched.
	# GP_SIDE_NONE 不是一条边：边距经钳制返回、其余不变。
	var gpNone: Array = GPFrameGeometry.gpDragSideMargins(gpS, GPFrameGeometry.GP_SIDE_NONE, 30.0)
	gpCheck(_gpSameMargins(gpNone, GPSheet.GP_FRAME_MARGINS_DEFAULT),
		"无侧边时边距应保持不变")


# A dragged side is bounded by the frame's OWN opposite side only: it may not cross it (that would turn
# the frame inside out) — but it may travel any distance OUTWARD, including clean off the paper.
# 被拖动的边只受图框**自身**对边的约束：不得越过它（那会让图框内翻）—— 但可以向**外**走任意距离，包括
# 彻底离开纸面。
#
# ⚠️ THIS REPLACED gpTestDragSideCannotSwallowTheSheet (2026-10-16), whose closing loop asserted the frame
# stays inside the paper on every input. That is false by design since the user asked for free movement
# (「自由移动，没有限制」). What IS true — and what this pins instead — is the frame's own consistency,
# which is exactly the option chosen over "no guard at all": without it, dragging a side past its
# opposite would make the frame vanish (neither drawn nor grabbable) and only undo could bring it back.
# ⚠️ 本测试替代 gpTestDragSideCannotSwallowTheSheet（2026-10-16）；后者结尾的循环断言「任何输入下图框都留
# 在纸内」。自用户要求自由移动（「自由移动，没有限制」）起，那按设计为假。真正成立、且此处改为钉住的，是图框
# 自身的自洽 —— 这正是当初在「连自洽保护也去掉」之外所选的那一项：没有它，把一条边拖过对边会让图框消失
# （既不绘制、也不可抓取），只能靠撤销找回。
func gpTestDragSideNeverTurnsTheFrameInsideOut() -> void:
	var gpS: GPSheet = _gpA3()
	# INWARD is capped exactly one minimum inner size short of the opposite side. "Inward" is the
	# direction TOWARDS the far edge on that side's own axis — +x for LEFT, −x for RIGHT, +y for TOP,
	# −y for BOTTOM. Those signs are derived from the geometry ("which way must the line travel to meet
	# its opposite"), NOT transcribed from the implementation; that is exactly the mistake corrected
	# on 2026-10-16, when the right and bottom handles turned out to be mirrored.
	# 向**内**恰好在对边之前一个「最小内框尺寸」处停下。「向内」是在该边自身轴上**朝向**纸另一侧的方向 ——
	# 左为 +x、右为 −x、上为 +y、下为 −y。这些符号由几何推导（「线要朝哪边走才对上对边」），**不是**从
	# 实现抄的；而抄实现正是 2026-10-16 更正掉的那个错误 —— 当时发现右 / 下两个手柄是镜像的。
	var gpInward: Array = [1000.0, 1000.0, -1000.0, -1000.0]
	var gpOpposite: Array = [GPSheet.GP_MARGIN_RIGHT, GPSheet.GP_MARGIN_BOTTOM,
		GPSheet.GP_MARGIN_LEFT, GPSheet.GP_MARGIN_TOP]
	for gpSide in 4:
		var gpBig: Array = GPFrameGeometry.gpDragSideMargins(gpS, gpSide, float(gpInward[gpSide]))
		gpApprox(float(gpBig[gpOpposite[gpSide]]),
			float(GPSheet.GP_FRAME_MARGINS_DEFAULT[gpOpposite[gpSide]]), GP_EPS,
			"第 %d 条边向内拖到极值不得改动它的对边" % gpSide)
		gpS.gpSetFrameMargins(gpBig)
		var gpInner: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
		var gpSpanned: float = gpInner.size.x
		if gpSide == GPSheet.GP_MARGIN_TOP or gpSide == GPSheet.GP_MARGIN_BOTTOM:
			gpSpanned = gpInner.size.y
		gpApprox(gpSpanned, GPSheet.GP_FRAME_MIN_SIZE_MM, GP_EPS,
			"第 %d 条边向内拖到极值后该轴内框应恰为最小尺寸（实测 %.4fmm）" % [gpSide, gpSpanned])
		# Back to the start for the next side (a direct write, so no extra undo step is recorded).
		# 复位供下一条边（直接写入，故不产生额外撤销步）。
		gpS.gpSetFrameMargins(GPSheet.GP_FRAME_MARGINS_DEFAULT)

	# OUTWARD is unbounded: one side at a time, the frame can be dragged clean off the sheet. The
	# margin that results is the distance from that side's PAPER EDGE, so it is NEGATIVE by exactly the
	# excursion the cursor made beyond the span. The literals below are hand-computed from that
	# definition (420 − 5000 and 297 − 5000) rather than read back out of the function under test.
	# 向**外**无界：逐条边，图框可以被拖到彻底离开纸面。得出的边距是到该边**纸缘**的距离，故其**负**值恰
	# 等于光标越出跨度的那段行程。下面的字面值由该定义手工算出（420 − 5000 与 297 − 5000），而不是从被测
	# 函数读回的。
	var gpOutCases: Array = [
		[GPSheet.GP_MARGIN_LEFT, -5000.0, -5000.0],
		[GPSheet.GP_MARGIN_TOP, -5000.0, -5000.0],
		[GPSheet.GP_MARGIN_RIGHT, 5000.0, GP_A3_W - 5000.0],
		[GPSheet.GP_MARGIN_BOTTOM, 5000.0, GP_A3_H - 5000.0],
	]
	for gpC in gpOutCases:
		var gpSide: int = int(gpC[0])
		var gpOut: Array = GPFrameGeometry.gpDragSideMargins(gpS, gpSide, float(gpC[1]))
		gpApprox(float(gpOut[gpSide]), float(gpC[2]), GP_EPS,
			"第 %d 条边向外拖到 %.0fmm 应得边距 %.0f（负值合法、无下限）"
				% [gpSide, float(gpC[1]), float(gpC[2])])

	# Every input on every side, across FOUR margin sets, still leaves a NON-COLLAPSED rectangle. Four
	# sets so the assertion cannot be accidentally conditional on the A3 default margins; the sets are
	# used in sequence, which also exercises "drag from an already-dragged state".
	# 每条边、每个取值、跨**四组**边距，都仍留下**未塌缩**的矩形。用四组是为了使该断言不会恰好只对 A3 默认
	# 边距成立；四组按顺序使用，因而也顺带覆盖「从已被拖过的状态再拖」。
	for gpSet in [[25.0, 5.0, 5.0, 5.0], [4.0, 4.0, 4.0, 4.0], [0.0, 0.0, 0.0, 0.0],
			[-20.0, 6.0, 3.0, -9.0]]:
		var gpS2: GPSheet = _gpA3()
		gpS2.gpSetFrameMargins(gpSet)
		for gpSide in 4:
			for gpVal in [-5000.0, -1.0, 0.0, 1.0, 5000.0]:
				gpS2.gpSetFrameMargins(GPFrameGeometry.gpDragSideMargins(gpS2, gpSide, gpVal))
				var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(gpS2)
				gpCheck(gpFrame.size.x >= GPSheet.GP_FRAME_MIN_SIZE_MM - GP_EPS
						and gpFrame.size.y >= GPSheet.GP_FRAME_MIN_SIZE_MM - GP_EPS,
					"边距 %s / 边 %d 拖到 %.0fmm：内框不得塌缩（实测 %.4f × %.4f）"
						% [str(gpSet), gpSide, gpVal, gpFrame.size.x, gpFrame.size.y])


# True when a point lies STRICTLY inside the rectangle (boundary counts as outside, within GP_EPS).
# 点是否**严格**落在矩形内部（边界视为外部，容差 GP_EPS）。
# Used by the zone-band assertions: a tick legitimately STARTS on the frame line, so "outside the frame"
# must not be tested as `not inside` with exact floats.
# 用于坐标带断言：刻度本就自图框线起，故「在图框之外」不能用精确浮点写成 `not inside`。
func _gpStrictlyInside(gpP: Vector2, gpR: Rect2) -> bool:
	return gpP.x > gpR.position.x + GP_EPS and gpP.x < gpR.end.x - GP_EPS \
		and gpP.y > gpR.position.y + GP_EPS and gpP.y < gpR.end.y - GP_EPS


# How far a point sits OUTSIDE the rectangle, in mm (0 when it is on or inside it).
# 点位于矩形**之外**的距离（mm）；在边上或内部时为 0。
func _gpOutward(gpP: Vector2, gpR: Rect2) -> float:
	var gpD: float = 0.0
	gpD = maxf(gpD, gpR.position.x - gpP.x)
	gpD = maxf(gpD, gpP.x - gpR.end.x)
	gpD = maxf(gpD, gpR.position.y - gpP.y)
	gpD = maxf(gpD, gpP.y - gpR.end.y)
	return gpD


# Point comparison with a tolerance, so a derived midpoint is never compared by exact float equality.
# 带容差的点比较，使推导出的中点永不被精确浮点相等所判定。
func _gpSamePoint(gpGot: Variant, gpWant: Vector2) -> bool:
	if not (gpGot is Vector2):
		return false
	var gpP: Vector2 = gpGot as Vector2
	return absf(gpP.x - gpWant.x) <= GP_EPS and absf(gpP.y - gpWant.y) <= GP_EPS


# Assert a point equals the expected one within GP_EPS.
# 断言某点与期望点在 GP_EPS 内相等。
func _gpCheckPoint(gpGot: Variant, gpWant: Vector2, gpMsg: String) -> void:
	gpCheck(_gpSamePoint(gpGot, gpWant), "%s（实测 %s，期望 %s）" % [gpMsg, str(gpGot), str(gpWant)])


# ---------------------------------------------------------------------------
# Title-block docking (图签停靠) — Rev.3 stage 1 / Rev.3 阶段 1
# ---------------------------------------------------------------------------
# The docking model has FOUR pure operations and each gets its own failure mode pinned here:
# 停靠模型有四个纯操作，各自钉住一种失效：
#   At(正推)     —— 一次手滑的符号错误会让图签贴错角或翻到框外；
#   Offset(反推) —— 反推的符号错误表现为「一开拖图签就跳」；
#   Clamp(钳制)  —— 框比图签窄时若不塌缩上限，图签会凭空消失（Rev.3 §9-① 明令禁止）；
#   Reanchor(重判) —— 中线规则若失步，一次拖拽就够不到四个角。
# Snap(吸附) 是纯手感，单独一例钉「容差口径为零时不得破坏其它分量」。

# The block reaches all four corners, and the DEFAULT pair (bottom-right, zero offset) degrades to the
# legacy rectangle — the guarantee that stage 1 moved no existing drawing.
# 图签够到四个角，且**默认**停靠对（右下、零偏移）退化为旧矩形 —— 即「阶段 1 没挪动任何既有图纸」的保证。
func gpTestTitleBlockAtReachesAllFourCorners() -> void:
	var gpFrame: Rect2 = Rect2(100.0, 50.0, 790.0, 565.0)
	var gpW: float = GPSheet.GP_TB_BLOCK_W
	var gpH: float = GPSheet.GP_TB_BLOCK_H
	# Default pair == the legacy rectangle. / 默认对 == 旧矩形。
	var gpBr: Rect2 = GPFrameGeometry.gpTitleBlockAt(gpFrame, GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, Vector2.ZERO)
	gpCheck(gpBr.is_equal_approx(Rect2(gpFrame.end.x - gpW, gpFrame.end.y - gpH, gpW, gpH)),
		"右下 + 零偏移必须退化为 v0.1 的旧矩形")
	gpCheck(gpBr.is_equal_approx(GPFrameGeometry.gpTitleBlockIn(gpFrame)),
		"默认正推 == gpTitleBlockIn（同一个事实的两个入口不得分家）")
	# Bottom-left: flush against the left edge. / 左下：贴住左缘。
	var gpBl: Rect2 = GPFrameGeometry.gpTitleBlockAt(gpFrame, GPSheet.GP_TB_ANCHOR_BOTTOM_LEFT, Vector2.ZERO)
	gpApprox(gpBl.position.x, gpFrame.position.x, GP_EPS, "左下锚角应贴住内框左缘")
	gpApprox(gpBl.end.y, gpFrame.end.y, GP_EPS, "左下锚角下边仍应贴住内框下边")
	# Top-right / top-left mirror on y. / 右上 / 左上在 y 上镜像。
	var gpTr: Rect2 = GPFrameGeometry.gpTitleBlockAt(gpFrame, GPSheet.GP_TB_ANCHOR_TOP_RIGHT, Vector2.ZERO)
	gpApprox(gpTr.end.x, gpFrame.end.x, GP_EPS, "右上锚角右边应贴住内框右边")
	gpApprox(gpTr.position.y, gpFrame.position.y, GP_EPS, "右上锚角应贴住内框上缘")
	var gpTl: Rect2 = GPFrameGeometry.gpTitleBlockAt(gpFrame, GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2.ZERO)
	gpCheck(gpTl.position.is_equal_approx(gpFrame.position), "左上 + 零偏移应贴住内框左上角")
	# A positive offset moves INTO the frame, whatever the anchor. / 无论锚角为何，正偏移都向**框内**移。
	var gpMoved: Rect2 = GPFrameGeometry.gpTitleBlockAt(gpFrame, GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(30.0, 20.0))
	gpApprox(gpMoved.position.x, gpFrame.position.x + 30.0, GP_EPS, "左上锚角 + 正偏移应向框内右移")
	gpApprox(gpMoved.position.y, gpFrame.position.y + 20.0, GP_EPS, "左上锚角 + 正偏移应向框内下移")


# The round-trip guarantee: offset == Offset(frame, anchor, At(frame, anchor, offset)) for every
# anchor. A silent sign error here is what the user feels as 「我一开拖图签就跳」.
# 往返保证：对每个锚角 offset == Offset(frame, anchor, At(frame, anchor, offset))。这里一个静默的
# 符号错误，用户的感受就是「我一开拖图签就跳」。
func gpTestTitleBlockOffsetInvertsTitleBlockAt() -> void:
	var gpFrame: Rect2 = Rect2(40.0, 30.0, 790.0, 565.0)
	var gpMaxX: float = gpFrame.size.x - GPSheet.GP_TB_BLOCK_W
	var gpMaxY: float = gpFrame.size.y - GPSheet.GP_TB_BLOCK_H
	var gpAnchors: Array = [
		GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, GPSheet.GP_TB_ANCHOR_BOTTOM_LEFT,
		GPSheet.GP_TB_ANCHOR_TOP_RIGHT, GPSheet.GP_TB_ANCHOR_TOP_LEFT]
	var gpOffsets: Array = [Vector2.ZERO, Vector2(37.0, 23.0), Vector2(gpMaxX, gpMaxY)]
	for gpAnchor in gpAnchors:
		for gpOff in gpOffsets:
			var gpRect: Rect2 = GPFrameGeometry.gpTitleBlockAt(gpFrame, gpAnchor as int, gpOff as Vector2)
			var gpBack: Vector2 = GPFrameGeometry.gpTitleBlockOffset(gpFrame, gpAnchor as int, gpRect)
			gpCheck(gpBack.is_equal_approx(gpOff as Vector2),
				"锚角 %d、偏移 %s 的往返必须恒等" % [gpAnchor as int, str(gpOff)])


# The clamp folds the offset into [0, span - block]; on a frame NARROWER than the block the upper
# bound collapses to zero, so the block hugs its edge and OVERFLOWS the far side — visible, never
# vanished (Rev.3 §9-①). Idempotent, so callers may clamp defensively.
# 钳制把偏移收进 [0, 跨度 − 图签]；当内框比图签**窄**时上限塌缩为零，图签贴边、向另一侧**溢出** ——
# 可见、绝不消失（Rev.3 §9-①）。幂等，故调用方可以放心地上再钳一次。
func gpTestTitleBlockClampOverflowsInsteadOfVanishing() -> void:
	var gpFrame: Rect2 = Rect2(0.0, 0.0, 790.0, 565.0)
	var gpMaxX: float = gpFrame.size.x - GPSheet.GP_TB_BLOCK_W
	var gpMaxY: float = gpFrame.size.y - GPSheet.GP_TB_BLOCK_H
	# Negative components fold to zero (a drag past the edge asks for "flush"). / 负分量收零（拖过边即要求「贴边」）。
	var gpNeg: Vector2 = GPFrameGeometry.gpClampTitleBlock(gpFrame, GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(-12.0, -3.0))
	gpCheck(gpNeg.is_equal_approx(Vector2.ZERO), "负偏移应被收进零（贴边）")
	# Above the span folds to the upper bound. / 超出跨度收进上限。
	var gpBig: Vector2 = GPFrameGeometry.gpClampTitleBlock(gpFrame, GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(9999.0, 9999.0))
	gpCheck(gpBig.is_equal_approx(Vector2(gpMaxX, gpMaxY)), "超界偏移应收进「跨度 − 图签」上限")
	# Inside stays untouched. / 界内原样保留。
	var gpIn: Vector2 = GPFrameGeometry.gpClampTitleBlock(gpFrame, GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(37.0, 23.0))
	gpCheck(gpIn.is_equal_approx(Vector2(37.0, 23.0)), "合法偏移不得被钳制改动")
	# Idempotent. / 幂等。
	var gpTwice: Vector2 = GPFrameGeometry.gpClampTitleBlock(gpFrame, GPSheet.GP_TB_ANCHOR_TOP_LEFT, gpBig)
	gpCheck(gpTwice.is_equal_approx(gpBig), "钳制必须幂等")
	# A frame NARROWER than the block: upper bound collapses to zero — hug + overflow, not vanish.
	# 比图签**窄**的内框：上限塌缩为零 —— 贴边溢出，而不是消失。
	var gpNarrow: Rect2 = Rect2(0.0, 0.0, 100.0, 40.0)
	var gpSq: Vector2 = GPFrameGeometry.gpClampTitleBlock(gpNarrow, GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(50.0, 30.0))
	gpCheck(gpSq.is_equal_approx(Vector2.ZERO), "窄框上钳制应塌缩为零（图签贴边溢出，而非消失）")
	# And the placed rectangle stays a VALID rectangle — nothing degenerate for a renderer to choke on.
	# 且落位矩形仍是**有效**矩形 —— 不给渲染器任何退化输入。
	var gpPlaced: Rect2 = GPFrameGeometry.gpTitleBlockAt(gpNarrow, GPSheet.GP_TB_ANCHOR_TOP_LEFT, gpSq)
	gpCheck(gpPlaced.size == Vector2(GPSheet.GP_TB_BLOCK_W, GPSheet.GP_TB_BLOCK_H),
		"窄框下图签矩形尺寸仍须完整")


# The snap folds a component to zero when it is within tolerance — the only step that is about feel.
# Zero (or negative) tolerance disables it without a second code path: only an already-zero component
# snaps, so a caller can turn the snap off by passing zero.
# 容差内的分量吸附到零 —— 唯一关乎手感的一步。零（或负）容差无需第二条代码路径即可关闭：只有本就是零的
# 分量会吸，故调用方传零即可关掉吸附。
func gpTestTitleBlockSnapArrivesAtTheInnerEdge() -> void:
	# Within tolerance both components snap. / 容差内两分量都吸。
	gpCheck(GPFrameGeometry.gpSnapTitleBlock(Vector2(3.0, 4.5), 5.0).is_equal_approx(Vector2.ZERO),
		"容差 5mm 内的偏移应吸附到零")
	# Only the component within tolerance snaps. / 只有容差内的分量吸。
	var gpHalf: Vector2 = GPFrameGeometry.gpSnapTitleBlock(Vector2(2.0, 12.0), 5.0)
	gpCheck(gpHalf.is_equal_approx(Vector2(0.0, 12.0)), "只有落在容差内的分量吸附，另一分量原样保留")
	# Exactly ON the tolerance snaps (<=). / 恰好等于容差也吸（<=）。
	gpCheck(GPFrameGeometry.gpSnapTitleBlock(Vector2(5.0, 9.0), 5.0).is_equal_approx(Vector2(0.0, 9.0)),
		"恰好等于容差的分量应吸附")
	# Beyond tolerance stays. / 超出容差原样保留。
	var gpFar: Vector2 = GPFrameGeometry.gpSnapTitleBlock(Vector2(5.001, 9.0), 5.0)
	gpCheck(gpFar.is_equal_approx(Vector2(5.001, 9.0)), "超出容差的偏移不得被吸附改动")
	# Zero tolerance disables the snap. / 零容差即关闭吸附。
	gpCheck(GPFrameGeometry.gpSnapTitleBlock(Vector2(0.001, 0.0), 0.0).is_equal_approx(Vector2(0.001, 0.0)),
		"零容差下非零分量不得吸附")
	# Negative tolerance behaves like zero (no crash, no snap). / 负容差等同零（不崩、不吸）。
	gpCheck(GPFrameGeometry.gpSnapTitleBlock(Vector2(1.0, 0.0), -3.0).is_equal_approx(Vector2(1.0, 0.0)),
		"负容差等同关闭吸附")


# Crossing the frame's centre line on an axis flips that axis's bit; a block exactly centred keeps the
# DEFAULT code. This is 「过中线即换角」 — the rule that lets one drag gesture reach all four corners.
# 在某轴越过内框中线即翻转该轴的位；恰好居中保持**默认**编码。这正是「过中线即换角」—— 让一次拖拽
# 够到四个角的规则。
func gpTestReanchorCrossesTheCentreLine() -> void:
	var gpFrame: Rect2 = Rect2(0.0, 0.0, 790.0, 565.0)
	var gpW: float = GPSheet.GP_TB_BLOCK_W
	var gpH: float = GPSheet.GP_TB_BLOCK_H
	# Bottom-right quadrant (where the block lives by default). / 右下象限（图签默认所在）。
	gpEq(GPFrameGeometry.gpReanchor(gpFrame, Rect2(gpFrame.end.x - gpW, gpFrame.end.y - gpH, gpW, gpH)),
		GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, "右下象限重判为右下锚角")
	# Bottom-left. / 左下。
	gpEq(GPFrameGeometry.gpReanchor(gpFrame, Rect2(gpFrame.position.x, gpFrame.end.y - gpH, gpW, gpH)),
		GPSheet.GP_TB_ANCHOR_BOTTOM_LEFT, "左下象限重判为左下锚角")
	# Top-right. / 右上。
	gpEq(GPFrameGeometry.gpReanchor(gpFrame, Rect2(gpFrame.end.x - gpW, gpFrame.position.y, gpW, gpH)),
		GPSheet.GP_TB_ANCHOR_TOP_RIGHT, "右上象限重判为右上锚角")
	# Top-left. / 左上。
	gpEq(GPFrameGeometry.gpReanchor(gpFrame, Rect2(gpFrame.position.x, gpFrame.position.y, gpW, gpH)),
		GPSheet.GP_TB_ANCHOR_TOP_LEFT, "左上象限重判为左上锚角")
	# Just PAST the centre line on x only: the y bit must stay. / 仅在 x 上刚过中线：y 位必须保持。
	var gpMidX: float = gpFrame.get_center().x
	gpEq(GPFrameGeometry.gpReanchor(gpFrame,
			Rect2(gpMidX + 1.0, gpFrame.end.y - gpH, gpW, gpH)),
		GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, "仅越过 x 中线时 y 位不得翻转")
	gpEq(GPFrameGeometry.gpReanchor(gpFrame,
			Rect2(gpMidX - 1.0 - gpW, gpFrame.end.y - gpH, gpW, gpH)),
		GPSheet.GP_TB_ANCHOR_BOTTOM_LEFT, "x 中线左侧即交给左下")
	# Exactly centred: a tie goes to the DEFAULT code (strict comparisons). / 恰好居中：平局归默认编码（严格比较）。
	var gpCentre: Rect2 = Rect2(gpMidX - gpW / 2.0, gpFrame.get_center().y - gpH / 2.0, gpW, gpH)
	gpEq(GPFrameGeometry.gpReanchor(gpFrame, gpCentre), GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT,
		"恰好居中的图签回落到默认（右下）编码")


# The live-sheet entry point: anchor + offset from the sheet, clamped, placed. A null sheet degrades to
# the legacy default so a renderer mid-teardown keeps drawing yesterday's block.
# 实时图纸入口：自图纸取锚角 + 偏移，钳制后落位。空图纸退化为旧默认，使拆除中的渲染器仍能画出昨天的图签。
func gpTestTitleBlockPlacedReadsTheSheetAndClamps() -> void:
	var gpS: GPSheet = _gpA3()
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	# Default sheet: identical to the legacy rectangle. / 默认图纸：与旧矩形完全一致。
	gpCheck(GPFrameGeometry.gpTitleBlockPlaced(gpFrame, gpS)
		.is_equal_approx(GPFrameGeometry.gpTitleBlockIn(gpFrame)),
		"默认停靠对下 gpTitleBlockPlaced 应等于旧矩形")
	# An offset pair is honoured after clamping. / 偏移对经钳制后被采纳。
	gpS.gpSetTbPlacement(GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(30.0, 20.0))
	gpCheck(GPFrameGeometry.gpTitleBlockPlaced(gpFrame, gpS)
		.is_equal_approx(GPFrameGeometry.gpTitleBlockAt(gpFrame, GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(30.0, 20.0))),
		"合法停靠对应被如实落位")
	# An out-of-range offset is clamped, not trusted. / 越界偏移被钳制、而非被信任。
	gpS.gpSetTbPlacement(GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(9999.0, 9999.0))
	var gpClamped: Rect2 = GPFrameGeometry.gpTitleBlockPlaced(gpFrame, gpS)
	gpApprox(gpClamped.end.x, gpFrame.end.x, GP_EPS, "越界偏移落位后图签右缘应贴住内框右缘")
	gpApprox(gpClamped.end.y, gpFrame.end.y, GP_EPS, "越界偏移落位后图签下缘应贴住内框下缘")
	# Null sheet degrades to the legacy default. / 空图纸退化为旧默认。
	gpCheck(GPFrameGeometry.gpTitleBlockPlaced(gpFrame, null)
		.is_equal_approx(GPFrameGeometry.gpTitleBlockIn(gpFrame)),
		"空图纸时退化为旧默认矩形")
