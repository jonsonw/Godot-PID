class_name GPSetEndNoteCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Attach / edit / detach the OPEN-END NOTE of one dangling end, creating the text annotation on
# first use — ONE undoable step (B08, ADR-34).
# 为某个悬空端挂上 / 改写 / 解除**开口端注记**，首次使用时创建文字注释 —— **一步**可撤销
#（B08，ADR-34）。
#
# Why one command and not two / 为何一条命令而非两条：
# The user's gesture is one act ("write what this open end is"). Splitting it into "create text
# object" + "point the edge at it" would leave a half state in the undo stack that the user never
# saw — exactly the kind of step the command layer exists to avoid.
# 用户的手势是**一个**动作（「写下这个开口端是什么」）。若拆成「建文字对象」+「让边指向它」，
# 撤销栈里就会出现用户从未见过的中间态 —— 正是命令层要避免的那种步。
#
# Anchor / 锚点：
# The note sits just OUTSIDE the end, offset along the outward direction derived from the line, so
# it does not overlap the pipe. Moving the end later keeps the stored note position (the user may
# drag the note); the binding is a uid REFERENCE, not a live transform.
# 注记落在端**外侧**：沿连线朝外的方向偏移，避免压住管子。之后移动端点保留注记已存的位置
#（用户可以自己拖注记）；绑定是 uid **引用**，不是活的变换关系。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# World-space gap between the end point and the note anchor, in mm.
# 端点与注记锚点之间的世界间隙（mm）。
const GP_NOTE_GAP: float = 4.0

# The graph the edge and the annotation live in.
# 边与注释所在的图。
var _gpGraph: GPPIDGraph = null

# The edge whose end carries the note.
# 承载注记的那条边。
var _gpEdgeId: String = ""

# Which end (true = the edge's start).
# 哪一端（true = 边的起点）。
var _gpIsFrom: bool = false

# Desired note text; "" detaches (and removes an annotation this command created earlier).
# 期望的注记文字；空串表示解除（并移除本命令此前创建的注释）。
var _gpText: String = ""

# Previous state, captured on the first execute.
# 先前状态，首次执行时捕获。
var _gpPrevUid: String = ""

# Previous text of the previously referenced note ("" when there was none).
# 先前所引用注记的文字（原本没有则为空串）。
var _gpPrevText: String = ""

# The annotation object this command created (null when it edited an existing one).
# 本命令创建的注释对象（编辑既有注记时为 null）。
var _gpCreated: GPShape = null

# Whether the previous state was captured already (redo executes again).
# 是否已捕获先前状态（重做会再次执行）。
var _gpSnapped: bool = false


# Build the intent: set (or clear) the note text of one edge end.
# 构造意图：设置（或清除）某边某端的注记文字。
func _init(gpGraph: GPPIDGraph, gpEdgeId: String, gpIsFrom: bool, gpText: String) -> void:
	_gpGraph = gpGraph
	_gpEdgeId = gpEdgeId
	_gpIsFrom = gpIsFrom
	_gpText = gpText
	gpLabel = "开口端注记"


# Apply the intent. Returns false when the edge is missing or the end is not dangling — a note on
# a CONNECTED end would be a note belonging to nothing, so the command refuses rather than
# silently attaching it to whatever is nearby.
# 应用意图。边缺失或该端并非悬空时返回 false —— 给**已连接**端挂注记等于给虚无挂注记，
# 故命令直接拒绝，而不是悄悄挂到附近的什么东西上。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if _gpGraph == null or _gpEdgeId == "":
		return false
	var gpE: GPPIDEdge = _gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null or not gpE.gpIsDangling(_gpIsFrom):
		return false
	if not _gpSnapped:
		_gpSnapped = true
		_gpPrevUid = gpE.gpEndNoteUid(_gpIsFrom)
		var gpPrev: GPShape = _gpFindNote(_gpPrevUid)
		_gpPrevText = gpPrev.gpText if gpPrev != null else ""
	var gpRefUid: String = gpE.gpEndNoteUid(_gpIsFrom)
	var gpNote: GPShape = _gpFindNote(gpRefUid)
	if _gpText.strip_edges() == "":
		# Detach: drop the reference, and remove the annotation only when THIS command created it
		# (deleting a note the user had written elsewhere would be a destructive surprise).
		# 解除：去掉引用，且仅当**本命令**创建的注释才删除（删除用户别处写的注记属破坏性意外）。
		if gpNote != null and gpNote == _gpCreated:
			_gpGraph.gpRemoveShape(gpNote)
		gpE.gpSetEndNoteUid(_gpIsFrom, "")
		_gpGraph.gpGraphChanged.emit()
		return true
	if gpNote == null:
		# First use: mint the annotation at the outward offset of this end.
		# 首次：在该端外侧偏移处铸造注释。
		_gpCreated = GPShape.gpTextNote(_gpNoteAnchor(gpE), _gpText)
		# The uid comes from the CONTEXT's generator (the document's counter), never from a global
		# singleton: two documents open at once must not mint the same uid (W21).
		# uid 来自**上下文**的生成器（本文档的计数器），绝不来自全局单例：同时打开的两张图
		# 不得铸出同一个 uid（W21）。
		_gpCreated.gpUid = gpCtx.gpIds.gpNextGlobal("t")
		gpNote = _gpCreated
		_gpGraph.gpAddShape(gpNote)
		gpE.gpSetEndNoteUid(_gpIsFrom, gpNote.gpUid)
	else:
		gpNote.gpText = _gpText
	gpNote.gpText = _gpText
	_gpGraph.gpGraphChanged.emit()
	return true


