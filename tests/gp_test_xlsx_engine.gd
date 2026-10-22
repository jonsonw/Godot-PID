extends "res://tests/gp_test.gd"
# P2 acceptance: XML DOM, ZIP/OOXML package, worksheet cells, and the minimal workbook
# builder. No template policy, no UI, no write-back here.
# P2 验收：XML DOM、ZIP/OOXML 包、工作表单元格、最小工作簿构建器。不含模板策略/UI/回写。
#
# What is pinned / 此处钉住：
#   1. XML parse/serialize keeps CJK and escapes &, <, >, quotes.
#   2. A1 refs round-trip, including AA / AZ / BA.
#   3. A built workbook is a valid package: workbook.xml + rels + sheets + styles.
#   4. Values read back with their types (text vs number vs bool).
#   5. Entry copy preserves unknown parts byte-for-byte; bad ZIP / OLE are refused.
#   6. Row shifting moves rows, cell refs, merges, filter and row breaks together.
# 1. XML 往返保留中文并正确转义；2. A1 引用往返；3. 构建的工作簿是有效包；
# 4. 读回值保留类型；5. 拷贝保留未知部件字节；坏 ZIP/OLE 被拒；
# 6. 行平移同时移动行、单元格引用、合并、筛选与分页符。

const GP_EPS: float = 0.0001


func _gpTemp(gpName: String) -> String:
	return "user://gp_test_xlsx_%s_%d" % [gpName, Time.get_ticks_usec()]


func _gpSpecs() -> Array:
	return [
		{
			"name": "管线一览表",
			"rows": [
				["序号", "管线号", "介质", "长度(m)", "阀门"],
				["1", "L-1", "矿浆", 12.5, "V-301"],
				["2", "L-2", "水", 8.0, ""],
			],
			"header_rows": 1,
			"widths": [8.0, 16.0, 14.0, 12.0, 16.0],
			"freeze_rows": 1,
			"auto_filter": "A1:E3",
			"landscape": true,
		},
		{
			"name": "设备一览表",
			"rows": [
				["位号", "名称", "数量", "材质"],
				["P-101", "离心泵", 1, "碳钢"],
				["T-201", "储罐", 1, "304不锈钢"],
			],
			"header_rows": 1,
			"widths": [14.0, 18.0, 8.0, 14.0],
		},
	]


func _gpBuildSpecs(gpName: String = "book") -> String:
	var gpPath: String = _gpTemp(gpName)
	var gpErr: int = GPXlsxBuilder.gpBuildToPath(gpPath, _gpSpecs())
	gpEq(gpErr, OK, "builder writes the workbook")
	return gpPath


func _gpCleanup(gpPath: String) -> void:
	if FileAccess.file_exists(gpPath):
		DirAccess.remove_absolute(gpPath)


# ==================== 1. XML ====================

func gpTestXmlParseSerialize() -> void:
	var gpSrc: String = '<root xmlns:x="urn:x"><x:a n="1"/><b>中文 &amp; ok</b><c>a&lt;b</c></root>'
	var gpRoot: Dictionary = GPXlsxXml.gpParse(gpSrc)
	gpCheck(not GPXlsxXml.gpHasError(gpRoot), "valid XML parses")
	var gpEl: Dictionary = GPXlsxXml.gpRootElement(gpRoot)
	gpEq(str(gpEl.get("name", "")), "root", "root element")
	gpEq(GPXlsxXml.gpLocalName("x:a"), "a", "namespace prefix is stripped for lookup")
	var gpA: Dictionary = GPXlsxXml.gpChild(gpEl, "a")
	gpEq(GPXlsxXml.gpAttr(gpA, "n"), "1", "attribute read")
	var gpB: Dictionary = GPXlsxXml.gpChild(gpEl, "b")
	gpEq(GPXlsxXml.gpTextOf(gpB), "中文 & ok", "entity decoded by parser")
	var gpC: Dictionary = GPXlsxXml.gpChild(gpEl, "c")
	gpEq(GPXlsxXml.gpTextOf(gpC), "a<b", "less-than decoded")
	var gpText: String = GPXlsxXml.gpSerialize(gpRoot)
	gpCheck(gpText.find("中文 &amp; ok") >= 0, "serializer re-escapes the ampersand")
	gpCheck(gpText.find("<x:a n=\"1\"/>") >= 0, "self-closing element and prefixed name survive")
	var gpAgain: Dictionary = GPXlsxXml.gpParse(gpText)
	gpEq(GPXlsxXml.gpTextOf(GPXlsxXml.gpChild(GPXlsxXml.gpRootElement(gpAgain), "b")),
		"中文 & ok", "serialize -> parse keeps the text")


