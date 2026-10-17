class_name GPTitleBlockDialog
extends Window

# Title-block / drawing-frame editor for one sheet (v0.1 Phase 2).
# 单张图纸的标题栏 / 图框编辑器（v0.1 Phase 2）。
# WHY BUILT ENTIRELY IN CODE: the dialog's rows are derived from
# GPSheet.GP_TB_FIELDS, so its shape must follow that table rather than a hand-authored
# .tscn that would silently drift whenever a field is added.
# 为何完全用代码构建：对话框的行是由 GPSheet.GP_TB_FIELDS 推导出来的，其形态必须随该表变化，
# 而不是手写的 .tscn —— 后者在新增字段时会静默失同步。
# Edits apply IMMEDIATELY (like the settings dialog): the frame repaints as you type, so
# "中英对照" stacking and per-cell overflow are visible before you commit to them.
# 编辑**即时生效**（同设置对话框）：边打字边重绘图框，以便在确定之前就能看到「中英对照」的
# 叠行效果与各格是否溢出。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

# Comfortable size range in logical UI units (see GPWindowFit).
# 逻辑 UI 单位下的舒适尺寸区间（见 GPWindowFit）。
const GP_MIN_LOGICAL: Vector2i = Vector2i(540, 560)
const GP_MAX_LOGICAL: Vector2i = Vector2i(660, 720)

# Spin-box range for ONE margin, in mm. Deliberately wide: the frame is free to sit off the paper, and
# a control whose range silently re-clamped would be a second, hidden copy of the very constraint the
# user asked us to remove. ±1000 mm covers every entry in GPSheet.GP_SHEET_PRESETS several times over
# (the largest, A0, is 1189 x 841).
# 单个边距数值框的取值范围（mm）。刻意放宽：图框可以停在纸外，而一个会悄悄再钳一次的控件，等于把用户刚刚
# 要求去掉的那条约束又藏了一份。±1000mm 足以覆盖 GPSheet.GP_SHEET_PRESETS 中任何图幅数倍（最大者 A0 为
# 1189 × 841）。
const GP_MARGIN_SPIN_MIN: float = -1000.0
const GP_MARGIN_SPIN_MAX: float = 1000.0

# The sheet being edited. / 正在编辑的图纸。
var gpSheet: GPSheet = null

# Canvas to repaint after every change; null is fine (headless / no viewer).
# 每次改动后重绘的画布；为 null 亦可（headless / 无视图）。
var gpTarget: GPCanvas2D = null

# Show-frame checkbox. / 「显示图框」复选框。
var gpFrameCheck: CheckBox = null

# Sheet-size dropdown. / 图幅下拉框。
var gpSizeOption: OptionButton = null

# Drawing-text language dropdown. / 图纸文字语言下拉框。
var gpModeOption: OptionButton = null

# Margin spin boxes, ordered exactly like GPSheet.GP_FRAME_MARGINS_DEFAULT — [left, top, right, bottom].
# 边距数值框，顺序与 GPSheet.GP_FRAME_MARGINS_DEFAULT 完全一致 —— [左, 上, 右, 下]。
var gpMarginSpins: Array = []

# The title block's anchor-corner dropdown (Rev.3 stage 1). Its item index IS the anchor code, so the
# widget and the model cannot drift through a lookup table.
# 图签的锚角下拉框（Rev.3 阶段 1）。其**选项下标即锚角编码**，故控件与模型不会经由一张查表而失步。
var gpTbAnchorOption: OptionButton = null

# field key -> { "zh": LineEdit, "en": LineEdit }.
# 字段键 -> { "zh": 中文输入框, "en": 英文输入框 }。
var gpEdits: Dictionary = {}

# Tracing-underlay controls (v0.1 Phase 5). / 追踪底图控件（v0.1 Phase 5）。
var gpFileDialog: FileDialog = null
var gpBgPathEdit: LineEdit = null


