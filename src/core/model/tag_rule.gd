class_name GPTagRule
extends RefCounted
# Copyright © 2026 Jonson Wang
# One numbering rule for process tags (e.g. "P-1001").
# 位号编号规则（如 "P-1001"）的单条定义。
#
# A rule answers three questions / 一条规则回答三个问题:
# 1. Where does the PREFIX come from? (category table / symbol table / one fixed string)
# 前缀从哪来？（类别表 / 图元表 / 固定串）
# 2. How is the number rendered? (start / step / zero padding / template)
# 序号如何呈现？（起始 / 步长 / 补零 / 模板）
# 3. What happens on a collision? (reject and tell / silently take the next free one)
# 撞号怎么办？（拒绝并提示 / 自动顺延到下一个空号）
#
# WHY THIS IS NOT GPTagGen / 为何不是 GPTagGen:
# GPTagGen owns the PIPE numbering ("PL-1001") and deliberately keeps its high-water marks in
# gpGraph.gpMeta, because pipe numbers predate this rule system and must keep working byte for
# byte. GPTagRule is the EQUIPMENT side and is user-editable per project. They share the
# "{prefix}-{seq}" shape on purpose so a user reading the sheet sees one consistent style.
# GPTagGen 负责「管线号」（"PL-1001"），其水位线刻意留在 gpGraph.gpMeta——管线号早于本规则
# 系统且必须逐字节保持原行为。GPTagRule 是「设备位号」侧，按工程可由用户编辑。二者刻意
# 共用 "{prefix}-{seq}" 形态，使图纸上的编号风格一致。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Where the prefix comes from. / 前缀来源。
enum GPPrefixSource {
	GP_BY_CATEGORY,  # look up gpCategoryPrefixes by gpCategory / 按 gpCategory 查 gpCategoryPrefixes
	GP_BY_SYMBOL,    # look up gpSymbolPrefixes by symbol id / 按图元 id 查 gpSymbolPrefixes
	GP_FIXED,        # always gpFixedPrefix / 恒用 gpFixedPrefix
}

# Factory template. Must contain {seq} — a rule without a sequence is a constant string and
# would hand every instance in the project the same tag.
# 出厂模板。必须含 {seq}——不含序号的规则是常量串，会给工程里每个实例同一个位号。
const GP_DEFAULT_TEMPLATE: String = "{prefix}-{seq}"

# First number handed out is GP_DEFAULT_START + GP_DEFAULT_STEP, i.e. P-1001.
# 首个发出的号是 GP_DEFAULT_START + GP_DEFAULT_STEP，即 P-1001。
const GP_DEFAULT_START: int = 1000

const GP_DEFAULT_STEP: int = 1

# 0 = no zero padding ("1001"); 4 = "0001".
# 0 = 不补零（"1001"）；4 = "0001"。
const GP_DEFAULT_DIGITS: int = 0

# Prefix for a category with no explicit mapping. "X" is deliberately ugly: a tag the user
# never configured should look un-configured on the sheet.
# 无显式映射的类别所用前缀。"X" 是刻意取丑的：用户没配过的位号在图纸上就该显得没配过。
const GP_FALLBACK_PREFIX: String = "X"

# Upper bound on zero padding. Beyond 8 digits the tags stop being readable.
# 补零位数上限。超过 8 位位号就不可读了。
const GP_MAX_DIGITS: int = 8

# Factory prefix table (§7.1 of the property plan). Keys are lowercase gpCategory values.
# 出厂前缀表（属性计划 §7.1）。键为小写的 gpCategory 取值。
const GP_DEFAULT_CATEGORY_PREFIXES: Dictionary = {
	"pump": "P",
	"valve": "V",
	"heat": "E",
	"tank": "T",
	"instrument": "I",
	"filter": "F",
	"general": "G",
}

# ---- configuration ----

# Template. Placeholders: {prefix} {seq} {seq:N} {area} {sheet}.
# 模板。占位符：{prefix} {seq} {seq:N} {area} {sheet}。
var gpTemplate: String = GP_DEFAULT_TEMPLATE

# Sequence start: the counter BEGINS here, so the first issued number is start + step.
# 序号起点：计数器自此开始，故首个发出的号是「起点 + 步长」。
var gpStart: int = GP_DEFAULT_START

var gpStep: int = GP_DEFAULT_STEP

