# ============================================================================
# GPCanvasContextMenu — 右键上下文菜单
# Right-click context menu .
#
# 持有右键菜单的「行为」：命中判定、菜单构建、动作分发；菜单的状态（当前命中节点 id、
# 命中顶点下标）也随行为一起内聚到本类，画布仅保留一份委托引用 _gpCtx。
# Holds the context-menu BEHAVIOR: hit-test, menu build, action dispatch. The menu STATE
# (current hit node id, hit vertex index) co-locates with the behavior here; the canvas keeps
# only a delegate reference `_gpCtx`.
#
# 通过 gpCv（GPCanvas2D 实例）读写画布实时状态与瞬态拖拽字段，画布侧保留薄转发，所有外部
# 调用点（main_window.gd / center_area.gd）保持不变。
# Reads/writes live canvas state and transient fields via gpCv; the canvas keeps thin
# call-throughs so all external call sites (main_window.gd / center_area.gd) stay unchanged.
# ============================================================================

class_name GPCanvasContextMenu
extends RefCounted

const GPMode = GPCanvasInteractState.GPMode

# Context-menu action ids. Ids (not positions) keep the handlers correct when optional
# items are inserted, because PopupMenu ids do not shift the way indices do.
# 右键菜单动作 id。用 id（而非位置）可在插入可选项后仍保持处理正确，
# 因为 PopupMenu 的 id 不会像下标那样位移。
const GP_CTX_EDIT: int = 0
const GP_CTX_DUPLICATE: int = 1
const GP_CTX_DELETE: int = 2
const GP_CTX_SELECT_ALL: int = 3
const GP_CTX_DESELECT: int = 4
const GP_CTX_CONNECT: int = 5
const GP_CTX_MAKE_SYMBOL: int = 6
# Vertex-only actions on the selected annotation polyline (only offered when the cursor sits on
# a vertex / handle grip of a single selected polyline). Pulled out of the running 0..7 range so
# they cannot collide with the shape/node actions above.
# 仅针对折线顶点的操作（仅当光标位于「单选折线」的顶点 / 手柄抓取点上时提供）。取值避开 0..7，
# 避免与上面的图形/图元动作冲突。
const GP_CTX_SMOOTH_VERTEX: int = 12
const GP_CTX_DELETE_VERTEX: int = 13
const GP_CTX_CORNER_VERTEX: int = 14

# Edge-targeted actions (shown when a single edge is hit or selected).
# 边级操作（单击命中或选中单条边时显示）。
const GP_CTX_DELETE_EDGE: int = 20
const GP_CTX_SET_PROCESS: int = 21
const GP_CTX_SET_UTILITY: int = 22
const GP_CTX_SET_SIGNAL: int = 23
const GP_CTX_RESNAP_ENDS: int = 24
const GP_CTX_CLEAR_VERTICES: int = 25
# Sheet-wide action (shown whenever the graph has edges).
# 全图纸操作（图内含边时显示）。
const GP_CTX_RENUMBER: int = 26
const GP_CTX_AUTO_CONNECT: int = 27
# Bump-anchor action (shown when right-click lands on an existing orange bump anchor).
# 鼓包锚点操作（右键命中既有橙色锚点时显示）。
const GP_CTX_DELETE_BUMP: int = 30
# Add-anchor action (shown when right-click lands on an EMPTY segment, so creating the orange
# corner goes through the menu rather than a silent direct insert). / 增加锚点操作（右键落在空白
# 线段时显示，使橙色角点经菜单创建而非静默直接插入）。
const GP_CTX_ADD_ANCHOR: int = 31
# Drop-a-symbol-on-a-line actions: let the pipe go around the new symbol, or split into two that
# feed through it. Id space kept clear of the edge block above.
# 图元落到连线上的两个动作：让管线绕开新图元 / 拆成两根穿过它。id 空间与上方边级块错开。
const GP_CTX_DROP_REROUTE: int = 32
const GP_CTX_DROP_SPLIT: int = 33

