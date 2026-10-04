# ============================================================================
# GPPlaceAttachTool — 次级图元（附件）的两种添加交互
# Attach interaction for secondary symbols (parts) — both modes of 规划 §15.
#
# 模式一（库内拖放）：左栏拖出一个部件 → 幽灵跟随光标、实时吸附最近的**兼容空闲锚点**并按锚点
# 朝向自适应；释放落在锚点上即建节点，未命中则**拒绝放置**（禁止光标 + 状态栏说明）。
# 模式二（右键添加 + 拖动定位）：右键宿主 →「添加附件」→ 立即落在第一个空闲兼容锚点，
# 随后进入**拖动定位**（同一个挂载拖动内核），`Esc` 撤销这次添加，点击 / 回车落位。
#
# Mode 1 (library drag): a ghost follows the cursor, live-snaps to the nearest FREE COMPATIBLE
# anchor and re-orients from the anchor's normal; releasing on one creates the node, and releasing
# on nothing REFUSES to place (forbidden cursor + a status-bar reason).
# Mode 2 (right-click, then position): the part lands on the first free compatible anchor and then
# enters the SAME mount-drag kernel; Esc undoes the whole addition, click / Enter drops it.
#
# 共同铁律（规划 §15.1）：次级图元**永远挂载、不落顶层**。找不到兼容锚点 = **不放置**，
# 而不是「自由摆放」—— 因为「附件脱离宿主」正是本次要消灭的缺陷。
# Shared iron rule (§15.1): a part is ALWAYS mounted, never top-level. No compatible anchor means
# NO placement, rather than "put it somewhere" — an orphaned part is the very defect being removed.
#
# 光标与预览走 tool 自己的 gpOnMove / gpDrawOverlay（与 GPPlaceTool 相同的方式），因为本工具在
# gpPendingAttach 非空时才会被 gpActiveTool() 选中。
# Cursor and preview ride the tool's own gpOnMove / gpDrawOverlay (exactly as GPPlaceTool does),
# because the tool is only reached while gpPendingAttach is non-empty.
# ============================================================================

class_name GPPlaceAttachTool
extends GPCanvasTool

# 幽灵填充 / 描边透明度（与 GPPlaceTool 的放置虚影保持一致，使两种「放置」看起来是同一种手势）。
# Ghost fill / stroke opacity — kept identical to GPPlaceTool's placement ghost, so the two
# "put a symbol here" gestures read as the same gesture.
const GP_GHOST_FILL_ALPHA: float = 0.20
const GP_GHOST_STROKE_ALPHA: float = 0.80

# 锚点高亮环半径（世界单位）与线宽（世界单位）。
# Anchor highlight ring radius / width, in world units.
const GP_ANCHOR_RING: float = 10.0
const GP_ANCHOR_RING_WIDTH: float = 2.0

# 挂载拖动内核（模式二与「拖动已挂载部件」共用）。
# The mount-drag kernel shared by mode 2 and by dragging an already-mounted part.
var _gpDrag: GPMountDragOps = GPMountDragOps.new()

# 最近一次算出的候选锚点（模式一的预览用）。空字典 = 未命中。
# The most recent candidate anchor (mode 1 preview). Empty dictionary = no hit.
var _gpCand: Dictionary = {}

# 最近一次移动事件的世界坐标。持有它是为了在不命中锚点时仍能把幽灵画在光标处 ——
# 画布上的 `_gpLastMouseWorld` 是私有字段，跨对象读取会违反「零私有调用」硬约束。
# World position of the most recent motion event. Kept so the ghost can still be drawn at the
# cursor when no anchor is in range — the canvas's `_gpLastMouseWorld` is private, and reading it
# across objects would break the "no cross-object private access" hard rule.
var _gpGhostWorld: Vector2 = Vector2.ZERO

# 最近一次算出的**落位元组**（模式一预览与落位共用 GPMountResolver.gpPlacementTuple 这一条
# 规则）。空字典 = 释放点在空白处。
# The most recent PLACEMENT tuple (mode 1). Preview and drop share the ONE rule
# GPMountResolver.gpPlacementTuple embodies. Empty dictionary = the drop is on empty space.
var _gpPlace: Dictionary = {}


