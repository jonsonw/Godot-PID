class_name GPPdfExporter
extends RefCounted
# Copyright © 2026 Jonson Wang
# Export a G-PID sheet to a single-page vector PDF, openable by any viewer or print shop.
# 把一张 G-PID 图纸导出为单页矢量 PDF，任何查看器与打印店都能打开。
#
# WHERE THE GEOMETRY COMES FROM / 几何从哪来：
# from GPPrintModel, and from NOWHERE ELSE — the same contract as the DXF writer. This file
# performs ZERO geometry: it translates entities into PDF syntax and flips Y once here.
# 来自 GPPrintModel，且**仅**来自它 —— 与 DXF 写出器同一契约。本文件**不做任何几何**：
# 只把实体翻译成 PDF 语法，并在此处翻转一次 Y 轴。
#
# TEXT / 文字：
# PDF has no text without a font, and headless Godot exposes no glyph outlines. So this
# writer EMBEDS a TrueType subset: the used characters' glyph IDs come from the TextServer,
# GPTtfSubset rebuilds a ~100 KB font around them, and the PDF wires it as a Type0/Identity-H
# font — 中文 stays selectable, searchable and resolution-independent. Y is flipped the same
# way geometry is: model Y-down, PDF Y-up.
# 没有字体就没有 PDF 文字，而 headless 的 Godot 不暴露字形轮廓。故本写出器**内嵌 TrueType
# 子集**：用到字符的字形 ID 取自 TextServer，GPTtfSubset 围绕它们重建 ~100 KB 的字体，
# PDF 以 Type0/Identity-H 接线 —— 中文保持可选中、可检索、与分辨率无关。Y 轴与几何同法
# 翻转：模型 Y 向下，PDF Y 向上。
#
# Dependency rule: io may reference core, never ui and never an autoload.
# 依赖规则：io 可引用 core，绝不引用 ui 与 autoload。

const GP_PT_PER_MM: float = 72.0 / 25.4

# Candidate CJK-capable SINGLE-font TTFs (a .ttc collection cannot be embedded as one
# FontFile2). First readable candidate wins; a settings-driven override arrives with the
# settings UI that needs it.
# 候选的**单体** TTF（.ttc 集合无法作为单个 FontFile2 内嵌）。第一个可读者胜出；
# 设置驱动的覆盖项随需要它的设置界面一起到来。
const GP_FONT_CANDIDATES: Array[String] = [
	"/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
]


# Convenience pipeline: load font -> project -> build -> write atomically.
# 便利流程：载字体 -> 投影 -> 组装 -> 原子落盘。
# [param gpCaption] title-block caption resolver (I18n-bound by the UI layer); absent =
# captions degrade to raw keys, exactly like the print model's own fallback.
# [param gpDefs] the library to project with; empty = the LIVE default library — the same
# convention gpExportLists and the DXF writer use, so a test can feed a synthetic library.
# [param gpFontPath] explicit source font; empty = GP_FONT_CANDIDATES (test seam).
# [param gpCaption] 图签字段名解析器（由界面层绑定 I18n）；缺省 = 字段名退化为裸键，
# 与打印模型自身的回退一致。
# [param gpDefs] 投影所用图元库；空 = **活动**默认库 —— 与 gpExportLists 及 DXF 写出器
# 同一约定，使测试可以喂合成的图元库。
# [param gpFontPath] 显式源字体；空 = GP_FONT_CANDIDATES（测试注入口）。
static func gpExportSheet(gpGraph: GPPIDGraph, gpSheet: GPSheet, gpPath: String,
		gpCaption: Callable = Callable(), gpDefs: Array[GPSymbolDef] = [],
		gpFontPath: String = "") -> GPIOResult:
	if gpSheet == null:
		return GPIOResult.gpFailure("pdf.no_sheet", "status.export_fail", gpPath)
	if gpPath.is_empty():
		return GPIOResult.gpFailure("io.write_failed", "status.export_fail", gpPath)
	var gpFont: Dictionary = gpLoadFont(gpFontPath)
	if not bool(gpFont["ok"]):
		return GPIOResult.gpFailure("pdf.no_font", "status.export_fail", gpPath)
	var gpLib: Array[GPSymbolDef] = gpDefs
	if gpLib.is_empty():
		gpLib = GPSymbolLibrary.gpDefaultDefs()
	var gpEntities: Array[Dictionary] = GPPrintModel.gpProject(gpSheet, gpLib, gpCaption)
	var gpBuilt: Dictionary = gpBuildPdf(gpEntities, gpSheet, gpFont)
	if not bool(gpBuilt["ok"]):
		return GPIOResult.gpFailure("pdf.no_font", "status.export_fail", gpPath)
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteBytesAtomic(
		gpPath, gpBuilt["bytes"] as PackedByteArray)
	if not gpWrite.gpIsOk():
		return GPIOResult.gpFailure("io.write_failed", "status.export_fail", gpPath)
	return GPIOResult.gpSuccessWith({"path": gpPath, "kind": "pdf",
		"entities": gpEntities.size(), "chars": int(gpBuilt["chars"])},
		"status.exported", gpPath)


