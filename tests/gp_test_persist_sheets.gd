extends "res://tests/gp_test.gd"
# Multi-sheet persistence tests (P2).
# 多图纸持久化测试（P2）。
# The failure mode being guarded against: a project with several tabs is saved, reopened,
# and only the first tab comes back. That is invisible until someone prints page 3.
# 所防范的失效模式：一个含多个标签页的工程保存后重新打开，只有第一个标签页回来。
# 在有人打印第 3 页之前，这个问题是看不见的。
# See 持久化实现方案 §6 / 见「持久化实现方案」§6。

const GP_TMP: String = "user://gp_test_sheets.pid.json"
# Synthetic, de-identified stand-in for the historic multi-document shape (see the same
# fixture in gp_test_persist_migrate.gd). The real client archive was removed 2026-10-07.
# 历史多文档形态的**合成脱敏**替身（另见 gp_test_persist_migrate.gd 中的同名 fixture）。
# 真实客户存档已于 2026-10-07 移除。
const GP_HISTORIC: String = "user://gp_test_sheets_historic.pid.json"


func _gpCleanup() -> void:
	for gpPath in [GP_TMP, GP_HISTORIC]:
		var gpAbs: String = ProjectSettings.globalize_path(gpPath)
		if FileAccess.file_exists(gpAbs):
			DirAccess.remove_absolute(gpAbs)


# Write the historic-shape fixture so gpReadSheets() runs against a REAL file on disk.
# 写出历史形态 fixture，使 gpReadSheets() 作用在磁盘上的**真实文件**上。
static func _gpWriteHistoric(gpPath: String) -> void:
	var gpFixture: Dictionary = {
		"meta": {"schema": "pid-1.0", "title": "Historic multi-document sample", "docs": 2},
		"documents": [
			{"id": "D1", "title": "Sheet A", "graph": {
				"meta": {"version": "1.0"},
				"nodes": [
					{"instance_id": "u-1", "symbol_id": "valve", "tag": "FV-001",
					 "position": [120, 80], "attr_values": {"size": "DN80"}},
					{"instance_id": "u-2", "symbol_id": "tank", "tag": "T-001",
					 "position": [220, 80]},
				],
				"edges": [{"instance_id": "e-1",
					"from_ref": {"node_id": "u-1", "port_id": "out"},
					"to_ref": {"node_id": "u-2", "port_id": "in"}}],
			}},
			{"id": "D2", "title": "Sheet B", "graph": {
				"nodes": [{"instance_id": "u-3", "symbol_id": "pump", "tag": "P-001",
					"position": [120, 80]}],
				"edges": [],
			}},
		],
		"cross_links": [{"from_doc": "D1", "from_node": "u-2", "to_doc": "D2",
			"to_node": "u-3", "tag": "PL-001"}],
	}
	GPAtomicFile.gpWriteJsonAtomic(gpPath, gpFixture)


# Three sheets, each with distinguishable content.
# 三张图纸，每张都有可区分的内容。
static func _gpThreeSheets() -> Array[GPSheet]:
	var gpOut: Array[GPSheet] = []
	var gpTags: Array[String] = ["P-101", "P-102", "P-103"]
	var gpNames: Array[String] = ["给料", "磨矿", "分级"]
	var gpI: int = 0
	for gpTag in gpTags:
		var gpS: GPSheet = GPSheet.gpNew("sheet-" + str(gpI + 1), gpNames[gpI], gpI)
		var gpN: GPPIDNode = gpS.gpGraph.gpNewNode("n" + str(gpI + 1), "pump", gpTag,
			Vector2(10.0 * float(gpI + 1), 20.0))
		gpN.gpUid = "uid-" + str(gpI + 1)
		gpS.gpGraph.gpAddNode(gpN)
		gpOut.append(gpS)
		gpI += 1
	return gpOut


