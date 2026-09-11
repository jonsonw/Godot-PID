class_name GPPortResolver
extends RefCounted
# Copyright © 2026 Jonson Wang
# The ONLY place that turns (node, port name) into a world position + outward normal.
# 把「节点 + 端口名」换算为世界坐标与向外法线的唯一场所。
#
# Why one owner / 为何唯一持有者：
#   GPSymbolView draws the port dots and GPEdgeView draws the pipe ends. If each did its own
#   rotation / flip math they would drift apart the moment one of them was fixed. Both now
#   call in here, so the dot and the pipe end can never disagree.
#   GPSymbolView 画端口圆点、GPEdgeView 画管线端点。若各算一遍旋转/翻转，任一处被修正时两者
#   立刻分家。现在两者都调本类，故「圆点与管线端点」永不分歧。
#
# Fault tolerance is the CONTRACT, not exactness / 契约是容错而非精确：
#   GPConnectCommand's original note said edges must never store a port name so that editing a
#   symbol's ports cannot silently break a connection. This resolver keeps that promise a
#   different way: port_id is a HINT, and resolution degrades in three steps instead of failing.
#   GPConnectCommand 原注释称边不应存端口名，以免编辑端口静默断连。本解析器以另一种方式守住
#   该承诺：port_id 只是「提示」，解析按阶梯降级，绝不失败。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


# Local (node-centered) offset of a port WITH the instance's flip and rotation applied.
# 端口相对节点中心的本地偏移，已应用实例的翻转与旋转。
# Order matters: mirror first (in the symbol's own frame), then rotate — the same order the
# renderer must use, otherwise a flipped-and-rotated valve's ports land on the wrong side.
# 顺序要紧：先镜像（在图元自身坐标系内），再旋转 —— 渲染器必须用同一顺序，否则「先翻转再旋转」
# 的阀门端口会跑到错误一侧。
static func gpPortLocalOriented(gpDef: GPSymbolDef, gpNode: GPPIDNode, gpPort: GPPort) -> Vector2:
	if gpDef == null or gpNode == null or gpPort == null:
		return Vector2.ZERO
	var gpL: Vector2 = gpDef.gpPortLocal(gpPort)
	if gpNode.gpFlipped:
		gpL.x = -gpL.x
	if not is_zero_approx(gpNode.gpRotationDeg):
		gpL = gpL.rotated(deg_to_rad(gpNode.gpRotationDeg))
	return gpL


# Outward normal of a port in world direction (unit length, or ZERO when the port declares none).
# 端口向外法线的世界方向（单位长度；端口未声明法线时为零向量）。
static func gpPortDirOriented(gpNode: GPPIDNode, gpPort: GPPort) -> Vector2:
	if gpNode == null or gpPort == null:
		return Vector2.ZERO
	var gpD: Vector2 = gpPort.gpDir
	if gpD == Vector2.ZERO:
		return Vector2.ZERO
	if gpNode.gpFlipped:
		gpD.x = -gpD.x
	if not is_zero_approx(gpNode.gpRotationDeg):
		gpD = gpD.rotated(deg_to_rad(gpNode.gpRotationDeg))
	return gpD.normalized()


