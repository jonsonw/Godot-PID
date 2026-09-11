class_name GPSetLabelOffsetCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Move one instance's tag relative to its symbol (M10b).
# 移动一个实例上标签相对其图元的位置（M10b）。
#
# The offset is stored NORMALISED (1.0 = half the envelope), never in pixels, so the tag keeps
# the same visual position when the user zooms, switches DPI or prints to PDF.
# 偏移以**归一化**方式存储（1.0 = 半个包络），绝不是像素，使用户缩放、切换 DPI
# 或打印 PDF 时标签保持同一视觉位置。
#
# Sentinel semantics / 哨兵语义:
#   Vector2.INF (GPLabelAnchor.GP_OFFSET_UNSET) means "no instance override — follow the type
#   layer". It is how a double-click reset is represented, and the model refuses to serialise
#   it (INF has no JSON form), so a reset simply removes the key from the file.
#   Vector2.INF（GPLabelAnchor.GP_OFFSET_UNSET）意为「无实例覆盖 —— 跟随类型层」。
#   双击复位即以此表示；模型拒绝序列化它（INF 无 JSON 形式），故复位等于从文件中删掉该键。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Node whose tag is moved. / 被移动标签的节点。
var _gpId: String = ""

# New normalised offset. / 新的归一化偏移。
var _gpNew: Vector2 = Vector2.ZERO

# Offset before the change, captured for undo. / 改动前的偏移，捕获以供撤销。
var _gpOld: Vector2 = Vector2.ZERO


func _init(gpInId: String, gpInOffset: Vector2) -> void:
	_gpId = gpInId
	_gpNew = gpInOffset
	gpLabel = "移动位号"


# Apply the offset. Returns false when the node is gone or nothing actually changes, so a
# press that never moved produces no undo step.
# 应用偏移。节点不存在或实际无变化时返回 false，使「按下但没动」不产生撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return false
	_gpOld = gpN.gpLabelOffset
	if _gpOld == _gpNew:
		return false
	gpN.gpLabelOffset = _gpNew
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpLabelOffset = _gpOld
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpLabelOffset = _gpNew
	gpCtx.gpGraph.gpGraphChanged.emit()
