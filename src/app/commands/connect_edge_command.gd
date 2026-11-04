class_name GPConnectEdgeCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Why a new command instead of extending GPConnectCommand / 为何新增而非扩展 GPConnectCommand:
# GPConnectCommand is node-to-node and is covered by two existing tests; overloading it with
# ports, kinds, signal types, tag minting and duplicate detection would turn a 63-line value
# object into a compatibility minefield. The two live side by side: the old one keeps serving
# the SELECT/CONNECT path, this one serves the P3 pipe and signal tools.
# GPConnectCommand 是节点到节点，且已有两个测试覆盖；若把端口、类型、信号、铸号与重复检测
# 都塞进去，会把 63 行的值对象变成兼容性雷区。两者并存：旧的继续服务选择/连线路径，
# 本命令服务 P3 的管道与信号线工具。
#
# Tag minting belongs HERE, not in the tool / 铸号属于此处，而非工具：
# Undo must not silently burn a number. If the tool minted the tag before handing off, an
# undone-and-redone pipe would consume two numbers from a sequence that is defined as
# never-recycled. Minting inside gpExecute() ties the number to a step that is recorded.
# 撤销绝不能静默烧掉一个号。若工具在交棒前铸号，一次「撤销再重做」的管道会从「绝不回收」
# 的序列里吃掉两个号。把铸号放进 gpExecute()，就把号与「被记录的那一步」绑定在一起。
# Undo deliberately does NOT roll the high-water mark back — that is what "never recycled"
# means. / 撤销刻意不回退水位线 —— 这正是「绝不回收」的含义。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Source end: {"node_id","port_id"} or {"node_id":"","port_id":"","point":[x,y]} for a dangling end.
# 起点端：端口绑定为 {"node_id","port_id"}；悬空端为 {"node_id":"","port_id":"","point":[x,y]}。
var gpFromRef: Dictionary = {}

# Destination end, same shape. / 终点端，同形状。
var gpToRef: Dictionary = {}

# GPPIDEdge.GP_PROCESS / GP_UTILITY / GP_SIGNAL.
var gpKind: String = GPPIDEdge.GP_PROCESS

# Signal medium when gpKind == GP_SIGNAL. / gpKind 为 SIGNAL 时的信号类型。
var gpSignalType: String = ""

# False when the user drew with Shift held (straight, not orthogonal).
# 用户按住 Shift 绘制时为 false（直线而非正交）。
var gpOrtho: bool = true

# A PRE-ASSIGNED line number (cross-sheet continuation, user feedback 2026-11-04): when
# non-empty and not already taken on the TARGET graph, it is used INSTEAD of minting — the
# pipe drawn from the twin connector carries the source line's number (ADR-36 D1: the same
# number on another sheet is the legitimate continuation case). Empty (or taken) falls back
# to the normal mint, so a conflicting sheet never blocks the gesture.
# 预先给定的管线号（跨图纸延续，用户反馈 2026-11-04）：非空且未在**目标图**上被占用时，
# 直接采用而**不**铸新号 —— 从孪生连接符画出的管线继承源端编号（ADR-36 D1：同号出现在
# 另一张图纸是合法的延续）。为空（或已被占用）时回落正常铸号，编号冲突绝不阻塞手势。
var gpPresetTag: String = ""

# Pre-computed MIDDLE waypoints (auto-routed). Empty = let GPEdgeRoute derive an L/Z/U path from
# the two port normals, exactly as a hand-drawn pipe does. Set by GPEditService.gpConnectEdgeRouted().
# 预先算好的中间折点（自动布线）。为空表示由 GPEdgeRoute 依两端口法线推导 L/Z/U 路径 ——
# 与手绘管线完全一致。由 GPEditService.gpConnectEdgeRouted() 设置。
var gpRouting: Array[Vector2] = []

# Id of the created edge (readable after a successful gpExecute(), for selection).
# 所创建边的 id（gpExecute() 成功后可读，供选中用）。
var gpCreatedId: String = ""

