class_name GPSymbolPaletteItem
extends Control

# One clickable entry in the left symbol library.
# 左侧图元库中的一个可点击条目。
# It shows a small vector thumbnail of the symbol and its localized name below.
# 显示图元的矢量缩略图，并在下方显示本地化的名称。

# Emitted when the user clicks this item.
# 用户点击本条目时发出。
signal gpPicked(type_id: String)

# Emitted when the user requests deletion of this symbol via the context menu. The
# actual deletion (and any cascade removal of canvas instances) is owned by the main
# window, which holds the graphs; this item only forwards the user's intent.
# 用户经右键菜单请求删除本图元时发出。真正的删除（及画布实例的级联清理）由持有图的主窗口
# 负责，本条目只转发用户意图。
signal gpDeleteRequested(gpId: String)

# Context-menu action ids (only one today, but keep the enum form for future actions).
# 右键菜单动作 id（目前仅一项，但保留枚举形式以便扩展）。
const GP_CTX_DELETE: int = 0

# Symbol definition rendered by this item.
# 本条目所渲染的图元定义。
var gpDef: GPSymbolDef = null

# Size of the thumbnail area in screen pixels.
# 缩略图区域的屏幕像素尺寸。
var gpThumbnailSize: Vector2 = Vector2(24.0, 24.0)

# Font size used for the localized symbol name below the thumbnail.
# 缩略图下方本地化符号名的字号。
var gpLabelFontSize: int = 11

# Whether the mouse cursor is currently over this item.
# 鼠标光标是否当前位于本条目上方。
var _gpHover: bool = false


# Initialize input handling and minimum size.
# 初始化输入处理与最小尺寸。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_gpCalcSizes()
	# Minimum WIDTH is 0: the palette grid stretches each cell to fill the viewport
	# via fit_child_in_rect, so the grid's combined minimum width stays small and the
	# left dock can shrink to its floor. The drawn cell width is driven by the grid
	# layout, not by this minimum. Height keeps a sensible floor for the thumbnail.
	# 最小宽度为 0：图元网格通过 fit_child_in_rect 把每格拉伸到视口宽，使网格合并最小
	# 宽保持很小、左停靠栏能收缩到下限。绘制用格宽由网格布局决定，而非此最小值。
	# 高度保留缩略图所需的合理下限。
	custom_minimum_size = Vector2(0.0, gpThumbnailSize.y + gpLabelFontSize + 12.0)
	mouse_entered.connect(_gpOnMouseEntered)
	mouse_exited.connect(_gpOnMouseExited)
	Settings.gpSymbolStyleChanged.connect(_gpOnSymbolStyleChanged)


# Recalculate thumbnail and label sizes from the current symbol font size so the
# toolbar items scale together with the canvas symbol text.
# 根据当前图元字号重新计算缩略图与标签尺寸，使工具栏条目随画布图元文字一起缩放。
func _gpCalcSizes() -> void:
	var gpBase: float = float(Settings.gpSymbolFontSize) + 8.0
	gpThumbnailSize = Vector2(gpBase, gpBase)
	gpLabelFontSize = Settings.gpSymbolFontSize


# React to symbol font / size changes: update minimum size and redraw.
# 响应图元字体/字号变化：更新最小尺寸并重绘。
func _gpOnSymbolStyleChanged() -> void:
	_gpCalcSizes()
	custom_minimum_size = Vector2(0.0, gpThumbnailSize.y + gpLabelFontSize + 12.0)
	update_minimum_size()
	queue_redraw()


# Track hover state and redraw when the mouse enters.
# 跟踪悬停状态，并在鼠标进入时重绘。
func _gpOnMouseEntered() -> void:
	_gpHover = true
	queue_redraw()


# Track hover state and redraw when the mouse leaves.
# 跟踪悬停状态，并在鼠标离开时重绘。
func _gpOnMouseExited() -> void:
	_gpHover = false
	queue_redraw()


# Handle mouse clicks on the whole item.
# 处理整个条目上的鼠标点击。
func _gui_input(gpEvent: InputEvent) -> void:
	if gpEvent is InputEventMouseButton:
		var gpMouseEvent: InputEventMouseButton = gpEvent as InputEventMouseButton
		# Right-click opens the symbol-library context menu (delete, etc.).
		# 右键打开图元库上下文菜单（删除等）。
		if gpMouseEvent.button_index == MOUSE_BUTTON_RIGHT and gpMouseEvent.pressed:
			accept_event()
			_gpShowContextMenu()
			return
		if gpMouseEvent.button_index == MOUSE_BUTTON_LEFT and gpMouseEvent.pressed:
			accept_event()
			var gpTypeId: String = gpDef.gpId if gpDef != null else ""
			gpPicked.emit(gpTypeId)
			queue_redraw()


