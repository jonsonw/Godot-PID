class_name GPUnlinkOffPageCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# UNLINK one cross-sheet connection (U3 inspector action row, user feedback 2026-11-04):
# the link leaves the container table and BOTH connector symbols go back to the honest
# "unlinked" state — their GP_KEY_LINK_ID prop is cleared, the flags themselves STAY on
# their sheets (unlike GPCrossSheetDeleteCommand, which removes the pair entirely).
# One undo step: undo re-inserts the link at its old index and re-seats both props.
# **断开**一条跨图纸连接（U3 属性面板动作行，用户反馈 2026-11-04）：link 离开容器表，
# **两个**连接符回到诚实的「未连接」态 —— GP_KEY_LINK_ID 属性被清除，旗标本体**留在**
# 各自图纸上（与 GPCrossSheetDeleteCommand 整对移除不同）。一个撤销步：撤销把 link 插回
# 原下标并把两端属性复位。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpLink: GPOffPageLink = null
var gpLinks: Array[GPOffPageLink] = []
var gpLocalGraph: GPPIDGraph = null
var gpPeerGraph: GPPIDGraph = null

var _gpAt: int = -1
var _gpLocalId: String = ""
var _gpPeerId: String = ""


func _init(gpInLink: GPOffPageLink, gpInLinks: Array[GPOffPageLink],
		gpInLocalGraph: GPPIDGraph, gpInPeerGraph: GPPIDGraph) -> void:
	gpLink = gpInLink
	gpLinks = gpInLinks
	gpLocalGraph = gpInLocalGraph
	gpPeerGraph = gpInPeerGraph
	if gpLink != null:
		_gpLocalId = str(gpLink.gpA.get(GPOffPageLink.GP_KEY_NODE, ""))
		_gpPeerId = str(gpLink.gpB.get(GPOffPageLink.GP_KEY_NODE, ""))
	gpLabel = "断开跨图纸连接"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpLink == null or not gpCtx.gpIsReady():
		return false
	# Guard the redo path: a link already gone means the container moved on without us.
	# 守护重做路径：link 已不在表中说明容器已自行变化。
	if not gpLinks.has(gpLink):
		return false
	_gpApply()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpLink == null or not gpCtx.gpIsReady():
		return
	if _gpAt >= 0 and _gpAt <= gpLinks.size():
		gpLinks.insert(_gpAt, gpLink)
	_gpSetLinked(gpLocalGraph, _gpLocalId, true)
	_gpSetLinked(gpPeerGraph, _gpPeerId, true)


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpLink == null or not gpCtx.gpIsReady():
		return
	_gpApply()


# The shared execute/redo mutation: pull the link from the table, clear both props.
# 执行 / 重做共用的变更：link 移出表、清除两端属性。
func _gpApply() -> void:
	_gpAt = gpLinks.find(gpLink)
	gpLinks.remove_at(_gpAt)
	_gpSetLinked(gpLocalGraph, _gpLocalId, false)
	_gpSetLinked(gpPeerGraph, _gpPeerId, false)


# Seat (or clear) the link reference on ONE end's connector; a missing node is tolerated —
# the sheet may have moved on (the peer half follows the same tolerance as the delete halves).
# 在一端的连接符上落（或清）link 引用；节点缺失可容忍 —— 图纸可能已自行变化（对端半步与
# 删除半步遵循同样的容忍）。
func _gpSetLinked(gpGraph: GPPIDGraph, gpNodeId: String, gpLinked: bool) -> void:
	if gpGraph == null or gpNodeId == "":
		return
	var gpNode: GPPIDNode = gpGraph.gpGetNode(gpNodeId)
	if gpNode == null:
		return
	if gpLinked:
		gpNode.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = gpLink.gpInstanceId
	else:
		gpNode.gpProps.erase(GPOffPageLink.GP_KEY_LINK_ID)
