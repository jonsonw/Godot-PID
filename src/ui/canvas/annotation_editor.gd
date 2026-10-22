class_name GPAnnotationEditor
extends RefCounted

# Annotation-shape editing for GPCanvas2D : grip drag / whole-shape move, polyline
# vertex + Bézier-handle editing, and "promote shapes into a symbol". These used to live inline
# in GPCanvas2D (the 1,640-line god-object). They are pure orchestration over the canvas's live
# graph + transient drag state, so moving them here is a relocation with no behaviour change.
# 主画布的注释图形编辑：锚点拖拽 / 整枚图形移动、折线顶点 + 贝塞尔手柄编辑，以及
# 「把图形提升为图元」。这些原本内联在 GPCanvas2D（1640 行上帝对象）中。它们只是对画布实时图与
# 瞬态拖拽状态的编排，故移至此文件属纯搬迁，行为零变更。
#
# Why a canvas delegate (not a free-standing pure module) / 为何是画布委托（而非独立纯模块）：
# grip/vertex edits mutate gpGraph.gpShapes() IN PLACE and emit gpGraphChanged, so they still need
# the canvas to redraw and broadcast. M3 change: the transient drag state itself now lives HERE
# tool executes it, the canvas dispatches on it, and this editor consumes it) — the one party that
# actually USES the data is this editor, so it now owns it and exposes start/move/end/query instead.
# 锚点 / 顶点编辑就地改写 gpGraph.gpShapes() 并发出 gpGraphChanged，故仍需画布重绘与广播。
# M3 变更：瞬态拖拽状态本身改由本类持有而非画布。此前它由四方共享（选择工具发起、抓取工具执行、
# 画布据此分派、本编辑器消费）——真正「使用」这些数据的一方是本编辑器，故由它持有，并对外暴露
# 开始 / 移动 / 结束 / 查询 四类操作，而非把内部字段敞开。

# The canvas we edit on. / 被编辑的画布。
var gpCv: GPCanvas2D

# Active grip (handle) drag: {"shape": int, "role": int, "idx": int}; empty dict = none.
# 进行中的锚点（手柄）拖拽：{"shape": 下标, "role": 角色, "idx": 顶点/角点序号}；空字典表示无。
var _gpGrip: Dictionary = {}

# Index of the annotation shape being moved as a whole (-1 = none).
# 正被整体移动的注释图形下标（-1 表示无）。
var _gpShapeIdx: int = -1

# Snapshot of every edge end that referenced the dragged TEXT note, taken at drag start so the
# release can either commit the follow or restore-then-convert with a correct undo image.
# 拖拽**文字**注记起始时，对每个引用它的边端拍快照：松手时或提交跟随，或先回退再转换 ——
# 两种做法都要有正确的撤销镜像。
var _gpNoteEdgeBefore: Array[Dictionary] = []

# World position where the whole-shape move started (to measure the drag delta).
# 整体移动开始时的世界坐标（用于测量拖拽位移）。
var _gpShapeStart: Vector2 = Vector2.ZERO

# Snapshot of the dragged shape's points at drag start, so the move replays rigidly with no drift.
# 拖拽开始时图形点位的快照，使整体移动无漂移地重放。
var _gpShapeOrigPts: PackedVector2Array = PackedVector2Array()


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# True while either a grip drag or a whole-shape move is in flight.
# 锚点拖拽或整图形移动正在进行时返回真。
func gpIsDragging() -> bool:
	return (not _gpGrip.is_empty()) or _gpShapeIdx >= 0


func gpHasGripDrag() -> bool:
	return not _gpGrip.is_empty()


func gpHasShapeDrag() -> bool:
	return _gpShapeIdx >= 0


# Abandon any in-flight drag without applying anything (ESC / cancel path).
# 放弃进行中的拖拽，不应用任何改动（ESC / 取消路径）。
func gpEndDrag() -> void:
	_gpGrip = {}
	_gpShapeIdx = -1
	_gpShapeOrigPts = PackedVector2Array()


