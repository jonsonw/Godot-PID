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
#
# Phase 2 (块式重构) extends this single surface into the geometry-canvas kernel (M1):
# it keeps the four drawing tools (polyline / circle / rect / port) and ADDS a "Select" tool
# that supports point-pick, rubber-band marquee (Window / Crossing), drag-move, right-click
# context menu and a progressive ESC. Selection is addressed by (kind + index); indices are
# re-resolved after every mutation (see _gpPruneSelection) — stable uid is deferred to the undo
# stage (decision D4).
# Phase 2（块式重构）把这块面板升级为几何画布内核（M1）：保留四种绘图工具，并新增「选择」工具，
# 支持点选、框选（Window/Crossing）、拖动、右键上下文菜单与渐进式 ESC。选择集以「种类 + 下标」
# 寻址，每次增删后重新解析下标（见 _gpPruneSelection）——稳定 uid 延后到撤销阶段（决策 D4）。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Emitted whenever the draft geometry changes (commit / undo / clear / edit).
# 草稿几何发生变化时发出（提交 / 撤销 / 清空 / 编辑）。
signal gpDraftChanged

# The author asked to turn the current drawing into a symbol (context-menu "Create Symbol…").
# The host (wizard / isolation layer) reads the geometry via gpGetDraftShapes / gpGetDraftPorts
# and opens the property + identity step. Left unconnected until Phase 4 wires the finalize flow.
# 用户请求把当前绘图生成为图元（右键菜单「生成图元…」）。宿主（向导 / 隔离层）通过
# gpGetDraftShapes / gpGetDraftPorts 读取几何并打开属性与身份步骤。Phase 4 接好收尾流程前先留作信号。
signal gpCreateRequested

# Active drawing tool.
# 当前绘图工具。
# GP_LINE is appended LAST so the legacy 0..4 tool ids (used by the demoted symbol-editor
# dropdown) stay unchanged; the isolation layer's tool row simply appends the line button.
# GP_LINE 放在最后，使旧的导出器下拉框仍沿用 0..4 的工具 id 不变；隔离层的工具行只在其末尾追加直线按钮。
enum GPTool { GP_POLYLINE, GP_CIRCLE, GP_RECT, GP_PORT, GP_SELECT, GP_LINE }

# Primitive kinds used to address a selection entry.
# 用于寻址选择集条目的图元种类。
const GP_KIND_PATH: String = "path"
const GP_KIND_CIRCLE: String = "circle"
const GP_KIND_RECT: String = "rect"
const GP_KIND_PORT: String = "port"

# Marquee semantics: left->right = Window (fully contained), right->left = Crossing (intersects).
# 框选语义：左→右 = 包含（Window），右→左 = 相交（Crossing）。
const GP_MARQUEE_WINDOW: int = 1
const GP_MARQUEE_CROSSING: int = 0

# Hit tolerance for thin primitives (lines) and the larger tolerance for clickable ports.
# 细线图元的命中容差，以及端口可点击的较大容差。
const GP_HIT_TOL: float = 6.0
const GP_PORT_HIT: float = 9.0

# Grid spacing in author-space pixels.
# 网格间距（作者空间像素）。
const GP_GRID: float = 16.0

# Snap radius for pulling a port onto the guide rectangle edge.
# 将端口吸附到参考框边线的吸附半径。
const GP_PORT_SNAP: float = 12.0

# Context-menu action ids. Deliberately spaced so drafting-only entries can be added later.
# 上下文菜单动作 id。刻意留出间隔，便于后续追加仅绘制态可用的条目。
const GP_CTX_CREATE: int = 0
const GP_CTX_DELETE: int = 1
const GP_CTX_SELECT_ALL: int = 2
const GP_CTX_DESELECT: int = 3
const GP_CTX_FINISH: int = 10
const GP_CTX_SELECT_TOOL: int = 11

# Grip (edit-point) roles shown on a single selected primitive. Modeled on AutoCAD's
# endpoint / center / radius / corner / vertex grips so the user can move or resize a
# primitive directly after selecting it.
# 单个选中图元上显示的抓取点（编辑点）角色，参照 AutoCAD 的端点 / 圆心 / 半径 / 角点 / 顶点
# 逻辑：选中图元后即可直接拖动或缩放，无需进入绘图工具。
const GP_GRIP_ENDPOINT: int = 1
const GP_GRIP_CENTER: int = 2
const GP_GRIP_RADIUS: int = 3
const GP_GRIP_CORNER: int = 4
const GP_GRIP_VERTEX: int = 5

# Click tolerance for grabbing a grip handle (author-space pixels).
# 抓取点的点击容差（作者空间像素）。
const GP_GRIP_HIT: float = 7.0

# Fraction of the shorter widget dimension occupied by the guide rectangle.
# 参考框占控件较短边的比例。
const GP_GUIDE_FILL: float = 0.62

# Emitted whenever the active tool changes, so the host can keep its tool row in sync.
# 当前工具变化时发出，使宿主可同步其工具按钮行。
signal gpToolChanged(gpTool: int)

# Selected tool. Select / Edit is the DEFAULT: an editor that opens in a drawing tool hides the
# pick / marquee / context-menu features behind a menu choice most users never open.
# 已选工具。默认即为「选择 / 编辑」：若打开时停在绘图工具，点选 / 框选 / 右键菜单这些功能
# 就被藏在了一个大多数人根本不会打开的下拉里。
var gpTool: GPTool = GPTool.GP_SELECT

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

# Current selection: [{"kind": String, "index": int}].
# 当前选择集：[{"kind": 字符串, "index": 整数}]。
var gpSelection: Array[Dictionary] = []

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

# Marquee rectangle while dragging on empty space (author-space pixels).
# 在空白处拖拽时的框选矩形（作者空间像素）。
var _gpMarqueeFrom: Vector2 = Vector2.ZERO
var _gpMarqueeTo: Vector2 = Vector2.ZERO
var _gpMarqueeing: bool = false

# Whether a selection-drag (move) is active and the last cursor position seen during it.
# 选择拖动（移动）是否进行中，及其间最近一次光标位置。
var _gpMoving: bool = false
var _gpMoveLast: Vector2 = Vector2.ZERO

