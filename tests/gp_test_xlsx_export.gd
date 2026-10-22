extends "res://tests/gp_test.gd"
# P3 acceptance: fill a bound template and export one file per list, with N=0/1/100,
# footer shifting, tokens, auto-filter/dimension/print area, and template immutability.
# P3 验收：填充已绑定模板并按类导出；覆盖 N=0/1/100、页脚平移、令牌、筛选/维度/打印区域、
# 模板不被改写。

const GP_EPS: float = 0.0001


func _gpDefs() -> Array[GPSymbolDef]:
	return GPSymbolLibrary.gpDefaultDefs()


func _gpDefsById() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpDef in _gpDefs():
		gpOut[gpDef.gpId] = gpDef
	return gpOut


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


func _gpLineSheet() -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpId = "s1"
	gpSheet.gpName = "P&ID 1"
	gpSheet.gpIndex = 0
	gpSheet.gpLabelMode = GPSheet.GP_LABEL_ZH
	gpSheet.gpTitleBlock = GPSheet.gpDefaultTitleBlock()
	gpSheet.gpTitleBlock["project"]["value"] = {"zh": "W6 项目", "en": "W6 Project"}
	gpSheet.gpTitleBlock["drawing_no"]["value"] = {"zh": "W6-1001", "en": "W6-1001"}
	gpSheet.gpTitleBlock["rev"]["value"] = {"zh": "A", "en": "A"}
	gpSheet.gpTitleBlock["company"]["value"] = {"zh": "G-PID", "en": "G-PID"}
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpSheet.gpGraph = gpG
	var gpPump: GPPIDNode = _gpNode("p1", "DPUMP001", "P-101", Vector2(100, 100))
	var gpTank: GPPIDNode = _gpNode("t1", "DTANK001", "T-201", Vector2(500, 100))
	var gpValve: GPPIDNode = _gpNode("v1", "DVALVE002", "V-301", Vector2(300, 100))
	gpG.gpAddNode(gpPump)
	gpG.gpAddNode(gpTank)
	gpG.gpAddNode(gpValve)
	var gpE1: GPPIDEdge = gpG.gpNewEdgeEx("e1", _gpRef("p1", "out", Vector2(150, 100)),
		_gpRef("v1", "in", Vector2(280, 100)), GPPIDEdge.GP_PROCESS, "", "L-1",
		{"dn": "DN80", "spec": "A1A", "medium": "矿浆"})
	var gpE2: GPPIDEdge = gpG.gpNewEdgeEx("e2", _gpRef("v1", "out", Vector2(320, 100)),
		_gpRef("t1", "top", Vector2(500, 60)), GPPIDEdge.GP_PROCESS, "", "L-1",
		{"dn": "DN80", "spec": "A1A", "medium": "矿浆"})
	gpG.gpAddEdge(gpE1)
	gpG.gpAddEdge(gpE2)
	return gpSheet


func _gpEmptySheet() -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpId = "s2"
	gpSheet.gpName = "Empty"
	gpSheet.gpIndex = 0
	gpSheet.gpLabelMode = GPSheet.GP_LABEL_ZH
	gpSheet.gpTitleBlock = GPSheet.gpDefaultTitleBlock()
	gpSheet.gpTitleBlock["project"]["value"] = {"zh": "W6 项目", "en": "W6 Project"}
	gpSheet.gpTitleBlock["company"]["value"] = {"zh": "G-PID", "en": "G-PID"}
	gpSheet.gpGraph = GPPIDGraph.new()
	return gpSheet


func _gpManySheet(gpCount: int) -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpId = "s3"
	gpSheet.gpName = "Many"
	gpSheet.gpIndex = 0
	gpSheet.gpLabelMode = GPSheet.GP_LABEL_ZH
	gpSheet.gpTitleBlock = GPSheet.gpDefaultTitleBlock()
	gpSheet.gpTitleBlock["project"]["value"] = {"zh": "W6 项目", "en": "W6 Project"}
	gpSheet.gpTitleBlock["company"]["value"] = {"zh": "G-PID", "en": "G-PID"}
	gpSheet.gpGraph = GPPIDGraph.new()
	for gpI in range(gpCount):
		gpSheet.gpGraph.gpAddNode(_gpNode("p%d" % gpI, "DPUMP001", "P-%d" % (gpI + 1),
			Vector2(100 + gpI * 20, 100)))
	return gpSheet


