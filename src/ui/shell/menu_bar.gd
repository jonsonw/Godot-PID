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

# Title i18n key -> PopupMenu, so enabled state can be set by action id across all menus.
# 标题 i18n 键 -> PopupMenu，便于按动作 id 跨菜单设置启用状态。
var _gpPopups: Dictionary = {}

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
	# Rebuilding drops every popup, so the registry must be dropped with them (a stale
	# PopupMenu would be a freed object).
	# 重建会丢弃所有弹出菜单，故注册表必须一并丢弃（残留的 PopupMenu 已是已释放对象）。
	_gpPopups = {}
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
	# Announce the opening so the host can refresh enabled states first.
	# 宣告展开，使宿主先刷新启用状态。
	gpPopup.about_to_popup.connect(_gpOnOpening.bind(gpTitleKey))
	_gpPopups[gpTitleKey] = gpPopup
	add_child(gpBtn)


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
	for gpTitleKey in _gpPopups.keys():
		var gpPopup: PopupMenu = _gpPopups[gpTitleKey]
		for gpI in range(gpPopup.item_count):
			# Separators carry null metadata and never match an action id.
			# 分隔线的 metadata 为 null，永不匹配动作 id。
			if gpPopup.get_item_metadata(gpI) != gpAction:
				continue
			gpPopup.set_item_disabled(gpI, not gpEnabled)