# Canvas this menu acts on (state owner).
# 本菜单作用的画布（状态持有者）。
var gpCv: GPCanvas2D

# Node id the right-click menu was opened on ("" when the click missed everything).
# 右键菜单打开时所处的节点 id（未命中任何节点时为空）。
var _gpCtxHit: String = ""

# Edge id the right-click menu was opened on ("" when no edge was hit / selected).
# 右键菜单打开时所处的边 id（未命中或选中任何边时为空）。
var _gpCtxEdge: String = ""

# Vertex index the right-click menu was opened on, for a single selected annotation polyline
# (only meaningful when the cursor hit one of its vertex / handle grips). -1 = none.
# 右键菜单打开时所处的「单选注释折线」顶点下标（仅当光标命中其顶点 / 手柄抓取点时才有意义）。-1 = 无。
var _gpCtxVertex: int = -1

# Bump anchor the right-click menu was opened on ("" / -1 when not on a bump). Cleared at the top of
# gpOnRightDown() so a non-bump right-click never leaves a stale target. / 右键菜单打开时所处的鼓包锚点
#（非锚点时为空 / -1）。在 gpOnRightDown() 顶部清零，非锚点右键绝不残留旧目标。
var _gpCtxBumpEid: String = ""
var _gpCtxBumpAi: int = -1
# Segment world position where right-click landed (so "增加锚点" can create the orange corner there).
# Cleared at the top of gpOnRightDown() so a non-segment right-click never leaves a stale target.
# 右键落点的线段世界坐标（供「增加锚点」在该处生成橙色角点）。在 gpOnRightDown() 顶部清零，
# 非线段右键绝不残留旧目标。
var _gpCtxBumpWorld: Vector2 = Vector2.ZERO

