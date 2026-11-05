extends "res://tests/gp_test.gd"
# A3 (W12 closure plan §4.3): the GPOffPageResolver — ONE pure answer per link, explicit
# context. Pins the display contract ADR-45 will normatively record.
# A3（W12 收口方案 §4.3）：GPOffPageResolver —— 每 link **一份**纯答案、显式上下文。
# 钉住 ADR-45 将规范性记录的展示契约。
#
# Failure modes being guarded against: (1) the derivation drifting between renderer, print
# model, DRC and a future exporter (the four-copies trap); (2) a guess replacing "" on an
# unresolvable slot (the flag must show "?"/blank, never an invented number); (3) the
# served-item walk crossing MORE than one edge or landing on another connector; (4) an
# impure resolve that mutates the link or the context; (5) null/garbage links crashing.
# 所防范的失效模式：(1) 推导在渲染器/打印模型/DRC/未来导出器之间漂移（四份副本陷阱）；
# (2) 无法解析的槽位用臆造值替代 ""（旗标只能显示「?」/空白，绝不编数字）；(3) 服务对象
# 的横边行走跨了**多于**一条边、或落在另一个连接符上；(4) resolve 不纯、改写 link 或上下文；
# (5) null/垃圾 link 崩溃。


# Two-sheet rig: sheet-1 (number "7") holds the A connector + a device; sheet-2 (number "8")
# holds the B end. Numbers/graphs are the EXPLICIT context.
# 双图纸夹具：sheet-1（图号 "7"）放 A 端连接符 + 一台设备；sheet-2（图号 "8"）放 B 端。
# 图号/图表即**显式上下文**。
func _gpRig() -> Dictionary:
	var gpG1: GPPIDGraph = GPPIDGraph.new()
	var gpConnA: GPPIDNode = gpG1.gpNewNode("n-conn-a", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-A", Vector2(50, 60), {})
	gpConnA.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG1.gpAddNode(gpConnA)
	var gpG2: GPPIDGraph = GPPIDGraph.new()
	var gpDev: GPPIDNode = gpG2.gpNewNode("n-dev", "PUMP001", "P-101", Vector2(300, 100), {})
	gpDev.gpTag = "P-101"
	gpG2.gpAddNode(gpDev)
	var gpNumbers: Dictionary = {"sheet-1": "7", "sheet-2": "8"}
	var gpGraphs: Dictionary = {"sheet-1": gpG1, "sheet-2": gpG2}
	var gpLink: GPOffPageLink = GPOffPageLink.new()
	gpLink.gpInstanceId = "xlink-1"
	gpLink.gpA = {"sheet_id": "sheet-1", "node_id": "n-conn-a", "port_id": "out"}
	gpLink.gpB = {"sheet_id": "sheet-2", "node_id": "n-dev", "port_id": "in"}
	gpLink.gpAttrs = {GPOffPageLink.GP_ATTR_MEDIUM: "水"}
	return {"g1": gpG1, "g2": gpG2, "numbers": gpNumbers, "graphs": gpGraphs,
		"link": gpLink, "dev": gpDev}


# Full resolution of a healthy link: peer number, medium, target tag, served.
# 健康 link 的完整解析：对端图号、介质、目标位号、served。
func gpTestResolveHealthyLink() -> void:
	var gpR: Dictionary = _gpRig()
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpR["link"], gpR["numbers"],
		gpR["graphs"])
	gpEq(gpOut["peer_number"], "8", "peer number is the B sheet's number / 对端图号取 B 图纸")
	gpEq(gpOut["medium"], "水", "medium read from the contract / 介质取自契约")
	gpEq(gpOut["target_tag"], "P-101", "target tag is the B device's tag / 目标位号是 B 设备位号")
	gpEq(gpOut["a_dangling"], false, "A end resolves / A 端可解析")
	gpEq(gpOut["b_dangling"], false, "B end resolves / B 端可解析")
	var gpServed: Dictionary = gpOut["served"]
	gpEq(gpServed["node_id"], "n-dev", "served is the B device itself / served 即 B 设备本身")


