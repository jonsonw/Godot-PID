extends SceneTree
# P3 visual spike: bind four generated templates, export four files, print paths.
# P3 可视化探针：绑定四套生成模板，导出四个文件并打印路径。

const BASE := "/Users/macbook/DSH/Godot-PID/过程文件/xlsx_p4"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(BASE + "/output")
	var sheet := _sheet()
	var defs := GPSymbolLibrary.gpDefaultDefs()
	var opts := {
		"lists": ["line", "equipment", "instrument", "valve"],
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

