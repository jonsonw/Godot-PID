class_name GPEditService
extends RefCounted
# Application editing service: user intent -> undoable command .
# 应用编辑服务：把用户意图翻译成可撤销的命令。
#
# Why this layer exists / 本层存在理由:
# place, connect, draw-commit), mixing "what the user asked for" with "how the canvas
# keeps itself in sync". This service is where that split lands: the canvas now asks
# "delete this selection" and gets a plain bool back, while the model mutation, the id
# allocation and the undo record are made here — with no reference to any widget.
# 每项用户可见的编辑原先都是 GPCanvas2D 里的内联代码（删除 / 复制 / 放置 / 连线 / 提交绘图），
# 把「用户要什么」与「画布如何自同步」混在一起。本服务就是那条分界线：画布现在只问
# 「删除这个选择集」并拿回一个 bool，而模型改动、id 分配与撤销记录都在此处完成 ——
# 全程不引用任何控件。
#
# Boundary / 边界:
# Model-only. Nothing here touches GPCanvas2D, GPEventBus or any node: mutations travel
# and view-only consequences (selection, mode, repaint) stay with the caller that owns
# them. That is what lets the whole service be unit-tested without a scene tree.
# 仅模型层。此处不触碰 GPCanvas2D、GPEventBus 或任何节点：改动经 GPPIDGraph.gpGraphChanged
# 到达视图（画布已在 M2 桥接），而纯视图后果（选择集、模式、重绘）留给持有它们的调用方。
# 这正是整个服务无需场景树即可单测的原因。
#
# M6 (PIDDocumentManager) will own one instance per document; until then the canvas holds it.
# M6（PIDDocumentManager）将为每个文档持有一份；在此之前由画布持有。

# What every command receives. Rebuilt whenever the displayed graph changes.
# 每条命令拿到的依赖。所显示图变化时重建。
var gpCtx: GPCommandContext = GPCommandContext.new()

# Undo/redo history for this document.
# 本文档的撤销 / 重做历史。
var gpStack: GPCommandStack = GPCommandStack.new()

# Machine-readable reason the most recent edge intent refused ("" when it succeeded). The canvas
# translates it through i18n for the status bar; the service itself never touches a widget.
# 最近一次连线意图拒绝执行的机器可读原因（成功时为 ""）。画布经 i18n 翻译后显示到状态栏；
# 服务本身绝不触碰控件。
var gpLastRefusal: String = ""

# Old->new mapping produced by the most recent gpRenumberTags(), so the shell can offer the
# audit CSV. Empty when no renumbering has run.
# 最近一次 gpRenumberTags() 产生的「旧→新」映射，供外壳提供对照表 CSV。
# 未执行过重编号时为空。
var gpLastTagMapping: Array[Dictionary] = []

# Edge ids whose endpoint was downgraded to the node centre by the most recent
# into the "ports went missing" warning.
# 外壳据此把非空列表转成「端口缺失」警告。
var gpLastSwapWarning: Array[String] = []


# Point the service at a (new) graph. The old history is dropped: undo must never reach
# back into a graph that is no longer displayed.
# 把服务指向（新的）图。旧历史被丢弃：撤销绝不能回到已不再显示的图。
# [param gpGraph] the topology to edit / 待编辑的拓扑图
# [param gpIds] shared id generator (ids stay unique across interactive + command edits)
# [param gpIds] 共享 id 生成器（使交互改动与命令改动的 id 保持唯一）
func gpBindGraph(gpGraph: GPPIDGraph, gpIds: GPIdGen, gpTags: GPTagRegistry = null) -> void:
	gpCtx = GPCommandContext.new(gpGraph, gpIds, gpTags)
	gpStack.gpClear()
	if gpTags != null:
		gpTags.gpGraph = gpGraph
 # The index is a cache: re-derive it so a document that was edited before this
 # service existed starts from the truth.
 # 索引是缓存：重新推导它，使在本服务存在之前就被编辑过的文档从真相出发。
		gpTags.gpRebuild()


# Renumber every equipment instance from the project's numbering rules . Returns false
# when the sheet has nothing to number. gpLastTagMapping carries the old->new rows afterwards.
# 按工程的编号规则重排所有设备实例。图纸无可编号对象时返回 false。
# 之后 gpLastTagMapping 携带「旧→新」各行。
func gpRenumberTags() -> bool:
	gpLastTagMapping = []
	var gpCmd: GPRenumberTagsCommand = GPRenumberTagsCommand.new()
	if not gpStack.gpDo(gpCmd, gpCtx):
		return false
	gpLastTagMapping = gpCmd.gpMapping()
	return true


