class_name GPCanvasSymbolLayer
extends RefCounted
# Copyright © 2026 Jonson Wang
# symbol view sync and hit testing
# 符号视图同步与命中测试
#
# WHY THIS EXISTS / 为何存在（架构优化建议 §3.4）：
#   GPCanvas2D was carrying many unrelated responsibilities in one file; this coordinator
#   owns the "symbol view sync and hit testing" use case end to end, so the root keeps only assembly and forwarding.
#   GPCanvas2D 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「符号视图同步与命中测试」这一用例，
#   使根类只保留装配与转发。
#
# Interaction / 交互方式：
#   - the root creates this coordinator and injects itself as gpHost (composition root);
#     根类创建本协调者并把自身注入为 gpHost（组合根装配）；
#   - the root forwards user actions here, never the other way round — this class drives the
#     host only through its public ports (GPCanvas2D.gp*);
#     根类把用户动作转发到此处，绝不反向 —— 本类只经宿主的公开端口（GPCanvas2D.gp*）驱动宿主；
#   - the root keeps every public port it had before: callers outside the canvas are unchanged.
#     根类保留其原有的每一个公开端口：画布外部的调用方零改动。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPCanvas2D = null


# Topmost edge under a world point, or "". / 世界点下最上层的边，无则 ""。
func gpHitEdge(gpWorld: Vector2) -> String:
	return GPCanvasHitTest.gpHitEdge(gpHost.gpGraph, gpDefLookupCallable(), gpWorld, gpHost.gpViewZoom)

# Definition for a symbol id, through the binder (used by the pure geometry delegates).
# 经绑定器取某符号 id 的定义（供纯几何委托使用）。
func gpDefFor(gpSymbolId: String) -> GPSymbolDef:
	if gpHost.gpBinder == null:
		return null
	return gpHost.gpBinder.gpDefFor(gpSymbolId)

# Bound by gpDefLookupCallable(). / 由 gpDefLookupCallable() 绑定。
func gpDefLookup(gpSymbolId: String) -> GPSymbolDef:
	if gpHost.gpBinder == null:
		return null
	return gpHost.gpBinder.gpDefFor(gpSymbolId)

# Symbol-id -> definition, handed to the pure geometry / hit-test modules so they never need the
# binder (or the canvas) themselves.
# 符号 id -> 定义，交给纯几何与命中测试模块，使它们无需直接依赖绑定器（或画布）。
func gpDefLookupCallable() -> Callable:
	return Callable(self, "gpDefLookup")

# Hit-test: index of the topmost annotation shape under the world point, or -1. Delegates to
# GPCanvasHitTest (P5 extraction); tolerance scales with zoom (6px at 100%).
# 命中测试：世界点下最上层注释图形下标，未命中 -1。委托 GPCanvasHitTest（P5 抽取）；容差随缩放（100% 时 6px）。
func gpHitShape(gpWorld: Vector2) -> int:
	return GPCanvasHitTest.gpHitShape(gpHost.gpGraph, gpWorld, gpHost.gpViewZoom)


# Queue redraw on all edge views (delegates to binder).
# 令所有连线视图重新绘制（委托给绑定器）。
func gpRefreshEdges() -> void:
	if gpHost.gpBinder != null:
		gpHost.gpBinder.gpRefreshEdges()

# Topmost node under a world point, or "". Delegates to GPCanvasHitTest (P5 extraction).
# 世界点下最上层的节点，无则 ""。委托 GPCanvasHitTest（P5 抽取）。
func gpHitTest(gpWorld: Vector2) -> String:
	return GPCanvasHitTest.gpHitNode(gpHost.gpGraph, gpHost.gpBinder, gpWorld)

func gpNodeRect(gpId: String) -> Rect2:
	return GPCanvasHitTest.gpNodeRect(gpHost.gpGraph, gpHost.gpBinder, gpId)

# ============================ lookup ============================
# ============================ 查找 ============================
# --- lookup ports delegate to GPCanvasHitTest (P5 extraction) ---
# --- 查找端口委托给 GPCanvasHitTest（P5 抽取）---
func gpNodeCenter(gpId: String) -> Vector2:
	return GPCanvasHitTest.gpNodeCenter(gpHost.gpGraph, gpId)

# Public port: repaint every symbol view. M10b fix — the tag label is painted by
# GPSymbolView, NOT by the canvas, and a parent's queue_redraw() never cascades to
# child CanvasItems. Without this a tag drag moved the model while the text stood still.
# 公开端口：重绘所有图元视图。M10b 修复 —— 位号标签由 GPSymbolView 绘制、而非画布，
# 且父节点的 queue_redraw() 不会级联到子 CanvasItem。缺此步，拖拽位号时模型动了、文字不动。
func gpRefreshSymbolViews() -> void:
	gpRefreshSymbols()

# Queue redraw on all symbol views (delegates to binder).
# 令所有图元视图重新绘制（委托给绑定器）。
func gpRefreshSymbols() -> void:
	if gpHost.gpBinder != null:
		gpHost.gpBinder.gpRefreshSymbols()

# ============================ view sync ============================
# ============================ 视图同步 ============================
# Sync both symbol views and edge views to the current graph state.
# 将图元视图与连线视图同步到当前图状态。
func gpSyncViews() -> void:
	if gpHost.gpBinder == null:
		return
	# gpZoom is forwarded so edge styling can hold its screen-space floors (line weight, dash
	# length, arrowhead, selection halo) instead of shrinking with the drawing.
	# 转发 gpZoom，使连线样式能保持其屏幕空间下限（线重、划长、箭头、选中光晕），
	# 而不随图纸一起缩小。
	# Edge selection lives in its own array (gpEdgeSel); forward it so the binder can light up the
	# edge halo (it was previously ignored, so a selected pipe showed only grip triangles).
	# 边选择存于独立数组 gpEdgeSel；一并转发使绑定器点亮边光晕（此前被忽略，选中管线只显三角）。
	# While a grip is being dragged, flag that edge as "editing" for a distinct highlight.
	# 抓取点拖拽进行中，把该边标记为「编辑中」以呈现差异化高亮。
	var gpEditingEdgeId: String = ""
	if gpHost.gpEdgeGrips != null and gpHost.gpEdgeGrips.gpIsDragging():
		gpEditingEdgeId = gpHost.gpEdgeGrips.gpDraggingEdgeId()
	gpHost.gpBinder.gpSync(gpHost.gpGraph, gpHost.gpDefs, gpHost.gpSelection, gpHost.gpConnectFrom, gpHost.gpViewZoom, gpHost.gpEdgeSel, gpEditingEdgeId)