var gpDigits: int = GP_DEFAULT_DIGITS

var gpPrefixSource: GPPrefixSource = GPPrefixSource.GP_BY_CATEGORY

var gpFixedPrefix: String = ""

# category key (lowercase) -> prefix. / 类别键（小写）-> 前缀。
var gpCategoryPrefixes: Dictionary = {}

# symbol id -> prefix. / 图元 id -> 前缀。
var gpSymbolPrefixes: Dictionary = {}

# ---- segmented rules (ADR-36 D4) ----
# EMPTY means "legacy single-template rule": the {prefix}-{seq} path above stays authoritative
# for it, and gpToDict() writes exactly the same keys as before (byte-stable archives).
# 为空表示「旧式单模板规则」：上面那条 {prefix}-{seq} 路径对它保持权威，且 gpToDict() 写出的键
# 与从前完全一致（存档逐字节稳定）。
# When NON-empty, this rule renders and validates through its segments instead.
# 非空时，本规则改由各段负责渲染与校验。
var gpSegments: Array[GPTagSegment] = []

# Separator between segments ("-" by convention). Only meaningful with gpSegments.
# 段间分隔符（约定为 "-"）。仅在 gpSegments 非空时有意义。
var gpSeparator: String = "-"


# Build the factory rule. / 构造出厂规则。
static func gpDefault() -> GPTagRule:
	var gpR: GPTagRule = GPTagRule.new()
	gpR.gpCategoryPrefixes = GP_DEFAULT_CATEGORY_PREFIXES.duplicate()
	return gpR


# ---- prefix resolution ----

# Prefix for a symbol definition. Resolution order (most specific first):
# 1) GP_FIXED / GP_BY_SYMBOL sources — an explicit table entry the user set here;
# 2) the category table entry for gpCategory;
# 3) the definition's own gpTagPrefix (the library author's default);
# 4) the first ASCII letter of the category, upper-cased;
# 5) GP_FALLBACK_PREFIX.
#
# WHY THE TABLE BEATS THE DEFINITION / 为何表优先于定义:
# gpCategoryPrefixes is PROJECT configuration the user edits in the numbering dialog;
# gpTagPrefix is baked into the library at generation time. When a project says "pumps are
# PP here", that is the more specific intent and must win — otherwise editing the table
# would appear to do nothing.
# gpCategoryPrefixes 是用户在编号对话框里编辑的**工程**配置；gpTagPrefix 是生成时烘进
# 图元库的默认值。当工程说「本工程泵为 PP」，这是更具体的意图，必须胜出——
# 否则编辑该表会看起来毫无作用。
# 图元定义的前缀。解析顺序（由最具体到最宽泛）见上。
func gpPrefixFor(gpDef: GPSymbolDef) -> String:
	if gpDef == null:
		if gpFixedPrefix != "":
			return gpSanitizePrefix(gpFixedPrefix)
		return GP_FALLBACK_PREFIX
	if gpPrefixSource == GPPrefixSource.GP_FIXED and gpFixedPrefix != "":
		return gpSanitizePrefix(gpFixedPrefix)
	if gpPrefixSource == GPPrefixSource.GP_BY_SYMBOL:
		var gpBySym: String = str(gpSymbolPrefixes.get(gpDef.gpId, ""))
		if gpBySym != "":
			return gpSanitizePrefix(gpBySym)
	var gpFromCat: String = _gpPrefixFromCategory(gpDef.gpCategory)
	if gpFromCat != GP_FALLBACK_PREFIX:
		return gpFromCat
	if gpDef.gpTagPrefix != "":
		return gpSanitizePrefix(gpDef.gpTagPrefix)
	return GP_FALLBACK_PREFIX


# Resolve the prefix from THIS RULE's configuration only, ignoring gpCategoryPrefixes is NOT
# what this means — see gpPrefixFor(). Kept for callers that already resolved the rule.
# 仅依本规则的配置解析前缀（含义见 gpPrefixFor()）。保留给已自行解析出规则的调用方。
func gpPrefixFromSource(gpDef: GPSymbolDef) -> String:
	return gpPrefixFor(gpDef)


