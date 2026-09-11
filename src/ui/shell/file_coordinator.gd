class_name GPFileCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Project file lifecycle: save / open / import / export / the unsaved-changes close guard.
# 工程文件生命周期：保存 / 打开 / 导入 / 导出 / 未保存关闭拦截。
#
# WHY THIS EXISTS / 为何存在（架构优化建议 §3.2）：
#   GPMainWindow had grown to 1,759 lines carrying eight unrelated responsibilities; the file
#   lifecycle alone was ~360 of them. This coordinator owns that one use case end to end —
#   the file dialog, the current-path bookkeeping, the dirty-flag settlement and the exit
#   three-way — so the root keeps only assembly and forwarding.
#   GPMainWindow 一度膨胀到 1,759 行、承载八类互不相关的职责，其中文件生命周期独占约 360 行。
#   本协调者端到端接管这一用例 —— 文件对话框、当前路径记账、脏标记结算与退出三选一 ——
#   使根类只保留装配与转发。
#
# Interaction / 交互方式：
#   - the root creates this coordinator and injects itself as gpHost (composition root);
#     根类创建本协调者并把自身注入为 gpHost（组合根装配）；
#   - the root forwards menu / toolbar actions here, never the other way round — this class
#     does not reach back into menus or the ribbon;
#     根类把菜单/工具栏动作转发到此处，绝不反向 —— 本类不回指菜单或 Ribbon；
#   - UI refresh goes through gpHost._gpSetState / the docks it owns.
#     UI 刷新经由 gpHost._gpSetState 及其持有的停靠栏完成。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPMainWindow = null


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
# NOTE / 注：the close is intercepted through get_window().close_requested (wired by the
# root), NOT _notification(NOTIFICATION_WM_CLOSE_REQUEST). On a Control scene root the WM
# notification is not reliably delivered in Godot 4, so the dialog would silently fail to
# appear. The signal fires on the real Window and is the canonical interception point.
# 关闭经由 get_window().close_requested（由根类接线）拦截，而非
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
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("dialog.unsaved_title")
	gpDlg.dialog_text = I18n.gpTr("dialog.unsaved_text")
	gpDlg.get_ok_button().text = I18n.gpTr("dialog.unsaved_save")
	gpDlg.get_cancel_button().text = I18n.gpTr("dialog.cancel")
	gpDlg.add_button(I18n.gpTr("dialog.unsaved_discard"), true, "discard")
	gpDlg.confirmed.connect(gpOnUnsavedSave.bind(gpDlg))
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.custom_action.connect(gpOnUnsavedDiscard.bind(gpDlg))
	gpHost.add_child(gpDlg)
	gpDlg.popup_centered()


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
		gpHost.gpFileDialog.popup_centered()
		return
	gpWriteProject(gpHost.gpCurrentPath)


# Open an existing project from disk.
# 从磁盘打开已有工程。
func gpOpenProject() -> void:
	gpHost.gpPendingFileAction = "open"
	gpHost.gpFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	gpHost.gpFileDialog.popup_centered()


# Merge an archive INTO the current drawing (non-destructive: nothing here is replaced).
# 把档案**合并进**当前图纸（非破坏：此处不替换任何东西）。
func gpImportProject() -> void:
	gpHost.gpPendingFileAction = "import"
	gpHost.gpFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	gpHost.gpFileDialog.popup_centered()


# Ask where to write an export container. Export is NOT save-as: the current path is
# untouched and the in-memory drawing is not modified.
# 询问导出容器写到哪里。导出不是另存为：当前路径不变，内存中的图纸也不被修改。
func gpPickExportPath(gpKind: String) -> void:
	gpHost.gpPendingFileAction = "export_" + gpKind
	gpHost.gpFileDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	gpHost.gpFileDialog.popup_centered()


# Forward the file-dialog result to the right handler.
# 把文件对话框的结果转交给对应处理。
func gpOnFileSelected(gpPath: String) -> void:
	if gpHost.gpPendingFileAction == "save":
		gpWriteProject(gpPath)
	elif gpHost.gpPendingFileAction == "open":
		gpReadProject(gpPath)
	elif gpHost.gpPendingFileAction == "import":
		gpDoImport(gpPath)
	elif gpHost.gpPendingFileAction.begins_with("export_"):
		gpDoExport(gpPath, gpHost.gpPendingFileAction.trim_prefix("export_"))


