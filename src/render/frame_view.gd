class_name GPFrameView
extends Node2D

# Draws the sheet's drawing frame + bilingual title block, in real millimetres.
# 以真实毫米绘制图纸的图框 + 双语标题栏。
# WHY A NODE UNDER world_root: the frame IS part of the drawing, not part of the UI.
# Being a child of world_root means it inherits the camera pan/zoom, so a 420x297 mm
# frame scales exactly like a 12 mm valve — which is what "1:1 reproduction" requires.
# Drawing it in screen space would need a parallel world->screen transform and would
# drift from the geometry at fractional zooms.
# 为何挂在 world_root 下：图框属于**图纸**而非界面。作为 world_root 的子节点，它继承相机
# 平移/缩放，故 420×297mm 的图框与 12mm 的阀门按完全相同的比例缩放 —— 这正是「1:1 复刻」
# 所要求的。若在屏幕空间绘制，则需另建一套世界→屏幕变换，且在非整数缩放下会与几何错位。
# Its MARGINS are SHEET DATA (Rev.3 stage 0a) and this view only READS them, so the frame moves
# for every consumer at once. Its ZONE RULER comes from the geometry module too (stage 0b), which is
# why the ticks follow a dragged frame instead of drifting away from it. Stage 0c makes the frame
# DRAGGABLE, but the drag interaction (grab band, side handles, hover cursor) lives in GPFrameGripOps
# and its handles are drawn in SCREEN space by that class — none of it is here. This view stays a
# pure renderer of whatever the sheet currently says, which is what lets a live drag simply repaint.
# 它的**边距**是**图纸数据**（Rev.3 阶段 0a），本视图只**读**，故图框一动、所有消费方同时跟着动。
# 它的**坐标带**同样取自几何模块（阶段 0b），这正是刻度能跟着被拖动的图框走、而不是与之脱节的原因。
# 阶段 0c 让图框**可拖动**，但拖拽交互（抓取带、侧手柄、悬停光标）在 GPFrameGripOps 内，
# 且其手柄由该类在**屏幕空间**绘制 —— 本文件一概不参与。本视图始终只是「照图纸当前所述绘制」，
# 这正是实时拖动只需重绘即可的原因。
# See plan Phase 2 + Rev.3 stages 0a/0b/0c / 见计划 Phase 2 与 Rev.3 阶段 0a/0b/0c。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

# The sheet this frame renders. Null = nothing drawn.
# 本图框渲染的图纸。为 null 时不绘制。
var gpSheet: GPSheet = null

# Line weights in mm, per ISO 128: the trim line is thin, the drawing frame is thick.
# 线宽（mm），依 ISO 128：裁边线细，图框线粗。
const GP_W_TRIM: float = 0.25
const GP_W_FRAME: float = 0.70
const GP_W_GRID: float = 0.18

# Margins live on the SHEET, not here — see GPSheet.gpFrameMargins / GPFrameGeometry.
# 边距在**图纸**上，不在此处 —— 见 GPSheet.gpFrameMargins / GPFrameGeometry。
# They used to be two constants right here, which is exactly what made the frame immovable by
# design; keeping a copy would give one fact two homes the moment any UI could change margins.
# 它们原就写在此处、两个常量 —— 正是这使图框在设计上不可移动；一旦任何界面能改边距，留下副本
# 就等于让同一个事实有两个家。

# Text heights in mm, taken from the measured DEXPI C01 palette. The reference draws every
# title-block field at ONE height — its `label` and `equipmentbarlabel` groups are both 2.5 mm — so
# caption and value are deliberately equal here. They keep separate names because a future template
# may want to distinguish them, and because tests pin both.
# 字高（mm），取自 DEXPI C01 实测字号档。参照图的**每个**标题栏字段都取同一字高 —— 其 `label`
# 与 `equipmentbarlabel` 组均为 2.5mm —— 故此处字段名与字段值刻意相等。保留两个名字是因为将来
# 的模板可能要把二者分开，也因为测试分别钉住了它们。
# The previous 2.2 / 2.8 pair matched neither the reference nor any standard tier.
# 此前的 2.2 / 2.8 组合既不匹配参照图，也不对应任何标准档位。
#
# WRITTEN AS LITERALS ON PURPOSE / 刻意写成字面值：GDScript rejects a cross-class constant
# reference in a const initialiser ("isn't a constant expression"), so the single source of truth is
# kept by a TEST instead — gp_test_ui_visual_scale.gd asserts these equal GPTextRole's values.
# GDScript 不允许在常量初始化式中引用其它类的常量（报 "isn't a constant expression"），故改由**测试**
# 维持单一来源：gp_test_ui_visual_scale.gd 断言它们与 GPTextRole 的取值相等。
const GP_CAPTION_MM: float = 2.5
const GP_VALUE_MM: float = 2.5

