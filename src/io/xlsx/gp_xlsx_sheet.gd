class_name GPXlsxSheet
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Worksheet-level model: A1 references, row/cell lookup and creation, value typing, and the
# row-shift operation the template filler needs. It works on the DOM dictionaries produced by
# GPXlsxXml, so unknown child elements are preserved.
# 工作表级模型：A1 引用、行/单元格查找与创建、值类型，以及模板填充所需的整行平移。
# 它操作 GPXlsxXml 产出的 DOM 字典，故未知子元素得以保留。
#
# SCHEMA ORDER MATTERS / 子元素顺序重要：
# OOXML validates worksheet children in a fixed sequence. Appending <autoFilter> after
# <pageMargins> is exactly the kind of defect that makes Excel show "we found a problem".
# Every insertion goes through _gpInsertOrdered(), which keeps the documented order.
# OOXML 的 worksheet 子元素有固定顺序。把 <autoFilter> 追加到 <pageMargins> 之后，正是让 Excel
# 弹出「发现一个问题」的那类缺陷。所有插入都走 _gpInsertOrdered()，保持规范顺序。
#
# Coding rule: every variable declares its type explicitly; every function is static.
# 编码规范：所有变量显式声明类型；函数全部静态。

const GP_NS_MAIN: String = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
const GP_NS_REL: String = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

# Worksheet child order (subset that matters, plus unknown names at the end).
# worksheet 子元素顺序（相关子集，未知名排最后）。
const GP_WORKBOOK_ORDER: Dictionary = {
	"fileVersion": 0,
	"fileSharing": 1,
	"workbookPr": 2,
	"workbookProtection": 3,
	"bookViews": 4,
	"sheets": 5,
	"functionGroups": 6,
	"externalReferences": 7,
	"definedNames": 8,
	"calcPr": 9,
	"oleSize": 10,
	"customWorkbookViews": 11,
	"pivotCaches": 12,
	"smartTagPr": 13,
	"smartTagTypes": 14,
	"webPublishing": 15,
	"fileRecoveryPr": 16,
	"webPublishObjects": 17,
	"extLst": 18,
}

const GP_CHILD_ORDER: Dictionary = {
	"sheetPr": 0,
	"dimension": 1,
	"sheetViews": 2,
	"sheetFormatPr": 3,
	"cols": 4,
	"sheetData": 5,
	"sheetCalcPr": 6,
	"sheetProtection": 7,
	"protectedRanges": 8,
	"scenarios": 9,
	"autoFilter": 10,
	"sortState": 11,
	"dataConsolidate": 12,
	"customSheetViews": 13,
	"mergeCells": 14,
	"phoneticPr": 15,
	"conditionalFormatting": 16,
	"dataValidations": 17,
	"hyperlinks": 18,
	"printOptions": 19,
	"pageMargins": 20,
	"pageSetup": 21,
	"headerFooter": 22,
	"rowBreaks": 23,
	"colBreaks": 24,
	"customProperties": 25,
	"cellWatches": 26,
	"ignoredErrors": 27,
	"smartTags": 28,
	"drawing": 29,
	"legacyDrawing": 30,
	"legacyDrawingHF": 31,
	"picture": 32,
	"oleObjects": 33,
	"controls": 34,
	"webPublishItems": 35,
	"tableParts": 36,
	"extLst": 37,
}


# Column number (1-based) -> letters. / 列号（1 起）转字母。
static func gpColumnName(gpCol: int) -> String:
	if gpCol <= 0:
		return ""
	var gpN: int = gpCol
	var gpOut: String = ""
	while gpN > 0:
		var gpR: int = (gpN - 1) % 26
		gpOut = String.chr(65 + gpR) + gpOut
		gpN = (gpN - 1) / 26
	return gpOut


# Letters -> column number (1-based; 0 when invalid). / 字母转列号（1 起；非法为 0）。
static func gpColumnNumber(gpLetters: String) -> int:
	var gpOut: int = 0
	for gpI in range(gpLetters.length()):
		var gpC: String = gpLetters.substr(gpI, 1).to_upper()
		if gpC < "A" or gpC > "Z":
			return 0
		gpOut = gpOut * 26 + (gpC.unicode_at(0) - 64)
	return gpOut


