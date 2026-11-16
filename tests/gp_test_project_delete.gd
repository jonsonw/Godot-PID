extends "res://tests/gp_test.gd"
# Headless tests for project DELETION (W13 user feedback 2026-11-11): the manager could
# only create and rename projects; deletion now goes through GPProjectLibrary.gpDeleteArchiveV4.
# Trash semantics (the DEFAULT) are OS-provided and cannot be verified headless — what IS
# pinned here is the contract around it: hostile input refusal, force-remove, and the
# recent list self-cleaning after deletion.
# 工程删除的 headless 测试（W13 实机反馈 2026-11-11）：管理器此前只能新建与重命名，
# 删除现经 GPProjectLibrary.gpDeleteArchiveV4 落地。废纸篓语义（默认路径）由 OS 提供，
# headless 无法钉死 —— 此处钉的是它的**契约周边**：敌意输入拒收、强制删除、以及删除后
# 最近列表的自清理。
#
# WHY trash-by-default / 为何默认走废纸篓：
# a project archive is a user document. Permanent deletion without a recycle step is the
# worse failure; the confirmation dialog + trash belt-and-suspenders is deliberate.
# 工程存档是用户文档。无回收环节的永久删除是更糟的失败；确认弹窗 + 废纸篓是刻意的双保险。

const GP_TMP_DIR: String = "user://gp_test_projdel"


func _gpCleanTmp() -> void:
	DirAccess.make_dir_recursive_absolute(GP_TMP_DIR)
	var gpDir: DirAccess = DirAccess.open(GP_TMP_DIR)
	if gpDir == null:
		return
	gpDir.list_dir_begin()
	var gpName: String = gpDir.get_next()
	while not gpName.is_empty():
		if not gpDir.current_is_dir():
			DirAccess.remove_absolute(GP_TMP_DIR.path_join(gpName))
		gpName = gpDir.get_next()
	gpDir.list_dir_end()


# Hostile input: an empty path and a nonexistent path must FAIL, never "succeed" silently.
# 敌意输入：空路径与不存在的路径必须**失败**，绝不静默"成功"。
func gpTestDeleteRefusesHostilePaths() -> void:
	var gpEmpty: GPIOResult = GPProjectLibrary.gpDeleteArchiveV4("", true)
	gpCheck(not gpEmpty.gpOk, "an empty path must fail deletion")
	gpEq(gpEmpty.gpCode, GPProjectLibrary.GP_ERR_DELETE_FAIL,
		"the empty-path failure must carry the delete error code")
	var gpMissing: GPIOResult = GPProjectLibrary.gpDeleteArchiveV4(
		GP_TMP_DIR.path_join("no_such.pid.json"), true)
	gpCheck(not gpMissing.gpOk, "a nonexistent archive must fail deletion")
	gpEq(gpMissing.gpCode, GPProjectLibrary.GP_ERR_DELETE_FAIL,
		"the missing-archive failure must carry the delete error code")


# Force removal: create -> delete -> the file is really gone.
# 强制删除：创建 -> 删除 -> 文件真的消失。
func gpTestDeleteForceReallyRemoves() -> void:
	_gpCleanTmp()
	var gpPath: String = GP_TMP_DIR.path_join("doomed.pid.json")
	var gpCreate: GPIOResult = GPProjectLibrary.gpCreateArchiveV4(gpPath, " doomed")
	gpCheck(gpCreate.gpOk, "the fixture archive must be created")
	var gpDel: GPIOResult = GPProjectLibrary.gpDeleteArchiveV4(gpPath, true)
	gpCheck(gpDel.gpOk, "force deletion must succeed on an existing archive")
	gpCheck(not FileAccess.file_exists(gpPath),
		"the archive must be really gone after force deletion")


# The recent list needs NO separate cleanup: gpRecentLoad drops entries whose file no
# longer exists, so a deleted archive leaves the list by itself (pinned against someone
# "optimizing" the touch path into keeping dead entries).
# 最近列表**无需**单独清理：gpRecentLoad 剔除文件已不存在的条目，被删存档自行离开列表
#（钉死此行为，防止有人把 touch 路径"优化"成保留死条目）。
func gpTestDeleteLeavesRecentSelfCleaning() -> void:
	_gpCleanTmp()
	var gpStore: String = GP_TMP_DIR.path_join("recent_store.json")
	var gpPath: String = GP_TMP_DIR.path_join("recent_doomed.pid.json")
	gpCheck(GPProjectLibrary.gpCreateArchiveV4(gpPath, "recent doomed").gpOk,
		"the recent fixture archive must be created")
	var gpList: Array[Dictionary] = GPProjectLibrary.gpRecentTouch(gpPath, gpStore)
	gpCheck(gpList.size() == 1, "the touched archive must be on the recent list")
	GPProjectLibrary.gpDeleteArchiveV4(gpPath, true)
	var gpAfter: Array[Dictionary] = GPProjectLibrary.gpRecentLoad(gpStore)
	gpEq(gpAfter.size(), 0, "the recent list must drop the deleted archive by itself")


