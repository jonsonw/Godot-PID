class_name GPSetLineAttrsCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Write the attributes typed into the "line attributes" panel and re-render the line number
# from them (ADR-36 D8/D9).
# 把「管线属性」面板里填的属性写回，并据此重渲染管线号（ADR-36 D8/D9）。
#
# WHY ONE COMMAND / 为何是一条命令：
# the user experiences "I just told the drawing what this line carries" as ONE action. Setting
# four attributes plus the number as five undo steps would make Ctrl+Z walk back through a
# half-described line — and a half-described line is exactly what produces a stale number.
# 用户感知的是「我刚告诉图纸这根线走什么介质」**一个动作**。把四个属性加位号拆成五个撤销步，
# 会让 Ctrl+Z 走过一堆「半描述」状态 —— 而半描述的线正是产生不新鲜位号的原因。
#
# THE NUMBER IS RE-RENDERED, NOT RE-MINTED / 号是**重渲染**，不是重新铸造：
# the placeholder minted at creation already owns a sequence number; filling the attributes
# must reuse it (`gpSequenceOf`), otherwise every line would silently burn one number and the
# four-digit counter would drift away from what is drawn.
# 创建时铸出的占位号已经占有一个序号；补属性必须**复用它**（`gpSequenceOf`），否则每根线都会
# 悄悄烧掉一个号，四位计数器就会与图上所见脱节。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpEdgeId: String = ""
var gpAttrs: Dictionary = {}

# Machine-readable refusal + human detail (mirrors the tag commands).
# 机器可读拒绝码 + 人类明细（与位号命令一致）。
var gpRefusal: String = ""
var gpRefusalDetail: String = ""

# Captured at first execute, replayed on redo — a redo must reproduce the SAME tag.
# 首次执行时捕获，重做时重放 —— 重做必须复现**同一个**位号。
var _gpOldTag: String = ""
var _gpOldAttrs: Dictionary = {}
var _gpHadKeys: Dictionary = {}
var _gpNewTag: String = ""
var _gpPlanned: bool = false


func _init(gpInEdgeId: String, gpInAttrs: Dictionary) -> void:
	gpEdgeId = gpInEdgeId
	gpAttrs = gpInAttrs.duplicate(true)
	gpLabel = "填写管线属性"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	gpRefusal = ""
	gpRefusalDetail = ""
	if not _gpPlanned:
		_gpOldTag = gpE.gpTag
		_gpOldAttrs = {}
		_gpHadKeys = {}
		for gpKey in gpAttrs.keys():
			var gpK: String = str(gpKey)
			_gpHadKeys[gpK] = gpE.gpAttrs.has(gpK)
			if gpE.gpAttrs.has(gpK):
				_gpOldAttrs[gpK] = gpE.gpAttrs[gpK]
		_gpNewTag = _gpPlanTag(gpCtx, gpE, gpAttrs)
		_gpPlanned = true
	_applyAttrs(gpE, gpAttrs)
	if _gpNewTag != "":
		gpE.gpTag = _gpNewTag
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	for gpKey in _gpHadKeys.keys():
		var gpK: String = str(gpKey)
		if bool(_gpHadKeys[gpK]):
			gpE.gpAttrs[gpK] = _gpOldAttrs.get(gpK, "")
		else:
			gpE.gpAttrs.erase(gpK)
	gpE.gpTag = _gpOldTag
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	# The plan is already captured; `_gpPlanned` keeps _gpPlanTag() from running again.
	# 方案已捕获；`_gpPlanned` 阻止再次推导，故重做复现同一个号。
	gpExecute(gpCtx)


# Work out the tag: re-render the SAME sequence with the new attributes; fall back to minting
# (which advances the mark) only when the old tag cannot be read or would collide.
# 推导位号：用新属性**重渲染同一个序号**；只有旧号读不出或会撞号时才真正铸新号（推进水位线）。
func _gpPlanTag(gpCtx: GPCommandContext, gpE: GPPIDEdge, gpNewAttrs: Dictionary) -> String:
	# Registry fallback: numbering may run off the registry's standard even when the graph has
	# none (see GPEditService.gpApplyLineAttrs, which also heals the split).
	# 注册器兜底：图上的标准为空时，铸造仍可能走注册器的标准（见 gpApplyLineAttrs 的修复）。
	var gpStd: GPProjectStandard = gpCtx.gpGraph.gpStandard
	if gpStd == null and gpCtx.gpTags != null:
		gpStd = gpCtx.gpTags.gpStandard
	if gpStd == null:
		return ""
	var gpRules: GPProjectTagRules = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE)
	var gpRule: GPTagRule = gpRules.gpRuleFor(null)
	if not gpRule.gpUsesSegments():
		return ""
	var gpMerged: Dictionary = gpE.gpAttrs.duplicate(true)
	for gpKey in gpNewAttrs.keys():
		gpMerged[str(gpKey)] = gpNewAttrs[gpKey]
	var gpSeq: int = gpRule.gpSequenceOf(gpE.gpTag)
	if gpSeq >= 0:
		var gpCandidate: String = gpRule.gpRender({"seq": gpSeq, "attrs": gpMerged}, gpStd)
		if gpCandidate != "" and not _gpWouldCollide(gpCtx, gpCandidate):
			return gpCandidate
	# No readable sequence (or a collision with a manually typed tag): mint a fresh one.
	# 读不出序号（或与手工号相撞）：铸一个新号。
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpGraph = gpCtx.gpGraph
		return gpCtx.gpTags.gpNextTagForClass(GPProjectStandard.GP_CLASS_LINE, null, gpMerged)
	return ""


func _gpWouldCollide(gpCtx: GPCommandContext, gpTag: String) -> bool:
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpGraph = gpCtx.gpGraph
		return gpCtx.gpTags.gpIsTakenForClass(GPProjectStandard.GP_CLASS_LINE, gpTag, gpEdgeId)
	return GPTagGen.gpIsTaken(gpCtx.gpGraph, gpTag, gpEdgeId)


# Blank means "clear this attribute", matching the rest of the app's blank=clear rule.
# 空白表示「清空该属性」，与应用其它地方的「空白=清空」一致。
static func _applyAttrs(gpE: GPPIDEdge, gpValues: Dictionary) -> void:
	for gpKey in gpValues.keys():
		var gpK: String = str(gpKey)
		var gpV: String = str(gpValues[gpKey]).strip_edges()
		if gpV == "":
			gpE.gpAttrs.erase(gpK)
		else:
			gpE.gpAttrs[gpK] = gpV
