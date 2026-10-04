extends "res://tests/gp_test.gd"
# Guards the i18n keys that reach the UI through STATIC SPEC TABLES rather than literal
# gpTr("...") call sites. gpTr() falls back to the RAW KEY TEXT when a key is missing, so a
# stale id never raises an error — it silently prints "ribbon.grp_draw" on a button.
#
# Why a literal scan cannot cover this: these tables feed keys in as VARIABLES
# (gpTr(gpCat), gpTr(str(gpItem["key"]))), so the only checkable place is the DATA SOURCE.
# History: the tool-block header kept the id "ribbon.grp_draw" after GPPIDRibbon was removed
# in 2026-09-26; the key was deleted with the component but the reference was not, and every
# gate stayed green because no test reads UI text.
#
# 校验经**静态定义表**（而非字面量 gpTr("...") 调用点）进入界面的 i18n 键。
# gpTr() 在键缺失时回退为**裸键名**，故过时 id 从不报错 —— 它只会把
# "ribbon.grp_draw" 静默显示到按钮上。
# 为什么字面量扫描覆盖不到：这些表把键作为**变量**传入（gpTr(gpCat)、gpTr(str(gpItem["key"]))），
# 因此唯一可校验之处是**数据源本身**。
# 历史：2026-09-26 移除 GPPIDRibbon 后，工具块标题仍保留 id "ribbon.grp_draw" ——
# 键随组件被删而引用未删；由于没有测试读取界面文案，所有门禁照绿。

# Key prefixes belonging to components that no longer exist. A key must never be named after
# a dead component: gpTr()'s silent fallback turns such an id into user-visible raw text.
# 已移除组件的键前缀。键绝不可以按死组件命名：gpTr() 的静默回退会把这种 id 变成用户可见的裸文本。
const GP_DEAD_DOMAINS: Array[String] = ["ribbon."]


# Tool block headers + their items (left symbol dock).
# 工具块标题及其条目（左侧图元库）。
func gpTestToolBlockKeysBilingual() -> void:
	for gpBlock in GPPIDToolbar.GP_TOOL_BLOCKS:
		var gpB: Dictionary = gpBlock as Dictionary
		_gpAssertKey(str(gpB.get("title_key", "")), "toolbar block title")
		for gpItem in gpB.get("items", []):
			var gpI: Dictionary = gpItem as Dictionary
			_gpAssertKey(str(gpI.get("key", "")), "toolbar item")


# Quick command bar items + their nested submenu rows (entries may be null = separator).
# 顶部快捷命令条条目及其嵌套子菜单行（元素可能为 null = 分隔符）。
func gpTestQuickBarKeysBilingual() -> void:
	for gpEntry in GPPIDQuickToolbar.GP_ITEMS:
		if gpEntry == null:
			continue
		var gpE: Dictionary = gpEntry as Dictionary
		_gpAssertKey(str(gpE.get("key", "")), "quick bar item")
		var gpMenu: Array = gpE.get("menu", []) as Array
		for gpRow in gpMenu:
			if gpRow == null:
				continue
			var gpR: Array = gpRow as Array
			if gpR.is_empty():
				continue
			_gpAssertKey(str(gpR[0]), "quick bar submenu")


# Menu rows in the menu bar: each row is a [label_key, action] pair.
# 菜单栏中的菜单行：每行是 [标签键, 动作] 的二元组。
# Why this is checked HERE and not only in the DEXPI tests: a menu label is the most visible
# text in the app, and a missing key shows the RAW KEY where the user cannot miss it. The menu
# bar is also the place new entries get added without anyone thinking about i18n.
# 为何**在此**检查而不只在 DEXPI 测试里检查：菜单标签是应用中最显眼的文字，
# 而缺失的键会把裸键名显示在用户无法忽视的地方。菜单栏也正是「新增条目时
# 没人会想到 i18n」的地方。
func gpTestMenuRowKeysBilingual() -> void:
	var gpKeys: Array[String] = []
	_gpCollectRowKeys(GPPIDMenuBar.GP_MENUS, gpKeys)
	gpCheck(gpKeys.size() >= 10, "menu rows were collected: " + str(gpKeys.size()))
	for gpKey in gpKeys:
		_gpAssertKey(gpKey, "menu row")


static func _gpCollectRowKeys(gpV: Variant, gpOut: Array[String]) -> void:
	if gpV is Array:
		var gpA: Array = gpV as Array
		if gpA.size() == 2 and (gpA[0] is String) and (gpA[1] is String):
			gpOut.append(str(gpA[0]))
			return
		for gpX in gpA:
			_gpCollectRowKeys(gpX, gpOut)
	elif gpV is Dictionary:
		for gpK in (gpV as Dictionary).values():
			_gpCollectRowKeys(gpK, gpOut)


