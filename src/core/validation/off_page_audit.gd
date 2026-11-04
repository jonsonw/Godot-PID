class_name GPOffPageAudit
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Container-level audit of the cross-sheet links (ADR-43 / W12-S4, §2.5 of the delivery plan).
# Like GPTagAudit: pure static functions over the WHOLE container (all sheets + the link table),
# no Node, no autoload, no viewport. The five rules:
#   1. drc.offpage.orphan_link  — a link endpoint references a missing sheet / node / port.
#   2. drc.offpage.unpaired     — a connector's link_id dangles, or a link endpoint is not a
#                                 connector.
#   3. drc.offpage.attr_mismatch — contract fields disagree between the link snapshot and the
#                                 edges attached at each end.
#   4. drc.offpage.kind_mismatch — the two connector families (pipe / signal) disagree, or the
#                                 link kind contradicts the port it lands on.
#   5. drc.offpage.duplicate    — the same normalized endpoint pair carries more than one link.
# ASSUMPTION: gpSheets is the FULL container sheet list (the rules decide "missing" against it).
# A subset audit would report out-of-scope sheets as orphans — callers passing subsets must pass
# an empty link table instead (the export gate stays sheet-only this round).
# 容器级跨图纸连接审计（ADR-43 / W12-S4，交付方案 §2.5）。仿 GPTagAudit：对**整个容器**
#（全部图纸 + link 表）的纯静态函数，不碰 Node、autoload、视口。五条规则见上。
# 前提：gpSheets 是**完整**容器图纸清单（规则据此判定「缺失」）。子集审计会把范围外图纸
# 误报为孤儿 —— 传子集的调用方应传空 link 表（本轮导出闸门保持仅图纸级）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_RULE_ORPHAN: String = "drc.offpage.orphan_link"
const GP_RULE_UNPAIRED: String = "drc.offpage.unpaired"
const GP_RULE_ATTR: String = "drc.offpage.attr_mismatch"
const GP_RULE_KIND: String = "drc.offpage.kind_mismatch"
const GP_RULE_DUP: String = "drc.offpage.duplicate"

# Finding entity prefix for link-scoped findings (waiver needs a stable uid).
# link 级发现的实体前缀（豁免需要稳定 uid）。
const GP_LINK_UID_PREFIX: String = "xlink-"

# The marker shown for an absent value in the mismatch detail.
# 差异明细中「缺失值」的占位符。
const GP_ABSENT: String = "—"


static func gpRun(gpSheets: Array, gpLinks: Array[GPOffPageLink],
		gpDefs: Array[GPSymbolDef]) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	var gpIndex: Dictionary = _gpIndex(gpSheets, gpDefs)
	for gpL in gpLinks:
		if gpL == null:
			continue
		_gpCheckEndpoints(gpL, gpIndex, gpOut)
		_gpCheckUnpaired(gpL, gpIndex, gpOut)
		_gpCheckAttrs(gpL, gpIndex, gpOut)
		_gpCheckKind(gpL, gpIndex, gpOut)
	_gpCheckStrays(gpLinks, gpIndex, gpOut)
	_gpCheckDuplicates(gpLinks, gpIndex, gpOut)
	# Deterministic order: rule id, then link id, then node id (the engine's finish also sorts,
	# but a stable order here keeps the pure function self-consistent for direct callers).
	# 确定性顺序：规则 id、link id、节点 id（引擎收口也会排序，但纯函数自身保序对直连
	# 调用方自洽）。
	gpOut.sort_custom(func(gpA: GPFinding, gpB: GPFinding) -> bool:
		if gpA.gpRuleId != gpB.gpRuleId:
			return gpA.gpRuleId < gpB.gpRuleId
		if gpA.gpNodeId != gpB.gpNodeId:
			return gpA.gpNodeId < gpB.gpNodeId
		return gpA.gpEntityUid < gpB.gpEntityUid)
	return gpOut


