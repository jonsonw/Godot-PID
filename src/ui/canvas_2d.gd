class_name GPCanvas2D
extends Control

# 2D drawing canvas, implemented with Control plus a manual camera (pan offset + zoom).
# 2D 画布：用 Control 配合手动相机（平移偏移 + 缩放）实现。
# Reads PIDGraph (node-edge data) and renders symbols and connections by SymbolDef.
# 读取 PIDGraph（节点-边数据），按 SymbolDef 渲染符号与连线。
# Interaction: wheel to zoom, middle-drag to pan, pick a symbol then click to place,
# connect mode clicks two symbols in turn.
# 交互：滚轮缩放 · 中键拖拽平移 · 选符号后点画布放置 · 连接模式依次点两个符号。
#
# Coding rule: every variable must declare its type explicitly (including container types).
# 编码规范：所有变量均显式声明类型（含容器类型）。

signal gpGraphChanged

enum GPMode { GP_SELECT, GP_CONNECT }

var gpGraph: GPPIDGraph
var gpDefs: Array[GPSymbolDef] = []
var gpNextId: int = 1

# ---- camera ----
# ---- 相机 ----
var gpViewOffset: Vector2 = Vector2.ZERO
var gpViewZoom: float = 1.0

# ---- interaction state ----
# ---- 交互状态 ----
var gpMode: int = GPMode.GP_SELECT
var gpPendingDef: GPSymbolDef = null
var gpSelectedId: String = ""
var gpConnectFrom: String = ""

var _gpPanning: bool = false
var _gpPanStart: Vector2 = Vector2.ZERO
var _gpPanOffsetStart: Vector2 = Vector2.ZERO
var _gpDragId: String = ""
var _gpDragOffset: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP


# ============================ transform ============================
# ============================ 坐标变换 ============================
func gpScreenFromWorld(w: Vector2) -> Vector2:
	return w * gpViewZoom + gpViewOffset


func gpWorldFromScreen(gpS: Vector2) -> Vector2:
	return (gpS - gpViewOffset) / gpViewZoom


# ============================ drawing ============================
# ============================ 绘制 ============================
func _draw() -> void:
	if gpGraph == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.14, 0.18))
	_gpDrawGrid()

	for gpE in gpGraph.gpEdges:
		var gpA: Vector2 = _gpNodeCenter(gpE["from"])
		var gpB: Vector2 = _gpNodeCenter(gpE["to"])
		if gpA == Vector2.INF or gpB == Vector2.INF:
			continue
		draw_line(gpScreenFromWorld(gpA), gpScreenFromWorld(gpB), Color(0.70, 0.75, 0.85), 2.0)

	for gpN in gpGraph.gpNodes:
		_gpDrawNode(gpN)

	if gpMode == GPMode.GP_CONNECT and gpConnectFrom != "":
		var gpC: Vector2 = _gpNodeCenter(gpConnectFrom)
		if gpC != Vector2.INF:
			draw_line(gpScreenFromWorld(gpC), get_local_mouse_position(), Color(0.30, 1.0, 0.40), 1.5)


func _gpDrawGrid() -> void:
	var gpStep: float = 50.0 * gpViewZoom
	if gpStep < 8.0:
		return
	var gpStartX: int = int(fmod(gpViewOffset.x, gpStep))
	var gpStartY: int = int(fmod(gpViewOffset.y, gpStep))
	var gpCol: Color = Color(0.22, 0.24, 0.30, 0.6)
	var x: int = gpStartX
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), gpCol, 1.0)
		x += int(gpStep)
	var y: int = gpStartY
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), gpCol, 1.0)
		y += int(gpStep)


func _gpDrawNode(gpN: Dictionary) -> void:
	var gpDef: GPSymbolDef = _gpDefFor(gpN["type"])
	var gpCenter: Vector2 = Vector2(gpN["pos"][0], gpN["pos"][1])
	var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef else Vector2(64, 48)
	gpSz *= gpViewZoom
	var gpTopleft: Vector2 = gpScreenFromWorld(gpCenter) - gpSz / 2.0
	var gpRect: Rect2 = Rect2(gpTopleft, gpSz)

	var gpBaseCol: Color = _gpCategoryColor(gpDef.gpCategory) if gpDef else Color(0.6, 0.6, 0.6)
	var gpFill: Color = gpBaseCol
	if gpN["id"] == gpSelectedId:
		gpFill = Color(1.0, 0.85, 0.2)
	elif gpN["id"] == gpConnectFrom:
		gpFill = Color(0.3, 1.0, 0.4)

	draw_rect(gpRect, gpFill, true)
	draw_rect(gpRect, Color(0.05, 0.05, 0.05), false, 2.0)

	var gpLabel: String
	if gpN["label"] != "":
		gpLabel = gpN["label"]
	elif gpDef:
		gpLabel = gpDef.gpDisplayName
	else:
		gpLabel = gpN["type"]
	var gpTp: Vector2 = gpTopleft + Vector2(0, gpSz.y / 2.0 + 7.0)
	var gpFont: Font = ThemeDB.fallback_font
	draw_string(gpFont, gpTp, gpLabel, HORIZONTAL_ALIGNMENT_CENTER, gpSz.x, 14, Color(0.07, 0.07, 0.07))

	if gpDef:
		for gpP in gpDef.gpPorts:
			var gpLp: Vector2 = Vector2(gpP["pos"][0], gpP["pos"][1]) * gpViewZoom
			draw_circle(gpScreenFromWorld(gpCenter) + gpLp, 4.0, Color(0.1, 0.1, 0.1))


