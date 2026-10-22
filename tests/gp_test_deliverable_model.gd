extends "res://tests/gp_test.gd"
# P1 acceptance: the four deliverable row sets and their classification rules.
# P1 验收：四类交付行集与分类规则。
#
# What is pinned here / 此处钉住什么：
#   1. LINE = one row per line number, not per edge; a valve split does not create two rows.
#      管线 = 一个管线号一行，不是一条边一行；阀门切开不产生两行。
#   2. VALVES live in the line's `valves` column and in the Valve List; FITTINGS appear nowhere.
#      阀门进管线 `valves` 列与阀门表；管件哪里都不出现。
#   3. EQUIPMENT / INSTRUMENT / VALVE are mutually exclusive; mounted children are not rows.
#      设备 / 仪表 / 阀门互斥；挂载子件不成行。
#   4. Sorting is natural + deterministic; the same input produces the same JSON twice.
#      排序为自然序 + 确定性；同一输入两次构建 JSON 一致。
#   5. Missing / duplicate / dangling / unknown data is REPORTED, never silently dropped.
#      缺失 / 重复 / 悬空 / 未知数据必须报告，绝不静默丢弃。
#
# No FileAccess, no UI, no xlsx here: P1 is model-only.
# 本套件不碰 FileAccess / UI / xlsx：P1 只做模型。

const GP_EPS: float = 0.001


# ==================== fixtures / 夹具 ====================

func _gpDefs() -> Array[GPSymbolDef]:
	return GPSymbolLibrary.gpDefaultDefs()


# Headless stand-in for the UI's I18n resolution. The model itself must not call I18n.
# UI 的 I18n 解析在 headless 的替身；模型本身不得调用 I18n。
func _gpTypeLabels() -> Dictionary:
	return {
		"DPUMP001": "离心泵",
		"DTANK001": "储罐",
		"DHEAT001": "换热器",
		"DVALVE002": "球阀",
		"DINSTRUMENT001": "变送器",
		"DGENERAL010": "异径管",
		"DGENERAL008": "管口",
	}


func _gpOptions() -> Dictionary:
	return {"locale": "zh", "type_labels": _gpTypeLabels()}


func _gpDef(gpId: String) -> GPSymbolDef:
	for gpDef in _gpDefs():
		if gpDef.gpId == gpId:
			return gpDef
	return null


func _gpSheet(gpId: String, gpName: String, gpIndex: int) -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpId = gpId
	gpSheet.gpName = gpName
	gpSheet.gpIndex = gpIndex
	gpSheet.gpGraph = GPPIDGraph.new()
	return gpSheet


func _gpNode(gpGraph: GPPIDGraph, gpId: String, gpSymbolId: String, gpTag: String,
		gpPos: Vector2) -> GPPIDNode:
	var gpNode: GPPIDNode = gpGraph.gpNewNode(gpId, gpSymbolId, gpTag, gpPos)
	gpGraph.gpAddNode(gpNode)
	return gpNode


func _gpMounted(gpGraph: GPPIDGraph, gpId: String, gpSymbolId: String, gpTag: String,
		gpPos: Vector2, gpParentId: String, gpAnchor: String) -> GPPIDNode:
	var gpNode: GPPIDNode = _gpNode(gpGraph, gpId, gpSymbolId, gpTag, gpPos)
	gpNode.gpParentUid = gpParentId
	gpNode.gpMountAnchor = gpAnchor
	return gpNode


func _gpEdge(gpGraph: GPPIDGraph, gpId: String, gpFromId: String, gpFromPort: String,
		gpToId: String, gpToPort: String, gpKind: String, gpTag: String,
		gpAttrs: Dictionary = {}, gpSignalType: String = "") -> GPPIDEdge:
	var gpEdge: GPPIDEdge = gpGraph.gpNewEdgeEx(gpId,
		{"node_id": gpFromId, "port_id": gpFromPort},
		{"node_id": gpToId, "port_id": gpToPort},
		gpKind, gpSignalType, gpTag, gpAttrs)
	gpGraph.gpAddEdge(gpEdge)
	return gpEdge