# Ink colours. The canvas background is dark (0.13,0.14,0.18), so ink is light — the
# frame reads as a CAD viewport overlay, not as a white paper simulation.
# 墨色。画布背景为深色，故墨色取亮 —— 图框呈现为 CAD 视口叠加层，而非白纸模拟。
const GP_INK: Color = Color(0.86, 0.89, 0.95, 0.95)
const GP_INK_DIM: Color = Color(0.72, 0.76, 0.84, 0.85)

# Accumulated canvas scale (camera zoom), captured once at the start of each draw, so the
# title-block text can be drawn in design pixels. See GPCanvasText.
# 每次绘制开始时捕获一次的累积画布缩放（相机缩放），使标题栏文字得以按设计像素绘制。见 GPCanvasText。
var _gpTextScale: float = 1.0

# Physical pixels per design pixel (Retina ~2), captured next to the zoom. The title block and
# the zone ruler rasterise at PHYSICAL pixel density (flicker/blur fix, 2026-10-16): a bitmap
# built at design-pixel density is magnified ~2x on a Retina screen, which is exactly the grey
# smudge this used to be. See GPCanvasText.gpSheetFontFit for the algebra.
# 每设计像素的物理像素数（Retina 约 2），与缩放一同捕获。标题栏与坐标带按**物理**像素密度
# 光栅化（发糊修复，2026-10-16）：设计像素密度的位图在 Retina 屏上被放大约 2 倍，正是此前的
# 灰糊块。代数见 GPCanvasText.gpSheetFontFit。
var _gpDeviceScale: float = 1.0

# The sheet's frame visual scale (A1 rebase, 2026-10-16), captured once per draw like the two
# scales above. Every frame FURNISHING below (line weights, the title-block cell grid and its
# text tiers) multiplies its A3-era millimetre constant by this; an A3-era sheet yields exactly
# 1.0 and therefore the historical ink, bit for bit.
# 图纸的图幅视觉比例（A1 重定基，2026-10-16），与上面两个比例一样每次绘制捕获一次。下方每一项
# 图框**陈设**（线宽、图签格网与它的三档字高）都把 A3 时代的毫米常量乘上它；A3 时代图纸恰得 1.0
# —— 墨迹逐位不变。
var _gpFrameScale: float = 1.0


# Rasterise the title-block text at the scale it is actually drawn at (the camera zoom), so the
# 2.2 / 2.8 mm field text stays crisp instead of being magnified from a 2 px raster. The property
# is an ENUM: `= true` would coerce to 1 = DISABLED, so the constant must be used.
# 按「实际绘制缩放」（相机缩放）光栅化标题栏文字，使 2.2 / 2.8mm 的字段文字保持清晰，而非由
# 2px 光栅放大而来。该属性是**枚举**：写 `= true` 会被强转为 1（DISABLED），故必须用常量。
func _ready() -> void:
	oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED


