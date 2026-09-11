class_name GPPortAnchor
extends RefCounted
# Copyright © 2026 Jonson Wang
# Connection anchors: the pickable endpoints a symbol exposes, plus the rules that decide
# whether two endpoints may be joined.
# 连接锚点：图元暴露的可拾取端点，以及判定两个端点能否相连的规则。
#
# Why a pure static module / 为何是纯静态模块：
#   The canvas paints the anchors, the select tool drags between them and the auto-router walks
#   from one to another. All three need EXACTLY the same answer to "where is this port?" and
#   "may these two be joined?" — putting the rules here means a drawn anchor, a dropped
#   connection and a routed path can never disagree, and every rule is headless-testable.
#   画布绘制锚点、选择工具在其间拖拽、自动布线从一个走到另一个。三者对「这个端口在哪」与
#   「这两端能否相接」需要完全一致的答案 —— 把规则放在此处，可使「画出的锚点」「落下的连线」
#   与「生成的路径」永不分歧，且每条规则都能 headless 单测。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Pick radius of an anchor in SCREEN pixels. Divided by zoom so a zoomed-out sheet stays as
# easy to hit as a zoomed-in one.
# 锚点的拾取半径（屏幕像素）。除以缩放，使缩小后的图纸与放大时一样好点中。
const GP_ANCHOR_PX: float = 10.0

# Refusal keys (machine-readable; the UI resolves them through I18n).
# 拒绝键（机器可读；界面经 I18n 解析）。
const GP_REFUSAL_NONE: String = ""
const GP_REFUSAL_SELF_LOOP: String = "edge_self_loop"
const GP_REFUSAL_BOTH_FREE: String = "pipe_needs_one_bound"
const GP_REFUSAL_TYPE: String = "port_type_mismatch"
const GP_REFUSAL_MISSING: String = "port_missing"


# ============================ 枚举 / 命中 ============================

# One anchor record: {"node_id","port_id","pos","dir","type"}.
# 单条锚点记录：{"node_id","port_id","pos","dir","type"}。
static func gpMakeAnchor(gpNodeId: String, gpPortId: String, gpPos: Vector2, gpDir: Vector2,
		gpType: String) -> Dictionary:
	return {
		"node_id": gpNodeId,
		"port_id": gpPortId,
		"pos": gpPos,
		"dir": gpDir,
		"type": gpType,
	}


# World position of one port, or Vector2.INF when the node / port cannot be resolved.
# 单个端口的世界坐标；节点或端口无法解析时返回 Vector2.INF。
static func gpPortWorldPos(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpNodeId: String,
		gpPortId: String) -> Vector2:
	if gpGraph == null or gpNodeId == "":
		return Vector2.INF
	var gpNode: GPPIDNode = gpGraph.gpGetNode(gpNodeId)
	if gpNode == null:
		return Vector2.INF
	var gpDef: GPSymbolDef = null
	if gpDefLookup.is_valid():
		gpDef = gpDefLookup.call(gpNode.gpSymbolId) as GPSymbolDef
	if gpDef == null:
		return Vector2.INF
	var gpPort: GPPort = gpDef.gpPortByName(gpPortId) if gpPortId != "" else null
	if gpPort == null:
		return Vector2.INF
	return gpNode.gpPosition + GPPortResolver.gpPortLocalOriented(gpDef, gpNode, gpPort)


# The anchor record for one (node, port), or an EMPTY dictionary when it cannot be resolved.
# 单个（节点, 端口）的锚点记录；无法解析时返回空字典。
static func gpAnchorOf(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpNodeId: String,
		gpPortId: String) -> Dictionary:
	var gpNode: GPPIDNode = gpGraph.gpGetNode(gpNodeId) if gpGraph != null else null
	if gpNode == null:
		return {}
	var gpDef: GPSymbolDef = null
	if gpDefLookup.is_valid():
		gpDef = gpDefLookup.call(gpNode.gpSymbolId) as GPSymbolDef
	if gpDef == null:
		return {}
	var gpPort: GPPort = gpDef.gpPortByName(gpPortId) if gpPortId != "" else null
	if gpPort == null:
		return {}
	return gpMakeAnchor(gpNodeId, gpPortId,
		gpNode.gpPosition + GPPortResolver.gpPortLocalOriented(gpDef, gpNode, gpPort),
		GPPortResolver.gpPortDirOriented(gpNode, gpPort), gpPort.gpType)


# Every anchor exposed by the given nodes. An EMPTY gpNodeIds means "every node on the sheet",
# which is what a connect drag needs (the target symbol need not be selected first).
# 给定节点所暴露的全部锚点。gpNodeIds 为空表示「图纸上每个节点」——连线拖拽正需要这个
# （目标图元不必先被选中）。
static func gpAnchors(gpGraph: GPPIDGraph, gpDefLookup: Callable,
		gpNodeIds: Array[String] = []) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpGraph == null:
		return gpOut
	var gpWanted: Array[String] = gpNodeIds
	for gpN in gpGraph.gpNodes:
		if not gpWanted.is_empty() and not gpWanted.has(gpN.gpInstanceId):
			continue
		var gpDef: GPSymbolDef = null
		if gpDefLookup.is_valid():
			gpDef = gpDefLookup.call(gpN.gpSymbolId) as GPSymbolDef
		if gpDef == null:
			continue
		for gpP in gpDef.gpPorts:
			gpOut.append(gpMakeAnchor(gpN.gpInstanceId, gpP.gpName,
				gpN.gpPosition + GPPortResolver.gpPortLocalOriented(gpDef, gpN, gpP),
				GPPortResolver.gpPortDirOriented(gpN, gpP), gpP.gpType))
	return gpOut


