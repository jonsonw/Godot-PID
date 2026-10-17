class_name GPFrameGripOps
extends RefCounted
# Copyright © 2026 Jonson Wang
# Frame (图框) grab band / side handles / drag — Rev.3 stage 0c.
# 图框（图框）抓取带 / 侧手柄 / 拖拽 —— Rev.3 阶段 0c。
#
# WHY THE DRAG NEEDS A GRAB BAND AT ALL / 为何拖拽非要有抓取带：
# the frame rectangle is the whole sheet minus its margins, so "the frame is draggable" read naively
# would mean a 420x297 target — every click anywhere would grab it and no symbol could be picked. The
# frame is therefore grabbable ONLY along its own four lines (band +/- GP_GRAB_PX), which is why this
# test can be dropped into the one branch of GPSelectTool that today only starts a marquee:
# 图框矩形就是纸面减去边距，故「图框可拖」若直白实现即等于一个 420×297 的目标 —— 点哪里都抓到它、任何
# 图元都拾取不了。因此图框**只沿它自己的四条线**可抓（带 ±GP_GRAB_PX），这也正是本检测能塞进
# GPSelectTool 中「今天只会起框选」那一个分支的原因：
# ★ SAFETY PROPERTY / 安全性：it can only ever change what happens where NOTHING was selectable before,
#   so it cannot regress symbol / edge / annotation picking.
#   它只可能改变「过去什么也选不中」的地方的行为，故不可能回归图元 / 边 / 注释图形的拾取。
#
# FOUR GESTURES, THREE SEMANTICS / 四种手势、三种语义：
#   * dragging a SIDE MIDPOINT HANDLE moves that ONE margin  -> resizes the frame;
#   * dragging the LINE ITSELF (the band, away from a handle) moves the WHOLE SHEET — paper, trim line,
#     frame, title block, zone ruler, every symbol, every edge, every annotation and the tracing
#     underlay — rigidly, by ONE command (GPTranslateSheetCommand), so no margin changes at all;
#   * ⌥Alt + dragging the LINE ITSELF keeps the pre-0d gesture -> translates the frame AGAINST its
#     margins (all four traded at once, size unchanged), content and paper staying put.
# Why both are still needed: a translate preserves the SIZE exactly, so it can only trade one margin
# against its opposite — widening a margin on its own therefore REQUIRES the side handle. Since the
# 2026-10-16 amendment NONE of these gestures is bounded by the paper: the frame may be moved or resized
# right off the sheet (a negative margin is how "this frame line is off the sheet" is written down), and
# since stage 0d the paper itself is a movable object. The only limit left is the frame's own
# consistency — a side may not cross its opposite, or the frame would turn inside out and become neither
# drawn nor grabbable (GPFrameGeometry.gpDragSideMargins).
#   * 拖动**侧中点手柄**只改那**一条**边距 -> 改尺寸；
#   * 拖动**线本身**（带上、远离手柄处）整体搬动**整张图纸** —— 纸面、裁边线、图框、图签、坐标带、每个图元、
#     每条边、每个注释图形与追踪底图 **刚性地**一起平移，且经**一条**命令（GPTranslateSheetCommand）提交，
#     故一条边距都不变；
#   * **⌥Alt + 拖线本身**沿用 0d 之前的手势 -> 平移图框**相对其边距**（四条边距同时对冲、尺寸不变），
#     内容与纸面不动。
# 三者仍有必要：平移精确保持尺寸，只能在一条边距与其对边之间做交换 —— 故单独把某条边距改大**必须**靠侧手柄。
# 自 2026-10-16 修正起，这些手势**都不再**受纸面约束：图框可以被挪出、也可以被改到纸外（负边距正是「该条图框
# 线在纸外」的写法），而自阶段 0d 起纸面本身也成了一个可移动的对象。仅剩的限制是图框自身的自洽 —— 一条边不得
# 越过它的对边，否则图框会内翻，既不被绘制也无法抓取（GPFrameGeometry.gpDragSideMargins）。
#
# WHY THE BAND, AND NOT A MODIFIER, IS THE PRIMARY SHEET MOVE / 为何**主**手势是拖带、而不挂修饰键：
# the user's words were 「纸的边界可以跟着图框一起移动」 — the FRAME LINE is what they reach for, so the
# line must be the plain gesture and the frame-against-margins legacy must be the one that hides behind a
# modifier. Reversing the two would make the requested behaviour invisible.
# 用户的原话是「纸的边界可以跟着图框一起移动」—— 用户伸手去抓的就是**图框线**，故线必须是那个不带修饰键的
# 手势，而「图框相对边距平移」这个旧语义才该藏到修饰键后面。若把两者对调，用户要求的行为就变成不可见的了。
#
# WHY ⌥Alt AND NOT SHIFT OR CTRL / 为何选 ⌥Alt 而不是 Shift 或 Ctrl：Shift is already threaded through
# this whole input chain as "additive selection" (gpShift survives from GPCanvas2D down to every tool), and
# Ctrl is the accelerator for undo/redo/copy — putting a drag semantic on either would make two different
# meanings share one key inside one gesture. Alt was the only free modifier.
# Shift 在这条输入链上自 GPCanvas2D 一路到每个工具都已被「追加选择」占用，Ctrl 是撤销/重做/复制的加速键 ——
# 把拖拽语义挂到任一个上，都会让同一个手势里的同一个键承载两种含义。Alt 是唯一空着的修饰键。
#
# Everything down to the "drag state" divider is PURE and headless-testable; everything from the
# "hover + overlay" divider down touches the canvas (plus the drag driver, which by construction is the
# only thing that writes). The geometry itself lives in GPFrameGeometry (one fact, one home) — this class
# decides WHICH gesture a press means and drives it, and never re-derives a rectangle.
# 「拖拽状态」分隔线以上的部分全是纯函数、可 headless 测试；自「悬停 + 覆盖层」分隔线起（外加拖拽驱动器
# 本身 —— 按构造它就是唯一写入者）触碰画布。几何本身在 GPFrameGeometry（一个事实一个家）—— 本类只判定
# 一次按下**意味着哪种手势**并驱动它，绝不重算矩形。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Half-width of the grab band around each frame line, in SCREEN pixels.
# 每条图框线两侧抓取带的半宽（**屏幕**像素）。
# Screen-constant on purpose: the band is a pointing affordance, so it must not shrink to nothing when
# the user zooms out to see the whole sheet — which is exactly when they are most likely to move it.
# 刻意取屏幕常量：抓取带是「指着」用的可及性区域，不能因为用户缩小到整幅视图就缩没了 —— 而那恰恰是
# 最可能去挪图框的时候。
const GP_GRAB_PX: float = 6.0

