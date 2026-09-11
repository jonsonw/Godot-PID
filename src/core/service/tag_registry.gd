class_name GPTagRegistry
extends RefCounted
# Copyright © 2026 Jonson Wang
# Project-wide tag uniqueness guard (M9 of the property plan).
# 工程级位号唯一性守卫（属性计划 M9）。
#
# A tag (位号) is the human-visible equipment number: "P-1001", "V-203". It is editable, it
# travels into DCS point lists and physical nameplates, and two pieces of equipment may never
# share one. The uid is the opposite: invisible, immutable, and what edges actually reference.
# 位号是给人看的设编号："P-1001"、"V-203"。它可改、会进 DCS 点表与现场标牌，且两台设备
# 绝不可共用。uid 则相反：不可见、不可变，边真正引用的是它。
#
# THE INDEX IS A CACHE, THE GRAPH IS THE TRUTH / 索引是缓存，图才是真相:
#   uid->tag and normalised-tag->uid are rebuilt from the graph by gpRebuild(). They are a
#   fast path for "who owns this tag?" error messages, never the authority. gpIsTaken()
#   ALSO scans the attached graph, so a stale index can slow numbering down but can NEVER
#   hand out a duplicate — the failure mode is a skipped number, not a broken sheet.
#   uid->tag 与归一化位号->uid 由 gpRebuild() 从图重建。它们是「谁占用了这个位号」错误
#   提示的快路径，绝非权威。gpIsTaken() 同时扫描所附的图，故索引过期只会让编号跳号，
#   绝不会发出重复位号——失效模式是跳号，而不是坏图纸。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The graph this registry guards. Optional, but strongly recommended: without it gpIsTaken
# cannot see tags written by code paths that forgot to register.
# 本注册器所守护的图。可选，但强烈建议提供：没有它，gpIsTaken 便看不见那些「忘记登记」
# 的代码路径写入的位号。
var gpGraph: GPPIDGraph = null

# Project numbering rules (prefix tables, template, sequence marks).
# 工程编号规则（前缀表、模板、序号水位线）。
var gpRules: GPProjectTagRules = null

# uid -> tag (as typed, display-cased). / uid -> 位号（按用户输入，保留大小写）。
var _gpTagByUid: Dictionary = {}

# normalised tag -> uid. / 归一化位号 -> uid。
var _gpUidByNorm: Dictionary = {}

# Tags that collided during the last gpRebuild(). Each entry is {"tag","uids"}.
# 上次 gpRebuild() 中发生冲突的位号。每项形如 {"tag","uids"}。
var _gpConflicts: Array[Dictionary] = []


# ---- normalisation ----

# Separators folded away before comparing: a draughtsman may type "P-1001", "P 1001" or
# "P.1001" and they are all the same pump. Only SEPARATORS go — letters (including CJK) and
# digits are kept, so two Chinese tags never collapse onto each other.
# 比较前折去分隔符：制图员可能键入 "P-1001"、"P 1001" 或 "P.1001"，它们都是同一台泵。
# 只去除**分隔符** —— 字母（含中文）与数字都保留，故两个中文位号不会互相折叠。
const GP_SEPARATORS: String = " \t\r\n-_./\\"

# Comparison form of a tag: separators removed, upper-cased. The stored tag keeps whatever
# the user typed, so "P-1001" stays readable on the sheet even though it compares as P1001.
# 位号的比较形式：去分隔符、转大写。存储的位号保留用户键入的原样，
# 故 "P-1001" 在图纸上依然可读，尽管它按 P1001 参与比较。
static func gpNormalize(gpTag: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpTag.length()):
		var gpC: String = gpTag[gpI]
		if GP_SEPARATORS.find(gpC) >= 0:
			continue
		gpOut += gpC
	return gpOut.to_upper()


# ---- registration ----

# Record a tag for a uid. An empty tag means "not numbered yet" and is always accepted —
# several un-numbered instances may coexist.
# 为一个 uid 登记位号。空位号意为「尚未编号」，恒被接受——多个未编号实例可并存。
func gpRegister(gpUid: String, gpTag: String) -> GPIOResult:
	if gpUid == "":
		return GPIOResult.gpFailure("tag.no_uid", "tag.err_no_uid", "")
	_gpReleaseLocked(gpUid)
	if gpTag == "":
		return GPIOResult.gpSuccess()
	var gpNorm: String = gpNormalize(gpTag)
	var gpOwner: String = _gpOwnerOfLocked(gpNorm, gpUid)
	if gpOwner != "":
		return GPIOResult.gpFailure("tag.duplicate", "tag.err_duplicate", "%s (%s)" % [gpTag, gpOwner])
	_gpTagByUid[gpUid] = gpTag
	_gpUidByNorm[gpNorm] = gpUid
	return GPIOResult.gpSuccess()


