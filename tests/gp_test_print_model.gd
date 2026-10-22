extends "res://tests/gp_test.gd"
# Print model: a sheet must project into entities whose geometry is IDENTICAL to what the
# live renderers draw — the frame asks GPFrameGeometry, the glyph mapping asks
# GPSymbolPainter's algebra, the pipes recompute GPEdgeRoute, the tag reuses the placement
# the canvas uses. An exporter that re-derived any of these would be a second copy of a
# judgment this project has already watched drift.
# 打印模型：图纸必须投影为与实时渲染器**完全一致**的实体几何 —— 图框问 GPFrameGeometry、
# 字形映射用 GPSymbolPainter 的代数、管线重算 GPEdgeRoute、位号复用画布的定位。
# 导出器若自行重推其中任何一项，就是本项目已多次目睹分家的「同一判断的第二份副本」。

const GP_SQ: float = 100.0


# ---- helpers / 辅助构造 ----

func _gpLineShape(gpPts: Array[Vector2], gpClosed: bool = false) -> GPShape:
	return GPShape.gpPolyline(gpPts, gpClosed)


# A bare sheet: frame OFF and the graph ATTACHED — the projection reads the graph THROUGH
# the sheet (the same route DEXPI takes), so a graph that never lands on the sheet projects
# nothing. This helper exists because both facts were learned the hard way below.
# 一张「素」图纸：图框关闭且图**挂在 sheet 上** —— 投影经 sheet 读图（与 DEXPI 同一路径），
# 没落到 sheet 上的图什么也不投影。此辅助的存在正是因为下面两个事实都吃过亏。
func _gpBareSheet(gpGraph: GPPIDGraph) -> GPSheet:
	var gpSheet := GPSheet.new()
	gpSheet.gpFrameOn = false
	gpSheet.gpGraph = gpGraph
	return gpSheet


func _gpGlyphDef(gpIdVal: String, gpCat: String) -> GPSymbolDef:
	var d := GPSymbolDef.new()
	d.gpId = gpIdVal
	d.gpCategory = gpCat
	d.gpDisplayName = gpIdVal
	# A unit-space square spanning the whole 0..100 box, so the mapping is exactly size/100.
	# 一个铺满 0..100 单位框的正方形，使映射恰为 size/100。
	var gpSq: Array[Vector2] = [Vector2(0, 0), Vector2(GP_SQ, 0), Vector2(GP_SQ, GP_SQ),
		Vector2(0, GP_SQ)]
	d.gpShapes.append(_gpLineShape(gpSq, true))
	d.gpDefaultSize = Vector2(50.0, 50.0)
	return d


func _gpPortedDef(gpIdVal: String) -> GPSymbolDef:
	var d := _gpGlyphDef(gpIdVal, "pump")
	d.gpPorts.append(GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE))
	d.gpPorts.append(GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE))
	return d


func _gpNodeIn(gpGraph: GPPIDGraph, gpIdVal: String, gpTag: String, gpSymbolId: String,
		gpPos: Vector2) -> GPPIDNode:
	var n := GPPIDNode.new()
	n.gpInstanceId = gpIdVal
	n.gpTag = gpTag
	n.gpSymbolId = gpSymbolId
	n.gpPosition = gpPos
	gpGraph.gpNodes.append(n)
	return n


func _gpPolys(gpOut: Array[Dictionary]) -> Array[Dictionary]:
	var gpRes: Array[Dictionary] = []
	for gpE in gpOut:
		if str(gpE["op"]) == GPPrintModel.GP_OP_POLY:
			gpRes.append(gpE)
	return gpRes


func _gpTexts(gpOut: Array[Dictionary]) -> Array[Dictionary]:
	var gpRes: Array[Dictionary] = []
	for gpE in gpOut:
		if str(gpE["op"]) == GPPrintModel.GP_OP_TEXT:
			gpRes.append(gpE)
	return gpRes


