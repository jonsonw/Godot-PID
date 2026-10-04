class_name GPPIDGraph
extends RefCounted

# P&ID topology data core: a strongly-typed node-edge graph.
# P&ID 拓扑数据内核：强类型的节点-边图。
# The 2D canvas, 3D linkage and list export all read this resource.
# 2D 画布、3D 联动、清单导出都读取这个 Resource。
# See 从零落地架构_分步实施.md Step 1.2 (object graph refactor).
# 见「从零落地架构_分步实施.md」Step 1.2（对象图重构）。

# Current on-disk meta version. One constant, because three writers would otherwise drift.
# 当前磁盘 meta 版本。集中为一个常量 —— 否则三个写出方迟早漂移。
#   1.1 -> port-aware edge shape (signal_type / ortho / dangling ends) + "tag_seq" high-water marks
#   1.2 -> hierarchical symbols: GPPIDNode.gpParentUid / gpMountAnchor, i.e. a node may be a
#          CHILD of another node (a nozzle mounted on a vessel, an actuator on a valve).
#   1.1 -> 端口感知的边（signal_type / ortho / 悬空端）+ "tag_seq" 管线号水位线
#   1.2 -> 层级图元：GPPIDNode.gpParentUid / gpMountAnchor —— 即一个节点可以是另一节点的**子件**
#          （装在容器上的管口、装在阀门上的执行机构）。
#
# ★ The version is a CAPABILITY statement, not a compatibility gate. Mount fields are still
# read through get(key, default), so a 1.1 file loads unchanged and simply has no mounts; the
# number only tells a reader that mounts MAY be present. Bumping it is therefore safe, and NOT
# bumping it would be the unsafe choice: a reader would have no cheap way to tell.
# ★ 版本号是**能力声明**，不是兼容闸门。挂载字段仍以 get(key, default) 读取，故 1.1 文件
# 照常加载、只是没有挂载；版本号只说明「挂载**可能**存在」。因此升级它是安全的，
# **不**升级反而不安全：读取方将无从廉价判断。
const GP_META_VERSION: String = "1.2"

# Project metadata stored inside the graph resource.
# 图资源内部保存的工程元数据。
# Older files keep loading: every new key is read through get(key, default).
# 旧文件照常加载：每个新键都以 get(key, default) 读取。
var gpMeta: Dictionary = {
	"version": GP_META_VERSION,
	"title": "",
	"sheets": 1,
}

# All symbol instances (nodes) in this sheet — strongly typed.
# 本图纸内所有图元实例（节点）——强类型。
# Not @export: Godot only exports built-ins / Resources / Nodes / enums, and GPPIDNode
# is a custom RefCounted. Serialization is manual via gpToDict (JSON), so no export needed.
# 不加 @export：Godot 仅允许导出内置类型 / Resource / Node / 枚举，而 GPPIDNode 是自定义
# RefCounted。序列化走手动 gpToDict()（JSON），故无需导出。
var gpNodes: Array[GPPIDNode] = []

# All connections (edges) between nodes in this sheet — strongly typed.
# 本图纸内节点之间的所有连线（边）——强类型。
var gpEdges: Array[GPPIDEdge] = []

# Embedded user symbol packs carried inside the saved file (data sovereignty).
# 随存盘文件一同携带的内嵌用户图元包（数据主权）。
# Self-contained: re-opening a *.pid.json restores the custom symbols without needing
# the separate user://symbol_packs/ files. Built by gpEmbedUserPacks() before save and
# rebuilt by gpFromDict() on load.
# 自包含：重新打开 *.pid.json 即可恢复自定义图元，无需单独的 user://symbol_packs/ 文件。
# 存盘前由 gpEmbedUserPacks() 填充，载入时由 gpFromDict() 重建。
var gpUserSymbolPacks: Array[GPSymbolPack] = []

# Free annotation shapes drawn directly on the sheet (line / circle / rectangle / polyline).
# 图纸上直接绘制的自由注释图形（直线 / 圆 / 矩形 / 折线）。
# These are decoration/annotation primitives that live in a flat layer, NOT symbol
# instances. They serialize with the graph so a *.pid.json round-trips them unchanged.
# 这些是处在扁平「图形层」的注释/装饰图元，不是图元实例。与图一同序列化，使 *.pid.json
# 往返后保持一致。
var gpShapes: Array[GPShape] = []