# Active grip-drag descriptor. Empty (is_empty) when no grip is being dragged. Fields:
# "kind" (primitive kind), "index" (array index), "role" (GP_GRIP_*), "gi" (grip index
# within the primitive, e.g. vertex index / corner index), "start" (grab point), and
# for corner grips "opp" (the fixed opposite corner used to resize the rect).
# 当前抓取点拖拽描述。无拖拽时为空字典（is_empty）。字段含：图元种类、数组下标、抓取点角色、
# 图元内抓取点下标、抓取起点；角点抓取另含固定不动的对角点 opp，用于矩形缩放。
var _gpGripDrag: Dictionary = {}


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
	_gpMarqueeing = false
	_gpMoving = false
	gpToolChanged.emit(int(gpNew))
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


# Load an existing symbol's geometry so it can be edited in place (block-editor workflow).
# 载入已有图元的几何，以便就地编辑（块编辑器工作流）。
# The author frame is arbitrary because gpNormalizeSymbol keeps only RELATIVE geometry: it fits
# the draft bbox into the unit box. Scaling the whole author space by any factor k therefore
# leaves the normalized result bit-identical (bbox scales by k, so the fit scale divides by k).
# That is why this loader may freely magnify the unit-box coordinates to a comfortable editing
# size without any loss on save.
# 作者空间是任意的，因为 gpNormalizeSymbol 只保留「相对几何」：它把草稿包围盒塞进单位框。
# 因此把整个作者空间统一缩放 k 倍，归一化结果逐位相同（包围盒放大 k，拟合缩放就除以 k）。
# 这正是本加载器可以随意把单位框坐标放大到舒适编辑尺寸、而保存时毫无损失的原因。
# [param gpShapes] dict with "paths"/"circles"/"rects" in author space.
# [param gpShapes] 含作者空间 "paths"/"circles"/"rects" 的字典。
func gpLoadShapes(gpShapes: Dictionary) -> void:
	gpPaths.clear()
	gpCircles.clear()
	gpRects.clear()
	_gpHistory.clear()
	gpSelection.clear()
	_gpDraftPts.clear()
	_gpDragging = false
	_gpMarqueeing = false
	_gpMoving = false

	for gpP in (gpShapes.get("paths", []) as Array):
		var gpPd: Dictionary = gpP as Dictionary
		var gpPts: Array[Vector2] = []
		for gpPair in (gpPd.get("pts", []) as Array):
			gpPts.append(Vector2(float(gpPair[0]), float(gpPair[1])))
		if gpPts.size() >= 2:
			gpPaths.append({"pts": gpPts, "closed": bool(gpPd.get("closed", false))})
			_gpHistory.append("path")

	for gpC in (gpShapes.get("circles", []) as Array):
		var gpCd: Dictionary = gpC as Dictionary
		var gpCc: Array = gpCd.get("c", [0.0, 0.0]) as Array
		gpCircles.append({
			"c": Vector2(float(gpCc[0]), float(gpCc[1])),
			"r": absf(float(gpCd.get("r", 1.0))),
		})
		_gpHistory.append("circle")

	for gpR in (gpShapes.get("rects", []) as Array):
		var gpRd: Dictionary = gpR as Dictionary
		var gpPos: Array = gpRd.get("pos", [0.0, 0.0]) as Array
		var gpSz: Array = gpRd.get("size", [0.0, 0.0]) as Array
		gpRects.append(Rect2(
			Vector2(float(gpPos[0]), float(gpPos[1])),
			Vector2(float(gpSz[0]), float(gpSz[1]))))
		_gpHistory.append("rect")

	queue_redraw()
	gpDraftChanged.emit()


# Load author-space ports (positions already in the same frame as gpLoadShapes).
# 载入作者空间端口（坐标与 gpLoadShapes 处于同一坐标系）。
func gpLoadPorts(gpPortsIn: Array) -> void:
	gpPorts.clear()
	for gpP in gpPortsIn:
		var gpPd: Dictionary = gpP as Dictionary
		var gpPos: Array = gpPd.get("pos", [0.5, 0.5]) as Array
		gpPorts.append({
			"name": str(gpPd.get("name", "p%d" % (gpPorts.size() + 1))),
			"pos": Vector2(float(gpPos[0]), float(gpPos[1])),
		})
		_gpHistory.append("port")
	queue_redraw()
	gpDraftChanged.emit()


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
	_gpPruneSelection()
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
	_gpMarqueeing = false
	_gpMoving = false
	gpSelection.clear()
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


# Whether any geometry (paths / circles / rects / ports) has been drawn.
# 是否已绘制任何几何（折线 / 圆 / 矩形 / 端口）。
func gpIsEmpty() -> bool:
	return gpPaths.is_empty() and gpCircles.is_empty() and gpRects.is_empty()


# Whether the drawing carries anything at all (used to enable "Create Symbol").
# 是否绘制了任何内容（用于启用「生成图元」）。
func _gpHasContent() -> bool:
	return not (gpPaths.is_empty() and gpCircles.is_empty() and gpRects.is_empty() and gpPorts.is_empty())