func _draw() -> void:
	if gpSheet == null:
		return
	if not gpSheet.gpFrameOn:
		return
	# The scale is read once per draw and reused by every string in the title block.
	# 每次绘制读取一次缩放，供标题栏内每一串文字复用。
	_gpTextScale = GPCanvasText.gpScaleOf(self)
	_gpDeviceScale = GPCanvasText.gpDeviceScaleOf(self)
	_gpFrameScale = gpSheet.gpFrameScale()
	var gpW: float = gpSheet.gpWidthMM
	var gpH: float = gpSheet.gpHeightMM
	if gpW <= 1.0 or gpH <= 1.0:
		return
	# Trim line (裁边线): the sheet edge as DRAWN. It sits `GP_TRIM_INSET_MM` inside the paper, which
	# is what the reference drawing does (see GPFrameGeometry.GP_TRIM_INSET_MM) — until Rev.3 stage 0c
	# this project drew it ON the paper edge, so every existing drawing's trim line moves 1 mm inwards.
	# 裁边线：**画出来的**纸边。它位于纸内 `GP_TRIM_INSET_MM` 处，与参照图一致（见
	# GPFrameGeometry.GP_TRIM_INSET_MM）—— 在 Rev.3 阶段 0c 之前本项目把它画在**纸边**上，
	# 故每一张既有图纸的裁边线都向内移动 1mm。
	# Its rectangle comes from the geometry module for the same reason the frame's does: stroke and
	# hit-test must agree, and a hard-coded Rect2 here is exactly how they would drift apart.
	# 其矩形与图框同理取自几何模块：描边与命中必须一致，而此处硬写一个 Rect2 正是二者分家的起点。
	draw_rect(GPFrameGeometry.gpTrimRect(gpSheet), GP_INK_DIM, false, GP_W_TRIM * _gpFrameScale)
	# Drawing frame (图框): the area actually available for the drawing. Its rectangle comes from
	# the geometry module and is NOT recomputed here, so what gets stroked is exactly what the
	# hit-test will reason about once the frame becomes draggable (Rev.3 stage 0c).
	# 内图框：真正可用于绘图的范围。其矩形取自几何模块、**不在此重算**，故描出来的正是图框可
	# 拖动之后（Rev.3 阶段 0c）命中判定所依据的那个矩形。
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(gpSheet)
	draw_rect(gpFrame, GP_INK, false, GP_W_FRAME * _gpFrameScale)
	# The zone ruler is part of the frame, so it is drawn immediately after it — and before the title
	# block, so the block's ink always wins in the bottom-right corner.
	# 坐标带属于图框，故紧随其后绘制 —— 且在标题栏之前，使右下角的墨迹始终以标题栏为准。
	_gpDrawZoneGrid()
	_gpDrawTitleBlock(gpFrame)


# Draw the sheet's zone ruler: division ticks, the four centring arrows, and the zone labels
# (numbers 1..n top and bottom, letters A.. down both sides).
# 绘制图纸坐标带：分格刻度、四边对中箭头，以及分区标号（上下为数字 1..n，左右为字母 A.. 自上而下）。
#
# WHY EVERYTHING COMES FROM GPFrameGeometry / 为何一切都取自 GPFrameGeometry:
# the ruler hangs off the frame line, and the frame line is draggable as of Rev.3. Deriving the ticks
# here from `gpSheet.gpWidthMM` would keep them bolted to the paper while the frame slid away — the
# classic "two copies of one geometric fact" failure. This function therefore performs NO geometry:
# it iterates three lists and draws them.
# 坐标带依附于图框线，而自 Rev.3 起图框线可拖动。若在此处自行由 `gpSheet.gpWidthMM` 推导刻度，
# 结果会是图框滑走、刻度还钉在纸上 —— 即典型的「同一几何事实写两份」失效。故本函数**不做任何
# 几何推导**：只遍历三个列表并绘制它们。
func _gpDrawZoneGrid() -> void:
	if gpSheet == null:
		return
	var gpFont: Font = _gpFont()
	# The ruler is true-scale like the title block: it must NOT take the readability floor, or at low
	# zoom a 2.85 mm label would swell past the band it belongs to.
	# 坐标带与标题栏同为真实比例：**不得**取可读性下限，否则在低缩放下 2.85mm 的标号会胀出它所属的
	# 那条带。
	# ⚠️ SCALED (A1 rebase): the label height rides the frame scale, and gpZoneLabels uses the SAME
	# value for its fit test and baseline — so band, fit and baseline move together by construction.
	# ⚠️ 带比例（A1 重定基）：标号字高随图幅视觉比例，gpZoneLabels 的放行判定与基线用的是**同一个**
	# 值 —— 带、判定、基线在构造上一同移动。
	var gpMM: float = GPTextRole.GP_FRAME_GRID_MM * _gpFrameScale
	for gpSeg in GPFrameGeometry.gpZoneTicks(gpSheet):
		var gpFrom: Vector2 = gpSeg[0]
		var gpTo: Vector2 = gpSeg[1]
		draw_line(gpFrom, gpTo, GP_INK_DIM, GP_W_GRID * _gpFrameScale)
	for gpSeg in GPFrameGeometry.gpZoneArrows(gpSheet):
		var gpApex: Vector2 = gpSeg[0]
		var gpTip: Vector2 = gpSeg[1]
		draw_line(gpApex, gpTip, GP_INK_DIM, GP_W_GRID * _gpFrameScale)
	for gpLabel in GPFrameGeometry.gpZoneLabels(gpSheet, gpMM):
		var gpAt: Vector2 = gpLabel["at"]
		_gpDrawTextCentred(gpFont, gpAt, str(gpLabel["text"]), gpMM, GP_INK)


