class_name GPGTestEdgeTagLayout
extends GPGTest
# Copyright © 2026 Jonson Wang
# Line-number placement: above a horizontal run, left of a vertical one.
# 管线编号落位：水平管正上方、竖管左侧。
# "Above" and "left" are SCREEN directions, so the convention must not flip when the two ends
# are swapped — that is what the second case below guards.
# 「上方」与「左侧」是屏幕方向，故两端对调时约定不得随之翻转 —— 这正是下面第二个用例所守护的。


# Longest leg wins: the number goes where there is room for it.
# 最长段优先：编号放在放得下的地方。
func gpTestLongestLegIsChosen() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(10.0, 200.0)])
	gpEq(GPEdgeTagLayout.gpLongestSegment(gpPts), 1, "the vertical leg is the longest / 垂直段最长")
	gpEq(GPEdgeTagLayout.gpLongestSegment(PackedVector2Array([Vector2(0.0, 0.0)])), -1,
		"no leg at all returns -1 / 无段时返回 -1")


# Horizontal run: centred, sitting above the line by exactly the gap.
# 水平管：居中，恰好位于管线上方一个净距处。
func gpTestHorizontalTagSitsAbove() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(200.0, 0.0)])
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 40.0, 16.0, true)
	gpCheck(not bool(gpPl.get("vertical", true)), "a horizontal run is not vertical / 水平段不是竖管")
	gpApprox(float(gpPl.get("rot", 1.0)), 0.0, 0.001, "no rotation on a horizontal run / 水平段不旋转")
	var gpPos: Vector2 = gpPl.get("pos", Vector2.ZERO)
	gpApprox(gpPos.x, 80.0, 0.001, "centred on the 200-long run / 在长 200 的段上居中")
	gpApprox(gpPos.y, -GPEdgeTagLayout.GP_GAP, 0.001, "sits one gap above the line / 位于线上方一个净距处")


# ... and stays above when the pipe is drawn right-to-left.
# ... 且当管线自右向左绘制时依然在上方。
func gpTestHorizontalTagStaysAboveWhenReversed() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(200.0, 0.0), Vector2(0.0, 0.0)])
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 40.0, 16.0, true)
	var gpPos: Vector2 = gpPl.get("pos", Vector2.ZERO)
	gpCheck(gpPos.y < 0.0, "reversed run still numbers above the line / 反向段仍在管线上方编号")


# Vertical run, rotated: the glyph column sits one gap to the LEFT of the pipe.
# 竖管（旋转）：字形列位于管线左侧一个净距处。
func gpTestVerticalRotatedTagSitsLeft() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 200.0)])
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 40.0, 16.0, true)
	gpCheck(bool(gpPl.get("vertical", false)), "a vertical run is vertical / 垂直段是竖管")
	gpApprox(float(gpPl.get("rot", 0.0)), -PI * 0.5, 0.001, "rotated -90 degrees / 旋转 -90 度")
	var gpPos: Vector2 = gpPl.get("pos", Vector2.ZERO)
	# Column centre = pos.x - height/2 = -gap  ->  pos.x = -gap + height/2 = -8 + 8 = 0
	# 列中心 = pos.x - 字高/2 = -净距  ->  pos.x = -净距 + 字高/2 = -8 + 8 = 0
	gpApprox(gpPos.x - 16.0 * 0.5, -GPEdgeTagLayout.GP_GAP, 0.001,
		"glyph column sits one gap left of the pipe / 字形列位于管线左侧一个净距处")
	# Origin starts half a text-width BELOW the midpoint so the text reads bottom-to-top.
	# 原点起于中点「下方」半个文字宽度处，使文字自下而上阅读。
	gpApprox(gpPos.y, 100.0 + 40.0 * 0.5, 0.001, "origin is half a text-width below the midpoint / 原点位于中点下方半个文字宽度处")


# Vertical run, unrotated: kept horizontal and right-aligned to the pipe.
# 竖管（不旋转）：保持水平，并右对齐到管线。
func gpTestVerticalUnrotatedTagKeepsReadingDirection() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 200.0)])
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 40.0, 16.0, false)
	gpApprox(float(gpPl.get("rot", 1.0)), 0.0, 0.001, "unrotated text / 文字不旋转")
	var gpPos: Vector2 = gpPl.get("pos", Vector2.ZERO)
	gpCheck(gpPos.x < 0.0, "text sits left of the pipe / 文字位于管线左侧")
	gpApprox(gpPos.x, -GPEdgeTagLayout.GP_GAP - 40.0, 0.001, "right-aligned to the pipe / 右对齐到管线")