# Resolve the source font: explicit path first, then the candidate table. The FontFile stays
# in the result dict — its RID dies with it, and glyph ids must outlive the build step.
# 解析源字体：显式路径优先，其后是候选表。FontFile 留在结果字典里 —— 它的 RID 随之而亡，
# 而字形 ID 必须活过整个组装步。
static func gpLoadFont(gpFontPath: String) -> Dictionary:
	var gpCands: Array[String] = []
	if gpFontPath != "":
		gpCands.append(gpFontPath)
	else:
		gpCands = GP_FONT_CANDIDATES
	for gpPath in gpCands:
		if not FileAccess.file_exists(gpPath):
			continue
		var gpBytes: PackedByteArray = FileAccess.get_file_as_bytes(gpPath)
		if gpBytes.size() < 100:
			continue
		var gpHead: Dictionary = GPTtfSubset.gpHeadInfo(gpBytes)
		if gpHead.is_empty() or int(gpHead["upem"]) == 0:
			continue
		var gpF: FontFile = FontFile.new()
		if gpF.load_dynamic_font(gpPath) != OK:
			continue
		var gpRids: Array[RID] = gpF.get_rids()
		if gpRids.is_empty():
			continue
		return {"ok": true, "path": gpPath, "bytes": gpBytes, "font": gpF, "rid": gpRids[0],
			"upem": int(gpHead["upem"]), "bbox": gpHead["bbox"],
			"ascent": int(gpHead["ascent"]), "descent": int(gpHead["descent"])}
	return {"ok": false}


