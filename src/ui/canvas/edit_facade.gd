class_name GPCanvasEditFacade
extends RefCounted
# Copyright © 2026 Jonson Wang
# edit intent facade; undo stack
# 编辑意图门面与撤销栈
#
# WHY THIS EXISTS / 为何存在：
# GPCanvas2D was carrying many unrelated responsibilities in one file; this coordinator
# owns the "edit intent facade" use case end to end, so the root keeps only assembly and forwarding.
# GPCanvas2D 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「编辑意图门面与撤销栈」这一用例，
# 使根类只保留装配与转发。
#
# Interaction / 交互方式：
# - the root creates this coordinator and injects itself as gpHost (composition root);
# 根类创建本协调者并把自身注入为 gpHost（组合根装配）；
# - the root forwards user actions here, never the other way round — this class drives the
# host only through its public ports (GPCanvas2D.gp*);
# 根类把用户动作转发到此处，绝不反向 —— 本类只经宿主的公开端口（GPCanvas2D.gp*）驱动宿主；
# - the root keeps every public port it had before: callers outside the canvas are unchanged.
# 根类保留其原有的每一个公开端口：画布外部的调用方零改动。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPCanvas2D = null


# Public: delete the current selection together with its edges (menu 编辑 / 删除).
# 公开：删除当前选择集及其关联的边（菜单「编辑 / 删除」）。
func gpDeleteSelection() -> void:
	gpRequestDeleteSelected()

# Surface a refusal to the user instead of failing silently: a click that produces no pipe must
# SAY why, or the tool looks broken.
# 把拒绝原因呈现给用户而非静默失败：一次点不出管线的点击必须「说明原因」，否则工具看起来是坏的。
# [param gpPrefix] i18n namespace the key lives under. Defaults to "edge." so every pre-existing
# caller is unchanged; the attach paths pass "attach.".
# [param gpPrefix] 键所在的 i18n 命名空间。默认 "edge."，故所有既有调用方不变；附件路径传 "attach."。
func gpReportRefusal(gpKey: String, gpPrefix: String = "edge.") -> void:
	if gpKey == "":
		return
	var gpMsg: String = gpKey
	# Headless-resilient: I18n is an autoload and is absent (or unreachable via an absolute
	# path) outside the live app / active scene tree. Only resolve it when safely in-tree,
	# otherwise keep the raw key as the message so headless runs stay error-free.
	# 无界面容错：I18n 是自动加载单例，脱离活动现场或活跃场景树时（含 headless 测试）
	# 既不存在也无法经绝对路径访问。仅在确定处于活跃场景树内时才解析，否则保留原始
	# 键作为消息，使无界面运行不再产生错误噪声。
	if gpHost.is_inside_tree():
		var gpI18n: Object = gpHost.get_node_or_null("/root/I18n")
		if gpI18n != null and gpI18n.has_method("gpTr"):
			gpMsg = str(gpI18n.gpTr(gpPrefix + gpKey))
	var gpInfo: Dictionary = {"refusal": gpKey, "message": gpMsg}
	gpHost.gpStatusUpdated.emit(gpInfo)
	gpHost.gpEvents.gpStatusUpdated.emit(gpInfo)

