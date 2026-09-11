class_name GPSymbolView
extends Node2D

# Visual representation of one P&ID symbol instance.
# 单个 P&ID 图元实例的可视化表示。
# A thin view node: it only projects the underlying GPPIDGraph node onto the screen.
# 薄视图节点：仅把底层 GPPIDGraph 节点投影到屏幕上。
# It does not own authoritative state; the graph is the single source of truth.
# 它不持有权威状态；图数据是唯一真相来源。
#
# Two layers on purpose / 刻意分两层：
#   this node  : world position + the label (upright, never mirrored, so text stays readable)
#   _gpBody    : flip + rotation + the glyph + the port dots
#   本节点    ：世界坐标 + 标签（始终正立、绝不镜像，故文字可读）
#   _gpBody   ：翻转 + 旋转 + 字形 + 端口圆点
# See GPSymbolBody for why the split is necessary.
# 拆分的原因见 GPSymbolBody。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Vertical distance from the envelope bottom to the label baseline.
# 包络底边到标签基线的垂直距离。
const GP_LABEL_GAP: float = 7.0

# Port dot radius (world units).
# 端口圆点半径（世界单位）。
const GP_PORT_R: float = 4.0

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

# Child layer that carries flip + rotation.
# 承载翻转与旋转的子层。
var _gpBody: GPSymbolBody = null


# Bind this view to a graph node and its definition.
# 将本视图绑定到一个图节点及其定义。
func gpInit(gpN: GPPIDNode, gpD: GPSymbolDef) -> void:
	gpNode = gpN
	gpNodeId = gpN.gpInstanceId
	gpDef = gpD
	name = "Symbol_" + gpNodeId
	if _gpBody == null:
		_gpBody = GPSymbolBody.new()
		_gpBody.gpView = self
		_gpBody.name = "Body"
		add_child(_gpBody)
	_gpUpdateTransform()
	gpRepaint()


# Update selection highlight state and redraw.
# 更新选中高亮状态并重绘。
func gpSetSelected(gpSel: bool) -> void:
	gpSelected = gpSel
	gpRepaint()


# Update "connection source" highlight state and redraw.
# 更新「连接源」高亮状态并重绘。
func gpSetConnectSource(gpSrc: bool) -> void:
	gpConnectSource = gpSrc
	gpRepaint()


# Public wrapper to sync the world position from the graph node.
# 公开包装：从图节点同步世界坐标位置。
func gpUpdateTransform() -> void:
	_gpUpdateTransform()


# Repaint BOTH layers: this node paints the label, the body child paints the glyph and the
# ports. Without it, "overwrite a symbol definition" refreshes the label but leaves the old
# geometry on screen.
# 重绘「两层」：本节点画标签，body 子节点画字形与端口。少了它，「覆盖图元定义」
# 只会刷新标签，而屏幕上仍留着旧几何。
#
# Why not override queue_redraw() / 为何不覆写 queue_redraw()：
#   Godot rejects it ("overrides a method from native class ... won't be called by the engine"),
#   and it would be a lie anyway: the engine would keep repainting only this node. An explicit
#   second entry point is honest about what it does.
#   Godot 会拒绝（"overrides a method from native class ... won't be called by the engine"），
#   而且那样做本身就是假的：引擎仍只会重绘本节点。显式的第二个入口才如实表达其行为。
func gpRepaint() -> void:
	queue_redraw()
	if _gpBody != null:
		_gpBody.queue_redraw()


# Sync position, flip and rotation from the underlying graph node.
# 从底层图节点同步位置、翻转与旋转。
func _gpUpdateTransform() -> void:
	if gpNode == null:
		return
	position = gpNode.gpPosition
	if _gpBody == null:
		return
	# Mirror first (in the symbol's own frame), then rotate — the SAME order GPPortResolver
	# uses, otherwise a flipped-and-rotated valve's ports land on the wrong side of the glyph.
	# 先镜像（在图元自身坐标系内），再旋转 —— 与 GPPortResolver 所用顺序一致，
	# 否则「先翻转再旋转」的阀门端口会落在字形的错误一侧。
	_gpBody.scale = Vector2(-1.0, 1.0) if gpNode.gpFlipped else Vector2.ONE
	_gpBody.rotation = deg_to_rad(gpNode.gpRotationDeg)


