class_name GPEdgeView
extends Node2D

# Visual representation of one P&ID edge (pipe, utility line or signal line).
# 一条 P&ID 连线（工艺管道、公用工程管线或信号线）的可视化表示。
# Lives under the same world_root as GPSymbolView so it scales and pans automatically.
# 与 GPSymbolView 同处一个 world_root 下，因此自动随其缩放与平移。
#
# This node draws in WORLD coordinates (its own transform stays identity; the zoom lives on
# world_root), so every width that must stay legible has to be divided by gpZoom — see
# GPEdgeStyle.GP_MIN_PX and the halo/arrow floors below.
# 本节点以世界坐标绘制（自身变换恒为单位，缩放位于 world_root 上），故任何「必须保持可读」
# 的宽度都要除以 gpZoom —— 见 GPEdgeStyle.GP_MIN_PX 及下方光晕 / 箭头的下限。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Placeholder shown for a pipe that has no line number yet. A P&ID pipe without a number is
# incomplete, and a silent gap in the drawing is the worst way to say so.
# 尚无编号的管道所显示的占位符。P&ID 中无编号的管道是不完整的，而图纸上「一片空白」
# 是最糟的表达方式。
const GP_TAG_PLACEHOLDER: String = "<?>"

# GPU dashed-line path (Line2D + Linetype shader). Default OFF so the validated CPU
# dash (GPEdgeDash) stays the active renderer; flip to true to use the shader for
# non-selected dashed edges (the perf path for 500+ edges). Selection still paints
# via _draw so the bright outline stays above the ink.
# GPU 虚线路径（Line2D + Linetype 着色器）。默认关闭，使已验证的 CPU 虚线
#（GPEdgeDash）仍为活动渲染器；置 true 即对「非选中虚线边」走着色器（500+ 边时的性能路径）。
# 选中态仍由 _draw 绘制，使亮色描边始终位于墨线之上。
const GP_GPU_DASH: bool = false

# Dashed ink as a Line2D child (only used when GP_GPU_DASH is on). Created once.
# 虚线墨线（仅 GP_GPU_DASH 为真时使用）的 Line2D 子节点，建一次。
var gpInkLine: Line2D = null

# Bound graph edge id.
# 绑定的图边 id。
var gpEdgeId: String = ""

# Bound graph edge object (strongly typed; the single source of truth).
# 绑定的图边对象（强类型；唯一真相来源）。
var gpEdge: GPPIDEdge = null

# Reference to the parent graph (used to look up node positions).
# 父图引用（用于查找节点位置）。
var gpGraph: GPPIDGraph = null

# symbol id -> GPSymbolDef, injected by GPGraphBinder. An invalid Callable degrades every port
# to the node centre (see GPPortResolver) instead of failing.
# 符号 id -> GPSymbolDef，由 GPGraphBinder 注入。Callable 无效时所有端口降级为节点中心
# （见 GPPortResolver）而非失败。
var gpDefLookup: Callable = Callable()

# Current canvas zoom; drives the screen-space floors.
# 当前画布缩放；驱动屏幕空间下限。
var gpZoom: float = 1.0

# Selection / hover / editing state (painted as a halo under the ink).
# 选中 / 悬停 / 编辑状态（以墨线之下的光晕绘制）。
var gpSelected: bool = false
var gpHovered: bool = false

# True while this edge's grip is being dragged (edit state). Drives the distinct orange highlight
# so "selected" and "actively editing" are visually separate.
# 本边抓取点正被拖拽（编辑态）时为真。驱动橙色高亮，使「选中」与「正在编辑」视觉分离。
var gpEditing: bool = false

# Crossing points where THIS line must show a break (断口). Pushed by the binder, which is the
# only party that can see every edge at once. Topology is unaffected — this is paint only.
# 本线须显示为断口的交叉点。由绑定器推送 —— 它是唯一能同时看到所有边的一方。
# 拓扑不受影响 —— 这仅仅是绘制。
var gpBreaks: Array[Vector2] = []