# Draw the 180x50 mm title block wherever the sheet's docking pair (anchor + offset) puts it.
# 按图纸的停靠对（锚角 + 偏移）绘制那块 180×50mm 标题栏。
# [param gpFrame] the inner frame rectangle (mm), straight from GPFrameGeometry — the block's place is
# derived from it, so the frame moving carries the block along with it.
#                 内框矩形（mm），直接取自 GPFrameGeometry —— 图块的位置由它推导，故图框一移动，图块随之而动。
#
# ⚠️ THE SILENT EARLY RETURN IS GONE (Rev.3 stage 1, §9-①) / ⚠️ 静默提前返回已删除（Rev.3 阶段 1，§9-①）：
# this used to `return` when the block's left edge crossed the frame's, i.e. draw NOTHING when the frame was
# too narrow to hold the block. That was harmless while the place was computed by code and therefore always
# fit — but the block is now draggable and the frame can now be resized to almost nothing (stage 0c), so a
# user could reach a state where their title block silently vanished, with no cursor, no error and no way
# back except remembering that Ctrl+Z exists. The clamping now happens in the geometry layer, and its
# contract is "hug the anchor edge and overflow the far side rather than refuse to draw" — so this function
# no longer has a "there is no block" case at all.
# 过去当图块的左边界越过图框左边界时它会 `return`，即「内框窄得放不下图块就什么都不画」。图块位置由代码算
# 出来、因此永远放得下的年代，这无害 —— 但图块现在可拖动、图框现在也能被缩到几乎为零（阶段 0c），于是用户
# 可以到达一个状态：图签无声消失，没有光标提示、没有报错，唯一的退路是记得 Ctrl+Z 存在。钳制现已移到几何层，
# 其契约是「贴住锚边、向另一侧溢出，而不是拒绝绘制」—— 故本函数已不再有「没有图块」这一情形。
func _gpDrawTitleBlock(gpFrame: Rect2) -> void:
	# Placed = anchor + offset, clamped, then located on the frame. THE geometry is not recomputed here:
	# the block's rectangle comes from the one module the hit-test will also use, which is what keeps
	# "where it is drawn" and "where it can be grabbed" the same question.
	# 落位 = 锚角 + 偏移，钳制后落在内框上。几何**不**在此重算：图块矩形取自命中判定也会用的同一个模块，
	# 这正是「它画在哪」与「它能在哪被抓住」保持为同一个问题的原因。
	var gpBlock: Rect2 = GPFrameGeometry.gpTitleBlockPlaced(gpFrame, gpSheet)
	var gpB: float = gpBlock.end.y
	var gpOX: float = gpBlock.position.x
	# Block outline. Line weight rides the frame scale like every other furnishing.
	# 图块外框。线宽与其余陈设一样随图幅视觉比例。
	draw_rect(gpBlock, GP_INK, false, GP_W_FRAME * _gpFrameScale)
	var gpFont: Font = _gpFont()
	# The cell table is stored in A3-era millimetres relative to the block's bottom-left corner;
	# scaled here so an A1 block lays out its cells at exactly twice the size.
	# 格网表以 A3 时代毫米存成相对图块左下角的坐标；在此乘比例，使 A1 图签的单元格恰为两倍大小。
	for gpF in GPSheet.GP_TB_FIELDS:
		var gpFX: float = float(gpF["x"]) * _gpFrameScale
		var gpFY: float = float(gpF["y"]) * _gpFrameScale
		var gpFW: float = float(gpF["w"]) * _gpFrameScale
		var gpFH: float = float(gpF["h"]) * _gpFrameScale
		# Field table Y grows upward from the block's bottom; world Y grows downward.
		# 字段表的 Y 自图块底边向上增长；世界坐标 Y 向下增长。
		var gpTop: float = gpB - gpFY - gpFH
		var gpLeft: float = gpOX + gpFX
		draw_rect(Rect2(gpLeft, gpTop, gpFW, gpFH), GP_INK_DIM, false, GP_W_GRID * _gpFrameScale)
		var gpKey: String = str(gpF["key"])
		var gpCap: String = _gpTrBoth(str(gpF["cap"]))
		# The 1.2 / 3.0 mm padding pair is part of the same A3-era layout — scaled with it.
		# 1.2 / 3.0mm 的内边距对是同一份 A3 时代版式的一部分 —— 随之缩放。
		_gpDrawText(gpFont, Vector2(gpLeft + 1.2 * _gpFrameScale, gpTop + 3.0 * _gpFrameScale),
			gpCap, GP_CAPTION_MM * _gpFrameScale, GP_INK_DIM)
		_gpDrawValue(gpFont, gpKey, gpLeft, gpTop, gpFW, gpFH)