# Connect the TWO PICKED endpoints with an obstacle-avoiding orthogonal route.
# 用一条绕开障碍的正交路径，把「两个已拾取的端点」连起来。
# The route becomes the edge's stored waypoints, so it stays fully editable afterwards and the
# manual drag / straight / L-Z-U routing remains available — the two coexist by design.
# 该路径写为这条边的折点，故此后仍可完全编辑，手动拖拽 / 直连 / L-Z-U 布线也依旧可用 ——
# 两种方式按设计并存。
# [return] the new edge id, or "" when refused (fewer than two picks, an illegal pair, ...).
# [return] 新边的 id；被拒绝时返回 ""（拾取不足两个、端点配对非法等）。
func gpRequestAutoConnect() -> String:
	if gpHost.gpGraph == null or gpHost.gpBinder == null or gpHost.gpPortPick.size() != 2:
		return ""
	var gpA: Dictionary = gpHost.gpPortPick[0]
	var gpB: Dictionary = gpHost.gpPortPick[1]
	var gpWhy: String = GPPortAnchor.gpValidatePair(gpA, gpB)
	if gpWhy != GPPortAnchor.GP_REFUSAL_NONE:
		gpReportRefusal(gpWhy)
		return ""
	var gpKind: String = GPPortAnchor.gpConnectKindFor(str(gpA.get("type", "")),
		str(gpB.get("type", "")))
	var gpLookup: Callable = gpHost.gpSymbolLayer.gpDefLookupCallable()
	var gpFa: Dictionary = GPPortAnchor.gpAnchorOf(gpHost.gpGraph, gpLookup, str(gpA.get("node_id", "")),
		str(gpA.get("port_id", "")))
	var gpFb: Dictionary = GPPortAnchor.gpAnchorOf(gpHost.gpGraph, gpLookup, str(gpB.get("node_id", "")),
		str(gpB.get("port_id", "")))
	if gpFa.is_empty() or gpFb.is_empty():
		gpReportRefusal(GPPortAnchor.GP_REFUSAL_MISSING)
		return ""
	var gpFromEnd: Dictionary = {"pos": gpFa.get("pos", Vector2.ZERO),
		"dir": gpFa.get("dir", Vector2.ZERO), "bound": true}
	var gpToEnd: Dictionary = {"pos": gpFb.get("pos", Vector2.ZERO),
		"dir": gpFb.get("dir", Vector2.ZERO), "bound": true}
	# The two endpoint symbols are excluded: a pipe must be allowed to touch what it connects.
	# 排除两个端点图元：管线必须被允许接触它所连接的东西。
	var gpSkip: Array[String] = [str(gpA.get("node_id", "")), str(gpB.get("node_id", ""))]
	var gpObstacles: Array[Rect2] = GPEdgeAutoRoute.gpObstacles(gpHost.gpGraph, gpLookup, gpSkip)
	var gpExisting: Array[PackedVector2Array] = gpHost.gpBinder.gpExistingPolylines()
	var gpPath: PackedVector2Array = GPEdgeAutoRoute.gpRouteAuto(gpFromEnd, gpToEnd, gpObstacles,
		gpExisting)
	# gpRouting stores MIDDLE waypoints only — the ends are re-resolved from the port refs every
	# frame, which is what keeps the pipe glued to its symbol when the symbol moves.
	# gpRouting 只存中间折点 —— 两端每帧都由端口引用重算，这正是图元移动时管线仍紧贴图元的原因。
	var gpMid: Array[Vector2] = []
	for gpI in range(1, gpPath.size() - 1):
		gpMid.append(gpPath[gpI])
	var gpId: String = gpHost.gpActions.gpConnectEdgeRouted({
		"node_id": str(gpA.get("node_id", "")), "port_id": str(gpA.get("port_id", ""))}, {
		"node_id": str(gpB.get("node_id", "")), "port_id": str(gpB.get("port_id", ""))},
		gpKind, gpMid)
	if gpId == "":
		gpReportRefusal(gpHost.gpActions.gpLastRefusal)
		return ""
	gpClearPortPick()
	gpHost.gpGraphChanged.emit()
	gpHost.queue_redraw()
	return gpId

# Drop the auto-connect endpoint picks (ESC path and every selection change).
# 清除自动连线端点的拾取（ESC 路径与每次选择变化时）。
func gpClearPortPick() -> void:
	gpHost.gpPortPick.clear()
	gpHost.gpHoverPort = {}
	gpHost.queue_redraw()

# Replace an edge's intermediate waypoints. / 替换一条边的中间拐点。
func gpRequestSetEdgeRouting(gpEdgeId: String, gpRouting: Array[Vector2]) -> bool:
	return gpHost.gpActions.gpSetEdgeRouting(gpEdgeId, gpRouting)

