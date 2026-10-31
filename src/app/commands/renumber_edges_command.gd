class_name GPRenumberCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Renumber LINES through the project standard (ADR-36 D8), as one undo step.
# 按项目标准重排**管线号**（ADR-36 D8），一个撤销步。
#
# WHY GROUPS AND NOT EDGES / 为何按「管线组」而不是按边：
# one line is often several edges (a valve splits a pipe), and a continued line has segments on
# another sheet. Renumbering per edge would give the two halves of one pipe two different
# numbers — the exact defect this command must not create. So edges sharing a tag are ONE group
# and receive ONE new number, across sheets.
# 一根管线常常是多条边（阀门把管子切开），延续的线还在另一张图纸上有段。逐边重排会给同一根
# 管线的两半分出两个号 —— 正是本命令绝不能制造的缺陷。故同号的边是**一个组**，跨图纸得到**一个**号。
#
# MANUAL NUMBERS ARE LEFT ALONE / 手工号不动：
# gpAttrs["tag_manual"] marks a deliberate choice; renumbering must not overwrite it (the old
# contract, kept). A group containing one hand-set number is skipped WHOLE — changing half of
# one pipe would split it into two.
# gpAttrs["tag_manual"] 标记刻意选择，重排不得覆盖（沿用旧契约）。组内任一边是手工号，**整组**跳过 ——
# 只改一根管子的一半会把它拆成两个号。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Edge id -> previous tag, captured before renumbering. / 重排前：边 id -> 原位号。
var _gpOldTags: Dictionary = {}

# Previous line sequence marks, so undo restores them exactly.
# 重排前的线号水位线，使撤销精确还原。
var _gpOldMarks: Dictionary = {}

# How many edges actually got a new number (for the "nothing to do" check).
# 实际被重排的边数量（用于「无需操作」判定）。
var _gpCount: int = 0

# True when the marks were restored early because minting overflowed.
# 因溢出提前还原水位线时为 true。
var _gpMarkKind: String = ""


func _init() -> void:
	gpLabel = "重新编号"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpGraphs: Array[GPPIDGraph] = []
	if gpCtx.gpTags != null:
		for gpG in gpCtx.gpTags.gpGraphs():
			gpGraphs.append(gpG)
	if gpGraphs.is_empty():
		gpGraphs.append(gpCtx.gpGraph)
	_gpOldTags = {}
	for gpG in gpGraphs:
		for gpE in gpG.gpEdges:
			_gpOldTags[gpE.gpInstanceId] = gpE.gpTag
	_gpCount = 0
	var gpStd: GPProjectStandard = gpCtx.gpGraph.gpStandard
	if gpStd != null:
		var gpRules: GPProjectTagRules = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE)
		var gpRule: GPTagRule = gpRules.gpRuleFor(null)
		if gpRule.gpUsesSegments():
			return _gpRenumberSegmented(gpGraphs, gpStd, gpRules, gpRule)
	return _gpRenumberLegacy(gpCtx)


