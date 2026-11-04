class_name GPOffPageResolver
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# A3 (W12 closure plan §4.3): the DERIVED resolution of ONE link as a pure function with an
# EXPLICIT context. Every consumer — renderer, print model, DRC, the future DEXPI exporter
# (W22) and reports (K03) — reads THIS one answer instead of re-deriving the same semantics
# in four places (the drift GPOffPageIndex's static snapshot made possible).
# A3（W12 收口方案 §4.3）：**一条 link 的派生解析** —— 带显式上下文的纯函数。渲染器、打印
# 模型、DRC、未来的 DEXPI 导出器（W22）与报表（K03）都读**这一份**答案，而不是在四处各自
# 重新推导同一份语义（静态快照曾允许的那种漂移）。
#
# EXPLICIT CONTEXT (A6 seed): the caller passes {sheet numbers, sheet graphs}; no global
# "current document" is consulted. GPOffPageIndex remains the UI's CACHE SHELL (it owns a
# snapshot and delegates to these functions) — CLI, batch runs and tests can resolve without
# ever touching gpSetContext's timing.
# **显式上下文**（A6 种子）：调用方传入 {图号表, 图表}；不查询任何全局「当前文档」。
# GPOffPageIndex 仍是 UI 的**缓存壳**（持有快照并委托给这些函数）—— CLI、批处理与测试
# 无需触碰 gpSetContext 的时序即可解析。
#
# The display CONTRACT this resolver pins is normative for ADR-45 (drafted alongside):
#   * three states, never collapsed: unlinked (""), dangling ("?"), resolved (tag/number);
#   * the target tag is DERIVED at read time (ADR-43 D3) — never a stored field;
#   * each connector's top legend line is the PEER end's served tag (ADR-45 D2a, user
#     feedback 2026-11-04): the source connector shows what the B end serves, the twin shows
#     what the A end serves — "where the line comes from / where it goes".
# 本解析钉住的**展示契约**对（同步起草的）ADR-45 具有规范性：三态永不合并；目标位号在
# 读取期**推导**（ADR-43 D3），绝不是存储字段；每个连接符的图例上一行是**其对端**所服务
# 对象的位号（ADR-45 D2a，2026-11-04 实机反馈）：源端连接符显示 B 端所服务者，孪生体显示
# A 端所服务者 —— 「线从哪台设备来 / 去往哪台设备」。
#
# Coding rule: every variable declares its type explicitly; all functions static & pure.
# 编码规范：全变量显式类型；全部函数为静态纯函数。


# Resolve ONE link. [param gpNumbers] is {sheet_id: drawing number}; [param gpGraphs] is
# {sheet_id: GPPIDGraph}. Returns:
#   a / b           the link's own endpoint refs (verbatim);
#   a_dangling      TRUE when the A end cannot be resolved in this context;
#   b_dangling      same for the B end;
#   peer_number     the B-end sheet's drawing number ("" when unknown — the A-view "peer");
#   target_tag      the tag of the item the B end serves ("" when unresolvable — the LINK-
#                   centric view reports read; per-connector display uses gpServedTagFor);
#   medium          the DERIVED medium (ADR-45 D2b): the A end's served edge's "medium"
#                   attribute, falling back to the link snapshot (old files);
#   served          {"node_id": ...} of the item the B end serves, or null.
# 解析**一条** link。[param gpNumbers] 为 {sheet_id: 图号}；[param gpGraphs] 为
# {sheet_id: GPPIDGraph}。返回：a / b（link 自身端引用原样）；a_dangling / b_dangling
#（该端在此上下文中无法解析时为真）；peer_number（B 端图纸号，未知为 ""）；target_tag
#（B 端所服务对象的位号，无法解析为 "" —— **link 中心**视角，报表/DRC 读它；逐连接符
# 的展示走 gpServedTagFor）；medium（**派生**介质，ADR-45 D2b：A 端服务边的 medium 属性，
# 回落 link 快照）；served（B 端所服务对象的 {node_id}，无法解析为 null）。
static func gpResolve(gpLink: GPOffPageLink, gpNumbers: Dictionary,
		gpGraphs: Dictionary) -> Dictionary:
	if gpLink == null:
		return {}
	var gpA: Dictionary = gpLink.gpA
	var gpB: Dictionary = gpLink.gpB
	var gpADangling: bool = _gpEndDangling(gpA, gpGraphs)
	var gpBDangling: bool = _gpEndDangling(gpB, gpGraphs)
	var gpPeerNo: String = str(gpNumbers.get(str(gpB.get(GPOffPageLink.GP_KEY_SHEET, "")), ""))
	var gpServed: Dictionary = _gpServedOf(gpB, gpGraphs)
	var gpTargetTag: String = ""
	if not gpServed.is_empty():
		gpTargetTag = str(gpServed.get("tag", ""))
	return {
		"a": gpA,
		"b": gpB,
		"a_dangling": gpADangling,
		"b_dangling": gpBDangling,
		"peer_number": gpPeerNo,
		"target_tag": gpTargetTag,
		"medium": gpMediumOf(gpLink, gpNumbers, gpGraphs),
		"served": gpServed if not gpServed.is_empty() else null,
	}