# Draw one field's value: one line in ZH/EN mode, two stacked lines in BOTH mode.
# An empty side is skipped rather than drawn as a blank line (graceful degradation).
# 绘制某字段的值：ZH/EN 模式单行，BOTH 模式上下双行；空的一侧跳过而非画空行（优雅降级）。
# [param gpFont] font to draw with / 绘制用字体
# [param gpKey] title-block field key / 标题栏字段键
# [param gpLeft] cell left (mm) / 单元格左边界
# [param gpTop] cell top (mm) / 单元格上边界
# [param gpFW] cell width (mm) / 单元格宽度
# [param gpFH] cell height (mm) / 单元格高度
func _gpDrawValue(gpFont: Font, gpKey: String, gpLeft: float, gpTop: float,
		gpFW: float, gpFH: float) -> void:
	if gpSheet == null:
		return
	var gpEntry: Variant = gpSheet.gpTitleBlock.get(gpKey)
	if gpEntry == null:
		return
	var gpVal: Variant = (gpEntry as Dictionary).get("value")
	if gpVal == null:
		return
	var gpV: Dictionary = gpVal as Dictionary
	var gpZh: String = str(gpV.get("zh", ""))
	var gpEn: String = str(gpV.get("en", ""))
	if gpZh == "" and gpEn == "":
		return
	var gpX: float = gpLeft + 1.2 * _gpFrameScale
	if gpSheet.gpLabelMode == GPSheet.GP_LABEL_BOTH:
		# Stacked: Chinese above, English below. Each side degrades independently.
		# 上下叠显：中文在上、英文在下。两侧各自独立降级。
		if gpZh != "" and gpEn != "":
			_gpDrawText(gpFont, Vector2(gpX, gpTop + 6.4 * _gpFrameScale), gpZh,
				GP_VALUE_MM * _gpFrameScale, GP_INK)
			_gpDrawText(gpFont, Vector2(gpX, gpTop + 9.4 * _gpFrameScale), gpEn,
				GP_VALUE_MM * _gpFrameScale, GP_INK)
		elif gpZh != "":
			_gpDrawText(gpFont, Vector2(gpX, gpTop + gpFH * 0.72), gpZh,
				GP_VALUE_MM * _gpFrameScale, GP_INK)
		else:
			_gpDrawText(gpFont, Vector2(gpX, gpTop + gpFH * 0.72), gpEn,
				GP_VALUE_MM * _gpFrameScale, GP_INK)
		return
	var gpOne: String = gpEn if gpSheet.gpLabelMode == GPSheet.GP_LABEL_EN else gpZh
	if gpOne == "":
		# Requested language empty: fall back to the other side instead of a blank cell.
		# 所求语言为空：回退到另一侧，而非留白。
		gpOne = gpZh if gpSheet.gpLabelMode == GPSheet.GP_LABEL_EN else gpEn
	if gpOne == "":
		return
	# ONE line, so the DRAWING TITLE may take the reference's larger height (4.0 mm, its
	# `DEXPI example PID` heading). This is deliberately confined to the single-line path: the
	# standard's block never stacks two lines in one 10 mm cell, so in BOTH mode the title keeps the
	# field height rather than let a 4.0 mm line collide with the line under it.
	# 单行，故**图纸标题**可采用参照图放大的字高（4.0mm，即其 `DEXPI example PID` 标题）。此处刻意
	# 只在单行路径生效：标准图的标题栏不在一个 10mm 单元格内叠两行，故 BOTH 模式下标题仍取字段字高，
	# 而不让 4.0mm 的行与它下面那行相撞。
	var gpMM: float = GP_VALUE_MM * _gpFrameScale
	if gpKey == "drawing_title":
		gpMM = GPTextRole.GP_DRAWING_TITLE_MM * _gpFrameScale
	_gpDrawText(gpFont, Vector2(gpX, gpTop + gpFH * 0.72), gpOne, gpMM, GP_INK)