# Build and pop up the context menu at the cursor. Only user-authored symbols can be
# deleted; built-in ISO symbols are read-only (decision D3) and the item is disabled.
# 在光标处构建并弹出上下文菜单。仅用户自建图元可删；内置 ISO 图元只读（决策 D3），条目禁用。
func _gpShowContextMenu() -> void:
	if gpDef == null:
		return
	var gpMenu: PopupMenu = PopupMenu.new()
	gpMenu.add_item(I18n.gpTr("symbol_lib.ctx_delete"), GP_CTX_DELETE)
	# Disable removal for built-in symbols so users cannot delete the shipped set.
	# 内置图元禁用删除，避免误删随附图元集。
	gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DELETE), gpDef.gpBuiltin)
	gpMenu.id_pressed.connect(_gpOnContext)
	add_child(gpMenu)
	# Position via the shared popup helper (global-screen formula, single source of truth).
	# 经统一弹窗助手定位（全局屏幕坐标公式，单一事实来源）。
	GPPopupHelper.gpPopupAtMouse(gpMenu, self)
	# Free the menu after it closes; a leaked PopupMenu keeps this item (and its grid) alive.
	# 关闭后释放菜单；泄漏的 PopupMenu 会让本条目（及所在网格）无法释放。
	gpMenu.popup_hide.connect(gpMenu.queue_free)


# Dispatch a context-menu action.
# 分发右键菜单动作。
func _gpOnContext(gpId: int) -> void:
	if gpDef == null:
		return
	if gpId == GP_CTX_DELETE:
		# Forward the delete intent to the main window, which owns the graphs and can
		# cascade-remove any placed instances before dropping the symbol. The menu's
		# "Delete" item is already disabled for built-in symbols, so gpDef here is user-owned.
		# 把删除意图转发给主窗口：它持有图，可在移除图元前级联清理画布实例。内置图元的
		# 「删除」项已被禁用，故此处 gpDef 必为用户自建。
		gpDeleteRequested.emit(gpDef.gpId)


# Draw the background, the symbol thumbnail and the label.
# 绘制背景、图元缩略图和标签。
func _draw() -> void:
	# Background color changes on hover to give visual feedback.
	# 悬停时背景色变化，提供视觉反馈。
	var gpBg: Color = Color(0.20, 0.23, 0.28) if _gpHover else Color(0.13, 0.15, 0.18)
	draw_rect(Rect2(Vector2.ZERO, size), gpBg, true)

	if gpDef == null:
		return

	# Thumbnail rectangle, centered horizontally with a small top margin.
	# 缩略图矩形，水平居中并留顶部边距。
	var gpThumbRect: Rect2 = Rect2(
		Vector2((size.x - gpThumbnailSize.x) / 2.0, 4.0),
		gpThumbnailSize
	)

	# Use the same category colors as the canvas so the palette and canvas match.
	# 使用与画布相同的类目颜色，使图元库与画布保持一致。
	var gpFill: Color = GPSymbolPainter.gpCategoryColor(gpDef.gpCategory)
	var gpStroke: Color = gpFill.lightened(0.25)
	var gpBorder: float = 1.5

	# Fallback rectangle for symbols that do not yet have a vector shape.
	# 对尚无矢量形状的图元，用矩形兜底。
	if gpDef.gpShapes.is_empty():
		draw_rect(gpThumbRect, gpFill, true)
		draw_rect(gpThumbRect, gpStroke, false, gpBorder)
	else:
		GPSymbolPainter.gpDrawShape(self, gpDef.gpShapeSpec(), gpThumbRect, gpFill, gpStroke, gpBorder)

	# Draw the localized display name directly below the thumbnail, centered across the cell.
	# 在缩略图正下方、跨整个单元格居中绘制本地化的显示名。
	var gpFont: Font = Settings.gpSymbolFont if Settings.gpSymbolFont != null else ThemeDB.fallback_font
	var gpName: String = I18n.gpTr(gpDef.gpDisplayName)
	var gpTextTop: float = gpThumbRect.position.y + gpThumbRect.size.y + 4.0
	draw_string(
		gpFont,
		Vector2(0.0, gpTextTop),
		gpName,
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x,
		gpLabelFontSize,
		Color(0.9, 0.9, 0.9)
	)
