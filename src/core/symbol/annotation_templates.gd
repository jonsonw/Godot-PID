class_name GPSymbolAnnotationTemplates
extends RefCounted
# Copyright © 2026 Jonson Wang
# Programmatic definitions for ANNOTATION-class symbols (Rev.3 stage 2 §四).
# 注释类图元的程序化定义（Rev.3 阶段 2 §四）。
#
# These are NOT hand-drawn glyphs: an annotation is "one template row + one policy row", all
# seven stage-2 policy fields set to their non-default values, with the geometry produced by
# the generator registry (GENERATOR:multiline) instead of static shapes. Zero new classes per
# symbol — that is the whole point of the definition-layer policy fields.
# 它们不是手绘字形：一个注释 = 「一行模板 + 一行策略」，七个阶段 2 策略字段全部取非默认值，
# 几何由生成器注册表（GENERATOR:multiline）产出而非静态形状。零个逐符号新类 —— 这正是
# 定义层策略字段存在的全部意义。
#
# Policy rationale / 策略依据（每字段对准一个痛点）：
#   EXPLICIT size        — the author's block size is the truth; the category table must NOT
#                          overwrite it (the size exemption).
#                          作者的块尺寸即真相；类别表**不得**覆写它（尺寸豁免）。
#   avoid_routing=false  — pipes may legally run under a text block; neither the collision
#                          relaxation nor the router may shove it or route around it.
#                          管线可合法横穿文本块；碰撞松弛与布线器都不得推它、也不得绕它。
#   mountable=false      — dropping a text block on a vessel must NOT mount it (Rev.3 §8:
#                          "not pushed" != "not mounted", the two stay orthogonal).
#                          文本块落到设备上**不得**挂载（Rev.3 §8：「不推挤」≠「不挂载」，二者正交）。
#   taggable=false       — a text block mints no equipment tag and renumbering skips it.
#                          文本块不铸设备位号，重排编号时跳过。
#   pick_mode=FULL (default, key omitted) — user feedback 2026-10-17: clicking the TEXT itself
#                          must select the block; the BORDER-only band felt like "you have to
#                          click outside the text to select it". A text block over a pipe is a
#                          deliberate placement — the author wants the block, not the pipe.
#   pick_mode=FULL（默认值，键不写出）—— 用户实测反馈 2026-10-17：点击文字**本身**必须选中
#                          文本块；仅边框带可点的体感就是「要移到外面点才能选中」。文本块压在
#                          管线上是作者的刻意摆放 —— 要的是块，不是管线。
#
# Editing contract / 编辑契约：content lives in gpProps["text"] (declared in the def's own
# schema, kind GP_TEXT so the inspector renders a multi-line field); the in-place editor
# reuses the stage-1.5 GPNodeTextEditor channel with the commit target swapped by
# GPSymbolGeneratorRegistry.gpTextPropKey().
# 内容存于 gpProps["text"]（由定义自身 schema 声明，kind=GP_TEXT 使属性面板渲染多行字段）；
# 就地编辑复用阶段 1.5 的 GPNodeTextEditor 通道，提交目标由
# GPSymbolGeneratorRegistry.gpTextPropKey() 换向。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The multi-line text block's definition id (also its i18n domain below).
# 多行文本块的定义 id（同时也是下方 i18n 的命名域）。
const GP_TEXT_MULTILINE_ID: String = "TEXT:multiline"

# The equipment data table's definition id (stage 3, GENERATOR:grid).
# 设备参数表的定义 id（阶段 3，GENERATOR:grid）。
const GP_TABLE_DEVICE_PARAM_ID: String = "TABLE:device_param"


# The built-in annotation definitions, appended to the library after the DEXPI pack.
# 内置注释定义，追加在 DEXPI 包之后进入图元库。
static func gpDefs() -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	gpOut.append(_gpTextMultiline())
	gpOut.append(_gpTableDeviceParam())
	return gpOut