# Font size for a given mm text height at the current canvas scale, as (integer size, residual) —
# hand BOTH to _gpDrawText; see GPCanvasText.gpFontFit for why the residual must not be dropped.
# The title block is a true-scale miniature of the sheet, so it takes NO legibility floor: a floor
# tall enough to help would make two stacked lines (3 mm baseline pitch) overlap.
# Rasterised at PHYSICAL pixel density since 2026-10-16 (the blur fix) — the bitmap density is
# 1:1 with the screen, so a 2.5 mm field is no longer a 6 px bitmap magnified by the display.
# 给定毫米字高在当前画布缩放下的字号，形如（整数号, 残差）—— 两者都要交给 _gpDrawText；残差不可
# 丢弃的原因见 GPCanvasText.gpFontFit。标题栏是图纸的真实比例缩样，故**不取**可读性下限：任何足够
# 大的下限都会让基线间距仅 3mm 的上下两行重叠。
# 自 2026-10-16 起按**物理**像素密度光栅化（发糊修复）—— 位图密度与屏幕 1:1，故 2.5mm 字段不再是
# 被显示器放大的 6px 位图。
func gpFontFit(gpMM: float) -> Vector2:
	return GPCanvasText.gpSheetFontFit(gpMM, _gpTextScale, _gpDeviceScale)


# Draw one string of the title block in design pixels, then restore the identity transform so the
# cell rectangles drawn around it keep their millimetre coordinates.
# 以设计像素绘制标题栏的一串文字，随后复位为单位变换，使环绕它的单元格线框仍按毫米坐标绘制。
#
# ⚠️ THE POSITION IS MILLIMETRES AND IS CONVERTED EXACTLY ONCE — BY gpDrawPos.
# The draw transform is `origin + scale * p`: its SCALE multiplies drawn coordinates and its ORIGIN
# rides through untouched. Getting that backwards is what broke this block: the baseline was computed
# in millimetres and then ALSO multiplied by the canvas scale, displacing every field by
# `(zoom - 1) x its distance from the sheet's top-left corner` — 0 at 100 %, which is why it shipped,
# and enough at the fit zoom to push the text out of the frame entirely. gpDrawPos() owns that one
# conversion and states the algebra; the baseline stays a millimetre value like the cell Rect2 above.
# ⚠️ 位置以毫米给出，且**只换算一次** —— 由 gpDrawPos 完成。
# 绘制变换是 `origin + scale * p`：其**缩放乘绘制坐标，原点原样通过**。搞反这一点正是本图块出问题
# 的原因：基线本已按毫米算好，却又乘了一次画布缩放，使每个字段位移
# `(缩放−1) × 自身到图纸左上角的距离` —— 100% 下恰为 0（故当时通过了审查），而在适配缩放下足以把文字
# 整个推出图框。gpDrawPos() 独自承担这唯一一次换算并写明该代数；基线始终是与上方单元格 Rect2 同级的
# 毫米值。
# [param gpPosMM] baseline origin, in millimetres / 毫米单位下的基线原点
# [param gpMM] sheet text height in millimetres / 图面字高（毫米）
func _gpDrawText(gpFont: Font, gpPosMM: Vector2, gpText: String, gpMM: float, gpCol: Color) -> void:
	if gpText == "":
		return
	var gpFit: Vector2 = gpFontFit(gpMM)
	draw_set_transform(Vector2.ZERO, 0.0, GPCanvasText.gpSheetTextScale(gpFit, _gpTextScale,
		_gpDeviceScale))
	draw_string(gpFont, GPCanvasText.gpSheetDrawPos(gpPosMM, gpFit, _gpTextScale, _gpDeviceScale),
		gpText, HORIZONTAL_ALIGNMENT_LEFT, -1, int(gpFit.x), gpCol)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Same as _gpDrawText, but the string is CENTRED horizontally on gpPosMM — which is what every zone
