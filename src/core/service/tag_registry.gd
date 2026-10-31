class_name GPTagRegistry
extends RefCounted
# Copyright © 2026 Jonson Wang
# Project-wide tag uniqueness guard .
# 工程级位号唯一性守卫（属性计划 M9）。
#
# A tag (位号) is the human-visible equipment number: "P-1001", "V-203". It is editable, it
# travels into DCS point lists and physical nameplates, and two pieces of equipment may never
# share one. The uid is the opposite: invisible, immutable, and what edges actually reference.
# 位号是给人看的设编号："P-1001"、"V-203"。它可改、会进 DCS 点表与现场标牌，且两台设备
# 绝不可共用。uid 则相反：不可见、不可变，边真正引用的是它。
#
# THE INDEX IS A CACHE, THE GRAPH IS THE TRUTH / 索引是缓存，图才是真相:
# uid->tag and normalised-tag->uid are rebuilt from the graph by gpRebuild(). They are a
# fast path for "who owns this tag?" error messages, never the authority. gpIsTaken()
# ALSO scans the attached graph, so a stale index can slow numbering down but can NEVER
# hand out a duplicate — the failure mode is a skipped number, not a broken sheet.
# uid->tag 与归一化位号->uid 由 gpRebuild() 从图重建。它们是「谁占用了这个位号」错误
# 提示的快路径，绝非权威。gpIsTaken() 同时扫描所附的图，故索引过期只会让编号跳号，
# 绝不会发出重复位号——失效模式是跳号，而不是坏图纸。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The graph this registry guards. Optional, but strongly recommended: without it gpIsTaken()
# cannot see tags written by code paths that forgot to register.
# 本注册器所守护的图。可选，但强烈建议提供：没有它，gpIsTaken() 便看不见那些「忘记登记」
# 的代码路径写入的位号。
var gpGraph: GPPIDGraph = null

# Project numbering rules (prefix tables, template, sequence marks).
# 工程编号规则（前缀表、模板、序号水位线）。
var gpRules: GPProjectTagRules = null

# Every sheet's graph of THIS project, including this registry's own (ADR-36 D6). Empty means
# "single sheet": the registry then sees only gpGraph, which is exactly the pre-ADR-36
# behaviour, so headless callers and tests that never set it keep working.
# 本工程**每张**图纸的图，含本注册器自己的那张（ADR-36 D6）。为空表示「单图纸」：此时注册器
# 只看 gpGraph，正是 ADR-36 之前的行为，故从未设置它的 headless 调用方与测试照旧可用。
var gpProjectGraphs: Array[GPPIDGraph] = []

# The project standard (class rules, scopes, code tables). Optional: null falls back to
# `gpGraph.gpStandard`, and if that is null too the registry behaves like the legacy one.
# 项目标准（类别规则、作用域、代号表）。可选：为空时回落 `gpGraph.gpStandard`；仍为空则
# 注册器退回旧行为。
var gpStandard: GPProjectStandard = null

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

# ---- scope / 作用域 ----

# Every graph this registry must see: the project's sheets (when known) plus this one.
# 本注册器必须看到的全部图：工程各图纸（已知时）加上自己这张。
func gpGraphs() -> Array[GPPIDGraph]:
	var gpOut: Array[GPPIDGraph] = []
	for gpG in gpProjectGraphs:
		if gpG != null and not gpOut.has(gpG):
			gpOut.append(gpG)
	if gpGraph != null and not gpOut.has(gpGraph):
		gpOut.append(gpGraph)
	return gpOut


# Install the project's sheet list. Called by the shell whenever tabs are added, closed or
# loaded; a null/empty list downgrades the registry to single-sheet behaviour.
# 安装工程图纸列表。外壳在标签页增删或载入后调用；null / 空列表使注册器退回单图纸行为。
func gpSetProjectGraphs(gpGraphsIn: Array) -> void:
	gpProjectGraphs = []
	for gpGRaw in gpGraphsIn:
		if gpGRaw is GPPIDGraph:
			gpProjectGraphs.append(gpGRaw as GPPIDGraph)
	gpRebuild()


# The standard this registry consults (may be null, meaning "legacy single-class").
# 本注册器查询的标准（可为 null，即「旧式单类别」）。
func gpStandardRef() -> GPProjectStandard:
	if gpStandard != null:
		return gpStandard
	if gpGraph != null:
		return gpGraph.gpStandard
	return null


