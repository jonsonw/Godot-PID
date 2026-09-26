class_name GPPortEditorPanel
extends PanelContainer
# Copyright © 2026 Jonson Wang
# The port (connection point) editing panel of the "make symbol" dialog: name, direction and
# delete for the port currently selected on the glyph editor.
# 「制作图元」对话框中的端点（连接点）编辑面板：对当前在图形编辑器中选中的端点做改名、改朝向与删除。
#
# It owns its own widgets and the direction table, and talks to GPSymbolEditor directly. The
# dialog keeps only a pointer to it and calls gpSync() whenever the editor reports a change.
# 本类持有自己的控件与朝向表，并直接与 GPSymbolEditor 对话。对话框只保留它的引用，
# 并在编辑器报告变更时调用 gpSync()。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Direction choices offered by the dropdown, in the same order as its items:
# none / left / right / up / down.
# 下拉框提供的朝向选项，顺序与其条目一致：无 / 左 / 右 / 上 / 下。
const GP_DIRS: Array[Vector2] = [Vector2.ZERO, Vector2(-1.0, 0.0), Vector2(1.0, 0.0),
	Vector2(0.0, -1.0), Vector2(0.0, 1.0)]

# The glyph editor whose ports are edited. / 被编辑端点的图形编辑器。
var gpEditor: GPSymbolEditor = null

var _gpPortName: LineEdit = null
var _gpPortDir: OptionButton = null
var _gpDelPort: Button = null
var _gpPortHint: Label = null


# Build the widgets. Call once, right after the editor is known.
# 构建控件。仅在编辑器已知之后调用一次。
func gpBuild(gpEd: GPSymbolEditor) -> void:
	gpEditor = gpEd
	var gpBox: VBoxContainer = VBoxContainer.new()
	gpBox.add_theme_constant_override("separation", 4)
	var gpTitle: Label = Label.new()
	gpTitle.text = I18n.gpTr("make_symbol.ports")
	gpTitle.add_theme_font_size_override("font_size", 14)
	gpBox.add_child(gpTitle)

	# Name row / 名称行
	var gpNameRow: HBoxContainer = HBoxContainer.new()
	gpNameRow.add_theme_constant_override("separation", 6)
	var gpNameL: Label = Label.new()
	gpNameL.text = I18n.gpTr("make_symbol.port_name") + ":"
	gpNameL.custom_minimum_size = Vector2(90.0, 0.0)
	gpNameRow.add_child(gpNameL)
	_gpPortName = LineEdit.new()
	_gpPortName.editable = false
	_gpPortName.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gpPortName.text_changed.connect(func(gpT: String) -> void: _gpOnPortName(gpT))
	gpNameRow.add_child(_gpPortName)
	gpBox.add_child(gpNameRow)

	# Direction row / 朝向行
	var gpDirRow: HBoxContainer = HBoxContainer.new()
	gpDirRow.add_theme_constant_override("separation", 6)
	var gpDirL: Label = Label.new()
	gpDirL.text = I18n.gpTr("make_symbol.port_dir") + ":"
	gpDirL.custom_minimum_size = Vector2(90.0, 0.0)
	gpDirRow.add_child(gpDirL)
	_gpPortDir = OptionButton.new()
	_gpPortDir.add_item(I18n.gpTr("make_symbol.port_dir_none"))
	_gpPortDir.add_item(I18n.gpTr("make_symbol.port_dir_left"))
	_gpPortDir.add_item(I18n.gpTr("make_symbol.port_dir_right"))
	_gpPortDir.add_item(I18n.gpTr("make_symbol.port_dir_up"))
	_gpPortDir.add_item(I18n.gpTr("make_symbol.port_dir_down"))
	_gpPortDir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gpPortDir.item_selected.connect(func(gpI: int) -> void: _gpOnPortDir(gpI))
	gpDirRow.add_child(_gpPortDir)
	gpBox.add_child(gpDirRow)

	# Delete + hint / 删除 + 提示
	var gpDelRow: HBoxContainer = HBoxContainer.new()
	gpDelRow.add_theme_constant_override("separation", 6)
	_gpDelPort = Button.new()
	_gpDelPort.text = I18n.gpTr("make_symbol.delete_port")
	_gpDelPort.disabled = true
	_gpDelPort.pressed.connect(func() -> void: _gpDeletePort())
	gpDelRow.add_child(_gpDelPort)
	gpBox.add_child(gpDelRow)
	_gpPortHint = Label.new()
	_gpPortHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gpPortHint.custom_minimum_size = Vector2(0.0, 28.0)
	gpBox.add_child(_gpPortHint)

	add_child(gpBox)


# Reflect the editor's current port selection on the widgets. Called by the dialog whenever the
# editor reports a change (gpChanged), so no call site has to remember it.
# 把编辑器当前的端点选中反映到控件上。由对话框在编辑器报告变更（gpChanged）时调用，
# 故各调用点无需各自记得同步。
func gpSync() -> void:
	if _gpPortName == null or gpEditor == null:
		return
	if gpEditor.gpSelPort >= 0 and gpEditor.gpSelPort < gpEditor.gpPorts.size():
		var gpP: GPPort = gpEditor.gpPorts[gpEditor.gpSelPort]
		_gpPortName.text = gpP.gpName
		_gpPortName.editable = true
		_gpPortDir.selected = gpDirIndex(gpP.gpDir)
		_gpDelPort.disabled = false
		_gpPortHint.text = I18n.gpTr("make_symbol.port_selected")
	else:
		_gpPortName.text = ""
		_gpPortName.editable = false
		_gpPortDir.selected = 0
		_gpDelPort.disabled = true
		_gpPortHint.text = I18n.gpTr("make_symbol.no_port_selected")


# Dropdown index for a direction vector; 0 ("none") when it matches nothing.
# 方向向量对应的下拉框下标；无匹配时返回 0（「无」）。
static func gpDirIndex(gpDir: Vector2) -> int:
	for gpI in range(GP_DIRS.size()):
		if GP_DIRS[gpI].is_equal_approx(gpDir):
			return gpI
	return 0


func _gpOnPortName(gpT: String) -> void:
	if gpEditor == null:
		return
	gpEditor.gpSetPortName(gpT)


func _gpOnPortDir(gpI: int) -> void:
	if gpEditor == null:
		return
	if gpI < 0 or gpI >= GP_DIRS.size():
		return
	gpEditor.gpSetPortDir(GP_DIRS[gpI])


func _gpDeletePort() -> void:
	if gpEditor == null:
		return
	gpEditor.gpDeleteSelectedPort()