# Serialize the active graph (with embedded user packs) and write it to disk.
# 把活动图（含内嵌用户图元包）序列化并写入磁盘。
# The actual file mechanics live in GPProjectIO (single source of truth for *.pid.json);
# this method only owns UI-side concerns (embedding packs, status, path bookkeeping).
# 真正的文件机制在 GPProjectIO（*.pid.json 的单一事实来源）；本方法仅负责 UI 关注点
# （嵌入图元包、状态栏、路径记账）。
func gpWriteProject(gpPath: String) -> void:
	# Embed custom user packs so the file is self-contained (data sovereignty).
	# 嵌入用户自定义图元包，使文件自包含（数据主权）。
	gpHost.gpActiveGraph().gpEmbedUserPacks(GPSymbolLibrary.gpUserPacks())
	# M12: stamp the library's schema fingerprints into the file so a later open can detect
	# that a field was added, renamed or deleted in the meantime.
	# M12：把库的 schema 指纹盖进文件，使日后打开能察觉期间字段被增 / 改名 / 删过。
	gpHost.gpActiveGraph().gpSchemaFingerprints = GPPropertyResolver.gpFingerprintsFor(gpHost.gpDefs)
	var gpFilePath: String = GPProjectIO.gpEnsurePidExt(gpPath)
	# A leftover .tmp means the last save died mid-write. Discard it: the target is still the
	# previous good copy, and a stale .tmp would otherwise confuse a later reader (E4).
	# 残留的 .tmp 意味着上次保存写了一半就死了。清掉它：目标仍是上一份完好副本，
	# 而陈旧的 .tmp 否则会迷惑日后的读取方（E4）。
	if GPAtomicFile.gpHasTempRemains(gpFilePath):
		GPAtomicFile.gpDiscardTempRemains(gpFilePath)
		gpHost._gpSetState("status.tmp_cleaned", [gpFilePath])
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
		gpWriteResult = GPProjectIO.gpWriteProjectResult(gpHost.gpActiveGraph(), gpFilePath)
	if not gpWriteResult.gpIsOk():
		gpHost._gpSetState("status.save_fail", [gpFilePath])
		return
	gpHost.gpCurrentPath = gpFilePath
	# M6: a successful save clears the unsaved-dirty flag so the title bar / project tree update.
	# M6：保存成功清除未保存脏标记，使标题栏/工程树同步。
	gpHost.gpDocManager.gpClearDirty()
	# Honour a pending quit from the close guard (path-less save-as on exit).
	# 兑现关闭拦截留下的待退出（退出时无路径的另存为）。
	if gpHost.gpQuitAfterSave:
		gpHost.gpQuitAfterSave = false
		gpHost.get_tree().quit()
		return
	var gpPackCount: int = gpHost.gpActiveGraph().gpUserSymbolPacks.size()
	gpHost._gpSetState("status.saved_with_packs", [gpFilePath, gpPackCount])


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
	# GPIOResult distinguishes a missing file from malformed JSON, and gpReadSheets keeps
	# that taxonomy (io.open_failed vs io.parse_failed).
	# GPIOResult 区分「文件缺失」与「JSON 损坏」，gpReadSheets 保持该分类
	# （io.open_failed 与 io.parse_failed）。
	var gpSheetsResult: GPIOResult = GPProjectIO.gpReadSheets(gpPath)
	if not gpSheetsResult.gpIsOk():
		gpHost._gpSetState("status.load_fail", [gpPath])
		return
	var gpSheets: Array = gpSheetsResult.gpPayload as Array
	if gpSheets.is_empty():
		gpHost._gpSetState("status.load_fail", [gpPath])
		return
	var gpNewGraph: GPPIDGraph = (gpSheets[0] as GPSheet).gpGraph
	# Rebuild EVERY tab, not just the active one: a multi-sheet file whose extra sheets were
	# silently dropped would look fine until the engineer printed the missing page.
	# 重建**每个**标签页，而不只是活动页：一个多图纸文件若其余图纸被静默丢弃，
	# 在工程师打印那张缺页之前看起来一切正常。
	gpHost.gpCenter.gpLoadSheets(gpSheets)
	gpHost.gpActiveCanvas().gpGraph = gpNewGraph
	# M6: swap the active document in the manager (resets dirty, announces the change on the bus).
	# M6：在管理器中切换当前文档（重置脏标记并总线通告变更）。
	gpHost.gpDocManager.gpSetGraph(gpNewGraph)
	gpHost.gpDefs = GPSymbolLibrary.gpDefaultDefs()
	gpHost._gpSyncInspectorDefs()
	# M12: the library may have moved on since this file was saved. Migrate renamed fields
	# first (values follow the rename), then TELL the user — an unreported field change is how
	# a drawing quietly stops matching the plant.
	# M12：自本文件存盘以来，库可能已经变了。先迁移改名字段（取值跟随改名），
	# 再**告知**用户 —— 不报告的字段变更正是图纸悄悄与现场脱节的原因。
	gpHost._gpReconcileLibraryDrift(gpNewGraph)
	gpHost.gpLeftDock.gpPopulate(gpHost.gpDefs)
	gpHost.gpActiveCanvas().gpDefs = gpHost.gpDefs
	gpHost.gpActiveCanvas().gpClearSelection()
	gpHost.gpActiveCanvas().gpConnectFrom = ""
	gpHost.gpActiveCanvas().gpShapeSel.clear()
	gpHost.gpActiveCanvas().queue_redraw()
	gpHost.gpCurrentPath = gpPath
	gpHost._gpSetState("status.loaded_with_packs", [gpPath, gpNewGraph.gpUserSymbolPacks.size()])


