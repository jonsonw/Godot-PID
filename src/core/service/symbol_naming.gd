class_name GPSymbolNaming
extends RefCounted
# Copyright © 2026 Jonson Wang
# The ONE authoritative definition of the project-wide symbol id rule.
# 项目级图元标识 id 命名规则的唯一权威定义。
#
# RULE / 规则
# <来源码><类别码><三位序号>
# source code + CATEGORY CODE (upper) + 3-digit sequence
#
# LVALVE001 L = 内置库图元（Library，随发行版自带、只读）
# CVALVE001 C = 自定义图元（Custom，用户自建或由内置图元派生）
# DVALVE001 D = DEXPI 标准包图元（DEXPI，独立命名空间）
#
# L 内置库 / library (ships with the release, read-only)
# C 自定义 / custom (authored by the user, or derived from a built-in)
# D DEXPI 包 / DEXPI pack (the v0.1 standard set from DEXPI Example C01)
#
# WHY "D" NEEDS ITS OWN LETTER / 为何 D 要单独一个字母：
# sharing a namespace with L would mint "VALVE001" twice — once per pack — and every saved
# *.pid.json would then resolve to whichever pack registered last. A per-source letter makes
# the id namespace exclusive by construction, not by convention.
# 若与 L 共用命名空间，"VALVE001" 会被两个包各铸一次，已存盘的 *.pid.json 会解析到
# 「后注册的那个」。来源码字母使命名空间**按构造**互斥，而非靠约定。
#
# WHY A SEQUENCE AT ALL / 为何要序号：
# the sequence lives INSIDE a category, so the id also reads as "which family, and the
# Nth member of it". An id built from the English name (BallValve) would make the sequence
# permanently 001 and the two halves of the id would carry the same information twice.
# 序号位于「类别内部」，因此 id 同时表达「属于哪一族」与「族内第几个」。若用英文名
# （BallValve）构造 id，序号将永远是 001，且 id 的两半会重复承载同一信息。
#
# SEQUENCE IS NEVER RECYCLED / 序号永不复用：
# gpAllocate() always returns max(existing)+1 and never fills a gap left by a deleted
# symbol. Reusing a retired number would make an old *.pid.json silently resolve to a
# DIFFERENT symbol that happens to occupy that number now — a data-corruption class bug.
# gpAllocate() 恒返回 max(已有)+1，绝不填补删除留下的空号。复用已退役编号会让旧存档
# 静默指向「恰好占用了该号」的另一个图元 —— 属于数据损坏级缺陷。

# Source code for built-in (library) symbols.
# 内置（图元库）图元的来源码。
const GP_SOURCE_LIBRARY: String = "L"

# Source code for user-authored (custom) symbols.
# 用户自建（自定义）图元的来源码。
const GP_SOURCE_CUSTOM: String = "C"

# Source code for the DEXPI standard pack (v0.1). A BUILT-IN pack, read-only like L — but
# with its own namespace so ids never collide with the legacy ISO set.
# DEXPI 标准包（v0.1）来源码。与 L 同为**内置只读**包，但独占命名空间，id 绝不与
# 历史 ISO 集冲突。
const GP_SOURCE_DEXPI: String = "D"

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
# The table mirrors the LIVE pack (dexpi). The ISO 10628 aliases were removed together with
# that pack in v0.1: an old archive referencing LVALVE001 will report symbol_missing on load
# (non-destructively, per ADR-6) rather than silently resolving to a different glyph.
# 本表镜像**当前生效**的包（dexpi）。ISO 10628 的别名随该包在 v0.1 一并移除：引用
# LVALVE001 的旧档在载入时将报告 symbol_missing（依 ADR-6 非破坏），而不是静默解析到
# 另一个图元。
const GP_LEGACY_ALIASES: Dictionary = {
	"angle_safety_valve_spring_loaded": "DVALVE001",
	"arrow_for_inlet_of_essential_substances": "DGENERAL001",
	"arrow_for_outlet_of_essential_substances": "DGENERAL002",
	"ball_valve": "DVALVE002",
	"blind_cover": "DGENERAL003",
	"butterfly_valve": "DVALVE003",
	"centrifugal_pump": "DPUMP001",
	"controlled_actuator": "DGENERAL004",
	"direction_of_flow_for_primary_segment": "DGENERAL005",
	"direction_of_flow_for_secondary_segment": "DGENERAL006",
	"floating_head_tube_bundle_heat_exchanger": "DHEAT001",
	"globe_valve": "DVALVE004",
	"instrumentation_bubble_central": "DINSTRUMENT001",
	"instrumentation_bubble_field": "DINSTRUMENT002",
	"manhole": "DGENERAL007",
	"nozzle": "DGENERAL008",
	"piping_insulated": "DGENERAL009",
	"plate_type_heat_exchanger": "DHEAT002",
	"reciprocating_pump": "DPUMP002",
	"reducer_general": "DGENERAL010",
	"slope": "DGENERAL011",
	"swing_check_valve": "DVALVE005",
	"t_type_connection": "DGENERAL012",
	"vessel_with_dished_heads": "DTANK001",
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
	if gpSource != GP_SOURCE_LIBRARY and gpSource != GP_SOURCE_CUSTOM \
			and gpSource != GP_SOURCE_DEXPI:
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
		var gpErr: Error = _gpRe.compile("^([LCD])([A-Z]+)([0-9]{%d})$" % GP_SEQ_DIGITS)
		if gpErr != OK:
			push_error("GPSymbolNaming: regex compile failed (%d)" % gpErr)
	return _gpRe
