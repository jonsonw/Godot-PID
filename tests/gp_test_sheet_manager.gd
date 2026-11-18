extends "res://tests/gp_test.gd"
# Headless tests for the sheet manager's pure core (W13 T5): category-code parsing from
# symbol ids, major-equipment classification (incl. mounted-attachment exclusion), the sheet
# scan shape, and the panel's row model.
# 图纸管理**纯核**的 headless 测试（W13 T5）：从图元 id 解析类别码、主要设备分类（含挂载
# 附件排除）、图纸扫描输出形态，以及面板的行模型。
# WHY / 为何要这些测试：
# The preview and any future equipment-table export share ONE classification; a silent
# mis-parse (say, "DGENERAL008" counted as equipment) would put a manhole on the equipment
# list. Everything here is pure, so the gate pins it exactly.
# 预览与将来的设备表导出共用**同一套**分类；一次静默误解析（比如把 "DGENERAL008" 算成
# 设备）就会让人孔出现在设备清单上。这里全是纯函数，门禁可以逐一钉死。

# Helper: a sheet with a fresh graph and one node. / 辅助：一张带新图与单节点的图纸。
func _gpNodeSheet(gpId: String, gpName: String) -> GPSheet:
	var gpSheet: GPSheet = GPSheet.gpNew(gpId, gpName, 0)
	gpSheet.gpGraph = GPPIDGraph.new()
	return gpSheet


# Helper: create AND add a top-level node (gpNewNode is a pure factory, it does not join
# the graph — gpAddNode is the mutation).
# 辅助：创建**并**加入顶层节点（gpNewNode 是纯工厂、不入图 —— 入图是 gpAddNode 的职责）。
func _gpNode(gpSheet: GPSheet, gpUid: String, gpSymbolId: String, gpTag: String) -> GPPIDNode:
	var gpN: GPPIDNode = gpSheet.gpGraph.gpNewNode(gpUid, gpSymbolId, gpTag, Vector2(100, 100))
	gpSheet.gpGraph.gpAddNode(gpN)
	return gpN


# ==================== gpCategoryCode / 类别码解析 ====================

# The code lives between the source letter and the digits; sources L/C/D share it.
# 类别码位于来源码与数字之间；L/C/D 三来源共用。
func gpTestCategoryCodeParsing() -> void:
	gpEq(GPEquipmentScan.gpCategoryCode("DPUMP001"), "PUMP", "DEXPI pump id -> PUMP")
	gpEq(GPEquipmentScan.gpCategoryCode("CPUMP003"), "PUMP", "custom pump id -> PUMP")
	gpEq(GPEquipmentScan.gpCategoryCode("LHEAT002"), "HEAT", "library exchanger id -> HEAT")
	gpEq(GPEquipmentScan.gpCategoryCode("DTANK001"), "TANK", "DEXPI tank id -> TANK")
	gpEq(GPEquipmentScan.gpCategoryCode("dpump001"), "PUMP",
		"lower case must classify too (hand-edited archives)")
	gpEq(GPEquipmentScan.gpCategoryCode("DVALVE002"), "VALVE",
		"a non-major code must still parse (it is just not equipment)")
	gpEq(GPEquipmentScan.gpCategoryCode(""), "", "an empty id must yield an empty code")
	gpEq(GPEquipmentScan.gpCategoryCode("D123"), "", "digits right after the source -> empty")
	gpEq(GPEquipmentScan.gpCategoryCode("X"), "", "a bare source letter -> empty")


# ==================== classification / 分类 ====================

# Only the five decided families are equipment. / 只有拍板的五个族算主要设备。
func gpTestEquipmentCodes() -> void:
	for gpCode: String in ["PUMP", "COLUMN", "HEAT", "VESSEL", "TANK"]:
		gpCheck(GPEquipmentScan.gpIsEquipmentCode(gpCode), gpCode + " must be equipment")
	for gpCode: String in ["VALVE", "GENERAL", "INSTRUMENT", ""]:
		gpCheck(GPEquipmentScan.gpIsEquipmentCode(gpCode) == false,
			gpCode + " must NOT be major equipment")


# ==================== gpScanSheet / 单张扫描 ====================

# Null-safe empty output. / null 安全的空输出。
func gpTestScanNullSheet() -> void:
	gpEq(GPEquipmentScan.gpScanSheet(null).get("ok", true), false,
		"a null sheet must scan to ok=false")


