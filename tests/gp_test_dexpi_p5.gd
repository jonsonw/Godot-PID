extends "res://tests/gp_test.gd"
# P5 acceptance: the DEXPI IMPORT PATH is actually wired into the UI, not just unit-tested
# in isolation. The export side got a menu entry + dialog filter + dispatch; this suite nails
# that the IMPORT side got the same three things, and that the on-disk round trip
# (write DEXPI -> read it back as a v3 container) works through the single UI entry point.
# P5 验收：DEXPI **导入**路径确实接入了 UI，而非只在孤立单元测试里跑通。
# 导出侧有菜单项 + 对话框过滤器 + 分发；本套件钉死导入侧也补上了这三样，
# 且「写 DEXPI -> 从磁盘读回为 v3 容器」的往返走的是唯一的 UI 入口。
#
# WHY THESE ASSERTIONS / 为何是这些断言：
# the export bug (and the matching import gap) was a SILENT feature — the modules existed and
# passed their own tests, but nothing in the UI invoked them, so the user could not actually
# pick a .pid.xml. These tests fail loudly if any of the three wiring pieces is ever dropped.
# 导出缺陷（以及对应的导入缺口）是**静默功能**——模块存在且自测通过，
# 但 UI 中没有任何东西调用它们，于是用户实际选不到 .pid.xml。
# 这三样接线任一处被删，本套件都会大声失败。

const GP_SHEET_W: float = 420.0
const GP_SHEET_H: float = 297.0


static func _gpSheet() -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpName = "P5 Import Sheet"
	gpSheet.gpWidthMM = GP_SHEET_W
	gpSheet.gpHeightMM = GP_SHEET_H
	return gpSheet


static func _gpGraph() -> GPPIDGraph:
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	var gpPump: GPPIDNode = gpGraph.gpNewNode("n1", "DPUMP001", "P-1001", Vector2(120.0, 90.0))
	gpPump.gpUid = "doc-n1"
	gpGraph.gpAddNode(gpPump)
	var gpTank: GPPIDNode = gpGraph.gpNewNode("n2", "DTANK001", "T-1002", Vector2(320.0, 210.0))
	gpTank.gpUid = "doc-n2"
	gpGraph.gpAddNode(gpTank)
	var gpEdge: GPPIDEdge = GPPIDEdge.new()
	gpEdge.gpInstanceId = "e5"
	gpEdge.gpFromRef = {"node_id": "n1", "port_id": "out"}
	gpEdge.gpToRef = {"node_id": "n2", "port_id": "top"}
	gpEdge.gpRouting = [Vector2(220.0, 150.0)]
	gpEdge.gpTag = "PL-1002"
	gpGraph.gpEdges.append(gpEdge)
	return gpGraph


# Flatten every action id out of the menu definition, recursing into submenus.
# 把菜单定义里的每个动作 id 摊平，递归进入子菜单。
static func _gpActionIds(gpEntries: Array) -> Array[String]:
	var gpOut: Array[String] = []
	for gpE in gpEntries:
		if gpE == null:
			continue
		if gpE is Array:
			var gpArr: Array = gpE as Array
			if gpArr.size() >= 2:
				gpOut.append(str(gpArr[1]))
		elif gpE is Dictionary:
			var gpD: Dictionary = gpE as Dictionary
			if gpD.has("items"):
				gpOut.append_array(_gpActionIds(gpD.get("items", []) as Array))
	return gpOut


# ---- wiring: the menu, the registry filter, the coordinator handlers --------

# The "import_dexpi" action must exist in the menu bar, right next to the pid.json import.
# 「import_dexpi」动作必须存在于菜单栏，紧挨 pid.json 导入项。
func gpTestImportDexpiActionIsInTheMenu() -> void:
	var gpAll: Array[String] = []
	for gpK in GPPIDMenuBar.GP_MENUS.keys():
		gpAll.append_array(_gpActionIds(GPPIDMenuBar.GP_MENUS[gpK] as Array))
	gpCheck(gpAll.has("import_dexpi"),
		"the import_dexpi action is wired into the menu bar: " + str(gpAll))
	gpCheck(gpAll.has("file_import"),
		"the existing pid.json import action is still present")


