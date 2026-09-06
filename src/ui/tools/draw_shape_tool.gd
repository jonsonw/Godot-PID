# ============================================================================
# GPDrawShapeTool — 注释图形绘制（P2 拆分）
# Annotation-shape drawing (P2 split).
#
# 持有绘图模式下的按下 / 移动 / 释放 / 按键逻辑，原 _gpOnLeftDown / _gpOnLeftUp / _gpOnKey 的绘图
# 分支已迁入本类（经 gpCtx.gpCv 读写画布状态，行为零变更）。两点工具（直线/圆/矩形/弧）按下锚定、
# 松开提交；折线每次点击追加顶点、Enter 或双击结束。
# Owns the drawing-mode press / move / release / key logic, migrated verbatim from _gpOnLeftDown /
# _gpOnLeftUp / _gpOnKey (reads/writes canvas state via gpCtx.gpCv, zero behavior change). Two-point
# tools (line / circle / rect / arc) anchor on press and commit on release; the polyline appends a
# vertex per click and finishes on Enter or double click.
# ============================================================================

class_name GPDrawShapeTool
extends GPCanvasTool

const GPMode = GPCanvasInteractState.GPMode

func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	gpCtx.gpCv._gpOnDrawDown(gpWorld, gpDouble)
	return true

func gpOnMove(gpWorld: Vector2) -> bool:
	var gpCv := gpCtx.gpCv
	# Rubber band follows the cursor while drawing (two-point tools + polyline preview). Consumed:
	# the canvas accepts the motion so the band redraws exclusively here.
	# 绘制图形时橡皮筋跟随光标（两点工具 + 折线预览）。已消费：画布据此 accept 事件，仅在此重绘。
	if gpCv._gpDrawActive or not gpCv._gpPolyPts.is_empty():
		gpCv._gpDrawTo = gpWorld
		gpCv.queue_redraw()
		return true
	return false

func gpOnRelease(gpWorld: Vector2) -> bool:
	var gpCv := gpCtx.gpCv
	# Commit the line / circle / rect drag as a new annotation shape, then auto-select it and
	# return to SELECT so its grips appear immediately (AutoCAD-like direct edit).
	# 把直线/圆/矩形拖拽提交为新的注释图形，随后自动选中并切回选择模式，使其锚点立即出现。
	if gpCv._gpDrawActive:
		var gpNewIdx: int = gpCv._gpCommitDraw(gpWorld)
		gpCv._gpDrawActive = false
		if gpNewIdx >= 0:
			gpCv.gpShapeSel = [gpNewIdx]
			gpCv._gpSetSelection([])
			gpCv.gpSetMode(GPMode.GP_SELECT)
		gpCv.queue_redraw()
		gpCv.gpGraphChanged.emit()
		gpCv._gpEmitStatus()
	return true

func gpOnKey(gpKey: InputEventKey) -> bool:
	var gpCv := gpCtx.gpCv
	# Confirm the in-progress polyline (Enter is the discoverable confirm key; double click also
	# works). No-op when fewer than two vertices exist yet.
	# 确认正在绘制的折线（Enter 是直观的确认键；双击亦可用）。顶点不足 2 个时为空操作。
	if gpKey.keycode == KEY_ENTER or gpKey.keycode == KEY_KP_ENTER:
		if not gpCv._gpPolyPts.is_empty():
			gpCv._gpFinishPolyline()
			return true
	return false