func _gpLayers(gpOut: Array[Dictionary]) -> Array[String]:
	var gpSeen: Dictionary = {}
	for gpE in gpOut:
		gpSeen[str(gpE["layer"])] = true
	var gpOutL: Array[String] = []
	for gpK in gpSeen.keys():
		gpOutL.append(str(gpK))
	return gpOutL


# ---- 1. null sheet projects nothing / 空图纸不投影 ----

func gpTestNullSheetYieldsNothing() -> void:
	var gpDefs: Array[GPSymbolDef] = []
	gpEq(GPPrintModel.gpProject(null, gpDefs).size(), 0, "a null sheet projects nothing")


# ---- 2. the frame asks GPFrameGeometry / 图框几何问同一模块 ----

func gpTestFrameMatchesGeometryModule() -> void:
	var gpSheet := GPSheet.new()
	gpSheet.gpName = "S"
	gpSheet.gpWidthMM = 420.0
	gpSheet.gpHeightMM = 297.0
	var gpDefs: Array[GPSymbolDef] = []
	var gpOut: Array[Dictionary] = GPPrintModel.gpProject(gpSheet, gpDefs)
	# The frame rectangle appears as a CLOSED poly whose corners are exactly gpFrameRect's.
	# 图框矩形以**闭合**折线出现，四角恰为 gpFrameRect 的四角。
	var gpWant: Rect2 = GPFrameGeometry.gpFrameRect(gpSheet)
	var gpFound := false
	for gpE in _gpPolys(gpOut):
		var gpPts: PackedVector2Array = gpE["pts"] as PackedVector2Array
		if gpPts.size() == 4 and bool(gpE["closed"]) \
				and gpPts[0].is_equal_approx(gpWant.position) \
				and gpPts[2].is_equal_approx(gpWant.end):
			gpFound = true
	gpCheck(gpFound, "the frame poly is gpFrameRect's own four corners")
	# Zone ruler counts match the geometry module's lists exactly.
	# 坐标带数量与几何模块的列表**精确**相等。
	gpEq(GPPrintModel.gpProject(gpSheet, gpDefs).filter(
		func(gpE: Dictionary) -> bool:
			return str(gpE["op"]) == GPPrintModel.GP_OP_LINE).size(),
		GPFrameGeometry.gpZoneTicks(gpSheet).size() + GPFrameGeometry.gpZoneArrows(gpSheet).size(),
		"line entities = ticks + arrows, from the same module")
	# Layers of frame-only output are FRAME only. / 纯图框产出的图层只有 FRAME。
	var gpLayers: Array[String] = _gpLayers(gpOut)
	gpEq(gpLayers.size(), 1, "one layer on a bare sheet")
	gpEq(gpLayers[0], GPPrintModel.GP_LAYER_FRAME, "and it is FRAME")


# ---- 3. the title block uses the injected caption + the sheet's values / 图签用注入的字段名与图纸取值 ----

func gpTestTitleBlockProjectsCaptionsAndValues() -> void:
	var gpSheet := GPSheet.new()
	gpSheet.gpName = "S"
	gpSheet.gpWidthMM = 420.0
	gpSheet.gpHeightMM = 297.0
	gpSheet.gpTitleBlock["drawing_title"] = {"value": {"zh": "解毒系统", "en": "Detox"}}
	var gpCaptions: Array[String] = []
	var gpDefs: Array[GPSymbolDef] = []
	var gpOut: Array[Dictionary] = GPPrintModel.gpProject(gpSheet, gpDefs,
		func(gpKey: String, gpFallback: String) -> String:
			gpCaptions.append(gpKey)
			return "CAP:" + gpKey)
	var gpTexts := _gpTexts(gpOut)
	# The caption callable saw the field keys. / 字段名 callable 收到了字段键。
	gpCheck(gpCaptions.has("frame.fld.drawing_title"), "the caption callable saw the field key")
	var gpGotCap := false
	var gpGotVal := false
	for gpT in gpTexts:
		if str(gpT["s"]) == "CAP:frame.fld.drawing_title":
			gpGotCap = true
		if str(gpT["s"]) == "解毒系统":
			gpGotVal = true
	gpCheck(gpGotCap, "the caption text carries the resolver's answer")
	gpCheck(gpGotVal, "the drawing title's zh value is projected")
	# No callable -> the raw key falls through, GPFrameView's own autoload-absent fallback.
	# 无 callable -> 落回裸键，与 GPFrameView 在 autoload 缺席时的回退一致。
	var gpBare: Array[Dictionary] = GPPrintModel.gpProject(gpSheet, gpDefs)
	var gpGotRaw := false
	for gpT in _gpTexts(gpBare):
		if str(gpT["s"]) == "frame.fld.drawing_title":
			gpGotRaw = true
	gpCheck(gpGotRaw, "without a resolver the caption degrades to the raw key")