func _gpLineTemplate() -> String:
	var gpPath: String = "user://gp_p3_line_template_%d.xlsx" % Time.get_ticks_usec()
	var gpErr: int = GPXlsxBuilder.gpBuildToPath(gpPath, [{
		"name": "管线一览表",
		"rows": [
			["{{project.name}}", "", "", "", ""],
			["序号", "管线号", "介质", "长度(m)", "阀门"],
			["", "", "", "", ""],
			["编制：{{project.company}}", "行数：{{list.line.count}}", "批准：", "", ""],
		],
		"header_rows": 2,
		"widths": [8.0, 16.0, 14.0, 12.0, 16.0],
		"freeze_rows": 2,
		"merges": ["A1:E1"],
		"auto_filter": "A2:E2",
		"landscape": true,
	}])
	gpEq(gpErr, OK, "line template builds")
	return gpPath


func _gpEquipmentTemplate() -> String:
	var gpPath: String = "user://gp_p3_equip_template_%d.xlsx" % Time.get_ticks_usec()
	var gpErr: int = GPXlsxBuilder.gpBuildToPath(gpPath, [{
		"name": "设备一览表",
		"rows": [
			["{{project.name}}", "", "", ""],
			["位号", "名称", "数量", "材质"],
			["", "", "", ""],
			["编制：{{project.company}}", "审核：", "批准：", ""],
		],
		"header_rows": 2,
		"widths": [14.0, 18.0, 8.0, 14.0],
		"freeze_rows": 2,
		"merges": ["A1:D1"],
		"auto_filter": "A2:D2",
		"landscape": true,
	}])
	gpEq(gpErr, OK, "equipment template builds")
	return gpPath


func _gpOutDir() -> String:
	var gpDir: String = "user://gp_p3_out_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(gpDir)
	return gpDir


func _gpClearDir(gpDir: String) -> void:
	var gpDA: DirAccess = DirAccess.open(gpDir)
	if gpDA == null:
		return
	for gpName in gpDA.get_files():
		DirAccess.remove_absolute(gpDir.path_join(gpName))


func _gpFileByList(gpPayload: Dictionary, gpList: String) -> Dictionary:
	for gpFileRaw in (gpPayload.get("files", []) as Array):
		var gpFile: Dictionary = gpFileRaw as Dictionary
		if str(gpFile.get("list", "")) == gpList:
			return gpFile
	return {}


func _gpSheetOf(gpPath: String) -> Dictionary:
	var gpRead: Dictionary = GPXlsxPackage.gpReadArchive(gpPath)
	if not bool(gpRead.get("ok", false)):
		return {}
	var gpEntries: Dictionary = gpRead["entries"] as Dictionary
	var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
	if not bool(gpBook.get("ok", false)):
		return {}
	var gpSheets: Array = gpBook["sheets"] as Array
	if gpSheets.is_empty():
		return {}
	var gpSheet: Dictionary = gpSheets[0] as Dictionary
	var gpPath1: String = str(gpSheet.get("path", ""))
	var gpRoot: Dictionary = GPXlsxXml.gpRootElement(GPXlsxPackage.gpReadPart(gpEntries, gpPath1))
	return {"entries": gpEntries, "sheet": gpSheet, "path": gpPath1, "root": gpRoot,
		"book": gpBook}


# ==================== main export ====================

