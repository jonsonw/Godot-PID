class_name GPAddShapeCommand
extends GPCommand
# Commit a finished annotation shape (line / circle / rect / arc / polyline) to the sheet (M4).
# 把绘制完成的注释图形（直线 / 圆 / 矩形 / 弧 / 折线）提交到图纸（M4）。
#
# Index rule / 下标规则:
#   Shapes are stored in z-order, so undo must put the shape back at the SAME index it came
#   from rather than appending it — otherwise undo silently restacks the drawing order.
#   图形按叠放顺序存储，故撤销必须把图形放回它原来所在的下标，而非追加到末尾，
#   否则撤销会静默改变叠放顺序。
#
# Identity rule / 同一性规则:
#   The shape OBJECT is kept, so redo re-inserts the very same instance (same id, same
#   bezier handles) instead of a rebuilt copy that would drift from what the user drew.
#   保留图形对象本身，故重做重新插入的是同一实例（同 id、同贝塞尔手柄），
#   而非会与用户所绘内容漂移的重建副本。

# The shape to add. Built by the drawing tool before it asks for a commit.
# 待加入的图形。由绘图工具在请求提交之前构造好。
var _gpShape: GPShape = null


# Build the command from an already-constructed shape.
# 由已构造好的图形建立命令。
func _init(gpInShape: GPShape) -> void:
	_gpShape = gpInShape
	gpLabel = "绘制图形"


# Append the shape. Returns false when there is nothing to add, or no graph to add it to.
# 追加图形。无图形可加或无图可加时返回 false。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null or _gpShape == null:
		return false
	gpCtx.gpGraph.gpAddShape(_gpShape)
	return true


# Take the shape back out. Located by object identity, so a stale index can never remove
# the wrong shape.
# 取回该图形。按对象同一性定位，故过期下标绝不会删错图形。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpShape == null:
		return
	gpCtx.gpGraph.gpRemoveShape(_gpShape)


# Re-insert the same shape object.
# 重新插入同一个图形对象。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpShape == null:
		return
	if gpCtx.gpGraph.gpShapes.find(_gpShape) >= 0:
		return
	gpCtx.gpGraph.gpAddShape(_gpShape)
