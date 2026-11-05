class_name GPOffPageIndex
extends RefCounted
# Copyright © 2026 Jonson Wang
# Session index that answers ONE question for the render layer: "which sheet does this off-page
# connector point at?" (ADR-43 D3 — the peer sheet number is DERIVED, never stored).
# 会话级索引，只为渲染层回答一个问题：「这个跨图纸连接符指向哪张图？」（ADR-43 D3 ——
# 对端图纸号是**推导**出来的，绝不存储）。
#
# WHY A SESSION INDEX AND NOT A PARAMETER / 为何用会话索引而非参数：
# The value is needed inside `GPSymbolView._draw` and inside `GPPrintModel`, both of which see
# only (def, node). The link table lives at the CONTAINER level (center_area.gpOffPageLinks), one
# level above any sheet, so it cannot travel down the node. Pushing it here is exactly the device
# GPSymbolLibrary.gpDocSizeScale already uses for the same reason (one document active at a time,
# the owner pushes a snapshot, every consumer reads it without new plumbing).
# 该取值在 `GPSymbolView._draw` 与 `GPPrintModel` 内部被需要，而两者只看得到 (def, node)。
# link 表属于**容器**层（center_area.gpOffPageLinks），在任何图纸之上，无法随节点下传。
# 放在这里正是 GPSymbolLibrary.gpDocSizeScale 为同一原因所用的手法（同一时刻只有一个文档，
# 持有者推快照，所有消费方读取而无需新增布线）。
#
# STALENESS / 陈旧性：the owner (GPCenterArea.gpRefreshOffPageContext) must re-push whenever the
# link table, the sheet list or a sheet's number changes. A stale snapshot degrades to a WRONG
# NUMBER ON A FLAG, never to a wrong link in the file — the document itself never reads this index.
# 陈旧性：持有者（GPCenterArea.gpRefreshOffPageContext）必须在 link 表 / 图纸列表 / 图号变化时
# 重新推送。快照陈旧只会让**旗标上的数字**不对，绝不会改动文件里的连接 —— 文档本身从不读本索引。
#
# Coding rule: every variable declares its type explicitly; every function is static (pure
# except for the two explicit setters).
# 编码规范：全变量显式类型；除两个显式 setter 外，函数均为静态纯函数。

# The container's links, by reference (never copied — the owner owns them).
# 容器的连接表，按引用持有（绝不复制 —— 归持有者所有）。
static var _gpLinks: Array[GPOffPageLink] = []

# sheet_id -> drawing number (GPSheet.gpNumber), as a plain String.
# sheet_id -> 图号（GPSheet.gpNumber），纯字符串。
static var _gpSheetNumbers: Dictionary = {}

# sheet_id -> graph, so DERIVED texts can reach the nodes on the other end (user feedback
# 2026-11-03: the flag's top line is the TARGET end's tag, which lives on the peer sheet).
# Held by reference, same as the link table.
# sheet_id -> 图，使**推导**文字能到达另一端的节点（用户反馈 2026-11-03：旗标上一行是
# **目标端**位号，而它活在 对端图纸上）。与 link 表一样按引用持有。
static var _gpGraphs: Dictionary = {}

# Optional symbol-def lookup (node -> category voice for the served walk, ADR-45 D2d).
# 可选的符号定义查找（为 served 行走提供类别声音，ADR-45 D2d）。
static var _gpDefLookup: Callable = Callable()

# What a connector shows when it HAS a link_id but the link / peer cannot be resolved.
# A question mark, not an error shout: an off-page flag without a reference is an INCOMPLETE
# drawing (mid-edit), which is legal; DRC (`drc.offpage.unpaired`, S4) is what reports it.
# 连接符**有** link_id 但 link / 对端无法解析时显示的内容。用问号而非感叹号：没有编号的跨页旗标
# 是一张**未完成**的图（编辑中间态），这是合法的；由 DRC（`drc.offpage.unpaired`，S4）报告。
const GP_UNRESOLVED_TEXT: String = "?"


