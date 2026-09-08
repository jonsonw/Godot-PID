# ============================================================================
# GPDrawShapeTool — 注释图形绘制（P2 拆分 · M3 状态归位）
# Annotation-shape drawing (P2 split · M3 state ownership).
#
# 持有绘图模式下的按下 / 移动 / 释放 / 按键逻辑。两点工具（直线/圆/矩形/弧）按下锚定、松开提交；
# 折线每次点击追加顶点、Enter 或双击结束。
# Two-point tools (line / circle / rect / arc) anchor on press and commit on release; the polyline
# appends a vertex per click and finishes on Enter or double click.
#
# M3：绘图瞬态状态（起点 / 终点 / 活动标记 / 折线顶点）与三条绘图逻辑（_gpOnDrawDown /
# _gpCommitDraw / _gpFinishPolyline）已从画布迁入本类。此前本工具只持有「动词」，状态与实现都
# 留在画布，于是出现「工具却没有工具的状态」——每次读写都要越过 gpCv._gp*。现在本类既持有状态
# 也持有逻辑，并自己绘制橡皮筋（经由此前声明却从未被调用的 gpDrawOverlay 钩子）。
# M3: the transient draw state and the three draw verbs moved here from the canvas. Previously this
# tool owned only the verbs while the state and implementation stayed on the canvas — "a tool
# without its own state" — so every read/write crossed gpCv._gp*. Now the tool owns both, and paints
# its own rubber band through gpDrawOverlay (a hook that was declared but never called).
# ============================================================================

class_name GPDrawShapeTool
extends GPCanvasTool

const GPMode = GPCanvasInteractState.GPMode

# ---- Transient draw state owned by this tool (M3) ----
# ---- 本工具自持的瞬态绘图状态（M3）----
# Anchor point of a two-point drag (world). / 两点拖拽的锚点（世界坐标）。
var _gpFrom: Vector2 = Vector2.ZERO

# Current rubber-band end point (world). / 橡皮筋当前终点（世界坐标）。
var _gpTo: Vector2 = Vector2.ZERO

# Whether a line / circle / rect / arc drag is active. Polyline uses _gpPolyPts instead.
# 直线/圆/矩形/弧拖拽是否进行中。折线用 _gpPolyPts 而非此标记。
var _gpActive: bool = false

# Committed-so-far polyline vertices (world). / 折线已落定的顶点（世界坐标）。
var _gpPolyPts: Array[Vector2] = []


func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	_gpOnDrawDown(gpWorld, gpDouble)
	return true


func gpOnMove(gpWorld: Vector2) -> bool:
	# Rubber band follows the cursor while drawing (two-point tools + polyline preview). Consumed:
	# the canvas accepts the motion so the band redraws exclusively here.
	# 绘制图形时橡皮筋跟随光标（两点工具 + 折线预览）。已消费：画布据此 accept 事件，仅在此重绘。
	if _gpActive or not _gpPolyPts.is_empty():
		_gpTo = gpWorld
		gpCtx.gpCv.queue_redraw()
		return true
	return false


func gpOnRelease(gpWorld: Vector2) -> bool:
	var gpCv := gpCtx.gpCv
	# Commit the line / circle / rect drag as a new annotation shape, then auto-select it and
	# return to SELECT so its grips appear immediately (AutoCAD-like direct edit).
	# 把直线/圆/矩形拖拽提交为新的注释图形，随后自动选中并切回选择模式，使其锚点立即出现。
	if _gpActive:
		var gpNewIdx: int = _gpCommitDraw(gpWorld)
		_gpActive = false
		if gpNewIdx >= 0:
			gpCv.gpShapeSel = [gpNewIdx]
			gpCv.gpSetSelection([])
			gpCv.gpSetMode(GPMode.GP_SELECT)
		gpCv.queue_redraw()
		gpCv.gpGraphChanged.emit()
		gpCv.gpEmitStatus()
	return true


func gpOnKey(gpKey: InputEventKey) -> bool:
	# Confirm the in-progress polyline (Enter is the discoverable confirm key; double click also
	# works). No-op when fewer than two vertices exist yet.
	# 确认正在绘制的折线（Enter 是直观的确认键；双击亦可用）。顶点不足 2 个时为空操作。
	if gpKey.keycode == KEY_ENTER or gpKey.keycode == KEY_KP_ENTER:
		if not _gpPolyPts.is_empty():
			_gpFinishPolyline()
			return true
	return false


# Cancel whatever is half-drawn (ESC path). Returns true when there was something to cancel, so the
# canvas can stop the key from propagating.
# 取消未完成的绘制（ESC 路径）。确有可取消内容时返回 true，画布据此阻止按键继续传播。
func gpCancel() -> bool:
	if _gpActive:
		_gpActive = false
		return true
	if not _gpPolyPts.is_empty():
		# Cancel the half-drawn polyline (do not commit); start fresh next click.
		# 取消半截折线（不提交）；下次点击从头开始。
		_gpPolyPts.clear()
		return true
	return false


