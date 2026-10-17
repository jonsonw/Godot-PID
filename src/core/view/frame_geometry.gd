class_name GPFrameGeometry
extends RefCounted
# Copyright © 2026 Jonson Wang
# Frame / title-block geometry, derived from the sheet. PURE and headless-testable: no Node,
# Control, camera or autoload dependency — it turns a GPSheet into millimetre rectangles.
# 图框 / 标题栏几何，由图纸推导。**纯函数**、可 headless 测试：无 Node / Control / 相机 /
# autoload 依赖，只把 GPSheet 变成毫米制矩形。
#
# WHY A SEPARATE MODULE / 为何单独成模块：
# both the RENDERER (which strokes the frame line) and the HIT-TEST (which decides where a drag
# may start) have to answer "where is the frame?" — and two copies of one geometric decision drift
# apart, so the canvas would stroke one rectangle and accept grabs on another. This module is the
# single source of truth for that question.
# **渲染**（描图框线）与**命中**（判断拖拽从哪里开始）都得回答「图框在哪？」—— 而同一几何判断
# 写两遍必然分家，于是画布会描一个矩形、却在另一个矩形上接受抓取。本模块是该问题的单一事实源。
#
# This file is stage 0a of Rev.3: only the frame rectangle. The title-block anchor / snap / clamp
# queries (stage 1) land here too, so the renderer keeps asking one module.
# 本文件是 Rev.3 阶段 0a 的产物：只做图框矩形。图签的锚角 / 吸附 / 钳制查询（阶段 1）也落在
# 这里，使渲染器始终只问一个模块。
#
# ⚠️ STAGE 0d ADDED ONE INPUT, NOT ONE RECTANGLE / ⚠️ 阶段 0d 加的是一个**输入**、不是一个矩形：
# the paper is no longer pinned to the world origin (GPSheet.gpPaperOrigin), and this module reads it
# in exactly TWO places — gpPaperRect() uses it as the paper's corner, and gpFrameRect() adds it to the
# paper-local inner rectangle. Everything else here (trim line, title block, zone ticks/arrows/labels,
# side midpoints, both hit-tests) is derived from one of those two, so ALL of it follows a moved sheet
# without a line of its own — the reason this module could absorb "the whole drawing moves" at all.
# 纸面不再钉在世界原点上（GPSheet.gpPaperOrigin），而本模块只在**两处**读它 —— gpPaperRect() 把它当作
# 纸的角，gpFrameRect() 把它加到纸面本地的内框上。此处其余一切（裁边线、图签、坐标带刻度/箭头/标号、
# 侧中点、两处命中判定）都由这两者之一推导，故**全都**跟着被移动的图纸走、各自一行未改 —— 这正是本模块
# 能够吸收「整张图纸移动」这件事的原因。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。


# Effective margins of a sheet, as [left, top, right, bottom] in mm.
# 图纸的生效边距，形如 [左, 上, 右, 下]（mm）。
#
# WHY A GUARDED READ / 为何带护栏读取：gpFrameMargins is a public field, so a malformed array
# (hand-edited archive, a future migration) must degrade to the standard default rather than hand
# every consumer a bogus rectangle. The write side clamps; this is the read side's floor.
# gpFrameMargins 是公开字段，格式不对的数组（手工改过的存档、将来的迁移）必须回落到标准默认值，
# 而不是把错误矩形交给每个消费方。写入侧负责钳制，这里是读取侧的兜底。
static func gpMargins(gpSheet: GPSheet) -> Array:
	if gpSheet == null:
		return GPSheet.GP_FRAME_MARGINS_DEFAULT.duplicate()
	var gpM: Array = gpSheet.gpFrameMargins
	if gpM.size() != GPSheet.GP_FRAME_MARGINS_DEFAULT.size():
		return GPSheet.GP_FRAME_MARGINS_DEFAULT.duplicate()
	return gpM.duplicate()


# The paper rectangle in mm, with its origin at the SHEET'S OWN top-left corner — i.e. at
# `GPSheet.gpPaperOrigin` (Rev.3 stage 0d), which is NOT necessarily the world origin.
# 纸面矩形（mm），原点在**图纸自身**的左上角 —— 即 `GPSheet.gpPaperOrigin`（Rev.3 阶段 0d），
# 它**不一定**是世界原点。
#
# ⚠️ THE TWO ZEROES ARE NOT THE SAME ZERO (Rev.3 stage 0d). Until this stage the body below was
# `Rect2(0.0, 0.0, W, H)` — a CONSTANT — because the paper WAS the world origin, and everything
# hanging off it (trim line, frame, title block, zone ruler) inherited that constant. Making the sheet
# movable is therefore, first and last, a matter of making THIS rectangle movable: every other
# rectangle in this module is derived from it or from the frame, so not one of them needed a change of
# its own. That is also why a moved sheet needs no new geometry anywhere else.
# ⚠️ 这两个「零」不是同一个零（Rev.3 阶段 0d）。在此之前，下面的函数体是 `Rect2(0.0, 0.0, W, H)` ——
# 一个**常量** —— 因为纸面**就是**世界原点，挂在其上的一切（裁边线、图框、图签、坐标带）都继承那个常量。
# 故「让图纸可移动」归根到底只是让**本**矩形可动：本模块其余每个矩形都由它或由图框推导，因此没有一个需要
# 单独改动。这也是被移动过的图纸在别处无需任何新几何的原因。
#
# ⚠️ NO CLAMP, ON PURPOSE / 刻意不钳制：the origin is wherever the sheet was dragged to, in world
# millimetres, and on an unbounded canvas every value is a legal position — unlike the margins, which
# carry the frame's own consistency (GPSheet.GP_FRAME_MIN_SIZE_MM).
# 原点就是图纸被拖到的地方（世界毫米），在无界画布上每个取值都是合法位置 —— 与承载图框自洽性的边距不同。
static func gpPaperRect(gpSheet: GPSheet) -> Rect2:
	if gpSheet == null:
		return Rect2()
	return Rect2(gpSheet.gpPaperOrigin, Vector2(gpSheet.gpWidthMM, gpSheet.gpHeightMM))


# ---------------------------------------------------------------------------
# Trim line (裁边线) / 裁边线
# ---------------------------------------------------------------------------
# How far the drawn sheet-edge line sits INSIDE the paper, in mm.
# 画出的纸边线位于纸面**内侧**多远（mm）。
#
# ⚠️ MEASURED, NOT CHOSEN: the reference (DEXPI Example C01) draws its outer `border` polyline at
# `1.0,-1.0 .. 419.0,-296.0` on a 420x297 paper — i.e. exactly 1 mm inside every edge. This project
# drew that line ON the paper edge until Rev.3 stage 0c, which is why the alignment was queued as a
# separate, user-owned decision (it moves the trim line of every existing drawing).
# ⚠️ 这是**实测**而非选择：参照图（DEXPI 示例 C01）在 420×297 的纸上把外层 `border` 折线画在
# `1.0,-1.0 .. 419.0,-296.0` —— 即每边恰好内缩 1mm。本项目在 Rev.3 阶段 0c 之前把该线画在
# **纸边**上，这正是「对齐裁边线」被单列为一项、且需用户拍板的原因（它会移动每一张既有图纸的裁边线）。
#
# WHY IT IS A CONSTANT AND NOT SHEET DATA / 为何是常量而非图纸数据：ISO 5457 does not make this
# offset configurable — it is the difference between the printed sheet and the trimmed one, and every
# drawing office uses the same small value. Making it data would add a persisted key nobody sets.
# ISO 5457 不把该内缩量做成可配置项 —— 它是「印刷幅面与裁切幅面之差」，各设计院取值相同。做成数据
# 只会多出一个没人会去设的持久化键。
#
# ⚠️ THE FRAME IS NO LONGER BOUND BY THIS LINE / 图框不再被这条线约束：until Rev.3's 2026-10-16
# amendment the frame's minimum margin equalled this inset, so a frame line could never land on the
# trim line, let alone cross it. That ordering was retired together with the paper bound: the frame
# now moves freely and MAY cross the trim line (and leave the paper altogether). Do NOT re-derive a
# constraint from this constant — it says where the SHEET EDGE is drawn, nothing about the frame.
# ⚠️ 在 Rev.3 的 2026-10-16 修正之前，图框的最小边距等于本内缩量，故图框线永不会压在裁边线上、更不会与之
# 交叉。该偏序已随纸面约束一并退役：图框现在自由移动，**可以**与裁边线交叉（也可以整块离开纸面）。不要从
# 本常量反推任何约束 —— 它只说明**纸边线画在哪里**，与图框无关。
const GP_TRIM_INSET_MM: float = 1.0


# The trim line rectangle (裁边线) in mm — the sheet edge as DRAWN.
# 裁边线矩形（mm）—— **画出来的**纸边。
#
# The inset is capped at half the shorter side so an absurd paper size degrades to a degenerate
# rectangle rather than to a mirrored (negative-size) one — the same "never hand a consumer an
# impossible rectangle" rule gpInnerRect follows.
# 内缩量以短边的一半为上限，使荒唐的纸幅退化为**退化矩形**而非**镜像矩形**（负尺寸）——
# 与 gpInnerRect 遵循的「绝不把不可能的矩形交给消费方」同一条规则。
#
# ⚠️ MEASURED FROM THE PAPER'S OWN CORNER (Rev.3 stage 0d) / ⚠️ 自**纸自身**的角量起（Rev.3 阶段 0d）：
# the inset is added to gpPaperOrigin rather than to the world origin, so a sheet that has been moved
# keeps exactly the same 1 mm trim line all round — it does not grow a new one at the world origin.
# 内缩量加在 gpPaperOrigin 上、而不是世界原点上，故被移动过的图纸四周仍恰是那条 1mm 的裁边线 ——
# 而不会在世界原点处另长出一条。
static func gpTrimRect(gpSheet: GPSheet) -> Rect2:
	if gpSheet == null:
		return Rect2()
	var gpW: float = gpSheet.gpWidthMM
	var gpH: float = gpSheet.gpHeightMM
	# The inset rides the frame visual scale (A1 rebase, 2026-10-16): 1 mm on an A3-era sheet,
	# 2 mm on an A1 one — the same proportion of the paper either way.
	# 内缩量随图幅视觉比例（A1 重定基，2026-10-16）：A3 时代图纸 1mm、A1 图纸 2mm —— 占纸面的
	# 比例两侧一致。
	var gpI: float = minf(GP_TRIM_INSET_MM * gpSheet.gpFrameScale(), minf(gpW, gpH) * 0.5)
	return Rect2(gpSheet.gpPaperOrigin + Vector2(gpI, gpI), Vector2(gpW - 2.0 * gpI, gpH - 2.0 * gpI))


