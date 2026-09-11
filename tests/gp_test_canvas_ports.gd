extends "res://tests/gp_test.gd"
# 架构优化 §3.4：钉住 GPCanvas2D 的对外门面（1 root + 4 实现类拆分之后）。
# Architecture §3.4: pin GPCanvas2D's public facade after the 1-root + 4-impl split.
#
# Why this exists / 为何存在：
#   canvas_2d.gd（1,347 行）按 §3.4 拆成 GPCanvasViewController / GPCanvasInputRouter /
#   GPCanvasEditFacade / GPCanvasSymbolLayer 四个实现类。根类把 41 个公开端口全部保留为
#   「单行转发壳」，外部调用方（main_window、属性面板、工具）零改动 —— 这是本次重构的
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
	"gpReportRefusal", 1,
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
	gpCheck(gpCv.gpDefFor("LPUMP003") == null, "无 binder 时定义查找返回 null / def lookup is null-safe")
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