# 是否有半个交互在进行（供释放分派与 ESC 链判断）。
# Whether a half-finished interaction is in flight (for release dispatch and the ESC chain).
func gpIsDragging() -> bool:
	return _gpDrag.gpIsDragging()


# 进入「拖动定位」态（规划 §15.3 第 4 步）。由右键添加路径在节点建好后调用。
# Enter the "position it" phase (§15.3 step 4). Called by the right-click path once the node exists.
func gpBeginPositioning(gpNodeId: String) -> bool:
	var gpCv: GPCanvas2D = gpCtx.gpCv
	if gpCv.gpGraph == null:
		return false
	if not _gpDrag.gpBegin(gpCv.gpGraph, gpCv.gpDefLookupCallable(), gpNodeId):
		return false
	_gpCand = {}
	_gpPlace = {}
	return true


# 模式一：有待挂载定义时，移动只是刷新手型光标与候选。
# Mode 1: with a definition armed, a move only refreshes the hand cursor and the candidate.
func gpOnMove(gpWorld: Vector2) -> bool:
	var gpCv: GPCanvas2D = gpCtx.gpCv
	if gpCv.gpPendingAttach.is_empty():
		return false
	_gpGhostWorld = gpWorld
	# 拖动定位态：把算出的挂载元组**实时写入**，使部件跟随光标（提交在释放时一次完成）。
	# Positioning: write the computed mount tuple LIVE so the part follows the cursor; the commit
	# happens once, on release.
	if _gpDrag.gpIsDragging():
		var gpTarget: Dictionary = _gpDrag.gpTargetFor(gpWorld, gpCv.gpViewZoom)
		if not gpTarget.is_empty():
			_gpDrag.gpApply(gpTarget)
		_gpCand = _gpCandidateAt(gpWorld)
		gpCv.mouse_default_cursor_shape = Control.CURSOR_DRAG if not _gpCand.is_empty() \
			else Control.CURSOR_FORBIDDEN
		gpCv.queue_redraw()
		return true
	# 模式一：幽灵跟随光标，实时求落位元组 —— 与释放共用同一条规则，拖动时看到的就是松手后
	# 得到的。
	# Mode 1: the ghost follows the cursor and the placement tuple is resolved live — the same rule
	# the release uses, so what you see while dragging is what you get when you let go.
	_gpCand = _gpCandidateAt(gpWorld)
	_gpPlace = GPMountResolver.gpPlacementTuple(gpCv.gpGraph, gpCv.gpDefLookupCallable(),
		gpWorld, gpCv.gpViewZoom, _gpArmedDef(gpCv))
	gpCv.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not _gpPlace.is_empty() \
		else Control.CURSOR_FORBIDDEN
	gpCv.queue_redraw()
	return true


# 左键：模式二 = 落位提交；模式一 = 点击落位（与拖出释放共用同一条规则）。
# Left press: mode 2 commits the drop; mode 1 lands the part (one shared rule with the release).
func gpOnPress(gpWorld: Vector2, _gpShift: bool, _gpDouble: bool) -> bool:
	var gpCv: GPCanvas2D = gpCtx.gpCv
	if gpCv.gpPendingAttach.is_empty():
		return false
	if _gpDrag.gpIsDragging():
		_gpCommitPositioning()
		return true
	_gpDropMode1(gpWorld)
	return true


# 回车 = 落位（与点击等价的键盘确认）。Esc 由 gpCancel() 处理。
# Enter drops the part (keyboard equivalent of the click). Esc is handled by gpCancel().
func gpOnKey(gpKey: InputEventKey) -> bool:
	if gpKey.keycode != KEY_ENTER and gpKey.keycode != KEY_KP_ENTER:
		return false
	if not _gpDrag.gpIsDragging():
		return false
	_gpCommitPositioning()
	return true