# Bind the sheet and the canvas to repaint; call before showing.
# 绑定要编辑的图纸与要重绘的画布；显示前调用。
# [param gpS] the sheet to edit / 待编辑的图纸
# [param gpCanvas] canvas to repaint (may be null) / 需要重绘的画布（可为 null）
func gpConfigure(gpS: GPSheet, gpCanvas: GPCanvas2D = null) -> void:
	gpSheet = gpS
	gpTarget = gpCanvas


# Show the dialog centered over the host window.
# 居中显示在宿主窗口之上。
func gpPopupOverHost() -> void:
	var gpParent: Node = get_parent()
	var gpHost: Window = gpParent.get_window() if gpParent != null else null
	GPWindowFit.gpPopupFitted(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL)


func _ready() -> void:
	title = I18n.gpTr("frame.title")
	close_requested.connect(queue_free)
	var gpHost: Window = null
	var gpParent: Node = get_parent()
	if gpParent != null:
		gpHost = gpParent.get_window()
	GPWindowFit.gpApply(self, gpHost, GP_MIN_LOGICAL, GP_MAX_LOGICAL, false)
	_gpBuild()


# Build the whole dialog: frame options, then one row per title-block field.
# 构建整个对话框：先是图框选项，再是标题栏每个字段一行。
func _gpBuild() -> void:
	var gpRoot: MarginContainer = MarginContainer.new()
	gpRoot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpRoot.add_theme_constant_override("margin_left", 12)
	gpRoot.add_theme_constant_override("margin_right", 12)
	gpRoot.add_theme_constant_override("margin_top", 12)
	gpRoot.add_theme_constant_override("margin_bottom", 12)
	add_child(gpRoot)
	var gpVBox: VBoxContainer = VBoxContainer.new()
	gpVBox.add_theme_constant_override("separation", 8)
	gpRoot.add_child(gpVBox)
	if gpSheet == null:
		return
	_gpBuildOptions(gpVBox)
	_gpBuildMargins(gpVBox)
	_gpBuildDocking(gpVBox)
	_gpBuildBackground(gpVBox)
	var gpScroll: ScrollContainer = ScrollContainer.new()
	gpScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpVBox.add_child(gpScroll)
	var gpGrid: GridContainer = GridContainer.new()
	gpGrid.columns = 3
	gpGrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpGrid.add_theme_constant_override("h_separation", 8)
	gpGrid.add_theme_constant_override("v_separation", 6)
	gpScroll.add_child(gpGrid)
	_gpBuildFieldRows(gpGrid)
	var gpOk: Button = Button.new()
	gpOk.text = I18n.gpTr("dialog.ok")
	gpOk.pressed.connect(queue_free)
	gpVBox.add_child(gpOk)


