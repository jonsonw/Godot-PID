extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# DRC engine + snapshot + config/waiver tests (ADR-39 P1).
# DRC 引擎 + 快照 + 配置/豁免测试（ADR-39 P1）。

const GP_SHEET_W: float = 420.0
const GP_SHEET_H: float = 297.0


static func _gpDef(gpId: String, gpSize: Vector2 = Vector2(30.0, 30.0),
		gpPorts: Array[GPPort] = [], gpAnchors: Array[GPAttachPoint] = [],
		gpMountKind: String = "", gpCategory: String = "equipment") -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = gpId
	gpD.gpCategory = gpCategory
	gpD.gpDefaultSize = gpSize
	gpD.gpPorts = gpPorts
	gpD.gpAttachPoints = gpAnchors
	gpD.gpMountKind = gpMountKind
	return gpD


static func _gpPort(gpName: String, gpType: String = GPPort.GP_NOZZLE) -> GPPort:
	var gpP: GPPort = GPPort.new()
	gpP.gpName = gpName
	gpP.gpType = gpType
	return gpP


static func _gpAnchor(gpName: String, gpPos: Vector2,
		gpDir: Vector2 = Vector2.ZERO) -> GPAttachPoint:
	return GPAttachPoint.gpMake(gpName, gpPos, gpDir)


static func _gpSheet() -> GPSheet:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpWidthMM = GP_SHEET_W
	gpS.gpHeightMM = GP_SHEET_H
	gpS.gpNumber = "PID-001"
	gpS.gpName = "PID-001"
	gpS.gpFrameOn = true
	return gpS


static func _gpStdDocOff() -> GPProjectStandard:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	gpCfg["rules"]["drc.doc.title_block_required"] = {"enabled": false}
	gpCfg["rules"]["drc.doc.title_block_drawing_no"] = {"enabled": false}
	gpCfg["rules"]["drc.doc.sheet_number"] = {"enabled": false}
	gpStd.gpValidation = gpCfg
	return gpStd


static func _gpTankNozzleWorld() -> Dictionary:
	var gpTankDef: GPSymbolDef = _gpDef("TANK", Vector2(60.0, 100.0), [],
		[_gpAnchor("bottom", Vector2(0.5, 1.0), Vector2(0.0, 1.0))], "", "tank")
	var gpNozDef: GPSymbolDef = _gpDef("NOZ", Vector2(8.0, 4.0),
		[_gpPort("pipe")], [], "NOZZLE", "general")
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpTank: GPPIDNode = gpG.gpNewNode("n1", "TANK", "T-1002", Vector2(200.0, 200.0))
	gpG.gpAddNode(gpTank)
	var gpNoz: GPPIDNode = gpG.gpNewNode("n2", "NOZ", "", Vector2(100.0, 100.0))
	gpNoz.gpParentUid = "n1"
	gpNoz.gpMountAnchor = "bottom"
	gpG.gpAddNode(gpNoz)
	var gpDefs: Array[GPSymbolDef] = [gpTankDef, gpNozDef]
	return {"graph": gpG, "defs": gpDefs, "sheet": _gpSheet()}


# Snapshot must resolve a mounted child through the host chain, not its stale gpPosition.
# 快照必须经宿主父链解析挂载子件，而不是它的过期 gpPosition。
func gpTestSnapshotResolvesMountWorldPosition() -> void:
	var gpF: Dictionary = _gpTankNozzleWorld()
	var gpDefs: Array[GPSymbolDef] = gpF["defs"] as Array[GPSymbolDef]
	var gpSnap: GPDrcSnapshot = GPDrcSnapshot.gpBuild(gpF["graph"], gpF["sheet"], gpDefs)
	var gpRect: Rect2 = gpSnap.gpRect("n2")
	# Host at (200,200), tank half-height 50 => bottom anchor y=250; nozzle 8x4 centered there.
	gpApprox(gpRect.get_center().x, 200.0, 0.6, "nozzle follows host x / 管口随宿主 x")
	gpApprox(gpRect.get_center().y, 250.0, 0.6, "nozzle follows host bottom / 管口贴在宿主底边")
	gpCheck(gpRect.get_center().distance_to(Vector2(100.0, 100.0)) > 50.0,
		"stale child position is not used / 不使用过期子件坐标")


