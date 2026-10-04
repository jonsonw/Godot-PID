class_name GPFileCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Project file lifecycle: save / open / import / export / the unsaved-changes close guard.
# 工程文件生命周期：保存 / 打开 / 导入 / 导出 / 未保存关闭拦截。
#
# WHY THIS EXISTS / 为何存在：
# GPMainWindow had grown to 1,759 lines carrying eight unrelated responsibilities; the file
# lifecycle alone was ~360 of them. This coordinator owns that one use case end to end —
# the file dialog, the current-path bookkeeping, the dirty-flag settlement and the exit
# three-way — so the root keeps only assembly and forwarding.
# GPMainWindow 一度膨胀到 1,759 行、承载八类互不相关的职责，其中文件生命周期独占约 360 行。
# 本协调者端到端接管这一用例 —— 文件对话框、当前路径记账、脏标记结算与退出三选一 ——
# 使根类只保留装配与转发。
#
# Interaction / 交互方式：
# - the root creates this coordinator and injects itself as gpHost (composition root);
# 根类创建本协调者并把自身注入为 gpHost（组合根装配）；
# - the root forwards menu / toolbar actions here, never the other way round — this class
# does not reach back into menus or the ribbon;
# 根类把菜单/工具栏动作转发到此处，绝不反向 —— 本类不回指菜单或 Ribbon；
# - UI refresh goes through gpHost.gpSetState() / the docks it owns.
# UI 刷新经由 gpHost.gpSetState() 及其持有的停靠栏完成。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPMainWindow = null

# Autosave POLICY + its timer. gpAutoSave holds the STATE (armed? which cadence); the Timer is
# the MECHANISM. Armed only after the first successful manual save (ADR-9).
# 自动保存**策略** + 计时器。gpAutoSave 持有**状态**（是否启用？用哪档节拍）；Timer 是**机制**。
# 仅在首次手动保存成功后启用（ADR-9）。
var gpAutoSave: GPAutoSaveService = GPAutoSaveService.new()
var gpAutoSaveTimer: Timer = null

# True while the exit three-way dialog is open. Autosave is paused then so it cannot overwrite
# the file behind a "Don't Save" choice — the guard must be able to honour a discard.
# 退出三选一打开期间为真。此时暂停自动保存，使其不会在用户选「不保存」时从背后改写文件 ——
# 护栏必须能兑现「丢弃」这一选择。
var _gpExitPromptOpen: bool = false


# ============================ autosave (ADR-9) ============================
# ============================ 自动保存（ADR-9） ============================
# Build the autosave Timer and start listening to dirty-flag flips. Called ONCE by the
# composition root. The timer stays idle until the first manual save arms it.
# 构建自动保存 Timer 并开始监听脏标记翻转。由组合根调用一次。计时器空闲，直至首次手动保存启用它。
func gpSetupAutoSave() -> void:
	gpAutoSaveTimer = Timer.new()
	gpAutoSaveTimer.one_shot = false
	gpAutoSaveTimer.wait_time = gpAutoSave.gpActiveInterval()
	gpAutoSaveTimer.autostart = false
	gpAutoSaveTimer.timeout.connect(gpOnAutoSaveTick)
	gpHost.add_child(gpAutoSaveTimer)
	# Re-time the moment the dirty flag flips, so a fresh edit drops the wait to the 1-minute
	# cadence instead of sitting out the idle 5-minute one.
	# 脏标记翻转的瞬间即重新计时，使新改动把等待降到 1 分钟节拍，而不必熬满空闲的 5 分钟。
	gpHost.gpDocManager.gpBus.gpDirtyChanged.connect(gpOnDirtyChanged)


# Arm autosave the first time a manual save succeeds, then start the countdown.
# 首次手动保存成功时启用自动保存，然后开始计时。
func gpArmAutoSaveIfNeeded() -> void:
	if gpAutoSave.gpIsArmed():
		return
	gpAutoSave.gpArm()
	gpRescheduleAutoSave()


# (Re)start the timer on the cadence that matches the current dirty state.
# 依据当前脏状态，用对应的节拍（重新）启动计时器。
func gpRescheduleAutoSave() -> void:
	if gpAutoSaveTimer == null:
		return
	gpAutoSaveTimer.stop()
	gpAutoSaveTimer.wait_time = gpAutoSave.gpIntervalFor(gpHost.gpDocManager.gpIsDirty())
	gpAutoSaveTimer.start()


