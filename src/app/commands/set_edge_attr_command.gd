class_name GPSetEdgeAttrCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Set (or clear) one well-known attribute on an edge: dn / medium / spec / insulation /
# show_arrow / show_tag / tag_offset (P3).
# 设置（或清除）边上的一个约定属性：dn / medium / spec / insulation / show_arrow / show_tag /
# tag_offset（P3）。
#
# Why one command for all of them / 为何用一个命令涵盖全部：
#   They differ only in key and value type, and the inspector must be able to revert each one
#   independently. A command per attribute would be seven near-identical files. The trade-off is
#   that undo restores a single key rather than a whole attribute block — which is exactly the
#   granularity a user editing one field expects.
#   它们只在键与值类型上不同，而属性面板必须能各自独立回退。每个属性一个命令会产生七个近乎
#   相同的文件。代价是撤销只恢复单个键而非整个属性块 —— 而这正是用户编辑单个字段时预期的粒度。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpEdgeId: String = ""
var gpKey: String = ""
var gpValue: Variant = null

# Previous value, plus whether the key existed at all (so undo can re-erase it).
# 原值，外加该键是否原本存在（使撤销能重新删除它）。
var _gpOldValue: Variant = null
var _gpHadKey: bool = false


func _init(gpInEdgeId: String, gpInKey: String, gpInValue: Variant) -> void:
	gpEdgeId = gpInEdgeId
	gpKey = gpInKey
	gpValue = gpInValue
	gpLabel = "修改连线属性"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null or gpKey == "":
		return false
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	_gpHadKey = gpE.gpAttrs.has(gpKey)
	if _gpHadKey:
		_gpOldValue = gpE.gpAttrs[gpKey]
		if _gpSame(_gpOldValue, gpValue):
			return false
	gpE.gpAttrs[gpKey] = gpValue
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	if _gpHadKey:
		gpE.gpAttrs[gpKey] = _gpOldValue
	else:
		gpE.gpAttrs.erase(gpKey)
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)


# Variant equality that survives arrays: "==" already compares Array/Dictionary by value in
# GDScript, so a plain test is correct here and avoids a type-sensitive switch.
# 能正确处理数组的 Variant 相等判定：GDScript 中 "==" 对 Array/Dictionary 本就按值比较，
# 故此处直接用即可，无需按类型分派的 switch。
func _gpSame(gpA: Variant, gpB: Variant) -> bool:
	return gpA == gpB
