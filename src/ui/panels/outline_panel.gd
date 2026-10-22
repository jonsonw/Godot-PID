class_name GPOutlinePanel
extends VBoxContainer
# Copyright © 2026 Jonson Wang
#
# Hierarchy outline: shows the mount tree that already lives in the DATA (gpParentUid) but had no
# UI. Read-only projection of the graph plus two commands — it never owns state and never edits
# the graph directly, so every action it offers is undoable through the normal command layer.
# 层级大纲：把**数据里早就有**的挂载树（gpParentUid）显示出来 —— 此前它没有任何界面。
# 本面板只是图数据的只读投影 + 两条命令；它不持有状态、也绝不直接改图，
# 因此它提供的每个动作都经由正常命令层，天然可撤销。
#
# Why a tree panel and not scene-tree parenting / 为何是树面板而不是场景树父子：
# The scene tree keeps symbols FLAT on purpose (the view is a thin projection; world position is
# derived by GPMountResolver). Turning it into a real parent/child hierarchy would make
# `position` relative and force undo semantics, copy remapping, cross-sheet hosts and a second
# port-resolution source to be redone. The hierarchy already exists in data, so a panel that
# READS it gives the user the structure without paying that bill. See docs/YAGNI.
# 场景树刻意让图元保持**平铺**（视图是瘦投影，世界坐标由 GPMountResolver 推导）。改成真正的
# 父子会让 `position` 变成相对坐标，并迫使撤销语义、复制重映射、跨图纸宿主与第二个端口解析
# 来源全部重做。层级本就存在于数据里，一个**读取**它的面板即可把结构交给用户，而不必付这笔账。
# 见 docs/YAGNI。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Context-menu ids. Mount candidates start at GP_CTX_MOUNT_BASE + index into _gpHostChoices.
# 右键菜单 id。挂载候选项从 GP_CTX_MOUNT_BASE + 候选下标开始。
const GP_CTX_DETACH: int = 1
const GP_CTX_MOUNT_BASE: int = 100

# Column indices of the tree.
# 树的列下标。
const GP_COL_NAME: int = 0
const GP_COL_TYPE: int = 1


# The tree control (built in gpBuild()). Public so tests can drive it headlessly.
# 树控件（在 gpBuild() 中构建）。公开，使测试可 headless 驱动它。
var gpTree: Tree = null

# Small explanatory line under the tree (mount semantics are not self-evident).
# 树下的一行说明（挂载语义并不自明）。
var gpHint: Label = null

# Canvas this panel projects. Null before gpBindCanvas() (the panel is built before any sheet
# exists, so it must tolerate having no graph yet).
# 本面板所投影的画布。gpBindCanvas() 之前为 null（面板先于任何图纸构建，故必须容忍暂无图）。
var _gpCanvas: GPCanvas2D = null

# Guards re-entrancy: a programmatic selection change re-emits the canvas selection event, which
# the host turns back into a refresh — without this flag that loop rebuilds the tree forever.
# 防重入：程序化改选会重新发出画布选择事件，宿主又把它变回一次刷新 —— 没有这个标志，
# 该循环会无限重建树。
var _gpRebuilding: bool = false

# Context menu (created once, repopulated per right-click).
# 右键菜单（创建一次，每次右键重新填充）。
var _gpMenu: PopupMenu = null

# Host ids listed in the menu, indexed by (id - GP_CTX_MOUNT_BASE).
# 菜单中列出的宿主 id，按 (id - GP_CTX_MOUNT_BASE) 索引。
var _gpHostChoices: Array[String] = []

# Item currently right-clicked ("" when the click landed on empty space).
# 当前被右键的条目（"" 表示点在空白处）。
var _gpMenuTarget: String = ""

# Tree item by node id, rebuilt on every gpRefresh().
# 节点 id → 树条目，每次 gpRefresh() 重建。
var _gpItemById: Dictionary = {}