# Handle mouse and keyboard input for the active tool.
# 处理当前工具的鼠标与键盘输入。
func _gui_input(gpEvent: InputEvent) -> void:
	if gpEvent is InputEventMouseMotion:
		var gpPt: Vector2 = _gpSnapPoint((gpEvent as InputEventMouseMotion).position)
		_gpCursor = gpPt
		if _gpMarqueeing:
			_gpMarqueeTo = gpPt
			queue_redraw()
		elif not _gpGripDrag.is_empty():
			# Dragging a grip edits the primitive in place (endpoint / center / radius / corner / vertex).
			# 拖动抓取点：就地编辑图元（端点 / 圆心 / 半径 / 角点 / 顶点）。
			_gpOnGripMove(gpPt)
		elif _gpMoving:
			_gpMoveSelected(gpPt - _gpMoveLast)
			_gpMoveLast = gpPt
		elif _gpDragging or not _gpDraftPts.is_empty():
			queue_redraw()
		return

	if gpEvent is InputEventMouseButton:
		var gpMb: InputEventMouseButton = gpEvent as InputEventMouseButton
		var gpPt: Vector2 = _gpSnapPoint(gpMb.position)
		# Right click ALWAYS opens the context menu. The old "finish the polyline instead" rule
		# made right click look dead exactly when a user most wants a menu (mid-draft), and it hid
		# every selection feature. While a polyline is in progress the menu simply leads with
		# "Finish Path", so no capability is lost.
		# 右键恒定弹出上下文菜单。旧的"改为结束折线"规则，恰好在用户最想要菜单的时候（绘制中）
		# 让右键看起来像失效，并掩盖了全部选择功能。折线进行中时菜单首项即为「结束折线」，
		# 因此不丢失任何能力。
		if gpMb.button_index == MOUSE_BUTTON_RIGHT and gpMb.pressed:
			# Cancel any in-progress grip / move drag so the menu never leaves a stuck state.
			# 取消进行中的抓取 / 移动拖拽，避免菜单留下卡死状态。
			if not _gpGripDrag.is_empty() or _gpMoving:
				_gpGripDrag.clear()
				_gpMoving = false
				queue_redraw()
			_gpShowContextMenu()
			accept_event()
			return
		if gpMb.button_index != MOUSE_BUTTON_LEFT:
			return
		# Select tool: pick / marquee on press, commit on release.
		# 选择工具：按下时点选 / 框选，松开时收尾。
		if gpTool == GPTool.GP_SELECT:
			if gpMb.pressed:
				_gpOnSelectDown(gpPt, gpMb.shift_pressed)
			else:
				if not _gpGripDrag.is_empty():
					_gpGripDrag.clear()
				elif _gpMarqueeing:
					_gpCommitMarquee()
				_gpMoving = false
			accept_event()
			return
		# Drawing tools: unchanged behaviour.
		# 绘图工具：行为不变。
		match gpTool:
			GPTool.GP_POLYLINE:
				if gpMb.pressed:
					if gpMb.double_click:
						var gpBefore: int = gpPaths.size()
						gpFinishPath(_gpNearFirst(gpPt))
						if gpPaths.size() > gpBefore:
							gpSelection = [{"kind": GP_KIND_PATH, "index": gpPaths.size() - 1}]
							gpSetTool(GPTool.GP_SELECT)
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
			GPTool.GP_LINE:
				# Straight line: press anchors the start point, release commits a 2-point path.
				# 直线：按下锚定起点，松开提交为两点折线（path）。
				if gpMb.pressed:
					_gpDragFrom = gpPt
					_gpCursor = gpPt
					_gpDragging = true
				else:
					_gpCommitLine(gpPt)
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
				var gpBefore: int = gpPaths.size()
				gpFinishPath(false)
				if gpPaths.size() > gpBefore:
					gpSelection = [{"kind": GP_KIND_PATH, "index": gpPaths.size() - 1}]
					gpSetTool(GPTool.GP_SELECT)
				accept_event()
			KEY_DELETE:
				# Delete selected primitives (Select tool). No-op when nothing is selected.
				# 删除选中图元（选择工具）。无选中时为空操作。
				if not gpSelection.is_empty():
					_gpDeleteSelected()
					accept_event()
			KEY_ESCAPE:
				# Progressive ESC: only consume the key when there is local state to unwind.
				# 渐进式 ESC：仅当存在本层可回退的状态时才消费该按键。
				if not _gpGripDrag.is_empty():
					_gpGripDrag.clear()
					queue_redraw()
					accept_event()
					return
				if not _gpDraftPts.is_empty():
					_gpDraftPts.clear()
					_gpDragging = false
					queue_redraw()
					accept_event()
					return
				if _gpMarqueeing:
					_gpMarqueeing = false
					queue_redraw()
					accept_event()
					return
				if not gpSelection.is_empty():
					gpSelection.clear()
					queue_redraw()
					accept_event()
					return
				# Nothing local to unwind -> do NOT consume; let it bubble (isolation layer, Phase 3).
				# 本层无状态可回退 → 不消费，让事件向上冒泡（隔离层，Phase 3）。
				return
			KEY_A:
				# Ctrl/Cmd+A selects every primitive — without it the geometry canvas has no
				# discoverable way to grab everything at once.
				# Ctrl/Cmd+A 全选：缺少它，几何画布就没有一目了然的"一次全选中"手段。
				if gpKey.ctrl_pressed or gpKey.meta_pressed:
					_gpSelectAll()
					accept_event()
			KEY_BACKSPACE:
				gpUndo()
				accept_event()


# Left press in Select mode: hit-test first; only start a marquee when nothing was hit.
# 选择模式下左键按下：先做命中测试；只有没命中任何东西时才开始框选。
func _gpOnSelectDown(gpPt: Vector2, gpShift: bool) -> void:
	# Grip priority: with exactly one primitive selected, grabbing its grip edits it in place
	# instead of moving the whole shape. This is what makes a selected circle / line / rect
	# behave like AutoCAD (endpoints, center+radius, corners become draggable handles).
	# 抓取点优先：仅选中单个图元时，按住其抓取点即就地编辑，而不是整体移动。正因如此，选中的
	# 圆 / 直线 / 矩形才像 AutoCAD 那样可拖动端点、圆心+半径、角点进行编辑。
	if gpSelection.size() == 1 and _gpGripDrag.is_empty():
		var gpGrip: Dictionary = _gpHitGrip(gpPt)
		if not gpGrip.is_empty():
			_gpStartGripDrag(gpGrip, gpPt)
			return
	var gpHit: Dictionary = gpPick(gpPt, gpPaths, gpCircles, gpRects, gpPorts, GP_HIT_TOL, GP_PORT_HIT)
	if not gpHit.is_empty():
		var gpKind: String = gpHit["kind"]
		var gpIdx: int = int(gpHit["index"])
		# Shift keeps the existing selection; without shift, clear others only when the hit is new.
		# Shift 保留既有选择；无 Shift 时仅当命中项尚未选中才清空其他项。
		if not gpShift and not _gpIsSelected(gpKind, gpIdx):
			gpSelection.clear()
		if not _gpIsSelected(gpKind, gpIdx):
			gpSelection.append(gpHit)
		_gpMoving = true
		_gpMoveLast = gpPt
		queue_redraw()
		return
	if not gpShift:
		gpSelection.clear()
	_gpMarqueeFrom = gpPt
	_gpMarqueeTo = gpPt
	_gpMarqueeing = true
	queue_redraw()