# Change a uid's tag. Rejects when the new tag belongs to somebody else.
# 修改某 uid 的位号。新位号归属他人时拒绝。
func gpRename(gpUid: String, gpNewTag: String) -> GPIOResult:
	return gpRegister(gpUid, gpNewTag)


# Forget a uid (node deleted). / 注销某 uid（节点被删）。
func gpRelease(gpUid: String) -> void:
	_gpReleaseLocked(gpUid)


# Drop every entry. / 清空全部条目。
func gpClear() -> void:
	_gpTagByUid.clear()
	_gpUidByNorm.clear()
	_gpConflicts.clear()


# ---- queries ----

# Whether a tag is in use by somebody other than gpExceptUid. Empty tags are never taken.
# 某位号是否已被 gpExceptUid 之外的对象占用。空位号永不算被占用。
func gpIsTaken(gpTag: String, gpExceptUid: String = "") -> bool:
	var gpNorm: String = gpNormalize(gpTag)
	if gpNorm == "":
		return false
	if _gpUidByNorm.has(gpNorm):
		var gpOwner: String = str(_gpUidByNorm[gpNorm])
		if gpOwner != gpExceptUid:
			return true
	if gpGraph != null:
		for gpN in gpGraph.gpNodes:
			if gpN.gpInstanceId == gpExceptUid:
				continue
			if gpNormalize(gpN.gpTag) == gpNorm:
				return true
	return false


# uid owning a tag, or "" when free. / 占用该位号的 uid；空闲时返回 ""。
func gpOwnerOf(gpTag: String) -> String:
	var gpNorm: String = gpNormalize(gpTag)
	if gpNorm == "":
		return ""
	var gpOwner: String = str(_gpUidByNorm.get(gpNorm, ""))
	if gpOwner != "":
		return gpOwner
	if gpGraph != null:
		for gpN in gpGraph.gpNodes:
			if gpNormalize(gpN.gpTag) == gpNorm:
				return gpN.gpInstanceId
	return ""


# Tag recorded for a uid ("" when unknown or un-numbered).
# 某 uid 已登记的位号（未知或未编号时为 ""）。
func gpTagOf(gpUid: String) -> String:
	return str(_gpTagByUid.get(gpUid, ""))


# How many uids carry a non-empty tag. / 持有非空位号的 uid 数量。
func gpCountTagged() -> int:
	return _gpTagByUid.size()


# Duplicates found by the last gpRebuild(). W10 validation reuses this verbatim.
# 上次 gpRebuild() 发现的重复项。W10 校验原样复用。
func gpConflicts() -> Array[Dictionary]:
	return _gpConflicts.duplicate()


# ---- allocation ----

# Mint the next free tag for a symbol definition. Advances the rule's sequence mark and
# skips numbers the user already typed by hand.
# 为一个图元定义铸造下一个空位号。推进规则的序号水位线，并跳过用户已手打占用的号。
# gpArea / gpSheet feed the {area} / {sheet} placeholders (empty until W21 multi-sheet lands).
# gpArea / gpSheet 供 {area} / {sheet} 占位符使用（W21 多图纸落地前为空）。
func gpNextTag(gpDef: GPSymbolDef, gpArea: String = "", gpSheet: String = "") -> String:
	_gpEnsureRules()
	var gpRule: GPTagRule = gpRules.gpRuleFor(gpDef)
	var gpPrefix: String = gpRule.gpPrefixFor(gpDef)
	var gpSkips: int = 0
	while gpSkips < GPProjectTagRules.GP_MAX_SKIPS:
		var gpN: int = gpRules.gpAdvance(gpPrefix, gpRule)
		var gpCandidate: String = gpRule.gpFormat(gpPrefix, gpN, gpArea, gpSheet)
		if not gpIsTaken(gpCandidate):
			return gpCandidate
		gpSkips += 1
	return ""


# Preview the next N tags WITHOUT consuming them — the numbering-rule dialog needs a live
# sample while the user is still typing.
# 预览接下来的 N 个位号而**不消耗**它们——编号规则对话框在用户仍在输入时就需要实时样例。
func gpPreview(gpDef: GPSymbolDef, gpCount: int = 3, gpArea: String = "",
		gpSheet: String = "") -> Array[String]:
	_gpEnsureRules()
	var gpRule: GPTagRule = gpRules.gpRuleFor(gpDef)
	var gpPrefix: String = gpRule.gpPrefixFor(gpDef)
	var gpOut: Array[String] = []
	var gpN: int = gpRules.gpPeek(gpPrefix, gpRule)
	var gpMade: int = 0
	var gpSkips: int = 0
	while gpMade < gpCount and gpSkips < GPProjectTagRules.GP_MAX_SKIPS:
		gpN += maxi(1, gpRule.gpStep)
		var gpCandidate: String = gpRule.gpFormat(gpPrefix, gpN, gpArea, gpSheet)
		if gpIsTaken(gpCandidate):
			gpSkips += 1
			continue
		gpOut.append(gpCandidate)
		gpMade += 1
	return gpOut


