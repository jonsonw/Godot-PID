extends "res://tests/gp_test.gd"
# Import behaviour tests: failure taxonomy, validation report, and the non-destructive
# conflict policy (P1).
# 导入行为测试：失败分类、校验报告与非破坏冲突策略（P1）。
# The rule under test: a default import must never DECREASE what the target already holds.
# 受测规则：默认导入**永不减少**目标已有的内容。
# See 持久化实现方案 §9 / 见「持久化实现方案」§9。

const GP_TMP: String = "user://gp_test_import.pid.json"
const GP_TMP2: String = "user://gp_test_import2.pid.json"


func _gpCleanup() -> void:
	for gpP in [GP_TMP, GP_TMP2]:
		var gpAbs: String = ProjectSettings.globalize_path(gpP)
		if FileAccess.file_exists(gpAbs):
			DirAccess.remove_absolute(gpAbs)


# A minimal v3 container with one node, built by hand so the test controls every conflict.
# 手工构造的最小 v3 容器（含一个节点），使测试能控制每种冲突。
static func _gpContainer(gpUid: String, gpTag: String, gpSymbolId: String = "pump") -> Dictionary:
	return {
		"format": "g-pid",
		"format_version": 3,
		"kind": "project",
		"doc_id": "docimp",
		"meta": {"version": "1.1", "title": "导入测试"},
		"sheets": [{
			"id": "sheet-1",
			"name": "S1",
			"index": 0,
			"nodes": [{"uid": gpUid, "instance_id": "n1", "symbol_id": gpSymbolId,
				"tag": gpTag, "position": [0.0, 0.0], "props": {}}],
			"edges": [],
			"shapes": [],
		}],
		"library": {"packs": [], "builtin_overrides": []},
	}


# --- failure taxonomy / 失败分类 -------------------------------------------

func gpTestMissingFileIsOpenFailure() -> void:
	var gpR: GPIOResult = GPProjectImport.gpReadArchive("user://gp_no_such_file.pid.json")
	gpCheck(not gpR.gpIsOk(), "a missing file must fail")
	gpCheck(gpR.gpFailedWith("io.open_failed"), "the code must be io.open_failed, got "
		+ gpR.gpCode)


func gpTestForeignJsonIsUnknownFormat() -> void:
	_gpCleanup()
	var gpW: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(GP_TMP, {"hello": "world"})
	gpCheck(gpW.gpIsOk(), "the scratch file should be writable")
	var gpR: GPIOResult = GPProjectImport.gpReadArchive(GP_TMP)
	gpCheck(gpR.gpFailedWith("io.unknown_format"), "unrelated JSON must be rejected, got "
		+ gpR.gpCode)
	_gpCleanup()


func gpTestFutureVersionIsRefused() -> void:
	_gpCleanup()
	var gpPayload: Dictionary = _gpContainer("u1", "P-1")
	gpPayload["format_version"] = 99
	var gpW: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(GP_TMP, gpPayload)
	gpCheck(gpW.gpIsOk(), "the scratch file should be writable")
	var gpR: GPIOResult = GPProjectImport.gpReadArchive(GP_TMP)
	gpCheck(gpR.gpFailedWith("io.future_version"),
		"a newer format_version must be refused, got " + gpR.gpCode)
	_gpCleanup()


# --- validation report / 校验报告 ------------------------------------------

# A missing symbol definition must be REPORTED, never dropped.
# 缺失的图元定义必须被**报告**，绝不丢弃。
func gpTestMissingSymbolReportedNotDropped() -> void:
	var gpReport: GPImportReport = GPImportReport.new()
	GPProjectImport.gpValidate(_gpContainer("u1", "P-1", "NO_SUCH_SYMBOL_999"), gpReport)
	gpCheck(gpReport.gpCountOf(GPImportReport.GP_ERROR) >= 1,
		"a symbol with no definition must be reported")
	gpCheck(int(gpReport.gpStats.get("nodes", 0)) == 1,
		"the node must still be counted, not discarded")