# Pause autosave while the exit prompt is open (see _gpExitPromptOpen).
# 退出提示打开期间暂停自动保存（见 _gpExitPromptOpen）。
func gpPauseAutoSaveForExitPrompt() -> void:
	_gpExitPromptOpen = true
	if gpAutoSaveTimer != null:
		gpAutoSaveTimer.stop()


# Resume the cadence after the user cancels the exit prompt.
# 用户在退出提示选「取消」后恢复节拍。
func gpResumeAutoSaveAfterCancel() -> void:
	_gpExitPromptOpen = false
	if gpAutoSave.gpIsArmed():
		gpRescheduleAutoSave()


# Timer fired: persist the active document if autosave is armed and a path exists.
# 计时器到点：若自动保存已启用且存在路径，落盘当前文档。
func gpOnAutoSaveTick() -> void:
	if _gpExitPromptOpen or not gpAutoSave.gpIsArmed():
		return
	if gpHost.gpCurrentPath == "":
		return
	gpWriteProject(gpHost.gpCurrentPath, true)


# Dirty flag flipped: re-time the countdown so the cadence tracks the document state.
# 脏标记翻转：重新计时，使节拍跟随文档状态。
func gpOnDirtyChanged(_gpDirty: bool) -> void:
	if _gpExitPromptOpen or not gpAutoSave.gpIsArmed():
		return
	gpRescheduleAutoSave()


# ============================ close guard ============================
# ============================ 关闭拦截 ============================
# Intercept the window close so an unsaved drawing is never lost silently.
# 拦截窗口关闭，使未保存的图纸永不静默丢失。
# WHY THIS IS NEEDED / 为何需要：saving is explicit (ADR-7: Ctrl+S is the only save path),
# which means a user who simply forgets to press it would lose everything with no warning.
# The guard is the safety net that makes an explicit-save model safe to adopt.
# 保存是显式的（ADR-7：Ctrl+S 是唯一保存路径），这意味着仅仅**忘记按**的用户会
# 毫无警告地丢失全部内容。这道护栏正是让「显式保存」模型可以被安全采用的安全网。
#
# NOTE / 注：the close is intercepted through get_window.close_requested (wired by the
# root), NOT _notification(NOTIFICATION_WM_CLOSE_REQUEST). On a Control scene root the WM
# notification is not reliably delivered in Godot 4, so the dialog would silently fail to
# appear. The signal fires on the real Window and is the canonical interception point.
# 关闭经由 get_window.close_requested（由根类接线）拦截，而非
# _notification(NOTIFICATION_WM_CLOSE_REQUEST)。在 Control 场景根上该 WM 通知在 Godot 4
# 中不可靠地送达，对话框会静默不出现。信号在真正的 Window 上触发，是权威拦截点。


# Close path: clean -> quit immediately; dirty -> ask, never decide for the user.
# 关闭路径：干净 -> 立即退出；脏 -> 询问，绝不替用户决定。
func gpOnCloseRequested() -> void:
	if not gpHost.gpDocManager.gpIsDirty():
		gpHost.get_tree().quit()
		return
	gpAskUnsaved()


# Three-way confirmation: Save / Don't Save / Cancel.
# 三选一确认：保存 / 不保存 / 取消。
# "Don't Save" is offered because a user may be closing precisely BECAUSE the edit was a
# mistake — forcing a save in that case would overwrite a good file with a bad one.
# 提供「不保存」是因为用户关闭窗口**恰恰可能**因为这次编辑是个错误 ——
# 此时强制保存会用坏数据覆盖好文件。
func gpAskUnsaved() -> void:
	# Pause autosave while the prompt is open: the user is deciding whether the work is worth
	# keeping, and a background save would silently overrule a "Don't Save" choice.
	# 提示期间暂停自动保存：用户正在决定这份工作是否值得保留，
	# 后台保存会静默否决「不保存」的选择。
	gpPauseAutoSaveForExitPrompt()
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("dialog.unsaved_title")
	gpDlg.dialog_text = I18n.gpTr("dialog.unsaved_text")
	gpDlg.get_ok_button().text = I18n.gpTr("dialog.unsaved_save")
	gpDlg.get_cancel_button().text = I18n.gpTr("dialog.cancel")
	gpDlg.add_button(I18n.gpTr("dialog.unsaved_discard"), true, "discard")
	gpDlg.confirmed.connect(gpOnUnsavedSave.bind(gpDlg))
	gpDlg.canceled.connect(gpOnUnsavedCancel.bind(gpDlg))
	gpDlg.custom_action.connect(gpOnUnsavedDiscard.bind(gpDlg))
	gpHost.add_child(gpDlg)
	gpDlg.popup_centered()


