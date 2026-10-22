class_name GPXlsxImport
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Read a classified-list workbook back into property/name/edge-attribute changes. It NEVER
# creates or deletes entities, never writes tags/line numbers, and never touches geometry.
# 把分类清单工作簿读回属性/名称/边属性变更。绝不新建/删除实体，绝不写位号/管线号，绝不碰几何。
#
# MATCHING / 匹配：
#   line rows      -> every PROCESS edge on the sheet whose tag == line_no
#   other rows     -> the node whose tag == row tag (unique; duplicates are ambiguous)
#   sheet column   -> picks the drawing; missing column is only OK when one drawing is open
# 管线行 -> 该图纸上 tag == 管线号 的全部工艺边；其它行 -> 位号唯一匹配的节点；
# sheet 列 -> 选图纸；无 sheet 列时仅允许只开一张图纸。
#
# BLANK = CLEAR / 空白=清空：
# an empty cell removes the property/name/edge attr, letting the library default win again.
# 空单元格移除属性/名称/边属性，让库默认值重新生效。
#
# Coding rule: every variable declares its type explicitly; every function is static.
# 编码规范：所有变量显式声明类型；函数全部静态。

const GP_EDGE_ATTRS: Array[String] = ["dn", "spec", "medium", "insulation"]


# Read files and produce a preview. gpFiles: [{path, list}] (list may be "" for auto-detect).
# 读取文件并生成预览。gpFiles: [{path, list}]（list 可为空自动识别）。
static func gpRead(gpFiles: Array, gpSheets: Array, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary = {}) -> Dictionary:
	var gpLocale: String = str(gpOptions.get("locale", "zh"))
	var gpTypeLabels: Dictionary = gpOptions.get("type_labels", {}) as Dictionary
	var gpIssues: Array = []
	var gpChanges: Array = []
	var gpFileResults: Array = []
	for gpFileRaw in gpFiles:
		var gpFile: Dictionary = gpFileRaw as Dictionary
		var gpPath: String = str(gpFile.get("path", ""))
		var gpList: String = str(gpFile.get("list", ""))
		var gpLoaded: Dictionary = GPXlsxTemplate.gpLoad(gpPath)
		if not bool(gpLoaded.get("ok", false)):
			gpIssues.append(_gpIssue("xlsx.read_failed", {"path": gpPath,
				"error": str(gpLoaded.get("error", "?"))}))
			gpFileResults.append({"path": gpPath, "list": gpList, "ok": false,
				"error": str(gpLoaded.get("error", "?"))})
			continue
		var gpEntries: Dictionary = gpLoaded["entries"] as Dictionary
		if gpList == "":
			gpList = _gpDetectList(gpEntries, gpDefs, gpLocale)
		if not GPDeliverableFields.gpIsKnownList(gpList):
			gpIssues.append(_gpIssue("xlsx.list_not_recognised", {"path": gpPath}))
			gpFileResults.append({"path": gpPath, "list": gpList, "ok": false,
				"error": "list"})
			continue
		var gpBinding: Dictionary = GPXlsxTemplate.gpBind(gpEntries, gpList, gpDefs,
			{"locale": gpLocale})
		if not bool(gpBinding.get("ok", false)):
			gpIssues.append(_gpIssue("xlsx.bind_failed", {"path": gpPath,
				"error": str(gpBinding.get("error", "?"))}))
			gpFileResults.append({"path": gpPath, "list": gpList, "ok": false,
				"error": str(gpBinding.get("error", "?"))})
			continue
		var gpFileBefore: int = gpChanges.size()
		_readFile(gpEntries, gpBinding, gpList, gpSheets, gpLocale, gpDefs, gpTypeLabels,
			gpChanges, gpIssues)
		gpFileResults.append({"path": gpPath, "list": gpList, "ok": true,
			"changes": gpChanges.size() - gpFileBefore})
	var gpDeduped: Array = _gpDedupe(gpChanges)
	return {
		"ok": true,
		"files": gpFileResults,
		"changes": gpDeduped,
		"issues": gpIssues,
		"summary": _gpSummary(gpDeduped),
	}