# 释放：拖动定位态下同样落位。模式一的**拖出手势也在释放时完成** —— 松开即按预览所见落位，
# 而不是把部件悬在半空再要求用户点第二次。
# Release: the positioning phase drops here too, AND the mode-1 palette drag completes HERE —
# letting go lands the part exactly as previewed, instead of leaving it hovering until a second
# click.
func gpOnRelease(_gpWorld: Vector2) -> bool:
	if _gpDrag.gpIsDragging():
		_gpCommitPositioning()
		return true
	var gpCv: GPCanvas2D = gpCtx.gpCv
	if gpCv.gpPendingAttach.is_empty():
		return false
	_gpDropMode1(_gpWorld)
	return true


# 模式一落位（点击与拖出释放共用）：吸附在锚点上，或落在光标处。空白处释放保留待命手势，
# 让用户仍可把部件带到别处。
# Mode-1 landing (shared by the press and the drag release): seats on an anchor or lands at the
# cursor. A release on empty space KEEPS the pending gesture, so the part can still be carried
# elsewhere.
func _gpDropMode1(gpWorld: Vector2) -> void:
	var gpCv: GPCanvas2D = gpCtx.gpCv
	var gpPend: Dictionary = gpCv.gpPendingAttach
	# 与幽灵预览**同一个**函数：所见即所得。
	# The VERY SAME function the ghost preview uses: what you see is what you get.
	var gpPlace: Dictionary = GPMountResolver.gpPlacementTuple(gpCv.gpGraph,
		gpCv.gpDefLookupCallable(), gpWorld, gpCv.gpViewZoom, _gpArmedDef(gpCv))
	if not bool(gpPlace.get("hit", false)):
		# 空白处：不放置并说明原因（规划 §15.2 第 4 步）。PREFIX-FREE 记号，"attach." 命名空间
		# 由 gpReportAttachRefusal() 自加。
		# Empty space: no placement, with a reason (§15.2 step 4). PREFIX-FREE token; the "attach."
		# namespace is added by gpReportAttachRefusal() itself.
		gpCv.gpReportAttachRefusal("no_anchor")
		return
	var gpNid: String = gpCv.gpRequestAttachNode(str(gpPend.get("symbol_id", "")),
		str(gpPlace["parent_uid"]), str(gpPlace["anchor"]),
		gpPlace["mount_offset"], float(gpPlace["mount_angle_deg"]))
	if gpNid != "":
		# gpClearPendingAttach() also restores the arrow cursor (single owner of that duty).
		# gpClearPendingAttach() 同时负责恢复箭头光标（该职责只有一个归属）。
		gpCv.gpClearPendingAttach()
	gpCv.queue_redraw()


# 当前上膛的定义（模式一）。挂载类型、基础安装角都从**它自己**来。
# The currently armed definition (mode 1). Mount kind and base mount rotation come from IT.
func _gpArmedDef(gpCv: GPCanvas2D) -> GPSymbolDef:
	return gpCv.gpDefFor(str(gpCv.gpPendingAttach.get("symbol_id", "")))


# ESC：放弃整个交互。拖动定位态还要**撤销刚压入的添加步**（规划 §15.3 第 4 步）——
# 否则用户按下 Esc 之后会留下一枚他并不想要的部件。
# ESC: abandon the whole interaction. The positioning phase must ALSO undo the just-pushed attach
# step (§15.3 step 4) — otherwise the user is left with a part they said they did not want.
func gpCancel() -> bool:
	var gpCv: GPCanvas2D = gpCtx.gpCv
	var gpPend: Dictionary = gpCv.gpPendingAttach
	if gpPend.is_empty():
		return false
	var gpUndoable: bool = _gpDrag.gpIsDragging() and bool(gpPend.get("undo_on_cancel", false))
	if _gpDrag.gpIsDragging():
		_gpDrag.gpRestore()
		_gpDrag.gpEnd()
	gpCv.gpClearPendingAttach()
	# 只有「本次添加」才回滚：拖动一个既有部件时 Esc 只放弃位移。
	# Only a freshly added part is rolled back; while re-positioning an existing one, Esc just
	# abandons the nudge.
	if gpUndoable:
		gpCv.gpUndo()
	gpCv.queue_redraw()
	return true


