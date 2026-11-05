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
#     what the A end serves — "where the line comes from / where it goes"; the served item is
#     the NEAREST equipment/instrument ALONG the line (user feedback 2026-11-05, ADR-45 D2d):
#     the walk traverses through untagged inline items (valves, fittings) until a device wins.
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
		gpGraphs: Dictionary, gpDefLookup: Callable = Callable()) -> Dictionary:
	if gpLink == null:
		return {}
	var gpA: Dictionary = gpLink.gpA
	var gpB: Dictionary = gpLink.gpB
	var gpADangling: bool = _gpEndDangling(gpA, gpGraphs)
	var gpBDangling: bool = _gpEndDangling(gpB, gpGraphs)
	var gpPeerNo: String = str(gpNumbers.get(str(gpB.get(GPOffPageLink.GP_KEY_SHEET, "")), ""))
	var gpServed: Dictionary = _gpServedOf(gpB, gpGraphs, gpDefLookup)
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
# D2a/D2d): a plain item serves itself, a connector (twin) serves the NEAREST equipment or
# instrument along its line (BFS through inline items), anything unresolvable serves nothing.
# Pure.
# 某一**端引用**所服务对象的位号 —— **逐连接符**的图例上一行（ADR-45 D2a/D2d）：普通对象
# 服务它自己、连接符（孪生体）服务**沿连线最近**的设备 / 仪表（广度优先穿透内联件）、一切
# 无法解析者服务空。纯函数。
static func gpServedTagFor(gpRef: Dictionary, gpNumbers: Dictionary,
		gpGraphs: Dictionary, gpDefLookup: Callable = Callable()) -> String:
	var gpServed: Dictionary = _gpServedOf(gpRef, gpGraphs, gpDefLookup)
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


# The item ONE end ref SERVES (the flag's top line; ADR-45 D2a, refined 2026-11-05 as D2d,
# round-6 revision): the walk is a breadth-first traversal across BOTH relations a line is
# made of — edges AND mounts (a mounted nozzle joins the line by an edge, its equipment by
# the mount). A NAMED device/instrument wins at its BFS depth (nearest first); mounted parts
# and inline piping are walked through; the nearest device met UNNAMED stops its branch (the
# honest blank — a farther guess would cross into the device's other lines); chained
# connectors are never crossed; the first TAGGED inline item met is the fallback for lines
# that reach no device at all.
# Returns {"node_id", "tag"} or {}.
# 某一**端引用**所服务的对象（旗标上一行；ADR-45 D2a，2026-11-05 细化为 D2d，第六轮修订）：
# 行走是横跨**两种**关系的广度优先 —— **边与挂载**（挂载管口靠边接入管线、靠挂载接入设备）。
# **有名字**的设备 / 仪表在其 BFS 深度上胜出（即最近优先）；挂载部件与内联管线被穿透；
# 途中遇到的**无名字**最近设备令其分支止步（诚实空槽 —— 向更远处臆造会跨进该设备的其它
# 管线）；链式连接符绝不跨过；完全到不了设备时，第一条**有位号**的内联件记为回落。
# 返回 {"node_id","tag"} 或 {}。
static func _gpServedOf(gpRef: Dictionary, gpGraphs: Dictionary,
		gpDefLookup: Callable = Callable()) -> Dictionary:
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
	# The end is a CONNECTOR (the twin): breadth-first along the line, nearest device wins.
	# 该端是**连接符**（孪生体）：沿连线广度优先，最近的设备胜出。
	var gpQueue: Array[String] = [gpNodeId]
	var gpSeen: Dictionary = {gpNodeId: true}
	var gpFallback: Dictionary = {}
	while not gpQueue.is_empty():
		var gpCur: String = gpQueue.pop_front()
		# Next hops = the far ends of the edges at gpCur PLUS gpCur's mount HOST. A mounted
		# inline item — the tank's nozzle the line lands on — joins the LINE by an edge but
		# its EQUIPMENT by the MOUNT relation (two relations, never one: the mount layer's
		# founding contract). The walk must cross both, or the nozzle dead-ends one hop
		# short of the tank it belongs to (user feedback 2026-11-05, round 6).
		# 下一跳 = gpCur 各条边的另一端 **加上** gpCur 的挂载宿主。挂载内联件 —— 管线所落的
		# 罐体管口 —— 靠**边**接入管线、靠**挂载关系**接入设备（两种关系，从来不是一种：
		# 挂载层的立约）。行走必须两种都跨，否则管口在离它所属罐体一步之遥处断头
		#（2026-11-05 实机反馈第六轮）。
		var gpNext: Array[String] = []
		for gpE in gpGraph.gpEdges:
			if gpE == null:
				continue
			var gpOtherId: String = _gpEdgeOtherNode(gpE, gpCur)
			if gpOtherId != "" and not gpSeen.has(gpOtherId):
				gpNext.append(gpOtherId)
		var gpCurNode: GPPIDNode = gpGraph.gpGetNode(gpCur)
		if gpCurNode != null and gpCurNode.gpIsMounted() \
				and not gpSeen.has(gpCurNode.gpParentUid):
			gpNext.append(gpCurNode.gpParentUid)
		for gpOtherId in gpNext:
			gpSeen[gpOtherId] = true
			var gpOther: GPPIDNode = gpGraph.gpGetNode(gpOtherId)
			if gpOther == null:
				continue
			# A chained connector is a dead end: it lives on ANOTHER sheet (or claims to).
			# 链式连接符是死路：它活在**另一张**图纸上（或声称如此）。
			if (gpOther.gpProps as Dictionary).has(GPOffPageLink.GP_KEY_LINK_ID) \
					or _gpIsOffpageDef(gpOther, gpDefLookup):
				continue
			var gpKind: String = _gpServedKindOf(gpOther, gpDefLookup)
			if gpKind == "device":
				return {"node_id": gpOtherId, "tag": gpOther.gpTag}
			if gpKind == "dead":
				# The nearest equipment is here but unnamed — stop, never guess farther.
				# 最近的设备就在此处但没有名字 —— 止步，绝不向更远处臆造。
				continue
			if str(gpOther.gpTag) != "" and gpFallback.is_empty():
				gpFallback = {"node_id": gpOtherId, "tag": gpOther.gpTag}
			gpQueue.append(gpOtherId)
	return gpFallback


