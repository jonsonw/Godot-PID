class_name GPMountDragOps
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# The drag kernel shared by BOTH attach interactions of 规划 §15 — "drag a part from the library"
# (mode 1) and "right-click add, then drag it into place" (mode 2). Dependency-free and
# Control-free so both are drivable headlessly.
# 规划 §15 两种附件交互**共用**的拖拽内核 —— 「从图库拖放部件」（模式一）与「右键添加后拖入
# 位置」（模式二）。无 UI 依赖、无 Control 依赖，故两者都能在 headless 下驱动。
#
# Split of duties / 职责划分：
#   * this class COMPUTES a target mount tuple and APPLIES it live, so the user sees the part snap
#     and turn while dragging;
#   * the COMMIT is not done here — the caller wraps the final tuple in GPSetMountCommand, so the
#     whole drag is ONE undo step, exactly like every other drag in this codebase.
#   * 本类**计算**目标挂载元组并**实时应用**，使用户在拖拽时看到部件吸附并转向；
#   * **提交**不在此处 —— 调用方把最终元组包进 GPSetMountCommand，使整次拖拽成为**一步**撤销，
#     与本仓库其它所有拖拽一致。
#
# Two regimes, decided per motion event / 两种状态，逐次移动事件判定：
#   1. A compatible anchor is within snapping distance -> the part JUMPS to it and re-orients from
#      the anchor's outward normal (gpAnchorDirToRotation). The local nudge is cleared, so the part
#      sits exactly on the anchor rather than drifting on top of a previous offset.
#   2. No anchor in range -> the part stays on its current host and follows the cursor WITHIN that
#      host's own frame (gpMountOffset). It therefore keeps inheriting the host's move / rotate /
#      flip, which is the whole point of a part being a part.
#   1. 兼容锚点在吸附距离内 -> 部件**跳**到该锚点，并按锚点向外法线重新定向
#      （gpAnchorDirToRotation）。本地微调被清零，使部件精确坐在锚点上，而不是叠在旧偏移上漂移。
#   2. 范围内没有锚点 -> 部件留在当前宿主上，在**宿主自身坐标系内**跟随光标（gpMountOffset）。
#      于是它继续继承宿主的移动 / 旋转 / 翻转 —— 这正是「部件之所以是部件」的关键。

# World position the cursor had when the drag began. Kept so gpCancel() is not needed to re-derive
# anything: the before-tuple is snapshotted whole.
# 拖拽开始时光标的世界坐标。保留它是为了 gpCancel() 无需重新推导任何东西 —— 之前元组整体快照。
var _gpGraph: GPPIDGraph = null
var _gpLookup: Callable = Callable()
var _gpNodeId: String = ""
var _gpBefore: Dictionary = {}
var _gpDragging: bool = false


# Whether the drag is live (so an ESC chain or a release handler knows to route here).
# 拖拽是否在进行中（供 ESC 链或释放处理器判断是否该路由到这里）。
func gpIsDragging() -> bool:
	return _gpDragging


# Id of the part being dragged ("" when idle).
# 正在拖拽的部件 id（空闲时 ""）。
func gpNodeId() -> String:
	return _gpNodeId


# The mount tuple as it was when the drag began — the value gpUndo of the commit command restores.
# 拖拽开始时的挂载元组 —— 即提交命令撤销时恢复的取值。
func gpBefore() -> Dictionary:
	return _gpBefore.duplicate()


# Start dragging a MOUNTED node. Returns false (and stays idle) for an unmounted node: a top-level
# symbol is moved by the ordinary position drag, and mixing the two would make a part's stored
# position silently authoritative again.
# 开始拖拽一个**已挂载**节点。未挂载节点返回 false 并保持空闲：顶层图元由普通的坐标拖拽移动，
# 混用两者会让部件的存储坐标再次静默地变成权威。
func gpBegin(gpGraph: GPPIDGraph, gpLookup: Callable, gpNodeIdIn: String) -> bool:
	_gpDragging = false
	_gpGraph = gpGraph
	_gpLookup = gpLookup
	_gpNodeId = gpNodeIdIn
	_gpBefore = {}
	if gpGraph == null:
		return false
	var gpN: GPPIDNode = gpGraph.gpGetNode(gpNodeIdIn)
	if gpN == null or not gpN.gpIsMounted():
		_gpNodeId = ""
		return false
	_gpBefore = gpTupleOf(gpN)
	_gpDragging = true
	return true


