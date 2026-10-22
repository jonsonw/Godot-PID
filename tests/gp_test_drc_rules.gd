extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# B1: the seven DRC rules (GPRulePack) — positive and negative examples, determinism, and the
# conservative exclusions that keep the checker believable.
# B1：七条 DRC 规则（GPRulePack）—— 正反例、确定性，以及让检查器保持可信的「保守排除」。
#
# WHY THE EXCLUSIONS ARE THE POINT / 保守排除为何才是重点：
# A checker earns trust by being RIGHT, not by firing often. These tests therefore pin the
# deliberate silences as hard as the hits: a spare nozzle is not a defect, a mounted part has no
# tag by design, and a signal line has no pipe number.
# 检查器靠**说得对**赢得信任，而不是靠报得多。故本套件把刻意的沉默与命中一样钉死：
# 空置管口不是缺陷、挂载部件本就无位号、信号线本就没有管线号。

const GP_SHEET_W: float = 420.0
const GP_SHEET_H: float = 297.0


# A minimal symbol definition with a default size and optional ports / schema.
# 带标称尺寸与可选端口 / schema 的最小图元定义。
static func _gpDef(gpId: String, gpPorts: Array[GPPort] = [], gpSchema: GPPropertySchema = null,
		gpCategory: String = "equipment") -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = gpId
	gpD.gpCategory = gpCategory
	gpD.gpDefaultSize = Vector2(30.0, 30.0)
	gpD.gpPorts = gpPorts
	gpD.gpSchema = gpSchema
	return gpD


static func _gpSheet() -> GPSheet:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpWidthMM = GP_SHEET_W
	gpS.gpHeightMM = GP_SHEET_H
	return gpS


# One node with a tag, centred at a position.
# 一个带位号的节点，居中于给定位置。
static func _gpNode(gpG: GPPIDGraph, gpId: String, gpTag: String, gpPos: Vector2) -> GPPIDNode:
	var gpN: GPPIDNode = gpG.gpNewNode(gpId, "SYM", gpTag, gpPos)
	gpG.gpAddNode(gpN)
	return gpN


# Findings of one rule id.
# 某条规则的发现。
static func _gpOf(gpFindings: Array[GPFinding], gpRuleId: String) -> Array[GPFinding]:
	var gpOut: Array[GPFinding] = []
	for gpF in gpFindings:
		if gpF.gpRuleId == gpRuleId:
			gpOut.append(gpF)
	return gpOut


# ---------------------------------------------------------------------------
# Rule 1 — open ends need a note (ADR-34)
# 规则 1 —— 开口端需要注记（ADR-34）
# ---------------------------------------------------------------------------

func gpTestDanglingWithoutNoteIsError() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1", {"node_id": "", "point": [20.0, 20.0]},
		{"node_id": "n1", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE)
	var gpF: Array[GPFinding] = GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")])
	var gpR1: Array[GPFinding] = _gpOf(gpF, GPRulePack.GP_RULE_DANGLING)
	gpEq(gpR1.size(), 1, "一个未注明的开口端报一条 / one unnoted open end, one finding")
	if gpR1.size() == 1:
		gpEq(gpR1[0].gpMessageKey, "drc.end_note_missing", "原因键正确 / the cause key is right")
		gpEq(gpR1[0].gpSeverity, GPFinding.GP_ERROR, "是 error / it is an error")


func gpTestNotedOpenEndIsSilent() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1", {"node_id": "", "point": [20.0, 20.0]},
		{"node_id": "n1", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE)
	var gpNote: GPShape = GPShape.gpTextNote(Vector2(24.0, 20.0), "TO ATM")
	gpNote.gpUid = "t-1"
	gpG.gpAddShape(gpNote)
	gpE.gpSetEndNoteUid(true, "t-1")
	var gpF: Array[GPFinding] = GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")])
	gpEq(_gpOf(gpF, GPRulePack.GP_RULE_DANGLING).size(), 0,
		"已注明的开口端不报 / a noted open end is silent")


