class_name GPMakeSymbolDialog
extends Window
# One-stop "Make Symbol" dialog (replaces the old glyph isolation editor).
#
# Flow: the P&ID canvas holds annotation GPShapes; the user selects them and asks to turn
# them into a symbol. main_window opens this dialog with the draft dict of the selected
# geometry. The dialog previews the shapes (normalized thumbnail, matching the symbol
# palette), lets the user pick a category, a name and a display name, then either
# OVERWRITES an existing user symbol whose display name matches, or CREATES a new one.
# On confirm it emits gpMadeSymbol(symbolId) so the caller can place/refresh.
#
# The dialog is an INTERACTIVE symbol editor: it previews the selected annotation geometry
# (normalized thumbnail, matching the symbol palette), lets the user pick a category, a name and a
# display name, then either OVERWRITES an existing user symbol or CREATES a new one. All geometry
# editing (ports + primitives) is DELEGATED to GPSymbolEditor (src/ui/dialogs/symbol_editor/), so
# every add / delete / move is undoable via its GPCommandStack, exactly like the main canvas. On
# confirm it emits gpMadeSymbol(symbolId) so the caller can place / refresh.
#
# 一站式「生成图元」对话框（取代旧的 glyph 隔离编辑器）。
#
# 流程：P&ID 主画布持有注释 GPShape；用户选中后要求把所选图形生成图元。main_window
# 携带所选几何的草稿字典打开本对话框。对话框以图元库同款缩略图预览图形，让用户选类别、
# 填名称与显示名称，然后「覆盖」显示名命中的已有用户图元、或「新建」一个。确认后发出
# gpMadeSymbol(symbolId)，供调用方放置 / 刷新。
#
# 在原本只读预览之上，本对话框现升级为「可交互编辑器」：
#   - 连接端点（端口）可点击添加、拖拽移动，选中后可改名 / 改朝向 / 删除。
#   - 简单图元编辑：在预览上绘制直线 / 矩形 / 圆 / 折线，或选中已有图元后移动 / 删除。
# 工作模型为两个强类型数组 _gpShapes（Array[GPShape]）与 _gpPorts（Array[GPPort]），
# 确认时统一重新序列化为保存字典。
#
# Coding rule: every variable declares an explicit type (containers included).
# 编码规范：所有变量显式声明类型（含容器类型）。

# Copyright © 2026 Jonson Wang

# Emitted when the user confirms; carries the id of the created / overwritten symbol.
# 用户在确定时发出；携带被创建 / 被覆盖图元的 id。
signal gpMadeSymbol(gpSymbolId: String)
# Emitted when the user cancels (or the dialog is closed without confirming).
# 用户在取消（或未确定而关闭）时发出。
signal gpCancelled

# Draft dict {paths, circles, rects, ...} of the selected annotation geometry.
# 所选注释几何的草稿字典 {paths, circles, rects, ...}。
var gpDraft: Dictionary = {}
# Kept for API compatibility (callers pass it), but mode selection is now governed purely
# by id uniqueness: a taken id forces Overwrite, a free id forces New (see _gpRefreshState).
# 为兼容调用方保留，但模式选择现完全由 id 唯一性治理：id 已被占用强制覆盖、空闲强制
# 新建（见 _gpRefreshState）。
var gpAllowOverwrite: bool = true
# Base display-name from the caller (e.g. the id of a symbol being edited) or "".
# 调用方给定的基础显示名（如正在编辑图元的 id），无则为空串。
var gpInitialName: String = ""
# Initial ports (normalized 0..1) carried in when EDITING an existing symbol, so the
# editor starts from the symbol's current connection points instead of an empty list.
# 编辑已有图元时带入的初始端口（归一化 0..1），使编辑器从图元当前连接点起步而非空白。
var gpInitialPorts: Array[GPPort] = []
# Initial display-name shown in the display-name field when editing an existing symbol.
# 编辑已有图元时显示名框的预填文本。
var gpInitialDisplay: String = ""

# -- geometry editor (delegated) / 几何编辑器（委托） --
# The dialog no longer owns the working model; GPSymbolEditor holds _gpShapes / _gpPorts, the active
# tool and the undo/redo history (GPCommandStack). The dialog only wires its UI to the editor.
# 对话框不再持有工作模型；GPSymbolEditor 持有 _gpShapes / _gpPorts、当前工具与撤销 / 重做历史
# （GPCommandStack）。对话框仅把 UI 接到编辑器。
var _gpEditor: GPSymbolEditor = null
# Outward-normal direction choices for a port (UI dropdown -> Vector2). / 端口可选朝向（UI 下拉 -> 向量）。
var _gpDirs: Array[Vector2] = [Vector2.ZERO, Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 1.0)]

