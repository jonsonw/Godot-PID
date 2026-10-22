class_name GPDeliverableFields
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# The ONE field catalogue for the four Excel deliverable lists (line / equipment /
# instrument / valve). It answers: which columns exist, which are required, which are
# writable back from Excel, and how a template header text maps to a key.
# 四张 Excel 交付清单（管线 / 设备 / 仪表 / 阀门）的**唯一**字段目录。它回答：
# 有哪些列、哪些必填、哪些可从 Excel 回写、模板表头文字如何映射到 key。
#
# WHY A TABLE / 为何用表：
# the four lists share fields (tag / name / sheet) but differ in source and writability.
# If each model hard-codes its own columns, the template reader, the xlsx writer and the
# write-back validator will drift into three different column sets. One table makes them
# one fact. 四张表共享字段（位号/名称/图纸），但来源与可写性不同。若每个模型各写一套列，
# 模板读取、xlsx 写出、回写校验会漂成三套列。一张表让它们成为同一个事实。
#
# LAYERING / 分层：this class lives in `io` because the model reads `GPDexpiMapping`
# (also io). It does not touch FileAccess, I18n or any Node — it is headless-testable.
# 本类位于 `io`，因为模型要读 `GPDexpiMapping`（同在 io）。它不碰 FileAccess / I18n / Node，
# 可 headless 测试。
#
# Coding rule: every variable declares its type explicitly; every function is static (pure).
# 编码规范：所有变量显式声明类型；函数全部静态（纯函数）。

# List ids / 清单 id。
const GP_LIST_LINE: String = "line"
const GP_LIST_EQUIPMENT: String = "equipment"
const GP_LIST_INSTRUMENT: String = "instrument"
const GP_LIST_VALVE: String = "valve"

# Stable list order (menu / output order). Never derive it from Dictionary.keys().
# 稳定清单顺序（菜单 / 输出顺序）。绝不从 Dictionary.keys() 推导。
const GP_LIST_IDS: Array = ["line", "equipment", "instrument", "valve"]

# Per-list display names, used when I18n is unavailable (headless) and as fallback.
# 各清单显示名；I18n 不可用（headless）时使用，也作为回落。
const GP_LIST_LABELS: Dictionary = {
	"line": {"zh": "管线一览表", "en": "Line List"},
	"equipment": {"zh": "设备一览表", "en": "Equipment List"},
	"instrument": {"zh": "仪表索引表", "en": "Instrument Index"},
	"valve": {"zh": "阀门一览表", "en": "Valve List"},
}

# Column order per list. This is the contract the default templates follow.
# 各清单列顺序。默认模板遵循本表。
const GP_LIST_FIELDS: Dictionary = {
	"line": [
		"no", "sheet", "line_no", "line_kind", "from", "to",
		"from_equipment", "to_equipment", "dn", "spec", "medium", "insulation",
		"length_m", "valves", "valve_count", "segment_count",
	],
	"equipment": [
		"no", "sheet", "tag", "name", "type", "class", "category", "qty",
		"material", "design_pressure", "design_temp", "volume", "heat_area", "duty",
		"rated_flow", "rated_head", "motor_power", "nozzle_count", "remark",
	],
	"instrument": [
		"no", "sheet", "tag", "name", "type", "class", "loop_no",
		"measure_range", "signal_type", "accuracy", "power_supply",
		"connected_line", "connected_equipment", "remark",
	],
	"valve": [
		"no", "sheet", "tag", "name", "type", "class", "line_no",
		"nominal_size", "pressure_rating", "body_material", "actuator_type",
		"fail_action", "qty", "remark",
	],
}

