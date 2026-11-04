class_name GPSymbolGeneratorRegistry
extends RefCounted
# Copyright © 2026 Jonson Wang
# Geometry-source registry (Rev.3 stage 2, D3): "GENERATOR:<id>" -> a PURE function that
# produces the render inputs for one symbol instance.
# 几何来源注册表（Rev.3 阶段 2，决策 D3）：「GENERATOR:<id>」-> 为单个图元实例产出渲染输入的
# **纯函数**。
#
# WHY A REGISTRY, NOT AN if-CHAIN / 为何要注册表而非特判：
# Decision D3 (the palette architecture) forbids per-symbol special cases in renderers. A
# definition that declares gpGeometrySource = "GENERATOR:<id>" asks THE REGISTRY for its
# shapes; the renderer stays dumb: it draws whatever spec comes back, and draws NOTHING when
# the spec is empty (the explicit no-draw fallback). New generator kinds then never touch
# symbol_view again.
# 决策 D3（调色板架构）禁止渲染器里出现逐符号特判。声明 gpGeometrySource = "GENERATOR:<id>"
# 的定义向**注册表**索要形状；渲染器保持迟钝：返回什么规格就画什么，规格为空就什么都不画
#（显式不画的兜底）。此后新增生成器种类再也不必触碰 symbol_view。
#
# Output contract / 输出契约：
#   "spec"          : a GPSymbolPainter shape spec ({paths,circles,rects,box}) — {} = no vector art.
#   "text_lines"    : PackedStringArray of lines the view paints inside the envelope.
#   "text_above"    : optional line painted ABOVE the envelope (off-page legend layout).
#   "text_below"    : optional line painted BELOW the envelope (off-page legend layout).
#   "text_center_u" : optional text-column centre in UNIT space — text rides the glyph body,
#                     not the envelope centre (the adaptive off-page body).
#   "text_mm"       : optional ABSOLUTE text height (see the off-page / table generators).
# Generators are PURE: same (def, node) -> same output, no I/O, no caching.
# 生成器是纯函数：同一 (def, node) -> 同一输出，无 I/O、无缓存。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The gpGeometrySource prefix that routes a definition to this registry.
# gpGeometrySource 中把定义路由到本注册表的前缀。
const GP_PREFIX: String = "GENERATOR:"


# Whether a geometry-source string names a generator (vs the STATIC default).
# 某几何来源串是否指向生成器（区别于 STATIC 默认）。
static func gpIsGenerator(gpSource: String) -> bool:
	return gpSource.begins_with(GP_PREFIX)


# Extract the generator id from a geometry-source string ("" when not a generator).
# 从几何来源串提取生成器 id（非生成器时返回 ""）。
static func gpGeneratorId(gpSource: String) -> String:
	if not gpIsGenerator(gpSource):
		return ""
	return gpSource.trim_prefix(GP_PREFIX)


# The gpProps key a generator reads its TEXT content from ("" = the generator takes no text
# prop; content-bearing generators declare one so the in-place editor and the inspector can
# target the same key without special-casing ids).
# 生成器读取**文字内容**的 gpProps 键（"" = 该生成器不消费文字属性）。带内容的生成器声明
# 一个键，使就地编辑器与属性面板瞄准同一个键，而无需按 id 特判。
static func gpTextPropKey(gpDef: GPSymbolDef) -> String:
	if gpDef == null:
		return ""
	match gpGeneratorId(gpDef.gpGeometrySource):
		"multiline":
			return "text"
	return ""


# Generate the render inputs for one instance. Unknown generator ids degrade to the empty
# result — the renderer's explicit no-draw fallback, never a crash.
# 为单个实例生成渲染输入。未知生成器 id 退化为空结果 —— 即渲染器的「显式不画」兜底，绝不崩溃。
static func gpGenerate(gpDef: GPSymbolDef, gpNode: GPPIDNode) -> Dictionary:
	var gpEmpty: Dictionary = {"spec": {}, "text_lines": PackedStringArray()}
	if gpDef == null or gpNode == null:
		return gpEmpty
	match gpGeneratorId(gpDef.gpGeometrySource):
		"multiline":
			return _gpGenerateMultiline(gpNode)
		"grid":
			return _gpGenerateGrid(gpDef, gpNode)
		"offpage":
			return _gpGenerateOffpage(gpDef, gpNode)
	return gpEmpty


# ---------------------------------------------------------------- grid (stage 3)
# ---------------------------------------------------------------- 格网（阶段 3）
#
# GENERATOR:grid — a TABLE (the equipment data table). The geometry is a variable grid:
# column widths + row heights come from gpProps CSVs, cell texts from per-cell props, and
# the output is BOTH the vector art (ENVELOPE-MM polylines whose box IS the envelope, derived
# from the same cell rects, so the painter's uniform fit is identity and the drawn grid cannot
# diverge from the cells) AND the cell list — the ONE structure the renderer, the hit test and
# the in-place editor all consume (Rev.2 iron rule: rendering and hit testing must call the
# SAME generator, or the lines you see and the cells you can click drift apart).
# GENERATOR:grid —— 表格（设备参数表）。几何是**可变格网**：列宽/行高来自 gpProps CSV，
# 单元格文字来自逐格属性；输出既有矢量图形（**包络毫米**折线，box 即包络，且由同一份格子
# 矩形派生，故 painter 的均匀适配是恒等变换、画的格线不可能与格子分家），也有格子列表 ——
# 渲染、命中、就地编辑三方消费的**同一份**结构（Rev.2 铁律：渲染与命中必须调同一个生成器，
# 否则「看起来的格线」与「点得到的格子」分家）。

# Template-default grid geometry: the REFERENCE drawing measured 90x26 mm (60+15+15 cols,
# 8 rows of 3.25) at A3 scale; the A1 rebase (iron rule 89: symbol data rides ×2) doubles
# the whole table — 180x52 mm, 120+30+30 cols, 8 rows of 6.5 — so cell text doubles with
# it (user feedback 2026-10-17: "the table text is too small, double it"). The CSVs in
# gpProps OVERRIDE these; an absent CSV falls back so a fresh instance still draws the
# reference grid at the rebased scale.
# 模板默认格网几何：参照图实测 90×26mm（60+15+15 列、8 行 ×3.25）为 A3 尺度；A1 重定基
#（铁律 89：图元数据搭 ×2）把整表翻倍 —— 180×52mm、120+30+30 列、8 行 ×6.5 —— 格字随之
# 翻倍（用户实测反馈 2026-10-17：「表格文字太小，扩大一倍」）。gpProps 里的 CSV **覆盖**
# 这些默认；CSV 缺失时回落，使刚放置的实例仍按重定基后的尺度画出参照格网。
const GP_DEFAULT_COLS: String = "120,30,30"
const GP_DEFAULT_ROWS: String = "6.5,6.5,6.5,6.5,6.5,6.5,6.5,6.5"