# library: a project's numbering convention belongs to the project, so reopening the
# archive years later reproduces the same convention (data sovereignty).
# 故多年后重开存档仍能复现同一套约定（数据主权）。
# Null until first touched; gpTagRulesOrCreate() materialises it.
# 首次使用前为 null；gpTagRulesOrCreate() 负责建立。
var gpTagRules: GPProjectTagRules = null

# keyed by symbol id: {"LPUMP003": "-12093481"}.
# Comparing it against the live library on load is how a drawing can tell that a field was
# added, renamed or deleted since it was saved — without that, "edit the library, every
# project follows" would silently diverge from the archived values.
# 载入时与活动库比对，图纸才能知道自存盘以来字段被增 / 改名 / 删过 ——
# 没有它，「改库即全项目同步」就会与已存档的取值静默分叉。
# Written only when non-empty, so a pre-M12 file keeps its exact v1/v2 byte shape.
# 仅在非空时写出，使 M12 之前的文件逐字节保持原有 v1/v2 形态。
var gpSchemaFingerprints: Dictionary = {}


# The project's numbering rules, creating the factory default on first use. Never null.
# 工程的编号规则，首次使用时建立出厂默认。绝不返回 null。
func gpTagRulesOrCreate() -> GPProjectTagRules:
	if gpTagRules == null:
		gpTagRules = GPProjectTagRules.gpDefaultRules()
	return gpTagRules


# Signals fired when data changes; the canvas subscribes to keep views in sync.
# 数据变化时发出的信号；画布订阅它们以保持视图同步。
signal gpNodeAdded(gpNode: GPPIDNode)
signal gpNodeRemoved(gpNode: GPPIDNode)
signal gpEdgeAdded(gpEdge: GPPIDEdge)
signal gpEdgeRemoved(gpEdge: GPPIDEdge)
signal gpGraphChanged()


# Convenience factory: build a node object from primitive fields.
# 便捷工厂：用原始字段构造一个节点对象。
func gpNewNode(gpId: String, gpSymbolId: String, gpLabel: String, gpPos: Vector2 = Vector2.ZERO, gpAttrs: Dictionary = {}) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpId
	gpN.gpSymbolId = gpSymbolId
	gpN.gpTag = gpLabel
	gpN.gpPosition = gpPos
	gpN.gpProps = gpAttrs.duplicate()
	return gpN


# Convenience factory: build an edge object (node-to-node) from primitive fields.
# 便捷工厂：用原始字段构造一条边对象（节点到节点）。
func gpNewEdge(gpId: String, gpFromId: String, gpToId: String, gpAttrs: Dictionary = {}) -> GPPIDEdge:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpInstanceId = gpId
	gpE.gpFromRef = {"node_id": gpFromId, "port_id": ""}
	gpE.gpToRef = {"node_id": gpToId, "port_id": ""}
	gpE.gpKind = "PROCESS"
	gpE.gpAttrs = gpAttrs.duplicate()
	return gpE


# Port-aware edge factory. Both refs accept any of the three end shapes documented on
# GPPIDEdge (port-bound / node-bound / dangling), so one factory covers every case the pipe
# and signal tools can produce. gpNewEdge() stays as-is so its existing callers and tests are
# untouched.
# 端口感知的边工厂。两端引用接受 GPPIDEdge 上记载的三种端点形态之一（端口绑定 / 节点绑定 /
# 悬空），故一个工厂即覆盖管道与信号工具能产出的全部情形。gpNewEdge() 保持原样，其既有
# 调用点与测试不受影响。
func gpNewEdgeEx(gpId: String, gpFrom: Dictionary, gpTo: Dictionary, gpKind: String,
		gpSignalType: String = "", gpTag: String = "", gpAttrs: Dictionary = {}) -> GPPIDEdge:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpInstanceId = gpId
	gpE.gpFromRef = gpFrom.duplicate(true)
	gpE.gpToRef = gpTo.duplicate(true)
	gpE.gpKind = gpKind
	gpE.gpSignalType = gpSignalType
	gpE.gpTag = gpTag
	gpE.gpAttrs = gpAttrs.duplicate(true)
	return gpE


