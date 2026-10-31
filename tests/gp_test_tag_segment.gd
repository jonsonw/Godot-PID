class_name GpTestTagSegment
extends GPGTest
# Headless tests for segmented tag rules (ADR-36 D4/D5/D7, step A2).
# 分段位号规则（ADR-36 D4/D5/D7，A2 步）的 headless 测试。
#
# The promises being pinned / 被钉住的承诺：
# 1. the user's line designation renders from a context: 150-CWR-0007-A1A-P;
# 2. missing attributes fall back to placeholders, never to an empty field;
# 3. a candidate tag is checked SEGMENT BY SEGMENT, and the refusal names the segment and
#    what it expected (this is what "不能突破规则" means in practice);
# 4. a legacy template rule is untouched: same rendering, same keys on disk (byte stability);
# 5. the compiled regex agrees with the renderer, so a bulk check (DRC / export gate) cannot
#    disagree with what the editor produced.
# 1. 用户的管线代号能从上下文渲染：150-CWR-0007-A1A-P；
# 2. 属性缺失时回落占位代号，绝不产出空字段；
# 3. 候选位号**逐段**校验，拒绝时指出第几段、期望什么（「不能突破规则」的实际含义）；
# 4. 旧式模板规则原封不动：渲染相同、落盘键相同（逐字节稳定）；
# 5. 编译出的正则与渲染器一致，故批量检查（DRC / 导出闸门）不会与编辑器产出的号打架。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


# A standard with the code tables a line number needs (material and insulation are empty in
# the factory set on purpose, so the test seeds them explicitly).
# 带齐管线号所需代号表的标准（材料与保温在出厂集里刻意留空，故测试显式补上）。
func _gpStd() -> GPProjectStandard:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_MATERIAL,
		[{"code": "A1A", "label": "碳钢", "aliases": ["Carbon Steel"]}])
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_INSULATION,
		[{"code": "P", "label": "保冷", "aliases": ["Cold"]}])
	return gpStd


func _gpAttrs() -> Dictionary:
	return {"dn": "DN150", "medium": "循环冷却水", "spec": "碳钢", "insulation": "保冷"}


# ---------------------------------------------------------------- rendering

func gpTestCompactPresetRendersTheDesignation() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpTag: String = gpRule.gpRender({"seq": 7, "attrs": _gpAttrs()}, _gpStd())
	gpEq(gpTag, "150-CWR-0007-A1A-P", "size-service-number-material-insulation")


func gpTestMissingAttributesFallBackToPlaceholders() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	gpEq(gpRule.gpRender({"seq": 7, "attrs": {}}, _gpStd()), "000-XX-0007-XXX-N",
		"every unknown field becomes its declared placeholder, never an empty string")


func gpTestDnTakesDigitsOnly() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpStd: GPProjectStandard = _gpStd()
	gpEq(gpRule.gpRender({"seq": 1, "attrs": {"dn": "150"}}, gpStd).split("-")[0], "150",
		"a bare number is used as is")
	gpEq(gpRule.gpRender({"seq": 1, "attrs": {"dn": "DN150"}}, gpStd).split("-")[0], "150",
		"the DN prefix is dropped, not carried into the tag")
	gpEq(gpRule.gpRender({"seq": 1, "attrs": {"dn": "DN80"}}, gpStd).split("-")[0], "080",
		"a two-digit size is zero-padded to the declared width")
	gpEq(gpRule.gpRender({"seq": 1, "attrs": {"dn": "4\""}}, gpStd).split("-")[0], "004",
		"an imperial size contributes its NUMBER — the inch mark never enters the tag")


func gpTestImperialSizeKeepsItsDigitsUnpadded() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	# Width 0 is the metric/imperial switch: an inch size stays `4`, it does not become `004`.
	# 宽度 0 就是公制/英制开关：英寸尺寸保持 `4`，不会变成 `004`。
	gpRule.gpSegments[0].gpWidth = 0
	gpEq(gpRule.gpRender({"seq": 1, "attrs": {"dn": "4\""}}, _gpStd()).split("-")[0], "4",
		"an imperial size keeps its digits verbatim")
	gpCheck(gpRule.gpValidate().gpIsOk(), "an unpadded numeric field is still a legal rule")
	gpCheck(bool(gpRule.gpCheckTag("4-CWR-0001-XXX-N").get("ok", false)),
		"and a one-digit size validates")


