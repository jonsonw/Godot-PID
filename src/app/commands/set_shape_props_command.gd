class_name GPSetShapePropsCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Edit the editable fields of ONE annotation shape (name / layer / props / colour) as a single
# undoable step.
# 把一个注释图形的可编辑字段（名称 / 图层 / 属性 / 墨色）作为一步可撤销的编辑来改。
#
# Why a dedicated command and not "mutate the object directly" / 为何专用命令而非直接改对象：
# Shapes live in the sheet's flat shape layer and carry no id, so the UI can only hand over an
# index (see GPDeleteShapesCommand for the same reasoning). Writing through a command is what
# makes the inspector's edits undoable at all — before this, a layer change would have been
# silent and permanent, which is exactly the kind of damage the command layer exists to prevent.
# 图形位于图纸的扁平图形层且没有 id，故界面只能交出下标（理由同 GPDeleteShapesCommand）。
# 经命令写入，属性面板的编辑才可撤销 —— 在此之前，改图层会静默且永久，正是命令层要防的破坏。
#
# Snapshot-whole / 整体快照：
# The "before" image is the four field VALUES, not the shape object: redo must replay the edited
# values onto whatever object sits at the index now, and undo must put back exactly what the four
# fields held. Values are plain (String / Dictionary / Color), so the snapshot stays cheap.
# 「之前」存的是四个字段的**值**，而非图形对象：重做要把编辑值重放到该下标当前的对象上，
# 撤销要精确还原四字段当时的内容。值都是简单的（String / Dictionary / Color），快照很便宜。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Shape index inside GPPIDGraph.gpShapes.
# 图形在 GPPIDGraph.gpShapes 中的下标。
var _gpIdx: int = -1

# Field values to write, keyed by the GPShape field name.
# 待写入的字段值，按 GPShape 字段名索引。
var _gpValues: Dictionary = {}

# Previous values, captured on the first execute so undo is exact.
# 先前值，首次执行时捕获，使撤销精确。
var _gpBefore: Dictionary = {}

# Whether the previous values have been captured (a command instance may execute more than once
# through redo, and only the FIRST execute may snapshot).
# 是否已捕获先前值（同一命令实例可能经重做多次执行，只有**首次**执行可以快照）。
var _gpSnapped: bool = false


# Build from a shape index and the subset of fields to change.
# 由图形下标与待改字段子集构造。
func _init(gpInIdx: int, gpInValues: Dictionary) -> void:
	_gpIdx = gpInIdx
	_gpValues = gpInValues.duplicate(true)
	gpLabel = "改图形属性"


# Write the values. Returns false when the index is stale or nothing actually differs — a no-op
# must not create a phantom undo step.
# 写入字段。下标失效或实际无变化时返回 false —— 空操作绝不能产生幽灵撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	if _gpIdx < 0 or _gpIdx >= gpCtx.gpGraph.gpShapes.size():
		return false
	var gpS: GPShape = gpCtx.gpGraph.gpShapes[_gpIdx]
	if gpS == null:
		return false
	if not _gpSnapped:
		_gpSnapped = true
		_gpBefore = _gpSnapshot(gpS)
	var gpChanged: bool = false
	for gpKey in _gpValues.keys():
		if _gpDiffers(gpS, str(gpKey), _gpValues[gpKey]):
			gpChanged = true
			break
	if not gpChanged and _gpHasAll(gpS):
		return false
	_gpApply(gpS, _gpValues)
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


# Put the captured values back.
# 把捕获的值放回去。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	if _gpIdx < 0 or _gpIdx >= gpCtx.gpGraph.gpShapes.size():
		return
	var gpS: GPShape = gpCtx.gpGraph.gpShapes[_gpIdx]
	if gpS == null:
		return
	_gpApply(gpS, _gpBefore)
	gpCtx.gpGraph.gpGraphChanged.emit()


# The four editable fields of one shape, as a dictionary.
# 一个图形的四个可编辑字段（字典形式）。
func _gpSnapshot(gpS: GPShape) -> Dictionary:
	return {
		"gpName": gpS.gpName,
		"gpLayer": gpS.gpLayer,
		"gpProps": gpS.gpProps.duplicate(true),
		"gpColor": gpS.gpColor,
	}


# Apply a value dictionary onto a shape. Unknown keys are IGNORED rather than pushed into
# gpProps: the inspector's field set is the contract, and a typo must not silently create a
# property nobody reads.
# 把值字典写到图形上。未知键**忽略**而不是塞进 gpProps：面板的字段集就是契约，
# 拼错一个键不得静默造出一条无人读取的属性。
func _gpApply(gpS: GPShape, gpVals: Dictionary) -> void:
	if gpVals.has("gpName"):
		gpS.gpName = str(gpVals["gpName"])
	if gpVals.has("gpLayer"):
		gpS.gpLayer = str(gpVals["gpLayer"])
	if gpVals.has("gpColor"):
		gpS.gpColor = gpVals["gpColor"] as Color
	if gpVals.has("gpProps"):
		gpS.gpProps = (gpVals["gpProps"] as Dictionary).duplicate(true)


func _gpDiffers(gpS: GPShape, gpKey: String, gpVal: Variant) -> bool:
	match gpKey:
		"gpName":
			return gpS.gpName != str(gpVal)
		"gpLayer":
			return gpS.gpLayer != str(gpVal)
		"gpColor":
			return gpS.gpColor != (gpVal as Color)
		"gpProps":
			return gpS.gpProps != (gpVal as Dictionary)
		_:
			return false


# True when every requested key already holds its requested value (i.e. the edit would be a
# no-op even though individual comparisons were skipped).
# 当每个请求的键都已持有其目标值时返回 true（即该编辑是空操作，尽管逐项比较被跳过）。
func _gpHasAll(gpS: GPShape) -> bool:
	for gpKey in _gpValues.keys():
		if _gpDiffers(gpS, str(gpKey), _gpValues[gpKey]):
			return false
	return true