# Record a drop-on-edge restore entry (Feature 2). / 记录一条落点恢复记录（功能 2）。
func gpRequestRecordDrop(gpSymNid: String, gpRecord: Dictionary) -> void:
	gpHost.gpActions.gpRecordDrop(gpSymNid, gpRecord)

# Move one end of an edge to another port / node, or make it dangle.
# 把一条边的一端改接到另一个端口 / 节点，或改为悬空。
func gpRequestReconnectEdge(gpEdgeId: String, gpIsFrom: bool, gpNewRef: Dictionary) -> bool:
	return gpHost.gpActions.gpReconnectEdge(gpEdgeId, gpIsFrom, gpNewRef)

# Rename an edge's line number. / 修改一条边的管线号。
func gpRequestSetEdgeTag(gpEdgeId: String, gpTag: String) -> bool:
	return gpHost.gpActions.gpSetEdgeTag(gpEdgeId, gpTag)

# Delete edges by id as one undo step. / 按 id 删除边（一步撤销）。
func gpRequestDeleteEdges(gpEdgeIds: Array[String]) -> bool:
	return gpHost.gpActions.gpDeleteEdges(gpEdgeIds)

func gpRequestConnectEdge(gpFromRef: Dictionary, gpToRef: Dictionary, gpKind: String,
		gpSignalType: String = "", gpOrtho: bool = true) -> String:
	return gpHost.gpActions.gpConnectEdge(gpFromRef, gpToRef, gpKind, gpSignalType, gpOrtho)

# Draw a pipe or a signal line between two resolved ends. Returns the new edge id, "" on refusal.
# 在两个已解析端点之间画管道或信号线。返回新边 id，拒绝时为 ""。
# Move the tag of one node . The offset is normalised (1.0 = half the envelope).
# 移动某节点的位号标签。偏移为归一化值（1.0 = 半个包络）。
func gpRequestSetLabelOffset(gpNodeId: String, gpOffset: Vector2) -> bool:
	return gpHost.gpActions.gpSetLabelOffset(gpNodeId, gpOffset)

# Move the line number of one edge . The offset is in WORLD millimetres, added on top of the
# automatic placement; Vector2.ZERO means "back to the automatic placement".
# 移动某条边的管线号。偏移为**世界毫米**，叠加在自动落位之上；Vector2.ZERO 意为「回到自动落位」。
func gpRequestSetEdgeTagOffset(gpEdgeId: String, gpOffset: Vector2) -> bool:
	return gpHost.gpActions.gpSetEdgeTagOffset(gpEdgeId, gpOffset)

# Record a finished group drag as one undo step. The caller rewinds the nodes to their
# pre-drag positions first, so the command re-applies the move instead of doubling it.
# 把一次完成的整组拖拽记录为一个撤销步。调用方先把节点回退到拖拽前位置，
# 使命令重新应用这次移动而非叠加一次。
func gpRequestMoveNodes(gpNodeIds: Array[String], gpDelta: Vector2) -> bool:
	return gpHost.gpActions.gpMoveNodes(gpNodeIds, gpDelta)

# Commit absolute node positions as one undo step (collision-avoidance push). Returns false when
# no node actually moves, so a placement/drag that needed no push records nothing.
# 一步提交节点绝对位置（碰撞避让推送）。无节点真正移动时返回 false，避免多余撤销步。
func gpRequestSetNodePositions(gpTargets: Dictionary) -> bool:
	return gpHost.gpActions.gpSetNodePositions(gpTargets)

# Commit a finished annotation shape. Returns its index in gpShapes(), or -1 on failure.
# 提交一枚绘制完成的注释图形。返回它在 gpShapes() 中的下标，失败返回 -1。
func gpRequestAddShape(gpShape: GPShape) -> int:
	return gpHost.gpActions.gpAddShape(gpShape)

# Connect two nodes with an edge. Returns false for a self-connection or a missing graph.
# 在两个节点之间连线。自连接或缺图时返回 false。
func gpRequestConnect(gpFromId: String, gpToId: String) -> bool:
	return gpHost.gpActions.gpConnect(gpFromId, gpToId)