# Two sheets used by most assertions. / 大多数断言使用的两张图纸。
func _gpTwoSheets() -> Array[GPSheet]:
	var gpSheet1: GPSheet = _gpSheet("s1", "P&ID 1", 0)
	var gpGraph1: GPPIDGraph = gpSheet1.gpGraph
	var gpPump: GPPIDNode = _gpNode(gpGraph1, "n1", "DPUMP001", "P-101", Vector2(100.0, 100.0))
	var gpTank: GPPIDNode = _gpNode(gpGraph1, "n2", "DTANK001", "T-201", Vector2(500.0, 100.0))
	var gpValve: GPPIDNode = _gpNode(gpGraph1, "n3", "DVALVE002", "V-301", Vector2(300.0, 100.0))
	_gpNode(gpGraph1, "n4", "DGENERAL010", "R-401", Vector2(300.0, 300.0))
	var gpNozzle: GPPIDNode = _gpMounted(gpGraph1, "n5", "DGENERAL008", "N1",
		Vector2(460.0, 100.0), "n2", "ves_right_nozzle")
	var gpInstr: GPPIDNode = _gpNode(gpGraph1, "n6", "DINSTRUMENT001", "PT-1001",
		Vector2(300.0, 300.0))

	var gpAttrs: Dictionary = {"dn": "DN80", "spec": "A1A", "medium": "矿浆", "insulation": "50"}
	_gpEdge(gpGraph1, "e1", gpPump.gpInstanceId, "out", gpValve.gpInstanceId, "in",
		GPPIDEdge.GP_PROCESS, "L-1", gpAttrs)
	_gpEdge(gpGraph1, "e2", gpValve.gpInstanceId, "out", gpNozzle.gpInstanceId, "pipe",
		GPPIDEdge.GP_PROCESS, "L-1", gpAttrs)
	var gpAttrs2: Dictionary = {"dn": "DN50", "spec": "A2", "medium": "水", "insulation": "30"}
	_gpEdge(gpGraph1, "e3", gpTank.gpInstanceId, "bottom", "n4", "in",
		GPPIDEdge.GP_PROCESS, "L-2", gpAttrs2)
	_gpEdge(gpGraph1, "e4", "n4", "out", gpPump.gpInstanceId, "in",
		GPPIDEdge.GP_PROCESS, "L-2", gpAttrs2)
	_gpEdge(gpGraph1, "e5", gpTank.gpInstanceId, "left", gpInstr.gpInstanceId, "proc",
		GPPIDEdge.GP_PROCESS, "L-3", {"dn": "DN25"})
	_gpEdge(gpGraph1, "e6", gpInstr.gpInstanceId, "sig", gpValve.gpInstanceId, "in",
		GPPIDEdge.GP_SIGNAL, "S-1", {}, "ELECTRIC")

	var gpSheet2: GPSheet = _gpSheet("s2", "P&ID 2", 1)
	var gpGraph2: GPPIDGraph = gpSheet2.gpGraph
	var gpHeat: GPPIDNode = _gpNode(gpGraph2, "n21", "DHEAT001", "E-301", Vector2(100.0, 100.0))
	var gpValve2: GPPIDNode = _gpNode(gpGraph2, "n22", "DVALVE002", "V-302", Vector2(300.0, 100.0))
	var gpInstr2: GPPIDNode = _gpNode(gpGraph2, "n23", "DINSTRUMENT001", "TI-1002",
		Vector2(300.0, 300.0))
	_gpEdge(gpGraph2, "e21", gpHeat.gpInstanceId, "shell_out", gpValve2.gpInstanceId, "in",
		GPPIDEdge.GP_PROCESS, "L-4", {"dn": "DN100"})
	_gpEdge(gpGraph2, "e22", gpValve2.gpInstanceId, "out", gpHeat.gpInstanceId, "shell_in",
		GPPIDEdge.GP_PROCESS, "L-4", {"dn": "DN100"})
	_gpEdge(gpGraph2, "e23", gpHeat.gpInstanceId, "shell_in", gpInstr2.gpInstanceId, "proc",
		GPPIDEdge.GP_PROCESS, "L-5", {"dn": "DN25"})
	var gpOut: Array[GPSheet] = [gpSheet1, gpSheet2]
	return gpOut


