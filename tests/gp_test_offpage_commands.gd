extends "res://tests/gp_test.gd"
# Cross-sheet COMMANDS (ADR-43 / W12-S3): create (one gesture, one undo) + sync-to-peer.
# 跨图纸**命令**（ADR-43 / W12-S3）：创建（一个手势、一次撤销）+ 同步到对端。
#
# The failure modes being guarded against: (1) undo leaves an unpaired connector or a link
# behind — a state the user never created; (2) redo burns a new id or renumbers the link, so
# the twin connectors silently stop referring to the same link; (3) the link id collides when
# two sheets' independent id counters mint the same "xlink-N"; (4) a sync smuggles non-contract
# keys into edges, or re-captures its undo priors so data is lost after two undos.
# 所防范的失效模式：(1) 撤销留下未配对的连接符或残留 link —— 用户从未制造过的状态；
# (2) 重做烧掉新 id 或改掉 link 编号，使两个孪生连接符悄悄不再指向同一条 link；
# (3) 两张图纸各自独立的 id 计数器铸出相同的 "xlink-N" 造成撞号；(4) 同步把非契约键偷运进边，
# 或重复捕获撤销原值使两次撤销后丢数据。

# The two ids, read from the pack so the test cannot drift from the definitions.
# 两个 id，取自图元包，使测试不可能与定义脱节。
const GP_ID_PIPE: String = GPSymbolPackOffpage.GP_ID_PIPE
const GP_ID_SIGNAL: String = GPSymbolPackOffpage.GP_ID_SIGNAL


func _gpGraph() -> GPPIDGraph:
	return GPPIDGraph.new()


# A bound source: any node with a port; the command (like the edge command) stores refs,
# it does not re-resolve geometry.
# 一个绑定源：任意带端口的节点；本命令（与建边命令一样）只存引用，不重解析几何。
func _gpSourceNode(gpG: GPPIDGraph) -> void:
	var gpN: GPPIDNode = gpG.gpNewNode("n1", "PUMP001", "P-101", Vector2(100, 100), {})
	gpG.gpAddNode(gpN)


# The standard two-sheet rig: local graph (sheet-1) + peer graph (sheet-2, number "7"),
# a shared id generator and a live container link array.
# 标准双图纸夹具：本地图（sheet-1）+ 对端图（sheet-2，图号 "7"），共享 id 生成器
# 与**活的**容器 link 表。
func _gpRig() -> Dictionary:
	var gpLocal: GPPIDGraph = _gpGraph()
	_gpSourceNode(gpLocal)
	var gpPeer: GPPIDGraph = _gpGraph()
	var gpIds: GPIdGen = GPIdGen.new()
	var gpCtx: GPCommandContext = GPCommandContext.new(gpLocal, gpIds)
	var gpLinks: Array[GPOffPageLink] = []
	return {"local": gpLocal, "peer": gpPeer, "ctx": gpCtx, "links": gpLinks}


func _gpCreate(gpRig: Dictionary, gpKind: String = GPPIDEdge.GP_PROCESS) \
		-> GPCrossSheetCreateCommand:
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "n1", "port_id": "out"}, gpKind, "", Vector2(30, 40), Vector2(50, 60),
		"sheet-1", "sheet-2", "7", gpRig["peer"], gpRig["links"])
	gpCmd.gpExecute(gpRig["ctx"])
	return gpCmd


# ---- create ----
# ---- 创建 ----

