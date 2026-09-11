class_name GPEdgeTagLayout
extends RefCounted
# Copyright © 2026 Jonson Wang
# Where a line number sits on its pipe.
# 管线编号落在其管线的什么位置。
#
# The drafting rule / 制图规则：
#   "number sits above a horizontal run, to the left of a vertical one". "Above / left" is
#   defined in SCREEN space (y grows downwards), not along the line's own direction, so a pipe
#   drawn right-to-left still gets its number above — otherwise flipping two symbols would flip
#   the drawing convention with them.
#   「编号位于水平管正上方、竖管左侧」。「上方 / 左侧」以屏幕空间定义（y 向下增长），而非
#   沿管线自身方向 —— 否则把两个图元左右对调，制图约定也会跟着翻转。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Clearance between the pipe centre-line and the text.
# 管线中心线与文字之间的净距。
const GP_GAP: float = 8.0


# Index of the longest leg, or -1 when the polyline has none.
# 最长段的索引；折线无段时返回 -1。
# The longest leg is used because it is the leg a reader's eye follows first, and it is the only
# leg guaranteed to have room for the whole number on a short zig-zag.
# 取最长段是因为读者的视线首先落在它上面，且在短促的 Z 形走线中，也只有它保证放得下整个编号。
static func gpLongestSegment(gpPts: PackedVector2Array) -> int:
	if gpPts.size() < 2:
		return -1
	var gpBest: int = 0
	var gpBestLen: float = -1.0
	for gpI in range(gpPts.size() - 1):
		var gpL: float = gpPts[gpI].distance_to(gpPts[gpI + 1])
		if gpL > gpBestLen:
			gpBestLen = gpL
			gpBest = gpI
	return gpBest


# Place a tag on a polyline.
# 把位号放到折线上。
# [param gpPts]     the routed polyline / 已完成布线的折线
# [param gpTextW]   measured text width in world units / 实测文字宽度（世界单位）
# [param gpTextH]   measured text height in world units / 实测文字高度（世界单位）
# [param gpRotate]  rotate the text -90 deg on a vertical run / 竖管上是否把文字旋转 -90°
# [param gpGap]     clearance override / 净距覆盖值
# [return] {"pos": Vector2, "rot": float, "vertical": bool}
#          pos is the text ORIGIN (draw_string's baseline start), already in world coordinates.
#          pos 是文字原点（draw_string 的基线起点），已是世界坐标。
static func gpPlace(gpPts: PackedVector2Array, gpTextW: float, gpTextH: float,
		gpRotate: bool, gpGap: float = GP_GAP) -> Dictionary:
	var gpI: int = gpLongestSegment(gpPts)
	if gpI < 0:
		return {"pos": Vector2.ZERO, "rot": 0.0, "vertical": false}
	var gpA: Vector2 = gpPts[gpI]
	var gpB: Vector2 = gpPts[gpI + 1]
	var gpMid: Vector2 = (gpA + gpB) * 0.5
	var gpD: Vector2 = gpB - gpA
	var gpVertical: bool = absf(gpD.y) > absf(gpD.x)
	if not gpVertical:
		# Horizontal run: centred, sitting on top of the line.
		# 水平管：居中，位于管线正上方。
		return {
			"pos": Vector2(gpMid.x - gpTextW * 0.5, gpMid.y - gpGap),
			"rot": 0.0,
			"vertical": false,
		}
	if gpRotate:
		# Rotated -90 deg: the text baseline runs bottom-to-top, so the origin starts half a
		# text-width BELOW the midpoint and the glyph column is nudged right by half its height
		# so the column (not the baseline) is what sits gpGap to the left of the pipe.
		# 旋转 -90°：文字基线自下而上，故原点起于中点「下方」半个文字宽度处；字形列再右移
		# 半个字高，使「字形列（而非基线）」位于管线左侧 gpGap 处。
		return {
			"pos": Vector2(gpMid.x - gpGap + gpTextH * 0.5, gpMid.y + gpTextW * 0.5),
			"rot": -PI * 0.5,
			"vertical": true,
		}
	# Unrotated: keep it readable, right-aligned to the pipe.
	# 不旋转：保持可读，右对齐到管线。
	return {
		"pos": Vector2(gpMid.x - gpGap - gpTextW, gpMid.y + gpTextH * 0.35),
		"rot": 0.0,
		"vertical": true,
	}
