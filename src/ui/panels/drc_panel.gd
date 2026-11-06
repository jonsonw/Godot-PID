class_name GPDRCPanel
extends VBoxContainer
# Copyright © 2026 Jonson Wang
#
# The health-check panel (B2): run the seven rules, list the findings by severity, jump to a
# finding, export a text / CSV report.
# 体检面板（B2）：跑七条规则、按严重度列出发现、跳转到某条、导出文本 / CSV 报告。
#
# Why a dock tab and not a modal dialog / 为何是停靠页而非模态对话框：
# DRC is a LOOP ("fix, re-run, fix"), not a one-shot. A modal makes every iteration cost two open
# and close actions; a dock keeps the list in sight while the user edits the drawing.
# DRC 是一个**循环**（改 → 再跑 → 再改），不是一次性动作。模态框会让每次迭代多两次开合；
# 停靠页让列表在用户改图时一直可见。
#
# What the panel owns / 面板持有什么：
# only the LAST run's findings and the row widgets. It never caches the graph; every run re-reads
# the canvas, so a stale row can never point at an object that has since moved or died.
# 只持有**最近一次**运行的发现与行控件。它绝不缓存图；每次运行都重读画布，故过期行不可能指向
# 一个已经移动或消失的对象。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# A finding row was clicked; the shell centres the view on it.
# 某条发现行被点击；外壳把视图对准它。
signal gpFindingActivated(gpWorld: Vector2)

# The full finding (ADR-39): the dialog uses it to select the object and switch to the property
# tab; the dock panel uses it to select WITHOUT changing the visible tab.
# 完整发现（ADR-39）：弹窗用它选中对象并切到属性页；停靠面板用它选中对象但**不**切页。
signal gpFindingActivatedFull(gpFinding: GPFinding)

# The current finding list changed (manual run or live scheduler). The shell uses it for the
# screen-space badge overlay.
# 当前发现列表变化（手动或实时调度）。外壳用它刷新屏幕空间角标。
signal gpFindingsChanged(gpFindings: Array[GPFinding])

# The canvas whose graph is checked (null until bound).
# 被检查的画布（绑定前为 null）。
var _gpCanvas: GPCanvas2D = null

# Findings of the last run.
# 最近一次运行的发现。
var _gpFindings: Array[GPFinding] = []

# "Whole project" mode: judge uniqueness / compliance across every sheet (ADR-36 C). The panel
# asks the shell for the sheet list instead of reaching into the tab bar itself.
# 「全工程」模式：跨所有图纸判断唯一性 / 合规（ADR-36 C）。面板向宿主索取图纸列表，
# 自己不去掏标签栏。
var _gpProjectMode: CheckBox = null
var _gpSheetsProvider: Callable = Callable()

# Container link-table provider for the off-page audit (W12-S4).
# 容器 link 表来源，供跨图纸审计用（W12-S4）。
var _gpLinksProvider: Callable = Callable()

var _gpSummary: Label = null
var _gpList: VBoxContainer = null
var _gpScroll: ScrollContainer = null
var _gpRunBtn: Button = null
var _gpTxtBtn: Button = null
var _gpCsvBtn: Button = null
var _gpJsonBtn: Button = null
var _gpWaiveBtn: Button = null
var _gpRevokeBtn: Button = null
var _gpSevFilter: OptionButton = null
var _gpFilterSev: int = 0
var _gpWaiverDialog: GPWaiverDialog = null
var _gpLastFinding: GPFinding = null


