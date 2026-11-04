class_name GPCanvasPane
extends PanelContainer
# Copyright © 2026 Jonson Wang
#
# ONE multi-view pane (ADR-44, W13-S6): a slim header (sheet picker + pop-out button) above
# a host area that an existing GPCanvas2D is REPARENTED into. The pane owns NO canvas and NO
# document state — ADR-44 D1: canvases are created once per sheet and merely re-homed, so a
# layout switch never rebuilds a single view node.
# 一个多视图窗格（ADR-44，W13-S6）：纤细头部（图纸选择器 + 摘出按钮）+ 一个承载区，既有的
# GPCanvas2D 被 **reparent** 进来。窗格不持有画布、不持有文档状态 —— ADR-44 D1：画布每张图纸
# 只建一次、只换宿主，故切换布局绝不重建任何视图节点。
#
# Focus semantics (ADR-44 D4): the canvas keeps FOCUS_CLICK, so the first click inside a pane
# focuses the canvas; the pane forwards that as gpPaneFocused and the center area collapses
# "which sheet do the docks serve" onto THAT pane. The active pane wears the same accent
# underline the selected sheet tab has.
# 焦点语义（ADR-44 D4）：画布保持 FOCUS_CLICK，故窗格内第一击即让画布获焦；窗格把它转成
# gpPaneFocused，中间区据此把「侧栏服务于哪张图」收口到**那个**窗格。活动窗格佩戴与选中
# 图纸 tab 同款的 accent 底线。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The user picked a sheet for THIS pane from the picker.
# 用户在本窗格的选择器里选定了一张图纸。
signal gpSheetPicked(gpPane: GPCanvasPane, gpSheetIdx: int)

# The pop-out button was pressed (W13-S7: move the pane's canvas into an embedded Window).
# 摘出按钮被按下（W13-S7：把窗格画布移入嵌入式 Window）。
signal gpPopoutRequested(gpPane: GPCanvasPane)

# The canvas inside this pane gained focus — make THIS the active pane.
# 本窗格内的画布获得焦点 —— 以本窗格为活动窗格。
signal gpPaneFocused(gpPane: GPCanvasPane)

# The area a canvas is reparented into.
# 画布 reparent 进来的承载区。
var gpHost: Control

# The slim header (picker + pop-out). Public so the center area can hide it in single-view
# (D22: one pane + tab bar = the header is pure duplication) and grey out the pop button
# while another pane's canvas is already popped out.
# 纤细头部（选择器 + 摘出）。公开使中间区能在单视图下隐藏它（D22：单窗格 + 标签栏 =
# 头部纯属重复），并在已有画布被摘出时把摘出按钮置灰。
var gpHeader: HBoxContainer

# The sheet picker (all sheets; the center area fills and disables entries).
# 图纸选择器（列出全部图纸；由中间区填充并禁用被占条目）。
var gpPick: OptionButton

# The pop-out button. / 摘出按钮。
var gpPopBtn: Button

# Which sheet tab this pane shows (GPPaneLayout.GP_EMPTY while empty).
# 本窗格显示的图纸标签下标（空时为 GPPaneLayout.GP_EMPTY）。
var gpSheetIdx: int = GPPaneLayout.GP_EMPTY

# Whether THIS pane is the active one (drives the accent underline).
# 本窗格是否为活动窗格（驱动 accent 底线）。
var gpActive: bool = false:
	set(gpOn):
		gpActive = gpOn
		_gpRestyle()

# The placeholder shown while no canvas is attached.
# 未挂画布时显示的占位符。
var _gpHint: Label

# The currently attached canvas (null while empty or popped out).
# 当前挂载的画布（空或已摘出时为 null）。
var _gpCanvas: GPCanvas2D = null


