class_name GPXlsxFiller
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Fills a BOUND template sheet with deliverable rows: clone the sample row, write each column,
# shift the footer, replace tokens, and keep auto-filter / print area / dimension in step.
# 把已绑定模板表填成交付行：克隆样例行、逐列写值、平移页脚、替换令牌，并同步筛选/打印区域/维度。
#
# DATA REGION CONTRACT / 数据区契约：
#   header row = binding.header_row
#   sample row = header + 1   (the ONLY data template row)
#   footer     = header + 2 .. last row   (shifted by N-1)
# 表头下一行是样例行（唯一的数据模板行）；再往下都是页脚，按行数整体平移。
#
# WHAT IS NOT COPIED / 不复制什么：
# a sample cell without a column mapping is NOT copied as static text (that would repeat
# "示例" N times). If it has a formula, the formula is cloned and row-shifted; otherwise the
# cell stays blank but keeps its style/border.
# 未映射的样例单元格**不**作为静态文字复制（否则「示例」会重复 N 行）。若它有公式，则克隆并按行
# 平移；否则留空但保留样式/边框。
#
# Coding rule: every variable declares its type explicitly; every function is static.
# 编码规范：所有变量显式声明类型；函数全部静态。

const GP_SKIP_MARKER: String = "{{GP_SKIP}}"
const GP_COVER_MARKER: String = "{{GP_COVER}}"
const GP_MARKERS: Array[String] = [
	"{{GP_HEADER}}", "{{GP_SKIP}}", "{{GP_COVER}}",
]


