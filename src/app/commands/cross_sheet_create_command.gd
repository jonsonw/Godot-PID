class_name GPCrossSheetCreateCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Create a CROSS-SHEET connection as ONE undoable step (ADR-43 / S3).
# 把「跨图纸连接」作为**一步**可撤销的编辑创建出来（ADR-43 / S3）。
#
# What one gesture means / 一个手势的含义：
# "this line continues on sheet N". Depending on what already exists, the command creates
# up to FOUR things at once: the local connector symbol, the edge from the source port into
# it, the twin connector on the peer sheet, and the container-level link. If these were
# separate undo steps, undo would leave an unpaired connector or a dangling flag — states
# the user never created and the DRC reports as errors. One gesture, one step.
# 「这条线在图纸 N 续接」。按既有实体的情况，命令一次最多创建四样东西：本端连接符图元、
# 从源端口接入的边、对端图纸上的孪生连接符、容器级 link。若拆成多步撤销，会留下未配对的
# 连接符或悬空旗标 —— 那是用户从未制造过的状态，DRC 会报错。一个手势，一步。
#
# Two creation paths, one command / 两条创建路径，一条命令：
# - MODE A (out-of-frame draw): nothing exists yet; both connectors and the edge are created.
# - MODE B ("connect to another sheet" on an existing connector, and/or an existing peer
#   item): gpExistingLocalNodeId / gpExistingPeerRef name objects that ALREADY exist; the
#   command only creates the link (and, on the local side, optionally the edge into the
#   existing connector). Existing objects are never re-created and never deleted by undo.
# - 模式 A（画线出界）：什么都还没有；两个连接符与边都由命令创建。
# - 模式 B（对既有连接符右键「连接到其他图纸…」和 / 或对端已有目标）：gpExistingLocalNodeId /
#   gpExistingPeerRef 指明**已存在**的对象；命令只创建 link（本端可选再补一条接入既有连接符
#   的边）。既有对象绝不重建，撤销也绝不删除它们。
#
# Why the command holds model references directly / 为何命令直接持有模型引用：
# GPCommandContext is deliberately sheet-local (one graph). A cross-sheet command needs
# the peer graph and the container link array too; both are MODEL objects, not widgets,
# so passing them in the constructor keeps the command a value object that runs headless.
# GPCommandContext 刻意是单图纸的（一张图）。跨图纸命令还需要对端图与容器 link 表；
# 两者都是**模型**对象而非控件，故经构造函数传入仍保持值对象属性，可 headless 测试。
#
# Id hygiene / id 卫生：
# The link id and created connector ids are minted INSIDE gpExecute() and reused on redo,
# so undo+redo never burns ids or renumbers the connection (same rule as the tag minting
# in GPConnectEdgeCommand). The link id is additionally de-duplicated against the live
# link array: two sheets have separate id generators, and only uniqueness INSIDE the
# container array matters.
# link id 与新建连接符 id 都在 gpExecute() 内铸出并在重做时复用，使撤销+重做既不烧号也
# 不改号（同 GPConnectEdgeCommand 的铸号规则）。link id 额外对**活的** link 表去重：
# 两张图纸各有 id 生成器，而唯一性只在容器数组内部有意义。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Local (source) end: {"node_id","port_id"} or a dangling {"point":[x,y]}.
# 本端（源）：端口绑定 {"node_id","port_id"}，或悬空 {"point":[x,y]}。
var gpFromRef: Dictionary = {}

# GPPIDEdge.GP_PROCESS / GP_UTILITY / GP_SIGNAL. SIGNAL picks the signal connector.
# 与边三分同词表。SIGNAL 选用信号连接符。
var gpKind: String = GPPIDEdge.GP_PROCESS

# Signal medium when gpKind == GP_SIGNAL. / gpKind 为 SIGNAL 时的信号类型。
var gpSignalType: String = ""

# False when the user drew with Shift held (straight, not orthogonal).
# 用户按住 Shift 绘制时为 false（直线而非正交）。
var gpOrtho: bool = true

# Where the local connector lands, in the local sheet's world mm (mode A only).
# 本端连接符落点（本图纸世界坐标 mm；仅模式 A）。
var gpLocalPos: Vector2 = Vector2.ZERO

# Where the twin connector lands on the peer sheet (mode A only).
# 孪生连接符在对端图纸上的落点（仅模式 A）。
var gpPeerPos: Vector2 = Vector2.ZERO

