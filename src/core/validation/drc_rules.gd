class_name GPDRCRules
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# DRC rule implementations (ADR-39). Pure functions over GPDrcSnapshot: no Node, no autoload, no
# viewport. The registry supplies id / severity / scope; a rule only returns findings.
# DRC 规则实现（ADR-39）。对 GPDrcSnapshot 的纯函数：不碰 Node、不碰 autoload、不碰视口。
# 注册表提供 id / 级别 / 范围；规则只负责产出发现。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_SEV_ERROR: String = "error"
const GP_SEV_WARNING: String = "warning"
const GP_SEV_INFO: String = "info"


# ---- finding helpers / 发现辅助 ----

static func _gpNodeF(gpSnap: GPDrcSnapshot, gpRule: String, gpSev: String, gpKey: String,
		gpParams: Array, gpNodeId: String, gpWorld: Vector2, gpCheck: String,
		gpHint: String) -> GPFinding:
	return GPFinding.gpMake(gpRule, gpSev, gpKey, gpParams).gpOnNode(gpNodeId, gpWorld) \
		.gpAs(gpCheck, gpHint).gpOnEntity(gpSnap.gpNodeUid(gpNodeId), gpSnap.sheet_id)


static func _gpEdgeF(gpSnap: GPDrcSnapshot, gpRule: String, gpSev: String, gpKey: String,
		gpParams: Array, gpEdgeId: String, gpWorld: Vector2, gpCheck: String,
		gpHint: String) -> GPFinding:
	return GPFinding.gpMake(gpRule, gpSev, gpKey, gpParams).gpOnEdge(gpEdgeId, gpWorld) \
		.gpAs(gpCheck, gpHint).gpOnEntity(gpSnap.gpEdgeUid(gpEdgeId), gpSnap.sheet_id)


static func _gpShapeF(gpSnap: GPDrcSnapshot, gpRule: String, gpSev: String, gpKey: String,
		gpParams: Array, gpIdx: int, gpWorld: Vector2, gpCheck: String,
		gpHint: String) -> GPFinding:
	return GPFinding.gpMake(gpRule, gpSev, gpKey, gpParams).gpOnShape(gpIdx, gpWorld) \
		.gpAs(gpCheck, gpHint).gpOnEntity("shape-%d" % gpIdx, gpSnap.sheet_id)


static func _gpMid(gpSnap: GPDrcSnapshot, gpEdgeId: String) -> Vector2:
	var gpPts: PackedVector2Array = gpSnap.gpPolyline(gpEdgeId)
	if gpPts.is_empty():
		return Vector2.INF
	if gpPts.size() == 1:
		return gpPts[0]
	return (gpPts[0] + gpPts[gpPts.size() - 1]) * 0.5


# =====================================================================
# TOPO — connectivity / 连接拓扑
# =====================================================================