# The tag of the item ONE end reference serves — the PER-CONNECTOR top legend line (ADR-45
# D2a): a plain item serves itself, a connector (twin) serves the item across its first
# non-connector edge, anything unresolvable serves nothing. Pure.
# 某一**端引用**所服务对象的位号 —— **逐连接符**的图例上一行（ADR-45 D2a）：普通对象
# 服务它自己、连接符（孪生体）服务横过它第一条非连接符边的对象、一切无法解析者服务空。
# 纯函数。
static func gpServedTagFor(gpRef: Dictionary, gpNumbers: Dictionary,
		gpGraphs: Dictionary) -> String:
	var gpServed: Dictionary = _gpServedOf(gpRef, gpGraphs)
	if gpServed.is_empty():
		return ""
	return str(gpServed.get("tag", ""))


# The DERIVED medium of one link (ADR-45 D2b, user feedback 2026-11-04): the A end's served
# edge carries the live "medium" attribute — the source line the user actually edits — and
# the link's seeded snapshot is only the FALLBACK for files created before derivation
# existed. Deriving beats storing: a medium edited after creation now shows up without any
# "sync" ritual. Pure.
# 一条 link 的**派生**介质（ADR-45 D2b，2026-11-04 实机反馈）：A 端的服务边携带**活的**
# medium 边属性 —— 用户真正编辑的那条源管线；link 的播种快照只是派生出现**之前**旧档的
# 回落。派生胜于存储：创建后再改介质，旗标即刻跟上，无需任何「同步」仪式。纯函数。
static func gpMediumOf(gpLink: GPOffPageLink, gpNumbers: Dictionary,
		gpGraphs: Dictionary) -> String:
	if gpLink == null:
		return ""
	var gpEdge: GPPIDEdge = _gpMediumEdgeOf(gpLink.gpA, gpGraphs)
	if gpEdge != null:
		var gpV: String = str(gpEdge.gpAttrs.get(GPOffPageLink.GP_ATTR_MEDIUM, "")).strip_edges()
		if gpV != "":
			return gpV
	return str(gpLink.gpAttrs.get(GPOffPageLink.GP_ATTR_MEDIUM, "")).strip_edges()


# The first edge hanging off ONE end's connector whose other end is not itself a connector —
# the line whose attributes this end displays. {} -> null on anything unresolvable.
# 某端连接符上挂着的第一条「对端不是连接符」的边 —— 即该端展示属性的那条线。一切无法
# 解析者返回 null。
static func _gpMediumEdgeOf(gpRef: Dictionary, gpGraphs: Dictionary) -> GPPIDEdge:
	var gpSheetId: String = str(gpRef.get(GPOffPageLink.GP_KEY_SHEET, ""))
	if gpSheetId == "":
		return null
	var gpGraph: GPPIDGraph = gpGraphs.get(gpSheetId) as GPPIDGraph
	if gpGraph == null:
		return null
	var gpNodeId: String = str(gpRef.get(GPOffPageLink.GP_KEY_NODE, ""))
	if gpNodeId == "":
		return null
	if gpGraph.gpGetNode(gpNodeId) == null:
		return null
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		var gpOtherId: String = _gpEdgeOtherNode(gpE, gpNodeId)
		if gpOtherId == "":
			continue
		var gpOther: GPPIDNode = gpGraph.gpGetNode(gpOtherId)
		if gpOther != null and not (gpOther.gpProps as Dictionary).has(
				GPOffPageLink.GP_KEY_LINK_ID):
			return gpE
	return null