# The inner drawing frame (图框) in mm — the area actually available for the drawing. This is the
# ONE rectangle the renderer strokes and the hit-test reasons about.
# 内图框（mm）—— 真正可用于绘图的范围。渲染器描边与命中判定用的是**同一个**矩形。
#
# ⚠️ THIS IS WHERE THE PAPER'S POSITION ENTERS (Rev.3 stage 0d) / ⚠️ 纸面的位置在**这里**进入（阶段 0d）：
# gpInnerRect() answers in PAPER-LOCAL millimetres (margins are distances from the paper's own edges),
# and this function is the single place that PLACES that rectangle on the paper by adding
# gpPaperOrigin. Everything derived from the frame — the title block, the zone ruler, the side-handle
# midpoints and both hit-tests — therefore follows a moved sheet with no change of its own.
# gpInnerRect() 以**纸面本地**毫米作答（边距是到纸自身各边的距离），而本函数是**唯一**把该矩形放到纸上的
# 地方（加上 gpPaperOrigin）。故图签、坐标带、侧中点、两处命中判定 —— 凡由图框推导者 —— 全都跟着被移动
# 的图纸走，各自无需改动。
#
# On a sheet that has never been moved the offset is zero, so this stays bit-identical to what every
# pre-existing drawing expects.
# 在从未移动过的图纸上该偏移为零，故这与每一张既有图纸所预期的结果逐位一致。
static func gpFrameRect(gpSheet: GPSheet) -> Rect2:
	if gpSheet == null:
		return Rect2()
	var gpLocal: Rect2 = gpInnerRect(gpSheet.gpWidthMM, gpSheet.gpHeightMM, gpMargins(gpSheet))
	return Rect2(gpLocal.position + gpSheet.gpPaperOrigin, gpLocal.size)


# Decode a SHEET_ANCHOR corner code (BR/BL/TR/TL) into the corresponding corner of the given
# frame rectangle. Stage 2's gpPlacePolicy consumes this: a definition that declares
# "SHEET_ANCHOR:<code>" lands there wherever the user clicked — the title block's
# "travels with the frame" semantics expressed as a definition policy, not a special case.
# 把 SHEET_ANCHOR 角码（BR/BL/TR/TL）解码为给定图框矩形的对应角点。阶段 2 的 gpPlacePolicy
# 消费它：声明 "SHEET_ANCHOR:<code>" 的定义无论用户点在哪都落到那里 —— 图签「跟着图框走」
# 的语义表达为定义策略，而非特例。
#
# Godot's Y axis grows downward, so "T" is the frame's small-y edge and "B" its large-y edge;
# "L"/"R" map to small-x / large-x respectively. An unrecognised code degrades to gpFallback
# so a typo in the policy string can never fling the symbol off-screen.
# Godot 的 Y 轴向下生长，故 "T" 是图框的小 y 边、"B" 是大 y 边；"L"/"R" 分别对应小 x / 大 x。
# 无法识别的编码退化为 gpFallback，保证策略串笔误也绝不会把图元甩出画面。
static func gpFrameCorner(gpFrame: Rect2, gpCode: String, gpFallback: Vector2) -> Vector2:
	match gpCode:
		"BR":
			return Vector2(gpFrame.end.x, gpFrame.end.y)
		"BL":
			return Vector2(gpFrame.position.x, gpFrame.end.y)
		"TR":
			return Vector2(gpFrame.end.x, gpFrame.position.y)
		"TL":
			return Vector2(gpFrame.position.x, gpFrame.position.y)
	return gpFallback


# The same rectangle from raw inputs, so callers that are mid-edit (a dialog holding not-yet-
# committed numbers) can ask without building a sheet.
# 由原始输入构造同一矩形，使正在编辑中的调用方（如持有未提交数值的对话框）无需构造图纸即可询问。
#
# ⚠️ THE RESULT IS PAPER-LOCAL — IT CARRIES NO PAPER POSITION (Rev.3 stage 0d) / ⚠️ 结果是**纸面本地**的
# —— 它不携带纸面的位置（Rev.3 阶段 0d）：its left edge is the left margin, i.e. a distance from the
# paper's own edge, so a sheet parked at (300, 200) still answers "the frame's left line is 25 mm from
# the paper". gpFrameRect() is the function that adds gpPaperOrigin and turns that into a world
# rectangle. Callers that want a WORLD rectangle must go through gpFrameRect(); this one is the
# margin arithmetic, unchanged since stage 0a, and is what the samples below (and the tests) pin.
# 其左边就是左边距，即到纸**自身**边的距离，故停在 (300, 200) 的图纸依然回答「图框左边距纸 25mm」。
# gpFrameRect() 才是加上 gpPaperOrigin、把它变成世界矩形的那一个。要世界矩形就必须走 gpFrameRect()；
# 本函数是边距算术，自阶段 0a 起未变，也是下方样例（与测试）所钉之物。
#
# ⚠️ THE RESULT MAY LIE OUTSIDE THE PAPER — DELIBERATELY (Rev.3 amendment, 2026-10-16). Until that
# amendment this function was where the paper bound was enforced on the READ side: the margins were
# folded through GPSheet.gpClampMargins and therefore only ever produced a subset of the paper. The
# frame now moves freely, so the only thing the fold still enforces is the one surviving invariant —
# the inner rectangle must not be turned inside out. A negative margin reaches this function as "that
# frame line is off the sheet", and the returned rectangle says exactly that.
# ⚠️ 结果**可以**落在纸面之外 —— 这是刻意的（Rev.3 修正，2026-10-16）。在该修正之前，本函数正是纸面约束
# 在**读取侧**的落点：边距经 GPSheet.gpClampMargins 折过一遍，故永远只产出纸面的子集。图框现在自由移动，
# 故这次折算仍强制的只剩唯一那条不变量 —— 内框不得内翻。负边距以「该条图框线在纸外」的身份抵达本函数，
# 返回的矩形如实如此。
# WHY KEEP THE FOLD AT ALL / 为何仍保留这次折算：a hand-edited archive or a future migration can carry
# an inside-out pair, and handing a consumer a negative-size rectangle makes the frame silently
# disappear (the renderer's zone grid and both hit-tests bail on `size <= 0`) — the user would then
# have to undo to get their frame back. The fold is idempotent, so re-folding already-legal margins
# costs one pass and changes nothing.
# 手工改过的存档或将来的迁移可能带有一对**内翻**的边距，而把负尺寸矩形交给消费方会让图框静默消失
# （渲染器的坐标带与两处命中判定遇 `size <= 0` 都会退回），用户于是只能靠撤销把图框要回来。折算幂等，故对
# 已经合法的边距再折一次只多花一帧、不改动任何值。
# [param gpW] / [param gpH] paper size in mm / 纸面尺寸（mm）
# [param gpM] margins as [left, top, right, bottom] in mm / 边距 [左, 上, 右, 下]（mm）
static func gpInnerRect(gpW: float, gpH: float, gpM: Array) -> Rect2:
	var gpC: Array = GPSheet.gpClampMargins(gpM, gpW, gpH)
	var gpL: float = float(gpC[GPSheet.GP_MARGIN_LEFT])
	var gpT: float = float(gpC[GPSheet.GP_MARGIN_TOP])
	var gpR: float = float(gpC[GPSheet.GP_MARGIN_RIGHT])
	var gpB: float = float(gpC[GPSheet.GP_MARGIN_BOTTOM])
	return Rect2(gpL, gpT, gpW - gpL - gpR, gpH - gpT - gpB)


# The title-block rectangle (图签) in mm, hugging the inner frame's bottom-right corner — where
# every drawing office puts it, and where this project has put it since v0.1.
# 标题栏（图签）矩形（mm），贴住内框右下角 —— 这是所有设计院的惯例，也是本项目自 v0.1 起的做法。
#
# ⚠️ THIS WAS THE DEFAULT OF A FAMILY, AND THE FAMILY HAS NOW LANDED (Rev.3 stage 1) / ⚠️ 它曾是一族情形的
# **默认**，而这一族现已落地（Rev.3 阶段 1）：this function is now the sheet-level query over the whole
# family — anchor corner + offset — and reduces to the historical rectangle whenever the anchor is
# bottom-right and the offset is zero, which is the default both fields carry. That reduction is pinned
# by test, because it is what keeps stage 1 from silently shifting every existing drawing.
# 本函数现已是这一族（锚角 + 偏移）在图纸层的查询，且在锚角为右下、偏移为零时退化为历史矩形 —— 而那正是两个
# 字段所带的默认值。该退化由测试钉住，因为它正是阶段 1 不悄悄挪动每一张既有图纸的原因。
static func gpTitleBlockRect(gpSheet: GPSheet) -> Rect2:
	if gpSheet == null:
		return Rect2()
	return gpTitleBlockPlaced(gpFrameRect(gpSheet), gpSheet)