# The peer sheet's id (GPSheet.gpId). / 对端图纸 id（GPSheet.gpId）。
var gpPeerSheetId: String = ""

# The local sheet's id. / 本端图纸 id。
var gpLocalSheetId: String = ""

# The peer sheet's DRAWING NUMBER for auto tag minting ("3-1"); "" falls back to a bare
# sequence number. Derived by the caller, never stored as a link field (ADR-43 D4).
# 铸自动编号用的对端**图号**（"3-1"）；为空则回落纯序号。由调用方推导，
# 绝不作为 link 字段存储（ADR-43 D4）。
var gpPeerNumber: String = ""

# The peer graph. / 对端图。
var gpPeerGraph: GPPIDGraph = null

# The LIVE container link array (gpCenter.gpOffPageLinks). Held by reference on purpose:
# the link must be visible to every reader of the container the moment execute returns.
# **活的**容器 link 表（gpCenter.gpOffPageLinks）。刻意按引用持有：execute 一返回，
# link 就必须对容器的所有读取方可见。
var gpLinks: Array[GPOffPageLink] = []

# MODE B: an EXISTING connector on the local sheet to attach the link to (no local node and
# no edge is created).
# 模式 B：本端图纸上**既有**的连接符，link 直接挂它（不建本端节点，也不建边）。
var gpExistingLocalNodeId: String = ""

# MODE B: an EXISTING peer endpoint {"node_id","port_id"} — the link's B end points there
# instead of a freshly minted twin.
# 模式 B：对端**既有**端点 {"node_id","port_id"} —— link 的 B 端指向它，而非新建孪生体。
var gpExistingPeerRef: Dictionary = {}

# The item on the PEER sheet the twin must SERVE (dialog mode, user feedback 2026-11-03):
# when it names an existing NON-connector item, the command mints the twin at its auto slot,
# draws the edge twin -> item, and points the link's B end at the twin — the connector on the
# target sheet is a free flag in the left column, NEVER a child of the item (the pack is
# non-mountable and no mount is ever created). When it names a CONNECTOR, the link attaches
# to that connector directly (the existing-peer shape).
# 对端图纸上孪生体要**服务**的对象（对话框路径，用户反馈 2026-11-03）：指向已存在的
# **非连接符**对象时，命令在自动槽位铸出孪生体、画出「孪生体 -> 对象」的边，并把 link 的
# B 端指向孪生体 —— 目标图纸上的连接符是左列里一面自由的旗标，**绝不**成为对象的子图元
#（图元包不可挂载，也从不创建挂载）。指向**连接符**时，link 直接挂该连接符（既有对端形态）。
var gpServedRef: Dictionary = {}

# The edge command for the twin -> served-item edge (its own half-step on the peer graph,
# sharing the id/tag registries — the same second-context pattern the delete command uses).
# 「孪生体 -> 服务对象」那条边的边命令（在对端图上的独立半步，共享 id/tag 注册表 ——
# 与删除命令相同的第二上下文模式）。
var _gpPeerConnect: GPConnectEdgeCommand = null

# Id of the created link (readable after a successful execute).
# 所创建 link 的 id（执行成功后可读）。
var gpCreatedLinkId: String = ""

# Human-readable reason the command refused. / 命令拒绝执行的人类可读原因。
var gpRefusal: String = ""

# Created objects, kept so undo removes exactly them and redo re-adds the SAME ones.
# 创建的对象。保留它们使撤销精确移除、重做原样加回。
var _gpLocalNode: GPPIDNode = null
var _gpPeerNode: GPPIDNode = null
var _gpLink: GPOffPageLink = null
var _gpConnect: GPConnectEdgeCommand = null
var _gpLinkAt: int = -1

# Prior link_id values of EXISTING nodes that were stamped in mode B, so undo restores
# exactly what was there ("" = the key is removed again).
# 模式 B 中被盖写的**既有**节点原 link_id 值，使撤销精确还原（"" = 撤销时删除该键）。
var _gpLocalStampPrior: String = ""
var _gpPeerStampPrior: String = ""


