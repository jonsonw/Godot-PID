class_name GPCenterArea
extends VBoxContainer

# Tabbed multi-sheet drawing area (Godot-editor style). Each tab holds its own
# GPCanvas2D + GPPIDGraph, so the user can edit several P&ID sheets side by side
# and switch between them. A "+" button adds a sheet; a fullscreen toggle button
# (signal gpFullscreenToggled) lets the host hide the side docks so the canvas fills
# the window. This is the foundation for future multi-P&ID editing.
# 多标签页绘图区（仿 Godot 编辑器）。每个标签页持有独立的 GPCanvas2D + GPPIDGraph，
# 用户可同时编辑多张 P&ID 图纸并在其间切换。"+" 按钮新建图纸；全屏按钮（信号
# gpFullscreenToggled）让宿主隐藏左右停靠栏，使画布占满窗口。这是未来多 P&ID 编辑的基础。
# Coding rule: every variable must declare its type explicitly (including container types).
# 编码规范：所有变量均显式声明类型（含容器类型）。

# Emitted for every newly created canvas so the host can configure it (symbol
# definitions + signal connections) once.
# 每当新建画布时发出，供宿主一次性配置（图元定义 + 信号连接）。
signal gpOnCanvasReady(canvas: GPCanvas2D)

# Emitted when the active sheet changes (add / switch / close), so the host can
# refresh the inspector for the newly active selection.
# 活动图纸切换时（新建 / 切换 / 关闭）发出，供宿主刷新新活动页的选中属性。
signal gpActiveChanged

# Emitted when the fullscreen toggle button is pressed; gpOn == true means enter
# fullscreen (hide side docks), false means exit.
# 全屏切换按钮按下时发出；gpOn 为真表示进入全屏（隐藏侧栏），为假表示退出。
signal gpFullscreenToggled(gpOn: bool)


# Tab bar showing one tab per sheet.
# 每个图纸一个标签页的标签栏。
var gpTabBar: TabBar

# Container that stacks all sheet canvases; only the active one is visible.
# 承载所有图纸画布的容器；仅活动页可见。
var gpBody: Control

# Per-sheet records: { "title": String, "graph": GPPIDGraph, "canvas": GPCanvas2D }.
# 每个图纸的记录：{ "title": 标题, "graph": 图, "canvas": 画布 }。
var gpTabs: Array[Dictionary] = []

# Index of the currently active sheet in gpTabs (-1 when empty).
# 当前活动图纸在 gpTabs 中的下标（空时为 -1）。
var gpActive: int = -1

# Symbol definitions shared by every sheet (kept in sync via gpSetDefs).
# 所有图纸共用的图元定义（经 gpSetDefs 保持同步）。
var gpDefs: Array[GPSymbolDef] = []

# Monotonic counter used to number new sheet titles (P&ID 1, P&ID 2, ...).
# 用于给新图纸标题编号（图纸 1、图纸 2 …）的单调递增计数。
var gpSheetSeq: int = 0

# Whether fullscreen mode is currently active.
# 当前是否处于全屏模式。
var gpFullscreen: bool = false

# Reference to the fullscreen toggle button, so we can relabel it on locale change.
# 全屏切换按钮的引用，便于在语言变化时重新设置文字。
var gpFullBtn: Button


