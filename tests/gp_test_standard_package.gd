class_name GpTestStandardPackage
extends GPGTest
# Headless tests for the portable project standard (ADR-36 B).
# 可移植项目标准（ADR-36 B）的 headless 测试。
#
# The promises being pinned / 被钉住的承诺：
# 1. the package carries the CONVENTION and NOT the marks — a new project starts its own
#    counters instead of continuing someone else's;
# 2. classes / code tables / classification survive a round trip;
# 3. a legacy `.gptagrule.json` still imports, and re-exporting it produces the v2 package;
# 4. the import preview reports what would actually change (and nothing when nothing does);
# 5. broken text is reported, never silently replaced by the factory standard.
# 1. 标准包带走**约定**、不带走水位线 —— 新工程从自己的计数器起步，而不是接着别人的跑；
# 2. 类别 / 代号表 / 分类映射往返不丢；
# 3. 旧式 `.gptagrule.json` 仍能导入，且再导出时产出 v2 标准包；
# 4. 导入预览报告**真正会变**的东西（没变就什么都不报）；
# 5. 坏文本会被报出来，绝不静默换成出厂标准。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


func _gpStdWithMarks() -> GPProjectStandard:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	# Pretend this project has already issued P-1001…P-1042.
	# 假装本工程已经发出过 P-1001…P-1042。
	gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_EQUIPMENT).gpSetMark("P", 1042)
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_MATERIAL,
		[{"code": "A1A", "label": "碳钢", "aliases": ["Carbon Steel"]}])
	gpStd.gpSetEnabled(GPProjectStandard.GP_CLASS_MANUAL_VALVE, true)
	gpStd.gpRevision["name"] = "某项目编号标准"
	return gpStd


# ---------------------------------------------------------------- package contents

func gpTestPackageCarriesConventionNotMarks() -> void:
	var gpStd: GPProjectStandard = _gpStdWithMarks()
	var gpText: String = GPTagRuleService.gpStandardToJson(gpStd)
	gpCheck(gpText.find("\"kind\": \"standard\"") >= 0, "the package names its kind")
	gpCheck(gpText.find("seq_marks") < 0,
		"the marks are NOT exported — a new project must start its own counters")
	var gpBack: GPProjectStandard = GPTagRuleService.gpStandardFromJson(gpText)
	gpCheck(gpBack != null, "the package parses")
	if gpBack == null:
		return
	gpEq(gpBack.gpRulesOf(GPProjectStandard.GP_CLASS_EQUIPMENT).gpPeek("P"),
		GPTagRule.GP_DEFAULT_START, "the counter restarts at the rule's start")


func gpTestPackageRoundTripsClassesTablesAndClassification() -> void:
	var gpStd: GPProjectStandard = _gpStdWithMarks()
	gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpDefault.gpStart = 5
	gpStd.gpClassification["by_symbol"] = {"DGENERAL009": GPProjectStandard.GP_CLASS_SPECIAL_ITEM}
	var gpBack: GPProjectStandard = GPTagRuleService.gpStandardFromJson(
		GPTagRuleService.gpStandardToJson(gpStd))
	gpCheck(gpBack != null, "round trip parses")
	if gpBack == null:
		return
	gpCheck(gpBack.gpEnabled(GPProjectStandard.GP_CLASS_MANUAL_VALVE),
		"the enable flag survives")
	gpEq(gpBack.gpCodeOf(GPProjectStandard.GP_TABLE_MATERIAL, "Carbon Steel"), "A1A",
		"the code table survives")
	gpEq(gpBack.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpDefault.gpStart, 5,
		"the line rule survives")
	gpEq(str(gpBack.gpClassification.get("by_symbol", {}).get("DGENERAL009", "")),
		GPProjectStandard.GP_CLASS_SPECIAL_ITEM, "the classification survives")
	gpEq(str(gpBack.gpRevision.get("name", "")), "某项目编号标准", "the revision block survives")


# ---------------------------------------------------------------- legacy bridge

