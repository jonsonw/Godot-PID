class_name GPSymbolIsolationLayer
extends Control

# Copyright © 2026 Jonson Wang
# In-place symbol editing, AutoCAD BEDIT style: the P&ID canvas behind stays visible but is
# dimmed and locked, and the symbol's geometry is edited right where it is used.
# 就地图元编辑（AutoCAD BEDIT 风格）：背后的 P&ID 画布保持可见但被淡显并锁定，
# 图元几何就在它被使用的地方直接编辑。
#
# Why this exists: the five-step wizard used to be the only way to change a glyph, which meant
# leaving the drawing, redrawing from scratch and re-exporting. Editing in place keeps the
# author's context (surrounding pipes, neighbours, scale) on screen.
# 为何需要：过去改一个字形只能走五步向导，即离开图纸、从头重画、再导出。就地编辑让作者
# 的上下文（周围管线、邻接图元、比例）始终留在屏幕上。
#
# Host contract / 宿主约定:
#   gpOpenOver(body, canvas, def) -> layer      build over GPCenterArea.gpBody
#   signal gpSaved(symbol_id)                   geometry saved; every instance already repaints
#   signal gpClosed()                           editing abandoned or finished
# Coding rule: every variable must declare its type explicitly (including container types).
# 编码规范：所有变量均显式声明类型（含容器类型）。

# Emitted after the edited geometry was normalized, registered and persisted under the same id.
# 编辑后的几何完成归一化、注册并以同一 id 落盘后发出。
signal gpSaved(gpSymbolId: String)

# Emitted when the layer is about to free itself (saved or cancelled).
# 本层即将释放自身时发出（保存或取消）。
signal gpClosed()

# Background opacity while isolated. Visible but clearly "not the subject" (decision D2).
# 隔离态下背景的不透明度。可见但明确「不是主角」（决策 D2）。
const GP_DIM_ALPHA: float = 0.35

# Layer purpose. GP_MODE_EDIT edits an existing symbol (id preserved on overwrite);
# GP_MODE_CREATE authors a brand-new symbol from a blank canvas.
# 编辑层用途。GP_MODE_EDIT 编辑已有图元（覆盖时 id 不变）；GP_MODE_CREATE 从空白画板
# 新建一个全新图元。
enum GPMode { GP_MODE_EDIT, GP_MODE_CREATE }

# gpDenormalizeSymbol returns unit-box coordinates (0..100), which are far too small to edit
# comfortably. Magnifying the WHOLE author space is normalization-invariant (see
# GPGlyphCanvas.gpLoadShapes), so this factor costs nothing on save.
# gpDenormalizeSymbol 返回单位框坐标（0..100），太小而不便编辑。整体放大作者空间对归一化
# 是不变的（见 GPGlyphCanvas.gpLoadShapes），故该系数在保存时不产生任何代价。
const GP_EDIT_SCALE: float = 3.0

# Comfortable editing area for the glyph canvas.
# 几何画板的舒适编辑区域。
const GP_GLYPH_MIN: Vector2 = Vector2(420, 360)

# Drawing-tool i18n keys, in GPGlyphCanvas.GPTool order (line is appended last at index 5).
# 绘图工具的 i18n 键，顺序同 GPGlyphCanvas.GPTool（直线置于末尾、下标 5）。
const GP_TOOL_KEYS: Array[String] = [
	"symed.tool_polyline", "symed.tool_circle", "symed.tool_rect", "symed.tool_port", "symed.tool_select", "symed.tool_line",
]

# The canvas being isolated: dimmed, locked and restored on close.
# 被隔离的画布：淡显、锁定，关闭时还原。
var gpCanvas: GPCanvas2D = null

# The definition being edited. Its id is preserved on save so placed instances follow.
# 正在编辑的定义。保存时保留其 id，使已放置实例同步跟随。
var gpDef: GPSymbolDef = null

# Edit vs create mode. In create mode the canvas starts blank and saving always authors a new
# symbol; in edit mode the save button may overwrite (user symbols) or only save-as (built-ins).
# 编辑模式还是新建模式。新建模式下画板从空白开始，保存必定新建图元；编辑模式下保存按钮
# 可覆盖（用户图元）或仅能另存为（内置图元）。
var gpMode: GPMode = GPMode.GP_MODE_EDIT

