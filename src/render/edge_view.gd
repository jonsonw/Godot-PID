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

# The pipe BODY is drawn by a single Line2D child (gpInkLine) for every edge kind. Solid edges use
# a plain material; dashed edges attach the Linetype shader clone. Driving the body through this node
# lets gpApplyGeometry() push live geometry during a drag with no queue_redraw dependency.
# 管线主体由单一 Line2D 子节点（gpInkLine）为所有连线类型绘制。实线用普通材质；虚线挂线型
# 着色器克隆。把主体交给此节点，gpApplyGeometry() 就能在拖拽时同步推送实时几何，不依赖 queue_redraw。
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

# Injected render-style snapshot. Replaces direct autoload reads; null only
# in hand-built tests that skip injection (defaults below then kick in).
# 注入的渲染样式快照。取代直接读 autoload；仅在跳过注入的手工测试中为 null（下方有默认兜底）。
var gpStyle: GPRenderStyle = null

# Selection / hover / editing state (painted as a halo under the ink).
# 选中 / 悬停 / 编辑状态（以墨线之下的光晕绘制）。
var gpSelected: bool = false
var gpHovered: bool = false

# True while this edge's grip is being dragged (edit state). Drives the distinct orange highlight
# so "selected" and "actively editing" are visually separate.
# 本边抓取点正被拖拽（编辑态）时为真。驱动橙色高亮，使「选中」与「正在编辑」视觉分离。
var gpEditing: bool = false

# Linetype shader material clone for this edge (dashed rendering). Solid edges render with a
# plain (null) material. Captured once in _ready() so it survives the body-paint toggling.
# 本边专用的线型着色器材质克隆（虚线渲染）。实线用普通（空）材质。于 _ready() 捕获一次，
# 以免在「实线/虚线」切换时丢失。
var _gpLinetypeMat: ShaderMaterial = null

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
	# gpInkLine is the SYNCHRONOUS drag-follow layer only. During a live drag gpApplyGeometry()
	# pushes the live polyline here directly (zero queue_redraw dependency) so a moved node's pipe
	# follows on top without lag. The moment _draw() runs it HIDES gpInkLine, because the authoritative
	# static body is painted by this view's own _draw (GPEdgePainter.gpDrawInk()) which always sits
	# ABOVE the canvas background and BELOW the overlays (halo / arrow / tag). z_index is kept high so
	# the brief on-top drag frame can never be occluded by a sibling.
	# gpInkLine 仅作「拖拽中」的同步跟随层：拖拽时 gpApplyGeometry() 把实时折线直接写于此
	#（不依赖 queue_redraw），使被移动图元的管线无滞后地顶层跟随。一旦 _draw() 执行即隐藏它，
	# 因为权威的静态主体由本视图自身 _draw()（GPEdgePainter.gpDrawInk()）绘制，它恒在画布背景之上、
	# 覆盖层（光晕 / 箭头 / 位号）之下。z_index 取高值仅为使那一瞬的顶层帧不被兄弟节点遮挡。
	gpInkLine.z_index = 20
	gpInkLine.z_as_relative = true
	gpInkLine.material = GPLinetypeMaterial.gpMake()
	_gpLinetypeMat = gpInkLine.material as ShaderMaterial
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


