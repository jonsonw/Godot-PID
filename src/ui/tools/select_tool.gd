# ============================================================================
# GPSelectTool — 选择 / 连线 / 框选 / 注释图形 交互
# Select / connect / marquee / annotation-shape interaction.
#
# 持有「选择模式」下的按下 / 释放 / 移动逻辑。锚点 / 整图形拖拽的「执行」部分在 GPGripTool，本类
# 只负责发起它们。
# Owns the SELECT-mode press / release / move logic. The grip / whole-shape DRAG execution lives in
# GPGripTool; this tool only initiates it.
#
# 整组拖拽状态（_gpDragId / _gpDragStartWorld / _gpDragOrigins）与其执行函数（gpOnDragMove()）、
# 以及框选提交，都经公开端口（gpMarq / gpRequest* / gpSnapshot()）进行。框选橡皮筋本身仍由
# GPCanvasMarquee 经共享状态对象持有，本类经 gpCtx.gpState.gpMarquee 取用（与画布的 gpMarq
# 是同一实例，故行为完全等价）。
# The group-drag state, its executor (gpOnDragMove()) and the marquee commit all go through public
# ports (gpMarq / gpRequest* / gpSnapshot()). The marquee band stays in GPCanvasMarquee via the
# shared state object; this tool reaches it through gpCtx.gpState.gpMarquee (the same instance as
# gpMarq, so behaviour is identical).
# ============================================================================

class_name GPSelectTool
extends GPCanvasTool

const GPMode = GPCanvasInteractState.GPMode

# Pressed node that anchors the group drag ("" = no drag in flight).
# 锚定整组拖拽的被按下节点（"" 表示无进行中的拖拽）。
var _gpDragId: String = ""

# World position where the group drag started (to measure the delta).
# 整组拖拽开始时的世界坐标（用于测量位移）。
var _gpDragStartWorld: Vector2 = Vector2.ZERO

# Snapshot of every dragged node's position at drag start: id -> Vector2.
# 拖拽开始时各被拖节点位置的快照：id -> Vector2。
var _gpDragOrigins: Dictionary = {}

# Snapshot of every NON-dragged node's position at drag start: id -> Vector2. The drag may push
# these aside via collision avoidance; this lets release rewind them before committing one clean
# undo step. Cleared on every drag start so a new drag never inherits a stale snapshot.
# 拖拽开始时各「非被拖」节点位置的快照：id -> Vector2。拖拽可能经碰撞避让把这些节点推开；
# 此快照使释放时能先把它们回退，再一次性提交干净的撤销步。每次拖拽开始都清空，避免沿用陈旧快照。
var _gpPushOrigins: Dictionary = {}

# Snapshot of which lines each dragged node already covered at drag start: id -> Array[String].
# Used on release to prompt ONLY for lines the symbol newly moved onto (not ones it sat on already).
# 拖拽开始时各被拖节点已压到的连线快照：id -> Array[String]。释放时只对新压到的连线弹出选择
# （而非它原本就压着的）。
var _gpDragStartEdges: Dictionary = {}

# The marquee band, owned by the shared interact state (same instance as the canvas's _gpMarq).
# 选框橡皮筋，由共享交互状态持有（与画布的 _gpMarq 为同一实例）。
var _gpMarq: GPCanvasMarquee:
	get: return gpCtx.gpState.gpMarquee


# True while a whole-selection group drag is in flight .
# 整组拖拽进行中返回真。
func gpIsDragging() -> bool:
	return _gpDragId != ""


# Abandon any in-flight group drag (canvas clear-selection path).
# 放弃进行中的整组拖拽（画布清空选择路径）。
func gpCancelDrag() -> void:
	_gpDragId = ""
	_gpDragOrigins.clear()
	_gpPushOrigins.clear()
	_gpDragStartEdges.clear()


# ESC path : report whether a group drag was abandoned, so the canvas can cancel
# through the generic tool port instead of holding this tool's concrete type.
# ESC 路径：报告是否放弃了整组拖拽，使画布可经通用工具端口取消，
# 而不必持有本工具的具体类型。
func gpCancel() -> bool:
	if _gpDragId == "":
		return false
	gpCancelDrag()
	return true


# Live-apply a group drag: replay every selected node from its start snapshot by the same delta, so
func gpOnDragMove(gpScreen: Vector2) -> void:
	var gpCv := gpCtx.gpCv
	var gpDelta: Vector2 = gpCv.gpWorldFromScreen(gpScreen) - _gpDragStartWorld
	var gpMoved: Array[String] = []
	for gpId in _gpDragOrigins.keys():
		var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
		if gpN == null:
			continue
		gpN.gpPosition = (_gpDragOrigins[gpId] as Vector2) + gpDelta
		var gpV: GPSymbolView = gpCv.gpBinder.gpGetSymbolView(gpId)
		if gpV != null:
			gpV.gpUpdateTransform()
		gpMoved.append(gpId)
	# Live collision avoidance: the dragged selection is the fixed anchor; shove any overlapping
	# neighbours aside so they scatter smoothly as the cursor moves (best-effort per frame).
	# Returns the neighbour ids it actually displaced, so their pipes can follow too.
	# 实时碰撞避让：被选（被拖）集合为固定锚点，把此刻与之重叠的邻件推开，
	# 使其随光标移动平滑散开（每帧尽力而为）。返回其实际推移的邻件 id，使它们的管线也能跟随。
	var gpPushed: Array[String] = _gpAvoidDuringDrag(gpCv)
	for gpId in gpPushed:
		if not gpMoved.has(gpId):
			gpMoved.append(gpId)
	# Redraw every pipe touching a moved node so its endpoints follow the symbol in real time
	# instead of snapping to the final position only on release. The drag feedback must include
	# the connected wires, not just the glyph.
	# 重绘所有触碰被移动节点的管线，使其端点在拖拽过程中实时跟随图元，
	# 而非等到释放时才突跳到位。拖拽反馈必须包含相连管线，而不只是字形本体。
	if not gpMoved.is_empty():
		gpCv.gpBinder.gpRedrawEdgesForNodes(gpMoved)
 # Also request a full canvas-frame repaint every drag frame. This keeps the background
 # overlay, the selection highlight and EVERY edge view in sync through the proven
 # _draw()/gpSync() path (which recomputes each pipe body from the live node position),
 # as a belt-and-suspenders guarantee on top of the synchronous gpApplyGeometry() above.
 # The marquee drag already does this on every move; the node drag must too, otherwise
 # the canvas's own sync loop stays dormant and an edge that depended on it would lag.
 # 同时请求整帧画布重绘。这使背景覆盖层、选中高亮与每条连线视图在每个拖拽帧都经已验证的
 # _draw()/gpSync() 路径保持同步（该路径依节点实时位置重算每条管线主体），与上方同步的
 # gpApplyGeometry() 形成双保险。框选拖拽每帧都已如此；节点拖拽亦须如此，否则画布自身的
 # 同步循环处于休眠，依赖它的连线便会滞后。
		gpCv.queue_redraw()


