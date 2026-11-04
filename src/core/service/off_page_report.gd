class_name GPOffPageReport
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# U5 / K03: the cross-sheet connection REPORT — one row per link, the table that turns the
# cross-drawing relations from invisible data into a visible checklist. Composed ENTIRELY of
# existing pure outputs: GPOffPageAudit.gpRun supplies the states (dangling ends, orphan
# refs, contract drift, ghost membership) and GPOffPageResolver.gpResolve supplies the
# derived peer numbers / target tags. No UI here — the DRC panel already lists the findings
# with jump anchors, filters, export and waivers; this model is the W22-facing data
# foundation (DEXPI field table consumes the same rows).
# U5 / K03：跨图纸连接**报表** —— 每 link 一行，把跨图关系从看不见的数据变成看得见的清单。
# 完全由既有纯输出**组合**而成：GPOffPageAudit.gpRun 供状态（悬空端、孤儿引用、契约漂移、
# 幽灵成员），GPOffPageResolver.gpResolve 供派生的对端图号 / 目标位号。此处无 UI ——
# DRC 面板已带跳转锚点、过滤、导出与豁免地列出这些发现；本模型是面向 W22 的数据基础
#（DEXPI 字段表消费同一批行）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


# The report. Returns {"rows": Array[Dictionary], "ghosts": Array[Dictionary]}.
# Row shape / 行形状:
#   {link_id, tag, state, drift, a_number, b_number, peer_number, target_tag, medium, dn}
#   state ∈ "paired" / "dangling_a" / "dangling_b" / "dangling_ab" / "broken"
#   drift = a contract field disagrees between the snapshot and the ends' edges.
# Ghost row shape / 幽灵行形状: {link_id, node_id, sheet_id} — a connector claiming a link
# that does not list it (the D10 membership rule).
# 报表。返回 {"rows": ..., "ghosts": ...}。state：paired（已配对）/ dangling_a / dangling_b /
# dangling_ab（端点悬空）/ broken（引用缺失）。drift：快照与两端边存在契约字段不一致。
static func gpRows(gpSheets: Array, gpLinks: Array[GPOffPageLink],
		gpDefs: Array[GPSymbolDef]) -> Dictionary:
	var gpFindings: Array[GPFinding] = GPOffPageAudit.gpRun(gpSheets, gpLinks, gpDefs)
	# Fold the findings into per-link state + the ghost list. Params of dangling_end:
	# [link label, "A"|"B", node id]; membership: [claim, node id].
	# 把发现折叠为每-link 状态 + 幽灵清单。dangling_end 参数：[link 名, "A"|"B", 节点 id]；
	# membership 参数：[声称 id, 节点 id]。
	var gpDangle: Dictionary = {}
	var gpDrift: Dictionary = {}
	var gpBroken: Dictionary = {}
	var gpGhosts: Array[Dictionary] = []
	for gpF in gpFindings:
		if gpF.gpCheckId == "drc.offpage.dangling_end":
			var gpEnd: String = str(gpF.gpParams[1]) if gpF.gpParams.size() > 1 else ""
			var gpPrev: String = str(gpDangle.get(gpF.gpEntityUid, ""))
			gpDangle[gpF.gpEntityUid] = gpEnd if gpPrev == "" \
				else (gpPrev if gpPrev == gpEnd else "AB")
		elif gpF.gpCheckId == "drc.offpage.attr_mismatch":
			gpDrift[gpF.gpEntityUid] = true
		elif gpF.gpRuleId == "drc.offpage.orphan_link":
			gpBroken[gpF.gpEntityUid] = true
		elif gpF.gpMessageKey == "drc.offpage.membership":
			gpGhosts.append({
				"link_id": str(gpF.gpParams[0]) if gpF.gpParams.size() > 0 else "",
				"node_id": str(gpF.gpParams[1]) if gpF.gpParams.size() > 1 else "",
				"sheet_id": gpF.gpSheetId,
			})
	# The resolver's explicit context: numbers + graphs by sheet id.
	# resolver 的显式上下文：按 sheet_id 的图号表与图表。
	var gpNumbers: Dictionary = {}
	var gpGraphs: Dictionary = {}
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet != null and gpSheet.gpId != "":
			gpNumbers[gpSheet.gpId] = gpSheet.gpNumber
			gpGraphs[gpSheet.gpId] = gpSheet.gpGraph
	var gpRows: Array[Dictionary] = []
	for gpL in gpLinks:
		if gpL == null:
			continue
		var gpUid: String = GPOffPageAudit.GP_LINK_UID_PREFIX + gpL.gpInstanceId
		var gpRes: Dictionary = GPOffPageResolver.gpResolve(gpL, gpNumbers, gpGraphs)
		var gpState: String = "paired"
		if gpBroken.has(gpUid):
			gpState = "broken"
		else:
			var gpD: String = str(gpDangle.get(gpUid, ""))
			if gpD == "AB":
				gpState = "dangling_ab"
			elif gpD == "A":
				gpState = "dangling_a"
			elif gpD == "B":
				gpState = "dangling_b"
		gpRows.append({
			"link_id": gpL.gpInstanceId,
			"tag": gpL.gpTag,
			"state": gpState,
			"drift": gpDrift.has(gpUid),
			"a_number": str(gpNumbers.get(str(gpL.gpA.get(
				GPOffPageLink.GP_KEY_SHEET, "")), "")),
			"b_number": str(gpNumbers.get(str(gpL.gpB.get(
				GPOffPageLink.GP_KEY_SHEET, "")), "")),
			"peer_number": str(gpRes.get("peer_number", "")),
			"target_tag": str(gpRes.get("target_tag", "")),
			"medium": str(gpRes.get("medium", "")),
			"dn": str(gpL.gpAttrs.get("dn", "")),
		})
	return {"rows": gpRows, "ghosts": gpGhosts}