# ---- 4. a glyph maps through GPSymbolPainter's algebra / 字形经 GPSymbolPainter 的代数映射 ----

func gpTestGlyphMapsAndRotates() -> void:
	var gpDef := _gpGlyphDef("GPUMP001", "pump")
	var gpGraph := GPPIDGraph.new()
	# Rotated 90°: local +x becomes world +y (Y is DOWN, so rotation turns x onto +y).
	# 旋转 90°：本地 +x 变为世界 +y（Y 向下，旋转把 x 转到 +y）。
	var gpNode := _gpNodeIn(gpGraph, "n1", "P-1001", "GPUMP001", Vector2(200.0, 300.0))
	gpNode.gpRotationDeg = 90.0
	var gpDefs: Array[GPSymbolDef] = [gpDef]
	var gpOut: Array[Dictionary] = GPPrintModel.gpProject(_gpBareSheet(gpGraph), gpDefs)
	# The glyph is the sheet's only EQUIPMENT poly (a closed spec path still travels as an
	# open polyline — the painter draws polylines and fills nothing, and the model mirrors
	# that: "closed" lives in the SHAPE, not in the spec paths).
	# 字形是图面上唯一的 EQUIPMENT 折线（闭合的 spec 路径仍以**开放**折线旅行 —— 渲染器
	# 画折线、不填充，模型镜像同一语义：「闭合」属于 SHAPE，不属于 spec 路径）。
	var gpGlyph := PackedVector2Array()
	for gpE in _gpPolys(gpOut):
		if str(gpE["layer"]) == GPPrintModel.GP_LAYER_EQUIPMENT:
			gpGlyph = gpE["pts"] as PackedVector2Array
	gpCheck(gpGlyph.size() >= 4, "the square glyph projected as a polyline")
	# The mapping is centred-scale: local (-25..25) rotated 90° about (200,300).
	# 映射为居中缩放：本地 (-25..25) 绕 (200,300) 旋转 90°。
	# Rotating (x,y) by +90° in a Y-DOWN world maps (x,y)->(-y,x): the bbox about the centre
	# is symmetric, so the rotated square still spans centre ± 25 on both axes.
	# Y 向下世界中 (x,y) 转 +90° 得 (-y,x)：正方形的包围盒关于中心对称，
	# 故旋转后仍在中心 ±25 的两轴范围内。
	var gpMin := Vector2(INF, INF)
	var gpMax := -Vector2(INF, INF)
	for gpP in gpGlyph:
		gpMin = gpMin.min(gpP)
		gpMax = gpMax.max(gpP)
	gpCheck(gpMin.is_equal_approx(Vector2(175.0, 275.0)),
		"rotated glyph bbox min = centre - 25, got " + str(gpMin))
	gpCheck(gpMax.is_equal_approx(Vector2(225.0, 325.0)),
		"rotated glyph bbox max = centre + 25, got " + str(gpMax))
	var gpGotBody := false
	for gpE in _gpPolys(gpOut):
		if str(gpE["layer"]) == GPPrintModel.GP_LAYER_EQUIPMENT \
				and absf(float(gpE["w"]) - GPPrintModel.GP_W_BODY) < 0.0001:
			gpGotBody = true
	gpCheck(gpGotBody, "equipment strokes at body weight")