# Push every node that now overlaps a dragged (fixed) node aside, live during a group drag.
# 整组拖拽时实时把此刻与被拖（固定）节点重叠的图元推开。
# Only non-dragged nodes move; the dragged selection stays glued to the cursor. A few relaxation
# passes per frame keep the feedback smooth without freezing the drag.
# 只有非被拖节点会移动，被拖集合始终黏在光标处。每帧少量松弛迭代既能保证反馈平滑又不卡顿。
func _gpAvoidDuringDrag(gpCv: GPCanvas2D) -> Array[String]:
	var gpMoved: Array[String] = []
	var gpFixed: Array[String] = []
	for gpId in _gpDragOrigins.keys():
		gpFixed.append(gpId)
	# A node the dragged part could attach to must not be shoved away by that very gesture: pin
	# every potential host so the drag reads as "snapping onto" rather than "pushing aside".
	# 被拖部件可能挂上去的那个节点绝不能被该手势推开：把所有潜在宿主钉住，使这次拖拽读作
	#「吸附上去」而不是「推开」。
	for gpId in GPMountResolver.gpPinnedHosts(gpCv.gpGraph, gpCv.gpDefFor, gpFixed):
		gpFixed.append(gpId)
	var gpAvoid: Dictionary = GPNodeCollision.gpResolve(gpCv.gpGraph, gpCv.gpDefFor,
		gpFixed, GPNodeCollision.GP_DEFAULT_PADDING, 4)
	for gpId in gpAvoid.keys():
		var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
		if gpN == null:
			continue
		gpN.gpPosition = (gpAvoid[gpId] as Vector2)
		var gpV: GPSymbolView = gpCv.gpBinder.gpGetSymbolView(gpId)
		if gpV != null:
			gpV.gpUpdateTransform()
		gpMoved.append(gpId)
	return gpMoved