# A two-point degenerate polyline still returns a usable dictionary.
# 退化的两点重合折线仍返回可用的字典。
func gpTestDegeneratePolylineIsSafe() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(5.0, 5.0), Vector2(5.0, 5.0)])
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 20.0, 12.0, true)
	gpCheck(gpPl.has("pos") and gpPl.has("rot"), "placement always has pos and rot / 落位始终含 pos 与 rot")


# A number rotated onto a VERTICAL run gets a VERTICAL shoulder — parallel to the text it cradles.
# 旋转到**竖管**上的编号得到一条**竖直**肩线 —— 与其所托的文字平行。
# The whole callout is built in the tag's own baseline frame, so rotating the number rotates the
# shelf with it. Building it on the world axes instead draws a horizontal tick straight ACROSS the
# vertical column of glyphs, which reads as a stray dash rather than as a shelf under the text.
# 整条引出线在编号自身的基线坐标系中构造，故编号一旋转、托线随之旋转。若按世界坐标轴构造，则会画出
# 一道横切竖直字列的短线 —— 读起来像一道游离的破折号，而不像托住文字的托线。
func gpTestRotatedTagLeaderShoulderIsVertical() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 200.0)])
	var gpW: float = 40.0
	var gpH: float = 3.0
	# Drag the number 30 mm to the LEFT of its pipe, so a leader is required at all.
	# 把编号向左拖离管线 30mm，使引出线必须出现。
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, gpW, gpH, true,
		GPEdgeTagLayout.GP_GAP, Vector2(-30.0, 0.0))
	gpApprox(float(gpPl.get("rot", 0.0)), -PI * 0.5, 0.001, "still rotated -90 deg / 仍旋转 -90°")
	var gpPos: Vector2 = gpPl.get("pos", Vector2.ZERO)
	var gpLeader: PackedVector2Array = GPEdgeTagLayout.gpLeader(gpPts, gpPl, gpW, gpH)
	gpEq(gpLeader.size(), 3, "rotated leader is the same 3-point callout / 旋转后仍是三点引出线")
	var gpE: Vector2 = gpLeader[1]
	var gpT: Vector2 = gpLeader[2]
	gpApprox(absf(gpT.x - gpE.x), 0.0, 0.001, "shoulder is vertical, not horizontal / 肩线竖直而非水平")
	gpApprox(absf(gpT.y - gpE.y), gpW + 2.0 * GPEdgeTagLayout.GP_LEADER_OVERHANG, 0.001,
		"shoulder spans the text plus both overhangs / 肩线跨度 = 字长 + 两端外伸")
	gpApprox(gpE.x, gpPos.x + GPEdgeTagLayout.GP_LEADER_PAD, 0.001,
		"shoulder sits one pad off the baseline / 肩线距基线一个 pad")
	var gpAnchor: Vector2 = gpLeader[0]
	gpCheck(absf(gpAnchor.x - gpE.x) > 0.001 and absf(gpAnchor.y - gpE.y) > 0.001,
		"the segment toward the pipe is genuinely slanted / 指向管线的一段确实是斜的")
	# The anchor really lands ON the pipe, not merely somewhere near it.
	# 锚点确实落在管线上，而非仅在其附近某处。
	var gpOn: Vector2 = GPEdgeTagLayout.gpNearestOnPolyline(gpPts, gpAnchor)
	gpApprox(gpOn.distance_to(gpAnchor), 0.0, 0.001, "anchor lies on the pipe / 锚点落在管线上")