# Replace the break points. Called by GPGraphBinder after each crossing pass.
# 替换断点。由 GPGraphBinder 在每次交叉计算后调用。
func gpSetBreaks(gpPts: Array[Vector2]) -> void:
	gpBreaks = gpPts
	queue_redraw()


# Bind this view to a graph edge.
# 将本视图绑定到一条图边。
func gpInit(gpE: GPPIDEdge, gpG: GPPIDGraph, gpLookup: Callable = Callable()) -> void:
	gpEdge = gpE
	gpEdgeId = gpE.gpInstanceId
	gpGraph = gpG
	gpDefLookup = gpLookup
	name = "Edge_" + gpEdgeId
	queue_redraw()


# Create the (optional) Line2D ink child once, hidden until the GPU dash path uses it.
# 建一次（可选）Line2D 墨线子节点，默认隐藏，待 GPU 虚线路径启用。
func _ready() -> void:
	gpInkLine = Line2D.new()
	gpInkLine.name = "InkGPU"
	gpInkLine.visible = false
	gpInkLine.material = GPLinetypeMaterial.gpMake()
	add_child(gpInkLine)


# Push per-frame view state from the binder.
# 由绑定器逐帧推送视图状态。
func gpSetView(gpZoomIn: float, gpSelectedIn: bool, gpHoveredIn: bool, gpEditingIn: bool = false) -> void:
	gpZoom = maxf(gpZoomIn, 0.01)
	gpSelected = gpSelectedIn
	gpHovered = gpHoveredIn
	gpEditing = gpEditingIn


# The full routed polyline, endpoints included. Exposed so hit-testing and the inspector can
# reuse exactly the geometry that was painted.
# 含端点的完整布线折线。对外暴露，使命中测试与属性面板能复用「真正被画出来的」那份几何。
func gpPolyline() -> PackedVector2Array:
	if gpGraph == null or gpEdge == null:
		return PackedVector2Array()
	var gpWant: String = GPPortResolver.gpWantTypeFor(gpEdge)
	var gpFrom: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpDefLookup, gpEdge, true, gpWant)
	var gpTo: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpDefLookup, gpEdge, false, gpWant)
	return GPEdgeRoute.gpRoute(gpFrom, gpTo, gpEdge.gpRouting, gpEdge.gpOrtho)