# The B end is a CONNECTOR (the twin): the served item is the one ACROSS its edge.
# B 端是**连接符**（孪生体）：被服务的对象在它那条边的另一头。
func gpTestResolveServedAcrossEdge() -> void:
	var gpR: Dictionary = _gpRig()
	var gpG2: GPPIDGraph = gpR["g2"]
	var gpConnB: GPPIDNode = gpG2.gpNewNode("n-conn-b", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-B", Vector2(60, 60), {})
	gpConnB.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG2.gpAddNode(gpConnB)
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-1", "n-conn-b", "n-dev"))
	(gpR["link"] as GPOffPageLink).gpB = {"sheet_id": "sheet-2", "node_id": "n-conn-b",
		"port_id": "in"}
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpR["link"], gpR["numbers"],
		gpR["graphs"])
	var gpServed: Dictionary = gpOut["served"]
	gpEq(gpServed["node_id"], "n-dev", "served crossed the edge to the device / served 横边到达设备")
	gpEq(gpOut["target_tag"], "P-101", "target tag is the served device's / 目标位号取被服务设备")


# Chained connectors must NOT be served — the walk skips connector-to-connector edges.
# 链式连接符不得被当作服务对象 —— 横边行走跳过连接符之间的边。
func gpTestResolveWalkSkipsChainedConnectors() -> void:
	var gpR: Dictionary = _gpRig()
	var gpG2: GPPIDGraph = gpR["g2"]
	var gpConnB: GPPIDNode = gpG2.gpNewNode("n-conn-b", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-B", Vector2(60, 60), {})
	gpConnB.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG2.gpAddNode(gpConnB)
	var gpConnC: GPPIDNode = gpG2.gpNewNode("n-conn-c", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-C", Vector2(60, 200), {})
	gpConnC.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-2"
	gpG2.gpAddNode(gpConnC)
	# conn-b — conn-c (both connectors) — then conn-c — dev.
	# conn-b — conn-c（两个都是连接符）—— conn-c — 设备。
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-1", "n-conn-b", "n-conn-c"))
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-2", "n-conn-c", "n-dev"))
	(gpR["link"] as GPOffPageLink).gpB = {"sheet_id": "sheet-2", "node_id": "n-conn-b",
		"port_id": "in"}
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpR["link"], gpR["numbers"],
		gpR["graphs"])
	# ONE edge only: from conn-b the first non-connector neighbour is… none (n-conn-c is a
	# connector). The walk does NOT chain — served stays empty, tag blank, never a guess.
	# 只走**一条**边：conn-b 的第一个非连接符邻居……没有（n-conn-c 也是连接符）。
	# 行走**不**续链 —— served 保持空、位号空白，绝不臆造。
	gpEq(gpOut["served"], null, "chained connector is NOT served / 链式连接符不作为服务对象")
	gpEq(gpOut["target_tag"], "", "tag blank, never a guess / 位号空白，绝不臆造")


# Dangling ends: unknown sheet / missing graph / missing node / empty ids.
# 悬空端：未知图纸 / 缺图 / 缺节点 / 空 id。
func gpTestDanglingDetection() -> void:
	var gpR: Dictionary = _gpRig()
	var gpLink: GPOffPageLink = gpR["link"]
	# B sheet unknown in the context / B 图纸不在上下文中
	gpLink.gpB = {"sheet_id": "sheet-9", "node_id": "n-dev", "port_id": "in"}
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpLink, gpR["numbers"], gpR["graphs"])
	gpEq(gpOut["b_dangling"], true, "unknown sheet dangles / 未知图纸悬空")
	gpEq(gpOut["peer_number"], "", "unknown sheet has no number / 未知图纸无图号")
	gpEq(gpOut["served"], null, "unknown sheet serves nothing / 未知图纸无服务对象")
	# B node missing from its graph / B 节点不在其图中
	gpLink.gpB = {"sheet_id": "sheet-2", "node_id": "n-ghost", "port_id": "in"}
	gpOut = GPOffPageResolver.gpResolve(gpLink, gpR["numbers"], gpR["graphs"])
	gpEq(gpOut["b_dangling"], true, "missing node dangles / 缺节点悬空")
	# Empty sheet id / 空 sheet_id
	gpLink.gpB = {"node_id": "n-dev"}
	gpOut = GPOffPageResolver.gpResolve(gpLink, gpR["numbers"], gpR["graphs"])
	gpEq(gpOut["b_dangling"], true, "empty sheet id dangles / 空 sheet_id 悬空")
	# A end untouched and healthy / A 端不受影响且健康
	gpEq(gpOut["a_dangling"], false, "A end still resolves / A 端仍可解析")


