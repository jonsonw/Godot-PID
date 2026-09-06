class_name GPSymbolNormalizer
extends RefCounted

# Copyright © 2026 Jonson Wang
# Turns a raw author-space glyph draft into a canonical GPSymbolDef.
# 把作者空间的原始字形草稿转换为规范化的 GPSymbolDef。
# This is the single place where "how a hand-drawn glyph becomes a library symbol" is decided,
# so the symbol editor, the SVG generator and any future importer all agree.
# 这里是「手绘字形如何变成图元库符号」的唯一决策点，确保图元编辑器、SVG 生成器与
# 未来的任何导入器保持一致。
# Model layer only: no UI, no autoload, headless-testable.
# 纯模型层：不依赖 UI、不依赖 autoload，可 headless 测试。
# See 符号编辑器设计说明 §6 / §7.
# 见《符号编辑器设计说明》§6 / §7。
#
# Draft shape / 草稿结构:
#   {
#     "id": String, "display_name": String,
#     "shapes": {"paths": [{"pts": [[x, y], ...], "closed": bool}],
#                "circles": [{"c": [x, y], "r": float}],
#                "rects": [{"pos": [x, y], "size": [w, h]}]},
#     "ports": [{"name": String, "pos": [x, y], "dir": [dx, dy]}],   # author-space pixels
#     "attrs_schema": Dictionary
#   }

# Author-space coordinates are arbitrary; only their relative geometry matters.
# 作者空间坐标是任意的，只有相对几何关系有意义。
const GP_UNIT_BOX: float = 100.0

# Center of the 100x100 unit box.
# 100x100 单位框的中心。
const GP_UNIT_CENTER: Vector2 = Vector2(50.0, 50.0)


# Normalize one raw draft into a canonical symbol definition.
# 将一份原始草稿归一化为规范化的图元定义。
# [param gpRaw] Author-space draft (see the module header).
# [param gpRaw] 作者空间草稿（见文件头说明）。
# [param gpCat] Target category; drives the nominal envelope and the fallback ports.
# [param gpCat] 目标类别；决定标称包络与兜底端口。
# [param gpPackSizes] Optional pack-level {category: Vector2} envelope override.
# [param gpPackSizes] 可选的图元包级 {类别: Vector2} 包络覆盖表。
static func gpNormalizeSymbol(gpRaw: Dictionary, gpCat: String, gpPackSizes: Dictionary = {}) -> GPSymbolDef:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = str(gpRaw.get("id", ""))
	gpDef.gpDisplayName = str(gpRaw.get("display_name", gpDef.gpId))
	gpDef.gpCategory = gpCat
	gpDef.gpAttrsSchema = (gpRaw.get("attrs_schema", {}) as Dictionary).duplicate(true)

	# (1) Nominal envelope comes from the category, never from the drawing — that is what makes
	# every member of a family render equal-sized.
	# (1) 标称包络取自类别而非图形本身 —— 这正是同族图元恒为等大的原因。
	var gpEnv: Vector2 = GPSymbolCategories.gpSizeFor(gpCat, gpPackSizes)
	gpDef.gpDefaultSize = gpEnv

	var gpShapes: Dictionary = gpRaw.get("shapes", {}) as Dictionary
	var gpBBox: Rect2 = gpComputeBBox(gpShapes)
	var gpRawPorts: Array = gpRaw.get("ports", [])

	if gpBBox.size.x <= 0.0 and gpBBox.size.y <= 0.0:
		# Nothing was drawn: keep an empty shape so the renderer falls back to a plain rectangle.
		# 未绘制任何图形：保留空形状，渲染层回退为纯矩形。
		gpDef.gpShapes = []
		gpDef.gpPorts = GPPortSpec.gpFromDicts(GPSymbolCategories.gpStandardPorts(gpCat))
		return gpDef

	# (2) Uniform fit into the 100x100 unit box, centered. Uniform (not per-axis) scaling is
	# what keeps a flat valve flat and a tall tank tall.
	# (2) 均匀缩放塞入 100x100 单位框并居中。均匀（而非按轴）缩放才能让扁阀门仍扁、高储罐仍高。
	var gpS: float = gpUnitScale(gpBBox)
	var gpCtr: Vector2 = gpBBox.get_center()
	gpDef.gpShapes = GPShapeSpec.gpFromSpec(_gpTransformShapes(gpShapes, gpS, gpCtr))

	# (3) Ports: author-placed ports go through the SAME geometry as the glyph, expressed as
	# 0..1 of the nominal envelope. Otherwise fall back to the category standard anchors.
	# (3) 端口：作者放置的端口与字形走同一套几何变换，并以标称包络的 0..1 表达；
	#     否则回退为类别标准锚点。
	if gpRawPorts.is_empty():
		gpDef.gpPorts = GPPortSpec.gpFromDicts(GPSymbolCategories.gpStandardPorts(gpCat))
	else:
		gpDef.gpPorts = GPPortSpec.gpFromDicts(gpNormalizePorts(gpRawPorts, gpBBox, gpEnv))
	return gpDef