# A1 reference. / A1 引用。
static func gpCellRef(gpCol: int, gpRow: int) -> String:
	return gpColumnName(gpCol) + str(gpRow)


# Parse "A1"/"$A$1" -> (col, row); (-1, -1) when invalid. / 解析 A1 引用。
static func gpParseRef(gpRef: String) -> Vector2i:
	var gpText: String = gpRef.replace("$", "").strip_edges().to_upper()
	var gpLetters: String = ""
	var gpDigits: String = ""
	for gpI in range(gpText.length()):
		var gpC: String = gpText.substr(gpI, 1)
		if gpC >= "A" and gpC <= "Z":
			if gpDigits != "":
				return Vector2i(-1, -1)
			gpLetters += gpC
		elif gpC.is_valid_int():
			gpDigits += gpC
		else:
			return Vector2i(-1, -1)
	if gpLetters == "" or gpDigits == "":
		return Vector2i(-1, -1)
	return Vector2i(gpColumnNumber(gpLetters), int(gpDigits))


static func gpRowOfRef(gpRef: String) -> int:
	return gpParseRef(gpRef).y


static func gpColOfRef(gpRef: String) -> int:
	return gpParseRef(gpRef).x


# <sheetData> child, created when missing. / <sheetData>，缺失时创建。
static func gpSheetData(gpSheet: Dictionary) -> Dictionary:
	var gpData: Dictionary = GPXlsxXml.gpChild(gpSheet, "sheetData")
	if not gpData.is_empty():
		return gpData
	gpData = GPXlsxXml.gpElement("sheetData")
	_gpInsertOrdered(gpSheet, gpData)
	return gpData


# Row node by 1-based row number, created when requested. / 按行号取行节点，可按需创建。
static func gpRow(gpSheet: Dictionary, gpRowNum: int, gpCreate: bool = false) -> Dictionary:
	var gpData: Dictionary = gpSheetData(gpSheet)
	for gpRowRaw in GPXlsxXml.gpChildren(gpData, "row"):
		var gpRowNode: Dictionary = gpRowRaw as Dictionary
		if int(GPXlsxXml.gpAttr(gpRowNode, "r", "0")) == gpRowNum:
			return gpRowNode
	if not gpCreate:
		return {}
	var gpNewRow: Dictionary = GPXlsxXml.gpElement("row", {"r": str(gpRowNum)})
	var gpChildren: Array = gpData.get("children", []) as Array
	var gpInsertAt: int = gpChildren.size()
	for gpI in range(gpChildren.size()):
		var gpChild: Dictionary = gpChildren[gpI] as Dictionary
		if GPXlsxXml.gpLocalName(str(gpChild.get("name", ""))) != "row":
			continue
		if int(GPXlsxXml.gpAttr(gpChild, "r", "0")) > gpRowNum:
			gpInsertAt = gpI
			break
	gpChildren.insert(gpInsertAt, gpNewRow)
	return gpNewRow


# Cell node by reference. / 按引用取单元格。
static func gpCell(gpSheet: Dictionary, gpRef: String) -> Dictionary:
	var gpPos: Vector2i = gpParseRef(gpRef)
	if gpPos.x <= 0 or gpPos.y <= 0:
		return {}
	var gpRowNode: Dictionary = gpRow(gpSheet, gpPos.y, false)
	if gpRowNode.is_empty():
		return {}
	for gpCellRaw in GPXlsxXml.gpChildren(gpRowNode, "c"):
		var gpCell: Dictionary = gpCellRaw as Dictionary
		if GPXlsxXml.gpAttr(gpCell, "r", "") == gpRef:
			return gpCell
	return {}


# Set a cell value. kind: text / number / bool / formula. style < 0 omits s.
# 写一个单元格。kind：text / number / bool / formula；style < 0 不写 s。
static func gpSetCell(gpSheet: Dictionary, gpRef: String, gpKind: String, gpValue: Variant,
		gpStyle: int = -1) -> Dictionary:
	var gpPos: Vector2i = gpParseRef(gpRef)
	if gpPos.x <= 0 or gpPos.y <= 0:
		return {}
	var gpRowNode: Dictionary = gpRow(gpSheet, gpPos.y, true)
	return gpSetCellInRow(gpRowNode, gpRef, gpKind, gpValue, gpStyle)