# Install the current container snapshot. Called by the owner after any change to either half.
# 安装当前容器快照。持有者在那两半任一处变化后调用。
# [param gpLinks] The container's link array (kept by reference).
# [param gpLinks] 容器的 link 数组（按引用保留）。
# [param gpSheetNumbers] {sheet_id: drawing number}, only the sheets that HAVE a number.
# [param gpSheetNumbers] {sheet_id: 图号}，仅包含确有图号的图纸。
# [param gpGraphs] {sheet_id: GPPIDGraph}, for deriving texts that reach across sheets.
# [param gpGraphs] {sheet_id: GPPIDGraph}，供跨图推导文字使用。
# [param gpDefLookup] optional symbol-id -> GPSymbolDef callable, feeding the served walk's
# device categories (ADR-45 D2d). Omitted -> the tag is the only voice.
# [param gpDefLookup] 可选的 符号id -> GPSymbolDef 调用，为 served 行走的设备类别供数
#（ADR-45 D2d）。省略 → 位号是唯一声音。
static func gpSetContext(gpLinks: Array[GPOffPageLink], gpSheetNumbers: Dictionary,
		gpGraphs: Dictionary = {}, gpDefLookup: Callable = Callable()) -> void:
	_gpLinks = gpLinks
	_gpSheetNumbers = gpSheetNumbers
	_gpGraphs = gpGraphs
	_gpDefLookup = gpDefLookup


# Drop the snapshot (document closed / tests). A later render resolves to GP_UNRESOLVED_TEXT.
# 清空快照（文档关闭 / 测试）。此后的渲染解析为 GP_UNRESOLVED_TEXT。
static func gpClear() -> void:
	_gpLinks = []
	_gpSheetNumbers = {}
	_gpGraphs = {}
	_gpDefLookup = Callable()


# The drawing number of a sheet, or "" when the sheet is unknown or unnumbered.
# 某图纸的图号；未知或未编号时返回 ""。
static func gpSheetNumber(gpSheetId: String) -> String:
	if gpSheetId == "":
		return ""
	return str(_gpSheetNumbers.get(gpSheetId, ""))


# ---- sheet ordering & labels (shared by the connect dialog AND the inspector's peer-sheet
# dropdown — one copy, so the two pickers can never fall out of order) ----
# ---- 图纸排序与标签（连接对话框**与**属性面板的对端图纸下拉共用 —— 只此一份，
# 两个选择器的次序永不分家）----

# Numeric-aware sheet order: "2" before "10"; sheets without a number keep file order behind
# numbered ones.
# 数字感知的图纸次序："2" 在 "10" 前；无图号的图纸排在有图号的之后，保持文件次序。
static func gpSheetBefore(gpA: GPSheet, gpB: GPSheet) -> bool:
	var gpNa: int = gpLeadingNumber(gpA.gpNumber)
	var gpNb: int = gpLeadingNumber(gpB.gpNumber)
	if gpNa != gpNb:
		return gpNa < gpNb
	if (gpA.gpNumber == "") != (gpB.gpNumber == ""):
		return gpB.gpNumber == ""
	return gpA.gpIndex < gpB.gpIndex


# The leading digit run of a drawing number ("P-03" -> 3); unnumbered sorts last.
# 图号的前导数字串（"P-03" → 3）；无图号者排最后。
static func gpLeadingNumber(gpS: String) -> int:
	var gpOut: String = ""
	for gpC in gpS:
		if gpC >= "0" and gpC <= "9":
			gpOut += gpC
		elif gpOut != "":
			break
	return int(gpOut) if gpOut != "" else 2147483647


# The shared picker label: "number · name", falling back to the ordinal position when the
# sheet carries no drawing number (a picker row of just "·" would be unreadable).
# 共用的选择器标签："图号 · 名称"；无图号的图纸回退用序号（只有「·」的选择器行没法读）。
static func gpSheetLabel(gpS: GPSheet) -> String:
	var gpNo: String = gpS.gpNumber.strip_edges()
	if gpNo == "":
		gpNo = str(gpS.gpIndex + 1)
	return gpNo + " · " + gpS.gpName


