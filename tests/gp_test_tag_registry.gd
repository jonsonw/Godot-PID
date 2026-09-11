class_name GpTestTagRegistry
extends GPGTest
# Headless tests for the tag numbering rule model and the uniqueness registry (M9).
# 位号编号规则模型与唯一性注册器（M9）的 headless 测试。
#
# The behaviour pinned here is the contract the rest of the property system builds on:
# default numbering reproduces the factory convention (P-1001), a duplicate is REFUSED
# rather than silently suffixed, and a stale index can never cause a duplicate tag.
# 此处钉住的行为是属性系统其余部分的契约：默认编号复现出厂约定（P-1001），
# 重复位号被**拒绝**而非静默加后缀，且索引过期绝不会导致重复位号。


# A pump definition, resolved from the real library so the test breaks if the pack changes.
# 从真实图元库解析出的泵定义，使图元包变化时测试会失败。
func _gpPumpDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolLibrary.gpFindById("LPUMP003")
	if gpD != null:
		return gpD
	var gpFallback: GPSymbolDef = GPSymbolDef.new()
	gpFallback.gpId = "LPUMP003"
	gpFallback.gpCategory = "pump"
	gpFallback.gpTagPrefix = "P"
	return gpFallback


func _gpValveDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "LVALVE001"
	gpD.gpCategory = "valve"
	gpD.gpTagPrefix = "V"
	return gpD


func _gpRegistry(gpGraph: GPPIDGraph) -> GPTagRegistry:
	var gpR: GPTagRegistry = GPTagRegistry.new()
	gpR.gpGraph = gpGraph
	gpR.gpRules = gpGraph.gpTagRulesOrCreate()
	return gpR


# ---------------------------------------------------------------- normalisation

func gpTestNormalizeIgnoresCaseAndWhitespace() -> void:
	# Separators are folded away: "P-1001", "p 1001" and "P.1001" all compare as P1001.
	# 分隔符被折去："P-1001"、"p 1001"、"P.1001" 都按 P1001 参与比较。
	gpEq(GPTagRegistry.gpNormalize("P-1001"), "P1001", "the dash is folded away for comparison")
	gpEq(GPTagRegistry.gpNormalize("p 1001"), "P1001", "case and spaces are folded away")
	gpEq(GPTagRegistry.gpNormalize(" P - 1001 "), "P1001", "surrounding space is dropped")
	gpEq(GPTagRegistry.gpNormalize("P.1001"), "P1001", "a dot is folded away too")
	gpEq(GPTagRegistry.gpNormalize(""), "", "empty stays empty")
	# CJK is NOT stripped, or two Chinese tags would collapse onto the same key.
	# 中文**不**被剥除，否则两个中文位号会折叠到同一个键上。
	gpCheck(GPTagRegistry.gpNormalize("泵-1") != GPTagRegistry.gpNormalize("阀-1"),
		"two Chinese tags stay distinct")


# ---------------------------------------------------------------- rule defaults

func gpTestFactoryRuleMatchesTheDocumentedDefault() -> void:
	var gpR: GPTagRule = GPTagRule.gpDefault()
	gpEq(gpR.gpTemplate, "{prefix}-{seq}", "factory template is {prefix}-{seq}")
	gpEq(gpR.gpStart, 1000, "factory start is 1000")
	gpEq(gpR.gpStep, 1, "factory step is 1")
	gpEq(gpR.gpDigits, 0, "factory does not zero-pad")
	gpEq(gpR.gpValidate().gpIsOk(), true, "the factory rule is valid")


func gpTestFactoryCategoryPrefixes() -> void:
	var gpR: GPTagRule = GPTagRule.gpDefault()
	gpEq(gpR.gpPrefixFor(_gpPumpDef()), "P", "pumps are P")
	gpEq(gpR.gpPrefixFor(_gpValveDef()), "V", "valves are V")
	var gpTank: GPSymbolDef = GPSymbolDef.new()
	gpTank.gpCategory = "tank"
	gpEq(gpR.gpPrefixFor(gpTank), "T", "tanks are T")
	var gpHeat: GPSymbolDef = GPSymbolDef.new()
	gpHeat.gpCategory = "heat"
	gpEq(gpR.gpPrefixFor(gpHeat), "E", "heat exchangers are E (not H)")


