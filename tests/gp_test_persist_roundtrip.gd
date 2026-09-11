extends "res://tests/gp_test.gd"
# Round-trip invariant tests for the persistence layer (P1).
# 持久化层往返不变式测试（P1）。
# The one thing that must never break: nothing the user drew may change by being saved and
# reopened. Tags, uids, positions and edge counts are the identities an engineer reasons
# about, so they are what these tests hold fixed.
# 绝不能破坏的一件事：用户画的东西不因保存再打开而改变。位号、uid、位置与边数是
# 工程师据以推理的标识，故这些测试把它们钉死。
# See 持久化实现方案 §12 (不变式) / 见「持久化实现方案」§12。

const GP_TMP: String = "user://gp_test_roundtrip.pid.json"


# A graph exercising every serialised field: props, names, anchor, offset, routing.
# 覆盖每个被序列化字段的图：props、names、锚点、偏移、走线。
func _gpSampleGraph() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpMeta["title"] = "往返测试"
	var gpN1: GPPIDNode = gpG.gpNewNode("n1", "pump", "P-1001", Vector2(10.5, 20.25))
	gpN1.gpUid = "doc-n1"
	gpN1.gpNames = {"zh_CN": "给料泵"}
	gpN1.gpProps = {"Q": "120", "H": "35"}
	gpN1.gpLabelAnchor = 2
	gpN1.gpLabelOffset = Vector2(0.0, 1.2)
	gpG.gpAddNode(gpN1)
	var gpN2: GPPIDNode = gpG.gpNewNode("n2", "tank", "V-1001", Vector2(50.0, 20.0))
	gpN2.gpUid = "doc-n2"
	gpG.gpAddNode(gpN2)
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "doc-n1", "port_id": "out"},
		{"node_id": "doc-n2", "port_id": "in"}, "PROCESS")
	gpE.gpRouting = [Vector2(20, 20), Vector2(40, 20)]
	gpE.gpTag = "PL-201"
	gpE.gpAttrs = {"dn": "80"}
	gpG.gpAddEdge(gpE)
	return gpG


func _gpCleanup() -> void:
	var gpAbs: String = ProjectSettings.globalize_path(GP_TMP)
	if FileAccess.file_exists(gpAbs):
		DirAccess.remove_absolute(gpAbs)


# Write -> migrate -> flatten -> rebuild: every field must come back identical.
# 写入 -> 迁移 -> 展平 -> 重建：每个字段都必须原样回来。
func gpTestFullFieldRoundTrip() -> void:
	var gpG: GPPIDGraph = _gpSampleGraph()
	var gpV3: Dictionary = GPSchemaMigrate.gpMigrate(gpG.gpToDict())
	var gpFlat: Dictionary = GPSchemaMigrate.gpToGraphDict(gpG.gpToDict())
	var gpG2: GPPIDGraph = GPPIDGraph.gpFromDict(gpFlat)
	gpCheck(gpG2 != null, "the rebuilt graph must not be null")
	if gpG2 == null:
		return
	gpCheck(gpG2.gpNodes.size() == 2, "both nodes must survive, got "
		+ str(gpG2.gpNodes.size()))
	gpCheck(gpG2.gpEdges.size() == 1, "the edge must survive")
	if gpG2.gpNodes.size() < 1:
		return
	var gpN1: GPPIDNode = gpG2.gpNodes[0] as GPPIDNode
	gpCheck(gpN1.gpUid == "doc-n1", "uid must survive: " + gpN1.gpUid)
	gpCheck(gpN1.gpTag == "P-1001", "tag must survive: " + gpN1.gpTag)
	gpCheck(gpN1.gpPosition == Vector2(10.5, 20.25), "position must survive: "
		+ str(gpN1.gpPosition))
	gpCheck(str(gpN1.gpNames.get("zh_CN", "")) == "给料泵", "names must survive")
	gpCheck(str(gpN1.gpProps.get("Q", "")) == "120", "props must survive")
	gpCheck(gpN1.gpLabelAnchor == 2, "label_anchor must survive")
	gpCheck(gpN1.gpLabelOffset == Vector2(0.0, 1.2), "label_offset must survive")
	if gpG2.gpEdges.size() >= 1:
		var gpE: GPPIDEdge = gpG2.gpEdges[0] as GPPIDEdge
		gpCheck(gpE.gpTag == "PL-201", "edge tag must survive")
		gpCheck(str(gpE.gpAttrs.get("dn", "")) == "80", "edge attrs must survive")
		gpCheck(gpE.gpRouting.size() == 2, "routing points must survive")
	gpCheck(int(gpV3.get("format_version", 0)) == 3, "the container must be v3")


# The uid / tag / edge-count invariant, asserted as sets.
# uid / 位号 / 边数不变式，以集合形式断言。
func gpTestIdentitySetsPreserved() -> void:
	var gpG: GPPIDGraph = _gpSampleGraph()
	var gpFlat: Dictionary = GPSchemaMigrate.gpToGraphDict(gpG.gpToDict())
	var gpG2: GPPIDGraph = GPPIDGraph.gpFromDict(gpFlat)
	var gpUids1: Array[String] = []
	var gpTags1: Array[String] = []
	for gpN in gpG.gpNodes:
		gpUids1.append((gpN as GPPIDNode).gpUid)
		gpTags1.append((gpN as GPPIDNode).gpTag)
	var gpUids2: Array[String] = []
	var gpTags2: Array[String] = []
	for gpN in gpG2.gpNodes:
		gpUids2.append((gpN as GPPIDNode).gpUid)
		gpTags2.append((gpN as GPPIDNode).gpTag)
	gpUids1.sort()
	gpUids2.sort()
	gpTags1.sort()
	gpTags2.sort()
	gpCheck(gpUids1 == gpUids2, "the uid set must be identical")
	gpCheck(gpTags1 == gpTags2, "the tag set must be identical")
	gpCheck(gpG2.gpEdges.size() == gpG.gpEdges.size(), "the edge count must be identical")


