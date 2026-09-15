class_name GPSnapResolver
extends RefCounted
# Copyright © 2026 Jonson Wang
# The ONLY place that turns a raw world click into "what did the user mean to connect to?".
# 把一次原始世界点击换算为「用户想连到哪里」的唯一场所。
#
# Why a pure static module / 为何是纯静态模块：
#   Both the pipe tool and the signal tool need the same answer, and the answer must be
#   testable without a canvas: given a graph and a point, which feature (if any) is meant?
#   Putting this in a tool would force a fake canvas into the test; here it is a pure function
#   of the graph + the snap state passed IN by the caller.
#   管道工具与信号线工具需要同一个答案，且该答案必须无需画布即可测试：给定图与点，指的是哪个
#   特征？若放进工具里，测试就得伪造画布；放在此处则是图与「传入的捕捉状态」的纯函数。
#
# Snap state is passed IN, never read from the global SnapState autoload — keeping core free of
# any autoload dependency is a hard architectural constraint. The pipe tool maps
# SnapState.GP_SNAP_TYPE onto the GP_KIND_* constants below (a 1:1 correspondence).
# 捕捉状态一律由调用方「传入」，绝不读取全局 SnapState autoload —— core 层无任何 autoload 依赖是
# 硬约束。管道工具把 SnapState.GP_SNAP_TYPE 映射到下方的 GP_KIND_* 常量（一一对应）。
#
# The priority ladder (ENDPOINT mode) is deliberate / 优先级阶梯（ENDPOINT 模式）是刻意设计的：
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
const GP_FREE: String = "free"  # snapping disabled: raw click point / 捕捉关闭：原始点击点
const GP_MID: String = "mid"  # midpoint of an existing edge / 已有边的中点
const GP_PERP: String = "perp"  # perpendicular foot on an edge segment / 边线段上的垂足
const GP_INTER: String = "inter"  # intersection of two edges / 两条边的交点

# Snap feature kinds (mirror SnapState.GP_SNAP_TYPE 1:1; the pipe tool maps the autoload enum
# onto these so the resolver never reads the global).
# 捕捉特征种类（与 SnapState.GP_SNAP_TYPE 一一对应；管道工具把 autoload 枚举映射到此处，
# 解析器永不读取全局）。
const GP_KIND_ENDPOINT: int = 0
const GP_KIND_MIDPOINT: int = 1
const GP_KIND_INTERSECTION: int = 2
const GP_KIND_PERPENDICULAR: int = 3


# Resolve a world click into a snap target.
# 把一次世界点击解析为吸附目标。
#
# [param gpGraph] the topology to search / 待搜索的拓扑图
# [param gpDefLookup] symbol-id -> GPSymbolDef (may be invalid) / 符号 id -> 定义（可为无效 Callable）
# [param gpWorld] the click in world coordinates / 点击的世界坐标
# [param gpZoom] current view zoom (radius is screen-relative) / 当前缩放（半径为屏幕相对）
# [param gpWantTypes] accepted GPPort types; EMPTY means "any port" / 可接受的端口用途；空表示「任意端口」
# [param gpSnapOn] when false, returns the raw click (no snapping) / 关闭时返回原始点击（不吸附）
# [param gpSnapKind] GP_KIND_* feature to snap to / 要吸附的特征种类
#
# Returns {"kind","node_id","port_id","pos","dir","type","bound",(edge_id)}. "pos" is always
# finite, so the caller can draw a preview from it without a null check. "bound" is what
# GPEdgeRoute reads to decide whether an end deserves an exit stub — a grid (dangling) end must
# not get one.
# 返回 {"kind","node_id","port_id","pos","dir","type","bound",(edge_id)}。"pos" 恒为有限值，调用方无需
# 判空即可画预览。"bound" 是 GPEdgeRoute 用来判断某端是否该有引出段的依据 —— 网格（悬空）端不该有。
static func gpSnap(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2, gpZoom: float,
		gpWantTypes: Array[String] = [], gpSnapOn: bool = true,
		gpSnapKind: int = GP_KIND_ENDPOINT) -> Dictionary:
	var gpR: float = GP_SNAP_PX / maxf(gpZoom, 0.01)
	# Snap disabled: the click IS the answer. Keeps the tool honest — a toggled-off snap must
	# never silently pull the point onto a port or the grid.
	# 捕捉关闭：点击即答案。保持工具诚实 —— 关闭的吸附绝不可静默把点拉到端口或网格上。
	if not gpSnapOn:
		return _gpFree(gpWorld)
	match gpSnapKind:
		GP_KIND_MIDPOINT:
			return _gpSnapMidpoint(gpGraph, gpDefLookup, gpWorld, gpR)
		GP_KIND_PERPENDICULAR:
			return _gpSnapPerp(gpGraph, gpDefLookup, gpWorld, gpR)
		GP_KIND_INTERSECTION:
			return _gpSnapIntersection(gpGraph, gpDefLookup, gpWorld, gpR)
		_:  # ENDPOINT (default) / 端点（默认）
			return _gpSnapEndpoint(gpGraph, gpDefLookup, gpWorld, gpWantTypes, gpR)