func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	var gpCv := gpCtx.gpCv
	# Clear any bump-anchor selection first; re-set below only when an anchor is actually grabbed.
	# 先清除鼓包锚点选择；仅当真正抓到锚点时才在下方重新置位。
	gpCtx.gpEdgeGrips.gpClearBumpSelection()
	var gpHit: String = gpCv.gpHitTest(gpWorld)
	# Rev.3 stage 1.5 (R1): a double click on a node's LABEL TEXT edits the tag in place, as
	# ONE undo step. Tested BEFORE the body branch and NOT gated on gpHit — the label usually
	# sits OUTSIDE the glyph where gpHitTest() reports a miss (the same M10b fact the tag grip
	# lives with), so dispatching through gpHit alone would leave the text dead on screen. The
	# predicate inside gpHitTextAny refuses anything that is not a tag-like single-path label,
	# so name/prop-derived texts and slot-bearing symbols keep the dialog here.
	# Rev.3 阶段 1.5（R1）：双击图元的**标签文字**就地改位号，一个撤销步。必须在「本体」分支
	# **之前**测、且**不以** gpHit 为闸 —— 标签通常位于字形**之外**，那里 gpHitTest() 报未命中
	#（与位号抓取点同源的 M10b 事实），只经 gpHit 分派会让文字在屏幕上完全是死的。
	# gpHitTextAny 内部的判据会拒绝一切「非位号型的单路径标签」，故名称 / 属性派生文字与
	# 带槽图元在此仍走对话框。
	if gpDouble and gpCtx.gpNodeEditor != null:
		# Stage 3 S2: a GRID table's double-click edits the CELL under the cursor (before
		# the label dispatch — the table owns its cells). The cell resolution shares the
		# generator with the renderer (Rev.2 iron rule) and, like the hit test, treats the
		# envelope as axis-aligned (v1: rotation/flip ignored for the field overlay).
		# 阶段 3 S2：grid 表格的双击编辑光标下的**格子**（先于标签分派 —— 表格的格子归它自己
		# 管）。格子解析与渲染共用同一个生成器（Rev.2 铁律）；与命中测试一样把包络视为
		# 轴对齐（v1：浮层忽略旋转/翻转）。
		var gpCellTarget: Dictionary = _gpCellEditTarget(gpCv, gpWorld)
		if str(gpCellTarget["node"]) != "":
			gpCtx.gpNodeEditor.gpOpenCell(str(gpCellTarget["node"]),
				str(gpCellTarget["key"]), gpCellTarget["rect"] as Rect2)
			return true
		var gpTextLabel: String = GPNodeTextEditor.gpHitTextAny(gpCv.gpGraph,
			gpCv.gpDefLookupCallable(), gpWorld)
		if gpTextLabel != "":
			gpCtx.gpNodeEditor.gpOpen(gpTextLabel)
			return true
	# Double click asks the host to open the symbol editor dialog (seeded with this
	# symbol's geometry) — the in-place BEDIT editor was removed.
	# 双击请求宿主打开图元编辑对话框（预填该图元几何）；就地 BEDIT 编辑器已移除。
	if gpDouble and gpHit != "":
		var gpDblNode: GPPIDNode = gpCv.gpGraph.gpGetNode(gpHit)
		if gpDblNode != null:
			gpCv.gpSymbolEditRequested.emit(gpDblNode.gpSymbolId)
		return true
	# Connect mode: pick source then destination.
	# 连线模式：先选起点再选终点。
	if gpCv.gpMode == GPMode.GP_CONNECT:
		if gpHit != "":
			if gpCv.gpConnectFrom == "":
				gpCv.gpConnectFrom = gpHit
			else:
				if gpCv.gpConnectFrom != gpHit:
 # 无法撤销且绕过了共享 id 生成器之外的全部约定）。
					gpCv.gpRequestConnect(gpCv.gpConnectFrom, gpHit)
				gpCv.gpConnectFrom = ""
			gpCv.queue_redraw()
		return true
	# SELECT mode: hit -> select (Shift toggles); miss -> start a marquee.
	# 选择模式：命中 → 选择（Shift 切换）；落空 → 开始框选。
	# M10b: the tag grip of the single selected node is tested FIRST, because it can sit
	# outside the glyph (below / beside it) where gpHitTest() would report a miss.
	# M10b：单选节点的位号抓取点被**优先**检测，因为它可能落在字形之外（下方 / 侧旁），
	# 而那里 gpHitTest() 会报未命中。
	var gpSelId: String = ""
	# A press that landed on ANOTHER node is not a press on the host's tag handle, even when it
	# happens to be within the handle's radius: a mounted PART of the selected host (a nozzle on a
	# vessel) is a smaller, more specific target than the host's own tag, and letting the handle win
	# there made those parts impossible to pick up — the reported "the built-in parts cannot be
	# dragged". The handle still owns every press that hit no node at all, which is the case it
	# exists for (it can sit outside the glyph).
	# 落在**另一个节点**上的按下不算按在宿主位号手柄上，即使它恰好落在手柄半径内：选中宿主的
	# **挂载部件**（罐上的管嘴）是比宿主位号更小、更具体的目标，让手柄在那里取胜会使这些部件
	# 完全拾不起来 —— 即用户报告的「自带部件拖不动」。手柄仍然独占「没打中任何节点」的按下，
	# 而那正是它存在的场景（它可以落在字形之外）。
	var gpGripBlocked: bool = gpHit != "" and gpHit != gpSelId
	if gpCv.gpSelection.size() == 1 and gpCtx.gpLabelGrips != null and not gpGripBlocked:
		gpSelId = gpCv.gpSelection[0]
		if gpDouble and gpCtx.gpLabelGrips.gpHitGrip(gpWorld,
				gpCv.gpGraph.gpGetNode(gpSelId), gpCv.gpDefFor(
					gpCv.gpGraph.gpGetNode(gpSelId).gpSymbolId if gpCv.gpGraph.gpGetNode(gpSelId) != null else ""),
				8.0 / maxf(gpCv.gpViewZoom, 0.0001),
				gpCv.gpGraph, gpCv.gpDefLookupCallable()):
 # Double-click the grip: reset to the type layer's default.
 # 双击抓取点：复位为类型层默认。
			gpCtx.gpLabelGrips.gpReset(gpSelId)
			return true
	if not gpGripBlocked and gpCtx.gpLabelGrips.gpTryStart(gpWorld, gpSelId):
		return true
	# P3-4 (grip priority): when a single edge is already selected, its grips (midpoint AND endpoint)
	# take priority over node / marquee handling, so a grip sitting on a symbol can still be grabbed.
	# 端点抓取点落在图元上，否则会被节点命中先行吃掉；故单选边时其抓取点优先于节点 / 框选处理。
	if gpCv.gpEdgeSel.size() == 1:
		var gpGrip: Dictionary = gpCtx.gpEdgeGrips.gpHitGrip(gpWorld, gpCv.gpEdgeSel[0])
		if not gpGrip.is_empty():
			gpCtx.gpEdgeGrips.gpStartGripDrag(gpCv.gpEdgeSel[0], gpGrip)
			return true
 # Orange bump anchor on the edge under the cursor (any edge) -> reshape that bump.
 # 光标下边上的橙色鼓包锚点（任意边）→ 重塑该鼓包。
		var gpEdgeUnder: String = gpCv.gpHitEdge(gpWorld)
		if gpEdgeUnder != "":
			var gpBump: Dictionary = gpCtx.gpEdgeGrips.gpHitBump(gpWorld, gpEdgeUnder)
			if not gpBump.is_empty():
				gpCtx.gpEdgeGrips.gpSelectBump(gpEdgeUnder, int(gpBump["anchor"]))
				gpCtx.gpEdgeGrips.gpStartBumpDrag(gpEdgeUnder, int(gpBump["anchor"]))
				return true
 # Body of the SAME selected edge (not a grip):
 # - a straight port-to-port edge has no routing to translate, so dragging the body must
 # insert a corner at the press point and drag it (makes the line draggable);
 # - any other edge (bent, or with a free/dangling end) keeps the whole-line translate.
 # 同一选中边的线体（非抓取点）：
 # - 直连端口端口的直边没有可平移的路由，故拖拽线体须改为「在按下处插入角点并拖动」（使线可拖动）；
 # - 其余边（弯曲、或含悬空端）保持整线刚性平移。
		if gpCv.gpHitEdge(gpWorld) == gpCv.gpEdgeSel[0]:
			var gpEid: String = gpCv.gpEdgeSel[0]
			var gpEbody: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEid)
			if gpEbody != null and gpEbody.gpRouting.is_empty() and not gpEbody.gpIsDangling(true) and not gpEbody.gpIsDangling(false):
				gpCtx.gpEdgeGrips.gpStartCornerDrag(gpEid, gpWorld)
			else:
				gpCtx.gpEdgeGrips.gpStartEdgeMove(gpEid, gpWorld)
			return true
	if gpHit != "":
 # P3-4: selecting a node drops any edge selection (the two are mutually exclusive).
 # 选中节点时清除边选择（两者互斥）。
		gpCv.gpEdgeSel.clear()
		if gpShift:
			if gpCv.gpSelection.has(gpHit):
				gpCv.gpSelection.erase(gpHit)
			else:
				gpCv.gpSelection.append(gpHit)
			gpCv.gpSetSelection(gpCv.gpSelection)
		elif not gpCv.gpSelection.has(gpHit):
			gpCv.gpSetSelection([gpHit])
 # Stage 3 S4: a press on the single-selected grid table's internal COLUMN SEPARATOR starts
 # a width drag instead of a body move. Tested AFTER the selection write above (a press on an
 # unselected table selects it first, so the single-selection gate inside gpTryStart sees the
 # fresh selection), and BEFORE the mounted/body branches (a table is never mounted, and the
 # separator is a more specific target than the body).
 # 阶段 3 S4：按在**单选** grid 表格的内部**列分隔线**上时开始列宽拖拽，而非本体搬动。
 # 在上方的选择写入**之后**测（按在未选中的表格上会先选中它，故 gpTryStart 内的单选闸看到的
 # 就是新选择）、在挂载 / 本体分支**之前**测（表格永不会被挂载，而分隔线是比本体更具体的目标）。
		if gpCtx.gpTableGrips != null and gpCtx.gpTableGrips.gpTryStart(gpWorld, gpHit):
			gpCv.queue_redraw()
			gpCv.gpEmitStatus()
			return true
 # A MOUNTED node is dragged by RE-MOUNTING it, not by writing its position: its world placement is
 # derived from the parent chain (see GPMountResolver), so a position drag would move the model and
 # leave the picture exactly where it was. The drag is handed to GPPlaceAttachTool so the kernel,
 # the preview and the single-undo-step commit stay shared with both §15 modes rather than being
 # reimplemented here.
 # 拖拽**已挂载**节点 = 重新挂载它，而不是写它的坐标：其世界位置由父链推导（见 GPMountResolver），
 # 故坐标拖拽会改模型却让画面纹丝不动。该拖拽交给 GPPlaceAttachTool，使内核、预览与「一步撤销」
 # 的提交与 §15 两种模式共用，而不是在此重写一遍。
 # The press returns here WITHOUT starting a position drag; the next motion / release is routed to
 # the attach tool, because arming it makes gpActiveTool() select it.
 # 本次按下在此返回，**不**启动坐标拖拽；随后的移动 / 释放会路由到附件工具，因为上膛就使
 # gpActiveTool() 选中它。
		var gpHitNode: GPPIDNode = gpCv.gpGraph.gpGetNode(gpHit) if gpCv.gpGraph != null else null
		if gpHitNode != null and gpHitNode.gpIsMounted():
			# A REFUSED arming must not swallow the press: falling through hands it to the ordinary
			# selection / drag path, instead of the part silently ignoring the user.
			# 上膛被拒时**绝不**吞掉这次按下：继续往下走会把它交给普通的选择 / 拖拽路径，
			# 而不是让部件静默地无视用户。
			if gpCv.gpArmMountDrag(gpHit, false):
				return true
 # Start a group drag only when the pressed node belongs to the selection.
 # 仅当按下的节点属于选择集时才开始整组拖拽。
		if gpCv.gpSelection.has(gpHit):
			_gpDragId = gpHit
			_gpDragStartWorld = gpWorld
			_gpDragOrigins.clear()
			_gpPushOrigins.clear()
			for gpId in gpCv.gpSelection:
				var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
				if gpN != null:
					_gpDragOrigins[gpId] = gpN.gpPosition
 # Snapshot which lines each dragged node already covers, so on release we only prompt
 # for lines it NEWLY moved onto (not ones it was already sitting on).
 # 快照每个被拖节点此刻压到的连线，使释放时只对「新压到」的连线弹出选择（而非原本就压着的）。
			_gpDragStartEdges.clear()
			for gpId in _gpDragOrigins.keys():
				var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
				if gpN != null:
					_gpDragStartEdges[gpId] = gpCv.gpEdgeGrips.gpEdgesUnderNode(gpN)
 # Snapshot every other node so a collision push can be rewound on release.
 # 快照其余所有节点，使释放时能回退被碰撞推送的节点。
			for gpO in gpCv.gpGraph.gpNodes:
				if not _gpDragOrigins.has(gpO.gpInstanceId):
					_gpPushOrigins[gpO.gpInstanceId] = gpO.gpPosition
		else:
			_gpDragId = ""
	else:
 # ---- P3-4: edge selection / double-click tag edit / grip drag ----
 # 边选择 / 双击改号 / 抓取点拖拽。
 # Pipes and signal lines are first-class selection targets in SELECT mode, just below
 # nodes. / 管道与信号线是选择模式下的一等选择目标，优先级仅次于节点。
 # Edge tag grip: the line-number is itself draggable. Tested across ALL edges (not just the
 # selected one) so a number dragged far off its pipe can still be grabbed to drag it back.
 # 边管线号抓取点：管线号本身可拖动。跨「所有」边检测（不限于已选中），
 # 使被拖离管线的编号仍可抓回。
		var gpTagEid: String = gpCtx.gpEdgeTagGrips.gpHitGripAny(gpWorld)
		if gpTagEid != "":
			if gpDouble:
 # Double-click the number: reset it to the auto (default) placement.
 # 双击编号：复位到自动（默认）落位。
				gpCtx.gpEdgeTagGrips.gpReset(gpTagEid)
			else:
 # Select the edge, then begin the drag from the press point.
 # 先选中该边，再从按下点开始拖拽。
				gpCv.gpSetEdgeSelection([gpTagEid])
				gpCtx.gpEdgeTagGrips.gpTryStart(gpWorld, gpTagEid)
			return true
		var gpEdgeHit: String = gpCv.gpHitEdge(gpWorld)
 # Double-click an edge opens its line-number editor in place. / 双击边就地打开管线号编辑器。
		if gpDouble and gpEdgeHit != "":
			gpCtx.gpEdgeEditor.gpOpen(gpEdgeHit)
			return true
 # Plain click on an edge selects it (mutually exclusive with node / shape selection).
 # 在边上的普通点击选中该边（与节点 / 图形选择互斥）。
		if gpEdgeHit != "":
			if gpShift:
				if gpCv.gpEdgeSel.has(gpEdgeHit):
					gpCv.gpEdgeSel.erase(gpEdgeHit)
				else:
					gpCv.gpEdgeSel.append(gpEdgeHit)
				gpCv.gpSetEdgeSelection(gpCv.gpEdgeSel)
			elif not gpCv.gpEdgeSel.has(gpEdgeHit):
				gpCv.gpSetEdgeSelection([gpEdgeHit])
			return true
 # Double-clicking a vertex / handle grip of the single selected annotation polyline toggles
 # Bézier handles (corner <-> smooth). Intercept BEFORE the hit/move logic below.
 # 双击「单选注释折线」的顶点 / 手柄抓取点：切换贝塞尔手柄（拐角 <-> 平滑）。须在下方命中/移动
 # 逻辑之前拦截。
		if gpDouble and gpCtx.gpAnno.gpOnShapeGripDoubleClick(gpWorld):
			return true
 # When a single shape is selected, try to grab one of ITS grips first. A pulled-out Bézier
 # handle end often sits OUTSIDE the polyline stroke, so testing shape-line hit first would
 # miss it and fall through to a marquee — making handles appear but not draggable.
 # 当单选一枚图形时，先尝试命中它自己的抓取点。拉出的贝塞尔手柄末端常位于折线墨线之外，若先按
 # 线段命中，会漏判并落入框选——造成句柄可见却拖不动。
		if gpCv.gpShapeSel.size() == 1:
			var gpGripAny: Dictionary = gpCtx.gpAnno.gpHitGrip(gpWorld, gpCv.gpShapeSel[0])
			if not gpGripAny.is_empty():
				gpCtx.gpAnno.gpStartGripDrag(gpGripAny)
				return true
 # No symbol hit: try an annotation shape (grip editing has priority when one is selected).
 # 未命中图元：改试注释图形（选中一枚时锚点编辑优先）。
		var gpSh: int = gpCv.gpHitShape(gpWorld)
		if gpSh >= 0:
 # P3-4: picking a shape drops any edge selection (mutually exclusive).
 # 选中图形时清除边选择（互斥）。
			gpCv.gpEdgeSel.clear()
			if gpCv.gpShapeSel.size() == 1:
				var gpGrip: Dictionary = gpCtx.gpAnno.gpHitGrip(gpWorld, gpCv.gpShapeSel[0])
				if not gpGrip.is_empty():
					gpCtx.gpAnno.gpStartGripDrag(gpGrip)
					return true
			if gpShift:
				if gpCv.gpShapeSel.has(gpSh):
					gpCv.gpShapeSel.erase(gpSh)
				else:
					gpCv.gpShapeSel.append(gpSh)
			elif not gpCv.gpShapeSel.has(gpSh):
				gpCv.gpShapeSel = [gpSh]
				gpCv.gpSetSelection([])
			gpCv.queue_redraw()
 # Begin a whole-shape move, replaying rigidly from the start snapshot.
 # 从此图形开始整体移动，由起始快照无漂移重放。
 # the drag snapshot now lives in GPAnnotationEditor — one port call replaces four
 # writes into canvas internals.
 # 拖拽快照现由 GPAnnotationEditor 持有——一次端口调用取代四次写画布内部字段。
			gpCtx.gpAnno.gpStartShapeDrag(gpSh, gpWorld)
			return true
 # Empty space: clear selection and start a marquee.
 # 空白处：清空选择并开始框选。
		if not gpShift:
			gpCv.gpSetSelection([])
			gpCv.gpShapeSel.clear()
 # P3-4: clicking empty space also drops any edge selection.
 # 点空白处同样清除边选择。
			gpCv.gpEdgeSel.clear()
		# ★ Rev.3 stage 1: the title block, FIRST among the sheet's furniture.
		# ★ Rev.3 阶段 1：图签，图纸陈设中的**第一**环。
		#
		# ⚠️ WHY IT PRECEDES THE FRAME / ⚠️ 为何在图框之前：the two targets OVERLAP — the block hugs the
		# frame's bottom-right corner, so part of the block's outline runs along the frame's own right and
		# bottom lines. A press there must mean the block (that is what the user aimed at); the frame's
		# corner is not lost, it is merely underneath, and moving the block exposes it. Testing the frame
		# first would leave the block half-draggable — its own bottom and right edges would resize the
		# frame instead of moving it.
		# 两个目标**重叠** —— 图签贴住图框右下角，故图签的一部分轮廓就沿着图框自身的右边与下边线。在那里按下
		# 必须意味着图签（那才是用户瞄准的东西）；图框那个角并未丢失，只是被压在下面，把图签移开即可露出。
		# 若先测图框，图签就会变成「只有一半能拖」—— 它自己的下边与右边会去改图框尺寸，而不是搬动它。
		#
		# Still inside the branch that TODAY only clears the selection and starts a rubber band, so like the
		# frame's probe below it cannot regress symbol / edge / annotation picking (a property of the
		# POSITION, not of the code inside the branch).
		# 它仍在「今天只会清空选择并起橡皮筋」的那个分支内，故与下方的图框探测一样，不可能回归图元 / 边 /
		# 注释图形的拾取（这是**位置**带来的性质，而不是分支内代码带来的）。
		# ★ 2026-10-16: a DOUBLE click on the title block opens its dialog (tested BEFORE the drag
		# arming below). The block has no in-place editor, so the dialog is the only way to change
		# its 13 fields — and a double click that only armed a no-motion drag felt completely dead
		# to the user. A plain press here still arms the drag: the two gestures stay distinct.
		# ★ 2026-10-16：**双击**图签打开其对话框（必须在下方拖拽上膛**之前**测）。图签没有就地编辑器，
		# 对话框是改它 13 个字段的唯一途径 —— 而只会上膛一次零位移拖拽的双击对用户来说完全是死的。
		# 普通按下在这里仍然上膛拖拽：两种手势互不干扰。
		if gpDouble and gpCtx.gpTitleBlockGrips.gpHit(gpWorld):
			gpCv.gpTitleBlockEditRequested.emit()
			return true
		if gpCtx.gpTitleBlockGrips.gpTryStart(gpWorld):
			gpCv.queue_redraw()
			gpCv.gpEmitStatus()
			return true
		# ★ Rev.3 stage 0c: the drawing frame, LAST before the marquee.
		# ★ Rev.3 阶段 0c：图框，紧接框选之前的最后一环。
		#
		# WHY EXACTLY HERE / 为何恰在此处：this is the branch that TODAY only clears the selection and
		# starts a rubber band — nothing above it can be reached by a press the frame accepts, so the
		# change cannot regress symbol / edge / annotation picking. That is a property of the POSITION,
		# not of the code in the branch.
		# 这一分支在今天只会清空选择并起橡皮筋 —— 图框接受的按下够不到它上方的任何一级，故本改动不可能
		# 回归图元 / 边 / 注释图形的拾取。这是**位置**带来的性质，而不是分支内代码带来的。
		# The band test is cheap (four distance checks on the frame rectangle) and runs on every click that
		# selected nothing, so it stays a pure geometry query — no node, no marker, no state.
		# 抓取带检测很便宜（对图框矩形做四次距离比较），且会在每一次「什么也没选中」的点击上运行，
		# 故它保持为纯几何查询 —— 不建节点、不留标记、不改状态。
		#
		# ⚠️ WHY THE ⌥Alt STATE IS READ LIVE HERE / ⚠️ 为何在此**实时**读 ⌥Alt：
		# the press chain (GPCanvas2D._gpOnLeftDown -> GPInputRouter.gpOnLeftDown -> gpOnPress) carries
		# Shift and double-click but NOT Alt, and threading a fourth parameter would have to touch all ten
		# gpOnPress implementations — four of them inside the symbol editor dialog, which owns no frame and
		# could never use it. Reading it here keeps the change to the one tool that has a frame, and matches
		# the existing precedent in GPPipeTool._gpIsStraight(), which samples a modifier live for the same
		# reason — a modifier that only matters at the instant of one event does not deserve a parameter on
		# a shared interface. The value is handed to GPFrameGripOps as an ARGUMENT, so the gesture decision
		# itself stays a pure function and remains headless-testable.
		# 按下链路（GPCanvas2D._gpOnLeftDown -> GPInputRouter.gpOnLeftDown -> gpOnPress）只传 Shift 与双击，
		# **不传** Alt；而加第四个参数就得改全部十处 gpOnPress 实现 —— 其中四处位于符号编辑器对话框内，
		# 那里没有图框、永远用不到。就近读取把改动限制在**唯一**拥有图框的工具上，并与 GPPipeTool._gpIsStraight()
		# 中的既有先例一致（同样出于「只在某一事件瞬间有意义的修饰键，不值得为它在共享接口上加参数」）：
		# 该值以**实参**交给 GPFrameGripOps，故手势判定本身仍是纯函数、仍可 headless 测试。
		if gpCtx.gpFrameGrips.gpTryStart(gpWorld, Input.is_key_pressed(KEY_ALT)):
			gpCv.queue_redraw()
			gpCv.gpEmitStatus()
			return true
		var gpScreen: Vector2 = gpCv.gpScreenFromWorld(gpWorld)
		_gpMarq.gpBegin(gpScreen, gpShift)
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()
	return true


