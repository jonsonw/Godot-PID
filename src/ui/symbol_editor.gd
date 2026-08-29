class_name GPSymbolEditor
extends Window

# Copyright © 2026 Jonson Wang
# Foolproof symbol editor: a five-step wizard that produces a GPSymbolPack without touching code.
# 傻瓜式图元编辑器：五步向导，不动代码即可产出 GPSymbolPack。
# Steps / 步骤:
#   1. pick a category      选类目
#   2. draw the glyph       画字形
#   3. fill the attr schema 填属性 schema
#   4. fill the standard ref 填标准出处
#   5. export               导出
# The category decides the nominal envelope, so every symbol of a family ends up equal-sized;
# GPSymbolNormalizer does the uniform fit and the 0..1 port normalization on export.
# 类目决定标称包络，因此同族图元最终恒为等大；导出时由 GPSymbolNormalizer 完成均匀缩放
# 与 0..1 端口归一化。
# See 符号编辑器设计说明 §5 / §6 / §7 / §9.
# 见《符号编辑器设计说明》§5 / §6 / §7 / §9。
# Layout lives in res://scenes/symbol_editor.tscn (editable in the editor); this script only
# wires signals, fills dynamic data and drives the wizard state.
# 布局保存在 res://scenes/symbol_editor.tscn（可在编辑器内可视化修改）；本脚本只负责接线、
# 填充动态数据并驱动向导状态。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# A SymbolPack was exported.
# 图元包导出完成。
signal gpPackExported(gpPack: GPSymbolPack)

# Wizard step count.
# 向导步骤总数。
const GP_STEP_COUNT: int = 5

# Directory the exported packs are written to.
# 导出图元包的写入目录。
const GP_EXPORT_DIR: String = "user://symbol_packs"

# Attribute schema value types offered in step 3.
# 第 3 步提供的属性 schema 值类型。
const GP_ATTR_TYPES: Array[String] = ["string", "float", "int", "bool"]

# Standard reference presets offered in step 4.
# 第 4 步提供的标准出处预设。
const GP_STD_PRESETS: Array[String] = [
	"ISA-5.1-2022",
	"ISO 10628-2",
	"GB/T 6567.2-2008",
	"HG/T 20519-2009",
]

# Wizard step i18n keys, in order.
# 向导各步骤的 i18n 键，按顺序排列。
const GP_STEP_KEYS: Array[String] = [
	"symed.step1", "symed.step2", "symed.step3", "symed.step4", "symed.step5",
]

# Smallest / largest window the wizard layout is comfortable in, in logical UI units. The actual
# window size is derived from these plus the area the dialog pops up in — see GPWindowFit.
# The minimum is deliberately modest: as an embedded subwindow the wizard lives inside the host's
# logical viewport, which on this project is only ~800x500 units, so a 900x620 minimum could not
# fit at all and pushed the window to a negative position (blank, screen-filling dialog).
# 向导布局的最小 / 最大舒适尺寸，单位为逻辑 UI 单位。实际窗口尺寸由二者结合弹出所在区域推导
# ——见 GPWindowFit。最小值刻意取小：作为嵌入式子窗口，向导活在宿主的逻辑视口内，本项目该视口
# 仅约 800x500 单位，故 900x620 的下限根本放不下，会把窗口顶到负坐标（表现为空白且铺满的对话框）。
const GP_MIN_LOGICAL: Vector2i = Vector2i(560, 400)
const GP_MAX_LOGICAL: Vector2i = Vector2i(1280, 860)

# The wizard is dense (step rail + page + live preview), so it opens as large as it is allowed to
# be rather than at the default fraction.
# 向导内容密集（步骤栏 + 页面 + 实时预览），故按允许的最大比例打开，而非默认比例。
const GP_SELF_FRAC: Vector2 = Vector2(0.94, 0.94)

# Preloaded rather than referenced by class_name: cross-script class_name lookups can fail
# depending on script load order (see CONTRIBUTING notes).
# 用 preload 而非 class_name 引用：跨脚本的 class_name 查找会因脚本加载顺序而失败（见贡献说明）。
const GP_WINDOW_FIT := preload("res://src/ui/window_fit.gd")

# Current wizard step, 0-based.
# 当前向导步骤，从 0 开始。
var gpStep: int = 0

# Screen index the window was last measured against, so a monitor change can be detected.
# 上次测量所参照的屏幕索引，用于检测显示器切换。
var gpLastScreen: int = -1

