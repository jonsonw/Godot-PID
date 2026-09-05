class_name GPCanvasSelection
extends RefCounted
# Pure selection-set model for the P&ID canvas (P1-1b).
#
# The canvas keeps TWO mutually-exclusive selection collections on the same sheet:
#   - node annotation "graph" selection:  gpNodeIds (Array[String])  -> selected P&ID symbol instances
#   - annotation "shape" selection:        gpShapeIdx (Array[int])   -> selected free-hand shapes
# Invariant: selecting into ONE collection clears the OTHER (a sheet item is either a node
# instance or a free annotation shape, never both in the same selection gesture).
# A "primary" id is mirrored for single-entity operations (context menus, status, drag target).
#
# This module centralises those invariants (set-clears-other / toggle / erase / clear / primary
# sync / emptiness) so the canvas input handlers delegate one-line calls instead of re-spelling
# the same array dance inline at ~14 sites. It is Control-free and headless-testable.
#
# 纯「画布选择集」模型（P1-1b）。
# 主画布在同一图纸上维护两套互斥选择：
#   - 节点标注「图形」选择：gpNodeIds（Array[String]）→ 选中的 P&ID 图元实例
#   - 注释「图形」选择：    gpShapeIdx（Array[int]） → 选中的自由手绘图形
# 不变式：向任一个集合「设选」会清空另一个（图纸元素要么是图元实例、要么是自由注释图形，
# 一次选择手势不会同时命中两者）。另有 primary 镜像供单实体操作（右键菜单/状态/拖动目标）。
# 本模块集中这些不变式（设选互斥 / toggle / erase / clear / primary 同步 / 空判定），
# 使画布输入处理委托一行调用，而非在约 14 处内联重复同一套数组舞步。无 Control 依赖、可 headless 单测。

# Selected P&ID node instance ids (mutually exclusive with gpShapeIdx).
# 选中的 P&ID 图元实例 id（与 gpShapeIdx 互斥）。
var gpNodeIds: Array[String] = []

# Selected free-hand annotation shape indices (mutually exclusive with gpNodeIds).
# 选中的自由注释图形下标（与 gpNodeIds 互斥）。
var gpShapeIdx: Array[int] = []

# Mirror of the primary (first) selected node id, for single-entity operations.
# primary（首个）选中节点 id 的镜像，供单实体操作使用。
var gpPrimaryNodeId: String = ""


# Whether any entity (node or shape) is selected.
# 是否选中了任一实体（节点或图形）。
func gpHasAny() -> bool:
	return not gpNodeIds.is_empty() or not gpShapeIdx.is_empty()


# Whether exactly one entity is selected (any kind).
# 是否恰好选中一个实体（任意类型）。
func gpIsSingle() -> bool:
	return (gpNodeIds.size() + gpShapeIdx.size()) == 1


# Node selection state, as the live array (for read-heavy hot paths). Callers must not mutate it
# directly; use the gpSetNodes / gpToggleNode helpers so the invariants stay intact.
# 节点选择状态（活数组，供读密集型热路径）。调用方不得直接修改，须经 gpSetNodes/gpToggleNode 保持不变式。
func gpNodes() -> Array[String]:
	return gpNodeIds


# Shape selection state, as the live array (for read-heavy hot paths). Same mutation rule applies.
# 图形选择状态（活数组）。同样的「勿直接改」规则。
func gpShapes() -> Array[int]:
	return gpShapeIdx


# Replace the node selection; this CLEARS any shape selection (mutual exclusion).
# Returns true when the effective node selection actually changed.
# 替换节点选择；会清空图形选择（互斥）。返回节点选择是否实际发生变化。
func gpSetNodes(gpIds: Array[String]) -> bool:
	var gpChanged: bool = not _gpSame(gpNodeIds, gpIds)
	gpNodeIds = gpIds.duplicate()
	gpPrimaryNodeId = gpNodeIds[0] if not gpNodeIds.is_empty() else ""
	if not gpNodeIds.is_empty() and not gpShapeIdx.is_empty():
		gpShapeIdx.clear()
	return gpChanged