func gpTestExportsTwoFilesAndFillsTemplate() -> void:
	var gpLineTpl: String = _gpLineTemplate()
	var gpEquipTpl: String = _gpEquipmentTemplate()
	var gpLineBefore: PackedByteArray = FileAccess.get_file_as_bytes(gpLineTpl)
	var gpOutDir: String = _gpOutDir()
	var gpOptions: Dictionary = {
		"lists": ["line", "equipment"],
		"templates": {"line": gpLineTpl, "equipment": gpEquipTpl},
		"output_dir": gpOutDir,
		"name_prefix": "W6",
		"locale": "zh",
		"include_empty": true,
	}
	var gpResult: GPIOResult = GPXlsxExport.gpExportLists([_gpLineSheet()], _gpDefs(), gpOptions)
	gpCheck(gpResult.gpIsOk(), "export succeeds")
	var gpPayload: Dictionary = gpResult.gpPayload as Dictionary
	gpEq(int(gpPayload.get("written", 0)), 2, "two files written")
	var gpLineFile: Dictionary = _gpFileByList(gpPayload, "line")
	gpCheck(bool(gpLineFile.get("ok", false)), "line file ok")
	gpCheck(FileAccess.file_exists(str(gpLineFile.get("path", ""))), "line file exists")
	var gpEquipFile: Dictionary = _gpFileByList(gpPayload, "equipment")
	gpCheck(bool(gpEquipFile.get("ok", false)), "equipment file ok")

	var gpLine: Dictionary = _gpSheetOf(str(gpLineFile["path"]))
	gpEq(str((gpLine["sheet"] as Dictionary).get("name", "")), "管线一览表", "line sheet name")
	gpEq(GPXlsxReader.gpTextAt(gpLine["entries"] as Dictionary, str(gpLine["path"]), "A1"),
		"W6 项目", "project token replaced")
	gpEq(GPXlsxReader.gpTextAt(gpLine["entries"] as Dictionary, str(gpLine["path"]), "B2"),
		"管线号", "header label")
	gpEq(GPXlsxReader.gpTextAt(gpLine["entries"] as Dictionary, str(gpLine["path"]), "B3"),
		"L-1", "line number row 3")
	gpEq(GPXlsxReader.gpTextAt(gpLine["entries"] as Dictionary, str(gpLine["path"]), "E3"),
		"V-301", "valve row 3")
	gpEq(GPXlsxReader.gpTextAt(gpLine["entries"] as Dictionary, str(gpLine["path"]), "A4"),
		"编制：G-PID", "footer token and footer row")
	gpEq(GPXlsxReader.gpTextAt(gpLine["entries"] as Dictionary, str(gpLine["path"]), "B4"),
		"行数：1", "list count token")
	gpEq(GPXlsxXml.gpAttr(GPXlsxXml.gpChild(gpLine["root"] as Dictionary, "autoFilter"), "ref"),
		"A2:E3", "auto filter covers one data row")
	gpEq(GPXlsxXml.gpAttr(GPXlsxXml.gpChild(gpLine["root"] as Dictionary, "dimension"), "ref"),
		"A1:E4", "dimension includes the shifted footer")
	var gpLineWb: Dictionary = (gpLine["book"] as Dictionary)["workbook"] as Dictionary
	var gpDefined: String = GPXlsxXml.gpSerialize(GPXlsxXml.gpChild(gpLineWb, "definedNames"))
	gpCheck(gpDefined.find("_xlnm.Print_Area") >= 0, "print area defined name exists")
	var gpPrintName: Dictionary = GPXlsxXml.gpChildren(GPXlsxXml.gpChild(gpLineWb,
		"definedNames"), "definedName")[0] as Dictionary
	gpEq(GPXlsxXml.gpAttr(gpPrintName, "localSheetId"), "0",
		"print area is sheet-local")

	var gpEquip: Dictionary = _gpSheetOf(str(gpEquipFile["path"]))
	gpEq(GPXlsxReader.gpTextAt(gpEquip["entries"] as Dictionary, str(gpEquip["path"]), "A3"),
		"P-101", "first equipment row")
	gpEq(GPXlsxReader.gpTextAt(gpEquip["entries"] as Dictionary, str(gpEquip["path"]), "A4"),
		"T-201", "second equipment row")
	gpEq(GPXlsxReader.gpTextAt(gpEquip["entries"] as Dictionary, str(gpEquip["path"]), "A5"),
		"编制：G-PID", "equipment footer shifted by one row")
	gpEq(GPXlsxXml.gpAttr(GPXlsxXml.gpChild(gpEquip["root"] as Dictionary, "autoFilter"), "ref"),
		"A2:D4", "equipment filter covers two data rows")

	gpEq(FileAccess.get_file_as_bytes(gpLineTpl), gpLineBefore,
		"template bytes are unchanged by export")
	_gpClearDir(gpOutDir)
	DirAccess.remove_absolute(gpLineTpl)
	DirAccess.remove_absolute(gpEquipTpl)


