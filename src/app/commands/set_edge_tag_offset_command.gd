class_name GPSetEdgeTagOffsetCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Move one edge's line number off its automatic placement (and back) .
# 把一条边的管线号移离其自动落位处（以及移回）。
#
# WHY A DEDICATED COMMAND instead of the generic GPSetEdgeAttrCommand / 为何不用通用的
# GPSetEdgeAttrCommand：
# The storage POLICY is not "put this key/value in the dict" — a zero offset must ERASE the key
# so an un-dragged number never leaves a residue in the file (see GPPIDEdge.gpSetTagOffset). The
# generic setter would happily write [0, 0] and change every saved sheet. Routing the write
# through the edge's own accessor keeps that rule in exactly one place, and it gives the undo
# stack an honest label ("移动管线号") instead of a generic "修改连线属性".
# 存储**策略**不是「把键值塞进字典」—— 零偏移必须**删除**该键，使未被拖动过的编号绝不在文件中留下
# 残留（见 GPPIDEdge.gpSetTagOffset）。通用 setter 会欣然写入 [0, 0]，从而改动每一张已保存的图纸。
# 把写入经该边自身的存取器，使这条规则只存在于一处，并给撤销栈一个诚实的标签（「移动管线号」），
# 而非泛泛的「修改连线属性」。
#
# The offset is in WORLD units (mm), never pixels, so the number keeps its place on the sheet
# across zoom changes and printing.
# 偏移以**世界单位（mm）**计，绝不用像素，故编号在缩放变化与出图之间保持其在图纸上的位置。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Edge whose line number is moved. / 被移动管线号的边。
var _gpEdgeId: String = ""

# New offset (world mm). / 新偏移（世界 mm）。
var _gpNew: Vector2 = Vector2.ZERO

# Offset before the change, captured for undo. / 改动前的偏移，捕获以供撤销。
var _gpOld: Vector2 = Vector2.ZERO


func _init(gpInEdgeId: String, gpInOffset: Vector2) -> void:
	_gpEdgeId = gpInEdgeId
	_gpNew = gpInOffset
	gpLabel = "移动管线号"


# Apply the offset. Returns false when the edge is gone or nothing actually changes, so a press
# that never moved produces no undo step.
# 应用偏移。边不存在或实际无变化时返回 false，使「按下但没动」不产生撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null:
		return false
	_gpOld = gpE.gpTagOffset()
	if _gpOld == _gpNew:
		return false
	gpE.gpSetTagOffset(_gpNew)
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null:
		return
	gpE.gpSetTagOffset(_gpOld)
	gpCtx.gpGraph.gpGraphChanged.emit()


# Re-apply. Safe to re-execute: the command stores no allocated id and the accessor is
# idempotent, so the base class default would work too — overridden only to keep the write
# path explicit next to its undo.
# 重新应用。重复执行是安全的：本命令不分配 id，且存取器幂等，故基类默认实现本也可行 ——
# 覆写只是为了让「写入路径」与其撤销并排呈现。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(_gpEdgeId)
	if gpE == null:
		return
	gpE.gpSetTagOffset(_gpNew)
	gpCtx.gpGraph.gpGraphChanged.emit()