# -- internal widgets / 内部控件 --
var _gpPreview: Control = null
var _gpCatBtn: OptionButton = null
var _gpCatKeys: Array[String] = []
var _gpNameEdit: LineEdit = null
var _gpDisplayEdit: LineEdit = null
var _gpModeNew: Button = null
var _gpModeOver: Button = null
var _gpHint: Label = null
var _gpOk: Button = null
var _gpExistingTargetId: String = ""
# editor widgets / 编辑器控件
var _gpToolBtns: Array[Button] = []
var _gpPortName: LineEdit = null
var _gpPortDir: OptionButton = null
var _gpDelPort: Button = null
var _gpPortHint: Label = null
var _gpDelShape: Button = null
var _gpShapeHint: Label = null
# (PortPanel / ShapePanel containers are returned from their builders and not retained.)

const GP_PREVIEW_SIZE: Vector2 = Vector2(260.0, 200.0)


# Open the dialog (static convenience): add it as an embedded child of gpOwner and show.
# 打开对话框（静态便捷方法）：作为 gpOwner 的嵌入子窗口添加并显示。
static func gpOpen(gpOwner: Window, gpDraft: Dictionary, gpInitialName: String = "", gpAllowOverwrite: bool = true, gpInitialPorts: Array[GPPort] = [], gpInitialDisplay: String = "") -> GPMakeSymbolDialog:
	var gpDlg: GPMakeSymbolDialog = GPMakeSymbolDialog.new()
	gpDlg.gpDraft = gpDraft.duplicate(true)
	gpDlg.gpInitialName = gpInitialName
	gpDlg.gpAllowOverwrite = gpAllowOverwrite
	gpDlg.gpInitialPorts = gpInitialPorts
	gpDlg.gpInitialDisplay = gpInitialDisplay
	gpOwner.add_child(gpDlg)
	gpDlg._gpBuild()
	gpDlg.popup_centered(Vector2i(560, 720))
	return gpDlg


func _ready() -> void:
	title = I18n.gpTr("make_symbol.title")
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_PRIMARY_SCREEN
	exclusive = true


