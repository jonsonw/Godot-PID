class_name GPXlsxReader
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Read-side helpers for tests and the property write-back importer: sheet rows/cells with
# typed values (text / number / bool / error). No editing here.
# 测试与属性回写导入器的读取侧助手：按行/单元格返回带类型的值（文本/数字/布尔/错误）。
# 此处不做编辑。
#
# Coding rule: every variable declares its type explicitly; every function is static.
# 编码规范：所有变量显式声明类型；函数全部静态。

# Read one sheet as rows:
#   [{"row": int, "cells": {"A": {"kind", "value", "style"}, ...}}, ...]
# 读取一张表为行数组。
static func gpReadSheet(gpEntries: Dictionary, gpSheetPath: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	var gpDoc: Dictionary = GPXlsxPackage.gpReadPart(gpEntries, gpSheetPath)
	if GPXlsxXml.gpHasError(gpDoc):
		return gpOut
	var gpRoot: Dictionary = GPXlsxXml.gpRootElement(gpDoc)
	var gpShared: Array[String] = GPXlsxPackage.gpSharedStrings(gpEntries)
	var gpData: Dictionary = GPXlsxXml.gpChild(gpRoot, "sheetData")
	for gpRowRaw in GPXlsxXml.gpChildren(gpData, "row"):
		var gpRowNode: Dictionary = gpRowRaw as Dictionary
		var gpRowNum: int = int(GPXlsxXml.gpAttr(gpRowNode, "r", "0"))
		var gpCells: Dictionary = {}
		for gpCellRaw in GPXlsxXml.gpChildren(gpRowNode, "c"):
			var gpCell: Dictionary = gpCellRaw as Dictionary
			gpCells[GPXlsxXml.gpAttr(gpCell, "r", "")] = GPXlsxSheet.gpCellValue(gpCell, gpShared)
		gpOut.append({"row": gpRowNum, "cells": gpCells})
	return gpOut


# Read one sheet into a rectangular matrix of raw values (row-major, 0-based).
# 读取一张表为矩形原始值矩阵（行优先，0 起）。
static func gpReadMatrix(gpEntries: Dictionary, gpSheetPath: String) -> Array:
	var gpRows: Array[Dictionary] = gpReadSheet(gpEntries, gpSheetPath)
	var gpMaxRow: int = 0
	var gpMaxCol: int = 0
	for gpRow in gpRows:
		var gpCells: Dictionary = gpRow["cells"] as Dictionary
		gpMaxRow = maxi(gpMaxRow, int(gpRow["row"]))
		for gpRefRaw in gpCells.keys():
			gpMaxCol = maxi(gpMaxCol, GPXlsxSheet.gpColOfRef(str(gpRefRaw)))
	var gpOut: Array = []
	for gpR in range(gpMaxRow):
		var gpLine: Array = []
		for gpC in range(gpMaxCol):
			gpLine.append(null)
		gpOut.append(gpLine)
	for gpRow in gpRows:
		var gpR: int = int(gpRow["row"]) - 1
		if gpR < 0 or gpR >= gpOut.size():
			continue
		var gpCells: Dictionary = gpRow["cells"] as Dictionary
		for gpRefRaw in gpCells.keys():
			var gpC: int = GPXlsxSheet.gpColOfRef(str(gpRefRaw)) - 1
			if gpC < 0 or gpC >= (gpOut[gpR] as Array).size():
				continue
			var gpVal: Dictionary = gpCells[gpRefRaw] as Dictionary
			(gpOut[gpR] as Array)[gpC] = gpVal.get("value", null)
	return gpOut


# Read a cell's display text from a sheet ("" when absent). / 读取单元格显示文本。
static func gpTextAt(gpEntries: Dictionary, gpSheetPath: String, gpRef: String) -> String:
	var gpDoc: Dictionary = GPXlsxPackage.gpReadPart(gpEntries, gpSheetPath)
	if GPXlsxXml.gpHasError(gpDoc):
		return ""
	var gpRoot: Dictionary = GPXlsxXml.gpRootElement(gpDoc)
	var gpCell: Dictionary = GPXlsxSheet.gpCell(gpRoot, gpRef)
	if gpCell.is_empty():
		return ""
	return GPXlsxSheet.gpCellText(gpCell, GPXlsxPackage.gpSharedStrings(gpEntries))


# Sheet descriptors by name ({} when absent). / 按名取工作表描述。
static func gpSheetByName(gpEntries: Dictionary, gpName: String) -> Dictionary:
	var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
	if not bool(gpBook.get("ok", false)):
		return {}
	for gpSheetRaw in (gpBook.get("sheets", []) as Array):
		var gpSheet: Dictionary = gpSheetRaw as Dictionary
		if str(gpSheet.get("name", "")) == gpName:
			return gpSheet
	return {}


# All sheet names in workbook order. / 工作簿顺序的全部表名。
static func gpSheetNames(gpEntries: Dictionary) -> Array[String]:
	var gpOut: Array[String] = []
	var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
	if not bool(gpBook.get("ok", false)):
		return gpOut
	for gpSheetRaw in (gpBook.get("sheets", []) as Array):
		gpOut.append(str((gpSheetRaw as Dictionary).get("name", "")))
	return gpOut
