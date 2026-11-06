class_name GPDRCReport
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Text / CSV rendering of a finding list (B2). Pure string builders: no file, no dialog, no panel.
# 发现列表的文本 / CSV 渲染（B2）。纯字符串构建器：不碰文件、不碰对话框、不碰面板。
#
# Why the renderer is separate from the writer / 为何渲染与写文件分开：
# the acceptance for a report is "the file says what the panel says". Keeping the string builder
# pure means that claim can be asserted without touching the disk, and the disk step becomes a
# three-line function that cannot change the content.
# 报告的验收是「文件说的与面板说的一致」。让字符串构建器保持纯，就能在不碰磁盘的情况下断言该声明，
# 而写盘那一步缩成三行、改不了内容。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# CSV header for the finding export (stable, so downstream spreadsheets can pin it).
# 发现导出的 CSV 表头（稳定，下游表格可据此固定列）。
const GP_CSV_HEADER: String = "severity,rule,node,edge,shape_idx,x,y,message"


# One-line summary: "3 errors / 2 warnings / 1 info".
# 单行摘要："3 errors / 2 warnings / 1 info"。
static func gpSummary(gpFindings: Array[GPFinding]) -> String:
	var gpText: String = GPLocalizer.gpTr("drc.summary") % [
		GPDRCConfig.gpCountActive(gpFindings, GPFinding.GP_ERROR),
		GPDRCConfig.gpCountActive(gpFindings, GPFinding.GP_WARNING),
		GPDRCConfig.gpCountActive(gpFindings, GPFinding.GP_INFO),
	]
	var gpWaived: int = GPDRCConfig.gpCountWaived(gpFindings)
	if gpWaived > 0:
		gpText += " · " + (GPLocalizer.gpTr("drc.summary_waived") % gpWaived)
	return gpText


# Human-readable text report: a header, the summary, then one line per finding grouped by
# severity. Errors first, because a report that buries the blockers is a report nobody reads.
# 人类可读的文本报告：抬头、摘要，然后按严重度分组的逐条行。**error 在前** ——
# 把拦路问题埋在下面的报告没人会读。
static func gpToText(gpFindings: Array[GPFinding]) -> String:
	var gpOut: Array[String] = []
	gpOut.append(GPLocalizer.gpTr("drc.report_title"))
	gpOut.append(gpSummary(gpFindings))
	for gpSev in [GPFinding.GP_ERROR, GPFinding.GP_WARNING, GPFinding.GP_INFO]:
		var gpRows: Array[GPFinding] = []
		for gpF in gpFindings:
			if gpF.gpSeverity == gpSev:
				gpRows.append(gpF)
		if gpRows.is_empty():
			continue
		gpOut.append("")
		gpOut.append("[%s]" % gpSev)
		for gpF in gpRows:
			gpOut.append("  - " + gpF.gpText() + "  (" + gpF.gpRuleId + ")")
	return "\n".join(gpOut) + "\n"


# CSV report, one row per finding. The message is the LOCALIZED text (a report is read by people),
# while `rule` stays the stable id (a report is also fed to tools).
# CSV 报告，每条发现一行。message 是**本地化**文字（报告给人读），而 `rule` 保持稳定 id
#（报告同时也喂给工具）。
static func gpToCsv(gpFindings: Array[GPFinding]) -> String:
	var gpLines: Array[String] = [GP_CSV_HEADER]
	for gpF in gpFindings:
		var gpX: String = "" if gpF.gpWorld == Vector2.INF else String.num(gpF.gpWorld.x, 2)
		var gpY: String = "" if gpF.gpWorld == Vector2.INF else String.num(gpF.gpWorld.y, 2)
		gpLines.append(",".join([
			_csv(gpF.gpSeverity), _csv(gpF.gpRuleId), _csv(gpF.gpNodeId), _csv(gpF.gpEdgeId),
			str(gpF.gpShapeIdx), gpX, gpY, _csv(gpF.gpText()),
		]))
	return "\n".join(gpLines) + "\n"


# Write a report next to the project (or under user:// when there is no project path).
# 把报告写到工程旁边（无工程路径时写 user://）。
# MOVED: the disk step is GPDRCReportFile in the io layer (see the note at the top of this file).
# Here only the string builders live, so "pure" is a fact rather than an aspiration.
# 已移出：写盘一步改为 io 层的 GPDRCReportFile（见本文件顶部说明）。此处只留字符串构建器，
# 「纯」从愿景变成事实。


# Quote one CSV field when it contains a comma, a quote or a newline.
# 当字段含逗号、引号或换行时加引号。
static func _csv(gpV: String) -> String:
	if gpV.contains(",") or gpV.contains("\"") or gpV.contains("\n"):
		return "\"" + gpV.replace("\"", "\"\"") + "\""
	return gpV


# Machine-readable report (ADR-39 D5). Text / CSV above are renderings of this data; the JSON is
# what the panel, CLI, export gate and AI repair loop all consume.
# 机器可读报告（ADR-39 D5）。上面的文本 / CSV 是它的渲染；JSON 是面板、CLI、导出闸门与 AI 修复
# 回路共同消费的数据。
static func gpToJson(gpFindings: Array[GPFinding], gpMeta: Dictionary = {}) -> String:
	var gpItems: Array = []
	for gpF in gpFindings:
		if gpF != null:
			gpItems.append(gpF.gpToDict())
	var gpOut: Dictionary = {
		"schema": "gpid.drc/1",
		"mode": str(gpMeta.get("mode", "sheet")),
		"doc_hash": str(gpMeta.get("doc_hash", "")),
		"rules_hash": str(gpMeta.get("rules_hash", "")),
		"counts": {
			"error": GPDRCConfig.gpCountActive(gpFindings, GPFinding.GP_ERROR),
			"warning": GPDRCConfig.gpCountActive(gpFindings, GPFinding.GP_WARNING),
			"info": GPDRCConfig.gpCountActive(gpFindings, GPFinding.GP_INFO),
			"waived": GPDRCConfig.gpCountWaived(gpFindings),
		},
		"findings": gpItems,
	}
	return JSON.stringify(gpOut, "\t")


# Write the JSON report and return its path ("" on failure).
# 写出 JSON 报告并返回路径（失败为空串）。
# MOVED to GPDRCReportFile (io) for the same reason as gpWrite above.
# 与上面的 gpWrite 同理，已移到 GPDRCReportFile（io）。