# Detect the list by trying to bind each catalogue list. / 尝试绑定四类清单来自动识别。
static func _gpDetectList(gpEntries: Dictionary, gpDefs: Array[GPSymbolDef],
		gpLocale: String) -> String:
	for gpList in GPDeliverableFields.gpListIds():
		var gpBind: Dictionary = GPXlsxTemplate.gpBind(gpEntries, gpList, gpDefs,
			{"locale": gpLocale})
		if bool(gpBind.get("ok", false)):
			return gpList
	return ""


static func _readFile(gpEntries: Dictionary, gpBinding: Dictionary, gpList: String,
		gpSheets: Array, gpLocale: String, gpDefs: Array[GPSymbolDef],
		gpTypeLabels: Dictionary, gpChanges: Array, gpIssues: Array) -> void:
	var gpPath: String = str(gpBinding.get("sheet_path", ""))
	var gpRows: Array[Dictionary] = GPXlsxReader.gpReadSheet(gpEntries, gpPath)
	var gpDataStart: int = int(gpBinding.get("data_start", 1))
	var gpColumns: Dictionary = gpBinding.get("columns", {}) as Dictionary
	var gpKeyField: String = "line_no" if gpList == GPDeliverableFields.GP_LIST_LINE else "tag"
	for gpRow in gpRows:
		var gpRowNum: int = int(gpRow.get("row", 0))
		if gpRowNum < gpDataStart:
			continue
		var gpCells: Dictionary = gpRow.get("cells", {}) as Dictionary
		var gpValues: Dictionary = {}
		for gpColRaw in gpColumns.keys():
			var gpCol: String = str(gpColRaw)
			var gpInfo: Dictionary = gpColumns[gpColRaw] as Dictionary
			var gpKey: String = str(gpInfo.get("key", ""))
			var gpCellRaw: Variant = gpCells.get(gpCol + str(gpRowNum), null)
			if gpCellRaw == null:
				gpValues[gpKey] = {"kind": "empty", "value": null}
				continue
			gpValues[gpKey] = gpCellRaw as Dictionary
		var gpKeyVal: Variant = (gpValues.get(gpKeyField, {}) as Dictionary).get("value", null)
		var gpKeyText: String = str(gpKeyVal).strip_edges() if gpKeyVal != null else ""
		if gpKeyText == "":
			continue
		if gpKeyText.begins_with("编制") or gpKeyText.begins_with("审核") \
				or gpKeyText.begins_with("批准"):
			continue
		var gpSheet: GPSheet = _gpResolveSheet(gpValues, gpSheets, gpIssues, gpRowNum)
		if gpSheet == null:
			continue
		var gpTargets: Array[Dictionary] = _gpTargets(gpSheet, gpList, gpKeyText, gpIssues)
		if gpTargets.is_empty():
			continue
		for gpTarget in gpTargets:
			for gpColRaw in gpColumns.keys():
				var gpInfo: Dictionary = gpColumns[gpColRaw] as Dictionary
				var gpField: String = str(gpInfo.get("key", ""))
				if gpField == gpKeyField or not gpWritable(gpField):
					continue
				var gpCellValue: Dictionary = gpValues.get(gpField, {}) as Dictionary
				var gpChange: Dictionary = _gpChangeOf(gpSheet, gpTarget, gpList, gpField,
					gpCellValue, gpLocale, gpDefs, gpTypeLabels, gpRowNum)
				if not gpChange.is_empty():
					gpChanges.append(gpChange)


# Is a field writable? Static catalogue first; dynamic props are writable by definition.
# 字段是否可写？先查静态目录；动态 prop 默认可写。
static func gpWritable(gpField: String) -> bool:
	if gpField.begins_with("prop:"):
		return true
	return GPDeliverableFields.gpIsWritable(gpField)


static func _gpResolveSheet(gpValues: Dictionary, gpSheets: Array, gpIssues: Array,
		gpRowNum: int) -> GPSheet:
	if gpSheets.is_empty():
		return null
	var gpSheetCell: Dictionary = gpValues.get("sheet", {}) as Dictionary
	var gpSheetName: String = str(gpSheetCell.get("value", "")).strip_edges() \
		if gpSheetCell.get("value", null) != null else ""
	if gpSheetName == "":
		if gpSheets.size() == 1:
			return gpSheets[0] as GPSheet
		gpIssues.append(_gpIssue("xlsx.sheet_missing", {"row": gpRowNum}))
		return null
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet != null and gpSheet.gpName == gpSheetName:
			return gpSheet
	gpIssues.append(_gpIssue("xlsx.sheet_not_found", {"row": gpRowNum,
		"sheet": gpSheetName}))
	return null


