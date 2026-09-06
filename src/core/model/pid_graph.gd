class_name GPPIDGraph
extends RefCounted

# P&ID topology data core: a strongly-typed node-edge graph.
# P&ID 拓扑数据内核：强类型的节点-边图。
# The 2D canvas, 3D linkage and list export all read this resource.
# 2D 画布、3D 联动、清单导出都读取这个 Resource。
# See 从零落地架构_分步实施.md Step 1.2 (object graph refactor).
# 见「从零落地架构_分步实施.md」Step 1.2（对象图重构）。

# Project metadata stored inside the graph resource.
# 图资源内部保存的工程元数据。
var gpMeta: Dictionary = {
	"version": "1.0",
	"title": "",
	"sheets": 1,
}

# All symbol instances (nodes) in this sheet — strongly typed.
# 本图纸内所有图元实例（节点）——强类型。
# Not @export: Godot only exports built-ins / Resources / Nodes / enums, and GPPIDNode
# is a custom RefCounted. Serialization is manual via gpToDict() (JSON), so no export needed.
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
	gpN.gpAttrValues = gpAttrs.duplicate()
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
	# Drop every edge attached to a removed instance (mirrors gpRemoveNodeWithEdges).
	# 删除每个被移除实例的连线（与 gpRemoveNodeWithEdges 一致）。
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
	return {
		"meta": gpMeta.duplicate(),
		"nodes": gpNodesOut,
		"edges": gpEdgesOut,
		"shapes": gpShapesOut,
		"user_symbol_packs": gpPacksOut,
	}


# Restore a graph from a plain dictionary (tolerant of old/new node/edge shapes).
# 从普通字典还原图（兼容新旧节点/边形状）。
static func gpFromDict(gpData: Dictionary) -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	if gpData.has("meta"):
		gpG.gpMeta = gpData["meta"].duplicate()
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
	return gpG
