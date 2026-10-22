extends "res://tests/gp_test.gd"
# P6 acceptance: read a real exported workbook back into property/name/edge-attr changes,
# apply them as one undo step per sheet, and verify blank=clear + read-only refusals.
# P6 验收：把真实导出的工作簿读回属性/名称/边属性变更，按图纸一条撤销步应用，并验证
# 空白=清空 + 只读拒绝。

const GP_EPS: float = 0.0001


func _gpDefs() -> Array[GPSymbolDef]:
	return GPSymbolLibrary.gpDefaultDefs()


func _gpNode(gpId: String, gpDefId: String, gpTag: String, gpPos: Vector2) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpId
	gpN.gpSymbolId = gpDefId
	gpN.gpTag = gpTag
	gpN.gpPosition = gpPos
	return gpN


func _gpRef(gpNodeId: String, gpPortId: String, gpPoint: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"sheet_id": "s1", "node_id": gpNodeId, "port_id": gpPortId,
		"point": gpPoint, "dir": Vector2.RIGHT, "is_dangling": false}


func _gpSheet(gpWithValve: bool = true) -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpId = "s1"
	gpSheet.gpName = "P&ID 1"
	gpSheet.gpIndex = 0
	gpSheet.gpLabelMode = GPSheet.GP_LABEL_ZH
	gpSheet.gpTitleBlock = GPSheet.gpDefaultTitleBlock()
	gpSheet.gpTitleBlock["project"]["value"] = {"zh": "W6 项目", "en": "W6"}
	gpSheet.gpTitleBlock["drawing_no"]["value"] = {"zh": "W6-1001", "en": "W6-1001"}
	gpSheet.gpTitleBlock["rev"]["value"] = {"zh": "A", "en": "A"}
	gpSheet.gpTitleBlock["company"]["value"] = {"zh": "G-PID", "en": "G-PID"}
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpSheet.gpGraph = gpG
	var gpPump: GPPIDNode = _gpNode("p1", "DPUMP001", "P-101", Vector2(100, 100))
	gpPump.gpNames["zh"] = "离心泵"
	gpPump.gpProps["design_temp"] = 120.0
	gpPump.gpProps["remark"] = "原备注"
	gpPump.gpProps["design_pressure"] = 1.6
	var gpTank: GPPIDNode = _gpNode("t1", "DTANK001", "T-201", Vector2(500, 100))
	gpG.gpAddNode(gpPump)
	gpG.gpAddNode(gpTank)
	var gpValve: GPPIDNode = _gpNode("v1", "DVALVE002", "V-301", Vector2(300, 100))
	if gpWithValve:
		gpG.gpAddNode(gpValve)
	gpG.gpAddEdge(gpG.gpNewEdgeEx("e1", _gpRef("p1", "out", Vector2(150, 100)),
		_gpRef("v1", "in", Vector2(280, 100)), GPPIDEdge.GP_PROCESS, "", "L-1",
		{"dn": "DN80", "spec": "A1A", "medium": "矿浆", "insulation": "50"}))
	gpG.gpAddEdge(gpG.gpNewEdgeEx("e2", _gpRef("v1", "out", Vector2(320, 100)),
		_gpRef("t1", "top", Vector2(500, 60)), GPPIDEdge.GP_PROCESS, "", "L-1",
		{"dn": "DN80", "spec": "A1A", "medium": "矿浆", "insulation": "50"}))
	return gpSheet


func _gpOutDir() -> String:
	var gpDir: String = "user://gp_p6_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(gpDir)
	return gpDir


func _gpExport(gpSheet: GPSheet, gpList: String) -> String:
	var gpDir: String = _gpOutDir()
	var gpResult: GPIOResult = GPXlsxExport.gpExportLists([gpSheet], _gpDefs(), {
		"lists": [gpList], "output_dir": gpDir, "name_prefix": "IMP",
		"locale": "zh", "include_empty": true,
		"type_labels": {"DPUMP001": "离心泵", "DTANK001": "储罐", "DVALVE002": "球阀"},
	})
	gpCheck(gpResult.gpIsOk(), "fixture export succeeds: " + gpList)
	var gpFiles: Array = (gpResult.gpPayload as Dictionary)["files"] as Array
	for gpFileRaw in gpFiles:
		var gpFile: Dictionary = gpFileRaw as Dictionary
		if bool(gpFile.get("ok", false)) and not bool(gpFile.get("skipped", false)):
			return str(gpFile.get("path", ""))
	return ""