# Whether overwriting the original id is allowed. Always false for built-in (read-only) symbols.
# 是否允许覆盖原 id。内置（只读）图元恒为 false。
var gpAllowOverwrite: bool = false

# Geometry canvas hosting the glyph.
# 承载字形的几何画板。
var gpGlyph: GPGlyphCanvas = null

# Title / hint / action widgets kept for locale refresh.
# 标题 / 提示 / 动作控件，保留以便刷新语言。
var gpTitleLabel: Label = null
var gpHintLabel: Label = null
var gpSaveBtn: Button = null
var gpCancelBtn: Button = null
var gpBgBtn: Button = null

# Drawing-tool toggle row.
# 绘图工具开关行。
var gpToolRow: HBoxContainer = null
var gpToolBtns: Array[Button] = []


# ============================ factory / lifecycle ============================
# ============================ 工厂 / 生命周期 ============================
# Open an isolation layer over gpBody, dimming and locking gpCanvas behind it.
# 在 gpBody 之上打开隔离层，并把 gpCanvas 淡显锁定在后面。
# Mount on GPCenterArea.gpBody (a Control), never on the enclosing VBoxContainer: adding to a
# container would make the layer a laid-out child and squeeze the canvas instead of covering it.
# 必须挂在 GPCenterArea.gpBody（Control）上，而非外层 VBoxContainer：加进容器会让它变成
# 参与布局的子项，从而挤压画布而不是覆盖它。
static func gpOpenOver(gpBody: Control, gpHost: GPCanvas2D, gpDefIn: GPSymbolDef, gpCreate: bool = false, gpInitialTool: int = GPGlyphCanvas.GPTool.GP_SELECT, gpSeedShapes: Dictionary = {}) -> GPSymbolIsolationLayer:
	if gpBody == null or gpHost == null:
		return null
	var gpLayer: GPSymbolIsolationLayer = GPSymbolIsolationLayer.new()
	gpLayer.name = "SymbolIsolationLayer"
	gpBody.add_child(gpLayer)
	gpLayer.gpSetup(gpHost, gpDefIn, gpCreate, gpInitialTool, gpSeedShapes)
	return gpLayer


# Convenience factory for the "New Symbol…" flow: a blank canvas that authors a fresh symbol.
# The gpInitialTool pre-selects the drawing tool so a toolbar click opens straight into it.
# When gpSeedShapes is supplied (from promoting annotation shapes on the main canvas) the
# glyph canvas opens pre-loaded with that geometry, so the user edits an existing drawing
# instead of starting from scratch.
# 「新建图元…」流程的便捷工厂：空白画板，用于从零创作全新图元。gpInitialTool 预选绘图工具，
# 使工具栏点击后直接进入该工具。传入 gpSeedShapes（从主画布「提升」注释图形时）会让几何画板
# 预装该几何，使用户编辑既有绘图而非从零开始。
static func gpOpenCreate(gpBody: Control, gpHost: GPCanvas2D, gpInitialTool: int = GPGlyphCanvas.GPTool.GP_SELECT, gpSeedShapes: Dictionary = {}) -> GPSymbolIsolationLayer:
	return gpOpenOver(gpBody, gpHost, null, true, gpInitialTool, gpSeedShapes)


