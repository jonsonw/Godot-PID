class_name GPSelectionCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Graph-to-panel sync bridge: subscribes to the event bus, refreshes inspector and status bar, writes panel edits back through the command layer
# 图与面板的双向同步桥：订阅事件总线刷新属性面板与状态栏，并把面板改值经命令层回写
#
# WHY THIS EXISTS / 为何存在（架构优化建议 §3.2）：
#   GPMainWindow was carrying many unrelated responsibilities in one file; this coordinator
#   owns the "Graph-to-panel sync bridge: subscribes to the event bus, refreshes inspector and status bar, writes panel edits back through the command layer" use case end to end, so the root keeps only assembly and forwarding.
#   GPMainWindow 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「图与面板的双向同步桥：订阅事件总线刷新属性面板与状态栏，并把面板改值经命令层回写」这一用例，
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


func gpOnEdgeAttrChanged(gpEdgeId: String, gpKey: String, gpVal) -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	match gpKey:
		"kind":
			# A SIGNAL edge must carry a signal type; default to ELECTRIC on the form's behalf.
			# 信号线必带信号类型；代表单默认取 ELECTRIC。
			if gpVal == GPPIDEdge.GP_SIGNAL:
				gpCanvas.gpActions.gpSetEdgeKind(gpEdgeId, GPPIDEdge.GP_SIGNAL, "ELECTRIC")
			else:
				gpCanvas.gpActions.gpSetEdgeKind(gpEdgeId, gpVal)
		"signal_type":
			var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpEdgeId)
			var gpKind: String = gpEdge.gpKind if gpEdge != null else GPPIDEdge.GP_SIGNAL
			gpCanvas.gpActions.gpSetEdgeKind(gpEdgeId, gpKind, gpVal)
		"tag":
			gpCanvas.gpActions.gpSetEdgeTag(gpEdgeId, str(gpVal))
		_:
			gpCanvas.gpActions.gpSetEdgeAttr(gpEdgeId, gpKey, gpVal)
	gpCanvas.queue_redraw()
	# Re-show the form so kind-dependent fields update (e.g. switching to SIGNAL hides dn/medium).
	# 重新显示表单，使依赖类型的字段随新类型更新（如切到信号线时隐藏 dn/medium）。
	gpRefreshSelection()


# ============================ menu ============================
# ============================ 菜单 ============================
# Dispatch menu actions.
# 分发菜单动作。

# Route one edit (single or batched) to the matching undoable intent on the edit service.
# 把一次编辑（单选或批量）路由到编辑服务上对应的可撤销意图。
func gpApplyAttr(gpIds: Array[String], gpKey: String, gpVal: Variant) -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null or gpIds.is_empty() or gpKey == "":
		return
	var gpActs: GPEditService = gpCanvas.gpActions
	var gpOk: bool = false
	if gpIds.size() == 1:
		var gpId: String = gpIds[0]
		if gpKey == "tag" or gpKey == "label":
			gpOk = gpActs.gpSetTag(gpId, str(gpVal))
		elif gpKey == "label_anchor":
			gpOk = gpActs.gpSetLabelAnchor(gpId, int(gpVal))
		elif gpKey.begins_with(GPInspector.GP_NAME_PREFIX):
			# "name:zh_CN" -> the locale is everything after the prefix.
			# "name:zh_CN" -> 前缀之后的部分即语种。
			gpOk = gpActs.gpSetName(gpId,
				gpKey.substr(GPInspector.GP_NAME_PREFIX.length()), str(gpVal))
		else:
			gpOk = gpActs.gpSetProperty(gpId, gpKey, gpVal)
	else:
		gpOk = gpActs.gpBatchSetProperty(gpIds, gpKey, gpVal)
	if gpOk:
		return
	# A refused edit explains itself (e.g. a duplicate tag); "nothing changed" stays silent.
	# 被拒绝的编辑会自己说明原因（如位号重复）；「无实际变化」则保持安静。
	if gpActs.gpLastRefusal != "":
		gpHost._gpSetState(gpActs.gpLastRefusal)

func gpOnBatchAttrChanged(gpIds: Array[String], gpKey: String, gpVal) -> void:
	gpApplyAttr(gpIds, gpKey, gpVal)

# React to an attribute edit in the inspector, and to the batched form of the same edit.
# 响应属性面板中的属性编辑，以及同一次编辑的批量形式。
# Reserved keys (M10): "tag", "name:<locale>", "label_anchor"; anything else is a property key.
# The historical "label" key is still accepted as a tag, so an older panel keeps working.
# 保留键（M10）："tag"、"name:<语种>"、"label_anchor"；其余一律视为属性键。
# 历史上的 "label" 键仍按位号处理，使旧面板继续可用。
#
# M11: every one of these now travels through an undoable command on the edit service, so
# Ctrl+Z reverses it and the dirty flag is set exactly once (driven by gpGraphChanged).
# M11：它们现在都经编辑服务上的可撤销命令落地，故 Ctrl+Z 可撤销，
# 且脏标记恰好置一次（由 gpGraphChanged 驱动）。
func gpOnAttrChanged(gpId: String, gpKey: String, gpVal) -> void:
	var gpIds: Array[String] = [gpId]
	gpApplyAttr(gpIds, gpKey, gpVal)