# Replace the project's numbering rules in one undoable-ish step. Rules are configuration,
# not geometry: they are applied immediately and are NOT pushed onto the undo stack, because
# undoing "change the convention" after new instances were numbered with it would leave the
# sheet inconsistent. Renumbering (gpRenumberTags()) is the undoable operation.
# 一步替换工程的编号规则。规则是配置而非几何：立即生效，且**不**压入撤销栈——
# 因为在新实例已按新规则编号后再撤销「改约定」会让图纸自相矛盾。
# 重编号（gpRenumberTags()）才是可撤销的操作。
func gpSetTagRules(gpRules: GPProjectTagRules) -> bool:
	if gpCtx.gpGraph == null or gpRules == null:
		return false
	gpCtx.gpGraph.gpTagRules = gpRules
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpRules = gpRules
	return true


# The project's numbering rules, creating the factory default on first use.
# 工程的编号规则，首次使用时建立出厂默认。
func gpTagRules() -> GPProjectTagRules:
	if gpCtx.gpGraph == null:
		return GPProjectTagRules.gpDefaultRules()
	return gpCtx.gpGraph.gpTagRulesOrCreate()


# ============================ intents ============================
# ============================ 用户意图 ============================

# Delete a mixed selection (nodes with their edges, plus annotation shapes) as one step.
# Returns false when nothing was deleted, so the caller can skip the repaint.
# 把混合选择集（节点及其连边，外加注释图形）作为一步删除。
# 未删掉任何东西时返回 false，调用方可据此跳过重绘。
#
# gpDefLookup is what lets the node half recognise a REQUIRED part (an A-class built-in nozzle) and
# refuse to delete it (规划 §16.2); passing an invalid lookup disables only that guard.
# gpDefLookup 使节点部分能识别**必需**部件（A 类自带管口）并拒绝对其删除（规划 §16.2）；
# 传入无效查找器只会关闭该护栏。
func gpDeleteSelection(gpNodeIds: Array[String], gpShapeIdxs: Array[int],
		gpEdgeIds: Array[String] = [], gpDefLookup: Callable = Callable()) -> bool:
	if gpNodeIds.is_empty() and gpShapeIdxs.is_empty() and gpEdgeIds.is_empty():
		return false
	var gpCmd: GPDeleteSelectionCommand = GPDeleteSelectionCommand.new(gpNodeIds, gpShapeIdxs,
		gpEdgeIds, gpDefLookup)
	return gpStack.gpDo(gpCmd, gpCtx)


# Copy nodes to a small offset. Returns the ids of the copies (empty when nothing was
# copied) so the caller can move the selection to them.
# 把节点复制到小幅偏移处。返回副本 id（未复制时为空），调用方可据此把选择集移到副本上。
func gpDuplicateSelection(gpNodeIds: Array[String]) -> Array[String]:
	if gpNodeIds.is_empty():
		return []
	var gpCmd: GPDuplicateNodesCommand = GPDuplicateNodesCommand.new(gpNodeIds)
	if not gpStack.gpDo(gpCmd, gpCtx):
		return []
	return gpCmd.gpNewIds.duplicate()


# Place one symbol instance. Returns the new node's id, or "" when it could not be placed.
# 放置一个图元实例。返回新节点 id，无法放置时返回 ""。
# Move one instance's tag relative to its symbol . One undo step per drag.
# 移动一个实例上标签相对其图元的位置。每次拖拽一个撤销步。
func gpSetLabelOffset(gpNodeId: String, gpOffset: Vector2) -> bool:
	if gpNodeId == "":
		return false
	var gpCmd: GPSetLabelOffsetCommand = GPSetLabelOffsetCommand.new(gpNodeId, gpOffset)
	return gpStack.gpDo(gpCmd, gpCtx)


# Move one edge's line number off its automatic placement . One undo step per drag.
# 把一条边的管线号移离其自动落位处。每次拖拽一个撤销步。
# A zero offset is legal and means "back to the automatic placement" — the command's model
# accessor erases the stored key, so a reset leaves nothing behind.
# 零偏移合法，意为「回到自动落位处」—— 命令所用的模型存取器会删除该存储键，故复位不留痕迹。
func gpSetEdgeTagOffset(gpEdgeId: String, gpOffset: Vector2) -> bool:
	if gpEdgeId == "":
		return false
	var gpCmd: GPSetEdgeTagOffsetCommand = GPSetEdgeTagOffsetCommand.new(gpEdgeId, gpOffset)
	return gpStack.gpDo(gpCmd, gpCtx)