# Structure guards: deleting down to nothing is refused, growing without bound is capped.
# 结构守卫：删空拒绝，无限增长设上限。
const GP_MIN_ROWS: int = 1
const GP_MIN_COLS: int = 1
const GP_MAX_ROWS: int = 50
const GP_MAX_COLS: int = 10

# The props prefix of a cell text key ("cell_<r>_<c>"). / 单元格文字键的前缀。
const GP_CELL_PREFIX: String = "cell_"

# Table row/col operations (gpMutatedProps). / 表格行列操作（gpMutatedProps）。
const GP_OP_INSERT_ROW: String = "insert_row"
const GP_OP_DELETE_ROW: String = "delete_row"
const GP_OP_INSERT_COL: String = "insert_col"
const GP_OP_DELETE_COL: String = "delete_col"

# Column-width drag (stage 3 S4). The smallest CSV width one column may keep after a
# boundary drag — the guard that makes "drag the boundary all the way left" squeeze a
# column to a visible sliver instead of letting it vanish.
# 列宽拖拽（阶段 3 S4）。一次边界拖拽后单列允许保留的最小 CSV 宽度 —— 有了这道守卫，
# 「把边界一路拖到头」只会把一列挤成可见的窄条，而不会让它消失。
const GP_MIN_COL_MM: float = 5.0


# The cell text key for grid position (r, c), 0-based. Pure naming — both the generator and
# the mutation transform derive keys through this, so they can never disagree on spelling.
# 格网位置 (r, c)（0 起）的单元格文字键。纯命名 —— 生成器与结构变换都经它取键，
# 两边对键名写法永不分歧。
static func gpCellKey(gpRow: int, gpCol: int) -> String:
	return GP_CELL_PREFIX + str(gpRow) + "_" + str(gpCol)


# Parse a CSV of positive floats ("60,15,15"); malformed entries degrade to the fallback so
# a hand-edited prop can never produce a degenerate zero-width column.
# 解析正浮点 CSV（"60,15,15"）；畸形项回落默认值，使手改的属性永远造不出零宽列。
static func _gpParseCsvMm(gpRaw: String, gpFallback: PackedFloat64Array) -> PackedFloat64Array:
	var gpOut: PackedFloat64Array = PackedFloat64Array()
	if gpRaw.strip_edges() != "":
		for gpPart in gpRaw.split(","):
			var gpV: float = gpPart.strip_edges().to_float()
			if gpV > 0.0:
				gpOut.append(gpV)
	if gpOut.size() == 0:
		return PackedFloat64Array(gpFallback)
	return gpOut


# The resolved grid: column widths / row heights in mm (props CSVs over the defaults).
# 解析后的格网：列宽 / 行高（mm）（props CSV 优先于默认值）。
static func _gpGridDims(gpNode: GPPIDNode) -> Dictionary:
	var gpDefCols: PackedFloat64Array = PackedFloat64Array()
	for gpV in GP_DEFAULT_COLS.split(","):
		gpDefCols.append(gpV.to_float())
	var gpDefRows: PackedFloat64Array = PackedFloat64Array()
	for gpV in GP_DEFAULT_ROWS.split(","):
		gpDefRows.append(gpV.to_float())
	return {
		"cols": _gpParseCsvMm(str(gpNode.gpProps.get("col_widths", "")), gpDefCols),
		"rows": _gpParseCsvMm(str(gpNode.gpProps.get("row_heights", "")), gpDefRows),
	}


# The cell list for one instance: EVERY grid position (empty cells included — a fresh
# table must still be clickable), each as {"key": String, "rect": Rect2} with the rect in
# NODE-LOCAL mm (origin = node centre, matching how the body frame is drawn). The grid
# stretches to fill the definition's EXPLICIT envelope regardless of the CSV sums.
# 单实例的格子列表：**全部**格位（含空格 —— 刚放置的表也必须可点），每项
# {"key": String, "rect": Rect2}，rect 为**节点本地 mm**（原点 = 节点中心，与 body 绘制
# 坐标系一致）。无论 CSV 总和如何，格网拉伸填满定义的 EXPLICIT 包络。
static func gpGridCellsOf(gpDef: GPSymbolDef, gpNode: GPPIDNode) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpDef == null or gpNode == null:
		return gpOut
	var gpDims: Dictionary = _gpGridDims(gpNode)
	var gpCols: PackedFloat64Array = gpDims["cols"]
	var gpRows: PackedFloat64Array = gpDims["rows"]
	var gpEnv: Vector2 = gpDef.gpDefaultSize
	var gpW: float = 0.0
	for gpV in gpCols:
		gpW += gpV
	var gpH: float = 0.0
	for gpV in gpRows:
		gpH += gpV
	if gpW <= 0.0 or gpH <= 0.0:
		return gpOut
	var gpTl: Vector2 = -gpEnv * 0.5
	var gpCumY: float = 0.0
	for gpR in range(gpRows.size()):
		var gpCumX: float = 0.0
		for gpC in range(gpCols.size()):
			var gpRect: Rect2 = Rect2(
				gpTl + Vector2(gpCumX / gpW * gpEnv.x, gpCumY / gpH * gpEnv.y),
				Vector2(gpCols[gpC] / gpW * gpEnv.x, gpRows[gpR] / gpH * gpEnv.y))
			gpOut.append({"key": gpCellKey(gpR, gpC), "rect": gpRect})
			gpCumX += gpCols[gpC]
		gpCumY += gpRows[gpR]
	return gpOut