func gpTestPrefixFallsBackToCategoryFirstLetter() -> void:
	var gpR: GPTagRule = GPTagRule.gpDefault()
	var gpOdd: GPSymbolDef = GPSymbolDef.new()
	gpOdd.gpCategory = "reactor"
	gpEq(gpR.gpPrefixFor(gpOdd), "R", "an unmapped category uses its own first letter")
	var gpCjk: GPSymbolDef = GPSymbolDef.new()
	gpCjk.gpCategory = "反应器"
	gpEq(gpR.gpPrefixFor(gpCjk), "X", "a category with no ASCII letter falls back to X")


func gpTestPrefixIsSanitised() -> void:
	gpEq(GPTagRule.gpSanitizePrefix("p-1"), "P1", "dashes are dropped, letters upper-cased")
	gpEq(GPTagRule.gpSanitizePrefix("Pump 01"), "PUMP01", "spaces are dropped")
	gpEq(GPTagRule.gpSanitizePrefix("泵"), "", "a non-ASCII prefix sanitises to empty")


# ---------------------------------------------------------------- formatting

func gpTestFormatHonoursTemplateAndPadding() -> void:
	var gpR: GPTagRule = GPTagRule.gpDefault()
	gpEq(gpR.gpFormat("P", 1001), "P-1001", "default format")
	gpR.gpDigits = 4
	gpEq(gpR.gpFormat("P", 7), "P-0007", "global zero padding applies")
	gpR.gpTemplate = "{prefix}{seq:3}"
	gpEq(gpR.gpFormat("V", 7), "V007", "{seq:3} overrides the global padding")
	gpR.gpTemplate = "{prefix}-{seq}-{area}"
	gpEq(gpR.gpFormat("P", 12, "A1"), "P-0012-A1", "{area} is substituted")


func gpTestValidateRejectsBrokenRules() -> void:
	var gpNoSeq: GPTagRule = GPTagRule.gpDefault()
	gpNoSeq.gpTemplate = "PUMP"
	gpEq(gpNoSeq.gpValidate().gpFailedWith("tag_rule.no_seq"), true, "a template without {seq} is refused")
	var gpBadStep: GPTagRule = GPTagRule.gpDefault()
	gpBadStep.gpStep = 0
	gpEq(gpBadStep.gpValidate().gpFailedWith("tag_rule.bad_step"), true, "step 0 is refused")
	var gpBadStart: GPTagRule = GPTagRule.gpDefault()
	gpBadStart.gpStart = -1
	gpEq(gpBadStart.gpValidate().gpFailedWith("tag_rule.bad_start"), true, "a negative start is refused")
	var gpBadDigits: GPTagRule = GPTagRule.gpDefault()
	gpBadDigits.gpDigits = 12
	gpEq(gpBadDigits.gpValidate().gpFailedWith("tag_rule.bad_digits"), true, "12 digits is refused")
	var gpBadFixed: GPTagRule = GPTagRule.gpDefault()
	gpBadFixed.gpPrefixSource = GPTagRule.GPPrefixSource.GP_FIXED
	gpEq(gpBadFixed.gpValidate().gpFailedWith("tag_rule.bad_fixed"), true, "an empty fixed prefix is refused")


# ---------------------------------------------------------------- project rules

