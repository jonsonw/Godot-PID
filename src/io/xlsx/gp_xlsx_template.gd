class_name GPXlsxTemplate
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Reads one user/default template workbook and binds it to ONE deliverable list: which sheet
# is the data sheet, which row is the header, and which column maps to which field.
# 读取一个用户/默认模板工作簿，并把它绑定到**一类**清单：哪张表是数据表、哪一行是表头、
# 哪一列映射到哪个字段。
#
# BINDING PRIORITY / 绑定优先级：
#   1. explicit cell marker {{GP_LIST:line}} (or equipment/instrument/valve)
#   2. sheet name alias (管线/设备/仪表/阀门, Line/Equipment/Instrument/Valve)
#   3. header signature (key field + family fields)
# 1. 单元格标记；2. 工作表名别名；3. 表头签名。
#
# COLUMN PRIORITY / 列优先级：
#   1. {{field}} / {{prop:key}} token
#   2. static alias / label / key (normalised)
#   3. schema label from the symbols used in this export
# 1. 字段令牌；2. 静态别名/标签/key；3. 本次导出图元的 schema 标签。
#
# Coding rule: every variable declares its type explicitly; every function is static.
# 编码规范：所有变量显式声明类型；函数全部静态。

const GP_MARKER_PREFIX: String = "{{GP_LIST:"
const GP_HEADER_MARKER: String = "{{GP_HEADER}}"
const GP_SKIP_MARKER: String = "{{GP_SKIP}}"
const GP_COVER_MARKER: String = "{{GP_COVER}}"

const GP_SHEET_ALIASES: Dictionary = {
	"line": ["管线", "管道", "line", "piping"],
	"equipment": ["设备", "equipment", "vessel"],
	"instrument": ["仪表", "instrument", "index"],
	"valve": ["阀门", "valve"],
}

const GP_SHEET_SCAN_ROWS: int = 30


# Load a template workbook into memory. For res:// paths the bytes are copied to a user://
# cache file first, because ZIPReader needs a real file and PCK-packed resources are not one.
# 把模板工作簿读进内存。res:// 路径先复制到 user:// 缓存，因为 ZIPReader 需要真实文件，
# 而 PCK 内资源不是。
static func gpLoad(gpPath: String) -> Dictionary:
	if gpPath == "":
		return {"ok": false, "error": "missing_path"}
	var gpCleanup: String = ""
	var gpReadPath: String = gpPath
	if gpPath.begins_with("res://"):
		var gpBytes: PackedByteArray = FileAccess.get_file_as_bytes(gpPath)
		if gpBytes.is_empty():
			return {"ok": false, "error": "missing", "path": gpPath}
		var gpDir: String = "user://cache"
		if not DirAccess.dir_exists_absolute(gpDir):
			DirAccess.make_dir_recursive_absolute(gpDir)
		gpCleanup = gpDir.path_join("gp_xlsx_template_%d.xlsx" % Time.get_ticks_usec())
		var gpFile: FileAccess = FileAccess.open(gpCleanup, FileAccess.WRITE)
		if gpFile == null:
			return {"ok": false, "error": "cache_write", "path": gpPath}
		gpFile.store_buffer(gpBytes)
		gpFile.close()
		gpReadPath = gpCleanup
	var gpRead: Dictionary = GPXlsxPackage.gpReadArchive(gpReadPath)
	if gpCleanup != "":
		DirAccess.remove_absolute(gpCleanup)
	if not bool(gpRead.get("ok", false)):
		return {"ok": false, "error": str(gpRead.get("error", "read")), "path": gpPath}
	var gpEntries: Dictionary = gpRead.get("entries", {}) as Dictionary
	var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
	if not bool(gpBook.get("ok", false)):
		return {"ok": false, "error": "workbook", "path": gpPath}
	return {"ok": true, "entries": gpEntries, "sheets": gpBook.get("sheets", []),
		"path": gpPath}


