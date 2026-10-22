# ============================================================================
# GPPortConnectOps — 端点（锚点）高亮 / 拾取 / 拖拽连线
# Endpoint (anchor) highlight / pick / drag-to-connect.
#
# 与 GPEdgeGripOps 同形的画布委托：瞬态交互状态留在本类，画布只负责转发事件与提供一个
# 公开端口。所有几何与合法性判定都下沉到 GPPortAnchor（core/view，纯静态、可 headless 单测）。
# A canvas delegate shaped like GPEdgeGripOps: the transient interaction state lives here and the
# canvas only forwards events plus one public port. Every geometric and legality decision is
# pushed down into GPPortAnchor (core/view, pure static, headless-testable).
#
# Interaction contract / 交互契约：
# 单击端点 = 拾取（供「自动连线」选端点，再点一次取消）
# 从端点拖到另一端点 = 直接连线（合法才连，非法落点拒绝并提示）
# click an anchor = pick it (auto-connect endpoint; click again to drop)
# drag anchor -> anchor = connect (only when legal; an illegal drop refuses out loud)
# ============================================================================

class_name GPPortConnectOps
extends RefCounted

const GPMode = GPCanvasInteractState.GPMode

# ---- anchor visual states / 锚点视觉状态 ----
const GP_STATE_IDLE: int = 0      # 已选中图元上的普通锚点 / plain anchor on a selected symbol
const GP_STATE_HOVER: int = 1     # 光标悬停 / under the cursor
const GP_STATE_PICKED: int = 2    # 已被拾取为自动连线端点 / picked as an auto-connect endpoint
const GP_STATE_OK: int = 3        # 拖拽中的合法落点 / legal drop target while dragging
const GP_STATE_BAD: int = 4       # 拖拽中的非法落点 / illegal drop target while dragging
const GP_STATE_SOURCE: int = 5    # 本次拖拽的起点 / source of the current drag

# Pick box size and dot radius in SCREEN pixels — the CEILING of the drawn handle.
# WHY A CEILING AND NOT A CONSTANT: a fixed 13 px box next to a 4x2 mm ball valve (4x2 screen
# points at 100% zoom, see plan Phase 0's mm base) is THREE TIMES the symbol, so the handles
# buried the very thing they belong to. The drawn handle now follows the symbol's on-screen size
# (see _gpHandleUnit()) and only falls back to these values for large equipment. Clickability is
# unaffected because picking uses GPPortAnchor.GP_ANCHOR_PX, which stays constant.
# 拾取框尺寸与圆点半径（屏幕像素）—— 为「所绘制手柄」的上限。
# 为何是上限而非定值：固定在 4×2mm 球阀（100% 缩放下即 4×2 屏幕点，见计划 Phase 0 的 mm 基准）
# 旁边的 13px 方框是图元的**三倍大**，手柄因此埋没了它本该服务的图元本身。现在绘制的手柄随
# 图元的屏幕尺寸而变（见 _gpHandleUnit()），仅在大型设备上回退到这里的取值。可点性不受影响：
# 拾取使用恒定的 GPPortAnchor.GP_ANCHOR_PX。
const GP_BOX: float = 13.0
const GP_DOT: float = 4.0

# Lower bound of the drawn handle so a very small symbol still shows a visible anchor.
# 所绘制手柄的下限，使极小图元仍能看见锚点。
const GP_MIN_HANDLE: float = 3.5

# Share of the symbol's larger on-screen dimension the handle box occupies.
# 手柄框占图元屏幕较大边长的比例。
const GP_HANDLE_RATIO: float = 0.30

# The visible dot is a SECOND fraction, applied to the handle UNIT (which already carries
# GP_HANDLE_RATIO), so the dot always stays inside the box that is drawn around it. Kept as its own
# named constant because "two ratios multiply" is easy to misread as an accidental double-application.
# 可见圆点在上海柄单元（其已含 GP_HANDLE_RATIO）之上再乘的**第二层**比例，使圆点始终落在围绕它的
# 方框之内。单列常量，是因为「两个比例相乘」极易被误读为误加的重复系数。
const GP_DOT_RATIO: float = 0.30