# Reverse of gpNormalizeSymbol: rebuild an author-space draft from a canonical GPSymbolDef.
# gpNormalizeSymbol 的逆操作：从规范化 GPSymbolDef 重建作者空间草稿。
# Normalization keeps only RELATIVE geometry (the author bbox is discarded), so the
# reconstructed author frame is chosen as the unit box itself — center (50,50), bbox equal to
# the def's own unit-space bbox. With GP_FIT_MARGIN = 1.0 this makes
# gpNormalizeSymbol(gpDenormalizeSymbol(def)) reproduce def's unit coords and 0..1 ports
# EXACTLY (within the 0.01 snapping already applied), so the glyph editor round-trips a
# hand-edited symbol without drift.
# 归一化只保留「相对几何」（作者包围盒被丢弃），故重建的作者框架直接取单位框本身——
# 中心 (50,50)、包围盒等于 def 自身的单位空间包围盒。在 GP_FIT_MARGIN = 1.0 下，
# gpNormalizeSymbol(gpDenormalizeSymbol(def)) 会精确还原 def 的单位坐标与 0..1 端口
# （已含 0.01 量化），使图元编辑器对字形的往返编辑无漂移。
# [param gpDef] Canonical symbol definition (unit-box gpShape, 0..1 ports, envelope size).
# [param gpDef] 规范化图元定义（单位框 gpShape、0..1 端口、包络尺寸）。
# Returns a draft dict in the same shape as gpNormalizeSymbol's input (module header),
# or an empty-shape draft with no ports when the def carries no geometry (forward re-derives
# the category standard ports on the next normalize).
# 返回与 gpNormalizeSymbol 输入同构的草稿字典；当 def 无几何时返回空形状草稿（下次归一化
# 会重新推导类别标准端口）。
static func gpDenormalizeSymbol(gpDef: GPSymbolDef) -> Dictionary:
	var gpCat: String = gpDef.gpCategory
	var gpEnv: Vector2 = gpDef.gpDefaultSize

	# Mirror the forward "nothing drawn" branch: empty geometry -> empty draft (ports re-derived).
	# Check the def's typed editable shapes directly (NOT the lossy flattened gpShapeSpec() render
	# spec) — the forward empty branch sets gpShapes = [], so is_empty() is the exact inverse.
	# 与正向「未绘制」分支对齐：空几何 → 空草稿（端口由下次归一化重新推导）。
	# 直接检查 def 的类型化可编辑形状（而非打平的 gpShapeSpec() 渲染 spec）——正向空分支把
	# gpShapes 置为 []，故 is_empty() 是精确的逆条件。
	if gpDef.gpShapes.is_empty():
		return {
			"id": gpDef.gpId,
			"display_name": gpDef.gpDisplayName,
			"category": gpCat,
			"shapes": {},
			"ports": [],
			"attrs_schema": gpDef.gpAttrsSchema.duplicate(true),
		}

	# Author space == unit box: the def's unit-frame shapes ARE the author pixels
	# (scale-invariant frame). gpEditSpec() derives a LOSSLESS editable spec (raw control
	# points + Bézier handles, NOT the flattened render spec), so editing a curved symbol via
	# the Make-Symbol dialog preserves its curve control points on re-normalize.
	# 作者空间 = 单位框：def 的单位框形状即作者像素（缩放无关框架）。gpEditSpec() 派生出**无损可编辑**
	# 规格（原始控制点 + 贝塞尔手柄，而非打平的渲染 spec），使经「生成图元」对话框编辑曲线图元时，
	# 重归一化仍保留其曲线控制点。
	var gpSpec: Dictionary = GPShapeSpec.gpEditSpec(gpDef.gpShapes)
	# Bbox for port re-derivation, computed on the same lossless editable spec so the round-trip
	# stays exact with what a later gpNormalizeSymbol would compute from this draft.
	# 供端口还原的包围盒，基于同一无损可编辑 spec 计算，使往返与后续 gpNormalizeSymbol 从该草稿
	# 重算的结果精确一致。
	var gpBBox: Rect2 = gpComputeBBox(gpSpec)
	return {
		"id": gpDef.gpId,
		"display_name": gpDef.gpDisplayName,
		"category": gpCat,
		"shapes": gpSpec,
		"ports": gpDenormalizePorts(GPPortSpec.gpToDicts(gpDef.gpPorts), gpBBox, gpEnv),
		"attrs_schema": gpDef.gpAttrsSchema.duplicate(true),
	}


