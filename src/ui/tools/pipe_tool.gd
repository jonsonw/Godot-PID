class_name GPPipeTool
extends GPCanvasTool
# Copyright © 2026 Jonson Wang
# Two-press pipe drawing: pick a start nozzle, preview, pick an end nozzle (P3).
# 两段式管道绘制：选起点管口 → 预览 → 选终点管口（P3）。
#
# Why a new mode instead of reusing GP_CONNECT / 为何新开模式而非复用 GP_CONNECT：
#   GP_CONNECT means "node to node, no ports, no line type". Six call sites read it. Changing
#   its meaning would change six contracts at once; a new mode is dispatched by the existing
#   registry and leaves the old path byte-for-byte intact.
#   GP_CONNECT 的语义是「节点到节点、无端口、无线型」，有六处代码在读它。改语义等于同时改六份
#   契约；新开模式由既有注册表分派，旧路径逐字节不变。
#
# The preview uses the SAME router and painter as the committed edge / 预览与提交的边用同一套
#   router 与 painter：
#   This is the whole point of "what you see is what you get". If the preview drew a straight
#   line while the committed edge was routed orthogonally, the pipe would jump the instant the
#   user released the mouse.
#   这正是「所见即所得」的全部意义。若预览画直线而提交的边走正交布线，用户一松手管线就会跳位。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GPMode = GPCanvasInteractState.GPMode

# ---- transient state (this tool owns it; the canvas only forwards events) ----
# ---- 瞬态状态（本工具自持；画布只转发事件）----
# Snap result of the first press. / 第一次按下的吸附结果。
var _gpStart: Dictionary = {}

# True between the first and second press. / 第一次与第二次按下之间为真。
var _gpActive: bool = false

# Latest cursor position (world) for the preview. / 预览用的最新光标位置（世界坐标）。
var _gpCursor: Vector2 = Vector2.ZERO

# Latest snap under the cursor (empty until the first move). / 光标下最新的吸附结果（首次移动前为空）。
var _gpCursorSnap: Dictionary = {}

# Machine-readable reason the last commit was refused ("" when it succeeded).
# 上次提交被拒绝的机器可读原因（成功时为 ""）。
var gpRefusal: String = ""


# ============================ subclass hooks ============================
# ============================ 子类钩子 ============================
# GPSignalTool overrides ONLY these three — the whole two-press state machine is inherited
# rather than copied, so a fix to the interaction lands in both tools at once.
# GPSignalTool 只覆写这三个 —— 整个两段式状态机是继承而非复制的，故交互上的一处修复
# 会同时落到两个工具上。

# The kind of edge this tool creates. / 本工具创建的边的类型。
func _gpKind() -> String:
	return GPPIDEdge.GP_PROCESS


# Port purposes this tool will connect to. / 本工具允许连接的端口用途。
func _gpWantTypes() -> Array[String]:
	return [GPPort.GP_NOZZLE, GPPort.GP_TERMINAL]


# Default signal medium (only meaningful for the signal tool). / 默认信号类型（仅信号线工具用）。
func _gpDefaultSignalType() -> String:
	return ""


# ============================ input ============================

func gpOnActivate() -> void:
	_gpReset()


func gpOnDeactivate() -> void:
	_gpReset()


func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	var gpCv := gpCtx.gpCv
	var gpSnap: Dictionary = _gpSnapAt(gpWorld)
	if not _gpActive:
		# First press: anchor the start. A pipe may also START dangling (off-sheet continuation),
		# so a grid snap is accepted here and only checked against the far end at commit time.
		# 第一次按下：锚定起点。管道也允许「起点悬空」（延续他页），故此处的网格吸附被接受，
		# 只在提交时才与另一端一起校验。
		_gpStart = gpSnap
		_gpActive = true
		_gpCursor = gpSnap.get("pos", gpWorld)
		_gpCursorSnap = gpSnap
		gpRefusal = ""
		gpCv.queue_redraw()
		gpCv.gpEmitStatus()
		return true
	# Second press: commit. / 第二次按下：提交。
	gpRefusal = _gpValidatePair(_gpStart, gpSnap)
	if gpRefusal != "":
		gpCv.gpReportRefusal(gpRefusal)
		_gpReset()
		gpCv.queue_redraw()
		return true
	var gpId: String = gpCv.gpRequestConnectEdge(_gpRefFrom(_gpStart), _gpRefFrom(gpSnap),
		_gpKind(), _gpDefaultSignalType(), not gpShift)
	if gpId == "":
		# The command refused (duplicate / self-loop / both ends free).
		# 命令拒绝（重复边 / 自环 / 两端皆悬空）。
		gpCv.gpReportRefusal(gpCv.gpActions.gpLastRefusal)
	else:
		gpRefusal = ""
	_gpReset()
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()
	return true


func gpOnMove(gpWorld: Vector2) -> bool:
	if not _gpActive:
		return false
	_gpCursor = gpWorld
	_gpCursorSnap = _gpSnapAt(gpWorld)
	gpCtx.gpCv.queue_redraw()
	return true


func gpOnKey(_gpKey: InputEventKey) -> bool:
	return false


func gpCancel() -> bool:
	if not _gpActive:
		return false
	_gpReset()
	gpCtx.gpCv.queue_redraw()
	return true


# ============================ overlay ============================