# Build the complete PDF bytes from projected entities. PURE — no disk, no autoload.
# 由投影实体组装完整的 PDF 字节。**纯函数** —— 不碰磁盘、不碰 autoload。
# Returns {"ok": bool, "bytes": PackedByteArray, "chars": int, "texts": int, "err": String}.
static func gpBuildPdf(gpEntities: Array[Dictionary], gpSheet: GPSheet,
		gpFont: Dictionary) -> Dictionary:
	var gpFail: Dictionary = {"ok": false, "bytes": PackedByteArray(), "chars": 0,
		"texts": 0, "err": ""}
	if gpSheet == null or not bool(gpFont["ok"]):
		gpFail["err"] = "bad input"
		return gpFail
	var gpS: float = GP_PT_PER_MM
	var gpW: float = gpSheet.gpWidthMM * gpS
	var gpH: float = gpSheet.gpHeightMM * gpS
	var gpUpem: int = int(gpFont["upem"])
	var gpTs: TextServer = TextServerManager.get_primary_interface()
	var gpRid: RID = gpFont["rid"]

	# ---- 1) used characters -> source glyph ids + advances / 用字 -> 源字形 ID + 步进 ----
	var gpChars: Dictionary = {}   # codepoint -> {"gid": int, "adv": int (font units)}
	var gpSrcOrder: PackedInt32Array = PackedInt32Array([0])  # .notdef seeded
	for gpE in gpEntities:
		if str(gpE["op"]) != GPPrintModel.GP_OP_TEXT:
			continue
		var gpT: String = str(gpE["s"])
		for gpI in range(gpT.length()):
			var gpCp: int = gpT.unicode_at(gpI)
			if gpChars.has(gpCp):
				continue
			var gpGid: int = gpTs.font_get_glyph_index(gpRid, 16, gpCp, 0)
			gpChars[gpCp] = {"gid": gpGid,
				"adv": int(round(gpTs.font_get_glyph_advance(gpRid, gpUpem, gpGid).x))}
			if gpGid > 0 and not gpSrcOrder.has(gpGid):
				gpSrcOrder.append(gpGid)

	# ---- 2) subset the font / 字体子集化 ----
	var gpSub: Dictionary = GPTtfSubset.gpSubset(gpFont["bytes"] as PackedByteArray, gpSrcOrder)
	if not bool(gpSub["ok"]):
		gpFail["err"] = str(gpSub["err"])
		return gpFail
	var gpMap: Dictionary = gpSub["map"]   # src gid -> new gid (== CID under Identity-H)

	# ---- 3) W array + ToUnicode / W 数组 + ToUnicode ----
	var gpWEntries: String = ""
	var gpBf: String = ""
	var gpSeen: Dictionary = {}
	for gpCp: int in gpChars:
		var gpCid: int = int(gpMap.get(int((gpChars[gpCp] as Dictionary)["gid"]), 0))
		if gpSeen.has(gpCid):
			continue
		gpSeen[gpCid] = true
		var gpW1000: int = int(round(
			float((gpChars[gpCp] as Dictionary)["adv"]) * 1000.0 / float(gpUpem)))
		gpWEntries += str(gpCid) + " [" + str(gpW1000) + "] "
		gpBf += "<%04X> <%s>\n" % [gpCid, _gpU16Hex(gpCp)]

	# ---- 4) content stream / 内容流 ----
	# White page FIRST — a PDF page has no intrinsic background, and converters/printers
	# composite transparent pages unpredictably (sips went BLACK in testing).
	# 先铺白底 —— PDF 页面没有固有背景，转换器/打印设备对透明页的合成不可预期
	#（实测 sips 会合成成黑底）。
	var gpCs: String = "1 1 1 rg 0 0 " + _gpNum2(gpW) + " " + _gpNum2(gpH) + " re f 0 g\n"
	# Rev.3 stage 0d: the sheet is a movable object. The print model emits WORLD millimetres
	# (frame + content both carry gpPaperOrigin), while a PDF page is PAPER-sized at (0,0).
	# Translate the whole content stream by -origin once, in PDF points, so a moved sheet
	# prints exactly like an unmoved one. The white page above is deliberately OUTSIDE this
	# transform: it must cover the whole page, not the paper rectangle.
	# Rev.3 阶段 0d：图纸是可移动对象。打印模型输出**世界**毫米（图框与内容都带 gpPaperOrigin），
	# 而 PDF 页面是 (0,0) 起的**纸面**尺寸。故在 PDF 点坐标里把整条内容流平移 -origin 一次，
	# 使移动过的图纸与未移动的打印结果一致。上方白底刻意在变换**之外**：它要铺满整页，而非纸面矩形。
	var gpShift: Vector2 = gpPageShift(gpSheet)
	if gpShift != Vector2.ZERO:
		gpCs += "q 1 0 0 1 " + _gpNum2(gpShift.x) + " " + _gpNum2(gpShift.y) + " cm\n"
	var gpTexts: int = 0
	for gpE in gpEntities:
		var gpOp: String = str(gpE["op"])
		match gpOp:
			GPPrintModel.GP_OP_LINE:
				gpCs += _gpNum2(float(gpE["w"]) * gpS) + " w\n"
				gpCs += gpPt(gpE["a"], gpH, gpS) + " m " + gpPt(gpE["b"], gpH, gpS) + " l S\n"
			GPPrintModel.GP_OP_POLY:
				gpCs += _gpPolyOp(gpE, gpH, gpS)
			GPPrintModel.GP_OP_CIRCLE:
				gpCs += _gpCircleOp(gpE, gpH, gpS)
			GPPrintModel.GP_OP_TEXT:
				var gpChunk: Dictionary = _gpTextOp(gpE, gpH, gpS, gpChars, gpMap, gpUpem)
				if not gpChunk.is_empty():
					gpCs += str(gpChunk["cs"])
					gpTexts += 1
	# Close the page transform opened above (only when it was opened). A transform left open
	# is legal PDF, but closing it keeps the stream balanced and makes the intent explicit.
	# 关闭上方打开的页面变换（仅在确实打开时）。未关闭的变换在 PDF 中合法，但关闭它使流保持
	# 平衡、意图明确。
	if gpShift != Vector2.ZERO:
		gpCs += "Q\n"
	# Whitespace-only padding so a zero-length stream never appears.
	# 仅空白填充，避免出现零长流。
	if gpCs == "":
		gpCs = "\n"

	# ---- 5) assemble objects / 组装对象 ----
	# The body is built as an ASCII STRING (length == byte count) and the binary subset
	# stream is spliced in at exactly one place; offsets are string lengths + the font bytes
	# accumulated so far. NO value-type captures: a PackedByteArray captured by a lambda is a
	# CoW COPY, and appends inside the lambda would be lost.
	# 正文按 ASCII **字符串**累加（长度即字节数），二进制子集流只在唯一一处拼接；
	# 偏移 = 字符串长度 + 截至目前累计的字体字节。**绝不用值类型捕获**：
	# 被 lambda 捕获的 PackedByteArray 是 CoW 副本，闭包内的 append 会丢失。
	var gpHeaderLen: int = 15   # "%PDF-1.4\n" (9) + binary marker line (6)
	var gpBody: String = ""
	var gpOffsets: PackedInt64Array = PackedInt64Array()
	var gpExtra: int = 0        # bytes of the binary font stream spliced before this point
	var gpBase: String = _gpBaseName(str(gpFont["path"]))
	var gpBB: Array = gpFont["bbox"] as Array
	var gpK1000: float = 1000.0 / float(gpUpem)
	var gpSubBytes: PackedByteArray = gpSub["bytes"] as PackedByteArray

	gpOffsets.append(gpHeaderLen + gpBody.length() + gpExtra)
	gpBody += "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
	gpOffsets.append(gpHeaderLen + gpBody.length() + gpExtra)
	gpBody += "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
	gpOffsets.append(gpHeaderLen + gpBody.length() + gpExtra)
	gpBody += "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " + \
		_gpNum2(gpW) + " " + _gpNum2(gpH) + "]" + \
		" /Resources << /Font << /F1 4 0 R >> >> /Contents 9 0 R >>\nendobj\n"
	gpOffsets.append(gpHeaderLen + gpBody.length() + gpExtra)
	gpBody += "4 0 obj\n<< /Type /Font /Subtype /Type0 /BaseFont /" + gpBase + \
		" /Encoding /Identity-H /DescendantFonts [5 0 R] /ToUnicode 8 0 R >>\nendobj\n"
	gpOffsets.append(gpHeaderLen + gpBody.length() + gpExtra)
	gpBody += "5 0 obj\n<< /Type /Font /Subtype /CIDFontType2 /BaseFont /" + gpBase + \
		" /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>" + \
		" /FontDescriptor 6 0 R /W [" + gpWEntries + "] /CIDToGIDMap /Identity >>\nendobj\n"
	gpOffsets.append(gpHeaderLen + gpBody.length() + gpExtra)
	gpBody += "6 0 obj\n<< /Type /FontDescriptor /FontName /" + gpBase + \
		" /Flags 4 /FontBBox [" + _gpNum2(float(gpBB[0]) * gpK1000) + \
		" " + _gpNum2(float(gpBB[1]) * gpK1000) + \
		" " + _gpNum2(float(gpBB[2]) * gpK1000) + \
		" " + _gpNum2(float(gpBB[3]) * gpK1000) + "]" + \
		" /ItalicAngle 0 /Ascent " + _gpNum2(float(int(gpFont["ascent"])) * gpK1000) + \
		" /Descent " + _gpNum2(float(int(gpFont["descent"])) * gpK1000) + \
		" /CapHeight 700 /StemV 80 /FontFile2 7 0 R >>\nendobj\n"
	# Object 7: the ONE binary stream — its bytes go between two string halves.
	# 对象 7：唯一的二进制流 —— 其字节夹在前后两段字符串之间。
	gpOffsets.append(gpHeaderLen + gpBody.length() + gpExtra)
	gpBody += "7 0 obj\n<< /Length1 " + str(gpSubBytes.size()) + \
		" /Length " + str(gpSubBytes.size()) + " >>\nstream\n"
	var gpFontAt: int = gpBody.length()
	gpExtra += gpSubBytes.size()
	var gpCMap: String = "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n" + \
		"/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n" + \
		"/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n" + \
		"1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n" + \
		_gpBfBlocks(gpBf) + "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"
	gpBody += "\nendstream\nendobj\n"
	gpOffsets.append(gpHeaderLen + gpBody.length() + gpExtra)
	gpBody += "8 0 obj\n<< /Length " + str(gpCMap.to_utf8_buffer().size()) + \
		" >>\nstream\n" + gpCMap + "endstream\nendobj\n"
	gpOffsets.append(gpHeaderLen + gpBody.length() + gpExtra)
	gpBody += "9 0 obj\n<< /Length " + str(gpCs.to_utf8_buffer().size()) + \
		" >>\nstream\n" + gpCs + "endstream\nendobj\n"
	# ---- xref + trailer / 交叉引用 + 尾部 ----
	var gpXrefAt: int = gpHeaderLen + gpBody.length() + gpExtra
	gpBody += "xref\n0 " + str(gpOffsets.size() + 1) + "\n0000000000 65535 f \n"
	for gpO in gpOffsets:
		gpBody += "%010d 00000 n \n" % gpO
	gpBody += "trailer\n<< /Size " + str(gpOffsets.size() + 1) + \
		" /Root 1 0 R >>\nstartxref\n" + str(gpXrefAt) + "\n%%EOF\n"
	# ---- splice the font bytes in / 把字体字节拼接进去 ----
	var gpBytes: PackedByteArray = PackedByteArray()
	gpBytes.append_array(PackedByteArray([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A,
		0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]))
	var gpBodyB: PackedByteArray = gpBody.to_utf8_buffer()
	gpBytes.append_array(gpBodyB.slice(0, gpFontAt))
	gpBytes.append_array(gpSubBytes)
	gpBytes.append_array(gpBodyB.slice(gpFontAt))
	return {"ok": true, "bytes": gpBytes, "chars": gpChars.size(), "texts": gpTexts, "err": ""}


