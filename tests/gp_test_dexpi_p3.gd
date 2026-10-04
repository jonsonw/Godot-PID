extends "res://tests/gp_test.gd"
# P3 acceptance: the import path — Reader, Validator, Importer — proven by ROUND TRIP against
# the exporter's own output (§8.4: "自产自销 — use your own export as the import test case").
# P3 验收：导入链路 —— Reader、Validator、Importer —— 以**往返**方式对着导出器自己的产出验证
# （§8.4：「自产自销」）。
#
# The strongest assertion here is not "it imported" but "the EXISTING import gate accepts the
# container we produced". GPProjectImport.gpValidate() is the pipeline every other import goes
# through; passing it means a DEXPI file gets uid-collision handling, tag de-duplication and
# non-destructive merge for free.
# 此处最强的断言不是「导入成功了」，而是「**既有**导入门禁接受我们产出的容器」。
# GPProjectImport.gpValidate() 是其它所有导入都走的管线；通过它意味着
# DEXPI 文件免费获得 uid 冲突处理、位号去重与非破坏合并。

const GP_SHEET_W: float = 420.0
const GP_SHEET_H: float = 297.0


static func _gpSheet() -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpName = "P3 Sheet"
	gpSheet.gpWidthMM = GP_SHEET_W
	gpSheet.gpHeightMM = GP_SHEET_H
	return gpSheet


static func _gpGraph() -> GPPIDGraph:
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	var gpPump: GPPIDNode = gpGraph.gpNewNode("n1", "DPUMP001", "P-1001", Vector2(120.0, 90.0))
	gpPump.gpUid = "doc-n1"
	gpPump.gpNames = {"zh_CN": "离心泵"}
	gpPump.gpProps = {"design_pressure": 1.5}
	gpGraph.gpAddNode(gpPump)
	var gpTank: GPPIDNode = gpGraph.gpNewNode("n2", "DTANK001", "T-1002", Vector2(320.0, 210.0))
	gpTank.gpUid = "doc-n2"
	gpGraph.gpAddNode(gpTank)
	var gpEdge: GPPIDEdge = GPPIDEdge.new()
	gpEdge.gpInstanceId = "e5"
	gpEdge.gpFromRef = {"node_id": "n1", "port_id": "out"}
	gpEdge.gpToRef = {"node_id": "n2", "port_id": "top"}
	gpEdge.gpRouting = [Vector2(220.0, 150.0)]
	gpEdge.gpTag = "PL-1002"
	gpEdge.gpAttrs = {"dn": "100", "medium": "水"}
	gpGraph.gpEdges.append(gpEdge)
	return gpGraph


static func _gpXml() -> String:
	return GPDexpiExporter.gpWriteXml(GPDexpiExporter.gpFromGraph(_gpGraph(), _gpSheet()))


static func _gpRead() -> Dictionary:
	var gpResult: GPIOResult = GPDexpiReader.gpReadXml(_gpXml())
	if not gpResult.gpIsOk():
		return {}
	return gpResult.gpPayload as Dictionary


# ---- reader -------------------------------------------------------------

func gpTestReaderAcceptsOurOwnExport() -> void:
	var gpResult: GPIOResult = GPDexpiReader.gpReadXml(_gpXml())
	gpCheck(gpResult.gpIsOk(), "our own export is readable: " + gpResult.gpToString())
	var gpMid: Dictionary = gpResult.gpPayload as Dictionary
	gpCheck(not gpMid.is_empty(), "a structure came back")


# fatal: the root must be <PlantModel> (§7.3).
# fatal：根必须是 <PlantModel>（§7.3）。
func gpTestReaderRefusesANonPlantModelRoot() -> void:
	var gpResult: GPIOResult = GPDexpiReader.gpReadXml(
		"<?xml version=\"1.0\"?><SomethingElse><Equipment ID=\"x\"/></SomethingElse>")
	gpCheck(not gpResult.gpIsOk(), "a foreign root is fatal")
	gpCheck(gpResult.gpFailedWith(GPDexpiReader.GP_CODE_NOT_PLANT_MODEL),
		"the failure names the reason")


