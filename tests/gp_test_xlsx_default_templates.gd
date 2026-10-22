extends "res://tests/gp_test.gd"
# P4 acceptance: the four shipped templates are readable, bind to the right list, carry
# tokens in the summary/footer, have no cover, and survive a fill.
# P4 验收：四套随包模板可读、绑定正确、汇总区/页脚含令牌、无封面、可被填充。
#
# Why a separate suite / 为何单独一套：
# P3 tests use synthetic templates. This suite checks the ACTUAL assets that ship in the
# PCK, including their sheet names, header aliases, print area and export include filter.
# P3 用合成模板；本套检查真正随包（进 PCK）的资产，包括表名、表头别名、打印区域与导出过滤器。

const GP_PATHS: Dictionary = {
	"line": "res://assets/templates/gp_list_line_default.xlsx",
	"equipment": "res://assets/templates/gp_list_equipment_default.xlsx",
	"instrument": "res://assets/templates/gp_list_instrument_default.xlsx",
	"valve": "res://assets/templates/gp_list_valve_default.xlsx",
}

const GP_SHEET_NAMES: Dictionary = {
	"line": "管线一览表",
	"equipment": "设备一览表",
	"instrument": "仪表索引表",
	"valve": "阀门一览表",
}


func _gpDefs() -> Array[GPSymbolDef]:
	return GPSymbolLibrary.gpDefaultDefs()


func _gpEntries(gpList: String) -> Dictionary:
	var gpLoaded: Dictionary = GPXlsxTemplate.gpLoad(str(GP_PATHS[gpList]))
	gpCheck(bool(gpLoaded.get("ok", false)), "template loads: " + gpList)
	return gpLoaded.get("entries", {}) as Dictionary


func _gpCellText(gpEntries: Dictionary, gpPath: String, gpRef: String) -> String:
	return GPXlsxReader.gpTextAt(gpEntries, gpPath, gpRef)


func _gpDefinedName(gpWorkbook: Dictionary, gpName: String) -> Dictionary:
	for gpChildRaw in GPXlsxXml.gpChildren(GPXlsxXml.gpChild(gpWorkbook, "definedNames"),
			"definedName"):
		var gpChild: Dictionary = gpChildRaw as Dictionary
		if GPXlsxXml.gpAttr(gpChild, "name", "") == gpName:
			return gpChild
	return {}


# ==================== assets ====================

func gpTestFourTemplatesExistAndAreXlsx() -> void:
	for gpList in GP_PATHS.keys():
		var gpPath: String = str(GP_PATHS[gpList])
		gpCheck(FileAccess.file_exists(gpPath), "exists: " + gpPath)
		var gpRead: Dictionary = GPXlsxPackage.gpReadArchive(gpPath)
		gpCheck(bool(gpRead.get("ok", false)), "valid xlsx: " + gpPath)


func gpTestEachTemplateBindsToItsList() -> void:
	for gpList in GP_PATHS.keys():
		var gpProbe: Dictionary = GPXlsxTemplate.gpProbe(str(GP_PATHS[gpList]), gpList,
			_gpDefs())
		gpCheck(bool(gpProbe.get("ok", false)), "binds: " + gpList)
		gpEq(str(gpProbe.get("sheet_name", "")), str(GP_SHEET_NAMES[gpList]),
			"sheet name: " + gpList)
		gpEq(int(gpProbe.get("header_row", 0)), 3, "header row 3: " + gpList)
		gpEq(int(gpProbe.get("data_start", 0)), 4, "sample row 4: " + gpList)
		var gpCols: Dictionary = gpProbe.get("columns", {}) as Dictionary
		gpCheck(not gpCols.is_empty(), "columns mapped: " + gpList)
		if gpList == "line":
			gpCheck(_gpHasColumn(gpCols, "line_no"), "line has line_no")
			gpCheck(_gpHasColumn(gpCols, "dn"), "line has dn")
			gpCheck(_gpHasColumn(gpCols, "valves"), "line has valves")
		else:
			gpCheck(_gpHasColumn(gpCols, "tag"), "list has tag: " + gpList)


func gpTestNoCoverAndOneSheet() -> void:
	for gpList in GP_PATHS.keys():
		var gpEntries: Dictionary = _gpEntries(gpList)
		var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
		gpEq((gpBook.get("sheets", []) as Array).size(), 1, "one data sheet: " + gpList)
		var gpSheets: Array = gpBook.get("sheets", []) as Array
		var gpPath: String = str((gpSheets[0] as Dictionary).get("path", ""))
		var gpRoot: Dictionary = GPXlsxXml.gpRootElement(GPXlsxPackage.gpReadPart(gpEntries, gpPath))
		var gpShared: Array[String] = GPXlsxPackage.gpSharedStrings(gpEntries)
		for gpRowRaw in GPXlsxXml.gpChildren(GPXlsxXml.gpChild(gpRoot, "sheetData"), "row"):
			for gpCellRaw in GPXlsxXml.gpChildren(gpRowRaw as Dictionary, "c"):
				var gpText: String = GPXlsxSheet.gpCellText(gpCellRaw as Dictionary, gpShared)
				gpCheck(gpText.find("{{GP_COVER}}") < 0, "no cover marker: " + gpList)