# Extra size / line weight applied to the emphasised states.
# 强调状态附加的尺寸与线宽。
const GP_GROW: float = 3.0

const GP_COL_IDLE: Color = Color(0.62, 0.69, 0.82, 0.95)
const GP_COL_HOVER: Color = Color(1.00, 0.92, 0.35, 1.0)
const GP_COL_PICKED: Color = Color(0.35, 0.95, 0.55, 1.0)
const GP_COL_OK: Color = Color(0.30, 1.00, 0.45, 1.0)
const GP_COL_BAD: Color = Color(1.00, 0.32, 0.32, 1.0)
const GP_COL_SOURCE: Color = Color(0.35, 0.90, 1.00, 1.0)

# Preview line colours (WYSIWYG: the preview uses the committed edge's own router).
# 预览线颜色（所见即所得：预览使用已提交边自身的布线器）。
const GP_COL_PREVIEW_OK: Color = Color(0.30, 1.00, 0.45, 0.95)
const GP_COL_PREVIEW_BAD: Color = Color(1.00, 0.42, 0.42, 0.85)

# Canvas this delegate acts on (state owner).
# 本委托作用的画布（状态持有者）。
var gpCv: GPCanvas2D

# Anchor the current drag started from (empty = no drag in flight).
# 本次拖拽的起点锚点（为空表示无进行中的拖拽）。
var _gpFrom: Dictionary = {}

# Anchor currently under the cursor during a drag (empty = cursor is over free space).
# 拖拽中光标下的锚点（为空表示光标在空白处）。
var _gpTarget: Dictionary = {}

# Latest cursor position in world coordinates.
# 光标在世界坐标系中的最新位置。
var _gpCursor: Vector2 = Vector2.ZERO

# Whether _gpTarget is a legal partner for _gpFrom.
# _gpTarget 是否为 _gpFrom 的合法配对。
var _gpValid: bool = false

# World position where the drag began (used to tell a click from a drag).
# 拖拽开始时的世界坐标（用于区分单击与拖拽）。
var _gpPressWorld: Vector2 = Vector2.ZERO


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# ============================ 状态查询 ============================

# Whether the current gesture has moved far enough to be a LINE rather than a CLICK.
# 当前手势是否已移动足够远、构成**画线**而不是**单击**。
var _gpMoved: bool = false

# True while an anchor-to-anchor drag is in flight.
# 端点对端点拖拽进行中返回真。
func gpIsDragging() -> bool:
	return not _gpFrom.is_empty()


# ============================ 输入 ============================

# Try to start a drag from the anchor under gpWorld. Returns false when nothing was hit, so the
# caller falls through to the normal node / edge / marquee handling.
# 尝试从 gpWorld 下的锚点开始拖拽。未命中返回 false，使调用方回落到常规的节点 / 边 / 框选处理。
func gpTryStartDrag(gpWorld: Vector2) -> bool:
	if gpCv.gpGraph == null or gpCv.gpSelection.is_empty():
		return false
	var gpA: Dictionary = GPPortAnchor.gpHitPort(gpCv.gpGraph, gpCv.gpDefLookupCallable(),
		gpWorld, gpCv.gpViewZoom, gpCv.gpSelection)
	if gpA.is_empty():
		return false
	_gpFrom = gpA
	_gpTarget = gpA
	_gpCursor = gpWorld
	_gpPressWorld = gpWorld
	_gpValid = false
	# A fresh gesture starts "not moved": a pure click must keep toggling the pick list, while a
	# real drag that ends in empty space is an OPEN END (see gpFinishDrag).
	# 新手势从「未移动」开始：纯单击仍切换拾取列表，而真正拖到空白的拖拽是**开口端**（见 gpFinishDrag）。
	_gpMoved = false
	return true


