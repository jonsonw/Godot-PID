class_name GPLabelGripOps
extends RefCounted
# Copyright © 2026 Jonson Wang
# Label (位号) placement on the sheet: geometry plus the drag interaction .
# 图纸上的标签（位号）定位：几何 + 拖拽交互。
#
# Everything above the "drag state" divider is PURE and headless-testable: given a node and
# its definition it answers "where does the tag sit?" and "what offset does this drag mean?".
# Only the last three methods touch the canvas.
# 「拖拽状态」分隔线以上的部分全是纯函数、可 headless 测试：给定节点与其定义，回答
# 「位号画在哪」与「这次拖拽意味着什么偏移」。只有最后三个方法触碰画布。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Gap between the envelope edge and the text, in millimetres. Mirrors GPSymbolView.GP_LABEL_GAP.
# 包络边缘到文字的间距（毫米）。与 GPSymbolView.GP_LABEL_GAP 一致。
# It is an UPPER BOUND, not a constant: see gpGapFor().
# 它是**上限**而非恒值：见 gpGapFor()。
const GP_GAP: float = 7.0

# Smallest gap the clamp may produce. / 钳制所能产生的最小间距。
const GP_MIN_GAP: float = 0.8

# Screen-pixel size of the grip square. / 抓取点方块的屏幕像素尺寸。
const GP_GRIP_SIZE: float = 9.0

# Grip colour, matching the edge grips' blue-on-white.
# 抓取点配色，与边抓取点的「蓝描边白填充」一致。
const GP_COL: Color = Color(0.20, 0.50, 1.0)


# ---------------------------------------------------------------- pure

# The text to draw. The template comes from the TYPE layer ({tag} by default); an empty tag
# falls back to the localized type name so a legacy, un-numbered sheet is not blank.
# 要绘制的文字。模板取自**类型层**（默认 {tag}）；位号为空时回落本地化类型名，
# 使未经编号的历史图纸不会是空白。
static func gpLabelText(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpLocale: String = "zh") -> String:
	if gpNode == null:
		return ""
	var gpName: String = GPPropertyResolver.gpDisplayName(
		gpNode.gpNames,
		gpDef.gpDisplayName if gpDef != null else "",
		gpLocale,
		gpNode.gpTag)
	var gpFmt: String = GPPropertyResolver.GP_DEFAULT_LABEL_FORMAT
	if gpDef != null and gpDef.gpLabelFormat != "":
		gpFmt = gpDef.gpLabelFormat
	var gpText: String = GPPropertyResolver.gpLabelText(gpFmt, gpNode.gpTag, gpName)
	if gpText.strip_edges() == "":
		return gpName
	return gpText


