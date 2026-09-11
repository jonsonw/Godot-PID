class_name GPInspector
extends ScrollContainer

# Property panel (right dock, "属性" tab) — M10 rebuild.
# 属性面板（右栏「属性」页）—— M10 重建。
#
# What this panel shows, in order / 本面板自上而下显示：
#   1. the SYMBOL NAME (read-only) — the library type, whose home is this panel and never
#      the canvas; plus a category-grouped dropdown to SWAP the symbol;
#      图元名称（只读）—— 库里的类型，它的家是本面板而非画布；外加按类目分组的
#      「更换图元」下拉；
#   2. 位号 (tag) and 名称 (multi-language) — the instance identity the user owns;
#      位号与名称（多语言）—— 用户自有的实例标识；
#   3. label placement (anchor) — the coarse choice; fine dragging happens on the canvas (M10b);
#      标签位置（锚点）—— 粗粒度选择；精细拖拽在画布上完成（M10b）；
#   4. the typed property fields resolved from the LIBRARY schema + this instance's values
#      (GPPropertyForm + GPPropertyResolver), grouped and ordered by the schema itself.
#      由**库 schema** 与本实例取值解析出的类型化属性字段（GPPropertyForm + GPPropertyResolver），
#      分组与顺序由 schema 自身决定。
#
# Two rules that make "edit the library, every project follows" true / 两条让
# 「改图元库、全项目同步」成立的规则：
#   - field DEFINITIONS are read from gpDef.gpSchema and never copied into the node;
#     字段**定义**读自 gpDef.gpSchema，绝不复制进节点；
#   - field VALUES are read through GPPropertyResolver (default vs override by `has()`).
#     字段**取值**经 GPPropertyResolver 读取（用 `has()` 区分默认与覆盖）。
#
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# An attribute was edited: node id, attribute key, new value.
# Reserved keys: "tag", "name:<locale>", "label_anchor"; anything else is a property key.
# 属性被编辑：节点 id、属性键、新值。
# 保留键："tag"、"name:<语种>"、"label_anchor"；其余一律视为属性键。
signal gpAttrChanged(gpId: String, key: String, val)

# An edge attribute was edited: edge id, attribute key, new value.
# 边属性被编辑：边 id、属性键、新值。
signal gpEdgeAttrChanged(gpEdgeId: String, key: String, val)

# The user picked a different symbol in the swap dropdown: node id, new symbol id.
# 用户在「更换图元」下拉中选了另一个图元：节点 id、新图元 id。
signal gpSymbolSwapRequested(gpNodeId: String, gpNewSymbolId: String)

# One edit applied to a whole selection: node ids, attribute key, new value (M11).
# Batched on purpose: the host turns the whole id set into ONE undo step.
# 一次编辑作用到整个选择集：节点 id 数组、属性键、新值（M11）。
# 刻意成批发送：宿主据此把整个 id 集合合成**一个**撤销步。
signal gpBatchAttrChanged(gpIds: Array[String], key: String, val)

# The user asked to drop this instance's orphaned values (M12). Explicit by design: an
# orphan is a value the user typed, so only the user may discard it.
# 用户请求清除本实例的孤儿值（M12）。刻意要求显式：孤儿是用户录入的值，
# 只有用户本人才能丢弃它。
signal gpCleanOrphansRequested(gpNodeId: String)

# Key prefix for a multi-language name edit (e.g. "name:zh_CN").
# 多语言名称编辑的键前缀（如 "name:zh_CN"）。
const GP_NAME_PREFIX: String = "name:"

# Minimum width of the property label column (left column of the 2-column inspector).
# 属性标签列（两列属性面板的左列）最小宽度。
const GP_LABEL_MIN_W: float = 150.0

# Root container for the form widgets.
# 表单控件的根容器。
var gpFormRoot: VBoxContainer

# Symbol definition of the currently inspected node.
# 当前查看节点的图元定义。
var gpCurrentDef: GPSymbolDef = null

# Reference to the currently inspected node object (the authoritative graph node).
# 当前查看节点对象的引用（权威的图节点）。
var gpCurrentNode: GPPIDNode = null

# Reference to the currently inspected edge object (authoritative graph edge). null when a node
# (or nothing) is shown. Only one of gpCurrentNode / gpCurrentEdge is non-null at a time.
# 当前查看边的引用（权威的图边）。显示节点（或无）时为 null。gpCurrentNode 与 gpCurrentEdge
# 同一时刻仅一个非 null。
var gpCurrentEdge: GPPIDEdge = null

