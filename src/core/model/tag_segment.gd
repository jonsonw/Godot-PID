class_name GPTagSegment
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# One segment of a composite tag rule (ADR-36 D4) — e.g. the 介质代码 part of
# `150-CWR-0007-A1A-N`.
# 分段位号规则（ADR-36 D4）中的**一段** —— 如 `150-CWR-0007-A1A-N` 里的介质代码。
#
# WHY SEGMENTS / 为何要分段：
# the user's line designation is not one counter, it is five ordered fields (size, service,
# number, material, insulation). A template string can only concatenate placeholders; it
# cannot say "this field is 2–3 letters from the medium code table, and when the medium is
# unknown fall back to XX". A segment can, and the same declaration doubles as the validator
# that refuses a hand-typed tag that does not fit (ADR-36 D7).
# 用户的管线代号不是"一个计数器"，而是五个有序字段（管径、介质、流水号、材料、保温）。模板串只能拼
# 占位符，说不出「这一段是介质代号表里的 2–3 个字母，介质未知时回落 XX」。分段可以，而且同一条声明
# 同时就是校验器，用来拒绝不合规的手工位号（ADR-36 D7）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Where a segment's value comes from. / 一段的取值来源。
enum GPSource {
	GP_FIXED,        # a literal (e.g. "SP" prefix) / 字面量（如特殊件前缀 SP）
	GP_SEQ,          # the sequence counter, zero padded to gpWidth / 序号，按 gpWidth 左补零
	GP_ATTR,         # the attribute text, filtered by charset / 属性原文，按字符集过滤
	GP_ATTR_DIGITS,  # the DIGITS of an attribute (DN150 -> 150), padded to gpWidth / 属性中的数字
	GP_CODE_TABLE,   # attribute value looked up in a project code table / 属性值查项目代号表
}

# Allowed characters. Anything else is dropped at render time and rejected at validation time.
# 允许的字符。渲染时丢弃其它字符，校验时拒绝。
enum GPCharset {
	GP_ANY,    # anything but the separator / 除分隔符外任意
	GP_DIGIT,  # 0-9
	GP_ALPHA,  # A-Z
	GP_ALNUM,  # A-Z 0-9
}

# Longest sequence width we accept. Beyond 12 digits the tag stops being readable and the
# counter can no longer overflow in any realistic project.
# 接受的序号宽度上限。超过 12 位位号不可读，现实工程也不可能把计数器跑溢出。
const GP_MAX_SEQ_WIDTH: int = 12

# Segment key (stable, used in error messages and by the dialog).
# 段键（稳定；用于错误消息与对话框）。
var gpKey: String = ""

# Attribute keys reserved by the edge/sheet model; a rule segment must not write them.
# 边/图纸模型保留的属性键；规则段不得写入这些键。
const GP_RESERVED_ATTR_KEYS: Array[String] = ["tag", "kind", "signal_type", "show_arrow", "show_tag"]


# The attribute key this segment reads. Normally gpAttr; but a segment saved with a blank or
# reserved attr (a common hand-edit / early-editor mistake) falls back to its own gpKey, so the
# field is still visible and the rendered value still moves with the panel.
# 本段读取的属性键。正常情况下是 gpAttr；但空键或保留键（常见的手改 / 早期编辑器错误）
# 回退到段自身的 gpKey，使字段仍可见、渲染值仍随面板变化。
func gpAttrKey() -> String:
	if gpAttr != "" and not GP_RESERVED_ATTR_KEYS.has(gpAttr):
		return gpAttr
	if gpKey != "":
		return gpKey
	return gpAttr

# Human label (fallback when i18n is unavailable).
# 人类可读名称（i18n 不可用时的回退）。
var gpLabel: String = ""

var gpSource: GPSource = GPSource.GP_FIXED

# GP_FIXED literal. / GP_FIXED 的字面量。
var gpLiteral: String = ""

# Attribute key on the instance / edge (dn, medium, spec, insulation, …).
# 实例 / 边上的属性键（dn、medium、spec、insulation…）。
var gpAttr: String = ""

# Code table id for GP_CODE_TABLE (medium / material / insulation / …).
# GP_CODE_TABLE 的代号表 id（medium / material / insulation…）。
var gpTable: String = ""

