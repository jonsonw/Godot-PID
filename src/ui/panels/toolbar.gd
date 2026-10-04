class_name GPPIDToolbar
extends VBoxContainer

# Left symbol-library dock, AutoCAD-style (2026-09-25 reference layout).
# 左侧图元库停靠栏，AutoCAD 风格（2026-09-25 参照布局）。
# Structure / 结构：
#   [标题 + 搜索框]
#   [绘制 工具块]  — icon-only buttons for canvas modes (the old Ribbon's draw tools
#                    moved here after the Ribbon left the top bar)
#                    画布模式的纯图标按钮（Ribbon 移出顶栏后其绘图工具迁居于此）
#                    （「编辑」块已按要求整体迁往顶部命令工具栏 quick_toolbar.gd，
#                      此处不再保留 undo / redo / delete / settings。）
#                    (the former EDIT block moved wholesale to the top command
#                     toolbar quick_toolbar.gd — undo / redo / delete / settings
#                     no longer live here.)
#   [滚动区]       — TWO top-level groups: 主图元 (carriers) and 次级图元 (attachments).
#                    Inside each, one collapsible category block per symbol category; each
#                    block header carries a small GEAR whose popup lets the user tick which
#                    symbols stay visible in the palette (persisted via Settings).
#                    两个顶层分组：主图元（载体）与次级图元（附件）。组内每类目一个可折叠块；
#                    块标题右侧有小**齿轮**，弹出的复选清单决定哪些图元显示在面板中
#                    （经 Settings 持久化）。
# The symbol BUTTONS are injected by code from SymbolLibrary so custom symbol packs
# drop in without touching the layout.
# 图元按钮由代码按类目从 SymbolLibrary 注入，自定义图元包无需改布局即可接入。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# A symbol was picked from the library (its type id).
# 从图元库选中某图元（返回其 type id）。
signal gpSymbolPicked(type: String)

# A library entry began a DRAG gesture (规划 §15, interaction mode 1). Kept separate from
# gpSymbolPicked on purpose: a pick means "place this on the sheet", a drag means "mount this part
# onto a host", and conflating them would make every drag also drop a free-floating node.
# 图元库某条开始了**拖动**手势（规划 §15 交互模式一）。刻意与 gpSymbolPicked 分开：点选意为
# 「把它放到图纸上」，拖动意为「把这个部件装到宿主上」；混为一谈会让每次拖动同时丢下一个自由节点。
signal gpSymbolDragStarted(type: String)

# A symbol deletion was requested from a palette item. Forwarded to the main window,
# which owns the graphs (to cascade-remove canvas instances) and the live library.
# 图元库条目请求删除某图元。转发给主窗口，由它持有图（级联清理画布实例）与活动图元库。
signal gpSymbolDeleteRequested(type: String)

# A tool was selected: "select" / "connect" / "custom".
# 选中某工具：select（选择）/ connect（连线）/ custom（自定义图元）。
signal gpToolSelected(type: String)

# A generic command from the tool blocks (canvas modes, undo/redo/delete/settings).
# Reuses the Ribbon action ids, so the host routes it through the existing handler.
# 工具块发出的通用命令（画布模式、撤销/重做/删除/设置）。复用 Ribbon 动作 id，
# 宿主经既有处理器路由即可。
signal gpActionRequested(action: String)

# Tool-block definitions: i18n title key + items. "toggle" buttons keep a pressed
# highlight and are tracked for mode-sync; "mode" is the GPCanvas2D.GPMode they map to.
# 工具块定义：i18n 标题键 + 条目。"toggle" 按钮保持按下高亮并参与模式同步；
# "mode" 为该按钮对应的 GPCanvas2D.GPMode。
const GP_TOOL_BLOCKS: Array = [
	{
		"title_key": "symbol_lib.grp_draw",
		"items": [
			{"action": "select",   "key": "symbol_lib.tool_select", "icon": "select",   "toggle": true, "mode": GPCanvas2D.GPMode.GP_SELECT},
			{"action": "connect",  "key": "symbol_lib.tool_connect", "icon": "connect",  "toggle": true, "mode": GPCanvas2D.GPMode.GP_CONNECT},
			{"action": "line",     "key": "canvas.tool_line",        "icon": "line",     "toggle": true, "mode": GPCanvas2D.GPMode.GP_DRAW_LINE},
			{"action": "circle",   "key": "canvas.tool_circle",      "icon": "circle",   "toggle": true, "mode": GPCanvas2D.GPMode.GP_DRAW_CIRCLE},
			{"action": "rect",     "key": "canvas.tool_rect",        "icon": "rect",     "toggle": true, "mode": GPCanvas2D.GPMode.GP_DRAW_RECT},
			{"action": "polyline", "key": "canvas.tool_polyline",    "icon": "polyline", "toggle": true, "mode": GPCanvas2D.GPMode.GP_DRAW_POLYLINE},
			{"action": "pipe",     "key": "symbol_lib.tool_pipe",    "icon": "pipe",     "toggle": true, "mode": GPCanvas2D.GPMode.GP_PIPE},
			{"action": "signal",   "key": "symbol_lib.tool_signal",  "icon": "signal",   "toggle": true, "mode": GPCanvas2D.GPMode.GP_SIGNAL},
		]
	},
]

# The two TOP-LEVEL groups of the symbol area, keyed by the very i18n key that titles them — so the
# key doubles as the collapse-state key, exactly as GP_TOOL_BLOCKS' title_key already does for the
# Draw block. A dotted key can never collide with a category name, which is what makes the shared
# gpCollapsed dictionary safe to reuse.
# 图元区的两个**顶层**分组，以给它们命名的同一个 i18n 键为键 —— 故该键同时充当折叠状态键，
# 与 GP_TOOL_BLOCKS 的 title_key 对「绘制」块所做之事完全一致。带点的键绝不可能与类目名碰撞，
# 这正是共用的 gpCollapsed 字典可以安全复用的原因。
#
# WHY SPLIT BY MOUNT KIND AND NOT BY CATEGORY / 为何按挂载类型而非类目划分：
# a valve and a nozzle both live in "general", yet one is a host and the other is a part. Category
# answers "what is this?", mount kind answers "how does it relate to another symbol?" — and the
# palette's job here is the second question (规划 §2).
# 阀门与管口同属「通用」类目，但一个是宿主、另一个是部件。类目回答「这是什么」，
# 挂载类型回答「它与别的图元是什么关系」—— 而图元库此处要回答的正是第二个问题（规划 §2）。
const GP_GRP_PRIMARY: String = "symbol_lib.grp_primary"
const GP_GRP_ATTACH: String = "symbol_lib.grp_attach"