# Edge length of the side-handle square, in screen pixels (matches GPLabelGripOps.GP_GRIP_SIZE).
# 侧手柄方块的边长（屏幕像素，与 GPLabelGripOps.GP_GRIP_SIZE 一致）。
const GP_GRIP_SIZE: float = 9.0

# Grip colour: the same blue-on-white as the tag / edge grips, so "this square is draggable" reads the
# same everywhere in the editor.
# 抓取点配色：与位号 / 边抓取点相同的「蓝描边白填充」，使「这个方块可拖」在编辑器各处读作同一件事。
const GP_COL: Color = Color(0.20, 0.50, 1.0)

# Smallest zoom the tolerances are computed against, so a degenerate zoom cannot produce an infinite
# band that swallows the sheet.
# 计算容差时的最小缩放，使退化缩放不会产出一条吞掉整张纸的无限抓取带。
const GP_MIN_ZOOM: float = 0.0001


# Grab tolerance in WORLD mm for a given canvas zoom. Pure, so the band width is testable without a
# canvas.
# 给定画布缩放下的抓取容差（世界毫米）。纯函数，使带宽度无需画布即可测试。
static func gpGrabTol(gpZoom: float) -> float:
	return GP_GRAB_PX / maxf(gpZoom, GP_MIN_ZOOM)


# ---------------------------------------------------------------- drag state

var gpCv: GPCanvas2D = null

# True while a frame drag is in flight. / 图框拖拽进行中时为真。
var _gpActive: bool = false

# True when the drag means TRANSLATE (band) rather than RESIZE (side handle).
# 该拖拽意味着**平移**（抓取带）还是**改尺寸**（侧手柄）时为真。
# ⚠️ Since stage 0d "translate" is AMBIGUOUS and always paired with _gpMoveSheet below; never read this
# field on its own to decide what a band drag does.
# ⚠️ 自阶段 0d 起「平移」是有歧义的，恒与下方 _gpMoveSheet 配对判断；绝不可单读本字段来判定拖带做什么。
var _gpPan: bool = false