# Fill one bound sheet. Return {"ok", "entries", "rows", "last_row", "issues"}.
# 填充一张已绑定表。返回 {"ok", "entries", "rows", "last_row", "issues"}。
static func gpFill(gpEntries: Dictionary, gpBinding: Dictionary, gpRows: Array,
		gpContext: Dictionary, gpList: String) -> Dictionary:
	var gpIssues: Array = []
	var gpPath: String = str(gpBinding.get("sheet_path", ""))
	if gpPath == "":
		return {"ok": false, "error": "no_sheet_path", "issues": gpIssues}
	var gpDoc: Dictionary = GPXlsxPackage.gpReadPart(gpEntries, gpPath)
	if GPXlsxXml.gpHasError(gpDoc):
		return {"ok": false, "error": "bad_sheet", "issues": gpIssues}
	var gpRoot: Dictionary = GPXlsxXml.gpRootElement(gpDoc)
	var gpShared: Array[String] = GPXlsxPackage.gpSharedStrings(gpEntries)
	var gpHeaderRow: int = int(gpBinding.get("header_row", 0))
	var gpDataStart: int = gpHeaderRow + 1
	var gpSample: Dictionary = _gpCaptureSample(gpRoot, gpDataStart, gpShared)
	if gpSample.is_empty():
		return {"ok": false, "error": "no_sample_row", "issues": gpIssues}
	var gpN: int = gpRows.size()
	var gpLastData: int = gpHeaderRow
	if gpN <= 0:
		# Remove the sample first, then pull the footer up. Doing it the other way round
		# would shift the footer into the sample row and then delete it.
		# 先删样例行，再把页脚上移。反过来会把页脚移到样例行位置然后一起删掉。
		GPXlsxSheet.gpRemoveRow(gpRoot, gpDataStart)
		GPXlsxSheet.gpShiftRows(gpRoot, gpDataStart + 1, -1)
	else:
		if gpN > 1:
			GPXlsxSheet.gpShiftRows(gpRoot, gpDataStart + 1, gpN - 1)
		var gpSampleRow: Dictionary = GPXlsxSheet.gpRow(gpRoot, gpDataStart, false)
		var gpPrevRow: Dictionary = gpSampleRow
		for gpI in range(gpN):
			var gpRowNode: Dictionary = gpSampleRow
			if gpI > 0:
				gpRowNode = gpSampleRow.duplicate(true)
				GPXlsxXml.gpSetAttr(gpRowNode, "r", str(gpDataStart + gpI))
				_gpInsertRowAfter(gpRoot, gpRowNode, gpPrevRow)
				gpPrevRow = gpRowNode
			_gpFillRow(gpRoot, gpRowNode, gpDataStart + gpI, gpRows[gpI] as Dictionary,
				gpBinding, gpSample, gpList, gpIssues)
		gpLastData = gpDataStart + gpN - 1

	_gpCleanHeader(gpRoot, gpBinding, gpShared, gpList, gpContext, gpIssues)
	_gpReplaceSheetTokens(gpRoot, gpShared, gpContext, gpIssues, false)

	# Auto-filter spans header..last data row. / 自动筛选覆盖表头到最后数据行。
	var gpColumns: Dictionary = gpBinding.get("columns", {}) as Dictionary
	if not gpColumns.is_empty():
		var gpMaxCol: int = 1
		for gpColRaw in gpColumns.keys():
			gpMaxCol = maxi(gpMaxCol, GPXlsxSheet.gpColumnNumber(str(gpColRaw)))
		var gpLastRow: int = maxi(gpLastData, gpHeaderRow)
		GPXlsxSheet.gpSetAutoFilter(gpRoot,
			"A%d:%s%d" % [gpHeaderRow, GPXlsxSheet.gpColumnName(gpMaxCol), gpLastRow])
	GPXlsxSheet.gpUpdateDimension(gpRoot)
	GPXlsxPackage.gpWritePart(gpEntries, gpPath, gpRoot)

	# Tokens on other sheets (cover / notes), and markers cleared everywhere.
	# 其它表（封面/说明）的令牌；所有表清除标记。
	var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
	if bool(gpBook.get("ok", false)):
		for gpSheetRaw in (gpBook.get("sheets", []) as Array):
			var gpSheet: Dictionary = gpSheetRaw as Dictionary
			var gpOtherPath: String = str(gpSheet.get("path", ""))
			if gpOtherPath == gpPath:
				continue
			var gpOtherDoc: Dictionary = GPXlsxPackage.gpReadPart(gpEntries, gpOtherPath)
			if GPXlsxXml.gpHasError(gpOtherDoc):
				continue
			var gpOtherRoot: Dictionary = GPXlsxXml.gpRootElement(gpOtherDoc)
			var gpSkip: bool = _gpHasMarker(gpOtherRoot,
				GPXlsxPackage.gpSharedStrings(gpEntries), "skip")
			_gpReplaceSheetTokens(gpOtherRoot, GPXlsxPackage.gpSharedStrings(gpEntries),
				gpContext, gpIssues, gpSkip)
			GPXlsxPackage.gpWritePart(gpEntries, gpOtherPath, gpOtherRoot)
		# Workbook-level calc and print area. / 工作簿级重算与打印区域。
		var gpWb: Dictionary = gpBook["workbook"] as Dictionary
		var gpCalc: Dictionary = GPXlsxXml.gpChild(gpWb, "calcPr")
		if gpCalc.is_empty():
			gpCalc = GPXlsxXml.gpElement("calcPr")
			GPXlsxXml.gpAppendChild(gpWb, gpCalc)
		GPXlsxXml.gpSetAttr(gpCalc, "fullCalcOnLoad", "1")
		GPXlsxXml.gpSetAttr(gpCalc, "forceFullCalc", "1")
		if not gpColumns.is_empty():
			var gpMaxCol2: int = 1
			for gpColRaw in gpColumns.keys():
				gpMaxCol2 = maxi(gpMaxCol2, GPXlsxSheet.gpColumnNumber(str(gpColRaw)))
			var gpLastRow2: int = _gpMaxRow(gpRoot)
			var gpStart: String = _gpPrintAreaStart(gpWb,
				str(gpBinding.get("sheet_name", "")))
			GPXlsxSheet.gpSetPrintArea(gpWb, str(gpBinding.get("sheet_name", "")),
				gpStart + ":" + GPXlsxSheet.gpCellRef(gpMaxCol2, gpLastRow2))
		GPXlsxPackage.gpWritePart(gpEntries, GPXlsxPackage.GP_WORKBOOK, gpWb)
	return {"ok": true, "entries": gpEntries, "rows": gpN, "last_row": gpLastData,
		"issues": gpIssues}


