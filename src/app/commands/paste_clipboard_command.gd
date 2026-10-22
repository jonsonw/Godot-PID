class_name GPPasteClipboardCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Paste the clipboard payload into THIS sheet as one undoable step (A6).
# 把剪贴板载荷粘贴到**当前**图纸，作为一步可撤销的编辑（A6）。
#
# Why the payload is re-cloned here and not stored as objects / 为何在此重新克隆而非存对象：
# The payload comes from ANOTHER graph (that is what cross-sheet paste means). Reusing the source
# objects would make two sheets share one node — editing either would silently edit both. So the
# command clones from DICTIONARIES into this context's graph.
# 载荷来自**另一张**图（跨图纸粘贴就是这个意思）。复用源对象会让两张图共享一个节点 ——
# 改任一张都静默改到另一张。故本命令从**字典**克隆进本上下文的图。
#
# What is dropped, and why / 什么会被丢弃，以及为什么：
#   * an edge whose end is NOT a node reference (a dangling end) is skipped: a dangling end is a
#     POINT in world space belonging to the source sheet, and pasting a point that means nothing
#     on this sheet would create a line to nowhere.
#   * a mounted child whose host was NOT copied becomes top-level: its old parent does not exist
#     here, and keeping the stale id would make the resolver walk a chain into nothing.
#   * an edge whose OTHER end is not in the pasted set is skipped for the same reason.
#   端点不是节点引用（悬空端）的边被跳过：悬空端是源图纸上的一个世界坐标点，粘到本图纸上毫无意义，
#   只会造出一条通往虚无的线。宿主未被一并复制的挂载子件降为顶层：旧父件在此不存在，保留过期 id
#   会让解析器沿一条通向虚无的父链行走。另一端不在粘贴集内的边同样跳过。
#
# Tags / 位号：
# A pasted top-level device is a DIFFERENT piece of equipment, so it must not carry the source's
# tag (two identical tags on one sheet is a drafting defect) — a fresh one is minted when the tag
# service is available, exactly like GPDuplicateNodesCommand. A mounted part keeps the source text
# (normally ""), because parts are identified by their own property, not by a tag.
# 粘贴出来的顶层设备是**另一台**设备，故不得沿用源位号（一张图纸上两个相同位号是制图缺陷）——
# 有标签服务时铸造新号，与 GPDuplicateNodesCommand 完全一致。挂载部件保留源文本（通常为 ""），
# 因为部件由其自身属性标识，而非位号。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Offset applied to every pasted root, in world units. Same value the duplicate path uses, so
# "duplicate" and "copy → paste in the same sheet" land in the same place.
# 每个粘贴根的偏移量（世界单位）。与复制路径同值，使「原地复制」与「复制→同图粘贴」落在同一点。
const GP_OFFSET: Vector2 = Vector2(24.0, 24.0)

# Captured payload (dictionaries), deep-copied at construction so a later clipboard change cannot
# mutate an in-flight command.
# 捕获的载荷（字典），构造时深拷贝，使之后剪贴板的变化无法改到进行中的命令。
var _gpNodes: Array = []

# Captured edge dictionaries.
# 捕获的连线字典。
var _gpEdges: Array = []

# Captured shape dictionaries.
# 捕获的图形字典。
var _gpShapes: Array = []

# Offset applied to pasted roots.
# 粘贴根的偏移量。
var _gpDelta: Vector2 = GP_OFFSET

# Created nodes, kept so redo re-adds the same objects with the same ids.
# 已创建的节点，保留使重做能用相同 id 重新加入同一批对象。
var _gpClones: Array[GPPIDNode] = []

# Created edges, same reason.
# 已创建的连线，同理。
var _gpEdgeClones: Array[GPPIDEdge] = []

# Created shapes, same reason.
# 已创建的图形，同理。
var _gpShapeClones: Array[GPShape] = []

# Source instance id -> clone id, used to remap parent chains and edge ends.
# 源实例 id → 副本 id，用于重映射父链与连线端点。
var _gpMap: Dictionary = {}

# Ids of the created nodes, available after gpExecute() so the caller can select the paste.
# 已创建节点的 id，gpExecute() 之后可用，供调用方选中粘贴结果。
var gpNewIds: Array[String] = []

# Refusal reason when execute returns false without a hard failure ("" when none).
# 执行返回 false 且非硬失败时的拒绝原因（无则 ""）。
var gpRefusal: String = ""


# Build from a payload snapshot and the offset to apply.
# 由载荷快照与偏移量构造。
func _init(gpNodes: Array, gpEdges: Array, gpShapes: Array,
		gpDelta: Vector2 = GP_OFFSET) -> void:
	_gpNodes = gpNodes.duplicate(true)
	_gpEdges = gpEdges.duplicate(true)
	_gpShapes = gpShapes.duplicate(true)
	_gpDelta = gpDelta
	gpLabel = "粘贴"


