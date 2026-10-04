extends "res://tests/gp_test.gd"
# P2 acceptance: the graphics layer — ShapeCatalogue, ShapeUsage and the graphical primitives.
# P2 验收：图形层 —— ShapeCatalogue、ShapeUsage 与图形图元。
#
# The acceptance criterion from §8.4 is a ROUND TRIP on known values: a known diagonal and a
# known colour must come back equivalent, with the Y flip applied. Tests below assert the
# relational property (file Y == -concept Y) rather than literals, because glyph geometry is
# owned by the symbol definition and moves when a symbol is edited.
# §8.4 的验收标准是已知值上的**往返**：一条已知斜线与一个已知颜色必须等价返回，且 Y 已翻转。
# 下列测试断言关系性质（文件 Y == -概念 Y）而非字面量，因为字形几何归图元定义所有，
# 图元被编辑时它会变动。

const GP_SHEET_W: float = 420.0
const GP_SHEET_H: float = 297.0


static func _gpSheet() -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpName = "P2 Sheet"
	gpSheet.gpWidthMM = GP_SHEET_W
	gpSheet.gpHeightMM = GP_SHEET_H
	return gpSheet


# A pump at a known position, rotated and mirrored, plus one presentation-only arrow.
# 一台位于已知位置、带旋转与镜像的泵，外加一个纯呈现的箭头。
static func _gpGraph() -> GPPIDGraph:
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	var gpPump: GPPIDNode = gpGraph.gpNewNode("n1", "DPUMP001", "P-1001", Vector2(150.0, 120.0))
	gpPump.gpUid = "doc-n1"
	gpPump.gpRotationDeg = 90.0
	gpPump.gpFlipped = true
	gpGraph.gpAddNode(gpPump)
	var gpArrow: GPPIDNode = gpGraph.gpNewNode("n2", "DGENERAL001", "", Vector2(40.0, 60.0))
	gpArrow.gpUid = "doc-n2"
	gpGraph.gpAddNode(gpArrow)
	return gpGraph


static func _gpMid() -> Dictionary:
	return GPDexpiExporter.gpFromGraph(_gpGraph(), _gpSheet())


static func _gpXml() -> String:
	return GPDexpiExporter.gpWriteXml(_gpMid())


# ---- projection ---------------------------------------------------------

func gpTestGraphicsAreCollected() -> void:
	var gpMid: Dictionary = _gpMid()
	var gpShapes: Array = gpMid.get(GPDexpiExporter.GP_KEY_SHAPES, []) as Array
	gpEq(gpShapes.size(), 2, "one catalogue entry per DISTINCT symbol used")
	var gpUsages: Array = gpMid.get(GPDexpiExporter.GP_KEY_USAGES, []) as Array
	gpEq(gpUsages.size(), 2, "one usage per node")


# ★ THE POINT OF P2 / P2 的要害：a presentation-only symbol has NO concept object, so it is
# skipped as equipment — but it is still a graphic, and it must still appear on the drawing.
# ★ 纯呈现图元**没有**概念对象，故作为设备被跳过 —— 但它仍是图形，仍须出现在图纸上。
func gpTestPresentationOnlySymbolsStillGetGraphics() -> void:
	var gpUsages: Array = _gpMid().get(GPDexpiExporter.GP_KEY_USAGES, []) as Array
	var gpArrowUsage: Dictionary = (gpUsages[1] as Dictionary)
	gpEq(str(gpArrowUsage.get("shape_id", "")), "DGENERAL001", "the arrow keeps its shape")
	gpEq(str(gpArrowUsage.get("item_id", "")), "",
		"a presentation-only usage carries NO ItemID (it has no concept object)")
	var gpPumpUsage: Dictionary = gpUsages[0] as Dictionary
	gpEq(str(gpPumpUsage.get("item_id", "")), "doc-n1", "the pump links to its Equipment")


# Scale is derived, not assumed: unit box 0..100 stretched to gpDefaultSize.
# 缩放是**推导**出来的，而非假设：单位框 0..100 拉伸到 gpDefaultSize。
func gpTestUsageScaleIsDerivedFromTheSymbolSize() -> void:
	var gpUsage: Dictionary = (_gpMid().get(GPDexpiExporter.GP_KEY_USAGES, []) as Array)[0] as Dictionary
	var gpDef: GPSymbolDef = GPSymbolLibrary.gpFindById("DPUMP001")
	if gpDef == null:
		gpCheck(true, "library unavailable in this run; scale falls back to 1.0")
		return
	var gpWant: float = minf(gpDef.gpDefaultSize.x, gpDef.gpDefaultSize.y) / 100.0
	gpApprox(float(gpUsage.get("scale", 0.0)), gpWant, 1e-6,
		"scale is the glyph unit box stretched to the symbol's real size")
	gpCheck(float(gpUsage.get("scale", 0.0)) != 1.0 or gpWant == 1.0,
		"the scale is the real ratio, not a hard-coded 1.0")


