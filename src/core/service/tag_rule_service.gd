class_name GPTagRuleService
extends RefCounted
# Copyright © 2026 Jonson Wang
# Pure helpers behind the "tag numbering rules" dialog (M9b).
# 「位号编号规则」对话框背后的纯逻辑（M9b）。
#
# Everything here is static and headless-testable: no Node, no I18n autoload, no widget.
# The dialog calls it on every keystroke to re-render the preview, and the renumber command
# calls it to build and apply a plan — the same code path, so what the dialog showed is
# exactly what the command does.
# 这里全是静态且可 headless 测试的：无 Node、无 I18n 自动加载、无控件。
# 对话框每次按键都调它重算预览，重编号命令调它构建并应用方案——同一条代码路径，
# 故对话框所显示的正是命令将要做的事。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# One preview row: what a category would be numbered like right now.
# 一行预览：某类别当前会被编成什么样。
# { "prefix": String, "sample": String, "category": String }
const GP_ROW_PREFIX: String = "prefix"
const GP_ROW_SAMPLE: String = "sample"
const GP_ROW_CATEGORY: String = "category"


# Preview rows for every category present in the library, plus one row per explicit
# override. gpRules is read but never mutated — previewing must not consume numbers.
# 为图元库中出现的每个类别（外加每条显式覆盖）生成预览行。
# 只读 gpRules，绝不改动——预览不得消耗号。
static func gpPreviewRows(gpRules: GPProjectTagRules, gpCount: int = 3) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpRules == null:
		return gpOut
	var gpCats: Array[String] = _gpLibraryCategories()
	for gpCat in gpCats:
		var gpDef: GPSymbolDef = GPSymbolDef.new()
		gpDef.gpId = ""
		gpDef.gpCategory = gpCat
		var gpPrefix: String = gpRules.gpPrefixFor(gpDef)
		var gpSamples: Array[String] = _gpSamples(gpRules, gpDef, gpCount)
		gpOut.append({
			GP_ROW_CATEGORY: gpCat,
			GP_ROW_PREFIX: gpPrefix,
			GP_ROW_SAMPLE: gpSamples[0] if not gpSamples.is_empty() else "",
		})
	return gpOut


# Sequence numbers a rule would mint next, without advancing any mark.
# 某规则接下来会铸造的序号（不推进任何水位线）。
static func _gpSamples(gpRules: GPProjectTagRules, gpDef: GPSymbolDef,
		gpCount: int) -> Array[String]:
	var gpRule: GPTagRule = gpRules.gpRuleFor(gpDef)
	var gpPrefix: String = gpRules.gpPrefixFor(gpDef)
	var gpOut: Array[String] = []
	var gpN: int = gpRules.gpPeek(gpPrefix, gpRule)
	for _gpI in range(maxi(1, gpCount)):
		gpN += maxi(1, gpRule.gpStep)
		gpOut.append(gpRule.gpFormat(gpPrefix, gpN))
	return gpOut


# Every category the symbol library actually uses, sorted. Drives the prefix table so the
# user never has to guess a category name.
# 图元库实际用到的全部类别（已排序）。它驱动前缀表，使用户无需猜测类别名。
static func _gpLibraryCategories() -> Array[String]:
	var gpSeen: Dictionary = {}
	for gpD in GPSymbolLibrary.gpDefaultDefs():
		if gpD.gpCategory != "":
			gpSeen[gpD.gpCategory] = true
	var gpOut: Array[String] = []
	for gpK in gpSeen.keys():
		gpOut.append(str(gpK))
	gpOut.sort()
	return gpOut


# Build the items a full renumber needs, straight from a graph. Nodes keep their graph
# order, which is the order the user drew them in — the most predictable renumbering.
# 从图直接构建全量重编号所需的条目。节点保持图中顺序，即用户绘制它们的顺序
# ——这是最可预期的重编号顺序。
static func gpRenumberItems(gpGraph: GPPIDGraph) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpGraph == null:
		return gpOut
	for gpN in gpGraph.gpNodes:
		gpOut.append({
			"uid": gpN.gpInstanceId,
			"tag": gpN.gpTag,
			"def": GPSymbolLibrary.gpFindById(gpN.gpSymbolId),
		})
	return gpOut


# Write a plan's "new" tags onto the graph's nodes. Returns how many nodes actually changed.
# 把方案中的新位号写回图的节点。返回实际发生变化的节点数。
static func gpApplyPlan(gpGraph: GPPIDGraph, gpPlan: Array[Dictionary]) -> int:
	if gpGraph == null:
		return 0
	var gpChanged: int = 0
	for gpRow in gpPlan:
		var gpN: GPPIDNode = gpGraph.gpGetNode(str(gpRow.get("uid", "")))
		if gpN == null:
			continue
		var gpNewTag: String = str(gpRow.get("new", ""))
		if gpN.gpTag != gpNewTag:
			gpN.gpTag = gpNewTag
			gpChanged += 1
	return gpChanged


