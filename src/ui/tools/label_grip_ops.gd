class_name GPLabelGripOps
extends RefCounted
# Copyright © 2026 Jonson Wang
# Label (位号) placement on the sheet: geometry plus the drag interaction (M10b).
# 图纸上的标签（位号）定位：几何 + 拖拽交互（M10b）。
#
# Everything above the "drag state" divider is PURE and headless-testable: given a node and
# its definition it answers "where does the tag sit?" and "what offset does this drag mean?".
# Only the last three methods touch the canvas.
# 「拖拽状态」分隔线以上的部分全是纯函数、可 headless 测试：给定节点与其定义，回答
# 「位号画在哪」与「这次拖拽意味着什么偏移」。只有最后三个方法触碰画布。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Gap between the envelope edge and the text, in pixels. Mirrors GPSymbolView.GP_LABEL_GAP.
# 包络边缘到文字的间距（像素）。与 GPSymbolView.GP_LABEL_GAP 一致。
const GP_GAP: float = 7.0

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


# The envelope used for scaling. A missing definition falls back to a sane default so the
# geometry never divides by zero.
# 用于缩放的包络。定义缺失时回落到合理默认值，使几何永不会除以零。
static func gpEnvelope(gpDef: GPSymbolDef) -> Vector2:
	if gpDef != null and gpDef.gpDefaultSize.x > 0.0 and gpDef.gpDefaultSize.y > 0.0:
		return gpDef.gpDefaultSize
	return Vector2(64.0, 48.0)


# Symbol-LOCAL offset (before flipping / rotating). This is the value the renderer needs:
# the node itself carries no rotation, so the rotation is applied by the caller.
# 图元**本地**偏移（翻转 / 旋转之前）。这是渲染器需要的值：
# 节点本身不承载旋转，旋转由调用方施加。
static func gpLocalOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> Vector2:
	var gpAnchor: int = gpEffectiveAnchor(gpNode, gpDef)
	var gpOff: Vector2 = gpEffectiveOffset(gpNode, gpDef)
	return GPLabelAnchor.gpOffsetWorld(gpAnchor, gpOff, gpEnvelope(gpDef), GP_GAP)


# WORLD position of the label anchor point, with the symbol's flip and rotation applied.
# 标签锚点的**世界**坐标，已施加图元的翻转与旋转。
static func gpWorldPos(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> Vector2:
	if gpNode == null:
		return Vector2.ZERO
	var gpOff: Vector2 = gpLocalOffset(gpNode, gpDef)
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
static func gpTextOrigin(gpAnchor: int, gpAnchorPos: Vector2, gpTextSize: Vector2) -> Vector2:
	match gpAnchor:
		GPLabelAnchor.GPAnchor.GP_LEFT:
			return gpAnchorPos - Vector2(gpTextSize.x, gpTextSize.y * 0.5)
		GPLabelAnchor.GPAnchor.GP_RIGHT:
			return gpAnchorPos - Vector2(0.0, gpTextSize.y * 0.5)
		_:
			return gpAnchorPos - Vector2(gpTextSize.x * 0.5, gpTextSize.y * 0.5)


# Whether a world point is on the grip. / 世界点是否落在抓取点上。
static func gpHitGrip(gpWorld: Vector2, gpNode: GPPIDNode, gpDef: GPSymbolDef,
		gpTol: float) -> bool:
	if gpNode == null:
		return false
	return gpWorld.distance_to(gpWorldPos(gpNode, gpDef)) <= gpTol


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
	if gpHitGrip(gpWorld, gpN, gpDef, gpT):
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
	if not gpHitGrip(gpWorld, gpN, gpDef, gpT):
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