# connection survive; only gpSymbolId changes. Edge endpoints whose port name the NEW symbol
# does not declare are downgraded to the node centre and reported in gpLastSwapWarning.
# 只有 gpSymbolId 变更。新图元未声明其端口名的边端点会降级到图元中心，
# 并记录在 gpLastSwapWarning 中。
func gpReplaceSymbol(gpNodeId: String, gpNewDef: GPSymbolDef) -> bool:
	gpLastSwapWarning = []
	if gpNodeId == "" or gpNewDef == null:
		return false
	var gpCmd: GPReplaceSymbolCommand = GPReplaceSymbolCommand.new(gpNodeId, gpNewDef)
	if not gpStack.gpDo(gpCmd, gpCtx):
		return false
	gpLastSwapWarning = gpCmd.gpDowngraded()
	return true


# ---- M11: undoable attribute / tag / name / anchor edits ----
# ---- M11：可撤销的属性 / 位号 / 名称 / 锚点编辑 ----
# Every user-visible edit reaches the model through a command from here on, so Ctrl+Z reverses
# it and the dirty flag (driven by gpGraphChanged) is set exactly once per edit.
# 从此每个用户可见的编辑都经命令进入模型，故 Ctrl+Z 可撤销，
# 且脏标记（由 gpGraphChanged 驱动）每次编辑恰好置一次。

# Change one instance's tag. A tag already used by another instance is refused up front, so the
# shell can say WHY — the command itself also returns false for "nothing changed", which is not
# an error and must not be reported as one.
# 修改某个实例的位号。已被其他实例占用的位号在此**提前**拒绝，使外壳能说明原因
# —— 命令本身对「无实际变化」也返回 false，那不是错误，不能当成错误上报。
func gpSetTag(gpNodeId: String, gpTag: String) -> bool:
	gpLastRefusal = ""
	if gpNodeId == "":
		return false
	var gpWant: String = gpTag.strip_edges()
	if gpCtx.gpTags != null and gpWant != "":
		gpCtx.gpTags.gpGraph = gpCtx.gpGraph
		if gpCtx.gpTags.gpIsTaken(gpWant, gpNodeId):
			gpLastRefusal = "tag.err_duplicate"
			return false
	var gpCmd: GPSetTagCommand = GPSetTagCommand.new(gpNodeId, gpTag)
	return gpStack.gpDo(gpCmd, gpCtx)


# Change one instance's name in one language, e.g. gpLocale = "zh_CN".
# 修改某个实例在某一语种下的名称，如 gpLocale = "zh_CN"。
func gpSetName(gpNodeId: String, gpLocale: String, gpText: String) -> bool:
	gpLastRefusal = ""
	if gpNodeId == "" or gpLocale == "":
		return false
	var gpCmd: GPSetNameCommand = GPSetNameCommand.new(gpNodeId, gpLocale, gpText)
	return gpStack.gpDo(gpCmd, gpCtx)


# Set one property value. An EMPTY string resets the field to the library default.
# 设置一个属性值。空字符串将该字段复位到库默认值。
func gpSetProperty(gpNodeId: String, gpKey: String, gpValue: Variant) -> bool:
	gpLastRefusal = ""
	if gpNodeId == "" or gpKey == "":
		return false
	var gpCmd: GPSetPropertyCommand = GPSetPropertyCommand.new(gpNodeId, gpKey, gpValue)
	return gpStack.gpDo(gpCmd, gpCtx)


# Set the coarse label anchor (GPLabelAnchor.GPAnchor.* or GPPropertyResolver.GP_ANCHOR_UNSET).
# 设置粗粒度标签锚点（GPLabelAnchor.GPAnchor.* 或 GPPropertyResolver.GP_ANCHOR_UNSET）。
func gpSetLabelAnchor(gpNodeId: String, gpAnchor: int) -> bool:
	gpLastRefusal = ""
	if gpNodeId == "":
		return false
	var gpCmd: GPSetLabelAnchorCommand = GPSetLabelAnchorCommand.new(gpNodeId, gpAnchor)
	return gpStack.gpDo(gpCmd, gpCtx)


