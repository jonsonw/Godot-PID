class_name GPGTestEdgeDash
extends GPGTest
# Copyright © 2026 Jonson Wang
# Dash chopping: the part of line styling that Godot does not give us.
# 虚线切段：Godot 没有直接提供给我们的那部分线型能力。
# Pure geometry, so it runs headlessly with no rasteriser involved.
# 纯几何，故可 headless 运行，不涉光栅化器。


# An empty pattern means "solid" — the caller uses draw_polyline and no segments are produced.
# 空图案表示「实线」—— 调用方改用 draw_polyline，不产生任何分段。
func gpTestEmptyPatternProducesNoSegments() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(100.0, 0.0)])
	gpEq(GPEdgeDash.gpSegments(gpPts, PackedFloat32Array()).size(), 0,
		"empty pattern yields no segments / 空图案不产生分段")
	gpApprox(GPEdgeDash.gpCycle(PackedFloat32Array()), 0.0, 0.001, "empty cycle is 0 / 空图案周期为 0")
	gpApprox(GPEdgeDash.gpCycle(PackedFloat32Array([10.0, 4.0])), 14.0, 0.001,
		"cycle is ink + gap / 周期为「有墨 + 空白」")


# A 100-long run with a 10-on / 4-off pattern: 8 inked pieces, the last one clipped.
# 长 100 的直段配 10 有墨 / 4 空白图案：8 段有墨，最后一段被截断。
func gpTestStraightRunDashCount() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(100.0, 0.0)])
	var gpSegs: PackedVector2Array = GPEdgeDash.gpSegments(gpPts, PackedFloat32Array([10.0, 4.0]))
	gpEq(gpSegs.size(), 16, "8 inked segments = 16 endpoints / 8 段有墨 = 16 个端点")
	gpApprox(gpSegs[0].x, 0.0, 0.001, "first dash starts at the line start / 首个划段起于线首")
	gpApprox(gpSegs[1].x, 10.0, 0.001, "first dash is 10 long / 首个划段长 10")
	gpApprox(gpSegs[2].x, 14.0, 0.001, "second dash starts after the gap / 第二个划段起于空白之后")
	gpApprox(gpSegs[15].x, 100.0, 0.001, "last dash is clipped at the end / 末段被终点截断")


# The whole point of carrying the walk across corners: an elbow must NOT restart the pattern.
# 跨拐点延续「行进状态」的全部意义：拐角处绝不能重启图案。
func gpTestPhaseContinuesAcrossACorner() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(50.0, 0.0), Vector2(50.0, 50.0)])
	var gpSegs: PackedVector2Array = GPEdgeDash.gpSegments(gpPts, PackedFloat32Array([10.0, 4.0]))
	# On the first leg, 50 = 3 full cycles (42) + 8 of ink, so 8 of ink are consumed and only
	# 2 remain when the corner is reached.
	# 第一段上 50 = 3 个完整周期（42）+ 8 有墨，故到达拐点时「还剩 2 有墨」。
	var gpFirstOnSecondLeg: Vector2 = Vector2.INF
	var gpI: int = 0
	while gpI + 1 < gpSegs.size():
		var gpA: Vector2 = gpSegs[gpI]
		if absf(gpA.x - 50.0) < 0.001 and absf(gpA.y) < 0.001:
			gpFirstOnSecondLeg = gpSegs[gpI + 1]
			break
		gpI += 2
	gpCheck(gpFirstOnSecondLeg != Vector2.INF, "a dash starts exactly at the corner / 有段划起于拐点")
	# A restart would have made this 10 long; carrying the phase makes it 2.
	# 若重启，此段长应为 10；延续相位则为 2。
	gpApprox(gpFirstOnSecondLeg.y, 2.0, 0.001, "leftover ink is 2, not a fresh 10 / 剩余有墨为 2 而非全新的 10")


# Total inked length must match the duty cycle of the pattern (independent of where the
# corners fall), which is what keeps two lines of the same type looking equally dark.
# 有墨总长必须符合图案的占空比（与拐点位置无关），这正是「同型线看起来一样深浅」的原因。
func gpTestInkedLengthMatchesDutyCycle() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(60.0, 0.0), Vector2(60.0, 40.0), Vector2(10.0, 40.0)])
	var gpPat: PackedFloat32Array = PackedFloat32Array([8.0, 4.0])
	var gpSegs: PackedVector2Array = GPEdgeDash.gpSegments(gpPts, gpPat)
	var gpInk: float = 0.0
	var gpI: int = 0
	while gpI + 1 < gpSegs.size():
		gpInk += gpSegs[gpI].distance_to(gpSegs[gpI + 1])
		gpI += 2
	# Total length 60 + 40 + 50 = 150, duty cycle 8/12.
	# 总长 60 + 40 + 50 = 150，占空比 8/12。
	gpCheck(absf(gpInk - 150.0 * 8.0 / 12.0) <= 8.0,
		"inked length tracks the 8/12 duty cycle / 有墨总长贴合 8/12 占空比")


# A degenerate polyline must not produce output (and must not hang the editor).
# 退化折线不得产生输出（更不得把编辑器卡死）。
func gpTestDegenerateInputIsSafe() -> void:
	var gpOne: PackedVector2Array = PackedVector2Array([Vector2(5.0, 5.0)])
	gpEq(GPEdgeDash.gpSegments(gpOne, PackedFloat32Array([4.0, 2.0])).size(), 0,
		"single point yields nothing / 单点不产出")
	var gpZero: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 0.0)])
	gpEq(GPEdgeDash.gpSegments(gpZero, PackedFloat32Array([4.0, 2.0])).size(), 0,
		"zero-length leg yields nothing / 零长段不产出")
	# A pattern of all zeros would spin forever without the internal guard.
	# 全零图案若无内部保护会无限循环。
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(50.0, 0.0)])
	gpEq(GPEdgeDash.gpSegments(gpPts, PackedFloat32Array([0.0, 0.0])).size(), 0,
		"all-zero pattern terminates / 全零图案会终止")