# ---------------------------------------------------------------------------
# content ops / 内容流算子
# ---------------------------------------------------------------------------

static func _gpPolyOp(gpE: Dictionary, gpH: float, gpS: float) -> String:
	var gpPts: PackedVector2Array = gpE["pts"] as PackedVector2Array
	if gpPts.size() < 2:
		return ""
	var gpOut: String = _gpNum2(float(gpE["w"]) * gpS) + " w\n"
	for gpI in range(gpPts.size()):
		gpOut += gpPt(gpPts[gpI], gpH, gpS) + (" m " if gpI == 0 else " l ")
	gpOut += ("h " if bool(gpE["closed"]) else "") + "S\n"
	return gpOut


# A circle as four Bézier arcs (k = 0.55228…), stroke only.
# 圆 = 四段贝塞尔（k = 0.55228…），仅描边。
static func _gpCircleOp(gpE: Dictionary, gpH: float, gpS: float) -> String:
	var gpC: Vector2 = gpE["c"] as Vector2
	var gpR: float = float(gpE["r"]) * gpS
	if gpR <= 0.0:
		return ""
	var gpK: float = gpR * 0.55228475
	var gpCx: float = gpC.x * gpS
	var gpCy: float = gpH - gpC.y * gpS
	var gpF: String = _gpNum2(float(gpE["w"]) * gpS) + " w\n"
	gpF += _gpNum2(gpCx) + " " + _gpNum2(gpCy + gpR) + " m\n"
	gpF += _gpNum2(gpCx + gpK) + " " + _gpNum2(gpCy + gpR) + " " + \
		_gpNum2(gpCx + gpR) + " " + _gpNum2(gpCy + gpK) + " " + \
		_gpNum2(gpCx + gpR) + " " + _gpNum2(gpCy) + " c\n"
	gpF += _gpNum2(gpCx + gpR) + " " + _gpNum2(gpCy - gpK) + " " + \
		_gpNum2(gpCx + gpK) + " " + _gpNum2(gpCy - gpR) + " " + \
		_gpNum2(gpCx) + " " + _gpNum2(gpCy - gpR) + " c\n"
	gpF += _gpNum2(gpCx - gpK) + " " + _gpNum2(gpCy - gpR) + " " + \
		_gpNum2(gpCx - gpR) + " " + _gpNum2(gpCy - gpK) + " " + \
		_gpNum2(gpCx - gpR) + " " + _gpNum2(gpCy) + " c\n"
	gpF += _gpNum2(gpCx - gpR) + " " + _gpNum2(gpCy + gpK) + " " + \
		_gpNum2(gpCx - gpK) + " " + _gpNum2(gpCy + gpR) + " " + \
		_gpNum2(gpCx) + " " + _gpNum2(gpCy + gpR) + " c h S\n"
	return gpF