# Effective anchor: the instance wins when it set one, otherwise the type layer's default.
# 生效锚点：实例设置过则用实例的，否则用类型层默认。
static func gpEffectiveAnchor(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> int:
	var gpLib: int = gpDef.gpLabelAnchor if gpDef != null else GPLabelAnchor.GPAnchor.GP_BELOW
	var gpInst: int = GPLabelAnchor.GPAnchor.GP_AUTO
	if gpNode != null:
		gpInst = gpNode.gpLabelAnchor
	return GPPropertyResolver.gpActiveAnchor(gpLib, gpInst)


# Effective normalised offset, resolved the same way as the anchor.
# 生效的归一化偏移，解析方式与锚点相同。
static func gpEffectiveOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> Vector2:
	var gpLib: Vector2 = gpDef.gpLabelOffset if gpDef != null else Vector2.ZERO
	var gpInst: Vector2 = GPLabelAnchor.GP_OFFSET_UNSET
	if gpNode != null:
		gpInst = gpNode.gpLabelOffset
	return GPPropertyResolver.gpActiveOffset(gpLib, gpInst)


# The gap actually used for a symbol of this envelope size.
# 给定包络尺寸下**实际**使用的间距。
#
# WHY NOT A CONSTANT / 为何不能是恒值：
# 7 mm is right for a 10 mm pump, but a nozzle is 4 x 2 mm — a fixed 7 mm gap put its number 8 mm
# off the centre, i.e. four nozzle lengths away, which is the reported "the text sits far too far
# away". Small symbols therefore take HALF their shorter side (a 4x2 nozzle -> 1 mm), floored so
# the text never lands on the glyph; every symbol at least 7 mm on its shorter side keeps the
# historic 7 mm exactly, so equipment annotations never move.
# 7mm 对 10mm 的泵合适，但管嘴只有 4x2mm —— 固定 7mm 会把编号推到离中心 8mm 处，即四个管嘴长，这正是
# 用户报告的「文字离得太远」。故小图元取**短边的一半**（4x2 管嘴 -> 1mm），并设下限使文字绝不压到
# 字形上；短边 ≥7mm 的图元精确保持历史的 7mm，故设备标注不会有任何位移。
static func gpGapFor(gpSize: Vector2) -> float:
	var gpSide: float = minf(gpSize.x, gpSize.y)
	if gpSide >= GP_GAP:
		return GP_GAP
	return clampf(gpSide * 0.5, GP_MIN_GAP, GP_GAP)


# The envelope used for scaling. A missing definition falls back to a sane default so the
# geometry never divides by zero.
# 用于缩放的包络。定义缺失时回落到合理默认值，使几何永不会除以零。
static func gpEnvelope(gpDef: GPSymbolDef) -> Vector2:
	if gpDef != null and gpDef.gpDefaultSize.x > 0.0 and gpDef.gpDefaultSize.y > 0.0:
		return gpDef.gpDefaultSize
	return Vector2(64.0, 48.0)


# How many quarter turns a MOUNTED part's label layout is turned by, so its slots can follow the
# part's mount MOUNT AXIS instead of the sheet. 0 unless the definition opts in.
# 已挂载部件的标签版式应转多少个 90° —— 使槽位随部件的**安装轴**而非图纸排布。定义未开启时为 0。
#
# The rule is derived from the DERIVED frame's rotation, never from the node's own fields: a mounted
# child stores no world rotation (see GPMountResolver), so its own field is always 0 and reading it
# would answer "horizontal" for every part.
# 该规则由**推导**坐标系的旋转求出，绝不读节点自身字段：挂载子件不存世界旋转（见
# GPMountResolver），其自身字段恒为 0，读它会把每个部件都答成「水平」。
#
# The sign is fixed at -1 (counter-clockwise): a quarter turn is applied only when the axis is
# VERTICAL, and it must map "above" onto the LEFT so the number lands left of a riser and the DN
# right of it — the convention in the reference drawing. Left- and right-facing anchors share the
# same quarter count, so the two horizontal nozzles do not mirror each other's texts.
# 符号固定为 -1（逆时针）：仅在轴线**竖直**时转 90°，且必须把「上」映到**左**，使编号落在竖管左侧、
# DN 落在右侧 —— 即参照图的约定。朝左与朝右的锚点取得相同的转数，故两支水平管嘴的文字不会互为镜像。
static func gpLabelQuarters(gpGraph: GPPIDGraph, gpLookup: Callable, gpDef: GPSymbolDef,
		gpNode: GPPIDNode) -> int:
	if gpDef == null or gpNode == null or not gpDef.gpLabelFollowsMount:
		return 0
	if gpGraph == null or not gpNode.gpIsMounted():
		return 0
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpGraph, gpLookup, gpNode)
	var gpQ: int = int(roundf(float(gpWT["rot_deg"]) / 90.0))
	if absi(gpQ) % 2 == 0:
		return 0
	return -1


