class_name GPInspector
extends ScrollContainer

# Property panel (right dock, "属性" tab) — M10 rebuild.
# 属性面板（右栏「属性」页）—— M10 重建。
#
# What this panel shows, in order / 本面板自上而下显示：
# 1. the SYMBOL NAME (read-only) — the library type, whose home is this panel and never
# the canvas; plus a category-grouped dropdown to SWAP the symbol;
# 图元名称（只读）—— 库里的类型，它的家是本面板而非画布；外加按类目分组的
# 「更换图元」下拉；
# 2. 位号 (tag) and 名称 (multi-language) — the instance identity the user owns;
# 位号与名称（多语言）—— 用户自有的实例标识；
# 3. label placement (anchor) — the coarse choice; fine dragging happens on the canvas ;
# 标签位置（锚点）—— 粗粒度选择；精细拖拽在画布上完成；
# 4. the typed property fields resolved from the LIBRARY schema + this instance's values
# (GPPropertyForm + GPPropertyResolver), grouped and ordered by the schema itself.
# 由**库 schema** 与本实例取值解析出的类型化属性字段（GPPropertyForm + GPPropertyResolver），
# 分组与顺序由 schema 自身决定。
#
# Two rules that make "edit the library, every project follows" true / 两条让
# 「改图元库、全项目同步」成立的规则：
# - field DEFINITIONS are read from gpDef.gpSchema and never copied into the node;
# 字段**定义**读自 gpDef.gpSchema，绝不复制进节点；
# - field VALUES are read through GPPropertyResolver (default vs override by `has`).
# 字段**取值**经 GPPropertyResolver 读取（用 `has` 区分默认与覆盖）。
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

# The user asked for the full line-attributes editor from the edge form (existing lines have
# no other way back to it; the panel used to open only when a NEW pipe was drawn).
# 用户在边表单里请求完整的管线属性编辑器（已有管线没有别的入口；此前面板只在新画线时打开）。
signal gpLineAttrsRequested(gpEdgeId: String)

# Re-render the line number from the CURRENT edge attributes without changing any value. This is
# the repair path for an old tag left stale by an earlier blind edit / rule change.
# 不改任何值，仅按当前边属性重渲染管线号；用于修复此前盲写 / 规则变更留下的陈旧号。
signal gpLineRerenderRequested(gpEdgeId: String)

# The user picked a different symbol in the swap dropdown: node id, new symbol id.
# 用户在「更换图元」下拉中选了另一个图元：节点 id、新图元 id。
signal gpSymbolSwapRequested(gpNodeId: String, gpNewSymbolId: String)

# Batched on purpose: the host turns the whole id set into ONE undo step.
# 刻意成批发送：宿主据此把整个 id 集合合成**一个**撤销步。
signal gpBatchAttrChanged(gpIds: Array[String], key: String, val)

# orphan is a value the user typed, so only the user may discard it.
# 只有用户本人才能丢弃它。
signal gpCleanOrphansRequested(gpNodeId: String)

# A CUSTOM property entry was added (Rev.3 stage 1.5, R2 / D7): node id, key, initial value.
# 一条**自定义**属性条目被新增（Rev.3 阶段 1.5，R2 / D7）：节点 id、键、初始值。
signal gpPropAddRequested(gpNodeId: String, gpKey: String, gpVal)

# A custom entry was RENAMED: node id, old key, new key. One undo step via the dedicated command.
# 一条自定义条目被**改名**：节点 id、旧键、新键。经专用命令成为一个撤销步。
signal gpPropRenamed(gpNodeId: String, gpOldKey: String, gpNewKey: String)

# A custom entry was deleted: node id, key (the value is erased, letting nothing back).
# 一条自定义条目被删除：节点 id、键（取值被擦除）。
signal gpPropDeleteRequested(gpNodeId: String, gpKey: String)

# An annotation-shape field was edited (A2). The shape has no id, so the INDEX is the handle —
# the same reason GPDeleteShapesCommand takes indices. The shell routes this to the command
# layer, which is what makes a layer edit undoable.
# 注释图形的某个字段被编辑（A2）。图形没有 id，故以**下标**为句柄 —— 理由同
# GPDeleteShapesCommand。外壳把它路由到命令层，这正是「改图层可撤销」的来源。
signal gpShapePropChanged(gpShapeIdx: int, gpField: String, gpValue)

# ADR-43 / S4-4: one link-attr field was committed (link id, attr key, new value). The shell
# routes this through GPCrossSheetSyncCommand (link-only) so the edit is one undo step.
# ADR-43 / S4-4：一个 link 属性字段已提交（link id、属性键、新值）。外壳经
# GPCrossSheetSyncCommand（仅 link）路由，使编辑成为一个撤销步。
signal gpLinkAttrEditRequested(gpLinkId: String, gpKey: String, gpValue: String)

# ADR-43 / S4-4: the user asked to push this link's contract snapshot to the peer end.
# ADR-43 / S4-4：用户要求把本 link 的契约快照推送到对端。
signal gpLinkSyncRequested(gpLinkId: String)

# ADR-43 / S4-4 (user feedback 2026-11-03): on an UNLINKED connector the user picked a peer
# sheet in the "对端图纸号" dropdown. The shell routes it through the same canvas gesture the
# context menu uses, so the connect dialog opens PRESELECTED on that sheet.
# ADR-43 / S4-4（用户反馈 2026-11-03）：未连线的连接符上，用户在「对端图纸号」下拉里选定
# 了一张图纸。外壳把它路由进与右键菜单**同一条**画布手势，使连接对话框直接预选该图纸。
signal gpConnectPickRequested(gpNodeId: String, gpSheetId: String)

# Cross-sheet inherit checkbox on a B-side continuation edge (user feedback 2026-11-04):
# the user switched "继承源端编号" on/off for this line segment.
# B 端延续边上的跨图纸继承勾选框（用户反馈 2026-11-04）：用户对本线段开关了「继承源端编号」。
signal gpEdgeInheritToggled(gpEdgeId: String, gpFollow: bool)

# Container link-table provider (the panel owns no link table). Invalid = section hidden.
# 容器 link 表来源（本面板不持有 link 表）。无效时整段隐藏。
var gpLinksProvider: Callable = Callable()

# Inherit-checkbox provider for the edge form; returns {"show": bool, "follow": bool}
# (the shell resolves the link direction — the panel stays sheet-local). Invalid or
# show=false = no checkbox row.
# 边表单的继承勾选框来源；返回 {"show": bool, "follow": bool}（link 方向由外壳判定 ——
# 面板保持单图纸）。无效或 show=false 时不渲染该行。
var gpEdgeInheritProvider: Callable = Callable()

