extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# DRC UI wiring: toolbar entry + result dialog rows emit the full finding.
# DRC UI 接线：工具栏入口 + 结果弹窗行发出完整发现。

func _gpCanvasWithFinding() -> GPCanvas2D:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpWidthMM = 420.0
	gpSheet.gpHeightMM = 297.0
	gpSheet.gpNumber = "PID-001"
	gpSheet.gpName = "PID-001"
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "MISSING_SYMBOL", "", Vector2(100.0, 100.0)))
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	add_child(gpCv)
	gpCv.gpGraph = gpG
	gpCv.gpDefs = []
	gpCv.gpSetSheet(gpSheet)
	return gpCv


func gpTestToolbarHasDrcTextEntry() -> void:
	var gpBar: GPPIDQuickToolbar = GPPIDQuickToolbar.new()
	add_child(gpBar)
	gpBar._ready()
	gpCheck(gpBar._gpBtns.has("tool_drc_dialog"), "toolbar has DRC action / 工具栏有 DRC 动作")
	if gpBar._gpBtns.has("tool_drc_dialog"):
		var gpBtn: Button = gpBar._gpBtns["tool_drc_dialog"] as Button
		gpEq(gpBtn.text, "DRC校验", "toolbar shows DRC校验 / 工具栏显示 DRC校验")
	var gpGot: Array[String] = []
	gpBar.gpActionTriggered.connect(func(gpId: String) -> void: gpGot.append(gpId))
	gpBar._gpOnPressed("tool_drc_dialog")
	gpCheck(gpGot.has("tool_drc_dialog"), "toolbar forwards the action / 工具栏转发动作")
	gpBar.queue_free()


func gpTestDialogRunsAndEmitsFinding() -> void:
	var gpCv: GPCanvas2D = _gpCanvasWithFinding()
	var gpDlg: GPDRCDialog = GPDRCDialog.new()
	add_child(gpDlg)
	gpDlg._ready()
	gpDlg._gpCanvas = gpCv
	gpDlg.gpRun()
	gpCheck(gpDlg._gpList.item_count > 0, "dialog lists findings / 弹窗列出发现")
	var gpGot: Array[GPFinding] = []
	gpDlg.gpFindingActivated.connect(func(gpF: GPFinding) -> void: gpGot.append(gpF))
	gpDlg._gpOnRowSelected(0)
	gpCheck(gpGot.size() == 1, "row emits the finding / 行发出发现")
	if gpGot.size() == 1:
		gpCheck(gpGot[0].gpRuleId != "", "finding has a rule id / 发现带规则号")
	gpDlg.queue_free()
	gpCv.queue_free()



func gpTestWaiverDialogRequiresReasonAndApprover() -> void:
	gpCheck(not GPWaiverDialog.gpIsValid("", "张三"), "empty reason invalid / 空理由无效")
	gpCheck(not GPWaiverDialog.gpIsValid("理由", ""), "empty approver invalid / 空批准人无效")
	gpCheck(GPWaiverDialog.gpIsValid("理由", "张三"), "both filled valid / 两者齐全有效")