func _init(gpInFromRef: Dictionary, gpInKind: String, gpInSignalType: String,
		gpInLocalPos: Vector2, gpInPeerPos: Vector2, gpInLocalSheetId: String,
		gpInPeerSheetId: String, gpInPeerNumber: String, gpInPeerGraph: GPPIDGraph,
		gpInLinks: Array[GPOffPageLink], gpInOrtho: bool = true,
		gpInExistingLocalNodeId: String = "", gpInExistingPeerRef: Dictionary = {},
		gpInServedRef: Dictionary = {}) -> void:
	gpFromRef = gpInFromRef.duplicate(true)
	gpKind = gpInKind
	gpSignalType = gpInSignalType
	gpOrtho = gpInOrtho
	gpLocalPos = gpInLocalPos
	gpPeerPos = gpInPeerPos
	gpLocalSheetId = gpInLocalSheetId
	gpPeerSheetId = gpInPeerSheetId
	gpPeerNumber = gpInPeerNumber
	gpPeerGraph = gpInPeerGraph
	gpLinks = gpInLinks
	gpExistingLocalNodeId = gpInExistingLocalNodeId
	gpExistingPeerRef = gpInExistingPeerRef.duplicate(true)
	gpServedRef = gpInServedRef.duplicate(true)
	gpLabel = "跨图纸连接"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	gpRefusal = ""
	if gpCtx == null or not gpCtx.gpIsReady():
		return false
	if not _gpValidate(gpCtx):
		return false
	# First run mints everything; a redo re-adds the SAME objects (see gpRedo).
	# 首次执行全部铸号；重做原样加回（见 gpRedo）。
	if _gpLink == null:
		# Mint the link id first: both endpoints' nodes may carry it in their props, so it
		# must exist before the nodes are built.
		# 先铸 link id：两端节点的 props 都可能要带它，故必须先于节点存在。
		var gpLinkId: String = _gpMintLinkId(gpCtx)
		var gpAttrs: Dictionary = {}
		if gpKind == GPPIDEdge.GP_SIGNAL and gpSignalType != "":
			gpAttrs["signal_type"] = gpSignalType
		# LOCAL SIDE. Mode B reuses the existing connector; mode A creates one and draws the
		# edge into it (edge minting — line number, duplicate detection — is delegated to the
		# existing command so both paths stay one vocabulary).
		# 本端。模式 B 复用既有连接符；模式 A 新建一个并接入边（铸管线号与重复检测交给
		# 既有命令，使两条路共用一套词表）。
		var gpLocalId: String = gpExistingLocalNodeId
		if gpLocalId == "":
			gpLocalId = gpCtx.gpIds.gpNext("n")
			_gpLocalNode = gpCtx.gpGraph.gpNewNode(gpLocalId, _gpSymbolId(), "",
				gpLocalPos, {GPOffPageLink.GP_KEY_LINK_ID: gpLinkId})
			gpCtx.gpGraph.gpAddNode(_gpLocalNode)
			var gpToRef: Dictionary = {"node_id": gpLocalId,
				"port_id": GPSymbolPackOffpage.GP_PORT_NAME}
			_gpConnect = GPConnectEdgeCommand.new(gpFromRef, gpToRef, gpKind,
				gpSignalType, gpOrtho)
			if not _gpConnect.gpExecute(gpCtx):
				# Roll the gesture back entirely: a refused edge must not leave a connector.
				# 整个手势回滚：边被拒时不得留下连接符。
				gpCtx.gpGraph.gpRemoveNode(gpLocalId)
				gpRefusal = _gpConnect.gpRefusal
				_gpLocalNode = null
				_gpConnect = null
				return false
		else:
			# The existing connector must carry the link id in its props, or the renderer
			# cannot derive its reference text at all.
			# 既有连接符的 props 必须盖上 link id，否则渲染层根本推导不出对端图号。
			_gpLocalStampPrior = _gpStampLinkId(
				gpCtx.gpGraph.gpGetNode(gpExistingLocalNodeId), gpLinkId)
		# PEER SIDE. Three shapes: (a) SERVED — the dialog picked a real item on the peer
		# sheet: mint the twin at its auto slot, draw the edge twin -> item, and the link's
		# B end is the twin; (b) EXISTING PEER — the B end is an existing connector: stamp it;
		# (c) BARE TWIN — no served item yet.
		# 对端。三种形态：(a) **服务模式** —— 对话框在对端图上选定了真实对象：在自动槽位铸孪生体、
		# 画出「孪生体 -> 对象」的边，link 的 B 端即孪生体；(b) **既有对端** —— B 端是既有连接符：
		# 盖章；(c) **裸孪生体** —— 尚无服务对象。
		var gpPeerRef: Dictionary = gpExistingPeerRef
		var gpServedNode: GPPIDNode = null
		if not gpServedRef.is_empty():
			gpServedNode = gpPeerGraph.gpGetNode(str(gpServedRef.get("node_id", "")))
			if gpServedNode != null and _gpIsConnector(gpServedNode):
				# Picking a connector in the dialog IS the existing-peer shape.
				# 在对话框里选中连接符，就是「既有对端」形态。
				gpPeerRef = gpServedRef
				gpServedNode = null
		if gpServedNode != null:
			var gpPeerId: String = gpCtx.gpIds.gpNext("n")
			_gpPeerNode = gpPeerGraph.gpNewNode(gpPeerId, _gpSymbolId(), "",
				gpPeerPos, {GPOffPageLink.GP_KEY_LINK_ID: gpLinkId})
			# UNFLIPPED, reading left-to-right (user feedback 2026-11-03, second round): the
			# flat face hugs the left column, the pennant points RIGHT toward the served item,
			# and the edge leaves from the "cont" port — whose per-instance position the
			# generator pins to the ADAPTIVE body's tip, so the line starts on drawn geometry
			# for any reference width. The connector stays a free top-level symbol.
			# **不翻转**、读向从左到右（用户反馈 2026-11-03 第二轮）：平直面贴左列、旗尖朝**右**
			# 指向被服务对象，边从 "cont" 端口出发 —— 该端口的逐实例位置由生成器钉在**自适应**
			# 主体的旗尖上，故任何编号宽度下线都从画出的几何上起步。连接符仍是自由的顶层图元。
			gpPeerGraph.gpAddNode(_gpPeerNode)
			var gpTwinRef: Dictionary = {"node_id": gpPeerId,
				"port_id": GPSymbolPackOffpage.GP_PORT_CONT}
			# INHERIT the source line's number (user feedback 2026-11-04): the continuation
			# segment on the peer sheet carries the SAME line number, not a freshly minted
			# one. An empty preset (signal lines, or no source line) mints as before.
			# 继承源管线编号（用户反馈 2026-11-04）：对端图纸上的延续段携带**同一个**管线号，
			# 而不是新铸一个。预设为空（信号线、或尚无源线）时照旧铸号。
			_gpPeerConnect = GPConnectEdgeCommand.new(gpTwinRef, gpServedRef, gpKind,
				gpSignalType, gpOrtho, _gpSourceEdgeTag(gpCtx))
			if not _gpPeerConnect.gpExecute(
					GPCommandContext.new(gpPeerGraph, gpCtx.gpIds, gpCtx.gpTags)):
				# Roll the WHOLE gesture back: the local half included — a refused peer edge
				# must not leave a half-built connection on either sheet.
				# 整个手势回滚：含本端一半 —— 对端边被拒时，任何一张图上都不得留下半成品。
				gpRefusal = _gpPeerConnect.gpRefusal
				_gpRollbackLocal(gpCtx)
				gpPeerGraph.gpRemoveNode(gpPeerId)
				_gpPeerNode = null
				_gpPeerConnect = null
				return false
			gpPeerRef = gpTwinRef
		elif gpPeerRef.is_empty():
			var gpPeerId: String = gpCtx.gpIds.gpNext("n")
			_gpPeerNode = gpPeerGraph.gpNewNode(gpPeerId, _gpSymbolId(), "",
				gpPeerPos, {GPOffPageLink.GP_KEY_LINK_ID: gpLinkId})
			# A bare twin still lives on the TARGET sheet, same left-to-right look; its
			# continuation port is where a future served edge will attach.
			# 裸孪生体同样立在**目标**图纸上、同样的从左到右外观；其续接端口就是将来
			# 「去往服务对象」的边要接的位置。
			gpPeerGraph.gpAddNode(_gpPeerNode)
			gpPeerRef = {"node_id": gpPeerId, "port_id": GPSymbolPackOffpage.GP_PORT_CONT}
		else:
			var gpPeerNode: GPPIDNode = gpPeerGraph.gpGetNode(
				str(gpPeerRef.get("node_id", "")))
			# An existing PEER connector displays the reference too; an ordinary item
			# (equipment port) does not — it is just where the line lands.
			# 对端**既有连接符**同样要显示对端编号；普通对象（设备端口）不用 ——
			# 它只是线的落脚点。
			if _gpIsConnector(gpPeerNode):
				_gpPeerStampPrior = _gpStampLinkId(gpPeerNode, gpLinkId)
		# The link. Endpoint order: A = local, B = peer.
		# link。端点次序：A = 本端，B = 对端。
		_gpLink = GPOffPageLink.new()
		_gpLink.gpInstanceId = gpLinkId
		_gpLink.gpKind = gpKind
		_gpLink.gpA = {GPOffPageLink.GP_KEY_SHEET: gpLocalSheetId,
			GPOffPageLink.GP_KEY_NODE: gpLocalId,
			GPOffPageLink.GP_KEY_PORT: GPSymbolPackOffpage.GP_PORT_NAME}
		_gpLink.gpB = {GPOffPageLink.GP_KEY_SHEET: gpPeerSheetId,
			GPOffPageLink.GP_KEY_NODE: str(gpPeerRef.get("node_id", "")),
			GPOffPageLink.GP_KEY_PORT: str(gpPeerRef.get("port_id", ""))}
		_gpLink.gpAttrs = gpAttrs
		_gpLink.gpTag = _gpMintTag()
		# INHERIT the contract snapshot from the SOURCE line (user feedback 2026-11-03: the
		# medium below the flag is the source line's medium, automatically — no hand typing).
		# 从**源管线**继承契约快照（用户反馈 2026-11-03：旗标下方的介质就是起始端管线的介质，
		# 自动继承 —— 无需手填）。
		_gpInheritContractAttrs(gpCtx)
		gpCreatedLinkId = gpLinkId
	_gpLinkAt = gpLinks.size()
	if not gpLinks.has(_gpLink):
		gpLinks.append(_gpLink)
	# The link table has no signal of its own; notifying the peer graph keeps ITS canvas
	# current, and the shell republishes the render snapshot after the command returns.
	# link 表自身无信号；通知对端图使其画布保持最新，渲染快照由外壳在命令返回后重发。
	gpPeerGraph.gpNotifyChanged()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	# Reverse order: link first, then the CREATED objects only. Mode B objects that existed
	# before the command are deliberately left alone.
	# 逆序：先 link，再只动**本命令创建的**对象。模式 B 中先于命令存在的对象刻意不动。
	if _gpLink != null and gpLinks != null and gpLinks.has(_gpLink):
		_gpLinkAt = gpLinks.find(_gpLink)
		gpLinks.remove_at(_gpLinkAt)
	if _gpPeerConnect != null and gpPeerGraph != null:
		_gpPeerConnect.gpUndo(GPCommandContext.new(gpPeerGraph, gpCtx.gpIds, gpCtx.gpTags))
	if _gpPeerNode != null and gpPeerGraph != null:
		gpPeerGraph.gpRemoveNode(_gpPeerNode.gpInstanceId)
	elif _gpPeerStampPrior != "" or _gpLink != null:
		# Mode B: restore the peer node's prior props instead of deleting the node.
		# 模式 B：还原对端节点的原 props，而非删除节点。
		if gpPeerGraph != null:
			_gpUnstampLinkId(gpPeerGraph.gpGetNode(str(gpExistingPeerRef.get("node_id", ""))),
				_gpPeerStampPrior)
	if _gpConnect != null:
		_gpConnect.gpUndo(gpCtx)
	if _gpLocalNode != null:
		gpCtx.gpGraph.gpRemoveNode(_gpLocalNode.gpInstanceId)
	elif _gpLocalStampPrior != "" or _gpLink != null:
		# Mode B: restore the local connector's prior props instead of deleting it.
		# 模式 B：还原本端连接符的原 props，而非删除它。
		_gpUnstampLinkId(gpCtx.gpGraph.gpGetNode(gpExistingLocalNodeId), _gpLocalStampPrior)


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	# Re-add the SAME objects in execution order — same ids, same tag, same link.
	# 按执行顺序原样加回 —— 同 id、同位号、同 link。
	if _gpLocalNode != null:
		gpCtx.gpGraph.gpAddNode(_gpLocalNode)
	if _gpConnect != null:
		_gpConnect.gpRedo(gpCtx)
	if _gpPeerNode != null and gpPeerGraph != null:
		gpPeerGraph.gpAddNode(_gpPeerNode)
	if _gpPeerConnect != null and gpPeerGraph != null:
		_gpPeerConnect.gpRedo(GPCommandContext.new(gpPeerGraph, gpCtx.gpIds, gpCtx.gpTags))
	if _gpLink != null and gpLinks != null and not gpLinks.has(_gpLink):
		var gpAt: int = _gpLinkAt if (_gpLinkAt >= 0 and _gpLinkAt <= gpLinks.size()) \
			else gpLinks.size()
		gpLinks.insert(gpAt, _gpLink)
	# Mode B props were unstamped by undo; stamp them again with the SAME link id.
	# 模式 B 的 props 已被撤销抹掉；用**同一个** link id 重新盖章。
	if _gpLink != null and gpExistingLocalNodeId != "":
		_gpStampLinkId(gpCtx.gpGraph.gpGetNode(gpExistingLocalNodeId), _gpLink.gpInstanceId)
	if _gpLink != null and not gpExistingPeerRef.is_empty():
		_gpStampLinkId(gpPeerGraph.gpGetNode(str(gpExistingPeerRef.get("node_id", ""))),
			_gpLink.gpInstanceId)
	if gpPeerGraph != null:
		gpPeerGraph.gpNotifyChanged()


