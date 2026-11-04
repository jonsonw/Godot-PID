class_name GPOffPageConnectDialog
extends ConfirmationDialog
# Copyright © 2026 Jonson Wang
#
# The "cross-sheet connection" dialog (ADR-43 / S3): pick the target sheet, then the target
# item (filterable by tag), then the port. Both creation paths land here — the out-of-frame
# draw AND "connect to another sheet…" on an existing connector — because they are the same
# question: "where does this line continue?".
# 「跨图纸连接」对话框（ADR-43 / S3）：选目标图纸 → 选目标对象（可按位号过滤）→ 选端口。
# 两条创建路径都汇到这里 —— 画线出界与对既有连接符右键「连接到其他图纸…」——
# 因为它们问的是同一个问题：「这条线在哪里续接？」。
#
# The dialog is MODEL-DRIVEN and decides nothing: it hands back a {sheet_id, node_id,
# port_id} ref and the COMMAND layer validates and executes. A dialog that builds edges
# itself could not be tested headless and would drift from the command's refusal rules.
# 对话框由**模型驱动**且不做任何决定：它只交回 {sheet_id, node_id, port_id} 引用，
# 校验与执行都由命令层完成。自己建边的对话框既无法 headless 测试，也会与命令的
# 拒绝规则分家。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Emitted on confirm with the chosen target ref.
# 确认时发射所选目标引用。
signal gpConnectChosen(gpTarget: Dictionary)

# All sheets of the project (the current one is excluded from the picker).
# 工程的全部图纸（当前图纸从选择器中排除）。
var _gpSheets: Array[GPSheet] = []

# The symbol library defs, for enumerating a node's ports.
# 图元库定义，用于枚举节点的端口。
var _gpDefs: Array[GPSymbolDef] = []

# The sheet id to exclude (the sheet the user is drawing on).
# 要排除的图纸 id（用户正在绘制的图纸）。
var _gpExcludeSheetId: String = ""

# A sheet to preselect (the inspector's peer-sheet dropdown routed here); "" = none.
# 要预选的图纸（属性面板的对端图纸下拉路由而来）；"" = 无。
var _gpPreselectSheetId: String = ""

var _gpSheetPick: OptionButton = null
var _gpFilter: LineEdit = null
var _gpItemList: ItemList = null
var _gpPortPick: OptionButton = null

# Content root; rebuilt on every gpSetup (same pattern as GPLineAttrsDialog).
# 内容根节点；每次 gpSetup 重建（与 GPLineAttrsDialog 同一模式）。
var _gpRoot: VBoxContainer = null

# sheet picker index -> GPSheet, so the handler never parses labels back.
# 图纸选择器下标 -> GPSheet，使处理函数绝不去反解标签文字。
var _gpSheetByIndex: Array[GPSheet] = []

# item list index -> node instance id, same rule.
# 列表下标 -> 节点实例 id，同一规则。
var _gpNodeByIndex: Array[String] = []


func _ready() -> void:
	title = I18n.gpTr("offpage.dlg_title")
	ok_button_text = I18n.gpTr("offpage.ok")
	cancel_button_text = I18n.gpTr("dialog.cancel")
	min_size = Vector2i(400, 380)
	confirmed.connect(_gpOnConfirmed)


# Populate and show. Safe to call repeatedly; the content is rebuilt each time. A non-empty
# gpPreselectSheetId opens the picker already sitting on that sheet (the inspector's
# peer-sheet dropdown hands its pick over here, so the user never chooses the sheet twice).
# 填充并显示。可重复调用；内容每次重建。gpPreselectSheetId 非空时选择器直接落在该图纸
#（属性面板的对端图纸下拉把所选图纸交到这里，用户不必选两次图纸）。
func gpSetup(gpSheets: Array[GPSheet], gpDefs: Array[GPSymbolDef],
		gpExcludeSheetId: String, gpPreselectSheetId: String = "") -> void:
	_gpSheets = gpSheets
	_gpDefs = gpDefs
	_gpExcludeSheetId = gpExcludeSheetId
	_gpPreselectSheetId = gpPreselectSheetId
	_gpBuildContent()
	popup_centered()