# Build the dialog body: preview + editor toolbar + category + name/display + ports panel +
# shapes panel + new/overwrite + actions.
# 构建对话框主体：预览 + 编辑工具条 + 类别 + 名称/显示名 + 端点面板 + 几何面板 + 新建/覆盖 + 操作按钮。
func _gpBuild() -> void:
	# Geometry editing is delegated to GPSymbolEditor: own the editor, wire its change / tool
	# signals to the UI, then build the rest of the dialog around it.
	# 几何编辑委托给 GPSymbolEditor：持有编辑器、把变更 / 工具信号接到 UI，再围绕它搭建其余对话框。
	_gpEditor = GPSymbolEditor.new()
	_gpEditor.gpChanged.connect(_gpOnEditorChanged)
	_gpEditor.gpToolChanged.connect(_gpOnToolChanged)
	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.name = "Root"
	gpRoot.add_theme_constant_override("separation", 8)
	gpRoot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(gpRoot)

	# Scrollable body: the editor panels (preview + ports + shapes + mode) exceed the
	# window height, which pushed the action row out of the window — the OK/Cancel
	# buttons became invisible and unreachable. The body scrolls; the action row below
	# is OUTSIDE the scroll area and stays visible at every window size.
	# 可滚动主体：编辑面板（预览 + 端点 + 图元 + 模式）总高超过窗口，把操作行挤出窗口外
	# —— 确定/取消不可见也不可达。主体滚动；下方的操作行在滚动区之外，任何窗口尺寸下恒可见。
	var gpScroll: ScrollContainer = ScrollContainer.new()
	gpScroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpScroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gpRoot.add_child(gpScroll)
	var gpBody: VBoxContainer = VBoxContainer.new()
	gpBody.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBody.add_theme_constant_override("separation", 8)
	gpScroll.add_child(gpBody)

	# Preview panel / 预览面板
	var gpPanel: PanelContainer = PanelContainer.new()
	gpPanel.custom_minimum_size = GP_PREVIEW_SIZE
	gpPanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBody.add_child(gpPanel)

	_gpPreview = _gpNewPreview()
	gpPanel.add_child(_gpPreview)

	# Editor toolbar / 编辑工具条
	gpBody.add_child(_gpNewToolRow())

	# Short usage tip / 简短操作提示
	var gpTip: Label = Label.new()
	gpTip.text = I18n.gpTr("make_symbol.editor_tip")
	gpTip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpTip.add_theme_color_override("font_color", Color(0.7, 0.73, 0.8))
	gpTip.custom_minimum_size = Vector2(0.0, 44.0)
	gpBody.add_child(gpTip)

	# Category dropdown / 类别下拉
	var gpCatRow: HBoxContainer = HBoxContainer.new()
	gpCatRow.add_theme_constant_override("separation", 6)
	var gpCatLabel: Label = Label.new()
	gpCatLabel.text = I18n.gpTr("make_symbol.category") + ":"
	gpCatLabel.custom_minimum_size = Vector2(110.0, 0.0)
	gpCatRow.add_child(gpCatLabel)
	_gpCatKeys = GPSymbolCategories.gpCategoryList()
	_gpCatBtn = OptionButton.new()
	for gpC in _gpCatKeys:
		_gpCatBtn.add_item(I18n.gpTr(gpC))
	_gpCatBtn.selected = _gpCatKeys.find("general") if _gpCatKeys.find("general") >= 0 else 0
	_gpCatBtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpCatRow.add_child(_gpCatBtn)
	gpBody.add_child(gpCatRow)

	# Internal name (id source) + display name / 内部名称（id 来源）+ 显示名
	_gpNameEdit = _gpNewLabeledEdit(gpBody, I18n.gpTr("make_symbol.name"), gpInitialName)
	_gpDisplayEdit = _gpNewLabeledEdit(gpBody, I18n.gpTr("make_symbol.display_name"), gpInitialDisplay)

	# Port panel / 端点面板
	gpBody.add_child(_gpNewPortPanel())
	# Shape panel / 图元几何面板
	gpBody.add_child(_gpNewShapePanel())

	# New vs Overwrite — a radio group: exactly ONE button is pressed at any time. Without
	# the group, clicking one left the other pressed (both looked active) or unpressed the
	# clicked one again, so the mode appeared to "do nothing".
	# 新建 与 覆盖 —— 单选组：任意时刻恰有一个按下。若无此组，点一个另一个仍保持按下
	# （两个看似同时激活），再点还会把已按下的弹起，模式切换表现为“没反应”。
	var gpModeGroup: ButtonGroup = ButtonGroup.new()
	gpModeGroup.allow_unpress = false
	var gpModeBox: VBoxContainer = VBoxContainer.new()
	gpModeBox.add_theme_constant_override("separation", 4)
	var gpModeLabel: Label = Label.new()
	gpModeLabel.text = I18n.gpTr("make_symbol.mode")
	gpModeBox.add_child(gpModeLabel)
	var gpModeRow: HBoxContainer = HBoxContainer.new()
	gpModeRow.add_theme_constant_override("separation", 12)
	_gpModeNew = Button.new()
	_gpModeNew.toggle_mode = true
	_gpModeNew.button_group = gpModeGroup
	_gpModeNew.button_pressed = true
	_gpModeNew.text = I18n.gpTr("make_symbol.new")
	var gpModeOverW: Button = Button.new()
	gpModeOverW.toggle_mode = true
	gpModeOverW.button_group = gpModeGroup
	gpModeOverW.text = I18n.gpTr("make_symbol.overwrite")
	gpModeRow.add_child(_gpModeNew)
	gpModeRow.add_child(gpModeOverW)
	gpModeBox.add_child(gpModeRow)
	gpBody.add_child(gpModeBox)
	_gpModeOver = gpModeOverW
	# Initial mode is NOT hardcoded here: the first _gpRefreshState() (end of _gpBuild)
	# derives it from id existence — a taken id forces Overwrite, a free id forces New.
	# 初始模式不在此硬编码：_gpBuild 末尾的首次 _gpRefreshState() 会按 id 是否已存在
	# 推导——已被占用强制覆盖、空闲强制新建。
	_gpModeNew.pressed.connect(func() -> void: _gpOnModeChanged())
	gpModeOverW.pressed.connect(func() -> void: _gpOnModeChanged())

	# Hint line (will-overwrite warning / errors) / 提示行（覆盖警告 / 错误）
	_gpHint = Label.new()
	_gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gpHint.add_theme_color_override("font_color", Color(0.85, 0.45, 0.2))
	_gpHint.custom_minimum_size = Vector2(0.0, 34.0)
	gpBody.add_child(_gpHint)

	# Action row / 操作行
	var gpAct: HBoxContainer = HBoxContainer.new()
	gpAct.add_theme_constant_override("separation", 8)
	gpAct.alignment = BoxContainer.ALIGNMENT_END
	var gpCancel: Button = Button.new()
	gpCancel.text = I18n.gpTr("make_symbol.cancel")
	var gpOk: Button = Button.new()
	gpOk.text = I18n.gpTr("make_symbol.ok")
	gpOk.disabled = true
	gpAct.add_child(gpCancel)
	gpAct.add_child(gpOk)
	gpRoot.add_child(gpAct)
	_gpOk = gpOk

	# Wire / 接线
	gpCancel.pressed.connect(_gpOnCancel)
	gpOk.pressed.connect(_gpOnOk)
	_gpNameEdit.text_changed.connect(func(_gpT: String) -> void: _gpRefreshState())
	_gpDisplayEdit.text_changed.connect(func(_gpT: String) -> void: _gpRefreshState())
	_gpCatBtn.item_selected.connect(func(_gpI: int) -> void: _gpRefreshState(); _gpEditor.gpSetCategory(_gpCurrentCat()))
	# Window's own close signal (not a gp-prefixed member): pressing the OS close button cancels.
	# Window 自带关闭信号（非 gp 前缀成员）：点系统关闭按钮即取消。
	close_requested.connect(_gpOnCancel)

	# Materialize the working model from the incoming draft + ports before first paint. The editor
	# emits gpChanged during gpInit (and again on gpSetTool), driving both the repaint and the panel
	# sync through _gpOnEditorChanged — so no manual panel sync is needed here.
	# 首次绘制前，由传入草稿 + 端口具象化工作模型。编辑器在 gpInit（及 gpSetTool）时发出 gpChanged，
	# 经 _gpOnEditorChanged 同时驱动重绘与面板同步——此处无需手动同步面板。
	_gpInitModel()
	_gpRefreshState()
	# Focus the name field only when the dialog is already inside the tree (headless runs
	# and pre-popup builds would otherwise error with "!is_inside_tree").
	# 仅当对话框已在场景树内才聚焦名称框（headless 运行与弹出前构建否则会报
	# "!is_inside_tree"）。
	if _gpNameEdit.is_inside_tree():
		_gpNameEdit.grab_focus()


