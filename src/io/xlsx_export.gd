class_name GPXlsxExport
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Orchestrates one export run: four lists, four template choices, four output files.
# It owns the per-file failure boundary: one bad template must not prevent the other lists.
# 编排一次导出：四类清单、四套模板、四个输出文件。它负责单文件失败边界：一个坏模板不能
# 阻止其它清单。
#
# NOT IN GP_EXPORTERS / 不进导出注册表：
# this is a multi-file, per-list-template WORKFLOW, not a single-file format. See ADR-32 D9.
# 这是多文件、每类模板不同的**工作流**，不是单文件格式。见 ADR-32 D9。
#
# Coding rule: every variable declares its type explicitly; every function is static.
# 编码规范：所有变量显式声明类型；函数全部静态。

const GP_DEFAULT_TEMPLATE_DIR: String = "res://assets/templates"
const GP_DEFAULT_PREFIX: String = "G-PID"


# The project standard of a sheet list (all sheets share one object in memory).
# 一组图纸的项目标准（内存里所有图纸共享同一个对象）。
static func _gpStdOfSheets(gpSheets: Array) -> GPProjectStandard:
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet != null and gpSheet.gpGraph != null:
			return gpSheet.gpGraph.gpStandard
	return null


# Export the requested lists. Returns GPIOResult with payload:
#   {"files": [{list, ok, path, rows, skipped, issues, error}], "counts": {...}, "issues": [...]}
# 导出请求的清单。返回 payload 见上。
static func gpExportLists(gpSheets: Array, gpDefs: Array[GPSymbolDef],
		gpOptions: Dictionary) -> GPIOResult:
	var gpLocale: String = str(gpOptions.get("locale", "zh"))
	var gpTypeLabels: Dictionary = gpOptions.get("type_labels", {}) as Dictionary
	# ADR-36 C: the EXPORT GATE. A list is a deliverable — shipping one with duplicate or
	# non-compliant tags is worse than refusing, because the receiver cannot tell which row is
	# which. The same audit the DRC runs, run here, so the two can never disagree.
	# ADR-36 C：**导出闸门**。清单是交付物 —— 带着重复或不合规位号发出去，比拒绝更糟，因为接收方
	# 分不清哪一行是哪一台。这里跑与 DRC 同一条审计，故两者不可能给出不同结论。
	var gpAudit: Array[GPFinding] = GPTagAudit.gpRun(gpSheets, gpDefs,
		_gpStdOfSheets(gpSheets))
	if GPTagAudit.gpHasBlocking(gpAudit):
		return GPIOResult.gpFailure("xlsx.blocked_tag_duplicate",
			"xlsx.blocked_tag_duplicate", GPTagAudit.gpBlockingSummary(gpAudit))
	var gpModel: Dictionary = GPDeliverableModel.gpBuildAll(gpSheets, gpDefs,
		{"locale": gpLocale, "type_labels": gpTypeLabels})
	var gpCounts: Dictionary = {}
	for gpListId in GPDeliverableFields.gpListIds():
		var gpRes: Dictionary = gpModel.get(gpListId, {}) as Dictionary
		gpCounts[gpListId] = int(gpRes.get("count", 0))
	var gpLists: Array = gpOptions.get("lists", GPDeliverableFields.gpListIds()) as Array
	var gpTemplates: Dictionary = gpOptions.get("templates", {}) as Dictionary
	var gpOutputDir: String = str(gpOptions.get("output_dir", ""))
	if gpOutputDir == "":
		return GPIOResult.gpFailure("xlsx.no_output_dir", "xlsx.err_output_dir")
	if not DirAccess.dir_exists_absolute(gpOutputDir):
		var gpMkErr: int = DirAccess.make_dir_recursive_absolute(gpOutputDir)
		if gpMkErr != OK:
			return GPIOResult.gpFailure("xlsx.output_dir_failed", "xlsx.err_output_dir", gpOutputDir)
	var gpFiles: Array = []
	var gpAllIssues: Array = []
	# Non-blocking audit findings (stale line numbers, unmapped symbols) travel with the
	# result, so the export dialog can list them next to the model's own issues.
	# 非阻断的审计发现（线号陈旧、图元未分类）随结果一起返回，使导出对话框把它们与模型自身的
	# 问题并列显示。
	for gpF in gpAudit:
		if gpF.gpSeverity == GPFinding.GP_WARNING:
			gpAllIssues.append({"code": gpF.gpMessageKey, "severity": "warning",
				"params": gpF.gpParams})
	var gpWritten: int = 0
	var gpFailed: int = 0
	for gpListRaw in gpLists:
		var gpList: String = str(gpListRaw)
		if not GPDeliverableFields.gpIsKnownList(gpList):
			continue
		var gpListRes: Dictionary = gpModel.get(gpList, {}) as Dictionary
		var gpRows: Array = gpListRes.get("rows", []) as Array
		var gpModelIssues: Array = gpListRes.get("issues", []) as Array
		gpAllIssues.append_array(gpModelIssues)
		if gpRows.is_empty() and not bool(gpOptions.get("include_empty", false)):
			gpFiles.append({"list": gpList, "ok": true, "skipped": true, "path": "",
				"rows": 0, "issues": gpModelIssues})
			continue
		var gpTemplatePath: String = str(gpTemplates.get(gpList, ""))
		if gpTemplatePath == "":
			gpTemplatePath = gpDefaultTemplatePath(gpList)
		var gpLoaded: Dictionary = GPXlsxTemplate.gpLoad(gpTemplatePath)
		if not bool(gpLoaded.get("ok", false)):
			gpFailed += 1
			gpFiles.append({"list": gpList, "ok": false, "path": "", "rows": gpRows.size(),
				"error": str(gpLoaded.get("error", "template")), "issues": gpModelIssues})
			continue
		var gpBinding: Dictionary = GPXlsxTemplate.gpBind(gpLoaded["entries"] as Dictionary,
			gpList, gpDefs, {"locale": gpLocale,
				"overrides": (gpOptions.get("overrides", {}) as Dictionary).get(gpList, {})})
		if not bool(gpBinding.get("ok", false)):
			gpFailed += 1
			gpFiles.append({"list": gpList, "ok": false, "path": "", "rows": gpRows.size(),
				"error": str(gpBinding.get("error", "bind")), "issues": gpModelIssues})
			continue
		var gpContext: Dictionary = GPXlsxFiller.gpTokenContext(gpSheets, gpCounts, gpLocale,
			gpList, str(gpBinding.get("sheet_name", "")), 1, gpSheets.size())
		var gpFill: Dictionary = GPXlsxFiller.gpFill(gpLoaded["entries"] as Dictionary,
			gpBinding, gpRows, gpContext, gpList)
		if not bool(gpFill.get("ok", false)):
			gpFailed += 1
			gpFiles.append({"list": gpList, "ok": false, "path": "", "rows": gpRows.size(),
				"error": str(gpFill.get("error", "fill")), "issues": gpModelIssues})
			continue
		var gpFillIssues: Array = gpFill.get("issues", []) as Array
		var gpIssues: Array = gpModelIssues.duplicate()
		gpIssues.append_array(gpFillIssues)
		var gpOutPath: String = gpOutputPath(gpOptions, gpList, gpLocale)
		var gpWrite: Dictionary = _gpWriteAtomic(gpOutPath, gpFill["entries"] as Dictionary)
		if not bool(gpWrite.get("ok", false)):
			gpFailed += 1
			gpFiles.append({"list": gpList, "ok": false, "path": gpOutPath,
				"rows": gpRows.size(), "error": str(gpWrite.get("error", "write")),
				"issues": gpIssues})
			continue
		gpWritten += 1
		gpFiles.append({"list": gpList, "ok": true, "skipped": false, "path": gpOutPath,
			"rows": gpRows.size(), "issues": gpIssues})
		gpAllIssues.append_array(gpFillIssues)
	var gpPayload: Dictionary = {
		"files": gpFiles,
		"counts": gpCounts,
		"issues": gpAllIssues,
		"written": gpWritten,
		"failed": gpFailed,
	}
	if gpWritten == 0:
		return GPIOResult.gpFailure("xlsx.no_files", "xlsx.err_no_files", gpOutputDir)
	return GPIOResult.gpSuccessWith(gpPayload, "status.xlsx_exported", gpOutputDir)


