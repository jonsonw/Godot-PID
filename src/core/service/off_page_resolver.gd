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
#   * both connectors of one link show the SAME target tag: the item the link points at on
#     the B-end sheet.
# 本解析钉住的**展示契约**对（同步起草的）ADR-45 具有规范性：三态永不合并；目标位号在
# 读取期**推导**（ADR-43 D3），绝不是存储字段；一条 link 的两个连接符显示**同一个**目标
# 位号 —— 即 link 在 B 端图纸上所指的那件东西。
#
# Coding rule: every variable declares its type explicitly; all functions static & pure.
# 编码规范：全变量显式类型；全部函数为静态纯函数。


# Resolve ONE link. [param gpNumbers] is {sheet_id: drawing number}; [param gpGraphs] is
# {sheet_id: GPPIDGraph}. Returns:
#   a / b           the link's own endpoint refs (verbatim);
#   a_dangling      TRUE when the A end cannot be resolved in this context;
#   b_dangling      same for the B end;
#   peer_number     the B-end sheet's drawing number ("" when unknown — the A-view "peer");
#   target_tag      the tag of the item the B end serves ("" when unresolvable — the flag's
#                   top line; both connectors show the same one);
#   medium          the contract medium (GPOffPageLink.GP_ATTR_MEDIUM);
#   served          {"node_id": ...} of the item the B end serves, or null.
# 解析**一条** link。[param gpNumbers] 为 {sheet_id: 图号}；[param gpGraphs] 为
# {sheet_id: GPPIDGraph}。返回：a / b（link 自身端引用原样）；a_dangling / b_dangling
#（该端在此上下文中无法解析时为真）；peer_number（B 端图纸号，未知为 ""）；target_tag
#（B 端所服务对象的位号，无法解析为 "" —— 旗标上一行，两端同显）；medium（契约介质）；
# served（B 端所服务对象的 {node_id}，无法解析为 null）。
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
		"medium": str(gpLink.gpAttrs.get(GPOffPageLink.GP_ATTR_MEDIUM, "")),
		"served": gpServed if not gpServed.is_empty() else null,
	}


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
