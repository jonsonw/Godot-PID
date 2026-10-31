class_name GpTestTagAudit
extends GPGTest
# Headless tests for the project-wide tag audit, the export gate and the import-side matching
# (ADR-36 C).
# 工程级位号审计、导出闸门与导入侧匹配（ADR-36 C）的 headless 测试。
#
# The promises being pinned / 被钉住的承诺：
# 1. a duplicate across sheets is an ERROR (the defect that started this work);
# 2. a tag that does not fit its rule is an ERROR, and a line number that no longer matches its
#    attributes is a WARNING (a drawing defect, not a data loss);
# 3. one line number on several sheets is INFO — the legitimate continuation (D1);
# 4. a duplicate BLOCKS the Excel export instead of shipping an ambiguous list;
# 5. import matches tags NORMALISED ("P 1001" == "P-1001"), finds UTILITY lines, and writes a
#    multi-sheet line row into every listed sheet;
# 6. an imported duplicate continues the sequence instead of becoming "P-1001-dup".
# 1. 跨页重复是 error（就是引发这轮工作的缺陷）；
# 2. 不符合规则的位号是 error；与属性脱节的线号是 warning（图面缺陷，不是数据丢失）；
# 3. 一个线号出现在多张图纸是 info —— 合法的延续（D1）；
# 4. 重复**阻断** Excel 导出，而不是发出一份分不清的清单；
# 5. 导入按**归一化**匹配（"P 1001" == "P-1001"）、找得到 UTILITY 线、跨页管线行写回每一张列出的图纸；
# 6. 导入遇到重号时**顺延序号**，而不是变成 "P-1001-dup"。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_EXPORT_DIR: String = "user://gp_test_export_gate"


func _gpPumpDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolLibrary.gpFindById("DPUMP001")
	if gpD != null:
		return gpD
	var gpF: GPSymbolDef = GPSymbolDef.new()
	gpF.gpId = "DPUMP001"
	gpF.gpCategory = "pump"
	gpF.gpTagPrefix = "P"
	return gpF


func _gpStdOf(gpSheet: GPSheet) -> GPProjectStandard:
	var gpStd: GPProjectStandard = gpSheet.gpGraph.gpStandardOrCreate()
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_MATERIAL,
		[{"code": "A1A", "label": "碳钢", "aliases": []}])
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_INSULATION,
		[{"code": "P", "label": "保冷", "aliases": []}])
	return gpStd


func _gpLineAttrs() -> Dictionary:
	return {"dn": "DN150", "medium": "循环冷却水", "spec": "碳钢", "insulation": "保冷"}


# One sheet that adopts the project standard of `gpStdFrom` (or creates its own).
# 一张图纸，采纳 `gpStdFrom` 的项目标准（或自建）。
func _gpSheet(gpName: String, gpIdx: int, gpStdFrom: GPProjectStandard = null) -> GPSheet:
	var gpSheet: GPSheet = GPSheet.gpNew("sheet-" + str(gpIdx + 1), gpName, gpIdx)
	if gpStdFrom != null:
		gpSheet.gpGraph.gpAdoptStandard(gpStdFrom)
	return gpSheet


# Render the factory line tag for the given attributes at sequence 1.
# 用给定属性渲染出厂线规则的第 1 号。
func _gpLineTag(gpStd: GPProjectStandard, gpAttrs: Dictionary) -> String:
	var gpRule: GPTagRule = gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpRuleFor(null)
	return gpRule.gpRender({"seq": 1, "attrs": gpAttrs}, gpStd)


# ---------------------------------------------------------------- audit

func gpTestCrossSheetDuplicateIsAnError() -> void:
	var gpA: GPSheet = _gpSheet("给料", 0)
	var gpStd: GPProjectStandard = _gpStdOf(gpA)
	var gpB: GPSheet = _gpSheet("磨矿", 1, gpStd)
	gpA.gpGraph.gpAddNode(gpA.gpGraph.gpNewNode("a1", "DPUMP001", "P-1001"))
	gpB.gpGraph.gpAddNode(gpB.gpGraph.gpNewNode("b1", "DPUMP001", "P-1001"))
	var gpFindings: Array[GPFinding] = GPTagAudit.gpRun([gpA, gpB], [_gpPumpDef()], gpStd)
	gpCheck(GPTagAudit.gpHasBlocking(gpFindings), "a cross-sheet duplicate blocks")
	gpEq(str(gpFindings[0].gpMessageKey), "drc.tag_duplicate", "and says it is a duplicate")
	gpEq(GPTagAudit.gpBlockingSummary(gpFindings), "P-1001", "the summary names the tag")


