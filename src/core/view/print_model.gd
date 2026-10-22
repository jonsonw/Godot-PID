class_name GPPrintModel
extends RefCounted
# Copyright © 2026 Jonson Wang
# Print model: project a whole sheet into a flat list of graphic ENTITIES (lines, polylines,
# circles, texts) in paper millimetres — the single source both the DXF and the PDF exporters
# pour into their file formats.
# 打印模型：把整张图纸投影为一份**图形实体**平面列表（线、折线、圆、文字），单位纸面毫米
# —— DXF 与 PDF 两个导出器共同灌注的唯一来源。
#
# WHY A MODEL BETWEEN SHEET AND FILE / 为何在图纸与文件之间加一层模型：
# "render and export must eat the same geometry" started as the renderer↔hit-test rule and
# now extends to export: if the DXF writer recomputed the frame, or the PDF writer re-derived
# the pipe polylines, each copy would drift the way every duplicated judgment in this project
# has. So the exporters do NO geometry at all — they translate entities into file syntax.
# 「渲染与导出必须吃同一份几何」起初是渲染↔命中的规则，现在推广到导出：DXF 写出器若自行重算
# 图框、PDF 写出器若自行重推管线折线，每份副本都会像本项目里每一次重复判断那样分家。
# 故导出器**不做任何几何** —— 它们只把实体翻译成文件语法。
#
# SOURCES (all PURE, all shared with the live renderers) / 数据源（全部纯函数、与实时渲染器共享）：
# - frame furnishings: GPFrameGeometry (trim / frame / zone ruler / title-block placement)
# - title-block layout: GPSheet.GP_TB_FIELDS x gpFrameScale, same formula GPFrameView draws
# - symbol glyphs: GPSymbolPainter.gpUnitBox + gpFitScale (the unit-box mapping)
# - mounted frames: GPMountResolver.gpWorldTransform (world transform never stored)
# - pipes: GPPortResolver.gpResolveEnd x2 -> GPEdgeRoute.gpRoute (recomputed like every frame)
# - annotations: GPShape.gpRenderPoints (world mm already) and the GENERATOR registry
# - tag placement: GPLabelPlacement (the core copy of the ui-side pure functions)
#
# COORDINATES / 坐标系：
# every entity is in WORLD millimetres, Y DOWN (the Godot convention). The DXF and PDF writers
# each flip Y into their own file convention — the model must not guess which file it feeds.
# 每个实体均为世界毫米、Y 向下（Godot 惯例）。DXF 与 PDF 写出器各自翻转到自身文件约定
# —— 模型不猜测自己在喂谁。
#
# KNOWN v1 DEVIATIONS FROM THE SCREEN RENDER / v1 相对屏幕渲染的已知偏差：
# - the user's symbol font-size SETTING is not consulted (the in-line tier constant is used);
#   the setting is an autoload and this model must stay headless-testable.
# - text baselines are approximated (no font metrics here): a text entity's "at" is the
#   reference point of a MIDDLE-height line, and the writers refine per format.
# - 不读用户的图元字号设置项（用在管档常量）；该设置是 autoload，而本模型必须保持
#   headless 可测。文字基线为近似（此处无字体度量）：text 实体的 "at" 是行中高的参考点，
#   由写出器按各自格式精化。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# ---- entity ops / 实体算子 ----
const GP_OP_LINE: String = "line"        # {"op","a","b","w","layer"}
const GP_OP_POLY: String = "poly"        # {"op","pts","closed","w","layer"}
const GP_OP_CIRCLE: String = "circle"    # {"op","c","r","w","layer"}
const GP_OP_TEXT: String = "text"        # {"op","at","s","h","align","valign","layer"}

# Text vertical reference. FRAME text (zone labels, title block) is authored on its BASELINE;
# symbol tags, generator notes and grid cells are authored on their MIDDLE line (the canvas
# centres the text box on the anchor). The two must not be conflated: the PDF/DXF writers add
# the middle->baseline conversion only for "middle".
# 文字纵向基准。图框文字（坐标带、图签）以**基线**编排；位号、生成器备注与表格格子以
# **行中高**编排（画布把文字盒中心放在锚点上）。二者不可混为一谈：PDF/DXF 写出器只对
# "middle" 施加「中高 → 基线」的换算。
const GP_VALIGN_BASELINE: String = "baseline"
const GP_VALIGN_MIDDLE: String = "middle"

