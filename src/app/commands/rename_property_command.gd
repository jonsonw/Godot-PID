class_name GPRenamePropertyCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Rename one instance's CUSTOM property key as ONE undo step (Rev.3 stage 1.5, R2 / D7).
# 一步撤销地重命名某个实例的**自定义**属性键（Rev.3 阶段 1.5，R2 / D7）。
#
# Why a dedicated command / 为何要专用命令：
# a rename done as "write new key + erase old key" would be TWO undo steps, and Ctrl+Z after a
# rename would leave a duplicated value behind. Moving the value in one command keeps the
# instance's data exactly as it was, only under a new name. This is INSTANCE-level only —
# renaming a LIBRARY field definition (which also migrates every instance via gpRenameFrom)
# belongs to the symbol-editor line.
# 用「写新键 + 删旧键」拼出的改名会是**两个**撤销步，且改名后按 Ctrl+Z 会留下重复的值。
# 单条命令内搬移取值，使实例数据除名字外逐位不变。本命令仅限**实例级** ——
# 改**库**字段定义（含经 gpRenameFrom 迁移全部实例）属图元编辑器线。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var _gpId: String = ""
var _gpOldKey: String = ""
var _gpNewKey: String = ""
var _gpVal: Variant = null

# Machine-readable refusal for the service layer ("gpLastRefusal" convention).
# 面向服务层的机器可读拒绝原因（gpLastRefusal 约定）。
var gpRefusal: String = ""


func _init(gpInId: String, gpInOldKey: String, gpInNewKey: String) -> void:
	_gpId = gpInId
	_gpOldKey = gpInOldKey
	_gpNewKey = gpInNewKey
	gpLabel = "重命名属性"


# Move gpProps[old] -> gpProps[new]. Refused when the old key is absent (nothing to rename) or
# the new key already holds a value (a silent overwrite would destroy data).
# 把 gpProps[旧] 搬到 gpProps[新]。旧键不存在（无可改名）或新键已有取值
#（静默覆盖会毁数据）时拒绝。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	gpRefusal = ""
	if gpCtx == null or gpCtx.gpGraph == null or _gpOldKey == "" or _gpNewKey == "":
		return false
	if _gpOldKey == _gpNewKey:
		return false
	if not GPPermissions.gpCanEditProps():
		gpRefusal = "perm.err_props"
		return false
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return false
	if not gpN.gpProps.has(_gpOldKey):
		gpRefusal = "adhoc.err_missing"
		return false
	if gpN.gpProps.has(_gpNewKey):
		gpRefusal = "adhoc.err_exists"
		return false
	_gpVal = gpN.gpProps[_gpOldKey]
	gpN.gpProps.erase(_gpOldKey)
	gpN.gpProps[_gpNewKey] = _gpVal
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpProps.erase(_gpNewKey)
	gpN.gpProps[_gpOldKey] = _gpVal
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpProps.erase(_gpOldKey)
	gpN.gpProps[_gpNewKey] = _gpVal
	gpCtx.gpGraph.gpGraphChanged.emit()