# Exact width for GP_SEQ; MINIMUM digit count for GP_ATTR_DIGITS; 0 = unbounded.
# GP_SEQ 的定宽；GP_ATTR_DIGITS 的**最少**位数；0 = 不限。
var gpWidth: int = 0

# Variable-width bounds for GP_ATTR / GP_CODE_TABLE (gpMax 0 = unbounded).
# GP_ATTR / GP_CODE_TABLE 的变长范围（gpMax 0 = 不限）。
var gpMin: int = 0
var gpMax: int = 0

var gpPad: String = "0"

var gpCharset: GPCharset = GPCharset.GP_ALNUM

# Used when the attribute is empty / not in the table. MUST itself satisfy the segment's
# charset and width — a fallback that breaks the rule would make every unknown value illegal.
# 属性为空 / 表里查不到时使用。它自己必须满足本段的字符集与宽度 —— 破规的兜底会让每个未知值都非法。
var gpFallback: String = ""

# Upper-case the value. Tags are compared upper-cased anyway; storing the render upper-case
# keeps the sheet consistent.
# 转大写。位号比较本就大写；渲染也大写可让图纸保持一致。
var gpUpper: bool = true


# ==================== factories / 构造 ====================

# A literal segment (a fixed prefix, a fixed separator piece).
# 字面量段（固定前缀、固定的分隔片段）。
static func gpFixed(gpKeyIn: String, gpLabelIn: String, gpLiteralIn: String) -> GPTagSegment:
	var gpS: GPTagSegment = GPTagSegment.new()
	gpS.gpKey = gpKeyIn
	gpS.gpLabel = gpLabelIn
	gpS.gpSource = GPSource.GP_FIXED
	gpS.gpLiteral = gpLiteralIn
	return gpS


# The counter segment, zero padded to width digits.
# 序号段，左补零到 width 位。
static func gpSeq(gpKeyIn: String, gpLabelIn: String, gpWidthIn: int,
		gpPadIn: String = "0") -> GPTagSegment:
	var gpS: GPTagSegment = GPTagSegment.new()
	gpS.gpKey = gpKeyIn
	gpS.gpLabel = gpLabelIn
	gpS.gpSource = GPSource.GP_SEQ
	gpS.gpWidth = gpWidthIn
	gpS.gpPad = gpPadIn
	gpS.gpCharset = GPCharset.GP_DIGIT
	return gpS


# The digits of an attribute (DN150 -> 150), at least `gpWidthIn` digits.
# 属性里的数字（DN150 -> 150），至少 gpWidthIn 位。
static func gpAttrDigits(gpKeyIn: String, gpLabelIn: String, gpAttrIn: String,
		gpWidthIn: int, gpFallbackIn: String) -> GPTagSegment:
	var gpS: GPTagSegment = GPTagSegment.new()
	gpS.gpKey = gpKeyIn
	gpS.gpLabel = gpLabelIn
	gpS.gpSource = GPSource.GP_ATTR_DIGITS
	gpS.gpAttr = gpAttrIn
	gpS.gpWidth = gpWidthIn
	gpS.gpCharset = GPCharset.GP_DIGIT
	gpS.gpFallback = gpFallbackIn
	return gpS


# Attribute text filtered by charset, bounded by min/max width.
# 按字符集过滤的属性原文，长度受 min/max 约束。
static func gpAttrText(gpKeyIn: String, gpLabelIn: String, gpAttrIn: String, gpMinIn: int,
		gpMaxIn: int, gpCharsetIn: GPCharset, gpFallbackIn: String) -> GPTagSegment:
	var gpS: GPTagSegment = GPTagSegment.new()
	gpS.gpKey = gpKeyIn
	gpS.gpLabel = gpLabelIn
	gpS.gpSource = GPSource.GP_ATTR
	gpS.gpAttr = gpAttrIn
	gpS.gpMin = gpMinIn
	gpS.gpMax = gpMaxIn
	gpS.gpCharset = gpCharsetIn
	gpS.gpFallback = gpFallbackIn
	return gpS


