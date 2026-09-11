class_name GPBatchSetPropertyCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Apply ONE edit to a whole selection as a SINGLE undo step (M11).
# 把一次编辑作用到整个选择集，且只产生**一个**撤销步（M11）。
#
# Why one command and not N / 为何是一条命令而非 N 条：
#   Ctrl+Z after a batch edit must undo the whole selection at once. Pushing one command per
#   node would make the user press Ctrl+Z forty times — and, worse, leave the sheet in forty
#   intermediate states that never existed on screen.
#   批量编辑后按一次 Ctrl+Z 必须**整体**撤销。每个节点压一条命令会让用户按四十次 Ctrl+Z
#   —— 更糟的是会留下四十个屏幕上从未存在过的中间状态。
#
# Deliberate refusal / 刻意拒绝：
#   "tag" is NOT batchable. Tags are unique project-wide, so writing one tag onto forty
#   instances would create forty duplicates; the panel disables the tag field in batch mode and
#   this command refuses it as a second line of defence.
#   "tag" **不可**批量。位号工程级唯一，把一个位号写到四十个实例上就造出四十个重复；
#   面板在批量模式下禁用位号字段，本命令再拒一次作为第二道防线。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Reserved edit keys. / 保留编辑键。
const GP_KEY_TAG: String = "tag"
const GP_KEY_ANCHOR: String = "label_anchor"
const GP_NAME_PREFIX: String = "name:"

var _gpIds: Array[String] = []
var _gpKey: String = ""
var _gpNewVal: Variant = null
# {"id": String, "had": bool, "val": Variant} per affected instance.
# 每个受影响实例一行：{"id", "had", "val"}
var _gpOld: Array[Dictionary] = []


func _init(gpInIds: Array[String], gpInKey: String, gpInVal: Variant) -> void:
	_gpIds = gpInIds.duplicate()
	_gpKey = gpInKey
	_gpNewVal = gpInVal
	gpLabel = "批量修改属性"


# Apply to every target. Returns false when the key is not batchable, no node resolved, or
# nothing actually changed — so an accidental empty batch leaves no undo step behind.
# 作用到每个目标。键不可批量、无节点可解析、或无实际变化时返回 false，
# 使一次误触发的空批量不留下撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null or _gpKey == "":
		return false
	if _gpKey == GP_KEY_TAG:
		return false
	_gpOld = []
	if _gpNewVal is String and str(_gpNewVal) == "" and _gpKey != GP_KEY_ANCHOR \
			and not _gpKey.begins_with(GP_NAME_PREFIX):
		# Empty means "reset to the library default" — only instances that actually carry a
		# value are affected.
		# 空意为「复位到库默认值」—— 只有确实带值的实例受影响。
		for gpId in _gpIds:
			var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
			if gpN == null or not gpN.gpProps.has(_gpKey):
				continue
			_gpOld.append({"id": gpId, "had": true, "val": gpN.gpProps[_gpKey]})
			gpN.gpProps.erase(_gpKey)
	else:
		for gpId in _gpIds:
			var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
			if gpN == null:
				continue
			if not _gpCapture(gpN):
				continue
			_gpApply(gpN)
	if _gpOld.is_empty():
		return false
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpRow in _gpOld:
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(str(gpRow["id"]))
		if gpN == null:
			continue
		_gpRestore(gpN, gpRow)
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpRow in _gpOld:
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(str(gpRow["id"]))
		if gpN == null:
			continue
		_gpApply(gpN)
	gpCtx.gpGraph.gpGraphChanged.emit()


# Record an instance's prior state; returns false when the edit would change nothing.
# 记录实例改动前的状态；编辑不产生实际变化时返回 false。
func _gpCapture(gpN: GPPIDNode) -> bool:
	if _gpKey == GP_KEY_ANCHOR:
		if gpN.gpLabelAnchor == int(_gpNewVal):
			return false
		_gpOld.append({"id": gpN.gpInstanceId, "had": true, "val": gpN.gpLabelAnchor})
		return true
	if _gpKey.begins_with(GP_NAME_PREFIX):
		var gpLocale: String = _gpKey.substr(GP_NAME_PREFIX.length())
		var gpHad: bool = gpN.gpNames.has(gpLocale)
		if gpHad and str(gpN.gpNames[gpLocale]) == str(_gpNewVal):
			return false
		_gpOld.append({"id": gpN.gpInstanceId, "had": gpHad,
			"val": gpN.gpNames.get(gpLocale, "")})
		return true
	var gpHad: bool = gpN.gpProps.has(_gpKey)
	if gpHad and gpN.gpProps[_gpKey] == _gpNewVal:
		return false
	_gpOld.append({"id": gpN.gpInstanceId, "had": gpHad, "val": gpN.gpProps.get(_gpKey, null)})
	return true


func _gpApply(gpN: GPPIDNode) -> void:
	if _gpKey == GP_KEY_ANCHOR:
		gpN.gpLabelAnchor = int(_gpNewVal)
	elif _gpKey.begins_with(GP_NAME_PREFIX):
		gpN.gpNames[_gpKey.substr(GP_NAME_PREFIX.length())] = str(_gpNewVal)
	else:
		gpN.gpProps[_gpKey] = _gpNewVal


func _gpRestore(gpN: GPPIDNode, gpRow: Dictionary) -> void:
	var gpHad: bool = bool(gpRow["had"])
	if _gpKey == GP_KEY_ANCHOR:
		gpN.gpLabelAnchor = int(gpRow["val"]) if gpHad else GPPropertyResolver.GP_ANCHOR_UNSET
		return
	if _gpKey.begins_with(GP_NAME_PREFIX):
		var gpLocale: String = _gpKey.substr(GP_NAME_PREFIX.length())
		if gpHad:
			gpN.gpNames[gpLocale] = gpRow["val"]
		else:
			gpN.gpNames.erase(gpLocale)
		return
	if gpHad:
		gpN.gpProps[_gpKey] = gpRow["val"]
	else:
		gpN.gpProps.erase(_gpKey)
