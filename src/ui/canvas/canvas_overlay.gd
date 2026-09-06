class_name GPCanvasOverlay
extends RefCounted

# Drawing layer for GPCanvas2D. Owns NO state of its own — it reads the live canvas
# (a CanvasItem) and paints the background grid, annotation shapes, their grips, the
# rubber-band marquee and the connect-preview line. Splitting this out of GPCanvas2D
# (P2) keeps the Control file focused on input + orchestration; the draw math is unchanged.
# 画布绘制层。自身不持有任何状态——它读取实时画布（一个 CanvasItem）并绘制背景网格、
# 注释图形、其抓取点、橡皮筋框选与连线预览线。P2 将其从 GPCanvas2D 抽出，使 Control 文件
# 专注于输入与编排；绘制数学完全一致，行为零变更。
#
# Why a delegate instead of free functions / why the canvas reference / 为何用委托而非自由函数、为何持有画布引用：
# Godot's draw_* family is a method on CanvasItem, so the only natural home for the drawing is
# "something that has a CanvasItem". Passing the canvas in and calling gpCv.draw_* keeps the
# coordinate transform (gpScreenFromWorld) and the live drag state (_gpDrawActive / _gpPolyPts)
# in one place, so the split is a pure relocation with no behaviour change.
# Godot 的 draw_* 是 CanvasItem 的方法，绘制唯一自然的归宿是「持有 CanvasItem 的对象」。把画布传入
# 并调用 gpCv.draw_*，使坐标变换（gpScreenFromWorld）与实时拖拽状态（_gpDrawActive / _gpPolyPts）
# 仍在一处，拆分即纯搬迁，行为零变更。

# Mirror of GPCanvas2D.GPMode so the literal GPMode.GP_* spellings keep compiling here.
# 镜像 GPCanvas2D.GPMode，使本文件内的 GPMode.GP_* 写法继续编译。
const GPMode = GPCanvasInteractState.GPMode

# The canvas we draw on (also our source of live state: graph, selection, zoom, drag flags).
# 被绘制的画布（也作为实时状态的来源：图、选择、缩放、拖拽标记）。
var gpCv: CanvasItem


func _init(gpCanvas: CanvasItem) -> void:
	gpCv = gpCanvas


# Paint the whole background overlay: bg fill, grid, shapes (+ selection + grips), marquee,
# connect preview. The graph<->view sync is owned by the canvas and runs just before this.
# 绘制整片背景覆盖层：底色填充、网格、图形（含选择与抓取点）、框选、连线预览。
# 图↔视图同步由画布持有，且恰在本方法之前运行。
func gpDraw() -> void:
	gpCv.draw_rect(Rect2(Vector2.ZERO, gpCv.size), Color(0.13, 0.14, 0.18))
	_gpDrawGrid()
	_gpDrawShapes()
	_gpDrawMarquee()
	_gpDrawConnectPreview()


# Draw the rubber-band marquee. CAD convention: dragging left->right is a WINDOW (only fully
# enclosed symbols are selected, blue); right->left is a CROSSING (anything touched, green).
# 绘制橡皮筋框选框。CAD 惯例：左→右为窗口模式（仅选中完全包含的图元，蓝色）；
# 右→左为交叉模式（碰到即选中，绿色）。
func _gpDrawMarquee() -> void:
	if not gpCv._gpMarq.gpActive:
		return
	var gpRect: Rect2 = gpCv._gpMarq.gpScreenRect()
	# Direction decides both the colour here and the hit rule on commit — one rule, one owner.
	# 拖动方向同时决定此处颜色与提交时的命中规则 —— 一条规则、一个持有者。
	var gpCol: Color = gpCv._gpMarq.gpColor()
	gpCv.draw_rect(gpRect, Color(gpCol.r, gpCol.g, gpCol.b, 0.15), true)
	gpCv.draw_rect(gpRect, gpCol, false, 1.0)


# Draw the background grid aligned to the world coordinate system.
# 绘制与世界坐标系对齐的背景网格。
func _gpDrawGrid() -> void:
	var gpStep: float = 50.0 * gpCv.gpViewZoom
	if gpStep < 8.0:
		return
	var gpStartX: int = int(fmod(gpCv.gpViewOffset.x, gpStep))
	var gpStartY: int = int(fmod(gpCv.gpViewOffset.y, gpStep))
	var gpCol: Color = Color(0.22, 0.24, 0.30, 0.6)
	# Vertical grid lines.
	# 垂直网格线。
	var x: int = gpStartX
	while x < int(gpCv.size.x):
		gpCv.draw_line(Vector2(x, 0), Vector2(x, gpCv.size.y), gpCol, 1.0)
		x += int(gpStep)
	# Horizontal grid lines.
	# 水平网格线。
	var y: int = gpStartY
	while y < int(gpCv.size.y):
		gpCv.draw_line(Vector2(0, y), Vector2(gpCv.size.x, y), gpCol, 1.0)
		y += int(gpStep)


