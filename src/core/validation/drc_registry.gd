class_name GPDrcRegistry
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# The DRC rule registry (ADR-39 D2): one stable, ordered list of descriptors. The engine never
# hard-codes "which rules exist"; it asks here. New checks must be registered to run — and to
# appear in the panel/config UI.
# DRC 规则注册表（ADR-39 D2）：一份稳定、有序的描述符清单。引擎不硬编码「有哪些规则」，
# 而是问这里。新检查必须登记才会执行 —— 也才会出现在面板/配置界面。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_SCOPE_SHEET: String = "sheet"
const GP_SCOPE_PROJECT: String = "project"


# Every rule, in stable order: legacy baseline first, then the new families.
# 全部规则，稳定顺序：先 legacy 基线，再新族。
static func gpAll() -> Array[GPDrcRule]:
	var gpOut: Array[GPDrcRule] = []
	# ---- legacy seven (implemented by GPRulePack, descriptors only) ----
	gpOut.append(GPDrcRule.gpMake("drc.dangling_end", "topo", "error", 0, Callable(),
		"drc.end_note_missing", "drc.fix.note_open_end", true))
	gpOut.append(GPDrcRule.gpMake("drc.port_unconnected", "topo", "error", 0, Callable(),
		"drc.port_unconnected", "drc.fix.wire_port", true))
	gpOut.append(GPDrcRule.gpMake("drc.tag", "tag", "error", 0, Callable(),
		"drc.tag_missing", "drc.fix.renumber", true))
	gpOut.append(GPDrcRule.gpMake("drc.required_props", "symbol", "error", 0, Callable(),
		"drc.required_prop_missing", "drc.fix.fill_prop", true))
	gpOut.append(GPDrcRule.gpMake("drc.layout", "layout", "warning", 0, Callable(),
		"drc.symbols_overlap", "drc.fix.move", true))
	gpOut.append(GPDrcRule.gpMake("drc.edge_attrs", "topo", "warning", 0, Callable(),
		"drc.edge_attrs_missing", "drc.fix.fill_prop", true))
	gpOut.append(GPDrcRule.gpMake("drc.sheet_fit", "layout", "info", 0, Callable(),
		"drc.sheet_sparse", "drc.fix.resize_sheet", true))

	# ---- P1 TOPO ----
	gpOut.append(_gpR("drc.topo.edge_ref_missing", "topo", "error", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckEdgeRefMissing(s, c), "drc.edge_ref_missing", "drc.fix.relink"))
	gpOut.append(_gpR("drc.topo.edge_port_type", "topo", "error", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckEdgePortType(s, c), "drc.edge_port_type", "drc.fix.reconnect"))
	gpOut.append(_gpR("drc.topo.edge_zero_length", "topo", "warning", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckEdgeZeroLength(s, c), "drc.edge_zero_length", "drc.fix.delete"))
	gpOut.append(_gpR("drc.topo.edge_duplicate", "topo", "warning", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckEdgeDuplicate(s, c), "drc.edge_duplicate", "drc.fix.delete"))
	gpOut.append(_gpR("drc.topo.edge_self_loop", "topo", "warning", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckEdgeSelfLoop(s, c), "drc.edge_self_loop", "drc.fix.relink"))

	# ---- P1 SYMBOL ----
	gpOut.append(_gpR("drc.symbol.unknown", "symbol", "error", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckSymbolUnknown(s, c), "drc.symbol_unknown", "drc.fix.replace_symbol"))
	gpOut.append(_gpR("drc.symbol.mount_integrity", "symbol", "error", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckMountIntegrity(s, c), "drc.mount_orphan", "drc.fix.remount"))
	gpOut.append(_gpR("drc.symbol.nozzle_duplicate", "symbol", "error", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckNozzleDuplicate(s, c), "drc.nozzle_duplicate", "drc.fix.renumber_nozzle"))
	gpOut.append(_gpR("drc.symbol.category_connect", "symbol", "error", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckSymbolCategoryConnect(s, c), "drc.symbol_category_connect", "drc.fix.relink"))
	gpOut.append(_gpR("drc.symbol.not_library", "symbol", "warning", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckSymbolNotLibrary(s, c), "drc.symbol_not_library", "drc.fix.promote_symbol"))

	# ---- P1 DOC ----
	gpOut.append(_gpR("drc.doc.sheet_number", "doc", "error", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckSheetNumber(s, c), "drc.sheet_number_missing", "drc.fix.set_number"))
	gpOut.append(_gpR("drc.doc.title_block_drawing_no", "doc", "warning", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckTitleBlockDrawingNo(s, c), "drc.title_block_drawing_no", "drc.fix.set_title_block"))
	gpOut.append(_gpR("drc.doc.title_block_required", "doc", "error", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckTitleBlockRequired(s, c), "drc.title_block_required", "drc.fix.fill_title_block"))
	gpOut.append(_gpR("drc.layout.title_block_intrusion", "layout", "warning", 1,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckTitleBlockIntrusion(s, c), "drc.title_block_intrusion", "drc.fix.move"))

	# ---- P2 LAYOUT ----
	gpOut.append(_gpR("drc.layout.line_overlap", "layout", "warning", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckLineOverlap(s, c), "drc.line_overlap", "drc.fix.reroute"))
	gpOut.append(_gpR("drc.layout.line_too_close", "layout", "info", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckLineTooClose(s, c), "drc.line_too_close", "drc.fix.reroute"))
	gpOut.append(_gpR("drc.layout.label_overlap", "layout", "warning", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckLabelOverlap(s, c), "drc.label_overlap", "drc.fix.move_label"))
	gpOut.append(_gpR("drc.layout.label_off_sheet", "layout", "warning", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckLabelOffSheet(s, c), "drc.label_off_sheet", "drc.fix.move_label"))
	gpOut.append(_gpR("drc.layout.annotation_crosses", "layout", "info", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckAnnotationCrosses(s, c), "drc.annotation_crosses", "drc.fix.move"))

	# ---- P2 TOPO ----
	gpOut.append(_gpR("drc.topo.branch_on_line", "topo", "error", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckBranchOnLine(s, c), "drc.branch_on_line", "drc.fix.add_junction"))
	gpOut.append(_gpR("drc.topo.signal_endpoint", "topo", "warning", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckSignalEndpoint(s, c), "drc.signal_endpoint", "drc.fix.relink"))
	gpOut.append(_gpR("drc.topo.dn_match", "topo", "warning", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckDnMatch(s, c), "drc.dn_match", "drc.fix.change_reducer"))
	gpOut.append(_gpR("drc.topo.media_continuity", "topo", "info", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckMediaContinuity(s, c), "drc.media_continuity", "drc.fix.check_medium"))

	# ---- P2 DOC ----
	gpOut.append(_gpR("drc.doc.title_block_inherit", "doc", "info", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckTitleBlockInherit(s, c), "drc.title_block_inherit", "drc.fix.review_override"))
	gpOut.append(_gpR("drc.doc.frame", "doc", "warning", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckFrame(s, c), "drc.frame_off", "drc.fix.frame_on"))

	# ---- gated checks (honest "needs a data model" entries) ----
	gpOut.append(_gpR("drc.topo.loop_number", "topo", "warning", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckLoopNumber(s, c), "drc.loop_number", "drc.fix.fill_loop"))
	gpOut.append(_gpGated("drc.topo.offpage_unpaired", "topo", "error", 2, "off-page connector model"))
	gpOut.append(_gpGated("drc.topo.flow_direction", "topo", "warning", 3, "flow-arrow attribute"))
	gpOut.append(_gpGated("drc.symbol.mount_part_props", "symbol", "warning", 2, "mounted-part schema"))
	gpOut.append(_gpGated("drc.symbol.pack_version", "symbol", "info", 3, "pack fingerprint"))
	gpOut.append(_gpGated("drc.symbol.scale", "symbol", "info", 3, "legacy scale marker"))
	gpOut.append(_gpR("drc.tag.prefix_category", "tag", "warning", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckPrefixCategory(s, c), "drc.tag_prefix_category", "drc.fix.renumber"))
	gpOut.append(_gpGated("drc.tag.reserved", "tag", "warning", 3, "reserved-word table"))
	gpOut.append(_gpGated("drc.line_group", "tag", "warning", 2, "line-group model"))
	gpOut.append(_gpR("drc.doc.revision", "doc", "warning", 2,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckRevision(s, c), "drc.revision_missing", "drc.fix.fill_title_block"))
	gpOut.append(_gpGated("drc.doc.sheet_ref", "doc", "error", 2, "off-page sheet references"))
	gpOut.append(_gpGated("drc.doc.dexpi", "doc", "error", 2, "DEXPI validator bridge"))
	gpOut.append(_gpGated("drc.doc.deliverable", "doc", "warning", 3, "deliverable/BOM bridge"))
	gpOut.append(_gpGated("drc.sem.nozzle_template", "sem", "info", 3, "project semantic rules"))
	gpOut.append(_gpR("drc.sem.valve_actuator", "sem", "warning", 3,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckValveActuator(s, c), "drc.sem_valve_actuator", "drc.fix.add_signal"))
	gpOut.append(_gpR("drc.sem.instrument_loop", "sem", "warning", 4,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckInstrumentLoop(s, c), "drc.sem_instrument_loop", "drc.fix.add_signal"))
	gpOut.append(_gpGated("drc.sem.psv", "sem", "info", 4, "project semantic rules"))
	gpOut.append(_gpGated("drc.sem.utility", "sem", "info", 4, "project semantic rules"))
	gpOut.append(_gpR("drc.sem.line_class", "sem", "info", 4,
		func(s: GPDrcSnapshot, c: Dictionary) -> Array[GPFinding]:
			return GPDRCRules.gpCheckLineClass(s, c), "drc.sem_line_class", "drc.fix.use_code"))

	return gpOut


static func _gpGated(gpId: String, gpFamily: String, gpSeverity: String, gpPhase: int,
		gpRequires: String) -> GPDrcRule:
	var gpR: GPDrcRule = GPDrcRule.gpMake(gpId, gpFamily, gpSeverity, gpPhase, Callable(),
		"", "", false)
	gpR.gpRequires = gpRequires
	return gpR


static func _gpR(gpId: String, gpFamily: String, gpSeverity: String, gpPhase: int,
		gpCheck: Callable, gpKey: String, gpHint: String) -> GPDrcRule:
	return GPDrcRule.gpMake(gpId, gpFamily, gpSeverity, gpPhase, gpCheck, gpKey, gpHint)


# One rule by id, or null.
# 按 id 取规则，或 null。
static func gpById(gpId: String) -> GPDrcRule:
	for gpR in gpAll():
		if gpR.gpId == gpId:
			return gpR
	return null