# Compute the mount tuple the part should have while the cursor sits at [param gpWorld].
# 当光标位于 [param gpWorld] 时，部件应具有的挂载元组。
# Returns {} when idle or when the node vanished mid-drag.
# 空闲、或拖拽途中节点消失时返回 {}。
func gpTargetFor(gpWorld: Vector2, gpZoom: float) -> Dictionary:
	if not _gpDragging or _gpGraph == null:
		return {}
	var gpN: GPPIDNode = _gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return {}
	var gpChildDef: GPSymbolDef = GPMountResolver.gpDefFor(_gpLookup, gpN.gpSymbolId)
	var gpKind: String = "" if gpChildDef == null else gpChildDef.gpMountKind
	# Regime 1: a free compatible anchor under the cursor wins outright.
	# 状态 1：光标下有空闲兼容锚点时直接取胜。
	var gpCand: Dictionary = GPMountResolver.gpMountCandidate(_gpGraph, _gpLookup, gpWorld, gpZoom,
		gpKind)
	if bool(gpCand["hit"]):
		return {
			"parent_uid": str(gpCand["parent_uid"]),
			"mount_anchor": str(gpCand["anchor"]),
			"mount_offset": Vector2.ZERO,
			# Snapping onto a real anchor resets any side override: the anchor's own outward
			# normal is the truth again.
			# 吸附到真实锚点即清除一切侧向覆盖：锚点自身的外法线重新成为权威。
			"mount_angle_deg": 0.0,
		}
	# Regime 2: stay on the current host and follow the cursor inside the host's own frame.
	# 状态 2：留在当前宿主上，并在宿主自身坐标系内跟随光标。
	if gpN.gpParentUid == "":
		return {}
	var gpHost: GPPIDNode = _gpGraph.gpGetNode(gpN.gpParentUid)
	if gpHost == null:
		return {}
	var gpHostDef: GPSymbolDef = GPMountResolver.gpDefFor(_gpLookup, gpHost.gpSymbolId)
	if gpHostDef == null:
		return {}
	var gpAnchor: GPAttachPoint = gpHostDef.gpAttachPointByName(gpN.gpMountAnchor)
	var gpAnchorLocal: Vector2 = GPMountResolver.gpAnchorLocal(gpHostDef, gpAnchor)
	var gpHostWT: Dictionary = GPMountResolver.gpWorldTransform(_gpGraph, _gpLookup, gpHost)
	var gpLocal: Vector2 = gpUnorientLocal(
		gpWorld - (gpHostWT["origin"] as Vector2),
		bool(gpHostWT["flipped"]),
		float(gpHostWT["rot_deg"]))
	# While the part glides over the host's body it also TURNS to face the side the cursor is on:
	# top of the host -> up, left -> left, right -> right, bottom -> down. The offset is untouched
	# (it lives in the HOST frame and the child's rotation never moves its centre), so the part
	# pivots in place — the reported "drag a nozzle around the host and it must re-orient".
	# 部件在宿主体上滑行的同时**转向**光标所在的一侧：宿主顶部朝上、左朝左、右朝右、下朝下。
	# 偏移不动（它处于宿主坐标系，且子件自身的旋转从不移动其中心），故部件原地转身 ——
	# 即用户报告的「拖动管嘴到宿主不同位置应自动调整朝向」。
	var gpAngle: float = gpN.gpMountAngleDeg
	var gpSideDir: Vector2 = GPMountResolver.gpSideOutwardDir(_gpGraph, _gpLookup, gpHost, gpWorld)
	if gpSideDir != Vector2.ZERO:
		var gpAnchorDir: Vector2 = Vector2.ZERO
		if gpAnchor != null:
			gpAnchorDir = GPMountResolver.gpOrientDir(gpAnchor.gpDir, bool(gpHostWT["flipped"]),
				float(gpHostWT["rot_deg"]))
		var gpBaseRot: float = 0.0
		if gpChildDef != null:
			gpBaseRot = gpChildDef.gpBaseMountRot
		gpAngle = wrapf(rad_to_deg(gpSideDir.angle())
			- GPMountResolver.gpAnchorDirToRotation(gpAnchorDir, gpBaseRot), -180.0, 180.0)
	return {
		"parent_uid": gpN.gpParentUid,
		"mount_anchor": gpN.gpMountAnchor,
		"mount_offset": gpLocal - gpAnchorLocal,
		"mount_angle_deg": gpAngle,
	}