# Build the UI, load the geometry and isolate the host canvas.
# 构建界面、载入几何并隔离宿主画布。
func gpSetup(gpHost: GPCanvas2D, gpDefIn: GPSymbolDef, gpCreate: bool = false, gpInitialTool: int = GPGlyphCanvas.GPTool.GP_SELECT, gpSeedShapes: Dictionary = {}) -> void:
	gpCanvas = gpHost
	gpMode = GPMode.GP_MODE_CREATE if gpCreate else GPMode.GP_MODE_EDIT
	if gpDefIn == null:
		# Blank definition for the new-symbol flow (geometry is drawn from scratch).
		# 新建图元流程的空白定义（几何从零绘制）。
		gpDefIn = GPSymbolDef.new()
		gpDefIn.gpCategory = "general"
		gpDefIn.gpDefaultSize = GPSymbolCategories.gpSizeFor("general")
	gpDef = gpDefIn
	# A symbol can be overwritten only when it is user-authored (not a built-in ISO symbol).
	# Derived custom_<id> copies are user-authored, so the user may overwrite them.
	# 仅当用户自建图元（非内置 ISO）时允许覆盖。派生的 custom_<id> 副本属用户图元，故可覆盖。
	gpAllowOverwrite = not gpDef.gpBuiltin
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)
	# Absorb every click so the locked canvas cannot be reached by accident.
	# 吸收所有点击，使被锁定的画布无法被误触。
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process_input(true)

	_gpBuildUi()
	# Pre-select the requested drawing tool (e.g. straight line) so the editor opens ready to draw.
	# 预选请求的绘图工具（如直线），使编辑器打开即处于可绘制状态。
	gpGlyph.gpSetTool(gpInitialTool)
	_gpLoadGeometry()
	# When creating from promoted annotation shapes, pre-load the same geometry so the user
	# edits the existing drawing instead of starting blank. Normalization only keeps relative
	# geometry, so absolute position is irrelevant.
	# 由「提升」的注释图形新建时，预装相同几何，使用户编辑既有绘图而非空白开始。归一化只保留
	# 相对几何，故绝对位置无关紧要。
	if gpMode == GPMode.GP_MODE_CREATE and not gpSeedShapes.is_empty():
		gpGlyph.gpLoadShapes(gpSeedShapes)

	# Dim + lock: modulate keeps the drawing readable as context, MOUSE_FILTER_IGNORE makes it
	# inert. (A bare `disabled` flag does not exist for Control, and hiding loses the context.)
	# 淡显 + 锁定：modulate 让图纸作为上下文仍可读，MOUSE_FILTER_IGNORE 使其失去响应。
	#（Control 没有 `disabled` 开关，而隐藏会丢掉上下文。）
	gpCanvas.modulate.a = GP_DIM_ALPHA
	gpCanvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gpGlyph.grab_focus()


# Build the shade, the editing panel and both control rows.
# 构建遮罩、编辑面板与两行控件。
func _gpBuildUi() -> void:
	var gpShade: ColorRect = ColorRect.new()
	gpShade.name = "Shade"
	gpShade.set_anchors_preset(Control.PRESET_FULL_RECT)
	gpShade.color = Color(0.04, 0.05, 0.08, 0.55)
	# IGNORE lets clicks fall through to this layer, which STOPs them.
	# IGNORE 让点击穿透到本层，由本层 STOP 吸收。
	gpShade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gpShade)

	var gpPanel: PanelContainer = PanelContainer.new()
	gpPanel.set_anchors_preset(Control.PRESET_CENTER)
	gpPanel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	gpPanel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(gpPanel)

	var gpRoot: VBoxContainer = VBoxContainer.new()
	gpRoot.add_theme_constant_override("separation", 8)
	gpPanel.add_child(gpRoot)

	gpTitleLabel = Label.new()
	gpRoot.add_child(gpTitleLabel)

	gpGlyph = GPGlyphCanvas.new()
	gpGlyph.custom_minimum_size = GP_GLYPH_MIN
	gpGlyph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpRoot.add_child(gpGlyph)
	gpGlyph.gpToolChanged.connect(_gpSyncToolRow)
	# Right-click "Create Symbol" inside the glyph canvas: author a NEW symbol from the
	# current geometry (save-as in edit mode, a fresh symbol in create mode).
	# 几何画板内右键「生成图元」：用当前几何新建一个图元（编辑模式为另存为，新建模式为全新图元）。
	gpGlyph.gpCreateRequested.connect(_gpOnCreateRequested)

	gpHintLabel = Label.new()
	gpHintLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpHintLabel.custom_minimum_size = Vector2(400.0, 0.0)
	gpRoot.add_child(gpHintLabel)

	# Drawing tools as visible toggles — a bare dropdown reads as plain text and hides the
	# Select / Edit tool, which is exactly how the feature went unnoticed before.
	# 绘图工具做成可见开关 —— 纯下拉框看着就是普通文字，会藏起「选择 / 编辑」工具，
	# 该功能此前正是因此被忽略。
	gpToolRow = HBoxContainer.new()
	gpToolRow.add_theme_constant_override("separation", 4)
	gpRoot.add_child(gpToolRow)
	for gpI in range(GP_TOOL_KEYS.size()):
		var gpBtn: Button = Button.new()
		gpBtn.toggle_mode = true
		gpBtn.pressed.connect(_gpOnToolButton.bind(gpI))
		gpToolRow.add_child(gpBtn)
		gpToolBtns.append(gpBtn)

	var gpBtnRow: HBoxContainer = HBoxContainer.new()
	gpBtnRow.add_theme_constant_override("separation", 6)
	gpRoot.add_child(gpBtnRow)

	gpSaveBtn = Button.new()
	gpSaveBtn.pressed.connect(_gpOnSaveBtn)
	gpBtnRow.add_child(gpSaveBtn)

	gpCancelBtn = Button.new()
	gpCancelBtn.pressed.connect(_gpClose)
	gpBtnRow.add_child(gpCancelBtn)

	gpBgBtn = Button.new()
	gpBgBtn.toggle_mode = true
	gpBgBtn.button_pressed = false
	gpBgBtn.toggled.connect(_gpOnBgToggled)
	gpBtnRow.add_child(gpBgBtn)

	gpGlyph.gpSetTool(4)
	_gpSyncToolRow()
	_gpRefreshText()