# Symbol + edge of a pending "dropped onto a line" choice. Set while the popup is open so the
# handler knows what to act on; cleared once the choice is dispatched.
# 待处理的「落到连线上」选择所属的图元与边。弹窗期间记录供处理器定位；分派后即清空。
var _gpDropSymNid: String = ""
var _gpDropEdgeId: String = ""


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# ============================ 右键菜单 ============================
# Right click: make the click target the selection, then open the menu.
# 右键：让被点击的对象成为选择，随后打开菜单。
# Selecting first is what makes "delete" unambiguous — the user sees exactly what the menu
# is about to act on.
# 先选中是让「删除」无歧义的原因 —— 用户能明确看到菜单将要作用于什么。
func gpOnRightDown(gpScreen: Vector2) -> void:
	var gpWorld: Vector2 = gpCv.gpWorldFromScreen(gpScreen)
	_gpCtxVertex = -1
	_gpCtxEdge = ""
	_gpCtxBumpEid = ""
	_gpCtxBumpAi = -1
	_gpCtxBumpWorld = Vector2.ZERO
	var gpHit: String = gpCv.gpHitTest(gpWorld)
	if gpHit != "":
		if not gpCv.gpSelection.has(gpHit):
			gpCv.gpSetSelection([gpHit])
		_gpCtxHit = gpHit
		gpShowContextMenu(gpHit)
		return
	# No symbol hit: try an annotation shape instead.
	# 未命中图元：改试注释图形。
	var gpSh: int = gpCv.gpHitShape(gpWorld)
	if gpSh >= 0:
		if not gpCv.gpShapeSel.has(gpSh):
			gpCv.gpShapeSel = [gpSh]
			gpCv.gpSetSelection([])
 # Remember which vertex of a single selected polyline was right-clicked so the menu can offer
 # vertex-only actions (smooth / corner / delete this vertex). Right-click on the empty inside
 # of the polyline leaves _gpCtxVertex = -1 (the shape-level menu shows instead).
 # 记住「单选折线」被右键点击的是哪个顶点，使菜单能提供仅针对顶点的操作（平滑 / 拐角 / 删除此顶点）。
 # 右键点在折线内部空白处时 _gpCtxVertex 保持 -1（显示图形级菜单）。
		var gpVGrip: Dictionary = gpCv.gpAnno.gpHitPolylineVertexGrip(gpWorld)
		if not gpVGrip.is_empty():
			_gpCtxVertex = int(gpVGrip["gi"])
		_gpCtxHit = ""
		gpShowContextMenu("")
		return
	# Edge hit: RIGHT-CLICK on any segment creates an ORANGE bump anchor there (scheme b). The edge
	# context menu is intentionally suppressed on the edge body — it remains reachable by right-clicking
	# empty space with the edge already selected. / 命中边：在任意线段右键「生成橙色锚点」（方案 b）。
	# 右键菜单在边线上被有意抑制 —— 仍可在「先选中边、再右键空白处」时呼出。
	var gpEid: String = gpCv.gpHitEdge(gpWorld)
	if gpEid != "":
		if not gpCv.gpEdgeSel.has(gpEid):
			gpCv.gpSetEdgeSelection([gpEid])
 # Right-click on an EXISTING orange bump anchor -> open a delete-anchor menu (do NOT create a
 # new one). / 右键命中既有橙色锚点 -> 弹出「删除锚点」菜单（不新建）。
		var gpExisting: Dictionary = gpCv.gpEdgeGrips.gpHitBump(gpWorld, gpEid)
		if not gpExisting.is_empty():
			_gpCtxBumpEid = gpEid
			_gpCtxBumpAi = int(gpExisting["anchor"])
			gpShowContextMenu("")
			return
 # Empty segment -> open a menu with "增加锚点" (the orange corner is created only when that
 # item is chosen, so adding an anchor goes through an explicit action instead of a silent
 # insert). Remember the edge id and the click world position for the menu handler.
 # 空白线段 -> 弹出含「增加锚点」的菜单（橙色角点仅在选中该项时创建，使加锚点成为显式动作
 # 而非静默插入）。记下边 id 与落点，供菜单处理器调用 gpStartBump()。
		_gpCtxEdge = gpEid
		_gpCtxBumpWorld = gpWorld
		_gpCtxHit = ""
		gpShowContextMenu("")
		return
	# Empty area: open the menu against the current selection (no new hit target).
	# 空白处：基于当前选择打开菜单（无新命中目标）。
	_gpCtxHit = ""
	gpShowContextMenu(_gpCtxHit)


# Build and pop up the context menu at the cursor.
# 在光标处构建并弹出上下文菜单。
func gpShowContextMenu(gpNodeHit: String) -> void:
	_gpCtxHit = gpNodeHit
	var gpMenu: PopupMenu = PopupMenu.new()
	_gpBuildMenuItems(gpMenu, gpNodeHit)
	_gpApplyMenuStates(gpMenu, gpNodeHit)
	gpMenu.id_pressed.connect(gpOnContext)
	gpCv.add_child(gpMenu)
	# Godot 4's PopupMenu/Popup exposes NO popup_at_cursor; the only positioning entry is popup, and
	# when popups are NOT embedded (embed_subwindows=false, the default) its .position is interpreted in
	# GLOBAL SCREEN coordinates. Positioning is centralized in GPPopupHelper.gpPopupAtMouse (single source
	# sites). Menu top-left anchors at the pointer and opens down-right (the convention). (2,2) nudges
	# the cursor off.
	# Godot 4 的 PopupMenu/Popup 没有 popup_at_cursor，仅 popup 可定位；「非嵌入」（默认值）时其
	# .position 取「全局屏幕」坐标。菜单定位统一交由 GPPopupHelper.gpPopupAtMouse()（窗口屏幕坐标公式的
	# 单一事实来源）。菜单左上角锚定在指针、向右下展开（符合惯例）。(2,2) 微调让光标落在菜单角外侧。
	GPPopupHelper.gpPopupAtMouse(gpMenu, gpCv)
	# Free the menu after it closes; a leaked PopupMenu keeps its parent alive.
	# 关闭后释放菜单；泄漏的 PopupMenu 会让其父节点无法释放。
	gpMenu.popup_hide.connect(gpMenu.queue_free)


