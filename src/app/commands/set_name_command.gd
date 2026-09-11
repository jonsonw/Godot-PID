class_name GPSetNameCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Change one instance's name in ONE language (M11).
# 修改某个实例在**某一语种**下的名称（M11）。
#
# Why one command per language / 为何按语种各一条命令：
#   gpNames is a locale-keyed dictionary, not a single string. Editing the Chinese name and
#   the English name are two separate user intents and must be two separate undo steps —
#   otherwise Ctrl+Z after typing the English name would also throw away the Chinese one.
#   gpNames 是按语种索引的字典，不是单个字符串。改中文名与改英文名是两种用户意图，
#   必须是两个独立的撤销步 —— 否则录完英文名后按 Ctrl+Z 会连中文名一起丢掉。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var _gpId: String = ""
var _gpLocale: String = ""
var _gpNewName: String = ""
var _gpOldName: String = ""
# Whether the instance had a name in this locale at all: undo must ERASE the key rather than
# leave an empty string behind, or "never named" and "named then cleared" become the same state.
# 该实例在此语种下原本是否有名称：撤销必须**删除**该键而非留下空串，
# 否则「从未命名」与「命名后又清空」会变成同一种状态。
var _gpHadOld: bool = false


func _init(gpInId: String, gpInLocale: String, gpInName: String) -> void:
	_gpId = gpInId
	_gpLocale = gpInLocale
	_gpNewName = gpInName
	gpLabel = "修改名称"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null or _gpLocale == "":
		return false
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return false
	_gpHadOld = gpN.gpNames.has(_gpLocale)
	_gpOldName = str(gpN.gpNames.get(_gpLocale, ""))
	if _gpHadOld and _gpOldName == _gpNewName:
		return false
	if not _gpHadOld and _gpNewName == "":
		return false
	gpN.gpNames[_gpLocale] = _gpNewName
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	if _gpHadOld:
		gpN.gpNames[_gpLocale] = _gpOldName
	else:
		gpN.gpNames.erase(_gpLocale)
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpNames[_gpLocale] = _gpNewName
	gpCtx.gpGraph.gpGraphChanged.emit()