# Apply one edit to a whole selection as a single undo step. "tag" is refused (it is unique).
# 把一次编辑作用到整个选择集，只产生一个撤销步。"tag" 被拒绝（位号必须唯一）。
func gpBatchSetProperty(gpNodeIds: Array[String], gpKey: String, gpValue: Variant) -> bool:
	gpLastRefusal = ""
	if gpNodeIds.is_empty() or gpKey == "":
		return false
	var gpCmd: GPBatchSetPropertyCommand = GPBatchSetPropertyCommand.new(gpNodeIds, gpKey, gpValue)
	return gpStack.gpDo(gpCmd, gpCtx)


# Place one symbol instance. Returns the new node's id, or "" when it could not be placed.
# 放置一个图元实例。返回新节点 id，无法放置时返回 ""。
#
# The returned id is the HOST's. Placing a vessel also instantiates its built-in parts (nozzles,
# manhole — 规划 §16) as ONE undo step, but they are secondary symbols and are deliberately not
# what the caller selects next.
# 返回的是**宿主** id。放置一台设备会同时实例化其自带部件（管口、人孔 —— 规划 §16），
# 全在**一个**撤销步内；但它们是次级图元，刻意不是调用方随后要选中的对象。
#
# gpDefLookup lets the command recognise the host's default children; an invalid lookup falls back
# to the global symbol library, so a caller that has a binder should still pass it in.
# gpDefLookup 使命令能识别宿主的默认子件；无效时回退到全局图元库，
# 故持有绑定器的调用方仍应把它传进来。
func gpPlaceNode(gpSymbolId: String, gpWorld: Vector2, gpTag: String = "",
		gpDefLookup: Callable = Callable()) -> String:
	if gpSymbolId == "":
		return ""
	var gpCmd: GPAddNodeCommand = GPAddNodeCommand.new(gpSymbolId, gpWorld, gpTag, gpDefLookup)
	if not gpStack.gpDo(gpCmd, gpCtx):
		return ""
	return gpCmd.gpCreatedId


# ---- P2: primary / secondary symbols (主图元 / 次级图元) ----
# ---- P2：主图元 / 次级图元 ----

# Attach one child onto a host anchor. Returns the new node's id, or "" when it was refused.
# 把一个子件挂到宿主锚点上。返回新节点 id；被拒时返回 ""。
#
# The refusal is machine-readable in gpLastRefusal (mirrors gpConnectEdgeRouted()): the two attach
# interactions both need to explain WHY nothing happened, and "the host is gone" is the only case
# the UI cannot pre-check cheaply.
# 拒绝原因以机器可读形式存入 gpLastRefusal（与 gpConnectEdgeRouted() 一致）：
# 两种附件交互都需要说明「为何什么都没发生」，而「宿主已消失」是 UI 无法廉价预检的唯一情形。
func gpAttachNode(gpSymbolId: String, gpParentUid: String, gpAnchor: String,
		gpTag: String = "", gpOffset: Vector2 = Vector2.ZERO,
		gpAngleDeg: float = 0.0) -> String:
	gpLastRefusal = ""
	if gpSymbolId == "" or gpParentUid == "":
		# PREFIX-FREE, like the edge refusals: the "attach." namespace is added downstream by
		# GPCanvasEditFacade.gpReportRefusal() (see attach_node_command.gd for the full reasoning).
		# **不带前缀**，与边的拒绝原因一致："attach." 命名空间由下游的
		# GPCanvasEditFacade.gpReportRefusal() 添加（完整理由见 attach_node_command.gd）。
		gpLastRefusal = "no_host"
		return ""
	var gpCmd: GPAttachNodeCommand = GPAttachNodeCommand.new(gpSymbolId, gpParentUid, gpAnchor,
		gpTag, gpOffset, gpAngleDeg)
	if not gpStack.gpDo(gpCmd, gpCtx):
		gpLastRefusal = gpCmd.gpRefusal
		return ""
	return gpCmd.gpCreatedId


# Detach the given nodes from their hosts, baking each derived world transform into its own fields
# so nothing jumps. Returns false when none of them was mounted.
# 把给定节点从其宿主上卸下，并把推导出的世界变换烘焙进各自字段，使任何东西都不跳位。
# 若没有一个处于挂载态则返回 false。
func gpDetachNodes(gpNodeIds: Array[String], gpDefLookup: Callable = Callable()) -> bool:
	if gpNodeIds.is_empty():
		return false
	var gpCmd: GPDetachNodesCommand = GPDetachNodesCommand.new(gpNodeIds, gpDefLookup)
	return gpStack.gpDo(gpCmd, gpCtx)


