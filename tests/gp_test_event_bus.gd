extends "res://tests/gp_test.gd"
# M2 event-bus tests: the app-layer channel that replaces the two half-dead channels.
# M2 事件总线测试：取代原先两条半失效通道的应用层通道。
#
# Runs under `--script` (no autoloads, no scene tree): the bus is a plain RefCounted that
# depends on core types only. That is precisely the "可测试" goal — an event channel you
# can exercise without booting Godot's UI.
# 在 `--script` 下运行（无 autoload、无场景树）：总线是仅依赖 core 类型的纯 RefCounted。
# 这正是「可测试」目标——不启动 Godot 界面即可检验事件通道。

# Counters / last payloads captured by the test callbacks.
# 测试回调记录的计数与最近载荷。
var _gpHits: int = 0
var _gpLastGraph: GPPIDGraph = null
var _gpLastIds: Array[String] = []
var _gpLastInfo: Dictionary = {}
var _gpLastMode: int = -1
var _gpCoreHits: int = 0
var _gpSecondHits: int = 0


# --- callbacks 回调 ---
func _gpOnGraph(gpGraph: GPPIDGraph) -> void:
	_gpHits += 1
	_gpLastGraph = gpGraph


func _gpOnSecondGraph(_gpGraph: GPPIDGraph) -> void:
	_gpSecondHits += 1


func _gpOnSelection(gpIds: Array[String]) -> void:
	_gpHits += 1
	_gpLastIds = gpIds


func _gpOnStatus(gpInfo: Dictionary) -> void:
	_gpHits += 1
	_gpLastInfo = gpInfo


func _gpOnMode(gpNewMode: int) -> void:
	_gpHits += 1
	_gpLastMode = gpNewMode


# Zero-arg callback for the core graph signal (it carries no payload).
# core 图信号的无参回调（该信号不携带载荷）。
func _gpOnCoreGraphChanged() -> void:
	_gpCoreHits += 1


func _gpReset() -> void:
	_gpHits = 0
	_gpSecondHits = 0
	_gpCoreHits = 0
	_gpLastGraph = null
	_gpLastIds = []
	_gpLastInfo = {}
	_gpLastMode = -1


# A new bus starts with no subscribers on any channel.
# 新建总线的各通道均无订阅者。
func gpTestBusStartsEmpty() -> void:
	_gpReset()
	var gpBus: GPEventBus = GPEventBus.new()
	gpEq(gpBus.gpConnectionCount("gpGraphChanged"), 0, "graph channel empty")
	gpEq(gpBus.gpConnectionCount("gpSelectionChanged"), 0, "selection channel empty")
	gpEq(gpBus.gpConnectionCount("gpStatusUpdated"), 0, "status channel empty")
	gpEq(gpBus.gpConnectionCount("gpModeChanged"), 0, "mode channel empty")
	gpEq(gpBus.gpConnectionCount("gpNoSuchSignal"), -1, "unknown signal reports -1")


# Graph-changed delivery, payload, and clean detachment (no leaked connection).
# 图变化投递、载荷，以及干净解绑（无连接泄漏）。
func gpTestGraphChangedDelivery() -> void:
	_gpReset()
	var gpBus: GPEventBus = GPEventBus.new()
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	gpBus.gpGraphChanged.connect(_gpOnGraph)
	gpEq(gpBus.gpConnectionCount("gpGraphChanged"), 1, "one subscriber registered")
	gpBus.gpGraphChanged.emit(gpGraph)
	gpEq(_gpHits, 1, "graph change delivered once")
	gpCheck(_gpLastGraph == gpGraph, "payload carries the emitting graph")
	gpBus.gpGraphChanged.emit(gpGraph)
	gpEq(_gpHits, 2, "second change delivered too")
	gpBus.gpGraphChanged.disconnect(_gpOnGraph)
	gpBus.gpGraphChanged.emit(gpGraph)
	gpEq(_gpHits, 2, "no delivery after disconnect")
	gpEq(gpBus.gpConnectionCount("gpGraphChanged"), 0, "connection fully released")


# Fan-out to several independent subscribers (the point of a bus vs. one signal slot).
# 向多个独立订阅者扇出（总线相对于单信号槽的意义所在）。
func gpTestGraphChangedFanOut() -> void:
	_gpReset()
	var gpBus: GPEventBus = GPEventBus.new()
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	gpBus.gpGraphChanged.connect(_gpOnGraph)
	gpBus.gpGraphChanged.connect(_gpOnSecondGraph)
	gpEq(gpBus.gpConnectionCount("gpGraphChanged"), 2, "two subscribers registered")
	gpBus.gpGraphChanged.emit(gpGraph)
	gpEq(_gpHits, 1, "first subscriber notified")
	gpEq(_gpSecondHits, 1, "second subscriber notified")
	gpBus.gpGraphChanged.disconnect(_gpOnGraph)
	gpBus.gpGraphChanged.disconnect(_gpOnSecondGraph)