# One gesture builds ALL four things and nothing else.
# 一个手势造出**全部四样**东西，且别无其它。
func gpTestCreateBuildsAllFourThings() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpCmd: GPCrossSheetCreateCommand = _gpCreate(gpRig)
	var gpLocal: GPPIDGraph = gpRig["local"]
	var gpPeer: GPPIDGraph = gpRig["peer"]
	var gpLinks: Array[GPOffPageLink] = gpRig["links"]
	gpCheck(gpCmd.gpRefusal == "", "the command accepts a bound source")
	gpEq(gpLinks.size(), 1, "exactly one link exists in the container")
	var gpLink: GPOffPageLink = gpLinks[0]
	# The local connector carries the link id and nothing else-derived.
	# 本端连接符带 link id，且无其它推导物。
	var gpLocalConn: GPPIDNode = null
	for gpN in gpLocal.gpNodes:
		if gpN.gpSymbolId == GP_ID_PIPE:
			gpLocalConn = gpN
	gpCheck(gpLocalConn != null, "the local sheet has a pipe connector")
	gpEq(str(gpLocalConn.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")),
		gpLink.gpInstanceId, "the local connector refers to THE link")
	# The edge runs from the source port into the connector's ref port.
	# 边从源端口接到连接符的 ref 端口。
	var gpEdge: GPPIDEdge = gpLocal.gpEdges[0]
	gpEq(str(gpEdge.gpFromRef.get("node_id", "")), "n1", "the edge starts at the source")
	gpEq(str(gpEdge.gpToRef.get("port_id", "")), GPSymbolPackOffpage.GP_PORT_NAME,
		"the edge lands on the connector's ref port")
	# The twin on the peer sheet shares the SAME link id.
	# 对端图纸上的孪生体共享**同一个** link id。
	var gpPeerConn: GPPIDNode = null
	for gpN in gpPeer.gpNodes:
		if gpN.gpSymbolId == GP_ID_PIPE:
			gpPeerConn = gpN
	gpCheck(gpPeerConn != null, "the peer sheet has a twin connector")
	gpEq(str(gpPeerConn.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")),
		gpLink.gpInstanceId, "the twin refers to the SAME link")
	# Endpoint order: A = local, B = peer.
	# 端点次序：A = 本端，B = 对端。
	gpEq(str(gpLink.gpA.get("sheet_id", "")), "sheet-1", "endpoint A is the local sheet")
	gpEq(str(gpLink.gpB.get("sheet_id", "")), "sheet-2", "endpoint B is the peer sheet")
	gpEq(str(gpLink.gpA.get("node_id", "")), gpLocalConn.gpInstanceId,
		"endpoint A points at the local connector")
	gpEq(str(gpLink.gpB.get("node_id", "")), gpPeerConn.gpInstanceId,
		"endpoint B points at the twin")


# The auto tag derives from the PEER drawing number + sequence, and is never copied from
# anything stored.
# 自动编号由**对端图号** + 序号推导，绝不抄自任何存储物。
func gpTestTagMintsFromPeerNumber() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpCmd: GPCrossSheetCreateCommand = _gpCreate(gpRig)
	gpEq((gpRig["links"][0] as GPOffPageLink).gpTag, "7-1",
		"the first tag on peer sheet 7 is 7-1")
	# A second link on the same pair increments the sequence.
	# 同一对图纸上的第二条 link 递增序号。
	var gpCmd2: GPCrossSheetCreateCommand = _gpCreate(gpRig)
	gpEq((gpRig["links"][1] as GPOffPageLink).gpTag, "7-2",
		"the second tag on peer sheet 7 is 7-2")
	gpCheck(gpCmd2.gpCreatedLinkId != gpCmd.gpCreatedLinkId,
		"two links never share an id")
	# Without a peer number the tag degrades to a bare sequence (still never empty).
	# 无对端图号时编号退化为纯序号（仍绝不为空）。
	var gpRig3: Dictionary = _gpRig()
	var gpCmd3: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "n1", "port_id": "out"}, GPPIDEdge.GP_PROCESS, "", Vector2.ZERO,
		Vector2.ZERO, "sheet-1", "sheet-2", "", gpRig3["peer"], gpRig3["links"])
	gpCmd3.gpExecute(gpRig3["ctx"])
	gpEq((gpRig3["links"][0] as GPOffPageLink).gpTag, "1", "a numberless peer yields a bare seq")


# A SIGNAL link picks the hexagon connector and carries the signal type into both the edge
# and the contract snapshot.
# SIGNAL link 选用六边形连接符，并把信号类型同时带进边与契约快照。
func gpTestSignalUsesHexagonAndCarriesType() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "n1", "port_id": "out"}, GPPIDEdge.GP_SIGNAL, "4-20mA",
		Vector2.ZERO, Vector2.ZERO, "sheet-1", "sheet-2", "7",
		gpRig["peer"], gpRig["links"])
	gpCheck(gpCmd.gpExecute(gpRig["ctx"]), "a signal link is accepted")
	var gpLocal: GPPIDGraph = gpRig["local"]
	var gpFound: bool = false
	for gpN in gpLocal.gpNodes:
		if gpN.gpSymbolId == GP_ID_SIGNAL:
			gpFound = true
	gpCheck(gpFound, "the signal link uses the hexagon connector, not the flag")
	var gpEdge: GPPIDEdge = gpLocal.gpEdges[0]
	gpEq(gpEdge.gpSignalType, "4-20mA", "the edge carries the signal type")
	gpEq((gpRig["links"][0] as GPOffPageLink).gpAttrs.get("signal_type", ""),
		"4-20mA", "the contract snapshot carries the signal type")


# Undo removes EXACTLY the four things; redo re-adds the SAME ids and tag.
# 撤销精确移除那四样东西；重做原样加回**同样的** id 与编号。
func gpTestUndoRedoRoundTrip() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpCmd: GPCrossSheetCreateCommand = _gpCreate(gpRig)
	var gpStack: GPCommandStack = GPCommandStack.new()
	gpStack.gpDo(gpCmd, gpRig["ctx"])
	var gpLinkBefore: GPOffPageLink = gpRig["links"][0]
	var gpTagBefore: String = gpLinkBefore.gpTag
	var gpLinkIdBefore: String = gpLinkBefore.gpInstanceId
	gpStack.gpUndo(gpRig["ctx"])
	gpEq(gpRig["links"].size(), 0, "undo removes the link from the container")
	gpEq((gpRig["local"] as GPPIDGraph).gpNodes.size(), 1,
		"undo leaves only the original source node on the local sheet")
	gpEq((gpRig["local"] as GPPIDGraph).gpEdges.size(), 0, "undo removes the edge")
	gpEq((gpRig["peer"] as GPPIDGraph).gpNodes.size(), 0, "undo removes the twin")
	gpStack.gpRedo(gpRig["ctx"])
	var gpLinkAfter: GPOffPageLink = gpRig["links"][0]
	gpCheck(gpLinkAfter == gpLinkBefore,
		"redo re-adds the SAME link object (no renumbering, no re-minting)")
	gpEq(gpLinkAfter.gpInstanceId, gpLinkIdBefore, "the link id survives undo+redo")
	gpEq(gpLinkAfter.gpTag, gpTagBefore, "the tag survives undo+redo")
	gpEq((gpRig["local"] as GPPIDGraph).gpEdges.size(), 1, "the edge is back")