# A number pulled CLEAR of a VERTICAL pipe is laid FLAT: a callout is read horizontally.
# 被拉离**竖管**的编号一律放平：引出标注按横排阅读。
# The rotation is a space-saving device that only pays while the number hugs its pipe; once the
# number is a detached callout the reader should not have to tilt their head for it.
# 旋转是仅在编号贴着管线时才划算的省地方手段；一旦编号成为脱离的引出标注，就不该让读者歪头去看。
func gpTestDetachedVerticalNumberLaysFlat() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 200.0)])
	var gpW: float = 40.0
	var gpH: float = 3.0
	var gpAt: Dictionary = GPEdgeTagLayout.gpPlaceCallout(gpPts, gpW, gpH, true,
		GPEdgeTagLayout.GP_GAP, Vector2(-30.0, 0.0))
	gpApprox(float(gpAt.get("rot", 9.0)), 0.0, 0.001, "the number is laid flat / 编号被放平")
	gpCheck(bool(gpAt.get("detached", false)), "it is detached / 它已脱离")
	gpCheck(bool(gpAt.get("flipped", false)), "and the flip is reported / 并记录已翻转")
	var gpLeader: PackedVector2Array = gpAt.get("leader", PackedVector2Array())
	gpEq(gpLeader.size(), 3, "flat callout = slant + shelf / 横排标注 = 斜段 + 托线")
	gpApprox(gpLeader[1].y, gpLeader[2].y, 0.001, "the shelf is horizontal / 托线水平")
	var gpBox: Rect2 = GPEdgeTagLayout.gpBox(gpAt, gpW, gpH)
	gpCheck(gpLeader[1].y > gpBox.end.y, "the shelf lies UNDER the text / 托线位于文字下方")
	var gpOn: Vector2 = GPEdgeTagLayout.gpNearestOnPolyline(gpPts, gpLeader[0])
	gpApprox(gpOn.distance_to(gpLeader[0]), 0.0, 0.001, "anchor lands on the pipe / 锚点落在管线上")


# A number still attached keeps the column — the flip must not fire early.
# 仍附着的编号保持竖排字列 —— 翻转不得提前触发。
func gpTestAttachedVerticalNumberStaysAColumn() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 200.0)])
	var gpAt: Dictionary = GPEdgeTagLayout.gpPlaceCallout(gpPts, 40.0, 3.0, true,
		GPEdgeTagLayout.GP_GAP, Vector2(-2.0, 0.0))
	gpApprox(float(gpAt.get("rot", 9.0)), -PI * 0.5, 0.001, "still the rotated column / 仍是竖排字列")
	gpCheck(not bool(gpAt.get("flipped", false)), "no flip while attached / 附着时未翻转")
	gpEq((gpAt.get("leader", PackedVector2Array()) as PackedVector2Array).size(), 0,
		"and no leader either / 且无引出线")


# The flip happens IN PLACE, and at the SAME standoff: the baseline edge and the centre line stay
# put, so the number un-rotates rather than jumping sideways.
# 翻转是**原地**的，且净距不变：基线边与中心线都不动，故编号是「转正」而非横向跳走。
# The preserved standoff is not cosmetic — it is what makes the leader appear at that very instant
# instead of a few millimetres of dragging later, since a wide flat box would otherwise land much
# closer to the pipe than the narrow column it replaced.
# 净距不变并非外观问题 —— 它正是「引出线在那一刻当场出现、而非再拖几毫米才出现」的原因：否则
# 一个宽扁的包围盒会比它替换掉的窄字列贴近管线得多。
func gpTestFlipKeepsTheNumberInPlace() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 200.0)])
	var gpW: float = 40.0
	var gpH: float = 3.0
	var gpOff: Vector2 = Vector2(-30.0, 0.0)
	var gpColumn: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, gpW, gpH, true,
		GPEdgeTagLayout.GP_GAP, gpOff)
	var gpAt: Dictionary = GPEdgeTagLayout.gpPlaceCallout(gpPts, gpW, gpH, true,
		GPEdgeTagLayout.GP_GAP, gpOff)
	var gpB0: Rect2 = GPEdgeTagLayout.gpBox(gpColumn, gpW, gpH)
	var gpB1: Rect2 = GPEdgeTagLayout.gpBox(gpAt, gpW, gpH)
	gpApprox(gpB1.end.x, gpB0.end.x, 0.001, "the edge nearest the pipe does not move / 距管线最近的边不动")
	gpApprox(gpB1.get_center().y, gpB0.get_center().y, 0.001, "nor does the centre line / 中心线亦不动")
	var gpC0: float = GPEdgeTagLayout.gpClearance(gpPts, gpColumn, gpW, gpH)
	var gpC1: float = GPEdgeTagLayout.gpClearance(gpPts, gpAt, gpW, gpH)
	gpApprox(gpC1, gpC0, 0.001, "the standoff is preserved / 净距保持不变")
	gpCheck(gpC1 > GPEdgeTagLayout.GP_LEADER_MIN, "and is enough for the leader / 且足以画出引出线")