# Step page containers; exactly one is visible at a time.
# 步骤页容器；同一时刻仅一个可见。
@onready var gpPages: Array[Control] = [
	$Panel/Margin/Root/Body/Center/PageCategory,
	$Panel/Margin/Root/Body/Center/PageGlyph,
	$Panel/Margin/Root/Body/Center/PageAttrs,
	$Panel/Margin/Root/Body/Center/PageStandard,
	$Panel/Margin/Root/Body/Center/PageExport,
]

# Step indicator labels in the left rail.
# 左侧导航栏中的步骤指示标签。
@onready var gpStepLabels: Array[Label] = [
	$Panel/Margin/Root/Body/Rail/Step0,
	$Panel/Margin/Root/Body/Rail/Step1,
	$Panel/Margin/Root/Body/Rail/Step2,
	$Panel/Margin/Root/Body/Rail/Step3,
	$Panel/Margin/Root/Body/Rail/Step4,
]

# Header title label.
# 头部标题标签。
@onready var gpTitleLabel: Label = $Panel/Margin/Root/Header/TitleLabel

# Header step badge, e.g. "2 / 5".
# 头部步骤徽标，如 "2 / 5"。
@onready var gpBadgeLabel: Label = $Panel/Margin/Root/Header/BadgeLabel

# Footer hint / error line.
# 底部提示 / 错误行。
@onready var gpHintLabel: Label = $Panel/Margin/Root/Footer/HintLabel

# Footer navigation buttons.
# 底部导航按钮。
@onready var gpPrevBtn: Button = $Panel/Margin/Root/Footer/PrevBtn
@onready var gpNextBtn: Button = $Panel/Margin/Root/Footer/NextBtn
@onready var gpExportBtn: Button = $Panel/Margin/Root/Footer/ExportBtn
@onready var gpCloseBtn: Button = $Panel/Margin/Root/Footer/CloseBtn

# --- step 1 widgets / 第 1 步控件 ---
@onready var gpCatOption: OptionButton = $Panel/Margin/Root/Body/Center/PageCategory/Grid/CatOption
@onready var gpIdEdit: LineEdit = $Panel/Margin/Root/Body/Center/PageCategory/Grid/IdEdit
@onready var gpNameEdit: LineEdit = $Panel/Margin/Root/Body/Center/PageCategory/Grid/NameEdit
@onready var gpEnvLabel: Label = $Panel/Margin/Root/Body/Center/PageCategory/Grid/EnvLabel
@onready var gpCatLabel: Label = $Panel/Margin/Root/Body/Center/PageCategory/Grid/CatLabel
@onready var gpIdLabel: Label = $Panel/Margin/Root/Body/Center/PageCategory/Grid/IdLabel
@onready var gpNameLabel: Label = $Panel/Margin/Root/Body/Center/PageCategory/Grid/NameLabel
@onready var gpEnvCaption: Label = $Panel/Margin/Root/Body/Center/PageCategory/Grid/EnvCaption

# --- step 2 widgets / 第 2 步控件 ---
@onready var gpToolOption: OptionButton = $Panel/Margin/Root/Body/Center/PageGlyph/Bar/ToolOption
@onready var gpToolLabel: Label = $Panel/Margin/Root/Body/Center/PageGlyph/Bar/ToolLabel
@onready var gpSnapCheck: CheckBox = $Panel/Margin/Root/Body/Center/PageGlyph/Bar/SnapCheck
@onready var gpFinishBtn: Button = $Panel/Margin/Root/Body/Center/PageGlyph/Bar/FinishBtn
@onready var gpUndoBtn: Button = $Panel/Margin/Root/Body/Center/PageGlyph/Bar/UndoBtn
@onready var gpClearBtn: Button = $Panel/Margin/Root/Body/Center/PageGlyph/Bar/ClearBtn
@onready var gpGlyph: GPGlyphCanvas = $Panel/Margin/Root/Body/Center/PageGlyph/Glyph
@onready var gpDrawHint: Label = $Panel/Margin/Root/Body/Center/PageGlyph/DrawHint

