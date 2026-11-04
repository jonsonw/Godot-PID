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

# D22: the four layout-mode buttons as one radio group (pressed = current mode).
# D22：四个布局模式按钮构成一组单选（按下态 = 当前模式）。
var gpLayoutButtons: Array[Button] = []

# Container that stacks all sheet canvases; only the active one is visible.
# 承载所有图纸画布的容器；仅活动页可见。
var gpBody: Control

# Per-sheet records: { "title": String, "graph": GPPIDGraph, "canvas": GPCanvas2D }.
# 每个图纸的记录：{ "title": 标题, "graph": 图, "canvas": 画布 }。
var gpTabs: Array[Dictionary] = []

# Index of the currently active sheet in gpTabs (-1 when empty).
# 当前活动图纸在 gpTabs 中的下标（空时为 -1）。
var gpActive: int = -1

# --- W13 multi-view (ADR-44) ----------------------------------------------
# The current layout mode (GPPaneLayout constants). Only the MODE persists (Settings);
# the bindings below are session state.
# 当前布局模式（GPPaneLayout 常量）。只有**模式**持久化（Settings）；以下绑定是会话状态。
var gpLayoutMode: int = GPPaneLayout.GP_SINGLE

# The panes of the current layout, left-to-right / top-to-bottom.
# 当前布局的窗格，自左向右 / 自上而下。
var _gpPanes: Array[GPCanvasPane] = []

# Pane i shows tab _gpPaneSheets[i] (GPPaneLayout.GP_EMPTY = empty pane). THE binding
# invariant (ADR-44 D2): a sheet index appears at most once.
# 窗格 i 显示标签 _gpPaneSheets[i]（GPPaneLayout.GP_EMPTY = 空窗格）。**绑定不变量**
#（ADR-44 D2）：一个图纸下标至多出现一次。
var _gpPaneSheets: Array[int] = []

# The pane the docks serve (ADR-44 D4: focus decides).
# 侧栏服务的窗格（ADR-44 D4：焦点决定）。
var _gpActivePane: int = 0

# The layout container inside gpBody; rebuilt on every mode switch.
# gpBody 内的布局容器；每次切换模式重建。
var _gpLayoutRoot: Control = null

# The embedded pop-out window (W13-S7) and the sheet tab it currently hosts (-1 = none).
# 嵌入式摘出窗口（W13-S7）与其当前承载的图纸标签（-1 = 无）。
var _gpPopWin: Window = null
var _gpPopSheet: int = GPPaneLayout.GP_EMPTY
# The pane that popped the canvas out (its preferential home on return).
# 摘出画布的窗格（归位时的优先去处）。
var _gpPopPane: int = 0

# Guards: while loading sheets the tab-changed signal must not re-bind panes (the load
# assigns them once at the end); while the tab bar is synced FROM the pane state, the
# tab-changed handler must not bounce back.
# 护栏：载入图纸期间 tab 变化信号**不得**重绑窗格（载入在末尾一次性指派）；
# 从窗格状态反向同步标签栏时，tab 变化处理器**不得**回弹。
var _gpLoading: bool = false
var _gpTabSyncing: bool = false

# Container-level cross-sheet off-page links (ADR-43). Links reference TWO sheets, so they
# are owned HERE — next to gpTabs, never inside any single sheet's graph. file_coordinator
# fills this on load and reads it on save; S3/S4 (commands, DRC) reach it the same way.
# 容器级跨图纸 Off-Page 连接（ADR-43）。link 两端各引用一张图纸，故归属**此处** ——
# 与 gpTabs 并列，绝不放进任何单张图纸的 graph。file_coordinator 载入时填充、保存时读取；
# S3/S4（命令与 DRC）经同一路径访问。
var gpOffPageLinks: Array[GPOffPageLink] = []

# The PROJECT's numbering standard shared by every tab (ADR-36). Null until something asks
# for it, so a project that never numbers anything still saves no `tag_rules` key.
# 全部标签页共享的**工程**编号标准（ADR-36）。在被索取之前为 null，故从不编号的工程
# 仍然不写出 `tag_rules` 键。
var gpProjectStandard: GPProjectStandard = null

# Symbol definitions shared by every sheet (kept in sync via gpSetDefs()).
# 所有图纸共用的图元定义（经 gpSetDefs() 保持同步）。
var gpDefs: Array[GPSymbolDef] = []

# Monotonic counter used to number new sheet titles (P&ID 1, P&ID 2, ...).
# 用于给新图纸标题编号（图纸 1、图纸 2 …）的单调递增计数。
var gpSheetSeq: int = 0

# Whether fullscreen mode is currently active.
# 当前是否处于全屏模式。
var gpFullscreen: bool = false

# Reference to the fullscreen toggle button, so we can re-tooltip it on locale change.
# 全屏切换按钮的引用，便于在语言变化时重设提示语。
var gpFullBtn: Button

# Inline rename editor (double-click a sheet tab). Created once; top-level so it
# floats over the tab band without participating in the VBox layout.
# 行内重命名编辑器（双击图纸 tab）。仅创建一次；top-level 使其悬浮于标签带之上、
# 不参与 VBox 布局。
var _gpRenameEdit: LineEdit = null

# Index of the sheet being renamed (-1 while idle).
# 正在重命名的图纸下标（空闲时为 -1）。
var _gpRenameIdx: int = -1


# Build the header (tab bar + add + fullscreen buttons) and the canvas body.
# The first sheet is NOT created here: the host connects gpOnCanvasReady first,
# then calls gpAddTab(), so the initial canvas is configured in the right order.
# 构建头部（标签栏 + 新建 + 全屏按钮）与画布体。此处不创建首张图纸：宿主先连接
# gpOnCanvasReady，再调用 gpAddTab()，使首张画布按正确顺序完成配置。
func _ready() -> void:
	# Assembly list: header (tab bar + the two icon buttons) -> canvas body -> locale hook.
	# 装配清单：头部（标签栏 + 两个图标按钮）→ 画布体 → 语言订阅。
	mouse_filter = MOUSE_FILTER_STOP
	add_child(_gpBuildHeader())
	gpBody = _gpBuildBody()
	# W13-S6 (ADR-44): restore the persisted layout mode, then build the pane tree. The
	# default (and every invalid stored value) is the historical single-pane look.
	# W13-S6（ADR-44）：恢复持久化的布局模式，然后构建窗格树。默认（及一切非法存值）
	# 是历史上的单窗外观。
	var gpStored: int = Settings.gpLayoutMode
	gpLayoutMode = gpStored if GPPaneLayout.gpIsValid(gpStored) else GPPaneLayout.GP_SINGLE
	_gpRebuildLayout()
	# Keep the static header tooltips in sync with the locale.
	# 让头部静态文字（按钮提示）随语言同步。
	I18n.gpLocaleChanged.connect(_gpOnLocale)
	# 视觉分层：首帧自绘画布工作区背景（最亮一档，聚焦）。
	queue_redraw()


# Header row: the tab band, then "+" and the fullscreen toggle at its right end.
# 头部行：标签色带，其后是「+」与全屏切换按钮（贴在色带右端）。
func _gpBuildHeader() -> HBoxContainer:
	var gpHeader: HBoxContainer = HBoxContainer.new()
	gpHeader.custom_minimum_size = Vector2(0.0, 28.0)
	gpHeader.size_flags_horizontal = SIZE_EXPAND_FILL
	gpHeader.size_flags_vertical = SIZE_SHRINK_BEGIN
	# Zero separation: the "+" button must sit FLUSH against the last sheet tab.
	# 零间距：「+」按钮必须紧贴最后一张图纸的 tab。
	gpHeader.add_theme_constant_override("separation", 0)
	gpHeader.add_child(_gpBuildTabBar())
	gpHeader.add_child(_gpBuildAddButton())
	gpHeader.add_child(_gpBuildFullscreenButton())
	gpHeader.add_child(_gpBuildLayoutButtons())
	# (No spacer needed: the tab band itself EXPANDs, so "+" and the fullscreen
	# button ride at the band's right end — "+" adapts right as tabs are added.)
	# （无需占位：tab 色带自身 EXPAND，「+」与全屏按钮贴在色带右端 ——
	# 新增图纸时「+」自适应右移。）
	return gpHeader


# The four layout-mode buttons (ADR-44 D1). Toggle-like: the current mode keeps the accent
# plate, so the mode stays visible without text.
# 四个布局模式按钮（ADR-44 D1）。类切换：当前模式保持 accent 色块，无文字也能看清模式。
func _gpBuildLayoutButtons() -> HBoxContainer:
	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 2)
	var gpSpecs: Array = [
		[GPPaneLayout.GP_SINGLE, "center.layout1_tip", "res://assets/icons/layout1.svg"],
		[GPPaneLayout.GP_SIDE, "center.layout2_tip", "res://assets/icons/layout2.svg"],
		[GPPaneLayout.GP_BIG2, "center.layout3_tip", "res://assets/icons/layout3.svg"],
		[GPPaneLayout.GP_GRID, "center.layout4_tip", "res://assets/icons/layout4.svg"],
	]
	for gpS in gpSpecs:
		var gpBtn: Button = _gpMakeIconButton(str(gpS[1]), str(gpS[2]))
		var gpMode: int = int(gpS[0])
		gpBtn.pressed.connect(func() -> void: gpSetLayoutMode(gpMode))
		gpBtn.set_meta("gp_layout_mode", gpMode)
		# D22: toggle_mode turns the "pressed" plate into a persistent radio state; the
		# sync below seeds it with the mode restored from Settings.
		# D22：toggle_mode 让「按下」色块成为持久的单选态；下方 sync 用 Settings 恢复的
		# 模式播种初值。
		gpBtn.toggle_mode = true
		gpLayoutButtons.append(gpBtn)
		gpRow.add_child(gpBtn)
	_gpSyncLayoutButtons()
	return gpRow