# Device/instrument category keys (ADR-45 D2d): what the flag's top line may name. Valves are
# inline piping, not equipment; "general" covers the misc-equipment family.
# 设备 / 仪表类别键（ADR-45 D2d）：旗标上一行可以点名的对象。阀门属内联管线、不是设备；
# "general" 涵盖杂项设备家族。
const GP_DEVICE_CATEGORIES: Array[String] = ["pump", "tank", "heat", "instrument", "general"]


# The three-way classification the served walk needs (user feedback 2026-11-05, round 6):
#   * "device" — may be NAMED as the served item: a tagged equipment/instrument whose def is
#     not a mounted part;
#   * "inline" — walk THROUGH: a mounted part (the def carries a mount kind — nozzle, manhole,
#     blind, insulation, actuator … a part joins equipment by the MOUNT relation, never by the
#     line), inline piping, or — in no-lookup mode — anything untagged (the tag is the only
#     voice left);
#   * "dead"   — the nearest equipment IS HERE but unnamed (device category, no tag): stop this
#     branch. Penetrating past a device would cross into its OTHER lines and could name a
#     farther, wrong device; the honest answer is the blank slot — assign the tag, it appears.
# Without a lookup the tag is the only voice: a tagged non-connector item is treated as the
# served item (the historical single-hop behavior, extended to walk through untagged items).
# Pure.
# 服务行走所需的**三分类**（2026-11-05 实机反馈第六轮）：
#   * "device" —— 可被**点名**为服务对象：有位号、设备 / 仪表类别、且非挂载部件的定义；
#   * "inline" —— **穿透**：挂载部件（定义带挂载种类 —— 管口、人孔、盲板、保温、执行机构
#     ……部件靠**挂载关系**接入设备，从不靠管线）、内联管线，或 —— 无 lookup 模式下 ——
#     一切无位号者（位号是唯一剩下的声音）；
#   * "dead"   —— 最近的设备**就在此处**但没有名字（设备类别、无位号）：此分支**止步**。
#     穿过设备会跨进它的**其它**管线、可能点名更远的错误设备；诚实的答案是空槽 —— 赋上位号
#     它就会出现。
# 没有 lookup 时位号是唯一声音：有位号的非连接符对象即视为被服务对象（历史上的单跳行为，
# 扩展为穿透无位号者）。纯函数。
static func _gpServedKindOf(gpN: GPPIDNode, gpDefLookup: Callable) -> String:
	var gpTagged: bool = str(gpN.gpTag) != ""
	if not gpDefLookup.is_valid():
		return "device" if gpTagged else "inline"
	var gpDef: GPSymbolDef = gpDefLookup.call(gpN.gpSymbolId) as GPSymbolDef
	if gpDef == null:
		return "device" if gpTagged else "inline"
	if gpDef.gpMountKind != "":
		return "inline"
	if not GP_DEVICE_CATEGORIES.has(gpDef.gpCategory):
		return "inline"
	return "device" if gpTagged else "dead"


# Whether the node's symbol is the offpage connector category (user packs may lack the
# link_id prop — the def category is the honest identity).
# 节点的符号是否为离页连接符类别（用户包可能缺 link_id 属性 —— def 类别才是诚实身份）。
static func _gpIsOffpageDef(gpN: GPPIDNode, gpDefLookup: Callable) -> bool:
	if not gpDefLookup.is_valid():
		return false
	var gpDef: GPSymbolDef = gpDefLookup.call(gpN.gpSymbolId) as GPSymbolDef
	return gpDef != null and gpDef.gpCategory == "offpage"


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