# --- step 3 widgets / 第 3 步控件 ---
@onready var gpAttrKeyEdit: LineEdit = $Panel/Margin/Root/Body/Center/PageAttrs/Row/AttrKeyEdit
@onready var gpAttrTypeOption: OptionButton = $Panel/Margin/Root/Body/Center/PageAttrs/Row/AttrTypeOption
@onready var gpAttrDefEdit: LineEdit = $Panel/Margin/Root/Body/Center/PageAttrs/Row/AttrDefEdit
@onready var gpAttrAddBtn: Button = $Panel/Margin/Root/Body/Center/PageAttrs/Row/AttrAddBtn
@onready var gpAttrDelBtn: Button = $Panel/Margin/Root/Body/Center/PageAttrs/Row/AttrDelBtn
@onready var gpAttrList: ItemList = $Panel/Margin/Root/Body/Center/PageAttrs/AttrList
@onready var gpAttrHint: Label = $Panel/Margin/Root/Body/Center/PageAttrs/AttrHint

# --- step 4 widgets / 第 4 步控件 ---
@onready var gpPackIdEdit: LineEdit = $Panel/Margin/Root/Body/Center/PageStandard/Grid/PackIdEdit
@onready var gpPackNameEdit: LineEdit = $Panel/Margin/Root/Body/Center/PageStandard/Grid/PackNameEdit
@onready var gpStdOption: OptionButton = $Panel/Margin/Root/Body/Center/PageStandard/Grid/StdRow/StdOption
@onready var gpStdEdit: LineEdit = $Panel/Margin/Root/Body/Center/PageStandard/Grid/StdRow/StdEdit
@onready var gpVersionEdit: LineEdit = $Panel/Margin/Root/Body/Center/PageStandard/Grid/VersionEdit
@onready var gpAuthorEdit: LineEdit = $Panel/Margin/Root/Body/Center/PageStandard/Grid/AuthorEdit
@onready var gpPackIdLabel: Label = $Panel/Margin/Root/Body/Center/PageStandard/Grid/PackIdLabel
@onready var gpPackNameLabel: Label = $Panel/Margin/Root/Body/Center/PageStandard/Grid/PackNameLabel
@onready var gpStdLabel: Label = $Panel/Margin/Root/Body/Center/PageStandard/Grid/StdLabel
@onready var gpVersionLabel: Label = $Panel/Margin/Root/Body/Center/PageStandard/Grid/VersionLabel
@onready var gpAuthorLabel: Label = $Panel/Margin/Root/Body/Center/PageStandard/Grid/AuthorLabel

# --- step 5 widgets / 第 5 步控件 ---
@onready var gpSummary: RichTextLabel = $Panel/Margin/Root/Body/Center/PageExport/Summary
@onready var gpRegisterCheck: CheckBox = $Panel/Margin/Root/Body/Center/PageExport/RegisterCheck
@onready var gpPathLabel: Label = $Panel/Margin/Root/Body/Center/PageExport/PathLabel

# Shared live preview.
# 共享的实时预览。
@onready var gpPreview: GPSymbolPreview = $Panel/Margin/Root/Body/Right/Preview

# Collected attribute schema: key -> {"type": String, "default": Variant}.
# 收集到的属性 schema：键 -> {"type": String, "default": Variant}。
var gpAttrSchema: Dictionary = {}

# The definition produced by the last normalization pass.
# 最近一次归一化产出的定义。
var gpResultDef: GPSymbolDef = null