# Every symbol definition in the library, for the swap dropdown. Owned by the shell, which
# re-assigns it whenever the library is reloaded.
# 图元库中的全部图元定义，供「更换图元」下拉使用。由外壳持有，库重载时重新赋值。
var gpDefs: Array[GPSymbolDef] = []

# Symbol ids parallel to the swap dropdown's items, rebuilt with the form.
# 与「更换图元」下拉各项一一对应的图元 id，随表单重建。
var _gpSwapIds: Array[String] = []

# Non-empty when several instances of the SAME symbol are selected: every edit is emitted
# once per id, so one keystroke lands on the whole selection (M10 "多选批量生效").
# 选中同一图元的多个实例时非空：每次编辑按 id 各发一次，一次录入落到整个选择集
#（M10「多选批量生效」）。
var _gpBatchIds: Array[String] = []

# The nodes behind _gpBatchIds, kept so a locale change can rebuild the batch form.
# _gpBatchIds 对应的节点，使语言切换时能重建批量表单。
var _gpBatchNodes: Array[GPPIDNode] = []


# Find the form root and show the empty hint.
# 找到表单根并显示空提示。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	gpFormRoot = $FormRoot
	_gpShowEmpty()
	I18n.gpLocaleChanged.connect(_gpOnLocaleChanged)


# ============================ node form / 节点表单 ============================

# Show the form for one selected node. Pass null def/node to clear.
# 显示选中节点的表单。def / node 为 null 时清空。
func gpShow(gpDef: GPSymbolDef, gpNode: GPPIDNode) -> void:
	_gpBatchIds = []
	_gpBatchNodes = []
	# A typed array is built explicitly: passing a bare `[]` literal into a typed
	# Array[GPPIDNode] parameter is a runtime type error in Godot 4.
	# 显式构建类型化数组：把裸 `[]` 字面量传给类型化的 Array[GPPIDNode] 参数
	# 在 Godot 4 中是运行时类型错误。
	var gpNodes: Array[GPPIDNode] = []
	if gpNode != null:
		gpNodes.append(gpNode)
	_gpBuildNodeForm(gpDef, gpNodes)


# Show the form for several selected instances of the SAME symbol. Edits apply to all of them.
# 显示同一图元的多个选中实例的表单。编辑将作用于全部实例。
# Mixed-type selections must NOT call this: a property that only some instances declare would
# be written onto instances that never had it. The shell calls gpShow for those.
# 混合类型选择**不可**调用本方法：只有部分实例声明的属性会被写到从未有过该属性的实例上。
# 外壳对混合选择调用 gpShow。
func gpShowMulti(gpDef: GPSymbolDef, gpNodes: Array[GPPIDNode]) -> void:
	_gpBatchNodes = []
	_gpBatchIds = []
	for gpN in gpNodes:
		if gpN == null:
			continue
		_gpBatchNodes.append(gpN)
		_gpBatchIds.append(gpN.gpInstanceId)
	if _gpBatchNodes.is_empty():
		gpShow(null, null)
		return
	_gpBuildNodeForm(gpDef, _gpBatchNodes)


