class_name GPPIDRibbon
extends Panel

# Ribbon-style top command bar (P0, ADR-UI-01). Replaces the old flat text
# toolbar with an AutoCAD/Office-like TabContainer: each tab groups related
# commands into icon+text buttons. The Ribbon is a SELF-CONTAINED container —
# to revert to the previous layout, the host only stops building it and calls
# the old _gpBuildToolBar instead (see main_window.gd). No other node depends
# on it, so it is fully reversible.
# Ribbon 式顶部命令区（P0，ADR-UI-01）。以 AutoCAD/Office 风格的 TabContainer 取代
# 原平铺文字工具栏：每个标签把相关命令按功能分组为「图标+文字」按钮。Ribbon 是
# 自包含容器——回退旧布局只需宿主停止构建它、改回 _gpBuildToolBar（见 main_window.gd），
# 无其他节点依赖它，故完全可逆。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# A command was triggered from a ribbon button (its action name).
# 从 Ribbon 按钮触发了某条命令（返回动作名）。
signal gpActionTriggered(action: String)

# Tab definitions. title_key is an i18n key; each group holds a caption key and a
# list of button specs. "toggle" buttons keep their pressed highlight and are
# tracked for mode-sync; "mode" is the GPCanvas2D.GPMode they map to.
# 标签定义。title_key 为 i18n 键；每个 group 含标题键与按钮规格列表。"toggle" 按钮
# 保持按下高亮并被记录以同步模式；"mode" 为该按钮对应的 GPCanvas2D.GPMode。
const GP_TABS: Array = [
	{
		"title_key": "ribbon.tab_home",
		"groups": [
			{
				"title_key": "ribbon.grp_pointer",
				"items": [
					{"action": "select",   "key": "symbol_lib.tool_select",   "icon": "select",   "toggle": true,  "mode": GPCanvas2D.GPMode.GP_SELECT},
					{"action": "connect",  "key": "symbol_lib.tool_connect",  "icon": "connect",  "toggle": true,  "mode": GPCanvas2D.GPMode.GP_CONNECT},
				]
			},
			{
				"title_key": "ribbon.grp_draw",
				"items": [
					{"action": "line",     "key": "canvas.tool_line",     "icon": "line",     "toggle": true, "mode": GPCanvas2D.GPMode.GP_DRAW_LINE},
					{"action": "circle",   "key": "canvas.tool_circle",   "icon": "circle",   "toggle": true, "mode": GPCanvas2D.GPMode.GP_DRAW_CIRCLE},
					{"action": "rect",     "key": "canvas.tool_rect",     "icon": "rect",     "toggle": true, "mode": GPCanvas2D.GPMode.GP_DRAW_RECT},
					{"action": "polyline", "key": "canvas.tool_polyline", "icon": "polyline", "toggle": true, "mode": GPCanvas2D.GPMode.GP_DRAW_POLYLINE},
				]
			},
			{
				"title_key": "ribbon.grp_line",
				"items": [
					{"action": "pipe",   "key": "symbol_lib.tool_pipe",   "icon": "pipe",   "toggle": true, "mode": GPCanvas2D.GPMode.GP_PIPE},
					{"action": "signal", "key": "symbol_lib.tool_signal", "icon": "signal", "toggle": true, "mode": GPCanvas2D.GPMode.GP_SIGNAL},
				]
			},
		]
	},
	{
		"title_key": "ribbon.tab_view",
		"groups": [
			{
				"title_key": "ribbon.grp_view",
				"items": [
					{"action": "view_zoom_in",  "key": "menu.view_zoom_in",  "icon": "zoom_in",  "toggle": false},
					{"action": "view_zoom_out", "key": "menu.view_zoom_out", "icon": "zoom_out", "toggle": false},
					{"action": "view_fit",      "key": "menu.view_fit",      "icon": "fit",      "toggle": false},
				]
			},
		]
	},
	{
		"title_key": "ribbon.tab_edit",
		"groups": [
			{
				"title_key": "ribbon.grp_edit",
				"items": [
					{"action": "edit_undo",    "key": "menu.edit_undo",    "icon": "undo",    "toggle": false},
					{"action": "edit_redo",    "key": "menu.edit_redo",    "icon": "redo",    "toggle": false},
					{"action": "edit_delete",  "key": "menu.edit_delete",  "icon": "delete",  "toggle": false},
					{"action": "tool_settings","key": "menu.tool_settings", "icon": "settings","toggle": false},
				]
			},
		]
	},
]