# The block rectangle inside a given inner frame — the form the renderer wants, since it already
# holds the frame rectangle and must not re-derive it (one fact, one home).
# 给定内框下的图块矩形 —— 渲染器需要的形式，因为它已持有内框矩形，且不得重算（一个事实一个家）。
#
# ⚠️ THE DEFAULT CASE OF THE FAMILY (Rev.3 stage 1) / ⚠️ 本族的**默认**情形（Rev.3 阶段 1）：it is the
# bottom-right corner with no offset, spelled out. Every pre-stage-1 call site (and every test that pins
# the historical geometry) keeps meaning exactly what it meant before, because that pair IS the default
# of GPSheet.gpTbAnchor / gpTbOffset; callers that carry live docking values use gpTitleBlockPlaced().
# 它就是「右下角、无偏移」的展开写法。每一个阶段 1 之前的调用点（以及每一个钉住历史几何的测试）含义完全
# 不变，因为那一对正是 GPSheet.gpTbAnchor / gpTbOffset 的默认值；携带实时停靠值的调用方用
# gpTitleBlockPlaced()。
static func gpTitleBlockIn(gpFrame: Rect2) -> Rect2:
	return gpTitleBlockAt(gpFrame, GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, Vector2.ZERO)


# ---------------------------------------------------------------------------
# Title-block docking (图签停靠) — Rev.3 stage 1 / Rev.3 阶段 1
# ---------------------------------------------------------------------------
# WHY THE BLOCK'S POSITION IS DERIVED AND NEVER STORED / 为何图签位置是推导的、永不存储：
# see GPSheet.gpTbAnchor — in one line, a stored point would let the block "fall off" the frame the
# moment the frame moved. Everything below is the arithmetic of that derivation, and every piece is a
# pure static function so the whole docking model is testable with no canvas at all.
# 见 GPSheet.gpTbAnchor —— 一句话：存下来的点会让图签在图框一移动时就「从框上掉下去」。下方全是该推导的
# 算术，且每一块都是纯静态函数，使整个停靠模型无需画布即可测试。
#
# ⚠️ NO `GPSnapResolver` HERE, ON PURPOSE (Rev.3 铁律 38) / ⚠️ 此处刻意**不**用 `GPSnapResolver`（铁律 38）：
# that resolver captures geometric FEATURES (ports, endpoints, midpoints, intersections, grid) — "snap to
# a symbol's geometry". Docking is object-to-object EDGE ALIGNMENT, a different meaning; sharing the
# resolver would let the pipe tool snap onto the title block's edges. Only its THRESHOLD convention is
# reused (screen pixels divided by zoom — see GP_SNAP_PX).
# 该解析器捕捉的是几何**特征**（端口、端点、中点、交点、网格）—— 即「吸附到图元几何」。停靠是对象↔对象的
# **内边对齐**，语义不同；共用会让管线工具吸到图签边上。只复用它**阈值**的口径（屏幕像素除以缩放 —— 见
# GP_SNAP_PX）。

# Bit 0 of the anchor code selects LEFT (set) vs RIGHT (clear). / 锚角编码的位 0：置位为左、清零为右。
static func _gpHugLeft(gpAnchor: int) -> bool:
	return (gpAnchor & 1) != 0


# Bit 1 of the anchor code selects TOP (set) vs BOTTOM (clear). / 锚角编码的位 1：置位为上、清零为下。
static func _gpHugTop(gpAnchor: int) -> bool:
	return (gpAnchor & 2) != 0


# The block rectangle for an explicit docking pair. THE ONE FORMULA — the renderer, the drag preview
# and every test go through it, so "where the block is drawn" and "where the pointer grabbed it" cannot
# disagree (the failure stage 0c avoided for the frame; same rule, GPFrameGeometry is one fact's home).
# 显式停靠对下的图块矩形。**唯一的公式** —— 渲染器、拖拽预览与每个测试都经它，使「图签画在哪」与「指针在哪
# 抓住它」不可能分家（阶段 0c 为图框避开的是同一个失效；同一条规则，GPFrameGeometry 是一个事实的家）。
#
# ⚠️ NOT CLAMPED. This is pure placement: hand it an offset that pushes the block off the frame and it
# will report exactly that. Clamping is a separate, named decision (gpClampTitleBlock) because the two
# have different callers — the inverse arithmetic (the drag) must be able to see the unclamped truth.
# ⚠️ **不**钳制。这是纯粹的位置计算：给它一个把图签推出框外的偏移，它就如实报告。钳制是一个另立且有名字的
# 判断（gpClampTitleBlock），因为两者调用方不同 —— 反推算术（拖拽）必须能看到未钳制的事实。
#
# [param gpFrame] the inner frame rectangle in world mm / 内框矩形（世界毫米）
# [param gpAnchor] the corner to hug, a GPSheet.GP_TB_ANCHOR_* code / 所贴之角，GPSheet.GP_TB_ANCHOR_* 编码
# [param gpOffset] distance from the anchor corner INTO the frame, in mm / 自锚角**向框内**的距离（mm）
# [param gpBlock] the block's size in mm; defaults to the A3-era constants so every historical
# caller and pinned test keeps its exact meaning. Sheet-aware callers pass
# GPSheet.gpTbBlockSize() (A1 rebase, 2026-10-16).
# 图块尺寸（mm）；默认取 A3 时代常量，使每个历史调用点与被钉住的测试含义不变。持有图纸的调用方
# 传 GPSheet.gpTbBlockSize()（A1 重定基，2026-10-16）。
static func gpTitleBlockAt(gpFrame: Rect2, gpAnchor: int, gpOffset: Vector2,
		gpBlock: Vector2 = Vector2(GPSheet.GP_TB_BLOCK_W, GPSheet.GP_TB_BLOCK_H)) -> Rect2:
	var gpW: float = gpBlock.x
	var gpH: float = gpBlock.y
	var gpX: float = 0.0
	if _gpHugLeft(gpAnchor):
		gpX = gpFrame.position.x + gpOffset.x
	else:
		gpX = gpFrame.end.x - gpOffset.x - gpW
	var gpY: float = 0.0
	if _gpHugTop(gpAnchor):
		gpY = gpFrame.position.y + gpOffset.y
	else:
		gpY = gpFrame.end.y - gpOffset.y - gpH
	return Rect2(gpX, gpY, gpW, gpH)


# The INVERSE of gpTitleBlockAt: which offset puts a rectangle at that place, for that anchor.
# gpTitleBlockAt 的**逆**：给定锚角，哪个偏移能把矩形放到那个位置。
#
# WHY THE INVERSE IS NEEDED AT ALL / 为何需要逆运算：a drag moves a RECTANGLE (the pointer dictates where
# the block's corner goes), while the model stores an OFFSET. Something has to convert one into the
# other, and doing it here — next to the forward formula — is what keeps the two from drifting into
# mutual inconsistency. / 拖拽移动的是一个**矩形**（指针决定图签的角去哪），而模型存的是**偏移**。总得有
# 东西把其一转成其二，而把它放在正推公式**旁边**，正是二者不分家、不互相矛盾的保证。
#
# ⚠️ ROUND-TRIP GUARANTEE / ⚠️ 往返保证：for any anchor, offset == gpTitleBlockOffset(frame, anchor,
# gpTitleBlockAt(frame, anchor, offset)). Pinned by test, because a silent sign error here would show up
# as "the block jumps when I start dragging".
# 对任意锚角：offset == gpTitleBlockOffset(frame, anchor, gpTitleBlockAt(frame, anchor, offset))。由测试
# 钉住，因为这里一个静默的符号错误表现出来就是「我一开拖图签就跳」。
static func gpTitleBlockOffset(gpFrame: Rect2, gpAnchor: int, gpRect: Rect2) -> Vector2:
	var gpX: float = 0.0
	if _gpHugLeft(gpAnchor):
		gpX = gpRect.position.x - gpFrame.position.x
	else:
		gpX = gpFrame.end.x - gpRect.end.x
	var gpY: float = 0.0
	if _gpHugTop(gpAnchor):
		gpY = gpRect.position.y - gpFrame.position.y
	else:
		gpY = gpFrame.end.y - gpRect.end.y
	return Vector2(gpX, gpY)


# Fold a docking offset into its legal set: each component in [0, frame span - block size].
# 把停靠偏移收进合法域：每个分量 ∈ [0, 内框跨度 − 图块尺寸]。
#
# WHY THE LOWER BOUND IS ZERO / 为何下限是零：the offset is measured from the anchor edge INTO the frame,
# so a negative component would put the block OUTSIDE the edge it is supposed to hug. That is not a
# position the docking model can express; a drag that reaches it is asking for "flush", which is zero.
# 偏移自锚边**向框内**量起，故负分量会把图签放到它本该贴住的那条边的**外面** —— 那不是停靠模型能表达的位置；
# 拖到那里就是在要求「贴边」，也就是零。
#
# WHY THE UPPER BOUND COLLAPSES INSTEAD OF THE BLOCK VANISHING / 为何上限塌缩、而不是让图签消失：
# when the frame is NARROWER than the block (which stage 0c made possible — a frame may be resized to
# almost nothing), the upper bound goes negative and maxf() pins it to zero. The block then hugs its
# anchor edge and OVERFLOWS the far side. That is the behaviour Rev.3 §9-① demands: 「真放不下就向左/上
# 溢出，而不是不画」 — the alternative (drawing nothing) is exactly what makes a dragged block
# "disappear", and the user's way out of it is a second of confusion plus a Ctrl+Z.
# 当内框比图块**窄**时（阶段 0c 使之成为可能 —— 图框可被缩到几乎为零），上限变为负数，maxf() 把它钉在零。
# 图签于是贴住锚边、向**另一侧溢出**。这正是 Rev.3 §9-① 所要求的行为：「真放不下就向左/上溢出，而不是不画」
# —— 另一种做法（什么都不画）恰恰就是「被拖的图签凭空消失」的成因，而用户从中脱身的代价是一秒钟的困惑加一次
# Ctrl+Z。
#
# Idempotent, so callers may clamp defensively. / 幂等，故调用方可以放心地上再钳一次。
#
# [param gpBlock] block size in mm; the A3-era constants by default (see gpTitleBlockAt).
# 图块尺寸（mm）；默认 A3 时代常量（见 gpTitleBlockAt）。
static func gpClampTitleBlock(gpFrame: Rect2, gpAnchor: int, gpOffset: Vector2,
		gpBlock: Vector2 = Vector2(GPSheet.GP_TB_BLOCK_W, GPSheet.GP_TB_BLOCK_H)) -> Vector2:
	var gpMaxX: float = maxf(0.0, gpFrame.size.x - gpBlock.x)
	var gpMaxY: float = maxf(0.0, gpFrame.size.y - gpBlock.y)
	return Vector2(clampf(gpOffset.x, 0.0, gpMaxX), clampf(gpOffset.y, 0.0, gpMaxY))


