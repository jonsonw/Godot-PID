class_name GPTitleBlockGripOps
extends RefCounted
# Copyright © 2026 Jonson Wang
# Title-block (图签) whole-block grab / drag / dock — Rev.3 stage 1.
# 图签整块抓取 / 拖拽 / 停靠 —— Rev.3 阶段 1。
#
# WHY THE WHOLE BLOCK IS THE TARGET HERE, UNLIKE THE FRAME'S BAND / 为何此处整块可抓、与图框的抓取带不同：
# the frame is grabbable only along its four LINES because it is the whole sheet minus its margins — an
# area target there would mean "click anywhere and you grab the frame". The title block is a single
# 180x50 mm object with its own extent, so its area IS its outline; there is no ambiguity to remove. The
# price is a small one and Rev.3 §4.1 named it: a press inside the bottom-right corner starts a block drag
# instead of a marquee, so a marquee over that corner has to start from outside it.
# 图框**只沿四条线**可抓，因为它是整张纸减去边距 —— 在那里用面积目标等于「点哪都抓到图框」。而图签是一个
# 有自身范围的 180×50mm 对象，其面积**就是**它的轮廓，没有歧义要消除。代价很小，且 Rev.3 §4.1 已点名：
# 在右下角内按下起的是图签拖拽而非框选，故要在该角范围内框选须从它外面起拖。
#
# ★ SAFETY PROPERTY / 安全性：like the frame, this can only ever change what happens where NOTHING was
# selectable before, because it is tested BELOW node / edge / annotation picking (see GPSelectTool.gpOnPress).
# 与图框一样，它只可能改变「过去什么也选不中」的地方的行为，因为它被放在图元 / 边 / 注释图形拾取**之后**
# （见 GPSelectTool.gpOnPress）。
#
# ⚠️ ORDER AGAINST THE FRAME IS LOAD-BEARING / ⚠️ 与图框的先后顺序是承重的：the two targets OVERLAP —
# the block hugs the frame's bottom-right corner, so part of its outline runs along the frame's own right
# and bottom lines. The block is therefore tested FIRST: a press on the block is a press on the block, and
# a user who wants the frame's corner can move the block and find the line underneath it. Testing the frame
# first would make the block's own edges ungrabbable, i.e. the object would be half-draggable.
# 两个目标**重叠** —— 图签贴住内框右下角，故它的一部分轮廓就沿着图框自身的右边与下边线。故图签**先**测：
# 按在图签上就是按在图签上；想要图框那个角的用户把图签移开便能找到下面的线。若先测图框，图签自身的边将永远
# 抓不到 —— 即「这个对象只有一半能拖」。
#
# THREE BEATS, ONE UNDO STEP / 三拍、一个撤销步：every mouse motion re-derives the docking pair from the
# pointer (no accumulation, so no drift), the release rewinds to the drag-start pair and then lets ONE
# command re-apply the final pair — the same rewind -> one command -> one step shape used by the frame drag
# and by GPSelectTool's group drag. Two fields travelling in one command is what keeps Ctrl+Z from stopping
# at a corner/offset combination the user never saw (see GPMutateSheetCommand.GP_FIELDS).
# 每次鼠标移动都**由指针重新推导**停靠对（不累加，故不漂移）；释放时回退到起始对，再由**一条**命令重新应用
# 最终对 —— 与图框拖拽、GPSelectTool 整组拖拽同一「回退 → 一条命令 → 一个撤销步」的形状。两个字段同乘一条
# 命令，正是 Ctrl+Z 不会停在用户从未见过的「角 + 偏移」组合上的原因（见 GPMutateSheetCommand.GP_FIELDS）。
#
# WHERE THE GEOMETRY LIVES / 几何住在哪：all of it is in GPFrameGeometry (one fact, one home) — this class
# decides WHAT a press means and drives it, and never re-derives a rectangle. Everything down to the
# "drag state" divider is pure; from the "hover + overlay" divider down touches the canvas.
# 全部在 GPFrameGeometry（一个事实一个家）—— 本类只判定一次按下**意味着什么**并驱动它，绝不重算矩形。
# 「拖拽状态」分隔线以上皆纯；自「悬停 + 覆盖层」分隔线起触碰画布。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Colour of the hover / drag outline: the same blue as the frame's side handles and the tag / edge grips,
# so "this thing is draggable" reads the same everywhere in the editor.
# 悬停 / 拖拽外框的配色：与图框侧手柄、位号 / 边抓取点相同的蓝，使「这东西可拖」在编辑器各处读作同一件事。
const GP_COL: Color = Color(0.20, 0.50, 1.0)