# Add a node object to the graph.
# 向图中添加一个节点对象。
func gpAddNode(gpNode: GPPIDNode) -> void:
	gpNodes.append(gpNode)
	gpNodeAdded.emit(gpNode)
	gpGraphChanged.emit()


# Add an edge object to the graph.
# 向图中添加一条边对象。
func gpAddEdge(gpEdge: GPPIDEdge) -> void:
	gpEdges.append(gpEdge)
	gpEdgeAdded.emit(gpEdge)
	gpGraphChanged.emit()


# Add a free annotation shape (line / circle / rectangle / polyline) to the sheet's shape layer.
# 向图纸图形层添加一枚自由注释图形（直线 / 圆 / 矩形 / 折线）。
func gpAddShape(gpShape: GPShape) -> void:
	gpShapes.append(gpShape)
	gpGraphChanged.emit()


# Find a node by id. Returns null when missing.
# 按 id 查找节点；找不到返回 null。
func gpGetNode(gpId: String) -> GPPIDNode:
	for gpN in gpNodes:
		if gpN.gpInstanceId == gpId:
			return gpN
	return null


# Find an edge by id. Returns null when missing.
# 按 id 查找边；找不到返回 null。
func gpGetEdge(gpId: String) -> GPPIDEdge:
	for gpE in gpEdges:
		if gpE.gpInstanceId == gpId:
			return gpE
	return null


# Remove a node by id. Returns whether it was actually removed.
# 按 id 删除节点，返回是否成功删除。
func gpRemoveNode(gpId: String) -> bool:
	for gpI in range(gpNodes.size()):
		if gpNodes[gpI].gpInstanceId == gpId:
			var gpN: GPPIDNode = gpNodes[gpI]
			gpNodes.remove_at(gpI)
			gpNodeRemoved.emit(gpN)
			gpGraphChanged.emit()
			return true
	return false


# Remove a node and every edge that touches it.
# 删除节点及其所有关联边。
func gpRemoveNodeWithEdges(gpId: String) -> void:
	gpRemoveNode(gpId)
	var gpKeep: Array[GPPIDEdge] = []
	for gpE in gpEdges:
		if gpE.gpFromRef.get("node_id", "") == gpId or gpE.gpToRef.get("node_id", "") == gpId:
			gpEdgeRemoved.emit(gpE)
		else:
			gpKeep.append(gpE)
	gpEdges = gpKeep
	gpGraphChanged.emit()


# Remove a WHOLE SET of nodes plus every edge touching ANY of them, emitting the same per-node /
# per-edge signals the single-node helper does.
# 一次性移除一**组**节点及触及其中任一节点的全部边，发出与单节点同名同序的信号。
#
# WHY A BATCH FORM / 为何需要批量形态：
# A cascade delete (规划 §6: deleting a host deletes its mounted subtree) must be ONE model
# operation. Looping the single-node helper would re-scan the whole edge list per node and, worse,
# could leave an edge between two removed nodes filtered twice but an edge to a removed node
# missed if the loop were ever reordered. Filtering once is both cheaper and impossible to get
# half-right. Whether a node is a host is NOT this layer's business: the caller passes the ids.
# 级联删除（规划 §6：删除宿主即删除其挂载子树）必须是一次模型操作。循环调用单节点辅助会对
# 每个节点重扫整张边表；更糟的是，一旦循环顺序被改动，两被删节点之间的边会被过滤两次，而指向
# 被删节点的边却可能被漏掉。一次性过滤既更快，也不可能只做对一半。
# 「谁是宿主」不是本层的职责：id 集合由调用方给出。
func gpRemoveNodesWithEdges(gpIds: Array[String]) -> void:
	if gpIds.is_empty():
		return
	var gpSet: Dictionary = {}
	for gpId in gpIds:
		gpSet[gpId] = true
	# Walk backwards so splicing does not shift the indices still to be visited.
	# 反向遍历，使删除元素不会移动尚未访问的下标。
	for gpI in range(gpNodes.size() - 1, -1, -1):
		if gpSet.has(gpNodes[gpI].gpInstanceId):
			var gpN: GPPIDNode = gpNodes[gpI]
			gpNodes.remove_at(gpI)
			gpNodeRemoved.emit(gpN)
	var gpKeep: Array[GPPIDEdge] = []
	for gpE in gpEdges:
		var gpFromId: String = str(gpE.gpFromRef.get("node_id", ""))
		var gpToId: String = str(gpE.gpToRef.get("node_id", ""))
		if gpSet.has(gpFromId) or gpSet.has(gpToId):
			gpEdgeRemoved.emit(gpE)
		else:
			gpKeep.append(gpE)
	gpEdges = gpKeep
	gpGraphChanged.emit()


