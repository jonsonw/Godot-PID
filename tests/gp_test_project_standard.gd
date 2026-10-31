class_name GpTestProjectStandard
extends GPGTest
# Headless tests for the project standard (ADR-36, step A1).
# 项目标准（ADR-36，A1 步）的 headless 测试。
#
# The promises being pinned / 被钉住的承诺：
# 1. a v1 archive loads into LEGACY mode and re-saves byte for byte (no silent format drift);
# 2. the v2 shape round-trips, and every class keeps its own rules and sequence marks;
# 3. several sheets of one project share ONE standard object, so a rule edited on sheet 2 is
#    the rule that was saved (the bug: sheet 2's rules used to vanish on save);
# 4. code tables resolve labels / aliases to a code, and classification sends a valve to the
#    manual-valve or instrument class according to its actuator (ADR-36 D5).
# 1. v1 存档以 legacy 模式载入并逐字节保存（格式不静默漂移）；
# 2. v2 形态可往返，且每个类别保有各自的规则与水位线；
# 3. 同一工程的若干图纸共享**一个**标准对象，故第二页改的规则就是存下来的规则
#    （此前的 bug：第二页的规则保存时消失）；
# 4. 代号表能把名称 / 别名解析为代号；分类按执行机构把阀门送进手阀或仪表类别（ADR-36 D5）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_TMP: String = "user://gp_test_standard.pid.json"


# A tiny stand-in for the project shell: it owns the shared standard and hands it out lazily,
# exactly like GPCenterArea does for real tabs.
# 工程外壳的极简替身：持有共享标准并惰性交出，与真实的 GPCenterArea 对标签页所做的一致。
class GPStandardHolder:
	var gpStandard: GPProjectStandard = null

	func gpGet() -> GPProjectStandard:
		if gpStandard == null:
			gpStandard = GPProjectStandard.gpDefaultStandard()
		return gpStandard


func _gpCleanup() -> void:
	var gpAbs: String = ProjectSettings.globalize_path(GP_TMP)
	if FileAccess.file_exists(gpAbs):
		DirAccess.remove_absolute(gpAbs)


func _gpPumpDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolLibrary.gpFindById("DPUMP001")
	if gpD != null:
		return gpD
	var gpF: GPSymbolDef = GPSymbolDef.new()
	gpF.gpId = "DPUMP001"
	gpF.gpCategory = "pump"
	gpF.gpTagPrefix = "P"
	return gpF


func _gpValveDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "DVALVE002"
	gpD.gpCategory = "valve"
	gpD.gpTagPrefix = "V"
	return gpD


# A v1 rules block, shaped exactly as GPProjectTagRules.gpToDict() has always written it.
# 一个 v1 规则块，形态与 GPProjectTagRules.gpToDict() 一贯写出的一致。
func _gpV1Dict() -> Dictionary:
	return {
		"version": 1,
		"default": {
			"template": "{prefix}-{seq}",
			"start": 1000,
			"step": 1,
			"digits": 0,
			"prefix_source": 0,
			"fixed_prefix": "",
			"category_prefixes": {"pump": "P", "valve": "V", "instrument": "I"},
			"symbol_prefixes": {},
		},
		"overrides": {},
		"seq_marks": {"P": 1002},
	}


# A registry bound to a graph, with the graph's own rules.
# 绑定到某图的注册器，使用该图自己的规则。
func _gpRegistry(gpGraph: GPPIDGraph) -> GPTagRegistry:
	var gpR: GPTagRegistry = GPTagRegistry.new()
	gpR.gpGraph = gpGraph
	gpR.gpRules = gpGraph.gpTagRulesOrCreate()
	gpR.gpRebuild()
	return gpR


# ---------------------------------------------------------------- factory

