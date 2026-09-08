class_name GPEditService
extends RefCounted
# Application editing service: user intent -> undoable command (M4 continued).
# 应用编辑服务：把用户意图翻译成可撤销的命令（M4 续）。
#
# Why this layer exists / 本层存在理由:
#   Every user-visible edit used to be inline code inside GPCanvas2D (delete, duplicate,
#   place, connect, draw-commit), mixing "what the user asked for" with "how the canvas
#   keeps itself in sync". This service is where that split lands: the canvas now asks
#   "delete this selection" and gets a plain bool back, while the model mutation, the id
#   allocation and the undo record are made here — with no reference to any widget.
#   每项用户可见的编辑原先都是 GPCanvas2D 里的内联代码（删除 / 复制 / 放置 / 连线 / 提交绘图），
#   把「用户要什么」与「画布如何自同步」混在一起。本服务就是那条分界线：画布现在只问
#   「删除这个选择集」并拿回一个 bool，而模型改动、id 分配与撤销记录都在此处完成 ——
#   全程不引用任何控件。
#
# Boundary / 边界:
#   Model-only. Nothing here touches GPCanvas2D, GPEventBus or any node: mutations travel
#   to the view through GPPIDGraph.gpGraphChanged, which the canvas already bridges (M2),
#   and view-only consequences (selection, mode, repaint) stay with the caller that owns
#   them. That is what lets the whole service be unit-tested without a scene tree.
#   仅模型层。此处不触碰 GPCanvas2D、GPEventBus 或任何节点：改动经 GPPIDGraph.gpGraphChanged
#   到达视图（画布已在 M2 桥接），而纯视图后果（选择集、模式、重绘）留给持有它们的调用方。
#   这正是整个服务无需场景树即可单测的原因。
#
# M6 (PIDDocumentManager) will own one instance per document; until then the canvas holds it.
# M6（PIDDocumentManager）将为每个文档持有一份；在此之前由画布持有。

# What every command receives. Rebuilt whenever the displayed graph changes.
# 每条命令拿到的依赖。所显示图变化时重建。
var gpCtx: GPCommandContext = GPCommandContext.new()

# Undo/redo history for this document.
# 本文档的撤销 / 重做历史。
var gpStack: GPCommandStack = GPCommandStack.new()


# Point the service at a (new) graph. The old history is dropped: undo must never reach
# back into a graph that is no longer displayed.
# 把服务指向（新的）图。旧历史被丢弃：撤销绝不能回到已不再显示的图。
# [param gpGraph] the topology to edit / 待编辑的拓扑图
# [param gpIds] shared id generator (ids stay unique across interactive + command edits)
# [param gpIds] 共享 id 生成器（使交互改动与命令改动的 id 保持唯一）
func gpBindGraph(gpGraph: GPPIDGraph, gpIds: GPIdGen) -> void:
	gpCtx = GPCommandContext.new(gpGraph, gpIds)
	gpStack.gpClear()


# ============================ intents ============================
# ============================ 用户意图 ============================

# Delete a mixed selection (nodes with their edges, plus annotation shapes) as one step.
# Returns false when nothing was deleted, so the caller can skip the repaint.
# 把混合选择集（节点及其连边，外加注释图形）作为一步删除。
# 未删掉任何东西时返回 false，调用方可据此跳过重绘。
func gpDeleteSelection(gpNodeIds: Array[String], gpShapeIdxs: Array[int]) -> bool:
	if gpNodeIds.is_empty() and gpShapeIdxs.is_empty():
		return false
	var gpCmd: GPDeleteSelectionCommand = GPDeleteSelectionCommand.new(gpNodeIds, gpShapeIdxs)
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
func gpPlaceNode(gpSymbolId: String, gpWorld: Vector2, gpTag: String = "") -> String:
	if gpSymbolId == "":
		return ""
	var gpCmd: GPAddNodeCommand = GPAddNodeCommand.new(gpSymbolId, gpWorld, gpTag)
	if not gpStack.gpDo(gpCmd, gpCtx):
		return ""
	return gpCmd.gpCreatedId


# Connect two nodes with an edge. Returns false for a self-connection or a missing graph.
# 在两个节点之间连线。自连接或缺图时返回 false。
func gpConnect(gpFromId: String, gpToId: String) -> bool:
	var gpCmd: GPConnectCommand = GPConnectCommand.new(gpFromId, gpToId)
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


# Commit a finished annotation shape. Returns its index in gpShapes, or -1 on failure.
# 提交一枚绘制完成的注释图形。返回它在 gpShapes 中的下标，失败返回 -1。
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
