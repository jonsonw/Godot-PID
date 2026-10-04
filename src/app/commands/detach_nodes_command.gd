class_name GPDetachNodesCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Detach mounted children from their hosts, as ONE undoable step.
# 把挂载子件从其宿主上卸下，作为一步可撤销的编辑。
#
# The one thing that must not be forgotten / 绝不可忘记的一件事：
# A mounted child's world transform is DERIVED, never stored (see GPMountResolver). The moment
# the mount link is cut that derivation disappears, so the node would snap back to whatever stale
# gpPosition / gpRotationDeg / gpFlipped happen to sit on it — usually (0,0), i.e. the symbol would
# teleport to the sheet origin. Detaching therefore BAKES the derived world transform into the
# node's own fields first, so the symbol stays exactly where the user sees it. That bake is the
# reason this needs its own command rather than a generic "set fields" one.
# 挂载子件的世界变换是**推导**的、永不存储（见 GPMountResolver）。一旦切断挂载链接，该推导即
# 消失，节点会弹回到它身上碰巧残留的过期 gpPosition / gpRotationDeg / gpFlipped —— 通常是 (0,0)，
# 也就是图元瞬移到图纸原点。故卸载前先把推导出的世界变换**烘焙**进节点自身字段，
# 使图元精确停在用户看到的位置。正因如此，这里需要一条专用命令，而不是通用的「改字段」命令。
#
# Value-object rule / 值对象规则：
# The "after" state is computed ONCE, on the first execute, and redo replays it verbatim. Re-deriving
# on redo would read a parent chain that may itself have changed in between, so the redo result
# would depend on history rather than on the state the user committed.
# 「之后」状态只在**首次执行**时计算一次，重做逐字重放它。重做时重新推导会去读一条其间可能
# 已经变化的父链，使重做结果取决于历史而非用户提交时的那份状态。

# Ids to detach, captured at construction.
# 待卸载的 id，构造时捕获。
var _gpIds: Array[String] = []

# Definition lookup used to derive the world transform that gets baked (the context deliberately
# carries no symbol library — see GPCommandContext's "deliberately NOT injected" list). Callers
# pass it in, exactly as GPEditService.gpSnapEdgeEnds() does.
# 用于推导待烘焙世界变换的定义查找器（上下文刻意不携带图元库 —— 见 GPCommandContext 的
# 「刻意不注入」清单）。由调用方传入，与 GPEditService.gpSnapEdgeEnds() 的做法一致。
var _gpLookup: Callable = Callable()

# Per-id snapshots: the "before" (mounted) and "after" (baked, top-level) field values. Both are
# dictionaries so undo and redo are pure assignments with no re-derivation.
# 逐 id 快照：「之前」（已挂载）与「之后」（已烘焙、顶层）的字段值。两者都是字典，
# 故撤销与重做都是纯赋值，不做重新推导。
var _gpBefore: Array[Dictionary] = []
var _gpAfter: Array[Dictionary] = []


# Build the command from the ids to detach and the definition lookup needed to bake them.
# 由待卸载的 id 与烘焙所需的定义查找器构造命令。
func _init(gpInIds: Array[String], gpInLookup: Callable = Callable()) -> void:
	_gpIds = gpInIds.duplicate()
	_gpLookup = gpInLookup
	gpLabel = "卸载附件"


# Bake the derived transform into every MOUNTED id, then clear the mount link. Returns false when
# none of the ids was actually mounted, so a stale selection produces no undo step.
# 把推导变换烘焙进每一个**已挂载**的 id，随后清空挂载链接。若没有一个 id 处于挂载态则返回 false，
# 使过期选择集不产生撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	if _gpBefore.is_empty():
		_gpCapture(gpCtx)
	if _gpAfter.is_empty():
		return false
	for gpI in range(_gpIds.size()):
		_gpApply(gpCtx, _gpIds[gpI], _gpAfter[gpI])
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