# Set every locale-dependent string.
# 设置所有依赖语言的文本。
func _gpRefreshText() -> void:
	if gpMode == GPMode.GP_MODE_CREATE:
		gpTitleLabel.text = I18n.gpTr("symed.new_title")
		gpHintLabel.text = I18n.gpTr("symed.create_hint")
	else:
		gpTitleLabel.text = "%s：%s（%s）" % [I18n.gpTr("iso.title"), I18n.gpTr(gpDef.gpDisplayName), gpDef.gpId]
		gpHintLabel.text = I18n.gpTr("iso.hint")
	for gpI in range(gpToolBtns.size()):
		gpToolBtns[gpI].text = I18n.gpTr(GP_TOOL_KEYS[gpI])
	# Save-button label reflects the available save scope.
	# 保存按钮文案反映可执行的保存范围。
	if gpMode == GPMode.GP_MODE_CREATE:
		gpSaveBtn.text = I18n.gpTr("iso.create")
	elif gpAllowOverwrite:
		gpSaveBtn.text = I18n.gpTr("iso.save")
	else:
		gpSaveBtn.text = I18n.gpTr("iso.save_as")
	gpCancelBtn.text = I18n.gpTr("iso.cancel")
	gpBgBtn.text = I18n.gpTr("iso.hide_bg")


# ============================ geometry load / save ============================
# ============================ 几何载入 / 保存 ============================
# Load the symbol's canonical geometry back into an editable author-space draft.
# 把图元的规范化几何重新载入为可编辑的作者空间草稿。
func _gpLoadGeometry() -> void:
	if gpMode == GPMode.GP_MODE_CREATE:
		# Blank canvas: nothing to load; just size the guide rectangle for the default category.
		# 空白画板：无需载入；仅为默认类目设置参考框尺寸。
		gpGlyph.gpSetEnvelope(gpDef.gpDefaultSize)
		return
	var gpDraft: Dictionary = GPSymbolNormalizer.gpDenormalizeSymbol(gpDef)
	var gpShapes: Dictionary = (gpDraft.get("shapes", {}) as Dictionary).duplicate(true)
	var gpPortsIn: Array = (gpDraft.get("ports", []) as Array).duplicate(true)
	gpShapes = _gpScaleShapes(gpShapes, GP_EDIT_SCALE)
	gpPortsIn = _gpScalePorts(gpPortsIn, GP_EDIT_SCALE)
	# The envelope drives the guide rectangle's aspect ratio only; it is not the drawing frame.
	# 包络仅决定参考框的宽高比，不是绘图坐标系。
	gpGlyph.gpSetEnvelope(gpDef.gpDefaultSize)
	gpGlyph.gpLoadShapes(gpShapes)
	gpGlyph.gpLoadPorts(gpPortsIn)


