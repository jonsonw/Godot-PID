class_name GpTestTagActions
extends GPGTest
# Headless tests for the three numbering entries — generate / validate / renumber — and the
# class rules that decide WHEN an instance is numbered (ADR-36 D3/D5/D7/D8/D9, step A4).
# 「生成 / 校验 / 重算」三个入口与「什么时候该编号」的类别规则
#（ADR-36 D3/D5/D7/D8/D9，A4 步）的 headless 测试。
#
# The promises being pinned / 被钉住的承诺：
# 1. a manual valve is NOT numbered; giving it an actuator turns it into an instrument and it
#    receives an instrument number (D5);
# 2. a new pipe is numbered from the LINE rule, with placeholders until its attributes exist;
# 3. filling the attributes re-renders the SAME number (no burned sequence numbers), and the
#    whole thing is one undo step (D9);
# 4. a hand-typed line number must satisfy the rule AND be unique on the sheet (D7);
# 5. renumbering treats "one line = one number": edges sharing a tag move together, and a
#    hand-set number is left alone (D8).
# 1. 手动阀**不**编号；给它装上执行机构即成为仪表并得到仪表号（D5）；
# 2. 新管线按**线规则**编号，属性未填时用占位；
# 3. 补属性**重渲染同一个号**（不烧序号），整件事一个撤销步（D9）；
# 4. 手打线号必须合规且在本图唯一（D7）；
# 5. 重编号遵守「一根线一个号」：同号的边一起动，手工号不动（D8）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


# A graph + standard + registry + edit service wired as the app wires them.
# 按应用的接法把 图 + 标准 + 注册器 + 编辑服务 装好。
func _gpSetup() -> Dictionary:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpStd: GPProjectStandard = gpG.gpStandardOrCreate()
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_MATERIAL,
		[{"code": "A1A", "label": "碳钢", "aliases": []}])
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_INSULATION,
		[{"code": "P", "label": "保冷", "aliases": []}])
	var gpReg: GPTagRegistry = GPTagRegistry.new()
	gpReg.gpGraph = gpG
	gpReg.gpStandard = gpStd
	gpReg.gpRules = gpG.gpTagRulesOrCreate()
	var gpOnly: Array[GPPIDGraph] = [gpG]
	gpReg.gpSetProjectGraphs(gpOnly)
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), gpReg)
	return {"graph": gpG, "std": gpStd, "reg": gpReg, "svc": gpSvc}


func _gpAttrs() -> Dictionary:
	return {"dn": "DN150", "medium": "循环冷却水", "spec": "碳钢", "insulation": "保冷"}


# Place two pumps and draw the pipe between them; returns [edgeId, pumpA, pumpB].
# 放两台泵并在它们之间画一条管线；返回 [边 id, 泵A, 泵B]。
func _gpPipe(gpSvc: GPEditService, gpG: GPPIDGraph) -> Array:
	var gpA: String = gpSvc.gpPlaceNode("DPUMP001", Vector2(0, 0))
	var gpB: String = gpSvc.gpPlaceNode("DPUMP001", Vector2(120, 0))
	var gpE: String = gpSvc.gpConnectEdge({"node_id": gpA, "port_id": "out"},
		{"node_id": gpB, "port_id": "in"}, GPPIDEdge.GP_PROCESS)
	return [gpE, gpA, gpB]


# ---------------------------------------------------------------- class decides numbering (D5)

func gpTestManualValveIsNotNumbered() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpId: String = gpSvc.gpPlaceNode("DVALVE002", Vector2.ZERO)
	gpCheck(gpId != "", "the valve was placed")
	gpEq(gpG.gpGetNode(gpId).gpTag, "", "a hand valve carries no number by default (D5)")


func gpTestActuatedValveGetsAnInstrumentNumber() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpId: String = gpSvc.gpPlaceNode("DVALVE002", Vector2.ZERO)
	gpEq(gpG.gpGetNode(gpId).gpTag, "", "starts unnumbered")
	gpCheck(gpSvc.gpSetProperty(gpId, "actuator_type", "气动"), "the actuator is set")
	gpEq(gpG.gpGetNode(gpId).gpTag, "I-1001",
		"an actuated valve is an instrument and gets an instrument number (D5)")


func gpTestSpecialItemUsesItsOwnRule() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpStd: GPProjectStandard = gpS["std"] as GPProjectStandard
	var gpReg: GPTagRegistry = gpS["reg"] as GPTagRegistry
	gpStd.gpClassification["by_symbol"] = {"DTEST_SP": GPProjectStandard.GP_CLASS_SPECIAL_ITEM}
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "DTEST_SP"
	gpDef.gpCategory = "general"
	gpEq(gpReg.gpNextTagForDef(gpDef), "SP-1001",
		"a special item is numbered by the special-item rule, not by the device rule")