# Default template path for one list. / 某清单的默认模板路径。
static func gpDefaultTemplatePath(gpList: String) -> String:
	return GP_DEFAULT_TEMPLATE_DIR.path_join("gp_list_%s_default.xlsx" % gpList)


# Suggested output path. Prefix/list/date are sanitised for cross-platform filenames.
# 建议输出路径。前缀/清单/日期按跨平台文件名净化。
static func gpOutputPath(gpOptions: Dictionary, gpList: String, gpLocale: String) -> String:
	var gpDir: String = str(gpOptions.get("output_dir", ""))
	var gpPrefix: String = str(gpOptions.get("name_prefix", ""))
	if gpPrefix.strip_edges() == "":
		gpPrefix = GP_DEFAULT_PREFIX
	var gpDate: String = Time.get_date_string_from_system().replace("-", "")
	var gpName: String = "%s_%s_%s.xlsx" % [
		_safeName(gpPrefix), _safeName(GPDeliverableFields.gpListLabel(gpList, gpLocale)), gpDate]
	return gpDir.path_join(gpName)


# Suggested file name without a directory (for the UI preview). / 不含目录的建议文件名。
static func gpSuggestedFileName(gpOptions: Dictionary, gpList: String, gpLocale: String) -> String:
	return gpOutputPath(gpOptions, gpList, gpLocale).get_file()


static func _safeName(gpText: String) -> String:
	var gpOut: String = gpText.strip_edges()
	for gpBad in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|", "\n", "\r", "\t"]:
		gpOut = gpOut.replace(gpBad, "_")
	if gpOut == "":
		gpOut = "_"
	return gpOut


# Write the built package atomically; keep the template untouched.
# 原子写出构建好的包；模板保持不改。
static func _gpWriteAtomic(gpPath: String, gpEntries: Dictionary) -> Dictionary:
	var gpDir: String = "user://cache"
	if not DirAccess.dir_exists_absolute(gpDir):
		DirAccess.make_dir_recursive_absolute(gpDir)
	var gpTmp: String = gpDir.path_join("gp_xlsx_export_%d.xlsx" % Time.get_ticks_usec())
	var gpErr: int = GPXlsxPackage.gpWriteArchive(gpTmp, gpEntries)
	if gpErr != OK:
		return {"ok": false, "error": "zip:%d" % gpErr}
	var gpBytes: PackedByteArray = FileAccess.get_file_as_bytes(gpTmp)
	DirAccess.remove_absolute(gpTmp)
	if gpBytes.is_empty():
		return {"ok": false, "error": "empty_bytes"}
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteBytesAtomic(gpPath, gpBytes)
	if not gpWrite.gpIsOk():
		return {"ok": false, "error": gpWrite.gpCode}
	return {"ok": true, "path": gpPath}
