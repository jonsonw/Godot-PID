extends "res://tests/gp_test.gd"
# Headless tests for the M4 command layer: context, stack, and the three concrete
# commands (add / delete / move).
# M4 命令层的 headless 测试：上下文、命令栈，以及三个具体命令（添加 / 删除 / 移动）。
#
# These run without a scene tree, which is the whole point of M4: the commands touch
# only GPPIDGraph + GPIdGen, so an edit is verifiable as pure model arithmetic.
# 这些测试不启动场景树，这正是 M4 的意义：命令只接触 GPPIDGraph + GPIdGen，
# 因此一次编辑可作为纯粹的模型运算被验证。

# Signal hit counter for the "mutate the model, the view follows" contract.
# 「改模型、视图自随之」契约用的信号命中计数器。
var _gpSignalHits: int = 0


func _gpOnGraphChanged() -> void:
	_gpSignalHits += 1


# Fixture: N1 -(E1)- N2, plus a fresh id generator, context and stack.
# 夹具：N1 -(E1)- N2，外加全新的 id 生成器、上下文与命令栈。
func _mkFixture() -> Array:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-101", Vector2(10, 10)))
	g.gpAddNode(g.gpNewNode("N2", "valve", "V-201", Vector2(100, 10)))
	g.gpAddEdge(g.gpNewEdge("E1", "N1", "N2"))
	var ctx: GPCommandContext = GPCommandContext.new(g, GPIdGen.new())
	var st: GPCommandStack = GPCommandStack.new()
	var gpOut: Array = [g, ctx, st]
	return gpOut


# ---------------------------------------------------------------- context / 上下文

func gpTestContextReadiness() -> void:
	# A context without both collaborators must refuse work rather than crash later.
	# 缺少任一协作者的上下文必须拒绝工作，而非稍后崩溃。
	var g: GPPIDGraph = GPPIDGraph.new()
	gpEq(GPCommandContext.new().gpIsReady(), false, "empty context is not ready")
	gpEq(GPCommandContext.new(g, null).gpIsReady(), false, "graph without ids is not ready")
	gpEq(GPCommandContext.new(g, GPIdGen.new()).gpIsReady(), true, "graph + ids is ready")


# ---------------------------------------------------------------- stack / 命令栈

func gpTestStackNewEditClearsRedo() -> void:
	# The classic editor rule: after undoing, a fresh edit discards the redo branch.
	# 经典编辑器规则：撤销后再做新编辑，重做分支即作废。
	var f: Array = _mkFixture()
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	var gpIds: Array[String] = ["N1"]
	gpCheck(st.gpDo(GPMoveNodesCommand.new(gpIds, Vector2(5, 5)), ctx), "first move recorded")
	gpCheck(st.gpUndo(ctx), "undo available")
	gpEq(st.gpCanRedo(), true, "redo branch exists after undo")
	gpCheck(st.gpDo(GPMoveNodesCommand.new(gpIds, Vector2(1, 1)), ctx), "second move recorded")
	gpEq(st.gpCanRedo(), false, "new edit wipes the redo branch")


func gpTestStackDepthLimit() -> void:
	# The oldest step is dropped first, so a long session cannot grow without bound.
	# 最旧的步最先被丢弃，因此长时间会话不会无界增长。
	var f: Array = _mkFixture()
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	st.gpLimit = 3
	var gpIds: Array[String] = ["N1"]
	for gpI in range(5):
		st.gpDo(GPMoveNodesCommand.new(gpIds, Vector2(1, 0)), ctx)
	gpEq(st.gpUndoDepth(), 3, "history capped at the configured limit")
	gpEq(st.gpRedoDepth(), 0, "redo stays empty while only doing")


func gpTestStackNoopCommandNotRecorded() -> void:
	# A command that did nothing must not become a phantom undo step the user has to
	# press Undo on to get anywhere.
	# 什么都没做的命令不得变成幽灵撤销步，逼用户空按一次撤销。
	var f: Array = _mkFixture()
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	var gpStale: Array[String] = ["DOES_NOT_EXIST"]
	gpCheck(not st.gpDo(GPDeleteNodesCommand.new(gpStale), ctx), "stale delete is refused")
	gpEq(st.gpUndoDepth(), 0, "nothing recorded for a no-op")


func gpTestStackLabelsTrackTop() -> void:
	var f: Array = _mkFixture()
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	gpEq(st.gpUndoLabel(), "", "no undo label on an empty stack")
	st.gpDo(GPAddNodeCommand.new("tank", Vector2(0, 0), "T-1"), ctx)
	gpEq(st.gpUndoLabel(), "添加节点", "undo label shows the pending command")
	st.gpUndo(ctx)
	gpEq(st.gpRedoLabel(), "添加节点", "redo label shows the undone command")


func gpTestStackClear() -> void:
	var f: Array = _mkFixture()
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	var gpIds: Array[String] = ["N1"]
	st.gpDo(GPMoveNodesCommand.new(gpIds, Vector2(3, 3)), ctx)
	st.gpClear()
	gpEq(st.gpCanUndo(), false, "clear drops undo history")
	gpEq(st.gpCanRedo(), false, "clear drops redo history")