# The link that carries gpNodeId on one of its ends, or null.
# 以 gpNodeId 为其一端的那条 link；无则 null。
# An instance id is unique across the container (ADR-17), so the node alone identifies the link;
# the sheet half of the ref is NOT consulted here — a connector copied onto another sheet keeps
# its link_id and must still resolve (DRC's duplicate rule reports that case).
# 实例 id 在容器内唯一（ADR-17），故仅凭节点即可定位 link；此处**不**比对 ref 的图纸一半 ——
# 被复制到另一张图纸的连接符仍带着 link_id，必须仍能解析（该情形由 DRC 的重复规则报告）。
static func gpLinkForNode(gpNodeId: String) -> GPOffPageLink:
	if gpNodeId == "":
		return null
	for gpLink in _gpLinks:
		if gpLink == null:
			continue
		if str(gpLink.gpA.get(GPOffPageLink.GP_KEY_NODE, "")) == gpNodeId:
			return gpLink
		if str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, "")) == gpNodeId:
			return gpLink
	return null


# The link with this id, or null. / 按 id 取 link；无则 null。
static func gpLinkById(gpLinkId: String) -> GPOffPageLink:
	if gpLinkId == "":
		return null
	for gpLink in _gpLinks:
		if gpLink != null and gpLink.gpInstanceId == gpLinkId:
			return gpLink
	return null


# The FAR end of a link relative to one of its nodes: {sheet_id, node_id, port_id}, or {} when
# gpNodeId is not an end of gpLink.
# 相对某一端而言 link 的**另一端**：{sheet_id, node_id, port_id}；gpNodeId 不是该 link 的端时返回 {}。
static func gpPeerRefOf(gpLink: GPOffPageLink, gpNodeId: String) -> Dictionary:
	if gpLink == null or gpNodeId == "":
		return {}
	if str(gpLink.gpA.get(GPOffPageLink.GP_KEY_NODE, "")) == gpNodeId:
		return gpLink.gpB
	if str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, "")) == gpNodeId:
		return gpLink.gpA
	return {}


