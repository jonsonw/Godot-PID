class_name GPSymbolLibraryCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Symbol library cascade delete, swap/rename, drift reconciliation, user packs and the symbol editor host
# 图元库级联删除、替换与重命名、漂移对账、用户包加载与符号编辑器宿主
#
# WHY THIS EXISTS / 为何存在（架构优化建议 §3.2）：
#   GPMainWindow was carrying many unrelated responsibilities in one file; this coordinator
#   owns the "Symbol library cascade delete, swap/rename, drift reconciliation, user packs and the symbol editor host" use case end to end, so the root keeps only assembly and forwarding.
#   GPMainWindow 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「图元库级联删除、替换与重命名、漂移对账、用户包加载与符号编辑器宿主」这一用例，
#   使根类只保留装配与转发。
#
# Interaction / 交互方式：
#   - the root creates this coordinator and injects itself as gpHost (composition root);
#     根类创建本协调者并把自身注入为 gpHost（组合根装配）；
#   - the root forwards menu / toolbar actions here, never the other way round — this class
#     does not reach back into menus or the ribbon;
#     根类把菜单/工具栏动作转发到此处，绝不反向 —— 本类不回指菜单或 Ribbon；
#   - UI refresh goes through gpHost._gpSetState / the docks the root owns.
#     UI 刷新经由 gpHost._gpSetState 及根类持有的停靠栏完成。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPMainWindow = null


# The edited geometry was re-registered under the SAME id, so every placed instance repaints.
# 编辑后的几何已按同一 id 重新注册，故所有已放置实例都会重绘。
# gpDefaultDefs() returns a stable-identity array that gpRegisterDefs patched in place, so the
# canvases already see the new object; only the palette and the paint need refreshing.
# gpDefaultDefs() 返回的数组身份稳定且已被 gpRegisterDefs 就地修补，故各画布已看到新对象；
# 只需刷新图元库与重绘。
func gpOnSymbolSaved(gpSymbolId: String) -> void:
	gpHost.gpDefs = GPSymbolLibrary.gpDefaultDefs()
	gpSyncInspectorDefs()
	gpHost.gpLeftDock.gpPopulate(gpHost.gpDefs)
	gpHost.gpCenter.gpSetDefs(gpHost.gpDefs)
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas != null:
		gpCanvas.queue_redraw()
	gpHost._gpRefreshSelection()
	gpHost._gpSetState("status.symbol_saved", [gpSymbolId])


# Delete every selected node and any edges connected to them (menu 编辑 / 删除).
# 删除所有选中节点及其关联的边（菜单「编辑 / 删除」）。
# Delegated to the canvas so the multi-selection state lives in exactly one place.
# 委托给画布执行，使多选状态只有一处真相来源。