# Snapshot's edge polyline must start at the nozzle port, not at the child's stale centre.
# 快照折线必须从管口端口出发，而不是子件过期中心。
func gpTestSnapshotEdgeStartsAtPort() -> void:
	var gpF: Dictionary = _gpTankNozzleWorld()
	var gpG: GPPIDGraph = gpF["graph"]
	var gpPumpDef: GPSymbolDef = _gpDef("PUMP", Vector2(60.0, 60.0), [_gpPort("suction")], [],
		"", "pump")
	var gpPump: GPPIDNode = gpG.gpNewNode("n3", "PUMP", "P-1002", Vector2(400.0, 250.0))
	gpG.gpAddNode(gpPump)
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n2", "port_id": "pipe"}, {"node_id": "n3", "port_id": "suction"},
		GPPIDEdge.GP_PROCESS, "", "PL-1001")
	gpG.gpAddEdge(gpE)
	var gpDefs: Array[GPSymbolDef] = (gpF["defs"] as Array[GPSymbolDef]).duplicate()
	gpDefs.append(gpPumpDef)
	var gpSnap: GPDrcSnapshot = GPDrcSnapshot.gpBuild(gpG, gpF["sheet"], gpDefs)
	var gpPts: PackedVector2Array = gpSnap.gpPolyline("e1")
	gpCheck(gpPts.size() >= 2, "edge has a polyline / 连线有折线")
	if gpPts.size() >= 2:
		gpCheck(gpPts[0].distance_to(Vector2(100.0, 100.0)) > 40.0,
			"polyline does not start at stale child centre / 折线不从过期子件中心出发")


func gpTestEdgeRefMissingIsError() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "BOX", "A-1", Vector2(100.0, 100.0)))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "gone", "port_id": "out"}, {"node_id": "n1", "port_id": "in"},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE)
	var gpF: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpG, _gpSheet(),
		[_gpDef("BOX", Vector2(30.0, 30.0), [_gpPort("in"), _gpPort("out")])], _gpStdDocOff())
	var gpHit: bool = false
	for gpOne in gpF:
		if gpOne.gpCheckId == "drc.topo.edge_ref_missing" and gpOne.gpSeverity == GPFinding.GP_ERROR:
			gpHit = true
	gpCheck(gpHit, "missing endpoint reference is an error / 端点引用失效是 error")


func gpTestMountOrphanIsError() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = gpG.gpNewNode("n1", "NOZ", "", Vector2(100.0, 100.0))
	gpN.gpParentUid = "missing-host"
	gpN.gpMountAnchor = "bottom"
	gpG.gpAddNode(gpN)
	var gpF: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpG, _gpSheet(),
		[_gpDef("NOZ", Vector2(8.0, 4.0), [_gpPort("pipe")], [], "NOZZLE", "general")],
		_gpStdDocOff())
	var gpHit: bool = false
	for gpOne in gpF:
		if gpOne.gpCheckId == "drc.symbol.mount_orphan":
			gpHit = true
	gpCheck(gpHit, "mount orphan is reported / 挂载孤儿被检出")


func gpTestNozzleDuplicateIsError() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "TANK", "T-1", Vector2(200.0, 200.0)))
	for gpId in ["n2", "n3"]:
		var gpN: GPPIDNode = gpG.gpNewNode(gpId, "NOZ", "", Vector2(100.0, 100.0))
		gpN.gpParentUid = "n1"
		gpN.gpMountAnchor = "bottom"
		gpN.gpProps["nozzle_id"] = "N1"
		gpG.gpAddNode(gpN)
	var gpF: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpG, _gpSheet(),
		[_gpDef("TANK", Vector2(60.0, 100.0), [], [_gpAnchor("bottom", Vector2(0.5, 1.0))],
			"", "tank"), _gpDef("NOZ", Vector2(8.0, 4.0), [_gpPort("pipe")], [],
			"NOZZLE", "general")], _gpStdDocOff())
	var gpHit: bool = false
	for gpOne in gpF:
		if gpOne.gpCheckId == "drc.symbol.nozzle_duplicate":
			gpHit = true
	gpCheck(gpHit, "duplicate nozzle number is reported / 重复管口号被检出")


