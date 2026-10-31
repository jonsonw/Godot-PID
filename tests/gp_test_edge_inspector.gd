extends "res://tests/gp_test.gd"
# Headless tests for the P4 edge inspector form contract (pure helpers) and the "change line
# type -> repaint immediately" seam. The form helpers are static so no widget is built; the
# repaint seam is exercised through GPEditService + the pure style table, exactly as the live
# canvas does (it redraws on gpGraphChanged). No canvas / autoload required.
# P4 连线属性面板表单契约（纯函数助手）与「改线型立即重绘」接缝的 headless 测试。表单助手为
# static，无需建控件；重绘接缝经 GPEditService + 纯样式表验证，与实时画布一致（画布在
# gpGraphChanged 时重绘）。无需画布 / 自动加载。

func _mkEdge(gpKind: String, gpSignalType: String = "") -> Array:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-101", Vector2(10, 10)))
	g.gpAddNode(g.gpNewNode("N2", "valve", "V-201", Vector2(100, 10)))
	var svc: GPEditService = GPEditService.new()
	svc.gpBindGraph(g, GPIdGen.new())
	var id: String = svc.gpConnectEdge({"node_id": "N1", "port_id": "p1"},
		{"node_id": "N2", "port_id": "p2"}, gpKind, gpSignalType)
	var e: GPPIDEdge = g.gpGetEdge(id)
	var out: Array = [g, svc, e, id]
	return out


# SIGNAL edges hide the pipe-only fields (dn / medium / spec / insulation).
# 信号线隐藏管道专属字段（dn/medium/spec/insulation）。
func gpTestSignalHidesPipeFields() -> void:
	var keys: Array[String] = GPInspector.gpEdgeFieldKeys(GPPIDEdge.GP_SIGNAL)
	gpCheck(keys.has("kind"), "signal form has kind")
	gpCheck(keys.has("signal_type"), "signal form has signal_type")
	gpCheck(keys.has("tag"), "signal form has tag")
	gpCheck(not keys.has("dn"), "signal form hides dn")
	gpCheck(not keys.has("medium"), "signal form hides medium")
	gpCheck(not keys.has("spec"), "signal form hides spec")
	gpCheck(not keys.has("insulation"), "signal form hides insulation")


# PROCESS and UTILITY keep all eight fields.
# PROCESS 与 UTILITY 保留全部八个字段。
func gpTestProcessShowsAllFields() -> void:
	var keys: Array[String] = GPInspector.gpEdgeFieldKeys(GPPIDEdge.GP_PROCESS)
	gpEq(keys.size(), 8, "process form has 8 fields")
	gpCheck(keys.has("dn") and keys.has("medium") and keys.has("spec") and keys.has("insulation"),
		"process form shows dn/medium/spec/insulation")


# A PROCESS edge's form pre-fills the minted tag and defaults show_tag=on, show_arrow=on.
# PROCESS 边表单预填铸出的管线号，且 show_tag / show_arrow 默认可勾选。
func gpTestProcessInitialValues() -> void:
	var f: Array = _mkEdge(GPPIDEdge.GP_PROCESS)
	var e: GPPIDEdge = f[2]
	var v: Dictionary = GPInspector.gpEdgeInitialValues(e)
	gpCheck(str(v["tag"]) != "", "process tag is pre-filled")
	gpEq(v["show_tag"], true, "process show_tag defaults on")
	gpEq(v["show_arrow"], true, "process show_arrow defaults on")


# A SIGNAL edge's form defaults show_tag=off (signal lines stay clean by convention).
# 信号线表单的 show_tag 默认关闭（按惯例信号线保持干净）。
func gpTestSignalInitialValues() -> void:
	var f: Array = _mkEdge(GPPIDEdge.GP_SIGNAL, "ELECTRIC")
	var e: GPPIDEdge = f[2]
	var v: Dictionary = GPInspector.gpEdgeInitialValues(e)
	gpEq(v["show_tag"], false, "signal show_tag defaults off")


# Changing an edge to SIGNAL pins ELECTRIC and the style table reflects it pure-functionally
# (the canvas repaints from this on gpGraphChanged). The change is one undoable step.
# 把边改为 SIGNAL 会钉死 ELECTRIC，且样式表以纯函数反映（画布据此在 gpGraphChanged 时重绘）。
# 该改动为一个可撤销步。
func gpTestSetKindSignalRepaintsAndUndoable() -> void:
	var f: Array = _mkEdge(GPPIDEdge.GP_PROCESS)
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var id: String = f[3]
	var e: GPPIDEdge = f[2]
	var changed: Array = [0]
	g.gpGraphChanged.connect(func(): changed[0] += 1)
	svc.gpSetEdgeKind(id, GPPIDEdge.GP_SIGNAL, "ELECTRIC")
	gpEq(e.gpKind, GPPIDEdge.GP_SIGNAL, "kind is SIGNAL after change")
	gpEq(e.gpSignalType, "ELECTRIC", "signal type pinned to ELECTRIC")
	gpEq(GPEdgeStyle.gpLineTypeKey(e.gpKind, e.gpSignalType), "line_type_electric",
		"style table resolves to electric signal line")
	gpCheck(changed[0] >= 1, "gpGraphChanged was emitted (drives immediate repaint)")
	svc.gpUndo()
	gpEq(e.gpKind, GPPIDEdge.GP_PROCESS, "undo restores PROCESS")
	gpEq(e.gpSignalType, "", "undo clears the signal type")