# The field catalogue. Every row:
#   zh / en     : fallback header text (I18n key is "field." + key)
#   aliases     : header auto-detection aliases (normalised before compare)
#   source      : where the value comes from (see the model)
#   kind        : text | int | float:<decimals>
#   required    : must be present to bind the list
#   writable    : may be written back from Excel
#   default_col : part of the default template
# 字段目录。每行：zh/en 回落表头、aliases 自动识别别名、source 取值来源、kind 类型、
# required 绑定必需、writable 可回写、default_col 是否进默认模板。
const GP_FIELDS: Dictionary = {
	# ---- shared / 共用 ----
	"no": {"zh": "序号", "en": "No.", "aliases": ["No.", "No", "Item", "序号"], "source": "computed:no", "kind": "int", "required": false, "writable": false, "default_col": true},
	"sheet": {"zh": "图纸", "en": "Sheet", "aliases": ["Sheet", "Drawing", "图纸", "图号"], "source": "sheet.name", "kind": "text", "required": false, "writable": false, "default_col": true},
	"tag": {"zh": "位号", "en": "Tag", "aliases": ["Tag", "Tag No.", "Tag No", "设备位号", "设备编号", "仪表位号", "阀门位号", "位号", "编号"], "source": "node.tag", "kind": "text", "required": true, "writable": false, "default_col": true},
	"name": {"zh": "名称", "en": "Name", "aliases": ["Name", "Description", "设备名称", "仪表名称", "阀门名称", "名称", "描述"], "source": "node.name", "kind": "text", "required": false, "writable": true, "default_col": true},
	"type": {"zh": "类型", "en": "Type", "aliases": ["Type", "Equipment Type", "Instrument Type", "Valve Type", "设备类型", "仪表类型", "阀门类型", "类型"], "source": "def.display", "kind": "text", "required": false, "writable": false, "default_col": true},
	"class": {"zh": "标准类", "en": "Class", "aliases": ["Class", "DEXPI Class", "标准类"], "source": "dexpi.class", "kind": "text", "required": false, "writable": false, "default_col": true},
	"remark": {"zh": "备注", "en": "Remark", "aliases": ["Remark", "Remarks", "Notes", "备注", "说明"], "source": "prop:remark", "kind": "text", "required": false, "writable": true, "default_col": true},

	# ---- line / 管线 ----
	"line_no": {"zh": "管线号", "en": "Line No.", "aliases": ["Line No.", "Line No", "Line Number", "Line", "管道号", "管线号", "线号", "管线编号"], "source": "edge.tag", "kind": "text", "required": true, "writable": false, "default_col": true},
	"line_kind": {"zh": "管线类型", "en": "Line Type", "aliases": ["Line Type", "Service", "管线类型", "线型", "类型"], "source": "edge.kind", "kind": "text", "required": false, "writable": false, "default_col": true},
	"from": {"zh": "起点", "en": "From", "aliases": ["From", "Start", "From End", "起点", "起始"], "source": "computed:from", "kind": "text", "required": false, "writable": false, "default_col": true},
	"to": {"zh": "终点", "en": "To", "aliases": ["To", "End", "To End", "终点", "止点"], "source": "computed:to", "kind": "text", "required": false, "writable": false, "default_col": true},
	"from_equipment": {"zh": "起点设备", "en": "From Equipment", "aliases": ["From Equipment", "Start Equipment", "起点设备"], "source": "computed:from_equipment", "kind": "text", "required": false, "writable": false, "default_col": true},
	"to_equipment": {"zh": "终点设备", "en": "To Equipment", "aliases": ["To Equipment", "End Equipment", "终点设备"], "source": "computed:to_equipment", "kind": "text", "required": false, "writable": false, "default_col": true},
	"dn": {"zh": "公称直径", "en": "DN", "aliases": ["DN", "Size", "Nominal Diameter", "公称直径", "公称尺寸", "管径"], "source": "edge.attr:dn", "kind": "text", "required": false, "writable": true, "default_col": true},
	"spec": {"zh": "管道等级", "en": "Piping Class", "aliases": ["Piping Class", "Spec", "Pipe Class", "管道等级", "等级"], "source": "edge.attr:spec", "kind": "text", "required": false, "writable": true, "default_col": true},
	"medium": {"zh": "介质", "en": "Medium", "aliases": ["Medium", "Fluid", "介质", "流体"], "source": "edge.attr:medium", "kind": "text", "required": false, "writable": true, "default_col": true},
	"insulation": {"zh": "保温", "en": "Insulation", "aliases": ["Insulation", "Insulation Thickness", "保温", "保温等级", "保温厚度"], "source": "edge.attr:insulation", "kind": "text", "required": false, "writable": true, "default_col": true},
	"length_m": {"zh": "长度(m)", "en": "Length (m)", "aliases": ["Length", "Length (m)", "长度", "长度(m)"], "source": "computed:length_m", "kind": "float:2", "required": false, "writable": false, "default_col": true},
	"valves": {"zh": "阀门", "en": "Valves", "aliases": ["Valves", "Valve Tags", "Valve No.", "阀门", "阀门位号", "阀门编号"], "source": "computed:valves", "kind": "text", "required": false, "writable": false, "default_col": true},
	"valve_count": {"zh": "阀门数", "en": "Valve Count", "aliases": ["Valve Count", "Valve Qty", "阀门数", "阀门数量"], "source": "computed:valve_count", "kind": "int", "required": false, "writable": false, "default_col": false},
	"segment_count": {"zh": "管段数", "en": "Segments", "aliases": ["Segments", "Segment Count", "管段数", "管段数量"], "source": "computed:segment_count", "kind": "int", "required": false, "writable": false, "default_col": false},

	# ---- equipment / 设备 ----
	"category": {"zh": "类别", "en": "Category", "aliases": ["Category", "类别"], "source": "def.category", "kind": "text", "required": false, "writable": false, "default_col": false},
	"qty": {"zh": "数量", "en": "Qty", "aliases": ["Qty", "Quantity", "数量", "台数"], "source": "computed:qty", "kind": "int", "required": false, "writable": false, "default_col": true},
	"material": {"zh": "材质", "en": "Material", "aliases": ["Material", "Body Material", "材质", "主要材质"], "source": "prop:material", "kind": "text", "required": false, "writable": true, "default_col": true},
	"design_pressure": {"zh": "设计压力(MPa)", "en": "Design Pressure (MPa)", "aliases": ["Design Pressure", "Design Pressure (MPa)", "设计压力", "设计压力(MPa)"], "source": "prop:design_pressure", "kind": "float:2", "required": false, "writable": true, "default_col": true},
	"design_temp": {"zh": "设计温度(℃)", "en": "Design Temp (℃)", "aliases": ["Design Temperature", "Design Temp", "Design Temp (℃)", "设计温度", "设计温度(℃)"], "source": "prop:design_temp", "kind": "float:1", "required": false, "writable": true, "default_col": true},
	"volume": {"zh": "容积(m³)", "en": "Volume (m³)", "aliases": ["Volume", "Volume (m³)", "容积", "容积(m³)"], "source": "prop:volume", "kind": "float:2", "required": false, "writable": true, "default_col": true},
	"heat_area": {"zh": "换热面积(m²)", "en": "Heat Area (m²)", "aliases": ["Heat Area", "Heat Area (m²)", "换热面积", "换热面积(m²)"], "source": "prop:heat_area", "kind": "float:2", "required": false, "writable": true, "default_col": true},
	"duty": {"zh": "热负荷(kW)", "en": "Duty (kW)", "aliases": ["Duty", "Duty (kW)", "热负荷", "热负荷(kW)"], "source": "prop:duty", "kind": "float:2", "required": false, "writable": true, "default_col": true},
	"rated_flow": {"zh": "额定流量(m³/h)", "en": "Rated Flow (m³/h)", "aliases": ["Rated Flow", "Rated Flow (m³/h)", "额定流量", "额定流量(m³/h)"], "source": "prop:rated_flow", "kind": "float:2", "required": false, "writable": true, "default_col": true},
	"rated_head": {"zh": "额定扬程(m)", "en": "Rated Head (m)", "aliases": ["Rated Head", "Rated Head (m)", "额定扬程", "额定扬程(m)"], "source": "prop:rated_head", "kind": "float:2", "required": false, "writable": true, "default_col": true},
	"motor_power": {"zh": "电机功率(kW)", "en": "Motor Power (kW)", "aliases": ["Motor Power", "Motor Power (kW)", "电机功率", "电机功率(kW)"], "source": "prop:motor_power", "kind": "float:2", "required": false, "writable": true, "default_col": true},
	"nozzle_count": {"zh": "管口数", "en": "Nozzle Count", "aliases": ["Nozzle Count", "Nozzles", "管口数", "管口数量"], "source": "computed:nozzle_count", "kind": "int", "required": false, "writable": false, "default_col": true},

	# ---- instrument / 仪表 ----
	"loop_no": {"zh": "回路号", "en": "Loop No.", "aliases": ["Loop No.", "Loop No", "Loop", "回路号", "回路"], "source": "computed:loop_no", "kind": "text", "required": false, "writable": false, "default_col": true},
	"measure_range": {"zh": "量程", "en": "Range", "aliases": ["Range", "Measuring Range", "Measure Range", "量程", "测量范围"], "source": "prop:measure_range", "kind": "text", "required": false, "writable": true, "default_col": true},
	"signal_type": {"zh": "信号类型", "en": "Signal Type", "aliases": ["Signal Type", "Signal", "信号类型", "信号"], "source": "prop:signal_type", "kind": "text", "required": false, "writable": true, "default_col": true},
	"accuracy": {"zh": "精度", "en": "Accuracy", "aliases": ["Accuracy", "精度"], "source": "prop:accuracy", "kind": "text", "required": false, "writable": true, "default_col": true},
	"power_supply": {"zh": "供电", "en": "Power Supply", "aliases": ["Power Supply", "Power", "供电", "电源"], "source": "prop:power_supply", "kind": "text", "required": false, "writable": true, "default_col": true},
	"connected_line": {"zh": "连接管线", "en": "Connected Line", "aliases": ["Connected Line", "Line", "连接管线", "所属管线"], "source": "computed:connected_line", "kind": "text", "required": false, "writable": false, "default_col": true},
	"connected_equipment": {"zh": "连接设备", "en": "Connected Equipment", "aliases": ["Connected Equipment", "Equipment", "连接设备", "所属设备"], "source": "computed:connected_equipment", "kind": "text", "required": false, "writable": false, "default_col": true},

	# ---- valve / 阀门 ----
	"nominal_size": {"zh": "公称通径(mm)", "en": "Size (mm)", "aliases": ["Nominal Size", "Size", "Size (mm)", "DN", "公称通径", "公称通径(mm)", "口径"], "source": "prop:nominal_size", "kind": "float:0", "required": false, "writable": true, "default_col": true},
	"pressure_rating": {"zh": "压力等级", "en": "Pressure Rating", "aliases": ["Pressure Rating", "Rating", "PN", "Class", "压力等级"], "source": "prop:pressure_rating", "kind": "text", "required": false, "writable": true, "default_col": true},
	"body_material": {"zh": "阀体材质", "en": "Body Material", "aliases": ["Body Material", "Valve Material", "阀体材质", "材质"], "source": "prop:body_material", "kind": "text", "required": false, "writable": true, "default_col": true},
	"actuator_type": {"zh": "执行机构", "en": "Actuator", "aliases": ["Actuator", "Actuator Type", "执行机构", "驱动方式"], "source": "prop:actuator_type", "kind": "text", "required": false, "writable": true, "default_col": true},
	"fail_action": {"zh": "故障安全位", "en": "Fail Action", "aliases": ["Fail Action", "Failure Action", "FC/FO/FL", "故障安全位", "故障位"], "source": "prop:fail_action", "kind": "text", "required": false, "writable": true, "default_col": true},
}