# Inverse of gpNormalizePorts: map 0..1 envelope ports back to author-space pixels.
# gpNormalizePorts 的逆：把 0..1 包络端口还原为作者空间像素。
# Forward: nx = 0.5 + (abs.x - ctr.x) * SEff / envW,  with ctr = bbox.center (= 50 in unit frame).
# 正向：nx = 0.5 + (abs.x - ctr.x) * SEff / envW，单位框下 ctr = bbox.center（= 50）。
# Inverse: abs.x = 50 + (nx - 0.5) * envW / SEff   (and likewise for y).
# 逆向：abs.x = 50 + (nx - 0.5) * envW / SEff（y 同理）。
# SEff uses the SAME gpComputeBBox(gpShape) the forward pass recomputes on re-normalize, so the
# round-trip is exact (the denormalized shape is the unit coords copied verbatim).
# SEff 用与正向一致的 gpComputeBBox(gpShape)（重归一化时会从草稿形状重新算出），
# 因此往返精确（反归一化的形状即原样复制的单位坐标）。
#
# Why the centre is gpBBox.get_center() and not the literal 50.0 / 为何用包围盒中心而非字面 50.0：
# the literal was a hidden ASSUMPTION that gpBBox is a unit-frame box (centre 50,50). That holds
# for gpDenormalizeSymbol (its shapes are already unit-frame), but NOT for the Make-Symbol
# dialog, which denormalizes ports over a freshly drawn, arbitrarily placed author bbox. Writing
# the general form removes the assumption without changing gpDenormalizeSymbol's behaviour —
# for a unit-frame box the centre is 50 anyway, and the 0.01 snapping absorbs the fp residue.
# 字面量 50.0 隐含假设了 gpBBox 是单位框（中心 50,50）。该假设对 gpDenormalizeSymbol 成立
# （其形状已是单位框），但对「生成图元」对话框不成立——后者要在刚绘制、位置任意的作者包围盒上
# 反归一化端口。写成一般形式去掉了这一假设，且不改变 gpDenormalizeSymbol 的行为：对单位框而言
# 中心本就是 50，0.01 量化亦会吸收浮点残差。
static func gpDenormalizePorts(gpPorts: Array, gpBBox: Rect2, gpEnv: Vector2) -> Array:
	var gpSEff: float = gpEnvelopeScale(gpBBox, gpEnv)
	if gpSEff <= 0.0:
		gpSEff = 1.0
	var gpEnvW: float = maxf(gpEnv.x, 0.001)
	var gpEnvH: float = maxf(gpEnv.y, 0.001)
	var gpCtr: Vector2 = gpBBox.get_center()
	var gpOut: Array = []
	for gpI in range(gpPorts.size()):
		var gpP: Dictionary = gpPorts[gpI] as Dictionary
		var gpPos: Array = gpP.get("pos", [0.5, 0.5])
		var gpNx: float = float(gpPos[0])
		var gpNy: float = float(gpPos[1])
		gpOut.append({
			"name": str(gpP.get("name", "p%d" % (gpI + 1))),
			"pos": [
				snappedf(gpCtr.x + (gpNx - 0.5) * gpEnvW / gpSEff, 0.01),
				snappedf(gpCtr.y + (gpNy - 0.5) * gpEnvH / gpSEff, 0.01),
			],
			"dir": gpP.get("dir", gpEdgeNormal(Vector2(gpNx, gpNy))),
		})
	return gpOut


# Uniform author-space -> unit-box scale factor.
# 作者空间 → 单位框的均匀缩放系数。
static func gpUnitScale(gpBBox: Rect2) -> float:
	var gpBw: float = maxf(gpBBox.size.x, 0.001)
	var gpBh: float = maxf(gpBBox.size.y, 0.001)
	return minf(GP_UNIT_BOX / gpBw, GP_UNIT_BOX / gpBh) * GPSymbolCategories.GP_FIT_MARGIN