func gpOnSymbolEditRequested(gpSymbolId: String) -> void:
	# The in-place symbol editor was removed (P4 refactor). Editing an existing placed symbol now
	# re-opens the Make-Symbol dialog seeded with that symbol's geometry; confirming under the same
	# display name overwrites the def (built-ins derive a C-rule copy per decision D3).
	# 就地图元编辑器已移除（P4 重构）。编辑已放置图元改为用「生成图元」对话框带入该图元几何；
	# 以相同显示名确定即覆盖该 def（内置图元按决策 D3 派生 C 规则副本）。
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null or gpHost.gpCenter == null:
		return
	var gpDef: GPSymbolDef = gpHost._gpDefFor(gpSymbolId)
	if gpDef == null:
		return
	# D3: built-in symbols are read-only → derive a copy under a fresh C-rule id
	# (C<CATEGORY><nnn>) so the original ISO glyph is never overwritten or re-fit.
	# 决策 D3：内置图元只读 → 以新的 C 规则 id（C<类别码><三位序号>）派生副本，
	# 绝不覆盖/重拟合原始 ISO 图元。
	var gpEditDef: GPSymbolDef = gpDef
	var gpAllowOverwrite: bool = true
	if gpDef.gpBuiltin:
		var gpDerivedId: String = GPSymbolLibrary.gpAllocateCustomId(gpDef.gpCategory)
		if gpDerivedId == "":
			push_warning("GPMainWindow: category %s has no free C-rule id left" % gpDef.gpCategory)
			return
		var gpCanon: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(
			GPSymbolNormalizer.gpDenormalizeSymbol(gpDef), gpDef.gpCategory, {})
		gpCanon.gpId = gpDerivedId
		gpCanon.gpBuiltin = false
		GPSymbolLibrary.gpRegisterDefs([gpCanon])
		gpHost.gpDefs = GPSymbolLibrary.gpDefaultDefs()
		gpSyncInspectorDefs()
		gpHost.gpLeftDock.gpPopulate(gpHost.gpDefs)
		gpHost.gpCenter.gpSetDefs(gpHost.gpDefs)
		gpEditDef = gpCanon
		gpAllowOverwrite = false
	# Convert the def's EDITABLE shape spec (raw control points + Bézier handles) into the dialog
	# draft, so editing an existing curved symbol keeps its curve control points. gpShapeSpec() is
	# the flattened render spec (painter); it would drop handles and degrade a curve to straight
	# segments. gpEditSpec() is the lossless inverse of what the dialog re-imports via gpFromSpec.
	# 把 def 的「可编辑」形状规格（原始控制点 + 贝塞尔手柄）转成对话框 draft，使编辑已有曲线图元时
	# 保留其曲线控制点。gpShapeSpec() 是给 painter 打平的渲染 spec，会丢手柄、把曲线退化成直线；
	# gpEditSpec() 是无损的，能被对话框经 gpFromSpec 无损还原。
	var gpDraft: Dictionary = GPShapeSpec.gpEditSpec(gpEditDef.gpShapes)
	gpDraft.erase("box")
	# Carry the symbol's current ports into the editor so editing preserves connection points
	# instead of silently dropping them (previously the dialog always started with zero ports).
	# 把图元当前端口带入编辑器，使编辑保留连接点而非静默丢弃（此前对话框总是从零端口起步）。
	# Seed the ID field with the symbol's real ID (uniqueness is judged by id, NOT display
	# name) and prefill the display-name field separately. A built-in's display name is an
	# i18n key (sym./iso. prefixed) — translate it so the derived copy stores human text.
	# 标识框预填图元真实 id（唯一性以 id 判定，非显示名），显示名单独预填。内置图元的
	# 显示名是 i18n 键（sym./iso. 前缀），先翻译，使派生副本保存为人类可读文本。
	var gpEditDisplay: String = gpEditDef.gpDisplayName
	if gpEditDisplay.begins_with("sym.") or gpEditDisplay.begins_with("iso."):
		gpEditDisplay = I18n.gpTr(gpEditDisplay)
	gpOpenMakeSymbolDialog(gpDraft, gpEditDef.gpId, gpAllowOverwrite, gpEditDef.gpPorts, gpEditDisplay)

# Open the Make-Symbol dialog converged from the two handlers (promote-from-shapes and
# edit-existing) that previously duplicated gpOpen + gpMadeSymbol.connect. gpOpen adds the
# dialog as a child Window, so it is handed the actual main Window (not this Control). On confirm
# the shared gpOnSymbolSaved refreshes the palette + canvas.
# 打开「生成图元」对话框的收敛助手——统一了「从图形提升」与「编辑已有图元」两个处理器此前重复的
# gpOpen + gpMadeSymbol.connect 逻辑。gpOpen 把对话框作为子 Window 添加，故传入真正的主 Window
# （而非本 Control）。确定后由共享的 gpOnSymbolSaved 刷新图元库与画布。
func gpOpenMakeSymbolDialog(gpDraft: Dictionary, gpInitialName: String, gpAllowOverwrite: bool, gpInitialPorts: Array[GPPort] = [], gpInitialDisplay: String = "") -> void:
	var gpWin: Window = gpHost.get_window()
	if gpWin == null or gpHost.gpCenter == null:
		return
	var gpDlg: GPMakeSymbolDialog = GPMakeSymbolDialog.gpOpen(gpWin, gpDraft, gpInitialName, gpAllowOverwrite, gpInitialPorts, gpInitialDisplay)
	if gpDlg == null:
		return
	gpDlg.gpMadeSymbol.connect(gpOnSymbolSaved)