func gpTestReaderRefusesUnparsableText() -> void:
	gpCheck(not GPDexpiReader.gpReadXml("").gpIsOk(), "an empty document is fatal")
	gpCheck(not GPDexpiReader.gpReadXml("   ").gpIsOk(), "a blank document is fatal")


# The round trip is a COMPARISON, not a translation: the intermediate structure must match.
# 往返是一次**比较**而非翻译：中间结构必须吻合。
func gpTestRoundTripReturnsAnEquivalentStructure() -> void:
	var gpOriginal: Dictionary = GPDexpiExporter.gpFromGraph(_gpGraph(), _gpSheet())
	var gpBack: Dictionary = _gpRead()
	gpEq((gpBack.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array).size(),
		(gpOriginal.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array).size(),
		"the same number of equipment came back")
	gpEq((gpBack.get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array).size(), 1,
		"the same number of segments came back")
	var gpEq1: Dictionary = (gpBack.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array)[0] as Dictionary
	gpEq(str(gpEq1.get("id", "")), "doc-n1", "the stable id survived")
	gpEq(str(gpEq1.get("class", "")), "CentrifugalPump", "the component class survived")
	gpEq(str(gpEq1.get("tag", "")), "P-1001", "the tag survived")
	gpEq(str(gpEq1.get("uri", "")), GPDexpiSchema.GP_URI_CENTRIFUGAL_PUMP,
		"the verified URI survived")


func gpTestRoundTripRestoresGeometryThroughTheFlip() -> void:
	var gpOriginal: Dictionary = GPDexpiExporter.gpFromGraph(_gpGraph(), _gpSheet())
	var gpOriginalPts: Array = ((gpOriginal.get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array)[0]
		as Dictionary).get("points", []) as Array
	var gpBackPts: Array = ((_gpRead().get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array)[0]
		as Dictionary).get("points", []) as Array
	gpEq(gpBackPts.size(), gpOriginalPts.size(), "the same number of points came back")
	var gpI: int = 0
	while gpI < min(gpBackPts.size(), gpOriginalPts.size()):
		var gpA: Vector2 = gpOriginalPts[gpI] as Vector2
		var gpB: Vector2 = gpBackPts[gpI] as Vector2
		gpApprox(gpB.x, gpA.x, 1e-4, "point " + str(gpI) + " X round-trips")
		gpApprox(gpB.y, gpA.y, 1e-4, "point " + str(gpI) + " Y round-trips")
		gpI += 1


func gpTestRoundTripRestoresTheExtent() -> void:
	var gpDiagram: Dictionary = _gpRead().get(GPDexpiExporter.GP_KEY_DIAGRAM, {}) as Dictionary
	gpEq(str(gpDiagram.get("name", "")), "P3 Sheet", "the sheet name came back")
	gpApprox(float(gpDiagram.get("min_y", -1.0)), 0.0, 1e-6, "MinY came back in concept space")
	gpApprox(float(gpDiagram.get("max_y", -1.0)), GP_SHEET_H, 1e-6, "MaxY came back")
	gpApprox(float(gpDiagram.get("max_x", -1.0)), GP_SHEET_W, 1e-6, "MaxX came back")


func gpTestRoundTripRestoresPoseAndAttributes() -> void:
	var gpUsages: Array = _gpRead().get(GPDexpiExporter.GP_KEY_USAGES, []) as Array
	gpCheck(gpUsages.size() >= 1, "usages came back")
	var gpU: Dictionary = gpUsages[0] as Dictionary
	var gpPos: Vector2 = gpU.get("position", Vector2.ZERO) as Vector2
	gpApprox(gpPos.x, 120.0, 1e-6, "the node's X position came back")
	gpApprox(gpPos.y, 90.0, 1e-6, "the node's Y position came back")
	var gpEquip: Dictionary = (_gpRead().get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array)[0] as Dictionary
	# names keyed by the two-letter tag, props by the reverse-mapped snake_case key.
	# names 以两字母标签为键，props 以反向映射的 snake_case 键为键。
	gpEq(str((gpEquip.get("names", {}) as Dictionary).get("zh", "")), "离心泵",
		"the Chinese name came back under 'zh'")
	gpApprox(float((gpEquip.get("props", {}) as Dictionary).get("design_pressure", 0.0)), 1.5,
		1e-6, "the property came back under its snake_case key")


