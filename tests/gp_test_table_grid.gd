extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
# Stage-3 equipment data table suite (GENERATOR:grid).
# 阶段 3 设备参数表套件（GENERATOR:grid）。
#
# Pins: the grid generator's pure geometry (cells / spec / hit), the row/col structure
# transform (shift + guards + caps), the snapshot-swap command (undo restores EVERY key),
# the TABLE:device_param template, the library wiring, the in-place-editor exclusion, and
# props round-trip.
# 钉住：grid 生成器纯几何（格子 / 规格 / 命中）、行列结构变换（位移 + 守卫 + 上限）、
# 快照交换命令（撤销还原**每一个**键）、TABLE:device_param 模板、库接线、就地编辑排除、
# 属性往返。
#
# ⚠️ 期望值从常量/几何推导，绝不从实现抄（铁律 86）。
# ⚠️ Expectations derive from constants/geometry, never copied from the implementation.

# The reference envelope: 90x26 mm, 60+15+15 cols, 8 rows of 3.25.
# 参照包络：90×26mm，60+15+15 列，8 行 × 3.25。
const GP_ENV: Vector2 = Vector2(180.0, 52.0)


# A grid def shaped like the built-in template (without touching the global library).
# 一个形似内置模板的 grid 定义（不触碰全局图元库）。
func _gpGridDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "TGRID1"
	gpD.gpDefaultSize = GP_ENV
	gpD.gpSizeMode = GPSymbolDef.GP_SIZE_MODE_EXPLICIT
	gpD.gpGeometrySource = GPSymbolDef.GP_GEOMETRY_GENERATOR_PREFIX + "grid"
	gpD.gpAvoidRouting = false
	gpD.gpTaggable = false
	gpD.gpMountable = false
	return gpD


# A graph with one table node carrying two filled cells.
# 一张含一个表格节点（两个已填格）的图。
func _gpTableNode(gpPropsIn: Dictionary) -> GPPIDNode:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("t1", "TGRID1", "", Vector2(0, 0)))
	var gpN: GPPIDNode = gpG.gpGetNode("t1")
	for gpK in gpPropsIn:
		gpN.gpProps[gpK] = gpPropsIn[gpK]
	return gpN


# ---------------------------------------------------------------- 1) generator geometry
# ---------------------------------------------------------------- 1) 生成器几何

# Default grid: 8x3 = 24 cells, first cell at the envelope top-left, last cell ends at the
# envelope bottom-right, every rect inside the envelope.
# 默认格网：8×3 = 24 格，首格在包络左上、末格终于包络右下、每个矩形都在包络内。
func gpTestGridCellsDefault() -> void:
	var gpDef: GPSymbolDef = _gpGridDef()
	var gpN: GPPIDNode = _gpTableNode({})
	var gpCells: Array[Dictionary] = GPSymbolGeneratorRegistry.gpGridCellsOf(gpDef, gpN)
	gpEq(gpCells.size(), 24, "默认格网应有 8x3=24 格")
	gpEq(str(gpCells[0]["key"]), GPSymbolGeneratorRegistry.gpCellKey(0, 0), "首格键应为 cell_0_0")
	var gpFirst: Rect2 = gpCells[0]["rect"] as Rect2
	gpEq(gpFirst.position, Vector2(-90.0, -26.0), "首格应从包络左上开始")
	gpApprox(gpFirst.size.x, 120.0, 0.001, "首列宽应为 120mm（A1 ×2 重定基）")
	gpApprox(gpFirst.size.y, 6.5, 0.001, "首行高应为 6.5mm（A1 ×2 重定基）")
	var gpLast: Rect2 = gpCells[23]["rect"] as Rect2
	gpEq(gpLast.end, Vector2(90.0, 26.0), "末格应终于包络右下")
	var gpEnvRect: Rect2 = Rect2(Vector2(-90.0, -26.0), GP_ENV)
	for gpCell in gpCells:
		gpCheck(gpEnvRect.grow(0.001).encloses(gpCell["rect"] as Rect2), "每格都应在包络内")
	# The key grid: cumulated widths/heights leave no gaps — cell (4,0) starts where rows
	# 0..3 end (4 x 3.25 = 13mm below the top).
	# 关键格网：宽高累加无缝 —— 格 (4,0) 起于行 0..3 之底（顶下 4×3.25=13mm）。
	var gpR40: Rect2 = gpCells[12]["rect"] as Rect2
	gpEq(gpR40.position, Vector2(-90.0, 0.0), "格 (4,0) 应起于纵向中线（无缝累加）")