# 覆盖层：画出幽灵部件（命中锚点时吸附并转向）与锚点高亮环。
# Overlay: the ghost part (snapped and turned on a hit) plus the anchor highlight ring.
func gpDrawOverlay(gpItem: CanvasItem) -> void:
	var gpCv: GPCanvas2D = gpCtx.gpCv
	if gpCv.gpPendingAttach.is_empty():
		return
	if not _gpCand.is_empty():
		_gpDrawAnchorRing(gpItem, gpCv)
	if _gpDrag.gpIsDragging():
		# 拖动定位态：真实图元已经跟随光标（视图层），故只画锚点环，不叠幽灵。
		# Positioning: the real view already follows the cursor, so only the ring is drawn.
		return
	var gpDef: GPSymbolDef = gpCv.gpDefFor(str(gpCv.gpPendingAttach.get("symbol_id", "")))
	if gpDef == null:
		return
	_gpDrawGhost(gpItem, gpCv, gpDef)


# 把 (世界点, 缩放, 挂载类型) 交给挂载阶梯。类型按当前态推导：
# 拖动定位态取自**正在拖动节点自身**的定义（其与调用方的入参无关，故不能依赖 state 里的键）；
# 模式一取自待挂载定义。
# Hand (world point, zoom, mount kind) to the mount ladder. The kind is derived from the current
# phase: while positioning it comes from the DRAGGED NODE's own definition (which the caller's
# state keys say nothing about), and in mode 1 from the armed definition.
func _gpCandidateAt(gpWorld: Vector2) -> Dictionary:
	var gpCv: GPCanvas2D = gpCtx.gpCv
	if gpCv.gpGraph == null:
		return {}
	var gpKind: String = ""
	if _gpDrag.gpIsDragging():
		# A part is attached by its OWN kind, never by whatever else happens to be armed.
		# 部件的挂载类型取自它**自己**，绝不取自恰好被上膛的别的东西。
		var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(_gpDrag.gpNodeId())
		var gpDef: GPSymbolDef = null
		if gpN != null:
			gpDef = gpCv.gpDefFor(gpN.gpSymbolId)
		if gpDef != null:
			gpKind = gpDef.gpMountKind
	else:
		gpKind = str(gpCv.gpPendingAttach.get("mount_kind", ""))
	if gpKind == "":
		return {}
	return GPMountResolver.gpMountCandidate(gpCv.gpGraph, gpCv.gpDefLookupCallable(), gpWorld,
		gpCv.gpViewZoom, gpKind)


# 落位：先**恢复**拖拽前元组，再交给命令重新应用 —— 这是命令栈记录撤销步的前提
# （见 GPEditService.gpSetMount() 的说明）。
# Drop: RESTORE the pre-drag tuple first, then let the command re-apply it — the precondition for
# the stack recording an undo step (see GPEditService.gpSetMount()).
func _gpCommitPositioning() -> void:
	var gpCv: GPCanvas2D = gpCtx.gpCv
	var gpId: String = _gpDrag.gpNodeId()
	# The "after" tuple comes from the KERNEL, not from a hand-written literal: it must carry every
	# mount field the drag can change — gpMountAngleDeg included, or the part snaps back upright on
	# release after having turned correctly under the cursor.
	# 「之后」元组取自**内核**，而非手写字面量：它必须携带拖拽可能改变的每一个挂载字段 ——
	# 含 gpMountAngleDeg，否则部件在光标下转向正确、释放后又弹回朝上。
	var gpAfter: Dictionary = _gpDrag.gpCommitTuple()
	# The verdict too comes from the kernel, and MUST be read before gpRestore() rewinds the node —
	# after that the current state is the pre-drag state again and nothing would look changed.
	# 判定同样取自内核，且必须在 gpRestore() 回退**之前**读取 —— 回退后当前态又变回拖拽前，
	# 于是看上去什么都没变。
	var gpDiffer: bool = _gpDrag.gpChanged()
	_gpDrag.gpRestore()
	_gpDrag.gpEnd()
	gpCv.gpClearPendingAttach()
	# 无变化（用户原地点击）时不提交，故不产生幽灵撤销步。
	# A no-op drop (clicked in place) commits nothing, so no phantom undo step appears.
	if gpDiffer:
		gpCv.gpRequestSetMount([gpId], [gpAfter])
	gpCv.gpSetSelection([gpId])
	gpCv.queue_redraw()




