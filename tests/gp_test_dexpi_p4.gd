extends "res://tests/gp_test.gd"
# P4 acceptance: discoverability and delivery. The registry must be the ONE place that knows
# which formats exist, and the menus must not drift away from it.
# P4 验收：可发现性与交付。注册表必须是**唯一**知道有哪些格式的地方，且菜单不得与它漂移。
#
# The defect this guards against is the one already hit once in this project: a thing exists in
# one list and not in the other, and nothing complains until a user looks at the screen. Here
# the two lists are "what can be exported" (the registry) and "what the user can click" (the
# menus).
# 它防范的缺陷在本项目已经出现过一次：某物存在于一张表而不在另一张，
# 且直到用户看向屏幕之前没有任何东西抱怨。此处这两张表是
# 「可导出什么」（注册表）与「用户能点什么」（菜单）。


static func _gpSheet() -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpName = "P4 Sheet"
	gpSheet.gpWidthMM = 420.0
	gpSheet.gpHeightMM = 297.0
	return gpSheet


static func _gpGraph() -> GPPIDGraph:
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	var gpPump: GPPIDNode = gpGraph.gpNewNode("n1", "DPUMP001", "P-1001", Vector2(100.0, 80.0))
	gpPump.gpUid = "doc-n1"
	gpGraph.gpAddNode(gpPump)
	var gpTank: GPPIDNode = gpGraph.gpNewNode("n2", "DTANK001", "T-1002", Vector2(280.0, 200.0))
	gpTank.gpUid = "doc-n2"
	gpGraph.gpAddNode(gpTank)
	var gpEdge: GPPIDEdge = GPPIDEdge.new()
	gpEdge.gpInstanceId = "e1"
	gpEdge.gpFromRef = {"node_id": "n1", "port_id": "out"}
	gpEdge.gpToRef = {"node_id": "n2", "port_id": "top"}
	gpEdge.gpTag = "PL-1001"
	gpGraph.gpEdges.append(gpEdge)
	return gpGraph


# ---- registry -----------------------------------------------------------

func gpTestRegistryKnowsEveryFormat() -> void:
	var gpKinds: Array[String] = GPExporterRegistry.gpAllKinds()
	gpEq(gpKinds.size(), 4, "project, library, config and dexpi")
	for gpWant in ["project", "library", "config", "dexpi"]:
		gpCheck(GPExporterRegistry.gpIsKnown(gpWant), gpWant + " is registered")


# A menu label that is not in the i18n table shows the RAW KEY to the user — the exact defect
# class already fixed once for the tool-block header.
# 不在 i18n 表中的菜单标签会把**裸键名**显示给用户 ——
# 这正是工具块标题上已经修过的同一类缺陷。
func gpTestEveryRegistryLabelExistsInI18n() -> void:
	for gpKind in GPExporterRegistry.gpAllKinds():
		var gpKey: String = GPExporterRegistry.gpLabelKeyOf(gpKind)
		gpCheck(not gpKey.is_empty(), gpKind + " has a label key")
		gpCheck(not (I18n.GP_STRINGS.get(gpKey, {}) as Dictionary).is_empty(),
			"label key present in GP_STRINGS: " + gpKey)
		var gpMap: Dictionary = I18n.GP_STRINGS.get(gpKey, {}) as Dictionary
		gpCheck(str(gpMap.get("zh", "")) != "", "zh non-empty for " + gpKey)
		gpCheck(str(gpMap.get("en", "")) != "", "en non-empty for " + gpKey)


func gpTestDexpiDeclaresItsNeeds() -> void:
	gpCheck(GPExporterRegistry.gpNeedsSheet(GPExporterRegistry.GP_DEXPI),
		"DEXPI declares that it needs a sheet (it writes a Diagram extent)")
	gpCheck(not GPExporterRegistry.gpNeedsSheet(GPExporterRegistry.GP_PROJECT),
		"the project container needs no sheet")
	gpEq(GPExporterRegistry.gpExtensionOf(GPExporterRegistry.GP_DEXPI), "pid.xml",
		"DEXPI ships as .pid.xml")


# The file dialog must offer the RIGHT filter per format. This defect shipped once: the dialog
# kept its startup filter (*.pid.json) for every export kind, so the DEXPI menu entry existed
# but could not be saved under its own extension. The registry is the single source the dialog
# reads, so the contract is pinned here: extension -> pattern -> label, all present.
# 文件对话框必须为每种格式提供**正确**的过滤器。此缺陷曾真实发生：对话框对所有导出
# 都沿用启动时的过滤器（*.pid.json），于是 DEXPI 菜单项存在、却无法按自身扩展名保存。
# 注册表是对话框读取的唯一来源，故在此钉死契约：扩展名 -> 通配符 -> 标签，全部齐备。
func gpTestEveryRegistryFormatHasADialogFilter() -> void:
	for gpKind in GPExporterRegistry.gpAllKinds():
		var gpExt: String = GPExporterRegistry.gpExtensionOf(gpKind)
		gpCheck(not gpExt.is_empty(), gpKind + " declares an extension")
		gpEq(GPExporterRegistry.gpFilterPatternOf(gpKind), "*." + gpExt,
			gpKind + " filter pattern follows its extension")
		var gpKey: String = GPExporterRegistry.gpFilterKeyOf(gpKind)
		gpCheck(not gpKey.is_empty(), gpKind + " has a filter label key")
		var gpMap: Dictionary = I18n.GP_STRINGS.get(gpKey, {}) as Dictionary
		gpCheck(str(gpMap.get("zh", "")) != "", "zh non-empty for " + gpKey)
		gpCheck(str(gpMap.get("en", "")) != "", "en non-empty for " + gpKey)
	# An unknown kind yields an empty pattern so the dialog can fall back to the project
	# filter instead of adding a meaningless "*." entry.
	# 未知格式返回空通配符，对话框据此回退到工程过滤器，而非加一个无意义的 "*." 项。
	gpEq(GPExporterRegistry.gpFilterPatternOf("nonsense"), "",
		"an unknown kind yields no pattern")