func gpOnRelease(gpWorld: Vector2) -> bool:
	var gpCv := gpCtx.gpCv
	# Grid-table column-boundary drag (stage 3 S4): commit as ONE undo step. Same three beats
	# as the title-block / frame drags below — rewind to the drag-start CSV, then let ONE
	# command re-apply the final one.
	# grid 表格列边界拖拽（阶段 3 S4）：提交为**一个**撤销步。与下方图签 / 图框拖拽同一三拍
	# —— 回退到拖拽起始 CSV，再由**一条**命令重新应用最终值。
	if gpCtx.gpTableGrips != null and gpCtx.gpTableGrips.gpIsDragging():
		gpCtx.gpTableGrips.gpEndGripDrag()
		gpCv.gpEmitStatus()
		return true
	# Title-block drag (Rev.3 stage 1): commit as ONE undo step. Same three beats as the frame drag below —
	# rewind to the drag-start docking pair, then let ONE command re-apply the final pair, so a block moved
	# 30 times during one gesture is ONE undo step and is never applied twice.
	# 图签拖拽（Rev.3 阶段 1）：提交为**一个**撤销步。与下方图框拖拽同一三拍 —— 回退到拖拽起始停靠对，再交由
	# **一条**命令重新应用最终对，故一次手势中搬动了 30 次的图签只是**一个**撤销步、且绝不叠加两次。
	if gpCtx.gpTitleBlockGrips.gpIsDragging():
		gpCtx.gpTitleBlockGrips.gpEndGripDrag()
		gpCv.gpEmitStatus()
		return true
	# Frame drag (Rev.3 stage 0c): commit as ONE undo step. The grip op rewinds the sheet to its
	# drag-start margins and lets the command re-apply the final ones, so a frame moved 30 times during
	# one gesture is ONE undo step — never thirty, and never applied twice.
	# 图框拖拽（Rev.3 阶段 0c）：提交为**一个**撤销步。抓取操作先把图纸回退到拖拽起始边距，再由命令
	# 重新应用最终值，故一次手势中移动了 30 次的图框只是**一个**撤销步 —— 不是三十个，也绝不叠加两次。
	if gpCtx.gpFrameGrips.gpIsDragging():
		gpCtx.gpFrameGrips.gpEndGripDrag()
		gpCv.gpEmitStatus()
		return true
	# Finish a marquee: gpFinish() reports whether the band was dragged far enough to be a real
	# marquee; a press/release without movement is a plain click, already handled on press.
	# gpFinish() 报告选框是否被拖到足以构成真正的框选；未产生位移的按下/释放只是普通单击。
	if _gpMarq.gpActive:
		if _gpMarq.gpFinish():
			_gpCommitMarquee()
		gpCv.queue_redraw()
		gpCv.gpEmitStatus()
		return true
	# Finish a group drag. Geometry was mutated live for feedback; to make the whole move AND any
	# collision pushes undoable as ONE step, we rewind every node (dragged + pushed) to its drag-start
	# position, then let a single command re-apply the final, fully-separated layout. One undo step
	# per drag, never applied twice.
	# 先把每个节点（被拖 + 被推）都回退到拖拽起点，再交由一条命令重新应用「最终、完全分离」后的
	# 布局。每次拖拽合成一个撤销步，且绝不会被叠加两次。
	if _gpDragId != "":
		_gpDragId = ""
		var gpIds: Array[String] = []
		var gpDelta: Vector2 = gpWorld - _gpDragStartWorld
		for gpId in _gpDragOrigins.keys():
			var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
			if gpN != null:
				gpN.gpPosition = (_gpDragOrigins[gpId] as Vector2)
				gpIds.append(gpId)
 # Rewind the pushed neighbours too, so the command starts from a clean baseline.
 # 同样回退被推送的邻件，使命令从干净基线起步。
		for gpId in _gpPushOrigins.keys():
			var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
			if gpN != null:
				gpN.gpPosition = (_gpPushOrigins[gpId] as Vector2)
 # Dragged nodes follow the cursor; neighbours are resolved to a non-overlapping layout.
 # 被拖节点跟随光标；邻件被解析为互不重叠的布局。
		var gpTargets: Dictionary = {}
		for gpId in gpIds:
			gpTargets[gpId] = (_gpDragOrigins[gpId] as Vector2) + gpDelta
		# A single LOOSE part released on a host MOUNTS there instead of landing as a loose symbol
		# on top of the equipment. The mount decision (anchor snap, body fallback, facing side) is
		# the resolver's; this hook only routes the release to a mount command when it applies.
		# 单个**松散部件**释放在宿主上时**就地挂载**，而不是作为松散图元压在设备上。
		# 挂载判定（锚点吸附 / 本体兜底 / 朝向侧别）属解析器；此处仅把符合条件的释放路由到挂载命令。
		# ⚠️ Stage-2 gate (gpMountable, Rev.3 §8): a definition that declared itself NOT mountable
		# (tables, multiline text) skips the mount routing entirely and lands loose — dropping a
		# table on a vessel must never make it a child of the vessel. The gate sits BEFORE the
		# resolver call: the resolver reasons about parts, and a non-mountable def is not one.
		# The decision itself is GPMountResolver.gpReleaseMayMount() (single source, pinned).
		# ⚠️ 阶段 2 闸（gpMountable，Rev.3 §8）：声明**不可挂载**的定义（表格、多行文本）完全
		# 跳过挂载路由、落为松散图元 —— 把表格拖放到罐上绝不能让它变成罐的子件。闸在解析器
		# **调用之前**：解析器推理的对象是部件，而不可挂载的定义根本不是部件。
		# 判定本体是 GPMountResolver.gpReleaseMayMount()（单一来源、已被钉住）。
		var gpReleaseDef: GPSymbolDef = gpCv.gpDefFor(gpIds[0])
		if gpIds.size() == 1 and not is_zero_approx(gpDelta.length()) \
				and GPMountResolver.gpReleaseMayMount(gpReleaseDef):
			var gpMountTuple: Dictionary = GPMountResolver.gpLooseReleaseAttach(gpCv.gpGraph,
				gpCv.gpDefFor, gpIds[0], gpWorld, gpCv.gpViewZoom)
			if not gpMountTuple.is_empty():
				var gpMountIds: Array[String] = [gpIds[0]]
				var gpMountTuples: Array[Dictionary] = [gpMountTuple]
				if gpCv.gpRequestSetMount(gpMountIds, gpMountTuples):
					_gpDragOrigins.clear()
					_gpPushOrigins.clear()
					_gpDragStartEdges.clear()
					gpCv.gpGraphChanged.emit()
					gpCv.queue_redraw()
					gpCv.gpEmitStatus()
					return true
		var gpAvoidFixed: Array[String] = gpIds.duplicate()
		for gpId in GPMountResolver.gpPinnedHosts(gpCv.gpGraph, gpCv.gpDefFor, gpIds):
			gpAvoidFixed.append(gpId)
		var gpAvoid: Dictionary = GPNodeCollision.gpResolve(gpCv.gpGraph, gpCv.gpDefFor,
				gpAvoidFixed, GPNodeCollision.GP_DEFAULT_PADDING, 24)
		for gpId in gpAvoid.keys():
			gpTargets[gpId] = (gpAvoid[gpId] as Vector2)
		if not gpTargets.is_empty():
			gpCv.gpRequestSetNodePositions(gpTargets)
 # Feature 1: a MOVED symbol that now covers a line it did not cover at drag start offers the
 # same reroute/split choice as a freshly placed one. One prompt per node.
 # 功能 1：移动后压到「拖拽起点未压到的连线」的图元，与刚放置的图元一样弹出「绕行 / 拆分」选择。
 # 每个图元一次提示。
		if gpCv.gpContextMenu != null:
			for gpId in gpIds:
				var gpNode: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
				if gpNode == null:
					continue
				var gpWas: Array = _gpDragStartEdges.get(gpId, [])
				var gpNow: Array[String] = gpCv.gpEdgeGrips.gpEdgesUnderNode(gpNode)
				for gpEid in gpNow:
					if not gpWas.has(gpEid):
						gpCv.gpContextMenu.gpPromptDropOnEdge(gpId, gpEid)
						break
		_gpDragOrigins.clear()
		_gpPushOrigins.clear()
		_gpDragStartEdges.clear()
		gpCv.gpGraphChanged.emit()
		gpCv.queue_redraw()
		gpCv.gpEmitStatus()
		return true
	return false