# Finish a marquee drag: resolve Window/Crossing and replace the selection.
# 结束框选拖拽：按 Window/Crossing 语义解析并替换选择集。
func _gpCommitMarquee() -> void:
	_gpMarqueeing = false
	var gpRect: Rect2 = Rect2(_gpMarqueeFrom, _gpMarqueeTo - _gpMarqueeFrom).abs()
	var gpMode: int = _gpMarqueeMode(_gpMarqueeFrom, _gpMarqueeTo)
	var gpNew: Array[Dictionary] = []
	gpNew.append_array(_gpMarqueeSelect(gpRect, gpMode, GP_KIND_PATH, gpPaths, GP_PORT_HIT))
	gpNew.append_array(_gpMarqueeSelect(gpRect, gpMode, GP_KIND_CIRCLE, gpCircles, GP_PORT_HIT))
	gpNew.append_array(_gpMarqueeSelect(gpRect, gpMode, GP_KIND_RECT, gpRects, GP_PORT_HIT))
	gpNew.append_array(_gpMarqueeSelect(gpRect, gpMode, GP_KIND_PORT, gpPorts, GP_PORT_HIT))
	gpSelection = gpNew
	queue_redraw()


# Remove every selected primitive (descending per kind so lower indices stay valid), then prune.
# 删除全部选中图元（每种类按下标降序移除，使较低下标保持有效），随后裁剪选择集。
func _gpDeleteSelected() -> void:
	if gpSelection.is_empty():
		return
	var gpByKind: Dictionary = {}
	for gpS in gpSelection:
		var gpK: String = gpS["kind"]
		var gpI: int = int(gpS["index"])
		if not gpByKind.has(gpK):
			gpByKind[gpK] = []
		(gpByKind[gpK] as Array).append(gpI)
	for gpK in gpByKind.keys():
		var gpIdxs: Array = gpByKind[gpK] as Array
		gpIdxs.sort()
		gpIdxs.reverse()
		match gpK:
			GP_KIND_PATH:
				for gpI in gpIdxs:
					if gpI >= 0 and gpI < gpPaths.size():
						gpPaths.remove_at(gpI)
			GP_KIND_CIRCLE:
				for gpI in gpIdxs:
					if gpI >= 0 and gpI < gpCircles.size():
						gpCircles.remove_at(gpI)
			GP_KIND_RECT:
				for gpI in gpIdxs:
					if gpI >= 0 and gpI < gpRects.size():
						gpRects.remove_at(gpI)
			GP_KIND_PORT:
				for gpI in gpIdxs:
					if gpI >= 0 and gpI < gpPorts.size():
						gpPorts.remove_at(gpI)
	gpSelection.clear()
	gpDraftChanged.emit()
	queue_redraw()


# Drop selection entries whose index is now out of range for its kind.
# 丢弃下标已越界的选择集条目。
func _gpPruneSelection() -> void:
	gpSelection = _gpPruneStatic(gpSelection, gpPaths.size(), gpCircles.size(), gpRects.size(), gpPorts.size())


# Select every committed primitive.
# 选中全部已提交图元。
func _gpSelectAll() -> void:
	gpSelection.clear()
	for gpI in range(gpPaths.size()):
		gpSelection.append({"kind": GP_KIND_PATH, "index": gpI})
	for gpI in range(gpCircles.size()):
		gpSelection.append({"kind": GP_KIND_CIRCLE, "index": gpI})
	for gpI in range(gpRects.size()):
		gpSelection.append({"kind": GP_KIND_RECT, "index": gpI})
	for gpI in range(gpPorts.size()):
		gpSelection.append({"kind": GP_KIND_PORT, "index": gpI})
	queue_redraw()


# Translate every selected primitive by gpDelta (author-space pixels).
# 把每个选中图元平移 gpDelta（作者空间像素）。
func _gpMoveSelected(gpDelta: Vector2) -> void:
	if gpDelta == Vector2.ZERO:
		return
	for gpS in gpSelection:
		var gpK: String = gpS["kind"]
		var gpI: int = int(gpS["index"])
		match gpK:
			GP_KIND_PATH:
				if gpI >= 0 and gpI < gpPaths.size():
					var gpOld: Array = gpPaths[gpI]["pts"]
					var gpNew: Array = []
					for gpV in gpOld:
						gpNew.append((gpV as Vector2) + gpDelta)
					gpPaths[gpI]["pts"] = gpNew
			GP_KIND_CIRCLE:
				if gpI >= 0 and gpI < gpCircles.size():
					var gpC: Dictionary = gpCircles[gpI]
					gpC["c"] = (gpC["c"] as Vector2) + gpDelta
					gpCircles[gpI] = gpC
			GP_KIND_RECT:
				if gpI >= 0 and gpI < gpRects.size():
					var gpR: Rect2 = gpRects[gpI] as Rect2
					gpRects[gpI] = Rect2(gpR.position + gpDelta, gpR.size)
			GP_KIND_PORT:
				if gpI >= 0 and gpI < gpPorts.size():
					var gpP: Dictionary = gpPorts[gpI]
					gpP["pos"] = (gpP["pos"] as Vector2) + gpDelta
					gpPorts[gpI] = gpP
	gpDraftChanged.emit()
	queue_redraw()


