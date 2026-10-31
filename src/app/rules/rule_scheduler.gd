class_name GPRuleScheduler
extends Node
# Copyright © 2026 Jonson Wang
#
# Live DRC scheduler (ADR-39 D5 / E02): a graph change marks the active sheet dirty; after a
# short debounce the engine runs ONCE and publishes findings. It is deliberately a debounce, not
# a per-frame scan: a drag emits dozens of changes and each full DRC run is not free.
# 实时 DRC 调度（ADR-39 D5 / E02）：图变化把活动图纸标脏；短去抖后只跑**一次**引擎并发布发现。
# 刻意用去抖而非每帧扫描：一次拖拽会发几十次变更，每次全量 DRC 并不便宜。
#
# What it does NOT do yet / 尚未做：
# - no per-node dirty set (whole-sheet runs);
# - no WorkerThreadPool split for heavy rules;
# - no HUD badges (the panel is refreshed instead).
# - 尚未做逐节点脏集合（整页重跑）、重规则线程拆分、HUD 角标（改为刷新面板）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

signal gpFindingsReady(gpFindings: Array[GPFinding], gpCanvas: GPCanvas2D)

# Debounce window in seconds. Long enough to coalesce a drag, short enough to feel live.
# 去抖窗口（秒）。长到能合并一次拖拽，短到仍有实时感。
const GP_DEBOUNCE: float = 0.25

var gpCanvas: GPCanvas2D = null
var gpDefs: Array[GPSymbolDef] = []
var gpLastFindings: Array[GPFinding] = []
var gpEnabled: bool = true

# Last run cost and the 3 ms target from ADR-39. A metric, not (yet) a slicing mechanism.
# 上次运行耗时与 ADR-39 的 3ms 目标。目前只是指标，尚未做时间切片。
const GP_BUDGET_USEC: int = 3000
var gpLastRunUsec: int = 0
var gpOverBudget: bool = false

var _gpDirty: bool = false
var _gpElapsed: float = 0.0
var _gpRunning: bool = false
var _gpSlice: int = 0
var _gpAccum: Array[GPFinding] = []
const GP_SLICES: Array[String] = ["", "layout", "topo", "symbol", "tag", "doc", "sem"]


func _ready() -> void:
	set_process(false)


# Point the scheduler at the active canvas (null unbinds).
# 指向活动画布（null 解绑）。
func gpBind(gpCanvasIn: GPCanvas2D, gpDefsIn: Array[GPSymbolDef] = []) -> void:
	gpCanvas = gpCanvasIn
	gpDefs = gpDefsIn
	_gpDirty = gpCanvas != null
	_gpElapsed = 0.0
	_gpRunning = false
	_gpSlice = 0
	_gpAccum.clear()
	set_process(gpEnabled and gpCanvas != null)


# A graph change arrived. The argument is accepted so this can be connected straight to the bus.
# 图变化到达。参数用于直接连总线。
func gpMarkDirty(_gpGraph: GPPIDGraph = null) -> void:
	_gpDirty = true
	_gpElapsed = 0.0
	set_process(gpEnabled and gpCanvas != null)


func gpSetEnabled(gpOn: bool) -> void:
	gpEnabled = gpOn
	set_process(gpOn and gpCanvas != null and _gpDirty)


func _process(gpDelta: float) -> void:
	if gpCanvas == null or gpCanvas.gpGraph == null:
		set_process(false)
		return
	if _gpRunning:
		_gpRunSlice()
		return
	if not _gpDirty:
		set_process(false)
		return
	_gpElapsed += gpDelta
	if _gpElapsed < GP_DEBOUNCE:
		return
	_gpElapsed = 0.0
	_gpDirty = false
	_gpRunning = true
	_gpSlice = 0
	_gpAccum.clear()
	_gpRunSlice()


# Run ONE slice (legacy first, then one family per frame) and merge when all slices are done.
# 跑**一片**（先 legacy，再每帧一个族），全部完成后合并。
func _gpRunSlice() -> void:
	if gpCanvas == null or gpCanvas.gpGraph == null:
		_gpRunning = false
		set_process(false)
		return
	var gpFamily: String = GP_SLICES[_gpSlice] if _gpSlice < GP_SLICES.size() else ""
	var gpOptions: Dictionary = {
		"families": [] if gpFamily == "" else [gpFamily],
		"skip_legacy": _gpSlice > 0,
	}
	var gpT0: int = Time.get_ticks_usec()
	var gpFound: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpCanvas.gpGraph, gpCanvas.gpSheet,
		gpDefs, gpCanvas.gpGraph.gpStandard, gpOptions)
	gpLastRunUsec = Time.get_ticks_usec() - gpT0
	gpOverBudget = gpLastRunUsec > GP_BUDGET_USEC
	_gpAccum.append_array(gpFound)
	_gpSlice += 1
	if _gpSlice < GP_SLICES.size():
		return
	_gpRunning = false
	set_process(false)
	gpLastFindings = GPDrcEngine.gpFinalize(_gpAccum, gpCanvas.gpGraph.gpStandard)
	gpFindingsReady.emit(gpLastFindings, gpCanvas)
	# If the graph changed while slices were running, start a fresh pass after the debounce.
	if _gpDirty:
		_gpRunning = false
		_gpSlice = 0
		_gpAccum.clear()
		_gpElapsed = 0.0
		set_process(gpEnabled and gpCanvas != null)


# Run the current sheet once and publish. Public so tests / a menu can force it.
# 立即跑一次当前图纸并发布。公开以便测试 / 菜单强制触发。
func gpRunNow() -> void:
	if gpCanvas == null or gpCanvas.gpGraph == null:
		return
	_gpRunning = false
	_gpSlice = 0
	_gpAccum.clear()
	var gpT0: int = Time.get_ticks_usec()
	gpLastFindings = GPDrcEngine.gpRunSheet(gpCanvas.gpGraph, gpCanvas.gpSheet, gpDefs,
		gpCanvas.gpGraph.gpStandard)
	gpLastRunUsec = Time.get_ticks_usec() - gpT0
	gpOverBudget = gpLastRunUsec > GP_BUDGET_USEC
	gpFindingsReady.emit(gpLastFindings, gpCanvas)