# The link id is unique INSIDE the container even when another sheet's counter has already
# minted the same "xlink-N".
# 即便另一张图纸的计数器已铸出相同的 "xlink-N"，link id 在容器内仍唯一。
func gpTestLinkIdIsUniqueInsideContainer() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpSquatter: GPOffPageLink = GPOffPageLink.new()
	gpSquatter.gpInstanceId = "xlink-1"
	gpRig["links"].append(gpSquatter)
	var gpCmd: GPCrossSheetCreateCommand = _gpCreate(gpRig)
	gpCheck(gpCmd.gpCreatedLinkId != "xlink-1",
		"the mint skips an id the container already holds")
	var gpSeen: Dictionary = {}
	for gpL in gpRig["links"]:
		gpCheck(not gpSeen.has(gpL.gpInstanceId), "no duplicate link id in the container")
		gpSeen[gpL.gpInstanceId] = true


# The refusals leave NOTHING behind — no connector, no edge, no link, no twin.
# 被拒时**什么都不留** —— 无连接符、无边、无 link、无孪生体。
func gpTestRefusalsLeaveNothingBehind() -> void:
	# Same sheet. / 同一张图。
	var gpRig: Dictionary = _gpRig()
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "n1", "port_id": "out"}, GPPIDEdge.GP_PROCESS, "", Vector2.ZERO,
		Vector2.ZERO, "sheet-1", "sheet-1", "7", gpRig["peer"], gpRig["links"])
	gpCheck(not gpCmd.gpExecute(gpRig["ctx"]), "a same-sheet link is refused")
	gpEq(gpCmd.gpRefusal, "same_sheet", "the refusal names the reason")
	gpEq(gpRig["links"].size(), 0, "no link was recorded")
	# A dangling drop with no bound end. / 无绑定端的悬空落点。
	var gpRig2: Dictionary = _gpRig()
	var gpCmd2: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "", "port_id": "", "point": [1.0, 2.0]}, GPPIDEdge.GP_PROCESS, "",
		Vector2.ZERO, Vector2.ZERO, "sheet-1", "sheet-2", "7",
		gpRig2["peer"], gpRig2["links"])
	gpCheck(not gpCmd2.gpExecute(gpRig2["ctx"]), "an unbound source is refused")
	gpEq(gpCmd2.gpRefusal, "pipe_needs_one_bound", "the refusal names the reason")
	gpEq((gpRig2["local"] as GPPIDGraph).gpNodes.size(), 1,
		"the local sheet still has only the source node")
	gpEq((gpRig2["peer"] as GPPIDGraph).gpNodes.size(), 0, "no twin was created")
	# A source node that does not exist. / 不存在的源节点。
	var gpRig3: Dictionary = _gpRig()
	var gpCmd3: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "ghost", "port_id": "out"}, GPPIDEdge.GP_PROCESS, "", Vector2.ZERO,
		Vector2.ZERO, "sheet-1", "sheet-2", "7", gpRig3["peer"], gpRig3["links"])
	gpCheck(not gpCmd3.gpExecute(gpRig3["ctx"]), "a missing source node is refused")
	gpEq(gpCmd3.gpRefusal, "node_missing", "the refusal names the reason")
	gpEq(gpRig3["links"].size(), 0, "no link was recorded")


# ---- served twin + inherited contract (user feedback 2026-11-03) ----
# ---- 服务孪生体 + 继承契约（用户反馈 2026-11-03）----

# The dialog picked a real item on the peer sheet: the twin is minted UNFLIPPED (reading
# left-to-right, user feedback 2026-11-03 second round), the edge twin -> item leaves from the
# "cont" port on the PEER graph, and the link's B end is the TWIN (never the item) — the
# connector is a free top-level flag in the left column, never a child of the item.
# 对话框在对端图上选定了真实对象：孪生体以**不翻转**态铸出（读向从左到右，用户反馈
# 2026-11-03 第二轮）、「孪生体 -> 对象」的边从 "cont" 端口出发画在**对端图**上、
# link 的 B 端是**孪生体**（绝不是对象）—— 连接符是左列里自由的顶层旗标，绝不是对象的子件。
func gpTestServedTwinConnectsToTheItem() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpPeer: GPPIDGraph = gpRig["peer"]
	var gpVessel: GPPIDNode = gpPeer.gpNewNode("v-1", "LTANK001", "T-101",
		Vector2(400, 300), {})
	gpPeer.gpAddNode(gpVessel)
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "n1", "port_id": "out"}, GPPIDEdge.GP_PROCESS, "", Vector2(30, 40),
		Vector2(50, 60), "sheet-1", "sheet-2", "7", gpPeer, gpRig["links"], true, "",
		{}, {"node_id": "v-1", "port_id": "p1"})
	gpCheck(gpCmd.gpExecute(gpRig["ctx"]), "the served gesture is accepted")
	var gpTwin: GPPIDNode = null
	for gpN in gpPeer.gpNodes:
		if gpN.gpSymbolId == GP_ID_PIPE:
			gpTwin = gpN
	gpCheck(gpTwin != null, "the twin exists on the peer sheet")
	gpCheck(not gpTwin.gpFlipped,
		"the twin is UNFLIPPED: the pennant reads left-to-right, pointing at the item")
	gpEq(gpPeer.gpEdges.size(), 1, "the peer sheet carries the twin -> item edge")
	var gpPE: GPPIDEdge = gpPeer.gpEdges[0]
	gpEq(str(gpPE.gpFromRef.get("node_id", "")), gpTwin.gpInstanceId,
		"the edge starts at the twin")
	gpEq(str(gpPE.gpFromRef.get("port_id", "")), GPSymbolPackOffpage.GP_PORT_CONT,
		"the edge leaves from the continuation port (the adaptive body's tip)")
	gpEq(str(gpPE.gpToRef.get("node_id", "")), "v-1", "the edge lands on the served item")
	var gpLink: GPOffPageLink = gpRig["links"][0]
	gpEq(str(gpLink.gpB.get("node_id", "")), gpTwin.gpInstanceId,
		"the link's B end is the TWIN, not the served item")
	gpEq(str(gpLink.gpB.get("port_id", "")), GPSymbolPackOffpage.GP_PORT_CONT,
		"the link's B port names the continuation side too")
	gpEq(gpTwin.gpParentUid, "", "the twin is a free top-level symbol, never mounted")
	# Undo takes the peer edge with it; redo brings the SAME shape back.
	# 撤销连带移除对端边；重做原样恢复。
	var gpStack: GPCommandStack = GPCommandStack.new()
	gpStack.gpDo(gpCmd, gpRig["ctx"])
	gpStack.gpUndo(gpRig["ctx"])
	gpEq(gpPeer.gpEdges.size(), 0, "undo removes the peer edge too")
	gpEq(gpPeer.gpNodes.size(), 1, "undo removes the twin (the served vessel stays)")
	gpStack.gpRedo(gpRig["ctx"])
	gpEq(gpPeer.gpEdges.size(), 1, "redo restores the peer edge")
	gpEq(gpPeer.gpNodes.size(), 2, "redo restores the twin beside the vessel")