# Resolve the two ends once and paint the whole edge.
# 一次性解析两端并绘制整条连线。
func _draw() -> void:
	if gpGraph == null or gpEdge == null:
		return
	var gpWant: String = GPPortResolver.gpWantTypeFor(gpEdge)
	var gpFrom: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpDefLookup, gpEdge, true, gpWant)
	var gpTo: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpDefLookup, gpEdge, false, gpWant)
	var gpPts: PackedVector2Array = GPEdgeRoute.gpRoute(gpFrom, gpTo, gpEdge.gpRouting, gpEdge.gpOrtho)
	if gpPts.size() < 2:
		return
	var gpSt: Dictionary = GPEdgeStyle.gpStyleFor(gpEdge.gpKind, gpEdge.gpSignalType, gpZoom)
	var gpW: float = float(gpSt.get("width", 1.6))
	var gpCol: Color = gpSt.get("color", Color(0.6, 0.65, 0.75))
	var gpPat: PackedFloat32Array = gpSt.get("pattern", PackedFloat32Array())
	# Screen-constant line weight: keep the rendered pixel width fixed across zoom
	# (width / zoom), the "plotting lineweight" mode. Off by default (lines thicken when
	# zoomed in, like a CAD model space). Either way the screen-space floor protects legibility.
	# 屏幕恒定线宽：缩放时渲染像素宽不变（width / zoom），即「出图线宽」模式。默认关闭
	#（线随放大变粗，如同 CAD 模型空间）。两种模式都受屏幕空间下限保护可读性。
	if Settings.gpScreenConstantWidth:
		gpW = gpW / gpZoom
	gpW = maxf(gpW, GPEdgeStyle.GP_MIN_PX / gpZoom)

	# Halo first: drawn UNDER the ink so the line keeps its true weight when selected.
	# 先画光晕：位于墨线之下，使线条在选中时仍保持其真实线重。
	# Editing state (a grip is being dragged) wins over plain selection, then hover.
	# 编辑态（抓取点正拖拽）优先于普通选中，再之后是悬停。
	if gpEditing:
		GPEdgePainter.gpDrawHalo(self, gpPts, GPEdgeStyle.GP_EDIT_HALO, gpW + 13.0 / gpZoom, gpBreaks)
	elif gpSelected:
		GPEdgePainter.gpDrawHalo(self, gpPts, GPEdgeStyle.GP_SEL_HALO, gpW + 11.0 / gpZoom, gpBreaks)
	elif gpHovered:
		GPEdgePainter.gpDrawHalo(self, gpPts, GPEdgeStyle.GP_HOVER_HALO, gpW + 6.0 / gpZoom, gpBreaks)

	# Ink: GPU dashed path (Line2D + shader) for non-selected dashed edges, else the
	# validated CPU dash. Selection still draws via _draw so the bright outline stays on top.
	# 墨线：非选中虚线边走 GPU 虚线路径（Line2D + 着色器），否则走已验证的 CPU 虚线。
	# 选中态仍由 _draw 绘制，使亮色描边位于墨线之上。
	if gpInkLine != null:
		gpInkLine.visible = false
	if GP_GPU_DASH and gpPat.size() >= 2 and gpBreaks.is_empty() and not (gpSelected or gpEditing):
		_gpDrawInkGPU(gpPts, gpCol, gpW, gpPat)
	else:
		GPEdgePainter.gpDrawInk(self, gpPts, gpCol, gpW, gpPat, gpBreaks)

	# Selected / editing: overlay a thin bright core stroke ON TOP of the ink so the WHOLE path
	# lights up (the halo alone can read as just a thicker glow). Keeps the original colour visible.
	# 选中 / 编辑：在墨线之上叠一道细亮描边，使整条路径发亮（仅光晕可能被误读为单纯变粗）。
	# 同时保留原色可见。
	if gpEditing or gpSelected:
		GPEdgePainter.gpDrawInk(self, gpPts, GPEdgeStyle.GP_SEL_OUTLINE, GPEdgeStyle.GP_MIN_PX / gpZoom, PackedFloat32Array(), gpBreaks)

	# A free end is legal but must be visible, otherwise a half-built pipe looks finished.
	# 悬空端合法但必须可见，否则一条只画了一半的管道看起来像是已完成。
	if not bool(gpFrom.get("bound", false)):
		GPEdgePainter.gpDrawDangling(self, gpFrom.get("pos", Vector2.ZERO), GPEdgeStyle.GP_DANGLING, gpZoom)
	if not bool(gpTo.get("bound", false)):
		GPEdgePainter.gpDrawDangling(self, gpTo.get("pos", Vector2.ZERO), GPEdgeStyle.GP_DANGLING, gpZoom)

	# Flow arrow: pipes only. A dashed signal line already carries direction in its styling and
	# an arrow on it reads as a process line.
	# 流向箭头：仅管道。虚线信号线已用线型表达方向，再加箭头会被误读为工艺管线。
	if gpEdge.gpKind != GPPIDEdge.GP_SIGNAL and _gpAttrBool("show_arrow", true):
		GPEdgePainter.gpDrawArrow(self, gpPts, gpCol)

	if _gpShouldDrawTag():
		_gpDrawTag(gpPts, gpCol)


