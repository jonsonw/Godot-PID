class_name GPDeliverableRules
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Which deliverable list a symbol belongs to — and, just as important, which symbols are
# NOT rows at all (fittings, mounted children, annotations).
# 一个图元属于哪张交付清单 —— 同样重要的是，哪些图元根本不成行（管件、挂载子件、注释）。
#
# THIS IS NOT THE DEXPI ROLE / 这不是 DEXPI role 的同义词：
# DEXPI puts valves and instruments under <Equipment>. A deliverable list must split them:
# valves go to the Valve List, instruments to the Instrument Index, fittings are not exported.
# So this table reads `GPDexpiMapping` as a fallback (class/role) but makes the product
# decision explicitly. Both tables have coverage tests; neither pretends to be the other.
# DEXPI 把阀门、仪表都归为 <Equipment>；交付清单必须分流：阀门进阀门表、仪表进仪表索引、
# 管件不导出。故本表把 `GPDexpiMapping` 的类名/角色当兜底，但产品归属由本表显式决定。
# 两张表都有覆盖测试，谁也不冒充谁。
#
# WHY FITTINGS ARE IGNORED / 为何管件不导出：
# user decision 2026-10-19: fittings (blind / reducer / tee) do not appear in any list.
# They still affect line length and geometry; they are simply not deliverable rows.
# 用户 2026-10-19 拍板：管件（盲板/异径/三通）不出现在任何清单；它们仍影响长度与几何，
# 只是不成为交付行。
#
# Coding rule: every variable declares its type explicitly; every function is static (pure).
# 编码规范：所有变量显式声明类型；函数全部静态（纯函数）。

# Classification kinds / 分类取值。
const GP_KIND_EQUIPMENT: String = "equipment"
const GP_KIND_INSTRUMENT: String = "instrument"
const GP_KIND_VALVE: String = "valve"
const GP_KIND_FITTING: String = "fitting"
const GP_KIND_MOUNTED: String = "mounted"
const GP_KIND_ANNOTATION: String = "annotation"
const GP_KIND_UNKNOWN: String = "unknown"

# Every kind this table can return. / 本表可能返回的全部 kind。
const GP_ALL_KINDS: Array = [
	GP_KIND_EQUIPMENT, GP_KIND_INSTRUMENT, GP_KIND_VALVE,
	GP_KIND_FITTING, GP_KIND_MOUNTED, GP_KIND_ANNOTATION, GP_KIND_UNKNOWN,
]

# Equipment categories that are always equipment. / 必然是设备的类别。
const GP_EQUIPMENT_CATEGORIES: Dictionary = {
	"pump": true,
	"tank": true,
	"heat": true,
}

# Mount kinds that make a symbol a MOUNTED CHILD (never a row of its own).
# 使图元成为**挂载子件**的 mount kind（永不单独成行）。
# NOZZLE / MANHOLE / INSULATION / ACTUATOR are attachments: they are summarised on the host.
# NOZZLE / MANHOLE / INSULATION / ACTUATOR 都是附件：在宿主行上汇总。
const GP_MOUNTED_KINDS: Dictionary = {
	"NOZZLE": true,
	"MANHOLE": true,
	"INSULATION": true,
	"ACTUATOR": true,
}

# Categories that always mean instrument / valve regardless of DEXPI role.
# 无论 DEXPI role 如何，必然表示仪表 / 阀门的类别。
const GP_INSTRUMENT_CATEGORY: String = "instrument"
const GP_VALVE_CATEGORY: String = "valve"