# ---- DXF layer names / DXF 图层名 ----
const GP_LAYER_FRAME: String = "FRAME"
const GP_LAYER_EQUIPMENT: String = "EQUIPMENT"
const GP_LAYER_PIPING: String = "PIPING"
const GP_LAYER_ANNOTATION: String = "ANNOTATION"

# ---- line weights (mm, ISO 128) / 线宽（mm，依 ISO 128） ----
# Frame weights mirror GPFrameView's constants (kept in a test, not a cross-class const).
# 图框线宽与 GPFrameView 的常量同值（由测试维持单一来源，而非跨类常量引用）。
const GP_W_TRIM: float = 0.25
const GP_W_FRAME: float = 0.70
const GP_W_GRID: float = 0.18
const GP_W_BODY: float = 0.35

# Title-block text tiers, mirroring GPFrameView (single source kept by test).
# 图签字高档，与 GPFrameView 同值（单一来源由测试维持）。
const GP_CAPTION_MM: float = 2.5
const GP_VALUE_MM: float = 2.5

# Fallback symbol size, same as GPSymbolView's. / 图元默认尺寸回落，与 GPSymbolView 相同。
const GP_DEFAULT_SIZE: Vector2 = Vector2(64.0, 48.0)


# Project the whole sheet. The defs array is the live library; a node whose symbol vanished
# contributes NOTHING (same contract as the equipment list — an exportable row needs a schema).
# gpCaption resolves a title-block caption i18n KEY into display text — injected because the
# key table lives in the I18n autoload, which core may never reference. The UI layer binds
# I18n's bilingual lookup; an unset/invalid callable degrades to the raw key, exactly the
# fallback GPFrameView uses when the autoload is absent.
# 投影整张图纸。defs 为活动图元库；图元已消失的节点**不产出**任何东西
#（与设备清单同一契约 —— 可导出的行需要 schema）。
# gpCaption 把图签字段的 i18n **键**解析为显示文字 —— 以**注入**传入，因为键表住在
# I18n autoload 里，而 core 绝不引用 autoload。界面层绑定 I18n 的双语查询；
# 未传/无效的 callable 回退为裸键 —— 与 GPFrameView 在 autoload 缺席时的回退一致。
static func gpProject(gpSheet: GPSheet, gpDefs: Array[GPSymbolDef],
		gpCaption: Callable = Callable()) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpSheet == null:
		return gpOut
	var gpLookup: Callable = func(gpId: String) -> GPSymbolDef:
		return GPPropertyResolver.gpDefById(gpDefs, gpId)
	gpFrameEntities(gpSheet, gpCaption, gpOut)
	if gpSheet.gpGraph != null:
		gpSymbolEntities(gpSheet.gpGraph, gpLookup, gpOut)
		gpEdgeEntities(gpSheet.gpGraph, gpLookup, gpOut)
		gpShapeEntities(gpSheet.gpGraph, gpOut)
	return gpOut


