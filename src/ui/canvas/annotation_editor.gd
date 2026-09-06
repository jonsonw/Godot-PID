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
# the grip/vertex edits mutate gpGraph.gpShapes IN PLACE and emit gpGraphChanged, and they share
# the canvas's transient drag state (_gpGripDrag / _gpShapeDragIdx / _gpShapeDragStart /
# _gpShapeDragOrigPts). Keeping the canvas as the single state owner and delegating the verb logic
# here preserves the exact ordering of emit/redraw/status that the original code relied on.
# 锚点 / 顶点编辑就地改写 gpGraph.gpShapes 并发出 gpGraphChanged，且共用画布的瞬态拖拽状态
# （_gpGripDrag / _gpShapeDragIdx / _gpShapeDragStart / _gpShapeDragOrigPts）。让画布作为唯一状态
# 持有者、此处只委派「动词逻辑」，可精确保留原代码所依赖的 emit/重绘/状态 顺序。

# The canvas we edit on (also the owner of the transient drag state we read/write).
# 被编辑的画布（也是我们所读写瞬态拖拽状态的持有者）。
var gpCv: GPCanvas2D


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


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
	gpCv._gpGripDrag = gpGrip.duplicate()
	gpCv._gpShapeDragIdx = -1
	gpCv.queue_redraw()


# Live-update the shape geometry while a grip is being dragged.
# 拖拽锚点期间实时更新图形几何。
func gpOnGripMove(gpWorld: Vector2) -> void:
	if gpCv._gpGripDrag.is_empty():
		return
	var gpIdx: int = int(gpCv._gpGripDrag["shape"])
	if gpIdx < 0 or gpIdx >= gpCv.gpGraph.gpShapes.size():
		return
	var gpS: GPShape = gpCv.gpGraph.gpShapes[gpIdx]
	# Delegate the geometry mutation to the shared grip editor (same code as the symbol editor).
	# 几何改写委托给共用的锚点编辑器（与符号编辑器同一份代码）。
	GPShapeGripEditor.gpApplyGrip(gpS, gpCv._gpGripDrag, gpWorld)
	gpCv.queue_redraw()
	gpCv._gpEmitStatus()


# Live-update a whole-shape move by replaying from the start snapshot.
# 由起始快照重放，实时更新整枚图形的移动。
func gpOnShapeMove(gpWorld: Vector2) -> void:
	if gpCv._gpShapeDragIdx < 0 or gpCv._gpShapeDragIdx >= gpCv.gpGraph.gpShapes.size():
		return
	var gpDelta: Vector2 = gpWorld - gpCv._gpShapeDragStart
	var gpS: GPShape = gpCv.gpGraph.gpShapes[gpCv._gpShapeDragIdx]
	gpS.gpPoints = GPGeometry.gpShiftPoints(gpCv._gpShapeDragOrigPts, gpDelta)
	# Circle radius is independent of translation (stored separately in gpRadius).
	# 圆的半径与平移无关（单独存于 gpRadius）。
	gpCv.queue_redraw()
	gpCv._gpEmitStatus()


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
	gpCv._gpEmitStatus()


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
	gpCv._gpEmitStatus()


# Delete vertex gpGi of the selected polyline. When only two vertices remain, deleting one would
# leave a single, non-drawable point — so we delete the whole polyline instead.
# 删除选中折线的顶点 gpGi。当只剩两个顶点时，删除其一将留下无法绘制的单点，故改为删除整条折线。
func gpRemoveVertex(gpShape: GPShape, gpGi: int) -> void:
	if gpShape == null or (gpShape.gpKind != GPShape.GPKind.GP_POLYLINE and gpShape.gpKind != GPShape.GPKind.GP_LINE):
		return
	if gpShape.gpPoints.size() <= 2:
		gpCv._gpDeleteSelected()
		return
	gpShape.gpRemoveVertex(gpGi)
	gpCv.queue_redraw()
	gpCv.gpGraphChanged.emit()
	gpCv._gpEmitStatus()


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
