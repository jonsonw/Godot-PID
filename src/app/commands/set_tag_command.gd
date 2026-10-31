class_name GPSetTagCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Change one instance's 位号 (tag) — M11.
#
# Why this is a command and not a direct write / 为何要成为命令而非直接写入：
# the tag ends up in the DCS point list and on the physical nameplate. A typo must be
# undoable in one step, and a duplicate must be REFUSED rather than silently suffixed —
# a silently renamed tag ships a drawing that no longer matches the plant.
# 位号最终会出现在 DCS 点表与现场标牌上。打错必须一步可撤销，重复必须**拒绝**
# 而非静默加后缀 —— 静默改名的图纸到了现场就与装置对不上。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var _gpId: String = ""
var _gpNewTag: String = ""
var _gpOldTag: String = ""

# Machine-readable refusal + the human detail (e.g. "第 3 段（管线号）：应为 4 位数字"),
# so the shell can say WHY instead of a generic failure.
# 机器可读的拒绝码 + 人类可读明细（如「第 3 段（管线号）：应为 4 位数字」），
# 使外壳能说明**为什么**，而不是笼统失败。
var gpRefusal: String = ""
var gpRefusalDetail: String = ""


func _init(gpInId: String, gpInTag: String) -> void:
	_gpId = gpInId
	_gpNewTag = gpInTag
	gpLabel = "修改位号"


# Apply the tag. Returns false when the node is gone, nothing changes, or the tag is already
# taken by another instance (the registry owns project-wide uniqueness).
# 应用位号。节点不存在、无实际变化，或位号已被其他实例占用时返回 false
#（工程级唯一性由注册表负责）。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return false
	var gpNew: String = _gpNewTag.strip_edges()
	if gpN.gpTag == gpNew:
		return false
	gpRefusal = ""
	gpRefusalDetail = ""
	# ADR-36 D7: a hand-typed tag must satisfy the numbering rule, not just be unique.
	# 候选号先过规则，再过唯一性。
	if gpNew != "":
		var gpChk: Dictionary = _gpCheckRule(gpCtx, gpN, gpNew)
		if not bool(gpChk.get("ok", true)):
			gpRefusal = "tag.err_rule"
			gpRefusalDetail = str(gpChk.get("detail", ""))
			return false
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpGraph = gpCtx.gpGraph
		if gpNew != "" and gpCtx.gpTags.gpIsTaken(gpNew, _gpId):
			gpRefusal = "tag.err_duplicate"
			gpRefusalDetail = gpNew
			return false
 # gpRegister() releases any previous binding for this id first, so register == rename.
 # gpRegister() 会先注销该 id 的旧绑定，故「登记」即「改名」。
		if not gpCtx.gpTags.gpRegister(_gpId, gpNew).gpIsOk():
			gpRefusal = "tag.err_duplicate"
			gpRefusalDetail = gpNew
			return false
	_gpOldTag = gpN.gpTag
	gpN.gpTag = gpNew
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


# Check the candidate against the RULE OF THE NODE'S CLASS. A node whose class is unknown
# (an unmapped symbol) is only checked for uniqueness — there is no rule to violate.
# 按该节点**所属类别**的规则校验。类别未知（未映射图元）只查唯一性 —— 没有规则可违反。
func _gpCheckRule(gpCtx: GPCommandContext, gpN: GPPIDNode, gpTag: String) -> Dictionary:
	var gpStd: GPProjectStandard = gpCtx.gpGraph.gpStandard
	if gpStd == null or gpN == null:
		return {"ok": true}
	var gpDef: GPSymbolDef = GPSymbolLibrary.gpFindById(gpN.gpSymbolId)
	var gpClass: String = gpStd.gpClassOf(gpDef, gpN.gpProps)
	if gpClass == "":
		return {"ok": true}
	var gpRules: GPProjectTagRules = gpStd.gpRulesOf(gpClass)
	var gpRule: GPTagRule = gpRules.gpRuleFor(gpDef)
	var gpPrefix: String = gpRules.gpPrefixFor(gpDef)
	return gpRule.gpCheckTemplateTag(gpTag, gpPrefix)


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpTag = _gpOldTag
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpGraph = gpCtx.gpGraph
		gpCtx.gpTags.gpRegister(_gpId, _gpOldTag)
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpTag = _gpNewTag
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpGraph = gpCtx.gpGraph
		gpCtx.gpTags.gpRegister(_gpId, _gpNewTag)
	gpCtx.gpGraph.gpGraphChanged.emit()