# Build the read-only-turned-interactive preview Control: a drawing surface that also
# receives mouse / keyboard input for port + glyph editing.
# 构建「由只读升级为可交互」的预览控件：既是绘制面，也接收鼠标 / 键盘输入以编辑端点与图元。
func _gpNewPreview() -> Control:
	var gpC: Control = Control.new()
	gpC.name = "Preview"
	gpC.custom_minimum_size = GP_PREVIEW_SIZE
	gpC.clip_contents = true
	gpC.mouse_filter = Control.MOUSE_FILTER_STOP
	# Geometry drawing + input are owned by GPSymbolEditor now. The preview only forwards its
	# draw / gui_input to the editor; the editor paints the glyph + ports + tool overlays.
	# 几何绘制与输入现由 GPSymbolEditor 负责。预览只把 draw / gui_input 转发给编辑器，
	# 编辑器绘制字形 + 端口 + 工具覆盖层。
	gpC.draw.connect(func() -> void: _gpEditor.gpDraw(gpC))
	gpC.gui_input.connect(func(gpEv: InputEvent) -> void: _gpEditor.gpOnInput(gpEv))
	return gpC


# Build the editor toolbar (tool selector). Each button is a toggle; exactly one is pressed.
# 构建编辑工具条（工具选择器）。每个按钮为开关，恰一个处于按下态。
func _gpNewToolRow() -> HBoxContainer:
	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 4)
	gpRow.name = "ToolRow"
	var gpLabels: Array[String] = [
		I18n.gpTr("make_symbol.tool_select"),
		I18n.gpTr("make_symbol.tool_port"),
		I18n.gpTr("make_symbol.tool_line"),
		I18n.gpTr("make_symbol.tool_rect"),
		I18n.gpTr("make_symbol.tool_circle"),
		I18n.gpTr("make_symbol.tool_poly"),
	]
	for gpI in range(gpLabels.size()):
		var gpB: Button = Button.new()
		gpB.toggle_mode = true
		gpB.text = gpLabels[gpI]
		gpB.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Bind the loop index by value so every button keeps its own tool (a captured loop
		# variable would otherwise collapse all buttons to the last index).
		# 用 .bind 把循环索引按值固定，使每个按钮保留各自的工具（捕获循环变量会令所有按钮塌缩为末位）。
		gpB.pressed.connect(_gpEditor.gpSetTool.bind(gpI))
		_gpToolBtns.append(gpB)
		gpRow.add_child(gpB)
	return gpRow


# Build the port (connection point) editing panel.
# 构建端点（连接点）编辑面板。
func _gpNewPortPanel() -> PanelContainer:
	var gpPanel: PanelContainer = PanelContainer.new()
	gpPanel.name = "PortPanel"
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

	gpPanel.add_child(gpBox)
	return gpPanel


# Build the glyph-geometry editing panel (delete selected primitive).
# 构建图元几何编辑面板（删除选中图元）。
func _gpNewShapePanel() -> PanelContainer:
	var gpPanel: PanelContainer = PanelContainer.new()
	gpPanel.name = "ShapePanel"
	var gpBox: VBoxContainer = VBoxContainer.new()
	gpBox.add_theme_constant_override("separation", 4)
	var gpTitle: Label = Label.new()
	gpTitle.text = I18n.gpTr("make_symbol.shapes")
	gpTitle.add_theme_font_size_override("font_size", 14)
	gpBox.add_child(gpTitle)
	var gpDelRow: HBoxContainer = HBoxContainer.new()
	gpDelRow.add_theme_constant_override("separation", 6)
	_gpDelShape = Button.new()
	_gpDelShape.text = I18n.gpTr("make_symbol.delete_shape")
	_gpDelShape.disabled = true
	_gpDelShape.pressed.connect(func() -> void: _gpDeleteShape())
	gpDelRow.add_child(_gpDelShape)
	gpBox.add_child(gpDelRow)
	_gpShapeHint = Label.new()
	_gpShapeHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gpShapeHint.custom_minimum_size = Vector2(0.0, 28.0)
	gpBox.add_child(_gpShapeHint)
	gpPanel.add_child(gpBox)
	return gpPanel


# Materialize the working model: parse the draft into _gpShapes, and seed _gpPorts from the
# caller-supplied initial ports (or an empty list when creating from scratch).
# 具象化工作模型：把草稿解析进 _gpShapes，并用调用方提供的初始端口（或新建时的空列表）播种 _gpPorts。
func _gpInitModel() -> void:
	# Parse the draft into the editor's working geometry, and seed its ports from the caller-supplied
	# initial ports (or an empty list when creating from scratch). Both are pushed IN PLACE so the
	# editor's command stack keeps valid references; the history is cleared by gpInit.
	# 把草稿解析进编辑器的工作几何，并用调用方提供的初始端口（或新建时的空列表）播种端口。
	# 两者均原地推送，使编辑器的命令栈持有有效引用；历史由 gpInit 清空。
	var gpS: Array[GPShape] = GPShapeSpec.gpFromSpec(gpDraft)
	var gpP: Array[GPPort] = GPPortSpec.gpFromDicts(GPPortSpec.gpToDicts(gpInitialPorts))
	_gpEditor.gpInit(gpS, gpP)


# ---- delegation glue (UI <-> GPSymbolEditor) ----
# 委托胶水层（UI <-> GPSymbolEditor）

# Repaint + re-sync the port / shape panels whenever the editor model or selection changes.
# 编辑器模型或选择变更时重绘并重新同步端点 / 图元面板。
func _gpOnEditorChanged() -> void:
	if _gpPreview != null:
		_gpPreview.queue_redraw()
	_gpSyncPortPanel()
	_gpSyncShapePanel()


# Reflect the active tool on the tool-button row. / 在工具按钮行上反映当前工具。
func _gpOnToolChanged(gpKind: int) -> void:
	for gpI in range(_gpToolBtns.size()):
		_gpToolBtns[gpI].button_pressed = (gpI == gpKind)


# ---- port / shape panel sync ----
# 端点 / 图形面板同步
func _gpDirIndex(gpDir: Vector2) -> int:
	for gpI in range(_gpDirs.size()):
		if _gpDirs[gpI].is_equal_approx(gpDir):
			return gpI
	return 0


func _gpSyncPortPanel() -> void:
	if _gpPortName == null or _gpEditor == null:
		return
	if _gpEditor.gpSelPort >= 0 and _gpEditor.gpSelPort < _gpEditor.gpPorts.size():
		var gpP: GPPort = _gpEditor.gpPorts[_gpEditor.gpSelPort]
		_gpPortName.text = gpP.gpName
		_gpPortName.editable = true
		_gpPortDir.selected = _gpDirIndex(gpP.gpDir)
		_gpDelPort.disabled = false
		_gpPortHint.text = I18n.gpTr("make_symbol.port_selected")
	else:
		_gpPortName.text = ""
		_gpPortName.editable = false
		_gpPortDir.selected = 0
		_gpDelPort.disabled = true
		_gpPortHint.text = I18n.gpTr("make_symbol.no_port_selected")


func _gpSyncShapePanel() -> void:
	if _gpDelShape == null or _gpEditor == null:
		return
	if _gpEditor.gpSelShape >= 0 and _gpEditor.gpSelShape < _gpEditor.gpShapes.size():
		_gpDelShape.disabled = false
		_gpShapeHint.text = I18n.gpTr("make_symbol.shape_selected") % (_gpEditor.gpSelShape + 1)
	else:
		_gpDelShape.disabled = true
		_gpShapeHint.text = I18n.gpTr("make_symbol.no_shape_selected") % _gpEditor.gpShapes.size()


func _gpOnPortName(gpT: String) -> void:
	if _gpEditor == null:
		return
	_gpEditor.gpSetPortName(gpT)


func _gpOnPortDir(gpI: int) -> void:
	if _gpEditor == null:
		return
	_gpEditor.gpSetPortDir(_gpDirs[gpI])


func _gpDeletePort() -> void:
	if _gpEditor == null:
		return
	_gpEditor.gpDeleteSelectedPort()


func _gpDeleteShape() -> void:
	if _gpEditor == null:
		return
	_gpEditor.gpDeleteSelectedShape()


func _gpSetTool(gpTool: int) -> void:
	if _gpEditor != null:
		_gpEditor.gpSetTool(gpTool)


# ---- helpers ----
# 助手
func _gpCurrentCat() -> String:
	if _gpCatBtn != null and _gpCatBtn.selected >= 0 and _gpCatBtn.selected < _gpCatKeys.size():
		return _gpCatKeys[_gpCatBtn.selected]
	return "general"


# Convert the working ports (normalized 0..1) into author-space pixels for the save dict.
# The inverse of GPSymbolNormalizer.gpNormalizePorts is applied with the SAME bbox + envelope
# the normalizer will recompute from the saved shapes, so the round-trip is exact.
# 把工作端口（归一化 0..1）换算为保存字典所需的作者空间像素。这里用与 GPSymbolNormalizer
# 从已保存图形重算时「同一 bbox + 包络」的 gpNormalizePorts 逆运算，使往返精确无漂移。
func _gpAuthorPorts(gpCat: String = "") -> Array:
	if _gpEditor == null:
		return []
	return _gpEditor.gpAuthorPorts(gpCat)


# Create a labeled LineEdit row inside gpParent; returns the LineEdit.
# 在 gpParent 内创建带标签的输入行；返回该 LineEdit。
func _gpNewLabeledEdit(gpParent: VBoxContainer, gpLabel: String, gpInit: String) -> LineEdit:
	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 6)
	var gpL: Label = Label.new()
	gpL.text = gpLabel + ":"
	gpL.custom_minimum_size = Vector2(110.0, 0.0)
	gpRow.add_child(gpL)
	var gpE: LineEdit = LineEdit.new()
	gpE.text = gpInit
	gpE.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpRow.add_child(gpE)
	gpParent.add_child(gpRow)
	return gpE


