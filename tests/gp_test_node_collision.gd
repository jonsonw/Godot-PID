extends "res://tests/gp_test.gd"
# Headless regression tests for GPNodeCollision (collision-avoidance push) and the
# GPSetNodePositionsCommand that commits its result. Builds tiny in-memory graphs; no canvas.
# GPNodeCollision（碰撞避让推送）与其提交命令 GPSetNodePositionsCommand 的 headless 回归测试。
# 仅建内存小图，不依赖画布。

# Build a graph with three overlapping 64x48 symbols clustered near the origin.
# 建一个三节点重叠的图，包络 64x48，聚在原点附近。
func _gpGraph() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("a", "pump", "P-1", Vector2(0, 0)))
	gpG.gpAddNode(gpG.gpNewNode("b", "tank", "V-1", Vector2(10, 0)))
	gpG.gpAddNode(gpG.gpNewNode("c", "valve", "X-1", Vector2(0, 10)))
	return gpG

# Def lookup returning a uniform 64x48 envelope for any symbol id.
# 任意图元 id 都返回统一的 64x48 包络。
func _gpDefs(gpSymbolId: String) -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpDefaultSize = Vector2(64.0, 48.0)
	return gpD

# True when any two envelopes (inflated by half the padding) still intersect.
# 任意两个包络（外扩半间距）仍相交则返回真。
func _gpAnyOverlap(gpG: GPPIDGraph, gpPad: float) -> bool:
	var gpHalf: float = gpPad * 0.5
	var gpRects: Dictionary = {}
	for gpN in gpG.gpNodes:
		gpRects[gpN.gpInstanceId] = Rect2(gpN.gpPosition - Vector2(32.0, 24.0), Vector2(64.0, 48.0)).grow(gpHalf)
	for gpI in gpG.gpNodes:
		for gpJ in gpG.gpNodes:
			if gpI.gpInstanceId == gpJ.gpInstanceId:
				continue
			if (gpRects[gpI.gpInstanceId] as Rect2).intersects(gpRects[gpJ.gpInstanceId] as Rect2):
				return true
	return false


# With one node fixed, the overlapping neighbours must be pushed aside and end up non-overlapping
# (with the padding gap). / 固定一个节点后，重叠邻件必须被推开，最终互不重叠（含间距）。
func gpTestFixedPushesOverlapping() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpRes: Dictionary = GPNodeCollision.gpResolve(gpG, _gpDefs, ["a"],
			GPNodeCollision.GP_DEFAULT_PADDING, 64)
	gpCheck(gpRes.has("b"), "b should be displaced")
	gpCheck(gpRes.has("c"), "c should be displaced")
	# Apply the resolved positions, then verify no pair still overlaps (with the padding gap).
	# 应用解析后的位置，再验证没有任何一对仍重叠（含 padding 间隙）。
	for gpId in gpRes.keys():
		gpG.gpGetNode(gpId).gpPosition = (gpRes[gpId] as Vector2)
	gpCheck(not _gpAnyOverlap(gpG, GPNodeCollision.GP_DEFAULT_PADDING),
			"no two envelopes should overlap after avoidance")


# Nodes placed far apart need no push, so the resolver returns an empty map.
# 彼此远离的节点无需推送，解析器应返回空字典。
func gpTestNoOverlapReturnsEmpty() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("a", "pump", "P-1", Vector2(0, 0)))
	gpG.gpAddNode(gpG.gpNewNode("b", "tank", "V-1", Vector2(500, 500)))
	var gpRes: Dictionary = GPNodeCollision.gpResolve(gpG, _gpDefs, ["a"])
	gpCheck(gpRes.is_empty(), "far-apart nodes need no push")


# GPSetNodePositionsCommand must apply absolute targets and undo/redo them cleanly.
# GPSetNodePositionsCommand 必须应用绝对目标，并能干净地撤销/重做。
func gpTestCommandSetPositionsApplyUndo() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("a", "pump", "P-1", Vector2(0, 0)))
	gpG.gpAddNode(gpG.gpNewNode("b", "tank", "V-1", Vector2(100, 0)))
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG)
	var gpTargets: Dictionary = {"a": Vector2(10, 20), "b": Vector2(110, 20)}
	var gpCmd: GPSetNodePositionsCommand = GPSetNodePositionsCommand.new(gpTargets)
	gpCheck(gpCmd.gpExecute(gpCtx), "execute succeeds")
	gpCheck(gpG.gpGetNode("a").gpPosition == Vector2(10, 20), "a moved to target")
	gpCheck(gpG.gpGetNode("b").gpPosition == Vector2(110, 20), "b moved to target")
	gpCmd.gpUndo(gpCtx)
	gpCheck(gpG.gpGetNode("a").gpPosition == Vector2(0, 0), "a restored on undo")
	gpCheck(gpG.gpGetNode("b").gpPosition == Vector2(100, 0), "b restored on undo")
	gpCmd.gpRedo(gpCtx)
	gpCheck(gpG.gpGetNode("a").gpPosition == Vector2(10, 20), "a redone")