# True when a BAND drag moves the WHOLE SHEET (paper + trim line + frame + title block + zone ruler +
# every symbol / edge / annotation / underlay), false when it moves the frame against its margins.
# 拖带是搬动**整张图纸**（纸面 + 裁边线 + 图框 + 图签 + 坐标带 + 全部图元/边/注释/底图）时为真；
# 为假时表示它改的是图框相对边距的位置。
#
# WHY A SECOND FLAG AND NOT A THIRD VALUE OF _gpPan / 为何另立一个标志、而不给 _gpPan 加第三个取值：
# a band drag is TWO independent bits — "which object moves" (sheet or frame) and "how it moves" (rigid
# translate or margin trade). Resizing shares the second bit's answer, so folding both into one enum
# would invent a combination that cannot occur and make the resize branch test a value it never sees.
# 拖带本身含**两个独立位** —— 「谁在动」（纸还是图框）与「怎么动」（刚性平移还是边距对冲）。改尺寸与后者
# 共用答案，故把两者并成一个枚举会凭空造出一个不可能发生的组合，还会让改尺寸分支去判定一个它永远看不到的值。
var _gpMoveSheet: bool = false

# The side being resized, or GPFrameGeometry.GP_SIDE_NONE for a translate.
# 正在改的那条边；平移时为 GPFrameGeometry.GP_SIDE_NONE。
var _gpSide: int = GPFrameGeometry.GP_SIDE_NONE

# World position where the drag began (the translate delta is measured from here, never accumulated).
# 拖拽起始的世界坐标（平移位移自此处量起，绝不逐帧累加）。
var _gpStartWorld: Vector2 = Vector2.ZERO

# Margins before the drag, captured so a plain click never perturbs the sheet and a release can rewind
# to a clean baseline before the single undo step is committed.
# 拖拽前的边距，捕获它使单纯的点击不会扰动图纸，且释放时能回退到干净基线再提交**一个**撤销步。
var _gpStartMargins: Array = []

# Live preview margins applied to the sheet during the drag.
# 拖拽过程中应用到图纸上的实时预览边距。
var _gpLiveMargins: Array = []

# Sheet origin before the drag, and the geometry snapshot of everything ON the sheet (stage 0d).
# 拖拽前的图纸原点，以及纸上一切物的几何快照（阶段 0d）。
#
# ⚠️ THE PAPER ORIGIN IS NOT IN THE SNAPSHOT, ON PURPOSE / ⚠️ 纸面原点**刻意不**放进快照里：
# GPPIDGraph owns the objects on the sheet and GPSheet owns the paper; GPTranslateSheetCommand therefore
# takes the paper from its constructor and the content from gpCtx.gpGraph (see its header). Keeping that
# same split here means the drag preview and the committed command read the two halves from the same two
# owners — the snapshot is passed to the command verbatim, so there is ONE enumeration of the geometry,
# not two that could drift.
# GPPIDGraph 拥有纸上的对象、GPSheet 拥有纸面，故 GPTranslateSheetCommand 由构造参数取纸、由 gpCtx.gpGraph
# 取内容（见其文件头）。此处沿用同一分工，使拖拽预览与最终提交的命令从同样的两个属主读取两半 —— 快照被原样
# 交给命令，故几何的枚举只有**一份**，而不是可能分家的两份。
var _gpStartOrigin: Vector2 = Vector2.ZERO
var _gpSnap: Dictionary = {}

# Side the pointer is currently over (handle OR band), or GP_SIDE_NONE.
# 指针当前所在的边（手柄**或**抓取带），或 GP_SIDE_NONE。
var _gpHoverSide: int = GPFrameGeometry.GP_SIDE_NONE

# True when that hover landed on a side HANDLE rather than on the plain band (decides the cursor).
# 该悬停落在侧**手柄**上（而非纯抓取带）时为真 —— 它决定光标形态。
var _gpHoverHandle: bool = false


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# ---------------------------------------------------------------- pure probes

# True when the frame may be grabbed at all: a sheet exists and draws its frame.
# 图框是否可被抓取：图纸存在且绘制图框。
#
# WHY gpFrameOn GATES IT / 为何受 gpFrameOn 约束：with the frame switched off nothing is drawn, so a
# grab band would be an invisible target the user cannot see and would not understand. Every probe
# below shares this gate, so "visible" and "grabbable" cannot drift apart.
# 图框关闭时不画任何东西，此时抓取带会成为一个用户看不见、也理解不了的隐形目标。下方每个探测共用此
# 闸门，使「可见」与「可抓」不会分家。
func gpCanGrab() -> bool:
	return gpCv != null and gpCv.gpSheet != null and gpCv.gpSheet.gpFrameOn


# The side a world point would grab via a HANDLE, or GP_SIDE_NONE.
# 世界点经**手柄**能抓到哪条边，或 GP_SIDE_NONE。
func gpHitHandle(gpWorld: Vector2) -> int:
	if not gpCanGrab():
		return GPFrameGeometry.GP_SIDE_NONE
	return GPFrameGeometry.gpHitSideHandle(gpCv.gpSheet, gpWorld, gpGrabTol(gpCv.gpViewZoom))