func gpTestFactoryStandardHasFiveClasses() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpEq(GPProjectStandard.gpClassIds().size(), 5, "five numbering classes")
	for gpClass in GPProjectStandard.GP_CLASS_IDS:
		gpCheck(gpStd.gpRulesOf(gpClass) != null, "class has rules: " + gpClass)
	gpCheck(gpStd.gpEnabled(GPProjectStandard.GP_CLASS_EQUIPMENT), "equipment numbers by default")
	gpCheck(gpStd.gpEnabled(GPProjectStandard.GP_CLASS_INSTRUMENT), "instrument numbers by default")
	gpCheck(gpStd.gpEnabled(GPProjectStandard.GP_CLASS_LINE), "line numbers by default")
	gpCheck(not gpStd.gpEnabled(GPProjectStandard.GP_CLASS_MANUAL_VALVE),
		"manual valves are NOT numbered by default (D5)")
	gpCheck(gpStd.gpEnabled(GPProjectStandard.GP_CLASS_SPECIAL_ITEM),
		"special items are numbered by default (D5)")
	gpEq(gpStd.gpScopeOf(GPProjectStandard.GP_CLASS_LINE), GPProjectStandard.GP_SCOPE_SHEET,
		"lines are unique per sheet (D1)")
	gpEq(gpStd.gpScopeOf(GPProjectStandard.GP_CLASS_EQUIPMENT),
		GPProjectStandard.GP_SCOPE_PROJECT, "equipment is unique project-wide (D1)")
	gpCheck(gpStd.gpAllowsCrossSheet(GPProjectStandard.GP_CLASS_LINE),
		"a line number may continue onto another sheet (D1)")


func gpTestFactoryEquipmentRuleIsUnchanged() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpRules: GPProjectTagRules = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_EQUIPMENT)
	gpEq(gpRules.gpDefault.gpTemplate, "{prefix}-{seq}", "the historic template survives")
	gpEq(gpRules.gpPrefixFor(_gpPumpDef()), "P", "pumps are still P")
	gpEq(gpRules.gpPrefixFor(_gpValveDef()), "V", "valves are still V")


# ---------------------------------------------------------------- legacy compatibility

func gpTestLegacyArchiveLoadsAndSavesByteIdentical() -> void:
	var gpV1: Dictionary = _gpV1Dict()
	var gpStd: GPProjectStandard = GPProjectStandard.gpFromDict(gpV1)
	gpCheck(gpStd.gpIsLegacy(), "a v1 block puts the standard in legacy mode")
	gpEq(gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_EQUIPMENT).gpPeek("P"), 1002,
		"the equipment mark is restored")
	# Byte-level claim: the emitted block must equal what the old writer produced. Compared
	# with sort_keys=false, so key ORDER counts too — stricter than the on-disk text (which
	# GPAtomicFile sorts) and therefore a safe superset of "the archive did not change".
	# 逐字节主张：输出的块必须与旧写出方一致。比较时 sort_keys=false，故键顺序也纳入 ——
	# 比落盘文本（GPAtomicFile 会排序）更严格，因而是「存档未变」的安全超集。
	gpEq(JSON.stringify(gpStd.gpToDict(), "", false), JSON.stringify(gpV1, "", false),
		"a legacy standard re-saves the v1 block verbatim")


func gpTestLegacyGraphKeepsItsV1Shape() -> void:
	var gpV1: Dictionary = _gpV1Dict()
	var gpG: GPPIDGraph = GPPIDGraph.gpFromDict({
		"meta": {"version": "1.1"}, "nodes": [], "tag_rules": gpV1,
	})
	gpEq(JSON.stringify(gpG.gpToDict()["tag_rules"], "", false),
		JSON.stringify(gpV1, "", false), "the graph writes the v1 block unchanged")
	gpCheck(gpG.gpStandard != null, "the graph holds a standard")
	gpCheck(gpG.gpStandard.gpIsLegacy(), "and it is still legacy")


func gpTestUntouchedGraphStillWritesNoRules() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.gpFromDict({"meta": {"version": "1.1"}, "nodes": []})
	gpCheck(gpG.gpStandard == null, "no rules, no standard")
	gpEq(gpG.gpToDict().has("tag_rules"), false, "an untouched file keeps its v1 shape")


func gpTestTouchingAV2FieldUpgradesTheShape() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpFromDict(_gpV1Dict())
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_MATERIAL,
		[{"code": "A1A", "label": "碳钢", "aliases": []}])
	gpCheck(not gpStd.gpIsLegacy(), "editing a code table leaves legacy mode")
	var gpOut: Dictionary = gpStd.gpToDict()
	gpEq(int(gpOut.get("version", 0)), GPProjectStandard.GP_VERSION, "the block is now v2")
	gpEq(str(gpOut.get("schema", "")), GPProjectStandard.GP_SCHEMA, "and names its schema")


# ---------------------------------------------------------------- v2 round trip