# Build the widgets. Called ONCE by the host after the panel is added to the tab container.
# 构建控件。由宿主在面板加入标签容器之后**调用一次**。
func gpBuild() -> void:
	name = "OutlineTab"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	gpTree = Tree.new()
	gpTree.name = "OutlineTree"
	gpTree.hide_root = true
	gpTree.columns = 2
	gpTree.column_titles_visible = true
	gpTree.set_column_title(GP_COL_NAME, I18n.gpTr("outline.col_node"))
	gpTree.set_column_title(GP_COL_TYPE, I18n.gpTr("outline.col_type"))
	gpTree.set_column_expand(GP_COL_NAME, true)
	gpTree.set_column_custom_minimum_width(GP_COL_TYPE, 72)
	gpTree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# How a row is selected / activated. A single click selects the symbol on the canvas (the
	# panel is a navigation aid first); double click does the same, because there is nothing else
	# it could mean — this is a hierarchy view, not an editor.
	# 行如何被选中 / 激活。单击即在画布上选中该图元（面板首先是导航辅助）；双击做同一件事，
	# 因为它不可能是别的意思 —— 这是层级视图，不是编辑器。
	gpTree.item_selected.connect(_gpOnItemSelected)
	gpTree.item_activated.connect(_gpOnItemActivated)
	gpTree.item_mouse_selected.connect(_gpOnItemMouseSelected)
	add_child(gpTree)

	gpHint = Label.new()
	gpHint.name = "OutlineHint"
	gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpHint.add_theme_font_size_override("font_size", 11)
	gpHint.text = I18n.gpTr("outline.hint")
	add_child(gpHint)

	_gpMenu = PopupMenu.new()
	_gpMenu.name = "OutlineMenu"
	_gpMenu.id_pressed.connect(_gpOnMenuIdPressed)
	add_child(_gpMenu)


# Point the panel at a canvas (called on tab switch and on first assembly).
# 把面板指向一个画布（切换标签与首次装配时调用）。
func gpBindCanvas(gpCv: GPCanvas2D) -> void:
	_gpCanvas = gpCv
	gpRefresh()


# Rebuild the whole tree from the bound canvas' graph.
# 依据所绑定画布的图重建整棵树。
# Cheap enough to run on every graph change: a sheet has tens of symbols, and a TreeItem rebuild
# is far cheaper than the repaint that triggered it.
# 每次图变化都跑得起：一张图纸只有几十个图元，重建树条目远比触发它的那次重绘便宜。
func gpRefresh() -> void:
	if gpTree == null:
		return
	_gpRebuilding = true
	gpTree.clear()
	_gpItemById.clear()
	var gpRoot: TreeItem = gpTree.create_item()
	if _gpCanvas != null and _gpCanvas.gpGraph != null:
		var gpGraph: GPPIDGraph = _gpCanvas.gpGraph
		var gpSeen: Dictionary = {}
		for gpId in gpTopLevelIds(gpGraph):
			_gpAddBranch(gpRoot, gpGraph, gpId, gpSeen)
	_gpSyncSelection()
	_gpRebuilding = false


# Update the tree's selection highlight to match the canvas, without rebuilding.
# 更新树的选中高亮以匹配画布，但不重建。
func gpRefreshSelection() -> void:
	if gpTree == null or _gpRebuilding:
		return
	_gpRebuilding = true
	_gpSyncSelection()
	_gpRebuilding = false


# Symbol ids that have no host on THIS sheet: either genuinely top-level (gpParentUid == "") or
# mounted onto a host that is not here (a sheet-local fragment of a larger assembly).
# 本图纸上没有宿主的图元 id：或真正顶层（gpParentUid == ""），或挂在不在本图纸上的宿主上
#（更大装配在本图纸上的片段）。
# Pure + static so it can be pinned headlessly without building any UI.
# 纯函数 + static，故无需构建界面即可被 headless 测试钉住。
static func gpTopLevelIds(gpGraph: GPPIDGraph) -> Array[String]:
	var gpOut: Array[String] = []
	if gpGraph == null:
		return gpOut
	for gpN in gpGraph.gpNodes:
		var gpParent: String = gpN.gpParentUid
		if gpParent == "" or gpGraph.gpGetNode(gpParent) == null:
			gpOut.append(gpN.gpInstanceId)
	return gpOut


