extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# U5 / K03: the cross-sheet connection REPORT (gp_test_offpage_report.gd). The report is a
# pure composition — GPOffPageAudit findings for the states, GPOffPageResolver for the
# derived numbers — so the pins here prove the COMPOSITION: healthy rows read "paired" with
# resolved peer data, a stripped line reads "dangling_b", a broken reference reads "broken",
# a contract drift sets the drift flag, and a ghost connector lands in the ghosts list.
# U5 / K03：跨图纸连接**报表**（gp_test_offpage_report.gd）。报表是纯组合 —— 状态来自
# GPOffPageAudit 的发现、派生号来自 GPOffPageResolver —— 故此处钉的是**组合**：健康行读出
# paired 与完整对端数据；抽线读出 dangling_b；断引用读出 broken；契约漂移点亮 drift；
# 幽灵连接符进入 ghosts 清单。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


const GP_ID_PIPE: String = "LOFFPAGE001"


static func _gpConnectorDef() -> GPSymbolDef:
	for gpD in GPSymbolLibrary.gpDefaultDefs():
		if gpD.gpId == GP_ID_PIPE:
			return gpD
	return null


static func _gpEquipmentDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "PEQUIPREPTEST"
	gpD.gpCategory = "equipment"
	var gpP: GPPort = GPPort.new()
	gpP.gpName = "p1"
	gpP.gpType = GPPort.GP_NOZZLE
	gpD.gpPorts.append(gpP)
	return gpD


static func _gpConnector(gpNodeId: String, gpLinkId: String) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpNodeId
	gpN.gpSymbolId = GP_ID_PIPE
	gpN.gpPosition = Vector2(100, 100)
	if gpLinkId != "":
		gpN.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = gpLinkId
	return gpN


static func _gpEquipment(gpNodeId: String) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpNodeId
	gpN.gpSymbolId = "PEQUIPREPTEST"
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


static func _gpLink(gpLinkId: String, gpTag: String, gpASheet: String, gpANode: String,
		gpBSheet: String, gpBNode: String, gpAttrs: Dictionary) -> GPOffPageLink:
	var gpL: GPOffPageLink = GPOffPageLink.new()
	gpL.gpInstanceId = gpLinkId
	gpL.gpTag = gpTag
	gpL.gpA = {GPOffPageLink.GP_KEY_SHEET: gpASheet, GPOffPageLink.GP_KEY_NODE: gpANode,
		GPOffPageLink.GP_KEY_PORT: "ref"}
	gpL.gpB = {GPOffPageLink.GP_KEY_SHEET: gpBSheet, GPOffPageLink.GP_KEY_NODE: gpBNode,
		GPOffPageLink.GP_KEY_PORT: "ref"}
	gpL.gpAttrs = gpAttrs.duplicate(true)
	return gpL


# Healthy two-sheet container: one link, both ends wired, contract consistent. The B-end
# equipment carries a TAG so the resolver can derive a target tag for the report row.
# 健康双图容器：一条 link、两端接线、契约一致。B 端设备带**位号**，使 resolver 能为报表
# 行推导目标位号。
static func _gpRig() -> Dictionary:
	var gpAttrs: Dictionary = {"dn": "50", "medium": "H2O"}
	var gpDefs: Array[GPSymbolDef] = [_gpConnectorDef(), _gpEquipmentDef()]
	var gpEquipB: GPPIDNode = _gpEquipment("n0b")
	gpEquipB.gpTag = "TK-101"
	var gpSheet1: GPSheet = _gpSheet("s1", "1",
		[_gpConnector("n1", "xlink-1"), _gpEquipment("n0")],
		[_gpEdge("e1", "n0", "p1", "n1", "ref", gpAttrs)])
	var gpSheet2: GPSheet = _gpSheet("s2", "3",
		[gpEquipB, _gpConnector("n2", "xlink-1")],
		[_gpEdge("e2", "n2", "ref", "n0b", "p1", gpAttrs)])
	var gpLink: GPOffPageLink = _gpLink("xlink-1", "3-1", "s1", "n1", "s2", "n2", gpAttrs)
	return {"defs": gpDefs, "sheets": [gpSheet1, gpSheet2] as Array,
		"links": [gpLink] as Array[GPOffPageLink], "link": gpLink}


static func _gpRowsOf(gpRig: Dictionary) -> Array[Dictionary]:
	var gpOut: Dictionary = GPOffPageReport.gpRows(gpRig["sheets"], gpRig["links"],
		gpRig["defs"])
	return gpOut["rows"] as Array[Dictionary]


