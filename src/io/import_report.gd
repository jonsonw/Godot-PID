class_name GPImportReport
extends RefCounted

# Structured outcome of an import: what was read, what was repaired, what was refused.
# 导入的结构化结果：读了什么、修了什么、拒了什么。
# WHY A REPORT AT ALL / 为何需要报告：
# an import that "mostly worked" is the dangerous kind. Silent fixes leave the engineer
# believing the drawing is complete when a valve silently lost its port mapping. Every
# automatic decision therefore lands here, and the host shows it to the user.
# 「大体成功」的导入才是最危险的一类。静默修正会让工程师以为图纸完整，
# 而某个阀门其实已经悄悄丢掉了端口映射。故每个自动决策都落到这里，由宿主展示给用户。
# Validation NEVER aborts an import (see 持久化实现方案 §9.2): data loss is the one outcome
# that must be impossible, so questionable entries are kept and reported, not dropped.
# 校验**永不**中断导入（见「持久化实现方案」§9.2）：数据丢失是唯一必须不可能发生的
# 结果，故有问题的条目一律保留并报告，而非丢弃。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

const GP_ERROR: String = "error"
const GP_WARNING: String = "warning"
const GP_INFO: String = "info"

# One entry per decision: {level, code, detail}.
# 每个决策一个条目：{level, code, detail}。
var gpEntries: Array[Dictionary] = []

# What the imported archive contained: nodes / edges / shapes / packs / sheets.
# 导入的存档含有什么：nodes / edges / shapes / packs / sheets。
var gpStats: Dictionary = {"nodes": 0, "edges": 0, "shapes": 0, "packs": 0, "sheets": 0}

# Source path, so the report can be re-read later. / 源路径，便于日后重读报告。
var gpSourcePath: String = ""


# Record one decision. / 记录一个决策。
func gpAdd(gpLevel: String, gpCode: String, gpDetail: String = "") -> void:
	gpEntries.append({"level": gpLevel, "code": gpCode, "detail": gpDetail})


func gpAddError(gpCode: String, gpDetail: String = "") -> void:
	gpAdd(GP_ERROR, gpCode, gpDetail)


func gpAddWarning(gpCode: String, gpDetail: String = "") -> void:
	gpAdd(GP_WARNING, gpCode, gpDetail)


func gpAddInfo(gpCode: String, gpDetail: String = "") -> void:
	gpAdd(GP_INFO, gpCode, gpDetail)


# How many entries sit at gpLevel. / 处于 gpLevel 级别的条目数。
func gpCountOf(gpLevel: String) -> int:
	var gpN: int = 0
	for gpE in gpEntries:
		if str((gpE as Dictionary).get("level", "")) == gpLevel:
			gpN += 1
	return gpN


# True when at least one entry is an error — the host uses this to pick a dialog tone,
# never to refuse the import.
# 至少有一个 error 条目时为真 —— 宿主用它选择对话框语气，绝不用来拒绝导入。
func gpHasErrors() -> bool:
	return gpCountOf(GP_ERROR) > 0


# Human-readable lines, capped so a pathological file cannot flood the UI.
# 人类可读的行，带上限，使病态文件无法刷屏 UI。
func gpLines(gpMax: int = 50) -> Array[String]:
	var gpOut: Array[String] = []
	var gpN: int = 0
	for gpE in gpEntries:
		if gpN >= gpMax:
			gpOut.append("... (" + str(gpEntries.size() - gpMax) + " more)")
			break
		var gpD: Dictionary = gpE as Dictionary
		var gpLine: String = "[" + str(gpD.get("level", "")) + "] " + str(gpD.get("code", ""))
		var gpDetail: String = str(gpD.get("detail", ""))
		if not gpDetail.is_empty():
			gpLine += " — " + gpDetail
		gpOut.append(gpLine)
		gpN += 1
	return gpOut


# One-line summary for the status bar. / 状态栏用的一行摘要。
func gpSummary() -> String:
	return "nodes=" + str(gpStats.get("nodes", 0)) \
		+ " edges=" + str(gpStats.get("edges", 0)) \
		+ " shapes=" + str(gpStats.get("shapes", 0)) \
		+ " packs=" + str(gpStats.get("packs", 0)) \
		+ " errors=" + str(gpCountOf(GP_ERROR)) \
		+ " warnings=" + str(gpCountOf(GP_WARNING))


# Machine-readable form (for tests and a future report panel).
# 机器可读形式（供测试与将来的报告面板使用）。
func gpToDict() -> Dictionary:
	return {
		"source": gpSourcePath,
		"stats": gpStats.duplicate(true),
		"errors": gpCountOf(GP_ERROR),
		"warnings": gpCountOf(GP_WARNING),
		"infos": gpCountOf(GP_INFO),
		"entries": gpEntries.duplicate(true),
	}
