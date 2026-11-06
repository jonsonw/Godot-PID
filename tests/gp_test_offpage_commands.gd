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

# D19: the source line is PORT-DIRECTED — the inbound "ref" edge is the source even when a
# "cont" edge sits EARLIER in the array (the old "first touching edge" rule would have
# inherited from the wrong line on a Y-connected connector).
# D19：源管线**按端口定向** —— 即使 cont 口边在数组里**更靠前**，入站 ref 边才是源
#（旧的「第一条触及边」规则会让 Y 形接法的连接符从错误的线上继承）。
func gpTestSourceEdgeIsPortDirected() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpLocal: GPPIDGraph = gpRig["local"]
	var gpConn: GPPIDNode = gpLocal.gpNewNode("c-1", GP_ID_PIPE, "", Vector2(20, 20), {})
	gpLocal.gpAddNode(gpConn)
	# The WRONG source first: a continuation-port edge, earliest in the array.
	# 错误的源在前：cont 口边，数组最早。
	var gpCont: GPPIDEdge = gpLocal.gpNewEdgeEx("e-c",
		{"node_id": "c-1", "port_id": "cont"}, {"node_id": "nX", "port_id": "p1"},
		GPPIDEdge.GP_PROCESS, "", "")
	gpLocal.gpAddEdge(gpCont)
	gpCont.gpAttrs["medium"] = "WRONG-SOURCE"
	# The RIGHT source second: the inbound ref edge.
	# 正确的源在后：入站 ref 边。
	var gpRef: GPPIDEdge = gpLocal.gpNewEdgeEx("e-r",
		{"node_id": "n1", "port_id": "p1"}, {"node_id": "c-1", "port_id": "ref"},
		GPPIDEdge.GP_PROCESS, "", "")
	gpLocal.gpAddEdge(gpRef)
	gpRef.gpAttrs["medium"] = "NAOH 32%"
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
		"NAOH 32%", "the REF-port edge is the source regardless of array order / "
		+ "不论数组顺序，ref 口边才是源")


# The peer continuation edge INHERITS the source line's number (user feedback 2026-11-04):
# mode B inherits the existing pipeline's tag; mode A inherits the tag the command itself
# just minted on the local sheet. Same number on another sheet is the legitimate
# continuation (ADR-36 D1).
# 对端延续边**继承**源管线编号（用户反馈 2026-11-04）：模式 B 继承既有管线的号；模式 A
# 继承命令刚在本图纸铸出的号。同号跨图是合法的延续（ADR-36 D1）。
func gpTestPeerEdgeInheritsSourceTag() -> void:
	# Mode B: the connector is already terminated by line e-0 carrying the number.
	# 模式 B：连接符已被带号的管线 e-0 终结。
	var gpRig: Dictionary = _gpRig()
	var gpLocal: GPPIDGraph = gpRig["local"]
	var gpConn: GPPIDNode = gpLocal.gpNewNode("c-1", GP_ID_PIPE, "", Vector2(20, 20), {})
	gpLocal.gpAddNode(gpConn)
	var gpLine: GPPIDEdge = gpLocal.gpNewEdge("e-0", "n1", "c-1")
	gpLocal.gpAddEdge(gpLine)
	gpLine.gpTag = "0101-PL-050-B1F-N"
	var gpPeer: GPPIDGraph = gpRig["peer"]
	var gpVessel: GPPIDNode = gpPeer.gpNewNode("v-1", "LTANK001", "T-101",
		Vector2(400, 300), {})
	gpPeer.gpAddNode(gpVessel)
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "c-1", "port_id": "ref"}, GPPIDEdge.GP_PROCESS, "", Vector2.ZERO,
		Vector2(50, 60), "sheet-1", "sheet-2", "7", gpPeer, gpRig["links"], true, "c-1",
		{}, {"node_id": "v-1", "port_id": "p1"})
	gpCheck(gpCmd.gpExecute(gpRig["ctx"]), "the mode B served gesture is accepted")
	gpEq((gpPeer.gpEdges[0] as GPPIDEdge).gpTag, "0101-PL-050-B1F-N",
		"the peer continuation edge carries the SOURCE line's number, not a minted one")
	# Mode A: nothing pre-exists; the peer inherits the number minted for the local segment.
	# 模式 A：一切尚不存在；对端继承本端段刚铸出的号。
	var gpRig2: Dictionary = _gpRig()
	var gpVessel2: GPPIDNode = (gpRig2["peer"] as GPPIDGraph).gpNewNode("v-1", "LTANK001",
		"T-101", Vector2(400, 300), {})
	(gpRig2["peer"] as GPPIDGraph).gpAddNode(gpVessel2)
	var gpCmd2: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "n1", "port_id": "out"}, GPPIDEdge.GP_PROCESS, "", Vector2(30, 40),
		Vector2(50, 60), "sheet-1", "sheet-2", "7", gpRig2["peer"], gpRig2["links"],
		true, "", {}, {"node_id": "v-1", "port_id": "p1"})
	gpCheck(gpCmd2.gpExecute(gpRig2["ctx"]), "the mode A served gesture is accepted")
	var gpLocalTag: String = ((gpRig2["local"] as GPPIDGraph).gpEdges[0] as GPPIDEdge).gpTag
	gpCheck(gpLocalTag != "", "the local segment minted a number")
	gpEq(((gpRig2["peer"] as GPPIDGraph).gpEdges[0] as GPPIDEdge).gpTag, gpLocalTag,
		"the peer continuation inherits the LOCAL segment's number in mode A too")
	# Undo + redo keep the inherited number (redo re-adds the SAME edge object).
	# 撤销 + 重做保持继承号（重做原样加回**同一个**边对象）。
	var gpStack: GPCommandStack = GPCommandStack.new()
	gpStack.gpDo(gpCmd2, gpRig2["ctx"])
	gpStack.gpUndo(gpRig2["ctx"])
	gpStack.gpRedo(gpRig2["ctx"])
	gpEq(((gpRig2["peer"] as GPPIDGraph).gpEdges[0] as GPPIDEdge).gpTag, gpLocalTag,
		"redo restores the inherited number, never a second mint")