# P2 主图元 / 次级图元 的**字面量**键（上下文菜单子菜单、工具与命令的拒绝原因）。
# 这些键不经静态定义表，故上面的表扫描覆盖不到 —— 在此显式钉住，
# 以免文件头部记载的「组件已删、引用仍在」那类静默缺陷重演。
# Literal keys of the P2 mounting feature (the context-menu submenu plus the refusal reasons of
# the tool and the commands). They do not flow through a static spec table, so the scans above
# cannot reach them; pinning them here keeps the silent-raw-key defect of the header from returning.
#
# The two refusal keys are pinned in their RESOLVED form ON PURPOSE. The command and the tool store
# only the PREFIX-FREE token and GPCanvasEditFacade.gpReportRefusal() adds the "attach." namespace.
# Pinning "attach.no_host" — rather than "no_host" — is therefore exactly what catches a namespace
# applied twice, which would resolve to a missing key and print the raw text to the status bar.
# 两条拒绝键刻意按**解析后**的形态钉住。命令与工具只存**不带前缀**的记号，
# 由 GPCanvasEditFacade.gpReportRefusal() 添加 "attach." 命名空间。
# 故钉住 "attach.no_host"（而非 "no_host"），正是能抓住「命名空间被加了两次」的那道钉子 ——
# 那会解析到一个缺失的键，并把裸文本打印到状态栏。
func gpTestAttachFeatureKeysBilingual() -> void:
	var gpKeys: Array[String] = [
		"canvas.ctx_attach",
		"canvas.ctx_attach_no_room",
		"canvas.ctx_detach",
		"attach.no_host",
		"attach.no_anchor",
	]
	for gpKey in gpKeys:
		_gpAssertKey(gpKey, "P2 attach feature")


# Keys reached through the toolbar's STATIC group constants rather than a literal gpTr("...") call
# site — the exact blind spot this suite exists for. P3 turned the left dock into two top-level
# groups; if one of these keys went missing, the dock would print "symbol_lib.grp_primary" over the
# library and every gate would stay green.
# 经工具栏的**静态分组常量**（而非字面量 gpTr("...") 调用点）抵达的键 —— 正是本套件存在的意义所指的
# 盲区。P3 把左停靠栏改成两个顶层分组；若其中一个键缺失，停靠栏上会打印出
# "symbol_lib.grp_primary"，而所有门禁照绿。
#
# Both the constants AND their being referenced by the render path are pinned: a constant that no
# longer appears in GPToolbar.GP_GRP_PRIMARY / GP_GRP_ATTACH is dead text.
# 常量本身**以及**它被渲染路径引用这件事都要钉住：不再出现在 GPToolbar.GP_GRP_PRIMARY /
# GP_GRP_ATTACH 中的常量就是死文本。
func gpTestPaletteGroupKeysBilingual() -> void:
	_gpAssertKey(GPPIDToolbar.GP_GRP_PRIMARY, "palette top-level group")
	_gpAssertKey(GPPIDToolbar.GP_GRP_ATTACH, "palette top-level group")
	# The two groups must be distinct, or the split would silently collapse into one list.
	gpCheck(GPPIDToolbar.GP_GRP_PRIMARY != GPPIDToolbar.GP_GRP_ATTACH,
		"the two palette groups have distinct keys")
	# The drag status messages (P3 mode 1) are routed through gpSetState() with a format arg.
	_gpAssertKey("status.attach_armed", "P3 palette drag status")
	_gpAssertKey("status.attach_not_mountable", "P3 palette drag status")


# Label anchor dropdown rows in the inspector.
# 属性面板中的标签锚点下拉选项。
func gpTestAnchorRowKeysBilingual() -> void:
	for gpRow in GPInspector.gpAnchorRows():
		var gpR: Dictionary = gpRow as Dictionary
		_gpAssertKey(str(gpR.get("key", "")), "anchor row")


# One key must be present in GP_STRINGS with non-empty zh AND en, and must not live in a
# dead component's naming domain. Failures name the key so the fix is a one-line edit.
# 单个键必须存在于 GP_STRINGS 且 zh 与 en 均非空，且不得位于死组件的命名域。
# 失败信息直接给出键名，使修复是一次单行编辑。
func _gpAssertKey(gpKey: String, gpWhere: String) -> void:
	gpCheck(gpKey != "", "non-empty i18n key in " + gpWhere)
	for gpDomain in GP_DEAD_DOMAINS:
		gpCheck(not gpKey.begins_with(gpDomain),
			"i18n key must not use a removed component's domain: " + gpKey)
	var gpMap: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
	gpCheck(not gpMap.is_empty(), "i18n key present in GP_STRINGS (" + gpWhere + "): " + gpKey)
	gpCheck(str(gpMap.get("zh", "")) != "", "zh non-empty for " + gpKey)
	gpCheck(str(gpMap.get("en", "")) != "", "en non-empty for " + gpKey)