# Frame on/off, sheet size and label-mode controls.
# 图框开关、图幅与标签模式控件。
func _gpBuildOptions(gpVBox: VBoxContainer) -> void:
	gpFrameCheck = CheckBox.new()
	gpFrameCheck.text = I18n.gpTr("frame.show")
	gpFrameCheck.button_pressed = gpSheet.gpFrameOn
	gpFrameCheck.toggled.connect(_gpOnFrameToggled)
	gpVBox.add_child(gpFrameCheck)

	var gpSizeRow: HBoxContainer = HBoxContainer.new()
	var gpSizeLabel: Label = Label.new()
	gpSizeLabel.text = I18n.gpTr("frame.size")
	gpSizeLabel.custom_minimum_size = Vector2(120.0, 0.0)
	gpSizeRow.add_child(gpSizeLabel)
	gpSizeOption = OptionButton.new()
	gpSizeOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Biggest first, so "A3" (the default) is not buried at the end of the list.
	# 由大到小排列，使默认值 A3 不至于埋在列表末尾。
	for gpK in ["A0", "A1", "A2", "A3", "A4"]:
		gpSizeOption.add_item(gpK)
		gpSizeOption.set_item_metadata(gpSizeOption.item_count - 1, gpK)
	_gpSelectSize(gpKFor(gpSheet.gpWidthMM, gpSheet.gpHeightMM))
	gpSizeOption.item_selected.connect(_gpOnSizeSelected)
	gpSizeRow.add_child(gpSizeOption)
	gpVBox.add_child(gpSizeRow)

	var gpModeRow: HBoxContainer = HBoxContainer.new()
	var gpModeLabel: Label = Label.new()
	gpModeLabel.text = I18n.gpTr("frame.label_mode")
	gpModeLabel.custom_minimum_size = Vector2(120.0, 0.0)
	gpModeRow.add_child(gpModeLabel)
	gpModeOption = OptionButton.new()
	gpModeOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpModeOption.add_item(I18n.gpTr("frame.mode_zh"), GPSheet.GP_LABEL_ZH)
	gpModeOption.add_item(I18n.gpTr("frame.mode_en"), GPSheet.GP_LABEL_EN)
	gpModeOption.add_item(I18n.gpTr("frame.mode_both"), GPSheet.GP_LABEL_BOTH)
	gpModeOption.select(_gpModeIndex(gpSheet.gpLabelMode))
	gpModeOption.item_selected.connect(_gpOnModeSelected)
	gpModeRow.add_child(gpModeOption)
	gpVBox.add_child(gpModeRow)

	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("frame.mode_hint")
	gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpHint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	gpHint.custom_minimum_size = Vector2(0.0, 34.0)
	gpVBox.add_child(gpHint)


# Frame-margin section: four spin boxes mirroring GPSheet.gpFrameMargins, plus a one-click reset.
# 图框边距段落：四个数值框对应 GPSheet.gpFrameMargins，外加一键复位。
#
# ⚠️ WHY IT COMMITS THROUGH THE CANVAS AND NOT THE MODEL / 为何经画布提交而非直写模型：changing a
# margin is an undoable edit like any other, and the drag path already commits through
# GPMutateSheetCommand. Writing gpSetFrameMargins() straight onto the model would leave this dialog as
# the ONE write path in the editor that cannot be taken back — precisely the hole Rev.3 set out to
# close. gpTarget is null only with no viewer at all (headless), where there is no undo stack to join.
# ⚠️ 改一条边距与任何其它编辑一样应当是**可撤销**的，而拖拽路径本就经 GPMutateSheetCommand 提交。直接在模型
# 上调 gpSetFrameMargins() 会让本对话框成为编辑器中唯一**收不回来**的写入路径 —— 那正是 Rev.3 要堵的洞。
# 只有当完全没有视图（headless）时 gpTarget 才为 null，那时本来也没有可加入的撤销栈。
#
# ⚠️ WHY A RESET BUTTON IS NOT A LUXURY / 为何「复位」不是奢侈品：now that the frame may leave the
# paper, "I dragged it somewhere and cannot find it" becomes reachable for the first time. Undo also
# recovers it — but undo asks the user to remember that the LAST thing they did was that drag; a button
# does not.
# ⚠️ 既然图框可以离开纸面，「我把它拖到某处、找不到了」就第一次成为可能。撤销也能救回来 —— 但撤销要求用户
# 记得最后一次操作就是那次拖拽；按钮不要求这个。
func _gpBuildMargins(gpVBox: VBoxContainer) -> void:
	var gpSec: Label = Label.new()
	gpSec.text = I18n.gpTr("frame.margin.title")
	gpVBox.add_child(gpSec)
	# Seed the boxes from the GEOMETRY layer, i.e. from the values the frame is actually drawn with —
	# not from the raw field, which may hold an inside-out pair that layer has already repaired.
	# 数值框由**几何层**取值播种，即图框**实际据此绘制**的那组值 —— 而非原始字段，后者可能持有已被该层修复
	# 过的内翻对边距。
	var gpNow: Array = GPFrameGeometry.gpEffectiveMargins(gpSheet)
	var gpKeys: Array = [
		"frame.margin.left", "frame.margin.top", "frame.margin.right", "frame.margin.bottom",
	]
	var gpRow: HBoxContainer = HBoxContainer.new()
	for gpI in gpKeys.size():
		var gpLbl: Label = Label.new()
		gpLbl.text = I18n.gpTr(str(gpKeys[gpI]))
		gpRow.add_child(gpLbl)
		var gpSpin: SpinBox = SpinBox.new()
		gpSpin.min_value = GP_MARGIN_SPIN_MIN
		gpSpin.max_value = GP_MARGIN_SPIN_MAX
		gpSpin.step = 0.5
		gpSpin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gpSpin.value = float(gpNow[gpI])
		gpSpin.value_changed.connect(_gpOnMarginChanged)
		gpRow.add_child(gpSpin)
		gpMarginSpins.append(gpSpin)
	gpVBox.add_child(gpRow)
	var gpReset: Button = Button.new()
	gpReset.text = I18n.gpTr("frame.margin.reset")
	gpReset.pressed.connect(_gpOnMarginReset)
	gpVBox.add_child(gpReset)
	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("frame.margin.hint")
	gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpHint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	gpHint.custom_minimum_size = Vector2(0.0, 34.0)
	gpVBox.add_child(gpHint)


