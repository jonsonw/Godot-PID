class_name GPCrossSheetSyncCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# Sync a cross-sheet connection's CONTRACT attributes to the peer end, as ONE undoable
# step (ADR-43 / S3, "同步到对端").
# 把跨图纸连接的**契约属性**同步到对端，作为一步可撤销的编辑（ADR-43 / S3「同步到对端」）。
#
# The rule the interaction follows / 交互遵循的规则：
# "modify freely, report every drift" (修改允许、漂移必报). Editing the local end is always
# allowed; the DRC (S4) reports any drift from the link snapshot. This command is what the
# "yes, sync" answer runs: it writes the new values into the link's contract snapshot AND
# into both ends' edges, so the three copies agree again — never silently, always as an
# explicit, undoable step.
# 本端可随意改；与 link 快照的漂移由 DRC（S4）报告。本命令就是「是，同步」这个回答的执行者：
# 它把新值写进 link 的契约快照**并**写入两端的边，使三份副本重新一致 —— 绝不静默，
# 永远是一次显式的、可撤销的步骤。
#
# Contract keys / 契约键:
# Exactly the five fields the plan names for links: pipes carry dn/medium/spec/insulation,
# signals carry signal_type. Anything else a caller passes is deliberately ignored — a
# sync must never smuggle arbitrary keys into edges.
# 恰是方案为 link 点名的五个字段：管道 dn/medium/spec/insulation，信号 signal_type。
# 调用方多传的键被刻意忽略 —— 同步绝不能把任意键偷运进边。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The five contract fields (plan §2.4). One list so DRC (S4) and this command can never
# spell the contract two ways.
# 五个契约字段（方案 §2.4）。单一名单使 DRC（S4）与本命令不可能把契约拼成两种写法。
# Single source of truth moved to the core model (S4): the audit and the command now read
# the SAME list.
# 单一名单上移至 core 模型（S4）：审计与命令从此读**同一份**。
const GP_CONTRACT_KEYS: Array[String] = GPOffPageLink.GP_CONTRACT_KEYS

# The link whose contract snapshot is updated. / 要更新契约快照的 link。
var gpLink: GPOffPageLink = null

# Requested values; only contract keys present here are applied.
# 请求值；仅这里**出现**的契约键会被应用。
var gpValues: Dictionary = {}

# The edges to keep in step (typically the local edge and the peer edge). Null entries
# and dangling ends are tolerated: a link may legitimately have no edge on one side.
# 要保持一致的边（通常是本端边与对端边）。容忍 null 与悬空端：link 的一侧合法地可能没有边。
var gpEdges: Array[GPPIDEdge] = []

# The graphs this sync touches (local + peer). Each gets exactly ONE gpNotifyChanged()
# per execute and per undo — dirty marking must never depend on callers remembering it
# (D03: a sync left the document "unmodified" and the edit was silently lost).
# 本次同步触及的图（本端 + 对端）。每次执行与撤销各发**一次** gpNotifyChanged() ——
# 脏标记绝不能依赖调用方记得去标（D03：同步后文档仍「未修改」，改动被静默丢失）。
var gpGraphs: Array[GPPIDGraph] = []

# Human-readable reason the command refused. / 命令拒绝执行的人类可读原因。
var gpRefusal: String = ""

# Prior link snapshot, for undo. / 撤销用的原 link 快照。
var _gpOldAttrs: Dictionary = {}

# Per-edge prior values, keyed by edge id then attr key; a key ABSENT from the edge
# before the sync is remembered as an absent key (not as "").
# 每条边的原值，按「边 id → 属性键」两级存；同步前**不存在**的键按「不存在」记忆
#（而非记成空串）。
var _gpOldEdgeAttrs: Dictionary = {}

# True once the command actually changed something.
# 命令确实改动了什么时为 true。
var _gpApplied: bool = false

# The contract keys this command applied, fixed at capture time so undo knows exactly
# which keys to restore or erase.
# 本命令应用过的契约键，捕获时固定，使撤销确切知道要恢复 / 删除哪些键。
var _gpAppliedKeys: Array[String] = []