# Drawing number of the sheet this connector's link points AT ("" when unresolvable).
# 该连接符所指图纸的图号（无法解析时 ""）。
static func gpPeerSheetNumberOf(gpNodeId: String) -> String:
	var gpLink: GPOffPageLink = gpLinkForNode(gpNodeId)
	if gpLink == null:
		return ""
	var gpPeer: Dictionary = gpPeerRefOf(gpLink, gpNodeId)
	return gpSheetNumber(str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")))


# The text an off-page connector displays INSIDE the flag. THREE distinct states, deliberately
# not collapsed:
#   * no link_id          -> ""  — a freshly placed connector, not linked yet (nothing to say);
#   * link_id but no link,
#     or no peer sheet no.-> GP_UNRESOLVED_TEXT — a dangling reference (S4 flags it as ERROR);
#   * resolved            -> the PEER DRAWING NUMBER relative to THIS end (user feedback
#                            2026-11-04, round 3): the source flag says where the line GOES,
#                            the twin says where it comes FROM. The link's cross-reference tag
#                            ("<peer>-<seq>") no longer rides the flag — it remains the
#                            cross-reference-table / report identity (ADR-45 D2c).
# 跨图纸连接符**框内**显示的文字。三态刻意不合并：未连线（空）／悬空引用（问号，S4 报 ERROR）／
# 已解析（**相对本端**的对端图号 —— 用户反馈 2026-11-04 第三轮：源端旗标说线**去哪**、孪生体
# 说线**从哪来**）。link 的交叉编号（「<对端图号>-<序号>」）不再上旗标 —— 它仍是交叉索引表 /
# 报表里的身份（ADR-45 D2c）。
#
# WHY PER-END AND NOT THE SHARED TAG / 为何逐端而非共享 tag：
# the stored tag is authored from the A perspective, so the twin quoting it would name its OWN
# sheet — the opposite of "where the line comes from". A per-end derivation has exactly one
# answer per connector and no second copy to drift.
# 存储的 tag 是从 A 端视角铸的，孪生体引用它只会念出**自己**那张图 —— 恰与「线从哪来」相反。
# 逐端推导对每个连接符恰有一个答案，不存在会漂移的第二份副本。
static func gpRefTextFor(gpNode: GPPIDNode) -> String:
	if gpNode == null:
		return ""
	var gpLinkId: String = str(gpNode.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, ""))
	if gpLinkId == "":
		return ""
	var gpLink: GPOffPageLink = gpLinkById(gpLinkId)
	if gpLink == null:
		return GP_UNRESOLVED_TEXT
	var gpPeer: Dictionary = gpPeerRefOf(gpLink, gpNode.gpInstanceId)
	var gpNo: String = gpSheetNumber(str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")))
	return gpNo if gpNo != "" else GP_UNRESOLVED_TEXT


# The tag the link's TARGET end serves — the LINK-CENTRIC view (reports / DRC read it from
# the A perspective). Kept alongside gpPeerTagFor: for the A-end connector the two agree.
# link **目标端**所服务的位号 —— **link 中心**视角（报表 / DRC 从 A 端视角读它）。与
# gpPeerTagFor 并存：对 A 端连接符二者一致。
#   * the B end is a plain item          -> its own tag;
#   * the B end is a connector (the twin)-> the tag of the item across ITS edge;
#   * anything unresolvable              -> "" (a blank slot, never a guess).
#   * B 端是普通对象 -> 它自己的位号；B 端是连接符（孪生体）-> 横过它那条边后的对象位号；
#     一切无法解析 -> ""（空槽位，绝不臆造）。
static func gpTargetTagFor(gpNode: GPPIDNode) -> String:
	if gpNode == null:
		return ""
	var gpLink: GPOffPageLink = gpLinkForNode(gpNode.gpInstanceId)
	if gpLink == null:
		return ""
	# A3: the derivation itself lives in GPOffPageResolver (explicit context, pure); this
	# index is only the UI's cache shell feeding the current snapshot in. One copy of the
	# semantics — the renderer, print model, DRC and the W22 exporter all share it.
	# A3：推导本体住在 GPOffPageResolver（显式上下文、纯函数）；本索引只是喂入当前快照的
	# UI **缓存壳**。语义只有一份 —— 渲染器、打印模型、DRC 与 W22 导出器共享它。
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpLink, _gpSheetNumbers, _gpGraphs,
		_gpDefLookup)
	return str(gpOut.get("target_tag", ""))


# The tag of the item THIS connector's PEER end serves — the PER-CONNECTOR top legend line
# (ADR-45 D2a, user feedback 2026-11-04): the source connector shows what the far sheet
# receives, the twin shows where the line comes FROM (the source equipment / instrument
# tag). The old "both ends show the same target tag" contract failed the real-machine
# check: a reader of the TARGET sheet needs the SOURCE device's tag, not its own.
# 本连接符**对端**所服务对象的位号 —— **逐连接符**的图例上一行（ADR-45 D2a，2026-11-04
# 实机反馈）：源端连接符显示对端图纸接收什么、孪生体显示线**从哪台设备来**（源端设备 /
# 仪表位号）。旧的「两端同显目标位号」契约未过实机验证：目标图的读图人需要的是**源端**
# 设备位号，而不是自己这一侧的。
static func gpPeerTagFor(gpNode: GPPIDNode) -> String:
	if gpNode == null:
		return ""
	var gpLink: GPOffPageLink = gpLinkForNode(gpNode.gpInstanceId)
	if gpLink == null:
		return ""
	var gpFar: Dictionary = gpPeerRefOf(gpLink, gpNode.gpInstanceId)
	if gpFar.is_empty():
		return ""
	return GPOffPageResolver.gpServedTagFor(gpFar, _gpSheetNumbers, _gpGraphs, _gpDefLookup)


