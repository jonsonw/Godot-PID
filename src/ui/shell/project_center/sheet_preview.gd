# Copyright 2026 G-PID Contributors. MIT License. See LICENSE.
class_name GPSheetPreview
extends Control

# Right-side sheet preview of the sheet manager (W13 T5). User feedback 2026-11-11: the first
# version drew an abstract OVERVIEW (one dot per node, one line per edge) — for a two-equipment
# sheet that reads as "just two dots". The thumbnail now eats THE SAME ENTITY MODEL as the
# DXF/PDF exporters (GPPrintModel.gpProject): frame, glyphs, pipes, annotations — a true
# miniature, and render/export/preview can never disagree about geometry again.
# 图纸管理器的右侧预览（W13 T5）。用户反馈 2026-11-11：首版画的是抽象**概览**（每节点一个
# 圆点、每条边一条直线）—— 两台设备的图纸看起来就是"两个点"。缩略图现在吃与 DXF/PDF
# 导出器**同一份实体模型**（GPPrintModel.gpProject）：图框、字形、管线、注释 —— 真实的
# 缩影，渲染/导出/预览从此不可能在几何上分家。
#
# WHY _draw AND NOT CHILD CONTROLS / 为何用 _draw 而非子控件：
# one paint pass over the cached entity list keeps refresh O(1) per selection and makes resize
# trivial (queue_redraw; entities are cached, only the mm->px mapping recomputes). No lambdas
# anywhere (R7) — the caption hook is a member function Callable, same pattern as gpDefsSnapshot.
# 对缓存实体列表的一次绘制让刷新在每次选中时 O(1)，缩放窗口只需 queue_redraw（实体已缓存，
# 仅重算 mm->px 映射）。全程零 lambda（R7）—— 图签字段钩子用成员函数 Callable，与
# gpDefsSnapshot 同一模式。
#
# Coding rule: every variable declares its type explicitly. / 编码规范：所有变量均显式声明类型。

# Per-layer ink (dark paper tuned). / 逐图层墨色（按深色纸面调校）。
const GP_INK: Dictionary = {
	GPPrintModel.GP_LAYER_FRAME: Color(0.42, 0.47, 0.55, 0.95),
	GPPrintModel.GP_LAYER_EQUIPMENT: Color(0.78, 0.86, 0.95, 1.0),
	GPPrintModel.GP_LAYER_PIPING: Color(0.55, 0.80, 0.65, 1.0),
	GPPrintModel.GP_LAYER_ANNOTATION: Color(0.62, 0.66, 0.72, 0.95),
}
const GP_INK_DEFAULT: Color = Color(0.7, 0.72, 0.75, 0.9)
# Equipment family colours for the list below (unchanged from T5).
# 下方清单的设备族配色（与 T5 一致）。
const GP_CODE_COLORS: Dictionary = {
	"PUMP": Color(0.45, 0.71, 1.00),
	"COLUMN": Color(0.36, 0.87, 0.75),
	"HEAT": Color(1.00, 0.66, 0.35),
	"VESSEL": Color(0.72, 0.58, 1.00),
	"TANK": Color(0.55, 0.85, 0.45),
}
const GP_NEUTRAL: Color = Color(0.62, 0.62, 0.62, 0.9)
# Text smaller than this on screen is unreadable mush — skip it (the glyph still shows where
# the annotation lives). / 屏幕上小于该高度的文字不可读 —— 跳过（字形仍标示注释位置）。
const GP_TEXT_MIN_PX: float = 4.0
# middle -> baseline conversion used by the file writers, mirrored for draw_string.
# 与文件写出器一致的「中高 -> 基线」换算，供 draw_string 镜像使用。
const GP_MIDDLE_TO_BASELINE: float = 0.35

# The sheet being previewed; null = empty state. / 正在预览的图纸；null = 空态。
var gpSheet: GPSheet = null

# Cached scan (stats + equipment list). / 缓存的扫描结果（统计行 + 设备清单）。
var gpCache: Dictionary = {}

# Cached projected entities (world mm, Y down) — rebuilt per selection, NOT per redraw.
# 缓存的投影实体（世界毫米、Y 向下）—— 每次选中重建，而非每次重绘。
var gpEntities: Array[Dictionary] = []