# A preset that is ALREADY taken on the peer sheet falls back to minting — the number
# conflict never blocks the gesture (the DRC reports the duplicate afterwards).
# 预设号已被对端图占用时回落铸号 —— 编号冲突绝不阻塞手势（重复由 DRC 事后报告）。
func gpTestPresetFallsBackWhenTakenOnPeerSheet() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpLocal: GPPIDGraph = gpRig["local"]
	var gpConn: GPPIDNode = gpLocal.gpNewNode("c-1", GP_ID_PIPE, "", Vector2(20, 20), {})
	gpLocal.gpAddNode(gpConn)
	var gpLine: GPPIDEdge = gpLocal.gpNewEdge("e-0", "n1", "c-1")
	gpLocal.gpAddEdge(gpLine)
	gpLine.gpTag = "TAKEN-1"
	# The peer sheet ALREADY has a pipe numbered TAKEN-1.
	# 对端图纸上**已有**一根 TAKEN-1 的管线。
	var gpPeer: GPPIDGraph = gpRig["peer"]
	var gpVessel: GPPIDNode = gpPeer.gpNewNode("v-1", "LTANK001", "T-101",
		Vector2(400, 300), {})
	gpPeer.gpAddNode(gpVessel)
	var gpOccupant: GPPIDEdge = gpPeer.gpNewEdge("e-x", "v-1", "v-1")
	gpPeer.gpAddEdge(gpOccupant)
	gpOccupant.gpTag = "TAKEN-1"
	var gpCmd: GPCrossSheetCreateCommand = GPCrossSheetCreateCommand.new(
		{"node_id": "c-1", "port_id": "ref"}, GPPIDEdge.GP_PROCESS, "", Vector2.ZERO,
		Vector2(50, 60), "sheet-1", "sheet-2", "7", gpPeer, gpRig["links"], true, "c-1",
		{}, {"node_id": "v-1", "port_id": "p1"})
	gpCheck(gpCmd.gpExecute(gpRig["ctx"]), "the gesture is still accepted")
	var gpNewTag: String = (gpPeer.gpEdges[1] as GPPIDEdge).gpTag
	gpCheck(gpNewTag != "TAKEN-1",
		"the new edge did not duplicate a number already on the peer sheet")
	gpCheck(gpNewTag != "", "the fallback minted a number instead")


# A PROPAGATED retag (cross-sheet continuation, user feedback 2026-11-04) changes the number
# but never sets tag_manual — the edge keeps following; a hand edit still flags manual; and
# undo restores the exact prior tag + flag state.
# **传播**改号（跨图纸延续，用户反馈 2026-11-04）改号但**绝不**置 tag_manual —— 边继续
# 跟随；手改仍然打标；撤销精确还原先前的号与标记状态。
func gpTestPropagatedRetagKeepsFollowing() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpLocal: GPPIDGraph = gpRig["local"]
	var gpA: GPPIDNode = gpLocal.gpNewNode("a-1", "LTANK001", "T-1", Vector2.ZERO, {})
	var gpB: GPPIDNode = gpLocal.gpNewNode("b-1", "LTANK001", "T-2", Vector2(90, 0), {})
	gpLocal.gpAddNode(gpA)
	gpLocal.gpAddNode(gpB)
	var gpE: GPPIDEdge = gpLocal.gpNewEdge("e-1", "a-1", "b-1")
	gpLocal.gpAddEdge(gpE)
	gpE.gpTag = "OLD-1"
	var gpCtx: GPCommandContext = gpRig["ctx"]
	var gpStack: GPCommandStack = GPCommandStack.new()
	# Propagated: tag changes, follow flag does NOT appear.
	# 传播：号变了，跟随标记**不**出现。
	var gpCmd: GPSetEdgeTagCommand = GPSetEdgeTagCommand.new("e-1", "NEW-1", true)
	gpCheck(gpStack.gpDo(gpCmd, gpCtx), "the propagated retag commits")
	gpEq(gpE.gpTag, "NEW-1", "the propagated number landed")
	gpCheck(not bool(gpE.gpAttrs.get("tag_manual", false)),
		"a propagated number never sets tag_manual — the edge keeps following")
	gpStack.gpUndo(gpCtx)
	gpEq(gpE.gpTag, "OLD-1", "undo restores the prior number")
	gpCheck(not bool(gpE.gpAttrs.get("tag_manual", false)), "undo restores the flag state")
	# A hand edit on the same edge still flags manual (the opt-out by editing).
	# 同一条边上的手改仍然打标（通过编辑选择退出）。
	var gpCmd2: GPSetEdgeTagCommand = GPSetEdgeTagCommand.new("e-1", "NEW-2")
	gpCheck(gpStack.gpDo(gpCmd2, gpCtx), "the hand retag commits")
	gpCheck(bool(gpE.gpAttrs.get("tag_manual", false)),
		"a hand-typed number still sets tag_manual")
	# A duplicate number on the SAME sheet is refused even when propagated (D1 only
	# legalises cross-sheet repeats).
	# 即使是传播，同图重号仍被拒（D1 只使跨图同号合法）。
	var gpE2: GPPIDEdge = gpLocal.gpNewEdge("e-2", "a-1", "b-1")
	gpLocal.gpAddEdge(gpE2)
	gpE2.gpTag = "NEW-2"
	var gpCmd3: GPSetEdgeTagCommand = GPSetEdgeTagCommand.new("e-1", "NEW-2", true)
	gpCheck(not gpStack.gpDo(gpCmd3, gpCtx),
		"a propagated retag onto a taken on-sheet number is refused")
	gpEq(gpE.gpTag, "NEW-2", "the refused propagation left the number untouched")