# The spec: unit-space polylines with a box matching the envelope aspect (100 x 100*H/W);
# path count = 1 border + (rows-1) + (cols-1) separators = 1+7+2 = 10.
# 规格：单位空间折线，box 与包络同纵横比（100 × 100*H/W）；路径数 = 1 外框 + 7 行分隔
# + 2 列分隔 = 10。
func gpTestGridGenerateSpec() -> void:
	var gpDef: GPSymbolDef = _gpGridDef()
	var gpN: GPPIDNode = _gpTableNode({})
	var gpGen: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(gpDef, gpN)
	var gpSpec: Dictionary = gpGen.get("spec", {}) as Dictionary
	gpCheck(not gpSpec.is_empty(), "grid 生成器应产出非空规格")
	var gpPaths: Array = gpSpec.get("paths", []) as Array
	gpEq(gpPaths.size(), 10, "规格应含 1 外框 + 7 行分隔 + 2 列分隔")
	var gpBox: Array = gpSpec.get("box", []) as Array
	gpApprox(float(gpBox[3]), 100.0 * 52.0 / 180.0, 0.001, "box 高应为 100*H/W（同纵横比；52/180 == 26/90，重定基不改变比例）")
	gpEq(int(gpBox[2]), 100, "box 宽应为 100")
	var gpCells: Array = gpGen.get("cells", []) as Array
	gpEq(gpCells.size(), 24, "生成器应同时返回 24 格（渲染命中同源）")


# gpCellAt: the point (0,0) sits in cell (4,0) (rows 0..3 end exactly at y=0); an outside
# point misses; a corner point lands in cell (0,0).
# gpCellAt：点 (0,0) 落在格 (4,0)（行 0..3 恰于 y=0 收尾）；格外点未命中；角点落格 (0,0)。
func gpTestCellAt() -> void:
	var gpDef: GPSymbolDef = _gpGridDef()
	var gpN: GPPIDNode = _gpTableNode({})
	gpEq(GPSymbolGeneratorRegistry.gpCellAt(gpDef, gpN, Vector2(0.0, 0.0)),
		GPSymbolGeneratorRegistry.gpCellKey(4, 0), "原点应命中格 (4,0)")
	gpEq(GPSymbolGeneratorRegistry.gpCellAt(gpDef, gpN, Vector2(-89.0, -25.0)),
		GPSymbolGeneratorRegistry.gpCellKey(0, 0), "左上角应命中格 (0,0)（探针点随 ×2 重定基）")
	gpEq(GPSymbolGeneratorRegistry.gpCellAt(gpDef, gpN, Vector2(89.9, 25.9)),
		GPSymbolGeneratorRegistry.gpCellKey(7, 2), "右下角应命中格 (7,2)（探针点随 ×2 重定基）")
	gpEq(GPSymbolGeneratorRegistry.gpCellAt(gpDef, gpN, Vector2(100.0, 100.0)),
		"", "格外点应未命中")


# ---------------------------------------------------------------- 2) structure transform
# ---------------------------------------------------------------- 2) 结构变换