# The sheet tab band, styled to mirror the right inspector's tabs.
# 图纸标签色带，样式镜像右侧属性面板的标签。
func _gpBuildTabBar() -> TabBar:
	gpTabBar = TabBar.new()
	# EXPAND_FILL: the tab band TILES across the whole header width, so "+" follows the band's
	# right end and moves right automatically as tabs are added.
	# EXPAND_FILL：tab 色带**平铺**整个头部宽度，「+」跟随色带右端、随新增标签自适应右移。
	gpTabBar.size_flags_horizontal = SIZE_EXPAND_FILL
	gpTabBar.size_flags_vertical = SIZE_SHRINK_CENTER
	gpTabBar.custom_minimum_size = Vector2(0.0, 26.0)
	# Sheet-tab styling mirrors the RIGHT inspector tabs: same dock-toned band,
	# same compact geometry, same selected look (dark fill + accent underline).
	# 图纸 tab 样式与右侧属性面板 tab 同款：同色带、同紧凑尺寸、同选中态（深底 + accent 底线）。
	var gpTabPanel: StyleBoxFlat = GPChromeStyle.gpStyleFor(GPChromeStyle.GP_DOCK_BG, 0)
	gpTabBar.add_theme_stylebox_override("panel", gpTabPanel)
	var gpTabBg: StyleBoxFlat = GPChromeStyle.gpStyleFor(GPChromeStyle.GP_DOCK_BG, GPChromeStyle.SIDE_BOTTOM)
	gpTabBg.content_margin_left = 10.0
	gpTabBg.content_margin_right = 10.0
	gpTabBg.content_margin_top = 3.0
	gpTabBg.content_margin_bottom = 3.0
	gpTabBar.add_theme_stylebox_override("tab_unselected", gpTabBg)
	gpTabBar.add_theme_stylebox_override("tab_hovered", gpTabBg)
	var gpTabSel: StyleBoxFlat = gpTabBg.duplicate() as StyleBoxFlat
	gpTabSel.bg_color = Color(0.129, 0.165, 0.204)
	gpTabSel.border_color = GPChromeStyle.GP_ACCENT
	gpTabSel.border_width_bottom = 1
	gpTabBar.add_theme_stylebox_override("tab_selected", gpTabSel)
	gpTabBar.add_theme_constant_override("side_margin", 0)
	# Show a close button only on the active tab (enum value 1, probed via ClassDB).
	# 仅在活动标签上显示关闭按钮（枚举值 1，已经 ClassDB 探针核实）。
	gpTabBar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	gpTabBar.focus_mode = Control.FOCUS_NONE
	gpTabBar.tab_changed.connect(_gpOnTabChanged)
	gpTabBar.tab_close_pressed.connect(_gpOnTabClose)
	# Double-click on a tab starts the inline rename editor (2026-09-25 request).
	# 双击标签页启动行内重命名编辑器（2026-09-25 需求）。
	gpTabBar.gui_input.connect(_gpOnTabBarInput)
	# Compact close button: small X icon + transparent background (drops the default pill).
	# The click TARGET must stay generous: TabBar only emits tab_close_pressed when both
	# press AND release land inside the close-button rect, so an 8px icon with zero
	# margins was a near-invisible 8x8 target — a tiny hand tremor between press and
	# release silently swallowed the click ("the X does nothing"). 10px icon + 4px
	# horizontal margins give an ~18x16 target while keeping the look compact.
	# 紧凑关闭按钮：小号 X 图标 + 透明背景（去掉默认按钮底）。但**命中区**必须够大：
	# TabBar 只有在按下与松开都落在关闭按钮矩形内时才发射 tab_close_pressed —— 8px 图标
	# 加零边距几乎是隐形的 8×8 目标，按-放之间手一抖点击就被静默吞掉（即「点 X 没反应」）。
	# 10px 图标 + 4px 水平边距给出约 18×16 的目标，同时保持紧凑观感。
	gpTabBar.add_theme_icon_override("close", _gpMakeCloseIcon(10))
	var gpCloseBg: StyleBoxFlat = StyleBoxFlat.new()
	gpCloseBg.content_margin_left = 4.0
	gpCloseBg.content_margin_right = 4.0
	gpCloseBg.content_margin_top = 0.0
	gpCloseBg.content_margin_bottom = 0.0
	gpCloseBg.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	gpTabBar.add_theme_stylebox_override("button_pressed", gpCloseBg)
	gpTabBar.add_theme_stylebox_override("button_highlight", gpCloseBg)
	return gpTabBar


# The three plate styles every header icon button shares (normal / hover / active).
# Both buttons get their OWN duplicates, so tweaking one cannot affect the other.
# 所有头部图标按钮共用的三种色块样式（常态 / 悬停 / 激活）。
# 两个按钮各取自己的副本，故调整其一不会影响另一个。
func _gpPlateStyles() -> Array:
	var gpPlate: StyleBoxFlat = StyleBoxFlat.new()
	gpPlate.bg_color = Color(0.180, 0.216, 0.267)
	gpPlate.set_corner_radius_all(3)
	gpPlate.set_content_margin_all(4.0)
	var gpHover: StyleBoxFlat = gpPlate.duplicate() as StyleBoxFlat
	gpHover.bg_color = GPChromeStyle.GP_SPLIT_HI
	var gpPlateActive: StyleBoxFlat = gpPlate.duplicate() as StyleBoxFlat
	gpPlateActive.bg_color = Color(0.129, 0.165, 0.204)
	gpPlateActive.border_color = GPChromeStyle.GP_ACCENT
	gpPlateActive.border_width_bottom = 1
	return [[ "normal", gpPlate ], [ "hover", gpHover ], [ "pressed", gpPlateActive ]]


# A header icon button on a rounded plate, slightly lighter than the dock; hover brightens it —
# matching the category-band family. Plate metrics are shared with the fullscreen button.
# 头部图标按钮：比 dock 略亮的圆角色块，悬停提亮 —— 与类目色带同族。
# 色块度量与全屏按钮共用。
func _gpMakeIconButton(gpTipKey: String, gpIconPath: String) -> Button:
	var gpBtn: Button = Button.new()
	gpBtn.tooltip_text = I18n.gpTr(gpTipKey)
	var gpIcon: Texture2D = load(gpIconPath) as Texture2D
	if gpIcon != null:
		gpBtn.icon = gpIcon
	gpBtn.add_theme_constant_override("icon_max_width", 14)
	gpBtn.custom_minimum_size = Vector2(24.0, 22.0)
	gpBtn.focus_mode = Control.FOCUS_NONE
	for gpSb in _gpPlateStyles():
		gpBtn.add_theme_stylebox_override(str(gpSb[0]), (gpSb[1] as StyleBoxFlat).duplicate() as StyleBoxFlat)
	gpBtn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return gpBtn


# "+" — adds a new sheet. / 「+」—— 新建图纸。
func _gpBuildAddButton() -> Button:
	var gpAddBtn: Button = _gpMakeIconButton("center.add_tab", "res://assets/icons/plus.svg")
	gpAddBtn.pressed.connect(gpAddTab)
	return gpAddBtn


# Fullscreen toggle. The active (fullscreen ON) state keeps the accent plate so the mode stays
# visible without any text.
# 全屏切换按钮。激活（全屏开启）时保持 accent 色块，无文字也能看清模式状态。
func _gpBuildFullscreenButton() -> Button:
	gpFullBtn = _gpMakeIconButton("center.fullscreen_tip", "res://assets/icons/fullscreen.svg")
	gpFullBtn.toggle_mode = true
	gpFullBtn.toggled.connect(_gpOnFullscreenToggle)
	return gpFullBtn


# The canvas working area. It paints its OWN canvas tint — the Center container itself wears the
# dock tint so the tab row blends with the right dock's band.
# 画布工作区。它自绘画布色 —— Center 容器自身为 dock 色，使 tab 行与右栏色带融为一体。
func _gpBuildBody() -> Control:
	var gpBodyOut: Control = Control.new()
	gpBodyOut.size_flags_horizontal = SIZE_EXPAND_FILL
	gpBodyOut.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(gpBodyOut)
	# The layout container (W13-S6): the pane tree lives HERE; gpBodyOut only paints the
	# canvas tint behind it.
	# 布局容器（W13-S6）：窗格树住在这里；gpBodyOut 只在其后绘制画布色。
	_gpLayoutRoot = Control.new()
	_gpLayoutRoot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gpBodyOut.add_child(_gpLayoutRoot)
	gpBodyOut.draw.connect(_gpDrawBodyBg)
	gpBodyOut.resized.connect(gpBodyOut.queue_redraw)
	gpBodyOut.queue_redraw()
	return gpBodyOut


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


# The active sheet's GPSheet (frame size, title block, label mode); null if none.
# 活动图纸的 GPSheet（图幅、标题栏、语言模式）；无则返回 null。
func gpActiveSheet() -> GPSheet:
	if gpActive < 0 or gpActive >= gpTabs.size():
		return null
	return gpTabs[gpActive].get("sheet") as GPSheet


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


# Activate a sheet by its stable id (or name). Returns true when it was found.
# Used by the DRC dialog's whole-project rows, which may point at another sheet.
# 按稳定 id（或名称）激活图纸。供 DRC 弹窗的全工程行使用（可能指向另一张图纸）。
func gpActivateSheet(gpSheetId: String) -> bool:
	if gpSheetId == "":
		return false
	for gpI in range(gpTabs.size()):
		var gpSheet: GPSheet = gpTabs[gpI].get("sheet") as GPSheet
		if gpSheet == null:
			continue
		if gpSheet.gpId == gpSheetId or gpSheet.gpName == gpSheetId:
			# W13 (ADR-44): "activate" = show in the ACTIVE pane (the DRC jump lands where
			# the user is looking). The tab bar follows; the handler keeps them in step.
			# W13（ADR-44）：「激活」= 在**活动**窗格中显示（DRC 跳转落在用户正看着的地方）。
			# 标签栏跟随；处理器保持二者一致。
			# D02: a popped sheet consumes the activation (the popup got focused and the
			# signal already fired) — do NOT re-emit.
			# D02：已摘出图纸会**消费**激活（弹窗已聚焦、信号已发）—— 不得重复发。
			if _gpBindActivePane(gpI):
				return true
			_gpTabSyncing = true
			gpTabBar.current_tab = gpI
			_gpTabSyncing = false
			gpActiveChanged.emit()
			return true
	return false