# Push the live polyline straight into the GPU ink Line2D (the dashed / solid body) so a moved
# node's pipe follows IMMEDIATELY, with zero dependence on queue_redraw/viewport timing. This is
# the synchronous half of the drag-follow fix and works for EVERY edge kind (solid PROCESS lines
# included — the previous build only updated the ink line for dashed edges, so solid pipes stayed
# frozen at the old position until the drag released).
# 把实时折线直接写进 GPU 墨线 Line2D（实线 / 虚线主体），使被移动图元的管线「即刻」跟随，
# 完全不依赖 queue_redraw/视口时序。这是拖拽跟随修复的同步半边，且对「所有」连线类型都有效
func gpApplyGeometry() -> void:
	if gpInkLine == null or gpGraph == null or gpEdge == null:
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
	if gpStyle != null and gpStyle.gpScreenConstantWidth:
		gpW = gpW / gpZoom
	gpW = maxf(gpW, GPEdgeStyle.GP_MIN_PX / gpZoom)
	_gpPaintInkBody(gpPts, gpCol, gpW, gpPat)


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
	if gpStyle != null and gpStyle.gpScreenConstantWidth:
		gpW = gpW / gpZoom
	gpW = maxf(gpW, GPEdgeStyle.GP_MIN_PX / gpZoom)

	# Halo first: drawn UNDER the ink so the line keeps its true weight when selected.
	# 先画光晕：位于墨线之下，使线条在选中时仍保持其真实线重。
	# Editing state (a grip is being dragged) wins over plain selection, then hover.
	# 编辑态（抓取点正拖拽）优先于普通选中，再之后是悬停。
	if gpEditing:
		GPEdgePainter.gpDrawHalo(self, gpPts, GPEdgeStyle.GP_EDIT_HALO, gpW + 13.0 / gpZoom)
	elif gpSelected:
		GPEdgePainter.gpDrawHalo(self, gpPts, GPEdgeStyle.GP_SEL_HALO, gpW + 11.0 / gpZoom)
	elif gpHovered:
		GPEdgePainter.gpDrawHalo(self, gpPts, GPEdgeStyle.GP_HOVER_HALO, gpW + 6.0 / gpZoom)

	# Ink (static body): painted by THIS view's own _draw() so it always sits ABOVE the canvas
	# background and BELOW the overlays (halo / selection / arrow / tag) drawn right after it.
	# gpInkLine is only the synchronous drag-follow layer (gpApplyGeometry()); hide it here so the CPU
	# body is the single authoritative render and the selected/hover outline stays on top.
	# 墨线（静态主体）：由本视图「自身」_draw() 绘制，恒在画布背景之上、其后覆盖层
	#（光晕 / 选中 / 箭头 / 位号）之下。gpInkLine 仅是拖拽同步跟随层（gpApplyGeometry()）；
	# 此处隐藏它，使 CPU 主体成为唯一权威渲染、选中 / 悬停描边始终位于其之上。
	GPEdgePainter.gpDrawInk(self, gpPts, gpCol, gpW, gpPat)
	gpInkLine.visible = false

	# Selected / editing: overlay a thin bright core stroke ON TOP of the ink so the WHOLE path
	# lights up (the halo alone can read as just a thicker glow). Keeps the original colour visible.
	# 选中 / 编辑：在墨线之上叠一道细亮描边，使整条路径发亮（仅光晕可能被误读为单纯变粗）。
	# 同时保留原色可见。
	if gpEditing or gpSelected:
		GPEdgePainter.gpDrawInk(self, gpPts, GPEdgeStyle.GP_SEL_OUTLINE, GPEdgeStyle.GP_MIN_PX / gpZoom, PackedFloat32Array())

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
		var gpGeo: Dictionary = gpTagGeometry()
		if not gpGeo.is_empty():
			_gpDrawTag(gpCol, gpGeo)
			# Selection handle only while the edge is selected/editing, so a dragged-away
			# number stays discoverable and grabbable. / 仅当选中 / 编辑时画手柄，使被拖离的编号
			# 仍可被找到、可抓取。
			if gpSelected or gpEditing:
				_gpDrawTagGrip(gpGeo)


# Paint the pipe BODY into the gpInkLine Line2D child — the single visible geometry for the edge.
# 把管线主体绘入 gpInkLine（Line2D 子节点）—— 本边唯一的可见几何。
# Solid edges (empty pattern) use a plain material (clean continuous stroke); dashed edges use the
# Linetype shader clone so the dash phase stays continuous across segments. Called both from _draw()
# and from gpApplyGeometry() so the body follows a moved node synchronously, never depending on
# queue_redraw timing.
# 实线（空图案）用普通材质（干净连续笔触）；虚线用线型着色器克隆，使划相位跨段连续。
# 既由 _draw() 又由 gpApplyGeometry() 调用，故主体同步跟随被移动节点，永不依赖 queue_redraw 时序。
func _gpPaintInkBody(gpPts: PackedVector2Array, gpColor: Color, gpWidth: float,
		gpPattern: PackedFloat32Array) -> void:
	if gpInkLine == null or gpPts.size() < 2:
		return
	gpInkLine.points = gpPts
	gpInkLine.width = gpWidth
	gpInkLine.default_color = gpColor
	gpInkLine.visible = true
	if gpPattern.size() >= 2 and _gpLinetypeMat != null:
		gpInkLine.material = _gpLinetypeMat
		var gpMat: ShaderMaterial = _gpLinetypeMat
		if gpMat.shader != null:
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
	else:
 # Solid line: plain (null) material renders a clean continuous stroke; no dash shader.
 # 实线：普通（空）材质即得干净连续笔触，无需虚线着色器。
		gpInkLine.material = null


# Pipes always show a number (placeholder when missing); signal lines stay clean by default.
# 管道始终显示编号（缺失时显示占位符）；信号线默认保持干净。
func _gpShouldDrawTag() -> bool:
	var gpDefault: bool = gpEdge.gpKind != GPPIDEdge.GP_SIGNAL
	return _gpAttrBool("show_tag", gpDefault)


