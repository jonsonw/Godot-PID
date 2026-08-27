class_name GPGlyphCanvas
extends Control

# Copyright © 2026 Jonson Wang
# Drawing surface for step 2 of the symbol editor wizard ("draw the glyph").
# 图元编辑器向导第 2 步（「画字形」）的绘图面板。
# Author space is simply this control's local pixel space: only the RELATIVE geometry matters,
# because GPSymbolNormalizer rescales the bounding box into the 100x100 unit box on export.
# 作者空间就是本控件的本地像素空间：只有「相对」几何有意义，因为导出时
# GPSymbolNormalizer 会把包围盒重新缩放到 100x100 单位框。
# The dashed guide rectangle shows the category nominal envelope aspect so the author can see
# what proportion the symbol will finally occupy.
# 虚线参考框显示类别标称包络的长宽比，让作者直观看到图元最终占据的比例。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Emitted whenever the draft geometry changes (commit / undo / clear).
# 草稿几何发生变化时发出（提交 / 撤销 / 清空）。
signal gpDraftChanged

# Active drawing tool.
# 当前绘图工具。
enum GPTool { GP_POLYLINE, GP_CIRCLE, GP_RECT, GP_PORT }

# Grid spacing in author-space pixels.
# 网格间距（作者空间像素）。
const GP_GRID: float = 16.0

# Snap radius for pulling a port onto the guide rectangle edge.
# 将端口吸附到参考框边线的吸附半径。
const GP_PORT_SNAP: float = 12.0

# Fraction of the shorter widget dimension occupied by the guide rectangle.
# 参考框占控件较短边的比例。
const GP_GUIDE_FILL: float = 0.62

# Selected tool.
# 已选工具。
var gpTool: GPTool = GPTool.GP_POLYLINE

# Whether clicks snap to the grid.
# 点击是否吸附到网格。
var gpSnap: bool = true

# Nominal envelope of the target category (used for the guide rectangle aspect only).
# 目标类别的标称包络（仅用于参考框长宽比）。
var gpEnvelope: Vector2 = Vector2(64, 48)

# Committed polylines: [{"pts": [Vector2...], "closed": bool}].
# 已提交折线：[{"pts": [Vector2...], "closed": bool}]。
var gpPaths: Array[Dictionary] = []

# Committed circles: [{"c": Vector2, "r": float}].
# 已提交圆：[{"c": Vector2, "r": float}]。
var gpCircles: Array[Dictionary] = []

# Committed rectangles: [Rect2].
# 已提交矩形：[Rect2]。
var gpRects: Array[Rect2] = []

# Placed ports: [{"name": String, "pos": Vector2}].
# 已放置端口：[{"name": String, "pos": Vector2}]。
var gpPorts: Array[Dictionary] = []

# Chronological record of primitive kinds, so undo removes the most recent one.
# 图元原语种类的时间顺序记录，使撤销能移除最近一次操作。
var _gpHistory: Array[String] = []

# In-progress polyline points.
# 正在绘制的折线点。
var _gpDraftPts: Array[Vector2] = []

# Drag anchor for circle / rect tools.
# 圆 / 矩形工具的拖拽起点。
var _gpDragFrom: Vector2 = Vector2.ZERO

# Whether a circle / rect drag is active.
# 圆 / 矩形拖拽是否进行中。
var _gpDragging: bool = false

# Live cursor position in author space (for rubber-band feedback).
# 作者空间中的实时光标位置（用于橡皮筋反馈）。
var _gpCursor: Vector2 = Vector2.ZERO


# Make the control focusable so keyboard shortcuts reach _gui_input.
# 让控件可获得焦点，使键盘快捷键能进入 _gui_input。
func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP


# Switch the active tool and drop any half-finished primitive.
# 切换当前工具，并丢弃未完成的图元原语。
func gpSetTool(gpNew: GPTool) -> void:
	gpFinishPath()
	gpTool = gpNew
	_gpDragging = false
	queue_redraw()


# Toggle grid snapping.
# 切换网格吸附。
func gpSetSnap(gpOn: bool) -> void:
	gpSnap = gpOn
	queue_redraw()


# Update the guide rectangle aspect after the category changed.
# 类别变化后更新参考框长宽比。
func gpSetEnvelope(gpEnv: Vector2) -> void:
	gpEnvelope = gpEnv
	queue_redraw()