# Attribute value resolved through a project code table, bounded by min/max width.
# 属性值经项目代号表解析，长度受 min/max 约束。
static func gpCode(gpKeyIn: String, gpLabelIn: String, gpTableIn: String, gpAttrIn: String,
		gpMinIn: int, gpMaxIn: int, gpCharsetIn: GPCharset,
		gpFallbackIn: String) -> GPTagSegment:
	var gpS: GPTagSegment = GPTagSegment.new()
	gpS.gpKey = gpKeyIn
	gpS.gpLabel = gpLabelIn
	gpS.gpSource = GPSource.GP_CODE_TABLE
	gpS.gpTable = gpTableIn
	gpS.gpAttr = gpAttrIn
	gpS.gpMin = gpMinIn
	gpS.gpMax = gpMaxIn
	gpS.gpCharset = gpCharsetIn
	gpS.gpFallback = gpFallbackIn
	return gpS


# ==================== rendering / 渲染 ====================

# Render this segment's value. Returns "" when the value cannot be produced legally (sequence
# overflow) — the caller must treat that as a refusal, never as an empty field.
# `gpCodeLookup(table_id, raw) -> String` resolves a code-table entry; an invalid Callable means
# "no tables available", which falls back to the placeholder.
# 渲染本段的值。无法合法产出时返回 ""（序号溢出）—— 调用方必须把它当作拒绝，绝不当成空字段。
# `gpCodeLookup(table_id, raw) -> String` 解析代号表条目；无效 Callable 意为「没有可用的表」，
# 此时回落到占位代号。
func gpRenderValue(gpSeq: int, gpAttrs: Dictionary,
		gpCodeLookup: Callable = Callable()) -> String:
	match gpSource:
		GPSource.GP_FIXED:
			return gpLiteral
		GPSource.GP_SEQ:
			var gpDigits: String = str(gpSeq)
			if gpWidth > 0 and gpDigits.length() > gpWidth:
				return ""
			return _gpPadLeft(gpDigits, gpWidth, gpPad)
		GPSource.GP_ATTR_DIGITS:
			var gpNum: String = _gpDigitsOf(str(gpAttrs.get(gpAttrKey(), "")))
			if gpNum == "":
				gpNum = gpFallback
			return _gpPadLeft(gpNum, gpWidth, gpPad)
		GPSource.GP_ATTR:
			var gpRaw: String = _gpFilter(str(gpAttrs.get(gpAttrKey(), "")))
			if gpRaw == "":
				return _gpFilter(gpFallback)
			return _gpClamp(gpRaw)
		GPSource.GP_CODE_TABLE:
			var gpCode: String = ""
			if gpCodeLookup.is_valid():
				gpCode = str(gpCodeLookup.call(gpTable, str(gpAttrs.get(gpAttrKey(), ""))))
			gpCode = _gpFilter(gpCode)
			if gpCode == "":
				return _gpFilter(gpFallback)
			return _gpClamp(gpCode)
	return ""


# ==================== validation / 校验 ====================

# Whether a candidate SEGMENT text fits this segment's charset and width.
# 候选**段文本**是否符合本段的字符集与宽度。
func gpCheckPart(gpPart: String) -> bool:
	if gpPart == "":
		return false
	var gpText: String = gpPart.to_upper()
	match gpSource:
		GPSource.GP_FIXED:
			return gpText == gpLiteral.to_upper()
		GPSource.GP_SEQ:
			return _gpIsDigits(gpText) and gpText.length() == gpWidth
		GPSource.GP_ATTR_DIGITS:
			return _gpIsDigits(gpText) and gpText.length() >= maxi(1, gpWidth)
	if not _gpCharsetOk(gpText):
		return false
	if gpMin > 0 and gpText.length() < gpMin:
		return false
	if gpMax > 0 and gpText.length() > gpMax:
		return false
	return true


# Human description of what this segment accepts, for the "第 N 段应为 …" message.
# 本段接受什么的人类描述，用于「第 N 段应为 …」的提示。
func gpExpectedText() -> String:
	match gpSource:
		GPSource.GP_FIXED:
			return "固定为 %s" % gpLiteral
		GPSource.GP_SEQ:
			return "%d 位数字" % gpWidth
		GPSource.GP_ATTR_DIGITS:
			if gpWidth <= 0:
				return "数字（不补位）"
			return "至少 %d 位数字" % gpWidth
		GPSource.GP_ATTR, GPSource.GP_CODE_TABLE:
			var gpChars: String = _gpCharsetText()
			if gpMin > 0 and gpMax > 0:
				if gpMin == gpMax:
					return "%d 位%s" % [gpMin, gpChars]
				return "%d-%d 位%s" % [gpMin, gpMax, gpChars]
			if gpMin > 0:
				return "至少 %d 位%s" % [gpMin, gpChars]
			if gpMax > 0:
				return "至多 %d 位%s" % [gpMax, gpChars]
			return "%s" % gpChars
	return ""