# The hard case: a LONG number, dragged only just past the threshold, whose flat box therefore
# lands right ACROSS its own pipe on the first estimate.
# 最刁的一种：**长**编号、且只刚过阈值一点点，故其横排包围盒在首次估算时正好横躺压住自己的管线。
# This is a regression pin. Measuring the correction from the box's nearest EDGE breaks down here,
# because that distance is 0 whenever the pipe lies UNDER the box — the correction then falls short
# on every pass and the number ends up flat with NO leader, edge almost touching the pipe. The
# correction therefore measures from the box CENTRE and subtracts the box's half-extent along that
# direction (its support function), which stays exact in this case too.
# 这是一条回归钉子。以包围盒**近边**量取修正量就在此失效：只要管线落在包围盒**之下**，该距离即为 0，
# 于是每轮修正都不足，最后编号已放平却**没有**引出线，其边几乎贴住管线。故修正量改自**中心**量起、
# 再减去包围盒沿该方向的半宽高（其支撑函数），那种情形同样精确。
func gpTestFlipEscapesALongNumberThatFirstCoversThePipe() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 200.0)])
	var gpW: float = 40.0
	var gpH: float = 3.0
	# 5 mm of drag: the column's clearance is 6 mm (just past the 5 mm threshold), while the flat box
	# is 40 mm wide and centred 6 mm off the pipe -> it covers the pipe completely.
	# 拖 5mm：字列净距 6mm（刚过 5mm 阈值），而横排包围盒宽 40mm、中心距管线 6mm -> 完全压住管线。
	var gpOff: Vector2 = Vector2(-5.0, 0.0)
	var gpColumn: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, gpW, gpH, true,
		GPEdgeTagLayout.GP_GAP, gpOff)
	var gpAt: Dictionary = GPEdgeTagLayout.gpPlaceCallout(gpPts, gpW, gpH, true,
		GPEdgeTagLayout.GP_GAP, gpOff)
	gpCheck(bool(gpAt.get("flipped", false)), "the flip did fire / 确实触发了翻转")
	gpEq((gpAt.get("leader", PackedVector2Array()) as PackedVector2Array).size(), 3,
		"and the leader came with it / 且引出线随之出现")
	var gpC0: float = GPEdgeTagLayout.gpClearance(gpPts, gpColumn, gpW, gpH)
	var gpC1: float = GPEdgeTagLayout.gpClearance(gpPts, gpAt, gpW, gpH)
	gpCheck(gpC1 > GPEdgeTagLayout.GP_LEADER_MIN,
		"the number does NOT end up covering its pipe / 编号最终没有压住其管线")
	gpApprox(gpC1, gpC0, 0.001, "standoff restored to the column's own / 净距恢复到字列原有的值")
	gpApprox(GPEdgeTagLayout.gpBox(gpAt, gpW, gpH).end.x,
		GPEdgeTagLayout.gpBox(gpColumn, gpW, gpH).end.x, 0.001,
		"the near edge is back where the column's was / 近边回到字列原来的位置")


# The invariant this whole change exists for: a number that HAS a leader is never a vertical
# column, and a number that still has no leader never flips. Swept across the drag range AND at two
# text widths, so neither a flickering threshold nor a flip lagging the leader by a few millimetres
# could pass — and so the long-number case (whose flat box can land across its pipe) is covered too.
# 本次改动存在的全部理由：**有**引出线的编号绝不是竖排字列，尚未有引出线的编号也绝不翻转。全程扫描，
# 且取两种文字宽度，故任何闪动的阈值、或比引出线晚几毫米的翻转都不可能通过 —— 长编号的情形
#（其横排包围盒可能横躺压住管线）也随之被覆盖。
func gpTestLeaderAndFlipNeverDisagree() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 200.0)])
	var gpH: float = 3.0
	var gpSawLeader: bool = false
	var gpSawColumn: bool = false
	for gpW in [12.0, 40.0]:
		for gpL in [0.0, 1.0, 2.0, 3.0, 4.0, 4.5, 5.0, 6.0, 10.0, 20.0, 40.0]:
			var gpAt: Dictionary = GPEdgeTagLayout.gpPlaceCallout(gpPts, gpW, gpH, true,
				GPEdgeTagLayout.GP_GAP, Vector2(-gpL, 0.0))
			var gpHas: bool = (gpAt.get("leader", PackedVector2Array()) as PackedVector2Array).size() > 0
			var gpFlat: bool = float(gpAt.get("rot", 9.0)) == 0.0
			gpCheck(gpHas == gpFlat, "leader and laid-flat agree, w=" + str(gpW)
				+ " drag=" + str(gpL) + " / 引出线与横排状态一致")
			if gpHas:
				gpSawLeader = true
			else:
				gpSawColumn = true
	gpCheck(gpSawLeader, "a long drag does produce a leader / 长距离拖拽确实产生引出线")
	gpCheck(gpSawColumn, "a short one does not / 短距离则不产生")