# Build the token context for one export. / 构建一次导出的令牌上下文。
static func gpTokenContext(gpSheets: Array, gpCounts: Dictionary, gpLocale: String,
		gpList: String, gpSheetName: String, gpSheetIndex: int, gpSheetTotal: int) -> Dictionary:
	var gpOut: Dictionary = {}
	gpOut["project.name"] = _gpTitleOf(gpSheets, "project")
	gpOut["project.title"] = _gpTitleOf(gpSheets, "drawing_title")
	gpOut["project.drawing_no"] = _gpJoinUniqueTitles(gpSheets, "drawing_no")
	gpOut["project.rev"] = _gpTitleOf(gpSheets, "rev")
	gpOut["project.date"] = _gpTitleOf(gpSheets, "date")
	gpOut["project.company"] = _gpTitleOf(gpSheets, "company")
	gpOut["project.sheet_count"] = gpSheets.size()
	gpOut["sheet.list"] = _gpSheetList(gpSheets)
	gpOut["sheet.name"] = gpSheetName
	gpOut["sheet.index"] = gpSheetIndex
	gpOut["sheet.total"] = gpSheetTotal
	gpOut["export.date"] = Time.get_date_string_from_system()
	gpOut["export.datetime"] = Time.get_datetime_string_from_system(false, true).replace("T", " ").substr(0, 16)
	gpOut["export.app"] = "G-PID " + str(ProjectSettings.get_setting("application/config/version", ""))
	gpOut["locale"] = gpLocale
	for gpListId in GPDeliverableFields.gpListIds():
		gpOut["list.%s.count" % gpListId] = int(gpCounts.get(gpListId, 0))
	return gpOut


# ==================== sample capture / 样例捕获 ====================

static func _gpCaptureSample(gpRoot: Dictionary, gpDataStart: int,
		gpShared: Array[String]) -> Dictionary:
	var gpRow: Dictionary = GPXlsxSheet.gpRow(gpRoot, gpDataStart, false)
	if gpRow.is_empty():
		return {}
	var gpCells: Dictionary = {}
	var gpFormulas: Dictionary = {}
	var gpStyles: Dictionary = {}
	for gpCellRaw in GPXlsxXml.gpChildren(gpRow, "c"):
		var gpCell: Dictionary = gpCellRaw as Dictionary
		var gpCol: String = GPXlsxSheet.gpColumnName(
			GPXlsxSheet.gpColOfRef(GPXlsxXml.gpAttr(gpCell, "r", "")))
		if gpCol == "":
			continue
		gpCells[gpCol] = gpCell.duplicate(true)
		gpStyles[gpCol] = int(GPXlsxXml.gpAttr(gpCell, "s", "-1"))
		var gpF: Dictionary = GPXlsxXml.gpChild(gpCell, "f")
		if not gpF.is_empty():
			gpFormulas[gpCol] = GPXlsxXml.gpTextOf(gpF)
	return {
		"row": gpRow.duplicate(true),
		"cells": gpCells,
		"formulas": gpFormulas,
		"styles": gpStyles,
		"height": float(GPXlsxXml.gpAttr(gpRow, "ht", "0")),
		"hidden": GPXlsxXml.gpAttr(gpRow, "hidden", ""),
		"outline": GPXlsxXml.gpAttr(gpRow, "outlineLevel", ""),
		"collapsed": GPXlsxXml.gpAttr(gpRow, "collapsed", ""),
	}


