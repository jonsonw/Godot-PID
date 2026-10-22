class_name GPFinishOpenEndCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Finish a line at an OPEN END with its note, as ONE undoable step (B08 follow-up).
# 把一条线**终止于开口端**并带上注记，作为一步可撤销的编辑（B08 续）。
#
# Why this cannot be two commands / 为何不能拆成两条命令：
# The user's gesture is one act: "stop here, and this is what the end is". If the edge and its
# note were two steps, undo would first remove the note and leave an UNNOTED open end behind —
# a state the user never created and which the DRC then reports as an error. One gesture, one step.
# 用户的手势是**一个**动作：「停在这里，这个端头叫这个」。若边与注记分成两步，撤销会先移除注记、
# 留下一个**未注明的开口端** —— 那是用户从未制造过的状态，而 DRC 会立刻把它报成错误。
# 一个手势，一步。
#
# Composition / 组合方式：
# it owns the two existing commands and forwards execute/undo/redo in the right order, so neither
# of them needs a special "composite mode" and both keep their own tests.
# 它持有两条既有命令，按正确顺序转发执行 / 撤销 / 重做，故两条命令都不需要「组合模式」，
# 也各自保留自己的测试。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The edge-creating command (owns tag minting / duplicate detection / routing).
# 建边命令（负责铸位号 / 重复检测 / 走线）。
var _gpConnect: GPConnectEdgeCommand = null

# The note command, constructed AFTER the edge exists (it needs the edge id).
# 注记命令，在边存在之后构造（它需要边 id）。
var _gpNote: GPSetEndNoteCommand = null

# The note text.
# 注记文字。
var _gpText: String = ""

# Which end of the new edge carries the note (the dangling one).
# 新边的哪一端带注记（悬空的那端）。
var _gpIsFrom: bool = false

# An EXISTING note uid to attach to, or "" to create a new one (B08: "connect to an end-point
# note" — two lines may legitimately terminate at the SAME open end, e.g. a header and a drain
# sharing one TO ATM note).
# 要接上的**既有**注记 uid，"" 表示新建（B08：「接到末端注记」—— 两条线可以合法地终止于**同一个**
# 开口端，例如一根汇管与一根排凝共用一条 TO ATM 注记）。
var _gpExistingUid: String = ""

# Id of the created edge, readable after a successful execute.
# 所创建边的 id，执行成功后可用。
var gpCreatedId: String = ""

# Refusal reason (mirrors the connect command's, plus our own).
# 拒绝原因（沿用建边命令的，另有本命令自己的）。
var gpRefusal: String = ""


# Build from the two end refs, the line kind and the note text.
# 由两端引用、线类型与注记文字构造。
# gpIsFromNote says which end of the NEW edge is dangling; the caller knows which one it drew.
# gpIsFromNote 指明**新边**的哪一端悬空；调用方知道自己画的是哪一端。
func _init(gpFromRef: Dictionary, gpToRef: Dictionary, gpKind: String, gpSignalType: String,
		gpText: String, gpIsFromNote: bool, gpOrtho: bool = true,
		gpExistingNoteUid: String = "") -> void:
	_gpConnect = GPConnectEdgeCommand.new(gpFromRef, gpToRef, gpKind, gpSignalType, gpOrtho)
	_gpText = gpText
	_gpIsFrom = gpIsFromNote
	_gpExistingUid = gpExistingNoteUid
	gpLabel = "绘制开口端"


# Create the edge, then hang the note on its dangling end. Rolls the edge back if the note is
# refused, so a failed note never leaves a half-done gesture.
# 先建边，再把注记挂到其悬空端。注记被拒时回滚边，使失败的手势绝不留下一半。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	gpRefusal = ""
	if not _gpConnect.gpExecute(gpCtx):
		gpRefusal = _gpConnect.gpRefusal
		return false
	gpCreatedId = _gpConnect.gpCreatedId
	if _gpExistingUid != "":
		# Attach to the note that already exists: a shared end point. No new object is created, and
		# undo must therefore NOT delete the note (it belongs to the other line).
		# 接上**既有**注记：共用同一个开口端。不创建新对象，故撤销**不得**删除该注记
		#（它属于另一条线）。
		var gpEdge: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpCreatedId)
		if gpEdge == null:
			_gpConnect.gpUndo(gpCtx)
			gpCreatedId = ""
			gpRefusal = "note_missing"
			return false
		gpEdge.gpSetEndNoteUid(_gpIsFrom, _gpExistingUid)
		gpCtx.gpGraph.gpGraphChanged.emit()
		return true
	_gpNote = GPSetEndNoteCommand.new(gpCtx.gpGraph, gpCreatedId, _gpIsFrom, _gpText)
	if not _gpNote.gpExecute(gpCtx):
		# The edge exists but the note did not attach: undo the edge so the caller can retry from a
		# clean drawing state instead of an open end the user did not ask for.
		# 边已建但注记没挂上：撤掉边，使调用方能从干净的绘制状态重试，
		# 而不是得到一个用户没要过的开口端。
		_gpConnect.gpUndo(gpCtx)
		gpCreatedId = ""
		gpRefusal = "note_failed"
		return false
	return true


# Undo the note first, then the edge (reverse order of execution).
# 先撤销注记，再撤销边（与执行相反的顺序）。
func gpUndo(gpCtx: GPCommandContext) -> void:
	# Shared end point: the note belongs to the OTHER line, so only the edge is undone.
	# 共用开口端：注记属于**另一条**线，故只撤销这条边。
	if _gpExistingUid != "":
		if _gpConnect != null:
			_gpConnect.gpUndo(gpCtx)
		return
	if _gpNote != null:
		_gpNote.gpUndo(gpCtx)
	if _gpConnect != null:
		_gpConnect.gpUndo(gpCtx)


# Redo in execution order.
# 按执行顺序重做。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if _gpConnect != null:
		_gpConnect.gpRedo(gpCtx)
	if _gpExistingUid != "":
		# Re-attach the reference after the edge is re-added (the note survived untouched).
		# 边被重新加入后恢复引用（注记本身未被动过）。
		var gpEdge: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpCreatedId)
		if gpEdge != null:
			gpEdge.gpSetEndNoteUid(_gpIsFrom, _gpExistingUid)
		return
	if _gpNote != null:
		_gpNote.gpRedo(gpCtx)