# Build the header (tab bar + add + fullscreen buttons) and the canvas body.
# The first sheet is NOT created here: the host connects gpOnCanvasReady first,
# then calls gpAddTab(), so the initial canvas is configured in the right order.
# 构建头部（标签栏 + 新建 + 全屏按钮）与画布体。此处不创建首张图纸：宿主先连接
# gpOnCanvasReady，再调用 gpAddTab()，使首张画布按正确顺序完成配置。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	# ---- header ----
	# ---- 头部 ----
	var gpHeader: HBoxContainer = HBoxContainer.new()
	gpHeader.custom_minimum_size = Vector2(0.0, 28.0)
	gpHeader.size_flags_horizontal = SIZE_EXPAND_FILL
	gpHeader.size_flags_vertical = SIZE_SHRINK_BEGIN
	gpHeader.add_theme_constant_override("separation", 2)
	# Tab bar grows to fill the header; the two buttons sit on its right.
	# 标签栏拉伸填满头部；两个按钮置于其右侧。
	gpTabBar = TabBar.new()
	gpTabBar.size_flags_horizontal = SIZE_EXPAND_FILL
	gpTabBar.size_flags_vertical = SIZE_SHRINK_CENTER
	# Show a close button only on the active tab (TabBar.CLOSE_BUTTON_SHOW_ACTIVE == 1).
	# 仅在活动标签上显示关闭按钮（TabBar.CLOSE_BUTTON_SHOW_ACTIVE == 1）。
	gpTabBar.tab_close_display_policy = 1
	gpTabBar.focus_mode = Control.FOCUS_NONE
	gpTabBar.tab_changed.connect(_gpOnTabChanged)
	gpTabBar.tab_close_pressed.connect(_gpOnTabClose)
	# Compact close button: small X icon + transparent background (drops the default pill).
	# 紧凑关闭按钮：小号 X 图标 + 透明背景（去掉默认按钮底）。
	gpTabBar.add_theme_icon_override("close", _gpMakeCloseIcon(8))
	var gpCloseBg: StyleBoxFlat = StyleBoxFlat.new()
	gpCloseBg.content_margin_left = 0.0
	gpCloseBg.content_margin_right = 0.0
	gpCloseBg.content_margin_top = 0.0
	gpCloseBg.content_margin_bottom = 0.0
	gpCloseBg.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	gpTabBar.add_theme_stylebox_override("button_pressed", gpCloseBg)
	gpTabBar.add_theme_stylebox_override("button_highlight", gpCloseBg)
	gpHeader.add_child(gpTabBar)
	# "+" button: add a new sheet.
	# "+" 按钮：新建图纸。
	var gpAddBtn: Button = Button.new()
	gpAddBtn.text = "+"
	gpAddBtn.tooltip_text = I18n.gpTr("center.add_tab")
	gpAddBtn.custom_minimum_size = Vector2(26.0, 0.0)
	gpAddBtn.focus_mode = Control.FOCUS_NONE
	gpAddBtn.pressed.connect(gpAddTab)
	gpHeader.add_child(gpAddBtn)
	# Fullscreen toggle button.
	# 全屏切换按钮。
	gpFullBtn = Button.new()
	gpFullBtn.text = I18n.gpTr("center.fullscreen")
	gpFullBtn.tooltip_text = I18n.gpTr("center.fullscreen_tip")
	gpFullBtn.toggle_mode = true
	gpFullBtn.custom_minimum_size = Vector2(40.0, 0.0)
	gpFullBtn.focus_mode = Control.FOCUS_NONE
	gpFullBtn.toggled.connect(_gpOnFullscreenToggle)
	gpHeader.add_child(gpFullBtn)
	add_child(gpHeader)
	# ---- body ----
	# ---- 画布体 ----
	gpBody = Control.new()
	gpBody.size_flags_horizontal = SIZE_EXPAND_FILL
	gpBody.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(gpBody)
	# Keep the static header labels (button tooltips) in sync with the locale.
	# 让头部静态文字（按钮提示）随语言同步。
	I18n.gpLocaleChanged.connect(_gpOnLocale)
	# 视觉分层：首帧自绘画布工作区背景（最亮一档，聚焦）。
	queue_redraw()


# ============================ public API ============================
# ============================ 公开接口 ============================
# Add a new sheet with a fresh graph and canvas, make it active, and announce it.
# 新建一张含独立图与画布的图纸并设为活动页，同时向外通告。
func gpAddTab() -> void:
	gpSheetSeq += 1
	var gpTitle: String = I18n.gpTr("center.sheet") + " " + str(gpSheetSeq)
	_gpAddTabWith(gpTitle, "sheet-" + str(gpSheetSeq))


# Return the active sheet's canvas (null if none).
# 返回活动图纸的画布（无则返回 null）。
func gpActiveCanvas() -> GPCanvas2D:
	if gpActive < 0 or gpActive >= gpTabs.size():
		return null
	return gpTabs[gpActive]["canvas"]


# Return the active sheet's graph (null if none).
# 返回活动图纸的图（无则返回 null）。
func gpActiveGraph() -> GPPIDGraph:
	if gpActive < 0 or gpActive >= gpTabs.size():
		return null
	return gpTabs[gpActive]["graph"]


# Return every sheet's canvas (not just the active one), so an operation can cascade
# across all open sheets — e.g. removing every placed instance of a deleted symbol.
# 返回每个图纸的画布（不只活动图纸），使操作能跨所有打开的图纸级联 —— 例如删除图元时
# 移除其全部已放置实例。
func gpAllCanvases() -> Array[GPCanvas2D]:
	var gpOut: Array[GPCanvas2D] = []
	for gpTab in gpTabs:
		var gpC: GPCanvas2D = gpTab["canvas"]
		if gpC != null and is_instance_valid(gpC):
			gpOut.append(gpC)
	return gpOut