func gpTestHealthyRowIsPairedAndResolved() -> void:
	var gpRows: Array[Dictionary] = _gpRowsOf(_gpRig())
	gpEq(gpRows.size(), 1, "one row per link / 每 link 一行")
	var gpR: Dictionary = gpRows[0]
	gpEq(str(gpR["state"]), "paired", "healthy link is paired / 健康 link 为已配对")
	gpCheck(not bool(gpR["drift"]), "no drift / 无漂移")
	gpEq(str(gpR["tag"]), "3-1", "tag shown / 显示编号")
	gpEq(str(gpR["peer_number"]), "3", "peer number derived / 对端图号已推导")
	gpEq(str(gpR["target_tag"]), "TK-101", "target tag derived / 目标位号已推导")
	gpEq(str(gpR["medium"]), "H2O", "medium derived / 介质已推导")


func gpTestDanglingEndMarksState() -> void:
	var gpRig: Dictionary = _gpRig()
	(gpRig["sheets"][1] as GPSheet).gpGraph.gpEdges.clear()
	var gpRows: Array[Dictionary] = _gpRowsOf(gpRig)
	gpEq(str(gpRows[0]["state"]), "dangling_b", "unwired B end reads dangling_b / B 端未接线为 dangling_b")
	# And BOTH ends unwired reads dangling_ab. / 两端都未接线读 dangling_ab。
	(gpRig["sheets"][0] as GPSheet).gpGraph.gpEdges.clear()
	var gpRows2: Array[Dictionary] = _gpRowsOf(gpRig)
	gpEq(str(gpRows2[0]["state"]), "dangling_ab", "both ends read dangling_ab / 两端未接线为 dangling_ab")


func gpTestBrokenRefAndDriftFlags() -> void:
	# Broken: point the link at a sheet that does not exist. / 断引用：指向不存在的图纸。
	var gpRig: Dictionary = _gpRig()
	var gpLink: GPOffPageLink = gpRig["link"] as GPOffPageLink
	gpLink.gpB = {GPOffPageLink.GP_KEY_SHEET: "s-gone",
		GPOffPageLink.GP_KEY_NODE: "n2", GPOffPageLink.GP_KEY_PORT: "ref"}
	gpEq(str(_gpRowsOf(gpRig)[0]["state"]), "broken", "orphan ref reads broken / 孤儿引用为 broken")
	# Drift: an edge disagrees with the snapshot on dn. / 漂移：某条边在 dn 上与快照不一致。
	var gpRig2: Dictionary = _gpRig()
	(gpRig2["sheets"][0].gpGraph.gpEdges[0] as GPPIDEdge).gpAttrs["dn"] = "80"
	gpCheck(bool(_gpRowsOf(gpRig2)[0]["drift"]), "contract drift flags the row / 契约漂移点亮行")


func gpTestGhostListMembership() -> void:
	var gpRig: Dictionary = _gpRig()
	# A pasted-copy ghost: claims the existing link but is nobody's endpoint.
	# 粘贴副本幽灵：声称已存在的 link 但不是任何一端。
	(gpRig["sheets"][0] as GPSheet).gpGraph.gpNodes.append(_gpConnector("n9", "xlink-1"))
	var gpOut: Dictionary = GPOffPageReport.gpRows(gpRig["sheets"], gpRig["links"],
		gpRig["defs"])
	gpEq((gpOut["rows"] as Array).size(), 1, "rows stay one per link / 行仍每 link 一行")
	var gpGhosts: Array = gpOut["ghosts"] as Array
	gpEq(gpGhosts.size(), 1, "exactly one ghost / 恰好一枚幽灵")
	if gpGhosts.size() == 1:
		gpEq(str(gpGhosts[0]["node_id"]), "n9", "ghost anchored on the copy / 幽灵锚在副本")
		gpEq(str(gpGhosts[0]["link_id"]), "xlink-1", "ghost names its claim / 幽灵写明声称")


func gpTestEmptyProjectReport() -> void:
	# Empty everything: an empty report, not an error. / 全空：空报表而非错误。
	var gpOut: Dictionary = GPOffPageReport.gpRows([], [] as Array[GPOffPageLink],
		[] as Array[GPSymbolDef])
	gpEq((gpOut["rows"] as Array).size(), 0, "no rows / 无行")
	gpEq((gpOut["ghosts"] as Array).size(), 0, "no ghosts / 无幽灵")