# Draw the rubber-band line when connecting two symbols.
# 连接两个图元时绘制橡皮筋线。
func _gpDrawConnectPreview() -> void:
	if gpCv.gpMode != GPMode.GP_CONNECT or gpCv.gpConnectFrom == "":
		return
	var gpC: Vector2 = gpCv._gpNodeCenter(gpCv.gpConnectFrom)
	if gpC == Vector2.INF:
		return
	gpCv.draw_line(gpCv.gpScreenFromWorld(gpC), gpCv.get_local_mouse_position(), Color(0.30, 1.0, 0.40), 1.5)


# Draw every annotation shape, its selection highlight and the in-progress rubber band.
# 绘制所有注释图形、其选择高亮与进行中的橡皮筋。
func _gpDrawShapes() -> void:
	if gpCv.gpGraph == null:
		return
	var gpInk: Color = Color(0.92, 0.94, 0.98)
	var gpSelCol: Color = Color(0.45, 0.75, 1.0)
	for gpS in gpCv.gpGraph.gpShapes:
		_gpDrawOneShape(gpS, gpInk)
	# Selection highlight (above the committed ink, below the rubber band).
	# 选择高亮（位于已绘制墨线之上、橡皮筋之下）。
	for gpIdx in gpCv.gpShapeSel:
		if gpIdx >= 0 and gpIdx < gpCv.gpGraph.gpShapes.size():
			var gpB: Rect2 = gpCv.gpGraph.gpShapes[gpIdx].gpBBox()
			var gpPos: Vector2 = gpCv.gpScreenFromWorld(gpB.position)
			var gpSize: Vector2 = gpB.size * gpCv.gpViewZoom
			gpCv.draw_rect(Rect2(gpPos, gpSize).grow(3.0), Color(gpSelCol, 0.9), false, 1.0)
	# Grips (handles) for the single selected shape — AutoCAD-style editing points the user can
	# drag to reshape / resize. Shown only for a single selection so a multi-pick drag stays a move.
	# 选中单枚图形时显示锚点（手柄）——用户可拖动的 AutoCAD 式编辑点，用于重塑 / 缩放。仅单选时显示，
	# 使多选拖拽保持为整体移动。
	if gpCv.gpShapeSel.size() == 1:
		var gpSelIdx: int = gpCv.gpShapeSel[0]
		if gpSelIdx >= 0 and gpSelIdx < gpCv.gpGraph.gpShapes.size():
			var gpGrips: Array[Dictionary] = GPShapeGripEditor.gpGrips(gpCv.gpGraph.gpShapes[gpSelIdx])
			var gpGs: float = 8.0
			# Vertex grips first (drawn as plain squares); handle grips get a tie-line to their
			# owning vertex drawn first so the squares sit on top of the line.
			# 先处理顶点抓取点（普通方块）；手柄抓取点先画到所属顶点的连线，使方块盖在连线上。
			for gpG in gpGrips:
				var gpP: Vector2 = gpCv.gpScreenFromWorld(gpG["pos"])
				var gpRect: Rect2 = Rect2(gpP - Vector2(gpGs * 0.5, gpGs * 0.5), Vector2(gpGs, gpGs))
				if int(gpG["role"]) == GPShapeGripEditor.GP_GRIP_HANDLE_IN or int(gpG["role"]) == GPShapeGripEditor.GP_GRIP_HANDLE_OUT:
					# The handle grip is stored as a RELATIVE offset on its vertex, so the owner of the
					# tie-line is the vertex itself (gpPoints[gi]); the grip position is the handle end.
					# 手柄以「相对所属顶点的偏移」存储，故连线的所属端点就是顶点本身（gpPoints[gi]），
					# 抓取点位置则是手柄末端。
					var gpOwner: Vector2 = gpCv.gpGraph.gpShapes[gpSelIdx].gpPoints[int(gpG["gi"])]
					gpCv.draw_line(gpCv.gpScreenFromWorld(gpOwner), gpP, Color(gpSelCol, 0.5), 1.0)
				gpCv.draw_rect(gpRect, Color(1.0, 1.0, 1.0), true)
				gpCv.draw_rect(gpRect, Color(0.20, 0.50, 1.0), false, 1.5)
	# In-progress rubber band for line / circle / rect.
	# 直线/圆/矩形的进行中橡皮筋。
	if gpCv._gpDrawActive:
		var gpA: Vector2 = gpCv.gpScreenFromWorld(gpCv._gpDrawFrom)
		var gpB: Vector2 = gpCv.gpScreenFromWorld(gpCv._gpDrawTo)
		match gpCv.gpMode:
			GPMode.GP_DRAW_LINE:
				gpCv.draw_line(gpA, gpB, Color(1.0, 0.82, 0.25), 1.5)
			GPMode.GP_DRAW_CIRCLE:
				gpCv.draw_circle(gpA, gpA.distance_to(gpB), Color(1.0, 0.82, 0.25, 0.7), false, 1.0)
			GPMode.GP_DRAW_RECT:
				gpCv.draw_rect(Rect2(gpA, gpB - gpA).abs(), Color(1.0, 0.82, 0.25, 0.7), false, 1.0)
	# In-progress polyline: committed vertices + rubber band to the cursor.
	# 进行中的折线：已落定顶点 + 到光标的橡皮筋。
	if not gpCv._gpPolyPts.is_empty():
		var gpV: PackedVector2Array = PackedVector2Array()
		for gpP in gpCv._gpPolyPts:
			gpV.append(gpCv.gpScreenFromWorld(gpP))
		if gpV.size() >= 2:
			gpCv.draw_polyline(gpV, Color(1.0, 0.82, 0.25), 1.5)
		gpCv.draw_line(gpCv.gpScreenFromWorld(gpCv._gpPolyPts.back()), gpCv.get_local_mouse_position(), Color(1.0, 0.82, 0.25, 0.6), 1.0)
		for gpP in gpCv._gpPolyPts:
			gpCv.draw_circle(gpCv.gpScreenFromWorld(gpP), 3.0, Color(1.0, 0.82, 0.25))