# Where the line number currently sits, in WORLD coordinates — the single source of truth that
# the painter, the drag grip and the leader ALL read, so the three can never disagree about
# where the number is.
# 管线号当前落位（世界坐标）—— 绘制、拖拽手柄与引出线共同读取的唯一真相来源，
# 故三者对「编号在哪」永不会各执一词。
# [return] {} when this edge shows no number at all; otherwise a record carrying
#   "text" / "font" / "fit" / "scale" / "pos" / "rot" / "size" / "box" / "leader" / "anchor" /
#   "offset" / "placeholder" / "detached" / "flipped".
# 本边完全不显示编号时返回 {}；否则返回含上述各键的记录。
# "detached" / "flipped" describe the callout state a dragged-away number is in (flat, with a
# leader); both come straight from gpPlaceCallout(), the single decision point, so the painter and
# any future UI reading them can never disagree with the geometry that was actually drawn.
# "detached" / "flipped" 描述被拖离的编号所处的引出标注状态（横排 + 引出线）；两者直接来自唯一
# 判定点 gpPlaceCallout()，故绘制方与日后读取它们的界面，都不可能和真正画出的几何不一致。
func gpTagGeometry() -> Dictionary:
	if gpEdge == null or not _gpShouldDrawTag():
		return {}
	var gpPts: PackedVector2Array = gpPolyline()
	if gpPts.size() < 2:
		return {}
	var gpFont: Font = ThemeDB.fallback_font
	if gpStyle != null and gpStyle.gpSymbolFont != null:
		gpFont = gpStyle.gpSymbolFont
	# A line number is an in-line annotation, which the reference drawing sets at 3.0 mm — the same
	# tier as a valve label, not the 4.5 mm of an equipment tag. The project-level override still
	# wins when set (> 0). See GPTextRole for the measurement.
	# 管线号属在管标注，参照图取 3.0mm —— 与阀门标注同档，而非设备位号的 4.5mm。项目级覆盖在
	# 设置为正时仍然优先。实测见 GPTextRole。
	var gpSizeSrc: float = GPTextRole.GP_INLINE_TAG_MM
	if gpStyle != null:
		gpSizeSrc = GPTextRole.gpPipeTagMM(gpStyle.gpPipeTagFontSize, gpStyle.gpSymbolFontSize)
	# The tag is drawn in DESIGN PIXELS (see GPCanvasText): a bitmap produced at the sheet height
	# would be magnified by the canvas scale and read as a grey smudge, whichever family is set.
	# 位号按**设计像素**绘制（详见 GPCanvasText）：以图面字高生成的字模会被画布缩放放大成一团灰糊，
	# 与所选字族无关。
	var gpScale: float = GPCanvasText.gpScaleOf(self)
	var gpFit: Vector2 = GPCanvasText.gpLabelFontFit(gpSizeSrc, self)
	var gpText: String = gpEdge.gpTag
	var gpPlaceholder: bool = gpText == ""
	if gpPlaceholder:
		# Unnumbered pipe: shout instead of staying silent.
		# 未编号管道：显式提示，而非沉默。
		gpText = GP_TAG_PLACEHOLDER
	# The per-edge "tag_rotate" attribute overrides the global default when present; otherwise
	# the global setting decides whether a vertical-run number is rotated.
	# 当边显式带 "tag_rotate" 属性时该属性优先；否则由全局设置决定竖管位号是否旋转。
	# The no-snapshot fallback is TRUE, matching both Settings and GPRenderStyle: "a vertical run is
	# numbered bottom-to-top" is a drafting convention, and a missing snapshot must not silently flip
	# a convention (the old `false` here meant an un-injected view rendered horizontal numbers).
	# 无快照时的回落取**真**，与 Settings、GPRenderStyle 三处一致：「竖管自下而上编号」是制图约定，
	# 而缺失快照不得静默翻转一条约定（此处旧值 `false` 意味着未被注入的视图会渲染水平编号）。
	var gpRotate: bool = _gpAttrBool("tag_rotate", gpStyle.gpPipeTagRotate if gpStyle != null else true)
	# Measured in the draw frame's unit (one design pixel), then converted to world units for the
	# layout module, which reasons in world coordinates — and converted back by the draw transform.
	# 以绘制坐标系单位（1 设计像素）测量，再换算为世界单位交给以世界坐标推理的布局模块；
	# 绘制变换会把它换算回来。
	var gpSzPx: Vector2 = gpFont.get_string_size(gpText, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		int(gpFit.x)) * gpFit.y
	var gpSzWorld: Vector2 = gpSzPx / maxf(gpScale, 0.0001)
	# The manual drag offset rides in as a WORLD vector, so a dragged number keeps its place on
	# the sheet across zoom changes exactly like an un-dragged one.
	# 手工拖拽偏移以**世界**向量传入，故被拖拽过的编号与未被拖拽者一样，在缩放变化间保持其在
	# 图纸上的位置。
	# gpPlaceCallout() — NOT gpPlace() — is the entry point: the callout rule (a number pulled clear
	# of its pipe is laid flat, with its leader) has to be applied where BOTH the placement and the
	# leader are produced. Calling the two separately is what let a rotated column keep a leader.
	# 入口是 gpPlaceCallout() 而非 gpPlace()：引出标注规则（被拉离管线的编号一律放平并带引出线）
	# 必须在「落位与引出线同时产出」的地方施加。分别调用这两者，正是「竖排字列却带着引出线」的由来。
	var gpOffset: Vector2 = gpEdge.gpTagOffset()
	var gpCall: Dictionary = GPEdgeTagLayout.gpPlaceCallout(gpPts, gpSzWorld.x, gpSzWorld.y,
		gpRotate, GPEdgeTagLayout.GP_GAP, gpOffset)
	return {
		"text": gpText,
		"font": gpFont,
		"fit": gpFit,
		"scale": gpScale,
		"pos": gpCall.get("pos", Vector2.ZERO),
		"rot": float(gpCall.get("rot", 0.0)),
		"size": gpSzWorld,
		"box": GPEdgeTagLayout.gpBox(gpCall, gpSzWorld.x, gpSzWorld.y),
		"leader": gpCall.get("leader", PackedVector2Array()),
		"anchor": gpCall.get("anchor", Vector2.ZERO),
		"offset": gpOffset,
		"placeholder": gpPlaceholder,
		"detached": bool(gpCall.get("detached", false)),
		"flipped": bool(gpCall.get("flipped", false)),
	}