func gpTestV2RoundTripKeepsEveryClass() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_MATERIAL,
		[{"code": "A1A", "label": "碳钢", "aliases": ["Carbon Steel"]}])
	gpStd.gpSetEnabled(GPProjectStandard.GP_CLASS_MANUAL_VALVE, true)
	gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpDefault.gpStart = 2000
	gpStd.gpRevision["name"] = "某项目编号标准"
	var gpBack: GPProjectStandard = GPProjectStandard.gpFromDict(gpStd.gpToDict())
	gpCheck(gpBack != null, "v2 parses")
	if gpBack == null:
		return
	gpCheck(not gpBack.gpIsLegacy(), "v2 is never legacy")
	gpCheck(gpBack.gpEnabled(GPProjectStandard.GP_CLASS_MANUAL_VALVE),
		"the enable flag survives")
	gpEq(gpBack.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpDefault.gpStart, 2000,
		"the line rule survives")
	gpEq(gpBack.gpCodeOf(GPProjectStandard.GP_TABLE_MATERIAL, "Carbon Steel"), "A1A",
		"the code table survives and still resolves aliases")
	gpEq(str(gpBack.gpRevision.get("name", "")), "某项目编号标准", "the revision block survives")


func gpTestClassMarksAreIndependent() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpEquip: GPProjectTagRules = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_EQUIPMENT)
	var gpLine: GPProjectTagRules = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE)
	gpEquip.gpAdvance("P")
	gpLine.gpAdvance("PL")
	gpEq(gpEquip.gpPeek("P"), 1001, "equipment consumed P-1001")
	gpEq(gpEquip.gpPeek("PL"), 1000, "the line counter is untouched by equipment")
	gpEq(gpLine.gpPeek("PL"), 1001, "the line class consumed PL-1001")


# ---------------------------------------------------------------- code tables

func gpTestCodeLookupByCodeLabelAndAlias() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpEq(gpStd.gpCodeOf(GPProjectStandard.GP_TABLE_MEDIUM, "CWR"), "CWR", "exact code")
	gpEq(gpStd.gpCodeOf(GPProjectStandard.GP_TABLE_MEDIUM, "cwr"), "CWR", "case-insensitive")
	gpEq(gpStd.gpCodeOf(GPProjectStandard.GP_TABLE_MEDIUM, "循环冷却水"), "CWR", "label")
	gpEq(gpStd.gpCodeOf(GPProjectStandard.GP_TABLE_MEDIUM, "冷却水"), "",
		"a substring is not an alias — matching is exact after normalisation")
	gpEq(gpStd.gpCodeOf(GPProjectStandard.GP_TABLE_MEDIUM, "工艺水"), "PW", "second row")
	gpEq(gpStd.gpCodeOf(GPProjectStandard.GP_TABLE_MEDIUM, ""), "", "empty resolves to empty")
	gpEq(gpStd.gpCodeOf("no_such_table", "PW"), "", "unknown table resolves to empty")


func gpTestFactoryCodeTablesHaveMediumPipeClassAndInsulation() -> void:
	# 2026-10-28: pipe class and insulation are no longer empty — the line attribute panel needs
	# pickers, and a picker over an empty table is just a text field.
	# 2026-10-28：管道等级与保温不再为空 —— 管线属性面板需要下拉，而空表上的下拉就是文本框。
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpCheck(gpStd.gpCodeTable(GPProjectStandard.GP_TABLE_MEDIUM).size() > 0,
		"the medium table has seed rows")
	gpCheck(gpStd.gpCodeTable(GPProjectStandard.GP_TABLE_MATERIAL).size() >= 3,
		"the pipe-class table has factory rows")
	gpCheck(gpStd.gpCodeTable(GPProjectStandard.GP_TABLE_INSULATION).size() >= 3,
		"the insulation table has factory rows")
	gpCheck(gpStd.gpValidate().gpIsOk(), "the factory tables are internally valid (no duplicate codes)")


func gpTestDuplicateCodeIsRejected() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_MATERIAL, [
		{"code": "A1A", "label": "碳钢", "aliases": []},
		{"code": "a1a", "label": "重复", "aliases": []},
	])
	var gpRes: GPIOResult = gpStd.gpValidate()
	gpCheck(not gpRes.gpIsOk(), "a duplicate code is a validation failure")


# ---------------------------------------------------------------- classification

func gpTestClassificationByCategory() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpEq(gpStd.gpClassOf(_gpPumpDef()), GPProjectStandard.GP_CLASS_EQUIPMENT, "a pump is equipment")
	var gpGeneral: GPSymbolDef = GPSymbolDef.new()
	gpGeneral.gpId = "DGENERAL999"
	gpGeneral.gpCategory = "general"
	gpEq(gpStd.gpClassOf(gpGeneral), "", "an unmapped category is not numbered automatically")


