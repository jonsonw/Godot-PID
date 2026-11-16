# Copyright 2026 G-PID Contributors. MIT License. See LICENSE.
class_name GPEquipmentScan
extends RefCounted

# Major-equipment scan over sheets (W13 T5 / ADR-47: new logic lives in a new file). Pure,
# model-only, zero UI — so the gate can pin the classification headless, and BOTH the sheet
# manager preview and any future equipment-table export reuse the same numbers.
# 图纸**主要设备**扫描（W13 T5 / ADR-47：新逻辑住新文件）。纯函数、只吃模型、零 UI ——
# 门禁可 headless 钉死分类数学；图纸管理预览与将来的设备表导出复用**同一组数字**。
#
# WHERE THE CATEGORY COMES FROM / 类别从哪里来：
# A symbol id is <source letter><CATEGORY CODE><3-digit sequence> (GPSymbolNaming is the one
# authority): DPUMP001 -> PUMP, CPUMP003 -> PUMP, LHEAT002 -> HEAT. The category code is ALREADY
# in the id, so classification is a parse, not a per-symbol lookup table that would drift from
# the packs. User decision (2026-11-10): majors = 泵 PUMP / 塔 COLUMN / 换热器 HEAT / 容器 VESSEL /
# 储罐 TANK. Codes with no row (VALVE, GENERAL, INSTRUMENT, …) are simply not major equipment.
# 图元 id 即 <来源码><类别码><三位序号>（GPSymbolNaming 是唯一权威）：DPUMP001 -> PUMP、
# CPUMP003 -> PUMP、LHEAT002 -> HEAT。类别码**已存在于 id 中**，分类是解析而非一张会与
# 图元包漂移的逐符号查找表。用户拍板（2026-11-10）：主要设备 = 泵 PUMP / 塔 COLUMN /
# 换热器 HEAT / 容器 VESSEL / 储罐 TANK。表中无行的类别码（VALVE、GENERAL、INSTRUMENT…）
# 就不是主要设备。
#
# MOUNTED CHILDREN / 挂载子件：
# A node with a non-empty gpParentUid is an ATTACHMENT (nozzle, manhole, actuator) of some host
# — attachments are never major equipment, no matter what their id looks like.
# gpParentUid 非空的节点是某个宿主的**附件**（接管口、人孔、执行机构）——附件永远不是主要
# 设备，无论其 id 长什么样。
#
# Coding rule: every variable declares its type explicitly. / 编码规范：所有变量均显式声明类型。

# Major-equipment category code -> i18n key for the display label. ONE table, keyed by the code
# parsed from ids; a new equipment family is one row here, nothing else.
# 主要设备类别码 -> 显示名 i18n 键。**一张表**、按 id 解析出的类别码作键；新增设备族只需此表
# 加一行，别处不用动。
const GP_EQUIPMENT_CODES: Dictionary = {
	"PUMP": "eq.cat.PUMP",
	"COLUMN": "eq.cat.COLUMN",
	"HEAT": "eq.cat.HEAT",
	"VESSEL": "eq.cat.VESSEL",
	"TANK": "eq.cat.TANK",
}


# Extract the category code from a symbol id: skip the source letter, collect A-Z until a digit.
# Tolerant of lower case (ids are canonical upper, but a hand-edited archive should still
# classify rather than silently fall out). No letters -> "" (e.g. "D123", "").
# 从图元 id 提取类别码：跳过来源码字母，收集 A-Z 直到遇数字。容忍小写（id 规范为大写，但
# 手改过的存档也应被分类而不是静默落空）。无字母 -> ""（如 "D123"、""）。
static func gpCategoryCode(gpSymbolId: String) -> String:
	if gpSymbolId.length() < 2:
		return ""
	var gpCode: String = ""
	for gpI: int in range(1, gpSymbolId.length()):
		var gpCh: String = gpSymbolId[gpI].to_upper()
		if gpCh >= "A" and gpCh <= "Z":
			gpCode += gpCh
		else:
			break
	return gpCode


# True when the category code is one of the decided major-equipment families.
# 类别码属于已拍板的主要设备族时为 true。
static func gpIsEquipmentCode(gpCode: String) -> bool:
	return GP_EQUIPMENT_CODES.has(gpCode)


# Scan ONE sheet. Null-safe: null sheet -> {"ok": false}. Output (all keys always present):
#   ok, sheet_id, sheet_name, sheet_number, node_count, edge_count, other_count,
#   equipment: Array[{uid, tag, symbol_id, code, label_key}] in graph order,
#   categories: {code: count} for major families only.
# 扫描**一张**图纸。null 安全：null 图纸 -> {"ok": false}。输出（键恒齐）：
#   ok / sheet_id / sheet_name / sheet_number / node_count / edge_count / other_count、
#   equipment（按图序的设备条目数组）、categories（仅主要设备族的计数）。
static func gpScanSheet(gpSheet: GPSheet) -> Dictionary:
	if gpSheet == null:
		return {"ok": false}
	var gpEquipment: Array[Dictionary] = []
	var gpCategories: Dictionary = {}
	var gpOther: int = 0
	var gpNodeCount: int = 0
	if gpSheet.gpGraph != null:
		gpNodeCount = gpSheet.gpGraph.gpNodes.size()
		for gpNode in gpSheet.gpGraph.gpNodes:
			if gpNode == null:
				continue
			# Mounted children are attachments of a host, never majors (see header).
			# 挂载子件是宿主的附件，永远不算主要设备（见文件头）。
			if not gpNode.gpParentUid.is_empty():
				continue
			var gpCode: String = gpCategoryCode(gpNode.gpSymbolId)
			if not gpIsEquipmentCode(gpCode):
				gpOther += 1
				continue
			gpCategories[gpCode] = int(gpCategories.get(gpCode, 0)) + 1
			gpEquipment.append({
				"uid": gpNode.gpInstanceId,
				"tag": gpNode.gpTag,
				"symbol_id": gpNode.gpSymbolId,
				"code": gpCode,
				"label_key": str(GP_EQUIPMENT_CODES.get(gpCode, "")),
			})
	var gpEdgeCount: int = 0
	if gpSheet.gpGraph != null:
		gpEdgeCount = gpSheet.gpGraph.gpEdges.size()
	return {
		"ok": true,
		"sheet_id": gpSheet.gpId,
		"sheet_name": gpSheet.gpName,
		"sheet_number": gpSheet.gpNumber,
		"node_count": gpNodeCount,
		"edge_count": gpEdgeCount,
		"other_count": gpOther,
		"equipment": gpEquipment,
		"categories": gpCategories,
	}


# Scan a sheet list in order; null sheets are skipped. / 依序扫描图纸列表；null 图纸被跳过。
static func gpScanSheets(gpSheets: Array) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	for gpSheet in gpSheets:
		var gpS: GPSheet = gpSheet as GPSheet
		if gpS == null:
			continue
		gpOut.append(gpScanSheet(gpS))
	return gpOut