# The project-level permission gates (create/rename/delete) are LIVE wiring, not
# decoration: they default to allow, flip under the test seam, and reopen on restore —
# the same contract as the entry-level gates (R2). When the real permission system
# lands (W14 identity, ADR-40), ONLY GPPermissions.gd changes.
# 项目级权限闸（创建/改名/删除）是**活的接线**，不是装饰：默认放行、测试接缝下拒绝、
# 还原后重开 —— 与条目级闸（R2）同一契约。真正的权限系统落地（W14 身份模型，ADR-40）
# 时，只改 GPPermissions.gd。
func gpTestProjectPermissionGatesAreLive() -> void:
	gpCheck(GPPermissions.gpCanCreateProject(), "the create gate defaults to allow")
	gpCheck(GPPermissions.gpCanRenameProject(), "the rename gate defaults to allow")
	gpCheck(GPPermissions.gpCanDeleteProject(), "the delete gate defaults to allow")
	GPPermissions.gpForceDeny = true
	gpCheck(not GPPermissions.gpCanCreateProject(), "the seam denies create")
	gpCheck(not GPPermissions.gpCanRenameProject(), "the seam denies rename")
	gpCheck(not GPPermissions.gpCanDeleteProject(), "the seam denies delete")
	GPPermissions.gpForceDeny = false
	gpCheck(GPPermissions.gpCanDeleteProject(), "restoring the seam reopens the delete gate")
	gpCheck(GPPermissions.gpCanCreateProject(), "restoring the seam reopens the create gate")


# The TRASH path (the DEFAULT!) is pinned end-to-end. Godot 4.7's OS.move_to_trash
# returns an ERROR ENUM, not a bool — the original `not OK` misreport judged every
# success a failure (on-device bug 2026-11-11). These assertions are the sentry: the
# trash route works headless on macOS, so a regression in the return-value semantics
# turns the suite red. Cost (honest): the fixtures land in the real trash.
# 废纸篓路径（**默认路径**！）端到端钉死。Godot 4.7 的 OS.move_to_trash 返回 Error
# 枚举而非布尔 —— 最初的 `not OK` 误报把每次成功判成失败（2026-11-11 实机缺陷）。
# 这些断言就是哨兵：macOS 上该路径 headless 可用，返回值语义一旦回归即转红。
# 诚实的代价：夹具文件会落进真实废纸篓。
func gpTestTrashPathSucceedsEndToEnd() -> void:
	_gpCleanTmp()
	var gpDirect: String = GP_TMP_DIR.path_join("direct.pid.json")
	gpCheck(_gpMakeFixture(gpDirect), "the direct fixture must be created")
	gpEq(OS.move_to_trash(ProjectSettings.globalize_path(gpDirect)), OK,
		"move_to_trash must return OK on success (Error enum, not bool)")
	var gpViaApi: String = GP_TMP_DIR.path_join("via_api.pid.json")
	gpCheck(_gpMakeFixture(gpViaApi), "the api fixture must be created")
	var gpDel: GPIOResult = GPProjectLibrary.gpDeleteArchiveV4(gpViaApi, false)
	gpCheck(gpDel.gpOk, "the default trash route must report success")
	gpEq(gpDel.gpMessageKey, "pc.deleted", "the trash route must carry the success key")


# Tiny helper so the assertion above stays one expression / 让上面第一条断言保持单表达式的微型助手。
func _gpMakeFixture(gpPath: String) -> bool:
	return GPProjectLibrary.gpCreateArchiveV4(gpPath, "direct").gpOk


# Success payload names the FILE (honest status line), and the success key is registered
# for both locales — a missing key would render the raw key text on screen.
# 成功载荷点名**文件名**（诚实状态行），成功键双语注册 —— 键缺失会把裸键名渲染上屏。
func gpTestDeleteSuccessShape() -> void:
	_gpCleanTmp()
	var gpPath: String = GP_TMP_DIR.path_join("named.pid.json")
	gpCheck(GPProjectLibrary.gpCreateArchiveV4(gpPath, "named").gpOk,
		"the fixture archive must be created")
	var gpDel: GPIOResult = GPProjectLibrary.gpDeleteArchiveV4(gpPath, true)
	gpEq(gpDel.gpMessageKey, "pc.deleted", "the success key must be the honest one")
	gpEq(gpDel.gpDetail, "named.pid.json", "the detail must name the deleted file")
