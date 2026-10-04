class_name GPDeleteNodesCommand
extends GPCommand
#
# Invertibility / 可逆性:
# Deletion is destructive only if you throw the objects away. This command snapshots
# the node objects AND the edge objects before removing them, so undo puts back the
# very same instances (same ids, same attributes, same routing) rather than
# reconstructed copies that would drift from the original.
# 删除之所以不可逆，只因为把对象丢了。本命令在移除前快照节点对象与边对象，
# 因此撤销放回的是同一批实例（同 id、同属性、同走线），而非会与原对象漂移的重建副本。

# Ids to delete. Captured at construction so the selection can change freely afterwards.
# 待删除的 id。构造时捕获，此后选择集可随意变化而不影响本命令。
var _gpIds: Array[String] = []

# Snapshot of the removed node objects, in graph order, for undo.
# 被删节点对象的快照（按图中顺序），供撤销使用。
var _gpNodes: Array[GPPIDNode] = []

# Snapshot of the edges that touched any deleted node, for undo.
# 与被删节点相连的边快照，供撤销使用。
var _gpEdges: Array[GPPIDEdge] = []

# Definition lookup used to resolve whether a node sits on a REQUIRED anchor. Injected because the
# context deliberately carries no symbol library (see GPCommandContext's "deliberately NOT injected"
# list); an invalid lookup simply disables the pin, which is the documented degradation direction.
# 用于判断节点是否坐在**必需**锚点上的定义查找器。需注入，因为上下文刻意不携带图元库
# （见 GPCommandContext 的「刻意不注入」清单）；无效查找器只是关闭这枚钉子，
# 这正是文档化的降级方向。
var _gpLookup: Callable = Callable()


# Build the command from the node ids to remove.
# 由待删除的节点 id 构造命令。
func _init(gpInIds: Array[String], gpInLookup: Callable = Callable()) -> void:
	_gpIds = gpInIds.duplicate()
	_gpLookup = gpInLookup
	gpLabel = "删除节点"


# Whether [param gpN] is a REQUIRED part that this command must refuse to delete. A required part
# whose HOST is itself among the requested ids is exempt: the part then goes away as part of the
# host's subtree, which is the intended behaviour, not a violation (规划 §16.2).
# [param gpN] 是否是本命令必须拒绝删除的**必需**部件。若其**宿主**也在本次请求的 id 之列则豁免：
# 此时该部件随宿主的子树一并消失，这正是预期行为而非违规（规划 §16.2）。
func _gpPinned(gpCtx: GPCommandContext, gpN: GPPIDNode) -> bool:
	if GPMountResolver.gpRequiredAnchorName(gpCtx.gpGraph, _gpLookup, gpN) == "":
		return false
	return not (gpN.gpParentUid in _gpIds)


# Snapshot, then remove each node with its edges. Returns false when none of the ids
# resolves to a real node, so an empty or stale selection produces no undo step.
# 先快照，再逐个删除节点及其边。若所有 id 都找不到真实节点则返回 false，
# 使空的或过期的选择集不产生撤销步。
#
# CASCADE / 级联：
# Deleting a host deletes its mounted subtree (规划 §6). Without it a nozzle would outlive its
# vessel and become precisely the orphan attachment this whole feature exists to remove — and,
# worse, it would silently degrade to sitting at its stale own coordinates (mount ladder 2).
# The expansion is DOWNWARD only: deleting a selected child never touches its host.
# 删除宿主即删除其挂载子树（规划 §6）。否则管口会比设备活得久，成为本功能要消灭的孤儿附件；
# 更糟的是，它会静默降级为停在自身过期坐标上（挂载阶梯 2）。扩展只朝**下**：
# 删除被选中的子件绝不会牵动其宿主。
#
# PINNED PARTS / 钉死的部件：
# An A-class part (a pump's suction nozzle) has a count and a position fixed by the machine, so it
# is skipped rather than deleted (see _gpPinned). The check runs against the ORIGINAL request list,
# which is why that list is no longer overwritten with the expanded set — a redo would otherwise
# see the part's host inside the (expanded) list and wrongly consider it exempt.
# A 类部件（泵的吸入管口）的数量与位置由机器决定，故被跳过而非删除（见 _gpPinned）。该检查针对
# **原始**请求列表，这正是本列表不再被「扩展后的集合」覆写的原因 —— 否则重做时会看到该部件的宿主
# 出现在（扩展后的）列表中，从而错误地认为它享豁免。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	_gpNodes.clear()
	_gpEdges.clear()
	# Each requested id plus its whole mounted subtree, in breadth-first order. Nodes reached
	# through another id's subtree are NOT pin-checked: they leave as part of THEIR host's cascade,
	# which is exactly what the exemption above describes.
	# 每个被请求的 id 及其完整挂载子树，广度优先。经由别的 id 的子树抵达的节点**不**做钉子检查：
	# 它们随**自身宿主**的级联一同离开，这正是上面那条豁免所描述的情形。
	var gpAll: Array[String] = []
	for gpId in _gpIds:
		var gpRoot: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
		if gpRoot != null and _gpPinned(gpCtx, gpRoot):
			continue
		for gpUid in GPMountResolver.gpSubtree(gpCtx.gpGraph, gpId):
			if not (gpUid in gpAll):
				gpAll.append(gpUid)
	if gpAll.is_empty():
		return false
	for gpId in gpAll:
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
		if gpAll.has(gpF) or gpAll.has(gpT):
			if not _gpEdges.has(gpE):
				_gpEdges.append(gpE)
	# One model operation for the whole set: filtering the edge list once is what makes "an edge
	# whose BOTH ends are in the set" impossible to handle inconsistently (see
	# GPPIDGraph.gpRemoveNodesWithEdges()).
	# 整组作为**一次**模型操作：一次性过滤边表，正是「两端都在集合内的边」不可能被处理不一致的原因
	# （见 GPPIDGraph.gpRemoveNodesWithEdges()）。
	gpCtx.gpGraph.gpRemoveNodesWithEdges(gpAll)
	if gpCtx.gpTags != null:
		for gpN in _gpNodes:
			gpCtx.gpTags.gpRelease(gpN.gpInstanceId)
	return true


# Put the nodes and their edges back, preserving ids and object identity.
# 放回节点与关联边，保持 id 与对象同一性。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpN in _gpNodes:
		gpCtx.gpGraph.gpAddNode(gpN)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRegister(gpN.gpInstanceId, gpN.gpTag)
	for gpE in _gpEdges:
		gpCtx.gpGraph.gpAddEdge(gpE)


# Re-snapshot and delete again. The graph is intact at this point, so re-running
# gpExecute() collects the same objects.
# 重新快照并再次删除。此刻图是完整的，因此重跑 gpExecute() 会收集到相同对象。
func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
