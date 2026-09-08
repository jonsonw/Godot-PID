# ============================================================================
# GPSelectTool — 选择 / 连线 / 框选 / 注释图形 交互（P2 拆分 · M3 状态归位）
# Select / connect / marquee / annotation-shape interaction (P2 split · M3 state ownership).
#
# 持有「选择模式」下的按下 / 释放 / 移动逻辑。锚点 / 整图形拖拽的「执行」部分在 GPGripTool，本类
# 只负责发起它们。
# Owns the SELECT-mode press / release / move logic. The grip / whole-shape DRAG execution lives in
# GPGripTool; this tool only initiates it.
#
# M3：整组拖拽状态（_gpDragId / _gpDragStartWorld / _gpDragOrigins）与其执行函数（gpOnDragMove）、
# 框选提交（_gpCommitMarquee）已从画布迁入本类；画布侧对应的私有字段与函数已删除，改经公开端口
# （gpMarq / gpRequest* / gpSnapshot）暴露。框选橡皮筋本身仍由 GPCanvasMarquee 经共享状态对象持有，
# 本类经 gpCtx.gpState.gpMarquee 取用（与画布的 gpMarq 是同一实例，故行为完全等价）。
# M3: the group-drag state and its executor (gpOnDragMove) plus the marquee commit moved here from
# the canvas; the canvas's private fields/functions were deleted and replaced by public ports
# (gpMarq / gpRequest* / gpSnapshot). The marquee band stays in GPCanvasMarquee via the shared
# state object; this tool reaches it through gpCtx.gpState.gpMarquee (same instance as gpMarq).
# ============================================================================

class_name GPSelectTool
extends GPCanvasTool

const GPMode = GPCanvasInteractState.GPMode

# ---- Group-drag state owned by this tool (M3) ----
# ---- 本工具自持的整组拖拽状态（M3）----
# Pressed node that anchors the group drag ("" = no drag in flight).
# 锚定整组拖拽的被按下节点（"" 表示无进行中的拖拽）。
var _gpDragId: String = ""

# World position where the group drag started (to measure the delta).
# 整组拖拽开始时的世界坐标（用于测量位移）。
var _gpDragStartWorld: Vector2 = Vector2.ZERO

# Snapshot of every dragged node's position at drag start: id -> Vector2.
# 拖拽开始时各被拖节点位置的快照：id -> Vector2。
var _gpDragOrigins: Dictionary = {}

# The marquee band, owned by the shared interact state (same instance as the canvas's _gpMarq).
# 选框橡皮筋，由共享交互状态持有（与画布的 _gpMarq 为同一实例）。
var _gpMarq: GPCanvasMarquee:
	get: return gpCtx.gpState.gpMarquee


# True while a whole-selection group drag is in flight (M3: replaces peeking at gpCv._gpDragId).
# 整组拖拽进行中返回真（M3：取代窥探 gpCv._gpDragId）。
func gpIsDragging() -> bool:
	return _gpDragId != ""


# Abandon any in-flight group drag (canvas clear-selection path).
# 放弃进行中的整组拖拽（画布清空选择路径）。
func gpCancelDrag() -> void:
	_gpDragId = ""
	_gpDragOrigins.clear()


# ESC path (M4 续): report whether a group drag was abandoned, so the canvas can cancel
# through the generic tool port instead of holding this tool's concrete type.
# ESC 路径（M4 续）：报告是否放弃了整组拖拽，使画布可经通用工具端口取消，
# 而不必持有本工具的具体类型。
func gpCancel() -> bool:
	if _gpDragId == "":
		return false
	gpCancelDrag()
	return true


# Live-apply a group drag: replay every selected node from its start snapshot by the same delta, so
# a drag never accumulates rounding drift. Moved from the canvas (M3).
# 实时应用整组拖拽：按同一位移从起始快照重放每个被选节点，使拖拽不累积舍入漂移。由画布迁来（M3）。
func gpOnDragMove(gpScreen: Vector2) -> void:
	var gpCv := gpCtx.gpCv
	var gpDelta: Vector2 = gpCv.gpWorldFromScreen(gpScreen) - _gpDragStartWorld
	for gpId in _gpDragOrigins.keys():
		var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
		if gpN == null:
			continue
		gpN.gpPosition = (_gpDragOrigins[gpId] as Vector2) + gpDelta
		var gpV: GPSymbolView = gpCv.gpBinder.gpGetSymbolView(gpId)
		if gpV != null:
			gpV.gpUpdateTransform()