# "Cancel" chosen: keep the window open and resume the autosave cadence.
# 选择了「取消」：保持窗口打开并恢复自动保存节拍。
func gpOnUnsavedCancel(gpDlg: ConfirmationDialog) -> void:
	gpDlg.queue_free()
	gpResumeAutoSaveAfterCancel()


# "Save" chosen: save (asking for a path first when there is none), then quit.
# 选择了「保存」：先保存（无路径时先询问路径），再退出。
func gpOnUnsavedSave(gpDlg: ConfirmationDialog) -> void:
	gpDlg.queue_free()
	if gpHost.gpCurrentPath == "":
 # No path yet: the save-as dialog must run first, and the quit waits for it.
 # 尚无路径：必须先走另存为对话框，退出等它完成。
		gpHost.gpQuitAfterSave = true
		gpSaveProject(true)
		return
	gpSaveProject(false)
	# Only quit if the save actually cleared the dirty flag; a failed save must leave the
	# window open, otherwise the guard would be the thing that loses the work.
	# 仅在保存确实清除了脏标记后才退出；保存失败必须让窗口保持打开，
	# 否则这道护栏本身就变成了丢失工作的原因。
	if not gpHost.gpDocManager.gpIsDirty():
		gpHost.get_tree().quit()


# "Don't Save" chosen: discard and quit.
# 选择了「不保存」：丢弃并退出。
func gpOnUnsavedDiscard(gpAction: StringName, gpDlg: ConfirmationDialog) -> void:
	if str(gpAction) != "discard":
		return
	gpDlg.queue_free()
	gpHost.get_tree().quit()


# ============================ project save / open ============================
# ============================ 工程存盘 / 打开 ============================
# Save the active project. Reuses the last path unless gpForcePick is true (Save As).
# 保存当前工程。除非 gpForcePick 为真（另存为），否则复用上次的路径。
func gpSaveProject(gpForcePick: bool) -> void:
	if gpForcePick or gpHost.gpCurrentPath == "":
 # No path yet (or Save As): ask the user via the file dialog.
 # 尚无路径（或另存为）：用文件对话框询问用户。
		gpHost.gpPendingFileAction = "save"
		gpHost.gpFileDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_gpApplyDialogFilters("")
		gpHost.gpFileDialog.popup_centered()
		return
	gpWriteProject(gpHost.gpCurrentPath)


# Open an existing project from disk.
# 从磁盘打开已有工程。
func gpOpenProject() -> void:
	gpHost.gpPendingFileAction = "open"
	gpHost.gpFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_gpApplyDialogFilters("")
	gpHost.gpFileDialog.popup_centered()


# Merge an archive INTO the current drawing (non-destructive: nothing here is replaced).
# 把档案**合并进**当前图纸（非破坏：此处不替换任何东西）。
func gpImportProject() -> void:
	gpHost.gpPendingFileAction = "import"
	gpHost.gpFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_gpApplyImportFilters()
	gpHost.gpFileDialog.popup_centered()


# The merged import dialog offers BOTH container formats: a *.pid.json merge archive and a
# DEXPI *.pid.xml. Offering only *.pid.json forced users through "All Files", and the file
# they picked then failed with a misleading "open failed" — the format was fine, the ROUTING
# was not (see gpOnFileSelected).
# 合并式导入对话框同时提供**两种**容器格式：*.pid.json 合并档案与 DEXPI *.pid.xml。
# 只给 *.pid.json 会逼用户走「All Files」，随后选中的文件还以误导性的「打开失败」告终
# —— 格式本身没问题，错的是**分发**（见 gpOnFileSelected）。
func _gpApplyImportFilters() -> void:
	gpHost.gpFileDialog.clear_filters()
	gpHost.gpFileDialog.add_filter("*.pid.json", I18n.gpTr("doc.pid_filter"))
	gpHost.gpFileDialog.add_filter("*.pid.xml", I18n.gpTr("doc.dexpi_filter"))