func gpOnMakeSymbolFromShapes(gpDraft: Dictionary) -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null or gpHost.gpCenter == null:
		return
	# gpOpen adds the dialog as a child Window, so hand it the actual main Window (not this Control).
	# gpOpen 会把对话框作为子 Window 添加，故传入真正的主 Window（而非本 Control）。
	var gpWin: Window = gpHost.get_window()
	if gpWin == null:
		return
	gpOpenMakeSymbolDialog(gpDraft, "", true)

# M12: drop the orphaned values of one instance, on the user's explicit request.
# M12：按用户明确请求，清除某个实例上的孤儿值。
func gpOnCleanOrphans(gpNodeId: String) -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpNode: GPPIDNode = gpHost._gpNodeFor(gpNodeId)
	if gpNode == null:
		return
	var gpDef: GPSymbolDef = gpHost._gpDefFor(gpNode.gpSymbolId)
	var gpSchema: GPPropertySchema = gpDef.gpSchema if gpDef != null else null
	var gpRemoved: int = GPPropertyResolver.gpCleanOrphans(gpNode, gpSchema)
	if gpRemoved <= 0:
		return
	gpCanvas.gpGraph.gpGraphChanged.emit()
	gpCanvas.queue_redraw()
	gpHost._gpRefreshSelection()
	gpHost._gpSetState("lib.orphans_cleaned", [gpRemoved])


# React to an attribute edit in the edge form: route each key to the matching undoable
# intent on the edit service, then repaint and rebuild the form (so kind-dependent fields
# like signal_type vs dn/medium/insulation show or hide according to the new kind).
# 响应边表单中的属性编辑：把每个键路由到编辑服务上对应的可撤销意图，随后重绘并重建表单
#（使依赖类型的字段——signal_type 与 dn/medium/insulation——按新类型正确显隐）。

# M12: reconcile a freshly opened drawing against the CURRENT library. Renamed fields carry
# their values across; deleted fields leave ORPHANS that are kept (never swept) and merely
# counted, so the user decides whether to clean them.
# M12：把刚打开的图纸与**当前**图元库对账。改名字段带着取值迁移；删除字段留下孤儿值
# —— 保留（绝不自动清扫）并只做计数，是否清理由用户决定。
func gpReconcileLibraryDrift(gpGraph: GPPIDGraph) -> void:
	if gpGraph == null:
		return
	var gpLive: Dictionary = GPPropertyResolver.gpFingerprintsFor(gpHost.gpDefs)
	var gpDrift: Array[String] = GPPropertyResolver.gpDriftedSymbols(
		gpLive, gpGraph.gpSchemaFingerprints)
	# Adopt the live fingerprints: from here on this drawing is "as of this library".
	# 采用当前指纹：从此本图纸即「对应此版本的库」。
	gpGraph.gpSchemaFingerprints = gpLive.duplicate()
	if gpDrift.is_empty():
		return
	var gpMigrated: int = GPPropertyResolver.gpMigrateGraph(gpGraph, gpHost.gpDefs)
	var gpOrphans: int = GPPropertyResolver.gpOrphanCount(gpGraph, gpHost.gpDefs)
	gpHost._gpSetState("lib.drift", [gpDrift.size(), gpMigrated, gpOrphans])

# Hand the live library to the inspector so its "更换图元" dropdown follows every reload.
# 把活动库交给属性面板，使其「更换图元」下拉跟随每次库重载。
func gpSyncInspectorDefs() -> void:
	if gpHost.gpInspector != null:
		gpHost.gpInspector.gpHost.gpDefs = gpHost.gpDefs

