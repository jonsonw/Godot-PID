class_name GPSetDropRestoreCommand
extends GPCommand
# Record (or un-record) a drop-on-edge restore entry as its own undo step, so undoing the drop
# also clears the symbol's restore history and re-doing re-creates it. Keeping the registry in
# lock-step with the drop's mutating commands is what makes "delete restores the original line"
# survive an undo of the drop itself.
# 把「落点恢复记录」作为独立撤销步写入（或撤除），使撤销落点也会清除该图元的恢复历史、
# 重做则重建之。令注册表与落点的改动命令同步，从而保证「删除时还原原始连线」在落点本身被撤销后
# 依然自洽。

# Symbol instance id the record belongs to. / 记录所属图元的实例 id。
var _gpSymNid: String = ""

# The record dict (a clone of the caller's — gpRecordDrop() stamps it with a monotonic "_rid").
# 记录字典（调用方字典的副本 —— gpRecordDrop() 会为其盖上单调 "_rid"）。
var _gpRecord: Dictionary = {}


func _init(gpSymNid: String, gpRecord: Dictionary) -> void:
	_gpSymNid = gpSymNid
	_gpRecord = gpRecord.duplicate()
	gpLabel = "记录落点"


# Add the record. gpRecordDrop() stamps _gpRecord["_rid"], so gpUndo() can find the exact entry.
# 追加记录。gpRecordDrop() 会写入 _gpRecord["_rid"]，故 gpUndo() 能精确定位该条目。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	gpCtx.gpGraph.gpRecordDrop(_gpSymNid, _gpRecord)
	return true


# Remove the exact record by its "_rid". / 按 "_rid" 精确移除该记录。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpRid: int = int(_gpRecord.get("_rid", -1))
	if gpRid >= 0:
		gpCtx.gpGraph.gpRemoveDrop(_gpSymNid, gpRid)


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