# Which cell (by key) contains a node-local mm point? "" when outside the grid. The hit
# test and the double-click dispatch both route through here — the same cells list the
# renderer paints from.
# 节点本地 mm 点落在哪个格子（按键名）？格外返回 ""。命中测试与双击分派都走这里
# —— 与渲染所用的同一份格子列表。
static func gpCellAt(gpDef: GPSymbolDef, gpNode: GPPIDNode, gpLocal: Vector2) -> String:
	for gpCell in gpGridCellsOf(gpDef, gpNode):
		if (gpCell["rect"] as Rect2).has_point(gpLocal):
			return gpCell["key"]
	return ""


# The grid GENERATOR output: spec (ENVELOPE-MM border + separators) + cells + empty lines.
# The spec is derived from the SAME cell rects the hit test and the editor consume, so the
# lines you see and the cells you click cannot diverge — not at the default 180x52, and not
# after a row/col insert changes the total width or height.
# grid 生成器输出：spec（**包络毫米**外框 + 分隔线）+ cells + 空文字行。spec 由命中测试与
# 编辑器消费的**同一份**格子矩形推导，故「看到的线」与「点得到的格子」不可能分家 ——
# 默认 180×52 如此，增删行列改变总宽/总高后也如此。
static func _gpGenerateGrid(gpDef: GPSymbolDef, gpNode: GPPIDNode) -> Dictionary:
	var gpCells: Array[Dictionary] = gpGridCellsOf(gpDef, gpNode)
	if gpCells.is_empty():
		return {"spec": {}, "text_lines": PackedStringArray()}
	var gpDims: Dictionary = _gpGridDims(gpNode)
	var gpCols: PackedFloat64Array = gpDims["cols"]
	var gpRows: PackedFloat64Array = gpDims["rows"]
	var gpEnv: Vector2 = gpDef.gpDefaultSize
	# Cells are node-local mm with the origin at the ENVELOPE CENTRE; the painter wants a
	# box whose paths start at 0, so add half the envelope back. Every boundary comes from
	# the cells themselves — this is the single-source guarantee that the old duplicate
	# normalisation (cumX/W in unit space vs cumX/W*env.x in cells) did not have.
	# 格子是节点本地毫米、原点在**包络中心**；painter 需要从 0 起的 box，故加回半个包络。
	# 每条边界都取自格子本身 —— 这正是旧的重复归一化（单位空间 cumX/W 与格子 cumX/W*env.x）
	# 所没有的单一来源保证。
	var gpXs: PackedFloat64Array = PackedFloat64Array([0.0])
	for gpC in range(gpCols.size()):
		var gpCellX: Dictionary = gpCells[gpC]
		gpXs.append((gpCellX["rect"] as Rect2).end.x + gpEnv.x * 0.5)
	var gpYs: PackedFloat64Array = PackedFloat64Array([0.0])
	for gpR in range(gpRows.size()):
		var gpCellY: Dictionary = gpCells[gpR * gpCols.size()]
		gpYs.append((gpCellY["rect"] as Rect2).end.y + gpEnv.y * 0.5)
	var gpPaths: Array = []
	# Outer border as ONE closed polyline. / 外框 = 一条闭合折线。
	gpPaths.append({"pts": [[0.0, 0.0], [gpEnv.x, 0.0], [gpEnv.x, gpEnv.y], [0.0, gpEnv.y],
		[0.0, 0.0]]})
	# Internal horizontal separators (between rows, endpoints excluded). / 行间内分隔线（不含端点）。
	for gpI in range(1, gpYs.size() - 1):
		gpPaths.append({"pts": [[0.0, gpYs[gpI]], [gpEnv.x, gpYs[gpI]]]})
	# Internal vertical separators (between cols). / 列间内分隔线。
	for gpI in range(1, gpXs.size() - 1):
		gpPaths.append({"pts": [[gpXs[gpI], 0.0], [gpXs[gpI], gpEnv.y]]})
	return {
		"spec": {"paths": gpPaths, "box": [0.0, 0.0, gpEnv.x, gpEnv.y]},
		"text_lines": PackedStringArray(),
		"cells": gpCells,
	}


