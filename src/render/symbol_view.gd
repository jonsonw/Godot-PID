class_name GPSymbolView
extends Node2D

# Visual representation of one P&ID symbol instance.
# 单个 P&ID 图元实例的可视化表示。
# A thin view node: it only projects the underlying GPPIDGraph node onto the screen.
# 薄视图节点：仅把底层 GPPIDGraph 节点投影到屏幕上。
# It does not own authoritative state; the graph is the single source of truth.
# 它不持有权威状态；图数据是唯一真相来源。

var gpNodeId: String = ""
var gpNode: Dictionary = {}
var gpDef: GPSymbolDef = null
var gpSelected: bool = false
var gpConnectSource: bool = false


# Bind this view to a graph node and its definition.
# 将本视图绑定到一个图节点及其定义。
func gpInit(gpN: Dictionary, gpD: GPSymbolDef) -> void:
	gpNode = gpN
	gpNodeId = gpN.get("id", "")
	gpDef = gpD
	name = "Symbol_" + gpNodeId
	_gpUpdateTransform()
	queue_redraw()


# Update selection highlight state and redraw.
# 更新选中高亮状态并重绘。
func gpSetSelected(gpSel: bool) -> void:
	gpSelected = gpSel
	queue_redraw()


# Update "connection source" highlight state and redraw.
# 更新「连接源」高亮状态并重绘。
func gpSetConnectSource(gpSrc: bool) -> void:
	gpConnectSource = gpSrc
	queue_redraw()


# Sync the world position from the underlying graph node.
# 从底层图节点同步世界坐标位置。
func gpUpdateTransform() -> void:
	_gpUpdateTransform()


func _gpUpdateTransform() -> void:
	if gpNode.is_empty():
		return
	var gpPos: Array = gpNode.get("pos", [0.0, 0.0])
	position = Vector2(float(gpPos[0]), float(gpPos[1]))


func _draw() -> void:
	var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
	var gpTopleft: Vector2 = -gpSz / 2.0
	var gpRect: Rect2 = Rect2(gpTopleft, gpSz)

	var gpBaseCol: Color = _gpCategoryColor(gpDef.gpCategory) if gpDef != null else Color(0.6, 0.6, 0.6)
	var gpFill: Color = gpBaseCol
	if gpSelected:
		gpFill = Color(1.0, 0.85, 0.2)
	elif gpConnectSource:
		gpFill = Color(0.3, 1.0, 0.4)

	# Border width is kept constant in world units; world_root scale makes it zoom uniformly.
	# 边框宽度保持世界单位常量；world_root 的缩放使其统一随缩放变化。
	var gpBorder: float = 2.0
	draw_rect(gpRect, gpFill, true)
	draw_rect(gpRect, Color(0.05, 0.05, 0.05), false, gpBorder)

	var gpLabel: String
	if gpNode.get("label", "") != "":
		gpLabel = gpNode["label"]
	elif gpDef != null:
		gpLabel = I18n.gpTr(gpDef.gpDisplayName)
	else:
		gpLabel = gpNode.get("type", "")

	var gpFont: Font = Settings.gpSymbolFont if Settings.gpSymbolFont != null else ThemeDB.fallback_font
	var gpFontSz: int = maxi(1, Settings.gpSymbolFontSize)
	var gpTp: Vector2 = gpTopleft + Vector2(0.0, gpSz.y / 2.0 + 7.0)
	draw_string(gpFont, gpTp, gpLabel, HORIZONTAL_ALIGNMENT_CENTER, gpSz.x, gpFontSz, Color(0.07, 0.07, 0.07))

	if gpDef != null:
		var gpPortR: float = 4.0
		for gpP in gpDef.gpPorts:
			var gpLp: Vector2 = Vector2(float(gpP["pos"][0]), float(gpP["pos"][1]))
			draw_circle(gpLp, gpPortR, Color(0.1, 0.1, 0.1))


func _gpCategoryColor(gpCat: String) -> Color:
	match gpCat:
		"pump":       return Color(0.30, 0.62, 0.95)
		"tank":       return Color(0.40, 0.80, 0.55)
		"valve":      return Color(0.95, 0.65, 0.25)
		"instrument": return Color(0.85, 0.45, 0.85)
		"heat":       return Color(0.95, 0.45, 0.45)
		_:            return Color(0.65, 0.68, 0.75)