# Commit the in-progress polyline (no-op when fewer than two points exist).
# 提交正在绘制的折线（点数少于 2 时为空操作）。
func gpFinishPath(gpClosed: bool = false) -> void:
	if _gpDraftPts.size() >= 2:
		gpPaths.append({"pts": _gpDraftPts.duplicate(), "closed": gpClosed})
		_gpHistory.append("path")
		gpDraftChanged.emit()
	_gpDraftPts.clear()
	queue_redraw()


# Remove the most recently committed primitive (or the in-progress polyline point).
# 移除最近提交的图元原语（或正在绘制折线的最后一个点）。
func gpUndo() -> void:
	if not _gpDraftPts.is_empty():
		_gpDraftPts.remove_at(_gpDraftPts.size() - 1)
		queue_redraw()
		return
	if _gpHistory.is_empty():
		return
	var gpKind: String = _gpHistory.pop_back()
	match gpKind:
		"path":
			if not gpPaths.is_empty():
				gpPaths.remove_at(gpPaths.size() - 1)
		"circle":
			if not gpCircles.is_empty():
				gpCircles.remove_at(gpCircles.size() - 1)
		"rect":
			if not gpRects.is_empty():
				gpRects.remove_at(gpRects.size() - 1)
		"port":
			if not gpPorts.is_empty():
				gpPorts.remove_at(gpPorts.size() - 1)
	gpDraftChanged.emit()
	queue_redraw()


# Drop the whole drawing.
# 清空整幅绘图。
func gpClear() -> void:
	gpPaths.clear()
	gpCircles.clear()
	gpRects.clear()
	gpPorts.clear()
	_gpHistory.clear()
	_gpDraftPts.clear()
	_gpDragging = false
	gpDraftChanged.emit()
	queue_redraw()


# Export the drawing as an author-space shape dictionary for GPSymbolNormalizer.
# 把绘图导出为供 GPSymbolNormalizer 使用的作者空间形状字典。
func gpGetDraftShapes() -> Dictionary:
	var gpOutPaths: Array = []
	for gpP in gpPaths:
		var gpPts: Array = []
		for gpPt in gpP["pts"]:
			gpPts.append([gpPt.x, gpPt.y])
		gpOutPaths.append({"pts": gpPts, "closed": bool(gpP["closed"])})
	var gpOutCircles: Array = []
	for gpC in gpCircles:
		var gpCc: Vector2 = gpC["c"]
		gpOutCircles.append({"c": [gpCc.x, gpCc.y], "r": float(gpC["r"])})
	var gpOutRects: Array = []
	for gpR in gpRects:
		gpOutRects.append({"pos": [gpR.position.x, gpR.position.y], "size": [gpR.size.x, gpR.size.y]})
	return {"paths": gpOutPaths, "circles": gpOutCircles, "rects": gpOutRects}


# Export the placed ports as an author-space port array.
# 把已放置端口导出为作者空间端口数组。
func gpGetDraftPorts() -> Array:
	var gpOut: Array = []
	for gpP in gpPorts:
		var gpPos: Vector2 = gpP["pos"]
		gpOut.append({"name": str(gpP["name"]), "pos": [gpPos.x, gpPos.y]})
	return gpOut


# Whether anything has been drawn yet.
# 是否已绘制任何内容。
func gpIsEmpty() -> bool:
	return gpPaths.is_empty() and gpCircles.is_empty() and gpRects.is_empty()


