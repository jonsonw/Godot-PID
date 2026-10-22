class_name GPDxfExporter
extends RefCounted
# Copyright © 2026 Jonson Wang
# Export a G-PID sheet to a plain-text DXF R12 file, openable by any CAD.
# 把一张 G-PID 图纸导出为纯文本 DXF R12 文件，任何 CAD 可打开。
#
# WHERE THE GEOMETRY COMES FROM / 几何从哪来：
# from GPPrintModel, and from NOWHERE ELSE. This writer performs ZERO geometry — it maps
# entities to DXF syntax. A writer that recomputed a frame or a route would be the second
# copy of a judgment this project has watched drift too many times.
# 来自 GPPrintModel，且**仅**来自它。本写出器**不做任何几何** —— 只把实体映射为 DXF 语法。
# 写出器若自行重算图框或管线，就是本项目目睹过太多次分家的「同一判断的第二份副本」。
#
# WHY R12 / 为何是 R12：
# the oldest, smallest, most universally parsed dialect — QCAD, LibreCAD, AutoCAD and every
# converter read it. POLYLINE/VERTEX (not LWPOLYLINE, which is R13+); no BLOCKS section at
# all (v1 scope: entities only).
# 最老、最小、被解析得最广的方言 —— QCAD / LibreCAD / AutoCAD 与一切转换器都读它。
# 用 POLYLINE/VERTEX（LWPOLYLINE 是 R13+）；无 BLOCKS 段（v1 范围：仅实体）。
#
# Y AXIS / Y 轴：
# the model is Y-down (Godot); DXF is Y-up. The flip happens HERE, once (y' = H − y), and
# the extents in the header are computed from the FLIPPED points so no viewer zooms wrong.
# 模型为 Y 向下（Godot）；DXF 为 Y 向上。翻转在**此处**发生一次（y' = H − y），
# 头部范围由**翻转后**的点计算，使任何查看器缩放都不错位。
#
# TEXT ENCODING / 文字编码：
# R12 predates Unicode. Non-ASCII characters are written as the \U+XXXX escape AutoCAD
# defines, so 中文 captions survive every reader instead of dying as codepage mojibake.
# R12 早于 Unicode。非 ASCII 字符以 AutoCAD 定义的 \U+XXXX 转义写出，
# 使中文字段名在任何读取器中存活，而非死于代码页乱码。
#
# Dependency rule: io may reference core, never ui and never an autoload.
# 依赖规则：io 可引用 core，绝不引用 ui 与 autoload。

# DXF colour numbers per standard layer. Custom shape layers default to white (7).
# 标准图层的 DXF 颜色号。自定义图形层默认白色（7）。
const GP_LAYER_COLOURS: Dictionary = {
	GPPrintModel.GP_LAYER_FRAME: 7,
	GPPrintModel.GP_LAYER_PIPING: 5,
	GPPrintModel.GP_LAYER_EQUIPMENT: 3,
	GPPrintModel.GP_LAYER_ANNOTATION: 2,
}