# Return the grip under the world point (within screen-tolerant distance), or an empty dict.
# 返回世界坐标点下的锚点（在屏幕容差距离内），未命中返回空字典。
func gpHitGrip(gpWorld: Vector2, gpShapeIdx: int) -> Dictionary:
	if gpShapeIdx < 0 or gpShapeIdx >= gpCv.gpGraph.gpShapes.size():
		return {}
	var gpTol: float = 6.0 / gpCv.gpViewZoom
	for gpG in GPShapeGripEditor.gpGrips(gpCv.gpGraph.gpShapes[gpShapeIdx]):
		if gpWorld.distance_to(gpG["pos"]) <= gpTol:
 # Tag the hit grip with its owning shape index so the drag can address the model.
 # 给命中的锚点标注所属图形下标，使拖拽能定位到模型。
			var gpRes: Dictionary = gpG.duplicate()
			gpRes["shape"] = gpShapeIdx
			return gpRes
	return {}


# Begin dragging the given grip (clears any whole-shape move so only the grip acts).
# 开始拖拽给定锚点（清除整图形移动，使仅锚点生效）。
func gpStartGripDrag(gpGrip: Dictionary) -> void:
	_gpGrip = gpGrip.duplicate()
	_gpShapeIdx = -1
	gpCv.queue_redraw()


# [param gpShapeIdx] index into gpGraph.gpShapes() / gpGraph.gpShapes() 中的下标。
# [param gpWorld] world position of the press, used to measure the delta / 按下处的世界坐标，用于测量位移。
func gpStartShapeDrag(gpShapeIdx: int, gpWorld: Vector2) -> void:
	# Snapshot the referencing ends BEFORE anything moves (only for text notes).
	# 在一切移动**之前**拍下引用端（仅文字注记）。
	_gpNoteEdgeBefore.clear()
	if gpCv.gpGraph != null and gpShapeIdx >= 0 and gpShapeIdx < gpCv.gpGraph.gpShapes.size():
		var gpS0: GPShape = gpCv.gpGraph.gpShapes[gpShapeIdx]
		if gpS0 != null and gpS0.gpKind == GPShape.GPKind.GP_TEXT and gpS0.gpUid != "":
			for gpE0 in gpCv.gpGraph.gpEdges:
				if gpE0 == null:
					continue
				for gpIsFrom0 in [true, false]:
					if gpE0.gpEndNoteUid(gpIsFrom0) == gpS0.gpUid:
						_gpNoteEdgeBefore.append({
							"edge_id": gpE0.gpInstanceId,
							"is_from": gpIsFrom0,
							"ref_from": gpE0.gpFromRef.duplicate(true),
							"ref_to": gpE0.gpToRef.duplicate(true),
						})
	gpEndDrag()
	if gpShapeIdx < 0 or gpShapeIdx >= gpCv.gpGraph.gpShapes.size():
		return
	_gpShapeIdx = gpShapeIdx
	_gpShapeStart = gpWorld
	_gpShapeOrigPts = gpCv.gpGraph.gpShapes[gpShapeIdx].gpPoints.duplicate()


# Finish a grip drag / whole-shape move. Geometry was already mutated live during the drag, so
func gpEndGripDrag() -> void:
	_gpGrip = {}