# Replace the active sheet's graph (used when opening a project file).
# 替换活动图纸的图（打开工程文件时调用）。
func gpSetActiveGraph(gpNewGraph: GPPIDGraph) -> void:
	if gpActive < 0 or gpActive >= gpTabs.size():
		return
	gpTabs[gpActive]["graph"] = gpNewGraph
	var gpC: GPCanvas2D = gpTabs[gpActive]["canvas"]
	gpC.gpGraph = gpNewGraph


# Install the container-level link table (ADR-43). THE way to set it: it also re-publishes the
# render snapshot, so a connector's derived reference never lags the data it derives from.
# 安装容器级连接表（ADR-43）。这是设置它的**唯一**途径：它同时重新发布渲染快照，使连接符推导出的
# 交叉编号永不落后于它所依据的数据。
func gpSetOffPageLinks(gpLinks: Array[GPOffPageLink]) -> void:
	gpOffPageLinks = gpLinks
	gpRefreshOffPageContext()


# Publish {sheet_id: drawing number} + the link table to GPOffPageIndex, then repaint every symbol
# view so the flags re-resolve their reference text (ADR-43 D3: the text is derived at render time,
# so nothing repaints by itself when the DATA behind it changes).
# 把 {sheet_id: 图号} 与 link 表发布给 GPOffPageIndex，然后重绘全部图元视图，使旗标重新解析其
# 交叉编号（ADR-43 D3：文字在渲染期推导，故其背后的**数据**变化时不会有任何东西自动重绘）。
# Called after any change to the tab list, a sheet's number or the link table. Cheap on purpose
# (a dictionary rebuild + a repaint): the alternative — a change notification per touched sheet —
# would be a second source of "when is the snapshot valid", and this one cannot silently drift.
# 在标签列表、某张图纸的图号或 link 表变化后调用。刻意保持廉价（重建一个字典 + 一次重绘）：
# 另一条路是为每张受影响的图纸做变更通知，那会多出一个「快照何时有效」的判定来源，而本方案不可能
# 悄悄脱节。
func gpRefreshOffPageContext() -> void:
	var gpNumbers: Dictionary = {}
	var gpGraphs: Dictionary = {}
	var gpIdx: int = 0
	for gpTabRaw in gpTabs:
		gpIdx += 1
		var gpSheet: GPSheet = (gpTabRaw as Dictionary).get("sheet") as GPSheet
		if gpSheet == null:
			continue
		# ADR-43 D4 reads the DRAWING NUMBER; a project that never ran the numbering standard has
		# none, and a flag reading "?" on every sheet of a perfectly valid drawing would be a
		# worse answer than the sheet's position ("see sheet 3"). The number therefore wins, and
		# the 1-based tab position is only the fallback — it never enters the document.
		# ADR-43 D4 取**图号**；从未运行编号标准的工程没有图号，而在一张完全有效的图纸上每面旗标都
		# 显示「?」，比显示图纸位置（「见第 3 张图」）更糟。故图号优先，1 起的标签位置仅作回落 ——
		# 它绝不进入文档。
		var gpNo: String = gpSheet.gpNumber.strip_edges()
		gpNumbers[gpSheet.gpId] = gpNo if gpNo != "" else str(gpIdx)
		# The graphs ride along so DERIVED texts can reach the TARGET end's tag (user feedback
		# 2026-11-03) — same by-reference snapshot as the link table.
		# 图随快照一同下发，使**推导**文字能够到**目标端**位号（用户反馈 2026-11-03）
		# —— 与 link 表同一份按引用快照。
		gpGraphs[gpSheet.gpId] = gpSheet.gpGraph
	GPOffPageIndex.gpSetContext(gpOffPageLinks, gpNumbers, gpGraphs)
	for gpTabRaw in gpTabs:
		var gpC: GPCanvas2D = (gpTabRaw as Dictionary).get("canvas") as GPCanvas2D
		if gpC != null and is_instance_valid(gpC):
			gpC.gpRefreshSymbolViews()
			gpC.queue_redraw()


# ADR-43 / S3: jump to the PEER end of the link a connector stands for — switch to the
# peer sheet's tab and select the peer connector. Navigation is deliberately NOT an
# undoable command: it changes nothing in any document.
# ADR-43 / S3：跳转到连接符所在 link 的**对端** —— 切到对端图纸的标签页并选中对端连接符。
# 导航刻意**不是**可撤销命令：它不改动任何文档。
func gpJumpToPeerConnector(gpNodeId: String) -> bool:
	var gpLink: GPOffPageLink = GPOffPageIndex.gpLinkForNode(gpNodeId)
	if gpLink == null:
		return false
	var gpPeer: Dictionary = GPOffPageIndex.gpPeerRefOf(gpLink, gpNodeId)
	var gpSheetId: String = str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, ""))
	var gpPeerNode: String = str(gpPeer.get(GPOffPageLink.GP_KEY_NODE, ""))
	if gpSheetId == "" or gpPeerNode == "":
		return false
	if not gpActivateSheet(gpSheetId):
		return false
	var gpC: GPCanvas2D = gpActiveCanvas()
	if gpC != null:
		gpC.gpSetSelection([gpPeerNode])
	return true


# The LIVE link table (same array the commands mutate — providers share identity, never copy).
# **活的** link 表（与命令改写的是同一个数组 —— 来源共享身份，绝不复制）。
func gpOffPageLinksList() -> Array[GPOffPageLink]:
	return gpOffPageLinks


# Every open tab as a persistable GPSheet, in tab order.
# 把每个打开的标签页按标签顺序导出为可持久化的 GPSheet。
func gpToSheets() -> Array[GPSheet]:
	var gpOut: Array[GPSheet] = []
	var gpI: int = 0
	for gpTab in gpTabs:
		# Reuse the tab's own GPSheet when present, so sheet-level data (frame size,
		# title block, label mode) survives a save instead of falling back to A3 defaults.
		# 复用标签页自己的 GPSheet（若存在），使图幅/标题栏/语言模式在保存时得以保留，
		# 而非回落成 A3 默认值。
		var gpSheet: GPSheet = gpTab.get("sheet") as GPSheet
		if gpSheet == null:
			gpSheet = GPSheet.new()
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
	# W13: if a canvas is popped out, the window must come home first — the incoming sheets
	# bring their own canvases and the old ones die below.
	# W13：若有画布被摘出，窗口必须先归位 —— 即将载入的图纸自带画布，旧画布在下方释放。
	if _gpPopSheet != GPPaneLayout.GP_EMPTY:
		_gpOnPopClosed()
	for gpTab in gpTabs:
		var gpC: GPCanvas2D = gpTab["canvas"]
		if gpC != null and is_instance_valid(gpC):
			if gpC.get_parent() != null:
				gpC.get_parent().remove_child(gpC)
			gpC.queue_free()
	gpTabs.clear()
	gpTabBar.clear_tabs()
	gpActive = -1
	gpSheetSeq = 0
	# A different project brings a different convention: drop the old shared standard so the
	# first sheet of the incoming file seeds its own (ADR-36).
	# 换了工程就换了约定：丢掉旧的共享标准，让载入文件的第一张图纸播下自己的（ADR-36）。
	gpProjectStandard = null
	# W13: while the sheets stream in, the tab-changed signal must NOT rebind panes — the
	# assignment happens ONCE below (pane i gets sheet i, the ADR-44 default reading order).
	# W13：图纸流入期间，tab 变化信号**不得**重绑窗格 —— 指派在下方**一次性**完成
	#（窗格 i 得到图纸 i，ADR-44 的默认阅读顺序）。
	_gpLoading = true
	_gpPaneSheets = []
	for gpI in range(GPPaneLayout.gpPaneCount(gpLayoutMode)):
		_gpPaneSheets.append(GPPaneLayout.GP_EMPTY)
	for gpS in gpSheets:
		var gpSheet: GPSheet = gpS as GPSheet
		if gpSheet == null:
			continue
		gpSheetSeq += 1
		_gpAddTabWith(gpSheet.gpName, gpSheet.gpId, gpSheet.gpGraph, gpSheet)
	_gpLoading = false
	# Pane i <- sheet i (clamped to the pane count; extra sheets stay reachable via the
	# tab bar / pickers, which is the D2-correct way to see them).
	# 窗格 i <- 图纸 i（收窄到窗格数；多出的图纸经标签栏 / 选择器仍可达 —— 那正是
	# D2 正确的查看方式）。
	for gpI in range(_gpPanes.size()):
		var gpS: int = gpI if gpI < gpTabs.size() else GPPaneLayout.GP_EMPTY
		_gpPaneSheets = GPPaneLayout.gpBind(_gpPaneSheets, gpI, gpS)
		_gpAttachPane(gpI, _gpPaneSheets[gpI])
	_gpActivePane = 0
	_gpSyncActiveTab()
	_gpFillPickers()
	_gpRestylePanes()
	# One final pass: while loading, each tab's list was still incomplete.
	# 最后再推一次：载入过程中每次拿到的列表都还不完整。
	gpSyncProjectGraphs()
	# Sheet numbers and the tab list changed; the off-page flags derive their reference from both.
	# 图号与标签列表都变了；跨图纸旗标正是从这两者推导其交叉编号。
	gpRefreshOffPageContext()
	gpActiveChanged.emit()


# Push a new symbol-definition set to every sheet's canvas (e.g. after exporting
# a custom symbol pack). Also remembered for future sheets.
# 把新的图元定义集推送到每个图纸的画布（如导出自定义图元包后）。同时记录供后续图纸使用。
func gpSetDefs(gpNewDefs: Array[GPSymbolDef]) -> void:
	gpDefs = gpNewDefs
	for gpTab in gpTabs:
		var gpC: GPCanvas2D = gpTab["canvas"]
		gpC.gpDefs = gpNewDefs


# ============================ internal ============================

