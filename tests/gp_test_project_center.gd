extends "res://tests/gp_test.gd"
# Headless tests for the project manager (W13 T2a + T2b + 2026-11-09 Godot-style rework):
# boot routing, card data projection, io library scan, hostile-archive degradation,
# recent list, archive creation, renaming and list merging.
# 项目管理器的 headless 测试（W13 T2a + T2b + 2026-11-09 Godot 式重构）：启动路由、
# 卡片数据投影、io 库扫描、坏档降级、最近列表、新建存档、重命名与列表合并。
# WHY / 为何要这些测试：
# The manager is the first thing a new user sees. The boot decision is a one-way door
# (wrong branch = no manager or a manager blocking a direct launch); the card projection
# feeds owner/sheet counts shown to engineers; the scan+peek seam is the only place ui
# data comes from disk, so corrupt-archive degradation must be pinned.
# 项目管理器是新用户看到的第一眼。启动决策是单向门（分支错了＝没有管理器，或管理器挡住
# 直启）；卡片投影喂给工程师看的是业主/图纸数；扫描+摘取缝口是 ui 数据唯一来自磁盘的
# 地方，坏档降级必须钉住。

const GP_TMP_DIR: String = "user://gp_test_projlib"


# ==================== boot routing / 启动路由 ====================

# No path argument -> manager. This is the double-click experience (Godot-style: the
# manager IS the app at boot).
# 无路径参数 -> 管理器。这是双击图标的体验（Godot 式：启动时管理器就是应用）。
func gpTestBootModeManagerWhenNoArgs() -> void:
	gpEq(GPBootRoot.gpBootMode(PackedStringArray()), "manager",
		"no args must open the project manager")
	gpEq(GPBootRoot.gpBootMode(PackedStringArray(["--editor"])), "manager",
		"non-path args must still open the project manager")


# A *.pid.json argument means the user named THIS archive -> editor, and .bak
# leftovers never count (they are crash debris, not intent).
# *.pid.json 参数＝用户点名了这个档 -> 编辑器；.bak 残留永不计（是崩溃碎片，不是意图）。
func gpTestBootModeEditorWhenPathArg() -> void:
	gpEq(GPBootRoot.gpBootMode(PackedStringArray(["res://demo.pid.json"])),
		"editor", "a .pid.json arg must go straight to the editor")
	gpEq(GPBootRoot.gpBootMode(PackedStringArray(
		["--headless", "/tmp/x.pid.json"])), "editor",
		"path can appear among other args")
	gpEq(GPBootRoot.gpBootMode(PackedStringArray(["x.pid.json.bak"])),
		"manager", ".bak leftovers must not trigger the editor branch")


# gpBootPath is the companion of gpBootMode: same rules, but returns the named archive
# so the boot router can load it.
# gpBootPath 是 gpBootMode 的配套：同样规则，但返回点名的存档供启动路由载入。
func gpTestBootPathExtractsArchive() -> void:
	gpEq(GPBootRoot.gpBootPath(PackedStringArray()), "",
		"no args must yield an empty boot path")
	gpEq(GPBootRoot.gpBootPath(PackedStringArray(
		["--editor", "/tmp/demo.pid.json"])), "/tmp/demo.pid.json",
		"the named archive must be extracted verbatim")
	gpEq(GPBootRoot.gpBootPath(PackedStringArray(["x.pid.json.bak"])), "",
		".bak leftovers must not count as a boot path")


# ==================== card projection / 卡片投影 ====================