# ==================== row fill / 行填充 ====================

static func _gpFillRow(gpRoot: Dictionary, gpRowNode: Dictionary, gpRowNum: int,
		gpRow: Dictionary, gpBinding: Dictionary, gpSample: Dictionary, gpList: String,
		gpIssues: Array) -> void:
	var gpColumns: Dictionary = gpBinding.get("columns", {}) as Dictionary
	var gpSeen: Dictionary = {}
	for gpColRaw in (gpSample.get("cells", {}) as Dictionary).keys():
		var gpCol: String = str(gpColRaw)
		var gpRef: String = gpCol + str(gpRowNum)
		var gpStyle: int = int((gpSample.get("styles", {}) as Dictionary).get(gpCol, -1))
		var gpColInfo: Dictionary = gpColumns.get(gpCol, {}) as Dictionary
		if not gpColInfo.is_empty():
			_gpWriteMappedCell(gpRowNode, gpRef, gpColInfo, gpRow, gpStyle, gpIssues)
			gpSeen[gpCol] = true
			continue
		var gpFormula: String = str((gpSample.get("formulas", {}) as Dictionary).get(gpCol, ""))
		if gpFormula != "":
			GPXlsxSheet.gpSetCellInRow(gpRowNode, gpRef, "formula",
				_gpShiftFormula(gpFormula, gpRowNum - int(gpBinding.get("data_start", 1))),
				gpStyle)
		else:
			GPXlsxSheet.gpSetCellInRow(gpRowNode, gpRef, "blank", null, gpStyle)
		gpSeen[gpCol] = true
	# Columns mapped by the template but absent from the sample row.
	# 模板映射了但样例行没有的列。
	for gpColRaw in gpColumns.keys():
		var gpCol: String = str(gpColRaw)
		if gpSeen.has(gpCol):
			continue
		_gpWriteMappedCell(gpRowNode, gpCol + str(gpRowNum),
			gpColumns[gpCol] as Dictionary, gpRow, -1, gpIssues)
	var gpHeight: float = float(gpSample.get("height", 0.0))
	if gpHeight > 0.0:
		GPXlsxSheet.gpSetRowHeight(gpRowNode, gpHeight)
	if str(gpSample.get("hidden", "")) != "":
		GPXlsxXml.gpSetAttr(gpRowNode, "hidden", str(gpSample["hidden"]))
	if str(gpSample.get("outline", "")) != "":
		GPXlsxXml.gpSetAttr(gpRowNode, "outlineLevel", str(gpSample["outline"]))
	if str(gpSample.get("collapsed", "")) != "":
		GPXlsxXml.gpSetAttr(gpRowNode, "collapsed", str(gpSample["collapsed"]))


static func _gpWriteMappedCell(gpRowNode: Dictionary, gpRef: String, gpColInfo: Dictionary,
		gpRow: Dictionary, gpStyle: int, gpIssues: Array) -> void:
	var gpKey: String = str(gpColInfo.get("key", ""))
	var gpValue: Variant = null
	if gpKey.begins_with("prop:"):
		var gpProps: Dictionary = gpRow.get("props", {}) as Dictionary
		gpValue = gpProps.get(gpKey.substr("prop:".length()), null)
	else:
		gpValue = gpRow.get(gpKey, null)
	if _gpIsBlank(gpValue):
		GPXlsxSheet.gpSetCellInRow(gpRowNode, gpRef, "blank", null, gpStyle)
		return
	var gpKind: String = _gpCellKind(gpColInfo, gpValue)
	if gpKind == "number":
		var gpNum: Variant = _gpToNumber(gpValue)
		if gpNum == null:
			GPXlsxSheet.gpSetCellInRow(gpRowNode, gpRef, "blank", null, gpStyle)
			gpIssues.append({"code": "xlsx.value_not_numeric", "severity": "warning",
				"params": {"key": gpKey, "value": str(gpValue)}})
			return
		GPXlsxSheet.gpSetCellInRow(gpRowNode, gpRef, "number", gpNum, gpStyle)
		return
	if gpKind == "bool":
		GPXlsxSheet.gpSetCellInRow(gpRowNode, gpRef, "bool", bool(gpValue), gpStyle)
		return
	GPXlsxSheet.gpSetCellInRow(gpRowNode, gpRef, "text",
		GPDeliverableFields.gpValueText(gpValue), gpStyle)


