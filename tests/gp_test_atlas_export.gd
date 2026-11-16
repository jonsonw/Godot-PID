extends "res://tests/gp_test.gd"
# Atlas (batch drawing-set) export, W13 T3 (S7b): one PDF per sheet via the EXISTING
# single-sheet exporter, a catalog page through the SAME gpBuildPdf, per-sheet honest
# reporting with a measured elapsed time, and per-sheet failures that never abort the set.
# 图册（整套图纸）导出，W13 T3（S7b）：经**既有**单图导出器逐张出 PDF、目录页走**同一个**
# gpBuildPdf、带实测耗时的逐图诚实报告、单张失败绝不中断整套。
# Acceptance from the plan: the set export carries a MEASURED duration.
# 方案验收项：整套导出必须带**实测**耗时。

const GP_TMP_DIR: String = "user://gp_test_atlas"


# The same synthetic fixture as the PDF suite. / 与 PDF 套件同一份合成夹具。
static func _gpDefs() -> Array[GPSymbolDef]:
	var d := GPSymbolDef.new()
	d.gpId = "GTEST001"
	d.gpCategory = "pump"
	d.gpDisplayName = "GTEST001"
	var gpSq: Array[Vector2] = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	d.gpShapes.append(GPShape.gpPolyline(gpSq, true))
	d.gpDefaultSize = Vector2(50.0, 50.0)
	var gpOut: Array[GPSymbolDef] = [d]
	return gpOut


static func _gpSheet(gpName: String, gpNumber: String) -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpName = gpName
	gpSheet.gpNumber = gpNumber
	gpSheet.gpWidthMM = 420.0
	gpSheet.gpHeightMM = 297.0
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	var gpPump: GPPIDNode = gpGraph.gpNewNode("n1", "GTEST001", "P-1001", Vector2(100.0, 80.0))
	gpGraph.gpAddNode(gpPump)
	gpSheet.gpGraph = gpGraph
	return gpSheet


func _gpCleanTmp() -> void:
	DirAccess.make_dir_recursive_absolute(GP_TMP_DIR)
	var gpDir: DirAccess = DirAccess.open(GP_TMP_DIR)
	if gpDir == null:
		return
	gpDir.list_dir_begin()
	var gpName: String = gpDir.get_next()
	while not gpName.is_empty():
		if not gpDir.current_is_dir():
			DirAccess.remove_absolute(GP_TMP_DIR.path_join(gpName))
		gpName = gpDir.get_next()
	gpDir.list_dir_end()


# Hostile input: no real sheets, or no target directory -> an honest refusal, never a
# silent "success" with zero files.
# 敌意输入：无真实图纸、或无目标目录 -> 如实拒绝，绝不带着零文件静默"成功"。
func gpTestAtlasRefusesHostileInput() -> void:
	var gpEmpty: GPIOResult = GPAtlasExporter.gpExportAtlas([], GP_TMP_DIR)
	gpCheck(not gpEmpty.gpOk, "an empty set must fail")
	gpEq(gpEmpty.gpMessageKey, "atlas.no_sheets", "the empty-set failure names the reason")
	var gpNulls: Array[GPSheet] = [null, null]
	var gpAllNull: GPIOResult = GPAtlasExporter.gpExportAtlas(gpNulls, GP_TMP_DIR)
	gpCheck(not gpAllNull.gpOk, "a set of null sheets must fail too")
	var gpNoDir: GPIOResult = GPAtlasExporter.gpExportAtlas(
		[_gpSheet("A", "001")], "")
	gpCheck(not gpNoDir.gpOk, "an empty directory must fail")


# The set path: two sheets -> two PDFs + the catalog, all named from the rows, with the
# measured duration in the payload.
# 整套路径：两张图纸 -> 两个 PDF + 目录页，文件名与 rows 一致，payload 带实测耗时。
func gpTestAtlasExportsSetWithCatalog() -> void:
	_gpCleanTmp()
	var gpOutDir: String = GP_TMP_DIR.path_join("set")
	var gpSheets: Array[GPSheet] = [_gpSheet("Feed Area", "001"), _gpSheet("CIL", "002")]
	var gpRes: GPIOResult = GPAtlasExporter.gpExportAtlas(gpSheets, gpOutDir,
		Callable(), _gpDefs())
	gpCheck(gpRes.gpOk, "the set export must succeed: " + gpRes.gpToString())
	var gpStats: Dictionary = gpRes.gpPayload as Dictionary
	gpEq(int(gpStats.get("count", 0)), 2, "both sheets must be exported")
	gpEq(int(gpStats.get("total", 0)), 2, "the total must name the set size")
	gpCheck(bool(gpStats.get("catalog_ok", false)), "the catalog page must be written")
	gpCheck(int(gpStats.get("elapsed_ms", -1)) >= 0, "the measured duration must be present")
	gpCheck(FileAccess.file_exists(gpOutDir.path_join("001_Feed Area.pdf")),
		"sheet 001 must land under its numbered name")
	gpCheck(FileAccess.file_exists(gpOutDir.path_join("002_CIL.pdf")),
		"sheet 002 must land under its numbered name")
	gpCheck(FileAccess.file_exists(gpOutDir.path_join("_index.pdf")),
		"the catalog page must exist")
	var gpRows: Array = gpStats.get("rows", []) as Array
	gpCheck(gpRows.size() == 2, "the rows must carry both sheets")
	if gpRows.size() == 2:
		gpEq(str((gpRows[0] as Dictionary).get("number", "")), "001",
			"row 1 must carry the drawing number")
		gpEq(str((gpRows[1] as Dictionary).get("name", "")), "CIL",
			"row 2 must carry the sheet title")


