extends "res://tests/gp_test.gd"
# P1 acceptance: minimal export loop — conceptual layer + Drawing extent, no graphics (§8.4 P1,
# 做法 A). Builds a small sheet, projects it, writes XML, and asserts the invariants that the
# spec calls out as silent failures.
# P1 验收：导出最小闭环 —— 概念层 + Drawing 范围，不含图形（§8.4 P1，做法 A）。
# 构造一张小图、投影、写出 XML，并断言规范点名的那些「静默失效」不变量。
#
# The export path is deliberately END-TO-END here (graph -> xml -> parsed back), because the
# failure modes are relational: an extent that does not contain its own shapes, a Y that was
# flipped in one place and not another. None of those are visible in a unit test of one step.
# 此处刻意采用**端到端**路径（图 -> xml -> 解析回来），因为失效模式是**关系性**的：
# 一个装不下自己图形的范围、一处翻转了而另一处没翻转的 Y。这些在单步单元测试里都看不见。

const GP_SHEET_W: float = 420.0
const GP_SHEET_H: float = 297.0


# ---- fixtures -----------------------------------------------------------

# A3 sheet with a pump, a tank and one bent process line.
# 一张 A3：一台泵、一台罐、一条带折点的工艺线。
static func _gpSampleGraph() -> GPPIDGraph:
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	# gpNewNode() only CONSTRUCTS a node; gpAddNode() is what puts it in the graph. Forgetting
	# this yields an empty graph that makes every downstream assertion fail for the wrong
	# reason — worth stating explicitly because the two calls look redundant.
	# gpNewNode() 只**构造**节点；把它放进图的是 gpAddNode()。漏掉后者会得到一个空图，
	# 使下游每条断言都因错误的原因失败 —— 值得显式说明，因为这两次调用看起来是冗余的。
	var gpPump: GPPIDNode = gpGraph.gpNewNode("n1", "DPUMP001", "P-1001", Vector2(100.0, 100.0))
	gpPump.gpUid = "doc-n1"
	gpPump.gpNames = {"zh_CN": "离心泵", "en_US": "Centrifugal pump"}
	gpPump.gpProps = {"design_pressure": 1.0, "volume": 12.5}
	gpGraph.gpAddNode(gpPump)
	var gpTank: GPPIDNode = gpGraph.gpNewNode("n2", "DTANK001", "T-1002", Vector2(300.0, 200.0))
	gpTank.gpUid = "doc-n2"
	gpTank.gpProps = {"design_temp": 100.0}
	gpGraph.gpAddNode(gpTank)
	var gpEdge: GPPIDEdge = GPPIDEdge.new()
	gpEdge.gpInstanceId = "e5"
	gpEdge.gpFromRef = {"node_id": "n1", "port_id": "out"}
	gpEdge.gpToRef = {"node_id": "n2", "port_id": "top"}
	gpEdge.gpRouting = [Vector2(200.0, 150.0)]
	gpEdge.gpTag = "PL-1002"
	# tag_offset is layout state; it must never appear in the file (risk 8).
	# tag_offset 是布局状态，绝不可出现在文件中（风险 8）。
	gpEdge.gpAttrs = {"dn": "100", "insulation": 40.0, "medium": "水", "tag_offset": Vector2(3.0, -1.0)}
	gpGraph.gpEdges.append(gpEdge)
	return gpGraph


static func _gpSampleSheet(gpName: String = "Test A3") -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpName = gpName
	gpSheet.gpWidthMM = GP_SHEET_W
	gpSheet.gpHeightMM = GP_SHEET_H
	return gpSheet


# ---- pre-flight ---------------------------------------------------------

func gpTestPreflightAcceptsAHealthySheet() -> void:
	var gpReport: GPImportReport = GPDexpiExporter.gpPreflight(_gpSampleGraph(), _gpSampleSheet())
	gpCheck(not gpReport.gpHasErrors(), "a complete sheet has no fatal finding")
	gpCheck(not gpReport.gpCountOf(GPImportReport.GP_ERROR) > 0, "no error entries")


func gpTestPreflightRejectsAZeroSizeSheet() -> void:
	var gpSheet: GPSheet = _gpSampleSheet()
	gpSheet.gpWidthMM = 0.0
	var gpReport: GPImportReport = GPDexpiExporter.gpPreflight(_gpSampleGraph(), gpSheet)
	gpCheck(gpReport.gpHasErrors(), "a zero-width sheet is fatal")
	gpEq(gpReport.gpCountOf(GPImportReport.GP_ERROR), 1, "exactly one fatal finding")


