class_name GPSetEdgeTagCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# ADR-36 D6/D7 supersede the old "duplicates are not refused" stance: a hand-typed line number
# must satisfy the line rule AND be unique ON THIS SHEET (the same number on another sheet is
# the legitimate continuation case, D1). A successful hand edit still sets gpAttrs["tag_manual"]
# so a future renumber skips a deliberate choice.
# ADR-36 D6/D7 取代旧口径「重号不作拒绝」：手打的管线号必须符合线规则，且在本图内唯一
#（同号出现在另一张图纸是合法的延续，见 D1）。手工改号成功后仍置 gpAttrs["tag_manual"]，
# 使今后的重编号跳过这次刻意的选择。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpEdgeId: String = ""
var gpNewTag: String = ""

# True when the change was PROPAGATED from the source line of a cross-sheet link (user
# feedback 2026-11-04): a propagated number is a continuation, not a deliberate hand choice,
# so tag_manual must stay unset — the peer edge keeps FOLLOWING the source. Validation (line
# rule + on-sheet uniqueness) is identical to a hand edit.
# 为 true 时表示本次改号是**从跨图纸 link 的源端传播**而来（用户反馈 2026-11-04）：传播号
# 是延续而非刻意的受选手选，故**不**置 tag_manual —— 对端边继续保持跟随源端。校验（线规则
# 与本图查重）与手改完全一致。
var gpPropagated: bool = false

# Previous tag, captured at execute time so undo is exact.
# 执行时捕获的原位号，使撤销精确。
var _gpOldTag: String = ""
var _gpHadManual: bool = false

# Machine-readable refusal + human detail, mirroring GPSetTagCommand.
# 机器可读拒绝码 + 人类明细，与 GPSetTagCommand 一致。
var gpRefusal: String = ""
var gpRefusalDetail: String = ""


func _init(gpInEdgeId: String, gpInNewTag: String, gpInPropagated: bool = false) -> void:
	gpEdgeId = gpInEdgeId
	gpNewTag = gpInNewTag
	gpPropagated = gpInPropagated
	gpLabel = "联动改号" if gpInPropagated else "修改管线号"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null or gpE.gpTag == gpNewTag:
		return false
	gpRefusal = ""
	gpRefusalDetail = ""
	var gpWant: String = gpNewTag.strip_edges()
	if gpWant != "":
		var gpChk: Dictionary = _gpCheckRule(gpCtx, gpWant)
		if not bool(gpChk.get("ok", true)):
			gpRefusal = "tag.err_rule"
			gpRefusalDetail = str(gpChk.get("detail", ""))
			return false
		if _gpIsTaken(gpCtx, gpWant):
			gpRefusal = "tag.err_duplicate"
			gpRefusalDetail = gpWant
			return false
	gpNewTag = gpWant
	_gpOldTag = gpE.gpTag
	_gpHadManual = bool(gpE.gpAttrs.get("tag_manual", false))
	gpE.gpTag = gpNewTag
	# A hand-typed number is a deliberate choice: remember it so renumbering leaves it alone.
	# A PROPAGATED number is the opposite — it must keep following the source, so the flag
	# stays untouched (undo still restores the exact prior state via _gpHadManual).
	# 手工输入的号是刻意选择：记住它，使重新编号时不碰它。**传播**来的号正相反 —— 它必须
	# 继续跟随源端，故标记保持不动（撤销仍经 _gpHadManual 精确还原先前状态）。
	if gpNewTag != "" and not gpPropagated:
		gpE.gpAttrs["tag_manual"] = true
	gpCtx.gpGraph.gpNotifyChanged()
	return true


# Check a candidate against the project's LINE rule (segmented designation, or a legacy
# template if the project has not migrated yet).
# 按工程的**管线**规则校验候选号（分段代号；工程尚未迁移时为旧式模板）。
func _gpCheckRule(gpCtx: GPCommandContext, gpTag: String) -> Dictionary:
	var gpStd: GPProjectStandard = gpCtx.gpGraph.gpStandard
	if gpStd == null:
		return {"ok": true}
	var gpRules: GPProjectTagRules = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE)
	var gpRule: GPTagRule = gpRules.gpRuleFor(null)
	return gpRule.gpCheckTemplateTag(gpTag, gpRules.gpPrefixFor(null))


# Sheet scope (D1): the same number may legitimately appear on ANOTHER sheet.
# 单页作用域（D1）：同一个号可以合法地出现在**另一张**图纸上。
func _gpIsTaken(gpCtx: GPCommandContext, gpTag: String) -> bool:
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpGraph = gpCtx.gpGraph
		return gpCtx.gpTags.gpIsTakenForClass(GPProjectStandard.GP_CLASS_LINE, gpTag, gpEdgeId)
	return GPTagGen.gpIsTaken(gpCtx.gpGraph, gpTag, gpEdgeId)


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	gpE.gpTag = _gpOldTag
	if _gpHadManual:
		gpE.gpAttrs["tag_manual"] = true
	else:
		gpE.gpAttrs.erase("tag_manual")
	gpCtx.gpGraph.gpNotifyChanged()


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
