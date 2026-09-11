class_name GPProjectTagRules
extends RefCounted
# Copyright © 2026 Jonson Wang
# Project-wide tag numbering configuration: one default rule, optional per-category /
# per-symbol overrides, and the per-prefix high-water marks.
# 工程级位号编号配置：一条默认规则、可选的按类别 / 按图元覆盖，以及各前缀的水位线。
#
# Two things live here on purpose / 以下两件事刻意放在此处：
#   1. The RULES travel with the project file (they are embedded in *.pid.json), because a
#      project's numbering convention belongs to that project — not to the symbol library and
#      not to the application. Data sovereignty: reopening the archive years later must
#      reproduce the same convention.
#      规则随工程文件走（内嵌进 *.pid.json），因为编号约定属于该工程——不属于图元库，
#      也不属于应用程序。数据主权：多年后重开存档必须能复现同一套约定。
#   2. The high-water marks travel with the rules, NOT with gpGraph.gpMeta["tag_seq"].
#      GPTagGen keeps pipe marks in gpMeta (pre-existing behaviour, must not change); the
#      equipment counter is new and belongs beside the rules that define it, so a rule edit
#      and its counter cannot drift apart.
#      水位线随规则走，而非落在 gpGraph.gpMeta["tag_seq"]。GPTagGen 的管线水位线留在
#      gpMeta（既有行为，不可改）；设备计数器是新增的，理应紧邻定义它的规则，
#      使「改规则」与「改计数器」不会脱节。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Key prefix for a category override entry (see gpOverrideKey).
# 类别覆盖项键的前缀（见 gpOverrideKey）。
const GP_CAT_KEY: String = "cat:"

# Key prefix for a symbol override entry.
# 图元覆盖项键的前缀。
const GP_SYM_KEY: String = "sym:"

# Guard against a hand-edited archive turning allocation into an endless loop.
# 防止手改过的存档把分配变成死循环。
const GP_MAX_SKIPS: int = 100000

# The one rule used when nothing more specific matches.
# 无更具体匹配时使用的那条规则。
var gpDefault: GPTagRule = null

# "cat:<category>" or "sym:<symbol id>" -> GPTagRule.
# "cat:<类别>" 或 "sym:<图元 id>" -> GPTagRule。
var gpOverrides: Dictionary = {}

# prefix -> high-water mark (the last sequence number handed out for that prefix).
# 前缀 -> 水位线（该前缀已发出的最后一个序号）。
var gpSeqMarks: Dictionary = {}


# Build the factory configuration. / 构造出厂配置。
static func gpDefaultRules() -> GPProjectTagRules:
	var gpR: GPProjectTagRules = GPProjectTagRules.new()
	gpR.gpDefault = GPTagRule.gpDefault()
	return gpR


# Build the override key for a category. / 构造类别的覆盖键。
static func gpCategoryKey(gpCategory: String) -> String:
	return GP_CAT_KEY + gpCategory.to_lower()


# Build the override key for a symbol id. / 构造图元 id 的覆盖键。
static func gpSymbolKey(gpSymbolId: String) -> String:
	return GP_SYM_KEY + gpSymbolId


# ---- rule lookup ----

# Rule for one symbol definition: a symbol override wins over a category override, which wins
# over the default. A def without an id (a dangling reference) gets the default.
# 一个图元定义所用的规则：图元覆盖 > 类别覆盖 > 默认。无 id 的定义（悬空引用）取默认。
func gpRuleFor(gpDef: GPSymbolDef) -> GPTagRule:
	_gpEnsureDefault()
	if gpDef == null:
		return gpDefault
	var gpBySym: Variant = gpOverrides.get(gpSymbolKey(gpDef.gpId), null)
	if gpBySym is GPTagRule:
		return gpBySym as GPTagRule
	var gpByCat: Variant = gpOverrides.get(gpCategoryKey(gpDef.gpCategory), null)
	if gpByCat is GPTagRule:
		return gpByCat as GPTagRule
	return gpDefault


# Resolve the prefix for a definition (never empty). Precedence, most specific first:
# 1) a per-symbol override rule set in this project;
# 2) the definition's own gpTagPrefix (the library author's choice);
# 3) the category override rule / the default rule.
# 解析出一个定义的前缀（绝不为空）。优先级由最具体到最宽泛：
# 1) 本工程中设置的按图元覆盖规则；
# 2) 定义自带的 gpTagPrefix（图元库作者的选择）；
# 3) 类别覆盖规则 / 默认规则。
func gpPrefixFor(gpDef: GPSymbolDef) -> String:
	if gpDef != null:
		var gpSymRule: Variant = gpOverrides.get(gpSymbolKey(gpDef.gpId), null)
		if gpSymRule is GPTagRule:
			return (gpSymRule as GPTagRule).gpPrefixFor(gpDef)
	return gpRuleFor(gpDef).gpPrefixFor(gpDef)


