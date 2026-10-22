class_name GPXlsxBuilder
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Builds a minimal but VALID .xlsx from plain row arrays. It is the fallback when the shipped
# default template asset is missing, and the fixture generator for the xlsx-engine tests.
# 用普通行数组构建一个**最小但有效**的 .xlsx。它是随包默认模板缺失时的回退，也是 xlsx 引擎
# 测试的夹具生成器。
#
# WHY THIS IS NOT THE DEFAULT TEMPLATE / 为何它不是默认模板：
# the shipped templates are authored in Excel (styles, print setup, merged title), because a
# user must be able to open and restyle them. This builder produces a plain, dependency-free
# workbook with just enough styling to be readable and printable.
# 随包模板在 Excel 里制作（样式、打印设置、合并标题），因为用户必须能打开并改样式。本构建器
# 只产出无依赖的朴素工作簿，样式仅够可读、可打印。
#
# Coding rule: every variable declares its type explicitly; every function is static.
# 编码规范：所有变量显式声明类型；函数全部静态。

const GP_NS_MAIN: String = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
const GP_NS_REL: String = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
const GP_NS_PKG_REL: String = "http://schemas.openxmlformats.org/package/2006/relationships"
const GP_CT_WORKBOOK: String = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"
const GP_CT_WORKSHEET: String = "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"
const GP_CT_STYLES: String = "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"
const GP_CT_CORE: String = "application/vnd.openxmlformats-package.core-properties+xml"
const GP_CT_APP: String = "application/vnd.openxmlformats-officedocument.extended-properties+xml"


# Build the package entries for a workbook.
# spec per sheet:
#   {name, rows: [[value, ...], ...], header_rows: int, widths: [float], merges: [String],
#    freeze_rows: int, auto_filter: String, print_area: String, landscape: bool}
# 构建工作簿的包条目。每个 sheet 的 spec 见上。
static func gpBuildWorkbook(gpSheets: Array) -> Dictionary:
	var gpEntries: Dictionary = {}
	var gpSheetDefs: Array = []
	var gpI: int = 0
	for gpSheetRaw in gpSheets:
		var gpSpec: Dictionary = gpSheetRaw as Dictionary
		gpI += 1
		var gpName: String = str(gpSpec.get("name", "Sheet%d" % gpI))
		gpName = _gpSafeSheetName(gpName)
		var gpPart: String = "xl/worksheets/sheet%d.xml" % gpI
		var gpSheetXml: Dictionary = gpBuildSheetXml(gpSpec)
		GPXlsxPackage.gpWritePart(gpEntries, gpPart, gpSheetXml)
		gpSheetDefs.append({"name": gpName, "part": gpPart, "sheet_id": str(gpI)})
	gpEntries[GPXlsxPackage.GP_CONTENT_TYPES] = _gpContentTypes(gpSheetDefs).to_utf8_buffer()
	gpEntries[GPXlsxPackage.GP_ROOT_RELS] = _gpRootRels().to_utf8_buffer()
	gpEntries[GPXlsxPackage.GP_WORKBOOK] = _gpWorkbook(gpSheetDefs).to_utf8_buffer()
	gpEntries[GPXlsxPackage.GP_WORKBOOK_RELS] = _gpWorkbookRels(gpSheetDefs).to_utf8_buffer()
	gpEntries[GPXlsxPackage.GP_STYLES] = _gpStyles().to_utf8_buffer()
	gpEntries["docProps/core.xml"] = _gpCoreProps().to_utf8_buffer()
	gpEntries["docProps/app.xml"] = _gpAppProps(gpSheetDefs).to_utf8_buffer()
	return gpEntries