# Refresh the hover anchor (called on plain mouse motion, outside any drag).
# 刷新悬停锚点（在普通鼠标移动时调用，拖拽之外）。
func gpUpdateHover(gpWorld: Vector2) -> void:
	if gpCv.gpGraph == null:
		return
	var gpA: Dictionary = {}
	if not gpCv.gpSelection.is_empty():
		gpA = GPPortAnchor.gpHitPort(gpCv.gpGraph, gpCv.gpDefLookupCallable(), gpWorld,
			gpCv.gpViewZoom, gpCv.gpSelection)
	gpCv.gpHoverPort = gpA


# Update the drag: re-snap the target and re-check legality.
# 更新拖拽：重新吸附目标并重新判定合法性。
func gpUpdateDrag(gpWorld: Vector2) -> void:
	if _gpFrom.is_empty():
		return
	_gpCursor = gpWorld
	# Movement threshold: 3 world units ≈ a few pixels. Below it the gesture is still a CLICK
	# (picking two anchors for auto-connect), above it the user meant to draw a line.
	# 移动阈值：3 世界单位约等于几个像素。低于它是**单击**（为自动连线拾取两个锚点），
	# 高于它说明用户是在画线。
	if gpWorld.distance_to(_gpPressWorld) > 3.0:
		_gpMoved = true
	# During a drag EVERY symbol's anchors are candidates: requiring the target to be selected
	# first would make the gesture useless.
	# 拖拽期间「每个」图元的锚点都是候选：若要求目标先被选中，该手势就没用了。
	_gpTarget = GPPortAnchor.gpHitPort(gpCv.gpGraph, gpCv.gpDefLookupCallable(), gpWorld,
		gpCv.gpViewZoom, [])
	_gpValid = (not _gpTarget.is_empty()) and GPPortAnchor.gpValidatePair(
		_gpFrom, _gpTarget) == GPPortAnchor.GP_REFUSAL_NONE


# Commit or abandon the drag. Returns true when an edge was created.
# 提交或放弃本次拖拽。创建出边时返回 true。
func gpFinishDrag() -> bool:
	if _gpFrom.is_empty():
		return false
	var gpFrom: Dictionary = _gpFrom
	var gpTarget: Dictionary = _gpTarget
	_gpReset()
	# Dropped on a DIFFERENT, legal anchor -> connect.
	# 落在「另一个」合法锚点上 -> 连线。
	if (not gpTarget.is_empty()) and (not GPPortAnchor.gpSamePort(gpFrom, gpTarget)):
		var gpWhy: String = GPPortAnchor.gpValidatePair(gpFrom, gpTarget)
		if gpWhy != GPPortAnchor.GP_REFUSAL_NONE:
 # An illegal drop must SAY why instead of silently doing nothing.
 # 非法落点必须「说出原因」，而不是静默地什么都不做。
			gpCv.gpReportRefusal(gpWhy)
			return false
		var gpKind: String = GPPortAnchor.gpConnectKindFor(str(gpFrom.get("type", "")),
			str(gpTarget.get("type", "")))
		var gpId: String = gpCv.gpRequestConnectEdge(_gpRefOf(gpFrom), _gpRefOf(gpTarget), gpKind)
		if gpId == "":
			gpCv.gpReportRefusal(gpCv.gpActions.gpLastRefusal)
			return false
		gpCv.gpPortPick.clear()
		gpCv.queue_redraw()
		return true
	# Dropped in EMPTY SPACE after a real drag -> finish the line as an OPEN END. It used to toggle
	# the pick list instead, which made the line VANISH on release — the gesture looked broken.
	# 真正拖拽后在**空白处**松开 → 以**开口端**结束这条线。此前会改成「切换拾取」，导致线在松手时
	# 消失 —— 手势看起来是坏的。
	if _gpMoved:
		var gpKindOpen: String = gpKindOfSource(str(gpFrom.get("type", "")))
		var gpTo: Dictionary = {"node_id": "", "port_id": "", "point": [_gpCursor.x, _gpCursor.y]}
		var gpId2: String = gpCv.gpRequestConnectEdge(_gpRefOf(gpFrom), gpTo, gpKindOpen)
		if gpId2 == "":
			gpCv.gpReportRefusal(gpCv.gpActions.gpLastRefusal)
			return false
		# NO selection and NO lingering hover ring: selecting the new edge drew grip handles, and the
		# hovered nozzle kept its highlight — the user read both as an unwanted "orange circle" at
		# the open end. Finishing a line should leave a clean drawing.
		# **不**选中新边、也清掉悬停环：选中会画出手柄、悬停的管嘴还会保留高亮 ——
		# 用户把这两者都当成了开口端处不该有的「橙色圈」。画完线应当留一张干净的图。
		gpCv.gpSetEdgeSelection([])
		gpCv.gpHoverPort = {}
		gpCv.queue_redraw()
		# REVERSE direction of "drag a note onto a port": dragging a port OUT to empty space
		# produces the note text. Opening the editor here is what turns "a line to nowhere" into
		# "a named open end"; cancelling leaves the line as an unnamed open end (still an error the
		# DRC reports, which is honest).
		# 「把注记拖到端口」的**反向**：从端口拖到空白处会产出注记文字。在此打开编辑器，正是把
		# 「一条通向虚无的线」变成「一个已命名的开口端」的那一步；取消则留下未命名的开口端
		#（DRC 仍会报它 —— 这是诚实的）。
		gpCv.gpOpenEndNoteDialog(gpId2, false)
		return true
	# Dropped back on itself (a click, not a drag) -> toggle the pick.
	# 落回自身（是单击而非拖拽）-> 切换拾取状态。
	gpTogglePick(gpFrom)
	gpCv.queue_redraw()
	return false