# Whether any finding is an error — mirrors GPTagAudit's gate question.
# 是否存在 error 级发现 —— 对齐 GPTagAudit 的闸门问法。
static func gpHasBlocking(gpFindings: Array[GPFinding]) -> bool:
	for gpF in gpFindings:
		if gpF.gpSeverity == GPFinding.GP_ERROR:
			return true
	return false


# ------------------------------------------------------------------ index
# 内部索引

# One container sweep: sheets by id, nodes by id (with sheet + def), connector mark.
# 一次容器扫描：按 id 索引图纸、节点（带图纸与定义）、连接符标记。
static func _gpIndex(gpSheets: Array, gpDefs: Array[GPSymbolDef]) -> Dictionary:
	var gpSheetById: Dictionary = {}
	var gpNodeById: Dictionary = {}
	var gpLookup: Dictionary = {}
	for gpD in gpDefs:
		if gpD != null:
			gpLookup[gpD.gpId] = gpD
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null or gpSheet.gpGraph == null:
			continue
		gpSheetById[gpSheet.gpId] = gpSheet
		for gpN in gpSheet.gpGraph.gpNodes:
			if gpN == null:
				continue
			var gpDef: GPSymbolDef = gpLookup.get(gpN.gpSymbolId) as GPSymbolDef
			gpNodeById[gpN.gpInstanceId] = {
				"node": gpN, "sheet": gpSheet, "def": gpDef,
				"connector": gpDef != null and gpDef.gpCategory == "offpage",
			}
	return {"sheets": gpSheetById, "nodes": gpNodeById}


# One endpoint record of a link: {"link","end","sheet_id","node_id","port_id"}.
# link 的一个端点记录。
static func _gpEnds(gpL: GPOffPageLink) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = [
		{"link": gpL, "end": "A", "sheet_id": str(gpL.gpA.get(GPOffPageLink.GP_KEY_SHEET, "")),
			"node_id": str(gpL.gpA.get(GPOffPageLink.GP_KEY_NODE, "")),
			"port_id": str(gpL.gpA.get(GPOffPageLink.GP_KEY_PORT, ""))},
		{"link": gpL, "end": "B", "sheet_id": str(gpL.gpB.get(GPOffPageLink.GP_KEY_SHEET, "")),
			"node_id": str(gpL.gpB.get(GPOffPageLink.GP_KEY_NODE, "")),
			"port_id": str(gpL.gpB.get(GPOffPageLink.GP_KEY_PORT, ""))},
	]
	return gpOut


# Display label of a link: the manual tag when present, else the instance id.
# link 的显示名：有手改编号用编号，否则用实例 id。
static func _gpLabel(gpL: GPOffPageLink) -> String:
	return gpL.gpTag if gpL.gpTag != "" else gpL.gpInstanceId


# The edges of a graph attached to (nodeId, portId).
# 图中挂在（节点, 端口）上的边。
static func _gpEdgesAt(gpGraph: GPPIDGraph, gpNodeId: String, gpPortId: String) -> Array[GPPIDEdge]:
	var gpOut: Array[GPPIDEdge] = []
	if gpGraph == null:
		return gpOut
	for gpE in gpGraph.gpEdges:
		var gpEdge: GPPIDEdge = gpE as GPPIDEdge
		if gpEdge == null:
			continue
		for gpRef in [gpEdge.gpFromRef, gpEdge.gpToRef]:
			if str(gpRef.get("node_id", "")) == gpNodeId \
					and str(gpRef.get("port_id", "")) == gpPortId:
				gpOut.append(gpEdge)
	return gpOut


# ------------------------------------------------------------------ rules
# 五条规则

