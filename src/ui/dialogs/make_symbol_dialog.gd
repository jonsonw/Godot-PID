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
# Beyond the original read-only preview, the dialog is now an INTERACTIVE editor:
#   - Connection ports (endpoints) can be ADDED by clicking, MOVED by dragging, and the
#     selected port can be RENAMED / re-aimed (direction) / DELETED.
#   - Simple glyph editing: add Line / Rectangle / Circle / Polyline primitives by
#     drawing on the preview, SELECT + MOVE an existing primitive, or DELETE it.
# The working model is two strongly-typed arrays, _gpShapes (Array[GPShape]) and
# _gpPorts (Array[GPPort]); everything is re-serialized to the save dict on confirm.
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

# -- editor tool state / 编辑工具状态 --
enum GPTool { GP_SELECT, GP_PORT, GP_LINE, GP_RECT, GP_CIRCLE, GP_POLY }
# Drag sub-state while the mouse is held: -1 none, 0 port, 1 shape, 2 newline, 3 newrect,
# 4 newcircle, 5 newpoly.
# 鼠标按住时的拖拽子状态：-1 无，0 端点，1 图形，2 新直线，3 新矩形，4 新圆，5 新折线。
const GP_PORT_HIT: float = 9.0
const GP_MIN_LEN: float = 3.0

var _gpTool: int = GPTool.GP_SELECT
var _gpShapes: Array[GPShape] = []            # working geometry model / 工作几何模型
var _gpPorts: Array[GPPort] = []              # working ports, normalized 0..1 / 工作端口（归一化）
var _gpSelPort: int = -1
var _gpSelShape: int = -1
var _gpDragKind: int = -1
var _gpDragLast: Vector2 = Vector2.ZERO
var _gpDraftShape: GPShape = null             # shape currently being drawn / 正在绘制的图形
var _gpPolyPts: PackedVector2Array = PackedVector2Array()
var _gpPolyCursor: Vector2 = Vector2.ZERO
# Outward-normal direction choices for a port / 端口可选朝向（向外法线）。
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
	_gpCatBtn.item_selected.connect(func(_gpI: int) -> void: _gpRefreshState(); _gpPreview.queue_redraw())
	# Window's own close signal (not a gp-prefixed member): pressing the OS close button cancels.
	# Window 自带关闭信号（非 gp 前缀成员）：点系统关闭按钮即取消。
	close_requested.connect(_gpOnCancel)

	# Materialize the working model from the incoming draft + ports before first paint.
	# 首次绘制前，由传入草稿 + 端口具象化工作模型。
	_gpInitModel()
	_gpSetTool(GPTool.GP_SELECT)
	_gpSyncPortPanel()
	_gpSyncShapePanel()
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
	gpC.draw.connect(func() -> void: _gpDrawPreview(gpC))
	gpC.gui_input.connect(_gpOnPreviewInput)
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
		gpB.pressed.connect(_gpSetTool.bind(gpI))
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
	_gpShapes = GPShapeSpec.gpFromSpec(gpDraft)
	# gpFromSpec ignores a stray "box" key and handles paths/circles/rects/arcs uniformly.
	# gpFromSpec 会忽略多余的 "box" 键，并统一处理 paths/circles/rects/arcs。
	# Deep-copy the incoming ports via the dict round-trip so editing never aliases the live
	# library's port objects (which would mutate other placed instances of the symbol).
	# 经字典往返深拷贝传入端口，使编辑绝不会别名到活动图元库的端口对象（否则会改到其他已放置实例）。
	_gpPorts = GPPortSpec.gpFromDicts(GPPortSpec.gpToDicts(gpInitialPorts))
	_gpSelPort = -1
	_gpSelShape = -1


# ---- coordinate mapping (preview-local <-> author-space, and normalized ports) ----
# 坐标映射（预览本地 <-> 作者空间，及归一化端口）
# The painter fits the glyph's unit box into the preview rect with uniform scale + centering.
# That mapping is now a pure module — GPPreviewTransform (core/geometry) — so the exact
# round-trip is headless-testable; the helpers below are thin wrappers that keep every call
# site in this file compiling unchanged.
# 渲染器以均匀缩放 + 居中把字形单位框塞入预览矩形。该映射现为纯模块 —— GPPreviewTransform
# （core/geometry）—— 使精确往返可在 headless 下断言；下列助手只是薄封装，使本文件各调用点保持不变。
var _gpXf: GPPreviewTransform = GPPreviewTransform.new()