# Bind a loaded template to one list. Options:
#   {"overrides": {"sheet": String}, "locale": "zh"}
# 把已载入模板绑定到一类清单。
static func gpBind(gpEntries: Dictionary, gpList: String, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary = {}) -> Dictionary:
	if not GPDeliverableFields.gpIsKnownList(gpList):
		return {"ok": false, "error": "unknown_list"}
	var gpBook: Dictionary = GPXlsxPackage.gpWorkbook(gpEntries)
	if not bool(gpBook.get("ok", false)):
		return {"ok": false, "error": "workbook"}
	var gpSheets: Array = gpBook.get("sheets", []) as Array
	var gpShared: Array[String] = GPXlsxPackage.gpSharedStrings(gpEntries)
	var gpDynamic: Dictionary = gpDynamicFields(gpDefs)
	var gpOverride: String = str((gpOptions.get("overrides", {}) as Dictionary).get("sheet", ""))
	var gpBest: Dictionary = {}
	var gpBestRank: int = -1
	var gpBestScore: int = -1
	for gpSheetRaw in gpSheets:
		var gpSheet: Dictionary = gpSheetRaw as Dictionary
		var gpName: String = str(gpSheet.get("name", ""))
		if gpOverride != "" and gpName != gpOverride:
			continue
		var gpRoot: Dictionary = GPXlsxXml.gpRootElement(
			GPXlsxPackage.gpReadPart(gpEntries, str(gpSheet.get("path", ""))))
		if GPXlsxXml.gpHasError(gpRoot):
			continue
		var gpMarker: String = _gpSheetMarker(gpRoot, gpShared)
		if gpMarker == "none" or gpMarker == "skip":
			continue
		if gpMarker != "" and gpMarker != gpList:
			continue
		var gpNameMatch: bool = _gpSheetNameMatches(gpName, gpList)
		var gpHeader: Dictionary = _gpFindHeader(gpRoot, gpList, gpShared, gpDynamic)
		var gpHeaderRow: int = int(gpHeader.get("row", 0))
		var gpScore: int = int(gpHeader.get("score", 0))
		if gpHeaderRow <= 0:
			continue
		if gpMarker == "" and not gpNameMatch and gpScore < 2:
			continue
		var gpRank: int = 3 if gpMarker != "" else (2 if gpNameMatch else 1)
		if gpRank > gpBestRank or (gpRank == gpBestRank and gpScore > gpBestScore):
			gpBestRank = gpRank
			gpBestScore = gpScore
			gpBest = {
				"ok": true,
				"list": gpList,
				"sheet_name": gpName,
				"sheet_path": str(gpSheet.get("path", "")),
				"header_row": gpHeaderRow,
				"data_start": gpHeaderRow + 1,
				"score": gpScore,
				"source": "marker" if gpMarker != "" else ("name" if gpNameMatch else "header"),
			}
	if gpBest.is_empty():
		return {"ok": false, "error": "no_sheet", "list": gpList}
	var gpRoot: Dictionary = GPXlsxXml.gpRootElement(
		GPXlsxPackage.gpReadPart(gpEntries, str(gpBest["sheet_path"])))
	var gpColumns: Dictionary = _gpColumns(gpRoot, int(gpBest["header_row"]), gpList,
		gpShared, gpDynamic)
	if gpColumns.is_empty():
		return {"ok": false, "error": "no_columns", "list": gpList,
			"sheet": gpBest["sheet_name"]}
	var gpKeyField: String = "line_no" if gpList == GPDeliverableFields.GP_LIST_LINE else "tag"
	var gpHasKey: bool = false
	for gpColRaw in gpColumns.keys():
		var gpCol: Dictionary = gpColumns[gpColRaw] as Dictionary
		if str(gpCol.get("key", "")) == gpKeyField:
			gpHasKey = true
			break
	if not gpHasKey:
		return {"ok": false, "error": "no_key", "list": gpList,
			"sheet": gpBest["sheet_name"], "key": gpKeyField}
	gpBest["columns"] = gpColumns
	# Current contract: the sample row is the row immediately below the header. If a later
	# row carries column tokens (e.g. {{tag}} three rows below a multi-row header), accepting
	# it silently would write data into a sub-header row and leave the template's old data.
	# Reject with a precise structural message instead of a confusing no_key.
	# 当前契约：样例行必须是表头下一行。若列令牌出现在更下面的行（例如多行表头下方三行），
	# 静默接受会把数据写进子表头并留下模板旧数据；这里用明确的结构错误拒绝，而不是 no_key。
	var gpTokenRow: int = _gpTokenRowBelowHeader(
		GPXlsxXml.gpRootElement(GPXlsxPackage.gpReadPart(gpEntries, str(gpBest["sheet_path"]))),
		int(gpBest["header_row"]), gpShared, gpDynamic, gpList)
	if gpTokenRow > 0 and gpTokenRow != int(gpBest["header_row"]) + 1:
		return {"ok": false, "error": "sample_row", "list": gpList,
			"sheet": gpBest["sheet_name"], "header_row": int(gpBest["header_row"]),
			"sample_row": gpTokenRow}
	return gpBest