# The port a dropped note should convert to: the closest anchor under EITHER the cursor or the
# note's own glyph, within a generous radius.
# 被丢下的注记该转成哪个端口：光标处**或**注记字形处最近的锚点，且用较宽松的半径。
# WHY not just the cursor point / 为何不只看光标点：
# the user drops the TEXT onto a nozzle, so the cursor often sits at the middle of the word while the
# nozzle is at its corner. Testing only the cursor made a visually-correct drop silently fail — the
# text stayed and the line never connected, which is exactly the reported bug.
# 用户是把**文字**丢到管嘴上的，光标常停在词中间而管嘴在它的角上。只测光标会让一次「看起来对」的
# 放下静默失败 —— 文字留下、线没接上，正是被报告的这个 bug。
func _gpPortUnderNote(gpS: GPShape, gpWorld: Vector2) -> Dictionary:
	if gpCv.gpGraph == null:
		return {}
	var gpAnchors: Array[Dictionary] = GPPortAnchor.gpAnchors(gpCv.gpGraph,
		gpCv.gpDefLookupCallable(), [])
	if gpAnchors.is_empty():
		return {}
	# Candidate points: where the user let go, the note's anchor, and the middle of its glyph.
	# 候选点：松手处、注记锚点、字形中心。
	var gpPts: Array[Vector2] = [gpWorld]
	if gpS.gpPoints.size() >= 1:
		gpPts.append(gpS.gpPoints[0])
		gpPts.append(gpS.gpBBox().get_center())
	# Generous radius: 18 screen pixels, so a drop that LOOKS on the nozzle counts.
	# 宽松半径：18 屏幕像素，使「看起来压住了管嘴」的放下也算。
	var gpR: float = 18.0 / maxf(gpCv.gpViewZoom, 0.01)
	var gpBest: Dictionary = {}
	var gpBestD: float = gpR
	for gpA in gpAnchors:
		var gpPos: Vector2 = gpA.get("pos", Vector2.ZERO)
		for gpP in gpPts:
			var gpD: float = gpPos.distance_to(gpP)
			if gpD < gpBestD:
				gpBestD = gpD
				gpBest = gpA
	return gpBest


# Move every referencing edge end onto the note's current anchor (live, during the drag).
# 把每个引用该注记的边端移到注记当前锚点上（拖拽期间实时）。
func _gpSyncNoteEdges(gpS: GPShape) -> void:
	if gpCv.gpGraph == null or gpS.gpPoints.is_empty():
		return
	var gpAnchor: Vector2 = gpS.gpPoints[0]
	var gpChanged: bool = false
	for gpE in gpCv.gpGraph.gpEdges:
		if gpE == null:
			continue
		for gpIsFrom in [true, false]:
			if gpE.gpEndNoteUid(gpIsFrom) != gpS.gpUid:
				continue
			if not gpE.gpIsDangling(gpIsFrom):
				continue
			gpE.gpSetDanglingPoint(gpIsFrom, gpAnchor)
			gpChanged = true
	if gpChanged:
		# THE REPAINT. Mutating the ref dictionary changes the MODEL, but the edge VIEW re-syncs on
		# this signal — without it the line stays behind while the text moves.
		# **重绘信号**。改引用字典只改**模型**，而边的**视图**在这个信号上重新同步 ——
		# 缺了它，文字在动、线不动。
		gpCv.gpGraph.gpGraphChanged.emit()


# Restore the note position and the referencing ends from the drag-start snapshot.
# 从拖拽起始快照恢复注记位置与各引用端。
func _gpRestoreNoteDrag(gpS: GPShape) -> void:
	for gpT in _gpNoteEdgeBefore:
		var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(str(gpT.get("edge_id", "")))
		if gpE == null:
			continue
		gpE.gpFromRef = (gpT.get("ref_from", {}) as Dictionary).duplicate(true)
		gpE.gpToRef = (gpT.get("ref_to", {}) as Dictionary).duplicate(true)
	if gpS != null and not _gpShapeOrigPts.is_empty():
		gpS.gpPoints = _gpShapeOrigPts.duplicate()
	_gpNoteEdgeBefore.clear()