# Insert an edge at a position (default: append). Used by undo to put a deleted edge back at
# the index it came from, which keeps the sheet's z-order stable across an undo.
# 在指定位置插入一条边（默认追加）。供撤销把已删边放回其原始下标，使图纸层序在撤销后保持稳定。
func gpInsertEdge(gpEdge: GPPIDEdge, gpAt: int = -1) -> void:
	if gpEdge == null:
		return
	gpEdges.insert(gpAt if gpAt >= 0 else gpEdges.size(), gpEdge)
	gpEdgeAdded.emit(gpEdge)
	gpGraphChanged.emit()


# Insert an annotation shape at a position (default: append). Used by undo to put a deleted
# shape back at the index it came from.
# 在指定位置插入一枚注释图形（默认追加）。供撤销把已删图形放回其原始下标。
func gpInsertShape(gpShape: GPShape, gpAt: int = -1) -> void:
	if gpShape == null:
		return
	gpShapes.insert(gpAt if gpAt >= 0 else gpShapes.size(), gpShape)
	gpGraphChanged.emit()


# Remove an annotation shape by object identity. Returns whether it was found.
# Going through the model (instead of splicing gpShapes() from a command) keeps "every
# topology mutation notifies from one place" true — see gpRemoveEdge().
# 按对象同一性移除一枚注释图形，返回是否找到。
# 经由模型（而非由命令直接拼接 gpShapes()）可保持「拓扑的每次改动都从一处通知」成立
# —— 参见 gpRemoveEdge()。
func gpRemoveShape(gpShape: GPShape) -> bool:
	var gpAt: int = gpShapes.find(gpShape)
	if gpAt < 0:
		return false
	gpShapes.remove_at(gpAt)
	gpGraphChanged.emit()
	return true


# Remove an edge by id. Returns whether it was actually removed.
# Added for M4: undoing a connect must be able to take the edge back out, and doing it
# here (rather than by splicing gpEdges from a command) keeps every mutation of the
# topology emitting from one place.
# 按 id 删除边，返回是否成功删除。
# 为 M4 新增：撤销一次连线需要把边取回；把这件事放在此处（而非由命令直接拼接 gpEdges）
# 可让拓扑的每次改动都从同一处发射信号。
func gpRemoveEdge(gpId: String) -> bool:
	for gpI in range(gpEdges.size()):
		if gpEdges[gpI].gpInstanceId == gpId:
			var gpE: GPPIDEdge = gpEdges[gpI]
			gpEdges.remove_at(gpI)
			gpEdgeRemoved.emit(gpE)
			gpGraphChanged.emit()
			return true
	return false


# Count how many placed instances reference the given symbol id on this sheet.
# 统计本图纸中引用该图元 id 的已放置实例数量。
func gpCountSymbolInstances(gpSymbolId: String) -> int:
	var gpCount: int = 0
	for gpN in gpNodes:
		if gpN.gpSymbolId == gpSymbolId:
			gpCount += 1
	return gpCount


