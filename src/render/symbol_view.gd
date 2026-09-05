class_name GPSymbolView
extends Node2D

# Visual representation of one P&ID symbol instance.
# 单个 P&ID 图元实例的可视化表示。
# A thin view node: it only projects the underlying GPPIDGraph node onto the screen.
# 薄视图节点：仅把底层 GPPIDGraph 节点投影到屏幕上。
# It does not own authoritative state; the graph is the single source of truth.
# 它不持有权威状态；图数据是唯一真相来源。

# Bound graph node id.
# 绑定的图节点 id。
var gpNodeId: String = ""

# Bound graph node object (strongly typed; the single source of truth).
# 绑定的图节点对象（强类型；唯一真相来源）。
var gpNode: GPPIDNode = null

# Bound symbol definition (may be null for unknown types).
# 绑定的图元定义（未知类型时可能为 null）。
var gpDef: GPSymbolDef = null

# Whether this symbol is currently selected.
# 当前是否被选中。
var gpSelected: bool = false

# Whether this symbol is the source of an in-progress connection.
# 当前是否为正在进行的连线的起点。
var gpConnectSource: bool = false


# Bind this view to a graph node and its definition.
# 将本视图绑定到一个图节点及其定义。
func gpInit(gpN: GPPIDNode, gpD: GPSymbolDef) -> void:
	gpNode = gpN
	gpNodeId = gpN.gpInstanceId
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


# Public wrapper to sync the world position from the graph node.
# 公开包装：从图节点同步世界坐标位置。
func gpUpdateTransform() -> void:
	_gpUpdateTransform()


# Sync position from the underlying graph node.
# 从底层图节点同步位置。
func _gpUpdateTransform() -> void:
	if gpNode == null:
		return
	position = gpNode.gpPosition


# Draw the symbol shape, label, ports and highlights.
# 绘制图元形状、标签、端口和高亮。
func _draw() -> void:
	var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
	var gpTopleft: Vector2 = -gpSz / 2.0
	var gpRect: Rect2 = Rect2(gpTopleft, gpSz)

	# Resolve base color and override it when selected or acting as connect source.
	# 解析基础颜色，并在选中或作为连线起点时覆盖为高亮色。
	var gpBaseCol: Color = GPSymbolPainter.gpCategoryColor(gpDef.gpCategory) if gpDef != null else Color(0.6, 0.6, 0.6)
	var gpFill: Color = gpBaseCol
	var gpStroke: Color = gpBaseCol.lightened(0.25)
	if gpSelected:
		gpFill = Color(1.0, 0.85, 0.2)
		gpStroke = Color(1.0, 1.0, 1.0)
	elif gpConnectSource:
		gpFill = Color(0.3, 1.0, 0.4)
		gpStroke = Color(1.0, 1.0, 1.0)

	# Border width is kept constant in world units; world_root scale makes it zoom uniformly.
	# 边框宽度保持世界单位常量；world_root 的缩放使其统一随缩放变化。
	var gpBorder: float = 2.0

	# If the definition carries a vector shape spec, render it natively (crisp at any zoom).
	# 若定义带有矢量形状规格，则原生渲染（任意缩放均清晰）。
	if gpDef != null and not gpDef.gpShapes.is_empty():
		GPSymbolPainter.gpDrawShape(self, gpDef.gpShapeSpec(), gpRect, gpFill, gpStroke, gpBorder)
	else:
		draw_rect(gpRect, gpFill, true)
		draw_rect(gpRect, gpStroke, false, gpBorder)

	# Resolve the label: custom label -> localized display name -> type id.
	# 解析标签：自定义标签 → 本地化显示名 → 类型 id。
	var gpLabel: String
	if gpNode.gpTag != "":
		gpLabel = gpNode.gpTag
	elif gpDef != null:
		gpLabel = I18n.gpTr(gpDef.gpDisplayName)
	else:
		gpLabel = gpNode.gpSymbolId

	# Draw the label below the symbol, horizontally centered, for every category.
	# 所有类目的标签均绘制在图元正下方、水平居中。
	var gpFont: Font = Settings.gpSymbolFont if Settings.gpSymbolFont != null else ThemeDB.fallback_font
	var gpFontSz: int = maxi(1, Settings.gpSymbolFontSize)
	var gpTp: Vector2 = gpTopleft + Vector2(0.0, gpSz.y / 2.0 + 7.0)
	draw_string(gpFont, gpTp, gpLabel, HORIZONTAL_ALIGNMENT_CENTER, gpSz.x, gpFontSz, Color(0.9, 0.9, 0.9))

	# Draw connection ports if the symbol definition provides them.
	# 如果图元定义提供了端口，则绘制连接端口。
	# Port positions are normalized 0..1 against the nominal envelope; gpPortLocal folds them
	# into node-centered pixel offsets, so every family member's ports stay aligned.
	# 端口位置相对标称包络归一化到 0..1；gpPortLocal 将其折算为节点中心像素偏移，
	# 因此同族成员的端口始终对齐。
	if gpDef != null:
		var gpPortR: float = 4.0
		for gpP in gpDef.gpPorts:
			var gpLp: Vector2 = gpDef.gpPortLocal(gpP)
			draw_circle(gpLp, gpPortR, gpStroke)