# Re-derive the whole index from gpItems (each {"uid","tag"}), typically the graph's nodes,
# or from the attached graph when gpItems is omitted. Later duplicates are recorded in
# gpConflicts() rather than silently overwriting the first owner.
# 从 gpItems（每项 {"uid","tag"}，通常即图的节点）重建整个索引；省略 gpItems 时从
# 所附的图重建。后到的重复项记入 gpConflicts()，而非静默覆盖首个占用者。
func gpRebuild(gpItems: Array[Dictionary] = []) -> void:
	_gpTagByUid.clear()
	_gpUidByNorm.clear()
	_gpConflicts.clear()
	var gpSource: Array[Dictionary] = gpItems
	if gpSource.is_empty() and gpGraph != null:
		gpSource = []
		for gpN in gpGraph.gpNodes:
			gpSource.append({"uid": gpN.gpInstanceId, "tag": gpN.gpTag})
	for gpIt in gpSource:
		var gpUid: String = str(gpIt.get("uid", ""))
		var gpTag: String = str(gpIt.get("tag", ""))
		if gpUid == "" or gpTag == "":
			continue
		var gpNorm: String = gpNormalize(gpTag)
		if _gpUidByNorm.has(gpNorm):
			_gpConflicts.append({"tag": gpTag, "uids": [str(_gpUidByNorm[gpNorm]), gpUid]})
			continue
		_gpTagByUid[gpUid] = gpTag
		_gpUidByNorm[gpNorm] = gpUid


# ---- renumbering ----

# Re-mint a tag for every item, in order. Returns the old->new mapping the caller applies to
# the nodes and exports as an audit CSV. Sequence marks are reset first, so the project is
# numbered densely from the very beginning.
# 按顺序为每一项重新铸造位号。返回 old->new 映射，供调用方应用到节点并导出为对照表。
# 先重置序号水位线，使整个工程自起点开始密集编号。
func gpPlanRenumberAll(gpItems: Array[Dictionary], gpArea: String = "",
		gpSheet: String = "") -> Array[Dictionary]:
	_gpEnsureRules()
	gpRules.gpResetMarks()
	_gpTagByUid.clear()
	_gpUidByNorm.clear()
	_gpConflicts.clear()
	var gpOut: Array[Dictionary] = []
	for gpIt in gpItems:
		var gpUid: String = str(gpIt.get("uid", ""))
		if gpUid == "":
			continue
		var gpDef: GPSymbolDef = gpIt.get("def", null) as GPSymbolDef
		var gpOld: String = str(gpIt.get("tag", ""))
		var gpNewTag: String = gpNextTag(gpDef, gpArea, gpSheet)
		if gpNewTag != "":
			_gpTagByUid[gpUid] = gpNewTag
			_gpUidByNorm[gpNormalize(gpNewTag)] = gpUid
		gpOut.append({"uid": gpUid, "old": gpOld, "new": gpNewTag})
	return gpOut


# ---- internals ----

# Drop a uid from both indexes without emitting anything.
# 从两个索引中移除某 uid，不发出任何信号。
func _gpReleaseLocked(gpUid: String) -> void:
	if not _gpTagByUid.has(gpUid):
		return
	var gpOld: String = str(_gpTagByUid[gpUid])
	_gpTagByUid.erase(gpUid)
	if gpOld != "" and str(_gpUidByNorm.get(gpNormalize(gpOld), "")) == gpUid:
		_gpUidByNorm.erase(gpNormalize(gpOld))


# Owner lookup that ignores gpExceptUid. / 忽略 gpExceptUid 的占用者查询。
func _gpOwnerOfLocked(gpNorm: String, gpExceptUid: String) -> String:
	var gpOwner: String = str(_gpUidByNorm.get(gpNorm, ""))
	if gpOwner != "" and gpOwner != gpExceptUid:
		return gpOwner
	if gpGraph != null:
		for gpN in gpGraph.gpNodes:
			if gpN.gpInstanceId == gpExceptUid:
				continue
			if gpNormalize(gpN.gpTag) == gpNorm:
				return gpN.gpInstanceId
	return ""


# Lazily materialise the rules so a registry built in two steps never dereferences null.
# 惰性建立规则，使「两步构造」的注册器永不解引用 null。
func _gpEnsureRules() -> void:
	if gpRules == null:
		# Bind to the GRAPH's rules (never a private copy): the sequence marks must be the
		# ones the graph serialises, or numbering would restart on every save/load.
		# 绑定到「图的」规则（绝不用私有副本）：序号水位线必须是图会序列化的那一份，
		# 否则每次存/读编号都会从头再来。
		gpRules = gpGraph.gpTagRulesOrCreate() if gpGraph != null else GPProjectTagRules.gpDefaultRules()
	elif gpGraph != null and gpGraph.gpTagRules != null and gpRules != gpGraph.gpTagRules:
		gpRules = gpGraph.gpTagRules
