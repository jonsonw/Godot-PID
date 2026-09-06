# ============================================================================
# GPCanvasContextMenu — 右键上下文菜单（P2 拆分）
# Right-click context menu (P2 split).
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

# Canvas this menu acts on (state owner).
# 本菜单作用的画布（状态持有者）。
var gpCv: GPCanvas2D

# Node id the right-click menu was opened on ("" when the click missed everything).
# 右键菜单打开时所处的节点 id（未命中任何节点时为空）。
var _gpCtxHit: String = ""

# Vertex index the right-click menu was opened on, for a single selected annotation polyline
# (only meaningful when the cursor hit one of its vertex / handle grips). -1 = none.
# 右键菜单打开时所处的「单选注释折线」顶点下标（仅当光标命中其顶点 / 手柄抓取点时才有意义）。-1 = 无。
var _gpCtxVertex: int = -1


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
	var gpHit: String = gpCv._gpHitTest(gpWorld)
	if gpHit != "":
		if not gpCv.gpSelection.has(gpHit):
			gpCv._gpSetSelection([gpHit])
		_gpCtxHit = gpHit
		gpShowContextMenu(gpHit)
		return
	# No symbol hit: try an annotation shape instead.
	# 未命中图元：改试注释图形。
	var gpSh: int = gpCv._gpHitShape(gpWorld)
	if gpSh >= 0:
		if not gpCv.gpShapeSel.has(gpSh):
			gpCv.gpShapeSel = [gpSh]
			gpCv._gpSetSelection([])
		# Remember which vertex of a single selected polyline was right-clicked so the menu can offer
		# vertex-only actions (smooth / corner / delete this vertex). Right-click on the empty inside
		# of the polyline leaves _gpCtxVertex = -1 (the shape-level menu shows instead).
		# 记住「单选折线」被右键点击的是哪个顶点，使菜单能提供仅针对顶点的操作（平滑 / 拐角 / 删除此顶点）。
		# 右键点在折线内部空白处时 _gpCtxVertex 保持 -1（显示图形级菜单）。
		var gpVGrip: Dictionary = gpCv._gpAnno.gpHitPolylineVertexGrip(gpWorld)
		if not gpVGrip.is_empty():
			_gpCtxVertex = int(gpVGrip["gi"])
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
	# Promote selected annotation shapes into a real symbol (only meaningful when shapes are picked).
	# 把选中的注释图形提升为真正图元（仅当选中图形时才有意义）。
	if not gpCv.gpShapeSel.is_empty():
		gpMenu.add_item(I18n.gpTr("canvas.ctx_make_symbol"), GP_CTX_MAKE_SYMBOL)
	# Vertex-only actions on the right-clicked vertex of a single selected polyline (Bézier handles).
	# 对「单选折线」被右键顶点的顶点级操作（贝塞尔手柄）。镜像符号编辑器：平滑 = 拉手柄、拐角 = 收手柄。
	if _gpCtxVertex >= 0:
		var gpSelShape: GPShape = gpCv._gpAnno.gpSingleSelectedShape()
		if gpSelShape != null and gpCv._gpAnno.gpVertexHasHandles(gpSelShape, _gpCtxVertex):
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
	gpMenu.add_separator()
	gpMenu.add_item(I18n.gpTr("canvas.ctx_select_all"), GP_CTX_SELECT_ALL)
	gpMenu.add_item(I18n.gpTr("canvas.ctx_deselect"), GP_CTX_DESELECT)
	gpMenu.add_separator()
	gpMenu.add_check_item(I18n.gpTr("canvas.ctx_connect_mode"), GP_CTX_CONNECT)
	# Disable by id, looked up through get_item_index: positional disabling breaks as soon as a
	# conditional item is inserted above. Items that were not added are skipped (index -1).
	# 按 id 禁用，并用 get_item_index 反查位置：一旦上方插入了条件项，按位置禁用就会错位。
	# 未添加的条目（下标 -1）直接跳过。
	if gpMenu.get_item_index(GP_CTX_EDIT) >= 0:
		gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_EDIT), gpNodeHit == "")
	if gpMenu.get_item_index(GP_CTX_DUPLICATE) >= 0:
		gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DUPLICATE), gpCv.gpSelection.is_empty())
	if gpMenu.get_item_index(GP_CTX_DELETE) >= 0:
		gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DELETE), gpCv.gpSelection.is_empty() and gpCv.gpShapeSel.is_empty())
	gpMenu.set_item_disabled(gpMenu.get_item_index(GP_CTX_DESELECT), gpCv.gpSelection.is_empty() and gpCv.gpShapeSel.is_empty())
	gpMenu.set_item_checked(gpMenu.get_item_index(GP_CTX_CONNECT), gpCv.gpMode == GPMode.GP_CONNECT)
	gpMenu.id_pressed.connect(gpOnContext)
	gpCv.add_child(gpMenu)
	# Godot 4's PopupMenu/Popup exposes NO popup_at_cursor(); the only positioning entry is popup(), and
	# when popups are NOT embedded (embed_subwindows=false, the default) its .position is interpreted in
	# GLOBAL SCREEN coordinates. Positioning is centralized in GPPopupHelper.gpPopupAtMouse (single source
	# of truth for the window-screen formula that was previously duplicated and error-prone across call
	# sites). Menu top-left anchors at the pointer and opens down-right (the convention). (2,2) nudges
	# the cursor off.
	# Godot 4 的 PopupMenu/Popup 没有 popup_at_cursor()，仅 popup() 可定位；「非嵌入」（默认值）时其
	# .position 取「全局屏幕」坐标。菜单定位统一交由 GPPopupHelper.gpPopupAtMouse（窗口屏幕坐标公式的
	# 单一事实来源）。菜单左上角锚定在指针、向右下展开（符合惯例）。(2,2) 微调让光标落在菜单角外侧。
	GPPopupHelper.gpPopupAtMouse(gpMenu, gpCv)
	# Free the menu after it closes; a leaked PopupMenu keeps its parent alive.
	# 关闭后释放菜单；泄漏的 PopupMenu 会让其父节点无法释放。
	gpMenu.popup_hide.connect(gpMenu.queue_free)