# Fast path for the filler: write into a row node it already holds. Scanning every row for
# EACH of thousands of cells turned a 2,000-row export into an O(rows^2) walk.
# 填充器快路径：直接写进已持有的行节点。为每个单元格扫描全表行会让 2,000 行导出退化为
# O(行数^2)。
static func gpSetCellInRow(gpRowNode: Dictionary, gpRef: String, gpKind: String,
		gpValue: Variant, gpStyle: int = -1) -> Dictionary:
	var gpPos: Vector2i = gpParseRef(gpRef)
	if gpPos.x <= 0 or gpPos.y <= 0 or gpRowNode.is_empty():
		return {}
	var gpChildren: Array = gpRowNode.get("children", []) as Array
	for gpI in range(gpChildren.size() - 1, -1, -1):
		var gpCell: Dictionary = gpChildren[gpI] as Dictionary
		if GPXlsxXml.gpAttr(gpCell, "r", "") == gpRef:
			gpChildren.remove_at(gpI)
	var gpAttrs: Dictionary = {"r": gpRef}
	if gpStyle >= 0:
		gpAttrs["s"] = str(gpStyle)
	var gpCellNode: Dictionary = GPXlsxXml.gpElement("c", gpAttrs)
	match gpKind:
		"text":
			gpCellNode["attrs"]["t"] = "inlineStr"
			var gpT: Dictionary = GPXlsxXml.gpElement("t", {"xml:space": "preserve"})
			gpT["text"] = str(gpValue)
			var gpIs: Dictionary = GPXlsxXml.gpElement("is", {}, [gpT])
			GPXlsxXml.gpAppendChild(gpCellNode, gpIs)
		"number":
			var gpV: Dictionary = GPXlsxXml.gpElement("v")
			gpV["text"] = str(gpValue)
			GPXlsxXml.gpAppendChild(gpCellNode, gpV)
		"bool":
			gpCellNode["attrs"]["t"] = "b"
			var gpB: Dictionary = GPXlsxXml.gpElement("v")
			gpB["text"] = "1" if bool(gpValue) else "0"
			GPXlsxXml.gpAppendChild(gpCellNode, gpB)
		"formula":
			var gpF: Dictionary = GPXlsxXml.gpElement("f")
			gpF["text"] = str(gpValue)
			GPXlsxXml.gpAppendChild(gpCellNode, gpF)
		"blank":
			pass
		_:
			return {}
	# Insert sorted by column. / 按列插入排序。
	var gpInsertAt: int = gpChildren.size()
	for gpI in range(gpChildren.size()):
		var gpOther: Dictionary = gpChildren[gpI] as Dictionary
		if gpColOfRef(GPXlsxXml.gpAttr(gpOther, "r", "")) > gpPos.x:
			gpInsertAt = gpI
			break
	gpChildren.insert(gpInsertAt, gpCellNode)
	return gpCellNode


# Read a cell value. sharedStrings must be the workbook's shared-string array.
# 读取单元格值。sharedStrings 必须是工作簿的共享字符串数组。
# Return: {"kind": "text"|"number"|"bool"|"empty"|"error", "value": Variant, "style": int}
static func gpCellValue(gpCell: Dictionary, gpShared: Array[String] = []) -> Dictionary:
	if gpCell.is_empty():
		return {"kind": "empty", "value": null, "style": -1}
	var gpStyle: int = int(GPXlsxXml.gpAttr(gpCell, "s", "-1"))
	var gpType: String = GPXlsxXml.gpAttr(gpCell, "t", "")
	if gpType == "inlineStr":
		var gpIs: Dictionary = GPXlsxXml.gpChild(gpCell, "is")
		var gpText: String = ""
		if not gpIs.is_empty():
			for gpTRaw in GPXlsxXml.gpChildren(gpIs, "t"):
				gpText += GPXlsxXml.gpTextOf(gpTRaw as Dictionary)
		return {"kind": "text", "value": gpText, "style": gpStyle}
	var gpVNode: Dictionary = GPXlsxXml.gpChild(gpCell, "v")
	var gpRaw: String = GPXlsxXml.gpTextOf(gpVNode)
	if gpType == "s":
		var gpIdx: int = int(gpRaw)
		var gpSharedText: String = str(gpShared[gpIdx]) if gpIdx >= 0 and gpIdx < gpShared.size() else ""
		return {"kind": "text", "value": gpSharedText, "style": gpStyle}
	if gpType == "str":
		return {"kind": "text", "value": gpRaw, "style": gpStyle}
	if gpType == "b":
		return {"kind": "bool", "value": gpRaw == "1", "style": gpStyle}
	if gpType == "e":
		return {"kind": "error", "value": gpRaw, "style": gpStyle}
	if gpRaw == "":
		return {"kind": "empty", "value": null, "style": gpStyle}
	if gpRaw.is_valid_float():
		return {"kind": "number", "value": float(gpRaw), "style": gpStyle}
	return {"kind": "text", "value": gpRaw, "style": gpStyle}


