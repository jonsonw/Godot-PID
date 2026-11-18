class_name GPLockFile
extends RefCounted
# Copyright © 2026 Jonson Wang
# Best-effort project lock for LAN multi-station use (W14 T5mini, ADR-40 D6③).
# 内网多工作站场景下的尽力而为工程锁（W14 T5mini，ADR-40 D6③）。
#
# POSITION / 定位（ADR-40 D6 关键判断，诚实声明）：
# The lock only moves conflict detection EARLIER (open time) — SMB/NFS lock semantics are
# unreliable (crashed clients leave stale locks; some NAS never honour them), so the lock
# is NEVER a correctness guarantee. The only backstop is the revision optimistic check
# (GPRevision + GPRevisionGuard). A lock failure never blocks opening.
# 锁只把冲突发现**提前**到打开时 —— SMB/NFS 锁语义不可靠（崩溃客户端留下僵尸锁；
# 部分 NAS 根本不执行），故锁**绝不是**正确性保证。唯一兜底是修订乐观校验
#（GPRevision + GPRevisionGuard）。锁失败绝不阻塞打开。
#
# SHAPE / 形态：<archive>.lock beside the archive: {"machine", "user", "pid", "at"}.
# STALE RULE / 僵尸规则：a lock whose owner machine+pid can no longer be confirmed AND
# whose age exceeds GP_STALE_SECONDS is reclaimed (crashed-client residue).
# 形态：存档旁 <archive>.lock：{"machine","user","pid","at"}。僵尸规则：超过
# GP_STALE_SECONDS 的锁视为僵尸回收（崩溃客户端残留）。
#
# LAYER RULE / 分层约束：FileAccess use routes through GPAtomicFile only; zero autoload.
# 对 FileAccess 的使用只经 GPAtomicFile；零 autoload。

const GP_LOCK_SUFFIX: String = ".lock"

# A lock older than this is considered stale (crashed client) and reclaimed on open.
# 超过此时长的锁视为僵尸（客户端崩溃），打开时回收。
const GP_STALE_SECONDS: int = 600

# Machine-readable open findings. / 打开时的机器可读发现。
const GP_FINDING_MINE: String = "lock.mine"
const GP_FINDING_FOREIGN: String = "lock.foreign"
const GP_FINDING_STALE: String = "lock.stale"


# The lock path beside an archive. / 存档旁的锁路径。
static func gpLockPath(gpArchivePath: String) -> String:
	return gpArchivePath + GP_LOCK_SUFFIX


# Acquire the lock. Returns false on ANY problem — never fatal, opening proceeds.
# 取锁。任何问题都返回 false —— 绝不致命，打开照常进行。
static func gpAcquire(gpArchivePath: String, gpUser: String) -> bool:
	var gpPayload: Dictionary = {
		"machine": OS.get_unique_id(),
		"user": gpUser,
		"pid": OS.get_process_id(),
		"at": Time.get_unix_time_from_system(),
	}
	return GPAtomicFile.gpWriteJsonAtomic(gpLockPath(gpArchivePath), gpPayload).gpIsOk()


# Release the lock — ONLY if it is ours (a stale foreign lock must survive a polite exit).
# 释放锁 —— 仅当锁是自己的（礼貌退出不得顺带删掉僵尸的外来锁）。
static func gpRelease(gpArchivePath: String) -> void:
	var gpPath: String = gpLockPath(gpArchivePath)
	if not FileAccess.file_exists(gpPath):
		return
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
	if gpRead.gpIsOk():
		var gpDict: Dictionary = gpRead.gpPayload as Dictionary
		if int(gpDict.get("pid", -1)) == OS.get_process_id() \
				and str(gpDict.get("machine", "")) == OS.get_unique_id():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))


# Check on open. Returns a machine-readable finding:
#   ""            — no lock present, all clear;
#   GP_FINDING_MINE — our own lock (re-open of the same process); harmless;
#   GP_FINDING_FOREIGN — another live session holds it (advise sheet-level split);
#   GP_FINDING_STALE — an old foreign lock was reclaimed as zombie residue.
# 打开时检查。返回机器可读发现：空串 = 无锁；mine = 本进程自己的锁（无害）；
# foreign = 活会话持有（建议分图编辑）；stale = 陈旧外来锁已按僵尸回收。
static func gpCheckOnOpen(gpArchivePath: String) -> String:
	var gpPath: String = gpLockPath(gpArchivePath)
	if not FileAccess.file_exists(gpPath):
		return ""
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
	if not gpRead.gpIsOk():
		# An unreadable lock is noise, not a blocker: report foreign (honest, advisory).
		# 不可读的锁是噪音而非阻断：按 foreign 上报（诚实、建议性）。
		return GP_FINDING_FOREIGN
	var gpDict: Dictionary = gpRead.gpPayload as Dictionary
	var gpMine: bool = int(gpDict.get("pid", -1)) == OS.get_process_id() \
		and str(gpDict.get("machine", "")) == OS.get_unique_id()
	if gpMine:
		return GP_FINDING_MINE
	var gpAge: float = Time.get_unix_time_from_system() - float(gpDict.get("at", 0.0))
	if gpAge > float(GP_STALE_SECONDS):
		# Zombie residue: reclaim so the NEXT open is clean, and say so.
		# 僵尸残留：回收使下次打开干净，并如实说明。
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))
		return GP_FINDING_STALE
	return GP_FINDING_FOREIGN


# The holder summary for the status line ("who holds it"). / 状态行用的持锁摘要（「谁持锁」）。
static func gpHolderSummary(gpArchivePath: String) -> String:
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpLockPath(gpArchivePath))
	if not gpRead.gpIsOk():
		return ""
	var gpDict: Dictionary = gpRead.gpPayload as Dictionary
	var gpUser: String = str(gpDict.get("user", ""))
	var gpMachine: String = str(gpDict.get("machine", ""))
	if gpUser == "":
		return gpMachine
	return gpUser + "@" + gpMachine.substr(0, 8)