# Helper: "drag" the number to a target box centre the way a real drag does — nudge by the shortfall
# and re-place. One step is NOT enough: the move itself can change WHICH leg is under the number, and
# that changes the standoff the box is laid at.
# 辅助：以真实拖拽的方式把编号「拖」到目标包围盒中心 —— 按欠量微调并重新落位。**一步不够**：移动
# 本身可能改变编号底下是**哪一段**，而那会改变包围盒的落位净距。
func _gpDragTo(gpPts: PackedVector2Array, gpW: float, gpH: float, gpTarget: Vector2) -> Dictionary:
	var gpOff: Vector2 = Vector2.ZERO
	var gpAt: Dictionary = GPEdgeTagLayout.gpPlaceCallout(gpPts, gpW, gpH, true,
		GPEdgeTagLayout.GP_GAP, gpOff)
	for gpI in range(6):
		var gpC: Vector2 = GPEdgeTagLayout.gpBox(gpAt, gpW, gpH).get_center()
		if gpC.distance_to(gpTarget) < 1e-4:
			break
		gpOff += gpTarget - gpC
		gpAt = GPEdgeTagLayout.gpPlaceCallout(gpPts, gpW, gpH, true,
			GPEdgeTagLayout.GP_GAP, gpOff)
	return gpAt


# The primitive the whole rule rests on: "is the leg nearest this point vertical?" — asked AT THE
# NUMBER, not of the pipe.
# 整条规则所依赖的原语：「离此点最近的那一段是否竖直？」—— 在**编号处**问，而非问整条管线。
func gpTestLocalLegOrientation() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, 200.0), Vector2(120.0, 200.0)])
	gpCheck(GPEdgeTagLayout.gpIsVerticalAt(gpPts, Vector2(20.0, 100.0)),
		"beside the vertical leg -> vertical / 竖直段旁 -> 竖直")
	gpCheck(not GPEdgeTagLayout.gpIsVerticalAt(gpPts, Vector2(60.0, 180.0)),
		"above the horizontal leg -> horizontal / 水平段上方 -> 水平")
	gpEq(GPEdgeTagLayout.gpNearestSegment(gpPts, Vector2(20.0, 100.0)), 0,
		"the nearest leg beside the vertical run is the vertical one / 竖直段旁读到的是竖直段")
	gpEq(GPEdgeTagLayout.gpNearestSegment(gpPts, Vector2(60.0, 180.0)), 1,
		"and above the horizontal run it is the horizontal one / 水平段上方读到的是水平段")
	# The nearest POINT and the nearest LEG come from one computation, so the leg the form was read
	# from always contains the point the leader anchors on.
	# 「最近点」与「最近段」出自同一次计算，故据以判定形态的那一段，必定包含引出线所锚的点。
	var gpQ: Vector2 = GPEdgeTagLayout.gpNearestOnPolyline(gpPts, Vector2(60.0, 180.0))
	gpApprox(gpQ.y, 200.0, 1e-6, "the nearest point lies on the horizontal leg / 最近点落在水平段上")
	gpEq(GPEdgeTagLayout.gpNearestSegment(PackedVector2Array([Vector2(1.0, 1.0)]), Vector2.ZERO), -1,
		"a degenerate polyline has no leg / 退化折线没有段")
	gpCheck(not GPEdgeTagLayout.gpIsVerticalAt(PackedVector2Array([Vector2(1.0, 1.0)]), Vector2.ZERO),
		"and falls back to the readable horizontal rule / 并回落为可读的横排规则")
	gpCheck(not GPEdgeTagLayout.gpIsVerticalAt(
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(50.0, 50.0)]), Vector2(25.0, 25.0)),
		"a 45 deg leg is read as horizontal / 45° 段按水平读")