# Equipment collection, attachment exclusion, counts, categories — all in one fixture.
# 设备收集、附件排除、计数、类别 —— 一个夹具全钉。
func gpTestScanSheetShape() -> void:
	var gpSheet: GPSheet = _gpNodeSheet("s1", "A")
	gpSheet.gpNumber = "01"
	# Pump = major. / 泵 = 主要设备。
	_gpNode(gpSheet, "n1", "DPUMP001", "P-101")
	# Valve = other. / 阀 = 其他。
	_gpNode(gpSheet, "n2", "DVALVE002", "V-1")
	# Tank = major. / 储罐 = 主要设备。
	_gpNode(gpSheet, "n3", "DTANK001", "TK-01")
	# Manhole MOUNTED on the tank: attachment, never major even though the role would be
	# equipment in DEXPI terms.
	# 挂在储罐上的人孔：附件 —— 即使在 DEXPI 语义里算 equipment 也绝不进主要设备清单。
	var gpMh: GPPIDNode = gpSheet.gpGraph.gpNewNode("n4", "DGENERAL007", "", Vector2(200, 80))
	gpMh.gpParentUid = "n3"
	gpSheet.gpGraph.gpAddNode(gpMh)
	# One edge (same factory+add split). / 一条边（同样先工厂后入图）。
	gpSheet.gpGraph.gpAddEdge(gpSheet.gpGraph.gpNewEdge("e1", "n1", "n2"))
	var gpScan: Dictionary = GPEquipmentScan.gpScanSheet(gpSheet)
	gpCheck(bool(gpScan.get("ok", false)), "a real sheet must scan ok")
	gpEq(str(gpScan.get("sheet_id", "")), "s1", "the scan must carry the sheet id")
	gpEq(str(gpScan.get("sheet_name", "")), "A", "the scan must carry the sheet name")
	gpEq(str(gpScan.get("sheet_number", "")), "01", "the scan must carry the sheet number")
	gpEq(int(gpScan.get("node_count", 0)), 4, "node count must count every node")
	gpEq(int(gpScan.get("edge_count", 0)), 1, "edge count must count edges")
	gpEq(int(gpScan.get("other_count", 0)), 1, "exactly the valve must be 'other'")
	var gpEquip: Array = gpScan.get("equipment", []) as Array
	gpEq(gpEquip.size(), 2, "pump + tank only: the manhole must be excluded")
	if gpEquip.size() == 2:
		gpEq(str((gpEquip[0] as Dictionary).get("uid", "")), "n1",
			"equipment must preserve graph order (n1 first)")
		gpEq(str((gpEquip[0] as Dictionary).get("code", "")), "PUMP", "n1 code")
		gpEq(str((gpEquip[0] as Dictionary).get("tag", "")), "P-101", "n1 tag")
		gpEq(str((gpEquip[0] as Dictionary).get("label_key", "")), "eq.cat.PUMP", "n1 label key")
		gpEq(str((gpEquip[1] as Dictionary).get("code", "")), "TANK", "n3 code")
	var gpCats: Dictionary = gpScan.get("categories", {}) as Dictionary
	gpEq(int(gpCats.get("PUMP", 0)), 1, "PUMP must count 1")
	gpEq(int(gpCats.get("TANK", 0)), 1, "TANK must count 1")
	gpCheck(not gpCats.has("VALVE"), "non-major codes must not appear in categories")


# An empty graph scans fine with zero counts. / 空图扫描正常、计数为零。
func gpTestScanEmptyGraph() -> void:
	var gpSheet: GPSheet = _gpNodeSheet("s1", "A")
	var gpScan: Dictionary = GPEquipmentScan.gpScanSheet(gpSheet)
	gpCheck(bool(gpScan.get("ok", false)), "an empty-graph sheet must scan ok")
	gpEq(int(gpScan.get("node_count", 1)), 0, "node count must be 0")
	gpEq((gpScan.get("equipment", []) as Array).size(), 0, "equipment must be empty")


# ==================== gpScanSheets / 多张扫描 ====================