# Whether a tag is in use by somebody other than gpExceptUid, ACROSS THE WHOLE PROJECT
# (every sheet, nodes and edges — one table, ADR-36 D6). Empty tags are never taken.
# 某位号是否已被 gpExceptUid 之外的对象占用，**跨整个工程**（每张图纸、节点与边 —— 一张表，
# ADR-36 D6）。空位号永不算被占用。
func gpIsTaken(gpTag: String, gpExceptUid: String = "") -> bool:
	return _gpIsTakenIn(gpGraphs(), gpTag, gpExceptUid)


# Whether a tag is taken ON ONE SHEET (nodes and edges). This is the scope of line numbers:
# the same line may legitimately continue onto another sheet (ADR-36 D1).
# 某位号在**单张图纸**上是否被占用（节点与边）。这是管线号的作用域：同一根管线可以合法延续到
# 另一张图纸（ADR-36 D1）。
func gpIsTakenOnSheet(gpTag: String, gpGraphIn: GPPIDGraph = null,
		gpExceptUid: String = "") -> bool:
	var gpOne: GPPIDGraph = gpGraphIn if gpGraphIn != null else gpGraph
	var gpList: Array[GPPIDGraph] = []
	if gpOne != null:
		gpList.append(gpOne)
	return _gpIsTakenIn(gpList, gpTag, gpExceptUid)


# Whether a tag is taken FOR A CANDIDATE OF A GIVEN CLASS — the one entry every minting path
# calls, so the scope rule lives in exactly one place.
# 对**某个类别**的候选者而言某位号是否被占用 —— 所有铸号路径唯一的判断入口，故作用域规则只此一处。
func gpIsTakenForClass(gpClass: String, gpTag: String, gpExceptUid: String = "") -> bool:
	var gpStd: GPProjectStandard = gpStandardRef()
	if gpStd != null and gpStd.gpScopeOf(gpClass) == GPProjectStandard.GP_SCOPE_SHEET:
		return gpIsTakenOnSheet(gpTag, gpGraph, gpExceptUid)
	return gpIsTaken(gpTag, gpExceptUid)


# uid owning a tag, or "" when free. Searches the same scope as gpIsTaken().
# 占用该位号的 uid；空闲时返回 ""。搜索范围与 gpIsTaken() 一致。
func gpOwnerOf(gpTag: String) -> String:
	var gpNorm: String = gpNormalize(gpTag)
	if gpNorm == "":
		return ""
	var gpOwner: String = str(_gpUidByNorm.get(gpNorm, ""))
	if gpOwner != "":
		return gpOwner
	for gpG in gpGraphs():
		for gpN in gpG.gpNodes:
			if gpNormalize(gpN.gpTag) == gpNorm:
				return gpN.gpInstanceId
		for gpE in gpG.gpEdges:
			if gpNormalize(gpE.gpTag) == gpNorm:
				return gpE.gpInstanceId
	return ""


# Scan one set of graphs for a normalised tag. The index is a fast path only: the graphs are
# the truth, so a stale index can slow things down but never hand out a duplicate.
# 在一组图中按归一化位号查找。索引只是快路径：图才是真相，故索引过期只会拖慢、绝不会放出重复位号。
func _gpIsTakenIn(gpGraphsIn: Array[GPPIDGraph], gpTag: String,
		gpExceptUid: String) -> bool:
	var gpNorm: String = gpNormalize(gpTag)
	if gpNorm == "":
		return false
	if _gpUidByNorm.has(gpNorm):
		var gpKnownOwner: String = str(_gpUidByNorm[gpNorm])
		if gpKnownOwner != gpExceptUid:
			return true
	for gpG in gpGraphsIn:
		for gpN in gpG.gpNodes:
			if gpN.gpInstanceId != gpExceptUid and gpNormalize(gpN.gpTag) == gpNorm:
				return true
		for gpE in gpG.gpEdges:
			if gpE.gpInstanceId != gpExceptUid and gpNormalize(gpE.gpTag) == gpNorm:
				return true
	return false


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