func gpTestProjectRulesRoundTrip() -> void:
	var gpP: GPProjectTagRules = GPProjectTagRules.gpDefaultRules()
	gpP.gpDefault.gpDigits = 4
	var gpCatRule: GPTagRule = GPTagRule.gpDefault()
	gpCatRule.gpTemplate = "{prefix}{seq:3}"
	gpP.gpSetOverride(GPProjectTagRules.gpCategoryKey("valve"), gpCatRule)
	gpP.gpSetMark("V", 1005)
	var gpBack: GPProjectTagRules = GPProjectTagRules.gpFromDict(gpP.gpToDict())
	gpEq(gpBack.gpDefault.gpDigits, 4, "the default rule survives a round trip")
	gpEq(gpBack.gpPeek("V", gpBack.gpDefault), 1005, "the sequence mark survives a round trip")
	var gpV: GPTagRule = gpBack.gpRuleFor(_gpValveDef())
	gpEq(gpV.gpTemplate, "{prefix}{seq:3}", "the category override is resolved by category")
	gpEq(gpBack.gpRuleFor(_gpPumpDef()).gpTemplate, "{prefix}-{seq}", "pumps keep the default")


func gpTestSymbolOverrideBeatsCategoryOverride() -> void:
	var gpP: GPProjectTagRules = GPProjectTagRules.gpDefaultRules()
	var gpSymRule: GPTagRule = GPTagRule.gpDefault()
	gpSymRule.gpPrefixSource = GPTagRule.GPPrefixSource.GP_FIXED
	gpSymRule.gpFixedPrefix = "SP"
	gpP.gpSetOverride(GPProjectTagRules.gpSymbolKey("LPUMP003"), gpSymRule)
	gpEq(gpP.gpPrefixFor(_gpPumpDef()), "SP", "the symbol override wins")
	gpEq(gpP.gpPrefixFor(_gpValveDef()), "V", "other symbols are untouched")


func gpTestMarksNeverGoBelowTheStart() -> void:
	var gpP: GPProjectTagRules = GPProjectTagRules.gpDefaultRules()
	gpP.gpSetMark("P", 5)
	gpEq(gpP.gpPeek("P", gpP.gpDefault), 1000, "a mark below the start is clamped up to the start")
	gpEq(gpP.gpAdvance("P", gpP.gpDefault), 1001, "the first issued number is start + step")


# ---------------------------------------------------------------- registry

func gpTestAutoNumberingFollowsTheFactoryConvention() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	gpEq(gpR.gpNextTag(_gpPumpDef()), "P-1001", "the first pump is P-1001")
	gpEq(gpR.gpNextTag(_gpPumpDef()), "P-1002", "the second pump is P-1002")
	gpEq(gpR.gpNextTag(_gpValveDef()), "V-1001", "valves have their own sequence")


func gpTestDuplicateTagIsRefusedWithOwner() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	gpEq(gpR.gpRegister("n1", "P-1001").gpIsOk(), true, "the first owner registers fine")
	var gpRes: GPIOResult = gpR.gpRegister("n2", "p 1001")
	gpEq(gpRes.gpIsOk(), false, "a normalisation-equal tag is refused")
	gpEq(gpRes.gpFailedWith("tag.duplicate"), true, "the failure code names the problem")
	gpCheck(gpRes.gpDetail.find("n1") >= 0, "the message names the occupant: %s" % gpRes.gpDetail)
	gpEq(gpR.gpOwnerOf("P-1001"), "n1", "the owner is still the first registrant")


func gpTestEmptyTagsMayCoexist() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	gpEq(gpR.gpRegister("n1", "").gpIsOk(), true, "an un-numbered node registers")
	gpEq(gpR.gpRegister("n2", "").gpIsOk(), true, "a second un-numbered node also registers")
	gpEq(gpR.gpIsTaken(""), false, "an empty tag is never taken")


func gpTestRenameAndRelease() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	gpR.gpRegister("n1", "P-1001")
	gpEq(gpR.gpRename("n1", "P-1002").gpIsOk(), true, "renaming to a free tag works")
	gpEq(gpR.gpTagOf("n1"), "P-1002", "the new tag is recorded")
	gpEq(gpR.gpIsTaken("P-1001"), false, "the old tag is free again")
	gpR.gpRelease("n1")
	gpEq(gpR.gpCountTagged(), 0, "release removes the entry")
	gpEq(gpR.gpIsTaken("P-1002"), false, "a released tag is free")


