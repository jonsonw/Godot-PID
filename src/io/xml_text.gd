class_name GPXmlText
extends RefCounted

# XML escaping, number formatting and indentation — the SINGLE place where DEXPI XML text is
# assembled. Every DEXPI writer routes its strings through here.
# XML 转义、数字格式化与缩进 —— 组装 DEXPI XML 文本的**唯一**场所。
# 所有 DEXPI 写出器的字符串都经此流出。
#
# WHY ONE PLACE / 为何单点：
# hand-built strings are where the spec's quietest rules get broken: an unescaped `&` in a
# tag name, a `Value=""` written for null, or a language tag left as `zh-CN`. Each of those
# produces a file that LOOKS fine and is rejected (or silently misread) downstream. With one
# builder, each rule is enforced once and can be asserted once.
# 手写字符串正是规范里那些「最安静的规则」被破坏的地方：标签名里未转义的 `&`、
# 为 null 写出 `Value=""`、语言标签留成 `zh-CN`。这些都会产出**看起来没问题**、
# 却在下游被拒收（或静默误读）的文件。单点构建后，每条规则只强制一次、也只需断言一次。
#
# Depends on nothing but GDScript: safe for headless use from io.
# 只依赖 GDScript，io 层 headless 使用安全。

# Escaping order matters: `&` must be replaced FIRST, or the replacements themselves get
# re-escaped into `&amp;amp;`.
# 转义顺序有讲究：`&` 必须**最先**替换，否则替换产物自身会被再次转义成 `&amp;amp;`。
const GP_ESCAPES: Array[Array] = [
	["&", "&amp;"],
	["<", "&lt;"],
	[">", "&gt;"],
	["\"", "&quot;"],
	["'", "&apos;"],
]

# Maximum decimals for a serialised number. Three is enough for 0..1 normalised colour
# (0.498) and for millimetre geometry, while keeping files readable.
# 序列化数字的最大小数位。3 位足以表达 0..1 归一化颜色（0.498）与毫米级几何，
# 同时保持文件可读。
const GP_MAX_DECIMALS: int = 3


# Escape XML special characters. / 转义 XML 特殊字符。
static func gpEscape(gpText: String) -> String:
	var gpOut: String = gpText
	for gpPair in GP_ESCAPES:
		var gpRow: Array = gpPair as Array
		gpOut = gpOut.replace(str(gpRow[0]), str(gpRow[1]))
	return gpOut


# Format a number for XML: no trailing zeros, no "-0", finite or "0".
# 数字格式化：无尾随零、无 "-0"、非有限值一律 "0"。
# WHY NO TRAILING ZEROS / 为何去掉尾随零：the spec's own examples read `Y="-40"` and
# `G="0.498"`, not `Y="-40.000"`. Matching the examples keeps diffs readable.
# 规范自身示例写作 `Y="-40"` 与 `G="0.498"`，而非 `Y="-40.000"`。与示例一致使 diff 可读。
static func gpNum(gpValue: float, gpDecimals: int = GP_MAX_DECIMALS) -> String:
	if not is_finite(gpValue):
		return "0"
	var gpOut: String = String.num(gpValue, gpDecimals)
	while gpOut.contains(".") and gpOut.ends_with("0"):
		gpOut = gpOut.substr(0, gpOut.length() - 1)
	if gpOut.ends_with("."):
		gpOut = gpOut.substr(0, gpOut.length() - 1)
	# A flipped zero must serialise as "0", never "-0": "-0" is legal XML but a red flag to
	# every reader, and it appears constantly because Y=0 is the sheet centre line.
	# 翻转后的零必须序列化为 "0" 而非 "-0"："-0" 虽合法，却会让每个阅读者起疑，
	# 而由于 Y=0 是图纸中线，它会频繁出现。
	if gpOut == "-0":
		gpOut = "0"
	return gpOut


# Trim a language tag to the two letters DEXPI permits (§4.5 hard constraint).
# THIS IS THE SINGLE IMPLEMENTATION POINT for the rule — never inline `.substr(0, 2)`.
# 将语言标签截断为 DEXPI 允许的**恰好两字母**（§4.5 硬约束）。
# 这是该规则的**唯一实现点** —— 绝不内联 `.substr(0, 2)`。
# `en` / `de` / `zh` are valid; `en-US` / `zh-CN` / `de-CH-1996` are NOT.
# `en` / `de` / `zh` 合法；`en-US` / `zh-CN` / `de-CH-1996` **非法**。
static func gpLang2(gpTag: String) -> String:
	var gpLow: String = gpTag.strip_edges().to_lower()
	if gpLow.is_empty():
		return ""
	if gpLow.length() <= 2:
		return gpLow
	return gpLow.substr(0, 2)


# Indentation of gpLevel steps (two spaces each).
# gpLevel 级缩进（每级两个空格）。
static func gpIndent(gpLevel: int) -> String:
	if gpLevel <= 0:
		return ""
	return "  ".repeat(gpLevel)


# `name="value"` with the value escaped. Returns "" for an empty value: the DEXPI null rule
# says OMIT the attribute entirely, never write `name=""` (§6.5 风险 2).
# `name="value"`，值已转义。值为空时返回 "" —— DEXPI 的 null 规则要求**完全省略**该属性，
# 绝不写 `name=""`（§6.5 风险 2）。
static func gpAttr(gpName: String, gpValue: String) -> String:
	if gpValue.is_empty():
		return ""
	return gpName + "=\"" + gpEscape(gpValue) + "\""


# Join non-empty attribute fragments with a single space.
# 用单个空格拼接非空属性片段。
static func gpAttrs(gpParts: Array[String]) -> String:
	var gpOut: String = ""
	for gpPart in gpParts:
		if gpPart.is_empty():
			continue
		if not gpOut.is_empty():
			gpOut += " "
		gpOut += gpPart
	return gpOut


# Opening tag with attributes, e.g. `<Equipment ID="p1" ComponentClass="Pump">`.
# 带属性的起始标签，如 `<Equipment ID="p1" ComponentClass="Pump">`。
static func gpOpen(gpName: String, gpAttrsText: String, gpLevel: int) -> String:
	var gpOut: String = gpIndent(gpLevel) + "<" + gpName
	if not gpAttrsText.is_empty():
		gpOut += " " + gpAttrsText
	return gpOut + ">"


# Closing tag. / 结束标签。
static func gpClose(gpName: String, gpLevel: int) -> String:
	return gpIndent(gpLevel) + "</" + gpName + ">"


# Self-closing tag, e.g. `<Coordinate X="10" Y="-20"/>`.
# 自闭合标签，如 `<Coordinate X="10" Y="-20"/>`。
static func gpSelf(gpName: String, gpAttrsText: String, gpLevel: int) -> String:
	var gpOut: String = gpIndent(gpLevel) + "<" + gpName
	if not gpAttrsText.is_empty():
		gpOut += " " + gpAttrsText
	return gpOut + "/>"


# Element with text content on one line. / 单行文本内容的元素。
static func gpText(gpName: String, gpAttrsText: String, gpContent: String, gpLevel: int) -> String:
	return gpOpen(gpName, gpAttrsText, gpLevel) + gpEscape(gpContent) + "</" + gpName + ">"


# XML declaration line. / XML 声明行。
static func gpDeclaration() -> String:
	return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
