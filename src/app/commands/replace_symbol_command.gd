class_name GPReplaceSymbolCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Swap one instance onto a different SymbolDef (M10) — "change the symbol, keep the identity".
# 把某个实例换到另一个 SymbolDef 上（M10）—— 「换图元，不换身份」。
#
# What is preserved / 保留什么：
#   gpUid, gpTag, gpProps and the node's position all survive untouched. That is the whole
#   point: a pump that becomes a different pump model keeps its tag P-1001, its property
#   values and — critically — every pipe still lands on it, because edges reference the node
#   id, never the symbol.
#   gpUid、gpTag、gpProps 与节点坐标全部原样保留。这正是重点：把一台泵换成另一型号，
#   它的位号 P-1001、属性值都还在 —— 关键是每根管子都还连着它，因为边引用的是
#   **节点 id**，从来不是图元。
#
# Port reconciliation / 端口对账（已拍板 2026-09-09：允许降级但警告）：
#   An edge stores the port NAME as a hint, not as a contract. When the new symbol has no
#   port of that name, the endpoint DOWNGRADES to the node centre instead of being severed —
#   the pipe stays connected and merely looks less precise. Blocking the swap would force
#   the user to delete and redraw; silently re-pointing it would hide the change. So the
#   downgraded edge ids are recorded in gpDowngraded() and the shell shows a warning.
#   边把端口**名**存为「提示」而非「契约」。新图元没有同名端口时，端点**降级**到图元中心
#   而非被切断 —— 管路保持连通，只是外观没那么精确。拦死更换会逼用户删了重画；静默改指
#   则会掩盖这次变动。故被降级的边 id 记录在 gpDowngraded() 中，由外壳给出警告。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Node whose symbol is swapped. / 被更换图元的节点。
var _gpNodeId: String = ""

# The symbol to swap onto. Captured at construction: the command is a value object and must
# never reach back into the library at undo time (the library may have changed since).
# 换入的图元。构造时捕获：命令是值对象，撤销时绝不回查图元库（库此后可能已变更）。
var _gpNewDef: GPSymbolDef = null

# Symbol id before the swap, for undo. / 更换前的图元 id，供撤销。
var _gpOldSymbolId: String = ""

# One row per edge end that touches this node:
# {"edge_id": String, "is_from": bool, "old_port": String}
# 每个接到本节点的边端点一行：{"edge_id", "is_from", "old_port"}
var _gpSnap: Array[Dictionary] = []

# Edge ids whose endpoint was downgraded to the node centre (for the shell's warning).
# 端点被降级到图元中心的边 id（供外壳告警）。
var _gpDowngraded: Array[String] = []


func _init(gpInNodeId: String, gpInNewDef: GPSymbolDef) -> void:
	_gpNodeId = gpInNodeId
	_gpNewDef = gpInNewDef
	gpLabel = "更换图元"


# Edges downgraded by the last gpExecute / gpRedo. Empty when every port matched.
# 最近一次 gpExecute / gpRedo 中被降级的边。端口全部匹配时为空。
func gpDowngraded() -> Array[String]:
	return _gpDowngraded.duplicate()


# Apply the swap. Returns false when the node is gone or the symbol is already the target,
# so a re-selection of the same symbol produces no phantom undo step.
# 执行更换。节点不存在或图元已是目标图元时返回 false，
# 使「又选了一次同一图元」不产生幽灵撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null or _gpNewDef == null:
		return false
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return false
	if gpN.gpSymbolId == _gpNewDef.gpId:
		return false
	_gpOldSymbolId = gpN.gpSymbolId
	_gpSnap = _gpCaptureRefs(gpCtx.gpGraph)
	gpN.gpSymbolId = _gpNewDef.gpId
	_gpDowngraded = []
	_gpDowngradeMissingPorts(gpCtx.gpGraph)
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return
	gpN.gpSymbolId = _gpOldSymbolId
	_gpRestoreRefs(gpCtx.gpGraph)
	_gpDowngraded = []
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpNewDef == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return
	gpN.gpSymbolId = _gpNewDef.gpId
	_gpDowngraded = []
	_gpDowngradeMissingPorts(gpCtx.gpGraph)
	gpCtx.gpGraph.gpGraphChanged.emit()


# Record the port name on every edge end bound to this node, so undo can restore it exactly.
# Dangling ends (a "point", no node_id) are not touched — they hold no port reference.
# 记录绑定在本节点上的每个边端点的端口名，供撤销精确还原。
# 悬空端（只有 "point"、无 node_id）不受影响 —— 它不含端口引用。
func _gpCaptureRefs(gpGraph: GPPIDGraph) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpGraph == null:
		return gpOut
	for gpE in gpGraph.gpEdges:
		if gpE == null:
			continue
		if str(gpE.gpFromRef.get("node_id", "")) == _gpNodeId:
			gpOut.append({"edge_id": gpE.gpInstanceId, "is_from": true,
				"old_port": str(gpE.gpFromRef.get("port_id", ""))})
		if str(gpE.gpToRef.get("node_id", "")) == _gpNodeId:
			gpOut.append({"edge_id": gpE.gpInstanceId, "is_from": false,
				"old_port": str(gpE.gpToRef.get("port_id", ""))})
	return gpOut


# Clear the port name wherever the NEW symbol has no matching port: GPPortResolver then
# degrades that end to the node centre, keeping the connection alive.
# 凡新图元没有同名端口处，清空端口名：GPPortResolver 随后把该端降级到图元中心，
# 连接依然成立。
func _gpDowngradeMissingPorts(gpGraph: GPPIDGraph) -> void:
	if gpGraph == null or _gpNewDef == null:
		return
	for gpRow in _gpSnap:
		var gpOld: String = str(gpRow["old_port"])
		if gpOld == "":
			continue
		if _gpNewDef.gpPortByName(gpOld) != null:
			continue
		var gpE: GPPIDEdge = gpGraph.gpGetEdge(str(gpRow["edge_id"]))
		if gpE == null:
			continue
		var gpRef: Dictionary = gpE.gpFromRef if bool(gpRow["is_from"]) else gpE.gpToRef
		gpRef["port_id"] = ""
		if not _gpDowngraded.has(gpE.gpInstanceId):
			_gpDowngraded.append(gpE.gpInstanceId)


# Put every captured port name back, in the exact shape it had before the swap.
# 把每个捕获到的端口名按更换前的确切形状还原回去。
func _gpRestoreRefs(gpGraph: GPPIDGraph) -> void:
	if gpGraph == null:
		return
	for gpRow in _gpSnap:
		var gpE: GPPIDEdge = gpGraph.gpGetEdge(str(gpRow["edge_id"]))
		if gpE == null:
			continue
		var gpRef: Dictionary = gpE.gpFromRef if bool(gpRow["is_from"]) else gpE.gpToRef
		gpRef["port_id"] = str(gpRow["old_port"])
