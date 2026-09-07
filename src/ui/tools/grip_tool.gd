# ============================================================================
# GPGripTool — 注释图形锚点 / 整图形拖拽（P2 拆分）
# Annotation-shape grip / whole-shape drag (P2 split).
#
# 持有「选中注释图形」的锚点拖拽与整图形移动的「执行」部分：移动时实时变更几何（经 GPAnnotationEditor
# 委托），释放时收尾并广播 gpGraphChanged。发起（命中抓取点 / 整图形命中）仍在 GPSelectTool 的落空
# 路径里，本类只负责拖拽过程本身。
# Owns the EXECUTION of a selected annotation shape's grip drag and whole-shape move: it mutates
# geometry live during the drag (delegating to GPAnnotationEditor) and finalizes + emits
# gpGraphChanged on release. Initiation (grip hit / shape hit) stays in GPSelectTool's miss path;
# this tool owns the drag itself.
# ============================================================================

class_name GPGripTool
extends GPCanvasTool

# M3: "is a drag in flight?" is now answered by the drag's owner (GPAnnotationEditor), not by
# peeking at canvas fields.
# M3：「是否有拖拽在进行」改由拖拽的持有者（GPAnnotationEditor）回答，而非窥探画布字段。
func gpOnMove(gpWorld: Vector2) -> bool:
	var gpAnno := gpCtx.gpAnno
	# Dragging a grip (handle) of the selected annotation shape reshapes / resizes it.
	# 拖动选中注释图形的锚点（手柄）以重塑 / 缩放图形。
	if gpAnno.gpHasGripDrag():
		gpAnno.gpOnGripMove(gpWorld)
	# Dragging the whole selected annotation shape moves it.
	# 拖动整枚选中的注释图形以移动之。
	elif gpAnno.gpHasShapeDrag():
		gpAnno.gpOnShapeMove(gpWorld)
	return true


func gpOnRelease(gpWorld: Vector2) -> bool:
	var gpCv := gpCtx.gpCv
	var gpAnno := gpCtx.gpAnno
	# Finish a grip (handle) drag — geometry already mutated live during the drag.
	# 结束锚点（手柄）拖拽——几何已在拖拽过程中实时变更。
	if gpAnno.gpHasGripDrag():
		gpAnno.gpEndGripDrag()
		gpCv.gpGraphChanged.emit()
		gpCv.gpEmitStatus()
		return true
	# Finish a whole-shape move.
	# 结束整枚图形的移动。
	if gpAnno.gpHasShapeDrag():
		gpAnno.gpEndShapeDrag()
		gpCv.gpGraphChanged.emit()
		gpCv.gpEmitStatus()
		return true
	return false
