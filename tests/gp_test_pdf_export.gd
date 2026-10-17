extends "res://tests/gp_test.gd"
# PDF export: the file must be a structurally valid single-page PDF whose geometry is the
# print model's own, whose text is embedded as a SUBSET font (Identity-H glyph ids, not the
# 23 MB system font), and whose Y flip is pinned at function level.
# PDF 导出：文件必须是结构合法的单页 PDF，几何即打印模型自身的，文字以**子集字体**内嵌
#（Identity-H 字形 ID，而非 23 MB 系统字体），Y 翻转在函数级被钉住。


# The same synthetic fixture as the DXF suite: one square glyph + ports, two nodes, one pipe.
# 与 DXF 套件同一份合成夹具：一个正方形字形 + 端口，两个节点、一根管线。
static func _gpDefs() -> Array[GPSymbolDef]:
	var d := GPSymbolDef.new()
	d.gpId = "GTEST001"
	d.gpCategory = "pump"
	d.gpDisplayName = "GTEST001"
	var gpSq: Array[Vector2] = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	d.gpShapes.append(GPShape.gpPolyline(gpSq, true))
	d.gpDefaultSize = Vector2(50.0, 50.0)
	d.gpPorts.append(GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE))
	d.gpPorts.append(GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE))
	var gpOut: Array[GPSymbolDef] = [d]
	return gpOut


static func _gpSheet() -> GPSheet:
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpName = "PDF Sheet"
	gpSheet.gpWidthMM = 420.0
	gpSheet.gpHeightMM = 297.0
	gpSheet.gpGraph = _gpGraph()
	return gpSheet


static func _gpGraph() -> GPPIDGraph:
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	var gpPump: GPPIDNode = gpGraph.gpNewNode("n1", "GTEST001", "P-1001", Vector2(100.0, 80.0))
	gpGraph.gpAddNode(gpPump)
	var gpPump2: GPPIDNode = gpGraph.gpNewNode("n2", "GTEST001", "P-1002", Vector2(300.0, 200.0))
	gpGraph.gpAddNode(gpPump2)
	var gpEdge: GPPIDEdge = GPPIDEdge.new()
	gpEdge.gpInstanceId = "e1"
	gpEdge.gpFromRef = {"node_id": "n1", "port_id": "out"}
	gpEdge.gpToRef = {"node_id": "n2", "port_id": "in"}
	gpGraph.gpEdges.append(gpEdge)
	return gpGraph


static func _gpRead(gpPath: String) -> String:
	return FileAccess.get_file_as_string(gpPath)


# Byte-safe search (the embedded font stream is NOT valid UTF-8).
# 字节安全搜索（内嵌字体流**不是**合法 UTF-8）。
static func _gpFind(gpB: PackedByteArray, gpNeedle: String, gpFrom: int = 0) -> int:
	var gpN: PackedByteArray = gpNeedle.to_ascii_buffer()
	for gpI in range(gpFrom, gpB.size() - gpN.size() + 1):
		var gpHit: bool = true
		for gpJ in range(gpN.size()):
			if gpB[gpI + gpJ] != gpN[gpJ]:
				gpHit = false
				break
		if gpHit:
			return gpI
	return -1


# ---- registry path end to end / 经注册表端到端 ----

func gpTestExportThroughTheRegistryProducesAValidPdf() -> void:
	var gpPath: String = "user://_gp_pdf_test.pdf"
	var gpResult: GPIOResult = GPExporterRegistry.gpExport(GPExporterRegistry.GP_PDF, gpPath,
		_gpGraph(), [], _gpSheet())
	gpCheck(gpResult.gpIsOk(), "the registry wrote the file: " + gpResult.gpToString())
	var gpStats: Dictionary = gpResult.gpPayload as Dictionary
	gpEq(str(gpStats.get("kind", "")), "pdf", "the payload names its kind")
	var gpB: PackedByteArray = FileAccess.get_file_as_bytes(gpPath)
	gpCheck(gpB.size() > 400, "the file carries real content")
	gpCheck(_gpFind(gpB, "%PDF-1.4") == 0, "starts with the PDF header")
	gpCheck(_gpFind(gpB, "/Type0") > 0 and _gpFind(gpB, "/Identity-H") > 0,
		"the text font is a Type0 Identity-H font")
	gpCheck(_gpFind(gpB, "/FontFile2") > 0, "a TrueType subset is embedded")
	gpCheck(_gpFind(gpB, "/ToUnicode") > 0 and _gpFind(gpB, "beginbfchar") > 0,
		"a ToUnicode map keeps the text searchable")
	gpCheck(_gpFind(gpB, "/W [") > 0, "glyph widths are declared")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))


