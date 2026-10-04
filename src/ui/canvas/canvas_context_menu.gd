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
# P2 attach / detach (规划 §15.3). Space 28/29 was still free between the sheet-wide block and the
# bump-anchor block, so the fixed ids stay contiguous and nothing has to be renumbered.
# P2 挂载 / 卸载（规划 §15.3）。28/29 是「全图纸块」与「鼓包锚点块」之间仍空着的号段，
# 故固定 id 保持连续、无需重新编号。
const GP_CTX_ATTACH: int = 28
const GP_CTX_DETACH: int = 29
# One action id per candidate part type in the dynamic "添加附件 ▶" submenu. Parked far above every
# other block so a dynamically built list can never collide with a fixed id, however long it grows.
# 「添加附件 ▶」动态子菜单中每种候选部件各占一个动作 id。取值远高于其它号段，
# 使动态构建的列表无论多长都不会与固定 id 撞号。
const GP_CTX_ATTACH_BASE: int = 100
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

# P2 attach submenu state. The host the submenu was built for, plus one entry per candidate part
# type (symbol id + its free anchor names, computed when the menu opened).
# P2 附件子菜单状态。子菜单所针对的宿主，以及每种候选部件一项（图元 id + 菜单打开时算出的空闲锚点名）。
# The free-anchor list is snapshotted with the menu deliberately: the graph cannot change while a
# modal popup is open, and snapshotting is what lets the disabled state and the eventual action
# agree on the SAME anchor set.
# 空闲锚点表是**随菜单一起**快照的：模态弹窗打开期间图不会变，而快照正是「置灰状态」与
# 「最终动作」在**同一套**锚点上达成一致的原因。
var _gpAttachHost: String = ""
var _gpAttachChoices: Array[Dictionary] = []
# The right-click POSITION, snapshotted with the menu. The attach choice uses it to pick the
# free anchor NEAREST to where the user pointed, so "right-click the top of the vessel" adds
# the nozzle at the top facing up instead of at the first declared anchor.
# 右键**位置**，随菜单一起快照。附件选择用它挑距用户指向**最近**的空闲锚点，使「右键点容器
# 上部」添加的管嘴落在上部朝上，而不是落在声明顺序的第一个锚点上。
var _gpAttachWorld: Vector2 = Vector2.ZERO


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
	_gpAttachWorld = gpWorld
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
		# Attach / detach sit with the node-targeted items because both act on the node selection.
		# 挂载 / 卸载与「作用于节点选择」的条目同处，因为两者都作用于节点选择。
		_gpBuildAttachSubmenu(gpMenu, gpNodeHit)
		if _gpDetachTargetCount(gpNodeHit) > 0:
			gpMenu.add_item(I18n.gpTr("canvas.ctx_detach"), GP_CTX_DETACH)
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
		GP_CTX_DETACH:
 # Take the selected parts off their hosts, keeping them exactly where they are on screen
 # (GPDetachNodesCommand bakes the derived transform).
 # 把选中的部件从其宿主上卸下，并让它们在屏幕上精确停在原处（GPDetachNodesCommand 会烘焙
 # 推导变换）。
			gpCv.gpRequestDetachSelected()
			gpCv.queue_redraw()
		_:
 # The dynamic "添加附件" items live at GP_CTX_ATTACH_BASE + index, so they must be matched by a
 # range test rather than by a fixed id. Anything below the base is genuinely unknown and ignored.
 # 动态的「添加附件」条目位于 GP_CTX_ATTACH_BASE + 下标，故只能按范围匹配、无法用固定 id。
 # 低于该基值的 id 属真正的未知项，直接忽略。
			if gpId >= GP_CTX_ATTACH_BASE:
				gpOnAttachChoice(gpId - GP_CTX_ATTACH_BASE)


