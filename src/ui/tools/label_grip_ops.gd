class_name GPLabelGripOps
extends RefCounted
# Copyright © 2026 Jonson Wang
# Label (位号) DRAG interaction on the sheet. The arithmetic behind it lives in
# GPLabelPlacement (core) — see the section header there, and P0-4 in the W12 architecture review.
# 图纸上标签（位号）的**拖拽交互**。其背后的算式住在 core 的 GPLabelPlacement —— 见彼处节首，
# 以及 W12 架构审查的 P0-4。
#
# WHAT CHANGED AND WHY / 改了什么、为何：
# This class used to hold BOTH halves: pure geometry (computed by GPSymbolView / GPEdgeView, which
# are render) and the drag state machine (which holds a GPCanvas2D). Because the pure half lived
# here, the renderer had to name a ui class to do arithmetic — a render -> ui arrow (D02).
# The pure half moved to core; what remains is only the interaction, plus thin forwards so ui
# callers (and the existing test suites) keep the one name they already use.
# 本类曾同时装两半：纯几何（由 render 的 GPSymbolView / GPEdgeView 计算）与拖拽状态机（持有
# GPCanvas2D）。纯的那半住在这里，渲染器就不得不命名一个 ui 类去做算术 —— 即 render → ui（D02）。
# 纯的一半已迁往 core；此处只剩交互，外加薄转发，使 ui 调用方（与既有测试套件）仍只认一个名字。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Shared with core by reference, not by value: one number, one definition.
# 按引用与 core 共用，而非复制数值：一个数字只有一个定义。
const GP_GAP: float = GPLabelPlacement.GP_GAP
const GP_MIN_GAP: float = GPLabelPlacement.GP_MIN_GAP
const GP_GRIP_SIZE: float = GPLabelPlacement.GP_GRIP_SIZE
const GP_COL: Color = GPLabelPlacement.GP_COL


# ============================================================================
# Forwarded surface — bodies are in GPLabelPlacement (core). Kept here so ui keeps one name.
# 转发面 —— 函数体在 core 的 GPLabelPlacement。保留于此使 ui 只认一个名字。
# ============================================================================

# The text to draw. FORWARDED to GPLabelPlacement (core); see that class' header.
# 要绘制的文字。**转发**至 core 的 GPLabelPlacement；见该类头部。
static func gpLabelText(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpLocale: String = "zh") -> String:
	return GPLabelPlacement.gpLabelText(gpNode, gpDef, gpLocale)