# Symbol-LOCAL offset (before flipping / rotating). This is the value the renderer needs:
# the node itself carries no rotation, so the rotation is applied by the caller.
# 图元**本地**偏移（翻转 / 旋转之前）。这是渲染器需要的值：
# 节点本身不承载旋转，旋转由调用方施加。
static func gpLocalOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> Vector2:
	var gpAnchor: int = gpEffectiveAnchor(gpNode, gpDef)
	var gpOff: Vector2 = gpEffectiveOffset(gpNode, gpDef)
	var gpSz: Vector2 = gpEnvelope(gpDef)
	return GPLabelAnchor.gpOffsetWorld(gpAnchor, gpOff, gpSz, gpGapFor(gpSz))


# ---------------------------------------------------------------- label slots
# ---------------------------------------------------------------- 文本槽
#
# A definition may declare N label slots (see GPLabelSlot): a nozzle shows its number above and
# its DN below, a valve actuator shows F.C. / F.O. The four helpers below resolve ONE slot the
# same way the single-label helpers above resolve the tag, including the per-instance override.
# 定义可声明 N 个文本槽（见 GPLabelSlot）：管口上显编号、下显 DN；阀门执行机构显 F.C. / F.O.
# 下方四个辅助以与上方单标签辅助完全相同的方式解析**一个**槽，含单实例覆盖。


# Text for one slot: template -> property value -> short code.
# 单个槽的文字：模板 -> 属性取值 -> 短码。
static func gpSlotText(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot,
		gpLocale: String = "zh") -> String:
	if gpNode == null or gpSlot == null:
		return ""
	var gpName: String = GPPropertyResolver.gpDisplayName(
		gpNode.gpNames,
		gpDef.gpDisplayName if gpDef != null else "",
		gpLocale,
		gpNode.gpTag)
	var gpText: String = GPPropertyResolver.gpLabelTextWithProps(gpSlot.gpFormat, gpNode.gpTag,
		gpName, gpDef.gpSchema if gpDef != null else null, gpNode.gpProps)
	gpText = gpText.strip_edges()
	# Short code: the CANVAS shows "F.C." / "F.O." while the stored VALUE stays "FC 故障关" — the
	# mapping is display-only, so nothing the user typed is ever rewritten (plan §14).
	# 短码：**画布**显示 "F.C." / "F.O."，而存储的**取值**仍是 "FC 故障关" —— 该映射只作用于显示，
	# 故用户录入的内容永不被改写（规划 §14）。
	if gpSlot.gpShortMap.has(gpText):
		gpText = str(gpSlot.gpShortMap[gpText])
	return gpText


# Whether a slot should be shown at all, honouring an optional "<key> != <value>" / "== <value>"
# guard. An absent or unparsable guard means visible, so a typo hides nothing silently.
# 某个槽是否应当显示，遵守可选的 "<key> != <value>" / "== <value>" 护栏。
# 护栏缺失或无法解析时视为可见，故拼写错误不会静默隐藏内容。
static func gpSlotVisible(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot) -> bool:
	if gpSlot == null:
		return false
	if gpNode == null:
		return true
	var gpGuard: String = gpSlot.gpVisibleWhen.strip_edges()
	if gpGuard == "":
		return true
	var gpOp: String = "!="
	var gpAt: int = gpGuard.find("!=")
	if gpAt < 0:
		gpOp = "=="
		gpAt = gpGuard.find("==")
	if gpAt < 0:
		return true
	var gpKey: String = gpGuard.substr(0, gpAt).strip_edges()
	if gpKey == "":
		return true
	var gpWant: String = gpGuard.substr(gpAt + gpOp.length()).strip_edges()
	var gpVal: Variant = GPPropertyResolver.gpEffectiveValue(
		gpDef.gpSchema if gpDef != null else null, gpNode.gpProps, gpKey)
	var gpText: String = "" if gpVal == null else str(gpVal)
	if gpOp == "!=":
		return gpText != gpWant
	return gpText == gpWant