# Finish a whole-shape move. gpWorld is where the user released (Vector2.INF when unknown).
# 结束整图形移动。gpWorld 是用户松手处的世界坐标（未知时为 Vector2.INF）。
# A TEXT note dropped onto a nozzle is CONVERTED to a connection: that gesture means "this open end
# is now wired", so the line and the note must change together (see GPConvertNoteToPortCommand).
# 落到管嘴上的**文字**注记会被**转换**为连线：该手势的意思是「这个开口端现在接上了」，
# 故线与注记必须一起变（见 GPConvertNoteToPortCommand）。
func gpEndShapeDrag(gpWorld: Vector2 = Vector2.INF) -> void:
	var gpIdx: int = _gpShapeIdx
	if gpIdx >= 0 and gpIdx < gpCv.gpGraph.gpShapes.size():
		var gpS: GPShape = gpCv.gpGraph.gpShapes[gpIdx]
		if gpS != null and gpS.gpKind == GPShape.GPKind.GP_TEXT and gpS.gpUid != "":
			var gpPort: Dictionary = {}
			if gpWorld != Vector2.INF:
				gpPort = _gpPortUnderNote(gpS, gpWorld)
			if not gpPort.is_empty():
				# Conversion must record the ORIGINAL end refs for undo, so rewind the live drag
				# first and let ONE command own the whole gesture.
				# 转换要为撤销记录**原始**端引用，故先把实时拖拽回退，再由**一条**命令接管整个手势。
				_gpRestoreNoteDrag(gpS)
				gpCv.gpRequestConvertNoteToPort(gpS.gpUid, gpPort)
			else:
				# No port under the release: the note stays, and the line stays with it.
				# 松手处没有端口：注记留下，连线也跟着留下。
				_gpNoteEdgeBefore.clear()
	# The drag is over: the hover ring must not linger.
	# 拖拽结束：悬停环不得残留。
	gpCv.gpHoverPort = {}
	gpCv.queue_redraw()
	_gpShapeIdx = -1
	_gpShapeOrigPts = PackedVector2Array()


# Live-update the shape geometry while a grip is being dragged.
# 拖拽锚点期间实时更新图形几何。
func gpOnGripMove(gpWorld: Vector2) -> void:
	if _gpGrip.is_empty():
		return
	var gpIdx: int = int(_gpGrip["shape"])
	if gpIdx < 0 or gpIdx >= gpCv.gpGraph.gpShapes.size():
		return
	var gpS: GPShape = gpCv.gpGraph.gpShapes[gpIdx]
	# Delegate the geometry mutation to the shared grip editor (same code as the symbol editor).
	# 几何改写委托给共用的锚点编辑器（与符号编辑器同一份代码）。
	GPShapeGripEditor.gpApplyGrip(gpS, _gpGrip, gpWorld)
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()


# Live-update a whole-shape move by replaying from the start snapshot.
# 由起始快照重放，实时更新整枚图形的移动。
func gpOnShapeMove(gpWorld: Vector2) -> void:
	if _gpShapeIdx < 0 or _gpShapeIdx >= gpCv.gpGraph.gpShapes.size():
		return
	var gpDelta: Vector2 = gpWorld - _gpShapeStart
	var gpS: GPShape = gpCv.gpGraph.gpShapes[_gpShapeIdx]
	gpS.gpPoints = GPGeometry.gpShiftPoints(_gpShapeOrigPts, gpDelta)
	# A text note's line FOLLOWS the text: the edge end that referenced the note tracks its anchor,
	# otherwise dragging the text would leave the pipe pointing at nothing (the tooltip says "this
	# end is TO ATM" while the end sits somewhere else).
	# 文字注记的连线**跟随**文字：引用该注记的边端跟踪它的锚点，否则拖动文字会留下一条指着虚无的管线
	#（注记写着「此端 TO ATM」，而端头却在别处）。
	if gpS.gpKind == GPShape.GPKind.GP_TEXT and gpS.gpUid != "":
		_gpSyncNoteEdges(gpS)
		# HIGHLIGHT the port the note is over, so "it will connect here" is visible before release.
		# **高亮**注记正压着的端口，使「松手就接这里」在松手前可见。
		gpCv.gpHoverPort = _gpPortUnderNote(gpS, gpS.gpPoints[0])
		gpCv.queue_redraw()
	# Circle radius is independent of translation (stored separately in gpRadius).
	# 圆的半径与平移无关（单独存于 gpRadius）。
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()


# The single selected annotation shape, or null when zero / many are selected. Returns null unless
# exactly one shape is picked, because vertex editing targets one polyline at a time.
# 单选时返回那枚注释图形；零选 / 多选返回 null。顶点编辑一次只作用于一条折线，故要求严格单选。
func gpSingleSelectedShape() -> GPShape:
	if gpCv.gpShapeSel.size() != 1:
		return null
	var gpIdx: int = gpCv.gpShapeSel[0]
	if gpIdx < 0 or gpIdx >= gpCv.gpGraph.gpShapes.size():
		return null
	return gpCv.gpGraph.gpShapes[gpIdx]


