# Copyright 2026 G-PID Contributors. MIT License. See LICENSE.
class_name GPAtlasExporter
extends RefCounted

# ATLAS (batch drawing-set) export — W13 T3 (S7b). Exports a WHOLE drawing set in one
# action: one PDF per sheet (looping over the EXISTING single-sheet exporter — there is
# no second copy of PDF logic here, the same "one blade" rule as GPSheetLifecycle) plus
# a CATALOG page (drawing index: number / title / file), then an honest per-sheet report
# with a measured elapsed time.
# 图册（整套图纸）导出 —— W13 T3（S7b）。一个动作导出**整套**图纸：每张一个 PDF（循环
# 调用**既有**单图导出器 —— 这里没有第二份 PDF 逻辑，与 GPSheetLifecycle 同一条「唯一
# 一把刀」规则），外加一页**目录页**（图号 / 图名 / 文件清单），最后给出带**实测耗时**
# 的逐图诚实报告。
#
# THE CATALOG IS NOT A SECOND PDF WRITER / 目录页不是第二个 PDF 写出器：
# the catalog page is a SYNTHETIC entity list (text ops + one rule line) in the print
# model's own op format, fed through the very same GPPdfExporter.gpBuildPdf. One geometry
# vocabulary, one writer.
# 目录页是**合成的**实体清单（文本算子 + 一条表格线），采用打印模型自身的算子格式，
# 走**同一个** GPPdfExporter.gpBuildPdf。一套几何词汇，一个写出器。
#
# Per-sheet failures NEVER abort the set: the loop continues, failures land in the
# payload, and the status line tells the whole truth.
# 单张失败**绝不**中断整套：循环继续，失败进 payload，状态行如实说全。
#
# Layer: io — may reference core only; the translator arrives as an injected Callable
# (the same rule as GPIOResult.gpText), so this file never touches an autoload.
# 分层：io —— 只可引用 core；翻译器以 Callable 注入（与 GPIOResult.gpText 同一规则），
# 本文件绝不触碰 autoload。

const GP_ERR_NO_SHEETS: String = "atlas.no_sheets"
const GP_ERR_DIR_FAIL: String = "atlas.dir_failed"

# Catalog pagination: rows per A4 page. Beyond this, an honest "… N more" line — a
# 50-sheet index squeezed onto one page is unreadable, and multi-page catalogs are a
# later need, not today's (YAGNI).
# 目录页分页：每页行数上限。超出后如实写「… 还有 N 张」—— 50 张的目录挤一页不可读，
# 而多页目录是以后的需求，不是今天的（YAGNI）。
const GP_MAX_ROWS: int = 35

const GP_CATALOG_FILE: String = "_index.pdf"


# Sanitize one sheet name into a filename fragment: path separators and OS-invalid
# characters collapse to "_"; an empty result degrades to "sheet".
# 把图纸名净化成文件名片段：路径分隔符与操作系统非法字符折叠为「_」；空结果退化为
# 「sheet」。
static func gpSafeName(gpTitle: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpTitle.length()):
		var gpC: String = gpTitle[gpI]
		if gpC == "/" or gpC == "\\" or gpC == ":" or gpC == "*" or gpC == "?" \
				or gpC == "\"" or gpC == "<" or gpC == ">" or gpC == "|" \
				or gpC.unicode_at(0) < 32:
			gpOut += "_"
		else:
			gpOut += gpC
	gpOut = gpOut.strip_edges()
	return gpOut if not gpOut.is_empty() else "sheet"


# Build the catalog-page entity list (PURE, testable). gpTexts carries the locale-bound
# strings: title, subtitle, col_no, col_number, col_name, col_file, more.
# 构建目录页实体清单（**纯函数**，可测）。gpTexts 携带已本地化的文案：
# title、subtitle、col_no、col_number、col_name、col_file、more。
static func gpCatalogEntities(gpRows: Array[Dictionary], gpTexts: Dictionary) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(105.0, 24.0),
		"s": str(gpTexts.get("title", "")), "h": 9.0, "align": "c"})
	gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(15.0, 34.0),
		"s": str(gpTexts.get("subtitle", "")), "h": 3.5, "align": "l"})
	# Column headers + the rule under them. / 列头 + 其下的表格线。
	gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(15.0, 44.0),
		"s": str(gpTexts.get("col_no", "")), "h": 3.5, "align": "l"})
	gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(30.0, 44.0),
		"s": str(gpTexts.get("col_number", "")), "h": 3.5, "align": "l"})
	gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(78.0, 44.0),
		"s": str(gpTexts.get("col_name", "")), "h": 3.5, "align": "l"})
	gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(150.0, 44.0),
		"s": str(gpTexts.get("col_file", "")), "h": 3.5, "align": "l"})
	gpOut.append({"op": GPPrintModel.GP_OP_LINE, "a": Vector2(15.0, 47.0),
		"b": Vector2(195.0, 47.0), "w": 0.6})
	var gpY: float = 54.0
	for gpI in range(mini(gpRows.size(), GP_MAX_ROWS)):
		var gpRow: Dictionary = gpRows[gpI]
		gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(15.0, gpY),
			"s": str(gpI + 1), "h": 3.2, "align": "l"})
		gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(30.0, gpY),
			"s": str(gpRow.get("number", "")), "h": 3.2, "align": "l"})
		gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(78.0, gpY),
			"s": str(gpRow.get("name", "")), "h": 3.2, "align": "l"})
		gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(150.0, gpY),
			"s": str(gpRow.get("file", "")), "h": 3.2, "align": "l"})
		gpY += 6.2
	if gpRows.size() > GP_MAX_ROWS:
		gpOut.append({"op": GPPrintModel.GP_OP_TEXT, "at": Vector2(15.0, gpY),
			"s": str(gpTexts.get("more", "")) % (gpRows.size() - GP_MAX_ROWS),
			"h": 3.2, "align": "l"})
	return gpOut


