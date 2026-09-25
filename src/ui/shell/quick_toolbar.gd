class_name GPPIDQuickToolbar
extends HBoxContainer

# Standalone top command toolbar (2026-09-25 AutoCAD reference layout): sits in its
# OWN row directly BELOW the menu bar — deliberately separated from it — and is
# CENTRED horizontally. It carries, in one icon strip:
#   新建 / 打开 / 保存 | 撤销 / 重做 / 删除 / 设置 | 打印 / 导入 / 导出▾ | 放大 / 缩小 / 适应
# The 撤销 / 重做 / 删除 / 设置 four come from the left palette's former EDIT block
# (moved here wholesale per the 2026-09-25 layout request — the palette no longer
# keeps them). Draw tools stay in the palette, like AutoCAD's panel-bound tools.
# 独立的顶部命令工具栏（2026-09-25 AutoCAD 参照布局）：独占菜单栏**正下方**的一行
# ——刻意与菜单栏分离——并**水平居中**。一条图标带承载：
#   新建 / 打开 / 保存 | 撤销 / 重做 / 删除 / 设置 | 打印 / 导入 / 导出▾ | 放大 / 缩小 / 适应
# 其中撤销 / 重做 / 删除 / 设置 四键来自左栏原「编辑」块（按要求整体迁入，
# 左栏不再保留）。绘图工具仍留在图元库，同 AutoCAD 的面板绑定工具。
# Actions reuse the menu action ids, so everything travels through the SAME
# gpOnMenu pipeline and needs no new routing.
# 动作复用菜单动作 id，故全部走同一条 gpOnMenu 管线、无需新路由。
# null entry = a small gap between clusters.
# null 条目 = 组间空隙。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Emitted when a toolbar action fires, carrying the menu action id (e.g. "file_save").
# 工具栏动作触发时发出，携带菜单动作 id（如 "file_save"）。
signal gpActionTriggered(gpId: String)

# Icon strip spec: menu action id + tooltip i18n key + icon file stem.
# 图标带定义：菜单动作 id + 提示语 i18n 键 + 图标文件名。
const GP_ITEMS: Array = [
	{"action": "file_new", "key": "menu.file_new", "icon": "file_new"},
	{"action": "file_open", "key": "menu.file_open", "icon": "file_open"},
	{"action": "file_save", "key": "menu.file_save", "icon": "file_save"},
	null,
	{"action": "edit_undo", "key": "menu.edit_undo", "icon": "undo"},
	{"action": "edit_redo", "key": "menu.edit_redo", "icon": "redo"},
	{"action": "edit_delete", "key": "menu.edit_delete", "icon": "delete"},
	{"action": "tool_settings", "key": "menu.tool_settings", "icon": "settings"},
	null,
	{"action": "file_print", "key": "menu.file_print", "icon": "file_print"},
	{"action": "file_import", "key": "menu.file_import", "icon": "file_import"},
	{"action": "file_export", "key": "menu.export", "icon": "file_export", "menu": [
		["menu.export_project", "export_project"],
		["menu.export_library", "export_library"],
		["menu.export_config", "export_config"],
		null,
		["menu.export_pdf", "export_pdf"],
		["menu.export_dxf", "export_dxf"],
	]},
	null,
	{"action": "view_zoom_in", "key": "menu.view_zoom_in", "icon": "zoom_in"},
	{"action": "view_zoom_out", "key": "menu.view_zoom_out", "icon": "zoom_out"},
	{"action": "view_fit", "key": "menu.view_fit", "icon": "fit"},
]

# Buttons keyed by action, so enable/disable and tooltip refresh find them.
# 以动作为键的按钮，便于启用/禁用与提示语刷新。
var _gpBtns: Dictionary = {}

# The export submenu popup (owned by the export button).
# 导出子菜单弹出层（归导出按钮所有）。
var _gpExportPopup: PopupMenu = null


# Build the icon strip once. The row's BoxContainer alignment CENTRES the strip
# horizontally regardless of window width (the requirement: the toolbar hangs
# centred below the menu bar).
# 一次性构建图标带。行容器 alignment=居中，使图标带在任意窗口宽度下都水平居中
#（即需求：工具栏悬挂于菜单栏下方居中）。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 2)
	for gpEntry in GP_ITEMS:
		if gpEntry == null:
			var gpGap: Control = Control.new()
			gpGap.custom_minimum_size = Vector2(10.0, 0.0)
			gpGap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(gpGap)
			continue
		add_child(_gpBuildBtn(gpEntry as Dictionary))
	I18n.gpLocaleChanged.connect(_gpRefreshTooltips)
	_gpRefreshTooltips(I18n.gpLocale)
	queue_redraw()


