class_name GpTestTagRuleService
extends GPGTest
# Headless tests for the numbering-rule service and the renumber command (M9b).
# 编号规则服务与重编号命令（M9b）的 headless 测试。
#
# The promise being pinned: what the dialog PREVIEWS is what the command APPLIES, because
# both go through the same service. And a renumber is one undo step that restores every
# tag, every sequence mark and the registry index together.
# 被钉住的承诺：对话框**预览**的正是命令**应用**的，因为二者走同一服务。
# 且重编号是一个撤销步，一次性还原全部位号、全部序号水位线与注册器索引。


func _gpPumpDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolLibrary.gpFindById("LPUMP003")
	if gpD != null:
		return gpD
	var gpF: GPSymbolDef = GPSymbolDef.new()
	gpF.gpId = "LPUMP003"
	gpF.gpCategory = "pump"
	return gpF


func _gpValveDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "LVALVE001"
	gpD.gpCategory = "valve"
	return gpD


func _gpGraphWithThree() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	# Ids are deliberately NOT "a1"/"a2": GPIdGen also hands out "a1", and a later placement
	# in these tests would then collide with a fixture node and gpGetNode would return the
	# wrong object. / 刻意不用 "a1"/"a2"：GPIdGen 也会发出 "a1"，此后测试里的放置会与夹具
	# 节点撞号，gpGetNode 就会返回错的对象。
	gpG.gpAddNode(gpG.gpNewNode("a1", "LPUMP003", "P-5000"))
	gpG.gpAddNode(gpG.gpNewNode("a2", "LVALVE001", "V-9000"))
	gpG.gpAddNode(gpG.gpNewNode("a3", "LPUMP003", "P-5001"))
	return gpG


func _gpRegistry(gpGraph: GPPIDGraph) -> GPTagRegistry:
	var gpR: GPTagRegistry = GPTagRegistry.new()
	gpR.gpGraph = gpGraph
	gpR.gpRules = gpGraph.gpTagRulesOrCreate()
	gpR.gpRebuild()
	return gpR


# ---------------------------------------------------------------- preview

func gpTestPreviewRowsCoverEveryLibraryCategory() -> void:
	var gpRows: Array[Dictionary] = GPTagRuleService.gpPreviewRows(
		GPProjectTagRules.gpDefaultRules(), 2)
	gpCheck(not gpRows.is_empty(), "preview produces rows")
	var gpCats: Dictionary = {}
	for gpRow in gpRows:
		gpCats[str(gpRow.get(GPTagRuleService.GP_ROW_CATEGORY, ""))] = true
	gpEq(gpCats.has("pump"), true, "pumps are previewed")
	gpEq(gpCats.has("valve"), true, "valves are previewed")
	gpEq(gpCats.has("instrument"), true, "instruments are previewed")


func gpTestPreviewReflectsTheCurrentRule() -> void:
	var gpP: GPProjectTagRules = GPProjectTagRules.gpDefaultRules()
	gpP.gpDefault.gpTemplate = "{prefix}{seq:4}"
	gpP.gpDefault.gpStart = 0
	var gpRows: Array[Dictionary] = GPTagRuleService.gpPreviewRows(gpP, 1)
	var gpFound: String = ""
	for gpRow in gpRows:
		if str(gpRow.get(GPTagRuleService.GP_ROW_CATEGORY, "")) == "pump":
			gpFound = str(gpRow.get(GPTagRuleService.GP_ROW_SAMPLE, ""))
	gpEq(gpFound, "P0001", "changing the template changes the preview immediately")


func gpTestPreviewDoesNotMutateTheRules() -> void:
	var gpP: GPProjectTagRules = GPProjectTagRules.gpDefaultRules()
	GPTagRuleService.gpPreviewRows(gpP, 3)
	gpEq(gpP.gpSeqMarks.is_empty(), true, "previewing leaves no sequence marks behind")


# ---------------------------------------------------------------- plan / apply

func gpTestRenumberItemsComeFromTheGraphInOrder() -> void:
	var gpG: GPPIDGraph = _gpGraphWithThree()
	var gpItems: Array[Dictionary] = GPTagRuleService.gpRenumberItems(gpG)
	gpEq(gpItems.size(), 3, "one item per node")
	gpEq(str(gpItems[0].get("uid", "")), "a1", "graph order is preserved")
	gpEq(str(gpItems[0].get("tag", "")), "P-5000", "the current tag is carried")


func gpTestApplyAndRevertPlan() -> void:
	var gpG: GPPIDGraph = _gpGraphWithThree()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpPlan: Array[Dictionary] = gpR.gpPlanRenumberAll(GPTagRuleService.gpRenumberItems(gpG))
	gpEq(GPTagRuleService.gpChangedCount(gpPlan), 3, "all three tags change")
	gpEq(GPTagRuleService.gpApplyPlan(gpG, gpPlan), 3, "three nodes were written")
	gpEq(gpG.gpGetNode("a1").gpTag, "P-1001", "the first pump became P-1001")
	gpEq(gpG.gpGetNode("a3").gpTag, "P-1002", "the second pump follows")
	gpEq(gpG.gpGetNode("a2").gpTag, "V-1001", "the valve is numbered in its own series")
	GPTagRuleService.gpRevertPlan(gpG, gpPlan)
	gpEq(gpG.gpGetNode("a1").gpTag, "P-5000", "revert restores the original tag")
	gpEq(gpG.gpGetNode("a2").gpTag, "V-9000", "revert restores every tag")