# Full meta path: project attributes win over file name, numbers format correctly.
# 完整元数据路径：工程属性压过文件名，数字格式化正确。
func gpTestAssembleDataUsesProjectAttributes() -> void:
	var gpEntry: Dictionary = {
		"path": "/tmp/pani.pid.json", "file_name": "pani.pid.json",
		"size_bytes": 1536, "modified_msec": 0,
	}
	var gpMeta: Dictionary = {
		"container_version": 4, "title": "Pani 金矿", "owner": "LEBTC",
		"sheet_count": 32, "member_count": 5,
	}
	var gpCard: Dictionary = GPProjectCard.gpAssembleData(gpEntry, gpMeta)
	gpEq(gpCard.get("title", ""), "Pani 金矿", "project_meta title must win")
	gpEq(gpCard.get("owner", ""), "LEBTC", "owner must pass through")
	gpEq(int(gpCard.get("sheet_count", 0)), 32, "sheet count must pass through")
	gpEq(gpCard.get("size_text", ""), "1.5 KB", "1.5 KB must format from 1536 bytes")
	gpEq(gpCard.get("time_text", ""), "", "zero mtime must render as empty time")


# Hostile path: empty meta -> file-stem title, dash owner, still a complete dict.
# 敌意路径：空元数据 -> 文件名主干标题、业主破折号，仍是完整 dict。
func gpTestAssembleDataFallsBackGracefully() -> void:
	var gpEntry: Dictionary = {
		"path": "/tmp/demo.pid.json", "file_name": "demo.pid.json",
		"size_bytes": 3 * 1024 * 1024, "modified_msec": 0,
	}
	var gpCard: Dictionary = GPProjectCard.gpAssembleData(gpEntry, {})
	gpEq(gpCard.get("title", ""), "demo", "empty meta must fall back to the file stem")
	gpEq(gpCard.get("owner", ""), "—", "missing owner must render as a dash")
	gpEq(gpCard.get("size_text", ""), "3.0 MB", "MB sizing must trigger at 1 MiB")


# Unknown size (recent-only entries) renders as a dash, never as "0 B".
# 未知大小（仅最近列表的条目）渲染为破折号，绝不是 "0 B"。
func gpTestAssembleDataRendersUnknownSizeAsDash() -> void:
	var gpEntry: Dictionary = {
		"path": "/tmp/r.pid.json", "file_name": "r.pid.json",
		"size_bytes": 0, "modified_msec": 0,
	}
	gpEq(GPProjectCard.gpAssembleData(gpEntry, {}).get("size_text", ""), "—",
		"size 0 must render as a dash, not 0 B")


# ==================== io library / io 库 ====================

# The default scan root must always resolve to something non-empty (Documents or user://),
# and it lives in the io layer — the manager only consumes it.
# 默认扫描根必须总能解析到非空值（文稿或 user://），且住在 io 层 —— 管理器只消费。
func gpTestDefaultScanDirReturnsUsableRoot() -> void:
	gpCheck(not GPProjectLibrary.gpDefaultScanDir().is_empty(),
		"default scan dir must never be empty")

# Scan lists only *.pid.json (one level, .bak excluded) and sorts newest first.
# 扫描只列 *.pid.json（一层，排除 .bak）并按最新优先排序。
func gpTestScanDirectoryListsArchivesOnly() -> void:
	gpPrepareTmpDir()
	var gpRes: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(GP_TMP_DIR + "/a.pid.json",
		_gpSampleContainer("Alpha"))
	gpCheck(gpRes.gpOk, "fixture write a must succeed")
	gpRes = GPAtomicFile.gpWriteJsonAtomic(GP_TMP_DIR + "/b.pid.json", {"orphan": true})
	gpCheck(gpRes.gpOk, "fixture write b must succeed")
	gpRes = GPAtomicFile.gpWriteJsonAtomic(GP_TMP_DIR + "/c.txt", {})
	gpCheck(gpRes.gpOk, "fixture write c must succeed")
	var gpEntries: Array[Dictionary] = GPProjectLibrary.gpScanDirectory(GP_TMP_DIR)
	gpEq(gpEntries.size(), 2, "only the two .pid.json files must be listed")
	for gpEntry in gpEntries:
		gpCheck(str(gpEntry.get("file_name", "")).ends_with(".pid.json"),
			"every entry must be a .pid.json archive")
	gpCleanupTmpDir()


