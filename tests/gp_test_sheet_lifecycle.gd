extends "res://tests/gp_test.gd"
# Headless tests for the REAL sheet deletion (W13 T4): the pure deletion plan, the
# cross-sheet link cascade math, the refusal rules, and the "no residue in the container"
# roundtrip through the normal write/read path.
# 图纸**真删除**的 headless 测试（W13 T4）：纯删除计划、跨图纸 link 级联数学、拒绝规则，
# 以及经正常写/读路径的「容器无残留」往返钉。
# WHY / 为何要这些测试：
# Deletion is the most destructive operation in the product and the cascade is its dangerous
# half — a missed link would leave the archive pointing at a sheet that no longer exists
# (pickers/off-page flags would rot). The plan is pure, so the gate can pin every rule.
# 删除是产品里**最具破坏性**的操作，级联是它危险的那一半 —— 漏掉一条 link，存档里就会
# 留下指向已不存在图纸的死引用（选择器 / 跨图纸旗标随之腐烂）。计划是纯函数，门禁可以
# 钉死每一条规则。

# Helper: a minimal sheet with a stable id.
# 辅助：带稳定 id 的最小图纸。
func _gpSheet(gpId: String, gpName: String) -> GPSheet:
	return GPSheet.gpNew(gpId, gpName, 0)


# Helper: a link with both endpoints on given sheet ids.
# 辅助：两端落在指定图纸 id 的 link。
func _gpLink(gpId: String, gpSheetA: String, gpSheetB: String) -> GPOffPageLink:
	var gpOut: GPOffPageLink = GPOffPageLink.new()
	gpOut.gpInstanceId = gpId
	gpOut.gpA = {GPOffPageLink.GP_KEY_SHEET: gpSheetA}
	gpOut.gpB = {GPOffPageLink.GP_KEY_SHEET: gpSheetB}
	return gpOut


# ==================== gpLinkTouchesSheet / 触碰判定 ====================

# Null-safe and empty-id-safe: a junk link and an idless deletion never match.
# null 安全与空 id 安全：垃圾 link 与无 id 的删除永不命中。
func gpTestLinkTouchRefusesNullAndEmpty() -> void:
	gpCheck(GPSheetLifecycle.gpLinkTouchesSheet(null, "s1") == false,
		"a null link must never touch")
	gpCheck(GPSheetLifecycle.gpLinkTouchesSheet(_gpLink("x", "s1", "s2"), "") == false,
		"an empty target id must never match")
	gpCheck(GPSheetLifecycle.gpLinkTouchesSheet(_gpLink("x", "", "s2"), "s1") == false,
		"a link without sheet refs must not touch")


# Either end counts. / 任一端命中即算。
func gpTestLinkTouchMatchesEitherEnd() -> void:
	gpCheck(GPSheetLifecycle.gpLinkTouchesSheet(_gpLink("x", "s1", "s2"), "s1"),
		"endpoint A must match")
	gpCheck(GPSheetLifecycle.gpLinkTouchesSheet(_gpLink("x", "s2", "s1"), "s1"),
		"endpoint B must match")
	gpCheck(GPSheetLifecycle.gpLinkTouchesSheet(_gpLink("x", "s3", "s4"), "s1") == false,
		"an untouched link must not match")


# ==================== plan: happy path / 计划：正常路径 ====================

# Delete the middle sheet: survivors keep order and identity, the title is reported.
# 删除中间那张：幸存者保序保身，标题如实上报。
func gpTestPlanDeletesAndKeepsOrder() -> void:
	var gpSheets: Array[GPSheet] = [_gpSheet("s1", "A"), _gpSheet("s2", "B"), _gpSheet("s3", "C")]
	var gpPlan: Dictionary = GPSheetLifecycle.gpPlanDelete(gpSheets, [], "s2")
	gpCheck(bool(gpPlan.get("ok", false)), "deleting a middle sheet must be allowed")
	gpEq(str(gpPlan.get("title", "")), "B", "the plan must report the deleted title")
	var gpSurvivors: Array = gpPlan.get("survivors", []) as Array
	gpEq(gpSurvivors.size(), 2, "exactly two survivors must remain")
	if gpSurvivors.size() == 2:
		gpEq((gpSurvivors[0] as GPSheet).gpId, "s1", "the first survivor must keep its order")
		gpEq((gpSurvivors[1] as GPSheet).gpId, "s3", "the last survivor must keep its order")
	gpEq(gpSheets.size(), 3, "planning must not mutate the caller's sheet array")


# The cascade: links touching the deleted sheet are collected, untouched ones stay out.
# 级联：触碰被删图纸的 link 被收集，未触碰的不进来。
func gpTestPlanCollectsAffectedLinks() -> void:
	var gpSheets: Array[GPSheet] = [_gpSheet("s1", "A"), _gpSheet("s2", "B"), _gpSheet("s3", "C")]
	var gpLinks: Array[GPOffPageLink] = [
		_gpLink("x1", "s1", "s2"),   # touches s2 / 触碰 s2
		_gpLink("x2", "s3", "s1"),   # untouched / 未触碰
		_gpLink("x3", "s2", "s3"),   # touches s2 / 触碰 s2
	]
	var gpPlan: Dictionary = GPSheetLifecycle.gpPlanDelete(gpSheets, gpLinks, "s2")
	var gpAffected: Array = gpPlan.get("affected", []) as Array
	gpEq(gpAffected.size(), 2, "exactly the two s2-touching links must be affected")
	if gpAffected.size() == 2:
		gpEq((gpAffected[0] as GPOffPageLink).gpInstanceId, "x1",
			"affected must preserve the input order (x1)")
		gpEq((gpAffected[1] as GPOffPageLink).gpInstanceId, "x3",
			"affected must preserve the input order (x3)")
	gpEq(gpLinks.size(), 3, "planning must not mutate the caller's link array")