# A sheet serialises to the v3 sheet shape and comes back identical.
# 图纸序列化为 v3 图纸形状并原样回来。
func gpTestSheetRoundTrip() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpGraph.gpAddNode(gpS.gpGraph.gpNewNode("n1", "pump", "P-1", Vector2(5, 6)))
	var gpD: Dictionary = gpS.gpToDict()
	gpCheck(str(gpD.get("id", "")) == "sheet-1", "sheet id must be written")
	gpCheck(str(gpD.get("name", "")) == "首页", "sheet name must be written")
	gpCheck(not gpD.has("tag_rules"), "project-level rules must NOT be duplicated per sheet")
	var gpS2: GPSheet = GPSheet.gpFromDict(gpD)
	gpCheck(gpS2.gpId == "sheet-1", "id must survive")
	gpCheck(gpS2.gpName == "首页", "name must survive")
	gpCheck(gpS2.gpGraph != null, "the graph must be rebuilt")
	if gpS2.gpGraph != null:
		gpCheck(gpS2.gpGraph.gpNodes.size() == 1, "geometry must survive")
		if gpS2.gpGraph.gpNodes.size() >= 1:
			gpCheck((gpS2.gpGraph.gpNodes[0] as GPPIDNode).gpTag == "P-1",
				"the tag must survive")


# Three sheets written and re-read must ALL come back, in order, with their own geometry.
# 写入再读出的三张图纸必须**全部**回来、顺序正确、且各自带着自己的几何。
func gpTestMultiSheetWriteRead() -> void:
	_gpCleanup()
	var gpSheets: Array = _gpThreeSheets()
	var gpW: GPIOResult = GPProjectIO.gpWriteSheetsResult(gpSheets, GP_TMP)
	gpCheck(gpW.gpIsOk(), "multi-sheet write must succeed: " + gpW.gpToString())
	if not gpW.gpIsOk():
		_gpCleanup()
		return
	var gpR: GPIOResult = GPProjectIO.gpReadSheets(GP_TMP)
	gpCheck(gpR.gpIsOk(), "multi-sheet read must succeed: " + gpR.gpToString())
	if not gpR.gpIsOk():
		_gpCleanup()
		return
	var gpBack: Array = gpR.gpPayload as Array
	gpCheck(gpBack.size() == 3, "all three sheets must come back, got " + str(gpBack.size()))
	if gpBack.size() < 3:
		_gpCleanup()
		return
	var gpTags: Array[String] = []
	for gpS in gpBack:
		var gpSheet: GPSheet = gpS as GPSheet
		gpCheck(gpSheet.gpGraph.gpNodes.size() == 1,
			"each sheet keeps its own single node")
		if gpSheet.gpGraph.gpNodes.size() >= 1:
			gpTags.append((gpSheet.gpGraph.gpNodes[0] as GPPIDNode).gpTag)
	gpCheck(gpTags == ["P-101", "P-102", "P-103"],
		"sheets must keep their order and content, got " + str(gpTags))
	# Identities must survive so a later save does not reshuffle the tab bar.
	# 标识必须存活，使后续保存不会打乱标签栏顺序。
	gpCheck((gpBack[0] as GPSheet).gpId == "sheet-1", "sheet 1 keeps its id")
	gpCheck((gpBack[2] as GPSheet).gpIndex == 2, "sheet 3 keeps its index")
	_gpCleanup()


# A single-sheet archive must still read as a ONE-element list (no special case for callers).
# 单图纸存档必须仍读作**单元素**列表（调用方无需特例）。
func gpTestSingleSheetReadsAsOne() -> void:
	_gpCleanup()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-1", Vector2(1, 2)))
	var gpW: GPIOResult = GPProjectIO.gpWriteProjectResult(gpG, GP_TMP)
	gpCheck(gpW.gpIsOk(), "single-sheet write must succeed")
	if not gpW.gpIsOk():
		_gpCleanup()
		return
	var gpR: GPIOResult = GPProjectIO.gpReadSheets(GP_TMP)
	gpCheck(gpR.gpIsOk(), "single-sheet read must succeed")
	if gpR.gpIsOk():
		var gpBack: Array = gpR.gpPayload as Array
		gpCheck(gpBack.size() == 1, "one sheet, got " + str(gpBack.size()))
		if gpBack.size() >= 1:
			gpCheck(((gpBack[0] as GPSheet).gpGraph.gpNodes.size()) == 1,
				"the node must survive")
	_gpCleanup()


