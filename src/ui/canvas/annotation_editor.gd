class_name GPAnnotationEditor
extends RefCounted

# Annotation-shape editing for GPCanvas2D (P2 split): grip drag / whole-shape move, polyline
# vertex + Bézier-handle editing, and "promote shapes into a symbol". These used to live inline
# in GPCanvas2D (the 1,640-line god-object). They are pure orchestration over the canvas's live
# graph + transient drag state, so moving them here is a relocation with no behaviour change.
# 主画布的注释图形编辑（P2 拆分）：锚点拖拽 / 整枚图形移动、折线顶点 + 贝塞尔手柄编辑，以及
# 「把图形提升为图元」。这些原本内联在 GPCanvas2D（1640 行上帝对象）中。它们只是对画布实时图与
# 瞬态拖拽状态的编排，故移至此文件属纯搬迁，行为零变更。
#
# Why a canvas delegate (not a free-standing pure module) / 为何是画布委托（而非独立纯模块）：
# grip/vertex edits mutate gpGraph.gpShapes IN PLACE and emit gpGraphChanged, so they still need
# the canvas to redraw and broadcast. M3 change: the transient drag state itself now lives HERE
# rather than on the canvas. It was previously shared by four parties (select tool starts it, grip
# tool executes it, the canvas dispatches on it, and this editor consumes it) — the one party that
# actually USES the data is this editor, so it now owns it and exposes start/move/end/query instead.
# 锚点 / 顶点编辑就地改写 gpGraph.gpShapes 并发出 gpGraphChanged，故仍需画布重绘与广播。
# M3 变更：瞬态拖拽状态本身改由本类持有而非画布。此前它由四方共享（选择工具发起、抓取工具执行、
# 画布据此分派、本编辑器消费）——真正「使用」这些数据的一方是本编辑器，故由它持有，并对外暴露
# 开始 / 移动 / 结束 / 查询 四类操作，而非把内部字段敞开。

# The canvas we edit on. / 被编辑的画布。
var gpCv: GPCanvas2D

# ---- Transient drag state owned by this editor (M3) ----
# ---- 本编辑器自持的瞬态拖拽状态（M3）----
# Active grip (handle) drag: {"shape": int, "role": int, "idx": int}; empty dict = none.
# 进行中的锚点（手柄）拖拽：{"shape": 下标, "role": 角色, "idx": 顶点/角点序号}；空字典表示无。
var _gpGrip: Dictionary = {}

# Index of the annotation shape being moved as a whole (-1 = none).
# 正被整体移动的注释图形下标（-1 表示无）。
var _gpShapeIdx: int = -1

# World position where the whole-shape move started (to measure the drag delta).
# 整体移动开始时的世界坐标（用于测量拖拽位移）。
var _gpShapeStart: Vector2 = Vector2.ZERO

# Snapshot of the dragged shape's points at drag start, so the move replays rigidly with no drift.
# 拖拽开始时图形点位的快照，使整体移动无漂移地重放。
var _gpShapeOrigPts: PackedVector2Array = PackedVector2Array()


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# ---- Drag lifecycle: the port this editor exposes to tools and the canvas (M3) ----
# ---- 拖拽生命周期：本编辑器对工具与画布暴露的端口（M3）----
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


# Begin moving a whole annotation shape, snapshotting its geometry for a rigid replay (M3).
# 开始整体移动一枚注释图形，快照其几何以便无漂移重放（M3）。
# [param gpShapeIdx] index into gpGraph.gpShapes / gpGraph.gpShapes 中的下标。
# [param gpWorld] world position of the press, used to measure the delta / 按下处的世界坐标，用于测量位移。
func gpStartShapeDrag(gpShapeIdx: int, gpWorld: Vector2) -> void:
	gpEndDrag()
	if gpShapeIdx < 0 or gpShapeIdx >= gpCv.gpGraph.gpShapes.size():
		return
	_gpShapeIdx = gpShapeIdx
	_gpShapeStart = gpWorld
	_gpShapeOrigPts = gpCv.gpGraph.gpShapes[gpShapeIdx].gpPoints.duplicate()


# Finish a grip drag / whole-shape move. Geometry was already mutated live during the drag, so
# there is nothing to apply here — only the transient state is released (M3).
# 结束锚点拖拽 / 整图形移动。几何已在拖拽过程中实时变更，故此处无需应用改动，只释放瞬态状态（M3）。
func gpEndGripDrag() -> void:
	_gpGrip = {}


func gpEndShapeDrag() -> void:
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
	return {"paths": gpPaths, "circles": gpCircles, "rects": gpRects}


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