func _gpOnModeChanged() -> void:
	_gpRefreshState()


# Enable OK / show overwrite target / warning based on current inputs.
# 依据当前输入启用「确定」/ 显示覆盖目标 / 警告。
func _gpRefreshState() -> void:
	var gpName: String = _gpNameEdit.text.strip_edges()
	var gpOverwriteMode: bool = _gpModeOver.button_pressed

	_gpExistingTargetId = ""

	# ID lookup runs on every keystroke regardless of the selected mode: whether the derived
	# id already exists in the library decides which mode is available AT ALL (id uniqueness
	# governs the dialog). Display name plays NO role.
	# 标识 id 查重与所选模式无关，每次输入都执行：派生 id 是否已存在于库中决定哪种模式
	# 可用（id 唯一性主导对话框）。显示名不参与判定。
	var gpHintSet: bool = false
	var gpTarget: GPSymbolDef = _gpFindExisting(gpName, _gpCurrentCategory())
	var gpBuiltinHit: bool = gpTarget != null and gpTarget.gpBuiltin

	if gpTarget != null and not gpBuiltinHit:
		# The name is taken by a user symbol: Overwrite is the ONLY available mode and is
		# forced on, so confirming replaces that symbol (keeping its allocated id).
		# 该名称已被用户图元占用：覆盖是唯一可用模式并被强制选中，确定即替换该图元
		#（沿用其已分配的 id）。
		_gpExistingTargetId = gpTarget.gpId
		_gpModeNew.disabled = true
		_gpModeOver.disabled = false
		if not gpOverwriteMode:
			_gpModeOver.button_pressed = true
			gpOverwriteMode = true
		var gpDisp: String = I18n.gpTr(gpTarget.gpDisplayName) if gpTarget.gpDisplayName.begins_with("sym.") or gpTarget.gpDisplayName.begins_with("iso.") else gpTarget.gpDisplayName
		_gpHint.text = I18n.gpTr("make_symbol.id_exists") % gpDisp
		gpHintSet = true
	elif gpBuiltinHit:
		# Built-in ids are read-only (decision D3): neither mode is available until the id
		# is changed to a free one.
		# 内置 id 只读（决策 D3）：更换为空闲 id 之前两种模式均不可用。
		_gpModeNew.disabled = true
		_gpModeOver.disabled = true
		_gpHint.text = I18n.gpTr("make_symbol.builtin_protected")
		gpHintSet = true
	else:
		# The id is free: New is the ONLY available mode and is forced on; overwrite has no
		# target and stays disabled.
		# 该 id 空闲：新建是唯一可用模式并被强制选中；覆盖无目标、保持禁用。
		_gpModeNew.disabled = false
		_gpModeOver.disabled = true
		if gpOverwriteMode:
			_gpModeNew.button_pressed = true
			gpOverwriteMode = false

	# OK gate: only the id source (internal name) is mandatory — the display name may be
	# left empty and falls back to the internal name on save. In overwrite mode a valid
	# non-built-in target id is required (guaranteed by the forced mode above).
	# 确定门控：仅标识来源（内部名称）必填 —— 显示名可留空，保存时回退为内部名称。
	# 覆盖模式要求有效的非内置覆盖目标 id（由上方强制模式保证）。
	if gpName == "":
		_gpOk.disabled = true
		_gpHint.text = I18n.gpTr("make_symbol.name_empty")
		return
	# A built-in id clash blocks OK in EVERY mode (both mode buttons are disabled, but the
	# pressed mode may still be New — without this guard OK would stay enabled and let a
	# "new" symbol slip through with a deduped xxx_2 id).
	# 内置 id 冲突在任意模式下都阻止确定（两个模式按钮虽已禁用，但按下态可能仍是新建
	# —— 缺此守卫时确定会保持可用，以去重 xxx_2 的 id 「新建」出混淆图元）。
	if gpBuiltinHit or (gpOverwriteMode and _gpExistingTargetId == ""):
		_gpOk.disabled = true
		# The hint already explains why (builtin_protected).
		# 提示行已说明原因（内置保护）。
	else:
		_gpOk.disabled = false
		# Clear stale warnings ONLY when this pass set no hint, so the id-exists
		# message survives.
		# 仅当本次未设置提示时才清残留警告，保住「id 已存在」信息。
		if not gpHintSet:
			_gpHint.text = ""