# Smallest zoom the snap tolerance is computed against, so a degenerate zoom cannot produce an infinite
# snapping distance that makes the block un-placeable.
# 计算吸附容差时的最小缩放，使退化缩放不会产出一个「哪都吸」的距离、从而让图签无处可放。
const GP_MIN_ZOOM: float = 0.0001

# ---------------------------------------------------------------- drag state

var gpCv: GPCanvas2D = null

# True while a title-block drag is in flight. / 图签拖拽进行中时为真。
var _gpActive: bool = false

# Pointer position relative to the block's top-left corner at the moment of the press. Held CONSTANT for
# the whole gesture, so the block follows the pointer rigidly no matter where inside it the user grabbed —
# and so re-judging the anchor mid-drag cannot make the block jump under the cursor.
# 按下瞬间指针相对图签左上角的位置。整个手势期间**保持常量**，故无论用户抓在图签内部何处，它都刚性地跟随
# 指针 —— 也正因如此，拖拽途中重判锚角不会让图签在光标底下跳。
var _gpGrabDelta: Vector2 = Vector2.ZERO

# The docking pair as it was before the drag, captured so a plain click never perturbs the sheet and a
# release can rewind to a clean baseline before the single undo step is committed.
# 拖拽前的停靠对。捕获它，使单纯的点击不会扰动图纸，且释放时能回退到干净基线再提交**一个**撤销步。
var _gpStartAnchor: int = GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT
var _gpStartOffset: Vector2 = Vector2.ZERO

# The docking pair the preview has written. The release commits THIS, not a value re-derived from the last
# motion event, because this is what the pixels actually show.
# 预览已写入的停靠对。释放时提交的是**它**，而不是由最后一次移动事件重新推导的值 —— 因为它才是画面真正显示的。
var _gpLiveAnchor: int = GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT
var _gpLiveOffset: Vector2 = Vector2.ZERO

# True while the pointer sits on the block (outside any drag), i.e. while the outline is drawn.
# 指针停在图签上（拖拽之外）时为真，即：何时绘制那圈外框。
var _gpHover: bool = false


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# ---------------------------------------------------------------- pure probes

# True when the block may be grabbed at all: a sheet exists and draws its frame. The block is part of the
# frame's furniture, so it shares the frame's gate — with the frame switched off there is no block on
# screen, and an invisible target the user cannot see is worse than none.
# 图签是否可被抓取：图纸存在且绘制图框。图签是图框的一部分陈设，故共用图框的闸门 —— 图框关闭时屏幕上没有
# 图签，而一个用户看不见的隐形目标比没有更糟。
func gpCanGrab() -> bool:
	return gpCv != null and gpCv.gpSheet != null and gpCv.gpSheet.gpFrameOn


# The block's world rectangle, straight from the geometry layer. / 图签的世界矩形，直接取自几何层。
func gpRect() -> Rect2:
	if gpCv == null or gpCv.gpSheet == null:
		return Rect2()
	return GPFrameGeometry.gpTitleBlockRect(gpCv.gpSheet)


# True when a world point falls inside the block. / 世界点落在图签内时为真。
func gpHit(gpWorld: Vector2) -> bool:
	if not gpCanGrab():
		return false
	return gpRect().has_point(gpWorld)


# True while a title-block drag is in flight. / 图签拖拽进行中时为真。
func gpIsDragging() -> bool:
	return _gpActive


# True while the pointer hovers the block. / 指针悬停在图签上时为真。
func gpHover() -> bool:
	return _gpHover


# Snap tolerance in WORLD mm for the current canvas zoom — screen pixels divided by zoom, the convention
# Rev.3 §9-② mandates and GPSnapResolver already uses (GPConstants.GP_SNAP_PX).
# 当前画布缩放下的吸附容差（世界毫米）—— 屏幕像素除以缩放，Rev.3 §9-② 所要求、GPSnapResolver 已在用的
# 口径（GPConstants.GP_SNAP_PX）。
func gpSnapTol() -> float:
	if gpCv == null:
		return GPConstants.GP_SNAP_PX
	return GPConstants.GP_SNAP_PX / maxf(gpCv.gpViewZoom, GP_MIN_ZOOM)


