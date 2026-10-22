class_name GPConvertNoteToPortCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Turn an annotated OPEN END into a real connection: the note text is dragged onto a nozzle, so the
# line(s) that ended at that note now end AT that port, and the note is removed (B08 follow-up).
# 把已注明的**开口端**变成真实连接：把注记文字拖到管嘴上，于是原本终止于该注记的线现在终止于
# 那个端口，注记被移除（B08 续）。
#
# Why this is a conversion and not a deletion / 为何是「转换」而非「删除」：
# the user's gesture says "this end was open, now it is connected". Deleting the note alone would
# leave the line dangling (still an error), and connecting alone would leave a note describing
# nothing. ONE gesture must produce a consistent drawing, hence ONE command.
# 用户的手势说的是「这个端头原本是开口，现在接上了」。只删注记会留下悬空端（仍是错误），
# 只连线会留下一条描述不了任何东西的注记。一个手势必须产出一张自洽的图 —— 故一条命令。
#
# Shared end points / 共用开口端：
# two lines may reference the SAME note; BOTH become connected to the port (that is what the
# drawing means when a header and a drain share one TO ATM). Undo restores each end separately.
# 两条线可能引用**同一条**注记；两者都接到该端口（汇管与排凝共用一条 TO ATM 时，图纸就是这个意思）。
# 撤销逐端恢复。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Graph that owns the note and the edges.
# 持有注记与各边的图。
var _gpGraph: GPPIDGraph = null

# Uid of the note being converted.
# 被转换注记的 uid。
var _gpNoteUid: String = ""

# Target port reference {node_id, port_id}.
# 目标端口引用 {node_id, port_id}。
var _gpPortRef: Dictionary = {}

# Edges touched, with their previous end refs and which side referenced the note.
# 被改动的边，及其先前的端引用与哪一端引用了该注记。
var _gpBefore: Array[Dictionary] = []

# The removed note object (kept for undo).
# 被移除的注记对象（供撤销）。
var _gpNote: GPShape = null

# Index the note occupied, so undo restores the z-order.
# 注记载原本所在的下标，使撤销恢复叠放顺序。
var _gpNoteAt: int = -1


# Build from the graph, the note uid and the target port.
# 由图、注记 uid 与目标端口构造。
func _init(gpGraph: GPPIDGraph, gpNoteUid: String, gpPortRef: Dictionary) -> void:
	_gpGraph = gpGraph
	_gpNoteUid = gpNoteUid
	_gpPortRef = gpPortRef.duplicate(true)
	gpLabel = "注记转连线"


# Convert every edge that references the note. Returns false when nothing referenced it (then
# nothing is changed at all — a drag onto a port of an unrelated note must not delete that note).
# 转换所有引用该注记的边。没有任何边引用时返回 false（此时什么都不改 ——
# 把不相干注记拖到端口上不得删掉它）。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if _gpGraph == null or _gpNoteUid == "" or _gpPortRef.is_empty():
		return false
	var gpNode: String = str(_gpPortRef.get("node_id", ""))
	var gpPort: String = str(_gpPortRef.get("port_id", ""))
	if gpNode == "" or gpPort == "":
		return false
	# Collect first, mutate second: the scan must not run against a changing edge list.
	# 先收集再改：扫描不得针对一个正在变化的边列表运行。
	var gpTargets: Array[Dictionary] = []
	for gpE in _gpGraph.gpEdges:
		if gpE == null:
			continue
		for gpIsFrom in [true, false]:
			if gpE.gpEndNoteUid(gpIsFrom) != _gpNoteUid:
				continue
			gpTargets.append({
				"edge_id": gpE.gpInstanceId,
				"is_from": gpIsFrom,
				"ref_from": gpE.gpFromRef.duplicate(true),
				"ref_to": gpE.gpToRef.duplicate(true),
			})
	if gpTargets.is_empty():
		return false
	_gpBefore = gpTargets.duplicate(true)
	_gpNote = _gpFindNote()
	_gpNoteAt = _gpGraph.gpShapes.find(_gpNote)
	for gpT in gpTargets:
		var gpE: GPPIDEdge = _gpGraph.gpGetEdge(str(gpT.get("edge_id", "")))
		if gpE == null:
			continue
		var gpIsFrom: bool = bool(gpT.get("is_from", false))
		# The end that was open becomes the port; the OTHER end is untouched.
		# 原本开口的那一端改成该端口；另一端不动。
		var gpNewRef: Dictionary = {"node_id": gpNode, "port_id": gpPort}
		if gpIsFrom:
			gpE.gpFromRef = gpNewRef
		else:
			gpE.gpToRef = gpNewRef
		gpE.gpSetEndNoteUid(gpIsFrom, "")
	if _gpNote != null:
		_gpGraph.gpRemoveShape(_gpNote)
	_gpGraph.gpGraphChanged.emit()
	return true


# Put the note back and restore every end that referenced it.
# 放回注记，并恢复每一个引用它的端。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if _gpGraph == null:
		return
	if _gpNote != null and _gpGraph.gpShapes.find(_gpNote) < 0:
		_gpGraph.gpInsertShape(_gpNote, _gpNoteAt)
	for gpT in _gpBefore:
		var gpE: GPPIDEdge = _gpGraph.gpGetEdge(str(gpT.get("edge_id", "")))
		if gpE == null:
			continue
		gpE.gpFromRef = (gpT.get("ref_from", {}) as Dictionary).duplicate(true)
		gpE.gpToRef = (gpT.get("ref_to", {}) as Dictionary).duplicate(true)
		gpE.gpSetEndNoteUid(bool(gpT.get("is_from", false)), _gpNoteUid)
	_gpGraph.gpGraphChanged.emit()


# Re-apply the conversion (same rule as execute, without re-scanning for new referrers).
# 重新应用转换（与 execute 同规则，但不重新扫描新的引用者）。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if _gpGraph == null:
		return
	var gpNode: String = str(_gpPortRef.get("node_id", ""))
	var gpPort: String = str(_gpPortRef.get("port_id", ""))
	for gpT in _gpBefore:
		var gpE: GPPIDEdge = _gpGraph.gpGetEdge(str(gpT.get("edge_id", "")))
		if gpE == null:
			continue
		var gpIsFrom: bool = bool(gpT.get("is_from", false))
		var gpNewRef: Dictionary = {"node_id": gpNode, "port_id": gpPort}
		if gpIsFrom:
			gpE.gpFromRef = gpNewRef
		else:
			gpE.gpToRef = gpNewRef
		gpE.gpSetEndNoteUid(gpIsFrom, "")
	if _gpNote != null:
		_gpGraph.gpRemoveShape(_gpNote)
	_gpGraph.gpGraphChanged.emit()


# The note object by uid.
# 按 uid 取注记对象。
func _gpFindNote() -> GPShape:
	for gpS in _gpGraph.gpShapes:
		if gpS != null and gpS.gpUid == _gpNoteUid:
			return gpS
	return null