func gpTestConfigCanDisableRule() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "NOZ", "", Vector2(100.0, 100.0)))
	(gpG.gpGetNode("n1") as GPPIDNode).gpParentUid = "gone"
	var gpStd: GPProjectStandard = _gpStdDocOff()
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	gpCfg["rules"]["drc.symbol.mount_integrity"] = {"enabled": false}
	gpStd.gpValidation = gpCfg
	var gpF: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpG, _gpSheet(),
		[_gpDef("NOZ", Vector2(8.0, 4.0))], gpStd)
	for gpOne in gpF:
		gpCheck(gpOne.gpCheckId != "drc.symbol.mount_orphan",
			"disabled rule produces no finding / 关闭的规则不产出发现")


func gpTestWaiverMarksFindingAndStopsBlocking() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "NOZ", "", Vector2(100.0, 100.0)))
	var gpN: GPPIDNode = gpG.gpGetNode("n1")
	gpN.gpParentUid = "gone"
	var gpStd: GPProjectStandard = _gpStdDocOff()
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	gpCfg["waivers"] = [{
		"rule": "drc.symbol.mount_orphan", "entity_uid": gpN.gpRefId(),
		"reason": "test waiver", "approver": "test",
	}]
	gpStd.gpValidation = gpCfg
	var gpF: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpG, _gpSheet(),
		[_gpDef("NOZ", Vector2(8.0, 4.0))], gpStd)
	var gpFound: GPFinding = null
	for gpOne in gpF:
		if gpOne.gpCheckId == "drc.symbol.mount_orphan":
			gpFound = gpOne
	gpCheck(gpFound != null, "finding exists before waiver / 豁免前存在发现")
	if gpFound != null:
		gpCheck(gpFound.gpWaived, "waiver marks the finding / 豁免标记生效")
		gpCheck(not gpFound.gpBlocksDelivery(), "waived error no longer blocks / 已豁免 error 不再阻断")


func gpTestRegistryContainsP1Checks() -> void:
	var gpIds: Dictionary = {}
	for gpR in GPDrcRegistry.gpAll():
		gpIds[gpR.gpId] = true
	for gpId in ["drc.topo.edge_ref_missing", "drc.symbol.mount_integrity",
			"drc.doc.sheet_number", "drc.layout.title_block_intrusion"]:
		gpCheck(gpIds.has(gpId), "registry has " + gpId)


func gpTestJsonReportShape() -> void:
	var gpF: Array[GPFinding] = [GPFinding.gpMake("drc.topo", GPFinding.GP_ERROR,
		"drc.edge_ref_missing", ["e1", "from"]).gpAs("drc.topo.edge_ref_missing", "drc.fix.relink")]
	var gpJson: String = GPDRCReport.gpToJson(gpF, {"mode": "sheet"})
	var gpParsed: Variant = JSON.parse_string(gpJson)
	gpCheck(gpParsed is Dictionary, "JSON parses / JSON 可解析")
	if gpParsed is Dictionary:
		var gpD: Dictionary = gpParsed as Dictionary
		gpEq(str(gpD.get("schema", "")), "gpid.drc/1", "schema is stable / schema 稳定")
		gpCheck((gpD.get("findings", []) as Array).size() == 1, "one finding row / 一条发现")


