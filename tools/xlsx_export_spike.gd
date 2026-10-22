extends SceneTree
# P3 visual spike: bind four generated templates, export four files, print paths.
# P3 可视化探针：绑定四套生成模板，导出四个文件并打印路径。

const BASE := "/Users/macbook/DSH/Godot-PID/过程文件/xlsx_p3"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(BASE + "/templates")
	DirAccess.make_dir_recursive_absolute(BASE + "/output")
	var line_tpl := _build_line_template()
	var equip_tpl := _build_equipment_template()
	var valve_tpl := _build_valve_template()
	var inst_tpl := _build_instrument_template()
	var sheet := _sheet()
	var defs := GPSymbolLibrary.gpDefaultDefs()
	var opts := {
		"lists": ["line", "equipment", "instrument", "valve"],
		"templates": {"line": line_tpl, "equipment": equip_tpl,
			"instrument": inst_tpl, "valve": valve_tpl},
		"output_dir": BASE + "/output",
		"name_prefix": "W6",
		"locale": "zh",
		"include_empty": true,
		"type_labels": {"DPUMP001": "离心泵", "DTANK001": "储罐", "DHEAT001": "换热器",
			"DVALVE002": "球阀", "DINSTRUMENT001": "压力变送器"},
	}
	var res: GPIOResult = GPXlsxExport.gpExportLists([sheet], defs, opts)
	print("OK=", res.gpIsOk(), " CODE=", res.gpCode, " DETAIL=", res.gpDetail)
	if res.gpIsOk():
		for f in (res.gpPayload as Dictionary)["files"]:
			print("FILE ", f["list"], " ok=", f["ok"], " rows=", f["rows"], " path=", f["path"])
	quit(0)

func _node(id: String, def: String, tag: String, pos: Vector2) -> GPPIDNode:
	var n := GPPIDNode.new()
	n.gpInstanceId = id
	n.gpSymbolId = def
	n.gpTag = tag
	n.gpPosition = pos
	return n

func _ref(node: String, port: String, point: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"sheet_id": "s1", "node_id": node, "port_id": port,
		"point": point, "dir": Vector2.RIGHT, "is_dangling": false}

func _sheet() -> GPSheet:
	var s := GPSheet.new()
	s.gpId = "s1"
	s.gpName = "P&ID 1"
	s.gpIndex = 0
	s.gpLabelMode = GPSheet.GP_LABEL_ZH
	s.gpTitleBlock = GPSheet.gpDefaultTitleBlock()
	s.gpTitleBlock["project"]["value"] = {"zh": "W6 煤制氢项目", "en": "W6"}
	s.gpTitleBlock["drawing_no"]["value"] = {"zh": "W6-1001", "en": "W6-1001"}
	s.gpTitleBlock["rev"]["value"] = {"zh": "A", "en": "A"}
	s.gpTitleBlock["company"]["value"] = {"zh": "G-PID", "en": "G-PID"}
	var g := GPPIDGraph.new()
	s.gpGraph = g
	var pump := _node("p1", "DPUMP001", "P-101", Vector2(100, 100))
	var tank := _node("t1", "DTANK001", "T-201", Vector2(520, 100))
	var valve := _node("v1", "DVALVE002", "V-301", Vector2(300, 100))
	var inst := _node("i1", "DINSTRUMENT001", "PT-1001", Vector2(180, 220))
	g.gpAddNode(pump)
	g.gpAddNode(tank)
	g.gpAddNode(valve)
	g.gpAddNode(inst)
	g.gpAddEdge(g.gpNewEdgeEx("e1", _ref("p1", "out", Vector2(150, 100)),
		_ref("v1", "in", Vector2(280, 100)), GPPIDEdge.GP_PROCESS, "", "L-1",
		{"dn": "DN80", "spec": "A1A", "medium": "矿浆", "insulation": "50"}))
	g.gpAddEdge(g.gpNewEdgeEx("e2", _ref("v1", "out", Vector2(320, 100)),
		_ref("t1", "top", Vector2(520, 60)), GPPIDEdge.GP_PROCESS, "", "L-1",
		{"dn": "DN80", "spec": "A1A", "medium": "矿浆", "insulation": "50"}))
	g.gpAddEdge(g.gpNewEdgeEx("e3", _ref("i1", "sig", Vector2(180, 200)),
		_ref("p1", "sig", Vector2(120, 140)), GPPIDEdge.GP_SIGNAL, "ELECTRIC", "",
		{}))
	return s

func _build_line_template() -> String:
	var p := BASE + "/templates/line.xlsx"
	var rows := [
		["{{project.name}}", "", "", "", ""],
		["序号", "管线号", "介质", "长度(m)", "阀门"],
		["", "", "", "", ""],
		["编制：{{project.company}}", "审核：", "批准：", "", ""],
	]
	GPXlsxBuilder.gpBuildToPath(p, [{"name": "管线一览表", "rows": rows,
		"header_rows": 2, "widths": [8.0, 16.0, 14.0, 12.0, 16.0],
		"freeze_rows": 2, "merges": ["A1:E1", "A4:C4"], "auto_filter": "A2:E2", "landscape": true}])
	return p

func _build_equipment_template() -> String:
	var p := BASE + "/templates/equipment.xlsx"
	var rows := [
		["{{project.name}}", "", "", "", "", ""],
		["序号", "位号", "名称", "类型", "数量", "材质"],
		["", "", "", "", "", ""],
		["编制：{{project.company}}", "审核：", "批准：", "", "", ""],
	]
	GPXlsxBuilder.gpBuildToPath(p, [{"name": "设备一览表", "rows": rows,
		"header_rows": 2, "widths": [8.0, 14.0, 20.0, 16.0, 8.0, 14.0],
		"freeze_rows": 2, "merges": ["A1:F1", "A4:C4"], "auto_filter": "A2:F2", "landscape": true}])
	return p

func _build_valve_template() -> String:
	var p := BASE + "/templates/valve.xlsx"
	var rows := [
		["{{project.name}}", "", "", "", "", "", ""],
		["序号", "位号", "类型", "管线号", "公称尺寸", "压力等级", "材质"],
		["", "", "", "", "", "", ""],
		["编制：{{project.company}}", "审核：", "批准：", "", "", "", ""],
	]
	GPXlsxBuilder.gpBuildToPath(p, [{"name": "阀门一览表", "rows": rows,
		"header_rows": 2, "widths": [8.0, 14.0, 16.0, 14.0, 12.0, 12.0, 14.0],
		"freeze_rows": 2, "merges": ["A1:G1", "A4:C4"], "auto_filter": "A2:G2", "landscape": true}])
	return p

func _build_instrument_template() -> String:
	var p := BASE + "/templates/instrument.xlsx"
	var rows := [
		["{{project.name}}", "", "", "", "", "", ""],
		["序号", "位号", "类型", "回路号", "信号类型", "连接管线", "连接设备"],
		["", "", "", "", "", "", ""],
		["编制：{{project.company}}", "审核：", "批准：", "", "", "", ""],
	]
	GPXlsxBuilder.gpBuildToPath(p, [{"name": "仪表索引表", "rows": rows,
		"header_rows": 2, "widths": [8.0, 14.0, 16.0, 12.0, 12.0, 14.0, 24.0],
		"freeze_rows": 2, "merges": ["A1:G1", "A4:C4"], "auto_filter": "A2:G2", "landscape": true}])
	return p
