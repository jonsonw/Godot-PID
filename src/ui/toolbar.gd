class_name GPPIDToolbar
extends VBoxContainer

# Left symbol-library dock. The FRAME is built once here (title + search box +
# scroll container + tool group); the symbol BUTTONS are injected by code from
# SymbolLibrary so custom symbol packs drop in without touching the layout.
# 左侧图元库停靠栏。框架在此一次性搭好（标题 + 搜索框 + 滚动容器 + 工具组）；
# 图元按钮由代码按类目从 SymbolLibrary 注入，自定义图元包无需改布局即可接入。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# A symbol was picked from the library (its type id).
# 从图元库选中某图元（返回其 type id）。
signal gpSymbolPicked(type: String)

# A tool was selected: "select" / "connect" / "custom".
# 选中某工具：select（选择）/ connect（连线）/ custom（自定义图元）。
signal gpToolSelected(type: String)

# Currently displayed symbol definitions.
# 当前显示的图元定义。
var gpDefs: Array[GPSymbolDef] = []

# Per-category collapse state (true = folded). Preserved across search / locale re-renders.
# 每个类目的折叠状态（true = 已折叠）。在搜索 / 语言切换的重渲染中保持不变。
var gpCollapsed: Dictionary = {}

# Live list of per-category thumbnail grids; columns are recomputed on dock resize.
# 每个类目的缩略图网格实时列表；列数随停靠栏缩放重算。
var gpGrids: Array[GPSymbolGrid] = []

# Title label at the top of the dock.
# 停靠栏顶部标题标签。
var gpTitle: Label

# Search input box.
# 搜索输入框。
var gpSearchBox: LineEdit

# Scroll container that holds the symbol list.
# 承载图元列表的滚动容器。
var gpListRoot: ScrollContainer

# Select tool button.
# 选择工具按钮。
var gpSelBtn: Button

# Connect tool button.
# 连线工具按钮。
var gpConBtn: Button

# Custom symbol tool button.
# 自定义图元工具按钮。
var gpCustBtn: Button


# Build the static frame of the dock.
# 构建停靠栏的静态框架。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP

	# ---- frozen frame: title ----
	# ---- 固化框架：标题 ----
	gpTitle = Label.new()
	add_child(gpTitle)

	# ---- frozen frame: search box ----
	# ---- 固化框架：搜索框 ----
	gpSearchBox = LineEdit.new()
	gpSearchBox.text_changed.connect(_gpOnSearch)
	add_child(gpSearchBox)

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
	gpListRoot.resized.connect(_gpReflow)
	add_child(gpListRoot)

	# ---- frozen frame: tool group ----
	# ---- 固化框架：工具组 ----
	var gpTools: HBoxContainer = HBoxContainer.new()
	# Cap each tool button's minimum width and clip its label when the dock is narrow,
	# so the three buttons stay below the dock floor (160px). At a wide dock the buttons
	# expand and show the full label; when shrunk, the label is clipped gracefully
	# (e.g. "自定义" -> "自定"). This lets the left dock shrink to its declared minimum
	# instead of being stretched by the button text widths.
	# 给每个工具按钮设最小宽度上限并在停靠栏变窄时裁剪标签，使三个按钮低于停靠栏
	# 下限(160px)。停靠栏宽时按钮拉伸显示完整标签；变窄时标签优雅截断（如「自定义」
	# →「自定」）。从而左停靠栏能收缩到声明的最小宽度，而不被按钮文字宽度撑开。
	const gpToolMinPx: float = 44.0
	gpSelBtn = Button.new()
	gpSelBtn.size_flags_horizontal = SIZE_EXPAND_FILL
	gpSelBtn.clip_text = true
	gpSelBtn.custom_minimum_size.x = gpToolMinPx
	gpConBtn = Button.new()
	gpConBtn.size_flags_horizontal = SIZE_EXPAND_FILL
	gpConBtn.clip_text = true
	gpConBtn.custom_minimum_size.x = gpToolMinPx
	gpCustBtn = Button.new()
	gpCustBtn.size_flags_horizontal = SIZE_EXPAND_FILL
	gpCustBtn.clip_text = true
	gpCustBtn.custom_minimum_size.x = gpToolMinPx
	gpSelBtn.pressed.connect(func(): gpToolSelected.emit("select"))
	gpConBtn.pressed.connect(func(): gpToolSelected.emit("connect"))
	gpCustBtn.pressed.connect(func(): gpToolSelected.emit("custom"))
	gpTools.add_child(gpSelBtn)
	gpTools.add_child(gpConBtn)
	gpTools.add_child(gpCustBtn)
	add_child(gpTools)

	I18n.gpLocaleChanged.connect(_gpRefreshLocale)
	_gpRefreshLocale(I18n.gpLocale)


# Inject symbols grouped by category. Call once after assigning the def set.
# 按类目注入图元。赋值图元集后调用一次。
func gpPopulate(gpDefsIn: Array[GPSymbolDef]) -> void:
	gpDefs = gpDefsIn
	_gpRender(gpDefs)