# Classify one definition. Returns a fresh dictionary:
#   {kind, role, class, unknown, reason}
# 分类一个图元定义。返回新字典：{kind, role, class, unknown, reason}。
static func gpClassificationOf(gpDef: GPSymbolDef) -> Dictionary:
	var gpOut: Dictionary = {
		"kind": GP_KIND_UNKNOWN,
		"role": "",
		"class": "",
		"unknown": false,
		"reason": "",
	}
	if gpDef == null:
		gpOut["kind"] = GP_KIND_UNKNOWN
		gpOut["reason"] = "missing_def"
		return gpOut

	# 1) Type-level facts first: a mounted child is never a row, whatever its category.
	# 1) 先看类型层：挂载子件永不单独成行，不论类别。
	if GP_MOUNTED_KINDS.has(gpDef.gpMountKind):
		gpOut["kind"] = GP_KIND_MOUNTED
		gpOut["reason"] = "mount_kind:" + gpDef.gpMountKind
		gpOut["role"] = gpRoleOf(gpDef)
		gpOut["class"] = gpClassNameOf(gpDef)
		return gpOut

	# 2) Explicit categories beat the DEXPI role (instruments/valves are <Equipment> there).
	# 2) 显式类别优先于 DEXPI role（那里仪表/阀门也是 <Equipment>）。
	if gpDef.gpCategory == GP_INSTRUMENT_CATEGORY:
		gpOut["kind"] = GP_KIND_INSTRUMENT
		gpOut["reason"] = "category:instrument"
		gpOut["role"] = gpRoleOf(gpDef)
		gpOut["class"] = gpClassNameOf(gpDef)
		return gpOut
	if gpDef.gpCategory == GP_VALVE_CATEGORY:
		gpOut["kind"] = GP_KIND_VALVE
		gpOut["reason"] = "category:valve"
		gpOut["role"] = gpRoleOf(gpDef)
		gpOut["class"] = gpClassNameOf(gpDef)
		return gpOut
	# Annotation templates are type-layer symbols with category "annotation" and no DEXPI row.
	# Without this explicit branch they would fall through to the unknown=equipment fallback.
	# 注释模板是 category="annotation" 且无 DEXPI 行的类型层图元；缺这一分支会掉进
	# 「未知→设备」兜底。
	if gpDef.gpCategory == "annotation":
		gpOut["kind"] = GP_KIND_ANNOTATION
		gpOut["reason"] = "category:annotation"
		gpOut["role"] = gpRoleOf(gpDef)
		gpOut["class"] = gpClassNameOf(gpDef)
		return gpOut
	if GP_EQUIPMENT_CATEGORIES.has(gpDef.gpCategory):
		gpOut["kind"] = GP_KIND_EQUIPMENT
		gpOut["reason"] = "category:" + gpDef.gpCategory
		gpOut["role"] = gpRoleOf(gpDef)
		gpOut["class"] = gpClassNameOf(gpDef)
		return gpOut

	# 3) Fall back to the DEXPI role. Fittings / annotations / actuators are ignored.
	# 3) 回落到 DEXPI role。管件 / 注释 / 执行机构不导出。
	var gpRole: String = gpRoleOf(gpDef)
	gpOut["role"] = gpRole
	gpOut["class"] = gpClassNameOf(gpDef)
	if gpRole == GPDexpiMapping.GP_ROLE_PIPING:
		gpOut["kind"] = GP_KIND_FITTING
		gpOut["reason"] = "role:piping_component"
		return gpOut
	if gpRole == GPDexpiMapping.GP_ROLE_ANNOTATION:
		gpOut["kind"] = GP_KIND_ANNOTATION
		gpOut["reason"] = "role:annotation"
		return gpOut
	if gpRole == GPDexpiMapping.GP_ROLE_ACTUATING:
		gpOut["kind"] = GP_KIND_MOUNTED
		gpOut["reason"] = "role:actuating"
		return gpOut

	# 4) Unknown/user symbols are an EQUIPMENT fallback, reported — never silently dropped.
	# 4) 未知/用户图元兜底进设备表并报告 —— 绝不静默丢弃。
	gpOut["kind"] = GP_KIND_EQUIPMENT
	gpOut["unknown"] = true
	gpOut["reason"] = "fallback:equipment"
	return gpOut


# Lists a definition belongs to. Empty means "no row" (fitting / mounted / annotation).
# 图元属于哪些清单。空表示「不成行」（管件/挂载/注释）。
static func gpListsForDef(gpDef: GPSymbolDef) -> Array[String]:
	var gpOut: Array[String] = []
	var gpClass: Dictionary = gpClassificationOf(gpDef)
	match str(gpClass.get("kind", GP_KIND_UNKNOWN)):
		GP_KIND_EQUIPMENT:
			gpOut.append(GPDeliverableFields.GP_LIST_EQUIPMENT)
		GP_KIND_INSTRUMENT:
			gpOut.append(GPDeliverableFields.GP_LIST_INSTRUMENT)
		GP_KIND_VALVE:
			gpOut.append(GPDeliverableFields.GP_LIST_VALVE)
		_:
			pass
	return gpOut


# Whether a classification kind becomes a row in one of the four lists.
# 某个分类是否会在四张表中成行。
static func gpIsRowKind(gpKind: String) -> bool:
	return gpKind == GP_KIND_EQUIPMENT or gpKind == GP_KIND_INSTRUMENT or gpKind == GP_KIND_VALVE


# Whether a classification kind is an INLINE component for line endpoint resolution.
# 某个分类是否为管线端点解析中的**内联件**。
# Valves and fittings sit ON a line: they are components, not its terminals. Mounted children
# (a nozzle) are terminals — a pipe really ends at the nozzle.
# 阀门与管件在管线上：它们是部件，不是端点。挂载子件（管口）是端点 —— 管子确实止于管口。
static func gpIsInlineKind(gpKind: String) -> bool:
	return gpKind == GP_KIND_VALVE or gpKind == GP_KIND_FITTING


# Whether a definition is a mounted child by its own mount kind.
# 定义是否按 mount kind 属于挂载子件。
static func gpIsMountedKind(gpDef: GPSymbolDef) -> bool:
	return gpDef != null and GP_MOUNTED_KINDS.has(gpDef.gpMountKind)


# DEXPI role of a definition ("" when unmapped). / 定义的 DEXPI role（未映射为空）。
static func gpRoleOf(gpDef: GPSymbolDef) -> String:
	if gpDef == null:
		return ""
	var gpRow: Variant = GPDexpiMapping.GP_SYMBOLS.get(gpDef.gpId)
	if gpRow is Dictionary:
		return str((gpRow as Dictionary).get("role", ""))
	return ""


# DEXPI class of a definition ("" when unmapped). / 定义的 DEXPI 类名（未映射为空）。
static func gpClassNameOf(gpDef: GPSymbolDef) -> String:
	if gpDef == null:
		return ""
	var gpRow: Variant = GPDexpiMapping.GP_SYMBOLS.get(gpDef.gpId)
	if gpRow is Dictionary:
		return str((gpRow as Dictionary).get("class", ""))
	return ""


# A human-readable reason for a classification (tests / diagnostics). / 分类原因（测试/诊断）。
static func gpReasonOf(gpDef: GPSymbolDef) -> String:
	return str(gpClassificationOf(gpDef).get("reason", ""))