# Draw the label only. The glyph and the ports are painted by the body child.
# 仅绘制标签。字形与端口由 body 子节点绘制。
func _draw() -> void:
	if gpNode == null:
		return

	# M10b: the label is the TAG, resolved through the shared geometry module so the canvas,
	# the grip and the headless tests all agree on where it goes.
	# M10b：标签即**位号**，经共用的几何模块解析，使画布、抓取点与 headless 测试
	# 对「它画在哪」完全一致。
	var gpLabel: String = GPLabelGripOps.gpLabelText(gpNode, gpDef, I18n.gpLocale)
	if gpLabel == "":
		return

	# The anchor rides in the symbol's own frame, so it is transformed by hand here: this node
	# carries no rotation, by design (see the header).
	# 锚点位于图元自身坐标系，故在此手工变换：本节点按设计不承载旋转（见文件头）。
	var gpAnchor: int = GPLabelGripOps.gpEffectiveAnchor(gpNode, gpDef)
	var gpOff: Vector2 = GPLabelGripOps.gpLocalOffset(gpNode, gpDef)
	if gpNode.gpFlipped:
		gpOff.x = -gpOff.x
	gpOff = gpOff.rotated(deg_to_rad(gpNode.gpRotationDeg))

	var gpFont: Font = Settings.gpSymbolFont if Settings.gpSymbolFont != null else ThemeDB.fallback_font
	var gpFontSz: int = maxi(1, Settings.gpSymbolFontSize)
	# Measure first, then place the text relative to the anchor per its alignment.
	# 先测量，再按对齐方式把文字摆到锚点的相应位置。
	var gpSzText: Vector2 = gpFont.get_string_size(gpLabel, HORIZONTAL_ALIGNMENT_LEFT, -1.0, gpFontSz)
	var gpOrigin: Vector2 = gpOff + GPLabelGripOps.gpTextOrigin(gpAnchor, Vector2.ZERO, gpSzText)
	draw_string(gpFont, gpOrigin, gpLabel, GPLabelGripOps.gpAlignFor(gpAnchor),
		-1.0, gpFontSz, Color(0.9, 0.9, 0.9))

	# The drag handle, only while selected — same visual language as the edge grips.
	# 仅在选中时绘制拖拽手柄 —— 与边抓取点同一套视觉语言。
	if gpSelected:
		var gpHalf: float = GPLabelGripOps.GP_GRIP_SIZE * 0.5
		draw_rect(Rect2(gpOff - Vector2(gpHalf, gpHalf),
			Vector2(GPLabelGripOps.GP_GRIP_SIZE, GPLabelGripOps.GP_GRIP_SIZE)),
			Color(1.0, 1.0, 1.0), true)
		draw_rect(Rect2(gpOff - Vector2(gpHalf, gpHalf),
			Vector2(GPLabelGripOps.GP_GRIP_SIZE, GPLabelGripOps.GP_GRIP_SIZE)),
			GPLabelGripOps.GP_COL, false, 1.5)


# Paint the glyph and the port dots. Called by GPSymbolBody._draw(), i.e. inside the flipped /
# rotated frame, which is exactly what port placement needs.
# 绘制字形与端口圆点。由 GPSymbolBody._draw() 调用，即在「已翻转 / 已旋转」的坐标系内，
# 这正是端口定位所需要的。
func gpDrawBody(gpCv: CanvasItem) -> void:
	if gpCv == null:
		return
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
		GPSymbolPainter.gpDrawShape(gpCv, gpDef.gpShapeSpec(), gpRect, gpFill, gpStroke, gpBorder)
	else:
		gpCv.draw_rect(gpRect, gpFill, true)
		gpCv.draw_rect(gpRect, gpStroke, false, gpBorder)

	# Draw connection ports if the symbol definition provides them.
	# 如果图元定义提供了端口，则绘制连接端口。
	# Positions come from GPPortResolver — the SAME source GPEdgeView uses for the pipe ends, so
	# a dot can never drift away from the pipe that lands on it.
	# 位置取自 GPPortResolver —— 与 GPEdgeView 计算管线端点所用的同一来源，
	# 故圆点永不会与落在它上面的管线脱开。
	if gpDef != null:
		for gpP in gpDef.gpPorts:
			var gpLp: Vector2 = GPPortResolver.gpPortLocalOriented(gpDef, gpNode, gpP)
			gpCv.draw_circle(gpLp, GP_PORT_R, GPEdgeStyle.gpPortColor(gpP.gpType))