# Append every applicable item, in a FIXED order: target-specific items first, then the
# sheet-wide tail. Which of them end up DISABLED is decided afterwards by _gpApplyMenuStates().
# 按**固定顺序**追加所有适用条目：先目标专属项，再全图纸尾部项。
# 其中哪些最终被**禁用**，由随后的 _gpApplyMenuStates() 决定。
func _gpBuildMenuItems(gpMenu: PopupMenu, gpNodeHit: String) -> void:
	# Promote selected annotation shapes into a real symbol (only meaningful when shapes are picked).
	# 把选中的注释图形提升为真正图元（仅当选中图形时才有意义）。
	if not gpCv.gpShapeSel.is_empty():
		gpMenu.add_item(I18n.gpTr("canvas.ctx_make_symbol"), GP_CTX_MAKE_SYMBOL)
	# Vertex-only actions on the right-clicked vertex of a single selected polyline (Bézier handles).
	# 对「单选折线」被右键顶点的顶点级操作（贝塞尔手柄）。镜像符号编辑器：平滑 = 拉手柄、拐角 = 收手柄。
	if _gpCtxVertex >= 0:
		var gpSelShape: GPShape = gpCv.gpAnno.gpSingleSelectedShape()
		if gpSelShape != null and gpCv.gpAnno.gpVertexHasHandles(gpSelShape, _gpCtxVertex):
			gpMenu.add_item(I18n.gpTr("canvas.ctx_corner_vertex"), GP_CTX_CORNER_VERTEX)
		else:
			gpMenu.add_item(I18n.gpTr("canvas.ctx_smooth_vertex"), GP_CTX_SMOOTH_VERTEX)
		gpMenu.add_item(I18n.gpTr("canvas.ctx_delete_vertex"), GP_CTX_DELETE_VERTEX)
	# Node-targeted actions need a node hit or an existing node selection.
	# 针对图元的动作需要命中图元或已有图元选择。
	var gpNodeCtx: bool = (gpNodeHit != "" or not gpCv.gpSelection.is_empty())
	if gpNodeCtx:
		gpMenu.add_item(I18n.gpTr("canvas.ctx_edit_symbol"), GP_CTX_EDIT)
		gpMenu.add_item(I18n.gpTr("canvas.ctx_duplicate"), GP_CTX_DUPLICATE)
	# Delete applies to either shapes or nodes.
	# 删除可同时作用于图形或图元。
	var gpCanDelete: bool = gpNodeCtx or (not gpCv.gpShapeSel.is_empty())
	if gpCanDelete:
		gpMenu.add_item(I18n.gpTr("canvas.ctx_delete"), GP_CTX_DELETE)
	# Bump-anchor target: offer delete. Shown INSTEAD of the full edge menu (suppressed below) so the
	# user is not offered both "delete anchor" and "delete connection" at once.
	# 鼓包锚点目标：提供删除。与整条边菜单互斥（下方已压制），避免同时出现「删锚点」与「删连线」。
	if _gpCtxBumpAi >= 0:
		gpMenu.add_item(I18n.gpTr("canvas.ctx_delete_bump"), GP_CTX_DELETE_BUMP)
	# Add-anchor target: right-click landed on an EMPTY segment (not on an existing anchor). Offer
	# "增加锚点" so creating the orange corner goes through the menu. Shown ABOVE the edge-level items.
	# 增加锚点目标：右键落在空白线段（非既有锚点）。提供「增加锚点」使橙色角点经菜单创建，位于边级项上方。
	if _gpCtxBumpWorld != Vector2.ZERO:
		gpMenu.add_item(I18n.gpTr("canvas.ctx_add_anchor"), GP_CTX_ADD_ANCHOR)
	# Edge-targeted actions: a single edge hit or already selected.
	# 边级操作：单击命中或已选中的单条边。
	var gpEdgeCtx: bool = (_gpCtxEdge != "" or gpCv.gpEdgeSel.size() == 1) and _gpCtxBumpAi < 0
	if gpEdgeCtx:
		var gpEid: String = _gpCtxEdge if _gpCtxEdge != "" else gpCv.gpEdgeSel[0]
		_gpCtxEdge = gpEid
		gpMenu.add_item(I18n.gpTr("canvas.ctx_delete_edge"), GP_CTX_DELETE_EDGE)
		gpMenu.add_item(I18n.gpTr("canvas.ctx_set_process"), GP_CTX_SET_PROCESS)
		gpMenu.add_item(I18n.gpTr("canvas.ctx_set_utility"), GP_CTX_SET_UTILITY)
		gpMenu.add_item(I18n.gpTr("canvas.ctx_set_signal"), GP_CTX_SET_SIGNAL)
		gpMenu.add_item(I18n.gpTr("canvas.ctx_resnap_ends"), GP_CTX_RESNAP_ENDS)
		gpMenu.add_item(I18n.gpTr("canvas.ctx_clear_vertices"), GP_CTX_CLEAR_VERTICES)
		gpMenu.add_separator()
	gpMenu.add_item(I18n.gpTr("canvas.ctx_select_all"), GP_CTX_SELECT_ALL)
	gpMenu.add_item(I18n.gpTr("canvas.ctx_deselect"), GP_CTX_DESELECT)
	gpMenu.add_separator()
	gpMenu.add_check_item(I18n.gpTr("canvas.ctx_connect_mode"), GP_CTX_CONNECT)
	# Sheet-wide renumber (useful from anywhere there are edges).
	# 全图纸重新编号（只要有边即可，随处可用）。
	if gpCv.gpGraph != null and not gpCv.gpGraph.gpEdges.is_empty():
		gpMenu.add_item(I18n.gpTr("canvas.ctx_renumber"), GP_CTX_RENUMBER)
	# Auto-connect the two PICKED endpoints with an obstacle-avoiding orthogonal route.
	# 用绕开障碍的正交路径，自动连接「两个已拾取的端点」。
	if gpCv.gpPortPick.size() >= 2:
		gpMenu.add_item(I18n.gpTr("canvas.ctx_auto_connect"), GP_CTX_AUTO_CONNECT)