# Title-block docking: which inner corner the block hugs (Rev.3 stage 1).
# 图签停靠：图签贴住哪个内角（Rev.3 阶段 1）。
#
# ⚠️ THE OFFSET IS DELIBERATELY NOT A NUMBER BOX / ⚠️ 偏移**刻意**不做数值框：a distance is chosen by
# dragging, and the drag snaps it to the edges — exposing a millimetre box here would be a second and worse
# way to say the same thing, and the two would then have to be kept in step by hand. The corner, by
# contrast, is genuinely awkward to pick with a pointer (you must first find the block, then drag it across
# the frame), so it gets the widget.
# 距离是靠拖拽选出来的、且拖拽会把它吸附到边上 —— 在这里暴露一个毫米数值框会是表达同一件事的第二种、更差的
# 方式，且两者此后就得靠手工保持同步。而「哪个角」用指针选确实别扭（先得找到图签，再把它拖过整张图框），
# 故给它一个控件。
#
# ⚠️ THE ITEM ORDER IS THE ANCHOR CODE — index == value, no lookup table that could fall out of step with
# GPSheet's constants. If a fifth corner is ever invented, it is added at the end and the code changes with
# it, in the same commit.
# ⚠️ **选项顺序即锚角编码** —— 下标 == 取值，没有会与 GPSheet 常量失步的查表。若将来造出第五个角，它追加在
# 末尾、编码随之改变，且在同一个提交里一起改。
func _gpBuildDocking(gpVBox: VBoxContainer) -> void:
	var gpSec: Label = Label.new()
	gpSec.text = I18n.gpTr("frame.tb.title")
	gpVBox.add_child(gpSec)
	var gpRow: HBoxContainer = HBoxContainer.new()
	var gpLbl: Label = Label.new()
	gpLbl.text = I18n.gpTr("frame.tb.anchor")
	gpLbl.custom_minimum_size = Vector2(60.0, 0.0)
	gpRow.add_child(gpLbl)
	gpTbAnchorOption = OptionButton.new()
	gpTbAnchorOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpTbAnchorOption.add_item(I18n.gpTr("frame.tb.anchor.br"))
	gpTbAnchorOption.add_item(I18n.gpTr("frame.tb.anchor.bl"))
	gpTbAnchorOption.add_item(I18n.gpTr("frame.tb.anchor.tr"))
	gpTbAnchorOption.add_item(I18n.gpTr("frame.tb.anchor.tl"))
	gpTbAnchorOption.selected = clampi(gpSheet.gpTbAnchor,
		GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, GPSheet.GP_TB_ANCHOR_TOP_LEFT)
	gpTbAnchorOption.item_selected.connect(_gpOnTbAnchorSelected)
	gpRow.add_child(gpTbAnchorOption)
	gpVBox.add_child(gpRow)
	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("frame.tb.hint")
	gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpHint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	gpHint.custom_minimum_size = Vector2(0.0, 34.0)
	gpVBox.add_child(gpHint)


