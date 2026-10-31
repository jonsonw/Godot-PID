class_name GpTestTagScope
extends GPGTest
# Headless tests for project-wide tag uniqueness (ADR-36 D1/D6, step A3).
# 工程级位号唯一性（ADR-36 D1/D6，A3 步）的 headless 测试。
#
# The promises being pinned / 被钉住的承诺：
# 1. a number minted on sheet 1 is not minted again on sheet 2;
# 2. a hand-typed duplicate is refused ACROSS sheets, not just within the current one;
# 3. line numbers are scoped to their sheet, so a pipe may legitimately continue onto another
#    sheet with the same number (D1) — while two lines on the SAME sheet may not share one;
# 4. nodes and lines share ONE table: a pipe cannot take a device's tag, and vice versa;
# 5. comparison is normalised, so "P 1001", "P.1001" and "P-1001" are the same tag.
# 1. 第一页铸过的号不会在第二页再铸一次；
# 2. 手打重复号**跨图纸**被拒，而不只看当前这张；
# 3. 管线号按图纸作用域，故同一根管线可以合法地以同号延续到另一张图纸（D1）—— 但同一张图纸上
#    两根线不得同号；
# 4. 节点与管线共用**一张表**：管线拿不走设备的位号，反之亦然；
# 5. 比较是归一化的，故 "P 1001"、"P.1001"、"P-1001" 是同一个位号。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


func _gpPumpDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolLibrary.gpFindById("DPUMP001")
	if gpD != null:
		return gpD
	var gpF: GPSymbolDef = GPSymbolDef.new()
	gpF.gpId = "DPUMP001"
	gpF.gpCategory = "pump"
	gpF.gpTagPrefix = "P"
	return gpF


# A standard with the tables a line number needs (same seed as the A2 suite).
# 带齐管线号所需代号表的标准（与 A2 套件同一套种子）。
func _gpStd(gpGraphIn: GPPIDGraph) -> GPProjectStandard:
	var gpStd: GPProjectStandard = gpGraphIn.gpStandardOrCreate()
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_MATERIAL,
		[{"code": "A1A", "label": "碳钢", "aliases": []}])
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_INSULATION,
		[{"code": "P", "label": "保冷", "aliases": []}])
	return gpStd


func _gpAttrs() -> Dictionary:
	return {"dn": "DN150", "medium": "循环冷却水", "spec": "碳钢", "insulation": "保冷"}


# Two graphs that belong to the same project (the standard is shared).
# 属于同一个工程的两张图（标准共享）。
func _gpTwoSheets() -> Array[GPPIDGraph]:
	var gpA: GPPIDGraph = GPPIDGraph.new()
	var gpB: GPPIDGraph = GPPIDGraph.new()
	var gpStd: GPProjectStandard = _gpStd(gpA)
	gpB.gpAdoptStandard(gpStd)
	var gpOut: Array[GPPIDGraph] = []
	gpOut.append(gpA)
	gpOut.append(gpB)
	return gpOut


func _gpRegistry(gpGraph: GPPIDGraph, gpProject: Array[GPPIDGraph]) -> GPTagRegistry:
	var gpR: GPTagRegistry = GPTagRegistry.new()
	gpR.gpGraph = gpGraph
	gpR.gpStandard = gpGraph.gpStandard
	gpR.gpRules = gpGraph.gpTagRulesOrCreate()
	gpR.gpSetProjectGraphs(gpProject)
	return gpR


# ---------------------------------------------------------------- scope plumbing

func gpTestRegistryWithoutProjectGraphsSeesOnlyItsSheet() -> void:
	var gpA: GPPIDGraph = GPPIDGraph.new()
	var gpR: GPTagRegistry = GPTagRegistry.new()
	gpR.gpGraph = gpA
	gpEq(gpR.gpGraphs().size(), 1, "no project list = single sheet (pre-ADR-36 behaviour)")


func gpTestProjectGraphsAreDeduplicated() -> void:
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	gpSheets.append(gpSheets[0])
	var gpR: GPTagRegistry = _gpRegistry(gpSheets[0], gpSheets)
	gpEq(gpR.gpGraphs().size(), 2, "two distinct sheets, the duplicate entry is folded away")


# ---------------------------------------------------------------- minting across sheets