# Disable / check the stateful items. Disabling goes through get_item_index (by ID), because
# positional disabling breaks as soon as a conditional item is inserted above; items that were
# not added report index -1 and are skipped.
# 设置有状态条目的禁用 / 勾选。禁用一律**按 id** 经 get_item_index 反查位置 —— 一旦上方插入了
# 条件项，按位置禁用就会错位；未添加的条目返回下标 -1，直接跳过。
func _gpApplyMenuStates(gpMenu: PopupMenu, gpNodeHit: String) -> void:
	if gpMenu.get_item_index(GP_CTX_EDIT) >= 0:
		gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_EDIT), gpNodeHit == "")
	if gpMenu.get_item_index(GP_CTX_DUPLICATE) >= 0:
		gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DUPLICATE), gpCv.gpSelection.is_empty())
	if gpMenu.get_item_index(GP_CTX_DELETE) >= 0:
		gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DELETE), gpCv.gpSelection.is_empty() and gpCv.gpShapeSel.is_empty())
	gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DESELECT), gpCv.gpSelection.is_empty() and gpCv.gpShapeSel.is_empty())
	gpMenu.set_item_checked(gpMenu.get_item_index(GP_CTX_CONNECT), gpCv.gpMode == GPMode.GP_CONNECT)


# Dispatch a context-menu action.
# 分发右键菜单动作。
func gpOnContext(gpId: int) -> void:
	match gpId:
		GP_CTX_MAKE_SYMBOL:
			gpCv.gpAnno.gpMakeSymbolFromShapes()
		GP_CTX_EDIT:
			var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(_gpCtxHit) if gpCv.gpGraph != null else null
			if gpN != null:
				gpCv.gpSymbolEditRequested.emit(gpN.gpSymbolId)
		GP_CTX_DUPLICATE:
			gpCv.gpRequestDuplicateSelected()
		GP_CTX_DELETE:
			gpCv.gpRequestDeleteSelected()
		GP_CTX_SMOOTH_VERTEX:
 # Pull handles out of the right-clicked vertex (make it smooth). Only valid when a single
 # polyline is selected and that vertex was the right-click target.
 # 拉出被右键顶点的两侧手柄（转为平滑）。仅当单选折线且该顶点正是右键目标时有效。
			var gpSmoothShape: GPShape = gpCv.gpAnno.gpSingleSelectedShape()
			if gpSmoothShape != null and _gpCtxVertex >= 0:
				gpCv.gpAnno.gpPullHandles(gpSmoothShape, _gpCtxVertex)
			_gpCtxVertex = -1
		GP_CTX_CORNER_VERTEX:
 # Collapse the handles of the right-clicked vertex back onto it (make it a corner).
 # 收起被右键顶点的两侧手柄（转为拐角）。
			var gpCornerShape: GPShape = gpCv.gpAnno.gpSingleSelectedShape()
			if gpCornerShape != null and _gpCtxVertex >= 0:
				gpCv.gpAnno.gpCollapseHandles(gpCornerShape, _gpCtxVertex)
			_gpCtxVertex = -1
		GP_CTX_DELETE_VERTEX:
 # Remove just the right-clicked vertex, keeping the rest of the polyline connected.
 # 仅删除被右键的顶点，折线其余部分保持连接。
			var gpDelShape: GPShape = gpCv.gpAnno.gpSingleSelectedShape()
			if gpDelShape != null and _gpCtxVertex >= 0:
				gpCv.gpAnno.gpRemoveVertex(gpDelShape, _gpCtxVertex)
			_gpCtxVertex = -1
		GP_CTX_SELECT_ALL:
			gpCv.gpRequestSelectAll()
		GP_CTX_DESELECT:
			gpCv.gpSetSelection([])
			gpCv.gpShapeSel.clear()
			gpCv.queue_redraw()
		GP_CTX_CONNECT:
			gpCv.gpSetMode(GPMode.GP_SELECT if gpCv.gpMode == GPMode.GP_CONNECT else GPMode.GP_CONNECT)
			gpCv.gpConnectFrom = ""
			gpCv.queue_redraw()
		GP_CTX_DELETE_EDGE:
			gpCv.gpActions.gpDeleteEdges([_gpCtxEdge])
			gpCv.gpEdgeSel.clear()
			gpCv.queue_redraw()
		GP_CTX_SET_PROCESS:
			gpCv.gpActions.gpSetEdgeKind(_gpCtxEdge, GPPIDEdge.GP_PROCESS)
			gpCv.queue_redraw()
		GP_CTX_SET_UTILITY:
			gpCv.gpActions.gpSetEdgeKind(_gpCtxEdge, GPPIDEdge.GP_UTILITY)
			gpCv.queue_redraw()
		GP_CTX_SET_SIGNAL:
			gpCv.gpActions.gpSetEdgeKind(_gpCtxEdge, GPPIDEdge.GP_SIGNAL, "ELECTRIC")
			gpCv.queue_redraw()
		GP_CTX_RESNAP_ENDS:
			gpCv.gpActions.gpSnapEdgeEnds(_gpCtxEdge, gpCv.gpDefLookupCallable())
			gpCv.queue_redraw()
		GP_CTX_CLEAR_VERTICES:
			gpCv.gpActions.gpSetEdgeRouting(_gpCtxEdge, [])
			gpCv.queue_redraw()
		GP_CTX_RENUMBER:
			gpCv.gpActions.gpRenumberEdges()
			gpCv.queue_redraw()
		GP_CTX_AUTO_CONNECT:
			gpCv.gpRequestAutoConnect()
			gpCv.queue_redraw()
		GP_CTX_DELETE_BUMP:
			if _gpCtxBumpEid != "" and _gpCtxBumpAi >= 0:
				gpCv.gpEdgeGrips.gpDeleteBump(_gpCtxBumpEid, _gpCtxBumpAi)
				_gpCtxBumpEid = ""
				_gpCtxBumpAi = -1
			gpCv.queue_redraw()
		GP_CTX_ADD_ANCHOR:
 # Create the orange corner at the remembered right-click position on the remembered edge.
 # 在记下的边、记下的右键落点处生成橙色角点。
			if _gpCtxEdge != "" and _gpCtxBumpWorld != Vector2.ZERO:
				gpCv.gpEdgeGrips.gpStartBump(_gpCtxEdge, _gpCtxBumpWorld)
				_gpCtxBumpWorld = Vector2.ZERO
				_gpCtxEdge = ""
			gpCv.queue_redraw()