# The side a world point would grab via the BAND, or GP_SIDE_NONE.
# 世界点经**抓取带**能抓到哪条边，或 GP_SIDE_NONE。
func gpHitBand(gpWorld: Vector2) -> int:
	if not gpCanGrab():
		return GPFrameGeometry.GP_SIDE_NONE
	return GPFrameGeometry.gpFrameSideAt(gpCv.gpSheet, gpWorld, gpGrabTol(gpCv.gpViewZoom))


# True while a frame drag is in flight. / 图框拖拽进行中时为真。
func gpIsDragging() -> bool:
	return _gpActive


# The side being hovered (handle or band), for tests and the overlay.
# 正在悬停的那条边（手柄或抓取带），供测试与覆盖层使用。
func gpHoverSide() -> int:
	return _gpHoverSide


# ---------------------------------------------------------------- drag

# Begin a drag when the press landed on a handle or on the frame's band. Returns false so the caller
# can fall through to ordinary selection / marquee when it did not.
# 按下落在手柄或图框抓取带上时开始拖拽。未命中返回 false，使调用方能继续走普通的选择 / 框选流程。
#
# ⚠️ THE HANDLE IS TESTED FIRST. It sits ON the line, i.e. inside the band, so testing the band first
# would make the resize gesture unreachable — the whole feature would appear as "dragging only ever
# moves the frame".
# ⚠️ **先测手柄**。手柄就在线上、即在抓取带内，若先测抓取带，改尺寸这一手势将永远够不到 ——
# 整个功能看起来就只是「拖来拖去只能挪框」。
#
# [param gpAlt] ⌥Alt held -> a band drag trades margins instead of moving the sheet. It is a PARAMETER
# and not a live `Input.is_key_pressed()` read inside this class, so the gesture choice stays a pure
# function of its inputs and both branches are testable headless. The call site supplies the live value
# (GPSelectTool, which already reads live modifier state for its own Shift handling).
# [param gpAlt] 按住 ⌥Alt -> 拖带改为对冲边距、而不搬动图纸。它做成**参数**、而不是在本类内实时读
# `Input.is_key_pressed()`，使「这次按下算哪种手势」保持为其输入的纯函数、两个分支都能 headless 测试。
# 实时值由调用点提供（GPSelectTool —— 它本就在为自己的 Shift 处理读取实时修饰键状态）。
#
# WHY THE SNAPSHOT IS TAKEN ONLY ON THE SHEET-MOVE PATH / 为何只在「搬纸」这条路上取快照：
# it is the only gesture that touches content, and capturing it costs a walk over every node, edge,
# annotation and drop-restore record — which a mere press must not pay for on a 900-node drawing.
# 它是唯一触碰内容的那个手势，而捕获要遍历每个节点、边、注释与落点恢复记录 —— 一次单纯的按下不该在
# 900 个节点的图上为此付出代价。
func gpTryStart(gpWorld: Vector2, gpAlt: bool = false) -> bool:
	if not gpCanGrab():
		return false
	var gpHandle: int = gpHitHandle(gpWorld)
	if gpHandle == GPFrameGeometry.GP_SIDE_NONE:
		if gpHitBand(gpWorld) == GPFrameGeometry.GP_SIDE_NONE:
			return false
	_gpActive = true
	_gpPan = gpHandle == GPFrameGeometry.GP_SIDE_NONE
	_gpMoveSheet = _gpPan and not gpAlt
	_gpSide = gpHandle if not _gpPan else GPFrameGeometry.GP_SIDE_NONE
	_gpStartWorld = gpWorld
	_gpStartMargins = gpCv.gpSheet.gpFrameMargins.duplicate()
	_gpLiveMargins = _gpStartMargins.duplicate()
	if _gpMoveSheet:
		_gpStartOrigin = gpCv.gpSheet.gpPaperOrigin
		_gpSnap = gpCv.gpGraph.gpCaptureGeometry() if gpCv.gpGraph != null else {}
	return true