# Characters dropped before header alias comparison.
# 表头别名比较前丢弃的字符。
const GP_HEADER_DROP: String = " \t\r\n-_./\\·（）()【】[]{}<>《》:：，,。、；;!！?？'\"“”‘’+＋&"


# All list ids, in stable order. / 全部清单 id，稳定顺序。
static func gpListIds() -> Array[String]:
	var gpOut: Array[String] = []
	for gpId in GP_LIST_IDS:
		gpOut.append(str(gpId))
	return gpOut


# Display name of one list, with zh/en fallback. / 单个清单显示名，中英回落。
static func gpListLabel(gpList: String, gpLocale: String = "zh") -> String:
	var gpRow: Variant = GP_LIST_LABELS.get(gpList)
	if not (gpRow is Dictionary):
		return gpList
	var gpMap: Dictionary = gpRow as Dictionary
	return str(gpMap.get(gpLocale, gpMap.get("zh", gpList)))


# Whether a list id is one of the four. / 是否为四类清单之一。
static func gpIsKnownList(gpList: String) -> bool:
	return GP_LIST_FIELDS.has(gpList)


# A defensive copy of one field definition ({} when unknown). / 字段定义副本（未知返回空）。
static func gpField(gpKey: String) -> Dictionary:
	var gpRow: Variant = GP_FIELDS.get(gpKey)
	if gpRow is Dictionary:
		return (gpRow as Dictionary).duplicate(true)
	return {}