func gpTestLegacyRulesJsonStillImports() -> void:
	# What the old dialog exported. / 旧对话框导出的东西。
	var gpRules: GPProjectTagRules = GPProjectTagRules.gpDefaultRules()
	gpRules.gpAdvance("P")
	var gpText: String = GPTagRuleService.gpRulesToJson(gpRules)
	var gpStd: GPProjectStandard = GPTagRuleService.gpStandardFromJson(gpText)
	gpCheck(gpStd != null, "a legacy rules file still imports")
	if gpStd == null:
		return
	gpCheck(gpStd.gpIsLegacy(), "and it imports as a legacy standard")
	gpEq(gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_EQUIPMENT).gpPeek("P"), 1001,
		"its equipment marks are preserved")


func gpTestLegacyStandardExportsAsV2() -> void:
	var gpV1: Dictionary = {
		"version": 1,
		"default": {
			"template": "{prefix}-{seq}", "start": 2000, "step": 1, "digits": 0,
			"prefix_source": 0, "fixed_prefix": "",
			"category_prefixes": {"pump": "P"}, "symbol_prefixes": {},
		},
		"overrides": {}, "seq_marks": {"P": 2003},
	}
	var gpStd: GPProjectStandard = GPProjectStandard.gpFromDict(gpV1)
	gpCheck(gpStd.gpIsLegacy(), "loaded as legacy")
	var gpText: String = GPTagRuleService.gpStandardToJson(gpStd)
	var gpParsed: Variant = JSON.parse_string(gpText)
	gpCheck(gpParsed is Dictionary, "exported text is JSON")
	if gpParsed is Dictionary:
		var gpRules: Dictionary = (gpParsed as Dictionary).get("tag_rules", {}) as Dictionary
		gpEq(int(gpRules.get("version", 0)), GPProjectStandard.GP_VERSION,
			"exporting a legacy project hands the receiver the v2 shape")
		gpCheck(gpText.find("seq_marks") < 0, "and never the marks")


# ---------------------------------------------------------------- import preview

func gpTestDiffReportsWhatWouldChange() -> void:
	var gpBefore: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpAfter: GPProjectStandard = _gpStdWithMarks()
	gpAfter.gpClassification["by_symbol"] = {"DGENERAL009": GPProjectStandard.GP_CLASS_SPECIAL_ITEM}
	var gpRows: Array[Dictionary] = GPTagRuleService.gpStandardDiff(gpBefore, gpAfter)
	gpCheck(gpRows.size() >= 3, "enable flag, code table and classification are all reported")
	var gpText: String = ""
	for gpRow in gpRows:
		gpText += str(gpRow.get("text", "")) + "\n"
	gpCheck(gpText.find("手动阀门") >= 0, "the class change names the class")
	gpCheck(gpText.find("medium") >= 0 or gpText.find("material") >= 0,
		"the code-table change names the table")
	gpCheck(gpText.find("DGENERAL009") >= 0, "the classification change names the symbol")


func gpTestDiffIsEmptyWhenNothingChanges() -> void:
	var gpStd: GPProjectStandard = _gpStdWithMarks()
	var gpRows: Array[Dictionary] = GPTagRuleService.gpStandardDiff(gpStd, gpStd.gpClone())
	gpEq(gpRows.size(), 0, "a clone differs in nothing")


func gpTestBrokenPackageIsReportedNotDefaulted() -> void:
	# NOTE: malformed JSON (unparseable text) is already covered by the project-IO suite; here we
	# only assert the "valid JSON, wrong shape" half, so the gate stays free of engine ERROR noise.
	# 注意：非法 JSON（根本解析不了）已由 project-IO 套件覆盖；这里只断言「合法 JSON 但形状不对」
	# 那一半，使门禁不被引擎 ERROR 噪声污染。
	gpCheck(GPTagRuleService.gpStandardFromJson("\"just a string\"") == null,
		"a JSON string is not a standard")
	gpCheck(GPTagRuleService.gpStandardFromJson("[1, 2, 3]") == null,
		"a non-object root is reported as unreadable")
	gpCheck(GPTagRuleService.gpStandardFromJson("{}") == null,
		"an empty object is not silently turned into the factory standard")


# ---------------------------------------------------------------- dialog sizing