# Normalize the draft under the ORIGINAL id and re-register it.
# 以原始 id 归一化草稿并重新注册。
# Keeping the id is what makes every placed instance follow: gpRegisterDefs swaps the
# GPSymbolDef object behind that id, and GPGraphBinder rebinds gpDef on the next sync.
# 保留 id 正是「所有已放置实例同步跟随」的原因：gpRegisterDefs 会替换该 id 背后的
# GPSymbolDef 对象，而 GPGraphBinder 在下次同步时重绑 gpDef。
# Save-button dispatcher: route to overwrite / save-as / create per the current mode.
# 保存按钮分发：按当前模式路由到覆盖 / 另存为 / 新建。
func _gpOnSaveBtn() -> void:
	if gpMode == GPMode.GP_MODE_CREATE:
		_gpOpenNameDialog()
		return
	if gpAllowOverwrite:
		_gpOpenSaveMenu()
	else:
		# Built-in symbols are read-only: only "save as new" is offered.
		# 内置图元只读：仅提供「另存为新图元」。
		_gpOpenNameDialog()


# Overwrite the original id: normalize + re-register under the SAME id so every placed
# instance repaints. Only reachable for user-authored symbols (gpAllowOverwrite).
# 覆盖原 id：以同一 id 归一化 + 重新注册，使所有已放置实例重绘。仅用户图元可达（gpAllowOverwrite）。
func _gpCommitOverwrite() -> void:
	var gpRaw: Dictionary = {
		"id": gpDef.gpId,
		"display_name": gpDef.gpDisplayName,
		"category": gpDef.gpCategory,
		"shapes": gpGlyph.gpGetDraftShapes(),
		"ports": gpGlyph.gpGetDraftPorts(),
		"attrs_schema": gpDef.gpAttrsSchema.duplicate(true),
	}
	var gpNewDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpRaw, gpDef.gpCategory, {})
	GPSymbolLibrary.gpRegisterDefs([gpNewDef])
	_gpPersist(gpNewDef)
	gpSaved.emit(gpNewDef.gpId)
	_gpClose()


# Offer overwrite (0) and save-as (1) from the save button; built-ins skip item 0.
# 在保存按钮处提供「覆盖(0) / 另存为(1)」；内置图元无第 0 项。
func _gpOpenSaveMenu() -> void:
	var gpMenu: PopupMenu = PopupMenu.new()
	if gpAllowOverwrite:
		gpMenu.add_item(I18n.gpTr("iso.overwrite") % gpDef.gpId, 0)
	gpMenu.add_item(I18n.gpTr("iso.save_as"), 1)
	gpMenu.id_pressed.connect(_gpOnSaveMenuPick)
	add_child(gpMenu)
	# popup() uses GLOBAL SCREEN coordinates when popups are NOT embedded (embed_subwindows=false, the
	# default). The save button's canvas-global position is converted through the viewport's screen
	# transform to WINDOW-LOCAL pixels, then the main window's screen position is added for the true
	# screen coordinate, so the menu drops down from the button instead of snapping to a screen corner.
	# The (0,28) nudge places it just below the button (Godot-CAD reference pattern).
	# popup() 在「非嵌入」（默认值）时取「全局屏幕」坐标。把按钮的画布全局位置经视口屏幕变换换算为「窗口内」
	# 像素，再叠加主窗口屏幕位置得到真实屏幕坐标，菜单从按钮正下方展开而非飞到角落。(0,28) 使其落在按钮下方
	# （即 Godot-CAD 参考实现做法）。
	var gpBtnWin: Vector2 = get_viewport().get_screen_transform() * gpSaveBtn.get_global_position()
	gpMenu.position = Vector2i(get_window().position) + Vector2i(gpBtnWin) + Vector2i(0, 28)
	gpMenu.popup()
	gpMenu.popup_hide.connect(gpMenu.queue_free)


# Dispatch the save-options popup.
# 分发保存选项弹出菜单。
func _gpOnSaveMenuPick(gpId: int) -> void:
	if gpId == 0:
		_gpCommitOverwrite()
	else:
		_gpOpenNameDialog()