# Refresh the transform from the live preview size and working shapes. Called at the top of every
# mapping helper ON PURPOSE: caching it would require an invalidation at every mutation site,
# which is exactly how "the click landed somewhere other than the glyph" bugs get introduced.
# 依实时预览尺寸与工作图形刷新变换。刻意在每个映射助手开头调用：若要缓存，就必须在每处变更点
# 使其失效——「点击落在图形之外」这类缺陷正是这样引入的。
func _gpSyncXf() -> void:
	_gpXf.gpViewSize = _gpPreview.size if _gpPreview != null else GP_PREVIEW_SIZE
	_gpXf.gpBox = GPPreviewTransform.gpBoxOf(_gpShapes)


func _gpViewRect(gpC: Control) -> Rect2:
	_gpXf.gpViewSize = gpC.size
	return _gpXf.gpViewRect()


func _gpLocalToAuthor(gpLocal: Vector2) -> Vector2:
	_gpSyncXf()
	return _gpXf.gpLocalToAuthor(gpLocal)


func _gpAuthorToLocal(gpAuthor: Vector2) -> Vector2:
	_gpSyncXf()
	return _gpXf.gpAuthorToLocal(gpAuthor)


# Normalized port (0..1) -> preview-local pixel. The full preview rect is the envelope, matching
# how GPSymbolView draws ports relative to the symbol's nominal envelope on the canvas.
# 归一化端口（0..1）-> 预览本地像素。整幅预览矩形即包络，与画布上 GPSymbolView 相对图元标称
# 包络绘制端口的方式一致。
func _gpPortLocal(gpN: Vector2) -> Vector2:
	_gpSyncXf()
	return _gpXf.gpPortLocal(gpN)


func _gpLocalToNorm(gpLocal: Vector2) -> Vector2:
	_gpSyncXf()
	return _gpXf.gpLocalToNorm(gpLocal)


# ---- drawing ----
# 绘制
func _gpDrawPreview(gpC: Control) -> void:
	var gpRect: Rect2 = _gpViewRect(gpC)
	# Pale panel fill / 淡色面板底
	gpC.draw_rect(gpRect, Color(0.12, 0.13, 0.16, 1.0), true)
	gpC.draw_rect(gpRect, Color(0.35, 0.38, 0.44, 1.0), false, 1.0)

	# Glyph shapes / 图元几何
	if not _gpShapes.is_empty():
		var gpSpec: Dictionary = GPShapeSpec.gpBuild(_gpShapes)
		var gpStroke: Color = GPSymbolPainter.gpCategoryColor(_gpCurrentCat())
		GPSymbolPainter.gpDrawShape(gpC, gpSpec, gpRect, Color(0.08, 0.09, 0.11, 1.0), gpStroke, 2.0)

	# Shape currently being drawn / 正在绘制的图形
	if _gpDraftShape != null:
		var gpDraftSpec: Dictionary = GPShapeSpec.gpBuild([_gpDraftShape])
		GPSymbolPainter.gpDrawShape(gpC, gpDraftSpec, gpRect, Color(0.08, 0.09, 0.11, 1.0), Color(0.6, 0.9, 1.0), 1.5)

	# Polyline in progress (placed vertices + rubber-band to cursor) / 进行中的折线（已落点 + 到光标的橡皮筋）
	if not _gpPolyPts.is_empty():
		var gpVecs: PackedVector2Array = PackedVector2Array()
		for gpP in _gpPolyPts:
			gpVecs.append(_gpAuthorToLocal(gpP))
		if _gpTool == GPTool.GP_POLY:
			gpVecs.append(_gpAuthorToLocal(_gpPolyCursor))
		gpC.draw_polyline(gpVecs, Color(0.6, 0.9, 1.0), 1.5)
		for gpP in _gpPolyPts:
			gpC.draw_circle(_gpAuthorToLocal(gpP), 3.0, Color(0.6, 0.9, 1.0))

	# Selection highlight around the selected primitive / 选中图形的高亮框
	if _gpSelShape >= 0 and _gpSelShape < _gpShapes.size():
		var gpB: Rect2 = _gpShapes[_gpSelShape].gpBBox().grow(GP_MIN_LEN)
		var gpA0: Vector2 = _gpAuthorToLocal(gpB.position)
		var gpA1: Vector2 = _gpAuthorToLocal(gpB.position + gpB.size)
		gpC.draw_rect(Rect2(gpA0, gpA1 - gpA0).abs(), Color(1.0, 0.85, 0.2), false, 1.5)

	# Ports (connection points) / 连接端点
	for gpI in range(_gpPorts.size()):
		var gpP: GPPort = _gpPorts[gpI]
		var gpL: Vector2 = _gpPortLocal(gpP.gpPos)
		var gpCol: Color = Color(1.0, 1.0, 1.0) if gpI == _gpSelPort else Color(0.4, 0.9, 1.0)
		gpC.draw_circle(gpL, 4.0, gpCol)
		if gpP.gpDir != Vector2.ZERO:
			gpC.draw_line(gpL, gpL + gpP.gpDir * 12.0, gpCol, 1.5)