# Replace the active sheet's graph (used when opening a project file).
# 替换活动图纸的图（打开工程文件时调用）。
func gpSetActiveGraph(gpNewGraph: GPPIDGraph) -> void:
	if gpActive < 0 or gpActive >= gpTabs.size():
		return
	gpTabs[gpActive]["graph"] = gpNewGraph
	var gpC: GPCanvas2D = gpTabs[gpActive]["canvas"]
	gpC.gpGraph = gpNewGraph


# Every open tab as a persistable GPSheet, in tab order.
# 把每个打开的标签页按标签顺序导出为可持久化的 GPSheet。
func gpToSheets() -> Array[GPSheet]:
	var gpOut: Array[GPSheet] = []
	var gpI: int = 0
	for gpTab in gpTabs:
		var gpSheet: GPSheet = GPSheet.new()
		gpSheet.gpId = str(gpTab.get("id", "sheet-" + str(gpI + 1)))
		gpSheet.gpName = str(gpTab.get("title", ""))
		gpSheet.gpIndex = gpI
		gpSheet.gpGraph = gpTab["graph"]
		gpOut.append(gpSheet)
		gpI += 1
	return gpOut


# Replace every open tab with gpSheets (used when opening a project file).
# 用 gpSheets 替换所有打开的标签页（打开工程文件时调用）。
# Existing canvases are torn down first: keeping them would leave orphaned GPCanvas2D
# nodes holding graphs that are no longer part of the project — invisible, but still
# receiving redraws and still holding memory.
# 先拆除既有画布：保留它们会留下持有「已不属于本工程」的图的孤立 GPCanvas2D 节点 ——
# 看不见，但仍在接收重绘、仍占着内存。
func gpLoadSheets(gpSheets: Array) -> void:
	for gpTab in gpTabs:
		var gpC: GPCanvas2D = gpTab["canvas"]
		if gpC != null and is_instance_valid(gpC):
			gpBody.remove_child(gpC)
			gpC.queue_free()
	gpTabs.clear()
	gpTabBar.clear_tabs()
	gpActive = -1
	gpSheetSeq = 0
	var gpI: int = 0
	for gpS in gpSheets:
		var gpSheet: GPSheet = gpS as GPSheet
		if gpSheet == null:
			continue
		gpSheetSeq += 1
		_gpAddTabWith(gpSheet.gpName, gpSheet.gpId, gpSheet.gpGraph)
		gpI += 1


# Push a new symbol-definition set to every sheet's canvas (e.g. after exporting
# a custom symbol pack). Also remembered for future sheets.
# 把新的图元定义集推送到每个图纸的画布（如导出自定义图元包后）。同时记录供后续图纸使用。
func gpSetDefs(gpNewDefs: Array[GPSymbolDef]) -> void:
	gpDefs = gpNewDefs
	for gpTab in gpTabs:
		var gpC: GPCanvas2D = gpTab["canvas"]
		gpC.gpDefs = gpNewDefs


# ============================ internal ============================
# ============================ 内部方法 ============================
# Create a sheet with the given title and wire it into the tab bar / body.
# 以给定标题创建图纸并接入标签栏 / 画布体。
# [param gpId] stable identity; empty is fine for a brand-new tab (gpToSheets derives one).
# [param gpId] 稳定标识；全新标签页留空亦可（gpToSheets 会推导一个）。
# [param gpGraphIn] when non-null the tab shows THIS graph instead of a fresh one.
# [param gpGraphIn] 非 null 时，该标签页显示**这个**图，而非新建一个。
func _gpAddTabWith(gpTitle: String, gpId: String = "", gpGraphIn: GPPIDGraph = null) -> void:
	var gpGraph: GPPIDGraph = gpGraphIn if gpGraphIn != null else GPPIDGraph.new()
	var gpCanvas: GPCanvas2D = GPCanvas2D.new()
	gpCanvas.gpGraph = gpGraph
	gpCanvas.gpDefs = gpDefs
	gpBody.add_child(gpCanvas)
	# Fill the body: the canvas is a plain Control child, so anchor it to the full rect.
	# 填满画布体：画布是普通 Control 子节点，故锚定到全矩形。
	gpCanvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpCanvas.visible = false
	var gpTab: Dictionary = {"id": gpId, "title": gpTitle, "graph": gpGraph, "canvas": gpCanvas}
	gpTabs.append(gpTab)
	gpTabBar.add_tab(gpTitle)
	var gpIdx: int = gpTabs.size() - 1
	gpTabBar.current_tab = gpIdx
	_gpShowOnly(gpIdx)
	gpOnCanvasReady.emit(gpCanvas)
	gpActiveChanged.emit()