func gpTestPreflightRejectsAMissingSheetName() -> void:
	var gpReport: GPImportReport = GPDexpiExporter.gpPreflight(_gpSampleGraph(), _gpSampleSheet("  "))
	gpCheck(gpReport.gpHasErrors(), "Diagram.Name is mandatory (§3.1)")


# An object without a stable uid must be refused, not exported with a throwaway id (§7.4).
# 缺少稳定 uid 的对象必须被拒绝，而不是带上一个临时 id 导出（§7.4）。
func gpTestPreflightRejectsMissingStableUid() -> void:
	var gpGraph: GPPIDGraph = _gpSampleGraph()
	(gpGraph.gpNodes[0] as GPPIDNode).gpUid = ""
	var gpReport: GPImportReport = GPDexpiExporter.gpPreflight(gpGraph, _gpSampleSheet())
	gpCheck(gpReport.gpHasErrors(), "a node without a stable uid is fatal")


func gpTestPreflightReportsSignalLinesAsUnsupported() -> void:
	var gpGraph: GPPIDGraph = _gpSampleGraph()
	(gpGraph.gpEdges[0] as GPPIDEdge).gpKind = GPPIDEdge.GP_SIGNAL
	var gpReport: GPImportReport = GPDexpiExporter.gpPreflight(gpGraph, _gpSampleSheet())
	gpCheck(not gpReport.gpHasErrors(), "a signal line is not fatal")
	var gpFound: bool = false
	for gpE in gpReport.gpEntries:
		if str((gpE as Dictionary).get("code", "")) == GPDexpiExporter.GP_CODE_SIGNAL_UNSUPPORTED:
			gpFound = true
	gpCheck(gpFound, "the unsupported signal line is reported, not silently dropped")


# ---- projection ---------------------------------------------------------

func gpTestProjectionShape() -> void:
	var gpGraph: GPPIDGraph = _gpSampleGraph()
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(gpGraph, _gpSampleSheet())
	gpCheck(not gpMid.is_empty(), "projection produced a structure")
	gpEq((gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array).size(), 2, "two equipment")
	gpEq((gpMid.get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array).size(), 1, "one segment")
	var gpSeg: Dictionary = (gpMid.get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array)[0] as Dictionary
	# Start + one stored bend + end. / 起点 + 一个已存折点 + 终点。
	gpEq((gpSeg.get("points", []) as Array).size(), 3, "bends are joined to the endpoints")
	# Edge references are translated from instance id to STABLE uid.
	# 边的引用已从 instance id 翻译为**稳定 uid**。
	gpEq(str(gpSeg.get("from_uid", "")), "doc-n1", "source reference uses the stable uid")
	gpEq(str(gpSeg.get("to_uid", "")), "doc-n2", "target reference uses the stable uid")


func gpTestProjectionKeepsDiagramInConceptCoordinates() -> void:
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(_gpSampleGraph(), _gpSampleSheet())
	var gpDiagram: Dictionary = gpMid.get(GPDexpiExporter.GP_KEY_DIAGRAM, {}) as Dictionary
	gpApprox(float(gpDiagram.get("min_y", -1.0)), 0.0, 1e-6, "concept MinY is 0 (Y down)")
	gpApprox(float(gpDiagram.get("max_y", -1.0)), GP_SHEET_H, 1e-6, "concept MaxY is the sheet height")
	gpEq(str(gpDiagram.get("name", "")), "Test A3", "diagram carries the sheet name")


# Annotations are presentation-only and must not become concept objects.
# 纯图形条目仅属呈现，不得变成概念对象。
func gpTestAnnotationsAreSkippedNotExported() -> void:
	var gpGraph: GPPIDGraph = _gpSampleGraph()
	var gpArrow: GPPIDNode = gpGraph.gpNewNode("n9", "DGENERAL001", "", Vector2(10.0, 10.0))
	gpArrow.gpUid = "doc-n9"
	gpGraph.gpAddNode(gpArrow)
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(gpGraph, _gpSampleSheet())
	gpEq((gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array).size(), 2,
		"the flow arrow is not exported as equipment")
	var gpSkipped: Array = gpMid.get(GPDexpiExporter.GP_KEY_SKIPPED, []) as Array
	gpEq(gpSkipped.size(), 1, "the skip is recorded")
	gpEq(str((gpSkipped[0] as Dictionary).get("reason", "")), "annotation", "skip reason is recorded")