# Category table lookup, then the category's own first letter, then the fallback.
# 先查类别表，再取类别自身首字母，最后回落。
func _gpPrefixFromCategory(gpCategory: String) -> String:
	var gpKey: String = gpCategory.to_lower()
	var gpMapped: String = str(gpCategoryPrefixes.get(gpKey, ""))
	if gpMapped != "":
		return gpSanitizePrefix(gpMapped)
	var gpLetter: String = gpFirstAsciiLetter(gpCategory)
	if gpLetter != "":
		return gpLetter
	return GP_FALLBACK_PREFIX


# First ASCII letter of a string, upper-cased. "" when the string has none, which is the
# normal case for a category written entirely in Chinese.
# 字符串的首个 ASCII 字母（大写）。没有时返回 ""——全中文类别即属此情形。
static func gpFirstAsciiLetter(gpText: String) -> String:
	for gpI in range(gpText.length()):
		var gpC: String = gpText[gpI]
		if gpC.length() == 1 and gpC.to_upper() != gpC.to_lower():
			return gpC.to_upper()
	return ""


# Keep only [A-Za-z0-9]. A prefix lands in a filename-friendly, DCS-importable string, so
# spaces, dashes and punctuation are dropped rather than escaped.
# 仅保留 [A-Za-z0-9]。前缀会落进文件名友好、可导入 DCS 的串，故空格、连字符与标点
# 一律丢弃而非转义。
static func gpSanitizePrefix(gpRaw: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpRaw.length()):
		var gpC: String = gpRaw[gpI]
		var gpIsDigit: bool = gpC >= "0" and gpC <= "9"
		var gpIsAlpha: bool = (gpC.to_upper() != gpC.to_lower())
		if gpIsDigit or gpIsAlpha:
			gpOut += gpC
	return gpOut.to_upper()


# ---- rendering ----

# Render one tag. {seq:N} wins over gpDigits so a template can override the global padding.
# 渲染一个位号。{seq:N} 优先于 gpDigits，使模板可覆盖全局补零。
func gpFormat(gpPrefix: String, gpSeq: int, gpArea: String = "", gpSheet: String = "") -> String:
	var gpOut: String = gpTemplate
	# Longest-first: {seq:4} must be consumed before {seq} gets a chance to match.
	# 先长后短：{seq:4} 必须在 {seq} 有机会匹配前被消费掉。
	gpOut = _gpReplaceSeqWithWidth(gpOut, gpSeq)
	gpOut = gpOut.replace("{seq}", _gpPadded(gpSeq, gpDigits))
	gpOut = gpOut.replace("{prefix}", gpPrefix)
	gpOut = gpOut.replace("{area}", gpArea)
	gpOut = gpOut.replace("{sheet}", gpSheet)
	return gpOut


# Zero-pad a sequence number. / 给序号补零。
static func _gpPadded(gpSeq: int, gpDigits: int) -> String:
	var gpS: String = str(gpSeq)
	if gpDigits <= 0:
		return gpS
	while gpS.length() < gpDigits:
		gpS = "0" + gpS
	return gpS


# Replace every {seq:N} occurrence. Done by hand (no RegEx) so the rule module stays free of
# RegEx state and cannot fail to compile at runtime.
# 替换每一处 {seq:N}。手工实现（不用 RegEx），使本模块不持有正则状态、不会运行期编译失败。
static func _gpReplaceSeqWithWidth(gpText: String, gpSeq: int) -> String:
	var gpOut: String = ""
	var gpI: int = 0
	while gpI < gpText.length():
		if gpText.substr(gpI, 5) == "{seq:":
			var gpEnd: int = gpText.find("}", gpI)
			if gpEnd > gpI:
				var gpWidth: int = int(gpText.substr(gpI + 5, gpEnd - gpI - 5))
				gpOut += _gpPadded(gpSeq, gpWidth)
				gpI = gpEnd + 1
				continue
		gpOut += gpText[gpI]
		gpI += 1
	return gpOut


# ---- segmented rendering & checking (ADR-36 D4/D7) ----

# Whether this rule is segment-based rather than the legacy template string.
# 本规则是否基于分段（而非旧式模板串）。
func gpUsesSegments() -> bool:
	return not gpSegments.is_empty()