# ---------------------------------------------------------------- drag

# Begin a drag when the press landed on the block. Returns false so the caller can fall through to the
# frame band and then to ordinary selection / marquee when it did not.
# 按下落在图签上时开始拖拽。未命中返回 false，使调用方能继续走图框抓取带、再到普通的选择 / 框选流程。
func gpTryStart(gpWorld: Vector2) -> bool:
	if not gpCanGrab():
		return false
	var gpBlock: Rect2 = gpRect()
	if not gpBlock.has_point(gpWorld):
		return false
	_gpActive = true
	_gpGrabDelta = gpWorld - gpBlock.position
	_gpStartAnchor = gpCv.gpSheet.gpTbAnchor
	_gpStartOffset = gpCv.gpSheet.gpTbOffset
	_gpLiveAnchor = _gpStartAnchor
	_gpLiveOffset = _gpStartOffset
	return true


# Live preview: re-derive the docking pair from the pointer and write it, so the block follows the cursor.
# 实时预览：由指针重新推导停靠对并写入，使图签跟随光标。
#
# ⚠️ THE FOUR STEPS ARE IN THIS ORDER FOR A REASON / ⚠️ 四步的**顺序**有讲究：
#   1. RE-JUDGE the anchor from where the block now is — dragging it past the frame's centre line hands it
#      to the other side, which is how one gesture reaches all four corners;
#   2. INVERT the placement to get the offset that anchor implies;
#   3. SNAP that offset towards the inner edges (the only step that is about feel);
#   4. CLAMP it, last, so the invariant ("the block never leaves the frame it is docked to") holds for
#      whatever the three steps above produced.
# Reversing 3 and 4 would let a clamp land on a nearly-zero offset that should have snapped to zero; and
# clamping before the inversion would be clamping a quantity that has not been computed yet.
#   1. 由图签**当前位置**重判锚角 —— 把它拖过内框中线即交给另一侧，这正是「一次拖拽够到四个角」的方式；
#   2. **反推**该锚角所蕴含的偏移；
#   3. 把该偏移**吸附**向内边（唯一关乎手感的一步）；
#   4. **钳制**，放最后，使不变量（「图签绝不离开它所停靠的图框」）对上三步产出的任何值都成立。
# 把 3 与 4 对调，会让一次钳制落在一个本该吸附到零的近似零值上；而在反推之前钳制，则是在钳一个尚未算出的量。
#
# ⚠️ NO REWIND LINE, UNLIKE THE FRAME'S MARGIN PATH / ⚠️ 与图框的边距路径不同，此处**没有**回退那一行：
# the margins path must rewind because it writes an ACCUMULATED value; this path writes a value derived
# from the pointer and an immutable grab delta, so the write is already idempotent.
# 边距路径必须回退，因为它写的是**累积**值；本路径写的是由指针与不可变抓取位移推导出的值，故写入本就幂等。
func gpOnGripMove(gpWorld: Vector2) -> void:
	if not _gpActive or not gpCanGrab():
		return
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(gpCv.gpSheet)
	# Sheet-aware block size (A1 rebase): the drag must reason about the block at the size it is
	# drawn at, and the clamp below must use the SAME size — one fact, passed once.
	# 随图纸的图签尺寸（A1 重定基）：拖拽按图签**绘制时**的尺寸推理，下方钳制也用**同一个**尺寸
	# —— 一个事实、只传一次。
	var gpSize: Vector2 = gpCv.gpSheet.gpTbBlockSize()
	var gpBlock: Rect2 = Rect2(gpWorld - _gpGrabDelta, gpSize)
	var gpAnchor: int = GPFrameGeometry.gpReanchor(gpFrame, gpBlock)
	var gpOffset: Vector2 = GPFrameGeometry.gpTitleBlockOffset(gpFrame, gpAnchor, gpBlock)
	gpOffset = GPFrameGeometry.gpSnapTitleBlock(gpOffset, gpSnapTol())
	gpOffset = GPFrameGeometry.gpClampTitleBlock(gpFrame, gpAnchor, gpOffset, gpSize)
	_gpLiveAnchor = gpAnchor
	_gpLiveOffset = gpOffset
	gpCv.gpSheet.gpSetTbPlacement(gpAnchor, gpOffset)
	# ONE refresh is enough here, unlike the whole-sheet move: the block is drawn by the frame view and
	# nothing else on the sheet depends on where it sits.
	# 此处一次刷新就够，与整图平移不同：图签由图框视图绘制，纸上其它任何东西都不依赖它所在的位置。
	gpCv.gpRefreshSheetFrame()
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()