# Build the mount tuple for "mount gpChildId onto gpHostId", or {} when it is not allowed.
# 构造「把 gpChildId 挂到 gpHostId」的挂载元组；不允许时返回 {}。
# All four rules live here as one pure function so the same judgment can be tested without a
# tree, a canvas or a command stack — and so the panel cannot invent a fifth rule of its own.
# 四条规则集中在同一个纯函数里，使同一判断无需树、画布或命令栈即可测试 ——
# 也使面板无法自己发明第五条规则。
#   1. both nodes exist, and they are not the same node;
#   2. the host is not inside the child's own subtree (that would be a cycle);
#   3. the child's definition declares a mount kind (a table / text block never mounts);
#   4. the host has a free anchor that accepts that kind.
#   1. 两个节点都存在且不是同一个；
#   2. 宿主不在子件自己的子树内（那会成环）；
#   3. 子件的定义声明了挂载种类（表格 / 文本块永不挂载）；
#   4. 宿主有接纳该种类的空闲锚点。
static func gpMountTuple(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpChildId: String,
		gpHostId: String) -> Dictionary:
	if gpGraph == null or gpChildId == "" or gpHostId == "" or gpChildId == gpHostId:
		return {}
	var gpChild: GPPIDNode = gpGraph.gpGetNode(gpChildId)
	var gpHost: GPPIDNode = gpGraph.gpGetNode(gpHostId)
	if gpChild == null or gpHost == null:
		return {}
	if GPMountResolver.gpSubtree(gpGraph, gpChildId).has(gpHostId):
		return {}
	var gpChildDef: GPSymbolDef = GPMountResolver.gpDefFor(gpDefLookup, gpChild.gpSymbolId)
	if gpChildDef == null or gpChildDef.gpMountKind == "":
		return {}
	var gpAnchor: String = GPMountResolver.gpFirstFreeAnchorForDef(gpGraph, gpDefLookup,
		gpHostId, gpChildDef)
	if gpAnchor == "":
		return {}
	return {
		"parent_uid": gpHostId,
		"mount_anchor": gpAnchor,
		"mount_offset": Vector2.ZERO,
		"mount_angle_deg": 0.0,
	}


# Recursively add one node and its mounted children.
# 递归添加一个节点及其挂载子件。
# [param gpSeen] breaks a hand-edited parent cycle (A mounts B, B mounts A) instead of recursing
# forever — the resolver has the same guard for the same reason.
# [param gpSeen] 打断手改出来的父链环（A 挂 B、B 挂 A），而不是无限递归 ——
# 解析器出于同样理由也有同样的护栏。
func _gpAddBranch(gpParentItem: TreeItem, gpGraph: GPPIDGraph, gpId: String,
		gpSeen: Dictionary) -> void:
	if gpSeen.has(gpId):
		return
	gpSeen[gpId] = true
	var gpN: GPPIDNode = gpGraph.gpGetNode(gpId)
	if gpN == null:
		return
	var gpDef: GPSymbolDef = null
	if _gpCanvas != null:
		gpDef = _gpCanvas.gpDefFor(gpN.gpSymbolId)
	var gpItem: TreeItem = gpTree.create_item(gpParentItem)
	# Name column: the tag (the thing an engineer reads), falling back to the type name — the SAME
	# resolution the canvas label uses, so a row never disagrees with the drawing.
	# 名称列：位号（工程师读的那个），缺失时回落到类型名 —— 与画布标签同一解析，
	# 故列表行绝不会与图纸不一致。
	gpItem.set_text(GP_COL_NAME, GPLabelGripOps.gpLabelText(gpN, gpDef, I18n.gpLocale))
	gpItem.set_text(GP_COL_TYPE, "" if gpDef == null else I18n.gpTr(gpDef.gpDisplayName))
	gpItem.set_metadata(GP_COL_NAME, gpId)
	gpItem.set_tooltip_text(GP_COL_NAME, gpId)
	_gpItemById[gpId] = gpItem
	for gpChild in GPMountResolver.gpChildrenOf(gpGraph, gpId):
		_gpAddBranch(gpItem, gpGraph, gpChild.gpInstanceId, gpSeen)