# Ask where to read a DEXPI XML file from. Reuses the shared dialog but with the DEXPI
# filter, so the user can actually SELECT a .pid.xml — the bare import dialog only offered
# *.pid.json, which is the SAME silent-feature class the export side had before the fix.
# 询问从哪个 DEXPI XML 文件读取。复用共享对话框但套用 DEXPI 过滤器，
# 使用户**能选**到 .pid.xml —— 裸导入对话框此前只会提供 *.pid.json，
# 与导出侧修复前「选不了 DEXPI」是同一类静默功能缺失。
func gpPickImportDexpiPath() -> void:
	gpHost.gpPendingFileAction = "import_dexpi"
	gpHost.gpFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_gpApplyDialogFilters("dexpi")
	gpHost.gpFileDialog.popup_centered()


# Ask where to write an export container. Export is NOT save-as: the current path is
# untouched and the in-memory drawing is not modified.
# 询问导出容器写到哪里。导出不是另存为：当前路径不变，内存中的图纸也不被修改。
func gpPickExportPath(gpKind: String) -> void:
	gpHost.gpPendingFileAction = "export_" + gpKind
	gpHost.gpFileDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_gpApplyDialogFilters(gpKind)
	# Prefill from the current project name so the default already carries the RIGHT
	# extension — the save dialog never appends one on its own.
	# 以当前工程名预填，使默认名已带**正确**的扩展名 —— 保存对话框从不会自动补扩展名。
	gpHost.gpFileDialog.current_file = _gpSuggestedExportName(gpKind)
	gpHost.gpFileDialog.popup_centered()


# Point the shared dialog's filters at the right format before EVERY popup. Without this the
# dialog keeps whichever filters it had at startup — which is exactly how "Export DEXPI XML"
# ended up offering only *.pid.json: the menu entry existed, the registry knew the extension,
# but nothing told the dialog.
# 每次**弹窗前**把共享对话框的过滤器指到正确格式。否则对话框沿用启动时的过滤器 ——
# 「导出 DEXPI XML」只提供 *.pid.json 正是这么来的：菜单项存在、注册表知道扩展名，
# 却没有任何东西告诉对话框。
func _gpApplyDialogFilters(gpKind: String) -> void:
	gpHost.gpFileDialog.clear_filters()
	var gpPattern: String = GPExporterRegistry.gpFilterPatternOf(gpKind)
	var gpLabelKey: String = GPExporterRegistry.gpFilterKeyOf(gpKind)
	if gpPattern.is_empty() or gpLabelKey.is_empty():
		# Not an export (open / save-as / import): the project container is the only format.
		# 非导出（打开 / 另存为 / 导入）：工程容器是唯一格式。
		gpPattern = "*.pid.json"
		gpLabelKey = "doc.pid_filter"
	gpHost.gpFileDialog.add_filter(gpPattern, I18n.gpTr(gpLabelKey))


# "…/W6.pid.json" -> "W6.pid.xml"; no current project -> "" (the field stays blank).
# The basename of "W6.pid.json" is "W6.pid" — an INCOMPLETE container name, not a prefix to
# double. Strip the trailing ".pid" before attaching the registry extension, or the pre-filled
# default lands on disk as "W6.pid.pid.xml" (observed in the wild).
# 「…/W6.pid.json」->「W6.pid.xml」；无当前工程则返回空串（输入框保持空白）。
# 「W6.pid.json」的 basename 是「W6.pid」—— 那是个**没写完**的容器名，不是用来翻倍的前缀。
# 追加注册表扩展名前必须先剥掉结尾的「.pid」，否则预填的默认名会以
# 「W6.pid.pid.xml」的形态落到磁盘上（实际发生过）。
func _gpSuggestedExportName(gpKind: String) -> String:
	var gpExt: String = GPExporterRegistry.gpExtensionOf(gpKind)
	var gpBase: String = gpHost.gpCurrentPath.get_file().get_basename()
	if gpBase.is_empty() or gpExt.is_empty():
		return ""
	if gpBase.ends_with(".pid"):
		gpBase = gpBase.trim_suffix(".pid")
	return gpBase + "." + gpExt


# Forward the file-dialog result to the right handler.
# 把文件对话框的结果转交给对应处理。
func gpOnFileSelected(gpPath: String) -> void:
	if gpHost.gpPendingFileAction == "save":
		gpWriteProject(gpPath)
	elif gpHost.gpPendingFileAction == "open":
		gpReadProject(gpPath)
	elif gpHost.gpPendingFileAction == "import":
		# Route by FORMAT, not by menu item: a .xml picked through the merged import dialog
		# is DEXPI, whatever entry opened the dialog. Routing it to the JSON reader produced
		# the misleading "open failed" the user actually hit.
		# 按**格式**而非菜单项分发：合并导入对话框里选到的 .xml 就是 DEXPI，
		# 与从哪个菜单项打开对话框无关。把它送进 JSON 读取器，就是用户实际撞上的
		# 那个误导性「打开失败」。
		if gpPath.get_file().ends_with(".xml"):
			gpDoImportDexpi(gpPath)
		else:
			gpDoImport(gpPath)
	elif gpHost.gpPendingFileAction == "import_dexpi":
		gpDoImportDexpi(gpPath)
	elif gpHost.gpPendingFileAction.begins_with("export_"):
		gpDoExport(gpPath, gpHost.gpPendingFileAction.trim_prefix("export_"))


