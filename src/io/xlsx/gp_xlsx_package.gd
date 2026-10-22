class_name GPXlsxPackage
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# ZIP + OOXML package plumbing for the deliverable exporter. It reads a workbook's parts
# into memory, parses the workbook/relationships, and writes a complete archive back without
# touching the parts it does not need to change.
# 交付导出器的 ZIP + OOXML 部件管线：把工作簿各部件读进内存、解析 workbook/relationships，
# 再写回完整归档；不需要改的部件保持原字节。
#
# WHY READ EVERYTHING INTO MEMORY / 为何全部读进内存：
# an xlsx is a ZIP; editing one sheet means rewriting the archive. Copying unknown parts
# byte-for-byte is the only way to preserve charts, macros (not supported here), themes and
# printer settings that this feature does not understand.
# xlsx 是 ZIP；改一张表就要重写归档。逐字节拷贝未知部件，是保留图表、主题、打印设置等
# 本功能不理解的部件的唯一办法。
#
# Coding rule: every variable declares its type explicitly; every function is static.
# 编码规范：所有变量显式声明类型；函数全部静态。

const GP_CONTENT_TYPES: String = "[Content_Types].xml"
const GP_ROOT_RELS: String = "_rels/.rels"
const GP_WORKBOOK: String = "xl/workbook.xml"
const GP_WORKBOOK_RELS: String = "xl/_rels/workbook.xml.rels"
const GP_STYLES: String = "xl/styles.xml"
const GP_SHARED_STRINGS: String = "xl/sharedStrings.xml"

const GP_MAGIC_ZIP: PackedByteArray = [0x50, 0x4B]
const GP_MAGIC_OLE: PackedByteArray = [0xD0, 0xCF, 0x11, 0xE0]


# Read every file entry of an xlsx into memory. Return:
#   {"ok": true, "entries": {name: PackedByteArray}, "path": path}
# or {"ok": false, "error": "missing"|"not_zip"|"ole"|"open"|"empty"|"bad_package", ...}
# 把 xlsx 的全部文件条目读进内存。返回成功/失败字典。
static func gpReadArchive(gpPath: String) -> Dictionary:
	if gpPath == "" or not FileAccess.file_exists(gpPath):
		return {"ok": false, "error": "missing", "path": gpPath}
	var gpMagic: PackedByteArray = _gpMagicOf(gpPath)
	if gpMagic.size() < 2 or gpMagic[0] != GP_MAGIC_ZIP[0] or gpMagic[1] != GP_MAGIC_ZIP[1]:
		if gpMagic.size() >= 4 and gpMagic[0] == GP_MAGIC_OLE[0] \
				and gpMagic[1] == GP_MAGIC_OLE[1] \
				and gpMagic[2] == GP_MAGIC_OLE[2] and gpMagic[3] == GP_MAGIC_OLE[3]:
			return {"ok": false, "error": "ole", "path": gpPath}
		return {"ok": false, "error": "not_zip", "path": gpPath}
	var gpZip: ZIPReader = ZIPReader.new()
	var gpErr: int = gpZip.open(gpPath)
	if gpErr != OK:
		return {"ok": false, "error": "open", "code": gpErr, "path": gpPath}
	var gpEntries: Dictionary = {}
	for gpNameRaw in gpZip.get_files():
		var gpName: String = str(gpNameRaw).replace("\\", "/")
		# Directory entries are not parts. / 目录条目不是部件。
		if gpName.ends_with("/") or gpName == "":
			continue
		var gpBytes: PackedByteArray = gpZip.read_file(gpName)
		gpEntries[gpName] = gpBytes
	gpZip.close()
	if gpEntries.is_empty():
		return {"ok": false, "error": "empty", "path": gpPath}
	if not gpEntries.has(GP_CONTENT_TYPES) or not gpEntries.has(GP_WORKBOOK):
		return {"ok": false, "error": "bad_package", "path": gpPath}
	return {"ok": true, "entries": gpEntries, "path": gpPath}


# Write a complete archive. Existing file is replaced only after the new archive is closed.
# 写出完整归档。只有新归档 close 后才覆盖既有文件。
static func gpWriteArchive(gpPath: String, gpEntries: Dictionary) -> int:
	if gpPath == "" or gpEntries.is_empty():
		return ERR_INVALID_PARAMETER
	var gpDir: String = gpPath.get_base_dir()
	if gpDir != "" and not DirAccess.dir_exists_absolute(gpDir):
		var gpMkErr: int = DirAccess.make_dir_recursive_absolute(gpDir)
		if gpMkErr != OK:
			return gpMkErr
	var gpZip: ZIPPacker = ZIPPacker.new()
	var gpErr: int = gpZip.open(gpPath)
	if gpErr != OK:
		return gpErr
	for gpName in gpOrderedNames(gpEntries):
		var gpStart: int = gpZip.start_file(gpName)
		if gpStart != OK:
			gpZip.close()
			_gpRemove(gpPath)
			return gpStart
		var gpBytes: Variant = gpEntries[gpName]
		if gpBytes is PackedByteArray:
			gpZip.write_file(gpBytes as PackedByteArray)
		gpZip.close_file()
	gpErr = gpZip.close()
	if gpErr != OK:
		_gpRemove(gpPath)
	return gpErr


