class_name GPEdgeTagGripOps
extends RefCounted
# Copyright © 2026 Jonson Wang
# Line-number (管线号) drag interaction on a pipe. The number is a draggable annotation of its
# edge: a single click-drag moves it, a double-click on it resets to the auto placement, and a
# number dragged far enough from its pipe gets a leader line (computed, never stored) back to it.
# 管线号在其管线上的拖拽交互。管线号是所属边的一个可拖拽标注：单击拖动可移动它，双击它复位到
# 自动落位，而被拖离管线足够远的编号会获得一条指回管线的引出线（推导得出、从不落盘）。
#
# Everything above the "drag state" divider is PURE and headless-testable: given an edge id it
# answers "where is the number's box?" and "does this cursor hit it?". Only the methods below the
# divider touch the canvas. The manual offset itself is stored in WORLD units (mm) on the edge's
# "tag_offset" attribute; a near-zero offset erases the key (see GPPIDEdge.gpSetTagOffset).
# 「拖拽状态」分隔线以上的部分全是纯函数、可 headless 测试：给定边 id 回答「编号包围盒在哪」与
#「此光标是否命中」。仅分隔线以下的方法触碰画布。手工偏移本身以**世界单位（mm）**存入边的
# "tag_offset" 属性；近零偏移会擦除该键（见 GPPIDEdge.gpSetTagOffset）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Screen-pixel size of the grip square (mirrors GPLabelGripOps.GP_GRIP_SIZE). Drawn in world
# units divided by the zoom, so it stays a constant screen size like the node-label handle.
# 抓取点方块的屏幕像素尺寸（与 GPLabelGripOps.GP_GRIP_SIZE 一致）。以世界单位除以缩放绘制，
# 使屏幕尺寸保持恒定，与图元位号手柄相同。
const GP_GRIP_SIZE: float = 9.0


# ---------------------------------------------------------------- pure

# The tag glyph box (world coordinates) for an edge, or Rect2() when it shows no number.
# 一条边的管线号字形包围盒（世界坐标）；不显示编号时返回 Rect2()。
func gpTagBox(gpEdgeId: String) -> Rect2:
	if gpCv == null or gpCv.gpBinder == null:
		return Rect2()
	var gpV: GPEdgeView = gpCv.gpBinder.gpGetEdgeView(gpEdgeId)
	if gpV == null:
		return Rect2()
	var gpGeo: Dictionary = gpV.gpTagGeometry()
	if gpGeo.is_empty():
		return Rect2()
	return gpGeo.get("box", Rect2())


# Whether a world point sits on an edge's tag grip (box expanded by a screen-pixel tolerance).
# 世界点是否落在某边的管线号抓取点上（包围盒按屏幕像素容差扩张）。
func gpHitGrip(gpWorld: Vector2, gpEdgeId: String, gpTol: float = 6.0) -> bool:
	if gpCv == null or gpCv.gpGraph == null:
		return false
	var gpBox: Rect2 = gpTagBox(gpEdgeId)
	if gpBox == Rect2():
		return false
	var gpT: float = gpTol / maxf(gpCv.gpViewZoom, 0.0001)
	var gpExpanded: Rect2 = Rect2(gpBox.position - Vector2(gpT, gpT),
		gpBox.size + Vector2(gpT * 2.0, gpT * 2.0))
	return gpExpanded.has_point(gpWorld)


# First edge (any edge, not just the selected one) whose tag grip is under the cursor, or "".
# 光标下管线号抓取点所属的第一条边（任意边，不限于已选中），无则 "".
# Used on PRESS so a number dragged far off an UNselected pipe can still be grabbed to drag it
# back — the leader-line case is the whole point of the feature.
# 用于**按下**时，使被拖离「未选中」管线很远的编号仍可抓住拖回 —— 引出线情形正是本功能的全部意义。
func gpHitGripAny(gpWorld: Vector2) -> String:
	if gpCv == null or gpCv.gpGraph == null:
		return ""
	for gpE in gpCv.gpGraph.gpEdges:
		if gpHitGrip(gpWorld, gpE.gpInstanceId):
			return gpE.gpInstanceId
	return ""


