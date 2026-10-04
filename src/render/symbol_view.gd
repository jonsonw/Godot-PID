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
# this node : world position + the label (upright, never mirrored, so text stays readable)
# _gpBody : flip + rotation + the glyph + the port dots
# 本节点 ：世界坐标 + 标签（始终正立、绝不镜像，故文字可读）
# _gpBody ：翻转 + 旋转 + 字形 + 端口圆点
# See GPSymbolBody for why the split is necessary.
# 拆分的原因见 GPSymbolBody。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Vertical distance from the envelope bottom to the label baseline.
# 包络底边到标签基线的垂直距离。
const GP_LABEL_GAP: float = 7.0

# Port dot radius: a FRACTION of the symbol's shorter side, clamped, instead of a fixed value.
# WHY NOT A CONSTANT ANY MORE: the constant was 4.0 and was written in the pixel era — since the
# world unit became 1 mm (plan Phase 0) it meant a 4 mm radius, i.e. an 8 mm dot on a 4x2 mm ball
# valve. That is the reported "endpoint size does not match the symbol at all". A ratio with a
# clamp keeps a nozzle dot readable on a column and proportionate on a valve; a screen-space floor
# stops it from vanishing when the whole sheet is fitted into the viewport.
# 端口圆点半径：取图元**较短边**的某个比例并夹取，而不再是一个定值。
# 为何不再用常量：该常量为 4.0 且写于像素时代 —— 自世界单位改为 1mm（计划 Phase 0）起，它意味着
# 4mm 半径，即在 4×2mm 的球阀上画一个 8mm 的圆点。这正是用户报告的「端点大小跟图元完全不匹配」。
# 用「比例 + 夹取」可让管口点在塔器上可读、在阀门上成比例；屏幕空间下限则避免整图适配视口时它
# 彻底消失。
const GP_PORT_R_RATIO: float = 0.06
const GP_PORT_R_MIN: float = 0.4
const GP_PORT_R_MAX: float = 1.6

# Bound graph node id.
# 绑定的图节点 id。
var gpNodeId: String = ""

# Bound graph node object (strongly typed; the single source of truth).
# 绑定的图节点对象（强类型；唯一真相来源）。
var gpNode: GPPIDNode = null

# Bound symbol definition (may be null for unknown types).
# 绑定的图元定义（未知类型时可能为 null）。
var gpDef: GPSymbolDef = null

# Host graph + definition lookup, injected by the binder. Required so a MOUNTED child can derive
# its world transform: the parent chain lives in the graph, not in this view.
# 宿主图与定义查找器，由绑定器注入。挂载子件推导其世界变换所必需：父链在图里，而不在本视图内。
var gpGraph: GPPIDGraph = null
var gpDefLookupCb: Callable = Callable()

# Whether this symbol is currently selected.
# 当前是否被选中。
var gpSelected: bool = false

# Whether this symbol is the source of an in-progress connection.
# 当前是否为正在进行的连线的起点。
var gpConnectSource: bool = false

# Child layer that carries flip + rotation.
# 承载翻转与旋转的子层。
var _gpBody: GPSymbolBody = null

# Injected render-style snapshot. Replaces direct autoload reads.
# 注入的渲染样式快照。取代直接读 autoload。
var gpStyle: GPRenderStyle = null


# Bind this view to a graph node and its definition.
# 将本视图绑定到一个图节点及其定义。
# [param gpGraphIn] / [param gpLookupIn] are optional so existing two-argument callers (smoke
# harnesses, the symbol editor) keep working; without them a MOUNTED child simply falls back to
# its own frame, which is exactly the pre-mount behaviour.
# [param gpGraphIn] / [param gpLookupIn] 为可选，使既有两参数调用方（冒烟夹具、图元编辑器）
# 继续可用；不传时挂载子件回落为自身坐标系，即挂载功能之前的行为。
func gpInit(gpN: GPPIDNode, gpD: GPSymbolDef, gpGraphIn: GPPIDGraph = null,
		gpLookupIn: Callable = Callable()) -> void:
	gpNode = gpN
	gpNodeId = gpN.gpInstanceId
	gpDef = gpD
	if gpGraphIn != null:
		gpGraph = gpGraphIn
	if gpLookupIn.is_valid():
		gpDefLookupCb = gpLookupIn
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
# Why not override queue_redraw / 为何不覆写 queue_redraw：
# Godot rejects it ("overrides a method from native class ... won't be called by the engine"),
# and it would be a lie anyway: the engine would keep repainting only this node. An explicit
# second entry point is honest about what it does.
# Godot 会拒绝（"overrides a method from native class ... won't be called by the engine"），
# 而且那样做本身就是假的：引擎仍只会重绘本节点。显式的第二个入口才如实表达其行为。
func gpRepaint() -> void:
	queue_redraw()
	if _gpBody != null:
		_gpBody.queue_redraw()


