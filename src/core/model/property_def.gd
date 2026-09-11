class_name GPPropertyDef
extends Resource
# Copyright © 2026 Jonson Wang
# One field definition in a symbol's property schema — TYPE LAYER metadata only.
# 图元属性 schema 中的单个字段定义 —— 仅属「类型层」元数据。
#
# Why this exists / 为何存在：
#   the old GPSymbolDef.gpAttrsSchema was a bare Dictionary with no type, no unit, no
#   validation and no multi-language label, so the inspector could only guess a LineEdit from
#   `.get("type")` and the library defaults never took effect. A typed Resource makes the
#   schema the single source of truth that every project instance RESOLVES against (M8).
#   旧的 GPSymbolDef.gpAttrsSchema 是无类型的裸 Dictionary：没有类型、单位、校验与多语言
#   标签，属性面板只能靠 `.get("type")` 猜一个 LineEdit，库默认值也从未生效。类型化 Resource
#   让 schema 成为唯一真源，供各项目实例解析（M8）。
#
# Invariant / 不变式：instances store VALUES only, never a copy of this definition — that is
# what makes "edit the library, every project follows" work (see GPPropertyResolver).
# 实例只存「值」，绝不快照本定义 —— 这正是「改库即全项目同步」得以成立的原因。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Value kinds. / 取值类型。
enum GPKind {
	GP_STRING,      # 单行文本 / single-line text
	GP_INT,         # 整数 / integer
	GP_FLOAT,       # 浮点（带单位）/ float (with unit)
	GP_BOOL,        # 布尔 / boolean
	GP_ENUM,        # 枚举（选项来自 gpOptions）/ enum driven by gpOptions
	GP_TEXT,        # 多行文本 / multi-line text
	GP_MULTILANG,   # 多语言字典 {locale: text} / locale-keyed dictionary
}

# Sentinel bounds: gpMin / gpMax default to ±INF so "no range" is expressed without a flag.
# 哨兵边界：gpMin / gpMax 默认 ±INF，无需额外标志即可表达「不限」。
const GP_UNBOUNDED_MIN: float = -INF
const GP_UNBOUNDED_MAX: float = INF

# ---- identity / 标识 ----
# Stable technical key, e.g. "rated_flow". Renaming goes through gpRenameFrom migration.
# 稳定的技术键，如 "rated_flow"；改名须经 gpRenameFrom 迁移。
@export var gpKey: String = ""

# I18n key for the display label, resolved by I18n.gpTr at UI time (never at model time).
# 显示名的 i18n 键，由 UI 层的 I18n.gpTr 解析（模型层绝不解析）。
@export var gpLabelKey: String = ""

# Fallback display label when gpLabelKey has no translation.
# 无对应译文时的回落显示名。
@export var gpLabel: String = ""

@export var gpKind: int = GPKind.GP_STRING

# Library-level default. Instances that never override this value follow it automatically.
# 库级默认值。从未覆盖该字段的实例自动跟随它。
@export var gpDefault: Variant = ""

# Panel grouping: 工艺 / 机械 / 仪表 / 电气 / 材料.
# 面板分组：工艺 / 机械 / 仪表 / 电气 / 材料。
@export var gpGroup: String = ""

@export var gpUnit: String = ""

@export var gpOptions: Array[String] = []

@export var gpMin: float = GP_UNBOUNDED_MIN
@export var gpMax: float = GP_UNBOUNDED_MAX

# Regex the value must match (STRING / TEXT / MULTILANG only).
# 取值必须匹配的正则（仅 STRING / TEXT / MULTILANG）。
@export var gpPattern: String = ""

@export var gpRequired: bool = false
@export var gpUnique: bool = false
@export var gpReadOnly: bool = false

# Sort weight inside a group (ascending).
# 组内的排序权重（升序）。
@export var gpOrder: int = 0

# Migration source: when a library rename happens, an instance value stored under this OLD key
# is moved to gpKey on load (see GPPropertyResolver.gpMigrateProps).
# 迁移来源：库中字段改名时，存于该「旧键」下的实例值会在加载时搬到 gpKey
# （见 GPPropertyResolver.gpMigrateProps）。
@export var gpRenameFrom: String = ""


# Whether a value counts as "not filled in" — the test gpRequired uses.
# 判断取值是否算「未填写」—— gpRequired 校验所用。
static func gpIsEmpty(gpValue: Variant) -> bool:
	if gpValue == null:
		return true
	if gpValue is String:
		return (gpValue as String).strip_edges() == ""
	if gpValue is Dictionary:
		return (gpValue as Dictionary).is_empty()
	if gpValue is Array:
		return (gpValue as Array).is_empty()
	return false


