class_name GPMenuCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Menu dispatch, undo/redo and the settings dialog; file actions are forwarded to GPFileCoordinator
# 菜单分发、撤销/重做与设置对话框；文件类动作转发给 GPFileCoordinator
#
# WHY THIS EXISTS / 为何存在（架构优化建议 §3.2）：
#   GPMainWindow was carrying many unrelated responsibilities in one file; this coordinator
#   owns the "Menu dispatch, undo/redo and the settings dialog" use case end to end, so the root keeps only assembly and forwarding.
#   GPMainWindow 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「菜单分发、撤销/重做与设置对话框；文件类动作转发给 GPFileCoordinator」这一用例，
#   使根类只保留装配与转发。
#
# Interaction / 交互方式：
#   - the root creates this coordinator and injects itself as gpHost (composition root);
#     根类创建本协调者并把自身注入为 gpHost（组合根装配）；
#   - the root forwards menu / toolbar actions here, never the other way round — this class
#     does not reach back into menus or the ribbon;
#     根类把菜单/工具栏动作转发到此处，绝不反向 —— 本类不回指菜单或 Ribbon；
#   - UI refresh goes through gpHost._gpSetState / the docks the root owns.
#     UI 刷新经由 gpHost._gpSetState 及根类持有的停靠栏完成。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPMainWindow = null


func gpDeleteSelected() -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null:
		return
	gpCanvas.gpDeleteSelection()


# ============================ state helper ============================
# ============================ 状态栏辅助 ============================
# Set the status bar text by i18n key and optional format arguments.
# 通过 i18n 键与可选格式化参数设置状态栏文本。

func gpOpenSettings() -> void:
	var gpDlg: GPSettingsDialog = (load("res://scenes/settings_dialog.tscn") as PackedScene).instantiate()
	gpHost.add_child(gpDlg)
	# gpPopupOverHost() sizes the dialog against the area that actually contains it; the bare
	# popup_centered() ignores `size` and can place an oversized dialog at a negative position.
	# gpPopupOverHost() 依据真正容纳它的区域取尺寸；裸 popup_centered() 会忽略 `size`，
	# 并可能把超大对话框放到负坐标。
	gpDlg.gpPopupOverHost()

# Menu 编辑 / 重做.
# 菜单「编辑 / 重做」。
func gpMenuRedo() -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null:
		return
	if gpCanvas.gpRedo():
		gpHost._gpSetState("status.redone")
	else:
		gpHost._gpSetState("status.nothing_to_redo")
	gpRefreshEditMenu()


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
# NOTE / 注：the close is intercepted through get_window().close_requested (wired in
# _ready), NOT _notification(NOTIFICATION_WM_CLOSE_REQUEST). On a Control scene root the
# WM notification is not reliably delivered in Godot 4, so the dialog would silently fail
# to appear. The signal fires on the real Window and is the canonical interception point.
# 关闭经由 get_window().close_requested（在 _ready 接线）拦截，而非
# _notification(NOTIFICATION_WM_CLOSE_REQUEST)。在 Control 场景根上该 WM 通知在 Godot 4
# 中不可靠地送达，对话框会静默不出现。信号在真正的 Window 上触发，是权威拦截点。


# Close path: clean -> quit immediately; dirty -> ask, never decide for the user.
# 关闭路径：干净 -> 立即退出；脏 -> 询问，绝不替用户决定。

# Menu 编辑 / 撤销. The canvas owns the stack, so all this does is ask and report.
# 菜单「编辑 / 撤销」。撤销栈归画布所有，故此处只负责发问与报告。
func gpMenuUndo() -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null:
		return
	if gpCanvas.gpUndo():
		gpHost._gpSetState("status.undone")
	else:
		gpHost._gpSetState("status.nothing_to_undo")
	gpRefreshEditMenu()

# Sync 撤销 / 重做 enabled state with the active sheet. No sheet means nothing to undo.
# 同步「撤销 / 重做」的可用状态与活动图纸。没有图纸即无可撤销。
func gpRefreshEditMenu() -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	var gpCanUndo: bool = gpCanvas != null and gpCanvas.gpCanUndo()
	var gpCanRedo: bool = gpCanvas != null and gpCanvas.gpCanRedo()
	gpHost.gpMenuBar.gpSetActionEnabled("edit_undo", gpCanUndo)
	gpHost.gpMenuBar.gpSetActionEnabled("edit_redo", gpCanRedo)

func gpOnMenuOpening(gpTitleKey: String) -> void:
	if gpTitleKey != "menu.edit":
		return
	gpRefreshEditMenu()

func gpOnMenu(gpAction: String) -> void:
	match gpAction:
		"file_new", "edit_clear":
			gpHost.gpActiveGraph().gpNodes.clear()
			gpHost.gpActiveGraph().gpEdges.clear()
			gpHost.gpActiveGraph().gpShapes.clear()
			gpHost.gpActiveCanvas().gpNextId = 1
			gpHost.gpActiveCanvas().gpClearSelection()
			gpHost.gpActiveCanvas().gpConnectFrom = ""
			gpHost.gpActiveCanvas().gpPendingDef = null
			gpHost.gpActiveCanvas().queue_redraw()
			gpHost._gpSetState("status.cleared")
		"file_save":
			gpHost.gpFileCoord.gpSaveProject(false)
		"file_save_as":
			gpHost.gpFileCoord.gpSaveProject(true)
		"file_open":
			gpHost.gpFileCoord.gpOpenProject()
		"file_import":
			gpHost.gpFileCoord.gpImportProject()
		"file_quit":
			# Route through the SAME close guard as the OS window-close button so the
			# unsaved-changes dialog behaves identically whether the user clicks the red X
			# or picks Quit from the menu. Used to diagnose whether the red X reaches
			# NOTIFICATION_WM_CLOSE_REQUEST at all.
			# 走与 OS 关闭按钮**完全相同**的关闭护栏，使未保存对话框在「点红 X」与
			# 「菜单退出」两种入口下表现一致。用于排查红 X 是否真的触发了关闭通知。
			gpHost.gpFileCoord.gpOnCloseRequested()
		"export_project":
			gpHost.gpFileCoord.gpPickExportPath("project")
		"export_library":
			gpHost.gpFileCoord.gpPickExportPath("library")
		"export_config":
			gpHost.gpFileCoord.gpPickExportPath("config")
		"view_zoom_in":
			gpHost.gpActiveCanvas().gpZoomStep(1.0)
		"view_zoom_out":
			gpHost.gpActiveCanvas().gpZoomStep(-1.0)
		"view_fit":
			gpHost.gpActiveCanvas().gpResetView()
			gpHost._gpSetState("status.view_reset")
		"edit_delete":
			if gpHost.gpActiveCanvas().gpSelectedId != "":
				gpDeleteSelected()
		"edit_undo":
			gpMenuUndo()
		"edit_redo":
			gpMenuRedo()
		"tool_settings":
			gpOpenSettings()
		"project_tag_rules":
			gpHost.gpTagCoord.gpOpenTagRuleDialog()
		_:
			gpHost._gpSetState("status.feature_todo", [gpAction])
