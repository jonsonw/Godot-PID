class_name GPProjectStandard
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# The PROJECT STANDARD: one numbering convention, shared by every sheet, exportable to the
# next project (ADR-36).
# 项目标准：一套编号约定，所有图纸共享，并可导出给下一个工程（ADR-36）。
#
# WHY THIS EXISTS / 为何需要它：
# numbering used to live in `GPTagRule` + `GPProjectTagRules` ON EACH SHEET'S GRAPH. That made
# a multi-sheet project number every sheet from 1001 and, worse, made the rules of sheet 2
# vanish on save (the container-level `tag_rules` key was taken from the FIRST sheet only).
# The standard is the single owner of the convention: rules per numbering class, code tables
# (medium / material / insulation / …), the symbol→class mapping, and the per-class sequence
# marks. Every sheet's graph ADOPTS the same instance, so a mark advanced on sheet 1 is
# visible on sheet 2.
# 编号此前是「每张图纸的图」上的 `GPTagRule` + `GPProjectTagRules`。这使多图纸工程每页都从
# 1001 起编，更糟的是第二页改的规则存不下来（容器级 `tag_rules` 只取第一张图纸）。本类成为
# 这套约定的唯一持有者：按编号类别的规则、代号表（介质/材料/保温…）、图元→类别映射，以及
# 各类别的序号水位线。每张图纸的图**采纳同一个实例**，故第一页推进的水位线第二页看得见。
#
# BACKWARD COMPATIBILITY, ON PURPOSE / 刻意的向后兼容：
# a project whose file carries the v1 shape (`default` / `overrides` / `seq_marks`) loads in
# LEGACY mode: it holds only the equipment rules and WRITES THE V1 SHAPE BACK, byte for byte.
# It upgrades to v2 the first time a v2-only field is touched (code tables, another class,
# the classification). This is what keeps the existing archives stable — see ADR-36 D12.
# 携带 v1 形态（`default` / `overrides` / `seq_marks`）的工程以**legacy 模式**载入：只持有设备
# 规则，且**按 v1 形态逐字节写回**。首次触及 v2 独有字段（代号表、其它类别、分类映射）时才升格。
# 这正是既有存档保持稳定的原因 —— 见 ADR-36 D12。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Format identity. `GP_SCHEMA` names the standard package; `GP_VERSION` is the in-file version.
# 格式标识。`GP_SCHEMA` 指标准包格式；`GP_VERSION` 是文件内版本。
const GP_SCHEMA: String = "gpid.standard/1"
const GP_VERSION: int = 2

# Numbering classes (ADR-36 D3). Stable ids: they are written into the project file.
# 编号类别（ADR-36 D3）。id 稳定：会写进工程文件。
const GP_CLASS_EQUIPMENT: String = "equipment"
const GP_CLASS_INSTRUMENT: String = "instrument"
const GP_CLASS_LINE: String = "line"
const GP_CLASS_MANUAL_VALVE: String = "manual_valve"
const GP_CLASS_SPECIAL_ITEM: String = "special_item"

const GP_CLASS_IDS: Array[String] = [
	"equipment", "instrument", "line", "manual_valve", "special_item",
]

# Uniqueness scopes (ADR-36 D6). "project" = one namespace across all sheets;
# "sheet" = one namespace per sheet (lines, with the cross-sheet continuation exception).
# 唯一性作用域（ADR-36 D6）。project = 跨全部图纸一个命名空间；sheet = 每张图纸一个
#（管线，跨页延续属例外）。
const GP_SCOPE_PROJECT: String = "project"
const GP_SCOPE_SHEET: String = "sheet"

# Code table ids. Missing tables are legal — they only mean placeholder codes get used.
# 代号表 id。表缺失是合法的 —— 只意味着会用到空缺代号。
const GP_TABLE_MEDIUM: String = "medium"
const GP_TABLE_MATERIAL: String = "material"
const GP_TABLE_INSULATION: String = "insulation"
const GP_TABLE_DISCIPLINE: String = "discipline"
const GP_TABLE_AREA: String = "area"
const GP_TABLE_DN: String = "dn"

const GP_TABLE_IDS: Array[String] = [
	"medium", "material", "insulation", "discipline", "area", "dn",
]

# Factory prefixes for the single-segment (legacy-shaped) class rules. Equipment keeps the
# historic by-category table so existing archives number exactly as before.
# 单段（旧形态）类别规则的出厂前缀。设备保留历史「按类别」表，使既有存档编号与以前完全一致。
const GP_CLASS_PREFIXES: Dictionary = {
	"instrument": "I",
	"line": "PL",
	"manual_valve": "V",
	"special_item": "SP",
}

