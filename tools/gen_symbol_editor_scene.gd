extends SceneTree

# Copyright © 2026 Jonson Wang
# One-shot tool: builds the static node tree of GPSymbolEditor and packs it into a real,
# editor-editable .tscn so the layout can be tweaked visually.
# 一次性工具：构建 GPSymbolEditor 的静态节点树并打包成可在编辑器内可视化修改的 .tscn。
# Run with / 运行方式:
#   Godot --headless --script tools/gen_symbol_editor_scene.gd
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_SCENE_PATH: String = "res://scenes/symbol_editor.tscn"


# Mark a control as a direct child of a plain Control (anchored, full-rect).
# 将一个控件标记为普通 Control 的直接子节点（锚定、铺满）。
func _gpAnchorFull(gpCtrl: Control) -> void:
	gpCtrl.layout_mode = 1
	gpCtrl.set_anchors_preset(Control.PRESET_FULL_RECT)


# Mark a control as a direct child of a Container (arranged by the container).
# 将一个控件标记为 Container 的直接子节点（由容器排布）。
func _gpInContainer(gpCtrl: Control) -> void:
	gpCtrl.layout_mode = 2


# Add gpChild to gpParent and mark it as a container child.
# 把 gpChild 加入 gpParent 并标记为容器子节点。
func _gpAdd(gpParent: Node, gpChild: Control) -> Control:
	gpParent.add_child(gpChild)
	_gpInContainer(gpChild)
	return gpChild