# Build and show the context menu at the cursor.
# 在光标处构建并显示上下文菜单。
func _gpShowContextMenu() -> void:
	var gpMenu: PopupMenu = PopupMenu.new()
	# Drafting state: offer to finish the open polyline first.
	# 绘制态：先提供结束未闭合折线。
	if not _gpDraftPts.is_empty():
		gpMenu.add_item(I18n.gpTr("symed.ctx_finish_path"), GP_CTX_FINISH)
		gpMenu.add_separator()
	gpMenu.add_item(I18n.gpTr("symed.ctx_create"), GP_CTX_CREATE)
	# Disable by ITEM INDEX resolved from the id: positional indices shift when the optional
	# "Finish Path" entry is present.
	# 按 id 解析出条目下标再禁用：可选「结束折线」条目存在时，位置下标会前移。
	gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_CREATE), not _gpHasContent() and gpSelection.is_empty())
	gpMenu.add_item(I18n.gpTr("symed.ctx_delete"), GP_CTX_DELETE)
	gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DELETE), gpSelection.is_empty())
	gpMenu.add_separator()
	gpMenu.add_item(I18n.gpTr("symed.ctx_select_all"), GP_CTX_SELECT_ALL)
	gpMenu.add_item(I18n.gpTr("symed.ctx_deselect"), GP_CTX_DESELECT)
	gpMenu.add_separator()
	# Switching back to Select / Edit from the menu: the feature must be reachable even for a
	# user who never opened the tool dropdown.
	# 可从菜单切回「选择 / 编辑」：即使从未打开工具下拉的用户也能触达该功能。
	gpMenu.add_item(I18n.gpTr("symed.ctx_select_tool"), GP_CTX_SELECT_TOOL)
	gpMenu.set_item_disabled(gpMenu.item_count - 1, gpTool == GPTool.GP_SELECT)
	gpMenu.id_pressed.connect(_gpOnContext)
	add_child(gpMenu)
	# Godot 4 exposes NO popup_at_cursor() on PopupMenu; popup() is the only positioning entry, and with
	# embed_subwindows=false (default) its .position is in GLOBAL SCREEN coordinates. get_viewport().
	# get_mouse_position() yields the cursor in WINDOW-LOCAL pixels (post-stretch); add the main window's
	# screen position for the true OS-cursor screen coordinate (the Godot-CAD reference pattern). The menu
	# top-left anchors at the pointer and opens down-right. (2,2) nudges the cursor off the corner.
	# Godot 4 的 PopupMenu 没有 popup_at_cursor()，仅 popup() 可定位；「非嵌入」时其 .position 取全局屏幕
	# 坐标。get_viewport().get_mouse_position() 返回「窗口内」像素坐标（已含拉伸缩放），叠加主窗口屏幕位置
	# 即 OS 光标的真实屏幕坐标（即 Godot-CAD 参考实现做法）。菜单左上角锚定指针、向右下展开。(2,2) 微调。
	var gpMouseWin: Vector2i = get_viewport().get_mouse_position()
	gpMenu.position = Vector2i(get_window().position) + gpMouseWin + Vector2i(2, 2)
	gpMenu.popup()
	# Free the menu after it closes; a leaked PopupMenu keeps its parent alive.
	# 关闭后释放菜单；泄漏的 PopupMenu 会让其父节点无法释放。
	gpMenu.popup_hide.connect(gpMenu.queue_free)


# Context-menu action dispatch.
# 上下文菜单动作分发。
func _gpOnContext(gpId: int) -> void:
	match gpId:
		0:
			gpCreateRequested.emit()
		1:
			_gpDeleteSelected()
		2:
			_gpSelectAll()
		3:
			gpSelection.clear()
			queue_redraw()
		10:
			# Finish the open polyline (mirrors the Finish Path button / Enter key).
			# 结束未闭合折线（与「结束折线」按钮 / Enter 键等效）。
			gpFinishPath(false)
		11:
			# Switch to Select / Edit. gpSetTool() already emits gpToolChanged for the host UI.
			# 切到「选择 / 编辑」。gpSetTool() 已会发出 gpToolChanged 通知宿主界面。
			gpSetTool(GPTool.GP_SELECT)


# Whether (kind, index) is already in the selection.
# （种类，下标）是否已在选择集中。
func _gpIsSelected(gpKind: String, gpIdx: int) -> bool:
	for gpS in gpSelection:
		if gpS["kind"] == gpKind and int(gpS["index"]) == gpIdx:
			return true
	return false


# Bounding box of a selected entry (small square around a port), for the highlight overlay.
# 选择条目的包围盒（端口取以其为中心的小方块），用于高亮叠层。
func _gpSelectionBBox(gpS: Dictionary) -> Rect2:
	var gpKind: String = gpS["kind"]
	var gpIdx: int = int(gpS["index"])
	if gpKind == GP_KIND_PORT:
		if gpIdx >= 0 and gpIdx < gpPorts.size():
			return Rect2((gpPorts[gpIdx]["pos"] as Vector2) - Vector2(GP_PORT_HIT, GP_PORT_HIT), Vector2(GP_PORT_HIT * 2.0, GP_PORT_HIT * 2.0))
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	return _gpPrimBBox(gpKind, gpIdx, gpPaths, gpCircles, gpRects)


# Grip handles (edit points) of a single selected primitive, in author-space pixels.
# 单个选中图元的抓取点（编辑点），以作者空间像素给出。
func _gpShapeGrips(gpS: Dictionary) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	var gpKind: String = gpS["kind"]
	var gpIdx: int = int(gpS["index"])
	if gpKind == GP_KIND_PATH and gpIdx >= 0 and gpIdx < gpPaths.size():
		var gpPts: Array = gpPaths[gpIdx]["pts"]
		for gpK in range(gpPts.size()):
			gpOut.append({"role": GP_GRIP_VERTEX, "gi": gpK, "pos": gpPts[gpK] as Vector2})
	elif gpKind == GP_KIND_CIRCLE and gpIdx >= 0 and gpIdx < gpCircles.size():
		var gpC: Vector2 = gpCircles[gpIdx]["c"]
		var gpR: float = gpCircles[gpIdx]["r"]
		gpOut.append({"role": GP_GRIP_CENTER, "gi": 0, "pos": gpC})
		gpOut.append({"role": GP_GRIP_RADIUS, "gi": 1, "pos": gpC + Vector2(gpR, 0.0)})
	elif gpKind == GP_KIND_RECT and gpIdx >= 0 and gpIdx < gpRects.size():
		var gpCorners: PackedVector2Array = _gpRectCorners(gpRects[gpIdx] as Rect2)
		for gpN in range(4):
			gpOut.append({"role": GP_GRIP_CORNER, "gi": gpN, "pos": gpCorners[gpN]})
	elif gpKind == GP_KIND_PORT and gpIdx >= 0 and gpIdx < gpPorts.size():
		gpOut.append({"role": GP_GRIP_VERTEX, "gi": 0, "pos": gpPorts[gpIdx]["pos"] as Vector2})
	return gpOut