# Re-mount nodes onto new (host, anchor, offset, angle) tuples as ONE undo step. Returns false when
# nothing actually changed, so a drag that ends on the anchor it started from records no undo step.
# 一步把节点改挂到新的 (宿主, 锚点, 偏移, 角) 元组上。若实际无变化则返回 false，
# 使「拖了一圈又落回原锚点」不产生撤销步。
#
# ⚠️ COMMIT ORDER (same trap as gpMoveNodes) / 提交时序（与 gpMoveNodes 同一个坑）：
# During a drag the caller has ALREADY written the tuples live (that is how the part followed the
# cursor). It must therefore RESTORE the pre-drag tuple before calling this, so the command sees a
# real change and re-applies exactly the user's drag. Calling it with the live values still in place
# makes the "nothing changed" guard fire, the stack records nothing, and the drag silently becomes
# un-undoable — which is precisely the class of bug the guard exists to catch, not to cause.
# 拖拽期间调用方**已经**把元组实时写入（部件跟随光标即由此而来）。因此它必须在此调用前**先恢复**
# 拖拽前的元组，使命令看到真实变化并重新应用用户的那次拖拽。若带着实时结果调用，命令的
# 「无变化」护栏会触发、栈什么也不记、这次拖拽就静默变成不可撤销 —— 而那恰是该护栏要**抓住**、
# 而非造成的缺陷类别。
func gpSetMount(gpNodeIds: Array[String], gpTargets: Array[Dictionary]) -> bool:
	if gpNodeIds.is_empty() or gpTargets.is_empty():
		return false
	var gpCmd: GPSetMountCommand = GPSetMountCommand.new(gpNodeIds, gpTargets)
	return gpStack.gpDo(gpCmd, gpCtx)


# Connect two nodes with an edge. Returns false for a self-connection or a missing graph.
# 在两个节点之间连线。自连接或缺图时返回 false。
func gpConnect(gpFromId: String, gpToId: String) -> bool:
	var gpCmd: GPConnectCommand = GPConnectCommand.new(gpFromId, gpToId)
	return gpStack.gpDo(gpCmd, gpCtx)


# ---- P3: port-aware edge intents ----
# ---- P3：端口感知的连线意图 ----

# Draw a pipe or a signal line between two resolved ends. Returns the new edge's id, or "" when
# the command refused (both ends dangling, a self-loop, or an exact duplicate) — in which case
# gpLastRefusal carries the machine-readable reason for the status bar.
# 在两个已解析的端点之间画一条管道或信号线。返回新边 id；命令拒绝时返回 ""
# （两端皆悬空、自环或完全重复）—— 此时 gpLastRefusal 带有供状态栏使用的机器可读原因。
func gpConnectEdge(gpFromRef: Dictionary, gpToRef: Dictionary, gpKind: String,
		gpSignalType: String = "", gpOrtho: bool = true) -> String:
	var gpCmd: GPConnectEdgeCommand = GPConnectEdgeCommand.new(gpFromRef, gpToRef, gpKind,
		gpSignalType, gpOrtho)
	if not gpStack.gpDo(gpCmd, gpCtx):
		gpLastRefusal = gpCmd.gpRefusal
		return ""
	gpLastRefusal = ""
	return gpCmd.gpCreatedId


# Draw a pipe / signal line whose MIDDLE waypoints were computed up front (auto-routing).
# 画一条「中间折点已预先算好」的管道 / 信号线（自动布线）。
# Why a separate intent instead of "connect then set-routing" / 为何单开意图而非「先连再改折点」：
# two commands would mean two undo steps for what the user experiences as ONE action ("auto
# connect"). Carrying the waypoints on the create command keeps it a single step.
# 两条命令会把用户感知为「一个动作」的操作变成两个撤销步。把折点挂在创建命令上，保持一步。
# The result is an ordinary edge with gpRouting filled in — it stays editable by every existing
# tool, so automatic and manual routing genuinely coexist.
# 结果就是一条填了 gpRouting 的普通边 —— 它仍可被所有既有工具编辑，故自动与手动布线真正并存。
func gpConnectEdgeRouted(gpFromRef: Dictionary, gpToRef: Dictionary, gpKind: String,
		gpRouting: Array[Vector2], gpSignalType: String = "") -> String:
	var gpCmd: GPConnectEdgeCommand = GPConnectEdgeCommand.new(gpFromRef, gpToRef, gpKind,
		gpSignalType, true)
	gpCmd.gpRouting = gpRouting.duplicate()
	if not gpStack.gpDo(gpCmd, gpCtx):
		gpLastRefusal = gpCmd.gpRefusal
		return ""
	gpLastRefusal = ""
	return gpCmd.gpCreatedId