func gpOnMove(gpWorld: Vector2) -> bool:
	var gpCv := gpCtx.gpCv
	# Grid-table column-boundary drag (stage 3 S4). Checked FIRST for the same reason the two
	# drags below are: a drag here is mutually exclusive with every other drag by construction.
	# grid 表格列边界拖拽（阶段 3 S4）。**最先**检查，理由与下方两个拖拽相同：此处拖拽按构造
	# 与其它所有拖拽互斥。
	if gpCtx.gpTableGrips != null and gpCtx.gpTableGrips.gpIsDragging():
		gpCtx.gpTableGrips.gpOnGripMove(gpWorld)
		return true
	# Title-block drag (Rev.3 stage 1). Checked FIRST for the same reason it is tested first on press: a
	# drag here is mutually exclusive with every other drag by construction, and the block's grab area
	# overlaps the frame's band.
	# 图签拖拽（Rev.3 阶段 1）。**最先**检查，理由与按下时先测它相同：此处拖拽按构造与其它所有拖拽互斥，
	# 且图签的抓取区与图框抓取带重叠。
	if gpCtx.gpTitleBlockGrips.gpIsDragging():
		gpCtx.gpTitleBlockGrips.gpOnGripMove(gpWorld)
		return true
	# Frame drag (Rev.3 stage 0c). Checked FIRST because a frame drag is mutually exclusive with every
	# other drag by construction — it can only start where nothing else was selectable, so no earlier
	# branch can have set a state that this one would shadow.
	# 图框拖拽（Rev.3 阶段 0c）。**最先**检查：图框拖拽按构造与其它所有拖拽互斥 —— 它只会在其它什么
	# 都选不中的地方开始，故不可能有更早的分支设置了会被本分支遮蔽的状态。
	if gpCtx.gpFrameGrips.gpIsDragging():
		gpCtx.gpFrameGrips.gpOnGripMove(gpWorld)
		return true
	# Live group-drag: the canvas forwards the motion to the active tool now that drag state
	# 拖拽状态已迁至本工具，画布把移动事件转发到活动工具。返回 true 使画布接受事件而非仅重绘。
	if gpIsDragging():
		gpOnDragMove(gpCv.gpScreenFromWorld(gpWorld))
		return true
	# Connect-preview rubber band (only meaningful while connecting). Not consumed: the canvas
	# redraws but must not swallow the motion event.
	# 连接预览橡皮筋（仅连线时有效）。不消费事件：画布重绘但不吞掉移动事件。
	if gpCv.gpMode == GPMode.GP_CONNECT and gpCv.gpConnectFrom != "":
		gpCv.queue_redraw()
		return false
	return false