# Topmost grip under gpPt for the single selected primitive, or an empty dict.
# 单个选中图元下 gpPt 处的最上抓点，未命中返回空字典。
func _gpHitGrip(gpPt: Vector2) -> Dictionary:
	if gpSelection.size() != 1:
		return {}
	var gpGrips: Array[Dictionary] = _gpShapeGrips(gpSelection[0])
	for gpG in gpGrips:
		if gpPt.distance_to(gpG["pos"] as Vector2) <= GP_GRIP_HIT:
			var gpHit: Dictionary = gpG.duplicate()
			gpHit["kind"] = gpSelection[0]["kind"]
			gpHit["index"] = int(gpSelection[0]["index"])
			return gpHit
	return {}


# Begin dragging the grip described by gpGrip (the hit result from _gpHitGrip).
# 开始拖动 gpGrip（来自 _gpHitGrip 的命中结果）所指的抓取点。
func _gpStartGripDrag(gpGrip: Dictionary, gpPt: Vector2) -> void:
	_gpGripDrag = gpGrip.duplicate()
	_gpGripDrag["start"] = gpPt
	if int(gpGrip["role"]) == GP_GRIP_CORNER:
		# Keep the opposite corner fixed so the rect resizes from the dragged corner only.
		# 固定对角点，使矩形仅从被拖动的角点缩放。
		var gpR: Rect2 = gpRects[int(gpGrip["index"])] as Rect2
		var gpCorners: PackedVector2Array = _gpRectCorners(gpR)
		var gpOpp: int = (int(gpGrip["gi"]) + 2) % 4
		_gpGripDrag["opp"] = gpCorners[gpOpp]
	queue_redraw()


# Live-edit the primitive while a grip is dragged (mutates the model in place).
# 拖动抓取点时就地编辑图元（直接改写模型）。
func _gpOnGripMove(gpPt: Vector2) -> void:
	if _gpGripDrag.is_empty():
		return
	var gpP: Vector2 = _gpSnapPoint(gpPt)
	var gpKind: String = _gpGripDrag["kind"]
	var gpIdx: int = int(_gpGripDrag["index"])
	var gpRole: int = int(_gpGripDrag["role"])
	var gpGi: int = int(_gpGripDrag["gi"])
	match gpRole:
		GP_GRIP_VERTEX:
			if gpKind == GP_KIND_PATH and gpIdx >= 0 and gpIdx < gpPaths.size():
				var gpPts: Array = gpPaths[gpIdx]["pts"]
				if gpGi >= 0 and gpGi < gpPts.size():
					gpPts[gpGi] = gpP
					gpPaths[gpIdx]["pts"] = gpPts
			elif gpKind == GP_KIND_PORT and gpIdx >= 0 and gpIdx < gpPorts.size():
				var gpPort: Dictionary = gpPorts[gpIdx]
				gpPort["pos"] = gpP
				gpPorts[gpIdx] = gpPort
		GP_GRIP_CENTER:
			if gpKind == GP_KIND_CIRCLE and gpIdx >= 0 and gpIdx < gpCircles.size():
				var gpC: Dictionary = gpCircles[gpIdx]
				gpC["c"] = gpP
				gpCircles[gpIdx] = gpC
		GP_GRIP_RADIUS:
			if gpKind == GP_KIND_CIRCLE and gpIdx >= 0 and gpIdx < gpCircles.size():
				var gpC: Dictionary = gpCircles[gpIdx]
				gpC["r"] = maxf(1.0, (gpC["c"] as Vector2).distance_to(gpP))
				gpCircles[gpIdx] = gpC
		GP_GRIP_CORNER:
			if gpKind == GP_KIND_RECT and gpIdx >= 0 and gpIdx < gpRects.size():
				var gpOpp: Vector2 = _gpGripDrag["opp"] as Vector2
				gpRects[gpIdx] = Rect2(gpOpp, gpP - gpOpp).abs()
	gpDraftChanged.emit()
	queue_redraw()


# The four corners of a rect, in TL / TR / BR / BL order (used for corner grips).
# 矩形的四个角点，顺序为左上 / 右上 / 右下 / 左下（用于角点抓取）。
static func _gpRectCorners(gpR: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		gpR.position,
		Vector2(gpR.end.x, gpR.position.y),
		gpR.end,
		Vector2(gpR.position.x, gpR.end.y),
	])


# ============================ static geometry helpers / 静态几何助手 ============================
# Pure functions so the hit-test / marquee logic can be unit-checked headlessly (no Control instance).
# 纯函数，使命中测试 / 框选逻辑可在 headless 下做单元校验（无需实例化 Control）。

# Distance from point gpP to segment AB.
# 点 gpP 到线段 AB 的距离。
static func _gpDistPointSeg(gpP: Vector2, gpA: Vector2, gpB: Vector2) -> float:
	if gpA.is_equal_approx(gpB):
		return gpP.distance_to(gpA)
	var gpAB: Vector2 = gpB - gpA
	var gpLen2: float = gpAB.length_squared()
	if gpLen2 < 1e-9:
		return gpP.distance_to(gpA)
	var gpT: float = clampf(gpAB.dot(gpP - gpA) / gpLen2, 0.0, 1.0)
	return gpP.distance_to(gpA + gpAB * gpT)