# Live preview: the sheet's margins are written on every motion so the frame, its zone ruler and its
# title block all follow the cursor. The real commit happens on release, as ONE undo step.
# 实时预览：每次移动都把图纸边距写下去，使图框、其坐标带与图签都跟随光标。真正的提交在释放时进行，
# 且为**一个**撤销步。
#
# ⚠️ THE DELTA IS MEASURED FROM THE DRAG START, so the sheet is first rewound to the captured start
# margins. Accumulating per-motion deltas would drift with the frame rate — the same trap
# GPLabelGripOps.gpOnGripMove documents, and the reason the rewind line below is not redundant.
# ⚠️ 位移自**拖拽起点**量起，故先把图纸回退到捕获的起始边距。逐次移动累加会随帧率漂移 ——
# 与 GPLabelGripOps.gpOnGripMove 记录的同一陷阱，也正是下方那行回退并非多余的原因。
func gpOnGripMove(gpWorld: Vector2) -> void:
	if not _gpActive or not gpCanGrab():
		return
	if _gpMoveSheet:
		_gpPreviewSheetMove(gpWorld - _gpStartWorld)
		gpCv.gpEmitStatus()
		return
	gpCv.gpSheet.gpSetFrameMargins(_gpStartMargins)
	if _gpPan:
		_gpLiveMargins = GPFrameGeometry.gpPanMargins(gpCv.gpSheet, gpWorld - _gpStartWorld)
	else:
		# A side follows the CURSOR's coordinate on its own axis, so the line lands exactly where the
		# user points — the natural feel for a resize, and why no start margins are needed here.
		# 边跟随**光标**在其自身轴上的坐标，故线恰好落在用户所指之处 —— 这就是改尺寸的自然手感，
		# 也是此处不需要起始边距的原因。
		var gpAxis: float = gpWorld.y if _gpIsVerticalSide(_gpSide) else gpWorld.x
		_gpLiveMargins = GPFrameGeometry.gpDragSideMargins(gpCv.gpSheet, _gpSide, gpAxis)
	gpCv.gpSheet.gpSetFrameMargins(_gpLiveMargins)
	gpCv.gpRefreshSheetFrame()
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()


# Commit the drag: rewind to the captured margins, then let the command re-apply the same value — one
# undo step, never applied twice (mirrors GPLabelGripOps.gpEndGripDrag and the node-move pattern).
# 提交拖拽：先回退到捕获的边距，再由命令重新应用同一个值 —— 一个撤销步，且绝不会叠加两次
# （与 GPLabelGripOps.gpEndGripDrag 及节点移动同一手法）。
func gpEndGripDrag() -> void:
	if not _gpActive or not gpCanGrab():
		_gpClearDrag()
		return
	if _gpMoveSheet:
		_gpEndSheetMove()
		return
	var gpNew: Array = _gpLiveMargins.duplicate()
	var gpStart: Array = _gpStartMargins.duplicate()
	_gpClearDrag()
	gpCv.gpSheet.gpSetFrameMargins(gpStart)
	if GPFrameGeometry.gpSameMargins(gpCv.gpSheet.gpFrameMargins, gpNew):
		# Nothing moved: no command, no undo step — but the frame must still repaint, because the
		# preview may have written and rewound a value with a different floating representation.
		# 没有移动：不发命令、不产生撤销步 —— 但图框仍须重绘，因为预览可能写过又回退了一个浮点表示
		# 不同的值。
		gpCv.gpRefreshSheetFrame()
		gpCv.queue_redraw()
		return
	gpCv.gpRequestSetFrameMargins(gpNew)
	gpCv.gpRefreshSheetFrame()
	gpCv.queue_redraw()


# Abandon the drag without committing (ESC path). / 放弃拖拽，不提交（ESC 路径）。
func gpCancelDrag() -> void:
	if not _gpActive:
		return
	var gpStart: Array = _gpStartMargins.duplicate()
	var gpWasSheetMove: bool = _gpMoveSheet
	var gpStartOrigin: Vector2 = _gpStartOrigin
	var gpSnap: Dictionary = _gpSnap
	_gpClearDrag()
	if not gpCanGrab():
		return
	if gpWasSheetMove:
		# Put BOTH halves back where they were. Restoring only the paper would leave the content
		# translated by the abandoned drag — the failure mode that looks like "ESC moved my drawing".
		# 两半都要放回去。只还原纸面会让内容被这次被放弃的拖拽平移掉 —— 那种失效看起来就像「ESC 把我的图挪了」。
		gpCv.gpSheet.gpSetPaperOrigin(gpStartOrigin)
		if gpCv.gpGraph != null:
			gpCv.gpGraph.gpRestoreGeometry(gpSnap)
		gpCv.gpRefreshSheetFrame()
		gpCv.gpRefreshSymbolViews()
		gpCv.gpRefreshEdges()
		gpCv.queue_redraw()
		return
	gpCv.gpSheet.gpSetFrameMargins(gpStart)
	gpCv.gpRefreshSheetFrame()
	gpCv.queue_redraw()


# ---------------------------------------------------------------- hover + overlay

