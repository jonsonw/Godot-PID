# ============================================================================
# GPSymbolAddShapeCommand — 提交一枚图元到符号工作图形表（M7）
# Commit a finished primitive to the symbol's working shape list (M7).
#
# 与画布 GPAddShapeCommand 同构，但作用于符号的 _gpShapes 数组。保留图形对象本身，故重做重插入
# 同一实例（同几何、同手柄），不会与用户所绘内容漂移。复用 GPCommand 自我求逆的值对象契约。
# Same shape as the canvas GPAddShapeCommand but operates on the symbol's _gpShapes array. The shape
# OBJECT is kept, so redo re-inserts the very same instance (same geometry, same handles) instead of a
# rebuilt copy. Follows the GPCommand self-inverting value-object contract.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolAddShapeCommand
extends GPCommand

# The working shape list (captured by reference). / 工作图形表（按引用捕获）。
var _gpShapes: Array[GPShape] = []
# The shape to add (built by the draw tool before requesting a commit). / 待加入的图形（绘图工具请求提交前构造）。
var _gpShape: GPShape = null


func _init(gpInShapes: Array[GPShape], gpInShape: GPShape) -> void:
	_gpShapes = gpInShapes
	_gpShape = gpInShape
	gpLabel = "绘制图形"


func gpExecute(_gpCtx: GPCommandContext) -> bool:
	if _gpShape == null or _gpShapes.has(_gpShape):
		return false
	_gpShapes.append(_gpShape)
	return true


func gpUndo(_gpCtx: GPCommandContext) -> void:
	if _gpShapes.has(_gpShape):
		_gpShapes.erase(_gpShape)


func gpRedo(_gpCtx: GPCommandContext) -> void:
	if not _gpShapes.has(_gpShape):
		_gpShapes.append(_gpShape)