# Unnumbered peer: peer_number "" is a legal state, NOT a dangling one (the sheet exists,
# its graph holds the node — the number is just absent; the flag falls back to the ordinal).
# 对端无图号：peer_number "" 是合法状态，**不是**悬空（图纸存在、图持有节点 —— 只是没编号；
# 旗标回落用序号）。
func gpTestUnnumberedPeerIsNotDangling() -> void:
	var gpR: Dictionary = _gpRig()
	var gpNumbers: Dictionary = {"sheet-1": "7"}  # sheet-2 present but unnumbered
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpR["link"], gpNumbers, gpR["graphs"])
	gpEq(gpOut["b_dangling"], false, "unnumbered is NOT dangling / 无图号不是悬空")
	gpEq(gpOut["peer_number"], "", "peer number empty / 对端图号为空")


# Purity: resolve must not mutate the link or the context, and null must not crash.
# 纯度：resolve 不得改写 link 或上下文；null 不得崩溃。
func gpTestResolveIsPureAndNullSafe() -> void:
	var gpR: Dictionary = _gpRig()
	var gpLink: GPOffPageLink = gpR["link"]
	var gpLinkBefore: String = str(gpLink.gpA) + str(gpLink.gpB) + str(gpLink.gpAttrs)
	var gpNumbersBefore: int = (gpR["numbers"] as Dictionary).size()
	var gpGraphsBefore: int = (gpR["graphs"] as Dictionary).size()
	GPOffPageResolver.gpResolve(gpLink, gpR["numbers"], gpR["graphs"])
	gpEq(str(gpLink.gpA) + str(gpLink.gpB) + str(gpLink.gpAttrs), gpLinkBefore,
		"link untouched / link 未被改写")
	gpEq((gpR["numbers"] as Dictionary).size(), gpNumbersBefore, "numbers untouched / 图号表未被改写")
	gpEq((gpR["graphs"] as Dictionary).size(), gpGraphsBefore, "graphs untouched / 图表未被改写")
	gpEq(GPOffPageResolver.gpResolve(null, gpR["numbers"], gpR["graphs"]), {},
		"null link resolves to an empty answer / null link 解析为空答案")


# Index delegation: GPOffPageIndex.gpTargetTagFor reads the SAME resolver (one semantics).
# 索引委托：GPOffPageIndex.gpTargetTagFor 读**同一个** resolver（语义只有一份）。
func gpTestIndexDelegatesToResolver() -> void:
	var gpR: Dictionary = _gpRig()
	GPOffPageIndex.gpSetContext([gpR["link"]] as Array[GPOffPageLink], gpR["numbers"],
		gpR["graphs"])
	var gpOut: String = GPOffPageIndex.gpTargetTagFor(gpR["dev"])
	# Wait: gpTargetTagFor takes a NODE and finds its OWN link — the DEV has no link_id.
	# The queried node must be the A CONNECTOR; the answer is the B device's tag.
	# 注意：gpTargetTagFor 接收节点并找**它自己的** link —— 设备没有 link_id。
	# 被查询的节点应是 A 端连接符；答案是 B 端设备的位号。
	var gpConnA: GPPIDNode = (gpR["g1"] as GPPIDGraph).gpGetNode("n-conn-a")
	gpOut = GPOffPageIndex.gpTargetTagFor(gpConnA)
	gpEq(gpOut, "P-101", "index resolves through the resolver / 索引经 resolver 解析")
	GPOffPageIndex.gpClear()


# ---- ADR-45 D2a/D2b (user feedback 2026-11-04) ----
# ---- 每端对端位号 + 介质读时派生（2026-11-04 实机反馈）----