# Rule 1 + 2 (endpoint existence / pairing) share one endpoint walk.
# 规则 1 + 2（端点存在性 / 配对）共用一次端点遍历。
static func _gpCheckEndpoints(gpL: GPOffPageLink, gpIndex: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	for gpEnd in _gpEnds(gpL):
		var gpSheetId: String = gpEnd["sheet_id"]
		var gpNodeId: String = gpEnd["node_id"]
		var gpSheet: GPSheet = (gpIndex["sheets"] as Dictionary).get(gpSheetId) as GPSheet
		if gpSheet == null:
			# The sheet itself is gone (the deleted-drawing case the cascade refuses to create).
			# 图纸本身没了（正是级联删除要避免造成的「删整图」情形）。
			gpOut.append(_gpLinkF(gpL, GP_RULE_ORPHAN, "drc.offpage.orphan_sheet",
				[_gpLabel(gpL), gpSheetId]))
			continue
		var gpRec: Dictionary = (gpIndex["nodes"] as Dictionary).get(gpNodeId, {})
		if gpRec.is_empty():
			# A deleted node without link cleanup — exactly what the unpaired rule also flags
			# from the connector side; here it is seen from the link side.
			# 节点被删而链未清 —— 与 unpaired 从连接符一侧报的是同一件事，此处从 link 侧看。
			gpOut.append(_gpLinkF(gpL, GP_RULE_ORPHAN, "drc.offpage.orphan_node",
				[_gpLabel(gpL), gpNodeId, gpSheetId]))
			continue
		var gpDef: GPSymbolDef = gpRec.get("def") as GPSymbolDef
		var gpNode: GPPIDNode = gpRec.get("node") as GPPIDNode
		if gpDef == null or gpDef.gpPorts.is_empty():
			continue
		var gpHasPort: bool = false
		for gpP in gpDef.gpPorts:
			if gpP != null and gpP.gpName == gpEnd["port_id"]:
				gpHasPort = true
				break
		if not gpHasPort:
			gpOut.append(_gpNodeF(gpL, GP_RULE_ORPHAN, "drc.offpage.orphan_port",
				[_gpLabel(gpL), gpEnd["port_id"], gpNodeId],
				gpNode, (gpRec["sheet"] as GPSheet).gpId))


# Rule 2: pairing. Both directions of the "connector ↔ link" handshake.
# 规则 2：配对。「连接符 ↔ link」握手的双向检查。
static func _gpCheckUnpaired(gpL: GPOffPageLink, gpIndex: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	for gpEnd in _gpEnds(gpL):
		var gpRec: Dictionary = (gpIndex["nodes"] as Dictionary).get(gpEnd["node_id"], {})
		if gpRec.is_empty():
			continue
		var gpNode: GPPIDNode = gpRec.get("node") as GPPIDNode
		# Direction 1: the node the link points at must BE a connector.
		# 方向 1：link 指向的节点必须是连接符。
		if not bool(gpRec.get("connector", false)):
			gpOut.append(_gpNodeF(gpL, GP_RULE_UNPAIRED, "drc.offpage.unpaired_link",
				[_gpLabel(gpL), gpEnd["node_id"]], gpNode,
				(gpRec.get("sheet") as GPSheet).gpId))


# Rule 2, direction 2 (needs the WHOLE link table, so it runs once, not per link): every
# connector claiming a link_id must find that link in the table — a dangling claim means the
# flag renders "?" forever and the pairing is broken.
# 规则 2 的方向 2（需要**整张** link 表，故只跑一次而非每 link）：每个声称 link_id 的
# 连接符都必须在表中找到该 link —— 悬空的声称意味着旗标永远渲染 "?"，配对已断。
static func _gpCheckStrays(gpLinks: Array[GPOffPageLink], gpIndex: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	var gpKnown: Dictionary = {}
	for gpL in gpLinks:
		if gpL != null:
			gpKnown[gpL.gpInstanceId] = true
	for gpRec in (gpIndex["nodes"] as Dictionary).values():
		var gpN: GPPIDNode = (gpRec as Dictionary).get("node") as GPPIDNode
		if gpN == null:
			continue
		var gpClaim: String = str(gpN.gpProps.get(GPOffPageLink.GP_KEY_LINK_ID, ""))
		if gpClaim == "" or gpKnown.has(gpClaim):
			continue
		gpOut.append(_gpStrayF(gpClaim, gpN, (gpRec.get("sheet") as GPSheet).gpId))


# A stray claim has no link object to hang the uid on — the uid is the CLAIM itself.
# 悬空声称没有 link 对象可挂 uid —— uid 就是声称本身。
static func _gpStrayF(gpClaim: String, gpNode: GPPIDNode, gpSheetId: String) -> GPFinding:
	var gpF: GPFinding = GPFinding.gpMake(GP_RULE_UNPAIRED, GPFinding.GP_ERROR,
		"drc.offpage.unpaired_stray", [gpClaim, gpNode.gpInstanceId]) \
		.gpAs(GP_RULE_UNPAIRED, _gpHint(GP_RULE_UNPAIRED)) \
		.gpOnEntity(GP_LINK_UID_PREFIX + gpClaim, gpSheetId)
	gpF.gpOnNode(gpNode.gpInstanceId, gpNode.gpPosition)
	return gpF


# Rule 3: contract snapshot vs the edges at each end. Only PRESENT sources compare — a free
# end (no edge) cannot mismatch what is not there.
# 规则 3：契约快照 vs 两端边属性。只比**在场**的来源 —— 自由端（无边）无法与不存在的
# 属性失配。
static func _gpCheckAttrs(gpL: GPOffPageLink, gpIndex: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	var gpEndEdges: Array = []
	for gpEnd in _gpEnds(gpL):
		var gpRec: Dictionary = (gpIndex["nodes"] as Dictionary).get(gpEnd["node_id"], {})
		var gpEdges: Array[GPPIDEdge] = []
		if not gpRec.is_empty():
			var gpSheet: GPSheet = gpRec.get("sheet") as GPSheet
			gpEdges = _gpEdgesAt(gpSheet.gpGraph, gpEnd["node_id"], gpEnd["port_id"])
		gpEndEdges.append(gpEdges)
	for gpKey in GPOffPageLink.GP_CONTRACT_KEYS:
		var gpLinkVal: String = str(gpL.gpAttrs.get(gpKey, ""))
		var gpVals: Array[String] = []
		for gpEdges2 in gpEndEdges:
			if (gpEdges2 as Array).is_empty():
				gpVals.append(GP_ABSENT)
				continue
			# All edges at one end must agree with each other too — take the set.
			# 同一端的多条边彼此也必须一致 —— 取集合。
			var gpSeen: Array[String] = []
			for gpE in gpEdges2:
				var gpV: String = str((gpE as GPPIDEdge).gpAttrs.get(gpKey, ""))
				if not gpSeen.has(gpV):
					gpSeen.append(gpV)
			if gpSeen.size() > 1:
				gpOut.append(_gpAttrF(gpL, gpIndex, "drc.offpage.attr_split",
					[gpKey, _gpLabel(gpL), "+".join(gpSeen)]))
				gpVals.append("+".join(gpSeen))
			else:
				gpVals.append(gpSeen[0])
		# Distinct present values > 1 → mismatch. The link counts as a source even when its
		# value is "" — an empty snapshot beside a filled edge is exactly the drift to report.
		# 在场的不同值 > 1 → 失配。link 即使值为 "" 也算一个来源 —— 空快照对着已填的边，
		# 正是要报告的漂移。
		var gpPresent: Array[String] = [gpLinkVal]
		for gpV2 in gpVals:
			if gpV2 != GP_ABSENT and not gpPresent.has(gpV2):
				gpPresent.append(gpV2)
		if gpPresent.size() > 1:
			gpOut.append(_gpAttrF(gpL, gpIndex, "drc.offpage.attr_mismatch",
				[gpKey, _gpLabel(gpL), gpLinkVal, gpVals[0], gpVals[1]]))


# Attr findings anchor on the A-end connector (the panel can jump there) and carry its
# sheet — a bare link finding has neither.
# 属性发现锚在 A 端连接符上（面板可跳转）并带其图纸 —— 纯 link 发现两者皆无。
static func _gpAttrF(gpL: GPOffPageLink, gpIndex: Dictionary, gpMsgKey: String,
		gpParams: Array) -> GPFinding:
	return _gpNodeF(gpL, GP_RULE_ATTR, gpMsgKey, gpParams,
		_gpAnchorOf(gpIndex, gpL), _gpSheetIdOf(gpIndex, _gpAnchorOf(gpIndex, gpL)))


# Rule 4: kind consistency — both connector families agree, and each lands on a port of the
# family the link declares (a SIGNAL link on a NOZZLE port is the plan's named example).
# 规则 4：类别一致 —— 两端连接符同族，且各自落在 link 所声明族别的端口上
#（SIGNAL link 接 NOZZLE 端口正是方案点名的例子）。
static func _gpCheckKind(gpL: GPOffPageLink, gpIndex: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	var gpKinds: Array[String] = []
	var gpNodes: Array = []
	for gpEnd in _gpEnds(gpL):
		var gpRec: Dictionary = (gpIndex["nodes"] as Dictionary).get(gpEnd["node_id"], {})
		if gpRec.is_empty():
			return
		var gpDef: GPSymbolDef = gpRec.get("def") as GPSymbolDef
		if gpDef == null:
			return
		# The family reads off the connector's port PURPOSE (the single discriminator, as in
		# the generator) — not a symbol-id list.
		# 族别读连接符端口的**用途**（与生成器同一个唯一判据）—— 没有任何符号 id 名单。
		var gpIsSignal: bool = not gpDef.gpPortsOfType(GPPort.GP_SIGNAL).is_empty()
		gpKinds.append("SIGNAL" if gpIsSignal else "NOZZLE")
		gpNodes.append(gpRec.get("node") as GPPIDNode)
	if gpKinds[0] != gpKinds[1]:
		gpOut.append(_gpNodeF(gpL, GP_RULE_KIND, "drc.offpage.kind_ends",
			[_gpLabel(gpL), gpKinds[0], gpKinds[1]],
			gpNodes[0] as GPPIDNode, _gpSheetIdOf(gpIndex, gpNodes[0] as GPPIDNode)))
	var gpLinkSignal: bool = gpL.gpKind == GPPIDEdge.GP_SIGNAL
	for gpI in range(2):
		var gpEndSignal: bool = gpKinds[gpI] == "SIGNAL"
		if gpLinkSignal != gpEndSignal:
			gpOut.append(_gpNodeF(gpL, GP_RULE_KIND, "drc.offpage.kind_port",
				[_gpLabel(gpL), gpKinds[gpI], "SIGNAL" if gpLinkSignal else "PROCESS"],
				gpNodes[gpI] as GPPIDNode,
				_gpSheetIdOf(gpIndex, gpNodes[gpI] as GPPIDNode)))


# Rule 5: the same unordered endpoint pair carrying more than one link. Only the LATER link in
# the table is flagged (the first one is the surviving connection), so a pair yields at most
# (count - 1) findings.
# 规则 5：同一无序端点对承载多条 link。只标表中**靠后**的 link（第一条是存活的连接），
# 故每对至多产生（数 - 1）条发现。
static func _gpCheckDuplicates(gpLinks: Array[GPOffPageLink], gpIndex: Dictionary,
		gpOut: Array[GPFinding]) -> void:
	var gpOwners: Dictionary = {}
	for gpL in gpLinks:
		if gpL == null:
			continue
		var gpNorm: Array[String] = [
			_gpNormEnd(str(gpL.gpA.get(GPOffPageLink.GP_KEY_SHEET, "")),
				str(gpL.gpA.get(GPOffPageLink.GP_KEY_NODE, "")),
				str(gpL.gpA.get(GPOffPageLink.GP_KEY_PORT, ""))),
			_gpNormEnd(str(gpL.gpB.get(GPOffPageLink.GP_KEY_SHEET, "")),
				str(gpL.gpB.get(GPOffPageLink.GP_KEY_NODE, "")),
				str(gpL.gpB.get(GPOffPageLink.GP_KEY_PORT, ""))),
		]
		gpNorm.sort()
		var gpPair: String = gpNorm[0] + "=>" + gpNorm[1]
		if gpOwners.has(gpPair):
			var gpFirst: GPOffPageLink = gpOwners[gpPair] as GPOffPageLink
			var gpAnchor: GPPIDNode = _gpAnchorOf(gpIndex, gpL)
			gpOut.append(_gpNodeF(gpL, GP_RULE_DUP, "drc.offpage.duplicate",
				[_gpLabel(gpL), _gpLabel(gpFirst),
				gpNorm[0], gpNorm[1]], gpAnchor, _gpSheetIdOf(gpIndex, gpAnchor)))
			continue
		gpOwners[gpPair] = gpL


# ------------------------------------------------------------------ helpers
# 辅助

static func _gpNormEnd(gpSheetId: String, gpNodeId: String, gpPortId: String) -> String:
	return gpSheetId + "/" + gpNodeId + "/" + gpPortId


static func _gpSheetIdOf(gpIndex: Dictionary, gpNode: GPPIDNode) -> String:
	if gpNode == null:
		return ""
	var gpRec: Dictionary = (gpIndex["nodes"] as Dictionary).get(gpNode.gpInstanceId, {})
	if gpRec.is_empty():
		return ""
	return (gpRec.get("sheet") as GPSheet).gpId


# A finding anchors to the FIRST end's node when it exists (the panel can jump there); a
# fully dangling link anchors to nothing but still carries the stable link uid for waivers.
# 发现尽量锚在 A 端节点上（面板可跳转）；完全悬空的 link 没有锚点，但仍带稳定 link uid
# 供豁免。
static func _gpAnchorOf(gpIndex: Dictionary, gpL: GPOffPageLink) -> GPPIDNode:
	for gpEnd in _gpEnds(gpL):
		var gpRec: Dictionary = (gpIndex["nodes"] as Dictionary).get(gpEnd["node_id"], {})
		if not gpRec.is_empty():
			return gpRec.get("node") as GPPIDNode
	return null


# Link-scoped finding: no node anchor required.
# link 级发现：不要求节点锚点。
static func _gpLinkF(gpL: GPOffPageLink, gpRule: String, gpMsgKey: String,
		gpParams: Array) -> GPFinding:
	return GPFinding.gpMake(gpRule, GPFinding.GP_ERROR, gpMsgKey, gpParams) \
		.gpAs(gpRule, _gpHint(gpRule)) \
		.gpOnEntity(GP_LINK_UID_PREFIX + gpL.gpInstanceId, "")


# Node-anchored finding (severity fixed by the rule table below).
# 节点锚定发现（级别由下方规则表定）。
static func _gpNodeF(gpL: GPOffPageLink, gpRule: String, gpMsgKey: String, gpParams: Array,
		gpNode: GPPIDNode, gpSheetId: String) -> GPFinding:
	var gpF: GPFinding = GPFinding.gpMake(gpRule, _gpSeverity(gpRule), gpMsgKey, gpParams) \
		.gpAs(gpRule, _gpHint(gpRule)) \
		.gpOnEntity(GP_LINK_UID_PREFIX + gpL.gpInstanceId, gpSheetId)
	if gpNode != null:
		gpF.gpOnNode(gpNode.gpInstanceId, gpNode.gpPosition)
	return gpF


# Severity per plan §2.5: orphan/unpaired/kind are ERROR; attr/duplicate are WARNING.
# 级别按方案 §2.5：orphan/unpaired/kind 为 ERROR；attr/duplicate 为 WARNING。
static func _gpSeverity(gpRule: String) -> String:
	return GPFinding.GP_WARNING if gpRule == GP_RULE_ATTR or gpRule == GP_RULE_DUP \
		else GPFinding.GP_ERROR


# Fix hints, one per rule (i18n keys — the registry descriptors carry the same ids).
# 修复提示，每规则一条（i18n 键 —— 注册表描述符带同样的 id）。
static func _gpHint(gpRule: String) -> String:
	match gpRule:
		GP_RULE_ORPHAN:
			return "drc.fix.offpage_repair_link"
		GP_RULE_UNPAIRED:
			return "drc.fix.offpage_repair_link"
		GP_RULE_ATTR:
			return "drc.fix.offpage_sync"
		GP_RULE_KIND:
			return "drc.fix.offpage_fix_kind"
		GP_RULE_DUP:
			return "drc.fix.offpage_merge"
	return ""
