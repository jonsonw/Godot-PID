extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# B6: SIGNAL-LINE DEXPI round trip (export → XML → read → import).
# B6：信号线的 DEXPI 往返（导出 → XML → 读取 → 导入）。
#
# The contract / 契约：
# DEXPI has no first-class signal-line class we can verify, so a signal line travels as a
# PipingNetworkSegment carrying two DECLARED marker attributes (`LineKindAssignmentClass` =
# `SIGNAL`, `SignalTypeAssignmentClass` = the signal type). That is a deviation, not an invented
# element — and it is what makes the round trip possible instead of dropping every instrument
# connection on export.
# DEXPI 没有可核实的信号线一等类，故信号线以 PipingNetworkSegment 随行，并带两条**已声明**的标记
# 属性（`LineKindAssignmentClass` = `SIGNAL`、`SignalTypeAssignmentClass` = 信号类型）。这是偏离，
# 不是臆造元素 —— 也正是它让往返成立，而不是一导出就丢掉所有仪表连线。
#
# The three promises / 三条承诺：
#   1. A SIGNAL LINE COMES BACK AS A SIGNAL LINE (kind + signal type intact).
#      **信号线回来还是信号线**（类型与信号类型不变）。
#   2. A PROCESS LINE STAYS BYTE-IDENTICAL — no marker is written when the edge is not a signal.
#      **工艺线逐字节不变** —— 非信号线不写标记。
#   3. THE MARKERS ARE TRANSPORT, NOT USER ATTRIBUTES — they must not surface in the inspector.
#      **标记是传输层，不是用户属性** —— 不得出现在属性面板。

const GP_SHEET_W: float = 420.0
const GP_SHEET_H: float = 297.0


static func _gpSheet() -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpName = "B6 Sheet"
	gpSheet.gpWidthMM = GP_SHEET_W
	gpSheet.gpHeightMM = GP_SHEET_H
	return gpSheet


# Two nodes with stable uids and one edge of the requested kind.
# 两个带稳定 uid 的节点，以及一条指定类型的边。
static func _gpGraph(gpKind: String, gpSignalType: String) -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpA: GPPIDNode = gpG.gpNewNode("n1", "DPUMP001", "P-1001", Vector2(100.0, 100.0))
	gpA.gpUid = "doc-n1"
	gpG.gpAddNode(gpA)
	var gpB: GPPIDNode = gpG.gpNewNode("n2", "DVALVE001", "V-201", Vector2(300.0, 100.0))
	gpB.gpUid = "doc-n2"
	gpG.gpAddNode(gpB)
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": ""}, {"node_id": "n2", "port_id": ""},
		gpKind, gpSignalType, "")
	gpG.gpAddEdge(gpE)
	return gpG


# Run the whole export → text → read → import chain, returning the imported edge dicts.
# 跑完「导出 → 文本 → 读取 → 导入」整链，返回导入后的边字典。
func _gpRoundTrip(gpKind: String, gpSignalType: String) -> Dictionary:
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(_gpGraph(gpKind, gpSignalType), _gpSheet())
	var gpXml: String = GPDexpiExporter.gpWriteXml(gpMid)
	var gpRead: GPIOResult = GPDexpiReader.gpReadXml(gpXml)
	gpCheck(gpRead.gpIsOk(), "导出的 XML 可被读回 / the exported XML reads back")
	var gpMid2: Dictionary = gpRead.gpPayload as Dictionary
	var gpV3: Dictionary = GPDexpiImporter.gpToV3(gpMid2)
	var gpSheets: Array = gpV3.get("sheets", []) as Array
	if gpSheets.is_empty():
		return {}
	return gpSheets[0] as Dictionary


# ---------------------------------------------------------------------------
# 1) Signal line survives the round trip
# 信号线经往返仍存在
# ---------------------------------------------------------------------------