# Order follows the input; null sheets are skipped. / 顺序跟随输入；null 图纸被跳过。
func gpTestScanSheetsList() -> void:
	var gpS1: GPSheet = _gpNodeSheet("s1", "A")
	_gpNode(gpS1, "n1", "DPUMP001", "P-101")
	var gpS2: GPSheet = _gpNodeSheet("s2", "B")
	var gpOut: Array[Dictionary] = GPEquipmentScan.gpScanSheets([gpS1, null, gpS2])
	gpEq(gpOut.size(), 2, "null sheets must be skipped")
	gpEq(str(gpOut[0].get("sheet_id", "")), "s1", "output must keep input order")
	gpEq(str(gpOut[1].get("sheet_id", "")), "s2", "output must keep input order (2)")
	gpEq((gpOut[0].get("equipment", []) as Array).size(), 1, "s1 carries its pump")
	gpEq((gpOut[1].get("equipment", []) as Array).size(), 0, "s2 carries nothing")


# ==================== panel row model / 面板行模型 ====================

# One row per real sheet, text = name (+ number), uid = id; nulls skipped.
# 每张真实图纸一行，text = 名称（+编号），uid = id；null 被跳过。
func gpTestPanelRows() -> void:
	var gpS1: GPSheet = GPSheet.gpNew("s1", "萃取区", 0)
	gpS1.gpNumber = "03"
	var gpS2: GPSheet = GPSheet.gpNew("s2", "磨矿", 0)
	var gpRows: Array[Dictionary] = GPSheetManagerPanel.gpBuildRows([gpS1, null, gpS2])
	gpEq(gpRows.size(), 2, "null sheets must not become rows")
	gpEq(str(gpRows[0].get("uid", "")), "s1", "row uid must carry the sheet id")
	gpEq(str(gpRows[0].get("text", "")), "萃取区  ·  03",
		"the row text must be name + number")
	gpEq(str(gpRows[1].get("text", "")), "磨矿",
		"without a number the text must be the bare name")


# ==================== thumbnail entity projection / 缩略图实体投影 ====================

# User feedback 2026-11-11: the preview showed "just two dots" for a two-equipment sheet. The
# fix routes the thumbnail through GPPrintModel.gpProject (the SAME entity model as the DXF/PDF
# exporters). This pin freezes that decision: a sheet with real default defs MUST project
# EQUIPMENT-layer glyph entities — an abstract dot would carry no layer at all.
# 用户反馈 2026-11-11：两台设备的图纸预览只显示"两个点"。修复让缩略图经 GPPrintModel.gpProject
#（与 DXF/PDF 导出器**同一份**实体模型）。本钉冻结该决策：带真实默认 defs 的图纸**必须**
# 投影出 EQUIPMENT 层的字形实体 —— 抽象圆点不带任何图层。
func gpTestThumbnailEntityProjection() -> void:
	var gpSheet: GPSheet = _gpNodeSheet("s1", "A")
	_gpNode(gpSheet, "n1", "DPUMP001", "P-101")
	_gpNode(gpSheet, "n3", "DTANK001", "TK-01")
	var gpDefs: Array[GPSymbolDef] = GPSymbolLibrary.gpDefaultDefs()
	gpCheck(gpDefs.size() > 0, "the default library must be non-empty for the projection")
	var gpEntities: Array[Dictionary] = GPPrintModel.gpProject(gpSheet, gpDefs, Callable())
	gpCheck(gpEntities.size() > 0, "a sheet with defs must project entities")
	var gpEquipCount: int = 0
	for gpE in gpEntities:
		if str((gpE as Dictionary).get("layer", "")) == GPPrintModel.GP_LAYER_EQUIPMENT:
			gpEquipCount += 1
	gpCheck(gpEquipCount > 0,
		"the thumbnail must yield REAL glyph entities on the EQUIPMENT layer (no dots)")
	# Missing defs degrade honestly: nothing per symbol, no crash. / defs 缺失诚实降级：
	# 逐符号不产出、不崩溃。
	var gpBare: Array[Dictionary] = GPPrintModel.gpProject(gpSheet, [], Callable())
	for gpE in gpBare:
		gpCheck(str((gpE as Dictionary).get("layer", "")) != GPPrintModel.GP_LAYER_EQUIPMENT,
			"without defs no EQUIPMENT entity may appear (the print contract)")


# ==================== creation-time numbering / 创建时发号 ====================