func gpTestMintingContinuesAcrossSheets() -> void:
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	var gpA: GPPIDGraph = gpSheets[0]
	var gpB: GPPIDGraph = gpSheets[1]
	var gpDef: GPSymbolDef = _gpPumpDef()
	var gpRegA: GPTagRegistry = _gpRegistry(gpA, gpSheets)
	var gpTagA: String = gpRegA.gpNextTag(gpDef)
	gpA.gpAddNode(gpA.gpNewNode("a1", gpDef.gpId, gpTagA))
	gpRegA.gpRegister("a1", gpTagA)
	gpEq(gpTagA, "P-1001", "sheet 1 mints P-1001")
	var gpRegB: GPTagRegistry = _gpRegistry(gpB, gpSheets)
	gpEq(gpRegB.gpNextTag(gpDef), "P-1002",
		"sheet 2 continues the project sequence instead of minting P-1001 again")


func gpTestSixPumpsAcrossTwoSheets() -> void:
	# The literal acceptance of A3: three pumps on each of two sheets must be P-1001…P-1006,
	# never P-1001 twice. Placement order alternates sheets, so the counter is exercised from
	# both sides.
	# A3 的字面验收：两张图纸各三台泵，必须是 P-1001…P-1006，绝不允许出现两个 P-1001。
	# 放置顺序在两张图纸间交替，使计数器从两侧都被验证到。
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	var gpDef: GPSymbolDef = _gpPumpDef()
	var gpMinted: Array[String] = []
	for gpI in range(6):
		var gpG: GPPIDGraph = gpSheets[gpI % 2]
		var gpReg: GPTagRegistry = _gpRegistry(gpG, gpSheets)
		var gpTag: String = gpReg.gpNextTag(gpDef)
		var gpId: String = "n" + str(gpI)
		gpG.gpAddNode(gpG.gpNewNode(gpId, gpDef.gpId, gpTag))
		gpReg.gpRegister(gpId, gpTag)
		gpMinted.append(gpTag)
	var gpWant: Array[String] = ["P-1001", "P-1002", "P-1003", "P-1004", "P-1005", "P-1006"]
	gpEq(gpMinted, gpWant, "six pumps over two sheets use six distinct numbers")


func gpTestEquipmentMintSkipsAnEdgeTagOnAnotherSheet() -> void:
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	var gpA: GPPIDGraph = gpSheets[0]
	var gpB: GPPIDGraph = gpSheets[1]
	# A pipe on sheet 1 already owns the text "P-1001" (a user may type anything).
	# 第一页的一根管线已经占用了 "P-1001" 这个文本（用户可能手打任何东西）。
	var gpEdge: GPPIDEdge = gpA.gpNewEdgeEx("e1", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "P-1001")
	gpA.gpAddEdge(gpEdge)
	var gpRegB: GPTagRegistry = _gpRegistry(gpB, gpSheets)
	gpEq(gpRegB.gpNextTag(_gpPumpDef()), "P-1002",
		"one table: an equipment number steps around a LINE tag on another sheet too")


# ---------------------------------------------------------------- manual edits

func gpTestHandTypedDuplicateIsRefusedAcrossSheets() -> void:
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	var gpA: GPPIDGraph = gpSheets[0]
	var gpB: GPPIDGraph = gpSheets[1]
	var gpDef: GPSymbolDef = _gpPumpDef()
	gpA.gpAddNode(gpA.gpNewNode("a1", gpDef.gpId, "P-1001"))
	var gpNodeB: GPPIDNode = gpB.gpNewNode("b1", gpDef.gpId, "P-2002")
	gpB.gpAddNode(gpNodeB)
	var gpRegB: GPTagRegistry = _gpRegistry(gpB, gpSheets)
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpB, GPIdGen.new(), gpRegB)
	gpCheck(not gpSvc.gpSetTag("b1", "P-1001"),
		"renaming sheet 2's pump onto sheet 1's number is refused")
	gpEq(gpSvc.gpLastRefusal, "tag.err_duplicate", "and the refusal is explained")
	gpEq(gpNodeB.gpTag, "P-2002", "the node keeps its old tag")
	gpCheck(gpSvc.gpSetTag("b1", "P-2003"), "a free number is still accepted")


func gpTestNormalisedComparisonAcrossSheets() -> void:
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	gpSheets[0].gpAddNode(gpSheets[0].gpNewNode("a1", "DPUMP001", "P 1001"))
	var gpRegB: GPTagRegistry = _gpRegistry(gpSheets[1], gpSheets)
	gpCheck(gpRegB.gpIsTaken("P-1001"),
		"the same tag typed with a dash instead of a space is still taken")
	gpCheck(gpRegB.gpIsTaken("p.1001"), "case and punctuation are folded away as well")


# ---------------------------------------------------------------- line scope (D1)