static func gpCellText(gpCell: Dictionary, gpShared: Array[String] = []) -> String:
	var gpValue: Dictionary = gpCellValue(gpCell, gpShared)
	var gpRaw: Variant = gpValue.get("value", null)
	if gpRaw == null:
		return ""
	if str(gpValue.get("kind", "")) == "bool":
		return "true" if bool(gpRaw) else "false"
	return str(gpRaw)


# Set/clear the worksheet dimension ref. / 设置/清除 dimension。
static func gpSetDimension(gpSheet: Dictionary, gpRef: String) -> void:
	var gpDim: Dictionary = GPXlsxXml.gpChild(gpSheet, "dimension")
	if gpDim.is_empty():
		gpDim = GPXlsxXml.gpElement("dimension", {"ref": gpRef})
		_gpInsertOrdered(gpSheet, gpDim)
		return
	GPXlsxXml.gpSetAttr(gpDim, "ref", gpRef)


# Recompute the dimension from existing rows/cells. / 由现有行列重算 dimension。
static func gpUpdateDimension(gpSheet: Dictionary) -> void:
	var gpData: Dictionary = gpSheetData(gpSheet)
	var gpMaxRow: int = 0
	var gpMaxCol: int = 0
	for gpRowRaw in GPXlsxXml.gpChildren(gpData, "row"):
		var gpRowNode: Dictionary = gpRowRaw as Dictionary
		var gpRowNum: int = int(GPXlsxXml.gpAttr(gpRowNode, "r", "0"))
		gpMaxRow = maxi(gpMaxRow, gpRowNum)
		for gpCellRaw in GPXlsxXml.gpChildren(gpRowNode, "c"):
			var gpCol: int = gpColOfRef(GPXlsxXml.gpAttr(gpCellRaw as Dictionary, "r", ""))
			gpMaxCol = maxi(gpMaxCol, gpCol)
	if gpMaxRow <= 0 or gpMaxCol <= 0:
		gpSetDimension(gpSheet, "A1")
		return
	gpSetDimension(gpSheet, "A1:" + gpCellRef(gpMaxCol, gpMaxRow))


# Set the auto-filter range. / 设置自动筛选范围。
static func gpSetAutoFilter(gpSheet: Dictionary, gpRef: String) -> void:
	if gpRef == "":
		return
	var gpFilter: Dictionary = GPXlsxXml.gpChild(gpSheet, "autoFilter")
	if gpFilter.is_empty():
		gpFilter = GPXlsxXml.gpElement("autoFilter", {"ref": gpRef})
		_gpInsertOrdered(gpSheet, gpFilter)
		return
	GPXlsxXml.gpSetAttr(gpFilter, "ref", gpRef)


# Set the print area by writing a defined name into the workbook node.
# 通过 workbook 的 definedName 设置打印区域。
static func gpSetPrintArea(gpWorkbook: Dictionary, gpSheetName: String, gpRef: String) -> void:
	var gpNames: Dictionary = GPXlsxXml.gpChild(gpWorkbook, "definedNames")
	if gpNames.is_empty():
		gpNames = GPXlsxXml.gpElement("definedNames")
		_gpInsertOrderedWith(gpWorkbook, gpNames, GP_WORKBOOK_ORDER)
	var gpName: String = "_xlnm.Print_Area"
	var gpValue: String = "'" + gpSheetName.replace("'", "''") + "'!" + _gpAbsRef(gpRef)
	var gpLocal: String = str(_gpSheetIndex(gpWorkbook, gpSheetName))
	for gpChildRaw in (gpNames.get("children", []) as Array):
		var gpChild: Dictionary = gpChildRaw as Dictionary
		if GPXlsxXml.gpAttr(gpChild, "name", "") == gpName:
			gpChild["text"] = gpValue
			GPXlsxXml.gpSetAttr(gpChild, "localSheetId", gpLocal)
			return
	var gpDef: Dictionary = GPXlsxXml.gpElement("definedName", {"name": gpName,
		"localSheetId": gpLocal})
	gpDef["text"] = gpValue
	GPXlsxXml.gpAppendChild(gpNames, gpDef)