# ==================== plan: refusals / 计划：拒绝规则 ====================

# Missing id and last-sheet refusals, both honest reasons.
# 缺 id 与「最后一张」两种拒绝，理由如实。
func gpTestPlanRefusals() -> void:
	var gpOne: Dictionary = GPSheetLifecycle.gpPlanDelete([_gpSheet("s1", "A")], [], "nope")
	gpCheck(bool(gpOne.get("ok", true)) == false and str(gpOne.get("reason")) == "missing",
		"an unknown id must refuse with missing")
	gpEq(GPSheetLifecycle.gpPlanDelete([], [], "s1").get("reason", ""), "missing",
		"an empty id must refuse with missing")
	var gpLast: Dictionary = GPSheetLifecycle.gpPlanDelete([_gpSheet("s1", "A")], [], "s1")
	gpCheck(bool(gpLast.get("ok", true)) == false and str(gpLast.get("reason")) == "last",
		"deleting the last sheet must refuse with last")


# Null sheets in the caller's array are skipped, never crash the plan.
# 调用方数组里的 null 图纸被跳过，绝不炸掉计划。
func gpTestPlanSkipsNullSheets() -> void:
	var gpSheets: Array[GPSheet] = [null, _gpSheet("s1", "A"), null, _gpSheet("s2", "B")]
	var gpPlan: Dictionary = GPSheetLifecycle.gpPlanDelete(gpSheets, [], "s2")
	gpCheck(bool(gpPlan.get("ok", false)), "planning must survive null entries")
	gpEq((gpPlan.get("survivors", []) as Array).size(), 1,
		"only the real survivor must remain")


# ==================== container roundtrip / 容器往返 ====================

# The gate criterion "no residue in the container", proven through the NORMAL io path:
# apply the cascade by hand (drop affected), write survivors + remaining links, read back —
# the deleted sheet id appears NOWHERE (sheets or links).
# 验收判据「容器无残留」，经**正常** io 路径证明：手工执行级联（去掉 affected）、写出
# 幸存者与剩余 link、读回 —— 被删的图纸 id **处处**不再出现（图纸与 link 均无）。
func gpTestDeletedSheetLeavesNoContainerResidue() -> void:
	var gpSheets: Array[GPSheet] = [_gpSheet("s1", "A"), _gpSheet("s2", "B"), _gpSheet("s3", "C")]
	var gpLinks: Array[GPOffPageLink] = [
		_gpLink("x1", "s1", "s2"), _gpLink("x2", "s3", "s1"), _gpLink("x3", "s2", "s3"),
	]
	var gpPlan: Dictionary = GPSheetLifecycle.gpPlanDelete(gpSheets, gpLinks, "s2")
	gpCheck(bool(gpPlan.get("ok", false)), "the fixture plan must be allowed")
	# Simulate gpApplyPlan's cascade: remove the affected from the live table.
	# 模拟 gpApplyPlan 的级联：从活表移除 affected。
	var gpRemaining: Array[GPOffPageLink] = []
	var gpAffected: Array = gpPlan.get("affected", []) as Array
	for gpL in gpLinks:
		if not gpAffected.has(gpL):
			gpRemaining.append(gpL)
	gpEq(gpRemaining.size(), 1, "exactly the untouched link must survive the cascade")
	# Write + read back through the NORMAL path (the one save uses).
	# 经**正常**写读路径（与保存同一条）往返。
	var gpPath: String = "user://gp_test_sheet_lifecycle.pid.json"
	var gpWrite: GPIOResult = GPProjectIO.gpWriteSheetsResult(gpPlan.get("survivors", []) as Array,
		gpPath, gpRemaining)
	gpCheck(gpWrite.gpIsOk(), "writing survivors must succeed")
	var gpRead: GPIOResult = GPProjectIO.gpReadSheetsWithLinks(gpPath)
	gpCheck(gpRead.gpIsOk(), "the archive must read back")
	if gpRead.gpIsOk():
		var gpPayload: Dictionary = gpRead.gpPayload as Dictionary
		var gpBackSheets: Array = gpPayload.get("sheets", []) as Array
		gpEq(gpBackSheets.size(), 2, "the archive must carry exactly the two survivors")
		for gpS in gpBackSheets:
			gpCheck(str((gpS as GPSheet).gpId) != "s2",
				"the deleted sheet id must not survive in sheets")
		var gpBackLinks: Array = gpPayload.get("links", []) as Array
		gpEq(gpBackLinks.size(), 1, "the archive must carry exactly the untouched link")
		for gpL in gpBackLinks:
			var gpRec: GPOffPageLink = gpL as GPOffPageLink
			if gpRec != null:
				gpCheck(GPSheetLifecycle.gpLinkTouchesSheet(gpRec, "s2") == false,
					"no surviving link may reference the deleted sheet")
	# Cleanup. / 清理。
	DirAccess.remove_absolute(gpPath)