# The four spin values as [left, top, right, bottom]. / 四个数值框的取值，形如 [左, 上, 右, 下]。
func _gpReadSpins() -> Array:
	var gpOut: Array = []
	for gpSpin in gpMarginSpins:
		gpOut.append((gpSpin as SpinBox).value)
	return gpOut


# Write four values into the boxes WITHOUT re-emitting value_changed.
# 把四个值写进数值框，且**不**再发出 value_changed。
#
# ⚠️ THE GUARD IS NOT AN OPTIMISATION: assigning `value` emits value_changed too, so an unguarded
# write-back would recurse — and, worse, would fight the user by overwriting the box they are typing in
# with whatever the model happened to keep.
# ⚠️ 这道护栏不是优化：给 `value` 赋值同样会发出 value_changed，故不加护栏的回写会递归 —— 更糟的是会与用户
# 抢编辑，把他们正在输入的框覆盖成模型碰巧留下的值。
func _gpSetSpins(gpValues: Array) -> void:
	for gpI in gpMarginSpins.size():
		if gpI >= gpValues.size():
			break
		var gpSpin: SpinBox = gpMarginSpins[gpI]
		if is_equal_approx(gpSpin.value, float(gpValues[gpI])):
			continue
		gpSpin.set_block_signals(true)
		gpSpin.value = float(gpValues[gpI])
		gpSpin.set_block_signals(false)


# Tracing-underlay section: image path + browse/clear, and an opacity slider.
# 追踪底图段落：图片路径 + 浏览/清除，以及透明度滑块。
func _gpBuildBackground(gpVBox: VBoxContainer) -> void:
	var gpSec: Label = Label.new()
	gpSec.text = I18n.gpTr("frame.bg.title")
	gpVBox.add_child(gpSec)

	# Path row: editable text + a file picker + a clear button.
	# 路径行：可编辑文本 + 文件选择器 + 清除按钮。
	var gpPathRow: HBoxContainer = HBoxContainer.new()
	gpBgPathEdit = LineEdit.new()
	gpBgPathEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpBgPathEdit.placeholder_text = I18n.gpTr("frame.bg.path")
	gpBgPathEdit.text = gpSheet.gpBackgroundPath
	gpBgPathEdit.text_changed.connect(func(gpT: String) -> void: _gpOnBgPath(gpT))
	gpPathRow.add_child(gpBgPathEdit)
	var gpBrowse: Button = Button.new()
	gpBrowse.text = I18n.gpTr("frame.bg.browse")
	gpBrowse.pressed.connect(_gpOpenBrowse)
	gpPathRow.add_child(gpBrowse)
	var gpClear: Button = Button.new()
	gpClear.text = I18n.gpTr("frame.bg.clear")
	gpClear.pressed.connect(func() -> void: _gpOnBgPath(""))
	gpPathRow.add_child(gpClear)
	gpVBox.add_child(gpPathRow)

	# Opacity row: a slider in [0.05, 1.0] so the underlay stays a faint reference.
	# 透明度行：滑块范围 [0.05, 1.0]，使底图始终为淡参考。
	var gpAlphaRow: HBoxContainer = HBoxContainer.new()
	var gpAlphaLabel: Label = Label.new()
	gpAlphaLabel.text = I18n.gpTr("frame.bg.alpha")
	gpAlphaLabel.custom_minimum_size = Vector2(120.0, 0.0)
	gpAlphaRow.add_child(gpAlphaLabel)
	var gpAlpha: HSlider = HSlider.new()
	gpAlpha.min_value = 0.05
	gpAlpha.max_value = 1.0
	gpAlpha.step = 0.05
	gpAlpha.value = gpSheet.gpBackgroundAlpha
	gpAlpha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpAlpha.value_changed.connect(func(gpV: float) -> void: _gpOnBgAlpha(gpV))
	gpAlphaRow.add_child(gpAlpha)
	gpVBox.add_child(gpAlphaRow)

	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("frame.bg.hint")
	gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpHint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	gpHint.custom_minimum_size = Vector2(0.0, 30.0)
	gpVBox.add_child(gpHint)

	# File picker is a child so it is freed with this dialog.
	# 文件选择器作为子节点，随本对话框一并释放。
	gpFileDialog = FileDialog.new()
	gpFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	gpFileDialog.access = FileDialog.ACCESS_FILESYSTEM
	gpFileDialog.add_filter("*.png,*.jpg,*.jpeg,*.webp", "Image")
	gpFileDialog.file_selected.connect(_gpOnBgFilePicked)
	add_child(gpFileDialog)