# Sheets provider for the unlinked connector's peer-sheet dropdown; returns
# {"sheets": Array[GPSheet], "current": String active sheet id}. Invalid = the dropdown
# degrades to the placeholder with no options.
# 未连线连接符的对端图纸下拉的图纸来源；返回 {"sheets": Array[GPSheet], "current": 当前
# 图纸 id}。无效时下拉退化为无可选项的占位符。
var gpSheetsProvider: Callable = Callable()

# Key prefix for a multi-language name edit (e.g. "name:zh_CN").
# 多语言名称编辑的键前缀（如 "name:zh_CN"）。
const GP_NAME_PREFIX: String = "name:"

# Minimum width of the property label column (left column of the 2-column inspector).
# 2026-09-25: 150 -> 112 (-25%) so the input fields start 25% further LEFT, per request.
# 属性标签列（两列属性面板的左列）最小宽度。2026-09-25：150 -> 112（-25%），
# 按需求让输入框整体左移约 25%。
const GP_LABEL_MIN_W: float = 112.0

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

# Supplies the project standard for the edge form's code pickers (medium / pipe class /
# insulation). A panel owns no graph, so the host injects this once instead of the inspector
# reaching into the canvas.
# 为边表单的代号下拉（介质 / 管道等级 / 保温）提供项目标准。面板不持有图，故由宿主注入一次，
# 而不是让面板反向去摸画布。
var gpStandardProvider: Callable = Callable()

# Every symbol definition in the library, for the swap dropdown. Owned by the shell, which
# re-assigns it whenever the library is reloaded.
# 图元库中的全部图元定义，供「更换图元」下拉使用。由外壳持有，库重载时重新赋值。
var gpDefs: Array[GPSymbolDef] = []

# Symbol ids parallel to the swap dropdown's items, rebuilt with the form.
# 与「更换图元」下拉各项一一对应的图元 id，随表单重建。
var _gpSwapIds: Array[String] = []

# Non-empty when several instances of the SAME symbol are selected: every edit is emitted
# once per id, so one keystroke lands on the whole selection .
# 选中同一图元的多个实例时非空：每次编辑按 id 各发一次，一次录入落到整个选择集
var _gpBatchIds: Array[String] = []

# The nodes behind _gpBatchIds, kept so a locale change can rebuild the batch form.
# _gpBatchIds 对应的节点，使语言切换时能重建批量表单。
var _gpBatchNodes: Array[GPPIDNode] = []

# How many section headers the current form already has; the FIRST section gets no
# hairline above it, every later one does (mirrors the left palette's category
# separators, 2026-09-25 request). Reset on every form rebuild.
# 当前表单已有多少个小节标题：首节上方不发丝线，其后每节上方各一条
#（与左栏类目分隔一致，2026-09-25 需求）。每次重建表单时归零。
var _gpHeadCount: int = 0

# Property search box contents (Rev.3 stage 1.5, R2). Reset on a NEW selection (gpShow /
# gpShowMulti), kept across in-form rebuilds so applying a search does not erase itself.
# 属性检索框内容（Rev.3 阶段 1.5，R2）。**新**选中时重置（gpShow / gpShowMulti），
# 表单内部重建时保留，使「应用检索」不会抹掉自己。
var _gpSearchQuery: String = ""

# Shape currently shown (A2). Null for the node / edge forms, so one panel never edits two
# kinds of object at once.
# 当前显示的图形（A2）。节点 / 边表单时为 null，使同一面板绝不会同时编辑两类对象。
var gpCurrentShape: GPShape = null

# Index of gpCurrentShape inside the graph's shape list.
# gpCurrentShape 在图图形列表中的下标。
var gpCurrentShapeIdx: int = -1

# Inline note label under the add-entry row (refusals surface here, in place).
# 「新增条目」行下方的就地提示标签（拒绝原因就地显示于此）。
var _gpAdhocNote: Label = null


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
	_gpSearchQuery = ""
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
# be written onto instances that never had it. The shell calls gpShow() for those.
# 混合类型选择**不可**调用本方法：只有部分实例声明的属性会被写到从未有过该属性的实例上。
# 外壳对混合选择调用 gpShow()。
func gpShowMulti(gpDef: GPSymbolDef, gpNodes: Array[GPPIDNode]) -> void:
	_gpBatchNodes = []
	_gpBatchIds = []
	_gpSearchQuery = ""
	for gpN in gpNodes:
		if gpN == null:
			continue
		_gpBatchNodes.append(gpN)
		_gpBatchIds.append(gpN.gpInstanceId)
	if _gpBatchNodes.is_empty():
		gpShow(null, null)
		return
	_gpBuildNodeForm(gpDef, _gpBatchNodes)