# Probe a template path for a list. / 探测模板对某清单的绑定。
static func gpProbe(gpPath: String, gpList: String, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary = {}) -> Dictionary:
	var gpLoaded: Dictionary = gpLoad(gpPath)
	if not bool(gpLoaded.get("ok", false)):
		return gpLoaded
	var gpBound: Dictionary = gpBind(gpLoaded["entries"] as Dictionary, gpList, gpDefs, gpOptions)
	if not bool(gpBound.get("ok", false)):
		gpBound["sheets"] = gpLoaded.get("sheets", [])
		return gpBound
	gpBound["sheets"] = gpLoaded.get("sheets", [])
	gpBound["entries"] = gpLoaded["entries"]
	return gpBound


# Dynamic fields from the symbols used in this export: "prop:<key>" -> {label, kind}.
# 本次导出图元的扩展字段："prop:<key>" -> {label, kind}。
static func gpDynamicFields(gpDefs: Array[GPSymbolDef]) -> Dictionary:
	var gpOut: Dictionary = {}
	for gpDef in gpDefs:
		if gpDef == null or gpDef.gpSchema == null:
			continue
		for gpFieldDef in gpDef.gpSchema.gpFields:
			var gpKey: String = "prop:" + gpFieldDef.gpKey
			var gpKind: String = _gpKindOfProperty(gpFieldDef.gpKind)
			gpOut[gpKey] = {"key": gpKey, "kind": gpKind, "label": gpFieldDef.gpKey}
			var gpLabels: Array[String] = [
				gpFieldDef.gpLabel, gpFieldDef.gpKey, gpFieldDef.gpLabelKey,
			]
			for gpLabelRaw in gpLabels:
				var gpNorm: String = GPDeliverableFields.gpNormalizeHeader(str(gpLabelRaw))
				if gpNorm == "" or gpOut.has(gpNorm):
					continue
				gpOut[gpNorm] = {"key": gpKey, "kind": gpKind,
					"label": str(gpLabelRaw)}
	return gpOut


static func _gpKindOfProperty(gpKind: int) -> String:
	match gpKind:
		GPPropertyDef.GPKind.GP_INT:
			return "int"
		GPPropertyDef.GPKind.GP_FLOAT:
			return "float:2"
		GPPropertyDef.GPKind.GP_BOOL:
			return "bool"
	return "text"


# Find the header row: marker wins; otherwise the best alias score in the first 30 rows.
# 查找表头行：标记优先；否则前 30 行中别名得分最高者。
static func _gpFindHeader(gpRoot: Dictionary, gpList: String, gpShared: Array[String],
		gpDynamic: Dictionary) -> Dictionary:
	var gpData: Dictionary = GPXlsxXml.gpChild(gpRoot, "sheetData")
	var gpBestRow: int = 0
	var gpBestScore: int = 0
	for gpRowRaw in GPXlsxXml.gpChildren(gpData, "row"):
		var gpRow: Dictionary = gpRowRaw as Dictionary
		var gpRowNum: int = int(GPXlsxXml.gpAttr(gpRow, "r", "0"))
		if gpRowNum <= 0 or gpRowNum > GP_SHEET_SCAN_ROWS:
			continue
		var gpScore: int = 0
		var gpHasMarker: bool = false
		for gpCellRaw in GPXlsxXml.gpChildren(gpRow, "c"):
			var gpCell: Dictionary = gpCellRaw as Dictionary
			var gpText: String = GPXlsxSheet.gpCellText(gpCell, gpShared)
			if gpText.find(GP_HEADER_MARKER) >= 0:
				gpHasMarker = true
			var gpMatch: Dictionary = _gpMatchField(gpText, gpList, gpDynamic)
			if bool(gpMatch.get("ok", false)):
				gpScore += 1
				if bool(gpMatch.get("key_field", false)):
					gpScore += 2
		if gpHasMarker:
			return {"row": gpRowNum, "score": 1000}
		if gpScore > gpBestScore or (gpScore == gpBestScore and gpRowNum > gpBestRow):
			gpBestScore = gpScore
			gpBestRow = gpRowNum
	return {"row": gpBestRow, "score": gpBestScore}