# The dialog filter for DEXPI must be offered on IMPORT too, or the user cannot select the
# file — the exact silent-feature class the export fix closed.
# DEXPI 的对话框过滤器在**导入**时也必须提供，否则用户选不到文件 ——
# 这正是导出修复所关闭的那类静默功能。
func gpTestImportDexpiDialogFilterIsPidXml() -> void:
	gpEq(GPExporterRegistry.gpFilterPatternOf("dexpi"), "*.pid.xml",
		"the DEXPI dialog filter offers *.pid.xml on import")
	gpEq(GPExporterRegistry.gpFilterKeyOf("dexpi"), "doc.dexpi_filter",
		"the filter label key matches the export one")


# The file coordinator must expose the two new handlers the menu routes to.
# 文件协调者必须暴露菜单所路由到的两个新处理函数。
func gpTestImportDexpiHandlersExist() -> void:
	var gpCoord: GPFileCoordinator = GPFileCoordinator.new()
	gpCheck(gpCoord.has_method("gpPickImportDexpiPath"),
		"the coordinator exposes the DEXPI import picker")
	gpCheck(gpCoord.has_method("gpDoImportDexpi"),
		"the coordinator exposes the DEXPI import handler")


# ---- wiring: the on-disk round trip through the single UI entry point -------

func gpTestReadFileToV3RoundTripsThroughDisk() -> void:
	var gpXml: String = GPDexpiExporter.gpWriteXml(
		GPDexpiExporter.gpFromGraph(_gpGraph(), _gpSheet()))
	var gpPath: String = OS.get_temp_dir().path_join("gp_dexpi_import_test.pid.xml")
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.WRITE)
	gpCheck(gpF != null, "temp DEXPI file opened for writing")
	if gpF != null:
		gpF.store_string(gpXml)
		gpF.close()
	var gpRes: GPIOResult = GPDexpiImporter.gpReadFileToV3(gpPath)
	gpCheck(gpRes.gpIsOk(), "the on-disk DEXPI file read back: " + gpRes.gpToString())
	var gpPayload: Dictionary = gpRes.gpPayload as Dictionary
	var gpV3: Dictionary = gpPayload.get("v3", {}) as Dictionary
	gpCheck(not gpV3.is_empty(), "a v3 container was produced from the file")
	# The produced container must satisfy the SAME gate every other import goes through.
	# 产出的容器必须满足其它所有导入都走的同一道门禁。
	var gpGate: GPImportReport = GPImportReport.new()
	GPProjectImport.gpValidate(gpV3, gpGate)
	gpCheck(not gpGate.gpHasErrors(), "the existing import gate accepts it: " + gpGate.gpSummary())
	gpEq(int(gpGate.gpStats.get("nodes", 0)), 2, "two nodes reached the gate")
	gpEq(int(gpGate.gpStats.get("edges", 0)), 1, "one edge reached the gate")
	# The source's own validation report rides along, so the UI can show error/warning counts.
	# 源文件自身的校验报告一并返回，使 UI 能显示错误/警告计数。
	var gpReport: GPImportReport = gpPayload.get("report", null) as GPImportReport
	gpCheck(gpReport != null and not gpReport.gpHasErrors(),
		"the source file's own validation report has no errors")
	# cleanup
	if FileAccess.file_exists(gpPath):
		DirAccess.remove_absolute(gpPath)


func gpTestReadFileToV3RefusesMissingFile() -> void:
	var gpRes: GPIOResult = GPDexpiImporter.gpReadFileToV3(
		OS.get_temp_dir().path_join("gp_dexpi_does_not_exist_xyz.pid.xml"))
	gpCheck(not gpRes.gpIsOk(), "a missing file is refused")
	gpCheck(gpRes.gpFailedWith("io.open_failed"), "the failure names the reason")


# ---- regression: the DOUBLE EXTENSION the user actually saw on disk ----------
# "W6.pid.pid.xml" was produced by the pre-filled export name (basename of "W6.pid.json" is
# "W6.pid", to which ".pid.xml" was appended whole) and by typing "W6.pid" by hand. A trailing
# ".pid" is an incomplete container name: FINISH it, never double it.
# 用户在磁盘上实际见到的「W6.pid.pid.xml」双扩展名回归钉：预填名把「W6.pid.json」的
# basename「W6.pid」整段追加「.pid.xml」；手打「W6.pid」同理。结尾的「.pid」是未写完的
# 容器名：**补完**，绝不翻倍。
func gpTestFinishNameNeverDoublesTheExtension() -> void:
	gpEq(GPExporterRegistry.gpFinishName("/a/W6", "pid.xml"), "/a/W6.pid.xml",
		"a bare typed name gets the full extension")
	gpEq(GPExporterRegistry.gpFinishName("/a/W6.pid", "pid.xml"), "/a/W6.pid.xml",
		"a trailing .pid is FINISHED, not doubled (was W6.pid.pid.xml)")
	gpEq(GPExporterRegistry.gpFinishName("/a/W6.pid.xml", "pid.xml"), "/a/W6.pid.xml",
		"a complete name is left alone")
	gpEq(GPExporterRegistry.gpFinishName("/a/W6.xml", "pid.xml"), "/a/W6.xml",
		"a user-chosen .xml name is respected")
	gpEq(GPExporterRegistry.gpFinishName("/a/W6", "png"), "/a/W6.png",
		"simple extensions still complete a bare name")