# Set (or clear, with null) an override. / 设置（或传 null 清除）一条覆盖规则。
func gpSetOverride(gpKey: String, gpRule: GPTagRule) -> void:
	if gpRule == null:
		gpOverrides.erase(gpKey)
		return
	gpOverrides[gpKey] = gpRule


# ---- sequence marks ----

# Current high-water mark for a prefix. Falls back to the rule's start, so the first number
# handed out is always start + step.
# 某前缀的当前水位线。回落到规则的起点，故首个发出的号恒为「起点 + 步长」。
func gpPeek(gpPrefix: String, gpRule: GPTagRule = null) -> int:
	var gpBase: int = gpRule.gpStart if gpRule != null else GPTagRule.GP_DEFAULT_START
	if gpSeqMarks.has(gpPrefix):
		return maxi(int(gpSeqMarks[gpPrefix]), gpBase)
	return gpBase


# Force a mark (used when a document is loaded, and by undo of a renumber).
# 强制设定水位线（载入文档时、以及撤销重编号时使用）。
func gpSetMark(gpPrefix: String, gpN: int) -> void:
	gpSeqMarks[gpPrefix] = gpN


# Advance and return the next sequence number for a prefix. The mark is committed here, so
# a number is never issued twice even if the caller drops the result on the floor.
# 推进并返回某前缀的下一个序号。水位线在此提交，故即便调用方丢弃结果，该号也不会重发。
func gpAdvance(gpPrefix: String, gpRule: GPTagRule = null) -> int:
	var gpStep: int = gpRule.gpStep if gpRule != null else GPTagRule.GP_DEFAULT_STEP
	var gpN: int = gpPeek(gpPrefix, gpRule) + maxi(1, gpStep)
	gpSeqMarks[gpPrefix] = gpN
	return gpN


# Forget every mark. Used by "renumber all", which restarts the whole project from scratch.
# 清空所有水位线。由「全量重编号」使用——它把整个工程从头重排。
func gpResetMarks() -> void:
	gpSeqMarks.clear()


# ---- validation ----

# Validate every rule. Returns the first failure, tagged with which rule it came from.
# 校验所有规则。返回首个失败，并标明来自哪条规则。
func gpValidate() -> GPIOResult:
	_gpEnsureDefault()
	var gpRes: GPIOResult = gpDefault.gpValidate()
	if not gpRes.gpIsOk():
		return gpRes
	for gpK in gpOverrides.keys():
		var gpR: Variant = gpOverrides[gpK]
		if gpR is GPTagRule:
			var gpOne: GPIOResult = (gpR as GPTagRule).gpValidate()
			if not gpOne.gpIsOk():
				gpOne.gpDetail = "%s (%s)" % [gpOne.gpDetail, str(gpK)]
				return gpOne
	return GPIOResult.gpSuccess()


# ---- persistence ----

func gpToDict() -> Dictionary:
	_gpEnsureDefault()
	var gpOut: Dictionary = {}
	for gpK in gpOverrides.keys():
		var gpR: Variant = gpOverrides[gpK]
		if gpR is GPTagRule:
			gpOut[str(gpK)] = (gpR as GPTagRule).gpToDict()
	return {
		"version": 1,
		"default": gpDefault.gpToDict(),
		"overrides": gpOut,
		"seq_marks": gpSeqMarks.duplicate(),
	}


static func gpFromDict(gpD: Dictionary) -> GPProjectTagRules:
	var gpR: GPProjectTagRules = GPProjectTagRules.new()
	if gpD.is_empty():
		return gpDefaultRules()
	gpR.gpDefault = GPTagRule.gpFromDict(gpD.get("default", {}) as Dictionary)
	var gpOvr: Dictionary = gpD.get("overrides", {})
	for gpK in gpOvr.keys():
		gpR.gpOverrides[str(gpK)] = GPTagRule.gpFromDict(gpOvr[gpK] as Dictionary)
	var gpMarks: Dictionary = gpD.get("seq_marks", {})
	gpR.gpSeqMarks = gpMarks.duplicate() if gpMarks is Dictionary else {}
	return gpR


# Lazily materialise the default rule so a rules object built field by field can never hand
# out a null rule.
# 惰性建立默认规则，使「逐字段构造」的规则对象绝不会交出 null 规则。
func _gpEnsureDefault() -> void:
	if gpDefault == null:
		gpDefault = GPTagRule.gpDefault()