func _gpRows(gpResult: Dictionary) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	for gpRowRaw in (gpResult.get("rows", []) as Array):
		gpOut.append(gpRowRaw as Dictionary)
	return gpOut


func _gpRowBy(gpRows: Array[Dictionary], gpKey: String, gpValue: String) -> Dictionary:
	for gpRow in gpRows:
		if str(gpRow.get(gpKey, "")) == gpValue:
			return gpRow
	return {}


func _gpIssueCodes(gpResult: Dictionary) -> Array[String]:
	var gpOut: Array[String] = []
	for gpIssueRaw in (gpResult.get("issues", []) as Array):
		var gpIssue: Dictionary = gpIssueRaw as Dictionary
		var gpCode: String = str(gpIssue.get("code", ""))
		if not gpOut.has(gpCode):
			gpOut.append(gpCode)
	return gpOut


func _gpCountByList(gpAll: Dictionary, gpList: String) -> int:
	var gpResult: Dictionary = gpAll.get(gpList, {}) as Dictionary
	return int(gpResult.get("count", 0))


# ==================== 1. line grouping / 管线分组 ====================

func gpTestLineGroupsByNumberNotByEdge() -> void:
	var gpAll: Dictionary = GPDeliverableModel.gpBuildAll(_gpTwoSheets(), _gpDefs(), _gpOptions())
	var gpLines: Array[Dictionary] = _gpRows(gpAll["line"] as Dictionary)
	gpEq(gpLines.size(), 5, "five line numbers: L-1..L-5; S-1 is a signal edge and is excluded")
	var gpL1: Dictionary = _gpRowBy(gpLines, "line_no", "L-1")
	gpEq(str(gpL1.get("segment_count", 0)), "2", "L-1 is split by a valve into two edges but is one row")
	gpEq(str(gpL1.get("from", "")), "P-101", "L-1 starts at the pump")
	gpEq(str(gpL1.get("to", "")), "N1", "L-1 ends at the nozzle")
	gpEq(str(gpL1.get("to_equipment", "")), "T-201", "the nozzle's host equipment is the tank")
	gpEq(str(gpL1.get("valves", "")), "V-301", "L-1 lists its valve")
	gpEq(int(gpL1.get("valve_count", 0)), 1, "one valve on L-1")
	gpEq(str(gpL1.get("dn", "")), "DN80", "edge attribute dn is carried")
	gpEq(str(gpL1.get("spec", "")), "A1A", "edge attribute spec is carried")
	gpEq(str(gpL1.get("medium", "")), "矿浆", "edge attribute medium is carried")
	gpEq(str(gpL1.get("insulation", "")), "50", "edge attribute insulation is carried")
	gpCheck(float(gpL1.get("length_m", 0.0)) > GP_EPS, "length is computed from the resolved polyline")


func gpTestFittingsAreNotExportedAndNotInValves() -> void:
	var gpAll: Dictionary = GPDeliverableModel.gpBuildAll(_gpTwoSheets(), _gpDefs(), _gpOptions())
	var gpLines: Array[Dictionary] = _gpRows(gpAll["line"] as Dictionary)
	var gpL2: Dictionary = _gpRowBy(gpLines, "line_no", "L-2")
	gpEq(str(gpL2.get("valves", "")), "", "a reducer on L-2 is a fitting, not a valve")
	gpEq(int(gpL2.get("valve_count", 0)), 0, "no valve on L-2")
	gpEq(str(gpL2.get("segment_count", 0)), "2", "L-2 still has two segments")
	# The reducer must not appear in ANY equipment/valve row either.
	var gpEquipment: Array[Dictionary] = _gpRows(gpAll["equipment"] as Dictionary)
	var gpValves: Array[Dictionary] = _gpRows(gpAll["valve"] as Dictionary)
	gpEq(_gpRowBy(gpEquipment, "tag", "R-401").size(), 0, "the reducer is not an equipment row")
	gpEq(_gpRowBy(gpValves, "tag", "R-401").size(), 0, "the reducer is not a valve row")