# Build the widgets. Call once, before gpBindCanvas().
# 构建控件。在 gpBindCanvas() 之前调用一次。
func gpBuild() -> void:
	add_theme_constant_override("separation", 4)
	var gpTitle: Label = Label.new()
	gpTitle.text = I18n.gpTr("drc.panel_title")
	gpTitle.add_theme_font_size_override("font_size", 14)
	add_child(gpTitle)
	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 4)
	_gpRunBtn = Button.new()
	_gpRunBtn.text = I18n.gpTr("drc.run")
	_gpRunBtn.pressed.connect(gpRun)
	gpRow.add_child(_gpRunBtn)
	_gpProjectMode = CheckBox.new()
	_gpProjectMode.text = I18n.gpTr("drc.project_mode")
	gpRow.add_child(_gpProjectMode)
	add_child(gpRow)
	# Export controls get their own row: the right dock is only ~200 px wide, and five buttons
	# in one row would be clipped (the JSON button added the last straw).
	# 导出控件单独一行：右停靠栏只有约 200px，五个按钮挤一行会被裁掉（JSON 按钮是最后一根稻草）。
	var gpRow2: HBoxContainer = HBoxContainer.new()
	gpRow2.add_theme_constant_override("separation", 4)
	_gpTxtBtn = Button.new()
	_gpTxtBtn.text = I18n.gpTr("drc.export_txt")
	_gpTxtBtn.disabled = true
	_gpTxtBtn.pressed.connect(func() -> void: _gpExport(false))
	gpRow2.add_child(_gpTxtBtn)
	_gpCsvBtn = Button.new()
	_gpCsvBtn.text = I18n.gpTr("drc.export_csv")
	_gpCsvBtn.disabled = true
	_gpCsvBtn.pressed.connect(func() -> void: _gpExport(true))
	gpRow2.add_child(_gpCsvBtn)
	_gpJsonBtn = Button.new()
	_gpJsonBtn.text = I18n.gpTr("drc.export_json")
	_gpJsonBtn.disabled = true
	_gpJsonBtn.pressed.connect(func() -> void: _gpExportJson())
	gpRow2.add_child(_gpJsonBtn)
	_gpWaiveBtn = Button.new()
	_gpWaiveBtn.text = I18n.gpTr("drc.waive_request")
	_gpWaiveBtn.disabled = true
	_gpWaiveBtn.pressed.connect(_gpOnWaiverPressed)
	add_child(gpRow2)
	var gpRow3: HBoxContainer = HBoxContainer.new()
	gpRow3.add_theme_constant_override("separation", 4)
	gpRow3.add_child(_gpWaiveBtn)
	_gpRevokeBtn = Button.new()
	_gpRevokeBtn.text = I18n.gpTr("drc.waive_revoke")
	_gpRevokeBtn.disabled = true
	_gpRevokeBtn.pressed.connect(_gpOnRevokePressed)
	gpRow3.add_child(_gpRevokeBtn)
	_gpSevFilter = OptionButton.new()
	_gpSevFilter.add_item(I18n.gpTr("drc.dialog_filter_all"), 0)
	_gpSevFilter.add_item(I18n.gpTr("drc.dialog_filter_error"), 1)
	_gpSevFilter.add_item(I18n.gpTr("drc.dialog_filter_warning"), 2)
	_gpSevFilter.add_item(I18n.gpTr("drc.dialog_filter_info"), 3)
	_gpSevFilter.item_selected.connect(_gpOnSevFilter)
	gpRow3.add_child(_gpSevFilter)
	add_child(gpRow3)
	_gpSummary = Label.new()
	_gpSummary.text = I18n.gpTr("drc.never_run")
	_gpSummary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_gpSummary)
	_gpScroll = ScrollContainer.new()
	_gpScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_gpScroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_gpScroll)
	_gpList = VBoxContainer.new()
	_gpList.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gpList.add_theme_constant_override("separation", 2)
	_gpScroll.add_child(_gpList)


# Point the panel at a canvas and refresh the localized text.
# 把面板指向某画布并刷新本地化文字。
func gpBindCanvas(gpCanvas: GPCanvas2D) -> void:
	_gpCanvas = gpCanvas


# Install the sheet-list provider used by "whole project" mode.
# 安装「全工程」模式使用的图纸列表来源。
func gpSetSheetsProvider(gpProvider: Callable) -> void:
	_gpSheetsProvider = gpProvider


# Install the container link-table provider for the off-page audit (W12-S4). Optional: an
# invalid provider just runs the project audit without the cross-sheet rules.
# 安装容器 link 表来源，供跨图纸审计使用（W12-S4）。可选：无效来源只是不带跨图纸规则
# 跑工程审计。
func gpSetLinksProvider(gpProvider: Callable) -> void:
	_gpLinksProvider = gpProvider


