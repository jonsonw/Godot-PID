extends "res://tests/gp_test.gd"
# 钉住 GPCanvas2D 的对外门面（1 root + 4 实现类拆分之后）。
# pin GPCanvas2D's public facade after the 1-root + 4-impl split.
#
# Why this exists / 为何存在：
#   canvas_2d.gd（1,347 行）拆成 GPCanvasViewController / GPCanvasInputRouter /
#   GPCanvasEditFacade / GPCanvasSymbolLayer 四个实现类。根类把 41 个公开端口全部保留为
#   「单行转发壳」，外部调用方（main_window、属性面板、工具）零改动 —— 这是该拆分的
#   核心不变量。转发壳一旦被误删或改签名，编译期**不会**报错（Godot 允许任意方法集），
#   只有运行时才炸，故必须用测试钉住。
#
#   The root keeps all 41 public ports as one-line forwarders; a deleted or re-signatured
#   forwarder is NOT a compile error in GDScript (any method set is legal), it only blows up
#   at runtime — so it has to be pinned by a test.
#
# The port list below is a snapshot of `func gp*` on GPCanvas2D (name, arity).
# 下面的端口清单是 GPCanvas2D 上 `func gp*` 的一份快照（函数名、参数个数）。

# Flat pairs: port name, expected argument count.
# 扁平成对：端口名、预期参数个数。
const GP_PORTS: Array = [
	"gpSetMode", 1,
	"gpBindDocument", 1,
	"gpEmitStatus", 0,
	"gpScreenFromWorld", 1,
	"gpWorldFromScreen", 1,
	"gpRefreshSymbolViews", 0,
	"gpNodeCenter", 1,
	"gpNodeRect", 1,
	"gpHitTest", 1,
	"gpHitShape", 1,
	"gpSetSelection", 1,
	"gpRequestSelectAll", 0,
	"gpSetEdgeSelection", 1,
	"gpRequestDeleteSelected", 0,
	"gpUndo", 0,
	"gpRedo", 0,
	"gpCanUndo", 0,
	"gpCanRedo", 0,
	"gpRequestDuplicateSelected", 0,
	"gpRequestPlaceNode", 2,
	"gpRequestConnect", 2,
	"gpRequestAddShape", 1,
	"gpRequestMoveNodes", 2,
	"gpCancelActiveTool", 0,
	"gpDefLookupCallable", 0,
	"gpRequestSetLabelOffset", 2,
	"gpDefFor", 1,
	"gpRequestConnectEdge", 5,
	"gpRequestDeleteEdges", 1,
	"gpRequestSetEdgeTag", 2,
	"gpRequestReconnectEdge", 3,
	"gpRequestSetEdgeRouting", 2,
	"gpClearPortPick", 0,
	"gpRequestAutoConnect", 0,
	"gpHitEdge", 1,
	# P0-D24 widened it with an OPTIONAL prefix (default "edge."): cross-sheet refusals
	# report under offpage.refuse_* instead of showing a raw key.
	# P0-D24 增加了**可选**前缀参数（默认 "edge."）：跨图纸拒绝经 offpage.refuse_* 上报，
	# 不再显示裸键。
	"gpReportRefusal", 2,
	"gpDeleteSelection", 0,
	"gpClearSelection", 0,
	"gpZoomStep", 1,
	"gpSnapshot", 0,
	"gpResetView", 0,
]


# Every public port still exists on the root, with the same arity it had before the split.
# 拆分后每个公开端口仍存在于根类上，且参数个数不变。
func gpTestPublicPortsKept() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpArity: Dictionary = {}
	for gpM in gpCv.get_method_list():
		var gpArgs: Array = gpM["args"]
		gpArity[str(gpM["name"])] = gpArgs.size()
	var gpCount: int = 0
	for gpI in range(0, GP_PORTS.size(), 2):
		var gpName: String = str(GP_PORTS[gpI])
		var gpWant: int = int(GP_PORTS[gpI + 1])
		gpCount += 1
		gpCheck(gpArity.has(gpName), "公开端口仍在根类上 / public port still on the root: " + gpName)
		gpEq(gpArity.get(gpName, -1), gpWant, "参数个数不变 / arity unchanged: " + gpName)
	gpEq(gpCount, 41, "钉住的公开端口总数 / pinned public port count")
	gpCv.free()