# Snap each offset component to zero when it is within tolerance — i.e. "the block has arrived at the
# inner edge". This is what the user feels as 吸附.
# 当某个偏移分量落在容差内时吸附到零 —— 即「图签到达了内边」。这就是用户所感到的**吸附**。
#
# ⚠️ THE TOLERANCE MUST BE IN WORLD mm, DERIVED FROM PIXELS DIVIDED BY ZOOM (Rev.3 §9-②) / ⚠️ 容差必须是
# **世界毫米**，由「像素除以缩放」得出（Rev.3 §9-②）：a fixed millimetre threshold feels dead when zoomed
# out (the block would have to be dragged onto the line) and impossibly sticky when zoomed in. Callers
# pass GPConstants.GP_SNAP_PX / zoom — the same convention GPSnapResolver already uses.
# 固定毫米阈值在缩小时毫无手感（非得拖到线上才吸）、放大时又黏得走不动。调用方传
# GPConstants.GP_SNAP_PX / zoom —— 与 GPSnapResolver 已在用的口径相同。
#
# A non-positive tolerance snaps only an already-zero component, so a caller can pass zero to disable
# the snap without a second code path. / 非正容差只会吸附本来就是零的分量，故调用方传零即可关闭吸附，
# 无需第二条代码路径。
static func gpSnapTitleBlock(gpOffset: Vector2, gpTol: float) -> Vector2:
	var gpX: float = gpOffset.x
	var gpY: float = gpOffset.y
	if absf(gpX) <= gpTol:
		gpX = 0.0
	if absf(gpY) <= gpTol:
		gpY = 0.0
	return Vector2(gpX, gpY)


# Which corner the block "wants" to hug, given where the drag has put it. Crossing the frame's centre
# line on an axis flips that axis's bit — so dragging the block past the middle of the frame hands it to
# the other side, which is how a docked block reaches all four corners with one gesture.
# 给定拖拽把图签放到了哪里，它「想」贴哪个角。在某个轴上越过内框**中线**即翻转该轴的位 —— 故把图签拖过
# 内框中间，它就被交给另一侧；这正是「一次拖拽够到四个角」的方式。
#
# ⚠️ WHY THE CENTRE LINE AND NOT THE NEAREST EDGE / 为何用中线、而不是最近边：the nearest edge flips the
# anchor while the block is still visibly hugging the OLD edge (the two are within a pixel of each other
# near a corner), and the anchor is not a user-visible thing — a flip the user cannot see looks like a
# bug when its effect appears later. The centre line is a stable, explainable rule: 「过中线即换角」.
# 「最近边」会在图签看上去仍贴着**旧**边时就翻转锚角（在角附近两者相距不到一个像素），而锚角并非用户可见之
# 物 —— 一次用户看不见的翻转，在其后果稍后显现时就像个 bug。中线是一条稳定、可解释的规则：「过中线即换角」。
#
# ⚠️ A TIE GOES TO THE DEFAULT / ⚠️ 恰好居中时归默认：the comparisons are strict (`<`), so a block exactly
# centred keeps—or falls back to—the bottom-right code. Any tie rule has to be picked; this one is
# picked because it is the code every other default in this file already uses.
# 比较是严格的（`<`），故恰好居中的图签保持（或回落到）右下编码。平局总得有一条规则；选它是因为它正是本文件
# 其他每一处默认值所用的编码。
static func gpReanchor(gpFrame: Rect2, gpRect: Rect2) -> int:
	var gpAnchor: int = GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT
	if gpRect.get_center().x < gpFrame.get_center().x:
		gpAnchor |= GPSheet.GP_TB_ANCHOR_BOTTOM_LEFT
	if gpRect.get_center().y < gpFrame.get_center().y:
		gpAnchor |= GPSheet.GP_TB_ANCHOR_TOP_RIGHT
	return gpAnchor


# The block's world rectangle from a live sheet: anchor + offset, clamped, placed.
# 由实时图纸得出图块的世界矩形：锚角 + 偏移，钳制后落位。
#
# WHY IT TAKES THE FRAME AND THE SHEET SEPARATELY / 为何分开收内框与图纸：the renderer already holds the
# inner frame rectangle and must not re-derive it (one fact, one home — the same reason gpTitleBlockIn()
# exists). gpTitleBlockRect(sheet) is the convenience wrapper for callers that have only a sheet.
# 渲染器已持有内框矩形、不得重算（一个事实一个家 —— 与 gpTitleBlockIn() 存在的原因相同）。
# gpTitleBlockRect(sheet) 是给只持有图纸的调用方的便捷封装。
static func gpTitleBlockPlaced(gpFrame: Rect2, gpSheet: GPSheet) -> Rect2:
	if gpSheet == null:
		return gpTitleBlockIn(gpFrame)
	# Sheet-aware size: the block scales with the paper (A1 rebase, 2026-10-16). The default
	# branch above keeps the A3-era constants for sheet-less callers.
	# 随图纸的尺寸：图块随纸幅缩放（A1 重定基，2026-10-16）。上方的无纸分支仍用 A3 时代常量。
	var gpBlock: Vector2 = gpSheet.gpTbBlockSize()
	var gpOffset: Vector2 = gpClampTitleBlock(gpFrame, gpSheet.gpTbAnchor, gpSheet.gpTbOffset, gpBlock)
	return gpTitleBlockAt(gpFrame, gpSheet.gpTbAnchor, gpOffset, gpBlock)


# ---------------------------------------------------------------------------
# Zone grid (分区格网) — Rev.3 stage 0b / Rev.3 阶段 0b
# ---------------------------------------------------------------------------
# WHY THE RULER LIVES HERE TOO / 为何坐标带也归此处：the band around a drawing frame is not
# decoration — it is how two engineers say "the valve at 7-C" to each other. Its divisions must agree
# with the frame line they hang off, so they are derived from the SAME rectangle the frame is.
# 图框四周的坐标带不是装饰 —— 它是两位工程师互相指认「7-C 那个阀」的方式。它的分格必须与所依附的
# 图框线一致，故它与图框由**同一个**矩形推导。

# Nominal field size in mm. ISO 5457 permits a field anywhere in 25..75 mm and does NOT fix how many
# there are, so the count is a choice; the reference (DEXPI Example C01) lands on ~35 mm fields.
# 标称分格边长（mm）。ISO 5457 允许 25–75mm 而**不**固定分格数，故分格数是一个选择；参照图
# （DEXPI 示例 C01）落在约 35mm。
const GP_ZONE_FIELD_MM: float = 35.0

# Depth of a division tick in mm, measured OUTWARD from the frame line.
# 分格刻度线的深度（mm），自图框线**向外**量。
# The reference's ticks span its whole band — but that is not a rule it can teach: its band is
# 4 mm margin − 1 mm trim inset = 3 mm. A FIXED depth is used instead, because "span the band" would
# grow a 24 mm tick on a 25 mm binding edge. Both rules agree exactly on the reference.
# 参照图的刻度贯穿其整条带，但那不是它能传授的规则：它的带 = 4mm 边距 − 1mm 裁边内缩 = 3mm。此处
# 改用**固定深度**，因为「贯穿整条带」会在 25mm 装订边上长出 24mm 的刻度。两条规则在参照图上完全一致。
const GP_ZONE_TICK_MM: float = 3.0

# Fewest fields an axis may have — and the reason the count is EVEN: an even count puts a division
# line exactly on the paper's centre line, which is where the centring arrows point and which is why
# the reference's 12 x 8 grid has its arrows landing on a division.
# 单轴最少分格数 —— 也是分格数**取偶数**的理由：偶数使分界线恰好落在纸面中线上，而中线正是指对中
# 箭头所指之处；参照图的 12×8 格网之所以让箭头落在分界线上，正是因为这个。
const GP_ZONE_MIN_COUNT: int = 2

# Half-width of a centring arrow's arms in mm — measured ±1.5 mm on the reference.
# 对中箭头两臂的半宽（mm）—— 参照图实测 ±1.5mm。
const GP_ZONE_ARROW_HALF_MM: float = 1.5

# Baseline offset below the band / row centre, as a fraction of the text height.
# 基线相对带 / 行中心的偏移，以字高的比例表示。
# Measured on the reference's four sides at 0.30..0.36 of 2.85 mm. One ratio covers all four, and it
# reproduces the row letters EXACTLY (23.003 / 275.878 mm) with the column numbers within 0.08 mm.
# 参照图四边实测为 2.85mm 的 0.30–0.36。单一比例可统一四边，且**精确**复现行字母（23.003 /
# 275.878mm），列数字误差在 0.08mm 内。
const GP_ZONE_BASELINE_RATIO: float = 0.33

# Row letters are A..Z; no sheet needs more (the reference has 8 rows). The clamp is explicit so an
# absurd frame cannot emit punctuation as a row label.
# 行号为 A..Z；图纸用不到更多（参照图 8 行）。此处显式钳制，使荒唐的图框不会产出标点作为行号。
const GP_ZONE_ALPHABET: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


