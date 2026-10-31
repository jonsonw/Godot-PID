class_name GPDrcEngine
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# The DRC engine (ADR-39 D2/D5): build one resolved snapshot, run the registered rules, merge the
# legacy pack, apply config + waivers, dedupe and sort. Pure; no Node, no autoload.
# DRC 引擎（ADR-39 D2/D5）：构建一份已解析快照，跑注册规则、合并 legacy 包、应用配置与豁免、
# 去重排序。纯函数：不碰 Node、不碰 autoload。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_SCOPE_SHEET: String = "sheet"
const GP_SCOPE_PROJECT: String = "project"


# Run one sheet. `gpOptions` may carry {"skip_tags": bool}.
# 跑一张图。`gpOptions` 可带 {"skip_tags": bool}。
static func gpRunSheet(gpGraph: GPPIDGraph, gpSheet: GPSheet,
		gpDefs: Array[GPSymbolDef] = [], gpStd: GPProjectStandard = null,
		gpOptions: Dictionary = {}) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	if gpGraph == null:
		return gpOut
	var gpSnap: GPDrcSnapshot = GPDrcSnapshot.gpBuild(gpGraph, gpSheet, gpDefs, gpStd)
	var gpCfg: Dictionary = gpStd.gpValidationConfig() if gpStd != null \
		else GPDRCConfig.gpDefaults()
	var gpSkipTags: bool = bool(gpOptions.get("skip_tags", false))
	var gpFamilies: Array = gpOptions.get("families", [])
	var gpSkipLegacy: bool = bool(gpOptions.get("skip_legacy", false))

	# ---- legacy pack (the seven baseline rules) ----
	if not gpSkipLegacy:
		for gpF in GPRulePack.gpRun(gpGraph, gpSheet, gpDefs, gpSkipTags):
			if gpF != null and _gpAdopt(gpSnap, gpCfg, gpF):
				gpOut.append(gpF)

	# ---- registered rules ----
	for gpR in GPDrcRegistry.gpAll():
		if gpR.gpLegacy:
			continue
		if not gpFamilies.is_empty() and not gpFamilies.has(gpR.gpFamily):
			continue
		if not GPDRCConfig.gpEnabled(gpCfg, gpR.gpId):
			continue
		if gpR.gpRequires != "":
			continue
		var gpFound: Array[GPFinding] = gpR.gpRun(gpSnap, gpCfg)
		for gpF in gpFound:
			if gpF != null and _gpAdopt(gpSnap, gpCfg, gpF):
				gpOut.append(gpF)

	return gpFinalize(gpOut, gpStd)


# Finalise a raw finding list: apply waivers and the deterministic finish. Public so a
# time-sliced scheduler can merge slices through the SAME contract as a full run.
# 收口一组原始发现：应用豁免与确定性排序。公开，使时间切片调度器通过**同一契约**合并切片。
static func gpFinalize(gpFindings: Array[GPFinding],
		gpStd: GPProjectStandard = null) -> Array[GPFinding]:
	var gpCfg: Dictionary = gpStd.gpValidationConfig() if gpStd != null \
		else GPDRCConfig.gpDefaults()
	GPDRCConfig.gpApplyWaivers(gpFindings, gpCfg)
	return _gpFinish(gpFindings)


# Run every sheet + project-wide audits.
# 跑全部图纸 + 工程级审计。
static func gpRunProject(gpSheets: Array, gpDefs: Array[GPSymbolDef] = [],
		gpStd: GPProjectStandard = null) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	var gpCfg: Dictionary = gpStd.gpValidationConfig() if gpStd != null \
		else GPDRCConfig.gpDefaults()
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null or gpSheet.gpGraph == null:
			continue
		# Per-sheet rules, with tags handed to the project audit (no duplicate tag rows).
		gpOut.append_array(gpRunSheet(gpSheet.gpGraph, gpSheet, gpDefs, gpStd,
			{"skip_tags": true}))
	# Project tag audit (ADR-36 C).
	for gpF in GPTagAudit.gpRun(gpSheets, gpDefs, gpStd):
		if gpF != null and _gpAdoptProject(gpF, gpCfg, gpSheets):
			gpOut.append(gpF)
	# Sheet-number uniqueness is a project property.
	_gpSheetNumberDuplicates(gpSheets, gpCfg, gpOut)
	GPDRCConfig.gpApplyWaivers(gpOut, gpCfg)
	return _gpFinish(gpOut)


# Adopt one finding from a snapshot-backed rule: stable uid, sheet id, check id, config severity,
# registry fix hint. Waivers are applied once at the end.
# 接纳一条快照规则发现：稳定 uid、图纸 id、检查号、配置级别、注册表修复提示。豁免最后统一应用。
static func _gpAdopt(gpSnap: GPDrcSnapshot, gpCfg: Dictionary, gpF: GPFinding) -> bool:
	if gpF.gpCheckId == "":
		gpF.gpCheckId = gpF.gpRuleId
	if gpF.gpSheetId == "":
		gpF.gpSheetId = gpSnap.sheet_id
	if gpF.gpEntityUid == "":
		if gpF.gpNodeId != "":
			gpF.gpEntityUid = gpSnap.gpNodeUid(gpF.gpNodeId)
		elif gpF.gpEdgeId != "":
			gpF.gpEntityUid = gpSnap.gpEdgeUid(gpF.gpEdgeId)
		elif gpF.gpShapeIdx >= 0:
			gpF.gpEntityUid = "shape-%d" % gpF.gpShapeIdx
	if not GPDRCConfig.gpEnabled(gpCfg, gpF.gpCheckId):
		return false
	gpF.gpSeverity = GPDRCConfig.gpSeverity(gpCfg, gpF.gpCheckId,
		GPDRCConfig.gpSeverity(gpCfg, gpF.gpRuleId, gpF.gpSeverity))
	if gpF.gpFixHint == "":
		var gpRule: GPDrcRule = GPDrcRegistry.gpById(gpF.gpCheckId)
		if gpRule == null:
			gpRule = GPDrcRegistry.gpById(gpF.gpRuleId)
		if gpRule != null:
			gpF.gpFixHint = gpRule.gpFixHint
	return true