# Effective anchor: the instance wins when it set one, otherwise the type layer's default.
# FORWARDED to GPLabelPlacement (core): the print model must answer "where does the tag sit"
# with the SAME judgment, and core may never reference ui — so the pure body moved there and
# this stays as the ui-side name the drag interaction calls.
# 生效锚点：实例设置过则用实例的，否则用类型层默认。
# **转发**至 core 的 GPLabelPlacement：打印模型必须以**同一判断**回答「位号在哪」，
# 而 core 绝不引用 ui —— 故纯函数体迁往彼处，此处保留拖拽交互调用的 ui 侧名字。
static func gpEffectiveAnchor(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> int:
	return GPLabelPlacement.gpEffectiveAnchor(gpNode, gpDef)


# Effective normalised offset, resolved the same way as the anchor. FORWARDED; see above.
# 生效的归一化偏移，解析方式与锚点相同。**转发**；见上。
static func gpEffectiveOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> Vector2:
	return GPLabelPlacement.gpEffectiveOffset(gpNode, gpDef)


# The gap actually used for a symbol of this envelope size. FORWARDED; see GPLabelPlacement.
# 给定包络尺寸下**实际**使用的间距。**转发**；见 GPLabelPlacement。
#
# WHY NOT A CONSTANT / 为何不能是恒值：
# 7 mm is right for a 10 mm pump, but a nozzle is 4 x 2 mm — a fixed 7 mm gap put its number 8 mm
# off the centre, i.e. four nozzle lengths away, which is the reported "the text sits far too far
# away". Small symbols therefore take HALF their shorter side (a 4x2 nozzle -> 1 mm), floored so
# the text never lands on the glyph; every symbol at least 7 mm on its shorter side keeps the
# historic 7 mm exactly, so equipment annotations never move.
# 7mm 对 10mm 的泵合适，但管嘴只有 4x2mm —— 固定 7mm 会把编号推到离中心 8mm 处，即四个管嘴长，
# 这正是用户报告的「文字离得太远」。故小图元取**短边的一半**（4x2 管嘴 -> 1mm），并设下限使文字
# 绝不压到字形上；短边 ≥7mm 的图元精确保持历史的 7mm，故设备标注不会有任何位移。
static func gpGapFor(gpSize: Vector2) -> float:
	return GPLabelPlacement.gpGapFor(gpSize)


# The envelope used for scaling. A missing definition falls back to a sane default so the
# geometry never divides by zero. FORWARDED; see GPLabelPlacement.
# 用于缩放的包络。定义缺失时回落到合理默认值，使几何永不会除以零。**转发**；见 GPLabelPlacement。
static func gpEnvelope(gpDef: GPSymbolDef) -> Vector2:
	return GPLabelPlacement.gpEnvelope(gpDef)


# Symbol-LOCAL offset (before flipping / rotating). This is the value the renderer needs:
# the node itself carries no rotation, so the rotation is applied by the caller.
# FORWARDED to GPLabelPlacement (core) — the print model consumes the same function there.
# 图元**本地**偏移（翻转 / 旋转之前）。这是渲染器需要的值：
# 节点本身不承载旋转，旋转由调用方施加。
# **转发**至 core 的 GPLabelPlacement —— 打印模型在彼处消费同一函数。
static func gpLocalOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> Vector2:
	return GPLabelPlacement.gpLocalOffset(gpNode, gpDef)


static func gpLabelQuarters(gpGraph: GPPIDGraph, gpLookup: Callable, gpDef: GPSymbolDef, gpNode: GPPIDNode) -> int:
	return GPLabelPlacement.gpLabelQuarters(gpGraph, gpLookup, gpDef, gpNode)


static func gpSlotText(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot, gpLocale: String = "zh") -> String:
	return GPLabelPlacement.gpSlotText(gpNode, gpDef, gpSlot, gpLocale)


static func gpSlotVisible(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot) -> bool:
	return GPLabelPlacement.gpSlotVisible(gpNode, gpDef, gpSlot)


static func gpSlotBaseAnchor(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot) -> int:
	return GPLabelPlacement.gpSlotBaseAnchor(gpNode, gpDef, gpSlot)


static func gpSlotAnchor(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot, gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable()) -> int:
	return GPLabelPlacement.gpSlotAnchor(gpNode, gpDef, gpSlot, gpGraph, gpLookup)


static func gpSlotOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot) -> Vector2:
	return GPLabelPlacement.gpSlotOffset(gpNode, gpDef, gpSlot)


static func gpSlotOffsetLocal(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpSlot: GPLabelSlot, gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable()) -> Vector2:
	return GPLabelPlacement.gpSlotOffsetLocal(gpNode, gpDef, gpSlot, gpGraph, gpLookup)


static func gpGripOffsetLocal(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable()) -> Vector2:
	return GPLabelPlacement.gpGripOffsetLocal(gpNode, gpDef, gpGraph, gpLookup)


static func gpWorldPos(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable()) -> Vector2:
	return GPLabelPlacement.gpWorldPos(gpNode, gpDef, gpGraph, gpLookup)


static func gpDragToOffset(gpNode: GPPIDNode, gpDef: GPSymbolDef, gpWorldDelta: Vector2) -> Vector2:
	return GPLabelPlacement.gpDragToOffset(gpNode, gpDef, gpWorldDelta)


static func gpAlignFor(gpAnchor: int) -> HorizontalAlignment:
	return GPLabelPlacement.gpAlignFor(gpAnchor)


static func gpTextOrigin(gpAnchor: int, gpAnchorPos: Vector2, gpTextSize: Vector2) -> Vector2:
	return GPLabelPlacement.gpTextOrigin(gpAnchor, gpAnchorPos, gpTextSize)


static func gpDrawOrigin(gpAnchor: int, gpOffsetWorld: Vector2, gpTextSizePx: Vector2, gpScale: float) -> Vector2:
	return GPLabelPlacement.gpDrawOrigin(gpAnchor, gpOffsetWorld, gpTextSizePx, gpScale)


