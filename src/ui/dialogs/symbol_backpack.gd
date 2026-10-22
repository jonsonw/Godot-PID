class_name GPSymbolBackpack
extends PopupPanel
# Copyright © 2026 Jonson Wang
#
# The symbol "backpack" (A11): press B, search, pick — or drag a symbol straight onto the sheet.
# 图元「背包」（A11）：按 B、搜索、选中 —— 或把图元直接拖到图纸上。
#
# Why a separate popup and not the left palette / 为何独立弹窗而非复用左栏库：
# The left palette is a permanent BROWSER (categories, scrolling, a place for hundreds of symbols).
# The backpack is a TRANSIENT launcher: it opens over the canvas, remembers what you touched last,
# and gets out of the way. Merging them would force one of the two jobs onto the other's surface.
# 左栏图库是常驻的**浏览**面（分类、滚动、容纳数百图元）。背包是**临时**发射器：浮在画布上、
# 记得你上次动过什么、随即让开。把两者合并，只会把其中一项职责硬塞进另一项的表面。
#
# Ordering rule (and why) / 排序规则（以及为什么）:
# favorites first, then recents, then everything else — and within each group the library order is
# kept. "Last used" is the fastest predictor of "next used" in a drafting session, so it must beat
# alphabetical; library order is stable, so nothing jumps around between openings.
# 收藏优先，其次最近，最后其余 —— 组内保持图库顺序。制图过程中「上次用过的」是「下次要用的」最好
# 预测，故必须优先于字母序；图库顺序稳定，故两次打开之间不会有东西乱跳。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# A symbol was chosen (clicked). The shell places it at the view centre.
# 某图元被选中（单击）。外壳把它放到视图中心。
signal gpSymbolChosen(gpId: String)

# How many "recent" entries to remember. Eight fits one row of the grid at every zoom without
# pushing the actual list below the fold.
# 记住多少条「最近」。八个在任何缩放下都放得下一行，不会把真正的列表挤到折叠线以下。
const GP_RECENT_CAP: int = 8

# Every symbol the backpack can offer, library order.
# 背包可提供的全部图元，按图库顺序。
var _gpAll: Array[GPSymbolDef] = []

# Favorite symbol ids, in the order they were favourited.
# 收藏的图元 id，按收藏先后。
var _gpFavorites: Array[String] = []

# Recently used symbol ids, most recent first.
# 最近使用的图元 id，最新的在前。
var _gpRecents: Array[String] = []

var _gpSearch: LineEdit = null
var _gpList: VBoxContainer = null
var _gpScroll: ScrollContainer = null


# Build the widgets. Call once, before gpOpen().
# 构建控件。在 gpOpen() 之前调用一次。
func gpBuild() -> void:
	var gpBox: VBoxContainer = VBoxContainer.new()
	gpBox.add_theme_constant_override("separation", 6)
	var gpTitle: Label = Label.new()
	gpTitle.text = I18n.gpTr("bag.title")
	gpTitle.add_theme_font_size_override("font_size", 14)
	gpBox.add_child(gpTitle)
	_gpSearch = LineEdit.new()
	_gpSearch.placeholder_text = I18n.gpTr("bag.search")
	_gpSearch.clear_button_enabled = true
	# Filter on every keystroke: the list is small enough that a debounce would only add latency.
	# 每次按键都过滤：列表足够小，防抖只会增加延迟。
	_gpSearch.text_changed.connect(func(_gpT: String) -> void: gpRefresh())
	gpBox.add_child(_gpSearch)
	_gpScroll = ScrollContainer.new()
	_gpScroll.custom_minimum_size = Vector2(360.0, 320.0)
	_gpScroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gpBox.add_child(_gpScroll)
	_gpList = VBoxContainer.new()
	_gpList.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gpList.add_theme_constant_override("separation", 2)
	_gpScroll.add_child(_gpList)
	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("bag.hint")
	gpHint.modulate = Color(0.6, 0.6, 0.65)
	gpBox.add_child(gpHint)
	add_child(gpBox)