# The project's numbering standard, created on first use and shared by every tab (ADR-36).
# Installed as each new graph's lazy provider, so the first sheet that numbers something
# establishes the convention and the others inherit exactly that object.
# 工程的编号标准，首次使用时建立并由所有标签页共享（ADR-36）。作为每张新图的惰性来源安装，
# 故第一张需要编号的图纸建立约定，其它图纸继承的正是同一个对象。
func gpProjectStandardOrCreate() -> GPProjectStandard:
	if gpProjectStandard == null:
		gpProjectStandard = GPProjectStandard.gpDefaultStandard()
	return gpProjectStandard


# Push the current tab list into every canvas's tag registry (ADR-36 D6). Uniqueness is then
# judged against the whole project, so sheet 2 can never mint a number sheet 1 already uses.
# 把当前标签页列表推给每个画布的位号注册器（ADR-36 D6）。此后唯一性按整个工程判断，
# 第二张图纸再也不可能铸出第一张已用的号。
# Give a sheet its drawing number (when missing) and fill its empty title-block fields from the
# project info (ADR-38).
# 给图纸分配图号（缺失时），并用项目信息填充其空缺的标题栏字段（ADR-38）。
func _gpEnsureSheetIdentity(gpSheet: GPSheet) -> void:
	if gpSheet == null:
		return
	var gpStd: GPProjectStandard = gpProjectStandard
	if gpStd == null and gpSheet.gpGraph != null:
		gpStd = gpSheet.gpGraph.gpStandard
	if gpStd == null:
		return
	if gpSheet.gpNumber.strip_edges() == "":
		gpSheet.gpAssignNumber(gpStd.gpSheetNumberFor(gpSheet.gpIndex + 1))
	gpSheet.gpApplyProjectInfo(gpStd)


# Tab caption: "<number> <name>" so the drawing number is visible on the sheet's tab — the same
# number the title block prints (.gpstd 图号 only lived in the block before).
# 标签标题：「<编号> <名称>」，使图纸编号在标签页上可见 —— 与标题栏打印的是同一个号
#（此前该号只存在于图签里）。
func _gpTabTitleOf(gpSheet: GPSheet) -> String:
	if gpSheet == null:
		return ""
	var gpName: String = gpSheet.gpName.strip_edges()
	var gpNo: String = gpSheet.gpNumber.strip_edges()
	if gpNo == "":
		return gpName
	if gpName == "":
		return gpNo
	return "%s %s" % [gpNo, gpName]


# Regenerate every sheet's number from tab order (ADR-38). Hand-edited drawing numbers survive
# because gpAssignNumber only overwrites the block while it still shows the previous auto value.
# 按标签顺序重编全部图纸编号（ADR-38）。手改过的图号会保留 —— gpAssignNumber 只在图签仍是
# 上一个自动值时才覆盖。
func gpRenumberSheets() -> void:
	var gpStd: GPProjectStandard = gpProjectStandard
	if gpStd == null:
		return
	var gpI: int = 0
	for gpTabRaw in gpTabs:
		var gpSheet: GPSheet = (gpTabRaw as Dictionary).get("sheet") as GPSheet
		if gpSheet != null:
			gpSheet.gpAssignNumber(gpStd.gpSheetNumberFor(gpI + 1))
			gpSheet.gpApplyProjectInfo(gpStd)
			gpTabBar.set_tab_title(gpI, _gpTabTitleOf(gpSheet))
		gpI += 1
	# Renumbering rewrites the very numbers the off-page flags display.
	# 重编号改写的正是跨图纸旗标所显示的号。
	gpRefreshOffPageContext()


# Apply one project standard to every tab (B: the dialog edits a copy, then hands it over once).
# 把同一套项目标准套用到每个标签页（B：对话框编辑副本，然后一次性交出）。
func gpApplyStandard(gpStd: GPProjectStandard) -> void:
	if gpStd == null:
		return
	gpProjectStandard = gpStd
	var gpI: int = 0
	for gpTabRaw in gpTabs:
		var gpCanvasOne: GPCanvas2D = (gpTabRaw as Dictionary).get("canvas") as GPCanvas2D
		if gpCanvasOne != null:
			gpCanvasOne.gpApplyStandard(gpStd)
		var gpSheetOne: GPSheet = (gpTabRaw as Dictionary).get("sheet") as GPSheet
		if gpSheetOne != null:
			gpSheetOne.gpGraph.gpAdoptStandard(gpStd)
			gpSheetOne.gpIndex = gpI
			_gpEnsureSheetIdentity(gpSheetOne)
			gpTabBar.set_tab_title(gpI, _gpTabTitleOf(gpSheetOne))
		gpI += 1
	# Applying a standard can mint drawing numbers for sheets that had none (see
	# _gpEnsureSheetIdentity), which changes what every off-page flag displays.
	# 套用标准会给原本没有图号的图纸铸号（见 _gpEnsureSheetIdentity），从而改变每个跨图纸旗标显示的内容。
	gpRefreshOffPageContext()


func gpSyncProjectGraphs() -> void:
	var gpGraphs: Array = []
	for gpTabRaw in gpTabs:
		var gpGraphOne: GPPIDGraph = (gpTabRaw as Dictionary).get("graph") as GPPIDGraph
		if gpGraphOne != null:
			gpGraphs.append(gpGraphOne)
	for gpTabRaw in gpTabs:
		var gpCanvasOne: GPCanvas2D = (gpTabRaw as Dictionary).get("canvas") as GPCanvas2D
		if gpCanvasOne != null:
			gpCanvasOne.gpSetProjectGraphs(gpGraphs)


# ============================ 内部方法 ============================
# Create a sheet with the given title and wire it into the tab bar / body.
# 以给定标题创建图纸并接入标签栏 / 画布体。
# [param gpId] stable identity; empty is fine for a brand-new tab (gpToSheets() derives one).
# [param gpId] 稳定标识；全新标签页留空亦可（gpToSheets() 会推导一个）。
# [param gpSheetIn] when non-null the tab adopts THIS sheet's frame/title-block settings.
# [param gpSheetIn] 非 null 时，该标签页沿用**这张图纸**的图框/标题栏设置。
func _gpAddTabWith(gpTitle: String, gpId: String = "", gpGraphIn: GPPIDGraph = null,
		gpSheetIn: GPSheet = null) -> void:
	var gpGraph: GPPIDGraph = gpGraphIn if gpGraphIn != null else GPPIDGraph.new()
	# ADR-36: every tab belongs to the SAME project, so it adopts the project's numbering
	# standard instead of starting from its own factory copy. Without this, every new sheet
	# began handing out P-1001 again — the cross-sheet duplicate that started this task.
	# ADR-36：每个标签页都属于同一个工程，故采纳工程的编号标准，而不是从自己的出厂副本起步。
	# 缺了这一步，每张新图纸都会再从 P-1001 发号 —— 正是引发本任务的跨页重复。
	# When the file carries rules, the first tab seeds the project standard and every later tab
	# adopts it; when it does not, each tab gets the LAZY provider, so the standard is created
	# once (by whoever numbers something first) and shared from then on.
	# 文件带规则时，第一页播下工程标准、后续每页采纳；不带规则时，每页拿到**惰性**来源，
	# 故标准只会被「第一个需要它的页」建立一次，此后共享。
	if gpProjectStandard == null and gpGraph.gpStandard != null:
		gpProjectStandard = gpGraph.gpStandard
	if gpProjectStandard != null:
		gpGraph.gpAdoptStandard(gpProjectStandard)
	else:
		gpGraph.gpStandardProvider = Callable(self, "gpProjectStandardOrCreate")
	var gpSheet: GPSheet = gpSheetIn
	if gpSheet == null:
		gpSheet = GPSheet.gpNew(gpId, gpTitle, gpTabs.size())
	gpSheet.gpGraph = gpGraph
	_gpEnsureSheetIdentity(gpSheet)
	var gpCanvas: GPCanvas2D = GPCanvas2D.new()
	gpCanvas.gpGraph = gpGraph
	gpCanvas.gpDefs = gpDefs
	# Hand the sheet to the canvas so its frame renderer knows the size and title block.
	# 把图纸交给画布，使其图框渲染器知道图幅与标题栏。
	gpCanvas.gpSetSheet(gpSheet)
	# W13 (ADR-44): the canvas is NO longer a hidden child of gpBody waiting for its turn —
	# it lives unparented until a pane (or the pop-out window) takes it. Visibility is the
	# pane's business now.
	# W13（ADR-44）：画布**不再**是 gpBody 下等待轮候的隐藏子节点 —— 在窗格（或摘出窗口）
	# 认领它之前它没有父节点。可见性从此归窗格管。
	var gpTab: Dictionary = {"id": gpId, "title": gpTitle, "graph": gpGraph, "canvas": gpCanvas,
		"sheet": gpSheet}
	gpTabs.append(gpTab)
	gpTabBar.add_tab(_gpTabTitleOf(gpSheet))
	var gpIdx: int = gpTabs.size() - 1
	gpSyncProjectGraphs()
	gpOnCanvasReady.emit(gpCanvas)
	# W13: route the new sheet into the ACTIVE pane via the tab bar (one code path with a
	# user click); during a project load the pane assignment happens once at the end.
	# W13：新图纸经标签栏路由进**活动**窗格（与用户点击同一条路径）；工程载入期间窗格指派
	# 在末尾一次性完成。
	if _gpLoading:
		_gpTabSyncing = true
		gpTabBar.current_tab = gpIdx
		_gpTabSyncing = false
	else:
		gpTabBar.current_tab = gpIdx
	gpActiveChanged.emit()
	# The tab list grew (or a whole project was just loaded): the off-page flags derive their
	# reference from {sheet_id: number}, so the snapshot must follow every change to it.
	# 标签列表增长（或整个工程刚载入）：跨图纸旗标从 {sheet_id: 图号} 推导其交叉编号，
	# 故快照必须跟随它的每一次变化。
	gpRefreshOffPageContext()


# ==================== W13 multi-view layout (ADR-44) ====================
# ==================== W13 多视图布局（ADR-44）====================

