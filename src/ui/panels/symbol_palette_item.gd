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

# Emitted once the pointer has travelled far enough to call this gesture a DRAG rather than a
# click (规划 §15, interaction mode 1). The library does not itself know how attaching works — the
# host turns this into "arm an attachment" and owns the cursor and the status text.
# 指针位移足够大、足以把本次手势判定为**拖动**（而非点击）时发出一次（规划 §15，交互模式一）。
# 图元库自身并不知道挂载如何运作 —— 由宿主把它转成「附件上膛」，并接管光标与状态文案。
signal gpDragStarted(type_id: String)

# Emitted when the user requests deletion of this symbol via the context menu. The
# actual deletion (and any cascade removal of canvas instances) is owned by the main
# window, which holds the graphs; this item only forwards the user's intent.
# 用户经右键菜单请求删除本图元时发出。真正的删除（及画布实例的级联清理）由主窗口
# 负责，本条目只转发用户意图。
signal gpDeleteRequested(gpId: String)

# Context-menu action ids (only one today, but keep the enum form for future actions).
# 右键菜单动作 id（目前仅一项，但保留枚举形式以便扩展）。
const GP_CTX_DELETE: int = 0

# How far the pointer must travel from the press point before a click becomes a drag.
# 指针自按下点位移多远后，点击才算变成拖动。
# 6 px is above the jitter of a normal click (a hand-driven click rarely moves more than 2-3 px)
# and below the distance at which the gesture visually reads as "I am moving this".
# 6 px 高于正常点击的抖动（手点一下很少移动超过 2–3 px），又低于手势看上去像「我在搬它」的距离。
const GP_DRAG_THRESHOLD_PX: float = 6.0

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

# Drag detection state. A press ARMS the gesture; only the motion that follows decides whether it
# was a click or a drag (see _gui_input / _input).
# 拖动检测状态。按下只是**上膛**；随后的位移才决定这是一次点击还是一次拖动（见 _gui_input / _input）。
var _gpPressActive: bool = false

# Viewport-space point where the press landed, the origin the drag distance is measured from.
# 按下点（视口坐标），拖动距离由此起算。
var _gpPressPos: Vector2 = Vector2.ZERO

# True once the threshold has been crossed for the CURRENT press. Doubles as the "已发布过" guard,
# so gpDragStarted fires exactly once per gesture.
# 当前这次按下是否已越过阈值。同时充当「已发出过」护栏，使 gpDragStarted 每次手势只发一次。
var _gpDragging: bool = false


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
	# Global input listening stays OFF until a press arms the gesture. Defining _input() makes the
	# engine call it for every event in the app, so leaving it on for every palette tile would be a
	# permanent per-event cost for a feature that is idle 99% of the time.
	# 全局输入监听在按下上膛之前保持**关闭**。定义 _input() 会让引擎为应用内每个事件调用它，
	# 若每块图元库图块都常开，就是一个 99% 时间闲置的功能产生的持续逐事件开销。
	set_process_input(false)


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
#
# Press and release are handled ASYMMETRICALLY on purpose / 按下与抬起刻意**不对称**处理：
# the press merely ARMS the gesture. Whether it turns out to be a click (-> gpPicked) or a drag
# (-> gpDragStarted) is decided by the motion in between, and that motion is observed by _input(),
# because a drag leaves this control within a few pixels and _gui_input() stops being called the
# moment it does. Emitting gpPicked on the press — which is what this used to do — would fire a
# full placement for every drag that started on a tile.
# 按下只是**上膛**。它究竟变成点击（→ gpPicked）还是拖动（→ gpDragStarted）由其间的位移决定，
# 而位移由 _input() 观察 —— 因为拖动会在几个像素内离开本控件，而 _gui_input() 在那一刻就不再被调用。
# 在按下时发 gpPicked（这曾是本函数的做法）会让每一次从图块开始的拖动都触发一次完整放置。
func _gui_input(gpEvent: InputEvent) -> void:
	if gpEvent is InputEventMouseButton:
		var gpMouseEvent: InputEventMouseButton = gpEvent as InputEventMouseButton
 # Right-click opens the symbol-library context menu (delete, etc.).
 # 右键打开图元库上下文菜单（删除等）。
		if gpMouseEvent.button_index == MOUSE_BUTTON_RIGHT and gpMouseEvent.pressed:
			accept_event()
			_gpShowContextMenu()
			return
		if gpMouseEvent.button_index == MOUSE_BUTTON_LEFT:
			if gpMouseEvent.pressed:
				accept_event()
				_gpBeginPress(gpMouseEvent.global_position)
			elif _gpPressActive:
				# Fallback for an in-place release. _input() normally gets there first (it runs
				# before the GUI phase) and clears the flag, so this branch simply never fires in
				# the common case — it exists so the gesture still resolves if _input() was
				# disabled by something else.
				# 原地抬起的兜底分支。通常 _input() 先到（它跑在 GUI 阶段之前）并清掉标志，
				# 故常见情形下本分支根本不触发 —— 它的存在只为在 _input() 被别处关掉时手势仍能了结。
				accept_event()
				_gpResolveRelease()