# 幽灵：半透明实形，与落位**共用同一条规则**（gpPlacementTuple）—— 吸附时坐在锚点上并按锚点
# 法向转向；在宿主体内滑行时停在光标处、按落点侧转向。拖动中看到的即松手后得到的。
# The ghost: a translucent silhouette sharing the SAME rule as the drop (gpPlacementTuple) — seated
# on the anchor and turned by its normal on a snap; at the cursor, turned toward the drop's side
# while gliding over a host's body. What you see while dragging is what you get on release.
func _gpDrawGhost(gpItem: CanvasItem, gpCv: GPCanvas2D, gpDef: GPSymbolDef) -> void:
	var gpPos: Vector2 = _gpGhostWorld
	var gpRot: float = 0.0
	if not _gpPlace.is_empty():
		# A snap shows the part ON the anchor (that is what snapping means); a body landing shows
		# it under the cursor (that is where it will land).
		# 吸附时部件显示**在锚点上**（吸附的意义就在此）；体内落位时显示**在光标下**
		# （那正是它将要落下的位置）。
		gpPos = _gpPlace["anchor_pos"] if bool(_gpPlace["on_anchor"]) else _gpGhostWorld
		var gpDir: Vector2 = _gpPlace["anchor_dir"]
		if gpDir != Vector2.ZERO:
			gpRot = GPMountResolver.gpAnchorDirToRotation(gpDir, gpDef.gpBaseMountRot) \
				+ float(_gpPlace["mount_angle_deg"])
	var gpSz: Vector2 = gpDef.gpDefaultSize
	var gpBaseColor: Color = GPSymbolPainter.gpCategoryColor(gpDef.gpCategory)
	var gpFill: Color = Color(gpBaseColor.r, gpBaseColor.g, gpBaseColor.b, GP_GHOST_FILL_ALPHA)
	var gpStroke: Color = gpBaseColor.lightened(0.25)
	gpStroke.a = GP_GHOST_STROKE_ALPHA
	# draw_set_transform(P, rot, S) => local = P + S*q, i.e. the origin is NOT scaled. The shape is
	# therefore drawn around (0,0) in symbol pixels and the transform places/scales it.
	# draw_set_transform(P, rot, S) 语义为 local = P + S*q，即原点 P **不被**缩放。
	# 故形状以图元像素绕 (0,0) 绘制，由变换负责摆放与缩放。
	var gpZoom: float = gpCv.gpViewZoom
	gpItem.draw_set_transform(gpCv.gpScreenFromWorld(gpPos), deg_to_rad(gpRot),
		Vector2(gpZoom, gpZoom))
	var gpRect: Rect2 = Rect2(-gpSz / 2.0, gpSz)
	if not gpDef.gpShapes.is_empty():
		GPSymbolPainter.gpDrawShape(gpItem, gpDef.gpShapeSpec(), gpRect, gpFill, gpStroke, 2.0)
	else:
		gpItem.draw_rect(gpRect, gpFill, true)
		gpItem.draw_rect(gpRect, gpStroke, false, 2.0)
	gpItem.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 锚点高亮环 —— 命中时给出「会挂到这里」的明确反馈（规划 §15.2 第 3 步）。
# The anchor highlight ring — explicit "it will land HERE" feedback (§15.2 step 3).
func _gpDrawAnchorRing(gpItem: CanvasItem, gpCv: GPCanvas2D) -> void:
	var gpZoom: float = gpCv.gpViewZoom
	var gpCenter: Vector2 = gpCv.gpScreenFromWorld(_gpCand["pos"])
	var gpRing: float = GP_ANCHOR_RING * gpZoom
	var gpHit: bool = bool(_gpCand.get("hit", false))
	var gpCol: Color = Color(0.20, 0.85, 0.35, 0.95) if gpHit else Color(0.70, 0.70, 0.70, 0.55)
	gpItem.draw_arc(gpCenter, gpRing, 0.0, TAU, 24, gpCol, GP_ANCHOR_RING_WIDTH * gpZoom, true)