# ---------------------------------------------------------------------------
# Frame furnishings / 图框陈设
# ---------------------------------------------------------------------------
# Every rectangle comes from GPFrameGeometry — the SAME module the renderer and the hit-test
# read, so a moved or resized sheet projects exactly as it displays.
# 每个矩形都取自 GPFrameGeometry —— 渲染器与命中判定读取的**同一模块**，
# 故被移动/缩放过的图纸投影即其显示。
static func gpFrameEntities(gpSheet: GPSheet, gpCaption: Callable,
		gpOut: Array[Dictionary]) -> void:
	if not gpSheet.gpFrameOn:
		return
	var gpFS: float = gpSheet.gpFrameScale()
	# Trim line (裁边线) then the drawing frame (图框), thin under thick.
	# 先裁边线再内图框，细线在粗线之下。
	gpPushRect(gpOut, GPFrameGeometry.gpTrimRect(gpSheet), GP_W_TRIM * gpFS, GP_LAYER_FRAME)
	gpPushRect(gpOut, GPFrameGeometry.gpFrameRect(gpSheet), GP_W_FRAME * gpFS, GP_LAYER_FRAME)
	# Zone ruler: ticks, centring arrows, labels (centred on their position).
	# 坐标带：刻度、对中箭头、标号（在自身位置上居中）。
	var gpGridW: float = GP_W_GRID * gpFS
	for gpSeg in GPFrameGeometry.gpZoneTicks(gpSheet):
		gpPushLine(gpOut, gpSeg[0] as Vector2, gpSeg[1] as Vector2, gpGridW, GP_LAYER_FRAME)
	for gpSeg in GPFrameGeometry.gpZoneArrows(gpSheet):
		gpPushLine(gpOut, gpSeg[0] as Vector2, gpSeg[1] as Vector2, gpGridW, GP_LAYER_FRAME)
	var gpLabelMM: float = GPTextRole.GP_FRAME_GRID_MM * gpFS
	for gpLabel in GPFrameGeometry.gpZoneLabels(gpSheet, gpLabelMM):
		gpPushText(gpOut, gpLabel["at"] as Vector2, str(gpLabel["text"]), gpLabelMM,
			"c", GP_LAYER_FRAME)
	# Title block. / 图签。
	gpTitleBlockEntities(gpSheet, gpCaption, gpFS, gpOut)


# Title block: outline + the GP_TB_FIELDS cell grid + caption/value texts, using the SAME
# A3-era layout table and the SAME base-relative Y-up arithmetic GPFrameView draws with.
# 图签：外框 + GP_TB_FIELDS 格网 + 字段名/值文字 —— 使用与 GPFrameView 绘制时**同一份**
# A3 时代版式表与同一套「自底向上」的 Y 轴算术。
static func gpTitleBlockEntities(gpSheet: GPSheet, gpCaption: Callable, gpFS: float,
		gpOut: Array[Dictionary]) -> void:
	var gpBlock: Rect2 = GPFrameGeometry.gpTitleBlockPlaced(
		GPFrameGeometry.gpFrameRect(gpSheet), gpSheet)
	gpPushRect(gpOut, gpBlock, GP_W_FRAME * gpFS, GP_LAYER_FRAME)
	var gpB: float = gpBlock.end.y
	var gpOX: float = gpBlock.position.x
	for gpF in GPSheet.GP_TB_FIELDS:
		var gpFW: float = float(gpF["w"]) * gpFS
		var gpFH: float = float(gpF["h"]) * gpFS
		# Field-table Y grows upward from the block's bottom; world Y grows downward.
		# 字段表的 Y 自图块底边向上增长；世界坐标 Y 向下增长。
		var gpTop: float = gpB - float(gpF["y"]) * gpFS - gpFH
		var gpLeft: float = gpOX + float(gpF["x"]) * gpFS
		gpPushRect(gpOut, Rect2(Vector2(gpLeft, gpTop), Vector2(gpFW, gpFH)),
			GP_W_GRID * gpFS, GP_LAYER_FRAME)
		# Caption at the top-left padding pair (1.2 / 3.0 mm, same A3-era layout).
		# 字段名在左上内边距对（1.2 / 3.0mm，同一份 A3 时代版式）。
		gpPushText(gpOut, Vector2(gpLeft + 1.2 * gpFS, gpTop + 3.0 * gpFS),
			_gpCaptionText(gpCaption, str(gpF["cap"])), GP_CAPTION_MM * gpFS,
			"l", GP_LAYER_FRAME)
		gpTitleBlockValue(gpSheet, str(gpF["key"]), gpLeft, gpTop, gpFW, gpFH, gpFS, gpOut)


# Resolve one caption key through the injected callable; an unset or invalid one degrades to
# the raw key (GPFrameView's own autoload-absent fallback).
# 经注入的 callable 解析一个字段名键；未传或无效时回退为裸键
#（GPFrameView 自身在 autoload 缺席时的回退）。
static func _gpCaptionText(gpCaption: Callable, gpKey: String) -> String:
	if gpCaption.is_valid():
		return str(gpCaption.call(gpKey, gpKey))
	return gpKey


