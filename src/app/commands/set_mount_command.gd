class_name GPSetMountCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Change WHERE an existing child is mounted — its host, anchor, local nudge and fine-tune angle —
# as ONE undoable step. This is the commit point for both drag paths of 规划 §15.
# 改变一个已存在子件**挂在哪里** —— 宿主、锚点、本地微调与微调角 —— 作为一步可撤销的编辑。
# 这是规划 §15 两条拖拽路径的共同提交点。
#
# Why "record both sides" instead of "delta" / 为何记录两侧而非位移量：
# A node's mounted transform is derived from the parent chain, so there is no meaningful delta to
# subtract — the fields are a (parent, anchor, offset, angle) tuple, and undo means putting the
# whole tuple back. Storing before/after tuples also makes redo independent of the current graph
# state, which is what stops a redo from drifting when the host was moved in between.
# 节点的挂载变换由父链推导，故不存在可相减的有意义位移量 —— 这些字段是一个
# (宿主, 锚点, 偏移, 角) 元组，撤销即把整个元组放回去。存前后两个元组也使重做不依赖当前图状态，
# 这正是「宿主其间被移动过」时重做不会漂移的原因。
#
# Redo rule / 重做规则：
# Replays the recorded "after" tuple verbatim; it never re-derives, so no id is minted and no
# derived value is recomputed (see GPDetachNodesCommand for the same reasoning).
# 逐字重放记录的「之后」元组；绝不重新推导，故不会铸造新 id、也不会重算推导值
# （与 GPDetachNodesCommand 同一理由）。

# Per-node target mount tuples, parallel to _gpIds.
# 逐节点的目标挂载元组，与 _gpIds 平行。
var _gpIds: Array[String] = []
var _gpTargets: Array[Dictionary] = []

# Snapshots of the previous tuples, captured on the first execute.
# 先前元组的快照，首次执行时捕获。
var _gpBefore: Array[Dictionary] = []


# Build the command from parallel id / target lists. A target uses the same keys as GPPIDNode's
# mount fields, so callers can build one from a gpMountCandidate() result plus an offset.
# 由平行的 id / 目标列表构造命令。目标使用与 GPPIDNode 挂载字段相同的键，
# 故调用方可直接由 gpMountCandidate() 的结果加上偏移构造一个。
func _init(gpInIds: Array[String], gpInTargets: Array[Dictionary]) -> void:
	_gpIds = gpInIds.duplicate()
	_gpTargets = gpInTargets.duplicate()
	gpLabel = "改挂载"


# Apply every target tuple, snapshotting the previous one first. Returns false when nothing
# actually changed, so a drag that ends on the anchor it started from records no undo step.
# 应用每个目标元组，并先快照先前元组。若实际没有任何变化则返回 false，
# 使「拖了一圈又落回原锚点」不产生撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	_gpBefore.clear()
	var gpChanged: bool = false
	for gpI in range(_gpIds.size()):
		var gpId: String = _gpIds[gpI]
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
		if gpN == null or gpI >= _gpTargets.size():
			continue
		var gpT: Dictionary = _gpTargets[gpI]
		var gpPrev: Dictionary = {
			"parent_uid": gpN.gpParentUid,
			"mount_anchor": gpN.gpMountAnchor,
			"mount_offset": gpN.gpMountOffset,
			"mount_angle_deg": gpN.gpMountAngleDeg,
		}
		_gpBefore.append(gpPrev)
		if _gpDiffers(gpPrev, gpT):
			gpChanged = true
		_gpWrite(gpN, gpT)
	if not gpChanged:
		return false
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


# Put every recorded previous tuple back. Ids are matched by position, so the command must be
# undone exactly as many times as it was executed — which the stack guarantees.
# 把记录的每个先前元组放回去。id 按位置对应，故本命令被撤销的次数必须与执行次数一致 ——
# 这是由命令栈保证的。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpI in range(_gpBefore.size()):
		if gpI >= _gpIds.size():
			break
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpIds[gpI])
		if gpN != null:
			_gpWrite(gpN, _gpBefore[gpI])
	gpCtx.gpGraph.gpGraphChanged.emit()


# Replay the target tuples verbatim. gpExecute() would refuse when the values are already correct
# (its "nothing changed" guard), which is exactly what happens on a redo after an undo of a
# same-anchor drag — so redo must not go through it.
# 逐字重放目标元组。gpExecute() 在取值已正确时会拒绝执行（其「无变化」护栏），
# 而「同锚点拖拽」撤销后再重做恰是这种情形 —— 故重做不可走它。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpI in range(_gpIds.size()):
		if gpI >= _gpTargets.size():
			break
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpIds[gpI])
		if gpN != null:
			_gpWrite(gpN, _gpTargets[gpI])
	gpCtx.gpGraph.gpGraphChanged.emit()


# Whether the target tuple differs from the current one in any field. A missing key means "leave
# this field alone", so a caller may move a node to another anchor without naming an offset.
# 目标元组是否在任一字段上与当前不同。缺键表示「该字段不动」，
# 故调用方可以把节点移到另一锚点而不必给出偏移。
func _gpDiffers(gpPrev: Dictionary, gpTarget: Dictionary) -> bool:
	if gpTarget.has("parent_uid") and str(gpTarget["parent_uid"]) != str(gpPrev["parent_uid"]):
		return true
	if gpTarget.has("mount_anchor") and str(gpTarget["mount_anchor"]) != str(gpPrev["mount_anchor"]):
		return true
	if gpTarget.has("mount_offset") and gpTarget["mount_offset"] != gpPrev["mount_offset"]:
		return true
	if gpTarget.has("mount_angle_deg") \
			and not is_equal_approx(float(gpTarget["mount_angle_deg"]), float(gpPrev["mount_angle_deg"])):
		return true
	return false


# Write only the keys the target actually carries (see _gpDiffers()).
# 只写入目标确实携带的键（见 _gpDiffers()）。
func _gpWrite(gpNode: GPPIDNode, gpTarget: Dictionary) -> void:
	if gpTarget.has("parent_uid"):
		gpNode.gpParentUid = str(gpTarget["parent_uid"])
	if gpTarget.has("mount_anchor"):
		gpNode.gpMountAnchor = str(gpTarget["mount_anchor"])
	if gpTarget.has("mount_offset"):
		gpNode.gpMountOffset = gpTarget["mount_offset"]
	if gpTarget.has("mount_angle_deg"):
		gpNode.gpMountAngleDeg = float(gpTarget["mount_angle_deg"])