# PURE row/col structure transform: given the current props and an operation on grid
# position (row, col), return {"ok": bool, "props": Dictionary} where "props" is the NEW
# full props map (CSVs re-serialised, cell keys renumbered). Refusals: deleting the last
# row/col, growing past the caps, unknown op. The COMMAND consumes this — the pure logic
# stays testable headless.
# **纯**行列结构变换：给定当前 props 与对格位 (row, col) 的操作，返回
# {"ok": bool, "props": Dictionary}，"props" 为**新的完整** props 映射（CSV 重新序列化、
# 格键重排）。拒绝情形：删最后一行/列、超出上限、未知操作。命令消费此输出 —— 纯逻辑
# 保持可 headless 测试。
static func gpMutatedProps(gpProps: Dictionary, gpOp: String, gpRow: int, gpCol: int) -> Dictionary:
	var gpDims: Dictionary = _gpGridDimsFromProps(gpProps)
	var gpCols: PackedFloat64Array = gpDims["cols"]
	var gpRows: PackedFloat64Array = gpDims["rows"]
	match gpOp:
		GP_OP_INSERT_ROW:
			if gpRows.size() >= GP_MAX_ROWS:
				return {"ok": false, "props": {}}
			gpRows.insert(clampi(gpRow, 0, gpRows.size()), gpRows[mini(maxi(gpRow, 0), gpRows.size() - 1)])
		GP_OP_DELETE_ROW:
			if gpRows.size() <= GP_MIN_ROWS or gpRow < 0 or gpRow >= gpRows.size():
				return {"ok": false, "props": {}}
			gpRows.remove_at(gpRow)
		GP_OP_INSERT_COL:
			if gpCols.size() >= GP_MAX_COLS:
				return {"ok": false, "props": {}}
			gpCols.insert(clampi(gpCol, 0, gpCols.size()), gpCols[mini(maxi(gpCol, 0), gpCols.size() - 1)])
		GP_OP_DELETE_COL:
			if gpCols.size() <= GP_MIN_COLS or gpCol < 0 or gpCol >= gpCols.size():
				return {"ok": false, "props": {}}
			gpCols.remove_at(gpCol)
		_:
			return {"ok": false, "props": {}}
	# Rebuild the props: strip every old cell key + the two CSVs, then write the new ones.
	# 重建 props：剥掉全部旧格键与两个 CSV，再写入新的。
	var gpOut: Dictionary = {}
	for gpK in gpProps:
		if gpK.begins_with(GP_CELL_PREFIX) or gpK == "col_widths" or gpK == "row_heights":
			continue
		gpOut[gpK] = gpProps[gpK]
	var gpColCsv: PackedStringArray = PackedStringArray()
	for gpV in gpCols:
		gpColCsv.append(_gpMmStr(gpV))
	var gpRowCsv: PackedStringArray = PackedStringArray()
	for gpV in gpRows:
		gpRowCsv.append(_gpMmStr(gpV))
	gpOut["col_widths"] = ",".join(gpColCsv)
	gpOut["row_heights"] = ",".join(gpRowCsv)
	for gpR in range(gpRows.size()):
		for gpC in range(gpCols.size()):
			# Cell text follows the operation: a row/col INSERT copies the text of the cell
			# it duplicates (an empty template row), a DELETE shifts everything after it up.
			# 单元格文字跟随操作：插入行/列复制被复制格的文字（空模板行），删除行/列把其后
			# 全部上移。
			var gpSrcR: int = gpR
			var gpSrcC: int = gpC
			# The INSERTED row/col itself stays EMPTY (a clean blank row); text shifts only
			# for indexes strictly past the clicked one. Missing the == case here would copy
			# the clicked row's text into the new blank row (caught by the stage-3 suite).
			# 被**插入**的行/列本身保持为空（干净的空白行）；文字只对严格大于被点下标的
			# 位移。漏掉 == 分支会把被点行的文字复制进新空行（阶段 3 套件抓到过）。
			var gpSkip: bool = (gpOp == GPSymbolGeneratorRegistry.GP_OP_INSERT_ROW
				and gpR == gpRow) or (gpOp == GPSymbolGeneratorRegistry.GP_OP_INSERT_COL
				and gpC == gpCol)
			if gpSkip:
				continue
			match gpOp:
				GP_OP_INSERT_ROW:
					if gpR > gpRow:
						gpSrcR = gpR - 1
				GP_OP_DELETE_ROW:
					gpSrcR = gpR if gpR < gpRow else gpR + 1
				GP_OP_INSERT_COL:
					if gpC > gpCol:
						gpSrcC = gpC - 1
				GP_OP_DELETE_COL:
					gpSrcC = gpC if gpC < gpCol else gpC + 1
			var gpKey: String = gpCellKey(gpSrcR, gpSrcC)
			if gpProps.has(gpKey):
				gpOut[gpCellKey(gpR, gpC)] = gpProps[gpKey]
	return {"ok": true, "props": gpOut}


# ---------------------------------------------------------------- column-width drag (S4)
# ---------------------------------------------------------------- 列宽拖拽（S4）
#
# THREE pure probes the grip layer consumes — the drag never re-derives a rectangle:
#   * gpColSeparatorAt — WHICH internal vertical boundary sits under a node-local mm point;
#   * gpGridWidthScale — HOW a world-mm delta maps onto the CSV-mm axis;
#   * gpColWidthShift  — the before→after props transform for one boundary move.
# 抓取层消费的三个**纯**探测 —— 拖拽绝不重算矩形：
#   * gpColSeparatorAt —— 节点本地 mm 点下是**哪条**内部竖向边界；
#   * gpGridWidthScale —— 世界 mm 位移**如何**映射到 CSV mm 轴上；
#   * gpColWidthShift  —— 一次边界移动的 before→after props 变换。


# Which internal VERTICAL boundary (between column i-1 and column i, i in 1..cols-1) lies
# within gpTolMm of a node-local mm point? -1 when none. The x of boundary i is derived
# from the SAME proportional layout the cells use (cumulative CSV share of the envelope
# width, origin = envelope top-left), so the grabbable lines are exactly the drawn
# separators — never a second geometry that can drift.
# 节点本地 mm 点的 gpTolMm 容差内是**哪条**内部竖向边界（列 i-1 与列 i 之间，i ∈
# 1..cols-1）？无则 -1。边界 i 的 x 从**与格子同一套**比例布局推导（CSV 累计份额 × 包络宽，
# 原点 = 包络左上），故可抓的线就是画出来的分隔线 —— 绝不存在会分家的第二份几何。
static func gpColSeparatorAt(gpDef: GPSymbolDef, gpNode: GPPIDNode, gpLocal: Vector2,
		gpTolMm: float) -> int:
	if gpDef == null or gpNode == null or gpTolMm <= 0.0:
		return -1
	var gpDims: Dictionary = _gpGridDims(gpNode)
	var gpCols: PackedFloat64Array = gpDims["cols"]
	if gpCols.size() < 2:
		return -1
	var gpEnv: Vector2 = gpDef.gpDefaultSize
	var gpW: float = 0.0
	for gpV in gpCols:
		gpW += gpV
	if gpW <= 0.0 or gpEnv.x <= 0.0:
		return -1
	# The point must also sit within the table's vertical span (a separator is a line of
	# FINITE height, not an infinite x-wall).
	# 点还须落在表格的纵向跨度内（分隔线是一条**有限高**的线，不是无限的 x 墙）。
	if gpLocal.y < -gpEnv.y * 0.5 - gpTolMm or gpLocal.y > gpEnv.y * 0.5 + gpTolMm:
		return -1
	var gpTlX: float = -gpEnv.x * 0.5
	var gpCum: float = 0.0
	for gpI in range(1, gpCols.size()):
		gpCum += gpCols[gpI - 1]
		var gpSepX: float = gpTlX + gpCum / gpW * gpEnv.x
		if absf(gpLocal.x - gpSepX) <= gpTolMm:
			return gpI
	return -1


# The world-mm -> CSV-mm scale for a column drag: the CSV sum spans the envelope width, so
# one world mm equals (sum / envelope width) CSV mm. 0.0 when unusable (no def/node, empty
# widths, degenerate envelope) — the caller refuses to arm on 0.0.
# 列宽拖拽的世界 mm -> CSV mm 比例：CSV 总和撑满包络宽，故一个世界 mm 等于
#（总和 / 包络宽）个 CSV mm。不可用时为 0.0（无 def/节点、空宽度、退化包络）——
# 调用方对 0.0 拒绝上膛。
static func gpGridWidthScale(gpDef: GPSymbolDef, gpNode: GPPIDNode) -> float:
	if gpDef == null or gpNode == null or gpDef.gpDefaultSize.x <= 0.0:
		return 0.0
	var gpCols: PackedFloat64Array = (_gpGridDims(gpNode)["cols"] as PackedFloat64Array)
	var gpW: float = 0.0
	for gpV in gpCols:
		gpW += gpV
	if gpW <= 0.0:
		return 0.0
	return gpW / gpDef.gpDefaultSize.x


