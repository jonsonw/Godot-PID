extends "res://tests/gp_test.gd"
# DXF export: the file must be readable R12 whose geometry is the print model's own — the
# Y flip happens exactly once here, non-ASCII text survives as \U+XXXX, and every standard
# layer lands in the LAYER table. A writer that invented its own geometry would be the
# second copy of a judgment the print model already owns.
# DXF 导出：文件必须是可读的 R12，其几何即打印模型自身的 —— Y 翻转只在此发生一次，
# 非 ASCII 文字以 \U+XXXX 存活，每个标准图层都进 LAYER 表。自行发明几何的写出器
# 就是打印模型已拥有的那个判断的第二份副本。


# A synthetic fixture: one glyph square + two ports, two nodes, one pipe — enough to put
# entities on all FOUR standard layers (frame / equipment / piping / annotation tag).
# 合成夹具：一个正方形字形 + 两个端口，两个节点、一根管线 —— 足以让**四个**标准图层
#（图框 / 图元 / 管线 / 位号注释）都有实体。
static func _gpDefs() -> Array[GPSymbolDef]:
	var d := GPSymbolDef.new()
	d.gpId = "GTEST001"
	d.gpCategory = "pump"
	d.gpDisplayName = "GTEST001"
	var gpSq: Array[Vector2] = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	d.gpShapes.append(GPShape.gpPolyline(gpSq, true))
	d.gpDefaultSize = Vector2(50.0, 50.0)
	d.gpPorts.append(GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE))
	d.gpPorts.append(GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE))
	var gpOut: Array[GPSymbolDef] = [d]
	return gpOut


static func _gpSheet() -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpName = "DXF Sheet"
	gpSheet.gpWidthMM = 420.0
	gpSheet.gpHeightMM = 297.0
	# The graph lands ON the sheet — the projection reads the graph THROUGH it.
	# 图落在 sheet **上** —— 投影经它读图。
	gpSheet.gpGraph = _gpGraph()
	return gpSheet


static func _gpGraph() -> GPPIDGraph:
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	var gpPump: GPPIDNode = gpGraph.gpNewNode("n1", "GTEST001", "P-1001", Vector2(100.0, 80.0))
	gpGraph.gpAddNode(gpPump)
	var gpPump2: GPPIDNode = gpGraph.gpNewNode("n2", "GTEST001", "P-1002", Vector2(300.0, 200.0))
	gpGraph.gpAddNode(gpPump2)
	var gpEdge: GPPIDEdge = GPPIDEdge.new()
	gpEdge.gpInstanceId = "e1"
	gpEdge.gpFromRef = {"node_id": "n1", "port_id": "out"}
	gpEdge.gpToRef = {"node_id": "n2", "port_id": "in"}
	gpGraph.gpEdges.append(gpEdge)
	return gpGraph


static func _gpRead(gpPath: String) -> String:
	return FileAccess.get_file_as_string(gpPath)


# ---- registry path end to end / 经注册表端到端 ----

func gpTestExportThroughTheRegistryWritesReadableR12() -> void:
	var gpPath: String = "user://_gp_dxf_test.dxf"
	var gpResult: GPIOResult = GPExporterRegistry.gpExport(GPExporterRegistry.GP_DXF, gpPath,
		_gpGraph(), [], _gpSheet())
	gpCheck(gpResult.gpIsOk(), "the registry wrote the file: " + gpResult.gpToString())
	var gpStats: Dictionary = gpResult.gpPayload as Dictionary
	gpCheck(gpStats != null, "the payload is a dictionary like every other export")
	gpEq(int(gpStats.get("nodes", -1)), 2, "the status line can report the nodes")
	var gpText: String = _gpRead(gpPath)
	gpCheck(gpText.begins_with("0\nSECTION\n2\nHEADER"), "starts with a HEADER section")
	gpCheck(gpText.find("$ACADVER") >= 0 and gpText.find("AC1009") >= 0,
		"declares the R12 version")
	gpCheck(gpText.find("$EXTMIN") >= 0 and gpText.find("$EXTMAX") >= 0,
		"carries the extents so viewers zoom correctly")
	gpCheck(gpText.find("0\nTABLES") >= 0 or gpText.find("2\nTABLES") >= 0,
		"has a TABLES section")
	gpCheck(gpText.find("0\nENTITIES") >= 0 or gpText.find("2\nENTITIES") >= 0,
		"has an ENTITIES section")
	gpCheck(gpText.ends_with("0\nEOF\n"), "ends with EOF")
	# The registry path projects with the LIVE library (the node's synthetic symbol is not
	# in it), so the only guaranteed entity layer here is the frame's.
	# 注册表路径用**活动**库投影（节点的合成图元不在其中），故此处唯一保证出现的实体层是图框层。
	gpCheck(gpText.find("0\nLAYER\n2\n" + GPPrintModel.GP_LAYER_FRAME + "\n") >= 0,
		"layer table contains " + GPPrintModel.GP_LAYER_FRAME)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))


