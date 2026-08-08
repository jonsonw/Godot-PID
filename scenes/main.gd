extends Control

## 主场景入口：搭建「左侧符号库 + 右侧工具栏/画布」布局。
## 持有 PIDGraph（数据内核）与 SymbolLibrary（符号集），把调色板按钮接到画布。
## 编码规范：所有变量均显式声明类型。

var graph: PIDGraph
var canvas: PIDCanvas
var defs: Array[SymbolDef] = []
var mode_btn: Button


func _ready() -> void:
	graph = PIDGraph.new()
	defs = SymbolLibrary.default_defs()

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hbox)

	# ---------------- 左侧：符号库 ----------------
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(190, 0)
	hbox.add_child(left)

	var title: Label = Label.new()
	title.text = "符号库 Symbol Library"
	left.add_child(title)

	for d in defs:
		var b: Button = Button.new()
		b.text = "%s · %s" % [d.display_name, d.category]
		b.pressed.connect(_on_pick.bind(d))
		left.add_child(b)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(spacer)

	var note: Label = Label.new()
	note.text = "选符号 → 点画布放置"
	left.add_child(note)

	# ---------------- 右侧：工具栏 + 画布 ----------------
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.add_child(right)

	var toolbar: HBoxContainer = HBoxContainer.new()
	right.add_child(toolbar)

	mode_btn = Button.new()
	mode_btn.text = "模式：选择"
	toolbar.add_child(mode_btn)
	mode_btn.pressed.connect(_toggle_mode)

	var clear_btn: Button = Button.new()
	clear_btn.text = "清空画布"
	toolbar.add_child(clear_btn)
	clear_btn.pressed.connect(_on_clear)

	var hint: Label = Label.new()
	hint.text = "滚轮缩放 · 中键拖拽平移 · 选符号后点画布放置 · 连接模式依次点两个符号"
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	toolbar.add_child(hint)

	canvas = PIDCanvas.new()
	canvas.size_flags_vertical = SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = SIZE_EXPAND_FILL
	canvas.graph = graph
	canvas.defs = defs
	canvas.graph_changed.connect(_on_graph_changed)
	right.add_child(canvas)


func _on_pick(d: SymbolDef) -> void:
	canvas.pending_def = d
	canvas.mode = PIDCanvas.Mode.SELECT
	canvas.connect_from = ""


func _toggle_mode() -> void:
	if canvas.mode == PIDCanvas.Mode.SELECT:
		canvas.mode = PIDCanvas.Mode.CONNECT
		mode_btn.text = "模式：连接"
	else:
		canvas.mode = PIDCanvas.Mode.SELECT
		mode_btn.text = "模式：选择"
		canvas.connect_from = ""


func _on_clear() -> void:
	graph.nodes.clear()
	graph.edges.clear()
	canvas.next_id = 1
	canvas.selected_id = ""
	canvas.connect_from = ""
	canvas.pending_def = null
	canvas.queue_redraw()


func _on_graph_changed() -> void:
	pass
