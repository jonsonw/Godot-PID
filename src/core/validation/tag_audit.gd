class_name GPTagAudit
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Project-wide TAG audit (ADR-36 C): one pass over every sheet that answers "is any tag missing,
# duplicated, non-compliant, or out of step with its attributes".
# 工程级**位号审计**（ADR-36 C）：一次扫过所有图纸，回答「有没有位号缺失 / 重复 / 不合规 /
# 与属性脱节」。
#
# WHY A SEPARATE CLASS FROM GPRulePack / 为何与 GPRulePack 分开：
# GPRulePack's rule 3 sees ONE sheet, because that is what the canvas has. Uniqueness, though,
# is a PROJECT property — and the export gate must judge the same thing the audit does, or the
# list could ship duplicates the check never looked at. So the project-wide tag judgement lives
# here, is used by BOTH the DRC project mode and the export gate, and rule 3 keeps serving the
# single-sheet case (existing behaviour, existing tests).
# GPRulePack 的规则 3 只看**一张**图纸，因为画布只有一张。但唯一性是**工程**属性 —— 而且导出闸门
# 必须与审计判同一件事，否则清单可能带着审计没看过的重复号出厂。故工程级的位号判断放在这里，
# 由 DRC 全工程模式与导出闸门**共用**，规则 3 继续服务单图纸场景（既有行为、既有测试）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_RULE_TAG: String = "drc.tag"


# Audit every sheet. Returns findings sorted deterministically (rule id, world, node, edge),
# exactly like GPRulePack.gpRun(), so two runs on the same project produce identical reports.
# 审计每张图纸。返回按（规则号、位置、节点、连线）确定排序的发现，与 GPRulePack.gpRun() 一致，
# 故同一工程两次运行产出相同报告。
static func gpRun(gpSheets: Array, gpDefs: Array[GPSymbolDef],
		gpStd: GPProjectStandard = null) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	var gpLookup: Dictionary = {}
	for gpD in gpDefs:
		if gpD != null:
			gpLookup[gpD.gpId] = gpD
	if gpSheets.is_empty():
		return gpOut
	_gpAuditNodes(gpSheets, gpLookup, gpStd, gpOut)
	_gpAuditLines(gpSheets, gpStd, gpOut)
	gpOut.sort_custom(func(gpA: GPFinding, gpB: GPFinding) -> bool:
		if gpA.gpRuleId != gpB.gpRuleId:
			return gpA.gpRuleId < gpB.gpRuleId
		if gpA.gpNodeId != gpB.gpNodeId:
			return gpA.gpNodeId < gpB.gpNodeId
		return gpA.gpEdgeId < gpB.gpEdgeId)
	return gpOut


# Whether any finding is an error — the export gate's only question.
# 是否存在 error 级发现 —— 导出闸门唯一要问的事。
static func gpHasBlocking(gpFindings: Array[GPFinding]) -> bool:
	for gpF in gpFindings:
		if gpF.gpSeverity == GPFinding.GP_ERROR:
			return true
	return false


# A short human summary of the blocking tags, for the export dialog's refusal message.
# 阻断位号的简短人类摘要，供导出对话框的拒绝文案使用。
static func gpBlockingSummary(gpFindings: Array[GPFinding], gpMax: int = 3) -> String:
	var gpParts: Array[String] = []
	for gpF in gpFindings:
		if gpF.gpSeverity != GPFinding.GP_ERROR:
			continue
		var gpText: String = str(gpF.gpParams[0]) if gpF.gpParams.size() > 0 else ""
		if gpText != "" and not gpParts.has(gpText):
			gpParts.append(gpText)
		if gpParts.size() >= gpMax:
			break
	return ", ".join(gpParts)


# ---- nodes / 节点 ----