# Defs source, injected as a member Callable (no lambda, R7). The panel wires
# Callable(gpHost, "gpDefsSnapshot"); an unset provider degrades to an empty library (frame
# still projects, symbol-less nodes contribute nothing — the print/export contract).
# defs 来源，注入为成员 Callable（无 lambda，R7）。面板接 Callable(gpHost, "gpDefsSnapshot")；
# 未注入时降级为空库（图框仍投影、无 def 的节点不产出 —— 与打印/导出同一契约）。
var gpDefsProvider: Callable = Callable()


# Caption hook for the title block: resolve an i18n KEY through the autoload. Member function
# so it can be passed as a Callable without a lambda (R7).
# 图签字段钩子：经 autoload 解析 i18n **键**。成员函数，故能以 Callable 传入而无 lambda（R7）。
func _gpCaption(gpKey: String, gpFallback: String) -> String:
	return I18n.gpTr(gpKey)


# Project the sheet into print-model entities with the injected defs.
# 用注入的 defs 把图纸投影为打印模型实体。
func _gpProjectEntities() -> Array[Dictionary]:
	if gpSheet == null:
		var gpNone: Array[Dictionary] = []
		return gpNone
	var gpDefs: Array[GPSymbolDef] = []
	if gpDefsProvider.is_valid():
		var gpV: Variant = gpDefsProvider.call()
		if gpV is Array[GPSymbolDef]:
			gpDefs = gpV
	return GPPrintModel.gpProject(gpSheet, gpDefs, Callable(self, "_gpCaption"))


# Show one sheet: scan + project once, redraw. / 展示一张图纸：扫描 + 投影一次，重绘。
func gpShowSheet(gpNewSheet: GPSheet) -> void:
	gpSheet = gpNewSheet
	gpCache = GPEquipmentScan.gpScanSheet(gpSheet)
	gpEntities = _gpProjectEntities()
	queue_redraw()


func _ready() -> void:
	# ADR-48 (adaptive popups): the window is resizable, so the miniature must re-fit on every
	# resize — redraw against the new size; entities stay cached.
	# ADR-48（自适应弹窗）：弹窗可缩放，缩影必须随每次缩放重排 —— 按新尺寸重画；实体保持缓存。
	resized.connect(queue_redraw)


# Clear to the empty state. / 清空到空态。
func gpClear() -> void:
	gpShowSheet(null)


# Ink for one entity layer. / 某实体图层的墨色。
func _gpInk(gpLayer: String) -> Color:
	return Color(GP_INK.get(gpLayer, GP_INK_DEFAULT))


# Draw one text entity (or skip it as unreadable). / 绘制一个文字实体（不可读则跳过）。
func _gpText(gpE: Dictionary, gpRect: Rect2, gpPxMM: float, gpFont: Font, gpFontSz: int) -> void:
	var gpHpx: float = float(gpE.get("h", 0.0)) * gpPxMM
	if gpHpx < GP_TEXT_MIN_PX:
		return
	var gpAt: Vector2 = gpE.get("at", Vector2.ZERO) as Vector2
	var gpP: Vector2 = gpRect.position + gpAt * gpPxMM
	var gpFs: int = maxi(int(round(gpHpx)), 4)
	var gpBaseY: float = gpP.y
	if str(gpE.get("valign", "")) == GPPrintModel.GP_VALIGN_MIDDLE:
		gpBaseY = gpP.y + gpHpx * GP_MIDDLE_TO_BASELINE
	var gpAlign: String = str(gpE.get("align", "l"))
	var gpS: String = str(gpE.get("s", ""))
	if gpS.is_empty():
		return
	var gpInk: Color = _gpInk(str(gpE.get("layer", "")))
	# The text box is bounded by the paper on the far side of the anchor, so alignment lands
	# exactly where the file writers put it.
	# 文字盒以锚点远端纸边为界，对齐落点与文件写出器完全一致。
	if gpAlign == "c":
		var gpHalf: float = minf(gpP.x - gpRect.position.x, gpRect.end.x - gpP.x)
		if gpHalf < 8.0:
			return
		draw_string(gpFont, Vector2(gpP.x - gpHalf, gpBaseY), gpS,
			HORIZONTAL_ALIGNMENT_CENTER, gpHalf * 2.0, gpFs, gpInk)
	elif gpAlign == "r":
		var gpW: float = gpP.x - gpRect.position.x
		if gpW < 8.0:
			return
		draw_string(gpFont, Vector2(gpRect.position.x, gpBaseY), gpS,
			HORIZONTAL_ALIGNMENT_RIGHT, gpW, gpFs, gpInk)
	else:
		var gpW2: float = gpRect.end.x - gpP.x
		if gpW2 < 8.0:
			return
		draw_string(gpFont, gpP + Vector2(0, 0), gpS, HORIZONTAL_ALIGNMENT_LEFT, gpW2, gpFs, gpInk)