# The margins as they will actually be USED, so callers that need per-side numbers (the tick depth is
# one) read the same values the frame rectangle was built from.
# **实际生效**的边距，使需要逐边数值的调用方（刻度深度即其一）读到与图框矩形同源的那组值。
#
# ⚠️ RENAMED FROM gpClampedMargins (2026-10-16). The old name promised a clamp and at the time meant
# "clamped into the paper" — a reader who carried that assumption forward would conclude the frame is
# still confined to the sheet, which is no longer true. Only the anti-inside-out guard is folded
# through here, so the new name describes what the function RETURNS rather than what it once did.
# ⚠️ 原名 gpClampedMargins（2026-10-16 更名）。旧名承诺「钳制」，且在当时意味着「钳进纸内」—— 沿用该假设
# 的读者会以为图框仍被锁在纸上，而事实已非如此。此处折过的只剩**防内翻**那道护栏，故新名描述的是「本函数
# 返回什么」，而不是「它当年做了什么」。
static func gpEffectiveMargins(gpSheet: GPSheet) -> Array:
	if gpSheet == null:
		return GPSheet.GP_FRAME_MARGINS_DEFAULT.duplicate()
	return GPSheet.gpClampMargins(gpMargins(gpSheet), gpSheet.gpWidthMM, gpSheet.gpHeightMM)


# Field counts along each axis, as (columns, rows).
# 两条轴上的分格数，形如（列数, 行数）。
#
# [param gpScale] frame visual scale (A1 rebase): the nominal field grows with the paper, so the
# COUNT stays the same as the A3 reference's — an A1 sheet divides into the same 12 x 8 grid,
# each field twice as wide. Defaults to 1.0 so the raw form keeps its historical meaning.
# 图幅视觉比例（A1 重定基）：标称分格随纸幅变大，故**分格数**与 A3 参照一致 —— A1 图纸仍是
# 同样的 12×8 格网、每格宽一倍。默认 1.0，使原始形式保持历史含义。
static func gpZoneCounts(gpFrame: Rect2, gpScale: float = 1.0) -> Vector2i:
	return Vector2i(
		_gpZoneCount(gpFrame.size.x, gpScale), _gpZoneCount(gpFrame.size.y, gpScale))


# One axis: the EVEN count nearest to `length / (nominal field × scale)`, never below the minimum.
# 单轴：最接近 `长度 / (标称分格 × 比例)` 的**偶数**分格数，且不低于最小值。
static func _gpZoneCount(gpLength: float, gpScale: float = 1.0) -> int:
	var gpWant: float = maxf(gpLength, 0.0) / (GP_ZONE_FIELD_MM * maxf(gpScale, 0.0001))
	return maxi(int(round(gpWant * 0.5)) * 2, GP_ZONE_MIN_COUNT)


# How far this side's marks run outward from the frame line: the standard depth, shortened when the
# margin itself is narrower, so the ruler never spills past the sheet edge it hangs under.
# 该边的标记自图框线向外延伸多远：标准深度，若该边距本身更窄则相应缩短，使坐标带永不越过它下方的纸边。
# Margin 4 mm — the reference — yields exactly the full 3 mm.
# 4mm 边距（即参照图）恰好得到完整的 3mm。
#
# ⚠️ A NEGATIVE MARGIN YIELDS DEPTH 0 — I.E. NO RULER ON THAT SIDE, ON PURPOSE (2026-10-16). A negative
# margin means the frame line lies OUTSIDE the paper, so there is no band between the line and the
# sheet edge to divide; drawing one there would float marks in empty canvas. The degraded result is
# "that side has no ruler", never "a ruler hanging in space". gpZoneLabels applies the same rule to
# the numerals, per side, so one cramped edge never wipes out the others.
# ⚠️ 负边距给出深度 0 —— 即**该边不出坐标带**，这是刻意的（2026-10-16）。负边距意味着图框线位于纸**外**，
# 此时线与纸边之间不存在可供划分的带；在那里画只会把标记悬浮在空画布上。降级结果是「该边没有坐标带」，绝不
# 会是「悬在空中的坐标带」。gpZoneLabels 对数字**逐边**施加同一条规则，故一条挤住的边不会抹掉其余各边。
static func gpZoneDepth(gpMargin: float, gpScale: float = 1.0) -> float:
	var gpTick: float = GP_ZONE_TICK_MM * maxf(gpScale, 0.0001)
	return clampf(minf(gpTick, gpMargin), 0.0, gpTick)


# The four depths in margin order [left, top, right, bottom], in mm.
# 四个深度，按边距顺序 [左, 上, 右, 下]（mm）。
# ⚠️ SCALED (A1 rebase): the tick depth rides the frame visual scale, so an A1 band is twice as
# deep — matching its doubled margins and doubled label height.
# ⚠️ 带比例（A1 重定基）：刻度深度随图幅视觉比例，A1 的带深一倍 —— 与翻倍的边距、翻倍的标号字高
# 相配。
static func gpZoneDepths(gpSheet: GPSheet) -> Array:
	var gpM: Array = gpEffectiveMargins(gpSheet)
	var gpS: float = gpSheet.gpFrameScale()
	return [
		gpZoneDepth(float(gpM[GPSheet.GP_MARGIN_LEFT]), gpS),
		gpZoneDepth(float(gpM[GPSheet.GP_MARGIN_TOP]), gpS),
		gpZoneDepth(float(gpM[GPSheet.GP_MARGIN_RIGHT]), gpS),
		gpZoneDepth(float(gpM[GPSheet.GP_MARGIN_BOTTOM]), gpS),
	]


# Every zone division tick, as a list of [from, to] millimetre pairs.
# 所有分区刻度线，形如 [起点, 终点] 毫米对的列表。
# Internal boundaries only: the frame's own four lines already close the band, and the reference
# carries no tick at its corners either.
# 只画**内部分界线**：图框自身的四条线已经封住坐标带，参照图的角上同样没有刻度。
static func gpZoneTicks(gpSheet: GPSheet) -> Array:
	var gpOut: Array = []
	if gpSheet == null:
		return gpOut
	var gpFrame: Rect2 = gpFrameRect(gpSheet)
	if gpFrame.size.x <= 0.0 or gpFrame.size.y <= 0.0:
		return gpOut
	var gpD: Array = gpZoneDepths(gpSheet)
	# The field size rides the frame scale, so the grid COUNT matches the A3 reference's.
	# 分格边长随图幅比例，故格网**数**与 A3 参照一致。
	var gpN: Vector2i = gpZoneCounts(gpFrame, gpSheet.gpFrameScale())
	var gpDT: float = float(gpD[GPSheet.GP_MARGIN_TOP])
	var gpDB: float = float(gpD[GPSheet.GP_MARGIN_BOTTOM])
	var gpDL: float = float(gpD[GPSheet.GP_MARGIN_LEFT])
	var gpDR: float = float(gpD[GPSheet.GP_MARGIN_RIGHT])
	var gpStepX: float = gpFrame.size.x / float(gpN.x)
	var gpStepY: float = gpFrame.size.y / float(gpN.y)
	# ⚠️ A ZERO-DEPTH SIDE EMITS NOTHING (2026-10-16). A depth of 0 means that side has no band — the frame
	# line sits on or beyond the paper edge — so its ticks would be ZERO-LENGTH segments: invisible, yet 48
	# wasted entries in the draw list every frame. Skipping them also keeps this function consistent with
	# gpZoneLabels, which already withholds numerals from a side too narrow to hold them.
	# ⚠️ 深度为 0 的边**不发出任何标记**（2026-10-16）。深度 0 意味着该边没有坐标带 —— 图框线在纸边处或
	# 更外 —— 故它的刻度会是**零长度**线段：看不见，却每帧占掉绘制列表里 48 项。跳过它们也使本函数与
	# gpZoneLabels 保持一致：后者本就对窄到装不下数字的边不给标号。
	if gpDT > 0.0 or gpDB > 0.0:
		for gpC in range(1, gpN.x):
			var gpX: float = gpFrame.position.x + gpStepX * float(gpC)
			if gpDT > 0.0:
				gpOut.append([Vector2(gpX, gpFrame.position.y),
					Vector2(gpX, gpFrame.position.y - gpDT)])
			if gpDB > 0.0:
				gpOut.append([Vector2(gpX, gpFrame.end.y), Vector2(gpX, gpFrame.end.y + gpDB)])
	if gpDL > 0.0 or gpDR > 0.0:
		for gpR in range(1, gpN.y):
			var gpY: float = gpFrame.position.y + gpStepY * float(gpR)
			if gpDL > 0.0:
				gpOut.append([Vector2(gpFrame.position.x, gpY),
					Vector2(gpFrame.position.x - gpDL, gpY)])
			if gpDR > 0.0:
				gpOut.append([Vector2(gpFrame.end.x, gpY), Vector2(gpFrame.end.x + gpDR, gpY)])
	return gpOut


