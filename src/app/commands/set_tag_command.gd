class_name GPSetTagCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Change one instance's 位号 (tag) — M11.
# 修改某个实例的位号（M11）。
#
# Why this is a command and not a direct write / 为何要成为命令而非直接写入：
#   the tag ends up in the DCS point list and on the physical nameplate. A typo must be
#   undoable in one step, and a duplicate must be REFUSED rather than silently suffixed —
#   a silently renamed tag ships a drawing that no longer matches the plant.
#   位号最终会出现在 DCS 点表与现场标牌上。打错必须一步可撤销，重复必须**拒绝**
#   而非静默加后缀 —— 静默改名的图纸到了现场就与装置对不上。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var _gpId: String = ""
var _gpNewTag: String = ""
var _gpOldTag: String = ""


func _init(gpInId: String, gpInTag: String) -> void:
	_gpId = gpInId
	_gpNewTag = gpInTag
	gpLabel = "修改位号"


# Apply the tag. Returns false when the node is gone, nothing changes, or the tag is already
# taken by another instance (the registry owns project-wide uniqueness).
# 应用位号。节点不存在、无实际变化，或位号已被其他实例占用时返回 false
#（工程级唯一性由注册表负责）。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return false
	var gpNew: String = _gpNewTag.strip_edges()
	if gpN.gpTag == gpNew:
		return false
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpGraph = gpCtx.gpGraph
		# gpRegister releases any previous binding for this id first, so register == rename.
		# gpRegister 会先注销该 id 的旧绑定，故「登记」即「改名」。
		if not gpCtx.gpTags.gpRegister(_gpId, gpNew).gpIsOk():
			return false
	_gpOldTag = gpN.gpTag
	gpN.gpTag = gpNew
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpTag = _gpOldTag
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpGraph = gpCtx.gpGraph
		gpCtx.gpTags.gpRegister(_gpId, _gpOldTag)
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpTag = _gpNewTag
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpGraph = gpCtx.gpGraph
		gpCtx.gpTags.gpRegister(_gpId, _gpNewTag)
	gpCtx.gpGraph.gpGraphChanged.emit()
