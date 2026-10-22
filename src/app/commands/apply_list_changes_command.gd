class_name GPApplyListChangesCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# One undo step for ALL changes belonging to ONE sheet. Multiple sheets get multiple commands
# (the import dialog groups by sheet), so Ctrl+Z always undoes exactly the sheet the user
# applied last — never a half-applied project.
# 一张图纸的全部变更压成一条撤销步。多张图纸按图纸分组（导入对话框负责），故 Ctrl+Z
# 总是精确撤销用户最后应用的那张图纸，绝不会留下「半个工程」。
#
# WHO WRITES WHAT / 写什么：
#   node_name  -> gpNames[locale]
#   node_prop  -> gpProps[key]
#   edge_attr  -> gpAttrs[key]
# Blank/clear removes the key (library default wins again). Tags/line numbers/geometry are
# not representable here by construction.
# 空白/清空移除键（库默认值重新生效）。位号/管线号/几何在此结构上不可表达。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量显式声明类型。

var _gpChanges: Array = []
var _gpApplied: Array = []
var _gpBefore: Array[Dictionary] = []
var _gpSeen: Dictionary = {}
# Changes skipped because the live value no longer matches the preview's `old` (stale).
# 因当前值已不等于预览 old 而跳过的变更（过期）。
var gpStale: Array[Dictionary] = []


func _init(gpChangesIn: Array) -> void:
	_gpChanges = gpChangesIn.duplicate(true)
	gpLabel = "应用清单变更"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	_gpBefore = []
	_gpApplied = []
	_gpSeen = {}
	gpStale = []
	for gpChangeRaw in _gpChanges:
		var gpChange: Dictionary = gpChangeRaw as Dictionary
		var gpKey: String = _gpKeyOf(gpChange)
		if _gpSeen.has(gpKey):
			continue
		var gpHad: bool = _gpHas(gpCtx.gpGraph, gpChange)
		var gpOld: Variant = _gpRead(gpCtx.gpGraph, gpChange)
		# D5 stale guard: if the live value differs from the preview's old, someone edited
		# between preview and apply; skip and report instead of overwriting.
		# D5 过期护栏：当前值不等于预览 old 时，说明预览后有人改过；跳过并报告，不覆盖。
		if gpChange.has("old") and gpOld != gpChange.get("old", null):
			gpStale.append(gpChange)
			continue
		var gpNew: Variant = gpChange.get("new", null)
		var gpClear: bool = bool(gpChange.get("clear", false))
		if gpClear and not gpHad:
			continue
		if not gpClear and gpHad and gpOld == gpNew:
			continue
		_gpSeen[gpKey] = true
		_gpBefore.append({"change": gpChange, "had": gpHad, "old": gpOld})
		_gpApplied.append(gpChange)
	if _gpApplied.is_empty():
		return false
	for gpChangeRaw in _gpApplied:
		_gpApply(gpCtx.gpGraph, gpChangeRaw as Dictionary)
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpRow in _gpBefore:
		var gpChange: Dictionary = gpRow["change"] as Dictionary
		if bool(gpRow["had"]):
			_gpWrite(gpCtx.gpGraph, gpChange, gpRow["old"])
		else:
			_gpErase(gpCtx.gpGraph, gpChange)
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpChangeRaw in _gpApplied:
		_gpApply(gpCtx.gpGraph, gpChangeRaw as Dictionary)
	gpCtx.gpGraph.gpGraphChanged.emit()


func _gpKeyOf(gpChange: Dictionary) -> String:
	return "%s|%s|%s|%s" % [str(gpChange.get("kind", "")),
		str(gpChange.get("target_id", "")), str(gpChange.get("key", "")),
		str(gpChange.get("locale", ""))]


func _gpHas(gpGraph: GPPIDGraph, gpChange: Dictionary) -> bool:
	var gpKind: String = str(gpChange.get("kind", ""))
	if gpKind == "edge_attr":
		var gpEdge: GPPIDEdge = gpGraph.gpGetEdge(str(gpChange.get("target_id", "")))
		return gpEdge != null and gpEdge.gpAttrs.has(str(gpChange.get("key", "")))
	var gpNode: GPPIDNode = gpGraph.gpGetNode(str(gpChange.get("target_id", "")))
	if gpNode == null:
		return false
	if gpKind == "node_name":
		return gpNode.gpNames.has(str(gpChange.get("locale", "")))
	return gpNode.gpProps.has(str(gpChange.get("key", "")))


func _gpRead(gpGraph: GPPIDGraph, gpChange: Dictionary) -> Variant:
	var gpKind: String = str(gpChange.get("kind", ""))
	if gpKind == "edge_attr":
		var gpEdge: GPPIDEdge = gpGraph.gpGetEdge(str(gpChange.get("target_id", "")))
		return gpEdge.gpAttrs.get(str(gpChange.get("key", "")), null) if gpEdge != null else null
	var gpNode: GPPIDNode = gpGraph.gpGetNode(str(gpChange.get("target_id", "")))
	if gpNode == null:
		return null
	if gpKind == "node_name":
		return gpNode.gpNames.get(str(gpChange.get("locale", "")), null)
	return gpNode.gpProps.get(str(gpChange.get("key", "")), null)


func _gpApply(gpGraph: GPPIDGraph, gpChange: Dictionary) -> void:
	if bool(gpChange.get("clear", false)):
		_gpErase(gpGraph, gpChange)
	else:
		_gpWrite(gpGraph, gpChange, gpChange.get("new", null))


func _gpWrite(gpGraph: GPPIDGraph, gpChange: Dictionary, gpValue: Variant) -> void:
	var gpKind: String = str(gpChange.get("kind", ""))
	if gpKind == "edge_attr":
		var gpEdge: GPPIDEdge = gpGraph.gpGetEdge(str(gpChange.get("target_id", "")))
		if gpEdge != null:
			gpEdge.gpAttrs[str(gpChange.get("key", ""))] = gpValue
		return
	var gpNode: GPPIDNode = gpGraph.gpGetNode(str(gpChange.get("target_id", "")))
	if gpNode == null:
		return
	if gpKind == "node_name":
		gpNode.gpNames[str(gpChange.get("locale", ""))] = str(gpValue)
	else:
		gpNode.gpProps[str(gpChange.get("key", ""))] = gpValue


func _gpErase(gpGraph: GPPIDGraph, gpChange: Dictionary) -> void:
	var gpKind: String = str(gpChange.get("kind", ""))
	if gpKind == "edge_attr":
		var gpEdge: GPPIDEdge = gpGraph.gpGetEdge(str(gpChange.get("target_id", "")))
		if gpEdge != null:
			gpEdge.gpAttrs.erase(str(gpChange.get("key", "")))
		return
	var gpNode: GPPIDNode = gpGraph.gpGetNode(str(gpChange.get("target_id", "")))
	if gpNode == null:
		return
	if gpKind == "node_name":
		gpNode.gpNames.erase(str(gpChange.get("locale", "")))
	else:
		gpNode.gpProps.erase(str(gpChange.get("key", "")))