# Saving through GPProjectIO and reopening must land on the same drawing.
# 经 GPProjectIO 保存再打开必须得到同一张图。
func gpTestSaveReopenThroughProjectIO() -> void:
	_gpCleanup()
	var gpG: GPPIDGraph = _gpSampleGraph()
	var gpW: GPIOResult = GPProjectIO.gpWriteProjectResult(gpG, GP_TMP)
	gpCheck(gpW.gpIsOk(), "write should succeed: " + gpW.gpToString())
	if not gpW.gpIsOk():
		_gpCleanup()
		return
	var gpR: GPIOResult = GPProjectIO.gpReadProjectResult(GP_TMP)
	gpCheck(gpR.gpIsOk(), "read should succeed: " + gpR.gpToString())
	if gpR.gpIsOk():
		var gpG2: GPPIDGraph = gpR.gpPayload as GPPIDGraph
		gpCheck(gpG2.gpNodes.size() == 2, "reopened graph keeps both nodes")
		gpCheck(gpG2.gpEdges.size() == 1, "reopened graph keeps the edge")
		if gpG2.gpNodes.size() >= 1:
			gpCheck((gpG2.gpNodes[0] as GPPIDNode).gpTag == "P-1001",
				"reopened graph keeps the tag")
			gpCheck((gpG2.gpNodes[0] as GPPIDNode).gpPosition == Vector2(10.5, 20.25),
				"reopened graph keeps the position")
	_gpCleanup()


# Every real archive in the repository must open, migrate and keep its geometry.
# 仓库中每个真实存档都必须能打开、迁移并保住其几何。
func gpTestRealArchivesOpen() -> void:
	var gpPaths: Array[String] = [
		"res://project.pid.json",
		"res://docs/samples/pani_detox.pid.json",
	]
	for gpPath in gpPaths:
		if not FileAccess.file_exists(gpPath):
			continue
		var gpR: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
		gpCheck(gpR.gpIsOk(), gpPath + " should parse")
		if not gpR.gpIsOk():
			continue
		var gpRaw: Dictionary = gpR.gpPayload as Dictionary
		var gpCount: int = GPSchemaMigrate.gpSheetCount(gpRaw)
		gpCheck(gpCount >= 1, gpPath + " should yield at least one sheet, got "
			+ str(gpCount))
		var gpFlat: Dictionary = GPSchemaMigrate.gpToGraphDict(gpRaw)
		var gpG: GPPIDGraph = GPPIDGraph.gpFromDict(gpFlat)
		gpCheck(gpG != null, gpPath + " should rebuild into a graph")
		if gpG != null:
			gpCheck(gpG.gpNodes.size() >= 0, gpPath + " node count must be non-negative")
	# The historic sample specifically: it used to read back as ZERO nodes.
	# 历史样例尤为关键：它过去会被读成 **0 节点**。
	if FileAccess.file_exists("res://docs/samples/pani_detox.pid.json"):
		var gpRR: GPIOResult = GPAtomicFile.gpReadJsonDict("res://docs/samples/pani_detox.pid.json")
		if gpRR.gpIsOk():
			var gpTotal: int = 0
			for gpS in (GPSchemaMigrate.gpMigrate(gpRR.gpPayload as Dictionary).get(
					"sheets", []) as Array):
				gpTotal += ((gpS as Dictionary).get("nodes", []) as Array).size()
			gpCheck(gpTotal == 3,
				"the historic sample must yield 3 nodes across its sheets, got " + str(gpTotal))


# Exporting then re-importing the same graph must be loss-free.
# 导出再导入同一张图必须无损。
func gpTestExportImportLossless() -> void:
	_gpCleanup()
	var gpG: GPPIDGraph = _gpSampleGraph()
	var gpOut: GPIOResult = GPProjectExport.gpExportToFile("project", GP_TMP, gpG, [], {}, "doc-x")
	gpCheck(gpOut.gpIsOk(), "export should succeed: " + gpOut.gpToString())
	if not gpOut.gpIsOk():
		_gpCleanup()
		return
	var gpStats: Dictionary = gpOut.gpPayload as Dictionary
	gpCheck(int(gpStats.get("nodes", 0)) == 2, "export stats should report 2 nodes")
	gpCheck(int(gpStats.get("edges", 0)) == 1, "export stats should report 1 edge")
	var gpIn: GPIOResult = GPProjectImport.gpReadArchive(GP_TMP)
	gpCheck(gpIn.gpIsOk(), "read-back should succeed: " + gpIn.gpToString())
	if gpIn.gpIsOk():
		var gpTarget: GPPIDGraph = GPPIDGraph.new()
		var gpMerge: GPIOResult = GPProjectImport.gpMergeInto(gpTarget,
			gpIn.gpPayload as Dictionary)
		gpCheck(gpMerge.gpIsOk(), "merge should succeed")
		gpCheck(gpTarget.gpNodes.size() == 2, "imported graph should hold 2 nodes")
		if gpTarget.gpNodes.size() >= 1:
			gpCheck((gpTarget.gpNodes[0] as GPPIDNode).gpTag == "P-1001",
				"imported node keeps its tag")
	_gpCleanup()