# Serialize the active graph (with embedded user packs) and write it to disk.
# 把活动图（含内嵌用户图元包）序列化并写入磁盘。
# The actual file mechanics live in GPProjectIO (single source of truth for *.pid.json);
# this method only owns UI-side concerns (embedding packs, status, path bookkeeping).
# 真正的文件机制在 GPProjectIO（*.pid.json 的单一事实来源）；本方法仅负责 UI 关注点
# （嵌入图元包、状态栏、路径记账）。
func gpWriteProject(gpPath: String, gpIsAuto: bool = false) -> void:
	# Embed custom user packs so the file is self-contained (data sovereignty).
	# 嵌入用户自定义图元包，使文件自包含（数据主权）。
	gpHost.gpActiveGraph().gpEmbedUserPacks(GPSymbolLibrary.gpUserPacks())
	# stamp the library's schema fingerprints into the file so a later open can detect
	# that a field was added, renamed or deleted in the meantime.
	# 把库的 schema 指纹盖进文件，使日后打开能察觉期间字段被增 / 改名 / 删过。
	gpHost.gpActiveGraph().gpSchemaFingerprints = GPPropertyResolver.gpFingerprintsFor(gpHost.gpDefs)
	var gpFilePath: String = GPProjectIO.gpEnsurePidExt(gpPath)
	# A leftover .tmp means the last save died mid-write. Discard it: the target is still the
	# 残留的 .tmp 意味着上次保存写了一半就死了。清掉它：目标仍是上一份完好副本，
	if GPAtomicFile.gpHasTempRemains(gpFilePath):
		GPAtomicFile.gpDiscardTempRemains(gpFilePath)
		gpHost.gpSetState("status.tmp_cleaned", [gpFilePath])
	# Prefer the GPIOResult API: it carries a machine-readable code plus an i18n reason key,
	# so the shell can explain WHY a save failed instead of only knowing that it did.
	# 优先使用 GPIOResult API：它携带机器可读码与 i18n 原因键，使外壳能解释保存「为何」失败，
	# 而不只是知道失败了。
	# Multi-sheet projects are written as a v3 container; a single-sheet project keeps the
	# v2 shape so archives written before this feature stay byte-stable.
	# 多图纸工程写成 v3 容器；单图纸工程保持 v2 形态，使本功能之前写出的存档保持字节稳定。
	var gpSheets: Array = gpHost.gpCenter.gpToSheets()
	var gpWriteResult: GPIOResult
	if gpSheets.size() > 1:
		gpWriteResult = GPProjectIO.gpWriteSheetsResult(gpSheets, gpFilePath)
	else:
		# A single-sheet archive keeps the v2 shape, which has NO sheets[] section — so the
		# tab title must be stamped into meta["title"], or the migration chain reconstructs
		# the first sheet's name from an empty/default title and the user's tab rename is
		# silently lost on reload (showed the default "Sheet 1" again).
		# 单图纸存档保持 v2 形态，其中**没有** sheets[] 段 —— 故必须把标签标题盖进
		# meta["title"]，否则迁移链会用空/默认标题重建首张图纸名，用户改过的标签名
		# 在重载时被静默丢弃（重开后又显示默认的「Sheet 1」）。
		var gpFirst: GPSheet = gpSheets[0] as GPSheet
		if gpFirst != null and gpFirst.gpName != "":
			(gpFirst.gpGraph if gpFirst.gpGraph != null else gpHost.gpActiveGraph()).gpMeta["title"] = gpFirst.gpName
		gpWriteResult = GPProjectIO.gpWriteProjectResult(gpHost.gpActiveGraph(), gpFilePath)
	if not gpWriteResult.gpIsOk():
		gpHost.gpSetState("status.save_fail", [gpFilePath])
		return
	gpHost.gpCurrentPath = gpFilePath
	# a successful save clears the unsaved-dirty flag so the title bar / project tree update.
	# 保存成功清除未保存脏标记，使标题栏/工程树同步。
	gpHost.gpDocManager.gpClearDirty()
	# The FIRST successful save arms autosave: only now does a real path exist to protect
	# (ADR-9). Subsequent saves keep it armed; arming is idempotent.
	# **首次**成功保存启用自动保存：此时才存在值得保护的真实路径（ADR-9）。
	# 后续保存保持启用；启用是幂等的。
	gpArmAutoSaveIfNeeded()
	# Honour a pending quit from the close guard (path-less save-as on exit).
	# 兑现关闭拦截留下的待退出（退出时无路径的另存为）。
	if gpHost.gpQuitAfterSave:
		gpHost.gpQuitAfterSave = false
		gpHost.get_tree().quit()
		return
	if gpIsAuto:
		# A quieter, distinct line so the user can tell a background checkpoint apart from
		# their own explicit Ctrl+S.
		# 更安静且独立的一行，使后台复检与用户自己的 Ctrl+S 可区分。
		gpHost.gpSetState("status.autosaved", [gpFilePath])
		return
	var gpPackCount: int = gpHost.gpActiveGraph().gpUserSymbolPacks.size()
	gpHost.gpSetState("status.saved_with_packs", [gpFilePath, gpPackCount])


