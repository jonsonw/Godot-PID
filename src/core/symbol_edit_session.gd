class_name GPSymbolEditSession
extends RefCounted

# Copyright © 2026 Jonson Wang
# Transient editing session for ONE symbol inside the isolation editor (Phase 3, M2).
# 隔离编辑器中对「单个图元」的临时编辑会话（Phase 3 · M2）。
# Holds the id under edit, whether it is a brand-new symbol, the builtin it was
# derived from (D3), and a DEEP snapshot of the definition taken at open time so
# we can detect dirtiness and support cancel WITHOUT mutating the live library.
# 持有正在编辑的图元 id、是否为全新图元、所派生的内置图元（D3），以及打开时
# 对定义的「深拷贝」快照——据此判断脏标志并支持取消，而不动活动图元库。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Id of the symbol being edited (stable across the whole session).
# 正在编辑的图元 id（整个会话期间稳定）。
var gpSymbolId: String = ""

# True when editing a brand-new symbol (no existing id in the library yet).
# 编辑全新图元时为 true（库中尚无该 id）。
var gpIsNew: bool = false

# Builtin id this symbol was derived from (D3), empty for a from-scratch symbol.
# 本图元所派生的内置图元 id（D3）；从零新建则为空。
var gpDerivedFrom: String = ""

# Deep snapshot of the definition taken at open time (via GPSymbolDef.gpToDict).
# 打开时对定义的深拷贝快照（经 GPSymbolDef.gpToDict）。
var _gpOriginal: Dictionary = {}

# Whether the working definition differs from the baseline snapshot.
# 工作定义是否偏离基线快照（脏标志）。
var gpDirty: bool = false


# Begin a session for gpDef. gpNewVal marks a never-registered symbol; gpDerived is
# the builtin id when this is a D3 derivation (else "").
# 为 gpDef 开启会话。gpNewVal 标记从未注册的图元；gpDerived 为 D3 派生时的内置 id（否则 ""）。
func gpOpen(gpDef: GPSymbolDef, gpNewVal: bool, gpDerived: String) -> void:
	gpSymbolId = gpDef.gpId
	gpIsNew = gpNewVal
	gpDerivedFrom = gpDerived
	_gpCapture(gpDef)
	gpDirty = false


# Re-capture the current definition as the clean baseline (call after a successful save).
# 把当前定义重新捕获为干净基线（保存成功后调用）。
func gpSnapshot(gpDef: GPSymbolDef) -> void:
	_gpCapture(gpDef)
	gpDirty = false


# Compare gpDef against the baseline; update gpDirty and return it.
# 将 gpDef 与基线比较，更新 gpDirty 并返回。
func gpMarkDirty(gpDef: GPSymbolDef) -> bool:
	gpDirty = not _gpEqual(gpDef.gpToDict(), _gpOriginal)
	return gpDirty


# Rebuild a GPSymbolDef from the baseline snapshot (for cancel / revert).
# 由基线快照重建 GPSymbolDef（用于取消 / 还原）。
func gpOriginalDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpFromDict(_gpOriginal)
	return gpD


# ---- internals / 内部 ----

# Capture gpDef as the current baseline snapshot (deep copy via gpToDict).
# 把 gpDef 捕获为当前基线快照（经 gpToDict 深拷贝）。
func _gpCapture(gpDef: GPSymbolDef) -> void:
	_gpOriginal = gpDef.gpToDict()


# Deep-equal two dictionaries (ports / shape carry nested arrays / dicts).
# 深比较两个字典（ports / shape 含嵌套数组 / 字典）。
func _gpEqual(gpA: Dictionary, gpB: Dictionary) -> bool:
	return var_to_str(gpA) == var_to_str(gpB)