# Build one worksheet XML node. / 构建一张工作表 XML 节点。
static func gpBuildSheetXml(gpSpec: Dictionary) -> Dictionary:
	var gpRoot: Dictionary = GPXlsxXml.gpElement("worksheet",
		{"xmlns": GP_NS_MAIN, "xmlns:r": GP_NS_REL})
	GPXlsxXml.gpAppendChild(gpRoot, GPXlsxXml.gpElement("dimension", {"ref": "A1"}))
	var gpFreeze: int = int(gpSpec.get("freeze_rows", 0))
	if gpFreeze > 0:
		var gpPane: Dictionary = GPXlsxXml.gpElement("pane", {
			"ySplit": str(gpFreeze),
			"topLeftCell": "A" + str(gpFreeze + 1),
			"activePane": "bottomLeft",
			"state": "frozen",
		})
		var gpView: Dictionary = GPXlsxXml.gpElement("sheetView",
			{"workbookViewId": "0", "tabSelected": "1"}, [gpPane])
		GPXlsxXml.gpAppendChild(gpRoot, GPXlsxXml.gpElement("sheetViews", {}, [gpView]))
	GPXlsxXml.gpAppendChild(gpRoot, GPXlsxXml.gpElement("sheetFormatPr",
		{"defaultRowHeight": "15"}))
	var gpWidths: Array = gpSpec.get("widths", []) as Array
	if not gpWidths.is_empty():
		var gpCols: Dictionary = GPXlsxXml.gpElement("cols")
		for gpI in range(gpWidths.size()):
			var gpWidth: float = float(gpWidths[gpI])
			GPXlsxXml.gpAppendChild(gpCols, GPXlsxXml.gpElement("col", {
				"min": str(gpI + 1), "max": str(gpI + 1),
				"width": str(gpWidth), "customWidth": "1",
			}))
		GPXlsxXml.gpAppendChild(gpRoot, gpCols)
	var gpData: Dictionary = GPXlsxXml.gpElement("sheetData")
	var gpRows: Array = gpSpec.get("rows", []) as Array
	var gpHeaderRows: int = int(gpSpec.get("header_rows", 1))
	for gpR in range(gpRows.size()):
		var gpRowVals: Array = gpRows[gpR] as Array
		var gpRowNode: Dictionary = GPXlsxXml.gpElement("row", {"r": str(gpR + 1)})
		var gpStyle: int = 1 if gpR < gpHeaderRows else 2
		for gpC in range(gpRowVals.size()):
			var gpValue: Variant = gpRowVals[gpC]
			var gpCell: Dictionary
			if gpValue is String:
				gpCell = _gpTextCell(GPXlsxSheet.gpCellRef(gpC + 1, gpR + 1), str(gpValue), gpStyle)
			elif gpValue is bool:
				gpCell = GPXlsxXml.gpElement("c", {
					"r": GPXlsxSheet.gpCellRef(gpC + 1, gpR + 1),
					"s": str(gpStyle), "t": "b",
				})
				var gpBoolV: Dictionary = GPXlsxXml.gpElement("v")
				gpBoolV["text"] = "1" if bool(gpValue) else "0"
				GPXlsxXml.gpAppendChild(gpCell, gpBoolV)
			elif (gpValue is int) or (gpValue is float):
				gpCell = GPXlsxXml.gpElement("c", {
					"r": GPXlsxSheet.gpCellRef(gpC + 1, gpR + 1), "s": str(gpStyle),
				})
				var gpNumV: Dictionary = GPXlsxXml.gpElement("v")
				gpNumV["text"] = str(gpValue)
				GPXlsxXml.gpAppendChild(gpCell, gpNumV)
			else:
				gpCell = _gpTextCell(GPXlsxSheet.gpCellRef(gpC + 1, gpR + 1),
					str(gpValue), gpStyle)
			GPXlsxXml.gpAppendChild(gpRowNode, gpCell)
		GPXlsxXml.gpAppendChild(gpData, gpRowNode)
	GPXlsxXml.gpAppendChild(gpRoot, gpData)
	var gpFilter: String = str(gpSpec.get("auto_filter", ""))
	if gpFilter != "":
		GPXlsxXml.gpAppendChild(gpRoot,
			GPXlsxXml.gpElement("autoFilter", {"ref": gpFilter}))
	var gpMerges: Array = gpSpec.get("merges", []) as Array
	if not gpMerges.is_empty():
		var gpMergeCells: Dictionary = GPXlsxXml.gpElement("mergeCells",
			{"count": str(gpMerges.size())})
		for gpRefRaw in gpMerges:
			GPXlsxXml.gpAppendChild(gpMergeCells,
				GPXlsxXml.gpElement("mergeCell", {"ref": str(gpRefRaw)}))
		GPXlsxXml.gpAppendChild(gpRoot, gpMergeCells)
	GPXlsxXml.gpAppendChild(gpRoot, GPXlsxXml.gpElement("pageMargins", {
		"left": "0.3", "right": "0.3", "top": "0.5", "bottom": "0.5",
		"header": "0.2", "footer": "0.2",
	}))
	var gpLandscape: bool = bool(gpSpec.get("landscape", false))
	var gpPageSetup: Dictionary = GPXlsxXml.gpElement("pageSetup", {
		"paperSize": "9",
		"orientation": "landscape" if gpLandscape else "portrait",
		"fitToWidth": "1",
		"fitToHeight": "0",
	})
	GPXlsxXml.gpAppendChild(gpRoot, gpPageSetup)
	GPXlsxSheet.gpUpdateDimension(gpRoot)
	return gpRoot


