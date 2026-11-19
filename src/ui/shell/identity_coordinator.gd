class_name GPIdentityCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Identity session coordinator (W14 T4a/T4b, ADR-40 D2/D4): login flow on multi-member
# projects, session user bookkeeping, and (T4b) the roster the manager edits.
# 身份会话协调者（W14 T4a/T4b，ADR-40 D2/D4）：多人工程的登录流程、会话用户记账，
# 以及（T4b）管理者编辑的成员名单。
#
# MODE SEMANTICS / 模式语义（v1.3.3，用户拍板 2026-11-19 —— 覆盖 v1.3 的单人零打扰）：
# - EVERY open of a credential-carrying roster requires sign-in, single or multi member.
#   The only bypass is a VALID machine-local 24h remember token (GPLoginRemember; the
#   password is never stored). Cancel / close EXITS back to the project manager.
# - Legacy rosters WITHOUT any credential (empty, or no enabled member carries a hash)
#   keep zero disturbance — there is nothing to authenticate against; the session stays
#   "local" honestly.
# - 任何带凭据的名单（单人或多人）**每次打开都必须登录**。唯一旁路是有效的本机
#   24 小时记住令牌（GPLoginRemember；密码不存储）。取消 / 关闭即退回项目管理器。
# - 无凭据的遗留名单（空名单，或无任何启用成员带哈希）保持零打扰 —— 没有可验证之物，
#   会话如实保持 "local"。
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

# v1.3.1: the first-run forced-change dialog (rebuilt per request, same R7 rule).
# v1.3.1：首登强制改密对话框（按次重建，同一 R7 规则）。
var _gpFirstRunDialog: GPFirstRunDialog = null


# v1.3.2: the profile dialog (basic info + self-service password change), rebuilt per
# request. / v1.3.2：资料对话框（基本信息 + 自助改密），按次重建。
var _gpProfileDialog: GPProfileDialog = null


# Set the SESSION user and mirror it onto (a) the persistent status-bar chip and (b) the
# quick-toolbar user button (v1.3.2), both reached through the CONTRACT (no scene tree
# access here). First contact binds their clicks to the profile dialog (roles stay
# manager-only). / 设置**会话用户**并镜像到 (a) 状态栏持久铭牌与 (b) 快捷工具栏用户按钮
#（v1.3.2），两者都经**契约**取得（此处不碰场景树）。首次接触把两者的点击接到资料对话框
#（角色管理仍归管理者）。
func gpSetSessionUser(gpUser: String) -> void:
	gpHost.gpCurrentUser = gpUser
	var gpBar: GPStatusBar = gpHost.gpStatusBarChip()
	if gpBar != null:
		if not gpBar.gpChangePasswordRequested.is_connected(gpPromptProfile):
			gpBar.gpChangePasswordRequested.connect(gpPromptProfile)
		gpBar.gpSetUser(gpUser)
	var gpQuick: GPPIDQuickToolbar = gpHost.gpQuickBar
	if gpQuick != null:
		if not gpQuick.gpProfileRequested.is_connected(gpPromptProfile):
			gpQuick.gpProfileRequested.connect(gpPromptProfile)
		gpQuick.gpSetUser(gpUser)

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
	# v1.3.1: the SHIPPED admin/admin credential triggers the FORCED first-run change in
	# BOTH modes — the default credential may never reach the editor. After the change the
	# user still signs in with the NEW credentials (v1.3.3).
	# v1.3.1：**出厂** admin/admin 凭据在两种模式下都触发**强制**首登改密 ——
	# 默认凭据永远进不了编辑器。改密后仍需用**新**凭据登录（v1.3.3）。
	if GPCMemberRoster.gpIsDefaultAdmin(gpMembers):
		gpPromptFirstRun()
		return
	# v1.3.3: credential-less legacy rosters (empty, or no enabled member carries a hash)
	# keep zero disturbance — nothing to authenticate against.
	# v1.3.3：无凭据的遗留名单（空名单，或无启用成员带哈希）保持零打扰 —— 无可验证之物。
	if not gpGateRequired(gpMembers):
		gpSetSessionUser(gpEnabledUsers[0] if not gpEnabledUsers.is_empty() else "local")
		return
	# v1.3.3: a VALID machine-local 24h remember token (user still enabled) skips re-entry.
	# v1.3.3：有效的本机 24 小时记住令牌（用户仍启用）跳过重输。
	var gpRemembered: String = GPLoginRemember.gpGet(gpFilePath, Time.get_unix_time_from_system())
	if gpRemembered != "" and gpEnabledUsers.has(gpRemembered):
		gpSetSessionUser(gpRemembered)
		return
	gpPromptLogin()