# PURE boundary-move transform: the boundary between column gpSepIndex-1 and gpSepIndex
# shifts by gpDeltaMm CSV-mm — column gpSepIndex-1 TAKES the delta, column gpSepIndex GIVES
# it, so the pair's total (and therefore the whole table's width share) is invariant. Both
# sides clamp to GP_MIN_COL_MM against the PAIR total (clamping each against its own old
# width would break the invariant); a pair total below 2x the floor is refused as
# degenerate. Returns {"ok", "props"} like gpMutatedProps — every other key passes through
# untouched, and only "col_widths" is rewritten.
# **纯**边界移动变换：列 gpSepIndex-1 与 gpSepIndex 之间的边界移动 gpDeltaMm（CSV mm）——
# 列 gpSepIndex-1 **拿走**位移、列 gpSepIndex **让出**位移，故这两列的总和（乃至整表在
# 包络中的宽度份额）不变。两侧都以**两列总和**为基准钳到 GP_MIN_COL_MM（各自对旧宽钳制会
# 破坏不变量）；两列总和低于下限两倍时按退化拒绝。返回 {"ok", "props"}，与 gpMutatedProps
# 同形 —— 其余键原样通过，仅重写 "col_widths"。
static func gpColWidthShift(gpProps: Dictionary, gpSepIndex: int, gpDeltaMm: float) -> Dictionary:
	var gpCols: PackedFloat64Array = (_gpGridDimsFromProps(gpProps)["cols"] as PackedFloat64Array)
	if gpSepIndex < 1 or gpSepIndex >= gpCols.size():
		return {"ok": false, "props": {}}
	var gpTotal: float = gpCols[gpSepIndex - 1] + gpCols[gpSepIndex]
	if gpTotal < GP_MIN_COL_MM * 2.0:
		return {"ok": false, "props": {}}
	var gpA: float = clampf(gpCols[gpSepIndex - 1] + gpDeltaMm, GP_MIN_COL_MM,
		gpTotal - GP_MIN_COL_MM)
	var gpB: float = gpTotal - gpA
	gpCols[gpSepIndex - 1] = gpA
	gpCols[gpSepIndex] = gpB
	var gpOut: Dictionary = {}
	for gpK in gpProps:
		if gpK == "col_widths":
			continue
		gpOut[gpK] = gpProps[gpK]
	var gpCsv: PackedStringArray = PackedStringArray()
	for gpV in gpCols:
		gpCsv.append(_gpMmStr(gpV))
	gpOut["col_widths"] = ",".join(gpCsv)
	return {"ok": true, "props": gpOut}


# Grid dims straight from a RAW props map (the pure-transform input shape — no node needed).
# 直接从**原始** props 映射解出的格网（纯变换的输入形态 —— 无需节点）。
static func _gpGridDimsFromProps(gpProps: Dictionary) -> Dictionary:
	var gpDefCols: PackedFloat64Array = PackedFloat64Array()
	for gpV in GP_DEFAULT_COLS.split(","):
		gpDefCols.append(gpV.to_float())
	var gpDefRows: PackedFloat64Array = PackedFloat64Array()
	for gpV in GP_DEFAULT_ROWS.split(","):
		gpDefRows.append(gpV.to_float())
	return {
		"cols": _gpParseCsvMm(str(gpProps.get("col_widths", "")), gpDefCols),
		"rows": _gpParseCsvMm(str(gpProps.get("row_heights", "")), gpDefRows),
	}


# Millimetre value -> compact CSV token (integer when whole: "60" not "60.0").
# 毫米值 -> 紧凑 CSV 片段（整数值写整数："60" 而非 "60.0"）。
static func _gpMmStr(gpV: float) -> String:
	if absf(gpV - roundf(gpV)) < 0.005:
		return str(int(roundf(gpV)))
	return str(snappedf(gpV, 0.01))


# GENERATOR:multiline — a multi-line TEXT block. Pure text: no vector art ({} spec, so the
# renderer's no-draw fallback applies), and the lines come from the node's "text" prop split
# on newlines. An empty/unset prop yields zero lines -> nothing painted at all, which is the
# intended look of a freshly placed, not-yet-filled text block.
# GENERATOR:multiline —— 多行文本块。纯文字：无矢量图形（{} 规格，走渲染器的「显式不画」
# 兜底），文字行取自节点 "text" 属性按换行拆分。属性为空/未设置时得到零行 -> 完全不画，
# 这正是刚放置、尚未填写的文本块应有的样子。
static func _gpGenerateMultiline(gpNode: GPPIDNode) -> Dictionary:
	var gpRaw: String = str(gpNode.gpProps.get("text", ""))
	# An empty/unset prop yields ZERO lines (not one empty line) — the "freshly placed,
	# nothing typed yet" state paints nothing at all.
	# 属性为空/未设置时得到**零行**（而非一行空串）—— 「刚放置、尚未输入」状态完全不画。
	if gpRaw == "":
		return {"spec": {}, "text_lines": PackedStringArray()}
	return {"spec": {}, "text_lines": gpRaw.split("\n") as PackedStringArray}