# User feedback 2026-11-11: fresh sheets had NO number anywhere (tab caption, manager list,
# preview header) until 编号设置 was re-applied — gpRenumberSheets only ran from that dialog.
# The mint-at-creation authority is GPSheetNumbering: std template when a standard lives,
# bare zero-padded sequence otherwise. Hand-edit survival stays with gpAssignNumber (ADR-38).
# 用户反馈 2026-11-11：新图纸在重套「编号设置」之前处处无号 —— gpRenumberSheets 只在那个
# 对话框里触发。创建时发号的唯一权威是 GPSheetNumbering：有标准走模板、否则裸三位序号。
# 手改存活的语义仍归 gpAssignNumber（ADR-38）。
func gpTestSheetNumbering() -> void:
	gpEq(GPSheetNumbering.gpNumberFor(1, null), "001", "no standard -> bare zero-padded sequence")
	gpEq(GPSheetNumbering.gpNumberFor(12, null), "012", "padding keeps its width")
	gpEq(GPSheetNumbering.gpNumberFor(0, null), "001", "the sequence clamps to 1-based")
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	gpStd.gpProjectInfo["project_no"] = "PRJ"
	gpStd.gpSheetNoRule["template"] = "{project_no}-{seq:3}"
	gpEq(GPSheetNumbering.gpNumberFor(4, gpStd), "PRJ-004",
		"with a standard the template wins (the fresh sheet matches the renumber)")


# ==================== project-wide identity / 全工程身份 ====================

# 2026-11-18 duplicate-number fix. Deleting the FIRST sheet used to reset the tab counter, so
# the next "+" re-minted the survivor's id, name AND number ("002 图纸 2" twice). All three
# identities must instead be derived from the whole project (open + hidden).
# 2026-11-18 重号修复：删掉第一张会重置标签计数器，下一次「+」会重铸幸存图纸的 id、名称与
# 编号（两个「002 图纸 2」）。三种身份都必须从全工程（打开+隐藏）推导。
func gpTestCreationNeverReusesSurvivorIdentity() -> void:
	var gpSurvivor: GPSheet = GPSheet.gpNew("sheet-2", "图纸 2", 0)
	gpSurvivor.gpAssignNumber("002")
	var gpSheets: Array = [gpSurvivor]
	var gpUsed: Dictionary = GPSheetNumbering.gpUsedNumbers(gpSheets)
	gpCheck(gpUsed.has("002"), "the survivor's number is reserved")
	gpEq(GPSheetNumbering.gpNextNumber(gpUsed, null), "003",
		"a new sheet continues past the highest in-use number; it never re-mints 002")
	gpEq(GPSheetIdentity.gpNextNameIndex(gpSheets), 3,
		"the display name continues from the survivor, not from the open-tab count")
	var gpNewId: String = GPSheetIdentity.gpNewId(gpSheets, 1000)
	gpCheck(gpNewId != gpSurvivor.gpId and gpNewId.begins_with("sheet-s"),
		"a new id is opaque and cannot be the survivor's id")
	var gpSecondId: String = GPSheetIdentity.gpNewId(
		[gpSurvivor, GPSheet.gpNew(gpNewId, "图纸 3", 1)], 1001)
	gpCheck(gpSecondId != gpNewId and gpSecondId != gpSurvivor.gpId,
		"two new sheets can never share an id")
	gpEq(GPSheetNumbering.gpSequenceOf("PRJ-002"), 2, "the trailing sequence is parsed")
	gpEq(GPSheetNumbering.gpSequenceOf("REV-A"), 0, "a non-numeric number advances nothing")


# A hidden sheet still belongs to the project: its number is reserved during a renumber, so an
# open sheet cannot be re-numbered onto it. Hidden sheets keep their own number verbatim.
# 隐藏图纸仍属本工程：重编时其号占槽位，打开图纸不得重编到该号上；隐藏图纸自身号码不变。
func gpTestRenumberReservesHiddenNumbers() -> void:
	var gpA: GPSheet = GPSheet.gpNew("a", "图纸 1", 0)
	gpA.gpAssignNumber("001")
	var gpB: GPSheet = GPSheet.gpNew("b", "图纸 2", 1)
	gpB.gpAssignNumber("002")
	var gpHidden: GPSheet = GPSheet.gpNew("h", "图纸 3", 2)
	gpHidden.gpAssignNumber("002")
	var gpPlan: Dictionary = GPSheetNumbering.gpPlanRenumber([gpA, gpB, gpHidden], 2, null)
	gpEq(str(gpPlan.get("a", "")), "001", "the first free slot is unchanged")
	gpEq(str(gpPlan.get("b", "")), "003", "the hidden sheet's 002 is skipped")
	gpCheck(not gpPlan.has("h"), "a hidden sheet is never renumbered by an open-tab pass")