# One row per standard field: bilingual caption, then the zh / en value inputs.
# 每个标准字段一行：双语字段名，后接中文 / 英文取值输入框。
func _gpBuildFieldRows(gpGrid: GridContainer) -> void:
	for gpF in GPSheet.GP_TB_FIELDS:
		var gpKey: String = str(gpF["key"])
		var gpCap: Label = Label.new()
		gpCap.text = I18n.gpTrBoth(str(gpF["cap"]))
		gpCap.custom_minimum_size = Vector2(110.0, 0.0)
		gpGrid.add_child(gpCap)
		var gpZh: LineEdit = LineEdit.new()
		gpZh.placeholder_text = I18n.gpTr("frame.col_zh")
		gpZh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gpZh.text = _gpValueOf(gpKey, "zh")
		gpZh.text_changed.connect(func(gpT: String) -> void: _gpOnValueChanged(gpKey, "zh", gpT))
		gpGrid.add_child(gpZh)
		var gpEn: LineEdit = LineEdit.new()
		gpEn.placeholder_text = I18n.gpTr("frame.col_en")
		gpEn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gpEn.text = _gpValueOf(gpKey, "en")
		gpEn.text_changed.connect(func(gpT: String) -> void: _gpOnValueChanged(gpKey, "en", gpT))
		gpGrid.add_child(gpEn)
		gpEdits[gpKey] = {"zh": gpZh, "en": gpEn}


# Read one language slot of one field, tolerating a missing entry.
# 读取某字段某一语言槽的值；条目缺失时容错。
func _gpValueOf(gpKey: String, gpLang: String) -> String:
	var gpEntry: Variant = gpSheet.gpTitleBlock.get(gpKey)
	if gpEntry == null:
		return ""
	var gpVal: Variant = (gpEntry as Dictionary).get("value")
	if gpVal == null:
		return ""
	return str((gpVal as Dictionary).get(gpLang, ""))


func _gpOnValueChanged(gpKey: String, gpLang: String, gpText: String) -> void:
	var gpEntry: Variant = gpSheet.gpTitleBlock.get(gpKey)
	if gpEntry == null:
		gpEntry = {"value": {"zh": "", "en": ""}}
		gpSheet.gpTitleBlock[gpKey] = gpEntry
	var gpVal: Variant = (gpEntry as Dictionary).get("value")
	if gpVal == null:
		gpVal = {"zh": "", "en": ""}
		(gpEntry as Dictionary)["value"] = gpVal
	(gpVal as Dictionary)[gpLang] = gpText
	_gpRepaint()


func _gpOnFrameToggled(gpOn: bool) -> void:
	gpSheet.gpFrameOn = gpOn
	_gpRepaint()


func _gpOnSizeSelected(_gpIdx: int) -> void:
	var gpK: String = str(gpSizeOption.get_selected_metadata())
	var gpV: Vector2 = GPSheet.GP_SHEET_PRESETS.get(gpK, GPSheet.GP_SHEET_PRESETS["A3"])
	gpSheet.gpWidthMM = gpV.x
	gpSheet.gpHeightMM = gpV.y
	# Keep the SIZE cell honest: it is derived from the real sheet, not typed by hand.
	# 让「图幅」格保持诚实：它由图幅推导，而非手填。
	gpSheet.gpSyncSheetSizeField()
	var gpE: Dictionary = gpEdits.get("sheet_size", {}) as Dictionary
	if gpE.has("zh"):
		(gpE["zh"] as LineEdit).text = gpK
		(gpE["en"] as LineEdit).text = gpK
	_gpRepaint()


