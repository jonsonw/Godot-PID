class_name GPSymbolPaletteItem
extends Control

# One clickable entry in the left symbol library.
# 左侧图元库中的一个可点击条目。
# It shows a small vector thumbnail of the symbol and its localized name below.
# 显示图元的矢量缩略图，并在下方显示本地化的名称。

# Emitted when the user clicks this item.
# 用户点击本条目时发出。
signal gpPicked(type_id: String)

# Symbol definition rendered by this item.
# 本条目所渲染的图元定义。
var gpDef: GPSymbolDef = null

# Size of the thumbnail area in screen pixels.
# 缩略图区域的屏幕像素尺寸。
var gpThumbnailSize: Vector2 = Vector2(24.0, 24.0)

# Whether the mouse cursor is currently over this item.
# 鼠标光标是否当前位于本条目上方。
var _gpHover: bool = false


# Initialize input handling and minimum size.
# 初始化输入处理与最小尺寸。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	# Fixed cell width so several thumbnails sit side by side in the palette flow.
	# 固定单元格宽度，使多个缩略图在图元库中并排成多列。
	custom_minimum_size = Vector2(60.0, gpThumbnailSize.y + 22.0)
	mouse_entered.connect(_gpOnMouseEntered)
	mouse_exited.connect(_gpOnMouseExited)


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
		if gpMouseEvent.button_index == MOUSE_BUTTON_LEFT and gpMouseEvent.pressed:
			accept_event()
			var gpTypeId: String = gpDef.gpId if gpDef != null else ""
			gpPicked.emit(gpTypeId)
			queue_redraw()


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
	if gpDef.gpShape.is_empty():
		draw_rect(gpThumbRect, gpFill, true)
		draw_rect(gpThumbRect, gpStroke, false, gpBorder)
	else:
		GPSymbolPainter.gpDrawShape(self, gpDef.gpShape, gpThumbRect, gpFill, gpStroke, gpBorder)

	# Draw the localized display name directly below the thumbnail, centered across the cell.
	# 在缩略图正下方、跨整个单元格居中绘制本地化的显示名。
	var gpFont: Font = Settings.gpSymbolFont if Settings.gpSymbolFont != null else ThemeDB.fallback_font
	var gpName: String = I18n.gpTr(gpDef.gpDisplayName)
	var gpLabelFontSz: int = 11
	var gpTextTop: float = gpThumbRect.position.y + gpThumbRect.size.y + 4.0
	draw_string(
		gpFont,
		Vector2(0.0, gpTextTop),
		gpName,
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x,
		gpLabelFontSz,
		Color(0.9, 0.9, 0.9)
	)