# ============================ build ============================
# ============================ 构建 ============================
func _gpBuild() -> Window:
	var gpRoot: Window = Window.new()
	gpRoot.name = "SymbolEditor"

	# Panel (anchored full-rect inside the Window).
	# Panel（在 Window 内锚定铺满）。
	var gpPanel: Panel = Panel.new()
	gpPanel.name = "Panel"
	_gpAnchorFull(gpPanel)
	gpRoot.add_child(gpPanel)

	# Margin container (anchored full-rect inside the Panel) with fixed outer padding.
	# 边距容器（在 Panel 内锚定铺满），固定外边距。
	var gpMargin: MarginContainer = MarginContainer.new()
	gpMargin.name = "Margin"
	_gpAnchorFull(gpMargin)
	gpMargin.add_theme_constant_override("margin_left", 14)
	gpMargin.add_theme_constant_override("margin_top", 12)
	gpMargin.add_theme_constant_override("margin_right", 14)
	gpMargin.add_theme_constant_override("margin_bottom", 12)
	gpPanel.add_child(gpMargin)

	# Root vertical stack: header / body / footer.
	# 根纵向堆叠：标题 / 主体 / 底部。
	var gpRootV: VBoxContainer = VBoxContainer.new()
	gpRootV.name = "Root"
	_gpAdd(gpMargin, gpRootV)
	gpRootV.add_theme_constant_override("separation", 8)

	# --- header ---
	# --- 标题行 ---
	var gpHeader: HBoxContainer = HBoxContainer.new()
	gpHeader.name = "Header"
	_gpAdd(gpRootV, gpHeader)
	var gpTitleLabel: Label = Label.new()
	gpTitleLabel.name = "TitleLabel"
	_gpAdd(gpHeader, gpTitleLabel)
	gpTitleLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gpBadgeLabel: Label = Label.new()
	gpBadgeLabel.name = "BadgeLabel"
	_gpAdd(gpHeader, gpBadgeLabel)
	gpBadgeLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_gpAdd(gpRootV, HSeparator.new())

	# --- body: rail | center pages | preview ---
	# --- 主体：导航栏 | 中部步骤页 | 右侧预览 ---
	var gpBody: HBoxContainer = HBoxContainer.new()
	gpBody.name = "Body"
	_gpAdd(gpRootV, gpBody)
	gpBody.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpBody.add_theme_constant_override("separation", 12)

	# left rail: step indicators
	# 左侧导航栏：步骤指示
	var gpRail: VBoxContainer = VBoxContainer.new()
	gpRail.name = "Rail"
	_gpAdd(gpBody, gpRail)
	gpRail.custom_minimum_size = Vector2(168, 0)
	gpRail.add_theme_constant_override("separation", 6)
	for gpI in range(5):
		var gpStepL: Label = Label.new()
		gpStepL.name = "Step%d" % gpI
		_gpAdd(gpRail, gpStepL)
		gpStepL.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# center: the five step pages
	# 中部：五个步骤页
	var gpCenter: VBoxContainer = VBoxContainer.new()
	gpCenter.name = "Center"
	_gpAdd(gpBody, gpCenter)
	gpCenter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpCenter.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_gpBuildPageCategory(gpCenter)
	_gpBuildPageGlyph(gpCenter)
	_gpBuildPageAttrs(gpCenter)
	_gpBuildPageStandard(gpCenter)
	_gpBuildPageExport(gpCenter)

	# right: live preview
	# 右侧：实时预览
	var gpRight: VBoxContainer = VBoxContainer.new()
	gpRight.name = "Right"
	_gpAdd(gpBody, gpRight)
	gpRight.custom_minimum_size = Vector2(300, 0)
	gpRight.add_theme_constant_override("separation", 6)
	var gpPvCap: Label = Label.new()
	gpPvCap.name = "PreviewCap"
	_gpAdd(gpRight, gpPvCap)
	var gpPreview: Control = Control.new()
	gpPreview.name = "Preview"
	_gpAdd(gpRight, gpPreview)
	gpPreview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpPreview.custom_minimum_size = Vector2(0, 260)
	var gpPvHint: Label = Label.new()
	gpPvHint.name = "PreviewHint"
	_gpAdd(gpRight, gpPvHint)
	gpPvHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_gpAdd(gpRootV, HSeparator.new())

	# --- footer ---
	# --- 底部导航 ---
	var gpFooter: HBoxContainer = HBoxContainer.new()
	gpFooter.name = "Footer"
	_gpAdd(gpRootV, gpFooter)
	gpFooter.add_theme_constant_override("separation", 8)
	var gpHintLabel: Label = Label.new()
	gpHintLabel.name = "HintLabel"
	_gpAdd(gpFooter, gpHintLabel)
	gpHintLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpHintLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for gpBtnName in ["PrevBtn", "NextBtn", "ExportBtn", "CloseBtn"]:
		var gpBtn: Button = Button.new()
		gpBtn.name = gpBtnName
		_gpAdd(gpFooter, gpBtn)

	# The wizard script (and the glyph/preview scripts) are attached by path via text
	# post-processing so this generator does not need the project autoloads to compile.
	# 向导脚本（及字形/预览脚本）稍后通过文本后处理按路径挂接，
	# 因此本生成器无需项目 autoload 也能编译。
	return gpRoot


# Build the category / id / display-name page (step 1).
# 构建类目 / id / 显示名页面（第 1 步）。
func _gpBuildPageCategory(gpCenter: VBoxContainer) -> void:
	var gpPage: VBoxContainer = VBoxContainer.new()
	gpPage.name = "PageCategory"
	_gpAdd(gpCenter, gpPage)
	gpPage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpPage.add_theme_constant_override("separation", 8)

	var gpGrid: GridContainer = GridContainer.new()
	gpGrid.name = "Grid"
	_gpAdd(gpPage, gpGrid)
	gpGrid.columns = 2
	gpGrid.add_theme_constant_override("h_separation", 12)
	gpGrid.add_theme_constant_override("v_separation", 8)

	var gpCatLabel: Label = Label.new()
	gpCatLabel.name = "CatLabel"
	_gpAdd(gpGrid, gpCatLabel)
	var gpCatOption: OptionButton = OptionButton.new()
	gpCatOption.name = "CatOption"
	_gpAdd(gpGrid, gpCatOption)
	gpCatOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var gpIdLabel: Label = Label.new()
	gpIdLabel.name = "IdLabel"
	_gpAdd(gpGrid, gpIdLabel)
	var gpIdEdit: LineEdit = LineEdit.new()
	gpIdEdit.name = "IdEdit"
	_gpAdd(gpGrid, gpIdEdit)
	gpIdEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var gpNameLabel: Label = Label.new()
	gpNameLabel.name = "NameLabel"
	_gpAdd(gpGrid, gpNameLabel)
	var gpNameEdit: LineEdit = LineEdit.new()
	gpNameEdit.name = "NameEdit"
	_gpAdd(gpGrid, gpNameEdit)
	gpNameEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var gpEnvCaption: Label = Label.new()
	gpEnvCaption.name = "EnvCaption"
	_gpAdd(gpGrid, gpEnvCaption)
	var gpEnvLabel: Label = Label.new()
	gpEnvLabel.name = "EnvLabel"
	_gpAdd(gpGrid, gpEnvLabel)

	var gpNote: Label = Label.new()
	gpNote.name = "Note"
	_gpAdd(gpPage, gpNote)
	gpNote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpNote.size_flags_vertical = Control.SIZE_EXPAND_FILL


