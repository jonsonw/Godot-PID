extends SceneTree
# Headless smoke for the §3.4 input split: GPCanvas2D._gui_input now only forwards to
# GPCanvasInputRouter, which owns panning, the tool registry and the tool dispatch.
# 架构优化 §3.4 输入拆分的无界面冒烟：GPCanvas2D._gui_input 现只转发给 GPCanvasInputRouter，
# 平移、工具注册表与工具分派都由后者持有。
#
# Why deferred / 为何用延迟调用：
#   SceneTree._initialize() runs before `root` itself is in the tree, so add_child() there does
#   NOT trigger _ready. The canvas must be built on the first idle frame instead.
#   SceneTree._initialize() 早于 root 入树，此时 add_child() 不会触发 _ready；
#   故画布要等到第一个空闲帧再构建。
#
# Run / 运行：
#   Godot --headless --path . --script res://tests/smoke_canvas_input.gd


func _initialize() -> void:
	# The canvas's script graph references the I18n / Settings autoloads as globals; under
	# `--script` they do not exist, so stand-ins are registered before anything is loaded.
	# 画布脚本图把 I18n / Settings 当全局引用；`--script` 下不存在，故先注册占位。
	Engine.register_singleton("I18n", Node.new())
	Engine.register_singleton("Settings", Node.new())
	call_deferred("_gpRun")


func _gpRun() -> void:
	var gpCls: GDScript = load("res://src/ui/canvas/canvas_2d.gd")
	var gpCv = gpCls.new()
	root.add_child(gpCv)
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("N1", "pump", "P-101", Vector2(100.0, 100.0)))
	gpG.gpAddNode(gpG.gpNewNode("N2", "valve", "V-201", Vector2(300.0, 100.0)))
	gpCv.gpGraph = gpG
	print("[smoke] in_tree=", gpCv.is_inside_tree(), " tools_built=", gpCv.gpInputRouter != null)
	# Wheel zoom / 滚轮缩放。
	var gpZ0: float = gpCv.gpViewZoom
	var gpE: InputEventMouseButton = InputEventMouseButton.new()
	gpE.button_index = MOUSE_BUTTON_WHEEL_UP
	gpE.pressed = true
	gpE.position = Vector2(10.0, 10.0)
	gpCv._gui_input(gpE)
	print("[smoke] zoom ", gpZ0, " -> ", gpCv.gpViewZoom)
	# Middle-button pan / 中键平移。
	var gpO0: Vector2 = gpCv.gpViewOffset
	var gpD: InputEventMouseButton = InputEventMouseButton.new()
	gpD.button_index = MOUSE_BUTTON_MIDDLE
	gpD.pressed = true
	gpD.position = Vector2(10.0, 10.0)
	gpCv._gui_input(gpD)
	var gpM: InputEventMouseMotion = InputEventMouseMotion.new()
	gpM.position = Vector2(40.0, 25.0)
	gpCv._gui_input(gpM)
	# A motion event only pans while the button is down; release afterwards.
	# 移动事件仅在按键按下期间平移；随后释放。
	var gpPanned: Vector2 = gpCv.gpViewOffset
	var gpU: InputEventMouseButton = InputEventMouseButton.new()
	gpU.button_index = MOUSE_BUTTON_MIDDLE
	gpU.pressed = false
	gpU.position = Vector2(40.0, 25.0)
	gpCv._gui_input(gpU)
	print("[smoke] offset ", gpO0, " -> ", gpPanned)
	# Left click on N1 -> selection / 左键点中 N1 -> 选中。
	var gpP: Vector2 = gpCv.gpScreenFromWorld(Vector2(100.0, 100.0))
	var gpL: InputEventMouseButton = InputEventMouseButton.new()
	gpL.button_index = MOUSE_BUTTON_LEFT
	gpL.pressed = true
	gpL.position = gpP
	gpCv._gui_input(gpL)
	var gpR: InputEventMouseButton = InputEventMouseButton.new()
	gpR.button_index = MOUSE_BUTTON_LEFT
	gpR.pressed = false
	gpR.position = gpP
	gpCv._gui_input(gpR)
	print("[smoke] selection=", gpCv.gpSelection, " primary=", gpCv.gpSelectedId)
	var gpOk: bool = (gpCv.gpViewZoom != gpZ0) and (gpPanned != gpO0) and (gpCv.gpSelectedId == "N1")
	print("[smoke] RESULT ", "OK" if gpOk else "FAILED")
	quit(0 if gpOk else 1)
