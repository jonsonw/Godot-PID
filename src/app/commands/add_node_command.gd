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


# Id of the created node, for the caller to select it right after placing. Empty before
# gpExecute has run.
# 所创建节点的 id，供调用方在放置后立即选中它。gpExecute 未运行时为空。
var gpCreatedId: String:
	get: return _gpNode.gpInstanceId if _gpNode != null else ""


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
		# "n" (lower case) is the project-wide node-id prefix: the canvas's own placement path
		# and every saved file use it. An upper-case "N" here silently forks the id namespace.
		# "n"（小写）是全项目统一的节点 id 前缀：画布自身的放置路径与所有存档文件都用它。
		# 此处若用大写 "N" 会静默地分叉 id 命名空间。
		var gpId: String = gpCtx.gpIds.gpNext("n")
		# Auto-number when the caller supplied no tag (M9): the sheet must show a tag, and a
		# tag must be unique project-wide. Done HERE rather than in gpRedo so the minted tag
		# is stored on the kept node object and survives undo/redo unchanged.
		# 调用方未给位号时自动编号（M9）：图纸上要显示位号，且位号必须工程级唯一。
		# 在此处而非 gpRedo 中编号，使铸造出的位号存留在被保留的节点对象上，
		# 撤销/重做后保持不变。
		var gpTagToUse: String = gpTag
		if gpTagToUse == "" and gpCtx.gpTags != null:
			gpCtx.gpTags.gpGraph = gpCtx.gpGraph
			gpTagToUse = gpCtx.gpTags.gpNextTag(GPSymbolLibrary.gpFindById(gpSymbolId))
		_gpNode = gpCtx.gpGraph.gpNewNode(gpId, gpSymbolId, gpTagToUse, gpPos)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRegister(_gpNode.gpInstanceId, _gpNode.gpTag)
	gpCtx.gpGraph.gpAddNode(_gpNode)
	return true


# Remove the node again. Edges touching it are NOT removed: a freshly added node has
# none, and removing any would lose user work on undo.
# 再次移除该节点。不删除其关联边：刚添加的节点本无边，且删边会让用户在撤销时丢工作。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpNode == null:
		return
	gpCtx.gpGraph.gpRemoveNode(_gpNode.gpInstanceId)
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpRelease(_gpNode.gpInstanceId)


# Re-add the very same node object, preserving its id.
# 重新加入同一个节点对象，保持其 id 不变。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if _gpNode == null:
		gpExecute(gpCtx)
		return
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	gpCtx.gpGraph.gpAddNode(_gpNode)
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpRegister(_gpNode.gpInstanceId, _gpNode.gpTag)