# ---------------------------------------------------------------- off-page connector (W12-S2)
# ---------------------------------------------------------------- 跨图纸连接符（W12-S2）
#
# GENERATOR:offpage — the Off-Page connector flag (ADR-43 D3). Two jobs, and they are the reason
# this is a generator rather than a static glyph:
#   1. the SILHOUETTE, chosen from the definition's PORT PURPOSE (NOZZLE -> one-way pennant,
#      SIGNAL -> both-ends-pointed hexagon). Data-driven on purpose: decision D3 forbids id lists
#      in renderers, so the pack's port type is the ONLY switch;
#   2. the TEXT, which is the peer drawing number DERIVED through GPOffPageIndex — never a stored
#      property (that is the whole point of D3: anchors are stored, the RELATION is derived).
# GENERATOR:offpage —— 跨图纸连接符旗标（ADR-43 D3）。两件事，也正是它必须是生成器而不是静态
# 字形的原因：
#   1. **轮廓**，由定义的**端口用途**选出（NOZZLE → 单向旗标，SIGNAL → 两端尖的六边形）。
#      刻意数据驱动：决策 D3 禁止渲染器出现 id 名单，故图元包的端口类型是**唯一**开关；
#   2. **文字**，即经 GPOffPageIndex **推导**出的对端图纸号 —— 绝不是存储属性（这正是 D3 的全部
#      意义：锚点存储，**关系**推导）。
#
# The text height is declared by this generator ("text_mm") because it is bounded by the small
# flag, not by the user's tag preference — see GPTextRole.GP_OFFPAGE_REF_MM.
# 字高由本生成器声明（"text_mm"），因为它由小旗标的尺寸定界，而非由用户的位号偏好 —— 见
# GPTextRole.GP_OFFPAGE_REF_MM。

# Fraction of the BODY width where the pennant's point starts (the flat body ends here). The
# body — not the envelope — is what the flag draws (see _gpOffpageBodyWidth).
# 旗标尖部起始处占**主体**宽度的比例（平直段到此为止）。主体 —— 而非包络 —— 才是旗标画出的
# 范围（见 _gpOffpageBodyWidth）。
const GP_OFFPAGE_FLAT_RATIO: float = 0.70

# Fraction of the BODY width where the signal hexagon's point starts, on BOTH ends.
# 信号六边形两端的尖部起始比例（占主体宽度）。
const GP_OFFPAGE_NOTCH_RATIO: float = 0.24

# The unit-space width every off-page glyph is authored against. The HEIGHT is derived from the
# definition's envelope aspect (see _gpOffpageBoxHeight), so the uniform fit lands the glyph
# exactly on the envelope and the port on the drawn edge, for ANY envelope shape. The outline
# itself is authored NARROWER (left-anchored) when the reference text is short — the box stays
# full so the fit, the port edge and every consumer's mapping are untouched.
# 跨图纸字形所依的单位空间宽度。**高度**由定义的包络长宽比推导（见 _gpOffpageBoxHeight），故均匀
# 适配后字形恰好贴合包络、端口恰好落在画出的边上 —— 对**任何**包络形状皆然。当编号文字较短时，
# 轮廓本身按**左锚定**画得更窄 —— 盒保持全宽，使适配、端口边缘与所有消费方的映射都不受影响。
const GP_OFFPAGE_BOX_W: float = 100.0

# Horizontal breathing room (mm) added around the reference text inside the flag body.
# Scales with the reference height (0.3x it) so the proportion survives size changes.
# 旗标主体内、交叉编号文字四周的水平留白（mm）。随编号字高缩放（其 0.3 倍），比例不随尺寸漂移。
const GP_OFFPAGE_PAD_MM: float = 2.4

# The narrowest flag body (mm) — what an EMPTY (unlinked) connector still draws, so a bare
# pennant never collapses into a sliver. 12.0 = 1.5x the reference height: at the doubled
# 8 mm text it sits just under a typical "3-1" reference (~13 mm), so the adaptive property
# stays visible on ordinary short numbers too.
# 旗标主体的最小宽度（mm）—— 空白（未连线）连接符也至少画这么宽，光杆旗标绝不细成一缕。
# 12.0 = 编号字高的 1.5 倍：在翻倍后的 8mm 字高下恰在典型 "3-1" 编号（约 13mm）之下，
# 使自适应性质对常见的短编号也看得见。
const GP_OFFPAGE_MIN_BODY_MM: float = 12.0


# D20 three-state ids (user feedback 2026-11-04). The generator is the SINGLE SOURCE of the
# state decision; the view (stroke color) and the print model (lineweight) only translate it.
# D20 三态 id（用户反馈 2026-11-04）。生成器是三态判定的**单一来源**；视图（描边色）与
# 打印模型（线重）只做翻译。
const GP_OFFPAGE_UNLINKED: String = "unlinked"
const GP_OFFPAGE_DANGLING: String = "dangling"
const GP_OFFPAGE_RESOLVED: String = "resolved"


# The offpage three-state for a reference text — the same "" / "?" / tag contract
# gpRefTextFor already owns, surfaced as a key. Pure.
# 交叉编号文字对应的三态 —— 与 gpRefTextFor 已有的 "" / "?" / tag 契约同源，只是显式成键。
# 纯函数。
static func gpOffpageStateFor(gpRefText: String) -> String:
	var gpT: String = gpRefText.strip_edges()
	if gpT == "":
		return GP_OFFPAGE_UNLINKED
	if gpT == "?":
		return GP_OFFPAGE_DANGLING
	return GP_OFFPAGE_RESOLVED


