class_name GPDeleteNodesCommand
extends GPCommand
# Delete one or more nodes together with every edge touching them (M4).
# 删除一个或多个节点及其所有关联边（M4）。
#
# Invertibility / 可逆性:
#   Deletion is destructive only if you throw the objects away. This command snapshots
#   the node objects AND the edge objects before removing them, so undo puts back the
#   very same instances (same ids, same attributes, same routing) rather than
#   reconstructed copies that would drift from the original.
#   删除之所以不可逆，只因为把对象丢了。本命令在移除前快照节点对象与边对象，
#   因此撤销放回的是同一批实例（同 id、同属性、同走线），而非会与原对象漂移的重建副本。

# Ids to delete. Captured at construction so the selection can change freely afterwards.
# 待删除的 id。构造时捕获，此后选择集可随意变化而不影响本命令。
var _gpIds: Array[String] = []

# Snapshot of the removed node objects, in graph order, for undo.
# 被删节点对象的快照（按图中顺序），供撤销使用。
var _gpNodes: Array[GPPIDNode] = []

# Snapshot of the edges that touched any deleted node, for undo.
# 与被删节点相连的边快照，供撤销使用。
var _gpEdges: Array[GPPIDEdge] = []


# Build the command from the node ids to remove.
# 由待删除的节点 id 构造命令。
func _init(gpInIds: Array[String]) -> void:
	_gpIds = gpInIds.duplicate()
	gpLabel = "删除节点"


# Snapshot, then remove each node with its edges. Returns false when none of the ids
# resolves to a real node, so an empty or stale selection produces no undo step.
# 先快照，再逐个删除节点及其边。若所有 id 都找不到真实节点则返回 false，
# 使空的或过期的选择集不产生撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	_gpNodes.clear()
	_gpEdges.clear()
	for gpId in _gpIds:
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
		if gpN != null and not _gpNodes.has(gpN):
			_gpNodes.append(gpN)
	if _gpNodes.is_empty():
		return false
	# Collect the touching edges BEFORE deleting, while the graph is still intact.
	# 在删除之前、图仍完整时收集关联边。
	for gpE in gpCtx.gpGraph.gpEdges:
		var gpF: String = str(gpE.gpFromRef.get("node_id", ""))
		var gpT: String = str(gpE.gpToRef.get("node_id", ""))
		if _gpIds.has(gpF) or _gpIds.has(gpT):
			if not _gpEdges.has(gpE):
				_gpEdges.append(gpE)
	for gpId in _gpIds:
		gpCtx.gpGraph.gpRemoveNodeWithEdges(gpId)
	return true


# Put the nodes and their edges back, preserving ids and object identity.
# 放回节点与关联边，保持 id 与对象同一性。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpN in _gpNodes:
		gpCtx.gpGraph.gpAddNode(gpN)
	for gpE in _gpEdges:
		gpCtx.gpGraph.gpAddEdge(gpE)


# Re-snapshot and delete again. The graph is intact at this point, so re-running
# gpExecute collects the same objects.
# 重新快照并再次删除。此刻图是完整的，因此重跑 gpExecute 会收集到相同对象。
func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