static func _gpToNumber(gpValue: Variant) -> Variant:
	if (gpValue is int) or (gpValue is float):
		return float(gpValue)
	if gpValue is String and str(gpValue).strip_edges().is_valid_float():
		return float(str(gpValue).strip_edges())
	return null


static func _gpCellKind(gpColInfo: Dictionary, gpValue: Variant) -> String:
	var gpKind: String = str(gpColInfo.get("kind", "text"))
	if gpKind == "int" or gpKind.begins_with("float"):
		return "number"
	if gpKind == "bool":
		return "bool"
	return "text"


static func _gpIsBlank(gpValue: Variant) -> bool:
	if gpValue == null:
		return true
	if gpValue is String:
		return str(gpValue).strip_edges() == ""
	return false


# ==================== header / markers / tokens ====================

static func _gpCleanHeader(gpRoot: Dictionary, gpBinding: Dictionary,
		gpShared: Array[String], gpList: String, gpContext: Dictionary, gpIssues: Array) -> void:
	var gpHeaderRow: int = int(gpBinding.get("header_row", 0))
	var gpRow: Dictionary = GPXlsxSheet.gpRow(gpRoot, gpHeaderRow, false)
	if gpRow.is_empty():
		return
	var gpColumns: Dictionary = gpBinding.get("columns", {}) as Dictionary
	var gpLocale: String = str(gpContext.get("locale", "zh"))
	for gpCellRaw in GPXlsxXml.gpChildren(gpRow, "c"):
		var gpCell: Dictionary = gpCellRaw as Dictionary
		var gpText: String = GPXlsxSheet.gpCellText(gpCell, gpShared)
		if gpText.find("{{") < 0:
			continue
		var gpRef: String = GPXlsxXml.gpAttr(gpCell, "r", "")
		var gpStyle: int = int(GPXlsxXml.gpAttr(gpCell, "s", "-1"))
		var gpNew: String = gpText
		var gpHadColumn: bool = false
		for gpColRaw in gpColumns.keys():
			var gpColInfo: Dictionary = gpColumns[gpColRaw] as Dictionary
			var gpKey: String = str(gpColInfo.get("key", ""))
			var gpToken: String = "{{" + gpKey + "}}"
			if gpNew.find(gpToken) >= 0:
				gpHadColumn = true
				if gpNew.strip_edges() == gpToken:
					gpNew = _gpHeaderLabel(gpColInfo, gpLocale)
				else:
					gpNew = gpNew.replace(gpToken, "").strip_edges()
		gpNew = _gpStripMarkers(gpNew)
		if gpNew == "" and gpHadColumn:
			# A header cell that was only a token now uses its label; a marker-only cell
			# stays blank.
			# 只写令牌的表头用字段标签；只有标记的单元格留空。
			gpNew = ""
		if gpNew != gpText:
			GPXlsxSheet.gpSetCell(gpRoot, gpRef, "text", gpNew, gpStyle)


static func _gpHeaderLabel(gpColInfo: Dictionary, gpLocale: String) -> String:
	var gpLabel: String = str(gpColInfo.get("label", ""))
	if gpLabel != "":
		return gpLabel
	var gpKey: String = str(gpColInfo.get("key", ""))
	if gpKey.begins_with("prop:"):
		return gpKey.substr("prop:".length())
	return GPDeliverableFields.gpLabel(gpKey, gpLocale)