# The merged import dialog must offer BOTH container formats — offering only *.pid.json
# forced the user through "All Files" and then misrouted the pick to the JSON reader.
# 合并式导入对话框必须同时提供两种容器格式 —— 只给 *.pid.json 会逼用户走
# 「All Files」，随后把选中的文件误送进 JSON 读取器。
func gpTestImportDialogCarriesBothFormats() -> void:
	var gpCoord: GPFileCoordinator = GPFileCoordinator.new()
	gpCheck(gpCoord.has_method("_gpApplyImportFilters"),
		"the coordinator applies the merged two-format import filters")


# ---- regression: pipe ends REBIND to their original ports --------------------
# DEXPI stores segment endpoints but NOT which port each end touched. Without rebinding,
# port_id came back "" and the renderer degraded to "first nozzle port" — pipes rendered
# attached to the wrong sides of the symbols (the user-visible geometry bug).
# DEXPI 只存线段端点，不存各端接的是哪个端口。不重绑时 port_id 回来是空串，
# 渲染器降级到「期望用途第一个端口」—— 管线被画到符号的错误侧面（用户可见的几何缺陷）。
func gpDefForLookup(gpSymbolId: String) -> GPSymbolDef:
	for gpD in GPSymbolLibrary.gpDefaultDefs():
		if gpD.gpId == gpSymbolId:
			return gpD
	return null


func _gpEdgeById(gpV3: Dictionary, gpId: String) -> Dictionary:
	for gpSheet in (gpV3.get("sheets", []) as Array):
		for gpE in ((gpSheet as Dictionary).get("edges", []) as Array):
			if str((gpE as Dictionary).get("instance_id", "")) == gpId:
				return gpE as Dictionary
	return {}


func gpTestRoundTripRestoresPortBindings() -> void:
	var gpXml: String = GPDexpiExporter.gpWriteXml(
		GPDexpiExporter.gpFromGraph(_gpGraph(), _gpSheet()))
	var gpMid: Dictionary = GPDexpiReader.gpReadXml(gpXml).gpPayload as Dictionary
	var gpV3: Dictionary = GPDexpiImporter.gpToV3(gpMid, Callable(self, "gpDefForLookup"))
	var gpE5: Dictionary = _gpEdgeById(gpV3, "e5")
	gpCheck(not gpE5.is_empty(), "edge e5 is present in the round-tripped container")
	var gpFromRef: Dictionary = gpE5.get("from_ref", {}) as Dictionary
	gpEq(str(gpFromRef.get("port_id", "")), "out",
		"the FROM end rebinds to the port nearest its stored endpoint")
	var gpToRef: Dictionary = gpE5.get("to_ref", {}) as Dictionary
	gpEq(str(gpToRef.get("port_id", "")), "top",
		"the TO end rebinds to the port nearest its stored endpoint")
	# The stored bend survives the round trip unchanged.
	# 已存折点在往返中保持不变。
	var gpRouting: Array = gpE5.get("routing", []) as Array
	gpEq(gpRouting.size(), 1, "the bend is preserved")
	if gpRouting.size() == 1:
		var gpBend: Array = gpRouting[0] as Array
		gpEq(float(gpBend[0]), 220.0, "the bend x round-trips")
		gpEq(float(gpBend[1]), 150.0, "the bend y round-trips")
	# Without a def lookup the binding stays empty — the documented degradation.
	# 不传定义查找时绑定保持空串 —— 这是文档化的降级行为。
	var gpV3Bare: Dictionary = GPDexpiImporter.gpToV3(gpMid)
	var gpBare5: Dictionary = _gpEdgeById(gpV3Bare, "e5")
	var gpBareFrom: Dictionary = gpBare5.get("from_ref", {}) as Dictionary
	gpEq(str(gpBareFrom.get("port_id", "")), "",
		"without a def lookup the port binding stays empty (renderer ladder applies)")