# Human-readable reason the command refused, so the caller can show it instead of guessing.
# 命令拒绝执行的人类可读原因，调用方可直接显示而无需猜测。
var gpRefusal: String = ""

# The edge this command created, kept so redo re-adds the SAME object with the SAME id and tag.
# 本命令创建的边。保留它使重做能用相同 id 与位号重新加入同一对象。
var _gpEdge: GPPIDEdge = null

# Index the edge was inserted at, so undo restores the original ordering.
# 该边被插入的下标，使撤销能恢复原有次序。
var _gpInsertAt: int = -1


func _init(gpInFrom: Dictionary, gpInTo: Dictionary, gpInKind: String,
		gpInSignalType: String = "", gpInOrtho: bool = true,
		gpInPresetTag: String = "") -> void:
	gpFromRef = gpInFrom.duplicate(true)
	gpToRef = gpInTo.duplicate(true)
	gpKind = gpInKind
	gpSignalType = gpInSignalType
	gpOrtho = gpInOrtho
	gpPresetTag = gpInPresetTag
	gpLabel = "绘制信号线" if gpInKind == GPPIDEdge.GP_SIGNAL else "绘制管道"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	gpRefusal = ""
	if gpCtx == null or not gpCtx.gpIsReady():
		return false
	if not _gpValidate():
		return false
	if _gpFindDuplicate(gpCtx) != null:
		gpRefusal = "edge_duplicate"
		return false
	if _gpEdge == null:
		var gpEid: String = gpCtx.gpIds.gpNext("e")
 # Mint the pipe number INSIDE the command (see the header: undo must not burn a number).
 # Signal lines carry no line number by convention, so they get "".
 # 在命令内部铸管线号（见文件头：撤销不得烧号）。信号线按惯例不带线号，故为 ""。
		var gpTag: String = ""
		if gpKind != GPPIDEdge.GP_SIGNAL:
			# Continuation first (user feedback 2026-11-04): an inherited number is not a
			# mint — it consumes nothing and is checked only against the TARGET graph's
			# occupancy (ADR-36 D1 makes cross-sheet repeats legal; an on-sheet repeat is
			# still a conflict and falls back to minting).
			# 延续优先（用户反馈 2026-11-04）：继承号不是铸号 —— 不消耗任何序号，且只对
			# **目标图**的占用情况查重（ADR-36 D1 使跨图同号合法；同图同号仍是冲突，
			# 此时回落铸号）。
			if gpPresetTag != "" and not _gpTagTaken(gpCtx, gpPresetTag):
				gpTag = gpPresetTag
			# ADR-36: a line is numbered through its CLASS rule (the five-field designation),
			# not by the legacy PL counter. Attributes are not known at this moment — the
			# attribute panel fills them in and re-renders the SAME number, so the placeholder
			# costs nothing.
			# ADR-36：管线号走**类别**规则（五段代号），不再是旧的 PL 计数器。此刻还没有属性 ——
			# 属性面板填完后会重渲染**同一个号**，故占位不消耗序号。
			elif gpCtx.gpTags != null:
				gpTag = gpCtx.gpTags.gpNextTagForClass(GPProjectStandard.GP_CLASS_LINE)
			else:
				gpTag = GPTagGen.gpNextTag(gpCtx.gpGraph)
		_gpEdge = gpCtx.gpGraph.gpNewEdgeEx(gpEid, gpFromRef, gpToRef, gpKind, gpSignalType, gpTag)
		_gpEdge.gpOrtho = gpOrtho
 # An auto-routed edge stores its waypoints as DATA, never as baked geometry: the two ends
 # are still re-resolved from the port refs every frame.
 # 自动布线的边把折点存为「数据」而非烘死的几何：两端仍每帧由端口引用重算。
		if not gpRouting.is_empty():
			_gpEdge.gpRouting = gpRouting.duplicate()
		gpCreatedId = gpEid
	_gpInsertAt = gpCtx.gpGraph.gpEdges.size()
	gpCtx.gpGraph.gpInsertEdge(_gpEdge, _gpInsertAt)
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpEdge == null:
		return
	gpCtx.gpGraph.gpRemoveEdge(_gpEdge.gpInstanceId)