# Shift every row at/after fromRow by delta. Also shifts cell refs, merges, autoFilter,
# hyperlinks and row breaks. Formulas are NOT rewritten here (the filler decides).
# 把 fromRow 及之后的行平移 delta；同步单元格引用、合并、筛选、超链接、分页符。
# 公式不在此重写（由填充器决定）。
static func gpShiftRows(gpSheet: Dictionary, gpFromRow: int, gpDelta: int) -> void:
	if gpDelta == 0 or gpFromRow <= 0:
		return
	var gpData: Dictionary = gpSheetData(gpSheet)
	for gpRowRaw in GPXlsxXml.gpChildren(gpData, "row"):
		var gpRowNode: Dictionary = gpRowRaw as Dictionary
		var gpRowNum: int = int(GPXlsxXml.gpAttr(gpRowNode, "r", "0"))
		if gpRowNum < gpFromRow:
			continue
		var gpNewRow: int = gpRowNum + gpDelta
		GPXlsxXml.gpSetAttr(gpRowNode, "r", str(gpNewRow))
		for gpCellRaw in GPXlsxXml.gpChildren(gpRowNode, "c"):
			var gpCell: Dictionary = gpCellRaw as Dictionary
			var gpRef: String = GPXlsxXml.gpAttr(gpCell, "r", "")
			var gpPos: Vector2i = gpParseRef(gpRef)
			if gpPos.x > 0 and gpPos.y >= gpFromRow:
				GPXlsxXml.gpSetAttr(gpCell, "r", gpCellRef(gpPos.x, gpPos.y + gpDelta))
	# Merge ranges / 合并范围
	for gpMergeRaw in GPXlsxXml.gpChildren(GPXlsxXml.gpChild(gpSheet, "mergeCells"), "mergeCell"):
		var gpMerge: Dictionary = gpMergeRaw as Dictionary
		var gpRef: String = GPXlsxXml.gpAttr(gpMerge, "ref", "")
		GPXlsxXml.gpSetAttr(gpMerge, "ref", _gpShiftRange(gpRef, gpFromRow, gpDelta))
	# Auto-filter / 自动筛选
	var gpFilter: Dictionary = GPXlsxXml.gpChild(gpSheet, "autoFilter")
	if not gpFilter.is_empty():
		GPXlsxXml.gpSetAttr(gpFilter, "ref",
			_gpShiftRange(GPXlsxXml.gpAttr(gpFilter, "ref", ""), gpFromRow, gpDelta))
	# Hyperlinks / 超链接
	for gpLinkRaw in GPXlsxXml.gpChildren(GPXlsxXml.gpChild(gpSheet, "hyperlinks"), "hyperlink"):
		var gpLink: Dictionary = gpLinkRaw as Dictionary
		var gpRef: String = GPXlsxXml.gpAttr(gpLink, "ref", "")
		GPXlsxXml.gpSetAttr(gpLink, "ref", _gpShiftRange(gpRef, gpFromRow, gpDelta))
	# Row breaks / 行分页符
	for gpBreakRaw in GPXlsxXml.gpChildren(GPXlsxXml.gpChild(gpSheet, "rowBreaks"), "brk"):
		var gpBreak: Dictionary = gpBreakRaw as Dictionary
		var gpId: int = int(GPXlsxXml.gpAttr(gpBreak, "id", "0"))
		if gpId >= gpFromRow:
			GPXlsxXml.gpSetAttr(gpBreak, "id", str(gpId + gpDelta))
	gpUpdateDimension(gpSheet)


