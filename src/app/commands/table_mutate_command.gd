class_name GPTableMutateCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Stage 3 (S3): ONE undo step for a grid-table STRUCTURE change (insert/delete a row or a
# column). Such an operation rewrites several props at once — the two CSVs AND every cell
# key from the touched index onward — so N gpSetProperty calls would leave N-1 intermediate
# undo states that never existed on screen (the exact disease GPBatchSetPropertyCommand's
# header describes for selection batches).
# 阶段 3（S3）：grid 表格**结构**变更（插入/删除一行或一列）的**一个**撤销步。这类操作
# 一口气改写多个属性 —— 两个 CSV 以及被触下标之后的**全部**格键 —— 若拆成 N 条
# gpSetProperty 会留下 N-1 个屏幕上从未存在过的中间撤销态（正是 GPBatchSetPropertyCommand
# 文件头对选择批量所描述的同一病症）。
#
# Snapshot shape / 快照形态：the command carries the FULL before/after props maps (a table's
# props are small; wholesale snapshots stay honest and trivially correct). Pure before→after
# computation lives in GPSymbolGeneratorRegistry.gpMutatedProps (headless-testable); this
# command only swaps snapshots.
# 命令携带**完整**的 before/after props 快照（表格属性很小；整体快照简单且显然正确）。
# before→after 的纯计算在 GPSymbolGeneratorRegistry.gpMutatedProps（可 headless 测试）；
# 本命令只负责交换快照。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var _gpId: String = ""
var _gpBefore: Dictionary = {}
var _gpAfter: Dictionary = {}


func _init(gpInId: String, gpBeforeIn: Dictionary, gpAfterIn: Dictionary) -> void:
	_gpId = gpInId
	_gpBefore = gpBeforeIn.duplicate(true)
	_gpAfter = gpAfterIn.duplicate(true)
	gpLabel = "编辑表格结构"


# Swap in the "after" snapshot. The equal-snapshot (no-op) check lives in the caller
# (GPEditService) so a refused/guarded menu action leaves no phantom undo step.
# 换入 after 快照。快照相等的无操作判定在调用方（GPEditService）——
# 被守卫拒绝的菜单动作不留幽灵撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return false
	_gpSwap(gpN, _gpAfter)
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


# Swap back the "before" snapshot — every affected key (the union of both snapshots) is
# erased then rewritten, so keys that EXISTED only before come back and keys that exist
# only after disappear. A per-key diff would drift; the union cannot.
# 换回 before 快照 —— 受影响键（两份快照的并集）先删后写：只在 before 里存在的键会回来、
# 只在 after 里存在的键会消失。逐键 diff 会漂移；并集不会。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	_gpSwap(gpN, _gpBefore)
	gpCtx.gpGraph.gpGraphChanged.emit()


# One snapshot application: erase the union of both snapshots' keys, then write the
# requested snapshot verbatim.
# 一次快照应用：删掉两份快照键的并集，再按给定快照原样写入。
func _gpSwap(gpN: GPPIDNode, gpSnapshot: Dictionary) -> void:
	var gpKeys: Dictionary = {}
	for gpK in _gpBefore:
		gpKeys[gpK] = true
	for gpK in _gpAfter:
		gpKeys[gpK] = true
	for gpK in gpKeys:
		gpN.gpProps.erase(gpK)
	for gpK in gpSnapshot:
		gpN.gpProps[gpK] = gpSnapshot[gpK]