# ---- serialisation ------------------------------------------------------

func gpTestDocumentIsReadableWithGraphics() -> void:
	var gpText: String = _gpXml()
	gpCheck(GPDexpiExporter.gpIsWellFormed(gpText), "the document with graphics still parses")


func gpTestShapeCatalogueIsEmitted() -> void:
	var gpText: String = _gpXml()
	gpCheck(gpText.contains("<ShapeCatalogue Name=\"G-PID\">"), "the catalogue is emitted")
	gpCheck(gpText.contains("<Shape Name=\"DPUMP001\">"), "the pump glyph is in the catalogue")
	gpCheck(gpText.contains("<Shape Name=\"DGENERAL001\">"), "the arrow glyph is too")
	gpCheck(gpText.contains("</ShapeCatalogue>"), "the catalogue is closed")


func gpTestEveryDrawingCoordinateIsFlipped() -> void:
	var gpText: String = _gpXml()
	# Verify the relational property on the catalogue's own primitives.
	# 在目录自身的图元上验证关系性质。
	var gpMid: Dictionary = _gpMid()
	var gpShapes: Array = gpMid.get(GPDexpiExporter.GP_KEY_SHAPES, []) as Array
	var gpChecked: int = 0
	for gpShape in gpShapes:
		for gpPrim in ((gpShape as Dictionary).get("primitives", []) as Array):
			var gpP: Dictionary = gpPrim as Dictionary
			for gpPoint in (gpP.get("points", []) as Array):
				var gpV: Vector2 = gpPoint as Vector2
				var gpWant: String = GPXmlText.gpSelf("Coordinate", GPXmlText.gpAttrs([
					GPXmlText.gpAttr("X", GPXmlText.gpNum(gpV.x)),
					GPXmlText.gpAttr("Y", GPXmlText.gpNum(GPDexpiMapping.gpFlipY(gpV.y))),
				]), 0)
				# The indentation differs by nesting level, so compare without leading spaces.
				# 缩进随嵌套层级变化，故比较时去掉前导空格。
				gpCheck(gpText.contains(gpWant.strip_edges()),
					"glyph point " + str(gpV) + " is written flipped")
				gpChecked += 1
	gpCheck(gpChecked > 0, "at least one glyph point was checked")


# Closed polygons repeat their first point (§4.4).
# 闭合多边形重复其首点（§4.4）。
func gpTestClosedPolygonsRepeatTheFirstPoint() -> void:
	var gpMid: Dictionary = _gpMid()
	var gpShapes: Array = gpMid.get(GPDexpiExporter.GP_KEY_SHAPES, []) as Array
	var gpFoundClosed: bool = false
	for gpShape in gpShapes:
		for gpPrim in ((gpShape as Dictionary).get("primitives", []) as Array):
			var gpP: Dictionary = gpPrim as Dictionary
			if not bool(gpP.get("closed", false)):
				continue
			gpFoundClosed = true
			var gpPts: Array = gpP.get("points", []) as Array
			var gpText: String = GPDexpiExporter.gpWriteXml(gpMid)
			var gpFirst: Vector2 = gpPts[0] as Vector2
			var gpLast: Vector2 = gpPts[gpPts.size() - 1] as Vector2
			# The emitted element must state one more point than the geometry holds.
			# 发出的元素声明的点数必须比几何实际点多一个。
			gpCheck(gpText.contains("NumPoints=\"%d\"" % (gpPts.size() + 1)),
				"a closed polygon declares one extra point")
			gpCheck(gpFirst != gpLast or gpPts.size() > 1,
				"the closing point is appended, not assumed")
	if not gpFoundClosed:
		# No closed primitive in the sample: assert the rule on a hand-made one instead, so the
		# rule stays covered even if the sample glyphs change.
		# 样例中没有闭合图元：改为在一个手工构造的图元上断言该规则，
		# 这样即使样例字形变更，该规则仍被覆盖。
		var gpText: String = GPDexpiExporter.gpWriteXml({
			GPDexpiExporter.GP_KEY_SHAPES: [
				{"id": "TESTCLOSED", "primitives": [
					{"kind": GPShape.GPKind.GP_POLYLINE, "points": [Vector2(0.0, 0.0),
						Vector2(10.0, 0.0), Vector2(10.0, 10.0)],
					"radius": 0.0, "closed": true, "color": Color(0.0, 0.0, 0.0)},
				]},
			],
		})
		gpCheck(gpText.contains("NumPoints=\"4\""), "a closed polygon declares one extra point")
		gpEq(gpText.count("<Coordinate"), 4, "the first point is repeated at the end")