func gpTestMutatedPropsInsertRow() -> void:
	var gpProps: Dictionary = {"cell_0_0": "A", "cell_1_0": "B", "col_widths": "60,15,15",
		"row_heights": "3.25,3.25"}
	var gpRes: Dictionary = GPSymbolGeneratorRegistry.gpMutatedProps(gpProps,
		GPSymbolGeneratorRegistry.GP_OP_INSERT_ROW, 1, 0)
	gpCheck(bool(gpRes["ok"]), "插入行应成功")
	var gpAfter: Dictionary = gpRes["props"] as Dictionary
	gpEq(gpAfter["row_heights"].split(",").size(), 3, "插入后应 3 行")
	gpEq(str(gpAfter["col_widths"]), "60,15,15", "列宽不应变化")
	gpEq(str(gpAfter.get("cell_0_0", "")), "A", "被点行之上的文字不应移动")
	gpCheck(not gpAfter.has(GPSymbolGeneratorRegistry.gpCellKey(1, 0)),
		"新插入行应为空格")
	gpEq(str(gpAfter.get("cell_2_0", "")), "B", "被点行的文字应下移一行")


func gpTestMutatedPropsDeleteColShifts() -> void:
	var gpProps: Dictionary = {"cell_0_2": "X", "row_heights": "3.25,3.25"}
	var gpRes: Dictionary = GPSymbolGeneratorRegistry.gpMutatedProps(gpProps,
		GPSymbolGeneratorRegistry.GP_OP_DELETE_COL, 0, 1)
	gpCheck(bool(gpRes["ok"]), "删除列应成功")
	var gpAfter: Dictionary = gpRes["props"] as Dictionary
	gpEq(gpAfter["col_widths"].split(",").size(), 2, "删除后应 2 列")
	gpEq(gpAfter["row_heights"].split(",").size(), 2, "行高不应变化")
	gpEq(str(gpAfter.get("cell_0_1", "")), "X", "被删列右侧的文字应左移一列")
	gpCheck(not gpAfter.has("cell_0_2"), "旧键 cell_0_2 不应残留")


func gpTestMutatedPropsGuards() -> void:
	var gpProps: Dictionary = {"row_heights": "5", "col_widths": "10"}
	var gpRes: Dictionary = GPSymbolGeneratorRegistry.gpMutatedProps(gpProps,
		GPSymbolGeneratorRegistry.GP_OP_DELETE_ROW, 0, 0)
	gpCheck(not bool(gpRes["ok"]), "删最后一行应拒绝")
	gpRes = GPSymbolGeneratorRegistry.gpMutatedProps(gpProps,
		GPSymbolGeneratorRegistry.GP_OP_DELETE_COL, 0, 0)
	gpCheck(not bool(gpRes["ok"]), "删最后一列应拒绝")
	gpRes = GPSymbolGeneratorRegistry.gpMutatedProps(gpProps, "bogus_op", 0, 0)
	gpCheck(not bool(gpRes["ok"]), "未知操作应拒绝")
	var gpLongCsv: PackedStringArray = PackedStringArray()
	for gpI in range(GPSymbolGeneratorRegistry.GP_MAX_ROWS):
		gpLongCsv.append("1")
	gpRes = GPSymbolGeneratorRegistry.gpMutatedProps(
		{"row_heights": ",".join(gpLongCsv), "col_widths": "10"},
		GPSymbolGeneratorRegistry.GP_OP_INSERT_ROW, 0, 0)
	gpCheck(not bool(gpRes["ok"]), "超出行上限应拒绝")
	gpRes = GPSymbolGeneratorRegistry.gpMutatedProps(gpProps,
		GPSymbolGeneratorRegistry.GP_OP_DELETE_ROW, 5, 0)
	gpCheck(not bool(gpRes["ok"]), "越界行下标应拒绝")


# ---------------------------------------------------------------- 3) command + undo
# ---------------------------------------------------------------- 3) 命令与撤销