func gpOnKey(gpKey: InputEventKey) -> bool:
	return false


# Overlay: draw the grips for every selected edge . Called by the canvas after the shared
# background overlay, so the grips sit above the pipe ink. The canvas itself is the CanvasItem.
# 覆盖层：为每条被选中的边绘制抓取点。由画布在共享背景覆盖层之后调用，使抓取点盖在管线墨线之上。
# 画布自身即 CanvasItem。
func gpDrawOverlay(gpCv: CanvasItem) -> void:
	var gpCanvas := gpCtx.gpCv
	for gpEid in gpCanvas.gpEdgeSel:
		gpCtx.gpEdgeGrips.gpDrawGrips(gpCv, gpEid)
	# The drawing frame's side handles (Rev.3 stage 0c). Drawn in SCREEN space, like the edge grips
	# above, because they are a screen-constant pointing affordance rather than drawing geometry — and
	# because it keeps them off GPFrameView, which must stay a pure renderer of the sheet.
	# 图框的侧手柄（Rev.3 阶段 0c）。与上方边抓取点一样在**屏幕空间**绘制：它们是屏幕常量的「指着用」
	# 可及性区域而非图纸几何 —— 也使它不必进入 GPFrameView，后者必须保持为图纸的纯渲染器。
	gpCtx.gpFrameGrips.gpDrawGrips(gpCv)
	# The title block's hover / drag outline (Rev.3 stage 1). Drawn after the frame's handles so the block's
	# outline wins where the two overlap — matching the press order, where the block is tested first.
	# 图签的悬停 / 拖拽外框（Rev.3 阶段 1）。在图框手柄之后绘制，使两者重叠处图签的外框压在上面 —— 与按下
	# 顺序一致（图签先被测试）。
	gpCtx.gpTitleBlockGrips.gpDrawGrips(gpCv)