static func _gpReplaceSheetTokens(gpRoot: Dictionary, gpShared: Array[String],
		gpContext: Dictionary, gpIssues: Array, gpSkip: bool) -> void:
	var gpData: Dictionary = GPXlsxXml.gpChild(gpRoot, "sheetData")
	for gpRowRaw in GPXlsxXml.gpChildren(gpData, "row"):
		var gpRow: Dictionary = gpRowRaw as Dictionary
		for gpCellRaw in GPXlsxXml.gpChildren(gpRow, "c"):
			var gpCell: Dictionary = gpCellRaw as Dictionary
			if not GPXlsxXml.gpChild(gpCell, "f").is_empty():
				continue
			var gpText: String = GPXlsxSheet.gpCellText(gpCell, gpShared)
			if gpText.find("{{") < 0:
				continue
			var gpNew: String = gpText
			if not gpSkip:
				for gpKey in gpContext.keys():
					gpNew = gpNew.replace("{{" + str(gpKey) + "}}", str(gpContext[gpKey]))
			gpNew = _gpStripMarkers(gpNew)
			if gpNew == gpText:
				continue
			var gpRef: String = GPXlsxXml.gpAttr(gpCell, "r", "")
			var gpStyle: int = int(GPXlsxXml.gpAttr(gpCell, "s", "-1"))
			GPXlsxSheet.gpSetCell(gpRoot, gpRef, "text", gpNew, gpStyle)


static func _gpStripMarkers(gpText: String) -> String:
	var gpOut: String = gpText
	for gpMarker in GP_MARKERS:
		gpOut = gpOut.replace(gpMarker, "")
	while true:
		var gpOpen: int = gpOut.find("{{GP_LIST:")
		if gpOpen < 0:
			break
		var gpClose: int = gpOut.find("}}", gpOpen)
		if gpClose < 0:
			break
		gpOut = gpOut.substr(0, gpOpen) + gpOut.substr(gpClose + 2)
	return gpOut.strip_edges()


static func _gpHasMarker(gpRoot: Dictionary, gpShared: Array[String], gpMarker: String) -> bool:
	var gpData: Dictionary = GPXlsxXml.gpChild(gpRoot, "sheetData")
	for gpRowRaw in GPXlsxXml.gpChildren(gpData, "row"):
		for gpCellRaw in GPXlsxXml.gpChildren(gpRowRaw as Dictionary, "c"):
			var gpText: String = GPXlsxSheet.gpCellText(gpCellRaw as Dictionary, gpShared)
			if gpMarker == "skip" and gpText.find(GP_SKIP_MARKER) >= 0:
				return true
			if gpMarker == "cover" and gpText.find(GP_COVER_MARKER) >= 0:
				return true
	return false


# ==================== misc helpers / 杂项 ====================

static func _gpInsertRowAfter(gpRoot: Dictionary, gpRow: Dictionary, gpAfter: Dictionary) -> void:
	var gpData: Dictionary = GPXlsxXml.gpChild(gpRoot, "sheetData")
	var gpChildren: Array = gpData.get("children", []) as Array
	for gpI in range(gpChildren.size()):
		if gpChildren[gpI] == gpAfter:
			gpChildren.insert(gpI + 1, gpRow)
			return
	gpChildren.append(gpRow)


static func _gpShiftFormula(gpFormula: String, gpDelta: int) -> String:
	if gpDelta == 0:
		return gpFormula
	var gpRe: RegEx = RegEx.new()
	var gpErr: int = gpRe.compile("(?<![A-Za-z0-9_])(\\$?)([A-Z]{1,3})(\\$?)([0-9]+)")
	if gpErr != OK:
		return gpFormula
	var gpOut: String = ""
	var gpPos: int = 0
	for gpMatch in gpRe.search_all(gpFormula):
		var gpRowAbs: bool = gpMatch.get_string(3) == "$"
		var gpRowNum: int = int(gpMatch.get_string(4))
		if not gpRowAbs:
			gpRowNum += gpDelta
		gpOut += gpFormula.substr(gpPos, gpMatch.get_start() - gpPos)
		gpOut += gpMatch.get_string(1) + gpMatch.get_string(2) + gpMatch.get_string(3) + str(gpRowNum)
		gpPos = gpMatch.get_end()
	gpOut += gpFormula.substr(gpPos)
	return gpOut