# Execute swaps in "after"; undo restores "before" key-for-key — including keys that only
# existed on one side (a delete-row renumber must fully reverse).
# 执行换入 after；撤销逐键还原 before —— 包括只存在于其中一侧的键
#（删行重排必须能完全逆转）。
func gpTestTableMutateCommandUndo() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("t1", "TGRID1", "", Vector2(0, 0)))
	var gpN: GPPIDNode = gpG.gpGetNode("t1")
	gpN.gpProps["col_widths"] = "60,15,15"
	gpN.gpProps["row_heights"] = "3.25,3.25"
	gpN.gpProps["cell_0_0"] = "A"
	gpN.gpProps["cell_1_0"] = "B"
	gpN.gpProps["unrelated"] = "keep"
	var gpBefore: Dictionary = gpN.gpProps.duplicate(true)
	var gpRes: Dictionary = GPSymbolGeneratorRegistry.gpMutatedProps(gpN.gpProps,
		GPSymbolGeneratorRegistry.GP_OP_DELETE_ROW, 1, 0)
	gpCheck(bool(gpRes["ok"]), "删行应成功")
	var gpCmd: GPTableMutateCommand = GPTableMutateCommand.new("t1", gpBefore,
		gpRes["props"] as Dictionary)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG, null, null)
	gpCheck(gpCmd.gpExecute(gpCtx), "命令应执行成功")
	gpEq(str(gpN.gpProps.get("cell_0_0", "")), "A", "执行后首行文字保留")
	gpCheck(not gpN.gpProps.has("cell_1_0"), "执行后第二行应消失")
	gpEq(str(gpN.gpProps.get("unrelated", "")), "keep", "无关键不应被触碰")
	gpCmd.gpUndo(gpCtx)
	for gpK in gpBefore:
		gpEq(gpN.gpProps.get(gpK, "__MISSING__"), gpBefore[gpK], "撤销后键 " + gpK + " 应逐键还原")
	gpEq(gpN.gpProps.size(), gpBefore.size(), "撤销后键数量应还原")


# The service entry: refuses with the i18n key on a guard, and is a no-op (false, no
# command) when nothing would change.
# 服务入口：守卫拒绝时给 i18n 键；无变化时为无操作（返回 false、不压命令）。
func gpTestEditServiceMutateTable() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("t1", "TGRID1", "", Vector2(0, 0)))
	var gpN: GPPIDNode = gpG.gpGetNode("t1")
	gpN.gpProps["row_heights"] = "5"
	gpN.gpProps["col_widths"] = "10"
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpCtx = GPCommandContext.new(gpG, null, null)
	gpCheck(not gpSvc.gpMutateTable("t1", GPSymbolGeneratorRegistry.GP_OP_DELETE_ROW, 0, 0),
		"删最后一行应被服务拒绝")
	gpEq(gpSvc.gpLastRefusal, "table.err_structure", "拒绝原因应为 i18n 键")
	gpCheck(not gpSvc.gpMutateTable("", GPSymbolGeneratorRegistry.GP_OP_INSERT_ROW, 0, 0),
		"空节点 id 应拒绝")
	gpCheck(gpSvc.gpMutateTable("t1", GPSymbolGeneratorRegistry.GP_OP_INSERT_ROW, 0, 0),
		"正常插入行应成功")
	gpEq(gpN.gpProps["row_heights"].split(",").size(), 2, "插入后应 2 行")


# ---------------------------------------------------------------- 4) template + wiring
# ---------------------------------------------------------------- 4) 模板与接线