func _gpCategoryColor(gpCat: String) -> Color:
	match gpCat:
		"pump":       return Color(0.30, 0.62, 0.95)
		"tank":       return Color(0.40, 0.80, 0.55)
		"valve":      return Color(0.95, 0.65, 0.25)
		"instrument": return Color(0.85, 0.45, 0.85)
		"heat":       return Color(0.95, 0.45, 0.45)
		_:            return Color(0.65, 0.68, 0.75)


# ============================ lookup ============================
# ============================ 查找 ============================
func _gpDefFor(gpTypeId: String) -> GPSymbolDef:
	for gpD in gpDefs:
		if gpD.gpId == gpTypeId:
			return gpD
	return null


func _gpNodeCenter(gpId: String) -> Vector2:
	for gpN in gpGraph.gpNodes:
		if gpN["id"] == gpId:
			return Vector2(gpN["pos"][0], gpN["pos"][1])
	return Vector2.INF


func _gpHitTest(gpWorld: Vector2) -> String:
	var gpBest: String = ""
	for gpN in gpGraph.gpNodes:
		var gpDef: GPSymbolDef = _gpDefFor(gpN["type"])
		var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef else Vector2(64, 48)
		var gpC: Vector2 = Vector2(gpN["pos"][0], gpN["pos"][1])
		var gpRect: Rect2 = Rect2(gpC - gpSz / 2.0, gpSz)
		if gpRect.has_point(gpWorld):
			gpBest = gpN["id"]
	return gpBest


func _gpSetNodePos(gpId: String, gpWorld: Vector2) -> void:
	for gpN in gpGraph.gpNodes:
		if gpN["id"] == gpId:
			gpN["pos"] = [gpWorld.x, gpWorld.y]
			return


# ============================ input ============================
# ============================ 输入 ============================
func _gui_input(gpEvent: InputEvent) -> void:
	if gpEvent is InputEventMouseButton:
		if gpEvent.button_index == MOUSE_BUTTON_WHEEL_UP or gpEvent.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if gpEvent.pressed:
				var gpFactor: float = 1.0 if gpEvent.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				_gpZoomAt(gpEvent.position, gpFactor)
			accept_event()
			return
		if gpEvent.button_index == MOUSE_BUTTON_MIDDLE:
			if gpEvent.pressed:
				_gpPanning = true
				_gpPanStart = gpEvent.position
				_gpPanOffsetStart = gpViewOffset
			else:
				_gpPanning = false
			accept_event()
			return
		if gpEvent.button_index == MOUSE_BUTTON_LEFT:
			if gpEvent.pressed:
				_gpOnLeftDown(gpEvent.position)
			else:
				_gpDragId = ""
			accept_event()
			return

	if gpEvent is InputEventMouseMotion:
		if _gpPanning:
			gpViewOffset = _gpPanOffsetStart + (gpEvent.position - _gpPanStart)
			queue_redraw()
			accept_event()
			return
		if _gpDragId != "":
			var gpWorld: Vector2 = gpWorldFromScreen(gpEvent.position)
			_gpSetNodePos(_gpDragId, gpWorld + _gpDragOffset)
			queue_redraw()
			accept_event()
			return


func _gpOnLeftDown(gpScreen: Vector2) -> void:
	var gpWorld: Vector2 = gpWorldFromScreen(gpScreen)

	if gpPendingDef != null:
		var gpNid: String = "n%d" % gpNextId
		gpNextId += 1
		gpGraph.gpAddNode(gpNid, gpPendingDef.gpId, gpPendingDef.gpDisplayName, gpWorld, {})
		gpSelectedId = gpNid
		gpPendingDef = null
		queue_redraw()
		gpGraphChanged.emit()
		return

	var gpHit: String = _gpHitTest(gpWorld)

	if gpMode == GPMode.GP_CONNECT:
		if gpHit != "":
			if gpConnectFrom == "":
				gpConnectFrom = gpHit
			else:
				if gpConnectFrom != gpHit:
					var gpEid: String = "e%d" % gpNextId
					gpNextId += 1
					gpGraph.gpAddEdge(gpEid, gpConnectFrom, gpHit, {})
					gpGraphChanged.emit()
				gpConnectFrom = ""
				queue_redraw()
		return

	# SELECT
	# 选择模式
	gpSelectedId = gpHit
	if gpHit != "":
		_gpDragId = gpHit
		_gpDragOffset = _gpNodeCenter(gpHit) - gpWorld
	queue_redraw()


func _gpZoomAt(gpScreen: Vector2, gpFactor: float) -> void:
	var gpWorldBefore: Vector2 = gpWorldFromScreen(gpScreen)
	gpViewZoom *= (1.0 + 0.12 * gpFactor)
	gpViewZoom = clamp(gpViewZoom, 0.25, 4.0)
	var gpScreenAfter: Vector2 = gpScreenFromWorld(gpWorldBefore)
	gpViewOffset += gpScreen - gpScreenAfter
	queue_redraw()