# Peek projects real v4 fields and degrades a corrupt archive to an empty summary
# instead of an error — the card list must survive one bad file.
# 摘取应读出真实 v4 字段，坏档应降级为空摘要而非报错 —— 卡片列表必须扛得住单个坏档。
func gpTestPeekMetaReadsV4AndDegrades() -> void:
	gpPrepareTmpDir()
	var gpGood: String = GP_TMP_DIR + "/good.pid.json"
	var gpRes: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(gpGood, _gpSampleContainer("Alpha"))
	gpCheck(gpRes.gpOk, "fixture write good must succeed")
	var gpMeta: Dictionary = GPProjectLibrary.gpPeekMeta(gpGood)
	gpEq(int(gpMeta.get("container_version", 0)), 4, "peek must read container_version=4")
	gpEq(gpMeta.get("title", ""), "Alpha", "peek must read project_meta.name as title")
	gpEq(int(gpMeta.get("sheet_count", 0)), 2, "sheet count must come from the payload array")
	gpEq(int(gpMeta.get("member_count", 0)), 1, "member count must come from members[]")
	# Corrupt archive: valid JSON, wrong shape, no version. Degrades, never throws.
	# 坏档：JSON 合法、形状不对、无版本号。降级，绝不抛错。
	gpRes = GPAtomicFile.gpWriteJsonAtomic(GP_TMP_DIR + "/corrupt.pid.json", {"hello": "world"})
	gpCheck(gpRes.gpOk, "fixture write corrupt must succeed")
	var gpBad: Dictionary = GPProjectLibrary.gpPeekMeta(GP_TMP_DIR + "/corrupt.pid.json")
	gpEq(int(gpBad.get("container_version", -1)), 0,
		"missing version must peek as 0, not throw")
	gpEq(int(gpBad.get("sheet_count", -1)), 0, "missing sheets must peek as 0")
	# Missing file: same degradation. / 缺文件：同样降级。
	gpEq(GPProjectLibrary.gpPeekMeta(GP_TMP_DIR + "/nope.pid.json").is_empty(), false,
		"missing file must still return the shaped (empty-valued) dict")
	gpCleanupTmpDir()


# ==================== recent list / 最近列表 ====================

# Roundtrip: touch order defines order, re-touch moves to front, and the list
# persists across load calls.
# 往返：touch 顺序即列表顺序，重 touch 提到最前，且列表跨调用持久。
func gpTestRecentTouchOrdersAndPersists() -> void:
	var gpStore: String = GP_TMP_DIR + "/recent_store.json"
	gpPrepareTmpDir()
	var gpA: String = GP_TMP_DIR + "/a.pid.json"
	var gpB: String = GP_TMP_DIR + "/b.pid.json"
	var gpC: String = GP_TMP_DIR + "/c.txt"
	# Real files: gpRecentLoad drops entries whose archive is gone.
	# 真实文件：gpRecentLoad 会剔除档案已消失的条目。
	gpCheck(GPAtomicFile.gpWriteJsonAtomic(gpA, {"x": 1}).gpOk, "fixture a must exist")
	gpCheck(GPAtomicFile.gpWriteJsonAtomic(gpB, {"x": 2}).gpOk, "fixture b must exist")
	gpCheck(GPAtomicFile.gpWriteJsonAtomic(gpC, {"x": 3}).gpOk, "fixture c must exist")
	var gpList: Array[Dictionary] = GPProjectLibrary.gpRecentTouch(gpA, gpStore)
	gpList = GPProjectLibrary.gpRecentTouch(gpB, gpStore)
	gpList = GPProjectLibrary.gpRecentTouch(gpC, gpStore)
	gpEq(gpList.size(), 3, "three touches must yield three entries")
	gpEq(str(gpList[0].get("path", "")), gpC, "the newest touch must be first")
	gpList = GPProjectLibrary.gpRecentTouch(gpA, gpStore)
	gpEq(str(gpList[0].get("path", "")), gpA, "re-touching a must move it to front")
	gpEq(gpList.size(), 3, "re-touch must not duplicate the entry")
	# Reload from disk: same order — the store persisted.
	# 从磁盘重读：顺序不变 —— 存档已持久化。
	var gpReloaded: Array[Dictionary] = GPProjectLibrary.gpRecentLoad(gpStore)
	gpEq(gpReloaded.size(), 3, "reload must see all three entries")
	gpEq(str(gpReloaded[0].get("path", "")), gpA, "reload must preserve the touch order")
	DirAccess.remove_absolute(gpStore)
	DirAccess.remove_absolute(gpA)
	DirAccess.remove_absolute(gpB)
	DirAccess.remove_absolute(gpC)


