extends "res://tests/gp_test.gd"
# Headless regression tests for the best-effort project lock (W14 T5mini, ADR-40 D6③):
# acquire / mine / foreign / stale reclaim / release-only-own / advisory-only semantics.
# 尽力而为工程锁的 headless 回归测试（W14 T5mini，ADR-40 D6③）：取锁 / 自己的锁 /
# 外来锁 / 僵尸回收 / 只释自己的锁 / 仅建议性语义。

const GP_ARCHIVE_PATH: String = "user://gp_test_lock.pid.json"


# Remove every scratch artefact (archive + lock + atomic-write side files).
# 清理全部临时产物（存档 + 锁 + 原子写伴生文件）。
func _gpCleanup() -> void:
	for gpPath in [GP_ARCHIVE_PATH, GP_ARCHIVE_PATH + ".lock", GP_ARCHIVE_PATH + ".bak",
			GP_ARCHIVE_PATH + ".tmp"]:
		var gpAbs: String = ProjectSettings.globalize_path(gpPath)
		if FileAccess.file_exists(gpAbs):
			DirAccess.remove_absolute(gpAbs)


# Acquire then check: the same process sees its own lock (harmless), release clears it.
# 取锁后检查：同进程看到自己的锁（无害），释放后消失。
func gpTestAcquireCheckRelease() -> void:
	_gpCleanup()
	gpEq(GPLockFile.gpCheckOnOpen(GP_ARCHIVE_PATH), "", "a fresh path must have no lock")
	gpCheck(GPLockFile.gpAcquire(GP_ARCHIVE_PATH, "alice"), "acquiring the lock must succeed")
	gpEq(GPLockFile.gpCheckOnOpen(GP_ARCHIVE_PATH), GPLockFile.GP_FINDING_MINE,
		"the same process must see its own lock")
	GPLockFile.gpRelease(GP_ARCHIVE_PATH)
	gpEq(GPLockFile.gpCheckOnOpen(GP_ARCHIVE_PATH), "", "after release there must be no lock")
	_gpCleanup()


# The lock file carries the owner identity (machine / user / pid / timestamp).
# 锁文件携带持有者身份（机器 / 用户 / pid / 时间戳）。
func gpTestLockPayload() -> void:
	_gpCleanup()
	GPLockFile.gpAcquire(GP_ARCHIVE_PATH, "bob")
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(GP_ARCHIVE_PATH + ".lock")
	gpCheck(gpRead.gpIsOk(), "the lock file must be readable JSON")
	if gpRead.gpIsOk():
		var gpDict: Dictionary = gpRead.gpPayload as Dictionary
		gpEq(str(gpDict.get("user", "")), "bob", "the lock must carry the session user")
		gpCheck(int(gpDict.get("pid", -1)) == OS.get_process_id(),
			"the lock must carry the owning pid")
		gpCheck(str(gpDict.get("machine", "")) != "", "the lock must carry the machine id")
	_gpCleanup()


# Release is POLITE: only our own lock is removed; a foreign lock survives.
# 释放是礼貌的：只删自己的锁；外来锁必须存活。
func gpTestReleaseOnlyOwn() -> void:
	_gpCleanup()
	# Forge a FOREIGN lock (different machine + pid). / 伪造一把外来锁（不同机器 + pid）。
	var gpForeign: Dictionary = {"machine": "other-machine", "user": "carol",
		"pid": OS.get_process_id() + 9999, "at": Time.get_unix_time_from_system()}
	gpCheck(GPAtomicFile.gpWriteJsonAtomic(GPLockFile.gpLockPath(GP_ARCHIVE_PATH), gpForeign).gpIsOk(),
		"planting the foreign lock must succeed")
	GPLockFile.gpRelease(GP_ARCHIVE_PATH)
	gpCheck(FileAccess.file_exists(GPLockFile.gpLockPath(GP_ARCHIVE_PATH)),
		"a foreign lock must survive a polite release")
	_gpCleanup()


# A foreign LIVE lock is advisory (foreign), and a STALE one is reclaimed + reported.
# 外来的活锁仅为建议（foreign）；陈旧锁被回收并如实上报。
func gpTestForeignAndStale() -> void:
	_gpCleanup()
	# Live foreign lock: recent timestamp, alien pid.
	# 活的外来锁：时间戳新鲜，pid 异己。
	var gpLive: Dictionary = {"machine": "other-machine", "user": "carol",
		"pid": OS.get_process_id() + 9999, "at": Time.get_unix_time_from_system()}
	GPAtomicFile.gpWriteJsonAtomic(GPLockFile.gpLockPath(GP_ARCHIVE_PATH), gpLive)
	gpEq(GPLockFile.gpCheckOnOpen(GP_ARCHIVE_PATH), GPLockFile.GP_FINDING_FOREIGN,
		"a live foreign lock must report foreign (advisory)")
	gpCheck(FileAccess.file_exists(GPLockFile.gpLockPath(GP_ARCHIVE_PATH)),
		"a live foreign lock must NOT be removed")
	# Stale foreign lock: older than GP_STALE_SECONDS -> reclaimed + reported.
	# 陈旧外来锁：超过 GP_STALE_SECONDS -> 回收 + 上报。
	var gpStale: Dictionary = {"machine": "old-machine", "user": "ghost",
		"pid": OS.get_process_id() + 9999,
		"at": Time.get_unix_time_from_system() - float(GPLockFile.GP_STALE_SECONDS + 60)}
	GPAtomicFile.gpWriteJsonAtomic(GPLockFile.gpLockPath(GP_ARCHIVE_PATH), gpStale)
	gpEq(GPLockFile.gpCheckOnOpen(GP_ARCHIVE_PATH), GPLockFile.GP_FINDING_STALE,
		"a stale lock must be reclaimed and reported stale")
	gpEq(GPLockFile.gpCheckOnOpen(GP_ARCHIVE_PATH), "",
		"after the reclaim the next check must be clean")
	_gpCleanup()


# The holder summary names the user + machine prefix (status-line material).
# 持锁摘要给出用户 + 机器前缀（状态行素材）。
func gpTestHolderSummary() -> void:
	_gpCleanup()
	var gpLive: Dictionary = {"machine": "abcdefgh12345678", "user": "carol",
		"pid": OS.get_process_id() + 9999, "at": Time.get_unix_time_from_system()}
	GPAtomicFile.gpWriteJsonAtomic(GPLockFile.gpLockPath(GP_ARCHIVE_PATH), gpLive)
	gpEq(GPLockFile.gpHolderSummary(GP_ARCHIVE_PATH), "carol@abcdefgh",
		"the summary must be user@machine-prefix")
	_gpCleanup()


# A CORRUPT lock file degrades to advisory-foreign, never a crash (SMB noise is real).
# 损坏的锁文件降级为建议性 foreign，绝不崩溃（SMB 上的噪音是真实存在的）。
func gpTestCorruptLockDegrades() -> void:
	_gpCleanup()
	var gpAbs: String = ProjectSettings.globalize_path(GPLockFile.gpLockPath(GP_ARCHIVE_PATH))
	var gpF: FileAccess = FileAccess.open(gpAbs, FileAccess.WRITE)
	gpF.store_string("not json at all")
	gpF.close()
	gpEq(GPLockFile.gpCheckOnOpen(GP_ARCHIVE_PATH), GPLockFile.GP_FINDING_FOREIGN,
		"a corrupt lock must degrade to advisory-foreign")
	_gpCleanup()