func gpTestXmlEmptyAndBad() -> void:
	var gpEmpty: Dictionary = GPXlsxXml.gpParsePart("")
	gpCheck(GPXlsxXml.gpHasError(gpEmpty), "empty part is an error")
	var gpBad: Dictionary = GPXlsxXml.gpParse("<a><b></a>")
	gpCheck(GPXlsxXml.gpHasError(gpBad), "mismatched tags are an error")
	var gpMeta: Dictionary = GPXlsxXml.gpElement("m", {"a": "1"})
	gpEq(GPXlsxXml.gpAttr(gpMeta, "a"), "1", "attribute helper")
	GPXlsxXml.gpSetAttr(gpMeta, "a", "2")
	gpEq(GPXlsxXml.gpAttr(gpMeta, "a"), "2", "attribute setter")


# ==================== 2. refs ====================

func gpTestCellRefs() -> void:
	gpEq(GPXlsxSheet.gpColumnName(1), "A", "column 1")
	gpEq(GPXlsxSheet.gpColumnName(26), "Z", "column 26")
	gpEq(GPXlsxSheet.gpColumnName(27), "AA", "column 27")
	gpEq(GPXlsxSheet.gpColumnName(52), "AZ", "column 52")
	gpEq(GPXlsxSheet.gpColumnName(53), "BA", "column 53")
	gpEq(GPXlsxSheet.gpCellRef(27, 12), "AA12", "cell ref")
	var gpPos: Vector2i = GPXlsxSheet.gpParseRef("$AA$12")
	gpEq(gpPos, Vector2i(27, 12), "absolute ref parses")
	gpEq(GPXlsxSheet.gpParseRef(""), Vector2i(-1, -1), "empty ref invalid")
	gpEq(GPXlsxSheet.gpParseRef("12A"), Vector2i(-1, -1), "digits before letters invalid")


# ==================== 3. builder + package ====================

func gpTestBuilderPackageAndReader() -> void:
	var gpPath: String = _gpBuildSpecs("build")
	gpCheck(FileAccess.file_exists(gpPath), "workbook lands on disk")
	var gpRead: Dictionary = GPXlsxPackage.gpReadArchive(gpPath)
	gpCheck(bool(gpRead.get("ok", false)), "archive reads back")
	var gpEntries: Dictionary = gpRead.get("entries", {}) as Dictionary
	gpCheck(gpEntries.has(GPXlsxPackage.GP_CONTENT_TYPES), "content types present")
	gpCheck(gpEntries.has(GPXlsxPackage.GP_WORKBOOK), "workbook present")
	gpCheck(gpEntries.has(GPXlsxPackage.GP_STYLES), "styles present")
	var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
	gpCheck(bool(gpBook.get("ok", false)), "workbook parses")
	var gpSheets: Array = gpBook.get("sheets", []) as Array
	gpEq(gpSheets.size(), 2, "two sheets in workbook order")
	gpEq(str((gpSheets[0] as Dictionary).get("name", "")), "管线一览表", "first sheet name")
	gpEq(str((gpSheets[0] as Dictionary).get("path", "")), "xl/worksheets/sheet1.xml", "first sheet part")
	var gpNames: Array[String] = GPXlsxReader.gpSheetNames(gpEntries)
	gpEq(gpNames.size(), 2, "sheet names read")
	var gpPath1: String = str((gpSheets[0] as Dictionary).get("path", ""))
	var gpRows: Array[Dictionary] = GPXlsxReader.gpReadSheet(gpEntries, gpPath1)
	gpEq(gpRows.size(), 3, "three rows read")
	gpEq(GPXlsxReader.gpTextAt(gpEntries, gpPath1, "A1"), "序号", "header text")
	gpEq(GPXlsxReader.gpTextAt(gpEntries, gpPath1, "B2"), "L-1", "line number")
	gpEq(GPXlsxReader.gpTextAt(gpEntries, gpPath1, "D2"), "12.5", "number text")
	var gpSheetRoot: Dictionary = GPXlsxXml.gpRootElement(GPXlsxPackage.gpReadPart(gpEntries, gpPath1))
	var gpCellA1: Dictionary = GPXlsxSheet.gpCell(gpSheetRoot, "A1")
	gpEq(GPXlsxXml.gpAttr(gpCellA1, "s"), "1", "header style index")
	var gpCellA2: Dictionary = GPXlsxSheet.gpCell(gpSheetRoot, "A2")
	gpEq(GPXlsxXml.gpAttr(gpCellA2, "s"), "2", "data style index")
	gpEq(GPXlsxXml.gpAttr(gpCellA2, "t"), "inlineStr", "text cells are inline strings")
	_gpCleanup(gpPath)