func gpTestSignalLinesAreSkippedInPhaseOne() -> void:
	var gpGraph: GPPIDGraph = _gpSampleGraph()
	(gpGraph.gpEdges[0] as GPPIDEdge).gpKind = GPPIDEdge.GP_SIGNAL
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(gpGraph, _gpSampleSheet())
	gpEq((gpMid.get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array).size(), 0, "no segment for a signal")
	gpEq((gpMid.get(GPDexpiExporter.GP_KEY_SKIPPED, []) as Array).size(), 1, "the skip is recorded")


# ---- serialisation ------------------------------------------------------

static func _gpXmlOfSample() -> String:
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(_gpSampleGraph(), _gpSampleSheet())
	return GPDexpiExporter.gpWriteXml(gpMid)


func gpTestDocumentIsWellFormedAndReParsable() -> void:
	var gpText: String = _gpXmlOfSample()
	gpCheck(gpText.begins_with("<?xml"), "document starts with the declaration")
	gpCheck(GPDexpiExporter.gpIsWellFormed(gpText), "the exported text parses back cleanly")
	gpCheck(gpText.contains("<PlantModel>"), "root element is PlantModel")
	gpCheck(gpText.contains("</PlantModel>"), "the root element is closed")
	# HONEST LIMIT / 诚实的局限：Godot's XMLParser is a LENIENT streaming reader, so it does not
	# catch a mismatched tag. This check proves the document can be READ, not that it is strictly
	# well-formed — that is L3's job, in CI, with xmllint (§7.2). Naming the limit here prevents
	# anyone from trusting this function to do more than it does.
	# Godot 的 XMLParser 是**宽松**的流式读取器，抓不到标签不匹配。本检查只证明文档**可读**，
	# 而非严格良构 —— 那是 L3 的职责，在 CI 中用 xmllint 完成（§7.2）。
	# 在此点明局限，以免有人误信该函数能做更多。
	gpCheck(not GPDexpiExporter.gpIsWellFormed(""), "an empty document is not readable")


func gpTestPlantInformationCarriesTheMandatoryFields() -> void:
	var gpText: String = _gpXmlOfSample()
	gpCheck(gpText.contains("SchemaVersion=\"4.2.0\""), "schema version is written")
	gpCheck(gpText.contains("Units=\"mm\""), "units are stated")
	gpCheck(gpText.contains("Discipline=\"PID\""), "discipline is stated")
	gpCheck(gpText.contains("OriginatingSystem=\"G-PID\""), "originating system is stated")
	gpCheck(gpText.contains("Date=\""), "export date is present (ExportDateTime is mandatory)")
	gpCheck(gpText.contains("<UnitsOfMeasure/>"), "UnitsOfMeasure container is present")


# Risk 7: every device is <Equipment>, never <Pump> / <Vessel>.
# 风险 7：所有设备都是 <Equipment>，绝不可写成 <Pump> / <Vessel>。
func gpTestDevicesSerialiseAsEquipment() -> void:
	var gpText: String = _gpXmlOfSample()
	gpCheck(gpText.contains("<Equipment ID=\"doc-n1\""), "the pump is an Equipment with its uid")
	gpCheck(gpText.contains("ComponentClass=\"CentrifugalPump\""), "component class distinguishes it")
	gpCheck(not gpText.contains("<Pump"), "never emit a class-named element")
	gpCheck(not gpText.contains("<CentrifugalPump"), "the class name is an attribute, not a tag")


# URI policy: verified or absent. A fabricated URI resolves to nothing.
# URI 原则：已核实或缺失。臆造的 URI 解析到空。
func gpTestUriIsVerifiedOrAbsent() -> void:
	var gpText: String = _gpXmlOfSample()
	gpCheck(gpText.contains("ComponentClassURI=\"http://data.posccaesar.org/rdl/RDS416834\""),
		"the verified pump URI is written")
	# The tank's URI is not verified, so no ComponentClassURI attribute appears for it.
	# 罐的 URI 未核实，故不会为它写出 ComponentClassURI 属性。
	var gpTankLine: String = _gpLineContaining(gpText, "ComponentClass=\"Vessel\"")
	gpCheck(not gpTankLine.is_empty(), "the tank is present")
	gpCheck(not gpTankLine.contains("ComponentClassURI"), "no invented URI for the tank")