# Adopt a project-audit finding (no snapshot): resolve its sheet by node id when possible.
# 接纳工程审计发现（无快照）：尽量按节点 id 找回图纸。
static func _gpAdoptProject(gpF: GPFinding, gpCfg: Dictionary, gpSheets: Array) -> bool:
	if gpF.gpCheckId == "":
		gpF.gpCheckId = gpF.gpRuleId
	if gpF.gpSheetId == "":
		for gpSheetRaw in gpSheets:
			var gpSheet: GPSheet = gpSheetRaw as GPSheet
			if gpSheet == null or gpSheet.gpGraph == null:
				continue
			if gpF.gpNodeId != "":
				var gpN: GPPIDNode = gpSheet.gpGraph.gpGetNode(gpF.gpNodeId)
				if gpN != null:
					gpF.gpSheetId = gpSheet.gpId
					gpF.gpEntityUid = gpN.gpRefId()
					break
			if gpF.gpEdgeId != "":
				var gpE: GPPIDEdge = gpSheet.gpGraph.gpGetEdge(gpF.gpEdgeId)
				if gpE != null:
					gpF.gpSheetId = gpSheet.gpId
					gpF.gpEntityUid = gpE.gpInstanceId
					break
	if not GPDRCConfig.gpEnabled(gpCfg, gpF.gpCheckId):
		return false
	gpF.gpSeverity = GPDRCConfig.gpSeverity(gpCfg, gpF.gpRuleId, gpF.gpSeverity)
	return true


# Project-level sheet number uniqueness.
# 工程级图纸编号唯一性。
static func _gpSheetNumberDuplicates(gpSheets: Array, _gpCfg: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	var gpSeen: Dictionary = {}
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null:
			continue
		var gpNo: String = gpSheet.gpNumber.strip_edges()
		if gpNo == "":
			continue
		if gpSeen.has(gpNo):
			gpOut.append(GPFinding.gpMake("drc.doc", GPFinding.GP_ERROR,
				"drc.sheet_number_duplicate", [gpNo, gpSheet.gpName])
				.gpAs("drc.doc.sheet_number_duplicate", "drc.fix.set_number")
				.gpOnEntity(gpSheet.gpId, gpSheet.gpId))
		else:
			gpSeen[gpNo] = gpSheet.gpId


# Stable sort + dedupe. One finding per (check, entity, message, params).
# 稳定排序 + 去重。每（检查号、对象、消息、参数）只保留一条。
static func _gpFinish(gpFindings: Array[GPFinding]) -> Array[GPFinding]:
	var gpUnique: Dictionary = {}
	var gpOut: Array[GPFinding] = []
	for gpF in gpFindings:
		if gpF == null:
			continue
		var gpKey: String = "%s|%s|%s|%s" % [gpF.gpCheckId, gpF.gpEntityUid,
			gpF.gpMessageKey, str(gpF.gpParams)]
		if gpUnique.has(gpKey):
			continue
		gpUnique[gpKey] = true
		gpOut.append(gpF)
	gpOut.sort_custom(_gpSortLess)
	return gpOut


static func _gpSortLess(gpA: GPFinding, gpB: GPFinding) -> bool:
	if gpA.gpRuleId != gpB.gpRuleId:
		return gpA.gpRuleId < gpB.gpRuleId
	if gpA.gpCheckId != gpB.gpCheckId:
		return gpA.gpCheckId < gpB.gpCheckId
	if gpA.gpWorld != gpB.gpWorld:
		if gpA.gpWorld == Vector2.INF:
			return false
		if gpB.gpWorld == Vector2.INF:
			return true
		if gpA.gpWorld.x != gpB.gpWorld.x:
			return gpA.gpWorld.x < gpB.gpWorld.x
		return gpA.gpWorld.y < gpB.gpWorld.y
	if gpA.gpNodeId != gpB.gpNodeId:
		return gpA.gpNodeId < gpB.gpNodeId
	return gpA.gpEdgeId < gpB.gpEdgeId


# Counts used by the panel and status line (waived excluded, counted separately).
# 面板与状态行使用的计数（排除已豁免，单独统计）。
static func gpCount(gpFindings: Array[GPFinding], gpSeverity: String) -> int:
	return GPDRCConfig.gpCountActive(gpFindings, gpSeverity)


static func gpCountWaived(gpFindings: Array[GPFinding]) -> int:
	return GPDRCConfig.gpCountWaived(gpFindings)


# Whether any active (non-waived) error blocks a delivery / export gate.
# 是否存在未豁免的 error 阻断交付 / 导出闸门。
static func gpHasBlocking(gpFindings: Array[GPFinding]) -> bool:
	for gpF in gpFindings:
		if gpF != null and gpF.gpBlocksDelivery():
			return true
	return false
