class_name GPTagRule
extends RefCounted
# Copyright © 2026 Jonson Wang
# One numbering rule for process tags (e.g. "P-1001").
# 位号编号规则（如 "P-1001"）的单条定义。
#
# A rule answers three questions / 一条规则回答三个问题:
#   1. Where does the PREFIX come from?  (category table / symbol table / one fixed string)
#      前缀从哪来？（类别表 / 图元表 / 固定串）
#   2. How is the number rendered?       (start / step / zero padding / template)
#      序号如何呈现？（起始 / 步长 / 补零 / 模板）
#   3. What happens on a collision?      (reject and tell / silently take the next free one)
#      撞号怎么办？（拒绝并提示 / 自动顺延到下一个空号）
#
# WHY THIS IS NOT GPTagGen / 为何不是 GPTagGen:
#   GPTagGen owns the PIPE numbering ("PL-1001") and deliberately keeps its high-water marks in
#   gpGraph.gpMeta, because pipe numbers predate this rule system and must keep working byte for
#   byte. GPTagRule is the EQUIPMENT side and is user-editable per project. They share the
#   "{prefix}-{seq}" shape on purpose so a user reading the sheet sees one consistent style.
#   GPTagGen 负责「管线号」（"PL-1001"），其水位线刻意留在 gpGraph.gpMeta——管线号早于本规则
#   系统且必须逐字节保持原行为。GPTagRule 是「设备位号」侧，按工程可由用户编辑。二者刻意
#   共用 "{prefix}-{seq}" 形态，使图纸上的编号风格一致。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Where the prefix comes from. / 前缀来源。
enum GPPrefixSource {
	GP_BY_CATEGORY,  # look up gpCategoryPrefixes by gpCategory / 按 gpCategory 查 gpCategoryPrefixes
	GP_BY_SYMBOL,    # look up gpSymbolPrefixes by symbol id / 按图元 id 查 gpSymbolPrefixes
	GP_FIXED,        # always gpFixedPrefix / 恒用 gpFixedPrefix
}

# What to do when the next number is already taken. / 下一个号已被占用时怎么办。
enum GPConflictPolicy {
	GP_REJECT,    # refuse and name the occupant / 拒绝并指出占用者
	GP_AUTO_NEXT, # keep scanning for a free number / 继续找空号
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
#   gpCategoryPrefixes is PROJECT configuration the user edits in the numbering dialog;
#   gpTagPrefix is baked into the library at generation time. When a project says "pumps are
#   PP here", that is the more specific intent and must win — otherwise editing the table
#   would appear to do nothing.
#   gpCategoryPrefixes 是用户在编号对话框里编辑的**工程**配置；gpTagPrefix 是生成时烘进
#   图元库的默认值。当工程说「本工程泵为 PP」，这是更具体的意图，必须胜出——
#   否则编辑该表会看起来毫无作用。
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
# what this means — see gpPrefixFor. Kept for callers that already resolved the rule.
# 仅依本规则的配置解析前缀（含义见 gpPrefixFor）。保留给已自行解析出规则的调用方。
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


# ---- validation ----

# Check the rule. Returns a failure GPIOResult naming the first problem found; the UI shows
# the message live and disables OK while the rule is invalid.
# 校验规则。返回指出首个问题的失败结果；界面实时显示提示并在非法态下禁用「确定」。
func gpValidate() -> GPIOResult:
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


# Whether the template carries a {seq:N} placeholder.
# 模板是否含 {seq:N} 占位符。
func _gpHasWidthSeq() -> bool:
	var gpI: int = gpTemplate.find("{seq:")
	return gpI >= 0 and gpTemplate.find("}", gpI) > gpI


# ---- persistence ----

func gpToDict() -> Dictionary:
	return {
		"template": gpTemplate,
		"start": gpStart,
		"step": gpStep,
		"digits": gpDigits,
		"prefix_source": int(gpPrefixSource),
		"fixed_prefix": gpFixedPrefix,
		"category_prefixes": gpCategoryPrefixes.duplicate(),
		"symbol_prefixes": gpSymbolPrefixes.duplicate(),
	}


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
	return gpR