# Finish the drag as an OPEN END carrying a note: ONE undo step (edge + note). Used by the dwell
# prompt, which is how the user gets from "I stopped here" to "this end is TO ATM".
# 以带注记的**开口端**结束本次拖拽：一步撤销（边 + 注记）。供悬停提示使用 ——
# 用户从「我停在这儿」走到「这个端头是 TO ATM」正是经它。
# gpText empty + gpExistingUid set means "share that already-annotated end point".
# gpText 为空且 gpExistingUid 非空表示「共用那个已注明的开口端」。
func gpFinishDragAsOpenEnd(gpText: String, gpExistingUid: String = "") -> String:
	if _gpFrom.is_empty():
		return ""
	var gpFrom: Dictionary = _gpFrom
	var gpKindOpen: String = gpKindOfSource(str(gpFrom.get("type", "")))
	var gpSignalType: String = "ELECTRIC" if gpKindOpen == GPPIDEdge.GP_SIGNAL else ""
	var gpTo: Dictionary = {"node_id": "", "port_id": "", "point": [_gpCursor.x, _gpCursor.y]}
	var gpId: String = gpCv.gpRequestFinishOpenEnd(_gpRefOf(gpFrom), gpTo, gpKindOpen,
		gpSignalType, gpText, false, true, gpExistingUid)
	_gpReset()
	if gpId != "":
		# Leave the drawing clean (see the note on the empty-space release above).
		# 保持画面干净（见上方「空白处松手」处的说明）。
		gpCv.gpSetEdgeSelection([])
		gpCv.gpHoverPort = {}
		gpCv.queue_redraw()
	return gpId


# Line kind implied by the anchor's PORT TYPE: signal anchors make signal lines, everything else
# makes a process pipe. One rule, used by both finish paths.
# 由锚点的**端口类型**决定线类型：信号类锚点出信号线，其余出工艺管道。一条规则，两条收尾路径共用。
func gpKindOfSource(gpPortType: String) -> String:
	if gpPortType == GPPort.GP_SIGNAL or gpPortType == GPPort.GP_ACTUATOR:
		return GPPIDEdge.GP_SIGNAL
	return GPPIDEdge.GP_PROCESS


# Abandon the drag (ESC path).
# 放弃拖拽（ESC 路径）。
func gpCancelDrag() -> void:
	if _gpFrom.is_empty():
		return
	_gpReset()
	gpCv.queue_redraw()