# Set the symbol pool (and the persisted favorite / recent lists).
# 设置图元池（以及持久化的收藏 / 最近列表）。
func gpSetSymbols(gpDefs: Array[GPSymbolDef], gpFavorites: Array[String],
		gpRecents: Array[String]) -> void:
	_gpAll = gpDefs.duplicate()
	_gpFavorites = gpFavorites.duplicate()
	_gpRecents = gpRecents.duplicate()


# Show the panel with a fresh list and focus in the search box.
# 以最新列表显示面板，并把焦点放进搜索框。
func gpOpen() -> void:
	gpRefresh()
	popup_centered()
	# Focus AFTER the popup is visible: a LineEdit grabbed focus while hidden keeps it only
	# intermittently on some platforms.
	# **弹出后**再取焦点：隐藏时抓焦点的 LineEdit 在某些平台上只能间歇保持。
	_gpSearch.grab_focus()
	_gpSearch.select_all()


# Remember that a symbol was just used (most recent first, de-duplicated, capped).
# 记住某图元刚被使用（最新在前、去重、封顶）。
func gpNoteUsed(gpId: String) -> void:
	_gpRecents = gpPushRecent(_gpRecents, gpId)


# Whether a symbol is a favorite.
# 某图元是否被收藏。
func gpIsFavorite(gpId: String) -> bool:
	return _gpFavorites.has(gpId)


# Toggle the favorite flag and rebuild (the right-click action).
# 切换收藏标志并重建（右键动作）。
func gpToggleFavorite(gpId: String) -> void:
	if _gpFavorites.has(gpId):
		_gpFavorites.erase(gpId)
	else:
		_gpFavorites.append(gpId)
	gpRefresh()


# Rebuild the item list from the current filter and ordering.
# 依据当前过滤与排序重建条目列表。
func gpRefresh() -> void:
	if _gpList == null:
		return
	for gpC in _gpList.get_children():
		_gpList.remove_child(gpC)
		gpC.queue_free()
	var gpQuery: String = _gpSearch.text if _gpSearch != null else ""
	var gpFiltered: Array[GPSymbolDef] = gpFilter(_gpAll, gpQuery, _gpFavorites, _gpRecents)
	if gpFiltered.is_empty():
		var gpEmpty: Label = Label.new()
		gpEmpty.text = I18n.gpTr("bag.empty")
		gpEmpty.modulate = Color(0.6, 0.6, 0.65)
		_gpList.add_child(gpEmpty)
		return
	for gpDef in gpFiltered:
		_gpList.add_child(_gpMakeItem(gpDef))


# One clickable row: name + (favorite star) + drag source.
# 一行可点条目：名称 +（收藏星标）+ 拖拽源。
func _gpMakeItem(gpDef: GPSymbolDef) -> Button:
	var gpBtn: Button = Button.new()
	var gpStar: String = "★ " if gpIsFavorite(gpDef.gpId) else ""
	gpBtn.text = "%s%s" % [gpStar, I18n.gpTr(gpDef.gpDisplayName, gpDef.gpDisplayName)]
	gpBtn.tooltip_text = "%s\n%s" % [gpDef.gpId, I18n.gpTr("bag.hint")]
	gpBtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Left-click chooses (places at the view centre); the DRAG payload is the same id, so both
	# gestures end in one place intent on the canvas.
	# 左键选中（放到视图中心）；**拖拽**载荷是同一个 id，故两种手势最终都落到画布上的同一个放置意图。
	gpBtn.pressed.connect(func() -> void: _gpChoose(gpDef.gpId))
	var gpId: String = gpDef.gpId
	gpBtn.set_drag_forwarding(
		func(_gpAt: Vector2) -> Variant: return {"symbol_id": gpId, "source": "backpack"},
		Callable(), Callable())
	gpBtn.gui_input.connect(func(gpEvent: InputEvent) -> void:
		if gpEvent is InputEventMouseButton:
			var gpMB: InputEventMouseButton = gpEvent as InputEventMouseButton
			if gpMB.pressed and gpMB.button_index == MOUSE_BUTTON_RIGHT:
				gpToggleFavorite(gpId))
	return gpBtn


