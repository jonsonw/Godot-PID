class_name GPGTestEdgeRoute
extends GPGTest
# Copyright © 2026 Jonson Wang
# Routing: the one geometric decision a P&ID reader notices first.
# 布线：P&ID 读者第一时间就会注意到的那个几何决策。
# Every case below is a DRAFTING situation, not a maths exercise: two nozzles facing each other,
# a pipe that has to turn a corner, a pair of ports facing the same way, and so on.
# 下面每个用例都是「制图场景」而非数学习题：两个正对的管口、必须拐弯的管线、
# 同向的两个端口等等。


# Two nozzles facing each other on one axis: one straight run, nothing in between.
# 两个管口在同一轴线上正对：一条直段，中间什么都不该有。
func gpTestFacingEndsCollapseToAStraightRun() -> void:
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(0.0, 0.0), "dir": Vector2(1.0, 0.0)},
		{"pos": Vector2(200.0, 0.0), "dir": Vector2(-1.0, 0.0)}, [], true)
	gpEq(gpPts.size(), 2, "facing horizontal ends route to 2 points / 正对水平端路由为 2 点")
	gpApprox(gpPts[0].x, 0.0, 0.001, "route starts at the source port / 路由起点即起点端口")
	gpApprox(gpPts[1].x, 200.0, 0.001, "route ends at the target port / 路由终点即终点端口")

	var gpV: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(0.0, 0.0), "dir": Vector2(0.0, 1.0)},
		{"pos": Vector2(0.0, 200.0), "dir": Vector2(0.0, -1.0)}, [], true)
	gpEq(gpV.size(), 2, "facing vertical ends route to 2 points / 正对垂直端路由为 2 点")


# Off-axis ends produce exactly one corner (a Z), and every leg stays axis-aligned.
# 错开的两端恰好产生一个拐点（Z 形），且每一段都保持轴对齐。
func gpTestOffsetEndsProduceOneOrthogonalCorner() -> void:
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(0.0, 0.0), "dir": Vector2(1.0, 0.0)},
		{"pos": Vector2(300.0, 120.0), "dir": Vector2(-1.0, 0.0)}, [], true)
	# The source stub is collinear with the run that follows it, so gpClean folds it in: the
	# drawn polyline is source -> corner -> target stub -> target.
	# 起点引出段与其后的直段共线，故 gpClean 会把它并进去：最终折线为
	# 起点 -> 拐点 -> 终点引入段 -> 终点。
	gpEq(gpPts.size(), 4, "Z route is source, corner, target stub, target / Z 路由为 起点-拐点-终点引入-终点")
	gpCheck(GPEdgeRoute.gpIsOrthogonal(gpPts), "every leg is axis-aligned / 每段均轴对齐")
	# The corner sits on the SOURCE row and on the TARGET column: that is what makes it a Z.
	# 拐点位于「起点所在行」与「终点所在列」的交点：这正是 Z 形的定义。
	gpApprox(gpPts[1].y, 0.0, 0.001, "corner keeps the source height / 拐点保持起点高度")
	gpApprox(gpPts[1].x, 300.0 - GPEdgeRoute.GP_STUB, 0.001, "corner sits on the target stub column / 拐点位于终点引入段所在列")
	gpApprox(gpPts[2].y, 120.0, 0.001, "target stub keeps the target height / 终点引入段保持终点高度")


# Mixed axes (a side nozzle into a bottom nozzle): one corner, entered along the target normal.
# 混合轴（侧管口接底部管口）：一个拐点，并沿终点法线进入。
func gpTestMixedAxesFormAnL() -> void:
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(0.0, 0.0), "dir": Vector2(1.0, 0.0)},
		{"pos": Vector2(200.0, -150.0), "dir": Vector2(0.0, 1.0)}, [], true)
	# 3 points: both stubs are collinear with the leg that follows or precedes them, so gpClean
	# folds them in — the drawn polyline is exactly source -> corner -> target.
	# 3 个点：两个引出段都与其后（或前）的段共线，故 gpClean 会把它们并进去 ——
	# 最终折线恰好是 起点 -> 拐点 -> 终点。
	gpEq(gpPts.size(), 3, "L route has one corner / L 路由有一个拐点")
	gpCheck(GPEdgeRoute.gpIsOrthogonal(gpPts), "L legs are axis-aligned / L 的各段轴对齐")
	# The last leg must run opposite to the target normal (i.e. into the nozzle).
	# 最后一段必须与终点法线相反（即「进入」管口）。
	var gpLast: Vector2 = gpPts[2] - gpPts[1]
	gpCheck(gpLast.dot(Vector2(0.0, 1.0)) < 0.0, "last leg enters against the target normal / 最后一段逆着终点法线进入")


# Same-way nozzles on one line: a straight run would cross the target symbol, so we detour.
# 同向且共线的两个管口：直连会横穿终点图元，故必须绕行。
func gpTestSameWayCollinearEndsDetour() -> void:
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(0.0, 0.0), "dir": Vector2(1.0, 0.0)},
		{"pos": Vector2(200.0, 0.0), "dir": Vector2(1.0, 0.0)}, [], true)
	gpCheck(gpPts.size() >= 5, "same-way collinear ends detour instead of folding back / 同向共线端绕行而非折返")
	gpCheck(GPEdgeRoute.gpIsOrthogonal(gpPts), "detour stays axis-aligned / 绕行保持轴对齐")
	# The detour must leave the symbol's own row: some leg sits clear of y = 0.
	# 绕行必须离开图元所在的行：应有某段远离 y = 0。
	var gpClear: bool = false
	for gpP in gpPts:
		if absf(gpP.y) >= GPEdgeRoute.GP_DETOUR * 0.9:
			gpClear = true
	gpCheck(gpClear, "detour clears the symbol row / 绕行避开图元所在行")