# The four implementation classes are assembled and pointed back at the canvas.
# 四个实现类均已装配，并反向指向画布。
func gpTestImplementationClassesWired() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCheck(gpCv.gpViewController != null, "GPCanvasViewController 已装配 / view controller assembled")
	gpCheck(gpCv.gpInputRouter != null, "GPCanvasInputRouter 已装配 / input router assembled")
	gpCheck(gpCv.gpEditFacade != null, "GPCanvasEditFacade 已装配 / edit facade assembled")
	gpCheck(gpCv.gpSymbolLayer != null, "GPCanvasSymbolLayer 已装配 / symbol layer assembled")
	gpCheck(gpCv.gpViewController.gpHost == gpCv, "gpHost 指回画布 / view controller points back")
	gpCheck(gpCv.gpInputRouter.gpHost == gpCv, "gpHost 指回画布 / input router points back")
	gpCheck(gpCv.gpEditFacade.gpHost == gpCv, "gpHost 指回画布 / edit facade points back")
	gpCheck(gpCv.gpSymbolLayer.gpHost == gpCv, "gpHost 指回画布 / symbol layer points back")
	gpCv.free()


# Regression: a canvas that never entered the scene tree must still answer its ports.
# 回归：从未进入场景树的画布，其公开端口仍必须可用。
#
# Headless regression checkers call GPCanvas2D.new() and use it directly; _ready never fires
# there, so any collaborator created only in _ready makes the forwarders hit null. The four
# implementation classes are therefore assembled in _init. This test is what keeps that true.
# headless 回归检查器直接 GPCanvas2D.new() 后就调用其端口，那时 _ready 永不触发；
# 只在 _ready 里创建的协作者会让转发壳打到 null 上。故四个实现类在 _init 装配 —— 本测试钉住这点。
func gpTestPortsWorkOutsideTheTree() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCheck(not gpCv.is_inside_tree(), "探针：画布刻意不入树 / probe: deliberately off-tree")
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpCv.gpGraph = gpG
	# Edit facade / 编辑门面。
	gpEq(gpCv.gpCanUndo(), false, "gpCanUndo 可在树外调用 / callable off-tree")
	gpEq(gpCv.gpCanRedo(), false, "gpCanRedo 可在树外调用 / callable off-tree")
	gpEq(gpCv.gpUndo(), false, "gpUndo 空栈返回 false / gpUndo on an empty stack")
	gpEq(gpCv.gpRedo(), false, "gpRedo 空栈返回 false / gpRedo on an empty stack")
	# Symbol layer / 符号图层。
	gpEq(gpCv.gpHitTest(Vector2(4.0, 4.0)), "", "空图命中为空 / no hit on an empty graph")
	gpEq(gpCv.gpHitEdge(Vector2(4.0, 4.0)), "", "空图命中边为空 / no edge hit on an empty graph")
	gpEq(gpCv.gpHitShape(Vector2(4.0, 4.0)), -1, "空图命中图形为 -1 / no shape hit on an empty graph")
	gpCheck(gpCv.gpDefFor("DPUMP001") == null, "无 binder 时定义查找返回 null / def lookup is null-safe")
	gpCheck(gpCv.gpDefLookupCallable().is_valid(), "定义查找 Callable 在树外有效 / def callable valid off-tree")
	# View controller / 视图控制器：屏幕 <-> 世界换算必须往返一致（默认 100% / 零偏移）。
	# Screen <-> world must round-trip at the default 100% zoom / zero offset.
	var gpBack: Vector2 = gpCv.gpScreenFromWorld(gpCv.gpWorldFromScreen(Vector2(33.0, 44.0)))
	gpApprox(gpBack.x, 33.0, 0.001, "坐标换算往返 x / coordinate round-trip x")
	gpApprox(gpBack.y, 44.0, 0.001, "坐标换算往返 y / coordinate round-trip y")
	# Status / 状态。
	gpCv.gpClearPortPick()
	gpCv.gpReportRefusal("")
	var gpSnap: Dictionary = gpCv.gpSnapshot()
	gpCheck(gpSnap.has("mode"), "gpSnapshot 含 mode / snapshot carries the mode")
	gpCheck(gpSnap.has("view_zoom"), "gpSnapshot 含 view_zoom / snapshot carries the zoom")
	gpCv.free()