# Dispatch a context-menu action.
# 分发右键菜单动作。
func gpOnContext(gpId: int) -> void:
	match gpId:
		GP_CTX_MAKE_SYMBOL:
			gpCv._gpAnno.gpMakeSymbolFromShapes()
		GP_CTX_EDIT:
			var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(_gpCtxHit) if gpCv.gpGraph != null else null
			if gpN != null:
				gpCv.gpSymbolEditRequested.emit(gpN.gpSymbolId)
		GP_CTX_DUPLICATE:
			gpCv._gpDuplicateSelected()
		GP_CTX_DELETE:
			gpCv._gpDeleteSelected()
		GP_CTX_SMOOTH_VERTEX:
			# Pull handles out of the right-clicked vertex (make it smooth). Only valid when a single
			# polyline is selected and that vertex was the right-click target.
			# 拉出被右键顶点的两侧手柄（转为平滑）。仅当单选折线且该顶点正是右键目标时有效。
			var gpSmoothShape: GPShape = gpCv._gpAnno.gpSingleSelectedShape()
			if gpSmoothShape != null and _gpCtxVertex >= 0:
				gpCv._gpAnno.gpPullHandles(gpSmoothShape, _gpCtxVertex)
			_gpCtxVertex = -1
		GP_CTX_CORNER_VERTEX:
			# Collapse the handles of the right-clicked vertex back onto it (make it a corner).
			# 收起被右键顶点的两侧手柄（转为拐角）。
			var gpCornerShape: GPShape = gpCv._gpAnno.gpSingleSelectedShape()
			if gpCornerShape != null and _gpCtxVertex >= 0:
				gpCv._gpAnno.gpCollapseHandles(gpCornerShape, _gpCtxVertex)
			_gpCtxVertex = -1
		GP_CTX_DELETE_VERTEX:
			# Remove just the right-clicked vertex, keeping the rest of the polyline connected.
			# 仅删除被右键的顶点，折线其余部分保持连接。
			var gpDelShape: GPShape = gpCv._gpAnno.gpSingleSelectedShape()
			if gpDelShape != null and _gpCtxVertex >= 0:
				gpCv._gpAnno.gpRemoveVertex(gpDelShape, _gpCtxVertex)
			_gpCtxVertex = -1
		GP_CTX_SELECT_ALL:
			gpCv._gpSelectAll()
		GP_CTX_DESELECT:
			gpCv._gpSetSelection([])
			gpCv.gpShapeSel.clear()
			gpCv.queue_redraw()
		GP_CTX_CONNECT:
			gpCv.gpSetMode(GPMode.GP_SELECT if gpCv.gpMode == GPMode.GP_CONNECT else GPMode.GP_CONNECT)
			gpCv.gpConnectFrom = ""
			gpCv.queue_redraw()