# ============================ private ============================

# The SOURCE line: the edge feeding the LOCAL connector. In mode A it is the edge the command
# itself just drew into the connector; in mode B it is the pipeline that already feeds the
# existing connector. D19 (2026-11-04): PORT-DIRECTED — the inbound "ref" port wins (that is
# where the line the user connected FROM enters); a connector with several ref edges gets the
# first in array order (deterministic), and the attr_split DRC rule is what reports the
# disagreement such a Y deserves. The any-port fallback only serves user-pack connectors
# whose ports do not follow the builtin vocabulary.
# **源管线**：接入本端连接符的那条边。模式 A 下是命令刚画进连接符的边；模式 B 下是已接入
# 既有连接符的管线。D19（2026-11-04）：**按端口定向** —— 入站「ref」口优先（用户接入的线
# 正是从这里进来）；多条 ref 边时按数组顺序取第一条（确定性），这种 Y 形接法的分歧由
# attr_split DRC 规则报告。任意端口回落仅服务于端口不走内置词表的用户包连接符。
func _gpSourceEdge(gpCtx: GPCommandContext) -> GPPIDEdge:
	if gpCtx == null or gpCtx.gpGraph == null:
		return null
	if _gpConnect != null and _gpConnect.gpCreatedId != "":
		return gpCtx.gpGraph.gpGetEdge(_gpConnect.gpCreatedId)
	var gpLocalId: String = str(_gpLink.gpA.get(GPOffPageLink.GP_KEY_NODE, "")) \
		if _gpLink != null else gpExistingLocalNodeId
	if gpLocalId == "":
		return null
	var gpAny: GPPIDEdge = null
	for gpE in gpCtx.gpGraph.gpEdges:
		if gpE == null:
			continue
		var gpFromN: String = str(gpE.gpFromRef.get("node_id", ""))
		var gpToN: String = str(gpE.gpToRef.get("node_id", ""))
		if gpFromN != gpLocalId and gpToN != gpLocalId:
			continue
		# Inbound ref wins; remember the first ANY-port edge as the fallback.
		# 入站 ref 优先；同时记住第一条任意端口边作回落。
		var gpAtRef: bool = (gpFromN == gpLocalId \
				and str(gpE.gpFromRef.get("port_id", "")) == GPSymbolPackOffpage.GP_PORT_NAME) \
			or (gpToN == gpLocalId \
				and str(gpE.gpToRef.get("port_id", "")) == GPSymbolPackOffpage.GP_PORT_NAME)
		if gpAtRef:
			return gpE
		if gpAny == null:
			gpAny = gpE
	return gpAny