func gpTestSequenceIsZeroPaddedAndOverflowIsRefused() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	gpEq(gpRule.gpRender({"seq": 1, "attrs": {}}, _gpStd()).split("-")[2], "0001",
		"the counter is padded to four digits")
	gpEq(gpRule.gpRender({"seq": 10000, "attrs": {}}, _gpStd()), "",
		"a five-digit counter cannot fit a four-digit field — render REFUSES, it does not widen")


# ---------------------------------------------------------------- checking

func gpTestGoodTagPasses() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpChk: Dictionary = gpRule.gpCheckTag("150-CWR-0007-A1A-P")
	gpCheck(bool(gpChk.get("ok", false)), "a well-formed tag passes")
	gpEq(int(gpChk.get("index", -2)), -1, "no failing segment is reported")


func gpTestWrongWidthNamesTheSegment() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpChk: Dictionary = gpRule.gpCheckTag("150-CWR-7-A1A-P")
	gpCheck(not bool(gpChk.get("ok", true)), "an unpadded counter is refused")
	gpEq(int(gpChk.get("index", -2)), 2, "the THIRD segment (numb) is the failing one")
	gpEq(str(gpChk.get("key", "")), "numb", "the refusal names the segment key")
	gpCheck(str(gpChk.get("detail", "")).find("4 位数字") >= 0,
		"and says what it expected: " + str(gpChk.get("detail", "")))


func gpTestWrongCharsetNamesTheSegment() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpChk: Dictionary = gpRule.gpCheckTag("150-12-0007-A1A-P")
	gpCheck(not bool(gpChk.get("ok", true)), "digits are not a medium code")
	gpEq(int(gpChk.get("index", -2)), 1, "the SECOND segment (service) is the failing one")
	gpEq(str(gpChk.get("key", "")), "service", "segment key is reported")


func gpTestWrongSegmentCountIsRefused() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpShort: Dictionary = gpRule.gpCheckTag("150-CWR-0007-A1A")
	gpCheck(not bool(gpShort.get("ok", true)), "a missing segment is refused")
	gpEq(int(gpShort.get("index", -2)), -1, "no particular segment — the shape is wrong")
	gpCheck(str(gpShort.get("detail", "")).find("段数不符") >= 0,
		"the message says the segment count is wrong")
	var gpLong: Dictionary = gpRule.gpCheckTag("150-CWR-0007-A1A-P-EXTRA")
	gpCheck(not bool(gpLong.get("ok", true)), "an extra segment is refused too")


func gpTestCheckIsCaseInsensitive() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	gpCheck(bool(gpRule.gpCheckTag("150-cwr-0007-a1a-p").get("ok", false)),
		"lower-case input is the same tag (the sheet may store either)")


func gpTestValidateTagReturnsRejectionWithDetail() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	gpCheck(gpRule.gpValidateTag("150-CWR-0007-A1A-P").gpIsOk(), "good tag accepted")
	var gpRes: GPIOResult = gpRule.gpValidateTag("150-CWR-7-A1A-P")
	gpCheck(not gpRes.gpIsOk(), "bad tag rejected")
	gpEq(gpRes.gpMessageKey, "tag.err_rule", "the command layer's refusal key")
	gpCheck(gpRes.gpDetail.find("第 3 段") >= 0, "detail points at the third segment")


# ---------------------------------------------------------------- regex / compile

func gpTestRegexAgreesWithTheRenderer() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpPattern: GPTagPattern = gpRule.gpCompile()
	var gpTag: String = gpRule.gpRender({"seq": 7, "attrs": _gpAttrs()}, _gpStd())
	var gpRe: RegEx = RegEx.new()
	gpEq(gpRe.compile(gpPattern.gpRegexText()), OK, "the compiled pattern is a valid regex")
	gpCheck(gpRe.search(gpTag) != null, "the rendered tag matches its own pattern: " + gpTag)
	gpCheck(gpRe.search("150-CWR-7-A1A-P") == null, "an unpadded counter does not match")
	gpCheck(gpRe.search("150-CWR-0007-A1A-P-EXTRA") == null, "an extra segment does not match")


# ---------------------------------------------------------------- presets / round trip