func gpTestEmptyListRemovesSampleAndPullsFooterUp() -> void:
	var gpEquipTpl: String = _gpEquipmentTemplate()
	var gpOutDir: String = _gpOutDir()
	var gpOptions: Dictionary = {
		"lists": ["equipment"], "templates": {"equipment": gpEquipTpl},
		"output_dir": gpOutDir, "name_prefix": "EMPTY", "locale": "zh",
		"include_empty": true,
	}
	var gpResult: GPIOResult = GPXlsxExport.gpExportLists([_gpEmptySheet()], _gpDefs(), gpOptions)
	gpCheck(gpResult.gpIsOk(), "empty export succeeds when include_empty=true")
	var gpPayload: Dictionary = gpResult.gpPayload as Dictionary
	gpEq(int(gpPayload.get("written", 0)), 1, "empty file is still written")
	var gpFile: Dictionary = _gpFileByList(gpPayload, "equipment")
	var gpOut: Dictionary = _gpSheetOf(str(gpFile["path"]))
	gpEq(GPXlsxReader.gpTextAt(gpOut["entries"] as Dictionary, str(gpOut["path"]), "A2"),
		"位号", "header remains")
	gpEq(GPXlsxReader.gpTextAt(gpOut["entries"] as Dictionary, str(gpOut["path"]), "A3"),
		"编制：G-PID", "footer takes the sample row's place")
	gpEq(GPXlsxXml.gpAttr(GPXlsxXml.gpChild(gpOut["root"] as Dictionary, "dimension"), "ref"),
		"A1:D3", "dimension shrinks with the empty data region")
	_gpClearDir(gpOutDir)
	DirAccess.remove_absolute(gpEquipTpl)


func gpTestHundredRows() -> void:
	var gpEquipTpl: String = _gpEquipmentTemplate()
	var gpOutDir: String = _gpOutDir()
	var gpOptions: Dictionary = {
		"lists": ["equipment"], "templates": {"equipment": gpEquipTpl},
		"output_dir": gpOutDir, "name_prefix": "MANY", "locale": "zh",
		"include_empty": true,
	}
	var gpResult: GPIOResult = GPXlsxExport.gpExportLists([_gpManySheet(100)], _gpDefs(), gpOptions)
	gpCheck(gpResult.gpIsOk(), "100-row export succeeds")
	var gpFile: Dictionary = _gpFileByList(gpResult.gpPayload as Dictionary, "equipment")
	var gpOut: Dictionary = _gpSheetOf(str(gpFile["path"]))
	gpEq(GPXlsxReader.gpTextAt(gpOut["entries"] as Dictionary, str(gpOut["path"]), "A3"),
		"P-1", "first of 100")
	gpEq(GPXlsxReader.gpTextAt(gpOut["entries"] as Dictionary, str(gpOut["path"]), "A102"),
		"P-100", "last of 100")
	gpEq(GPXlsxReader.gpTextAt(gpOut["entries"] as Dictionary, str(gpOut["path"]), "A103"),
		"编制：G-PID", "footer after 100 rows")
	gpEq(GPXlsxXml.gpAttr(GPXlsxXml.gpChild(gpOut["root"] as Dictionary, "autoFilter"), "ref"),
		"A2:D102", "filter covers 100 data rows")
	_gpClearDir(gpOutDir)
	DirAccess.remove_absolute(gpEquipTpl)


func gpTestEmptyWithoutIncludeEmptyProducesNoFile() -> void:
	var gpEquipTpl: String = _gpEquipmentTemplate()
	var gpOutDir: String = _gpOutDir()
	var gpOptions: Dictionary = {
		"lists": ["equipment"], "templates": {"equipment": gpEquipTpl},
		"output_dir": gpOutDir, "name_prefix": "SKIP", "locale": "zh",
		"include_empty": false,
	}
	var gpResult: GPIOResult = GPXlsxExport.gpExportLists([_gpEmptySheet()], _gpDefs(), gpOptions)
	gpCheck(not gpResult.gpIsOk(), "empty list without include_empty fails")
	gpEq(gpResult.gpCode, "xlsx.no_files", "no-files error code")
	gpEq(DirAccess.open(gpOutDir).get_files().size(), 0, "no file written")
	_gpClearDir(gpOutDir)
	DirAccess.remove_absolute(gpEquipTpl)