# Axis-aligned bounding box of one primitive (index into the relevant array).
# 单个图元（相关数组中的下标）的轴对齐包围盒。
static func _gpPrimBBox(gpKind: String, gpIdx: int, gpPaths: Array[Dictionary], gpCircles: Array[Dictionary], gpRects: Array[Rect2]) -> Rect2:
	if gpIdx < 0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	match gpKind:
		GP_KIND_PATH:
			if gpIdx < gpPaths.size():
				var gpMin := Vector2(INF, INF)
				var gpMax := Vector2(-INF, -INF)
				for gpV in gpPaths[gpIdx]["pts"]:
					var gpPt: Vector2 = gpV
					gpMin = gpMin.min(gpPt)
					gpMax = gpMax.max(gpPt)
				return Rect2(gpMin, gpMax - gpMin)
		GP_KIND_CIRCLE:
			if gpIdx < gpCircles.size():
				var gpC: Vector2 = gpCircles[gpIdx]["c"]
				var gpR: float = gpCircles[gpIdx]["r"]
				return Rect2(gpC - Vector2(gpR, gpR), Vector2(gpR * 2.0, gpR * 2.0))
		GP_KIND_RECT:
			if gpIdx < gpRects.size():
				return gpRects[gpIdx] as Rect2
	return Rect2(Vector2.ZERO, Vector2.ZERO)


# Bounding box of one array element for marquee testing (path / circle / port need custom handling).
# 框选测试用：单个数组元素的包围盒（path / circle / port 需特殊处理）。
static func _gpArrBBox(gpKind: String, gpArr: Array, gpIdx: int) -> Rect2:
	if gpKind == GP_KIND_CIRCLE:
		var gpC: Vector2 = gpArr[gpIdx]["c"]
		var gpR: float = gpArr[gpIdx]["r"]
		return Rect2(gpC - Vector2(gpR, gpR), Vector2(gpR * 2.0, gpR * 2.0))
	if gpKind == GP_KIND_PORT:
		var gpPos: Vector2 = gpArr[gpIdx]["pos"]
		var gpH: float = GP_PORT_HIT
		return Rect2(gpPos - Vector2(gpH, gpH), Vector2(gpH * 2.0, gpH * 2.0))
	if gpKind == GP_KIND_RECT:
		return gpArr[gpIdx] as Rect2
	# path
	var gpMin := Vector2(INF, INF)
	var gpMax := Vector2(-INF, -INF)
	for gpV in (gpArr[gpIdx]["pts"] as Array):
		var gpPt: Vector2 = gpV
		gpMin = gpMin.min(gpPt)
		gpMax = gpMax.max(gpPt)
	return Rect2(gpMin, gpMax - gpMin)


# Is gpPt on / inside a primitive (within the hit tolerance)?
# 点 gpPt 是否落在图元上 / 内（在命中容差内）？
static func _gpHitPrim(gpPt: Vector2, gpKind: String, gpIdx: int, gpPaths: Array[Dictionary], gpCircles: Array[Dictionary], gpRects: Array[Rect2], gpPorts: Array[Dictionary], gpTol: float, gpPortHit: float) -> bool:
	match gpKind:
		GP_KIND_PATH:
			if gpIdx < gpPaths.size():
				var gpPts: Array = gpPaths[gpIdx]["pts"]
				for gpI in range(gpPts.size() - 1):
					if _gpDistPointSeg(gpPt, gpPts[gpI], gpPts[gpI + 1]) <= gpTol:
						return true
				return false
		GP_KIND_CIRCLE:
			if gpIdx < gpCircles.size():
				var gpC: Vector2 = gpCircles[gpIdx]["c"]
				var gpR: float = gpCircles[gpIdx]["r"]
				return gpPt.distance_to(gpC) <= gpR + gpTol
		GP_KIND_RECT:
			if gpIdx < gpRects.size():
				return (gpRects[gpIdx] as Rect2).grow(gpTol).has_point(gpPt)
		GP_KIND_PORT:
			if gpIdx < gpPorts.size():
				return gpPt.distance_to(gpPorts[gpIdx]["pos"]) <= gpPortHit
	return false


# Topmost primitive under gpPt, or an empty dict when nothing is hit.
# gpPt 下最上层的图元；未命中时返回空字典。
static func gpPick(gpPt: Vector2, gpPaths: Array[Dictionary], gpCircles: Array[Dictionary], gpRects: Array[Rect2], gpPorts: Array[Dictionary], gpTol: float, gpPortHit: float) -> Dictionary:
	for gpI in range(gpPorts.size() - 1, -1, -1):
		if _gpHitPrim(gpPt, GP_KIND_PORT, gpI, gpPaths, gpCircles, gpRects, gpPorts, gpTol, gpPortHit):
			return {"kind": GP_KIND_PORT, "index": gpI}
	for gpI in range(gpRects.size() - 1, -1, -1):
		if _gpHitPrim(gpPt, GP_KIND_RECT, gpI, gpPaths, gpCircles, gpRects, gpPorts, gpTol, gpPortHit):
			return {"kind": GP_KIND_RECT, "index": gpI}
	for gpI in range(gpCircles.size() - 1, -1, -1):
		if _gpHitPrim(gpPt, GP_KIND_CIRCLE, gpI, gpPaths, gpCircles, gpRects, gpPorts, gpTol, gpPortHit):
			return {"kind": GP_KIND_CIRCLE, "index": gpI}
	for gpI in range(gpPaths.size() - 1, -1, -1):
		if _gpHitPrim(gpPt, GP_KIND_PATH, gpI, gpPaths, gpCircles, gpRects, gpPorts, gpTol, gpPortHit):
			return {"kind": GP_KIND_PATH, "index": gpI}
	return {}


# Marquee mode from drag direction: left->right = Window (contain), right->left = Crossing.
# 由拖拽方向得出框选模式：左→右 = 包含（Window），右→左 = 相交（Crossing）。
static func _gpMarqueeMode(gpFrom: Vector2, gpTo: Vector2) -> int:
	return GP_MARQUEE_WINDOW if gpFrom.x <= gpTo.x else GP_MARQUEE_CROSSING


# Does a primitive bbox satisfy the marquee mode?
# 图元包围盒是否满足框选模式？
static func _gpPrimInMarquee(gpBBox: Rect2, gpRect: Rect2, gpMode: int) -> bool:
	if gpMode == GP_MARQUEE_WINDOW:
		return gpRect.encloses(gpBBox)
	return gpRect.intersects(gpBBox)