# ============================ lifecycle ============================
# ============================ 生命周期 ============================
# Wire signals, fill dynamic data and drive the wizard. The node tree itself lives in the scene file.
# 绑定信号、填充动态数据并驱动向导。节点树本身位于场景文件中。
func _ready() -> void:
	title = I18n.gpTr("symed.title")
	# Establish a `min_size` that provably fits the area we pop up in, before anything can call
	# `popup*()`. The final size / position is set by gpPopupOverHost().
	# 在任何 `popup*()` 之前先确立一个确定放得下的 `min_size`；最终尺寸与位置由
	# gpPopupOverHost() 设定。
	_gpFitToScreen(false)
	focus_entered.connect(_gpOnFocusEntered)
	close_requested.connect(queue_free)
	# Host resized (or moved to a monitor of different scale): keep the dialog inside it.
	# 宿主被缩放（或移到不同缩放的显示器）：保持对话框仍在其内部。
	var gpHostWin: Window = _gpHostWindow()
	if gpHostWin != null:
		gpHostWin.size_changed.connect(_gpOnHostResized)

	# ---- step 1: category list ----
	# ---- 第 1 步：类目列表 ----
	var gpCats: Array[String] = GPSymbolCategories.gpCategoryList()
	for gpI in range(gpCats.size()):
		gpCatOption.add_item(I18n.gpTr(gpCats[gpI], gpCats[gpI]), gpI)
		gpCatOption.set_item_metadata(gpI, gpCats[gpI])
	gpCatOption.item_selected.connect(_gpOnCategorySelected)

	# ---- step 2: drawing tool list + initial states ----
	# ---- 第 2 步：绘图工具列表 + 初始状态 ----
	gpToolOption.add_item(I18n.gpTr("symed.tool_polyline"), 0)
	gpToolOption.add_item(I18n.gpTr("symed.tool_circle"), 1)
	gpToolOption.add_item(I18n.gpTr("symed.tool_rect"), 2)
	gpToolOption.add_item(I18n.gpTr("symed.tool_port"), 3)
	gpToolOption.item_selected.connect(_gpOnToolSelected)
	gpSnapCheck.button_pressed = true
	gpSnapCheck.toggled.connect(_gpOnSnapToggled)
	gpFinishBtn.pressed.connect(_gpOnFinishPath)
	gpUndoBtn.pressed.connect(_gpOnUndo)
	gpClearBtn.pressed.connect(_gpOnClear)
	gpGlyph.gpDraftChanged.connect(_gpRefreshPreview)

	# ---- step 3: attr type list + buttons ----
	# ---- 第 3 步：属性类型列表 + 按钮 ----
	for gpI in range(GP_ATTR_TYPES.size()):
		gpAttrTypeOption.add_item(GP_ATTR_TYPES[gpI], gpI)
	gpAttrAddBtn.pressed.connect(_gpOnAttrAdd)
	gpAttrDelBtn.pressed.connect(_gpOnAttrDelete)

	# ---- step 4: standard presets + initial pack metadata ----
	# ---- 第 4 步：标准预设 + 图元包初始元数据 ----
	for gpI in range(GP_STD_PRESETS.size()):
		gpStdOption.add_item(GP_STD_PRESETS[gpI], gpI)
	gpStdOption.item_selected.connect(_gpOnStdSelected)
	gpPackIdEdit.text = "my_pack"
	gpPackNameEdit.text = "我的图元包"
	gpStdEdit.text = GP_STD_PRESETS[0]
	gpVersionEdit.text = "1.0"

	# ---- step 5: export options ----
	# ---- 第 5 步：导出选项 ----
	gpSummary.bbcode_enabled = true
	gpSummary.fit_content = false
	gpRegisterCheck.button_pressed = true

	# ---- footer navigation ----
	# ---- 底部导航 ----
	gpPrevBtn.pressed.connect(_gpOnPrev)
	gpNextBtn.pressed.connect(_gpOnNext)
	gpExportBtn.pressed.connect(_gpOnExport)
	gpCloseBtn.pressed.connect(queue_free)

	I18n.gpLocaleChanged.connect(_gpOnLocaleChanged)
	_gpOnCategorySelected(gpCatOption.selected)
	_gpGotoStep(0)


# ============================ resolution / HiDPI fit ============================
# ============================ 分辨率 / HiDPI 自适应 ============================
# The window that owns this dialog (the main app window). The dialog pops up over it, so its
# screen is the one we must measure against.
# 拥有本对话框的窗口（主程序窗口）。对话框会弹在其上，故须以其所在屏幕为测量基准。
func _gpHostWindow() -> Window:
	var gpParent: Node = get_parent()
	if gpParent == null:
		return null
	return gpParent.get_window()


# Re-derive content scale, min_size and (when gpResize) size from the area we live in.
# 依据所处区域重新推导内容缩放、min_size 以及（gpResize 时）size。
func _gpFitToScreen(gpResize: bool) -> void:
	var gpHost: Window = _gpHostWindow()
	GP_WINDOW_FIT.gpApply(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL, gpResize, GP_SELF_FRAC)
	gpLastScreen = GP_WINDOW_FIT.gpScreenOf(self, gpHost)


# Show the wizard as a movable, resizable window centered over the main window. Callers must use
# this instead of the bare `popup_centered()`: that engine call ignores `size` and falls back to
# `min_size`, which is how an oversized dialog ended up at a negative position.
# 以可移动、可缩放的窗口居中显示在主窗口之上。调用方必须用本方法而非裸 `popup_centered()`：
# 后者会忽略 `size` 并退回 `min_size`，正是超大对话框被放到负坐标的原因。
func gpPopupOverHost() -> void:
	var gpHost: Window = _gpHostWindow()
	GP_WINDOW_FIT.gpPopupFitted(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL, GP_SELF_FRAC)
	gpLastScreen = GP_WINDOW_FIT.gpScreenOf(self, gpHost)