# ==================== 2. mutual exclusion / 互斥 ====================

func gpTestEquipmentInstrumentValveAreMutuallyExclusive() -> void:
	var gpAll: Dictionary = GPDeliverableModel.gpBuildAll(_gpTwoSheets(), _gpDefs(), _gpOptions())
	var gpEquipment: Array[Dictionary] = _gpRows(gpAll["equipment"] as Dictionary)
	var gpInstruments: Array[Dictionary] = _gpRows(gpAll["instrument"] as Dictionary)
	var gpValves: Array[Dictionary] = _gpRows(gpAll["valve"] as Dictionary)
	gpEq(gpEquipment.size(), 3, "P-101, T-201 and E-301")
	gpCheck(_gpRowBy(gpEquipment, "tag", "P-101").size() > 0, "pump is equipment")
	gpCheck(_gpRowBy(gpEquipment, "tag", "T-201").size() > 0, "tank is equipment")
	gpCheck(_gpRowBy(gpEquipment, "tag", "V-301").size() == 0, "valve is NOT equipment")
	gpCheck(_gpRowBy(gpEquipment, "tag", "PT-1001").size() == 0, "instrument is NOT equipment")
	gpCheck(_gpRowBy(gpEquipment, "tag", "N1").size() == 0, "mounted nozzle is NOT a row")
	gpEq(gpInstruments.size(), 2, "PT-1001 and TI-1002")
	gpCheck(_gpRowBy(gpInstruments, "tag", "PT-1001").size() > 0, "instrument row exists")
	gpEq(gpValves.size(), 2, "V-301 and V-302")
	gpCheck(_gpRowBy(gpValves, "tag", "V-301").size() > 0, "valve row exists")
	# The tank's nozzle is summarised on the host, not its own row.
	var gpTank: Dictionary = _gpRowBy(gpEquipment, "tag", "T-201")
	gpEq(int(gpTank.get("nozzle_count", 0)), 1, "the tank counts its mounted nozzle")


func gpTestValveRowCarriesLineAndSchema() -> void:
	var gpAll: Dictionary = GPDeliverableModel.gpBuildAll(_gpTwoSheets(), _gpDefs(), _gpOptions())
	var gpValves: Array[Dictionary] = _gpRows(gpAll["valve"] as Dictionary)
	var gpV301: Dictionary = _gpRowBy(gpValves, "tag", "V-301")
	gpEq(str(gpV301.get("line_no", "")), "L-1", "the valve names the line it sits on")
	gpEq(str(gpV301.get("type", "")), "球阀", "the valve type is the library display name")
	gpCheck(str(gpV301.get("class", "")) == "BallValve", "the valve class comes from the DEXPI map")
	gpEq(int(gpV301.get("qty", 0)), 1, "qty defaults to one")


func gpTestInstrumentConnectivityAndLoop() -> void:
	var gpAll: Dictionary = GPDeliverableModel.gpBuildAll(_gpTwoSheets(), _gpDefs(), _gpOptions())
	var gpInstruments: Array[Dictionary] = _gpRows(gpAll["instrument"] as Dictionary)
	var gpPT: Dictionary = _gpRowBy(gpInstruments, "tag", "PT-1001")
	gpEq(str(gpPT.get("loop_no", "")), "1001", "loop number is the first digit run of the tag")
	gpEq(str(gpPT.get("connected_line", "")), "L-3", "the process-side line is reported")
	gpCheck(str(gpPT.get("connected_equipment", "")).find("T-201") >= 0,
		"the connected equipment is reported")
	gpEq(str(gpPT.get("signal_type", "")), "电气", "signal type falls back to the signal edge")


