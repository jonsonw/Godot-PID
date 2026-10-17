class_name GPSetPropertyCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# The override rule this command enforces / 本命令强制的覆盖规则：
# writing a value puts the key into gpProps, which is exactly what GPPropertyResolver reads
# as "this instance overrides the library default". Clearing a field therefore means REMOVING
# the key (letting the library default win again) — never storing an empty string as a value.
# 写入一个值即把该键放入 gpProps，而 GPPropertyResolver 正是据此判定
# 「本实例覆盖了库默认值」。故「清空字段」= **移除**该键（让库默认值重新生效），
# 绝不是存一个空字符串当值。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var _gpId: String = ""
var _gpKey: String = ""
var _gpNewVal: Variant = null
var _gpOldVal: Variant = null
var _gpHadOld: bool = false

# Rev.3 stage 1.5 (R2): an explicitly CREATED custom entry may legitimately hold an empty
# string — the "empty means reset" rule exists so a LIBRARY default can win again, but a
# custom key has no library default to fall back to. Default false keeps every existing
# caller byte-identical.
# Rev.3 阶段 1.5（R2）：被**显式创建**的自定义条目可以合法持有空字符串 ——
# 「空即复位」规则的存在理由是让**库默认值**重新生效，而自定义键没有可回落的库默认值。
# 默认 false 使所有既有调用方逐字节不变。
var _gpAllowEmpty: bool = false


func _init(gpInId: String, gpInKey: String, gpInVal: Variant,
		gpAllowEmptyIn: bool = false) -> void:
	_gpId = gpInId
	_gpKey = gpInKey
	_gpNewVal = gpInVal
	_gpAllowEmpty = gpAllowEmptyIn
	gpLabel = "修改属性"


# Apply the value. An EMPTY string means "reset to the library default", which is modelled by
# removing the key — unless the caller allowed an explicitly created empty custom entry.
# Returns false when nothing actually changes, so no phantom undo step appears.
# 应用取值。空字符串意为「复位到库默认值」，以移除该键表达 —— 除非调用方允许
# 「显式创建的空自定义条目」。无实际变化时返回 false，避免出现幽灵撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null or _gpKey == "":
		return false
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return false
	_gpHadOld = gpN.gpProps.has(_gpKey)
	_gpOldVal = gpN.gpProps.get(_gpKey, null)
	if _gpNewVal is String and str(_gpNewVal) == "" and not _gpAllowEmpty:
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
	if _gpNewVal is String and str(_gpNewVal) == "" and not _gpAllowEmpty:
		gpN.gpProps.erase(_gpKey)
	else:
		gpN.gpProps[_gpKey] = _gpNewVal
	gpCtx.gpGraph.gpGraphChanged.emit()
