extends "res://tests/gp_test.gd"
# The five container-level off-page DRC rules (ADR-43 §2.5 / W12-S4). Each rule gets a
# positive AND a negative pin: the negative proves a healthy container is silent, the positive
# proves the rule reports with the right check id, severity, anchor and detail — the "all
# green but nothing runs" trap (iron rule: assertions must be able to fail).
# 五条容器级跨图纸 DRC 规则（ADR-43 §2.5 / W12-S4）。每条规则都钉**正反两面**：反面证明
# 健康容器保持沉默，正面证明规则以正确的检查号、级别、锚点与明细报告 —— 防「全绿但什么
# 都没跑」（铁律：断言必须能失败）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


const GP_ID_PIPE: String = "LOFFPAGE001"
const GP_ID_SIGNAL: String = "LOFFPAGE002"


# ------------------------------------------------------------------ rig
# 测试夹具

static func _gpConnectorDef(gpId: String) -> GPSymbolDef:
	for gpD in GPSymbolLibrary.gpDefaultDefs():
		if gpD.gpId == gpId:
			return gpD
	return null


static func _gpEquipmentDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "PEQUIPDRCTEST"
	gpD.gpCategory = "equipment"
	var gpP: GPPort = GPPort.new()
	gpP.gpName = "p1"
	gpP.gpType = GPPort.GP_NOZZLE
	gpD.gpPorts.append(gpP)
	return gpD


static func _gpConnector(gpNodeId: String, gpDefId: String, gpLinkId: String) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpNodeId
	gpN.gpSymbolId = gpDefId
	gpN.gpPosition = Vector2(100, 100)
	if gpLinkId != "":
		gpN.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = gpLinkId
	return gpN


static func _gpEquipment(gpNodeId: String) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpNodeId
	gpN.gpSymbolId = "PEQUIPDRCTEST"
	gpN.gpPosition = Vector2(50, 50)
	return gpN


static func _gpEdge(gpEdgeId: String, gpFromNode: String, gpFromPort: String,
		gpToNode: String, gpToPort: String, gpAttrs: Dictionary) -> GPPIDEdge:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpInstanceId = gpEdgeId
	gpE.gpKind = GPPIDEdge.GP_PROCESS
	gpE.gpFromRef = {"node_id": gpFromNode, "port_id": gpFromPort}
	gpE.gpToRef = {"node_id": gpToNode, "port_id": gpToPort}
	gpE.gpAttrs = gpAttrs.duplicate(true)
	return gpE


static func _gpSheet(gpSheetId: String, gpNumber: String, gpNodes: Array,
		gpEdges: Array) -> GPSheet:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpId = gpSheetId
	gpS.gpNumber = gpNumber
	gpS.gpGraph = GPPIDGraph.new()
	for gpRaw in gpNodes:
		gpS.gpGraph.gpNodes.append(gpRaw as GPPIDNode)
	for gpRaw2 in gpEdges:
		gpS.gpGraph.gpEdges.append(gpRaw2 as GPPIDEdge)
	return gpS


static func _gpLink(gpLinkId: String, gpKind: String, gpASheet: String, gpANode: String,
		gpBSheet: String, gpBNode: String, gpAttrs: Dictionary) -> GPOffPageLink:
	var gpL: GPOffPageLink = GPOffPageLink.new()
	gpL.gpInstanceId = gpLinkId
	gpL.gpKind = gpKind
	gpL.gpA = {GPOffPageLink.GP_KEY_SHEET: gpASheet, GPOffPageLink.GP_KEY_NODE: gpANode,
		GPOffPageLink.GP_KEY_PORT: "ref"}
	gpL.gpB = {GPOffPageLink.GP_KEY_SHEET: gpBSheet, GPOffPageLink.GP_KEY_NODE: gpBNode,
		GPOffPageLink.GP_KEY_PORT: "ref"}
	gpL.gpAttrs = gpAttrs.duplicate(true)
	return gpL


