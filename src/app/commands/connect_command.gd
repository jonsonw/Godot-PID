class_name GPConnectCommand
extends GPCommand
# Create one edge between two nodes (M4).
# 在两个节点之间创建一条连线（M4）。
#
# Kept deliberately narrow: it knows the two endpoint ids and nothing about ports. P&ID
# edges in this model store endpoint NODE ids only (never a port name) so that editing a
# symbol's ports never silently breaks an existing connection.
# 刻意做得窄：它只知道两个端点 id，不知道端口。本模型中的 P&ID 边只存端点节点 id
# （从不存端口名），因此编辑图元端口永远不会静默断掉已有连接。

# Source node id. / 起点节点 id。
var gpFromId: String = ""

# Target node id. / 终点节点 id。
var gpToId: String = ""


# The edge this command created, kept so redo re-adds the SAME object with the SAME id
# (see GPAddNodeCommand for why re-minting an id on redo is a silent corruption).
# 本命令创建的边。保留它使重做能用相同 id 重新加入同一对象
# （重做时重新生成 id 为何是静默损坏，参见 GPAddNodeCommand）。
var _gpEdge: GPPIDEdge = null


# Build the command from the two endpoint node ids.
# 由两个端点节点 id 构造命令。
func _init(gpInFromId: String, gpInToId: String) -> void:
	gpFromId = gpInFromId
	gpToId = gpInToId
	gpLabel = "连接节点"


# Create (first run) or re-add (redo) the edge. Self-connections are refused, matching the
# interactive path: an edge from a node to itself has no meaning in a P&ID.
# 首次运行时创建边，重做时重新加入。拒绝自连接，与交互路径一致：
# 节点到自身的连线在 P&ID 中没有意义。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or not gpCtx.gpIsReady():
		return false
	if gpFromId == "" or gpToId == "" or gpFromId == gpToId:
		return false
	if _gpEdge == null:
		var gpEid: String = gpCtx.gpIds.gpNext("e")
		_gpEdge = gpCtx.gpGraph.gpNewEdge(gpEid, gpFromId, gpToId, {})
	gpCtx.gpGraph.gpAddEdge(_gpEdge)
	return true


# Take the edge back out.
# 取回该边。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpEdge == null:
		return
	gpCtx.gpGraph.gpRemoveEdge(_gpEdge.gpInstanceId)


# Re-add the very same edge object, preserving its id.
# 重新加入同一个边对象，保持其 id 不变。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpEdge == null:
		return
	gpCtx.gpGraph.gpAddEdge(_gpEdge)