# Start tracking a press. Auto-click or double-click never reaches here as a "drag": the flag is
# reset on every release, so each gesture is judged on its own motion.
# 开始跟踪一次按下。自动连点或双击都不会被当成拖动：标志在每次抬起时复位，故每次手势各按自身位移判定。
func _gpBeginPress(gpScreen: Vector2) -> void:
	_gpPressActive = true
	_gpDragging = false
	_gpPressPos = gpScreen
	set_process_input(true)
	queue_redraw()


# Watch the global stream for two things the item cannot see locally: the motion that proves a drag
# (the pointer has left this control by then) and the release that ends it (the pointer may now be
# over the canvas, which would otherwise swallow the event and leave this item stuck armed forever).
# 在全局事件流中观察两件本条目在本地看不到的事：足以证明是拖动的位移（此时指针已离开本控件），
# 以及终结手势的抬起（指针此刻可能在画布上，否则该事件会被画布吞掉、本条目将永远卡在上膛态）。
func _input(gpEvent: InputEvent) -> void:
	if not _gpPressActive:
		return
	if gpEvent is InputEventMouseMotion:
		# A gesture on a PRIMARY symbol (no mount kind) is never a drag: it cannot be mounted, so
		# the only meaningful reading of "I dragged a pump" is "I want to place a pump" — which is
		# exactly what the pick does. Classifying it here keeps the pointer from arming a gesture
		# that is guaranteed to fail, and costs the user nothing (the release still emits gpPicked).
		# 主图元（无挂载类型）上的手势永远不是拖动：它无法被挂载，故「我拖了一台泵」唯一有意义的
		# 解读是「我要放一台泵」—— 而这正是点选所做的事。在此分类可避免指针上膛一个注定失败的
		# 手势，且用户毫无损失（抬起时仍会发出 gpPicked）。
		if gpDef == null or gpDef.gpMountKind == "":
			return
		if not _gpDragging and (gpEvent.global_position - _gpPressPos).length() >= GP_DRAG_THRESHOLD_PX:
			_gpDragging = true
			# Hand the gesture over, then FORGET it locally: the item keeps no notion of what a
			# drag means, so there is exactly one place (the host) that knows how attaching works.
			# 交出一次手势，随后在本地**忘掉**它：本条目对「拖动意味着什么」一无所知，
			# 故「挂载如何运作」只有一处（宿主）知道。
			gpDragStarted.emit(gpDef.gpId)
	elif gpEvent is InputEventMouseButton:
		var gpMb: InputEventMouseButton = gpEvent as InputEventMouseButton
		if gpMb.button_index == MOUSE_BUTTON_LEFT and not gpMb.pressed:
			_gpResolveRelease()


# End the gesture: emit gpPicked only when the pointer never crossed the threshold, then disarm.
# 了结本次手势：仅当指针从未越过阈值时发出 gpPicked，随后解除上膛。
# Guards on _gpPressActive so it is harmless to call twice for one release (see _gui_input).
# 以 _gpPressActive 为护栏，故同一次抬起调用两次也无副作用（见 _gui_input）。
func _gpResolveRelease() -> void:
	if not _gpPressActive:
		return
	var gpWasDrag: bool = _gpDragging
	_gpPressActive = false
	_gpDragging = false
	set_process_input(false)
	queue_redraw()
	if gpWasDrag:
		return
	gpPicked.emit(gpDef.gpId if gpDef != null else "")


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