# The chosen target ref; {} when nothing valid is selected.
# 所选目标引用；未选中有效项时为 {}。
func gpResult() -> Dictionary:
	return _gpCurrentRef()


# ============================ UI ============================

func _gpBuildContent() -> void:
	if _gpRoot != null and is_instance_valid(_gpRoot):
		_gpRoot.queue_free()
	_gpRoot = VBoxContainer.new()
	_gpRoot.add_theme_constant_override("separation", 8)
	var gpRoot: VBoxContainer = _gpRoot
	# Sheet picker, ordered by DRAWING NUMBER (the number a flag will show); the ordering
	# helpers live on the core index so the inspector's dropdown shares the exact same order.
	# 图纸选择器，按**图号**排序（旗标显示的正是图号）；排序助手放在 core 索引上，
	# 使属性面板的下拉与这里共享**完全相同**的次序。
	gpRoot.add_child(_gpMakeLabel("offpage.target_sheet"))
	_gpSheetPick = OptionButton.new()
	_gpSheetByIndex = []
	var gpOrdered: Array[GPSheet] = []
	for gpS in _gpSheets:
		if gpS != null and gpS.gpId != _gpExcludeSheetId:
			gpOrdered.append(gpS)
	gpOrdered.sort_custom(GPOffPageIndex.gpSheetBefore)
	for gpI in range(gpOrdered.size()):
		var gpS: GPSheet = gpOrdered[gpI]
		_gpSheetPick.add_item(GPOffPageIndex.gpSheetLabel(gpS))
		_gpSheetByIndex.append(gpS)
	_gpSheetPick.item_selected.connect(_gpOnSheetPicked)
	gpRoot.add_child(_gpSheetPick)
	# Tag filter. / 位号过滤。
	gpRoot.add_child(_gpMakeLabel("offpage.filter"))
	_gpFilter = LineEdit.new()
	_gpFilter.placeholder_text = I18n.gpTr("offpage.filter")
	_gpFilter.text_changed.connect(_gpOnFilterChanged)
	gpRoot.add_child(_gpFilter)
	# Item list. / 对象列表。
	_gpItemList = ItemList.new()
	_gpItemList.custom_minimum_size = Vector2(0, 160)
	_gpItemList.item_selected.connect(_gpOnItemPicked)
	gpRoot.add_child(_gpItemList)
	# Port picker. / 端口选择器。
	gpRoot.add_child(_gpMakeLabel("offpage.port"))
	_gpPortPick = OptionButton.new()
	gpRoot.add_child(_gpPortPick)
	add_child(_gpRoot)
	if _gpSheetPick.item_count > 0:
		# Honour the preselect (inspector hand-off); fall back to the first sheet.
		# 应用预选（属性面板移交）；否则回落到第一张。
		var gpPre: int = 0
		for gpI in range(_gpSheetByIndex.size()):
			if _gpSheetByIndex[gpI].gpId == _gpPreselectSheetId:
				gpPre = gpI
				break
		_gpSheetPick.select(gpPre)
		_gpPopulateItems()
	_gpUpdateOk()


func _gpMakeLabel(gpKey: String) -> Label:
	var gpL: Label = Label.new()
	gpL.text = I18n.gpTr(gpKey)
	return gpL


func _gpSheetLabel(gpS: GPSheet) -> String:
	# Delegates to the shared core helper (the inspector dropdown reads the same labels).
	# 委托给共用的 core 助手（属性面板下拉读同一份标签）。
	return GPOffPageIndex.gpSheetLabel(gpS)