# Swap one instance onto another symbol (M10). uid, tag, property values and every
# connection survive; only gpSymbolId changes. Missing ports are downgraded to the node
# centre rather than severed, and the count is surfaced as a warning.
# 把某个实例换到另一个图元上（M10）。uid、位号、属性值与全部连接都保留，只有 gpSymbolId 变更。
# 缺失的端口降级到图元中心而非被切断，并把数量以警告形式告知用户。
func gpOnSymbolSwap(gpNodeId: String, gpNewSymbolId: String) -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	var gpNewDef: GPSymbolDef = gpHost._gpDefFor(gpNewSymbolId)
	if gpNewDef == null:
		gpHost._gpSetState("swap.no_such_symbol", [gpNewSymbolId])
		return
	if not gpCanvas.gpActions.gpReplaceSymbol(gpNodeId, gpNewDef):
		return
	gpCanvas.queue_redraw()
	gpHost._gpRefreshSelection()
	# "Allowed but warned" (decided 2026-09-09): the pipes still connect, they just lost the
	# exact nozzle they were drawn onto — the user decides whether to re-seat them.
	# 「允许但警告」（2026-09-09 拍板）：管路仍然连通，只是失去了原本吸附的管口
	# —— 是否重新落位由用户决定。
	var gpDowngraded: Array[String] = gpCanvas.gpActions.gpLastSwapWarning
	if gpDowngraded.size() > 0:
		gpHost._gpSetState("swap.warn_ports", [gpDowngraded.size()])
	else:
		gpHost._gpSetState("swap.done", [I18n.gpTr(gpNewDef.gpDisplayName, gpNewDef.gpDisplayName)])

# Delete a symbol from the library and re-render the left palette. gpDefs shares identity
# with the live library array, so it already shrank; gpPopulate re-renders the views.
# 从图元库删除图元并重渲染左侧图元库。gpDefs 与活动库数组共享身份、已随之缩减；gpPopulate 重渲染。
func gpDeleteSymbolAndRefresh(gpId: String) -> void:
	GPSymbolLibrary.gpDeleteDef(gpId)
	gpHost.gpLeftDock.gpPopulate(gpHost.gpDefs)
	gpHost._gpSetState("status.symbol_deleted", [gpId])


# ============================ canvas changes ============================
# ============================ 画布变化 ============================
# React to graph changes by refreshing the inspector for the current selection.
# 图变化时刷新当前选中的属性面板。

# Remove every placed instance of the symbol from all sheets (and their edges), then delete
# it from the library and refresh the palette.
# 从所有图纸移除该图元的全部已放置实例（及其连线），再从图元库删除并重渲染图元库。
func gpCascadeDeleteSymbol(gpId: String) -> void:
	for gpC in gpHost.gpCenter.gpAllCanvases():
		if gpC.gpGraph != null:
			var gpRemoved: int = gpC.gpGraph.gpRemoveSymbolInstances(gpId)
			if gpRemoved > 0:
				gpC.gpClearSelection()
				gpC.queue_redraw()
				# (M2) No manual emit any more: gpRemoveSymbolInstances emits the core graph
				# signal, and the canvas now binds that signal and funnels it to the bus.
				# Previously the UI had to remember to emit "on behalf of" the data layer.
				# （M2）不再手动发射：gpRemoveSymbolInstances 会发射 core 图信号，画布已绑定
				# 该信号并汇入总线。此前 UI 必须记得「代数据层」发射一次。
	gpDeleteSymbolAndRefresh(gpId)

# Ask the user to confirm deletion when the symbol is in use on the canvas. Cascade removal
# of placed instances happens only after the user confirms (no silent data loss).
# 图元正在画布使用时，征求删除确认。仅在用户确认后才级联清理画布实例（避免静默丢数据）。
func gpConfirmCascadeDelete(gpId: String, gpTotal: int) -> void:
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("symbol_lib.delete_title")
	gpDlg.dialog_text = I18n.gpTr("symbol_lib.delete_used_confirm") % [gpTotal]
	# Confirmed carries no argument, so capture gpId in the callback. Free the dialog either way.
	# confirmed 信号不带参数，故在回调中捕获 gpId。无论确认或取消都释放对话框。
	gpDlg.confirmed.connect(func():
		gpCascadeDeleteSymbol(gpId)
		gpDlg.queue_free()
	)
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpHost.add_child(gpDlg)
	gpDlg.popup_centered()

func gpOnSymbolDeleteRequested(gpId: String) -> void:
	var gpTotal: int = 0
	for gpC in gpHost.gpCenter.gpAllCanvases():
		if gpC.gpGraph != null:
			gpTotal += gpC.gpGraph.gpCountSymbolInstances(gpId)
	if gpTotal == 0:
		gpDeleteSymbolAndRefresh(gpId)
		return
	gpConfirmCascadeDelete(gpId, gpTotal)
