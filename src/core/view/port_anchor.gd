class_name GPPortAnchor
extends RefCounted
# Copyright © 2026 Jonson Wang
# Connection anchors: the pickable endpoints a symbol exposes, plus the rules that decide
# whether two endpoints may be joined.
# 连接锚点：图元暴露的可拾取端点，以及判定两个端点能否相连的规则。
#
# Why a pure static module / 为何是纯静态模块：
# The canvas paints the anchors, the select tool drags between them and the auto-router walks
# from one to another. All three need EXACTLY the same answer to "where is this port?" and
# "may these two be joined?" — putting the rules here means a drawn anchor, a dropped
# connection and a routed path can never disagree, and every rule is headless-testable.
# 画布绘制锚点、选择工具在其间拖拽、自动布线从一个走到另一个。三者对「这个端口在哪」与
# 「这两端能否相接」需要完全一致的答案 —— 把规则放在此处，可使「画出的锚点」「落下的连线」
# 与「生成的路径」永不分歧，且每条规则都能 headless 单测。
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
	# Going through GPPortResolver.gpPortWorld() (instead of adding the node position here) is
	# what folds a MOUNTED child's host chain into the port position.
	# 经由 GPPortResolver.gpPortWorld()（而非在此处加节点坐标）才能把挂载子件的宿主父链折进端口位置。
	return GPPortResolver.gpPortWorld(gpGraph, gpDefLookup, gpDef, gpNode, gpPort)


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
		GPPortResolver.gpPortWorld(gpGraph, gpDefLookup, gpDef, gpNode, gpPort),
		GPPortResolver.gpPortWorldDir(gpGraph, gpDefLookup, gpNode, gpPort), gpPort.gpType)


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
	# Dedupe by (node, port): a host that has yielded to its nozzles contributes THEIR ports, and
	# those same ports are contributed again by the nozzle nodes themselves when the caller asks for
	# every node — without this the sheet would show two overlapping anchors at each nozzle tip.
	# 按 (节点, 端口) 去重：已让位于管嘴的宿主贡献的是**管嘴的**端口，而调用方索取「每个节点」时
	# 管嘴节点自身又会贡献同一批端口 —— 少了这一步，图纸上每个管嘴端会出现两个重叠锚点。
	var gpSeen: Dictionary = {}
	for gpN in gpGraph.gpNodes:
		if not gpWanted.is_empty() and not gpWanted.has(gpN.gpInstanceId):
			continue
		# gpServingPorts() answers with the ports that ACTUALLY carry this node's connections:
		# its own, or its mounted nozzles' when those have taken over (see GPMountResolver).
		# gpServingPorts() 返回**真正**承载该节点连接关系的端口：自身端口，或接管之后的管嘴端口
		#（见 GPMountResolver）。
		for gpS in GPMountResolver.gpServingPorts(gpGraph, gpDefLookup, gpN):
			var gpSN: GPPIDNode = gpS["node"]
			var gpSP: GPPort = gpS["port"]
			var gpSDef: GPSymbolDef = gpS["def"]
			var gpKey: String = gpSN.gpInstanceId + "|" + gpSP.gpName
			if gpSeen.has(gpKey):
				continue
			gpSeen[gpKey] = true
			gpOut.append(gpMakeAnchor(gpSN.gpInstanceId, gpSP.gpName,
				GPPortResolver.gpPortWorld(gpGraph, gpDefLookup, gpSDef, gpSN, gpSP),
				GPPortResolver.gpPortWorldDir(gpGraph, gpDefLookup, gpSN, gpSP), gpSP.gpType))
	return gpOut


# Nearest anchor to a world point, or an EMPTY dictionary when none is within the pick radius.
# 距世界点最近的锚点；拾取半径内没有时返回空字典。
# [param gpNodeIds] restrict the search() to these nodes; EMPTY = every node.
# [param gpNodeIds] 限定在这些节点内搜索；为空 = 每个节点。
#
# BODY WINS WHEN THE ANCHORS BELONG TO THE SELECTION / 锚点属于选择集时**本体取胜**：
# Restricting the search to the selected symbols means the user was aiming at one of them, and may
# equally have meant the symbol itself. A nozzle is 4 mm long with a port at EACH tip, so the 10 px
# pick radius covers its entire body and the part could never be grabbed — the reported "the
# built-in parts cannot be dragged". The anchor therefore only wins when the press is CLOSER TO THE
# ANCHOR than to the centre of the node that owns it: pressing a tip snaps the tip, pressing the
# body grabs the part. The rule is scale-free, so a 10 mm valve keeps behaving exactly as before.
# When gpNodeIds is EMPTY the search serves a wire looking for a landing point on ANY symbol, and
# there the nearest port is simply the answer — no body-wins test applies.
# 把搜索限定在选中图元上，意味着用户瞄的就是其中之一，也可能瞄的是图元本身。管嘴长 4mm、**两端**
# 各有一个端口，故 10px 拾取半径盖住它整个身子，部件便永远抓不住 —— 即用户报告的「自带部件拖不动」。
# 因此锚点仅在「按下点离锚点比离其所属节点中心更近」时才取胜：按端头就是按端头，按身子就是抓部件。
# 该规则与尺寸无关，故 10mm 的阀门行为与之前**完全**一致。当 gpNodeIds 为空时，搜索是在为一条
# 连线寻找落点，最近的端口就是答案，不适用「本体取胜」。
static func gpHitPort(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2,
		gpZoom: float, gpNodeIds: Array[String] = []) -> Dictionary:
	var gpR: float = GP_ANCHOR_PX / maxf(gpZoom, 0.01)
	var gpBest: Dictionary = {}
	var gpBestD: float = gpR
	var gpSelOnly: bool = not gpNodeIds.is_empty()
	for gpA in gpAnchors(gpGraph, gpDefLookup, gpNodeIds):
		var gpD: float = (gpA["pos"] as Vector2).distance_to(gpWorld)
		if gpD > gpBestD:
			continue
		if gpSelOnly and gpD >= _gpCentreDistance(gpGraph, gpDefLookup, gpA, gpWorld):
			continue
		gpBestD = gpD
		gpBest = gpA
	return gpBest


# Distance from a world point to the derived centre of the node an anchor belongs to. INF when the
# node cannot be resolved, so the body-wins test above never rejects on a missing node (INF compares
# as "far", leaving the anchor in charge).
# 世界点到锚点所属节点**推导**中心的距离。节点无法解析时为 INF，使上方的「本体取胜」判定绝不会因
# 节点缺失而拒绝（INF 视为「远」，仍由锚点取胜）。
static func _gpCentreDistance(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpAnchor: Dictionary,
		gpWorld: Vector2) -> float:
	if gpGraph == null:
		return INF
	var gpNode: GPPIDNode = gpGraph.gpGetNode(str(gpAnchor.get("node_id", "")))
	if gpNode == null:
		return INF
	return GPPortResolver.gpNodeWorldOrigin(gpGraph, gpDefLookup, gpNode).distance_to(gpWorld)


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