# The source line's number ("" for signal lines — they carry none by convention — or when
# no source line exists yet).
# 源管线的编号（信号线按惯例不带号、或尚无源线时为 ""）。
func _gpSourceEdgeTag(gpCtx: GPCommandContext) -> String:
	if gpKind == GPPIDEdge.GP_SIGNAL:
		return ""
	var gpE: GPPIDEdge = _gpSourceEdge(gpCtx)
	return gpE.gpTag if gpE != null else ""


# INHERIT the contract snapshot from the SOURCE line (user feedback 2026-11-03): the first
# edge touching the local connector is that line; its contract attrs seed the link's
# snapshot, and the sync command / DRC take it from there. Only keys the link does not carry
# yet are copied, so re-running stays idempotent and a caller-supplied signal_type survives.
# 从**源管线**继承契约快照（用户反馈 2026-11-03）：触及本端连接符的第一条边就是那根管线；
# 其契约属性为 link 快照播种，此后由同步命令 / DRC 接管。只拷贝 link 尚未携带的键，
# 使重复执行保持幂等、调用方先行的 signal_type 得以存活。
func _gpInheritContractAttrs(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpLink == null:
		return
	var gpE: GPPIDEdge = _gpSourceEdge(gpCtx)
	if gpE == null:
		return
	for gpKey in GPOffPageLink.GP_CONTRACT_KEYS:
		var gpVal: String = str(gpE.gpAttrs.get(gpKey, "")).strip_edges()
		if gpVal == "":
			continue
		if str(_gpLink.gpAttrs.get(gpKey, "")).strip_edges() == "":
			_gpLink.gpAttrs[gpKey] = gpVal


# Undo the LOCAL half (mode A: the created edge + node; mode B: the stamp) — used when the
# PEER half refuses, so a refused gesture leaves NOTHING behind on either sheet.
# 回滚**本端**一半（模式 A：新建的边 + 节点；模式 B：盖的章）—— 对端一半拒绝时使用，
# 使被拒的手势在两张图上都**不**留下任何东西。
func _gpRollbackLocal(gpCtx: GPCommandContext) -> void:
	if _gpConnect != null:
		_gpConnect.gpUndo(gpCtx)
		_gpConnect = null
	if _gpLocalNode != null:
		gpCtx.gpGraph.gpRemoveNode(_gpLocalNode.gpInstanceId)
		_gpLocalNode = null
	elif gpExistingLocalNodeId != "":
		_gpUnstampLinkId(gpCtx.gpGraph.gpGetNode(gpExistingLocalNodeId), _gpLocalStampPrior)
		_gpLocalStampPrior = ""

# Refuse the shapes that have no meaning as a cross-sheet connection.
# 拒绝作为跨图纸连接没有意义的形状。
func _gpValidate(gpCtx: GPCommandContext) -> bool:
	if gpPeerGraph == null:
		gpRefusal = "peer_graph_missing"
		return false
	if gpLinks == null:
		gpRefusal = "links_missing"
		return false
	if gpLocalSheetId == "" or gpPeerSheetId == "":
		gpRefusal = "sheet_missing"
		return false
	if gpLocalSheetId == gpPeerSheetId:
		gpRefusal = "same_sheet"
		return false
	if not _gpValidateLocal(gpCtx):
		return false
	if not _gpValidatePeer():
		return false
	return true


# Local-side checks: in mode A the source must be a bound, existing end; in mode B the
# existing connector must exist and must not already carry ANOTHER live link.
# 本端检查：模式 A 要求源端已绑定且存在；模式 B 要求既有连接符存在，且尚未挂着**另一条**
# 存活的 link（否则旧 link 会被 orphan）。
func _gpValidateLocal(gpCtx: GPCommandContext) -> bool:
	if gpExistingLocalNodeId != "":
		var gpNode: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpExistingLocalNodeId)
		if gpNode == null:
			gpRefusal = "node_missing"
			return false
		var gpCarried: String = str(gpNode.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, ""))
		# A stamp placed by THIS command's own earlier execution is not a conflict — only
		# a link the command does not own would be orphaned by re-stamping.
		# 本命令自己此前执行盖的章不算冲突 —— 只有**不属于本命令**的 link 才会被重盖章变孤儿。
		if gpCarried != "" and not (gpCarried == _gpOwnLinkId()) and _gpLinkIdTaken(gpCarried):
			gpRefusal = "connector_already_linked"
			return false
		return true
	# Mode A: a dangling drop with no bound end cannot become a cross-sheet connection —
	# the twin connector would reference a line that exists on neither sheet.
	# 模式 A：无任何绑定端的悬空落点成不了跨图纸连接 —— 孪生连接符将引用一条在两张图上
	# 都不存在的线。
	var gpFn: String = str(gpFromRef.get("node_id", ""))
	if gpFn == "":
		gpRefusal = "pipe_needs_one_bound"
		return false
	if gpCtx.gpGraph.gpGetNode(gpFn) == null:
		gpRefusal = "node_missing"
		return false
	return true


