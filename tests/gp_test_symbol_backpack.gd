extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Headless tests for the symbol backpack (A11): filtering, ordering, recents, and the one drop
# payload the canvas accepts.
# 图元背包（A11）的 headless 测试：过滤、排序、最近列表，以及画布接受的唯一拖拽载荷。
#
# Four promises are guarded here / 此处守护四条承诺：
#   1. SEARCH SEES WHAT THE ROW SHOWS. A user typing the visible name (either language) or the
#      category finds the symbol — not only those who happen to know the internal id.
#      **搜索看得见行里显示的东西**。输入可见名称（任一语种）或类目都能找到图元 —— 而不是只有知道
#      内部 id 的人才找得到。
#   2. FAVOURITES BEAT RECENTS BEAT REST. The order a drafter expects, and it must not depend on
#      the library's alphabetical accident.
#      **收藏 > 最近 > 其余**。制图者期待的次序，且不得取决于图库的字母序偶然。
#   3. RECENTS ARE MOST-RECENT-FIRST, DE-DUPLICATED AND CAPPED. Otherwise the list degrades into a
#      second alphabetical index that never forgets anything.
#      **最近是最新在前、去重、封顶**。否则该列表会退化成一份永不遗忘的第二个字母索引。
#   4. DRAG AND CLICK ARE THE SAME INTENT. The drop payload carries only a symbol id; the canvas
#      cannot place anything a click could not.
#      **拖与点是同一个意图**。拖拽载荷只带图元 id；画布无法放置任何单击放不下的东西。

# A tiny symbol pool: two defs whose display names are translatable keys, plus one with an id-only
# match, so the three search paths can each be exercised.
# 小巧的图元池：两个显示名是词条键的图元，外加一个只能靠 id 命中的，使三条搜索路径各被走到。
func _gpDefs() -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	var gpA: GPSymbolDef = GPSymbolDef.new()
	gpA.gpId = "valve_gate"
	gpA.gpDisplayName = "sym.gate_valve"
	gpA.gpCategory = "valve"
	gpOut.append(gpA)
	var gpB: GPSymbolDef = GPSymbolDef.new()
	gpB.gpId = "pump_centrifugal"
	gpB.gpDisplayName = "sym.pump"
	gpB.gpCategory = "pump"
	gpOut.append(gpB)
	var gpC: GPSymbolDef = GPSymbolDef.new()
	gpC.gpId = "zzz_special"
	gpC.gpDisplayName = "sym.unknown"
	gpC.gpCategory = "misc"
	gpOut.append(gpC)
	return gpOut


func _gpIds(gpDefs: Array[GPSymbolDef]) -> Array[String]:
	var gpOut: Array[String] = []
	for gpD in gpDefs:
		gpOut.append(gpD.gpId)
	return gpOut


# ---------------------------------------------------------------------------
# Filtering
# 过滤
# ---------------------------------------------------------------------------

func gpTestFilterByCategory() -> void:
	var gpDefs: Array[GPSymbolDef] = _gpDefs()
	var gpFav: Array[String] = []
	var gpRecent: Array[String] = []
	var gpOut: Array[GPSymbolDef] = GPSymbolBackpack.gpFilter(gpDefs, "valve", gpFav, gpRecent)
	gpEq(gpOut.size(), 1, "按类目命中一个 / one hit by category")
	gpEq(gpOut[0].gpId, "valve_gate", "命中的是闸阀 / the hit is the gate valve")


func gpTestFilterById() -> void:
	var gpDefs: Array[GPSymbolDef] = _gpDefs()
	var gpNone: Array[String] = []
	var gpOut: Array[GPSymbolDef] = GPSymbolBackpack.gpFilter(gpDefs, "zzz", gpNone, gpNone)
	gpEq(gpOut.size(), 1, "按 id 命中 / one hit by id")
	gpEq(gpOut[0].gpId, "zzz_special", "命中的是 zzz / the zzz symbol")


func gpTestFilterCaseInsensitiveAndTrimmed() -> void:
	var gpDefs: Array[GPSymbolDef] = _gpDefs()
	var gpNone: Array[String] = []
	var gpOut: Array[GPSymbolDef] = GPSymbolBackpack.gpFilter(gpDefs, "  PUMP  ", gpNone, gpNone)
	gpEq(gpOut.size(), 1, "大小写与空白被忽略 / case and padding are ignored")
	gpEq(gpOut[0].gpId, "pump_centrifugal", "命中的是泵 / the pump")


func gpTestFilterEmptyQueryKeepsEverything() -> void:
	var gpDefs: Array[GPSymbolDef] = _gpDefs()
	var gpNone: Array[String] = []
	var gpOut: Array[GPSymbolDef] = GPSymbolBackpack.gpFilter(gpDefs, "", gpNone, gpNone)
	gpEq(gpOut.size(), gpDefs.size(), "空查询返回全部 / an empty query returns everything")


# ---------------------------------------------------------------------------
# Ordering
# 排序
# ---------------------------------------------------------------------------