# Sync position, flip and rotation from the underlying graph node.
# 从底层图节点同步位置、翻转与旋转。
func _gpUpdateTransform() -> void:
	if gpNode == null:
		return
	# The world frame comes from GPMountResolver, NOT from the node's own fields. For a MOUNTED
	# child the node stores no world coordinate (it is derived from the host), so reading
	# gpPosition here would leave the glyph behind while its pipes followed the host.
	# 世界坐标系取自 GPMountResolver，而非节点自身字段。挂载子件不存世界坐标（由宿主推导），
	# 故此处读 gpPosition 会让字形落在原处、而它的管线跟着宿主跑。
	var gpFrame: Dictionary = GPMountResolver.gpWorldTransform(gpGraph, gpDefLookupCb, gpNode)
	position = gpFrame["origin"]
	if _gpBody == null:
		return
	# Mirror first (in the symbol's own frame), then rotate — the SAME order GPPortResolver
	# uses, otherwise a flipped-and-rotated valve's ports land on the wrong side of the glyph.
	# 先镜像（在图元自身坐标系内），再旋转 —— 与 GPPortResolver 所用顺序一致，
	# 否则「先翻转再旋转」的阀门端口会落在字形的错误一侧。
	_gpBody.scale = Vector2(-1.0, 1.0) if bool(gpFrame["flipped"]) else Vector2.ONE
	_gpBody.rotation = deg_to_rad(float(gpFrame["rot_deg"]))


# Draw the label(s). The glyph and the ports are painted by the body child.
# 绘制标签。字形与端口由 body 子节点绘制。
#
# TWO PATHS, ONE OF WHICH IS FROZEN / 两条路径，其中一条被封冻：
#   * gpLabelSlots non-empty -> N independent texts (new);
#   * gpLabelSlots empty     -> the original single-label path, byte-for-byte (backward compat).
#   * gpLabelSlots 非空 -> N 段独立文字（新）；
#   * gpLabelSlots 为空 -> 原单标签路径，逐字节不变（向后兼容）。
func _draw() -> void:
	if gpNode == null:
		return
	var gpLocale: String = gpStyle.gpLocale if gpStyle != null else "zh_CN"

	# ---- multi-slot path / 多槽路径 ----
	if gpDef != null and not gpDef.gpLabelSlots.is_empty():
		var gpDrewAny: bool = false
		for gpSlot in gpDef.gpLabelSlots:
			if not GPLabelGripOps.gpSlotVisible(gpNode, gpDef, gpSlot):
				continue
			var gpSlotText: String = GPLabelGripOps.gpSlotText(gpNode, gpDef, gpSlot, gpLocale)
			if gpSlotText == "":
				continue
			_gpDrawOneText(gpSlotText,
				GPLabelGripOps.gpSlotAnchor(gpNode, gpDef, gpSlot, gpGraph, gpDefLookupCb),
				GPLabelGripOps.gpSlotOffsetLocal(gpNode, gpDef, gpSlot, gpGraph, gpDefLookupCb),
				GPTextRole.gpSlotMM(gpSlot.gpTier, _gpBaseFontMM(), gpDef.gpDefaultSize))
			gpDrewAny = true
		# The grip rides the FIRST slot's anchor, so a drag still has one predictable home.
		# 抓取点跟随**首个**槽的锚点，使拖拽仍有一个可预期的落点。
		if gpSelected and gpDrewAny:
			_gpDrawGrip(GPLabelGripOps.gpSlotOffsetLocal(gpNode, gpDef, gpDef.gpLabelSlots[0],
				gpGraph, gpDefLookupCb))
		return

	# ---- original single-label path (unchanged) / 原单标签路径（未改动） ----
	# M10b: the label is the TAG, resolved through the shared geometry module so the canvas,
	# the grip and the headless tests all agree on where it goes.
	# M10b：标签即**位号**，经共用的几何模块解析，使画布、抓取点与 headless 测试
	# 对「它画在哪」完全一致。
	var gpLabel: String = GPLabelGripOps.gpLabelText(gpNode, gpDef, gpLocale)
	if gpLabel == "":
		return
	var gpAnchor: int = GPLabelGripOps.gpEffectiveAnchor(gpNode, gpDef)
	var gpOff: Vector2 = GPLabelGripOps.gpLocalOffset(gpNode, gpDef)
	# The height depends on WHAT the symbol is, not on a single global number: the reference drawing
	# annotates equipment at 4.5 mm and everything in-line at 3.0 mm. See GPTextRole for the
	# measurement. The setting supplies the in-line tier (and the fallback for an unknown category).
	# 字高取决于**图元是什么**，而非一个全局数字：参照图对设备标注 4.5mm、对在管标注 3.0mm。实测见
	# GPTextRole。设置项提供在管档（并作为未知类别的兜底）。
	_gpDrawOneText(gpLabel, gpAnchor, gpOff,
		GPTextRole.gpTagMM(gpDef.gpCategory if gpDef != null else "", _gpBaseFontMM()))
	# The drag handle, only while selected — same visual language as the edge grips.
	# 仅在选中时绘制拖拽手柄 —— 与边抓取点同一套视觉语言。
	if gpSelected:
		_gpDrawGrip(gpOff)