# Remove every placed instance of the given symbol (and every edge that touches one),
# returning the number of instances removed. Called when a symbol is deleted from the
# library so canvas instances do not become orphans referencing a missing definition.
# 移除该图元的所有已放置实例（及其关联连线），返回移除的实例数。删除图元库图元时调用，
# 以免画布实例成为引用缺失定义的孤儿。
func gpRemoveSymbolInstances(gpSymbolId: String) -> int:
	var gpRemovedIds: Array[String] = []
	var gpKeepNodes: Array[GPPIDNode] = []
	for gpN in gpNodes:
		if gpN.gpSymbolId == gpSymbolId:
			gpRemovedIds.append(gpN.gpInstanceId)
			gpNodeRemoved.emit(gpN)
		else:
			gpKeepNodes.append(gpN)
	var gpCount: int = gpRemovedIds.size()
	if gpCount == 0:
		return 0
	gpNodes = gpKeepNodes
	# Drop every edge attached to a removed instance (mirrors gpRemoveNodeWithEdges()).
	# 删除每个被移除实例的连线（与 gpRemoveNodeWithEdges() 一致）。
	var gpKeepEdges: Array[GPPIDEdge] = []
	for gpE in gpEdges:
		var gpFrom: String = gpE.gpFromRef.get("node_id", "")
		var gpTo: String = gpE.gpToRef.get("node_id", "")
		if gpFrom in gpRemovedIds or gpTo in gpRemovedIds:
			gpEdgeRemoved.emit(gpE)
		else:
			gpKeepEdges.append(gpE)
	gpEdges = gpKeepEdges
	gpGraphChanged.emit()
	return gpCount


# Embed the user symbol packs (read from user://) into this graph before saving.
# 存盘前把用户图元包（取自 user://）嵌入本图。
# Pass GPSymbolLibrary.gpUserPacks() so the exported *.pid.json carries every custom
# symbol the user authored, making the file portable to any machine (data sovereignty).
# 传入 GPSymbolLibrary.gpUserPacks() 即可让导出的 *.pid.json 携带用户自建的全部自定义图元，
# 使文件可在任意机器间移植（数据主权）。
func gpEmbedUserPacks(gpPacks: Array[GPSymbolPack]) -> void:
	gpUserSymbolPacks = gpPacks.duplicate()


# ============================================================================
# Drop-on-edge restore registry (「图元压到连线」-> 删除时还原原始连线).
# 落点（图元压到连线上）恢复注册表。
#
# Why graph-level and not on the node / 为何位于图层级而非节点上:
# The records must survive the symbol being deleted (node gone) so the delete command can
# find them by id. They are also persisted so a save+reload still restores on delete.
# 记录必须在图元被删除（节点已不在）后仍存在，如此删除命令才能按 id 找到它们。一并持久化，
# 使存档重载后删除仍可还原。
#
# Schema / 记录形态:
# reroute: {"kind":"reroute", "edge_id":String, "orig_routing":Array[Vector2]}
# split: {"kind":"split", "orig":Dictionary (edge.gpToDict()), "orig_index":int}
# Every record carries a monotonic "_rid" so records of one symbol stay distinguishable.
# 每条记录带单调 "_rid"，使同一图元的多条记录彼此可区分。
var gpDropRestore: Dictionary = {}

# Monotonic record id source (NOT serialized; restored from the max loaded rid).
# 单调记录 id 源（不序列化；从载入的最大 rid 恢复）。
var _gpDropSeq: int = 0


# Append a restore record for [param gpSymNid]. Returns the assigned record id so the caller can
# remove exactly this record on undo. / 为 [param gpSymNid] 追加一条恢复记录，返回所分配 id 供撤销时精确移除。
func gpRecordDrop(gpSymNid: String, gpRecord: Dictionary) -> int:
	if not gpDropRestore.has(gpSymNid):
		gpDropRestore[gpSymNid] = []
	var gpList: Array = gpDropRestore[gpSymNid]
	_gpDropSeq += 1
	gpRecord["_rid"] = _gpDropSeq
	gpList.append(gpRecord)
	return _gpDropSeq


# Records for [param gpSymNid], or [] when none. / [param gpSymNid] 的全部记录，无则 []。
func gpDropRecords(gpSymNid: String) -> Array:
	if not gpDropRestore.has(gpSymNid):
		return []
	return gpDropRestore[gpSymNid].duplicate()