# TabContainer that hosts the command tabs.
# 承载命令标签的 TabContainer。
var gpTabs: TabContainer

# i18n keys for each tab title, parallel to tab order (for re-translation).
# 每个标签标题的 i18n 键，与标签顺序对应（用于重翻译）。
var gpTabTitleKeys: Array[String] = []

# Group caption labels, kept for locale / font refresh.
# 组标题标签，保留以便语言/字号刷新。
var gpGroupTitles: Array[Label] = []

# All ribbon buttons, kept for locale / font refresh.
# 全部 Ribbon 按钮，保留以便语言/字号刷新。
var gpButtons: Array[Button] = []

# Toggle buttons keyed by action, for mode-sync highlight.
# 以动作为键的开关按钮，用于模式同步高亮。
var gpModeBtns: Dictionary = {}

# action -> GPCanvas2D.GPMode map, for mode-sync highlight.
# 动作 → GPCanvas2D.GPMode 映射，用于模式同步高亮。
var gpActionToMode: Dictionary = {}


# Build the ribbon UI and connect localization / font signals.
# 构建 Ribbon UI 并连接本地化/字号信号。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP

	# Dark panel matching the app chrome (#21242E). The Ribbon is a FIXED-height
	# bar; the body below absorbs the rest of the vertical space.
	# 深色面板，贴合应用 chrome（#21242E）。Ribbon 为固定高度条，其下主体吸收剩余垂直空间。
	var gpBg: StyleBoxFlat = StyleBoxFlat.new()
	gpBg.bg_color = Color(0.13, 0.14, 0.18)
	gpBg.content_margin_left = 6.0
	gpBg.content_margin_right = 6.0
	gpBg.content_margin_top = 4.0
	gpBg.content_margin_bottom = 4.0
	add_theme_stylebox_override("panel", gpBg)
	custom_minimum_size = Vector2(0, 112)
	size_flags_vertical = 0

	_gpBuild()
	I18n.gpLocaleChanged.connect(_gpRefreshLocale)
	Settings.gpUIFontChanged.connect(_gpOnFontChanged)


# Construct the TabContainer, its tabs and grouped buttons.
# 构造 TabContainer、各标签及分组按钮。
func _gpBuild() -> void:
	var gpV: VBoxContainer = VBoxContainer.new()
	gpV.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(gpV)

	gpTabs = TabContainer.new()
	gpTabs.size_flags_vertical = SIZE_EXPAND_FILL
	gpV.add_child(gpTabs)

	for gpTabDef in GP_TABS:
		var gpTab: HBoxContainer = HBoxContainer.new()
		gpTab.size_flags_vertical = SIZE_EXPAND_FILL
		gpTab.add_theme_constant_override("separation", 14)
		gpTabs.add_child(gpTab)
		gpTabTitleKeys.append(gpTabDef["title_key"])
		gpTabs.set_tab_title(gpTabs.get_child_count() - 1, I18n.gpTr(gpTabDef["title_key"]))
		var gpGroups: Array = gpTabDef["groups"]
		for gpGi in gpGroups.size():
			gpTab.add_child(_gpBuildGroup(gpGroups[gpGi]))
			# Thin separator between groups (not after the last one).
			# 组间细分隔线（最后一组之后不加）。
			if gpGi < gpGroups.size() - 1:
				var gpSep: VSeparator = VSeparator.new()
				gpSep.custom_minimum_size.x = 1
				gpTab.add_child(gpSep)

	_gpApplyFont()


# Build one command group: a small caption above a row of buttons.
# 构造一个命令组：一行小标题位于按钮行之上。
func _gpBuildGroup(gpGroup: Dictionary) -> Control:
	var gpV: VBoxContainer = VBoxContainer.new()
	gpV.size_flags_horizontal = SIZE_SHRINK_CENTER
	gpV.add_theme_constant_override("separation", 3)

	var gpTitle: Label = Label.new()
	gpTitle.text = I18n.gpTr(gpGroup["title_key"])
	gpTitle.set_meta("gpKey", gpGroup["title_key"])
	gpTitle.add_theme_font_size_override("font_size", 11)
	gpTitle.add_theme_color_override("font_color", Color(0.70, 0.74, 0.82))
	gpTitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gpV.add_child(gpTitle)
	gpGroupTitles.append(gpTitle)

	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 6)
	gpRow.size_flags_vertical = SIZE_EXPAND_FILL
	for gpItem in gpGroup["items"]:
		gpRow.add_child(_gpBuildBtn(gpItem))
	gpV.add_child(gpRow)
	return gpV


