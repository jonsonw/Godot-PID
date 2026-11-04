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
static func gpSetContext(gpLinks: Array[GPOffPageLink], gpSheetNumbers: Dictionary,
		gpGraphs: Dictionary = {}) -> void:
	_gpLinks = gpLinks
	_gpSheetNumbers = gpSheetNumbers
	_gpGraphs = gpGraphs


# Drop the snapshot (document closed / tests). A later render resolves to GP_UNRESOLVED_TEXT.
# 清空快照（文档关闭 / 测试）。此后的渲染解析为 GP_UNRESOLVED_TEXT。
static func gpClear() -> void:
	_gpLinks = []
	_gpSheetNumbers = {}
	_gpGraphs = {}


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


# The text an off-page connector displays. THREE distinct states, deliberately not collapsed:
#   * no link_id          -> ""  — a freshly placed connector, not linked yet (nothing to say);
#   * link_id but no link,
#     or no peer sheet no.-> GP_UNRESOLVED_TEXT — a dangling reference (S4 flags it as ERROR);
#   * resolved            -> the link's cross-reference TAG when it has one (ADR-43 D4,
#                            "<peer sheet>-<seq>"), else the peer DRAWING NUMBER.
# 跨图纸连接符显示的文字。三态刻意不合并：未连线（空）／悬空引用（问号，S4 报 ERROR）／已解析
# （优先 link 的跨图编号 tag —— ADR-43 D4 的「<对端图号>-<序号>」—— 否则对端图号）。
#
# WHY THE TAG WINS OVER THE BARE NUMBER / 为何 tag 优先于裸图号：
# The tag is the number the drawing's own cross-reference list quotes, and it already begins with
# the peer sheet number, so showing it loses nothing and adds the sequence. A bare number is the
# fallback for a link created before numbering ran.
# tag 就是图面交叉索引表引用的那个号，且它本身已以对端图号开头，故显示它不损失信息、还多出序号；
# 裸图号是「编号尚未运行时建立的 link」的回落。
static func gpRefTextFor(gpNode: GPPIDNode) -> String:
	if gpNode == null:
		return ""
	var gpLinkId: String = str(gpNode.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, ""))
	if gpLinkId == "":
		return ""
	var gpLink: GPOffPageLink = gpLinkById(gpLinkId)
	if gpLink == null:
		return GP_UNRESOLVED_TEXT
	if gpLink.gpTag != "":
		return gpLink.gpTag
	var gpPeer: Dictionary = gpPeerRefOf(gpLink, gpNode.gpInstanceId)
	var gpNo: String = gpSheetNumber(str(gpPeer.get(GPOffPageLink.GP_KEY_SHEET, "")))
	return gpNo if gpNo != "" else GP_UNRESOLVED_TEXT


# The tag the link's TARGET end serves (user feedback 2026-11-03: the flag's top line). Both
# connectors of one link show the SAME tag — the item the connection points at on the sheet
# it goes to:
#   * the B end is a plain item          -> its own tag;
#   * the B end is a connector (the twin)-> the tag of the item across ITS edge;
#   * anything unresolvable              -> "" (a blank slot, never a guess).
# link **目标端**所服务的位号（用户反馈 2026-11-03：旗标上一行）。一条 link 的两个连接符显示
# **同一个**位号 —— 连接所指向的、目标图纸上那台设备 / 仪表 / 管线：
#   * B 端是普通对象 -> 它自己的位号；
#   * B 端是连接符（孪生体）-> 横过它那条边后的对象位号；
#   * 一切无法解析 -> ""（空槽位，绝不臆造）。
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
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpLink, _gpSheetNumbers, _gpGraphs)
	return str(gpOut.get("target_tag", ""))


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
		gpConnectorIds: Array[String]) -> Vector2:
	if gpFrame.size == Vector2.ZERO or gpEnv.x <= 0.0 or gpEnv.y <= 0.0:
		return Vector2.ZERO
	var gpColX: float = gpFrame.position.x + gpEnv.x * 0.55
	var gpBandRight: float = gpFrame.position.x + gpFrame.size.x * 0.3
	var gpBottom: float = -1e9
	var gpHas: bool = false
	if gpGraph != null:
		for gpN in gpGraph.gpNodes:
			if gpN == null or not gpConnectorIds.has(gpN.gpSymbolId):
				continue
			if gpN.gpPosition.x > gpBandRight:
				continue
			gpHas = true
			gpBottom = maxf(gpBottom, gpN.gpPosition.y)
	if not gpHas:
		return Vector2(gpColX, gpFrame.position.y + gpEnv.y * 1.5)
	# Pitch = 3 envelope heights: the glyph itself plus clearance for the ABOVE/BELOW legend
	# slots, which reach ~1 text height beyond the envelope on each side.
	# 行距 = 3 倍包络高：字形本身，加上 / 下**图例槽位**的净空 —— 它们各自越出包络约一个字高。
	return Vector2(gpColX, gpBottom + gpEnv.y * 3.0)