func _gpOnModeSelected(gpIdx: int) -> void:
	gpSheet.gpLabelMode = int(gpModeOption.get_item_id(gpIdx))
	_gpRepaint()


# One margin box moved: commit all four as ONE undo step — the command takes the whole array, so a
# four-box edit does not become four entries in the undo menu.
# 某个边距框变动：把四条边距作为**一个**撤销步提交 —— 命令收的是整份数组，故四个框的编辑不会在撤销菜单里
# 变成四条记录。
func _gpOnMarginChanged(_gpValue: float) -> void:
	_gpApplyMargins(_gpReadSpins())


# Reset every margin to the standard default and commit that as one undo step as well, so the rescue
# itself can be taken back.
# 把每条边距复位到标准默认值，同样作为**一个**撤销步提交 —— 使「救命」这个动作本身也可以被撤销。
func _gpOnMarginReset() -> void:
	_gpApplyMargins(GPSheet.GP_FRAME_MARGINS_DEFAULT.duplicate())


# Commit one margin array — through the canvas (-> GPMutateSheetCommand) when a canvas is bound, else
# straight onto the model — and then MIRROR back whatever the model actually kept.
# 提交一份边距数组 —— 有画布绑定时经画布（-> GPMutateSheetCommand），否则直接写模型 —— 随后把模型
# **实际留下**的值回映到控件上。
#
# ⚠️ THE MIRROR IS NOT COSMETIC / 回映不是装饰：the write path may alter what it was handed (an
# inside-out pair is repaired by GPSheet.gpClampMargins). Without the mirror the boxes would keep
# showing the impossible numbers that were typed while the frame drew something else — one question with
# two answers, which is how the next person loses an afternoon.
# ⚠️ 写入路径可能改动它收到的值（内翻的对边距会被 GPSheet.gpClampMargins 修复）。若不回映，数值框会继续
# 显示用户键入的那个不可能的值、而图框画的是另一个 —— 同一个问题两个答案，下一个人就会为此丢掉一下午。
#
# ⚠️ THE EXPLICIT REFRESH BELOW IS BELT AND BRACES, NOT THE MECHANISM: the command emits
# GPSheet.gpSheetChanged, which GPSheetLayer already subscribes to for exactly this purpose. The two
# calls are kept only because the drag path makes the same ones, and they are idempotent.
# ⚠️ 下方显式刷新是**双保险而非机制**：命令会发出 GPSheet.gpSheetChanged，而 GPSheetLayer 本就为此订阅了
# 它。这两行只因为拖拽路径也这么做而保留，且它们是幂等的。
func _gpApplyMargins(gpValues: Array) -> void:
	if gpTarget != null:
		gpTarget.gpRequestSetFrameMargins(gpValues)
		gpTarget.gpRefreshSheetFrame()
		gpTarget.queue_redraw()
	else:
		gpSheet.gpSetFrameMargins(gpValues)
	_gpSetSpins(gpSheet.gpFrameMargins)


# The user picked another anchor corner (Rev.3 stage 1).
# 用户选了另一个锚角（Rev.3 阶段 1）。
#
# ⚠️ THE OFFSET IS KEPT, DELIBERATELY / ⚠️ **刻意**保留偏移：it measures the distance from whichever edge is
# hugged, so it stays meaningful under any anchor. Resetting it here would silently also undo "how far from
# the edge the block sat" — the user asked to move the block to another corner, not to push it flush against
# it. (Note the reverse is not true: a drag overwrites the offset, because a drag IS a statement about the
# distance.)
# 它量的是「到所贴那条边的距离」，故在任何锚角下都有意义。在此复位会连带静默撤销「图签离边多远」—— 用户要
# 的是把图签挪到另一个角，不是把它推到贴边。（反过来不成立：拖拽会覆写偏移，因为拖拽**就是**对距离的陈述。）
func _gpOnTbAnchorSelected(gpIdx: int) -> void:
	_gpApplyTbPlacement(gpIdx, gpSheet.gpTbOffset)