# Hover feedback: mark the side under the pointer and show the matching cursor. Returns true when the
# caller should consume the motion event.
# 悬停反馈：标记指针下的那条边并显示相应光标。返回 true 表示调用方应消费该移动事件。
#
# The cursor carries the SEMANTICS, not just "something is here": a handle reads as a resize
# (HSIZE / VSIZE) and the plain band reads as a move — and since stage 0d that move carries the WHOLE
# SHEET, not just the frame, which is precisely what the user asked for (「纸的边界跟着图框一起移动」).
# A single MOVE cursor for both would leave two very different gestures looking identical.
# 光标承载**语义**而非仅「这里有东西」：手柄读作改尺寸（HSIZE / VSIZE），纯抓取带读作移动 —— 而自阶段 0d
# 起，那个「移动」带走的是**整张图纸**、不只是图框，这正是用户所要（「纸的边界跟着图框一起移动」）。
# 两者共用一个 MOVE 光标会让两种截然不同的手势看起来一模一样。
func gpUpdateHoverCursor(gpWorld: Vector2) -> bool:
	# ⚠️ REPAINT ON THE STATE EDGE, NOT ON EVERY MOTION (flicker fix, mirrors the title block):
	# the side handles / side highlight are drawn by the canvas overlay, so a hover toggle needs
	# exactly ONE queue_redraw — including the LEAVE edge, which is what removes the stale
	# highlight. Per-motion repaints made the whole canvas redraw on every mouse-move.
	# ⚠️ 在**状态沿**重绘，而不是每次移动都重绘（闪烁修复，与图签同构）：侧手柄 / 边高亮由画布
	# 覆盖层绘制，故 hover 翻转只需要**一次** queue_redraw —— 包括**离开沿**，正是它消掉残留高亮。
	# 每次移动都重绘曾使整张画布随鼠标逐格重绘。
	#
	# ⚠️ CURSOR: CLAIM WHILE HOVERED, HAND BACK ONCE ON THE LEAVE EDGE / ⚠️ 光标：悬停期间认领，
	# 离开沿恰好一次归还：the setter pushes to the OS immediately on every value change and this
	# handler runs AFTER the tag-grip handlers; while on the band the repeated write early-returns
	# (value unchanged, no OS call), and the leave edge is the single moment this handler writes
	# ARROW — so no writer ever re-asserts per motion, which is what killed the cursor flicker
	# reported over the title block (same mechanism, same fix).
	# 该 setter 在每次值变化时立即下发 OS，而本处理器**后于**各标签抓取点运行；在带上时重复写入
	# 会在 setter 处早退（值未变，无 OS 调用），离开沿才是本处理器写 ARROW 的唯一时机 —— 由此任何
	# 写入者都不再逐移动重新声明，图签上报告的光标抖动（同一机制）即因此消亡（同一修法）。
	var gpWasSide: int = _gpHoverSide
	var gpWasHandle: bool = _gpHoverHandle
	if not gpCanGrab() or _gpActive:
		_gpHoverSide = GPFrameGeometry.GP_SIDE_NONE
		_gpHoverHandle = false
	else:
		var gpHandle: int = gpHitHandle(gpWorld)
		_gpHoverHandle = gpHandle != GPFrameGeometry.GP_SIDE_NONE
		_gpHoverSide = gpHandle if _gpHoverHandle else gpHitBand(gpWorld)
		if _gpHoverSide != GPFrameGeometry.GP_SIDE_NONE:
			if _gpHoverHandle:
				gpCv.mouse_default_cursor_shape = (Control.CURSOR_VSIZE if _gpIsVerticalSide(_gpHoverSide)
					else Control.CURSOR_HSIZE)
			else:
				gpCv.mouse_default_cursor_shape = Control.CURSOR_MOVE
	if _gpHoverSide != gpWasSide or _gpHoverHandle != gpWasHandle:
		# Any hover change (enter, leave, or sliding between sides) is exactly one repaint.
		# 任何 hover 变化（进入、离开、或滑到另一条边）恰好重绘一次。
		gpCv.queue_redraw()
		# And on the LEAVE edge, exactly one cursor hand-back to the arrow.
		# 且在**离开沿**，恰好一次把光标交还箭头。
		if _gpHoverSide == GPFrameGeometry.GP_SIDE_NONE:
			gpCv.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return _gpHoverSide != GPFrameGeometry.GP_SIDE_NONE