func gpTestDanglingEdgeReported() -> void:
	var gpData: Dictionary = _gpContainer("u1", "P-1")
	var gpSheet: Dictionary = (gpData["sheets"] as Array)[0] as Dictionary
	gpSheet["edges"] = [{"instance_id": "e1",
		"from_ref": {"node_id": "u1", "port_id": ""},
		"to_ref": {"node_id": "ghost", "port_id": ""}}]
	var gpReport: GPImportReport = GPImportReport.new()
	GPProjectImport.gpValidate(gpData, gpReport)
	gpCheck(gpReport.gpCountOf(GPImportReport.GP_ERROR) >= 1,
		"an edge pointing at a missing node must be reported")


# --- non-destructive conflicts / 非破坏冲突 --------------------------------

# A colliding uid must be re-assigned on the INCOMING side; the existing node is untouched.
# 冲突的 uid 必须在**导入方**重新分配；既有节点不受影响。
func gpTestUidCollisionReassignsIncoming() -> void:
	var gpTarget: GPPIDGraph = GPPIDGraph.new()
	var gpExisting: GPPIDNode = gpTarget.gpNewNode("n0", "pump", "P-900", Vector2.ZERO)
	gpExisting.gpUid = "docimp-n1"
	gpTarget.gpAddNode(gpExisting)
	var gpR: GPIOResult = GPProjectImport.gpMergeInto(gpTarget, _gpContainer("docimp-n1", "P-1"))
	gpCheck(gpR.gpIsOk(), "merge must succeed")
	gpCheck(gpTarget.gpNodes.size() == 2, "both nodes must coexist, got "
		+ str(gpTarget.gpNodes.size()))
	if gpTarget.gpNodes.size() >= 2:
		gpCheck((gpTarget.gpNodes[0] as GPPIDNode).gpUid == "docimp-n1",
			"the existing uid must be untouched")
		gpCheck((gpTarget.gpNodes[1] as GPPIDNode).gpUid != "docimp-n1",
			"the incoming uid must be re-assigned")
		gpCheck((gpTarget.gpNodes[1] as GPPIDNode).gpUid != "",
			"the new uid must not be empty")


# A colliding tag gets a visible -dup suffix; the existing device keeps its tag.
# 冲突位号获得显眼的 -dup 后缀；既有设备保住自己的位号。
func gpTestTagCollisionAppendsDup() -> void:
	var gpTarget: GPPIDGraph = GPPIDGraph.new()
	var gpExisting: GPPIDNode = gpTarget.gpNewNode("n0", "pump", "P-1001", Vector2.ZERO)
	gpExisting.gpUid = "doclocal-n0"
	gpTarget.gpAddNode(gpExisting)
	var gpR: GPIOResult = GPProjectImport.gpMergeInto(gpTarget, _gpContainer("docimp-n1", "P-1001"))
	gpCheck(gpR.gpIsOk(), "merge must succeed")
	gpCheck(gpTarget.gpNodes.size() == 2, "both devices must coexist")
	if gpTarget.gpNodes.size() >= 2:
		gpCheck((gpTarget.gpNodes[0] as GPPIDNode).gpTag == "P-1001",
			"the existing tag must be untouched")
		gpCheck((gpTarget.gpNodes[1] as GPPIDNode).gpTag == "P-1001-dup",
			"the incoming tag should get a -dup suffix, got "
			+ (gpTarget.gpNodes[1] as GPPIDNode).gpTag)