# ---- validator ----------------------------------------------------------

func gpTestValidatorAcceptsOurOwnExport() -> void:
	var gpReport: GPImportReport = GPDexpiValidator.gpValidate(_gpRead())
	gpCheck(not gpReport.gpHasErrors(), "our own export has no structural error: "
		+ gpReport.gpSummary())


# A missing URI is a warning, never a fabricated one (§7.5 ④).
# 缺失的 URI 是 warning，绝不是一个臆造的 URI（§7.5 ④）。
func gpTestMissingUriIsWarnedNotInvented() -> void:
	var gpReport: GPImportReport = GPDexpiValidator.gpValidate(_gpRead())
	var gpFound: bool = false
	for gpE in gpReport.gpEntries:
		if str((gpE as Dictionary).get("code", "")) == GPDexpiValidator.GP_CODE_MISSING_URI:
			gpFound = true
	gpCheck(gpFound, "the tank's missing URI is reported")
	gpCheck(not gpReport.gpHasErrors(), "but it is not an error — the object is still usable")


func gpTestMissingComponentClassIsAnError() -> void:
	var gpMid: Dictionary = _gpRead()
	((gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array)[0] as Dictionary)["class"] = ""
	var gpReport: GPImportReport = GPDexpiValidator.gpValidate(gpMid)
	gpCheck(gpReport.gpHasErrors(), "an object without a ComponentClass is unusable (§7.3)")


# A document with no <Drawing> is legal: concept only (§7.5 ②).
# 没有 <Drawing> 的文档是合法的：仅概念层（§7.5 ②）。
func gpTestNoDiagramIsLegalAndReported() -> void:
	var gpMid: Dictionary = _gpRead()
	gpMid.erase(GPDexpiExporter.GP_KEY_DIAGRAM)
	var gpReport: GPImportReport = GPDexpiValidator.gpValidate(gpMid)
	gpCheck(not gpReport.gpHasErrors(), "a diagram-less document is not an error")
	var gpFound: bool = false
	for gpE in gpReport.gpEntries:
		if str((gpE as Dictionary).get("code", "")) == GPDexpiValidator.GP_CODE_NO_DIAGRAM:
			gpFound = true
	gpCheck(gpFound, "and it is reported as information")


func gpTestDanglingReferenceIsAnError() -> void:
	var gpMid: Dictionary = _gpRead()
	((gpMid.get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array)[0] as Dictionary)["from_uid"] = "ghost"
	var gpReport: GPImportReport = GPDexpiValidator.gpValidate(gpMid)
	gpCheck(gpReport.gpHasErrors(), "a reference to an absent object is an error")


func gpTestUnknownClassDegradesToAWarning() -> void:
	var gpMid: Dictionary = _gpRead()
	((gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array)[0] as Dictionary)["class"] = "Unobtainium"
	var gpReport: GPImportReport = GPDexpiValidator.gpValidate(gpMid)
	gpCheck(not gpReport.gpHasErrors(), "an unknown class is degraded, not rejected")
	var gpFound: bool = false
	for gpE in gpReport.gpEntries:
		if str((gpE as Dictionary).get("code", "")) == GPDexpiValidator.GP_CODE_UNKNOWN_CLASS:
			gpFound = true
	gpCheck(gpFound, "and the unknown class is named in the report")


func gpTestEmptyStructureIsFatal() -> void:
	var gpReport: GPImportReport = GPDexpiValidator.gpValidate({})
	gpCheck(gpReport.gpHasErrors(), "an empty structure cannot form a model")


# ---- importer -----------------------------------------------------------

