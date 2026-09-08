# ============================================================================
# GPSymbolDrawTool — 绘制新图元（直线 / 矩形 / 圆 / 折线）（M7）
# Draw a new primitive (line / rect / circle / polyline) in the symbol editor (M7).
#
# 对应画布 GPDrawShapeTool：两点工具按下锚定、松开提交；折线每次点击追加顶点、Enter / 双击 / 闭合时
# 结束。瞬态状态（起止点、橡皮筋、折线顶点）与绘制逻辑都在本工具内，提交经编辑器的可撤销命令。
# Mirrors the canvas GPDrawShapeTool: two-point tools anchor on press and commit on release; the
# polyline appends a vertex per click and finishes on Enter / double click / loop close. Transient
# state (anchor, rubber band, polyline vertices) and the draw verbs live here; the commit goes
# through the editor's undoable command.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolDrawTool
extends GPSymbolEditorTool

# Which primitive this tool instance draws. Set by the editor when the tool is activated.
# 本工具实例绘制哪种图元。由编辑器在激活时设定。
var _gpKind: int = GPShape.GPKind.GP_LINE

# Two-point drag anchor (author space) + rubber-band end. / 两点拖拽的锚点（作者空间）+ 橡皮筋终点。
var _gpFrom: Vector2 = Vector2.ZERO
var _gpTo: Vector2 = Vector2.ZERO
var _gpActive: bool = false

# Committed-so-far polyline vertices (author space). / 折线已落定顶点（作者空间）。
var _gpPolyPts: Array[Vector2] = []

# Minimum size to count as a real primitive. / 视为真实图元的最小尺寸。
const GP_MIN_LEN: float = 3.0


func gpOnDeactivate() -> void:
	_gpActive = false
	_gpPolyPts.clear()


func gpOnPress(gpLocal: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	var gpEd: GPSymbolEditor = gpCtx.gpEditor
	if _gpKind == GPShape.GPKind.GP_POLYLINE:
		if gpDouble:
			_gpFinishPolyline(gpEd)
		else:
			var gpA: Vector2 = gpEd.gpLocalToAuthor(gpLocal)
			# Close the loop when clicking near the first vertex. / 点回首顶点时闭合。
			if _gpPolyPts.size() >= 2 and gpEd.gpAuthorToLocal(_gpPolyPts[0]).distance_to(gpLocal) < 8.0:
				_gpFinishPolyline(gpEd)
			else:
				_gpPolyPts.append(gpA)
				_gpTo = gpA
		return true
	# Two-point tools: anchor on press. / 两点工具：按下锚定。
	_gpFrom = gpEd.gpLocalToAuthor(gpLocal)
	_gpTo = _gpFrom
	_gpActive = true
	return true


func gpOnMove(gpLocal: Vector2) -> bool:
	if _gpActive or not _gpPolyPts.is_empty():
		_gpTo = gpCtx.gpEditor.gpLocalToAuthor(gpLocal)
		return true
	return false


func gpOnRelease(gpLocal: Vector2) -> bool:
	var gpEd: GPSymbolEditor = gpCtx.gpEditor
	if _gpActive:
		_gpCommit(gpEd, gpEd.gpLocalToAuthor(gpLocal))
		_gpActive = false
	return true


func gpOnKey(gpKey: InputEventKey) -> bool:
	var gpEd: GPSymbolEditor = gpCtx.gpEditor
	if gpKey.keycode == KEY_ENTER or gpKey.keycode == KEY_KP_ENTER:
		if not _gpPolyPts.is_empty():
			_gpFinishPolyline(gpEd)
			return true
	return false


# Cancel whatever is half-drawn (ESC path). Returns true when there was something to cancel.
# 取消未完成的绘制（ESC 路径）。确有可取消内容时返回 true。
func gpCancel() -> bool:
	if _gpActive:
		_gpActive = false
		return true
	if not _gpPolyPts.is_empty():
		_gpPolyPts.clear()
		return true
	return false


# Commit the in-progress two-point drag as a new primitive, then auto-select it and return to
# SELECT (AutoCAD-like direct edit). / 把进行中的两点拖拽提交为图元，随后自动选中并切回选择模式。
func _gpCommit(gpEd: GPSymbolEditor, gpTo: Vector2) -> void:
	var gpS: GPShape = null
	match _gpKind:
		GPShape.GPKind.GP_LINE:
			if _gpFrom.distance_to(gpTo) >= GP_MIN_LEN:
				gpS = GPShape.gpLine(_gpFrom, gpTo)
		GPShape.GPKind.GP_RECT:
			var gpR: Rect2 = Rect2(_gpFrom, gpTo - _gpFrom).abs()
			if gpR.size.x >= GP_MIN_LEN and gpR.size.y >= GP_MIN_LEN:
				gpS = GPShape.gpRect(_gpFrom, gpTo)
		GPShape.GPKind.GP_CIRCLE:
			var gpR: float = _gpFrom.distance_to(gpTo)
			if gpR >= GP_MIN_LEN:
				gpS = GPShape.gpCircle(_gpFrom, gpR)
	if gpS != null:
		gpEd.gpAddShape(gpS)
		gpEd.gpSetTool(GPSymbolEditor.GP_SELECT)


# Finish a polyline drag: commit it as a new primitive when it has 2+ vertices.
# 结束折线拖拽：当顶点数 >= 2 时提交为图元。
func _gpFinishPolyline(gpEd: GPSymbolEditor) -> void:
	if _gpPolyPts.size() >= 2:
		var gpArr: Array[Vector2] = []
		for gpP in _gpPolyPts:
			gpArr.append(gpP)
		gpEd.gpAddShape(GPShape.gpPolyline(gpArr, false))
		gpEd.gpSetTool(GPSymbolEditor.GP_SELECT)
	_gpPolyPts.clear()


func gpDrawOverlay(gpC: Control) -> void:
	var gpEd: GPSymbolEditor = gpCtx.gpEditor
	if _gpActive:
		var gpA: Vector2 = gpEd.gpAuthorToLocal(_gpFrom)
		var gpB: Vector2 = gpEd.gpAuthorToLocal(_gpTo)
		match _gpKind:
			GPShape.GPKind.GP_LINE:
				gpC.draw_line(gpA, gpB, Color(0.6, 0.9, 1.0), 1.5)
			GPShape.GPKind.GP_RECT:
				gpC.draw_rect(Rect2(gpA, gpB - gpA).abs(), Color(0.6, 0.9, 1.0, 0.7), false, 1.0)
			GPShape.GPKind.GP_CIRCLE:
				gpC.draw_circle(gpA, gpA.distance_to(gpB), Color(0.6, 0.9, 1.0, 0.7), false, 1.0)
	if not _gpPolyPts.is_empty():
		var gpV: PackedVector2Array = PackedVector2Array()
		for gpP in _gpPolyPts:
			gpV.append(gpEd.gpAuthorToLocal(gpP))
		if gpV.size() >= 2:
			gpC.draw_polyline(gpV, Color(0.6, 0.9, 1.0), 1.5)
		gpC.draw_line(gpEd.gpAuthorToLocal(_gpPolyPts.back()), gpEd.gpAuthorToLocal(_gpTo), Color(0.6, 0.9, 1.0, 0.6), 1.0)
		for gpP in _gpPolyPts:
			gpC.draw_circle(gpEd.gpAuthorToLocal(gpP), 3.0, Color(0.6, 0.9, 1.0))