# Paint the line number (or its placeholder) where gpTagGeometry() put it — a leader line first
# when the number has been dragged away from its pipe.
# 在 gpTagGeometry() 指定的位置绘制管线编号（或其占位符）—— 编号被拖离其管线时先绘制引出线。
func _gpDrawTag(gpCol: Color, gpGeo: Dictionary) -> void:
	var gpColor: Color = gpCol
	if bool(gpGeo.get("placeholder", false)):
		gpColor = GPEdgeStyle.GP_DANGLING
	GPEdgePainter.gpDrawLeader(self, gpGeo.get("leader", PackedVector2Array()), gpColor, gpZoom)
	GPEdgePainter.gpDrawTag(self, gpGeo, gpColor)


# Selection handle on the line number, so a dragged-away tag is discoverable and grabbable.
# 管线号上的选中手柄，使被拖离的编号可被发现、可被抓取。
# Mirrors the node-label grip: a white square with a blue outline, drawn at the tag box centre in
# world units (divided by the zoom so it stays a constant ~9 screen pixels, exactly like the
# node-label handle in symbol_view).
# 与图元位号手柄同形：白底蓝框方块，画在编号包围盒中心（世界单位下除以缩放以保持约 9 屏幕像素恒定，
# 与 symbol_view 中的图元位号手柄完全一致）。
func _gpDrawTagGrip(gpGeo: Dictionary) -> void:
	var gpBox: Rect2 = gpGeo.get("box", Rect2())
	if gpBox == Rect2():
		return
	var gpGs: float = GPLabelGripOps.GP_GRIP_SIZE / maxf(gpZoom, 0.0001)
	var gpC: Vector2 = gpBox.get_center()
	var gpR: float = gpGs * 0.5
	draw_rect(Rect2(gpC.x - gpR, gpC.y - gpR, gpGs, gpGs), Color(1.0, 1.0, 1.0), true)
	draw_rect(Rect2(gpC.x - gpR, gpC.y - gpR, gpGs, gpGs), GPLabelGripOps.GP_COL, false, 1.5 / gpZoom)


# Live preview while the number is being dragged: write the offset straight onto the edge and
# repaint. The drag commits on release as ONE undo step, exactly like the node-label drag — the
# preview is deliberately outside the command stack so a 60 Hz drag does not push 60 undo steps.
# 拖拽编号时的实时预览：把偏移直接写到边上并重绘。拖拽在释放时作为**一个**撤销步提交，与图元
# 标签拖拽完全一致 —— 预览有意不经过命令栈，使 60Hz 的拖拽不会压入 60 个撤销步。
func gpSetTagOffsetPreview(gpOffset: Vector2) -> void:
	if gpEdge == null:
		return
	gpEdge.gpSetTagOffset(gpOffset)
	queue_redraw()


# Read a boolean from gpAttrs with a default. Absent key == default, never an error.
# 带默认值地从 gpAttrs 读取布尔值。键不存在即取默认值，绝不报错。
func _gpAttrBool(gpKey: String, gpDefault: bool) -> bool:
	if not gpEdge.gpAttrs.has(gpKey):
		return gpDefault
	return bool(gpEdge.gpAttrs[gpKey])