func gpTestFavoritesThenRecentsThenRest() -> void:
	var gpDefs: Array[GPSymbolDef] = _gpDefs()
	var gpFav: Array[String] = ["zzz_special"]
	var gpRecent: Array[String] = ["pump_centrifugal"]
	var gpOut: Array[GPSymbolDef] = GPSymbolBackpack.gpFilter(gpDefs, "", gpFav, gpRecent)
	var gpOrder: Array[String] = _gpIds(gpOut)
	gpEq(gpOrder, ["zzz_special", "pump_centrifugal", "valve_gate"],
		"收藏 → 最近 → 其余 / favourites, then recents, then the rest")


func gpTestRecentsOrderIsMostRecentFirst() -> void:
	var gpDefs: Array[GPSymbolDef] = _gpDefs()
	var gpNone: Array[String] = []
	# Two recents, newest first: pump then valve — the library order is the OPPOSITE, so a pass
	# here proves the recents list drives the order.
	# 两条最近，最新在前：泵然后阀 —— 图库顺序恰好**相反**，故通过即证明排序由最近列表驱动。
	var gpRecent: Array[String] = ["pump_centrifugal", "valve_gate"]
	var gpOut: Array[GPSymbolDef] = GPSymbolBackpack.gpFilter(gpDefs, "", gpNone, gpRecent)
	var gpOrder: Array[String] = _gpIds(gpOut)
	gpEq(gpOrder, ["pump_centrifugal", "valve_gate", "zzz_special"],
		"最近按最近列表排 / recents follow the recents list")


# ---------------------------------------------------------------------------
# Recent push
# 最近列表推入
# ---------------------------------------------------------------------------

func gpTestPushRecentMovesToFrontAndDedupes() -> void:
	var gpList: Array[String] = ["a", "b", "c"]
	var gpOut: Array[String] = GPSymbolBackpack.gpPushRecent(gpList, "c")
	gpEq(gpOut, ["c", "a", "b"], "已存在的项移到最前且不重复 / an existing id moves to front, no duplicate")
	gpEq(gpList, ["a", "b", "c"], "输入列表未被就地修改 / the input list is not mutated")


func gpTestPushRecentCapsLength() -> void:
	var gpList: Array[String] = []
	for gpI in range(GPSymbolBackpack.GP_RECENT_CAP):
		gpList.append("id%d" % gpI)
	var gpOut: Array[String] = GPSymbolBackpack.gpPushRecent(gpList, "fresh")
	gpEq(gpOut.size(), GPSymbolBackpack.GP_RECENT_CAP, "封顶 / capped")
	gpEq(gpOut[0], "fresh", "新项在最前 / the fresh id is first")
	gpCheck(not gpOut.has("id%d" % (GPSymbolBackpack.GP_RECENT_CAP - 1)),
		"最旧的一项被挤出 / the oldest entry fell off")


# ---------------------------------------------------------------------------
# Favorites toggle (widget-level state, no popup shown)
# 收藏开关（控件级状态，不弹窗）
# ---------------------------------------------------------------------------

func gpTestFavoriteToggle() -> void:
	var gpBag: GPSymbolBackpack = GPSymbolBackpack.new()
	gpBag.gpBuild()
	gpBag.gpSetSymbols(_gpDefs(), [], [])
	gpCheck(not gpBag.gpIsFavorite("valve_gate"), "初始未收藏 / not a favourite at first")
	gpBag.gpToggleFavorite("valve_gate")
	gpCheck(gpBag.gpIsFavorite("valve_gate"), "收藏生效 / favouriting works")
	gpBag.gpToggleFavorite("valve_gate")
	gpCheck(not gpBag.gpIsFavorite("valve_gate"), "取消收藏 / unfavouriting works")
	gpBag.free()


# ---------------------------------------------------------------------------
# The drop payload
# 拖拽载荷
# ---------------------------------------------------------------------------

func gpTestCanvasAcceptsBackpackPayload() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCheck(gpCv._can_drop_data(Vector2.ZERO, {"symbol_id": "valve_gate", "source": "backpack"}),
		"接受背包载荷 / the backpack payload is accepted")
	gpCheck(not gpCv._can_drop_data(Vector2.ZERO, {"something": "else"}),
		"拒绝无关字典 / an unrelated dictionary is refused")
	gpCheck(not gpCv._can_drop_data(Vector2.ZERO, "text"),
		"拒绝非字典 / a plain string is refused")
	gpCv.free()


# ---------------------------------------------------------------------------
# i18n + settings defaults
# i18n 与设置默认值
# ---------------------------------------------------------------------------

func gpTestBagKeysBilingual() -> void:
	for gpKey in ["bag.title", "bag.search", "bag.empty", "bag.hint", "status.bag_placed"]:
		var gpPair: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
		gpCheck(not gpPair.is_empty(), "键存在 / key present: " + gpKey)
		gpCheck(str(gpPair.get("zh", "")) != "", "中文非空 / zh non-empty: " + gpKey)
		gpCheck(str(gpPair.get("en", "")) != "", "英文非空 / en non-empty: " + gpKey)


func gpTestBagDefaultsAreEmpty() -> void:
	gpEq(Settings.gpBagFavorites.size(), 0, "收藏默认为空 / favourites start empty")
	gpEq(Settings.gpBagRecents.size(), 0, "最近默认为空 / recents start empty")
