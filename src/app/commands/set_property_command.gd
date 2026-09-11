class_name GPSetPropertyCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Set ONE property value on ONE instance (M11).
# 在单个实例上设置**一个**属性值（M11）。
#
# The override rule this command enforces / 本命令强制的覆盖规则：
#   writing a value puts the key into gpProps, which is exactly what GPPropertyResolver reads
#   as "this instance overrides the library default". Clearing a field therefore means REMOVING
#   the key (letting the library default win again) — never storing an empty string as a value.
#   写入一个值即把该键放入 gpProps，而 GPPropertyResolver 正是据此判定
#   「本实例覆盖了库默认值」。故「清空字段」= **移除**该键（让库默认值重新生效），
#   绝不是存一个空字符串当值。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var _gpId: String = ""
var _gpKey: String = ""
var _gpNewVal: Variant = null
var _gpOldVal: Variant = null
var _gpHadOld: bool = false


func _init(gpInId: String, gpInKey: String, gpInVal: Variant) -> void:
	_gpId = gpInId
	_gpKey = gpInKey
	_gpNewVal = gpInVal
	gpLabel = "修改属性"


# Apply the value. An EMPTY string means "reset to the library default", which is modelled by
# removing the key. Returns false when nothing actually changes, so no phantom undo step appears.
# 应用取值。空字符串意为「复位到库默认值」，以移除该键表达。无实际变化时返回 false，
# 避免出现幽灵撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null or _gpKey == "":
		return false
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return false
	_gpHadOld = gpN.gpProps.has(_gpKey)
	_gpOldVal = gpN.gpProps.get(_gpKey, null)
	if _gpNewVal is String and str(_gpNewVal) == "":
		if not _gpHadOld:
			return false
		gpN.gpProps.erase(_gpKey)
	elif _gpHadOld and _gpOldVal == _gpNewVal:
		return false
	else:
		gpN.gpProps[_gpKey] = _gpNewVal
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	if _gpHadOld:
		gpN.gpProps[_gpKey] = _gpOldVal
	else:
		gpN.gpProps.erase(_gpKey)
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	if _gpNewVal is String and str(_gpNewVal) == "":
		gpN.gpProps.erase(_gpKey)
	else:
		gpN.gpProps[_gpKey] = _gpNewVal
	gpCtx.gpGraph.gpGraphChanged.emit()
