# ============================================================================
# GPSelectTool — 选择 / 连线 / 框选 / 注释图形 交互（P2 拆分）
# Select / connect / marquee / annotation-shape interaction (P2 split).
#
# 持有「选择模式」下的按下 / 释放 / 移动逻辑，原 _gpOnLeftDown / _gpOnLeftUp 的对应分支已迁入
# 本类（经 gpCtx.gpCv 读写画布状态，行为零变更）。锚点 / 整图形拖拽的「执行」部分在 GPGripTool，
# 本类只负责在落空路径里发起它们。
# Owns the SELECT-mode press / release / move logic, migrated verbatim from _gpOnLeftDown /
# _gpOnLeftUp (reads/writes canvas state via gpCtx.gpCv, zero behavior change). The grip / whole-shape
# DRAG execution lives in GPGripTool; this tool only initiates it from the miss path.
# ============================================================================

class_name GPSelectTool
extends GPCanvasTool

const GPMode = GPCanvasInteractState.GPMode

func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	var gpCv := gpCtx.gpCv
	var gpHit: String = gpCv._gpHitTest(gpWorld)
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
					var gpEid: String = gpCv._gpState.gpIds.gpNext("e")
					gpCv.gpGraph.gpAddEdge(gpCv.gpGraph.gpNewEdge(gpEid, gpCv.gpConnectFrom, gpHit, {}))
					gpCv.gpGraphChanged.emit()
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
			gpCv._gpSetSelection(gpCv.gpSelection)
		elif not gpCv.gpSelection.has(gpHit):
			gpCv._gpSetSelection([gpHit])
		# Start a group drag only when the pressed node belongs to the selection.
		# 仅当按下的节点属于选择集时才开始整组拖拽。
		if gpCv.gpSelection.has(gpHit):
			gpCv._gpDragId = gpHit
			gpCv._gpDragStartWorld = gpWorld
			gpCv._gpDragOrigins.clear()
			for gpId in gpCv.gpSelection:
				var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
				if gpN != null:
					gpCv._gpDragOrigins[gpId] = gpN.gpPosition
		else:
			gpCv._gpDragId = ""
	else:
		# Double-clicking a vertex / handle grip of the single selected annotation polyline toggles
		# Bézier handles (corner <-> smooth). Intercept BEFORE the hit/move logic below.
		# 双击「单选注释折线」的顶点 / 手柄抓取点：切换贝塞尔手柄（拐角 <-> 平滑）。须在下方命中/移动
		# 逻辑之前拦截。
		if gpDouble and gpCv._gpAnno.gpOnShapeGripDoubleClick(gpWorld):
			return true
		# When a single shape is selected, try to grab one of ITS grips first. A pulled-out Bézier
		# handle end often sits OUTSIDE the polyline stroke, so testing shape-line hit first would
		# miss it and fall through to a marquee — making handles appear but not draggable.
		# 当单选一枚图形时，先尝试命中它自己的抓取点。拉出的贝塞尔手柄末端常位于折线墨线之外，若先按
		# 线段命中，会漏判并落入框选——造成句柄可见却拖不动。
		if gpCv.gpShapeSel.size() == 1:
			var gpGripAny: Dictionary = gpCv._gpAnno.gpHitGrip(gpWorld, gpCv.gpShapeSel[0])
			if not gpGripAny.is_empty():
				gpCv._gpAnno.gpStartGripDrag(gpGripAny)
				return true
		# No symbol hit: try an annotation shape (grip editing has priority when one is selected).
		# 未命中图元：改试注释图形（选中一枚时锚点编辑优先）。
		var gpSh: int = gpCv._gpHitShape(gpWorld)
		if gpSh >= 0:
			if gpCv.gpShapeSel.size() == 1:
				var gpGrip: Dictionary = gpCv._gpAnno.gpHitGrip(gpWorld, gpCv.gpShapeSel[0])
				if not gpGrip.is_empty():
					gpCv._gpAnno.gpStartGripDrag(gpGrip)
					return true
			if gpShift:
				if gpCv.gpShapeSel.has(gpSh):
					gpCv.gpShapeSel.erase(gpSh)
				else:
					gpCv.gpShapeSel.append(gpSh)
			elif not gpCv.gpShapeSel.has(gpSh):
				gpCv.gpShapeSel = [gpSh]
				gpCv._gpSetSelection([])
			gpCv.queue_redraw()
			# Begin a whole-shape move, replaying rigidly from the start snapshot.
			# 从此图形开始整体移动，由起始快照无漂移重放。
			gpCv._gpShapeDragIdx = gpSh
			gpCv._gpShapeDragStart = gpWorld
			if gpSh >= 0 and gpSh < gpCv.gpGraph.gpShapes.size():
				gpCv._gpShapeDragOrigPts = gpCv.gpGraph.gpShapes[gpSh].gpPoints.duplicate()
				gpCv._gpShapeDragOrigR = gpCv.gpGraph.gpShapes[gpSh].gpRadius
			return true
		# Empty space: clear selection and start a marquee.
		# 空白处：清空选择并开始框选。
		if not gpShift:
			gpCv._gpSetSelection([])
			gpCv.gpShapeSel.clear()
		var gpScreen: Vector2 = gpCv.gpScreenFromWorld(gpWorld)
		gpCv._gpMarq.gpBegin(gpScreen, gpShift)
	gpCv.queue_redraw()
	gpCv._gpEmitStatus()
	return true


func gpOnRelease(gpWorld: Vector2) -> bool:
	var gpCv := gpCtx.gpCv
	# Finish a marquee: gpFinish() reports whether the band was dragged far enough to be a real
	# marquee; a press/release without movement is a plain click, already handled on press.
	# gpFinish() 报告选框是否被拖到足以构成真正的框选；未产生位移的按下/释放只是普通单击。
	if gpCv._gpMarq.gpActive:
		if gpCv._gpMarq.gpFinish():
			gpCv._gpCommitMarquee()
		gpCv.queue_redraw()
		gpCv._gpEmitStatus()
		return true
	# Finish a group drag (geometry already mutated live during the drag).
	# 结束整组拖拽（几何已在拖拽过程中实时变更）。
	if gpCv._gpDragId != "":
		gpCv._gpDragId = ""
		gpCv._gpDragOrigins.clear()
		gpCv.gpGraphChanged.emit()
		gpCv._gpEmitStatus()
		return true
	return false


func gpOnMove(gpWorld: Vector2) -> bool:
	# Connect-preview rubber band (only meaningful while connecting). Not consumed: the canvas
	# redraws but must not swallow the motion event.
	# 连接预览橡皮筋（仅连线时有效）。不消费事件：画布重绘但不吞掉移动事件。
	var gpCv := gpCtx.gpCv
	if gpCv.gpMode == GPMode.GP_CONNECT and gpCv.gpConnectFrom != "":
		gpCv.queue_redraw()
	return false


func gpOnKey(gpKey: InputEventKey) -> bool:
	return false
