extends Node
# P6 visual acceptance: load main, seed the same P&ID, open the import dialog on a real
# edited workbook, capture preview, apply, capture applied state, and print the resulting props.
# P6 可视化验收：加载主场景、铺同一张 P&ID、在真实改过的 xlsx 上打开导入对话框、
# 截预览、应用、截应用后状态，并打印结果属性。
const OUT := "/Users/macbook/DSH/Godot-PID/过程文件/xlsx_p6"
const FILE := "/Users/macbook/DSH/Godot-PID/过程文件/xlsx_p6/import_equipment.xlsx"
var _main: Control = null
var _dlg: Window = null

func _ready() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	_main = scene.instantiate() as Control
	get_tree().root.add_child.call_deferred(_main)
	await _wait(20)
	_seed_graph()
	await _wait(4)
	_main.gpMenuCoord.gpOpenImportLists()
	await _wait(10)
	_dlg = _find(get_tree().root)
	if _dlg == null:
		print("NO_DIALOG")
		get_tree().quit(1)
		return
	_dlg.gpSetFilePath(FILE)
	_dlg.gpReadPreview()
	await _wait(6)
	await _capture(OUT + "/import_preview.png")
	print("CHANGES ", _dlg.gpChanges.size(), " ISSUES ", _dlg.gpIssues.size())
	_dlg.gpApplyPreview()
	await _wait(6)
	await _capture(OUT + "/import_applied.png")
	var pump: GPPIDNode = _main.gpCenter.gpActiveSheet().gpGraph.gpGetNode("p1")
	print("AFTER name=", pump.gpNames.get("zh", ""), " material=", pump.gpProps.get("material", ""),
		" dp=", pump.gpProps.get("design_pressure", ""), " dt_has=", pump.gpProps.has("design_temp"),
		" remark_has=", pump.gpProps.has("remark"))
	get_tree().quit(0)

func _wait(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("SAVE ", path, " err=", img.save_png(path), " size=", img.get_size())

func _find(node: Node) -> Window:
	if node is GPImportListsDialog:
		return node as Window
	for c in node.get_children():
		var f := _find(c)
		if f != null:
			return f
	return null

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

func _seed_graph() -> void:
	var sheet: GPSheet = _main.gpCenter.gpActiveSheet()
	if sheet == null:
		return
	if sheet.gpGraph == null:
		sheet.gpGraph = GPPIDGraph.new()
	sheet.gpTitleBlock = GPSheet.gpDefaultTitleBlock()
	sheet.gpTitleBlock["project"]["value"] = {"zh": "W6 煤制氢项目", "en": "W6"}
	var g: GPPIDGraph = sheet.gpGraph
	var pump := _node("p1", "DPUMP001", "P-101", Vector2(160, 180))
	pump.gpNames["zh"] = "离心泵"
	pump.gpProps["design_temp"] = 120.0
	pump.gpProps["remark"] = "原备注"
	pump.gpProps["design_pressure"] = 1.6
	var tank := _node("t1", "DTANK001", "T-201", Vector2(620, 180))
	var valve := _node("v1", "DVALVE002", "V-301", Vector2(380, 180))
	g.gpAddNode(pump)
	g.gpAddNode(tank)
	g.gpAddNode(valve)
	g.gpAddEdge(g.gpNewEdgeEx("e1", _ref("p1", "out", Vector2(210, 180)),
		_ref("v1", "in", Vector2(360, 180)), GPPIDEdge.GP_PROCESS, "", "L-1",
		{"dn": "DN80", "spec": "A1A", "medium": "矿浆", "insulation": "50"}))
	g.gpAddEdge(g.gpNewEdgeEx("e2", _ref("v1", "out", Vector2(400, 180)),
		_ref("t1", "top", Vector2(620, 140)), GPPIDEdge.GP_PROCESS, "", "L-1",
		{"dn": "DN80", "spec": "A1A", "medium": "矿浆", "insulation": "50"}))