# Paint the rubber band and the in-progress polyline. Moved here from GPCanvasOverlay (M3): these
# visuals are driven entirely by this tool's own state, so the tool paints them.
# 绘制橡皮筋与进行中的折线。由 GPCanvasOverlay 迁来（M3）：这些视觉完全由本工具自身状态驱动，
# 故由本工具绘制。
func gpDrawOverlay(gpCv: CanvasItem) -> void:
	# In-progress rubber band for line / circle / rect.
	# 直线/圆/矩形的进行中橡皮筋。
	if _gpActive:
		var gpA: Vector2 = gpCv.gpScreenFromWorld(_gpFrom)
		var gpB: Vector2 = gpCv.gpScreenFromWorld(_gpTo)
		match gpCtx.gpCv.gpMode:
			GPMode.GP_DRAW_LINE:
				gpCv.draw_line(gpA, gpB, Color(1.0, 0.82, 0.25), 1.5)
			GPMode.GP_DRAW_CIRCLE:
				gpCv.draw_circle(gpA, gpA.distance_to(gpB), Color(1.0, 0.82, 0.25, 0.7), false, 1.0)
			GPMode.GP_DRAW_RECT:
				gpCv.draw_rect(Rect2(gpA, gpB - gpA).abs(), Color(1.0, 0.82, 0.25, 0.7), false, 1.0)
	# In-progress polyline: committed vertices + rubber band to the cursor.
	# 进行中的折线：已落定顶点 + 到光标的橡皮筋。
	if not _gpPolyPts.is_empty():
		var gpV: PackedVector2Array = PackedVector2Array()
		for gpP in _gpPolyPts:
			gpV.append(gpCv.gpScreenFromWorld(gpP))
		if gpV.size() >= 2:
			gpCv.draw_polyline(gpV, Color(1.0, 0.82, 0.25), 1.5)
		gpCv.draw_line(gpCv.gpScreenFromWorld(_gpPolyPts.back()), gpCv.get_local_mouse_position(), Color(1.0, 0.82, 0.25, 0.6), 1.0)
		for gpP in _gpPolyPts:
			gpCv.draw_circle(gpCv.gpScreenFromWorld(gpP), 3.0, Color(1.0, 0.82, 0.25))


# ============================ private ============================

# Press handler for the drawing tools. Two-point tools (line / circle / rect / arc) anchor on press
# and commit on release; the polyline appends a vertex per click and finishes on double click.
# 绘图工具的按下处理。两点工具（直线/圆/矩形/弧）按下锚定、松开提交；折线每次点击追加一个顶点，
# 双击结束。
func _gpOnDrawDown(gpWorld: Vector2, gpDouble: bool) -> void:
	match gpCtx.gpCv.gpMode:
		GPMode.GP_DRAW_LINE, GPMode.GP_DRAW_CIRCLE, GPMode.GP_DRAW_RECT, GPMode.GP_DRAW_ARC:
			_gpFrom = gpWorld
			_gpTo = gpWorld
			_gpActive = true
			gpCtx.gpCv.queue_redraw()
		GPMode.GP_DRAW_POLYLINE:
			if gpDouble:
				_gpFinishPolyline()
			else:
				_gpPolyPts.append(gpWorld)
				_gpTo = gpWorld
				gpCtx.gpCv.queue_redraw()


# Commit the in-progress line / circle / rect / arc drag as a new annotation shape. Returns the new
# shape's index (or -1 when the drag was too small to be a real primitive).
# 把进行中的直线/圆/矩形/弧拖拽提交为一枚新的注释图形。返回新图形的下标（过小则 -1）。
func _gpCommitDraw(gpTo: Vector2) -> int:
	var gpCv := gpCtx.gpCv
	var gpS: GPShape = null
	match gpCv.gpMode:
		GPMode.GP_DRAW_LINE:
			if _gpFrom.distance_to(gpTo) >= 2.0:
				gpS = GPShape.gpLine(_gpFrom, gpTo)
		GPMode.GP_DRAW_CIRCLE:
			var gpR: float = _gpFrom.distance_to(gpTo)
			if gpR >= 2.0:
				gpS = GPShape.gpCircle(_gpFrom, gpR)
		GPMode.GP_DRAW_RECT:
			var gpR: Rect2 = Rect2(_gpFrom, gpTo - _gpFrom).abs()
			if gpR.size.x >= 2.0 and gpR.size.y >= 2.0:
				gpS = GPShape.gpRect(_gpFrom, gpTo)
		GPMode.GP_DRAW_ARC:
			# A press-drag-release defines the arc's end points; the center is their midpoint so
			# the result is the minor arc between them (half-circle when dragged straight).
			# 按下拖到松开定义弧的起止点；圆心取二者中点，故结果为二者间的劣弧（竖直拖出为半圆）。
			if _gpFrom.distance_to(gpTo) >= 2.0:
				var gpCtr: Vector2 = (_gpFrom + gpTo) * 0.5
				gpS = GPShape.gpArc(gpCtr, _gpFrom, gpTo)
	if gpS != null:
		# M4 续：提交经画布端口进入命令层（GPEditService → GPAddShapeCommand），
		# 于是「画一条线」也是一步可撤销的编辑。
		# M4 cont: the commit goes through a canvas port into the command layer, so drawing a
		# line becomes one undoable step too.
		return gpCv.gpRequestAddShape(gpS)
	return -1


# Finish a polyline drag: commit it as a new annotation shape when it has 2+ vertices.
# 结束折线拖拽：当顶点数 ≥ 2 时提交为一枚新的注释图形。
func _gpFinishPolyline() -> void:
	var gpCv := gpCtx.gpCv
	if _gpPolyPts.size() >= 2:
		var gpIdx: int = gpCv.gpRequestAddShape(GPShape.gpPolyline(_gpPolyPts.duplicate(), false))
		gpCv.gpShapeSel = [gpIdx]
		gpCv.gpSetSelection([])
		gpCv.gpSetMode(GPMode.GP_SELECT)
		gpCv.gpGraphChanged.emit()
	_gpPolyPts.clear()
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()