# Dragged to another monitor: re-sync the scale and keep the window on screen, but never fight
# a size the user set by hand.
# 被拖到另一台显示器：重新同步缩放并确保窗口留在屏幕内，但绝不覆盖用户手动调整过的尺寸。
func _gpOnFocusEntered() -> void:
	if current_screen == gpLastScreen:
		return
	_gpFitToScreen(false)


# Host window resized: re-clamp so the dialog cannot end up larger than what contains it.
# 宿主窗口尺寸变化：重新钳制，避免对话框大于容纳它的区域。
func _gpOnHostResized() -> void:
	if not is_inside_tree():
		return
	_gpFitToScreen(false)


# ============================ locale refresh ============================
# ============================ 语言刷新 ============================
# Refresh every locale-dependent text in the wizard (labels, buttons, step rail, summary).
# 刷新向导中所有依赖语言的文本（标签、按钮、步骤导航、汇总）。
func _gpOnLocaleChanged(_gpLocale: String) -> void:
	_gpRefreshStaticText()


# Set all static labels from the i18n table and re-highlight the active step.
# 从 i18n 表设置全部静态标签，并重新高亮当前步骤。
func _gpRefreshStaticText() -> void:
	gpTitleLabel.text = I18n.gpTr("symed.title")
	gpBadgeLabel.text = "%d / %d" % [gpStep + 1, GP_STEP_COUNT]

	# Step rail: text + active highlight.
	# 步骤导航：文本 + 当前步高亮。
	for gpI in range(gpStepLabels.size()):
		gpStepLabels[gpI].text = I18n.gpTr(GP_STEP_KEYS[gpI])
		gpStepLabels[gpI].remove_theme_color_override("font_color")
	if gpStep >= 0 and gpStep < gpStepLabels.size():
		gpStepLabels[gpStep].add_theme_color_override("font_color", Color(0.45, 0.75, 1.0))

	# Step 1 labels.
	# 第 1 步标签。
	gpCatLabel.text = I18n.gpTr("symed.cat_label")
	gpIdLabel.text = I18n.gpTr("symed.id_label")
	gpNameLabel.text = I18n.gpTr("symed.name_label")
	gpEnvCaption.text = I18n.gpTr("symed.env_label")

	# Step 2 labels.
	# 第 2 步标签。
	gpToolLabel.text = I18n.gpTr("symed.tool_label")
	gpFinishBtn.text = I18n.gpTr("symed.btn_finish")
	gpUndoBtn.text = I18n.gpTr("symed.btn_undo")
	gpClearBtn.text = I18n.gpTr("symed.btn_clear")
	gpDrawHint.text = I18n.gpTr("symed.draw_hint")

	# Step 3 labels.
	# 第 3 步标签。
	gpAttrAddBtn.text = I18n.gpTr("symed.btn_add")
	gpAttrDelBtn.text = I18n.gpTr("symed.btn_delete")
	gpAttrHint.text = I18n.gpTr("symed.attr_hint")

	# Step 4 labels.
	# 第 4 步标签。
	gpPackIdLabel.text = I18n.gpTr("symed.pack_id_label")
	gpPackNameLabel.text = I18n.gpTr("symed.pack_name_label")
	gpStdLabel.text = I18n.gpTr("symed.std_label")
	gpVersionLabel.text = I18n.gpTr("symed.version_label")
	gpAuthorLabel.text = I18n.gpTr("symed.author_label")

	# Step 5 controls.
	# 第 5 步控件。
	gpRegisterCheck.text = I18n.gpTr("symed.export_register")

	# Footer buttons.
	# 底部按钮。
	gpPrevBtn.text = I18n.gpTr("symed.prev")
	gpNextBtn.text = I18n.gpTr("symed.next")
	gpExportBtn.text = I18n.gpTr("symed.export")
	gpCloseBtn.text = I18n.gpTr("symed.close")

	# The live summary is dynamic; rebuild it only when we are on the last step.
	# 汇总是动态的，仅当处于最后一步时重建。
	if gpStep == GP_STEP_COUNT - 1:
		_gpRefreshSummary()