static func _gpTokenRowBelowHeader(gpRoot: Dictionary, gpHeaderRow: int,
		gpShared: Array[String], gpDynamic: Dictionary, gpList: String) -> int:
	var gpData: Dictionary = GPXlsxXml.gpChild(gpRoot, "sheetData")
	for gpRowRaw in GPXlsxXml.gpChildren(gpData, "row"):
		var gpRow: Dictionary = gpRowRaw as Dictionary
		var gpRowNum: int = int(GPXlsxXml.gpAttr(gpRow, "r", "0"))
		if gpRowNum <= gpHeaderRow:
			continue
		for gpCellRaw in GPXlsxXml.gpChildren(gpRow, "c"):
			var gpText: String = GPXlsxSheet.gpCellText(gpCellRaw as Dictionary, gpShared)
			for gpToken in _gpTokens(gpText):
				if GPDeliverableFields.gpHasField(gpList, gpToken) 						or gpDynamic.has(gpToken) 						or gpDynamic.has(GPDeliverableFields.gpNormalizeHeader(gpToken)):
					return gpRowNum
	return 0


static func _gpColumns(gpRoot: Dictionary, gpHeaderRow: int, gpList: String,
		gpShared: Array[String], gpDynamic: Dictionary) -> Dictionary:
	var gpOut: Dictionary = {}
	var gpRow: Dictionary = GPXlsxSheet.gpRow(gpRoot, gpHeaderRow, false)
	if gpRow.is_empty():
		return gpOut
	for gpCellRaw in GPXlsxXml.gpChildren(gpRow, "c"):
		var gpCell: Dictionary = gpCellRaw as Dictionary
		var gpRef: String = GPXlsxXml.gpAttr(gpCell, "r", "")
		var gpCol: String = GPXlsxSheet.gpColumnName(GPXlsxSheet.gpColOfRef(gpRef))
		if gpCol == "":
			continue
		var gpText: String = GPXlsxSheet.gpCellText(gpCell, gpShared)
		var gpMatch: Dictionary = _gpMatchField(gpText, gpList, gpDynamic)
		if not bool(gpMatch.get("ok", false)):
			continue
		gpOut[gpCol] = {"key": str(gpMatch["key"]), "kind": str(gpMatch["kind"]),
			"label": str(gpMatch.get("label", ""))}
	return gpOut


# Match one header cell to a field. Token wins over text alias.
# 把一个表头单元格匹配到字段；令牌优先于文字别名。
static func _gpMatchField(gpText: String, gpList: String, gpDynamic: Dictionary) -> Dictionary:
	for gpToken in _gpTokens(gpText):
		var gpTokenKey: String = gpToken.strip_edges()
		if GPDeliverableFields.gpHasField(gpList, gpTokenKey):
			return {"ok": true, "key": gpTokenKey,
				"kind": GPDeliverableFields.gpKind(gpTokenKey),
				"key_field": GPDeliverableFields.gpIsRequired(gpTokenKey), "label": ""}
		if gpDynamic.has(gpTokenKey) or gpDynamic.has(GPDeliverableFields.gpNormalizeHeader(gpTokenKey)):
			var gpDyn: Dictionary = gpDynamic.get(gpTokenKey,
				gpDynamic.get(GPDeliverableFields.gpNormalizeHeader(gpTokenKey), {}))
			return {"ok": true, "key": str(gpDyn.get("key", gpTokenKey)),
				"kind": str(gpDyn.get("kind", "text")), "key_field": false,
				"label": str(gpDyn.get("label", ""))}
	var gpNorm: String = GPDeliverableFields.gpNormalizeHeader(gpText)
	if gpNorm == "":
		return {"ok": false}
	# Key columns win over generic aliases: a bilingual "Item 位号" header contains BOTH
	# "Item" (an alias of no) and "位号" (tag). Without this priority it was classified as
	# `no`, and the template then failed with no_key because no column was `tag`.
	# 关键列优先于泛别名：双语表头「Item 位号」同时包含「Item」（序号的别名）与「位号」（tag）。
	# 没有这条优先级时它会被判成 `no`，随后模板因没有 tag 列而报 no_key。
	var gpKeyField: String = "line_no" if gpList == GPDeliverableFields.GP_LIST_LINE else "tag"
	var gpKeyCandidates: Array[String] = [gpKeyField,
		GPDeliverableFields.gpLabel(gpKeyField, "zh"),
		GPDeliverableFields.gpLabel(gpKeyField, "en")]
	gpKeyCandidates.append_array(GPDeliverableFields.gpAliases(gpKeyField))
	for gpCandidateRaw in gpKeyCandidates:
		if GPDeliverableFields.gpNormalizeHeader(str(gpCandidateRaw)) == gpNorm:
			return {"ok": true, "key": gpKeyField,
				"kind": GPDeliverableFields.gpKind(gpKeyField),
				"key_field": true, "label": ""}
	for gpCandidateRaw in gpKeyCandidates:
		var gpCand: String = GPDeliverableFields.gpNormalizeHeader(str(gpCandidateRaw))
		if gpCand.length() >= 2 and gpNorm.find(gpCand) >= 0:
			return {"ok": true, "key": gpKeyField,
				"kind": GPDeliverableFields.gpKind(gpKeyField),
				"key_field": true, "label": ""}
	for gpKey in GPDeliverableFields.gpFieldsOf(gpList):
		var gpCandidates: Array[String] = [gpKey, GPDeliverableFields.gpLabel(gpKey, "zh"),
			GPDeliverableFields.gpLabel(gpKey, "en")]
		gpCandidates.append_array(GPDeliverableFields.gpAliases(gpKey))
		for gpCandidateRaw in gpCandidates:
			var gpCand: String = GPDeliverableFields.gpNormalizeHeader(str(gpCandidateRaw))
			if gpCand == "":
				continue
			if gpCand == gpNorm:
				return {"ok": true, "key": gpKey, "kind": GPDeliverableFields.gpKind(gpKey),
					"key_field": GPDeliverableFields.gpIsRequired(gpKey), "label": ""}
	for gpDynKey in gpDynamic.keys():
		var gpDyn: Dictionary = gpDynamic[gpDynKey] as Dictionary
		if str(gpDynKey) == gpNorm:
			return {"ok": true, "key": str(gpDyn.get("key", "")),
				"kind": str(gpDyn.get("kind", "text")), "key_field": false,
				"label": str(gpDyn.get("label", ""))}
	# Last resort: containment, but only for candidates long enough to be meaningful.
	# 最后一步：包含匹配，但别名至少 2 个字符，避免 No 命中 Nozzle。
	for gpKey in GPDeliverableFields.gpFieldsOf(gpList):
		var gpCandidates2: Array[String] = [GPDeliverableFields.gpLabel(gpKey, "zh"),
			GPDeliverableFields.gpLabel(gpKey, "en")]
		gpCandidates2.append_array(GPDeliverableFields.gpAliases(gpKey))
		for gpCandidateRaw in gpCandidates2:
			var gpCand: String = GPDeliverableFields.gpNormalizeHeader(str(gpCandidateRaw))
			if gpCand.length() >= 2 and (gpNorm.find(gpCand) >= 0 or gpCand.find(gpNorm) >= 0):
				return {"ok": true, "key": gpKey, "kind": GPDeliverableFields.gpKind(gpKey),
					"key_field": GPDeliverableFields.gpIsRequired(gpKey), "label": ""}
	return {"ok": false}