# Delete edges by id as one step, restoring them at their original indices on undo.
# 按 id 删除边（一步），撤销时按原下标恢复。
func gpDeleteEdges(gpEdgeIds: Array[String]) -> bool:
	if gpEdgeIds.is_empty():
		return false
	var gpCmd: GPDeleteEdgesCommand = GPDeleteEdgesCommand.new(gpEdgeIds)
	return gpStack.gpDo(gpCmd, gpCtx)


# Rename an edge's line number. / 修改一条边的管线号。
func gpSetEdgeTag(gpEdgeId: String, gpTag: String) -> bool:
	var gpCmd: GPSetEdgeTagCommand = GPSetEdgeTagCommand.new(gpEdgeId, gpTag)
	return gpStack.gpDo(gpCmd, gpCtx)


# Set one well-known attribute (dn / medium / spec / insulation / show_arrow / show_tag / ...).
# 设置一个约定属性（dn / medium / spec / insulation / show_arrow / show_tag / …）。
func gpSetEdgeAttr(gpEdgeId: String, gpKey: String, gpValue: Variant) -> bool:
	var gpCmd: GPSetEdgeAttrCommand = GPSetEdgeAttrCommand.new(gpEdgeId, gpKey, gpValue)
	return gpStack.gpDo(gpCmd, gpCtx)


# Replace an edge's intermediate waypoints. / 替换一条边的中间拐点。
func gpSetEdgeRouting(gpEdgeId: String, gpRouting: Array[Vector2]) -> bool:
	var gpCmd: GPSetEdgeRoutingCommand = GPSetEdgeRoutingCommand.new(gpEdgeId, gpRouting)
	return gpStack.gpDo(gpCmd, gpCtx)


# Record a drop-on-edge restore entry as one undo step, so undoing the drop also clears the
# symbol's restore history (Feature 2: deleting a dropped symbol restores the original line).
# 把落点恢复记录作为一步撤销写入，使撤销落点也会清除该图元的恢复历史
# （功能 2：删除压到连线上的图元会还原原始连线）。
func gpRecordDrop(gpSymNid: String, gpRecord: Dictionary) -> void:
	var gpCmd: GPSetDropRestoreCommand = GPSetDropRestoreCommand.new(gpSymNid, gpRecord)
	gpStack.gpDo(gpCmd, gpCtx)


# Move one end of an edge to another port / node, or make it dangle.
# 把一条边的一端改接到另一个端口 / 节点，或改为悬空。
func gpReconnectEdge(gpEdgeId: String, gpIsFrom: bool, gpNewRef: Dictionary) -> bool:
	var gpCmd: GPReconnectEdgeCommand = GPReconnectEdgeCommand.new(gpEdgeId, gpIsFrom, gpNewRef)
	return gpStack.gpDo(gpCmd, gpCtx)


# Change an edge's kind (and signal type for SIGNAL edges). One undo step; the style table is a
# pure function of (kind, signal_type) so the canvas repaints immediately with no data migration.
# 改变边的类型（信号线另带信号类型）。一个撤销步；样式表为 (kind, signal_type) 纯函数，
# 故画布立即重绘，无需数据迁移。
func gpSetEdgeKind(gpEdgeId: String, gpKind: String, gpSignalType: String = "") -> bool:
	var gpCmd: GPSetEdgeKindCommand = GPSetEdgeKindCommand.new(gpEdgeId, gpKind, gpSignalType)
	return gpStack.gpDo(gpCmd, gpCtx)


# Re-resolve an edge's ends to real ports (legacy centre lines -> port lines). The def lookup is
# supplied by the caller (the canvas owns the symbol table). One undo step.
# 把边的两端重新吸附到真实端口（老档中心连线 -> 端口连线）。图元表由调用方提供（画布持有）。
# 一个撤销步。
func gpSnapEdgeEnds(gpEdgeId: String, gpDefLookup: Callable) -> bool:
	var gpCmd: GPResnapEdgeCommand = GPResnapEdgeCommand.new(gpEdgeId, gpDefLookup)
	return gpStack.gpDo(gpCmd, gpCtx)