# Restore a plan's "old" tags (undo). / 恢复方案中的旧位号（撤销）。
static func gpRevertPlan(gpGraph: GPPIDGraph, gpPlan: Array[Dictionary]) -> int:
	if gpGraph == null:
		return 0
	var gpChanged: int = 0
	for gpRow in gpPlan:
		var gpN: GPPIDNode = gpGraph.gpGetNode(str(gpRow.get("uid", "")))
		if gpN == null:
			continue
		var gpOldTag: String = str(gpRow.get("old", ""))
		if gpN.gpTag != gpOldTag:
			gpN.gpTag = gpOldTag
			gpChanged += 1
	return gpChanged


# Render the old->new mapping as CSV. A renumber changes the number painted on a physical
# nameplate and listed in the DCS point table, so the mapping is a deliverable, not a log.
# 把「旧→新」映射渲染为 CSV。重编号会改变现场标牌与 DCS 点表上的编号，
# 故该映射是交付物，而非日志。
static func gpMappingToCsv(gpPlan: Array[Dictionary]) -> String:
	# PackedStringArray has no join() in Godot 4 — concatenate by hand.
	# Godot 4 的 PackedStringArray 没有 join() —— 手工拼接。
	var gpOut: String = "uid,old_tag,new_tag\n"
	for gpRow in gpPlan:
		gpOut += "%s,%s,%s\n" % [
			gpCsvCell(str(gpRow.get("uid", ""))),
			gpCsvCell(str(gpRow.get("old", ""))),
			gpCsvCell(str(gpRow.get("new", ""))),
		]
	return gpOut


# Quote a CSV cell when it contains a delimiter, a quote or a newline.
# 单元格含分隔符、引号或换行时加引号。
# PUBLIC because M13's equipment lists (GPListBasic) must escape with the exact same rule —
# two hand-rolled escapers would drift, and an asymmetric one corrupts the round-trip.
# 设为公开：M13 的设备清单（GPListBasic）必须用**完全相同**的规则转义 ——
# 两份手写转义器必然漂移，而不对称的转义会破坏往返。
static func gpCsvCell(gpText: String) -> String:
	var gpNeedsQuotes: bool = (gpText.find(",") >= 0 or gpText.find("\"") >= 0
		or gpText.find("\n") >= 0)
	if not gpNeedsQuotes:
		return gpText
	return "\"" + gpText.replace("\"", "\"\"") + "\""


# Human-readable summary for a confirmation dialog: how many nodes change.
# 供确认对话框使用的人类可读摘要：有多少节点会变。
static func gpChangedCount(gpPlan: Array[Dictionary]) -> int:
	var gpN: int = 0
	for gpRow in gpPlan:
		if str(gpRow.get("old", "")) != str(gpRow.get("new", "")):
			gpN += 1
	return gpN


# ==================== M13: portable rule template (.gptagrule.json) ====================
# ==================== M13：可移植规则模板（.gptagrule.json） ====================
# A project's numbering convention is the kind of thing a company standardises across dozens
# of projects. Exporting it as plain JSON lets a team diff it, review it and copy it into the
# next project — and because it is plain text, it stays readable in ten years without G-PID.
# 一个工程的编号约定，往往是一家公司在几十个工程间统一的东西。把它导出为纯 JSON，
# 团队就能 diff、评审、并复制到下一个工程；而且因为它是纯文本，十年后没有 G-PID 也读得懂。


# Serialise a rules object to the portable template. Pretty-printed on purpose (diffable).
# 把规则对象序列化为可移植模板。刻意做美化缩进（便于 diff）。
static func gpRulesToJson(gpRules: GPProjectTagRules) -> String:
	if gpRules == null:
		return "{}"
	return JSON.stringify(gpRules.gpToDict(), "  ", true)


# Parse a template back. Returns null when the text is not valid JSON or not an object, so a
# hand-broken file is reported as "could not read" instead of silently yielding factory rules.
# 解析模板。文本不是合法 JSON 或不是对象时返回 null —— 手工改坏的文件应报「读不了」，
# 而不是静默退化成出厂规则。
static func gpRulesFromJson(gpText: String) -> GPProjectTagRules:
	var gpParsed: Variant = JSON.parse_string(gpText)
	if gpParsed == null or not (gpParsed is Dictionary):
		return null
	return GPProjectTagRules.gpFromDict(gpParsed as Dictionary)