# ============================ step navigation ============================
# ============================ 步骤导航 ============================
# Switch to a step, updating the visible page and footer controls.
# 切换到某一步，更新可见页与底部控件。
func _gpGotoStep(gpIdx: int) -> void:
	gpIdx = clampi(gpIdx, 0, GP_STEP_COUNT - 1)
	gpStep = gpIdx
	for gpI in range(gpPages.size()):
		gpPages[gpI].visible = (gpI == gpIdx)
	gpPrevBtn.disabled = (gpIdx == 0)
	gpNextBtn.visible = (gpIdx < GP_STEP_COUNT - 1)
	gpExportBtn.visible = (gpIdx == GP_STEP_COUNT - 1)
	gpHintLabel.text = ""
	_gpRefreshStaticText()


func _gpOnPrev() -> void:
	_gpGotoStep(gpStep - 1)


func _gpOnNext() -> void:
	# Step 1 requires an id and a display name before advancing.
	# 离开第 1 步前必须已填 id 与显示名。
	if gpStep == 0:
		if gpIdEdit.text.strip_edges() == "":
			_gpSetHint("symed.hint_id_required")
			return
		if gpNameEdit.text.strip_edges() == "":
			_gpSetHint("symed.hint_name_required")
			return
	_gpGotoStep(gpStep + 1)


# ============================ step 1: category / identity ============================
# ============================ 第 1 步：类目 / 身份 ============================
# Category changed: update the guide envelope, the family peers and the live preview.
# 类目变化：更新参考框包络、同族参考与实时预览。
func _gpOnCategorySelected(gpIdx: int) -> void:
	var gpCat: String = _gpCurrentCategory(gpIdx)
	var gpEnv: Vector2 = GPSymbolCategories.gpSizeFor(gpCat)
	gpGlyph.gpSetEnvelope(gpEnv)
	gpEnvLabel.text = "%d × %d px" % [int(gpEnv.x), int(gpEnv.y)]
	_gpRefreshPeers(gpCat)
	_gpRefreshPreview()


# id text changed: keep the preview label in sync.
# id 文本变化：同步预览标签。
func _gpOnIdChanged(_gpText: String) -> void:
	_gpRefreshPreview()


# Resolve the currently selected category key (falls back to the list when metadata is missing).
# 解析当前选中的类目键（元数据缺失时回退到列表本身）。
func _gpCurrentCategory(gpIdx: int = -1) -> String:
	var gpSel: int = gpIdx if gpIdx >= 0 else gpCatOption.selected
	var gpCat: String = ""
	if gpSel >= 0 and gpSel < gpCatOption.item_count:
		gpCat = str(gpCatOption.get_item_metadata(gpSel))
	if gpCat == "":
		var gpCats: Array[String] = GPSymbolCategories.gpCategoryList()
		gpCat = gpCats[gpSel] if (gpSel >= 0 and gpSel < gpCats.size()) else "general"
	return gpCat


# ============================ step 2: glyph ============================
# ============================ 第 2 步：画字形 ============================
# Drawing tool changed: forward it to the canvas.
# 绘图工具改变：转发给画板。
func _gpOnToolSelected(gpIdx: int) -> void:
	gpGlyph.gpSetTool(gpIdx)


func _gpOnSnapToggled(gpOn: bool) -> void:
	gpGlyph.gpSetSnap(gpOn)


func _gpOnFinishPath() -> void:
	gpGlyph.gpFinishPath(false)


func _gpOnUndo() -> void:
	gpGlyph.gpUndo()


func _gpOnClear() -> void:
	gpGlyph.gpClear()


# ============================ step 3: attribute schema ============================
# ============================ 第 3 步：属性 schema ============================
# Add the current attribute row to the schema.
# 把当前属性行加入 schema。
func _gpOnAttrAdd() -> void:
	var gpKey: String = gpAttrKeyEdit.text.strip_edges()
	if gpKey == "":
		_gpSetHint("symed.hint_attr_key")
		return
	if gpAttrSchema.has(gpKey):
		_gpSetHint("symed.hint_attr_dup")
		return
	var gpType: String = GP_ATTR_TYPES[gpAttrTypeOption.selected]
	var gpDefVal: Variant = _gpParseAttrDefault(gpType, gpAttrDefEdit.text)
	gpAttrSchema[gpKey] = {"type": gpType, "default": gpDefVal}
	gpAttrKeyEdit.text = ""
	gpAttrDefEdit.text = ""
	_gpRenderAttrList()
	gpHintLabel.text = ""