# Whether THIS connector's flag is BROKEN — it claims a link (link_id set) but the reference
# does not resolve ("?"): either the link left the table (a stale claim after a reconnect —
# user feedback 2026-11-05) or the peer sheet has no drawing number. The renderer paints the
# flag amber (D20) and the attached line amber through this one predicate — one copy of the
# "this continuation is broken" voice for both.
# 该连接符的旗标是否**已断** —— 它声称一条 link（link_id 在）但引用解析不到（「?」）：
# 要么 link 已离开表（重连后的陈旧声称 —— 用户反馈 2026-11-05），要么对端图纸没有图号。
# 渲染器经**这一个**判谓把旗标（D20 琥珀）与所连管线一并染琥珀 —— 「这段延续已断」的
# 声音只有一份。
static func gpFlagBrokenFor(gpNode: GPPIDNode) -> bool:
	if gpNode == null:
		return false
	if not (gpNode.gpProps as Dictionary).has(GPOffPageLink.GP_KEY_LINK_ID):
		return false
	return gpRefTextFor(gpNode) == GP_UNRESOLVED_TEXT


# The DERIVED medium of this connector's link (ADR-45 D2b): the A end's served edge carries
# the LIVE attribute — a medium edited on the line after creation shows up without any
# sync ritual; the link's seeded snapshot is only the old-file fallback.
# 本连接符所在 link 的**派生**介质（ADR-45 D2b）：A 端服务边携带**活的**边属性 —— 创建后
# 再改介质即刻跟上，无需同步仪式；link 播种快照只是旧档回落。
static func gpMediumFor(gpNode: GPPIDNode) -> String:
	if gpNode == null:
		return ""
	var gpLink: GPOffPageLink = gpLinkForNode(gpNode.gpInstanceId)
	if gpLink == null:
		return ""
	return GPOffPageResolver.gpMediumOf(gpLink, _gpSheetNumbers, _gpGraphs)


# ---- auto placement / 自动落位 ------------------------------------------
# ---- 目标图纸左列的下一个槽位（用户反馈 2026-11-03：目标图纸上的连接符永远在左侧、
# 多个自上而下自动排布）----

# The next free slot in a sheet's LEFT connector column. Pure geometry + graph scan:
#   * x — a fixed column near the frame's left edge, sized from the envelope;
#   * y — below the LOWEST connector already living in the column (they stack top-down);
#     an empty column starts near the frame's top.
# A flag the user parked OUTSIDE the column never dictates the stacking — the column belongs
# to the auto-placed family.
# 图纸**左列**的下一个空槽位。纯几何 + 图扫描：
#   * x —— 紧贴图框左缘的固定列，由包络定尺寸；
#   * y —— 已在列中的**最低**连接符之下（自上而下堆叠）；空列从图框顶部附近起排。
# 用户停在列**外**的旗标不参与堆叠 —— 这一列属于自动落位家族。
static func gpNextLeftSlot(gpGraph: GPPIDGraph, gpFrame: Rect2, gpEnv: Vector2,
		gpIsConnector: Callable) -> Vector2:
	return gpNextEdgeSlot(gpGraph, gpFrame, gpEnv, gpIsConnector, "left")


# D17 (2026-11-04, R4): the drop point picks the NEAREST frame edge, and the local flag snaps
# into THAT edge's connector column/row — same stacking family as the left column. The drop
# point only decides WHICH side; it never places the flag itself (no outside-the-frame
# prints, no flags sitting on the frame line).
# D17（2026-11-04，R4）：松手点只选**最近的图框边**，本端旗标吸附进**该边**的连接符
# 列/行 —— 与左列同一套堆叠家族。松手点只决定走向哪一侧；旗标本身绝不落在松手点上
#（杜绝出纸打印、杜绝压线旗标）。
static func gpSnapSlotFor(gpWorld: Vector2, gpGraph: GPPIDGraph, gpFrame: Rect2,
		gpEnv: Vector2, gpIsConnector: Callable) -> Vector2:
	if gpFrame.size == Vector2.ZERO:
		return gpWorld
	var gpSides: Array = [
		{"side": "left", "d": absf(gpWorld.x - gpFrame.position.x)},
		{"side": "right", "d": absf(gpWorld.x - gpFrame.end.x)},
		{"side": "top", "d": absf(gpWorld.y - gpFrame.position.y)},
		{"side": "bottom", "d": absf(gpWorld.y - gpFrame.end.y)},
	]
	gpSides.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
		return float(gpA["d"]) < float(gpB["d"]))
	return gpNextEdgeSlot(gpGraph, gpFrame, gpEnv, gpIsConnector, str(gpSides[0]["side"]))