# One text run: flip the middle-height reference down to a baseline, centre by the font's
# own advances, and emit the glyph-id hex string. An empty string emits nothing.
# One text run: resolve the horizontal alignment (left / centre / right), convert the model's
# vertical reference into a PDF baseline (middle = +0.35h, baseline = unchanged), and emit the
# glyph-id hex string. An empty string emits nothing.
# 一段文字：解析水平对齐（左 / 中 / 右），把模型的纵向基准换算成 PDF 基线（中高 = +0.35h，
# 基线 = 不变），再写出字形 ID 十六进制串。空字符串不产出。
static func _gpTextOp(gpE: Dictionary, gpH: float, gpS: float, gpChars: Dictionary,
		gpMap: Dictionary, gpUpem: int) -> Dictionary:
	var gpT: String = str(gpE["s"])
	if gpT == "":
		return {}
	var gpSz: float = float(gpE["h"]) * gpS
	var gpWidth: float = 0.0
	var gpHex: String = ""
	for gpI in range(gpT.length()):
		var gpCp: int = gpT.unicode_at(gpI)
		var gpInfo: Dictionary = gpChars[gpCp]
		gpWidth += float(int(gpInfo["adv"])) * gpSz / float(gpUpem)
		gpHex += "%04X" % int(gpMap.get(int(gpInfo["gid"]), 0))
	var gpX: float = (gpE["at"] as Vector2).x * gpS
	match str(gpE.get("align", "l")):
		"c":
			gpX -= gpWidth * 0.5
		"r":
			gpX -= gpWidth
	var gpY: float = (gpE["at"] as Vector2).y
	if str(gpE.get("valign", GPPrintModel.GP_VALIGN_BASELINE)) == GPPrintModel.GP_VALIGN_MIDDLE:
		gpY += float(gpE["h"]) * 0.35
	var gpBaseY: float = gpH - gpY * gpS
	return {"cs": "BT\n/F1 " + _gpNum2(gpSz) + " Tf\n" + \
		_gpNum2(gpX) + " " + _gpNum2(gpBaseY) + " Td\n<" + gpHex + "> Tj\nET\n"}