# A counting binder: records the refresh fan-out without a scene tree (off-tree, like every
# fixture in this file — the refresh ports are null-safe there by design).
# 计数绑定器：无需场景树即可记录刷新扇出（树外，与本文件所有夹具一致 —— 刷新端口在设计
# 上就是空安全的）。
class _gpCountBinder extends GPGraphBinder:
	var gpSymbolRefreshes: int = 0
	var gpEdgeRefreshes: int = 0

	func gpRefreshSymbols() -> void:
		gpSymbolRefreshes += 1

	func gpRefreshEdges() -> void:
		gpEdgeRefreshes += 1


# Stage 3 S4 fix: the CORE graph's change signal must reach the CHILD CanvasItems. A parent's
# queue_redraw() does not cascade to children, and the binder's rebind guard is reference-based,
# so an in-place mutation (grid-table structure op, cell text, tag edit) — and every command
# UNDO/REDO — used to leave stale pixels while the hit test moved on. The refresh now lives in
# _gpOnGraphDataChanged; this pin keeps it there.
# 阶段 3 S4 修复：核心图的变化信号必须到达**子** CanvasItem。父节点 queue_redraw() 不级联到
# 子节点，而绑定器的重绑判据是引用相等 —— 原地变换（表格结构操作、格子文字、位号编辑）以及
# 一切命令的撤销/重做都曾留下陈旧像素而命中测试已前移。刷新现居于 _gpOnGraphDataChanged；
# 本钉防止它再次丢失。
func gpTestGraphSignalRepaintsChildViews() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpB: _gpCountBinder = _gpCountBinder.new()
	gpCv.gpBinder = gpB
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpCv.gpGraph = gpG
	gpEq(gpB.gpSymbolRefreshes, 0, "仅绑定不刷新 / bind alone does not refresh")
	# One emit = one command execute / undo / redo reaching the views.
	# 一次发射 = 一次命令执行 / 撤销 / 重做到达视图。
	gpG.gpGraphChanged.emit()
	gpEq(gpB.gpSymbolRefreshes, 1, "核心图信号必须重绘图元子视图 / core graph signal repaints symbol views")
	gpEq(gpB.gpEdgeRefreshes, 1, "核心图信号必须重绘边子视图 / core graph signal repaints edge views")
	gpG.gpGraphChanged.emit()
	gpEq(gpB.gpSymbolRefreshes, 2, "再次变化再次刷新（撤销/重做同路径）/ second change refreshes again (undo/redo same path)")
	gpEq(gpB.gpEdgeRefreshes, 2, "边视图同步再刷新 / edge views refresh in step")
	gpB.free()
	gpCv.free()


# ============================================================================
# S7 (2026-11-06): the last mouse position belongs to the ROUTER, not the canvas.
# S7（2026-11-06）：最近一次鼠标位置属于**路由**，不属于画布。
#
# WHY THIS PIN EXISTS / 为何需要这颗钉：
# `_gpLastMouseWorld` was the only state on GPCanvas2D whose single writer lived in another
# class. GPCanvasInputRouter wrote it through `gpHost._gpLastMouseWorld = ...` — three
# cross-object private accesses, the last real ones in the canvas. The canvas merely stored the
# number and read it once, to put a coordinate into the status snapshot.
# `_gpLastMouseWorld` 是画布上唯一「唯一写入者住在另一个类里」的状态：GPCanvasInputRouter 经
# `gpHost._gpLastMouseWorld = ...` 写它 —— 三处跨对象私有访问，也是画布内最后三处。画布只是替它
# 存着，并且只读一次（往状态快照里放一个坐标）。
#
# The failure this pin prevents is not a crash. It is the shape the canvas file itself already
# documents twice (drawing state, shape-drag state): state left on the root "because the root is
# where things are", and then the root is the party that has to be kept in sync with the class
# that actually acts on the value. Nobody notices; the status bar just shows a stale coordinate.
# 本钉防的不是崩溃，而是画布文件里已经写过两次的形状（绘图态、图形拖拽态）：状态「因为根类方便」
# 留在根类，于是根类成了那个必须跟真正使用它的类保持同步的一方。没人会注意到 —— 状态栏只是显示
# 一个过期的坐标。
# ============================================================================

const GP_INPUT_ROUTER_PATH: String = "res://src/ui/canvas/input_router.gd"
const GP_CANVAS_PATH: String = "res://src/ui/canvas/canvas_2d.gd"