# Commit the drag: rewind to the captured pair, then let the command write the final one — one undo step,
# never applied twice. A press that moved nothing records nothing.
# 提交拖拽：回退到捕获的对，再由命令写入最终对 —— 一个撤销步，且绝不叠加两次。没有移动的按下不产生任何记录。
func gpEndGripDrag() -> void:
	if not _gpActive or not gpCanGrab():
		_gpClearDrag()
		return
	var gpNewAnchor: int = _gpLiveAnchor
	var gpNewOffset: Vector2 = _gpLiveOffset
	var gpStartAnchor: int = _gpStartAnchor
	var gpStartOffset: Vector2 = _gpStartOffset
	_gpClearDrag()
	gpCv.gpSheet.gpSetTbPlacement(gpStartAnchor, gpStartOffset)
	if gpNewAnchor == gpStartAnchor and gpNewOffset == gpStartOffset:
		# Nothing moved: no command, no undo step — but the block must still repaint, because the preview
		# may have written and rewound a value with a different floating representation.
		# 没有移动：不发命令、不产生撤销步 —— 但图签仍须重绘，因为预览可能写过又回退了一个浮点表示不同的值。
		gpCv.gpRefreshSheetFrame()
		gpCv.queue_redraw()
		return
	gpCv.gpRequestSetTitleBlockPlacement(gpNewAnchor, gpNewOffset)
	gpCv.gpRefreshSheetFrame()
	gpCv.queue_redraw()


# Abandon the drag without committing (ESC path). / 放弃拖拽，不提交（ESC 路径）。
func gpCancelDrag() -> void:
	if not _gpActive:
		return
	var gpStartAnchor: int = _gpStartAnchor
	var gpStartOffset: Vector2 = _gpStartOffset
	_gpClearDrag()
	if not gpCanGrab():
		return
	gpCv.gpSheet.gpSetTbPlacement(gpStartAnchor, gpStartOffset)
	gpCv.gpRefreshSheetFrame()
	gpCv.queue_redraw()


# ---------------------------------------------------------------- hover + overlay

