extends "res://tests/gp_test.gd"
# P3 acceptance: template binding (sheet marker / name / header) and column mapping.
# P3 验收：模板绑定（表标记 / 表名 / 表头）与列映射。

const GP_EPS: float = 0.0001


func _gpDefs() -> Array[GPSymbolDef]:
	return GPSymbolLibrary.gpDefaultDefs()


func _gpTemp(gpName: String) -> String:
	return "user://gp_test_tpl_%s_%d.xlsx" % [gpName, Time.get_ticks_usec()]


func _gpBuildTemplate(gpRows: Array, gpOptions: Dictionary = {}) -> String:
	var gpPath: String = _gpTemp("template")
	var gpSpec: Dictionary = {
		"name": str(gpOptions.get("sheet_name", "管线一览表")),
		"rows": gpRows,
		"header_rows": int(gpOptions.get("header_rows", 2)),
		"widths": [8.0, 16.0, 14.0, 12.0, 16.0],
		"freeze_rows": int(gpOptions.get("freeze_rows", 0)),
		"merges": gpOptions.get("merges", []),
		"auto_filter": str(gpOptions.get("auto_filter", "")),
	}
	gpEq(GPXlsxBuilder.gpBuildToPath(gpPath, [gpSpec]), OK, "template builds")
	return gpPath


func _gpLineTemplateRows() -> Array:
	return [
		["{{project.name}}", "", "", "", ""],
		["序号", "管线号", "介质", "长度(m)", "阀门"],
		["", "", "", "", ""],
		["编制：{{project.company}}", "审核：", "批准：", "", ""],
	]


func _gpEnglishRows() -> Array:
	return [
		["No.", "Line No.", "Medium", "Length (m)", "Valves"],
		["", "", "", "", ""],
	]


func _gpCleanup(gpPath: String) -> void:
	if FileAccess.file_exists(gpPath):
		DirAccess.remove_absolute(gpPath)


# ==================== binding ====================

func gpTestBindsByHeaderAndMapsColumns() -> void:
	var gpPath: String = _gpBuildTemplate(_gpLineTemplateRows(),
		{"sheet_name": "Custom Data", "merges": ["A1:E1"], "freeze_rows": 2, "auto_filter": "A2:E2"})
	var gpProbe: Dictionary = GPXlsxTemplate.gpProbe(gpPath, "line", _gpDefs())
	gpCheck(bool(gpProbe.get("ok", false)), "line template binds")
	gpEq(int(gpProbe.get("header_row", 0)), 2, "header row detected")
	gpEq(int(gpProbe.get("data_start", 0)), 3, "data starts below the header")
	var gpCols: Dictionary = gpProbe.get("columns", {}) as Dictionary
	gpCheck(gpCols.has("A"), "column A mapped")
	gpEq(str((gpCols.get("B", {}) as Dictionary).get("key", "")), "line_no", "B is line number")
	gpEq(str((gpCols.get("E", {}) as Dictionary).get("key", "")), "valves", "E is valves")
	gpEq(str(gpProbe.get("source", "")), "header", "binding source is the header signature")
	_gpCleanup(gpPath)


func gpTestBindsEnglishHeaders() -> void:
	var gpPath: String = _gpBuildTemplate(_gpEnglishRows(),
		{"sheet_name": "Custom Sheet", "header_rows": 1})
	var gpProbe: Dictionary = GPXlsxTemplate.gpProbe(gpPath, "line", _gpDefs())
	gpCheck(bool(gpProbe.get("ok", false)), "English headers bind")
	gpEq(int(gpProbe.get("header_row", 0)), 1, "English header row")
	var gpCols: Dictionary = gpProbe.get("columns", {}) as Dictionary
	gpEq(str((gpCols.get("A", {}) as Dictionary).get("key", "")), "no", "No. -> no")
	gpEq(str((gpCols.get("B", {}) as Dictionary).get("key", "")), "line_no",
		"Line No. -> line_no")
	gpEq(str((gpCols.get("E", {}) as Dictionary).get("key", "")), "valves",
		"Valves -> valves")
	_gpCleanup(gpPath)