func gpTestTagViolatingItsRuleIsAnError() -> void:
	var gpA: GPSheet = _gpSheet("首页", 0)
	var gpStd: GPProjectStandard = _gpStdOf(gpA)
	gpA.gpGraph.gpAddNode(gpA.gpGraph.gpNewNode("a1", "DPUMP001", "P-abc"))
	var gpFindings: Array[GPFinding] = GPTagAudit.gpRun([gpA], [_gpPumpDef()], gpStd)
	gpCheck(GPTagAudit.gpHasBlocking(gpFindings), "a non-compliant tag is an error")
	gpEq(str(gpFindings[0].gpMessageKey), "drc.tag_invalid", "reported as a rule violation")


func gpTestLineTagViolatingItsRuleIsAnError() -> void:
	var gpA: GPSheet = _gpSheet("首页", 0)
	var gpStd: GPProjectStandard = _gpStdOf(gpA)
	var gpEdge: GPPIDEdge = gpA.gpGraph.gpNewEdgeEx("e1", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "随便打的号")
	gpA.gpGraph.gpAddEdge(gpEdge)
	var gpFindings: Array[GPFinding] = GPTagAudit.gpRun([gpA], [_gpPumpDef()], gpStd)
	gpCheck(GPTagAudit.gpHasBlocking(gpFindings), "a hand-typed line number is audited")
	gpEq(str(gpFindings[0].gpMessageKey), "drc.line_tag_invalid", "as a line-rule violation")