# Convenience pipeline: project -> serialise -> write.
# 便利流程：投影 -> 序列化 -> 落盘。
# [param gpCaption] title-block caption resolver (I18n-bound by the UI layer); absent =
# captions degrade to raw keys, exactly like the print model's own fallback.
# [param gpDefs] the library to project with; empty = the LIVE default library — the same
# convention gpExportLists uses, so a test can feed a synthetic fixture library.
# [param gpCaption] 图签字段名解析器（由界面层绑定 I18n）；缺省 = 字段名退化为裸键，
# 与打印模型自身的回退一致。
# [param gpDefs] 投影所用图元库；空 = **活动**默认库 —— 与 gpExportLists 同一约定，
# 使测试可以喂合成的夹具库。
static func gpExportSheet(gpGraph: GPPIDGraph, gpSheet: GPSheet, gpPath: String,
		gpCaption: Callable = Callable(), gpDefs: Array[GPSymbolDef] = []) -> GPIOResult:
	if gpSheet == null:
		return GPIOResult.gpFailure("dxf.no_sheet", "status.export_fail", gpPath)
	if gpPath.is_empty():
		return GPIOResult.gpFailure("io.write_failed", "status.export_fail", gpPath)
	var gpLib: Array[GPSymbolDef] = gpDefs
	if gpLib.is_empty():
		gpLib = GPSymbolLibrary.gpDefaultDefs()
	var gpEntities: Array[Dictionary] = GPPrintModel.gpProject(gpSheet, gpLib, gpCaption)
	var gpStats: Dictionary = {"nodes": 0, "edges": 0}
	if gpGraph != null:
		gpStats["nodes"] = gpGraph.gpNodes.size()
		gpStats["edges"] = gpGraph.gpEdges.size()
	var gpText: String = gpWriteDxf(gpEntities, gpSheet)
	# An EMPTY entity list means an empty sheet — still a legal drawing; only a write
	# failure is a failure. / 空实体列表意味着空图纸 —— 仍是合法图纸；只有写出失败才算失败。
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteAtomic(gpPath, gpText)
	if not gpWrite.gpIsOk():
		return GPIOResult.gpFailure("io.write_failed", "status.export_fail", gpPath)
	gpStats["path"] = gpPath
	gpStats["kind"] = "dxf"
	return GPIOResult.gpSuccessWith(gpStats, "status.exported", gpPath)


# ---------------------------------------------------------------------------
# serialisation / 序列化
# ---------------------------------------------------------------------------

# Group-code pairs are emitted as two lines (code \n value) — the DXF way.
# 组码对以两行写出（码 \n 值）—— DXF 的方式。
static func gpWriteDxf(gpEntities: Array[Dictionary], gpSheet: GPSheet) -> String:
	var gpH: float = gpSheet.gpHeightMM if gpSheet != null else 0.0
	var gpOut: String = ""
	gpOut += _gpPair(0, "SECTION") + _gpPair(2, "HEADER")
	gpOut += _gpPair(9, "$ACADVER") + _gpPair(1, "AC1009")
	var gpBBox: Rect2 = _gpFlippedBounds(gpEntities, gpH)
	if gpBBox.size.x > 0.0:
		gpOut += _gpPair(9, "$EXTMIN") + _gpPair(10, _gpNum(gpBBox.position.x)) \
			+ _gpPair(20, _gpNum(gpBBox.position.y)) + _gpPair(30, "0.0")
		gpOut += _gpPair(9, "$EXTMAX") + _gpPair(10, _gpNum(gpBBox.end.x)) \
			+ _gpPair(20, _gpNum(gpBBox.end.y)) + _gpPair(30, "0.0")
	gpOut += _gpPair(0, "ENDSEC")
	gpOut += _gpLayersSection(gpEntities)
	gpOut += _gpPair(0, "SECTION") + _gpPair(2, "ENTITIES")
	for gpE in gpEntities:
		gpOut += _gpEntity(gpE, gpH)
	gpOut += _gpPair(0, "ENDSEC")
	gpOut += _gpPair(0, "EOF")
	return gpOut


static func _gpLayersSection(gpEntities: Array[Dictionary]) -> String:
	var gpNames: Array[String] = []
	for gpE in gpEntities:
		var gpL: String = str(gpE["layer"])
		if not gpNames.has(gpL):
			gpNames.append(gpL)
	gpNames.sort()
	var gpOut: String = _gpPair(0, "SECTION") + _gpPair(2, "TABLES")
	gpOut += _gpPair(0, "TABLE") + _gpPair(2, "LAYER") + _gpPair(70, str(gpNames.size()))
	for gpN in gpNames:
		gpOut += _gpPair(0, "LAYER") + _gpPair(2, gpN) \
			+ _gpPair(70, "0") + _gpPair(62, str(_gpColourOf(gpN))) + _gpPair(6, "CONTINUOUS")
	gpOut += _gpPair(0, "ENDTAB") + _gpPair(0, "ENDSEC")
	return gpOut