# Write a computed tuple onto the node so the user sees the part follow the cursor. Only the three
# mount fields are touched: the part's own position / rotation stay derived, never stored.
# 把算出的元组写到节点上，使用户看到部件跟随光标。只改三个挂载字段：部件自身的坐标 / 旋转仍是
# 推导的，绝不存储。
func gpApply(gpTarget: Dictionary) -> void:
	if gpTarget.is_empty() or _gpGraph == null:
		return
	var gpN: GPPIDNode = _gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return
	gpN.gpParentUid = str(gpTarget["parent_uid"])
	gpN.gpMountAnchor = str(gpTarget["mount_anchor"])
	gpN.gpMountOffset = gpTarget["mount_offset"]
	if gpTarget.has("mount_angle_deg"):
		gpN.gpMountAngleDeg = float(gpTarget["mount_angle_deg"])


# Put the node back exactly as it was when the drag began. Safe to call when idle.
# 把节点精确还原为拖拽开始时的样子。空闲时调用亦安全。
#
# TWO callers, both mandatory / 两个调用方，都必不可少：
#   1. the ESC path — abandon the drag;
#   2. the COMMIT path — restore first, THEN hand the target tuple to GPSetMountCommand, so the
#      command sees a real difference and records a proper undo step (see gpSetMount()'s ⚠️ note).
#   1. ESC 路径 —— 放弃本次拖拽；
#   2. **提交**路径 —— 先恢复，再把目标元组交给 GPSetMountCommand，使命令看到真实差异并记下
#      一步正常的撤销（见 gpSetMount() 的 ⚠️ 说明）。
func gpRestore() -> void:
	if _gpBefore.is_empty() or _gpGraph == null:
		return
	var gpN: GPPIDNode = _gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return
	gpN.gpParentUid = str(_gpBefore["parent_uid"])
	gpN.gpMountAnchor = str(_gpBefore["mount_anchor"])
	gpN.gpMountOffset = _gpBefore["mount_offset"]
	gpN.gpMountAngleDeg = float(_gpBefore.get("mount_angle_deg", 0.0))


# End the drag. The caller commits gpBefore()..current as one GPSetMountCommand.
# 结束拖拽。调用方把 gpBefore()..当前 提交为一步 GPSetMountCommand。
func gpEnd() -> void:
	_gpDragging = false
	_gpGraph = null
	_gpLookup = Callable()
	_gpNodeId = ""


# Inverse of GPMountResolver.gpOrientLocal(): take a WORLD delta back into the frame it was oriented
# from. The forward map is "mirror, then rotate", so the inverse is "un-rotate, then un-mirror" —
# both steps are involutions and the rotation is the negated angle.
# GPMountResolver.gpOrientLocal() 的逆：把世界位移量还原回它被变换前所在的坐标系。
# 正向映射是「先镜像再旋转」，故逆向是「先反旋转再反镜像」—— 两步都是对合，且旋转取负角。
static func gpUnorientLocal(gpWorldDelta: Vector2, gpFlipped: bool, gpRotDeg: float) -> Vector2:
	var gpL: Vector2 = gpWorldDelta
	if not is_zero_approx(gpRotDeg):
		gpL = gpL.rotated(deg_to_rad(-gpRotDeg))
	if gpFlipped:
		gpL.x = -gpL.x
	return gpL