# Build the shared node form. gpNodes() is 1 (single) or N (batch) instances of gpDef.
# 构建共用的节点表单。gpNodes() 为 gpDef 的 1 个（单选）或 N 个（批量）实例。
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

	# ---- property search (Rev.3 stage 1.5, R2) + typed property fields ----
	# ---- 属性检索（Rev.3 阶段 1.5，R2）+ 类型化属性字段 ----
	var gpSchema: GPPropertySchema = gpDef.gpSchema
	var gpPropsList: Array = []
	for gpN in gpNodes:
		gpPropsList.append(gpN.gpProps)
	if not gpIsBatch:
		_gpAddSearchBox()
	if gpSchema == null or gpSchema.gpFields.is_empty():
		_gpAddHead(I18n.gpTr("inspector.properties"))
		_gpAddNote(I18n.gpTr("inspector.no_props"))
	elif _gpSearchQuery != "":
		# Searching: the matching rows are flattened into ONE section, rendered by the very
		# same row builder, so a hit looks exactly like it does in its own group.
		# 检索时：命中行摊平为**一个**小节，仍用同一个行构建器渲染，故命中项的样子
		# 与它在原分组中完全一致。
		var gpHits: Array[Dictionary] = GPPropertyForm.gpSearch(gpSchema, gpPrimary.gpProps,
			_gpSearchQuery)
		_gpAddHead("%s · %d" % [I18n.gpTr("inspector.search"), gpHits.size()])
		for gpRow in gpHits:
			_gpAddPropertyRow(gpRow, gpSchema, gpPropsList, false)
	else:
		for gpSec in GPPropertyForm.gpSections(gpSchema, gpPrimary.gpProps):
			_gpAddHead(GPPropertyForm.gpSectionTitle(str(gpSec["group"]),
				(gpSec["fields"] as Array).size()))
			for gpRow in (gpSec["fields"] as Array):
				_gpAddPropertyRow(gpRow, gpSchema, gpPropsList, gpIsBatch)

	# ---- custom entries: user-owned keys outside the schema (Rev.3 stage 1.5, R2) ----
	# ---- 自定义条目：schema 之外、用户自有的键（Rev.3 阶段 1.5，R2） ----
	# Same storage as the old "orphans" (gpProps keys the schema does not declare), now EDITABLE:
	# rename / delete per row, add at the bottom — instance level only (D7). Batch mode and a
	# denied permission both fall back to the old read-only display; only the user may discard
	# these values, so the sweep button stays explicit and is gated too.
	# 与旧「孤儿」同源存储（schema 未声明的 gpProps 键），现在**可编辑**：逐行改名 / 删除，
	# 底部新增 —— 仅实例级（D7）。批量模式与权限被拒都回落旧的只读展示；这些值只有用户
	# 本人可丢弃，故一键清理仍是显式按钮、且同样被闸控。
	var gpAdhoc: Array[Dictionary] = GPPropertyForm.gpAdhocRows(gpSchema, gpPrimary.gpProps)
	var gpMayEditProps: bool = GPPermissions.gpCanEditProps() and not gpIsBatch
	if not gpAdhoc.is_empty():
		_gpAddHead(I18n.gpTr("inspector.adhoc"))
		for gpRow in gpAdhoc:
			if gpMayEditProps:
				_gpAddAdhocRow(str(gpRow["key"]), str(gpRow["value"]))
			else:
				_gpAddTextField(str(gpRow["key"]), str(gpRow["value"]), "", true)
	if gpMayEditProps:
		_gpAddAdhocCreator()
	if not gpAdhoc.is_empty():
		var gpBtn: Button = Button.new()
		gpBtn.text = I18n.gpTr("inspector.clean_orphans") % [gpAdhoc.size()]
		gpBtn.size_flags_horizontal = SIZE_EXPAND_FILL
		gpBtn.disabled = not GPPermissions.gpCanEditProps()
		gpBtn.pressed.connect(func() -> void:
			if gpCurrentNode != null:
				gpCleanOrphansRequested.emit(gpCurrentNode.gpInstanceId))
		gpFormRoot.add_child(gpBtn)
	# ---- cross-sheet link section (ADR-43 S4-4) ----
	# ---- 跨图纸连接段（ADR-43 S4-4）----
	_gpAddLinkSection(gpDef, gpPrimary)


# The off-page connector's link section: the derived peer number (read-only, the index owns
# it), the two legend lines (equipment description / medium) and the contract snapshot, all
# editable on the LINK (not the node), plus the sync button that pushes the snapshot to the
# peer end. Edits are committed per field through gpLinkAttrEditRequested — the shell routes
# them through GPCrossSheetSyncCommand so every keystroke-commit is one undo step.
# 跨图纸连接符的 link 段：对端图纸号（只读，索引所有）、图例两行（设备描述 / 介质）与
# 契约快照 —— 都编辑在 **link**（而非节点）上，外加把快照推送到对端的同步按钮。编辑逐字段
# 经 gpLinkAttrEditRequested 提交 —— 外壳把它们路由进 GPCrossSheetSyncCommand，
# 使每次提交都是一个撤销步。
func _gpAddLinkSection(gpDef: GPSymbolDef, gpNode: GPPIDNode) -> void:
	if gpDef == null or gpNode == null or gpDef.gpCategory != "offpage":
		return
	if not gpLinksProvider.is_valid():
		return
	var gpLink: GPOffPageLink = null
	for gpL in gpLinksProvider.call() as Array:
		if gpL != null and gpL.gpInstanceId == str(gpNode.gpProps.get(
				GPOffPageLink.GP_KEY_LINK_ID, "")):
			gpLink = gpL
			break
	_gpAddHead(I18n.gpTr("offpage.insp_head"))
	if gpLink == null:
		# An unlinked connector: offer a PEER-SHEET dropdown (user feedback 2026-11-03 —
		# the old blank read-only field offered no way forward). Picking a sheet emits
		# gpConnectPickRequested; the shell opens the connect dialog preselected on it.
		# 未连线的连接符：提供**对端图纸下拉**（用户反馈 2026-11-03 —— 原来的空白只读
		# 字段无处下手）。选定图纸即发射 gpConnectPickRequested；外壳据此打开预选到该
		# 图纸的连接对话框。
		_gpAddPeerSheetPick(gpNode)
		return
	_gpAddTextField(I18n.gpTr("offpage.insp_ref"),
		GPOffPageIndex.gpRefTextFor(gpNode), "", true)
	# The TARGET end's tag is DERIVED through the index (user feedback 2026-11-03: the top
	# line of the legend inherits the tag of the item the link serves) — read-only, like the
	# reference. The contract keys follow as editable fields; the medium was seeded from the
	# source line at creation and syncs from here.
	# **目标端**位号经索引**推导**（用户反馈 2026-11-03：图例上一行自动继承 link 所服务对象的
	# 位号）—— 与对端图号一样只读。其后是可编辑的契约字段；介质在创建时已从源管线播种，
	# 由此处同步。
	_gpAddTextField(I18n.gpTr("offpage.insp_target"),
		GPOffPageIndex.gpTargetTagFor(gpNode), "", true)
	for gpKey in GPOffPageLink.GP_CONTRACT_KEYS:
		var gpK: String = gpKey
		_gpAddLinkField(gpLink.gpInstanceId,
			I18n.gpTr("offpage.insp_medium") if gpKey == GPOffPageLink.GP_ATTR_MEDIUM
			else gpKey, str(gpLink.gpAttrs.get(gpKey, "")), gpK)
	var gpSyncBtn: Button = Button.new()
	gpSyncBtn.text = I18n.gpTr("offpage.insp_sync")
	gpSyncBtn.size_flags_horizontal = SIZE_EXPAND_FILL
	gpSyncBtn.pressed.connect(func() -> void:
		gpLinkSyncRequested.emit(gpLink.gpInstanceId))
	gpFormRoot.add_child(gpSyncBtn)
	_gpAddNote(I18n.gpTr("offpage.insp_sync_hint"))


