extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# B2: DRC report rendering (text / CSV) and the panel's own behaviour.
# B2：DRC 报告渲染（文本 / CSV）与面板自身行为。
#
# The acceptance is "the file says what the panel says", so the string builders are tested pure:
# no disk, no dialog, no scene tree. The one disk test writes into user:// and reads the text
# back — that is the only way to prove the path and the content agree.
# 验收标准是「文件说的与面板说的一致」，故字符串构建器**纯测**：不碰磁盘、不碰对话框、不碰场景树。
# 唯一落盘的测试写进 user:// 再读回文字 —— 那是证明路径与内容一致的唯一方法。

func _gpFindings() -> Array[GPFinding]:
	var gpF: Array[GPFinding] = []
	gpF.append(GPFinding.gpMake("drc.tag_missing", GPFinding.GP_ERROR, "drc.tag_missing",
		["n1"]).gpOnNode("n1", Vector2(10.0, 20.0)))
	gpF.append(GPFinding.gpMake("drc.symbols_overlap", GPFinding.GP_WARNING,
		"drc.symbols_overlap", ["n1", "n2"]).gpOnNode("n1", Vector2(11.0, 21.0)))
	gpF.append(GPFinding.gpMake("drc.sheet_sparse", GPFinding.GP_INFO, "drc.sheet_sparse", [3]))
	return gpF


func gpTestSummaryCountsBySeverity() -> void:
	var gpText: String = GPDRCReport.gpSummary(_gpFindings())
	gpCheck(gpText.contains("1"), "摘要含计数 / the summary carries counts")
	gpCheck(gpText.contains("错误") or gpText.contains("error"), "含错误字样 / it names errors")


func gpTestTextReportGroupsSeveritiesAndKeepsBlockersFirst() -> void:
	var gpText: String = GPDRCReport.gpToText(_gpFindings())
	var gpErr: int = gpText.find("[error]")
	var gpWarn: int = gpText.find("[warning]")
	var gpInfo: int = gpText.find("[info]")
	gpCheck(gpErr >= 0, "有 error 分组 / an error group exists")
	gpCheck(gpWarn > gpErr, "warning 在 error 之后 / warnings follow errors")
	gpCheck(gpInfo > gpWarn, "info 在 warning 之后 / infos follow warnings")
	gpCheck(gpText.contains("drc.tag_missing"), "行里带规则号 / rows carry the rule id")


func gpTestCsvReportHasStableHeaderAndOneRowPerFinding() -> void:
	var gpCsv: String = GPDRCReport.gpToCsv(_gpFindings())
	var gpLines: PackedStringArray = gpCsv.split("\n", false)
	gpEq(gpLines[0], GPDRCReport.GP_CSV_HEADER, "表头稳定 / the header is stable")
	gpEq(gpLines.size(), 4, "表头 + 三条发现 / header plus three findings")


func gpTestCsvQuotesCommas() -> void:
	var gpF: Array[GPFinding] = [GPFinding.gpMake("drc.edge_attrs_missing", GPFinding.GP_WARNING,
		"drc.edge_attrs_missing", ["e1", "dn, medium"])]
	var gpCsv: String = GPDRCReport.gpToCsv(gpF)
	gpCheck(gpCsv.contains("\"") , "含逗号的字段被加引号 / a field with a comma is quoted")


func gpTestReportWritesAndReadsBack() -> void:
	var gpDir: String = "user://drc_test_reports"
	var gpPath: String = GPDRCReport.gpWrite(_gpFindings(), gpDir, "unit", false)
	gpCheck(gpPath != "", "写出成功 / the write succeeds")
	gpCheck(FileAccess.file_exists(gpPath), "文件存在 / the file exists")
	gpCheck(FileAccess.get_file_as_string(gpPath).contains("drc.tag_missing"),
		"内容与渲染一致 / the file matches the rendered text")


func gpTestEmptyReportStillRendersHeader() -> void:
	var gpNone: Array[GPFinding] = []
	var gpText: String = GPDRCReport.gpToText(gpNone)
	gpCheck(gpText.contains("0"), "空报告也带计数 / an empty report still counts")
	var gpCsv: String = GPDRCReport.gpToCsv(gpNone)
	gpEq(gpCsv.strip_edges(), GPDRCReport.GP_CSV_HEADER, "空 CSV 只有表头 / an empty CSV is header-only")


func gpTestPanelRunsAndFillsRows() -> void:
	# Drive the real panel against a real canvas in-tree: the panel is the user's surface, so its
	# wiring must be exercised, not just the pure rules underneath it.
	# 用树内真画布驱动真面板：面板才是用户的界面，故要测它的接线，而不只是下面的纯规则。
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	add_child(gpCv)
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "SYM", "", Vector2(50.0, 50.0)))
	gpCv.gpGraph = gpG
	var gpPanel: GPDRCPanel = GPDRCPanel.new()
	add_child(gpPanel)
	gpPanel.gpBuild()
	gpPanel.gpBindCanvas(gpCv)
	gpPanel.gpRun()
	gpCheck(gpPanel.gpFindings().size() > 0, "运行后有发现 / a run produces findings")
	gpCheck(gpPanel.gpFindings()[0] is GPFinding, "发现是 GPFinding / findings are typed")
	gpPanel.queue_free()
	gpCv.queue_free()