# Currently displayed symbol definitions.
# 当前显示的图元定义。
var gpDefs: Array[GPSymbolDef] = []

# Per-category collapse state (true = folded). Preserved across search() / locale re-renders.
# 每个类目的折叠状态（true = 已折叠）。在搜索 / 语言切换的重渲染中保持不变。
var gpCollapsed: Dictionary = {}

# Live list of per-category thumbnail grids; columns are recomputed on dock resize.
# 每个类目的缩略图网格实时列表；列数随停靠栏缩放重算。
var gpGrids: Array[GPSymbolGrid] = []

# Floor width (pixels) fed to every thumbnail grid so its column-count floor stays
# in sync with the left dock's GP_LEFT_MIN (set by main_window.gd). 160 by default.
# 传给每个缩略图网格的下限宽（像素），使其列数下限与左停靠栏的 GP_LEFT_MIN 保持一致
# （由 main_window.gd 注入）。默认 160。
var gpMinWidth: float = 160.0

# Title label at the top of the dock.
# 停靠栏顶部标题标签。
var gpTitle: Label

# Search input box.
# 搜索输入框。
var gpSearchBox: LineEdit

# Scroll container that holds the symbol list.
# 承载图元列表的滚动容器。
var gpListRoot: ScrollContainer

# Column hosting the static tool blocks (built once, above the scroll area).
# 承载静态工具块的列（仅构建一次，位于滚动区上方）。
var gpToolsRoot: VBoxContainer

# Toggle buttons keyed by action, for mode-sync highlight.
# 以动作为键的开关按钮，用于模式同步高亮。
var gpToolBtns: Dictionary = {}

# action -> GPCanvas2D.GPMode map, for mode-sync highlight.
# 动作 → GPCanvas2D.GPMode 映射，用于模式同步高亮。
var gpActionToMode: Dictionary = {}

# All tool-block buttons, kept for locale / font refresh.
# 全部工具块按钮，保留以便语言/字号刷新。
var _gpToolButtons: Array[Button] = []

# Tool-block header buttons, kept for locale / font refresh (arrow re-derived from
# the collapse state on every re-render).
# 工具块标题按钮，保留以便语言/字号刷新（箭头每次重渲染时按折叠状态重推）。
var _gpToolHeaders: Array[Button] = []


# Build the static frame of the dock.
# 构建停靠栏的静态框架。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP

	# ---- frozen frame: title ----
	# ---- 固化框架：标题 ----
	gpTitle = Label.new()
	add_child(gpTitle)

	# ---- frozen frame: search() box ----
	# ---- 固化框架：搜索框 ----
	gpSearchBox = LineEdit.new()
	gpSearchBox.text_changed.connect(_gpOnSearch)
	add_child(gpSearchBox)

	# ---- frozen frame: tool blocks (the old Ribbon's draw/edit commands) ----
	# ---- 固化框架：工具块（原 Ribbon 的绘图/编辑命令）----
	gpToolsRoot = VBoxContainer.new()
	gpToolsRoot.add_theme_constant_override("separation", 2)
	add_child(gpToolsRoot)
	for gpBlock in GP_TOOL_BLOCKS:
		gpToolsRoot.add_child(_gpBuildToolBlock(gpBlock as Dictionary))

	# 1px hairline separating the DRAW-TILE area from the symbol-category area —
	# the same separator the categories use between themselves (2026-09-25 request).
	# 「绘制」图块区与图元类目区之间的 1px 发丝分隔线 —— 与类目之间的分隔线同款
	#（2026-09-25 需求）。
	var gpToolSep: ColorRect = ColorRect.new()
	gpToolSep.color = GPChromeStyle.GP_BORDER
	gpToolSep.custom_minimum_size = Vector2(0.0, 1.0)
	add_child(gpToolSep)

	# ---- frozen frame: scroll container (symbols injected here) ----
	# ---- 固化框架：滚动容器（图元注入于此）----
	gpListRoot = ScrollContainer.new()
	gpListRoot.size_flags_vertical = SIZE_EXPAND_FILL
	gpListRoot.size_flags_horizontal = SIZE_FILL
	# Disable horizontal scrolling: the grid's minimum width is forced to the
	# viewport width by _gpReflow, so the content always equals the viewport (it
	# fills edge-to-edge, no right gap, no overlap) and there is never an
	# horizontal scrollbar. Only vertical scrolling is kept.
	# 关闭横向滚动：网格最小宽由 _gpReflow 强制设为视口宽，故内容恒等于视口（铺满
	# 无右侧留白、不重叠），且永远不会出现横向滚动条。仅保留纵向滚动。
	gpListRoot.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Reflow the thumbnail grids whenever the dock (and thus the viewport) is resized,
	# so the palette stays multi-column and matches the real width.
	# 停靠栏（也即视口）缩放时重排缩略图网格，使图元库保持多列并贴合真实宽度。
	gpListRoot.resized.connect(gpReflow)
	add_child(gpListRoot)

	# Explicitly match the static frame controls to the current UI font size so they
	# update reliably when the user changes the font in the settings dialog.
	# 让静态框架控件显式匹配当前界面字号，确保用户在设置对话框改字号时能可靠更新。
	_gpApplyUIFontSize()

	I18n.gpLocaleChanged.connect(_gpRefreshLocale)
	Settings.gpUIFontChanged.connect(_gpOnFontChanged)
	Settings.gpSymbolStyleChanged.connect(_gpOnSymbolStyleChanged)
	_gpRefreshLocale(I18n.gpLocale)
	# 视觉分层：增大垂直留白 + 首帧自绘背景（与画布分隔的右边界）。
	add_theme_constant_override("separation", 6)
	queue_redraw()