# A healthy two-sheet container: one process link between two pipe connectors, contract
# attrs consistent on the link and on both edges.
# 健康的双图容器：一条 PROCESS link 连接两个管道连接符，契约属性在 link 与两端边上一致。
static func _gpRig() -> Dictionary:
	var gpAttrs: Dictionary = {"dn": "50", "medium": "H2O"}
	var gpDefs: Array[GPSymbolDef] = [
		_gpConnectorDef(GP_ID_PIPE), _gpConnectorDef(GP_ID_SIGNAL), _gpEquipmentDef()]
	var gpSheet1: GPSheet = _gpSheet("s1", "1",
		[_gpConnector("n1", GP_ID_PIPE, "xlink-1"), _gpEquipment("n0")],
		[_gpEdge("e1", "n0", "p1", "n1", "ref", gpAttrs)])
	var gpSheet2: GPSheet = _gpSheet("s2", "3",
		[_gpConnector("n2", GP_ID_PIPE, "xlink-1"), _gpEquipment("n0b")],
		[_gpEdge("e2", "n2", "ref", "n0b", "p1", gpAttrs)])
	var gpLink: GPOffPageLink = _gpLink("xlink-1", GPPIDEdge.GP_PROCESS,
		"s1", "n1", "s2", "n2", gpAttrs)
	return {"defs": gpDefs, "sheets": [gpSheet1, gpSheet2] as Array,
		"links": [gpLink] as Array[GPOffPageLink], "link": gpLink}


static func _gpRunAudit(gpRig: Dictionary) -> Array[GPFinding]:
	return GPOffPageAudit.gpRun(gpRig["sheets"], gpRig["links"], gpRig["defs"])


static func _gpChecksOf(gpFindings: Array[GPFinding]) -> Array[String]:
	var gpOut: Array[String] = []
	for gpF in gpFindings:
		gpOut.append(gpF.gpCheckId)
	return gpOut


# ------------------------------------------------------------------ tests
# 测试

# The negative pin for the WHOLE family: a healthy container is silent.
# 整族的反面钉：健康容器保持沉默。
func gpTestHealthyContainerIsSilent() -> void:
	gpEq(_gpRunAudit(_gpRig()).size(), 0,
		"a consistent container produces zero off-page findings")


# Rule 1: every flavor of a dangling endpoint is an ERROR naming the link.
# 规则 1：悬空端点的每种形态都是 ERROR 并指名 link。
func gpTestOrphanEndpoints() -> void:
	var gpRig: Dictionary = _gpRig()
	(gpRig["links"] as Array).append(_gpLink("xlink-9", GPPIDEdge.GP_PROCESS,
		"s-gone", "n1", "s1", "n0", {}))
	var gpF1: Array[GPFinding] = _gpRunAudit(gpRig)
	var gpKeys1: Array[String] = []
	for gpF in gpF1:
		gpKeys1.append(gpF.gpMessageKey)
	# The MESSAGE KEY, not just the rule id — the node flavor would otherwise silently absorb
	# the sheet case (found by reverse verification: disabling the sheet branch stayed green).
	# 断言**消息键**而非仅规则 id —— 否则节点形态会悄悄吞掉图纸形态（反向验证发现：
	# 关掉图纸分支测试仍绿）。
	gpCheck(gpKeys1.has("drc.offpage.orphan_sheet"),
		"a missing SHEET names the sheet flavour")
	# The sheet flavour and the node flavour are distinguishable by message key.
	# 图纸形态与节点形态凭消息键可分。
	var gpRig2: Dictionary = _gpRig()
	(gpRig2["links"] as Array).append(_gpLink("xlink-9", GPPIDEdge.GP_PROCESS,
		"s1", "n-gone", "s1", "n0", {}))
	var gpF2: Array[GPFinding] = _gpRunAudit(gpRig2)
	var gpKeys2: Array[String] = []
	for gpF in gpF2:
		gpKeys2.append(gpF.gpMessageKey)
	gpCheck(gpKeys2.has("drc.offpage.orphan_node"), "a missing NODE names its message key")
	var gpRig3: Dictionary = _gpRig()
	var gpL3: GPOffPageLink = _gpLink("xlink-9", GPPIDEdge.GP_PROCESS,
		"s1", "n1", "s2", "n2", {})
	gpL3.gpB[GPOffPageLink.GP_KEY_PORT] = "bad-port"
	(gpRig3["links"] as Array).append(gpL3)
	var gpF3: Array[GPFinding] = _gpRunAudit(gpRig3)
	var gpKeys3: Array[String] = []
	for gpF in gpF3:
		gpKeys3.append(gpF.gpMessageKey)
	gpCheck(gpKeys3.has("drc.offpage.orphan_port"), "a missing PORT names its message key")
	# (The extra link carries empty attrs, so it ALSO legally raises a WARNING attr mismatch —
	# scope the severity pin to the orphan family alone.)
	#（附加的 link 带空属性，会合法地产出 WARNING 级失配 —— 级别钉只圈 orphan 族。）
	for gpF in gpF3:
		if gpF.gpCheckId == "drc.offpage.orphan_link":
			gpEq(gpF.gpSeverity, GPFinding.GP_ERROR, "orphan findings are ERROR level")