static func _gpTargets(gpSheet: GPSheet, gpList: String, gpKey: String,
		gpIssues: Array) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	var gpGraph: GPPIDGraph = gpSheet.gpGraph
	if gpGraph == null:
		return gpOut
	if gpList == GPDeliverableFields.GP_LIST_LINE:
		for gpEdge in gpGraph.gpEdges:
			if gpEdge == null or gpEdge.gpKind != GPPIDEdge.GP_PROCESS:
				continue
			if gpEdge.gpTag == gpKey:
				gpOut.append({"kind": "edge", "id": gpEdge.gpInstanceId,
					"label": gpEdge.gpTag})
		if gpOut.is_empty():
			gpIssues.append(_gpIssue("xlsx.line_not_found", {"sheet": gpSheet.gpName,
				"line": gpKey}))
		return gpOut
	var gpHits: Array[GPPIDNode] = []
	for gpNode in gpGraph.gpNodes:
		if gpNode != null and gpNode.gpTag == gpKey:
			gpHits.append(gpNode)
	if gpHits.is_empty():
		gpIssues.append(_gpIssue("xlsx.tag_not_found", {"sheet": gpSheet.gpName,
			"tag": gpKey}))
	elif gpHits.size() > 1:
		gpIssues.append(_gpIssue("xlsx.tag_ambiguous", {"sheet": gpSheet.gpName,
			"tag": gpKey}))
	else:
		gpOut.append({"kind": "node", "id": gpHits[0].gpInstanceId, "label": gpKey})
	return gpOut


static func _gpChangeOf(gpSheet: GPSheet, gpTarget: Dictionary, gpList: String,
		gpField: String, gpCell: Dictionary, gpLocale: String,
		gpDefs: Array[GPSymbolDef], gpTypeLabels: Dictionary, gpRowNum: int) -> Dictionary:
	var gpKind: String = str(gpTarget.get("kind", ""))
	var gpId: String = str(gpTarget.get("id", ""))
	var gpRaw: Variant = gpCell.get("value", null)
	var gpCellKind: String = str(gpCell.get("kind", "empty"))
	var gpClear: bool = gpRaw == null or (gpRaw is String and str(gpRaw).strip_edges() == "")
	var gpNew: Variant = null
	var gpChangeKind: String = ""
	var gpKey: String = gpField
	var gpOld: Variant = null
	if gpKind == "edge":
		if not GP_EDGE_ATTRS.has(gpField):
			return {}
		gpChangeKind = "edge_attr"
		gpOld = _gpEdgeOld(gpSheet, gpId, gpField)
		if not gpClear:
			gpNew = gpRaw
	elif gpField == "name":
		gpChangeKind = "node_name"
		gpKey = "name"
		gpOld = _gpNodeNameOld(gpSheet, gpId, gpLocale)
		if not gpClear:
			gpNew = str(gpRaw)
			# An exported node with no explicit name shows its localized type label. Reading
			# that back must NOT create a name override; otherwise every round-trip would
			# freeze the library default into the instance.
			# 未显式命名的节点导出时显示本地化类型名。把它读回时**不应**创建名称覆盖，
			# 否则每次导入都会把库默认名冻进实例。
			var gpNode: GPPIDNode = gpSheet.gpGraph.gpGetNode(gpId) if gpSheet.gpGraph != null else null
			if gpNode != null and gpOld == null:
				var gpDisplay: String = _gpDisplayName(gpNode, gpDefs, gpTypeLabels)
				if gpDisplay != "" and str(gpNew) == gpDisplay:
					return {}
	elif gpField.begins_with("prop:"):
		gpChangeKind = "node_prop"
		gpKey = gpField.substr("prop:".length())
		gpOld = _gpNodePropOld(gpSheet, gpId, gpKey)
		if not gpClear:
			gpNew = _gpCoerceDynamic(gpRaw, gpCellKind)
	else:
		gpChangeKind = "node_prop"
		gpOld = _gpNodePropOld(gpSheet, gpId, gpField)
		if not gpClear:
			gpNew = GPDeliverableFields.gpCoerce(gpField, gpRaw)
	if not gpClear and gpOld == gpNew:
		return {}
	if gpClear and gpOld == null:
		return {}
	return {
		"sheet_id": gpSheet.gpId,
		"sheet_name": gpSheet.gpName,
		"list": gpList,
		"kind": gpChangeKind,
		"target_id": gpId,
		"target_label": str(gpTarget.get("label", "")),
		"key": gpKey,
		"locale": gpLocale,
		"field": gpField,
		"old": gpOld,
		"new": gpNew,
		"clear": gpClear,
		"row": gpRowNum,
	}