# The original 2026-10-28 incident, full structure: tank + 5 nozzles + pump + 2 nozzles + one
# line. The legacy layout rules must stay silent (the P0 geometry fix), while the real missing
# attributes are still reported.
# 2026-10-28 事故的完整结构：容器 + 5 管口 + 泵 + 2 管口 + 一条线。legacy 布局规则必须沉默
#（P0 几何修复），而真实的缺失属性仍要报。
func gpTestUserFixtureLayoutStaysClean() -> void:
	var gpTankDef: GPSymbolDef = _gpDef("TANK", Vector2(60.0, 100.0), [],
		[_gpAnchor("bottom", Vector2(0.5, 1.0), Vector2(0.0, 1.0)),
		_gpAnchor("left", Vector2(0.0, 0.5), Vector2(-1.0, 0.0)),
		_gpAnchor("right", Vector2(1.0, 0.5), Vector2(1.0, 0.0)),
		_gpAnchor("top_left", Vector2(0.3, 0.0), Vector2(0.0, -1.0)),
		_gpAnchor("top_right", Vector2(0.7, 0.0), Vector2(0.0, -1.0))], "", "tank")
	var gpNozDef: GPSymbolDef = _gpDef("NOZ", Vector2(8.0, 4.0), [_gpPort("pipe")], [],
		"NOZZLE", "general")
	var gpPumpDef: GPSymbolDef = _gpDef("PUMP", Vector2(60.0, 60.0), [_gpPort("suction")], [],
		"", "pump")
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "TANK", "T-1002", Vector2(200.0, 300.0)))
	var gpAnchors: Array[String] = ["bottom", "left", "right", "top_left", "top_right"]
	for gpI in range(gpAnchors.size()):
		var gpN: GPPIDNode = gpG.gpNewNode("n%d" % (gpI + 2), "NOZ", "", Vector2(100.0, 100.0))
		gpN.gpParentUid = "n1"
		gpN.gpMountAnchor = gpAnchors[gpI]
		gpG.gpAddNode(gpN)
	gpG.gpAddNode(gpG.gpNewNode("n7", "PUMP", "P-1002", Vector2(500.0, 400.0)))
	for gpI in range(2):
		var gpN: GPPIDNode = gpG.gpNewNode("n%d" % (gpI + 8), "NOZ", "", Vector2(500.0, 400.0))
		gpN.gpParentUid = "n7"
		gpN.gpMountAnchor = "suction" if gpI == 0 else "bottom"
		gpG.gpAddNode(gpN)
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e10",
		{"node_id": "n2", "port_id": "pipe"}, {"node_id": "n8", "port_id": "pipe"},
		GPPIDEdge.GP_PROCESS, "", "")
	gpG.gpAddEdge(gpE)
	var gpDefs: Array[GPSymbolDef] = [gpTankDef, gpNozDef, gpPumpDef]
	var gpF: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpG, _gpSheet(), gpDefs, _gpStdDocOff())
	var gpLayout: int = 0
	for gpOne in gpF:
		if gpOne.gpRuleId == "drc.layout" and (gpOne.gpMessageKey == "drc.symbols_overlap"
				or gpOne.gpMessageKey == "drc.edge_crosses_symbol"):
			gpLayout += 1
	gpEq(gpLayout, 0, "user fixture has no false layout findings / 用户结构没有假布局发现")
	var gpAttrs: bool = false
	for gpOne in gpF:
		if gpOne.gpMessageKey == "drc.edge_attrs_missing":
			gpAttrs = true
	gpCheck(gpAttrs, "missing dn/medium/spec is still reported / 缺属性仍被报出")


func gpTestLineOverlapIsReported() -> void:
	var gpBoxDef: GPSymbolDef = _gpDef("BOX", Vector2(20.0, 20.0),
		[_gpPort("in"), _gpPort("out")])
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpPos: Array[Vector2] = [Vector2(100.0, 100.0), Vector2(500.0, 100.0),
		Vector2(200.0, 100.0), Vector2(400.0, 100.0)]
	for gpI in range(4):
		gpG.gpAddNode(gpG.gpNewNode("n%d" % gpI, "BOX", "B-%d" % gpI, gpPos[gpI]))
	var gpE1: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n0", "port_id": "out"}, {"node_id": "n1", "port_id": "in"},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	var gpE2: GPPIDEdge = gpG.gpNewEdgeEx("e2",
		{"node_id": "n2", "port_id": "out"}, {"node_id": "n3", "port_id": "in"},
		GPPIDEdge.GP_PROCESS, "", "PL-2")
	gpG.gpAddEdge(gpE1)
	gpG.gpAddEdge(gpE2)
	var gpF: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpG, _gpSheet(), [gpBoxDef],
		_gpStdDocOff())
	var gpHit: bool = false
	for gpOne in gpF:
		if gpOne.gpCheckId == "drc.layout.line_overlap":
			gpHit = true
	gpCheck(gpHit, "collinear overlap is reported / 共线重叠被检出")