# Refresh static text after a locale change.
# 语言切换后刷新静态文字。
func gpRefreshText() -> void:
	if _gpProjectMode != null:
		_gpProjectMode.text = I18n.gpTr("drc.project_mode")
	if _gpRunBtn != null:
		_gpRunBtn.text = I18n.gpTr("drc.run")
		_gpTxtBtn.text = I18n.gpTr("drc.export_txt")
		_gpCsvBtn.text = I18n.gpTr("drc.export_csv")
		if _gpJsonBtn != null:
			_gpJsonBtn.text = I18n.gpTr("drc.export_json")
		if _gpWaiveBtn != null:
			_gpWaiveBtn.text = I18n.gpTr("drc.waive_request")
		if _gpRevokeBtn != null:
			_gpRevokeBtn.text = I18n.gpTr("drc.waive_revoke")
		if _gpSevFilter != null and _gpSevFilter.item_count >= 4:
			_gpSevFilter.set_item_text(0, I18n.gpTr("drc.dialog_filter_all"))
			_gpSevFilter.set_item_text(1, I18n.gpTr("drc.dialog_filter_error"))
			_gpSevFilter.set_item_text(2, I18n.gpTr("drc.dialog_filter_warning"))
			_gpSevFilter.set_item_text(3, I18n.gpTr("drc.dialog_filter_info"))
	if _gpFindings.is_empty():
		_gpSummary.text = I18n.gpTr("drc.never_run")


# Run the registered DRC rules on the bound canvas and rebuild the list.
# 在绑定画布上跑注册的 DRC 规则并重建列表。
func gpRun() -> void:
	if _gpCanvas == null or _gpCanvas.gpGraph == null:
		_gpFindings = []
		_gpSummary.text = I18n.gpTr("drc.no_canvas")
		_gpRebuildRows()
		return
	if _gpProjectMode != null and _gpProjectMode.button_pressed and _gpSheetsProvider.is_valid():
		var gpSheets: Array = _gpSheetsProvider.call()
		var gpStd: GPProjectStandard = _gpCanvas.gpGraph.gpStandard
		var gpLinks: Array[GPOffPageLink] = []
		if _gpLinksProvider.is_valid():
			gpLinks = _gpLinksProvider.call() as Array[GPOffPageLink]
		_gpFindings = GPDrcEngine.gpRunProject(gpSheets, _gpCanvas.gpDefs, gpStd, gpLinks)
	else:
		_gpFindings = GPDrcEngine.gpRunSheet(_gpCanvas.gpGraph, _gpCanvas.gpSheet,
			_gpCanvas.gpDefs, _gpCanvas.gpGraph.gpStandard)
	_gpSummary.text = GPDRCReport.gpSummary(_gpFindings)
	_gpTxtBtn.disabled = _gpFindings.is_empty()
	_gpCsvBtn.disabled = _gpFindings.is_empty()
	if _gpJsonBtn != null:
		_gpJsonBtn.disabled = _gpFindings.is_empty()
	_gpRebuildRows()
	gpFindingsChanged.emit(_gpFindings)


# The findings of the last run (the shell may also use them for its status line).
# 最近一次运行的发现（外壳也可用它更新状态栏）。
func gpFindings() -> Array[GPFinding]:
	return _gpFindings.duplicate()


# Replace the list with live findings WITHOUT switching tabs or changing project mode.
# 用实时发现替换列表，但不切页、不改全工程模式。
func gpShowFindings(gpFindings: Array[GPFinding]) -> void:
	_gpFindings = gpFindings.duplicate()
	_gpSummary.text = GPDRCReport.gpSummary(_gpFindings)
	var gpHas: bool = not _gpFindings.is_empty()
	_gpTxtBtn.disabled = not gpHas
	_gpCsvBtn.disabled = not gpHas
	if _gpJsonBtn != null:
		_gpJsonBtn.disabled = not gpHas
	_gpRebuildRows()
	gpFindingsChanged.emit(_gpFindings)


# Whether the panel is in whole-project mode (live scheduling is sheet-only).
# 面板是否处于全工程模式（实时调度只跑单页）。
func gpIsProjectMode() -> bool:
	return _gpProjectMode != null and _gpProjectMode.button_pressed


func _gpOnSevFilter(gpIdx: int) -> void:
	_gpFilterSev = gpIdx
	_gpRebuildRows()


# Filter check: 0 = all, 1 = error, 2 = warning, 3 = info.
# 过滤判定：0=全部，1=error，2=warning，3=info。
func _gpPassesFilter(gpF: GPFinding) -> bool:
	match _gpFilterSev:
		1:
			return gpF.gpSeverity == GPFinding.GP_ERROR
		2:
			return gpF.gpSeverity == GPFinding.GP_WARNING
		3:
			return gpF.gpSeverity == GPFinding.GP_INFO
		_:
			return true


