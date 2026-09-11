class_name GPSnapResolver
extends RefCounted
# Copyright © 2026 Jonson Wang
# The ONLY place that turns a raw world click into "what did the user mean to connect to?".
# 把一次原始世界点击换算为「用户想连到哪里」的唯一场所。
#
# Why a pure static module / 为何是纯静态模块：
#   Both the pipe tool and the signal tool need the same answer, and the answer must be
#   testable without a canvas: given a graph and a point, which port (if any) is meant? Putting
#   this in a tool would force a fake canvas into the test; here it is a pure function of the
#   graph.
#   管道工具与信号线工具需要同一个答案，且该答案必须无需画布即可测试：给定图与点，指的是哪个
#   端口？若放进工具里，测试就得伪造画布；放在此处则是图的纯函数。
#
# The priority ladder is deliberate / 优先级阶梯是刻意设计的：
#   1. a port whose TYPE the tool wants     类型被工具期望的端口
#   2. any other port                        任何其他端口
#   3. the node centre                       节点中心
#   4. the 50-unit grid                      50 单位网格
#   Step 2 exists so the tool can say "this port is the wrong kind" instead of silently
#   snapping to nothing — a user who clicks an actuator with the pipe tool must be TOLD, not
#   quietly given a dangling end.
#   第 2 步的存在，是为了让工具能说「这个端口类型不对」，而不是静默地什么都不吸 ——
#   用管道工具点到执行机构时，必须「告知」用户，而不是悄悄给他一个悬空端。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Snap radius in SCREEN pixels. Divided by zoom, so the magnet stays equally forgiving when the
# user zooms out — a fixed world radius would make ports impossible to hit at 25%.
# 吸附半径（屏幕像素）。除以 zoom，使缩小后磁力同样宽容 —— 固定的世界半径会让 25% 时根本点不中端口。
const GP_SNAP_PX: float = 12.0

# Fallback grid step in world units, matching the grid the overlay actually draws.
# 回退网格步长（世界单位），与覆盖层实际画出的网格一致。
# NOTE: named GP_GRID_STEP (not GP_GRID) to avoid colliding with the GP_GRID result-kind
# string below — Godot forbids redeclaring a constant in the same script.
# 注意：命名为 GP_GRID_STEP（而非 GP_GRID），以免与下方 GP_GRID 结果种类字符串重名。
const GP_GRID_STEP: float = 50.0

# Result kinds / 结果种类。
const GP_PORT: String = "port"  # snapped to a port / 吸附到端口
const GP_NODE: String = "node"  # snapped to a node centre / 吸附到节点中心
const GP_GRID: String = "grid"  # snapped to the grid / 吸附到网格