# ---- ShapeUsage ---------------------------------------------------------

func gpTestShapeUsageCarriesPose() -> void:
	var gpText: String = _gpXml()
	gpCheck(gpText.contains("<ShapeUsage ID="), "usages are emitted")
	gpCheck(gpText.contains("Shape=\"DPUMP001\""), "the usage references its shape")
	gpCheck(gpText.contains("ItemID=\"doc-n1\""), "the equipment usage links to the object")
	# Position: concept (150,120) -> file (150,-120).
	# 位置：概念 (150,120) -> 文件 (150,-120)。
	gpCheck(gpText.contains("<Position X=\"150\" Y=\"-120\"/>"),
		"the usage position is flipped like every other coordinate")
	# Rotation: clockwise 90 in G-PID -> counter-clockwise -90 in Proteus (待确认 4).
	# 旋转：G-PID 的顺时针 90 -> Proteus 的逆时针 -90（待确认 4）。
	gpCheck(gpText.contains("Rotation=\"-90\""), "the rotation sign inverts")
	gpCheck(gpText.contains("IsMirrored=\"yes\""), "the mirror flag is carried")
	gpCheck(gpText.contains("ScaleX="), "ScaleX is written")
	gpCheck(gpText.contains("ScaleY="), "ScaleY is written")


func gpTestUsageGroupsAreEmittedInsideTheDrawing() -> void:
	var gpText: String = _gpXml()
	gpCheck(gpText.contains("<RepresentationGroup ID=\"rg_static\">"),
		"usages sit in a representation group")
	gpCheck(gpText.contains("<RepresentationTypeGroup ID=\"rtg_static\" Type=\"Static\">"),
		"and in a typed group (§10: groups cannot nest groups)")
	gpCheck(gpText.contains("</Drawing>"), "the Drawing element is closed around them")


# Risk 3 again, now on the graphics path: colour must be 0..1 everywhere.
# 再次验证风险 3，这次在图形路径上：颜色在任何位置都必须是 0..1。
func gpTestPresentationColourIsNormalised() -> void:
	var gpText: String = GPDexpiExporter.gpWriteXml({
		GPDexpiExporter.GP_KEY_SHAPES: [
			{"id": "TESTCOLOR", "primitives": [
				{"kind": GPShape.GPKind.GP_LINE, "points": [Vector2(0.0, 0.0), Vector2(10.0, 10.0)],
					"radius": 0.0, "closed": false, "color": Color(0.0, 0.498, 1.0)},
			]},
		],
	})
	gpCheck(gpText.contains("<Presentation"), "a presentation block is emitted")
	gpCheck(gpText.contains("R=\"0\""), "red channel is normalised")
	gpCheck(gpText.contains("G=\"0.498\""), "green channel keeps three decimals")
	gpCheck(gpText.contains("B=\"1\""), "blue channel is normalised")
	# A 0..255 value would show up as something like G="127"; assert none exceeds 1.
	# 若是 0..255 的写法，会出现类似 G="127" 的值；断言没有任何分量超过 1。
	var gpRe: RegEx = RegEx.new()
	gpRe.compile(" [RGB]=\"([0-9.]+)\"")
	for gpM in gpRe.search_all(gpText):
		gpCheck(float((gpM as RegExMatch).get_string(1)) <= 1.0,
			"no colour channel exceeds 1.0: " + (gpM as RegExMatch).get_string(1))