# Restore the mount link and the pre-detach own-fields.
# 恢复挂载链接与卸载前自身的字段。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpBefore.is_empty():
		return
	for gpI in range(_gpIds.size()):
		_gpApply(gpCtx, _gpIds[gpI], _gpBefore[gpI])
	gpCtx.gpGraph.gpGraphChanged.emit()


# Replay the baked state verbatim (see the value-object rule in the header).
# 逐字重放已烘焙的状态（见头部的值对象规则）。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpAfter.is_empty():
		return
	for gpI in range(_gpIds.size()):
		_gpApply(gpCtx, _gpIds[gpI], _gpAfter[gpI])
	gpCtx.gpGraph.gpGraphChanged.emit()


# Read the current fields of every mounted id and compute the baked twin. Unmounted or missing ids
# are dropped from BOTH lists so the index correspondence stays exact.
# 读取每个已挂载 id 的当前字段并算出烘焙后的孪生值。未挂载或不存在的 id 从**两个**列表中
# 一并剔除，使下标对应关系保持精确。
func _gpCapture(gpCtx: GPCommandContext) -> void:
	var gpKeepIds: Array[String] = []
	_gpBefore.clear()
	_gpAfter.clear()
	for gpId in _gpIds:
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
		if gpN == null or not gpN.gpIsMounted():
			continue
		# A REQUIRED part cannot be detached either (规划 §16.2): peeling the suction nozzle off a
		# pump would leave a machine whose inlet has floated away, and the nozzle would then sit at
		# whatever stale own-coordinates it happens to carry. Same guard as delete, same reason.
		# **必需**部件同样不可卸载（规划 §16.2）：把吸入管口从泵上剥下来，会让机器的进口飘走，
		# 且该管口会停在自己碰巧残留的过期坐标上。与删除同一个护栏、同一个理由。
		if GPMountResolver.gpRequiredAnchorName(gpCtx.gpGraph, _gpLookup, gpN) != "":
			continue
		# The derived frame is read BEFORE anything is written, so the bake is not affected by the
		# order in which the ids are processed (two nodes can share a host).
		# 推导坐标系在任何写入之前读取，故烘焙结果不受 id 处理顺序影响（两个节点可能共用一个宿主）。
		var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpCtx.gpGraph, _gpLookup, gpN)
		gpKeepIds.append(gpId)
		_gpBefore.append({
			"parent_uid": gpN.gpParentUid,
			"mount_anchor": gpN.gpMountAnchor,
			"mount_offset": gpN.gpMountOffset,
			"mount_angle_deg": gpN.gpMountAngleDeg,
			"pos": gpN.gpPosition,
			"rot_deg": gpN.gpRotationDeg,
			"flipped": gpN.gpFlipped,
		})
		_gpAfter.append({
			"parent_uid": "",
			"mount_anchor": "",
			"mount_offset": Vector2.ZERO,
			"mount_angle_deg": 0.0,
			"pos": gpWT["origin"],
			"rot_deg": float(gpWT["rot_deg"]),
			"flipped": bool(gpWT["flipped"]),
		})
	_gpIds = gpKeepIds


# Write one snapshot onto one node. A missing node is skipped rather than failing, matching the
# "unknown ids are skipped" rule of GPMoveNodesCommand.
# 把一份快照写到一个节点上。节点缺失时跳过而非失败，与 GPMoveNodesCommand 的
# 「未知 id 跳过」规则一致。
func _gpApply(gpCtx: GPCommandContext, gpId: String, gpSnap: Dictionary) -> void:
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
	if gpN == null:
		return
	gpN.gpParentUid = str(gpSnap["parent_uid"])
	gpN.gpMountAnchor = str(gpSnap["mount_anchor"])
	gpN.gpMountOffset = gpSnap["mount_offset"]
	gpN.gpMountAngleDeg = float(gpSnap["mount_angle_deg"])
	gpN.gpPosition = gpSnap["pos"]
	gpN.gpRotationDeg = float(gpSnap["rot_deg"])
	gpN.gpFlipped = bool(gpSnap["flipped"])