# The contract snapshot is INHERITED from the source line: a mode B connector already
# terminated by a line carrying a medium seeds the link's snapshot at creation.
# 契约快照从**源管线继承**：模式 B 的连接符已被一根带介质的管线终结，创建时即为 link
# 快照播种。
func gpTestMediumInheritsFromSourceLine() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpLocal: GPPIDGraph = gpRig["local"]
	var gpConn: GPPIDNode = gpLocal.gpNewNode("c-1", GP_ID_PIPE, "", Vector2(20, 20), {})
	gpLocal.gpAddNode(gpConn)
	var gpLine: GPPIDEdge = gpLocal.gpNewEdge("e-0", "n1", "c-1")
	gpLocal.gpAddEdge(gpLine)
	gpLine.gpAttrs["medium"] = "NAOH 32%"
	var gpPeer: GPPIDGraph = gpRig["peer"]
	var gpVessel: GPPIDNode = gpPeer.gpNewNode("v-1", "LTANK001", "T-101",
		Vector2(400, 300), {})
	gpPeer.gpAddNode(gpVessel)
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "c-1", "port_id": "ref"}, GPPIDEdge.GP_PROCESS, "", Vector2.ZERO,
		Vector2(50, 60), "sheet-1", "sheet-2", "7", gpPeer, gpRig["links"], true, "c-1",
		{}, {"node_id": "v-1", "port_id": "p1"})
	gpCheck(gpCmd.gpExecute(gpRig["ctx"]), "the mode B served gesture is accepted")
	gpEq(str((gpRig["links"][0] as GPOffPageLink).gpAttrs.get("medium", "")),
		"NAOH 32%", "the medium is inherited from the source line, not hand-typed")


# A served ref that names a GHOST node is refused with NOTHING created on either sheet.
# 指向**幽灵**节点的服务对象被拒，两张图上什么都不建。
func gpTestServedGhostRefusesCleanly() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "n1", "port_id": "out"}, GPPIDEdge.GP_PROCESS, "", Vector2.ZERO,
		Vector2.ZERO, "sheet-1", "sheet-2", "7", gpRig["peer"], gpRig["links"], true, "",
		{}, {"node_id": "ghost", "port_id": "p1"})
	gpCheck(not gpCmd.gpExecute(gpRig["ctx"]), "a ghost served item is refused")
	gpEq(gpCmd.gpRefusal, "node_missing", "the refusal names the reason")
	gpEq(gpRig["links"].size(), 0, "no link was recorded")
	gpEq((gpRig["local"] as GPPIDGraph).gpEdges.size(), 0,
		"the local edge was rolled back too")
	gpEq((gpRig["local"] as GPPIDGraph).gpNodes.size(), 1,
		"the local sheet still has only the source node")
	gpEq((gpRig["peer"] as GPPIDGraph).gpNodes.size(), 0, "no twin was created")


# The LEFT connector column (user feedback 2026-11-03): an empty column starts top-left;
# the next slot stacks BELOW the lowest connector already in the column; a flag parked far
# right never dictates the stacking.
# **左列**（用户反馈 2026-11-03）：空列从左上起排；下一槽位摞在列中**最低**者之下；
# 停在远端的旗标不参与堆叠。
func gpTestLeftColumnStacksTopDown() -> void:
	var gpFrame: Rect2 = Rect2(0, 0, 841, 594)
	var gpEnv: Vector2 = Vector2(96, 10)
	var gpIds: Array[String] = [GP_ID_PIPE, GP_ID_SIGNAL]
	var gpFirst: Vector2 = GPOffPageIndex.gpNextLeftSlot(null, gpFrame, gpEnv, gpIds)
	gpCheck(gpFirst.x < gpEnv.x * 2.0, "the column hugs the frame's left edge")
	gpCheck(gpFirst.y < gpEnv.y * 3.0, "an empty column starts near the top")
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("c1", GP_ID_PIPE, "", Vector2(gpFirst.x, gpFirst.y), {}))
	gpG.gpAddNode(gpG.gpNewNode("c2", GP_ID_PIPE, "", Vector2(700, 100), {}))
	var gpNext: Vector2 = GPOffPageIndex.gpNextLeftSlot(gpG, gpFrame, gpEnv, gpIds)
	gpCheck(gpNext.y > gpFirst.y + gpEnv.y * 2.0,
		"the next slot sits below the lowest column member")
	gpCheck(absf(gpNext.x - gpFirst.x) < 0.001, "the column keeps its x")
	gpCheck(absf(gpNext.y - (gpFirst.y + gpEnv.y * 3.0)) < 0.001,
		"the pitch is exactly 3 envelope heights")