# Effective anchor of one slot WITHOUT the mount-axis turn: instance override wins, then the
# slot's own declaration. The GEOMETRY of the offset is computed from this base anchor.
# 单个槽的生效锚点，**不含**安装轴转向：单实例覆盖胜出，其次槽位自身声明。偏移的**几何**
# 由该基准锚点计算。
static func gpSlotBaseAnchor(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot) -> int:
	if gpSlot == null:
		return GPLabelAnchor.GPAnchor.GP_BELOW
	var gpA: int = gpSlot.gpAnchor
	if gpNode != null:
		var gpOv: Variant = gpNode.gpLabelSlotOverrides.get(gpSlot.gpKey, null)
		if gpOv is Dictionary and (gpOv as Dictionary).has("anchor"):
			gpA = int((gpOv as Dictionary)["anchor"])
	return gpA


# Effective anchor of one slot: the base anchor turned so the layout follows the part's mount
# axis (see gpLabelQuarters()). The turned anchor decides the world SIDE and the text ALIGNMENT;
# the offset GEOMETRY is gpSlotOffsetLocal's job.
# 单个槽的生效锚点：基准锚点经转向，使版式跟随部件的安装轴（见 gpLabelQuarters()）。转向锚点
# 决定**世界侧别**与文字**对齐**；偏移**几何**由 gpSlotOffsetLocal 负责。
static func gpSlotAnchor(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot,
		gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable()) -> int:
	return GPLabelAnchor.gpRotateAnchor(gpSlotBaseAnchor(gpNode, gpDef, gpSlot),
		gpLabelQuarters(gpGraph, gpLookup, gpDef, gpNode))


# Effective NORMALISED offset of one slot, resolved the same way as the anchor.
# 单个槽的生效**归一化**偏移，解析方式与锚点相同。
static func gpSlotOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot) -> Vector2:
	if gpSlot == null:
		return Vector2.ZERO
	var gpOff: Vector2 = gpSlot.gpOffset
	if gpNode != null:
		var gpOv: Variant = gpNode.gpLabelSlotOverrides.get(gpSlot.gpKey, null)
		if gpOv is Dictionary and (gpOv as Dictionary).has("offset"):
			var gpRaw: Variant = (gpOv as Dictionary)["offset"]
			if gpRaw is Vector2:
				gpOff = gpRaw
			elif gpRaw is Array and (gpRaw as Array).size() >= 2:
				gpOff = Vector2(float((gpRaw as Array)[0]), float((gpRaw as Array)[1]))
	return gpOff


# Pixel offset of one slot — the value GPSymbolView draws at (mirrors gpLocalOffset).
# 单个槽的像素偏移 —— GPSymbolView 据此绘制（与 gpLocalOffset 对应）。
#
# UNTURNED (gpQ == 0) the base anchor's local formula applies directly. TURNED (a part standing on
# a vertical face) the anchor names a WORLD side, so the offset is computed in the WORLD frame —
# against the world-aligned envelope whose extents SWAP for a ±90° mount — and returned AS a
# view-frame vector. The text node never rotates (labels stay upright by design), so the view
# frame's axes ARE the world's axes: rotating the vector "back" into the mount frame put the
# number on the riser's TIP (above the glyph) instead of alongside it — the user's screenshot.
# 未转向（gpQ == 0）时直接套用基准锚点的本地公式。已转向（部件立于竖直面）时锚点指的是**世界
# 侧别**，故偏移须在**世界系**中计算 —— 对齐世界包络（±90° 挂载下两轴 extents 对调）—— 并以
# **视图系向量**原样返回。文字节点从不旋转（标签按设计恒为正立），故视图系的轴就是世界的轴：
# 若把向量「旋回」挂载系，编号会落到竖管**端头**（字形上方）而非管侧 —— 即用户截图所示。
# NOTE: only the turned case consumes the mount frame's rotation here; a FLIPPED host with a
# turned label is left to a later round (the anchor turn itself already ignores flipping).
# 注意：此处只有转向情形消费挂载坐标系的旋转；「翻转宿主 + 转向标签」留给后续轮次
#（锚点转向本身也已忽略翻转）。
static func gpSlotOffsetLocal(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot,
		gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable()) -> Vector2:
	var gpOff: Vector2 = gpSlotOffset(gpNode, gpDef, gpSlot)
	var gpSz: Vector2 = gpEnvelope(gpDef)
	var gpQ: int = gpLabelQuarters(gpGraph, gpLookup, gpDef, gpNode)
	if gpQ == 0:
		return GPLabelAnchor.gpOffsetWorld(gpSlotBaseAnchor(gpNode, gpDef, gpSlot), gpOff, gpSz,
			gpGapFor(gpSz))
	var gpAt: int = GPLabelAnchor.gpRotateAnchor(gpSlotBaseAnchor(gpNode, gpDef, gpSlot), gpQ)
	return GPLabelAnchor.gpOffsetWorld(gpAt, gpOff, Vector2(gpSz.y, gpSz.x), gpGapFor(gpSz))