# Handle mouse and keyboard input for the active tool.
# 处理当前工具的鼠标与键盘输入。
func _gui_input(gpEvent: InputEvent) -> void:
	if gpEvent is InputEventMouseMotion:
		_gpCursor = _gpSnapPoint((gpEvent as InputEventMouseMotion).position)
		if _gpDragging or not _gpDraftPts.is_empty():
			queue_redraw()
		return

	if gpEvent is InputEventMouseButton:
		var gpMb: InputEventMouseButton = gpEvent as InputEventMouseButton
		var gpPt: Vector2 = _gpSnapPoint(gpMb.position)
		if gpMb.button_index == MOUSE_BUTTON_RIGHT and gpMb.pressed:
			# Right click finishes an open polyline, otherwise undoes.
			# 右键结束未闭合折线，否则执行撤销。
			if _gpDraftPts.is_empty():
				gpUndo()
			else:
				gpFinishPath(false)
			accept_event()
			return
		if gpMb.button_index != MOUSE_BUTTON_LEFT:
			return
		match gpTool:
			GPTool.GP_POLYLINE:
				if gpMb.pressed:
					if gpMb.double_click:
						gpFinishPath(_gpNearFirst(gpPt))
					else:
						_gpDraftPts.append(gpPt)
						_gpCursor = gpPt
						queue_redraw()
			GPTool.GP_CIRCLE, GPTool.GP_RECT:
				if gpMb.pressed:
					_gpDragFrom = gpPt
					_gpCursor = gpPt
					_gpDragging = true
				else:
					_gpCommitDrag(gpPt)
			GPTool.GP_PORT:
				if gpMb.pressed:
					_gpAddPort(_gpSnapToGuide(gpPt))
		accept_event()
		return

	if gpEvent is InputEventKey:
		var gpKey: InputEventKey = gpEvent as InputEventKey
		if not gpKey.pressed:
			return
		match gpKey.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				gpFinishPath(false)
				accept_event()
			KEY_ESCAPE:
				_gpDraftPts.clear()
				_gpDragging = false
				queue_redraw()
				accept_event()
			KEY_BACKSPACE:
				gpUndo()
				accept_event()


# Commit a circle or rectangle drag.
# 提交圆或矩形拖拽。
func _gpCommitDrag(gpTo: Vector2) -> void:
	if not _gpDragging:
		return
	_gpDragging = false
	if gpTool == GPTool.GP_CIRCLE:
		var gpR: float = _gpDragFrom.distance_to(gpTo)
		if gpR >= 2.0:
			gpCircles.append({"c": _gpDragFrom, "r": gpR})
			_gpHistory.append("circle")
			gpDraftChanged.emit()
	else:
		var gpRect: Rect2 = Rect2(_gpDragFrom, gpTo - _gpDragFrom).abs()
		if gpRect.size.x >= 2.0 and gpRect.size.y >= 2.0:
			gpRects.append(gpRect)
			_gpHistory.append("rect")
			gpDraftChanged.emit()
	queue_redraw()


# Append one port with an auto-generated name.
# 追加一个自动命名的端口。
func _gpAddPort(gpPos: Vector2) -> void:
	gpPorts.append({"name": "p%d" % (gpPorts.size() + 1), "pos": gpPos})
	_gpHistory.append("port")
	gpDraftChanged.emit()
	queue_redraw()


# Snap a point to the grid when snapping is on.
# 开启吸附时把点吸附到网格。
func _gpSnapPoint(gpPt: Vector2) -> Vector2:
	if not gpSnap:
		return gpPt
	return Vector2(snappedf(gpPt.x, GP_GRID), snappedf(gpPt.y, GP_GRID))


# Pull a point onto the nearest guide-rectangle edge when it is close enough.
# 当点足够靠近时，把它吸附到最近的参考框边线上。
func _gpSnapToGuide(gpPt: Vector2) -> Vector2:
	var gpGuide: Rect2 = _gpGuideRect()
	var gpDl: float = absf(gpPt.x - gpGuide.position.x)
	var gpDr: float = absf(gpPt.x - gpGuide.end.x)
	var gpDt: float = absf(gpPt.y - gpGuide.position.y)
	var gpDb: float = absf(gpPt.y - gpGuide.end.y)
	var gpBest: float = minf(minf(gpDl, gpDr), minf(gpDt, gpDb))
	if gpBest > GP_PORT_SNAP:
		return gpPt
	if is_equal_approx(gpBest, gpDl):
		return Vector2(gpGuide.position.x, gpPt.y)
	if is_equal_approx(gpBest, gpDr):
		return Vector2(gpGuide.end.x, gpPt.y)
	if is_equal_approx(gpBest, gpDt):
		return Vector2(gpPt.x, gpGuide.position.y)
	return Vector2(gpPt.x, gpGuide.end.y)


# Whether a point is close enough to the first draft point to auto-close the polyline.
# 点是否足够靠近折线首点以自动闭合。
func _gpNearFirst(gpPt: Vector2) -> bool:
	if _gpDraftPts.is_empty():
		return false
	return _gpDraftPts[0].distance_to(gpPt) <= GP_GRID