# The cap holds: touching beyond 10 keeps only the newest 10 (all files real, or
# the load-time missing-drop would empty the list before the cap even applies).
# 上限生效：超过 10 条只留最新 10 条（文件必须真实存在，否则载入时的缺档剔除
# 会在上限生效之前就把列表清空）。
# Missing archives ARE dropped on load — proven at the end by deleting everything.
# 载入时缺失档案确会被剔除 —— 用例末尾删光档案来证明。
func gpTestRecentDropsMissingAndCaps() -> void:
	var gpStore: String = GP_TMP_DIR + "/recent_store.json"
	gpPrepareTmpDir()
	var gpPaths: Array[String] = []
	for gpI in range(12):
		var gpPath: String = GP_TMP_DIR + "/ghost_%d.pid.json" % gpI
		gpCheck(GPAtomicFile.gpWriteJsonAtomic(gpPath, {"i": gpI}).gpOk,
			"fixture ghost_%d must exist" % gpI)
		gpPaths.append(gpPath)
		GPProjectLibrary.gpRecentTouch(gpPath, gpStore)
	var gpList: Array[Dictionary] = GPProjectLibrary.gpRecentTouch(gpPaths[11], gpStore)
	gpEq(gpList.size(), GPProjectLibrary.GP_RECENT_CAP,
		"the list must never exceed the cap")
	gpEq(str(gpList[0].get("path", "")), gpPaths[11], "the newest touch must be first")
	# Everything exists -> reload keeps the capped 10.
	# 全部存在 -> 重读保留截断后的 10 条。
	gpEq(GPProjectLibrary.gpRecentLoad(gpStore).size(), GPProjectLibrary.GP_RECENT_CAP,
		"all-present entries must survive a reload")
	# Delete every archive: reload drops them all — the strip never offers dead entries.
	# 删光档案：重读全被剔除 —— 最近条永不提供死条目。
	for gpPath in gpPaths:
		DirAccess.remove_absolute(gpPath)
	gpEq(GPProjectLibrary.gpRecentLoad(gpStore).size(), 0,
		"load must drop every archive that no longer exists")
	DirAccess.remove_absolute(gpStore)


# ==================== create / rename / merge · 新建 / 重命名 / 合并 ====================