# Build the shared node form. gpNodes is 1 (single) or N (batch) instances of gpDef.
# 构建共用的节点表单。gpNodes 为 gpDef 的 1 个（单选）或 N 个（批量）实例。
func _gpBuildNodeForm(gpDef: GPSymbolDef, gpNodes: Array[GPPIDNode]) -> void:
	_gpClearForm()
	gpCurrentEdge = null
	gpCurrentDef = gpDef
	gpCurrentNode = gpNodes[0] if not gpNodes.is_empty() else null
	if gpDef == null or gpNodes.is_empty():
		_gpShowEmpty()
		return

	var gpPrimary: GPPIDNode = gpNodes[0]
	var gpIsBatch: bool = gpNodes.size() > 1

	# ---- header: the library symbol name, read-only ----
	# ---- 标题：库图元名称，只读 ----
	_gpAddHead(I18n.gpTr(gpDef.gpDisplayName, gpDef.gpDisplayName))
	_gpAddNote("%s：%s" % [I18n.gpTr("inspector.symbol_id"), gpDef.gpId])
	if gpIsBatch:
		_gpAddNote(I18n.gpTr("inspector.batch") % [gpNodes.size()])

	# ---- swap dropdown: every library symbol, grouped by category ----
	# ---- 更换图元下拉：库内全部图元，按类目分组 ----
	_gpAddSwapRow(gpDef)

	# ---- identity: tag + multi-language names ----
	# ---- 标识：位号 + 多语言名称 ----
	_gpAddHead(I18n.gpTr("inspector.identity"))
	# The tag is read-only in batch mode: tags are unique project-wide, so one value cannot
	# legitimately be written onto several instances (GPBatchSetPropertyCommand refuses it too).
	# 批量模式下位号为只读：位号工程级唯一，一个值不可能合法地写到多个实例上
	#（GPBatchSetPropertyCommand 同样会拒绝）。
	_gpAddTextField(I18n.gpTr("inspector.tag"), _gpSharedTag(gpNodes), "tag", gpIsBatch)
	_gpAddTextField(I18n.gpTr("inspector.name_zh"),
		_gpSharedName(gpNodes, GPPropertyResolver.GP_FALLBACK_LOCALE),
		GP_NAME_PREFIX + GPPropertyResolver.GP_FALLBACK_LOCALE, false)
	_gpAddTextField(I18n.gpTr("inspector.name_en"), _gpSharedName(gpNodes, "en_US"),
		GP_NAME_PREFIX + "en_US", false)

	# ---- label placement ----
	# ---- 标签位置 ----
	_gpAddHead(I18n.gpTr("inspector.label"))
	_gpAddAnchorRow(gpPrimary)

	# ---- typed property fields, straight from the library schema ----
	# ---- 类型化属性字段，直接来自库 schema ----
	var gpSchema: GPPropertySchema = gpDef.gpSchema
	var gpPropsList: Array = []
	for gpN in gpNodes:
		gpPropsList.append(gpN.gpProps)
	if gpSchema == null or gpSchema.gpFields.is_empty():
		_gpAddHead(I18n.gpTr("inspector.properties"))
		_gpAddNote(I18n.gpTr("inspector.no_props"))
	else:
		for gpSec in GPPropertyForm.gpSections(gpSchema, gpPrimary.gpProps):
			_gpAddHead(GPPropertyForm.gpSectionTitle(str(gpSec["group"]),
				(gpSec["fields"] as Array).size()))
			for gpRow in (gpSec["fields"] as Array):
				_gpAddPropertyRow(gpRow, gpSchema, gpPropsList, gpIsBatch)

	# ---- orphans: values the library no longer declares, kept on purpose ----
	# ---- 孤儿：库中已不再声明、但刻意保留的取值 ----
	var gpOrphans: Array[Dictionary] = GPPropertyForm.gpOrphanRows(gpSchema, gpPrimary.gpProps)
	if not gpOrphans.is_empty():
		_gpAddHead(I18n.gpTr("inspector.orphan"))
		for gpRow in gpOrphans:
			_gpAddTextField(str(gpRow["key"]), str(gpRow["value"]), "", true)
		# Cleaning is ONE explicit button, never an automatic sweep.
		# 清理是**一个明确的按钮**，绝不是自动清扫。
		var gpBtn: Button = Button.new()
		gpBtn.text = I18n.gpTr("inspector.clean_orphans") % [gpOrphans.size()]
		gpBtn.size_flags_horizontal = SIZE_EXPAND_FILL
		gpBtn.pressed.connect(func() -> void:
			if gpCurrentNode != null:
				gpCleanOrphansRequested.emit(gpCurrentNode.gpInstanceId))
		gpFormRoot.add_child(gpBtn)


# ============================ swap dropdown / 更换图元下拉 ============================

# The category-grouped "change symbol" dropdown. Selecting an entry asks the shell to run the
# swap (this panel owns no graph), which keeps uid / tag / connections intact.
# 按类目分组的「更换图元」下拉。选中某项即请求外壳执行更换（本面板不持有图），
# 从而保住 uid / 位号 / 连接。
func _gpAddSwapRow(gpCurDef: GPSymbolDef) -> void:
	var gpRow: HBoxContainer = _gpFieldRow(I18n.gpTr("inspector.swap"))
	var gpOpt: OptionButton = OptionButton.new()
	gpOpt.size_flags_horizontal = SIZE_EXPAND_FILL
	_gpSwapIds = []

	var gpRows: Array[Dictionary] = []
	for gpD in gpDefs:
		if gpD == null:
			continue
		var gpEntry: Dictionary = {}
		gpEntry["cat"] = gpD.gpCategory
		gpEntry["name"] = gpD.gpDisplayName
		gpEntry["id"] = gpD.gpId
		gpRows.append(gpEntry)
	# Category first, then display name: a 40-entry library must stay scannable.
	# 先按类目、再按显示名：40 项的库也必须一眼可扫。
	gpRows.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
		if str(gpA["cat"]) != str(gpB["cat"]):
			return str(gpA["cat"]) < str(gpB["cat"])
		return str(gpA["name"]) < str(gpB["name"]))

	var gpLastCat: String = ""
	var gpSelIdx: int = -1
	for gpR in gpRows:
		if gpR["cat"] != gpLastCat:
			if gpLastCat != "":
				gpOpt.add_separator()
			gpLastCat = str(gpR["cat"])
		var gpIdx: int = _gpSwapIds.size()
		gpOpt.add_item("%s · %s" % [I18n.gpTr(str(gpR["cat"]), str(gpR["cat"])),
			str(gpR["name"])], gpIdx)
		_gpSwapIds.append(str(gpR["id"]))
		if str(gpR["id"]) == gpCurDef.gpId:
			gpSelIdx = gpIdx
	if gpSelIdx >= 0:
		gpOpt.select(gpSelIdx)
	else:
		gpOpt.disabled = true
	# A symbol swap changes which ports exist, so it is deliberately NOT batched: the shell
	# applies it to the primary node where the user can see the result.
	# 换图元会改变端口集合，故刻意**不做**批量：由外壳作用于主节点，用户能立刻看到结果。
	gpOpt.item_selected.connect(func(gpI: int) -> void:
		if gpCurrentNode == null:
			return
		if gpI < 0 or gpI >= _gpSwapIds.size():
			return
		gpSymbolSwapRequested.emit(gpCurrentNode.gpInstanceId, _gpSwapIds[gpI]))
	gpRow.add_child(gpOpt)