# ---- input ----
# 输入
func _gpOnPreviewInput(gpEv: InputEvent) -> void:
	if gpEv is InputEventMouseButton:
		var gpMb: InputEventMouseButton = gpEv as InputEventMouseButton
		if gpMb.button_index == MOUSE_BUTTON_LEFT:
			if gpMb.pressed:
				_gpOnPress(gpMb.position)
			else:
				_gpOnRelease(gpMb.position)
	elif gpEv is InputEventMouseMotion:
		_gpOnMotion((gpEv as InputEventMouseMotion).position)
	elif gpEv is InputEventKey:
		var gpK: InputEventKey = gpEv as InputEventKey
		if gpK.pressed:
			_gpOnKey(gpK)


func _gpOnPress(gpLocal: Vector2) -> void:
	match _gpTool:
		GPTool.GP_SELECT:
			var gpPi: int = _gpHitPort(gpLocal)
			if gpPi >= 0:
				_gpSelPort = gpPi
				_gpSelShape = -1
				_gpDragKind = 0
				_gpSyncPortPanel()
				_gpPreview.queue_redraw()
				return
			var gpSi: int = _gpHitShape(gpLocal)
			if gpSi >= 0:
				_gpSelShape = gpSi
				_gpSelPort = -1
				_gpDragKind = 1
				_gpDragLast = gpLocal
				_gpSyncShapePanel()
				_gpPreview.queue_redraw()
				return
			_gpSelPort = -1
			_gpSelShape = -1
			_gpSyncPortPanel()
			_gpSyncShapePanel()
			_gpPreview.queue_redraw()
		GPTool.GP_PORT:
			var gpN: Vector2 = _gpLocalToNorm(gpLocal)
			var gpP: GPPort = GPPort.new()
			gpP.gpName = "p%d" % (_gpPorts.size() + 1)
			gpP.gpPos = gpN
			var gpEdge: Array = GPSymbolNormalizer.gpEdgeNormal(gpN)
			gpP.gpDir = Vector2(float(gpEdge[0]), float(gpEdge[1]))
			_gpPorts.append(gpP)
			_gpSelPort = _gpPorts.size() - 1
			_gpSelShape = -1
			_gpSyncPortPanel()
			_gpPreview.queue_redraw()
		GPTool.GP_LINE:
			_gpStartNew(GPShape.GPKind.GP_LINE, gpLocal)
		GPTool.GP_RECT:
			_gpStartNew(GPShape.GPKind.GP_RECT, gpLocal)
		GPTool.GP_CIRCLE:
			_gpStartNew(GPShape.GPKind.GP_CIRCLE, gpLocal)
		GPTool.GP_POLY:
			var gpA: Vector2 = _gpLocalToAuthor(gpLocal)
			if _gpPolyPts.size() >= 2 and _gpAuthorToLocal(_gpPolyPts[0]).distance_to(gpLocal) < 8.0:
				_gpFinishPoly()
				return
			_gpPolyPts.append(gpA)
			_gpPolyCursor = gpA
			_gpPreview.queue_redraw()