# Rule 2, both directions: a link landing on a non-connector, and a connector claiming a
# link the table does not know.
# 规则 2 双向：link 落在非连接符上；连接符声称表中不存在的 link。
func gpTestUnpairedBothDirections() -> void:
	var gpRig: Dictionary = _gpRig()
	(gpRig["links"] as Array).append(_gpLink("xlink-9", GPPIDEdge.GP_PROCESS,
		"s1", "n0", "s2", "n2", {}))
	var gpF1: Array[GPFinding] = _gpRunAudit(gpRig)
	var gpKeys: Array[String] = []
	for gpF in gpF1:
		gpKeys.append(gpF.gpMessageKey)
	gpCheck(gpKeys.has("drc.offpage.unpaired_link"),
		"a link landing on plain equipment is unpaired")
	var gpRig2: Dictionary = _gpRig()
	var gpStray: GPPIDNode = _gpConnector("n5", GP_ID_PIPE, "xlink-404")
	(gpRig2["sheets"][0] as GPSheet).gpGraph.gpNodes.append(gpStray)
	var gpF2: Array[GPFinding] = _gpRunAudit(gpRig2)
	var gpKeys2: Array[String] = []
	for gpF in gpF2:
		gpKeys2.append(gpF.gpMessageKey)
	gpCheck(gpKeys2.has("drc.offpage.unpaired_stray"),
		"a connector claiming an unknown link_id is unpaired (the ? flag is real)")
	for gpF in gpF2:
		gpEq(gpF.gpSeverity, GPFinding.GP_ERROR, "unpaired findings are ERROR level")


# Rule 3: the three-way comparison — an edge disagreeing with the link snapshot is the
# drift the sync command exists to fix; absent ends are skipped, not fabricated.
# 规则 3：三方比对 —— 边与 link 快照不一致正是同步命令要修的漂移；缺失端跳过而非臆造。
func gpTestAttrMismatchThreeWay() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpSheet1: GPSheet = gpRig["sheets"][0] as GPSheet
	(gpSheet1.gpGraph.gpEdges[0] as GPPIDEdge).gpAttrs["dn"] = "45"
	var gpF: Array[GPFinding] = _gpRunAudit(gpRig)
	var gpHits: int = 0
	for gpX in gpF:
		if gpX.gpMessageKey == "drc.offpage.attr_mismatch":
			gpHits += 1
			gpCheck(gpX.gpParams.has("dn"), "the mismatching KEY is named: %s" % [gpX.gpParams])
			gpCheck(gpX.gpSeverity == GPFinding.GP_WARNING,
				"attr mismatch is a WARNING, not a gate")
			gpCheck(str(gpX.gpParams[2]) == "50" and str(gpX.gpParams[3]) == "45"
				and str(gpX.gpParams[4]) == "50",
				"the detail shows link=50, A=45, B=50: %s" % [gpX.gpParams])
	gpEq(gpHits, 1, "exactly one mismatch row for the drifted key")
	# A free end (no edge AT ALL) is ABSENT, not wrong: the link snapshot alone must not fire.
	# Removing the edge (not emptying its attrs) is what models the dangling connector.
	# 自由端（**完全没有边**）是「缺失」而非「错误」：只有 link 快照不应触发。把边从图里
	# 拿掉（而非清空其属性）才是「连接符悬空」的建模。
	var gpRig2: Dictionary = _gpRig()
	var gpSheet2: GPSheet = gpRig2["sheets"][1] as GPSheet
	gpSheet2.gpGraph.gpEdges.remove_at(0)
	var gpF2: Array[GPFinding] = _gpRunAudit(gpRig2)
	for gpX2 in gpF2:
		gpCheck(gpX2.gpMessageKey != "drc.offpage.attr_mismatch",
			"an edgeless end never fabricates a mismatch")


