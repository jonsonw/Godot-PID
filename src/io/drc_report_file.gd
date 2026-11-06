class_name GPDRCReportFile
extends RefCounted
# Copyright © 2026 Jonson Wang
# Disk writer for DRC reports. The RENDERING stays in core (GPDRCReport: text / CSV / JSON string
# builders); this class only puts those strings on disk.
# DRC 报告的写盘器。**渲染**仍属 core（GPDRCReport：文本 / CSV / JSON 字符串构建器）；
# 本类只负责把那些字符串落到磁盘。
#
# WHY THE SPLIT / 为何要拆：
# GPDRCReport's header promises "pure string builders: no file, no dialog, no panel", yet two
# functions in it opened DirAccess and FileAccess. The promise was the right design and the code
# did not keep it. Moving the write out makes the header true and lets the byte-for-byte content
# be asserted without a disk (see gp_test_drc_report.gd).
# GPDRCReport 的文件头承诺"纯字符串构建器：不碰文件、不碰对话框、不碰面板"，但其中两个函数却开了
# DirAccess 与 FileAccess。承诺才是正确设计，代码没守住。把写盘移出后文件头重新成立，且内容可逐字节
# 断言而无需磁盘（见 gp_test_drc_report.gd）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


# Write the human-readable text / CSV report. Returns the written path, or "" on failure.
# 写出人类可读的文本 / CSV 报告。返回写入路径，失败返回 ""。
# The caller shows the path, so the user never has to guess where the file went.
# 调用方把路径显示出来，用户不必猜文件去哪了。
static func gpWrite(gpFindings: Array[GPFinding], gpDir: String, gpBaseName: String,
		gpAsCsv: bool) -> String:
	if gpDir == "":
		return ""
	var gpExt: String = ".csv" if gpAsCsv else ".txt"
	var gpPath: String = gpDir.path_join(gpBaseName + gpExt)
	var gpBody: String = GPDRCReport.gpToCsv(gpFindings) if gpAsCsv else GPDRCReport.gpToText(gpFindings)
	if not GPFileGateway.gpWriteText(gpPath, gpBody):
		return ""
	return gpPath


# Write the machine-readable JSON report (ADR-39 D5). Returns the written path, or "" on failure.
# 写出机器可读的 JSON 报告（ADR-39 D5）。返回写入路径，失败返回 ""。
static func gpWriteJson(gpFindings: Array[GPFinding], gpDir: String, gpBaseName: String,
		gpMeta: Dictionary = {}) -> String:
	if gpDir == "":
		return ""
	var gpPath: String = gpDir.path_join(gpBaseName + ".json")
	if not GPFileGateway.gpWriteText(gpPath, GPDRCReport.gpToJson(gpFindings, gpMeta)):
		return ""
	return gpPath