# THE REPORTED CASE. A number standing as a column on the VERTICAL leg of an L-shaped pipe, dragged
# sideways onto that same pipe's HORIZONTAL leg, must read left-to-right — it must not stay a column
# merely because the leg it CAME FROM (and the pipe's longest leg) is vertical.
# 用户报告的情形：立在 L 形管线**竖直**段上的字列，被侧向拖到同一管线的**水平**段上后，必须自左向右
# 阅读 —— 绝不能仅因为「它来自的那一段（也是该管线的最长段）是竖直的」而继续竖排。
func gpTestTagOnAHorizontalLegReadsHorizontally() -> void:
	# An L as a routed pipe really looks: the vertical leg first and longest, then a horizontal one.
	# 真实布线后的 L 形：竖直段在前且最长，随后一条水平段。
	var gpPts: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, 200.0), Vector2(120.0, 200.0)])
	var gpW: float = 40.0
	var gpH: float = 3.0
	gpEq(GPEdgeTagLayout.gpLongestSegment(gpPts), 0, "the vertical leg is the longest / 竖直段最长")
	# As it comes: the number sits on that vertical leg and stands as a column.
	# 初始：编号位于该竖直段上，立为字列。
	var gpHome: Dictionary = GPEdgeTagLayout.gpPlaceCallout(gpPts, gpW, gpH, true)
	gpApprox(float(gpHome.get("rot", 9.0)), -PI * 0.5, 0.001, "it starts as a column / 初始为字列")
	# Dragged onto the HORIZONTAL leg and left ATTACHED there — its box one gap above that leg.
	# 拖到**水平**段上，并留在该处**附着** —— 包围盒位于该段上方一个净距处。
	var gpLeg: Vector2 = Vector2(60.0, 200.0)
	var gpTarget: Vector2 = gpLeg + Vector2(0.0, -(GPEdgeTagLayout.GP_GAP + gpH * 0.5))
	var gpAt: Dictionary = _gpDragTo(gpPts, gpW, gpH, gpTarget)
	gpApprox(float(gpAt.get("rot", 9.0)), 0.0, 0.001,
		"it reads left-to-right on the horizontal leg / 在水平段上自左向右阅读")
	gpCheck(not bool(gpAt.get("vertical", true)), "the leg under it is horizontal / 其下之段为水平段")
	gpApprox(GPEdgeTagLayout.gpBox(gpAt, gpW, gpH).get_center().distance_to(gpTarget), 0.0, 1e-3,
		"the drag is honoured, not overridden / 拖拽落点被尊重，未被改写")
	gpCheck(not bool(gpAt.get("detached", true)), "and it is still attached / 且仍然附着")
	gpApprox(GPEdgeTagLayout.gpClearance(gpPts, gpAt, gpW, gpH), GPEdgeTagLayout.GP_GAP, 1e-3,
		"at the drafting gap above that leg / 位于该段上方制图净距处")
	gpEq((gpAt.get("leader", PackedVector2Array()) as PackedVector2Array).size(), 0,
		"attached, so no leader is drawn / 附着，故不画引出线")


# ... while a drag that merely slides the number ALONG the vertical leg keeps the column. The new
# rule must not flatten a number that is still over a vertical leg.
# ... 而只是**沿竖直段**滑动编号时仍保持字列。新规则不得把仍压在竖直段上的编号放平。
func gpTestDraggingAlongTheVerticalLegKeepsTheColumn() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, 200.0), Vector2(120.0, 200.0)])
	for gpDy in [-60.0, 0.0, 60.0]:
		var gpAt: Dictionary = GPEdgeTagLayout.gpPlaceCallout(gpPts, 40.0, 3.0, true,
			GPEdgeTagLayout.GP_GAP, Vector2(0.0, gpDy))
		gpApprox(float(gpAt.get("rot", 9.0)), -PI * 0.5, 0.001,
			"sliding along the pipe (dy=" + str(gpDy) + ") keeps the column / 沿管线滑动保持字列")
		gpCheck(not bool(gpAt.get("detached", true)),
			"and it is attached (dy=" + str(gpDy) + ") / 且附着")
		gpEq((gpAt.get("leader", PackedVector2Array()) as PackedVector2Array).size(), 0,
			"so no leader (dy=" + str(gpDy) + ") / 故无引出线")