# Build one tool block: a caption header above an auto-flowing tile grid.
# Each tool is a SQUARE TILE the same size as a palette cell (THUMB+PAD), drawn
# without any default background; hover/active light the tile up, exactly like the
# symbol tiles. HFlowContainer re-wraps the tiles to whatever the dock width allows.
# 构建一个工具块：小标题位于自适应换行的图块网格之下。每个工具是**方形图块**，
# 与图元单元格同尺寸（THUMB+PAD），默认无底色；悬停/激活点亮图块，与图元图块完全同款。
# HFlowContainer 依停靠栏宽度自动换行，实现图标自适应布置。
func _gpBuildToolBlock(gpBlock: Dictionary) -> Control:
	var gpV: VBoxContainer = VBoxContainer.new()
	gpV.add_theme_constant_override("separation", 2)

	# Collapsible header, the SAME contract as the symbol-category headers: the
	# 绘制 block folds exactly like any other category (2026-09-25 request).
	# 可折叠标题，与图元类目标题**同一契约**：「绘制」块与其他类目一样可折叠。
	var gpCat: String = str(gpBlock["title_key"])
	if not gpCollapsed.has(gpCat):
		gpCollapsed[gpCat] = false
	var gpFold: bool = gpCollapsed[gpCat]

	var gpHeader: Button = Button.new()
	gpHeader.size_flags_horizontal = SIZE_EXPAND_FILL
	gpHeader.alignment = HORIZONTAL_ALIGNMENT_LEFT
	gpHeader.flat = true
	gpHeader.clip_text = true
	gpHeader.add_theme_font_size_override("font_size", maxi(11, Settings.gpEffectiveFontSize() - 2))
	gpHeader.text = ("▾ " if not gpFold else "▸ ") + I18n.gpTr(gpCat)
	gpHeader.set_meta("gpKey", gpCat)
	# Same category-band look: slightly-lighter band + the AutoCAD category feel.
	# 同类目色带观感：略亮色带 + AutoCAD 类目感。
	var gpHdrBg: StyleBoxFlat = StyleBoxFlat.new()
	gpHdrBg.bg_color = Color(0.180, 0.216, 0.267)
	gpHdrBg.content_margin_left = 6.0
	gpHdrBg.content_margin_top = 2.0
	gpHdrBg.content_margin_bottom = 2.0
	gpHeader.add_theme_stylebox_override("normal", gpHdrBg)
	gpHeader.add_theme_stylebox_override("hover", gpHdrBg)
	gpHeader.add_theme_stylebox_override("pressed", gpHdrBg)
	gpHeader.add_theme_color_override("font_color", Color(0.80, 0.84, 0.90))
	gpV.add_child(gpHeader)
	_gpToolHeaders.append(gpHeader)

	# HFlowContainer: fixed-size tiles that WRAP to the dock width — the palette-style
	# auto-flow. Tiles keep their minimum; the flow derives rows from the real width.
	# HFlowContainer：固定尺寸图块按停靠栏宽度**自动换行** —— 图元库式自适应流式布局。
	# 图块保持最小尺寸；流式容器按真实宽度推导行数。
	var gpGrid: HFlowContainer = HFlowContainer.new()
	gpGrid.add_theme_constant_override("h_separation", 2)
	gpGrid.add_theme_constant_override("v_separation", 2)
	gpGrid.visible = not gpFold
	for gpItem in gpBlock["items"]:
		gpGrid.add_child(_gpBuildToolBtn(gpItem as Dictionary))
	gpV.add_child(gpGrid)
	gpHeader.pressed.connect(_gpToggleToolBlock.bind(gpCat, gpGrid, gpHeader))
	return gpV


# Toggle the draw tool block's collapsed state and update the header arrow.
# 切换「绘制」工具块的折叠状态并更新标题箭头。
func _gpToggleToolBlock(gpCat: String, gpGrid: HFlowContainer, gpHeader: Button) -> void:
	var gpNow: bool = not gpCollapsed.get(gpCat, false)
	gpCollapsed[gpCat] = gpNow
	gpGrid.visible = not gpNow
	gpHeader.text = ("▾ " if not gpNow else "▸ ") + I18n.gpTr(gpCat)


# Build one icon-only tool button (tooltip = localized name, like the AutoCAD tiles).
# 构建一枚纯图标工具按钮（提示 = 本地化名称，同 AutoCAD 图块）。
func _gpBuildToolBtn(gpItem: Dictionary) -> Button:
	var gpBtn: Button = Button.new()
	gpBtn.focus_mode = Control.FOCUS_NONE
	gpBtn.tooltip_text = I18n.gpTr(str(gpItem["key"]))
	gpBtn.set_meta("gpKey", gpItem["key"])
	# SQUARE TILE, the same footprint as a palette cell (THUMB + PAD = 33 px): the
	# draw tools read as siblings of the symbol tiles below (2026-09-25 request).
	# **方形图块**，与图元单元格同尺寸（THUMB + PAD = 33 px）：「绘制」工具与下方
	# 图元图块视觉同族（2026-09-25 需求）。
	var gpTile: float = GPSymbolPaletteItem.GP_THUMB_PX + GPSymbolPaletteItem.GP_CELL_PAD
	gpBtn.custom_minimum_size = Vector2(gpTile, gpTile)
	# No default background: transparent until hover; hover lights the WHOLE tile
	# (GP_SPLIT_HI — the exact colour the symbol tiles use); the ACTIVE mode keeps a
	# dark accent fill + accent underline, mirroring the selected tab look.
	# 默认无底色：悬停前完全透明；悬停点亮**整块**（GP_SPLIT_HI —— 与图元图块同色）；
	# 激活模式保持深色 accent 底 + accent 底线，与选中 tab 同款。
	var gpNone: StyleBoxFlat = StyleBoxFlat.new()
	gpNone.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	gpNone.set_content_margin_all(4.0)
	var gpHover: StyleBoxFlat = gpNone.duplicate() as StyleBoxFlat
	gpHover.bg_color = GPChromeStyle.GP_SPLIT_HI
	gpHover.set_corner_radius_all(3)
	var gpActive: StyleBoxFlat = gpHover.duplicate() as StyleBoxFlat
	gpActive.bg_color = Color(0.129, 0.165, 0.204)
	gpActive.border_color = GPChromeStyle.GP_ACCENT
	gpActive.border_width_bottom = 1
	gpBtn.add_theme_stylebox_override("normal", gpNone)
	gpBtn.add_theme_stylebox_override("hover", gpHover)
	gpBtn.add_theme_stylebox_override("pressed", gpActive)
	gpBtn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var gpIcon: Texture2D = load("res://assets/icons/%s.svg" % str(gpItem["icon"])) as Texture2D
	if gpIcon != null:
		gpBtn.icon = gpIcon
	# Icon width == the palette thumbnail size (GP_THUMB_PX = 21), so the draw block
	# and the symbol tiles share ONE icon scale (2026-09-25 request).
	# 图标宽 = 图元库缩略图尺寸（GP_THUMB_PX = 21），「绘制」块与图元图块共用同一图标尺度。
	gpBtn.add_theme_constant_override("icon_max_width", int(GPSymbolPaletteItem.GP_THUMB_PX))
	if bool(gpItem.get("toggle", false)):
		gpBtn.toggle_mode = true
		gpToolBtns[str(gpItem["action"])] = gpBtn
		gpActionToMode[str(gpItem["action"])] = int(gpItem["mode"])
	gpBtn.pressed.connect(_gpOnToolBtn.bind(str(gpItem["action"])))
	_gpToolButtons.append(gpBtn)
	return gpBtn