# Mint a tag for a symbol instance through its numbering CLASS (ADR-36 D3/D5). Returns ""
# when the class is unknown or disabled — the instance is then simply NOT numbered (a manual
# valve by default, an unmapped symbol), which is a legitimate outcome, not an error.
# 按图元实例所属的**编号类别**铸号（ADR-36 D3/D5）。类别未知或未启用时返回 "" —— 该实例就是
# **不编号**（默认的手动阀、未映射的图元），这是合法结果，不是错误。
# Every placement / paste / duplicate path goes through here, so a valve's actuator decides
# whether it is an instrument or a manual valve in ONE place.
# 放置 / 粘贴 / 复制的每条路径都走这里，故「阀门按执行机构归仪表还是手阀」只在这一处判断。
func gpNextTagForDef(gpDef: GPSymbolDef, gpProps: Dictionary = {}) -> String:
	var gpStd: GPProjectStandard = gpStandardRef()
	if gpStd == null:
		# No standard yet: keep the pre-ADR-36 behaviour so nothing regresses before the first
		# rule edit.
		# 尚无标准：保持 ADR-36 之前的行为，使首次改规则前不会有任何回归。
		return gpNextTag(gpDef)
	var gpClass: String = gpStd.gpClassOf(gpDef, gpProps)
	if gpClass == "" or not gpStd.gpEnabled(gpClass):
		return ""
	return gpNextTagForClass(gpClass, gpDef, gpProps)


# Mint the next free tag for one numbering CLASS (ADR-36 D3/D6). This is the single entry the
# class-specific paths use; `gpNextTag()` above stays as the equipment shim for pre-ADR-36
# callers.
# 为某个编号类别铸造下一个空位号（ADR-36 D3/D6）。类别相关的路径都走这一个入口；
# 上面的 `gpNextTag()` 保留为 ADR-36 之前调用方的设备侧兼容入口。
# For a segmented rule (the line designation) the mark key is the CLASS id; for a template
# rule it stays the prefix, so existing equipment counters are untouched.
# 对分段规则（管线代号）而言水位线键是**类别 id**；对模板规则仍是前缀，故既有设备计数器不受影响。
func gpNextTagForClass(gpClass: String, gpDef: GPSymbolDef = null,
		gpAttrs: Dictionary = {}, gpArea: String = "", gpSheet: String = "") -> String:
	var gpStd: GPProjectStandard = gpStandardRef()
	var gpUseRules: GPProjectTagRules = gpRules
	if gpStd != null:
		gpUseRules = gpStd.gpRulesOf(gpClass)
	elif gpClass == GPProjectStandard.GP_CLASS_LINE and gpGraph != null:
		# A line cannot be numbered without the project standard (it owns the line rule and its
		# mark). Materialise it on demand — minting is a write, so creating the standard here
		# does not surprise a project that never numbers anything.
		# 没有项目标准就无法给管线编号（线规则与水位线都在标准里）。按需建立 —— 铸号本身就是写操作，
		# 故这里创建标准不会惊到「从不编号」的工程。
		gpStd = gpGraph.gpStandardOrCreate()
		gpUseRules = gpStd.gpRulesOf(gpClass)
	var gpRule: GPTagRule = gpUseRules.gpRuleFor(gpDef)
	var gpPrefix: String = ""
	var gpMarkKey: String = gpClass
	if not gpRule.gpUsesSegments():
		gpPrefix = gpUseRules.gpPrefixFor(gpDef)
		gpMarkKey = gpPrefix
	var gpSkips: int = 0
	while gpSkips < GPProjectTagRules.GP_MAX_SKIPS:
		var gpN: int = gpUseRules.gpAdvance(gpMarkKey, gpRule)
		var gpCandidate: String = ""
		if gpRule.gpUsesSegments():
			gpCandidate = gpRule.gpRender({"seq": gpN, "attrs": gpAttrs, "prefix": gpPrefix,
				"area": gpArea, "sheet": gpSheet}, gpStd)
			if gpCandidate == "":
				# Sequence overflow / illegal value: minting must fail loudly, not hand out "".
				# 序号溢出 / 取值非法：铸号必须明确失败，绝不交出 ""。
				return ""
		else:
			gpCandidate = gpRule.gpFormat(gpPrefix, gpN, gpArea, gpSheet)
		if not gpIsTakenForClass(gpClass, gpCandidate):
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
	if gpSource.is_empty():
		# ADR-36: the index covers EVERY sheet of the project, not just this one — otherwise
		# the fast path would keep reporting "free" for a tag that sheet 2 already uses.
		# ADR-36：索引覆盖**工程每一张**图纸，而不只是本张 —— 否则快路径会一直把第二页已用的
		# 位号报成"空闲"。
		gpSource = []
		for gpG in gpGraphs():
			for gpN in gpG.gpNodes:
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