# The inherit checkbox rides on GPSetEdgeAttrCommand's "null = clear" contract (user
# feedback 2026-11-04): erasing tag_manual resumes following, undo brings the flag back.
# 继承勾选框搭乘 GPSetEdgeAttrCommand 的「null = 清除」契约（用户反馈 2026-11-04）：
# 删除 tag_manual 即恢复跟随，撤销把标记带回来。
func gpTestAttrEraseResumesFollowing() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpLocal: GPPIDGraph = gpRig["local"]
	var gpA: GPPIDNode = gpLocal.gpNewNode("a-1", "LTANK001", "T-1", Vector2.ZERO, {})
	var gpB: GPPIDNode = gpLocal.gpNewNode("b-1", "LTANK001", "T-2", Vector2(90, 0), {})
	gpLocal.gpAddNode(gpA)
	gpLocal.gpAddNode(gpB)
	var gpE: GPPIDEdge = gpLocal.gpNewEdge("e-1", "a-1", "b-1")
	gpLocal.gpAddEdge(gpE)
	var gpCtx: GPCommandContext = gpRig["ctx"]
	var gpStack: GPCommandStack = GPCommandStack.new()
	# Opt out: tag_manual = true. / 选择退出：tag_manual = true。
	gpCheck(gpStack.gpDo(GPSetEdgeAttrCommand.new("e-1", "tag_manual", true), gpCtx),
		"the opt-out attr edit commits")
	gpCheck(bool(gpE.gpAttrs.get("tag_manual", false)), "the edge is manual now")
	# Opt back in: null erases the key. / 重新加入：null 删除该键。
	gpCheck(gpStack.gpDo(GPSetEdgeAttrCommand.new("e-1", "tag_manual", null), gpCtx),
		"the opt-in erase commits")
	gpCheck(not (gpE.gpAttrs as Dictionary).has("tag_manual"),
		"the key is ERASED, not stored as false")
	# Undo of the erase restores the flag. / 撤销删除恢复标记。
	gpStack.gpUndo(gpCtx)
	gpCheck(bool(gpE.gpAttrs.get("tag_manual", false)), "undo restores the manual flag")
	# Erasing an absent key is a no-op, not a bogus undo entry.
	# 删除不存在的键是无事可做，而非伪造撤销步。
	gpStack.gpUndo(gpCtx) # drop the restored state back — now the key is absent again
	gpCheck(not gpStack.gpDo(GPSetEdgeAttrCommand.new("e-1", "tag_manual", null), gpCtx),
		"erasing an absent key reports no change")
	gpCheck(not (gpE.gpAttrs as Dictionary).has("tag_manual"), "the key stays absent")


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
	# D16: the member test is the CATEGORY predicate now (a def lookup callable in the shell;
	# here the default library's own defs), so a custom/derived connector stacks as well.
	# D16：成员判定改走**类别**判谓（外壳里是 def 查找 Callable；此处用默认符号库的 def），
	# 自定义/派生连接符同样参与堆叠。
	var gpDefs: Array[GPSymbolDef] = GPSymbolLibrary.gpDefaultDefs()
	var gpLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		for gpD in gpDefs:
			if gpD != null and gpD.gpId == gpSymId:
				return gpD
		return null
	var gpIsConn: Callable = func(gpN: GPPIDNode) -> bool:
		return GPOffPageIndex.gpIsConnectorNode(gpN, gpLookup)
	var gpFirst: Vector2 = GPOffPageIndex.gpNextLeftSlot(null, gpFrame, gpEnv, gpIsConn)
	gpCheck(gpFirst.x < gpEnv.x * 2.0, "the column hugs the frame's left edge")
	gpCheck(gpFirst.y < gpEnv.y * 3.0, "an empty column starts near the top")
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("c1", GP_ID_PIPE, "", Vector2(gpFirst.x, gpFirst.y), {}))
	gpG.gpAddNode(gpG.gpNewNode("c2", GP_ID_PIPE, "", Vector2(700, 100), {}))
	var gpNext: Vector2 = GPOffPageIndex.gpNextLeftSlot(gpG, gpFrame, gpEnv, gpIsConn)
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


# ---- full-attribute inherit (user feedback 2026-11-04, round 2) ----
# ---- 全属性继承（用户反馈 2026-11-04 第二轮）----