func gpTestDialogSizesItselfToContentAndScreen() -> void:
	# The reported bug: the dialog occupied the whole vertical screen.
	# 用户报告的缺陷：对话框占满整个竖向屏幕。
	# ADR-37 rule: content + 24, floored by the design minimum, capped by the design maximum and
	# by the available area.
	# ADR-37 规则：内容 + 24，受设计下限托底、受设计上限与可用区域双重封顶。
	var gpMin: Vector2i = Vector2i(760, 420)
	var gpMax: Vector2i = Vector2i(1000, 720)
	gpEq(GPWindowFit.gpContentSize(Vector2i(300, 200), Vector2i(1000, 800), gpMin, gpMax),
		Vector2i(760, 420), "small content gets the minimum window")
	gpEq(GPWindowFit.gpContentSize(Vector2i(2000, 1500), Vector2i(1000, 800), gpMin, gpMax),
		Vector2i(1000, 720), "large content is capped by the design maximum")
	# 700 + 24 = 724 < the 760 floor, so the floor wins; the height is natural (500 + 24).
	# 700+24=724 小于 760 下限，故取下限；高度保持自然值（500+24）。
	gpEq(GPWindowFit.gpContentSize(Vector2i(700, 500), Vector2i(1000, 800), gpMin, gpMax),
		Vector2i(760, 524), "content below the floor is raised to it; height stays natural")
	gpEq(GPWindowFit.gpContentSize(Vector2i(1200, 1200), Vector2i(700, 480), gpMin, gpMax),
		Vector2i(700, 480), "a small parent area caps the window, never overflowing it")


# ---------------------------------------------------------------- code-table migration

func gpTestOldProjectGetsTheFactoryCodeTablesOnce() -> void:
	# A project written BEFORE the pipe-class / insulation seeds: both tables empty and no
	# `seed_migrated` flag. Opening it must fill them, or the line panel has no pickers.
	# 在管道等级/保温种子出现**之前**写出的工程：两张表为空、没有 `seed_migrated` 标志。
	# 打开它必须补上，否则管线面板没有下拉。
	var gpV2: Dictionary = GPProjectStandard.gpDefaultStandard().gpToDict()
	(gpV2["code_tables"] as Dictionary)[GPProjectStandard.GP_TABLE_MATERIAL] = []
	(gpV2["code_tables"] as Dictionary)[GPProjectStandard.GP_TABLE_INSULATION] = []
	gpV2.erase("seed_migrated")
	var gpStd: GPProjectStandard = GPProjectStandard.gpFromDict(gpV2)
	gpCheck(gpStd.gpCodeTable(GPProjectStandard.GP_TABLE_MATERIAL).size() >= 3,
		"the empty pipe-class table is seeded on open")
	gpCheck(gpStd.gpCodeTable(GPProjectStandard.GP_TABLE_INSULATION).size() >= 3,
		"the empty insulation table is seeded on open")
	gpCheck(gpStd.gpSeedMigrated, "and the one-time flag is set")


func gpTestClearedTableIsNotResurrected() -> void:
	# Once the migration ran, an intentionally emptied table must STAY empty on the next open —
	# otherwise "I deleted these rows" is impossible to express.
	# 迁移跑过之后，被刻意清空的表在下次打开时必须**保持为空** —— 否则「我把这些行删了」无法表达。
	var gpStd: GPProjectStandard = GPProjectStandard.gpFromDict(
		GPProjectStandard.gpDefaultStandard().gpToDict())
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_MATERIAL, [])
	var gpBack: GPProjectStandard = GPProjectStandard.gpFromDict(gpStd.gpToDict())
	gpEq(gpBack.gpCodeTable(GPProjectStandard.GP_TABLE_MATERIAL).size(), 0,
		"a deliberately emptied table survives a reopen")


func gpTestLinePanelGetsPickersForPipeClassAndInsulation() -> void:
	# The reported bug: 管道等级 and 保温 had no dropdown because the tables were empty.
	# 用户报告的缺陷：管道等级与保温没有下拉，因为表是空的。
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpMtl: GPTagSegment = null
	var gpIns: GPTagSegment = null
	for gpSegRaw in gpRule.gpSegments:
		var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
		if gpSeg.gpKey == "mtl":
			gpMtl = gpSeg
		elif gpSeg.gpKey == "in":
			gpIns = gpSeg
	gpCheck(GPLineAttrsDialog.gpChoicesFor(gpMtl, gpStd).size() >= 3,
		"the pipe-class field now offers the factory codes")
	gpCheck(GPLineAttrsDialog.gpChoicesFor(gpIns, gpStd).size() >= 3,
		"the insulation field now offers the factory codes")


