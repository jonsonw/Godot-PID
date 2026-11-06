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
# BOUND TO DATA, NOT TO THE CANVAS / 绑的是数据，不是画布：
# This scheduler lives in app. It used to hold `gpCanvas: GPCanvas2D` — a ui class — only to read
# three values off it (graph, sheet, standard) and to echo it back in the signal. That made app
# depend on ui for no reason (W12 review D02), and it is exactly the kind of arrow that made the
# "swap the renderer" claim untrue. It now takes the graph and the sheet directly, and echoes the
# GRAPH back so a subscriber can tell whether the findings are about what the user is looking at.
# 本调度器住在 app。它曾持有 `gpCanvas: GPCanvas2D`（ui 类），只为从上面读三个值（图、图纸、标准），
# 并在信号里回传它 —— 使 app 无故依赖 ui（W12 审查 D02），而正是这类箭头让「可换渲染器」的说法失真。
# 现在直接收图与图纸，并回传**图**，使订阅方能判断这批发现是否关于用户正在看的东西。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

signal gpFindingsReady(gpFindings: Array[GPFinding], gpGraph: GPPIDGraph)

# Debounce window in seconds. Long enough to coalesce a drag, short enough to feel live.
# 去抖窗口（秒）。长到能合并一次拖拽，短到仍有实时感。
const GP_DEBOUNCE: float = 0.25

var gpGraph: GPPIDGraph = null
var gpSheet: GPSheet = null
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


# Point the scheduler at a sheet's data (null graph unbinds).
# 指向某张图纸的数据（图为 null 即解绑）。
# Rebinding CANCELS an in-flight run: `_gpRunning` is cleared and the slice cursor reset, so no
# findings from the previous sheet can be published after the switch.
# 重绑会**取消**在途运行：清 `_gpRunning` 并复位分片游标，故切换后不会再有上一张图纸的发现被发布。
func gpBind(gpGraphIn: GPPIDGraph, gpSheetIn: GPSheet,
		gpDefsIn: Array[GPSymbolDef] = []) -> void:
	gpGraph = gpGraphIn
	gpSheet = gpSheetIn
	gpDefs = gpDefsIn
	_gpDirty = gpGraph != null
	_gpElapsed = 0.0
	_gpRunning = false
	_gpSlice = 0
	_gpAccum.clear()
	set_process(gpEnabled and gpGraph != null)


# A graph change arrived. The argument is accepted so this can be connected straight to the bus.
# 图变化到达。参数用于直接连总线。
func gpMarkDirty(_gpGraph: GPPIDGraph = null) -> void:
	_gpDirty = true
	_gpElapsed = 0.0
	set_process(gpEnabled and gpGraph != null)


func gpSetEnabled(gpOn: bool) -> void:
	gpEnabled = gpOn
	set_process(gpOn and gpGraph != null and _gpDirty)


func _process(gpDelta: float) -> void:
	if gpGraph == null:
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
	if gpGraph == null:
		_gpRunning = false
		set_process(false)
		return
	var gpFamily: String = GP_SLICES[_gpSlice] if _gpSlice < GP_SLICES.size() else ""
	var gpOptions: Dictionary = {
		"families": [] if gpFamily == "" else [gpFamily],
		"skip_legacy": _gpSlice > 0,
	}
	var gpT0: int = Time.get_ticks_usec()
	var gpFound: Array[GPFinding] = GPDrcEngine.gpRunSheet(gpGraph, gpSheet,
		gpDefs, gpGraph.gpStandard, gpOptions)
	gpLastRunUsec = Time.get_ticks_usec() - gpT0
	gpOverBudget = gpLastRunUsec > GP_BUDGET_USEC
	_gpAccum.append_array(gpFound)
	_gpSlice += 1
	if _gpSlice < GP_SLICES.size():
		return
	_gpRunning = false
	set_process(false)
	gpLastFindings = GPDrcEngine.gpFinalize(_gpAccum, gpGraph.gpStandard)
	gpFindingsReady.emit(gpLastFindings, gpGraph)
	# If the graph changed while slices were running, start a fresh pass after the debounce.
	if _gpDirty:
		_gpRunning = false
		_gpSlice = 0
		_gpAccum.clear()
		_gpElapsed = 0.0
		set_process(gpEnabled and gpGraph != null)


# Run the current sheet once and publish. Public so tests / a menu can force it.
# 立即跑一次当前图纸并发布。公开以便测试 / 菜单强制触发。
func gpRunNow() -> void:
	if gpGraph == null:
		return
	_gpRunning = false
	_gpSlice = 0
	_gpAccum.clear()
	var gpT0: int = Time.get_ticks_usec()
	gpLastFindings = GPDrcEngine.gpRunSheet(gpGraph, gpSheet, gpDefs,
		gpGraph.gpStandard)
	gpLastRunUsec = Time.get_ticks_usec() - gpT0
	gpOverBudget = gpLastRunUsec > GP_BUDGET_USEC
	gpFindingsReady.emit(gpLastFindings, gpGraph)