# The peer-sheet dropdown for an UNLINKED connector. Ordered by drawing number through the
# SAME core helper the connect dialog uses, so the two pickers can never disagree. Item 0 is
# a placeholder; picking a real sheet emits gpConnectPickRequested and snaps back, ready to
# be rebuilt (the shell opens the dialog, the connector becomes linked, the section re-renders).
# 未连线连接符的对端图纸下拉。经与连接对话框**同一个** core 助手按图号排序，两个选择器
# 永不次序分家。第 0 项为占位符；选中真图纸即发射 gpConnectPickRequested 并弹回占位
#（外壳随后打开对话框，连接符成为已连接，本段随之重渲染）。
func _gpAddPeerSheetPick(gpNode: GPPIDNode) -> void:
	var gpData: Dictionary = {}
	if gpSheetsProvider.is_valid():
		gpData = gpSheetsProvider.call() as Dictionary
	var gpRaw: Array = gpData.get("sheets", []) as Array
	var gpCurrent: String = str(gpData.get("current", ""))
	var gpRow: HBoxContainer = _gpFieldRow(I18n.gpTr("offpage.insp_ref"))
	var gpOpt: OptionButton = OptionButton.new()
	gpOpt.size_flags_horizontal = SIZE_EXPAND_FILL
	gpOpt.add_item(I18n.gpTr("offpage.insp_pick_sheet"))
	var gpOrdered: Array[GPSheet] = []
	for gpV in gpRaw:
		var gpS: GPSheet = gpV as GPSheet
		if gpS != null and gpS.gpId != gpCurrent:
			gpOrdered.append(gpS)
	gpOrdered.sort_custom(GPOffPageIndex.gpSheetBefore)
	var gpIds: Array[String] = []
	for gpS in gpOrdered:
		gpOpt.add_item(GPOffPageIndex.gpSheetLabel(gpS))
		gpIds.append(gpS.gpId)
	# No sibling sheet to offer? Keep the row honest: disabled placeholder, no dead choice.
	# 没有可选的兄弟图纸？让这一行保持诚实：禁用的占位符，不给死选项。
	gpOpt.disabled = gpIds.is_empty()
	var gpNodeId: String = gpNode.gpInstanceId
	gpOpt.item_selected.connect(func(gpIdx: int) -> void:
		gpOpt.select(0)
		if gpIdx > 0 and gpIdx - 1 < gpIds.size():
			gpConnectPickRequested.emit(gpNodeId, gpIds[gpIdx - 1]))
	gpRow.add_child(gpOpt)


# One editable link-attr row. Commits on submit (Enter), so partial typing never lands in
# the model.
# 一行可编辑的 link 属性。提交发生在 text_submitted（回车），半截输入永不进模型。
func _gpAddLinkField(gpLinkId: String, gpLabel: String, gpInitial: String,
		gpKey: String) -> void:
	var gpRow: HBoxContainer = _gpFieldRow(gpLabel)
	var gpEdit: LineEdit = LineEdit.new()
	gpEdit.size_flags_horizontal = SIZE_EXPAND_FILL
	gpEdit.text = gpInitial
	gpEdit.text_submitted.connect(func(gpV: String) -> void:
		# The shell resolves the link by id — this panel owns no link table.
		# 外壳按 id 解析 link —— 本面板不持有 link 表。
		gpLinkAttrEditRequested.emit(gpLinkId, gpKey, gpV))
	gpRow.add_child(gpEdit)


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
	# "general"（通用）永远排在最后（与左栏图元库一致，2026-09-25 需求）。
	# Category first, then display name; the "general" category always sorts LAST,
	# mirroring the left palette (2026-09-25 request).
	gpRows.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
		var gpAIsG: bool = str(gpA["cat"]).to_lower() == "general"
		var gpBIsG: bool = str(gpB["cat"]).to_lower() == "general"
		if gpAIsG != gpBIsG:
			return gpBIsG
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


# ---- custom-entry CRUD widgets (Rev.3 stage 1.5, R2 / D7) ----
# ---- 自定义条目增删改控件（Rev.3 阶段 1.5，R2 / D7） ----

# One CUSTOM entry: editable key (commit = rename, one undo step), editable value (commit =
# set), and a per-row delete. Only reached when the permission allows and the selection is
# single, so the editors can bind straight to gpCurrentNode.
# 一条**自定义**条目：键可编辑（提交 = 改名，一个撤销步）、值可编辑（提交 = 写入）、
# 行内删除。仅在权限允许且单选时到达此处，故编辑器可直接绑定 gpCurrentNode。
func _gpAddAdhocRow(gpKey: String, gpVal: String) -> void:
	var gpRow: HBoxContainer = _gpFieldRow(gpKey)
	var gpKeyEdit: LineEdit = LineEdit.new()
	gpKeyEdit.text = gpKey
	gpKeyEdit.size_flags_horizontal = SIZE_EXPAND_FILL
	gpKeyEdit.tooltip_text = I18n.gpTr("inspector.adhoc_rename_hint")
	gpKeyEdit.text_submitted.connect(func(gpNew: String) -> void:
		var gpName: String = gpNew.strip_edges()
		if gpName == "" or gpName == gpKey or gpCurrentNode == null:
			return
		gpPropRenamed.emit(gpCurrentNode.gpInstanceId, gpKey, gpName))
	gpRow.add_child(gpKeyEdit)
	var gpValEdit: LineEdit = LineEdit.new()
	gpValEdit.text = gpVal
	gpValEdit.size_flags_horizontal = SIZE_EXPAND_FILL
	gpValEdit.text_submitted.connect(func(gpV: String) -> void:
		_gpEmit(gpKey, gpV))
	gpRow.add_child(gpValEdit)
	var gpDel: Button = Button.new()
	gpDel.text = "✕"
	gpDel.tooltip_text = I18n.gpTr("inspector.adhoc_delete_hint")
	gpDel.pressed.connect(func() -> void:
		if gpCurrentNode != null:
			gpPropDeleteRequested.emit(gpCurrentNode.gpInstanceId, gpKey))
	gpRow.add_child(gpDel)