func gpTestDialogAppliesWaiverToProjectStandard() -> void:
	var gpCv: GPCanvas2D = _gpCanvasWithFinding()
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	gpCfg["rules"]["drc.doc.title_block_required"] = {"enabled": false}
	gpCfg["rules"]["drc.doc.title_block_drawing_no"] = {"enabled": false}
	gpCfg["rules"]["drc.doc.sheet_number"] = {"enabled": false}
	gpStd.gpValidation = gpCfg
	gpCv.gpGraph.gpAdoptStandard(gpStd)
	var gpDlg: GPDRCDialog = GPDRCDialog.new()
	add_child(gpDlg)
	gpDlg._ready()
	gpDlg._gpCanvas = gpCv
	gpDlg.gpRun()
	var gpTarget: GPFinding = null
	for gpF in gpDlg._gpFindings:
		if gpF.gpCheckId == "drc.symbol.unknown":
			gpTarget = gpF
			break
	gpCheck(gpTarget != null, "symbol-unknown finding exists / 存在未知图元发现")
	if gpTarget != null:
		gpCheck(gpDlg._gpApplyWaiver(gpTarget, "历史图元", "张三"),
			"waiver is written / 豁免写入")
		var gpWaivers: Array = gpStd.gpValidationConfig().get("waivers", []) as Array
		gpEq(gpWaivers.size(), 1, "one waiver stored / 存了一条豁免")
		gpCheck(GPDRCConfig.gpRemoveWaiver(gpStd, gpTarget), "waiver can be removed / 豁免可撤销")
		gpEq((gpStd.gpValidationConfig().get("waivers", []) as Array).size(), 0,
			"waiver list is empty after removal / 撤销后列表为空")
	gpDlg.queue_free()
	gpCv.queue_free()


func gpTestSchedulerRunsAndPublishesFindings() -> void:
	var gpCv: GPCanvas2D = _gpCanvasWithFinding()
	var gpSched: GPRuleScheduler = GPRuleScheduler.new()
	add_child(gpSched)
	gpSched.gpBind(gpCv.gpGraph, gpCv.gpSheet, [])
	var gpGot: Array = []
	gpSched.gpFindingsReady.connect(func(gpF: Array[GPFinding], _g: GPPIDGraph) -> void:
		gpGot.append(gpF))
	gpSched.gpRunNow()
	gpEq(gpGot.size(), 1, "scheduler publishes once / 调度器发布一次")
	gpCheck(gpSched.gpLastFindings.size() > 0, "scheduler has findings / 调度器有发现")
	gpSched.queue_free()
	gpCv.queue_free()


func gpTestOverlayAcceptsFindings() -> void:
	var gpCv: GPCanvas2D = _gpCanvasWithFinding()
	var gpOverlay: GPRuleOverlay = GPRuleOverlay.new()
	add_child(gpOverlay)
	gpOverlay.gpAttach(gpCv)
	gpOverlay.gpShow([GPFinding.gpMake("drc.layout", GPFinding.GP_WARNING,
		"drc.symbol_off_sheet", ["n1"]).gpOnNode("n1", Vector2(100.0, 100.0))], gpCv.gpSheet.gpId)
	gpEq(gpOverlay.gpFindings.size(), 1, "overlay holds findings / 覆盖层持有发现")
	gpCheck(gpOverlay.get_parent() == gpCv, "overlay attaches to canvas / 覆盖层挂到画布")
	gpOverlay.queue_free()
	gpCv.queue_free()


func gpTestPanelGroupsByFamilyAndFiltersSeverity() -> void:
	var gpPanel: GPDRCPanel = GPDRCPanel.new()
	add_child(gpPanel)
	gpPanel.gpBuild()
	var gpFindings: Array[GPFinding] = [
		GPFinding.gpMake("drc.topo", GPFinding.GP_ERROR, "drc.edge_ref_missing",
			["e1", "from"]).gpAs("drc.topo.edge_ref_missing", ""),
		GPFinding.gpMake("drc.layout", GPFinding.GP_WARNING, "drc.symbol_off_sheet",
			["n1"]).gpAs("drc.layout", ""),
		GPFinding.gpMake("drc.doc", GPFinding.GP_INFO, "drc.title_block_inherit",
			["project", "a", "b"]).gpAs("drc.doc.title_block_inherit", ""),
	]
	gpPanel.gpShowFindings(gpFindings)
	gpEq(gpPanel._gpList.get_child_count(), 6, "3 group headers + 3 rows / 3 个组标题 + 3 行")
	gpPanel._gpSevFilter.select(1)
	gpPanel._gpOnSevFilter(1)
	# Only the topo header + its one error row remain.
	gpEq(gpPanel._gpList.get_child_count(), 2, "error filter keeps one group + one row / 错误过滤只剩一组一行")
	gpPanel.queue_free()


