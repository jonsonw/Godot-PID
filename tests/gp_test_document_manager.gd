extends "res://tests/gp_test.gd"
# Headless tests for M6 GPAppDocumentManager: bus ownership, active-graph tracking, and the
# dirty-flag lifecycle (rising-edge emit, idempotency, reset on set-graph, clear on save).
# M6 GPAppDocumentManager 的 headless 测试：总线归属、当前图跟踪、脏标记生命周期
# （上升沿发射、幂等、切换图重置、保存清除）。
#
# The manager is a pure RefCounted: no Node, no autoload, so this suite runs with no scene tree
# beyond the harness. The canvas-binding half of M6 is covered by the main-scene smoke test.
# 管理器是纯 RefCounted：无 Node、无自动加载，故本套件除运行器外无需场景树。
# M6 的画布绑定半部分由主场景冒烟测试覆盖。

# Signal hit counters.
# 信号命中计数。
var _gpDocHits: int = 0
var _gpDirtyHits: int = 0
var _gpLastGraph: GPPIDGraph = null
var _gpLastDirty: bool = false


func _gpOnDocChanged(g: GPPIDGraph) -> void:
	_gpDocHits += 1
	_gpLastGraph = g


func _gpOnDirtyChanged(d: bool) -> void:
	_gpDirtyHits += 1
	_gpLastDirty = d


# The runner reuses ONE instance across every gpTest* method, so these signal counters would
# otherwise accumulate. Reset them at the top of each method that reads them.
# 运行器在同一个实例上顺序调用每个 gpTest* 方法，故这些信号计数会跨方法累加；
# 在每个读取它们的方法开头清零。
func _gpResetSignalCounters() -> void:
	_gpDocHits = 0
	_gpDirtyHits = 0
	_gpLastGraph = null
	_gpLastDirty = false


# Fixture: a one-node graph.
# 夹具：单节点图。
func _mkGraph() -> GPPIDGraph:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-101", Vector2(10, 10)))
	return g


# ---------------------------------------------------------- bus ownership / 总线归属

func gpTestManagerOwnsBus() -> void:
	var m: GPAppDocumentManager = GPAppDocumentManager.new()
	gpCheck(m.gpBus != null, "manager constructs with a bus")
	gpEq(m.gpBus is GPEventBus, true, "the bus is a GPEventBus")


# ---------------------------------------------------------- active graph / 当前图

func gpTestTracksActiveGraph() -> void:
	var m: GPAppDocumentManager = GPAppDocumentManager.new()
	var g: GPPIDGraph = _mkGraph()
	m.gpSetGraph(g)
	gpEq(m.gpGraph == g, true, "active graph stored")
	gpEq(m.gpIsDirty(), false, "fresh document is not dirty")


func gpTestDocChangedEmittedOnSetGraph() -> void:
	_gpResetSignalCounters()
	var m: GPAppDocumentManager = GPAppDocumentManager.new()
	m.gpBus.gpDocChanged.connect(Callable(self, "_gpOnDocChanged"))
	var g: GPPIDGraph = _mkGraph()
	m.gpSetGraph(g)
	gpEq(_gpDocHits, 1, "gpDocChanged fired once on set-graph")
	gpEq(_gpLastGraph == g, true, "gpDocChanged carried the new graph")


# ---------------------------------------------------------- dirty lifecycle / 脏标记

func gpTestDirtyMarkedAndEmitted() -> void:
	_gpResetSignalCounters()
	var m: GPAppDocumentManager = GPAppDocumentManager.new()
	m.gpBus.gpDirtyChanged.connect(Callable(self, "_gpOnDirtyChanged"))
	m.gpMarkDirty()
	gpEq(m.gpIsDirty(), true, "document becomes dirty")
	gpEq(_gpDirtyHits, 1, "gpDirtyChanged fired on rising edge")
	gpEq(_gpLastDirty, true, "gpDirtyChanged carried true")


func gpTestDirtyIdempotent() -> void:
	_gpResetSignalCounters()
	var m: GPAppDocumentManager = GPAppDocumentManager.new()
	m.gpBus.gpDirtyChanged.connect(Callable(self, "_gpOnDirtyChanged"))
	m.gpMarkDirty()
	m.gpMarkDirty()
	m.gpMarkDirty()
	gpEq(_gpDirtyHits, 1, "repeated marks emit only once (rising edge)")


func gpTestClearDirtyEmitsFalse() -> void:
	_gpResetSignalCounters()
	var m: GPAppDocumentManager = GPAppDocumentManager.new()
	m.gpBus.gpDirtyChanged.connect(Callable(self, "_gpOnDirtyChanged"))
	m.gpMarkDirty()
	m.gpClearDirty()
	gpEq(m.gpIsDirty(), false, "document no longer dirty after clear")
	gpEq(_gpDirtyHits, 2, "clear emits the falling edge")
	gpEq(_gpLastDirty, false, "gpDirtyChanged carried false")
	# Clearing again is a no-op (already clean).
	# 再清一次是无操作（已干净）。
	m.gpClearDirty()
	gpEq(_gpDirtyHits, 2, "clearing an already-clean doc emits nothing")


func gpTestSetGraphResetsDirty() -> void:
	_gpResetSignalCounters()
	var m: GPAppDocumentManager = GPAppDocumentManager.new()
	m.gpBus.gpDocChanged.connect(Callable(self, "_gpOnDocChanged"))
	var g1: GPPIDGraph = _mkGraph()
	var g2: GPPIDGraph = _mkGraph()
	m.gpSetGraph(g1)
	m.gpMarkDirty()
	gpEq(m.gpIsDirty(), true, "dirty before re-set")
	m.gpSetGraph(g2)
	gpEq(m.gpIsDirty(), false, "switching document resets dirty")
	gpEq(_gpDocHits, 2, "gpDocChanged fired again for the new document")
	gpEq(m.gpGraph == g2, true, "active graph is now the new one")