# Build the drawing page (tool bar + glyph canvas) (step 2).
# 构建绘图页（工具条 + 字形画板）（第 2 步）。
func _gpBuildPageGlyph(gpCenter: VBoxContainer) -> void:
	var gpPage: VBoxContainer = VBoxContainer.new()
	gpPage.name = "PageGlyph"
	_gpAdd(gpCenter, gpPage)
	gpPage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpPage.add_theme_constant_override("separation", 6)

	var gpBar: HBoxContainer = HBoxContainer.new()
	gpBar.name = "Bar"
	_gpAdd(gpPage, gpBar)
	gpBar.add_theme_constant_override("separation", 8)

	var gpToolLabel: Label = Label.new()
	gpToolLabel.name = "ToolLabel"
	_gpAdd(gpBar, gpToolLabel)
	var gpToolOption: OptionButton = OptionButton.new()
	gpToolOption.name = "ToolOption"
	_gpAdd(gpBar, gpToolOption)
	var gpSnapCheck: CheckBox = CheckBox.new()
	gpSnapCheck.name = "SnapCheck"
	_gpAdd(gpBar, gpSnapCheck)
	var gpFinishBtn: Button = Button.new()
	gpFinishBtn.name = "FinishBtn"
	_gpAdd(gpBar, gpFinishBtn)
	var gpUndoBtn: Button = Button.new()
	gpUndoBtn.name = "UndoBtn"
	_gpAdd(gpBar, gpUndoBtn)
	var gpClearBtn: Button = Button.new()
	gpClearBtn.name = "ClearBtn"
	_gpAdd(gpBar, gpClearBtn)

	var gpGlyph: Control = Control.new()
	gpGlyph.name = "Glyph"
	_gpAdd(gpPage, gpGlyph)
	gpGlyph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpGlyph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpGlyph.custom_minimum_size = Vector2(0, 320)

	var gpDrawHint: Label = Label.new()
	gpDrawHint.name = "DrawHint"
	_gpAdd(gpPage, gpDrawHint)
	gpDrawHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# Build the attribute schema page (step 3).
# 构建属性 schema 页面（第 3 步）。
func _gpBuildPageAttrs(gpCenter: VBoxContainer) -> void:
	var gpPage: VBoxContainer = VBoxContainer.new()
	gpPage.name = "PageAttrs"
	_gpAdd(gpCenter, gpPage)
	gpPage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpPage.add_theme_constant_override("separation", 6)

	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.name = "Row"
	_gpAdd(gpPage, gpRow)
	gpRow.add_theme_constant_override("separation", 6)

	var gpAttrKeyEdit: LineEdit = LineEdit.new()
	gpAttrKeyEdit.name = "AttrKeyEdit"
	_gpAdd(gpRow, gpAttrKeyEdit)
	gpAttrKeyEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gpAttrTypeOption: OptionButton = OptionButton.new()
	gpAttrTypeOption.name = "AttrTypeOption"
	_gpAdd(gpRow, gpAttrTypeOption)
	var gpAttrDefEdit: LineEdit = LineEdit.new()
	gpAttrDefEdit.name = "AttrDefEdit"
	_gpAdd(gpRow, gpAttrDefEdit)
	gpAttrDefEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gpAttrAddBtn: Button = Button.new()
	gpAttrAddBtn.name = "AttrAddBtn"
	_gpAdd(gpRow, gpAttrAddBtn)
	var gpAttrDelBtn: Button = Button.new()
	gpAttrDelBtn.name = "AttrDelBtn"
	_gpAdd(gpRow, gpAttrDelBtn)

	var gpAttrList: ItemList = ItemList.new()
	gpAttrList.name = "AttrList"
	_gpAdd(gpPage, gpAttrList)
	gpAttrList.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpAttrList.custom_minimum_size = Vector2(0, 260)

	var gpAttrHint: Label = Label.new()
	gpAttrHint.name = "AttrHint"
	_gpAdd(gpPage, gpAttrHint)
	gpAttrHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# Build the pack metadata / standard reference page (step 4).