# TEXT:multiline — a multi-line text block.
# TEXT:multiline —— 多行文本块。
static func _gpTextMultiline() -> GPSymbolDef:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = GP_TEXT_MULTILINE_ID
	# i18n KEY, matching the pack convention (gpTr resolves it per locale).
	# i18n **键**，与图元包约定一致（gpTr 按语种解析）。
	gpDef.gpDisplayName = "sym.text_multiline"
	gpDef.gpCategory = "annotation"
	# Explicit authored envelope (mm): wide and short, like a note block. EXPLICIT keeps it.
	# ⚠️ A1 REBASE (iron rule 89): symbol data rides ×2 — the note block doubles with it
	# (80x40), and so does its text (see symbol_view.GP_ANNOTATE_FONT_SCALE; user feedback
	# 2026-10-17: annotation text was half size on the A1 sheet).
	# 显式包络（mm）：宽而扁，如同备注块。EXPLICIT 模式保留它。
	# ⚠️ A1 重定基（铁律 89）：图元数据搭 ×2 —— 备注块随之翻倍（80×40），文字亦然
	#（见 symbol_view.GP_ANNOTATE_FONT_SCALE；用户实测反馈 2026-10-17：A1 图面上注释文字只有一半大）。
	gpDef.gpDefaultSize = Vector2(80.0, 40.0)
	gpDef.gpSizeMode = GPSymbolDef.GP_SIZE_MODE_EXPLICIT
	gpDef.gpGeometrySource = GPSymbolDef.GP_GEOMETRY_GENERATOR_PREFIX + "multiline"
	# gpPickMode stays at its FULL default (user feedback: click the text = select the block);
	# per the non-default-write rule the key is simply never emitted.
	# gpPickMode 保持 FULL 默认（用户反馈：点文字即选中块）；按「非默认才写出」规则，键直接不写。
	gpDef.gpAvoidRouting = false
	gpDef.gpTaggable = false
	gpDef.gpMountable = false
	# No static shapes and no ports: the generator owns the geometry, and a text block
	# connects to nothing.
	# 无静态形状、无端口：几何归生成器所有，文本块不与任何东西连接。
	gpDef.gpShapes = []
	gpDef.gpPorts = []
	# Built-in per decision D3: read-only in the library; editing derives a C-rule copy.
	# 按决策 D3 标记内置：库内只读；编辑时派生 C 规则副本。
	gpDef.gpBuiltin = true
	# The content prop, declared so the inspector offers a multi-line text field for it.
	# 声明内容属性，使属性面板为其提供多行文本字段。
	var gpSchema: GPPropertySchema = GPPropertySchema.new()
	var gpField: GPPropertyDef = GPPropertyDef.new()
	gpField.gpFromDict({
		"key": "text",
		"label": "文本",
		"kind": 5,
		"group": "注释",
		"order": 10,
	})
	gpSchema.gpFields.append(gpField)
	gpDef.gpSchema = gpSchema
	return gpDef


# TABLE:device_param — the equipment data table (stage 3, GENERATOR:grid). Geometry comes
# from the grid generator (columns/rows from props CSVs over the reference defaults: the
# Plate HX drawing measured 90x26 mm at A3 scale, doubled to 180x52 by the A1 rebase —
# 120+30+30 cols x 8 rows of 6.5 mm). Cell TEXTS live in per-cell props ("cell_<r>_<c>")
# and are edited by double-clicking the cell, NOT here: the schema only declares the two
# geometry CSVs.
# TABLE:device_param —— 设备参数表（阶段 3，GENERATOR:grid）。几何由格网生成器产出
#（列/行来自 props CSV，回落参照默认：板换图 A3 尺度实测 90×26mm，经 A1 重定基翻倍为
# 180×52 —— 120+30+30 列 × 8 行 × 6.5mm）。单元格**文字**存于逐格属性（"cell_<r>_<c>"），
# 靠双击格子编辑，而非在此声明：schema 只声明两个几何 CSV 字段。
static func _gpTableDeviceParam() -> GPSymbolDef:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = GP_TABLE_DEVICE_PARAM_ID
	gpDef.gpDisplayName = "sym.table_device_param"
	gpDef.gpCategory = "annotation"
	# The reference table measured 90x26 mm at A3 scale; the A1 rebase (iron rule 89:
	# symbol data rides ×2) doubles the template — 180x52 — so the cell text doubles with
	# the row heights (user feedback 2026-10-17: "the table text is too small, double it").
	# 参照表实测 90×26mm 为 A3 尺度；A1 重定基（铁律 89：图元数据搭 ×2）把模板翻倍 ——
	# 180×52 —— 格字随行高一起翻倍（用户实测反馈 2026-10-17：「表格文字太小，扩大一倍」）。
	gpDef.gpDefaultSize = Vector2(180.0, 52.0)
	gpDef.gpSizeMode = GPSymbolDef.GP_SIZE_MODE_EXPLICIT
	gpDef.gpGeometrySource = GPSymbolDef.GP_GEOMETRY_GENERATOR_PREFIX + "grid"
	# FULL pick (stage-2 user feedback: click the thing = select the thing). A table is
	# placed deliberately; clicking a cell must grab the TABLE.
	# FULL 拾取（阶段 2 用户反馈：点什么选什么）。表格是刻意摆放的；点格子必须选中**表**。
	gpDef.gpAvoidRouting = false
	gpDef.gpTaggable = false
	gpDef.gpMountable = false
	gpDef.gpShapes = []
	gpDef.gpPorts = []
	gpDef.gpBuiltin = true
	# Schema: the two geometry CSVs only. Cell texts are per-instance props with dynamic
	# keys — a static schema cannot enumerate them (and must not: the grid can grow).
	# Schema：仅两个几何 CSV。单元格文字是动态键的实例属性 —— 静态 schema 无法枚举
	#（也不该枚举：格网可以增长）。
	var gpSchema: GPPropertySchema = GPPropertySchema.new()
	gpSchema.gpFields.append(_gpCsvField("col_widths", "列宽 (mm)", 10))
	gpSchema.gpFields.append(_gpCsvField("row_heights", "行高 (mm)", 20))
	gpDef.gpSchema = gpSchema
	return gpDef


# One CSV geometry field for the table schema. / 表格 schema 的一段 CSV 几何字段。
static func _gpCsvField(gpKey: String, gpLabel: String, gpOrder: int) -> GPPropertyDef:
	var gpField: GPPropertyDef = GPPropertyDef.new()
	gpField.gpFromDict({
		"key": gpKey,
		"label": gpLabel,
		"kind": 5,
		"group": "表格",
		"order": gpOrder,
	})
	return gpField