# GPU dashed ink: drive the Line2D child + Linetype shader. The shader dashes along the
# polyline's UV, so the dash phase stays continuous across segments. Selection is NOT drawn
# here (it stays in _draw), so this is only ever called for unselected edges.
# GPU 虚线墨线：驱动 Line2D 子节点 + Linetype 着色器。着色器沿折线 UV 做虚线，故划相位
# 跨段连续。选中态不在此绘制（仍在 _draw），故仅对非选中边调用。
func _gpDrawInkGPU(gpPts: PackedVector2Array, gpColor: Color, gpWidth: float,
		gpPattern: PackedFloat32Array) -> void:
	if gpInkLine == null or gpPts.size() < 2:
		GPEdgePainter.gpDrawInk(self, gpPts, gpColor, gpWidth, gpPattern, gpBreaks)
		return
	gpInkLine.points = gpPts
	gpInkLine.width = gpWidth
	gpInkLine.default_color = gpColor
	gpInkLine.visible = true
	var gpMat: ShaderMaterial = gpInkLine.material as ShaderMaterial
	if gpMat != null and gpMat.shader != null:
		# Min-dash protection in world units so a dash never collapses below one pixel.
		# 世界单位下的最小划长保护，使单段划长不塌缩至一像素以下。
		var gpMin: float = GPEdgeStyle.GP_MIN_DASH_PX / gpZoom
		var gpZoomed: PackedFloat32Array = PackedFloat32Array()
		for gpV in gpPattern:
			gpZoomed.append(maxf(gpV, gpMin))
		gpMat.set_shader_parameter("pattern", gpZoomed)
		gpMat.set_shader_parameter("pattern_count", gpZoomed.size())
		gpMat.set_shader_parameter("linetype_scale", GPLinetypeManager.gpLinetypeScale)
		var gpLen: float = 0.0
		for gpI in range(gpPts.size() - 1):
			gpLen += gpPts[gpI].distance_to(gpPts[gpI + 1])
		gpMat.set_shader_parameter("line_length", maxf(gpLen, 1.0))
		gpMat.set_shader_parameter("color", gpColor)


# Pipes always show a number (placeholder when missing); signal lines stay clean by default.
# 管道始终显示编号（缺失时显示占位符）；信号线默认保持干净。
func _gpShouldDrawTag() -> bool:
	var gpDefault: bool = gpEdge.gpKind != GPPIDEdge.GP_SIGNAL
	return _gpAttrBool("show_tag", gpDefault)


# Paint the line number (or its placeholder) on the longest leg.
# 把管线编号（或其占位符）绘制到最长段上。
func _gpDrawTag(gpPts: PackedVector2Array, gpCol: Color) -> void:
	var gpFont: Font = Settings.gpSymbolFont if Settings.gpSymbolFont != null else ThemeDB.fallback_font
	# Pipe-tag font size overrides the symbol font size when set (>0); otherwise it inherits.
	# 管线位号字号在设置为正时覆盖图元字号，否则继承。
	var gpSize: int = maxi(1, Settings.gpPipeTagFontSize if Settings.gpPipeTagFontSize > 0 else Settings.gpSymbolFontSize)
	var gpText: String = gpEdge.gpTag
	var gpColor: Color = gpCol
	if gpText == "":
		# Unnumbered pipe: shout instead of staying silent.
		# 未编号管道：显式提示，而非沉默。
		gpText = GP_TAG_PLACEHOLDER
		gpColor = GPEdgeStyle.GP_DANGLING
	# The per-edge "tag_rotate" attribute overrides the global default when present; otherwise
	# the global setting decides whether a vertical-run number is rotated.
	# 当边显式带 "tag_rotate" 属性时该属性优先；否则由全局设置决定竖管位号是否旋转。
	var gpRotate: bool = _gpAttrBool("tag_rotate", Settings.gpPipeTagRotate)
	GPEdgePainter.gpDrawTag(self, gpPts, gpText, gpFont, gpSize, gpColor, gpRotate)


# Read a boolean from gpAttrs with a default. Absent key == default, never an error.
# 带默认值地从 gpAttrs 读取布尔值。键不存在即取默认值，绝不报错。
func _gpAttrBool(gpKey: String, gpDefault: bool) -> bool:
	if not gpEdge.gpAttrs.has(gpKey):
		return gpDefault
	return bool(gpEdge.gpAttrs[gpKey])