# Rule 4: link kind vs connector family — the plan's named case (a SIGNAL link on a NOZZLE
# port) and the two-ends-disagree case.
# 规则 4：link 类别 vs 连接符族 —— 方案点名的情形（SIGNAL link 接 NOZZLE 端口）与
# 两端不一致的情形。
func gpTestKindMismatch() -> void:
	var gpRig: Dictionary = _gpRig()
	(gpRig["link"] as GPOffPageLink).gpKind = GPPIDEdge.GP_SIGNAL
	var gpF: Array[GPFinding] = _gpRunAudit(gpRig)
	var gpPortHits: int = 0
	for gpX in gpF:
		if gpX.gpMessageKey == "drc.offpage.kind_port":
			gpPortHits += 1
			gpEq(gpX.gpSeverity, GPFinding.GP_ERROR, "kind mismatch is ERROR level")
	gpEq(gpPortHits, 2, "a SIGNAL link on both NOZZLE connectors is flagged at BOTH ends")
	var gpRig2: Dictionary = _gpRig()
	(gpRig2["sheets"][1] as GPSheet).gpGraph.gpNodes[0] = _gpConnector("n2", GP_ID_SIGNAL,
		"xlink-1")
	var gpF2: Array[GPFinding] = _gpRunAudit(gpRig2)
	var gpKeys: Array[String] = []
	for gpX2 in gpF2:
		gpKeys.append(gpX2.gpMessageKey)
	gpCheck(gpKeys.has("drc.offpage.kind_ends"),
		"a pipe connector and a signal connector on one link disagree")


# Rule 5: the same endpoint pair under two links — the LATER link is flagged, once.
# 规则 5：同一端点对两条 link —— 被标的是**靠后**那条，且只一条。
func gpTestDuplicateEndpointPair() -> void:
	var gpRig: Dictionary = _gpRig()
	(gpRig["links"] as Array).append(_gpLink("xlink-2", GPPIDEdge.GP_PROCESS,
		"s1", "n1", "s2", "n2", {}))
	var gpF: Array[GPFinding] = _gpRunAudit(gpRig)
	var gpHits: int = 0
	for gpX in gpF:
		if gpX.gpMessageKey == "drc.offpage.duplicate":
			gpHits += 1
			gpCheck(str(gpX.gpParams[0]) == "xlink-2",
				"the LATER link is the flagged one: %s" % [gpX.gpParams])
	gpEq(gpHits, 1, "one duplicate row per extra link, not per direction")
	gpEq(_gpDupSeverity(gpF), GPFinding.GP_WARNING, "duplicate is a WARNING")


static func _gpDupSeverity(gpFindings: Array[GPFinding]) -> String:
	for gpF in gpFindings:
		if gpF.gpMessageKey == "drc.offpage.duplicate":
			return gpF.gpSeverity
	return ""


# Every finding carries a stable uid (waiver anchor) and, where a node exists, its sheet.
# 每条发现都带稳定 uid（豁免锚点）；有节点时带所在图纸。
func gpTestFindingsCarryUidAndSheet() -> void:
	var gpRig: Dictionary = _gpRig()
	(gpRig["link"] as GPOffPageLink).gpAttrs["dn"] = "99"
	var gpF: Array[GPFinding] = _gpRunAudit(gpRig)
	gpCheck(gpF.size() > 0, "the drift fired (precondition)")
	for gpX in gpF:
		gpCheck(gpX.gpEntityUid.begins_with("xlink-"),
			"the uid is the link's stable id: %s" % [gpX.gpEntityUid])
		gpCheck(gpX.gpSheetId == "s1" or gpX.gpSheetId == "s2",
			"the finding knows which sheet it sits on: %s" % [gpX.gpSheetId])


# The ENGINE wiring: project mode picks the family up, sheet-only calls stay silent — the
# backward-compat pin for the optional parameter.
# 引擎接线：工程模式收进该族；仅图纸调用保持沉默 —— 可选参数的向后兼容钉。
func gpTestEngineWiring() -> void:
	var gpRig: Dictionary = _gpRig()
	(gpRig["link"] as GPOffPageLink).gpAttrs["dn"] = "99"
	var gpWith: Array[GPFinding] = GPDrcEngine.gpRunProject(gpRig["sheets"],
		gpRig["defs"], null, gpRig["links"])
	var gpHit: bool = false
	for gpF in gpWith:
		if gpF.gpCheckId.begins_with("drc.offpage."):
			gpHit = true
			break
	gpCheck(gpHit, "project mode runs the off-page family when links are handed in")
	var gpWithout: Array[GPFinding] = GPDrcEngine.gpRunProject(gpRig["sheets"],
		gpRig["defs"], null)
	for gpF2 in gpWithout:
		gpCheck(not gpF2.gpCheckId.begins_with("drc.offpage."),
			"sheet-only callers see no off-page rows (optional param stays optional)")