# Symbol-local offset the DRAG GRIP rides at. For a slot-bearing symbol that is the FIRST slot —
# exactly where GPSymbolView draws it — so the drawn handle and its hit test can never disagree.
# 拖拽**抓取点**所在的图元本地偏移。对带槽图元取**首个**槽 —— 即 GPSymbolView 绘制它的位置 ——
# 故画出的手柄与其命中测试绝不会互相矛盾。
static func gpGripOffsetLocal(gpNode: GPPIDNode, gpDef: GPSymbolDef,
		gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable()) -> Vector2:
	if gpNode == null:
		return Vector2.ZERO
	if gpDef != null and not gpDef.gpLabelSlots.is_empty():
		return gpSlotOffsetLocal(gpNode, gpDef, gpDef.gpLabelSlots[0], gpGraph, gpLookup)
	return gpLocalOffset(gpNode, gpDef)


# WORLD position of the label anchor point, with the symbol's flip and rotation applied.
# 标签锚点的**世界**坐标，已施加图元的翻转与旋转。
static func gpWorldPos(gpNode: GPPIDNode, gpDef: GPSymbolDef,
		gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable()) -> Vector2:
	if gpNode == null:
		return Vector2.ZERO
	var gpOff: Vector2 = gpGripOffsetLocal(gpNode, gpDef, gpGraph, gpLookup)
	if gpNode.gpFlipped:
		gpOff.x = -gpOff.x
	gpOff = gpOff.rotated(deg_to_rad(gpNode.gpRotationDeg))
	return gpNode.gpPosition + gpOff


# Turn a world-space drag delta into the new NORMALISED offset. The delta is un-rotated and
# un-mirrored first, because the user drags on screen while the offset lives in the symbol's
# own frame — otherwise dragging a rotated valve moves its tag sideways.
# 把世界坐标下的拖拽位移换算为新的**归一化**偏移。位移先被反旋转、反镜像，
# 因为用户在屏幕上拖，而偏移活在图形自身坐标系里——否则拖动一个旋转过的阀门会让位号横向跑。
static func gpDragToOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef,
		gpWorldDelta: Vector2) -> Vector2:
	if gpNode == null:
		return Vector2.ZERO
	var gpD: Vector2 = gpWorldDelta.rotated(deg_to_rad(-gpNode.gpRotationDeg))
	if gpNode.gpFlipped:
		gpD.x = -gpD.x
	var gpSz: Vector2 = gpEnvelope(gpDef)
	var gpCur: Vector2 = gpEffectiveOffset(gpNode, gpDef)
	var gpNext: Vector2 = gpCur + Vector2(
		gpD.x / maxf(gpSz.x * 0.5, 1.0),
		gpD.y / maxf(gpSz.y * 0.5, 1.0))
	return GPLabelAnchor.gpClamp(gpEffectiveAnchor(gpNode, gpDef), gpNext)