func gpTestValidationConfigRoundTripsThroughProjectStandard() -> void:
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	gpCfg["rules"]["drc.layout"] = {"severity": "error"}
	gpCfg["thresholds"]["line_gap_mm"] = 12.0
	gpCfg["waivers"] = [{"rule": "drc.layout", "entity_uid": "u-1", "reason": "test"}]
	gpStd.gpValidation = gpCfg
	var gpD: Dictionary = gpStd.gpToDict()
	gpCheck(gpD.has("validation"), "validation is written when customised / 定制后写出 validation")
	var gpBack: GPProjectStandard = GPProjectStandard.gpFromDict(gpD)
	var gpBackCfg: Dictionary = gpBack.gpValidationConfig()
	gpEq(str((gpBackCfg["rules"]["drc.layout"] as Dictionary).get("severity", "")), "error",
		"rule severity round-trips / 规则级别往返")
	gpApprox(float(gpBackCfg["thresholds"].get("line_gap_mm", 0.0)), 12.0, 0.001,
		"threshold round-trips / 阈值往返")
	gpEq((gpBackCfg["waivers"] as Array).size(), 1, "waiver round-trips / 豁免往返")


func gpTestExportGateBlocksErrorsAndAllowsWaiver() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = gpG.gpNewNode("n1", "MISSING", "A-1", Vector2(100.0, 100.0))
	gpG.gpAddNode(gpN)
	var gpSheet: GPSheet = _gpSheet()
	gpSheet.gpGraph = gpG
	var gpStd: GPProjectStandard = _gpStdDocOff()
	var gpGate: Dictionary = GPExportGate.gpCheck([gpSheet], [], gpStd)
	gpCheck(bool(gpGate.get("blocked", false)), "un-waived error blocks export / 未豁免 error 阻断导出")
	gpCheck(int(gpGate.get("errors", 0)) > 0, "gate counts errors / 闸门统计 error")
	# Waive the symbol-unknown finding by its stable uid (instance id when no uid exists).
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	gpCfg["waivers"] = [{
		"rule": "drc.symbol.unknown", "entity_uid": gpN.gpRefId(),
		"reason": "legacy symbol", "approver": "test",
	}]
	gpStd.gpValidation = gpCfg
	var gpGate2: Dictionary = GPExportGate.gpCheck([gpSheet], [], gpStd)
	gpCheck(not bool(gpGate2.get("blocked", false)), "waived error no longer blocks / 已豁免 error 不再阻断")


func gpTestRevisionPolicyIsOptIn() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "BOX", "A-1", Vector2(100.0, 100.0)))
	var gpStd: GPProjectStandard = _gpStdDocOff()
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	gpCfg["policy"]["revision_required"] = true
	gpStd.gpValidation = gpCfg
	var gpF: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpG, _gpSheet(),
		[_gpDef("BOX", Vector2(30.0, 30.0))], gpStd)
	var gpHit: bool = false
	for gpOne in gpF:
		if gpOne.gpCheckId == "drc.doc.revision_missing":
			gpHit = true
	gpCheck(gpHit, "revision policy fires when enabled / 开启版次策略后报出")


func gpTestSemInstrumentNeedsSignalWhenEnabled() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "INST", "I-1", Vector2(100.0, 100.0)))
	var gpStd: GPProjectStandard = _gpStdDocOff()
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	gpCfg["policy"]["sem_enabled"] = true
	gpStd.gpValidation = gpCfg
	var gpF: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpG, _gpSheet(),
		[_gpDef("INST", Vector2(22.0, 22.0), [], [], "", "instrument")], gpStd)
	var gpHit: bool = false
	for gpOne in gpF:
		if gpOne.gpCheckId == "drc.sem.instrument_loop":
			gpHit = true
	gpCheck(gpHit, "SEM instrument check fires when enabled / 开启 SEM 后仪表缺信号报出")