# The next free slot ON ONE FRAME SIDE. Pure geometry + graph scan:
#   * vertical sides (left/right) — a fixed column hugging the edge, stacking TOP-DOWN below
#     the lowest member already in that side's band;
#   * horizontal sides (top/bottom) — a fixed row, stacking LEFT-TO-RIGHT after the
#     rightmost member in the band.
# 某一条图框边上的下一个空槽位。纯几何 + 图扫描：
#   * 竖边（左/右）—— 紧贴边缘的固定列，在该侧带内的**最低**成员之下自上而下堆叠；
#   * 横边（上/下）—— 固定行，在该侧带内**最右**成员之右自左向右堆叠。
static func gpNextEdgeSlot(gpGraph: GPPIDGraph, gpFrame: Rect2, gpEnv: Vector2,
		gpIsConnector: Callable, gpSide: String) -> Vector2:
	if gpFrame.size == Vector2.ZERO or gpEnv.x <= 0.0 or gpEnv.y <= 0.0:
		return Vector2.ZERO
	var gpVertical: bool = gpSide == "left" or gpSide == "right"
	var gpColX: float = 0.0
	var gpRowY: float = 0.0
	var gpBandFar: float = 0.0
	if gpSide == "left":
		gpColX = gpFrame.position.x + gpEnv.x * 0.55
		gpBandFar = gpFrame.position.x + gpFrame.size.x * 0.3
	elif gpSide == "right":
		gpColX = gpFrame.end.x - gpEnv.x * 0.55
		gpBandFar = gpFrame.end.x - gpFrame.size.x * 0.3
	elif gpSide == "top":
		gpRowY = gpFrame.position.y + gpEnv.y * 0.55
		gpBandFar = gpFrame.position.y + gpFrame.size.y * 0.3
	else:
		gpRowY = gpFrame.end.y - gpEnv.y * 0.55
		gpBandFar = gpFrame.end.y - gpFrame.size.y * 0.3
	var gpFar: float = -1e9
	var gpHas: bool = false
	if gpGraph != null:
		for gpN in gpGraph.gpNodes:
			# D16 (2026-11-04): the column member test is the PREDICATE the caller hands in —
			# "def category == offpage" (+ the props-link_id fallback for user-pack
			# connectors), NOT a builtin symbol-id list. A custom/derived connector now
			# stacks instead of overlapping.
			# D16（2026-11-04）：列成员判定交给调用方注入的**判谓** —— 「def 类别 == offpage」
			#（外加用户包连接符的 props-link_id 兜底），而非内置符号 id 名单。自定义/派生
			# 连接符从此参与堆叠而不是相互重叠。
			if gpN == null or not bool(gpIsConnector.call(gpN)):
				continue
			# A member of THIS side's band only; a flag parked elsewhere never dictates it.
			# 只算**本侧**带内的成员；停在别处的旗标不参与。
			var gpInBand: bool = (gpN.gpPosition.x <= gpBandFar) if gpSide == "left" \
				else (gpN.gpPosition.x >= gpBandFar) if gpSide == "right" \
				else (gpN.gpPosition.y <= gpBandFar) if gpSide == "top" \
				else (gpN.gpPosition.y >= gpBandFar)
			if not gpInBand:
				continue
			gpHas = true
			# Vertical sides stack along Y (below the lowest); horizontal sides along X.
			# 竖边沿 Y 堆叠（最低者之下）；横边沿 X 堆叠。
			gpFar = maxf(gpFar, gpN.gpPosition.y if gpVertical else gpN.gpPosition.x)
	if not gpHas:
		if gpVertical:
			return Vector2(gpColX, gpFrame.position.y + gpEnv.y * 1.5)
		return Vector2(gpFrame.position.x + gpEnv.x * 1.5, gpRowY)
	# Pitch = 3 envelope heights: the glyph itself plus clearance for the ABOVE/BELOW legend
	# slots, which reach ~1 text height beyond the envelope on each side.
	# 行距 = 3 倍包络高：字形本身，加上 / 下**图例槽位**的净空 —— 它们各自越出包络约一个字高。
	if gpVertical:
		return Vector2(gpColX, gpFar + gpEnv.y * 3.0)
	return Vector2(gpFar + gpEnv.x * 3.0, gpRowY)