# Build one icon+text ribbon button.
# 构造一枚「图标+文字」Ribbon 按钮。
func _gpBuildBtn(gpItem: Dictionary) -> Button:
	var gpBtn: Button = Button.new()
	gpBtn.text = I18n.gpTr(gpItem["key"])
	gpBtn.tooltip_text = I18n.gpTr(gpItem["key"])
	gpBtn.set_meta("gpKey", gpItem["key"])
	gpBtn.focus_mode = Control.FOCUS_NONE
	gpBtn.custom_minimum_size = Vector2(66, 60)
	# Ribbon look: icon centered on TOP of the text (icon_alignment=center,
	# vertical_icon_alignment=top) — matches the reference Godot-CAD layout.
	# Ribbon 观感：图标居中置于文字上方（icon_alignment=居中，vertical_icon_alignment=置顶），
	# 与参考项目 Godot-CAD 布局一致。
	gpBtn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gpBtn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	gpBtn.add_theme_constant_override("icon_max_width", 24)
	gpBtn.add_theme_constant_override("icon_max_height", 24)

	# Load the icon defensively: a missing/failed load just shows text (no crash).
	# 防御性加载图标：加载失败仅显示文字，不会崩溃。
	var gpIcon: Texture2D = load("res://assets/icons/%s.svg" % gpItem["icon"]) as Texture2D
	if gpIcon != null:
		gpBtn.icon = gpIcon

	if gpItem.get("toggle", false):
		gpBtn.toggle_mode = true
		gpModeBtns[gpItem["action"]] = gpBtn
		gpActionToMode[gpItem["action"]] = int(gpItem["mode"])

	gpBtn.pressed.connect(_gpOnBtnPressed.bind(gpItem["action"]))
	gpButtons.append(gpBtn)
	return gpBtn


# Forward a button press to the host via the gpActionTriggered signal.
# 将按钮按下经 gpActionTriggered 信号转发给宿主。
func _gpOnBtnPressed(gpAction: String) -> void:
	gpActionTriggered.emit(gpAction)


# Highlight the toggle button matching the active canvas mode.
# 高亮与当前画布模式匹配的开关按钮。
func gpSyncMode(gpMode: int) -> void:
	for gpAct in gpModeBtns.keys():
		var gpBtn: Button = gpModeBtns[gpAct]
		var gpM: int = gpActionToMode.get(gpAct, -1)
		gpBtn.button_pressed = (gpM >= 0 and gpMode == gpM)


# Re-translate every locale-dependent text after a language switch.
# 语言切换后重翻译所有依赖语言的文本。
func _gpRefreshLocale(_gpLocale: String) -> void:
	for gpI in gpTabTitleKeys.size():
		gpTabs.set_tab_title(gpI, I18n.gpTr(gpTabTitleKeys[gpI]))
	for gpL in gpGroupTitles:
		gpL.text = I18n.gpTr(gpL.get_meta("gpKey"))
	for gpB in gpButtons:
		var gpK: String = gpB.get_meta("gpKey")
		gpB.text = I18n.gpTr(gpK)
		gpB.tooltip_text = I18n.gpTr(gpK)


# Re-apply UI font size to captions and buttons when the user changes it.
# 用户改字号时把字号应用到标题与按钮。
func _gpOnFontChanged() -> void:
	_gpApplyFont()


# Push the current UI font size onto captions and buttons.
# 把当前界面字号作用到标题与按钮。
func _gpApplyFont() -> void:
	var gpSz: int = Settings.gpEffectiveFontSize()
	for gpB in gpButtons:
		gpB.add_theme_font_size_override("font_size", gpSz)
	# Group captions stay a touch smaller than the buttons for a ribbon feel.
	# 组标题比按钮略小，保留 Ribbon 观感。
	for gpL in gpGroupTitles:
		gpL.add_theme_font_size_override("font_size", maxi(11, gpSz - 2))
