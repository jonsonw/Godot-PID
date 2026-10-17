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
#   "spec"       : a GPSymbolPainter shape spec ({paths,circles,rects,box}) — {} = no vector art.
#   "text_lines" : PackedStringArray of lines the view paints inside the envelope.
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
	return gpEmpty


# ---------------------------------------------------------------- grid (stage 3)
# ---------------------------------------------------------------- 格网（阶段 3）
#
# GENERATOR:grid — a TABLE (the equipment data table). The geometry is a variable grid:
# column widths + row heights come from gpProps CSVs, cell texts from per-cell props, and
# the output is BOTH the vector art (unit-space polylines whose box matches the envelope's
# aspect ratio, so the painter's uniform fit fills it exactly) AND the cell list — the ONE
# structure the renderer, the hit test and the in-place editor all consume (Rev.2 iron
# rule: rendering and hit testing must call the SAME generator, or the lines you see and
# the cells you can click drift apart).
# GENERATOR:grid —— 表格（设备参数表）。几何是**可变格网**：列宽/行高来自 gpProps CSV，
# 单元格文字来自逐格属性；输出既有矢量图形（单位空间折线，box 与包络同纵横比 ⇒ painter
# 的均匀适配恰好铺满），也有格子列表 —— 渲染、命中、就地编辑三方消费的**同一份**结构
#（Rev.2 铁律：渲染与命中必须调同一个生成器，否则「看起来的格线」与「点得到的格子」分家）。

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


# The grid GENERATOR output: spec (unit-space border + separators) + cells + empty lines.
# The box aspect equals the envelope's, so the painter's uniform fit fills it exactly.
# grid 生成器输出：spec（单位空间外框 + 分隔线）+ cells + 空文字行。box 纵横比与包络一致，
# painter 的均匀适配恰好铺满。
static func _gpGenerateGrid(gpDef: GPSymbolDef, gpNode: GPPIDNode) -> Dictionary:
	var gpCells: Array[Dictionary] = gpGridCellsOf(gpDef, gpNode)
	if gpCells.is_empty():
		return {"spec": {}, "text_lines": PackedStringArray()}
	var gpDims: Dictionary = _gpGridDims(gpNode)
	var gpCols: PackedFloat64Array = gpDims["cols"]
	var gpRows: PackedFloat64Array = gpDims["rows"]
	var gpW: float = 0.0
	for gpV in gpCols:
		gpW += gpV
	var gpH: float = 0.0
	for gpV in gpRows:
		gpH += gpV
	var gpEnv: Vector2 = gpDef.gpDefaultSize
	# Unit box matches the envelope aspect so the uniform fit has no letterboxing. In this
	# space BOTH axes divide by the SAME total (gpW): unit x = cumX/W*100, unit y =
	# cumY/W*100 (the y span is then 100*H/W, exactly the box height).
	# 单位 box 与包络同纵横比，均匀适配无留白。该空间中两轴除以**同一个**总量（gpW）：
	# unit x = cumX/W*100、unit y = cumY/W*100（y 跨度即 100*H/W，恰为 box 高）。
	var gpUnitH: float = 100.0 * gpH / gpW
	var gpXs: PackedFloat64Array = PackedFloat64Array([0.0])
	var gpCumX: float = 0.0
	for gpV in gpCols:
		gpCumX += gpV
		gpXs.append(gpCumX / gpW * 100.0)
	var gpYs: PackedFloat64Array = PackedFloat64Array([0.0])
	var gpCumY: float = 0.0
	for gpV in gpRows:
		gpCumY += gpV
		gpYs.append(gpCumY / gpW * 100.0)
	var gpPaths: Array = []
	# Outer border as ONE closed polyline. / 外框 = 一条闭合折线。
	gpPaths.append({"pts": [[0.0, 0.0], [100.0, 0.0], [100.0, gpUnitH], [0.0, gpUnitH],
		[0.0, 0.0]]})
	# Internal horizontal separators (between rows, endpoints excluded). / 行间内分隔线（不含端点）。
	for gpI in range(1, gpYs.size() - 1):
		gpPaths.append({"pts": [[0.0, gpYs[gpI]], [100.0, gpYs[gpI]]]})
	# Internal vertical separators (between cols). / 列间内分隔线。
	for gpI in range(1, gpXs.size() - 1):
		gpPaths.append({"pts": [[gpXs[gpI], 0.0], [gpXs[gpI], gpUnitH]]})
	return {
		"spec": {"paths": gpPaths, "box": [0.0, 0.0, 100.0, gpUnitH]},
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