# Add / remove an anchor from the auto-connect pick list (max two, oldest dropped first).
# 在自动连线选取列表中加入 / 移除一个锚点（最多两个，超出则丢掉最早的那个）。
func gpTogglePick(gpA: Dictionary) -> void:
	if gpA.is_empty():
		return
	var gpIdx: int = -1
	for gpI in range(gpCv.gpPortPick.size()):
		if GPPortAnchor.gpSamePort(gpCv.gpPortPick[gpI], gpA):
			gpIdx = gpI
			break
	if gpIdx >= 0:
		gpCv.gpPortPick.remove_at(gpIdx)
		return
	if gpCv.gpPortPick.size() >= 2:
		gpCv.gpPortPick.remove_at(0)
	gpCv.gpPortPick.append(gpA)


# ============================ 绘制 ============================

# Paint the anchors (and, while dragging, the preview line). Called from the canvas overlay in
# SCREEN space so the pick boxes keep a constant size at any zoom.
# 绘制锚点（拖拽中另绘预览线）。由画布覆盖层以「屏幕」坐标调用，使拾取框在任意缩放下尺寸恒定。
func gpDrawPorts(gpTarget: CanvasItem) -> void:
	if gpCv == null or gpTarget == null or gpCv.gpGraph == null:
		return
	var gpDragging: bool = gpIsDragging()
	var gpNodeIds: Array[String] = []
	if not gpDragging:
 # Anchors are exposed by SELECTED symbols only (plus the picked pair, so an auto-connect
 # selection stays visible even after the symbol is deselected).
 # 锚点仅由「已选中」的图元暴露（外加已拾取的那对，使自动连线的选择在取消选中图元后依然可见）。
		# A hovered port must be drawn even when nothing is selected: during a note drag the selection
		# is the SHAPE, not a node — without this branch there would be no anchor to highlight.
		# 即使没有选中节点，悬停的端口也必须画出来：拖注记时选中的是**图形**而非节点 ——
		# 缺这一分支就没有可高亮的锚点。
		if gpCv.gpSelection.is_empty() and gpCv.gpPortPick.is_empty() \
				and gpCv.gpHoverPort.is_empty():
			return
		gpNodeIds = gpCv.gpSelection.duplicate()
		for gpP in gpCv.gpPortPick:
			var gpNid: String = str(gpP.get("node_id", ""))
			if gpNid != "" and not gpNodeIds.has(gpNid):
				gpNodeIds.append(gpNid)
		var gpHoverNid: String = str(gpCv.gpHoverPort.get("node_id", ""))
		if gpHoverNid != "" and not gpNodeIds.has(gpHoverNid):
			gpNodeIds.append(gpHoverNid)
	var gpAnchors: Array[Dictionary] = GPPortAnchor.gpAnchors(gpCv.gpGraph,
		gpCv.gpDefLookupCallable(), gpNodeIds)
	for gpA in gpAnchors:
		_gpDrawOne(gpTarget, gpA, gpDragging)
	if gpDragging:
		_gpDrawPreview(gpTarget)


# ============================ private ============================

func _gpReset() -> void:
	_gpFrom = {}
	_gpTarget = {}
	_gpValid = false


# Turn an anchor record into the ref an edge stores.
# 把锚点记录转换为边所存的引用。
func _gpRefOf(gpA: Dictionary) -> Dictionary:
	return {"node_id": str(gpA.get("node_id", "")), "port_id": str(gpA.get("port_id", ""))}


# Visual state of one anchor in the current interaction context.
# 当前交互上下文中某个锚点的视觉状态。
func _gpStateOf(gpA: Dictionary, gpDragging: bool) -> int:
	# Not dragging, but the cursor (or a dragged note) is over this port → show the hover ring.
	# 未拖拽，但光标（或被拖动的注记）正压在这个端口上 → 显示悬停环。
	if not gpDragging and not gpCv.gpHoverPort.is_empty() \
			and GPPortAnchor.gpSamePort(gpA, gpCv.gpHoverPort):
		return GP_STATE_HOVER
	if gpDragging:
		if GPPortAnchor.gpSamePort(gpA, _gpFrom):
			return GP_STATE_SOURCE
		if not _gpTarget.is_empty() and GPPortAnchor.gpSamePort(gpA, _gpTarget):
			return GP_STATE_OK if _gpValid else GP_STATE_BAD
 # Every other anchor is tinted by whether it COULD accept this line.
 # 其余锚点按「能否接受本条线」着色。
		if GPPortAnchor.gpValidatePair(_gpFrom, gpA) == GPPortAnchor.GP_REFUSAL_NONE:
			return GP_STATE_OK
		return GP_STATE_BAD
	for gpP in gpCv.gpPortPick:
		if GPPortAnchor.gpSamePort(gpP, gpA):
			return GP_STATE_PICKED
	if GPPortAnchor.gpSamePort(gpCv.gpHoverPort, gpA):
		return GP_STATE_HOVER
	return GP_STATE_IDLE