# Whether ONE endpoint reference resolves in this context: its sheet must carry a graph AND
# that graph must hold the node. An empty sheet id dangles by definition.
# 某一端引用在此上下文中能否解析：其图纸必须带图、图内必须持有该节点。空 sheet_id 视为悬空。
static func _gpEndDangling(gpRef: Dictionary, gpGraphs: Dictionary) -> bool:
	var gpSheetId: String = str(gpRef.get(GPOffPageLink.GP_KEY_SHEET, ""))
	if gpSheetId == "":
		return true
	var gpGraph: GPPIDGraph = gpGraphs.get(gpSheetId) as GPPIDGraph
	if gpGraph == null:
		return true
	var gpNodeId: String = str(gpRef.get(GPOffPageLink.GP_KEY_NODE, ""))
	if gpNodeId == "":
		return true
	return gpGraph.gpGetNode(gpNodeId) == null


# The item the B end SERVES (the flag's top line, user feedback 2026-11-03):
#   * the B end is a plain item  -> itself (its own tag);
#   * the B end is a CONNECTOR (the twin) -> the item across its edge — the first edge whose
#     other end is not itself a connector (chained connectors carry no tag of their own);
#   * anything unresolvable      -> {} (a blank slot, never a guess).
# Returns {"node_id", "tag"} or {}.
# B 端**所服务**的对象（旗标上一行，用户反馈 2026-11-03）：B 端是普通对象 → 它自己（自身
# 位号）；B 端是**连接符**（孪生体）→ 横过它那条边后的对象 —— 第一条「对端不是连接符」的边
#（链式连接符自己不带位号）；一切无法解析 → {}（空槽位，绝不臆造）。返回 {"node_id","tag"} 或 {}。
static func _gpServedOf(gpRef: Dictionary, gpGraphs: Dictionary) -> Dictionary:
	var gpSheetId: String = str(gpRef.get(GPOffPageLink.GP_KEY_SHEET, ""))
	if gpSheetId == "":
		return {}
	var gpGraph: GPPIDGraph = gpGraphs.get(gpSheetId) as GPPIDGraph
	if gpGraph == null:
		return {}
	var gpNodeId: String = str(gpRef.get(GPOffPageLink.GP_KEY_NODE, ""))
	if gpNodeId == "":
		return {}
	var gpN: GPPIDNode = gpGraph.gpGetNode(gpNodeId)
	if gpN == null:
		return {}
	if not (gpN.gpProps as Dictionary).has(GPOffPageLink.GP_KEY_LINK_ID):
		return {"node_id": gpNodeId, "tag": gpN.gpTag}
	# The B end is a CONNECTOR (the twin): walk across its edges to the first item that is
	# not itself a connector.
	# B 端是**连接符**（孪生体）：横过它的边，找到第一个「自身不是连接符」的对象。
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		var gpOtherId: String = _gpEdgeOtherNode(gpE, gpNodeId)
		if gpOtherId == "":
			continue
		var gpOther: GPPIDNode = gpGraph.gpGetNode(gpOtherId)
		if gpOther != null and not (gpOther.gpProps as Dictionary).has(GPOffPageLink.GP_KEY_LINK_ID):
			return {"node_id": gpOtherId, "tag": gpOther.gpTag}
	return {}


# The id of the node at the OPPOSITE end of an edge, or "" when gpNodeId is not an end.
# （与 GPOffPageIndex._gpEdgeOtherNode 同语义 —— resolver 是显式上下文的一份，不依赖索引。）
# 边**另一端**节点的 id；gpNodeId 不是端点时返回 ""。
static func _gpEdgeOtherNode(gpEdge: GPPIDEdge, gpNodeId: String) -> String:
	var gpF: String = str(gpEdge.gpFromRef.get("node_id", ""))
	var gpT: String = str(gpEdge.gpToRef.get("node_id", ""))
	if gpF == gpNodeId and gpT != "":
		return gpT
	if gpT == gpNodeId and gpF != "":
		return gpF
	return ""