# Render a tag from a context. Context keys:
#   "seq"   : int, the sequence number (defaults to start + step)
#   "attrs" : Dictionary of instance / edge attributes (dn, medium, spec, insulation, area…)
# Returns "" when a segment cannot be produced legally (sequence overflow) — the caller must
# treat that as a refusal, never as an empty field.
# 按上下文渲染位号。上下文键见上。某段无法合法产出（序号溢出）时返回 "" —— 调用方必须
# 把它当作拒绝，绝不能当成空字段。
# NOTE: `gpStd` is deliberately UNTYPED — annotating it as GPProjectStandard would create a
# parse-time cycle (standard → presets → rule → segment) that Godot refuses to resolve.
# 注意：`gpStd` 刻意不写类型 —— 标注成 GPProjectStandard 会造成解析期循环
#（标准 → 预置 → 规则 → 分段），Godot 无法解析。
func gpRender(gpCtx: Dictionary = {}, gpStd = null) -> String:
	if not gpUsesSegments():
		# A template rule needs a prefix from the caller (the graph knows the symbol, this rule
		# does not). Returning "" beats returning "-1001" — a caller that forgot the prefix must
		# not get a plausible-looking wrong tag.
		# 模板规则需要调用方给出前缀（图知道是哪个图元，本规则不知道）。返回 "" 胜过返回 "-1001" ——
		# 忘了传前缀的调用方不该拿到一个「看着像对的」错位号。
		var gpPrefix: String = str(gpCtx.get("prefix", gpFixedPrefix))
		if gpPrefix == "":
			return ""
		return gpFormat(gpPrefix, int(gpCtx.get("seq", gpStart + gpStep)),
			str(gpCtx.get("area", "")), str(gpCtx.get("sheet", "")))
	var gpSeq: int = int(gpCtx.get("seq", gpStart + gpStep))
	var gpAttrs: Variant = gpCtx.get("attrs", {})
	var gpAttrMap: Dictionary = {}
	if gpAttrs is Dictionary:
		gpAttrMap = gpAttrs as Dictionary
	var gpLookup: Callable = Callable()
	if gpStd != null:
		gpLookup = Callable(gpStd, "gpCodeOf")
	var gpParts: Array[String] = []
	for gpSegRaw in gpSegments:
		var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
		if gpSeg == null:
			continue
		var gpValue: String = gpSeg.gpRenderValue(gpSeq, gpAttrMap, gpLookup)
		if gpValue == "":
			return ""
		gpParts.append(gpValue)
	return gpSeparator.join(gpParts)


# Compile this rule into a validator (regex + per-segment checks).
# 把本规则编译成校验器（正则 + 逐段检查）。
func gpCompile() -> GPTagPattern:
	return GPTagPattern.gpCompile(gpSegments, gpSeparator)


# Check a candidate tag for a LEGACY template rule. Only the default "{prefix}-{seq}" shape can
# be judged without guessing; anything else is accepted (a project that hand-crafted a template
# gets uniqueness checking only, never a false refusal).
# 校验**旧式模板规则**的候选位号。只有默认的 "{prefix}-{seq}" 形态可判；其它形态一律接受
#（手工构造过模板的工程至少还有唯一性校验，绝不误拒）。
func gpCheckTemplateTag(gpTag: String, gpPrefix: String, gpSeparatorIn: String = "-") -> Dictionary:
	var gpOut: Dictionary = {"ok": true, "index": -1, "key": "", "label": "",
		"expected": "", "detail": ""}
	if gpUsesSegments():
		return gpCheckTag(gpTag)
	if gpPrefix == "" or gpTemplate.find("{prefix}") < 0:
		return gpOut
	var gpText: String = gpTag.strip_edges()
	if gpText == "":
		gpOut["ok"] = false
		gpOut["detail"] = "位号为空"
		return gpOut
	var gpHead: String = gpPrefix + gpSeparatorIn
	if not gpText.to_upper().begins_with(gpHead.to_upper()):
		gpOut["ok"] = false
		gpOut["expected"] = gpHead + "数字"
		gpOut["detail"] = "应以 %s 开头（%s）" % [gpHead, gpPrefix]
		return gpOut
	var gpTail: String = gpText.substr(gpHead.length())
	if not gpTail.is_valid_int():
		gpOut["ok"] = false
		gpOut["expected"] = gpHead + "数字"
		gpOut["detail"] = "「%s」之后应为数字" % gpPrefix
		return gpOut
	return gpOut