# One field's value: one line in single-language mode, two stacked lines in BOTH mode.
# Mirrors GPFrameView._gpDrawValue's positions and its independent per-side degradation.
# 某字段的值：单语模式一行，BOTH 模式上下两行。镜像 GPFrameView._gpDrawValue 的
# 位置与「两侧各自独立降级」。
static func gpTitleBlockValue(gpSheet: GPSheet, gpKey: String, gpLeft: float, gpTop: float,
		gpFW: float, gpFH: float, gpFS: float, gpOut: Array[Dictionary]) -> void:
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
	var gpX: float = gpLeft + 1.2 * gpFS
	if gpSheet.gpLabelMode == GPSheet.GP_LABEL_BOTH:
		if gpZh != "" and gpEn != "":
			gpPushText(gpOut, Vector2(gpX, gpTop + 6.4 * gpFS), gpZh, GP_VALUE_MM * gpFS,
				"l", GP_LAYER_FRAME)
			gpPushText(gpOut, Vector2(gpX, gpTop + 9.4 * gpFS), gpEn, GP_VALUE_MM * gpFS,
				"l", GP_LAYER_FRAME)
		elif gpZh != "":
			gpPushText(gpOut, Vector2(gpX, gpTop + gpFH * 0.72), gpZh, GP_VALUE_MM * gpFS,
				"l", GP_LAYER_FRAME)
		else:
			gpPushText(gpOut, Vector2(gpX, gpTop + gpFH * 0.72), gpEn, GP_VALUE_MM * gpFS,
				"l", GP_LAYER_FRAME)
		return
	var gpOne: String = gpEn if gpSheet.gpLabelMode == GPSheet.GP_LABEL_EN else gpZh
	if gpOne == "":
		gpOne = gpZh if gpSheet.gpLabelMode == GPSheet.GP_LABEL_EN else gpEn
	if gpOne == "":
		return
	var gpMM: float = GP_VALUE_MM * gpFS
	if gpKey == "drawing_title":
		gpMM = GPTextRole.GP_DRAWING_TITLE_MM * gpFS
	gpPushText(gpOut, Vector2(gpX, gpTop + gpFH * 0.72), gpOne, gpMM, "l", GP_LAYER_FRAME)


# ---------------------------------------------------------------------------
# Symbols / 图元
# ---------------------------------------------------------------------------
static func gpSymbolEntities(gpGraph: GPPIDGraph, gpLookup: Callable,
		gpOut: Array[Dictionary]) -> void:
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		gpOneSymbol(gpGraph, gpLookup, gpN, gpOut)


# One node: glyph (static spec or generator spec) + generator texts/cells + the tag.
# 单个节点：字形（静态规格或生成器规格）+ 生成器文字/格子 + 位号。
static func gpOneSymbol(gpGraph: GPPIDGraph, gpLookup: Callable, gpNode: GPPIDNode,
		gpOut: Array[Dictionary]) -> void:
	var gpDef: GPSymbolDef = gpLookup.call(gpNode.gpSymbolId) as GPSymbolDef
	if gpDef == null:
		return
	# World transform NEVER stored — derived from the mount chain (ADR-23 family).
	# 世界变换**永不存储** —— 由挂载父链推导（ADR-23 家族）。
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpGraph, gpLookup, gpNode)
	var gpSize: Vector2 = GPLabelPlacement.gpEnvelope(gpDef)
	var gpSpec: Dictionary = {}
	var gpGen: Dictionary = {}
	if GPSymbolGeneratorRegistry.gpIsGenerator(gpDef.gpGeometrySource):
		gpGen = GPSymbolGeneratorRegistry.gpGenerate(gpDef, gpNode)
		gpSpec = gpGen.get("spec", {}) as Dictionary
	elif not gpDef.gpShapes.is_empty():
		gpSpec = gpDef.gpShapeSpec()
	gpGlyphEntities(gpSpec, gpSize, gpWT, gpOut)
	gpGeneratorTexts(gpGen, gpNode, gpSize, gpWT, gpOut)
	gpTagEntity(gpNode, gpDef, gpWT, gpOut)