# Paint one anchor: a coloured dot plus its pick box.
# 绘制单个锚点：彩色圆点 + 拾取框。
func _gpDrawOne(gpTarget: CanvasItem, gpA: Dictionary, gpDragging: bool) -> void:
	var gpP: Vector2 = gpCv.gpScreenFromWorld(gpA.get("pos", Vector2.ZERO) as Vector2)
	var gpState: int = _gpStateOf(gpA, gpDragging)
	var gpCol: Color = GP_COL_IDLE
	var gpGrow: float = 0.0
	var gpWidth: float = 1.5
	match gpState:
		GP_STATE_HOVER:
			gpCol = GP_COL_HOVER
			gpGrow = GP_GROW
			gpWidth = 2.0
		GP_STATE_PICKED:
			gpCol = GP_COL_PICKED
			gpGrow = GP_GROW
			gpWidth = 2.2
		GP_STATE_OK:
			gpCol = GP_COL_OK
			gpGrow = GP_GROW * 0.7
			gpWidth = 2.0
		GP_STATE_BAD:
			gpCol = GP_COL_BAD
			gpWidth = 1.2
		GP_STATE_SOURCE:
			gpCol = GP_COL_SOURCE
			gpGrow = GP_GROW
			gpWidth = 2.2
		_:
			gpCol = GP_COL_IDLE
	# The dot keeps the port's own purpose colour, so a nozzle still reads as a nozzle.
	# 圆点保留端口自身的用途色，使管口看起来仍是管口。
	var gpUnit: float = _gpHandleUnit(str(gpA.get("node_id", "")))
	var gpDot: float = clampf(gpUnit * GP_DOT_RATIO, GP_MIN_HANDLE * 0.35, GP_DOT)
	var gpBox: float = gpHandleBoxFor(gpUnit)
	var gpDotCol: Color = GPEdgeStyle.gpPortColor(str(gpA.get("type", "")))
	gpTarget.draw_circle(gpP, gpDot + gpGrow * 0.5, gpDotCol)
	# Pick box: the thing the user actually clicks. / 拾取框：用户真正点中的东西。
	var gpSize: float = gpBox + gpGrow
	var gpRect: Rect2 = Rect2(gpP - Vector2(gpSize, gpSize) * 0.5, Vector2(gpSize, gpSize))
	gpTarget.draw_rect(gpRect, gpCol, false, gpWidth)
	# A picked / source anchor gets a second, outer box: unmistakable at a glance.
	# 已拾取 / 起点的锚点再加一个外框：一眼即可辨认。
	if gpState == GP_STATE_PICKED or gpState == GP_STATE_SOURCE:
		gpTarget.draw_rect(gpRect.grow(3.0), gpCol, false, 1.0)


