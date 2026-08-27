class_name GPInspector
extends ScrollContainer

# Property panel (right dock, "属性" tab). Builds an editable form from the
# selected node's SymbolDef.gpAttrsSchema, plus a name/label field. Edits emit
# gpAttrChanged so the host writes them back into the PIDGraph node.
# 属性面板（右栏「属性」页）。按选中节点 SymbolDef.gpAttrsSchema 生成可编辑表单，
# 外加名称/标签字段。编辑 emit gpAttrChanged，由宿主写回 PIDGraph 节点。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# An attribute was edited: node id, attribute key, new value.
# 属性被编辑：节点 id、属性键、新值。
signal gpAttrChanged(gpId: String, key: String, val)

# Root container for the form widgets.
# 表单控件的根容器。
var gpFormRoot: VBoxContainer

# Symbol definition of the currently inspected node.
# 当前查看节点的图元定义。
var gpCurrentDef: GPSymbolDef = null

# Reference to the currently inspected node object (the authoritative graph node).
# 当前查看节点对象的引用（权威的图节点）。
var gpCurrentNode: GPPIDNode = null


# Find the form root and show the empty hint.
# 找到表单根并显示空提示。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	gpFormRoot = $FormRoot
	_gpShowEmpty()
	I18n.gpLocaleChanged.connect(_gpOnLocaleChanged)


# Show the form for a selected node. Pass null def/node to clear.
# 显示选中节点的表单。def / node 为 null 时清空。
func gpShow(gpDef: GPSymbolDef, gpNode: GPPIDNode) -> void:
	gpCurrentDef = gpDef
	gpCurrentNode = gpNode

	# Clear existing form.
	# 清空已有表单。
	for gpC in gpFormRoot.get_children():
		gpFormRoot.remove_child(gpC)
		gpC.queue_free()

	if gpDef == null or gpNode == null:
		_gpShowEmpty()
		return

	# Header with localized symbol name.
	# 带本地化图元名的标题。
	var gpHead: Label = Label.new()
	gpHead.text = "▾ %s" % I18n.gpTr(gpDef.gpDisplayName)
	gpFormRoot.add_child(gpHead)

	# ---- name / label field (always present) ----
	# ---- 名称 / 标签字段（始终存在） ----
	var gpNameLabel: Label = Label.new()
	gpNameLabel.text = I18n.gpTr("prop.label")
	gpFormRoot.add_child(gpNameLabel)
	var gpNameEdit: LineEdit = LineEdit.new()
	gpNameEdit.text = gpNode.gpTag
	gpNameEdit.size_flags_horizontal = SIZE_EXPAND_FILL
	gpNameEdit.text_changed.connect(func(gpV: String): gpAttrChanged.emit(gpNode.gpInstanceId, "label", gpV))
	gpFormRoot.add_child(gpNameEdit)

	# ---- schema-driven fields ----
	# ---- 按 schema 生成的字段 ----
	var gpSchema: Dictionary = gpDef.gpAttrsSchema
	if gpSchema.is_empty():
		var gpHint: Label = Label.new()
		gpHint.text = I18n.gpTr("symbol_lib.empty_attrs")
		gpFormRoot.add_child(gpHint)
		return

	for gpKey in gpSchema.keys():
		var gpSpec: Dictionary = gpSchema[gpKey]
		var gpFieldLabel: String = gpSpec.get("label", gpKey)
		var gpFieldType: String = gpSpec.get("type", "string")

		var gpLbl: Label = Label.new()
		gpLbl.text = I18n.gpTr(gpFieldLabel, gpFieldLabel)
		gpFormRoot.add_child(gpLbl)

		if gpFieldType == "enum":
			# Enum field: use an OptionButton.
			# 枚举字段：使用下拉选项按钮。
			var gpOpt: OptionButton = OptionButton.new()
			gpOpt.size_flags_horizontal = SIZE_EXPAND_FILL
			for gpO in gpSpec.get("options", []):
				gpOpt.add_item(String(gpO))
			var gpCur: String = String(gpNode.gpAttrValues.get(gpKey, ""))
			var gpFound: int = gpOpt.find_item_index(gpCur)
			if gpFound >= 0:
				gpOpt.select(gpFound)
			gpOpt.item_selected.connect(func(gpI: int): gpAttrChanged.emit(gpNode.gpInstanceId, gpKey, gpOpt.get_item_text(gpI)))
			gpFormRoot.add_child(gpOpt)
		else:
			# Default string field: use a LineEdit.
			# 默认字符串字段：使用单行输入框。
			var gpEdit: LineEdit = LineEdit.new()
			gpEdit.size_flags_horizontal = SIZE_EXPAND_FILL
			gpEdit.text = String(gpNode.gpAttrValues.get(gpKey, ""))
			gpEdit.text_changed.connect(func(gpV: String): gpAttrChanged.emit(gpNode.gpInstanceId, gpKey, gpV))
			gpFormRoot.add_child(gpEdit)


# Show the empty-selection hint.
# 显示未选中提示。
func _gpShowEmpty() -> void:
	gpCurrentDef = null
	gpCurrentNode = null
	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("symbol_lib.select_hint")
	gpFormRoot.add_child(gpHint)


# Rebuild the form when the locale changes.
# 语言变化时重建表单。
func _gpOnLocaleChanged(_gpLocale: String) -> void:
	if gpCurrentDef == null or gpCurrentNode == null:
		_gpShowEmpty()
	else:
		gpShow(gpCurrentDef, gpCurrentNode)