# Renumber every process / utility pipe with fresh PL tags (hand-set and signal-line tags kept).
# 用全新 PL 位号重排每条工艺 / 公用工程管线（保留手工号与信号线）。一个撤销步。
func gpRenumberEdges() -> bool:
	var gpCmd: GPRenumberCommand = GPRenumberCommand.new()
	return gpStack.gpDo(gpCmd, gpCtx)


# Translate nodes by a delta as one undo step. Used when a drag finishes: the caller rewinds
# the nodes to their pre-drag positions first, so the command re-applies the same move the
# user just performed (rather than applying it a second time on top of the live result).
# Returns false for an empty selection or a zero delta, so a plain click records nothing.
# 把节点按位移量平移，作为一步撤销。用于拖拽结束：调用方先把节点回退到拖拽前位置，
# 使命令重新应用的正是用户刚做的那次移动（而非在实时结果之上再叠一次）。
# 空选择集或零位移返回 false，故普通单击不会留下撤销步。
func gpMoveNodes(gpNodeIds: Array[String], gpDelta: Vector2) -> bool:
	if gpNodeIds.is_empty() or gpDelta.is_zero_approx():
		return false
	var gpCmd: GPMoveNodesCommand = GPMoveNodesCommand.new(gpNodeIds, gpDelta)
	return gpStack.gpDo(gpCmd, gpCtx)


# Set absolute positions of one or more nodes in one undo step (collision-avoidance push during
# placement and dragging). Returns false for an empty target map or when no target differs from
# the node's live position, so a placement/drag that needed no push records no extra undo step.
# 一步设置多个节点的绝对位置（放置与拖拽时的碰撞避让推送）。目标为空、或没有任何目标与节点
# 实时位置不同（即无需推送）时返回 false，避免多记一个撤销步。
func gpSetNodePositions(gpTargets: Dictionary) -> bool:
	if gpCtx.gpGraph == null or gpTargets.is_empty():
		return false
	var gpChanges: bool = false
	for gpId in gpTargets.keys():
		var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
		if gpN != null and (gpN.gpPosition as Vector2) != (gpTargets[gpId] as Vector2):
			gpChanges = true
			break
	if not gpChanges:
		return false
	var gpCmd: GPSetNodePositionsCommand = GPSetNodePositionsCommand.new(gpTargets)
	return gpStack.gpDo(gpCmd, gpCtx)


# Commit a finished annotation shape. Returns its index in gpShapes(), or -1 on failure.
# 提交一枚绘制完成的注释图形。返回它在 gpShapes() 中的下标，失败返回 -1。
func gpAddShape(gpShape: GPShape) -> int:
	if gpShape == null or gpCtx.gpGraph == null:
		return -1
	var gpCmd: GPAddShapeCommand = GPAddShapeCommand.new(gpShape)
	if not gpStack.gpDo(gpCmd, gpCtx):
		return -1
	return gpCtx.gpGraph.gpShapes.find(gpShape)


# ============================ history ============================
# ============================ 历史 ============================

# Undo the last command. Returns false when there is nothing to undo.
# 撤销最近一条命令。无可撤销时返回 false。
func gpUndo() -> bool:
	return gpStack.gpUndo(gpCtx)


# Redo the last undone command. Returns false when there is nothing to redo.
# 重做最近被撤销的命令。无可重做时返回 false。
func gpRedo() -> bool:
	return gpStack.gpRedo(gpCtx)


# Whether an undo step is available (for enabling menu items).
# 是否存在可撤销的步骤（用于启用菜单项）。
func gpCanUndo() -> bool:
	return gpStack.gpCanUndo()


# Whether a redo step is available.
# 是否存在可重做的步骤。
func gpCanRedo() -> bool:
	return gpStack.gpCanRedo()


# Label of the next undo step, e.g. "删除" for menus and the status bar.
# 下一个撤销步的标签（如「删除」），供菜单与状态栏显示。
func gpUndoLabel() -> String:
	return gpStack.gpUndoLabel()


# Label of the next redo step.
# 下一个重做步的标签。
func gpRedoLabel() -> String:
	return gpStack.gpRedoLabel()