# Switch the layout mode. Only the MODE persists (Settings); the pane<->sheet bindings are
# session state, rebuilt around the SAME canvas instances (ADR-44 D1: no view node is ever
# recreated by a layout switch).
# 切换布局模式。只有**模式**持久化（Settings）；窗格与图纸的绑定是会话状态，围绕**同一批**
# 画布实例重建（ADR-44 D1：切换布局绝不重建任何视图节点）。
func gpSetLayoutMode(gpMode: int) -> void:
	if not GPPaneLayout.gpIsValid(gpMode) or gpMode == gpLayoutMode:
		return
	gpLayoutMode = gpMode
	Settings.gpLayoutMode = gpMode
	Settings.gpSave()
	_gpRebuildLayout()
	# D22: the four header buttons are a RADIO GROUP — the current mode stays visually
	# pressed so the mode is readable without text.
	# D22：头部四按钮是一组**单选** —— 当前模式保持视觉按下态，无文字也能读出模式。
	_gpSyncLayoutButtons()


# Keep the layout buttons' pressed state in step with gpLayoutMode.
# 使布局按钮的按下态与 gpLayoutMode 保持一致。
func _gpSyncLayoutButtons() -> void:
	for gpBtn in gpLayoutButtons:
		gpBtn.set_pressed_no_signal(int(gpBtn.get_meta("gp_layout_mode", 0)) == gpLayoutMode)


# Tear the old pane tree down (detaching — never freeing — the canvases) and build the new
# one around the same instances.
# 拆除旧窗格树（只**摘下**、绝不释放画布），围绕同一批实例建新的。
func _gpRebuildLayout() -> void:
	var gpKeep: int = gpActive
	for gpP in _gpPanes:
		if is_instance_valid(gpP):
			gpP.gpDetachCanvas()
	if _gpLayoutRoot != null and is_instance_valid(_gpLayoutRoot):
		for gpC in _gpLayoutRoot.get_children():
			_gpLayoutRoot.remove_child(gpC)
			gpC.queue_free()
	_gpPanes.clear()
	var gpCount: int = GPPaneLayout.gpPaneCount(gpLayoutMode)
	_gpPaneSheets = GPPaneLayout.gpResized(_gpPaneSheets, gpCount, gpKeep)
	# Same refill contract as closing a tab: no sheet may vanish from view while a pane
	# seat exists — gpResized alone can leave orphan bindings when the mode shrinks, and
	# a blank pane next to an invisible sheet reads exactly like the reported "blank
	# canvas after a layout switch". The popped-out sheet stays excluded (the window and
	# a pane would fight over the same canvas).
	# 与关签同一份回填契约：只要还有窗格座位，就不许有图纸从视野里消失 —— 模式收窄时
	# 仅 gpResized 会留下孤儿绑定，「空窗格 + 不可见图纸」读起来正是用户报告的
	# 「切换布局后画布空白」。已摘出的图纸照旧排除（窗口与窗格会争抢同一块画布）。
	_gpPaneSheets = GPPaneLayout.gpRefill(_gpPaneSheets, gpTabs.size(), _gpPopSheet)
	_gpBuildLayoutTree(gpLayoutMode)
	_gpActivePane = clampi(_gpActivePane, 0, gpCount - 1)
	for gpI in range(_gpPanes.size()):
		_gpAttachPane(gpI, _gpPaneSheets[gpI])
	_gpSyncActiveTab()
	_gpFillPickers()
	_gpRestylePanes()


# The pane tree per mode (ADR-44 D1: nested SPLIT containers — a GridContainer has no
# draggable dividers, which the plan requires).
# 每种模式的窗格树（ADR-44 D1：嵌套 **split** 容器 —— GridContainer 没有可拖动的分隔条，
# 而这是方案的硬要求）。
# ⚠️ The layout root is a PLAIN Control, and a plain Control does NOT manage its children's
# rects — size flags are ignored there. The TOP node of every mode must therefore anchor
# itself to the full rect, or the whole pane tree collapses to its minimum size (one
# 56×22 header strip with a dark void below): the reported "blank canvas after a layout
# switch". Deeper nodes live inside split Containers, where size flags DO work.
# ⚠️ 布局根是**普通** Control，而普通 Control **不**管理子节点矩形 —— size flags 在此被无视。
# 故每种模式的**顶层**节点必须自行锚定满矩形，否则整棵窗格树塌缩到最小尺寸（只剩一条
# 56×22 的头部细条、下方一片黑）：即用户报告的「切换布局后画布空白」。更深层节点住在
# split 容器里，size flags 在那里才生效。
func _gpBuildLayoutTree(gpMode: int) -> void:
	var gpTop: Control = null
	match gpMode:
		GPPaneLayout.GP_SINGLE:
			gpTop = _gpMakePane()
		GPPaneLayout.GP_SIDE:
			var gpSplit: HSplitContainer = HSplitContainer.new()
			gpSplit.size_flags_horizontal = SIZE_EXPAND_FILL
			gpSplit.size_flags_vertical = SIZE_EXPAND_FILL
			gpSplit.add_child(_gpMakePane())
			gpSplit.add_child(_gpMakePane())
			gpTop = gpSplit
		GPPaneLayout.GP_BIG2:
			# One large pane + two stacked small ones (the plan's "1 big, 2 usable small").
			# 一大窗格 + 上下两小格（方案里的「1 大 2 小可用」）。
			var gpSplit: HSplitContainer = HSplitContainer.new()
			gpSplit.size_flags_horizontal = SIZE_EXPAND_FILL
			gpSplit.size_flags_vertical = SIZE_EXPAND_FILL
			gpSplit.add_child(_gpMakePane())
			var gpRight: VSplitContainer = VSplitContainer.new()
			gpRight.size_flags_horizontal = SIZE_EXPAND_FILL
			gpRight.size_flags_vertical = SIZE_EXPAND_FILL
			gpRight.add_child(_gpMakePane())
			gpRight.add_child(_gpMakePane())
			gpSplit.add_child(gpRight)
			gpTop = gpSplit
		GPPaneLayout.GP_GRID:
			var gpSplit: HSplitContainer = HSplitContainer.new()
			gpSplit.size_flags_horizontal = SIZE_EXPAND_FILL
			gpSplit.size_flags_vertical = SIZE_EXPAND_FILL
			var gpTopHalf: VSplitContainer = VSplitContainer.new()
			var gpBottom: VSplitContainer = VSplitContainer.new()
			for gpHalf: VSplitContainer in [gpTopHalf, gpBottom]:
				gpHalf.size_flags_horizontal = SIZE_EXPAND_FILL
				gpHalf.size_flags_vertical = SIZE_EXPAND_FILL
				gpHalf.add_child(_gpMakePane())
				gpHalf.add_child(_gpMakePane())
			gpSplit.add_child(gpTopHalf)
			gpSplit.add_child(gpBottom)
			gpTop = gpSplit
	if gpTop != null:
		_gpLayoutRoot.add_child(gpTop)
		gpTop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# One pane, wired to the center area's handlers.
# 一个窗格，接好中间区的各处理器。
func _gpMakePane() -> GPCanvasPane:
	var gpPane: GPCanvasPane = GPCanvasPane.new()
	gpPane.gpSheetPicked.connect(_gpOnPanePick)
	gpPane.gpPaneFocused.connect(_gpOnPaneFocused)
	gpPane.gpPopoutRequested.connect(gpPopoutPane)
	_gpPanes.append(gpPane)
	return gpPane


# Bind pane gpPaneIdx to sheet tab gpSheetIdx (GP_EMPTY = detach only). The canvas keeps its
# whole view state — reparenting must not reset a single scroll or zoom.
# 把窗格 gpPaneIdx 绑到图纸标签 gpSheetIdx（GP_EMPTY = 仅摘下）。画布保留全部视图状态 ——
# reparent 不许弄丢任何滚转或缩放。
func _gpAttachPane(gpPaneIdx: int, gpSheetIdx: int) -> void:
	if gpPaneIdx < 0 or gpPaneIdx >= _gpPanes.size():
		return
	var gpCv: GPCanvas2D = _gpCanvasOfTab(gpSheetIdx)
	# D02 guard (second order): a canvas living in the pop-out window must NEVER be
	# re-parented into a pane. The bind level routes popped sheets to _gpFocusPopout(),
	# so reaching here means some caller bypassed it — refuse instead of stealing
	# (add_child would auto-reparent the canvas OUT of the window).
	# D02 守卫（二阶）：住在摘出窗口里的画布**绝不**被抢进窗格。绑定层已把已摘出的图纸
	# 路由到 _gpFocusPopout()，走到这里说明有调用方绕过了它 —— 拒绝而非抢夺
	#（add_child 会把画布自动 reparent **出**窗口）。
	if gpCv != null and _gpPopWin != null and is_instance_valid(_gpPopWin) \
			and gpCv.get_parent() == _gpPopWin:
		return
	var gpPane: GPCanvasPane = _gpPanes[gpPaneIdx]
	gpPane.gpAttachCanvas(gpCv)
	gpPane.gpSheetIdx = gpSheetIdx


# The canvas of sheet tab gpS (null when out of range or empty).
# 图纸标签 gpS 的画布（越界或空时为 null）。
func _gpCanvasOfTab(gpS: int) -> GPCanvas2D:
	if gpS < 0 or gpS >= gpTabs.size():
		return null
	return gpTabs[gpS]["canvas"] as GPCanvas2D