func gpTestTableTemplateDef() -> void:
	var gpFound: GPSymbolDef = null
	var gpCount: int = 0
	for gpD in GPSymbolAnnotationTemplates.gpDefs():
		if gpD.gpId == GPSymbolAnnotationTemplates.GP_TABLE_DEVICE_PARAM_ID:
			gpFound = gpD
		gpCount += 1
	gpEq(gpCount, 2, "注释模板应有 2 个（多行文本 + 设备参数表）")
	gpCheck(gpFound != null, "应存在 TABLE:device_param 模板")
	if gpFound == null:
		return
	gpEq(gpFound.gpCategory, "annotation", "模板类目应为 annotation")
	gpEq(gpFound.gpSizeMode, GPSymbolDef.GP_SIZE_MODE_EXPLICIT, "模板应为显式尺寸")
	gpEq(gpFound.gpGeometrySource, "GENERATOR:grid", "模板几何应来自 grid 生成器")
	gpEq(gpFound.gpPickMode, GPSymbolDef.GP_PICK_FULL,
		"模板拾取应为 FULL（阶段 2 反馈：点格子即选中）")
	gpCheck(not gpFound.gpAvoidRouting, "模板不参与避让")
	gpCheck(not gpFound.gpTaggable, "模板不可编号")
	gpCheck(not gpFound.gpMountable, "模板不可挂载")
	gpEq(gpFound.gpDefaultSize, Vector2(180.0, 52.0), "模板包络应为 180x52mm（参照表 ×2 重定基）")
	gpEq(gpFound.gpShapes.size(), 0, "模板无静态形状（几何归生成器）")
	gpEq(gpFound.gpPorts.size(), 0, "表格不应有端口")
	gpCheck(gpFound.gpBuiltin, "模板应为内置（D3 只读）")
	# The A1-rebase text doubling is pinned at the constant level: the cell cap and the
	# annotation scale are exactly 2x their A3-era values (user feedback 2026-10-17).
	# A1 重定基的文字翻倍在常量层钉住：格字上限与注释比例恰为 A3 时代值的 2 倍
	#（用户实测反馈 2026-10-17）。
	gpEq(GPSymbolView.GP_CELL_FONT_MM, 4.4, "格字上限应随重定基翻倍至 4.4mm")
	gpEq(GPSymbolView.GP_ANNOTATE_FONT_SCALE, 2.0, "注释文字相对在管档比例应为 2.0")
	gpCheck(gpFound.gpSchema != null, "模板应声明 schema")
	if gpFound.gpSchema != null:
		gpCheck((gpFound.gpSchema as GPPropertySchema).gpFieldByKey("col_widths") != null,
			"schema 应声明 col_widths")
		gpCheck((gpFound.gpSchema as GPPropertySchema).gpFieldByKey("row_heights") != null,
			"schema 应声明 row_heights")


func gpTestLibraryServesTable() -> void:
	var gpD: GPSymbolDef = GPSymbolLibrary.gpFindById("TABLE:device_param")
	gpCheck(gpD != null, "图元库应能按 id 找到 TABLE:device_param")
	if gpD == null:
		return
	gpEq(gpD.gpDefaultSize, Vector2(180.0, 52.0), "库中模板应保持参照包络（×2 重定基）")
	gpCheck(GPSymbolGeneratorRegistry.gpIsGenerator(gpD.gpGeometrySource),
		"库中模板应走生成器")


# A grid table is NOT a tag-editing target — its double-clicks belong to the cell dispatch.
# grid 表格**不是**位号编辑目标 —— 它的双击归格子分派。
func gpTestWantsInPlaceExcludesGrid() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("t1", "TGRID1", "", Vector2(0, 0)))
	var gpN: GPPIDNode = gpG.gpGetNode("t1")
	gpCheck(not GPNodeTextEditor.gpWantsInPlace(gpN, _gpGridDef()),
		"grid 定义不得进入位号就地编辑路径")


# Props (CSVs + cell keys) survive a node round trip untouched — persistence is the whole
# data-sovereignty promise.
# 属性（CSV + 格键）应原样通过节点往返 —— 持久化即数据主权的承诺。
func gpTestPropsRoundtrip() -> void:
	var gpN: GPPIDNode = _gpTableNode({"col_widths": "60,15,15",
		"row_heights": "3.25,3.25", "cell_0_0": "A", "cell_1_1": "B"})
	var gpBack: GPPIDNode = GPPIDNode.new()
	gpBack.gpFromDict(gpN.gpToDict())
	for gpK in ["col_widths", "row_heights", "cell_0_0", "cell_1_1"]:
		gpEq(str(gpBack.gpProps.get(gpK, "")), str(gpN.gpProps[gpK]),
			"往返后键 " + gpK + " 应保持")
	gpEq(gpBack.gpProps.size(), gpN.gpProps.size(), "往返后属性数量应一致")


# ---------------------------------------------------------------- 5) column-width drag (S4)
# ---------------------------------------------------------------- 5) 列宽拖拽（S4）
#
# Geometry derivation (iron rule 86): default cols 120+30+30 span the 180 mm envelope, so
# boundary 1 sits at local x = -90 + 120/180*180 = 30 and boundary 2 at -90 + 150/180*180 = 60.
# 几何推导（铁律 86）：默认列 120+30+30 撑满 180mm 包络，故边界 1 在本地 x = -90 + 120/180*180 = 30，
# 边界 2 在 -90 + 150/180*180 = 60。