# The user's symbol font size — the IN-LINE tier, and the fallback for an unknown category.
# 用户设置的图元字号 —— 在管档，并作为未知类别的兜底。
func _gpBaseFontMM() -> float:
	if gpStyle != null:
		return gpStyle.gpSymbolFontSize
	return GPTextRole.GP_INLINE_TAG_MM


# Paint ONE piece of label text at a symbol-local offset. Shared by the single-label path and by
# every label slot, so a slot can never drift from the tag's placement rules.
# 在给定图元本地偏移处绘制**一段**标签文字。单标签路径与每个文本槽共用，
# 故槽位绝不会偏离位号的定位规则。
func _gpDrawOneText(gpText: String, gpAnchor: int, gpOffLocal: Vector2, gpFontMM: float) -> void:
	# The anchor rides in the symbol's own frame, so it is transformed by hand here: this node
	# carries no rotation, by design (see the header).
	# 锚点位于图元自身坐标系，故在此手工变换：本节点按设计不承载旋转（见文件头）。
	# NOTE: this uses the CHILD'S OWN flip/rotation, not its derived mount frame — deliberately.
	# A label is always drawn upright (never mirrored) and positioned relative to the symbol, and
	# the grip hit-test uses exactly the same math, so the two stay consistent.
	# 注意：此处用子件**自身**的翻转/旋转，而非其推导挂载坐标系 —— 这是刻意的。标签恒为正立
	# （绝不镜像）且相对图元定位，而抓取点命中测试用的是同一套数学，故两者保持一致。
	var gpOff: Vector2 = _gpOriented(gpOffLocal)

	var gpFont: Font = ThemeDB.fallback_font
	if gpStyle != null and gpStyle.gpSymbolFont != null:
		gpFont = gpStyle.gpSymbolFont
	# Text is drawn in DESIGN PIXELS, not millimetres: a bitmap produced at the sheet height (3 px
	# for a 3 mm tag) is magnified by world_root's scale and reads as a grey smudge. See GPCanvasText
	# for the rationale. The counter-scale makes one draw unit one design pixel, so every coordinate
	# below is a world coordinate multiplied by the accumulated scale.
	# 文字按**设计像素**绘制，而非毫米：以图面字高（3mm 位号即 3px）生成的字模会被 world_root 的
	# 缩放放大成一团灰糊（详见 GPCanvasText）。该反向缩放使 1 绘制单位 == 1 设计像素，故下方每个
	# 坐标都是「世界坐标 × 累积缩放」。
	var gpScale: float = GPCanvasText.gpScaleOf(self)
	var gpFit: Vector2 = GPCanvasText.gpLabelFontFit(gpFontMM, self)
	var gpFontSz: int = int(gpFit.x)
	# Measure first, then place the text relative to the anchor per its alignment.
	# 先测量，再按对齐方式把文字摆到锚点的相应位置。
	# The offset term is world mm and the measured size is design px — see gpDrawOrigin for why the
	# two must not be scaled together (that was the reported zoom drift).
	# 偏移项为世界 mm，实测尺寸为设计像素 —— 二者不可同乘缩放，原因见 gpDrawOrigin
	#（那正是用户报告的缩放漂移）。
	# The box is the ROUNDED size times the residual, i.e. the box that will actually be painted — the
	# placement must be computed from that, not from the un-compensated measurement.
	# 包围盒取「取整字号 × 残差」，即**真正会被画出来**的那个盒子；定位必须据它计算，而非未补偿的测量值。
	var gpSzText: Vector2 = gpFont.get_string_size(gpText, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		gpFontSz) * gpFit.y
	var gpOrigin: Vector2 = GPLabelGripOps.gpDrawOrigin(gpAnchor, gpOff, gpSzText, gpScale)
	# The residual rides in the DRAW SCALE, so the anchor must be pre-divided by it: the glyph then
	# scales ABOUT gpOrigin and lands on exactly the design pixel gpDrawOrigin chose. Putting gpOrigin
	# in the transform's position instead would multiply it by the parent scale a second time — the
	# very error gpDrawOrigin exists to prevent (it put every tag ~6 mm off the moment it was tried).
	# 残差乘在**绘制缩放**上，故锚点须预先除以它：字形因此绕 gpOrigin 缩放，落点仍是 gpDrawOrigin 选定
	# 的那个设计像素。若把 gpOrigin 放进变换的 position，它会被父级缩放**再乘一次** —— 正是 gpDrawOrigin
	# 存在的意义所在（试过之后每个位号立刻偏了约 6mm）。
	draw_set_transform(Vector2.ZERO, 0.0, GPCanvasText.gpTextScale(gpFit, gpScale))
	# The alignment argument is inert at width = -1 (Godot ignores it; measured), so the position is
	# fully determined by gpDrawOrigin above. It is passed anyway to state the intent, and it stays
	# pinned by gp_test_label_anchor.
	# 宽度为 -1 时对齐参数不起作用（Godot 忽略它，已实测），故位置完全由上面的 gpDrawOrigin 决定。
	# 仍然传入它只是为了表明意图，并由 gp_test_label_anchor 钉住其取值。
	draw_string(gpFont, gpOrigin / gpFit.y, gpText, GPLabelGripOps.gpAlignFor(gpAnchor),
		-1.0, gpFontSz, Color(0.9, 0.9, 0.9))
	# Restore the identity so anything drawn later on this item is unaffected.
	# 复位为单位变换，使本项之后的任何绘制不受影响。
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# The drag handle for the label grip, drawn at a symbol-local offset.
# 位号抓取点的拖拽手柄，绘制在给定图元本地偏移处。
#
# GPLabelGripOps.GP_GRIP_SIZE is a SCREEN-pixel size (the edge grips draw it in screen space),
# but this node draws inside the scaled world_root — used raw it became a 9 mm square, i.e. a
# handle larger than a ball valve. Dividing by the accumulated scale restores the intended
# constant screen size and matches the edge grips exactly.
# GPLabelGripOps.GP_GRIP_SIZE 是**屏幕像素**尺寸（边抓取点在屏幕空间绘制它），但本节点在
# 被缩放的世界根内绘制 —— 直接使用会变成 9mm 方块，即比球阀还大的手柄。除以累积缩放即可恢复
# 既定的屏幕恒定尺寸，并与边抓取点完全一致。
func _gpDrawGrip(gpOffLocal: Vector2) -> void:
	var gpOff: Vector2 = _gpOriented(gpOffLocal)
	var gpScale: float = GPCanvasText.gpScaleOf(self)
	var gpGs: float = GPLabelGripOps.GP_GRIP_SIZE / gpScale
	var gpHalf: float = gpGs * 0.5
	draw_rect(Rect2(gpOff - Vector2(gpHalf, gpHalf), Vector2(gpGs, gpGs)),
		Color(1.0, 1.0, 1.0), true)
	draw_rect(Rect2(gpOff - Vector2(gpHalf, gpHalf), Vector2(gpGs, gpGs)),
		GPLabelGripOps.GP_COL, false, 1.5)