func gpTestMediaBoxIsTheSheetInPoints() -> void:
	# 420 x 297 mm -> pt at 72/25.4. / 420 x 297 mm 按 72/25.4 折算为 pt。
	var gpPath: String = "user://_gp_pdf_mediabox.pdf"
	gpCheck(GPExporterRegistry.gpExport(GPExporterRegistry.GP_PDF, gpPath, _gpGraph(), [],
		_gpSheet()).gpIsOk(), "the export succeeded")
	var gpText: String = _gpRead(gpPath)
	gpCheck(gpText.find("/MediaBox [0 0 1190.55 841.89]") >= 0,
		"the MediaBox is the sheet size in points")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))


func gpTestTextIsGlyphIdsNotRawBytes() -> void:
	# The tag P-1001 must appear as a hex glyph-id string inside BT/ET, never as ASCII.
	# 位号 P-1001 必须以 BT/ET 内的十六进制字形 ID 串出现，绝不能是裸 ASCII。
	var gpPath: String = "user://_gp_pdf_text.pdf"
	var gpResult: GPIOResult = GPPdfExporter.gpExportSheet(_gpGraph(), _gpSheet(), gpPath,
		Callable(), _gpDefs())
	gpCheck(gpResult.gpIsOk(), "the direct export wrote the file: " + gpResult.gpToString())
	var gpB: PackedByteArray = FileAccess.get_file_as_bytes(gpPath)
	var gpBt: int = _gpFind(gpB, "BT\n")
	gpCheck(gpBt > 0, "a text object exists")
	var gpEt: int = _gpFind(gpB, "ET\n", gpBt)
	gpCheck(gpEt > gpBt, "the text object closes")
	var gpTj: int = _gpFind(gpB, "> Tj", gpBt)
	gpCheck(gpTj > gpBt and gpTj < gpEt, "the run ends with a hex Tj")
	gpCheck(_gpFind(gpB, "P-1001") < 0, "raw tag ASCII is NOT in the file")
	var gpStats: Dictionary = gpResult.gpPayload as Dictionary
	gpCheck(int(gpStats.get("chars", 0)) >= 6, "P-1001 contributed its characters")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))


func gpTestChineseValueSurvivesViaToUnicode() -> void:
	var gpSheet := _gpSheet()
	gpSheet.gpTitleBlock["drawing_title"] = {"value": {"zh": "解毒", "en": "Detox"}}
	var gpPath: String = "user://_gp_pdf_cjk.pdf"
	gpCheck(GPPdfExporter.gpExportSheet(_gpGraph(), gpSheet, gpPath, Callable(),
		_gpDefs()).gpIsOk(), "the export succeeded")
	# BYTE search: the embedded font stream is not UTF-8, and get_file_as_string's
	# replacement decoding can swallow the ASCII that follows a stray lead byte.
	# **字节级**搜索：内嵌字体流不是 UTF-8，get_file_as_string 的替换解码
	# 会把紧随某个孤立前导字节之后的 ASCII 一并吞掉。
	var gpB: PackedByteArray = FileAccess.get_file_as_bytes(gpPath)
	# 解 = U+89E3, 毒 = U+6BD2 — the ToUnicode bfchar rows must name them.
	# 解 = U+89E3、毒 = U+6BD2 —— ToUnicode 的 bfchar 行必须指名它们。
	gpCheck(_gpFind(gpB, "<89E3>") >= 0 and _gpFind(gpB, "<6BD2>") >= 0,
		"the CJK codepoints appear in the ToUnicode map")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath))


func gpTestPointFlipIsPinnedAtFunctionLevel() -> void:
	# 20 mm above the bottom edge of a 297 mm sheet, in points.
	# 297 mm 图纸底边上方 20mm，折算为 pt。
	var gpS: float = GPPdfExporter.GP_PT_PER_MM
	gpEq(GPPdfExporter.gpPt(Vector2(10.0, 20.0), 297.0 * gpS, gpS), "28.35 785.20",
		"y' = H_pt - y_mm*s, x scaled only")


# ---- subsetter / 子集化器 ----