# Right-click "Create Symbol" inside the glyph canvas: author a NEW symbol from the current
# geometry (save-as in edit mode, a fresh symbol in create mode).
# 几何画板内右键「生成图元」：用当前几何新建图元（编辑模式另存为，新建模式为全新图元）。
func _gpOnCreateRequested() -> void:
	_gpOpenNameDialog()


# Build the name + category dialog that finalizes a new symbol (create mode or save-as).
# 构建「名称 + 类目」对话框，用于新建图元（新建模式或另存为）的最终点确认。
func _gpOpenNameDialog() -> void:
	var gpIsNew: bool = (gpMode == GPMode.GP_MODE_CREATE)
	var gpDlg: PanelContainer = PanelContainer.new()
	gpDlg.name = "NameDialog"
	gpDlg.set_anchors_preset(Control.PRESET_CENTER)
	gpDlg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	gpDlg.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(gpDlg)

	var gpV: VBoxContainer = VBoxContainer.new()
	gpV.add_theme_constant_override("separation", 8)
	gpDlg.add_child(gpV)

	var gpTitle: Label = Label.new()
	gpTitle.text = I18n.gpTr("symed.new_title" if gpIsNew else "symed.save_as_title")
	gpV.add_child(gpTitle)

	var gpNameEdit: LineEdit = LineEdit.new()
	gpNameEdit.placeholder_text = I18n.gpTr("symed.name_ph")
	if not gpIsNew:
		gpNameEdit.text = gpDef.gpDisplayName
	gpNameEdit.custom_minimum_size = Vector2(360.0, 0.0)
	gpV.add_child(gpNameEdit)

	var gpCatKeys: Array[String] = GPSymbolCategories.gpCategoryList()
	var gpCatBtn: OptionButton = OptionButton.new()
	for gpC in gpCatKeys:
		gpCatBtn.add_item(I18n.gpTr(gpC))
	gpCatBtn.custom_minimum_size = Vector2(360.0, 0.0)
	var gpSelIdx: int = gpCatKeys.find(gpDef.gpCategory)
	if gpSelIdx < 0:
		gpSelIdx = gpCatKeys.find("general")
	if gpSelIdx < 0:
		gpSelIdx = 0
	gpCatBtn.selected = gpSelIdx
	gpV.add_child(gpCatBtn)

	var gpIdPreview: Label = Label.new()
	gpV.add_child(gpIdPreview)
	var gpUpdatePreview: Callable = func() -> void:
		gpIdPreview.text = I18n.gpTr("symed.id_preview") % _gpMakeUniqueId(gpNameEdit.text.strip_edges())
	gpNameEdit.text_changed.connect(func(_gpT: String) -> void: gpUpdatePreview.call())
	gpUpdatePreview.call()

	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 6)
	var gpOk: Button = Button.new()
	gpOk.text = I18n.gpTr("symed.dialog_ok")
	var gpCancel: Button = Button.new()
	gpCancel.text = I18n.gpTr("symed.dialog_cancel")
	gpRow.add_child(gpOk)
	gpRow.add_child(gpCancel)
	gpV.add_child(gpRow)

	gpOk.pressed.connect(func() -> void: _gpOnNameOk(gpDlg, gpNameEdit, gpCatBtn, gpCatKeys))
	gpCancel.pressed.connect(func() -> void: gpDlg.queue_free())
	gpNameEdit.grab_focus()


# Finalize a new symbol from the dialog: unique id + normalize + register + persist + emit.
# 由对话框落定新图元：唯一 id + 归一化 + 注册 + 持久化 + 发出信号。
func _gpOnNameOk(gpDlg: PanelContainer, gpNameEdit: LineEdit, gpCatBtn: OptionButton, gpCatKeys: Array[String]) -> void:
	var gpName: String = gpNameEdit.text.strip_edges()
	if gpName == "":
		# Reject an empty name but keep the dialog open with an inline hint.
		# 名称为空则拒绝，并就地提示，保持对话框打开。
		gpNameEdit.placeholder_text = I18n.gpTr("symed.name_empty")
		gpNameEdit.grab_focus()
		return
	var gpCat: String = "general"
	if gpCatBtn.selected >= 0 and gpCatBtn.selected < gpCatKeys.size():
		gpCat = gpCatKeys[gpCatBtn.selected]
	var gpId: String = _gpMakeUniqueId(gpName)
	var gpRaw: Dictionary = {
		"id": gpId,
		"display_name": gpName,
		"category": gpCat,
		"shapes": gpGlyph.gpGetDraftShapes(),
		"ports": gpGlyph.gpGetDraftPorts(),
		"attrs_schema": gpDef.gpAttrsSchema.duplicate(true),
	}
	var gpNewDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpRaw, gpCat, {})
	GPSymbolLibrary.gpRegisterDefs([gpNewDef])
	_gpPersist(gpNewDef)
	gpDlg.queue_free()
	gpSaved.emit(gpNewDef.gpId)
	_gpClose()