# Mirror the canvas selection into the tree, expanding the ancestors of a selected row so it is
# actually visible (a collapsed host would otherwise hide the symbol the user just picked).
# 把画布选择镜像到树上，并展开选中行的祖先，使其真正可见
#（否则一个折叠的宿主会把用户刚选中的图元藏起来）。
func _gpSyncSelection() -> void:
	if _gpCanvas == null:
		return
	var gpSel: Array[String] = _gpCanvas.gpSelection
	# Select through the TREE, not the item: in a multi-column Tree the canonical API is
	# Tree.set_selected(item, column) / TreeItem.select(column). TreeItem.set_selected() is the
	# single-column shorthand and does not update the tree's own "current item", so
	# gpTree.get_selected() would keep returning null and the panel would look like it ignored the
	# canvas selection.
	# 经**树**而不是条目来选中：多列 Tree 的规范接口是 Tree.set_selected(item, column) /
	# TreeItem.select(column)。TreeItem.set_selected() 是单列简写，不更新树自身的「当前条目」，
	# 于是 gpTree.get_selected() 永远返回 null，面板看起来就像无视了画布的选择。
	for gpId in _gpItemById.keys():
		var gpItem: TreeItem = _gpItemById[gpId] as TreeItem
		if gpItem == null:
			continue
		if gpSel.has(str(gpId)):
			gpItem.select(GP_COL_NAME)
			gpTree.set_selected(gpItem, GP_COL_NAME)
		else:
			gpItem.deselect(GP_COL_NAME)
	for gpId in gpSel:
		var gpItem: TreeItem = _gpItemById.get(gpId, null) as TreeItem
		if gpItem == null:
			continue
		var gpUp: TreeItem = gpItem.get_parent()
		while gpUp != null:
			gpUp.set_collapsed(false)
			gpUp = gpUp.get_parent()


# Node id of the currently selected tree row ("" when nothing is selected).
# 当前选中树行的节点 id（无选中时为 ""）。
func _gpSelectedId() -> String:
	if gpTree == null:
		return ""
	var gpItem: TreeItem = gpTree.get_selected()
	if gpItem == null:
		return ""
	return str(gpItem.get_metadata(GP_COL_NAME))


# A row was selected with the mouse or keyboard: select that symbol on the canvas.
# 某行被（鼠标或键盘）选中：在画布上选中该图元。
func _gpOnItemSelected() -> void:
	if _gpRebuilding or _gpCanvas == null:
		return
	var gpId: String = _gpSelectedId()
	if gpId == "":
		return
	_gpCanvas.gpSetSelection([gpId])


# Double click. Deliberately identical to a single click: this is a navigation view, and inventing
# a second meaning (zoom-to-fit? open editor?) would make the panel unpredictable.
# 双击。刻意与单击相同：这是导航视图，另造第二含义（缩放到适配？打开编辑器？）
# 只会让面板变得不可预期。
func _gpOnItemActivated() -> void:
	_gpOnItemSelected()


# Right click: build the context menu for the row under the cursor.
# 右键：为光标下的行构建右键菜单。
func _gpOnItemMouseSelected(gpPos: Vector2, gpButton: int) -> void:
	if gpButton != MOUSE_BUTTON_RIGHT or _gpCanvas == null or _gpMenu == null:
		return
	var gpItem: TreeItem = gpTree.get_item_at_position(gpPos)
	_gpMenuTarget = "" if gpItem == null else str(gpItem.get_metadata(GP_COL_NAME))
	if _gpMenuTarget == "":
		return
	_gpBuildMenu()
	# Anchor the popup at the cursor in SCREEN space: get_item_at_position() works in local space,
	# so the tree's screen position must be added or the menu appears offset by the dock layout.
	# 在**屏幕**空间把弹出菜单放到光标处：get_item_at_position() 用的是本地坐标，
	# 必须加上树的屏幕位置，否则菜单会偏移一个停靠栏的距离。
	var gpAt: Vector2 = gpTree.get_screen_position() + gpPos
	_gpMenu.reset_size()
	_gpMenu.position = Vector2i(gpAt)
	_gpMenu.popup()


