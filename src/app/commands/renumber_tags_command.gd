class_name GPRenumberTagsCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Renumber every piece of equipment on the sheet from the project's numbering rules (M9b).
# 按工程的编号规则重排图纸上全部设备的位号（M9b）。
#
# WHY THIS IS ONE UNDO STEP / 为何是一个撤销步:
#   Renumbering touches every instance at once. Twenty separate undo steps would mean the
#   sheet passes through twenty half-renumbered states, and any of them could be saved by
#   accident — a half-renumbered P&ID is worse than an un-renumbered one because the damage
#   is invisible until someone compares it with the DCS point list.
#   重编号一次性改动所有实例。若拆成二十个撤销步，图纸会经历二十个「半重编号」中间态，
#   任何一个都可能被误存——半重编号的 P&ID 比未重编号更糟，因为不对照 DCS 点表看不出损坏。
#
# What it does NOT touch / 它不碰什么:
#   Edges. Pipe numbers are owned by GPTagGen and get their own command (GPRenumberCommand);
#   mixing the two namespaces in one step would make the undo label a lie.
#   连线。管线号归 GPTagGen，有自己的命令（GPRenumberCommand）；把两个命名空间混进
#   一个撤销步会让撤销标签变成假话。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The plan: [{uid, old, new}]. Captured on execute, replayed verbatim on redo — a redo must
# reproduce the SAME numbers, not re-derive them (the user may have edited the rules since).
# 方案：[{uid, old, new}]。执行时捕获，重做时原样重放——重做必须复现**同一批**号，
# 而非重新推导（用户此后可能又改过规则）。
var _gpPlan: Array[Dictionary] = []

# Sequence marks as they were before renumbering, so undo restores them exactly.
# 重排前的序号水位线，使撤销能精确还原。
var _gpOldMarks: Dictionary = {}


func _init() -> void:
	gpLabel = "重排位号"


# The plan, available after gpExecute so the caller can offer the old->new CSV.
# gpExecute 之后可用的方案，供调用方提供「旧→新」对照表 CSV。
func gpMapping() -> Array[Dictionary]:
	return _gpPlan.duplicate()


# Build and apply the renumbering. Returns false when the project has nothing to number, so
# invoking it on an empty sheet produces no undo step.
# 构建并应用重编号。工程无可编号对象时返回 false，故在空图纸上调用不产生撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null or gpCtx.gpTags == null:
		return false
	var gpItems: Array[Dictionary] = GPTagRuleService.gpRenumberItems(gpCtx.gpGraph)
	if gpItems.is_empty():
		return false
	gpCtx.gpTags.gpGraph = gpCtx.gpGraph
	_gpOldMarks = gpCtx.gpTags.gpRules.gpSeqMarks.duplicate()
	_gpPlan = gpCtx.gpTags.gpPlanRenumberAll(gpItems)
	GPTagRuleService.gpApplyPlan(gpCtx.gpGraph, _gpPlan)
	gpCtx.gpGraph.gpGraphChanged.emit()
	return GPTagRuleService.gpChangedCount(_gpPlan) > 0


# Restore the old tags, the old marks and the registry index in one shot.
# 一次性恢复旧位号、旧水位线与注册器索引。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	GPTagRuleService.gpRevertPlan(gpCtx.gpGraph, _gpPlan)
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpRules.gpSeqMarks = _gpOldMarks.duplicate()
		gpCtx.gpTags.gpRebuild()
	gpCtx.gpGraph.gpGraphChanged.emit()


# Replay the captured plan. / 重放已捕获的方案。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	GPTagRuleService.gpApplyPlan(gpCtx.gpGraph, _gpPlan)
	if gpCtx.gpTags != null:
		# The plan's numbers are already minted; just re-seed the index from the graph.
		# 方案里的号已经铸造过，只需从图重建索引。
		gpCtx.gpTags.gpRebuild()
	gpCtx.gpGraph.gpGraphChanged.emit()