# ============================ private ============================

# GPCanvasMarquee so the band the user sees and the set that gets picked can never disagree.
# 选中的集合永不会分歧。
func _gpCommitMarquee() -> void:
	var gpCv := gpCtx.gpCv
	var gpA: Vector2 = gpCv.gpWorldFromScreen(_gpMarq.gpFrom)
	var gpB: Vector2 = gpCv.gpWorldFromScreen(_gpMarq.gpTo)
	var gpRect: Rect2 = Rect2(gpA.min(gpB), (gpA - gpB).abs())
	# Left -> right is WINDOW (enclose); right -> left is CROSSING (touch). Same predicate the
	# drawer used for the band colour, so what you see is what you get.
	# 左→右为窗口（完全包含）；右→左为交叉（碰到即可）。与绘制选框颜色所用的同一判据，所见即所得。
	var gpWindow: bool = _gpMarq.gpIsWindow()
	var gpPicked: Array[String] = []
	for gpN in gpCv.gpGraph.gpNodes:
		if GPCanvasMarquee.gpPicks(gpWindow, gpRect, gpCv.gpNodeRect(gpN.gpInstanceId)):
			gpPicked.append(gpN.gpInstanceId)
	# Annotation shapes are selected by the same marquee (Window/Crossing) rule.
	# 注释图形按相同的框选（包含/相交）规则被选中。
	var gpShapePicked: Array[int] = []
	for gpI in range(gpCv.gpGraph.gpShapes.size()):
		if GPCanvasMarquee.gpPicks(gpWindow, gpRect, gpCv.gpGraph.gpShapes[gpI].gpBBox()):
			gpShapePicked.append(gpI)
	if _gpMarq.gpAdditive:
		for gpId in gpPicked:
			if not gpCv.gpSelection.has(gpId):
				gpCv.gpSelection.append(gpId)
		gpCv.gpSetSelection(gpCv.gpSelection)
		for gpI in gpShapePicked:
			if not gpCv.gpShapeSel.has(gpI):
				gpCv.gpShapeSel.append(gpI)
	else:
		gpCv.gpSetSelection(gpPicked)
		gpCv.gpShapeSel = gpShapePicked
	gpCv.queue_redraw()


