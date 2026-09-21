class_name GPSetNodePositionsCommand
extends GPCommand
# Set absolute positions of one or more nodes in one undo step. Used to commit the result of
# collision-avoidance pushes (during placement and dragging) as a single, reversible edit.
# 一步将多个节点的位置设为绝对值。用于把碰撞避让的推送结果（放置与拖拽时）作为单次可撤销编辑提交。
#
# Why absolute targets instead of a shared delta / 为何用绝对目标而非统一位移:
# A collision push moves each displaced node by its OWN vector — not a uniform translate. A
# delta-only command cannot express that, so this command records { id: targetPosition } and
# captures the originals on first execute for a clean undo.
# 碰撞推送让每个被推节点各自走一段不同的位移，并非统一平移；仅靠 delta 的命令无法表达，
# 故本命令记录 { id: 目标位置 }，并在首次执行时捕获原值，以便干净地撤销。
#
# Model-only mutation: like every command it emits gpGraphChanged once so the view follows.
# 仅改模型：与本仓库所有命令一致，仅发射一次 gpGraphChanged，使视图随之刷新。

# nodeId -> absolute target position (world coordinates).
# 节点 id -> 绝对目标位置（世界坐标）。
var _gpTargets: Dictionary = {}

# nodeId -> original position captured on first execute (for undo).
# 节点 id -> 首次执行时捕获的原位置（供撤销）。
var _gpOld: Dictionary = {}

# Guards against undoing a move that was never applied (defensive).
# 防止撤销一次从未应用的移动（防御性）。
var _gpApplied: bool = false


# Build the command from the absolute target map.
# 由绝对目标字典构造命令。
func _init(gpInTargets: Dictionary) -> void:
	_gpTargets = gpInTargets.duplicate()
	gpLabel = "调整图元位置"


# Apply every target. Returns false when the graph is missing; unknown ids are skipped.
# 应用每个目标。图缺失时返回 false；未知 id 被跳过。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	_gpOld.clear()
	for gpId in _gpTargets.keys():
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
		if gpN == null:
			continue
		_gpOld[gpId] = gpN.gpPosition
		gpN.gpPosition = (_gpTargets[gpId] as Vector2)
	_gpApplied = true
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


# Restore every captured original. / 还原每个被捕获的原位置。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if not _gpApplied or gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpId in _gpOld.keys():
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
		if gpN != null:
			gpN.gpPosition = (_gpOld[gpId] as Vector2)
	_gpApplied = false
	gpCtx.gpGraph.gpGraphChanged.emit()


# Re-apply the same targets. Idempotent here, so the default redo (gpExecute()) is correct.
# 重新应用同一组目标。此处重执行幂等，默认重做（gpExecute()）即可。
func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