# ============================ property rows / 属性行 ============================

# One schema-declared field. gpIsBatch switches the shown value to the shared one and blanks
# the control when the instances disagree, so nothing is overwritten by accident.
# 一个 schema 声明的字段。gpIsBatch 时改用「共有取值」显示，实例不一致则留空，
# 避免不小心覆盖全部。
func _gpAddPropertyRow(gpRow: Dictionary, gpSchema: GPPropertySchema,
		gpPropsList: Array, gpIsBatch: bool) -> void:
	var gpKey: String = str(gpRow["key"])
	var gpKind: int = int(gpRow["kind"])
	var gpReadOnly: bool = bool(gpRow["read_only"])
	var gpLabel: String = str(gpRow["label"])
	if bool(gpRow["required"]):
		gpLabel = "%s %s" % [gpLabel, I18n.gpTr("inspector.required")]

	var gpValue: Variant = gpRow["value"]
	var gpOverridden: bool = bool(gpRow["overridden"])
	if gpIsBatch:
		var gpShared: Dictionary = GPPropertyForm.gpSharedValue(gpSchema, gpPropsList, gpKey)
		gpValue = gpShared["value"]
		gpOverridden = GPPropertyForm.gpAllOverridden(gpPropsList, gpKey)
		if not bool(gpShared["same"]):
			gpValue = ""

	# Not overridden => the value is inherited from the library; say so, so an edit is a
	# deliberate choice rather than an invisible one.
	# 未覆盖 => 取值继承自库；明确标出，使「覆盖」成为主动选择而非无形发生。
	if not gpOverridden:
		gpLabel = "%s  (%s)" % [gpLabel, I18n.gpTr("inspector.default")]

	match gpKind:
		GPPropertyDef.GPKind.GP_BOOL:
			_gpAddBoolField(gpLabel, bool(gpValue), gpKey, gpReadOnly)
		GPPropertyDef.GPKind.GP_ENUM:
			_gpAddEnumField(gpLabel, (gpRow["options"] as Array), str(gpValue), gpKey, gpReadOnly)
		GPPropertyDef.GPKind.GP_INT, GPPropertyDef.GPKind.GP_FLOAT:
			_gpAddNumberField(gpLabel, gpValue, float(gpRow["min"]), float(gpRow["max"]),
				str(gpRow["unit"]), gpKind, gpKey, gpReadOnly)
		GPPropertyDef.GPKind.GP_MULTILANG:
			_gpAddTextField(gpLabel, _gpMultilangText(gpValue), gpKey, gpReadOnly)
		_:
			# GP_STRING / GP_TEXT: a single-line field. Committing on Enter (not per keystroke)
			# keeps one edit == one undo step once M11 lands.
			# GP_STRING / GP_TEXT：单行输入。回车提交（而非逐键）可保证「一次编辑 = 一个撤销步」
			# —— M11 落地后即成立。
			_gpAddTextField(gpLabel, str(gpValue), gpKey, gpReadOnly)


# Text stored under the panel's primary locale inside a MULTILANG value.
# 取 MULTILANG 取值中「面板主语种」下的文本。
func _gpMultilangText(gpValue: Variant) -> String:
	if gpValue is Dictionary:
		var gpD: Dictionary = gpValue as Dictionary
		return str(gpD.get(GPPropertyResolver.GP_FALLBACK_LOCALE, ""))
	return str(gpValue)