func gpTestValveClassFollowsItsActuator() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpValve: GPSymbolDef = _gpValveDef()
	gpEq(gpStd.gpClassOf(gpValve, {"actuator_type": "手动"}),
		GPProjectStandard.GP_CLASS_MANUAL_VALVE, "a hand valve is a manual valve")
	gpEq(gpStd.gpClassOf(gpValve, {"actuator_type": "无"}),
		GPProjectStandard.GP_CLASS_MANUAL_VALVE, "no actuator counts as manual")
	gpEq(gpStd.gpClassOf(gpValve, {"actuator_type": "气动"}),
		GPProjectStandard.GP_CLASS_INSTRUMENT, "a pneumatic valve is an instrument (D5)")
	gpEq(gpStd.gpClassOf(gpValve, {"actuator_type": "电动"}),
		GPProjectStandard.GP_CLASS_INSTRUMENT, "an electric valve is an instrument (D5)")
	gpEq(gpStd.gpClassOf(gpValve, {}),
		GPProjectStandard.GP_CLASS_MANUAL_VALVE, "a valve without the property defaults to manual")
	var gpInstrument: GPSymbolDef = GPSymbolDef.new()
	gpInstrument.gpId = "DINSTR001"
	gpInstrument.gpCategory = "instrument"
	gpEq(gpStd.gpClassOf(gpInstrument, {}), GPProjectStandard.GP_CLASS_INSTRUMENT,
		"an instrument is an instrument whatever its properties")


func gpTestSymbolOverrideWins() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpStd.gpClassification["by_symbol"] = {"DGENERAL009": GPProjectStandard.GP_CLASS_SPECIAL_ITEM}
	var gpFilter: GPSymbolDef = GPSymbolDef.new()
	gpFilter.gpId = "DGENERAL009"
	gpFilter.gpCategory = "general"
	gpEq(gpStd.gpClassOf(gpFilter), GPProjectStandard.GP_CLASS_SPECIAL_ITEM,
		"a symbol override beats the category table")


# ---------------------------------------------------------------- sharing across sheets

func gpTestNewGraphAdoptsTheStandardAndSharesMarks() -> void:
	var gpA: GPPIDGraph = GPPIDGraph.new()
	var gpRegA: GPTagRegistry = _gpRegistry(gpA)
	gpEq(gpRegA.gpNextTag(_gpPumpDef()), "P-1001", "sheet A mints P-1001")
	var gpB: GPPIDGraph = GPPIDGraph.new()
	gpB.gpAdoptStandard(gpA.gpStandard)
	gpCheck(gpA.gpStandard == gpB.gpStandard, "both graphs hold the same standard object")
	var gpRegB: GPTagRegistry = _gpRegistry(gpB)
	gpEq(gpRegB.gpNextTag(_gpPumpDef()), "P-1002",
		"sheet B continues the project sequence instead of restarting at 1001")


func gpTestSheetsShareOneStandardAfterReopen() -> void:
	_gpCleanup()
	var gpSheets: Array = []
	var gpI: int = 0
	for gpName in ["给料", "磨矿"]:
		var gpSheet: GPSheet = GPSheet.gpNew("sheet-" + str(gpI + 1), gpName, gpI)
		gpSheets.append(gpSheet)
		gpI += 1
	# Both tabs must adopt the same standard in memory (the project has one convention).
	# 两个标签页在内存中须采纳同一个标准（一个工程一套约定）。
	var gpFirstGraph: GPPIDGraph = (gpSheets[0] as GPSheet).gpGraph
	gpFirstGraph.gpTagRulesOrCreate().gpAdvance("P")
	for gpSheetRaw in gpSheets:
		(gpSheetRaw as GPSheet).gpGraph.gpAdoptStandard(gpFirstGraph.gpStandard)
	var gpW: GPIOResult = GPProjectIO.gpWriteSheetsResult(gpSheets, GP_TMP)
	gpCheck(gpW.gpIsOk(), "write must succeed: " + gpW.gpToString())
	if not gpW.gpIsOk():
		_gpCleanup()
		return
	var gpR: GPIOResult = GPProjectIO.gpReadSheets(GP_TMP)
	gpCheck(gpR.gpIsOk(), "read must succeed: " + gpR.gpToString())
	if not gpR.gpIsOk():
		_gpCleanup()
		return
	var gpBack: Array = gpR.gpPayload as Array
	gpEq(gpBack.size(), 2, "both sheets come back")
	if gpBack.size() < 2:
		_gpCleanup()
		return
	var gpA: GPPIDGraph = (gpBack[0] as GPSheet).gpGraph
	var gpB: GPPIDGraph = (gpBack[1] as GPSheet).gpGraph
	gpCheck(gpA.gpStandard != null and gpB.gpStandard != null, "both graphs have a standard")
	if gpA.gpStandard != null and gpB.gpStandard != null:
		gpCheck(gpA.gpStandard == gpB.gpStandard,
			"the two sheets share ONE standard object after reopen")
		gpEq(gpA.gpStandard.gpRulesOf(GPProjectStandard.GP_CLASS_EQUIPMENT).gpPeek("P"), 1001,
			"the shared mark is restored once")
	_gpCleanup()