# 构建图元包元数据 / 标准出处页面（第 4 步）。
func _gpBuildPageStandard(gpCenter: VBoxContainer) -> void:
	var gpPage: VBoxContainer = VBoxContainer.new()
	gpPage.name = "PageStandard"
	_gpAdd(gpCenter, gpPage)
	gpPage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpPage.add_theme_constant_override("separation", 8)

	var gpGrid: GridContainer = GridContainer.new()
	gpGrid.name = "Grid"
	_gpAdd(gpPage, gpGrid)
	gpGrid.columns = 2
	gpGrid.add_theme_constant_override("h_separation", 12)
	gpGrid.add_theme_constant_override("v_separation", 8)

	var gpPackIdLabel: Label = Label.new()
	gpPackIdLabel.name = "PackIdLabel"
	_gpAdd(gpGrid, gpPackIdLabel)
	var gpPackIdEdit: LineEdit = LineEdit.new()
	gpPackIdEdit.name = "PackIdEdit"
	_gpAdd(gpGrid, gpPackIdEdit)
	gpPackIdEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var gpPackNameLabel: Label = Label.new()
	gpPackNameLabel.name = "PackNameLabel"
	_gpAdd(gpGrid, gpPackNameLabel)
	var gpPackNameEdit: LineEdit = LineEdit.new()
	gpPackNameEdit.name = "PackNameEdit"
	_gpAdd(gpGrid, gpPackNameEdit)
	gpPackNameEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var gpStdLabel: Label = Label.new()
	gpStdLabel.name = "StdLabel"
	_gpAdd(gpGrid, gpStdLabel)
	var gpStdRow: HBoxContainer = HBoxContainer.new()
	gpStdRow.name = "StdRow"
	_gpAdd(gpGrid, gpStdRow)
	gpStdRow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpStdRow.add_theme_constant_override("separation", 6)
	var gpStdOption: OptionButton = OptionButton.new()
	gpStdOption.name = "StdOption"
	_gpAdd(gpStdRow, gpStdOption)
	var gpStdEdit: LineEdit = LineEdit.new()
	gpStdEdit.name = "StdEdit"
	_gpAdd(gpStdRow, gpStdEdit)
	gpStdEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var gpVersionLabel: Label = Label.new()
	gpVersionLabel.name = "VersionLabel"
	_gpAdd(gpGrid, gpVersionLabel)
	var gpVersionEdit: LineEdit = LineEdit.new()
	gpVersionEdit.name = "VersionEdit"
	_gpAdd(gpGrid, gpVersionEdit)
	gpVersionEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var gpAuthorLabel: Label = Label.new()
	gpAuthorLabel.name = "AuthorLabel"
	_gpAdd(gpGrid, gpAuthorLabel)
	var gpAuthorEdit: LineEdit = LineEdit.new()
	gpAuthorEdit.name = "AuthorEdit"
	_gpAdd(gpGrid, gpAuthorEdit)
	gpAuthorEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var gpSpacer: Control = Control.new()
	gpSpacer.name = "Spacer"
	_gpAdd(gpPage, gpSpacer)
	gpSpacer.size_flags_vertical = Control.SIZE_EXPAND_FILL