# Read a project from disk and swap it into the active canvas.
# 从磁盘读入工程并替换为当前活动画布。
# File parsing/decoding is delegated to GPProjectIO; the graph-swap and UI refresh that
# follow stay here because they touch the canvas, dock and selection state.
# 文件解析/解码交给 GPProjectIO；其后的图切换与 UI 刷新仍在此处，因为它们涉及画布、停靠栏与选择状态。
func gpReadProject(gpPath: String) -> void:
	# Read as SHEETS, not as one graph: a v3 file may carry several pages, and even a v1/v2
	# file comes back as a one-element list, so there is no special case.
	# 以**图纸**为单位读取，而非读成一张图：v3 文件可能含多页，
	# 即便 v1/v2 文件也返回单元素列表，故无特例分支。
	# GPIOResult distinguishes a missing file from malformed JSON, and gpReadSheets() keeps
	# that taxonomy (io.open_failed vs io.parse_failed).
	# GPIOResult 区分「文件缺失」与「JSON 损坏」，gpReadSheets() 保持该分类
	# （io.open_failed 与 io.parse_failed）。
	var gpSheetsResult: GPIOResult = GPProjectIO.gpReadSheets(gpPath)
	if not gpSheetsResult.gpIsOk():
		gpHost.gpSetState("status.load_fail", [gpPath])
		return
	var gpSheets: Array = gpSheetsResult.gpPayload as Array
	if gpSheets.is_empty():
		gpHost.gpSetState("status.load_fail", [gpPath])
		return
	var gpNewGraph: GPPIDGraph = (gpSheets[0] as GPSheet).gpGraph
	# Rebuild EVERY tab, not just the active one: a multi-sheet file whose extra sheets were
	# silently dropped would look fine until the engineer printed the missing page.
	# 重建**每个**标签页，而不只是活动页：一个多图纸文件若其余图纸被静默丢弃，
	# 在工程师打印那张缺页之前看起来一切正常。
	gpHost.gpCenter.gpLoadSheets(gpSheets)
	gpHost.gpActiveCanvas().gpGraph = gpNewGraph
	# swap the active document in the manager (resets dirty, announces the change on the bus).
	# 在管理器中切换当前文档（重置脏标记并总线通告变更）。
	gpHost.gpDocManager.gpSetGraph(gpNewGraph)
	gpHost.gpDefs = GPSymbolLibrary.gpDefaultDefs()
	gpHost.gpSyncInspectorDefs()
	# the library may have moved on since this file was saved. Migrate renamed fields
	# first (values follow the rename), then TELL the user — an unreported field change is how
	# a drawing quietly stops matching the plant.
	# 自本文件存盘以来，库可能已经变了。先迁移改名字段（取值跟随改名），
	# 再**告知**用户 —— 不报告的字段变更正是图纸悄悄与现场脱节的原因。
	gpHost.gpReconcileLibraryDrift(gpNewGraph)
	gpHost.gpLeftDock.gpPopulate(gpHost.gpDefs)
	gpHost.gpActiveCanvas().gpDefs = gpHost.gpDefs
	gpHost.gpActiveCanvas().gpClearSelection()
	gpHost.gpActiveCanvas().gpConnectFrom = ""
	gpHost.gpActiveCanvas().gpShapeSel.clear()
	gpHost.gpActiveCanvas().queue_redraw()
	gpHost.gpCurrentPath = gpPath
	gpHost.gpSetState("status.loaded_with_packs", [gpPath, gpNewGraph.gpUserSymbolPacks.size()])