# Factory code tables: deliberately tiny (user decision 2026-10-26 — bulk entry lands in
# batch B). They exist so a code lookup can be demonstrated; empty is not an error.
# 出厂代号表：刻意极简（用户 2026-10-26 决定 —— 批量录入在 B 批次）。它们只为演示查表；
# 空表不是错误。
const GP_SEED_MEDIUM: Array = [
	{"code": "PW", "label": "工艺水", "aliases": ["Process Water"]},
	{"code": "CWR", "label": "循环冷却水", "aliases": ["Cooling Water Return"]},
]

const GP_SEED_DISCIPLINE: Array = [
	{"code": "PI", "label": "工艺", "aliases": ["Process"]},
	{"code": "UI", "label": "公用", "aliases": ["Utility"]},
]

# Pipe class (管道等级 / 材料等级) — the factory set every new project starts from. The codes are
# the ones used in the line designation's MTL segment; aliases let a user type the Chinese name.
# 管道等级（材料等级）—— 每个新工程的出厂集。代号即管线代号 MTL 段的取值；别名允许用户直接写中文名。
const GP_SEED_MATERIAL: Array = [
	{"code": "A1A", "label": "碳钢 20#", "aliases": ["碳钢", "Carbon Steel"]},
	{"code": "A2A", "label": "不锈钢 304", "aliases": ["304", "不锈钢"]},
	{"code": "A3A", "label": "不锈钢 316L", "aliases": ["316L", "316"]},
	{"code": "B1A", "label": "合金钢", "aliases": ["Alloy Steel"]},
]

# Insulation / 保温保冷.
const GP_SEED_INSULATION: Array = [
	{"code": "H", "label": "保温", "aliases": ["Hot Insulation", "热保温"]},
	{"code": "C", "label": "保冷", "aliases": ["Cold Insulation", "冷保温"]},
	{"code": "P", "label": "人身防护", "aliases": ["Personnel Protection"]},
	{"code": "T", "label": "伴热", "aliases": ["Tracing"]},
	{"code": "N", "label": "无保温", "aliases": ["None", "无"]},
]

# Display names for the code tables (the dialog shows "material · 管道等级", not a raw id).
# 代号表的显示名（对话框显示「material · 管道等级」，而不是裸 id）。
const GP_TABLE_LABELS: Dictionary = {
	"medium": "介质代码",
	"material": "管道等级",
	"insulation": "保温/保冷",
	"discipline": "专业代码",
	"area": "区域代码",
	"dn": "管径",
}

# Factory symbol→class mapping. Category first, then the valve actuator refinement; unknown
# symbols get "" (= not numbered automatically), which DRC reports as `tag_class_unmapped`.
# 出厂「图元→类别」映射。先按类别，再对阀门按执行机构细化；未知图元得 ""（= 不自动编号），
# 由 DRC 报 `tag_class_unmapped`。
const GP_DEFAULT_BY_CATEGORY: Dictionary = {
	"pump": "equipment",
	"tank": "equipment",
	"heat": "equipment",
	"instrument": "instrument",
	"valve": "manual_valve",
}

const GP_DEFAULT_VALVE_BY_ACTUATOR: Dictionary = {
	"手动": "manual_valve",
	"无": "manual_valve",
	"气动": "instrument",
	"电动": "instrument",
	"液动": "instrument",
}

# ---- state ----

# True while this standard came from a v1 file and has not been upgraded. In this mode
# gpToDict() emits the v1 shape, so an old archive re-saves byte for byte.
# 当本标准来自 v1 文件且未升格时为 true。此模式 gpToDict() 输出 v1 形态，故旧存档保存后逐字节不变。
var gpLegacy: bool = false

# Human-facing revision block of the standard package (name / vendor / rev / updated_at).
# 标准包的对人可读修订块（名称 / 厂家 / 修订 / 日期）。
var gpRevision: Dictionary = {}

# Uniqueness scope settings. `line_unique` is "sheet"; `line_cross_sheet` is "declared"
# (same number allowed across sheets, DRC asks for the continuation declaration).
# 唯一性作用域设置。line_unique 为 sheet；line_cross_sheet 为 declared
#（允许跨页同号，DRC 要求延续声明）。
var gpScope: Dictionary = {}

# class id -> GPProjectTagRules (one rule set per class, including its own sequence marks).
# class id -> GPProjectTagRules（每个类别一套规则，含自己的序号水位线）。
var gpClasses: Dictionary = {}

# class id -> {"enabled": bool, "scope": String}.
# class id -> {"enabled": bool, "scope": String}。
var gpClassMeta: Dictionary = {}

# table id -> Array of {"code", "label", "aliases"}.
# 表 id -> {"code","label","aliases"} 数组。
var gpCodeTables: Dictionary = {}

# {"by_category": {}, "by_symbol": {}, "valve_by_actuator": {}}.
var gpClassification: Dictionary = {}

