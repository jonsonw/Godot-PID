class_name GPSetEdgeTagCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Rename one edge's line number (P3). Used by the double-click tag editor.
# 修改一条边的管线号（P3）。由双击编号编辑器调用。
#
# Duplicate numbers are NOT refused / 重号不作拒绝：
#   Two branches legitimately carry the same line number on a real P&ID, so refusing would be
#   wrong. The caller surfaces a status-bar warning and sets gpAttrs["tag_manual"], which makes
#   a future "renumber all" skip this edge instead of overwriting a deliberate choice.
#   真实 P&ID 上两条支管完全可以同号，故拒绝是错的。调用方给出状态栏警告并置
#   gpAttrs["tag_manual"]，使将来的「全部重新编号」跳过本边，而非覆盖一次刻意的选择。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpEdgeId: String = ""
var gpNewTag: String = ""

# Previous tag, captured at execute time so undo is exact.
# 执行时捕获的原位号，使撤销精确。
var _gpOldTag: String = ""
var _gpHadManual: bool = false


func _init(gpInEdgeId: String, gpInNewTag: String) -> void:
	gpEdgeId = gpInEdgeId
	gpNewTag = gpInNewTag
	gpLabel = "修改管线号"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null or gpE.gpTag == gpNewTag:
		return false
	_gpOldTag = gpE.gpTag
	_gpHadManual = bool(gpE.gpAttrs.get("tag_manual", false))
	gpE.gpTag = gpNewTag
	# A hand-typed number is a deliberate choice: remember it so renumbering leaves it alone.
	# 手工输入的号是刻意选择：记住它，使重新编号时不碰它。
	if gpNewTag != "":
		gpE.gpAttrs["tag_manual"] = true
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	gpE.gpTag = _gpOldTag
	if _gpHadManual:
		gpE.gpAttrs["tag_manual"] = true
	else:
		gpE.gpAttrs.erase("tag_manual")
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
