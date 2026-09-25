class_name GPAutoSaveService
extends RefCounted
# Copyright © 2026 Jonson Wang
# Autosave scheduling POLICY — a tiny state machine with no knowledge of files or the scene tree.
# 自动保存调度**策略** —— 一个不认识文件与场景树的小状态机。
#
# WHY THIS EXISTS / 为何存在：
# "When do we save automatically?" is a policy question with three moving parts: is autosave
# armed at all, how often to save while the drawing is dirty, and how often while it is idle.
# Keeping that policy in a plain RefCounted lets it be unit-tested headlessly (no Timer, no
# real clock) and leaves the file coordinator as the MECHANISM (a real Timer + the write).
# 「何时自动保存」是一个有三处变动的策略问题：是否已启用、脏时多久存一次、空闲时多久存一次。
# 把策略放进纯 RefCounted，既可 headless 单测（无 Timer、无真实时钟），
# 也让文件协调者只当**机制**（真 Timer + 实际写入）。
#
# Lifecycle / 生命周期：
# autosave stays DISARMED until the user's first successful manual save. Only then does a real
# path exist, so only then is there a file worth protecting. See ADR-7 (explicit save first)
# and ADR-9 (autosave after the first save).
# 自动保存在用户**首次手动保存成功**前保持关闭。只有那时才存在真实路径，
# 才有一个文件值得保护。见 ADR-7（显式保存优先）与 ADR-9（首存后自动保存）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Default cadence in seconds. A change is persisted within a minute; an idle document is
# re-checkpointed every five minutes.
# 默认节拍（秒）。改动在 1 分钟内落盘；空闲文档每 5 分钟复检一次。
const GP_ACTIVE_INTERVAL_SEC: float = 60.0
const GP_IDLE_INTERVAL_SEC: float = 300.0

# Armed once the first manual save succeeded; stays armed for the rest of the session.
# 首次手动保存成功后置位；本会话内一直保持。
var _gpArmed: bool = false

# Cadence while the document has unsaved changes.
# 文档存在未保存改动时的节拍。
var _gpActiveSec: float = GP_ACTIVE_INTERVAL_SEC

# Cadence while the document has no changes.
# 文档无改动时的节拍。
var _gpIdleSec: float = GP_IDLE_INTERVAL_SEC


# Arm autosave. Called by the mechanism after the first successful manual save.
# 启用自动保存。由机制在首次手动保存成功后调用。
func gpArm() -> void:
	_gpArmed = true


# Disarm autosave (e.g. a future "disable autosave" setting; not wired to UI yet).
# 关闭自动保存（例如将来的「禁用自动保存」设置；尚未接入 UI）。
func gpDisarm() -> void:
	_gpArmed = false


# Whether autosave may fire at all.
# 自动保存是否允许触发。
func gpIsArmed() -> bool:
	return _gpArmed


# The wait to use for the NEXT tick, given the document's dirty state.
# 给定文档脏状态，为**下一次**等待选择的时长。
# Dirty -> short cadence (protect live work); clean -> long cadence (idle checkpoint).
# 脏 -> 短节拍（保护正在进行的编辑）；干净 -> 长节拍（空闲复检）。
func gpIntervalFor(gpDirty: bool) -> float:
	return _gpActiveSec if gpDirty else _gpIdleSec


# Override the two cadences (a future settings panel would call this).
# 覆盖两档节拍（将来的设置面板会调用）。
func gpConfigure(gpActiveSec: float, gpIdleSec: float) -> void:
	_gpActiveSec = maxf(1.0, gpActiveSec)
	_gpIdleSec = maxf(1.0, gpIdleSec)


# Inspection accessors (used by tests and the settings UI to display the current policy).
# 检视访问器（供测试与设置界面展示当前策略）。
func gpActiveInterval() -> float:
	return _gpActiveSec


func gpIdleInterval() -> float:
	return _gpIdleSec
