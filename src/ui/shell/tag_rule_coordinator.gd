class_name GPTagRuleCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Tag-rule dialog orchestration and the renumber workflow
# 位号规则对话框编排与重编号工作流
#
# WHY THIS EXISTS / 为何存在：
# GPMainWindow was carrying many unrelated responsibilities in one file; this coordinator
# owns the "Tag-rule dialog orchestration and the renumber workflow" use case end to end, so the root keeps only assembly and forwarding.
# GPMainWindow 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「位号规则对话框编排与重编号工作流」这一用例，
# 使根类只保留装配与转发。
#
# Interaction / 交互方式：
# - the root creates this coordinator and injects itself as gpHost (composition root);
# 根类创建本协调者并把自身注入为 gpHost（组合根装配）；
# - the root forwards menu / toolbar actions here, never the other way round — this class
# does not reach back into menus or the ribbon;
# 根类把菜单/工具栏动作转发到此处，绝不反向 —— 本类不回指菜单或 Ribbon；
# - UI refresh goes through gpHost.gpSetState() / the docks the root owns.
# UI 刷新经由 gpHost.gpSetState() 及根类持有的停靠栏完成。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPMainWindow = null


# Run the renumber command and report how many tags changed.
# 执行重编号命令并报告变动了多少位号。
func gpDoRenumberTags() -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null:
		return
	if not gpCanvas.gpActions.gpRenumberTags():
		gpHost.gpSetState("tag_rule.applied")
		return
	var gpChanged: int = GPTagRuleService.gpChangedCount(gpCanvas.gpActions.gpLastTagMapping)
	gpHost.gpSetState("tag_rule.renumbered", [gpChanged])
	gpCanvas.queue_redraw()
	gpHost.gpSelCoord.gpRefreshSelection()


# Refresh 编辑 menu items against the live undo stack, called just before the popup
# opens. The menu bar itself never learns what a canvas is; it only asks.
# 在菜单展开前依据实时撤销栈刷新「编辑」菜单项。菜单栏本身不需要知道画布是什么，
# 它只是发问。

# Ask before renumbering: the change is reversible in the app but NOT on a printed
# nameplate, so the user must see the count first.
# 重编号前先询问：本改动在软件内可撤销，但在已印好的标牌上不可撤销，
# 故必须先让用户看到数量。
func gpConfirmRenumberTags() -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null:
		return
	var gpCount: int = gpCanvas.gpGraph.gpNodes.size()
	if gpCount == 0:
		gpHost.gpSetState("tag_rule.applied")
		return
	var gpDlg: ConfirmationDialog = ConfirmationDialog.new()
	gpDlg.title = I18n.gpTr("tag_rule.confirm_title")
	gpDlg.dialog_text = I18n.gpTr("tag_rule.renumber_confirm") % [gpCount]
	gpHost.add_child(gpDlg)
	gpDlg.confirmed.connect(func():
		gpDoRenumberTags()
		gpDlg.queue_free())
	gpDlg.canceled.connect(gpDlg.queue_free)
	gpDlg.popup_centered()

# Apply the standard to EVERY sheet, then optionally renumber (with a confirmation, because a
# tag ends up on a physical nameplate and in the DCS point list).
# 把标准套用到**每一张**图纸，然后可选地重编号（需确认，因为位号会落到现场标牌与 DCS 点表上）。
func gpOnStandardApplied(gpStd: GPProjectStandard, gpRenumber: bool) -> void:
	if gpStd == null:
		return
	gpHost.gpCenter.gpApplyStandard(gpStd)
	# The sheet list may have grown since the dialog opened; re-announce it so every registry
	# judges uniqueness against all sheets with the NEW scopes.
	# 对话框打开后图纸列表可能变过；重新通告一次，使每个注册器按**新**作用域判断唯一性。
	gpHost.gpCenter.gpSyncProjectGraphs()
	gpHost.gpSetState("standard.applied")
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas != null:
		gpCanvas.queue_redraw()
		gpHost.gpSelCoord.gpRefreshSelection()
	if gpRenumber:
		gpConfirmRenumberTags()


# Menu 项目 / 项目标准 . The dialog edits a copy and hands it back; renumbering is a separate,
# confirmed, single-undo-step operation.
# 菜单「项目 / 项目标准」。对话框编辑副本并交回；重编号是独立的、需确认的、单撤销步操作。
func gpOpenTagRuleDialog() -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null:
		return
	# Deliberately UNTYPED + load(): annotating would pull the dialog into the startup graph.
	# 刻意不写类型标注并用 load()：标注会把该对话框拉进启动依赖图。
	var gpDlg = (load("res://src/ui/dialogs/project_standard_dialog.gd") as GDScript).new()
	gpHost.add_child(gpDlg)
	gpDlg.gpStandardApplied.connect(gpOnStandardApplied)
	# ADR-38: "renumber all sheets" is a separate, explicit action — it changes printed numbers.
	# ADR-38：「重编全部图纸编号」是独立的显式动作 —— 它会改变已打印的图号。
	gpDlg.gpSheetsRenumberRequested.connect(func() -> void:
		gpHost.gpCenter.gpRenumberSheets()
		gpHost.gpSetState("standard.applied"))
	gpDlg.gpStatus.connect(func(gpKey: String, gpArgs: Array) -> void:
		gpHost.gpSetState(gpKey, gpArgs))
	gpDlg.gpShowStandard(gpCanvas.gpGraph.gpStandardOrCreate())
	# Free the dialog on close either way; it is a one-shot editor, not a panel.
	# 无论何种关闭方式都释放对话框：它是一次性编辑器，而非常驻面板。
	gpDlg.close_requested.connect(gpDlg.queue_free)
	gpDlg.confirmed.connect(gpDlg.queue_free)
	gpDlg.canceled.connect(gpDlg.queue_free)