func gpTestColSeparatorAt() -> void:
	var gpDef: GPSymbolDef = _gpGridDef()
	var gpN: GPPIDNode = _gpTableNode({})
	# Exact hits on both derived boundaries. / 两条推导边界上的精确命中。
	gpEq(GPSymbolGeneratorRegistry.gpColSeparatorAt(gpDef, gpN, Vector2(30.0, 0.0), 1.0), 1,
		"x=30 应命中边界 1（120/180 处）")
	gpEq(GPSymbolGeneratorRegistry.gpColSeparatorAt(gpDef, gpN, Vector2(60.0, 0.0), 1.0), 2,
		"x=60 应命中边界 2（150/180 处）")
	# Tolerance band: inside 1.5 mm grabs, 1.6 mm misses. / 容差带：1.5mm 内抓到，1.6mm 落空。
	gpEq(GPSymbolGeneratorRegistry.gpColSeparatorAt(gpDef, gpN, Vector2(28.5, 0.0), 1.5), 1,
		"x=28.5 在 1.5mm 容差内应命中边界 1")
	gpEq(GPSymbolGeneratorRegistry.gpColSeparatorAt(gpDef, gpN, Vector2(31.6, 0.0), 1.0), -1,
		"x=31.6 距边界 1 超出 1mm 容差应落空")
	# The y gate: a separator is a FINITE line. / 纵向闸：分隔线是**有限高**的线。
	gpEq(GPSymbolGeneratorRegistry.gpColSeparatorAt(gpDef, gpN, Vector2(30.0, 30.0), 1.0), -1,
		"纵向出包络（y=30 > 26+容差）应落空")
	# Degenerate inputs. / 退化输入。
	gpEq(GPSymbolGeneratorRegistry.gpColSeparatorAt(gpDef, gpN, Vector2(30.0, 0.0), 0.0), -1,
		"零容差应拒绝")
	gpEq(GPSymbolGeneratorRegistry.gpColSeparatorAt(null, gpN, Vector2(30.0, 0.0), 1.0), -1,
		"空 def 应落空")
	var gpN1: GPPIDNode = _gpTableNode({"col_widths": "50"})
	gpEq(GPSymbolGeneratorRegistry.gpColSeparatorAt(gpDef, gpN1, Vector2(30.0, 0.0), 1.0), -1,
		"单列表格无内部边界应落空")


func gpTestGridWidthScale() -> void:
	var gpDef: GPSymbolDef = _gpGridDef()
	var gpN: GPPIDNode = _gpTableNode({})
	gpApprox(GPSymbolGeneratorRegistry.gpGridWidthScale(gpDef, gpN), 180.0 / 180.0, 0.0001,
		"默认 CSV 总和等于包络宽时比例应为 1")
	var gpN2: GPPIDNode = _gpTableNode({"col_widths": "60,15,15"})
	gpApprox(GPSymbolGeneratorRegistry.gpGridWidthScale(gpDef, gpN2), 90.0 / 180.0, 0.0001,
		"CSV 总和 90 / 包络宽 180 比例应为 0.5")
	gpEq(GPSymbolGeneratorRegistry.gpGridWidthScale(null, gpN), 0.0, "空 def 比例应为 0")