# The sequence number carried by a rendered tag, or -1 when it cannot be read. Used by the line
# attribute panel: filling the attributes must re-render the SAME number, not burn a new one.
# 从已渲染的位号里读回序号；读不出时返回 -1。供管线属性面板使用：补属性应**重渲染同一个号**，
# 而不是再烧掉一个号。
func gpSequenceOf(gpTag: String) -> int:
	if not gpUsesSegments():
		var gpTail: String = gpTag.strip_edges()
		var gpCut: int = gpTail.rfind(gpSeparator)
		if gpCut < 0:
			return -1
		gpTail = gpTail.substr(gpCut + 1)
		return int(gpTail) if gpTail.is_valid_int() else -1
	var gpParts: PackedStringArray = gpTag.strip_edges().split(gpSeparator, true)
	if gpParts.size() != gpSegments.size():
		return -1
	for gpI in range(gpSegments.size()):
		var gpSeg: GPTagSegment = gpSegments[gpI]
		if gpSeg != null and gpSeg.gpSource == GPTagSegment.GPSource.GP_SEQ:
			var gpDigits: String = gpParts[gpI]
			return int(gpDigits) if gpDigits.is_valid_int() else -1
	return -1


# Check a candidate tag against this rule. Returns GPITagPattern.gpCheck()'s dictionary.
# 按本规则校验一个候选位号。返回 GPTagPattern.gpCheck() 的字典。
func gpCheckTag(gpTag: String) -> Dictionary:
	if not gpUsesSegments():
		# The legacy template cannot be checked positionally; accept anything non-empty so a
		# pre-ADR-36 project keeps working until it migrates.
		# 旧式模板无法按段校验；只要非空就接受，使 ADR-36 之前的工程在迁移前继续可用。
		var gpOk: bool = gpTag.strip_edges() != ""
		return {"ok": gpOk, "index": -1, "key": "", "label": "", "expected": "",
			"detail": "" if gpOk else "位号为空"}
	return gpCompile().gpCheck(gpTag)


# Result-typed wrapper around gpCheckTag(), for command-layer refusals.
# gpCheckTag() 的结果类型包装，供命令层拒绝时使用。
func gpValidateTag(gpTag: String) -> GPIOResult:
	var gpChk: Dictionary = gpCheckTag(gpTag)
	if bool(gpChk.get("ok", false)):
		return GPIOResult.gpSuccess()
	return GPIOResult.gpFailure("tag.err_rule", "tag.err_rule", str(gpChk.get("detail", "")))


# ---- validation ----

# Check the rule. Returns a failure GPIOResult naming the first problem found; the UI shows
# the message live and disables OK while the rule is invalid.
# 校验规则。返回指出首个问题的失败结果；界面实时显示提示并在非法态下禁用「确定」。
func gpValidate() -> GPIOResult:
	if gpUsesSegments():
		return _gpValidateSegments()
	if gpTemplate.find("{seq}") < 0 and not _gpHasWidthSeq():
		return GPIOResult.gpFailure("tag_rule.no_seq", "tag_rule.err_no_seq", gpTemplate)
	if gpStart < 0:
		return GPIOResult.gpFailure("tag_rule.bad_start", "tag_rule.err_bad_start", str(gpStart))
	if gpStep < 1:
		return GPIOResult.gpFailure("tag_rule.bad_step", "tag_rule.err_bad_step", str(gpStep))
	if gpDigits < 0 or gpDigits > GP_MAX_DIGITS:
		return GPIOResult.gpFailure("tag_rule.bad_digits", "tag_rule.err_bad_digits", str(gpDigits))
	if gpPrefixSource == GPPrefixSource.GP_FIXED and gpFixedPrefix == "":
		return GPIOResult.gpFailure("tag_rule.bad_fixed", "tag_rule.err_bad_fixed", "")
	return GPIOResult.gpSuccess()