# The add-entry row: key + optional initial value + the add button. A key the LIBRARY declares
# is refused here (with an inline note) instead of silently becoming an override.
# 「新增条目」行：键 + 可选初始值 + 添加按钮。**库已声明**的键在此被拒（就地提示），
# 而不是静默变成一条覆盖。
func _gpAddAdhocCreator() -> void:
	var gpRow: HBoxContainer = _gpFieldRow(I18n.gpTr("inspector.adhoc_add"))
	var gpKeyEdit: LineEdit = LineEdit.new()
	gpKeyEdit.placeholder_text = I18n.gpTr("inspector.adhoc_key_ph")
	gpKeyEdit.size_flags_horizontal = SIZE_EXPAND_FILL
	gpRow.add_child(gpKeyEdit)
	var gpValEdit: LineEdit = LineEdit.new()
	gpValEdit.placeholder_text = I18n.gpTr("inspector.adhoc_val_ph")
	gpValEdit.size_flags_horizontal = SIZE_EXPAND_FILL
	gpRow.add_child(gpValEdit)
	var gpBtn: Button = Button.new()
	gpBtn.text = I18n.gpTr("inspector.adhoc_add_btn")
	gpBtn.pressed.connect(func() -> void:
		var gpK: String = gpKeyEdit.text.strip_edges()
		if gpK == "" or gpCurrentNode == null:
			return
		if gpCurrentDef != null and gpCurrentDef.gpSchema != null \
				and gpCurrentDef.gpSchema.gpFieldByKey(gpK) != null:
			_gpSetAdhocNote(I18n.gpTr("inspector.adhoc_declared"))
			return
		if gpCurrentNode.gpProps.has(gpK):
			_gpSetAdhocNote(I18n.gpTr("inspector.adhoc_exists"))
			return
		_gpSetAdhocNote("")
		gpPropAddRequested.emit(gpCurrentNode.gpInstanceId, gpK, gpValEdit.text))
	gpRow.add_child(gpBtn)
	_gpAdhocNote = Label.new()
	_gpAdhocNote.modulate = Color(0.85, 0.45, 0.3)
	gpFormRoot.add_child(_gpAdhocNote)


# Show / clear the inline note under the add-entry row. No-op when the row is absent
# (batch mode / no permission never builds it).
# 显示 / 清除「新增条目」行下方的就地提示。行不存在时（批量 / 无权限）为空操作。
func _gpSetAdhocNote(gpText: String) -> void:
	if _gpAdhocNote != null:
		_gpAdhocNote.text = gpText


# The property search box (single selection only; batch keeps the full grouped view).
# Commits on ENTER, not per keystroke: a rebuild-per-keystroke would free the very widget the
# user is typing in. The query survives the rebuild via _gpSearchQuery.
# 属性检索框（仅单选；批量保持完整分组视图）。**回车**提交而非逐键：
# 逐键重建会释放用户正在输入的控件本身。查询词经 _gpSearchQuery 在重建后存活。
func _gpAddSearchBox() -> void:
	var gpRow: HBoxContainer = _gpFieldRow(I18n.gpTr("inspector.search"))
	var gpEdit: LineEdit = LineEdit.new()
	gpEdit.placeholder_text = I18n.gpTr("inspector.search_ph")
	gpEdit.size_flags_horizontal = SIZE_EXPAND_FILL
	gpEdit.text = _gpSearchQuery
	gpEdit.text_submitted.connect(func(gpV: String) -> void:
		_gpSearchQuery = gpV.strip_edges()
		if gpCurrentDef != null and gpCurrentNode != null:
			_gpBuildNodeForm(gpCurrentDef, [gpCurrentNode]))
	gpRow.add_child(gpEdit)


# ============================ widget helpers / 控件辅助 ============================

# Announce one edit. In batch mode the WHOLE selection travels in a single signal so the host
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


# Dropdown for the coarse label position. Fine positioning is the canvas grip's job .
# 粗粒度标签位置下拉。精细定位由画布上的抓取点负责。
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
	# A 1px hairline above every section EXCEPT the first — the same separator the
	# left symbol library draws between its categories.
	# 除首节外每个小节上方一条 1px 发丝线 —— 与左栏图元库类目间分隔一致。
	if _gpHeadCount > 0:
		var gpSep: ColorRect = ColorRect.new()
		gpSep.color = GPChromeStyle.GP_BORDER
		gpSep.custom_minimum_size = Vector2(0.0, 1.0)
		gpFormRoot.add_child(gpSep)
	_gpHeadCount += 1
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
	# Left-aligned labels (2026-09-25 request): the whole inspector content now lines
	# up flush left — heads, notes and field labels share one left edge.
	# 标签左对齐（2026-09-25 需求）：面板全部内容贴左 —— 小节标题、注释与字段标签
	# 共用同一条左缘。
	gpLbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	# Every non-shape form clears the shape handle: otherwise a stale index could be edited by a
	# later keystroke that the user aimed at a NODE (silent wrong-object edit).
	# 所有非图形表单都清掉图形句柄：否则用户明明是冲着**节点**敲的键，却可能改到过期的下标上
	#（静默改错对象）。
	gpCurrentShape = null
	gpCurrentShapeIdx = -1
	_gpHeadCount = 0
	_gpAdhocNote = null
	for gpC in gpFormRoot.get_children():
		gpFormRoot.remove_child(gpC)
		gpC.queue_free()


# ============================ shape form / 图形表单 ============================

# Show the form for ONE selected annotation shape. Pass null / -1 to clear.
# 显示单个选中注释图形的表单。传 null / -1 清空。
#
# Why the shape panel is small / 为何图形面板很小：
# A shape is a primitive, not a symbol instance: it has no library definition, no port and no
# property schema, so the only user-editable facts are its name, its layer bucket and its ink.
# Anything more would have to invent a schema (which is a symbol feature) or edit geometry
# numerically (which the viewport grips already do better).
# 图形是图元基元而非符号实例：没有库定义、没有端口、没有属性 schema，故用户可编辑的事实只有
# 名称、图层桶与墨色。再多就得自造 schema（那是符号的特性）或用数值改几何（视口手柄已做得更好）。
func gpShowShape(gpShape: GPShape, gpShapeIdx: int) -> void:
	gpCurrentDef = null
	gpCurrentNode = null
	gpCurrentEdge = null
	_gpBatchIds = []
	_gpBatchNodes = []
	_gpClearForm()
	gpCurrentShape = gpShape
	gpCurrentShapeIdx = gpShapeIdx
	if gpShape == null:
		_gpShowEmpty()
		return
	_gpAddHead(I18n.gpTr("inspector.shape"))
	_gpAddNote("%s：%s" % [I18n.gpTr("inspector.shape_kind"),
		I18n.gpTr(gpShapeKindKey(gpShape.gpKind))])
	_gpAddNote("%s：%d" % [I18n.gpTr("inspector.shape_points"), gpShape.gpPoints.size()])
	_gpAddShapeText(I18n.gpTr("inspector.shape_name"), gpShape.gpName, "gpName")
	_gpAddShapeLayer(gpShape.gpLayer)