func _gpOnAttrDelete() -> void:
	var gpSel: PackedInt32Array = gpAttrList.get_selected_items()
	if gpSel.is_empty():
		return
	var gpKey: String = str(gpAttrList.get_item_metadata(gpSel[0]))
	if gpAttrSchema.has(gpKey):
		gpAttrSchema.erase(gpKey)
		_gpRenderAttrList()


# Coerce a default-string into the declared attribute type.
# 把默认值字符串按声明类型强制转换。
func _gpParseAttrDefault(gpType: String, gpText: String) -> Variant:
	var gpT: String = gpText.strip_edges()
	if gpT == "":
		match gpType:
			"string": return ""
			"float": return 0.0
			"int": return 0
			"bool": return false
	match gpType:
		"float": return float(gpT)
		"int": return int(gpT)
		"bool":
			return gpT == "true" or gpT == "1" or gpT == "yes" or gpT == "是"
		_:
			return gpT


# Redraw the attribute list, keeping the key on each item's metadata for deletion.
# 重绘属性列表，并把键写入每个条目的元数据以便删除。
func _gpRenderAttrList() -> void:
	gpAttrList.clear()
	var gpIdx: int = 0
	for gpKey in gpAttrSchema.keys():
		var gpEntry: Dictionary = gpAttrSchema[gpKey]
		gpAttrList.add_item("%s : %s = %s" % [gpKey, gpEntry["type"], str(gpEntry["default"])])
		gpAttrList.set_item_metadata(gpIdx, gpKey)
		gpIdx += 1


# ============================ step 4: standard reference ============================
# ============================ 第 4 步：标准出处 ============================
# Standard preset chosen: copy it into the free-text field.
# 选择标准预设：写入自由文本输入框。
func _gpOnStdSelected(gpIdx: int) -> void:
	if gpIdx >= 0 and gpIdx < GP_STD_PRESETS.size():
		gpStdEdit.text = GP_STD_PRESETS[gpIdx]


# ============================ live preview ============================
# ============================ 实时预览 ============================
# Rebuild the preview from the draft + identity so the author sees the normalized result live.
# 由草稿 + 身份实时重建预览，使作者看到归一化后的结果。
func _gpRefreshPreview() -> void:
	var gpCat: String = _gpCurrentCategory()
	var gpRaw: Dictionary = {
		"id": gpIdEdit.text if gpIdEdit.text != "" else "preview",
		"display_name": gpNameEdit.text if gpNameEdit.text != "" else "preview",
		"shapes": gpGlyph.gpGetDraftShapes(),
		"ports": gpGlyph.gpGetDraftPorts(),
		"attrs_schema": gpAttrSchema,
	}
	gpPreview.gpSetDef(GPSymbolNormalizer.gpNormalizeSymbol(gpRaw, gpCat, {}))


# Refresh the family reference strip shown under the preview.
# 刷新预览下方的同族参考条。
func _gpRefreshPeers(gpCat: String) -> void:
	var gpPeers: Array[GPSymbolDef] = []
	for gpD in GPSymbolLibrary.gpDefaultDefs():
		if gpD.gpCategory == gpCat:
			gpPeers.append(gpD)
	gpPreview.gpSetPeers(gpPeers)


# ============================ step 5: export ============================
# ============================ 第 5 步：导出 ============================
# Rebuild the summary text for the export page.
# 为导出页重建汇总文本。
func _gpRefreshSummary() -> void:
	var gpCat: String = _gpCurrentCategory()
	var gpEnv: Vector2 = GPSymbolCategories.gpSizeFor(gpCat)
	var gpPorts: int = gpGlyph.gpGetDraftPorts().size()
	gpSummary.text = "[b]%s[/b]\n" % I18n.gpTr("symed.title")
	gpSummary.text += "• %s: %s\n" % [I18n.gpTr("info.id"), gpIdEdit.text]
	gpSummary.text += "• %s: %s\n" % [I18n.gpTr("info.type"), gpNameEdit.text]
	gpSummary.text += "• %s: %s\n" % [I18n.gpTr("info.category"), I18n.gpTr(gpCat)]
	gpSummary.text += "• %s: %d × %d px\n" % [I18n.gpTr("info.size"), int(gpEnv.x), int(gpEnv.y)]
	gpSummary.text += "• %s: %d\n" % [I18n.gpTr("symed.summary_shapes"), _gpDraftShapeCount()]
	gpSummary.text += "• %s: %d\n" % [I18n.gpTr("symed.summary_ports"), gpPorts]
	gpSummary.text += "• %s: %s\n" % [I18n.gpTr("symed.summary_pack"), gpPackIdEdit.text]
	gpSummary.text += "• %s: %s\n" % [I18n.gpTr("symed.summary_std"), gpStdEdit.text]
	gpRegisterCheck.text = I18n.gpTr("symed.export_register")


