class_name GPTagPattern
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# A compiled segmented rule: the validator half of ADR-36 D4/D7.
# 编译后的分段规则：ADR-36 D4/D7 的「校验器」那一半。
#
# TWO OUTPUTS, ONE DECLARATION / 一条声明，两个产物：
# `gpRegexText()` is the whole-tag regex (useful for bulk checks, DRC and export gates);
# `gpCheck()` splits the candidate on the separator and reports WHICH segment failed and what
# it expected. The second one is what a user sees when their hand-typed tag is refused, so it
# must never be a vague "format error".
# `gpRegexText()` 是整号正则（适合批量检查、DRC 与导出闸门）；`gpCheck()` 按分隔符切开候选，
# 报出**第几段**失败、期望什么。后者正是用户手打位号被拒时看到的东西，绝不能是笼统的「格式错误」。
#
# WHY SPLIT INSTEAD OF MATCHING GROUPS / 为何切开而不是用捕获组：
# segments may be variable width (2–3 letters), so capture-group indexes drift and a wrong
# width turns into "segment 2 ate segment 3". Splitting by the separator is exact as long as
# no literal/fallback contains the separator — which GPTagSegment.gpValidate() enforces.
# 段可以是变宽的（2–3 个字母），捕获组下标会漂移，宽度一错就变成「第 2 段吃掉了第 3 段」。
# 按分隔符切开是精确的 —— 前提是字面量与兜底都不含分隔符，而这由 GPTagSegment.gpValidate() 保证。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpSeparator: String = "-"
var gpSegments: Array[GPTagSegment] = []

# Compiled regex text, built once in gpCompile().
# 编译出的正则文本，在 gpCompile() 中一次构建。
var _gpRegexText: String = ""


# Compile a segment list. Never fails: an invalid rule is reported by GPTagRule.gpValidate(),
# which must be called before relying on the pattern.
# 编译段列表。不会失败：非法规则由 GPTagRule.gpValidate() 报告，使用图案前应先调它。
static func gpCompile(gpSegmentsIn: Array[GPTagSegment], gpSeparatorIn: String) -> GPTagPattern:
	var gpP: GPTagPattern = GPTagPattern.new()
	gpP.gpSeparator = gpSeparatorIn
	gpP.gpSegments = gpSegmentsIn.duplicate()
	gpP._gpRegexText = gpP._gpBuildRegex()
	return gpP


# The whole-tag regular expression.
# 整号正则。
func gpRegexText() -> String:
	return _gpRegexText


# Check one candidate tag. Returns a fresh dictionary:
#   {ok, index, key, label, expected, detail}
# `index` is the 0-based segment index that failed (-1 for "wrong number of segments" or an
# empty tag); `detail` is the ready-to-show sentence.
# 校验一个候选位号。返回新字典（见上）。index 是失败段的 0 基下标（-1 表示段数不符或空位号）；
# detail 是可直接显示的整句。
func gpCheck(gpTag: String) -> Dictionary:
	var gpOut: Dictionary = {
		"ok": false, "index": -1, "key": "", "label": "", "expected": "", "detail": "",
	}
	var gpText: String = gpTag.strip_edges()
	if gpText == "":
		gpOut["detail"] = "位号为空"
		return gpOut
	var gpParts: PackedStringArray = gpText.split(gpSeparator, true)
	if gpParts.size() != gpSegments.size():
		gpOut["detail"] = "段数不符：应为 %d 段，实际 %d 段" % [gpSegments.size(),
			gpParts.size()]
		return gpOut
	for gpI in range(gpSegments.size()):
		var gpSeg: GPTagSegment = gpSegments[gpI]
		if gpSeg == null:
			continue
		var gpPart: String = gpParts[gpI]
		if gpSeg.gpCheckPart(gpPart):
			continue
		gpOut["index"] = gpI
		gpOut["key"] = gpSeg.gpKey
		gpOut["label"] = gpSeg.gpLabel
		gpOut["expected"] = gpSeg.gpExpectedText()
		gpOut["detail"] = "第 %d 段（%s）：应为 %s" % [gpI + 1, gpSeg.gpLabel,
			gpSeg.gpExpectedText()]
		return gpOut
	gpOut["ok"] = true
	gpOut["detail"] = ""
	return gpOut


# Build the whole-tag regex from the segments.
# 由各段构建整号正则。
func _gpBuildRegex() -> String:
	var gpParts: PackedStringArray = PackedStringArray()
	for gpSegRaw in gpSegments:
		var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
		if gpSeg == null:
			continue
		gpParts.append(_gpSegmentRegex(gpSeg))
	# Anchored: the pattern must describe the WHOLE tag, otherwise RegEx.search() would accept
	# "150-CWR-0007-A1A-P-EXTRA" as a prefix match — a validator that passes extra segments is
	# worse than no validator.
	# 加锚点：图案必须描述**整个**位号，否则 RegEx.search() 会把 "…-P-EXTRA" 当作前缀匹配
	# 而放行 —— 一个会放过多余段的校验器比没有校验器更糟。
	return "^%s$" % _gpEscape(gpSeparator).join(gpParts)


# Regex for one segment.
# 单段的正则。
func _gpSegmentRegex(gpSeg: GPTagSegment) -> String:
	match gpSeg.gpSource:
		GPTagSegment.GPSource.GP_FIXED:
			return _gpEscape(gpSeg.gpLiteral)
		GPTagSegment.GPSource.GP_SEQ:
			return "\\d{%d}" % gpSeg.gpWidth
		GPTagSegment.GPSource.GP_ATTR_DIGITS:
			return "\\d{%d,}" % maxi(1, gpSeg.gpWidth)
		GPTagSegment.GPSource.GP_ATTR, GPTagSegment.GPSource.GP_CODE_TABLE:
			return "%s%s" % [_gpCharsetClass(gpSeg.gpCharset), _gpQuantifier(gpSeg)]
	return ".+"


# Character class for a charset. GP_ANY excludes the separator and whitespace, matching the
# render-time filter.
# 字符集对应的字符类。GP_ANY 排除分隔符与空白，与渲染期的过滤一致。
func _gpCharsetClass(gpCharset: GPTagSegment.GPCharset) -> String:
	match gpCharset:
		GPTagSegment.GPCharset.GP_DIGIT:
			return "[0-9]"
		GPTagSegment.GPCharset.GP_ALPHA:
			return "[A-Za-z]"
		GPTagSegment.GPCharset.GP_ALNUM:
			return "[A-Za-z0-9]"
	return "[^%s\\s]" % _gpEscape(gpSeparator)


# Quantifier for a variable-width segment.
# 变长段的量词。
func _gpQuantifier(gpSeg: GPTagSegment) -> String:
	if gpSeg.gpMin > 0 and gpSeg.gpMax > 0:
		return "{%d,%d}" % [gpSeg.gpMin, gpSeg.gpMax]
	if gpSeg.gpMin > 0:
		return "{%d,}" % gpSeg.gpMin
	if gpSeg.gpMax > 0:
		return "{1,%d}" % gpSeg.gpMax
	return "+"


# Escape regex metacharacters in a literal piece (no RegEx.escape in GDScript).
# 转义字面量中的正则元字符（GDScript 没有 RegEx.escape）。
static func _gpEscape(gpText: String) -> String:
	var gpOut: String = ""
	var gpSpecial: String = "\\.^$|?*+()[]{}"
	for gpI in range(gpText.length()):
		var gpC: String = gpText[gpI]
		if gpSpecial.find(gpC) >= 0:
			gpOut += "\\"
		gpOut += gpC
	return gpOut