# ============================ 放到连线上 ============================
# ==================== Dropped-on-a-line choice ====================
# GPPlaceTool calls this after a placement lands on an existing pipe. Two outcomes are offered:
# route the pipe AROUND the new symbol, or SPLIT it into two feeding through the symbol's ports.
# GPPlaceTool 在「放置落点压到既有管线」后调用本函数。提供两个结果：让管线绕开新图元，
# 或把它拆成两根经图元端口穿过。
# [param gpSymNid] instance id of the just-placed symbol / 刚放置图元的实例 id
# [param gpEdgeId] id of the pipe running under it / 从其下方穿过的那条管线 id
func gpPromptDropOnEdge(gpSymNid: String, gpEdgeId: String) -> void:
	_gpDropSymNid = gpSymNid
	_gpDropEdgeId = gpEdgeId
	var gpM: PopupMenu = PopupMenu.new()
	gpM.add_item(I18n.gpTr("canvas.ctx_drop_reroute"), GP_CTX_DROP_REROUTE)
	gpM.add_item(I18n.gpTr("canvas.ctx_drop_split"), GP_CTX_DROP_SPLIT)
	gpM.id_pressed.connect(_gpOnDropContext)
	gpCv.add_child(gpM)
	# The cursor is at the drop point right now, so anchor the menu at the pointer.
	# 此刻光标正位于落点，故把菜单锚定在指针处。
	GPPopupHelper.gpPopupAtMouse(gpM, gpCv)
	gpM.popup_hide.connect(gpM.queue_free)


