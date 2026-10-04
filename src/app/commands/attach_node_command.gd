class_name GPAttachNodeCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Create a node that is MOUNTED on a host, as ONE undoable step.
# 创建一个**挂载**在宿主上的节点，作为一步可撤销的编辑。
#
# Why it is not a variant of GPAddNodeCommand / 为何不是 GPAddNodeCommand 的一个变体：
# A mounted child's world position is DERIVED, never stored (see GPMountResolver). So the caller
# cannot hand over a world position the way the free-placement path does — it hands over a
# (parent, anchor) pair instead, and the position field is deliberately left at ZERO so a future
# reader can never mistake a stale coordinate for the truth. Making this a separate command keeps
# GPAddNodeCommand's "world position IS the position" contract intact for every existing caller.
# 挂载子件的世界坐标是**推导**的、永不存储（见 GPMountResolver）。故调用方无法像自由放置路径
# 那样交出世界坐标 —— 它交出 (宿主, 锚点) 对，而位置字段被**刻意**留在 ZERO，使将来的读者绝不
# 会把过期坐标误认为真相。独立成命令可使 GPAddNodeCommand 的「世界坐标就是位置」契约对既有
# 调用方保持完整。
#
# Redo rule / 重做规则：
# Same as GPAddNodeCommand: the created object is kept, so redo re-adds the SAME object with the
# SAME id. Re-running gpExecute() would mint a new id and silently break references.
# 与 GPAddNodeCommand 相同：保留所创建的对象，故重做会以相同 id 重新加入同一对象。
# 重跑 gpExecute() 会铸造新 id 并静默破坏引用。

# Symbol definition id to instantiate (e.g. "DGENERAL008").
# 要实例化的图元定义 id（如 "DGENERAL008"）。
var gpSymbolId: String = ""

# Host node the new child is mounted on.
# 新子件所挂载的宿主节点。
var gpParentUid: String = ""

# Anchor NAME on the host. May be "" — then the child degrades to the host centre (ladder 3).
# 宿主上的锚点**名**。可为 "" —— 此时子件降级到宿主中心（阶梯 3）。
var gpAnchor: String = ""

# Optional per-instance nudge, in the host's local pixels (default ZERO).
# 可选的单实例微调（宿主本地像素，默认 ZERO）。
var gpMountOffset: Vector2 = Vector2.ZERO

# Optional per-instance extra rotation, in degrees (default 0).
# 可选的单实例附加旋转（度，默认 0）。
var gpMountAngleDeg: float = 0.0

# Tag/label shown next to the instance. May be empty (the canvas then shows the type name).
# 实例旁显示的位号 / 标签。可为空（此时画布显示类型名）。
var gpTag: String = ""

# The node this command created. Kept so undo/redo stay id-stable (see header).
# 本命令创建的节点。保留它以保证撤销 / 重做时 id 稳定（见头部说明）。
var _gpNode: GPPIDNode = null

# Machine-readable reason the command refused, mirroring GPConnectEdgeCommand.gpRefusal — the
# caller (GPEditService) copies it into gpLastRefusal for the status bar.
# 命令拒绝执行的机器可读原因，与 GPConnectEdgeCommand.gpRefusal 一致 —— 调用方（GPEditService）
# 把它抄进 gpLastRefusal 供状态栏显示。
var gpRefusal: String = ""


# Id of the created node, for the caller to select it right after attaching. Empty before
# gpExecute() has run.
# 所创建节点的 id，供调用方在挂载后立即选中它。gpExecute() 未运行时为空。
var gpCreatedId: String:
	get: return _gpNode.gpInstanceId if _gpNode != null else ""


# Build the command. gpInParentUid is the host, gpInAnchor the anchor name on it.
# 构造命令：gpInParentUid 为宿主，gpInAnchor 为其上的锚点名。
func _init(gpInSymbolId: String, gpInParentUid: String, gpInAnchor: String,
		gpInTag: String = "", gpInOffset: Vector2 = Vector2.ZERO,
		gpInAngleDeg: float = 0.0) -> void:
	gpSymbolId = gpInSymbolId
	gpParentUid = gpInParentUid
	gpAnchor = gpInAnchor
	gpTag = gpInTag
	gpMountOffset = gpInOffset
	gpMountAngleDeg = gpInAngleDeg
	gpLabel = "添加附件"


