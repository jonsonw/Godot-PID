class_name GPPIDToolbar
extends VBoxContainer

# Left symbol-library dock. The FRAME is built once here (title + search box +
# scroll container + tool group); the symbol BUTTONS are injected by code from
# SymbolLibrary so custom symbol packs drop in without touching the layout.
# 左侧图元库停靠栏。框架在此一次性搭好（标题 + 搜索框 + 滚动容器 + 工具组）；
# 图元按钮由代码按类目从 SymbolLibrary 注入，自定义图元包无需改布局即可接入。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# A symbol was picked from the library (its type id).
# 从图元库选中某图元（返回其 type id）。
signal gpSymbolPicked(type: String)
# A tool was selected: "select" / "connect" / "custom".
# 选中某工具：select（选择）/ connect（连线）/ custom（自定义图元）。
signal gpToolSelected(type: String)

var gpDefs: Array[GPSymbolDef] = []
var gpTitle: Label
var gpSearchBox: LineEdit
var gpListRoot: ScrollContainer
var gpSelBtn: Button
var gpConBtn: Button
var gpCustBtn: Button


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP

	# ---- frozen frame: title ----
	# ---- 固化框架：标题 ----
	gpTitle = Label.new()
	add_child(gpTitle)

	# ---- frozen frame: search box ----
	# ---- 固化框架：搜索框 ----
	gpSearchBox = LineEdit.new()
	gpSearchBox.text_changed.connect(_gpOnSearch)
	add_child(gpSearchBox)

	# ---- frozen frame: scroll container (symbols injected here) ----
	# ---- 固化框架：滚动容器（图元注入于此） ----
	gpListRoot = ScrollContainer.new()
	gpListRoot.size_flags_vertical = SIZE_EXPAND_FILL
	gpListRoot.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(gpListRoot)

	# ---- frozen frame: tool group ----
	# ---- 固化框架：工具组 ----
	var gpTools: HBoxContainer = HBoxContainer.new()
	gpSelBtn = Button.new()
	gpSelBtn.size_flags_horizontal = SIZE_EXPAND_FILL
	gpConBtn = Button.new()
	gpConBtn.size_flags_horizontal = SIZE_EXPAND_FILL
	gpCustBtn = Button.new()
	gpCustBtn.size_flags_horizontal = SIZE_EXPAND_FILL
	gpSelBtn.pressed.connect(func(): gpToolSelected.emit("select"))
	gpConBtn.pressed.connect(func(): gpToolSelected.emit("connect"))
	gpCustBtn.pressed.connect(func(): gpToolSelected.emit("custom"))
	gpTools.add_child(gpSelBtn)
	gpTools.add_child(gpConBtn)
	gpTools.add_child(gpCustBtn)
	add_child(gpTools)

	I18n.gpLocaleChanged.connect(_gpRefreshLocale)
	_gpRefreshLocale(I18n.gpLocale)


# Inject symbols grouped by category. Call once after assigning the def set.
# 按类目注入图元。赋值图元集后调用一次。
func gpPopulate(gpDefsIn: Array[GPSymbolDef]) -> void:
	gpDefs = gpDefsIn
	_gpRender(gpDefs)


func _gpOnSearch(gpQ: String) -> void:
	_gpRender(_gpFilter(gpQ))


func _gpFilter(gpQ: String) -> Array[GPSymbolDef]:
	var gpNeedle: String = gpQ.strip_edges().to_lower()
	if gpNeedle == "":
		return gpDefs
	var gpOut: Array[GPSymbolDef] = []
	for gpD in gpDefs:
		var gpHay: String = "%s %s %s" % [I18n.gpTr(gpD.gpDisplayName), gpD.gpId, gpD.gpCategory]
		if gpHay.to_lower().contains(gpNeedle):
			gpOut.append(gpD)
	return gpOut


# Render the injected symbol list, grouped by category.
# 渲染注入的图元列表，按类目分组。
func _gpRender(gpList: Array[GPSymbolDef]) -> void:
	for gpC in gpListRoot.get_children():
		gpListRoot.remove_child(gpC)
		gpC.queue_free()

	var gpVbox: VBoxContainer = VBoxContainer.new()
	gpVbox.size_flags_horizontal = SIZE_EXPAND_FILL
	gpListRoot.add_child(gpVbox)

	var gpByCat: Dictionary = {}
	for gpD in gpList:
		if not gpByCat.has(gpD.gpCategory):
			gpByCat[gpD.gpCategory] = []
		gpByCat[gpD.gpCategory].append(gpD)

	for gpCat in gpByCat.keys():
		var gpHeader: Label = Label.new()
		gpHeader.text = "▾ %s" % I18n.gpTr(gpCat)
		gpVbox.add_child(gpHeader)
		for gpD in gpByCat[gpCat]:
			var gpB: Button = Button.new()
			gpB.text = I18n.gpTr(gpD.gpDisplayName)
			gpB.alignment = HORIZONTAL_ALIGNMENT_LEFT
			gpB.size_flags_horizontal = SIZE_EXPAND_FILL
			gpB.pressed.connect(_gpOnPick.bind(gpD.gpId))
			gpVbox.add_child(gpB)


func _gpRefreshLocale(gpLocale: String) -> void:
	gpTitle.text = I18n.gpTr("symbol_lib.title")
	gpSearchBox.placeholder_text = I18n.gpTr("symbol_lib.search")
	gpSelBtn.text = I18n.gpTr("symbol_lib.tool_select")
	gpConBtn.text = I18n.gpTr("symbol_lib.tool_connect")
	gpCustBtn.text = I18n.gpTr("symbol_lib.tool_custom")
	_gpRender(_gpFilter(gpSearchBox.text))


func _gpOnPick(gpTypeId: String) -> void:
	gpSymbolPicked.emit(gpTypeId)