# ============================ endpoint snapping (original ladder) ============================
# ============================ 端点吸附（原优先级阶梯） ============================

static func _gpSnapEndpoint(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2,
		gpWantTypes: Array[String], gpR: float) -> Dictionary:
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


# ============================ feature snapping (CAD modes) ============================
# ============================ 特征吸附（CAD 模式） ============================

# Snap to the midpoint of the NEAREST existing edge. A take-off point for tapping a live line.
# 吸附到「最近已有边」的中点。用作从在用管线上接出支管的接管点。
static func _gpSnapMidpoint(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2,
		gpR: float) -> Dictionary:
	var gpBest: Dictionary = {}
	var gpBestD: float = gpR
	if gpGraph != null:
		for gpE in gpGraph.gpEdges:
			var gpPoly: PackedVector2Array = _gpEdgePolyline(gpGraph, gpDefLookup, gpE)
			if gpPoly.size() < 2:
				continue
			var gpN: int = gpPoly.size()
			var gpMid: Vector2 = Vector2.ZERO
			if gpN % 2 == 1:
				gpMid = gpPoly[int(gpN / 2)]
			else:
				gpMid = (gpPoly[int(gpN / 2) - 1] + gpPoly[int(gpN / 2)]) * 0.5
			var gpD: float = gpMid.distance_to(gpWorld)
			if gpD < gpBestD:
				gpBestD = gpD
				gpBest = {"kind": GP_MID, "node_id": "", "port_id": "", "pos": gpMid,
					"dir": Vector2.ZERO, "type": "", "bound": false, "edge_id": gpE.gpInstanceId}
	if not gpBest.is_empty():
		return gpBest
	return _gpGrid(gpWorld)


# Snap to the nearest perpendicular foot on ANY edge segment.
# 吸附到「任意边线段」上最近的垂足。
static func _gpSnapPerp(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2,
		gpR: float) -> Dictionary:
	var gpBest: Dictionary = {}
	var gpBestD: float = gpR
	if gpGraph != null:
		for gpE in gpGraph.gpEdges:
			var gpPoly: PackedVector2Array = _gpEdgePolyline(gpGraph, gpDefLookup, gpE)
			for gpI in range(gpPoly.size() - 1):
				var gpA: Vector2 = gpPoly[gpI]
				var gpB: Vector2 = gpPoly[gpI + 1]
				var gpFoot: Vector2 = _gpClosestOnSeg(gpWorld, gpA, gpB)
				var gpD: float = gpFoot.distance_to(gpWorld)
				if gpD < gpBestD:
					gpBestD = gpD
					gpBest = {"kind": GP_PERP, "node_id": "", "port_id": "", "pos": gpFoot,
						"dir": Vector2.ZERO, "type": "", "bound": false, "edge_id": gpE.gpInstanceId}
	if not gpBest.is_empty():
		return gpBest
	return _gpGrid(gpWorld)