# Create (first run) or re-add (redo) the mounted node.
# 首次运行时创建节点，重做时重新加入。
#
# Refuses when the host is not on this sheet: an attachment that cannot find its host is exactly
# the "执行机构浮在阀门旁" defect this feature exists to remove, so it must not be created at all.
# 宿主不在本图纸上时拒绝：找不到宿主的附件正是本功能要消灭的「执行机构浮在阀门旁」缺陷，
# 故根本不应创建。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	gpRefusal = ""
	if gpCtx == null or not gpCtx.gpIsReady():
		return false
	if gpParentUid == "" or gpCtx.gpGraph.gpGetNode(gpParentUid) == null:
		# PREFIX-FREE token, exactly like GPConnectEdgeCommand's "edge_self_loop": the "attach."
		# namespace is added by GPCanvasEditFacade.gpReportRefusal(). Carrying the namespace here
		# as well would resolve "attach.attach.no_host" — a MISSING key, which gpTr() renders as
		# raw text in the status bar instead of raising an error.
		# **不带前缀**的记号，与 GPConnectEdgeCommand 的 "edge_self_loop" 完全一致："attach."
		# 命名空间由 GPCanvasEditFacade.gpReportRefusal() 添加。若在此连命名空间一起带，
		# 会解析成 "attach.attach.no_host" —— 一个**缺失**的键，gpTr() 不会报错，
		# 而是把裸键名显示到状态栏。
		gpRefusal = "no_host"
		return false
	if _gpNode == null:
		# "n" (lower case) is the project-wide node-id prefix — see GPAddNodeCommand.
		# "n"（小写）是全项目统一的节点 id 前缀 —— 见 GPAddNodeCommand。
		var gpId: String = gpCtx.gpIds.gpNext("n")
		var gpTagToUse: String = gpTag
		if gpTagToUse == "" and gpCtx.gpTags != null:
			gpCtx.gpTags.gpGraph = gpCtx.gpGraph
			gpTagToUse = gpCtx.gpTags.gpNextTag(GPSymbolLibrary.gpFindById(gpSymbolId))
		# Position stays ZERO on purpose: it is derived from the mount chain, never read.
		# 位置刻意保持 ZERO：它由挂载父链推导，从不被读取。
		_gpNode = gpCtx.gpGraph.gpNewNode(gpId, gpSymbolId, gpTagToUse, Vector2.ZERO)
		_gpNode.gpParentUid = gpParentUid
		_gpNode.gpMountAnchor = gpAnchor
		_gpNode.gpMountOffset = gpMountOffset
		_gpNode.gpMountAngleDeg = gpMountAngleDeg
		# Auto part numbering (the user's "M1 / M2 per host, never repeated" rule): a numbered part
		# that arrives without its number property is minted the next free one among the host's
		# OTHER children. The node is not in the graph yet, so it can never number against itself.
		# 部件自动编号（用户的「每台宿主内 M1 / M2、绝不重复」规则）：带编号契约而**未带编号值**
		# 的部件，取宿主其余子件中的下一个空号。此刻节点尚未入图，故绝不会与自己比较。
		var gpChildDef: GPSymbolDef = GPSymbolLibrary.gpFindById(gpSymbolId)
		if gpChildDef != null and gpChildDef.gpPartTagKey != "":
			var gpExisting: String = str(_gpNode.gpProps.get(gpChildDef.gpPartTagKey, ""))
			if gpExisting.strip_edges() == "":
				_gpNode.gpProps[gpChildDef.gpPartTagKey] = GPMountResolver.gpNextPartTag(
					gpCtx.gpGraph, gpChildDef, gpParentUid)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRegister(_gpNode.gpInstanceId, _gpNode.gpTag)
	gpCtx.gpGraph.gpAddNode(_gpNode)
	return true


# Remove the node again. Its edges are NOT removed: a freshly attached child has none, and
# removing any would lose user work on undo (same rule as GPAddNodeCommand).
# 再次移除该节点。不删除其关联边：刚挂载的子件本无边，且删边会让用户在撤销时丢工作
# （与 GPAddNodeCommand 同一规则）。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpNode == null:
		return
	gpCtx.gpGraph.gpRemoveNode(_gpNode.gpInstanceId)
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpRelease(_gpNode.gpInstanceId)


# Re-add the very same node object, preserving its id.
# 重新加入同一个节点对象，保持其 id 不变。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if _gpNode == null:
		gpExecute(gpCtx)
		return
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	gpCtx.gpGraph.gpAddNode(_gpNode)
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpRegister(_gpNode.gpInstanceId, _gpNode.gpTag)