# Draw the side handles (and highlight the side being grabbed) in SCREEN space.
# 在**屏幕空间**绘制侧手柄（并高亮正被抓住的那条边）。
#
# ⚠️ SHOWN WHILE HOVERED OR DRAGGING, NOT ALWAYS — a deliberate departure from "handles are always
# visible". The four side midpoints are exactly where Rev.3 stage 0b draws the ISO 5457 CENTRING MARKS
# (对中符号); parking four permanent squares on them would cover a symbol that carries meaning in its
# own right, and the sheet is supposed to read as a 1:1 reproduction of the reference drawing. The
# affordance is not hidden, only deferred: the cursor already changes over the band, and the handles
# appear the moment the pointer arrives.
# ⚠️ **仅在悬停或拖拽时显示**，这是对「手柄常显」的刻意偏离。四条边的中点正是 Rev.3 阶段 0b 绘制
# ISO 5457 **对中符号**之处；常驻四个方块会盖住一个本身就有含义的符号，而图纸应当读作参照图的 1:1 复刻。
# 该可及性并未被隐藏，只是推迟：光标在抓取带上方本就会变化，而手柄在指针到达的瞬间即出现。
func gpDrawGrips(gpItem: CanvasItem) -> void:
	if gpItem == null or not gpCanGrab():
		return
	var gpSide: int = _gpHoverSide
	if _gpActive:
		gpSide = _gpHoverSide if _gpPan else _gpSide
	if gpSide == GPFrameGeometry.GP_SIDE_NONE:
		return
	# Highlight the grabbable side along its full length, so "which line will move" is unambiguous.
	# 沿整条边高亮可抓的那条线，使「哪条线会动」不再有歧义。
	_gpDrawSideHighlight(gpItem, gpSide)
	var gpG: float = GP_GRIP_SIZE
	for gpMid in GPFrameGeometry.gpSideMidpoints(gpCv.gpSheet):
		var gpP: Vector2 = gpCv.gpScreenFromWorld(gpMid as Vector2)
		var gpRect: Rect2 = Rect2(gpP - Vector2(gpG, gpG) * 0.5, Vector2(gpG, gpG))
		gpItem.draw_rect(gpRect, Color(1.0, 1.0, 1.0), true)
		gpItem.draw_rect(gpRect, GP_COL, false, 1.5)


# ============================ private ============================

# The whole-sheet preview: paper origin + every absolute coordinate, from the snapshot, at the TOTAL
# delta. Nothing here reads the previous frame's state, so the preview cannot drift.
# 整图预览：纸面原点 + 每个绝对坐标，皆由快照按**总**位移算出。此处不读上一帧的任何状态，故预览不会漂移。
#
# ⚠️ NO REWIND LINE, UNLIKE THE MARGIN PATH / ⚠️ 与边距路径不同，此处**没有**回退那一行：
# the margin preview must rewind because it writes an ACCUMULATED value (a margin the previous motion
# computed); this path writes an ABSOLUTE value derived from an immutable snapshot, so the write is
# already idempotent — replaying it 1,000 times lands on the same bits. Adding a rewind would mean
# writing the whole model twice per mouse move.
# 边距预览必须回退，因为它写的是**累积**值（上一次移动算出的边距）；本路径写的是由不可变快照推导的**绝对**
# 值，故这次写入本就幂等 —— 重放一千次仍落在同样的位上。加一行回退只会让模型每次鼠标移动被写两遍。
#
# ⚠️ WHY ALL FOUR REFRESHES / 为何四次刷新：the four coordinate holders are owned by four different
# views, and none of them cascades to the others (the trap already documented on GPCanvas2D.gpOnCameraChanged
# — a parent's queue_redraw never reaches a child CanvasItem).
#   * gpRefreshSheetFrame -> frame + zone ruler + title block, and (stage 0d) the tracing underlay;
#   * gpRefreshSymbolViews -> every symbol view, whose transform is re-derived inside _draw();
#   * gpRefreshEdges -> every edge view;
#   * queue_redraw -> the canvas overlay: annotations, marquee, grips.
# ⚠️ **为何要四次刷新**：四个坐标持有者分属四个不同视图，且互不级联（该陷阱已记载于
# GPCanvas2D.gpOnCameraChanged —— 父节点的 queue_redraw 永远到不了子 CanvasItem）。
#   * gpRefreshSheetFrame -> 图框 + 坐标带 + 图签，以及（阶段 0d）追踪底图；
#   * gpRefreshSymbolViews -> 每个图元视图，其 transform 在 _draw() 内重新推导；
#   * gpRefreshEdges -> 每条边视图；
#   * queue_redraw -> 画布覆盖层：注释图形、框选、抓取点。
func _gpPreviewSheetMove(gpDelta: Vector2) -> void:
	gpCv.gpSheet.gpSetPaperOrigin(_gpStartOrigin + gpDelta)
	if gpCv.gpGraph != null:
		gpCv.gpGraph.gpRestoreGeometry(_gpSnap, gpDelta)
	gpCv.gpRefreshSheetFrame()
	gpCv.gpRefreshSymbolViews()
	gpCv.gpRefreshEdges()
	gpCv.queue_redraw()


