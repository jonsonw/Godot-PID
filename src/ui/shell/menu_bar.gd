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

# Menu definitions: i18n title key -> array of [label_i18n_key, actionId].
# Use null entry for a separator.
# 菜单定义：i18n 标题键 -> [[标签 i18n 键, 动作 id], ...]。null 表示分隔线。
const GP_MENUS: Dictionary = {
	"menu.file": [
		["menu.file_new", "file_new"],
		["menu.file_open", "file_open"],
		["menu.file_save", "file_save"],
		["menu.file_save_as", "file_save_as"],
		["menu.file_print", "file_print"],
		null,
		["menu.export_pdf", "export_pdf"],
		["menu.export_dxf", "export_dxf"],
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


# Build the menu bar and connect locale refresh.
# 构建菜单栏并连接语言刷新。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_gpRebuild()
	I18n.gpLocaleChanged.connect(_gpRebuild)


# Rebuild all menu buttons (used on startup and on locale change).
# 重建所有菜单按钮（启动和语言变化时使用）。
func _gpRebuild(gpLocale: String = "") -> void:
	# Remove old menu buttons.
	# 移除旧菜单按钮。
	for gpC in get_children():
		remove_child(gpC)
		gpC.queue_free()
	for gpTitleKey in GP_MENUS.keys():
		_gpAddMenu(gpTitleKey, GP_MENUS[gpTitleKey])


# Add one top-level menu with its popup items.
# 添加一个顶级菜单及其弹出项。
func _gpAddMenu(gpTitleKey: String, gpItems: Array) -> void:
	var gpBtn: MenuButton = MenuButton.new()
	gpBtn.text = I18n.gpTr(gpTitleKey)
	var gpPopup: PopupMenu = gpBtn.get_popup()
	var gpIdx: int = 0
	for gpEntry in gpItems:
		if gpEntry == null:
			gpPopup.add_separator()
			gpIdx += 1
			continue
		var gpLabelKey: String = gpEntry[0]
		var gpAction: String = gpEntry[1]
		gpPopup.add_item(I18n.gpTr(gpLabelKey), gpIdx)
		gpPopup.set_item_metadata(gpIdx, gpAction)
		gpIdx += 1
	gpPopup.id_pressed.connect(_gpOnPressed.bind(gpPopup))
	add_child(gpBtn)


# Forward a popup item press to the action signal.
# 将弹出项点击转发为动作信号。
func _gpOnPressed(gpIndex: int, gpPopup: PopupMenu) -> void:
	var gpAction: String = gpPopup.get_item_metadata(gpIndex)
	gpActionTriggered.emit(gpAction)