# A tool-block button was pressed: forward the action id through gpActionRequested.
# 工具块按钮被按下：经 gpActionRequested 转发动作 id。
func _gpOnToolBtn(gpAction: String) -> void:
	gpActionRequested.emit(gpAction)


# Highlight the toggle button matching the active canvas mode (Ribbon's old contract,
# now served by the palette blocks).
# 高亮与当前画布模式匹配的开关按钮（Ribbon 的旧契约，现由图元库工具块履行）。
func gpSyncMode(gpMode: int) -> void:
	for gpAct in gpToolBtns.keys():
		var gpBtn: Button = gpToolBtns[gpAct] as Button
		var gpM: int = int(gpActionToMode.get(gpAct, -1))
		gpBtn.button_pressed = (gpM >= 0 and gpMode == gpM)


# Inject symbols grouped by category. Call once after assigning the def set.
# 按类目注入图元。赋值图元集后调用一次。
func gpPopulate(gpDefsIn: Array[GPSymbolDef]) -> void:
	gpDefs = gpDefsIn
	_gpRender(gpDefs)


# React to search() text changes.
# 响应搜索文本变化。
func _gpOnSearch(gpQ: String) -> void:
	_gpRender(_gpFilter(gpQ))


# Filter the symbol list by query string.
# 按查询字符串过滤图元列表。
func _gpFilter(gpQ: String) -> Array[GPSymbolDef]:
	var gpNeedle: String = gpQ.strip_edges().to_lower()
	if gpNeedle == "":
		return gpDefs
	var gpOut: Array[GPSymbolDef] = []
	for gpD in gpDefs:
		var gpHay: String = "%s %s %s" % [I18n.gpTr(gpD.gpDisplayName), gpD.gpId, gpD.gpCategory]
		if gpHay.to_lower().contains(gpNeedle):
			gpOut.append(gpD)
	return gpOut


# Render the injected symbol list: TWO top-level groups (primary / attachments), each holding the
# collapsible per-category blocks, whose thumbnails use GPSymbolGrid's multi-column layout.
# 渲染注入的图元列表：**两个顶层分组**（主图元 / 次级图元），各自包含可折叠的类目块，
# 其缩略图用 GPSymbolGrid 多列排布。
func _gpRender(gpList: Array[GPSymbolDef]) -> void:
	# Read as an assembly list: clear -> column -> one block per TOP-LEVEL group -> reflow.
	# 读作装配清单：清空 -> 建列 -> 每个**顶层**分组一块 -> 重排。
	_gpClearList()
	var gpVbox: VBoxContainer = _gpNewColumn()
	var gpByGroup: Dictionary = _gpGroupByMountKind(gpList)
	var gpFirst: bool = true
	for gpGrp in [GP_GRP_PRIMARY, GP_GRP_ATTACH]:
		var gpItems: Array = gpByGroup[gpGrp] as Array
		# An empty group is skipped entirely: an "Attachments" header over nothing would read as a
		# bug rather than as "this library has no parts yet".
		# 空分组整体跳过：一个「次级图元」标题下面什么都没有，读起来像 bug 而不是「本库还没有部件」。
		if gpItems.is_empty():
			continue
		# A 1px hairline separates the two groups (none before the first).
		# 两分组之间以 1px 发丝线分隔（首个之前不画）。
		if not gpFirst:
			_gpAddHairline(gpVbox)
		gpFirst = false
		gpVbox.add_child(_gpBuildTopGroup(str(gpGrp), gpItems))
	# Recompute columns now that grids exist (size may be 0 yet; resize handler refreshes later).
	# 网格已建好，先按当前视口重排一次（此时尺寸可能仍为 0，缩放处理器之后会再刷新）。
	gpReflow(-1.0)


# Bucket the symbols into the two top-level groups, preserving first-appearance order inside each.
# 把图元分入两个顶层分组，组内保持首次出现顺序。
func _gpGroupByMountKind(gpList: Array) -> Dictionary:
	var gpOut: Dictionary = {GP_GRP_PRIMARY: [], GP_GRP_ATTACH: []}
	for gpD in gpList:
		var gpDef: GPSymbolDef = gpD as GPSymbolDef
		if gpDef == null:
			continue
		var gpKey: String = GP_GRP_ATTACH if gpDef.gpMountKind != "" else GP_GRP_PRIMARY
		(gpOut[gpKey] as Array).append(gpDef)
	return gpOut


