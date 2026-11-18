class_name GPRevisionGuard
extends RefCounted
# Copyright © 2026 Jonson Wang
# Shell-side optimistic revision gate — a coordinator over the shell contract (W14, ADR-40
# D6, user ruling D-A=C1).
# 外壳侧乐观修订闸 —— 走外壳契约的协调者（W14，ADR-40 D6，用户拍板 D-A=C1）。
#
# WHY A NEW FILE / 为何是新文件：
# ADR-47 forbids growing file_coordinator.gd (frozen budget 726); the save-path hygiene and
# the revision gate live HERE, so the coordinator keeps only three one-line calls. It joins
# the shell contract like every other coordinator (`var gpHost: GPShellHost`), injected by
# the contract itself in _init() — the root's assembly (main_window) is budget-frozen and
# must not grow for a pure save-path concern.
# ADR-47 禁止继续增长 file_coordinator.gd（冻结预算 726 行）；保存路径卫生与修订闸收在本
# 文件，协调者只留三行调用。它与其余协调者一样进外壳契约（`var gpHost: GPShellHost`），
# 由契约自身在 _init() 注入 —— 根类装配（main_window）预算冻结，不因纯保存路径关注点而增长。
#
# Semantics / 语义：
# - gate BEFORE any write: a leftover .tmp is cleaned honestly, and when the on-disk header
#   revision has moved since this session loaded it, the save is REFUSED with
#   status.revision_conflict — no silent overwrite, no auto-copy (the user decides, C1).
# - 任何写入**之前**先闸：残留 .tmp 诚实清理；当盘上头部修订较本会话载入时前移，
#   保存被**拒绝**并报 status.revision_conflict —— 不静默覆盖、不自动副本（用户决定，C1）。
# - Archives without a revision key (legacy / brand-new path) are skipped: progressive
#   compatibility (D-C).
# - 无修订键的存档（旧档 / 全新路径）跳过比对：渐进兼容（D-C）。
#
# Layer rule / 分层约束：may call down into io (same direction file_coordinator already uses).
# 可下调调用 io（与 file_coordinator 既有方向一致）。
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The SHELL CONTRACT, not the scene root (same narrow type as every coordinator).
# **外壳契约**，而非场景根类（与其余协调者相同的窄类型）。
var gpHost: GPShellHost = null


# Pre-save gate: returns TRUE when the save may proceed (state lines already set on refusal).
# 保存前闸：返回 true 表示可继续保存（拒绝时状态行已设置）。
func gpGateSave(gpFilePath: String) -> bool:
	# A leftover .tmp means the last save died mid-write. Discard it: the target is still
	# the previous good copy. / 残留的 .tmp 意味着上次保存写了一半就死了。清掉它：
	# 目标仍是上一份完好副本。
	if GPAtomicFile.gpHasTempRemains(gpFilePath):
		GPAtomicFile.gpDiscardTempRemains(gpFilePath)
		gpHost.gpSetState("status.tmp_cleaned", [gpFilePath])
	# No loaded baseline (legacy archive / brand-new path): nothing to compare against.
	# 无载入基线（旧档 / 全新路径）：无从比对。
	if gpHost.gpLoadedRevision == "":
		return true
	var gpDiskHeader: GPIOResult = GPProjectIO.gpReadHeader(gpFilePath)
	if not gpDiskHeader.gpIsOk():
		# Missing / unreadable target: the write itself will fail with its own honest code.
		# 目标缺失 / 不可读：写入本身会以自己的诚实失败码报错。
		return true
	var gpDiskRev: String = str((gpDiskHeader.gpPayload as Dictionary).get("revision", ""))
	if gpDiskRev != "" and gpDiskRev != gpHost.gpLoadedRevision:
		gpHost.gpSetState("status.revision_conflict", [gpFilePath])
		return false
	return true


# Refresh the session revision state from the JUST-WRITTEN header, so the next save's
# chain continues from this stamp (and its optimistic check stays meaningful).
# 从**刚写出**的头部刷新会话修订状态，使下一次保存的链从本次盖章继续
#（其乐观校验也因此保持有意义）。
func gpRefreshAfterSave(gpFilePath: String) -> void:
	var gpFreshHeader: GPIOResult = GPProjectIO.gpReadHeader(gpFilePath)
	if not gpFreshHeader.gpIsOk():
		return
	var gpFresh: Dictionary = gpFreshHeader.gpPayload as Dictionary
	gpHost.gpLoadedRevision = str(gpFresh.get("revision", ""))
	gpHost.gpLoadedRevisions = (gpFresh.get("revisions", []) as Array) if (gpFresh.get("revisions") is Array) else []


# Capture the header revision state at LOAD time — the baseline the next save's optimistic
# check compares against. An empty payload (fresh open) honestly resets the baseline.
# 在**载入时**记录头部修订状态 —— 作为下一次保存乐观校验的基线。
# 空载荷（全新打开）如实重置基线。
func gpCaptureOnLoad(gpPayload: Dictionary) -> void:
	gpHost.gpLoadedRevision = str(gpPayload.get("revision", ""))
	gpHost.gpLoadedRevisions = (gpPayload.get("revisions", []) as Array) if (gpPayload.get("revisions") is Array) else []
	# T4a: the roster rides along too (written back on session saves).
	# T4a：名单随行（会话保存时回写）。
	gpHost.gpLoadedMembers = (gpPayload.get("members", []) as Array) if (gpPayload.get("members") is Array) else []