# Uniqueness is judged by NAME + CATEGORY, not by an id: since the L/C naming rule the id
# is allocated from the category (C< CATEGORY ><nnn>) and no longer derives from the name,
# so the name is the only thing that tells "does this symbol already exist?". Built-ins are
# read-only (decision D3): when the name hits a built-in, it is returned so
# _gpRefreshState/_gpOnOk can refuse.
# 唯一性以「名称 + 类别」判定，而非 id：自 L/C 命名规则起，id 由类别分配
# （C<类别码><三位序号>）、不再由名称导出，因此只有名称能回答「该图元是否已存在」。
# 内置图元只读（决策 D3）：名称命中内置时原样返回，由 _gpRefreshState/_gpOnOk 拒绝。
func _gpFindExisting(gpName: String, gpCategory: String) -> GPSymbolDef:
	if gpName == "":
		return null
	return GPSymbolLibrary.gpFindByNameAndCategory(gpName, gpCategory)


# Category currently selected in the dropdown, defaulting to "general".
# 下拉框当前选中的类别，缺省为 "general"。
func _gpCurrentCategory() -> String:
	var gpCat: String = "general"
	if _gpCatBtn.selected >= 0 and _gpCatBtn.selected < _gpCatKeys.size():
		gpCat = _gpCatKeys[_gpCatBtn.selected]
	return gpCat