func gpTestUnmappedSymbolIsNotNumbered() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpReg: GPTagRegistry = gpS["reg"] as GPTagRegistry
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "DUNMAPPED"
	gpDef.gpCategory = "general"
	gpEq(gpReg.gpNextTagForDef(gpDef), "",
		"a symbol with no numbering class is simply not numbered (a DRC info, not an error)")


# ---------------------------------------------------------------- generation (D8/D9)

func gpTestNewPipeIsNumberedWithPlaceholders() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpRow: Array = _gpPipe(gpSvc, gpG)
	var gpEdgeId: String = str(gpRow[0])
	gpCheck(gpEdgeId != "", "the pipe was created")
	gpEq(gpG.gpGetEdge(gpEdgeId).gpTag, "000-XX-0001-XXX-N",
		"a fresh pipe gets a legal placeholder number from the five-field rule")


func gpTestFillingAttributesReRendersTheSameNumber() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpEdgeId: String = str(_gpPipe(gpSvc, gpG)[0])
	gpCheck(gpSvc.gpApplyLineAttrs(gpEdgeId, _gpAttrs()), "attributes apply")
	var gpE: GPPIDEdge = gpG.gpGetEdge(gpEdgeId)
	gpEq(gpE.gpTag, "150-CWR-0001-A1A-P", "the number is re-rendered from the attributes")
	gpEq(str(gpE.gpAttrs.get("medium", "")), "循环冷却水", "the attribute itself is stored")


func gpTestFillingAttributesDoesNotBurnASequenceNumber() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpEdgeId: String = str(_gpPipe(gpSvc, gpG)[0])
	gpSvc.gpApplyLineAttrs(gpEdgeId, _gpAttrs())
	# A SECOND pipe must be 0002 — if filling the first had burned a number it would be 0003.
	# 第二根管线必须是 0002 —— 若补属性时烧掉一个号，这里就会是 0003。
	var gpRow2: Array = _gpPipe(gpSvc, gpG)
	gpEq(gpG.gpGetEdge(str(gpRow2[0])).gpTag, "000-XX-0002-XXX-N",
		"the placeholder number was reused, not burned")


func gpTestLineAttributesUndoIsOneStep() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpEdgeId: String = str(_gpPipe(gpSvc, gpG)[0])
	var gpOldTag: String = gpG.gpGetEdge(gpEdgeId).gpTag
	gpSvc.gpApplyLineAttrs(gpEdgeId, _gpAttrs())
	gpCheck(gpSvc.gpUndo(), "the panel's change is one undo step")
	var gpE: GPPIDEdge = gpG.gpGetEdge(gpEdgeId)
	gpEq(gpE.gpTag, gpOldTag, "undo restores the placeholder number")
	gpEq(str(gpE.gpAttrs.get("medium", "")), "", "undo removes the attributes it wrote")


# ---------------------------------------------------------------- copy / paste (D8)

func gpTestPastedPipeIsRenumberedByTheLineRule() -> void:
	# The reported bug: devices copied to another sheet got fresh numbers, pipes fell back to
	# the legacy "PL-xxxx" because the paste path used a different minter.
	# 用户报告的缺陷：拷贝到另一张图纸时设备号会更新，管线号却退回旧的 "PL-xxxx"，
	# 因为粘贴路径用了另一个铸号入口。
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpReg: GPTagRegistry = gpS["reg"] as GPTagRegistry
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	# The SOURCE sheet already issued 0001; the project counter must continue from there.
	# 源图纸已经发出 0001；工程计数器必须从那里接着走。
	var gpSourceTag: String = gpReg.gpNextTagForClass(GPProjectStandard.GP_CLASS_LINE, null,
		_gpAttrs())
	gpEq(gpSourceTag, "150-CWR-0001-A1A-P", "the source line owns 0001")
	var gpNodes: Array = [
		{"instance_id": "n1", "symbol_id": "DPUMP001", "tag": "P-1001", "position": [0, 0],
			"props": {}},
		{"instance_id": "n2", "symbol_id": "DPUMP001", "tag": "P-1002", "position": [100, 0],
			"props": {}},
	]
	var gpEdges: Array = [{
		"from_ref": {"node_id": "n1", "port_id": "out"},
		"to_ref": {"node_id": "n2", "port_id": "in"},
		"kind": GPPIDEdge.GP_PROCESS, "tag": gpSourceTag, "attrs": _gpAttrs(),
	}]
	var gpCmd: GPPasteClipboardCommand = GPPasteClipboardCommand.new(gpNodes, gpEdges, [],
		Vector2(10, 10))
	gpCheck(gpSvc.gpExecuteCommand(gpCmd), "the paste runs")
	gpCheck(gpG.gpEdges.size() == 1, "the pipe came across")
	if gpG.gpEdges.is_empty():
		return
	var gpPasted: String = gpG.gpEdges[0].gpTag
	gpEq(gpPasted, "150-CWR-0002-A1A-P",
		"the pasted pipe continues the LINE sequence (not a PL counter)")
	gpCheck(gpPasted.find("PL") < 0, "and it never falls back to the legacy PL prefix")


