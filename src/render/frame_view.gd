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
# It is NOT editable geometry: no node/edge is created for it, and it never takes part in
# hit-testing or undo. / 它不是可编辑几何：不生成节点/边，也不参与拾取与撤销。
# See plan Phase 2 / 见计划 Phase 2。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

# The sheet this frame renders. Null = nothing drawn.
# 本图框渲染的图纸。为 null 时不绘制。
var gpSheet: GPSheet = null

# Line weights in mm, per ISO 128: the trim line is thin, the drawing frame is thick.
# 线宽（mm），依 ISO 128：裁边线细，图框线粗。
const GP_W_TRIM: float = 0.25
const GP_W_FRAME: float = 0.70
const GP_W_GRID: float = 0.18

# Margins in mm: the binding edge (left) is wider, per GB-T 14689 / ISO 5457.
# 边距（mm）：装订边（左）更宽，依 GB-T 14689 / ISO 5457。
const GP_MARGIN_BIND: float = 25.0
const GP_MARGIN_OTHER: float = 5.0

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
	var gpW: float = gpSheet.gpWidthMM
	var gpH: float = gpSheet.gpHeightMM
	if gpW <= 1.0 or gpH <= 1.0:
		return
	# Trim line (裁边线): the physical sheet edge.
	draw_rect(Rect2(0.0, 0.0, gpW, gpH), GP_INK_DIM, false, GP_W_TRIM)
	# Drawing frame (图框): the area actually available for the drawing.
	var gpL: float = GP_MARGIN_BIND
	var gpT: float = GP_MARGIN_OTHER
	var gpR: float = gpW - GP_MARGIN_OTHER
	var gpB: float = gpH - GP_MARGIN_OTHER
	draw_rect(Rect2(gpL, gpT, gpR - gpL, gpB - gpT), GP_INK, false, GP_W_FRAME)
	_gpDrawTitleBlock(gpR, gpB)


# Draw the 180x50 mm title block anchored to the inner frame's bottom-right corner.
# 绘制贴在内框右下角的 180×50mm 标题栏。
# [param gpR] inner frame right edge (mm) / 内框右边界
# [param gpB] inner frame bottom edge (mm) / 内框下边界
func _gpDrawTitleBlock(gpR: float, gpB: float) -> void:
	var gpBW: float = GPSheet.GP_TB_BLOCK_W
	var gpBH: float = GPSheet.GP_TB_BLOCK_H
	var gpOX: float = gpR - gpBW
	if gpOX < GP_MARGIN_BIND:
		return
	# Block outline. / 图块外框。
	draw_rect(Rect2(gpOX, gpB - gpBH, gpBW, gpBH), GP_INK, false, GP_W_FRAME)
	var gpFont: Font = _gpFont()
	for gpF in GPSheet.GP_TB_FIELDS:
		var gpFX: float = float(gpF["x"])
		var gpFY: float = float(gpF["y"])
		var gpFW: float = float(gpF["w"])
		var gpFH: float = float(gpF["h"])
		# Field table Y grows upward from the block's bottom; world Y grows downward.
		# 字段表的 Y 自图块底边向上增长；世界坐标 Y 向下增长。
		var gpTop: float = gpB - gpFY - gpFH
		var gpLeft: float = gpOX + gpFX
		draw_rect(Rect2(gpLeft, gpTop, gpFW, gpFH), GP_INK_DIM, false, GP_W_GRID)
		var gpKey: String = str(gpF["key"])
		var gpCap: String = _gpTrBoth(str(gpF["cap"]))
		_gpDrawText(gpFont, Vector2(gpLeft + 1.2, gpTop + 3.0), gpCap, GP_CAPTION_MM, GP_INK_DIM)
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
	var gpX: float = gpLeft + 1.2
	if gpSheet.gpLabelMode == GPSheet.GP_LABEL_BOTH:
		# Stacked: Chinese above, English below. Each side degrades independently.
		# 上下叠显：中文在上、英文在下。两侧各自独立降级。
		if gpZh != "" and gpEn != "":
			_gpDrawText(gpFont, Vector2(gpX, gpTop + 6.4), gpZh, GP_VALUE_MM, GP_INK)
			_gpDrawText(gpFont, Vector2(gpX, gpTop + 9.4), gpEn, GP_VALUE_MM, GP_INK)
		elif gpZh != "":
			_gpDrawText(gpFont, Vector2(gpX, gpTop + gpFH * 0.72), gpZh, GP_VALUE_MM, GP_INK)
		else:
			_gpDrawText(gpFont, Vector2(gpX, gpTop + gpFH * 0.72), gpEn, GP_VALUE_MM, GP_INK)
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
	var gpMM: float = GP_VALUE_MM
	if gpKey == "drawing_title":
		gpMM = GPTextRole.GP_DRAWING_TITLE_MM
	_gpDrawText(gpFont, Vector2(gpX, gpTop + gpFH * 0.72), gpOne, gpMM, GP_INK)


# Font size for a given mm text height at the current canvas scale, as (integer size, residual) —
# hand BOTH to _gpDrawText; see GPCanvasText.gpFontFit for why the residual must not be dropped.
# The title block is a true-scale miniature of the sheet, so it takes NO legibility floor: a floor
# tall enough to help would make two stacked lines (3 mm baseline pitch) overlap.
# 给定毫米字高在当前画布缩放下的字号，形如（整数号, 残差）—— 两者都要交给 _gpDrawText；残差不可
# 丢弃的原因见 GPCanvasText.gpFontFit。标题栏是图纸的真实比例缩样，故**不取**可读性下限：任何足够
# 大的下限都会让基线间距仅 3mm 的上下两行重叠。
func gpFontFit(gpMM: float) -> Vector2:
	return GPCanvasText.gpExactFontFit(gpMM, _gpTextScale)


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
	draw_set_transform(Vector2.ZERO, 0.0, GPCanvasText.gpTextScale(gpFit, _gpTextScale))
	draw_string(gpFont, GPCanvasText.gpDrawPos(gpPosMM, gpFit, _gpTextScale), gpText,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(gpFit.x), gpCol)
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