# Show sheet gpTabIdx in the ACTIVE pane (the tab bar's and gpAddTab's intent). This replaces
# the old stack-only _gpShowOnly: in every mode "switching sheets" means "rebind the active
# pane", and the uniqueness invariant empties whatever other pane showed it.
# 在**活动**窗格中显示图纸 gpTabIdx（标签栏与 gpAddTab 的意图）。它取代旧的单窗 _gpShowOnly：
# 在任何模式下「切换图纸」都意味着「重绑活动窗格」，唯一性不变量会清空其它显示它的窗格。
# Returns true when the request was CONSUMED by the pop-out route (the caller must not emit
# gpActiveChanged again — _gpFocusPopout already did); false when a normal bind happened.
# 请求被摘出路由**消费**时返回 true（调用方不得再发 gpActiveChanged —— _gpFocusPopout 已发过）；
# 发生普通绑定时返回 false。
func _gpBindActivePane(gpTabIdx: int) -> bool:
	if gpTabIdx < 0 or gpTabIdx >= gpTabs.size():
		gpActive = -1
		return false
	# D02 (the choke point): activating the POPPED-OUT sheet must FOCUS the window, never
	# rebind — a bind+attach would reparent the canvas out of the window (add_child auto-
	# reparent), leaving the window empty while _gpPopSheet still points at it (and a later
	# close would steal the canvas from whatever pane took it). EVERY activation route —
	# tab click, DRC jump, jump-to-peer — funnels through here.
	# D02（收口点）：激活**已摘出**的图纸必须**聚焦窗口**而绝不重绑 —— 绑定+挂载会把画布
	# 抢出窗口（add_child 自动 reparent），窗口空着而 _gpPopSheet 仍指着它（且此后关窗会
	# 从收留它的窗格里把画布再抢走）。**所有**激活路径 —— 标签点击、DRC 跳转、跳转到对端
	# —— 都汇入此处。
	if gpTabIdx == _gpPopSheet:
		_gpFocusPopout()
		return true
	_gpPaneSheets = GPPaneLayout.gpBind(_gpPaneSheets, _gpActivePane, gpTabIdx)
	_gpAttachPane(_gpActivePane, gpTabIdx)
	gpActive = gpTabIdx
	_gpFillPickers()
	_gpRestylePanes()
	return false


# A pane's canvas gained focus (ADR-44 D4): THIS pane becomes the one the docks serve. If its
# sheet differs from the current active tab, the active tab follows — the tab bar selection
# is kept in sync WITHOUT re-triggering the binding (the sheet is already where it belongs).
# 某窗格的画布获得焦点（ADR-44 D4）：**本窗格**成为侧栏服务的窗格。若其图纸与当前活动标签
# 不同，活动标签跟随 —— 标签栏选择被同步，但**不**重新触发绑定（图纸已经在它该在的地方）。
func _gpOnPaneFocused(gpPane: GPCanvasPane) -> void:
	var gpIdx: int = _gpPanes.find(gpPane)
	if gpIdx < 0:
		return
	_gpActivePane = gpIdx
	_gpRestylePanes()
	var gpS: int = _gpPaneSheets[gpIdx]
	if gpS != gpActive and gpS >= 0:
		gpActive = gpS
		_gpTabSyncing = true
		gpTabBar.current_tab = gpS
		_gpTabSyncing = false
		gpActiveChanged.emit()


# A pane's picker chose a sheet: rebind THIS pane (the uniqueness invariant empties the pane
# that showed it before), and make the pane active — the user just aimed at it.
# 某窗格的选择器选定了图纸：重绑**本窗格**（唯一性不变量会清空原先显示它的窗格），并把它
# 设为活动窗格 —— 用户刚刚瞄准了它。
func _gpOnPanePick(gpPane: GPCanvasPane, gpSheetIdx: int) -> void:
	var gpIdx: int = _gpPanes.find(gpPane)
	if gpIdx < 0 or gpSheetIdx < 0 or gpSheetIdx >= gpTabs.size():
		return
	_gpActivePane = gpIdx
	_gpPaneSheets = GPPaneLayout.gpBind(_gpPaneSheets, gpIdx, gpSheetIdx)
	_gpAttachPane(gpIdx, gpSheetIdx)
	gpActive = gpSheetIdx
	_gpTabSyncing = true
	gpTabBar.current_tab = gpSheetIdx
	_gpTabSyncing = false
	_gpFillPickers()
	_gpRestylePanes()
	gpActiveChanged.emit()


# Keep the ACTIVE TAB in step with the active pane's sheet (called from the layout engine).
# 让**活动标签**跟随活动窗格的图纸（由布局引擎调用）。
func _gpSyncActiveTab() -> void:
	var gpS: int = _gpPaneSheets[_gpActivePane] if _gpActivePane < _gpPaneSheets.size() \
		else GPPaneLayout.GP_EMPTY
	var gpOld: int = gpActive
	gpActive = gpS
	if gpS >= 0 and gpTabBar.current_tab != gpS:
		_gpTabSyncing = true
		gpTabBar.current_tab = gpS
		_gpTabSyncing = false
	# D04: a layout switch can silently rewrite gpActive — the docks (inspector, toolbar,
	# menus) follow gpActiveChanged, so a silent change would leave them editing a sheet
	# that is no longer visible. Emit exactly when the active sheet actually moved.
	# D04：切换布局会静默改写 gpActive —— 侧栏（属性面板/工具栏/菜单）跟随
	# gpActiveChanged，不发信号它们就会继续编辑一张已经不可见的图纸。活动页确实移动时
	# 恰好发一次。
	if gpActive != gpOld:
		gpActiveChanged.emit()


# Accent underline on the active pane only.
# 仅活动窗格佩戴 accent 底线。
func _gpRestylePanes() -> void:
	for gpI in range(_gpPanes.size()):
		_gpPanes[gpI].gpActive = (gpI == _gpActivePane)


# The picker of every pane: all sheets, own entry selected, entries held by OTHER panes (or
# living in the pop-out window) disabled — the D2 invariant made visible.
# 每个窗格的选择器：列出全部图纸，选中自己的，被**其它**窗格占用（或已在摘出窗口中）的
# 条目禁用 —— 让 D2 不变量可见。
func _gpFillPickers() -> void:
	for gpI in range(_gpPanes.size()):
		var gpPane: GPCanvasPane = _gpPanes[gpI]
		gpPane.gpPick.clear()
		var gpSel: int = -1
		for gpS in range(gpTabs.size()):
			var gpTitle: String = str(gpTabs[gpS].get("title", ""))
			gpPane.gpPick.add_item(gpTitle)
			if gpS == gpPane.gpSheetIdx:
				gpSel = gpS
			# Another pane's sheet (or the popped-out one) is not bindable here.
			# 其它窗格的图纸（或已摘出的那张）在此不可绑定。
			if _gpPaneSheets.has(gpS) and gpS != gpPane.gpSheetIdx:
				gpPane.gpPick.set_item_disabled(gpPane.gpPick.item_count - 1, true)
			elif gpS == _gpPopSheet:
				gpPane.gpPick.set_item_disabled(gpPane.gpPick.item_count - 1, true)
		if gpSel >= 0:
			gpPane.gpPick.select(gpSel)


# The canvas under a GLOBAL point, for cross-pane gestures (W13-S8 drag-to-connect). The
# popped-out window counts too — it is as much a view of a sheet as any pane.
# 全局点下的画布，供跨窗格手势使用（W13-S8 拖拽连线）。摘出窗口同样算数 —— 它与任何窗格
# 一样是某张图纸的一个视图。
func gpCanvasAtGlobalPoint(gpGlobal: Vector2) -> GPCanvas2D:
	for gpP in _gpPanes:
		var gpCv: GPCanvas2D = gpP.gpCanvas()
		if gpCv != null and gpCv.get_global_rect().has_point(gpGlobal):
			return gpCv
	if _gpPopWin != null and is_instance_valid(_gpPopWin) and _gpPopSheet >= 0:
		var gpCv: GPCanvas2D = _gpCanvasOfTab(_gpPopSheet)
		if gpCv != null and gpCv.get_global_rect().has_point(gpGlobal):
			return gpCv
	return null


# ---- pop-out (W13-S7, ADR-44 D3: EMBEDDED window — one code path on every platform) ----
# ---- 摘出（W13-S7，ADR-44 D3：**嵌入式**窗口 —— 所有平台同一条代码路径）----

# Pop the pane's canvas out into an embedded Window. The pane goes empty (the picker stays
# honest by disabling the popped sheet); closing the window returns the canvas HERE first.
# 把窗格画布摘出到嵌入式 Window。窗格变空（选择器禁用已摘出的图纸以保持诚实）；
# 关闭窗口时画布优先归位**此处**。
func gpPopoutPane(gpPane: GPCanvasPane) -> void:
	var gpIdx: int = _gpPanes.find(gpPane)
	if gpIdx < 0 or _gpPopSheet != GPPaneLayout.GP_EMPTY:
		return
	var gpSheetIdx: int = _gpPaneSheets[gpIdx]
	var gpCv: GPCanvas2D = gpPane.gpDetachCanvas()
	if gpCv == null:
		return
	_gpPopPane = gpIdx
	_gpPopSheet = gpSheetIdx
	_gpPaneSheets[gpIdx] = GPPaneLayout.GP_EMPTY
	gpPane.gpSheetIdx = GPPaneLayout.GP_EMPTY
	if _gpPopWin == null or not is_instance_valid(_gpPopWin):
		_gpPopWin = Window.new()
		# The window hosts ONLY the canvas (ADR-44 D3): no menus, no docks — the main window
		# keeps every tool and all context.
		# 窗口只承载画布（ADR-44 D3）：无菜单、无停靠栏 —— 主窗保留全部工具与上下文。
		_gpPopWin.close_requested.connect(_gpOnPopClosed)
		_gpPopWin.min_size = Vector2i(480, 320)
		add_child(_gpPopWin)
	_gpPopWin.title = str(gpTabs[gpSheetIdx].get("title", ""))
	_gpPopWin.add_child(gpCv)
	gpCv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A click inside the popup must still make its sheet the ACTIVE one (the docks serve it),
	# even though the canvas no longer sits in a pane.
	# 弹窗内点击仍须使其图纸成为**活动**图纸（侧栏服务它），尽管画布已不在窗格中。
	if not gpCv.focus_entered.is_connected(_gpOnPopFocused):
		gpCv.focus_entered.connect(_gpOnPopFocused)
	_gpPopWin.popup_centered(Vector2i(960, 640))
	_gpFillPickers()