static func _gpEntity(gpE: Dictionary, gpH: float) -> String:
	match str(gpE["op"]):
		GPPrintModel.GP_OP_LINE:
			return _gpLine(gpE, gpH)
		GPPrintModel.GP_OP_POLY:
			return _gpPolyline(gpE, gpH)
		GPPrintModel.GP_OP_CIRCLE:
			return _gpCircle(gpE, gpH)
		GPPrintModel.GP_OP_TEXT:
			return _gpText(gpE, gpH)
	return ""


static func _gpLine(gpE: Dictionary, gpH: float) -> String:
	var gpA: Vector2 = gpFlipY(gpE["a"], gpH)
	var gpB: Vector2 = gpFlipY(gpE["b"], gpH)
	return _gpPair(0, "LINE") + _gpPair(8, str(gpE["layer"])) \
		+ _gpPair(10, _gpNum(gpA.x)) + _gpPair(20, _gpNum(gpA.y)) + _gpPair(30, "0.0") \
		+ _gpPair(11, _gpNum(gpB.x)) + _gpPair(21, _gpNum(gpB.y)) + _gpPair(31, "0.0")


static func _gpPolyline(gpE: Dictionary, gpH: float) -> String:
	var gpPts: PackedVector2Array = gpE["pts"] as PackedVector2Array
	if gpPts.size() < 2:
		return ""
	var gpOut: String = _gpPair(0, "POLYLINE") + _gpPair(8, str(gpE["layer"])) \
		+ _gpPair(66, "1") + _gpPair(70, "1" if bool(gpE["closed"]) else "0")
	for gpP in gpPts:
		var gpF: Vector2 = gpFlipY(gpP, gpH)
		gpOut += _gpPair(0, "VERTEX") + _gpPair(8, str(gpE["layer"])) \
			+ _gpPair(10, _gpNum(gpF.x)) + _gpPair(20, _gpNum(gpF.y)) + _gpPair(30, "0.0")
	gpOut += _gpPair(0, "SEQEND") + _gpPair(8, str(gpE["layer"]))
	return gpOut


static func _gpCircle(gpE: Dictionary, gpH: float) -> String:
	var gpC: Vector2 = gpFlipY(gpE["c"], gpH)
	return _gpPair(0, "CIRCLE") + _gpPair(8, str(gpE["layer"])) \
		+ _gpPair(10, _gpNum(gpC.x)) + _gpPair(20, _gpNum(gpC.y)) + _gpPair(30, "0.0") \
		+ _gpPair(40, _gpNum(float(gpE["r"])))


# A text with a non-default horizontal or vertical alignment uses DXF's alignment-point form:
# 72 (0=left, 1=centre, 2=right) and 73 (0=baseline, 1=bottom, 2=middle, 3=top), with the
# alignment point in 11/21/31. A plain left-baseline text keeps the historic insertion point.
# 非默认水平/纵向对齐的文字用 DXF 的对齐点形式：72（0=左、1=中、2=右）与 73（0=基线、
# 1=底、2=中、3=顶），对齐点写在 11/21/31。左对齐+基线仍用历史插入点。
static func _gpText(gpE: Dictionary, gpH: float) -> String:
	var gpAt: Vector2 = gpFlipY(gpE["at"], gpH)
	var gpHCode: int = 0
	match str(gpE.get("align", "l")):
		"c":
			gpHCode = 1
		"r":
			gpHCode = 2
	var gpVCode: int = 0
	if str(gpE.get("valign", GPPrintModel.GP_VALIGN_BASELINE)) == GPPrintModel.GP_VALIGN_MIDDLE:
		gpVCode = 2
	var gpOut: String = _gpPair(0, "TEXT") + _gpPair(8, str(gpE["layer"])) \
		+ _gpPair(10, _gpNum(gpAt.x)) + _gpPair(20, _gpNum(gpAt.y)) + _gpPair(30, "0.0") \
		+ _gpPair(40, _gpNum(float(gpE["h"]))) \
		+ _gpPair(1, gpDxfText(str(gpE["s"])))
	if gpHCode != 0 or gpVCode != 0:
		gpOut += _gpPair(72, str(gpHCode)) + _gpPair(73, str(gpVCode)) \
			+ _gpPair(11, _gpNum(gpAt.x)) + _gpPair(21, _gpNum(gpAt.y)) + _gpPair(31, "0.0")
	return gpOut