# ---------------------------------------------------------------------------
# helpers / 辅助
# ---------------------------------------------------------------------------

# The page-space translation that cancels the sheet's world position, in PDF points.
# 抵消图纸世界位置的页面空间平移量（PDF 点）。
#
# WHY IT IS A FUNCTION, NOT AN INLINE EXPRESSION / 为何做成函数而非内联表达式：
# this is the one place where "the paper is at (x,y) in the world" meets "the PDF page starts
# at (0,0)". Pinning it directly (and using it for the content-stream `cm`) means a sign error
# cannot hide behind a symmetric fixture; the moved-sheet test asserts the numeric pair.
# 这是「纸在世界 (x,y)」与「PDF 页面从 (0,0) 起」相遇的唯一一处。直接钉住它（并让内容流的
# `cm` 使用它）使符号错误无法藏在对称夹具后面；移动图纸测试直接断言这对数值。
# [param gpSheet] the sheet whose paper origin is cancelled / 待抵消纸面原点的图纸
# [return] (tx, ty) in PDF points, to be applied as `1 0 0 1 tx ty cm`
static func gpPageShift(gpSheet: GPSheet) -> Vector2:
	if gpSheet == null:
		return Vector2.ZERO
	return Vector2(-gpSheet.gpPaperOrigin.x * GP_PT_PER_MM,
		gpSheet.gpPaperOrigin.y * GP_PT_PER_MM)