# Localized key for a shape kind. Pure + static so the mapping can be pinned headlessly.
# 图形种类的本地化键。纯函数 + static，故映射可被 headless 钉住。
static func gpShapeKindKey(gpKind: int) -> String:
	match gpKind:
		GPShape.GPKind.GP_LINE:
			return "shape.kind_line"
		GPShape.GPKind.GP_CIRCLE:
			return "shape.kind_circle"
		GPShape.GPKind.GP_RECT:
			return "shape.kind_rect"
		GPShape.GPKind.GP_POLYLINE:
			return "shape.kind_polyline"
		GPShape.GPKind.GP_ARC:
			return "shape.kind_arc"
		_:
			return "shape.kind_line"


# The four layer buckets a shape may live in, in menu order.
# 图形可处的四个图层桶，按菜单顺序。
const GP_SHAPE_LAYERS: Array[String] = ["ANNOTATION", "BORDER", "DIMENSION", "HATCH"]


# One-line text row bound to a shape field.
# 绑定到图形字段的单行文本行。
func _gpAddShapeText(gpLabel: String, gpInitial: String, gpField: String) -> void:
	var gpRow: HBoxContainer = _gpFieldRow(gpLabel)
	var gpEdit: LineEdit = LineEdit.new()
	gpEdit.size_flags_horizontal = SIZE_EXPAND_FILL
	gpEdit.text = gpInitial
	gpEdit.text_submitted.connect(func(gpV: String) -> void:
		if gpCurrentShapeIdx >= 0:
			gpShapePropChanged.emit(gpCurrentShapeIdx, gpField, gpV))
	gpRow.add_child(gpEdit)


# Layer dropdown: the stored value is the raw bucket name, the visible text is localized.
# 图层下拉：存的是原始桶名，显示的是本地化文字。
func _gpAddShapeLayer(gpCurrent: String) -> void:
	var gpRow: HBoxContainer = _gpFieldRow(I18n.gpTr("inspector.shape_layer"))
	var gpOpt: OptionButton = OptionButton.new()
	gpOpt.size_flags_horizontal = SIZE_EXPAND_FILL
	for gpI in range(GP_SHAPE_LAYERS.size()):
		gpOpt.add_item(I18n.gpTr("shape.layer_" + GP_SHAPE_LAYERS[gpI].to_lower()))
		gpOpt.set_item_metadata(gpI, GP_SHAPE_LAYERS[gpI])
		if GP_SHAPE_LAYERS[gpI] == gpCurrent:
			gpOpt.select(gpI)
	gpOpt.item_selected.connect(func(gpI: int) -> void:
		if gpCurrentShapeIdx < 0:
			return
		var gpLayer: String = str(gpOpt.get_item_metadata(gpI))
		gpShapePropChanged.emit(gpCurrentShapeIdx, "gpLayer", gpLayer))
	gpRow.add_child(gpOpt)


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
	var gpSections: Dictionary = gpEdgeFieldSections(gpEdge, _gpEdgeStandard())
	_gpAddEdgeSection("inspector.section.line_number", gpSections["identity"] as Array[String],
		gpEdge, true)
	_gpAddEdgeSection("inspector.section.general", gpSections["general"] as Array[String],
		gpEdge, false)
	# Cross-sheet inherit checkbox (user feedback 2026-11-04): only on a B-side continuation
	# (the shell decides via the provider), never on signal lines (they carry no line number).
	# 跨图纸继承勾选框（用户反馈 2026-11-04）：仅在 B 端延续段显示（外壳经 provider 判定）；
	# 信号线绝不显示（其不带管线号）。
	var gpInherit: Dictionary = {}
	if gpEdgeInheritProvider.is_valid() and gpEdge.gpKind != GPPIDEdge.GP_SIGNAL:
		gpInherit = gpEdgeInheritProvider.call(gpEdge.gpInstanceId) as Dictionary
	if bool(gpInherit.get("show", false)):
		var gpInhRow: HBoxContainer = _gpFieldRow(I18n.gpTr("offpage.insp_inherit"))
		gpInhRow.tooltip_text = I18n.gpTr("offpage.insp_inherit_tip")
		var gpInhChk: CheckBox = CheckBox.new()
		gpInhChk.button_pressed = bool(gpInherit.get("follow", false))
		gpInhChk.size_flags_horizontal = SIZE_EXPAND_FILL
		gpInhChk.toggled.connect(func(gpV: bool) -> void:
			gpEdgeInheritToggled.emit(gpEdge.gpInstanceId, gpV))
		gpInhRow.add_child(gpInhChk)


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


# Attribute keys that are plumbing, not user-editable line properties.
# 属于内部管线状态、不应作为用户属性字段的键。
const GP_EDGE_INTERNAL_ATTRS: Array[String] = [
	"tag", "tag_manual", "end_notes", "tag_offset", "broken_from", "broken_to", "routing",
	"line_group", "kind", "signal_type", "show_arrow", "show_tag",
]
const GP_EDGE_PIPE_FALLBACK: Array[String] = ["dn", "medium", "spec", "insulation"]
# Always-available engineering attributes, so the general section is useful even before an
# import created them. They are ordinary edge attributes and do not participate in the tag rule.
# 常驻的工程属性：即使导入前尚未存在，也给出可填字段；它们是普通边属性，不参与编号规则。
const GP_EDGE_GENERAL_DEFAULTS: Array[String] = ["design_pressure", "design_temp"]


# The two field groups of an edge form: identity (what makes the line number) and general
# engineering properties. Rules drive the identity group, so a project-standard field can never
# be missing here again; existing gpAttrs keys that are not identity/internal appear in general.
# 边表单的两个字段组：标识（构成管线号的字段）与常规工程属性。标识组由项目标准规则驱动，
# 故项目标准新增字段不可能再在这里消失；不属于标识/内部的既有 gpAttrs 键进入常规组。
static func gpEdgeFieldSections(gpEdge: GPPIDEdge, gpStd: GPProjectStandard) -> Dictionary:
	var gpIdentity: Array[String] = []
	var gpGeneral: Array[String] = []
	if gpEdge == null:
		return {"identity": gpIdentity, "general": gpGeneral}
	if gpEdge.gpKind == GPPIDEdge.GP_SIGNAL:
		# A signal line has no pipeline number; show its kind / signal type / flags as general.
		gpGeneral.append_array(["kind", "signal_type", "tag", "show_arrow", "show_tag"])
	else:
		gpIdentity.append("tag")
		var gpSeen: Dictionary = {}
		var gpRule: GPTagRule = _gpLineRule(gpStd)
		if gpRule != null:
			for gpSegRaw in gpRule.gpSegments:
				var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
				if gpSeg == null:
					continue
				if gpSeg.gpSource != GPTagSegment.GPSource.GP_ATTR 						and gpSeg.gpSource != GPTagSegment.GPSource.GP_ATTR_DIGITS 						and gpSeg.gpSource != GPTagSegment.GPSource.GP_CODE_TABLE:
					continue
				var gpAttrKey: String = gpSeg.gpAttrKey()
				if gpAttrKey == "" or gpSeen.has(gpAttrKey):
					continue
				gpSeen[gpAttrKey] = true
				gpIdentity.append(gpAttrKey)
		if gpIdentity.size() == 1:
			# No rule available (headless / legacy): keep the historic pipe fields.
			for gpKey in GP_EDGE_PIPE_FALLBACK:
				gpIdentity.append(gpKey)
		gpGeneral.append_array(["kind", "show_arrow", "show_tag"])
		for gpKey in GP_EDGE_GENERAL_DEFAULTS:
			if not gpGeneral.has(gpKey):
				gpGeneral.append(gpKey)
		var gpExtras: Array[String] = []
		for gpKeyRaw in gpEdge.gpAttrs.keys():
			var gpKey: String = str(gpKeyRaw)
			if gpIdentity.has(gpKey) or gpGeneral.has(gpKey) or GP_EDGE_INTERNAL_ATTRS.has(gpKey):
				continue
			if gpKey.begins_with("_"):
				continue
			gpExtras.append(gpKey)
		gpExtras.sort()
		gpGeneral.append_array(gpExtras)
	return {"identity": gpIdentity, "general": gpGeneral}


