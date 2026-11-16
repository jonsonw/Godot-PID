class_name GPProjectLibrary
extends RefCounted

# Project library scan & metadata peek (W13 T2a, project center).
# 项目库扫描与元数据摘取（W13 T2a，项目中心）。
#
# WHY A NEW FILE / 为何是新文件：
# The architecture guard owns DirAccess/FileAccess to the io layer (ADR-2). The project
# center (ui) needs a directory listing + a lightweight header read, so the io seam is
# a new static helper here — zero growth in project_io.gd beyond yesterday's single
# stamp line, zero file access in ui.
# 架构守卫把 DirAccess/FileAccess 划给 io 层（ADR-2）。项目中心（ui）需要目录列举 +
# 轻量头部读取，io 缝口就是本文件的静态助手 —— project_io.gd 保持昨日单行转发之外
# 零增长，ui 层零文件访问。
#
# PERFORMANCE NOTE (honest) / 性能注记（诚实）：
# gpPeekMeta parses the WHOLE JSON today. Fine for current archive sizes; when S9
# performance work lands (20 MB threshold), swap to a streaming header read if needed.
# gpPeekMeta 目前解析整个 JSON。对当前存档体量足够；S9 性能专项落地（20 MB 阈值）后
# 如有需要再换流式头部读取。

const GP_ARCHIVE_SUFFIX: String = ".pid.json"
const GP_ERR_DIR_UNAVAILABLE: String = "library.dir_unavailable"

# Recent-projects store (W13 T2b). Lives in user:// (app data, not user documents):
# it is engine state, unlike the archives themselves.
# 最近工程列表存档（W13 T2b）。放 user://（应用数据，不是用户文档）：这是引擎状态，
# 与工程存档本身不同。
const GP_RECENT_PATH: String = "user://recent_projects.json"
const GP_RECENT_CAP: int = 10
const GP_ERR_RECENT_WRITE: String = "library.recent_write_failed"
const GP_ERR_CREATE_EXISTS: String = "library.create_exists"
const GP_ERR_CREATE_WRITE: String = "library.create_write_failed"


# Default scan root: the user's Documents folder (project files are user documents,
# not engine data); falls back to user:// when the OS gives nothing. Lives HERE because
# the existence check is a DirAccess call and io owns DirAccess (the architecture
# guard caught the ui-side attempt within one gate run — working as intended).
# 默认扫描根：用户「文稿」目录（工程文件是用户文档，不是引擎数据）；系统取不到时
# 回退 user://。放这里是因为存在性检查是 DirAccess 调用而 io 独占 DirAccess
#（架构守卫在门禁里一跑就抓到了 ui 侧的越界尝试 —— 守卫按设计工作）。
static func gpDefaultScanDir() -> String:
	var gpDocs: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if not gpDocs.is_empty() and DirAccess.dir_exists_absolute(gpDocs):
		return gpDocs
	return "user://"


# List *.pid.json archives in one directory, newest first. Only ONE level (no recursion):
# a project is a single self-contained file (ADR-41 D2), so archives live flat.
# 列举一个目录下的 *.pid.json 存档，按修改时间倒序。只扫一层（不递归）：
# 工程是单文件自包含形态（ADR-41 D2），存档平铺即可。
# Entry shape / 条目形状：{path, file_name, size_bytes, modified_msec}
static func gpScanDirectory(gpDirPath: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	var gpDir: DirAccess = DirAccess.open(gpDirPath)
	if gpDir == null:
		return gpOut
	gpDir.list_dir_begin()
	var gpName: String = gpDir.get_next()
	while not gpName.is_empty():
		if not gpDir.current_is_dir() and gpName.ends_with(GP_ARCHIVE_SUFFIX):
			var gpPath: String = gpDirPath.path_join(gpName)
			var gpSize: int = 0
			var gpFile: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
			if gpFile != null:
				gpSize = int(gpFile.get_length())
				gpFile.close()
			gpOut.append({
				"path": gpPath,
				"file_name": gpName,
				"size_bytes": gpSize,
				"modified_msec": FileAccess.get_modified_time(gpPath) * 1000,
			})
		gpName = gpDir.get_next()
	gpDir.list_dir_end()
	# Newest first — the card list is a recents view in disguise.
	# 最新优先 —— 卡片列表本质就是最近项目视图。
	gpOut.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
		return int(gpA.get("modified_msec", 0)) > int(gpB.get("modified_msec", 0)))
	return gpOut