# Translate-through-injection: a live Callable wins, an empty one degrades to the
# English fallback (the catalog must never show a raw i18n key).
# 经注入翻译：Callable 可用则用之，空 Callable 退化为英文兜底（目录页绝不显示裸 i18n 键）。
static func _gpText(gpTr: Callable, gpKey: String, gpFallback: String) -> String:
	if gpTr.is_valid():
		return str(gpTr.call(gpKey))
	return gpFallback


# Export the whole set. See the class header for the contract.
# 导出整套图纸。契约见类头注释。
# [param gpTr] locale translator (Callable taking an i18n key); empty = English fallbacks.
# [param gpTr] 语言翻译器（接收 i18n 键的 Callable）；空 = 英文兜底。
static func gpExportAtlas(gpSheets: Array[GPSheet], gpDirPath: String,
		gpCaption: Callable = Callable(), gpDefs: Array[GPSymbolDef] = [],
		gpFontPath: String = "", gpTr: Callable = Callable()) -> GPIOResult:
	# 1) Validate: only REAL sheets count. / 校验：只有**真实**图纸算数。
	var gpValid: Array[GPSheet] = []
	for gpSheet in gpSheets:
		if gpSheet != null:
			gpValid.append(gpSheet)
	if gpValid.is_empty():
		return GPIOResult.gpFailure(GP_ERR_NO_SHEETS, "atlas.no_sheets", gpDirPath)
	if gpDirPath.is_empty():
		return GPIOResult.gpFailure(GP_ERR_DIR_FAIL, "atlas.dir_failed", gpDirPath)
	var gpStart: int = Time.get_ticks_usec()

	# 2) The target directory (created, not refused — an atlas usually lands in a NEW
	#    folder named after the project; DirAccess is io's own to call).
	#    目标目录（创建而非拒绝 —— 图册通常落进一个以工程名命名的新文件夹；
	#    DirAccess 本就归 io 调用）。
	var gpDirErr: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(gpDirPath))
	if gpDirErr != OK:
		return GPIOResult.gpFailure(GP_ERR_DIR_FAIL, "atlas.dir_failed", gpDirPath)

	# 3) Loop the EXISTING single-sheet exporter. / 循环**既有**单图导出器。
	var gpRows: Array[Dictionary] = []
	var gpFailed: Array[Dictionary] = []
	for gpI in range(gpValid.size()):
		var gpS: GPSheet = gpValid[gpI]
		var gpFile: String = "%03d_%s.pdf" % [gpI + 1, gpSafeName(gpS.gpName)]
		if gpS.gpGraph == null:
			gpFailed.append({"sheet": gpS.gpName, "file": gpFile, "code": "atlas.no_graph"})
			continue
		var gpRes: GPIOResult = GPPdfExporter.gpExportSheet(gpS.gpGraph, gpS,
			gpDirPath.path_join(gpFile), gpCaption, gpDefs, gpFontPath)
		if gpRes.gpOk:
			gpRows.append({"number": gpS.gpNumber, "name": gpS.gpName, "file": gpFile})
		else:
			gpFailed.append({"sheet": gpS.gpName, "file": gpFile,
				"code": gpRes.gpMessageKey})

	# 4) The catalog page — same builder, synthetic entities, A4 portrait.
	#    目录页 —— 同一组装器、合成实体、A4 竖版。
	var gpCatalogOk: bool = false
	if not gpRows.is_empty():
		var gpCat: GPSheet = GPSheet.new()
		gpCat.gpName = "Index"
		gpCat.gpWidthMM = 210.0
		gpCat.gpHeightMM = 297.0
		var gpStamp: String = Time.get_datetime_string_from_system().replace("T", " ")
		var gpTexts: Dictionary = {
			"title": _gpText(gpTr, "atlas.title", "Drawing Index"),
			"subtitle": "%s  ·  %s" % [_gpText(gpTr, "atlas.count", "%d sheet(s)")
				% gpRows.size(), gpStamp],
			"col_no": _gpText(gpTr, "atlas.col_no", "No."),
			"col_number": _gpText(gpTr, "atlas.col_number", "Drawing No."),
			"col_name": _gpText(gpTr, "atlas.col_name", "Title"),
			"col_file": _gpText(gpTr, "atlas.col_file", "File"),
			"more": _gpText(gpTr, "atlas.more", "... %d more sheet(s) not listed"),
		}
		var gpEntities: Array[Dictionary] = gpCatalogEntities(gpRows, gpTexts)
		var gpFont: Dictionary = GPPdfExporter.gpLoadFont(gpFontPath)
		if bool(gpFont["ok"]):
			var gpBuilt: Dictionary = GPPdfExporter.gpBuildPdf(gpEntities, gpCat, gpFont)
			if bool(gpBuilt["ok"]):
				var gpWrite: GPIOResult = GPAtomicFile.gpWriteBytesAtomic(
					gpDirPath.path_join(GP_CATALOG_FILE), gpBuilt["bytes"] as PackedByteArray)
				gpCatalogOk = gpWrite.gpOk

	# 5) The honest report. / 如实报告。
	var gpElapsed: int = Time.get_ticks_usec() - gpStart
	return GPIOResult.gpSuccessWith({
		"dir": gpDirPath, "count": gpRows.size(), "total": gpValid.size(),
		"failed": gpFailed, "rows": gpRows, "catalog_ok": gpCatalogOk,
		"elapsed_ms": int(gpElapsed / 1000.0),
	}, "status.atlas_done", gpDirPath)