# Segment-based line renumbering: one number per (old tag) group, across sheets.
# 分段线号重排：按（旧号）分组，跨图纸一号一组。
func _gpRenumberSegmented(gpGraphs: Array[GPPIDGraph], gpStd: GPProjectStandard,
		gpRules: GPProjectTagRules, gpRule: GPTagRule) -> bool:
	_gpMarkKind = "class"
	_gpOldMarks = gpRules.gpSeqMarks.duplicate()
	gpRules.gpResetMarks()
	# Node tags are the other half of the one table; lines may not take them.
	# 节点位号是同一张表的另一半；管线不得占用。
	var gpTaken: Dictionary = {}
	for gpG in gpGraphs:
		for gpN in gpG.gpNodes:
			if gpN.gpTag != "":
				gpTaken[GPTagRegistry.gpNormalize(gpN.gpTag)] = true
	# Group edges by their current tag, preserving sheet order then edge order.
	# 按当前号把边分组，保持「图纸顺序 → 边顺序」。
	var gpGroupKeys: Array[String] = []
	var gpGroups: Dictionary = {}
	for gpG in gpGraphs:
		for gpE in gpG.gpEdges:
			if gpE.gpKind == GPPIDEdge.GP_SIGNAL:
				continue
			var gpKey: String = ("tag:" + gpE.gpTag) if gpE.gpTag != "" \
				else ("edge:" + gpE.gpInstanceId)
			if not gpGroups.has(gpKey):
				gpGroups[gpKey] = []
				gpGroupKeys.append(gpKey)
			(gpGroups[gpKey] as Array).append(gpE)
	for gpKey in gpGroupKeys:
		var gpEdges: Array = gpGroups[gpKey] as Array
		var gpManual: bool = false
		for gpERaw in gpEdges:
			if bool((gpERaw as GPPIDEdge).gpAttrs.get("tag_manual", false)):
				gpManual = true
				break
		if gpManual:
			continue
		var gpAttrs: Dictionary = (gpEdges[0] as GPPIDEdge).gpAttrs
		var gpNewTag: String = ""
		var gpSkips: int = 0
		while gpSkips < GPProjectTagRules.GP_MAX_SKIPS:
			var gpSeq: int = gpRules.gpAdvance(GPProjectStandard.GP_CLASS_LINE, gpRule)
			gpNewTag = gpRule.gpRender({"seq": gpSeq, "attrs": gpAttrs}, gpStd)
			if gpNewTag == "":
				# Counter overflow: stop rather than hand out an empty tag.
				# 计数器溢出：宁可停下，也不发出空号。
				gpRules.gpSeqMarks = _gpOldMarks.duplicate()
				return false
			if not gpTaken.has(GPTagRegistry.gpNormalize(gpNewTag)):
				break
			gpSkips += 1
		gpTaken[GPTagRegistry.gpNormalize(gpNewTag)] = true
		for gpERaw in gpEdges:
			var gpE: GPPIDEdge = gpERaw as GPPIDEdge
			if gpE.gpTag != gpNewTag:
				gpE.gpTag = gpNewTag
				_gpCount += 1
	for gpG in gpGraphs:
		gpG.gpGraphChanged.emit()
	return _gpCount > 0


# Pre-ADR-36 behaviour, kept verbatim for projects that never adopted a standard.
# 从未采用标准的工程沿用 ADR-36 之前的行为，原样保留。
func _gpRenumberLegacy(gpCtx: GPCommandContext) -> bool:
	_gpMarkKind = "meta"
	var gpGraph: GPPIDGraph = gpCtx.gpGraph
	_gpOldMarks = (gpGraph.gpMeta.get(GPTagGen.GP_META_KEY, {}) as Dictionary).duplicate()
	gpGraph.gpMeta[GPTagGen.GP_META_KEY] = {}
	for gpE in gpGraph.gpEdges:
		if gpE.gpKind == GPPIDEdge.GP_SIGNAL:
			continue
		if bool(gpE.gpAttrs.get("tag_manual", false)):
			continue
		gpE.gpTag = GPTagGen.gpNextTag(gpGraph, GPTagGen.GP_PIPE_PREFIX)
		_gpCount += 1
	gpGraph.gpGraphChanged.emit()
	return _gpCount > 0


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpGraphs: Array[GPPIDGraph] = []
	if gpCtx.gpTags != null:
		for gpG in gpCtx.gpTags.gpGraphs():
			gpGraphs.append(gpG)
	if gpGraphs.is_empty():
		gpGraphs.append(gpCtx.gpGraph)
	for gpG in gpGraphs:
		for gpE in gpG.gpEdges:
			if _gpOldTags.has(gpE.gpInstanceId):
				gpE.gpTag = str(_gpOldTags[gpE.gpInstanceId])
	# Restore the marks where they were taken from.
	# 把水位线还原到它原来的位置。
	if _gpMarkKind == "class":
		var gpStd: GPProjectStandard = gpCtx.gpGraph.gpStandard
		if gpStd != null:
			gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpSeqMarks = _gpOldMarks.duplicate()
	elif _gpMarkKind == "meta":
		gpCtx.gpGraph.gpMeta[GPTagGen.GP_META_KEY] = _gpOldMarks.duplicate()
	for gpG in gpGraphs:
		gpG.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