func gpTestSummaryAndFooterTokens() -> void:
	for gpList in GP_PATHS.keys():
		var gpEntries: Dictionary = _gpEntries(gpList)
		var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
		var gpSheet: Dictionary = (gpBook.get("sheets", []) as Array)[0] as Dictionary
		var gpPath: String = str(gpSheet.get("path", ""))
		var gpA2: String = _gpCellText(gpEntries, gpPath, "A2")
		gpCheck(gpA2.find("{{project.name}}") >= 0, "project token: " + gpList)
		gpCheck(gpA2.find("{{list.%s.count}}" % gpList) >= 0, "count token: " + gpList)
		var gpA5: String = _gpCellText(gpEntries, gpPath, "A5")
		gpCheck(gpA5.find("{{project.company}}") >= 0, "company token: " + gpList)
		var gpDate: String = _gpCellText(gpEntries, gpPath, "J5")
		gpCheck(gpDate.find("{{export.date}}") >= 0, "date token: " + gpList)


func gpTestPrintAreaAndTitles() -> void:
	for gpList in GP_PATHS.keys():
		var gpEntries: Dictionary = _gpEntries(gpList)
		var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
		var gpWb: Dictionary = gpBook["workbook"] as Dictionary
		var gpArea: Dictionary = _gpDefinedName(gpWb, "_xlnm.Print_Area")
		gpCheck(not gpArea.is_empty(), "print area defined: " + gpList)
		gpEq(GPXlsxXml.gpAttr(gpArea, "localSheetId"), "0", "print area local: " + gpList)
		var gpTitles: Dictionary = _gpDefinedName(gpWb, "_xlnm.Print_Titles")
		gpCheck(not gpTitles.is_empty(), "print titles defined: " + gpList)
		var gpSheet: Dictionary = (gpBook.get("sheets", []) as Array)[0] as Dictionary
		var gpPath: String = str(gpSheet.get("path", ""))
		var gpRoot: Dictionary = GPXlsxXml.gpRootElement(GPXlsxPackage.gpReadPart(gpEntries, gpPath))
		var gpFilter: Dictionary = GPXlsxXml.gpChild(gpRoot, "autoFilter")
		gpCheck(GPXlsxXml.gpAttr(gpFilter, "ref", "").begins_with("A3:"),
			"filter starts at the header row: " + gpList)
		var gpDim: String = GPXlsxXml.gpAttr(GPXlsxXml.gpChild(gpRoot, "dimension"), "ref", "")
		gpCheck(gpDim.ends_with("5"), "dimension includes the footer: " + gpList)


# ==================== fill the real default ====================

func gpTestDefaultLineTemplateFills() -> void:
	var gpProbe: Dictionary = GPXlsxTemplate.gpProbe(str(GP_PATHS["line"]), "line", _gpDefs())
	gpCheck(bool(gpProbe.get("ok", false)), "default line binds for fill")
	var gpEntries: Dictionary = gpProbe["entries"] as Dictionary
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
	var gpContext: Dictionary = GPXlsxFiller.gpTokenContext([gpSheet], {"line": 1}, "zh",
		"line", "管线一览表", 1, 1)
	var gpRows: Array = [{"no": 1, "line_no": "L-1", "medium": "矿浆", "dn": "DN80",
		"length_m": 12.5, "valves": "V-301"}]
	var gpFill: Dictionary = GPXlsxFiller.gpFill(gpEntries, gpProbe, gpRows, gpContext, "line")
	gpCheck(bool(gpFill.get("ok", false)), "default line fills")
	var gpPath: String = str(gpProbe.get("sheet_path", ""))
	gpEq(_gpCellText(gpEntries, gpPath, "A2").find("{{"), -1, "summary tokens replaced")
	gpEq(_gpCellText(gpEntries, gpPath, "A2").find("W6 项目") >= 0, true, "project value present")
	gpEq(_gpCellText(gpEntries, gpPath, "B4"), "L-1", "data row at the sample position")
	gpEq(_gpCellText(gpEntries, gpPath, "A5"), "编制：G-PID", "footer token replaced")
	gpCheck(_gpCellText(gpEntries, gpPath, "A2").find("共 1 条") >= 0, "count token replaced")


func gpTestExportPresetIncludesTemplates() -> void:
	var gpText: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	gpEq(gpText.count("assets/templates/*.xlsx"), 2,
		"both export presets include the template folder")


# ==================== helpers ====================

func _gpHasColumn(gpCols: Dictionary, gpKey: String) -> bool:
	for gpColRaw in gpCols.keys():
		if str((gpCols[gpColRaw] as Dictionary).get("key", "")) == gpKey:
			return true
	return false


func gpRootOf(gpEntries: Dictionary, gpPath: String) -> Dictionary:
	return GPXlsxXml.gpRootElement(GPXlsxPackage.gpReadPart(gpEntries, gpPath))


func gpSheetMaxCol(gpRoot: Dictionary) -> int:
	var gpMax: int = 1
	for gpRowRaw in GPXlsxXml.gpChildren(GPXlsxXml.gpChild(gpRoot, "sheetData"), "row"):
		for gpCellRaw in GPXlsxXml.gpChildren(gpRowRaw as Dictionary, "c"):
			gpMax = maxi(gpMax, GPXlsxSheet.gpColOfRef(
				GPXlsxXml.gpAttr(gpCellRaw as Dictionary, "r", "")))
	return gpMax