# ---------------------------------------------------------------------------
# helpers / 辅助
# ---------------------------------------------------------------------------

# Flip one Y-down model point into the DXF Y-up sheet frame.
# PUBLIC (promoted): the flip is pinned at FUNCTION level — a sheet-symmetric fixture
# leaves the coordinate SET unchanged, so only this direct assertion can catch its loss.
# 把一个 Y 向下的模型点翻进 DXF Y 向上的图纸坐标系。
# **公开**（提升）：翻转在**函数级**被钉住 —— 相对图纸对称的夹具不改变坐标**集合**，
# 故只有这条直接断言能抓住翻转丢失。
static func gpFlipY(gpP: Variant, gpH: float) -> Vector2:
	return Vector2((gpP as Vector2).x, gpH - (gpP as Vector2).y)


# Extents of the FLIPPED entities, guarded against an empty list (no extents at all).
# **翻转后**实体的范围，对空列表设护栏（此时根本没有范围）。
static func _gpFlippedBounds(gpEntities: Array[Dictionary], gpH: float) -> Rect2:
	var gpMin := Vector2(INF, INF)
	var gpMax := -Vector2(INF, INF)
	for gpE in gpEntities:
		var gpPts: Array[Vector2] = []
		match str(gpE["op"]):
			GPPrintModel.GP_OP_LINE:
				gpPts = [gpE["a"], gpE["b"]]
			GPPrintModel.GP_OP_POLY:
				for gpP in (gpE["pts"] as PackedVector2Array):
					gpPts.append(gpP)
			GPPrintModel.GP_OP_CIRCLE:
				var gpC: Vector2 = gpE["c"]
				var gpR: float = float(gpE["r"])
				gpPts = [gpC + Vector2(-gpR, -gpR), gpC + Vector2(gpR, gpR)]
			GPPrintModel.GP_OP_TEXT:
				gpPts = [gpE["at"]]
		for gpP in gpPts:
			var gpF: Vector2 = gpFlipY(gpP, gpH)
			gpMin = gpMin.min(gpF)
			gpMax = gpMax.max(gpF)
	if gpMin.x > gpMax.x:
		return Rect2()
	return Rect2(gpMin, gpMax - gpMin)


static func _gpColourOf(gpLayer: String) -> int:
	return int(GP_LAYER_COLOURS.get(gpLayer, 7))


# One group-code pair as the two lines DXF requires.
# 按 DXF 要求把一组组码写成两行。
static func _gpPair(gpCode: int, gpVal: String) -> String:
	return str(gpCode) + "\n" + gpVal + "\n"


# Millimetre coordinate formatting: plain decimal, no exponent — every CAD reads it.
# 毫米坐标格式：朴素小数、无指数 —— 任何 CAD 都读。
static func _gpNum(gpV: float) -> String:
	return "%.4f" % gpV


# Escape non-ASCII as AutoCAD's \U+XXXX so R12 readers keep 中文 intact.
# PUBLIC (promoted): the tests assert the escaping directly.
# 非 ASCII 以 AutoCAD 的 \U+XXXX 转义，使 R12 读取器保住中文。
# **公开**（提升）：测试直接断言该转义。
static func gpDxfText(gpS: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpS.length()):
		var gpC: String = gpS[gpI]
		if gpC.unicode_at(0) > 126:
			gpOut += "\\U+%04X" % gpC.unicode_at(0)
		else:
			gpOut += gpC
	return gpOut