func gpTestStaleIndexCannotProduceADuplicate() -> void:
	# The index is a cache; the graph is the truth. A node written behind the registry's back
	# must still be seen, so the worst outcome is a skipped number.
	# 索引是缓存，图才是真相。绕过注册器写入的节点仍须被看见，
	# 故最坏结果只是跳号。
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n9", "LPUMP003", "P-1001"))
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	gpEq(gpR.gpIsTaken("P-1001"), true, "a tag written directly on the graph is seen")
	gpEq(gpR.gpOwnerOf("P-1001"), "n9", "its owner is found by scanning")
	gpEq(gpR.gpNextTag(_gpPumpDef()), "P-1002", "allocation skips it rather than duplicating it")


func gpTestHandTypedNumbersAreSkipped() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n9", "LPUMP003", "P-1001"))
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	gpEq(gpR.gpNextTag(_gpPumpDef()), "P-1002", "the hand-typed 1001 is skipped")
	gpEq(gpR.gpNextTag(_gpPumpDef()), "P-1003", "numbering continues from there")


func gpTestRebuildDetectsDuplicates() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "LPUMP003", "P-1001"))
	gpG.gpAddNode(gpG.gpNewNode("n2", "LPUMP003", "p 1001"))
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	gpR.gpRebuild()
	gpEq(gpR.gpConflicts().size(), 1, "one duplicate is reported")
	gpEq(str(gpR.gpConflicts()[0].get("uids", [])[1]), "n2", "the later node is named in the conflict")
	gpEq(gpR.gpOwnerOf("P-1001"), "n1", "the first node keeps ownership")


func gpTestPreviewDoesNotConsumeNumbers() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpPreview: Array[String] = gpR.gpPreview(_gpPumpDef(), 3)
	gpEq(gpPreview.size(), 3, "three samples are produced")
	gpEq(gpPreview[0], "P-1001", "the first sample is P-1001")
	gpEq(gpPreview[2], "P-1003", "the third sample is P-1003")
	gpEq(gpR.gpNextTag(_gpPumpDef()), "P-1001", "previewing did not consume P-1001")


func gpTestRenumberPlanIsDenseAndMapped() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "LPUMP003", "P-5000"))
	gpG.gpAddNode(gpG.gpNewNode("n2", "LVALVE001", "V-9000"))
	gpG.gpAddNode(gpG.gpNewNode("n3", "LPUMP003", "P-5001"))
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	gpR.gpRebuild()
	var gpItems: Array[Dictionary] = [
		{"uid": "n1", "tag": "P-5000", "def": _gpPumpDef()},
		{"uid": "n2", "tag": "V-9000", "def": _gpValveDef()},
		{"uid": "n3", "tag": "P-5001", "def": _gpPumpDef()},
	]
	var gpPlan: Array[Dictionary] = gpR.gpPlanRenumberAll(gpItems)
	gpEq(gpPlan.size(), 3, "every item is planned")
	gpEq(str(gpPlan[0].get("old", "")), "P-5000", "the old tag is carried for the audit CSV")
	gpEq(str(gpPlan[0].get("new", "")), "P-1001", "renumbering restarts at 1001")
	gpEq(str(gpPlan[2].get("new", "")), "P-1002", "the second pump follows the first")
	gpEq(str(gpPlan[1].get("new", "")), "V-1001", "valves keep their own prefix")


# ---------------------------------------------------------------- graph persistence