# Remove one row and its cells. / 删除一整行。
static func gpRemoveRow(gpSheet: Dictionary, gpRowNum: int) -> void:
	var gpData: Dictionary = gpSheetData(gpSheet)
	var gpChildren: Array = gpData.get("children", []) as Array
	for gpI in range(gpChildren.size() - 1, -1, -1):
		var gpRowNode: Dictionary = gpChildren[gpI] as Dictionary
		if int(GPXlsxXml.gpAttr(gpRowNode, "r", "0")) == gpRowNum:
			gpChildren.remove_at(gpI)
			gpUpdateDimension(gpSheet)
			return


static func gpSetRowHeight(gpRowNode: Dictionary, gpHeight: float) -> void:
	GPXlsxXml.gpSetAttr(gpRowNode, "ht", str(gpHeight))
	GPXlsxXml.gpSetAttr(gpRowNode, "customHeight", "1")


# Insert a child while keeping the OOXML worksheet child order. / 按 OOXML 顺序插入子节点。
static func _gpInsertOrdered(gpSheet: Dictionary, gpChild: Dictionary) -> void:
	_gpInsertOrderedWith(gpSheet, gpChild, GP_CHILD_ORDER)


static func _gpInsertOrderedWith(gpNode: Dictionary, gpChild: Dictionary, gpOrder: Dictionary) -> void:
	var gpName: String = GPXlsxXml.gpLocalName(str(gpChild.get("name", "")))
	var gpRank: int = int(gpOrder.get(gpName, 100))
	var gpChildren: Array = gpNode.get("children", []) as Array
	var gpAt: int = gpChildren.size()
	for gpI in range(gpChildren.size()):
		var gpOther: Dictionary = gpChildren[gpI] as Dictionary
		var gpOtherName: String = GPXlsxXml.gpLocalName(str(gpOther.get("name", "")))
		if int(gpOrder.get(gpOtherName, 100)) > gpRank:
			gpAt = gpI
			break
	gpChildren.insert(gpAt, gpChild)


# Shift a range ref's end row when it reaches/overlaps fromRow. / 平移范围引用的结束行。
static func _gpShiftRange(gpRef: String, gpFromRow: int, gpDelta: int) -> String:
	if gpRef == "":
		return gpRef
	var gpParts: PackedStringArray = gpRef.split(":", false)
	if gpParts.size() == 1:
		var gpPos: Vector2i = gpParseRef(gpParts[0])
		if gpPos.x <= 0:
			return gpRef
		return gpCellRef(gpPos.x, gpPos.y + gpDelta) if gpPos.y >= gpFromRow else gpRef
	if gpParts.size() != 2:
		return gpRef
	var gpA: Vector2i = gpParseRef(gpParts[0])
	var gpB: Vector2i = gpParseRef(gpParts[1])
	if gpA.x <= 0 or gpB.x <= 0:
		return gpRef
	if gpB.y >= gpFromRow:
		gpB.y += gpDelta
	if gpA.y >= gpFromRow:
		gpA.y += gpDelta
	if gpA.y > gpB.y:
		gpA.y = gpB.y
	return gpCellRef(gpA.x, gpA.y) + ":" + gpCellRef(gpB.x, gpB.y)


static func _gpSheetIndex(gpWorkbook: Dictionary, gpSheetName: String) -> int:
	var gpSheets: Dictionary = GPXlsxXml.gpChild(gpWorkbook, "sheets")
	var gpIdx: int = 0
	for gpSheetRaw in GPXlsxXml.gpChildren(gpSheets, "sheet"):
		var gpSheet: Dictionary = gpSheetRaw as Dictionary
		if GPXlsxXml.gpAttr(gpSheet, "name", "") == gpSheetName:
			return gpIdx
		gpIdx += 1
	return 0


static func _gpAbsRef(gpRef: String) -> String:
	var gpParts: PackedStringArray = gpRef.split(":", false)
	if gpParts.size() == 1:
		var gpPos: Vector2i = gpParseRef(gpParts[0])
		return "$" + gpColumnName(gpPos.x) + "$" + str(gpPos.y) if gpPos.x > 0 else gpRef
	if gpParts.size() != 2:
		return gpRef
	var gpA: Vector2i = gpParseRef(gpParts[0])
	var gpB: Vector2i = gpParseRef(gpParts[1])
	if gpA.x <= 0 or gpB.x <= 0:
		return gpRef
	return "$" + gpColumnName(gpA.x) + "$" + str(gpA.y) + ":$" + gpColumnName(gpB.x) + "$" + str(gpB.y)
