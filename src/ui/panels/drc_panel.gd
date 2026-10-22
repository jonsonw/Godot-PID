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

# The canvas whose graph is checked (null until bound).
# 被检查的画布（绑定前为 null）。
var _gpCanvas: GPCanvas2D = null

# Findings of the last run.
# 最近一次运行的发现。
var _gpFindings: Array[GPFinding] = []

var _gpSummary: Label = null
var _gpList: VBoxContainer = null
var _gpScroll: ScrollContainer = null
var _gpRunBtn: Button = null
var _gpTxtBtn: Button = null
var _gpCsvBtn: Button = null


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
	_gpTxtBtn = Button.new()
	_gpTxtBtn.text = I18n.gpTr("drc.export_txt")
	_gpTxtBtn.disabled = true
	_gpTxtBtn.pressed.connect(func() -> void: _gpExport(false))
	gpRow.add_child(_gpTxtBtn)
	_gpCsvBtn = Button.new()
	_gpCsvBtn.text = I18n.gpTr("drc.export_csv")
	_gpCsvBtn.disabled = true
	_gpCsvBtn.pressed.connect(func() -> void: _gpExport(true))
	gpRow.add_child(_gpCsvBtn)
	add_child(gpRow)
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


# Refresh static text after a locale change.
# 语言切换后刷新静态文字。
func gpRefreshText() -> void:
	if _gpRunBtn != null:
		_gpRunBtn.text = I18n.gpTr("drc.run")
		_gpTxtBtn.text = I18n.gpTr("drc.export_txt")
		_gpCsvBtn.text = I18n.gpTr("drc.export_csv")
	if _gpFindings.is_empty():
		_gpSummary.text = I18n.gpTr("drc.never_run")


# Run the seven rules on the bound canvas and rebuild the list.
# 在绑定画布上跑七条规则并重建列表。
func gpRun() -> void:
	if _gpCanvas == null or _gpCanvas.gpGraph == null:
		_gpFindings = []
		_gpSummary.text = I18n.gpTr("drc.no_canvas")
		_gpRebuildRows()
		return
	_gpFindings = GPRulePack.gpRun(_gpCanvas.gpGraph, _gpCanvas.gpSheet, _gpCanvas.gpDefs)
	_gpSummary.text = GPDRCReport.gpSummary(_gpFindings)
	_gpTxtBtn.disabled = _gpFindings.is_empty()
	_gpCsvBtn.disabled = _gpFindings.is_empty()
	_gpRebuildRows()


# The findings of the last run (the shell may also use them for its status line).
# 最近一次运行的发现（外壳也可用它更新状态栏）。
func gpFindings() -> Array[GPFinding]:
	return _gpFindings.duplicate()


func _gpRebuildRows() -> void:
	for gpC in _gpList.get_children():
		_gpList.remove_child(gpC)
		gpC.queue_free()
	if _gpFindings.is_empty():
		var gpEmpty: Label = Label.new()
		gpEmpty.text = I18n.gpTr("drc.all_clear")
		gpEmpty.modulate = Color(0.55, 0.8, 0.6)
		_gpList.add_child(gpEmpty)
		return
	for gpF in _gpFindings:
		var gpBtn: Button = Button.new()
		gpBtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		gpBtn.text = "%s  %s" % [_gpSeverityMark(gpF.gpSeverity), gpF.gpText()]
		gpBtn.tooltip_text = "%s\n%s" % [gpF.gpRuleId, _gpWhere(gpF)]
		gpBtn.add_theme_color_override("font_color", _gpSeverityColor(gpF.gpSeverity))
		# Jump on click: the finding carries the world position, so the shell never has to
		# re-derive where the problem is.
		# 点击跳转：发现自带世界坐标，故外壳无需重新推导问题在哪。
		gpBtn.pressed.connect(func() -> void: gpFindingActivated.emit(gpF.gpWorld))
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
	var gpPath: String = GPDRCReport.gpWrite(_gpFindings, gpDir, gpBase, gpAsCsv)
	if gpPath == "":
		return
	gpFindingActivated.emit(Vector2.INF)
	# The path is surfaced through the shell's status line; emitting it here would need a second
	# signal, so the panel keeps it simple and lets the export path speak for itself via the
	# tooltip of the buttons.
	# 路径经外壳状态栏呈现；在此再发一个信号只会让面板变复杂，故让导出路径通过按钮提示自证。
	_gpSummary.text = "%s\n%s" % [GPDRCReport.gpSummary(_gpFindings), gpPath]