# Merge an archive into the active drawing.
# 把档案合并进活动图纸。
# The archive may be v1/v2/v3: the migration chain runs inside gpReadArchive(), so an old
# file is upgraded rather than rejected.
# 档案可以是 v1/v2/v3：迁移链在 gpReadArchive() 内部运行，故旧文件被升级而非拒绝。
func gpDoImport(gpPath: String) -> void:
	var gpRead: GPIOResult = GPProjectImport.gpReadArchive(gpPath)
	if not gpRead.gpIsOk():
		gpHost.gpSetState(gpRead.gpMessageKey, [gpPath])
		return
	var gpGraph: GPPIDGraph = gpHost.gpActiveGraph()
	var gpBefore: int = gpGraph.gpNodes.size()
	var gpMerge: GPIOResult = GPProjectImport.gpMergeInto(gpGraph,
		gpRead.gpPayload as Dictionary)
	if not gpMerge.gpIsOk():
		gpHost.gpSetState("status.import_fail", [gpPath])
		return
	var gpReport: GPImportReport = gpMerge.gpPayload as GPImportReport
	# Imported symbols may be new to the library, so both docks must be rebuilt.
	# 导入的图元对库可能是新的，故两个停靠栏都必须重建。
	gpHost.gpDefs = GPSymbolLibrary.gpDefaultDefs()
	gpHost.gpLeftDock.gpPopulate(gpHost.gpDefs)
	gpHost.gpActiveCanvas().gpDefs = gpHost.gpDefs
	gpHost.gpActiveCanvas().queue_redraw()
	# An import IS an edit: the drawing changed, so the dirty flag must follow.
	# 导入**就是**一次编辑：图纸变了，脏标记必须跟着走。
	gpHost.gpDocManager.gpMarkDirty()
	gpHost.gpSetState("status.imported", [gpPath, gpReport.gpCountOf(GPImportReport.GP_ERROR),
		gpReport.gpCountOf(GPImportReport.GP_WARNING)])
	# Warnings are not shown inline yet; the count in the status bar is the honest minimum
	# (a silent "imported OK" would hide a renamed tag).
	# 警告尚未内联展示；状态栏里的计数是诚实的最低限度
	# （一句静默的「导入成功」会掩盖被改名的位号）。
	if gpReport.gpCountOf(GPImportReport.GP_ERROR) > 0:
		print("G-PID import report: ", gpReport.gpSummary())