# One top-level group: a heavier header (accent edge, darker band) above the per-category blocks it
# contains. Folding the header hides the whole group, which is the reason the row exists.
# 一个顶层分组：较重的标题（accent 侧边、更深色带）位于其包含的各类目块之上。
# 折叠该标题即隐藏整组 —— 这正是这一行存在的理由。
func _gpBuildTopGroup(gpGrpKey: String, gpItems: Array) -> Control:
	if not gpCollapsed.has(gpGrpKey):
		gpCollapsed[gpGrpKey] = false
	var gpFold: bool = gpCollapsed[gpGrpKey]

	var gpOuter: VBoxContainer = VBoxContainer.new()
	gpOuter.size_flags_horizontal = SIZE_EXPAND_FILL
	gpOuter.add_theme_constant_override("separation", 2)

	var gpHead: Button = Button.new()
	gpHead.size_flags_horizontal = SIZE_EXPAND_FILL
	gpHead.alignment = HORIZONTAL_ALIGNMENT_LEFT
	gpHead.flat = true
	gpHead.clip_text = true
	gpHead.add_theme_font_size_override("font_size", Settings.gpEffectiveFontSize())
	gpHead.text = ("▾ " if not gpFold else "▸ ") + I18n.gpTr(gpGrpKey)
	gpHead.set_meta("gpKey", gpGrpKey)
	# One visual step ABOVE the category bands below: darker fill + an accent left edge, so the
	# hierarchy (group > category > tiles) reads at a glance instead of only by indentation.
	# 比下方类目色带高**一级**：更深底色 + accent 左侧边，使层级（分组 > 类目 > 图块）一眼可读，
	# 而不是只能靠缩进分辨。
	var gpBg: StyleBoxFlat = StyleBoxFlat.new()
	gpBg.bg_color = Color(0.129, 0.165, 0.204)
	gpBg.border_color = GPChromeStyle.GP_ACCENT
	gpBg.border_width_left = 3
	gpBg.content_margin_left = 6.0
	gpBg.content_margin_top = 3.0
	gpBg.content_margin_bottom = 3.0
	gpHead.add_theme_stylebox_override("normal", gpBg)
	gpHead.add_theme_stylebox_override("hover", gpBg)
	gpHead.add_theme_stylebox_override("pressed", gpBg)
	gpHead.add_theme_color_override("font_color", Color(0.88, 0.91, 0.95))
	gpOuter.add_child(gpHead)

	# The body holds one collapsible CATEGORY block per category present in this group, with the
	# same hairline separation the ungrouped list used to have.
	# 主体持有本组内每个类目一个可折叠**类目**块，并沿用未分组列表原先的发丝线分隔。
	var gpBody: VBoxContainer = VBoxContainer.new()
	gpBody.size_flags_horizontal = SIZE_EXPAND_FILL
	gpBody.add_theme_constant_override("separation", 2)
	gpBody.visible = not gpFold
	var gpByCat: Dictionary = _gpGroupByCategory(gpItems)
	var gpCatKeys: Array = _gpOrderedCategories(gpByCat)
	var gpCatIdx: int = 0
	for gpCat in gpCatKeys:
		if gpCatIdx > 0:
			_gpAddHairline(gpBody)
		gpCatIdx += 1
		gpBody.add_child(_gpBuildCategoryGroup(str(gpCat), gpByCat[gpCat] as Array))
	gpOuter.add_child(gpBody)
	gpHead.pressed.connect(_gpToggleCategory.bind(gpGrpKey, gpBody, gpHead))
	return gpOuter


# Drop every child of the list and forget the grids built for the previous render.
# 清空列表的全部子节点，并遗忘上一次渲染建立的网格。
func _gpClearList() -> void:
	for gpC in gpListRoot.get_children():
		gpListRoot.remove_child(gpC)
		gpC.queue_free()
	gpGrids = []


# The single column that holds every category group. EXPAND (not just FILL) so the
# ScrollContainer hands this column its whole viewport width. With FILL alone the column kept its
# own minimum width, so the grid below laid its cells out for the wider dock width while its own
# rect stayed narrow — the cells then overflowed horizontally instead of merely wrapping. EXPAND
# makes the column width and the width the grid lays out for the SAME number.
# 持有全部类目分组的单列。用 EXPAND（而非仅 FILL）使 ScrollContainer 把整个视口宽度交给本列。
# 仅 FILL 时本列保持自身最小宽，于是下方网格按更宽的停靠栏宽度摆放单元格、自身矩形却仍是窄的
# —— 单元格便横向溢出，而不是正常换行。EXPAND 让「本列宽度」与「网格据以布局的宽度」成为同一个数。
func _gpNewColumn() -> VBoxContainer:
	var gpVbox: VBoxContainer = VBoxContainer.new()
	gpVbox.size_flags_horizontal = SIZE_EXPAND_FILL
	gpListRoot.add_child(gpVbox)
	return gpVbox


# Bucket the symbols by category, preserving first-appearance order within each bucket.
# 按类目把图元分桶，桶内保持首次出现顺序。
# Takes a plain Array on purpose: the two top-level groups hand it untyped slices of a Dictionary,
# and an untyped Array cannot be passed where Array[GPSymbolDef] is expected without a conversion
# that GDScript refuses at runtime.
# 刻意接收无类型 Array：两个顶层分组传给它的是来自字典的无类型切片，而无类型 Array 传给
# Array[GPSymbolDef] 形参会要求一次 GDScript 在运行期拒绝的转换。
func _gpGroupByCategory(gpList: Array) -> Dictionary:
	var gpByCat: Dictionary = {}
	for gpD in gpList:
		var gpDef: GPSymbolDef = gpD as GPSymbolDef
		if gpDef == null:
			continue
		if not gpByCat.has(gpDef.gpCategory):
			gpByCat[gpDef.gpCategory] = []
		gpByCat[gpDef.gpCategory].append(gpDef)
	return gpByCat


# Category order for display: "general"（通用）always sorts LAST; the rest keep first-appearance
# order. The comparison is case-insensitive to tolerate capitalised variants in older packs.
# 类目的显示顺序：「通用」永远排在最后；其余保持首次出现顺序。
# 比较不区分大小写，兼容旧包里可能的大写变体。
func _gpOrderedCategories(gpByCat: Dictionary) -> Array:
	var gpCatKeys: Array = []
	for gpK in gpByCat.keys():
		if str(gpK).to_lower() != "general":
			gpCatKeys.append(gpK)
	if gpByCat.has("general"):
		gpCatKeys.append("general")
	return gpCatKeys


