class_name GPIdentityCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Identity session coordinator (W14 T4a/T4b, ADR-40 D2/D4): login flow on multi-member
# projects, session user bookkeeping, and (T4b) the roster the manager edits.
# 身份会话协调者（W14 T4a/T4b，ADR-40 D2/D4）：多人工程的登录流程、会话用户记账，
# 以及（T4b）管理者编辑的成员名单。
#
# MODE SEMANTICS / 模式语义（ADR-40 D2；v1.3 收紧）：
# - single mode (<= 1 member): ZERO disturbance — session user stays "local/manager", no
#   login prompt ever.
# - multi mode (> 1 member): opening the archive prompts login. CANCEL / close EXITS back
#   to the project manager (v1.3 user decision 2026-11-18) — a multi-user project has no
#   "local" bypass. Enforcement of role capabilities is W15 (the permission matrix).
# - 单人模式（成员数 <= 1）：零打扰 —— 会话用户保持 "local/manager"，永不弹登录。
# - 多人模式（成员数 > 1）：打开存档即提示登录。取消 / 关闭即**退回项目管理器**
#（v1.3 用户拍板 2026-11-18）—— 多人工程没有「本地」旁路。角色能力强制是 W15（权限矩阵）。
#
# Contract holder per the shell rule; self-injected by shell_host._init() because the
# root's assembly is budget-frozen (same reason as revision_guard).
# 按外壳规则持有契约；由 shell_host._init() 自注入 —— 理由与 revision_guard 相同
#（根类装配预算冻结）。
var gpHost: GPShellHost = null

# Enabled members of the open archive (roster for the login dialog and the T4b panel).
# 打开工程的启用成员（登录对话框与 T4b 面板的名单）。
var gpEnabledUsers: Array[String] = []

# The full roster of the open archive (enabled AND disabled — the panel shows both).
# 打开工程的完整名单（启用与停用 —— 面板两者都显示）。
var gpMembers: Array = []

# The login dialog, rebuilt per request (member var, not a lambda capture — R7).
# 登录对话框，按次重建（成员变量而非 lambda 捕获 —— R7）。
var _gpDialog: GPLoginDialog = null

# W14 T5mini: the archive whose lock THIS session currently holds ("" = none). Released
# on project switch and app exit; a crash leaves the lock to the stale reclaim.
# W14 T5mini：本会话当前持锁的存档（"" = 无）。切换工程与退出时释放；崩溃留给僵尸回收。
var _gpLockedPath: String = ""

# The archive the login dialog authenticates against (the dialog re-reads it LIVE on
# every submit). / 登录对话框鉴权用的存档路径（对话框每次提交**实时重读**）。
var _gpCurrentPath: String = ""


# Called by file_coordinator AFTER a successful archive load. Resets the session to
# "local" (identity is per-project-load), reads the roster from the plaintext header,
# and prompts login when the project is in multi mode.
# 由 file_coordinator 在存档**载入成功后**调用。会话重置为 "local"（身份随工程载入），
# 从明文头部读名单，多人模式下提示登录。
func gpOnProjectLoaded(gpFilePath: String) -> void:
	gpHost.gpCurrentUser = "local"
	gpMembers = []
	gpEnabledUsers = []
	_gpCurrentPath = gpFilePath
	gpOnProjectLock(gpFilePath)
	var gpHeader: GPIOResult = GPProjectIO.gpReadHeader(gpFilePath)
	if not gpHeader.gpIsOk():
		return
	var gpPayload: Dictionary = gpHeader.gpPayload as Dictionary
	var gpRaw: Variant = gpPayload.get("members", null)
	if gpRaw is Array:
		gpMembers = gpRaw as Array
	gpEnabledUsers = gpEnabledOf(gpMembers)
	# Single mode: zero disturbance. / 单人模式：零打扰。
	if gpMembers.size() <= 1:
		return
	gpPromptLogin()