func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	var gpCv := gpCtx.gpCv
	var gpHit: String = gpCv.gpHitTest(gpWorld)
	# Double click edits the symbol's geometry in place (AutoCAD BEDIT entry point).
	# 双击就地编辑图元几何（AutoCAD BEDIT 入口）。
	if gpDouble and gpHit != "":
		var gpDblNode: GPPIDNode = gpCv.gpGraph.gpGetNode(gpHit)
		if gpDblNode != null:
			gpCv.gpSymbolEditRequested.emit(gpDblNode.gpSymbolId)
		return true
	# Connect mode: pick source then destination.
	# 连线模式：先选起点再选终点。
	if gpCv.gpMode == GPMode.GP_CONNECT:
		if gpHit != "":
			if gpCv.gpConnectFrom == "":
				gpCv.gpConnectFrom = gpHit
			else:
				if gpCv.gpConnectFrom != gpHit:
					# M4 续：连线改经画布端口进入命令层，从而可撤销（此前直接调 gpAddEdge，
					# 无法撤销且绕过了共享 id 生成器之外的全部约定）。
					# M4 cont: connecting now goes through a canvas port into the command layer
					# so it becomes undoable (it used to call gpAddEdge directly).
					gpCv.gpRequestConnect(gpCv.gpConnectFrom, gpHit)
				gpCv.gpConnectFrom = ""
			gpCv.queue_redraw()
		return true
	# SELECT mode: hit -> select (Shift toggles); miss -> start a marquee.
	# 选择模式：命中 → 选择（Shift 切换）；落空 → 开始框选。
	if gpHit != "":
		if gpShift:
			if gpCv.gpSelection.has(gpHit):
				gpCv.gpSelection.erase(gpHit)
			else:
				gpCv.gpSelection.append(gpHit)
			gpCv.gpSetSelection(gpCv.gpSelection)
		elif not gpCv.gpSelection.has(gpHit):
			gpCv.gpSetSelection([gpHit])
		# Start a group drag only when the pressed node belongs to the selection.
		# 仅当按下的节点属于选择集时才开始整组拖拽。
		if gpCv.gpSelection.has(gpHit):
			_gpDragId = gpHit
			_gpDragStartWorld = gpWorld
			_gpDragOrigins.clear()
			for gpId in gpCv.gpSelection:
				var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
				if gpN != null:
					_gpDragOrigins[gpId] = gpN.gpPosition
		else:
			_gpDragId = ""
	else:
		# Double-clicking a vertex / handle grip of the single selected annotation polyline toggles
		# Bézier handles (corner <-> smooth). Intercept BEFORE the hit/move logic below.
		# 双击「单选注释折线」的顶点 / 手柄抓取点：切换贝塞尔手柄（拐角 <-> 平滑）。须在下方命中/移动
		# 逻辑之前拦截。
		if gpDouble and gpCtx.gpAnno.gpOnShapeGripDoubleClick(gpWorld):
			return true
		# When a single shape is selected, try to grab one of ITS grips first. A pulled-out Bézier
		# handle end often sits OUTSIDE the polyline stroke, so testing shape-line hit first would
		# miss it and fall through to a marquee — making handles appear but not draggable.
		# 当单选一枚图形时，先尝试命中它自己的抓取点。拉出的贝塞尔手柄末端常位于折线墨线之外，若先按
		# 线段命中，会漏判并落入框选——造成句柄可见却拖不动。
		if gpCv.gpShapeSel.size() == 1:
			var gpGripAny: Dictionary = gpCtx.gpAnno.gpHitGrip(gpWorld, gpCv.gpShapeSel[0])
			if not gpGripAny.is_empty():
				gpCtx.gpAnno.gpStartGripDrag(gpGripAny)
				return true
		# No symbol hit: try an annotation shape (grip editing has priority when one is selected).
		# 未命中图元：改试注释图形（选中一枚时锚点编辑优先）。
		var gpSh: int = gpCv.gpHitShape(gpWorld)
		if gpSh >= 0:
			if gpCv.gpShapeSel.size() == 1:
				var gpGrip: Dictionary = gpCtx.gpAnno.gpHitGrip(gpWorld, gpCv.gpShapeSel[0])
				if not gpGrip.is_empty():
					gpCtx.gpAnno.gpStartGripDrag(gpGrip)
					return true
			if gpShift:
				if gpCv.gpShapeSel.has(gpSh):
					gpCv.gpShapeSel.erase(gpSh)
				else:
					gpCv.gpShapeSel.append(gpSh)
			elif not gpCv.gpShapeSel.has(gpSh):
				gpCv.gpShapeSel = [gpSh]
				gpCv.gpSetSelection([])
			gpCv.queue_redraw()
			# Begin a whole-shape move, replaying rigidly from the start snapshot.
			# 从此图形开始整体移动，由起始快照无漂移重放。
			# M3: the drag snapshot now lives in GPAnnotationEditor — one port call replaces four
			# writes into canvas internals.
			# M3：拖拽快照现由 GPAnnotationEditor 持有——一次端口调用取代四次写画布内部字段。
			gpCtx.gpAnno.gpStartShapeDrag(gpSh, gpWorld)
			return true
		# Empty space: clear selection and start a marquee.
		# 空白处：清空选择并开始框选。
		if not gpShift:
			gpCv.gpSetSelection([])
			gpCv.gpShapeSel.clear()
		var gpScreen: Vector2 = gpCv.gpScreenFromWorld(gpWorld)
		_gpMarq.gpBegin(gpScreen, gpShift)
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()
	return true