# Lightweight project summary for one archive. NEVER throws on hostile input: a
# corrupt file degrades to an empty dict and the card falls back to file-name title.
# 单个存档的轻量项目摘要。对敌意输入绝不抛错：坏档降级为空 dict，卡片回退文件名标题。
# Return shape / 返回形状：
#   {container_version, title, owner, sheet_count, member_count}
static func gpPeekMeta(gpFilePath: String) -> Dictionary:
	var gpOut: Dictionary = {
		"container_version": 0,
		"title": "",
		"owner": "",
		"sheet_count": 0,
		"member_count": 0,
	}
	var gpRes: GPIOResult = GPAtomicFile.gpReadJsonDict(gpFilePath)
	if not gpRes.gpOk or not (gpRes.gpPayload is Dictionary):
		return gpOut
	var gpDict: Dictionary = gpRes.gpPayload
	gpOut["container_version"] = int(gpDict.get("container_version", 0))
	# Sheets: length of the array is the single source of truth (meta.sheets is a
	# denormalized mirror and must never be trusted over the payload).
	# 图纸数：数组长度是唯一事实源（meta.sheets 是反规范化镜像，永不高于载荷采信）。
	var gpSheetsRaw: Variant = gpDict.get("sheets", null)
	if gpSheetsRaw is Array:
		gpOut["sheet_count"] = (gpSheetsRaw as Array).size()
	var gpMembersRaw: Variant = gpDict.get("members", null)
	if gpMembersRaw is Array:
		gpOut["member_count"] = (gpMembersRaw as Array).size()
	# Title: v4 project_meta.name -> legacy meta.title -> file stem (caller-side).
	# 标题：v4 project_meta.name -> 旧 meta.title -> 文件名主干（由调用方兜底）。
	var gpMeta: Dictionary = {}
	if gpDict.get("project_meta") is Dictionary:
		gpMeta = gpDict.get("project_meta")
	elif gpDict.get("meta") is Dictionary:
		gpMeta = gpDict.get("meta")
	var gpTitle: String = str(gpMeta.get("name", ""))
	if gpTitle.is_empty():
		gpTitle = str(gpMeta.get("title", ""))
	gpOut["title"] = gpTitle
	gpOut["owner"] = str(gpMeta.get("owner", ""))
	return gpOut


# ==================== recent projects / 最近工程（W13 T2b） ====================

# Load the recent list, dropping entries whose archive no longer exists on disk.
# A missing store, corrupt JSON or a wrong shape degrades to an EMPTY list — the
# recent strip is a convenience, never a blocker.
# 读取最近列表，剔除磁盘上已不存在的条目。存档缺失、JSON 损坏或形状不对一律降级为
# **空**列表 —— 最近条是便利功能，绝不做拦路虎。
# Entry shape / 条目形状：{path: String, ts: int}，最新在前。
static func gpRecentLoad(gpStore: String = GP_RECENT_PATH) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	var gpRes: GPIOResult = GPAtomicFile.gpReadJsonDict(gpStore)
	if not gpRes.gpOk or not (gpRes.gpPayload is Dictionary):
		return gpOut
	var gpRaw: Variant = (gpRes.gpPayload as Dictionary).get("entries", null)
	if not (gpRaw is Array):
		return gpOut
	for gpEntry in gpRaw as Array:
		if not (gpEntry is Dictionary):
			continue
		var gpPath: String = str((gpEntry as Dictionary).get("path", ""))
		if gpPath.is_empty() or not FileAccess.file_exists(gpPath):
			continue
		gpOut.append({"path": gpPath, "ts": int((gpEntry as Dictionary).get("ts", 0))})
	return gpOut


# Move one archive to the front of the recent list (append if new), cap the length
# and persist. Returns the resulting list so the caller can rebuild its UI directly.
# 把一个存档提到最近列表最前（新条目则追加），截断到上限并持久化。返回结果列表，
# 调用方可直接拿去重建界面。
static func gpRecentTouch(gpArchivePath: String, gpStore: String = GP_RECENT_PATH) -> Array[Dictionary]:
	var gpList: Array[Dictionary] = gpRecentLoad(gpStore)
	var gpNow: int = Time.get_unix_time_from_system() as int
	# Deduplicate by absolute path: two spellings of the same file must not stack.
	# 按绝对路径去重：同一文件两种写法不得叠两条。
	var gpAbs: String = gpArchivePath.simplify_path()
	var gpKept: Array[Dictionary] = []
	for gpEntry in gpList:
		if str(gpEntry.get("path", "")).simplify_path() != gpAbs:
			gpKept.append(gpEntry)
	gpKept.push_front({"path": gpAbs, "ts": gpNow})
	while gpKept.size() > GP_RECENT_CAP:
		gpKept.pop_back()
	gpRecentSave(gpKept, gpStore)
	return gpKept


# Persist the recent list. The write goes through GPAtomicFile (the atomic-write pin
# allows no other FileAccess.WRITE site in the tree).
# 持久化最近列表。写入走 GPAtomicFile（原子写钉：全树不允许其它 FileAccess.WRITE 点）。
static func gpRecentSave(gpList: Array[Dictionary], gpStore: String = GP_RECENT_PATH) -> GPIOResult:
	return GPAtomicFile.gpWriteJsonAtomic(gpStore, {"entries": gpList})