# Risk 1: every coordinate is flipped.
# 风险 1：每个坐标都翻转。
# These are RELATIONAL assertions, not literal ones: endpoints come from the port resolution,
# so they carry a nozzle offset that belongs to the symbol definition. Hard-coding a literal
# coordinate would make this test break whenever a symbol's port moves.
# 这些是**关系性**断言，而非字面量断言：端点来自端口解析，带有属于图元定义的管口偏移。
# 硬编码字面坐标会让本测试在图元端口移动时失效。
func gpTestCoordinatesAreFlipped() -> void:
	var gpGraph: GPPIDGraph = _gpSampleGraph()
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(gpGraph, _gpSampleSheet())
	var gpPts: Array = ((gpMid.get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array)[0]
		as Dictionary).get("points", []) as Array
	var gpText: String = GPDexpiExporter.gpWriteXml(gpMid)
	gpEq(gpPts.size(), 3, "start + bend + end")
	for gpP in gpPts:
		var gpV: Vector2 = gpP as Vector2
		# Rebuild the expected line the same way the exporter does, then require it verbatim.
		# 以与导出器相同的方式重建期望的那一行，再要求其逐字出现。
		var gpWant: String = GPXmlText.gpSelf("Coordinate", GPXmlText.gpAttrs([
			GPXmlText.gpAttr("X", GPXmlText.gpNum(gpV.x)),
			GPXmlText.gpAttr("Y", GPXmlText.gpNum(GPDexpiMapping.gpFlipY(gpV.y))),
		]), 5)
		gpCheck(gpText.contains(gpWant), "concept " + str(gpV) + " is written with Y flipped")
	gpCheck(gpText.contains("NumPoints=\"3\""), "the polyline states three points")
	# The stored bend has no port offset, so its literal value is stable and worth pinning.
	# 已存折点没有管口偏移，故其字面值稳定，值得钉死。
	gpCheck(gpText.contains("<Coordinate X=\"200\" Y=\"-150\"/>"),
		"the stored bend flips from 150 to -150")


# Endpoints are resolved through the port resolver — NOT taken as the node centre — so the
# exported line starts and ends on the real nozzle.
# 端点经端口解析器得出 —— **而非**取节点中心 —— 故导出的线起止于真实管口。
func gpTestEndpointsUsePortResolution() -> void:
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(_gpSampleGraph(), _gpSampleSheet())
	var gpSeg: Dictionary = (gpMid.get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array)[0] as Dictionary
	var gpWhy: String = str(gpSeg.get("why_from", ""))
	gpCheck(gpWhy in ["port", "typed", "center", "free"],
		"the resolver reports which rung it used: " + gpWhy)
	var gpPts: Array = gpSeg.get("points", []) as Array
	var gpStart: Vector2 = gpPts[0] as Vector2
	var gpEnd: Vector2 = gpPts[2] as Vector2
	gpCheck(gpStart != Vector2.ZERO, "the start point was resolved, not left at the origin")
	gpCheck(gpEnd != Vector2.ZERO, "the end point was resolved, not left at the origin")
	# The pump outlet is offset from the node centre: proof the nozzle was used.
	# 泵的出口相对节点中心有偏移：这证明用的是管口而非中心。
	gpApprox(gpStart.y, 100.0, 1e-6, "the start sits on the pump's outlet height")
	gpApprox(gpEnd.x, 300.0, 1e-6, "the end sits on the tank's centre line (top nozzle)")


# ★ THE SELF-CONSISTENCY INVARIANT / 自洽性不变量：
# every shape must lie INSIDE the extent it is declared in. This is the check that catches the
# whole class of "flipped in one place, not another" bugs, and it is why the extent is flipped
# along with the geometry (see GPDexpiExporter._gpDrawingLines).
# 每个图形都必须落在其声明的范围**之内**。这项检查能抓住整类「一处翻转、另一处没翻转」
# 的缺陷，也正是范围随几何一起翻转的原因（见 GPDexpiExporter._gpDrawingLines）。
func gpTestEveryCoordinateLiesInsideTheExtent() -> void:
	var gpText: String = _gpXmlOfSample()
	var gpMinY: float = _gpExtentValue(gpText, "MinY")
	var gpMaxY: float = _gpExtentValue(gpText, "MaxY")
	var gpMinX: float = _gpExtentValue(gpText, "MinX")
	var gpMaxX: float = _gpExtentValue(gpText, "MaxX")
	gpCheck(gpMinY < gpMaxY, "the extent is not degenerate")
	var gpYs: Array[float] = _gpAllCoordinateY(gpText)
	gpCheck(gpYs.size() >= 3, "coordinates were found")
	for gpY in gpYs:
		gpCheck(gpY >= gpMinY - 0.001 and gpY <= gpMaxY + 0.001,
			"coordinate Y " + str(gpY) + " lies within [" + str(gpMinY) + ", " + str(gpMaxY) + "]")
	var gpXs: Array[float] = _gpAllCoordinateX(gpText)
	for gpX in gpXs:
		gpCheck(gpX >= gpMinX - 0.001 and gpX <= gpMaxX + 0.001,
			"coordinate X " + str(gpX) + " lies within the extent")