# Check the segment DEFINITION itself (not a value). Returns a failure naming the problem.
# 校验**段定义**本身（不是取值）。返回指出问题的失败结果。
func gpValidate(gpSeparator: String) -> GPIOResult:
	if gpKey == "":
		return GPIOResult.gpFailure("tag_seg.no_key", "tag_seg.err_no_key", gpLabel)
	if gpSeparator == "":
		return GPIOResult.gpFailure("tag_seg.no_separator", "tag_seg.err_no_separator", gpKey)
	if gpSource == GPSource.GP_FIXED:
		if gpLiteral == "":
			return GPIOResult.gpFailure("tag_seg.empty_literal", "tag_seg.err_empty_literal",
				gpKey)
		if gpLiteral.find(gpSeparator) >= 0:
			return GPIOResult.gpFailure("tag_seg.literal_has_separator",
				"tag_seg.err_literal_has_separator", "%s (%s)" % [gpLiteral, gpSeparator])
		return GPIOResult.gpSuccess()
	if gpSource == GPSource.GP_SEQ:
		if gpWidth < 1 or gpWidth > GP_MAX_SEQ_WIDTH:
			return GPIOResult.gpFailure("tag_seg.bad_width", "tag_seg.err_bad_width",
				"%s (%d)" % [gpKey, gpWidth])
		if gpPad.length() != 1:
			return GPIOResult.gpFailure("tag_seg.bad_pad", "tag_seg.err_bad_pad", gpKey)
		return GPIOResult.gpSuccess()
	if gpSource == GPSource.GP_ATTR_DIGITS:
		if gpAttr == "":
			return GPIOResult.gpFailure("tag_seg.no_attr", "tag_seg.err_no_attr", gpKey)
		# Width 0 = "keep the digits as they are" — the metric/imperial switch. A project that
		# sizes lines in inches sets the field to 0 so `4"` renders as `4`, not `004`.
		# 宽度 0 = 「原样保留数字」—— 即公制/英制开关。以英寸标注管径的工程把它设为 0，
		# 使 `4"` 渲染为 `4` 而不是 `004`。
		if gpWidth < 0:
			return GPIOResult.gpFailure("tag_seg.bad_width", "tag_seg.err_bad_width",
				"%s (%d)" % [gpKey, gpWidth])
	else:
		if gpAttr == "":
			return GPIOResult.gpFailure("tag_seg.no_attr", "tag_seg.err_no_attr", gpKey)
		if gpSource == GPSource.GP_CODE_TABLE and gpTable == "":
			return GPIOResult.gpFailure("tag_seg.no_table", "tag_seg.err_no_table", gpKey)
		if gpMin < 1:
			return GPIOResult.gpFailure("tag_seg.bad_min", "tag_seg.err_bad_min", gpKey)
		if gpMax != 0 and gpMax < gpMin:
			return GPIOResult.gpFailure("tag_seg.bad_max", "tag_seg.err_bad_max", gpKey)
	# GP_ATTR / GP_ATTR_DIGITS / GP_CODE_TABLE all need a fallback that itself fits.
	if gpFallback == "":
		return GPIOResult.gpFailure("tag_seg.no_fallback", "tag_seg.err_no_fallback", gpKey)
	if not gpCheckPart(gpFallback):
		return GPIOResult.gpFailure("tag_seg.bad_fallback", "tag_seg.err_bad_fallback",
			"%s (%s)" % [gpKey, gpFallback])
	return GPIOResult.gpSuccess()


# ==================== persistence / 持久化 ====================

func gpToDict() -> Dictionary:
	return {
		"key": gpKey,
		"label": gpLabel,
		"source": int(gpSource),
		"literal": gpLiteral,
		"attr": gpAttr,
		"table": gpTable,
		"width": gpWidth,
		"min": gpMin,
		"max": gpMax,
		"pad": gpPad,
		"charset": int(gpCharset),
		"fallback": gpFallback,
		"upper": gpUpper,
	}