func gpTestSignalLineRoundTrip() -> void:
	var gpSheet: Dictionary = _gpRoundTrip(GPPIDEdge.GP_SIGNAL, "PNEUMATIC")
	var gpEdges: Array = gpSheet.get("edges", []) as Array
	gpEq(gpEdges.size(), 1, "导入后仍有一条边 / one edge comes back")
	if gpEdges.is_empty():
		return
	var gpE: Dictionary = gpEdges[0] as Dictionary
	gpEq(str(gpE.get("kind", "")), GPPIDEdge.GP_SIGNAL, "类型仍是 SIGNAL / the kind is still SIGNAL")
	gpEq(str(gpE.get("signal_type", "")), "PNEUMATIC", "信号类型仍是气动 / the signal type survived")


func gpTestElectricSignalRoundTrip() -> void:
	var gpSheet: Dictionary = _gpRoundTrip(GPPIDEdge.GP_SIGNAL, "ELECTRIC")
	var gpEdges: Array = gpSheet.get("edges", []) as Array
	gpEq(gpEdges.size(), 1, "电气信号线往返 / an electric signal line round trips")
	if gpEdges.size() == 1:
		gpEq(str((gpEdges[0] as Dictionary).get("signal_type", "")), "ELECTRIC",
			"电气类型保留 / ELECTRIC is preserved")


# ---------------------------------------------------------------------------
# 2) Process lines are untouched
# 工艺线不受影响
# ---------------------------------------------------------------------------

func gpTestProcessLineRoundTripHasNoMarker() -> void:
	var gpG: GPPIDGraph = _gpGraph(GPPIDEdge.GP_PROCESS, "")
	var gpXml: String = GPDexpiExporter.gpWriteXml(
		GPDexpiExporter.gpFromGraph(gpG, _gpSheet()))
	gpCheck(not gpXml.contains("LineKindAssignmentClass"),
		"工艺线不写标记 / no marker is written for a process line")
	gpEq(gpXml.count("<PipingNetworkSegment"), 1, "工艺线仍是一条管段 / still one segment")
	var gpSheet: Dictionary = _gpRoundTrip(GPPIDEdge.GP_PROCESS, "")
	var gpEdges: Array = gpSheet.get("edges", []) as Array
	gpEq(gpEdges.size(), 1, "工艺线往返 / the process line round trips")
	if gpEdges.size() == 1:
		gpEq(str((gpEdges[0] as Dictionary).get("kind", "")), GPPIDEdge.GP_PROCESS,
			"类型仍是 PROCESS / the kind stays PROCESS")


func gpTestMarkerIsPresentForSignals() -> void:
	var gpG: GPPIDGraph = _gpGraph(GPPIDEdge.GP_SIGNAL, "DATA")
	var gpXml: String = GPDexpiExporter.gpWriteXml(
		GPDexpiExporter.gpFromGraph(gpG, _gpSheet()))
	gpCheck(gpXml.contains("LineKindAssignmentClass"), "信号线写出标记 / the marker is written")
	gpCheck(gpXml.contains("SignalTypeAssignmentClass"), "信号类型写出 / the signal type is written")
	gpCheck(gpXml.contains("SIGNAL"), "标记值为 SIGNAL / the marker says SIGNAL")


# ---------------------------------------------------------------------------
# 3) Markers must not become user attributes
# 标记不得变成用户属性
# ---------------------------------------------------------------------------

func gpTestMarkersDoNotLeakIntoAttrs() -> void:
	var gpSheet: Dictionary = _gpRoundTrip(GPPIDEdge.GP_SIGNAL, "ELECTRIC")
	var gpEdges: Array = gpSheet.get("edges", []) as Array
	if gpEdges.is_empty():
		return
	var gpAttrs: Dictionary = (gpEdges[0] as Dictionary).get("attrs", {}) as Dictionary
	gpCheck(not gpAttrs.has("line_kind"),
		"line_kind 不留在用户属性里 / line_kind is not left in user attributes")
	gpCheck(not gpAttrs.has("signal_type"),
		"signal_type 不重复留在 attrs 里 / signal_type is not duplicated into attrs")