# Project information shared by every sheet (业主 / 项目名称 / 设计阶段 / 校审人员 …). The title
# block inherits from here, so a project fills these ONCE instead of on every sheet.
# 全图纸共享的项目信息（业主 / 项目名称 / 设计阶段 / 校审人员…）。标题栏从这里继承，故一个工程
# 只填一次，而不是每张图纸各填一遍。
# Keys are fixed; each value is a plain string (bilingual sheets show the same text in both
# lines — engineering offices rarely translate the client's name).
# 键固定；值为纯字符串（中英对照图纸两行显示同一段文字 —— 设计院很少翻译业主名称）。
var gpProjectInfo: Dictionary = {}

# Drawing-number rule: {template, start, step}. Placeholders: {project_no}, {project_name},
# {stage}, {seq} and {seq:N}. A sheet number is derived from this + the sheet's sequence.
# 图纸编号规则：{template, start, step}。占位符：{project_no}、{project_name}、{stage}、
# {seq} 与 {seq:N}。图纸编号由它 + 该图纸的序号推导。
var gpSheetNoRule: Dictionary = {}

# Whether this project has already been through the "factory code tables" migration. A project
# saved before the material/insulation seeds existed has those tables EMPTY; without this flag
# every reopen would re-seed them and resurrect rows the user deliberately deleted.
# 本工程是否已执行过「出厂代号表」迁移。在材料/保温种子存在之前保存的工程，这两张表是**空的**；
# 没有这个标志，每次重开都会重新灌入，把用户刻意删掉的行又复活。
var gpSeedMigrated: bool = false

# DRC configuration + waivers (ADR-39 D7). Kept as a plain dictionary so it rides the same
# archive path as the rest of the standard. Absent = factory defaults; never a null dereference.
# DRC 配置与豁免（ADR-39 D7）。保持普通字典，随标准走同一条存档路径。缺省 = 出厂默认，
# 绝不解引用空值。
var gpValidation: Dictionary = {}


# ==================== factory / 出厂 ====================

# Build the factory standard: equipment keeps the historic convention, every other class is
# pre-wired but (except special items) disabled until the project turns it on.
# 构造出厂标准：设备保留历史约定；其它类别已接好线，但除特殊件外默认关闭，由工程开启。
static func gpDefaultStandard() -> GPProjectStandard:
	var gpS: GPProjectStandard = GPProjectStandard.new()
	gpS.gpLegacy = false
	gpS.gpRevision = {
		"name": "", "vendor": "", "rev": "A", "updated_at": "",
	}
	gpS.gpScope = {
		"line_unique": GP_SCOPE_SHEET,
		"line_cross_sheet": "declared",
	}
	gpS.gpClasses = {}
	gpS.gpClassMeta = {}
	for gpClass in GP_CLASS_IDS:
		gpS.gpClasses[gpClass] = _gpFactoryRules(gpClass)
	var gpManual: Dictionary = {
		"enabled": false, "scope": GP_SCOPE_PROJECT,
	}
	var gpOn: Dictionary = {"enabled": true, "scope": GP_SCOPE_PROJECT}
	var gpLine: Dictionary = {"enabled": true, "scope": GP_SCOPE_SHEET}
	gpS.gpClassMeta = {
		GP_CLASS_EQUIPMENT: gpOn.duplicate(),
		GP_CLASS_INSTRUMENT: gpOn.duplicate(),
		GP_CLASS_LINE: gpLine,
		GP_CLASS_MANUAL_VALVE: gpManual,
		GP_CLASS_SPECIAL_ITEM: gpOn.duplicate(),
	}
	gpS.gpCodeTables = {
		GP_TABLE_MEDIUM: (GP_SEED_MEDIUM as Array).duplicate(true),
		GP_TABLE_MATERIAL: (GP_SEED_MATERIAL as Array).duplicate(true),
		GP_TABLE_INSULATION: (GP_SEED_INSULATION as Array).duplicate(true),
		GP_TABLE_DISCIPLINE: (GP_SEED_DISCIPLINE as Array).duplicate(true),
		GP_TABLE_AREA: [],
		GP_TABLE_DN: [],
	}
	gpS.gpSeedMigrated = true
	gpS.gpClassification = {
		"by_category": GP_DEFAULT_BY_CATEGORY.duplicate(),
		"by_symbol": {},
		"valve_by_actuator": GP_DEFAULT_VALVE_BY_ACTUATOR.duplicate(),
	}
	gpS.gpProjectInfo = {
		"owner": "", "project_name": "", "project_no": "", "stage": "",
		"company": "", "designed": "", "checked": "", "approved": "",
	}
	gpS.gpSheetNoRule = {
		"template": "{project_no}-{seq:3}", "start": 0, "step": 1,
	}
	return gpS