func gpTestMouseTrackingStateLivesWithTheRouter() -> void:
	var gpRouterSrc: String = FileAccess.get_file_as_string(GP_INPUT_ROUTER_PATH)
	var gpCanvasSrc: String = FileAccess.get_file_as_string(GP_CANVAS_PATH)
	gpCheck(gpRouterSrc != "" and gpCanvasSrc != "",
		"两份源码可读（不可读会让下面每条都白过）/ both sources are readable")

	# 1) The state is declared by its writer, and stays PRIVATE there.
	# 1) 状态由它的写入者声明，并在那里保持**私有**。
	gpCheck(gpRouterSrc.contains("var _gpLastMouseWorld: Vector2"),
		"字段住在路由里且是私有的 / the field lives in the router, privately")
	gpCheck(gpRouterSrc.contains("func gpLastMouseWorld() -> Vector2"),
		"路由提供只读端口 / the router publishes a read-only port")

	# 2) The canvas no longer declares it. A leftover declaration is the dangerous shape: it
	# compiles, the snapshot keeps using it, and the router's value silently drifts away from
	# the one on screen.
	# 2) 画布不再声明它。残留声明是最危险的形状：照样编译，快照继续用它，而路由里的值与屏幕上
	# 的那个悄悄分家。
	gpCheck(not gpCanvasSrc.contains("var _gpLastMouseWorld"),
		"画布不再持有这个字段 / the canvas no longer declares the field")

	# 3) The snapshot READS THROUGH THE PORT. Checked as the exact expression, because the
	# failure mode here is a plausible-looking alternative (a local copy, a parameter, a
	# recomputed value) that is wrong for a reason no reviewer would see.
	# 3) 快照**经端口读**。判据是完整表达式：此处的失效形态是一个看起来同样合理的替代（本地副本、
	# 参数、重算的值），而它错在一个评审看不出来的理由上。
	gpCheck(gpCanvasSrc.contains('"world": gpInputRouter.gpLastMouseWorld()'),
		"状态快照经端口取值 / the status snapshot borrows the value through the port")

	# 4) Anti-backslide, judged inside the router only: no cross-object private access left in
	# it at all. `gpHost._gp` is the precise marker — `_gpLastMouseWorld` alone would also match
	# the router's own field.
	# 4) 防回流，只在路由内判定：其中不得再有任何跨对象私有访问。判据用 `gpHost._gp` 前缀 ——
	# 只用 `_gpLastMouseWorld` 会把路由自己的字段也算进去。
	gpCheck(not gpRouterSrc.contains("gpHost._gp"),
		"路由不再经宿主读私有成员 / the router touches no private member of its host")

	# 5) Read-only means read-only: no setter. A `gpSetLastMouseWorld()` would let any caller
	# move the "cursor" with no mouse — the status bar would then report a position where
	# nothing happened.
	# 5) 只读就是只读：不得有 setter。`gpSetLastMouseWorld()` 会让任何调用方在没有鼠标的情况下
	# 移动「光标」—— 状态栏随后会报告一个什么都没发生过的位置。
	gpCheck(not gpRouterSrc.contains("func gpSetLastMouseWorld"),
		"没有可写端口（状态只有一个写入者）/ no setter: the state has exactly one writer")

	# 6) Behaviour, off-tree: the port answers, and the emitted snapshot carries the same
	# number. `gpEvents` has a private fallback bus, so gpEmitStatus() is callable without
	# the scene tree (that is what makes this assertion possible at all).
	# 6) 行为（树外）：端口可用，且发出的快照带着同一个数。`gpEvents` 有私有回退总线，故
	# gpEmitStatus() 无需场景树即可调用 —— 这正是这条断言得以成立的前提。
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpEq(gpCv.gpInputRouter.gpLastMouseWorld(), Vector2.ZERO,
		"未收到移动事件时为零 / zero before any motion event")
	var gpSeen: Array[Dictionary] = []
	gpCv.gpStatusUpdated.connect(func(gpIn: Dictionary) -> void: gpSeen.append(gpIn))
	gpCv.gpEmitStatus()
	gpEq(gpSeen.size(), 1, "快照已发出 / one snapshot emitted")
	gpCheck(gpSeen[0].has("world"), "快照含 world 键 / the snapshot carries 'world'")
	gpEq(gpSeen[0].get("world", Vector2.ONE), gpCv.gpInputRouter.gpLastMouseWorld(),
		"快照里的坐标就是端口的值 / the snapshot's coordinate IS the port's value")
	gpCv.free()