# Whether vertex gpGi of gpShape currently has any Bézier handle pulled out.
# gpShape 的顶点 gpGi 当前是否有被拉出的贝塞尔手柄。
func gpVertexHasHandles(gpShape: GPShape, gpGi: int) -> bool:
	if gpGi < 0 or gpGi >= gpShape.gpHandles.size():
		return false
	if gpShape.gpHandles[gpGi].size() < 2:
		return false
	return (not gpShape.gpHandles[gpGi][0].is_equal_approx(Vector2.ZERO)) or (not gpShape.gpHandles[gpGi][1].is_equal_approx(Vector2.ZERO))


# Collapse both handles of vertex gpGi back onto the vertex (making it a corner node).
# 把顶点 gpGi 的两侧手柄塌缩回顶点自身（使其成为拐角节点）。
func gpCollapseHandles(gpShape: GPShape, gpGi: int) -> void:
	if gpShape == null or gpGi < 0 or gpGi >= gpShape.gpPoints.size():
		return
	gpShape.gpEnsureHandles()
	gpShape.gpHandles[gpGi] = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	gpCv.queue_redraw()
	gpCv.gpGraphChanged.emit()
	gpCv.gpEmitStatus()


# Pull BOTH Bézier handles out of vertex gpGi (AutoCAD-style "convert to smooth node"). The handles
# are seeded along the average direction of the neighbouring vertices so the curve appears at once.
# 从顶点 gpGi 拉出两侧贝塞尔手柄（AutoCAD 风格「转为平滑节点」）。手柄沿相邻顶点的平均方向初始化，
# 使曲线立即显现。
func gpPullHandles(gpShape: GPShape, gpGi: int) -> void:
	if gpShape == null or (gpShape.gpKind != GPShape.GPKind.GP_POLYLINE and gpShape.gpKind != GPShape.GPKind.GP_LINE):
		return
	if gpGi < 0 or gpGi >= gpShape.gpPoints.size():
		return
	gpShape.gpEnsureHandles()
	var gpN: int = gpShape.gpPoints.size()
	var gpPrev: Vector2 = gpShape.gpPoints[gpGi]
	var gpNext: Vector2 = gpShape.gpPoints[gpGi]
	if gpGi > 0:
		gpPrev = gpShape.gpPoints[gpGi - 1]
	elif gpShape.gpClosed and gpN >= 2:
		gpPrev = gpShape.gpPoints[gpN - 1]
	if gpGi + 1 < gpN:
		gpNext = gpShape.gpPoints[gpGi + 1]
	elif gpShape.gpClosed and gpN >= 2:
		gpNext = gpShape.gpPoints[0]
	var gpHere: Vector2 = gpShape.gpPoints[gpGi]
	var gpDir: Vector2 = gpNext - gpPrev
	if gpDir.length_squared() < 1e-6:
		gpDir = Vector2(1.0, 0.0)
	gpDir = gpDir.normalized()
	var gpK: float = 0.3 * (gpNext - gpPrev).length()
	if gpK < 8.0:
		gpK = 8.0
	gpShape.gpSetHandle(gpGi, 0, gpHere - gpDir * gpK)
	gpShape.gpSetHandle(gpGi, 1, gpHere + gpDir * gpK)
	gpCv.queue_redraw()
	gpCv.gpGraphChanged.emit()
	gpCv.gpEmitStatus()


# Delete vertex gpGi of the selected polyline. When only two vertices remain, deleting one would
# leave a single, non-drawable point — so we delete the whole polyline instead.
# 删除选中折线的顶点 gpGi。当只剩两个顶点时，删除其一将留下无法绘制的单点，故改为删除整条折线。
func gpRemoveVertex(gpShape: GPShape, gpGi: int) -> void:
	if gpShape == null or (gpShape.gpKind != GPShape.GPKind.GP_POLYLINE and gpShape.gpKind != GPShape.GPKind.GP_LINE):
		return
	if gpShape.gpPoints.size() <= 2:
		gpCv.gpRequestDeleteSelected()
		return
	gpShape.gpRemoveVertex(gpGi)
	gpCv.queue_redraw()
	gpCv.gpGraphChanged.emit()
	gpCv.gpEmitStatus()