func _gpOnMotion(gpLocal: Vector2) -> void:
	match _gpDragKind:
		0:  # dragging a port / 拖拽端点
			if _gpSelPort >= 0 and _gpSelPort < _gpPorts.size():
				_gpPorts[_gpSelPort].gpPos = _gpLocalToNorm(gpLocal)
				_gpPreview.queue_redraw()
		1:  # dragging a shape / 拖拽图形
			var gpDeltaA: Vector2 = _gpLocalToAuthor(gpLocal) - _gpLocalToAuthor(_gpDragLast)
			_gpDragLast = gpLocal
			_gpTranslateShape(_gpSelShape, gpDeltaA)
			_gpPreview.queue_redraw()
		2:  # drawing a line / 绘制直线
			if _gpDraftShape != null and _gpDraftShape.gpPoints.size() >= 2:
				_gpDraftShape.gpPoints = PackedVector2Array([_gpDraftShape.gpPoints[0], _gpLocalToAuthor(gpLocal)])
				_gpPreview.queue_redraw()
		3:  # drawing a rectangle / 绘制矩形
			if _gpDraftShape != null and _gpDraftShape.gpPoints.size() >= 2:
				_gpDraftShape.gpPoints = PackedVector2Array([_gpDraftShape.gpPoints[0], _gpLocalToAuthor(gpLocal)])
				_gpPreview.queue_redraw()
		4:  # drawing a circle / 绘制圆
			if _gpDraftShape != null and _gpDraftShape.gpPoints.size() >= 1:
				_gpDraftShape.gpRadius = _gpDraftShape.gpPoints[0].distance_to(_gpLocalToAuthor(gpLocal))
				_gpPreview.queue_redraw()
		5:  # drawing a polyline / 绘制折线
			_gpPolyCursor = _gpLocalToAuthor(gpLocal)
			_gpPreview.queue_redraw()


func _gpOnRelease(gpLocal: Vector2) -> void:
	match _gpDragKind:
		2:
			_gpCommitLine()
		3:
			_gpCommitRect()
		4:
			_gpCommitCircle()
	_gpDragKind = -1
	_gpDraftShape = null
	_gpPreview.queue_redraw()


func _gpOnKey(gpK: InputEventKey) -> void:
	if gpK.keycode == KEY_ENTER or gpK.keycode == KEY_KP_ENTER:
		if _gpTool == GPTool.GP_POLY and _gpPolyPts.size() >= 2:
			_gpFinishPoly()
	elif gpK.keycode == KEY_ESCAPE:
		if _gpTool == GPTool.GP_POLY:
			_gpPolyPts = PackedVector2Array()
			_gpPreview.queue_redraw()
	elif gpK.keycode == KEY_DELETE or gpK.keycode == KEY_BACKSPACE:
		if _gpSelPort >= 0:
			_gpDeletePort()
		elif _gpSelShape >= 0:
			_gpDeleteShape()


# ---- hit testing ----
# 命中测试
func _gpHitPort(gpLocal: Vector2) -> int:
	for gpI in range(_gpPorts.size()):
		if _gpPortLocal(_gpPorts[gpI].gpPos).distance_to(gpLocal) < GP_PORT_HIT:
			return gpI
	return -1


func _gpHitShape(gpLocal: Vector2) -> int:
	var gpA: Vector2 = _gpLocalToAuthor(gpLocal)
	# GPGeometry.gpShapeHit replaces the old bbox test: a bbox "hit" selects a shape when the
	# click lands in empty space inside its bounding rectangle, and it cannot tell a curved
	# polyline from its straight control polygon. The shared routine tests the real outline
	# (flattening curves and arcs) within a tolerance, matching the main canvas exactly.
	# 改用 GPGeometry.gpShapeHit 取代旧的包围盒判据：包围盒判据在点击落在矩形内空白处时也算命中，
	# 且无法区分曲线折线与其直线控制多边形。共享例程按容差测试真实轮廓（展平曲线与圆弧），
	# 与主画布完全一致。
	var gpTol: float = GP_MIN_LEN
	for gpI in range(_gpShapes.size() - 1, -1, -1):
		if GPGeometry.gpShapeHit(gpA, _gpShapes[gpI], gpTol):
			return gpI
	return -1