# Clone the payload into this sheet. Returns false when nothing could be created, so an empty
# clipboard records no undo step.
# 把载荷克隆进本图。什么都建不出来时返回 false，使空剪贴板不产生撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	gpRefusal = ""
	if gpCtx == null or gpCtx.gpGraph == null:
		gpRefusal = "no_graph"
		return false
	_gpClones.clear()
	_gpEdgeClones.clear()
	_gpShapeClones.clear()
	_gpMap.clear()
	gpNewIds.clear()

	# ---- pass 1: nodes ----
	# ---- 第一遍：节点 ----
	for gpRaw in _gpNodes:
		var gpD: Dictionary = gpRaw as Dictionary
		if gpD.is_empty():
			continue
		var gpSrcId: String = str(gpD.get("instance_id", ""))
		if gpSrcId == "":
			continue
		var gpNewId: String = gpCtx.gpIds.gpNext("n")
		var gpSymbolId: String = str(gpD.get("symbol_id", gpD.get("symbol", "")))
		var gpParentSrc: String = str(gpD.get("parent_uid", ""))
		var gpTopLevel: bool = gpParentSrc == "" or not _gpHasNode(gpD, gpParentSrc)
		var gpTag: String = str(gpD.get("tag", ""))
		if gpCtx.gpTags != null and gpTopLevel:
			gpCtx.gpTags.gpGraph = gpCtx.gpGraph
			gpTag = gpCtx.gpTags.gpNextTag(GPSymbolLibrary.gpFindById(gpSymbolId))
		var gpPos: Vector2 = _gpVec(gpD.get("position", []))
		if gpTopLevel:
			gpPos += _gpDelta
		var gpProps: Dictionary = gpD.get("props", {}) as Dictionary
		var gpN: GPPIDNode = gpCtx.gpGraph.gpNewNode(gpNewId, gpSymbolId, gpTag, gpPos,
			gpProps.duplicate(true))
		gpN.gpRotationDeg = float(gpD.get("rotation_deg", 0.0))
		gpN.gpFlipped = bool(gpD.get("flipped", false))
		gpN.gpMountAnchor = str(gpD.get("mount_anchor", ""))
		gpN.gpMountOffset = _gpVec(gpD.get("mount_offset", []))
		gpN.gpMountAngleDeg = float(gpD.get("mount_angle_deg", 0.0))
		# Parent is resolved in pass 2 (a child may be cloned before its host).
		# 父链在第二遍解析（子件可能先于宿主被克隆）。
		gpN.gpParentUid = "" if gpTopLevel else gpParentSrc
		gpCtx.gpGraph.gpAddNode(gpN)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRegister(gpNewId, gpTag)
		_gpClones.append(gpN)
		gpNewIds.append(gpNewId)
		_gpMap[gpSrcId] = gpNewId

	# ---- pass 2: parent remap ----
	# ---- 第二遍：父链重映射 ----
	for gpN in _gpClones:
		var gpParent: String = gpN.gpParentUid
		if gpParent == "":
			continue
		if _gpMap.has(gpParent):
			gpN.gpParentUid = str(_gpMap[gpParent])
		else:
			# Host not pasted (stale id from another sheet): become top-level. Silently keeping
			# the id would leave the node mounted on nothing.
			# 宿主未被粘贴（来自另一张图纸的过期 id）：降为顶层。静默保留该 id 等于把节点挂在虚空上。
			gpN.gpParentUid = ""

	# ---- pass 3: edges (both ends must map) ----
	# ---- 第三遍：连线（两端都必须能映射） ----
	for gpRaw in _gpEdges:
		var gpD: Dictionary = gpRaw as Dictionary
		if gpD.is_empty():
			continue
		var gpFrom: Dictionary = gpD.get("from_ref", {}) as Dictionary
		var gpTo: Dictionary = gpD.get("to_ref", {}) as Dictionary
		var gpFromNode: String = str(gpFrom.get("node_id", ""))
		var gpToNode: String = str(gpTo.get("node_id", ""))
		if gpFromNode == "" or gpToNode == "":
			# A dangling end is a world point on the SOURCE sheet; pasting it would draw a line to
			# nowhere. Skipped, not invented.
			# 悬空端是**源**图纸上的世界坐标点；粘过来只会画出一条通往虚无的线。跳过，不臆造。
			continue
		if not _gpMap.has(gpFromNode) or not _gpMap.has(gpToNode):
			continue
		var gpEid: String = gpCtx.gpIds.gpNext("e")
		var gpKind: String = str(gpD.get("kind", GPPIDEdge.GP_PROCESS))
		var gpSignalType: String = str(gpD.get("signal_type", ""))
		var gpETag: String = str(gpD.get("tag", ""))
		if gpETag != "":
			# Edge numbers are minted by GPTagGen (pipe prefix), NOT by the node tag registry:
			# the registry keys off a symbol DEFINITION, and a line has none — the connect command
			# mints its numbers exactly this way.
			# 线号由 GPTagGen（管线前缀）铸造，**不是**节点标签注册器：注册器按图元**定义**取规则，
			# 而线没有定义 —— 连线命令正是这么铸号的。
			gpETag = GPTagGen.gpNextTag(gpCtx.gpGraph)
		var gpNewFrom: Dictionary = {"node_id": str(_gpMap[gpFromNode]), "port_id": str(gpFrom.get("port_id", ""))}
		var gpNewTo: Dictionary = {"node_id": str(_gpMap[gpToNode]), "port_id": str(gpTo.get("port_id", ""))}
		var gpE: GPPIDEdge = gpCtx.gpGraph.gpNewEdgeEx(gpEid, gpNewFrom, gpNewTo, gpKind,
			gpSignalType, gpETag)
		gpE.gpOrtho = bool(gpD.get("ortho", true))
		gpE.gpAttrs = (gpD.get("attrs", {}) as Dictionary).duplicate(true)
		# Waypoints are copied as DATA relative to the sheet origin. They are kept verbatim
		# because a routed line that lost its bends would silently become a straight jump across
		# the sheet; the +delta on the nodes and the untouched polyline can disagree visually, so
		# the polyline is translated by the same delta as its (top-level) ends.
		# 折点作为**数据**按图面原点复制。原样保留，是因为丢掉折点的走线会静默变成横穿图纸的直线；
		# 节点加了偏移而折线没加会让二者视觉不符，故折线按其（顶层）端点平移同一偏移量。
		var gpRouting: Array[Vector2] = []
		for gpP in (gpD.get("routing", []) as Array):
			gpRouting.append(_gpVec(gpP) + _gpDelta)
		gpE.gpRouting = gpRouting
		gpCtx.gpGraph.gpAddEdge(gpE)
		_gpEdgeClones.append(gpE)

	# ---- pass 4: annotation shapes ----
	# ---- 第四遍：注释图形 ----
	for gpRaw in _gpShapes:
		var gpD: Dictionary = gpRaw as Dictionary
		if gpD.is_empty():
			continue
		var gpS: GPShape = GPShape.new()
		gpS.gpFromDict(gpD)
		# A shape's geometry is absolute, so every vertex moves with the paste offset — otherwise
		# the shape would land on top of the original it was copied from.
		# 图形的几何是绝对的，故每个顶点都随粘贴偏移移动 —— 否则它会原样压在来源图形上。
		var gpPts: PackedVector2Array = PackedVector2Array()
		for gpP in gpS.gpPoints:
			gpPts.append(gpP + _gpDelta)
		gpS.gpPoints = gpPts
		gpCtx.gpGraph.gpAddShape(gpS)
		_gpShapeClones.append(gpS)

	return not (_gpClones.is_empty() and _gpShapeClones.is_empty() and _gpEdgeClones.is_empty())


