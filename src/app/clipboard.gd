class_name GPClipboard
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Application-wide clipboard for symbols / edges / annotation shapes, as VALUE objects.
# 应用级剪贴板，存放图元 / 连线 / 注释图形的**值对象**。
#
# Why a static store and not an autoload / 为何用 static 存储而非自动加载：
# The clipboard has to outlive the SHEET (that is the whole point of A6: copy here, paste on
# another drawing), but it does not need a scene-tree node, a signal or a lifecycle. A static
# Dictionary is reachable from every layer that may need it, works in a headless test, and adds
# no autoload to project.godot.
# 剪贴板必须比**图纸**活得久（这正是 A6 的全部意义：在这张图上复制、到另一张图上粘贴），
# 但它不需要场景树节点、信号或生命周期。一个 static 字典在任何需要它的层都可达、在 headless
# 测试里可用，且无需往 project.godot 里添加自动加载。
#
# Why DICTIONARIES and not live objects / 为何存字典而非活对象：
# A live GPPIDNode belongs to ONE graph: pasting the same object into a second sheet would make
# two drawings share one node, so editing either would silently edit both. Serialising at copy
# time (and cloning at paste time) is what keeps the two sheets independent.
# 活的 GPPIDNode 属于**一张**图：把同一对象粘到第二张图纸会让两张图共享一个节点，改任一张都会
# 静默改到另一张。复制时序列化、粘贴时克隆，正是两张图纸彼此独立的原因。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The captured payload: {"nodes": Array[Dictionary], "edges": Array[Dictionary],
# "shapes": Array[Dictionary]}. Empty means "nothing was copied yet".
# 捕获的载荷：{"nodes": ..., "edges": ..., "shapes": ...}。为空表示尚未复制过任何东西。
static var gpPayload: Dictionary = {}

# Monotonic counter bumped on every copy. Pasting does not change it; the render/status layers
# may use it to say "pasted the copy captured at revision N" (and tests use it to prove that a
# second copy really replaced the first).
# 每次复制自增的计数器。粘贴不改它；渲染 / 状态层可用它表达「粘贴的是第 N 次复制的快照」，
# 测试也用它证明第二次复制确实替换了第一次。
static var gpRevision: int = 0


# Replace the clipboard contents. The arrays are duplicated deep so a later edit to the source
# objects cannot mutate what the user already copied.
# 替换剪贴板内容。数组做深拷贝，使之后对源对象的编辑无法改到用户已复制的内容。
static func gpSet(gpNodes: Array, gpEdges: Array, gpShapes: Array) -> void:
	gpPayload = {
		"nodes": gpNodes.duplicate(true),
		"edges": gpEdges.duplicate(true),
		"shapes": gpShapes.duplicate(true),
	}
	gpRevision += 1


# Whether anything is copied.
# 是否已复制过内容。
static func gpHas() -> bool:
	return not gpNodes().is_empty() or not gpEdges().is_empty() or not gpShapes().is_empty()


# Copied node dictionaries (empty when nothing was copied).
# 复制的节点字典（未复制时为空）。
static func gpNodes() -> Array:
	return gpPayload.get("nodes", []) as Array


# Copied edge dictionaries.
# 复制的连线字典。
static func gpEdges() -> Array:
	return gpPayload.get("edges", []) as Array


# Copied shape dictionaries.
# 复制的图形字典。
static func gpShapes() -> Array:
	return gpPayload.get("shapes", []) as Array


# Drop the contents (a fresh copy replaces them; this is for tests and for "clear clipboard").
# 丢弃内容（新的复制会替换它们；本函数供测试与「清空剪贴板」使用）。
static func gpClear() -> void:
	gpPayload = {}