# ---- shape creation / commit ----
# 图形创建 / 提交
func _gpStartNew(gpKind: int, gpLocal: Vector2) -> void:
	var gpA: Vector2 = _gpLocalToAuthor(gpLocal)
	_gpDragLast = gpLocal
	if gpKind == GPShape.GPKind.GP_LINE:
		_gpDragKind = 2
		_gpDraftShape = GPShape.gpLine(gpA, gpA)
	elif gpKind == GPShape.GPKind.GP_RECT:
		_gpDragKind = 3
		_gpDraftShape = GPShape.gpRect(gpA, gpA)
	elif gpKind == GPShape.GPKind.GP_CIRCLE:
		_gpDragKind = 4
		_gpDraftShape = GPShape.gpCircle(gpA, 0.0)
	_gpPreview.queue_redraw()


func _gpCommitLine() -> void:
	if _gpDraftShape == null or _gpDraftShape.gpPoints.size() < 2:
		return
	var gpA: Vector2 = _gpDraftShape.gpPoints[0]
	var gpB: Vector2 = _gpDraftShape.gpPoints[1]
	if gpA.distance_to(gpB) >= GP_MIN_LEN:
		_gpShapes.append(_gpDraftShape)
		_gpSelShape = _gpShapes.size() - 1
		_gpSelPort = -1
		_gpSetTool(GPTool.GP_SELECT)
		_gpSyncShapePanel()


func _gpCommitRect() -> void:
	if _gpDraftShape == null or _gpDraftShape.gpPoints.size() < 2:
		return
	var gpA: Vector2 = _gpDraftShape.gpPoints[0]
	var gpB: Vector2 = _gpDraftShape.gpPoints[1]
	var gpSz: Vector2 = (gpB - gpA).abs()
	if gpSz.x >= GP_MIN_LEN and gpSz.y >= GP_MIN_LEN:
		_gpShapes.append(_gpDraftShape)
		_gpSelShape = _gpShapes.size() - 1
		_gpSelPort = -1
		_gpSetTool(GPTool.GP_SELECT)
		_gpSyncShapePanel()


func _gpCommitCircle() -> void:
	if _gpDraftShape == null:
		return
	if _gpDraftShape.gpRadius >= GP_MIN_LEN:
		_gpShapes.append(_gpDraftShape)
		_gpSelShape = _gpShapes.size() - 1
		_gpSelPort = -1
		_gpSetTool(GPTool.GP_SELECT)
		_gpSyncShapePanel()


func _gpFinishPoly() -> void:
	if _gpPolyPts.size() >= 2:
		var gpArr: Array[Vector2] = []
		for gpP in _gpPolyPts:
			gpArr.append(gpP)
		_gpShapes.append(GPShape.gpPolyline(gpArr, false))
		_gpSelShape = _gpShapes.size() - 1
		_gpSelPort = -1
	_gpPolyPts = PackedVector2Array()
	_gpSetTool(GPTool.GP_SELECT)
	_gpSyncShapePanel()


func _gpTranslateShape(gpIdx: int, gpDelta: Vector2) -> void:
	if gpIdx < 0 or gpIdx >= _gpShapes.size():
		return
	var gpS: GPShape = _gpShapes[gpIdx]
	# Whole-shape translation is GPGeometry.gpShiftPoints — the same routine the main canvas
	# uses, so a shape dragged here and there cannot drift apart in behaviour.
	# 整体平移即 GPGeometry.gpShiftPoints —— 与主画布同一例程，使图形在此处与彼处拖动行为不会分歧。
	gpS.gpPoints = GPGeometry.gpShiftPoints(gpS.gpPoints, gpDelta)


# ---- port / shape panel sync ----
# 端点 / 图形面板同步
func _gpDirIndex(gpDir: Vector2) -> int:
	for gpI in range(_gpDirs.size()):
		if _gpDirs[gpI].is_equal_approx(gpDir):
			return gpI
	return 0