# ★ THE DEFINING ASSERTION OF P3 / P3 的决定性断言：
# the container we produce must satisfy the pipeline every other import already satisfies.
# 我们产出的容器必须满足其它所有导入都已满足的那条管线。
func gpTestProducedContainerPassesTheExistingImportGate() -> void:
	var gpV3: Dictionary = GPDexpiImporter.gpToV3(_gpRead())
	gpCheck(not gpV3.is_empty(), "a container was produced")
	var gpReport: GPImportReport = GPImportReport.new()
	GPProjectImport.gpValidate(gpV3, gpReport)
	gpCheck(not gpReport.gpHasErrors(),
		"the existing import gate accepts it: " + gpReport.gpSummary())
	gpEq(int(gpReport.gpStats.get("nodes", 0)), 2, "two nodes reached the gate")
	gpEq(int(gpReport.gpStats.get("edges", 0)), 1, "one edge reached the gate")


func gpTestContainerCarriesIdentityAndTopology() -> void:
	var gpV3: Dictionary = GPDexpiImporter.gpToV3(_gpRead())
	var gpSheets: Array = gpV3.get("sheets", []) as Array
	gpEq(gpSheets.size(), 1, "one sheet")
	var gpNodes: Array = (gpSheets[0] as Dictionary).get("nodes", []) as Array
	var gpEdges: Array = (gpSheets[0] as Dictionary).get("edges", []) as Array
	gpEq(gpNodes.size(), 2, "two nodes")
	gpEq(gpEdges.size(), 1, "one edge")
	var gpN0: Dictionary = gpNodes[0] as Dictionary
	gpEq(str(gpN0.get("uid", "")), "doc-n1", "the node keeps its stable uid")
	gpEq(str(gpN0.get("symbol_id", "")), "DPUMP001",
		"the ComponentClass was reverse-mapped back to a local symbol")
	gpEq(str(gpN0.get("tag", "")), "P-1001", "the tag came through")
	var gpE0: Dictionary = gpEdges[0] as Dictionary
	gpEq(str((gpE0.get("from_ref", {}) as Dictionary).get("node_id", "")), "doc-n1",
		"the edge references the STABLE uid, not an instance id")
	gpEq(str((gpE0.get("to_ref", {}) as Dictionary).get("node_id", "")), "doc-n2",
		"so the reference survives uid reassignment on merge")


# Routing stores BENDS ONLY, so the endpoints read back must NOT be duplicated into it.
# routing **只存折点**，故读回的端点**不得**被重复写进去。
func gpTestRoutingKeepsBendsOnly() -> void:
	var gpV3: Dictionary = GPDexpiImporter.gpToV3(_gpRead())
	var gpEdges: Array = ((gpV3.get("sheets", []) as Array)[0] as Dictionary).get("edges", []) as Array
	var gpRouting: Array = (gpEdges[0] as Dictionary).get("routing", []) as Array
	gpEq(gpRouting.size(), 1, "three file points yield one stored bend")
	gpApprox(float((gpRouting[0] as Array)[0]), 220.0, 1e-6, "the bend X is preserved")
	gpApprox(float((gpRouting[0] as Array)[1]), 150.0, 1e-6, "the bend Y is preserved")


# An unknown class must not lose the object: it keeps a placeholder symbol, and the original
# class stays recoverable through the Custom convention.
# 未知类不得丢失对象：它保留一个占位图元，且原类通过 Custom 约定仍可恢复。
func gpTestUnknownClassStillProducesANode() -> void:
	var gpMid: Dictionary = _gpRead()
	((gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array)[0] as Dictionary)["class"] = "CustomDPUMP001"
	var gpV3: Dictionary = GPDexpiImporter.gpToV3(gpMid)
	var gpNodes: Array = ((gpV3.get("sheets", []) as Array)[0] as Dictionary).get("nodes", []) as Array
	gpEq(str((gpNodes[0] as Dictionary).get("symbol_id", "")), "DPUMP001",
		"the CustomDPUMP001 convention recovers the original symbol id")


func gpTestEmptyStructureProducesNoContainer() -> void:
	gpCheck(GPDexpiImporter.gpToV3({}).is_empty(), "no container from nothing")