# Factory rules for one class. Equipment = the historic by-category rule (byte-compatible);
# the others use a fixed prefix so a class cannot accidentally borrow another class's letters.
# 某类别的出厂规则。设备 = 历史「按类别」规则（逐字节兼容）；其余用固定前缀，
# 使一个类别不会误用另一个类别的字母。
static func _gpFactoryRules(gpClass: String) -> GPProjectTagRules:
	if gpClass == GP_CLASS_EQUIPMENT:
		return GPProjectTagRules.gpDefaultRules()
	if gpClass == GP_CLASS_LINE:
		# ADR-36 D3: the factory line rule is the user's five-field designation
		# (SIZE-SERV-NUMB-MTL-IN), not a single "PL-1001" counter.
		# ADR-36 D3：出厂管线规则是用户选定的五段代号（管径-介质-流水号-材料-保温），
		# 而不是单一 "PL-1001" 计数器。
		var gpLineRules: GPProjectTagRules = GPProjectTagRules.new()
		gpLineRules.gpDefault = GPTagRulePresets.gpLineCompact()
		return gpLineRules
	var gpRules: GPProjectTagRules = GPProjectTagRules.gpDefaultRules()
	var gpRule: GPTagRule = gpRules.gpDefault
	gpRule.gpPrefixSource = GPTagRule.GPPrefixSource.GP_FIXED
	gpRule.gpFixedPrefix = str(GP_CLASS_PREFIXES.get(gpClass, "X"))
	return gpRules


# Every class id, in UI order. Kept as a function (not the const) so callers cannot mutate it.
# 全部类别 id，按界面顺序。以函数而非常量暴露，使调用方无法改动它。
static func gpClassIds() -> Array[String]:
	var gpOut: Array[String] = []
	for gpClass in GP_CLASS_IDS:
		gpOut.append(gpClass)
	return gpOut


# Factory rows for one code table. Used by the migration above and by the dialog's
# "load factory examples" button, so both sources stay identical.
# 某张代号表的出厂行。迁移与对话框的「载入出厂示例」按钮共用它，故两处不会漂移。
static func gpFactoryTable(gpTable: String) -> Array:
	match gpTable:
		GP_TABLE_MEDIUM:
			return (GP_SEED_MEDIUM as Array).duplicate(true)
		GP_TABLE_MATERIAL:
			return (GP_SEED_MATERIAL as Array).duplicate(true)
		GP_TABLE_INSULATION:
			return (GP_SEED_INSULATION as Array).duplicate(true)
		GP_TABLE_DISCIPLINE:
			return (GP_SEED_DISCIPLINE as Array).duplicate(true)
	return []


# Fallback label (headless / pre-i18n). The dialog maps these through I18n.
# 回退显示名（headless / i18n 之前）。对话框再经 I18n 映射。
static func gpClassLabel(gpClass: String) -> String:
	match gpClass:
		GP_CLASS_EQUIPMENT:
			return "设备"
		GP_CLASS_INSTRUMENT:
			return "仪表"
		GP_CLASS_LINE:
			return "管线"
		GP_CLASS_MANUAL_VALVE:
			return "手动阀门"
		GP_CLASS_SPECIAL_ITEM:
			return "特殊件"
	return gpClass


# ==================== class rules / 类别规则 ====================

# Rules of one class. Unknown / missing classes fall back to the equipment rules, so a
# half-built standard can never hand out a null.
# 某类别的规则。未知 / 缺失类别回落到设备规则，故半构造的标准绝不会交出 null。
# Every code-table id the editor should show: the six built-ins plus any table referenced by a
# rule segment (a user-created field can name its own table) and any table already stored.
# 编辑器应显示的全部代号表 id：六个内置表 + 规则段引用的表（用户新建字段可自带表名）+
# 已经存储的表。
func gpTableIds() -> Array[String]:
	var gpOut: Array[String] = []
	for gpId in GP_TABLE_IDS:
		if not gpOut.has(gpId):
			gpOut.append(gpId)
	for gpClass in GP_CLASS_IDS:
		var gpRules: GPProjectTagRules = gpRulesOf(gpClass)
		if gpRules == null:
			continue
		var gpRuleList: Array = [gpRules.gpDefault]
		for gpOverrideRaw in gpRules.gpOverrides.values():
			gpRuleList.append(gpOverrideRaw)
		for gpRuleRaw in gpRuleList:
			var gpRule: GPTagRule = gpRuleRaw as GPTagRule
			if gpRule == null:
				continue
			for gpSegRaw in gpRule.gpSegments:
				var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
				if gpSeg != null and gpSeg.gpTable != "" and not gpOut.has(gpSeg.gpTable):
					gpOut.append(gpSeg.gpTable)
	for gpTableRaw in gpCodeTables.keys():
		var gpTable: String = str(gpTableRaw)
		if gpTable != "" and not gpOut.has(gpTable):
			gpOut.append(gpTable)
	return gpOut


func gpRulesOf(gpClass: String) -> GPProjectTagRules:
	_gpEnsureClasses()
	var gpFound: Variant = gpClasses.get(gpClass, null)
	if gpFound is GPProjectTagRules:
		return gpFound as GPProjectTagRules
	return gpClasses[GP_CLASS_EQUIPMENT] as GPProjectTagRules