# Creating an archive produces a VALID v4 container that the normal read path opens
# as one blank sheet — "new" and "first read" must agree — and a second create on
# the same path must refuse (no silent overwrite).
# 新建存档产生**合法** v4 容器，正常读路径将其开为一张空白图纸 —— 「新建」与「首次读取」
# 必须一致 —— 同路径二次新建必须拒绝（绝不静默覆盖）。
func gpTestCreateArchiveV4Lifecycle() -> void:
	gpPrepareTmpDir()
	var gpPath: String = GP_TMP_DIR + "/fresh.pid.json"
	var gpRes: GPIOResult = GPProjectLibrary.gpCreateArchiveV4(gpPath, "Fresh")
	gpCheck(gpRes.gpOk, "create must succeed on an unused path")
	# Validate the written container directly.
	# 直接校验写出的容器。
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
	gpCheck(gpRead.gpOk and gpRead.gpPayload is Dictionary, "created file must read back as JSON dict")
	if gpRead.gpOk and gpRead.gpPayload is Dictionary:
		gpEq(GPProjectContainerV4.gpValidateV4(gpRead.gpPayload).size(), 0,
			"a created archive must pass gpValidateV4 with zero findings")
	# W13 fix (user feedback 2026-11-11): the read path reports an empty archive HONESTLY
	# as zero sheets — io must not pad a nameless one (it cannot reach I18n). The SHELL
	# opens it as one properly named sheet via gpAddTab (file_coordinator).
	# W13 修复（用户反馈 2026-11-11）：读路径**如实**上报空存档为零张图纸 —— io 绝不补
	# 无名图纸（拿不到 I18n）。外壳经 gpAddTab 把它开成一张**有名有号**的图纸
	#（file_coordinator）。
	var gpSheets: GPIOResult = GPProjectIO.gpReadSheetsWithLinks(gpPath)
	gpCheck(gpSheets.gpIsOk(), "the normal read path must open a fresh archive")
	if gpSheets.gpIsOk():
		var gpPayload: Dictionary = gpSheetsResult_payload(gpSheets)
		gpEq((gpPayload.get("sheets", []) as Array).size(), 0,
			"a fresh archive must read back as zero sheets (the shell names the first one)")
	# Overwrite refusal. / 拒绝覆盖。
	gpRes = GPProjectLibrary.gpCreateArchiveV4(gpPath, "Fresh")
	gpCheck(gpRes.gpFailedWith(GPProjectLibrary.GP_ERR_CREATE_EXISTS),
		"a second create on the same path must refuse with create_exists")
	DirAccess.remove_absolute(gpPath)


# Rename rewrites project_meta.name in place, the peek reflects it, an empty name is
# refused and a missing archive degrades to an error — never a throw.
# 重命名原地改写 project_meta.name，摘取随即反映；空名被拒；缺档降级为错误 —— 绝不抛错。
func gpTestRenameArchiveV4RewritesMetaInPlace() -> void:
	gpPrepareTmpDir()
	var gpPath: String = GP_TMP_DIR + "/renamable.pid.json"
	gpCheck(GPProjectLibrary.gpCreateArchiveV4(gpPath, "Before").gpOk,
		"fixture create must succeed")
	gpCheck(GPProjectLibrary.gpRenameArchiveV4(gpPath, "  Pani 金矿 ").gpOk,
		"rename must succeed on an existing archive")
	gpEq(GPProjectLibrary.gpPeekMeta(gpPath).get("title", ""), "Pani 金矿",
		"peek must reflect the renamed title (edges stripped)")
	# In-place: no "meta"/"project_meta" duplication — exactly one meta key remains.
	# 原地性：不产生 "meta"/"project_meta" 双写 —— 恰好剩一个元数据键。
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
	if gpRead.gpOk and gpRead.gpPayload is Dictionary:
		var gpDict: Dictionary = gpRead.gpPayload
		gpCheck(not (gpDict.get("meta") is Dictionary),
			"renaming a project_meta archive must not spawn a legacy meta key")
	# Empty name refused; missing archive refused with the read error.
	# 空名被拒；缺档以读错误被拒。
	gpCheck(GPProjectLibrary.gpRenameArchiveV4(gpPath, "   ").gpFailedWith(
		GPProjectLibrary.GP_ERR_RENAME_EMPTY), "an empty name must be refused")
	gpCheck(GPProjectLibrary.gpRenameArchiveV4(GP_TMP_DIR + "/nope.pid.json", "X").gpFailedWith(
		GPProjectLibrary.GP_ERR_RENAME_READ), "a missing archive must fail with rename_read")
	DirAccess.remove_absolute(gpPath)