# Family of a finding, for the grouped list / headers.
# 发现所属规则族，用于分组列表 / 标题。
static func _gpFamilyOf(gpF: GPFinding) -> String:
	var gpId: String = gpF.gpCheckId if gpF.gpCheckId != "" else gpF.gpRuleId
	var gpRule: GPDrcRule = GPDrcRegistry.gpById(gpId)
	if gpRule == null:
		gpRule = GPDrcRegistry.gpById(gpF.gpRuleId)
	if gpRule != null:
		return gpRule.gpFamily
	match gpF.gpRuleId:
		"drc.layout", "drc.sheet_fit":
			return "layout"
		"drc.tag":
			return "tag"
		"drc.required_props":
			return "symbol"
		"drc.edge_attrs", "drc.dangling_end", "drc.port_unconnected":
			return "topo"
	return "topo"


func _gpRebuildRows() -> void:
	for gpC in _gpList.get_children():
		_gpList.remove_child(gpC)
		gpC.queue_free()
	var gpShown: Array[GPFinding] = []
	for gpF in _gpFindings:
		if gpF != null and _gpPassesFilter(gpF):
			gpShown.append(gpF)
	if gpShown.is_empty():
		var gpEmpty: Label = Label.new()
		gpEmpty.text = I18n.gpTr("drc.all_clear") if _gpFindings.is_empty() \
			else I18n.gpTr("drc.filter_empty")
		gpEmpty.modulate = Color(0.55, 0.8, 0.6)
		_gpList.add_child(gpEmpty)
		return
	# Group by family in a fixed order; within a family keep the engine's deterministic order.
	# 按固定族序分组；族内保留引擎的确定性顺序。
	var gpFamilies: Array[String] = ["layout", "topo", "symbol", "tag", "doc", "sem", "offpage"]
	for gpFamily in gpFamilies:
		var gpRows: Array[GPFinding] = []
		for gpF in gpShown:
			if _gpFamilyOf(gpF) == gpFamily:
				gpRows.append(gpF)
		if gpRows.is_empty():
			continue
		var gpHeader: Label = Label.new()
		gpHeader.text = "%s · %d" % [I18n.gpTr("drc.family." + gpFamily), gpRows.size()]
		gpHeader.add_theme_font_size_override("font_size", 12)
		gpHeader.modulate = Color(0.62, 0.7, 0.85)
		_gpList.add_child(gpHeader)
		for gpF in gpRows:
			var gpBtn: Button = Button.new()
			gpBtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var gpPrefix: String = I18n.gpTr("drc.waived") + "  " if gpF.gpWaived else ""
			gpBtn.text = "%s  %s%s" % [_gpSeverityMark(gpF.gpSeverity), gpPrefix, gpF.gpText()]
			gpBtn.tooltip_text = "%s\n%s" % [gpF.gpCheckId if gpF.gpCheckId != "" else gpF.gpRuleId,
				_gpWhere(gpF)]
			gpBtn.add_theme_color_override("font_color", _gpSeverityColor(gpF.gpSeverity))
			gpBtn.pressed.connect(func() -> void:
				_gpLastFinding = gpF
				if _gpWaiveBtn != null:
					_gpWaiveBtn.disabled = gpF.gpEntityUid == ""
				if _gpRevokeBtn != null:
					_gpRevokeBtn.disabled = not gpF.gpWaived
				gpFindingActivated.emit(gpF.gpWorld)
				gpFindingActivatedFull.emit(gpF))
			_gpList.add_child(gpBtn)


# Short severity marker (text, not an icon: it survives a missing icon theme).
# 简短严重度标记（文字而非图标：图标主题缺失时仍然可用）。
static func _gpSeverityMark(gpSev: String) -> String:
	match gpSev:
		GPFinding.GP_ERROR:
			return "●"
		GPFinding.GP_WARNING:
			return "▲"
		_:
			return "·"


# Row colour by severity.
# 按严重度的行色。
static func _gpSeverityColor(gpSev: String) -> Color:
	match gpSev:
		GPFinding.GP_ERROR:
			return Color(0.95, 0.45, 0.45)
		GPFinding.GP_WARNING:
			return Color(0.95, 0.78, 0.35)
		_:
			return Color(0.62, 0.7, 0.85)