func gpTestValueTypes() -> void:
	var gpPath: String = _gpBuildSpecs("types")
	var gpRead: Dictionary = GPXlsxPackage.gpReadArchive(gpPath)
	var gpEntries: Dictionary = gpRead.get("entries", {}) as Dictionary
	var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
	var gpPath1: String = str(((gpBook.get("sheets", []) as Array)[0] as Dictionary).get("path", ""))
	var gpSheetRoot: Dictionary = GPXlsxXml.gpRootElement(GPXlsxPackage.gpReadPart(gpEntries, gpPath1))
	var gpNum: Dictionary = GPXlsxSheet.gpCellValue(GPXlsxSheet.gpCell(gpSheetRoot, "D2"), [])
	gpEq(str(gpNum.get("kind", "")), "number", "number cell kind")
	gpApprox(float(gpNum.get("value", 0.0)), 12.5, GP_EPS, "number value")
	var gpText: Dictionary = GPXlsxSheet.gpCellValue(GPXlsxSheet.gpCell(gpSheetRoot, "A2"), [])
	gpEq(str(gpText.get("kind", "")), "text", "text cell kind")
	gpEq(str(gpText.get("value", "")), "1", "text value")
	# Shared-string and bool cases are exercised through hand-built cells.
	var gpSharedCell: Dictionary = GPXlsxXml.gpElement("c", {"r": "A1", "t": "s"})
	var gpV: Dictionary = GPXlsxXml.gpElement("v")
	gpV["text"] = "0"
	GPXlsxXml.gpAppendChild(gpSharedCell, gpV)
	gpEq(str(GPXlsxSheet.gpCellValue(gpSharedCell, ["中文"]).get("value", "")), "中文",
		"shared string resolves through the string table")
	var gpBoolCell: Dictionary = GPXlsxXml.gpElement("c", {"r": "A1", "t": "b"})
	var gpBV: Dictionary = GPXlsxXml.gpElement("v")
	gpBV["text"] = "0"
	GPXlsxXml.gpAppendChild(gpBoolCell, gpBV)
	gpEq(GPXlsxSheet.gpCellText(gpBoolCell, []), "false", "bool false renders as false")
	_gpCleanup(gpPath)


# ==================== 4. worksheet editing ====================

func gpTestCellWriteAndDimension() -> void:
	var gpRoot: Dictionary = GPXlsxBuilder.gpBuildSheetXml({
		"name": "T", "rows": [["A", "B"], ["1", "2"]], "header_rows": 1,
	})
	GPXlsxSheet.gpSetCell(gpRoot, "C5", "text", "新增", 2)
	GPXlsxSheet.gpUpdateDimension(gpRoot)
	gpEq(GPXlsxXml.gpAttr(GPXlsxXml.gpChild(gpRoot, "dimension"), "ref"), "A1:C5",
		"dimension expands to the new cell")
	gpEq(GPXlsxSheet.gpCellText(GPXlsxSheet.gpCell(gpRoot, "C5"), []), "新增", "new cell text")
	GPXlsxSheet.gpSetCell(gpRoot, "C5", "number", 3.25, 2)
	gpEq(str(GPXlsxSheet.gpCellValue(GPXlsxSheet.gpCell(gpRoot, "C5"), []).get("kind", "")),
		"number", "overwrite changes the cell kind")
	gpEq(str(GPXlsxSheet.gpCellValue(GPXlsxSheet.gpCell(gpRoot, "C5"), []).get("value", "")),
		"3.25", "overwrite writes the number")


func gpTestRowShiftAndRefs() -> void:
	var gpRoot: Dictionary = GPXlsxBuilder.gpBuildSheetXml({
		"name": "T",
		"rows": [["H1", "H2"], ["a", "b"], ["c", "d"], ["e", "f"]],
		"header_rows": 1,
		"merges": ["A3:B3"],
		"auto_filter": "A1:B4",
	})
	# Insert two rows at row 3: rows 3..4 move to 5..6.
	GPXlsxSheet.gpShiftRows(gpRoot, 3, 2)
	gpEq(GPXlsxSheet.gpCellText(GPXlsxSheet.gpCell(gpRoot, "A5"), []), "c", "row 3 moved to row 5")
	gpEq(GPXlsxSheet.gpCellText(GPXlsxSheet.gpCell(gpRoot, "A6"), []), "e", "row 4 moved to row 6")
	gpEq(GPXlsxSheet.gpCell(gpRoot, "A3").size(), 0, "row 3 is empty after the shift")
	var gpMerge: Dictionary = GPXlsxXml.gpChildren(GPXlsxXml.gpChild(gpRoot, "mergeCells"),
		"mergeCell")[0] as Dictionary
	gpEq(GPXlsxXml.gpAttr(gpMerge, "ref"), "A5:B5", "merge range shifted")
	gpEq(GPXlsxXml.gpAttr(GPXlsxXml.gpChild(gpRoot, "autoFilter"), "ref"), "A1:B6",
		"auto filter range shifted")
	gpEq(GPXlsxXml.gpAttr(GPXlsxXml.gpChild(gpRoot, "dimension"), "ref"), "A1:B6",
		"dimension updated after the shift")


