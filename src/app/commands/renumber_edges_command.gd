class_name GPRenumberCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Renumber every process / utility pipe on the sheet with fresh, never-recycled PL tags (P4).
# 用全新的、绝不回收的 PL 位号重排图纸上每条工艺 / 公用工程管线（P4）。
#
# Edges whose tag was set by hand (gpAttrs["tag_manual"]) are skipped so a deliberate choice is
# never overwritten; signal lines carry no tag by convention and are skipped too. One undo step
# restores every tag and the high-water mark together.
# 手工指定号（gpAttrs["tag_manual"]）的边会被跳过，以免覆盖刻意选择；信号线按惯例不带号也跳过。
# 一次撤销同时恢复全部位号与水位线。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Edge id -> previous tag, captured before renumbering. / 重排前：边 id -> 原位号。
var _gpOldTags: Dictionary = {}

# Previous tag-sequence high-water marks. / 原位号序列水位线。
var _gpOldSeq: Dictionary = {}

# How many edges actually got a new number (for the "nothing to do" check).
# 实际被重排的边数量（用于「无需操作」判定）。
var _gpCount: int = 0


func _init() -> void:
	gpLabel = "重新编号"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	_gpOldTags = {}
	for gpE in gpCtx.gpGraph.gpEdges:
		_gpOldTags[gpE.gpInstanceId] = gpE.gpTag
	_gpOldSeq = gpCtx.gpGraph.gpMeta.get(GPTagGen.GP_META_KEY, {}).duplicate()
	# Fresh sequence: renumbering restarts from PL-1001 and skips any tag still in use
	# (including the hand-set ones we are about to leave alone).
	# 全新序列：从 PL-1001 重启，并跳过仍被占用（含将保留的手工号）的号。
	gpCtx.gpGraph.gpMeta[GPTagGen.GP_META_KEY] = {}
	_gpCount = 0
	for gpE in gpCtx.gpGraph.gpEdges:
		if gpE.gpKind == GPPIDEdge.GP_SIGNAL:
			continue
		if bool(gpE.gpAttrs.get("tag_manual", false)):
			continue
		gpE.gpTag = GPTagGen.gpNextTag(gpCtx.gpGraph, GPTagGen.GP_PIPE_PREFIX)
		_gpCount += 1
	gpCtx.gpGraph.gpGraphChanged.emit()
	return _gpCount > 0


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpE in gpCtx.gpGraph.gpEdges:
		var gpOld = _gpOldTags.get(gpE.gpInstanceId, "")
		if gpOld != null:
			gpE.gpTag = gpOld
	if _gpOldSeq.is_empty():
		gpCtx.gpGraph.gpMeta.erase(GPTagGen.GP_META_KEY)
	else:
		gpCtx.gpGraph.gpMeta[GPTagGen.GP_META_KEY] = _gpOldSeq.duplicate()
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
