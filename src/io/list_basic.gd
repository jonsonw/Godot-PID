class_name GPListBasic
extends RefCounted
# Copyright © 2026 Jonson Wang
# Bill-of-materials style lists: one CSV per symbol category, carrying TAG + NAME + the
# effective value of every property the library declares (M13).
# 物料清单式清单：每个图元类别一张 CSV，含位号 + 名称 + 库声明的每个属性的**有效值**（M13）。
#
# Why TAG is the row key / 为何以位号作为行键：
#   A list is a DELIVERABLE that工艺 / DCS 点表 / 现场标牌 read, and those documents speak in
#   tags — never in uids. Re-import therefore matches rows back to nodes BY TAG.
#   清单是给工艺 / DCS 点表 / 现场标牌读的**交付物**，那些文档只认位号、不认 uid，
#   故回灌按**位号**把行匹配回节点。
#
# Every read goes through GPPropertyResolver — never node.gpProps directly — so an exported
# value is byte-for-byte what the inspector and W10 validation show.
# 所有读取都经 GPPropertyResolver —— 绝不直接读 node.gpProps —— 故导出的取值
# 与属性面板、W10 校验所见逐字节一致。
#
# ROUND-TRIP RULE (the subtle one) / 往返规则（最关键的一条）：
#   gpProps.has(key) is what separates "never touched" from "explicitly set to the default"
#   (M8). A naive re-import would write EVERY column and destroy that distinction, so
#   gpApplyList only writes a cell when it actually DIFFERS from the current effective value
#   — and ERASES the key when the cell is blank ("follow the library default again").
#   gpProps.has(key) 区分「从未动过」与「显式设为默认值」（M8）。朴素的回灌会把每一列都写回去，
#   从而摧毁该区分，故 gpApplyList 仅在单元格与当前有效值**确有差异**时才写入；
#   单元格为空则**删除该键**（意为「重新跟随库默认」）。
#
# Coding rule: every variable declares its type explicitly; all functions are static (pure).
# 编码规范：所有变量均显式声明类型；函数全部为静态（纯函数）。

# Columns emitted before the schema-driven property columns.
# 排在 schema 属性列之前的两列。
const GP_COL_TAG: String = "tag"
const GP_COL_NAME: String = "name"

# File extension of every exported list. / 所有导出清单的扩展名。
const GP_LIST_EXT: String = ".csv"


# ==================== building / 构建 ====================

# One EXPORT row per node of gpCategory: tag + name + every effective property.
# Values are rendered for text (see _gpValueText) — these rows feed the CSV, not the model.
# 某类别每个节点一行**导出行**：位号 + 名称 + 全部有效属性。取值已渲染为文本
# （见 _gpValueText）—— 这些行供 CSV 使用，不是模型对象。
# gpDefs falls back to the live symbol library when omitted.
# 省略 gpDefs 时回落到活动图元库。
static func gpBuildList(gpGraph: GPPIDGraph, gpCategory: String,
		gpDefs: Array[GPSymbolDef] = []) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpGraph == null:
		return gpOut
	var gpAll: Array[GPSymbolDef] = _gpResolveDefs(gpDefs)
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		var gpDef: GPSymbolDef = GPPropertyResolver.gpDefById(gpAll, gpN.gpSymbolId)
		# A node whose symbol vanished from the library has no schema to export — skip it
		# rather than emitting a row that cannot be matched back.
		# 图元已从库中消失的节点没有可导出的 schema —— 跳过，而非产出无法回灌的行。
		if gpDef == null or gpDef.gpCategory != gpCategory:
			continue
		gpOut.append(_gpRow(gpN, gpDef))
	return gpOut