# Replace one class's rules (marks included). Upgrades a legacy standard to v2.
# 替换某类别的规则（含水位线）。会把 legacy 标准升格为 v2。
func gpSetRulesOf(gpClass: String, gpRules: GPProjectTagRules) -> void:
	if gpRules == null:
		return
	_gpEnsureClasses()
	gpClasses[gpClass] = gpRules
	gpTouch()


# Meta (enabled / scope) of one class, never null.
# 某类别的元信息（启用 / 作用域），绝不返回 null。
func gpMetaOf(gpClass: String) -> Dictionary:
	_gpEnsureClasses()
	var gpFound: Variant = gpClassMeta.get(gpClass, null)
	if gpFound is Dictionary:
		return gpFound as Dictionary
	return {"enabled": false, "scope": GP_SCOPE_PROJECT}


# Whether a class mints tags automatically.
# 某类别是否自动铸号。
func gpEnabled(gpClass: String) -> bool:
	return bool(gpMetaOf(gpClass).get("enabled", false))


# Enable / disable automatic numbering for a class.
# 启用 / 停用某类别的自动编号。
func gpSetEnabled(gpClass: String, gpOn: bool) -> void:
	_gpEnsureClasses()
	var gpMeta: Dictionary = gpMetaOf(gpClass)
	gpMeta["enabled"] = gpOn
	gpClassMeta[gpClass] = gpMeta
	gpTouch()


# Uniqueness scope of a class ("project" / "sheet").
# 某类别的唯一性作用域（project / sheet）。
func gpScopeOf(gpClass: String) -> String:
	if gpClass == GP_CLASS_LINE:
		return str(gpScope.get("line_unique", GP_SCOPE_SHEET))
	return str(gpMetaOf(gpClass).get("scope", GP_SCOPE_PROJECT))


# Whether the same number may legitimately appear on another sheet (line continuation).
# 同一个号是否可以合法地出现在另一张图纸上（管线延续）。
func gpAllowsCrossSheet(gpClass: String) -> bool:
	return gpClass == GP_CLASS_LINE and gpScopeOf(gpClass) == GP_SCOPE_SHEET


# ==================== code tables / 代号表 ====================

# Rows of one code table (never null; unknown tables come back empty).
# 某代号表的行（绝不返回 null；未知表返回空数组）。
func gpCodeTable(gpTable: String) -> Array:
	var gpRows: Variant = gpCodeTables.get(gpTable, null)
	return (gpRows as Array) if gpRows is Array else []


# Replace one code table. Upgrades a legacy standard to v2.
# 替换某代号表。会把 legacy 标准升格为 v2。
func gpSetCodeTable(gpTable: String, gpRows: Array) -> void:
	gpCodeTables[gpTable] = gpRows.duplicate(true)
	gpTouch()


# Resolve a raw attribute value to its code, or "" when the table has no such entry.
# Comparison is whitespace/case-insensitive and also matches the label and any alias, so
# "循环冷却水", "cwr" and "Cooling Water Return" all resolve to CWR.
# 把原始属性值解析为代号；表里没有该条目时返回 ""。比较忽略空白与大小写，并匹配名称与任一别名，
# 故「循环冷却水」「cwr」「Cooling Water Return」都解析为 CWR。
func gpCodeOf(gpTable: String, gpRaw: String) -> String:
	var gpWant: String = _gpNormCode(gpRaw)
	if gpWant == "":
		return ""
	for gpRowRaw in gpCodeTable(gpTable):
		if not (gpRowRaw is Dictionary):
			continue
		var gpRow: Dictionary = gpRowRaw as Dictionary
		var gpCode: String = str(gpRow.get("code", ""))
		if _gpNormCode(gpCode) == gpWant:
			return gpCode
		if _gpNormCode(str(gpRow.get("label", ""))) == gpWant:
			return gpCode
		for gpAliasRaw in (gpRow.get("aliases", []) as Array):
			if _gpNormCode(str(gpAliasRaw)) == gpWant:
				return gpCode
	return ""


# ==================== classification / 分类映射 ====================

# Which numbering class a symbol instance belongs to ("" = not numbered automatically).
# `gpProps` is the INSTANCE's property map, because a valve's class depends on its actuator.
# 一个图元实例属于哪个编号类别（"" = 不自动编号）。`gpProps` 是**实例**属性表，
# 因为阀门的类别取决于它的执行机构。
func gpClassOf(gpDef: GPSymbolDef, gpProps: Dictionary = {}) -> String:
	if gpDef == null:
		return ""
	var gpBySym: Dictionary = gpClassification.get("by_symbol", {}) as Dictionary
	if gpBySym.has(gpDef.gpId):
		return str(gpBySym[gpDef.gpId])
	var gpByCat: Dictionary = gpClassification.get("by_category", {}) as Dictionary
	var gpBase: String = str(gpByCat.get(gpDef.gpCategory, ""))
	# Only valves are refined by their actuator. Doing it for every category would let a
	# stray `actuator_type` property reclassify a pump.
	# 只有阀门按执行机构细化；对每类都做会让一个多余的 `actuator_type` 属性把泵改了类。
	if gpBase == GP_CLASS_MANUAL_VALVE or gpDef.gpCategory == "valve":
		var gpMap: Dictionary = gpClassification.get("valve_by_actuator", {}) as Dictionary
		var gpAct: String = str(gpProps.get("actuator_type", ""))
		if gpMap.has(gpAct):
			return str(gpMap[gpAct])
	return gpBase