# Flat field list, for callers/tests that do not render sections.
# 扁平字段列表，供不渲染分节的调用方/测试使用。
static func gpEdgeFieldKeysFor(gpEdge: GPPIDEdge, gpStd: GPProjectStandard) -> Array[String]:
	var gpSections: Dictionary = gpEdgeFieldSections(gpEdge, gpStd)
	var gpOut: Array[String] = []
	gpOut.append_array(gpSections["identity"] as Array[String])
	gpOut.append_array(gpSections["general"] as Array[String])
	return gpOut


# Line-number rule of the project (the edge class has one default rule).
# 工程的管线号规则（边类别使用默认规则）。
static func _gpLineRule(gpStd: GPProjectStandard) -> GPTagRule:
	if gpStd == null:
		return null
	return gpStd.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpRuleFor(null)


# True when the project-standard line rule consumes this key (so editing it must re-render the
# line number through gpApplyLineAttr, not the blind gpSetEdgeAttr path).
# 项目标准管线规则是否消费该键（是则编辑必须经 gpApplyLineAttr 重渲染号，而不是盲写 gpSetEdgeAttr）。
static func gpIsLineRuleAttr(gpKey: String, gpStd: GPProjectStandard) -> bool:
	return _gpLineSegmentFor(gpKey, gpStd) != null


# The line-rule segment that owns an attribute key, or null.
# 拥有某个属性键的管线规则段，没有则 null。
static func _gpLineSegmentFor(gpKey: String, gpStd: GPProjectStandard) -> GPTagSegment:
	var gpRule: GPTagRule = _gpLineRule(gpStd)
	if gpRule == null:
		return null
	for gpSegRaw in gpRule.gpSegments:
		var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
		if gpSeg != null and gpSeg.gpAttrKey() == gpKey:
			return gpSeg
	return null


# Label for one edge field: the rule segment's label wins (new project-standard fields), then
# the existing edge.* translation, then the raw key as a last resort.
# 边字段标签：优先规则段标签（项目标准新增字段），其次既有 edge.* 翻译，最后裸键。
static func gpEdgeFieldLabel(gpKey: String, gpStd: GPProjectStandard) -> String:
	var gpSeg: GPTagSegment = _gpLineSegmentFor(gpKey, gpStd)
	if gpSeg != null and gpSeg.gpLabel != "":
		return gpSeg.gpLabel
	return I18n.gpTr("edge." + gpKey, gpKey)


# Add one titled group; the identity group gets the "edit line attributes" entry, which is the
# only way back to the full dialog for an existing pipe.
# 添加一个带标题的字段组；标识组带「编辑管线属性」入口 —— 已有管线回到完整面板的唯一路径。
func _gpAddEdgeSection(gpTitleKey: String, gpKeys: Array[String], gpEdge: GPPIDEdge,
		gpWithEdit: bool) -> void:
	if gpKeys.is_empty():
		return
	var gpHead: HBoxContainer = HBoxContainer.new()
	gpHead.add_theme_constant_override("separation", 8)
	gpFormRoot.add_child(gpHead)
	var gpTitle: Label = Label.new()
	gpTitle.text = I18n.gpTr(gpTitleKey)
	gpTitle.add_theme_font_size_override("font_size", 11)
	gpTitle.modulate = Color(1, 1, 1, 0.65)
	gpTitle.size_flags_horizontal = SIZE_EXPAND_FILL
	gpHead.add_child(gpTitle)
	if gpWithEdit:
		var gpEdit: Button = Button.new()
		gpEdit.text = I18n.gpTr("inspector.edit_line_attrs")
		gpEdit.tooltip_text = I18n.gpTr("inspector.edit_line_attrs_tip")
		gpEdit.pressed.connect(func() -> void:
			gpLineAttrsRequested.emit(gpEdge.gpInstanceId))
		gpHead.add_child(gpEdit)
		var gpRerender: Button = Button.new()
		gpRerender.text = I18n.gpTr("inspector.rerender_line")
		gpRerender.tooltip_text = I18n.gpTr("inspector.rerender_line_tip")
		gpRerender.pressed.connect(func() -> void:
			gpLineRerenderRequested.emit(gpEdge.gpInstanceId))
		gpHead.add_child(gpRerender)
	for gpKey in gpKeys:
		_gpAddEdgeField(gpEdge, gpKey)


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
	for gpKey in GP_EDGE_GENERAL_DEFAULTS:
		if not gpOut.has(gpKey):
			gpOut[gpKey] = str(gpEdge.gpAttrs.get(gpKey, ""))
	# Project-standard / engineering attributes added after the fixed set: expose them too, so
	# the pure helper matches what the dynamic form will render.
	# 固定字段之后新增的项目标准 / 工程属性：一并暴露，使纯助手与动态表单一致。
	for gpKeyRaw in gpEdge.gpAttrs.keys():
		var gpKey: String = str(gpKeyRaw)
		if not gpOut.has(gpKey) and not GP_EDGE_INTERNAL_ATTRS.has(gpKey):
			gpOut[gpKey] = gpEdge.gpAttrs[gpKey]
	return gpOut