# Merge unifies scan + recents: duplicates collapse, recent-only entries normalize to
# the scan shape, and the result sorts newest first.
# 合并统一扫描与最近列表：重复项塌缩、仅最近条目归一化为扫描形状，且结果最新优先。
func gpTestMergeProjectListsDedupesAndNormalizes() -> void:
	var gpScan: Array[Dictionary] = [
		{"path": "/tmp/a.pid.json", "file_name": "a.pid.json", "size_bytes": 10, "modified_msec": 300},
		{"path": "/tmp/b.pid.json", "file_name": "b.pid.json", "size_bytes": 20, "modified_msec": 500},
	]
	var gpRecents: Array[Dictionary] = [
		{"path": "/tmp/b.pid.json", "ts": 999},
		{"path": "/tmp/elsewhere/c.pid.json", "ts": 800},
	]
	var gpMerged: Array[Dictionary] = GPProjectLibrary.gpMergeProjectLists(gpScan, gpRecents)
	gpEq(gpMerged.size(), 3, "the duplicate b must collapse to one entry")
	# The recent-only c stats the real file (mtime = now, ms-scale) so it deterministically
	# leads the fixture's tiny epoch-scale msec values; order: c, b, a.
	# 仅最近列表的 c 会 stat 真实文件（mtime = 现在，毫秒级），确定性地压过样例里
	# 纪元级的小毫秒值；顺序：c、b、a。
	gpEq(str(gpMerged[0].get("path", "")), "/tmp/elsewhere/c.pid.json",
		"the recent-only c (real mtime, now) must lead")
	gpEq(str(gpMerged[1].get("path", "")), "/tmp/b.pid.json",
		"the scanned b (500) must follow the now-based entries")
	var gpC: Dictionary = gpMerged[0]
	gpEq(str(gpC.get("file_name", "")), "c.pid.json",
		"a recent-only entry must normalize its file name")
	gpEq(int(gpC.get("size_bytes", -1)), 0,
		"a recent-only entry must carry size 0 (unknown)")
	gpCheck(int(gpC.get("modified_msec", 0)) > 500,
		"a recent-only entry must carry a real mtime, not the raw touch seconds")
	# Path spelling differences collapse too. / 路径写法差异同样塌缩。
	var gpRecents2: Array[Dictionary] = [{"path": "/tmp/./a.pid.json", "ts": 1}]
	gpEq(GPProjectLibrary.gpMergeProjectLists(gpScan, gpRecents2).size(), 2,
		"simplified paths must dedupe across spellings")


# Payload extractor kept tiny so the block above stays readable.
# 载荷提取器保持极小，让上面的用例可读。
func gpSheetsResult_payload(gpRes: GPIOResult) -> Dictionary:
	return gpRes.gpPayload as Dictionary


# ==================== fixtures / 样例 ====================

func _gpSampleContainer(gpName: String) -> Dictionary:
	return GPProjectContainerV4.gpWrapV4({
		"kind": "project",
		"meta": {"title": "demo"},
		"sheets": [
			{"id": "s1", "name": "PFD", "number": "01", "nodes": []},
			{"id": "s2", "name": "P&ID", "number": "02", "nodes": []},
		],
	}, {"name": gpName, "owner": "LEBTC"}, [{"user": "alice", "roles": ["manager"]}])


func gpPrepareTmpDir() -> void:
	DirAccess.make_dir_recursive_absolute(GP_TMP_DIR)


func gpCleanupTmpDir() -> void:
	DirAccess.remove_absolute(GP_TMP_DIR + "/a.pid.json")
	DirAccess.remove_absolute(GP_TMP_DIR + "/b.pid.json")
	DirAccess.remove_absolute(GP_TMP_DIR + "/c.txt")
	DirAccess.remove_absolute(GP_TMP_DIR + "/good.pid.json")
	DirAccess.remove_absolute(GP_TMP_DIR + "/corrupt.pid.json")
	DirAccess.remove_absolute(GP_TMP_DIR)