func gpTestSchedulerRecordsBudgetMetric() -> void:
	var gpCv: GPCanvas2D = _gpCanvasWithFinding()
	var gpSched: GPRuleScheduler = GPRuleScheduler.new()
	add_child(gpSched)
	gpSched.gpBind(gpCv.gpGraph, gpCv.gpSheet, [])
	gpSched.gpRunNow()
	gpCheck(gpSched.gpLastRunUsec >= 0, "scheduler records run cost / 调度器记录耗时")
	gpCheck(gpSched.gpOverBudget == (gpSched.gpLastRunUsec > GPRuleScheduler.GP_BUDGET_USEC),
		"over-budget flag matches the metric / 超预算标志与指标一致")
	gpSched.queue_free()
	gpCv.queue_free()


func gpTestRepairPlanDialogListsActions() -> void:
	var gpF: Array[GPFinding] = [
		GPFinding.gpMake("drc.layout", GPFinding.GP_WARNING, "drc.symbol_off_sheet",
			["n1"]).gpAs("drc.layout", "drc.fix.move").gpOnEntity("u-1", "s1"),
	]
	var gpDlg: GPRepairPlanDialog = GPRepairPlanDialog.new()
	add_child(gpDlg)
	gpDlg._ready()
	gpDlg._gpPlan = GPDRCRepair.gpPlan(gpF)
	gpDlg._gpRebuild()
	gpEq(gpDlg._gpPlan.size(), 1, "plan has one action / 计划有一个动作")
	gpEq(gpDlg._gpList.item_count, 1, "dialog lists the action / 弹窗列出动作")
	gpDlg.queue_free()


func gpTestSchedulerTimeSlicesPublishAfterAllFamilies() -> void:
	var gpCv: GPCanvas2D = _gpCanvasWithFinding()
	var gpSched: GPRuleScheduler = GPRuleScheduler.new()
	add_child(gpSched)
	gpSched.gpBind(gpCv.gpGraph, gpCv.gpSheet, [])
	gpSched._gpRunning = true
	gpSched._gpSlice = 0
	gpSched._gpAccum.clear()
	for _i in range(GPRuleScheduler.GP_SLICES.size()):
		gpSched._gpRunSlice()
	gpCheck(not gpSched._gpRunning, "slices finish / 切片跑完")
	gpCheck(gpSched.gpLastFindings.size() > 0, "time-sliced run has findings / 时间切片有发现")
	gpSched.queue_free()
	gpCv.queue_free()


func gpTestFocusWorldAppliesCameraAndCentres() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	add_child(gpCv)
	gpCv.size = Vector2(800.0, 600.0)
	gpCv.gpFocusWorld(Vector2(100.0, 100.0))
	var gpScreen: Vector2 = gpCv.gpScreenFromWorld(Vector2(100.0, 100.0))
	gpCheck(gpScreen.distance_to(Vector2(400.0, 300.0)) < 0.5,
		"focus puts the world point at the viewport centre / 定位把世界点放到视口中心")
	if gpCv.gpWorldRoot != null:
		gpCheck(gpCv.gpWorldRoot.position.is_equal_approx(gpCv.gpViewOffset),
			"focus applies the camera to the world root / 定位把相机应用到世界根")
	gpCv.queue_free()


func gpTestFocusRectZoomsAndCentres() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	add_child(gpCv)
	gpCv.size = Vector2(800.0, 600.0)
	var gpRect: Rect2 = Rect2(100.0, 100.0, 40.0, 40.0)
	gpCv.gpFocusRect(gpRect, 2.5)
	gpCheck(gpCv.gpViewZoom > 1.0, "focus rect zooms in / 定位矩形会放大")
	var gpScreen: Vector2 = gpCv.gpScreenFromWorld(gpRect.get_center())
	gpCheck(gpScreen.distance_to(Vector2(400.0, 300.0)) < 0.5,
		"focus rect centres the entity / 定位矩形把实体放到中心")
	gpCv.queue_free()
