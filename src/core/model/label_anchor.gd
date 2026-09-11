class_name GPLabelAnchor
extends RefCounted
# Copyright © 2026 Jonson Wang
# Where a node's label sits relative to its envelope — the geometry behind "the tag can be
# moved inside / above / below the symbol, but only so far".
# 节点标签相对包络的位置 —— 「位号可在图元内 / 上 / 下移动，但不能超出一定范畴」背后的几何。
#
# Two decisions worth stating / 两条值得写明的设计决定：
#  1. Offsets are NORMALISED (1.0 = half the envelope), never pixels. Pixels drift the moment
#     the user zooms, switches DPI or prints — the label would detach from its own symbol.
#     偏移是**归一化**的（1.0 = 半个包络），绝不是像素。用户缩放、切换 DPI 或打印时，
#     像素偏移会立刻漂移，标签会与自己的图元脱开。
#  2. The offset is CLAMPED to GP_RANGE half-envelopes from the symbol centre, so a label can
#     dodge a crowded nozzle but can never wander onto the neighbour's equipment and be misread
#     as belonging to it.
#     偏移被限制在距图元中心 GP_RANGE 个半包络内，使标签可以避开密集管口，但绝不会漂到
#     隔壁设备上被误读成属于那台设备。
#
# Coding rule: every variable declares its type explicitly; all functions are static (pure).
# 编码规范：所有变量均显式声明类型；函数全部为静态（纯函数）。

# Anchor positions relative to the envelope. / 相对包络的锚点位置。
enum GPAnchor {
	GP_AUTO,    # not decided: fall back to GP_BELOW / 未指定：回落到 GP_BELOW
	GP_BELOW,   # under the envelope (the historic, default look) / 包络下方（历史默认外观）
	GP_ABOVE,   # over the envelope / 包络上方
	GP_INSIDE,  # within the envelope / 包络内部
	GP_LEFT,    # left of the envelope / 包络左侧
	GP_RIGHT,   # right of the envelope / 包络右侧
}

# How far the label centre may travel from the symbol centre, in half-envelopes.
# 标签中心距图元中心可移动的距离（以半包络为单位）。
const GP_RANGE: float = 1.5

# Tighter limit for the INSIDE anchor, so the text cannot spill out of the glyph.
# INSIDE 锚点更紧的限制，避免文字溢出字形之外。
const GP_INSIDE_RANGE: float = 0.9

# Sentinel for "this layer did not set an offset" — Vector2.ZERO is a LEGITIMATE offset
# ("exactly on the anchor"), so it cannot double as "unset".
# 「本层未设置偏移」的哨兵 —— Vector2.ZERO 是**合法**偏移（正好落在锚点上），
# 故不能兼任「未设置」。
const GP_OFFSET_UNSET: Vector2 = Vector2.INF


# Limit for one anchor. / 某一锚点的偏移上限。
static func gpLimitFor(gpAnchor: int) -> float:
	if gpAnchor == GPAnchor.GP_INSIDE:
		return GP_INSIDE_RANGE
	return GP_RANGE


# Clamp a normalised offset into the allowed range for gpAnchor.
# 把归一化偏移夹到 gpAnchor 允许范围内。
static func gpClamp(gpAnchor: int, gpOffset: Vector2) -> Vector2:
	var gpLim: float = gpLimitFor(gpAnchor)
	return Vector2(
		clampf(gpOffset.x, -gpLim, gpLim),
		clampf(gpOffset.y, -gpLim, gpLim))


# Anchor base position in symbol-local pixels (before the user's offset is applied).
# 锚点基准位置（图元本地像素坐标，尚未叠加用户偏移）。
# [param gpSize] envelope size in pixels. / 包络尺寸（像素）。
# [param gpGap]  gap between the envelope edge and the text. / 包络边缘到文字的间距。
static func gpBaseOffset(gpAnchor: int, gpSize: Vector2, gpGap: float) -> Vector2:
	match gpAnchor:
		GPAnchor.GP_ABOVE:
			return Vector2(0.0, -(gpSize.y * 0.5 + gpGap))
		GPAnchor.GP_INSIDE:
			return Vector2.ZERO
		GPAnchor.GP_LEFT:
			return Vector2(-(gpSize.x * 0.5 + gpGap), 0.0)
		GPAnchor.GP_RIGHT:
			return Vector2(gpSize.x * 0.5 + gpGap, 0.0)
		_:
			# GP_BELOW and GP_AUTO: the historic look — the label rides under the glyph.
			# GP_BELOW 与 GP_AUTO：历史外观 —— 标签位于字形下方。
			return Vector2(0.0, gpSize.y * 0.5 + gpGap)


# Final symbol-local offset: anchor base + clamped normalised offset scaled by the half envelope.
# 最终图元本地偏移：锚点基准 + 经夹取的归一化偏移 × 半包络。
# [param gpOffset] normalised offset (1.0 = half the envelope). / 归一化偏移（1.0 = 半个包络）。
static func gpOffsetWorld(gpAnchor: int, gpOffset: Vector2, gpSize: Vector2, gpGap: float) -> Vector2:
	var gpClamped: Vector2 = gpClamp(gpAnchor, gpOffset)
	var gpLocal: Vector2 = Vector2(gpClamped.x * gpSize.x * 0.5, gpClamped.y * gpSize.y * 0.5)
	return gpBaseOffset(gpAnchor, gpSize, gpGap) + gpLocal