# Pure, testable: does this roster require the credential gate? TRUE iff at least one
# ENABLED member carries a password hash. Empty / hash-less rosters cannot authenticate
# and stay zero-disturbance (honest fallback, v1.3.3).
# 纯函数、可测：该名单是否需要凭据门？当且仅当至少一个**启用**成员带密码哈希时为真。
# 空名单 / 无哈希名单无法鉴权，保持零打扰（如实兜底，v1.3.3）。
static func gpGateRequired(gpMembers: Array) -> bool:
	for gpEntry in gpMembers:
		if not (gpEntry is Dictionary):
			continue
		var gpM: Dictionary = gpEntry as Dictionary
		if not bool(gpM.get("enabled", true)):
			continue
		if str(gpM.get("hash", "")) != "":
			return true
	return false


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


# Login outcome: success -> the session user changes (and, when the remember box was
# ticked, a machine-local 24h token is recorded — the PASSWORD IS NEVER STORED).
# Cancel / close -> EXIT back to the project manager (v1.3: no "local" bypass).
# 登录结果：成功 -> 会话用户切换（勾选记住时记一条**本机** 24 小时令牌 —— **密码绝不
# 存储**）。取消 / 关闭 -> 退回项目管理器（v1.3：没有「本地」旁路）。
func _gpOnLoginDone(gpUser: String, gpOk: bool, gpRemember: bool) -> void:
	_gpDialog = null
	if gpOk and gpUser != "":
		if gpRemember and _gpCurrentPath != "":
			GPLoginRemember.gpPut(_gpCurrentPath, gpUser, Time.get_unix_time_from_system())
		gpSetSessionUser(gpUser)
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


# v1.3.1 first-run: the shipped admin/admin must be replaced (new name + new password +
# recovery email) before anything else. Cancel exits back to the manager — same gate as
# the multi-user login.
# v1.3.1 首登：出厂 admin/admin 必须先替换（新账户名 + 新密码 + 找回邮箱）才能继续。
# 取消即退回项目管理器 —— 与多用户登录同一门。
func gpPromptFirstRun() -> void:
	if _gpFirstRunDialog != null and is_instance_valid(_gpFirstRunDialog):
		_gpFirstRunDialog.move_to_foreground()
		return
	_gpFirstRunDialog = GPFirstRunDialog.new()
	_gpFirstRunDialog.gpSetup(_gpCurrentPath)
	gpHost.add_child(_gpFirstRunDialog)
	_gpFirstRunDialog.gpFirstRunDone.connect(_gpOnFirstRunDone)
	_gpFirstRunDialog.popup_centered(Vector2i(460, 380))


func _gpOnFirstRunDone(gpUser: String, gpOk: bool) -> void:
	_gpFirstRunDialog = null
	if gpOk and gpUser != "":
		# v1.3.3 (user request 2026-11-19): after replacing the shipped credential the user
		# still SIGNS IN with the new username + password — re-read the (changed) roster
		# from disk, then prompt the login gate.
		# v1.3.3（用户要求 2026-11-19）：替换出厂凭据后仍需用新用户名 + 密码**登录** ——
		# 先从盘上重读（已变更的）名单，再弹登录门。
		var gpHeader: GPIOResult = GPProjectIO.gpReadHeader(_gpCurrentPath)
		if gpHeader.gpIsOk():
			var gpRaw: Variant = (gpHeader.gpPayload as Dictionary).get("members", null)
			if gpRaw is Array:
				gpMembers = gpRaw as Array
			gpEnabledUsers = gpEnabledOf(gpMembers)
		gpPromptLogin()
	else:
		gpHost.gpSetState("identity.login_cancelled", [])
		gpHost.gpExitToManager()


# v1.3.2 profile: basic info (read-only) + self-service password change, opened from the
# quick-toolbar user button or the status-bar chip. The user can change ONLY their own
# password — roles / display name / email ride through untouched.
# v1.3.2 资料：基本信息（只读）+ 自助改密，从快捷工具栏用户按钮或状态栏铭牌进入。
# 用户**只能**改自己的密码 —— 角色 / 显示名 / 邮箱原样保留。
func gpPromptProfile() -> void:
	if _gpCurrentPath == "" or gpHost.gpCurrentUser == "" or gpHost.gpCurrentUser == "local":
		return
	if _gpProfileDialog != null and is_instance_valid(_gpProfileDialog):
		_gpProfileDialog.move_to_foreground()
		return
	_gpProfileDialog = GPProfileDialog.new()
	_gpProfileDialog.gpSetup(_gpCurrentPath, gpHost.gpCurrentUser)
	_gpProfileDialog.gpProfileDone.connect(_gpOnProfileDone)
	gpHost.add_child(_gpProfileDialog)
	_gpProfileDialog.popup_centered(Vector2i(460, 480))


func _gpOnProfileDone(gpOk: bool) -> void:
	_gpProfileDialog = null
	if gpOk:
		gpHost.gpSetState("identity.pw_changed", [])


# The enabled roster for the login dialog / panel callers.
# 供登录对话框 / 面板调用方使用的启用名单。
func gpRosterEnabled() -> Array[String]:
	return gpEnabledUsers.duplicate()