func _gpOnCancel() -> void:
	gpCancelled.emit()
	queue_free()


# Confirm: resolve new vs overwrite, build the def, register + persist, emit gpMadeSymbol.
# 确定：判定新建/覆盖，构建 def，注册 + 持久化，发出 gpMadeSymbol。
func _gpOnOk() -> void:
	var gpName: String = _gpNameEdit.text.strip_edges()
	if gpName == "":
		return
	var gpDisplay: String = _gpDisplayEdit.text.strip_edges()
	# The display name is a label only — fall back to the internal name when left empty.
	# 显示名仅作标签 —— 留空时回退为内部名称。
	if gpDisplay == "":
		gpDisplay = gpName
	var gpCat: String = "general"
	if _gpCatBtn.selected >= 0 and _gpCatBtn.selected < _gpCatKeys.size():
		gpCat = _gpCatKeys[_gpCatBtn.selected]
	var gpOverwrite: bool = _gpModeOver.button_pressed

	# Overwrite is decided by NAME + CATEGORY: the name identifies the existing def to
	# replace. The New path allocates the next free id from the naming rule
	# (C<CATEGORY><nnn>) — ids are never derived from the name any more.
	# 覆盖由「名称 + 类别」决定：名称定位被替换的已有图元。新建路径按命名规则
	#（C<类别码><三位序号>）分配下一个空闲 id —— id 不再由名称导出。
	var gpTarget: GPSymbolDef = _gpFindExisting(gpName, gpCat)
	var gpId: String = ""
	if gpOverwrite and gpTarget != null and not gpTarget.gpBuiltin:
		gpId = gpTarget.gpId
	else:
		gpId = GPSymbolLibrary.gpAllocateCustomId(gpCat)
	if gpId == "":
		# The category used up all 999 slots: refuse instead of emitting a malformed id.
		# 该类别已用满 999 个号位：拒绝，而不是产出一个非法 id。
		_gpHint.text = I18n.gpTr("make_symbol.category_full",
			"Category %s has no free id left (999 used)") % GPSymbolNaming.gpCategoryCode(gpCat)
		return

	# Serialize the edited geometry from the working model (lossless, keeps Bézier handles) plus
	# the edited ports expressed in author-space pixels.
	# 由工作模型序列化编辑后的几何（无损，保留贝塞尔手柄），并附上作者空间像素表达的编辑后端口。
	var gpRaw: Dictionary = {
		"id": gpId,
		"display_name": gpDisplay,
		"category": gpCat,
		"shapes": GPShapeSpec.gpEditSpec(_gpEditor.gpShapes),
		"ports": _gpAuthorPorts(),
		"attrs_schema": {},
	}
	var gpNewDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpRaw, gpCat, {})
	GPSymbolLibrary.gpRegisterDefs([gpNewDef])
	_gpPersist(gpNewDef)
	gpMadeSymbol.emit(gpNewDef.gpId)
	queue_free()