func _ready() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	# The pane body is one column: header row, then the canvas host. The accent underline is
	# painted by THIS node's "panel" stylebox (see _gpRestyle).
	# 窗格主体为一列：头部行，然后是画布承载区。accent 底线由本节点的 "panel" 样式盒绘制
	#（见 _gpRestyle）。
	var gpCol: VBoxContainer = VBoxContainer.new()
	gpCol.add_theme_constant_override("separation", 0)
	add_child(gpCol)
	# ---- header ---- / ---- 头部 ----
	var gpHeaderRow: HBoxContainer = HBoxContainer.new()
	gpHeader = gpHeaderRow
	gpHeaderRow.custom_minimum_size = Vector2(0.0, 22.0)
	gpHeaderRow.size_flags_vertical = SIZE_SHRINK_BEGIN
	gpHeaderRow.add_theme_constant_override("separation", 2)
	gpCol.add_child(gpHeaderRow)
	# D22: a click on the pane HEADER (not just the canvas) activates the pane too — the
	# header is part of the pane's identity, and aiming at it is aiming at the pane.
	# D22：点击窗格**头部**（而不只是画布）同样激活本窗格 —— 头部是窗格身份的一部分，
	# 瞄准它就是瞄准窗格。
	gpHeaderRow.gui_input.connect(_gpOnHeaderInput)
	gpPick = OptionButton.new()
	gpPick.size_flags_horizontal = SIZE_EXPAND_FILL
	gpPick.size_flags_vertical = SIZE_SHRINK_CENTER
	gpPick.custom_minimum_size = Vector2(0.0, 20.0)
	gpPick.focus_mode = Control.FOCUS_NONE
	gpPick.clip_text = true
	gpPick.item_selected.connect(_gpOnPicked)
	gpHeader.add_child(gpPick)
	gpPopBtn = Button.new()
	gpPopBtn.tooltip_text = I18n.gpTr("center.popout_tip")
	gpPopBtn.focus_mode = Control.FOCUS_NONE
	gpPopBtn.custom_minimum_size = Vector2(22.0, 20.0)
	gpPopBtn.pressed.connect(func() -> void: gpPopoutRequested.emit(self))
	var gpIcon: Texture2D = load("res://assets/icons/popout.svg") as Texture2D
	if gpIcon != null:
		gpPopBtn.icon = gpIcon
	gpPopBtn.add_theme_constant_override("icon_max_width", 12)
	gpHeader.add_child(gpPopBtn)
	# ---- host + placeholder ---- / ---- 承载区 + 占位符 ----
	gpHost = Control.new()
	gpHost.size_flags_horizontal = SIZE_EXPAND_FILL
	gpHost.size_flags_vertical = SIZE_EXPAND_FILL
	gpHost.clip_contents = true
	gpCol.add_child(gpHost)
	_gpHint = Label.new()
	_gpHint.text = I18n.gpTr("center.pane_empty")
	_gpHint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_gpHint.modulate = Color(1.0, 1.0, 1.0, 0.45)
	gpHost.add_child(_gpHint)
	I18n.gpLocaleChanged.connect(_gpOnLocale)
	_gpRestyle()


# Attach a canvas: reparent it under the host, fill the host, hide the placeholder, and route
# its focus to gpPaneFocused. Safe to call with null (just shows the placeholder).
# 挂载画布：reparent 到承载区下、铺满、隐藏占位符，并把它的焦点路由到 gpPaneFocused。
# 传 null 亦安全（只显示占位符）。
func gpAttachCanvas(gpCv: GPCanvas2D) -> void:
	if _gpCanvas != null and is_instance_valid(_gpCanvas):
		if not _gpCanvas.focus_entered.is_connected(gpEmitFocused):
			_gpCanvas.focus_entered.disconnect(gpEmitFocused)
		if _gpCanvas != gpCv and _gpCanvas.get_parent() != null:
			_gpCanvas.get_parent().remove_child(_gpCanvas)
	_gpCanvas = gpCv
	if gpCv == null:
		_gpHint.visible = true
		return
	_gpHint.visible = false
	gpHost.add_child(gpCv)
	gpCv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpCv.visible = true
	if not gpCv.focus_entered.is_connected(gpEmitFocused):
		gpCv.focus_entered.connect(gpEmitFocused)