func gpTestLineAttributeChoicesComeFromTheCodeTables() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpStd: GPProjectStandard = gpS["std"] as GPProjectStandard
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpService: GPTagSegment = null
	var gpSize: GPTagSegment = null
	for gpSegRaw in gpRule.gpSegments:
		var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
		if gpSeg.gpKey == "service":
			gpService = gpSeg
		elif gpSeg.gpKey == "size":
			gpSize = gpSeg
	gpCheck(GPLineAttrsDialog.gpChoicesFor(gpService, gpStd).size() >= 2,
		"the medium picker is filled from the project's code table")
	gpEq(GPLineAttrsDialog.gpChoicesFor(gpSize, gpStd).size(), 0,
		"the size field is NOT a picker — it stays a number input")


func gpTestInspectorAttrChoicesComeFromTheStandard() -> void:
	# The right-hand panel must offer the project's codes, not a free-text box.
	# 右侧面板必须给出项目代号，而不是自由文本框。
	var gpS: Dictionary = _gpSetup()
	var gpStd: GPProjectStandard = gpS["std"] as GPProjectStandard
	gpCheck(GPInspector.gpEdgeAttrChoices("medium", gpStd).size() >= 2,
		"the medium picker is filled from the medium table")
	gpEq(GPInspector.gpEdgeAttrChoices("spec", gpStd).size(), 1,
		"the pipe-class picker is filled from the material table")
	gpEq(GPInspector.gpEdgeAttrChoices("insulation", gpStd).size(), 1,
		"the insulation picker is filled from the insulation table")
	gpEq(GPInspector.gpEdgeAttrChoices("dn", gpStd).size(), 0,
		"the size stays a text field")


func gpTestInspectorAttrEditRerendersTheLineNumber() -> void:
	# Reported: editing a line attribute in the right panel did nothing. The four pipe fields
	# build the number, so one edit must re-render it (same sequence), not just write the key.
	# 用户报告：在右侧面板改管线属性没反应。四个管道字段**构成**线号，故一次编辑必须用**同一个**
	# 序号重渲染它，而不是只写一个键。
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpPipe: Array = _gpPipe(gpSvc, gpG)
	var gpEdgeId: String = str(gpPipe[0])
	gpCheck(gpSvc.gpApplyLineAttrs(gpEdgeId, {"dn": "150", "medium": "CWR", "spec": "A1A",
		"insulation": "P"}), "the attributes apply")
	var gpEdge: GPPIDEdge = gpG.gpGetEdge(gpEdgeId)
	var gpBefore: String = gpEdge.gpTag
	gpCheck(gpBefore.begins_with("150-CWR-"), "the number reflects the attributes: " + gpBefore)
	gpCheck(gpSvc.gpApplyLineAttr(gpEdgeId, "medium", "PW"), "one attribute edit applies")
	gpCheck(gpEdge.gpTag != gpBefore, "the line number is re-rendered on screen")
	gpCheck(gpEdge.gpTag.begins_with("150-PW-"),
		"the new medium is in the number: " + gpEdge.gpTag)
	gpEq(str(gpEdge.gpAttrs.get("medium", "")), "PW", "the attribute itself is stored")


# ---------------------------------------------------------------- hand editing (D7)

func gpTestBadLineNumberIsRefusedWithTheSegment() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpEdgeId: String = str(_gpPipe(gpSvc, gpG)[0])
	gpSvc.gpApplyLineAttrs(gpEdgeId, _gpAttrs())
	gpCheck(not gpSvc.gpSetEdgeTag(gpEdgeId, "150-CWR-7-A1A-P"),
		"an unpadded counter is refused")
	gpEq(gpSvc.gpLastRefusal, "tag.err_rule", "the refusal says it is a rule violation")
	gpCheck(gpSvc.gpLastRefusalDetail.find("第 3 段") >= 0,
		"and points at the third segment: " + gpSvc.gpLastRefusalDetail)