static func gpFromDict(gpD: Dictionary) -> GPTagSegment:
	var gpS: GPTagSegment = GPTagSegment.new()
	gpS.gpKey = str(gpD.get("key", ""))
	gpS.gpLabel = str(gpD.get("label", ""))
	gpS.gpSource = int(gpD.get("source", GPSource.GP_FIXED)) as GPSource
	gpS.gpLiteral = str(gpD.get("literal", ""))
	gpS.gpAttr = str(gpD.get("attr", ""))
	gpS.gpTable = str(gpD.get("table", ""))
	gpS.gpWidth = int(gpD.get("width", 0))
	gpS.gpMin = int(gpD.get("min", 0))
	gpS.gpMax = int(gpD.get("max", 0))
	gpS.gpPad = str(gpD.get("pad", "0"))
	gpS.gpCharset = int(gpD.get("charset", GPCharset.GP_ALNUM)) as GPCharset
	gpS.gpFallback = str(gpD.get("fallback", ""))
	gpS.gpUpper = bool(gpD.get("upper", true))
	return gpS


# ==================== internals / 内部 ====================

# Digits only, in order. "DN150" -> "150"; `4"` -> "4".
# 仅数字，按原顺序。"DN150" -> "150"；`4"` -> "4"。
static func _gpDigitsOf(gpRaw: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpRaw.length()):
		var gpC: String = gpRaw[gpI]
		if gpC >= "0" and gpC <= "9":
			gpOut += gpC
	return gpOut


static func _gpIsDigits(gpText: String) -> bool:
	if gpText == "":
		return false
	for gpI in range(gpText.length()):
		var gpC: String = gpText[gpI]
		if gpC < "0" or gpC > "9":
			return false
	return true


# Keep only the characters this segment's charset allows, upper-cased.
# 仅保留本段字符集允许的字符，并转大写。
func _gpFilter(gpRaw: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpRaw.length()):
		var gpC: String = gpRaw[gpI]
		if gpC == "\n" or gpC == "\r" or gpC == "\t":
			gpC = " "
		if gpCharset == GPCharset.GP_DIGIT:
			if gpC >= "0" and gpC <= "9":
				gpOut += gpC
		elif gpCharset == GPCharset.GP_ALPHA:
			if gpC.to_upper() != gpC.to_lower():
				gpOut += gpC
		elif gpCharset == GPCharset.GP_ALNUM:
			if gpC >= "0" and gpC <= "9" or gpC.to_upper() != gpC.to_lower():
				gpOut += gpC
		else:
			# GP_ANY still drops the tag separator and whitespace: a value that contains
			# them would silently split the tag into more segments than the rule declares.
			# GP_ANY 仍会丢掉分隔符与空白：含它们的取值会把位号悄悄切成比规则更多的段。
			if gpC != "-" and gpC != " ":
				gpOut += gpC
	if gpUpper:
		gpOut = gpOut.to_upper()
	return gpOut


# Trim a variable-length value to gpMax (never pad — a code is not a number).
# 把变长取值裁到 gpMax（绝不补位 —— 代号不是数字）。
func _gpClamp(gpText: String) -> String:
	if gpMax > 0 and gpText.length() > gpMax:
		return gpText.substr(0, gpMax)
	return gpText


func _gpCharsetOk(gpText: String) -> bool:
	for gpI in range(gpText.length()):
		var gpC: String = gpText[gpI]
		match gpCharset:
			GPCharset.GP_DIGIT:
				if gpC < "0" or gpC > "9":
					return false
			GPCharset.GP_ALPHA:
				if gpC.to_upper() == gpC.to_lower():
					return false
			GPCharset.GP_ALNUM:
				if not (gpC >= "0" and gpC <= "9") and gpC.to_upper() == gpC.to_lower():
					return false
			_:
				pass
	return true


func _gpCharsetText() -> String:
	match gpCharset:
		GPCharset.GP_DIGIT:
			return "数字"
		GPCharset.GP_ALPHA:
			return "字母"
		GPCharset.GP_ALNUM:
			return "字母数字"
	return "字符"


static func _gpPadLeft(gpText: String, gpWidth: int, gpPadChar: String) -> String:
	var gpOut: String = gpText
	if gpWidth <= 0:
		return gpOut
	var gpPad: String = gpPadChar if gpPadChar != "" else "0"
	while gpOut.length() < gpWidth:
		gpOut = gpPad + gpOut
	return gpOut