# Map one glyph spec from its OWN box into the node's frame, then into the world. Static
# symbols use a 0..100 unit box; the grid generator emits envelope-mm paths with an
# envelope-sized box. The painter's algebra is scale-agnostic, so both go through the same
# gpUnitBox + gpFitScale pair — no per-generator special case.
# 把一份字形规格从**它自己的** box 映射进节点坐标系，再映射到世界。静态图元用 0..100 单位框；
# grid 生成器产出包络毫米路径与包络大小的 box。painter 的代数与尺度无关，故两者都走同一对
# gpUnitBox + gpFitScale —— 没有逐生成器特判。
static func gpGlyphEntities(gpSpec: Dictionary, gpSize: Vector2, gpWT: Dictionary,
		gpOut: Array[Dictionary]) -> void:
	if gpSpec.is_empty():
		return
	var gpBox: Rect2 = GPSymbolPainter.gpUnitBox(gpSpec)
	var gpK: float = GPSymbolPainter.gpFitScale(gpBox, gpSize)
	var gpBoxCtr: Vector2 = gpBox.get_center()
	# The envelope is Rect2(-size/2, size) in the body frame (see GPSymbolView.gpDrawBody),
	# so the mapping CENTRE is the local ORIGIN, not half the size.
	# 包络在 body 坐标系中是 Rect2(-size/2, size)（见 GPSymbolView.gpDrawBody），
	# 故映射**中心**是本地原点，而非半尺寸。
	var gpCtr: Vector2 = Vector2.ZERO
	for gpP in gpSpec.get("paths", []):
		var gpPts: Array = (gpP as Dictionary).get("pts", [])
		if gpPts.is_empty():
			continue
		var gpWorldPts: PackedVector2Array = PackedVector2Array()
		for gpPt in gpPts:
			gpWorldPts.append(_gpToWorld(
				gpCtr + (Vector2(float(gpPt[0]), float(gpPt[1])) - gpBoxCtr) * gpK, gpWT))
		gpPushPoly(gpOut, gpWorldPts, false, GP_W_BODY, GP_LAYER_EQUIPMENT)
	for gpC in gpSpec.get("circles", []):
		var gpCen: Vector2 = gpCtr + (Vector2(float(gpC["c"][0]), float(gpC["c"][1])) - gpBoxCtr) * gpK
		# A uniform scale keeps circles circles; the world transform only moves the centre.
		# 均匀缩放使圆恒为圆；世界变换只移动圆心。
		gpPushCircle(gpOut, _gpToWorld(gpCen, gpWT), float(gpC["r"]) * gpK,
			GP_W_BODY, GP_LAYER_EQUIPMENT)
	for gpRd in gpSpec.get("rects", []):
		var gpPos: Vector2 = gpCtr + (Vector2(float(gpRd["pos"][0]), float(gpRd["pos"][1])) - gpBoxCtr) * gpK
		var gpR: Rect2 = Rect2(gpPos, Vector2(float(gpRd["size"][0]), float(gpRd["size"][1])) * gpK)
		gpPushPoly(gpOut, _gpRectPts(gpR, gpWT), true, GP_W_BODY, GP_LAYER_EQUIPMENT)
	for gpA in gpSpec.get("arcs", []):
		var gpAC: Vector2 = gpCtr + (Vector2(float(gpA["c"][0]), float(gpA["c"][1])) - gpBoxCtr) * gpK
		gpPushPoly(gpOut, _gpArcPts(gpAC, float(gpA["r"]) * gpK,
			float(gpA["a0"]), float(gpA["a1"]), gpWT), false, GP_W_BODY, GP_LAYER_EQUIPMENT)