# ---- 5. the tag reuses the canvas placement / 位号复用画布定位 ----

func gpTestTagPlacementMatchesCanvasMath() -> void:
	var gpDef := _gpGlyphDef("GPUMP001", "pump")
	var gpGraph := GPPIDGraph.new()
	_gpNodeIn(gpGraph, "n1", "P-1001", "GPUMP001", Vector2(200.0, 300.0))
	var gpDefs: Array[GPSymbolDef] = [gpDef]
	var gpOut: Array[Dictionary] = GPPrintModel.gpProject(_gpBareSheet(gpGraph), gpDefs)
	# Expected point = origin + oriented local offset, the SAME formula the canvas applies.
	# 期望点 = 原点 + 定向后的本地偏移，与画布施加的**同一公式**。
	var gpOff: Vector2 = GPLabelPlacement.gpLocalOffset(gpGraph.gpNodes[0], gpDef)
	var gpWant: Vector2 = Vector2(200.0, 300.0) + gpOff
	var gpFound := false
	for gpT in _gpTexts(gpOut):
		if str(gpT["s"]) == "P-1001" \
				and (gpT["at"] as Vector2).is_equal_approx(gpWant):
			gpFound = true
			# A pump is an equipment category -> the 9 mm tier.
			# 泵属设备类别 -> 9mm 档。
			gpEq(float(gpT["h"]), GPTextRole.gpTagMM("pump", GPTextRole.GP_INLINE_TAG_MM),
				"equipment tag rides the equipment tier")
			# P0-2: the anchor is the text BOX CENTRE, not its left end; the tag must be
			# emitted centred + middle-baseline or every printed tag shifts right.
			# P0-2：锚点是文字**盒中心**、不是左端；位号必须按居中 + 行中高发出，否则每个
			# 打印位号都右移。
			gpEq(str(gpT["align"]), "c", "居中锚点的位号应水平居中")
			gpEq(str(gpT["valign"]), GPPrintModel.GP_VALIGN_MIDDLE, "位号应以行中高为基准")
	gpCheck(gpFound, "the tag sits exactly where the canvas formula puts it")


# P0-2: a LEFT tag hangs left (right-aligned), a RIGHT tag starts at its right edge (left-aligned);
# both stay middle-baseline. The old "always l" projection shifted them by half/full width.
# P0-2：LEFT 位号向左悬挂（右对齐）、RIGHT 位号从右缘起排（左对齐）；两者都保持行中高。
# 旧的「永远 l」投影让它们右移半个/一个整字宽。
func gpTestTagAlignmentFollowsAnchor() -> void:
	for gpCase in [[GPLabelAnchor.GPAnchor.GP_LEFT, "r"], [GPLabelAnchor.GPAnchor.GP_RIGHT, "l"]]:
		var gpDef := _gpGlyphDef("GPUMP002", "pump")
		gpDef.gpLabelAnchor = int(gpCase[0])
		var gpGraph := GPPIDGraph.new()
		_gpNodeIn(gpGraph, "n1", "P-2001", "GPUMP002", Vector2(200.0, 300.0))
		var gpOut: Array[Dictionary] = GPPrintModel.gpProject(_gpBareSheet(gpGraph), [gpDef])
		var gpFound := false
		for gpT in _gpTexts(gpOut):
			if str(gpT["s"]) == "P-2001":
				gpFound = true
				gpEq(str(gpT["align"]), str(gpCase[1]), "位号对齐应随锚点变化")
				gpEq(str(gpT["valign"]), GPPrintModel.GP_VALIGN_MIDDLE, "位号纵向仍为行中高")
		gpCheck(gpFound, "anchor case should still emit the tag")


