class_name GPSetShapeGeometryCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Commit one annotation-shape geometry edit (grip drag, whole-shape move, handle / vertex edit)
# as ONE undo step. The drag preview writes the model live; this command carries the before/after
# snapshots and, for a text note, the referencing edge-end snapshots, so Ctrl+Z restores both the
# glyph and the line that follows it.
# 把一次注释图形几何编辑（锚点拖拽 / 整形状移动 / 手柄 / 顶点编辑）提交为**一个**撤销步。
# 拖拽预览实时写模型；本命令携带 before/after 快照，并为文字注记携带引用边端快照，使 Ctrl+Z
# 同时还原字形与跟随它的连线。
#
# WHY NOT just "mutate then push a no-op command" / 为何不「先改模型再压一条空命令」：
# undo must know the exact pre-drag image. Capturing before at drag start and after at release is
# the only way a 30-move drag stays one step without replaying every intermediate frame.
# 撤销必须知道拖拽前的精确镜像。起始取 before、释放取 after，是让 30 次移动只占一个撤销步、
# 又不重放中间帧的唯一方式。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var _gpIdx: int = -1
var _gpBefore: Dictionary = {}
var _gpAfter: Dictionary = {}
var _gpEdgesBefore: Array[Dictionary] = []
var _gpEdgesAfter: Array[Dictionary] = []


func _init(gpInIdx: int, gpInBefore: Dictionary, gpInAfter: Dictionary,
		gpInEdgesBefore: Array[Dictionary] = [], gpInEdgesAfter: Array[Dictionary] = []) -> void:
	_gpIdx = gpInIdx
	_gpBefore = gpInBefore.duplicate(true)
	_gpAfter = gpInAfter.duplicate(true)
	_gpEdgesBefore = _gpCopyEdges(gpInEdgesBefore)
	_gpEdgesAfter = _gpCopyEdges(gpInEdgesAfter)
	gpLabel = "编辑注释图形"


# Snapshot the geometry fields this command owns. Deliberately narrow: style / text / props have
# their own commands and must not be swept into a drag undo image.
# 只快照本命令拥有的几何字段：样式 / 文字 / 属性各有自己的命令，不得被卷进拖拽撤销镜像。
static func gpSnapshotShape(gpShape: GPShape) -> Dictionary:
	var gpOut: Dictionary = {}
	if gpShape == null:
		return gpOut
	gpOut["points"] = gpShape.gpPoints.duplicate()
	gpOut["radius"] = gpShape.gpRadius
	var gpHandles: Array[PackedVector2Array] = []
	for gpHandle in gpShape.gpHandles:
		gpHandles.append((gpHandle as PackedVector2Array).duplicate())
	gpOut["handles"] = gpHandles
	return gpOut


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	if _gpIdx < 0 or _gpIdx >= gpCtx.gpGraph.gpShapes.size():
		return false
	if _gpBefore == _gpAfter and _gpEdgesBefore == _gpEdgesAfter:
		return false
	if not _gpApply(gpCtx, _gpAfter, _gpEdgesAfter):
		return false
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	if _gpApply(gpCtx, _gpBefore, _gpEdgesBefore):
		gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	# This is a replay, not a first execute: do not reject the snapshot pair just because the
	# model already matches "after".
	# 这是重放而非首次执行：不能因模型已是 after 就拒绝快照对。
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	if _gpApply(gpCtx, _gpAfter, _gpEdgesAfter):
		gpCtx.gpGraph.gpGraphChanged.emit()


func _gpApply(gpCtx: GPCommandContext, gpShot: Dictionary, gpEdges: Array[Dictionary]) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	if _gpIdx < 0 or _gpIdx >= gpCtx.gpGraph.gpShapes.size():
		return false
	var gpShape: GPShape = gpCtx.gpGraph.gpShapes[_gpIdx]
	if gpShape == null:
		return false
	gpShape.gpPoints = (gpShot.get("points", PackedVector2Array()) as PackedVector2Array).duplicate()
	gpShape.gpRadius = float(gpShot.get("radius", 0.0))
	gpShape.gpHandles.clear()
	var gpHandles: Array = gpShot.get("handles", []) as Array
	for gpHandleRaw in gpHandles:
		gpShape.gpHandles.append((gpHandleRaw as PackedVector2Array).duplicate())
	for gpEdgeShot in gpEdges:
		var gpEdge: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(str(gpEdgeShot.get("edge_id", "")))
		if gpEdge == null:
			continue
		gpEdge.gpFromRef = (gpEdgeShot.get("ref_from", {}) as Dictionary).duplicate(true)
		gpEdge.gpToRef = (gpEdgeShot.get("ref_to", {}) as Dictionary).duplicate(true)
	return true


func _gpCopyEdges(gpEdges: Array[Dictionary]) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	for gpEdgeRaw in gpEdges:
		gpOut.append((gpEdgeRaw as Dictionary).duplicate(true))
	return gpOut