# ---- sync to peer ----
# ---- 同步到对端 ----

func _gpSyncRig() -> Dictionary:
	var gpRig: Dictionary = _gpRig()
	var gpCmd: GPCrossSheetCreateCommand = _gpCreate(gpRig)
	var gpLink: GPOffPageLink = gpRig["links"][0]
	var gpLocalEdge: GPPIDEdge = (gpRig["local"] as GPPIDGraph).gpEdges[0]
	var gpEdges: Array[GPPIDEdge] = [gpLocalEdge]
	gpRig["create"] = gpCmd
	gpRig["link"] = gpLink
	gpRig["edges"] = gpEdges
	return gpRig


# "Yes, sync" writes the values into the snapshot AND both ends, and undo restores
# the exact prior state (including an attr the edge never had).
# 「是，同步」把值写进快照**并**写入两端；撤销恢复到精确的原状态（包括边原本没有的属性）。
func gpTestSyncWritesSnapshotAndEdgesAndUndoRestores() -> void:
	var gpRig: Dictionary = _gpSyncRig()
	var gpLink: GPOffPageLink = gpRig["link"]
	var gpEdge: GPPIDEdge = gpRig["edges"][0]
	var gpCmd: GPCrossSheetSyncCommand = GPCrossSheetSyncCommand.new(gpLink,
		{"dn": "50", "spec": "CS150"}, gpRig["edges"])
	gpCheck(gpCmd.gpExecute(gpRig["ctx"]), "a contract sync is accepted")
	gpEq(gpLink.gpAttrs.get("dn", ""), "50", "the snapshot carries the new dn")
	gpEq(gpLink.gpAttrs.get("spec", ""), "CS150", "the snapshot carries the new spec")
	gpEq(gpEdge.gpAttrs.get("dn", ""), "50", "the local edge follows the contract")
	var gpStack: GPCommandStack = GPCommandStack.new()
	gpStack.gpDo(gpCmd, gpRig["ctx"])
	gpStack.gpUndo(gpRig["ctx"])
	gpCheck(not (gpEdge.gpAttrs as Dictionary).has("dn"),
		"undo restores an attr the edge did not have to ABSENT, not empty")
	gpCheck(not (gpLink.gpAttrs as Dictionary).has("dn"),
		"undo restores the snapshot the same way")


# A sync never smuggles non-contract keys anywhere.
# 同步绝不为非契约键开绿灯。
func gpTestSyncIgnoresNonContractKeys() -> void:
	var gpRig: Dictionary = _gpSyncRig()
	var gpLink: GPOffPageLink = gpRig["link"]
	var gpEdge: GPPIDEdge = gpRig["edges"][0]
	var gpCmd: GPCrossSheetSyncCommand = GPCrossSheetSyncCommand.new(gpLink,
		{"colour": "red", "dn": "80"}, gpRig["edges"])
	gpCmd.gpExecute(gpRig["ctx"])
	gpEq(gpLink.gpAttrs.get("dn", ""), "80", "a contract key still applies")
	gpCheck(not (gpLink.gpAttrs as Dictionary).has("colour"),
		"a non-contract key never reaches the snapshot")
	gpCheck(not (gpEdge.gpAttrs as Dictionary).has("colour"),
		"a non-contract key never reaches the edge")


# A request with no contract values is refused and records no undo step.
# 不含契约值的请求被拒绝，且不记录撤销步。
func gpTestSyncRefusesWithoutContractValues() -> void:
	var gpRig: Dictionary = _gpSyncRig()
	var gpCmd: GPCrossSheetSyncCommand = GPCrossSheetSyncCommand.new(gpRig["link"],
		{"colour": "red"}, gpRig["edges"])
	gpCheck(not gpCmd.gpExecute(gpRig["ctx"]), "a non-contract-only request is refused")
	gpEq(gpCmd.gpRefusal, "no_contract_values", "the refusal names the reason")
	gpEq((gpRig["link"] as GPOffPageLink).gpAttrs.size(), 0,
		"a refused sync changes the snapshot for nothing")
	var gpStack: GPCommandStack = GPCommandStack.new()
	gpCheck(not gpStack.gpDo(gpCmd, gpRig["ctx"]),
		"the stack refuses to record a step that changes nothing")


# ---- P0-D03: dirty marking (notify) ----
# ---- P0-D03：脏标记（notify）----