# The centring marks (对中符号) as arrow heads: two arms per side, apex ON the frame line at that
# side's midpoint, each arm running back out to the tick end.
# 对中符号（箭头形）：每边两臂，顶点落在该边中点的**图框线上**，两臂各自回到刻度末端。
# The straight stem is NOT emitted here: it is the zone division line at the centre, which the even
# count guarantees exists and which gpZoneTicks() already produces. Drawing it twice would put two
# strokes on one line. / 此处**不**发出直线中轴：它就是中线上的分界线，偶数分格已保证它存在，
# 且 gpZoneTicks() 已经画出。重复绘制会在同一条线上叠两笔。
static func gpZoneArrows(gpSheet: GPSheet) -> Array:
	var gpOut: Array = []
	if gpSheet == null:
		return gpOut
	var gpFrame: Rect2 = gpFrameRect(gpSheet)
	if gpFrame.size.x <= 0.0 or gpFrame.size.y <= 0.0:
		return gpOut
	var gpD: Array = gpZoneDepths(gpSheet)
	var gpDL: float = float(gpD[GPSheet.GP_MARGIN_LEFT])
	var gpDT: float = float(gpD[GPSheet.GP_MARGIN_TOP])
	var gpDR: float = float(gpD[GPSheet.GP_MARGIN_RIGHT])
	var gpDB: float = float(gpD[GPSheet.GP_MARGIN_BOTTOM])
	var gpMX: float = (gpFrame.position.x + gpFrame.end.x) * 0.5
	var gpMY: float = (gpFrame.position.y + gpFrame.end.y) * 0.5
	# The arms' half-width rides the frame scale (A1 rebase) — doubled paper, doubled arms.
	# 箭头两臂半宽随图幅比例（A1 重定基）—— 纸幅翻倍、臂长翻倍。
	var gpHalf: float = GP_ZONE_ARROW_HALF_MM * gpSheet.gpFrameScale()
	# Same zero-depth rule as gpZoneTicks: no band, no arrow — an arm of zero length is invisible ink that
	# still costs a draw call.
	# 与 gpZoneTicks 同样的零深度规则：没有坐标带就没有箭头 —— 零长度的臂是看不见的墨迹，却仍要花掉一次
	# 绘制调用。
	if gpDT > 0.0:
		gpOut.append([Vector2(gpMX, gpFrame.position.y),
			Vector2(gpMX - gpHalf, gpFrame.position.y - gpDT)])
		gpOut.append([Vector2(gpMX, gpFrame.position.y),
			Vector2(gpMX + gpHalf, gpFrame.position.y - gpDT)])
	if gpDB > 0.0:
		gpOut.append([Vector2(gpMX, gpFrame.end.y),
			Vector2(gpMX - gpHalf, gpFrame.end.y + gpDB)])
		gpOut.append([Vector2(gpMX, gpFrame.end.y),
			Vector2(gpMX + gpHalf, gpFrame.end.y + gpDB)])
	if gpDL > 0.0:
		gpOut.append([Vector2(gpFrame.position.x, gpMY),
			Vector2(gpFrame.position.x - gpDL, gpMY - gpHalf)])
		gpOut.append([Vector2(gpFrame.position.x, gpMY),
			Vector2(gpFrame.position.x - gpDL, gpMY + gpHalf)])
	if gpDR > 0.0:
		gpOut.append([Vector2(gpFrame.end.x, gpMY),
			Vector2(gpFrame.end.x + gpDR, gpMY - gpHalf)])
		gpOut.append([Vector2(gpFrame.end.x, gpMY),
			Vector2(gpFrame.end.x + gpDR, gpMY + gpHalf)])
	return gpOut


# The baseline y for a label whose band / row centre is gpCentreY.
# 中心线位于 gpCentreY 的标号的基线 y。
static func gpZoneBaselineY(gpCentreY: float, gpTextMM: float) -> float:
	return gpCentreY + GP_ZONE_BASELINE_RATIO * maxf(gpTextMM, 0.0)


# The row letter for a 0-based row index: A at the TOP row, per ISO 5457 (the reference confirms it
# — its `A` sits at y 21.6 mm, its `H` at 274.5 mm).
# 0 基行号对应的行字母：**顶行**为 A，依 ISO 5457（参照图证实：其 `A` 位于 y 21.6mm、`H` 位于 274.5mm）。
static func gpZoneRowLabel(gpIndex: int) -> String:
	var gpI: int = mini(maxi(gpIndex, 0), GP_ZONE_ALPHABET.length() - 1)
	return GP_ZONE_ALPHABET.substr(gpI, 1)


# Every zone label, as {"text": String, "at": Vector2} where `at` is the BASELINE ANCHOR: the string
# is centred horizontally on at.x and its baseline sits on at.y. One anchor shape serves all four
# sides, which is why the renderer needs no per-side special case.
# 所有分区标号，形如 {"text": String, "at": Vector2}，其中 `at` 是**基线锚点**：字符串在 at.x 上
# 水平居中、基线落在 at.y。单一锚点形式即可服务四边，故渲染器无需逐边特判。
#
# ⚠️ A SIDE WHOSE BAND IS NARROWER THAN THE TEXT GETS NO LABELS — and that is the honest answer,
# not a defect. A margin can be anything from negative (the frame line is off the sheet, so there is no
# band at all) to a fraction of a millimetre; a 2.85 mm number cannot be written in a band that narrow,
# and placing it anyway would put ink outside the sheet. The ticks and arrows are still drawn wherever a
# band exists (they are depth-bounded), so a cramped side degrades to "ruler without numerals" rather
# than to "ruler that spills". The gate is PER SIDE, so moving the frame towards the top edge never
# wipes out the bottom labels.
# ⚠️ 带宽窄于字高的边**不出标号** —— 这是诚实的答案，不是缺陷。图框可被拖到 1mm 下限，此时图框线与
# 纸边之间只剩 1mm；2.85mm 的数字写不进去，硬写就会把墨迹落到纸外。刻度与箭头仍会绘制（它们受深度
# 约束、留在纸内），故窄边降级为「无数字的坐标带」而非「溢出纸面的坐标带」。闸门**逐边**生效，因此
# 把图框拖向上边不会把下边的标号一并抹掉。
# [param gpTextMM] text height: both the baseline offset and the fit test / 字高：既用于基线偏移，
#   也用于「放不放得下」的判定
static func gpZoneLabels(gpSheet: GPSheet, gpTextMM: float) -> Array:
	var gpOut: Array = []
	if gpSheet == null:
		return gpOut
	var gpFrame: Rect2 = gpFrameRect(gpSheet)
	if gpFrame.size.x <= 0.0 or gpFrame.size.y <= 0.0:
		return gpOut
	var gpD: Array = gpZoneDepths(gpSheet)
	var gpN: Vector2i = gpZoneCounts(gpFrame, gpSheet.gpFrameScale())
	var gpStepX: float = gpFrame.size.x / float(gpN.x)
	var gpStepY: float = gpFrame.size.y / float(gpN.y)
	var gpText: float = maxf(gpTextMM, 0.0)
	var gpDT: float = float(gpD[GPSheet.GP_MARGIN_TOP])
	var gpDB: float = float(gpD[GPSheet.GP_MARGIN_BOTTOM])
	var gpDL: float = float(gpD[GPSheet.GP_MARGIN_LEFT])
	var gpDR: float = float(gpD[GPSheet.GP_MARGIN_RIGHT])
	var gpLeft: bool = gpDL >= gpText
	var gpRight: bool = gpDR >= gpText
	var gpTop: bool = gpDT >= gpText
	var gpBottom: bool = gpDB >= gpText
	if gpLeft or gpRight:
		var gpAtLeft: float = gpFrame.position.x - gpDL * 0.5
		var gpAtRight: float = gpFrame.end.x + gpDR * 0.5
		for gpR in gpN.y:
			var gpY: float = gpFrame.position.y + gpStepY * (float(gpR) + 0.5)
			var gpLetter: String = gpZoneRowLabel(gpR)
			if gpLeft:
				gpOut.append({"text": gpLetter, "at": Vector2(gpAtLeft, gpZoneBaselineY(gpY, gpText))})
			if gpRight:
				gpOut.append({"text": gpLetter, "at": Vector2(gpAtRight, gpZoneBaselineY(gpY, gpText))})
	if gpTop or gpBottom:
		var gpAtTop: float = gpFrame.position.y - gpDT * 0.5
		var gpAtBottom: float = gpFrame.end.y + gpDB * 0.5
		for gpC in gpN.x:
			var gpX: float = gpFrame.position.x + gpStepX * (float(gpC) + 0.5)
			var gpNum: String = str(gpC + 1)
			if gpTop:
				gpOut.append({"text": gpNum, "at": Vector2(gpX, gpZoneBaselineY(gpAtTop, gpText))})
			if gpBottom:
				gpOut.append({"text": gpNum, "at": Vector2(gpX, gpZoneBaselineY(gpAtBottom, gpText))})
	return gpOut


# ---------------------------------------------------------------------------
# Frame dragging (图框拖动) — Rev.3 stage 0c / Rev.3 阶段 0c
# ---------------------------------------------------------------------------
# WHY THE DRAG ARITHMETIC LIVES HERE / 为何拖拽算术落在此处：
# the renderer strokes a rectangle derived from these margins and the hit-test accepts grabs on a
# rectangle derived from the same margins (see this file's header). A drag is therefore a
# TRANSFORMATION OF THE MARGINS — and if the canvas computed those margins on its own, the frame you
# drag and the frame you see would be derived twice. Every function below is pure and headless.
# 渲染器描的矩形与命中判定接受的矩形都由这些边距推导（见本文件头）。于是「拖拽」就是一次**边距变换**
# —— 若画布自行计算这组边距，「你拖的框」与「你看到的框」就会各推导一次。以下全是纯函数、可 headless 测。

# Sentinel for "no side": deliberately -1 so it can never collide with a margin index (0..3).
# 表示「没有边」的哨兵：刻意取 -1，使其永不与边距下标（0..3）冲突。
#
# ⚠️ A SIDE **IS** A MARGIN INDEX, on purpose: 左侧 == GP_MARGIN_LEFT, 上 == GP_MARGIN_TOP, ...
# Reusing GPSheet's indices means the side->margin association cannot drift — a second enum would be
# one more place for "which element does the left edge touch?" to be answered differently.
# ⚠️ 「一条边」**就是**一个边距下标，刻意的：左 == GP_MARGIN_LEFT、上 == GP_MARGIN_TOP…… 复用 GPSheet
# 的下标使「边 ↔ 边距」的对应关系不可能分家 —— 另立一个枚举就等于又多了一处会答错的地方。
const GP_SIDE_NONE: int = -1


