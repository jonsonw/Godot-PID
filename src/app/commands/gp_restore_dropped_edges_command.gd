class_name GPRestoreDroppedEdgesCommand
extends GPCommand
# records: a SPLIT recreates the original edge (same id, same routing, same ends) and a REROUTE
# restores the edge's original intermediate waypoints. This is the 4th half of
# GPDeleteSelectionCommand, so the whole delete stays ONE undo step and both ends' original
# connections are preserved exactly.
# 删除一个曾压到连线上的图元时，重放其落点恢复记录：SPLIT 重建原边（同 id、同走线、同两端），
# REROUTE 还原该边原始中间折点。本命令作为 GPDeleteSelectionCommand 的第 4 部分，使整个删除仍是
# 一步撤销，且连线两端原有的连接关系原样保留。

# Records captured from the graph at delete time: symbol id -> Array of records (deep copy).
# 删除时从图捕获的记录：图元 id -> 记录数组（深拷贝）。
var _gpBySym: Dictionary = {}

# For undo we remember what we created/overwrote so the reverse is exact.
# 供撤销：记下重建的边 id 与被覆盖的落点后走线，使反向精确。
var _gpRecreated: Array[String] = []
var _gpReroutedBack: Dictionary = {}  # edge_id -> Array[Vector2] (the routing we set during execute)


func _init(gpBySym: Dictionary) -> void:
	_gpBySym = gpBySym.duplicate(true)
	gpLabel = "还原落点连线"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	_gpRecreated.clear()
	_gpReroutedBack.clear()
	var gpAny: bool = false
	for gpSym in _gpBySym.keys():
		var gpRecs: Array = _gpBySym[gpSym]
		for gpR in gpRecs:
			if gpR.get("kind", "") == "split":
 # Rebuild the original edge object from its saved dict and re-insert it at its
 # former z-index so the sheet's draw order is unchanged after the delete.
 # 依所存字典重建原边对象，并按原层序插回，使删除后图纸绘制顺序不变。
				var gpOrig: Dictionary = gpR.get("orig", {})
				if gpOrig.is_empty():
					continue
				var gpEdge: GPPIDEdge = GPPIDEdge.new()
				gpEdge.gpFromDict(gpOrig)
				var gpIdx: int = int(gpR.get("orig_index", -1))
				if gpIdx < 0 or gpIdx > gpCtx.gpGraph.gpEdges.size():
					gpIdx = gpCtx.gpGraph.gpEdges.size()
				gpCtx.gpGraph.gpInsertEdge(gpEdge, gpIdx)
				_gpRecreated.append(gpEdge.gpInstanceId)
				gpAny = true
			elif gpR.get("kind", "") == "reroute":
 # Restore the edge's pre-drop intermediate waypoints (ends are unchanged).
 # 还原该边落点前的「中间折点」（两端不变）。
				var gpEid: String = str(gpR.get("edge_id", ""))
				var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEid)
				if gpE != null:
					_gpReroutedBack[gpEid] = gpE.gpRouting.duplicate()
					gpE.gpRouting = (gpR.get("orig_routing", []) as Array[Vector2]).duplicate()
					gpAny = true
 # The symbol is gone now; drop its history with it.
 # 图元已不在，历史随之清除。
		gpCtx.gpGraph.gpClearDrops(gpSym)
	return gpAny


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	# Reverse reroutes first (restore the post-drop routing), then remove recreated edges.
	# 先反转向（恢复落点后走线），再移除重建的边。
	for gpEid in _gpReroutedBack.keys():
		var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEid)
		if gpE != null:
			gpE.gpRouting = (_gpReroutedBack[gpEid] as Array[Vector2]).duplicate()
	_gpReroutedBack.clear()
	for gpEid in _gpRecreated:
		gpCtx.gpGraph.gpRemoveEdge(gpEid)
	_gpRecreated.clear()
	# Re-record the symbol histories so a later (re)delete can replay again.
	# 重新登记图元历史，使后续再删仍可重放。
	for gpSym in _gpBySym.keys():
		for gpR in _gpBySym[gpSym]:
			gpCtx.gpGraph.gpRecordDrop(gpSym, gpR.duplicate())


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
