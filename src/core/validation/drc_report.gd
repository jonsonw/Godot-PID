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
	return I18n.gpTr("drc.summary") % [
		GPRulePack.gpCount(gpFindings, GPFinding.GP_ERROR),
		GPRulePack.gpCount(gpFindings, GPFinding.GP_WARNING),
		GPRulePack.gpCount(gpFindings, GPFinding.GP_INFO),
	]


# Human-readable text report: a header, the summary, then one line per finding grouped by
# severity. Errors first, because a report that buries the blockers is a report nobody reads.
# 人类可读的文本报告：抬头、摘要，然后按严重度分组的逐条行。**error 在前** ——
# 把拦路问题埋在下面的报告没人会读。
static func gpToText(gpFindings: Array[GPFinding]) -> String:
	var gpOut: Array[String] = []
	gpOut.append(I18n.gpTr("drc.report_title"))
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
# Returns the written path, or "" on failure. The caller shows the path, so the user never has to
# guess where the file went.
# 返回写入路径，失败返回空串。调用方把路径显示出来，用户不必猜文件去哪了。
static func gpWrite(gpFindings: Array[GPFinding], gpDir: String, gpBaseName: String,
		gpAsCsv: bool) -> String:
	if gpDir == "":
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(gpDir))
	var gpExt: String = ".csv" if gpAsCsv else ".txt"
	var gpPath: String = gpDir.path_join(gpBaseName + gpExt)
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.WRITE)
	if gpF == null:
		return ""
	gpF.store_string(gpToCsv(gpFindings) if gpAsCsv else gpToText(gpFindings))
	gpF.close()
	return gpPath


# Quote one CSV field when it contains a comma, a quote or a newline.
# 当字段含逗号、引号或换行时加引号。
static func _csv(gpV: String) -> String:
	if gpV.contains(",") or gpV.contains("\"") or gpV.contains("\n"):
		return "\"" + gpV.replace("\"", "\"\"") + "\""
	return gpV