# A single-sheet project must NOT be upgraded to v3 on disk: archives written before this
# feature have to stay byte-stable.
# 单图纸工程**不得**在磁盘上升格为 v3：本功能之前写出的存档必须保持字节稳定。
func gpTestSingleSheetStaysV2() -> void:
	_gpCleanup()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-1", Vector2(1, 2)))
	var gpW: GPIOResult = GPProjectIO.gpWriteProjectResult(gpG, GP_TMP)
	if not gpW.gpIsOk():
		_gpCleanup()
		return
	var gpR: GPIOResult = GPAtomicFile.gpReadJsonDict(GP_TMP)
	if gpR.gpIsOk():
		var gpD: Dictionary = gpR.gpPayload as Dictionary
		gpCheck(str(gpD.get("format", "")) == "",
			"a single-sheet save must not gain the v3 format marker")
		gpCheck(gpD.has("nodes"), "a single-sheet save keeps the v2 top-level shape")
	# ...but writing it as SHEETS does upgrade it.
	# ……但以「图纸」方式写出则会升格。
	var gpSheets: Array = GPProjectIO.gpReadSheets(GP_TMP).gpPayload as Array
	var gpW2: GPIOResult = GPProjectIO.gpWriteSheetsResult(gpSheets, GP_TMP)
	if gpW2.gpIsOk():
		var gpR2: GPIOResult = GPAtomicFile.gpReadJsonDict(GP_TMP)
		if gpR2.gpIsOk():
			gpCheck(str((gpR2.gpPayload as Dictionary).get("format", "")) == "g-pid",
				"an explicit sheets write must produce v3")
	_gpCleanup()


# The historic multi-document shape must reopen as its two real sheets — from a fixture
# written on the spot, not from a shipped sample file (the client archive was removed
# 2026-10-07). A missing fixture must FAIL here, not skip: the old existence guard hid the
# fact that a deleted file was silently deleting coverage.
# 历史多文档形态必须重新打开为它真正的两页 —— 用**当场写出的 fixture**，而不是随库样例文件
# （客户存档已于 2026-10-07 移除）。fixture 缺失必须在此**失败**而非跳过：
# 旧的护栏掩盖了「文件被删＝覆盖被删」的事实。
func gpTestHistoricDocumentsReopenAsSheets() -> void:
	_gpWriteHistoric(GP_HISTORIC)
	var gpR: GPIOResult = GPProjectIO.gpReadSheets(GP_HISTORIC)
	gpCheck(gpR.gpIsOk(), "the historic shape must read as sheets")
	if not gpR.gpIsOk():
		return
	var gpSheets: Array = gpR.gpPayload as Array
	gpCheck(gpSheets.size() == 2, "the historic shape has 2 documents, got "
		+ str(gpSheets.size()))
	if gpSheets.size() < 2:
		return
	var gpD1: GPSheet = gpSheets[0] as GPSheet
	var gpD2: GPSheet = gpSheets[1] as GPSheet
	gpCheck(gpD1.gpId == "D1", "the first document id must be preserved")
	gpCheck(gpD1.gpGraph.gpNodes.size() == 2, "D1 has 2 nodes")
	gpCheck(gpD2.gpGraph.gpNodes.size() == 1, "D2 has 1 node")
	gpCheck((gpD2.gpGraph.gpNodes[0] as GPPIDNode).gpTag == "P-001",
		"D2's node keeps its tag")
	_gpCleanup()


# An empty sheet list must be refused, not written as a broken archive.
# 空图纸列表必须被拒绝，而不是写出一个损坏的存档。
func gpTestEmptySheetListRefused() -> void:
	var gpErr: int = GPProjectIO.gpWriteSheets([], "user://gp_never.pid.json")
	gpCheck(gpErr != OK, "writing zero sheets must fail")
	gpCheck(not GPProjectIO.gpWriteSheetsResult([], "user://gp_never.pid.json").gpIsOk(),
		"the result-typed writer must report failure too")
