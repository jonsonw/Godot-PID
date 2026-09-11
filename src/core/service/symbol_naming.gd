class_name GPSymbolNaming
extends RefCounted
# Copyright © 2026 Jonson Wang
# The ONE authoritative definition of the project-wide symbol id rule.
# 项目级图元标识 id 命名规则的唯一权威定义。
#
# RULE / 规则
#   <来源码><类别码><三位序号>
#   source code + CATEGORY CODE (upper) + 3-digit sequence
#
#   LVALVE001   L = 内置库图元（Library，随发行版自带、只读）
#   CVALVE001   C = 自定义图元（Custom，用户自建或由内置图元派生）
#
#   L 内置库 / library (ships with the release, read-only)
#   C 自定义 / custom (authored by the user, or derived from a built-in)
#
# WHY A SEQUENCE AT ALL / 为何要序号：
#   the sequence lives INSIDE a category, so the id also reads as "which family, and the
#   Nth member of it". An id built from the English name (BallValve) would make the sequence
#   permanently 001 and the two halves of the id would carry the same information twice.
#   序号位于「类别内部」，因此 id 同时表达「属于哪一族」与「族内第几个」。若用英文名
#   （BallValve）构造 id，序号将永远是 001，且 id 的两半会重复承载同一信息。
#
# SEQUENCE IS NEVER RECYCLED / 序号永不复用：
#   gpAllocate always returns max(existing)+1 and never fills a gap left by a deleted
#   symbol. Reusing a retired number would make an old *.pid.json silently resolve to a
#   DIFFERENT symbol that happens to occupy that number now — a data-corruption class bug.
#   gpAllocate 恒返回 max(已有)+1，绝不填补删除留下的空号。复用已退役编号会让旧存档
#   静默指向「恰好占用了该号」的另一个图元 —— 属于数据损坏级缺陷。

# Source code for built-in (library) symbols.
# 内置（图元库）图元的来源码。
const GP_SOURCE_LIBRARY: String = "L"

# Source code for user-authored (custom) symbols.
# 用户自建（自定义）图元的来源码。
const GP_SOURCE_CUSTOM: String = "C"

# Width of the sequence field, zero-padded.
# 序号字段宽度，零填充。
const GP_SEQ_DIGITS: int = 3

# Largest allocatable sequence (999 for three digits).
# 可分配的最大序号（三位即 999）。
const GP_SEQ_MAX: int = 999

# Fallback category code when a category string yields no letters at all.
# 类别字符串完全不含字母时的兜底类别码。
const GP_CATEGORY_FALLBACK: String = "GENERAL"

# Legacy id -> current id. Filled in by tools/gen_symbol_packs.py (see legacy_id_map.json).
# 旧 id → 新 id。由 tools/gen_symbol_packs.py 生成（见 legacy_id_map.json）。
# The built-in library ids used to be the SVG file stem ("P_CentrifugalPump_001"); every
# *.pid.json written before the rule change carries those, so they must keep resolving.
# 内置图元库 id 原先就是 SVG 文件名主干（"P_CentrifugalPump_001"），规则变更前落盘的
# 每个 *.pid.json 都带这些 id，因此必须能继续解析。
const GP_LEGACY_ALIASES: Dictionary = {
	"BV_BallValve_001": "LVALVE001",
	"CHK_CheckValve_001": "LVALVE002",
	"CV_ControlValve_001": "LVALVE003",
	"DV_DiaphragmValve_001": "LVALVE004",
	"GLV_GlobeValve_001": "LVALVE005",
	"GV_GateValve_001": "LVALVE006",
	"PV_Positioner_001": "LVALVE007",
	"VAV_ValveActuator_001": "LVALVE008",
	"C_Compressor_001": "LPUMP001",
	"PD_PositiveDisplacementPump_001": "LPUMP002",
	"P_CentrifugalPump_001": "LPUMP003",
	"TK_Tank_001": "LTANK001",
	"HX_HeatExchanger_001": "LHEAT001",
	"FE_FieldEnclosure_001": "LINSTRUMENT001",
	"FI_FlowIndicator_001": "LINSTRUMENT002",
	"FT_FlowTransmitter_001": "LINSTRUMENT003",
	"LI_LevelIndicator_001": "LINSTRUMENT004",
	"LT_LevelTransmitter_001": "LINSTRUMENT005",
	"PI_PressureIndicator_001": "LINSTRUMENT006",
	"PT_PressureTransmitter_001": "LINSTRUMENT007",
	"TI_TemperatureIndicator_001": "LINSTRUMENT008",
	"TT_TemperatureTransmitter_001": "LINSTRUMENT009",
	"ElectricalLine_DotDash_001": "LGENERAL001",
	"InstrumentLine_Dashed_001": "LGENERAL002",
	"ProcessLine_Solid_001": "LGENERAL003",
}

# Compiled-once validator for the canonical form.
# 只编译一次的规范格式校验器。
static var _gpRe: RegEx = null