# Replace the shape selection; this CLEARS any node selection (mutual exclusion).
# Returns true when the effective shape selection actually changed.
# 替换图形选择；会清空节点选择（互斥）。返回图形选择是否实际发生变化。
func gpSetShapes(gpIdxs: Array[int]) -> bool:
	var gpChanged: bool = not _gpSameShape(gpShapeIdx, gpIdxs)
	gpShapeIdx = gpIdxs.duplicate()
	if not gpShapeIdx.is_empty() and not gpNodeIds.is_empty():
		gpNodeIds.clear()
		gpPrimaryNodeId = ""
	return gpChanged


# Clear both node and shape selection.
# 清空节点与图形选择。
func gpClearAll() -> void:
	var gpHad: bool = gpHasAny()
	gpNodeIds.clear()
	gpShapeIdx.clear()
	gpPrimaryNodeId = ""
	# (gpHad kept only for a caller that wants to know whether redraw is needed.)


# Set ONLY the primary mirror id, leaving both selection arrays untouched. Mirrors the canvas's
# historical gpSelectedId field: it was a pure "current entity" mirror written independently of the
# arrays (e.g. reset to "" on an empty-canvas clear), not a selection mutation.
# 仅设置 primary 镜像 id，不改动两个选择数组。对应画布历史 gpSelectedId 字段语义：它是独立写、
# 与数组解耦的「当前实体」镜像（例如空白处清除时置 ""），并非一次选择变更。
func gpSetPrimary(gpId: String) -> void:
	gpPrimaryNodeId = gpId


# Whether gpId is in the node selection.
# gpId 是否在节点选择中。
func gpHasNode(gpId: String) -> bool:
	return gpNodeIds.has(gpId)


# Whether gpIdx is in the shape selection.
# gpIdx 是否在图形选择中。
func gpHasShape(gpIdx: int) -> bool:
	return gpShapeIdx.has(gpIdx)


# Toggle gpId in the node selection. If gpShift is false the call behaves as gpSetNodes([gpId])
# (single-select clears everything else). If gpShift is true it adds/removes gpId without
# clearing the rest; when nothing was selected before the toggle, gpId becomes the sole pick.
# 在节点选择中切换 gpId。gpShift 为 false 时等价于 gpSetNodes([gpId])（单选清空其余）；
# gpShift 为 true 时仅增删 gpId 而不清空其余；若此前无任何选择，gpId 成为唯一选中。
func gpToggleNode(gpId: String, gpShift: bool) -> void:
	if gpShift:
		if gpNodeIds.has(gpId):
			gpNodeIds.erase(gpId)
		else:
			if gpNodeIds.is_empty() and not gpShapeIdx.is_empty():
				gpShapeIdx.clear()
			gpNodeIds.append(gpId)
		gpPrimaryNodeId = gpNodeIds[0] if not gpNodeIds.is_empty() else ""
	else:
		gpSetNodes([gpId])


# Toggle gpIdx in the shape selection. Same shift semantics as gpToggleNode.
# 在图形选择中切换 gpIdx。shift 语义与 gpToggleNode 相同。
func gpToggleShape(gpIdx: int, gpShift: bool) -> void:
	if gpShift:
		if gpShapeIdx.has(gpIdx):
			gpShapeIdx.erase(gpIdx)
		else:
			if gpShapeIdx.is_empty() and not gpNodeIds.is_empty():
				gpNodeIds.clear()
				gpPrimaryNodeId = ""
			gpShapeIdx.append(gpIdx)
	else:
		gpSetShapes([gpIdx])


# Whether two string arrays hold the same elements in the same order.
# 两个字符串数组是否元素、顺序都相同。
static func _gpSame(gpA: Array[String], gpB: Array[String]) -> bool:
	if gpA.size() != gpB.size():
		return false
	for gpI in range(gpA.size()):
		if gpA[gpI] != gpB[gpI]:
			return false
	return true


# Whether two int arrays hold the same elements in the same order.
# 两个整型数组是否元素、顺序都相同。
static func _gpSameShape(gpA: Array[int], gpB: Array[int]) -> bool:
	if gpA.size() != gpB.size():
		return false
	for gpI in range(gpA.size()):
		if gpA[gpI] != gpB[gpI]:
			return false
	return true
