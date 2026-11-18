# Copyright 2026 G-PID Contributors. MIT License. See LICENSE.
class_name GPSheetNumbering
extends RefCounted

# Sheet-number authority for CREATION time (W13 user feedback 2026-11-11): a fresh sheet must
# carry a number IMMEDIATELY — before this, gpRenumberSheets only ran from the 编号设置 dialog,
# so every new sheet showed NO number anywhere (tab caption, manager list, preview header)
# until the user re-applied the numbering rules.
# 图纸编号的**创建时**权威（W13 用户反馈 2026-11-11）：新图纸必须**立即**带编号 —— 此前
# gpRenumberSheets 只在「编号设置」对话框里触发，于是每张新图纸在重套编号规则之前，
# 标签标题、管理列表、预览页眉全都没有编号。
#
# WHY A PURE CORE FILE / 为何是纯 core 文件：
# the decision "std template when a standard lives, bare zero-padded sequence otherwise" is
# ONE judgment and must not fork between the editor's tab bar and the manager's panel. Pure
# statics stay headless-testable. Hand-edit survival stays with gpAssignNumber (ADR-38) —
# this file only mints the FIRST number of a sheet's life.
# 「有标准走标准模板、无标准走裸三位序号」是**一个**判断，不得在编辑器标签栏与管理面板
# 之间分家。纯静态保持 headless 可测。手改存活的语义仍归 gpAssignNumber（ADR-38）——
# 本文件只铸造一张图纸**人生的第一枚**编号。
#
# PROJECT-WIDE AUTHORITY (2026-11-18 duplicate-number fix): the caller passes the number set
# gathered from ALL sheets — open AND hidden. A hidden sheet still belongs to the project and
# reserves its number; deriving the next number from "how many tabs are open" re-minted a
# deleted sheet's number after a reload (two tabs both "002 图纸 2").
# **工程级发号权威**（2026-11-18 重号修复）：调用方传入从**全部**图纸（打开+隐藏）收集的已用号。
# 隐藏图纸仍属本工程、仍占用其号；用「当前打开标签数」推导下一号，会在删除重建后重铸已删
# 图纸的号（两个标签都是「002 图纸 2」）。
#
# Coding rule: every variable declares its type explicitly. / 编码规范：所有变量均显式声明类型。

# Mint a sheet number for the 1-based tab sequence: the live standard's template when one is
# adopted, a bare zero-padded sequence otherwise (still a valid, honest number).
# 为 1 起的标签序号铸一枚图纸编号：已采纳标准则走其模板，否则裸三位序号（同样是有效、
# 诚实的编号）。
static func gpNumberFor(gpSeq: int, gpStd: GPProjectStandard) -> String:
	if gpStd != null:
		return gpStd.gpSheetNumberFor(gpSeq)
	return "%03d" % maxi(gpSeq, 1)


# Collect every drawing number in use across OPEN and HIDDEN sheets. The hidden set used to be
# omitted, which let a new sheet collide with one the user had merely closed.
# 收集打开与隐藏图纸的**全部**已用图号。旧实现漏掉隐藏集合，于是新建图纸会撞上一张只是
# 被关闭（而非删除）的图纸。
static func gpUsedNumbers(gpSheets: Array) -> Dictionary:
	var gpOut: Dictionary = {}
	for gpRaw in gpSheets:
		var gpSheet: GPSheet = gpRaw as GPSheet
		if gpSheet == null:
			continue
		var gpNo: String = gpSheet.gpNumber.strip_edges()
		if gpNo != "":
			gpOut[gpNo] = true
	return gpOut


# Last run of decimal digits in a number ("PRJ-002" -> 2, "REV-A" -> 0). A hand-edited
# non-numeric number occupies its slot but does not advance the auto sequence.
# 编号中最后一段连续数字（"PRJ-002" → 2，"REV-A" → 0）。手改的非数字编号占槽位，
# 但不推进自动序号。
static func gpSequenceOf(gpText: String) -> int:
	var gpBest: int = 0
	var gpRun: String = ""
	for gpI in range(gpText.length() + 1):
		var gpCh: String = gpText.substr(gpI, 1)
		if gpCh != "" and gpCh.is_valid_int():
			gpRun += gpCh
		elif gpRun != "":
			gpBest = gpRun.to_int()
			gpRun = ""
	return gpBest