func gpTestColWidthShift() -> void:
	var gpProps: Dictionary = {"col_widths": "60,30,30", "row_heights": "6.5",
		"cell_0_0": "A"}
	# Normal trade across boundary 1: left takes +10, right gives it. / 边界 1 的正常对冲：左列拿 +10。
	var gpRes: Dictionary = GPSymbolGeneratorRegistry.gpColWidthShift(gpProps, 1, 10.0)
	gpCheck(bool(gpRes["ok"]), "正常对冲应成功")
	var gpAfter: Dictionary = gpRes["props"] as Dictionary
	gpEq(str(gpAfter["col_widths"]), "70,20,30", "对冲后应为 70,20,30（左拿右让）")
	gpEq(str(gpAfter.get("cell_0_0", "")), "A", "格键不应被触碰")
	gpEq(str(gpAfter["row_heights"]), "6.5", "行高不应被触碰")
	# Both over-drives clamp against the PAIR total (90): floors 5 / 85. / 双向超拖都以**两列和**（90）钳制。
	gpRes = GPSymbolGeneratorRegistry.gpColWidthShift(gpProps, 1, -100.0)
	gpEq(str((gpRes["props"] as Dictionary)["col_widths"]), "5,85,30",
		"左列触底应钳到 5，右列收下余量 85")
	gpRes = GPSymbolGeneratorRegistry.gpColWidthShift(gpProps, 2, 100.0)
	gpEq(str((gpRes["props"] as Dictionary)["col_widths"]), "60,55,5",
		"右列触底应钳到 5，左列收下余量 55")
	# Guards: bad index, degenerate pair total. / 守卫：越界下标、退化两列和。
	gpCheck(not bool(GPSymbolGeneratorRegistry.gpColWidthShift(gpProps, 0, 1.0)["ok"]),
		"下标 0 应拒绝")
	gpCheck(not bool(GPSymbolGeneratorRegistry.gpColWidthShift(gpProps, 3, 1.0)["ok"]),
		"越界下标 3 应拒绝")
	gpCheck(not bool(GPSymbolGeneratorRegistry.gpColWidthShift({"col_widths": "2,2"}, 1,
		1.0)["ok"]), "两列和低于下限两倍应按退化拒绝")
	# Missing CSV falls back to the template defaults (120,30,30). / 缺 CSV 回落模板默认（120,30,30）。
	gpRes = GPSymbolGeneratorRegistry.gpColWidthShift({}, 1, 10.0)
	gpEq(str((gpRes["props"] as Dictionary)["col_widths"]), "130,20,30",
		"缺 CSV 时应按默认列宽对冲")


# The service snapshot entry: executes the drag's commit as one undo step; an equal pair and
# an unknown node are refused.
# 服务快照入口：把拖拽的提交作为**一个**撤销步执行；相等快照对与未知节点被拒绝。
func gpTestCommitTableSnapshot() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("t1", "TGRID1", "", Vector2(0, 0)))
	var gpN: GPPIDNode = gpG.gpGetNode("t1")
	gpN.gpProps["col_widths"] = "60,30,30"
	gpN.gpProps["cell_0_0"] = "A"
	var gpBefore: Dictionary = gpN.gpProps.duplicate(true)
	var gpAfter: Dictionary = (GPSymbolGeneratorRegistry.gpColWidthShift(gpBefore, 1, 10.0)
		["props"] as Dictionary)
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpCtx = GPCommandContext.new(gpG, null, null)
	gpCheck(gpSvc.gpCommitTableSnapshot("t1", gpBefore, gpAfter), "快照提交应成功")
	gpEq(str(gpN.gpProps["col_widths"]), "70,20,30", "提交后列宽应为 70,20,30")
	gpEq(str(gpN.gpProps["cell_0_0"]), "A", "提交后格键保留")
	gpCheck(not gpSvc.gpCommitTableSnapshot("t1", gpAfter, gpAfter), "相等快照对应拒绝")
	gpCheck(not gpSvc.gpCommitTableSnapshot("", gpBefore, gpAfter), "空节点 id 应拒绝")
	gpCheck(not gpSvc.gpCommitTableSnapshot("nope", gpBefore, gpAfter), "未知节点应拒绝")


# The grip layer's pure tolerance: screen-constant pointing, like the frame band.
# 抓取层的**纯**容差：与图框抓取带一样按屏幕常量指向。
func gpTestTableGripTol() -> void:
	gpApprox(GPTableGripOps.gpGrabTol(2.0), 3.0, 0.0001, "6px 抓取带在 2 倍缩放下应为 3mm")
	gpApprox(GPTableGripOps.gpGrabTol(0.0), 6.0 / GPTableGripOps.GP_MIN_ZOOM, 0.0001,
		"退化缩放应钳到最小缩放")