# Peer-side checks: a mode B peer endpoint or a served item must name an EXISTING node on
# the peer graph — a link pointing at nothing would dangle on the very step that created it.
# 对端检查：模式 B 的对端端点或服务对象都必须指向对端图上**存在**的节点 —— 指向虚无的 link
# 在创建它的那一步就已经悬空。
func _gpValidatePeer() -> bool:
	if not gpExistingPeerRef.is_empty():
		var gpPeerNodeId: String = str(gpExistingPeerRef.get("node_id", ""))
		if gpPeerNodeId == "" or gpPeerGraph.gpGetNode(gpPeerNodeId) == null:
			gpRefusal = "node_missing"
			return false
	if not gpServedRef.is_empty():
		var gpServedId: String = str(gpServedRef.get("node_id", ""))
		if gpServedId == "" or gpPeerGraph.gpGetNode(gpServedId) == null:
			gpRefusal = "node_missing"
			return false
	return true


# The connector symbol for this kind: signal -> hexagon, everything else -> flag.
# 此类型对应的连接符符号：信号 -> 六边形，其余 -> 旗标。
func _gpSymbolId() -> String:
	return GPSymbolPackOffpage.GP_ID_SIGNAL if gpKind == GPPIDEdge.GP_SIGNAL \
		else GPSymbolPackOffpage.GP_ID_PIPE