# The inheritable key set: every engineering attribute EXCEPT the number (it follows via the
# dedicated tag path) and the drawing-local ones (kind / signal type / arrow / tag
# visibility belong to each sheet).
# 可继承键集合：除编号（走专用编号通道）与绘图本地项（类型 / 信号类型 / 箭头 / 号显隐
# 属于每张图纸）外的全部工程属性。
func gpTestInheritKeysExcludeTagAndDrawingLocals() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpE: GPPIDEdge = gpG.gpNewEdge("e-1", "n1", "n2")
	gpE.gpAttrs["dn"] = "50"
	var gpKeys: Array[String] = GPInspector.gpEdgeInheritKeys(gpE, null)
	gpCheck(gpKeys.has("dn") and gpKeys.has("medium") and gpKeys.has("spec") \
		and gpKeys.has("insulation"), "the pipe identity fields are inheritable")
	gpCheck(gpKeys.has("design_pressure") and gpKeys.has("design_temp"),
		"the general engineering defaults are inheritable")
	gpCheck(not gpKeys.has("tag"),
		"the number follows the dedicated tag path, never this set")
	gpCheck(not gpKeys.has("kind") and not gpKeys.has("show_arrow") \
		and not gpKeys.has("show_tag") and not gpKeys.has("signal_type"),
		"drawing-local keys never inherit")
	# An imported / project-standard extra attribute is inheritable too ("all properties").
	# 导入 / 项目标准的额外属性同样可继承（「所有属性」）。
	gpE.gpAttrs["pipe_class"] = "B1F"
	gpCheck(GPInspector.gpEdgeInheritKeys(gpE, null).has("pipe_class"),
		"an extra edge attribute is inheritable too")
	# A signal line carries no pipeline attributes: nothing to inherit.
	# 信号线不带管线属性：无可继承。
	var gpSig: GPPIDEdge = gpG.gpNewEdge("e-2", "n1", "n2")
	gpSig.gpKind = GPPIDEdge.GP_SIGNAL
	gpCheck(GPInspector.gpEdgeInheritKeys(gpSig, null).is_empty(),
		"a signal edge inherits nothing")


# The batch blind-write is ONE undo step for the whole block: execute, undo, redo each move
# ALL keys together, and an identical write refuses (no empty undo step stacked).
# 批量盲写对整个属性块是**一个**撤销步：执行、撤销、重做都让**全部**键一起动，且相同值
# 写入被拒（不压入空转撤销步）。
func gpTestBatchAttrsIsOneUndoStep() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpE: GPPIDEdge = gpG.gpNewEdge("e-1", "n1", "n2")
	gpG.gpAddEdge(gpE)
	gpE.gpAttrs["dn"] = "50"
	gpE.gpAttrs["medium"] = "W"
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG, GPIdGen.new())
	var gpCmd: GPSetEdgeAttrsCommand = GPSetEdgeAttrsCommand.new("e-1",
		{"dn": "80", "spec": "B1F", "medium": null})
	gpCheck(gpCmd.gpExecute(gpCtx), "the batch executes")
	gpEq(str(gpE.gpAttrs.get("dn", "")), "80", "an existing key is overwritten")
	gpEq(str(gpE.gpAttrs.get("spec", "")), "B1F", "a new key is created")
	gpCheck(not gpE.gpAttrs.has("medium"), "null clears the key (single-key contract)")
	gpCmd.gpUndo(gpCtx)
	gpEq(str(gpE.gpAttrs.get("dn", "")), "50", "undo restores the overwritten key")
	gpCheck(not gpE.gpAttrs.has("spec"), "undo erases the key the batch created")
	gpEq(str(gpE.gpAttrs.get("medium", "")), "W", "undo restores the cleared key")
	gpCmd.gpRedo(gpCtx)
	gpEq(str(gpE.gpAttrs.get("dn", "")), "80", "redo replays the same writes")
	gpCheck(not gpE.gpAttrs.has("medium"), "redo clears again")
	var gpNoop: GPSetEdgeAttrsCommand = GPSetEdgeAttrsCommand.new("e-1", {"dn": "80"})
	gpCheck(not gpNoop.gpExecute(gpCtx), "an identical write refuses, no empty step")
	# Undo after a refused no-op restores the SAME state, not a half-synced one.
	# 被拒的空转之后撤销恢复的仍是**同一**状态，而不是「同步了一半」。
	gpNoop.gpUndo(gpCtx)
	gpEq(str(gpE.gpAttrs.get("dn", "")), "80", "undo after a refused write changes nothing")
	gpEq(str(gpE.gpAttrs.get("spec", "")), "B1F",
		"and the created key survives the refused write")


# Execute / undo / redo each notify the graph exactly once (B3), like every other command.
# 执行 / 撤销 / 重做各恰好通知图一次（B3），与其它命令一致。
func gpTestBatchAttrsNotifiesOncePerStep() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpE: GPPIDEdge = gpG.gpNewEdge("e-1", "n1", "n2")
	gpG.gpAddEdge(gpE)
	var gpHits: Array[int] = [0]
	gpG.gpGraphChanged.connect(func() -> void: gpHits[0] += 1)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG, GPIdGen.new())
	var gpCmd: GPSetEdgeAttrsCommand = GPSetEdgeAttrsCommand.new("e-1", {"dn": "80"})
	gpCheck(gpCmd.gpExecute(gpCtx), "the batch executes")
	gpEq(gpHits[0], 1, "execute notifies exactly once")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpHits[0], 2, "undo notifies too (B3)")
	gpCmd.gpRedo(gpCtx)
	gpEq(gpHits[0], 3, "redo notifies too")