# Element-wise margin comparison with an explicit tolerance. Two MEASURED reasons why `==` is not used
# here (both verified on 2026-10-15 against the running engine, NOT inferred):
# 逐项比较边距，带显式容差。不用 `==` 有两条**实测**理由（均于 2026-10-15 对运行中的引擎核对，非推断）：
#
#   1. `==` IS EXACT. `[25.0 + 1e-12] == [25.0]` is `false`. Margin values come out of pan / drag
#      arithmetic, so such noise is normal — a plain click would then read as "changed" and record a
#      phantom undo step every time.
#      1. `==` 是**精确**相等。`[25.0 + 1e-12] == [25.0]` 为 `false`。边距取自平移 / 拖拽算术，
#         这种噪声是常态 —— 于是单纯点击会被读作「变了」，每次都记下一个幽灵撤销步。
#   2. `==` IS TYPE-STRICT PER ELEMENT. `[25, 5, 5, 5]` (ints) != `[25.0, 5.0, 5.0, 5.0]` (floats).
#      Margins arrive from JSON (a whole number parses back as INT) and from the frame dialog's spin
#      boxes — so an UNCHANGED value can compare unequal and be reported as an edit.
#      2. `==` 逐元素**类型严格**。`[25, 5, 5, 5]`（整数）≠ `[25.0, 5.0, 5.0, 5.0]`（浮点）。边距会
#         来自 JSON（整数会被解析回 INT），也会来自图框对话框的数值框 —— 故**未改变**的值也可能判为
#         不等、被报成一次编辑。
#
# ⚠️ CORRECTION ON THE RECORD: an earlier draft of this file justified the helper by claiming `==`
# compares arrays BY REFERENCE. That is FALSE — measured, `a.duplicate() == a` is `true` (Array `==`
# compares by value). The helper is still required, but for reasons 1 and 2 above. The wrong premise
# happened to produce the right code; the comment had to be fixed so nobody later "simplifies" this
# away on the strength of a claim that does not hold.
# ⚠️ 勘误入档：本文件早前的一稿以「`==` **按引用**比较数组」为由引入本函数。那是**错的** —— 实测
# `a.duplicate() == a` 为 `true`（Array `==` 是按值比较）。本函数仍然必需，但理由改为上面两条。
# 错误的前提碰巧产出了正确的代码；注释必须改正，以免后人凭着一条不成立的论断把它「简化」掉。
static func gpSameMargins(gpA: Array, gpB: Array) -> bool:
	if gpA.size() != gpB.size():
		return false
	for gpI in gpA.size():
		if absf(float(gpA[gpI]) - float(gpB[gpI])) > 0.0001:
			return false
	return true


# The world point at the middle of each side, ordered like the margins [left, top, right, bottom].
# 每条边中点的世界坐标，顺序与边距一致 [左, 上, 右, 下]。
#
# These are the side-handle anchors: dragging one moves that single margin (i.e. resizes the frame),
# which is the ONLY way to widen a margin (see the pan function below).
# 它们是侧手柄的锚点：拖动其中一个只改那一条边距（即改尺寸），而这正是**唯一**能把边距改大的途径
# （见下方平移函数）。
static func gpSideMidpoints(gpSheet: GPSheet) -> Array:
	var gpOut: Array = []
	if gpSheet == null:
		return gpOut
	var gpF: Rect2 = gpFrameRect(gpSheet)
	if gpF.size.x <= 0.0 or gpF.size.y <= 0.0:
		return gpOut
	var gpMX: float = (gpF.position.x + gpF.end.x) * 0.5
	var gpMY: float = (gpF.position.y + gpF.end.y) * 0.5
	gpOut.append(Vector2(gpF.position.x, gpMY))
	gpOut.append(Vector2(gpMX, gpF.position.y))
	gpOut.append(Vector2(gpF.end.x, gpMY))
	gpOut.append(Vector2(gpMX, gpF.end.y))
	return gpOut


# Which side handle a world point grabs, or GP_SIDE_NONE. A handle is a DISC of radius gpTol around
# the side's midpoint, so the handle region is a strict subset of that side's grab band.
# 世界点抓到哪个侧手柄，或 GP_SIDE_NONE。手柄是侧中点周围半径 gpTol 的**圆盘**，故手柄区是该边抓取带
# 的严格子集。
static func gpHitSideHandle(gpSheet: GPSheet, gpWorld: Vector2, gpTol: float) -> int:
	var gpMids: Array = gpSideMidpoints(gpSheet)
	var gpBest: int = GP_SIDE_NONE
	var gpBestD: float = maxf(gpTol, 0.0)
	for gpI in gpMids.size():
		var gpD: float = gpWorld.distance_to(gpMids[gpI] as Vector2)
		if gpD <= gpBestD:
			gpBestD = gpD
			gpBest = gpI
	return gpBest


# Which frame LINE a world point grabs, or GP_SIDE_NONE. The band is `gpTol` on either side of the
# frame line (`frame_view`'s header calls it "内框线 ± 6px 的一圈带状区"), and the point must also lie
# within that side's span (extended by the same tolerance, so corners are reachable from outside).
# 世界点抓到哪条**图框线**，或 GP_SIDE_NONE。带状区为图框线两侧各 gpTol（`frame_view` 文件头称之为
# 「内框线 ±6px 的一圈带状区」），且该点须落在该边的跨度内（跨度同样外扩 gpTol，使角部可从外侧够到）。
#
# ⚠️ NEVER "INSIDE THE FRAME GRABS IT": a 420x297 rectangle must not hijack every click on the sheet.
# Only the band does; the whole interior falls through to selection / marquee as before.
# ⚠️ **框内一律不抓**：420×297 的矩形绝不能把图纸上的每一次点击都吃掉。只有带状区会命中；内部照旧
# 落到选择 / 框选。
#
# Ties (a point equidistant from two lines, i.e. exactly on a corner diagonal) resolve to the LOWEST
# margin index — deterministic, and documented so the behaviour is not "whatever the loop did".
# 平局（一点到两条线等距，即恰在角平分线上）取**最小**边距下标 —— 确定且入档，行为不是「循环碰巧怎么走」。
static func gpFrameSideAt(gpSheet: GPSheet, gpWorld: Vector2, gpTol: float) -> int:
	if gpSheet == null:
		return GP_SIDE_NONE
	var gpF: Rect2 = gpFrameRect(gpSheet)
	if gpF.size.x <= 0.0 or gpF.size.y <= 0.0:
		return GP_SIDE_NONE
	var gpT: float = maxf(gpTol, 0.0)
	# Candidates in TIE-BREAK order, each as [side, distance-to-the-line, whether-in-span].
	# `d <= best` (not `<`) makes the LAST of an exact tie win, so the list is written in the
	# tie-break order's REVERSE: bottom, right, top, left.
	# 候选按**平局裁决**顺序排列，每项为 [边, 到该线的距离, 是否在跨度内]。
	# 用 `d <= best`（而非 `<`）会让精确平局中的**后者**胜出，故此表按裁决顺序**倒序**书写：
	# 下、右、上、左。
	var gpCand: Array = [
		[GPSheet.GP_MARGIN_BOTTOM, absf(gpWorld.y - gpF.end.y),
			gpWorld.x >= gpF.position.x - gpT and gpWorld.x <= gpF.end.x + gpT],
		[GPSheet.GP_MARGIN_RIGHT, absf(gpWorld.x - gpF.end.x),
			gpWorld.y >= gpF.position.y - gpT and gpWorld.y <= gpF.end.y + gpT],
		[GPSheet.GP_MARGIN_TOP, absf(gpWorld.y - gpF.position.y),
			gpWorld.x >= gpF.position.x - gpT and gpWorld.x <= gpF.end.x + gpT],
		[GPSheet.GP_MARGIN_LEFT, absf(gpWorld.x - gpF.position.x),
			gpWorld.y >= gpF.position.y - gpT and gpWorld.y <= gpF.end.y + gpT],
	]
	var gpBest: int = GP_SIDE_NONE
	var gpBestD: float = gpT
	for gpC in gpCand:
		if not bool(gpC[2]):
			continue
		if float(gpC[1]) <= gpBestD:
			gpBestD = float(gpC[1])
			gpBest = int(gpC[0])
	return gpBest


# Margins after TRANSLATING the frame by gpDelta (mm) — the four margins move against each other, so
# the frame keeps its SIZE exactly while travelling FREELY: it may leave the paper on any side and even
# come to rest wholly outside it.
# 把图框**平移** gpDelta（mm）后的边距 —— 四条边距互相对冲，故图框尺寸精确不变，且**自由**移动：它可以
# 从任一边离开纸面，甚至可以整块停在纸外。
#
# ⚠️ THE DELTA IS NO LONGER CLAMPED (Rev.3 amendment, 2026-10-16). Until then the admissible interval
# was derived per axis from the paper bound (`left + d >= 1` and `right - d >= 1`), which on the A3
# default 25/5/5/5 measured [-24, +4] mm — the frame could not leave the sheet and, to the right,
# could barely move at all (the 5 mm right margin hit its floor after 4 mm). The user's request
# (「自由移动，没有限制」) retired that bound, so every delta is admissible. A margin that comes back
# NEGATIVE is the honest encoding of "that frame line is now off the sheet".
# ⚠️ 位移**不再**被钳制（Rev.3 修正，2026-10-16）。在那之前，允许的位移区间由纸面约束按轴推导
# （`left + d >= 1` 与 `right - d >= 1`），在 A3 默认 25/5/5/5 上实测为 [−24, +4]mm —— 图框离不开纸，
# 且往右几乎动不了（仅 5mm 的右边距走 4mm 就撞上下限）。用户的诉求（「自由移动，没有限制」）已作废该约束，
# 故任何位移都合法。回来的边距若为**负**，正是「该条图框线现在纸外」的诚实编码。
#
# ⚠️ WHY THE DELTA WAS EVER THE RIGHT THING TO CLAMP — AND WHY THAT REASONING SURVIVES / 为何当年钳制
# **位移**才是对的形状，以及为何那条理由至今仍成立：clamping the four margins individually (via
# GPSheet.gpClampMargins) would let one hit a bound while the other kept moving, which CHANGES THE SIZE
# — the frame would silently grow/shrink while the user is trying to move it. Translating by a single
# delta keeps `width == W - L - R` and `height == H - T - B` invariant BY CONSTRUCTION, so the size is
# preserved EXACTLY. (This is also why gpSameMargins exists: the arithmetic above introduces float
# noise, and a size check that used `==` would read a plain click as an edit.)
# ⚠️ 逐条钳制边距（经 GPSheet.gpClampMargins）会让一条撞到界而另一条继续走 —— 那就**改了尺寸**：用户想挪
# 框，框却悄悄胀大/缩小。用单一位移平移，在**构造上**保持 `宽 == W − L − R`、`高 == H − T − B` 不变，故尺寸
# **精确**不变。（这也是 gpSameMargins 存在的原因：上面的算术会引入浮点噪声，而用 `==` 做的尺寸检查会把
# 单纯点击读成一次编辑。）
#
# The incoming margins are still folded through gpEffectiveMargins() first, so a sheet carrying an
# inside-out pair gets repaired before it is translated rather than drifting further out of shape.
# 进来的边距仍先经 gpEffectiveMargins() 折一遍，故带有内翻对边距的图纸会先被修复再被平移，而不是越走越歪。
static func gpPanMargins(gpSheet: GPSheet, gpDelta: Vector2) -> Array:
	if gpSheet == null:
		return GPSheet.GP_FRAME_MARGINS_DEFAULT.duplicate()
	var gpM: Array = gpEffectiveMargins(gpSheet)
	var gpL: float = float(gpM[GPSheet.GP_MARGIN_LEFT])
	var gpT: float = float(gpM[GPSheet.GP_MARGIN_TOP])
	var gpR: float = float(gpM[GPSheet.GP_MARGIN_RIGHT])
	var gpB: float = float(gpM[GPSheet.GP_MARGIN_BOTTOM])
	return [gpL + gpDelta.x, gpT + gpDelta.y, gpR - gpDelta.x, gpB - gpDelta.y]