# Mint a link id that is unique INSIDE the container array. The local sheet's counter is
# only a starting point: another sheet may have minted the same "xlink-N" already.
# 铸一个在容器数组内唯一的 link id。本图纸的计数器只是起点：另一张图纸可能已铸过
# 同样的 "xlink-N"。
func _gpMintLinkId(gpCtx: GPCommandContext) -> String:
	var gpCandidate: String = gpCtx.gpIds.gpNext(GPOffPageLink.GP_ID_PREFIX)
	while _gpLinkIdTaken(gpCandidate):
		gpCandidate = gpCtx.gpIds.gpNext(GPOffPageLink.GP_ID_PREFIX)
	return gpCandidate


func _gpLinkIdTaken(gpCandidate: String) -> bool:
	for gpL in gpLinks:
		if gpL != null and gpL.gpInstanceId == gpCandidate:
			return true
	return false


# The link id this command already minted ("" before the first execute).
# 本命令已铸出的 link id（首次执行前为 ""）。
func _gpOwnLinkId() -> String:
	return _gpLink.gpInstanceId if _gpLink != null else ""


# Auto tag "<peer number>-<seq>"; without a peer number, a bare sequence. Manual edits
# later overwrite it (attrs["tag_manual"]), exactly like edge renumbering.
# 自动编号「<对端图号>-<序号>」；无对端图号时为纯序号。之后可手改覆盖
# （attrs["tag_manual"]），沿用边重编号的既有惯例。
func _gpMintTag() -> String:
	var gpSeq: int = gpLinks.size() + 1
	if gpPeerNumber == "":
		return str(gpSeq)
	return gpPeerNumber + "-" + str(gpSeq)