# Horizontal text alignment for an anchor: a label to the LEFT of the glyph reads right-
# aligned (it hangs off the left edge); INSIDE is centred.
# 锚点对应的文本水平对齐：位于字形**左侧**的标签用右对齐（它从左边悬挂出来）；
# INSIDE 居中。
static func gpAlignFor(gpAnchor: int) -> HorizontalAlignment:
	match gpAnchor:
		GPLabelAnchor.GPAnchor.GP_LEFT:
			return HORIZONTAL_ALIGNMENT_RIGHT
		GPLabelAnchor.GPAnchor.GP_RIGHT:
			return HORIZONTAL_ALIGNMENT_LEFT
		_:
			return HORIZONTAL_ALIGNMENT_CENTER


# Where the text's top-left corner goes, given the anchor point and the measured text size.
# 给定锚点与测量出的文字尺寸，文字左上角应放在哪里。
#
# NOTE ON THE ALIGNMENT ARGUMENT passed by callers / 关于调用方所传「对齐」参数的说明：
# Godot IGNORES HorizontalAlignment when the draw width is negative (measured: LEFT/CENTER/RIGHT
# all start at the same x with width = -1). The position therefore comes ENTIRELY from this
# function, which is why it returns a top-left corner rather than relying on the engine.
# Godot 在绘制宽度为负时**忽略**对齐参数（实测：width = -1 时 LEFT/CENTER/RIGHT 三者起点 x 相同）。
# 故位置**完全**由本函数决定 —— 这正是它返回「左上角」而不依赖引擎的原因。
static func gpTextOrigin(gpAnchor: int, gpAnchorPos: Vector2, gpTextSize: Vector2) -> Vector2:
	match gpAnchor:
		GPLabelAnchor.GPAnchor.GP_LEFT:
			return gpAnchorPos - Vector2(gpTextSize.x, gpTextSize.y * 0.5)
		GPLabelAnchor.GPAnchor.GP_RIGHT:
			return gpAnchorPos - Vector2(0.0, gpTextSize.y * 0.5)
		_:
			return gpAnchorPos - Vector2(gpTextSize.x * 0.5, gpTextSize.y * 0.5)


# Drawn origin of the label: what to hand draw_string inside the counter-scaled frame.
# 标签的绘制原点：在反向缩放坐标系内交给 draw_string 的值。
#
# TWO UNITS MEET HERE, AND THE WHOLE POINT IS NOT TO MAGNIFY ONE OF THEM TWICE.
# 此处相遇两种单位，全部要点在于**不可对其中之一重复施加缩放**：
#   * the anchor offset lives in WORLD units (mm) and MUST be magnified by the canvas scale;
#   * gpTextOrigin() measures the text, so it already works in the unit the glyph is drawn in
#     (design pixels) and must NOT be magnified again.
#   * 锚点偏移是世界单位（mm），**必须**乘以画布缩放；
#   * gpTextOrigin() 是对文字的测量，其单位已是字形的绘制单位（设计像素），**绝不**可再乘一次。
# Multiplying the SUM — which is what the draw site used to do — flies the text off at a rate
# proportional to the zoom, because the text-origin term grew with the zoom while the glyph bitmap
# did not. That is exactly the reported "the tag wanders off when I zoom, and the grip cannot bring
# it back": the grip is drawn at the true world offset, so no amount of dragging can make a
# zoom-scaled ghost line up with it.
# 对**和式**施乘 —— 绘制点原先正是如此 —— 会使文字以与缩放成正比的速度飞离，因为文字原点项随缩放
# 增长而字形位图并未随之增长。这正是用户报告的「一缩放位号就跑掉、手柄也调不回来」：手柄画在真实的
# 世界偏移处，故无论怎么拖，那个被多乘了一次的幽灵都无法与它重合。
# [param gpOffsetWorld] symbol-local anchor offset, world units (mm) / 图元本地锚点偏移，世界单位（mm）
# [param gpTextSizePx] measured text size in design pixels / 实测文字尺寸（设计像素）
# [param gpScale] accumulated canvas scale / 画布累积缩放
static func gpDrawOrigin(gpAnchor: int, gpOffsetWorld: Vector2, gpTextSizePx: Vector2,
		gpScale: float) -> Vector2:
	var gpK: float = maxf(gpScale, 0.0001)
	return gpOffsetWorld * gpK + gpTextOrigin(gpAnchor, Vector2.ZERO, gpTextSizePx)