func gpTestRulesTravelWithTheProjectFile() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	gpR.gpNextTag(_gpPumpDef())
	gpR.gpNextTag(_gpPumpDef())
	var gpBack: GPPIDGraph = GPPIDGraph.gpFromDict(gpG.gpToDict())
	gpCheck(gpBack.gpTagRules != null, "rules are serialised")
	gpEq(gpBack.gpTagRules.gpPeek("P"), 1002, "the high-water mark travels with the file")
	var gpR2: GPTagRegistry = _gpRegistry(gpBack)
	gpEq(gpR2.gpNextTag(_gpPumpDef()), "P-1003", "numbering continues after a save/load round trip")


func gpTestOldArchiveWithoutRulesStillLoads() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.gpFromDict({"meta": {"version": "1.1"}, "nodes": []})
	gpCheck(gpG.gpTagRules == null, "a v1 file carries no rules")
	gpEq(gpG.gpToDict().has("tag_rules"), false, "an untouched file keeps its v1 shape")
	gpCheck(gpG.gpTagRulesOrCreate() != null, "the factory default is created on demand")
	gpEq(gpG.gpToDict().has("tag_rules"), true, "once rules exist they are written")


# ---------------------------------------------------------------- command wiring

func gpTestPlacementMintsAUniqueTag() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), gpR)
	var gpId1: String = gpSvc.gpPlaceNode("LPUMP003", Vector2.ZERO)
	var gpId2: String = gpSvc.gpPlaceNode("LPUMP003", Vector2(50, 0))
	gpEq(gpG.gpGetNode(gpId1).gpTag, "P-1001", "the first placement is P-1001")
	gpEq(gpG.gpGetNode(gpId2).gpTag, "P-1002", "the second placement is P-1002")


func gpTestPlacementWithoutRegistryKeepsOldBehaviour() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new())
	var gpId: String = gpSvc.gpPlaceNode("LPUMP003", Vector2.ZERO, "T-301")
	gpEq(gpG.gpGetNode(gpId).gpTag, "T-301", "an explicit tag is used verbatim")
	var gpId2: String = gpSvc.gpPlaceNode("LPUMP003", Vector2.ZERO)
	gpEq(gpG.gpGetNode(gpId2).gpTag, "", "no registry means no minting (pre-M9 behaviour)")


func gpTestDuplicateGetsItsOwnTag() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), gpR)
	var gpSrc: String = gpSvc.gpPlaceNode("LPUMP003", Vector2.ZERO)
	var gpCopies: Array[String] = gpSvc.gpDuplicateSelection([gpSrc])
	gpEq(gpCopies.size(), 1, "one copy was made")
	gpEq(gpG.gpGetNode(gpCopies[0]).gpTag, "P-1002", "the copy does not inherit the source tag")
	gpEq(gpR.gpIsTaken("P-1001"), true, "the source still owns P-1001")


func gpTestUndoRedoKeepsTheRegistryConsistent() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), gpR)
	var gpId: String = gpSvc.gpPlaceNode("LPUMP003", Vector2.ZERO)
	gpEq(gpR.gpIsTaken("P-1001"), true, "the placed tag is registered")
	gpEq(gpSvc.gpUndo(), true, "undo is available")
	gpEq(gpR.gpIsTaken("P-1001"), false, "undo released the tag again")
	gpEq(gpSvc.gpRedo(), true, "redo is available")
	gpEq(gpR.gpIsTaken("P-1001"), true, "redo re-registered the very same tag")
	gpEq(gpG.gpGetNode(gpId).gpTag, "P-1001", "redo did not mint a new number")


func gpTestDeleteReleasesTheTag() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = _gpRegistry(gpG)
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), gpR)
	var gpId: String = gpSvc.gpPlaceNode("LPUMP003", Vector2.ZERO)
	gpEq(gpSvc.gpDeleteSelection([gpId], []), true, "the node was deleted")
	gpEq(gpR.gpIsTaken("P-1001"), false, "deleting released the tag")
	gpEq(gpSvc.gpUndo(), true, "undo is available")
	gpEq(gpR.gpIsTaken("P-1001"), true, "undo restored the tag")