# D10 rule A: dangling END — a link endpoint connector with NO edge at its referenced port.
# Negative + positive: a healthy container is silent; a panel-picked link whose B connector
# never got its line reports a WARNING anchored on that connector.
# D10 规则 A：悬空端 —— link 端点连接符在被引用端口上**没有**边。正反两面：健康容器沉默；
# 面板选图建立的 link 其 B 端连接符一直没接线时，报出锚定在该连接符上的 WARNING。
func gpTestDanglingEndWarning() -> void:
	# Negative: the healthy rig has an edge at BOTH referenced ports — no dangling finding.
	# 反面：健康夹具在被引用的两端端口上都有边 —— 无悬空发现。
	var gpClean: Array[GPFinding] = _gpRunAudit(_gpRig())
	for gpF in gpClean:
		gpCheck(gpF.gpMessageKey != "drc.offpage.dangling_end",
			"healthy container stays silent on dangling / 健康容器对悬空保持沉默")
	# Positive: strip sheet 2's edge — the B connector now dangles at its "ref" port.
	# 正面：抽掉图纸 2 的边 —— B 端连接符在 ref 端口悬空。
	var gpRig: Dictionary = _gpRig()
	var gpSheet2: GPSheet = gpRig["sheets"][1] as GPSheet
	gpSheet2.gpGraph.gpEdges.clear()
	var gpF1: Array[GPFinding] = _gpRunAudit(gpRig)
	var gpHits: Array[GPFinding] = []
	for gpX in gpF1:
		if gpX.gpMessageKey == "drc.offpage.dangling_end":
			gpHits.append(gpX)
	gpEq(gpHits.size(), 1, "exactly one dangling-end finding / 恰好一条悬空端发现")
	if gpHits.size() == 1:
		gpEq(gpHits[0].gpSeverity, GPFinding.GP_WARNING,
			"dangling is a WARNING / 悬空是 WARNING")
		gpEq(gpHits[0].gpNodeId, "n2", "anchored on the B connector / 锚在 B 端连接符")
		gpEq(gpHits[0].gpEntityUid, GPOffPageAudit.GP_LINK_UID_PREFIX + "xlink-1",
			"stable link uid for waivers / 供豁免的稳定 link uid")


# D10 rule B: GHOST membership — a connector claims a link that EXISTS but does not list it.
# Distinct from the unknown-claim stray: this one shows a REAL number (it renders via the
# link it claims) yet no cascade and no jump can ever reach it.
# D10 规则 B：幽灵成员 —— 连接符声称一条**存在**但不认得它的 link。与「未知声称」不同：
# 它经所声称的 link 渲染出**真实编号**，但级联与跳转永远到不了它。
func gpTestGhostMembershipError() -> void:
	var gpRig: Dictionary = _gpRig()
	# A second connector on sheet 1 claiming the SAME (existing) link id — the pasted-copy
	# ghost. The copy path strips link_id now (D11); an archive written before did not.
	# 图纸 1 上第二个连接符声称**同一条（存在的）**link id —— 粘贴副本幽灵。现在复制路径
	# 已剥离 link_id（D11）；此前写出的存档没有。
	(gpRig["sheets"][0] as GPSheet).gpGraph.gpNodes.append(
		_gpConnector("n9", GP_ID_PIPE, "xlink-1"))
	var gpF: Array[GPFinding] = _gpRunAudit(gpRig)
	var gpKeys: Array[String] = []
	for gpX in gpF:
		gpKeys.append(gpX.gpMessageKey)
	gpCheck(gpKeys.has("drc.offpage.membership"),
		"ghost membership is reported / 幽灵成员被报告")
	for gpX in gpF:
		if gpX.gpMessageKey == "drc.offpage.membership":
			gpEq(gpX.gpSeverity, GPFinding.GP_ERROR,
				"membership is an ERROR / 成员校验是 ERROR")
			gpEq(gpX.gpNodeId, "n9", "anchored on the ghost / 锚在幽灵旗标")
	# And the honest copy path (D11) makes the whole class impossible going forward: a node
	# WITHOUT the claim produces nothing.
	# 且诚实的复制路径（D11）让这一类问题今后无法产生：不带声称的节点什么都不报。
	var gpRig2: Dictionary = _gpRig()
	(gpRig2["sheets"][0] as GPSheet).gpGraph.gpNodes.append(_gpConnector("n9b", GP_ID_PIPE, ""))
	gpEq(_gpRunAudit(gpRig2).size(), 0, "claim-free copy is silent / 无声称副本沉默")