# Stamp the link id into an existing node's props and return the PRIOR value ("" when the
# key was absent), so undo can restore exactly what was there.
# 把 link id 盖进既有节点的 props，并返回**原值**（键原本不存在时为 ""），
# 使撤销能精确还原。
func _gpStampLinkId(gpNode: GPPIDNode, gpLinkId: String) -> String:
	if gpNode == null:
		return ""
	var gpPrior: String = str(gpNode.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, ""))
	gpNode.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = gpLinkId
	return gpPrior


# Restore a stamped node's prior props value; an absent prior key is removed again.
# 还原被盖章节点的原 props 值；原键不存在时再次删除。
func _gpUnstampLinkId(gpNode: GPPIDNode, gpPrior: String) -> void:
	if gpNode == null:
		return
	if gpPrior == "":
		if (gpNode.gpProps as Dictionary).has(GPOffPageLink.GP_KEY_LINK_ID):
			gpNode.gpProps.erase(GPOffPageLink.GP_KEY_LINK_ID)
	else:
		gpNode.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = gpPrior


# Whether a node is an off-page CONNECTOR (the two builtin ids; a user pack connector that
# already carries a link_id also counts, since its props prove its role).
# 节点是否为跨图纸**连接符**（两个内置 id；已带 link_id 的用户包连接符同样算 ——
# 其 props 已证明身份）。
func _gpIsConnector(gpNode: GPPIDNode) -> bool:
	if gpNode == null:
		return false
	if gpNode.gpSymbolId == GPSymbolPackOffpage.GP_ID_PIPE \
			or gpNode.gpSymbolId == GPSymbolPackOffpage.GP_ID_SIGNAL:
		return true
	return (gpNode.gpProps as Dictionary).has(GPOffPageLink.GP_KEY_LINK_ID)
