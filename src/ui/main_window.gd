extends Control

# Main scene entry: builds the "left symbol palette + right toolbar/canvas" layout.
# 主场景入口：搭建「左侧符号库 + 右侧工具栏/画布」布局。
# Holds the PIDGraph (data core) and SymbolLibrary (symbol set), wiring palette buttons to the canvas.
# 持有 PIDGraph（数据内核）与 SymbolLibrary（符号集），把调色板按钮接到画布。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpGraph: GPPIDGraph
var gpCanvas: GPCanvas2D
var gpDefs: Array[GPSymbolDef] = []
var gpModeBtn: Button


func _ready() -> void:
	gpGraph = GPPIDGraph.new()
	gpDefs = GPSymbolLibrary.gpDefaultDefs()

	var gpHbox: HBoxContainer = HBoxContainer.new()
	gpHbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(gpHbox)

	# ---------------- left: symbol library ----------------
	# ---------------- 左侧：符号库 ----------------
	var gpLeft: VBoxContainer = VBoxContainer.new()
	gpLeft.custom_minimum_size = Vector2(190, 0)
	gpHbox.add_child(gpLeft)

	var gpTitle: Label = Label.new()
	gpTitle.text = "符号库 Symbol Library"
	gpLeft.add_child(gpTitle)

	for gpD in gpDefs:
		var gpB: Button = Button.new()
		gpB.text = "%s · %s" % [gpD.gpDisplayName, gpD.gpCategory]
		gpB.pressed.connect(_gpOnPick.bind(gpD))
		gpLeft.add_child(gpB)

	var gpSpacer: Control = Control.new()
	gpSpacer.size_flags_vertical = SIZE_EXPAND_FILL
	gpLeft.add_child(gpSpacer)

	var gpNote: Label = Label.new()
	gpNote.text = "选符号 → 点画布放置"
	gpLeft.add_child(gpNote)

	# ---------------- right: toolbar + canvas ----------------
	# ---------------- 右侧：工具栏 + 画布 ----------------
	var gpRight: VBoxContainer = VBoxContainer.new()
	gpRight.size_flags_horizontal = SIZE_EXPAND_FILL
	gpHbox.add_child(gpRight)

	var gpToolbar: HBoxContainer = HBoxContainer.new()
	gpRight.add_child(gpToolbar)

	gpModeBtn = Button.new()
	gpModeBtn.text = "模式：选择"
	gpToolbar.add_child(gpModeBtn)
	gpModeBtn.pressed.connect(_gpToggleMode)

	var gpClearBtn: Button = Button.new()
	gpClearBtn.text = "清空画布"
	gpToolbar.add_child(gpClearBtn)
	gpClearBtn.pressed.connect(_gpOnClear)

	var gpHint: Label = Label.new()
	gpHint.text = "滚轮缩放 · 中键拖拽平移 · 选符号后点画布放置 · 连接模式依次点两个符号"
	gpHint.size_flags_horizontal = SIZE_EXPAND_FILL
	gpToolbar.add_child(gpHint)

	gpCanvas = GPCanvas2D.new()
	gpCanvas.size_flags_vertical = SIZE_EXPAND_FILL
	gpCanvas.size_flags_horizontal = SIZE_EXPAND_FILL
	gpCanvas.gpGraph = gpGraph
	gpCanvas.gpDefs = gpDefs
	gpCanvas.gpGraphChanged.connect(_gpOnGraphChanged)
	gpRight.add_child(gpCanvas)


func _gpOnPick(gpD: GPSymbolDef) -> void:
	gpCanvas.gpPendingDef = gpD
	gpCanvas.gpMode = GPCanvas2D.GPMode.GP_SELECT
	gpCanvas.gpConnectFrom = ""


func _gpToggleMode() -> void:
	if gpCanvas.gpMode == GPCanvas2D.GPMode.GP_SELECT:
		gpCanvas.gpMode = GPCanvas2D.GPMode.GP_CONNECT
		gpModeBtn.text = "模式：连接"
	else:
		gpCanvas.gpMode = GPCanvas2D.GPMode.GP_SELECT
		gpModeBtn.text = "模式：选择"
		gpCanvas.gpConnectFrom = ""


func _gpOnClear() -> void:
	gpGraph.gpNodes.clear()
	gpGraph.gpEdges.clear()
	gpCanvas.gpNextId = 1
	gpCanvas.gpSelectedId = ""
	gpCanvas.gpConnectFrom = ""
	gpCanvas.gpPendingDef = null
	gpCanvas.queue_redraw()


func _gpOnGraphChanged() -> void:
	pass