func _gpEditWorkbook(gpPath: String, gpList: String, gpEdits: Dictionary) -> void:
	var gpRead: Dictionary = GPXlsxPackage.gpReadArchive(gpPath)
	gpCheck(bool(gpRead.get("ok", false)), "archive reads for edit")
	var gpEntries: Dictionary = gpRead["entries"] as Dictionary
	var gpProbe: Dictionary = GPXlsxTemplate.gpBind(gpEntries, gpList, _gpDefs(), {})
	gpCheck(bool(gpProbe.get("ok", false)), "binding for edit")
	var gpSheetPath: String = str(gpProbe.get("sheet_path", ""))
	var gpRoot: Dictionary = GPXlsxXml.gpRootElement(GPXlsxPackage.gpReadPart(gpEntries, gpSheetPath))
	var gpRow: int = int(gpProbe.get("data_start", 1))
	var gpCols: Dictionary = gpProbe.get("columns", {}) as Dictionary
	for gpFieldRaw in gpEdits.keys():
		var gpField: String = str(gpFieldRaw)
		var gpCol: String = ""
		for gpColRaw in gpCols.keys():
			if str((gpCols[gpColRaw] as Dictionary).get("key", "")) == gpField:
				gpCol = str(gpColRaw)
				break
		gpCheck(gpCol != "", "column exists for " + gpField)
		var gpRef: String = gpCol + str(gpRow)
		var gpCell: Dictionary = GPXlsxSheet.gpCell(gpRoot, gpRef)
		var gpStyle: int = int(GPXlsxXml.gpAttr(gpCell, "s", "-1"))
		var gpValue: Variant = gpEdits[gpFieldRaw]
		if gpValue == null or (gpValue is String and str(gpValue) == ""):
			GPXlsxSheet.gpSetCell(gpRoot, gpRef, "blank", null, gpStyle)
		elif gpValue is int or gpValue is float:
			GPXlsxSheet.gpSetCell(gpRoot, gpRef, "number", gpValue, gpStyle)
		else:
			GPXlsxSheet.gpSetCell(gpRoot, gpRef, "text", str(gpValue), gpStyle)
	GPXlsxSheet.gpUpdateDimension(gpRoot)
	GPXlsxPackage.gpWritePart(gpEntries, gpSheetPath, gpRoot)
	gpEq(GPXlsxPackage.gpWriteArchive(gpPath, gpEntries), OK, "edited workbook writes")


func _gpImport(gpPath: String, gpSheet: GPSheet, gpList: String) -> Dictionary:
	return GPXlsxImport.gpRead([{"path": gpPath, "list": gpList}], [gpSheet], _gpDefs(),
		{"locale": "zh", "type_labels": {"DPUMP001": "离心泵", "DTANK001": "储罐",
			"DVALVE002": "球阀"}})


func _gpApply(gpSheet: GPSheet, gpChanges: Array) -> bool:
	var gpCmd: GPApplyListChangesCommand = GPApplyListChangesCommand.new(gpChanges)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpSheet.gpGraph)
	return gpCmd.gpExecute(gpCtx) if gpCmd.gpExecute(gpCtx) else false


func _gpCleanup(gpPath: String) -> void:
	if FileAccess.file_exists(gpPath):
		DirAccess.remove_absolute(gpPath)
	if FileAccess.file_exists(gpPath + ".bak"):
		DirAccess.remove_absolute(gpPath + ".bak")


# ==================== equipment ====================

func gpTestEquipmentImportAppliesAndUndoesAsOneStep() -> void:
	var gpSheet: GPSheet = _gpSheet(true)
	var gpPath: String = _gpExport(gpSheet, "equipment")
	_gpEditWorkbook(gpPath, "equipment", {
		"name": "离心泵 A",
		"material": "316L",
		"design_pressure": 2.5,
		"design_temp": "",
		"remark": "",
	})
	var gpImp: Dictionary = _gpImport(gpPath, gpSheet, "equipment")
	gpCheck(bool(gpImp.get("ok", false)), "import preview returns ok")
	var gpChanges: Array = gpImp.get("changes", []) as Array
	gpEq(gpChanges.size(), 5, "five property/name changes")
	var gpHasClear: bool = false
	for gpChangeRaw in gpChanges:
		if bool((gpChangeRaw as Dictionary).get("clear", false)):
			gpHasClear = true
	gpCheck(gpHasClear, "blank cell becomes a clear change")
	var gpCmd: GPApplyListChangesCommand = GPApplyListChangesCommand.new(gpChanges)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpSheet.gpGraph)
	gpCheck(gpCmd.gpExecute(gpCtx), "one sheet command executes")
	var gpPump: GPPIDNode = gpSheet.gpGraph.gpGetNode("p1")
	gpEq(str(gpPump.gpNames.get("zh", "")), "离心泵 A", "name applied")
	gpEq(str(gpPump.gpProps.get("material", "")), "316L", "material applied")
	gpApprox(float(gpPump.gpProps.get("design_pressure", 0.0)), 2.5, GP_EPS,
		"design pressure applied")
	gpCheck(not gpPump.gpProps.has("design_temp"), "blank clears design temp")
	gpCheck(not gpPump.gpProps.has("remark"), "blank clears remark")
	gpCmd.gpUndo(gpCtx)
	gpEq(str(gpPump.gpNames.get("zh", "")), "离心泵", "undo restores name")
	gpEq(str(gpPump.gpProps.get("remark", "")), "原备注", "undo restores remark")
	gpApprox(float(gpPump.gpProps.get("design_temp", 0.0)), 120.0, GP_EPS,
		"undo restores design temp")
	gpCmd.gpRedo(gpCtx)
	gpCheck(not gpPump.gpProps.has("remark"), "redo re-clears remark")
	_gpCleanup(gpPath)