# PER-CONNECTOR top line: the PEER end's served tag. The A connector shows what the B end
# serves; the twin shows what the A end serves — "where the line comes from / goes".
# **逐连接符**的上一行：**对端**所服务位号。A 端连接符显示 B 端所服务者；孪生体显示
# A 端所服务者 —— 「线从哪台设备来 / 去往哪台设备」。
func gpTestServedTagIsPerEnd() -> void:
	var gpR: Dictionary = _gpRig()
	var gpG1: GPPIDGraph = gpR["g1"]
	var gpG2: GPPIDGraph = gpR["g2"]
	# A end: connector + a source device across its edge (the equipment the line comes from).
	# A 端：连接符 + 横边后的源设备（线所来自的那台设备）。
	var gpSrc: GPPIDNode = gpG1.gpNewNode("n-src", "PUMP001", "E-1001", Vector2(10, 60), {})
	gpSrc.gpTag = "E-1001"
	gpG1.gpAddNode(gpSrc)
	gpG1.gpAddEdge(gpG1.gpNewEdge("e-src", "n-conn-a", "n-src"))
	# B end: twin + edge to the served device.
	# B 端：孪生体 + 到被服务设备的边。
	var gpConnB: GPPIDNode = gpG2.gpNewNode("n-conn-b", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-B", Vector2(60, 60), {})
	gpConnB.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG2.gpAddNode(gpConnB)
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-1", "n-conn-b", "n-dev"))
	(gpR["link"] as GPOffPageLink).gpB = {"sheet_id": "sheet-2", "node_id": "n-conn-b",
		"port_id": "in"}
	var gpLink: GPOffPageLink = gpR["link"]
	# served is a property of the END REF, not of the display: the A end serves the SOURCE
	# device (what the TWIN displays), the B end serves the target device (what the SOURCE
	# connector displays).
	# served 是**端引用**的属性，不是展示的属性：A 端所服务者是源端设备（孪生体显示的就是
	# 它），B 端所服务者为目标设备（源端连接符显示的就是它）。
	gpEq(GPOffPageResolver.gpServedTagFor(gpLink.gpA, gpR["numbers"], gpR["graphs"]),
		"E-1001", "the A end serves the source device — what the twin displays / A 端所服务者为源端设备 —— 孪生体显示它")
	gpEq(GPOffPageResolver.gpServedTagFor(gpLink.gpB, gpR["numbers"], gpR["graphs"]),
		"P-101", "the B end serves the target device — what the source connector displays / B 端所服务者为目标设备 —— 源端连接符显示它")
	gpEq(GPOffPageResolver.gpServedTagFor({}, gpR["numbers"], gpR["graphs"]), "",
		"an empty reference serves nothing / 空引用服务空")
	# Index level: the per-connector entry agrees with the resolver, per end.
	# 索引层：逐连接符入口与 resolver 一致，逐端成立。
	GPOffPageIndex.gpSetContext([gpLink] as Array[GPOffPageLink], gpR["numbers"],
		gpR["graphs"])
	var gpConnA: GPPIDNode = gpG1.gpGetNode("n-conn-a")
	gpEq(GPOffPageIndex.gpPeerTagFor(gpConnA), "P-101",
		"index: A connector sees the far (B) tag / 索引：A 连接符见远端（B）位号")
	gpEq(GPOffPageIndex.gpPeerTagFor(gpConnB), "E-1001",
		"index: twin sees the far (A) tag — the source equipment / 索引：孪生体见远端（A）位号 —— 源端设备")
	GPOffPageIndex.gpClear()


# The medium is DERIVED from the A end's served edge (the live attribute), the link's seeded
# snapshot only a fallback for files without the edge attribute.
# 介质从 A 端服务边**派生**（活属性）；link 播种快照只是无边属性旧档的回落。
func gpTestMediumDerivesFromSourceEdge() -> void:
	var gpR: Dictionary = _gpRig()
	var gpLink: GPOffPageLink = gpR["link"]
	# No A-end edge yet: the snapshot fallback answers.
	# A 端尚无边：快照回落作答。
	gpEq(GPOffPageResolver.gpMediumOf(gpLink, gpR["numbers"], gpR["graphs"]), "水",
		"without an edge the snapshot answers / 无边时由快照作答")
	# The source line appears WITH its medium: the live edge attribute WINS over the stale
	# snapshot — a medium edited after creation shows up with no sync ritual.
	# 源管线带着介质出现：**活边属性胜过**陈旧快照 —— 创建后再改介质即刻跟上，无需同步仪式。
	var gpG1: GPPIDGraph = gpR["g1"]
	var gpSrc: GPPIDNode = gpG1.gpNewNode("n-src", "PUMP001", "E-1001", Vector2(10, 60), {})
	gpSrc.gpTag = "E-1001"
	gpG1.gpAddNode(gpSrc)
	var gpLine: GPPIDEdge = gpG1.gpNewEdge("e-src", "n-conn-a", "n-src")
	gpLine.gpAttrs[GPOffPageLink.GP_ATTR_MEDIUM] = "SLURRY 32%"
	gpG1.gpAddEdge(gpLine)
	gpEq(GPOffPageResolver.gpMediumOf(gpLink, gpR["numbers"], gpR["graphs"]), "SLURRY 32%",
		"the live edge medium wins over the snapshot / 活边介质胜过快照")
	# An edge without a medium falls back to the snapshot again.
	# 无介质的边再次回落到快照。
	gpLine.gpAttrs[GPOffPageLink.GP_ATTR_MEDIUM] = ""
	gpEq(GPOffPageResolver.gpMediumOf(gpLink, gpR["numbers"], gpR["graphs"]), "水",
		"an empty edge medium falls back / 空边介质回落快照")
	# Null safety / 空安全。
	gpEq(GPOffPageResolver.gpMediumOf(null, gpR["numbers"], gpR["graphs"]), "",
		"a null link has no medium / null link 无介质")


# ---- ADR-45 D2d (user feedback 2026-11-05) ----
# ---- served = 沿连线最近的设备 / 仪表（BFS 穿透内联件）----

# An untagged valve between the connector and the device is passed THROUGH, not served.
# 连接符与设备之间的**无位号**阀门被**穿透**，而非被当作服务对象。
func gpTestServedWalksThroughUntaggedInline() -> void:
	var gpR: Dictionary = _gpRig()
	var gpG2: GPPIDGraph = gpR["g2"]
	var gpConnB: GPPIDNode = gpG2.gpNewNode("n-conn-b", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-B", Vector2(60, 60), {})
	gpConnB.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG2.gpAddNode(gpConnB)
	var gpValve: GPPIDNode = gpG2.gpNewNode("n-valve", "VALVE001", "", Vector2(120, 60), {})
	gpG2.gpAddNode(gpValve)
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-1", "n-conn-b", "n-valve"))
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-2", "n-valve", "n-dev"))
	(gpR["link"] as GPOffPageLink).gpB = {"sheet_id": "sheet-2", "node_id": "n-conn-b",
		"port_id": "in"}
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpR["link"], gpR["numbers"],
		gpR["graphs"])
	gpEq(str((gpOut["served"] as Dictionary).get("node_id", "")), "n-dev",
		"the walk passes the untagged valve to the device / 行走穿过无位号阀门到达设备")
	gpEq(gpOut["target_tag"], "P-101", "the top line names the device / 上一行点设备的名")


# With a def lookup a TAGGED inline valve does not stop the walk — the category says inline;
# the pump beyond it wins (BFS keeps going until a device category answers).
# 带 def lookup 时**带位号**的内联阀门也拦不住行走 —— 类别说它是内联件；其后的泵胜出
#（BFS 一直走到设备类别作答为止）。
func gpTestServedDeviceBeatsTaggedValve() -> void:
	var gpR: Dictionary = _gpRig()
	var gpG2: GPPIDGraph = gpR["g2"]
	var gpConnB: GPPIDNode = gpG2.gpNewNode("n-conn-b", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-B", Vector2(60, 60), {})
	gpConnB.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG2.gpAddNode(gpConnB)
	var gpValve: GPPIDNode = gpG2.gpNewNode("n-valve", "VALVE001", "", Vector2(120, 60), {})
	gpValve.gpTag = "V-5"
	gpG2.gpAddNode(gpValve)
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-1", "n-conn-b", "n-valve"))
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-2", "n-valve", "n-dev"))
	(gpR["link"] as GPOffPageLink).gpB = {"sheet_id": "sheet-2", "node_id": "n-conn-b",
		"port_id": "in"}
	# The lookup: VALVE001 is inline piping, PUMP001 is a device.
	# lookup：VALVE001 是内联管线，PUMP001 是设备。
	var gpLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		var gpDef: GPSymbolDef = GPSymbolDef.new()
		gpDef.gpId = gpSymId
		gpDef.gpCategory = "valve" if gpSymId == "VALVE001" else "pump"
		return gpDef
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpR["link"], gpR["numbers"],
		gpR["graphs"], gpLookup)
	gpEq(str((gpOut["served"] as Dictionary).get("node_id", "")), "n-dev",
		"a tagged valve is INLINE — the walk continues to the pump / 带位号的阀门是内联件 —— 行走继续到泵")
	gpEq(gpOut["target_tag"], "P-101", "the top line names the pump / 上一行点泵的名")


# No device reachable at all: the FIRST tagged inline item met is the honest fallback —
# a named thing beats a blank slot, never a guess beyond what the line actually touches.
# 完全到不了设备：途中**第一条**有位号的内联件是诚实的回落 —— 有点名的对象胜过空槽，
# 但绝不越过连线真正触及的东西去臆造。
func gpTestServedFallbackToTaggedInline() -> void:
	var gpR: Dictionary = _gpRig()
	var gpG2: GPPIDGraph = gpR["g2"]
	var gpConnB: GPPIDNode = gpG2.gpNewNode("n-conn-b", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-B", Vector2(60, 60), {})
	gpConnB.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG2.gpAddNode(gpConnB)
	var gpValve: GPPIDNode = gpG2.gpNewNode("n-valve", "VALVE001", "", Vector2(120, 60), {})
	gpValve.gpTag = "V-5"
	gpG2.gpAddNode(gpValve)
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-1", "n-conn-b", "n-valve"))
	(gpR["link"] as GPOffPageLink).gpB = {"sheet_id": "sheet-2", "node_id": "n-conn-b",
		"port_id": "in"}
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpR["link"], gpR["numbers"],
		gpR["graphs"])
	gpEq(str((gpOut["served"] as Dictionary).get("node_id", "")), "n-valve",
		"the tagged inline item is the fallback / 有位号的内联件是回落")
	gpEq(gpOut["target_tag"], "V-5", "the top line names the valve / 上一行点阀门的名")


# ---- ADR-45 D2d round-6 revision (user feedback 2026-11-05): the walk crosses BOTH
# relations — edges AND mounts; mounted parts never win; the nearest UNNAMED device stops.
# ---- ADR-45 D2d 第六轮修订（2026-11-05 实机反馈）：行走横跨**两种**关系 —— 边与挂载；
# 挂载部件绝不胜出；最近的无名设备止步。

# The line lands on the tank's NOZZLE (mounted on the tank, no edge between nozzle and tank):
# the walk crosses the mount relation to the host and names the tank. The round-6 defect: the
# twin's top line stayed blank because the nozzle ended the walk one hop short of its tank.
# 管线落在罐体的**管口**上（管口挂载于罐体、两者之间没有边）：行走跨过挂载关系到达宿主、
# 点罐体的名。第六轮缺陷：孪生体上一行空白，因为行走离管口所属的罐体一步之遥处断了头。
func gpTestServedCrossesMountToHost() -> void:
	var gpR: Dictionary = _gpRig()
	var gpG2: GPPIDGraph = gpR["g2"]
	var gpConnB: GPPIDNode = gpG2.gpNewNode("n-conn-b", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-B", Vector2(60, 60), {})
	gpConnB.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG2.gpAddNode(gpConnB)
	# The nozzle: mounted on the tank (mount relation, NOT an edge), untagged.
	# 管口：**挂载**在罐体上（挂载关系，**不是**边），无位号。
	var gpNozzle: GPPIDNode = gpG2.gpNewNode("n-nozzle", "DGENERAL008", "", Vector2(200, 60), {})
	gpNozzle.gpParentUid = "n-dev"
	gpG2.gpAddNode(gpNozzle)
	# The ONLY edge: connector — nozzle. The tank hangs off the nozzle by the mount alone.
	# 唯一的边：连接符 —— 管口。罐体只靠挂载吊在管口下。
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-1", "n-conn-b", "n-nozzle"))
	(gpR["link"] as GPOffPageLink).gpB = {"sheet_id": "sheet-2", "node_id": "n-conn-b",
		"port_id": "in"}
	# No lookup: the mount hop is pure node data, it must work without the def voice too.
	# 无 lookup：挂载跳是纯节点数据，没有定义的声音也必须工作。
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpR["link"], gpR["numbers"],
		gpR["graphs"])
	gpEq(str((gpOut["served"] as Dictionary).get("node_id", "")), "n-dev",
		"the walk crosses the mount to the host tank / 行走跨过挂载到达宿主罐体")
	gpEq(gpOut["target_tag"], "P-101", "the top line names the tank / 上一行点罐体的名")


# A mounted part NEVER wins, even when it carries a part tag: the nozzle's "N2" is not the
# equipment the line serves — the walk penetrates the part and names its host.
# 挂载部件**绝不**胜出，即便它带着部件号：管口的「N2」不是管线所服务的设备 —— 行走穿透
# 部件、点其宿主的名。
func gpTestMountedPartNeverWins() -> void:
	var gpR: Dictionary = _gpRig()
	var gpG2: GPPIDGraph = gpR["g2"]
	var gpConnB: GPPIDNode = gpG2.gpNewNode("n-conn-b", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-B", Vector2(60, 60), {})
	gpConnB.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG2.gpAddNode(gpConnB)
	var gpNozzle: GPPIDNode = gpG2.gpNewNode("n-nozzle", "DGENERAL008", "N2", Vector2(200, 60), {})
	gpNozzle.gpParentUid = "n-dev"
	gpG2.gpAddNode(gpNozzle)
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-1", "n-conn-b", "n-nozzle"))
	(gpR["link"] as GPOffPageLink).gpB = {"sheet_id": "sheet-2", "node_id": "n-conn-b",
		"port_id": "in"}
	# The lookup: DGENERAL008 is category "general" (the round-6 trap — it sat in the device
	# list) BUT carries the NOZZLE mount kind; PUMP001 is a plain pump.
	# lookup：DGENERAL008 类别为 "general"（第六轮陷阱 —— 它就在设备类别表里）**但**带
	# NOZZLE 挂载种类；PUMP001 是普通泵。
	var gpLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		var gpDef: GPSymbolDef = GPSymbolDef.new()
		gpDef.gpId = gpSymId
		gpDef.gpCategory = "general" if gpSymId == "DGENERAL008" else "pump"
		gpDef.gpMountKind = "NOZZLE" if gpSymId == "DGENERAL008" else ""
		return gpDef
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpR["link"], gpR["numbers"],
		gpR["graphs"], gpLookup)
	gpEq(str((gpOut["served"] as Dictionary).get("node_id", "")), "n-dev",
		"a tagged nozzle is still a PART — the host wins / 带位号的管口仍是**部件** —— 宿主胜出")
	gpEq(gpOut["target_tag"], "P-101", "the top line names the pump, not the nozzle / 上一行点泵的名，不是管口")


# The nearest device met UNNAMED stops its branch — the walk must NOT penetrate past a
# device into its other lines to name a farther one; the honest answer is the blank slot.
# 途中遇到的**无名字**最近设备令其分支止步 —— 行走**绝不**穿过设备跨进它的其它管线去点
# 更远的名；诚实的答案是空槽。
func gpTestUntaggedDeviceStopsBranch() -> void:
	var gpR: Dictionary = _gpRig()
	var gpG2: GPPIDGraph = gpR["g2"]
	var gpConnB: GPPIDNode = gpG2.gpNewNode("n-conn-b", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-B", Vector2(60, 60), {})
	gpConnB.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-1"
	gpG2.gpAddNode(gpConnB)
	# An UNTAGGED tank on the line, a tagged pump beyond it.
	# 线上一台**无位号**的罐，其后一台有位号的泵。
	var gpTank: GPPIDNode = gpG2.gpNewNode("n-tank", "TANK001", "", Vector2(120, 60), {})
	gpG2.gpAddNode(gpTank)
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-1", "n-conn-b", "n-tank"))
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-2", "n-tank", "n-dev"))
	(gpR["link"] as GPOffPageLink).gpB = {"sheet_id": "sheet-2", "node_id": "n-conn-b",
		"port_id": "in"}
	var gpLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		var gpDef: GPSymbolDef = GPSymbolDef.new()
		gpDef.gpId = gpSymId
		gpDef.gpCategory = "tank" if gpSymId == "TANK001" else "pump"
		return gpDef
	var gpOut: Dictionary = GPOffPageResolver.gpResolve(gpR["link"], gpR["numbers"],
		gpR["graphs"], gpLookup)
	gpEq(gpOut["served"], null,
		"the unnamed nearest device stops the walk — honest blank / 无名的最近设备令行走止步 —— 诚实空槽")
	gpEq(gpOut["target_tag"], "", "no farther guess across the device / 绝不越过设备向更远处臆造")


# The broken-claim predicate (user feedback 2026-11-05): a claim whose link is gone is
# BROKEN (the reconnect leftover); a healthy claim is not; no claim is not.
# 断声称判谓（用户反馈 2026-11-05）：link 已走的声称 = 「断」（重连遗留物）；健康声称
# = 否；无声称 = 否。
func gpTestFlagBrokenPredicate() -> void:
	var gpR: Dictionary = _gpRig()
	var gpG1: GPPIDGraph = gpR["g1"]
	GPOffPageIndex.gpSetContext([gpR["link"]] as Array[GPOffPageLink], gpR["numbers"],
		gpR["graphs"])
	# Healthy claim: the link exists, the peer number resolves.
	# 健康声称：link 在、对端图号可解析。
	var gpConnA: GPPIDNode = gpG1.gpGetNode("n-conn-a")
	gpCheck(not GPOffPageIndex.gpFlagBrokenFor(gpConnA),
		"a healthy claim is not broken / 健康声称不算断")
	# Stale claim: the link_id points at a link the table no longer holds.
	# 陈旧声称：link_id 指向表里已不存在的 link。
	var gpStale: GPPIDNode = gpG1.gpNewNode("n-stale", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-S", Vector2(50, 200), {})
	gpStale.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = "xlink-404"
	gpG1.gpAddNode(gpStale)
	gpCheck(GPOffPageIndex.gpFlagBrokenFor(gpStale),
		"a stale claim IS broken / 陈旧声称即断")
	# No claim at all: not broken (an honest unlinked flag).
	# 完全无声称：不算断（诚实的未连接旗标）。
	var gpBare: GPPIDNode = gpG1.gpNewNode("n-bare", GPSymbolPackOffpage.GP_ID_PIPE,
		"CONN-B2", Vector2(50, 300), {})
	gpG1.gpAddNode(gpBare)
	gpCheck(not GPOffPageIndex.gpFlagBrokenFor(gpBare),
		"no claim is not broken / 无声称不算断")
	gpCheck(not GPOffPageIndex.gpFlagBrokenFor(null), "null degrades to false / null 回落假")
	GPOffPageIndex.gpClear()


# The NOZZLE LANDING refs (user feedback 2026-11-05, round 7): the connect dialog's port
# list must name the host's MOUNTED NOZZLES — the line lands on the nozzle, never on the
# equipment body; a non-nozzle part (manhole) is not a landing point.
# **管口落点**引用（用户反馈 2026-11-05 第七轮）：连接对话框的端口列表必须列出宿主
# **挂载的管口** —— 线落在管口上、绝不落在设备本体上；非管口部件（人孔）不是落点。
func gpTestNozzleLandingRefs() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpTank: GPPIDNode = gpG.gpNewNode("n-tank", "TANK001", "T-1003", Vector2(300, 100), {})
	gpTank.gpTag = "T-1003"
	gpG.gpAddNode(gpTank)
	var gpNoz: GPPIDNode = gpG.gpNewNode("n-noz", "DGENERAL008", "", Vector2(300, 60),
		{"nozzle_id": "N2"})
	gpNoz.gpParentUid = "n-tank"
	gpNoz.gpMountAnchor = "pump_discharge"
	gpG.gpAddNode(gpNoz)
	var gpHole: GPPIDNode = gpG.gpNewNode("n-hole", "DGENERAL007", "", Vector2(320, 100), {})
	gpHole.gpParentUid = "n-tank"
	gpHole.gpMountAnchor = "manhole"
	gpG.gpAddNode(gpHole)
	var gpLookup: Callable = func(gpSymId: String) -> GPSymbolDef:
		var gpDef: GPSymbolDef = GPSymbolDef.new()
		gpDef.gpId = gpSymId
		match gpSymId:
			"DGENERAL008":
				gpDef.gpCategory = "general"
				gpDef.gpMountKind = "NOZZLE"
				gpDef.gpPorts = [GPPort.gpMake("pipe", Vector2(1, 0.5), Vector2(1, 0))]
			"DGENERAL007":
				gpDef.gpCategory = "general"
				gpDef.gpMountKind = "MANHOLE"
				# A port on the manhole too — so the KIND check, not a missing port, is
				# what excludes non-nozzle parts (keeps the pin sensitive to the filter).
				# 人孔**也**带端口 —— 使排除非管口部件的是**种类检查**而非缺端口
				#（保持钉子对过滤器敏感）。
				gpDef.gpPorts = [GPPort.gpMake("hole", Vector2(0.5, 0), Vector2(0, -1))]
			_:
				gpDef.gpCategory = "tank"
		return gpDef
	var gpRefs: Array[Dictionary] = GPOffPageIndex.gpNozzleLandingRefs(gpG, "n-tank", gpLookup)
	gpEq(gpRefs.size(), 1, "exactly the nozzle is a landing point / 恰好管口是落点")
	if gpRefs.size() == 1:
		gpEq(str(gpRefs[0].get("node_id", "")), "n-noz",
			"the ref points AT the nozzle / 引用指向管口本身")
		gpEq(str(gpRefs[0].get("port_id", "")), "pipe",
			"the port is the nozzle's line port / 端口是管口的管线端口")
		gpEq(str(gpRefs[0].get("nozzle_id", "")), "N2", "the part name rides along / 部件名随行")
	gpEq(GPOffPageIndex.gpNozzleLandingRefs(gpG, "n-missing", gpLookup).size(), 0,
		"an unknown host yields nothing / 未知宿主交回空")
	gpEq(GPOffPageIndex.gpNozzleLandingRefs(null, "n-tank", gpLookup).size(), 0,
		"a null graph yields nothing / 空图交回空")