# ============================ P2: attach / detach ============================
# ============================ P2：挂载 / 卸载 ============================
# Attach one child onto a host anchor (规划 §15, both interaction modes funnel through here).
# Returns the new node's id, or "" when refused — in which case the reason has been surfaced.
# 把一个子件挂到宿主锚点上（规划 §15，两种交互模式都汇聚到此处）。返回新节点 id；
# 被拒时返回 ""，且原因已呈现给用户。
#
# The new node becomes the selection so the user can immediately edit its own properties (管口号 /
# DN / 故障位) without hunting for it — the natural next action after dropping a part.
# 新节点随即成为选中项，使用户能立即编辑它自身的属性（管口号 / DN / 故障位）而不必去找它 ——
# 这是放下部件之后最自然的下一步。
func gpRequestAttachNode(gpSymbolId: String, gpParentUid: String, gpAnchor: String,
		gpOffset: Vector2 = Vector2.ZERO, gpAngleDeg: float = 0.0) -> String:
	if gpHost.gpGraph == null:
		return ""
	var gpNid: String = gpHost.gpActions.gpAttachNode(gpSymbolId, gpParentUid, gpAnchor,
		"", gpOffset, gpAngleDeg)
	if gpNid == "":
		gpReportRefusal(gpHost.gpActions.gpLastRefusal, "attach.")
		return ""
	gpSetSelection([gpNid])
	gpHost.queue_redraw()
	return gpNid


# Detach every selected node from its host, keeping it exactly where it is on screen (the command
# bakes the derived transform — see GPDetachNodesCommand).
# 把每个选中节点从其宿主上卸下，并让它在屏幕上精确停在原处（命令会烘焙推导变换 —— 见
# GPDetachNodesCommand）。
# Returns false when nothing in the selection was mounted, so the action is silently inert rather
# than pushing a meaningless undo step.
# 选择集中没有任何挂载项时返回 false，使该动作静默无效，而不是压入一个无意义的撤销步。
func gpRequestDetachSelected() -> bool:
	if gpHost.gpGraph == null or gpHost.gpSelection.is_empty():
		return false
	if not gpHost.gpActions.gpDetachNodes(gpHost.gpSelection, gpHost.gpDefLookupCallable()):
		return false
	gpHost.queue_redraw()
	return true


# Commit a finished mount drag as ONE undo step. The caller must have RESTORED the pre-drag tuple
# first (see GPEditService.gpSetMount()'s ⚠️ note).
# 把一次完成的挂载拖拽提交为**一步**撤销。调用方必须先**恢复**拖拽前的元组
# （见 GPEditService.gpSetMount() 的 ⚠️ 说明）。
func gpRequestSetMount(gpNodeIds: Array[String], gpTargets: Array[Dictionary]) -> bool:
	if gpHost.gpGraph == null:
		return false
	var gpOk: bool = gpHost.gpActions.gpSetMount(gpNodeIds, gpTargets)
	if gpOk:
		gpHost.queue_redraw()
	return gpOk


# Place one symbol instance (palette click). Returns the new node id, "" on failure.
# 放置一个图元实例（调色板点击）。返回新节点 id，失败返回 ""。
# The definition lookup is handed down so the command can instantiate the host's built-in parts
# (nozzles / manhole) in the same undo step (规划 §16).
# 定义查找器向下传递，使命令能在同一个撤销步内实例化宿主的自带部件（管口 / 人孔，规划 §16）。
func gpRequestPlaceNode(gpSymbolId: String, gpWorld: Vector2) -> String:
	return gpHost.gpActions.gpPlaceNode(gpSymbolId, gpWorld, "", gpHost.gpDefLookupCallable())