func gpTestDocAndRulesHashesAreDeterministic() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "BOX", "A-1", Vector2(100.0, 100.0)))
	var gpSheet: GPSheet = _gpSheet()
	gpSheet.gpGraph = gpG
	var gpA: String = GPExportGate.gpDocHash([gpSheet])
	var gpB: String = GPExportGate.gpDocHash([gpSheet])
	gpEq(gpA, gpB, "doc hash is deterministic / 文档哈希确定")
	gpG.gpAddNode(gpG.gpNewNode("n2", "BOX", "A-2", Vector2(200.0, 100.0)))
	var gpC: String = GPExportGate.gpDocHash([gpSheet])
	gpCheck(gpA != gpC, "doc hash changes with the graph / 图变哈希变")
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpR1: String = GPExportGate.gpRulesHash(gpStd)
	var gpR2: String = GPExportGate.gpRulesHash(gpStd)
	gpEq(gpR1, gpR2, "rules hash is deterministic / 规则哈希确定")
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	gpCfg["rules"]["drc.layout"] = {"severity": "error"}
	gpStd.gpValidation = gpCfg
	gpCheck(GPExportGate.gpRulesHash(gpStd) != gpR1,
		"rules hash changes with config / 配置变哈希变")


func gpTestExportGateMatchesEngineOnFixtures() -> void:
	var gpGoodRead: GPIOResult = GPProjectIO.gpReadSheets("res://tests/fixtures/drc_good.pid.json")
	gpCheck(gpGoodRead.gpIsOk(), "good fixture loads / 好夹具可载入")
	var gpBadRead: GPIOResult = GPProjectIO.gpReadSheets("res://tests/fixtures/drc_bad.pid.json")
	gpCheck(gpBadRead.gpIsOk(), "bad fixture loads / 坏夹具可载入")
	if not gpGoodRead.gpIsOk() or not gpBadRead.gpIsOk():
		return
	var gpDefs: Array[GPSymbolDef] = GPSymbolLibrary.gpDefaultDefs()
	var gpGoodGate: Dictionary = GPExportGate.gpCheck(gpGoodRead.gpPayload as Array, gpDefs)
	gpCheck(not bool(gpGoodGate.get("blocked", true)),
		"good fixture passes the gate / 好夹具通过闸门")
	var gpBadSheets: Array = gpBadRead.gpPayload as Array
	var gpBadGate: Dictionary = GPExportGate.gpCheck(gpBadSheets, gpDefs)
	gpCheck(bool(gpBadGate.get("blocked", false)),
		"bad fixture is blocked / 坏夹具被阻断")
	# Same engine, same findings: this is the "GUI and CLI share one gate" contract.
	# 同一引擎、同一发现：这就是「GUI 与 CLI 共用一道闸门」的契约。
	var gpEngineFindings: Array[GPFinding] = GPDrcEngine.gpRunProject(gpBadSheets, gpDefs)
	var gpGateFindings: Array = gpBadGate.get("findings", []) as Array
	gpEq(gpGateFindings.size(), gpEngineFindings.size(),
		"gate and engine finding counts agree / 闸门与引擎发现数一致")
	if gpGateFindings.size() == gpEngineFindings.size():
		for gpI in range(gpEngineFindings.size()):
			gpEq((gpGateFindings[gpI] as GPFinding).gpCheckId,
				gpEngineFindings[gpI].gpCheckId,
				"finding %d check id agrees / 第 %d 条检查号一致" % [gpI, gpI])


func gpTestRepairPlanMapsHintsAndDedupes() -> void:
	var gpF: Array[GPFinding] = [
		GPFinding.gpMake("drc.layout", GPFinding.GP_WARNING, "drc.symbol_off_sheet",
			["n1"]).gpAs("drc.layout", "drc.fix.move").gpOnEntity("u-1", "s1"),
		GPFinding.gpMake("drc.topo", GPFinding.GP_ERROR, "drc.edge_ref_missing",
			["e1", "from"]).gpAs("drc.topo.edge_ref_missing", "drc.fix.relink").gpOnEntity("u-2", "s1"),
		GPFinding.gpMake("drc.topo", GPFinding.GP_ERROR, "drc.edge_ref_missing",
			["e1", "from"]).gpAs("drc.topo.edge_ref_missing", "drc.fix.relink").gpOnEntity("u-2", "s1"),
		GPFinding.gpMake("drc.doc", GPFinding.GP_INFO, "drc.title_block_inherit",
			["a", "b", "c"]).gpAs("drc.doc.title_block_inherit", "drc.fix.review_override").gpOnEntity("s1", "s1"),
	]
	var gpPlan: Array[Dictionary] = GPDRCRepair.gpPlan(gpF)
	gpEq(gpPlan.size(), 3, "plan dedupes entity+check / 计划按对象+检查号去重")
	gpEq(gpPlan[0].get("action", ""), GPDRCRepair.GP_ACTION_RELINK,
		"error relink first / error 的 relink 排在最前")
	var gpCounts: Dictionary = GPDRCRepair.gpCounts(gpPlan)
	gpEq(int(gpCounts.get(GPDRCRepair.GP_ACTION_RELINK, 0)), 1,
		"one relink action / 一个 relink 动作")
	gpEq(int(gpCounts.get(GPDRCRepair.GP_ACTION_MOVE, 0)), 1,
		"one move action / 一个 move 动作")