# Build entries and return the archive bytes. / 构建条目并返回归档字节。
static func gpBuildBytes(gpSheets: Array) -> PackedByteArray:
	var gpEntries: Dictionary = gpBuildWorkbook(gpSheets)
	var gpDir: String = "user://cache"
	if not DirAccess.dir_exists_absolute(gpDir):
		DirAccess.make_dir_recursive_absolute(gpDir)
	var gpTmp: String = gpDir.path_join("gp_xlsx_build_%d.xlsx" % Time.get_ticks_usec())
	var gpErr: int = GPXlsxPackage.gpWriteArchive(gpTmp, gpEntries)
	if gpErr != OK:
		return PackedByteArray()
	var gpFile: FileAccess = FileAccess.open(gpTmp, FileAccess.READ)
	if gpFile == null:
		return PackedByteArray()
	var gpBytes: PackedByteArray = gpFile.get_buffer(gpFile.get_length())
	gpFile.close()
	DirAccess.remove_absolute(gpTmp)
	return gpBytes


# Build and write directly to a path. / 直接写到路径。
static func gpBuildToPath(gpPath: String, gpSheets: Array) -> int:
	return GPXlsxPackage.gpWriteArchive(gpPath, gpBuildWorkbook(gpSheets))


static func _gpTextCell(gpRef: String, gpText: String, gpStyle: int) -> Dictionary:
	var gpCell: Dictionary = GPXlsxXml.gpElement("c",
		{"r": gpRef, "s": str(gpStyle), "t": "inlineStr"})
	var gpT: Dictionary = GPXlsxXml.gpElement("t", {"xml:space": "preserve"})
	gpT["text"] = gpText
	GPXlsxXml.gpAppendChild(gpCell, GPXlsxXml.gpElement("is", {}, [gpT]))
	return gpCell


static func _gpSafeSheetName(gpName: String) -> String:
	var gpOut: String = gpName.strip_edges()
	for gpBad in ["[", "]", ":", "*", "?", "/", "\\"]:
		gpOut = gpOut.replace(gpBad, "_")
	if gpOut == "":
		gpOut = "Sheet"
	if gpOut.length() > 31:
		gpOut = gpOut.substr(0, 31)
	return gpOut


static func _gpContentTypes(gpSheetDefs: Array) -> String:
	var gpOut: String = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
	gpOut += '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
	gpOut += '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
	gpOut += '<Default Extension="xml" ContentType="application/xml"/>'
	gpOut += '<Override PartName="/xl/workbook.xml" ContentType="%s"/>' % GP_CT_WORKBOOK
	gpOut += '<Override PartName="/xl/styles.xml" ContentType="%s"/>' % GP_CT_STYLES
	gpOut += '<Override PartName="/docProps/core.xml" ContentType="%s"/>' % GP_CT_CORE
	gpOut += '<Override PartName="/docProps/app.xml" ContentType="%s"/>' % GP_CT_APP
	for gpSheetRaw in gpSheetDefs:
		var gpSheet: Dictionary = gpSheetRaw as Dictionary
		gpOut += '<Override PartName="/%s" ContentType="%s"/>' % [str(gpSheet["part"]), GP_CT_WORKSHEET]
	return gpOut + "</Types>"


static func _gpRootRels() -> String:
	var gpOut: String = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
	gpOut += '<Relationships xmlns="%s">' % GP_NS_PKG_REL
	gpOut += '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
	gpOut += '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
	gpOut += '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
	return gpOut + "</Relationships>"