func _init(gpInLink: GPOffPageLink, gpInValues: Dictionary,
		gpInEdges: Array[GPPIDEdge] = [],
		gpInGraphs: Array[GPPIDGraph] = []) -> void:
	gpLink = gpInLink
	gpValues = gpInValues.duplicate(true)
	gpEdges = gpInEdges
	gpGraphs = gpInGraphs
	gpLabel = "同步到对端"


func gpExecute(_gpCtx: GPCommandContext) -> bool:
	gpRefusal = ""
	if gpLink == null:
		gpRefusal = "link_missing"
		return false
	# Only contract keys that the caller actually supplied.
	# 仅取调用方实际给出的契约键。
	var gpApply: Dictionary = {}
	for gpKey in GP_CONTRACT_KEYS:
		if gpValues.has(gpKey):
			gpApply[gpKey] = gpValues[gpKey]
	if gpApply.is_empty():
		# Nothing in the request touches the contract: refuse rather than record a step
		# that changes nothing (no phantom undo step).
		# 请求没有触及契约：拒绝而非记录一个什么都没改的步骤（不产生幽灵撤销步）。
		gpRefusal = "no_contract_values"
		return false
	# Capture priors ONCE. Re-executing after an undo must not overwrite the priors with
	# the command's own output (that is what would make undo+undo lose data).
	# 原值只捕获一次。撤销后再执行不得用命令自己的输出覆盖原值（那会让连撤两次丢数据）。
	if not _gpApplied:
		_gpOldAttrs = gpLink.gpAttrs.duplicate(true)
		_gpAppliedKeys = []
		for gpKey in gpApply.keys():
			_gpAppliedKeys.append(gpKey)
		_gpOldEdgeAttrs = {}
		for gpE in gpEdges:
			if gpE == null:
				continue
			var gpPrior: Dictionary = {}
			for gpKey in gpApply.keys():
				if (gpE.gpAttrs as Dictionary).has(gpKey):
					gpPrior[gpKey] = gpE.gpAttrs[gpKey]
			_gpOldEdgeAttrs[gpE.gpInstanceId] = gpPrior
	# Apply to the snapshot, then to every edge present.
	# 先写快照，再写到每条存在的边。
	for gpKey in gpApply.keys():
		gpLink.gpAttrs[gpKey] = gpApply[gpKey]
	for gpE in gpEdges:
		if gpE == null:
			continue
		for gpKey in gpApply.keys():
			gpE.gpAttrs[gpKey] = gpApply[gpKey]
	_gpApplied = true
	_gpNotifyAll()
	return true


# One notify per touched graph — both on the way in and on the way out (B3: undo must
# dirty the document exactly like execute does).
# 每张触及的图各一次 notify —— 执行与撤销一视同仁（B3：撤销必须与执行一样把文档标脏）。
func _gpNotifyAll() -> void:
	for gpG in gpGraphs:
		if gpG != null:
			gpG.gpNotifyChanged()


func gpUndo(_gpCtx: GPCommandContext) -> void:
	if not _gpApplied or gpLink == null:
		return
	gpLink.gpAttrs = _gpOldAttrs.duplicate(true)
	for gpE in gpEdges:
		if gpE == null:
			continue
		var gpPrior: Dictionary = _gpOldEdgeAttrs.get(gpE.gpInstanceId, {}) as Dictionary
		for gpKey in _gpAppliedKeys:
			# Restore keys the edge had; ERASE keys it did not have. An undo that leaves
			# "dn": "" behind would not be a restoration — the edge never had a dn.
			# 恢复边原有的键；**删除**它原本没有的键。留下 "dn": "" 的撤销不叫恢复
			# —— 那条边从来没有过 dn。
			if not gpPrior.has(gpKey):
				if (gpE.gpAttrs as Dictionary).has(gpKey):
					gpE.gpAttrs.erase(gpKey)
			else:
				gpE.gpAttrs[gpKey] = gpPrior[gpKey]
	_gpApplied = false
	_gpNotifyAll()