# GUI and CLI both call GPExporterRegistry; two calls on the same data must be byte-identical.
# This is the closest headless proof of "same exporter, same bytes" without driving the GUI.
# GUI 与 CLI 都调 GPExporterRegistry；同一数据两次导出必须逐字节一致。这是不驱动 GUI 时
# 「同一导出器、同一字节」的最接近证明。
func gpTestExporterIsByteDeterministic() -> void:
	var gpRead: GPIOResult = GPProjectIO.gpReadSheets("res://tests/fixtures/drc_good.pid.json")
	gpCheck(gpRead.gpIsOk(), "fixture loads for export / 导出夹具可载入")
	if not gpRead.gpIsOk():
		return
	var gpSheets: Array = gpRead.gpPayload as Array
	var gpSheet: GPSheet = gpSheets[0] as GPSheet
	var gpDefs: Array[GPSymbolDef] = GPSymbolLibrary.gpDefaultDefs()
	# PDF / DXF are the delivery artefacts named by E06. The project container is not asserted
	# here: it carries save-time metadata by design, so byte-identity is not its contract.
	# PDF / DXF 是 E06 指定的交付物。工程容器不在此断言：它按设计携带保存时间元数据，
	# 逐字节一致不是它的契约。
	for gpKind in [GPExporterRegistry.GP_DXF, GPExporterRegistry.GP_PDF]:
		var gpExt: String = GPExporterRegistry.gpExtensionOf(gpKind)
		var gpA: String = "user://drc_consistency_a." + gpExt
		var gpB: String = "user://drc_consistency_b." + gpExt
		var gpRa: GPIOResult = GPExporterRegistry.gpExport(gpKind, gpA, gpSheet.gpGraph,
			GPSymbolLibrary.gpUserPacks(), gpSheet)
		var gpRb: GPIOResult = GPExporterRegistry.gpExport(gpKind, gpB, gpSheet.gpGraph,
			GPSymbolLibrary.gpUserPacks(), gpSheet)
		if not gpRa.gpIsOk() or not gpRb.gpIsOk():
			gpCheck(false, "export failed for " + gpKind + ": " + str(gpRa.gpDetail))
			continue
		var gpBytesA: PackedByteArray = FileAccess.get_file_as_bytes(gpA)
		var gpBytesB: PackedByteArray = FileAccess.get_file_as_bytes(gpB)
		gpEq(gpBytesA.size(), gpBytesB.size(), gpKind + " byte size matches / 字节数一致")
		gpCheck(gpBytesA == gpBytesB, gpKind + " bytes are identical / 两次导出逐字节一致")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gpA))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gpB))


func gpTestFamilySliceLimitsRegisteredRules() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "MISSING", "", Vector2(100.0, 100.0)))
	var gpSheet: GPSheet = _gpSheet()
	var gpF: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpG, gpSheet, [],
		_gpStdDocOff(), {"families": ["symbol"], "skip_legacy": true})
	for gpOne in gpF:
		gpCheck(gpOne.gpRuleId == "drc.symbol" or gpOne.gpRuleId == "drc.layout",
			"family slice only returns that family / 族切片只返回该族")
	gpCheck(gpF.size() > 0, "symbol family slice has findings / symbol 族切片有发现")
