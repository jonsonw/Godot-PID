extends Node
# P5 visual acceptance: load the real main scene, add a small P&ID, open the export dialog,
# capture it, run an export through the dialog, and capture the result table.
# P5 可视化验收：加载真实主场景、加一张小 P&ID、打开导出对话框、截图、经对话框导出、再截图结果表。
const OUT := "/Users/macbook/DSH/Godot-PID/过程文件/xlsx_p5"
var _main: Control = null
var _dlg: Window = null
var _prefs_before: Dictionary = {}
var _had_prefs: bool = false

func _ready() -> void:
	_had_prefs = FileAccess.file_exists("user://deliverable_export.cfg")
	_prefs_before = GPDeliverablePrefs.gpLoad()
	DirAccess.make_dir_recursive_absolute(OUT + "/output")
	var scene := load("res://scenes/main.tscn") as PackedScene
	_main = scene.instantiate() as Control
	# The preview scene's own _ready is still setting up children; deferred add avoids
	# "Parent node is busy setting up children".
	# 预览场景自己的 _ready 还在搭建子节点；延迟 add 避免「父节点正忙」。
	get_tree().root.add_child.call_deferred(_main)
	await _wait(20)
	_seed_graph()
	await _wait(4)
	_main.gpMenuCoord.gpOpenExportLists()
	await _wait(10)
	_dlg = _find_dialog(get_tree().root)
	if _dlg == null:
		print("NO_DIALOG")
		get_tree().quit(1)
		return
	await _capture(OUT + "/dialog_initial.png")
	_dlg.gpOutputEdit.text = OUT + "/output"
	_dlg.gpPrefixEdit.text = "W6"
	_dlg._gpOnExport()
	await _wait(8)
	await _capture(OUT + "/dialog_result.png")
	# Do not leave the test output folder/prefix in the user's real preferences.
	# 不要把测试输出目录/前缀留在用户真实偏好里。
	if _had_prefs:
		GPDeliverablePrefs.gpSaveTo("user://deliverable_export.cfg",
			str(_prefs_before.get("output_dir", "")),
			str(_prefs_before.get("name_prefix", "G-PID")),
			_prefs_before.get("templates", {}) as Dictionary)
	else:
		GPDeliverablePrefs.gpClear()
	print("CAPTURED")
	get_tree().quit(0)

func _wait(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("SAVE ", path, " err=", img.save_png(path), " size=", img.get_size())

func _find_dialog(node: Node) -> Window:
	if node is GPExportListsDialog:
		return node as Window
	for c in node.get_children():
		var f := _find_dialog(c)
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
	sheet.gpTitleBlock["drawing_no"]["value"] = {"zh": "W6-1001", "en": "W6-1001"}
	sheet.gpTitleBlock["rev"]["value"] = {"zh": "A", "en": "A"}
	sheet.gpTitleBlock["company"]["value"] = {"zh": "G-PID", "en": "G-PID"}
	var g: GPPIDGraph = sheet.gpGraph
	var pump := _node("p1", "DPUMP001", "P-101", Vector2(160, 180))
	var tank := _node("t1", "DTANK001", "T-201", Vector2(620, 180))
	var valve := _node("v1", "DVALVE002", "V-301", Vector2(380, 180))
	var inst := _node("i1", "DINSTRUMENT001", "PT-1001", Vector2(260, 330))
	g.gpAddNode(pump)
	g.gpAddNode(tank)
	g.gpAddNode(valve)
	g.gpAddNode(inst)
	g.gpAddEdge(g.gpNewEdgeEx("e1", _ref("p1", "out", Vector2(210, 180)),
		_ref("v1", "in", Vector2(360, 180)), GPPIDEdge.GP_PROCESS, "", "L-1",
		{"dn": "DN80", "spec": "A1A", "medium": "矿浆", "insulation": "50"}))
	g.gpAddEdge(g.gpNewEdgeEx("e2", _ref("v1", "out", Vector2(400, 180)),
		_ref("t1", "top", Vector2(620, 140)), GPPIDEdge.GP_PROCESS, "", "L-1",
		{"dn": "DN80", "spec": "A1A", "medium": "矿浆", "insulation": "50"}))
	g.gpAddEdge(g.gpNewEdgeEx("e3", _ref("i1", "sig", Vector2(260, 310)),
		_ref("p1", "sig", Vector2(180, 220)), GPPIDEdge.GP_SIGNAL, "ELECTRIC", "", {}))