# ==================== new archive / 新建存档（W13 T2b） ====================

# Create a new, EMPTY v4 archive at gpArchivePath. Refuses to overwrite. The container
# carries no sheets: on first open the read path reports zero sheets and the SHELL opens
# one properly named sheet (gpAddTab — I18n name + creation-time number; W13 fix
# 2026-11-11: io no longer pads a nameless sheet), so "new project" and "first read"
# stay consistent.
# 在 gpArchivePath 新建一个**空** v4 存档。拒绝覆盖已有文件。容器不携带图纸：首次打开
# 时读路径如实上报零张图纸，由**外壳**开一张有名有号的图纸（gpAddTab —— I18n 名 +
# 创建时编号；W13 修复 2026-11-11：io 不再补无名图纸），「新建」与「首次读取」由此
# 保持一致。
# Default member: the local user as manager — the identity model (ADR-40) takes over
# the real user record from W14.
# 默认成员：本地用户为 manager —— 真实用户记录自 W14 起由身份模型（ADR-40）接管。
static func gpCreateArchiveV4(gpArchivePath: String, gpName: String) -> GPIOResult:
	if FileAccess.file_exists(gpArchivePath):
		return GPIOResult.gpFailure(GP_ERR_CREATE_EXISTS, "pc.create_exists", gpArchivePath)
	var gpContainer: Dictionary = GPProjectContainerV4.gpWrapV4(
		{"kind": "project", "sheets": [], "cross_links": []},
		{"name": gpName, "owner": ""},
		[{"user": "local", "roles": ["manager"]}])
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(gpArchivePath, gpContainer)
	if not gpWrite.gpOk:
		return GPIOResult.gpFailure(GP_ERR_CREATE_WRITE, "pc.create_failed", gpArchivePath)
	return GPIOResult.gpSuccess("pc.created", gpArchivePath)


# ==================== rename & merge / 重命名与合并（W13 实机反馈 2026-11-09） ====================

const GP_ERR_RENAME_EMPTY: String = "library.rename_empty"
const GP_ERR_RENAME_READ: String = "library.rename_read_failed"
const GP_ERR_RENAME_WRITE: String = "library.rename_write_failed"


# Rename a project: rewrite the display name inside the archive (single-file container,
# ADR-41 D2 — there is no folder to rename). Refuses an empty name; the write goes through
# the atomic writer. Whichever meta key the archive uses (project_meta / legacy meta) is
# updated IN PLACE — never duplicated across both keys.
# 重命名工程：改写存档**内部**的显示名（单文件容器，ADR-41 D2 —— 没有文件夹可改名）。
# 拒绝空名；写入走原子写。存档用的哪个元数据键（project_meta / 旧 meta）就**原地**更新
# 哪个 —— 绝不把元数据复制到两个键下。
static func gpRenameArchiveV4(gpArchivePath: String, gpNewName: String) -> GPIOResult:
	var gpName: String = gpNewName.strip_edges()
	if gpName.is_empty():
		return GPIOResult.gpFailure(GP_ERR_RENAME_EMPTY, "pc.rename_empty", gpArchivePath)
	var gpRes: GPIOResult = GPAtomicFile.gpReadJsonDict(gpArchivePath)
	if not gpRes.gpOk or not (gpRes.gpPayload is Dictionary):
		return GPIOResult.gpFailure(GP_ERR_RENAME_READ, "pc.rename_failed", gpArchivePath)
	var gpDict: Dictionary = gpRes.gpPayload
	var gpMeta: Dictionary = {}
	var gpMetaKey: String = "project_meta"
	if gpDict.get("project_meta") is Dictionary:
		gpMeta = gpDict.get("project_meta")
	elif gpDict.get("meta") is Dictionary:
		gpMeta = gpDict.get("meta")
		gpMetaKey = "meta"
	else:
		gpMeta = {}
	gpMeta["name"] = gpName
	gpDict[gpMetaKey] = gpMeta
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(gpArchivePath, gpDict)
	if not gpWrite.gpOk:
		return GPIOResult.gpFailure(GP_ERR_RENAME_WRITE, "pc.rename_failed", gpArchivePath)
	return GPIOResult.gpSuccess("pc.renamed", gpName)


# ==================== delete / 删除（W13 实机反馈 2026-11-11） ====================

const GP_ERR_DELETE_FAIL: String = "library.delete_failed"


