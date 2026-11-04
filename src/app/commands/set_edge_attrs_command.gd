class_name GPSetEdgeAttrsCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Blind-write SEVERAL attributes on ONE edge as a single undo step. null = CLEAR that key
# (same contract as GPSetEdgeAttrCommand). Unlike GPSetLineAttrsCommand this NEVER touches
# the line number: the cross-sheet inherit feature (user feedback 2026-11-04, round 2) uses
# it to copy a source edge's attribute block onto the B-side continuation edge, whose number
# must stay the inherited one instead of being re-rendered from rules.
# 一个撤销步内盲写**多条**边属性。null = 清除该键（与 GPSetEdgeAttrCommand 同契约）。与
# GPSetLineAttrsCommand 不同，它**绝不**触碰管线号：跨图纸继承（用户反馈 2026-11-04 第二轮）
# 用它把源端边的属性块拷到 B 端延续边 —— 延续段的号必须保持继承值，而不是按规则重渲染。
#
# WHY NOT N × GPSetEdgeAttrCommand / 为何不是 N 次单键命令：
# Toggling the inherit checkbox off snapshots the whole source attribute block; propagation
# copies it again on every source edit. Either as N undo steps would make Ctrl+Z walk back
# through a half-synced peer. One command, one step, all-or-nothing.
# 取消继承勾选时快照的是整个源端属性块；传播在源端每次编辑后又整块拷贝。任其拆成 N 个撤销步，
# Ctrl+Z 会走过一堆「同步了一半」的对端。一条命令、一个撤销步、要么全成要么不动。
#
# Deliberately SILENT / 刻意不发信号：
# this command IS the downstream end of attribute propagation. The shell listens for
# gpEdgeAttrsCommitted on SOURCE edits; if this command emitted the same signal, each
# propagated write would fan out again and never terminate. It emits nothing.
# 本命令**就是**属性传播的下游端。外壳监听的是**源端**编辑的 gpEdgeAttrsCommitted；若本命令
# 也发同一信号，每次传播写入都会再次扇出、永不收敛。故它什么都不发。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpEdgeId: String = ""
var gpValues: Dictionary = {}

# Per-key "before" state, captured at first execute: prior value (when the key existed) and
# whether it existed at all (so undo can re-erase keys it created).
# 逐键的「之前」状态，首次执行时捕获：原值（键存在时）与键是否存在（使撤销能删除它新造的键）。
var _gpOldValues: Dictionary = {}
var _gpHadKeys: Dictionary = {}
var _gpPlanned: bool = false


func _init(gpInEdgeId: String, gpInValues: Dictionary) -> void:
	gpEdgeId = gpInEdgeId
	gpValues = gpInValues.duplicate(true)
	gpLabel = "同步延续段属性"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null or gpValues.is_empty():
		return false
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return false
	if not _gpPlanned:
		for gpKey in gpValues.keys():
			var gpK: String = str(gpKey)
			_gpHadKeys[gpK] = gpE.gpAttrs.has(gpK)
			if _gpHadKeys[gpK]:
				_gpOldValues[gpK] = gpE.gpAttrs[gpK]
		_gpPlanned = true
	var gpChanged: bool = false
	for gpKey in gpValues.keys():
		var gpK: String = str(gpKey)
		var gpV: Variant = gpValues[gpKey]
		if gpV == null:
			# null = clear; clearing an absent key changes nothing.
			# null = 清除；清除不存在的键不做任何事。
			if _gpHadKeys[gpK]:
				gpE.gpAttrs.erase(gpK)
				gpChanged = true
		else:
			if _gpHadKeys[gpK] and _gpSame(_gpOldValues[gpK], gpV):
				continue
			gpE.gpAttrs[gpK] = gpV
			gpChanged = true
	if not gpChanged:
		# Nothing actually differed: report failure so callers do not stack a no-op undo step.
		# 实际无差异：报失败，使调用方不会压入一个空转的撤销步。
		return false
	gpCtx.gpGraph.gpNotifyChanged()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCtx.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	for gpKey in _gpHadKeys.keys():
		var gpK: String = str(gpKey)
		if bool(_gpHadKeys[gpK]):
			gpE.gpAttrs[gpK] = _gpOldValues[gpK]
		else:
			gpE.gpAttrs.erase(gpK)
	gpCtx.gpGraph.gpNotifyChanged()


func gpRedo(gpCtx: GPCommandContext) -> void:
	# The plan is captured; redo replays the same writes.
	# 方案已捕获；重做重放同一批写入。
	gpExecute(gpCtx)


# Variant equality that survives arrays: "==" already compares Array/Dictionary by value in
# GDScript, so a plain test is correct here.
# 能正确处理数组的 Variant 相等判定：GDScript 中 "==" 对 Array/Dictionary 本就按值比较，
# 此处直接用即可。
func _gpSame(gpA: Variant, gpB: Variant) -> bool:
	return gpA == gpB