func _draw() -> void:
	var gpFont: Font = get_theme_default_font()
	var gpFontSz: int = get_theme_default_font_size()
	var gpFg: Color = get_theme_color("font_color", "Label")
	var gpDim: Color = Color(gpFg.r, gpFg.g, gpFg.b, 0.65)
	if gpSheet == null or not bool(gpCache.get("ok", false)):
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0), false)
		var gpEmpty: String = I18n.gpTr("pv.empty")
		if gpFont != null:
			draw_string(gpFont, Vector2(16, 24 + gpFontSz), gpEmpty,
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, gpFontSz, gpDim)
		return
	# Paper rect: keep the sheet's aspect, fit inside the control with a margin. The mapping is
	# now FIXED sheet mm -> preview px (a true miniature of the whole sheet), no node-extent
	# zooming — what you see spans exactly the paper.
	# 纸面矩形：保持图幅纵横比，带边距放入控件。映射是**固定**的图幅毫米 -> 预览像素
	#（整张图纸的真实缩影），不再按节点范围缩放 —— 所见即整张纸。
	var gpMargin: float = 14.0
	var gpAvail: Vector2 = size - Vector2(gpMargin * 2.0, gpMargin * 2.0)
	var gpAspect: Vector2 = Vector2(gpSheet.gpWidthMM, gpSheet.gpHeightMM)
	var gpScale: float = minf(gpAvail.x / maxf(gpAspect.x, 1.0),
		gpAvail.y / maxf(gpAspect.y, 1.0))
	var gpPaper: Vector2 = gpAspect * gpScale
	var gpRect: Rect2 = Rect2(Vector2(gpMargin, gpMargin), gpPaper)
	draw_rect(gpRect, Color(0.10, 0.11, 0.13), true)
	draw_rect(gpRect, Color(0.45, 0.5, 0.58), false, 1.5)
	var gpPxMM: float = gpPaper.x / maxf(gpAspect.x, 1.0)
	# Entities in print order (frame under equipment under piping under annotations) — the SAME
	# sequence the DXF/PDF writers pour.
	# 实体按打印顺序（图框在下、设备居中、管线在上、注释最上）—— 与 DXF/PDF 写出器灌注的
	# 同一顺序。
	for gpE in gpEntities:
		var gpOp: String = str(gpE.get("op", ""))
		var gpInk: Color = _gpInk(str(gpE.get("layer", "")))
		if gpOp == GPPrintModel.GP_OP_LINE:
			var gpA: Vector2 = gpRect.position + (gpE.get("a", Vector2.ZERO) as Vector2) * gpPxMM
			var gpB: Vector2 = gpRect.position + (gpE.get("b", Vector2.ZERO) as Vector2) * gpPxMM
			draw_line(gpA, gpB, gpInk, maxf(float(gpE.get("w", 0.35)) * gpPxMM, 1.0), true)
		elif gpOp == GPPrintModel.GP_OP_POLY:
			var gpSrc: PackedVector2Array = gpE.get("pts", PackedVector2Array()) as PackedVector2Array
			if gpSrc.size() < 2:
				continue
			var gpPts: PackedVector2Array = PackedVector2Array()
			for gpP in gpSrc:
				gpPts.append(gpRect.position + gpP * gpPxMM)
			if bool(gpE.get("closed", false)):
				gpPts.append(gpPts[0])
			draw_polyline(gpPts, gpInk, maxf(float(gpE.get("w", 0.35)) * gpPxMM, 1.0), true)
		elif gpOp == GPPrintModel.GP_OP_CIRCLE:
			var gpC: Vector2 = gpRect.position + (gpE.get("c", Vector2.ZERO) as Vector2) * gpPxMM
			var gpR: float = float(gpE.get("r", 0.0)) * gpPxMM
			if gpR < 0.75:
				continue
			draw_arc(gpC, gpR, 0.0, TAU, 48, gpInk,
				maxf(float(gpE.get("w", 0.35)) * gpPxMM, 1.0), true)
		elif gpOp == GPPrintModel.GP_OP_TEXT:
			if gpFont != null:
				_gpText(gpE, gpRect, gpPxMM, gpFont, gpFontSz)
	# Header: sheet title above the paper (the real title block now lives INSIDE the drawing).
	# 页眉：图纸名画在纸面上方（真实图签如今已在图纸内部）。
	var gpTitle: String = str(gpCache.get("sheet_name", ""))
	var gpNum: String = str(gpCache.get("sheet_number", ""))
	if not gpNum.is_empty():
		gpTitle += "  ·  " + gpNum
	if gpFont != null and not gpTitle.is_empty():
		draw_string(gpFont, Vector2(gpMargin, maxf(gpRect.position.y - 4.0, gpFontSz)),
			gpTitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - gpMargin * 2.0, gpFontSz, gpFg)
	# Stats line + major equipment list below the paper. / 纸面下方：统计行 + 主要设备清单。
	var gpStats: String = I18n.gpTr("pv.stats") % [int(gpCache.get("node_count", 0)),
		int(gpCache.get("edge_count", 0))]
	var gpY: float = gpRect.end.y + 16.0
	if gpFont != null:
		draw_string(gpFont, Vector2(gpMargin, gpY + gpFontSz), gpStats,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - gpMargin * 2.0, gpFontSz, gpDim)
		gpY += gpFontSz + 8.0
		draw_string(gpFont, Vector2(gpMargin, gpY + gpFontSz), I18n.gpTr("pv.equipment"),
			HORIZONTAL_ALIGNMENT_LEFT, size.x - gpMargin * 2.0, gpFontSz, gpFg)
		gpY += gpFontSz + 4.0
	var gpEquip: Array = gpCache.get("equipment", []) as Array
	if gpEquip.is_empty():
		if gpFont != null:
			draw_string(gpFont, Vector2(gpMargin, gpY + gpFontSz), I18n.gpTr("pv.none_equipment"),
				HORIZONTAL_ALIGNMENT_LEFT, size.x - gpMargin * 2.0, gpFontSz, gpDim)
		return
	# Two columns if the list is long. / 清单长时排两列。
	var gpPerCol: int = maxi(ceili(float(gpEquip.size()) / 2.0), 1)
	for gpI: int in gpEquip.size():
		var gpRowY: float = gpY + float(gpI % gpPerCol) * (float(gpFontSz) + 4.0)
		var gpColX: float = gpMargin if gpI < gpPerCol else gpMargin + gpRect.size.x * 0.5
		var gpEntry: Dictionary = gpEquip[gpI] as Dictionary
		var gpDot: Color = Color(GP_CODE_COLORS.get(str(gpEntry.get("code", "")), GP_NEUTRAL))
		draw_circle(Vector2(gpColX + 5.0, gpRowY + gpFontSz * 0.62), 3.5, gpDot)
		if gpFont != null:
			var gpLabel: String = I18n.gpTr(str(gpEntry.get("label_key", "")))
			var gpTag: String = str(gpEntry.get("tag", ""))
			var gpLine: String = gpLabel + ("  " + gpTag if not gpTag.is_empty() else "")
			draw_string(gpFont, Vector2(gpColX + 14.0, gpRowY + gpFontSz), gpLine,
				HORIZONTAL_ALIGNMENT_LEFT, gpRect.size.x * 0.5 - 16.0, gpFontSz, gpFg)