# Copy every selected node to a small offset, keeping its attributes and orientation.
# 把所有选中节点复制到小幅偏移处，保留其属性与朝向。
func gpRequestDuplicateSelected() -> void:
	if gpHost.gpGraph == null or gpHost.gpSelection.is_empty():
		return
	var gpCopies: Array[String] = gpHost.gpActions.gpDuplicateSelection(gpHost.gpSelection)
	if gpCopies.is_empty():
		return
	# Select the copies, not the originals: the natural next action is to drag them into place.
	# 选中副本而非原件：下一步自然是把它们拖到目标位置。
	gpSetSelection(gpCopies)
	gpHost.queue_redraw()

# Drop selection entries that no longer resolve in the graph. Without this, undoing a place
# leaves gpSelection pointing at a node that is gone, and the inspector edits a ghost.
# 剔除图中已无法解析的选择项。否则撤销一次放置后，gpSelection 仍指向已消失的节点，
# 属性面板会去编辑一个幽灵对象。
func gpPruneSelection() -> void:
	if gpHost.gpGraph == null:
		return
	var gpKeep: Array[String] = []
	for gpId in gpHost.gpSelection:
		if gpHost.gpGraph.gpGetNode(gpId) != null:
			gpKeep.append(gpId)
	var gpShapeKeep: Array[int] = []
	for gpI in gpHost.gpShapeSel:
		if gpI >= 0 and gpI < gpHost.gpGraph.gpShapes.size():
			gpShapeKeep.append(gpI)
	# an edge can be deleted by undo too; drop the selection entry so edge grips and the
	# tag editor never point at a ghost edge.
	# 边也可能被撤销删除；剔除该选择项，使边抓取点与位号编辑器永不指向幽灵边。
	var gpEdgeKeep: Array[String] = []
	for gpEid in gpHost.gpEdgeSel:
		if gpHost.gpGraph.gpGetEdge(gpEid) != null:
			gpEdgeKeep.append(gpEid)
	if gpKeep.size() == gpHost.gpSelection.size() and gpShapeKeep.size() == gpHost.gpShapeSel.size() and gpEdgeKeep.size() == gpHost.gpEdgeSel.size():
		return
	gpHost.gpShapeSel = gpShapeKeep
	gpHost.gpEdgeSel = gpEdgeKeep
	gpSetSelection(gpKeep)

# Whether a redo step is available.
# 是否存在可重做步骤。
func gpCanRedo() -> bool:
	return gpHost.gpActions.gpCanRedo()

# Whether an undo step is available (for enabling host menu items).
# 是否存在可撤销步骤（供宿主菜单项启用与否）。
func gpCanUndo() -> bool:
	return gpHost.gpActions.gpCanUndo()

# Redo the most recently undone edit (Ctrl+Y / Ctrl+Shift+Z). Returns false when empty.
# 重做最近被撤销的编辑（Ctrl+Y / Ctrl+Shift+Z）。无可重做时返回 false。
func gpRedo() -> bool:
	if not gpHost.gpActions.gpRedo():
		return false
	gpPruneSelection()
	return true

# Undo the most recent user edit (Ctrl+Z). Returns false when there is nothing to undo.
# 撤销最近一次用户编辑（Ctrl+Z）。无可撤销时返回 false。
# Undo can remove the very things the selection still points at (undoing a place drops a
# node; undoing a shape insert shifts every later index). Pruning here means every caller
# — shortcut, menu, or a future script — gets a consistent selection for free.
# 撤销可能移除选择集仍指向的对象（撤销放置会移除节点；撤销插入图形会让后续下标整体前移）。
# 在此修剪，意味着所有调用方——快捷键、菜单或今后的脚本——都自动获得一致的选择集。
func gpUndo() -> bool:
	if not gpHost.gpActions.gpUndo():
		return false
	gpPruneSelection()
	return true