# ============================ P2: 添加附件 / 卸载附件 ============================
# ==================== P2: attach / detach ====================
# Build the "添加附件 ▶" submenu: ONE entry per part type that can go on this host right now. A type
# with no free compatible anchor is DISABLED with a reason instead of hidden — hiding it would make
# the user believe the part does not exist at all (规划 §15.3 step 2).
# 构建「添加附件 ▶」子菜单：能为当前宿主实际挂上的每种部件各一项。没有空闲兼容锚点的类型被
# **置灰并给出原因**而非隐藏 —— 隐藏会让用户以为该部件根本不存在（规划 §15.3 第 2 步）。
func _gpBuildAttachSubmenu(gpMenu: PopupMenu, gpNodeHit: String) -> void:
	# Reset first: a previous menu's host must never leak into this one (same rule the bump fields
	# follow in gpOnRightDown()).
	# 先清零：上一个菜单的宿主绝不能泄漏到本次（与 gpOnRightDown() 中鼓包字段同一规则）。
	_gpAttachHost = ""
	_gpAttachChoices.clear()
	if gpCv.gpGraph == null:
		return
	var gpHostUid: String = gpNodeHit if gpNodeHit != "" else gpCv.gpSelectedId
	var gpHostNode: GPPIDNode = gpCv.gpGraph.gpGetNode(gpHostUid)
	if gpHostNode == null:
		return
	var gpHostDef: GPSymbolDef = gpCv.gpDefFor(gpHostNode.gpSymbolId)
	if gpHostDef == null or gpHostDef.gpAttachPoints.is_empty():
		return
	var gpLookup: Callable = gpCv.gpDefLookupCallable()
	# Sorted by id inside the resolver, so the submenu order is stable frame to frame.
	# 在解析器内按 id 排序，故子菜单顺序逐帧稳定。
	var gpCands: Array[GPSymbolDef] = GPMountResolver.gpMountableDefs(GPSymbolLibrary.gpDefaultDefs())
	if gpCands.is_empty():
		return
	var gpSub: PopupMenu = PopupMenu.new()
	# An explicit name: add_submenu_item() refers to the child by NAME, and Godot's auto-generated
	# child names are not under our control.
	# 显式命名：add_submenu_item() 按**名字**引用子节点，而 Godot 自动生成的名字不受我们控制。
	gpSub.name = "gp_attach_sub"
	for gpChild in gpCands:
		var gpFree: Array[String] = GPMountResolver.gpFreeAnchorsForDef(gpCv.gpGraph, gpLookup,
			gpHostUid, gpChild)
		_gpAttachChoices.append({"symbol_id": gpChild.gpId, "free": gpFree})
		var gpActionId: int = GP_CTX_ATTACH_BASE + _gpAttachChoices.size() - 1
		# The display name is an i18n KEY for DEXPI-pack symbols ("dexpi.dgeneral008"), so the
		# label must go through the translator exactly as the palette item's tooltip does. Used
		# raw, the submenu read "dexpi.dgeneral008" instead of "接管嘴 / Nozzle".
		# 显示名对 DEXPI 包的图元而言是 i18n **键**（"dexpi.dgeneral008"），故标签必须与调色板
		# 条目的 tooltip 一样经翻译器。直接使用会让子菜单显示 "dexpi.dgeneral008" 而非「接管嘴」。
		var gpRaw: String = gpChild.gpDisplayName if gpChild.gpDisplayName != "" else gpChild.gpId
		var gpLabel: String = I18n.gpTr(gpRaw)
		gpSub.add_item(gpLabel, gpActionId)
		var gpAt: int = gpSub.get_item_index(gpActionId)
		gpSub.set_item_disabled(gpAt, gpFree.is_empty())
		if gpFree.is_empty():
			gpSub.set_item_tooltip(gpAt, I18n.gpTr("canvas.ctx_attach_no_room"))
	_gpAttachHost = gpHostUid
	gpSub.id_pressed.connect(gpOnContext)
	gpMenu.add_child(gpSub)
	gpMenu.add_submenu_item(I18n.gpTr("canvas.ctx_attach"), gpSub.name)


# How many nodes the "卸载附件" action would actually act on: the mounted ones among the selection
# (or the right-clicked node when it is not in the selection). The item is offered only when it can
# do something, so the menu never presents a dead entry.
# 「卸载附件」实际会作用到几个节点：选择集中的挂载项（右键节点不在选择集中时则取该节点）。
# 仅在确有效果时才提供该条目，菜单绝不呈现死条目。
func _gpDetachTargetCount(gpNodeHit: String) -> int:
	if gpCv.gpGraph == null:
		return 0
	var gpIds: Array[String] = []
	if gpNodeHit != "" and not gpCv.gpSelection.has(gpNodeHit):
		gpIds = [gpNodeHit]
	else:
		gpIds = gpCv.gpSelection
	var gpCount: int = 0
	for gpId in gpIds:
		var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
		if gpN != null and gpN.gpIsMounted():
			gpCount += 1
	return gpCount


# Dispatch one "添加附件" choice: attach the chosen type to the free compatible anchor NEAREST to
# where the user right-clicked (the first declared one when no position is known), then hand the
# new node straight to the positioning drag, so it lands correctly FIRST and the user only ever
# nudges from there (规划 §15.3 steps 3-4) — no aiming required to get it onto the host.
# 分派一个「添加附件」选择：把所选类型挂到距**右键位置最近**的空闲兼容锚点（无位置信息时取
# 声明顺序的第一个），随后把新节点直接交给拖动定位。于是它先落对位置，用户只需从那里微调
#（规划 §15.3 第 3-4 步）—— 无需瞄准即可贴上宿主。
func gpOnAttachChoice(gpChoiceIdx: int) -> void:
	if gpChoiceIdx < 0 or gpChoiceIdx >= _gpAttachChoices.size() or _gpAttachHost == "":
		return
	var gpChoice: Dictionary = _gpAttachChoices[gpChoiceIdx]
	var gpFree: Array[String] = gpChoice["free"]
	if gpFree.is_empty():
		return
	# The nearest-anchor pick lives in the resolver so it stays testable and the menu stays thin.
	# 最近锚点的挑选放在解析器里，保持可测且菜单层足够薄。
	var gpBest: String = GPMountResolver.gpNearestAnchorName(gpCv.gpGraph, gpCv.gpDefLookupCallable(),
		_gpAttachHost, gpFree, _gpAttachWorld)
	gpCv.gpRequestAttachAndPosition(str(gpChoice["symbol_id"]), _gpAttachHost, gpBest)
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
