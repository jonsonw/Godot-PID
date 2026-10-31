class_name GPExportGate
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# The delivery gate (ADR-39 D5 / E05): run the SAME engine the panel runs, and refuse a delivery
# when an un-waived error exists. Warnings pass but are listed; infos never block.
# 交付闸门（ADR-39 D5 / E05）：跑与面板**同一套**引擎；存在未豁免 error 时拒绝交付。
# warning 放行但列入报告；info 永不阻断。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Run the gate over a set of sheets.
# 对一组图纸跑闸门。
# Returns {"findings": Array[GPFinding], "blocked": bool, "errors": int, "warnings": int,
#          "infos": int, "waived": int, "summary": String}.
# 返回上述字典。
static func gpCheck(gpSheets: Array, gpDefs: Array[GPSymbolDef] = [],
		gpStd: GPProjectStandard = null) -> Dictionary:
	var gpFindings: Array[GPFinding] = GPDrcEngine.gpRunProject(gpSheets, gpDefs, gpStd)
	var gpErrors: int = GPDrcEngine.gpCount(gpFindings, GPFinding.GP_ERROR)
	var gpWarnings: int = GPDrcEngine.gpCount(gpFindings, GPFinding.GP_WARNING)
	var gpInfos: int = GPDrcEngine.gpCount(gpFindings, GPFinding.GP_INFO)
	var gpWaived: int = GPDrcEngine.gpCountWaived(gpFindings)
	var gpStdUsed: GPProjectStandard = gpStd
	if gpStdUsed == null:
		for gpSheetRaw in gpSheets:
			var gpSheet: GPSheet = gpSheetRaw as GPSheet
			if gpSheet != null and gpSheet.gpGraph != null and gpSheet.gpGraph.gpStandard != null:
				gpStdUsed = gpSheet.gpGraph.gpStandard
				break
	return {
		"findings": gpFindings,
		"blocked": gpErrors > 0,
		"errors": gpErrors,
		"warnings": gpWarnings,
		"infos": gpInfos,
		"waived": gpWaived,
		"doc_hash": gpDocHash(gpSheets),
		"rules_hash": gpRulesHash(gpStdUsed),
		"summary": I18n.gpTr("drc.summary") % [gpErrors, gpWarnings, gpInfos],
	}


# Human-readable refusal line for a dialog / status bar.
# 供对话框 / 状态栏使用的拒绝文案。
static func gpBlockerText(gpGate: Dictionary) -> String:
	return I18n.gpTr("drc.export_blocked") % int(gpGate.get("errors", 0))


# Deterministic hash of the drawing data (sheets / graphs / title blocks). Same project →
# same hash; any edit → a different hash. This is what makes a report re-computable.
# 图纸数据的确定性哈希（图纸 / 图 / 标题栏）。同工程 → 同哈希；任何编辑 → 不同哈希。
# 这正是报告可复算的前提。
static func gpDocHash(gpSheets: Array) -> String:
	var gpParts: Array[String] = []
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null:
			continue
		gpParts.append(gpSheet.gpId + "|" + gpSheet.gpNumber + "|" + gpSheet.gpName)
		if gpSheet.gpGraph != null:
			gpParts.append(JSON.stringify(gpSheet.gpGraph.gpToDict()))
	return "\n".join(gpParts).sha256_text()


# Deterministic hash of the rule set + project config. Two runs with the same rules/config
# produce the same hash; changing a severity or threshold changes it.
# 规则集 + 工程配置的确定性哈希。同规则/配置两次运行同哈希；改级别或阈值即变。
static func gpRulesHash(gpStd: GPProjectStandard = null) -> String:
	var gpParts: Array[String] = []
	for gpR in GPDrcRegistry.gpAll():
		gpParts.append("%s|%s|%s|%d|%s" % [gpR.gpId, gpR.gpFamily,
			gpR.gpDefaultSeverity, gpR.gpPhase, gpR.gpRequires])
	if gpStd != null:
		var gpCfg: Dictionary = gpStd.gpValidationConfig()
		gpParts.append(JSON.stringify(gpCfg.get("rules", {})))
		gpParts.append(JSON.stringify(gpCfg.get("thresholds", {})))
		gpParts.append(JSON.stringify(gpCfg.get("policy", {})))
	return "\n".join(gpParts).sha256_text()