# ============================ selection / inspector ============================
# ============================ 选中 / 属性面板 ============================
# Refresh the inspector and info tab for the currently selected node.
# 为当前选中节点刷新属性面板与信息标签页。
func gpRefreshSelection() -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	# No active sheet (or nothing selected): clear the inspector.
	# 无活动图纸（或无选中）：清空属性面板。
	if gpCanvas == null:
		if gpHost.gpInspector != null:
			gpHost.gpInspector.gpShow(null, null)
		if gpHost.gpInfoLabel != null:
			gpHost.gpInfoLabel.text = I18n.gpTr("symbol_lib.no_selection")
		return
	var gpId: String = gpCanvas.gpSelectedId
	if gpId == "":
		# No node selected: before clearing the panel, show a single selected edge's form if any.
		# 未选中节点：在清空面板前，若单选了一条边则显示其表单。
		if gpCanvas.gpEdgeSel.size() == 1 and gpCanvas.gpGraph != null:
			var gpEdge: GPPIDEdge = gpCanvas.gpGraph.gpGetEdge(gpCanvas.gpEdgeSel[0])
			if gpEdge != null:
				gpHost.gpInspector.gpShowEdge(gpEdge)
				var gpType: String = I18n.gpTr(GPEdgeStyle.gpLineTypeKey(gpEdge.gpKind, gpEdge.gpSignalType))
				gpHost.gpInfoLabel.text = "%s：%s\n%s：%s" % [
					I18n.gpTr("info.id"), gpEdge.gpInstanceId,
					I18n.gpTr("edge.kind"), gpType]
				return
		gpHost.gpInspector.gpShow(null, null)
		gpHost.gpInfoLabel.text = I18n.gpTr("symbol_lib.no_selection")
		return

	var gpNode: GPPIDNode = gpHost._gpNodeFor(gpId)
	if gpNode == null:
		gpHost.gpInspector.gpShow(null, null)
		gpHost.gpInfoLabel.text = I18n.gpTr("symbol_lib.no_selection")
		return

	var gpDef: GPSymbolDef = gpHost._gpDefFor(gpNode.gpSymbolId)

	# Multi-select (M10): when every selected instance instantiates the SAME symbol, the panel
	# edits them as one batch. A mixed selection falls back to the primary node — writing a
	# property onto instances that never declared it would be silent data damage.
	# 多选（M10）：当所有选中实例实例化的是**同一**图元时，面板按批量编辑。
	# 混合选择回落到主节点 —— 把某属性写到从未声明它的实例上属于静默的数据破坏。
	var gpBatch: Array[GPPIDNode] = []
	var gpSameSymbol: bool = true
	for gpSelId in gpCanvas.gpSelection:
		var gpSelNode: GPPIDNode = gpHost._gpNodeFor(gpSelId)
		if gpSelNode == null:
			continue
		if gpSelNode.gpSymbolId != gpNode.gpSymbolId:
			gpSameSymbol = false
			break
		gpBatch.append(gpSelNode)
	if gpBatch.size() > 1 and gpSameSymbol:
		gpHost.gpInspector.gpShowMulti(gpDef, gpBatch)
	else:
		gpHost.gpInspector.gpShow(gpDef, gpNode)

	var gpCat: String = I18n.gpTr(gpDef.gpCategory) if gpDef else "—"
	var gpSize: String = str(gpDef.gpDefaultSize) if gpDef else "—"
	gpHost.gpInfoLabel.text = "%s：%s\n%s：%s\n%s：%s\n%s：%s" % [
		I18n.gpTr("info.id"), gpId,
		I18n.gpTr("info.type"), gpNode.gpSymbolId,
		I18n.gpTr("info.category"), gpCat,
		I18n.gpTr("info.size"), gpSize]

# Update the status bar from a canvas status snapshot.
# 根据画布状态快照更新状态栏。
func gpOnStatus(gpInfo: Dictionary) -> void:
	# No active sheet yet (e.g. very first frame before the initial tab exists): keep
	# the last snapshot and skip, to avoid touching a null canvas.
	# 尚无活动图纸（如首帧初始标签建立前）：保留上次快照并跳过，避免触碰空画布。
	if gpHost.gpActiveCanvas() == null:
		return
	gpHost.gpLastStatus = gpInfo
	var gpSel: String = gpInfo.get("selection", "")
	gpHost.gpSelLabel.text = I18n.gpTr("status.selected") % (gpSel if gpSel != "" else I18n.gpTr("status.none"))

	var gpWorld: Vector2 = gpInfo.get("world", Vector2.ZERO)
	gpHost.gpCoordLabel.text = I18n.gpTr("status.coord") % [int(gpWorld.x), int(gpWorld.y)]

	var gpZoom: float = gpInfo.get("zoom", 1.0)
	gpHost.gpZoomLabel.text = I18n.gpTr("status.zoom") % [int(gpZoom * 100.0)]
	# (M2) The old "diff the selection string, then refresh the inspector" block is gone:
	# selection changes now arrive as their own gpSelectionChanged event, so this handler
	# is once again ONLY about the status bar (its actual single responsibility).
	# （M2）原先「比对选中字符串再刷新属性面板」的代码块已删除：选中变化由独立的
	# gpSelectionChanged 事件送达，本处理函数恢复为只负责状态栏（真正的单一职责）。

# M2: selection is a first-class event again. Previously it was smuggled to the host inside
# the status snapshot, and _gpOnStatus had to diff the "selection" string to guess whether
# the inspector needed a refresh. The canvas now emits gpSelectionChanged explicitly.
# M2：选择重新成为一等事件。此前它被塞进状态快照，_gpOnStatus 必须比对 "selection"
# 字符串来猜测是否需要刷新属性面板；现在画布显式发射 gpSelectionChanged。
func gpOnSelectionChanged(_gpIds: Array[String] = []) -> void:
	gpRefreshSelection()

func gpOnGraphChanged(_gpGraph: GPPIDGraph = null) -> void:
	gpRefreshSelection()