# The dashed guide rectangle: centered, with the category envelope aspect ratio.
# 虚线参考框：居中，采用类别包络的长宽比。
func _gpGuideRect() -> Rect2:
	var gpMaxEnv: float = maxf(maxf(gpEnvelope.x, gpEnvelope.y), 1.0)
	var gpSpan: float = minf(size.x, size.y) * GP_GUIDE_FILL
	var gpK: float = gpSpan / gpMaxEnv
	var gpSz: Vector2 = gpEnvelope * gpK
	return Rect2((size - gpSz) * 0.5, gpSz)


# Render grid, guide rectangle, committed primitives, rubber band and ports.
# 绘制网格、参考框、已提交图元原语、橡皮筋与端口。
func _draw() -> void:
	var gpBg: Color = Color(0.13, 0.14, 0.17)
	var gpGridCol: Color = Color(1, 1, 1, 0.06)
	var gpGuideCol: Color = Color(0.45, 0.75, 1.0, 0.55)
	var gpInk: Color = Color(0.92, 0.94, 0.98)
	var gpDraftCol: Color = Color(1.0, 0.82, 0.25)
	var gpPortCol: Color = Color(0.35, 1.0, 0.55)

	draw_rect(Rect2(Vector2.ZERO, size), gpBg, true)

	# Grid.
	# 网格。
	var gpX: float = 0.0
	while gpX <= size.x:
		draw_line(Vector2(gpX, 0), Vector2(gpX, size.y), gpGridCol, 1.0)
		gpX += GP_GRID
	var gpY: float = 0.0
	while gpY <= size.y:
		draw_line(Vector2(0, gpY), Vector2(size.x, gpY), gpGridCol, 1.0)
		gpY += GP_GRID

	# Guide rectangle + center crosshair.
	# 参考框 + 中心十字线。
	var gpGuide: Rect2 = _gpGuideRect()
	draw_rect(gpGuide, gpGuideCol, false, 1.0)
	var gpCtr: Vector2 = gpGuide.get_center()
	draw_line(Vector2(gpGuide.position.x, gpCtr.y), Vector2(gpGuide.end.x, gpCtr.y), Color(gpGuideCol, 0.25), 1.0)
	draw_line(Vector2(gpCtr.x, gpGuide.position.y), Vector2(gpCtr.x, gpGuide.end.y), Color(gpGuideCol, 0.25), 1.0)

	# Committed primitives.
	# 已提交图元原语。
	for gpP in gpPaths:
		var gpPts: Array = gpP["pts"]
		var gpVecs: PackedVector2Array = PackedVector2Array()
		for gpPt in gpPts:
			gpVecs.append(gpPt)
		if bool(gpP["closed"]) and gpVecs.size() >= 2:
			gpVecs.append(gpVecs[0])
		if gpVecs.size() >= 2:
			draw_polyline(gpVecs, gpInk, 2.0)
	for gpC in gpCircles:
		draw_circle(gpC["c"], float(gpC["r"]), gpInk, false, 2.0)
	for gpR in gpRects:
		draw_rect(gpR, gpInk, false, 2.0)

	# In-progress polyline (committed segments solid, rubber band to cursor).
	# 正在绘制的折线（已落点为实线，到光标为橡皮筋）。
	if not _gpDraftPts.is_empty():
		var gpDv: PackedVector2Array = PackedVector2Array()
		for gpPt in _gpDraftPts:
			gpDv.append(gpPt)
		if gpDv.size() >= 2:
			draw_polyline(gpDv, gpDraftCol, 2.0)
		draw_line(_gpDraftPts[_gpDraftPts.size() - 1], _gpCursor, Color(gpDraftCol, 0.6), 1.0)
		for gpPt in _gpDraftPts:
			draw_circle(gpPt, 3.0, gpDraftCol)

	# Rubber band for circle / rect drags.
	# 圆 / 矩形拖拽的橡皮筋。
	if _gpDragging:
		if gpTool == GPTool.GP_CIRCLE:
			draw_circle(_gpDragFrom, _gpDragFrom.distance_to(_gpCursor), Color(gpDraftCol, 0.7), false, 1.0)
		else:
			draw_rect(Rect2(_gpDragFrom, _gpCursor - _gpDragFrom).abs(), Color(gpDraftCol, 0.7), false, 1.0)

	# Ports.
	# 端口。
	for gpP in gpPorts:
		var gpPos: Vector2 = gpP["pos"]
		draw_circle(gpPos, 4.0, gpPortCol)
		draw_circle(gpPos, 7.0, Color(gpPortCol, 0.35), false, 1.0)