# Import a DEXPI XML file: read -> validate -> convert -> merge into the active drawing.
# 导入 DEXPI XML 文件：读取 -> 校验 -> 转换 -> 合并进当前图纸。
# Same non-destructive merge contract as gpDoImport (GPProjectImport): an import never
# shrinks the drawing. The DEXPI container reuses gpMergeInto, so it inherits every
# guarantee (uid reassignment, tag de-dup, non-destructive merge) for free — there is no
# second, divergent import implementation.
# 与 gpDoImport 相同的非破坏合并契约（GPProjectImport）：导入永不缩减图纸。
# DEXPI 容器复用 gpMergeInto，故免费获得全部保障（uid 重分配、位号去重、非破坏合并），
# 不存在第二套分叉的导入实现。
func gpDoImportDexpi(gpPath: String) -> void:
	# One entry point for the whole DEXPI import chain: the reader, validator and converter
	# are NOT called individually from the shell. This keeps the UI trivial and the contract
	# in exactly one place (see GPDexpiImporter.gpReadFileToV3).
	# DEXPI 导入整条链路只有一个入口：reader / validator / converter 不单独由外壳调用，
	# 使界面保持简单、契约只落在一处（见 GPDexpiImporter.gpReadFileToV3）。
	# The def lookup lets the importer REBIND each pipe end to the port nearest its stored
	# endpoint — without it, port_id stays "" and the renderer degrades to "first nozzle
	# port", drawing pipes on the wrong sides of the symbols.
	# 定义查找让导入器把每根管线端**重绑**到离其已存端点最近的端口 ——
	# 不传则 port_id 保持空串，渲染器降级到「期望用途第一个端口」，
	# 管线会被画到符号的错误侧面。
	var gpRes: GPIOResult = GPDexpiImporter.gpReadFileToV3(gpPath, Callable(gpHost, "gpDefFor"))
	if not gpRes.gpIsOk():
		gpHost.gpSetState(gpRes.gpMessageKey, [gpPath])
		return
	var gpPayload: Dictionary = gpRes.gpPayload as Dictionary
	var gpV3: Dictionary = gpPayload.get("v3", {}) as Dictionary
	var gpReport: GPImportReport = gpPayload.get("report", null) as GPImportReport
	var gpGraph: GPPIDGraph = gpHost.gpActiveGraph()
	var gpMerge: GPIOResult = GPProjectImport.gpMergeInto(gpGraph, gpV3,
		GPProjectImport.GP_MODE_MERGE)
	if not gpMerge.gpIsOk():
		gpHost.gpSetState("status.import_fail", [gpPath])
		return
	# Imported symbols may be new to the library, so both docks must be rebuilt (same as
	# gpDoImport).
	# 导入的图元对库可能为新，故两个停靠栏都要重建（同 gpDoImport）。
	gpHost.gpDefs = GPSymbolLibrary.gpDefaultDefs()
	gpHost.gpLeftDock.gpPopulate(gpHost.gpDefs)
	gpHost.gpActiveCanvas().gpDefs = gpHost.gpDefs
	gpHost.gpActiveCanvas().queue_redraw()
	# An import IS an edit: the drawing changed, so the dirty flag must follow.
	# 导入**就是**一次编辑：图纸变了，脏标记必须跟着走。
	gpHost.gpDocManager.gpMarkDirty()
	var gpErr: int = 0
	var gpWarn: int = 0
	if gpReport != null:
		gpErr = gpReport.gpCountOf(GPImportReport.GP_ERROR)
		gpWarn = gpReport.gpCountOf(GPImportReport.GP_WARNING)
	gpHost.gpSetState("status.imported", [gpPath, gpErr, gpWarn])
	if gpErr > 0 and gpReport != null:
		print("G-PID DEXPI import report: ", gpReport.gpSummary())


# Write one export container, whichever the registry says gpKind maps to.
# 写出 gpKind 在注册表中对应的那一种导出容器。
# The dispatch lives in the registry, so adding a format never touches this method again.
# 分派逻辑在注册表中，故新增格式再也不会碰到本方法。
func gpDoExport(gpPath: String, gpKind: String) -> void:
	# The save dialog does not append extensions: a bare typed name would land on disk with
	# no suffix at all. Completion lives in the registry (single source of truth) — it also
	# finishes a trailing ".pid" instead of doubling it ("W6.pid" -> "W6.pid.xml", never
	# "W6.pid.pid.xml").
	# 保存对话框不补扩展名：手打的裸名会以**无后缀**落盘。补全逻辑归注册表（单一事实来源）
	# —— 它还会补完结尾的「.pid」而非翻倍（「W6.pid」->「W6.pid.xml」，
	# 绝不产生「W6.pid.pid.xml」）。
	var gpExt: String = GPExporterRegistry.gpExtensionOf(gpKind)
	gpPath = GPExporterRegistry.gpFinishName(gpPath, gpExt)
	var gpPacks: Array = GPSymbolLibrary.gpUserPacks()
	var gpOut: GPIOResult = GPExporterRegistry.gpExport(gpKind, gpPath,
		gpHost.gpActiveGraph(), gpPacks, _gpActiveSheet())
	if not gpOut.gpIsOk():
		gpHost.gpSetState(gpOut.gpMessageKey, [gpPath])
		return
	var gpStats: Dictionary = gpOut.gpPayload as Dictionary
	# A failed cast yields null, and calling .get() on null would abort the export flow at the
	# very last step — after the file was already written.
	# 失败的转换会产出 null，而对 null 调 .get() 会让导出流程在**最后一步**中断 ——
	# 那时文件其实已经写好了。
	if gpStats == null:
		gpHost.gpSetState("status.exported", [gpPath, 0, 0])
		return
	gpHost.gpSetState("status.exported", [gpPath, int(gpStats.get("nodes", 0)),
		int(gpStats.get("edges", 0))])


# The sheet behind the active canvas. DEXPI needs it for the Diagram extent; other formats
# ignore it.
# 活动画布背后的图纸。DEXPI 需要它来给出 Diagram 范围；其它格式忽略它。
func _gpActiveSheet() -> GPSheet:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null:
		return null
	return gpCanvas.gpSheet