# W14 T5mini (ADR-40 D6③): best-effort lock on open — check first (advise a sheet split
# when a live foreign session holds it, reclaim zombies), then acquire. A lock problem is
# advisory ONLY; it never blocks opening (revision is the backstop).
# W14 T5mini（ADR-40 D6③）：打开时的尽力而为锁 —— 先查（活外来会话则建议分图；僵尸回收）
# 再取锁。锁问题**仅为建议**，绝不阻塞打开（修订才是兜底）。
func gpOnProjectLock(gpFilePath: String) -> void:
	gpReleaseOnExit()
	var gpFinding: String = GPLockFile.gpCheckOnOpen(gpFilePath)
	match gpFinding:
		GPLockFile.GP_FINDING_FOREIGN:
			gpHost.gpSetState("identity.lock_foreign", [GPLockFile.gpHolderSummary(gpFilePath)])
		GPLockFile.GP_FINDING_STALE:
			gpHost.gpSetState("identity.lock_stale", [])
	if gpFinding == GPLockFile.GP_FINDING_FOREIGN:
		return
	if GPLockFile.gpAcquire(gpFilePath, gpHost.gpCurrentUser):
		_gpLockedPath = gpFilePath


# Release the held lock (project switch / app exit). Never fatal.
# 释放所持锁（切换工程 / 应用退出）。绝不致命。
func gpReleaseOnExit() -> void:
	if _gpLockedPath != "":
		GPLockFile.gpRelease(_gpLockedPath)
		_gpLockedPath = ""


# Pure, testable: the ENABLED member names of a roster (shape guards per v4 校验口径).
# 纯函数、可测：名单中的**启用**成员名（形状守卫与 v4 校验口径一致）。
static func gpEnabledOf(gpMembers: Array) -> Array[String]:
	var gpOut: Array[String] = []
	for gpEntry in gpMembers:
		if not (gpEntry is Dictionary):
			continue
		if bool((gpEntry as Dictionary).get("enabled", true)):
			var gpName: String = str((gpEntry as Dictionary).get("user", ""))
			if gpName != "" and not gpOut.has(gpName):
				gpOut.append(gpName)
	return gpOut


# Show (or refocus) the login dialog. / 显示（或置前）登录对话框。
func gpPromptLogin() -> void:
	if _gpDialog != null and is_instance_valid(_gpDialog):
		# ADR-48: refocus an existing window with move_to_foreground (move_to_front does
		# NOT exist on Window). / ADR-48：复用窗口置前用 move_to_foreground
		#（move_to_front 在 Window 上不存在）。
		_gpDialog.move_to_foreground()
		return
	_gpDialog = GPLoginDialog.new()
	var gpPrefill: String = gpEnabledUsers[0] if not gpEnabledUsers.is_empty() else ""
	_gpDialog.gpSetup(_gpCurrentPath, gpPrefill)
	gpHost.add_child(_gpDialog)
	_gpDialog.gpLoginDone.connect(_gpOnLoginDone)
	_gpDialog.popup_centered(Vector2i(430, 320))


# Login outcome: success -> the session user changes. Cancel / close -> EXIT back to the
# project manager (v1.3 user decision 2026-11-18: a multi-user project has NO "local"
# bypass — being able to draw after cancelling the login was the reported leak).
# 登录结果：成功 -> 会话用户切换。取消 / 关闭 -> **退回项目管理器**（v1.3 用户拍板
# 2026-11-18：多人工程**没有**「本地」旁路 —— 取消登录后还能画图是用户报的漏洞）。
func _gpOnLoginDone(gpUser: String, gpOk: bool) -> void:
	_gpDialog = null
	if gpOk and gpUser != "":
		gpHost.gpCurrentUser = gpUser
		# v1.3: the display name is a manager-assigned fact in the member entry (the
		# local credential store is retired).
		# v1.3：显示名是成员条目里管理者分配的事实（本机凭据库已退役）。
		var gpDisplay: String = str(GPCMemberRoster.gpFind(gpMembers, gpUser).get("display_name", ""))
		if gpDisplay != "":
			gpHost.gpSetState("identity.logged_in", [gpUser + " (" + gpDisplay + ")"])
		else:
			gpHost.gpSetState("identity.logged_in", [gpUser])
	else:
		gpHost.gpSetState("identity.login_cancelled", [])
		gpHost.gpExitToManager()


# The enabled roster for the login dialog / panel callers.
# 供登录对话框 / 面板调用方使用的启用名单。
func gpRosterEnabled() -> Array[String]:
	return gpEnabledUsers.duplicate()