# Canonical key order for one list. / 单个清单的字段顺序。
static func gpFieldsOf(gpList: String) -> Array[String]:
	var gpOut: Array[String] = []
	var gpRaw: Variant = GP_LIST_FIELDS.get(gpList)
	if not (gpRaw is Array):
		return gpOut
	for gpKey in (gpRaw as Array):
		gpOut.append(str(gpKey))
	return gpOut


# Columns that the default template for this list carries. / 默认模板列。
static func gpDefaultColumns(gpList: String) -> Array[String]:
	var gpOut: Array[String] = []
	for gpKey in gpFieldsOf(gpList):
		if bool(gpField(gpKey).get("default_col", false)):
			gpOut.append(gpKey)
	return gpOut


# Whether a key belongs to a list (used to reject a template column that maps to nothing).
# 某 key 是否属于该表（用于拒绝映射到不存在的模板列）。
static func gpHasField(gpList: String, gpKey: String) -> bool:
	return gpFieldsOf(gpList).has(gpKey)


# Value kind of a field ("text" when unknown, so a stray key never becomes a number).
# 字段类型（未知按 text，避免野键变数字）。
static func gpKind(gpKey: String) -> String:
	return str(gpField(gpKey).get("kind", "text"))


# Source expression of a field. / 字段取值来源。
static func gpSource(gpKey: String) -> String:
	return str(gpField(gpKey).get("source", ""))