# B1/D02: THE single "focus the popped-out sheet" path — the window is raised, the sheet
# becomes the active tab (NO rebind: the canvas lives in the window, not in a pane). Both
# the canvas focus signal and the programmatic activation routes land here, so the
# "focus popup" semantics can never be written twice.
# B1/D02：**唯一**的「聚焦已摘出图纸」路径 —— 窗口置顶，该图纸成为活动标签（**不**重绑：
# 画布住在窗口里，不在窗格中）。画布焦点信号与程序性激活路径都落到这里，「聚焦弹窗」
# 的语义不可能被写第二遍。
func _gpFocusPopout() -> void:
	if _gpPopSheet < 0 or _gpPopSheet >= gpTabs.size():
		return
	if _gpPopWin != null and is_instance_valid(_gpPopWin):
		if not _gpPopWin.visible:
			# Defensive: a hidden window with a live pop state is the D01 bug shape —
			# recover by showing it instead of leaving the sheet invisible.
			# 防御：隐藏着的窗口却带着活弹窗状态正是 D01 的病灶形状 —— 重新显示以自愈，
			# 而不是让图纸不可见。
			_gpPopWin.show()
		_gpPopWin.move_to_foreground()
	var gpOld: int = gpActive
	gpActive = _gpPopSheet
	if gpActive != gpOld:
		_gpTabSyncing = true
		gpTabBar.current_tab = _gpPopSheet
		_gpTabSyncing = false
		gpActiveChanged.emit()


# The popped-out canvas gained focus: route through the SINGLE popout-focus path (B1).
# 被摘出的画布获得焦点：经**唯一**的弹窗聚焦路径转发（B1）。
func _gpOnPopFocused() -> void:
	_gpFocusPopout()


# The pop-out window closed: return the canvas to its preferential pane (the one that popped
# it; if the layout changed meanwhile, the first pane that can take it). The sheet is NOT
# shown anywhere else in the meantime, so the bind cannot violate D2.
# 摘出窗口被关闭：画布归位到优先窗格（摘出它的那个；期间布局若变过，则退而求第一个能收的
# 窗格）。期间该图纸未在别处显示，故绑定不可能违反 D2。
func _gpOnPopClosed() -> void:
	if _gpPopSheet == GPPaneLayout.GP_EMPTY:
		return
	var gpCv: GPCanvas2D = _gpCanvasOfTab(_gpPopSheet)
	var gpSheetIdx: int = _gpPopSheet
	if _gpPopWin != null and is_instance_valid(_gpPopWin) and gpCv != null \
			and gpCv.get_parent() == _gpPopWin:
		_gpPopWin.remove_child(gpCv)
	# The focus route back into the popup handler must die with the popup state.
	# 指回弹窗处理器的焦点路由必须随弹窗状态一同消亡。
	if gpCv != null and gpCv.focus_entered.is_connected(_gpOnPopFocused):
		gpCv.focus_entered.disconnect(_gpOnPopFocused)
	_gpPopSheet = GPPaneLayout.GP_EMPTY
	if gpCv == null:
		_gpFillPickers()
		return
	var gpHome: int = _gpPopPane if _gpPopPane < _gpPanes.size() else 0
	_gpPaneSheets = GPPaneLayout.gpBind(_gpPaneSheets, gpHome, gpSheetIdx)
	_gpAttachPane(gpHome, gpSheetIdx)
	if _gpActivePane == gpHome and gpActive != gpSheetIdx:
		gpActive = gpSheetIdx
		_gpTabSyncing = true
		gpTabBar.current_tab = gpSheetIdx
		_gpTabSyncing = false
		gpActiveChanged.emit()
	_gpFillPickers()
	_gpRestylePanes()
	# D01: close_requested does NOT close the window automatically (Godot 4.7 docs) —
	# without an explicit hide() the window lingers as an empty shell the user can never
	# dismiss (the reported "关不掉的空窗").
	# D01：close_requested 不会自动关窗（Godot 4.7 文档）—— 不显式 hide() 窗口就以空壳
	# 形式留在屏幕上且永远关不掉（即报告的「关不掉的空窗」）。
	if _gpPopWin != null and is_instance_valid(_gpPopWin):
		_gpPopWin.hide()


# Active tab changed via the tab bar (a click, or a programmatic sync): show that sheet in
# the ACTIVE pane and notify the host.
# 通过标签栏切换活动页（点击或程序同步）：在**活动**窗格中显示该图纸并通知宿主。
func _gpOnTabChanged(gpIdx: int) -> void:
	if _gpTabSyncing or _gpLoading:
		return
	if gpIdx < 0 or gpIdx >= gpTabs.size():
		return
	# D02: the pop-out route emits inside _gpFocusPopout — consuming here avoids a double
	# gpActiveChanged.
	# D02：摘出路由在 _gpFocusPopout 内部发信号 —— 在此消费，避免 gpActiveChanged 发两次。
	if _gpBindActivePane(gpIdx):
		return
	gpActiveChanged.emit()


# A tab's close button was pressed: drop that sheet (never close the last one).
# 某标签页关闭按钮被按下：移除该图纸（永不关闭最后一张）。
func _gpOnTabClose(gpIdx: int) -> void:
	if gpTabs.size() <= 1:
		return
	var gpTab: Dictionary = gpTabs[gpIdx]
	var gpC: GPCanvas2D = gpTab["canvas"]
	# ADR-43 / S4 deletion case ③: closing a sheet invalidates every link ending on it.
	# NEVER silently — list the affected links, get an explicit confirmation, delete the
	# links, then close. The PEER connectors survive (their flags will show "?" and the
	# unpaired rule reports the repair), because the peer drawing must not lose objects
	# out from under the user.
	# ADR-43 / S4 删除情形③：关闭图纸会让落在其上的每条 link 失效。**绝不静默** ——
	# 列出受影响连接、取得明确确认、删除这些 link，然后关签。**对端连接符保留**
	#（旗标显示 "？"，unpaired 规则提示修复）—— 不能让对端图纸上的对象凭空消失。
	var gpSheetId: String = gpC.gpSheet.gpId if gpC.gpSheet != null else ""
	var gpAffected: Array[GPOffPageLink] = []
	for gpL in gpOffPageLinks:
		if gpL == null:
			continue
		if str(gpL.gpA.get(GPOffPageLink.GP_KEY_SHEET, "")) == gpSheetId \
				or str(gpL.gpB.get(GPOffPageLink.GP_KEY_SHEET, "")) == gpSheetId:
			gpAffected.append(gpL)
	if gpAffected.size() > 0:
		_gpConfirmSheetClose(gpIdx, gpAffected)
		return
	_gpCloseTabNow(gpIdx)


# The confirmation for case ③: one line per affected link; only an explicit OK deletes them.
# 情形③的确认框：每条受影响 link 一行；只有明确的「确定」才删除。
func _gpConfirmSheetClose(gpIdx: int, gpAffected: Array[GPOffPageLink]) -> void:
	var gpLines: String = ""
	for gpL in gpAffected:
		var gpTag: String = gpL.gpTag if gpL.gpTag != "" else gpL.gpInstanceId
		var gpPeerId: String = str(gpL.gpB.get(GPOffPageLink.GP_KEY_SHEET, ""))
		if str(gpL.gpB.get(GPOffPageLink.GP_KEY_SHEET, "")) == _gpSheetIdAt(gpIdx):
			gpPeerId = str(gpL.gpA.get(GPOffPageLink.GP_KEY_SHEET, ""))
		gpLines += I18n.gpTr("offpage.del_line") % [gpTag,
			I18n.gpTr("offpage.peer_sheet") % _gpSheetLabelOf(gpPeerId)] + "\n"
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("offpage.close_title")
	gpDlg.dialog_text = I18n.gpTr("offpage.close_text") % [gpLines.strip_edges()]
	gpDlg.ok_button_text = I18n.gpTr("dialog.ok")
	gpDlg.cancel_button_text = I18n.gpTr("dialog.cancel")
	add_child(gpDlg)
	gpDlg.confirmed.connect(func() -> void:
		for gpL in gpAffected:
			gpOffPageLinks.erase(gpL)
		gpRefreshOffPageContext()
		_gpCloseTabNow(gpIdx)
		gpDlg.queue_free())
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.popup_centered()


# The sheet id of the tab at gpIdx ("" when out of range).
# 下标 gpIdx 处标签页的图纸 id（越界为 ""）。
func _gpSheetIdAt(gpIdx: int) -> String:
	if gpIdx < 0 or gpIdx >= gpTabs.size():
		return ""
	var gpC: GPCanvas2D = gpTabs[gpIdx]["canvas"] as GPCanvas2D
	return gpC.gpSheet.gpId if gpC.gpSheet != null else ""


# A human label for a sheet id: its tab name (the number rides the name's prefix); a missing
# sheet degrades to "?" — honest, like the flags.
# 图纸 id 的人类标签：标签名（图号含在名字里）；找不到时降级为 "？" —— 与旗标一样诚实。
func _gpSheetLabelOf(gpSheetId: String) -> String:
	for gpI in range(gpTabs.size()):
		if _gpSheetIdAt(gpI) == gpSheetId:
			return str(gpTabs[gpI].get("title", gpSheetId))
	return GPOffPageIndex.GP_UNRESOLVED_TEXT