func gpTestFullPresetRendersSevenSegments() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineFull()
	var gpAttrs: Dictionary = {
		"area": "1200", "discipline": "PI", "medium": "CWR",
		"spec": "A1A", "dn": "06", "insulation": "P",
	}
	gpEq(gpRule.gpRender({"seq": 7, "attrs": gpAttrs}, _gpStd()),
		"1200-PI-CWR-0007-A1A-06-P",
		"area-discipline-medium-number-material-size-insulation")


func gpTestSegmentedRuleRoundTrips() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpBack: GPTagRule = GPTagRule.gpFromDict(gpRule.gpToDict())
	gpCheck(gpBack.gpUsesSegments(), "segments survive a save/load round trip")
	gpEq(gpBack.gpSeparator, "-", "the separator survives")
	gpEq(gpBack.gpRender({"seq": 7, "attrs": _gpAttrs()}, _gpStd()),
		"150-CWR-0007-A1A-P", "and it renders the same tag")
	gpEq(gpBack.gpValidate().gpIsOk(), true, "and it stays valid")


# ---------------------------------------------------------------- rule validation

func gpTestRuleWithoutASequenceIsRefused() -> void:
	var gpRule: GPTagRule = GPTagRule.new()
	gpRule.gpSegments = [
		GPTagSegment.gpCode("service", "介质代码", GPProjectStandard.GP_TABLE_MEDIUM, "medium",
			2, 3, GPTagSegment.GPCharset.GP_ALPHA, "XX"),
	]
	var gpRes: GPIOResult = gpRule.gpValidate()
	gpCheck(not gpRes.gpIsOk(), "a rule without a counter would give every instance one tag")
	gpEq(gpRes.gpMessageKey, "tag_seg.err_seq_count", "and the reason says exactly that")


func gpTestSeparatorInsideALiteralIsRefused() -> void:
	var gpRule: GPTagRule = GPTagRulePresets.gpPrefixed("A-B")
	var gpRes: GPIOResult = gpRule.gpValidate()
	gpCheck(not gpRes.gpIsOk(), "a literal containing the separator would split the tag")
	gpEq(gpRes.gpMessageKey, "tag_seg.err_literal_has_separator", "the reason names the problem")


func gpTestFallbackThatBreaksTheRuleIsRefused() -> void:
	var gpRule: GPTagRule = GPTagRule.new()
	gpRule.gpSegments = [
		GPTagSegment.gpAttrDigits("size", "管径", "dn", 3, "ABC"),
		GPTagSegment.gpSeq("numb", "管线号", 4, "0"),
	]
	var gpRes: GPIOResult = gpRule.gpValidate()
	gpCheck(not gpRes.gpIsOk(), "a placeholder that breaks its own segment is refused")
	gpEq(gpRes.gpMessageKey, "tag_seg.err_bad_fallback", "and it is the fallback that is blamed")


func gpTestFactoryLineRuleIsSegmented() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpLine: GPProjectTagRules = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE)
	gpCheck(gpLine.gpDefault.gpUsesSegments(),
		"the factory line rule is the five-field designation (D3), not a PL counter")
	gpEq(gpLine.gpDefault.gpSegments.size(), 5, "five segments")
	gpCheck(gpStd.gpValidate().gpIsOk(), "and the whole factory standard validates")


# ---------------------------------------------------------------- legacy untouched

func gpTestLegacyRenderNeedsAPrefix() -> void:
	var gpRule: GPTagRule = GPTagRule.gpDefault()
	gpEq(gpRule.gpRender({"seq": 1001}), "",
		"a template rule with no prefix refuses instead of producing '-1001'")
	gpEq(gpRule.gpRender({"seq": 1001, "prefix": "P"}), "P-1001",
		"with the caller's prefix it renders exactly as before")


func gpTestLegacyTemplateRuleIsUnchanged() -> void:
	var gpRule: GPTagRule = GPTagRule.gpDefault()
	gpCheck(not gpRule.gpUsesSegments(), "the factory equipment rule is still a template rule")
	gpEq(gpRule.gpFormat("P", 1001), "P-1001", "and renders exactly as before")
	var gpDict: Dictionary = gpRule.gpToDict()
	gpEq(gpDict.has("segments"), false, "no segment key is written for a template rule")
	gpEq(gpDict.has("separator"), false, "no separator key either (byte stability)")
	var gpBack: GPTagRule = GPTagRule.gpFromDict(gpDict)
	gpCheck(not gpBack.gpUsesSegments(), "and it loads back as a template rule")
	gpEq(gpBack.gpFormat("P", 1001), "P-1001", "with unchanged rendering")