# Merge an archive into the active drawing.
# 把档案合并进活动图纸。
# The archive may be v1/v2/v3: the migration chain runs inside gpReadArchive, so an old
# file is upgraded rather than rejected.
# 档案可以是 v1/v2/v3：迁移链在 gpReadArchive 内部运行，故旧文件被升级而非拒绝。
func gpDoImport(gpPath: String) -> void:
	var gpRead: GPIOResult = GPProjectImport.gpReadArchive(gpPath)
	if not gpRead.gpIsOk():
		gpHost._gpSetState(gpRead.gpMessageKey, [gpPath])
		return
	var gpGraph: GPPIDGraph = gpHost.gpActiveGraph()
	var gpBefore: int = gpGraph.gpNodes.size()
	var gpMerge: GPIOResult = GPProjectImport.gpMergeInto(gpGraph,
		gpRead.gpPayload as Dictionary)
	if not gpMerge.gpIsOk():
		gpHost._gpSetState("status.import_fail", [gpPath])
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
	gpHost._gpSetState("status.imported", [gpPath, gpReport.gpCountOf(GPImportReport.GP_ERROR),
		gpReport.gpCountOf(GPImportReport.GP_WARNING)])
	# Warnings are not shown inline yet; the count in the status bar is the honest minimum
	# (a silent "imported OK" would hide a renamed tag).
	# 警告尚未内联展示；状态栏里的计数是诚实的最低限度
	# （一句静默的「导入成功」会掩盖被改名的位号）。
	if gpReport.gpCountOf(GPImportReport.GP_ERROR) > 0:
		print("G-PID import report: ", gpReport.gpSummary())


# Write one of the three export containers.
# 写出三种导出容器之一。
func gpDoExport(gpPath: String, gpKind: String) -> void:
	var gpPacks: Array = GPSymbolLibrary.gpUserPacks()
	var gpOut: GPIOResult = GPProjectExport.gpExportToFile(gpKind, gpPath,
		gpHost.gpActiveGraph(), gpPacks)
	if not gpOut.gpIsOk():
		gpHost._gpSetState(gpOut.gpMessageKey, [gpPath])
		return
	var gpStats: Dictionary = gpOut.gpPayload as Dictionary
	gpHost._gpSetState("status.exported", [gpPath, int(gpStats.get("nodes", 0)),
		int(gpStats.get("edges", 0))])