# Count the committed primitives in the draft (paths + circles + rects).
# 统计草稿中已提交的图元原语数量（折线 + 圆 + 矩形）。
func _gpDraftShapeCount() -> int:
	var gpS: Dictionary = gpGlyph.gpGetDraftShapes()
	var gpN: int = (gpS.get("paths", []) as Array).size()
	gpN += (gpS.get("circles", []) as Array).size()
	gpN += (gpS.get("rects", []) as Array).size()
	return gpN


# Export: normalize the draft into a GPSymbolDef, wrap it in a GPSymbolPack, register it and
# optionally persist it to user://symbol_packs/<id>.json. Emits gpPackExported for the host.
# 导出：把草稿归一化为 GPSymbolDef，装入 GPSymbolPack，注册并可选持久化到
# user://symbol_packs/<id>.json，最后 emit gpPackExported 通知宿主。
func _gpOnExport() -> void:
	if gpIdEdit.text.strip_edges() == "":
		_gpGotoStep(0)
		_gpSetHint("symed.hint_id_required")
		return
	if gpNameEdit.text.strip_edges() == "":
		_gpGotoStep(0)
		_gpSetHint("symed.hint_name_required")
		return

	var gpCat: String = _gpCurrentCategory()
	var gpId: String = gpIdEdit.text.strip_edges()
	var gpRaw: Dictionary = {
		"id": gpId,
		"display_name": gpNameEdit.text.strip_edges(),
		"shapes": gpGlyph.gpGetDraftShapes(),
		"ports": gpGlyph.gpGetDraftPorts(),
		"attrs_schema": gpAttrSchema,
	}
	# The single place that turns a hand-drawn glyph into a canonical definition.
	# 把手绘字形变成规范化定义的唯一入口。
	var gpDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpRaw, gpCat, {})
	gpResultDef = gpDef

	var gpPack: GPSymbolPack = GPSymbolPack.new()
	gpPack.gpPackId = gpPackIdEdit.text.strip_edges()
	gpPack.gpName = gpPackNameEdit.text.strip_edges()
	gpPack.gpStandardRef = gpStdEdit.text.strip_edges()
	gpPack.gpVersion = gpVersionEdit.text.strip_edges()
	gpPack.gpAuthor = gpAuthorEdit.text.strip_edges()
	gpPack.gpSymbols = [gpDef]

	# Register into the live library so the new symbol shows up in the palette immediately.
	# 注册进活动图元库，使新图元立即出现在图元面板。
	if gpRegisterCheck.button_pressed:
		GPSymbolLibrary.gpRegisterDefs([gpDef])

	# Persist to user://symbol_packs/<id>.json when the directory is writable.
	# 目录可写时持久化到 user://symbol_packs/<id>.json。
	var gpDir: String = GP_EXPORT_DIR
	if not DirAccess.dir_exists_absolute(gpDir):
		DirAccess.make_dir_recursive_absolute(gpDir)
	var gpPath: String = "%s/%s.json" % [gpDir, gpId]
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.WRITE)
	if gpF != null:
		gpF.store_string(JSON.stringify(gpPack.gpToDict(), "", true))
		gpF.close()
		gpPathLabel.text = "%s：%s" % [I18n.gpTr("symed.export_saved"), gpPath]
	else:
		gpPathLabel.text = "%s：%s" % [I18n.gpTr("symed.export_save_fail"), gpPath]

	_gpSetHint("symed.export_done")
	gpPackExported.emit(gpPack)


# ============================ hint helper ============================
# ============================ 提示辅助 ============================
# Show a localized hint line at the bottom of the wizard.
# 在向导底部显示一条本地化提示。
func _gpSetHint(gpKey: String) -> void:
	gpHintLabel.text = I18n.gpTr(gpKey)