# The SHARED connector predicate (D16): a node is a column member when its definition says
# category "offpage", or — for a user-pack symbol without a def — when its props carry a
# link_id (the props prove the role, the same rule the create command applies).
# 共享的连接符判谓（D16）：定义类别为 "offpage" 即列成员；无定义的用户包符号以 props 里的
# link_id 兜底（props 证明身份 —— 与创建命令同一条规则）。
static func gpIsConnectorNode(gpNode: GPPIDNode, gpDefLookup: Callable) -> bool:
	if gpNode == null:
		return false
	if gpDefLookup.is_valid():
		var gpDef: GPSymbolDef = gpDefLookup.call(gpNode.gpSymbolId) as GPSymbolDef
		if gpDef != null:
			return gpDef.gpCategory == "offpage"
	return (gpNode.gpProps as Dictionary).has(GPOffPageLink.GP_KEY_LINK_ID)


# Where a cross-sheet line may LAND on a host item (user feedback 2026-11-05, round 7):
# its MOUNTED NOZZLES, one ref {node_id, port_id, nozzle_id, tag, anchor} per nozzle — the
# line must land on a nozzle, never straight on the equipment body. Each ref's node is the
# NOZZLE itself (the served edge connects to the nozzle's own line port), so the flag's
# served walk then hops the mount relation to the equipment (the round-6 rule). Non-nozzle
# children (manholes, blinds …) are not line landing points and never appear. Pure.
# 跨图纸管线在宿主对象上的**落点**（用户反馈 2026-11-05 第七轮）：它**挂载的管口**，
# 每枚管口一个引用 {node_id, port_id, nozzle_id, tag, anchor} —— 线必须落在管口上，
# 绝不直连设备本体。每个引用的节点就是**管口本身**（服务边接到管口自己的管线端口），
# 旗标的 served 行走随后经挂载关系跳到设备（第六轮规则）。非管口子件（人孔、盲板……）
# 不是管线落点，绝不出现。纯函数。
static func gpNozzleLandingRefs(gpGraph: GPPIDGraph, gpHostUid: String,
		gpDefLookup: Callable) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpGraph == null or gpHostUid == "":
		return gpOut
	for gpChild in GPMountResolver.gpChildrenOf(gpGraph, gpHostUid):
		if gpChild == null:
			continue
		var gpDef: GPSymbolDef = null
		if gpDefLookup.is_valid():
			gpDef = gpDefLookup.call(gpChild.gpSymbolId) as GPSymbolDef
		if gpDef == null or gpDef.gpMountKind != "NOZZLE":
			continue
		# The nozzle's LINE port: the def's first NOZZLE-type port, else its first port.
		# 管口的**管线**端口：定义里第一个 NOZZLE 型端口，否则第一个端口。
		var gpPort: String = ""
		for gpP in gpDef.gpPorts:
			if gpP != null and gpP.gpType == GPPort.GP_NOZZLE:
				gpPort = gpP.gpName
				break
		if gpPort == "" and not gpDef.gpPorts.is_empty() and gpDef.gpPorts[0] != null:
			gpPort = gpDef.gpPorts[0].gpName
		if gpPort == "":
			continue
		gpOut.append({"node_id": gpChild.gpInstanceId, "port_id": gpPort,
			"nozzle_id": str(gpChild.gpProps.get("nozzle_id", "")),
			"tag": str(gpChild.gpTag), "anchor": gpChild.gpMountAnchor})
	return gpOut
