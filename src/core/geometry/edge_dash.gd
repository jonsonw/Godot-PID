class_name GPEdgeDash
extends RefCounted
# Copyright © 2026 Jonson Wang
# Turn a polyline + a dash pattern into the list of inked segments.
# 把「折线 + 虚线图案」转换为有墨线段列表。
#
# Why this is a separate pure module / 为何单独成模块且为纯函数：
#   Godot's draw_line has no dash support, so dashing means chopping the polyline ourselves.
#   Keeping the chopping pure and separate makes the pattern testable without a viewport
#   (headless CI has no rasteriser) and keeps GPEdgePainter a thin paint-only shell.
#   Godot 的 draw_line 不支持虚线，故虚线必须自己切段。把切段逻辑做成独立的纯函数，
#   使图案无需视口即可测试（headless CI 无光栅化器），并让 GPEdgePainter 保持「只画」的薄壳。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


# Total length of one full pattern cycle (ink + gaps). 0 when the pattern is empty or degenerate.
# 一个完整图案周期的总长（有墨 + 空白）。图案为空或退化时为 0。
static func gpCycle(gpPattern: PackedFloat32Array) -> float:
	var gpSum: float = 0.0
	for gpV in gpPattern:
		gpSum += maxf(gpV, 0.0)
	return gpSum


# Split a polyline into inked segments according to a pattern.
# 按图案把折线切分为有墨线段。
# [param gpPts]     polyline (2+ points) / 折线（至少 2 点）
# [param gpPattern] alternating ink / gap lengths in world units; EMPTY means "solid, call
#                   draw_polyline instead" / 世界单位下交替的「有墨/空白」长度；为空表示实线
#                   （此时应改调 draw_polyline）
# [return] flat point pairs: [a0,b0, a1,b1, ...] — every two entries are one inked segment.
# [return] 扁平的点对：[a0,b0, a1,b1, ...] —— 每两个元素为一段有墨线段。
#
# Phase continuity / 相位连续性：
#   the walk (which pattern entry we are inside, and how much of it is left) is carried across
#   corners instead of restarting per leg. Restarting per leg makes a dash-dot line look like a
#   random dot pattern around every elbow.
#   「当前处在图案的第几项、还剩多少」跨拐点延续，而不是每段重新开始。每段重启会让点划线在
#   每个拐角处看起来像随机点阵。
static func gpSegments(gpPts: PackedVector2Array, gpPattern: PackedFloat32Array) -> PackedVector2Array:
	var gpOut: PackedVector2Array = PackedVector2Array()
	if gpPts.size() < 2 or gpPattern.is_empty():
		return gpOut
	if gpCycle(gpPattern) <= 0.0:
		return gpOut
	var gpIdx: int = 0
	var gpLeft: float = maxf(gpPattern[gpIdx], 0.0)
	var gpInk: bool = true
	for gpI in range(gpPts.size() - 1):
		var gpA: Vector2 = gpPts[gpI]
		var gpB: Vector2 = gpPts[gpI + 1]
		var gpLen: float = gpA.distance_to(gpB)
		if gpLen <= 0.0001:
			continue
		var gpDir: Vector2 = (gpB - gpA) / gpLen
		var gpT: float = 0.0
		# Guard the loop: a pattern entry of length 0 would otherwise spin forever.
		# 循环保护：长度为 0 的图案项否则会无限循环。
		var gpGuard: int = 0
		while gpT < gpLen and gpGuard < 100000:
			gpGuard += 1
			var gpStep: float = minf(gpLeft, gpLen - gpT)
			if gpInk and gpStep > 0.0:
				gpOut.append(gpA + gpDir * gpT)
				gpOut.append(gpA + gpDir * (gpT + gpStep))
			gpT += gpStep
			gpLeft -= gpStep
			if gpLeft <= 0.0001:
				gpIdx = (gpIdx + 1) % gpPattern.size()
				gpLeft = maxf(gpPattern[gpIdx], 0.0)
				gpInk = not gpInk
				# A zero-length entry still has to advance, otherwise the loop stalls on it.
				# 零长项也必须推进，否则循环会停在该项上。
				if gpLeft <= 0.0001:
					gpIdx = (gpIdx + 1) % gpPattern.size()
					gpLeft = maxf(gpPattern[gpIdx], 0.0)
					gpInk = not gpInk
	return gpOut