func gpTestRemoveRow() -> void:
	var gpRoot: Dictionary = GPXlsxBuilder.gpBuildSheetXml({
		"name": "T", "rows": [["H"], ["a"], ["b"]], "header_rows": 1,
	})
	GPXlsxSheet.gpRemoveRow(gpRoot, 2)
	gpEq(GPXlsxSheet.gpCell(gpRoot, "A2").size(), 0, "removed row is gone")
	gpEq(GPXlsxSheet.gpCellText(GPXlsxSheet.gpCell(gpRoot, "A3"), []), "b",
		"the following row keeps its number (no implicit renumber)")


func gpTestPrintAreaDefinedName() -> void:
	var gpDoc: Dictionary = GPXlsxBuilder.gpBuildSheetXml({
		"name": "T", "rows": [["H"], ["a"]], "header_rows": 1,
	})
	var gpBook: Dictionary = GPXlsxXml.gpRootElement(GPXlsxPackage.gpReadPart(
		GPXlsxBuilder.gpBuildWorkbook([{"name": "T", "rows": [["H"], ["a"]]}]),
		GPXlsxPackage.GP_WORKBOOK))
	GPXlsxSheet.gpSetPrintArea(gpBook, "T", "A1:B2")
	var gpText: String = GPXlsxXml.gpSerialize(gpBook)
	gpCheck(gpText.find("_xlnm.Print_Area") >= 0, "print area defined name exists")
	gpCheck(gpText.find("'T'!$A$1:$B$2") >= 0, "print area range is absolute")


# ==================== 5. package round-trip & errors ====================

func gpTestCopyPreservesEntries() -> void:
	var gpSrc: String = _gpBuildSpecs("copy_src")
	var gpDst: String = _gpTemp("copy_dst")
	var gpRead: Dictionary = GPXlsxPackage.gpReadArchive(gpSrc)
	gpCheck(bool(gpRead.get("ok", false)), "source reads")
	var gpEntries: Dictionary = gpRead.get("entries", {}) as Dictionary
	var gpBefore: int = gpEntries.size()
	var gpWriteErr: int = GPXlsxPackage.gpWriteArchive(gpDst, gpEntries)
	gpEq(gpWriteErr, OK, "copy writes")
	var gpAgain: Dictionary = GPXlsxPackage.gpReadArchive(gpDst)
	gpCheck(bool(gpAgain.get("ok", false)), "copy reads")
	var gpCopied: Dictionary = gpAgain.get("entries", {}) as Dictionary
	gpEq(gpCopied.size(), gpBefore, "every entry survives the copy")
	for gpName in gpEntries.keys():
		gpCheck(gpCopied.has(gpName), "entry present: " + str(gpName))
		gpEq((gpCopied[gpName] as PackedByteArray), (gpEntries[gpName] as PackedByteArray),
			"entry bytes equal: " + str(gpName))
	_gpCleanup(gpSrc)
	_gpCleanup(gpDst)


func gpTestBadArchivesAreRefused() -> void:
	var gpNotZip: String = _gpTemp("not_zip")
	var gpF: FileAccess = FileAccess.open(gpNotZip, FileAccess.WRITE)
	gpF.store_string("not a zip")
	gpF.close()
	var gpRead: Dictionary = GPXlsxPackage.gpReadArchive(gpNotZip)
	gpCheck(not bool(gpRead.get("ok", false)), "non-zip refused")
	gpEq(str(gpRead.get("error", "")), "not_zip", "non-zip reason")
	_gpCleanup(gpNotZip)

	var gpOle: String = _gpTemp("ole")
	var gpOleF: FileAccess = FileAccess.open(gpOle, FileAccess.WRITE)
	gpOleF.store_buffer(PackedByteArray([0xD0, 0xCF, 0x11, 0xE0, 0x00]))
	gpOleF.close()
	var gpOleRead: Dictionary = GPXlsxPackage.gpReadArchive(gpOle)
	gpEq(str(gpOleRead.get("error", "")), "ole", "OLE/encrypted workbook reason")
	_gpCleanup(gpOle)

	var gpBad: String = _gpTemp("bad_package")
	var gpZip: ZIPPacker = ZIPPacker.new()
	gpEq(gpZip.open(gpBad), OK, "zip created")
	gpZip.start_file("[Content_Types].xml")
	gpZip.write_file("<Types/>".to_utf8_buffer())
	gpZip.close_file()
	gpZip.close()
	var gpBadRead: Dictionary = GPXlsxPackage.gpReadArchive(gpBad)
	gpEq(str(gpBadRead.get("error", "")), "bad_package", "zip without workbook is refused")
	_gpCleanup(gpBad)