func gpTestReadOnlyColumnsAreIgnored() -> void:
	var gpSheet: GPSheet = _gpSheet(true)
	var gpPath: String = _gpExport(gpSheet, "equipment")
	_gpEditWorkbook(gpPath, "equipment", {"type": "篡改类型", "class": "FakeClass"})
	var gpImp: Dictionary = _gpImport(gpPath, gpSheet, "equipment")
	gpEq((gpImp.get("changes", []) as Array).size(), 0, "read-only columns create no changes")
	gpEq(str((gpSheet.gpGraph.gpGetNode("p1") as GPPIDNode).gpTag), "P-101",
		"tag is untouched")
	_gpCleanup(gpPath)


func gpTestUnknownTagIsReported() -> void:
	var gpSheet: GPSheet = _gpSheet(true)
	var gpPath: String = _gpExport(gpSheet, "equipment")
	_gpEditWorkbook(gpPath, "equipment", {"tag": "P-999", "name": "不存在"})
	var gpImp: Dictionary = _gpImport(gpPath, gpSheet, "equipment")
	gpEq((gpImp.get("changes", []) as Array).size(), 0, "unknown tag creates no changes")
	var gpFound: bool = false
	for gpIssueRaw in (gpImp.get("issues", []) as Array):
		if str((gpIssueRaw as Dictionary).get("code", "")) == "xlsx.tag_not_found":
			gpFound = true
	gpCheck(gpFound, "unknown tag is reported")
	_gpCleanup(gpPath)


# ==================== line ====================

func gpTestLineImportWritesEveryEdge() -> void:
	var gpSheet: GPSheet = _gpSheet(true)
	var gpPath: String = _gpExport(gpSheet, "line")
	_gpEditWorkbook(gpPath, "line", {"dn": "DN100", "medium": "水", "insulation": ""})
	var gpImp: Dictionary = _gpImport(gpPath, gpSheet, "line")
	var gpChanges: Array = gpImp.get("changes", []) as Array
	gpEq(gpChanges.size(), 6, "three attrs x two line edges")
	var gpCmd: GPApplyListChangesCommand = GPApplyListChangesCommand.new(gpChanges)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpSheet.gpGraph)
	gpCheck(gpCmd.gpExecute(gpCtx), "line command executes")
	for gpId in ["e1", "e2"]:
		var gpEdge: GPPIDEdge = gpSheet.gpGraph.gpGetEdge(gpId)
		gpEq(str(gpEdge.gpAttrs.get("dn", "")), "DN100", "dn applied to " + gpId)
		gpEq(str(gpEdge.gpAttrs.get("medium", "")), "水", "medium applied to " + gpId)
		gpCheck(not gpEdge.gpAttrs.has("insulation"), "insulation cleared on " + gpId)
	gpCmd.gpUndo(gpCtx)
	var gpE1: GPPIDEdge = gpSheet.gpGraph.gpGetEdge("e1")
	gpEq(str(gpE1.gpAttrs.get("dn", "")), "DN80", "undo restores dn")
	gpEq(str(gpE1.gpAttrs.get("insulation", "")), "50", "undo restores insulation")
	_gpCleanup(gpPath)


# ==================== detection / no-op ====================

func gpTestAutoDetectsList() -> void:
	var gpSheet: GPSheet = _gpSheet(true)
	var gpPath: String = _gpExport(gpSheet, "equipment")
	var gpImp: Dictionary = GPXlsxImport.gpRead([{"path": gpPath}], [gpSheet], _gpDefs(),
		{"locale": "zh"})
	var gpFiles: Array = gpImp.get("files", []) as Array
	gpEq(str((gpFiles[0] as Dictionary).get("list", "")), "equipment",
		"auto-detects equipment from the sheet name")
	_gpCleanup(gpPath)


func gpTestNoOpCommandReturnsFalse() -> void:
	var gpSheet: GPSheet = _gpSheet(true)
	var gpCmd: GPApplyListChangesCommand = GPApplyListChangesCommand.new([{
		"kind": "node_name", "target_id": "p1", "key": "name", "locale": "zh",
		"old": "离心泵", "new": "离心泵", "clear": false,
	}])
	var gpCtx: GPCommandContext = GPCommandContext.new(gpSheet.gpGraph)
	gpCheck(not gpCmd.gpExecute(gpCtx), "unchanged value leaves no undo step")


func gpTestUneditedExportRoundTripsWithNoChanges() -> void:
	var gpSheet: GPSheet = _gpSheet(true)
	var gpPath: String = _gpExport(gpSheet, "equipment")
	var gpImp: Dictionary = _gpImport(gpPath, gpSheet, "equipment")
	gpEq((gpImp.get("changes", []) as Array).size(), 0,
		"export -> import with no edits creates no changes")
	gpEq((gpImp.get("issues", []) as Array).size(), 0, "no issues on a clean round-trip")
	_gpCleanup(gpPath)