# Build a filesystem-safe, library-unique id from a display name (CJK kept as-is).
# 由显示名生成「文件系统安全、图元库内唯一」的 id（中文原样保留）。
static func _gpMakeUniqueId(gpName: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpName.length()):
		var gpC: String = gpName.substr(gpI, 1)
		var gpU: int = gpC.unicode_at(0)
		# Keep CJK, alphanumerics and underscore; fold spaces / punctuation into "_".
		# 保留中文、字母数字与下划线；空格与标点折叠为 "_"。
		var gpCJK: bool = (gpU >= 0x3400 and gpU <= 0x4DBF) or (gpU >= 0x4E00 and gpU <= 0x9FFF)
		if gpCJK or (gpU >= 48 and gpU <= 57) or (gpU >= 65 and gpU <= 90) or (gpU >= 97 and gpU <= 122) or gpC == "_":
			gpOut += gpC
		else:
			gpOut += "_"
	if gpOut == "":
		gpOut = "symbol"
	# Disambiguate against any existing id in the live library.
	# 与活动图元库中已有 id 消歧。
	var gpCandidate: String = gpOut
	var gpN: int = 2
	while GPSymbolLibrary.gpFindById(gpCandidate) != null:
		gpCandidate = "%s_%d" % [gpOut, gpN]
		gpN += 1
	return gpCandidate


# Persist the definition as a user pack so the edit survives an app restart.
# 把定义持久化为用户图元包，使本次编辑在重启后依然有效。
func _gpPersist(gpNewDef: GPSymbolDef) -> void:
	var gpDir: String = GPSymbolLibrary.GP_USER_PACKS_DIR
	if not DirAccess.dir_exists_absolute(gpDir):
		DirAccess.make_dir_recursive_absolute(gpDir)
	var gpPack: GPSymbolPack = GPSymbolPack.new()
	gpPack.gpPackId = "user_%s" % gpNewDef.gpId
	gpPack.gpName = gpNewDef.gpDisplayName
	gpPack.gpVersion = "1.0"
	gpPack.gpSymbols = [gpNewDef]
	var gpPath: String = "%s/%s.json" % [gpDir, gpNewDef.gpId]
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.WRITE)
	if gpF == null:
		push_warning("GPSymbolIsolationLayer: cannot write %s" % gpPath)
		return
	gpF.store_string(JSON.stringify(gpPack.gpToDict(), "", true))
	gpF.close()


# ============================ tools ============================
# ============================ 工具 ============================
func _gpOnToolButton(gpToolId: int) -> void:
	gpGlyph.gpSetTool(gpToolId)


# Mirror the canvas's current tool onto the toggle row (also covers canvas-initiated changes).
# 把画布当前工具反映到开关行（同时覆盖画布端发起的变更）。
func _gpSyncToolRow() -> void:
	var gpCur: int = int(gpGlyph.gpTool)
	for gpI in range(gpToolBtns.size()):
		gpToolBtns[gpI].button_pressed = (gpI == gpCur)


# D2: default is a faint, inert ghost; the toggle switches the background fully off.
# D2：默认为淡显的静态底图；开关可把背景完全关闭。
func _gpOnBgToggled(gpHidden: bool) -> void:
	if gpCanvas == null or not is_instance_valid(gpCanvas):
		return
	gpCanvas.visible = not gpHidden
	gpCanvas.modulate.a = GP_DIM_ALPHA


