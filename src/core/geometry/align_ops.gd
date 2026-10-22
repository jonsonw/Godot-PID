class_name GPAlignOps
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Pure geometry for align / distribute (A7). No graph, no UI, no services — only rectangles in,
# top-left origins out, so the eight operations can be pinned headlessly with plain numbers.
# 对齐 / 分布（A7）的纯几何。不碰图、不碰界面、不碰服务 —— 只进矩形、出左上角原点，
# 使八种操作都能用普通数字在 headless 下钉死。
#
# Why origins and not centers / 为何给原点而非中心：
# The caller converts to and from GPPIDNode.gpPosition (which IS the centre) using the symbol's
# envelope. Keeping that conversion OUT of this module means the maths never has to know what a
# symbol is — and a test never has to build one.
# 调用方用图元包络在原点与 GPPIDNode.gpPosition（**中心**）之间换算。把换算留在此模块之外，
# 数学就不必知道「图元」是什么，测试也不必造一个图元。
#
# Why equal SPACING and not equal centres / 为何等**间距**而非等中心：
# Drafting convention distributes the GAPS (the whitespace between envelopes), because that is
# what the eye reads as even. Equal centres would make a wide vessel and a narrow valve look
# unevenly packed.
# 制图惯例分布的是**间隙**（包络之间的空白），因为那才是眼睛读作「均匀」的东西。
# 等中心会让一台宽设备与一个窄阀门看起来疏密不匀。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The eight operations. Values are part of the public surface (the context menu maps ids to them).
# 八种操作。取值属公开面（右键菜单把 id 映射到它们）。
enum Mode {
	GP_LEFT,        # align left edges / 左对齐
	GP_HCENTER,     # align horizontal centres / 水平居中
	GP_RIGHT,       # align right edges / 右对齐
	GP_TOP,         # align top edges / 上对齐
	GP_VCENTER,     # align vertical centres / 垂直居中
	GP_BOTTOM,      # align bottom edges / 下对齐
	GP_DIST_H,      # equal horizontal gaps / 水平等间距
	GP_DIST_V,      # equal vertical gaps / 垂直等间距
}


# New top-left origins for every input rectangle, in the SAME order.
# 每个输入矩形的新左上角原点，顺序与输入一致。
# Fewer than two rectangles is a no-op for every mode (aligning one thing to itself would still
# push a phantom undo step), and that is expressed by returning the inputs unchanged.
# 少于两个矩形时所有模式都是空操作（把一件东西与自己对不齐，却仍会压入幽灵撤销步），
# 这通过原样返回输入来表达。
static func gpTargets(gpRects: Array[Rect2], gpMode: int) -> Array[Vector2]:
	var gpOut: Array[Vector2] = []
	for gpR in gpRects:
		gpOut.append(gpR.position)
	if gpRects.size() < 2:
		return gpOut
	match gpMode:
		Mode.GP_LEFT:
			var gpMinX: float = gpRects[0].position.x
			for gpR in gpRects:
				gpMinX = minf(gpMinX, gpR.position.x)
			for gpI in range(gpOut.size()):
				gpOut[gpI] = Vector2(gpMinX, gpOut[gpI].y)
		Mode.GP_HCENTER:
			var gpUnion: Rect2 = gpRects[0]
			for gpR in gpRects:
				gpUnion = gpUnion.merge(gpR)
			var gpCx: float = gpUnion.get_center().x
			for gpI in range(gpOut.size()):
				gpOut[gpI] = Vector2(gpCx - gpRects[gpI].size.x * 0.5, gpOut[gpI].y)
		Mode.GP_RIGHT:
			var gpMaxR: float = gpRects[0].end.x
			for gpR in gpRects:
				gpMaxR = maxf(gpMaxR, gpR.end.x)
			for gpI in range(gpOut.size()):
				gpOut[gpI] = Vector2(gpMaxR - gpRects[gpI].size.x, gpOut[gpI].y)
		Mode.GP_TOP:
			var gpMinY: float = gpRects[0].position.y
			for gpR in gpRects:
				gpMinY = minf(gpMinY, gpR.position.y)
			for gpI in range(gpOut.size()):
				gpOut[gpI] = Vector2(gpOut[gpI].x, gpMinY)
		Mode.GP_VCENTER:
			var gpUnionV: Rect2 = gpRects[0]
			for gpR in gpRects:
				gpUnionV = gpUnionV.merge(gpR)
			var gpCy: float = gpUnionV.get_center().y
			for gpI in range(gpOut.size()):
				gpOut[gpI] = Vector2(gpOut[gpI].x, gpCy - gpRects[gpI].size.y * 0.5)
		Mode.GP_BOTTOM:
			var gpMaxB: float = gpRects[0].end.y
			for gpR in gpRects:
				gpMaxB = maxf(gpMaxB, gpR.end.y)
			for gpI in range(gpOut.size()):
				gpOut[gpI] = Vector2(gpOut[gpI].x, gpMaxB - gpRects[gpI].size.y)
		Mode.GP_DIST_H:
			return _gpDistribute(gpRects, true)
		Mode.GP_DIST_V:
			return _gpDistribute(gpRects, false)
	return gpOut