# The batch write is the propagation's own DOWNSTREAM end: it must never emit
# gpEdgeAttrsCommitted, or each propagated write would fan out again and never terminate.
# The inspector path emits exactly once with the non-number keys.
# 批量写入是传播自身的**下游端**：绝不 emit gpEdgeAttrsCommitted，否则每次传播写入都会再次
# 扇出、永不收敛。属性面板路径则恰好发射一次，且只带非编号键。
func gpTestBatchServiceWriteIsSilentInspectorPathEmits() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpE: GPPIDEdge = gpG.gpNewEdge("e-1", "n1", "n2")
	gpG.gpAddEdge(gpE)
	gpE.gpAttrs["dn"] = "80"
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new())
	var gpHits: Array[int] = [0]
	var gpLastKeys: Array = [null]
	gpSvc.gpEdgeAttrsCommitted.connect(func(_gpId: String, gpKeys: Array[String]) -> void:
		gpHits[0] += 1
		gpLastKeys[0] = gpKeys)
	gpCheck(gpSvc.gpSetEdgeAttrs("e-1", {"dn": "100", "spec": "B1F"}),
		"the batch write succeeds")
	gpEq(gpHits[0], 0, "the batch write emits NOTHING (recursion pin)")
	gpCheck(gpSvc.gpApplyLineAttr("e-1", "dn", "150"), "the inspector path applies")
	gpEq(gpHits[0], 1, "the inspector path emits exactly once")
	var gpKeys: Array[String] = gpLastKeys[0] as Array[String]
	gpCheck(gpKeys.size() == 1 and gpKeys[0] == "dn",
		"the emission names the attribute, never \"tag\"")
	gpCheck(gpSvc.gpSetEdgeAttr("e-1", "design_pressure", "1.0"),
		"the single blind write succeeds")
	gpEq(gpHits[0], 2, "the single blind write emits once too")
	gpKeys = gpLastKeys[0] as Array[String]
	gpCheck(gpKeys.size() == 1 and gpKeys[0] == "design_pressure",
		"the single emission names its key")


# ------------------------------------------------------------------ D20 three-state (2026-11-04)
# The offpage flag's three states ride the GENERATOR output as one key — screen translates
# it to a stroke color, print to a lineweight; both read the SAME decision (B2 redline).
# The decision itself is a pure function of the reference text.
# 离页旗标的三态作为**一个键**随生成器输出走 —— 屏幕把它翻译成描边色、打印翻译成线重，
# 双方读**同一份**判定（B2 红线）。判定本身是交叉编号文字的纯函数。
func gpTestOffpageStateFollowsTheReferenceText() -> void:
	gpEq(GPSymbolGeneratorRegistry.gpOffpageStateFor(""), "unlinked",
		"an empty reference is the honest UNLINKED placeholder")
	gpEq(GPSymbolGeneratorRegistry.gpOffpageStateFor("  "), "unlinked",
		"whitespace-only is still unlinked")
	gpEq(GPSymbolGeneratorRegistry.gpOffpageStateFor("?"), "dangling",
		"the question mark is the DANGLING reference")
	gpEq(GPSymbolGeneratorRegistry.gpOffpageStateFor("2-1"), "resolved",
		"a real number is RESOLVED")


# ------------------------------------------------------------------ U3 unlink (2026-11-04)
# Unlink = the link leaves the table, BOTH connector flags STAY (honest unlinked state,
# props cleared), one undo step; undo re-seats the link at its old index and both props.
# 断开 = link 离开表、**两面**连接符旗标**留下**（诚实的未连接态、属性清除），一个撤销步；
# 撤销把 link 插回原下标并复位两端属性。
func gpTestUnlinkKeepsBothFlagsAndRoundTrips() -> void:
	var gpRig: Dictionary = _gpRig()
	_gpCreate(gpRig)
	var gpLinks: Array[GPOffPageLink] = gpRig["links"]
	var gpLink: GPOffPageLink = gpLinks[0]
	var gpLocalId: String = str(gpLink.gpA.get(GPOffPageLink.GP_KEY_NODE, ""))
	var gpPeerId: String = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
	var gpLocalGraph: GPPIDGraph = gpRig["local"] as GPPIDGraph
	var gpPeerGraph: GPPIDGraph = gpRig["peer"] as GPPIDGraph
	var gpUnlink: GPUnlinkOffPageCommand = GPUnlinkOffPageCommand.new(gpLink, gpLinks,
		gpLocalGraph, gpPeerGraph)
	gpCheck(gpUnlink.gpExecute(gpRig["ctx"]), "the unlink executes")
	gpEq(gpLinks.size(), 0, "the link left the container table")
	gpCheck(gpLocalGraph.gpGetNode(gpLocalId) != null,
		"the LOCAL connector flag STAYS on its sheet")
	gpCheck(gpPeerGraph.gpGetNode(gpPeerId) != null,
		"the PEER connector flag STAYS on its sheet")
	gpEq(str((gpLocalGraph.gpGetNode(gpLocalId) as GPPIDNode).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), "", "the local prop is cleared — honest unlinked")
	gpEq(str((gpPeerGraph.gpGetNode(gpPeerId) as GPPIDNode).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), "", "the peer prop is cleared — honest unlinked")
	# Undo: link back at its old index, both props re-seated. / 撤销：link 回原下标、属性复位。
	gpUnlink.gpUndo(gpRig["ctx"])
	gpEq(gpLinks.size(), 1, "undo puts the link back")
	gpCheck(gpLinks[0] == gpLink, "the SAME link object returns")
	gpEq(str((gpLocalGraph.gpGetNode(gpLocalId) as GPPIDNode).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), gpLink.gpInstanceId, "the local prop is re-seated")
	gpEq(str((gpPeerGraph.gpGetNode(gpPeerId) as GPPIDNode).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), gpLink.gpInstanceId, "the peer prop is re-seated")
	# Redo unlinks again. / 重做再断开一次。
	gpUnlink.gpRedo(gpRig["ctx"])
	gpEq(gpLinks.size(), 0, "redo removes the link again")
	gpEq(str((gpLocalGraph.gpGetNode(gpLocalId) as GPPIDNode).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), "", "redo clears the local prop again")