# Nearest anchor to a world point, or an EMPTY dictionary when none is within the pick radius.
# 距世界点最近的锚点；拾取半径内没有时返回空字典。
# [param gpNodeIds] restrict the search to these nodes; EMPTY = every node.
# [param gpNodeIds] 限定在这些节点内搜索；为空 = 每个节点。
static func gpHitPort(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2,
		gpZoom: float, gpNodeIds: Array[String] = []) -> Dictionary:
	var gpR: float = GP_ANCHOR_PX / maxf(gpZoom, 0.01)
	var gpBest: Dictionary = {}
	var gpBestD: float = gpR
	for gpA in gpAnchors(gpGraph, gpDefLookup, gpNodeIds):
		var gpD: float = (gpA["pos"] as Vector2).distance_to(gpWorld)
		if gpD <= gpBestD:
			gpBestD = gpD
			gpBest = gpA
	return gpBest


# Do two anchor records name the very same endpoint?
# 两条锚点记录指的是同一个端点吗？
static func gpSamePort(gpA: Dictionary, gpB: Dictionary) -> bool:
	return str(gpA.get("node_id", "")) == str(gpB.get("node_id", "")) and str(
		gpA.get("port_id", "")) == str(gpB.get("port_id", ""))


# True when a dictionary is a resolved anchor (has a node id).
# 字典是已解析的锚点（带节点 id）时为真。
static func gpIsAnchor(gpA: Dictionary) -> bool:
	return not gpA.is_empty() and str(gpA.get("node_id", "")) != ""


# ============================ 连接合法性 ============================

# What a port purpose WANTS: "pipe", "signal" or "any" (TERMINAL accepts either).
# 端口用途「想要」什么："pipe"、"signal" 或 "any"（TERMINAL 两者皆可）。
static func gpWishFor(gpType: String) -> String:
	match gpType:
		GPPort.GP_NOZZLE:
			return "pipe"
		GPPort.GP_ACTUATOR, GPPort.GP_SIGNAL:
			return "signal"
		_:
			# TERMINAL and any future purpose accept either kind of line.
			# TERMINAL 及今后新增的用途都接受两类线。
			return "any"


# The edge kind two port purposes imply, or "" when the pair is ILLEGAL.
# 两个端口用途所隐含的连线类型；该配对非法时返回 ""。
# A process nozzle and a valve actuator cannot be joined: the snap resolver deliberately offers
# the wrong-typed port so the UI can SAY why instead of silently snapping to nothing.
# 工艺管口与阀门执行机构不能相接：吸附解析器刻意提供类型不符的端口，好让界面能「说出原因」
# 而不是静默地什么都不吸。
static func gpConnectKindFor(gpTypeA: String, gpTypeB: String) -> String:
	var gpWa: String = gpWishFor(gpTypeA)
	var gpWb: String = gpWishFor(gpTypeB)
	# Both ends agree on a kind. / 两端对类型意见一致。
	if gpWa == gpWb:
		if gpWa == "pipe":
			return GPPIDEdge.GP_PROCESS
		if gpWa == "signal":
			return GPPIDEdge.GP_SIGNAL
		# Both are "any" (TERMINAL <-> TERMINAL): a pipe is the honest default.
		# 两端都是 "any"（TERMINAL 对 TERMINAL）：管道是最诚实的默认。
		return GPPIDEdge.GP_PROCESS
	# One end is undecided: follow the end that has an opinion.
	# 一端无偏好：听有意见的那一端。
	if gpWa == "any":
		return GPPIDEdge.GP_SIGNAL if gpWb == "signal" else GPPIDEdge.GP_PROCESS
	if gpWb == "any":
		return GPPIDEdge.GP_SIGNAL if gpWa == "signal" else GPPIDEdge.GP_PROCESS
	# One wants a pipe, the other a signal line: illegal.
	# 一端要管道、另一端要信号线：非法。
	return ""


# Validate a pair of anchors. Returns "" when they may be joined, otherwise a refusal key.
# 校验一对锚点。可连接时返回 ""，否则返回拒绝键。
static func gpValidatePair(gpA: Dictionary, gpB: Dictionary) -> String:
	if not gpIsAnchor(gpA) or not gpIsAnchor(gpB):
		return GP_REFUSAL_BOTH_FREE
	if gpSamePort(gpA, gpB):
		return GP_REFUSAL_SELF_LOOP
	if gpConnectKindFor(str(gpA.get("type", "")), str(gpB.get("type", ""))) == "":
		return GP_REFUSAL_TYPE
	return GP_REFUSAL_NONE