# ==================== 3. fields & classification ====================

func gpTestFieldCatalogueDefaults() -> void:
	gpEq(GPDeliverableFields.gpListIds().size(), 4, "four lists")
	var gpLineFields: Array[String] = GPDeliverableFields.gpFieldsOf("line")
	gpCheck(gpLineFields.has("valves"), "line keeps the valves column")
	gpCheck(gpLineFields.has("valve_count"), "valve_count is available")
	var gpDefault: Array[String] = GPDeliverableFields.gpDefaultColumns("line")
	gpCheck(gpDefault.has("valves"), "valves is a default column")
	gpCheck(not gpDefault.has("valve_count"), "valve_count is optional, not default")
	gpCheck(GPDeliverableFields.gpIsWritable("dn"), "dn is writable")
	gpCheck(not GPDeliverableFields.gpIsWritable("tag"), "tag is the key, never writable")
	gpEq(GPDeliverableFields.gpSource("dn"), "edge.attr:dn", "edge attributes have their own source")
	gpEq(GPDeliverableFields.gpNormalizeHeader("管线号 Line No."), "管线号lineno",
		"header normalisation drops spaces/punctuation and lower-cases")
	gpEq(GPDeliverableFields.gpCoerce("design_pressure", "1.25"), 1.25,
		"numeric coercion parses the cell text")
	gpEq(GPDeliverableFields.gpCoerce("qty", ""), null, "a blank numeric cell stays null, not zero")


func gpTestClassificationCoverageOfBuiltins() -> void:
	var gpKinds: Dictionary = {}
	for gpDef in _gpDefs():
		# Only built-ins are contractual; user packs are allowed to be "unknown" (equipment
		# fallback) and must not fail this coverage assertion.
		# 只有内置图元受契约约束；用户包允许是「未知→设备」兜底，不应让本覆盖断言失败。
		if not gpDef.gpBuiltin:
			continue
		var gpClass: Dictionary = GPDeliverableRules.gpClassificationOf(gpDef)
		var gpKind: String = str(gpClass.get("kind", ""))
		gpCheck(gpKind != GPDeliverableRules.GP_KIND_UNKNOWN,
			"builtin " + gpDef.gpId + " must have a concrete classification")
		gpKinds[gpKind] = true
	gpCheck(gpKinds.has(GPDeliverableRules.GP_KIND_EQUIPMENT), "some builtin is equipment")
	gpCheck(gpKinds.has(GPDeliverableRules.GP_KIND_INSTRUMENT), "some builtin is instrument")
	gpCheck(gpKinds.has(GPDeliverableRules.GP_KIND_VALVE), "some builtin is valve")
	gpCheck(gpKinds.has(GPDeliverableRules.GP_KIND_FITTING), "some builtin is fitting")
	gpCheck(gpKinds.has(GPDeliverableRules.GP_KIND_MOUNTED), "some builtin is mounted")
	gpCheck(gpKinds.has(GPDeliverableRules.GP_KIND_ANNOTATION), "some builtin is annotation")


# ==================== 4. sorting & determinism / 排序与确定性 ====================