func _gpChoose(gpId: String) -> void:
	gpNoteUsed(gpId)
	hide()
	gpSymbolChosen.emit(gpId)


# ---------------------------------------------------------------------------
# Pure helpers (static so they can be pinned without a popup)
# 纯函数助手（static，故无需弹窗即可钉住）
# ---------------------------------------------------------------------------

# Filter by query and order by favorites -> recents -> rest, preserving library order inside each
# group. Case-insensitive match against the id, the display name, and the category: a user hunting
# for "阀门" should not have to know the id, and one hunting for "valve" should not have to know
# the Chinese display name.
# 按查询过滤，并按 收藏 → 最近 → 其余 排序，组内保持图库顺序。对 id、显示名与类目做大小写不敏感
# 匹配：找「阀门」的人不该需要知道 id，找 "valve" 的人也不该需要知道中文显示名。
static func gpFilter(gpDefs: Array[GPSymbolDef], gpQuery: String, gpFavorites: Array[String],
		gpRecents: Array[String]) -> Array[GPSymbolDef]:
	var gpQ: String = gpQuery.strip_edges().to_lower()
	var gpFavHits: Array[GPSymbolDef] = []
	var gpRecentHits: Array[GPSymbolDef] = []
	var gpRest: Array[GPSymbolDef] = []
	for gpDef in gpDefs:
		if gpDef == null:
			continue
		if gpQ != "" and not _gpMatches(gpDef, gpQ):
			continue
		if gpFavorites.has(gpDef.gpId):
			gpFavHits.append(gpDef)
		elif gpRecents.has(gpDef.gpId):
			gpRecentHits.append(gpDef)
		else:
			gpRest.append(gpDef)
	var gpOut: Array[GPSymbolDef] = []
	gpOut.append_array(gpFavHits)
	# Recents are ordered by the RECENTS list (most recent first), not by library order — that is
	# the whole point of keeping the list.
	# 最近组按**最近列表**排序（最新在前），而不是图库顺序 —— 那正是保留该列表的意义。
	for gpId in gpRecents:
		for gpDef in gpRecentHits:
			if gpDef.gpId == gpId and not gpOut.has(gpDef):
				gpOut.append(gpDef)
	for gpDef in gpRecentHits:
		if not gpOut.has(gpDef):
			gpOut.append(gpDef)
	gpOut.append_array(gpRest)
	return gpOut


static func _gpMatches(gpDef: GPSymbolDef, gpLowerQuery: String) -> bool:
	if gpDef.gpId.to_lower().contains(gpLowerQuery):
		return true
	if gpDef.gpDisplayName.to_lower().contains(gpLowerQuery):
		return true
	if gpDef.gpCategory.to_lower().contains(gpLowerQuery):
		return true
	# The localized display name is what the row actually SHOWS, so it must be searchable too.
	# 本地化显示名才是行里**实际显示**的文字，故也必须可搜。
	var gpTr: String = I18n.gpTr(gpDef.gpDisplayName, gpDef.gpDisplayName)
	return gpTr.to_lower().contains(gpLowerQuery)


# Push an id onto a most-recent-first list: de-duplicate, then cap.
# 把一个 id 推到「最新在前」的列表：先去重，再封顶。
static func gpPushRecent(gpList: Array[String], gpId: String) -> Array[String]:
	var gpOut: Array[String] = [gpId]
	for gpOld in gpList:
		if gpOld != gpId and not gpOut.has(gpOld):
			gpOut.append(gpOld)
		if gpOut.size() >= GP_RECENT_CAP:
			break
	return gpOut
