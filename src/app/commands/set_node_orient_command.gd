class_name GPSetNodeOrientCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Set the ORIENTATION (rotation degrees + mirror flag) of several nodes as one undoable step.
# 把多个节点的**朝向**（旋转角度 + 镜像标志）作为一步可撤销的编辑写入。
#
# Why separate from GPSetNodePositionsCommand / 为何与 GPSetNodePositionsCommand 分开：
# Position and orientation are different edits with different labels and different failure modes.
# A rotate that also moved things would make "undo the rotation" impossible to reason about, and
# a mounted child derives its POSITION from its host but OWNS its rotation/flip — so the two
# fields do not even live in the same authority.
# 位置与朝向是两种编辑：标签不同、失效模式也不同。若旋转顺手挪了位置，「撤销这次旋转」就说不清；
# 而挂载子件的**位置**由宿主推导、**旋转/翻转**归它自己 —— 两个字段本就不属同一权威。
#
# Targets, not deltas / 写目标，不写增量：
# The command receives the RESULT values. The "rotate by 90" arithmetic lives in GPEditService
# (one place), so undo/redo can replay the recorded target verbatim and never re-derive — the
# same value-object rule the mount commands follow.
# 命令接收**结果**值。「转 90 度」的算术在 GPEditService（一处），故撤销/重做可逐字重放记录的
# 目标值、绝不重新推导 —— 与挂载命令同一条值对象规则。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Node ids, parallel to the two target arrays.
# 节点 id，与两个目标数组平行。
var _gpIds: Array[String] = []

# Target rotation in degrees, parallel to _gpIds.
# 目标旋转角（度），与 _gpIds 平行。
var _gpRots: Array[float] = []

# Target mirror flag, parallel to _gpIds.
# 目标镜像标志，与 _gpIds 平行。
var _gpFlips: Array[bool] = []

# Previous {rot, flipped} per node, captured on the FIRST execute only.
# 每个节点的先前 {rot, flipped}，仅在**首次**执行时捕获。
var _gpBefore: Array[Dictionary] = []

# Whether the snapshot was taken already (redo executes the same instance again).
# 是否已快照（重做会再次执行同一实例）。
var _gpSnapped: bool = false


# Build from parallel id / target lists.
# 由平行的 id / 目标列表构造。
func _init(gpInIds: Array[String], gpInRots: Array[float], gpInFlips: Array[bool]) -> void:
	_gpIds = gpInIds.duplicate()
	_gpRots = gpInRots.duplicate()
	_gpFlips = gpInFlips.duplicate()
	gpLabel = "旋转 / 镜像"


# Write the targets. Returns false when nothing actually changed, so a redundant R press records
# no undo step (e.g. a 0-degree rotate, or a mirror applied twice by a script).
# 写入目标值。实际无变化时返回 false，使多余的 R 按键不产生撤销步（例如 0 度旋转、
# 或被脚本连按两次的镜像）。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null or _gpIds.is_empty():
		return false
	if not _gpSnapped:
		_gpSnapped = true
		_gpBefore.clear()
		for gpId in _gpIds:
			var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
			_gpBefore.append({} if gpN == null else
				{"rot": gpN.gpRotationDeg, "flipped": gpN.gpFlipped})
	var gpChanged: bool = false
	for gpI in range(_gpIds.size()):
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpIds[gpI])
		if gpN == null:
			continue
		var gpRot: float = gpRotationAt(gpI)
		var gpFlip: bool = gpFlipAt(gpI)
		if gpN.gpRotationDeg != gpRot or gpN.gpFlipped != gpFlip:
			gpChanged = true
		gpN.gpRotationDeg = gpRot
		gpN.gpFlipped = gpFlip
	if not gpChanged:
		# Nothing moved: restore the (identical) values anyway so a partially-formed redo cannot
		# leave a node half-applied.
		# 没有任何移动：仍把（相同的）值写回，避免半成形的重做让节点停在半套状态。
		return false
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


# Put the recorded orientations back.
# 把记录的朝向放回去。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpI in range(_gpIds.size()):
		if gpI >= _gpBefore.size():
			break
		var gpPrev: Dictionary = _gpBefore[gpI]
		if gpPrev.is_empty():
			continue
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpIds[gpI])
		if gpN == null:
			continue
		gpN.gpRotationDeg = float(gpPrev.get("rot", 0.0))
		gpN.gpFlipped = bool(gpPrev.get("flipped", false))
	gpCtx.gpGraph.gpGraphChanged.emit()


# Target rotation for slot gpI (0 when the caller supplied no value).
# 第 gpI 槽的目标旋转角（调用方未给则为 0）。
func gpRotationAt(gpI: int) -> float:
	if gpI < 0 or gpI >= _gpRots.size():
		return 0.0
	return gpNormalizeDeg(_gpRots[gpI])


# Target mirror flag for slot gpI.
# 第 gpI 槽的目标镜像标志。
func gpFlipAt(gpI: int) -> bool:
	if gpI < 0 or gpI >= _gpFlips.size():
		return false
	return _gpFlips[gpI]


# Fold any angle into [0, 360). Static + pure so the wrap rule is testable on its own: a rotate
# that kept accumulating (90 → 450 → 810 …) would compare unequal against an imported 90 forever,
# and every rotate would then look like a change to the command's no-op guard.
# 把任意角折到 [0, 360)。static + 纯函数，使折返规则可单独测试：若角度一路累加（90 → 450 → 810…），
# 它将永远与导入的 90 不等，于是每次旋转在命令的空操作护栏眼里都像「有变化」。
static func gpNormalizeDeg(gpDeg: float) -> float:
	return wrapf(gpDeg, 0.0, 360.0)
