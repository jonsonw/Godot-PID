class_name GPAppDocumentManager
extends RefCounted
# Application-layer document state owner (M6 of the modularisation plan).
# 应用层文档状态所有者（模块化方案 M6）。
#
# Replaces the old GPAppState autoload stub. Instead of a global singleton that every
# module reaches into directly, the composition root (main_window) builds ONE manager per
# open document and injects it into the canvas. The manager owns the event bus (so the
# canvas no longer creates its own), tracks the active graph and the unsaved-dirty flag,
# and broadcasts document / dirty changes through the bus.
# 取代旧 GPAppState 自动加载桩。不再是一个人人可钻的全局单例，而是由组合根（main_window）
# 为每个打开的文档构建唯一管理器并注入画布。管理器持有事件总线（画布不再自建），
# 跟踪当前图与未保存脏标记，并经由总线广播文档/脏标记变更。

# Active document (single-sheet topology graph).
# 当前文档（单图纸拓扑图）。
var gpGraph: GPPIDGraph = null

# True when the active document has unsaved changes.
# 当前文档存在未保存改动时为 true。
var gpDirty: bool = false

# Event channel owned by this manager. The canvas forwards onto it; widgets subscribe.
# 本管理器持有的事件通道。画布向其转发；控件订阅之。
# Created here on purpose: the manager is the single owner of the bus (M6).
# 刻意在此创建：管理器是总线的唯一所有者（M6）。
var gpBus: GPEventBus = GPEventBus.new()


# Swap the active document. Resets the dirty flag and announces the change so every
# subscriber (title bar, project tree, canvas) can re-bind in one place.
# 切换当前文档。重置脏标记并通告变更，使所有订阅者（标题栏、工程树、画布）在一处重新绑定。
func gpSetGraph(gpNewGraph: GPPIDGraph) -> void:
	gpGraph = gpNewGraph
	gpDirty = false
	if gpBus != null:
		gpBus.gpDocChanged.emit(gpNewGraph)


# Mark the document dirty (an edit happened). Idempotent: emits only on the rising edge.
# 标记文档为脏（发生了编辑）。幂等：仅在上升沿发射。
func gpMarkDirty() -> void:
	if gpDirty:
		return
	gpDirty = true
	if gpBus != null:
		gpBus.gpDirtyChanged.emit(true)


# Clear the dirty flag (document saved / freshly opened). Idempotent.
# 清除脏标记（已保存 / 刚打开）。幂等。
func gpClearDirty() -> void:
	if not gpDirty:
		return
	gpDirty = false
	if gpBus != null:
		gpBus.gpDirtyChanged.emit(false)


# Report whether the document needs saving.
# 报告文档是否需要保存。
func gpIsDirty() -> bool:
	return gpDirty
