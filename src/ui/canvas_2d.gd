class_name Canvas2D
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

signal graph_changed

enum Mode { SELECT, CONNECT }

var graph: PIDGraph
var defs: Array[SymbolDef] = []
var next_id: int = 1

# ---- camera ----
# ---- 相机 ----
var view_offset: Vector2 = Vector2.ZERO
var view_zoom: float = 1.0

# ---- interaction state ----
# ---- 交互状态 ----
var mode: int = Mode.SELECT
var pending_def: SymbolDef = null
var selected_id: String = ""
var connect_from: String = ""

var _panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _pan_offset_start: Vector2 = Vector2.ZERO
var _drag_id: String = ""
var _drag_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP


# ============================ transform ============================
# ============================ 坐标变换 ============================
func screen_from_world(w: Vector2) -> Vector2:
	return w * view_zoom + view_offset


func world_from_screen(s: Vector2) -> Vector2:
	return (s - view_offset) / view_zoom


# ============================ drawing ============================
# ============================ 绘制 ============================
func _draw() -> void:
	if graph == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.14, 0.18))
	_draw_grid()

	for e in graph.edges:
		var a: Vector2 = _node_center(e["from"])
		var b: Vector2 = _node_center(e["to"])
		if a == Vector2.INF or b == Vector2.INF:
			continue
		draw_line(screen_from_world(a), screen_from_world(b), Color(0.70, 0.75, 0.85), 2.0)

	for n in graph.nodes:
		_draw_node(n)

	if mode == Mode.CONNECT and connect_from != "":
		var c: Vector2 = _node_center(connect_from)
		if c != Vector2.INF:
			draw_line(screen_from_world(c), get_local_mouse_position(), Color(0.30, 1.0, 0.40), 1.5)


func _draw_grid() -> void:
	var step: float = 50.0 * view_zoom
	if step < 8.0:
		return
	var start_x: int = int(fmod(view_offset.x, step))
	var start_y: int = int(fmod(view_offset.y, step))
	var col: Color = Color(0.22, 0.24, 0.30, 0.6)
	var x: int = start_x
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
		x += int(step)
	var y: int = start_y
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), col, 1.0)
		y += int(step)


func _draw_node(n: Dictionary) -> void:
	var def: SymbolDef = _def_for(n["type"])
	var center: Vector2 = Vector2(n["pos"][0], n["pos"][1])
	var sz: Vector2 = def.default_size if def else Vector2(64, 48)
	sz *= view_zoom
	var topleft: Vector2 = screen_from_world(center) - sz / 2.0
	var rect: Rect2 = Rect2(topleft, sz)

	var base_col: Color = _category_color(def.category) if def else Color(0.6, 0.6, 0.6)
	var fill: Color = base_col
	if n["id"] == selected_id:
		fill = Color(1.0, 0.85, 0.2)
	elif n["id"] == connect_from:
		fill = Color(0.3, 1.0, 0.4)

	draw_rect(rect, fill, true)
	draw_rect(rect, Color(0.05, 0.05, 0.05), false, 2.0)

	var label: String
	if n["label"] != "":
		label = n["label"]
	elif def:
		label = def.display_name
	else:
		label = n["type"]
	var tp: Vector2 = topleft + Vector2(0, sz.y / 2.0 + 7.0)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 14, Color(0.07, 0.07, 0.07))

	if def:
		for p in def.ports:
			var lp: Vector2 = Vector2(p["pos"][0], p["pos"][1]) * view_zoom
			draw_circle(screen_from_world(center) + lp, 4.0, Color(0.1, 0.1, 0.1))


func _category_color(cat: String) -> Color:
	match cat:
		"pump":       return Color(0.30, 0.62, 0.95)
		"tank":       return Color(0.40, 0.80, 0.55)
		"valve":      return Color(0.95, 0.65, 0.25)
		"instrument": return Color(0.85, 0.45, 0.85)
		"heat":       return Color(0.95, 0.45, 0.45)
		_:            return Color(0.65, 0.68, 0.75)


# ============================ lookup ============================
# ============================ 查找 ============================
func _def_for(type_id: String) -> SymbolDef:
	for d in defs:
		if d.id == type_id:
			return d
	return null


func _node_center(id: String) -> Vector2:
	for n in graph.nodes:
		if n["id"] == id:
			return Vector2(n["pos"][0], n["pos"][1])
	return Vector2.INF


func _hit_test(world: Vector2) -> String:
	var best: String = ""
	for n in graph.nodes:
		var def: SymbolDef = _def_for(n["type"])
		var sz: Vector2 = def.default_size if def else Vector2(64, 48)
		var c: Vector2 = Vector2(n["pos"][0], n["pos"][1])
		var rect: Rect2 = Rect2(c - sz / 2.0, sz)
		if rect.has_point(world):
			best = n["id"]
	return best


func _set_node_pos(id: String, world: Vector2) -> void:
	for n in graph.nodes:
		if n["id"] == id:
			n["pos"] = [world.x, world.y]
			return


# ============================ input ============================
# ============================ 输入 ============================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var factor: float = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				_zoom_at(event.position, factor)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_panning = true
				_pan_start = event.position
				_pan_offset_start = view_offset
			else:
				_panning = false
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_down(event.position)
			else:
				_drag_id = ""
			accept_event()
			return

	if event is InputEventMouseMotion:
		if _panning:
			view_offset = _pan_offset_start + (event.position - _pan_start)
			queue_redraw()
			accept_event()
			return
		if _drag_id != "":
			var world: Vector2 = world_from_screen(event.position)
			_set_node_pos(_drag_id, world + _drag_offset)
			queue_redraw()
			accept_event()
			return


func _on_left_down(screen: Vector2) -> void:
	var world: Vector2 = world_from_screen(screen)

	if pending_def != null:
		var nid: String = "n%d" % next_id
		next_id += 1
		graph.add_node(nid, pending_def.id, pending_def.display_name, world, {})
		selected_id = nid
		pending_def = null
		queue_redraw()
		graph_changed.emit()
		return

	var hit: String = _hit_test(world)

	if mode == Mode.CONNECT:
		if hit != "":
			if connect_from == "":
				connect_from = hit
			else:
				if connect_from != hit:
					var eid: String = "e%d" % next_id
					next_id += 1
					graph.add_edge(eid, connect_from, hit, {})
					graph_changed.emit()
				connect_from = ""
				queue_redraw()
		return

	# SELECT
	# 选择模式
	selected_id = hit
	if hit != "":
		_drag_id = hit
		_drag_offset = _node_center(hit) - world
	queue_redraw()


func _zoom_at(screen: Vector2, factor: float) -> void:
	var world_before: Vector2 = world_from_screen(screen)
	view_zoom *= (1.0 + 0.12 * factor)
	view_zoom = clamp(view_zoom, 0.25, 4.0)
	var screen_after: Vector2 = screen_from_world(world_before)
	view_offset += screen - screen_after
	queue_redraw()