# Double-click a grip of the single selected annotation polyline: toggle that vertex between a
# corner node (handles collapsed) and a smooth node (handles pulled out). Double-clicking a handle
# grip collapses it. Returns true when the gesture was consumed.
# 双击「单选注释折线」的一个抓取点：在拐角（手柄塌缩）与平滑（手柄拉出）间切换。双击手柄抓取点则塌缩。
# 手势被消费时返回 true。
func gpOnShapeGripDoubleClick(gpWorld: Vector2) -> bool:
	var gpShape: GPShape = gpSingleSelectedShape()
	if gpShape == null or (gpShape.gpKind != GPShape.GPKind.GP_POLYLINE and gpShape.gpKind != GPShape.GPKind.GP_LINE):
		return false
	var gpGrip: Dictionary = gpHitGrip(gpWorld, gpCv.gpShapeSel[0])
	if gpGrip.is_empty():
		return false
	var gpRole: int = int(gpGrip["role"])
	var gpGi: int = int(gpGrip["gi"])
	if gpRole == GPShapeGripEditor.GP_GRIP_VERTEX:
		if gpVertexHasHandles(gpShape, gpGi):
			gpCollapseHandles(gpShape, gpGi)
		else:
			gpPullHandles(gpShape, gpGi)
		return true
	if gpRole == GPShapeGripEditor.GP_GRIP_HANDLE_IN or gpRole == GPShapeGripEditor.GP_GRIP_HANDLE_OUT:
		gpCollapseHandles(gpShape, gpGi)
		return true
	return false


# The vertex grip (as a grip dict) under gpWorld for the single selected annotation polyline, or an
# empty dict. Used by the right-click menu to offer vertex-only actions when the cursor sits on a
# vertex grip of that polyline.
# gpWorld 下「单选注释折线」的顶点抓取点（以抓取点字典形式），未命中返回空字典。右键菜单据此在光标
# 位于折线顶点抓取点上时提供仅针对顶点的操作。
func gpHitPolylineVertexGrip(gpWorld: Vector2) -> Dictionary:
	var gpShape: GPShape = gpSingleSelectedShape()
	if gpShape == null or (gpShape.gpKind != GPShape.GPKind.GP_POLYLINE and gpShape.gpKind != GPShape.GPKind.GP_LINE):
		return {}
	var gpGrip: Dictionary = gpHitGrip(gpWorld, gpCv.gpShapeSel[0])
	if gpGrip.is_empty():
		return {}
	if int(gpGrip["role"]) != GPShapeGripEditor.GP_GRIP_VERTEX:
		return {}
	return gpGrip