# Remove everything this paste created.
# 移除本次粘贴创建的一切。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpE in _gpEdgeClones:
		gpCtx.gpGraph.gpRemoveEdge(gpE.gpInstanceId)
	for gpN in _gpClones:
		gpCtx.gpGraph.gpRemoveNode(gpN.gpInstanceId)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRelease(gpN.gpInstanceId)
	for gpS in _gpShapeClones:
		gpCtx.gpGraph.gpRemoveShape(gpS)


# Re-add the very same objects (ids stay stable, so later references hold).
# 重新加入同一批对象（id 保持稳定，故后续引用依然成立）。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpN in _gpClones:
		gpCtx.gpGraph.gpAddNode(gpN)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRegister(gpN.gpInstanceId, gpN.gpTag)
	for gpE in _gpEdgeClones:
		gpCtx.gpGraph.gpAddEdge(gpE)
	for gpS in _gpShapeClones:
		gpCtx.gpGraph.gpAddShape(gpS)


# Whether the payload captured a node with this source instance id (used to decide "top-level").
# 载荷是否捕获了该源实例 id 的节点（用于判定「是否顶层」）。
func _gpHasNode(gpSelfDict: Dictionary, gpSrcId: String) -> bool:
	for gpRaw in _gpNodes:
		var gpD: Dictionary = gpRaw as Dictionary
		if str(gpD.get("instance_id", "")) == gpSrcId:
			return true
	return false


# Read a Vector2 stored as [x, y] (JSON shape) or as a Vector2 (already typed).
# 读取以 [x, y]（JSON 形态）或已是 Vector2 存储的坐标。
func _gpVec(gpV: Variant) -> Vector2:
	if gpV is Vector2:
		return gpV as Vector2
	if gpV is Array:
		var gpA: Array = gpV as Array
		if gpA.size() >= 2:
			return Vector2(float(gpA[0]), float(gpA[1]))
	return Vector2.ZERO
