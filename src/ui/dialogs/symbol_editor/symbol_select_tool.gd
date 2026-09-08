# ============================================================================
# GPSymbolSelectTool — 选择 / 移动已有图形或端口（M7）
# Select / move an existing shape or port in the symbol editor (M7).
#
# 对应画布 GPSelectTool 的选择+拖拽逻辑，但作用于符号的 _gpShapes / _gpPorts 模型。拖拽为实时反馈，
# 释放时把整段移动收口为一条可撤销命令（先记起点快照，命令重放同一位移，绝不被叠加两次）。
# Mirrors the canvas GPSelectTool select+drag logic, but operates on the symbol's _gpShapes /
# _gpPorts model. The drag is live feedback; on release it is collapsed into one undoable command
# (start snapshot, command re-applies the same delta, never applied twice).
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolSelectTool
extends GPSymbolEditorTool

# Drag sub-state: 0 port, 1 shape, -1 none. / 拖拽子状态：0 端点，1 图形，-1 无。
var _gpDragKind: int = -1
# Preview-local position of the last motion. / 上一次移动所在的预览本地坐标。
var _gpDragLast: Vector2 = Vector2.ZERO
# Dragged shape or port index. / 被拖图形或端口的下标。
var _gpDragIdx: int = -1

# Snapshot of the dragged shape's points/radius at drag start (for an undoable move).
# 拖拽开始时对被拖图形点集/半径的快照（供可撤销移动使用）。
var _gpBeforePts: PackedVector2Array = PackedVector2Array()
var _gpBeforeR: float = 0.0
# Snapshot of the dragged port's normalized position at drag start.
# 拖拽开始时被拖端口的归一化位置快照。
var _gpBeforePos: Vector2 = Vector2.ZERO


func gpOnPress(gpLocal: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	var gpEd: GPSymbolEditor = gpCtx.gpEditor
	var gpPi: int = gpEd.gpHitPort(gpLocal)
	if gpPi >= 0:
		gpEd.gpSelPort = gpPi
		gpEd.gpSelShape = -1
		_gpDragKind = 0
		_gpDragIdx = gpPi
		_gpBeforePos = gpEd.gpPorts[gpPi].gpPos
		return true
	var gpSi: int = gpEd.gpHitShape(gpLocal)
	if gpSi >= 0:
		gpEd.gpSelShape = gpSi
		gpEd.gpSelPort = -1
		_gpDragKind = 1
		_gpDragIdx = gpSi
		_gpDragLast = gpLocal
		_gpBeforePts = gpEd.gpShapes[gpSi].gpPoints.duplicate()
		_gpBeforeR = gpEd.gpShapes[gpSi].gpRadius
		return true
	gpEd.gpSelPort = -1
	gpEd.gpSelShape = -1
	return true


func gpOnMove(gpLocal: Vector2) -> bool:
	var gpEd: GPSymbolEditor = gpCtx.gpEditor
	if _gpDragKind == 0 and _gpDragIdx >= 0 and _gpDragIdx < gpEd.gpPorts.size():
		gpEd.gpPorts[_gpDragIdx].gpPos = gpEd.gpLocalToNorm(gpLocal)
		return true
	if _gpDragKind == 1 and _gpDragIdx >= 0 and _gpDragIdx < gpEd.gpShapes.size():
		var gpDeltaA: Vector2 = gpEd.gpLocalToAuthor(gpLocal) - gpEd.gpLocalToAuthor(_gpDragLast)
		_gpDragLast = gpLocal
		var gpS: GPShape = gpEd.gpShapes[_gpDragIdx]
		gpS.gpPoints = GPGeometry.gpShiftPoints(gpS.gpPoints, gpDeltaA)
		return true
	return false


func gpOnRelease(gpLocal: Vector2) -> bool:
	var gpEd: GPSymbolEditor = gpCtx.gpEditor
	if _gpDragKind == 0 and _gpDragIdx >= 0 and _gpDragIdx < gpEd.gpPorts.size():
		var gpAfter: Vector2 = gpEd.gpPorts[_gpDragIdx].gpPos
		if not gpAfter.is_equal_approx(_gpBeforePos):
			gpEd.gpMovePort(_gpDragIdx, _gpBeforePos, gpAfter)
	elif _gpDragKind == 1 and _gpDragIdx >= 0 and _gpDragIdx < gpEd.gpShapes.size():
		var gpS: GPShape = gpEd.gpShapes[_gpDragIdx]
		var gpAfterPts: PackedVector2Array = gpS.gpPoints.duplicate()
		var gpAfterR: float = gpS.gpRadius
		if not _gpPointsEqual(gpAfterPts, _gpBeforePts) or not is_equal_approx(gpAfterR, _gpBeforeR):
			gpEd.gpMoveShape(_gpDragIdx, _gpBeforePts, _gpBeforeR, gpAfterPts, gpAfterR)
	_gpDragKind = -1
	_gpDragIdx = -1
	return true


# True when two point arrays are element-wise equal (within float epsilon).
# 两点集逐元素相等（浮点容差内）时返回真。
func _gpPointsEqual(gpA: PackedVector2Array, gpB: PackedVector2Array) -> bool:
	if gpA.size() != gpB.size():
		return false
	for gpI in range(gpA.size()):
		if not gpA[gpI].is_equal_approx(gpB[gpI]):
			return false
	return true