# label needs (the reference authors them `text-anchor="middle"`).
# 与 _gpDrawText 相同，但字符串在 gpPosMM 上**水平居中** —— 这正是每个分区标号所需的
# （参照图以 `text-anchor="middle"` 编排它们）。
#
# ⚠️ THE OFFSET IS APPLIED IN DRAW UNITS, NOT MILLIMETRES. Inside the transform below, one draw unit
# is one DESIGN PIXEL with font size gpFit.x, so the string's advance width measured at that same size
# is already the number to subtract — no mm conversion and, above all, no second application of the
# canvas scale (the trap documented on gpDrawPos). The transform's origin stays ZERO, so only the
# text's own anchor moves; no other geometry of this frame is affected.
# ⚠️ 偏移量以**绘制单位**扣除，而非毫米。下方变换内 1 绘制单位 = 1 设计像素、字号为 gpFit.x，故
# 以同号测得的字符串宽度就是应当扣除的那个数 —— 无需毫米换算，尤其**不得**再乘一次画布缩放
# （即 gpDrawPos 上记录的陷阱）。变换原点保持 ZERO，故只有文字自身的锚点移动，本图框其余几何不受影响。
# [param gpPosMM] baseline anchor in millimetres; the string is centred on its x, baseline on its y
#                 毫米制基线锚点：字符串在其 x 上居中、基线落在其 y 上
func _gpDrawTextCentred(gpFont: Font, gpPosMM: Vector2, gpText: String,
		gpMM: float, gpCol: Color) -> void:
	if gpText == "":
		return
	var gpFit: Vector2 = gpFontFit(gpMM)
	var gpSize: int = int(gpFit.x)
	var gpWidth: float = gpFont.get_string_size(gpText, HORIZONTAL_ALIGNMENT_LEFT, -1, gpSize).x
	draw_set_transform(Vector2.ZERO, 0.0, GPCanvasText.gpSheetTextScale(gpFit, _gpTextScale,
		_gpDeviceScale))
	var gpAt: Vector2 = GPCanvasText.gpSheetDrawPos(gpPosMM, gpFit, _gpTextScale, _gpDeviceScale)
	draw_string(gpFont, gpAt - Vector2(gpWidth * 0.5, 0.0), gpText,
		HORIZONTAL_ALIGNMENT_LEFT, -1, gpSize, gpCol)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Resolve a font without depending on the Settings autoload, so this view still draws
# under headless `--script` runs where autoloads do not exist.
# 取字体时不依赖 Settings 自动加载，使本视图在 autoload 不存在的 headless `--script` 下
# 依然能绘制。
func _gpFont() -> Font:
	var gpSet: Object = get_node_or_null("/root/Settings")
	if gpSet != null and gpSet.has_method("gpLoadFont"):
		var gpF: Font = gpSet.gpLoadFont(str(gpSet.get("gpFontKey"))) as Font
		if gpF != null:
			return gpF
	return ThemeDB.fallback_font


# Bilingual caption lookup with an autoload-free fallback to the raw key.
# 双语字段名查询；无 autoload 时回退为原始键。
func _gpTrBoth(gpKey: String) -> String:
	var gpI: Object = get_node_or_null("/root/I18n")
	if gpI != null and gpI.has_method("gpTrBoth"):
		return str(gpI.gpTrBoth(gpKey, gpKey))
	return gpKey


# Re-render after any frame-affecting change.
# 任何影响图框的改动后重绘。
func gpRefresh() -> void:
	queue_redraw()