# A link already out of the table cannot be unlinked twice (the redo-race guard, same as delete).
# 已不在表中的 link 不能再断开一次（重做竞态守卫，与整删一致）。
func gpTestUnlinkRefusesAMissingLink() -> void:
	var gpRig: Dictionary = _gpRig()
	_gpCreate(gpRig)
	var gpLinks: Array[GPOffPageLink] = gpRig["links"]
	var gpLink: GPOffPageLink = gpLinks[0]
	var gpLocalGraph: GPPIDGraph = gpRig["local"] as GPPIDGraph
	var gpPeerGraph: GPPIDGraph = gpRig["peer"] as GPPIDGraph
	var gpUnlink: GPUnlinkOffPageCommand = GPUnlinkOffPageCommand.new(gpLink, gpLinks,
		gpLocalGraph, gpPeerGraph)
	gpLinks.erase(gpLink)
	gpCheck(not gpUnlink.gpExecute(gpRig["ctx"]),
		"a link no longer in the table refuses to unlink")
	gpCheck(gpLocalGraph.gpGetNode(str(gpLink.gpA.get(GPOffPageLink.GP_KEY_NODE, ""))) != null,
		"and the local flag keeps its link reference")


# D16: a USER-PACK connector (no builtin id, no def in the default library) still stacks in
# the left column when its props carry link_id — the props prove the role.
# D16：**用户包**连接符（非内置 id、默认库无 def）只要 props 带 link_id 就参与左列堆叠
# —— props 证明身份。
func gpTestUserPackConnectorStacks() -> void:
	var gpFrame: Rect2 = Rect2(0, 0, 841, 594)
	var gpEnv: Vector2 = Vector2(96, 10)
	var gpDefs: Array[GPSymbolDef] = GPSymbolLibrary.gpDefaultDefs()
	var gpLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		for gpD in gpDefs:
			if gpD != null and gpD.gpId == gpSymId:
				return gpD
		return null
	var gpIsConn: Callable = func(gpN: GPPIDNode) -> bool:
		return GPOffPageIndex.gpIsConnectorNode(gpN, gpLookup)
	var gpFirst: Vector2 = GPOffPageIndex.gpNextLeftSlot(null, gpFrame, gpEnv, gpIsConn)
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpUser: GPPIDNode = gpG.gpNewNode("u1", "EUSRCUSTCONN", "",
		Vector2(gpFirst.x, gpFirst.y), {})
	gpUser.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG.gpAddNode(gpUser)
	var gpNext: Vector2 = GPOffPageIndex.gpNextLeftSlot(gpG, gpFrame, gpEnv, gpIsConn)
	gpCheck(gpNext.y > gpFirst.y + gpEnv.y * 2.0,
		"a user-pack connector dictates the stacking / 用户包连接符参与堆叠")
	# And WITHOUT the props claim (and no def) it is not a column member.
	# 而无 props 声称（且无 def）时不是列成员。
	var gpG2: GPPIDGraph = GPPIDGraph.new()
	gpG2.gpAddNode(gpG2.gpNewNode("u2", "EUSRCUSTCONN", "",
		Vector2(gpFirst.x, gpFirst.y), {}))
	var gpNext2: Vector2 = GPOffPageIndex.gpNextLeftSlot(gpG2, gpFrame, gpEnv, gpIsConn)
	gpCheck(absf(gpNext2.y - (gpFrame.position.y + gpEnv.y * 1.5)) < 0.001,
		"a def-less, claim-less symbol is ignored / 无定义无声称的符号被忽略")