# Next number for a NEW sheet: one past the highest sequence currently in use. Deleted sheets'
# numbers are NOT recycled — reusing a drawing number breaks document traceability.
# 新图纸取号：当前最大序号 +1。已删图纸的号**不回收** —— 复用图号会破坏文档可追溯性。
static func gpNextNumber(gpUsed: Dictionary, gpStd: GPProjectStandard) -> String:
	var gpMax: int = 0
	for gpNo in gpUsed.keys():
		gpMax = maxi(gpMax, gpSequenceOf(str(gpNo)))
	var gpSeq: int = gpMax + 1
	var gpOut: String = gpNumberFor(gpSeq, gpStd)
	var gpGuard: int = 0
	while gpUsed.has(gpOut) and gpGuard < 10000:
		gpSeq += 1
		gpGuard += 1
		gpOut = gpNumberFor(gpSeq, gpStd)
	return gpOut


# Next number for a RENUMBER pass: the smallest free slot, so 001/002 stay 001/002. Slots held
# by hand-edited numbers or by hidden sheets are already in gpUsed and are skipped.
# 重编取号：最小空位，使 001/002 重编后仍是 001/002。手改号与隐藏图纸的槽位已在 gpUsed 中，
# 自然被避开。
static func gpNextFreeNumber(gpUsed: Dictionary, gpStd: GPProjectStandard) -> String:
	var gpSeq: int = 1
	while gpSeq <= 100000:
		var gpOut: String = gpNumberFor(gpSeq, gpStd)
		if not gpUsed.has(gpOut):
			return gpOut
		gpSeq += 1
	return gpNumberFor(1, gpStd)


# Mirrors GPSheet.gpAssignNumber's overwrite rule: an auto number may be regenerated while the
# title block still shows the same value (or is empty); a hand-edited block is reserved.
# 与 GPSheet.gpAssignNumber 的覆盖判据同形：图签仍是当前号（或为空）时该号可重编；
# 手改过图签的号保留。
static func gpIsAutoNumbered(gpSheet: GPSheet) -> bool:
	if gpSheet == null:
		return false
	var gpBlock: String = gpSheet.gpTitleValue("drawing_no").strip_edges()
	return gpBlock == "" or gpBlock == gpSheet.gpNumber.strip_edges()


# Plan a whole-project renumber in one pure call. gpSheets follows gpToSheets()'s order:
# the first gpOpenCount entries are OPEN tabs, the rest are HIDDEN sheets. Hidden sheets always
# reserve their number; hand-edited open sheets reserve theirs; the remaining open sheets get
# the smallest free slots. Returns {sheet_id: new_number} for sheets that must change.
# 一次纯调用规划全工程重编。gpSheets 遵循 gpToSheets() 的顺序：前 gpOpenCount 项是**打开**
# 标签，其余是**隐藏**图纸。隐藏图纸与手改号的打开图纸一律占号，其余打开图纸取最小空位。
# 返回 {sheet_id: 新号}，只含需要改号的图纸。
static func gpPlanRenumber(gpSheets: Array, gpOpenCount: int,
		gpStd: GPProjectStandard) -> Dictionary:
	var gpReserved: Dictionary = {}
	var gpTotal: int = mini(gpOpenCount, gpSheets.size())
	for gpI in range(gpTotal, gpSheets.size()):
		var gpHidden: GPSheet = gpSheets[gpI] as GPSheet
		if gpHidden != null and not gpHidden.gpNumber.strip_edges().is_empty():
			gpReserved[gpHidden.gpNumber.strip_edges()] = true
	for gpI in range(gpTotal):
		var gpManual: GPSheet = gpSheets[gpI] as GPSheet
		if gpManual != null and not gpManual.gpNumber.strip_edges().is_empty() \
			and not gpIsAutoNumbered(gpManual):
			gpReserved[gpManual.gpNumber.strip_edges()] = true
	var gpPlan: Dictionary = {}
	for gpI in range(gpTotal):
		var gpSheet: GPSheet = gpSheets[gpI] as GPSheet
		if gpSheet == null or not gpIsAutoNumbered(gpSheet):
			continue
		var gpNo: String = gpNextFreeNumber(gpReserved, gpStd)
		gpPlan[gpSheet.gpId] = gpNo
		gpReserved[gpNo] = true
	return gpPlan