# Resolve a world click into a snap target.
# 把一次世界点击解析为吸附目标。
#
# [param gpGraph] the topology to search / 待搜索的拓扑图
# [param gpDefLookup] symbol-id -> GPSymbolDef (may be invalid) / 符号 id -> 定义（可为无效 Callable）
# [param gpWorld] the click in world coordinates / 点击的世界坐标
# [param gpZoom] current view zoom (radius is screen-relative) / 当前缩放（半径为屏幕相对）
# [param gpWantTypes] accepted GPPort types; EMPTY means "any port" / 可接受的端口用途；空表示「任意端口」
#
# Returns {"kind","node_id","port_id","pos","dir","type","bound"}. "pos" is always finite, so the
# caller can draw a preview from it without a null check. "bound" is what GPEdgeRoute reads to
# decide whether an end deserves an exit stub — a grid (dangling) end must not get one.
# 返回 {"kind","node_id","port_id","pos","dir","type","bound"}。"pos" 恒为有限值，调用方无需判空
# 即可画预览。"bound" 是 GPEdgeRoute 用来判断某端是否该有引出段的依据 —— 网格（悬空）端不该有。
static func gpSnap(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2, gpZoom: float,
		gpWantTypes: Array[String] = []) -> Dictionary:
	var gpR: float = GP_SNAP_PX / maxf(gpZoom, 0.01)
	if gpGraph == null:
		return _gpGrid(gpWorld)
	var gpBestTyped: Dictionary = {}
	var gpBestAny: Dictionary = {}
	var gpTypedD: float = gpR
	var gpAnyD: float = gpR
	for gpN in gpGraph.gpNodes:
		var gpDef: GPSymbolDef = null
		if gpDefLookup.is_valid():
			gpDef = gpDefLookup.call(gpN.gpSymbolId) as GPSymbolDef
		if gpDef == null or gpDef.gpPorts.is_empty():
			continue
		for gpP in gpDef.gpPorts:
			var gpPos: Vector2 = gpN.gpPosition + GPPortResolver.gpPortLocalOriented(gpDef, gpN, gpP)
			var gpD: float = gpPos.distance_to(gpWorld)
			if gpD > gpR:
				continue
			var gpTyped: bool = gpWantTypes.is_empty() or gpWantTypes.has(gpP.gpType)
			if gpTyped and gpD < gpTypedD:
				gpTypedD = gpD
				gpBestTyped = _gpPort(gpN, gpP, gpPos)
			if gpD < gpAnyD:
				gpAnyD = gpD
				gpBestAny = _gpPort(gpN, gpP, gpPos)
	# A type-matching port always beats a closer mismatched one: clicking an actuator while the
	# pipe tool is armed should report "wrong kind", not latch onto the wrong thing.
	# 类型匹配的端口永远胜过更近但不匹配的那个：管道工具已激活时点到执行机构，应报告「类型不符」
	# 而不是吸附到错误的东西上。
	if not gpBestTyped.is_empty():
		return gpBestTyped
	if not gpBestAny.is_empty():
		return gpBestAny
	# Legacy packs and "general" symbols have no ports; their centre is the honest answer.
	# 老符号包与 general 图元没有端口，其中心是诚实的答案。
	for gpN in gpGraph.gpNodes:
		if gpN.gpPosition.distance_to(gpWorld) <= gpR:
			return _gpNode(gpN)
	return _gpGrid(gpWorld)


# Convenience for the tools: is this snap result actually a port?
# 供工具使用的便捷判断：该吸附结果是否真的是端口？
static func gpIsPort(gpSnap: Dictionary) -> bool:
	return str(gpSnap.get("kind", "")) == GP_PORT


# ============================ private ============================

static func _gpPort(gpN: GPPIDNode, gpP: GPPort, gpPos: Vector2) -> Dictionary:
	return {
		"kind": GP_PORT,
		"node_id": gpN.gpInstanceId,
		"port_id": gpP.gpName,
		"pos": gpPos,
		"dir": GPPortResolver.gpPortDirOriented(gpN, gpP),
		"type": gpP.gpType,
		"bound": true,
	}


static func _gpNode(gpN: GPPIDNode) -> Dictionary:
	return {
		"kind": GP_NODE,
		"node_id": gpN.gpInstanceId,
		"port_id": "",
		"pos": gpN.gpPosition,
		"dir": Vector2.ZERO,
		"type": "",
		"bound": true,
	}


# Nearest grid intersection. A dangling end still lands on something aligned, which is what
# makes off-sheet continuations look drawn rather than dropped.
# 最近的网格交点。悬空端仍落在对齐的位置上，这正是「延续到他页」看起来像画出而非随手丢放的原因。
static func _gpGrid(gpWorld: Vector2) -> Dictionary:
	var gpP: Vector2 = Vector2(snappedf(gpWorld.x, GP_GRID_STEP), snappedf(gpWorld.y, GP_GRID_STEP))
	return {
		"kind": GP_GRID,
		"node_id": "",
		"port_id": "",
		"pos": gpP,
		"dir": Vector2.ZERO,
		"type": "",
		"bound": false,
	}
