class_name GPCommandContext
extends RefCounted
# Everything a command is allowed to touch (M4 of the modularisation plan).
# 命令允许接触的全部依赖（模块化方案 M4）。
#
# Why this exists / 存在理由:
#   Commands used to be inline code inside GPCanvas2D (delete / duplicate / move / ...),
#   mixing "what the user asked for" with "how the canvas keeps itself in sync". The
#   context object is the seam: a command receives the graph and the id generator, and
#   nothing else. It cannot reach into widgets, so it cannot acquire UI coupling by
#   accident, and the very same command runs headless in a unit test.
#   命令原先是 GPCanvas2D 里的内联代码（删除 / 复制 / 移动…），把「用户要什么」和
#   「画布如何自同步」混在一起。上下文对象就是那条缝：命令只拿到图与 id 生成器，
#   拿不到任何控件，因此无法意外引入 UI 耦合，同一条命令也能在 headless 单测里跑。
#
# Deliberately NOT injected / 刻意不注入:
#   - GPCanvas2D: commands mutate the model only. View refresh is a consequence of
#     GPPIDGraph.gpGraphChanged, which the canvas already bridges onto GPEventBus (M2).
#     画布：命令只改模型。视图刷新是 gpGraphChanged 的结果，画布已把它桥接到总线（M2）。
#   - GPEventBus: the model signal already reaches the bus through the canvas bridge,
#     so a command emitting on the bus directly would double-notify every subscriber.
#     事件总线：模型信号已通过画布桥到达总线，命令直接发总线会让订阅者收到两次。
#   M6 (PIDDocumentManager) will own this context; until then the canvas builds it.
#   M6（PIDDocumentManager）将持有此上下文；在此之前由画布构建。

# The topology being edited. Commands add/remove/mutate nodes, edges and shapes on it.
# 正在编辑的拓扑图。命令在其上增 / 删 / 改节点、边与注释图形。
var gpGraph: GPPIDGraph = null

# Id source for objects a command creates. Shared with the canvas so generated ids stay
# unique across interactive and programmatic edits (and later across sheets, W21).
# 命令创建对象所用的 id 来源。与画布共享，使生成的 id 在交互改动与程序化改动之间
# 保持唯一（未来跨图纸亦唯一，W21）。
var gpIds: GPIdGen = null


# Both collaborators may be supplied up front; a null graph simply makes every command
# refuse to run (gpIsReady) instead of crashing on a nil dereference.
# 两个协作者可在构造时一次给全；图为 null 时命令只是拒绝执行（gpIsReady），而非空引用崩溃。
# Tag uniqueness guard (M9). Optional: without it commands still run, they just cannot mint
# or refuse a tag — which is exactly how every pre-M9 command behaves in the tests.
# 位号唯一性守卫（M9）。可选：没有它命令照常运行，只是不能铸造或拒绝位号
# ——这正是 M9 之前每条命令在测试中的行为。
var gpTags: GPTagRegistry = null


# Both collaborators may be supplied up front; a null graph simply makes every command
# refuse to run (gpIsReady) instead of crashing on a nil dereference.
# 两个协作者可在构造时一次给全；图为 null 时命令只是拒绝执行（gpIsReady），而非空引用崩溃。
func _init(gpInGraph: GPPIDGraph = null, gpInIds: GPIdGen = null,
		gpInTags: GPTagRegistry = null) -> void:
	gpGraph = gpInGraph
	gpIds = gpInIds
	gpTags = gpInTags


# True when the context can actually run a command that mutates the graph.
# Commands that also create objects should additionally check gpIds.
# 上下文能否真正执行改动图的命令。会创建对象的命令还应额外检查 gpIds。
func gpIsReady() -> bool:
	return gpGraph != null and gpIds != null