func gpTestDuplicateLineNumberOnTheSheetIsRefused() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpEdgeId: String = str(_gpPipe(gpSvc, gpG)[0])
	gpSvc.gpApplyLineAttrs(gpEdgeId, _gpAttrs())
	var gpOther: GPPIDEdge = gpG.gpNewEdgeEx("e9", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "150-CWR-0002-A1A-P")
	gpG.gpAddEdge(gpOther)
	gpCheck(not gpSvc.gpSetEdgeTag(gpEdgeId, "150-CWR-0002-A1A-P"),
		"two lines on one sheet may not share a number")
	gpEq(gpSvc.gpLastRefusal, "tag.err_duplicate", "and it is reported as a duplicate")


func gpTestNodeTagMustMatchItsPrefix() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpId: String = gpSvc.gpPlaceNode("DPUMP001", Vector2.ZERO)
	gpCheck(not gpSvc.gpSetTag(gpId, "P-abc"), "a pump tag must end in digits")
	gpEq(gpSvc.gpLastRefusal, "tag.err_rule", "reported as a rule violation")
	gpCheck(gpSvc.gpSetTag(gpId, "P-2001"), "a well-formed tag is accepted")
	gpEq(gpG.gpGetNode(gpId).gpTag, "P-2001", "and stored")


# ---------------------------------------------------------------- renumbering (D8)

func gpTestRenumberKeepsOneNumberPerPipe() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpEdgeId: String = str(_gpPipe(gpSvc, gpG)[0])
	gpSvc.gpApplyLineAttrs(gpEdgeId, _gpAttrs())
	# A valve splits a pipe into several edges that carry the SAME number.
	# 阀门把一根管子切成多条边，它们带着**同一个**号。
	var gpSecond: GPPIDEdge = gpG.gpNewEdgeEx("e2", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "150-CWR-0001-A1A-P")
	gpSecond.gpAttrs = _gpAttrs()
	gpG.gpAddEdge(gpSecond)
	# A different line, with a smaller size, so renumbering really changes something.
	# 另一根线，管径更小，使重排真的产生变化。
	var gpThird: GPPIDEdge = gpG.gpNewEdgeEx("e3", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "150-CWR-0009-A1A-P")
	gpThird.gpAttrs = {"dn": "50", "medium": "循环冷却水", "spec": "碳钢", "insulation": "保冷"}
	gpG.gpAddEdge(gpThird)
	# Change the first line's size so the renumber output differs from its current number.
	# 改掉第一根线的管径，使重排输出与当前号不同。
	gpG.gpGetEdge(gpEdgeId).gpAttrs["dn"] = "80"
	gpSecond.gpAttrs["dn"] = "80"
	gpCheck(gpSvc.gpRenumberEdges(), "renumbering succeeds")
	gpEq(gpG.gpGetEdge(gpEdgeId).gpTag, "080-CWR-0001-A1A-P", "the first pipe gets 0001")
	gpEq(gpSecond.gpTag, "080-CWR-0001-A1A-P",
		"the second segment of the SAME pipe gets the SAME number")
	gpEq(gpThird.gpTag, "050-CWR-0002-A1A-P", "the other line gets the next number")


func gpTestRenumberLeavesManualNumbersAlone() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	var gpEdgeId: String = str(_gpPipe(gpSvc, gpG)[0])
	gpSvc.gpApplyLineAttrs(gpEdgeId, _gpAttrs())
	var gpManual: GPPIDEdge = gpG.gpNewEdgeEx("e5", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "150-CWR-0777-A1A-P")
	gpManual.gpAttrs = _gpAttrs()
	gpManual.gpAttrs["tag_manual"] = true
	gpG.gpAddEdge(gpManual)
	gpSvc.gpRenumberEdges()
	gpEq(gpManual.gpTag, "150-CWR-0777-A1A-P", "a hand-set number survives renumbering")