# Generator text lines: centred in the envelope, pitch 1.5x the sheet height — the SAME
# layout _gpDrawTextLines paints, expressed as centred text entities.
# 生成器文字行：包络内居中、行距为图面字高 1.5 倍 —— 与 _gpDrawTextLines 画出的
# 同一版式，表达为居中文字实体。
static func gpGeneratorTexts(gpGen: Dictionary, gpNode: GPPIDNode, gpSize: Vector2,
		gpWT: Dictionary, gpOut: Array[Dictionary]) -> void:
	if gpGen.is_empty():
		return
	var gpLines: PackedStringArray = gpGen.get("text_lines", PackedStringArray()) as PackedStringArray
	if not gpLines.is_empty():
		# GPTextRole's mirrored tier (the render layer's GPSymbolView keeps its own literal;
		# a test pins the two equal — core may not reference render).
		# GPTextRole 的镜像档（render 层的 GPSymbolView 保留自己的字面量；由测试钉住二者
		# 相等 —— core 不能引用 render）。
		var gpMM: float = GPTextRole.GP_INLINE_TAG_MM * GPTextRole.GP_ANNOTATE_SCALE
		var gpPitch: float = gpMM * 1.5
		var gpTotal: float = gpPitch * gpLines.size()
		# Centred on the envelope centre = the local origin (same rect as the renderer's).
		# 以包络中心 = 本地原点为中心（与渲染器同一矩形）。
		var gpCx: float = 0.0
		var gpTop: float = -gpTotal * 0.5
		for gpI in range(gpLines.size()):
			var gpLine: String = gpLines[gpI]
			if gpLine.strip_edges() == "":
				continue
			# "at" is the CENTRE of this line's pitch cell, horizontally centred.
			# "at" 是本行行距单元的**中心**，水平居中。
			gpPushText(gpOut, _gpToWorld(Vector2(gpCx, gpTop + gpPitch * (float(gpI) + 0.5)), gpWT),
				gpLine, gpMM, "c", GP_LAYER_ANNOTATION, GP_VALIGN_MIDDLE)
	# Grid cells: the SAME cell rects the hit-test and the editor consume (local mm); the text
	# lives in the node's props under the CELL KEY (the stage-3 contract), left-aligned with
	# the 1 mm padding and the row-clamped height.
	# 表格格子：与命中测试、编辑器消费的**同一份**格子矩形（本地 mm）；文字按**格子键**
	# 存于节点 props（阶段 3 契约），左对齐、1mm 内边距、行高钳制的字高。
	var gpCells: Array = gpGen.get("cells", []) as Array
	for gpCell in gpCells:
		var gpR: Rect2 = gpCell["rect"] as Rect2
		var gpS: String = str(gpNode.gpProps.get(str(gpCell["key"]), ""))
		if gpS.strip_edges() == "":
			continue
		var gpMM: float = minf(GPTextRole.GP_CELL_TEXT_MM, gpR.size.y * 0.62)
		gpPushText(gpOut, _gpToWorld(gpR.position + Vector2(1.0, gpR.size.y * 0.5), gpWT),
			gpS, gpMM, "l", GP_LAYER_ANNOTATION, GP_VALIGN_MIDDLE)


# The tag: placed by the SAME pure placement the canvas uses, oriented flip-then-rotate
# like every symbol-local offset, then pushed into the world.
# 位号：由画布所用的**同一**纯定位函数放置，与所有图元本地偏移一样先翻转后旋转，
# 再推入世界。
static func gpTagEntity(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpWT: Dictionary,
		gpOut: Array[Dictionary]) -> void:
	var gpText: String = GPLabelPlacement.gpLabelText(gpNode, gpDef)
	if gpText == "":
		return
	var gpOff: Vector2 = GPLabelPlacement.gpLocalOffset(gpNode, gpDef)
	if bool(gpWT["flipped"]):
		gpOff.x = -gpOff.x
	gpOff = gpOff.rotated(deg_to_rad(float(gpWT["rot_deg"])))
	var gpAt: Vector2 = (gpWT["origin"] as Vector2) + gpOff
	# The canvas places the text BOX CENTRE on this anchor (gpDrawOrigin + gpTextOrigin), and
	# hangs a GP_LEFT tag to the left / a GP_RIGHT tag to the right. Reproducing only the anchor
	# point (the old code) left every tag shifted right by ~half its width. The alignment and the
	# middle baseline are therefore part of the projection contract, not writer cosmetics.
	# 画布把这个锚点当作文字**盒中心**（gpDrawOrigin + gpTextOrigin），并让 GP_LEFT 标签向
	# 左悬挂、GP_RIGHT 向右悬挂。旧代码只复现锚点，导致每个位号整体右移约半个字宽。故对齐
	# 方式与行中高基线属于投影契约的一部分，而不是写出器的装饰。
	gpPushText(gpOut, gpAt, gpText,
		GPTextRole.gpTagMM(gpDef.gpCategory, GPTextRole.GP_INLINE_TAG_MM),
		_gpAlignForAnchor(GPLabelPlacement.gpEffectiveAnchor(gpNode, gpDef)),
		GP_LAYER_ANNOTATION, GP_VALIGN_MIDDLE)