# Generate the flag + its derived reference text.
# 生成旗标及其推导出的交叉编号文字。
static func _gpGenerateOffpage(gpDef: GPSymbolDef, gpNode: GPPIDNode) -> Dictionary:
	var gpH: float = _gpOffpageBoxHeight(gpDef)
	# TEXT LAYOUT (user feedback 2026-11-03, refined the same day): all three slots are
	# DERIVED or INHERITED, none is hand-typed on the connector —
	#   INSIDE the flag  — the peer drawing number (DERIVED, the three states below);
	#   ABOVE the flag   — the TARGET end's tag (DERIVED through GPOffPageIndex: the item
	#                      the link serves on the sheet it points at);
	#   BELOW the flag   — the medium (INHERITED: copied from the source edge into the link
	#                      at creation, GPCrossSheetCreateCommand).
	# The renderer and the print model read the same three slots, so screen and paper cannot
	# disagree. Empty slots paint nothing — the honest "not resolved yet".
	# 文字版式（用户反馈 2026-11-03，同日细化）：三个槽位全部**推导或继承**，没有一个是在
	# 连接符上手填的 —— **框内**：对端图纸号（**推导**，即下方三态）；**框上方**：**目标端**
	# 位号（经 GPOffPageIndex 推导：link 所指图纸上被服务的那台设备 / 仪表 / 管线）；
	# **框下方**：介质（**继承**：创建时从源边拷入 link，见 GPCrossSheetCreateCommand）。
	# 渲染器与打印模型读**同一组**三个槽位，屏幕与纸面不可能分家。空槽不画 —— 诚实的
	# 「尚未解析」。
	var gpTarget: String = ""
	var gpMedium: String = ""
	var gpLink: GPOffPageLink = GPOffPageIndex.gpLinkForNode(
		gpNode.gpInstanceId if gpNode != null else "")
	if gpLink != null:
		gpMedium = str(gpLink.gpAttrs.get(GPOffPageLink.GP_ATTR_MEDIUM, ""))
		gpTarget = GPOffPageIndex.gpTargetTagFor(gpNode)
	# The reference text: "" while unlinked (a blank flag is the honest look of "not connected
	# yet"), "?" when the reference dangles, the tag or peer number once resolved. The DECISION
	# lives in GPOffPageIndex so the S3 commands and the S4 rules read the same three states.
	# 交叉编号文字：未连线时为 ""（空白旗标正是「尚未连接」的诚实样子），引用悬空时为 "?"，
	# 已解析时为 tag 或对端图号。判定放在 GPOffPageIndex，使 S3 命令与 S4 规则读到**同一组**三态。
	var gpRef: String = GPOffPageIndex.gpRefTextFor(gpNode)
	# ADAPTIVE BODY WIDTH (user feedback 2026-11-03): the flag hugs the text it carries —
	# height ~1.25x the reference text height (the envelope's job), width driven by the text.
	# 宽度自适应（用户反馈 2026-11-03）：旗标紧贴所载文字 —— 高度约 1.25 倍编号字高（由包络
	# 保证），宽度由文字驱动。
	var gpBodyW: float = _gpOffpageBodyWidth(gpDef, gpRef)
	var gpPaths: Array = _gpOffpagePaths(gpH, gpBodyW, _gpIsSignalConnector(gpDef))
	# D20 three-state visual (user feedback 2026-11-04): the STATE rides the generator output
	# as a key — screen picks a STROKE color from it, print picks a LINEWEIGHT from it; both
	# read this one decision so screen and paper cannot disagree (B2 redline: color/stroke
	# only — geometry and the blank-row contract are untouched).
	# D20 三态视觉（用户反馈 2026-11-04）：三态作为键随生成器输出走 —— 屏幕由它选**描边色**、
	# 打印由它选**线重**，双方读同一份判定，屏幕与纸面不可能分家（B2 红线：只改描边/颜色
	# —— 几何与空行占位契约分毫不动）。
	# MIRRORED TWIN (user feedback 2026-11-03): a connector standing on the TARGET sheet is
	# authored with gpFlipped = true — the BODY's own flip transform mirrors the glyph (flat
	# face + port land on the RIGHT, pennant pointing back off-page) and mirrors the text
	# POSITIONS with it, while the view counter-mirrors the text GLYPHS so they stay readable
	# (see GPSymbolView._gpDrawTextLines). The generator therefore stays FLIP-AGNOSTIC: one
	# output for both orientations, exactly one mirroring, no double mirror.
	# 镜像孪生体（用户反馈 2026-11-03）：立在**目标**图纸上的连接符以 gpFlipped = true 创建
	# —— body 自带的翻转变换把字形镜像（平直面 + 端口落在**右**缘、旗尖指回图外），并连带镜像
	# 文字**位置**；视图再对文字**字形**做反向镜像使其保持可读（见 GPSymbolView 的
	# _gpDrawTextLines）。故生成器对翻转**无感**：两种朝向一份输出、恰好一次镜像、绝不双重。
	return {
		"spec": {"paths": gpPaths, "box": [0.0, 0.0, GP_OFFPAGE_BOX_W, gpH]},
		"text_lines": PackedStringArray([gpRef]),
		"text_above": gpTarget,
		"text_below": gpMedium,
		"offpage_state": gpOffpageStateFor(gpRef),
		# Where the text column is centred, in UNIT space (the body's midpoint). The view maps
		# it through the spec box's uniform fit, so the text rides the BODY, not the envelope.
		# 文字列的中心，单位空间（主体中点）。视图经 spec 盒的均匀适配映射它，文字跟着**主体**
		# 而非包络走。
		"text_center_u": gpBodyW * 0.5,
		"text_mm": GPTextRole.GP_OFFPAGE_REF_MM,
	}


# PER-INSTANCE port position overrides, NORMALIZED on the def's envelope (0..1). The ONE hook
# GPPortResolver reads; every consumer of a port position (edge ends, port dots, snap, grips,
# DRC snapshot, DEXPI import) picks the override up from there, so the continuation port can
# ride the ADAPTIVE body's tip for any reference width. Returns {} when the generator declares
# no override — today only the off-page "cont" port moves; "ref" stays on the drawn left edge.
# 逐实例的端口位置覆盖，按定义包络**归一化**（0..1）。这是 GPPortResolver 读取的**唯一**钩子；
# 端口位置的每个消费方（边端点、端口圆点、吸附、抓取点、DRC 快照、DEXPI 导入）都从这里取
# 覆盖值，使续接端口在任何编号宽度下都贴着**自适应**主体的旗尖。生成器未声明覆盖时返回 {}
# —— 今天只有跨图纸的 "cont" 端口会动；"ref" 恒在画出的左缘上。
static func gpPortUnitOverrides(gpDef: GPSymbolDef, gpNode: GPPIDNode) -> Dictionary:
	if gpDef == null or gpNode == null:
		return {}
	if gpGeneratorId(gpDef.gpGeometrySource) != "offpage":
		return {}
	# The body's tip, as a fraction of the envelope width. The body spans [0, gpBodyW] of the
	# unit box, and the unit box maps 1:1 onto the envelope — the SAME mapping the spec box
	# gives every other consumer, so the port and the drawn tip cannot disagree.
	# 主体的旗尖，占包络宽度的比例。主体横跨单位盒的 [0, gpBodyW]，而单位盒与包络一一映射
	# —— 与 spec 盒给其它消费方的是**同一**映射，故端口与画出的旗尖不可能不一致。
	var gpBodyW: float = _gpOffpageBodyWidth(gpDef, GPOffPageIndex.gpRefTextFor(gpNode))
	return {GPSymbolPackOffpage.GP_PORT_CONT:
		Vector2(gpBodyW / GP_OFFPAGE_BOX_W, 0.5)}