# Direct writer call with a synthetic fixture library: entities must land on ALL FOUR
# standard layers, proving the LAYER table is built from the entities, not a fixed list.
# 以合成夹具库直调写出器：实体必须落在**全部四个**标准图层上，
# 证明 LAYER 表由实体构建，而非一份固定清单。
func gpTestAllFourLayersLandInTheTable() -> void:
	var gpPath: String = "user://_gp_dxf_layers.dxf"
	var gpResult: GPIOResult = GPDxfExporter.gpExportSheet(_gpGraph(), _gpSheet(), gpPath,
		Callable(), _gpDefs())
	gpCheck(gpResult.gpIsOk(), "the direct export wrote the file: " + gpResult.gpToString())
	gpEq(int((gpResult.gpPayload as Dictionary).get("edges", -1)), 1,
		"the payload can report the edge")
	var gpText: String = _gpRead(gpPath)
	for gpLayer in [GPPrintModel.GP_LAYER_FRAME, GPPrintModel.GP_LAYER_PIPING,
			GPPrintModel.GP_LAYER_EQUIPMENT, GPPrintModel.GP_LAYER_ANNOTATION]:
		gpCheck(gpText.find("0\nLAYER\n2\n" + gpLayer + "\n") >= 0,
			"layer table contains " + gpLayer)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))


func gpTestFrameIsFlippedIntoYUp() -> void:
	# The flip is pinned at FUNCTION level: a sheet-symmetric fixture leaves the coordinate
	# SET unchanged (the reverse-verification once ran GREEN on an injected no-flip for
	# exactly that reason), so only this direct assertion catches the arithmetic.
	# 翻转在**函数级**被钉：相对图纸对称的夹具不改变坐标**集合**
	#（反向验证曾因这个原因在注入「不翻转」时跑绿），故只有这条直接断言能抓住该算术。
	gpCheck(GPDxfExporter.gpFlipY(Vector2(10.0, 20.0), 297.0).is_equal_approx(Vector2(10.0, 277.0)),
		"y' = H - y, x untouched")
	# And the writer still emits the flipped frame corner end to end.
	# 且写出器端到端仍输出翻转后的图框角。
	var gpPath: String = "user://_gp_dxf_flip.dxf"
	gpCheck(GPExporterRegistry.gpExport(GPExporterRegistry.GP_DXF, gpPath, _gpGraph(), [],
		_gpSheet()).gpIsOk(), "the export succeeded")
	var gpText: String = _gpRead(gpPath)
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(_gpSheet())
	var gpWantY: float = 297.0 - gpFrame.position.y
	gpCheck(gpText.find(_gpNumLine(gpFrame.position.x, gpWantY)) >= 0,
		"the frame's flipped top-left corner appears as a coordinate pair")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))


# The exact "10\nx\n20\ny\n" pair a DXF coordinate occupies.
# 一个 DXF 坐标占据的确切「10\nx\n20\ny\n」对。
static func _gpNumLine(gpX: float, gpY: float) -> String:
	return "10\n%.4f\n20\n%.4f\n" % [gpX, gpY]


func gpTestNonAsciiBecomesUnicodeEscapes() -> void:
	var gpText: String = GPDxfExporter.gpDxfText("解毒P-101")
	gpCheck(gpText.find("\\U+89E3") >= 0 and gpText.find("\\U+6BD2") >= 0,
		"each CJK char becomes its \\U+XXXX escape")
	gpCheck(gpText.ends_with("P-101"), "ASCII passes through untouched")


func gpTestCentredTextUsesTheAlignmentPoint() -> void:
	# A zone label projects centred; its DXF TEXT must carry 72=1 and an 11-point.
	# 分区标号以居中投影；其 DXF TEXT 必须带 72=1 与 11 对齐点。
	var gpSheet := _gpSheet()
	var gpDefs: Array[GPSymbolDef] = []
	var gpEntities: Array[Dictionary] = GPPrintModel.gpProject(gpSheet, gpDefs)
	var gpCentred: Dictionary = {}
	for gpE in gpEntities:
		if str(gpE["op"]) == GPPrintModel.GP_OP_TEXT and str(gpE["align"]) == "c":
			gpCentred = gpE
			break
	gpCheck(not gpCentred.is_empty(), "the bare sheet has a centred zone label")
	var gpText: String = GPDxfExporter.gpWriteDxf([gpCentred], gpSheet)
	gpCheck(gpText.find("72\n1") >= 0, "centred text declares horizontal alignment 1")
	gpCheck(gpText.find("11\n") >= 0, "centred text carries the alignment point")


# ---- refusals / 拒绝 ----

func gpTestWithoutASheetIsRefused() -> void:
	var gpResult: GPIOResult = GPExporterRegistry.gpExport(GPExporterRegistry.GP_DXF,
		"user://_gp_dxf_nosheet.dxf", _gpGraph(), [], null)
	gpCheck(not gpResult.gpIsOk(), "DXF cannot project without a sheet")
	gpCheck(gpResult.gpFailedWith("dxf.no_sheet"), "and says which prerequisite is missing")


func gpTestEmptyPathIsRefused() -> void:
	gpCheck(not GPExporterRegistry.gpExport(GPExporterRegistry.GP_DXF, "", _gpGraph(), [],
		_gpSheet()).gpIsOk(), "no path means no export")


func gpTestFinishNameAppendsDxfOnce() -> void:
	gpEq(GPExporterRegistry.gpFinishName("/a/W6", "dxf"), "/a/W6.dxf",
		"a bare name gains the extension once")
	gpEq(GPExporterRegistry.gpFinishName("/a/W6.dxf", "dxf"), "/a/W6.dxf",
		"a complete name is untouched")