# Effective author-space -> canvas-pixel scale once the glyph is rendered inside the envelope.
# 字形在包络内渲染后，作者空间 → 画布像素的有效缩放系数。
# The intermediate unit-box scale and the fit margin cancel out, so this is simply
# min(env.x / bboxW, env.y / bboxH) — the same factor GPSymbolPainter ends up applying.
# 中间的单位框缩放与留边系数相互抵消，故它就是 min(env.x / bboxW, env.y / bboxH)，
# 与 GPSymbolPainter 最终施加的系数一致。
static func gpEnvelopeScale(gpBBox: Rect2, gpEnv: Vector2) -> float:
	var gpBw: float = maxf(gpBBox.size.x, 0.001)
	var gpBh: float = maxf(gpBBox.size.y, 0.001)
	return minf(gpEnv.x / gpBw, gpEnv.y / gpBh)


# Convert author-space ports into envelope-normalized 0..1 ports.
# 将作者空间端口换算为相对包络归一化的 0..1 端口。
static func gpNormalizePorts(gpRawPorts: Array, gpBBox: Rect2, gpEnv: Vector2) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	var gpSEff: float = gpEnvelopeScale(gpBBox, gpEnv)
	var gpCtr: Vector2 = gpBBox.get_center()
	var gpEnvW: float = maxf(gpEnv.x, 0.001)
	var gpEnvH: float = maxf(gpEnv.y, 0.001)
	for gpI in range(gpRawPorts.size()):
		var gpP: Dictionary = gpRawPorts[gpI] as Dictionary
		var gpPos: Array = gpP.get("pos", [0.0, 0.0])
		var gpAbs: Vector2 = Vector2(float(gpPos[0]), float(gpPos[1]))
		var gpNx: float = 0.5 + (gpAbs.x - gpCtr.x) * gpSEff / gpEnvW
		var gpNy: float = 0.5 + (gpAbs.y - gpCtr.y) * gpSEff / gpEnvH
		var gpName: String = str(gpP.get("name", "p%d" % (gpI + 1)))
		gpOut.append({
			"name": gpName,
			"pos": [snappedf(gpNx, 0.0001), snappedf(gpNy, 0.0001)],
			"dir": gpEdgeNormal(Vector2(gpNx, gpNy)),
		})
	return gpOut


# Snap a normalized port to the nearest envelope edge and return that outward normal.
# 把归一化端口吸附到最近的包络边，并返回该向外法线。
static func gpEdgeNormal(gpNorm: Vector2) -> Array:
	var gpDx: float = minf(gpNorm.x, 1.0 - gpNorm.x)
	var gpDy: float = minf(gpNorm.y, 1.0 - gpNorm.y)
	if gpDx <= gpDy:
		return [-1, 0] if gpNorm.x <= 0.5 else [1, 0]
	return [0, -1] if gpNorm.y <= 0.5 else [0, 1]


# Compute the axis-aligned bounding box of every primitive in an author-space shape dict.
# 计算作者空间形状字典中所有图元原语的轴对齐包围盒。
# Returns a zero-sized Rect2 when the dict holds no geometry.
# 当字典内无任何几何时返回零尺寸 Rect2。
static func gpComputeBBox(gpShapes: Dictionary) -> Rect2:
	var gpHas: bool = false
	var gpMinX: float = 0.0
	var gpMinY: float = 0.0
	var gpMaxX: float = 0.0
	var gpMaxY: float = 0.0

	for gpP in gpShapes.get("paths", []):
		for gpPt in (gpP as Dictionary).get("pts", []):
			var gpX: float = float(gpPt[0])
			var gpY: float = float(gpPt[1])
			if not gpHas:
				gpMinX = gpX
				gpMaxX = gpX
				gpMinY = gpY
				gpMaxY = gpY
				gpHas = true
			else:
				gpMinX = minf(gpMinX, gpX)
				gpMaxX = maxf(gpMaxX, gpX)
				gpMinY = minf(gpMinY, gpY)
				gpMaxY = maxf(gpMaxY, gpY)

	for gpC in gpShapes.get("circles", []):
		var gpCd: Dictionary = gpC as Dictionary
		var gpCx: float = float(gpCd["c"][0])
		var gpCy: float = float(gpCd["c"][1])
		var gpR: float = absf(float(gpCd["r"]))
		if not gpHas:
			gpMinX = gpCx - gpR
			gpMaxX = gpCx + gpR
			gpMinY = gpCy - gpR
			gpMaxY = gpCy + gpR
			gpHas = true
		else:
			gpMinX = minf(gpMinX, gpCx - gpR)
			gpMaxX = maxf(gpMaxX, gpCx + gpR)
			gpMinY = minf(gpMinY, gpCy - gpR)
			gpMaxY = maxf(gpMaxY, gpCy + gpR)

	for gpRd in gpShapes.get("rects", []):
		var gpRr: Dictionary = gpRd as Dictionary
		var gpRx: float = float(gpRr["pos"][0])
		var gpRy: float = float(gpRr["pos"][1])
		var gpRw: float = float(gpRr["size"][0])
		var gpRh: float = float(gpRr["size"][1])
		if not gpHas:
			gpMinX = minf(gpRx, gpRx + gpRw)
			gpMaxX = maxf(gpRx, gpRx + gpRw)
			gpMinY = minf(gpRy, gpRy + gpRh)
			gpMaxY = maxf(gpRy, gpRy + gpRh)
			gpHas = true
		else:
			gpMinX = minf(gpMinX, minf(gpRx, gpRx + gpRw))
			gpMaxX = maxf(gpMaxX, maxf(gpRx, gpRx + gpRw))
			gpMinY = minf(gpMinY, minf(gpRy, gpRy + gpRh))
			gpMaxY = maxf(gpMaxY, maxf(gpRy, gpRy + gpRh))

	if not gpHas:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	return Rect2(Vector2(gpMinX, gpMinY), Vector2(gpMaxX - gpMinX, gpMaxY - gpMinY))