# Delete one archive. DEFAULT = move to the OS trash (recoverable — a project file is a
# user document; permanent deletion of user data without a recycle step is the worse
# failure). gpForceRemove=true skips the trash for headless tests. The recent list needs
# no separate cleanup: gpRecentLoad drops entries whose file no longer exists, so the
# deleted archive leaves the list on the next refresh.
# 删除一个存档。默认 = 移入系统废纸篓（可恢复 —— 工程文件是用户文档；对用户数据做
# 无回收站的永久删除是更糟的失败）。gpForceRemove=true 跳过废纸篓，供 headless 测试。
# 最近列表无需单独清理：gpRecentLoad 会剔除文件已不存在的条目，故被删存档在下次刷新
# 时自动离开列表。
static func gpDeleteArchiveV4(gpArchivePath: String, gpForceRemove: bool = false) -> GPIOResult:
	if gpArchivePath.is_empty() or not FileAccess.file_exists(gpArchivePath):
		return GPIOResult.gpFailure(GP_ERR_DELETE_FAIL, "pc.delete_failed", gpArchivePath)
	# macOS trashItemAtURL (and DirAccess.remove_absolute) need a REAL POSIX path — a
	# user:// protocol path fails with "file does not exist" (probe 2026-11-11).
	# Globalize once at the seam so archives under the user:// fallback scan dir delete
	# exactly like Documents ones.
	# macOS 的 trashItemAtURL（以及 DirAccess.remove_absolute）要**真实 POSIX 路径** ——
	# user:// 协议路径会报「文件不存在」（探针 2026-11-11）。在缝口统一 globalize 一次，
	# 让 user:// 回退扫描目录下的存档与 Documents 下的删法完全一致。
	var gpAbsPath: String = ProjectSettings.globalize_path(gpArchivePath)
	if not gpForceRemove:
		# Godot 4.7 signature: returns an ERROR ENUM (OK = really landed in the trash),
		# NOT a bool. A bare `not OK` is `not 0` == true, which misreports every SUCCESS
		# as a failure — the 2026-11-11 on-device bug. Compare against OK explicitly.
		# Godot 4.7 签名：返回 **Error 枚举**（OK = 真的进了废纸篓），不是布尔值。
		# 裸 `not OK` 即 `not 0` 恒为真，会把每次成功误报为失败 —— 2026-11-11 实机缺陷。
		# 必须显式与 OK 比较。
		if OS.move_to_trash(gpAbsPath) != OK:
			return GPIOResult.gpFailure(GP_ERR_DELETE_FAIL, "pc.delete_failed", gpArchivePath)
	else:
		var gpErr: Error = DirAccess.remove_absolute(gpAbsPath)
		if gpErr != OK:
			return GPIOResult.gpFailure(GP_ERR_DELETE_FAIL, "pc.delete_failed", gpArchivePath)
	return GPIOResult.gpSuccess("pc.deleted", gpArchivePath.get_file())


# Merge a directory scan with the recent list into ONE unified card source (Godot-style:
# the list IS the recents view). Archives outside the scan dir arrive via the recent list
# and are normalized to the scan entry shape; duplicates collapse by simplified absolute
# path. Newest first. Pure & testable.
# 把目录扫描与最近列表合并成**一个**卡片数据源（Godot 式：列表即最近项目视图）。
# 扫描目录之外的存档经最近列表进入，并归一化为扫描条目形状；重复项按简化绝对路径合并。
# 最新优先。纯函数可测。
# Entry shape / 条目形状：{path, file_name, size_bytes, modified_msec}
static func gpMergeProjectLists(gpScan: Array[Dictionary], gpRecents: Array[Dictionary]) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	var gpSeen: Dictionary = {}
	for gpEntry in gpScan:
		var gpPath: String = str(gpEntry.get("path", "")).simplify_path()
		if gpPath.is_empty() or gpSeen.has(gpPath):
			continue
		gpSeen[gpPath] = true
		gpOut.append(gpEntry)
	for gpRecent in gpRecents:
		var gpRecentPath: String = str(gpRecent.get("path", "")).simplify_path()
		if gpRecentPath.is_empty() or gpSeen.has(gpRecentPath):
			continue
		gpSeen[gpRecentPath] = true
		# Recent-only entries carry the archive's REAL modification time when it can be
		# stat'ed (最近编辑 must mean last edited, not last opened); the touch timestamp
		# is only the fallback. Both are seconds->msec normalized.
		# 仅最近列表的条目尽量取存档的**真实**修改时间（「最近编辑」必须意为最后编辑，
		# 而非最后打开）；touch 时间戳只作回退。两者均按秒->毫秒归一化。
		var gpMsec: int = maxi(FileAccess.get_modified_time(gpRecentPath) * 1000,
			int(gpRecent.get("ts", 0)) * 1000)
		gpOut.append({
			"path": gpRecentPath,
			"file_name": gpRecentPath.get_file(),
			"size_bytes": 0,
			"modified_msec": gpMsec,
		})
	gpOut.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
		return int(gpA.get("modified_msec", 0)) > int(gpB.get("modified_msec", 0)))
	return gpOut