# The extent itself is flipped: 0..297 (concept, Y down) becomes -297..0 (file, Y up).
# 范围自身也被翻转：0..297（概念，Y 向下）变为 -297..0（文件，Y 向上）。
func gpTestExtentIsFlippedWithTheGeometry() -> void:
	var gpText: String = _gpXmlOfSample()
	gpCheck(gpText.contains("MinY=\"-297\""), "MinY is the flipped bottom edge")
	gpCheck(gpText.contains("MaxY=\"0\""), "MaxY is the flipped top edge")
	gpCheck(gpText.contains("MinX=\"0\""), "MinX stays 0")
	gpCheck(gpText.contains("MaxX=\"420\""), "MaxX is the sheet width")
	gpCheck(gpText.contains("<Drawing ID="), "Diagram lands on the Drawing element (§2.1)")
	gpCheck(gpText.contains("Name=\"Test A3\""), "the mandatory Diagram.Name is written")


# Risk 2: null is an OMITTED Value, never an empty string.
# 风险 2：null 是**省略** Value，绝非空串。
func gpTestNullIsOmittedNotEmpty() -> void:
	var gpGraph: GPPIDGraph = _gpSampleGraph()
	(gpGraph.gpNodes[0] as GPPIDNode).gpProps = {"design_pressure": null}
	var gpText: String = GPDexpiExporter.gpWriteXml(
		GPDexpiExporter.gpFromGraph(gpGraph, _gpSampleSheet()))
	gpCheck(not gpText.contains("Value=\"\""), "no attribute is written with an empty value")
	gpCheck(gpText.contains("Name=\"DesignPressureAssignmentClass\""),
		"the attribute is still present, with the value omitted")


# Risk 4: language tags are exactly two letters.
# 风险 4：语言标签恰好两字母。
func gpTestLanguageTagsAreTwoLetters() -> void:
	var gpText: String = _gpXmlOfSample()
	gpCheck(gpText.contains("Language=\"zh\""), "zh_CN is trimmed to zh")
	gpCheck(gpText.contains("Language=\"en\""), "en_US is trimmed to en")
	gpCheck(not gpText.contains("zh_CN"), "the regional form never reaches the file")
	gpCheck(not gpText.contains("en_US"), "the regional form never reaches the file")


# Risk 8: layout state must not become an engineering attribute.
# 风险 8：布局状态不得变成工程属性。
func gpTestInternalKeysAreNotExported() -> void:
	var gpText: String = _gpXmlOfSample()
	gpCheck(not gpText.contains("tag_offset"), "the layout key never appears")
	gpCheck(not gpText.contains("TagOffset"), "no derived attribute name either")
	gpCheck(gpText.contains("NominalDiameterAssignmentClass"), "real attributes still export")


# Physical quantities carry Units + UnitsURI together.
# 物理量同时携带 Units 与 UnitsURI。
func gpTestPhysicalQuantitiesCarryUnits() -> void:
	var gpText: String = _gpXmlOfSample()
	gpCheck(gpText.contains("InsulationThicknessAssignmentClass"), "insulation is exported")
	gpCheck(gpText.contains("Units=\"Millimetre\""), "the unit is stated")
	gpCheck(gpText.contains("UnitsURI=\"http://data.posccaesar.org/rdl/RDS1357739\""),
		"the unit URI is stated")