# Turn a world-space drag delta into the new WORLD offset. Pipes carry no rotation or flip, so the
# offset is simply start + delta (stored as mm, independent of zoom).
# 把世界坐标下的拖拽位移换算为新的**世界**偏移。管线不承载旋转或翻转，故偏移即 start + delta
#（以 mm 存储，与缩放无关）。
func gpDragToOffset(gpEdge: GPPIDEdge, gpWorldDelta: Vector2) -> Vector2:
	if gpEdge == null:
		return Vector2.ZERO
	return _gpStartOffset + gpWorldDelta


# ---------------------------------------------------------------- drag state

# The canvas that owns the live graph + the edit ports. / 持有实时图与编辑端口的画布。
var gpCv: GPCanvas2D

# Edge id whose tag is being dragged ("" when nothing is in flight).
# 正被拖动管线号的边 id（无进行时为空）。
var _gpEdgeId: String = ""

# World position where the drag began. / 拖拽开始时的世界坐标。
var _gpStartWorld: Vector2 = Vector2.ZERO

# Offset before the drag, captured so a plain click never perturbs the value.
# 拖拽前的偏移，捕获它使单纯的点击不会扰动取值。
var _gpStartOffset: Vector2 = Vector2.ZERO

# Live preview offset applied to the edge during the drag.
# 拖拽过程中应用到边上的实时预览偏移。
var _gpLiveOffset: Vector2 = Vector2.ZERO


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# Hover feedback: show a MOVE cursor while the grip is under the cursor. Returns true when the
# caller should consume the motion event. Only scans the SELECTED edge(s) for hover feedback (cheap,
# covers the common case); press-time hit-testing still scans every edge, so an unselected far-dragged
# number remains grabbable without the hover cursor.
# 悬停反馈：抓取点在光标下时显示移动光标。返回 true 表示调用方应消费该移动事件。
# 仅对选中边做悬停反馈（开销低、覆盖常见情形）；按下时的命中检测仍扫描所有边，
# 故未选中而被拖远的编号依然可抓（只是没有悬停光标）。
func gpUpdateHoverCursor(gpWorld: Vector2) -> bool:
	if gpCv == null:
		return false
	# Yield the cursor while a symbol is pending placement.
	# 放置虚影预览期间让出光标控制权。
	if gpCv.gpPendingDef != null:
		return false
	if _gpEdgeId != "":
		gpCv.mouse_default_cursor_shape = Control.CURSOR_MOVE
		return true
	if gpCv.gpEdgeSel.is_empty():
		return false
	for gpEid in gpCv.gpEdgeSel:
		if gpHitGrip(gpWorld, gpEid):
			gpCv.mouse_default_cursor_shape = Control.CURSOR_MOVE
			return true
	gpCv.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return false


# True while a tag drag is in flight. / 管线号拖拽进行中返回真。
func gpIsDragging() -> bool:
	return _gpEdgeId != ""


# The edge id being dragged ("" when idle). / 正被拖动的边 id（空闲时为空）。
func gpDraggingEdgeId() -> String:
	return _gpEdgeId


# Begin a drag when the grip is under the cursor. Returns false so the caller can fall through to
# ordinary edge selection / double-click-to-edit when the press was not on the grip.
# 抓取点在光标下时开始拖拽。未命中返回 false，使调用方在按下的不是抓取点时
# 能继续走普通的边选择 / 双击改号流程。
func gpTryStart(gpWorld: Vector2, gpEdgeId: String) -> bool:
	if gpCv == null or gpCv.gpGraph == null or gpEdgeId == "":
		return false
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	if not gpHitGrip(gpWorld, gpEdgeId):
		return false
	_gpEdgeId = gpEdgeId
	_gpStartWorld = gpWorld
	_gpStartOffset = gpE.gpTagOffset()
	_gpLiveOffset = _gpStartOffset
	return true