# One broken sheet NEVER aborts the set: the good sheets export, the failure lands in
# the payload, and the catalog lists only what really landed.
# 一张坏图纸**绝不**中断整套：好图纸照常导出，失败进 payload，目录只列真正落盘的。
func gpTestAtlasContinuesOnPerSheetFailure() -> void:
	_gpCleanTmp()
	var gpOutDir: String = GP_TMP_DIR.path_join("partial")
	var gpBroken: GPSheet = GPSheet.new()
	gpBroken.gpName = "broken"
	gpBroken.gpWidthMM = 420.0
	gpBroken.gpHeightMM = 297.0
	var gpSheets: Array[GPSheet] = [_gpSheet("Good", "001"), gpBroken, _gpSheet("Last", "003")]
	var gpRes: GPIOResult = GPAtlasExporter.gpExportAtlas(gpSheets, gpOutDir,
		Callable(), _gpDefs())
	gpCheck(gpRes.gpOk, "one bad sheet must not fail the whole set")
	var gpStats: Dictionary = gpRes.gpPayload as Dictionary
	gpEq(int(gpStats.get("count", 0)), 2, "exactly the two good sheets export")
	gpEq((gpStats.get("failed", []) as Array).size(), 1, "the bad sheet must be reported")
	gpCheck(FileAccess.file_exists(gpOutDir.path_join("003_Last.pdf")),
		"the sheet AFTER the bad one must still export")
	gpCheck(FileAccess.file_exists(gpOutDir.path_join("_index.pdf")),
		"the catalog must list only the sheets that landed")


# Filename safety: path separators and OS-invalid characters collapse to "_"; an empty
# name degrades to "sheet". A ":" in a title would otherwise fork macOS paths silently.
# 文件名安全：路径分隔符与系统非法字符折叠为「_」；空名退化为「sheet」。图名里的
# 「:」否则会在 macOS 路径上悄悄分叉。
func gpTestSafeNameCollapsesInvalidCharacters() -> void:
	gpEq(GPAtlasExporter.gpSafeName("P-101: feed"), "P-101_ feed",
		"the colon must collapse")
	gpEq(GPAtlasExporter.gpSafeName("a/b\\c|d?e*f"), "a_b_c_d_e_f",
		"all invalid characters must collapse")
	gpEq(GPAtlasExporter.gpSafeName("   "), "sheet", "an empty name must degrade")


# The catalog layout is a PURE projection: the page holds the headers, the rule line, at
# most GP_MAX_ROWS data rows, and an honest "N more" line beyond that.
# 目录页排版是**纯投影**：页内含列头、表格线、至多 GP_MAX_ROWS 行数据，超出即如实写
# 「还有 N 张」。
func gpTestCatalogEntitiesPaginateHonestly() -> void:
	var gpTexts: Dictionary = {"title": "T", "subtitle": "S", "col_no": "N",
		"col_number": "NO", "col_name": "NAME", "col_file": "FILE",
		"more": "more %d"}
	var gpSmall: Array[Dictionary] = []
	for gpI in range(3):
		gpSmall.append({"number": "00%d" % (gpI + 1), "name": "s%d" % gpI, "file": "f%d" % gpI})
	var gpEntSmall: Array[Dictionary] = GPAtlasExporter.gpCatalogEntities(gpSmall, gpTexts)
	gpCheck(gpEntSmall.size() > 0, "the small catalog must produce entities")
	var gpHasMore: bool = false
	for gpE in gpEntSmall:
		if str(gpE["op"]) == GPPrintModel.GP_OP_TEXT and str(gpE.get("s", "")).contains("more"):
			gpHasMore = true
	gpCheck(not gpHasMore, "a 3-row set must NOT show the more-line")
	var gpBig: Array[Dictionary] = []
	for gpI in range(GPAtlasExporter.GP_MAX_ROWS + 10):
		gpBig.append({"number": "", "name": "s", "file": "f"})
	var gpEntBig: Array[Dictionary] = GPAtlasExporter.gpCatalogEntities(gpBig, gpTexts)
	var gpDataRows: int = 0
	var gpMoreText: String = ""
	for gpE in gpEntBig:
		if str(gpE["op"]) == GPPrintModel.GP_OP_TEXT and str(gpE.get("s", "")).contains("more"):
			gpMoreText = str(gpE.get("s", ""))
		if str(gpE["op"]) == GPPrintModel.GP_OP_TEXT and str(gpE.get("s", "")) == "s":
			gpDataRows += 1
	gpEq(gpDataRows, GPAtlasExporter.GP_MAX_ROWS, "the data rows must cap at GP_MAX_ROWS")
	gpEq(gpMoreText, "more 10", "the more-line must count the overflow honestly")