# Execute notifies EVERY touched graph exactly ONCE; undo does the same (B3: an undo that
# leaves the document "unmodified" loses the restore silently at close).
# 执行给每张触及的图恰好**一次** notify；撤销同样（B3：撤销后文档若仍「未修改」，
# 关闭时恢复会静默丢失）。
func gpTestSyncNotifiesBothGraphsOnExecuteAndUndo() -> void:
	var gpRig: Dictionary = _gpSyncRig()
	var gpLink: GPOffPageLink = gpRig["link"]
	var gpLocal: GPPIDGraph = gpRig["local"]
	var gpPeer: GPPIDGraph = gpRig["peer"]
	# Lambdas capture locals BY VALUE — count through arrays (reference semantics).
	# Lambda 对局部变量按**值**捕获 —— 用数组（引用语义）计数。
	var gpHits: Array[int] = [0, 0]
	gpLocal.gpGraphChanged.connect(func() -> void: gpHits[0] += 1)
	gpPeer.gpGraphChanged.connect(func() -> void: gpHits[1] += 1)
	var gpGraphs: Array[GPPIDGraph] = [gpLocal, gpPeer]
	var gpCmd: GPCrossSheetSyncCommand = GPCrossSheetSyncCommand.new(gpLink,
		{"dn": "80"}, gpRig["edges"], gpGraphs)
	gpCheck(gpCmd.gpExecute(gpRig["ctx"]), "the sync executes")
	gpEq(gpHits[0], 1, "execute notifies the LOCAL graph exactly once")
	gpEq(gpHits[1], 1, "execute notifies the PEER graph exactly once (D03)")
	gpCmd.gpUndo(gpRig["ctx"])
	gpEq(gpHits[0], 2, "undo notifies the local graph too (B3)")
	gpEq(gpHits[1], 2, "undo notifies the peer graph too (B3)")


# A graph left out of the gpGraphs list is NOT notified: the list is the whole contract.
# 未列入 gpGraphs 的图**不会**被通知：这张名单就是完整契约。
func gpTestSyncNotifiesOnlyTheListedGraphs() -> void:
	var gpRig: Dictionary = _gpSyncRig()
	var gpHits: Array[int] = [0]
	var gpPeer: GPPIDGraph = gpRig["peer"]
	gpPeer.gpGraphChanged.connect(func() -> void: gpHits[0] += 1)
	var gpGraphs: Array[GPPIDGraph] = [gpRig["local"]]
	var gpCmd: GPCrossSheetSyncCommand = GPCrossSheetSyncCommand.new(gpRig["link"],
		{"dn": "80"}, gpRig["edges"], gpGraphs)
	gpCheck(gpCmd.gpExecute(gpRig["ctx"]), "the sync executes")
	gpEq(gpHits[0], 0, "a graph outside the list hears nothing")


# ---- P0-D24: refusal keys are localized ----
# ---- P0-D24：拒绝键已本地化 ----

# Every cross-sheet refusal key has an offpage.refuse_* entry with BOTH zh and en — a
# missing entry used to show the raw key (e.g. "edge.same_sheet") in the status bar.
# 每个跨图纸拒绝键都有**中英双语**的 offpage.refuse_* 条目 —— 缺条目曾使状态栏显示裸键
#（如「edge.same_sheet」）。
func gpTestRefusalKeysAreLocalized() -> void:
	var gpKeys: Array[String] = ["same_sheet", "connector_already_linked", "sheet_missing",
		"node_missing", "peer_graph_missing", "links_missing", "no_contract_values",
		"pipe_needs_one_bound"]
	var gpStrings: Dictionary = (load("res://src/autoload/i18n.gd") as GDScript).GP_STRINGS
	for gpKey in gpKeys:
		var gpFull: String = "offpage.refuse_%s" % gpKey
		gpCheck(gpStrings.has(gpFull), "refusal key %s exists in the i18n table" % gpFull)
		if gpStrings.has(gpFull):
			var gpEntry: Dictionary = gpStrings[gpFull] as Dictionary
			gpCheck(str(gpEntry.get("zh", "")) != "", "%s has a zh string" % gpFull)
			gpCheck(str(gpEntry.get("en", "")) != "", "%s has an en string" % gpFull)


# A missing link and null edge entries are tolerated, not crashes.
# 缺 link 与 null 边条目被容忍，而非崩溃。
func gpTestSyncToleratesMissingPieces() -> void:
	var gpCmd: GPCrossSheetSyncCommand = GPCrossSheetSyncCommand.new(null, {"dn": "50"})
	gpCheck(not gpCmd.gpExecute(null), "a missing link is refused")
	gpEq(gpCmd.gpRefusal, "link_missing", "the refusal names the reason")
	var gpRig: Dictionary = _gpSyncRig()
	var gpEdges: Array[GPPIDEdge] = [null, gpRig["edges"][0], null]
	var gpCmd2: GPCrossSheetSyncCommand = GPCrossSheetSyncCommand.new(gpRig["link"],
		{"dn": "50"}, gpEdges)
	gpCheck(gpCmd2.gpExecute(gpRig["ctx"]),
		"null edge entries are skipped, the real edge still syncs")
	gpEq((gpRig["edges"][0] as GPPIDEdge).gpAttrs.get("dn", ""), "50",
		"the surviving edge carries the value")


# Two undos in a row must not lose data: re-executing must NOT re-capture the priors
# from its own output.
# 连撤两次不得丢数据：再执行**不得**用自身输出重捕获原值。
func gpTestSyncPriorsSurviveRedo() -> void:
	var gpRig: Dictionary = _gpSyncRig()
	var gpLink: GPOffPageLink = gpRig["link"]
	var gpEdge: GPPIDEdge = gpRig["edges"][0]
	var gpCmd: GPCrossSheetSyncCommand = GPCrossSheetSyncCommand.new(gpLink,
		{"dn": "50"}, gpRig["edges"])
	var gpStack: GPCommandStack = GPCommandStack.new()
	gpStack.gpDo(gpCmd, gpRig["ctx"])
	gpStack.gpUndo(gpRig["ctx"])
	gpStack.gpRedo(gpRig["ctx"])
	gpStack.gpUndo(gpRig["ctx"])
	gpCheck(not (gpEdge.gpAttrs as Dictionary).has("dn"),
		"after do/undo/redo/undo the edge is back to its true prior state")
	gpCheck(not (gpLink.gpAttrs as Dictionary).has("dn"),
		"the snapshot is likewise restored")