# Rubber band. Drawn in SCREEN coordinates (the overlay is a screen-space CanvasItem), using the
# committed edge's own router and painter so the preview cannot disagree with the result.
# 橡皮筋。以屏幕坐标绘制（覆盖层是屏幕空间的 CanvasItem），并使用提交边自身的 router 与 painter，
# 使预览不可能与结果不一致。
func gpDrawOverlay(gpCv: CanvasItem) -> void:
	if not _gpActive or gpCv == null:
		return
	var gpEnd: Dictionary = _gpCursorSnap
	if gpEnd.is_empty():
		gpEnd = {"pos": _gpCursor, "dir": Vector2.ZERO, "bound": false}
	var gpWorld: PackedVector2Array = GPEdgeRoute.gpRoute(_gpStart, gpEnd, [], not _gpIsStraight())
	if gpWorld.size() < 2:
		return
	var gpPts: PackedVector2Array = PackedVector2Array()
	for gpP in gpWorld:
		gpPts.append(gpCv.gpScreenFromWorld(gpP))
	var gpSt: Dictionary = GPEdgeStyle.gpStyleFor(_gpKind(), _gpDefaultSignalType(), 1.0)
	var gpW: float = maxf(float(gpSt.get("width", 1.6)), 1.5)
	GPEdgePainter.gpDrawInk(gpCv, gpPts, gpSt.get("color", Color("#DCE3F0")), gpW,
		gpSt.get("pattern", PackedFloat32Array()))
	# Highlight the anchored end so "where does this pipe start" is never ambiguous.
	# 高亮已锚定的那一端，使「这条管线从哪开始」永不含糊。
	var gpSp: Vector2 = gpCv.gpScreenFromWorld(_gpStart.get("pos", Vector2.ZERO))
	gpCv.draw_circle(gpSp, 5.0, Color(0.35, 0.85, 0.95, 0.9))
	# Highlight the end about to be picked.
	# 高亮即将被选中的那一端。
	var gpEp: Vector2 = gpCv.gpScreenFromWorld(gpEnd.get("pos", Vector2.ZERO))
	if GPSnapResolver.gpIsPort(gpEnd):
		gpCv.draw_circle(gpEp, 5.0, Color(0.35, 0.85, 0.95, 0.55))


func gpCursor() -> int:
	return Input.CURSOR_CROSS


# ============================ private ============================

func _gpReset() -> void:
	_gpStart = {}
	_gpActive = false
	_gpCursorSnap = {}


func _gpSnapAt(gpWorld: Vector2) -> Dictionary:
	var gpCv := gpCtx.gpCv
	return GPSnapResolver.gpSnap(gpCv.gpGraph, gpCv.gpDefLookupCallable(), gpWorld,
		gpCv.gpViewZoom, _gpWantTypes())


# Shift means "straight, no orthogonal routing". Sampled live at draw time (not from the press
# event) because the preview must follow the key while it is held, and gpOnMove carries no
# modifier flags.
# Shift 表示「直连、不走正交」。在绘制时实时采样（而非取按下事件），因为预览必须跟随按住状态，
# 而 gpOnMove 不携带修饰键。
func _gpIsStraight() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)


# Turn a snap result into the ref dictionary an edge stores.
# 把吸附结果转换为边所存的引用字典。
func _gpRefFrom(gpSnap: Dictionary) -> Dictionary:
	var gpNodeId: String = str(gpSnap.get("node_id", ""))
	if gpNodeId == "":
		var gpP: Vector2 = gpSnap.get("pos", Vector2.ZERO)
		return {"node_id": "", "port_id": "", "point": [gpP.x, gpP.y]}
	return {"node_id": gpNodeId, "port_id": str(gpSnap.get("port_id", ""))}


# Reject the pairs that have no meaning on a P&ID. Returns "" when the pair is acceptable,
# otherwise a machine-readable refusal key.
# 拒绝在 P&ID 上没有意义的端点配对。可接受时返回 ""，否则返回机器可读的拒绝键。
#
# The type check is what stops a user from running a pipe into a valve actuator: the snap
# resolver deliberately OFFERS the wrong-typed port so we can say so, instead of silently
# snapping to nothing.
# 类型检查正是阻止用户把管道接到阀门执行机构上的东西：吸附解析器刻意「提供」类型不符的端口，
# 好让我们能说出来，而不是静默地什么都不吸。
func _gpValidatePair(gpA: Dictionary, gpB: Dictionary) -> String:
	var gpAn: String = str(gpA.get("node_id", ""))
	var gpBn: String = str(gpB.get("node_id", ""))
	# Both ends free: a line connected to nothing is not a pipe.
	# 两端皆悬空：一条什么都没连的线不是管线。
	if gpAn == "" and gpBn == "":
		return "pipe_needs_one_bound"
	# Same port on the same node: a self-loop. Two DIFFERENT ports on one node is a real
	# recirculation / bypass line and stays legal.
	# 同一节点的同一端口：自环。同一节点的两个「不同」端口是真实的回流 / 旁通线，保持合法。
	if gpAn != "" and gpAn == gpBn and str(gpA.get("port_id", "")) == str(gpB.get("port_id", "")):
		return "edge_self_loop"
	# Type check on whichever end is bound to a port (a node-centre snap has type "" and is
	# always accepted — legacy symbols have no ports at all).
	# 对绑定到端口的那一端做类型检查（节点中心吸附的 type 为 ""，恒被接受 —— 老图元本就没有端口）。
	var gpWant: Array[String] = _gpWantTypes()
	var gpAt: String = str(gpA.get("type", ""))
	var gpBt: String = str(gpB.get("type", ""))
	if gpAn != "" and gpAt != "" and not gpWant.has(gpAt):
		return "port_type_mismatch"
	if gpBn != "" and gpBt != "" and not gpWant.has(gpBt):
		return "port_type_mismatch"
	return ""
