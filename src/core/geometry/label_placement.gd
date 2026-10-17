class_name GPLabelPlacement
extends RefCounted
# Copyright © 2026 Jonson Wang
# PURE geometry of label (位号) placement, extracted from GPLabelGripOps.
# 标签（位号）定位的**纯**几何，自 GPLabelGripOps 抽出。
#
# WHY THIS EXISTS / 为何存在：
# GPLabelGripOps lives in ui/tools, and core may never reference ui. The print model
# (GPPrintModel) must place tags at EXACTLY the spot the canvas draws them — a "where does
# the tag sit" judgment written twice would drift, which is the failure class this project
# has hit repeatedly. The functions moved here verbatim; GPLabelGripOps forwards to them, so
# its behaviour, its tests and its callers all stay untouched.
# GPLabelGripOps 位于 ui/tools，而 core 绝不引用 ui。打印模型（GPPrintModel）必须把位号
# 放在画布所画的**同一位置** —— 「位号在哪」这一判断写两遍必然分家，正是本项目反复撞上的
# 失效类别。以下函数逐字迁入；GPLabelGripOps 转发调用，故其行为、测试与调用方一概不动。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Gap between the envelope edge and the text, in millimetres. Mirrors GPSymbolView.GP_LABEL_GAP.
# 包络边缘到文字的间距（毫米）。与 GPSymbolView.GP_LABEL_GAP 一致。
# It is an UPPER BOUND, not a constant: see gpGapFor().
# 它是**上限**而非恒值：见 gpGapFor()。
const GP_GAP: float = 7.0

# Smallest gap the clamp may produce. / 钳制所能产生的最小间距。
const GP_MIN_GAP: float = 0.8


# The text to draw. The template comes from the TYPE layer ({tag} by default); an empty tag
# falls back to the localized type name so a legacy, un-numbered sheet is not blank.
# 要绘制的文字。模板取自**类型层**（默认 {tag}）；位号为空时回落本地化类型名，
# 使未经编号的历史图纸不会是空白。
static func gpLabelText(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpLocale: String = "zh") -> String:
	if gpNode == null:
		return ""
	var gpName: String = GPPropertyResolver.gpDisplayName(
		gpNode.gpNames,
		gpDef.gpDisplayName if gpDef != null else "",
		gpLocale,
		gpNode.gpTag)
	var gpFmt: String = GPPropertyResolver.GP_DEFAULT_LABEL_FORMAT
	if gpDef != null and gpDef.gpLabelFormat != "":
		gpFmt = gpDef.gpLabelFormat
	var gpText: String = GPPropertyResolver.gpLabelText(gpFmt, gpNode.gpTag, gpName)
	if gpText.strip_edges() == "":
		return gpName
	return gpText


# Effective anchor: the instance wins when it set one, otherwise the type layer's default.
# 生效锚点：实例设置过则用实例的，否则用类型层默认。
static func gpEffectiveAnchor(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> int:
	var gpLib: int = gpDef.gpLabelAnchor if gpDef != null else GPLabelAnchor.GPAnchor.GP_BELOW
	var gpInst: int = GPLabelAnchor.GPAnchor.GP_AUTO
	if gpNode != null:
		gpInst = gpNode.gpLabelAnchor
	return GPPropertyResolver.gpActiveAnchor(gpLib, gpInst)


# Effective normalised offset, resolved the same way as the anchor.
# 生效的归一化偏移，解析方式与锚点相同。
static func gpEffectiveOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> Vector2:
	var gpLib: Vector2 = gpDef.gpLabelOffset if gpDef != null else Vector2.ZERO
	var gpInst: Vector2 = GPLabelAnchor.GP_OFFSET_UNSET
	if gpNode != null:
		gpInst = gpNode.gpLabelOffset
	return GPPropertyResolver.gpActiveOffset(gpLib, gpInst)


# The gap actually used for a symbol of this envelope size.
# 给定包络尺寸下**实际**使用的间距。
#
# WHY NOT A CONSTANT / 为何不能是恒值：
# 7 mm is right for a 10 mm pump, but a nozzle is 4 x 2 mm — a fixed 7 mm gap put its number 8 mm
# off the centre, i.e. four nozzle lengths away, which is the reported "the text sits far too far
# away". Small symbols therefore take HALF their shorter side (a 4x2 nozzle -> 1 mm), floored so
# the text never lands on the glyph; every symbol at least 7 mm on its shorter side keeps the
# historic 7 mm exactly, so equipment annotations never move.
# 7mm 对 10mm 的泵合适，但管嘴只有 4x2mm —— 固定 7mm 会把编号推到离中心 8mm 处，即四个管嘴长，
# 这正是用户报告的「文字离得太远」。故小图元取**短边的一半**（4x2 管嘴 -> 1mm），并设下限使文字
# 绝不压到字形上；短边 ≥7mm 的图元精确保持历史的 7mm，故设备标注不会有任何位移。
static func gpGapFor(gpSize: Vector2) -> float:
	var gpSide: float = minf(gpSize.x, gpSize.y)
	if gpSide >= GP_GAP:
		return GP_GAP
	return clampf(gpSide * 0.5, GP_MIN_GAP, GP_GAP)


# The envelope used for scaling. A missing definition falls back to a sane default so the
# geometry never divides by zero.
# 用于缩放的包络。定义缺失时回落到合理默认值，使几何永不会除以零。
static func gpEnvelope(gpDef: GPSymbolDef) -> Vector2:
	if gpDef != null and gpDef.gpDefaultSize.x > 0.0 and gpDef.gpDefaultSize.y > 0.0:
		return gpDef.gpDefaultSize
	return Vector2(64.0, 48.0)


# Symbol-LOCAL offset (before flipping / rotating). This is the value the renderer needs:
# the node itself carries no rotation, so the rotation is applied by the caller.
# 图元**本地**偏移（翻转 / 旋转之前）。这是渲染器需要的值：
# 节点本身不承载旋转，旋转由调用方施加。
static func gpLocalOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> Vector2:
	var gpAnchor: int = gpEffectiveAnchor(gpNode, gpDef)
	var gpOff: Vector2 = gpEffectiveOffset(gpNode, gpDef)
	var gpSz: Vector2 = gpEnvelope(gpDef)
	return GPLabelAnchor.gpOffsetWorld(gpAnchor, gpOff, gpSz, gpGapFor(gpSz))