# P0-2: FRAME text is authored on its baseline. It must say so, or the PDF writer adds the
# middle->baseline offset a second time and every zone label / title-block value sinks by 0.35h.
# P0-2：图框文字以**基线**编排。若不声明，PDF 写出器会再次施加「中高→基线」偏移，使每个
# 坐标带标号 / 图签值下沉 0.35h。
func gpTestFrameTextDeclaresBaseline() -> void:
	var gpSheet := GPSheet.new()
	gpSheet.gpGraph = GPPIDGraph.new()
	var gpOut: Array[Dictionary] = GPPrintModel.gpProject(gpSheet, [])
	var gpFound := false
	for gpT in _gpTexts(gpOut):
		if str(gpT["layer"]) == GPPrintModel.GP_LAYER_FRAME:
			gpFound = true
			gpEq(str(gpT["valign"]), GPPrintModel.GP_VALIGN_BASELINE,
				"图框文字应以基线为参考")
	gpCheck(gpFound, "the bare sheet still emits frame text")


# ---- 6. pipes recompute the route / 管线重算布线 ----

func gpTestPipesRecomputeTheSameRoute() -> void:
	var gpDef := _gpPortedDef("GPUMP001")
	var gpGraph := GPPIDGraph.new()
	_gpNodeIn(gpGraph, "n1", "P-1001", "GPUMP001", Vector2(100.0, 100.0))
	# Offset vertically so the orthogonal route MUST turn — a straight-line edge would make
	# a naive "connect the ends" shortcut indistinguishable from the real route (the reason
	# the reverse-verification of this suite once ran green on an injected shortcut).
	# 垂直错开使正交布线**必拐弯** —— 共线直连边会让「只连两端」的偷懒捷径与真实布线
	# 无法区分（本套件反向验证曾在注入捷径时跑绿，正是这个原因）。
	_gpNodeIn(gpGraph, "n2", "P-1002", "GPUMP001", Vector2(300.0, 250.0))
	var gpEdge := GPPIDEdge.new()
	gpEdge.gpInstanceId = "e1"
	gpEdge.gpFromRef = {"node_id": "n1", "port_id": "out"}
	gpEdge.gpToRef = {"node_id": "n2", "port_id": "in"}
	gpGraph.gpEdges.append(gpEdge)
	var gpDefs: Array[GPSymbolDef] = [gpDef]
	var gpOut: Array[Dictionary] = GPPrintModel.gpProject(_gpBareSheet(gpGraph), gpDefs)
	# The expected polyline is the ROUTE FUNCTION's own output for the same edge.
	# 期望折线即对同一条边**布线函数自身**的输出。
	var gpWant: Dictionary = GPPortResolver.gpResolveEnd(gpGraph,
		func(gpId: String) -> GPSymbolDef: return gpDef, gpEdge, true,
		GPPortResolver.gpWantTypeFor(gpEdge))
	var gpWantTo: Dictionary = GPPortResolver.gpResolveEnd(gpGraph,
		func(gpId: String) -> GPSymbolDef: return gpDef, gpEdge, false,
		GPPortResolver.gpWantTypeFor(gpEdge))
	var gpWantPts: PackedVector2Array = GPEdgeRoute.gpRoute(gpWant, gpWantTo,
		gpEdge.gpRouting, gpEdge.gpOrtho)
	var gpGotPts := PackedVector2Array()
	for gpE in _gpPolys(gpOut):
		if str(gpE["layer"]) == GPPrintModel.GP_LAYER_PIPING:
			gpGotPts = gpE["pts"] as PackedVector2Array
	gpCheck(gpGotPts.size() > 0, "the pipe projected as a polyline")
	gpEq(gpGotPts.size(), gpWantPts.size(), "same point count as the route function")
	var gpAllEq := gpGotPts.size() == gpWantPts.size()
	for gpI in range(mini(gpGotPts.size(), gpWantPts.size())):
		if not gpGotPts[gpI].is_equal_approx(gpWantPts[gpI]):
			gpAllEq = false
	gpCheck(gpAllEq, "every route point matches GPEdgeRoute's output")


