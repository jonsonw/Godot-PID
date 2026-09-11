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