func gpTestSubsetterShrinksAndRenumbers() -> void:
	var gpFontPath: String = GPPdfExporter.GP_FONT_CANDIDATES[0]
	if not FileAccess.file_exists(gpFontPath):
		gpCheck(true, "no source font on this machine; subset unit check is vacuous")
		return
	var gpBytes: PackedByteArray = FileAccess.get_file_as_bytes(gpFontPath)
	var gpTs: TextServer = TextServerManager.get_primary_interface()
	var gpF: FontFile = FontFile.new()
	gpF.load_dynamic_font(gpFontPath)
	var gpRid: RID = gpF.get_rids()[0]
	var gpGids: PackedInt32Array = PackedInt32Array()
	for gpCp in ["P".unicode_at(0), "1".unicode_at(0), "解".unicode_at(0)]:
		gpGids.append(gpTs.font_get_glyph_index(gpRid, 16, gpCp, 0))
	var gpSub: Dictionary = GPTtfSubset.gpSubset(gpBytes, gpGids)
	gpCheck(bool(gpSub["ok"]), "the subset succeeded: " + str(gpSub["err"]))
	var gpMap: Dictionary = gpSub["map"]
	# >= 4: the three requested glyphs + .notdef — a COMPOSITE request may pull its
	# components in, so the exact count is not pinned.
	# >= 4：三个请求字形 + .notdef —— **复合字形**请求会自动拉入构件，故不钉死总数。
	gpCheck(gpMap.size() >= 4, "three glyphs + .notdef (composites may add more): "
		+ str(gpMap.size()))
	for gpG in gpGids:
		gpCheck(gpMap.has(gpG), "source gid " + str(gpG) + " is mapped")
	gpEq(int(gpMap[0]), 0, ".notdef stays at zero")
	# New ids are consecutive and the subset is far smaller than the 23 MB source.
	# 新 ID 连续，且子集远小于 23 MB 的源字体。
	var gpSeen: Array = []
	for gpK: int in gpMap:
		gpSeen.append(int(gpMap[gpK]))
	gpSeen.sort()
	for gpI in range(gpSeen.size()):
		gpEq(int(gpSeen[gpI]), gpI, "new glyph ids are consecutive")
	var gpSubBytes: PackedByteArray = gpSub["bytes"] as PackedByteArray
	gpCheck(gpSubBytes.size() < gpBytes.size() / 10,
		"the subset is under a tenth of the source")
	var gpHead: Dictionary = GPTtfSubset.gpHeadInfo(gpSubBytes)
	gpCheck(not gpHead.is_empty(), "the subset re-parses as a font")
	gpEq(int(gpHead["upem"]), int(GPTtfSubset.gpHeadInfo(gpBytes)["upem"]),
		"units per em survives the rebuild")


# ---- refusals / 拒绝 ----

func gpTestWithoutASheetIsRefused() -> void:
	var gpResult: GPIOResult = GPExporterRegistry.gpExport(GPExporterRegistry.GP_PDF,
		"user://_gp_pdf_nosheet.pdf", _gpGraph(), [], null)
	gpCheck(not gpResult.gpIsOk(), "PDF cannot project without a sheet")
	gpCheck(gpResult.gpFailedWith("pdf.no_sheet"), "and says which prerequisite is missing")


func gpTestUnknownFontIsRefused() -> void:
	var gpResult: GPIOResult = GPPdfExporter.gpExportSheet(_gpGraph(), _gpSheet(),
		"user://_gp_pdf_nofont.pdf", Callable(), _gpDefs(), "/nonexistent/font.ttf")
	gpCheck(not gpResult.gpIsOk(), "no source font means no export")
	gpCheck(gpResult.gpFailedWith("pdf.no_font"), "and names the missing font")


func gpTestEmptyPathIsRefused() -> void:
	gpCheck(not GPExporterRegistry.gpExport(GPExporterRegistry.GP_PDF, "", _gpGraph(), [],
		_gpSheet()).gpIsOk(), "no path means no export")


func gpTestFinishNameAppendsPdfOnce() -> void:
	gpEq(GPExporterRegistry.gpFinishName("/a/W6", "pdf"), "/a/W6.pdf",
		"a bare name gains the extension once")
	gpEq(GPExporterRegistry.gpFinishName("/a/W6.pdf", "pdf"), "/a/W6.pdf",
		"a complete name is untouched")