func gpTestAttrEditHealsTheSplitStandard() -> void:
	# Real-world shape: numbering ran off the REGISTRY's standard while the GRAPH had none (a
	# session whose project never went through "apply standard"). The re-render path read the
	# graph's standard, found nothing, and silently left the number stale.
	# 真实形状：铸造走**注册器**的标准，而**图**上没有（工程从未点过「应用标准」的会话）。
	# 重渲染路径读图上的标准，读到空，于是静默留下陈旧线号。
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpCheck(gpG.gpStandard == null, "the graph starts without a standard")
	var gpStd: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var gpReg: GPTagRegistry = GPTagRegistry.new()
	gpReg.gpGraph = gpG
	gpReg.gpRules = gpG.gpTagRulesOrCreate()
	var gpOnly: Array[GPPIDGraph] = [gpG]
	gpReg.gpSetProjectGraphs(gpOnly)
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), gpReg)
	gpReg.gpStandard = gpStd
	var gpEdge: GPPIDEdge = gpG.gpNewEdgeEx("e1", {"node_id": "", "port_id": ""},
		{"node_id": "", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "050-PW-0001-A1A-H")
	gpEdge.gpAttrs = {"dn": "50", "medium": "PW", "spec": "A1A", "insulation": "H"}
	gpG.gpAddEdge(gpEdge)
	gpCheck(gpSvc.gpApplyLineAttr("e1", "dn", "100"), "the single attribute edit applies")
	gpCheck(gpG.gpStandard != null, "the graph adopts the registry's standard (healed)")
	gpCheck(gpEdge.gpTag.begins_with("100-PW-"),
		"the number is re-rendered with the new diameter: " + gpEdge.gpTag)


# BUG-003: once the project defines a `dn` code table, the size segment is a PICKER on both
# surfaces — not a free text field. The default empty table must still leave it as text.
# BUG-003：项目定义 dn 代号表后，管径段在两个入口都必须是下拉，而不是自由文本；
# 空表时仍保持文本输入。
func gpTestDnCodeTableMakesSizeAPickerEverywhere() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpStd: GPProjectStandard = gpS["std"] as GPProjectStandard
	var gpRule: GPTagRule = GPTagRulePresets.gpLineCompact()
	var gpSize: GPTagSegment = null
	for gpSegRaw in gpRule.gpSegments:
		var gpSeg: GPTagSegment = gpSegRaw as GPTagSegment
		if gpSeg.gpKey == "size":
			gpSize = gpSeg
	gpCheck(gpSize != null, "the compact rule has a size segment")
	gpEq(GPLineAttrsDialog.gpChoicesFor(gpSize, gpStd).size(), 0,
		"empty dn table keeps the size as text")
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_DN, [
		{"code": "50", "label": "DN50"},
		{"code": "80", "label": "DN80"},
	])
	gpEq(GPLineAttrsDialog.gpChoicesFor(gpSize, gpStd).size(), 2,
		"dn table turns the dialog size field into a picker")
	gpEq(GPInspector.gpEdgeAttrChoices("dn", gpStd).size(), 2,
		"dn table turns the inspector size field into a picker")
	gpEq(GPInspector.gpEdgeAttrTable("dn", gpStd), GPProjectStandard.GP_TABLE_DN,
		"the inspector resolves dn to the dn table")


# BUG-003 regression: a code-table VALUE like DN80 (not just "80") must re-render the tag's
# digits through ATTR_DIGITS, and a selected code must update the line number.
# BUG-003 回归：代号值 DN80（不只是 "80"）也必须经 ATTR_DIGITS 重渲染出数字，选择后线号更新。
func gpTestDnCodeValueRerendersLineNumber() -> void:
	var gpS: Dictionary = _gpSetup()
	var gpStd: GPProjectStandard = gpS["std"] as GPProjectStandard
	var gpSvc: GPEditService = gpS["svc"] as GPEditService
	var gpG: GPPIDGraph = gpS["graph"] as GPPIDGraph
	gpStd.gpSetCodeTable(GPProjectStandard.GP_TABLE_DN, [
		{"code": "DN50", "label": "50"},
		{"code": "DN80", "label": "80"},
	])
	var gpPipe: Array = _gpPipe(gpSvc, gpG)
	var gpEdgeId: String = str(gpPipe[0])
	gpSvc.gpApplyLineAttrs(gpEdgeId, {"dn": "DN50", "medium": "CWR", "spec": "A1A", "insulation": "N"})
	gpCheck(gpG.gpGetEdge(gpEdgeId).gpTag.begins_with("050-"),
		"DN50 renders 050: " + gpG.gpGetEdge(gpEdgeId).gpTag)
	gpCheck(gpSvc.gpApplyLineAttr(gpEdgeId, "dn", "DN80"), "DN80 applies")
	gpCheck(gpG.gpGetEdge(gpEdgeId).gpTag.begins_with("080-"),
		"DN80 renders 080: " + gpG.gpGetEdge(gpEdgeId).gpTag)