# All {{...}} tokens in a text. / 提取文本中的全部 {{...}} 令牌。
static func _gpTokens(gpText: String) -> Array[String]:
	var gpOut: Array[String] = []
	var gpStart: int = 0
	while true:
		var gpOpen: int = gpText.find("{{", gpStart)
		if gpOpen < 0:
			break
		var gpClose: int = gpText.find("}}", gpOpen + 2)
		if gpClose < 0:
			break
		gpOut.append(gpText.substr(gpOpen + 2, gpClose - gpOpen - 2))
		gpStart = gpClose + 2
	return gpOut


# Marker of a sheet: "line"/"equipment"/... / "none"/"skip"; "" when no marker.
# 工作表标记；无标记为空。
static func _gpSheetMarker(gpRoot: Dictionary, gpShared: Array[String]) -> String:
	var gpData: Dictionary = GPXlsxXml.gpChild(gpRoot, "sheetData")
	for gpRowRaw in GPXlsxXml.gpChildren(gpData, "row"):
		var gpRow: Dictionary = gpRowRaw as Dictionary
		for gpCellRaw in GPXlsxXml.gpChildren(gpRow, "c"):
			var gpText: String = GPXlsxSheet.gpCellText(gpCellRaw as Dictionary, gpShared)
			if gpText.find(GP_SKIP_MARKER) >= 0:
				return "skip"
			if gpText.find(GP_COVER_MARKER) >= 0:
				return "none"
			var gpIdx: int = gpText.find(GP_MARKER_PREFIX)
			if gpIdx >= 0:
				var gpClose: int = gpText.find("}}", gpIdx)
				if gpClose > gpIdx:
					return gpText.substr(gpIdx + GP_MARKER_PREFIX.length(),
						gpClose - gpIdx - GP_MARKER_PREFIX.length()).strip_edges()
	return ""


static func _gpSheetNameMatches(gpName: String, gpList: String) -> bool:
	var gpLower: String = gpName.to_lower()
	for gpAliasRaw in (GP_SHEET_ALIASES.get(gpList, []) as Array):
		if gpLower.find(str(gpAliasRaw).to_lower()) >= 0:
			return true
	return false