# Symbol ids are no longer derived from the name: since the L/C naming rule they are
# allocated by GPSymbolNaming via GPSymbolLibrary.gpAllocateCustomId (C<CATEGORY><nnn>).
# The name still matters — it is what makes a symbol "already exist" (see
# _gpFindExisting) — but it no longer turns into an id. GPIdGen.gpSanitize remains the
# normalizer for the OTHER id spaces (documents, cross-references) that W21/W22 add.
# 图元 id 不再由名称导出：自 L/C 命名规则起，它们由 GPSymbolNaming 经
# GPSymbolLibrary.gpAllocateCustomId 分配（C<类别码><三位序号>）。名称仍有作用 —— 它是判定
# 图元「是否已存在」的依据（见 _gpFindExisting）—— 但不再被转成 id。GPIdGen.gpSanitize
# 仍是其他 id 空间（文档、跨图引用）的归一化器，供 W21/W22 使用。


# Persist a def as a single-symbol user pack under user://symbol_packs/<id>.json.
# 把单个图元 def 持久化为 user://symbol_packs/<id>.json 用户包。
func _gpPersist(gpNewDef: GPSymbolDef) -> void:
	var gpDir: String = GPSymbolLibrary.GP_USER_PACKS_DIR
	if not DirAccess.dir_exists_absolute(gpDir):
		DirAccess.make_dir_recursive_absolute(gpDir)
	var gpPack: GPSymbolPack = GPSymbolPack.new()
	gpPack.gpPackId = "user_%s" % gpNewDef.gpId
	gpPack.gpName = gpNewDef.gpDisplayName
	gpPack.gpVersion = "1.0"
	# Append (NOT a literal assignment): an untyped array literal must not be assigned
	# wholesale to the typed Array[GPSymbolDef] member (runtime type error).
	# 用 append（勿用字面量整体赋值）：无类型数组字面量不能整体赋给强类型 Array[GPSymbolDef] 成员。
	gpPack.gpSymbols.append(gpNewDef)
	var gpPath: String = "%s/%s.json" % [gpDir, gpNewDef.gpId]
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.WRITE)
	if gpF == null:
		push_warning("GPMakeSymbolDialog: cannot write %s" % gpPath)
		return
	gpF.store_string(JSON.stringify(gpPack.gpToDict(), "", true))
	gpF.close()