# Remove the record with [param gpRid] from [param gpSymNid]'s list. No-op when absent.
# 移除 [param gpSymNid] 列表中 id 为 [param gpRid] 的记录；不存在时为空操作。
func gpRemoveDrop(gpSymNid: String, gpRid: int) -> void:
	if not gpDropRestore.has(gpSymNid):
		return
	var gpList: Array = gpDropRestore[gpSymNid]
	for gpI in range(gpList.size() - 1, -1, -1):
		var gpR: Dictionary = gpList[gpI]
		if int(gpR.get("_rid", -1)) == gpRid:
			gpList.remove_at(gpI)
			break
	if gpList.is_empty():
		gpDropRestore.erase(gpSymNid)


# Remove every record for [param gpSymNid] (called after the delete command has replayed them).
# 移除 [param gpSymNid] 的全部记录（在删除命令重放后调用）。
func gpClearDrops(gpSymNid: String) -> void:
	gpDropRestore.erase(gpSymNid)


# Persist a record to the archive-friendly plain shape (Vector2 routing -> [x,y] pairs).
# 把记录转为可存档的普通形态（Vector2 走线 -> [x,y] 数组对）。
static func _gpDropRecordToDict(gpR: Dictionary) -> Dictionary:
	var gpOut: Dictionary = gpR.duplicate()
	if gpR.get("kind", "") == "reroute":
		var gpRouted: Array = []
		for gpP in gpR.get("orig_routing", []):
			if gpP is Vector2:
				gpRouted.append([gpP.x, gpP.y])
		gpOut["orig_routing"] = gpRouted
	return gpOut


# Inverse of _gpDropRecordToDict(). / _gpDropRecordToDict() 的逆操作。
static func _gpDropRecordFromDict(gpRD: Dictionary) -> Dictionary:
	var gpR: Dictionary = gpRD.duplicate()
	if gpRD.get("kind", "") == "reroute":
		var gpRouted: Array[Vector2] = []
		for gpP in gpRD.get("orig_routing", []):
			if gpP is Array and gpP.size() >= 2:
				gpRouted.append(Vector2(float(gpP[0]), float(gpP[1])))
		gpR["orig_routing"] = gpRouted
	return gpR


# Serialize the graph to a plain dictionary (object graph -> dict graph).
# 将图序列化为普通字典（对象图 → 字典图）。
func gpToDict() -> Dictionary:
	var gpNodesOut: Array = []
	for gpN in gpNodes:
		gpNodesOut.append(gpN.gpToDict())
	var gpEdgesOut: Array = []
	for gpE in gpEdges:
		gpEdgesOut.append(gpE.gpToDict())
	# Annotation shapes serialize verbatim so they round-trip with the sheet.
	# 注释图形原样序列化，随图纸一同往返。
	var gpShapesOut: Array = []
	for gpS in gpShapes:
		gpShapesOut.append(gpS.gpToDict())
	# Embed user packs so the saved file is self-contained.
	# 嵌入用户图元包，使存盘文件自包含。
	var gpPacksOut: Array = []
	for gpPack in gpUserSymbolPacks:
		gpPacksOut.append(gpPack.gpToDict())
	# the library fingerprint snapshot travels INSIDE meta, so a reader that knows
	# nothing about it still sees an ordinary meta dictionary.
	# 库指纹快照放在 meta **内部**，故不认识它的读取方看到的仍是一个普通的 meta 字典。
	var gpMetaOut: Dictionary = gpMeta.duplicate()
	if not gpSchemaFingerprints.is_empty():
		gpMetaOut["schema_fingerprints"] = gpSchemaFingerprints.duplicate()
	var gpOut: Dictionary = {
		"meta": gpMetaOut,
		"nodes": gpNodesOut,
		"edges": gpEdgesOut,
		"shapes": gpShapesOut,
		"user_symbol_packs": gpPacksOut,
	}
	# Written only once the project actually has rules, so a file untouched by M9 keeps
	# its v1 shape byte for byte. / 仅当工程确有规则时写出，使未经 M9 改动的文件
	# 逐字节保持 v1 形态。
	if gpTagRules != null:
		gpOut["tag_rules"] = gpTagRules.gpToDict()
	# Persist drop-restore records only when non-empty, so an untouched file keeps its byte shape.
	# 仅当非空时持久化落点恢复记录，使未触及本功能的文件保持原字节形态。
	if not gpDropRestore.is_empty():
		var gpDR: Array = []
		for gpSym in gpDropRestore.keys():
			var gpOutRecs: Array = []
			for gpRec in gpDropRestore[gpSym]:
				gpOutRecs.append(_gpDropRecordToDict(gpRec))
			gpDR.append({"sym": gpSym, "recs": gpOutRecs})
		gpOut["drop_restore"] = gpDR
	return gpOut