# Coerce a raw value (from JSON, from a LineEdit, from an import) into this field's kind.
# 把一个原始值（来自 JSON、输入框或导入）强制转换为本字段的类型。
# Unparseable input falls back to gpDefault rather than raising — a P&ID sheet must still open
# when one property was hand-edited in a text editor.
# 无法解析的输入回落到 gpDefault 而非抛错 —— 某个属性被手工改坏时，图纸仍须能打开。
func gpCoerce(gpValue: Variant) -> Variant:
	if gpValue == null:
		return gpDefault
	match gpKind:
		GPKind.GP_INT:
			return int(gpValue)
		GPKind.GP_FLOAT:
			return float(gpValue)
		GPKind.GP_BOOL:
			if gpValue is String:
				var gpS: String = (gpValue as String).strip_edges().to_lower()
				return gpS == "true" or gpS == "1" or gpS == "yes" or gpS == "on"
			return bool(gpValue)
		GPKind.GP_ENUM:
			var gpE: String = str(gpValue)
			if gpOptions.has(gpE):
				return gpE
			return gpDefault
		GPKind.GP_MULTILANG:
			return gpValue if gpValue is Dictionary else {}
		_:
			return str(gpValue)


# Whether a value satisfies required / range / enum / pattern. Non-blocking by design: the UI
# shows a yellow frame, and W10 validation produces the real report.
# 取值是否满足必填 / 范围 / 枚举 / 正则。按设计不阻断输入：UI 出黄框，真正的报告由 W10 校验给出。
func gpValidate(gpValue: Variant) -> bool:
	if gpRequired and gpIsEmpty(gpValue):
		return false
	if gpKind == GPKind.GP_ENUM and gpOptions.size() > 0:
		if not gpOptions.has(str(gpValue)):
			return false
	if gpKind == GPKind.GP_INT or gpKind == GPKind.GP_FLOAT:
		var gpN: float = float(gpValue)
		if gpN < gpMin or gpN > gpMax:
			return false
	if gpPattern != "" and gpKind != GPKind.GP_BOOL:
		var gpRe: RegEx = RegEx.new()
		# A bad pattern must NOT lock the user out of their own sheet — treat it as "no rule".
		# 坏正则绝不能把用户锁在自己的图纸外 —— 视为「无规则」。
		if gpRe.compile(gpPattern) == OK:
			if gpRe.search(str(gpValue)) == null:
				return false
	return true


# Serialize to a dictionary (JSON-friendly; gpDefault/gpOptions are assumed JSON scalars).
# 序列化为字典（JSON 友好；gpDefault / gpOptions 假定为 JSON 标量）。
func gpToDict() -> Dictionary:
	var gpD: Dictionary = {}
	gpD["key"] = gpKey
	gpD["label_key"] = gpLabelKey
	gpD["label"] = gpLabel
	gpD["kind"] = gpKind
	gpD["default"] = gpDefault
	gpD["group"] = gpGroup
	gpD["unit"] = gpUnit
	gpD["options"] = gpOptions.duplicate()
	gpD["min"] = gpMin
	gpD["max"] = gpMax
	gpD["pattern"] = gpPattern
	gpD["required"] = gpRequired
	gpD["unique"] = gpUnique
	gpD["read_only"] = gpReadOnly
	gpD["order"] = gpOrder
	gpD["rename_from"] = gpRenameFrom
	return gpD


# Restore in place (inverse of gpToDict). Every key is optional: a hand-written partial schema
# must still load.
# 就地还原（gpToDict 的逆操作）。所有键均可选：手写的残缺 schema 也须能载入。
func gpFromDict(gpD: Dictionary) -> void:
	gpKey = gpD.get("key", "")
	gpLabelKey = gpD.get("label_key", "")
	gpLabel = gpD.get("label", "")
	gpKind = int(gpD.get("kind", GPKind.GP_STRING))
	gpDefault = gpD.get("default", "")
	gpGroup = gpD.get("group", "")
	gpUnit = gpD.get("unit", "")
	var gpOps: Array = gpD.get("options", [])
	var gpOpsOut: Array[String] = []
	for gpO in gpOps:
		gpOpsOut.append(str(gpO))
	gpOptions = gpOpsOut
	gpMin = float(gpD.get("min", GP_UNBOUNDED_MIN))
	gpMax = float(gpD.get("max", GP_UNBOUNDED_MAX))
	gpPattern = gpD.get("pattern", "")
	gpRequired = bool(gpD.get("required", false))
	gpUnique = bool(gpD.get("unique", false))
	gpReadOnly = bool(gpD.get("read_only", false))
	gpOrder = int(gpD.get("order", 0))
	gpRenameFrom = gpD.get("rename_from", "")