# Delete every selected node (with its attached edges), shape and selected edge in ONE undo step.
# 删除所有选中节点（及其关联边）、图形与选中边，合并为「一个撤销步」。
func gpRequestDeleteSelected() -> void:
	if gpHost.gpGraph == null:
		return
	var gpNodes: Array[String] = gpHost.gpSelection.duplicate()
	var gpShapes: Array[int] = gpHost.gpShapeSel.duplicate()
	# Edges whose endpoints are being deleted are already removed by the node half of the command,
	# so feeding them in again would double-delete and double-insert on undo. Keep only the edges
	# that survive the node deletion.
	# 端点正被删除的边已由命令的节点部分一并移除，重复纳入会双重删除并在撤销时重复插入。只保留
	# 节点删除后仍存留的边。
	var gpEdges: Array[String] = []
	for gpEid in gpHost.gpEdgeSel:
		var gpE: GPPIDEdge = gpHost.gpGraph.gpGetEdge(gpEid)
		if gpE == null:
			continue
		var gpF: String = str(gpE.gpFromRef.get("node_id", ""))
		var gpT: String = str(gpE.gpToRef.get("node_id", ""))
		if gpNodes.has(gpF) or gpNodes.has(gpT):
			continue
		gpEdges.append(gpEid)
	if gpNodes.is_empty() and gpShapes.is_empty() and gpEdges.is_empty():
		return
	# Nodes, shapes AND edges go in one request, so a mixed delete stays ONE undo step.
	# 节点、图形与边同在一次请求中提交，故混合删除仍是一个撤销步。
	if not gpHost.gpActions.gpDeleteSelection(gpNodes, gpShapes, gpEdges,
			gpHost.gpDefLookupCallable()):
		return
	gpHost.gpShapeSel.clear()
	gpSetSelection([])
	gpSetEdgeSelection([])
	gpHost.queue_redraw()

# selection, so setting it clears the others and refreshes the inspector via the selection event.
# 并经选择事件刷新属性面板。
func gpSetEdgeSelection(gpIds: Array[String]) -> void:
	gpHost.gpEdgeSel = gpIds.duplicate()
	gpHost.gpSelection = []
	gpHost.gpShapeSel = []
	gpHost.gpConnectFrom = ""
	gpHost.queue_redraw()
	# The inspector listens on the node-selection event; clearing it hides a stale node panel.
	# 属性面板监听节点选择事件；清空它可隐藏残留的节点面板。
	# Emit the already-typed gpSelection (Array[String]); passing a bare [] would make Godot
	# refuse to coerce an untyped Array into the signal's Array[String] parameter.
	# 发射已具类型的 gpSelection（Array[String]）；若直接传裸 []，Godot 会拒绝把无类型 Array
	# 提升为信号的 Array[String] 参数而报转换错误。
	gpHost.gpEvents.gpSelectionChanged.emit(gpHost.gpSelection)
	gpHost.gpEmitStatus()

# Select every node on the sheet (Ctrl/Cmd+A).
# 选中图纸上的所有节点（Ctrl/Cmd+A）。
func gpRequestSelectAll() -> void:
	if gpHost.gpGraph == null:
		return
	var gpAll: Array[String] = []
	for gpN in gpHost.gpGraph.gpNodes:
		gpAll.append(gpN.gpInstanceId)
	gpSetSelection(gpAll)

# ============================ selection ============================
# ============================ 选择 ============================
# Replace the selection set and keep gpSelectedId (the primary entry) in sync.
# 替换选择集，并同步 gpSelectedId（主选项）。
func gpSetSelection(gpIds: Array[String]) -> void:
	gpHost.gpSelection = gpIds.duplicate()
	gpHost.gpSelectedId = gpHost.gpSelection[0] if not gpHost.gpSelection.is_empty() else ""
	gpHost.queue_redraw()
	# the status snapshot, where main_window diffed the "selection" string to decide whether
	# to refresh the inspector. Subscribers now react to this directly.
	# 选择重新成为一等事件。过去它被塞进状态快照，由 main_window 比对 "selection"
	# 字符串来决定是否刷新属性面板；订阅者现在直接响应本事件。
	gpHost.gpEvents.gpSelectionChanged.emit(gpHost.gpSelection)
	gpHost.gpEmitStatus()