func gpTestSecondSheetRuleEditPersists() -> void:
	_gpCleanup()
	var gpSheets: Array = []
	var gpI: int = 0
	for gpName in ["给料", "磨矿"]:
		gpSheets.append(GPSheet.gpNew("sheet-" + str(gpI + 1), gpName, gpI))
		gpI += 1
	var gpGraph: GPPIDGraph = (gpSheets[0] as GPSheet).gpGraph
	gpGraph.gpTagRulesOrCreate().gpAdvance("P")
	for gpSheetRaw in gpSheets:
		(gpSheetRaw as GPSheet).gpGraph.gpAdoptStandard(gpGraph.gpStandard)
	gpCheck(GPProjectIO.gpWriteSheetsResult(gpSheets, GP_TMP).gpIsOk(), "first write succeeds")
	var gpR: GPIOResult = GPProjectIO.gpReadSheets(GP_TMP)
	if not gpR.gpIsOk():
		gpCheck(false, "read failed: " + gpR.gpToString())
		_gpCleanup()
		return
	var gpBack: Array = gpR.gpPayload as Array
	# Edit the convention from sheet 2, as a user would with that tab active.
	# 以第二张图纸为活动页改约定，正如用户会做的那样。
	var gpSheet2: GPSheet = gpBack[1] as GPSheet
	var gpStd: GPProjectStandard = gpSheet2.gpGraph.gpStandard
	gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpDefault.gpStart = 3000
	gpStd.gpTouch()
	gpCheck(GPProjectIO.gpWriteSheetsResult(gpBack, GP_TMP).gpIsOk(), "second write succeeds")
	var gpR2: GPIOResult = GPProjectIO.gpReadSheets(GP_TMP)
	if not gpR2.gpIsOk():
		gpCheck(false, "second read failed: " + gpR2.gpToString())
		_gpCleanup()
		return
	var gpBack2: Array = gpR2.gpPayload as Array
	var gpStd2: GPProjectStandard = (gpBack2[0] as GPSheet).gpGraph.gpStandard
	gpEq(gpStd2.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpDefault.gpStart, 3000,
		"a rule edited on sheet 2 is the rule that was saved (the old bug)")
	_gpCleanup()

func gpTestLazyProviderSharesOneStandardAcrossFreshTabs() -> void:
	var gpHolder: GPStandardHolder = GPStandardHolder.new()
	var gpA: GPPIDGraph = GPPIDGraph.new()
	gpA.gpStandardProvider = Callable(gpHolder, "gpGet")
	var gpB: GPPIDGraph = GPPIDGraph.new()
	gpB.gpStandardProvider = Callable(gpHolder, "gpGet")
	# The two tabs were created BEFORE anything was numbered — the case that used to make
	# each tab start from its own factory copy and mint P-1001 twice.
	# 两张图纸都在任何编号发生**之前**建立 —— 这正是过去让每页各自从出厂副本起步、
	# 两页各发一个 P-1001 的情形。
	gpCheck(gpHolder.gpStandard == null, "asking is what creates the standard, not creating a tab")
	gpEq(gpA.gpToDict().has("tag_rules"), false, "a tab that numbered nothing writes no rules")
	gpEq(_gpRegistry(gpA).gpNextTag(_gpPumpDef()), "P-1001", "the first tab mints P-1001")
	gpEq(_gpRegistry(gpB).gpNextTag(_gpPumpDef()), "P-1002",
		"the second tab continues the SAME sequence instead of restarting")
	gpCheck(gpA.gpStandard == gpB.gpStandard, "both tabs share one standard object")