func gpOnRelease(gpWorld: Vector2) -> bool:
	var gpCv := gpCtx.gpCv
	# Finish a marquee: gpFinish() reports whether the band was dragged far enough to be a real
	# marquee; a press/release without movement is a plain click, already handled on press.
	# gpFinish() 报告选框是否被拖到足以构成真正的框选；未产生位移的按下/释放只是普通单击。
	if _gpMarq.gpActive:
		if _gpMarq.gpFinish():
			_gpCommitMarquee()
		gpCv.queue_redraw()
		gpCv.gpEmitStatus()
		return true
	# Finish a group drag. Geometry was mutated live for feedback; to make the move undoable
	# we rewind every node to its pre-drag position and let the command re-apply the SAME
	# delta — one undo step per drag, never applied twice.
	# 结束整组拖拽。几何此前为实时反馈已被改写；为使这次移动可撤销，先把每个节点回退到拖拽前
	# 位置，再由命令重新应用「同一位移量」——每次拖拽合成一个撤销步，且绝不会被叠加两次。
	if _gpDragId != "":
		_gpDragId = ""
		var gpIds: Array[String] = []
		var gpDelta: Vector2 = gpWorld - _gpDragStartWorld
		for gpId in _gpDragOrigins.keys():
			var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
			if gpN == null:
				continue
			gpN.gpPosition = (_gpDragOrigins[gpId] as Vector2)
			gpIds.append(gpId)
		gpCv.gpRequestMoveNodes(gpIds, gpDelta)
		_gpDragOrigins.clear()
		gpCv.gpGraphChanged.emit()
		gpCv.queue_redraw()
		gpCv.gpEmitStatus()
		return true
	return false


func gpOnMove(gpWorld: Vector2) -> bool:
	var gpCv := gpCtx.gpCv
	# Live group-drag: the canvas forwards the motion to the active tool now that drag state
	# lives here (M3). Return true so the canvas accepts the event instead of only redrawing.
	# M3：拖拽状态已迁至本工具，画布把移动事件转发到活动工具。返回 true 使画布接受事件而非仅重绘。
	if gpIsDragging():
		gpOnDragMove(gpCv.gpScreenFromWorld(gpWorld))
		return true
	# Connect-preview rubber band (only meaningful while connecting). Not consumed: the canvas
	# redraws but must not swallow the motion event.
	# 连接预览橡皮筋（仅连线时有效）。不消费事件：画布重绘但不吞掉移动事件。
	if gpCv.gpMode == GPMode.GP_CONNECT and gpCv.gpConnectFrom != "":
		gpCv.queue_redraw()
		return false
	return false


func gpOnKey(gpKey: InputEventKey) -> bool:
	return false


# ============================ private ============================

# Apply the finished marquee to the selection set. Moved from the canvas (M3): the rule lives in
# GPCanvasMarquee so the band the user sees and the set that gets picked can never disagree.
# 把完成的框选应用到选择集。由画布迁来（M3）：判据位于 GPCanvasMarquee，故用户看到的选框与最终
# 选中的集合永不会分歧。
func _gpCommitMarquee() -> void:
	var gpCv := gpCtx.gpCv
	var gpA: Vector2 = gpCv.gpWorldFromScreen(_gpMarq.gpFrom)
	var gpB: Vector2 = gpCv.gpWorldFromScreen(_gpMarq.gpTo)
	var gpRect: Rect2 = Rect2(gpA.min(gpB), (gpA - gpB).abs())
	# Left -> right is WINDOW (enclose); right -> left is CROSSING (touch). Same predicate the
	# drawer used for the band colour, so what you see is what you get.
	# 左→右为窗口（完全包含）；右→左为交叉（碰到即可）。与绘制选框颜色所用的同一判据，所见即所得。
	var gpWindow: bool = _gpMarq.gpIsWindow()
	var gpPicked: Array[String] = []
	for gpN in gpCv.gpGraph.gpNodes:
		if GPCanvasMarquee.gpPicks(gpWindow, gpRect, gpCv.gpNodeRect(gpN.gpInstanceId)):
			gpPicked.append(gpN.gpInstanceId)
	# Annotation shapes are selected by the same marquee (Window/Crossing) rule.
	# 注释图形按相同的框选（包含/相交）规则被选中。
	var gpShapePicked: Array[int] = []
	for gpI in range(gpCv.gpGraph.gpShapes.size()):
		if GPCanvasMarquee.gpPicks(gpWindow, gpRect, gpCv.gpGraph.gpShapes[gpI].gpBBox()):
			gpShapePicked.append(gpI)
	if _gpMarq.gpAdditive:
		for gpId in gpPicked:
			if not gpCv.gpSelection.has(gpId):
				gpCv.gpSelection.append(gpId)
		gpCv.gpSetSelection(gpCv.gpSelection)
		for gpI in gpShapePicked:
			if not gpCv.gpShapeSel.has(gpI):
				gpCv.gpShapeSel.append(gpI)
	else:
		gpCv.gpSetSelection(gpPicked)
		gpCv.gpShapeSel = gpShapePicked
	gpCv.queue_redraw()