# Validate the segment declarations: exactly one counter, legal widths, a fallback that fits,
# and no literal that contains the separator.
# 校验分段声明：恰有一个序号段、宽度合法、兜底自身合规、且没有含分隔符的字面量。
func _gpValidateSegments() -> GPIOResult:
	if gpSeparator == "":
		return GPIOResult.gpFailure("tag_seg.no_separator", "tag_seg.err_no_separator", "")
	if gpStart < 0:
		return GPIOResult.gpFailure("tag_rule.bad_start", "tag_rule.err_bad_start", str(gpStart))
	if gpStep < 1:
		return GPIOResult.gpFailure("tag_rule.bad_step", "tag_rule.err_bad_step", str(gpStep))
	var gpSeenKeys: Dictionary = {}
	var gpSeqCount: int = 0
	for gpSegRaw in gpSegments:
		var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
		if gpSeg == null:
			return GPIOResult.gpFailure("tag_seg.bad_segment", "tag_seg.err_bad_segment", "")
		if gpSeenKeys.has(gpSeg.gpKey):
			return GPIOResult.gpFailure("tag_seg.duplicate_key", "tag_seg.err_duplicate_key",
				gpSeg.gpKey)
		gpSeenKeys[gpSeg.gpKey] = true
		if gpSeg.gpSource == GPTagSegment.GPSource.GP_SEQ:
			gpSeqCount += 1
		var gpOne: GPIOResult = gpSeg.gpValidate(gpSeparator)
		if not gpOne.gpIsOk():
			return gpOne
	if gpSeqCount != 1:
		return GPIOResult.gpFailure("tag_seg.seq_count", "tag_seg.err_seq_count",
			str(gpSeqCount))
	return GPIOResult.gpSuccess()


# Whether the template carries a {seq:N} placeholder.
# 模板是否含 {seq:N} 占位符。
func _gpHasWidthSeq() -> bool:
	var gpI: int = gpTemplate.find("{seq:")
	return gpI >= 0 and gpTemplate.find("}", gpI) > gpI


# ---- persistence ----

func gpToDict() -> Dictionary:
	var gpOut: Dictionary = {
		"template": gpTemplate,
		"start": gpStart,
		"step": gpStep,
		"digits": gpDigits,
		"prefix_source": int(gpPrefixSource),
		"fixed_prefix": gpFixedPrefix,
		"category_prefixes": gpCategoryPrefixes.duplicate(),
		"symbol_prefixes": gpSymbolPrefixes.duplicate(),
	}
	# Segments are written ONLY when used, so a legacy rule keeps its exact v1 key set
	# (ADR-36 D12: reopening an old archive must reproduce its bytes).
	# 仅在使用时才写分段键，使旧式规则保持完全相同的 v1 键集
	#（ADR-36 D12：重开旧存档必须复现其字节）。
	if gpUsesSegments():
		var gpSegsOut: Array = []
		for gpSegRaw in gpSegments:
			var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
			if gpSeg != null:
				gpSegsOut.append(gpSeg.gpToDict())
		gpOut["separator"] = gpSeparator
		gpOut["segments"] = gpSegsOut
	return gpOut


# Tolerant read: every key falls back to the factory value, so a rule saved by a future
# version with more keys still loads here.
# 宽容读取：每个键都回落到出厂值，故将来的版本存下的「键更多」的规则仍可在本版载入。
static func gpFromDict(gpD: Dictionary) -> GPTagRule:
	var gpR: GPTagRule = GPTagRule.new()
	if gpD.is_empty():
		return gpDefault()
	gpR.gpTemplate = str(gpD.get("template", GP_DEFAULT_TEMPLATE))
	gpR.gpStart = int(gpD.get("start", GP_DEFAULT_START))
	gpR.gpStep = int(gpD.get("step", GP_DEFAULT_STEP))
	gpR.gpDigits = int(gpD.get("digits", GP_DEFAULT_DIGITS))
	gpR.gpPrefixSource = int(gpD.get("prefix_source", GPPrefixSource.GP_BY_CATEGORY)) as GPPrefixSource
	gpR.gpFixedPrefix = str(gpD.get("fixed_prefix", ""))
	var gpCats: Dictionary = gpD.get("category_prefixes", {})
	gpR.gpCategoryPrefixes = gpCats.duplicate() if gpCats is Dictionary else {}
	var gpSyms: Dictionary = gpD.get("symbol_prefixes", {})
	gpR.gpSymbolPrefixes = gpSyms.duplicate() if gpSyms is Dictionary else {}
	gpR.gpSeparator = str(gpD.get("separator", "-"))
	var gpSegsIn: Variant = gpD.get("segments", null)
	if gpSegsIn is Array:
		for gpSegRaw in (gpSegsIn as Array):
			if gpSegRaw is Dictionary:
				gpR.gpSegments.append(GPTagSegment.gpFromDict(gpSegRaw as Dictionary))
	return gpR