# ============================ widget helpers / 控件辅助 ============================

# Announce one edit. In batch mode the WHOLE selection travels in a single signal so the host
# can record one undo step (M11); emitting once per node would need N presses of Ctrl+Z.
# 宣告一次编辑。批量模式下**整个选择集**装在单个信号里发出，使宿主记录一个撤销步（M11）；
# 每节点发一次会让用户按 N 次 Ctrl+Z。
func _gpEmit(gpKey: String, gpVal: Variant) -> void:
	if gpKey == "":
		return
	if _gpBatchIds.size() > 1:
		gpBatchAttrChanged.emit(_gpBatchIds, gpKey, gpVal)
		return
	if gpCurrentNode == null:
		return
	gpAttrChanged.emit(gpCurrentNode.gpInstanceId, gpKey, gpVal)


# The tag to show: shared across the batch, or "" when the instances disagree.
# 显示的位号：批量集共有的位号；实例不一致时为 ""。
func _gpSharedTag(gpNodes: Array[GPPIDNode]) -> String:
	if gpNodes.is_empty():
		return ""
	var gpFirst: String = gpNodes[0].gpTag
	for gpI in range(1, gpNodes.size()):
		if gpNodes[gpI].gpTag != gpFirst:
			return ""
	return gpFirst


# The name to show for one locale: shared across the batch, or "" when they disagree.
# 某语种下显示的名称：批量集共有的名称；实例不一致时为 ""。
func _gpSharedName(gpNodes: Array[GPPIDNode], gpLocale: String) -> String:
	if gpNodes.is_empty():
		return ""
	var gpFirst: String = str(gpNodes[0].gpNames.get(gpLocale, ""))
	for gpI in range(1, gpNodes.size()):
		if str(gpNodes[gpI].gpNames.get(gpLocale, "")) != gpFirst:
			return ""
	return gpFirst


# Label anchor rows: "follow the library" first, then the six anchors.
# 标签锚点选项：「跟随库默认」在前，其后六个锚点。
static func gpAnchorRows() -> Array[Dictionary]:
	return [
		{"value": GPPropertyResolver.GP_ANCHOR_UNSET, "key": "inspector.anchor_follow"},
		{"value": GPLabelAnchor.GPAnchor.GP_AUTO, "key": "anchor.auto"},
		{"value": GPLabelAnchor.GPAnchor.GP_BELOW, "key": "anchor.below"},
		{"value": GPLabelAnchor.GPAnchor.GP_ABOVE, "key": "anchor.above"},
		{"value": GPLabelAnchor.GPAnchor.GP_INSIDE, "key": "anchor.inside"},
		{"value": GPLabelAnchor.GPAnchor.GP_LEFT, "key": "anchor.left"},
		{"value": GPLabelAnchor.GPAnchor.GP_RIGHT, "key": "anchor.right"},
	]


# Dropdown for the coarse label position. Fine positioning is the canvas grip's job (M10b).
# 粗粒度标签位置下拉。精细定位由画布上的抓取点负责（M10b）。
func _gpAddAnchorRow(gpNode: GPPIDNode) -> void:
	var gpRow: HBoxContainer = _gpFieldRow(I18n.gpTr("inspector.anchor"))
	var gpOpt: OptionButton = OptionButton.new()
	gpOpt.size_flags_horizontal = SIZE_EXPAND_FILL
	var gpSelIdx: int = -1
	var gpIdx: int = 0
	for gpA in gpAnchorRows():
		gpOpt.add_item(I18n.gpTr(str(gpA["key"])), int(gpA["value"]))
		if int(gpA["value"]) == gpNode.gpLabelAnchor:
			gpSelIdx = gpIdx
		gpIdx += 1
	if gpSelIdx >= 0:
		gpOpt.select(gpSelIdx)
	gpOpt.item_selected.connect(func(gpI: int) -> void:
		_gpEmit("label_anchor", gpOpt.get_item_id(gpI)))
	gpRow.add_child(gpOpt)


func _gpAddHead(gpText: String) -> void:
	var gpLbl: Label = Label.new()
	gpLbl.text = "▾ %s" % gpText
	gpFormRoot.add_child(gpLbl)