# ---- mode B: existing objects on both ends ----
# ---- 模式 B：两端皆用既有对象 ----

# An existing local connector + an existing peer item: ONLY the link is created, the
# connector's props get stamped, and undo restores the props to ABSENT.
# 本端既有连接符 + 对端既有对象：**只**创建 link，连接符 props 被盖章，
# 撤销把 props 还原到「无此键」。
func gpTestModeBLinksExistingEndsOnly() -> void:
	var gpRig: Dictionary = _gpRig()
	# An existing, UNLINKED connector on the local sheet.
	# 本端图纸上一只**未连接**的既有连接符。
	var gpConn: GPPIDNode = (gpRig["local"] as GPPIDGraph).gpNewNode("c1", GP_ID_PIPE,
		"", Vector2(200, 200), {})
	(gpRig["local"] as GPPIDGraph).gpAddNode(gpConn)
	# An existing item on the peer sheet (an equipment port, not a connector).
	# 对端图纸上的既有对象（设备端口，非连接符）。
	var gpPeerItem: GPPIDNode = (gpRig["peer"] as GPPIDGraph).gpNewNode("p1", "TANK001",
		"T-101", Vector2(50, 50), {})
	(gpRig["peer"] as GPPIDGraph).gpAddNode(gpPeerItem)
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{}, GPPIDEdge.GP_PROCESS, "", Vector2.ZERO, Vector2.ZERO,
		"sheet-1", "sheet-2", "7", gpRig["peer"], gpRig["links"], true, "c1",
		{"node_id": "p1", "port_id": "in"})
	gpCheck(gpCmd.gpExecute(gpRig["ctx"]), "mode B is accepted")
	gpEq((gpRig["local"] as GPPIDGraph).gpNodes.size(), 2,
		"no node was created on the local sheet")
	gpEq((gpRig["local"] as GPPIDGraph).gpEdges.size(), 0, "no edge was created")
	gpEq((gpRig["peer"] as GPPIDGraph).gpNodes.size(), 1, "no twin was minted")
	gpEq(gpRig["links"].size(), 1, "exactly one link exists")
	var gpLink: GPOffPageLink = gpRig["links"][0]
	gpEq(str(gpLink.gpA.get("node_id", "")), "c1", "endpoint A is the existing connector")
	gpEq(str(gpLink.gpB.get("node_id", "")), "p1", "endpoint B is the existing item")
	gpEq(str(gpLink.gpB.get("port_id", "")), "in", "endpoint B keeps the chosen port")
	gpEq(str(gpConn.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")), gpLink.gpInstanceId,
		"the existing connector now carries the link id")
	# Undo restores the props to ABSENT and leaves both existing nodes alive.
	# 撤销把 props 还原到「无此键」，且两个既有节点都健在。
	var gpStack: GPCommandStack = GPCommandStack.new()
	gpStack.gpDo(gpCmd, gpRig["ctx"])
	gpStack.gpUndo(gpRig["ctx"])
	gpEq(gpRig["links"].size(), 0, "undo removes the link")
	gpCheck(not (gpConn.gpProps as Dictionary).has(GPOffPageLink.GP_KEY_LINK_ID),
		"undo un-stamps the connector (the key existed neither before nor after)")
	gpEq((gpRig["local"] as GPPIDGraph).gpNodes.size(), 2,
		"undo does NOT delete the existing connector")
	gpEq((gpRig["peer"] as GPPIDGraph).gpNodes.size(), 1,
		"undo does NOT delete the existing peer item")
	gpStack.gpRedo(gpRig["ctx"])
	gpEq(str(gpConn.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")),
		(gpRig["links"][0] as GPOffPageLink).gpInstanceId,
		"redo re-stamps the SAME link id")


# A connector that already carries a LIVE link must not be linked again — the old link
# would be orphaned by the new stamp.
# 已挂着**存活** link 的连接符不得再连 —— 新盖章会让旧 link 变孤儿。
func gpTestModeBRefusesAlreadyLinkedConnector() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpConn: GPPIDNode = (gpRig["local"] as GPPIDGraph).gpNewNode("c1", GP_ID_PIPE,
		"", Vector2.ZERO, {GPOffPageLink.GP_KEY_LINK_ID: "xlink-9"})
	(gpRig["local"] as GPPIDGraph).gpAddNode(gpConn)
	var gpSquatter: GPOffPageLink = GPOffPageLink.new()
	gpSquatter.gpInstanceId = "xlink-9"
	gpRig["links"].append(gpSquatter)
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{}, GPPIDEdge.GP_PROCESS, "", Vector2.ZERO, Vector2.ZERO,
		"sheet-1", "sheet-2", "7", gpRig["peer"], gpRig["links"], true, "c1", {})
	gpCheck(not gpCmd.gpExecute(gpRig["ctx"]),
		"an already-linked connector is refused")
	gpEq(gpCmd.gpRefusal, "connector_already_linked", "the refusal names the reason")
	gpEq(gpRig["links"].size(), 1, "no second link was recorded")
	gpEq(str(gpConn.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, "")), "xlink-9",
		"the old stamp is untouched")


