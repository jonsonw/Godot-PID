extends "res://tests/gp_test.gd"
# Multi-sheet persistence tests (P2).
# 多图纸持久化测试（P2）。
# The failure mode being guarded against: a project with several tabs is saved, reopened,
# and only the first tab comes back. That is invisible until someone prints page 3.
# 所防范的失效模式：一个含多个标签页的工程保存后重新打开，只有第一个标签页回来。
# 在有人打印第 3 页之前，这个问题是看不见的。
# See 持久化实现方案 §6 / 见「持久化实现方案」§6。

const GP_TMP: String = "user://gp_test_sheets.pid.json"


func _gpCleanup() -> void:
	var gpAbs: String = ProjectSettings.globalize_path(GP_TMP)
	if FileAccess.file_exists(gpAbs):
		DirAccess.remove_absolute(gpAbs)


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


# The historic multi-document sample must reopen as its two real sheets.
# 历史多文档样例必须重新打开为它真正的两页。
func gpTestHistoricDocumentsReopenAsSheets() -> void:
	var gpPath: String = "res://docs/samples/pani_detox.pid.json"
	if not FileAccess.file_exists(gpPath):
		return
	var gpR: GPIOResult = GPProjectIO.gpReadSheets(gpPath)
	gpCheck(gpR.gpIsOk(), "the historic sample must read as sheets")
	if not gpR.gpIsOk():
		return
	var gpSheets: Array = gpR.gpPayload as Array
	gpCheck(gpSheets.size() == 2, "the historic sample has 2 documents, got "
		+ str(gpSheets.size()))
	if gpSheets.size() < 2:
		return
	var gpD1: GPSheet = gpSheets[0] as GPSheet
	var gpD2: GPSheet = gpSheets[1] as GPSheet
	gpCheck(gpD1.gpId == "D1", "the first document id must be preserved")
	gpCheck(gpD1.gpGraph.gpNodes.size() == 2, "D1 has 2 nodes")
	gpCheck(gpD2.gpGraph.gpNodes.size() == 1, "D2 has 1 node")
	gpCheck((gpD2.gpGraph.gpNodes[0] as GPPIDNode).gpTag == "P-201",
		"D2's node keeps its tag")


# An empty sheet list must be refused, not written as a broken archive.
# 空图纸列表必须被拒绝，而不是写出一个损坏的存档。
func gpTestEmptySheetListRefused() -> void:
	var gpErr: int = GPProjectIO.gpWriteSheets([], "user://gp_never.pid.json")
	gpCheck(gpErr != OK, "writing zero sheets must fail")
	gpCheck(not GPProjectIO.gpWriteSheetsResult([], "user://gp_never.pid.json").gpIsOk(),
		"the result-typed writer must report failure too")