# Build the summary / export page (step 5).
# 构建汇总 / 导出页面（第 5 步）。
func _gpBuildPageExport(gpCenter: VBoxContainer) -> void:
	var gpPage: VBoxContainer = VBoxContainer.new()
	gpPage.name = "PageExport"
	_gpAdd(gpCenter, gpPage)
	gpPage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpPage.add_theme_constant_override("separation", 8)

	var gpSummary: RichTextLabel = RichTextLabel.new()
	gpSummary.name = "Summary"
	_gpAdd(gpPage, gpSummary)
	gpSummary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpSummary.custom_minimum_size = Vector2(0, 280)

	var gpRegisterCheck: CheckBox = CheckBox.new()
	gpRegisterCheck.name = "RegisterCheck"
	_gpAdd(gpPage, gpRegisterCheck)

	var gpPathLabel: Label = Label.new()
	gpPathLabel.name = "PathLabel"
	_gpAdd(gpPage, gpPathLabel)
	gpPathLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# Insert the three script ext_resources and attach them to the matching nodes by text,
# so the scene loads in the real project (which provides I18n/Settings autoloads).
# 以文本方式插入三个脚本 ext_resource 并挂到对应节点，使场景在提供 I18n/Settings autoload
# 的真实项目中可正常加载。
func _gpInjectScripts(gpPath: String) -> void:
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpF == null:
		push_error("cannot read %s" % gpPath)
		return
	var gpText: String = gpF.get_as_text()
	gpF.close()

	var gpLines: PackedStringArray = gpText.split("\n", false)
	var gpOut: PackedStringArray = []
	var gpInjected: bool = false
	for gpLine in gpLines:
		if not gpInjected and gpLine.begins_with("[gd_scene"):
			gpOut.append(gpLine)
			gpOut.append("[ext_resource type=\"Script\" path=\"res://src/ui/glyph_canvas.gd\" id=\"1\"]")
			gpOut.append("[ext_resource type=\"Script\" path=\"res://src/ui/symbol_preview.gd\" id=\"2\"]")
			gpOut.append("[ext_resource type=\"Script\" path=\"res://src/ui/symbol_editor.gd\" id=\"3\"]")
			gpInjected = true
			continue
		if gpLine.begins_with("[node name=\"SymbolEditor\""):
			gpLine += " script = ExtResource(\"3\")"
		elif gpLine.begins_with("[node name=\"Glyph\""):
			gpLine += " script = ExtResource(\"1\")"
		elif gpLine.begins_with("[node name=\"Preview\""):
			gpLine += " script = ExtResource(\"2\")"
		gpOut.append(gpLine)

	var gpW: FileAccess = FileAccess.open(gpPath, FileAccess.WRITE)
	if gpW == null:
		push_error("cannot write %s" % gpPath)
		return
	gpW.store_string("\n".join(gpOut))
	gpW.close()


# Recursively mark every descendant as owned by the packed root, otherwise pack() only
# serializes the root node.
# 递归地把每个后代节点的 owner 设为打包根，否则 pack() 只会序列化根节点。
func _gpSetOwners(gpNode: Node, gpRoot: Node) -> void:
	for gpChild in gpNode.get_children():
		gpChild.owner = gpRoot
		_gpSetOwners(gpChild, gpRoot)


# ============================ entry ============================
# ============================ 入口 ============================
func _initialize() -> void:
	var gpRoot: Window = _gpBuild()
	_gpSetOwners(gpRoot, gpRoot)
	var gpPacked: PackedScene = PackedScene.new()
	var gpErr: int = gpPacked.pack(gpRoot)
	if gpErr != OK:
		push_error("pack failed with error %d" % gpErr)
		quit(1)
		return
	gpErr = ResourceSaver.save(gpPacked, GP_SCENE_PATH)
	if gpErr != OK:
		push_error("save %s failed with error %d" % [GP_SCENE_PATH, gpErr])
		quit(1)
		return
	_gpInjectScripts(GP_SCENE_PATH)
	print("OK: wrote %s" % GP_SCENE_PATH)
	quit(0)