# Build a "label | control" row: a fixed-min-width label on the left, the caller adds the
# control to the returned HBox. This is the standard 2-column inspector layout; it beats a
# GridContainer(columns=2) because section headers / notes can stay full-width (a GridContainer
# has no per-cell column span, so a header would steal only one cell).
# 构建「标签 | 控件」行：左侧固定最小宽标签，调用方把控件加到返回的 HBox。这是标准两列
# 属性面板布局；优于 GridContainer(columns=2)，因为小节标题 / 注释可保持整行（GridContainer
# 无单列跨列能力，标题只会占一格）。
func _gpFieldRow(gpLabelText: String) -> HBoxContainer:
	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 8)
	var gpLbl: Label = Label.new()
	gpLbl.text = gpLabelText
	gpLbl.custom_minimum_size = Vector2(GP_LABEL_MIN_W, 0.0)
	gpLbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	gpLbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gpRow.add_child(gpLbl)
	gpFormRoot.add_child(gpRow)
	return gpRow


func _gpAddNote(gpText: String) -> void:
	var gpLbl: Label = Label.new()
	gpLbl.text = gpText
	gpLbl.modulate = Color(0.55, 0.55, 0.6)
	gpFormRoot.add_child(gpLbl)


# Single-line text field. gpKey == "" renders a read-only display (used for orphans).
# 单行文本字段。gpKey 为 "" 时渲染为只读展示（用于孤儿字段）。
func _gpAddTextField(gpLabel: String, gpInitial: String, gpKey: String, gpReadOnly: bool) -> void:
	var gpRow: HBoxContainer = _gpFieldRow(gpLabel)
	var gpEdit: LineEdit = LineEdit.new()
	gpEdit.size_flags_horizontal = SIZE_EXPAND_FILL
	gpEdit.text = gpInitial
	if gpReadOnly or gpKey == "":
		gpEdit.editable = false
	else:
		gpEdit.text_submitted.connect(func(gpV: String) -> void:
			_gpEmit(gpKey, _gpValueFor(gpKey, gpV)))
	gpRow.add_child(gpEdit)


# MULTILANG fields keep every other locale: only the panel's primary locale is rewritten.
# MULTILANG 字段保留其他语种：只改写面板主语种。
func _gpValueFor(gpKey: String, gpText: String) -> Variant:
	if not gpKey.begins_with(GP_NAME_PREFIX) and gpCurrentDef != null:
		var gpF: GPPropertyDef = gpCurrentDef.gpSchema.gpFieldByKey(gpKey) if gpCurrentDef.gpSchema != null else null
		if gpF != null and gpF.gpKind == GPPropertyDef.GPKind.GP_MULTILANG and gpCurrentNode != null:
			var gpOut: Dictionary = {}
			if gpCurrentNode.gpProps.get(gpKey, null) is Dictionary:
				gpOut = (gpCurrentNode.gpProps[gpKey] as Dictionary).duplicate()
			gpOut[GPPropertyResolver.GP_FALLBACK_LOCALE] = gpText
			return gpOut
	return gpText


func _gpAddBoolField(gpLabel: String, gpInitial: bool, gpKey: String, gpReadOnly: bool) -> void:
	var gpRow: HBoxContainer = _gpFieldRow(gpLabel)
	var gpChk: CheckBox = CheckBox.new()
	gpChk.button_pressed = gpInitial
	gpChk.size_flags_horizontal = SIZE_EXPAND_FILL
	if gpReadOnly:
		gpChk.disabled = true
	else:
		gpChk.toggled.connect(func(gpV: bool) -> void:
			_gpEmit(gpKey, gpV))
	gpRow.add_child(gpChk)


func _gpAddEnumField(gpLabel: String, gpOptions: Array, gpCurrent: String,
		gpKey: String, gpReadOnly: bool) -> void:
	var gpRow: HBoxContainer = _gpFieldRow(gpLabel)
	var gpOpt: OptionButton = OptionButton.new()
	gpOpt.size_flags_horizontal = SIZE_EXPAND_FILL
	var gpValues: Array[String] = []
	for gpO in gpOptions:
		gpValues.append(str(gpO))
		gpOpt.add_item(str(gpO))
	var gpFound: int = gpValues.find(gpCurrent)
	if gpFound >= 0:
		gpOpt.select(gpFound)
	if gpReadOnly:
		gpOpt.disabled = true
	else:
		gpOpt.item_selected.connect(func(gpI: int) -> void:
			if gpI < 0 or gpI >= gpValues.size():
				return
			_gpEmit(gpKey, gpValues[gpI]))
	gpRow.add_child(gpOpt)