# Refill the item list from the picked sheet's graph, honoring the filter text.
# 依所选图纸的图重填对象列表，并应用过滤文字。
func _gpPopulateItems() -> void:
	_gpItemList.clear()
	_gpNodeByIndex = []
	var gpSheet: GPSheet = _gpPickedSheet()
	if gpSheet == null or gpSheet.gpGraph == null:
		_gpPopulatePorts("")
		_gpUpdateOk()
		return
	var gpNeedle: String = _gpFilter.text.strip_edges()
	for gpN in gpSheet.gpGraph.gpNodes:
		if gpN == null:
			continue
		# An item without a tag cannot be found by a reader of the drawing, so listing it
		# in a "pick a target" dialog would be noise.
		# 没有位号的对象在读图时无从指认，故「选目标」列表里列出它只是噪音。
		var gpTag: String = gpN.gpTag.strip_edges()
		if gpTag == "":
			continue
		if gpNeedle != "" and not gpTag.containsn(gpNeedle):
			continue
		_gpItemList.add_item(gpTag)
		_gpNodeByIndex.append(gpN.gpInstanceId)
	if _gpItemList.item_count > 0:
		_gpItemList.select(0)
		_gpPopulatePorts(_gpNodeByIndex[0])
	else:
		_gpPopulatePorts("")
	_gpUpdateOk()


# Ports of the picked node's symbol def, in def order (drawing order = intent order).
# 所选节点图元定义的端口，按定义次序（图面次序＝设计意图次序）。
func _gpPopulatePorts(gpNodeId: String) -> void:
	_gpPortPick.clear()
	if gpNodeId == "" or _gpPickedSheet() == null:
		return
	var gpNode: GPPIDNode = _gpPickedSheet().gpGraph.gpGetNode(gpNodeId)
	if gpNode == null:
		return
	var gpDef: GPSymbolDef = _gpDefFor(gpNode.gpSymbolId)
	if gpDef == null:
		return
	for gpP in gpDef.gpPorts:
		if gpP != null:
			_gpPortPick.add_item(gpP.gpName)
	if _gpPortPick.item_count > 0:
		_gpPortPick.select(0)


func _gpDefFor(gpSymbolId: String) -> GPSymbolDef:
	for gpD in _gpDefs:
		if gpD != null and gpD.gpId == gpSymbolId:
			return gpD
	return null


func _gpPickedSheet() -> GPSheet:
	var gpI: int = _gpSheetPick.get_selected_id()
	if _gpSheetPick.item_count == 0:
		return null
	return _gpSheetByIndex[_gpSheetPick.selected]


func _gpPickedNodeId() -> String:
	var gpSel: Array = _gpItemList.get_selected_items()
	if gpSel.is_empty():
		return ""
	var gpI: int = gpSel[0]
	return _gpNodeByIndex[gpI] if gpI >= 0 and gpI < _gpNodeByIndex.size() else ""


func _gpPickedPort() -> String:
	if _gpPortPick.item_count == 0 or _gpPortPick.selected < 0:
		return ""
	return _gpPortPick.get_item_text(_gpPortPick.selected)


# A complete ref is the OK gate: sheet + node + port, all three.
# 完整引用是 OK 的闸门：图纸 + 节点 + 端口，三者缺一不可。
func _gpCurrentRef() -> Dictionary:
	var gpSheet: GPSheet = _gpPickedSheet()
	var gpNodeId: String = _gpPickedNodeId()
	var gpPort: String = _gpPickedPort()
	if gpSheet == null or gpNodeId == "" or gpPort == "":
		return {}
	return {"sheet_id": gpSheet.gpId, "node_id": gpNodeId, "port_id": gpPort}


func _gpUpdateOk() -> void:
	get_ok_button().disabled = _gpCurrentRef().is_empty()


func _gpOnSheetPicked(_gpIdx: int) -> void:
	_gpPopulateItems()


func _gpOnFilterChanged(_gpText: String) -> void:
	_gpPopulateItems()


func _gpOnItemPicked(_gpIdx: int) -> void:
	_gpPopulatePorts(_gpPickedNodeId())
	_gpUpdateOk()


func _gpOnConfirmed() -> void:
	var gpRef: Dictionary = _gpCurrentRef()
	if not gpRef.is_empty():
		gpConnectChosen.emit(gpRef)