# Build one icon-only flat button (tooltip = localized name, AutoCAD style).
# 构建一枚纯图标扁平按钮（提示 = 本地化名称，AutoCAD 风格）。
func _gpBuildBtn(gpSpec: Dictionary) -> Button:
	var gpBtn: Button = Button.new()
	gpBtn.flat = true
	gpBtn.focus_mode = Control.FOCUS_NONE
	gpBtn.tooltip_text = I18n.gpTr(str(gpSpec["key"]))
	gpBtn.set_meta("gpKey", str(gpSpec["key"]))
	var gpIcon: Texture2D = load("res://assets/icons/%s.svg" % str(gpSpec["icon"])) as Texture2D
	if gpIcon != null:
		gpBtn.icon = gpIcon
	gpBtn.add_theme_constant_override("icon_max_width", 18)
	gpBtn.custom_minimum_size = Vector2(28.0, 24.0)
	# Hover feedback on the chrome: a slightly lighter flat plate, AutoCAD toolbar feel.
	# chrome 上的悬停反馈：略亮的扁平色板，AutoCAD 工具栏观感。
	var gpHover: StyleBoxFlat = StyleBoxFlat.new()
	gpHover.bg_color = GPChromeStyle.GP_SPLIT_HI
	gpHover.set_content_margin_all(2.0)
	gpHover.set_corner_radius_all(3)
	gpBtn.add_theme_stylebox_override("hover", gpHover)
	var gpPressed: StyleBoxFlat = gpHover.duplicate() as StyleBoxFlat
	gpPressed.bg_color = GPChromeStyle.GP_BORDER
	gpBtn.add_theme_stylebox_override("pressed", gpPressed)
	if gpSpec.has("menu"):
		gpBtn.pressed.connect(_gpOpenExportMenu.bind(gpBtn))
	else:
		gpBtn.pressed.connect(_gpOnPressed.bind(str(gpSpec["action"])))
	_gpBtns[str(gpSpec["action"])] = gpBtn
	return gpBtn


# Mirror menu-item enabled state (undo/redo gray out with an empty stack).
# 镜像菜单项可用状态（撤销/重做随空栈置灰）。
func gpSetActionEnabled(gpAction: String, gpEnabled: bool) -> void:
	if _gpBtns.has(gpAction):
		var gpBtn: Button = _gpBtns[gpAction] as Button
		if gpBtn != null:
			gpBtn.disabled = not gpEnabled


# Open the export submenu under the export button.
# 在「导出」按钮下方弹出导出子菜单。
func _gpOpenExportMenu(gpBtn: Button) -> void:
	if _gpExportPopup == null:
		_gpExportPopup = PopupMenu.new()
		_gpFillPopup(_gpExportPopup, [
			["menu.export_project", "export_project"],
			["menu.export_library", "export_library"],
			["menu.export_config", "export_config"],
			null,
			["menu.export_pdf", "export_pdf"],
			["menu.export_dxf", "export_dxf"],
		])
		add_child(_gpExportPopup)
	GPPopupHelper.gpPopupAtMouse(_gpExportPopup, gpBtn)


# Fill one popup from [labelKey, actionId] rows; null = separator. Item presses are
# forwarded through THIS toolbar's gpActionTriggered (same pipeline as the menus).
# 用 [标签键, 动作 id] 行填充弹出菜单；null = 分隔线。条目点击经**本工具栏**的
# gpActionTriggered 转发（与菜单同一条管线）。
func _gpFillPopup(gpPopup: PopupMenu, gpItems: Array) -> void:
	var gpIdx: int = 0
	for gpEntry in gpItems:
		if gpEntry == null:
			gpPopup.add_separator()
			gpIdx += 1
			continue
		var gpRow: Array = gpEntry as Array
		gpPopup.add_item(I18n.gpTr(str(gpRow[0])), gpIdx)
		gpPopup.set_item_metadata(gpIdx, str(gpRow[1]))
		gpIdx += 1
	gpPopup.id_pressed.connect(_gpOnPopupId.bind(gpPopup))


# A popup item was pressed: read its metadata (the action id) and forward it.
# 弹出菜单条目被点击：读取其 metadata（动作 id）并转发。
func _gpOnPopupId(gpIndex: int, gpPopup: PopupMenu) -> void:
	gpActionTriggered.emit(str(gpPopup.get_item_metadata(gpIndex)))


# Forward a button press through the SAME action pipeline as the menus.
# 按钮按下：经与菜单**相同**的动作管线转发。
func _gpOnPressed(gpAction: String) -> void:
	gpActionTriggered.emit(gpAction)


# Re-translate the tooltips after a locale change.
# 语言切换后重翻译提示语。
func _gpRefreshTooltips(_gpLocale: String) -> void:
	for gpAct in _gpBtns.keys():
		var gpBtn: Button = _gpBtns[gpAct] as Button
		if gpBtn != null and gpBtn.has_meta("gpKey"):
			gpBtn.tooltip_text = I18n.gpTr(str(gpBtn.get_meta("gpKey")))


# Paint the chrome background + a dark bottom groove (separates the toolbar from
# the body below, matching the reference's dark seam under the command rows).
# 自绘 chrome 背景 + 底部深色凹缝（与下方主体分隔，对应参考图命令行下的深色缝）。
func _draw() -> void:
	GPChromeStyle.gpDraw(self, GPChromeStyle.GP_RIBBON_BG, GPChromeStyle.SIDE_BOTTOM)