# D17 (R4): the FULL snap — the drop point picks the nearest frame edge, and the flag lands
# in THAT side's connector column/row (same stacking family as the left column), never at
# the drop point itself.
# D17（R4）：**完整吸附** —— 松手点只选最近的图框边，旗标落进**该边**的连接符列/行
#（与左列同一套堆叠家族），绝不落在松手点本身。
func gpTestSnapSlotPicksNearestEdge() -> void:
	var gpFrame: Rect2 = Rect2(0, 0, 841, 594)
	var gpEnv: Vector2 = Vector2(96, 10)
	var gpDefs: Array[GPSymbolDef] = GPSymbolLibrary.gpDefaultDefs()
	var gpLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		for gpD in gpDefs:
			if gpD != null and gpD.gpId == gpSymId:
				return gpD
		return null
	var gpIsConn: Callable = func(gpN: GPPIDNode) -> bool:
		return GPOffPageIndex.gpIsConnectorNode(gpN, gpLookup)
	var gpG: GPPIDGraph = GPPIDGraph.new()
	# Nearest-edge choice: a drop far to the RIGHT snaps into the right column.
	# 最近边选择：图框右侧远处的松手点吸附进**右**列。
	# D26 (2026-11-06): the right column now sits ≈ 1/12 frame width inside the border.
	# D26（2026-11-06）：右列现位于距内边框约 1/12 图幅宽处。
	var gpRight: Vector2 = GPOffPageIndex.gpSnapSlotFor(Vector2(900, 300), gpG,
		gpFrame, gpEnv, gpIsConn)
	gpCheck(absf(gpRight.x - (gpFrame.end.x - maxf(gpEnv.x * 0.55,
			gpFrame.size.x / 12.0))) < 0.001,
		"the right drop hugs the frame's right edge / 右侧松手贴右缘")
	gpCheck(absf(gpRight.y - (gpFrame.position.y + gpEnv.y * 1.5)) < 0.001,
		"an empty right column starts near the top / 空右列从顶部附近起排")
	# A drop above the frame snaps into the top ROW (stacks along +x).
	# 图框上方的松手点吸附进**上**行（沿 +x 堆叠）。
	var gpTop: Vector2 = GPOffPageIndex.gpSnapSlotFor(Vector2(400, -50), gpG,
		gpFrame, gpEnv, gpIsConn)
	gpCheck(absf(gpTop.y - (gpFrame.position.y + gpEnv.y * 0.55)) < 0.001,
		"the top drop hugs the frame's top edge / 上方松手贴上缘")
	gpCheck(absf(gpTop.x - (gpFrame.position.x + gpEnv.x * 1.5)) < 0.001,
		"an empty top row starts near the left / 空上行从左侧附近起排")
	# Stacking: a member in the right column pushes the next slot DOWN by the pitch.
	# 堆叠：右列已有成员时，下一槽位按行距下移。
	gpG.gpAddNode(gpG.gpNewNode("c1", GP_ID_PIPE, "", Vector2(gpRight.x, gpRight.y), {}))
	var gpRight2: Vector2 = GPOffPageIndex.gpSnapSlotFor(Vector2(900, 300), gpG,
		gpFrame, gpEnv, gpIsConn)
	gpCheck(absf(gpRight2.y - (gpRight.y + gpEnv.y * 3.0)) < 0.001,
		"the next right slot stacks 3 envelopes down / 右列下一槽下移 3 倍包络")
	# A member parked in the LEFT band never dictates the RIGHT column.
	# 停在**左**带的成员不支配**右**列。
	var gpG2: GPPIDGraph = GPPIDGraph.new()
	gpG2.gpAddNode(gpG2.gpNewNode("c2", GP_ID_PIPE, "",
		Vector2(gpFrame.position.x + gpEnv.x * 0.55, gpFrame.position.y + 50.0), {}))
	var gpRight3: Vector2 = GPOffPageIndex.gpSnapSlotFor(Vector2(900, 300), gpG2,
		gpFrame, gpEnv, gpIsConn)
	gpCheck(absf(gpRight3.y - (gpFrame.position.y + gpEnv.y * 1.5)) < 0.001,
		"a left-band member does not stack the right column / 左带成员不堆叠右列")
	# Print-safety: EVERY snapped slot lies INSIDE the frame (no off-paper prints).
	# 打印安全：**每个**吸附槽位都在图框**内**（绝无出纸打印）。
	for gpSlot in [gpRight, gpTop, gpRight2, gpRight3]:
		gpCheck(gpFrame.has_point(gpSlot), "the slot is inside the frame / 槽位在图框内")


# D26 (2026-11-06 user feedback): the SOURCE connector's slot API — ALWAYS the right
# column, top-down stacking, ≈ 1/12 of the frame width inside the right border; the
# half-envelope floor keeps small frames print-safe.
# D26（2026-11-06 用户反馈）：**源端**连接符专用槽位 —— 一律**右列**、自上而下堆叠、
# 距右内边框约 1/12 图幅宽；半包络下限保证小图幅不出纸。
func gpTestNextRightSlotParksTheSourceFlag() -> void:
	var gpFrame: Rect2 = Rect2(0, 0, 841, 594)
	var gpEnv: Vector2 = Vector2(48, 5)
	var gpIsConn: Callable = func(_gpN: GPPIDNode) -> bool:
		return true
	var gpSlotX: float = gpFrame.end.x - maxf(gpEnv.x * 0.55, gpFrame.size.x / 12.0)
	# An empty source column starts near the top, at the 1/12-depth column.
	# 空源列从顶部附近起排，列位在 1/12 深度。
	var gpFirst: Vector2 = GPOffPageIndex.gpNextRightSlot(null, gpFrame, gpEnv, gpIsConn)
	gpCheck(absf(gpFirst.x - gpSlotX) < 0.001,
		"the source column sits 1/12 frame width inside the right border / 源端列距右内边框 1/12 图幅宽")
	gpCheck(absf(gpFirst.y - (gpFrame.position.y + gpEnv.y * 1.5)) < 0.001,
		"an empty source column starts near the top / 空源列从顶部附近起排")
	# Stacking: the next source flag goes BELOW the lowest member, same column.
	# 堆叠：下一个源端旗标排在**最低**成员之下，同列。
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("c1", GP_ID_PIPE, "", Vector2(gpFirst.x, gpFirst.y), {}))
	var gpNext: Vector2 = GPOffPageIndex.gpNextRightSlot(gpG, gpFrame, gpEnv, gpIsConn)
	gpCheck(absf(gpNext.x - gpFirst.x) < 0.001,
		"the source column keeps its x / 源端列保持 x")
	gpCheck(absf(gpNext.y - (gpFirst.y + gpEnv.y * 3.0)) < 0.001,
		"the next source slot stacks 3 envelopes down / 源列下一槽下移 3 倍包络")
	# A LEFT-band member (the PEER twin) never stacks the source column.
	# **左**带成员（对端孪生体）不参与源列堆叠。
	var gpG2: GPPIDGraph = GPPIDGraph.new()
	gpG2.gpAddNode(gpG2.gpNewNode("c2", GP_ID_PIPE, "",
		Vector2(gpFrame.position.x + gpEnv.x * 0.55, gpFrame.position.y + 50.0), {}))
	var gpFresh: Vector2 = GPOffPageIndex.gpNextRightSlot(gpG2, gpFrame, gpEnv, gpIsConn)
	gpCheck(absf(gpFresh.y - (gpFrame.position.y + gpEnv.y * 1.5)) < 0.001,
		"a left-band member does not stack the source column / 左带成员不堆叠源列")
	# Print safety on a small frame: the half-envelope floor wins over 1/12.
	# 小图幅打印安全：半包络下限压过 1/12。
	var gpSmall: Vector2 = GPOffPageIndex.gpNextRightSlot(null, Rect2(0, 0, 200, 150),
		gpEnv, gpIsConn)
	gpCheck(absf(gpSmall.x - (200.0 - gpEnv.x * 0.55)) < 0.001,
		"a small frame keeps the envelope floor / 小图幅保持半包络下限")