func gpTestNaturalSorting() -> void:
	var gpSheet: GPSheet = _gpSheet("s-sort", "P&ID Sort", 0)
	var gpGraph: GPPIDGraph = gpSheet.gpGraph
	var gpPump: GPPIDNode = _gpNode(gpGraph, "n1", "DPUMP001", "P-10", Vector2(100.0, 100.0))
	var gpTank: GPPIDNode = _gpNode(gpGraph, "n2", "DTANK001", "P-2", Vector2(500.0, 100.0))
	_gpEdge(gpGraph, "e1", gpPump.gpInstanceId, "out", gpTank.gpInstanceId, "bottom",
		GPPIDEdge.GP_PROCESS, "L-10")
	_gpEdge(gpGraph, "e2", gpPump.gpInstanceId, "out", gpTank.gpInstanceId, "bottom",
		GPPIDEdge.GP_PROCESS, "L-2")
	var gpSheets: Array[GPSheet] = [gpSheet]
	var gpAll: Dictionary = GPDeliverableModel.gpBuildAll(gpSheets, _gpDefs(), _gpOptions())
	var gpEquipment: Array[Dictionary] = _gpRows(gpAll["equipment"] as Dictionary)
	gpEq(str(gpEquipment[0].get("tag", "")), "P-2", "P-2 sorts before P-10")
	gpEq(str(gpEquipment[1].get("tag", "")), "P-10", "P-10 sorts after P-2")
	var gpLines: Array[Dictionary] = _gpRows(gpAll["line"] as Dictionary)
	gpEq(str(gpLines[0].get("line_no", "")), "L-2", "L-2 sorts before L-10")
	gpEq(str(gpLines[1].get("line_no", "")), "L-10", "L-10 sorts after L-2")


func gpTestDeterministicRows() -> void:
	var gpSheets: Array[GPSheet] = _gpTwoSheets()
	var gpDefs: Array[GPSymbolDef] = _gpDefs()
	var gpFirst: Dictionary = GPDeliverableModel.gpBuildAll(gpSheets, gpDefs, _gpOptions())
	var gpSecond: Dictionary = GPDeliverableModel.gpBuildAll(gpSheets, gpDefs, _gpOptions())
	gpEq(JSON.stringify(gpFirst, "", true), JSON.stringify(gpSecond, "", true),
		"the same input produces byte-identical JSON twice")


# ==================== 5. issues / 问题报告 ====================

func gpTestIssuesAreReportedNotDropped() -> void:
	var gpSheet: GPSheet = _gpSheet("s-issues", "Issues", 0)
	var gpGraph: GPPIDGraph = gpSheet.gpGraph
	var gpPumpA: GPPIDNode = _gpNode(gpGraph, "i1", "DPUMP001", "P-1", Vector2(100.0, 100.0))
	var gpPumpB: GPPIDNode = _gpNode(gpGraph, "i2", "DPUMP001", "P-1", Vector2(200.0, 100.0))
	_gpNode(gpGraph, "i3", "DPUMP001", "", Vector2(300.0, 100.0))
	_gpNode(gpGraph, "i4", "DTANK001", "T-1", Vector2(500.0, 100.0))
	_gpNode(gpGraph, "i5", "DVALVE002", "V-1", Vector2(300.0, 300.0))
	_gpNode(gpGraph, "i6", "DINSTRUMENT001", "PT-2", Vector2(400.0, 300.0))
	_gpNode(gpGraph, "i7", "MISSING_SYMBOL", "X-1", Vector2(600.0, 100.0))
	_gpNode(gpGraph, "i8", "X-USER", "U-1", Vector2(700.0, 100.0))
	# An empty line number + a dangling end. / 空管线号 + 悬空端。
	_gpEdge(gpGraph, "i-e1", gpPumpA.gpInstanceId, "out", "i4", "bottom",
		GPPIDEdge.GP_PROCESS, "")
	var gpDangle: GPPIDEdge = gpGraph.gpNewEdgeEx("i-e2",
		{"node_id": gpPumpB.gpInstanceId, "port_id": "out"},
		{"point": [900.0, 900.0]}, GPPIDEdge.GP_PROCESS, "", "")
	gpGraph.gpAddEdge(gpDangle)
	var gpSheets: Array[GPSheet] = [gpSheet]
	var gpDefs: Array[GPSymbolDef] = []
	gpDefs.append_array(_gpDefs())
	var gpCustom: GPSymbolDef = GPSymbolDef.new()
	gpCustom.gpId = "X-USER"
	gpCustom.gpCategory = "general"
	gpCustom.gpDisplayName = "自定义"
	gpDefs.append(gpCustom)
	var gpAll: Dictionary = GPDeliverableModel.gpBuildAll(gpSheets, gpDefs, _gpOptions())
	var gpCodes: Array[String] = _gpIssueCodes(gpAll)
	gpCheck(gpCodes.has("data.tag_duplicate"), "duplicate P-1 is reported")
	gpCheck(gpCodes.has("data.tag_missing"), "the untagged pump is reported")
	gpCheck(gpCodes.has("data.unknown_symbol"), "the missing symbol definition is reported")
	gpCheck(gpCodes.has("data.unclassified_symbol"), "the unknown user symbol is reported")
	gpCheck(gpCodes.has("data.valve_no_line"), "the unconnected valve is reported")
	gpCheck(gpCodes.has("data.instrument_unconnected"), "the unconnected instrument is reported")
	gpCheck(gpCodes.has("data.line_no_missing"), "the empty line number is reported")
	gpCheck(gpCodes.has("data.line_dangling"), "the dangling edge is reported")
	# The unknown definition still yields an equipment row; it is not silently dropped.
	var gpEquipment: Array[Dictionary] = _gpRows(gpAll["equipment"] as Dictionary)
	gpCheck(_gpRowBy(gpEquipment, "tag", "X-1").size() > 0, "unknown definition still exports a row")
	gpCheck(_gpRowBy(gpEquipment, "tag", "U-1").size() > 0, "unknown user symbol falls back to equipment")
	gpCheck(_gpRowBy(gpEquipment, "tag", "P-1").size() > 0, "duplicate tags both keep their rows")