# ==================== validation / 校验 ====================

# Validate every class rule and every code table. Returns the first failure, tagged with
# the class / table it came from, so the dialog can point at the right field.
# 校验全部类别规则与代号表。返回首个失败并标明所属类别 / 表，使对话框能指到对的字段。
func gpValidate() -> GPIOResult:
	_gpEnsureClasses()
	for gpClass in GP_CLASS_IDS:
		var gpRules: GPProjectTagRules = gpRulesOf(gpClass)
		var gpOne: GPIOResult = gpRules.gpValidate()
		if not gpOne.gpIsOk():
			gpOne.gpDetail = "%s (%s)" % [gpOne.gpDetail, gpClass]
			return gpOne
	for gpTableRaw in gpCodeTables.keys():
		var gpTable: String = str(gpTableRaw)
		var gpSeen: Dictionary = {}
		for gpRowRaw in gpCodeTable(gpTable):
			if not (gpRowRaw is Dictionary):
				return GPIOResult.gpFailure("standard.bad_table_row", "standard.err_bad_row",
					gpTable)
			var gpCode: String = str((gpRowRaw as Dictionary).get("code", "")).strip_edges()
			if gpCode == "":
				return GPIOResult.gpFailure("standard.empty_code", "standard.err_empty_code",
					gpTable)
			var gpNorm: String = _gpNormCode(gpCode)
			if gpSeen.has(gpNorm):
				return GPIOResult.gpFailure("standard.duplicate_code",
					"standard.err_duplicate_code", "%s (%s)" % [gpCode, gpTable])
			gpSeen[gpNorm] = true
	return GPIOResult.gpSuccess()


# ==================== legacy switch / 旧档兼容开关 ====================

# Whether this standard is still in v1 shape (writes v1 back).
# 本标准是否仍处 v1 形态（按 v1 写回）。
func gpIsLegacy() -> bool:
	return gpLegacy


# Leave legacy mode: from now on the file carries the v2 shape. Called by every v2-only setter.
# 退出 legacy 模式：此后文件携带 v2 形态。每个 v2 独有 setter 都会调用它。
func gpTouch() -> void:
	gpLegacy = false


# ==================== DRC validation / DRC 校验 ====================

# Normalised DRC config (defaults + this project's overrides + waivers).
# 归一化的 DRC 配置（默认值 + 本工程覆盖 + 豁免）。
func gpValidationConfig() -> Dictionary:
	return GPDRCConfig.gpNormalize(gpValidation)


# Replace the DRC config. Always stored normalised so the next read sees one shape.
# 替换 DRC 配置。始终存归一化形态，使下一次读取只有一种形状。
func gpSetValidationConfig(gpCfg: Dictionary) -> void:
	gpValidation = GPDRCConfig.gpNormalize(gpCfg)
	gpTouch()


# ==================== persistence / 持久化 ====================

# Serialise. Legacy standards emit the v1 shape EXACTLY as GPProjectTagRules always did, so a
# reopened old archive is written back byte for byte (ADR-36 D12).
# 序列化。legacy 标准原样输出 v1 形态（与 GPProjectTagRules 一贯一致），故重开的旧存档逐字节写回。
func gpToDict() -> Dictionary:
	_gpEnsureClasses()
	if gpLegacy:
		return (gpClasses[GP_CLASS_EQUIPMENT] as GPProjectTagRules).gpToDict()
	var gpClassesOut: Dictionary = {}
	for gpClass in GP_CLASS_IDS:
		var gpMeta: Dictionary = gpMetaOf(gpClass)
		gpClassesOut[gpClass] = {
			"enabled": bool(gpMeta.get("enabled", false)),
			"scope": gpScopeOf(gpClass),
			"rules": gpRulesOf(gpClass).gpToDict(),
		}
	var gpOut: Dictionary = {
		"version": GP_VERSION,
		"schema": GP_SCHEMA,
		"revision": gpRevision.duplicate(true),
		"scope": gpScope.duplicate(true),
		"classes": gpClassesOut,
		"code_tables": gpCodeTables.duplicate(true),
		"classification": gpClassification.duplicate(true),
		"seed_migrated": gpSeedMigrated,
		"project_info": gpProjectInfo.duplicate(true),
		"sheet_no": gpSheetNoRule.duplicate(true),
	}
	# Only emit when the project actually customised DRC, so an untouched archive keeps its
	# previous byte shape (ADR-36 D12's "no-op saves stay identical").
	# 仅在工程确实定制过 DRC 时写出，使未触碰的存档保持原有字节形态。
	if not gpValidation.is_empty():
		gpOut["validation"] = gpValidation.duplicate(true)
	return gpOut