# Convert selected annotation shapes into an author-space shape dict (paths / circles / rects)
# for the isolation editor. All geometry is shifted so the combined bbox top-left is at the
# origin — GPSymbolNormalizer only keeps RELATIVE geometry, so absolute position is irrelevant.
# 把选中的注释图形转成作者空间形状字典（paths / circles / rects）供隔离编辑器使用。
# 所有几何都平移到「包围盒左上角位于原点」——GPSymbolNormalizer 只保留相对几何，绝对位置无关紧要。
func gpShapesToDraft(gpShapes: Array[GPShape]) -> Dictionary:
	var gpMin := Vector2(INF, INF)
	for gpS in gpShapes:
		var gpB: Rect2 = gpS.gpBBox()
		gpMin = gpMin.min(gpB.position)
	var gpPaths: Array = []
	var gpCircles: Array = []
	var gpRects: Array = []
	# A15: arcs used to be DROPPED here without a word — the user selected three primitives, got
	# two, and nothing said why. They now travel as center + radius + sweep, the same keys
	# GPShapeSpec.gpEditSpec() emits, so the dialog rehydrates them losslessly.
	# A15：圆弧此前在此被**无声丢弃** —— 用户选中三个基元却只过去两个，且无人解释。现在它们以
	# 圆心 + 半径 + 扫掠角随行，键与 GPShapeSpec.gpEditSpec() 完全一致，故对话框能无损还原。
	var gpArcs: Array = []
	for gpS in gpShapes:
		match gpS.gpKind:
			GPShape.GPKind.GP_LINE:
				if gpS.gpPoints.size() >= 2:
					gpPaths.append({
						"pts": [
							[gpS.gpPoints[0].x - gpMin.x, gpS.gpPoints[0].y - gpMin.y],
							[gpS.gpPoints[1].x - gpMin.x, gpS.gpPoints[1].y - gpMin.y],
						],
						"closed": false,
 # Carry Bézier handles (relative offsets) so a curved spline survives promotion.
 # Relative offsets are translation-invariant, so -gpMin does not affect them.
 # 携带贝塞尔手柄（相对偏移），使曲线样条经提升后仍可继续编辑；相对偏移与平移无关。
						"handles": GPShapeSpec.gpEmitHandles(gpS),
					})
			GPShape.GPKind.GP_POLYLINE:
				var gpPts: Array = []
				for gpP in gpS.gpPoints:
					gpPts.append([gpP.x - gpMin.x, gpP.y - gpMin.y])
				var gpPathD: Dictionary = {"pts": gpPts, "closed": gpS.gpClosed}
 # Preserve Bézier handles so a curved polyline is not flattened on promotion.
 # 保留贝塞尔手柄，避免曲线折线在提升时被展平。
				gpPathD["handles"] = GPShapeSpec.gpEmitHandles(gpS)
				gpPaths.append(gpPathD)
			GPShape.GPKind.GP_CIRCLE:
				if gpS.gpPoints.size() >= 1:
					gpCircles.append({"c": [gpS.gpPoints[0].x - gpMin.x, gpS.gpPoints[0].y - gpMin.y], "r": gpS.gpRadius})
			GPShape.GPKind.GP_RECT:
				if gpS.gpPoints.size() >= 2:
					var gpR: Rect2 = Rect2(gpS.gpPoints[0], (gpS.gpPoints[1] - gpS.gpPoints[0]).abs())
					gpRects.append({"pos": [gpR.position.x - gpMin.x, gpR.position.y - gpMin.y], "size": [gpR.size.x, gpR.size.y]})
			GPShape.GPKind.GP_ARC:
				if gpS.gpPoints.size() >= 3 and gpS.gpRadius > 0.0:
					var gpAng: Dictionary = gpS.gpArcAngles()
					var gpC: Vector2 = gpS.gpArcCenter()
					gpArcs.append({
						"c": [gpC.x - gpMin.x, gpC.y - gpMin.y],
						"r": gpS.gpRadius,
						"a0": gpAng["a0"],
						"a1": gpAng["a1"],
					})
			_:
				# A kind this builder does not know: SAY SO instead of silently shrinking the
				# selection. A silent drop is indistinguishable from a bug in the user's eyes.
				# 本构建器不认识的种类：**说出来**，而不是静默缩小选区。静默丢弃在用户眼里与 bug 无异。
				push_warning("gpShapesToDraft: unsupported shape kind %d skipped" % gpS.gpKind)
	return {"paths": gpPaths, "circles": gpCircles, "rects": gpRects, "arcs": gpArcs}


# Promote the selected annotation shapes into a real symbol: emit the geometry dict so the
# host opens the isolation editor pre-loaded with the same drawing.
# 把选中的注释图形提升为真正的图元：发射几何字典，使宿主打开已预装相同图形的隔离编辑器。
func gpMakeSymbolFromShapes() -> void:
	var gpShapes: Array[GPShape] = []
	for gpIdx in gpCv.gpShapeSel:
		if gpIdx >= 0 and gpIdx < gpCv.gpGraph.gpShapes.size():
			gpShapes.append(gpCv.gpGraph.gpShapes[gpIdx])
	if gpShapes.is_empty():
		return
	gpCv.gpMakeSymbolRequested.emit(gpShapesToDraft(gpShapes))