# Selection / status / mode channels carry their payloads unchanged.
# 选中 / 状态 / 模式通道原样携带载荷。
func gpTestSelectionStatusModePayloads() -> void:
	_gpReset()
	var gpBus: GPEventBus = GPEventBus.new()
	gpBus.gpSelectionChanged.connect(_gpOnSelection)
	gpBus.gpStatusUpdated.connect(_gpOnStatus)
	gpBus.gpModeChanged.connect(_gpOnMode)

	var gpIds: Array[String] = ["n1", "n2"]
	gpBus.gpSelectionChanged.emit(gpIds)
	gpEq(_gpHits, 1, "selection delivered")
	gpEq(_gpLastIds, gpIds, "selection carries the full id list")

	# NOTE (Godot constraint): emitting an untyped `[]` literal into a signal whose parameter
	# is typed `Array[String]` fails at runtime ("Cannot convert argument 1 from Array to
	# Array"). Production code is safe because it forwards an already-typed `gpSelection`,
	# but a test must build a typed empty array explicitly.
	# 注意（Godot 约束）：向参数类型为 `Array[String]` 的信号发射无类型 `[]` 字面量会在运行时
	# 失败（"Cannot convert argument 1 from Array to Array"）。生产代码转发的是已类型化的
	# `gpSelection`，故安全；但测试必须显式构造带类型的空数组。
	var gpEmpty: Array[String] = []
	gpBus.gpSelectionChanged.emit(gpEmpty)
	gpEq(_gpLastIds, [], "clearing selection delivers an empty list")

	var gpInfo: Dictionary = {"selection": "n1", "count": 1, "zoom": 2.0, "world": Vector2(3, 4)}
	gpBus.gpStatusUpdated.emit(gpInfo)
	gpEq(_gpLastInfo, gpInfo, "status snapshot delivered unchanged")

	gpBus.gpModeChanged.emit(4)
	gpEq(_gpLastMode, 4, "mode change delivered")
	# Two selection changes + one status + one mode = four deliveries in total.
	# 两次选中变化 + 一次状态 + 一次模式 = 共四次投递。
	gpEq(_gpHits, 4, "four events in total across the three channels")

	gpBus.gpSelectionChanged.disconnect(_gpOnSelection)
	gpBus.gpStatusUpdated.disconnect(_gpOnStatus)
	gpBus.gpModeChanged.disconnect(_gpOnMode)


# The core graph channel is genuinely live: before M2 it was emitted 7x with ZERO
# subscribers, so programmatic mutations never reached the UI. M2 binds it in the canvas.
# core 图通道确实可用：M2 之前它发射 7 处却零订阅者，程序化改动传不到 UI。M2 在画布中绑定它。
func gpTestCoreGraphChannelIsLive() -> void:
	_gpReset()
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	gpGraph.gpGraphChanged.connect(_gpOnCoreGraphChanged)
	gpEq(_gpCoreHits, 0, "no change before mutation")
	gpGraph.gpAddNode(gpGraph.gpNewNode("n1", "pump", "P-01"))
	gpEq(_gpCoreHits, 1, "adding a node notifies the graph channel")
	var gpN2: GPPIDNode = gpGraph.gpNewNode("n2", "tank", "T-201")
	gpGraph.gpAddNode(gpN2)
	gpGraph.gpAddEdge(gpGraph.gpNewEdge("e1", "n1", "n2"))
	gpEq(_gpCoreHits, 3, "every mutation notifies exactly once")
	gpGraph.gpRemoveNodeWithEdges("n1")
	gpCheck(_gpCoreHits > 3, "removal notifies as well")
	gpGraph.gpGraphChanged.disconnect(_gpOnCoreGraphChanged)
	gpEq(gpGraph.gpGraphChanged.get_connections().size(), 0, "graph connection released")


# A bus is per-sheet: two buses do not cross-talk (guards the multi-sheet design decision).
# 总线按图纸隔离：两条总线互不串扰（守护多图纸设计决策）。
func gpTestBusesAreIndependent() -> void:
	_gpReset()
	var gpBusA: GPEventBus = GPEventBus.new()
	var gpBusB: GPEventBus = GPEventBus.new()
	gpBusA.gpGraphChanged.connect(_gpOnGraph)
	gpBusB.gpGraphChanged.emit(GPPIDGraph.new())
	gpEq(_gpHits, 0, "sheet B change does not reach sheet A subscriber")
	gpBusA.gpGraphChanged.emit(GPPIDGraph.new())
	gpEq(_gpHits, 1, "sheet A change reaches its own subscriber")
	gpBusA.gpGraphChanged.disconnect(_gpOnGraph)