func gpTestStaleLineNumberIsAWarning() -> void:
	var gpA: GPSheet = _gpSheet("首页", 0)
	var gpStd: GPProjectStandard = _gpStdOf(gpA)
	var gpTag: String = _gpLineTag(gpStd, _gpLineAttrs())
	var gpEdge: GPPIDEdge = gpA.gpGraph.gpNewEdgeEx("e1", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", gpTag)
	# The size changed after the number was minted — nobody supports the number any more.
	# 号铸完之后管径改了 —— 已经没有任何一段支持这个号。
	gpEdge.gpAttrs = {"dn": "DN80", "medium": "循环冷却水", "spec": "碳钢", "insulation": "保冷"}
	gpA.gpGraph.gpAddEdge(gpEdge)
	var gpFindings: Array[GPFinding] = GPTagAudit.gpRun([gpA], [_gpPumpDef()], gpStd)
	var gpStale: bool = false
	for gpF in gpFindings:
		if gpF.gpMessageKey == "drc.line_tag_stale":
			gpStale = true
			gpEq(gpF.gpSeverity, GPFinding.GP_WARNING, "stale is a warning, not an error")
	gpCheck(gpStale, "the stale number is reported")
	gpCheck(not GPTagAudit.gpHasBlocking(gpFindings), "a stale number does not block the export")


func gpTestSharedLineAcrossSheetsIsInfo() -> void:
	var gpA: GPSheet = _gpSheet("给料", 0)
	var gpStd: GPProjectStandard = _gpStdOf(gpA)
	var gpB: GPSheet = _gpSheet("磨矿", 1, gpStd)
	var gpTag: String = _gpLineTag(gpStd, _gpLineAttrs())
	for gpPair in [[gpA, "e1"], [gpB, "e1"]]:
		var gpSheet: GPSheet = gpPair[0]
		var gpEdge: GPPIDEdge = gpSheet.gpGraph.gpNewEdgeEx(str(gpPair[1]),
			{"node_id": "", "port_id": ""}, {"node_id": "", "port_id": ""},
			GPPIDEdge.GP_PROCESS, "", gpTag)
		gpEdge.gpAttrs = _gpLineAttrs().duplicate()
		gpSheet.gpGraph.gpAddEdge(gpEdge)
	var gpFindings: Array[GPFinding] = GPTagAudit.gpRun([gpA, gpB], [_gpPumpDef()], gpStd)
	var gpShared: bool = false
	for gpF in gpFindings:
		if gpF.gpMessageKey == "drc.line_shared_across_sheets":
			gpShared = true
			gpEq(gpF.gpSeverity, GPFinding.GP_INFO, "continuation is info (D1)")
	gpCheck(gpShared, "the same line number on two sheets is reported as a continuation")
	gpCheck(not GPTagAudit.gpHasBlocking(gpFindings), "and does not block")


func gpTestUnmappedSymbolIsInfo() -> void:
	var gpA: GPSheet = _gpSheet("首页", 0)
	var gpStd: GPProjectStandard = _gpStdOf(gpA)
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "DGENERAL500"
	gpDef.gpCategory = "general"
	gpA.gpGraph.gpAddNode(gpA.gpGraph.gpNewNode("a1", "DGENERAL500", "G-1001"))
	var gpFindings: Array[GPFinding] = GPTagAudit.gpRun([gpA], [gpDef], gpStd)
	gpEq(gpFindings.size(), 1, "only the unmapped-class info fires")
	gpEq(str(gpFindings[0].gpMessageKey), "drc.tag_class_unmapped", "and it is the mapping gap")
	gpEq(gpFindings[0].gpSeverity, GPFinding.GP_INFO, "mapping is an info, not a defect")


func gpTestCleanProjectHasNoFindings() -> void:
	var gpA: GPSheet = _gpSheet("首页", 0)
	var gpStd: GPProjectStandard = _gpStdOf(gpA)
	gpA.gpGraph.gpAddNode(gpA.gpGraph.gpNewNode("a1", "DPUMP001", "P-1001"))
	var gpEdge: GPPIDEdge = gpA.gpGraph.gpNewEdgeEx("e1", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "",
		_gpLineTag(gpStd, _gpLineAttrs()))
	gpEdge.gpAttrs = _gpLineAttrs().duplicate()
	gpA.gpGraph.gpAddEdge(gpEdge)
	var gpFindings: Array[GPFinding] = GPTagAudit.gpRun([gpA], [_gpPumpDef()], gpStd)
	gpEq(gpFindings.size(), 0, "a compliant project produces no tag findings")


# ---------------------------------------------------------------- export gate

func gpTestExportIsBlockedByDuplicateTags() -> void:
	var gpA: GPSheet = _gpSheet("给料", 0)
	var gpStd: GPProjectStandard = _gpStdOf(gpA)
	var gpB: GPSheet = _gpSheet("磨矿", 1, gpStd)
	gpA.gpGraph.gpAddNode(gpA.gpGraph.gpNewNode("a1", "DPUMP001", "P-1001"))
	gpB.gpGraph.gpAddNode(gpB.gpGraph.gpNewNode("b1", "DPUMP001", "P-1001"))
	var gpSheets: Array = [gpA, gpB]
	var gpRes: GPIOResult = GPXlsxExport.gpExportLists(gpSheets, [_gpPumpDef()], {
		"output_dir": GP_EXPORT_DIR, "locale": "zh"})
	gpCheck(not gpRes.gpIsOk(), "the export is refused")
	gpEq(gpRes.gpMessageKey, "xlsx.blocked_tag_duplicate", "with the duplicate-tag reason")
	gpCheck(gpRes.gpDetail.find("P-1001") >= 0, "and names the offending tag")


# ---------------------------------------------------------------- import matching

func gpTestImportMatchesNormalisedTags() -> void:
	var gpA: GPSheet = _gpSheet("首页", 0)
	gpA.gpGraph.gpAddNode(gpA.gpGraph.gpNewNode("a1", "DPUMP001", "P-1001"))
	var gpTargets: Array[Dictionary] = GPXlsxImport.gpMatchTargets([gpA],
		GPDeliverableFields.GP_LIST_EQUIPMENT, "P 1001", [])
	gpEq(gpTargets.size(), 1, "a differently spelled but identical tag still matches")
	gpEq(str(gpTargets[0].get("id", "")), "a1", "and the match is the right node")


func gpTestImportMatchesUtilityLines() -> void:
	var gpA: GPSheet = _gpSheet("首页", 0)
	var gpEdge: GPPIDEdge = gpA.gpGraph.gpNewEdgeEx("e1", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_UTILITY, "", "PL-2001")
	gpA.gpGraph.gpAddEdge(gpEdge)
	var gpTargets: Array[Dictionary] = GPXlsxImport.gpMatchTargets([gpA],
		GPDeliverableFields.GP_LIST_LINE, "PL 2001", [])
	gpEq(gpTargets.size(), 1, "a UTILITY line is found (it used to be filtered out of the import)")
	gpEq(str(gpTargets[0].get("id", "")), "e1", "and it is the right edge")


func gpTestImportWritesAMultiSheetLineRowToEverySheet() -> void:
	var gpA: GPSheet = _gpSheet("给料", 0)
	var gpB: GPSheet = _gpSheet("磨矿", 1)
	for gpPair in [[gpA, "e1"], [gpB, "e2"]]:
		var gpSheet: GPSheet = gpPair[0]
		gpSheet.gpGraph.gpAddEdge(gpSheet.gpGraph.gpNewEdgeEx(str(gpPair[1]),
			{"node_id": "", "port_id": ""}, {"node_id": "", "port_id": ""},
			GPPIDEdge.GP_PROCESS, "", "150-CWR-0001-A1A-P"))
	var gpTargets: Array[Dictionary] = GPXlsxImport.gpMatchTargets([gpA, gpB],
		GPDeliverableFields.GP_LIST_LINE, "150-CWR-0001-A1A-P", [])
	gpEq(gpTargets.size(), 2, "a merged line row targets BOTH sheets")


# ---------------------------------------------------------------- import merge numbering

func gpTestImportedDuplicateContinuesTheSequence() -> void:
	var gpUsed: Dictionary = {"P-1001": true, "P-1002": true, "P-1003": true}
	gpEq(GPProjectImport.gpNextFreeTagLike("P-1001", gpUsed), "P-1004",
		"the imported device takes the next free number")
	gpEq(GPProjectImport.gpNextFreeTagLike("P-0007", {"P-0007": true}), "P-0008",
		"zero padding is preserved")
	gpEq(GPProjectImport.gpNextFreeTagLike("PL-1", {"PL-1": true}), "PL-2",
		"single-digit tails work too")