# Re-add the very same edge object — same id, same tag, same routing. Re-executing would mint a
# second number for the same pipe.
# 重新加入同一个边对象 —— 同 id、同位号、同折线。若重新执行，会为同一条管线铸出第二个号。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpEdge == null:
		return
	var gpAt: int = _gpInsertAt if _gpInsertAt >= 0 else gpCtx.gpGraph.gpEdges.size()
	gpCtx.gpGraph.gpInsertEdge(_gpEdge, gpAt)


# ============================ private ============================

# Reject the shapes that have no meaning on a P&ID:
# - both ends dangling (a line with no connection at all is not a pipe)
# - the same port on the same node (a self-loop)
# 拒绝在 P&ID 上没有意义的形状：
# - 两端皆悬空（一条完全没有连接的线不是管线）
# - 同一节点的同一端口（自环）
# The same node with two DIFFERENT ports is allowed: a real recirculation or bypass line.
# 同一节点的两个「不同」端口是允许的：真实的回流线或旁通线。
func _gpValidate() -> bool:
	var gpFn: String = str(gpFromRef.get("node_id", ""))
	var gpTn: String = str(gpToRef.get("node_id", ""))
	var gpFp: String = str(gpFromRef.get("port_id", ""))
	var gpTp: String = str(gpToRef.get("port_id", ""))
	if gpFn == "" and gpTn == "":
		gpRefusal = "pipe_needs_one_bound"
		return false
	if gpFn != "" and gpFn == gpTn and gpFp == gpTp:
		gpRefusal = "edge_self_loop"
		return false
	return true


# An identical edge (same kind, same two ends) already exists.
# 已存在一条完全相同的边（同类型、同两端）。
func _gpFindDuplicate(gpCtx: GPCommandContext) -> GPPIDEdge:
	for gpE in gpCtx.gpGraph.gpEdges:
		if gpE.gpKind != gpKind:
			continue
		if _gpSameEnd(gpE.gpFromRef, gpFromRef) and _gpSameEnd(gpE.gpToRef, gpToRef):
			return gpE
	return null


# Whether a line number is already occupied on the TARGET graph. Live scan (nodes and edges
# share one table, ADR-36 D6) — deliberately NOT the shared tag registry: this command runs
# with a registry whose graph binding/index belongs to ANOTHER sheet mid-gesture, and its
# cached state would misreport the just-minted local number as "taken" here.
# 管线号是否已被**目标图**占用。活体扫描（节点与边共表，ADR-36 D6）—— 刻意**不**走共享
# 编号注册表：本命令执行中途，注册表的图绑定 / 索引属于**另一张**图纸，其缓存态会把刚铸出
# 的本端号误判为「此处已被占用」。
func _gpTagTaken(gpCtx: GPCommandContext, gpTag: String) -> bool:
	return GPTagGen.gpIsTaken(gpCtx.gpGraph, gpTag, "")


# End equality that treats port_id as a HINT, not a contract: a legacy edge with an empty
# port_id on the same node still counts as the same end, so the user cannot stack duplicates by
# mixing old and new connections.
# 把 port_id 当「提示」而非契约的端点相等判定：同一节点上 port_id 为空的老边仍算同一端，
# 故用户无法通过混用新旧连接来堆叠重复边。
func _gpSameEnd(gpA: Dictionary, gpB: Dictionary) -> bool:
	if str(gpA.get("node_id", "")) != str(gpB.get("node_id", "")):
		return false
	var gpAp: String = str(gpA.get("port_id", ""))
	var gpBp: String = str(gpB.get("port_id", ""))
	if gpAp == "" or gpBp == "":
		return true
	return gpAp == gpBp