# The canvas is leaving (pane teardown or pop-out): stop routing its focus and forget it.
# 画布即将离开（窗格拆除或摘出）：停止焦点路由并遗忘它。
func gpDetachCanvas() -> GPCanvas2D:
	if _gpCanvas == null:
		return null
	if _gpCanvas.focus_entered.is_connected(gpEmitFocused):
		_gpCanvas.focus_entered.disconnect(gpEmitFocused)
	# The canvas must PHYSICALLY leave the host, not merely be forgotten: a layout switch
	# queue_free()s the whole pane tree right after this call, and a canvas still parented
	# inside it would die WITH the tree while gpTabs keeps holding it — the "Trying to cast
	# a freed object" crash and the permanently blank panes after a layout switch.
	# 画布必须**物理离开**承载区，而不仅是被遗忘：切换布局会在本调用之后立刻 queue_free()
	# 整棵窗格树，仍挂在里面的画布会随树一起释放，而 gpTabs 还持有它 —— 「Trying to cast
	# a freed object」崩溃与切换布局后画布永久空白皆源于此。
	if _gpCanvas.get_parent() != null:
		_gpCanvas.get_parent().remove_child(_gpCanvas)
	var gpOut: GPCanvas2D = _gpCanvas
	_gpCanvas = null
	if _gpHint != null:
		_gpHint.visible = true
	return gpOut


# The attached canvas, if any. / 当前挂载的画布（若有）。
func gpCanvas() -> GPCanvas2D:
	return _gpCanvas if _gpCanvas != null and is_instance_valid(_gpCanvas) else null


# Focus forwarding (also the disconnect target — a method, not a lambda, so it can unbind).
# 焦点转发（同时是断连目标 —— 用方法而非 lambda，才能解绑）。
func gpEmitFocused() -> void:
	gpPaneFocused.emit(self)


# The picker says: show this sheet here. / 选择器：在此显示该图纸。
func _gpOnPicked(gpIdx: int) -> void:
	gpSheetPicked.emit(self, gpIdx)


# D22: show/hide the pane header. Single view hides it (the tab bar already carries the
# picker and the menu carries the pop-out entry); multi-view panes keep it — with several
# panes each needs its own picker at hand.
# D22：显示/隐藏窗格头部。单视图隐藏（标签栏已承载选择器、菜单承载摘出入口）；多视图窗格
# 保留 —— 多窗格时每个窗格都需要手边的选择器。
func gpSetChromeVisible(gpOn: bool) -> void:
	if gpHeader != null:
		gpHeader.visible = gpOn


# D22: header click = pane focus. / D22：头部点击 = 窗格激活。
func _gpOnHeaderInput(gpEv: InputEvent) -> void:
	if gpEv is InputEventMouseButton and gpEv.pressed \
			and gpEv.button_index == MOUSE_BUTTON_LEFT:
		gpPaneFocused.emit(self)


# Active panes wear the selected-tab look (dark fill + accent bottom border) — D22 adds an
# accent bar down the LEFT edge and an accent-tinted picker caption, so the active pane reads
# at a glance even when panes sit far apart; inactive ones stay dock-toned.
# 活动窗格佩戴选中 tab 的外观（深底 + accent 下边框）—— D22 再加**左缘** accent 竖条与
# accent 色选择器标题，使活动窗格即使相距很远也一眼可辨；非活动保持 dock 色。
func _gpRestyle() -> void:
	var gpSb: StyleBoxFlat = GPChromeStyle.gpStyleFor(GPChromeStyle.GP_DOCK_BG, 0)
	gpSb.content_margin_left = 2.0
	gpSb.content_margin_right = 2.0
	gpSb.content_margin_top = 0.0
	gpSb.content_margin_bottom = 0.0
	if gpActive:
		gpSb.bg_color = Color(0.129, 0.165, 0.204)
		gpSb.border_color = GPChromeStyle.GP_ACCENT
		gpSb.border_width_bottom = 1
		gpSb.border_width_left = 2
	add_theme_stylebox_override("panel", gpSb)
	if gpPick != null:
		if gpActive:
			gpPick.add_theme_color_override("font_color", GPChromeStyle.GP_ACCENT)
		else:
			gpPick.remove_theme_color_override("font_color")


# Locale changed: refresh the placeholder and the pop-out tooltip.
# 语言变化：刷新占位符与摘出按钮提示。
func _gpOnLocale(_gpLocale: String) -> void:
	_gpHint.text = I18n.gpTr("center.pane_empty")
	gpPopBtn.tooltip_text = I18n.gpTr("center.popout_tip")