# One model point as "x y" in PDF space (mm -> pt, Y flipped).
# 一个模型点写成 PDF 空间的 "x y"（mm -> pt，Y 翻转）。
# PUBLIC (promoted): the flip is pinned at FUNCTION level — the sheet-symmetric frame leaves
# the coordinate SET unchanged, so only a direct assertion can catch its loss.
# **公开**（提升）：翻转在**函数级**被钉住 —— 相对图纸对称的图框不改变坐标**集合**，
# 故只有直接断言能抓住翻转丢失。
static func gpPt(gpP: Variant, gpH: float, gpS: float) -> String:
	var gpV: Vector2 = gpP as Vector2
	return _gpNum2(gpV.x * gpS) + " " + _gpNum2(gpH - gpV.y * gpS)


# Codepoint -> UTF-16BE hex (surrogate pair beyond the BMP).
# 码点 -> UTF-16BE 十六进制（BMP 之外用代理对）。
static func _gpU16Hex(gpCp: int) -> String:
	if gpCp > 0xFFFF:
		var gpV: int = gpCp - 0x10000
		return "%04X%04X" % [0xD800 + (gpV >> 10), 0xDC00 + (gpV & 0x3FF)]
	return "%04X" % gpCp


# Split bfchar lines into <=100-entry beginbfchar blocks.
# 把 bfchar 行拆为 ≤100 条的 beginbfchar 块。
static func _gpBfBlocks(gpBf: String) -> String:
	if gpBf == "":
		return "1 beginbfchar\n<0000> <0000>\nendbfchar\n"
	var gpLines: PackedStringArray = gpBf.split("\n", false)
	var gpOut: String = ""
	for gpStart in range(0, gpLines.size(), 100):
		var gpEnd: int = mini(gpStart + 100, gpLines.size())
		gpOut += str(gpEnd - gpStart) + " beginbfchar\n"
		for gpI in range(gpStart, gpEnd):
			gpOut += gpLines[gpI] + "\n"
		gpOut += "endbfchar\n"
	return gpOut


# BaseFont name from the font path: alphanumerics of the basename.
# 由字体路径取 BaseFont 名：文件名中的字母数字。
static func _gpBaseName(gpPath: String) -> String:
	var gpBase: String = gpPath.get_file().get_basename()
	var gpOut: String = ""
	for gpI in range(gpBase.length()):
		var gpC: String = gpBase[gpI]
		if (gpC >= "a" and gpC <= "z") or (gpC >= "A" and gpC <= "Z") \
				or (gpC >= "0" and gpC <= "9"):
			gpOut += gpC
	return gpOut if gpOut != "" else "Font"


static func _gpNum2(gpV: float) -> String:
	return "%.2f" % gpV