func gpTestNoteObjectDeletedIsItsOwnCause() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1", {"node_id": "", "point": [20.0, 20.0]},
		{"node_id": "n1", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE)
	gpE.gpSetEndNoteUid(true, "t-gone")
	var gpR1: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]),
		GPRulePack.GP_RULE_DANGLING)
	gpEq(gpR1.size(), 1, "引用失效报一条 / a dead reference is one finding")
	if gpR1.size() == 1:
		gpEq(gpR1[0].gpMessageKey, "drc.end_note_missing_object",
			"原因与「没注记」区分开 / the cause is distinct from 'no note'")


func gpTestBlankNoteTextIsItsOwnCause() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1", {"node_id": "", "point": [20.0, 20.0]},
		{"node_id": "n1", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE)
	var gpNote: GPShape = GPShape.gpTextNote(Vector2(24.0, 20.0), "   ")
	gpNote.gpUid = "t-blank"
	gpG.gpAddShape(gpNote)
	gpE.gpSetEndNoteUid(true, "t-blank")
	var gpR1: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]),
		GPRulePack.GP_RULE_DANGLING)
	gpEq(gpR1.size(), 1, "空文字报一条 / blank text is one finding")
	if gpR1.size() == 1:
		gpEq(gpR1[0].gpMessageKey, "drc.end_note_empty_text", "空文字有自己的原因键 / own cause key")


# ---------------------------------------------------------------------------
# Rule 2 — required ports only
# 规则 2 —— 只报「必需」端口
# ---------------------------------------------------------------------------

func gpTestSparePortIsNotADefect() -> void:
	var gpPort: GPPort = GPPort.new()
	gpPort.gpName = "spare"
	gpPort.gpType = GPPort.GP_NOZZLE
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpF: Array[GPFinding] = GPRulePack.gpRun(gpG, _gpSheet(),
		[_gpDef("SYM", [gpPort])])
	gpEq(_gpOf(gpF, GPRulePack.GP_RULE_PORT).size(), 0,
		"空置管口不报（默认非必需）/ a spare nozzle is silent by default")


func gpTestRequiredPortWiredIsSilent() -> void:
	var gpPort: GPPort = GPPort.new()
	gpPort.gpName = "out"
	gpPort.gpType = GPPort.GP_NOZZLE
	gpPort.gpRequired = true
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": "out"}, {"node_id": "", "point": [300.0, 100.0]},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE)
	gpE.gpSetEndNoteUid(false, "")
	var gpF: Array[GPFinding] = GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM", [gpPort])])
	gpEq(_gpOf(gpF, GPRulePack.GP_RULE_PORT).size(), 0,
		"必需端口已接线则不报 / a wired required port is silent")


func gpTestRequiredPortUnwiredIsError() -> void:
	var gpPort: GPPort = GPPort.new()
	gpPort.gpName = "out"
	gpPort.gpRequired = true
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpR2: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(),
		[_gpDef("SYM", [gpPort])]), GPRulePack.GP_RULE_PORT)
	gpEq(gpR2.size(), 1, "必需端口未接报一条 / one finding for an unwired required port")
	if gpR2.size() == 1:
		gpEq(gpR2[0].gpSeverity, GPFinding.GP_ERROR, "是 error / it is an error")


# ---------------------------------------------------------------------------
# Rule 3 — tags, with the deliberate silences
# 规则 3 —— 位号，以及刻意的沉默
# ---------------------------------------------------------------------------

func gpTestMissingTagIsError() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "", Vector2(100.0, 100.0))
	var gpR3: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]),
		GPRulePack.GP_RULE_TAG)
	gpEq(gpR3.size(), 1, "缺位号报一条 / a missing tag is one finding")
	if gpR3.size() == 1:
		gpEq(gpR3[0].gpMessageKey, "drc.tag_missing", "原因键正确 / the cause key is right")


func gpTestMountedPartNeedsNoTag() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "host", "V-100", Vector2(100.0, 100.0))
	var gpChild: GPPIDNode = _gpNode(gpG, "child", "", Vector2(130.0, 100.0))
	gpChild.gpParentUid = "host"
	gpChild.gpMountAnchor = "top"
	# The child overlaps its own host on purpose; the overlap rule must also stay silent.
	# 子件刻意压在宿主上；重叠规则同样必须沉默。
	gpEq(_gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]), GPRulePack.GP_RULE_TAG).size(), 0,
		"挂载部件无需位号 / a mounted part needs no tag")