func _gpAddNumberField(gpLabel: String, gpInitial: Variant, gpMin: float, gpMax: float,
		gpUnit: String, gpKind: int, gpKey: String, gpReadOnly: bool) -> void:
	if gpUnit != "":
		gpLabel = "%s (%s)" % [gpLabel, gpUnit]
	var gpRow: HBoxContainer = _gpFieldRow(gpLabel)
	var gpSpin: SpinBox = SpinBox.new()
	gpSpin.size_flags_horizontal = SIZE_EXPAND_FILL
	# A ±INF bound is "no bound" (GPPropertyDef.GP_UNBOUNDED_*), which a SpinBox expresses as
	# a very wide range rather than as infinity.
	# ±INF 表示「不限」（GPPropertyDef.GP_UNBOUNDED_*），SpinBox 用极宽区间表达而非无穷。
	gpSpin.min_value = gpMin if is_finite(gpMin) else -1000000.0
	gpSpin.max_value = gpMax if is_finite(gpMax) else 1000000.0
	gpSpin.step = 1.0 if gpKind == GPPropertyDef.GPKind.GP_INT else 0.1
	gpSpin.value = float(gpInitial)
	if gpReadOnly:
		gpSpin.editable = false
	else:
		gpSpin.value_changed.connect(func(gpV: float) -> void:
			if gpKind == GPPropertyDef.GPKind.GP_INT:
				_gpEmit(gpKey, int(gpV))
			else:
				_gpEmit(gpKey, gpV))
	gpRow.add_child(gpSpin)


# Remove every child of the form root. / 清空表单根的全部子节点。
func _gpClearForm() -> void:
	for gpC in gpFormRoot.get_children():
		gpFormRoot.remove_child(gpC)
		gpC.queue_free()


# ============================ edge form / 边表单 ============================

# Show the form for a single selected edge. Pass null to clear.
# 显示单选边的表单。edge 为 null 时清空。
func gpShowEdge(gpEdge: GPPIDEdge) -> void:
	gpCurrentDef = null
	gpCurrentNode = null
	gpCurrentEdge = gpEdge
	_gpBatchIds = []
	_gpBatchNodes = []
	_gpClearForm()
	if gpEdge == null:
		_gpShowEmpty()
		return
	# Header with the line type name (localized line-type key).
	# 带本地化线型名的标题。
	var gpHead: Label = Label.new()
	gpHead.text = "▾ %s" % I18n.gpTr(GPEdgeStyle.gpLineTypeKey(gpEdge.gpKind, gpEdge.gpSignalType))
	gpFormRoot.add_child(gpHead)
	for gpKey in gpEdgeFieldKeys(gpEdge.gpKind):
		_gpAddEdgeField(gpEdge, gpKey)


# Field keys shown in the edge form for a given kind. SIGNAL edges hide the pipe-only
# fields (dn / medium / spec / insulation) because a signal line has none of them; PROCESS
# and UTILITY keep all eight. Pure + headless-testable (no widget built here).
# 给定类型下边表单显示的字段键。信号线隐藏管道专属字段（dn/medium/spec/insulation），
# 因信号线没有这些；PROCESS 与 UTILITY 保留全部八个。纯函数、可 headless 测试（此处不建控件）。
static func gpEdgeFieldKeys(gpKind: String) -> Array[String]:
	var gpKeys: Array[String] = ["kind", "tag", "show_arrow", "show_tag"]
	if gpKind == GPPIDEdge.GP_SIGNAL:
		gpKeys.append("signal_type")
	else:
		gpKeys.append_array(["dn", "medium", "spec", "insulation"])
	return gpKeys


# Initial display values for an edge form (pure, headless-testable). tag is pre-filled from the
# edge; show_tag defaults to "draw for pipes, hide for signal lines".
# 边表单的初始显示值（纯函数，可 headless 测试）。tag 预填自边；show_tag 默认「管道画、信号线不画」。
static func gpEdgeInitialValues(gpEdge: GPPIDEdge) -> Dictionary:
	var gpOut: Dictionary = {}
	gpOut["kind"] = gpEdge.gpKind
	gpOut["signal_type"] = gpEdge.gpSignalType
	gpOut["tag"] = gpEdge.gpTag
	gpOut["dn"] = str(gpEdge.gpAttrs.get("dn", ""))
	gpOut["medium"] = str(gpEdge.gpAttrs.get("medium", ""))
	gpOut["spec"] = str(gpEdge.gpAttrs.get("spec", ""))
	gpOut["insulation"] = str(gpEdge.gpAttrs.get("insulation", ""))
	gpOut["show_arrow"] = bool(gpEdge.gpAttrs.get("show_arrow", true))
	gpOut["show_tag"] = bool(gpEdge.gpAttrs.get("show_tag", gpEdge.gpKind != GPPIDEdge.GP_SIGNAL))
	return gpOut