func _gpCloseTabNow(gpIdx: int) -> void:
	var gpTab: Dictionary = gpTabs[gpIdx]
	var gpC: GPCanvas2D = gpTab["canvas"]
	# W13: the canvas may live in a pane host or in the pop-out window — detach from wherever
	# it actually is. If THIS sheet was the popped-out one, drop the window with it.
	# W13：画布可能住在窗格承载区或摘出窗口里 —— 从**实际所在处**摘下。若被关的正是
	# 已摘出的那张，窗口随之撤下。
	if _gpPopSheet == gpIdx and _gpPopWin != null and is_instance_valid(_gpPopWin):
		_gpPopWin.remove_child(gpC)
		_gpPopSheet = GPPaneLayout.GP_EMPTY
		# D01: the closed sheet WAS the popped one — hide the window too, or it lingers.
		# D01：被关的正是已摘出的那张 —— 窗口也要随之隐藏，否则留在屏幕上。
		_gpPopWin.hide()
	if gpC.get_parent() != null:
		gpC.get_parent().remove_child(gpC)
	gpC.queue_free()
	gpTabs.remove_at(gpIdx)
	gpTabBar.remove_tab(gpIdx)
	# Keep the binding invariant: panes that showed this sheet go empty, later sheets shift
	# down one slot, then the empty panes refill from the sheets nothing shows.
	# 保持绑定不变量：显示该图纸的窗格变空，其后的图纸整体前移一位，空窗格再从「无人显示的
	# 图纸」里回填。
	_gpPaneSheets = GPPaneLayout.gpAfterTabRemoved(_gpPaneSheets, gpIdx)
	_gpPaneSheets = GPPaneLayout.gpRefill(_gpPaneSheets, gpTabs.size(), _gpPopSheet)
	for gpI in range(_gpPanes.size()):
		_gpAttachPane(gpI, _gpPaneSheets[gpI])
	var gpNew: int = mini(gpIdx, gpTabs.size() - 1)
	# Prefer to keep the ACTIVE PANE showing something sensible; the tab bar follows it.
	# 优先让**活动窗格**显示合理内容；标签栏跟随它。
	# (Renamed gpActiveSheet -> gpPaneSheet: the old name shadowed the _gpActiveSheet()
	# method and read as "the active sheet", which it is not — it is the sheet bound to
	# the active pane. / 旧名遮蔽了 _gpActiveSheet() 方法且语义误导——它是活动**窗格**绑的图纸。)
	var gpPaneSheet: int = _gpPaneSheets[_gpActivePane] \
		if _gpActivePane < _gpPaneSheets.size() else GPPaneLayout.GP_EMPTY
	if gpPaneSheet < 0 and gpTabs.size() > 0:
		_gpPaneSheets = GPPaneLayout.gpBind(_gpPaneSheets, _gpActivePane, gpNew)
		_gpAttachPane(_gpActivePane, gpNew)
		gpPaneSheet = gpNew
	gpActive = gpPaneSheet
	if gpPaneSheet >= 0:
		_gpTabSyncing = true
		gpTabBar.current_tab = gpPaneSheet
		_gpTabSyncing = false
	gpSyncProjectGraphs()
	# Closing a sheet shifts every later tab's fallback number and, in S4, invalidates the links
	# that ended on it — republish now so the surviving flags stop pointing into nothing.
	# 关闭一张图纸会改变其后所有标签的回落编号，且在 S4 中会让落在该图上的 link 失效 ——
	# 立即重新发布，使存活的旗标不再指向空处。
	gpRefreshOffPageContext()
	_gpFillPickers()
	_gpRestylePanes()
	gpActiveChanged.emit()


# Fullscreen toggle: remember state, relabel the button, and forward to the host.
# 全屏切换：记录状态、重设按钮文字，并转发给宿主。
func _gpOnFullscreenToggle(gpOn: bool) -> void:
	gpFullscreen = gpOn
	if gpFullBtn != null:
		# Icon-only button: state lives in the accent plate; only the tooltip changes.
		# 纯图标按钮：状态由 accent 色块承载；仅提示语随状态变化。
		gpFullBtn.tooltip_text = I18n.gpTr("center.fullscreen_exit") if gpOn else I18n.gpTr("center.fullscreen_tip")
	gpFullscreenToggled.emit(gpOn)


# Locale changed: refresh the static header button labels.
# 语言变化：刷新头部静态按钮文字。
func _gpOnLocale(_gpLocale: String) -> void:
	# Titles are user-facing sheet names; keep them. Only refresh the button labels.
	# 标题是用户可见的图纸名，保持不变；仅刷新按钮文字。
	if gpFullBtn != null:
		gpFullBtn.tooltip_text = I18n.gpTr("center.fullscreen_exit") if gpFullscreen else I18n.gpTr("center.fullscreen_tip")


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

# ======================= inline tab rename (double-click) =======================
# ======================= 行内标签重命名（双击）=======================
# A double click on the tab band starts an inline LineEdit over the clicked tab.
# Enter commits, Escape or focus loss cancels; the rename updates the tab title,
# the sheet record AND the GPSheet name so it survives a save/reload.
# 双击标签带即在对应标签上启动行内 LineEdit。回车提交、Esc 或失焦取消；重命名同时
# 更新标签标题、图纸记录与 GPSheet 名称，保存/重载后仍保留。
func _gpOnTabBarInput(gpEvent: InputEvent) -> void:
	# GDScript does not narrow the `is` operand inside a compound condition, so cast once
	# first — this also removes the UNSAFE_PROPERTY_ACCESS warnings.
	# GDScript 不会在复合条件里收窄 `is` 的操作数类型，所以先做一次 cast —— 同时消除
	# UNSAFE_PROPERTY_ACCESS 警告。
	var gpMb: InputEventMouseButton = gpEvent as InputEventMouseButton
	if gpMb != null and gpMb.pressed and gpMb.double_click \
			and gpMb.button_index == MOUSE_BUTTON_LEFT:
		var gpIdx: int = gpTabBar.get_tab_idx_at_point(gpTabBar.get_local_mouse_position())
		if gpIdx >= 0:
			_gpBeginRename(gpIdx)


# Show the rename editor over the tab at gpIdx.
# 在 gpIdx 处的标签上显示重命名编辑器。
func _gpBeginRename(gpIdx: int) -> void:
	if gpIdx < 0 or gpIdx >= gpTabs.size():
		return
	_gpEndRename(true)
	_gpRenameIdx = gpIdx
	if _gpRenameEdit == null:
		_gpRenameEdit = LineEdit.new()
		# Top-level: floats over the tab band; containers skip top-level children.
		# top-level：悬浮于标签带之上；容器会跳过 top-level 子节点。
		_gpRenameEdit.set_as_top_level(true)
		_gpRenameEdit.visible = false
		_gpRenameEdit.text_submitted.connect(_gpOnRenameSubmitted)
		_gpRenameEdit.gui_input.connect(_gpOnRenameGuiInput)
		_gpRenameEdit.focus_exited.connect(_gpEndRename.bind(true))
		add_child(_gpRenameEdit)
	_gpRenameEdit.text = str(gpTabs[gpIdx]["title"])
	var gpTabRect: Rect2 = gpTabBar.get_tab_rect(gpIdx)
	_gpRenameEdit.global_position = gpTabBar.get_global_rect().position + gpTabRect.position + Vector2(0.0, 1.0)
	# Never narrower than 80px: a freshly created "P&ID 1" tab is tiny but must stay editable.
	# 不得窄于 80px：新建的「P&ID 1」标签很小，但必须可编辑。
	_gpRenameEdit.size = Vector2(maxf(gpTabRect.size.x, 80.0), gpTabRect.size.y - 2.0)
	_gpRenameEdit.visible = true
	_gpRenameEdit.grab_focus()
	_gpRenameEdit.select_all()


# While the editor is open, Escape cancels the rename (commits nothing).
# 编辑器打开期间，Esc 取消重命名（不提交）。
func _gpOnRenameGuiInput(gpEvent: InputEvent) -> void:
	# Same narrowing rule as _gpOnTabBarInput. / 与 _gpOnTabBarInput 同一条收窄规则。
	var gpKey: InputEventKey = gpEvent as InputEventKey
	if gpKey != null and gpKey.pressed and gpKey.keycode == KEY_ESCAPE:
		_gpEndRename(false)


# Enter was pressed inside the editor: commit and close.
# 编辑器内按下回车：提交并关闭。
# ⚠️ MUST pass _gpRenameIdx: the default (-1) makes _gpCommitRename bail out early,
# so the rename silently did NOTHING (the reported "display name doesn't change").
# ⚠️ 必须传 _gpRenameIdx：默认值 -1 会让 _gpCommitRename 提前返回，重命名静默失效
#（即用户报告的「显示名称不改变」）。
func _gpOnRenameSubmitted(gpText: String) -> void:
	_gpCommitRename(gpText, _gpRenameIdx)
	_gpEndRename(false)


# Commit (or drop) the pending rename and hide the editor.
# 提交（或丢弃）未决的重命名并隐藏编辑器。
func _gpEndRename(gpCommit: bool) -> void:
	if _gpRenameEdit == null or not _gpRenameEdit.visible:
		return
	var gpIdx: int = _gpRenameIdx
	var gpText: String = _gpRenameEdit.text
	_gpRenameEdit.visible = false
	_gpRenameIdx = -1
	if gpCommit:
		_gpCommitRename(gpText, gpIdx)


# Apply a non-empty, changed title to the tab, the sheet record and the GPSheet.
# 把非空且变化过的标题应用到标签、图纸记录与 GPSheet。
func _gpCommitRename(gpText: String, gpIdx: int = -1) -> void:
	var gpNew: String = gpText.strip_edges()
	if gpIdx < 0 or gpIdx >= gpTabs.size():
		return
	if gpNew == "" or gpNew == str(gpTabs[gpIdx]["title"]):
		return
	gpTabs[gpIdx]["title"] = gpNew
	var gpSheet: GPSheet = gpTabs[gpIdx].get("sheet") as GPSheet
	if gpSheet != null:
		gpSheet.gpName = gpNew
	var gpSheetForTitle: GPSheet = gpTabs[gpIdx].get("sheet") as GPSheet
	gpTabBar.set_tab_title(gpIdx, _gpTabTitleOf(gpSheetForTitle) if gpSheetForTitle != null else gpNew)


# Paint the canvas working-area background (brightest tier) so the sheet stands out
# from the darker side docks; canvas content draws on top.
# 自绘画布工作区背景（最亮一档），使图纸从较暗侧栏中凸显；画布内容绘制于其上。
func _draw() -> void:
	GPChromeStyle.gpDraw(self, GPChromeStyle.GP_DOCK_BG, 0)


# Paint the canvas working area (gpBody) in the canvas tint; content draws above.
# 以画布色绘制绘图工作区（gpBody）；画布内容绘制于其上。
func _gpDrawBodyBg() -> void:
	GPChromeStyle.gpDraw(gpBody, GPChromeStyle.GP_CANVAS_BG, 0)