# React to search text changes.
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


# Render the injected symbol list, grouped by category with a collapsible header per group.
# 渲染注入的图元列表，按类目分组，每类目一个可折叠标题；缩略图用 GPSymbolGrid 多列自适应排布。
func _gpRender(gpList: Array[GPSymbolDef]) -> void:
	# Clear previous list.
	# 清空旧列表。
	for gpC in gpListRoot.get_children():
		gpListRoot.remove_child(gpC)
		gpC.queue_free()
	gpGrids = []

	var gpVbox: VBoxContainer = VBoxContainer.new()
	gpVbox.size_flags_horizontal = SIZE_FILL
	gpListRoot.add_child(gpVbox)

	# Group symbols by category.
	# 按类目对图元分组。
	var gpByCat: Dictionary = {}
	for gpD in gpList:
		if not gpByCat.has(gpD.gpCategory):
			gpByCat[gpD.gpCategory] = []
		gpByCat[gpD.gpCategory].append(gpD)

	# One collapsible group per category.
	# 每个类目一个可折叠分组。
	for gpCat in gpByCat.keys():
		if not gpCollapsed.has(gpCat):
			gpCollapsed[gpCat] = false
		var gpCollapsedNow: bool = gpCollapsed[gpCat]

		var gpGroup: VBoxContainer = VBoxContainer.new()
		gpGroup.size_flags_horizontal = SIZE_FILL
		gpGroup.add_theme_constant_override("separation", 2)
		gpVbox.add_child(gpGroup)

		# Clickable category header: toggles the group when pressed.
		# 可点击的类目标题：点击折叠 / 展开本组。
		var gpHeader: Button = Button.new()
		gpHeader.size_flags_horizontal = SIZE_FILL
		gpHeader.alignment = HORIZONTAL_ALIGNMENT_LEFT
		gpHeader.flat = true
		gpHeader.text = ("▾ " if not gpCollapsedNow else "▸ ") + I18n.gpTr(gpCat)
		gpGroup.add_child(gpHeader)

		# Multi-column, width-adaptive thumbnail grid. Its minimum width is forced
		# to the viewport width by _gpReflow so it always fills and re-derives its
		# column count from the real width (see symbol_grid.gd).
		# 多列、随宽度自适应的缩略图网格。其最小宽由 _gpReflow 强制设为视口宽，
		# 从而始终填满并按真实宽度重排列数（见 symbol_grid.gd）。
		var gpGrid: GPSymbolGrid = GPSymbolGrid.new()
		gpGrid.size_flags_horizontal = SIZE_FILL
		gpGrid.visible = not gpCollapsedNow
		gpGroup.add_child(gpGrid)
		gpGrids.append(gpGrid)

		for gpD in gpByCat[gpCat]:
			var gpItem: GPSymbolPaletteItem = GPSymbolPaletteItem.new()
			gpItem.gpDef = gpD
			gpItem.size_flags_horizontal = SIZE_EXPAND_FILL
			gpItem.gpPicked.connect(_gpOnPick)
			gpGrid.add_child(gpItem)

		gpHeader.pressed.connect(_gpToggleCategory.bind(gpCat, gpGrid, gpHeader))

	# Recompute columns now that grids exist (size may be 0 yet; resize handler refreshes later).
	# 网格已建好，先按当前视口重排一次（此时尺寸可能仍为 0，缩放处理器之后会再刷新）。
	_gpReflow(-1.0)


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
func _gpReflow(gpForcedWidth: float = -1.0) -> void:
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


# Toggle a category group's collapsed state and update the header arrow.
# 切换某类目分组的折叠状态并更新标题箭头。
func _gpToggleCategory(gpCat: String, gpGrid: GPSymbolGrid, gpHeader: Button) -> void:
	var gpNow: bool = not gpCollapsed.get(gpCat, false)
	gpCollapsed[gpCat] = gpNow
	gpGrid.visible = not gpNow
	gpHeader.text = ("▾ " if not gpNow else "▸ ") + I18n.gpTr(gpCat)


# Refresh all locale-dependent texts.
# 刷新所有依赖语言的文本。
func _gpRefreshLocale(gpLocale: String) -> void:
	gpTitle.text = I18n.gpTr("symbol_lib.title")
	gpSearchBox.placeholder_text = I18n.gpTr("symbol_lib.search")
	gpSelBtn.text = I18n.gpTr("symbol_lib.tool_select")
	gpConBtn.text = I18n.gpTr("symbol_lib.tool_connect")
	gpCustBtn.text = I18n.gpTr("symbol_lib.tool_custom")
	_gpRender(_gpFilter(gpSearchBox.text))


# Emit that a symbol was picked.
# 发出图元被选中信号。
func _gpOnPick(gpTypeId: String) -> void:
	gpSymbolPicked.emit(gpTypeId)