# Restore a graph from a plain dictionary (tolerant of old/new node/edge shapes).
# 从普通字典还原图（兼容新旧节点/边形状）。
static func gpFromDict(gpData: Dictionary) -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	if gpData.has("meta"):
		gpG.gpMeta = gpData["meta"].duplicate()
 # restore the library fingerprint snapshot (absent in every pre-M12 file).
 # 恢复库指纹快照。
		var gpFp: Variant = gpG.gpMeta.get("schema_fingerprints", null)
		if gpFp is Dictionary:
			gpG.gpSchemaFingerprints = (gpFp as Dictionary).duplicate()
	# v2: numbering rules. Absent in v1 files -> left null, and gpTagRulesOrCreate() hands
	# out the factory default on first use, so an old archive loads unchanged.
	# v2：编号规则。v1 文件里没有此键 -> 保持 null，由 gpTagRulesOrCreate() 在首次使用
	# 时给出出厂默认，故旧存档载入行为不变。
	if gpData.has("tag_rules"):
		gpG.gpTagRules = GPProjectTagRules.gpFromDict(gpData["tag_rules"] as Dictionary)
	if gpData.has("nodes"):
		for gpND in gpData["nodes"]:
			var gpN: GPPIDNode = GPPIDNode.new()
			gpN.gpFromDict(gpND)
			gpG.gpNodes.append(gpN)
	if gpData.has("edges"):
		for gpED in gpData["edges"]:
			var gpE: GPPIDEdge = GPPIDEdge.new()
			gpE.gpFromDict(gpED)
			gpG.gpEdges.append(gpE)
	if gpData.has("shapes"):
		for gpSD in gpData["shapes"]:
			var gpS: GPShape = GPShape.new()
			gpS.gpFromDict(gpSD)
			gpG.gpShapes.append(gpS)
	# Restore embedded user packs and reconcile them into the live library so the
	# custom symbols are available again after re-opening the file (self-contained).
	# 恢复内嵌的用户图元包，并调和进活动图元库，使重新打开文件后自定义图元再次可用（自包含）。
	if gpData.has("user_symbol_packs"):
		var gpPackDicts: Array = gpData["user_symbol_packs"]
		var gpRestoredDefs: Array[GPSymbolDef] = []
		for gpPD in gpPackDicts:
			var gpPack: GPSymbolPack = GPSymbolPack.new()
			gpPack.gpFromDict(gpPD)
			gpG.gpUserSymbolPacks.append(gpPack)
			for gpSym in gpPack.gpSymbols:
				gpRestoredDefs.append(gpSym)
		if gpRestoredDefs.size() > 0:
			GPSymbolLibrary.gpRegisterDefs(gpRestoredDefs)
	# Restore drop-restore records (absent in every pre-feature file). The sequence counter is
	# re-seeded from the max loaded rid so freshly recorded entries never collide with them.
	# 恢复落点恢复记录（本功能之前的文件均无此键）。单调 id 源从载入的最大 rid 重置，
	# 使新记录的 id 不会与之冲突。
	if gpData.has("drop_restore"):
		var gpMaxRid: int = 0
		for gpEntry in gpData["drop_restore"]:
			var gpSym: String = str(gpEntry.get("sym", ""))
			if gpSym == "":
				continue
			var gpRecs: Array = []
			for gpRD in gpEntry.get("recs", []):
				var gpR: Dictionary = _gpDropRecordFromDict(gpRD)
				gpMaxRid = maxi(gpMaxRid, int(gpR.get("_rid", 0)))
				gpRecs.append(gpR)
			if not gpRecs.is_empty():
				gpG.gpDropRestore[gpSym] = gpRecs
		gpG._gpDropSeq = gpMaxRid
	return gpG