# Dispatch the drop choice. Splitting can be refused (symbol has <2 ports) -> then explain why.
# 分派「落到连线」的选择。拆分可能被拒（图元端口 <2）——此时说明原因。
func _gpOnDropContext(gpId: int) -> void:
	if gpId == GP_CTX_DROP_REROUTE:
		gpCv.gpEdgeGrips.gpRerouteAround(_gpDropEdgeId, _gpDropSymNid)
	elif gpId == GP_CTX_DROP_SPLIT:
		if not gpCv.gpEdgeGrips.gpSplitThroughSymbol(_gpDropEdgeId, _gpDropSymNid):
			_gpRefuseDrop()
	gpCv.queue_redraw()
	_gpDropSymNid = ""
	_gpDropEdgeId = ""


# A symbol with fewer than two ports cannot be spliced into a pipe — tell the user to add ports.
# 端口少于两个的图元无法串进管线 —— 提示用户去增加端点。
func _gpRefuseDrop() -> void:
	var gpDlg: AcceptDialog = AcceptDialog.new()
	gpDlg.title = I18n.gpTr("canvas.ctx_drop_title")
	gpDlg.dialog_text = I18n.gpTr("canvas.ctx_drop_needs_ports")
	gpCv.add_child(gpDlg)
	gpDlg.popup_centered()
	# Free on either outcome, else the dialog leaks and keeps the canvas alive.
	# 两种结局都释放，否则对话框泄漏并使画布无法释放。
	gpDlg.confirmed.connect(gpDlg.queue_free)
	gpDlg.popup_hide.connect(gpDlg.queue_free)