# Live preview: write the dragged offset straight onto the edge so the number follows the cursor.
# The real commit happens on release, as ONE undo step (mirrors the node-label and edge-grip drags).
# 实时预览：把拖拽出的偏移直接写到边上，使编号跟随光标。真正的提交在释放时进行，
# 且合成一个撤销步（与图元位号、边抓取点的拖拽同一手法）。
func gpOnGripMove(gpWorld: Vector2) -> void:
	if _gpEdgeId == "" or gpCv == null or gpCv.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null:
		return
	# The edge still holds the drag-start offset, so the delta is measured from there — accumulating
	# per-move deltas would drift with the frame rate. / 边上的偏移仍是拖拽起点值，位移自那里起算，
	# 按每次移动累加会随帧率漂移。
	_gpLiveOffset = gpDragToOffset(gpE, gpWorld - _gpStartWorld)
	gpE.gpSetTagOffset(_gpLiveOffset)
	var gpV: GPEdgeView = gpCv.gpBinder.gpGetEdgeView(_gpEdgeId)
	if gpV != null:
		gpV.queue_redraw()
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()


# Commit the drag: rewind to the original offset, then let the command re-apply the same value —
# one undo step, never applied twice. A drag shorter than the erase epsilon is treated as a no-op so
# a jittery click does not leave a phantom undo step.
# 提交拖拽：先回退到原偏移，再由命令重新应用同一值 —— 一个撤销步，绝不会叠加两次。
# 短于擦除阈值的拖拽视作无操作，使轻微抖动的点击不会留下幽灵撤销步。
func gpEndGripDrag() -> void:
	if _gpEdgeId == "" or gpCv == null or gpCv.gpGraph == null:
		return
	var gpId: String = _gpEdgeId
	var gpNew: Vector2 = _gpLiveOffset
	_gpEdgeId = ""
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpId)
	if gpE != null:
		gpE.gpSetTagOffset(_gpStartOffset)  # rewind / 回退
		if _gpStartOffset.distance_to(gpNew) > GPPIDEdge.GP_TAG_OFFSET_EPS:
			gpCv.gpRequestSetEdgeTagOffset(gpId, gpNew)
	var gpV: GPEdgeView = gpCv.gpBinder.gpGetEdgeView(gpId)
	if gpV != null:
		gpV.queue_redraw()
	gpCv.queue_redraw()


# Abandon the drag without committing. / 放弃拖拽，不提交。
func gpCancelDrag() -> void:
	if _gpEdgeId == "" or gpCv == null or gpCv.gpGraph == null:
		return
	var gpId: String = _gpEdgeId
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpId)
	if gpE != null:
		gpE.gpSetTagOffset(_gpStartOffset)
	_gpEdgeId = ""
	var gpV: GPEdgeView = gpCv.gpBinder.gpGetEdgeView(gpId)
	if gpV != null:
		gpV.queue_redraw()
	gpCv.queue_redraw()


# Double-click the grip: reset to the auto (default) placement. A zero offset erases the key, so the
# number snaps back to GPEdgeTagLayout's automatic spot above / left of the pipe.
# 双击抓取点：复位到自动（默认）落位。零偏移会擦除该键，使编号回到 GPEdgeTagLayout 在管线上方 / 左侧
# 自动算出的位置。
func gpReset(gpEdgeId: String) -> void:
	if gpCv == null or gpEdgeId == "":
		return
	gpCv.gpRequestSetEdgeTagOffset(gpEdgeId, Vector2.ZERO)
	var gpV: GPEdgeView = gpCv.gpBinder.gpGetEdgeView(gpEdgeId)
	if gpV != null:
		gpV.queue_redraw()
	gpCv.queue_redraw()
