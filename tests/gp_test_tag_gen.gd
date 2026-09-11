extends "res://tests/gp_test.gd"
# Headless tests for GPTagGen (P1 of the connection feature).
# 连线功能 P1 —— GPTagGen 的 headless 测试。
#
# The rule under test: a pipe number is issued once and NEVER recycled. Two pipes in the same
# project must never carry the same number, because in a P&ID a line number is a reference
# used in the line list, the isometrics and the HAZOP sheet — reusing one after a delete
# mislabels physical plant.
# 被测规则：管道号一次发放、绝不回收。同一工程里两条管道绝不能同号，因为在 P&ID 中管线号是
# 被管线表、轴测图与 HAZOP 工作表引用的标识 —— 删除后重用等于给实体装置贴错标签。


func _gpGraph() -> GPPIDGraph:
	return GPPIDGraph.new()


func gpTestFirstTagIsOneThousandAndOne() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpEq(GPTagGen.gpNextTag(gpG), "PL-1001", "first pipe number is PL-1001")
	gpEq(GPTagGen.gpNextTag(gpG), "PL-1002", "second pipe number is PL-1002")


func gpTestPrefixIsConfigurable() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpEq(GPTagGen.gpNextTag(gpG, "UW"), "UW-1001", "utility water lines use their own prefix")
	gpEq(GPTagGen.gpNextTag(gpG, "PL"), "PL-1001", "prefixes have independent sequences")


# Deleting a pipe does NOT hand its number to the next one.
# 删除一条管道不会把它的号让给下一条。
func gpTestDeletedNumbersAreNotRecycled() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpT1: String = GPTagGen.gpNextTag(gpG)
	var gpT2: String = GPTagGen.gpNextTag(gpG)
	gpG.gpAddEdge(gpG.gpNewEdge("e1", "n1", "n2"))
	gpG.gpEdges[0].gpTag = gpT1
	gpG.gpRemoveEdge("e1")
	# gpT2 is still in use, so the next free number is 1003 — never 1001 again.
	# gpT2 仍在使用，故下一个可用号是 1003 —— 绝不再回到 1001。
	gpG.gpAddEdge(gpG.gpNewEdge("e2", "n1", "n2"))
	gpG.gpEdges[0].gpTag = gpT2
	gpEq(GPTagGen.gpNextTag(gpG), "PL-1003", "a deleted number is never reissued")


# The user may have typed a number ahead of the counter; allocation must skip it.
# 用户可能提前手打了某个号；分配必须跳过它。
func gpTestSkipsManuallyTakenNumbers() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddEdge(gpG.gpNewEdge("e1", "n1", "n2"))
	gpG.gpEdges[0].gpTag = "PL-1001"
	gpEq(GPTagGen.gpNextTag(gpG), "PL-1002", "an occupied number is skipped")


# The high-water mark lives in gpMeta, which gpToDict/gpFromDict already carry wholesale.
# 水位线落在 gpMeta，而 gpToDict/gpFromDict 已整体往返它。
func gpTestHighWaterMarkSurvivesSaveLoad() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	GPTagGen.gpNextTag(gpG)
	GPTagGen.gpNextTag(gpG)
	var gpG2: GPPIDGraph = GPPIDGraph.gpFromDict(gpG.gpToDict())
	gpEq(GPTagGen.gpPeek(gpG2), 1002, "the high-water mark survives a save/load round-trip")
	gpEq(GPTagGen.gpNextTag(gpG2), "PL-1003", "numbering continues after re-opening the file")


func gpTestPeekStartsAtBase() -> void:
	gpEq(GPTagGen.gpPeek(_gpGraph()), GPTagGen.GP_BASE, "a fresh graph starts at the base")
	gpEq(GPTagGen.gpPeek(null), GPTagGen.GP_BASE, "a null graph is tolerated")


func gpTestNullGraphIsSafe() -> void:
	gpEq(GPTagGen.gpNextTag(null), "", "a null graph yields an empty tag rather than crashing")


# Duplicate numbers are legal for branch lines, so the allocator must not refuse them —
# gpIsTaken exists so the caller can WARN, never to block.
# 支管同号是合法的，故分配器不得拒绝 —— gpIsTaken 供调用方「警告」而非「阻止」。
func gpTestIsTakenIgnoresTheEditedEdge() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddEdge(gpG.gpNewEdge("e1", "n1", "n2"))
	gpG.gpEdges[0].gpTag = "PL-1001"
	gpCheck(GPTagGen.gpIsTaken(gpG, "PL-1001"), "an existing number is reported as taken")
	gpCheck(not GPTagGen.gpIsTaken(gpG, "PL-1001", "e1"), "the edited edge excludes itself")
	gpCheck(not GPTagGen.gpIsTaken(gpG, ""), "an empty tag is never taken")