# A 1px separator line matching the one GPChromeStyle uses between chrome bands.
# 一条 1px 分隔线，与 GPChromeStyle 在各 chrome 带之间所用的一致。
func _gpAddHairline(gpParent: Control) -> void:
	var gpSep: ColorRect = ColorRect.new()
	gpSep.color = GPChromeStyle.GP_BORDER
	gpSep.custom_minimum_size = Vector2(0.0, 1.0)
	gpParent.add_child(gpSep)


# One collapsible category group: header row (fold button + gear) above the thumbnail grid.
# 一个可折叠的类目分组：标题行（折叠按钮 + 齿轮）位于缩略图网格之上。
func _gpBuildCategoryGroup(gpCat: String, gpItems: Array) -> Control:
	if not gpCollapsed.has(gpCat):
		gpCollapsed[gpCat] = false
	var gpCollapsedNow: bool = gpCollapsed[gpCat]

	var gpGroup: VBoxContainer = VBoxContainer.new()
	gpGroup.size_flags_horizontal = SIZE_FILL
	gpGroup.add_theme_constant_override("separation", 2)

	var gpHead: Dictionary = _gpBuildCategoryHeader(gpCat, gpCollapsedNow)
	gpGroup.add_child(gpHead["row"] as HBoxContainer)

	var gpGrid: GPSymbolGrid = _gpBuildCategoryGrid(gpCollapsedNow)
	gpGroup.add_child(gpGrid)
	gpGrids.append(gpGrid)
	_gpFillCategoryGrid(gpGrid, gpItems)

	# Bind the two header buttons now that both the grid and the item list exist.
	# 两个标题按钮在此接线 —— 此时网格与条目表都已就绪。
	var gpHeader: Button = gpHead["header"]
	var gpGear: Button = gpHead["gear"]
	gpHeader.pressed.connect(_gpToggleCategory.bind(gpCat, gpGrid, gpHeader))
	gpGear.pressed.connect(_gpShowVisibilityMenu.bind(gpCat, gpItems, gpGrid))
	return gpGroup


# Header row of a category group: [▾ category (expand, click = fold)] [gear (visibility menu)].
# Returns {"row": HBoxContainer, "header": Button, "gear": Button} — the callers bind to the
# named handles rather than to child indices, so adding a widget to this row cannot silently
# rewire the buttons.
# 类目分组的标题行：[▾ 类目（伸展，点击折叠）] [齿轮（可见性菜单）]。
# 返回 {"row": HBoxContainer, "header": Button, "gear": Button} —— 调用方按**具名句柄**接线，
# 而非子节点下标；故将来在本行增删控件都不会静默把按钮接错。
func _gpBuildCategoryHeader(gpCat: String, gpCollapsedNow: bool) -> Dictionary:
	var gpHeadRow: HBoxContainer = HBoxContainer.new()
	gpHeadRow.add_theme_constant_override("separation", 0)

	var gpHeader: Button = Button.new()
	gpHeader.size_flags_horizontal = SIZE_EXPAND_FILL
	gpHeader.alignment = HORIZONTAL_ALIGNMENT_LEFT
	gpHeader.flat = true
	gpHeader.clip_text = true
	gpHeader.add_theme_font_size_override("font_size", Settings.gpEffectiveFontSize())
	gpHeader.text = ("▾ " if not gpCollapsedNow else "▸ ") + I18n.gpTr(gpCat)
	gpHeadRow.add_child(gpHeader)
	# 类目标题：克制的浅背景（仅比 dock 略亮）+ 1px 发丝底线。
	var gpHdrBg: StyleBoxFlat = StyleBoxFlat.new()
	gpHdrBg.bg_color = Color(0.180, 0.216, 0.267)
	gpHdrBg.content_margin_left = 6.0
	gpHdrBg.content_margin_top = 2.0
	gpHdrBg.content_margin_bottom = 2.0
	gpHeader.add_theme_stylebox_override("normal", gpHdrBg)
	gpHeader.add_theme_stylebox_override("hover", gpHdrBg)
	gpHeader.add_theme_stylebox_override("pressed", gpHdrBg)
	gpHeader.add_theme_color_override("font_color", Color(0.80, 0.84, 0.90))

	# The category GEAR: opens the per-symbol visibility checklist (AutoCAD panel menu).
	# 类目**齿轮**：打开逐图元的可见性复选清单（AutoCAD 面板菜单）。
	var gpGear: Button = Button.new()
	gpGear.flat = true
	gpGear.focus_mode = Control.FOCUS_NONE
	gpGear.tooltip_text = I18n.gpTr("symbol_lib.gear_tip")
	gpGear.custom_minimum_size = Vector2(22.0, 22.0)
	var gpGearIcon: Texture2D = load("res://assets/icons/gear.svg") as Texture2D
	if gpGearIcon != null:
		gpGear.icon = gpGearIcon
	gpGear.add_theme_constant_override("icon_max_width", 12)
	var gpGearBg: StyleBoxFlat = gpHdrBg.duplicate() as StyleBoxFlat
	gpGearBg.content_margin_left = 2.0
	gpGearBg.content_margin_right = 4.0
	gpGear.add_theme_stylebox_override("normal", gpGearBg)
	gpGear.add_theme_stylebox_override("hover", gpGearBg)
	gpGear.add_theme_stylebox_override("pressed", gpGearBg)
	gpHeadRow.add_child(gpGear)
	return {"row": gpHeadRow, "header": gpHeader, "gear": gpGear}


# Multi-column, width-adaptive thumbnail grid. Its minimum width is forced to the viewport width
# by _gpReflow so it always fills and re-derives its column count from the real width
# (see symbol_grid.gd).
# 多列、随宽度自适应的缩略图网格。其最小宽由 _gpReflow 强制设为视口宽，
# 从而始终填满并按真实宽度重排列数（见 symbol_grid.gd）。
func _gpBuildCategoryGrid(gpCollapsedNow: bool) -> GPSymbolGrid:
	var gpGrid: GPSymbolGrid = GPSymbolGrid.new()
	gpGrid.size_flags_horizontal = SIZE_FILL
	# Keep the grid's column-count floor aligned with the left dock minimum so a narrow dock
	# still derives a sensible (>=1) column count from GP_LEFT_MIN.
	# 让网格列数下限与左停靠栏最小宽对齐，窄停靠栏仍按 GP_LEFT_MIN 推导出合理（≥1）列数。
	gpGrid.gpMinWidth = gpMinWidth
	gpGrid.visible = not gpCollapsedNow
	return gpGrid