# Same symbol id but different content: BOTH must survive, so the incoming one is renamed.
# 图元 id 相同但内容不同：**两者**都必须存活，故导入方被改名。
func gpTestSymbolConflictDerivesNewId() -> void:
	var gpId: String = GPSymbolLibrary.gpAllocateCustomId("valve")
	var gpLocal: GPSymbolDef = GPSymbolDef.new()
	gpLocal.gpId = gpId
	gpLocal.gpDisplayName = "本地阀"
	GPSymbolLibrary.gpRegisterDefs([gpLocal])

	var gpIncoming: GPSymbolDef = GPSymbolDef.new()
	gpIncoming.gpId = gpId
	gpIncoming.gpDisplayName = "导入阀"
	var gpPack: GPSymbolPack = GPSymbolPack.new()
	gpPack.gpPackId = "imp"
	gpPack.gpSymbols = [gpIncoming]
	var gpData: Dictionary = _gpContainer("docimp-n1", "P-1", gpId)
	gpData["library"] = {"packs": [gpPack.gpToDict()], "builtin_overrides": []}

	var gpTarget: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPIOResult = GPProjectImport.gpMergeInto(gpTarget, gpData)
	gpCheck(gpR.gpIsOk(), "merge must succeed")
	var gpReport: GPImportReport = gpR.gpPayload as GPImportReport
	gpCheck(gpReport != null, "a report must be returned")
	if gpReport == null:
		return
	gpCheck(gpReport.gpCountOf(GPImportReport.GP_WARNING) >= 1,
		"the rename must be reported as a warning")
	# The local definition must still answer to its own id — the import may not overwrite it.
	# 本地定义必须仍以自己原来的 id 响应 —— 导入不得覆盖它。
	var gpStillLocal: GPSymbolDef = GPSymbolLibrary.gpFindById(gpId)
	gpCheck(gpStillLocal != null, "the local symbol must still exist")
	if gpStillLocal != null:
		gpCheck(gpStillLocal.gpDisplayName == "本地阀",
			"the local symbol must keep its own content, got " + gpStillLocal.gpDisplayName)
	# And the node's symbol_id must have been remapped to the derived id.
	# 且节点的 symbol_id 必须已被重映射到派生出的 id。
	gpCheck(gpTarget.gpNodes.size() == 1, "the node must still be imported")
	if gpTarget.gpNodes.size() >= 1:
		var gpImportedId: String = (gpTarget.gpNodes[0] as GPPIDNode).gpSymbolId
		gpCheck(gpImportedId != gpId,
			"the imported node must point at the derived id, not the original")


# Merge mode ADDS; replace mode SUBSTITUTES. Replace is opt-in by name.
# merge 模式是**追加**；replace 模式是**替换**。replace 必须指名才能启用。
func gpTestReplaceModeClearsFirst() -> void:
	var gpTarget: GPPIDGraph = GPPIDGraph.new()
	gpTarget.gpAddNode(gpTarget.gpNewNode("n0", "pump", "P-900", Vector2.ZERO))
	var gpData: Dictionary = _gpContainer("docimp-n1", "P-1")
	var gpMerge: GPIOResult = GPProjectImport.gpMergeInto(gpTarget, gpData,
		GPProjectImport.GP_MODE_MERGE)
	gpCheck(gpMerge.gpIsOk(), "merge must succeed")
	gpCheck(gpTarget.gpNodes.size() == 2, "merge keeps both, got " + str(gpTarget.gpNodes.size()))
	var gpReplace: GPIOResult = GPProjectImport.gpMergeInto(gpTarget, gpData,
		GPProjectImport.GP_MODE_REPLACE)
	gpCheck(gpReplace.gpIsOk(), "replace must succeed")
	gpCheck(gpTarget.gpNodes.size() == 1, "replace leaves only the imported node, got "
		+ str(gpTarget.gpNodes.size()))


# --- three container kinds / 三种容器 kind ---------------------------------

func gpTestLibraryKindExportImport() -> void:
	_gpCleanup()
	var gpPack: GPSymbolPack = GPSymbolPack.new()
	gpPack.gpPackId = "p1"
	gpPack.gpName = "我的图元包"
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = GPSymbolLibrary.gpAllocateCustomId("valve")
	gpDef.gpDisplayName = "专用阀"
	gpPack.gpSymbols = [gpDef]
	var gpOut: GPIOResult = GPProjectExport.gpExportToFile("library", GP_TMP,
		GPPIDGraph.new(), [gpPack])
	gpCheck(gpOut.gpIsOk(), "library export must succeed: " + gpOut.gpToString())
	if not gpOut.gpIsOk():
		_gpCleanup()
		return
	var gpIn: GPIOResult = GPProjectImport.gpReadArchive(GP_TMP)
	gpCheck(gpIn.gpIsOk(), "library read-back must succeed")
	if gpIn.gpIsOk():
		var gpV3: Dictionary = gpIn.gpPayload as Dictionary
		gpCheck(str(gpV3.get("kind", "")) == "library", "kind must be library")
		var gpPacks: Array = ((gpV3.get("library", {}) as Dictionary).get("packs", []) as Array)
		gpCheck(gpPacks.size() == 1, "the pack must round-trip")
	_gpCleanup()