# Back-to-back nozzles: the pipe has to come back around, again without crossing a symbol.
# 背对背的两个管口：管线必须绕回来，同样不能穿过图元。
func gpTestBackToBackEndsDetour() -> void:
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(0.0, 0.0), "dir": Vector2(1.0, 0.0)},
		{"pos": Vector2(-200.0, 0.0), "dir": Vector2(1.0, 0.0)}, [], true)
	gpCheck(gpPts.size() >= 5, "back-to-back ends detour / 背对背端绕行")
	gpCheck(GPEdgeRoute.gpIsOrthogonal(gpPts), "back-to-back detour stays orthogonal / 背对背绕行保持正交")


# A dangling end declares no normal; the axis is borrowed from the direction to the other end.
# 悬空端不声明法线；其轴向借用「指向另一端」的方向。
func gpTestDanglingEndBorrowsAnAxis() -> void:
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(0.0, 0.0), "dir": Vector2.ZERO},
		{"pos": Vector2(150.0, 0.0), "dir": Vector2(-1.0, 0.0)}, [], true)
	gpEq(gpPts.size(), 2, "dangling end still routes to a straight run / 悬空端仍路由为直段")
	gpCheck(GPEdgeRoute.gpIsOrthogonal(gpPts), "dangling route is axis-aligned / 悬空路由轴对齐")


# A free end gets NO stub: the dangling point the user placed is the end of the pipe, exactly.
# 悬空端「没有」引出段：用户放置的那个悬空点就是管线的精确端点。
func gpTestDanglingEndHasNoStub() -> void:
	var gpFree: Vector2 = Vector2(400.0, 0.0)
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(0.0, 0.0), "dir": Vector2(1.0, 0.0), "bound": true},
		{"pos": gpFree, "dir": Vector2.ZERO, "bound": false}, [], true)
	gpEq(gpPts[gpPts.size() - 1], gpFree, "free end lands exactly on its stored point / 悬空端精确落在已存点上")


# Stored waypoints are the user's: honoured verbatim, never re-routed.
# 已存折点属于用户：原样采纳，绝不重新布线。
func gpTestStoredWaypointsWin() -> void:
	var gpWay: Array[Vector2] = [Vector2(100.0, 0.0), Vector2(100.0, 100.0)]
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(0.0, 0.0), "dir": Vector2(1.0, 0.0)},
		{"pos": Vector2(200.0, 100.0), "dir": Vector2(-1.0, 0.0)}, gpWay, true)
	gpEq(gpPts.size(), 4, "user waypoints are kept / 保留用户折点")
	gpEq(gpPts[1], Vector2(100.0, 0.0), "first waypoint preserved / 第一个折点保留")
	gpEq(gpPts[2], Vector2(100.0, 100.0), "second waypoint preserved / 第二个折点保留")


# Shift-drawn edges are straight, even when the ports would have produced an L.
# 按 Shift 画出的边是直的，即便端口本会产生 L 形。
func gpTestNonOrthoIsAStraightLine() -> void:
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(0.0, 0.0), "dir": Vector2(1.0, 0.0)},
		{"pos": Vector2(200.0, 150.0), "dir": Vector2(-1.0, 0.0)}, [], false)
	gpEq(gpPts.size(), 2, "straight edge is 2 points / 直连边为 2 点")
	gpCheck(not GPEdgeRoute.gpIsOrthogonal(gpPts), "straight edge is allowed to be diagonal / 直连边允许斜向")


# Degenerate input (both ends on the same point) must still return something drawable.
# 退化输入（两端重合）仍须返回可绘制的结果。
func gpTestCoincidentEndsStayDrawable() -> void:
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(
		{"pos": Vector2(50.0, 50.0), "dir": Vector2.ZERO},
		{"pos": Vector2(50.0, 50.0), "dir": Vector2.ZERO}, [], true)
	gpCheck(gpPts.size() >= 2, "coincident ends still yield a polyline / 重合端仍产出折线")
	gpCheck(GPEdgeRoute.gpIsOrthogonal(gpPts), "coincident route stays orthogonal / 重合端路由保持正交")


# gpClean drops a corner that adds nothing, and keeps a real corner.
# gpClean 会丢弃毫无贡献的拐点，而保留真正的拐点。
func gpTestCleanDropsOnlyCollinearPoints() -> void:
	var gpFlat: PackedVector2Array = GPEdgeRoute.gpClean(
		[Vector2(0.0, 0.0), Vector2(50.0, 0.0), Vector2(100.0, 0.0)])
	gpEq(gpFlat.size(), 2, "collinear middle point removed / 共线中间点被移除")
	var gpCorner: PackedVector2Array = GPEdgeRoute.gpClean(
		[Vector2(0.0, 0.0), Vector2(50.0, 0.0), Vector2(50.0, 60.0)])
	gpEq(gpCorner.size(), 3, "real corner kept / 真正的拐点保留")
	var gpDup: PackedVector2Array = GPEdgeRoute.gpClean(
		[Vector2(0.0, 0.0), Vector2(0.0, 0.0), Vector2(30.0, 0.0)])
	gpEq(gpDup.size(), 2, "duplicate point removed / 重复点被移除")