# The flag body's width in unit space, derived from the reference text it must hug. The unit box
# stays FULL width so the uniform fit is unchanged; the body just occupies the left part of it,
# which keeps the port (at unit x=0) on drawn geometry for every consumer.
# 旗标主体在单位空间中的宽度，由它要紧贴的编号文字推导。单位盒保持**全宽**使均匀适配不变；
# 主体只占其左侧一部分 —— 这保证了端口（单位 x=0）在所有消费方都落在画出的几何上。
static func _gpOffpageBodyWidth(gpDef: GPSymbolDef, gpRef: String) -> float:
	var gpEnvW: float = GP_OFFPAGE_BOX_W
	if gpDef != null and gpDef.gpDefaultSize.x > 0.001:
		gpEnvW = gpDef.gpDefaultSize.x
	var gpNeed: float = _gpRefTextWidthMM(gpRef) + GP_OFFPAGE_PAD_MM
	var gpMin: float = GP_OFFPAGE_MIN_BODY_MM * GP_OFFPAGE_BOX_W / gpEnvW
	return clampf(gpNeed * GP_OFFPAGE_BOX_W / gpEnvW, gpMin, GP_OFFPAGE_BOX_W)


# A font-free width estimate of the reference text, in mm at the declared reference height.
# Per-character classes: full-width (CJK) 1.0, narrow punctuation/digits-of-honour 0.35,
# lowercase 0.52, everything else (digits, upper) 0.62 — generous enough that a flag is never
# caught clipping its own number. The PDF/DXF writer measures the REAL font; this estimate only
# sizes geometry, and erring wide is the safe direction.
# 编号文字的无字体宽度估算（按声明字高，单位 mm）。逐字符分类：全角（中日韩）1.0、窄标点与
# 「1」类窄数字 0.35、小写 0.52、其余（数字、大写）0.62 —— 宁宽勿窄，旗标绝不裁掉自己的编号。
# PDF/DXF 写出器量的是**真**字体；本估算只为几何定尺寸，偏宽是安全方向。
static func _gpRefTextWidthMM(gpS: String) -> float:
	var gpW: float = 0.0
	for gpC in gpS:
		if gpC.unicode_at(0) >= 0x2E80:
			gpW += 1.0
		elif gpC in [".", ",", "-", ":", ";", " ", "'", "1", "i", "j", "l", "I", "(", ")", "/"]:
			gpW += 0.35
		elif gpC != gpC.to_upper():
			gpW += 0.52
		else:
			gpW += 0.62
	return gpW * GPTextRole.GP_OFFPAGE_REF_MM


# Whether this connector carries SIGNALs (as opposed to process piping). The port purpose is the
# single discriminator — no symbol-id list anywhere.
# 本连接符承载的是**信号**（而非工艺管道）吗。端口用途是唯一判据 —— 代码里没有任何符号 id 名单。
static func _gpIsSignalConnector(gpDef: GPSymbolDef) -> bool:
	if gpDef == null:
		return false
	return not gpDef.gpPortsOfType(GPPort.GP_SIGNAL).is_empty()


# Unit-space box height for this definition, derived from its envelope aspect so that
# min(envelope.x / 100, envelope.y / H) == envelope.x / 100: the glyph then fills the envelope
# exactly and its left edge — where the port sits — is the envelope's left edge.
# 本定义的单位空间盒高，由包络长宽比推导，使 min(包络.x/100, 包络.y/H) == 包络.x/100：字形因此
# 恰好填满包络，其左边缘（端口所在）即包络左边缘。
# A degenerate or missing size falls back to the square box, i.e. the pre-derivation behaviour.
# 尺寸退化或缺失时回落到方盒，即推导引入之前的行为。
static func _gpOffpageBoxHeight(gpDef: GPSymbolDef) -> float:
	if gpDef == null:
		return GP_OFFPAGE_BOX_W
	var gpW: float = maxf(gpDef.gpDefaultSize.x, 0.001)
	var gpS: float = maxf(gpDef.gpDefaultSize.y, 0.001)
	return clampf(GP_OFFPAGE_BOX_W * gpS / gpW, 1.0, 1000.0)


# The outline, as closed polylines in unit space (the last point repeats the first — the painter
# draws polylines and does NOT close them for us).
# 轮廓，单位空间中的闭合折线（末点复写首点 —— 绘制器只画折线，不会替我们闭合）。
# The LEFT edge is a full-height vertical in both variants, so the port at (0, 0.5) lands exactly
# on drawn geometry rather than in empty space. The body spans [0, gpBodyW] — LEFT-ANCHORED,
# because the pipe arrives at the flag's left edge and the flag grows rightward only as far as
# its text needs (adaptive body width, see _gpOffpageBodyWidth).
# 两个变体的**左**边都是整高竖线，故位于 (0, 0.5) 的端口恰好落在画出的几何上，而不是空白处。
# 主体横跨 [0, gpBodyW] —— **左锚定**：管线从旗标左缘接入，旗标只向右长到文字所需的宽度
#（自适应主体宽，见 _gpOffpageBodyWidth）。
static func _gpOffpagePaths(gpH: float, gpBodyW: float, gpIsSignal: bool) -> Array:
	var gpMid: float = gpH * 0.5
	if gpIsSignal:
		# Both ends pointed: "the signal goes somewhere and comes from somewhere" — visually
		# distinct from the one-way pennant at a glance, which is the only job of the silhouette.
		# 两端皆尖：「信号去往别处、也来自别处」—— 一眼即可与单向旗标区分，这就是轮廓的全部职责。
		var gpN: float = gpBodyW * GP_OFFPAGE_NOTCH_RATIO
		var gpFar: float = gpBodyW - gpN
		return [{"pts": [
			[0.0, gpMid], [gpN, 0.0], [gpFar, 0.0], [gpBodyW, gpMid],
			[gpFar, gpH], [gpN, gpH], [0.0, gpMid],
		]}]
	var gpKnee: float = gpBodyW * GP_OFFPAGE_FLAT_RATIO
	return [{"pts": [
		[0.0, 0.0], [gpKnee, 0.0], [gpBodyW, gpMid], [gpKnee, gpH], [0.0, gpH],
		[0.0, 0.0],
	]}]