# Horizontal alignment for a tag anchor: a LEFT tag hangs off the left edge (right-aligned),
# a RIGHT tag starts at the right edge (left-aligned), every other anchor is centred.
# 位号锚点的水平对齐：LEFT 标签向左悬挂（右对齐）、RIGHT 标签从右缘起排（左对齐），其余居中。
static func _gpAlignForAnchor(gpAnchor: int) -> String:
	match gpAnchor:
		GPLabelAnchor.GPAnchor.GP_LEFT:
			return "r"
		GPLabelAnchor.GPAnchor.GP_RIGHT:
			return "l"
	return "c"


# ---------------------------------------------------------------------------
# Pipes / 管线
# ---------------------------------------------------------------------------
# Ends recomputed from the port refs, route recomputed from those ends — exactly what the
# edge layer paints every frame, and therefore what a moved symbol projects.
# 端点由端口引用重算、布线由端点重算 —— 与连线层每帧画出的完全一致，
# 故被移动过的图元投影亦随之而动。
static func gpEdgeEntities(gpGraph: GPPIDGraph, gpLookup: Callable,
		gpOut: Array[Dictionary]) -> void:
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		var gpWant: String = GPPortResolver.gpWantTypeFor(gpE)
		var gpFrom: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpLookup, gpE, true, gpWant)
		var gpTo: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpLookup, gpE, false, gpWant)
		var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(gpFrom, gpTo, gpE.gpRouting, gpE.gpOrtho)
		if gpPts.size() < 2:
			continue
		gpPushPoly(gpOut, gpPts, false, GP_W_BODY, GP_LAYER_PIPING)


# ---------------------------------------------------------------------------
# Free annotation shapes / 自由注释图形
# ---------------------------------------------------------------------------
# Shape points already live in world millimetres (see the canvas overlay); polylines and
# arcs are sampled through the SHARED sampler so the projection matches the painter.
# 图形顶点本就以世界毫米存储（见画布叠加层）；折线与圆弧经**共享**采样器取点，
# 使投影与绘制一致。
static func gpShapeEntities(gpGraph: GPPIDGraph, gpOut: Array[Dictionary]) -> void:
	for gpS in gpGraph.gpShapes:
		if gpS == null:
			continue
		var gpLayer: String = gpS.gpLayer if gpS.gpLayer != "" else GP_LAYER_ANNOTATION
		match gpS.gpKind:
			GPShape.GPKind.GP_LINE:
				if gpS.gpPoints.size() >= 2:
					gpPushLine(gpOut, gpS.gpPoints[0], gpS.gpPoints[1], GP_W_BODY, gpLayer)
			GPShape.GPKind.GP_CIRCLE:
				if gpS.gpPoints.size() >= 1:
					gpPushCircle(gpOut, gpS.gpPoints[0], gpS.gpRadius, GP_W_BODY, gpLayer)
			GPShape.GPKind.GP_RECT:
				if gpS.gpPoints.size() >= 2:
					gpPushPoly(gpOut, _gpRectPts(
						Rect2(gpS.gpPoints[0], (gpS.gpPoints[1] - gpS.gpPoints[0]).abs()),
						{"origin": Vector2.ZERO, "rot_deg": 0.0, "flipped": false}),
						true, GP_W_BODY, gpLayer)
			_:
				# POLYLINE and ARC sample through the shared renderer (Bézier-aware).
				# 折线与圆弧经共享渲染器采样（感知贝塞尔）。
				var gpSamp: PackedVector2Array = GPGeometry.gpRenderPoints(gpS, 8)
				if gpS.gpClosed and gpSamp.size() >= 2:
					gpSamp.append(gpSamp[0])
				if gpSamp.size() >= 2:
					gpPushPoly(gpOut, gpSamp, false, GP_W_BODY, gpLayer)


# ---------------------------------------------------------------------------
# entity helpers / 实体辅助
# ---------------------------------------------------------------------------