static func _gpAuditNodes(gpSheets: Array, gpLookup: Dictionary, gpStd: GPProjectStandard,
		gpOut: Array[GPFinding]) -> void:
	var gpOwners: Dictionary = {}
	var gpOrder: Array[String] = []
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null or gpSheet.gpGraph == null:
			continue
		for gpN in gpSheet.gpGraph.gpNodes:
			if gpN == null:
				continue
			# Mounted parts are identified by nozzle_id, not by a tag (ADR-23 D6).
			# 挂载部件凭 nozzle_id 标识而非位号（ADR-23 D6）。
			if gpN.gpParentUid != "":
				continue
			var gpDef: GPSymbolDef = gpLookup.get(gpN.gpSymbolId) as GPSymbolDef
			if gpDef == null or gpDef.gpCategory == "annotation" or not gpDef.gpTaggable:
				continue
			var gpTag: String = gpN.gpTag.strip_edges()
			if gpTag == "":
				gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_ERROR,
					"drc.tag_missing", [gpN.gpInstanceId]).gpOnNode(
						gpN.gpInstanceId, gpN.gpPosition))
				continue
			var gpNorm: String = GPTagRegistry.gpNormalize(gpTag)
			if not gpOwners.has(gpNorm):
				gpOwners[gpNorm] = []
				gpOrder.append(gpNorm)
			(gpOwners[gpNorm] as Array).append({"node": gpN, "sheet": gpSheet, "def": gpDef})
	# Duplicates: the first owner keeps the tag, every later one is a finding — across sheets.
	# 重复：首个占用者保留，之后每一个都算一条 —— 跨图纸。
	for gpNorm in gpOrder:
		var gpList: Array = gpOwners[gpNorm] as Array
		if gpList.size() < 2:
			continue
		var gpFirstNode: GPPIDNode = (gpList[0]["node"] as GPPIDNode)
		for gpI in range(gpList.size()):
			if gpI == 0:
				continue
			var gpN: GPPIDNode = gpList[gpI]["node"] as GPPIDNode
			gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_ERROR,
				"drc.tag_duplicate", [gpN.gpTag, gpFirstNode.gpInstanceId,
					gpN.gpInstanceId]).gpOnNode(gpN.gpInstanceId, gpN.gpPosition))
	# Compliance: a tag that does not fit its class rule is a defect of the DRAWING.
	# 合规性：不符合本类规则的位号是**图纸**的缺陷。
	if gpStd == null:
		return
	for gpNorm in gpOrder:
		for gpItemRaw in gpOwners[gpNorm] as Array:
			var gpItem: Dictionary = gpItemRaw as Dictionary
			var gpN: GPPIDNode = gpItem["node"] as GPPIDNode
			var gpDef: GPSymbolDef = gpItem["def"] as GPSymbolDef
			var gpClass: String = gpStd.gpClassOf(gpDef, gpN.gpProps)
			if gpClass == "":
				gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_INFO,
					"drc.tag_class_unmapped", [gpN.gpInstanceId]).gpOnNode(
						gpN.gpInstanceId, gpN.gpPosition))
				continue
			var gpRules: GPProjectTagRules = gpStd.gpRulesOf(gpClass)
			var gpRule: GPTagRule = gpRules.gpRuleFor(gpDef)
			var gpChk: Dictionary = gpRule.gpCheckTemplateTag(gpN.gpTag,
				gpRules.gpPrefixFor(gpDef))
			if not bool(gpChk.get("ok", true)):
				gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_ERROR,
					"drc.tag_invalid", [gpN.gpInstanceId, str(gpChk.get("detail", ""))]).gpOnNode(
						gpN.gpInstanceId, gpN.gpPosition))


# ---- lines / 管线 ----