# ---- registry vs menus --------------------------------------------------

static func _gpCollectActions(gpV: Variant, gpOut: Array[String]) -> void:
	if gpV is Array:
		var gpA: Array = gpV as Array
		# A menu row is a [label_key, action] pair.
		# 菜单行是 [标签键, 动作] 的二元组。
		if gpA.size() == 2 and (gpA[0] is String) and (gpA[1] is String):
			gpOut.append(str(gpA[1]))
			return
		for gpX in gpA:
			_gpCollectActions(gpX, gpOut)
	elif gpV is Dictionary:
		for gpK in (gpV as Dictionary).values():
			_gpCollectActions(gpK, gpOut)


# Every registered format must be CLICKABLE. A format that exists only in the registry is
# invisible to the user, which is a silent feature.
# 每种已注册的格式都必须**可点击**。只存在于注册表中的格式对用户不可见 ——
# 那是一个静默的功能。
func gpTestEveryRegisteredFormatHasAMenuEntry() -> void:
	var gpActions: Array[String] = []
	_gpCollectActions(GPPIDMenuBar.GP_MENUS, gpActions)
	_gpCollectActions(GPPIDQuickToolbar.GP_ITEMS, gpActions)
	gpCheck(gpActions.size() > 5, "menu actions were collected: " + str(gpActions.size()))
	for gpKind in GPExporterRegistry.gpAllKinds():
		var gpAction: String = "export_" + gpKind
		gpCheck(gpActions.has(gpAction),
			"menu exposes " + gpAction + " for the " + gpKind + " format")


# ---- dispatch -----------------------------------------------------------

func gpTestUnknownKindIsRefused() -> void:
	var gpResult: GPIOResult = GPExporterRegistry.gpExport("nonsense", "user://x.pid.xml",
		_gpGraph(), [], _gpSheet())
	gpCheck(not gpResult.gpIsOk(), "an unregistered kind is refused")
	gpCheck(gpResult.gpFailedWith("export.unknown_kind"), "and says why")


func gpTestDexpiWithoutASheetIsRefused() -> void:
	var gpResult: GPIOResult = GPExporterRegistry.gpExport(GPExporterRegistry.GP_DEXPI,
		"user://_gp_p4_no_sheet.xml", _gpGraph(), [], null)
	gpCheck(not gpResult.gpIsOk(), "DEXPI cannot write a Diagram without a sheet")
	gpCheck(gpResult.gpFailedWith("dexpi.no_sheet"), "and says which prerequisite is missing")


func gpTestEmptyPathIsRefused() -> void:
	gpCheck(not GPExporterRegistry.gpExport(GPExporterRegistry.GP_DEXPI, "",
		_gpGraph(), [], _gpSheet()).gpIsOk(), "no path means no export")


# ---- end to end through the registry ------------------------------------

func gpTestDexpiExportThroughTheRegistryRoundTrips() -> void:
	var gpPath: String = "user://_gp_p4_dexpi.xml"
	var gpResult: GPIOResult = GPExporterRegistry.gpExport(GPExporterRegistry.GP_DEXPI, gpPath,
		_gpGraph(), [], _gpSheet())
	gpCheck(gpResult.gpIsOk(), "the registry wrote the file: " + gpResult.gpToString())
	# The payload shape must match the other formats', or the shared status line breaks.
	# 载荷形态必须与其它格式一致，否则共用的状态栏逻辑会坏掉。
	var gpStats: Dictionary = gpResult.gpPayload as Dictionary
	gpCheck(gpStats != null, "the payload is a dictionary like every other export")
	gpEq(int(gpStats.get("nodes", 0)), 2, "the status line can report two nodes")
	gpEq(int(gpStats.get("edges", 0)), 1, "and one edge")
	var gpRead: GPIOResult = GPAtomicFile.gpReadText(gpPath)
	gpCheck(gpRead.gpIsOk(), "the file can be read back")
	var gpText: String = str(gpRead.gpPayload)
	gpCheck(GPDexpiExporter.gpIsWellFormed(gpText), "and it is readable XML")
	# Import it back: the round trip through the REGISTRY path is the real delivery proof.
	# 再导入回来：经**注册表**路径的往返才是真正的交付证明。
	var gpBack: GPIOResult = GPDexpiReader.gpReadXml(gpText)
	gpCheck(gpBack.gpIsOk(), "the exported file imports back")
	var gpMid: Dictionary = gpBack.gpPayload as Dictionary
	gpEq((gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array).size(), 2,
		"both pieces of equipment came back")
	var gpReport: GPImportReport = GPImportReport.new()
	GPProjectImport.gpValidate(GPDexpiImporter.gpToV3(gpMid), gpReport)
	gpCheck(not gpReport.gpHasErrors(), "and the existing import gate accepts it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))