# An existing PEER connector gets stamped too (it displays the reference); an ordinary
# peer item does not.
# 对端**既有连接符**同样被盖章（它要显示对端编号）；对端普通对象不会。
func gpTestModeBStampsPeerConnectorOnly() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpConn: GPPIDNode = (gpRig["local"] as GPPIDGraph).gpNewNode("c1", GP_ID_PIPE,
		"", Vector2.ZERO, {})
	(gpRig["local"] as GPPIDGraph).gpAddNode(gpConn)
	# The peer end is ANOTHER connector.
	# 对端是**另一只**连接符。
	var gpPeerConn: GPPIDNode = (gpRig["peer"] as GPPIDGraph).gpNewNode("c2", GP_ID_PIPE,
		"", Vector2(10, 10), {})
	(gpRig["peer"] as GPPIDGraph).gpAddNode(gpPeerConn)
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{}, GPPIDEdge.GP_PROCESS, "", Vector2.ZERO, Vector2.ZERO,
		"sheet-1", "sheet-2", "7", gpRig["peer"], gpRig["links"], true, "c1",
		{"node_id": "c2", "port_id": "ref"})
	gpCmd.gpExecute(gpRig["ctx"])
	gpCheck((gpPeerConn.gpProps as Dictionary).has(GPOffPageLink.GP_KEY_LINK_ID),
		"the peer connector is stamped and will display the reference")
	var gpStack: GPCommandStack = GPCommandStack.new()
	gpStack.gpDo(gpCmd, gpRig["ctx"])
	gpStack.gpUndo(gpRig["ctx"])
	gpCheck(not (gpPeerConn.gpProps as Dictionary).has(GPOffPageLink.GP_KEY_LINK_ID),
		"undo un-stamps the peer connector as well")


# ---- delete cascade (S4 case ①) ----
# ---- 删除级联（S4 情形①）----

# Deleting a connector removes the WHOLE connection — link, both connectors, the touching
# edge — and the round trip restores all of it in reverse.
# 删除连接符移除**整条**连接 —— link、两端连接符、其上的边 —— 且往返按逆序全部还原。
func gpTestDeleteCascadesAndRoundTrips() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpCmd: GPCrossSheetCreateCommand = _gpCreate(gpRig)
	var gpLinks: Array[GPOffPageLink] = gpRig["links"]
	var gpLink: GPOffPageLink = gpLinks[0]
	var gpLocalId: String = str(gpLink.gpA.get(GPOffPageLink.GP_KEY_NODE, ""))
	var gpPeerId: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
	var gpLocalGraph: GPPIDGraph = gpRig["local"] as GPPIDGraph
	var gpPeerGraph: GPPIDGraph = gpRig["peer"] as GPPIDGraph
	var gpEdgesBefore: int = gpLocalGraph.gpEdges.size()
	var gpDel: GPCrossSheetDeleteCommand = GPCrossSheetDeleteCommand.new(gpLink,
		[gpLocalId], [gpPeerId], gpPeerGraph, gpLinks)
	gpCheck(gpDel.gpExecute(gpRig["ctx"]), "the cascade executes")
	gpEq(gpLinks.size(), 0, "the link left the container table")
	gpCheck(gpLocalGraph.gpGetNode(gpLocalId) == null, "the local connector is gone")
	gpCheck(gpPeerGraph.gpGetNode(gpPeerId) == null, "the PEER connector is gone too")
	gpCheck(gpLocalGraph.gpEdges.size() < gpEdgesBefore,
		"the edge into the local connector went with it")
	# Undo: reverse order — both halves first, then the link back at its old index.
	# 撤销：逆序 —— 先两半节点，link 回到原下标。
	gpDel.gpUndo(gpRig["ctx"])
	gpEq(gpLinks.size(), 1, "undo puts the link back")
	gpCheck(gpLinks[0] == gpLink, "the SAME link object returns (uid stability)")
	gpCheck(gpLocalGraph.gpGetNode(gpLocalId) != null, "the local connector returns")
	gpCheck(gpPeerGraph.gpGetNode(gpPeerId) != null, "the peer connector returns")
	gpEq(gpLocalGraph.gpEdges.size(), gpEdgesBefore, "the edge returns with it")
	# Redo deletes again. / 重做再删一遍。
	gpDel.gpRedo(gpRig["ctx"])
	gpEq(gpLinks.size(), 0, "redo removes the link again")
	gpCheck(gpLocalGraph.gpGetNode(gpLocalId) == null, "redo removes the local connector")
	gpCheck(gpPeerGraph.gpGetNode(gpPeerId) == null, "redo removes the peer connector")


# A link already removed from the table cannot be deleted twice (the redo-race guard).
# 已不在表中的 link 不能再删一次（重做竞态守卫）。
func gpTestDeleteRefusesAMissingLink() -> void:
	var gpRig: Dictionary = _gpRig()
	_gpCreate(gpRig)
	var gpLinks: Array[GPOffPageLink] = gpRig["links"]
	var gpLink: GPOffPageLink = gpLinks[0]
	var gpPeerId: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
	var gpDel: GPCrossSheetDeleteCommand = GPCrossSheetDeleteCommand.new(gpLink, [],
		[gpPeerId], gpRig["peer"] as GPPIDGraph, gpLinks)
	gpLinks.erase(gpLink)
	gpCheck(not gpDel.gpExecute(gpRig["ctx"]),
		"a link that is no longer in the table refuses to cascade")
	gpCheck((gpRig["peer"] as GPPIDGraph).gpGetNode(gpPeerId) != null,
		"and the peer connector is untouched")