static func _gpDisplayName(gpNode: GPPIDNode, gpDefs: Array[GPSymbolDef],
		gpTypeLabels: Dictionary) -> String:
	if gpTypeLabels.has(gpNode.gpSymbolId):
		return str(gpTypeLabels[gpNode.gpSymbolId])
	for gpDef in gpDefs:
		if gpDef != null and gpDef.gpId == gpNode.gpSymbolId:
			return gpDef.gpDisplayName
	return ""


static func _gpCoerceDynamic(gpRaw: Variant, gpCellKind: String) -> Variant:
	if gpCellKind == "number":
		return float(gpRaw)
	if gpCellKind == "bool":
		return bool(gpRaw)
	return str(gpRaw)


static func _gpNodePropOld(gpSheet: GPSheet, gpId: String, gpKey: String) -> Variant:
	var gpNode: GPPIDNode = gpSheet.gpGraph.gpGetNode(gpId) if gpSheet.gpGraph != null else null
	if gpNode == null:
		return null
	return gpNode.gpProps.get(gpKey, null)


static func _gpNodeNameOld(gpSheet: GPSheet, gpId: String, gpLocale: String) -> Variant:
	var gpNode: GPPIDNode = gpSheet.gpGraph.gpGetNode(gpId) if gpSheet.gpGraph != null else null
	if gpNode == null:
		return null
	return gpNode.gpNames.get(gpLocale, null)


static func _gpEdgeOld(gpSheet: GPSheet, gpId: String, gpKey: String) -> Variant:
	var gpEdge: GPPIDEdge = gpSheet.gpGraph.gpGetEdge(gpId) if gpSheet.gpGraph != null else null
	if gpEdge == null:
		return null
	return gpEdge.gpAttrs.get(gpKey, null)


static func _gpDedupe(gpChanges: Array) -> Array:
	var gpOut: Array = []
	var gpIndex: Dictionary = {}
	for gpChangeRaw in gpChanges:
		var gpChange: Dictionary = gpChangeRaw as Dictionary
		var gpKey: String = "%s|%s|%s|%s|%s" % [str(gpChange.get("sheet_id", "")),
			str(gpChange.get("kind", "")), str(gpChange.get("target_id", "")),
			str(gpChange.get("key", "")), str(gpChange.get("locale", ""))]
		if gpIndex.has(gpKey):
			var gpOld: Dictionary = gpOut[int(gpIndex[gpKey])] as Dictionary
			gpChange["old"] = gpOld.get("old", null)
			gpOut[int(gpIndex[gpKey])] = gpChange
			continue
		gpIndex[gpKey] = gpOut.size()
		gpOut.append(gpChange)
	return gpOut


static func _gpSummary(gpChanges: Array) -> Dictionary:
	var gpChanged: int = 0
	var gpCleared: int = 0
	for gpChangeRaw in gpChanges:
		var gpChange: Dictionary = gpChangeRaw as Dictionary
		gpChanged += 1
		if bool(gpChange.get("clear", false)):
			gpCleared += 1
	return {"changed": gpChanged, "cleared": gpCleared,
		"kept": maxi(0, gpChanges.size() - gpChanged)}


static func _gpIssue(gpCode: String, gpParams: Dictionary) -> Dictionary:
	return {"code": gpCode, "severity": "warning", "params": gpParams}