# Equalise the GAPS along one axis, keeping the two outermost edges where they are.
# 沿一个轴等化**间隙**，两端最外侧的边保持不动。
# The order of the returned array matches the INPUT, while the distribution itself walks a sorted
# index list — the caller's node order must not influence the result, or the same selection would
# produce different layouts depending on click order.
# 返回数组顺序与**输入**一致，而分布本身沿排序后的下标表行走 —— 调用方的节点顺序不得影响结果，
# 否则同一选择集会因点击顺序不同而排出不同布局。
static func _gpDistribute(gpRects: Array[Rect2], gpHorizontal: bool) -> Array[Vector2]:
	var gpOut: Array[Vector2] = []
	for gpR in gpRects:
		gpOut.append(gpR.position)
	# Sort indices by the leading edge along the axis. / 按下标沿轴的首边排序。
	var gpOrder: Array[int] = []
	for gpI in range(gpRects.size()):
		gpOrder.append(gpI)
	gpOrder.sort_custom(func(gpA: int, gpB: int) -> bool:
		return gpRects[gpA].position.x < gpRects[gpB].position.x if gpHorizontal \
			else gpRects[gpA].position.y < gpRects[gpB].position.y)
	# Span covered by the outermost edges, minus the sum of the sizes: that is the whitespace
	# to divide into (n-1) equal gaps.
	# 最外侧边覆盖的跨度减去尺寸之和 = 待分成 (n-1) 个等间隙的空白。
	var gpFirst: Rect2 = gpRects[gpOrder[0]]
	var gpLast: Rect2 = gpRects[gpOrder[gpOrder.size() - 1]]
	var gpStart: float = gpFirst.position.x if gpHorizontal else gpFirst.position.y
	var gpEnd: float = gpLast.end.x if gpHorizontal else gpLast.end.y
	var gpUsed: float = 0.0
	for gpR in gpRects:
		gpUsed += gpR.size.x if gpHorizontal else gpR.size.y
	var gpGap: float = (gpEnd - gpStart - gpUsed) / float(gpOrder.size() - 1)
	var gpCursor: float = gpStart
	for gpI in gpOrder:
		var gpR2: Rect2 = gpRects[gpI]
		if gpHorizontal:
			gpOut[gpI] = Vector2(gpCursor, gpOut[gpI].y)
			gpCursor += gpR2.size.x + gpGap
		else:
			gpOut[gpI] = Vector2(gpOut[gpI].x, gpCursor)
			gpCursor += gpR2.size.y + gpGap
	return gpOut


# Whether an operation needs at least two objects (all of them do, but the caller also uses this
# to disable menu entries honestly instead of offering a no-op).
# 该操作是否需要至少两个对象（全都需要，但调用方也用它**诚实地**禁用菜单项，而不是提供一个空操作）。
static func gpNeedsTwo() -> int:
	return 2
