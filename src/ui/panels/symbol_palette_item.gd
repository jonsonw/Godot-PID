class_name GPSymbolPaletteItem
extends Control

# One clickable entry in the left symbol library.
# 左侧图元库中的一个可点击条目。
# AutoCAD-style (2026-09-25 reference): the item shows ONLY the vector thumbnail —
# no text label. The localized name appears on HOVER (tooltip), following the
# project language. This halves the cell height and lets 4-5 tiles fit per row.
# AutoCAD 风格（2026-09-25 参照图）：条目只显示矢量缩略图 —— 无文字标签。本地化名称在
# 悬停时以提示显示，随项目语言。单元格高度因此减半，每行可排 4–5 格。

# Emitted when the user clicks this item.
# 用户点击本条目时发出。
signal gpPicked(type_id: String)

# Emitted when the user requests deletion of this symbol via the context menu. The
# actual deletion (and any cascade removal of canvas instances) is owned by the main
# window, which holds the graphs; this item only forwards the user's intent.
# 用户经右键菜单请求删除本图元时发出。真正的删除（及画布实例的级联清理）由主窗口
# 负责，本条目只转发用户意图。
signal gpDeleteRequested(gpId: String)

# Context-menu action ids (only one today, but keep the enum form for future actions).
# 右键菜单动作 id（目前仅一项，但保留枚举形式以便扩展）。
const GP_CTX_DELETE: int = 0

# Symbol definition rendered by this item.
# 本条目所渲染的图元定义。
var gpDef: GPSymbolDef = null

# Palette cell metrics — defined ONCE here: this item draws with them and GPSymbolGrid derives its
# row height from them, so the two can never disagree. They used to disagree (the grid sized rows
# from gpFontSize while the item reserved space from gpSymbolFontSize), and that mismatch is what
# let one category's thumbnails spill over the next category's header.
# 图元库单元格度量 —— **只在此处定义一次**：本条目据此绘制，GPSymbolGrid 据此推导行高，故二者
# 永不会分歧。此前二者确实分歧（网格按 gpFontSize 排行高，条目却按 gpSymbolFontSize 预留空间），
# 正是这一错位让某个类目的缩略图溢出到下一个类目的标题上。
# The thumbnail is a fixed pixel size on purpose. It used to be gpSymbolFontSize + 8, but that
# value is a MILLIMETRE sheet text height since v0.1 (plan Phase 0) — deriving a pixel thumbnail
# from it produced an 11 px box beside a 24 px label, i.e. the reported "text too large".
# 缩略图刻意取固定像素尺寸。此前为 gpSymbolFontSize + 8，但该值自 v0.1 起是**毫米**图面字高
#（计划 Phase 0）—— 用它推导像素缩略图会得到「11px 的框配 24px 的字」，即用户报告的「文字过大」。
# Since the label was removed the cell height no longer depends on any font size at all:
# GP_CELL_PAD splits evenly above/below the thumbnail.
# 自标签移除后，单元格高度不再依赖任何字号：GP_CELL_PAD 均匀分在缩略图上下。
# 2026-09-25: the thumbnail was shrunk by 1/4 (28 -> 21 px) per user request; tiles stay
# square so the thumbnail and the draw-block icons share ONE icon size.
# 2026-09-25：缩略图按需求缩小 1/4（28 -> 21 px）；图块保持正方形，与「绘制」块图标同尺寸。
const GP_THUMB_PX: float = 21.0
const GP_CELL_PAD: float = 12.0

# Size of the thumbnail area in screen pixels.
# 缩略图区域的屏幕像素尺寸。
var gpThumbnailSize: Vector2 = Vector2(GP_THUMB_PX, GP_THUMB_PX)

# Whether the mouse cursor is currently over this item.
# 鼠标光标是否当前位于本条目上方。
var _gpHover: bool = false


# Height one palette cell needs: thumbnail + vertical padding. The grid's row height MUST come from
# here so that layout and drawing can never disagree. The UI-font parameter is kept so existing
# call sites (and the regression tests) stay valid; the height is intentionally font-independent
# now that the label is gone.
# 一个图元库单元格所需的高度：缩略图 + 上下边距。网格的行高**必须**取自此函数，
# 使布局与绘制永不分歧。界面字号参数仅为兼容既有调用点（及回归测试）而保留；
# 标签移除后高度刻意与字号无关。
static func gpCellHeight(_gpUIFont: int) -> float:
	return GP_THUMB_PX + GP_CELL_PAD


# Initialize input handling and minimum size.
# 初始化输入处理与最小尺寸。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0.0, gpCellHeight(0))
	mouse_entered.connect(_gpOnMouseEntered)
	mouse_exited.connect(_gpOnMouseExited)
	# The hover name follows the project language, so retranslate on locale change.
	# 悬停名称随项目语言，故语言变化时重翻译。
	I18n.gpLocaleChanged.connect(_gpOnLocaleChanged)
	_gpRefreshTooltip()


# Refresh the hover tooltip from the localized display name.
# 由本地化显示名刷新悬停提示。
func _gpRefreshTooltip() -> void:
	tooltip_text = I18n.gpTr(gpDef.gpDisplayName) if gpDef != null else ""


func _gpOnLocaleChanged(_gpLocale: String) -> void:
	_gpRefreshTooltip()


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


# Draw the background and the symbol thumbnail, centered in the cell.
# 绘制背景与图元缩略图，在单元格内居中。
func _draw() -> void:
	# Default: NO background at all (the dock tint shows through — 2026-09-25 request).
	# On hover the WHOLE tile area lights up as the visual hint.
	# 默认：完全无底色（透出停靠栏底色 —— 2026-09-25 需求）。悬停时整块图块区域
	# 点亮，作为视觉提示。
	if _gpHover:
		draw_rect(Rect2(Vector2.ZERO, size), GPChromeStyle.GP_SPLIT_HI, true)

	if gpDef == null:
		return

	# Thumbnail rectangle, centered BOTH axes with the pad split evenly.
	# 缩略图矩形，两轴居中，边距均分。
	var gpThumbRect: Rect2 = Rect2(
		Vector2((size.x - gpThumbnailSize.x) / 2.0, (size.y - gpThumbnailSize.y) / 2.0),
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