func gpTestBindsByMarkerAndForcesHeaderRow() -> void:
	var gpRows: Array = [
		["{{GP_LIST:line}}", "", "", "", ""],
		["说明", "", "", "", ""],
		["序号", "管线号", "介质", "长度(m)", "阀门"],
		["", "", "", "", ""],
	]
	var gpPath: String = _gpBuildTemplate(gpRows,
		{"sheet_name": "任意表名", "header_rows": 1, "merges": ["A1:E1"]})
	var gpProbe: Dictionary = GPXlsxTemplate.gpProbe(gpPath, "line", _gpDefs())
	gpCheck(bool(gpProbe.get("ok", false)), "marker template binds")
	gpEq(int(gpProbe.get("header_row", 0)), 3, "marker allows a header below row 2")
	gpEq(str(gpProbe.get("source", "")), "marker", "marker wins over name/header")
	_gpCleanup(gpPath)


func gpTestRejectsTemplateWithoutKeyColumn() -> void:
	var gpPath: String = _gpBuildTemplate([
		["序号", "介质", "长度(m)"],
		["", "", ""],
	], {"sheet_name": "No Key", "header_rows": 1})
	var gpProbe: Dictionary = GPXlsxTemplate.gpProbe(gpPath, "line", _gpDefs())
	gpCheck(not bool(gpProbe.get("ok", false)), "template without line_no is rejected")
	gpEq(str(gpProbe.get("error", "")), "no_key", "reports the missing key column")
	_gpCleanup(gpPath)


func gpTestDynamicSchemaColumn() -> void:
	var gpRows: Array = [
		["位号", "名称", "密封型式"],
		["", "", ""],
	]
	var gpPath: String = _gpBuildTemplate(gpRows,
		{"sheet_name": "设备一览表", "header_rows": 1})
	var gpProbe: Dictionary = GPXlsxTemplate.gpProbe(gpPath, "equipment", _gpDefs())
	gpCheck(bool(gpProbe.get("ok", false)), "equipment template binds")
	var gpCols: Dictionary = gpProbe.get("columns", {}) as Dictionary
	gpEq(str((gpCols.get("C", {}) as Dictionary).get("key", "")), "prop:seal_type",
		"schema label maps to prop:seal_type")
	_gpCleanup(gpPath)


func gpTestBilingualItemHeaderMapsTag() -> void:
	# "Item" is an alias of no; "位号" is tag. The key field must win.
	# “Item”是序号别名，“位号”是 tag；关键列必须优先。
	var gpPath: String = _gpBuildTemplate([
		["Item\n位号", "Description\n说明"],
		["", ""],
	], {"sheet_name": "EQ LIST", "header_rows": 1})
	var gpProbe: Dictionary = GPXlsxTemplate.gpProbe(gpPath, "equipment", _gpDefs())
	gpCheck(bool(gpProbe.get("ok", false)), "bilingual Item/位号 binds")
	var gpCols: Dictionary = gpProbe.get("columns", {}) as Dictionary
	gpEq(str((gpCols.get("A", {}) as Dictionary).get("key", "")), "tag",
		"Item/位号 maps to tag, not no")
	_gpCleanup(gpPath)


func gpTestRejectsTokenBelowHeader() -> void:
	var gpPath: String = _gpBuildTemplate([
		["Title", "", ""],
		["{{GP_HEADER}}", "Item\n位号", "Description\n说明"],
		["", "", ""],
		["", "{{tag}}", "{{name}}"],
	], {"sheet_name": "EQ LIST", "header_rows": 1})
	var gpProbe: Dictionary = GPXlsxTemplate.gpProbe(gpPath, "equipment", _gpDefs())
	gpCheck(not bool(gpProbe.get("ok", false)), "token row below sample is rejected")
	gpEq(str(gpProbe.get("error", "")), "sample_row", "specific sample-row error")
	gpEq(int(gpProbe.get("header_row", 0)), 2, "reports header row")
	gpEq(int(gpProbe.get("sample_row", 0)), 4, "reports token row")
	_gpCleanup(gpPath)