# ---------------------------------------------------------------- add / 添加

func gpTestAddNodeUndoRedoKeepsId() -> void:
	# Redo must reuse the SAME id: a fresh id would silently orphan every reference
	# (edges, external exports) that pointed at the node.
	# 重做必须复用同一 id：新 id 会静默孤立所有指向该节点的引用（边、外部导出）。
	var f: Array = _mkFixture()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	gpCheck(st.gpDo(GPAddNodeCommand.new("tank", Vector2(5, 5), "T-301"), ctx), "add recorded")
	gpEq(g.gpNodes.size(), 3, "node added")
	var gpNewId: String = g.gpNodes[2].gpInstanceId
	gpCheck(st.gpUndo(ctx), "undo after add")
	gpEq(g.gpNodes.size(), 2, "node removed by undo")
	gpCheck(st.gpRedo(ctx), "redo after undo")
	gpEq(g.gpNodes.size(), 3, "node restored by redo")
	gpEq(g.gpGetNode(gpNewId) != null, true, "redo reuses the original id")
	gpEq(g.gpGetNode(gpNewId).gpTag, "T-301", "restored node keeps its tag")


# ---------------------------------------------------------------- delete / 删除

func gpTestDeleteNodeRestoresNodeAndEdges() -> void:
	# Cascade delete must be fully invertible, edges included — otherwise undo leaves a
	# half-connected graph behind.
	# 级联删除必须完全可逆（含边），否则撤销后会留下半连通的图。
	var f: Array = _mkFixture()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	var gpIds: Array[String] = ["N1"]
	gpCheck(st.gpDo(GPDeleteNodesCommand.new(gpIds), ctx), "delete recorded")
	gpEq(g.gpNodes.size(), 1, "node removed")
	gpEq(g.gpEdges.size(), 0, "touching edge removed with it")
	gpCheck(st.gpUndo(ctx), "undo after delete")
	gpEq(g.gpNodes.size(), 2, "node restored")
	gpEq(g.gpEdges.size(), 1, "edge restored with it")
	gpEq(g.gpGetEdge("E1") != null, true, "restored edge keeps its id")


func gpTestDeleteRedoRemovesAgain() -> void:
	var f: Array = _mkFixture()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	var gpIds: Array[String] = ["N1"]
	st.gpDo(GPDeleteNodesCommand.new(gpIds), ctx)
	st.gpUndo(ctx)
	gpCheck(st.gpRedo(ctx), "redo after undoing a delete")
	gpEq(g.gpNodes.size(), 1, "delete re-applied")
	gpEq(g.gpEdges.size(), 0, "edge stays removed on redo")


# ---------------------------------------------------------------- move / 移动

func gpTestMoveUndoRestoresPosition() -> void:
	var f: Array = _mkFixture()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	var gpIds: Array[String] = ["N1"]
	st.gpDo(GPMoveNodesCommand.new(gpIds, Vector2(50, 20)), ctx)
	gpEq(g.gpGetNode("N1").gpPosition, Vector2(60, 30), "node translated")
	st.gpUndo(ctx)
	gpEq(g.gpGetNode("N1").gpPosition, Vector2(10, 10), "undo returns it exactly")
	st.gpRedo(ctx)
	gpEq(g.gpGetNode("N1").gpPosition, Vector2(60, 30), "redo re-applies the delta")


func gpTestMoveGroupIsRigid() -> void:
	# Every node shifts by the same delta, so a group keeps its relative layout.
	# 每个节点位移相同，因此整组保持相对布局。
	var f: Array = _mkFixture()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	var gpBoth: Array[String] = ["N1", "N2"]
	st.gpDo(GPMoveNodesCommand.new(gpBoth, Vector2(10, 10)), ctx)
	gpEq(g.gpGetNode("N1").gpPosition, Vector2(20, 20), "first node moved")
	gpEq(g.gpGetNode("N2").gpPosition, Vector2(110, 20), "second node moved by the same delta")
	st.gpUndo(ctx)
	gpEq(g.gpGetNode("N2").gpPosition, Vector2(100, 10), "second node back to origin")


# ------------------------------------------------- view-follows-model / 视图自随

func gpTestMoveNotifiesOncePerCommand() -> void:
	# gpPosition is a plain property, so the command must notify explicitly — exactly
	# once for the whole group, not once per node (that would redraw N times).
	# gpPosition 是普通属性，因此命令必须显式通知——整组一次，而非每节点一次
	# （后者会重复重绘 N 次）。
	var f: Array = _mkFixture()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	_gpSignalHits = 0
	g.gpGraphChanged.connect(Callable(self, "_gpOnGraphChanged"))
	var gpBoth: Array[String] = ["N1", "N2"]
	st.gpDo(GPMoveNodesCommand.new(gpBoth, Vector2(1, 1)), ctx)
	gpEq(_gpSignalHits, 1, "one graph-changed notification for a two-node move")
	st.gpUndo(ctx)
	gpEq(_gpSignalHits, 2, "undo notifies again so the view can refresh")
	g.gpGraphChanged.disconnect(Callable(self, "_gpOnGraphChanged"))