# Snap to the nearest intersection of TWO edges.
# 吸附到「两条边」的交点中最接近的一个。
static func _gpSnapIntersection(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2,
		gpR: float) -> Dictionary:
	var gpEdges: Array = []
	if gpGraph != null:
		gpEdges = gpGraph.gpEdges
	var gpBest: Dictionary = {}
	var gpBestD: float = gpR
	for gpI in range(gpEdges.size()):
		var gpP1: PackedVector2Array = _gpEdgePolyline(gpGraph, gpDefLookup, gpEdges[gpI])
		for gpJ in range(gpI + 1, gpEdges.size()):
			var gpP2: PackedVector2Array = _gpEdgePolyline(gpGraph, gpDefLookup, gpEdges[gpJ])
			for gpA in range(gpP1.size() - 1):
				for gpB in range(gpP2.size() - 1):
					var gpPt: Vector2 = _gpSegIntersect(gpP1[gpA], gpP1[gpA + 1], gpP2[gpB], gpP2[gpB + 1])
					if gpPt == Vector2.INF:
						continue
					var gpD: float = gpPt.distance_to(gpWorld)
					if gpD < gpBestD:
						gpBestD = gpD
						gpBest = {"kind": GP_INTER, "node_id": "", "port_id": "", "pos": gpPt,
							"dir": Vector2.ZERO, "type": "", "bound": false}
	if not gpBest.is_empty():
		return gpBest
	return _gpGrid(gpWorld)


# ============================ geometry helpers ============================

# World-space polyline of one edge, recomputed from its port refs + routing (never cached, so it
# always reflects the live symbol positions).
# 一条边的世界坐标折线：依端口引用 + 中间折点实时重算（不缓存，恒反映图元当前位置）。
static func _gpEdgePolyline(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpEdge: GPPIDEdge) -> PackedVector2Array:
	if gpEdge == null:
		return PackedVector2Array()
	var gpFrom: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpDefLookup, gpEdge, true, "")
	var gpTo: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpDefLookup, gpEdge, false, "")
	return GPEdgeRoute.gpRoute(gpFrom, gpTo, gpEdge.gpRouting, gpEdge.gpOrtho)


# Closest point on segment AB to P (clamped to the segment).
# 线段 AB 上离 P 最近的点（夹在段内）。
static func _gpClosestOnSeg(gpP: Vector2, gpA: Vector2, gpB: Vector2) -> Vector2:
	var gpAB: Vector2 = gpB - gpA
	var gpLen2: float = gpAB.length_squared()
	if gpLen2 < 1e-9:
		return gpA
	var gpT: float = (gpP - gpA).dot(gpAB) / gpLen2
	gpT = clampf(gpT, 0.0, 1.0)
	return gpA + gpAB * gpT


# Intersection point of segments A1A2 and B1B2, or Vector2.INF when they don't cross inside
# both segments (parallel / outside).
# 线段 A1A2 与 B1B2 的交点；若不在线段内相交（平行 / 越界）则返回 Vector2.INF。
static func _gpSegIntersect(gpA1: Vector2, gpA2: Vector2, gpB1: Vector2, gpB2: Vector2) -> Vector2:
	var gpR1: Vector2 = gpA2 - gpA1
	var gpS1: Vector2 = gpB2 - gpB1
	var gpDenom: float = gpR1.x * gpS1.y - gpR1.y * gpS1.x
	if absf(gpDenom) < 1e-9:
		return Vector2.INF  # parallel / collinear / 平行或共线
	var gpT: float = ((gpB1.x - gpA1.x) * gpS1.y - (gpB1.y - gpA1.y) * gpS1.x) / gpDenom
	var gpU: float = ((gpB1.x - gpA1.x) * gpR1.y - (gpB1.y - gpA1.y) * gpR1.x) / gpDenom
	if gpT < 0.0 or gpT > 1.0 or gpU < 0.0 or gpU > 1.0:
		return Vector2.INF
	return gpA1 + gpR1 * gpT


# ============================ result builders ============================

# True when the snap result is a real port (used by the overlay to highlight a port end vs a
# grid/node end). Pure string check on the "kind" field, so it never depends on the call site.
# 当吸附结果是真实端口时为 true（覆盖层用它区分「高亮端口端」与「网格 / 节点端」）。对 kind 字段做纯
# 字符串判定，不依赖调用方上下文。
static func gpIsPort(gpSnap: Dictionary) -> bool:
	return str(gpSnap.get("kind", "")) == GP_PORT


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


# A click with snapping disabled — never pulled onto a port or the grid.
# 关闭捕捉时的点击：绝不拉到端口或网格上。
static func _gpFree(gpWorld: Vector2) -> Dictionary:
	return {
		"kind": GP_FREE,
		"node_id": "",
		"port_id": "",
		"pos": gpWorld,
		"dir": Vector2.ZERO,
		"type": "",
		"bound": false,
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