# Whether a world point is on the grip. / 世界点是否落在抓取点上。
static func gpHitGrip(gpWorld: Vector2, gpNode: GPPIDNode, gpDef: GPSymbolDef,
		gpTol: float, gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable()) -> bool:
	if gpNode == null:
		return false
	return gpWorld.distance_to(gpWorldPos(gpNode, gpDef, gpGraph, gpLookup)) <= gpTol


# ---------------------------------------------------------------- drag state

var gpCv: GPCanvas2D

# Node id whose label is being dragged ("" when nothing is in flight).
# 正被拖动标签的节点 id（无进行时为空）。
var _gpNodeId: String = ""

# World position where the drag began. / 拖拽开始时的世界坐标。
var _gpStartWorld: Vector2 = Vector2.ZERO

# Offset before the drag, captured so a plain click never perturbs the value.
# 拖拽前的偏移，捕获它使单纯的点击不会扰动取值。
var _gpStartOffset: Vector2 = Vector2.ZERO

# Live preview offset applied to the node during the drag.
# 拖拽过程中应用到节点上的实时预览偏移。
var _gpLiveOffset: Vector2 = Vector2.ZERO


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# Hover feedback: show a MOVE cursor while the grip is under the cursor. Returns true
# when the caller should consume the motion event (so port hover does not fight it).
# 悬停反馈：抓取点在光标下时显示移动光标。返回 true 表示调用方应消费该移动事件
# （使端口悬停不会与之争抢）。
func gpUpdateHoverCursor(gpWorld: Vector2) -> bool:
	if gpCv == null:
		return false
	# 放置虚影预览期间让出光标控制权：input_router 在本函数返回 true 时会直接 return，链末的
	# GPPlaceTool.gpOnMove() 便不会执行，手型会被锁在本函数设的 MOVE 上、虚影也不跟随。返回 false
	# 让位给 PlaceTool，由它独占手型。/ Yield the cursor while a symbol is pending: input_router
	# returns early when this handler reports true, which would skip GPPlaceTool.gpOnMove() at the end
	# of the chain and freeze the cursor on MOVE. False hands control back to PlaceTool.
	if gpCv.gpPendingDef != null:
		return false
	if _gpNodeId != "":
		gpCv.mouse_default_cursor_shape = Control.CURSOR_MOVE
		return true
	if gpCv.gpGraph == null or gpCv.gpSelection.size() != 1:
		gpCv.mouse_default_cursor_shape = Control.CURSOR_ARROW
		return false
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpCv.gpSelection[0])
	if gpN == null:
		gpCv.mouse_default_cursor_shape = Control.CURSOR_ARROW
		return false
	var gpDef: GPSymbolDef = gpCv.gpDefFor(gpN.gpSymbolId)
	var gpT: float = 8.0 / maxf(gpCv.gpViewZoom, 0.0001)
	if gpHitGrip(gpWorld, gpN, gpDef, gpT, gpCv.gpGraph, gpCv.gpDefLookupCallable()):
		gpCv.mouse_default_cursor_shape = Control.CURSOR_MOVE
		return true
	gpCv.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return false


# True while a label drag is in flight. / 标签拖拽进行中返回真。
func gpIsDragging() -> bool:
	return _gpNodeId != ""


# The node id being dragged ("" when idle). / 正被拖动的节点 id（空闲时为空）。
func gpDraggingNodeId() -> String:
	return _gpNodeId