static func _gpPrintAreaStart(gpWorkbook: Dictionary, gpSheetName: String) -> String:
	var gpNames: Dictionary = GPXlsxXml.gpChild(gpWorkbook, "definedNames")
	var gpIdx: int = _gpSheetIndex(gpWorkbook, gpSheetName)
	for gpNameRaw in GPXlsxXml.gpChildren(gpNames, "definedName"):
		var gpName: Dictionary = gpNameRaw as Dictionary
		if GPXlsxXml.gpAttr(gpName, "name", "") != "_xlnm.Print_Area":
			continue
		var gpLocal: String = GPXlsxXml.gpAttr(gpName, "localSheetId", "-1")
		if gpLocal != "-1" and gpLocal != str(gpIdx):
			continue
		var gpText: String = GPXlsxXml.gpTextOf(gpName)
		var gpBang: int = gpText.rfind("!")
		if gpBang < 0:
			continue
		var gpRange: String = gpText.substr(gpBang + 1)
		var gpParts: PackedStringArray = gpRange.split(":", false)
		if gpParts.is_empty():
			continue
		var gpPos: Vector2i = GPXlsxSheet.gpParseRef(gpParts[0])
		if gpPos.x > 0 and gpPos.y > 0:
			return GPXlsxSheet.gpCellRef(gpPos.x, gpPos.y)
	return "A1"


static func _gpSheetIndex(gpWorkbook: Dictionary, gpSheetName: String) -> int:
	var gpSheets: Dictionary = GPXlsxXml.gpChild(gpWorkbook, "sheets")
	var gpIdx: int = 0
	for gpSheetRaw in GPXlsxXml.gpChildren(gpSheets, "sheet"):
		if GPXlsxXml.gpAttr(gpSheetRaw as Dictionary, "name", "") == gpSheetName:
			return gpIdx
		gpIdx += 1
	return 0


static func _gpMaxRow(gpRoot: Dictionary) -> int:
	var gpMax: int = 1
	var gpData: Dictionary = GPXlsxXml.gpChild(gpRoot, "sheetData")
	for gpRowRaw in GPXlsxXml.gpChildren(gpData, "row"):
		gpMax = maxi(gpMax, int(GPXlsxXml.gpAttr(gpRowRaw as Dictionary, "r", "0")))
	return gpMax


static func _gpTitleOf(gpSheets: Array, gpKey: String) -> String:
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null:
			continue
		var gpValue: String = gpSheet.gpTitleValue(gpKey)
		if gpValue.strip_edges() != "":
			return gpValue
	return ""


static func _gpJoinUniqueTitles(gpSheets: Array, gpKey: String) -> String:
	var gpOut: Array[String] = []
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null:
			continue
		var gpValue: String = gpSheet.gpTitleValue(gpKey).strip_edges()
		if gpValue != "" and not gpOut.has(gpValue):
			gpOut.append(gpValue)
	return _gpJoin(gpOut, ", ")


static func _gpSheetList(gpSheets: Array) -> String:
	var gpOut: Array[String] = []
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null:
			continue
		var gpName: String = gpSheet.gpName.strip_edges()
		if gpName == "":
			gpName = "图纸 %d" % (gpSheet.gpIndex + 1)
		gpOut.append(gpName)
	return _gpJoin(gpOut, ", ")


static func _gpJoin(gpParts: Array[String], gpSep: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpParts.size()):
		if gpI > 0:
			gpOut += gpSep
		gpOut += gpParts[gpI]
	return gpOut
