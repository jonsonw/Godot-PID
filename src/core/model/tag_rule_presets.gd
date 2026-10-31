class_name GPTagRulePresets
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Factory rule presets (ADR-36 D3/D4). Kept apart from GPTagRule so the model stays a pure
# mechanism and the CONVENTIONS are visible in one place a project can compare against.
# 出厂规则预设（ADR-36 D3/D4）。与 GPTagRule 分开，使模型保持纯机制，而**约定**集中在一处，
# 工程可以直接对照。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The line rule the user chose on 2026-10-26: SIZE-SERV-NUMB-MTL-IN.
# 用户 2026-10-26 选定的管线规则：管径-介质代码-管线号-材料等级-保温/保冷。
#   SIZE  管径      numbers of `dn` (DN150 -> 150), at least 3 digits, 000 when unknown
#   SERV  介质代码  code table `medium` (循环冷却水 -> CWR), 2–3 letters, XX when unknown
#   NUMB  管线号    the counter, exactly 4 digits (0001 …)
#   MTL   材料等级  code table `material` (looked up from `spec`), 1–3 alnum, XXX unknown
#   IN    保温保冷  code table `insulation`, 1–2 letters, N when unknown
# Starting at 0 makes the first issued line number 0001 rather than 1001 — a four-digit
# line number is a SEQUENCE for branches, not a high-water project number.
# 起点 0 使首个管线号为 0001 而非 1001 —— 四位线号是**支管序号**，不是工程高位号。
static func gpLineCompact() -> GPTagRule:
	var gpR: GPTagRule = GPTagRule.new()
	gpR.gpStart = 0
	gpR.gpStep = 1
	gpR.gpSeparator = "-"
	gpR.gpSegments = [
		GPTagSegment.gpAttrDigits("size", "管径", "dn", 3, "000"),
		GPTagSegment.gpCode("service", "介质代码", "medium", "medium",
			2, 3, GPTagSegment.GPCharset.GP_ALPHA, "XX"),
		GPTagSegment.gpSeq("numb", "管线号", 4, "0"),
		GPTagSegment.gpCode("mtl", "管道等级", "material", "spec",
			1, 3, GPTagSegment.GPCharset.GP_ALNUM, "XXX"),
		GPTagSegment.gpCode("in", "保温保冷", "insulation",
			"insulation", 1, 2, GPTagSegment.GPCharset.GP_ALPHA, "N"),
	]
	return gpR


# The seven-segment designation from the user's reference sheet (AREA-DISC-MED-UID-MTL-DN-IN),
# offered as a preset for projects that standardise on it.
# 用户参考图上的七段写法（区域-专业-介质-管线号-材料-管径-保温），供采用该标准的工程选用。
static func gpLineFull() -> GPTagRule:
	var gpR: GPTagRule = GPTagRule.new()
	gpR.gpStart = 0
	gpR.gpStep = 1
	gpR.gpSeparator = "-"
	gpR.gpSegments = [
		GPTagSegment.gpAttrDigits("area", "区域代码", "area", 4, "0000"),
		GPTagSegment.gpCode("discipline", "专业代码", "discipline",
			"discipline", 2, 2, GPTagSegment.GPCharset.GP_ALPHA, "XX"),
		GPTagSegment.gpCode("medium", "介质代码", "medium", "medium",
			2, 3, GPTagSegment.GPCharset.GP_ALPHA, "XX"),
		GPTagSegment.gpSeq("numb", "管线号", 4, "0"),
		GPTagSegment.gpCode("material", "材料编码", "material",
			"spec", 1, 3, GPTagSegment.GPCharset.GP_ALNUM, "XXX"),
		GPTagSegment.gpAttrDigits("dn", "管径", "dn", 2, "00"),
		GPTagSegment.gpCode("insulation", "保温", "insulation",
			"insulation", 1, 2, GPTagSegment.GPCharset.GP_ALPHA, "N"),
	]
	return gpR


# A single-segment "PREFIX-0001" rule. Used by the classes that keep a short tag (special
# items, manual valves configured by the project) instead of a composite designation.
# 单段「前缀-0001」规则。供仍使用短位号的类别（特殊件、工程自行配置的手阀）使用，
# 而不是复合代号。
static func gpPrefixed(gpPrefix: String, gpWidth: int = 4) -> GPTagRule:
	var gpR: GPTagRule = GPTagRule.new()
	gpR.gpStart = 0
	gpR.gpStep = 1
	gpR.gpSeparator = "-"
	gpR.gpSegments = [
		GPTagSegment.gpFixed("prefix", "前缀", gpPrefix),
		GPTagSegment.gpSeq("numb", "序号", gpWidth, "0"),
	]
	return gpR