# Begin a drag when the grip is under the cursor. Returns false so the caller can fall
# through to ordinary node selection when the press was not on the grip.
# 抓取点在光标下时开始拖拽。未命中返回 false，使调用方在按下的不是抓取点时
# 能继续走普通的节点选择流程。
func gpTryStart(gpWorld: Vector2, gpNodeId: String, gpTol: float = 6.0) -> bool:
	if gpCv == null or gpCv.gpGraph == null or gpNodeId == "":
		return false
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpNodeId)
	if gpN == null:
		return false
	var gpDef: GPSymbolDef = gpCv.gpDefFor(gpN.gpSymbolId)
	var gpT: float = gpTol / maxf(gpCv.gpViewZoom, 0.0001)
	if not gpHitGrip(gpWorld, gpN, gpDef, gpT, gpCv.gpGraph, gpCv.gpDefLookupCallable()):
		return false
	_gpNodeId = gpNodeId
	_gpStartWorld = gpWorld
	_gpStartOffset = gpN.gpLabelOffset
	_gpLiveOffset = gpN.gpLabelOffset
	return true


# Live preview: write the dragged offset straight onto the node so the tag follows the
# cursor. The real commit happens on release, as ONE undo step.
# 实时预览：把拖拽出的偏移直接写到节点上，使位号跟随光标。真正的提交在释放时进行，
# 且合成**一个**撤销步。
func gpOnGripMove(gpWorld: Vector2) -> void:
	if _gpNodeId == "" or gpCv == null or gpCv.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return
	var gpDef: GPSymbolDef = gpCv.gpDefFor(gpN.gpSymbolId)
	# The node still holds the drag-start offset, so the delta is measured from there —
	# accumulating per-move deltas would drift with the frame rate.
	# 节点上仍是拖拽起始偏移，故位移自那里起算——按每次移动累加位移会随帧率漂移。
	gpN.gpLabelOffset = _gpStartOffset
	_gpLiveOffset = gpDragToOffset(gpN, gpDef, gpWorld - _gpStartWorld)
	gpN.gpLabelOffset = _gpLiveOffset
	# The text is drawn by GPSymbolView, so the VIEWS must repaint — the canvas repaints
	# only its own background and would leave the tag frozen where it was.
	# 文字由 GPSymbolView 绘制，故必须重绘**视图** —— 画布只重绘自己的背景，
	# 标签会僵在原地不动。
	gpCv.gpRefreshSymbolViews()
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()


# Commit the drag: rewind to the original offset, then let the command re-apply the same
# value — one undo step, never applied twice (mirrors the node-move pattern).
# 提交拖拽：先回退到原偏移，再由命令重新应用同一个值——一个撤销步，且绝不会叠加两次
# （与节点移动同一手法）。
func gpEndGripDrag() -> void:
	if _gpNodeId == "" or gpCv == null or gpCv.gpGraph == null:
		return
	var gpId: String = _gpNodeId
	var gpNew: Vector2 = _gpLiveOffset
	_gpNodeId = ""
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
	if gpN != null:
		gpN.gpLabelOffset = _gpStartOffset
		if gpN.gpLabelOffset != gpNew:
			gpCv.gpRequestSetLabelOffset(gpId, gpNew)
	gpCv.gpRefreshSymbolViews()
	gpCv.queue_redraw()


# Abandon the drag without committing. / 放弃拖拽，不提交。
func gpCancelDrag() -> void:
	if _gpNodeId == "" or gpCv == null or gpCv.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(_gpNodeId)
	if gpN != null:
		gpN.gpLabelOffset = _gpStartOffset
	_gpNodeId = ""
	gpCv.gpRefreshSymbolViews()
	gpCv.queue_redraw()


# Double-click the grip: reset to the type layer's default (unset offset, auto anchor).
# 双击抓取点：复位为类型层默认（偏移未设置、锚点自动）。
func gpReset(gpNodeId: String) -> void:
	if gpCv == null or gpNodeId == "":
		return
	gpCv.gpRequestSetLabelOffset(gpNodeId, GPLabelAnchor.GP_OFFSET_UNSET)
	gpCv.gpRefreshSymbolViews()
	gpCv.queue_redraw()