func _gpSyncPortPanel() -> void:
	if _gpPortName == null:
		return
	if _gpSelPort >= 0 and _gpSelPort < _gpPorts.size():
		var gpP: GPPort = _gpPorts[_gpSelPort]
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
	if _gpDelShape == null:
		return
	if _gpSelShape >= 0 and _gpSelShape < _gpShapes.size():
		_gpDelShape.disabled = false
		_gpShapeHint.text = I18n.gpTr("make_symbol.shape_selected") % (_gpSelShape + 1)
	else:
		_gpDelShape.disabled = true
		_gpShapeHint.text = I18n.gpTr("make_symbol.no_shape_selected") % _gpShapes.size()


func _gpOnPortName(gpT: String) -> void:
	if _gpSelPort < 0 or _gpSelPort >= _gpPorts.size():
		return
	_gpPorts[_gpSelPort].gpName = gpT


func _gpOnPortDir(gpI: int) -> void:
	if _gpSelPort < 0 or _gpSelPort >= _gpPorts.size():
		return
	_gpPorts[_gpSelPort].gpDir = _gpDirs[gpI]
	_gpPreview.queue_redraw()


func _gpDeletePort() -> void:
	if _gpSelPort < 0 or _gpSelPort >= _gpPorts.size():
		return
	_gpPorts.remove_at(_gpSelPort)
	_gpSelPort = -1
	_gpSyncPortPanel()
	_gpPreview.queue_redraw()


func _gpDeleteShape() -> void:
	if _gpSelShape < 0 or _gpSelShape >= _gpShapes.size():
		return
	_gpShapes.remove_at(_gpSelShape)
	_gpSelShape = -1
	_gpSyncShapePanel()
	_gpPreview.queue_redraw()


func _gpSetTool(gpTool: int) -> void:
	_gpTool = gpTool
	for gpI in range(_gpToolBtns.size()):
		_gpToolBtns[gpI].button_pressed = (gpI == gpTool)
	if gpTool != GPTool.GP_POLY:
		_gpPolyPts = PackedVector2Array()
	_gpPreview.queue_redraw()


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
func _gpAuthorPorts() -> Array:
	var gpShapesDict: Dictionary = GPShapeSpec.gpEditSpec(_gpShapes)
	var gpBBox: Rect2 = GPSymbolNormalizer.gpComputeBBox(gpShapesDict)
	var gpEnv: Vector2 = GPSymbolCategories.gpSizeFor(_gpCurrentCat())
	# The inverse mapping now lives in one place (GPSymbolNormalizer.gpDenormalizePorts), shared
	# with gpDenormalizeSymbol. Previously this function re-spelled the same algebra, so any
	# future correction to the round-trip would have had to be made twice.
	# 逆映射现收敛到一处（GPSymbolNormalizer.gpDenormalizePorts），与 gpDenormalizeSymbol 共用。
	# 此前本函数把同一套代数又写了一遍，将来任何往返修正都得改两处。
	var gpPortDicts: Array = GPPortSpec.gpToDicts(_gpPorts)
	for gpI in range(gpPortDicts.size()):
		var gpD: Dictionary = gpPortDicts[gpI] as Dictionary
		# An unnamed port still needs a stable name; gpDenormalizePorts only defaults when the
		# key is ABSENT, and GPPort always serializes it (possibly as "").
		# 未命名端口仍需稳定名称；gpDenormalizePorts 仅在键「缺失」时才取默认值，
		# 而 GPPort 总会序列化该键（可能为空串）。
		if str(gpD.get("name", "")) == "":
			gpD["name"] = "p%d" % (gpI + 1)
	return GPSymbolNormalizer.gpDenormalizePorts(gpPortDicts, gpBBox, gpEnv)


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
	var gpTarget: GPSymbolDef = _gpFindExisting(gpName)
	var gpBuiltinHit: bool = gpTarget != null and gpTarget.gpBuiltin

	if gpTarget != null and not gpBuiltinHit:
		# The id is taken by a user symbol: Overwrite is the ONLY available mode and is
		# forced on, so confirming replaces that symbol. New is disabled to keep ids unique.
		# 该 id 已被用户图元占用：覆盖是唯一可用模式并被强制选中，确定即替换该图元；
		# 新建被禁用以保证 id 唯一。
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