# Draw one annotation shape in screen space (world coords transformed by the camera).
# 在屏幕空间绘制一枚注释图形（世界坐标经相机变换）。
func _gpDrawOneShape(gpS: GPShape, gpInk: Color) -> void:
	match gpS.gpKind:
		GPShape.GPKind.GP_LINE:
			if gpS.gpPoints.size() >= 2:
				gpCv.draw_line(gpCv.gpScreenFromWorld(gpS.gpPoints[0]), gpCv.gpScreenFromWorld(gpS.gpPoints[1]), gpInk, 2.0)
		GPShape.GPKind.GP_CIRCLE:
			if gpS.gpPoints.size() >= 1:
				gpCv.draw_circle(gpCv.gpScreenFromWorld(gpS.gpPoints[0]), gpS.gpRadius * gpCv.gpViewZoom, gpInk, false, 2.0)
		GPShape.GPKind.GP_RECT:
			if gpS.gpPoints.size() >= 2:
				var gpR: Rect2 = Rect2(gpCv.gpScreenFromWorld(gpS.gpPoints[0]), (gpS.gpPoints[1] - gpS.gpPoints[0]).abs() * gpCv.gpViewZoom)
				gpCv.draw_rect(gpR, gpInk, false, 2.0)
		GPShape.GPKind.GP_POLYLINE:
			# Sample the polyline (Bézier-handle aware) so pulled-out handles render as curves.
			# 沿折线采样（感知贝塞尔手柄），使拉出的手柄渲染成曲线。
			var gpSamp: PackedVector2Array = GPGeometry.gpRenderPoints(gpS, 8)
			var gpV: PackedVector2Array = PackedVector2Array()
			for gpP in gpSamp:
				gpV.append(gpCv.gpScreenFromWorld(gpP))
			if gpS.gpClosed and gpV.size() >= 2:
				gpV.append(gpV[0])
			if gpV.size() >= 2:
				gpCv.draw_polyline(gpV, gpInk, 2.0)
		GPShape.GPKind.GP_ARC:
			# Sample the arc through the shared renderer (gpArcSample) so it matches the painter.
			# 经共享渲染器（gpArcSample）采样圆弧，使主画布与符号绘制器表现一致。
			var gpArcPts: PackedVector2Array = GPGeometry.gpRenderPoints(gpS, 8)
			var gpArcV: PackedVector2Array = PackedVector2Array()
			for gpP in gpArcPts:
				gpArcV.append(gpCv.gpScreenFromWorld(gpP))
			if gpArcV.size() >= 2:
				gpCv.draw_polyline(gpArcV, gpInk, 2.0)
