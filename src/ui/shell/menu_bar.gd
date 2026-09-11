class_name GPPIDMenuBar
extends HBoxContainer

# Top CAD-style menu bar. The fixed structure is built here; every action emits
# gpActionTriggered(id) so the main window wires the real logic without coupling
# this widget. Labels are resolved through I18n and rebuilt when the locale changes.
# 顶部 CAD 风格菜单栏。固定结构在此构建；每个动作 emit gpActionTriggered(id)，
# 由主窗口接入真实逻辑。标签走 I18n，切换语言时自动重建。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Emitted when a menu action fires, carrying the action id (e.g. "file_save").
# 菜单动作触发时发出，携带动作 id（如 "file_save"）。
signal gpActionTriggered(gpId: String)

# Raised just before a popup opens, so the host can enable/disable items against live
# state (e.g. 撤销 is only enabled when the undo stack is non-empty). This keeps the bar
# ignorant of the canvas: it reports "a menu is opening", the host decides what is valid.
# 弹出菜单展开前发出，便于宿主依据实时状态启用 / 禁用菜单项（例如撤销栈非空才启用「撤销」）。
# 这样菜单栏无需认识画布：它只报告「某菜单要展开了」，由宿主判断什么可用。
signal gpMenuOpening(gpTitleKey: String)

# Every PopupMenu built by this bar, top-level AND submenu, so enabled state can be set
# by action id without knowing where the action lives.
# 本菜单栏构建的每个 PopupMenu（顶级**与**子菜单），便于按动作 id 设置启用状态，
# 而无需知道该动作位于何处。
var _gpPopups: Array[PopupMenu] = []

# Menu definitions: i18n title key -> array of [label_i18n_key, actionId].
# Use null entry for a separator.
# 菜单定义：i18n 标题键 -> [[标签 i18n 键, 动作 id], ...]。null 表示分隔线。
const GP_MENUS: Dictionary = {
	# A Dictionary entry means "submenu": {title: <i18n key>, items: [...]}. Import/export
	# are deliberately NOT flattened into the file menu: they produce files for OTHER
	# people, which is a different mental act from saving your own work.
	# Dictionary 条目表示「子菜单」：{title: <i18n 键>, items: [...]}。
	# 导入 / 导出刻意不摊平进文件菜单：它们产出给**别人**的文件，
	# 与保存自己的工作是不同的心智动作。
	"menu.file": [
		["menu.file_new", "file_new"],
		["menu.file_open", "file_open"],
		null,
		["menu.file_save", "file_save"],
		["menu.file_save_as", "file_save_as"],
		null,
		["menu.file_import", "file_import"],
		{"title": "menu.export", "items": [
			["menu.export_project", "export_project"],
			["menu.export_library", "export_library"],
			["menu.export_config", "export_config"],
			null,
			["menu.export_pdf", "export_pdf"],
			["menu.export_dxf", "export_dxf"],
		]},
		null,
		["menu.file_print", "file_print"],
		null,
		["menu.file_quit", "file_quit"],
	],
	"menu.edit": [
		["menu.edit_undo", "edit_undo"],
		["menu.edit_redo", "edit_redo"],
		null,
		["menu.edit_delete", "edit_delete"],
		["menu.edit_clear", "edit_clear"],
	],
	"menu.view": [
		["menu.view_fit", "view_fit"],
		["menu.view_zoom_in", "view_zoom_in"],
		["menu.view_zoom_out", "view_zoom_out"],
		["menu.view_grid", "view_grid"],
	],
	"menu.project": [
		["menu.project_tag_rules", "project_tag_rules"],
		["menu.project_export_list", "project_export_list"],
	],
	"menu.insert": [
		["menu.insert_frame", "insert_frame"],
		["menu.insert_frame_style", "insert_frame_style"],
	],
	"menu.format": [
		["menu.format_bg", "format_bg"],
	],
	"menu.tools": [
		["menu.tool_ai_unitop", "tool_ai_unitop"],
		["menu.tool_settings", "tool_settings"],
	],
	"menu.help": [
		["menu.help_about", "help_about"],
	],
}

# Action id -> keyboard accelerator: [keycode, with_shift].
# 动作 id -> 键盘加速键：[键码, 是否带 Shift]。
# Saving is the ONE action a drawing tool must never make the user hunt for in a menu, so it
# gets the conventional binding on every platform: Ctrl+S (Win/Linux) / Cmd+S (macOS), with
# the Shift variant for "save as".
# 保存是绘图工具里唯一绝不能让用户在菜单里翻找的动作，故在所有平台上都采用约定俗成的
# 绑定：Ctrl+S（Win/Linux）/ Cmd+S（macOS），带 Shift 的变体为「另存为」。
# See 持久化实现方案 §5.0 / ADR-7 (explicit save first).
# 见「持久化实现方案」§5.0 / ADR-7（显式保存优先）。
const GP_SHORTCUTS: Dictionary = {
	"file_save": [KEY_S, false],
	"file_save_as": [KEY_S, true],
	"file_open": [KEY_O, false],
}