# Build the export row for one node. / 构建单节点的导出行。
static func _gpRow(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> Dictionary:
	var gpRow: Dictionary = {}
	gpRow[GP_COL_TAG] = gpNode.gpTag
	gpRow[GP_COL_NAME] = GPPropertyResolver.gpDisplayName(
		gpNode.gpNames, gpDef.gpDisplayName, GPPropertyResolver.GP_FALLBACK_LOCALE, gpNode.gpTag)
	if gpDef.gpSchema == null:
		return gpRow
	for gpK in gpDef.gpSchema.gpKeys():
		var gpField: GPPropertyDef = gpDef.gpSchema.gpFieldByKey(gpK)
		var gpValue: Variant = GPPropertyResolver.gpEffectiveValue(
			gpDef.gpSchema, gpNode.gpProps, gpK)
		gpRow[gpK] = _gpValueText(gpField, gpValue)
	return gpRow


# Render one effective value as export text. MULTILANG becomes its display text: a raw dict
# is unreadable in Excel and could never round-trip.
# 把单个有效值渲染为导出文本。MULTILANG 渲染为其显示文本：裸字典在 Excel 里不可读，
# 也永远无法往返。
static func _gpValueText(gpField: GPPropertyDef, gpValue: Variant) -> String:
	if gpValue == null:
		return ""
	if gpField != null and gpField.gpKind == GPPropertyDef.GPKind.GP_MULTILANG:
		var gpMl: Dictionary = gpValue if gpValue is Dictionary else {}
		return GPPropertyResolver.gpDisplayName(gpMl, "", GPPropertyResolver.GP_FALLBACK_LOCALE, "")
	return str(gpValue)


# Categories actually present in the graph, sorted — drives "one file per category".
# 图中实际出现的类别（已排序），驱动「一类别一文件」。
static func gpCategories(gpGraph: GPPIDGraph, gpDefs: Array[GPSymbolDef] = []) -> Array[String]:
	var gpSeen: Dictionary = {}
	if gpGraph != null:
		var gpAll: Array[GPSymbolDef] = _gpResolveDefs(gpDefs)
		for gpN in gpGraph.gpNodes:
			if gpN == null:
				continue
			var gpDef: GPSymbolDef = GPPropertyResolver.gpDefById(gpAll, gpN.gpSymbolId)
			if gpDef != null and gpDef.gpCategory != "":
				gpSeen[gpDef.gpCategory] = true
	var gpOut: Array[String] = []
	for gpK in gpSeen.keys():
		gpOut.append(str(gpK))
	gpOut.sort()
	return gpOut


# ==================== CSV ====================

# Column order: tag, name, then every property key in first-seen order. Symbols of ONE
# category may declare different schemas, so the header is the UNION across all rows —
# a column a row does not have simply exports as blank.
# 列顺序：位号、名称，随后按「首次出现」顺序排各属性键。同一类别下的图元 schema 可能不同，
# 故表头取所有行的**并集** —— 某行没有的列导出为空。
static func gpColumns(gpRows: Array[Dictionary]) -> Array[String]:
	var gpOut: Array[String] = [GP_COL_TAG, GP_COL_NAME]
	for gpRow in gpRows:
		for gpK in gpRow.keys():
			var gpS: String = str(gpK)
			if not gpOut.has(gpS):
				gpOut.append(gpS)
	return gpOut


# Render rows as CSV (header line + one line per row).
# 把行渲染为 CSV（表头行 + 每行一行）。
static func gpListToCsv(gpRows: Array[Dictionary]) -> String:
	var gpCols: Array[String] = gpColumns(gpRows)
	# Neither Array[String] nor PackedStringArray offers join() in Godot 4 — concatenate by hand.
	# Godot 4 中 Array[String] 与 PackedStringArray 都没有 join() —— 手工拼接。
	var gpOut: String = ""
	for gpI in range(gpCols.size()):
		if gpI > 0:
			gpOut += ","
		gpOut += GPTagRuleService.gpCsvCell(gpCols[gpI])
	gpOut += "\n"
	for gpRow in gpRows:
		for gpJ in range(gpCols.size()):
			if gpJ > 0:
				gpOut += ","
			gpOut += GPTagRuleService.gpCsvCell(_gpCellText(gpRow, gpCols[gpJ]))
		gpOut += "\n"
	return gpOut


# Text for one cell; a column this row does not have exports as blank (never "null").
# 单元格文本；本行没有的列导出为空白（绝不是 "null"）。
static func _gpCellText(gpRow: Dictionary, gpKey: String) -> String:
	if not gpRow.has(gpKey) or gpRow[gpKey] == null:
		return ""
	return str(gpRow[gpKey])


# Parse CSV back into rows (inverse of gpListToCsv). Every value is a String — coercion to the
# declared kind happens in gpApplyList, which is the only place that knows the schema.
# 把 CSV 解析回行（gpListToCsv 的逆操作）。每个取值都是字符串 —— 到声明类型的强制转换
# 发生在 gpApplyList，因为只有它知道 schema。
static func gpCsvToList(gpText: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	var gpLines: PackedStringArray = gpText.split("\n", false)
	if gpLines.is_empty():
		return gpOut
	var gpHeader: Array[String] = _gpSplitLine(_gpStripCr(gpLines[0]))
	for gpI in range(1, gpLines.size()):
		var gpCells: Array[String] = _gpSplitLine(_gpStripCr(gpLines[gpI]))
		var gpRow: Dictionary = {}
		# A short line keeps the trailing columns blank instead of dropping them — a
		# hand-edited CSV must not silently truncate a row.
		# 短行把尾部列留空而非丢弃 —— 手工编辑过的 CSV 不该静默截断一行。
		for gpJ in range(gpHeader.size()):
			gpRow[gpHeader[gpJ]] = gpCells[gpJ] if gpJ < gpCells.size() else ""
		gpOut.append(gpRow)
	return gpOut


# Split one CSV line, honouring "quoted" cells and "" escapes.
# 拆分一行 CSV，识别 "带引号" 单元格与 "" 转义。
static func _gpSplitLine(gpLine: String) -> Array[String]:
	var gpOut: Array[String] = []
	var gpCur: String = ""
	var gpInQuotes: bool = false
	var gpI: int = 0
	while gpI < gpLine.length():
		var gpC: String = gpLine.substr(gpI, 1)
		if gpInQuotes:
			if gpC == "\"":
				# "" inside quotes is one literal quote. / 引号内的 "" 是一个字面引号。
				if gpI + 1 < gpLine.length() and gpLine.substr(gpI + 1, 1) == "\"":
					gpCur += "\""
					gpI += 1
				else:
					gpInQuotes = false
			else:
				gpCur += gpC
		elif gpC == "\"":
			gpInQuotes = true
		elif gpC == ",":
			gpOut.append(gpCur)
			gpCur = ""
		else:
			gpCur += gpC
		gpI += 1
	gpOut.append(gpCur)
	return gpOut


# Excel on Windows emits CRLF; a stray CR would otherwise end up inside the last cell.
# Windows 版 Excel 会输出 CRLF；残留的 CR 否则会混进最后一个单元格。
static func _gpStripCr(gpLine: String) -> String:
	return gpLine.replace("\r", "")


# ==================== writing to disk / 落盘 ====================

# Write one CSV per category into gpDir. Returns {category: path}.
# 把每个类别写一张 CSV 到 gpDir。返回 {类别: 路径}。
# gpDir must already exist. A file that cannot be opened is simply omitted from the result —
# one unwritable category must not lose the other three.
# gpDir 须已存在。打不开的文件直接从结果中省略 —— 一个类别写不出去不该连累其余三个。
static func gpExportLists(gpGraph: GPPIDGraph, gpDir: String,
		gpDefs: Array[GPSymbolDef] = []) -> Dictionary:
	var gpOut: Dictionary = {}
	if gpGraph == null or gpDir == "":
		return gpOut
	for gpCat in gpCategories(gpGraph, gpDefs):
		var gpRows: Array[Dictionary] = gpBuildList(gpGraph, gpCat, gpDefs)
		var gpPath: String = gpDir.path_join(gpCat + GP_LIST_EXT)
		var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.WRITE)
		if gpF == null:
			continue
		gpF.store_string(gpListToCsv(gpRows))
		gpF.close()
		gpOut[gpCat] = gpPath
	return gpOut


# ==================== re-import (回灌) ====================

# Write imported rows back onto the graph, MATCHED BY TAG. Returns how many nodes changed.
# 把导入的行写回图，**按位号匹配**。返回发生变化的节点数。
# Rules / 规则：
#  - the tag column is the KEY and is never written: renumbering belongs to the renumber
#    command, which alone keeps the project tag registry consistent;
#    位号列是**键**且绝不写回：重编号属于重编号命令，只有它能保持项目位号注册表一致；
#  - the name column writes into the fallback locale when non-empty;
#    名称列非空时写入回落语种；
#  - a property column is written ONLY when the node's own symbol declares that key, and is
#    coerced to the declared kind — a stray column can never invent a property;
#    属性列仅在节点自身图元声明了该键时才写入，并强制转换为声明类型 —— 多余列绝不会凭空造属性；
#  - a BLANK cell ERASES the key, meaning "follow the library default again" (see the
#    round-trip rule in this file's header).
#    空单元格**删除**该键，意为「重新跟随库默认」（见本文件头部的往返规则）。
static func gpApplyList(gpGraph: GPPIDGraph, gpRows: Array[Dictionary],
		gpDefs: Array[GPSymbolDef] = []) -> int:
	if gpGraph == null:
		return 0
	var gpAll: Array[GPSymbolDef] = _gpResolveDefs(gpDefs)
	var gpChanged: int = 0
	for gpRow in gpRows:
		var gpNode: GPPIDNode = _gpNodeByTag(gpGraph, str(gpRow.get(GP_COL_TAG, "")))
		if gpNode == null:
			continue
		if _gpApplyRow(gpNode, gpRow, GPPropertyResolver.gpDefById(gpAll, gpNode.gpSymbolId)):
			gpChanged += 1
	return gpChanged


# Tags in gpRows that match no node. A typo in Excel must be REPORTED, not silently dropped —
# that is why this is a separate query instead of a return value.
# gpRows 中匹配不到任何节点的位号。Excel 里的拼写错误必须**报出来**而非静默丢弃 ——
# 这正是它做成一个独立查询、而非塞进返回值的原因。
static func gpUnmatchedTags(gpGraph: GPPIDGraph, gpRows: Array[Dictionary]) -> Array[String]:
	var gpOut: Array[String] = []
	if gpGraph == null:
		return gpOut
	for gpRow in gpRows:
		var gpTag: String = str(gpRow.get(GP_COL_TAG, ""))
		if gpTag == "" or gpOut.has(gpTag):
			continue
		if _gpNodeByTag(gpGraph, gpTag) == null:
			gpOut.append(gpTag)
	gpOut.sort()
	return gpOut


# Apply one row to one node. Returns whether anything actually changed.
# 把一行应用到单个节点。返回是否确有变化。
static func _gpApplyRow(gpNode: GPPIDNode, gpRow: Dictionary, gpDef: GPSymbolDef) -> bool:
	var gpBefore: int = gpNode.gpProps.hash()
	var gpBeforeNames: int = gpNode.gpNames.hash()
	var gpNameIn: String = str(gpRow.get(GP_COL_NAME, "")).strip_edges()
	if gpNameIn != "" and gpDef != null:
		# Only write on a real difference. The export falls back to the library display name,
		# so even a never-named instance carries text in the name column — writing it back
		# would fabricate a name out of the fallback and count as a change.
		# 仅在确有差异时写入。导出会回落到库显示名，故连从未命名的实例在名称列里也有文本 ——
		# 原样写回等于凭回落值凭空造出一个名称，还会被计为一次变更。
		var gpCurrentName: String = GPPropertyResolver.gpDisplayName(
			gpNode.gpNames, gpDef.gpDisplayName, GPPropertyResolver.GP_FALLBACK_LOCALE, gpNode.gpTag)
		if gpNameIn != gpCurrentName:
			gpNode.gpNames[GPPropertyResolver.GP_FALLBACK_LOCALE] = gpNameIn
	if gpDef == null or gpDef.gpSchema == null:
		return gpNode.gpProps.hash() != gpBefore or gpNode.gpNames.hash() != gpBeforeNames
	for gpK in gpDef.gpSchema.gpKeys():
		if not gpRow.has(gpK):
			continue
		var gpField: GPPropertyDef = gpDef.gpSchema.gpFieldByKey(gpK)
		var gpRaw: String = str(gpRow[gpK]).strip_edges()
		var gpCurrent: Variant = GPPropertyResolver.gpEffectiveValue(
			gpDef.gpSchema, gpNode.gpProps, gpK)
		if gpRaw == "":
			# Cleared in Excel — drop the override and follow the library default again.
			# 在 Excel 里被清空 —— 删除覆盖，重新跟随库默认。
			if gpNode.gpProps.has(gpK):
				gpNode.gpProps.erase(gpK)
			continue
		if gpField.gpKind == GPPropertyDef.GPKind.GP_MULTILANG:
			if gpRaw == _gpValueText(gpField, gpCurrent):
				continue
			var gpMl: Dictionary = gpCurrent if gpCurrent is Dictionary else {}
			gpMl = gpMl.duplicate(true)
			gpMl[GPPropertyResolver.GP_FALLBACK_LOCALE] = gpRaw
			gpNode.gpProps[gpK] = gpMl
			continue
		var gpCoerced: Variant = gpField.gpCoerce(gpRaw)
		# Only write on a real difference: re-importing an untouched export must leave
		# gpProps exactly as it was, or "never touched" would be lost (see header).
		# 仅在确有差异时写入：回灌一份未改动的导出必须让 gpProps 原封不动，
		# 否则「从未动过」这一信息就丢了（见文件头部）。
		if gpCoerced != gpCurrent:
			gpNode.gpProps[gpK] = gpCoerced
	return gpNode.gpProps.hash() != gpBefore or gpNode.gpNames.hash() != gpBeforeNames


# ==================== internals / 内部 ====================

# The library to resolve against: an explicit list wins, otherwise the live one.
# 用于解析的图元库：显式传入者优先，否则用活动库。
static func _gpResolveDefs(gpDefs: Array[GPSymbolDef]) -> Array[GPSymbolDef]:
	if not gpDefs.is_empty():
		return gpDefs
	return GPSymbolLibrary.gpDefaultDefs()


# Find a node by tag (the row key). / 按位号（行键）查找节点。
static func _gpNodeByTag(gpGraph: GPPIDGraph, gpTag: String) -> GPPIDNode:
	if gpTag == "":
		return null
	for gpN in gpGraph.gpNodes:
		if gpN != null and gpN.gpTag == gpTag:
			return gpN
	return null