# Commit a docking pair — through the canvas (-> GPMutateSheetCommand) when a canvas is bound, else straight
# onto the model — and then MIRROR back whatever the model actually kept.
# 提交一个停靠对 —— 有画布绑定时经画布（-> GPMutateSheetCommand），否则直接写模型 —— 随后把模型**实际
# 留下**的值回映到控件上。
#
# ⚠️ THE MIRROR IS NOT COSMETIC / 回映不是装饰：the write path may alter what it was handed (the offset is
# clamped against the inner rectangle, which may be smaller than the block). Without the mirror the dropdown
# could keep showing a corner the block does not actually hug — one question with two answers.
# 写入路径可能改动它收到的值（偏移会针对内框被钳制，而内框可能比图块还小）。若不回映，下拉会继续显示一个图签
# 实际并未贴住的角 —— 同一个问题两个答案。
func _gpApplyTbPlacement(gpAnchor: int, gpOffset: Vector2) -> void:
	if gpTarget != null:
		gpTarget.gpRequestSetTitleBlockPlacement(gpAnchor, gpOffset)
		gpTarget.gpRefreshSheetFrame()
		gpTarget.queue_redraw()
	else:
		gpSheet.gpSetTbPlacement(gpAnchor, gpOffset)
	if gpTbAnchorOption != null:
		gpTbAnchorOption.set_block_signals(true)
		gpTbAnchorOption.selected = clampi(gpSheet.gpTbAnchor,
			GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, GPSheet.GP_TB_ANCHOR_TOP_LEFT)
		gpTbAnchorOption.set_block_signals(false)


func _gpOpenBrowse() -> void:
	if gpFileDialog != null:
		gpFileDialog.popup_centered(Vector2i(720, 480))


func _gpOnBgFilePicked(gpPath: String) -> void:
	gpSheet.gpBackgroundPath = gpPath
	if gpBgPathEdit != null:
		gpBgPathEdit.text = gpPath
	_gpRepaint()


func _gpOnBgPath(gpPath: String) -> void:
	gpSheet.gpBackgroundPath = gpPath
	_gpRepaint()


func _gpOnBgAlpha(gpV: float) -> void:
	gpSheet.gpBackgroundAlpha = gpV
	_gpRepaint()


# Push the edited sheet back to the canvas so the frame redraws.
# 把编辑后的图纸推回画布，使图框重绘。
func _gpRepaint() -> void:
	if gpTarget != null:
		gpTarget.gpSetSheet(gpSheet)


# Option-button row matching the sheet's current size.
# 选中与当前图幅匹配的下拉项。
func _gpSelectSize(gpK: String) -> void:
	for gpI in range(gpSizeOption.item_count):
		if str(gpSizeOption.get_item_metadata(gpI)) == gpK:
			gpSizeOption.select(gpI)
			return


func _gpModeIndex(gpMode: int) -> int:
	for gpI in range(gpModeOption.item_count):
		if gpModeOption.get_item_id(gpI) == gpMode:
			return gpI
	return 0


# Nearest preset name for a size; "" when the size is custom.
# 尺寸最接近的预设名；自定义尺寸时为空串。
static func gpKFor(gpW: float, gpH: float) -> String:
	for gpK in GPSheet.GP_SHEET_PRESETS:
		var gpV: Vector2 = GPSheet.GP_SHEET_PRESETS[gpK]
		if absf(gpV.x - gpW) < 0.5 and absf(gpV.y - gpH) < 0.5:
			return str(gpK)
	return ""