# The MIRROR: an L whose LONGEST leg is horizontal, with the number dragged onto its vertical leg —
# that one must stand up as a column. Without this, the rule could pass by simply never rotating.
# 镜像：**最长**段为水平段的 L 形管线，编号被拖到其竖直段上时须立为字列。缺此一例，规则可能靠
# 「永不旋转」而蒙混过关。
func gpTestTagOnAVerticalLegOfAHorizontalPipeIsAColumn() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(200.0, 0.0), Vector2(200.0, 120.0)])
	var gpW: float = 40.0
	var gpH: float = 3.0
	gpEq(GPEdgeTagLayout.gpLongestSegment(gpPts), 0, "the horizontal leg is the longest / 水平段最长")
	var gpHome: Dictionary = GPEdgeTagLayout.gpPlaceCallout(gpPts, gpW, gpH, true)
	gpApprox(float(gpHome.get("rot", 9.0)), 0.0, 0.001, "it starts flat / 初始横排")
	var gpLeg: Vector2 = Vector2(200.0, 60.0)
	var gpTarget: Vector2 = gpLeg + Vector2(-(GPEdgeTagLayout.GP_GAP + gpH * 0.5), 0.0)
	var gpAt: Dictionary = _gpDragTo(gpPts, gpW, gpH, gpTarget)
	gpApprox(float(gpAt.get("rot", 9.0)), -PI * 0.5, 0.001,
		"it stands as a column on the vertical leg / 在竖直段上立为字列")
	gpCheck(bool(gpAt.get("vertical", false)), "the leg under it is vertical / 其下之段为竖直段")
	gpApprox(GPEdgeTagLayout.gpBox(gpAt, gpW, gpH).get_center().distance_to(gpTarget), 0.0, 1e-3,
		"the drag is honoured, not overridden / 拖拽落点被尊重，未被改写")
	gpCheck(not bool(gpAt.get("detached", true)), "still attached / 仍然附着")
	gpEq((gpAt.get("leader", PackedVector2Array()) as PackedVector2Array).size(), 0,
		"no leader while attached / 附着时不画引出线")


# Across a drag that carries the number from the vertical leg onto the horizontal one and then far
# off the pipe, the form must change AT MOST ONCE, and a number that HAS a leader must always be
# flat. Pinned on an L-shaped pipe, where "which leg is under it" and "is it detached" are two
# DIFFERENT questions — on a straight pipe they coincide, so the earlier sweep could not tell them
# apart, and a flickering boundary between the two rules would have gone unnoticed.
# 在一段把编号从竖直段带过水平段、再拖离管线的拖拽全程中，形态至多改变**一次**，且**有**引出线的
# 编号必为横排。钉子下在 L 形管线上：此处「底下是哪一段」与「是否已脱离」是两个**不同**的问题 ——
# 在直管上二者重合，故先前的扫描无法区分，而规则之间闪动的边界也就无从被发现。
func gpTestFormChangesOnceAcrossALDrag() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, 200.0), Vector2(120.0, 200.0)])
	var gpW: float = 40.0
	var gpH: float = 3.0
	var gpWasColumn: bool = true
	var gpSawColumn: bool = false
	var gpSawFlat: bool = false
	var gpFlips: int = 0
	var gpTargets: Array[Vector2] = [
		Vector2(-2.5, 100.0), Vector2(-2.5, 40.0), Vector2(-2.5, 160.0),
		Vector2(20.0, 185.0), Vector2(60.0, 196.0), Vector2(120.0, 196.0),
		Vector2(300.0, 350.0),
	]
	for gpT in gpTargets:
		var gpAt: Dictionary = _gpDragTo(gpPts, gpW, gpH, gpT)
		var gpColumn: bool = float(gpAt.get("rot", 0.0)) != 0.0
		var gpHasLeader: bool = (gpAt.get("leader", PackedVector2Array()) as PackedVector2Array).size() > 0
		gpCheck(not (gpColumn and gpHasLeader),
			"a number with a leader is never a column (" + str(gpT) + ") / 有引出线的编号绝不是字列")
		if gpColumn:
			gpSawColumn = true
		else:
			gpSawFlat = true
		if gpColumn != gpWasColumn:
			gpFlips += 1
			gpWasColumn = gpColumn
	gpCheck(gpSawColumn and gpSawFlat, "the drag crosses both forms / 全程跨越两种形态")
	gpEq(gpFlips, 1, "and the form changes exactly once — no flicker / 形态恰改变一次，无闪动")