# Switching PROCESS -> UTILITY clears any stale signal type (kinds are mutually exclusive).
# PROCESS -> UTILITY 会清掉残留的信号类型（类型互斥）。
func gpTestSetUtilityClearsSignalType() -> void:
	var f: Array = _mkEdge(GPPIDEdge.GP_SIGNAL, "ELECTRIC")
	var svc: GPEditService = f[1]
	var id: String = f[3]
	var e: GPPIDEdge = f[2]
	svc.gpSetEdgeKind(id, GPPIDEdge.GP_UTILITY)
	gpEq(e.gpKind, GPPIDEdge.GP_UTILITY, "kind is UTILITY")
	gpEq(e.gpSignalType, "", "signal type cleared for a non-signal line")


# BUG-002: the edge form is driven by the project-standard line rule, so a newly added segment
# appears in the identity section; non-identity attrs land in the general section.
# BUG-002：边表单由项目标准管线规则驱动；新增段进入「管线编号」节，非标识属性进入「常规属性」节。
func gpTestEdgeSectionsFollowProjectStandardAndGeneralAttrs() -> void:
	var f: Array = _mkEdge(GPPIDEdge.GP_PROCESS)
	var e: GPPIDEdge = f[2]
	var std: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var rule: GPTagRule = std.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpRuleFor(null)
	rule.gpSegments.append(GPTagSegment.gpAttrText(
		"service", "服务等级", "service", 1, 6, GPTagSegment.GPCharset.GP_ALNUM, ""))
	e.gpAttrs["service"] = "CS"
	e.gpAttrs["design_pressure"] = "1.6"
	var sec: Dictionary = GPInspector.gpEdgeFieldSections(e, std)
	var identity: Array = sec["identity"] as Array
	var general: Array = sec["general"] as Array
	gpCheck(identity.has("tag"), "identity section has the line number")
	gpCheck(identity.has("dn"), "identity section has dn")
	gpCheck(identity.has("service"), "identity section has the new project-standard field")
	gpCheck(general.has("kind"), "general section has kind")
	gpCheck(general.has("design_pressure"), "general section has an engineering attribute")
	gpEq(GPInspector.gpEdgeFieldLabel("service", std), "服务等级",
		"the new field uses the rule segment's label")
	var keys: Array[String] = GPInspector.gpEdgeFieldKeysFor(e, std)
	gpCheck(keys.has("service"), "flat key list includes the new field")
	gpCheck(keys.has("design_pressure"), "flat key list includes the engineering attribute")
	gpCheck(GPInspector.gpEdgeInitialValues(e).has("service"),
		"initial values include the new field")


# A segment saved with a blank / reserved attr key falls back to its own gpKey, so the field is
# still visible and editing it can still re-render the line number (the early-editor mistake that
# produced "I added 子项号 but got an extra 管线号 11").
# 空属性键 / 保留属性键（tag 等）的段回退到段键，使字段仍可见、编辑仍能重渲染线号
#（即「加了子项号却多出一个管线号 11」的早期编辑器错误）。
func gpTestBlankAttrSegmentFallsBackToKey() -> void:
	var f: Array = _mkEdge(GPPIDEdge.GP_PROCESS)
	var e: GPPIDEdge = f[2]
	var std: GPProjectStandard = GPProjectStandard.gpDefaultStandard()
	var rule: GPTagRule = std.gpRulesOf(GPProjectStandard.GP_CLASS_LINE).gpRuleFor(null)
	rule.gpSegments.append(GPTagSegment.gpAttrText(
		"subitem", "子项号", "", 1, 4, GPTagSegment.GPCharset.GP_ALNUM, ""))
	e.gpAttrs["subitem"] = "11"
	var sec: Dictionary = GPInspector.gpEdgeFieldSections(e, std)
	gpCheck((sec["identity"] as Array).has("subitem"),
		"the blank-attr segment falls back to its key and stays visible")
	gpEq(GPInspector.gpEdgeFieldLabel("subitem", std), "子项号",
		"the segment label is used for the fallback key")