# Populate a category grid with one palette tile per symbol, honouring persisted visibility.
# 用每个图元一个图块填充类目网格，并遵循持久化的可见性选择。
func _gpFillCategoryGrid(gpGrid: GPSymbolGrid, gpItems: Array) -> void:
	for gpD in gpItems:
		var gpItem: GPSymbolPaletteItem = GPSymbolPaletteItem.new()
		gpItem.gpDef = gpD
		gpItem.size_flags_horizontal = SIZE_EXPAND_FILL
		gpItem.gpPicked.connect(_gpOnPick)
		gpItem.gpDragStarted.connect(_gpOnDragStarted)
		gpItem.gpDeleteRequested.connect(_gpOnDeleteRequested)
		# Apply the persisted visibility choice: an unticked symbol stays hidden
		# (the grid lays out visible children only, so no hole is left).
		# 应用持久化的可见性选择：被取消勾选的图元保持隐藏
		#（网格只排布可见子项，故不留空洞）。
		gpItem.visible = not bool(Settings.gpPaletteHidden.get(gpD.gpId, false))
		gpGrid.add_child(gpItem)


# Open the per-category visibility checklist: one check item per symbol (localized
# name), plus "Show All". Toggling flips the palette item's visibility and persists
# the choice in Settings so it survives restarts.
# 打开类目的可见性复选清单：每个图元一个复选项（本地化名），外加「全部显示」。
# 切换即翻转图元条目可见性，并把选择持久化到 Settings，重启后保留。
func _gpShowVisibilityMenu(gpCat: String, gpDefsIn: Array, gpGrid: GPSymbolGrid) -> void:
	var gpMenu: PopupMenu = PopupMenu.new()
	var gpIdx: int = 0
	for gpD in gpDefsIn:
		var gpDef: GPSymbolDef = gpD as GPSymbolDef
		if gpDef == null:
			continue
		gpMenu.add_check_item(I18n.gpTr(gpDef.gpDisplayName), gpIdx)
		gpMenu.set_item_checked(gpIdx, not bool(Settings.gpPaletteHidden.get(gpDef.gpId, false)))
		gpMenu.set_item_metadata(gpIdx, gpDef.gpId)
		gpIdx += 1
	if gpIdx > 0:
		gpMenu.add_separator()
	gpMenu.add_item(I18n.gpTr("symbol_lib.show_all"), gpIdx)
	gpMenu.set_item_metadata(gpIdx, "__show_all__")
	gpMenu.id_pressed.connect(_gpOnVisibilityToggled.bind(gpMenu, gpGrid))
	add_child(gpMenu)
	GPPopupHelper.gpPopupAtMouse(gpMenu, gpGrid)
	# Free the popup after it closes so this dock can be released later.
	# 弹层关闭后释放，使停靠栏此后仍可释放。
	gpMenu.popup_hide.connect(gpMenu.queue_free)


# One checklist row was toggled: flip that symbol's palette visibility and persist.
# 勾选清单的一行被切换：翻转该图元在面板中的可见性并持久化。
func _gpOnVisibilityToggled(gpId: int, gpMenu: PopupMenu, gpGrid: GPSymbolGrid) -> void:
	var gpMeta: String = str(gpMenu.get_item_metadata(gpId))
	if gpMeta == "__show_all__":
		# Show All: clear every hidden entry of this category's symbols.
		# 全部显示：清空本类目各图元的隐藏记录。
		for gpI in range(gpMenu.item_count):
			var gpMid: String = str(gpMenu.get_item_metadata(gpI))
			if gpMid != "__show_all__" and gpMid != "":
				Settings.gpPaletteHidden.erase(gpMid)
				_gpSetItemVisible(gpGrid, gpMid, true)
		Settings.gpSave()
		return
	var gpHide: bool = not bool(Settings.gpPaletteHidden.get(gpMeta, false))
	if gpHide:
		Settings.gpPaletteHidden[gpMeta] = true
	else:
		Settings.gpPaletteHidden.erase(gpMeta)
	Settings.gpSave()
	_gpSetItemVisible(gpGrid, gpMeta, not gpHide)


# Flip the visibility of the palette item whose def carries the given symbol id.
# 翻转携带指定符号 id 的图元条目可见性。
func _gpSetItemVisible(gpGrid: GPSymbolGrid, gpSymbolId: String, gpVis: bool) -> void:
	for gpC in gpGrid.get_children():
		var gpItem: GPSymbolPaletteItem = gpC as GPSymbolPaletteItem
		if gpItem != null and gpItem.gpDef != null and gpItem.gpDef.gpId == gpSymbolId:
			gpItem.visible = gpVis
	gpGrid.update_minimum_size()
	gpGrid.queue_sort()