# Parse either shape. A dict without `version >= 2` is a v1 rules block: it becomes the
# equipment class and the standard stays in legacy mode.
# 解析两种形态。没有 `version >= 2` 的字典即 v1 规则块：它成为设备类别，标准保持 legacy 模式。
static func gpFromDict(gpD: Dictionary) -> GPProjectStandard:
	if gpD.is_empty():
		return gpDefaultStandard()
	if int(gpD.get("version", 1)) < GP_VERSION or not gpD.has("classes"):
		var gpLegacyStd: GPProjectStandard = gpDefaultStandard()
		gpLegacyStd.gpClasses[GP_CLASS_EQUIPMENT] = GPProjectTagRules.gpFromDict(gpD)
		gpLegacyStd.gpLegacy = true
		return gpLegacyStd
	var gpS: GPProjectStandard = gpDefaultStandard()
	gpS.gpLegacy = false
	var gpRev: Variant = gpD.get("revision", null)
	if gpRev is Dictionary:
		gpS.gpRevision = (gpRev as Dictionary).duplicate(true)
	var gpScopeIn: Variant = gpD.get("scope", null)
	if gpScopeIn is Dictionary:
		var gpScopeD: Dictionary = (gpScopeIn as Dictionary).duplicate(true)
		for gpKey in gpScopeD.keys():
			gpS.gpScope[str(gpKey)] = gpScopeD[gpKey]
	var gpClassesIn: Variant = gpD.get("classes", null)
	if gpClassesIn is Dictionary:
		for gpClassRaw in (gpClassesIn as Dictionary).keys():
			var gpClass: String = str(gpClassRaw)
			var gpEntry: Variant = (gpClassesIn as Dictionary)[gpClassRaw]
			if not (gpEntry is Dictionary):
				continue
			var gpEntryD: Dictionary = gpEntry as Dictionary
			gpS.gpClasses[gpClass] = GPProjectTagRules.gpFromDict(
				(gpEntryD.get("rules", {}) as Dictionary))
			gpS.gpClassMeta[gpClass] = {
				"enabled": bool(gpEntryD.get("enabled", false)),
				"scope": str(gpEntryD.get("scope", GP_SCOPE_PROJECT)),
			}
	var gpTablesIn: Variant = gpD.get("code_tables", null)
	if gpTablesIn is Dictionary:
		gpS.gpCodeTables = (gpTablesIn as Dictionary).duplicate(true)
	var gpClassIn: Variant = gpD.get("classification", null)
	if gpClassIn is Dictionary:
		gpS.gpClassification = (gpClassIn as Dictionary).duplicate(true)
	gpS.gpSeedMigrated = bool(gpD.get("seed_migrated", false))
	var gpInfoIn: Variant = gpD.get("project_info", null)
	if gpInfoIn is Dictionary:
		for gpKeyRaw in (gpInfoIn as Dictionary).keys():
			gpS.gpProjectInfo[str(gpKeyRaw)] = str((gpInfoIn as Dictionary)[gpKeyRaw])
	var gpNoIn: Variant = gpD.get("sheet_no", null)
	if gpNoIn is Dictionary:
		for gpKeyRaw in (gpNoIn as Dictionary).keys():
			gpS.gpSheetNoRule[str(gpKeyRaw)] = (gpNoIn as Dictionary)[gpKeyRaw]
	var gpValIn: Variant = gpD.get("validation", null)
	if gpValIn is Dictionary:
		gpS.gpValidation = (gpValIn as Dictionary).duplicate(true)
	# One-time migration: a project written before the material/insulation seeds existed has
	# those tables empty, which would leave the line panel without pickers. Seed them ONCE; the
	# flag makes the decision permanent, so "I deleted every row" is respected on the next open.
	# 一次性迁移：在材料/保温种子出现之前写出的工程，这两张表是空的，管线面板因此没有下拉。
	# **只灌一次**；标志让这个决定永久化，故「我把行都删了」在下次打开时依然被尊重。
	if not gpS.gpSeedMigrated:
		for gpTable in [GP_TABLE_MATERIAL, GP_TABLE_INSULATION]:
			if gpS.gpCodeTable(gpTable).is_empty():
				gpS.gpCodeTables[gpTable] = gpFactoryTable(gpTable)
		gpS.gpSeedMigrated = true
	gpS._gpEnsureClasses()
	return gpS


# Deep copy — the dialog edits a copy so Cancel stays a true no-op.
# 深拷贝 —— 对话框编辑副本，使「取消」成为真正的空操作。
func gpClone() -> GPProjectStandard:
	return GPProjectStandard.gpFromDict(gpToDict())


# ==================== internals / 内部 ====================