# ============================ close ============================
# ============================ 关闭 ============================
# ESC is progressive: while the glyph still owns local state (a selection, or a non-select
# tool that may hold a half-drawn primitive) the key is left to the glyph canvas; only an
# idle editor closes.
# ESC 是渐进式的：当画板仍持有局部状态（选择集，或可能握着半截图元的非选择工具）时，
# 按键留给几何画板处理；只有空闲的编辑器才会关闭。
func _input(gpEvent: InputEvent) -> void:
	if not (gpEvent is InputEventKey):
		return
	var gpKey: InputEventKey = gpEvent as InputEventKey
	if not gpKey.pressed or gpKey.echo or gpKey.keycode != KEY_ESCAPE:
		return
	if gpGlyph != null:
		if not gpGlyph.gpSelection.is_empty():
			return
		if int(gpGlyph.gpTool) != 4:
			return
	get_viewport().set_input_as_handled()
	_gpClose()


# Restore the host canvas and free the layer.
# 还原宿主画布并释放本层。
func _gpClose() -> void:
	_gpRestoreHost()
	gpClosed.emit()
	queue_free()


# Undo the dim + lock applied in gpSetup().
# 撤销 gpSetup() 施加的淡显与锁定。
func _gpRestoreHost() -> void:
	if gpCanvas != null and is_instance_valid(gpCanvas):
		gpCanvas.modulate.a = 1.0
		gpCanvas.mouse_filter = Control.MOUSE_FILTER_STOP
		gpCanvas.visible = true
		gpCanvas.queue_redraw()
	gpCanvas = null


# ============================ static helpers ============================
# ============================ 静态辅助 ============================
# Uniformly magnify a shape dict. Normalization-invariant, so it is lossless on save.
# 统一放大形状字典。对归一化不变，故保存时无损。
static func _gpScaleShapes(gpShapes: Dictionary, gpK: float) -> Dictionary:
	var gpPaths: Array = []
	for gpP in (gpShapes.get("paths", []) as Array):
		var gpPd: Dictionary = gpP as Dictionary
		var gpPts: Array = []
		for gpPair in (gpPd.get("pts", []) as Array):
			gpPts.append([float(gpPair[0]) * gpK, float(gpPair[1]) * gpK])
		gpPaths.append({"pts": gpPts, "closed": bool(gpPd.get("closed", false))})
	var gpCircles: Array = []
	for gpC in (gpShapes.get("circles", []) as Array):
		var gpCd: Dictionary = gpC as Dictionary
		var gpCc: Array = gpCd.get("c", [0.0, 0.0]) as Array
		gpCircles.append({
			"c": [float(gpCc[0]) * gpK, float(gpCc[1]) * gpK],
			"r": absf(float(gpCd.get("r", 1.0))) * gpK,
		})
	var gpRects: Array = []
	for gpR in (gpShapes.get("rects", []) as Array):
		var gpRd: Dictionary = gpR as Dictionary
		var gpPos: Array = gpRd.get("pos", [0.0, 0.0]) as Array
		var gpSz: Array = gpRd.get("size", [0.0, 0.0]) as Array
		gpRects.append({
			"pos": [float(gpPos[0]) * gpK, float(gpPos[1]) * gpK],
			"size": [float(gpSz[0]) * gpK, float(gpSz[1]) * gpK],
		})
	return {"paths": gpPaths, "circles": gpCircles, "rects": gpRects}


# Uniformly magnify author-space port positions (same frame as the shapes).
# 统一放大作者空间的端口坐标（与形状同一坐标系）。
static func _gpScalePorts(gpPortsIn: Array, gpK: float) -> Array:
	var gpOut: Array = []
	for gpP in gpPortsIn:
		var gpPd: Dictionary = gpP as Dictionary
		var gpPos: Array = gpPd.get("pos", [0.5, 0.5]) as Array
		gpOut.append({
			"name": str(gpPd.get("name", "p%d" % (gpOut.size() + 1))),
			"pos": [float(gpPos[0]) * gpK, float(gpPos[1]) * gpK],
			"dir": gpPd.get("dir", [0.0, 0.0]),
		})
	return gpOut