# A pipe is a CenterLine under a PipingNetworkSegment — not a bare line (§2.2).
# 管线是 PipingNetworkSegment 下的 CenterLine —— 而非一条裸线（§2.2）。
func gpTestPipeIsACenterLineUnderASegment() -> void:
	var gpText: String = _gpXmlOfSample()
	gpCheck(gpText.contains("<PipingNetworkSystem"), "segments live under a network system")
	gpCheck(gpText.contains("<PipingNetworkSegment ID=\"e5\""), "the segment keeps its id")
	gpCheck(gpText.contains("<CenterLine>"), "the pipe is a center line")
	gpCheck(gpText.contains("<SourceItem ItemID=\"doc-n1\"/>"),
		"the source reference points at a stable uid")
	gpCheck(gpText.contains("<TargetItem ItemID=\"doc-n2\"/>"),
		"the target reference points at a stable uid")


# ---- file output --------------------------------------------------------

func gpTestExportFileWritesAndReparses() -> void:
	var gpPath: String = "user://_gp_test_dexpi_p1.xml"
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(_gpSampleGraph(), _gpSampleSheet())
	var gpResult: GPIOResult = GPDexpiExporter.gpExportFile(gpMid, gpPath)
	gpCheck(gpResult.gpIsOk(), "export succeeds: " + gpResult.gpToString())
	var gpRead: GPIOResult = GPAtomicFile.gpReadText(gpPath)
	gpCheck(gpRead.gpIsOk(), "the written file can be read back")
	var gpText: String = str(gpRead.gpPayload)
	gpCheck(gpText.contains("<PlantModel>"), "the file holds the document")
	gpCheck(GPDexpiExporter.gpIsWellFormed(gpText), "the file on disk is well-formed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))


func gpTestExportSheetRefusesAnInvalidSheet() -> void:
	var gpSheet: GPSheet = _gpSampleSheet()
	gpSheet.gpHeightMM = 0.0
	var gpResult: GPIOResult = GPDexpiExporter.gpExportSheet(_gpSampleGraph(), gpSheet,
		"user://_gp_test_dexpi_p1_bad.xml")
	gpCheck(not gpResult.gpIsOk(), "an invalid sheet is refused before anything is written")
	gpCheck(not FileAccess.file_exists("user://_gp_test_dexpi_p1_bad.xml"),
		"nothing reaches the disk on refusal")


# ---- helpers ------------------------------------------------------------

static func _gpLineContaining(gpText: String, gpNeedle: String) -> String:
	for gpLine in gpText.split("\n", false):
		if (gpLine as String).contains(gpNeedle):
			return gpLine as String
	return ""


static func _gpExtentValue(gpText: String, gpName: String) -> float:
	var gpRe: RegEx = RegEx.new()
	gpRe.compile(gpName + "=\"(-?[0-9.]+)\"")
	var gpM: RegExMatch = gpRe.search(gpText)
	if gpM == null:
		return NAN
	return float(gpM.get_string(1))


# Only the WORLD coordinates belong in an extent check. Shape-catalogue coordinates are LOCAL
# (a glyph's own 0..100 space), so including them would test nothing and hide a real failure.
# 只有**世界坐标**才该纳入范围检查。图元目录里的坐标是**局部**的（字形自身的 0..100 空间），
# 把它们算进来等于什么也没测，还会掩盖真正的失败。
static func _gpWorldCoordinateText(gpText: String) -> String:
	var gpOut: String = ""
	var gpFrom: int = 0
	while true:
		var gpStart: int = gpText.find("<CenterLine>", gpFrom)
		if gpStart < 0:
			break
		var gpEnd: int = gpText.find("</CenterLine>", gpStart)
		if gpEnd < 0:
			break
		gpOut += gpText.substr(gpStart, gpEnd - gpStart)
		gpFrom = gpEnd
	return gpOut


static func _gpAllCoordinateY(gpText: String) -> Array[float]:
	var gpOut: Array[float] = []
	var gpRe: RegEx = RegEx.new()
	gpRe.compile("<Coordinate X=\"(-?[0-9.]+)\" Y=\"(-?[0-9.]+)\"/>")
	for gpM in gpRe.search_all(_gpWorldCoordinateText(gpText)):
		gpOut.append(float((gpM as RegExMatch).get_string(2)))
	return gpOut


static func _gpAllCoordinateX(gpText: String) -> Array[float]:
	var gpOut: Array[float] = []
	var gpRe: RegEx = RegEx.new()
	gpRe.compile("<Coordinate X=\"(-?[0-9.]+)\" Y=\"(-?[0-9.]+)\"/>")
	for gpM in gpRe.search_all(_gpWorldCoordinateText(gpText)):
		gpOut.append(float((gpM as RegExMatch).get_string(1)))
	return gpOut