# Internal: map every primitive into the 100x100 unit box and stamp the resulting bbox as "box".
# 内部：把所有图元原语映射到 100x100 单位框，并把结果包围盒写入 "box"。
static func _gpTransformShapes(gpShapes: Dictionary, gpS: float, gpCtr: Vector2) -> Dictionary:
	var gpPaths: Array = []
	for gpP in gpShapes.get("paths", []):
		var gpPd: Dictionary = gpP as Dictionary
		var gpPts: Array = gpPd.get("pts", [])
		if gpPts.size() < 2:
			continue
		var gpNew: Array = []
		for gpPt in gpPts:
			gpNew.append(_gpToUnit(Vector2(float(gpPt[0]), float(gpPt[1])), gpS, gpCtr))
		var gpPdOut: Dictionary = {"pts": gpNew, "closed": bool(gpPd.get("closed", false))}
		# Bézier handles are RELATIVE offsets from each vertex, so uniform scaling + translation
		# during normalization leave them unchanged — carry them through verbatim so a curved
		# spline keeps its curve after being made into a symbol (was flattened to a polyline).
		# 贝塞尔手柄是「相对各顶点的偏移」，归一化的等比缩放与平移不改变它 —— 原样透传，
		# 使弯成弧线的样条在生成图元后仍是曲线（此前被展平成折线）。
		if gpPd.has("handles"):
			gpPdOut["handles"] = gpPd["handles"]
		gpPaths.append(gpPdOut)

	var gpCircles: Array = []
	for gpC in gpShapes.get("circles", []):
		var gpCd: Dictionary = gpC as Dictionary
		var gpCc: Vector2 = Vector2(float(gpCd["c"][0]), float(gpCd["c"][1]))
		gpCircles.append({
			"c": _gpToUnit(gpCc, gpS, gpCtr),
			"r": snappedf(absf(float(gpCd["r"])) * gpS, 0.01),
		})

	var gpRects: Array = []
	for gpRd in gpShapes.get("rects", []):
		var gpRr: Dictionary = gpRd as Dictionary
		var gpRp: Vector2 = Vector2(float(gpRr["pos"][0]), float(gpRr["pos"][1]))
		var gpRs: Vector2 = Vector2(float(gpRr["size"][0]), float(gpRr["size"][1]))
		# Normalize to a positive-size rectangle before transforming.
		# 变换前先规整为正尺寸矩形。
		var gpAbsRect: Rect2 = Rect2(gpRp, gpRs).abs()
		gpRects.append({
			"pos": _gpToUnit(gpAbsRect.position, gpS, gpCtr),
			"size": [snappedf(gpAbsRect.size.x * gpS, 0.01), snappedf(gpAbsRect.size.y * gpS, 0.01)],
		})

	var gpOut: Dictionary = {"paths": gpPaths, "circles": gpCircles, "rects": gpRects}
	var gpBox: Rect2 = gpComputeBBox(gpOut)
	gpOut["box"] = [
		snappedf(gpBox.position.x, 0.01),
		snappedf(gpBox.position.y, 0.01),
		snappedf(gpBox.size.x, 0.01),
		snappedf(gpBox.size.y, 0.01),
	]
	return gpOut


# Internal: map one author-space point into the unit box.
# 内部：把一个作者空间点映射到单位框。
static func _gpToUnit(gpPt: Vector2, gpS: float, gpCtr: Vector2) -> Array:
	var gpU: Vector2 = (gpPt - gpCtr) * gpS + GP_UNIT_CENTER
	return [snappedf(gpU.x, 0.01), snappedf(gpU.y, 0.01)]