# Hover feedback: show the move cursor over the block. Returns true when the caller should consume the
# motion event.
# 悬停反馈：图签上方显示移动光标。返回 true 表示调用方应消费该移动事件。
#
# ⚠️ REPAINT ON THE STATE EDGE, NOT ON EVERY MOTION / ⚠️ 在**状态沿**重绘，而不是每次移动都重绘：
# the hover outline is drawn by the canvas overlay, so showing or hiding it needs exactly ONE
# queue_redraw when hover toggles. Repainting on every motion made the whole canvas (and via the
# sync, every symbol view) redraw per mouse-move — the reported "the block keeps flickering". The
# LEAVE edge also repaints, which is what kills the stale outline that used to stay behind.
# 悬停外框由画布覆盖层绘制，故显示或隐藏它只需要 hover 翻转时的**一次** queue_redraw。每次移动
# 都重绘曾使整张画布（连同 sync 里的每个图元视图）随鼠标逐格重绘 —— 即用户报告的「图签不断闪动」。
# **离开沿**同样重绘一次，这正是消掉「外框残留在屏上」的关键。
#
# ⚠️ NO MODIFIER CHANGES THIS GESTURE / ⚠️ 没有修饰键会改变这个手势：unlike the frame's band (which shares
# its line with the ⌥Alt margin trade), the block has exactly one meaning, so it takes the plain MOVE cursor
# and no key. Adding a second meaning later would need a second cursor, not a second key.
# 与图框抓取带（其线还与 ⌥Alt 边距对冲共享）不同，图签只有一种含义，故用朴素的 MOVE 光标、不挂任何键。
# 将来若要加第二种含义，需要的是第二个光标、不是一个新键。
#
# ⚠️ THE CURSOR IS CLAIMED PER MOTION BUT THE SETTER IS IDEMPOTENT; THE HAND-BACK IS EDGE-ONLY /
# ⚠️ 光标逐移动「认领」，但 setter 幂等；「归还」只在状态沿：the property setter pushes to the OS
# immediately on every VALUE CHANGE, and this handler runs AFTER the tag-grip handlers on every
# motion event. While hovered, the repeated MOVE write early-returns in the setter (value unchanged,
# no OS call); on the LEAVE edge we hand the cursor back to ARROW exactly once — that restore is what
# lets the tag-grip handlers stay claim/release without anyone re-asserting per motion.
# 该属性 setter 在每次**值变化**时立即下发 OS，而本处理器在每个移动事件里都**后于**标签抓取点运行。
# 悬停期间重复写 MOVE 会在 setter 处早退（值未变，无 OS 调用）；在**离开沿**把光标恰好一次交还
# ARROW —— 有了这次归还，各抓取点处理器才能安心「认领 / 归还」，无需任何人逐移动重新声明。
func gpUpdateHoverCursor(gpWorld: Vector2) -> bool:
	var gpWas: bool = _gpHover
	if not gpCanGrab() or _gpActive:
		_gpHover = false
		if gpWas:
			# Left the block (or a drag took over): one repaint so the outline does not stay behind,
			# and the cursor goes back to the arrow exactly once.
			# 离开了图签（或拖拽接管）：重绘一次使外框不残留，光标也恰好一次交还箭头。
			gpCv.queue_redraw()
			gpCv.mouse_default_cursor_shape = Control.CURSOR_ARROW
		return false
	_gpHover = gpHit(gpWorld)
	if _gpHover:
		# Idempotent claim: while staying hovered the setter early-returns (no OS call).
		# 幂等认领：持续悬停时 setter 早退（无 OS 调用）。
		gpCv.mouse_default_cursor_shape = Control.CURSOR_MOVE
	if _gpHover != gpWas:
		# ENTER or LEAVE: exactly one repaint on the state edge; on LEAVE also one cursor hand-back.
		# 进入或离开：状态沿上恰好重绘一次；离开沿另有一次光标归还。
		gpCv.queue_redraw()
		if not _gpHover:
			gpCv.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return _gpHover


# Outline the block while it is hovered or dragged, in SCREEN space.
# 在悬停或拖拽期间于**屏幕空间**描出图签外框。
#
# ⚠️ IT DOES NOT REPLACE THE BLOCK'S OWN OUTLINE — IT SITS EXACTLY ON TOP OF IT. The block already draws a
# frame-coloured border (the drawing's ink); this is an affordance layer the same weight as the frame's
# side handles, and it disappears the moment the pointer leaves. Highlighting the interior instead would
# fight the 13 cells of text the block exists to carry.
# ⚠️ 它**不**取代图签自身的轮廓 —— 它恰好压在其上。图签本就画了一圈图框色边框（图纸的墨色）；这一层是与图框
# 侧手柄同权重的可及性提示，指针一离开即消失。若改为高亮内部，就会与图签存在的意义 —— 那 13 格文字 —— 打架。
func gpDrawGrips(gpItem: CanvasItem) -> void:
	if gpItem == null or not gpCanGrab():
		return
	if not _gpHover and not _gpActive:
		return
	var gpBlock: Rect2 = gpRect()
	var gpA: Vector2 = gpCv.gpScreenFromWorld(gpBlock.position)
	var gpB: Vector2 = gpCv.gpScreenFromWorld(gpBlock.end)
	gpItem.draw_rect(Rect2(gpA, gpB - gpA), GP_COL, false, 1.5)


# ============================ private ============================

# Reset every drag field. One function so a new field cannot be forgotten by one of the two exit paths
# (commit and cancel) and leave the tool stuck in a half-armed state.
# 复位全部拖拽字段。收口为一个函数，使新增字段不会被两条退出路径（提交与取消）中的一条漏掉，
# 从而把工具卡在半个上膛状态。
func _gpClearDrag() -> void:
	_gpActive = false
	_gpGrabDelta = Vector2.ZERO
	_gpStartAnchor = GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT
	_gpStartOffset = Vector2.ZERO
	_gpLiveAnchor = GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT
	_gpLiveOffset = Vector2.ZERO