# True when gpId matches the canonical rule (e.g. "LVALVE001", "CPUMP003").
# gpId 符合规范规则（如 "LVALVE001"、"CPUMP003"）时为 true。
static func gpIsValid(gpId: String) -> bool:
	return _gpRegex().search(gpId) != null


# Split a canonical id into its parts: {source, category, seq}. Empty dict when invalid.
# 把规范 id 拆成各部分：{source, category, seq}。非法时返回空字典。
static func gpParse(gpId: String) -> Dictionary:
	var gpM: RegExMatch = _gpRegex().search(gpId)
	if gpM == null:
		return {}
	var gpOut: Dictionary = {}
	gpOut["source"] = gpM.get_string(1)
	gpOut["category"] = gpM.get_string(2)
	gpOut["seq"] = int(gpM.get_string(3))
	return gpOut


# Category code from a GPSymbolDef.gpCategory string: letters only, upper-cased.
# "valve" -> "VALVE", "instrument_signal" -> "INSTRUMENTSIGNAL" (underscore dropped so the
# code stays a single unbroken token). Falls back to GP_CATEGORY_FALLBACK.
# 由 GPSymbolDef.gpCategory 字符串生成类别码：仅保留字母并大写。
# "valve" -> "VALVE"、"instrument_signal" -> "INSTRUMENTSIGNAL"（去掉下划线以保持单一连续词）。
# 无字母时回退到 GP_CATEGORY_FALLBACK。
static func gpCategoryCode(gpCategory: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpCategory.length()):
		var gpC: String = gpCategory.substr(gpI, 1)
		var gpU: int = gpC.unicode_at(0)
		if (gpU >= 65 and gpU <= 90) or (gpU >= 97 and gpU <= 122):
			gpOut += gpC.to_upper()
	if gpOut == "":
		return GP_CATEGORY_FALLBACK
	return gpOut


# Id prefix for a source + category pair, e.g. ("L", "valve") -> "LVALVE".
# 来源 + 类别对的 id 前缀，如 ("L", "valve") -> "LVALVE"。
static func gpPrefix(gpSource: String, gpCategory: String) -> String:
	return gpSource + gpCategoryCode(gpCategory)


# Highest sequence currently used by a prefix, or 0 when the family is empty.
# 某前缀当前已用的最大序号；该族为空时返回 0。
static func gpMaxSeq(gpPrefixText: String, gpTaken: Array[String]) -> int:
	var gpMax: int = 0
	for gpId in gpTaken:
		if not gpId.begins_with(gpPrefixText):
			continue
		var gpTail: String = gpId.substr(gpPrefixText.length())
		if gpTail.length() != GP_SEQ_DIGITS:
			continue
		var gpAllDigits: bool = true
		for gpI in range(gpTail.length()):
			var gpU: int = gpTail.unicode_at(gpI)
			if gpU < 48 or gpU > 57:
				gpAllDigits = false
				break
		if not gpAllDigits:
			continue
		gpMax = maxi(gpMax, int(gpTail))
	return gpMax


# Allocate the next FREE id in the family: max(existing) + 1, gaps are never reused.
# 在族内分配下一个可用 id：max(已有) + 1，空号绝不复用。
# Returns "" when the family is exhausted (999 used) or the source code is unknown.
# 该族耗尽（已用满 999）或来源码未知时返回 ""。
static func gpAllocate(gpSource: String, gpCategory: String, gpTaken: Array[String]) -> String:
	if gpSource != GP_SOURCE_LIBRARY and gpSource != GP_SOURCE_CUSTOM:
		return ""
	var gpNext: int = gpMaxSeq(gpPrefix(gpSource, gpCategory), gpTaken) + 1
	if gpNext > GP_SEQ_MAX:
		return ""
	return "%s%03d" % [gpPrefix(gpSource, gpCategory), gpNext]


# Translate a pre-rule legacy id into its current id. Unknown ids pass through unchanged —
# user-authored symbols created before this rule (e.g. "my_valve", "离心泵") have no entry
# here, and silently rewriting them would break that user's saved files.
# 把规则变更前的旧 id 翻译为当前 id。未知 id 原样返回 —— 规则变更前用户自建的图元
# （如 "my_valve"、"离心泵"）在此没有条目，静默改写会破坏该用户的存档。
static func gpMigrate(gpLegacyId: String) -> String:
	return String(GP_LEGACY_ALIASES.get(gpLegacyId, gpLegacyId))


# True when gpId is a pre-rule legacy id that has a known translation.
# gpId 是存在已知映射的规则变更前旧 id 时为 true。
static func gpIsLegacy(gpId: String) -> bool:
	return GP_LEGACY_ALIASES.has(gpId)


# Cached validator (GDScript has no static initialiser, so compile lazily).
# 缓存的校验器（GDScript 无静态初始化器，故惰性编译）。
static func _gpRegex() -> RegEx:
	if _gpRe == null:
		_gpRe = RegEx.new()
		var gpErr: Error = _gpRe.compile("^([LC])([A-Z]+)([0-9]{%d})$" % GP_SEQ_DIGITS)
		if gpErr != OK:
			push_error("GPSymbolNaming: regex compile failed (%d)" % gpErr)
	return _gpRe