func gpTestDuplicateTagIsError() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-100", Vector2(100.0, 100.0))
	_gpNode(gpG, "n2", "P-100", Vector2(200.0, 100.0))
	var gpR3: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]),
		GPRulePack.GP_RULE_TAG)
	gpEq(gpR3.size(), 1, "重复位号报一条 / one duplicate finding")
	if gpR3.size() == 1:
		gpEq(gpR3[0].gpMessageKey, "drc.tag_duplicate", "原因键正确 / the cause key is right")


func gpTestSignalLineNeedsNoPipeNumber() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": ""}, {"node_id": "", "point": [300.0, 100.0]},
		GPPIDEdge.GP_SIGNAL, "ELECTRIC", "")
	gpG.gpAddEdge(gpE)
	var gpR3: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]),
		GPRulePack.GP_RULE_TAG)
	gpEq(gpR3.size(), 0, "信号线不要求线号 / a signal line needs no pipe number")


# ---------------------------------------------------------------------------
# Rule 4 — required properties
# 规则 4 —— 必填属性
# ---------------------------------------------------------------------------

func gpTestRequiredPropertyMissing() -> void:
	var gpF: GPPropertyDef = GPPropertyDef.new()
	gpF.gpKey = "design_pressure"
	gpF.gpRequired = true
	var gpSchema: GPPropertySchema = GPPropertySchema.new()
	gpSchema.gpFields = [gpF]
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpR4: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(),
		[_gpDef("SYM", [], gpSchema)]), GPRulePack.GP_RULE_PROPS)
	gpEq(gpR4.size(), 1, "必填属性为空报一条 / one finding for an empty required property")


func gpTestRequiredPropertyFilled() -> void:
	var gpF: GPPropertyDef = GPPropertyDef.new()
	gpF.gpKey = "design_pressure"
	gpF.gpRequired = true
	var gpSchema: GPPropertySchema = GPPropertySchema.new()
	gpSchema.gpFields = [gpF]
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = _gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	gpN.gpProps["design_pressure"] = "1.6"
	gpEq(_gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM", [], gpSchema)]),
		GPRulePack.GP_RULE_PROPS).size(), 0, "填了就沉默 / a filled property is silent")


# ---------------------------------------------------------------------------
# Rule 5 — layout
# 规则 5 —— 布局
# ---------------------------------------------------------------------------

func gpTestOverlapIsWarning() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	_gpNode(gpG, "n2", "P-2", Vector2(110.0, 100.0))
	var gpR5: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]),
		GPRulePack.GP_RULE_LAYOUT)
	var gpFound: bool = false
	for gpF in gpR5:
		if gpF.gpMessageKey == "drc.symbols_overlap":
			gpFound = true
			gpEq(gpF.gpSeverity, GPFinding.GP_WARNING, "重叠是 warning / overlap is a warning")
	gpCheck(gpFound, "重叠被检出 / the overlap is reported")


func gpTestMountChildOverHostIsSilent() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "host", "V-100", Vector2(100.0, 100.0))
	var gpChild: GPPIDNode = _gpNode(gpG, "child", "V-100a", Vector2(105.0, 100.0))
	gpChild.gpParentUid = "host"
	gpChild.gpMountAnchor = "top"
	var gpR5: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]),
		GPRulePack.GP_RULE_LAYOUT)
	# Count first (this assertion always runs), then the per-finding probe.
	# 先无条件断言条数，再逐条探测 —— 否则没有发现时循环体一次也不执行，测试就成了空测试。
	var gpOverlaps: int = 0
	for gpF in gpR5:
		if gpF.gpMessageKey == "drc.symbols_overlap":
			gpOverlaps += 1
	gpEq(gpOverlaps, 0, "子件压宿主不产生重叠发现 / a mounted child over its host yields no overlap")


func gpTestOffSheetIsWarning() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(50.0, 50.0))
	_gpNode(gpG, "n2", "P-2", Vector2(600.0, 50.0))
	var gpR5: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]),
		GPRulePack.GP_RULE_LAYOUT)
	var gpFound: bool = false
	for gpF in gpR5:
		if gpF.gpMessageKey == "drc.symbol_off_sheet":
			gpFound = true
	gpCheck(gpFound, "越出图框被检出 / off-sheet is reported")