# Collect every primitive of gpKind whose bbox satisfies the marquee.
# 收集 gpKind 中所有满足框选条件的图元。
static func _gpMarqueeSelect(gpRect: Rect2, gpMode: int, gpKind: String, gpArr: Array, gpPortHit: float) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	for gpI in range(gpArr.size()):
		var gpB: Rect2 = _gpArrBBox(gpKind, gpArr, gpI)
		if _gpPrimInMarquee(gpB, gpRect, gpMode):
			gpOut.append({"kind": gpKind, "index": gpI})
	return gpOut


# Drop out-of-range selection entries given the current array sizes.
# 依据当前各数组大小，丢弃越界的选择集条目。
static func _gpPruneStatic(gpSel: Array[Dictionary], gpNPath: int, gpNCircle: int, gpNRect: int, gpNPort: int) -> Array[Dictionary]:
	var gpKept: Array[Dictionary] = []
	for gpS in gpSel:
		var gpK: String = gpS["kind"]
		var gpI: int = int(gpS["index"])
		var gpN: int = -1
		match gpK:
			GP_KIND_PATH:
				gpN = gpNPath
			GP_KIND_CIRCLE:
				gpN = gpNCircle
			GP_KIND_RECT:
				gpN = gpNRect
			GP_KIND_PORT:
				gpN = gpNPort
		if gpI >= 0 and gpI < gpN:
			gpKept.append(gpS)
	return gpKept


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
			# Auto-select the new circle and switch to Select so its grips appear immediately.
			# 自动选中新建圆并切到「选择」，使其抓取点立即出现（AutoCAD 风格）。
			gpSelection = [{"kind": GP_KIND_CIRCLE, "index": gpCircles.size() - 1}]
			gpSetTool(GPTool.GP_SELECT)
	else:
		var gpRect: Rect2 = Rect2(_gpDragFrom, gpTo - _gpDragFrom).abs()
		if gpRect.size.x >= 2.0 and gpRect.size.y >= 2.0:
			gpRects.append(gpRect)
			_gpHistory.append("rect")
			gpDraftChanged.emit()
			# Auto-select the new rect and switch to Select so its corner grips appear immediately.
			# 自动选中新建矩形并切到「选择」，使其角点抓取点立即出现。
			gpSelection = [{"kind": GP_KIND_RECT, "index": gpRects.size() - 1}]
			gpSetTool(GPTool.GP_SELECT)
	queue_redraw()


# Commit a straight-line drag as a 2-point polyline (a path primitive).
# 把直线拖拽提交为两点折线（path 图元原语）。
func _gpCommitLine(gpTo: Vector2) -> void:
	if not _gpDragging:
		return
	_gpDragging = false
	if _gpDragFrom.distance_to(gpTo) >= 2.0:
		gpPaths.append({"pts": [_gpDragFrom, gpTo], "closed": false})
		_gpHistory.append("path")
		gpDraftChanged.emit()
		# Auto-select the new line and switch to Select so its endpoints appear as grips.
		# 自动选中新建直线并切到「选择」，使其端点作为抓取点立即出现。
		gpSelection = [{"kind": GP_KIND_PATH, "index": gpPaths.size() - 1}]
		gpSetTool(GPTool.GP_SELECT)
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
	var gpSelCol: Color = Color(0.45, 0.75, 1.0)

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

	# Selection highlight (under the draft rubber-band, above the committed ink).
	# 选择高亮（位于草稿橡皮筋之下、已提交墨线之上）。
	for gpS in gpSelection:
		var gpB: Rect2 = _gpSelectionBBox(gpS)
		draw_rect(gpB.grow(3.0), Color(gpSelCol, 0.9), false, 1.0)

	# Grip handles for a single selected primitive: small white squares with a blue border,
	# draggable like AutoCAD's edit points (endpoint / center / radius / corner / vertex).
	# 单个选中图元的抓取点：白色小方块加蓝色边框，可像 AutoCAD 编辑点一样拖动（端点 / 圆心 /
	# 半径 / 角点 / 顶点）。
	if gpSelection.size() == 1:
		var gpGrips: Array[Dictionary] = _gpShapeGrips(gpSelection[0])
		for gpG in gpGrips:
			var gpPos: Vector2 = gpG["pos"] as Vector2
			draw_rect(Rect2(gpPos - Vector2(4, 4), Vector2(8, 8)), Color(1, 1, 1, 1), true)
			draw_rect(Rect2(gpPos - Vector2(4, 4), Vector2(8, 8)), gpSelCol, false, 1.5)

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

	# Rubber band for circle / rect / line drags.
	# 圆 / 矩形 / 直线拖拽的橡皮筋。
	if _gpDragging:
		if gpTool == GPTool.GP_CIRCLE:
			draw_circle(_gpDragFrom, _gpDragFrom.distance_to(_gpCursor), Color(gpDraftCol, 0.7), false, 1.0)
		elif gpTool == GPTool.GP_LINE:
			draw_line(_gpDragFrom, _gpCursor, Color(gpDraftCol, 0.7), 2.0)
		else:
			draw_rect(Rect2(_gpDragFrom, _gpCursor - _gpDragFrom).abs(), Color(gpDraftCol, 0.7), false, 1.0)

	# Marquee rectangle (top-most overlay).
	# 框选矩形（最上层叠层）。
	if _gpMarqueeing:
		var gpMr: Rect2 = Rect2(_gpMarqueeFrom, _gpMarqueeTo - _gpMarqueeFrom).abs()
		draw_rect(gpMr, Color(gpSelCol, 0.8), false, 1.0)
		draw_rect(gpMr, Color(gpSelCol, 0.12), true)

	# Ports.
	# 端口。
	for gpP in gpPorts:
		var gpPos: Vector2 = gpP["pos"]
		draw_circle(gpPos, 4.0, gpPortCol)
		draw_circle(gpPos, 7.0, Color(gpPortCol, 0.35), false, 1.0)