# Build one labeled control for an edge field and wire it to gpEdgeAttrChanged.
# 为边的一个字段构建带标签的控件，并接入 gpEdgeAttrChanged。
func _gpAddEdgeField(gpEdge: GPPIDEdge, gpKey: String) -> void:
	var gpStd: GPProjectStandard = _gpEdgeStandard()
	var gpRow: HBoxContainer = _gpFieldRow(gpEdgeFieldLabel(gpKey, gpStd))
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
			# Any attribute with a non-empty project code table is a picker — this is what
			# makes `dn` a dropdown once the standard defines a dn table, and it also covers
			# project-standard custom fields without a second hard-coded field map.
			# 任何有非空项目代号表的属性都走下拉 —— 这就是项目标准定义 dn 表后管径变成
			# 下拉的原因，也让项目标准自定义字段无需第二张硬编码字段表。
			var gpChoices: Array[Dictionary] = gpEdgeAttrChoices(gpKey, gpStd)
			if not gpChoices.is_empty():
				_gpAddEdgeCodePicker(gpRow, gpEdge, gpKey, gpChoices)
				return
			_gpAddEdgeText(gpRow, gpEdge, gpKey)


# The code table behind an edge attribute key; "" when the field is not a code field.
# 边属性键背后的代号表；不是代号字段时返回 ""。
# A project-standard rule segment can name the table explicitly (material -> spec); otherwise
# the attribute key itself is tried, which is what makes `dn` use the `dn` table.
# 项目标准规则段可以显式指定表名（material -> spec）；否则直接试属性键本身 ——
# 这正是 `dn` 使用 `dn` 代号表的原因。
static func gpEdgeAttrTable(gpKey: String, gpStd: GPProjectStandard = null) -> String:
	if gpStd != null:
		var gpSeg: GPTagSegment = _gpLineSegmentFor(gpKey, gpStd)
		if gpSeg != null and gpSeg.gpTable != "" and not gpStd.gpCodeTable(gpSeg.gpTable).is_empty():
			return gpSeg.gpTable
		if not gpStd.gpCodeTable(gpKey).is_empty():
			return gpKey
	match gpKey:
		"medium":
			return GPProjectStandard.GP_TABLE_MEDIUM
		"spec":
			return GPProjectStandard.GP_TABLE_MATERIAL
		"insulation":
			return GPProjectStandard.GP_TABLE_INSULATION
	return ""


# Pickable codes for an edge attribute, straight from the project standard (pure + testable).
# 边属性的可选代号，直接取自项目标准（纯函数，可测试）。
static func gpEdgeAttrChoices(gpKey: String, gpStd: GPProjectStandard) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	var gpTable: String = gpEdgeAttrTable(gpKey, gpStd)
	if gpTable == "" or gpStd == null:
		return gpOut
	for gpRowRaw in gpStd.gpCodeTable(gpTable):
		if not (gpRowRaw is Dictionary):
			continue
		var gpRow: Dictionary = gpRowRaw as Dictionary
		var gpCode: String = str(gpRow.get("code", "")).strip_edges()
		if gpCode != "":
			gpOut.append({"code": gpCode, "label": str(gpRow.get("label", ""))})
	return gpOut


func _gpEdgeStandard() -> GPProjectStandard:
	if not gpStandardProvider.is_valid():
		return null
	var gpStdRaw: Variant = gpStandardProvider.call()
	return gpStdRaw as GPProjectStandard if gpStdRaw is GPProjectStandard else null


# Code picker for medium / pipe class / insulation: the table's codes ARE the options.
# 介质 / 管道等级 / 保温的代号下拉：表里的代号**就是**选项。
func _gpAddEdgeCodePicker(gpRow: HBoxContainer, gpEdge: GPPIDEdge, gpKey: String,
		gpChoices: Array[Dictionary]) -> void:
	var gpCur: String = str(gpEdge.gpAttrs.get(gpKey, "")).strip_edges()
	var gpOpt: OptionButton = OptionButton.new()
	gpOpt.size_flags_horizontal = SIZE_EXPAND_FILL
	gpOpt.add_item(I18n.gpTr("line_attrs.empty_choice"))
	gpOpt.set_item_metadata(0, "")
	var gpSel: int = 0
	for gpI in range(gpChoices.size()):
		var gpItem: Dictionary = gpChoices[gpI]
		var gpCode: String = str(gpItem.get("code", ""))
		var gpLabel: String = str(gpItem.get("label", ""))
		gpOpt.add_item("%s · %s" % [gpCode, gpLabel] if gpLabel != "" else gpCode)
		gpOpt.set_item_metadata(gpI + 1, gpCode)
		if gpCode == gpCur:
			gpSel = gpI + 1
	if gpSel == 0 and gpCur != "":
		# Keep an unknown legacy value visible instead of silently clearing it.
		# 保留未知的旧值可见，而不是静默清空它。
		gpOpt.add_item(I18n.gpTr("line_attrs.current_choice") % gpCur)
		gpOpt.set_item_metadata(gpOpt.item_count - 1, gpCur)
		gpSel = gpOpt.item_count - 1
	gpOpt.select(gpSel)
	var gpOriginal: String = gpCur
	gpOpt.item_selected.connect(func(gpI: int) -> void:
		var gpNew: String = str(gpOpt.get_item_metadata(gpI))
		if gpNew != gpOriginal:
			gpEdgeAttrChanged.emit(gpEdge.gpInstanceId, gpKey, gpNew))
	gpRow.add_child(gpOpt)


# Single-line text field that commits on Enter AND on losing focus. Committing on focus loss is
# what makes "type and click away" work — with Enter only, the edit looked like it did nothing.
# 单行文本字段：回车**以及失焦**时提交。失焦提交让「打完点别处」也能生效 —— 只认回车时，
# 这次编辑看起来就像什么都没发生。
func _gpAddEdgeText(gpRow: HBoxContainer, gpEdge: GPPIDEdge, gpKey: String) -> void:
	var gpEdit: LineEdit = LineEdit.new()
	gpEdit.size_flags_horizontal = SIZE_EXPAND_FILL
	gpEdit.text = gpEdge.gpTag if gpKey == "tag" else str(gpEdge.gpAttrs.get(gpKey, ""))
	var gpOriginal: String = gpEdit.text
	var gpCommit: Callable = func(gpV: String) -> void:
		if gpV.strip_edges() != gpOriginal.strip_edges():
			gpEdgeAttrChanged.emit(gpEdge.gpInstanceId, gpKey, gpV)
	gpEdit.text_submitted.connect(gpCommit)
	gpEdit.focus_exited.connect(func() -> void: gpCommit.call(gpEdit.text))
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