# Put the previous note (or the absence of one) back.
# 把先前的注记（或「没有注记」）放回去。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if _gpGraph == null:
		return
	var gpE: GPPIDEdge = _gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null:
		return
	if _gpCreated != null and gpE.gpEndNoteUid(_gpIsFrom) == _gpCreated.gpUid:
		_gpGraph.gpRemoveShape(_gpCreated)
	if _gpPrevUid == "":
		gpE.gpSetEndNoteUid(_gpIsFrom, "")
	else:
		gpE.gpSetEndNoteUid(_gpIsFrom, _gpPrevUid)
		var gpPrev: GPShape = _gpFindNote(_gpPrevUid)
		if gpPrev != null:
			gpPrev.gpText = _gpPrevText
	_gpGraph.gpGraphChanged.emit()


# Re-apply the intent (recreating the annotation object keeps its uid, so references stay valid).
# 重新应用意图（重建注释对象保持同一 uid，故引用依然有效）。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if _gpGraph == null or _gpText.strip_edges() == "":
		return
	var gpE: GPPIDEdge = _gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null:
		return
	var gpNote: GPShape = _gpFindNote(_gpCreated.gpUid if _gpCreated != null else "")
	if gpNote == null and _gpCreated != null:
		_gpGraph.gpAddShape(_gpCreated)
		gpNote = _gpCreated
	if gpNote != null:
		gpNote.gpText = _gpText
		gpE.gpSetEndNoteUid(_gpIsFrom, gpNote.gpUid)
	_gpGraph.gpGraphChanged.emit()


# Find an annotation by uid (null when absent).
# 按 uid 找注释（不存在返回 null）。
func _gpFindNote(gpUid: String) -> GPShape:
	if gpUid == "" or _gpGraph == null:
		return null
	for gpS in _gpGraph.gpShapes:
		if gpS != null and gpS.gpUid == gpUid:
			return gpS
	return null


# Where the note should sit: just outside the end, along the pipe's outward direction.
# 注记应落的位置：端外侧，沿管子朝外的方向。
func _gpNoteAnchor(gpE: GPPIDEdge) -> Vector2:
	var gpEnd: Vector2 = gpE.gpDanglingPoint(_gpIsFrom)
	if gpEnd == Vector2.INF:
		return Vector2.ZERO
	# The outward direction is the reverse of the line's direction at that end. The line's other
	# end is either a real point or resolved from routing; when both are unavailable the note goes
	# right of the end (a stable, readable default).
	# 朝外方向是该端处线方向的反向。另一端要么是真实坐标、要么要从折线解析；两者都不可用时，
	# 注记放在端右侧（稳定且可读的默认）。
	var gpInside: Vector2 = Vector2.ZERO
	if _gpIsFrom and gpE.gpRouting.size() > 0:
		gpInside = gpE.gpRouting[0]
	elif not _gpIsFrom and gpE.gpRouting.size() > 0:
		gpInside = gpE.gpRouting[gpE.gpRouting.size() - 1]
	var gpDir: Vector2 = (gpEnd - gpInside)
	if gpDir.length() < 0.001:
		gpDir = Vector2.RIGHT
	gpDir = gpDir.normalized()
	return gpEnd + gpDir * GP_NOTE_GAP