func gpTestConfigKindExportImport() -> void:
	_gpCleanup()
	var gpConfig: Dictionary = {"sheet": {"size": "A3", "orientation": "portrait"}}
	var gpOut: GPIOResult = GPProjectExport.gpExportToFile("config", GP_TMP,
		GPPIDGraph.new(), [], gpConfig)
	gpCheck(gpOut.gpIsOk(), "config export must succeed: " + gpOut.gpToString())
	if not gpOut.gpIsOk():
		_gpCleanup()
		return
	var gpIn: GPIOResult = GPProjectImport.gpReadArchive(GP_TMP)
	gpCheck(gpIn.gpIsOk(), "config read-back must succeed")
	if gpIn.gpIsOk():
		var gpV3: Dictionary = gpIn.gpPayload as Dictionary
		gpCheck(str(gpV3.get("kind", "")) == "config", "kind must be config")
		var gpSheet: Dictionary = ((gpV3.get("config", {}) as Dictionary).get(
			"sheet", {}) as Dictionary)
		gpCheck(str(gpSheet.get("size", "")) == "A3",
			"the user's A3 choice must survive, got " + str(gpSheet.get("size", "")))
	_gpCleanup()


# Export must not mutate the graph it was handed, and must not be confused with save-as.
# 导出不得改动交给它的图，也不得与另存为混淆。
func gpTestExportDoesNotMutateGraph() -> void:
	_gpCleanup()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-1", Vector2(1, 2)))
	var gpBefore: int = gpG.gpNodes.size()
	var gpOut: GPIOResult = GPProjectExport.gpExportToFile("project", GP_TMP, gpG, [], {}, "d1")
	gpCheck(gpOut.gpIsOk(), "export must succeed")
	gpCheck(gpG.gpNodes.size() == gpBefore, "the source graph must be untouched")
	gpCheck(not gpG.gpMeta.has("format"), "the in-memory graph must not gain format keys")
	_gpCleanup()


# The menu must actually expose import/export — a feature that exists only in code is a
# feature the user cannot reach.
# 菜单必须真的把导入 / 导出暴露出来 —— 只存在于代码里的功能，是用户够不到的功能。
func gpTestMenuExposesImportExport() -> void:
	var gpFileMenu: Array = GPPIDMenuBar.GP_MENUS["menu.file"] as Array
	var gpActions: Array[String] = []
	var gpHasExportSubmenu: bool = false
	for gpEntry in gpFileMenu:
		if gpEntry is Array:
			gpActions.append(str((gpEntry as Array)[1]))
		elif gpEntry is Dictionary:
			gpHasExportSubmenu = true
			for gpSub in ((gpEntry as Dictionary).get("items", []) as Array):
				if gpSub is Array:
					gpActions.append(str((gpSub as Array)[1]))
	gpCheck(gpActions.has("file_import"), "the file menu must carry file_import")
	gpCheck(gpHasExportSubmenu, "the file menu must carry an export submenu")
	gpCheck(gpActions.has("export_project"), "export submenu must carry export_project")
	gpCheck(gpActions.has("export_library"), "export submenu must carry export_library")
	gpCheck(gpActions.has("export_config"), "export submenu must carry export_config")


# A report must be usable by the host: counts, capped lines, machine-readable form.
# 报告必须可供宿主使用：计数、带上限的行、机器可读形式。
func gpTestReportIsUsable() -> void:
	var gpReport: GPImportReport = GPImportReport.new()
	gpReport.gpSourcePath = GP_TMP
	gpReport.gpAddError("import.symbol_missing", "XYZ")
	gpReport.gpAddWarning("import.tag_duplicate", "P-1")
	gpReport.gpAddInfo("import.symbol_added", "ABC")
	gpCheck(gpReport.gpCountOf(GPImportReport.GP_ERROR) == 1, "one error")
	gpCheck(gpReport.gpCountOf(GPImportReport.GP_WARNING) == 1, "one warning")
	gpCheck(gpReport.gpHasErrors(), "hasErrors must be true")
	gpCheck(gpReport.gpLines().size() == 3, "three lines")
	gpCheck((gpReport.gpToDict().get("errors", 0)) == 1, "the dict form must carry the count")
	gpCheck(not gpReport.gpSummary().is_empty(), "a summary must exist")
