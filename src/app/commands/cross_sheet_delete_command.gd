class_name GPCrossSheetDeleteCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Delete ONE cross-sheet connection ENTIRELY, as ONE undo step (ADR-43 deletion case ① /
# plan §2.5): the link leaves the container table, and BOTH connector symbols (with their
# touching edges) leave their sheets. Deleting one flag while its twin survived would leave a
# "?" on the peer drawing — the plan names that the worst failure mode, so the user's single
# "delete" on a confirmed dialog removes the whole pair.
# 把**一条**跨图纸连接整个删掉，作为**一个撤销步**（ADR-43 删除情形① / 方案 §2.5）：link
# 离开容器表，**两个**连接符（连同其上的边）离开各自图纸。只删一面会让对端图上留下 "？" ——
# 方案点名这是最坏的失败模式，故用户在确认对话框上按下的那一次「删除」成对移除。
#
# Undo restores in reverse: both node halves first, then the link back at its old index.
# Redo re-deletes through the SAME composed halves.
# 撤销按逆序恢复：先两半节点，再把 link 插回原下标。重做经**同样的**组合半步再删。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpLink: GPOffPageLink = null
var gpLinks: Array[GPOffPageLink] = []
var gpPeerGraph: GPPIDGraph = null

# The two node halves; each also removes the edges touching its nodes.
# 两个节点半步；各自连带删除其节点上的边。
var _gpLocalHalf: GPDeleteNodesCommand = null
var _gpPeerHalf: GPDeleteNodesCommand = null

var _gpLinkAt: int = -1
var _gpLocalNodeIds: Array[String] = []
var _gpPeerNodeIds: Array[String] = []


func _init(gpInLink: GPOffPageLink, gpInLocalNodeIds: Array[String],
		gpInPeerNodeIds: Array[String], gpInPeerGraph: GPPIDGraph,
		gpInLinks: Array[GPOffPageLink], gpInLookup: Callable = Callable()) -> void:
	gpLink = gpInLink
	gpLinks = gpInLinks
	gpPeerGraph = gpInPeerGraph
	_gpLocalNodeIds = gpInLocalNodeIds.duplicate()
	_gpPeerNodeIds = gpInPeerNodeIds.duplicate()
	# Each half is built once and reused for undo/redo (the same contract GPDeleteSelection uses).
	# 每半步构建一次，撤销/重做复用（与 GPDeleteSelection 相同的契约）。
	if not _gpLocalNodeIds.is_empty():
		_gpLocalHalf = GPDeleteNodesCommand.new(_gpLocalNodeIds, gpInLookup)
	if not _gpPeerNodeIds.is_empty():
		_gpPeerHalf = GPDeleteNodesCommand.new(_gpPeerNodeIds, gpInLookup)
	gpLabel = "删除跨图纸连接"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpLink == null or not gpCtx.gpIsReady():
		return false
	# Guard the redo path: a link already gone means the container moved on without us.
	# 守护重做路径：link 已不在表中说明容器已自行变化。
	if not gpLinks.has(gpLink):
		return false
	if _gpLocalHalf != null and not _gpLocalHalf.gpExecute(gpCtx):
		return false
	if _gpPeerHalf != null:
		# The peer half runs against the PEER graph with the SAME id/tag registries (ids are
		# minted only by the create path; deletion mints nothing, so sharing is safe).
		# 对端半步在**对端图**上执行，共享同一 id/位号注册表（id 只由创建路径铸号；删除
		# 不铸号，故共享安全）。
		var gpPeerCtx: GPCommandContext = GPCommandContext.new(gpPeerGraph, gpCtx.gpIds,
			gpCtx.gpTags)
		if not _gpPeerHalf.gpExecute(gpPeerCtx):
			_gpLocalHalf.gpUndo(gpCtx)
			return false
	_gpLinkAt = gpLinks.find(gpLink)
	gpLinks.remove_at(_gpLinkAt)
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	# Reverse order: link back first is WRONG (a node would still be missing while the flag
	# already renders) — nodes back first, then the link.
	# 逆序：先还 link 是**错**的（旗标已渲染而节点还缺）—— 先节点，后 link。
	if _gpPeerHalf != null and gpPeerGraph != null:
		_gpPeerHalf.gpUndo(GPCommandContext.new(gpPeerGraph, gpCtx.gpIds, gpCtx.gpTags))
	if _gpLocalHalf != null:
		_gpLocalHalf.gpUndo(gpCtx)
	if gpLink != null and gpLinks != null and not gpLinks.has(gpLink):
		var gpAt: int = _gpLinkAt if (_gpLinkAt >= 0 and _gpLinkAt <= gpLinks.size()) \
			else gpLinks.size()
		gpLinks.insert(gpAt, gpLink)


func gpRedo(gpCtx: GPCommandContext) -> void:
	if _gpLocalHalf != null:
		_gpLocalHalf.gpRedo(gpCtx)
	if _gpPeerHalf != null and gpPeerGraph != null:
		_gpPeerHalf.gpRedo(GPCommandContext.new(gpPeerGraph, gpCtx.gpIds, gpCtx.gpTags))
	# Redo deletes the link again; undo already put it back at its old index, so remove by
	# identity wherever it now sits.
	# 重做把 link 再删一次；撤销已把它放回原下标，故按身份在当前位置移除。
	if gpLink != null and gpLinks != null:
		var gpAt: int = gpLinks.find(gpLink)
		if gpAt >= 0:
			gpLinks.remove_at(gpAt)