# ---------------------------------------------------------------------------
# Rule 6 — edge attribute completeness
# 规则 6 —— 连线属性完整性
# ---------------------------------------------------------------------------

func gpTestProcessEdgeMissingAttrs() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": ""}, {"node_id": "", "point": [300.0, 100.0]},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE)
	var gpR6: Array[GPFinding] = _gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]),
		GPRulePack.GP_RULE_EDGE_ATTRS)
	gpEq(gpR6.size(), 1, "缺属性报一条 / one finding")
	if gpR6.size() == 1:
		gpEq(gpR6[0].gpMessageKey, "drc.edge_attrs_missing", "原因键正确 / the cause key is right")


func gpTestProcessEdgeWithAttrsIsSilent() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "P-1", Vector2(100.0, 100.0))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": ""}, {"node_id": "", "point": [300.0, 100.0]},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpE.gpAttrs["dn"] = "DN100"
	gpE.gpAttrs["medium"] = "WATER"
	gpE.gpAttrs["spec"] = "A1A"
	gpG.gpAddEdge(gpE)
	gpEq(_gpOf(GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")]),
		GPRulePack.GP_RULE_EDGE_ATTRS).size(), 0, "属性齐全则沉默 / complete attrs are silent")


# ---------------------------------------------------------------------------
# Determinism + severity counting (E01 acceptance)
# 确定性与严重度统计（E01 验收）
# ---------------------------------------------------------------------------

func gpTestRunIsDeterministic() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "", Vector2(100.0, 100.0))
	_gpNode(gpG, "n2", "", Vector2(110.0, 100.0))
	var gpDefs: Array[GPSymbolDef] = [_gpDef("SYM")]
	var gpA: Array[GPFinding] = GPRulePack.gpRun(gpG, _gpSheet(), gpDefs)
	var gpB: Array[GPFinding] = GPRulePack.gpRun(gpG, _gpSheet(), gpDefs)
	gpEq(gpA.size(), gpB.size(), "两次运行条数一致 / same count twice")
	for gpI in range(gpA.size()):
		gpEq(gpA[gpI].gpToDict().hash(), gpB[gpI].gpToDict().hash(),
			"第 %d 条逐字段一致 / entry %d is identical" % [gpI, gpI])


func gpTestCountBySeverity() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	_gpNode(gpG, "n1", "", Vector2(100.0, 100.0))
	var gpF: Array[GPFinding] = GPRulePack.gpRun(gpG, _gpSheet(), [_gpDef("SYM")])
	gpCheck(GPRulePack.gpCount(gpF, GPFinding.GP_ERROR) >= 1, "至少一条 error / at least one error")
	gpEq(GPRulePack.gpCount(gpF, GPFinding.GP_ERROR)
		+ GPRulePack.gpCount(gpF, GPFinding.GP_WARNING)
		+ GPRulePack.gpCount(gpF, GPFinding.GP_INFO), gpF.size(),
		"分严重度统计之和等于总数 / severity counts sum to the total")


func gpTestEveryMessageKeyIsBilingual() -> void:
	var gpKeys: Array[String] = [
		"drc.end_note_missing", "drc.end_note_missing_object", "drc.end_note_empty_text",
		"drc.port_unconnected", "drc.tag_missing", "drc.tag_duplicate", "drc.edge_tag_missing",
		"drc.required_prop_missing", "drc.symbols_overlap", "drc.symbol_off_sheet",
		"drc.edge_crosses_symbol", "drc.signal_type_missing", "drc.edge_attrs_missing",
		"drc.sheet_sparse", "drc.sheet_crowded",
	]
	for gpK in gpKeys:
		var gpPair: Dictionary = I18n.GP_STRINGS.get(gpK, {})
		gpCheck(not gpPair.is_empty(), "键存在 / key present: " + gpK)
		gpCheck(str(gpPair.get("zh", "")) != "", "中文非空 / zh non-empty: " + gpK)
		gpCheck(str(gpPair.get("en", "")) != "", "英文非空 / en non-empty: " + gpK)