# Fill any missing class / table / classification entry, so a hand-edited or older standard
# never dereferences null.
# 补齐缺失的类别 / 表 / 分类项，使手改过或较旧的标准不会解引用 null。
func _gpEnsureClasses() -> void:
	if gpClasses.is_empty():
		for gpClass in GP_CLASS_IDS:
			gpClasses[gpClass] = _gpFactoryRules(gpClass)
	for gpClass in GP_CLASS_IDS:
		if not (gpClasses.get(gpClass, null) is GPProjectTagRules):
			gpClasses[gpClass] = _gpFactoryRules(gpClass)
		if not gpClassMeta.has(gpClass):
			gpClassMeta[gpClass] = {
				"enabled": gpClass != GP_CLASS_MANUAL_VALVE,
				"scope": GP_SCOPE_PROJECT if gpClass != GP_CLASS_LINE else GP_SCOPE_SHEET,
			}
	if gpScope.is_empty():
		gpScope = {"line_unique": GP_SCOPE_SHEET, "line_cross_sheet": "declared"}
	if gpProjectInfo.is_empty():
		gpProjectInfo = {
			"owner": "", "project_name": "", "project_no": "", "stage": "",
			"company": "", "designed": "", "checked": "", "approved": "",
		}
	if gpSheetNoRule.is_empty():
		gpSheetNoRule = {"template": "{project_no}-{seq:3}", "start": 0, "step": 1}
	if gpClassification.is_empty():
		gpClassification = {
			"by_category": GP_DEFAULT_BY_CATEGORY.duplicate(),
			"by_symbol": {},
			"valve_by_actuator": GP_DEFAULT_VALVE_BY_ACTUATOR.duplicate(),
		}
	else:
		for gpKey in ["by_category", "by_symbol", "valve_by_actuator"]:
			if not (gpClassification.get(gpKey, null) is Dictionary):
				gpClassification[gpKey] = {}


# Comparison form of a code / label / alias: whitespace folded away, upper-cased.
# 代号 / 名称 / 别名的比较形式：去空白、转大写。
static func _gpNormCode(gpRaw: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpRaw.length()):
		var gpC: String = gpRaw[gpI]
		if gpC == " " or gpC == "\t" or gpC == "\n" or gpC == "\r":
			continue
		gpOut += gpC
	return gpOut.to_upper()


# One project-info value, never null.
# 某个项目信息值，绝不为 null。
func gpInfo(gpKey: String) -> String:
	return str(gpProjectInfo.get(gpKey, "")).strip_edges()


# Render a drawing number for sheet sequence `gpSeq` (1-based).
# 为第 `gpSeq` 张图纸（1 起）渲染图纸编号。
func gpSheetNumberFor(gpSeq: int) -> String:
	var gpTemplate: String = str(gpSheetNoRule.get("template", "{project_no}-{seq:3}"))
	if gpTemplate.strip_edges() == "":
		gpTemplate = "{project_no}-{seq:3}"
	var gpOut: String = gpTemplate
	# {seq:N} first (longest placeholder), then the bare {seq}.
	# 先替换 {seq:N}（最长的占位符），再替换裸 {seq}。
	gpOut = _gpReplaceSeqWidth(gpOut, gpSeq)
	gpOut = gpOut.replace("{seq}", str(gpSeq))
	gpOut = gpOut.replace("{project_no}", gpInfo("project_no"))
	gpOut = gpOut.replace("{project_name}", gpInfo("project_name"))
	gpOut = gpOut.replace("{stage}", gpInfo("stage"))
	# Collapse separators left by empty placeholders ("--" -> "-"), trim stray dashes.
	# 折叠空占位符留下的分隔符（"--" → "-"），并去掉两端多余的横线。
	while gpOut.find("--") >= 0:
		gpOut = gpOut.replace("--", "-")
	if gpOut.begins_with("-"):
		gpOut = gpOut.substr(1)
	if gpOut.ends_with("-"):
		gpOut = gpOut.substr(0, gpOut.length() - 1)
	return gpOut


# Zero-padded sequence replacement for {seq:N} (same shape as GPTagRule's renderer).
# {seq:N} 的补零替换（与 GPTagRule 的渲染同形）。
static func _gpReplaceSeqWidth(gpText: String, gpSeq: int) -> String:
	var gpOut: String = ""
	var gpI: int = 0
	while gpI < gpText.length():
		if gpText.substr(gpI, 5) == "{seq:":
			var gpEnd: int = gpText.find("}", gpI)
			if gpEnd > gpI:
				var gpWidth: int = int(gpText.substr(gpI + 5, gpEnd - gpI - 5))
				var gpDigits: String = str(gpSeq)
				while gpDigits.length() < gpWidth:
					gpDigits = "0" + gpDigits
				gpOut += gpDigits
				gpI = gpEnd + 1
				continue
		gpOut += gpText[gpI]
		gpI += 1
	return gpOut