# Finish a whole-sheet drag: rewind both halves to the snapshot, then hand the NET delta to the command
# so the gesture becomes ONE undo step (the same three beats as the margin path, and as
# GPSelectTool's group drag: rewind -> one command -> one step).
# 结束整图拖拽：把两半都回退到快照，再把**净**位移交给命令，使这次手势成为**一个**撤销步（与边距路径、
# 以及 GPSelectTool 的整组拖拽同一三拍：回退 → 一条命令 → 一个撤销步）。
#
# The net delta is read back off the MODEL rather than remembered from the last gpOnGripMove: the model is
# what the preview actually wrote, so a lost or coalesced motion event can never make the committed move
# disagree with the pixels the user saw. It is also why a press-with-no-movement is detected for free —
# a zero delta means the preview was never asked to move anything.
# 净位移从**模型**读回，而不是记住上一次 gpOnGripMove：模型正是预览真正写过的东西，故丢失或合并的移动事件
# 绝不会让提交的位移与用户看到的画面不一致。这也正是「按下而没动」能被免费判出的原因 —— 位移为零即表示预览
# 从未被要求移动任何东西。
func _gpEndSheetMove() -> void:
	var gpNet: Vector2 = gpCv.gpSheet.gpPaperOrigin - _gpStartOrigin
	var gpStartOrigin: Vector2 = _gpStartOrigin
	var gpSnap: Dictionary = _gpSnap
	_gpClearDrag()
	gpCv.gpSheet.gpSetPaperOrigin(gpStartOrigin)
	if gpCv.gpGraph != null:
		gpCv.gpGraph.gpRestoreGeometry(gpSnap)
	if gpNet == Vector2.ZERO:
		# A plain click on the frame line: no command, no undo step — but still repaint, because the
		# preview may have written and rewound a value with a different floating representation.
		# 在图框线上单纯点一下：不发命令、不产生撤销步 —— 但仍须重绘，因为预览可能写过又回退了一个
		# 浮点表示不同的值。
		gpCv.gpRefreshSheetFrame()
		gpCv.queue_redraw()
		return
	gpCv.gpRequestTranslateSheet(gpNet)
	gpCv.gpRefreshSheetFrame()
	gpCv.gpRefreshSymbolViews()
	gpCv.gpRefreshEdges()
	gpCv.queue_redraw()


# True for the two sides whose outward direction is vertical, i.e. the top and bottom lines.
# 对两条「向外方向为竖直」的边（即上下两条线）返回真。
func _gpIsVerticalSide(gpSide: int) -> bool:
	return gpSide == GPSheet.GP_MARGIN_TOP or gpSide == GPSheet.GP_MARGIN_BOTTOM


# Reset every drag field. One function so a new field cannot be forgotten by one of the two exit paths
# (commit and cancel) and leave the tool stuck in a half-armed state.
# 复位全部拖拽字段。收口为一个函数，使新增字段不会被两条退出路径（提交与取消）中的一条漏掉，
# 从而把工具卡在半个上膛状态。
func _gpClearDrag() -> void:
	_gpActive = false
	_gpPan = false
	_gpMoveSheet = false
	_gpSide = GPFrameGeometry.GP_SIDE_NONE
	_gpStartOrigin = Vector2.ZERO
	_gpSnap = {}
	_gpStartMargins = []
	_gpLiveMargins = []


# Stroke one frame line in the grip colour, in screen space.
# 以抓取点配色在屏幕空间描出一条图框线。
func _gpDrawSideHighlight(gpItem: CanvasItem, gpSide: int) -> void:
	var gpF: Rect2 = GPFrameGeometry.gpFrameRect(gpCv.gpSheet)
	if gpF.size.x <= 0.0 or gpF.size.y <= 0.0:
		return
	var gpA: Vector2 = gpF.position
	var gpB: Vector2 = gpF.end
	match gpSide:
		GPSheet.GP_MARGIN_LEFT:
			gpB = Vector2(gpF.position.x, gpF.end.y)
		GPSheet.GP_MARGIN_TOP:
			gpB = Vector2(gpF.end.x, gpF.position.y)
		GPSheet.GP_MARGIN_RIGHT:
			gpA = Vector2(gpF.end.x, gpF.position.y)
		_:
			gpA = Vector2(gpF.position.x, gpF.end.y)
	gpItem.draw_line(gpCv.gpScreenFromWorld(gpA), gpCv.gpScreenFromWorld(gpB), GP_COL, 2.0)