# The four mount fields of a node, as the tuple shape this class and GPSetMountCommand share.
# 节点的四个挂载字段，即本类与 GPSetMountCommand 共用的元组形态。
#
# PUBLIC and STATIC on purpose, because the DROP path must build its "after" tuple from the very
# same shape the drag began from: a hand-written three-field dictionary there silently dropped
# gpMountAngleDeg, so a part turned correctly while dragging and snapped back upright on release.
# One shape, one author — the model field list is never transcribed twice.
# 刻意设为**公开静态**，因为落位路径必须用与拖拽起点**完全相同的形态**构造其「之后」元组：
# 那里曾手写了一份三字段字典，静默丢掉 gpMountAngleDeg —— 于是部件拖拽时转向正确、释放后
# 又弹回朝上。一种形态、一个作者 —— 模型字段清单绝不被抄写两遍。
static func gpTupleOf(gpNode: GPPIDNode) -> Dictionary:
	return {
		"parent_uid": gpNode.gpParentUid,
		"mount_anchor": gpNode.gpMountAnchor,
		"mount_offset": gpNode.gpMountOffset,
		"mount_angle_deg": gpNode.gpMountAngleDeg,
	}


# The tuple the COMMIT should hand to GPSetMountCommand: the node's CURRENT mount state, read
# through gpTupleOf() so no field — the facing angle least of all — can be left behind.
# 提交应交给 GPSetMountCommand 的元组：节点的**当前**挂载状态，经 gpTupleOf() 读取，
# 使任何字段（尤其是朝向角）都不可能被漏掉。
func gpCommitTuple() -> Dictionary:
	if _gpGraph == null or _gpNodeId == "":
		return {}
	var gpN: GPPIDNode = _gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return {}
	return gpTupleOf(gpN)


# Whether the node's CURRENT mount tuple differs from the one the drag began with. This — and not a
# private helper in the tool — is the verdict the drop asks before committing, so a drag that only
# TURNED the part is not mistaken for a no-op and silently dropped.
# 节点**当前**挂载元组是否不同于拖拽起点的那个。落位在提交前问的是**这个**（而非工具里的私有
# 辅助函数），故「只把部件转了个向」的拖拽不会被误判为无变化而遭静默丢弃。
func gpChanged() -> bool:
	if _gpBefore.is_empty():
		return false
	return gpTuplesDiffer(_gpBefore, gpCommitTuple())


# Whether two mount tuples differ in ANY field — the facing angle included. Compared one field at
# a time rather than through Dictionary equality, and kept next to gpTupleOf() so adding a mount
# field to the model cannot leave this comparison behind.
# 两个挂载元组是否在**任一**字段上不同 —— 含朝向角。逐字段比较而非依赖 Dictionary 的相等语义，
# 且与 gpTupleOf() 相邻存放，故给模型新增挂载字段时不可能漏掉这里的比较。
static func gpTuplesDiffer(gpA: Dictionary, gpB: Dictionary) -> bool:
	if gpA.is_empty() or gpB.is_empty():
		return false
	if str(gpA.get("parent_uid", "")) != str(gpB.get("parent_uid", "")):
		return true
	if str(gpA.get("mount_anchor", "")) != str(gpB.get("mount_anchor", "")):
		return true
	if gpA.get("mount_offset", Vector2.ZERO) != gpB.get("mount_offset", Vector2.ZERO):
		return true
	return not is_equal_approx(float(gpA.get("mount_angle_deg", 0.0)),
		float(gpB.get("mount_angle_deg", 0.0)))