# Resolve one edge end into {"pos": Vector2, "dir": Vector2, "bound": bool, "why": String}.
# 把一条边的一端解析为 {"pos", "dir", "bound", "why"}。
#
# NEVER returns Vector2.INF: an unresolvable end still gets a drawable position, so a bad port
# name degrades the look of one pipe instead of making it vanish.
# 绝不返回 Vector2.INF：无法解析的端点仍得到可绘制位置，故错误的端口名只是让某条管线外观降级，
# 而不会让它消失。
#
# Degradation ladder / 降级阶梯：
#   1. "port"    exact port_id hit                                精确命中 port_id
#   2. "typed"   port_id missing/renamed -> first port of the wanted type
#                端口 id 缺失或被改名 -> 期望用途的首个端口
#   3. "center"  no ports at all (legacy pack / general symbol)    完全无端口（老包 / general 图元）
#   4. "free"    dangling end -> the stored point                  悬空端 -> 已存点
#   5. "free"    node id points at a node that no longer exists    节点 id 指向已不存在的节点
static func gpResolveEnd(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpEdge: GPPIDEdge,
		gpIsFrom: bool, gpWantType: String = "") -> Dictionary:
	if gpEdge == null:
		return {"pos": Vector2.ZERO, "dir": Vector2.ZERO, "bound": false, "why": "free"}
	var gpRef: Dictionary = gpEdge.gpFromRef if gpIsFrom else gpEdge.gpToRef
	var gpNodeId: String = str(gpRef.get("node_id", ""))
	# 4. Dangling end. / 悬空端。
	if gpNodeId == "":
		var gpFree: Vector2 = gpEdge.gpDanglingPoint(gpIsFrom)
		if gpFree == Vector2.INF:
			gpFree = Vector2.ZERO
		return {"pos": gpFree, "dir": Vector2.ZERO, "bound": false, "why": "free"}
	if gpGraph == null:
		return {"pos": Vector2.ZERO, "dir": Vector2.ZERO, "bound": false, "why": "free"}
	var gpNode: GPPIDNode = gpGraph.gpGetNode(gpNodeId)
	# 5. Node vanished (deleted without cleaning the edge). / 节点已消失（删节点时未清理边）。
	if gpNode == null:
		return {"pos": Vector2.ZERO, "dir": Vector2.ZERO, "bound": false, "why": "free"}
	var gpDef: GPSymbolDef = null
	if gpDefLookup.is_valid():
		gpDef = gpDefLookup.call(gpNode.gpSymbolId) as GPSymbolDef
	# 3. No definition or no ports. / 无定义或无端口。
	if gpDef == null or gpDef.gpPorts.is_empty():
		return {"pos": gpNode.gpPosition, "dir": Vector2.ZERO, "bound": true, "why": "center"}
	# 1. Exact port hit. / 精确命中端口。
	var gpPortId: String = str(gpRef.get("port_id", ""))
	var gpPort: GPPort = gpDef.gpPortByName(gpPortId) if gpPortId != "" else null
	var gpWhy: String = "port"
	# 2. Fall back to the first port of the wanted purpose. / 退化为期望用途的首个端口。
	if gpPort == null:
		var gpCands: Array[GPPort] = gpDef.gpPortsOfType(gpWantType) if gpWantType != "" else gpDef.gpPorts
		if gpCands.is_empty():
			return {"pos": gpNode.gpPosition, "dir": Vector2.ZERO, "bound": true, "why": "center"}
		gpPort = gpCands[0]
		gpWhy = "typed"
	return {
		"pos": gpNode.gpPosition + gpPortLocalOriented(gpDef, gpNode, gpPort),
		"dir": gpPortDirOriented(gpNode, gpPort),
		"bound": true,
		"why": gpWhy,
	}


# The port purpose an edge wants at its ends (used as gpWantType above).
# 一条边在其端点所期望的端口用途（用作上面的 gpWantType）。
static func gpWantTypeFor(gpEdge: GPPIDEdge) -> String:
	if gpEdge == null:
		return GPPort.GP_NOZZLE
	return GPPort.GP_SIGNAL if gpEdge.gpKind == GPPIDEdge.GP_SIGNAL else GPPort.GP_NOZZLE


# Resolve an end into the ref the resolver would actually draw from: a port-bound ref when the
# end lands on a node that has ports, otherwise the original ref (centre / dangling). Used by the
# "re-snap ends" command to upgrade legacy centre lines to real port lines, and it is undoable
# because it only rewrites port_id (never the geometry the resolver computes live).
# 把一端解析为「解析器实际依之绘制」的引用：当端落到含端口的节点上时返回端口绑定引用，
# 否则返回原引用（中心 / 悬空）。供「重新吸附端点」命令把老档中心连线升级为真实端口连线，
# 且可撤销 —— 它只改写 port_id，绝不改动解析器实时计算的几何。
static func gpSnapRef(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpEdge: GPPIDEdge,
		gpIsFrom: bool) -> Dictionary:
	var gpRef: Dictionary = gpEdge.gpFromRef if gpIsFrom else gpEdge.gpToRef
	var gpNodeId: String = str(gpRef.get("node_id", ""))
	if gpNodeId == "":
		return gpRef.duplicate()
	if gpGraph == null:
		return gpRef.duplicate()
	var gpNode: GPPIDNode = gpGraph.gpGetNode(gpNodeId)
	if gpNode == null:
		return gpRef.duplicate()
	var gpDef: GPSymbolDef = null
	if gpDefLookup.is_valid():
		gpDef = gpDefLookup.call(gpNode.gpSymbolId) as GPSymbolDef
	if gpDef == null or gpDef.gpPorts.is_empty():
		return gpRef.duplicate()
	# Prefer an already-named, still-existing port. / 优先用已命名且仍存在的端口。
	var gpPortId: String = str(gpRef.get("port_id", ""))
	if gpPortId != "" and gpDef.gpPortByName(gpPortId) != null:
		return {"node_id": gpNodeId, "port_id": gpPortId}
	# Otherwise the first port of the wanted purpose (matches the live resolver ladder).
	# 否则取期望用途的首个端口（与实时解析器阶梯一致）。
	var gpWant: String = gpWantTypeFor(gpEdge)
	var gpCands: Array[GPPort] = gpDef.gpPortsOfType(gpWant) if gpWant != "" else gpDef.gpPorts
	var gpPick: GPPort = null
	if not gpCands.is_empty():
		gpPick = gpCands[0]
	elif not gpDef.gpPorts.is_empty():
		gpPick = gpDef.gpPorts[0]
	if gpPick == null:
		return gpRef.duplicate()
	return {"node_id": gpNodeId, "port_id": gpPick.gpName}