# Build one labeled control for an edge field and wire it to gpEdgeAttrChanged.
# 为边的一个字段构建带标签的控件，并接入 gpEdgeAttrChanged。
func _gpAddEdgeField(gpEdge: GPPIDEdge, gpKey: String) -> void:
	var gpRow: HBoxContainer = _gpFieldRow(I18n.gpTr("edge." + gpKey))
	match gpKey:
		"kind":
			_gpAddEnum(gpRow, gpEdge, "kind", ["PROCESS", "UTILITY", "SIGNAL"],
				["edge.kind_process", "edge.kind_utility", "edge.kind_signal"], gpEdge.gpKind)
		"signal_type":
			var gpCur: String = gpEdge.gpSignalType if gpEdge.gpSignalType != "" else "ELECTRIC"
			_gpAddEnum(gpRow, gpEdge, "signal_type",
				["ELECTRIC", "PNEUMATIC", "HYDRAULIC", "DATA", "CAPILLARY"],
				["edge.type_electric", "edge.type_pneumatic", "edge.type_hydraulic",
				 "edge.type_data", "edge.type_capillary"], gpCur)
		"show_arrow", "show_tag":
			var gpDef: bool = true if gpKey == "show_arrow" else (gpEdge.gpKind != GPPIDEdge.GP_SIGNAL)
			var gpChk: CheckBox = CheckBox.new()
			gpChk.button_pressed = bool(gpEdge.gpAttrs.get(gpKey, gpDef))
			gpChk.size_flags_horizontal = SIZE_EXPAND_FILL
			gpChk.toggled.connect(func(gpV: bool) -> void:
				gpEdgeAttrChanged.emit(gpEdge.gpInstanceId, gpKey, gpV))
			gpRow.add_child(gpChk)
		_:
			# tag / dn / medium / spec / insulation -> a single-line text field.
			# tag / dn / medium / spec / insulation -> 单行文本字段。
			var gpEdit: LineEdit = LineEdit.new()
			gpEdit.size_flags_horizontal = SIZE_EXPAND_FILL
			if gpKey == "tag":
				gpEdit.text = gpEdge.gpTag
			else:
				gpEdit.text = str(gpEdge.gpAttrs.get(gpKey, ""))
			# Commit on Enter, not on every keystroke, so the form is not rebuilt mid-typing.
			# 在回车时提交而非每次按键，避免输入途中重建表单。
			gpEdit.text_submitted.connect(func(gpV: String) -> void:
				gpEdgeAttrChanged.emit(gpEdge.gpInstanceId, gpKey, gpV))
			gpRow.add_child(gpEdit)


# Build an OptionButton from parallel value / i18n-key arrays and emit the raw value on select.
# 由「值数组 / i18n 键数组」构建下拉框，选中时 emit 原始值。
func _gpAddEnum(gpParent: Container, gpEdge: GPPIDEdge, gpKey: String, gpValues: Array[String],
		gpTextKeys: Array[String], gpCurrent: String) -> void:
	var gpOpt: OptionButton = OptionButton.new()
	gpOpt.size_flags_horizontal = SIZE_EXPAND_FILL
	var gpFound: int = -1
	for gpI in range(gpValues.size()):
		gpOpt.add_item(I18n.gpTr(gpTextKeys[gpI]))
		if gpValues[gpI] == gpCurrent:
			gpFound = gpI
	if gpFound >= 0:
		gpOpt.select(gpFound)
	gpOpt.item_selected.connect(func(gpI: int) -> void:
		gpEdgeAttrChanged.emit(gpEdge.gpInstanceId, gpKey, gpValues[gpI]))
	gpParent.add_child(gpOpt)


# Show the empty-selection hint. / 显示未选中提示。
func _gpShowEmpty() -> void:
	gpCurrentDef = null
	gpCurrentNode = null
	gpCurrentEdge = null
	_gpBatchIds = []
	_gpBatchNodes = []
	if gpFormRoot == null:
		return
	_gpClearForm()
	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("symbol_lib.select_hint")
	gpFormRoot.add_child(gpHint)


# Rebuild the form when the locale changes.
# 语言变化时重建表单。
func _gpOnLocaleChanged(_gpLocale: String) -> void:
	if gpCurrentEdge != null:
		gpShowEdge(gpCurrentEdge)
	elif _gpBatchNodes.size() > 1:
		gpShowMulti(gpCurrentDef, _gpBatchNodes)
	elif gpCurrentDef == null or gpCurrentNode == null:
		_gpShowEmpty()
	else:
		gpShow(gpCurrentDef, gpCurrentNode)