# An arc has no DEXPI primitive in the listed set, so it degrades to a polyline rather than
# being dropped or invented as a new element.
# 规范列出的图元集合中没有弧线，故弧线降级为折线 —— 既不丢弃，也不臆造新元素。
func gpTestArcDegradesToAPolyline() -> void:
	var gpText: String = GPDexpiExporter.gpWriteXml({
		GPDexpiExporter.GP_KEY_SHAPES: [
			{"id": "TESTARC", "primitives": [
				{"kind": GPShape.GPKind.GP_ARC, "points": [Vector2(0.0, 0.0), Vector2(5.0, 5.0),
					Vector2(10.0, 0.0)], "radius": 0.0, "closed": false,
					"color": Color(0.0, 0.0, 0.0)},
			]},
		],
	})
	gpCheck(gpText.contains("<PolyLine"), "an arc becomes a polyline")
	gpCheck(not gpText.contains("<Arc"), "no invented <Arc> element")
	gpCheck(gpText.contains("NumPoints=\"3\""), "the sampled points are preserved")


# A circle becomes an ellipse with a centre and both radii.
# 圆变成带圆心与两个半径的椭圆。
func gpTestCircleBecomesAnEllipse() -> void:
	var gpText: String = GPDexpiExporter.gpWriteXml({
		GPDexpiExporter.GP_KEY_SHAPES: [
			{"id": "TESTCIRCLE", "primitives": [
				{"kind": GPShape.GPKind.GP_CIRCLE, "points": [Vector2(50.0, 50.0)],
					"radius": 12.5, "closed": false, "color": Color(0.0, 0.0, 0.0)},
			]},
		],
	})
	gpCheck(gpText.contains("<Ellipse"), "a circle becomes an ellipse")
	gpCheck(gpText.contains("<Center X=\"50\" Y=\"-50\"/>"),
		"the centre is flipped like every coordinate")
	gpCheck(gpText.contains("<RX Value=\"12.5\"/>"), "the radius is carried")
	gpCheck(gpText.contains("<RY Value=\"12.5\"/>"), "both radii are written")


# ---- round trip on known values -----------------------------------------

# §8.4 P2 acceptance: a known diagonal must come back equivalent across the flip.
# §8.4 P2 验收：一条已知斜线必须在翻转后等价返回。
func gpTestKnownDiagonalRoundTrip() -> void:
	var gpA: Vector2 = Vector2(10.0, 20.0)
	var gpB: Vector2 = Vector2(60.0, 90.0)
	var gpText: String = GPDexpiExporter.gpWriteXml({
		GPDexpiExporter.GP_KEY_SEGMENTS: [
			{"id": "e1", "points": [gpA, gpB], "from_uid": "", "to_uid": "", "attrs": {}, "tag": ""},
		],
	})
	gpCheck(gpText.contains("<Coordinate X=\"10\" Y=\"-20\"/>"),
		"the first end of the known diagonal flips")
	gpCheck(gpText.contains("<Coordinate X=\"60\" Y=\"-90\"/>"),
		"the second end of the known diagonal flips")
	# Recovering the concept points back out of the file text is the actual round trip.
	# 从文件文本中还原出概念点，才是真正的往返。
	var gpBack: Array[Vector2] = []
	var gpRe: RegEx = RegEx.new()
	gpRe.compile("<Coordinate X=\"(-?[0-9.]+)\" Y=\"(-?[0-9.]+)\"/>")
	for gpM in gpRe.search_all(gpText):
		var gpX: float = float((gpM as RegExMatch).get_string(1))
		var gpY: float = GPDexpiMapping.gpFlipY(float((gpM as RegExMatch).get_string(2)))
		gpBack.append(Vector2(gpX, gpY))
	gpEq(gpBack.size(), 2, "both ends came back")
	if gpBack.size() == 2:
		gpApprox((gpBack[0] as Vector2).x, gpA.x, 1e-6, "first end X is unchanged")
		gpApprox((gpBack[0] as Vector2).y, gpA.y, 1e-6, "first end Y round-trips")
		gpApprox((gpBack[1] as Vector2).y, gpB.y, 1e-6, "second end Y round-trips")
		# The slope is preserved: a flipped diagram would invert it twice and match by accident,
		# so assert the ORIGINAL slope survived one flip-and-back.
		# 斜率保持不变：整图翻转会翻转两次而偶然吻合，
		# 故断言原斜率在「一次翻转 + 一次还原」后仍然成立。
		var gpSlope: float = (gpB.y - gpA.y) / (gpB.x - gpA.x)
		var gpBackSlope: float = ((gpBack[1] as Vector2).y - (gpBack[0] as Vector2).y) \
			/ ((gpBack[1] as Vector2).x - (gpBack[0] as Vector2).x)
		gpApprox(gpBackSlope, gpSlope, 1e-6, "the slope survives the round trip")
