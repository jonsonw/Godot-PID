class_name GPAddNodeCommand
extends GPCommand
# Place one symbol instance on the sheet (M4).
# 在图纸上放置一个图元实例（M4）。
#
# Redo rule / 重做规则:
#   The created node object is kept, so redo re-adds the SAME object with the SAME id.
#   Re-running gpExecute on redo would call gpIds.gpNext() again and hand the node a
#   brand-new id, silently breaking every edge and every external reference to it.
#   保留所创建的节点对象，因此重做会用相同 id 重新加入同一对象。
#   若重做时再次执行 gpExecute，会再调 gpIds.gpNext() 拿到全新 id，
#   从而静默断开所有关联边与外部引用。

# Symbol definition id to instantiate (e.g. "pump_centrifugal").
# 要实例化的图元定义 id（如 "pump_centrifugal"）。
var gpSymbolId: String = ""

# Tag/label shown next to the instance (e.g. "P-101"). May be empty.
# 实例旁显示的位号 / 标签（如 "P-101"）。可为空。
var gpTag: String = ""

# Where to place it, in world coordinates.
# 放置位置（世界坐标）。
var gpPos: Vector2 = Vector2.ZERO

# The node this command created. Kept so undo/redo stay id-stable (see header).
# 本命令创建的节点。保留它以保证撤销 / 重做时 id 稳定（见头部说明）。
var _gpNode: GPPIDNode = null


# Build the command. gpInSymbolId selects the symbol, gpInPos is the world position,
# gpInTag is the optional tag text.
# 构造命令：gpInSymbolId 选择图元，gpInPos 为世界坐标，gpInTag 为可选位号。
func _init(gpInSymbolId: String, gpInPos: Vector2, gpInTag: String = "") -> void:
	gpSymbolId = gpInSymbolId
	gpPos = gpInPos
	gpTag = gpInTag
	gpLabel = "添加节点"


# Create (first run) or re-add (redo) the node.
# 首次运行时创建节点，重做时重新加入。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or not gpCtx.gpIsReady():
		return false
	if _gpNode == null:
		var gpId: String = gpCtx.gpIds.gpNext("N")
		_gpNode = gpCtx.gpGraph.gpNewNode(gpId, gpSymbolId, gpTag, gpPos)
	gpCtx.gpGraph.gpAddNode(_gpNode)
	return true


# Remove the node again. Edges touching it are NOT removed: a freshly added node has
# none, and removing any would lose user work on undo.
# 再次移除该节点。不删除其关联边：刚添加的节点本无边，且删边会让用户在撤销时丢工作。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpNode == null:
		return
	gpCtx.gpGraph.gpRemoveNode(_gpNode.gpInstanceId)


# Re-add the very same node object, preserving its id.
# 重新加入同一个节点对象，保持其 id 不变。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if _gpNode == null:
		gpExecute(gpCtx)
		return
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	gpCtx.gpGraph.gpAddNode(_gpNode)