# Whether Excel may write this field back. / 是否允许 Excel 回写。
static func gpIsWritable(gpKey: String) -> bool:
	return bool(gpField(gpKey).get("writable", false))


# Whether the list binding requires this field. / 绑定该表是否必须有此列。
static func gpIsRequired(gpKey: String) -> bool:
	return bool(gpField(gpKey).get("required", false))


# Header aliases, defensive copy. / 表头别名副本。
static func gpAliases(gpKey: String) -> Array[String]:
	var gpOut: Array[String] = []
	var gpRaw: Variant = gpField(gpKey).get("aliases", [])
	if gpRaw is Array:
		for gpAlias in (gpRaw as Array):
			gpOut.append(str(gpAlias))
	return gpOut


# I18n key for a field label. / 字段标签的 i18n 键。
static func gpLabelKey(gpKey: String) -> String:
	return "field." + gpKey


# Fallback label (zh/en) without I18n. / 无 I18n 时的回落标签。
static func gpLabel(gpKey: String, gpLocale: String = "zh") -> String:
	var gpRow: Dictionary = gpField(gpKey)
	return str(gpRow.get(gpLocale, gpRow.get("zh", gpKey)))


# Model locale strings (zh / en) -> the locale keys used by GPPropertyResolver.
# 模型语种（zh / en）-> GPPropertyResolver 使用的语种键。
static func gpLocaleCode(gpLocale: String) -> String:
	if gpLocale == "en":
		return "en_US"
	return "zh_CN"


# Normalise a template header for alias matching: drop whitespace and punctuation, lower-case.
# 归一化模板表头用于别名匹配：去空白与标点、转小写。
# Digits and CJK are kept, so "管线号 Line No." becomes "管线号lineno" while "P-1001" stays
# comparable as "p1001". 保留数字与汉字：故「管线号 Line No.」归一为「管线号lineno」，
# 「P-1001」归一为「p1001」，仍可比较。
static func gpNormalizeHeader(gpText: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpText.length()):
		var gpC: String = gpText.substr(gpI, 1)
		if GP_HEADER_DROP.find(gpC) >= 0:
			continue
		gpOut += gpC.to_lower()
	return gpOut


# Render one value as text for a fallback/CSV context. MULTILANG becomes its zh_CN text.
# 把一个值渲染为文本（回落/CSV 场景）。多语言取 zh_CN 文本。
static func gpValueText(gpValue: Variant) -> String:
	if gpValue == null:
		return ""
	if gpValue is Dictionary:
		return GPPropertyResolver.gpDisplayName(
			gpValue as Dictionary, "", GPPropertyResolver.GP_FALLBACK_LOCALE, "")
	if gpValue is bool:
		return "true" if bool(gpValue) else "false"
	return str(gpValue)


# Coerce a raw property value to the field's numeric type; null when absent/unparseable.
# 把原始属性值强制为字段数值类型；缺失/不可解析返回 null。
static func gpNumeric(gpKey: String, gpValue: Variant) -> Variant:
	if gpValue == null:
		return null
	var gpKindText: String = gpKind(gpKey)
	if gpKindText == "int":
		if (gpValue is int) or (gpValue is float):
			return int(gpValue)
		var gpI: String = str(gpValue).strip_edges()
		return int(gpI) if gpI.is_valid_int() else null
	if gpKindText.begins_with("float"):
		if (gpValue is int) or (gpValue is float):
			return float(gpValue)
		var gpF: String = str(gpValue).strip_edges()
		return float(gpF) if gpF.is_valid_float() else null
	return gpValue


# Coerce a raw property value to the field's text/typed value, using null for empty numerics.
# 把原始属性值转为字段的文本/数值；空数值返回 null，供 xlsx 写空单元格。
static func gpCoerce(gpKey: String, gpValue: Variant) -> Variant:
	var gpKindText: String = gpKind(gpKey)
	if gpKindText == "int" or gpKindText.begins_with("float"):
		return gpNumeric(gpKey, gpValue)
	if gpValue == null:
		return ""
	return gpValueText(gpValue)