func gpTestPipeClassAcceptsTheChineseAlias() -> void:
	# The picker stores codes, but a typed Chinese name must still resolve (old drawings,
	# hand-edited XLSX): "不锈钢" -> A2A.
	# 下拉存代号，但手打的中文名仍要能解析（旧图、手改的 XLSX）："不锈钢" -> A2A。
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpEq(gpStd.gpCodeOf(GPProjectStandard.GP_TABLE_MATERIAL, "不锈钢"), "A2A",
		"the Chinese alias resolves to its code")
	gpEq(gpStd.gpCodeOf(GPProjectStandard.GP_TABLE_INSULATION, "保冷"), "C",
		"insulation aliases resolve as well")


# ---------------------------------------------------------------- project info / sheet numbers

func gpTestProjectInfoAndSheetRuleSurviveRoundTrip() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpStd.gpProjectInfo["owner"] = "某业主"
	gpStd.gpProjectInfo["project_name"] = "某项目"
	gpStd.gpProjectInfo["project_no"] = "PRJ"
	gpStd.gpProjectInfo["stage"] = "施工图"
	gpStd.gpProjectInfo["designed"] = "张三"
	gpStd.gpProjectInfo["checked"] = "李四"
	gpStd.gpProjectInfo["approved"] = "王五"
	gpStd.gpSheetNoRule["template"] = "{project_no}-{stage}-{seq:3}"
	var gpBack: GPProjectStandard = GPTagRuleService.gpStandardFromJson(
		GPTagRuleService.gpStandardToJson(gpStd))
	gpCheck(gpBack != null, "the package parses")
	if gpBack == null:
		return
	gpEq(gpBack.gpInfo("owner"), "某业主", "owner survives")
	gpEq(gpBack.gpInfo("checked"), "李四", "reviewer survives")
	gpEq(str(gpBack.gpSheetNoRule.get("template", "")), "{project_no}-{stage}-{seq:3}",
		"the sheet-number rule survives")


func gpTestSheetNumberRuleRendersAndCollapsesEmptyParts() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpStd.gpProjectInfo["project_no"] = "PRJ"
	gpEq(gpStd.gpSheetNumberFor(1), "PRJ-001", "project number + zero-padded sequence")
	gpEq(gpStd.gpSheetNumberFor(42), "PRJ-042", "padding keeps its width")
	gpStd.gpSheetNoRule["template"] = "{project_no}-{seq}"
	gpEq(gpStd.gpSheetNumberFor(7), "PRJ-7", "bare {seq} is not padded")
	# An empty placeholder must not leave a double dash or a stray leading dash.
	# 空占位符不得留下双横线或前导横线。
	gpStd.gpSheetNoRule["template"] = "{project_no}-{stage}-{seq:2}"
	gpEq(gpStd.gpSheetNumberFor(3), "PRJ-03", "an empty stage collapses cleanly")


func gpTestTitleBlockInheritsProjectInfoWithoutOverwriting() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpStd.gpProjectInfo["company"] = "某设计院"
	gpStd.gpProjectInfo["project_name"] = "某项目"
	gpStd.gpProjectInfo["designed"] = "张三"
	gpStd.gpProjectInfo["checked"] = "李四"
	var gpSheet: GPSheet = GPSheet.gpNew("s1", "给料", 0)
	gpSheet.gpAssignNumber("PRJ-001")
	gpSheet.gpApplyProjectInfo(gpStd)
	gpEq(gpSheet.gpTitleValue("company"), "某设计院", "company inherits")
	gpEq(gpSheet.gpTitleValue("project"), "某项目", "project name inherits")
	gpEq(gpSheet.gpTitleValue("designed"), "张三", "designer inherits")
	gpEq(gpSheet.gpTitleValue("drawing_no"), "PRJ-001", "the title block shows the sheet number")
	# A per-sheet value must survive a later project-info apply.
	# 图纸上已填的值在再次应用项目信息时必须保留。
	gpSheet.gpTitleBlock["checked"] = {"caption": "", "value": {"zh": "赵六", "en": "Zhao"}}
	gpStd.gpProjectInfo["checked"] = "李四"
	gpSheet.gpApplyProjectInfo(gpStd)
	gpEq(gpSheet.gpTitleValue("checked"), "赵六", "an explicit per-sheet value is never overwritten")