# ---- 7. free shapes keep their layer / 自由图形保留其图层 ----

func gpTestShapeKeepsLayer() -> void:
	var gpGraph := GPPIDGraph.new()
	var gpS := GPShape.gpPolyline(PackedVector2Array([Vector2.ZERO, Vector2(10, 10)]), false)
	gpS.gpLayer = "MY_LAYER"
	gpGraph.gpShapes.append(gpS)
	var gpDefs: Array[GPSymbolDef] = []
	var gpOut: Array[Dictionary] = GPPrintModel.gpProject(_gpBareSheet(gpGraph), gpDefs)
	gpEq(gpOut.size(), 1, "one entity from one shape")
	gpEq(str(gpOut[0]["layer"]), "MY_LAYER", "the shape's own layer travels to the entity")


# ---- 8. grid tables project cells + texts / 表格投影格子与文字 ----

func gpTestGridTableProjectsCellTexts() -> void:
	var gpDef: GPSymbolDef = null
	for gpD in GPSymbolLibrary.gpDefaultDefs():
		if gpD.gpId == "TABLE:device_param":
			gpDef = gpD
	gpCheck(gpDef != null, "the device-param template is in the live library")
	if gpDef == null:
		return
	var gpGraph := GPPIDGraph.new()
	var gpNode := _gpNodeIn(gpGraph, "n1", "T-1", "TABLE:device_param", Vector2(400.0, 200.0))
	gpNode.gpProps["cell_0_0"] = "设计值"
	var gpDefs: Array[GPSymbolDef] = [gpDef]
	var gpOut: Array[Dictionary] = GPPrintModel.gpProject(_gpBareSheet(gpGraph), gpDefs)
	var gpGotCell := false
	for gpT in _gpTexts(gpOut):
		if str(gpT["s"]) == "设计值":
			gpGotCell = true
			# Row height 6.5 mm -> the clamp gives 6.5*0.62 = 4.03, under the 4.4 cap.
			# 行高 6.5mm -> 钳制得 6.5*0.62 = 4.03，低于 4.4 上限。
			gpCheck(absf(float(gpT["h"]) - 6.5 * 0.62) < 0.001,
				"cell text height follows the row clamp, not the cap")
	gpCheck(gpGotCell, "the cell text from the node's props is projected")
	# The generator's separator lines ride the SAME layer the body ink does on screen
	# (EQUIPMENT) — the model mirrors the renderer, it does not invent its own zoning.
	# 生成器的分隔线与屏幕上 body 墨线同层（EQUIPMENT）—— 模型镜像渲染器，不自创分区。
	var gpSeenSep := false
	for gpE in _gpPolys(gpOut):
		if str(gpE["layer"]) == GPPrintModel.GP_LAYER_EQUIPMENT \
				and (gpE["pts"] as PackedVector2Array).size() >= 2:
			gpSeenSep = true
	gpCheck(gpSeenSep, "the grid's separator lines ride EQUIPMENT like the body ink")


# ---- 9. the mirrored text tiers are pinned / 镜像字高档位被钉住 ----

func gpTestMirroredTiersMatchRenderConstants() -> void:
	# Core may not reference render, so GPTextRole carries the print model's copies and this
	# test is the device that keeps them one source of truth.
	# core 不能引用 render，故 GPTextRole 持有打印模型的副本，而本测试就是维持单一事实源的工具。
	gpEq(GPTextRole.GP_ANNOTATE_SCALE, GPSymbolView.GP_ANNOTATE_FONT_SCALE,
		"the annotation scale mirrors the render constant")
	gpEq(GPTextRole.GP_CELL_TEXT_MM, GPSymbolView.GP_CELL_FONT_MM,
		"the cell text cap mirrors the render constant")