# Stable entry order: content types and rels first, then workbook, styles, sheets, extras.
# 稳定条目顺序：content types / rels 在前，然后 workbook、styles、sheets、其它。
static func gpOrderedNames(gpEntries: Dictionary) -> Array[String]:
	var gpNames: Array[String] = []
	for gpNameRaw in gpEntries.keys():
		gpNames.append(str(gpNameRaw))
	gpNames.sort_custom(func(gpA: String, gpB: String) -> bool:
		var gpPa: int = _gpPartPriority(gpA)
		var gpPb: int = _gpPartPriority(gpB)
		if gpPa != gpPb:
			return gpPa < gpPb
		return gpA < gpB)
	return gpNames


# Parse the workbook and its relationships into sheet descriptors:
#   {"ok": true, "workbook": node, "rels": node, "sheets": [{name, sheet_id, rid, path}]}
# 解析 workbook 与 relationships，得到工作表描述。
static func gpWorkbook(gpEntries: Dictionary) -> Dictionary:
	if not gpEntries.has(GP_WORKBOOK):
		return {"ok": false, "error": "missing_workbook"}
	var gpWorkbookNode: Dictionary = gpReadPart(gpEntries, GP_WORKBOOK)
	if GPXlsxXml.gpHasError(gpWorkbookNode):
		return {"ok": false, "error": "bad_workbook", "detail": str(gpWorkbookNode.get("error", ""))}
	var gpWbEl: Dictionary = GPXlsxXml.gpRootElement(gpWorkbookNode)
	if gpWbEl.is_empty():
		return {"ok": false, "error": "bad_workbook", "detail": "no_workbook_element"}
	var gpRels: Dictionary = {}
	if gpEntries.has(GP_WORKBOOK_RELS):
		gpRels = gpReadPart(gpEntries, GP_WORKBOOK_RELS)
	var gpRelsEl: Dictionary = GPXlsxXml.gpRootElement(gpRels)
	var gpTargetById: Dictionary = {}
	for gpRelRaw in GPXlsxXml.gpChildren(gpRelsEl, "Relationship"):
		var gpRel: Dictionary = gpRelRaw as Dictionary
		var gpId: String = GPXlsxXml.gpAttr(gpRel, "Id")
		var gpTarget: String = GPXlsxXml.gpAttr(gpRel, "Target")
		var gpType: String = GPXlsxXml.gpAttr(gpRel, "Type")
		if gpId != "" and gpTarget != "" and gpType.find("worksheet") >= 0:
			gpTargetById[gpId] = _gpResolvePartPath("xl", gpTarget)
	var gpSheets: Array = []
	for gpSheetRaw in GPXlsxXml.gpChildren(GPXlsxXml.gpChild(gpWbEl, "sheets"), "sheet"):
		var gpSheet: Dictionary = gpSheetRaw as Dictionary
		var gpName: String = GPXlsxXml.gpAttr(gpSheet, "name")
		var gpRid: String = GPXlsxXml.gpAttr(gpSheet, "r:id")
		if gpRid == "":
			gpRid = GPXlsxXml.gpAttr(gpSheet, "id")
		var gpPath: String = str(gpTargetById.get(gpRid, ""))
		if gpPath == "":
			continue
		gpSheets.append({
			"name": gpName,
			"sheet_id": GPXlsxXml.gpAttr(gpSheet, "sheetId"),
			"rid": gpRid,
			"path": gpPath,
		})
	return {"ok": true, "workbook": gpWbEl, "rels": gpRelsEl, "sheets": gpSheets}


# Parse one XML part. / 解析一个 XML 部件。
static func gpReadPart(gpEntries: Dictionary, gpPart: String) -> Dictionary:
	if not gpEntries.has(gpPart):
		return {"name": "#document", "attrs": {}, "children": [], "text": "",
			"error": "missing_part"}
	var gpBytes: Variant = gpEntries[gpPart]
	if not (gpBytes is PackedByteArray):
		return {"name": "#document", "attrs": {}, "children": [], "text": "",
			"error": "bad_part"}
	return GPXlsxXml.gpParsePart((gpBytes as PackedByteArray).get_string_from_utf8())


# Serialize a node back into the entries dictionary. / 把节点序列化回 entries。
static func gpWritePart(gpEntries: Dictionary, gpPart: String, gpNode: Dictionary) -> void:
	gpEntries[gpPart] = GPXlsxXml.gpSerialize(gpNode).to_utf8_buffer()