# Who/where, for the tooltip.
# 供提示显示「谁 / 在哪」。
static func _gpWhere(gpF: GPFinding) -> String:
	if gpF.gpNodeId != "":
		return "node " + gpF.gpNodeId
	if gpF.gpEdgeId != "":
		return "edge " + gpF.gpEdgeId
	if gpF.gpShapeIdx >= 0:
		return "shape #" + str(gpF.gpShapeIdx)
	return ""


# Write the last run to disk and tell the user where it went (the shell shows the status line).
# 把最近一次运行写盘并告知位置（由外壳显示状态栏）。
func _gpExport(gpAsCsv: bool) -> void:
	if _gpFindings.is_empty():
		return
	var gpDir: String = "user://drc_reports"
	var gpBase: String = "drc-%s" % Time.get_datetime_string_from_system().replace(":", "-")
	var gpPath: String = GPDRCReportFile.gpWrite(_gpFindings, gpDir, gpBase, gpAsCsv)
	if gpPath == "":
		return
	gpFindingActivated.emit(Vector2.INF)
	# The path is surfaced through the shell's status line; emitting it here would need a second
	# signal, so the panel keeps it simple and lets the export path speak for itself via the
	# tooltip of the buttons.
	# 路径经外壳状态栏呈现；在此再发一个信号只会让面板变复杂，故让导出路径通过按钮提示自证。
	_gpSummary.text = "%s\n%s" % [GPDRCReport.gpSummary(_gpFindings), gpPath]


# Request a waiver for the last clicked finding. The model is shared with the dialog; the panel
# never switches tabs on its own, so this stays a pure data action.
# 为最近点击的发现申请例外。模型与弹窗共用；面板从不自行切页，故这只是一个数据动作。
func _gpOnWaiverPressed() -> void:
	if _gpLastFinding == null:
		return
	var gpStd: GPProjectStandard = null
	if _gpCanvas != null and _gpCanvas.gpGraph != null:
		gpStd = _gpCanvas.gpGraph.gpStandard
	if gpStd == null or _gpLastFinding.gpEntityUid == "":
		_gpSummary.text = I18n.gpTr("drc.waive_no_std")
		return
	if _gpWaiverDialog == null:
		_gpWaiverDialog = GPWaiverDialog.new()
		add_child(_gpWaiverDialog)
		_gpWaiverDialog.gpWaiverAccepted.connect(func(gpReason: String, gpApprover: String) -> void:
			if GPDRCConfig.gpAddWaiver(gpStd, _gpLastFinding, gpReason, gpApprover):
				_gpSummary.text = I18n.gpTr("drc.waive_saved")
				gpRun())
	var gpRule: String = _gpLastFinding.gpCheckId if _gpLastFinding.gpCheckId != "" \
		else _gpLastFinding.gpRuleId
	_gpWaiverDialog.gpShowFor(gpRule, _gpLastFinding.gpEntityUid)


func _gpOnRevokePressed() -> void:
	if _gpLastFinding == null or not _gpLastFinding.gpWaived:
		return
	var gpStd: GPProjectStandard = null
	if _gpCanvas != null and _gpCanvas.gpGraph != null:
		gpStd = _gpCanvas.gpGraph.gpStandard
	if gpStd == null:
		return
	if GPDRCConfig.gpRemoveWaiver(gpStd, _gpLastFinding):
		_gpSummary.text = I18n.gpTr("drc.waive_removed")
		gpRun()


# Write the JSON report (the machine-readable source; text / CSV are renderings of it).
# 写出 JSON 报告（机器可读的源；文本 / CSV 是它的渲染）。
func _gpExportJson() -> void:
	if _gpFindings.is_empty():
		return
	var gpDir: String = "user://drc_reports"
	var gpBase: String = "drc-%s" % Time.get_datetime_string_from_system().replace(":", "-")
	var gpStd: GPProjectStandard = null
	if _gpCanvas != null and _gpCanvas.gpGraph != null:
		gpStd = _gpCanvas.gpGraph.gpStandard
	var gpMeta: Dictionary = {
		"mode": "project" if gpIsProjectMode() else "sheet",
		"doc_hash": GPExportGate.gpDocHash([_gpCanvas.gpSheet] if _gpCanvas != null else []),
		"rules_hash": GPExportGate.gpRulesHash(gpStd),
	}
	var gpPath: String = GPDRCReportFile.gpWriteJson(_gpFindings, gpDir, gpBase, gpMeta)
	if gpPath != "":
		_gpSummary.text = "%s\n%s" % [GPDRCReport.gpSummary(_gpFindings), gpPath]