static func _gpAuditLines(gpSheets: Array, gpStd: GPProjectStandard,
		gpOut: Array[GPFinding]) -> void:
	var gpGroups: Dictionary = {}
	var gpOrder: Array[String] = []
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null or gpSheet.gpGraph == null:
			continue
		for gpE in gpSheet.gpGraph.gpEdges:
			if gpE == null:
				continue
			if gpE.gpKind != GPPIDEdge.GP_PROCESS and gpE.gpKind != GPPIDEdge.GP_UTILITY:
				continue
			var gpTag: String = gpE.gpTag.strip_edges()
			if gpTag == "":
				gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_WARNING,
					"drc.edge_tag_missing", [gpE.gpInstanceId]).gpOnEdge(
						gpE.gpInstanceId, _gpEdgeMid(gpSheet.gpGraph, gpE)))
				continue
			var gpNorm: String = GPTagRegistry.gpNormalize(gpTag)
			if not gpGroups.has(gpNorm):
				gpGroups[gpNorm] = []
				gpOrder.append(gpNorm)
			(gpGroups[gpNorm] as Array).append({"edge": gpE, "graph": gpSheet.gpGraph,
				"sheet": gpSheet})
	var gpRule: GPTagRule = null
	var gpRules: GPProjectTagRules = null
	if gpStd != null:
		gpRules = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE)
		gpRule = gpRules.gpRuleFor(null)
	for gpNorm in gpOrder:
		var gpList: Array = gpGroups[gpNorm] as Array
		var gpFirst: GPPIDEdge = (gpList[0]["edge"] as GPPIDEdge)
		# One number on several sheets is the legitimate continuation case (D1) — reported as
		# info, never as a defect, because only the draughtsman can tell continuation from a
		# collision (the declaration mechanism lands with W22).
		# 一个号出现在多张图纸上是合法的延续（D1）—— 只报 info，绝不报缺陷，因为只有制图员能区分
		# 「延续」与「撞号」（声明机制随 W22 落地）。
		var gpSheetNames: Dictionary = {}
		for gpItemRaw in gpList:
			var gpSheetObj: GPSheet = (gpItemRaw as Dictionary)["sheet"] as GPSheet
			if gpSheetObj != null:
				gpSheetNames[gpSheetObj.gpName if gpSheetObj.gpName != "" else
					str(gpSheetObj.gpIndex + 1)] = true
		if gpSheetNames.size() > 1:
			gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_INFO,
				"drc.line_shared_across_sheets", [gpFirst.gpTag, gpSheetNames.size()]).gpOnEdge(
					gpFirst.gpInstanceId, _gpEdgeMid(gpList[0]["graph"] as GPPIDGraph, gpFirst)))
		if gpRule == null or not gpRule.gpUsesSegments():
			continue
		var gpChk: Dictionary = gpRule.gpCheckTag(gpFirst.gpTag)
		if not bool(gpChk.get("ok", true)):
			gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_ERROR,
				"drc.line_tag_invalid", [gpFirst.gpTag, str(gpChk.get("detail", ""))]).gpOnEdge(
					gpFirst.gpInstanceId, _gpEdgeMid(gpList[0]["graph"] as GPPIDGraph, gpFirst)))
			continue
		# Stale: the tag's attribute segments are not supported by ANY edge of this line. One
		# segment may legitimately differ from the others (a size change mid-line, D2), so the
		# test is "nobody supports it", not "the first edge disagrees".
		# 陈旧：号里的属性段**没有任何一段**支持。一根线中途变径是合法的（D2），故判据是
		# 「没有任何一段支持」，而不是「第一段不同意」。
		var gpSeq: int = gpRule.gpSequenceOf(gpFirst.gpTag)
		var gpSupported: bool = false
		if gpSeq >= 0:
			for gpItemRaw in gpList:
				var gpE: GPPIDEdge = (gpItemRaw as Dictionary)["edge"] as GPPIDEdge
				if gpRule.gpRender({"seq": gpSeq, "attrs": gpE.gpAttrs}, gpStd) == gpFirst.gpTag:
					gpSupported = true
					break
		if not gpSupported:
			gpOut.append(GPFinding.gpMake(GP_RULE_TAG, GPFinding.GP_WARNING,
				"drc.line_tag_stale", [gpFirst.gpTag]).gpOnEdge(gpFirst.gpInstanceId,
					_gpEdgeMid(gpList[0]["graph"] as GPPIDGraph, gpFirst)))


# Middle of an edge, for "jump to" positioning (same rule as GPRulePack's helper).
# 边的中点，供「跳转到」定位（与 GPRulePack 的辅助同一规则）。
static func _gpEdgeMid(gpGraph: GPPIDGraph, gpE: GPPIDEdge) -> Vector2:
	if gpE == null or gpGraph == null:
		return Vector2.INF
	if not gpE.gpRouting.is_empty():
		return (gpE.gpRouting[0] + gpE.gpRouting[gpE.gpRouting.size() - 1]) * 0.5
	var gpA: GPPIDNode = gpGraph.gpGetNode(str(gpE.gpFromRef.get("node_id", "")))
	var gpB: GPPIDNode = gpGraph.gpGetNode(str(gpE.gpToRef.get("node_id", "")))
	if gpA == null or gpB == null:
		return Vector2.INF
	return (gpA.gpPosition + gpB.gpPosition) * 0.5