func gpTestMappingCsvIsExportable() -> void:
	var gpG: GPPIDGraph = _gpGraphWithThree()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpPlan: Array[Dictionary] = gpR.gpPlanRenumberAll(GPTagRuleService.gpRenumberItems(gpG))
	var gpCsv: String = GPTagRuleService.gpMappingToCsv(gpPlan)
	gpCheck(gpCsv.begins_with("uid,old_tag,new_tag\n"), "a header row leads the CSV")
	gpCheck(gpCsv.find("a1,P-5000,P-1001") >= 0, "the old->new pair is on one row: %s" % gpCsv)
	var gpLines: PackedStringArray = gpCsv.split("\n")
	gpEq(gpLines.size(), 5, "header + 3 rows + trailing newline")


func gpTestCsvCellsAreQuotedWhenNeeded() -> void:
	gpEq(GPTagRuleService.gpCsvCell("P-1001"), "P-1001", "a plain cell is untouched")
	gpEq(GPTagRuleService.gpCsvCell("A,B"), "\"A,B\"", "a comma forces quoting")
	gpEq(GPTagRuleService.gpCsvCell("A\"B"), "\"A\"\"B\"", "a quote is doubled")


# ---------------------------------------------------------------- command

func _gpSvc(gpG: GPPIDGraph, gpR: GPTagRegistry) -> GPEditService:
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), gpR)
	return gpSvc


func gpTestRenumberIsOneUndoStep() -> void:
	var gpG: GPPIDGraph = _gpGraphWithThree()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpSvc: GPEditService = _gpSvc(gpG, gpR)
	gpEq(gpSvc.gpRenumberTags(), true, "renumbering ran")
	gpEq(gpG.gpGetNode("a1").gpTag, "P-1001", "dense numbering from the start")
	gpEq(gpG.gpGetNode("a3").gpTag, "P-1002", "the second pump follows")
	gpEq(gpSvc.gpUndo(), true, "undo is available")
	gpEq(gpG.gpGetNode("a1").gpTag, "P-5000", "ONE undo restored every tag")
	gpEq(gpG.gpGetNode("a2").gpTag, "V-9000", "including the valve")
	gpEq(gpG.gpGetNode("a3").gpTag, "P-5001", "including the third node")
	gpEq(gpR.gpIsTaken("P-1001"), false, "the registry index was restored too")


func gpTestRenumberRestoresTheSequenceMarks() -> void:
	var gpG: GPPIDGraph = _gpGraphWithThree()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	gpR.gpNextTag(_gpPumpDef())
	gpEq(gpR.gpRules.gpPeek("P"), 1001, "a mark existed before renumbering")
	var gpSvc: GPEditService = _gpSvc(gpG, gpR)
	gpSvc.gpRenumberTags()
	gpEq(gpSvc.gpUndo(), true, "undo is available")
	gpEq(gpR.gpRules.gpPeek("P"), 1001, "the old high-water mark is back")


func gpTestRenumberRedoReusesTheSameNumbers() -> void:
	var gpG: GPPIDGraph = _gpGraphWithThree()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpSvc: GPEditService = _gpSvc(gpG, gpR)
	gpSvc.gpRenumberTags()
	gpSvc.gpUndo()
	gpEq(gpSvc.gpRedo(), true, "redo is available")
	gpEq(gpG.gpGetNode("a1").gpTag, "P-1001", "redo reproduced the SAME numbers")
	gpEq(gpG.gpGetNode("a3").gpTag, "P-1002", "not a fresh allocation")


func gpTestRenumberOnEmptySheetIsANoOp() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpSvc: GPEditService = _gpSvc(gpG, gpR)
	gpEq(gpSvc.gpRenumberTags(), false, "nothing to renumber means no undo step")
	gpEq(gpSvc.gpCanUndo(), false, "no phantom undo step was pushed")


func gpTestSetTagRulesTakesEffectOnNewPlacements() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpSvc: GPEditService = _gpSvc(gpG, gpR)
	var gpNew: GPProjectTagRules = GPProjectTagRules.gpDefaultRules()
	gpNew.gpDefault.gpTemplate = "{prefix}{seq:4}"
	gpNew.gpDefault.gpStart = 0
	gpNew.gpDefault.gpCategoryPrefixes = {"pump": "PP"}
	gpEq(gpSvc.gpSetTagRules(gpNew), true, "the rules were replaced")
	var gpId: String = gpSvc.gpPlaceNode("LPUMP003", Vector2.ZERO)
	gpEq(gpG.gpGetNode(gpId).gpTag, "PP0001", "the new rule drives new placements")
	gpEq(gpG.gpTagRules.gpDefault.gpTemplate, "{prefix}{seq:4}", "the rules live on the graph")


func gpTestRenumberThenPlaceContinuesTheSequence() -> void:
	var gpG: GPPIDGraph = _gpGraphWithThree()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpSvc: GPEditService = _gpSvc(gpG, gpR)
	gpSvc.gpRenumberTags()
	var gpId: String = gpSvc.gpPlaceNode("LPUMP003", Vector2.ZERO)
	gpEq(gpG.gpGetNode(gpId).gpTag, "P-1003", "a new pump continues after the renumbered ones")