# Apply a world transform to a symbol-local point: flip x, then rotate, then translate —
# the same order GPMountResolver's frame algebra and GPSymbolView._gpOriented use.
# 对图元本地点施加世界变换：先翻转 x，再旋转，再平移 —— 与 GPMountResolver 的
# 坐标系代数及 GPSymbolView._gpOriented 同一顺序。
static func _gpToWorld(gpLocal: Vector2, gpWT: Dictionary) -> Vector2:
	var gpP: Vector2 = gpLocal
	if bool(gpWT["flipped"]):
		gpP.x = -gpP.x
	return gpP.rotated(deg_to_rad(float(gpWT["rot_deg"]))) + (gpWT["origin"] as Vector2)


# Rectangle corners as a closed polyline, through the world transform (a rotated rect is a
# parallelogram of points, not a rect op).
# 矩形四角输出为闭合折线，经世界变换（旋转后的矩形是点的平行四边形，不再是 rect 实体）。
static func _gpRectPts(gpR: Rect2, gpWT: Dictionary) -> PackedVector2Array:
	return PackedVector2Array([
		_gpToWorld(gpR.position, gpWT),
		_gpToWorld(gpR.position + Vector2(gpR.size.x, 0.0), gpWT),
		_gpToWorld(gpR.end, gpWT),
		_gpToWorld(gpR.position + Vector2(0.0, gpR.size.y), gpWT),
	])


# Arc sampled as a minor CCW sweep, 32 segments — the painter's own polygonalisation.
# 圆弧按劣弧/逆时针扫掠采样为 32 段 —— 绘制器自身的多边形化方式。
static func _gpArcPts(gpCen: Vector2, gpR: float, gpA0: float, gpA1: float,
		gpWT: Dictionary) -> PackedVector2Array:
	var gpDelta: float = fposmod(gpA1 - gpA0, TAU)
	var gpOut: PackedVector2Array = PackedVector2Array()
	for gpI in range(33):
		var gpAng: float = gpA0 + gpDelta * (float(gpI) / 32.0)
		gpOut.append(_gpToWorld(gpCen + Vector2(cos(gpAng), sin(gpAng)) * gpR, gpWT))
	return gpOut


static func gpPushLine(gpOut: Array[Dictionary], gpA: Vector2, gpB: Vector2,
		gpW: float, gpLayer: String) -> void:
	gpOut.append({"op": GP_OP_LINE, "a": gpA, "b": gpB, "w": gpW, "layer": gpLayer})


static func gpPushPoly(gpOut: Array[Dictionary], gpPts: PackedVector2Array, gpClosed: bool,
		gpW: float, gpLayer: String) -> void:
	gpOut.append({"op": GP_OP_POLY, "pts": gpPts, "closed": gpClosed, "w": gpW, "layer": gpLayer})


static func gpPushRect(gpOut: Array[Dictionary], gpR: Rect2, gpW: float, gpLayer: String) -> void:
	gpOut.append({"op": GP_OP_POLY, "closed": true, "w": gpW, "layer": gpLayer,
		"pts": PackedVector2Array([gpR.position,
			gpR.position + Vector2(gpR.size.x, 0.0), gpR.end,
			gpR.position + Vector2(0.0, gpR.size.y)])})


static func gpPushCircle(gpOut: Array[Dictionary], gpC: Vector2, gpR: float,
		gpW: float, gpLayer: String) -> void:
	gpOut.append({"op": GP_OP_CIRCLE, "c": gpC, "r": gpR, "w": gpW, "layer": gpLayer})


# align:  "l"/"c"/"r" = gpAt is the LEFT end / horizontal CENTRE / RIGHT end.
# valign: "baseline" = gpAt lies ON the baseline (frame text); "middle" = gpAt is the middle
#         of the line box (tags / generator notes / grid cells).
# align： "l"/"c"/"r" = gpAt 是**左端 / 水平中心 / 右端**。
# valign："baseline" = gpAt 落在**基线**上（图框文字）；"middle" = gpAt 是行盒**中高**（位号 /
#         生成器备注 / 表格格子）。
static func gpPushText(gpOut: Array[Dictionary], gpAt: Vector2, gpS: String, gpH: float,
		gpAlign: String, gpLayer: String, gpValign: String = GP_VALIGN_BASELINE) -> void:
	gpOut.append({"op": GP_OP_TEXT, "at": gpAt, "s": gpS, "h": gpH, "align": gpAlign,
		"valign": gpValign, "layer": gpLayer})