# An edge end must reference an existing node, and (when named) an existing port.
# 连线端点必须引用存在的节点；命名端口必须存在。
static func gpCheckEdgeRefMissing(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpD: Dictionary = gpSnap.gpEdge(gpEId)
		var gpE: GPPIDEdge = gpD.get("edge") as GPPIDEdge
		if gpE == null:
			continue
		for gpIsFrom in [true, false]:
			var gpRef: Dictionary = gpE.gpFromRef if gpIsFrom else gpE.gpToRef
			var gpNodeId: String = str(gpRef.get("node_id", ""))
			if gpNodeId == "":
				continue
			var gpEnd: String = "from" if gpIsFrom else "to"
			if not gpSnap.gpHasNode(gpNodeId):
				gpOut.append(_gpEdgeF(gpSnap, "drc.topo", GP_SEV_ERROR, "drc.edge_ref_missing",
					[gpSnap.gpEdgeLabel(gpEId), gpEnd], gpEId, _gpMid(gpSnap, gpEId),
					"drc.topo.edge_ref_missing", "drc.fix.relink"))
				continue
			var gpPortId: String = str(gpRef.get("port_id", ""))
			if gpPortId == "":
				continue
			var gpNodeData: Dictionary = gpSnap.gpNode(gpNodeId)
			var gpDef: GPSymbolDef = gpNodeData.get("def") as GPSymbolDef
			if gpDef == null or gpDef.gpPorts.is_empty():
				continue
			if gpDef.gpPortByName(gpPortId) == null:
				gpOut.append(_gpEdgeF(gpSnap, "drc.topo", GP_SEV_ERROR, "drc.edge_port_missing",
					[gpSnap.gpEdgeLabel(gpEId), gpSnap.gpNodeLabel(gpNodeId), gpPortId], gpEId,
					_gpMid(gpSnap, gpEId), "drc.topo.edge_port_missing", "drc.fix.relink"))
	return gpOut


# Process lines may only land on process / generic ports; signal lines only on signal /
# actuator / generic ports. Legacy edges without a port_id are skipped (the resolver's fallback
# is a hint, not a defect).
# 工艺线只能接工艺 / 通用端口；信号线只能接信号 / 执行机构 / 通用端口。无 port_id 的旧连线跳过
#（解析器的回退是提示，不是缺陷）。
static func gpCheckEdgePortType(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpD: Dictionary = gpSnap.gpEdge(gpEId)
		var gpE: GPPIDEdge = gpD.get("edge") as GPPIDEdge
		if gpE == null:
			continue
		var gpWant: String = GPPort.GP_SIGNAL if gpE.gpKind == GPPIDEdge.GP_SIGNAL \
			else GPPort.GP_NOZZLE
		for gpIsFrom in [true, false]:
			var gpRef: Dictionary = gpE.gpFromRef if gpIsFrom else gpE.gpToRef
			var gpNodeId: String = str(gpRef.get("node_id", ""))
			var gpPortId: String = str(gpRef.get("port_id", ""))
			if gpNodeId == "" or gpPortId == "":
				continue
			var gpPort: Dictionary = gpSnap.gpPort(gpNodeId, gpPortId)
			if gpPort.is_empty():
				continue
			var gpType: String = str(gpPort.get("type", GPPort.GP_NOZZLE))
			var gpOk: bool = gpType == GPPort.GP_TERMINAL \
				or (gpWant == GPPort.GP_SIGNAL and (gpType == GPPort.GP_SIGNAL
					or gpType == GPPort.GP_ACTUATOR)) \
				or (gpWant == GPPort.GP_NOZZLE and gpType == GPPort.GP_NOZZLE)
			if not gpOk:
				gpOut.append(_gpEdgeF(gpSnap, "drc.topo", GP_SEV_ERROR, "drc.edge_port_type",
					[gpSnap.gpEdgeLabel(gpEId), gpSnap.gpNodeLabel(gpNodeId), gpPortId, gpType],
					gpEId, _gpMid(gpSnap, gpEId), "drc.topo.edge_port_type", "drc.fix.reconnect"))
	return gpOut


# Zero-length line: both resolved ends at the same point (>= 0.5 mm apart is fine).
# 零长度线：两端解析后落在同一点（相距 >= 0.5 mm 即正常）。
static func gpCheckEdgeZeroLength(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpD: Dictionary = gpSnap.gpEdge(gpEId)
		var gpE: GPPIDEdge = gpD.get("edge") as GPPIDEdge
		if gpE == null:
			continue
		if str(gpE.gpFromRef.get("node_id", "")) == "" \
				or str(gpE.gpToRef.get("node_id", "")) == "":
			continue
		var gpFrom: Dictionary = gpD.get("from", {}) as Dictionary
		var gpTo: Dictionary = gpD.get("to", {}) as Dictionary
		var gpA: Vector2 = gpFrom.get("pos", Vector2.ZERO)
		var gpB: Vector2 = gpTo.get("pos", Vector2.ZERO)
		if gpA.distance_to(gpB) < 0.5:
			gpOut.append(_gpEdgeF(gpSnap, "drc.topo", GP_SEV_WARNING, "drc.edge_zero_length",
				[gpSnap.gpEdgeLabel(gpEId)], gpEId, gpA, "drc.topo.edge_zero_length",
				"drc.fix.delete"))
	return gpOut


# Two identical edges between the same ordered ports of the same kind.
# 同一对端口、同一类型的两条重复连线。
static func gpCheckEdgeDuplicate(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpSeen: Dictionary = {}
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpE: GPPIDEdge = (gpSnap.gpEdge(gpEId).get("edge") as GPPIDEdge)
		if gpE == null:
			continue
		var gpA: String = "%s/%s" % [str(gpE.gpFromRef.get("node_id", "")),
			str(gpE.gpFromRef.get("port_id", ""))]
		var gpB: String = "%s/%s" % [str(gpE.gpToRef.get("node_id", "")),
			str(gpE.gpToRef.get("port_id", ""))]
		var gpKey: String = (gpA + "|" + gpB) if gpA <= gpB else (gpB + "|" + gpA)
		gpKey += "|" + gpE.gpKind
		if gpSeen.has(gpKey):
			gpOut.append(_gpEdgeF(gpSnap, "drc.topo", GP_SEV_WARNING, "drc.edge_duplicate",
				[gpSnap.gpEdgeLabel(gpEId), gpSnap.gpEdgeLabel(str(gpSeen[gpKey]))], gpEId,
				_gpMid(gpSnap, gpEId), "drc.topo.edge_duplicate", "drc.fix.delete"))
		else:
			gpSeen[gpKey] = gpEId
	return gpOut


# An edge whose two ends are the same node.
# 首尾接在同一节点的连线。
static func gpCheckEdgeSelfLoop(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpE: GPPIDEdge = (gpSnap.gpEdge(gpEId).get("edge") as GPPIDEdge)
		if gpE == null:
			continue
		var gpA: String = str(gpE.gpFromRef.get("node_id", ""))
		var gpB: String = str(gpE.gpToRef.get("node_id", ""))
		if gpA != "" and gpA == gpB:
			gpOut.append(_gpEdgeF(gpSnap, "drc.topo", GP_SEV_WARNING, "drc.edge_self_loop",
				[gpSnap.gpEdgeLabel(gpEId)], gpEId, _gpMid(gpSnap, gpEId),
				"drc.topo.edge_self_loop", "drc.fix.relink"))
	return gpOut


# =====================================================================
# SYMBOL — library / mounting / 图元库与挂载
# =====================================================================

# Every node's symbol id must resolve to a definition.
# 每个节点的 symbol_id 必须解析到定义。
static func gpCheckSymbolUnknown(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.nodes.keys():
		var gpNId: String = str(gpId)
		var gpD: Dictionary = gpSnap.gpNode(gpNId)
		var gpN: GPPIDNode = gpD.get("node") as GPPIDNode
		if gpN == null or gpD.get("def") != null:
			continue
		gpOut.append(_gpNodeF(gpSnap, "drc.symbol", GP_SEV_ERROR, "drc.symbol_unknown",
			[gpSnap.gpNodeLabel(gpNId), gpN.gpSymbolId], gpNId, gpD.get("origin", Vector2.ZERO),
			"drc.symbol.unknown", "drc.fix.replace_symbol"))
	return gpOut


# Mounting integrity: the host must exist, the anchor must exist on the host definition, and
# the child's mount kind must be accepted by that anchor.
# 挂载完整性：宿主必须存在、锚点必须在宿主定义上存在、子件类型必须被该锚点接受。
static func gpCheckMountIntegrity(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.nodes.keys():
		var gpNId: String = str(gpId)
		var gpD: Dictionary = gpSnap.gpNode(gpNId)
		var gpN: GPPIDNode = gpD.get("node") as GPPIDNode
		if gpN == null or gpN.gpParentUid == "":
			continue
		var gpHost: GPPIDNode = gpSnap.graph.gpGetNode(gpN.gpParentUid)
		if gpHost == null:
			gpOut.append(_gpNodeF(gpSnap, "drc.symbol", GP_SEV_ERROR, "drc.mount_orphan",
				[gpSnap.gpNodeLabel(gpNId), gpN.gpParentUid], gpNId,
				gpD.get("origin", Vector2.ZERO), "drc.symbol.mount_orphan", "drc.fix.delete"))
			continue
		var gpHostDef: GPSymbolDef = gpSnap.defs.get(gpHost.gpSymbolId) as GPSymbolDef
		if gpHostDef == null:
			continue
		var gpAnchor: GPAttachPoint = gpHostDef.gpAttachPointByName(gpN.gpMountAnchor)
		if gpAnchor == null:
			gpOut.append(_gpNodeF(gpSnap, "drc.symbol", GP_SEV_ERROR, "drc.mount_anchor_missing",
				[gpSnap.gpNodeLabel(gpNId), gpSnap.gpNodeLabel(gpHost.gpInstanceId),
					gpN.gpMountAnchor], gpNId, gpD.get("origin", Vector2.ZERO),
				"drc.symbol.mount_anchor_missing", "drc.fix.remount"))
			continue
		var gpChildDef: GPSymbolDef = gpD.get("def") as GPSymbolDef
		if gpChildDef != null and not GPMountResolver.gpCanMount(gpHostDef, gpAnchor, gpChildDef):
			gpOut.append(_gpNodeF(gpSnap, "drc.symbol", GP_SEV_ERROR, "drc.mount_accepts",
				[gpSnap.gpNodeLabel(gpNId), gpAnchor.gpName, gpChildDef.gpMountKind], gpNId,
				gpD.get("origin", Vector2.ZERO), "drc.symbol.mount_accepts", "drc.fix.remount"))
	return gpOut


# Two mounted parts on one host sharing the same nozzle / manhole number.
# 同一宿主上两个部件共用同一个管口 / 人孔号。
static func gpCheckNozzleDuplicate(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpSeen: Dictionary = {}
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.nodes.keys():
		var gpNId: String = str(gpId)
		var gpD: Dictionary = gpSnap.gpNode(gpNId)
		var gpN: GPPIDNode = gpD.get("node") as GPPIDNode
		if gpN == null or gpN.gpParentUid == "":
			continue
		var gpTag: String = str(gpN.gpProps.get("nozzle_id",
			gpN.gpProps.get("manhole_id", ""))).strip_edges()
		if gpTag == "":
			continue
		var gpKey: String = gpN.gpParentUid + "|" + gpTag
		if gpSeen.has(gpKey):
			gpOut.append(_gpNodeF(gpSnap, "drc.symbol", GP_SEV_ERROR, "drc.nozzle_duplicate",
				[gpSnap.gpNodeLabel(gpNId), gpTag], gpNId, gpD.get("origin", Vector2.ZERO),
				"drc.symbol.nozzle_duplicate", "drc.fix.renumber_nozzle"))
		else:
			gpSeen[gpKey] = gpNId
	return gpOut


# An edge must not connect to an annotation / non-connectable symbol.
# 连线不得接到注释 / 不可连接图元。
static func gpCheckSymbolCategoryConnect(gpSnap: GPDrcSnapshot,
		_gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpE: GPPIDEdge = (gpSnap.gpEdge(gpEId).get("edge") as GPPIDEdge)
		if gpE == null:
			continue
		for gpIsFrom in [true, false]:
			var gpRef: Dictionary = gpE.gpFromRef if gpIsFrom else gpE.gpToRef
			var gpNId: String = str(gpRef.get("node_id", ""))
			if gpNId == "":
				continue
			var gpDef: GPSymbolDef = gpSnap.gpNode(gpNId).get("def") as GPSymbolDef
			if gpDef != null and gpDef.gpCategory == "annotation":
				gpOut.append(_gpEdgeF(gpSnap, "drc.symbol", GP_SEV_ERROR,
					"drc.symbol_category_connect", [gpSnap.gpEdgeLabel(gpEId),
						gpSnap.gpNodeLabel(gpNId)], gpEId, _gpMid(gpSnap, gpEId),
					"drc.symbol.category_connect", "drc.fix.relink"))
	return gpOut


# Suspected hand-drawn equipment: a CLOSED free shape of meaningful size sitting near a port or
# an edge end. Text / leaders / open annotations are never reported.
# 疑似手绘设备：有实际尺寸的**闭合**自由图形，且靠近端口或线端。文字 / 引出线 / 开放标注永不报。
static func gpCheckSymbolNotLibrary(gpSnap: GPDrcSnapshot,
		gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	var gpPolicy: String = str(GPDRCConfig.gpPolicy(gpCfg, "free_shapes", "warning"))
	if gpPolicy == "off":
		return gpOut
	var gpAnchors: Array[Vector2] = []
	for gpNId in gpSnap.nodes.keys():
		var gpD: Dictionary = gpSnap.gpNode(str(gpNId))
		var gpPorts: Dictionary = gpD.get("ports", {}) as Dictionary
		for gpP in gpPorts.values():
			gpAnchors.append((gpP as Dictionary).get("pos", Vector2.ZERO))
	for gpEId in gpSnap.edges.keys():
		var gpPts: PackedVector2Array = gpSnap.gpPolyline(str(gpEId))
		if not gpPts.is_empty():
			gpAnchors.append(gpPts[0])
			gpAnchors.append(gpPts[gpPts.size() - 1])
	for gpIdx in range(gpSnap.shapes.size()):
		var gpS: GPShape = gpSnap.shapes[gpIdx] as GPShape
		if gpS == null or gpS.gpKind == GPShape.GPKind.GP_TEXT:
			continue
		var gpClosed: bool = gpS.gpClosed or gpS.gpKind == GPShape.GPKind.GP_RECT \
			or gpS.gpKind == GPShape.GPKind.GP_CIRCLE
		if not gpClosed:
			continue
		var gpBox: Rect2 = gpS.gpBBox()
		if gpBox.size.x < 12.0 or gpBox.size.y < 12.0:
			continue
		var gpNear: bool = false
		for gpA in gpAnchors:
			if gpBox.grow(10.0).has_point(gpA):
				gpNear = true
				break
		if not gpNear:
			continue
		var gpSev: String = GP_SEV_WARNING if gpPolicy == "warning" else GP_SEV_INFO
		gpOut.append(_gpShapeF(gpSnap, "drc.symbol", gpSev, "drc.symbol_not_library",
			["#%d" % gpIdx], gpIdx, gpBox.get_center(), "drc.symbol.not_library",
			"drc.fix.promote_symbol"))
	return gpOut


# =====================================================================
# DOC — sheet identity / title block / 图纸身份与图签
# =====================================================================

static func gpCheckSheetNumber(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	if gpSnap.sheet == null:
		return []
	var gpOut: Array[GPFinding] = []
	if gpSnap.sheet.gpNumber.strip_edges() == "":
		gpOut.append(GPFinding.gpMake("drc.doc", GP_SEV_ERROR, "drc.sheet_number_missing",
			[gpSnap.sheet.gpName]).gpAs("drc.doc.sheet_number_missing", "drc.fix.set_number")
			.gpOnEntity(gpSnap.sheet_id, gpSnap.sheet_id))
	return gpOut


static func gpCheckTitleBlockDrawingNo(gpSnap: GPDrcSnapshot,
		_gpCfg: Dictionary) -> Array[GPFinding]:
	if gpSnap.sheet == null:
		return []
	var gpNo: String = gpSnap.sheet.gpNumber.strip_edges()
	if gpNo == "":
		return []
	var gpBlock: String = gpSnap.sheet.gpTitleValueWithProject("drawing_no", gpSnap.std)
	if gpBlock == "" or gpBlock == gpNo:
		return []
	return [GPFinding.gpMake("drc.doc", GP_SEV_WARNING, "drc.title_block_drawing_no",
		[gpBlock, gpNo]).gpAs("drc.doc.title_block_drawing_no", "drc.fix.set_title_block")
		.gpOnEntity(gpSnap.sheet_id, gpSnap.sheet_id)]


static func gpCheckTitleBlockRequired(gpSnap: GPDrcSnapshot,
		_gpCfg: Dictionary) -> Array[GPFinding]:
	if gpSnap.sheet == null:
		return []
	var gpOut: Array[GPFinding] = []
	# drawing_no / drawing_title are identity: error. The rest are completeness: warning.
	var gpRequired: Array = [
		["drawing_no", "frame.fld.drawing_no", GP_SEV_ERROR],
		["drawing_title", "frame.fld.drawing_title", GP_SEV_ERROR],
		["project", "frame.fld.project", GP_SEV_WARNING],
		["designed", "frame.fld.designed", GP_SEV_WARNING],
		["checked", "frame.fld.checked", GP_SEV_WARNING],
		["approved", "frame.fld.approved", GP_SEV_WARNING],
	]
	for gpRow in gpRequired:
		var gpKey: String = str((gpRow as Array)[0])
		var gpVal: String = gpSnap.sheet.gpTitleValueWithProject(gpKey, gpSnap.std)
		if gpVal.strip_edges() != "":
			continue
		gpOut.append(GPFinding.gpMake("drc.doc", str((gpRow as Array)[2]),
			"drc.title_block_required", [GPLocalizer.gpTr(str((gpRow as Array)[1]))])
			.gpAs("drc.doc.title_block_required", "drc.fix.fill_title_block")
			.gpOnEntity(gpSnap.sheet_id, gpSnap.sheet_id))
	return gpOut


# Symbols / lines / annotations must not sit on the title block.
# 图元 / 连线 / 注释不得压在标题栏上。
static func gpCheckTitleBlockIntrusion(gpSnap: GPDrcSnapshot,
		_gpCfg: Dictionary) -> Array[GPFinding]:
	if gpSnap.sheet != null and not gpSnap.sheet.gpFrameOn:
		return []
	if gpSnap.title_rect.size.x <= 0.0 or gpSnap.title_rect.size.y <= 0.0:
		return []
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.nodes.keys():
		var gpNId: String = str(gpId)
		var gpR: Rect2 = gpSnap.gpRect(gpNId)
		if gpR.intersects(gpSnap.title_rect):
			gpOut.append(_gpNodeF(gpSnap, "drc.layout", GP_SEV_WARNING,
				"drc.title_block_intrusion", [gpSnap.gpNodeLabel(gpNId)], gpNId,
				gpR.get_center(), "drc.layout.title_block_intrusion", "drc.fix.move"))
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpPts: PackedVector2Array = gpSnap.gpPolyline(gpEId)
		if GPDRCGeometry.gpPolylineHitsRect(gpPts, gpSnap.title_rect):
			gpOut.append(_gpEdgeF(gpSnap, "drc.layout", GP_SEV_WARNING,
				"drc.title_block_intrusion", [gpSnap.gpEdgeLabel(gpEId)], gpEId,
				_gpMid(gpSnap, gpEId), "drc.layout.title_block_intrusion", "drc.fix.move"))
	return gpOut


# =====================================================================
# LAYOUT — lines / labels / annotations / 布局
# =====================================================================

# Two different lines sharing a collinear run is a real ambiguity (not a crossing).
# 两条不同连线共用一段共线走向，是真正的歧义（不是交叉）。
static func gpCheckLineOverlap(gpSnap: GPDrcSnapshot, gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	var gpMin: float = GPDRCConfig.gpThreshold(gpCfg, "line_overlap_mm", 2.0)
	var gpIds: Array = gpSnap.edges.keys()
	for gpI in range(gpIds.size()):
		var gpAId: String = str(gpIds[gpI])
		var gpA: Dictionary = gpSnap.gpEdge(gpAId)
		var gpEA: GPPIDEdge = gpA.get("edge") as GPPIDEdge
		var gpPa: PackedVector2Array = gpA.get("polyline", PackedVector2Array())
		if gpEA == null or gpPa.size() < 2:
			continue
		for gpJ in range(gpI + 1, gpIds.size()):
			var gpBId: String = str(gpIds[gpJ])
			var gpB: Dictionary = gpSnap.gpEdge(gpBId)
			var gpEB: GPPIDEdge = gpB.get("edge") as GPPIDEdge
			if gpEB == null or _gpShareNode(gpEA, gpEB) or _gpSameTag(gpEA, gpEB):
				continue
			var gpPb: PackedVector2Array = gpB.get("polyline", PackedVector2Array())
			if gpPb.size() < 2:
				continue
			var gpFound: bool = false
			for gpA1 in range(gpPa.size() - 1):
				for gpB1 in range(gpPb.size() - 1):
					if GPDRCGeometry.gpCollinearOverlap(gpPa[gpA1], gpPa[gpA1 + 1],
							gpPb[gpB1], gpPb[gpB1 + 1]) >= gpMin:
						gpFound = true
						break
				if gpFound:
					break
			if gpFound:
				gpOut.append(_gpEdgeF(gpSnap, "drc.layout", GP_SEV_WARNING, "drc.line_overlap",
					[gpSnap.gpEdgeLabel(gpAId), gpSnap.gpEdgeLabel(gpBId)], gpAId,
					_gpMid(gpSnap, gpAId), "drc.layout.line_overlap", "drc.fix.reroute"))
	return gpOut


# Parallel lines closer than the project gap over a meaningful run are hard to read.
# 平行线间距小于工程阈值且并行长度可观时，图面难读。
static func gpCheckLineTooClose(gpSnap: GPDrcSnapshot, gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	var gpGap: float = GPDRCConfig.gpThreshold(gpCfg, "line_gap_mm", 8.0)
	var gpRun: float = GPDRCConfig.gpThreshold(gpCfg, "parallel_len_mm", 30.0)
	var gpIds: Array = gpSnap.edges.keys()
	for gpI in range(gpIds.size()):
		var gpAId: String = str(gpIds[gpI])
		var gpA: Dictionary = gpSnap.gpEdge(gpAId)
		var gpEA: GPPIDEdge = gpA.get("edge") as GPPIDEdge
		var gpPa: PackedVector2Array = gpA.get("polyline", PackedVector2Array())
		if gpEA == null or gpPa.size() < 2:
			continue
		for gpJ in range(gpI + 1, gpIds.size()):
			var gpBId: String = str(gpIds[gpJ])
			var gpB: Dictionary = gpSnap.gpEdge(gpBId)
			var gpEB: GPPIDEdge = gpB.get("edge") as GPPIDEdge
			if gpEB == null or _gpShareNode(gpEA, gpEB) or _gpSameTag(gpEA, gpEB):
				continue
			var gpPb: PackedVector2Array = gpB.get("polyline", PackedVector2Array())
			if gpPb.size() < 2:
				continue
			var gpFound: bool = false
			for gpA1 in range(gpPa.size() - 1):
				for gpB1 in range(gpPb.size() - 1):
					var gpRunD: Dictionary = GPDRCGeometry.gpParallelRun(gpPa[gpA1],
						gpPa[gpA1 + 1], gpPb[gpB1], gpPb[gpB1 + 1])
					if bool(gpRunD.get("parallel", false)) \
							and float(gpRunD.get("dist", 999.0)) < gpGap \
							and float(gpRunD.get("overlap", 0.0)) >= gpRun:
						gpFound = true
						break
				if gpFound:
					break
			if gpFound:
				gpOut.append(_gpEdgeF(gpSnap, "drc.layout", GP_SEV_INFO, "drc.line_too_close",
					[gpSnap.gpEdgeLabel(gpAId), gpSnap.gpEdgeLabel(gpBId)], gpAId,
					_gpMid(gpSnap, gpAId), "drc.layout.line_too_close", "drc.fix.reroute"))
	return gpOut


# Labels must not collide with each other / other symbols.
# 标注不得彼此相压或压到别的图元。
static func gpCheckLabelOverlap(gpSnap: GPDrcSnapshot, gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	var gpGap: float = GPDRCConfig.gpThreshold(gpCfg, "label_gap_mm", 1.0)
	var gpIds: Array = gpSnap.nodes.keys()
	for gpI in range(gpIds.size()):
		var gpAId: String = str(gpIds[gpI])
		var gpA: Dictionary = gpSnap.gpNode(gpAId)
		var gpRA: Rect2 = gpA.get("label_rect", Rect2())
		if gpRA.size.x <= 0.0:
			continue
		for gpJ in range(gpI + 1, gpIds.size()):
			var gpBId: String = str(gpIds[gpJ])
			if gpSnap.gpRoot(gpAId) == gpSnap.gpRoot(gpBId):
				continue
			var gpRB: Rect2 = gpSnap.gpNode(gpBId).get("label_rect", Rect2())
			if gpRB.size.x <= 0.0:
				continue
			if gpRA.grow(-gpGap).intersects(gpRB.grow(-gpGap)):
				gpOut.append(_gpNodeF(gpSnap, "drc.layout", GP_SEV_WARNING, "drc.label_overlap",
					[gpSnap.gpNodeLabel(gpAId), gpSnap.gpNodeLabel(gpBId)], gpAId,
					gpRA.get_center(), "drc.layout.label_overlap", "drc.fix.move_label"))
		# A label over another symbol's envelope is equally unreadable.
		for gpBId in gpIds:
			if str(gpBId) == gpAId or gpSnap.gpRoot(gpAId) == gpSnap.gpRoot(str(gpBId)):
				continue
			var gpRB: Rect2 = gpSnap.gpRect(str(gpBId))
			if gpRB.size.x > 0.0 and gpRA.grow(-gpGap).intersects(gpRB.grow(-gpGap)):
				gpOut.append(_gpNodeF(gpSnap, "drc.layout", GP_SEV_WARNING, "drc.label_overlap",
					[gpSnap.gpNodeLabel(gpAId), gpSnap.gpNodeLabel(str(gpBId))], gpAId,
					gpRA.get_center(), "drc.layout.label_overlap", "drc.fix.move_label"))
				break
	return gpOut


static func gpCheckLabelOffSheet(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	if gpSnap.paper_rect.size.x <= 0.0:
		return []
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.nodes.keys():
		var gpNId: String = str(gpId)
		var gpR: Rect2 = gpSnap.gpNode(gpNId).get("label_rect", Rect2())
		if gpR.size.x > 0.0 and not gpSnap.paper_rect.encloses(gpR):
			gpOut.append(_gpNodeF(gpSnap, "drc.layout", GP_SEV_WARNING, "drc.label_off_sheet",
				[gpSnap.gpNodeLabel(gpNId)], gpNId, gpR.get_center(),
				"drc.layout.label_off_sheet", "drc.fix.move_label"))
	return gpOut


# Free annotation lines should not cut through equipment.
# 自由注释线不应穿过设备。
static func gpCheckAnnotationCrosses(gpSnap: GPDrcSnapshot,
		_gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpIdx in range(gpSnap.shapes.size()):
		var gpS: GPShape = gpSnap.shapes[gpIdx] as GPShape
		if gpS == null or gpS.gpKind == GPShape.GPKind.GP_TEXT:
			continue
		var gpPts: PackedVector2Array = gpS.gpPoints
		if gpPts.size() < 2:
			continue
		for gpNId in gpSnap.nodes.keys():
			var gpR: Rect2 = gpSnap.gpRect(str(gpNId))
			if GPDRCGeometry.gpPolylineHitsRect(gpPts, gpR.grow(-0.5)):
				gpOut.append(_gpShapeF(gpSnap, "drc.layout", GP_SEV_INFO,
					"drc.annotation_crosses", ["#%d" % gpIdx, gpSnap.gpNodeLabel(str(gpNId))],
					gpIdx, gpR.get_center(), "drc.layout.annotation_crosses", "drc.fix.move"))
				break
	return gpOut


# =====================================================================
# TOPO — branches / signal endpoints / attributes / 拓扑补充
# =====================================================================

static func gpCheckBranchOnLine(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpE: GPPIDEdge = (gpSnap.gpEdge(gpEId).get("edge") as GPPIDEdge)
		if gpE == null:
			continue
		for gpIsFrom in [true, false]:
			var gpRef: Dictionary = gpE.gpFromRef if gpIsFrom else gpE.gpToRef
			var gpEnd: Dictionary = gpSnap.gpEdge(gpEId).get("from" if gpIsFrom else "to", {})
			var gpPos: Vector2 = (gpEnd as Dictionary).get("pos", Vector2.INF)
			if gpPos == Vector2.INF:
				continue
			for gpOther in gpSnap.edges.keys():
				if str(gpOther) == gpEId:
					continue
				var gpO: GPPIDEdge = (gpSnap.gpEdge(str(gpOther)).get("edge") as GPPIDEdge)
				if gpO == null or _gpShareNode(gpE, gpO):
					continue
				var gpPts: PackedVector2Array = gpSnap.gpPolyline(str(gpOther))
				var gpHit: bool = false
				for gpI in range(gpPts.size() - 1):
					if GPDRCGeometry.gpPointOnSegmentInterior(gpPos, gpPts[gpI],
							gpPts[gpI + 1], 0.5):
						gpHit = true
						break
				if gpHit:
					gpOut.append(_gpEdgeF(gpSnap, "drc.topo", GP_SEV_ERROR, "drc.branch_on_line",
						[gpSnap.gpEdgeLabel(gpEId), gpSnap.gpEdgeLabel(str(gpOther))], gpEId,
						gpPos, "drc.topo.branch_on_line", "drc.fix.add_junction"))
					break
	return gpOut


static func gpCheckSignalEndpoint(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpE: GPPIDEdge = (gpSnap.gpEdge(gpEId).get("edge") as GPPIDEdge)
		if gpE == null or gpE.gpKind != GPPIDEdge.GP_SIGNAL:
			continue
		for gpIsFrom in [true, false]:
			var gpRef: Dictionary = gpE.gpFromRef if gpIsFrom else gpE.gpToRef
			var gpNId: String = str(gpRef.get("node_id", ""))
			if gpNId == "" or not gpSnap.gpHasNode(gpNId):
				continue
			var gpDef: GPSymbolDef = gpSnap.gpNode(gpNId).get("def") as GPSymbolDef
			if gpDef == null:
				continue
			var gpOk: bool = gpDef.gpCategory == "instrument" or gpDef.gpCategory == "electrical" \
				or gpDef.gpCategory == "valve" or gpDef.gpCategory == "general"
			if not gpOk:
				gpOut.append(_gpEdgeF(gpSnap, "drc.topo", GP_SEV_WARNING,
					"drc.signal_endpoint", [gpSnap.gpEdgeLabel(gpEId),
						gpSnap.gpNodeLabel(gpNId)], gpEId, _gpMid(gpSnap, gpEId),
					"drc.topo.signal_endpoint", "drc.fix.relink"))
	return gpOut


static func gpCheckDnMatch(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpE: GPPIDEdge = (gpSnap.gpEdge(gpEId).get("edge") as GPPIDEdge)
		if gpE == null or gpE.gpKind == GPPIDEdge.GP_SIGNAL:
			continue
		var gpDn: int = _gpDigits(str(gpE.gpAttrs.get("dn", "")))
		if gpDn <= 0:
			continue
		for gpIsFrom in [true, false]:
			var gpRef: Dictionary = gpE.gpFromRef if gpIsFrom else gpE.gpToRef
			var gpNId: String = str(gpRef.get("node_id", ""))
			if gpNId == "":
				continue
			var gpN: GPPIDNode = gpSnap.graph.gpGetNode(gpNId)
			if gpN == null:
				continue
			var gpNoz: int = _gpDigits(str(gpN.gpProps.get("nominal_size", "")))
			if gpNoz > 0 and gpNoz != gpDn:
				gpOut.append(_gpEdgeF(gpSnap, "drc.topo", GP_SEV_WARNING, "drc.dn_match",
					[gpSnap.gpEdgeLabel(gpEId), "DN%d / DN%d" % [gpDn, gpNoz]], gpEId,
					_gpMid(gpSnap, gpEId), "drc.topo.dn_match", "drc.fix.change_reducer"))
				break
	return gpOut


static func gpCheckMediaContinuity(gpSnap: GPDrcSnapshot,
		_gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpNId in gpSnap.nodes.keys():
		var gpMeds: Dictionary = {}
		for gpEId in gpSnap.edges.keys():
			var gpE: GPPIDEdge = (gpSnap.gpEdge(str(gpEId)).get("edge") as GPPIDEdge)
			if gpE == null or gpE.gpKind == GPPIDEdge.GP_SIGNAL:
				continue
			if str(gpE.gpFromRef.get("node_id", "")) != str(gpNId) \
					and str(gpE.gpToRef.get("node_id", "")) != str(gpNId):
				continue
			var gpMed: String = str(gpE.gpAttrs.get("medium", "")).strip_edges()
			if gpMed != "":
				gpMeds[gpMed.to_upper()] = true
		if gpMeds.size() > 1:
			gpOut.append(_gpNodeF(gpSnap, "drc.topo", GP_SEV_INFO,
				"drc.media_continuity", [gpSnap.gpNodeLabel(str(gpNId))], str(gpNId),
				gpSnap.gpNode(str(gpNId)).get("origin", Vector2.ZERO),
				"drc.topo.media_continuity", "drc.fix.check_medium"))
	return gpOut


# =====================================================================
# DOC — inheritance / frame / 图签继承与图框
# =====================================================================

static func gpCheckTitleBlockInherit(gpSnap: GPDrcSnapshot,
		_gpCfg: Dictionary) -> Array[GPFinding]:
	if gpSnap.sheet == null or gpSnap.std == null:
		return []
	var gpOut: Array[GPFinding] = []
	var gpFields: Array = [
		["company", "company"], ["project", "project_name"],
		["designed", "designed"], ["checked", "checked"], ["approved", "approved"],
	]
	for gpRow in gpFields:
		var gpKey: String = str((gpRow as Array)[0])
		var gpInfoKey: String = str((gpRow as Array)[1])
		var gpOwn: String = gpSnap.sheet.gpTitleValue(gpKey).strip_edges()
		var gpProj: String = gpSnap.std.gpInfo(gpInfoKey).strip_edges()
		if gpOwn != "" and gpProj != "" and gpOwn != gpProj:
			gpOut.append(GPFinding.gpMake("drc.doc", GP_SEV_INFO, "drc.title_block_inherit",
				[GPLocalizer.gpTr("frame.fld." + gpKey), gpOwn, gpProj])
				.gpAs("drc.doc.title_block_inherit", "drc.fix.review_override")
				.gpOnEntity(gpSnap.sheet_id, gpSnap.sheet_id))
	return gpOut


static func gpCheckFrame(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	if gpSnap.sheet == null or gpSnap.sheet.gpFrameOn:
		return []
	return [GPFinding.gpMake("drc.doc", GP_SEV_WARNING, "drc.frame_off",
		[gpSnap.sheet.gpName]).gpAs("drc.doc.frame_off", "drc.fix.frame_on")
		.gpOnEntity(gpSnap.sheet_id, gpSnap.sheet_id)]


# ---- small helpers / 小辅助 ----

static func _gpShareNode(gpA: GPPIDEdge, gpB: GPPIDEdge) -> bool:
	var gpAn: Array[String] = [str(gpA.gpFromRef.get("node_id", "")),
		str(gpA.gpToRef.get("node_id", ""))]
	for gpRef in [gpB.gpFromRef, gpB.gpToRef]:
		if gpAn.has(str((gpRef as Dictionary).get("node_id", ""))):
			return true
	return false


static func _gpSameTag(gpA: GPPIDEdge, gpB: GPPIDEdge) -> bool:
	var gpTa: String = gpA.gpTag.strip_edges()
	return gpTa != "" and gpTa == gpB.gpTag.strip_edges()


static func _gpDigits(gpText: String) -> int:
	var gpDigits: String = ""
	for gpI in range(gpText.length()):
		var gpC: String = gpText[gpI]
		if gpC >= "0" and gpC <= "9":
			gpDigits += gpC
	return int(gpDigits) if gpDigits != "" else 0


# =====================================================================
# TAG / DOC — project-configurable checks / 项目可配置检查
# =====================================================================

# A tag's prefix should match the symbol definition's category prefix (P for pump, T for tank…).
# 位号前缀应与图元定义的类别前缀一致（泵 P、容器 T…）。
static func gpCheckPrefixCategory(gpSnap: GPDrcSnapshot, _gpCfg: Dictionary) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.nodes.keys():
		var gpNId: String = str(gpId)
		var gpD: Dictionary = gpSnap.gpNode(gpNId)
		var gpN: GPPIDNode = gpD.get("node") as GPPIDNode
		var gpDef: GPSymbolDef = gpD.get("def") as GPSymbolDef
		if gpN == null or gpDef == null or gpN.gpTag.strip_edges() == "" \
				or gpDef.gpTagPrefix.strip_edges() == "":
			continue
		var gpPrefix: String = gpDef.gpTagPrefix.strip_edges().to_upper()
		var gpTag: String = gpN.gpTag.strip_edges().to_upper()
		if not gpTag.begins_with(gpPrefix):
			gpOut.append(_gpNodeF(gpSnap, "drc.tag", GP_SEV_WARNING, "drc.tag_prefix_category",
				[gpSnap.gpNodeLabel(gpNId), gpPrefix], gpNId,
				gpD.get("origin", Vector2.ZERO), "drc.tag.prefix_category", "drc.fix.renumber"))
	return gpOut


# Signal lines need a loop number only when the project opts in (`policy.signal_loop_required`).
# 只有工程显式开启 `policy.signal_loop_required` 时，信号线才要求回路号。
static func gpCheckLoopNumber(gpSnap: GPDrcSnapshot, gpCfg: Dictionary) -> Array[GPFinding]:
	if not bool(GPDRCConfig.gpPolicy(gpCfg, "signal_loop_required", false)):
		return []
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpE: GPPIDEdge = (gpSnap.gpEdge(gpEId).get("edge") as GPPIDEdge)
		if gpE == null or gpE.gpKind != GPPIDEdge.GP_SIGNAL:
			continue
		var gpLoop: String = str(gpE.gpAttrs.get("loop", "")).strip_edges()
		if gpLoop == "":
			gpOut.append(_gpEdgeF(gpSnap, "drc.topo", GP_SEV_WARNING, "drc.loop_number",
				[gpSnap.gpEdgeLabel(gpEId)], gpEId, _gpMid(gpSnap, gpEId),
				"drc.topo.loop_number", "drc.fix.fill_loop"))
	return gpOut


# =====================================================================
# P4 SEM — project-opt-in semantic checks / 项目可选的工艺语义检查
# =====================================================================

static func gpCheckRevision(gpSnap: GPDrcSnapshot, gpCfg: Dictionary) -> Array[GPFinding]:
	if gpSnap.sheet == null or gpSnap.std == null:
		return []
	if not bool(GPDRCConfig.gpPolicy(gpCfg, "revision_required", false)):
		return []
	var gpOut: Array[GPFinding] = []
	for gpKey in ["rev", "date"]:
		if gpSnap.sheet.gpTitleValue(gpKey).strip_edges() == "":
			gpOut.append(GPFinding.gpMake("drc.doc", GP_SEV_WARNING, "drc.revision_missing",
				[GPLocalizer.gpTr("frame.fld." + gpKey)])
				.gpAs("drc.doc.revision_missing", "drc.fix.fill_title_block")
				.gpOnEntity(gpSnap.sheet_id, gpSnap.sheet_id))
	return gpOut


# An automatic valve needs a signal connection (project opt-in).
# 自动阀需要信号线连接（项目开启时）。
static func gpCheckValveActuator(gpSnap: GPDrcSnapshot, gpCfg: Dictionary) -> Array[GPFinding]:
	if not bool(GPDRCConfig.gpPolicy(gpCfg, "sem_enabled", false)):
		return []
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.nodes.keys():
		var gpNId: String = str(gpId)
		var gpD: Dictionary = gpSnap.gpNode(gpNId)
		var gpN: GPPIDNode = gpD.get("node") as GPPIDNode
		var gpDef: GPSymbolDef = gpD.get("def") as GPSymbolDef
		if gpN == null or gpDef == null or gpDef.gpCategory != "valve":
			continue
		var gpAct: String = str(gpN.gpProps.get("actuator_type", "")).strip_edges()
		if gpAct == "" or gpAct == "手动" or gpAct == "无":
			continue
		if not _gpNodeHasSignal(gpSnap, gpNId):
			gpOut.append(_gpNodeF(gpSnap, "drc.sem", GP_SEV_WARNING, "drc.sem_valve_actuator",
				[gpSnap.gpNodeLabel(gpNId), gpAct], gpNId, gpD.get("origin", Vector2.ZERO),
				"drc.sem.valve_actuator", "drc.fix.add_signal"))
	return gpOut


# A field instrument needs a signal connection (project opt-in).
# 现场仪表需要信号线连接（项目开启时）。
static func gpCheckInstrumentLoop(gpSnap: GPDrcSnapshot, gpCfg: Dictionary) -> Array[GPFinding]:
	if not bool(GPDRCConfig.gpPolicy(gpCfg, "sem_enabled", false)):
		return []
	var gpOut: Array[GPFinding] = []
	for gpId in gpSnap.nodes.keys():
		var gpNId: String = str(gpId)
		var gpD: Dictionary = gpSnap.gpNode(gpNId)
		var gpDef: GPSymbolDef = gpD.get("def") as GPSymbolDef
		if gpDef == null or gpDef.gpCategory != "instrument":
			continue
		if not _gpNodeHasSignal(gpSnap, gpNId):
			gpOut.append(_gpNodeF(gpSnap, "drc.sem", GP_SEV_WARNING, "drc.sem_instrument_loop",
				[gpSnap.gpNodeLabel(gpNId)], gpNId, gpD.get("origin", Vector2.ZERO),
				"drc.sem.instrument_loop", "drc.fix.add_signal"))
	return gpOut


# Medium / spec codes must exist in the project code tables (when those tables are populated).
# 介质 / 材料等级代号必须在项目代号表中存在（表非空时）。
static func gpCheckLineClass(gpSnap: GPDrcSnapshot, gpCfg: Dictionary) -> Array[GPFinding]:
	if not bool(GPDRCConfig.gpPolicy(gpCfg, "sem_enabled", false)) or gpSnap.std == null:
		return []
	var gpOut: Array[GPFinding] = []
	var gpTable: Array = gpSnap.std.gpCodeTable("medium")
	if gpTable.is_empty():
		return gpOut
	for gpId in gpSnap.edges.keys():
		var gpEId: String = str(gpId)
		var gpE: GPPIDEdge = (gpSnap.gpEdge(gpEId).get("edge") as GPPIDEdge)
		if gpE == null or gpE.gpKind == GPPIDEdge.GP_SIGNAL:
			continue
		var gpMed: String = str(gpE.gpAttrs.get("medium", "")).strip_edges()
		if gpMed == "":
			continue
		if gpSnap.std.gpCodeOf("medium", gpMed) == "":
			gpOut.append(_gpEdgeF(gpSnap, "drc.sem", GP_SEV_INFO, "drc.sem_line_class",
				[gpSnap.gpEdgeLabel(gpEId), gpMed], gpEId, _gpMid(gpSnap, gpEId),
				"drc.sem.line_class", "drc.fix.use_code"))
	return gpOut


static func _gpNodeHasSignal(gpSnap: GPDrcSnapshot, gpNodeId: String) -> bool:
	for gpId in gpSnap.edges.keys():
		var gpE: GPPIDEdge = (gpSnap.gpEdge(str(gpId)).get("edge") as GPPIDEdge)
		if gpE == null or gpE.gpKind != GPPIDEdge.GP_SIGNAL:
			continue
		if str(gpE.gpFromRef.get("node_id", "")) == gpNodeId \
				or str(gpE.gpToRef.get("node_id", "")) == gpNodeId:
			return true
	return false