func gpTestLineNumberIsScopedToItsSheet() -> void:
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	var gpA: GPPIDGraph = gpSheets[0]
	var gpB: GPPIDGraph = gpSheets[1]
	var gpLine: String = "150-CWR-0001-A1A-P"
	gpA.gpAddEdge(gpA.gpNewEdgeEx("e1", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", gpLine))
	var gpRegB: GPTagRegistry = _gpRegistry(gpB, gpSheets)
	gpCheck(not gpRegB.gpIsTakenForClass(GPProjectStandard.GP_CLASS_LINE, gpLine),
		"the same line number on another sheet is the continuation case, not a duplicate (D1)")
	gpCheck(gpRegB.gpIsTakenForClass(GPProjectStandard.GP_CLASS_EQUIPMENT, gpLine),
		"but an EQUIPMENT number is unique project-wide, so that text is taken (D1)")


func gpTestTwoLinesOnTheSameSheetMayNotShareANumber() -> void:
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	var gpB: GPPIDGraph = gpSheets[1]
	var gpLine: String = "150-CWR-0001-A1A-P"
	gpB.gpAddEdge(gpB.gpNewEdgeEx("e1", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", gpLine))
	var gpRegB: GPTagRegistry = _gpRegistry(gpB, gpSheets)
	gpCheck(gpRegB.gpIsTakenForClass(GPProjectStandard.GP_CLASS_LINE, gpLine, "e9"),
		"two lines on the SAME sheet may not share a number")
	gpCheck(not gpRegB.gpIsTakenForClass(GPProjectStandard.GP_CLASS_LINE, gpLine, "e1"),
		"editing a line keeps its own number free for itself")


func gpTestLineMintingUsesTheSegmentedRule() -> void:
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	var gpB: GPPIDGraph = gpSheets[1]
	var gpReg: GPTagRegistry = _gpRegistry(gpB, gpSheets)
	gpEq(gpReg.gpNextTagForClass(GPProjectStandard.GP_CLASS_LINE, null, _gpAttrs()),
		"150-CWR-0001-A1A-P", "the line class mints the five-field designation")
	gpEq(gpReg.gpNextTagForClass(GPProjectStandard.GP_CLASS_LINE, null, _gpAttrs()),
		"150-CWR-0002-A1A-P", "and the shared mark advances")


func gpTestLineMintingSkipsANumberUsedOnTheSameSheet() -> void:
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	var gpB: GPPIDGraph = gpSheets[1]
	# The counter still points at 0001, but 0001 is already painted on this sheet.
	# 计数器仍指向 0001，但本张图纸上已经画着 0001。
	gpB.gpAddEdge(gpB.gpNewEdgeEx("e1", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "150-CWR-0001-A1A-P"))
	var gpReg: GPTagRegistry = _gpRegistry(gpB, gpSheets)
	gpEq(gpReg.gpNextTagForClass(GPProjectStandard.GP_CLASS_LINE, null, _gpAttrs()),
		"150-CWR-0002-A1A-P", "the mint skips the number already used on this sheet")


# ---------------------------------------------------------------- one table, both kinds

func gpTestLineAllocatorSeesNodeTags() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "PL-1001"))
	gpEq(GPTagGen.gpNextTag(gpG), "PL-1002",
		"a pipe cannot take a device tag (the two namespaces used to be blind to each other)")


func gpTestNodeRegistrySeesLineTags() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddEdge(gpG.gpNewEdgeEx("e1", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "PL-2000"))
	var gpR: GPTagRegistry = GPTagRegistry.new()
	gpR.gpGraph = gpG
	gpR.gpRebuild()
	gpCheck(gpR.gpIsTaken("PL-2000"), "the node side sees a line's tag in the same table")


# ---------------------------------------------------------------- rebuild

func gpTestRebuildDetectsDuplicatesAcrossSheets() -> void:
	var gpSheets: Array[GPPIDGraph] = _gpTwoSheets()
	gpSheets[0].gpAddNode(gpSheets[0].gpNewNode("a1", "DPUMP001", "P-1001"))
	gpSheets[1].gpAddNode(gpSheets[1].gpNewNode("b1", "DPUMP001", "P-1001"))
	var gpR: GPTagRegistry = _gpRegistry(gpSheets[0], gpSheets)
	gpEq(gpR.gpConflicts().size(), 1, "a cross-sheet duplicate is recorded by the rebuild")
	gpEq(gpR.gpCountTagged(), 1, "the first owner keeps the tag, the second is a conflict")