# Apply the symbol's own flip then rotation to a symbol-local offset (label / grip placement).
# 对图元本地偏移施加图元自身的翻转再旋转（标签 / 抓取点定位）。
func _gpOriented(gpOffLocal: Vector2) -> Vector2:
	var gpOff: Vector2 = gpOffLocal
	if gpNode.gpFlipped:
		gpOff.x = -gpOff.x
	return gpOff.rotated(deg_to_rad(gpNode.gpRotationDeg))


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

	# Border width is the equipment-outline weight: 0.35 mm (ISO multi-weight standard). It is a
	# world-unit (mm) constant, so world_root scale zooms it uniformly. It is floored in SCREEN
	# space, exactly like the edge layer (GPEdgeStyle.GP_MIN_PX), because at the sheet-fit zoom
	# (~2x) 0.35 mm is 0.7 screen points and renders as a washed-out hairline. The mm value stays
	# the authored / exported weight; only the on-screen render gets a floor.
	# 边框宽度取设备轮廓线宽：0.35 mm（ISO 多级线宽标准）。为世界单位（mm）常量，随 world_root
	# 缩放统一变化。它在**屏幕**空间设下限，与连线层（GPEdgeStyle.GP_MIN_PX）完全一致 —— 因为在
	# 整图适配缩放（约 2×）下 0.35mm 仅 0.7 屏幕点，看起来是发虚的细丝。mm 值仍是既定/导出线宽，
	# 只有屏幕渲染获得下限。
	# The accumulated scale is read from the transform instead of being plumbed in: this node lives
	# under a scaled world_root, so its global scale IS the camera zoom (one source, no plumbing).
	# 累积缩放直接从变换读取而非层层传递：本节点位于被缩放的世界根之下，其全局缩放**就是**相机
	# 缩放（单一来源，无需布线）。
	var gpScale: float = maxf(absf(gpCv.get_global_transform().get_scale().x), 0.01)
	var gpBorder: float = maxf(0.35, GPEdgeStyle.GP_MIN_PX / gpScale)

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
	# The offset used here is the PURE symbol-local one, because this call runs INSIDE the body's
	# frame (see GPSymbolBody): the body's own flip + rotation already maps local -> world. Rotating
	# the offset a second time here was a latent double-transform that put a rotated or flipped
	# symbol's dots somewhere else than its pipe ends.
	# 此处用的是**纯**图元本地偏移，因为本次调用运行在 body 的坐标系内（见 GPSymbolBody）：
	# body 自身的翻转 + 旋转已经把本地映射到世界。在此再旋转一次是潜在的「双重变换」，
	# 会让已旋转/已翻转图元的圆点落在与管线端点不同的位置。
	if gpDef != null:
		var gpPortR: float = gpPortRadiusFor(gpSz)
		# Screen-space floor so a fitted whole sheet does not erase the connection marks.
		# 屏幕空间下限，使「整图适配」时连接标记不会被抹掉。
		gpPortR = maxf(gpPortR, GPEdgeStyle.GP_MIN_PX * 0.9 / gpScale)
		# A host whose mounted nozzles carry ports has YIELDED its own connect points: drawing
		# them would put wall dots under the nozzle tips and invite pipes back onto the wall
		# (the reported "the host's connection ports are still there"). The nozzles are separate
		# nodes and draw their own dots, so nothing is lost by the skip.
		# 已挂上带端口管嘴的宿主**让位**了自己的连接点：继续画会把壁面圆点压在管嘴端头下面，
		# 诱使管线回到罐壁（即用户报告的「宿主的连接端口还在」）。管嘴是独立节点、自会画出
		# 自己的圆点，故跳过不损失任何东西。
		if GPMountResolver.gpPortsSuperseded(gpGraph, gpDefLookupCb, gpNode):
			return
		for gpP in gpDef.gpPorts:
			var gpLp: Vector2 = gpDef.gpPortLocal(gpP)
			gpCv.draw_circle(gpLp, gpPortR, GPEdgeStyle.gpPortColor(gpP.gpType))


# Port dot radius (world mm) for a symbol of this size: a fraction of the SHORTER side, clamped.
# Split out as a pure function so the reported "endpoint size does not match the symbol" defect is
# pinned by a test instead of only by a screenshot.
# 给定尺寸图元的端口圆点半径（世界 mm）：取**较短边**的某个比例并夹取。拆为纯函数，使
# 用户报告的「端点大小与图元不匹配」缺陷由测试钉住，而非仅靠截图。
# NOTE: this is the authored / exported radius. The renderer additionally applies a SCREEN-space
# floor (GPEdgeStyle.GP_MIN_PX), which is a display-only concession and deliberately not here.
# 注意：本值为既定 / 导出半径。渲染时另加**屏幕**空间下限（GPEdgeStyle.GP_MIN_PX），那是
# 纯显示让步，刻意不放在此处。
static func gpPortRadiusFor(gpSize: Vector2) -> float:
	return clampf(minf(gpSize.x, gpSize.y) * GP_PORT_R_RATIO, GP_PORT_R_MIN, GP_PORT_R_MAX)