# ==================== 6. multi-sheet line / 跨图纸同号 ====================

func gpTestSameLineNumberAcrossSheetsMerges() -> void:
	var gpSheet1: GPSheet = _gpSheet("m1", "P&ID A", 0)
	var gpSheet2: GPSheet = _gpSheet("m2", "P&ID B", 1)
	var gpPump1: GPPIDNode = _gpNode(gpSheet1.gpGraph, "n1", "DPUMP001", "P-1",
		Vector2(100.0, 100.0))
	var gpTank1: GPPIDNode = _gpNode(gpSheet1.gpGraph, "n2", "DTANK001", "T-1",
		Vector2(500.0, 100.0))
	var gpPump2: GPPIDNode = _gpNode(gpSheet2.gpGraph, "n3", "DPUMP001", "P-2",
		Vector2(100.0, 100.0))
	var gpTank2: GPPIDNode = _gpNode(gpSheet2.gpGraph, "n4", "DTANK001", "T-2",
		Vector2(500.0, 100.0))
	_gpEdge(gpSheet1.gpGraph, "e1", gpPump1.gpInstanceId, "out", gpTank1.gpInstanceId, "bottom",
		GPPIDEdge.GP_PROCESS, "L-9")
	_gpEdge(gpSheet2.gpGraph, "e2", gpPump2.gpInstanceId, "out", gpTank2.gpInstanceId, "bottom",
		GPPIDEdge.GP_PROCESS, "L-9")
	var gpSheets: Array[GPSheet] = [gpSheet1, gpSheet2]
	var gpAll: Dictionary = GPDeliverableModel.gpBuildAll(gpSheets, _gpDefs(), _gpOptions())
	var gpLines: Array[Dictionary] = _gpRows(gpAll["line"] as Dictionary)
	var gpL9: Dictionary = _gpRowBy(gpLines, "line_no", "L-9")
	gpEq(str(gpL9.get("sheet", "")), "P&ID A, P&ID B", "both sheet names are listed in order")
	var gpSheetIds: Array = gpL9.get("_sheet_ids", []) as Array
	gpEq(gpSheetIds.size(), 2, "both sheet ids are kept for write-back")
