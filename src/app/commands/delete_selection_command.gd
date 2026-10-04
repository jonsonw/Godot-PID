class_name GPDeleteSelectionCommand
extends GPCommand
# Delete a MIXED selection (nodes + annotation shapes + edges) as ONE undo step .
# 把混合选择集（节点 + 注释图形 + 边）作为「一个撤销步」删除。
#
# Why a composite / 为何做成组合命令:
# A marquee can catch nodes and shapes at once. Pushing two separate commands would make
# the user press Ctrl+Z twice to undo what looked like a single Delete — the classic
# "undo granularity must match the perceived action" rule. The edge half is added in W4 so
# pressing Del on a selected pipe is also one step.
# 一次框选可以同时框住节点与图形。若压入两条独立命令，用户要按两次 Ctrl+Z 才能撤销
# 看起来是一次删除的动作 —— 违反了「撤销粒度必须与感知到的一次操作对齐」这条经典规则。
# 边的部分于 W4 补入，使在选中管线上按 Del 同样只算一步。

# Node half of the deletion (nodes + their touching edges).
# 删除的节点部分（节点 + 其关联边）。
var _gpNodes: GPDeleteNodesCommand = null

# Annotation-shape half of the deletion.
# 删除的注释图形部分。
var _gpShapes: GPDeleteShapesCommand = null

# Edge half of the deletion (only edges NOT attached to a deleted node — those are removed by the
# node half, so including them here would double-delete and double-insert on undo).
# 删除的边部分（仅含未依附于被删节点的边 —— 依附者已由节点部分删除，重复纳入会双重删除并在撤销时
# 重复插入）。
var _gpEdges: GPDeleteEdgesCommand = null

# Deleted node ids, captured at construction so gpExecute() can look up each symbol's restore
# records even after the nodes are gone. / 被删节点 id，构造时捕获，使 gpExecute() 能在节点删后按 id 找到恢复记录。
var _gpNodeIds: Array[String] = []

# 4th half: replay drop-restore records for deleted symbols so a symbol dropped/moved onto a line
# brings its original line back in the SAME undo step (Feature: delete restores the original line).
# 第 4 部分：重放被删图元的落点恢复记录，使「压到连线上的图元」在「同一撤销步」内还原出原始连线。
var _gpRestore: GPRestoreDroppedEdgesCommand = null


# Build the command from the current selection: node ids, shape indices and edge ids.
# 由当前选择集构造命令：节点 id、图形下标与边 id。
# gpInLookup resolves symbol definitions; the node half needs it to recognise a REQUIRED part (an
# A-class built-in nozzle) and refuse to delete it. An invalid lookup just disables that guard.
# gpInLookup 解析图元定义；节点部分需要它来识别**必需**部件（A 类自带管口）并拒绝对其删除。
# 无效查找器只是关闭该护栏。
func _init(gpInNodeIds: Array[String], gpInShapeIdxs: Array[int], gpInEdgeIds: Array[String] = [],
		gpInLookup: Callable = Callable()) -> void:
	_gpNodes = GPDeleteNodesCommand.new(gpInNodeIds, gpInLookup)
	_gpShapes = GPDeleteShapesCommand.new(gpInShapeIdxs)
	# Only build the edge half when there is something to delete, so an edge-less selection stays
	# a pure node/shape composite (no empty no-op half).
	# 仅在确有边要删时才构建边部分，使不含边的选择仍是纯节点 / 图形复合体（不引入空的无效半步）。
	if gpInEdgeIds.size() > 0:
		_gpEdges = GPDeleteEdgesCommand.new(gpInEdgeIds)
	# Keep the node ids so gpExecute() can look up each symbol's restore records by id.
	# 保留节点 id，使 gpExecute() 能按 id 查到每个图元的恢复记录。
	_gpNodeIds = gpInNodeIds.duplicate()
	gpLabel = "删除"


# Run all halves. Returns true when any of them actually removed something.
# 执行所有部分。任一部分确实删掉了东西即返回 true。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null:
		return false
	var gpA: bool = _gpNodes.gpExecute(gpCtx)
	var gpB: bool = _gpShapes.gpExecute(gpCtx)
	var gpC: bool = (_gpEdges != null) and _gpEdges.gpExecute(gpCtx)
	# 4th half: original-line restore for symbols dropped/moved onto a line. The node half has
	# already cascade-deleted the two child edges of a split, so recreating the original edge here
	# is safe. For a reroute the original edge still exists (its ends are unchanged), so only its
	# intermediate waypoints are restored.
	# 第 4 部分：曾压到连线上的图元 -> 还原原始连线。节点部分已级联删除「拆分」产生的两条子边，
	# 故此处重建原边是安全的；「绕行」的原边仍在（两端不变），仅需还原其中间折点。
	_gpRestore = null
	if gpCtx.gpGraph != null:
		var gpRestoreBySym: Dictionary = {}
		for gpNid in _gpNodeIds:
			var gpRecs: Array = gpCtx.gpGraph.gpDropRecords(gpNid)
			if not gpRecs.is_empty():
				gpRestoreBySym[gpNid] = gpRecs
		if not gpRestoreBySym.is_empty():
			_gpRestore = GPRestoreDroppedEdgesCommand.new(gpRestoreBySym)
			_gpRestore.gpExecute(gpCtx)
	return gpA or gpB or gpC or (_gpRestore != null)


# Restore all halves. Shapes first, then edges (both endpoints still exist), then the drop-restore
# (removes any recreated edge / re-applies the post-drop routing), then nodes — this keeps the
# annotation layer valid and every edge re-inserted before its endpoints could be touched.
# 恢复所有部分。先图形、再边（两端仍存在）、再落点还原、后节点 —— 既保持注释层有效，
# 又让每条边在端点被触及前已插回。
func gpUndo(gpCtx: GPCommandContext) -> void:
	_gpShapes.gpUndo(gpCtx)
	if _gpEdges != null:
		_gpEdges.gpUndo(gpCtx)
	if _gpRestore != null:
		_gpRestore.gpUndo(gpCtx)
	_gpNodes.gpUndo(gpCtx)


# Re-apply all halves. Nodes first (which removes edges attached to them), then the standalone edges,
# then shapes, then the drop-restore (recreates the original edge / restores its routing).
# 重新应用所有部分。先节点（会移除依附其上的边），再独立边，后图形，最后落点还原（重建原边 / 还原走线）。
func gpRedo(gpCtx: GPCommandContext) -> void:
	_gpNodes.gpRedo(gpCtx)
	if _gpEdges != null:
		_gpEdges.gpRedo(gpCtx)
	_gpShapes.gpRedo(gpCtx)
	if _gpRestore != null:
		_gpRestore.gpRedo(gpCtx)