# Re-derive each category grid's columns after a width change. The grid fills the
# dock viewport through ScrollContainer's fit-to-viewport stretch (horizontal
# scrolling is disabled), so we must NOT pin its MINIMUM width to the dock width:
# a non-zero minimum would bubble up the VBox chain into the left dock and lock the
# HSplitContainer splitter at the widest width ever reached (widen-only, never back
# to a narrower dock). Keeping the grid minimum at 0 is exactly what lets the
# splitter move freely in both directions.
# 宽度变化后重排每个类目网格的列数。网格靠 ScrollContainer 的「贴合视口拉伸」（横向滚动
# 已关闭）铺满停靠栏，因此绝不能把网格「最小宽」钉成停靠栏宽：非零最小宽会沿 VBox 链向上
# 冒泡到左停靠栏，把 HSplitContainer 分隔条锁死在「曾达到的最宽」（只能加宽、拖不回去）。
# 网格最小宽保持 0，正是分隔条能自由双向拖动的关键。
# GPLayoutCoordinator. Promoting it closes that encapsulation leak; the toolbar still calls it
# internally on resize and at first build.
# 公开端口：GPLayoutCoordinator 会跨对象调用它，故不能是私有；工具栏自身在缩放与首次构建时
# 仍内部调用它。以公开端口暴露，可避免调用方窥探私有成员。
func gpReflow(gpForcedWidth: float = -1.0) -> void:
	# Always feed the grid the real ScrollContainer viewport width. Relying on the
	# grid's own size.x inside NOTIFICATION_SORT_CHILDREN is unreliable because the
	# grid may be sorted before the parent has allocated the new width. The resized
	# signal of gpListRoot carries no argument, so we read gpListRoot.size.x directly.
	# 始终把 ScrollContainer 视口的真实宽度喂给网格。在 NOTIFICATION_SORT_CHILDREN 中依赖
	# 网格自身 size.x 不可靠，因为网格可能在父节点分配新宽度前就被排序。gpListRoot 的 resized
	# 信号不带参数，因此直接读 gpListRoot.size.x。
	var gpW: float = gpForcedWidth
	if gpW <= 0.0 and gpListRoot != null and is_instance_valid(gpListRoot):
		gpW = gpListRoot.size.x
	for gpG in gpGrids:
		if gpG != null and is_instance_valid(gpG):
 # Zero minimum width: no bubble, no splitter lock.
 # 最小宽归零：不冒泡、不锁分隔条。
			gpG.custom_minimum_size.x = 0.0
			if gpW > 0.0:
 # Pass the real dock width directly so columns are derived from the
 # dragged/allocated width, not from a possibly stale size.x.
 # 直接把真实停靠栏宽度传给网格，使列数按拖拽/分配后的宽度计算，而非可能过期的 size.x。
				gpG.gpSetAvailWidth(gpW)
			else:
				gpG.queue_sort()


# Toggle a collapsible block (a category group OR a top-level group) and update its header arrow.
# 切换一个可折叠块（类目分组**或**顶层分组）并更新其标题箭头。
# [param gpBody] is typed Control, not GPSymbolGrid: the top-level group's body is a plain
# VBoxContainer. Both callers only ever touch `visible`, which is the whole contract.
# [param gpBody] 类型为 Control 而非 GPSymbolGrid：顶层分组的主体是普通 VBoxContainer。
# 两个调用方都只碰 `visible`，而这就是全部契约。
func _gpToggleCategory(gpCat: String, gpBody: Control, gpHeader: Button) -> void:
	var gpNow: bool = not gpCollapsed.get(gpCat, false)
	gpCollapsed[gpCat] = gpNow
	gpBody.visible = not gpNow
	gpHeader.text = ("▾ " if not gpNow else "▸ ") + I18n.gpTr(gpCat)


# Refresh all locale-dependent texts.
# 刷新所有依赖语言的文本。
func _gpRefreshLocale(gpLocale: String) -> void:
	gpTitle.text = I18n.gpTr("symbol_lib.title")
	gpSearchBox.placeholder_text = I18n.gpTr("symbol_lib.search")
	for gpH in _gpToolHeaders:
		var gpCat: String = str(gpH.get_meta("gpKey"))
		gpH.text = ("▸ " if bool(gpCollapsed.get(gpCat, false)) else "▾ ") + I18n.gpTr(gpCat)
	for gpB in _gpToolButtons:
		gpB.tooltip_text = I18n.gpTr(str(gpB.get_meta("gpKey")))
	_gpRender(_gpFilter(gpSearchBox.text))


# Apply the current UI font size to all statically-created frame controls so they
# stay in sync with the rest of the application.
# 将当前界面字号应用到所有静态创建的框架控件，使其与应用程序其余部分保持同步。
func _gpApplyUIFontSize() -> void:
	var gpSz: int = Settings.gpEffectiveFontSize()
	gpTitle.add_theme_font_size_override("font_size", gpSz)
	gpSearchBox.add_theme_font_size_override("font_size", gpSz)


# React to UI font changes: re-apply font size and re-render the whole list.
# 响应界面字号变化：重新应用字号并重绘整个列表。
func _gpOnFontChanged() -> void:
	_gpApplyUIFontSize()
	_gpRefreshLocale(I18n.gpLocale)


# React to symbol font / size changes: recreate the palette items so they pick up
# the new thumbnail size.
# 响应图元字体/字号变化：重新创建图元条目以采用新的缩略图尺寸。
func _gpOnSymbolStyleChanged() -> void:
	_gpRender(_gpFilter(gpSearchBox.text))


# Emit that a symbol was picked.
# 发出图元被选中信号。
func _gpOnPick(gpTypeId: String) -> void:
	gpSymbolPicked.emit(gpTypeId)


# A library tile crossed the drag threshold. Forwarded verbatim: what a drag MEANS is the host's
# business (arm an attachment), and this dock deliberately knows nothing about mounting.
# 某图元库图块越过了拖动阈值。原样转发：拖动**意味着什么**是宿主的事（给附件上膛），
# 本停靠栏刻意对挂载一无所知。
func _gpOnDragStarted(gpTypeId: String) -> void:
	gpSymbolDragStarted.emit(gpTypeId)


# A palette item requested deletion: forward to the main window, which owns the graphs
# (to cascade-remove canvas instances) and the live library. The local re-render happens
# there via gpPopulate() after the symbol is actually removed.
# 图元条目请求删除：转发给主窗口，由它持有图（级联清理画布实例）与活动图元库。本地重渲染
# 在图元确实被移除后由主窗口经 gpPopulate() 完成。
func _gpOnDeleteRequested(gpId: String) -> void:
	gpSymbolDeleteRequested.emit(gpId)


# 视觉分层：左停靠栏显式刷 DOCK 背景（受控的深色档），接缝发丝线由顶层叠加层绘制。
# Visual layering: paint the left dock's controlled DOCK background; the seam hairline is
# drawn by the top overlay. _draw() content sits beneath child controls.
func _draw() -> void:
	GPChromeStyle.gpDraw(self, GPChromeStyle.GP_DOCK_BG, 0)