# Show only the sheet at gpIdx; hide the rest.
# 仅显示 gpIdx 处的图纸，隐藏其余。
func _gpShowOnly(gpIdx: int) -> void:
	for gpI in range(gpTabs.size()):
		var gpC: GPCanvas2D = gpTabs[gpI]["canvas"]
		gpC.visible = (gpI == gpIdx)
	gpActive = gpIdx


# Active tab changed via the tab bar: switch the visible canvas and notify the host.
# 通过标签栏切换活动页：切换可见画布并通知宿主。
func _gpOnTabChanged(gpIdx: int) -> void:
	if gpIdx < 0 or gpIdx >= gpTabs.size():
		return
	_gpShowOnly(gpIdx)
	gpActiveChanged.emit()


# A tab's close button was pressed: drop that sheet (never close the last one).
# 某标签页关闭按钮被按下：移除该图纸（永不关闭最后一张）。
func _gpOnTabClose(gpIdx: int) -> void:
	if gpTabs.size() <= 1:
		return
	var gpTab: Dictionary = gpTabs[gpIdx]
	var gpC: GPCanvas2D = gpTab["canvas"]
	gpBody.remove_child(gpC)
	gpC.queue_free()
	gpTabs.remove_at(gpIdx)
	gpTabBar.remove_tab(gpIdx)
	# Keep the active index valid and re-show the correct canvas.
	# 保持活动下标合法并重新显示对应画布。
	var gpNew: int = mini(gpIdx, gpTabs.size() - 1)
	gpTabBar.current_tab = gpNew
	_gpShowOnly(gpNew)
	gpActiveChanged.emit()


# Fullscreen toggle: remember state, relabel the button, and forward to the host.
# 全屏切换：记录状态、重设按钮文字，并转发给宿主。
func _gpOnFullscreenToggle(gpOn: bool) -> void:
	gpFullscreen = gpOn
	if gpFullBtn != null:
		gpFullBtn.text = I18n.gpTr("center.fullscreen_exit") if gpOn else I18n.gpTr("center.fullscreen")
	gpFullscreenToggled.emit(gpOn)


# Locale changed: refresh the static header button labels.
# 语言变化：刷新头部静态按钮文字。
func _gpOnLocale(_gpLocale: String) -> void:
	# Titles are user-facing sheet names; keep them. Only refresh the button labels.
	# 标题是用户可见的图纸名，保持不变；仅刷新按钮文字。
	if gpFullBtn != null:
		gpFullBtn.text = I18n.gpTr("center.fullscreen_exit") if gpFullscreen else I18n.gpTr("center.fullscreen")


# Generate a small, crisp "X" close icon for the tab bar (gpSize px, transparent bg).
# 为标签栏生成细巧的 “X” 关闭图标（gpSize 像素，透明底）。
func _gpMakeCloseIcon(gpSize: int) -> Texture2D:
	var gpImg: Image = Image.create(gpSize, gpSize, false, Image.FORMAT_RGBA8)
	gpImg.fill(Color(0.0, 0.0, 0.0, 0.0))
	var gpCol: Color = Color(0.60, 0.62, 0.68, 1.0)
	var gpT: int = 1  # X line thickness in px / X 线宽（像素）
	for gpX in range(gpSize):
		for gpY in range(gpSize):
			# Two diagonals form an X. / 两条对角线构成 X。
			if abs(gpX - gpY) <= gpT or abs(gpX + gpY - (gpSize - 1)) <= gpT:
				gpImg.set_pixel(gpX, gpY, gpCol)
	return ImageTexture.create_from_image(gpImg)

# Paint the canvas working-area background (brightest tier) so the sheet stands out
# from the darker side docks; canvas content draws on top.
# 自绘画布工作区背景（最亮一档），使图纸从较暗侧栏中凸显；画布内容绘制于其上。
func _draw() -> void:
	GPChromeStyle.gpDraw(self, GPChromeStyle.GP_CANVAS_BG, 0)