static func gpHitGrip(gpWorld: Vector2, gpNode: GPPIDNode, gpDef: GPSymbolDef, gpTol: float, gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable()) -> bool:
	return GPLabelPlacement.gpHitGrip(gpWorld, gpNode, gpDef, gpTol, gpGraph, gpLookup)


# ---------------------------------------------------------------- drag state

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

# True while THIS handler owns the cursor (has set a non-arrow shape and not yet
# handed it back). The cursor is a SINGLE resource with MANY writers on one motion
# event (tag grips, title block, frame band, tools); whoever did not claim it must
# never write per-event, because Godot's mouse_default_cursor_shape setter pushes
# the shape to the OS IMMEDIATELY on every value change ("Display the new cursor
# shape instantly") — an unconditional per-motion ARROW reset followed by another
# writer's MOVE made the OS cursor flip arrow<->move at event rate, i.e. the
# reported "the cursor jitters over the title block". Hence: claim while hovered /
# dragging, hand back exactly once on the way out.
# 本处理器「认领」光标期间为真（已设非箭头形状且尚未归还）。光标是**单一**资源，而同一
# 移动事件里有**多个**写入者（标签抓取点、图签、图框带、工具）；未认领者绝不可逐事件写入
# —— Godot 的 mouse_default_cursor_shape setter 在每次值变化时**立即**下发 OS
# （"Display the new cursor shape instantly"），一条逐移动的 ARROW 重置加上另一写入者的
# MOVE，曾使 OS 光标以事件频率在箭头↔移动间翻转，即用户报告的「指针在图签上抖动」。
# 故立规：悬停 / 拖拽期间认领，退出时**恰好一次**归还。
var _gpCursorClaimed: bool = false


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# Hover feedback: show a MOVE cursor while the grip is under the cursor. Returns true
# when the caller should consume the motion event (so port hover does not fight it).
# 悬停反馈：抓取点在光标下时显示移动光标。返回 true 表示调用方应消费该移动事件
# （使端口悬停不会与之争抢）。
#
# ⚠️ CURSOR WRITES ARE CLAIM/RELEASE, NEVER PER-MOTION RESETS / ⚠️ 光标写入是「认领 / 归还」，
# 绝不逐移动重置：this function runs on EVERY motion event BEFORE the title-block and frame
# probes, so an unconditional `= CURSOR_ARROW` here flips the shape away from whatever those
# writers set, and their re-assert flips it back — two immediate OS writes per event. The ARROW
# below therefore fires ONLY when this handler itself previously claimed the cursor.
# 本函数在**每个**移动事件里先于图签与图框探测运行，故此处一条无条件 `= CURSOR_ARROW` 会把
# 形状从其它写入者设定的值上翻走，对方再翻回来 —— 每事件两次立即 OS 写入。因此下方 ARROW
# 只在本处理器**自己此前认领过**光标时才发出。
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
		# Drag in flight: claim (idempotent — the setter early-returns on an unchanged value).
		# 拖拽进行中：认领（幂等 —— 值不变时 setter 直接早退）。
		if not _gpCursorClaimed:
			gpCv.mouse_default_cursor_shape = Control.CURSOR_MOVE
			_gpCursorClaimed = true
		return true
	var gpClaimNow: bool = false
	if gpCv.gpGraph != null and gpCv.gpSelection.size() == 1:
		var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpCv.gpSelection[0])
		if gpN != null:
			var gpDef: GPSymbolDef = gpCv.gpDefFor(gpN.gpSymbolId)
			var gpT: float = 8.0 / maxf(gpCv.gpViewZoom, 0.0001)
			gpClaimNow = GPLabelPlacement.gpHitGrip(gpWorld, gpN, gpDef, gpT, gpCv.gpGraph, gpCv.gpDefLookupCallable())
	if gpClaimNow:
		if not _gpCursorClaimed:
			gpCv.mouse_default_cursor_shape = Control.CURSOR_MOVE
			_gpCursorClaimed = true
		return true
	# Leave edge (or never claimed): hand the cursor back exactly ONCE.
	# 离开沿（或从未认领）：恰好**一次**归还光标。
	if _gpCursorClaimed:
		gpCv.mouse_default_cursor_shape = Control.CURSOR_ARROW
		_gpCursorClaimed = false
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
	_gpLiveOffset = GPLabelPlacement.gpDragToOffset(gpN, gpDef, gpWorld - _gpStartWorld)
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