# ---- regression: edges must BIND to nodes, never fall back to the origin -----
# The imported nodes used sequential instance ids ("n1","n2",...) while the edges addressed
# the DEXPI ids, so gpGetNode() found nothing, GPPortResolver degraded to "free" and returned
# Vector2.ZERO — the entire sheet's pipes were anchored at the ORIGIN. These assertions drive
# the REAL downstream path (merge -> gpGetNode -> gpResolveEnd) instead of only inspecting the
# container, because the container looked fine while the rendered drawing was wrong.
# 导入的节点用顺序 id（n1/n2…）而边引用 DEXPI id，于是 gpGetNode() 找不到节点、
# GPPortResolver 降级到 "free" 并返回 Vector2.ZERO —— 整张图的管线锚在**原点**。
# 以下断言驱动**真实**下游路径（merge -> gpGetNode -> gpResolveEnd），而不只是检查容器，
# 因为容器当时看起来没问题、渲染出来的图却是错的。
func gpTestImportedEdgesBindToNodesNotOrigin() -> void:
	var gpXml: String = GPDexpiExporter.gpWriteXml(
		GPDexpiExporter.gpFromGraph(_gpGraph(), _gpSheet()))
	var gpMid: Dictionary = GPDexpiReader.gpReadXml(gpXml).gpPayload as Dictionary
	var gpLookup: Callable = Callable(self, "gpDefForLookup")
	var gpV3: Dictionary = GPDexpiImporter.gpToV3(gpMid, gpLookup)
	# The node's instance_id must be the same string the edges reference.
	# 节点的 instance_id 必须与边引用的字符串一致。
	var gpNodes: Array = ((gpV3.get("sheets", []) as Array)[0] as Dictionary).get("nodes", []) as Array
	var gpEdge: Dictionary = _gpEdgeById(gpV3, "e5")
	var gpFromId: String = str((gpEdge.get("from_ref", {}) as Dictionary).get("node_id", ""))
	var gpIds: Array[String] = []
	for gpN in gpNodes:
		gpIds.append(str((gpN as Dictionary).get("instance_id", "")))
	gpCheck(gpIds.has(gpFromId),
		"the edge's node_id matches a node instance_id: " + gpFromId + " in " + str(gpIds))
	# Drive the real merge + resolver, then compare against the ORIGINAL geometry.
	# 驱动真实的合并 + 解析器，再与**原始**几何对比。
	var gpTarget: GPPIDGraph = GPPIDGraph.new()
	var gpMerge: GPIOResult = GPProjectImport.gpMergeInto(gpTarget, gpV3)
	gpCheck(gpMerge.gpIsOk(), "the container merges into a graph: " + gpMerge.gpToString())
	gpEq(gpTarget.gpNodes.size(), 2, "two nodes were merged")
	gpEq(gpTarget.gpEdges.size(), 1, "one edge was merged")
	var gpImported: GPPIDEdge = gpTarget.gpEdges[0] as GPPIDEdge
	var gpWant: String = GPPortResolver.gpWantTypeFor(gpImported)
	var gpOrigGraph: GPPIDGraph = _gpGraph()
	var gpOrig: GPPIDEdge = gpOrigGraph.gpEdges[0] as GPPIDEdge
	var gpWantOrig: String = GPPortResolver.gpWantTypeFor(gpOrig)
	for gpIsFrom in [true, false]:
		var gpA: Dictionary = GPPortResolver.gpResolveEnd(gpTarget, gpLookup, gpImported,
			gpIsFrom, gpWant)
		var gpB: Dictionary = GPPortResolver.gpResolveEnd(gpOrigGraph, gpLookup, gpOrig,
			gpIsFrom, gpWantOrig)
		var gpPa: Vector2 = gpA.get("pos", Vector2.ZERO) as Vector2
		var gpPb: Vector2 = gpB.get("pos", Vector2.ZERO) as Vector2
		gpCheck(gpPa != Vector2.ZERO,
			"the imported end does NOT collapse to the origin (side from=" + str(gpIsFrom) + ")")
		gpEq(str(gpA.get("why", "")), "port",
			"the end resolves by exact port hit, not by a degraded rung")
		gpCheck(gpPa.distance_to(gpPb) < 1e-4,
			"the imported end lands exactly where the original did: "
			+ str(gpPa) + " vs " + str(gpPb))