# Margins after dragging ONE side so that the LINE LANDS ON THE CURSOR — i.e. on gpWorldAxis, the
# cursor's world coordinate on that side's own axis. Exactly one element of the array changes — the
# opposite side is untouched, which is what makes this the "resize" gesture rather than a second pan.
# 把**一条边**拖到**光标所在之处** —— 即 gpWorldAxis，光标在**该边自身轴**上的世界坐标 —— 之后的边距。
# 数组中**恰好**一个元素改变 —— 对边不动，这正是它读作「改尺寸」而非第二次平移的原因。
#
# ⚠️ gpWorldAxis IS A WORLD COORDINATE, NOT A MARGIN VALUE (Rev.3 stage 0d) / ⚠️ gpWorldAxis 是**世界
# 坐标**，不是边距值（Rev.3 阶段 0d）。It is the raw number the caller read off the pointer. Two things
# follow, and both are load-bearing:
# 它是调用方自指针读到的原始数值。由此得到两件事，而两件都是承重的：
#   * the margin is the DISTANCE from that side's PAPER EDGE, so gpPaperOrigin is subtracted here —
#     measured from the edge, never from the world origin. That is what makes the drag feel identical
#     on a sheet parked at (300, 200) and on one at (0, 0).
#     边距是到**该边纸缘**的距离，故此处减掉 gpPaperOrigin —— 自纸缘量起、绝不从世界原点量起。这正是
#     停在 (300, 200) 的图纸与停在 (0, 0) 的图纸手感相同的原因。
#   * for RIGHT / BOTTOM that distance runs the OTHER way round the paper, so it is `span - local`.
#     对**右 / 下**两边，该距离是绕纸的另一向量取的，故取 `span − local`。
#
# ⚠️ THE MIRROR IS A CORRECTION, RECORDED AS SUCH (Rev.3 stage 0d, 2026-10-16) / ⚠️ 该镜像是一次
# **更正**，在此如实入档（Rev.3 阶段 0d，2026-10-16）：until this stage the right and bottom handles
# computed `margin = cursor` — the very expression the left and top ones use — which put the dragged
# line at `span - cursor` instead of under the cursor. Dragging the RIGHT handle 35 mm leftward
# therefore moved the line 375 mm leftward and collapsed the frame on the first motion.
# 在此之前，右 / 下两个手柄算的是 `margin = 光标` —— 与左 / 上同一个表达式 —— 这使被拖的线落在
# `span − 光标` 处、而不是光标之下。于是把**右**手柄向左拖 35mm，线会向左跑 375mm，并在第一次移动时
# 就把图框压扁。
# LEFT/TOP were always correct because there the margin and the line's own coordinate coincide — which
# is precisely how the asymmetry stayed invisible. Two pinned expectations were corrected alongside it;
# both had been transcribed from this implementation rather than derived from the intent their own
# names state ("the side lands on the cursor's coordinate on that axis").
# 左 / 上一直是对的，因为在那里边距与线自身的坐标恰好重合 —— 这种不对称正因此而不易察觉。随之更正了
# 两条已钉住的期望值；两条都是自本实现抄来的，而不是从它们自身名字所声明的意图（「该边落到光标在该轴
# 上的坐标」）推导出来的。
#
# ⚠️ THE ONLY BOUND LEFT IS THE FRAME'S OWN (Rev.3 amendment, 2026-10-16): the dragged margin may not
# exceed `span - MIN_SIZE - other`, i.e. that side may not cross its opposite and turn the frame inside
# out. There is NO LOWER BOUND — dragging a side OUTWARD past the paper edge is free, and the resulting
# NEGATIVE margin is how "this frame line is off the sheet" is written down.
# ⚠️ 只剩图框**自身**的那道界（Rev.3 修正，2026-10-16）：被拖动的边距不得超过 `span − MIN_SIZE − 对边`，
# 即该边不得越过对边而使图框内翻。**没有**下限 —— 把一条边向**外**拖出纸边是自由的，得到的**负**边距正是
# 「该条图框线在纸外」的写法。
#
# ⚠️ AN UPPER BOUND, NOT A PAIR-CLAMP: only the dragged element is written, so the opposite edge stays
# exactly where it was — which is the property that makes this read as a resize. The result is still
# folded through GPSheet.gpClampMargins as a floor: on a legal input that is a no-op (idempotent), and
# on any input it repairs an inside-out pair — the one non-negotiable constraint of this feature.
# ⚠️ 这是**上限**，不是成对钳制：只写被拖动的那个元素，故对边精确停在原处 —— 正是这条性质使本手势读作
# 改尺寸。结果仍过一遍 GPSheet.gpClampMargins 兜底：对合法输入它是空操作（幂等），对任何输入它修复内翻的
# 对边距 —— 这是本功能唯一不可协商的约束。
static func gpDragSideMargins(gpSheet: GPSheet, gpSide: int, gpWorldAxis: float) -> Array:
	if gpSheet == null:
		return GPSheet.GP_FRAME_MARGINS_DEFAULT.duplicate()
	var gpM: Array = gpEffectiveMargins(gpSheet)
	if gpSide < 0 or gpSide >= gpM.size():
		return gpM
	var gpMinSize: float = GPSheet.GP_FRAME_MIN_SIZE_MM
	var gpSpan: float = gpSheet.gpWidthMM
	var gpOther: float = 0.0
	match gpSide:
		GPSheet.GP_MARGIN_LEFT:
			gpOther = float(gpM[GPSheet.GP_MARGIN_RIGHT])
		GPSheet.GP_MARGIN_RIGHT:
			gpOther = float(gpM[GPSheet.GP_MARGIN_LEFT])
		GPSheet.GP_MARGIN_TOP:
			gpOther = float(gpM[GPSheet.GP_MARGIN_BOTTOM])
			gpSpan = gpSheet.gpHeightMM
		_:
			gpOther = float(gpM[GPSheet.GP_MARGIN_TOP])
			gpSpan = gpSheet.gpHeightMM
	# Which axis this side reads, and where its paper edge sits on that axis. A side reads the axis it
	# runs PERPENDICULAR to: the left/right lines are vertical, so they read x; top/bottom read y.
	# 该边读哪条轴，以及它那条纸缘在该轴上的位置。一条边读的是它**垂直**于的那条轴：左右两条线竖直，
	# 故读 x；上下读 y。
	var gpVertical: bool = gpSide == GPSheet.GP_MARGIN_TOP or gpSide == GPSheet.GP_MARGIN_BOTTOM
	var gpEdge: float = gpSheet.gpPaperOrigin.y if gpVertical else gpSheet.gpPaperOrigin.x
	# Distance from that paper edge to the cursor, measured in the axis' own direction.
	# 自该纸缘到光标的距离，按该轴自身的方向量取。
	var gpLocal: float = gpWorldAxis - gpEdge
	# RIGHT / BOTTOM measure from the FAR edge, so the distance is the span minus the offset.
	# 右 / 下自**远**端纸缘量起，故该距离为跨度减去偏移。
	var gpWanted: float = gpLocal
	if gpSide == GPSheet.GP_MARGIN_RIGHT or gpSide == GPSheet.GP_MARGIN_BOTTOM:
		gpWanted = gpSpan - gpLocal
	# ⚠️ `maxf(..., 0.0)` and NOT the old `maxf(..., gpMin)`: on an absurd paper the bound could
	# otherwise go negative, and `minf(value, negative)` would let the dragged side run PAST its
	# opposite — the exact inside-out state this function exists to prevent.
	# ⚠️ 用 `maxf(..., 0.0)` 而非旧写的 `maxf(..., gpMin)`：否则在荒唐纸幅下该上限可能为负，而
	# `minf(取值, 负数)` 会让被拖的边**越过**对边 —— 恰恰是本函数存在的意义所在要防的那种内翻。
	var gpHi: float = maxf(gpSpan - gpMinSize - gpOther, 0.0)
	gpM[gpSide] = minf(gpWanted, gpHi)
	return GPSheet.gpClampMargins(gpM, gpSheet.gpWidthMM, gpSheet.gpHeightMM)
