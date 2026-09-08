class_name GPEventBus
extends RefCounted
# Application-layer event channel (M2 of the modularisation plan).
# 应用层事件通道（模块化方案 M2）。
#
# Why this exists / 存在理由:
#   Before M2 the app had two parallel, half-dead channels:
#   M2 之前应用层存在两条并行且半失效的通道：
#     1. GPPIDGraph.gpGraphChanged (core) — emitted 7x but had ZERO subscribers,
#        so programmatic mutations (e.g. cascade-deleting a symbol) never reached the UI.
#        core 的 gpGraphChanged 发射 7 处却零订阅者，导致程序化改动（如级联删除图元）传不到 UI。
#     2. GPCanvas2D.gpStatusUpdated — the inspector refresh was secretly piggybacked on
#        the STATUS channel (main_window diffed "selection" string on every status tick).
#        属性面板刷新偷偷寄生在状态通道上（main_window 每次状态更新比对选中字符串）。
#   The bus replaces both with ONE explicit, typed, headless-testable channel, and cuts
#   the app->ui coupling: services emit, widgets subscribe, nobody polls private state.
#   总线用一条显式、强类型、可 headless 测试的通道取代两者，并切断 app→ui 耦合：
#   服务发事件、控件订阅，谁都不轮询对方私有状态。
#
# Scope rule / 作用域规则:
#   One bus per sheet (canvas), NOT one global bus. A global bus would cross-wire every
#   open sheet (all canvases redrawing / refreshing on another sheet's change).
#   每图纸（画布）一条总线，而非全局单条。全局总线会让所有图纸串扰。
#   M6 (document_manager) will take ownership of the bus; until then the canvas owns it.
#   M6（document_manager）将接管总线所有权；在此之前由画布持有。
#
# Layering / 分层:
#   ui -> app -> core. The bus lives in app and carries NO ui types: subscribers may be
#   widgets today and headless tests tomorrow, and app code never learns which.
#   总线位于 app 层且不携带任何 ui 类型：订阅者今天是控件、明天是测试，app 代码无需知晓。

# Graph data changed: node/edge/annotation-shape added, moved, edited or removed.
# Carries the graph itself so a subscriber can tell which sheet changed without
# reaching back into the canvas.
# 图数据变化：节点 / 连线 / 注释图形增删改移。携带图对象本身，使订阅者无需回查画布
# 即可判断是哪张图纸发生变化。
signal gpGraphChanged(gpGraph: GPPIDGraph)

# Selection set changed (click, marquee, Ctrl+A, delete, ...). Carries the new id list.
# This replaces the old "diff the selection string inside the status handler" hack.
# 选择集变化（点击、框选、Ctrl+A、删除等）。携带新的 id 列表。
# 取代原先「在状态处理函数里比对选中字符串」的隐式做法。
signal gpSelectionChanged(gpIds: Array[String])

# Status-bar snapshot: selection id, selection count, zoom, cursor world position.
# 状态栏快照：选中 id、选中数量、缩放、光标世界坐标。
signal gpStatusUpdated(gpInfo: Dictionary)

# Interaction mode changed (select / connect / draw-*) so the toolbar highlight can follow.
# 交互模式变化（选择 / 连线 / 绘图），供工具栏高亮同步。
signal gpModeChanged(gpNewMode: int)

# Active document swapped (open / new / switch sheet). Carries the new graph so subscribers
# can re-bind the correct sheet in ONE place. Owned/emitted by GPAppDocumentManager (M6).
# 当前文档切换（打开 / 新建 / 切换图纸）。携带新图，使订阅者在一处重新绑定正确的图纸。
# 由 GPAppDocumentManager（M6）持有并发射。
signal gpDocChanged(gpGraph: GPPIDGraph)

# Unsaved-changes flag flipped. Carries the new dirty state so the title bar / project tree
# can show a "needs save" marker without polling private state. Owned/emitted by
# GPAppDocumentManager (M6).
# 未保存改动标记翻转。携带新的脏标记状态，使标题栏/工程树无需轮询私有态即可显示保存提示。
# 由 GPAppDocumentManager（M6）持有并发射。
signal gpDirtyChanged(gpDirty: bool)


# Number of connected callables for a given signal name. Used by tests to assert that
# a subscriber really detached (a leaked connection is the classic event-bus bug).
# 指定信号的已连接数量。测试用它断言订阅者确实解绑（连接泄漏是事件总线的典型缺陷）。
func gpConnectionCount(gpSignalName: String) -> int:
	var gpSigs: Array[Dictionary] = get_signal_list()
	for gpS in gpSigs:
		if str(gpS.get("name", "")) == gpSignalName:
			var gpArr: Array[Dictionary] = get_signal_connection_list(gpSignalName)
			return gpArr.size()
	return -1