# Build the menu bar and connect locale refresh.
# 构建菜单栏并连接语言刷新。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	# 左内边距 + 菜单间距，提升留白精致度（spacer 非 MenuButton，_gpRebuild 不清除）。
	add_theme_constant_override("separation", 6)
	var gpInset: Control = Control.new()
	gpInset.custom_minimum_size = Vector2(6.0, 0.0)
	gpInset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gpInset)
	_gpRebuild()
	I18n.gpLocaleChanged.connect(_gpRebuild)
	queue_redraw()


# Rebuild all menu buttons (used on startup and on locale change).
# 重建所有菜单按钮（启动和语言变化时使用）。
func _gpRebuild(gpLocale: String = "") -> void:
	# Remove old menu buttons.
	# 移除旧菜单按钮。
	for gpC in get_children():
		if gpC is MenuButton:
			remove_child(gpC)
			gpC.queue_free()
	# Rebuilding drops every popup, so the registry must be dropped with them (a stale
	# PopupMenu would be a freed object).
	# 重建会丢弃所有弹出菜单，故注册表必须一并丢弃（残留的 PopupMenu 已是已释放对象）。
	_gpPopups.clear()
	for gpTitleKey in GP_MENUS.keys():
		_gpAddMenu(gpTitleKey, GP_MENUS[gpTitleKey])


# Add one top-level menu with its popup items.
# 添加一个顶级菜单及其弹出项。
func _gpAddMenu(gpTitleKey: String, gpItems: Array) -> void:
	var gpBtn: MenuButton = MenuButton.new()
	gpBtn.text = I18n.gpTr(gpTitleKey)
	var gpPopup: PopupMenu = gpBtn.get_popup()
	_gpFillPopup(gpPopup, gpItems)
	# Announce the opening so the host can refresh enabled states first.
	# 宣告展开，使宿主先刷新启用状态。
	gpPopup.about_to_popup.connect(_gpOnOpening.bind(gpTitleKey))
	add_child(gpBtn)


# Fill one popup from gpItems, recursing into submenu entries and registering every popup
# (including nested ones) so action-based enabling keeps working.
# 用 gpItems 填充一个弹出菜单，递归进入子菜单条目，并登记每个弹出菜单
# （含嵌套的），使基于动作的启用控制继续有效。
func _gpFillPopup(gpPopup: PopupMenu, gpItems: Array) -> void:
	var gpIdx: int = 0
	for gpEntry in gpItems:
		if gpEntry == null:
			gpPopup.add_separator()
			gpIdx += 1
			continue
		# A Dictionary entry opens a submenu. Godot requires the submenu to be a CHILD of
		# the parent popup and referenced by its node name.
		# Dictionary 条目展开一个子菜单。Godot 要求子菜单是父弹出菜单的**子节点**，
		# 并以节点名引用。
		if gpEntry is Dictionary:
			var gpSpec: Dictionary = gpEntry as Dictionary
			var gpSub: PopupMenu = PopupMenu.new()
			gpSub.name = I18n.gpTr(str(gpSpec.get("title", "")))
			_gpFillPopup(gpSub, gpSpec.get("items", []) as Array)
			gpPopup.add_child(gpSub)
			gpPopup.add_submenu_item(gpSub.name, gpSub.name)
			gpIdx += 1
			continue
		var gpEntryArr: Array = gpEntry as Array
		var gpLabelKey: String = gpEntryArr[0]
		var gpAction: String = gpEntryArr[1]
		gpPopup.add_item(I18n.gpTr(gpLabelKey), gpIdx)
		gpPopup.set_item_metadata(gpIdx, gpAction)
		# Accelerator: registered as a GLOBAL shortcut so it fires even while the popup is
		# closed, and so Godot renders it at the right edge of the menu item — a shortcut the
		# user cannot see is a shortcut the user will not find.
		# 加速键：注册为**全局**快捷方式，使弹出菜单关闭时也能触发，并让 Godot 把它渲染在
		# 菜单项右端 —— 用户看不见的快捷键，等于用户找不到的快捷键。
		# _unhandled_input was deliberately NOT used: an input field (the inspector's property
		# form) consumes key events first, so Ctrl+S typed while editing a property would be
		# swallowed — exactly the moment a user is most likely to save.
		# 刻意未用 _unhandled_input：输入框（属性面板表单）会先消费按键事件，
		# 故编辑属性时按下的 Ctrl+S 会被吞掉 —— 而那恰恰是用户最可能想保存的时刻。
		if GP_SHORTCUTS.has(gpAction):
			var gpShortcutSpec: Array = GP_SHORTCUTS[gpAction]
			gpPopup.set_item_shortcut(gpIdx,
				_gpMakeShortcut(int(gpShortcutSpec[0]), bool(gpShortcutSpec[1])), true)
		gpIdx += 1
	gpPopup.id_pressed.connect(_gpOnPressed.bind(gpPopup))
	_gpPopups.append(gpPopup)