# The grid-table cell under a world point: {"node": id, "key": cell key, "rect": local mm}.
# An empty "node" means the double-click target is not a grid table cell. Geometry comes
# from GPSymbolGeneratorRegistry — the SAME cells the renderer paints (Rev.2 iron rule:
# rendering and hit testing must never resolve geometry twice).
# 世界点下的 grid 表格格子：{"node": id, "key": 格键, "rect": 本地 mm}。"node" 为空表示
# 双击目标不是 grid 表格格子。几何取自 GPSymbolGeneratorRegistry —— 与渲染所画的**同一批**
# 格子（Rev.2 铁律：渲染与命中绝不做两次几何解析）。
func _gpCellEditTarget(gpCv: GPCanvas2D, gpWorld: Vector2) -> Dictionary:
	var gpMiss: Dictionary = {"node": "", "key": "", "rect": Rect2()}
	if gpCv.gpGraph == null:
		return gpMiss
	var gpHit: String = gpCv.gpHitTest(gpWorld)
	if gpHit == "":
		return gpMiss
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpHit)
	if gpN == null:
		return gpMiss
	var gpDef: GPSymbolDef = gpCv.gpDefFor(gpN.gpSymbolId)
	if gpDef == null or GPSymbolGeneratorRegistry.gpGeneratorId(gpDef.gpGeometrySource) != "grid":
		return gpMiss
	var gpOrigin: Vector2 = GPPortResolver.gpNodeWorldOrigin(gpCv.gpGraph,
		gpCv.gpDefLookupCallable(), gpN)
	var gpKey: String = GPSymbolGeneratorRegistry.gpCellAt(gpDef, gpN, gpWorld - gpOrigin)
	if gpKey == "":
		return gpMiss
	for gpCell in GPSymbolGeneratorRegistry.gpGridCellsOf(gpDef, gpN):
		if str(gpCell["key"]) == gpKey:
			return {"node": gpHit, "key": gpKey, "rect": gpCell["rect"] as Rect2}
	return gpMiss