# Text of a part ("" when absent). / 部件文本（缺失为空）。
static func gpPartText(gpEntries: Dictionary, gpPart: String) -> String:
	if not gpEntries.has(gpPart):
		return ""
	var gpBytes: Variant = gpEntries[gpPart]
	return (gpBytes as PackedByteArray).get_string_from_utf8() if gpBytes is PackedByteArray else ""


# Shared strings, preserving rich-text run order. / 共享字符串（保留富文本 run 顺序）。
static func gpSharedStrings(gpEntries: Dictionary) -> Array[String]:
	var gpOut: Array[String] = []
	if not gpEntries.has(GP_SHARED_STRINGS):
		return gpOut
	var gpRoot: Dictionary = gpReadPart(gpEntries, GP_SHARED_STRINGS)
	var gpSst: Dictionary = GPXlsxXml.gpRootElement(gpRoot)
	for gpSiRaw in GPXlsxXml.gpChildren(gpSst, "si"):
		var gpSi: Dictionary = gpSiRaw as Dictionary
		var gpText: String = ""
		# Plain <si><t>...</t></si> / 普通文本
		for gpChildRaw in (gpSi.get("children", []) as Array):
			var gpChild: Dictionary = gpChildRaw as Dictionary
			if GPXlsxXml.gpLocalName(str(gpChild.get("name", ""))) == "t":
				gpText += GPXlsxXml.gpTextOf(gpChild)
			elif GPXlsxXml.gpLocalName(str(gpChild.get("name", ""))) == "r":
				var gpT: Dictionary = GPXlsxXml.gpChild(gpChild, "t")
				if not gpT.is_empty():
					gpText += GPXlsxXml.gpTextOf(gpT)
		gpOut.append(gpText)
	return gpOut


# Resolve a relationship target relative to a base directory ("xl", "xl/worksheets", ...).
# 相对基准目录解析关系目标。
static func gpResolvePartPath(gpBaseDir: String, gpTarget: String) -> String:
	return _gpResolvePartPath(gpBaseDir, gpTarget)


# Ensure a part path is normalized and has no traversal. / 规范化部件路径并禁止上跳。
static func gpNormalizePart(gpPart: String) -> String:
	var gpOut: String = gpPart.replace("\\", "/")
	while gpOut.begins_with("/"):
		gpOut = gpOut.substr(1)
	if gpOut.find("..") >= 0:
		return ""
	return gpOut


# Copy one entry dictionary (byte arrays are shared; callers must not mutate them in place).
# 复制条目字典（字节数组共享；调用方不得原地修改）。
static func gpCopyEntries(gpEntries: Dictionary) -> Dictionary:
	var gpOut: Dictionary = {}
	for gpNameRaw in gpEntries.keys():
		gpOut[str(gpNameRaw)] = gpEntries[gpNameRaw]
	return gpOut


static func _gpResolvePartPath(gpBaseDir: String, gpTarget: String) -> String:
	var gpTargetNorm: String = gpTarget.replace("\\", "/")
	if gpTargetNorm.begins_with("/"):
		return gpNormalizePart(gpTargetNorm)
	var gpBase: String = gpBaseDir.strip_edges()
	var gpParts: Array[String] = []
	if gpBase != "":
		for gpPartRaw in gpBase.split("/", false):
			gpParts.append(str(gpPartRaw))
	for gpPartRaw in gpTargetNorm.split("/", false):
		var gpPart: String = str(gpPartRaw)
		if gpPart == "." or gpPart == "":
			continue
		if gpPart == "..":
			if not gpParts.is_empty():
				gpParts.pop_back()
			continue
		gpParts.append(gpPart)
	var gpOut: String = ""
	for gpPart in gpParts:
		if gpOut != "":
			gpOut += "/"
		gpOut += gpPart
	return gpOut


static func _gpPartPriority(gpName: String) -> int:
	if gpName == GP_CONTENT_TYPES:
		return 0
	if gpName == GP_ROOT_RELS:
		return 1
	if gpName.begins_with("docProps/"):
		return 2
	if gpName == GP_WORKBOOK:
		return 3
	if gpName == GP_WORKBOOK_RELS:
		return 4
	if gpName == GP_STYLES:
		return 5
	if gpName == GP_SHARED_STRINGS:
		return 6
	if gpName.begins_with("xl/worksheets/"):
		return 7
	return 8


static func _gpMagicOf(gpPath: String) -> PackedByteArray:
	var gpFile: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpFile == null:
		return PackedByteArray()
	var gpBytes: PackedByteArray = gpFile.get_buffer(4)
	gpFile.close()
	return gpBytes


static func _gpRemove(gpPath: String) -> void:
	if FileAccess.file_exists(gpPath):
		DirAccess.remove_absolute(gpPath)