# ---- unlink（U3 断开 + 重连变体）----
# ---- unlink ----

# The plain 断开 clears BOTH claims; the RECONNECT variant (gpKeepPeerClaim, user feedback
# 2026-11-05) leaves the FAR claim in place — the old target renders "?" with an amber line
# and the DRC strays rule reports it as an ERROR, while undo restores everything.
# 普通「断开」清除**两端**声称；**重连变体**（gpKeepPeerClaim，用户反馈 2026-11-05）把
# 远端声称留在原地 —— 原目标端渲染「?」、连线染琥珀，DRC strays 规则报 ERROR，
# 而撤销恢复一切。
func gpTestUnlinkKeepsPeerClaimForReconnect() -> void:
	# Plain unlink: both ends go back to the honest unlinked state.
	# 普通「断开」：两端都回到诚实的未连接态。
	var gpRig: Dictionary = _gpRig()
	_gpCreate(gpRig)
	var gpLink: GPOffPageLink = gpRig["links"][0]
	var gpLocalId: String = str(gpLink.gpA.get("node_id", ""))
	var gpPeerId: String = str(gpLink.gpB.get("node_id", ""))
	var gpCmd: GPUnlinkOffPageCommand = GPUnlinkOffPageCommand.new(gpLink,
		gpRig["links"], gpRig["local"], gpRig["peer"])
	gpCheck(gpCmd.gpExecute(gpRig["ctx"]), "plain unlink executes / 普通断开可执行")
	gpEq((gpRig["links"] as Array).size(), 0, "the link left the table / link 已离表")
	gpEq(str((gpRig["local"] as GPPIDGraph).gpGetNode(gpLocalId).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), "", "local claim cleared / 本端声称已清")
	gpEq(str((gpRig["peer"] as GPPIDGraph).gpGetNode(gpPeerId).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), "", "peer claim cleared / 对端声称已清")
	gpCmd.gpUndo(gpRig["ctx"])
	gpEq((gpRig["links"] as Array).size(), 1, "undo re-inserts the link / 撤销插回 link")
	gpEq(str((gpRig["peer"] as GPPIDGraph).gpGetNode(gpPeerId).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), gpLink.gpInstanceId,
		"undo re-seats the peer claim / 撤销复位对端声称")
	# Reconnect variant: the FAR claim survives — stale on purpose (ADR-45 D2e).
	# 重连变体：远端声称**存活** —— 刻意陈旧（ADR-45 D2e）。
	var gpRig2: Dictionary = _gpRig()
	_gpCreate(gpRig2)
	var gpLink2: GPOffPageLink = gpRig2["links"][0]
	var gpLocalId2: String = str(gpLink2.gpA.get("node_id", ""))
	var gpPeerId2: String = str(gpLink2.gpB.get("node_id", ""))
	var gpCmd2: GPUnlinkOffPageCommand = GPUnlinkOffPageCommand.new(gpLink2,
		gpRig2["links"], gpRig2["local"], gpRig2["peer"], true)
	gpCheck(gpCmd2.gpExecute(gpRig2["ctx"]), "reconnect break executes / 重连断开可执行")
	gpEq((gpRig2["links"] as Array).size(), 0, "the link left the table / link 已离表")
	gpEq(str((gpRig2["local"] as GPPIDGraph).gpGetNode(gpLocalId2).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), "", "local claim cleared / 本端声称已清")
	gpEq(str((gpRig2["peer"] as GPPIDGraph).gpGetNode(gpPeerId2).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), gpLink2.gpInstanceId,
		"the far claim SURVIVES — stale on purpose / 远端声称**存活** —— 刻意陈旧")
	gpCmd2.gpUndo(gpRig2["ctx"])
	gpEq((gpRig2["links"] as Array).size(), 1, "undo restores the link / 撤销恢复 link")
	gpEq(str((gpRig2["local"] as GPPIDGraph).gpGetNode(gpLocalId2).gpProps.get(
		GPOffPageLink.GP_KEY_LINK_ID, "")), gpLink2.gpInstanceId,
		"undo re-seats the local claim / 撤销复位本端声称")