# Forward a popup item press to the action signal.
# 将弹出项点击转发为动作信号。
func _gpOnPressed(gpIndex: int, gpPopup: PopupMenu) -> void:
	var gpAction: String = gpPopup.get_item_metadata(gpIndex)
	gpActionTriggered.emit(gpAction)


# Forward a popup opening to the host.
# 把菜单展开转发给宿主。
func _gpOnOpening(gpTitleKey: String) -> void:
	gpMenuOpening.emit(gpTitleKey)


# Enable or disable every item carrying the given action id. Items default to enabled,
# so the host only has to speak about the ones that can become unavailable.
# 启用或禁用所有携带指定动作 id 的菜单项。菜单项默认可用，故宿主只需关心那些会变为
# 不可用的项。
func gpSetActionEnabled(gpAction: String, gpEnabled: bool) -> void:
	for gpPopup in _gpPopups:
		if not is_instance_valid(gpPopup):
			continue
		for gpI in range(gpPopup.item_count):
			# Separators carry null metadata and never match an action id.
			# 分隔线的 metadata 为 null，永不匹配动作 id。
			if gpPopup.get_item_metadata(gpI) != gpAction:
				continue
			gpPopup.set_item_disabled(gpI, not gpEnabled)


# Build a platform-correct accelerator for one action.
# 为一个动作构造符合平台习惯的加速键。
# macOS uses Cmd as the primary modifier; Windows/Linux use Ctrl. Both are registered on macOS
# so a switcher's muscle memory still works, with Cmd first so the menu label renders as ⌘S.
# macOS 以 Cmd 为主修饰键；Windows/Linux 用 Ctrl。macOS 上两者都注册，
# 使跨平台用户的肌肉记忆仍然有效，且 Cmd 在前以便菜单标签渲染为 ⌘S。
static func _gpMakeShortcut(gpKeycode: int, gpShift: bool) -> Shortcut:
	var gpSc: Shortcut = Shortcut.new()
	var gpEvents: Array[InputEvent] = []
	if OS.get_name() == "macOS":
		gpEvents.append(_gpKeyEvent(gpKeycode, gpShift, false))
		gpEvents.append(_gpKeyEvent(gpKeycode, gpShift, true))
	else:
		gpEvents.append(_gpKeyEvent(gpKeycode, gpShift, true))
	gpSc.events = gpEvents
	return gpSc


# One key event for an accelerator.
# 加速键用的单个按键事件。
# [param gpCtrl] true -> Ctrl (Windows/Linux); false -> Cmd / Meta (macOS).
# [param gpCtrl] 为真 -> Ctrl（Windows/Linux）；为假 -> Cmd / Meta（macOS）。
static func _gpKeyEvent(gpKeycode: int, gpShift: bool, gpCtrl: bool) -> InputEventKey:
	var gpE: InputEventKey = InputEventKey.new()
	gpE.keycode = gpKeycode
	gpE.ctrl_pressed = gpCtrl
	gpE.meta_pressed = not gpCtrl
	gpE.shift_pressed = gpShift
	return gpE


# Every accelerator currently registered, as "action -> Shortcut", for tests and for a future
# shortcut-settings panel.
# 当前注册的全部加速键，形如「动作 -> Shortcut」，供测试与将来的快捷键设置面板使用。
static func gpShortcutSpecs() -> Dictionary:
	return GP_SHORTCUTS

# Paint the chrome background + bottom border (separates the menu bar from the Ribbon).
# 自绘 chrome 背景 + 底部边界线（与下方 Ribbon 分隔）。
func _draw() -> void:
	GPChromeStyle.gpDraw(self, GPChromeStyle.GP_CHROME_BG, GPChromeStyle.SIDE_BOTTOM)