# Fill the context menu: detach (when mounted) + one entry per host that can accept the node.
# 填充右键菜单：脱离（处于挂载态时）+ 每个能接纳该节点的宿主一条。
func _gpBuildMenu() -> void:
	_gpMenu.clear()
	_gpHostChoices.clear()
	var gpGraph: GPPIDGraph = _gpCanvas.gpGraph
	if gpGraph == null:
		return
	var gpNode: GPPIDNode = gpGraph.gpGetNode(_gpMenuTarget)
	if gpNode == null:
		return
	if gpNode.gpParentUid != "":
		_gpMenu.add_item(I18n.gpTr("outline.ctx_detach"), GP_CTX_DETACH)
	var gpLookup: Callable = _gpCanvas.gpDefLookupCallable()
	for gpHost in gpGraph.gpNodes:
		if gpHost.gpInstanceId == _gpMenuTarget:
			continue
		if gpMountTuple(gpGraph, gpLookup, _gpMenuTarget, gpHost.gpInstanceId).is_empty():
			continue
		var gpHostDef: GPSymbolDef = _gpCanvas.gpDefFor(gpHost.gpSymbolId)
		var gpHostLabel: String = GPLabelGripOps.gpLabelText(gpHost, gpHostDef, I18n.gpLocale)
		_gpMenu.add_item(I18n.gpTr("outline.ctx_mount_to") % gpHostLabel,
			GP_CTX_MOUNT_BASE + _gpHostChoices.size())
		_gpHostChoices.append(gpHost.gpInstanceId)
	if _gpMenu.item_count == 0:
		_gpMenu.add_item(I18n.gpTr("outline.ctx_none"), GP_CTX_MOUNT_BASE)
		_gpMenu.set_item_disabled(0, true)


# Menu entry chosen.
# 菜单项被选中。
func _gpOnMenuIdPressed(gpId: int) -> void:
	if _gpCanvas == null or _gpMenuTarget == "":
		return
	if gpId == GP_CTX_DETACH:
		# Detach goes through the selection: the existing command detaches "the selection", and
		# re-implementing a single-node variant would be a second code path for one operation.
		# 脱离经由选择集：既有命令处理的是「选中项」，为单个节点另写一份等于给同一操作开第二条代码路径。
		_gpCanvas.gpSetSelection([_gpMenuTarget])
		_gpCanvas.gpRequestDetachSelected()
		gpRefresh()
		return
	var gpIndex: int = gpId - GP_CTX_MOUNT_BASE
	if gpIndex < 0 or gpIndex >= _gpHostChoices.size():
		return
	var gpGraph: GPPIDGraph = _gpCanvas.gpGraph
	if gpGraph == null:
		return
	var gpTuple: Dictionary = gpMountTuple(gpGraph, _gpCanvas.gpDefLookupCallable(),
		_gpMenuTarget, _gpHostChoices[gpIndex])
	if gpTuple.is_empty():
		return
	# ONE undo step, and the same command the canvas' own mount drag uses — so a tree mount and a
	# canvas mount are literally the same edit, not two features that must be kept in sync.
	# 一步撤销，且与画布自身的挂载拖拽使用同一条命令 —— 故「在树里挂」与「在画布上挂」
	# 是同一次编辑，而不是两个必须同步维护的功能。
	_gpCanvas.gpRequestSetMount([_gpMenuTarget], [gpTuple])
	gpRefresh()


# Refresh every localized string in the panel (host calls this on locale change).
# 刷新面板中所有本地化文本（语言变化时由宿主调用）。
func gpRefreshText() -> void:
	if gpTree != null:
		gpTree.set_column_title(GP_COL_NAME, I18n.gpTr("outline.col_node"))
		gpTree.set_column_title(GP_COL_TYPE, I18n.gpTr("outline.col_type"))
	if gpHint != null:
		gpHint.text = I18n.gpTr("outline.hint")