static func _gpWorkbook(gpSheetDefs: Array) -> String:
	var gpOut: String = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
	gpOut += '<workbook xmlns="%s" xmlns:r="%s">' % [GP_NS_MAIN, GP_NS_REL]
	gpOut += '<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="24000" windowHeight="12000"/></bookViews>'
	gpOut += "<sheets>"
	for gpI in range(gpSheetDefs.size()):
		var gpSheet: Dictionary = gpSheetDefs[gpI] as Dictionary
		gpOut += '<sheet name="%s" sheetId="%s" r:id="rId%d"/>' % [
			GPXlsxXml.gpEscapeAttr(str(gpSheet["name"])), str(gpSheet["sheet_id"]), gpI + 1]
	gpOut += "</sheets>"
	gpOut += '<calcPr calcId="191029" fullCalcOnLoad="1" forceFullCalc="1"/>'
	return gpOut + "</workbook>"


static func _gpWorkbookRels(gpSheetDefs: Array) -> String:
	var gpOut: String = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
	gpOut += '<Relationships xmlns="%s">' % GP_NS_PKG_REL
	for gpI in range(gpSheetDefs.size()):
		var gpSheet: Dictionary = gpSheetDefs[gpI] as Dictionary
		gpOut += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="%s"/>' % [
			gpI + 1, str(gpSheet["part"]).trim_prefix("xl/")]
	gpOut += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' % (gpSheetDefs.size() + 1)
	return gpOut + "</Relationships>"


static func _gpStyles() -> String:
	var gpOut: String = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
	gpOut += '<styleSheet xmlns="%s">' % GP_NS_MAIN
	gpOut += '<fonts count="4">'
	gpOut += '<font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>'
	gpOut += '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/><family val="2"/></font>'
	gpOut += '<font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>'
	gpOut += '<font><b/><sz val="14"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>'
	gpOut += "</fonts>"
	gpOut += '<fills count="3">'
	gpOut += '<fill><patternFill patternType="none"/></fill>'
	gpOut += '<fill><patternFill patternType="gray125"/></fill>'
	gpOut += '<fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/><bgColor indexed="64"/></patternFill></fill>'
	gpOut += "</fills>"
	gpOut += '<borders count="2">'
	gpOut += '<border><left/><right/><top/><bottom/><diagonal/></border>'
	gpOut += '<border><left style="thin"><color rgb="FFB7B7B7"/></left><right style="thin"><color rgb="FFB7B7B7"/></right><top style="thin"><color rgb="FFB7B7B7"/></top><bottom style="thin"><color rgb="FFB7B7B7"/></bottom><diagonal/></border>'
	gpOut += "</borders>"
	gpOut += '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
	gpOut += '<cellXfs count="4">'
	gpOut += '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
	gpOut += '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
	gpOut += '<xf numFmtId="0" fontId="2" fillId="0" borderId="1" xfId="0" applyBorder="1"/>'
	gpOut += '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
	gpOut += "</cellXfs>"
	gpOut += '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
	gpOut += '<dxfs count="0"/>'
	gpOut += '<tableStyles count="0" defaultTableStyle="TableStyleMedium9" defaultPivotStyle="PivotStyleLight16"/>'
	return gpOut + "</styleSheet>"


static func _gpCoreProps() -> String:
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
		+ '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" ' \
		+ 'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" ' \
		+ 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' \
		+ '<dc:creator>G-PID</dc:creator><cp:lastModifiedBy>G-PID</cp:lastModifiedBy>' \
		+ '<dcterms:created xsi:type="dcterms:W3CDTF">2026-01-01T00:00:00Z</dcterms:created>' \
		+ '<dcterms:modified xsi:type="dcterms:W3CDTF">2026-01-01T00:00:00Z</dcterms:modified>' \
		+ '</cp:coreProperties>'


static func _gpAppProps(gpSheetDefs: Array) -> String:
	var gpOut: String = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
	gpOut += '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
	gpOut += "<Application>G-PID</Application><DocSecurity>0</DocSecurity><ScaleCrop>false</ScaleCrop>"
	gpOut += '<HeadingPairs><vt:vector size="2" baseType="variant"><vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant><vt:variant><vt:i4>%d</vt:i4></vt:variant></vt:vector></HeadingPairs>' % gpSheetDefs.size()
	gpOut += '<TitlesOfParts><vt:vector size="%d" baseType="lpstr">' % gpSheetDefs.size()
	for gpSheetRaw in gpSheetDefs:
		gpOut += '<vt:lpstr>%s</vt:lpstr>' % GPXlsxXml.gpEscapeText(str((gpSheetRaw as Dictionary)["name"]))
	gpOut += "</vt:vector></TitlesOfParts></Properties>"
	return gpOut