# Uniqueness is judged by ID (not display name): the id derived from the internal name is
# looked up directly in the live library — on every keystroke, regardless of mode. The
# display name is a free-form label and may repeat. Built-ins are read-only (decision D3):
# when the id hits a built-in, it is returned so _gpRefreshState/_gpOnOk can refuse.
# 唯一性以标识 id 判定（非显示名）：由内部名称导出的 id 直接到活动库查找——每次输入都查、
# 与模式无关。显示名是自由标签、可重复。内置图元只读（决策 D3）：id 命中内置时原样返回，
# 由 _gpRefreshState/_gpOnOk 拒绝。
func _gpFindExisting(gpName: String) -> GPSymbolDef:
	if gpName == "":
		return null
	return GPSymbolLibrary.gpFindById(_gpIdFromName(gpName))


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

	# Overwrite is decided purely by id: the id derived from the internal name identifies
	# the existing def to replace; New path dedupes via _gpUniqueId to keep ids unique.
	# 覆盖完全由 id 决定：由内部名称导出的 id 定位被替换的已有图元；新建路径经
	# _gpUniqueId 去重以保持 id 唯一。
	var gpTarget: GPSymbolDef = _gpFindExisting(gpName)
	var gpId: String = ""
	if gpOverwrite and gpTarget != null and not gpTarget.gpBuiltin:
		gpId = gpTarget.gpId
	else:
		gpId = _gpUniqueId(gpName)

	# Serialize the edited geometry from the working model (lossless, keeps Bézier handles) plus
	# the edited ports expressed in author-space pixels.
	# 由工作模型序列化编辑后的几何（无损，保留贝塞尔手柄），并附上作者空间像素表达的编辑后端口。
	var gpRaw: Dictionary = {
		"id": gpId,
		"display_name": gpDisplay,
		"category": gpCat,
		"shapes": GPShapeSpec.gpEditSpec(_gpShapes),
		"ports": _gpAuthorPorts(),
		"attrs_schema": {},
	}
	var gpNewDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpRaw, gpCat, {})
	GPSymbolLibrary.gpRegisterDefs([gpNewDef])
	_gpPersist(gpNewDef)
	gpMadeSymbol.emit(gpNewDef.gpId)
	queue_free()


# Filesystem-safe id from a name (CJK kept); non-alphanumerics collapse to "_".
# Delegates to GPIdGen.gpSanitize: the SAME normalization that _gpUniqueId and _gpFindExisting
# rely on, so the id typed by the user is the id matched in the library. Keeping one
# implementation matters because W21/W22 will create ids for documents and cross-references
# from other entry points too.
# 由名称生成文件系统安全 id（中文保留）；非字母数字折叠为 "_"。委托 GPIdGen.gpSanitize：
# 与 _gpUniqueId、_gpFindExisting 使用同一套归一化，保证用户输入的标识即库中匹配的标识。
# 保持单一实现很重要，因为 W21/W22 还会从别的入口为文档与跨图引用生成 id。
func _gpIdFromName(gpName: String) -> String:
	return GPIdGen.gpSanitize(gpName)


# Unique id for creation: normalize the name, then dedupe against the live library with a
# numeric suffix. This is what guarantees id uniqueness on the New path.
# 新建路径的唯一 id：归一化名称后与活动库去重（数字后缀）。此即新建路径的唯一性保障。
func _gpUniqueId(gpName: String) -> String:
	# The predicate is passed as a Callable so the library is queried lazily — no need to
	# materialize every id for the common "free on first try" case.
	# 谓词以 Callable 传入，使图元库被惰性查询——「首次即空闲」的常见情形无需物化全部 id。
	var gpIsTaken: Callable = func(gpCandidate: String) -> bool:
		return GPSymbolLibrary.gpFindById(gpCandidate) != null
	return GPIdGen.gpEnsureUnique(GPIdGen.gpSanitize(gpName), gpIsTaken)


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