func gpTestRenumberKeepsAHandEditedDrawingNumber() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpStd.gpProjectInfo["project_no"] = "PRJ"
	var gpSheet: GPSheet = GPSheet.gpNew("s1", "给料", 0)
	gpSheet.gpAssignNumber("PRJ-001")
	# The user overrides the number printed in the block.
	# 用户改掉了图签里打印的图号。
	gpSheet.gpTitleBlock["drawing_no"] = {"caption": "", "value": {"zh": "MANUAL-9", "en": "MANUAL-9"}}
	gpSheet.gpAssignNumber("PRJ-002")
	gpEq(gpSheet.gpNumber, "PRJ-002", "the sheet number itself is regenerated")
	gpEq(gpSheet.gpTitleValue("drawing_no"), "MANUAL-9",
		"but a hand-edited block value is left alone")


func gpTestSheetNumberTravelsWithTheFile() -> void:
	var gpSheet: GPSheet = GPSheet.gpNew("s1", "给料", 0)
	gpSheet.gpAssignNumber("PRJ-007")
	var gpBack: GPSheet = GPSheet.gpFromDict(gpSheet.gpToDict())
	gpEq(gpBack.gpNumber, "PRJ-007", "the drawing number is persisted")


func gpTestDialogCollectsTheProjectInfoTab() -> void:
	# Regression: the project-info tab was built but never collected, so confirming the dialog
	# silently dropped everything typed there (title block stayed empty).
	# 回归：项目信息页建好了控件却没有收集，点确定时填的内容被**静默丢弃**（图框一直是空的）。
	var gpDlg: GPProjectStandardDialog = GPProjectStandardDialog.new()
	gpDlg._gpStd = GPProjectStandard.gpDefaultStandard()
	gpDlg._gpBuild()
	(gpDlg._gpInfoEdits["owner"] as LineEdit).text = "某业主"
	(gpDlg._gpInfoEdits["project_no"] as LineEdit).text = "PRJ"
	(gpDlg._gpInfoEdits["checked"] as LineEdit).text = "李四"
	(gpDlg._gpNoTemplate as LineEdit).text = "{project_no}-{seq:2}"
	(gpDlg._gpNoStart as SpinBox).value = 0
	gpDlg._gpCollectAll()
	gpEq(gpDlg._gpStd.gpInfo("owner"), "某业主", "the owner field reaches the standard")
	gpEq(gpDlg._gpStd.gpInfo("checked"), "李四", "the reviewer field reaches the standard")
	gpEq(gpDlg._gpStd.gpSheetNumberFor(1), "PRJ-01", "the number rule reaches the standard")
	gpDlg.free()


func gpTestTitleBlockChangeIsSignalledForRepaint() -> void:
	# The frame repaints on gpSheetChanged; a silent mutation showed stale values on screen.
	# 图框靠 gpSheetChanged 重绘；静默修改会让屏幕一直显示旧值。
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpStd.gpProjectInfo["owner"] = "某业主"
	gpStd.gpProjectInfo["company"] = "某设计院"
	var gpSheet: GPSheet = GPSheet.gpNew("s1", "给料", 0)
	var gpCount: Array = [0]
	gpSheet.gpSheetChanged.connect(func() -> void: gpCount[0] += 1)
	gpSheet.gpAssignNumber("PRJ-001")
	gpSheet.gpApplyProjectInfo(gpStd)
	gpCheck(int(gpCount[0]) >= 2, "assigning a number and filling the block both notify")
	var gpBefore: int = int(gpCount[0])
	gpSheet.gpApplyProjectInfo(gpStd)
	gpEq(int(gpCount[0]), gpBefore, "a no-op apply does not spam the signal")