# The rubber-band preview, drawn with the SAME router the committed edge will use.
# 橡皮筋预览，使用「已提交边将使用的同一个」布线器绘制。
func _gpDrawPreview(gpTarget: CanvasItem) -> void:
	var gpFrom: Dictionary = {
		"pos": _gpFrom.get("pos", Vector2.ZERO),
		"dir": _gpFrom.get("dir", Vector2.ZERO),
		"bound": true,
	}
	var gpTo: Dictionary
	if not _gpTarget.is_empty():
		gpTo = {
			"pos": _gpTarget.get("pos", Vector2.ZERO),
			"dir": _gpTarget.get("dir", Vector2.ZERO),
			"bound": true,
		}
	else:
		gpTo = {"pos": _gpCursor, "dir": Vector2.ZERO, "bound": false}
	var gpWorld: PackedVector2Array = GPEdgeRoute.gpRoute(gpFrom, gpTo, [], true)
	if gpWorld.size() < 2:
		return
	var gpPts: PackedVector2Array = PackedVector2Array()
	for gpP in gpWorld:
		gpPts.append(gpCv.gpScreenFromWorld(gpP))
	# Illegal drop: red and dashed-looking (thin) so it reads as "no" before the mouse is released.
	# 非法落点：红色且更细，使鼠标释放「之前」就能读出「不行」。
	gpTarget.draw_polyline(gpPts, GP_COL_PREVIEW_OK if _gpValid else GP_COL_PREVIEW_BAD,
		2.0 if _gpValid else 1.2)
	# Snap hint: a ring on the anchor about to be picked up.
	# 吸附提示：在即将被选中的锚点上画一个圆环。
	if not _gpTarget.is_empty():
		var gpEp: Vector2 = gpCv.gpScreenFromWorld(_gpTarget.get("pos", Vector2.ZERO) as Vector2)
		gpTarget.draw_arc(gpEp, clampf(_gpHandleUnit(str(_gpTarget.get("node_id", ""))),
			GP_MIN_HANDLE, GP_BOX) * 0.75, 0.0, TAU, 20,
			GP_COL_OK if _gpValid else GP_COL_BAD, 2.0)


# Screen size of the handle this anchor's symbol deserves: a fraction of the symbol's larger
# on-screen dimension, so the handle stays proportional to whatever it annotates — 4 mm valve or
# 420 mm column. Returns 0 when the node / definition cannot be resolved, which makes the caller
# fall back to the constant FLOOR (clampf(0, GP_MIN_HANDLE, GP_BOX) == GP_MIN_HANDLE) — i.e. an
# unresolvable anchor gets the smallest legible handle, never a symbol-sized one.
# 该锚点所属图元应得的手柄屏幕尺寸：取图元屏幕较大边长的某个比例，使手柄始终与其所标注之物
# 成比例 —— 无论是 4mm 的阀门还是 420mm 的塔器。节点/定义无法解析时返回 0，调用方据此回退到
# 常量**下限**（clampf(0, GP_MIN_HANDLE, GP_BOX) == GP_MIN_HANDLE）—— 即无法解析的锚点得到
# 最小的可读手柄，而绝不会得到「图元大小」的手柄。
func _gpHandleUnit(gpNodeId: String) -> float:
	if gpNodeId == "" or gpCv.gpGraph == null:
		return 0.0
	var gpNode: GPPIDNode = gpCv.gpGraph.gpGetNode(gpNodeId)
	if gpNode == null:
		return 0.0
	var gpDef: GPSymbolDef = gpCv.gpDefFor(gpNode.gpSymbolId)
	if gpDef == null:
		return 0.0
	return gpHandleUnitFor(maxf(gpDef.gpDefaultSize.x, gpDef.gpDefaultSize.y), gpCv.gpViewZoom)


# Handle unit (screen px) for a symbol whose larger authored side is gpSymbolMaxMM, at gpZoom.
# Pure, so the "handle must scale with its symbol" contract is pinned by a test.
# 较大作者边长为 gpSymbolMaxMM 的图元在 gpZoom 下的手柄单元（屏幕 px）。纯函数，使
# 「手柄须随其图元缩放」这一契约由测试钉住。
static func gpHandleUnitFor(gpSymbolMaxMM: float, gpZoom: float) -> float:
	if gpSymbolMaxMM <= 0.0 or gpZoom <= 0.0:
		return 0.0
	return gpSymbolMaxMM * gpZoom * GP_HANDLE_RATIO


# Clamp a handle unit into the legible range. Pure, and the ONLY place the floor/ceiling apply.
# 把柄单元夹取到可读区间。纯函数，也是下限/上限唯一生效之处。
static func gpHandleBoxFor(gpUnit: float) -> float:
	return clampf(gpUnit, GP_MIN_HANDLE, GP_BOX)
