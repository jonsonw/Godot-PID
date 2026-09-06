class_name GPShapeSpec
extends RefCounted

# Copyright © 2026 Jonson Wang
# Bidirectional conversion between the unified Array[GPShape] model and the legacy
# {paths,circles,rects,box} render spec. Centralized so the symbol editor, the main canvas,
# the normalizer and the pack builder all agree on one mapping.
# 统一模型 Array[GPShape] 与历史 {paths,circles,rects,box} 渲染规格之间的双向转换。
# 集中于此，使图元编辑器、主画布、归一化器与图元包构建器共用同一映射。

# Build the legacy render spec from a list of GPShape primitives.
# 由 GPShape 原语列表构建历史渲染规格。
# "box" is the union bounding box of every primitive (what the painter centers on).
# "box" 为所有原语的包围盒并集（渲染器据此居中）。
static func gpBuild(gpShapes: Array[GPShape]) -> Dictionary:
	var gpPaths: Array = []
	var gpCircles: Array = []
	var gpRects: Array = []
	var gpArcs: Array = []
	var gpHas: bool = false
	var gpMin := Vector2(INF, INF)
	var gpMax := Vector2(-INF, -INF)
	for gpS in gpShapes:
		var gpB: Rect2 = gpS.gpBBox()
		if gpB.size.x > 0.0 or gpB.size.y > 0.0:
			gpMin = gpMin.min(gpB.position)
			gpMax = gpMax.max(gpB.position + gpB.size)
			gpHas = true
		match gpS.gpKind:
			GPShape.GPKind.GP_CIRCLE:
				if gpS.gpPoints.size() >= 1:
					gpCircles.append({"c": [gpS.gpPoints[0].x, gpS.gpPoints[0].y], "r": gpS.gpRadius})
			GPShape.GPKind.GP_RECT:
				if gpS.gpPoints.size() >= 2:
					var gpA: Vector2 = gpS.gpPoints[0]
					var gpBp: Vector2 = gpS.gpPoints[1]
					var gpPos: Vector2 = Vector2(minf(gpA.x, gpBp.x), minf(gpA.y, gpBp.y))
					var gpSz: Vector2 = Vector2(absf(gpBp.x - gpA.x), absf(gpBp.y - gpA.y))
					gpRects.append({"pos": [gpPos.x, gpPos.y], "size": [gpSz.x, gpSz.y]})
			GPShape.GPKind.GP_ARC:
				# Store center + radius + sweep angles so the arc edits faithfully (grips change
				# radius + sweep) instead of being flattened to a sampled polyline.
				# 存圆心 + 半径 + 扫掠角，使弧可被忠实编辑（抓取点改变半径与扫掠），而非压平为采样折线。
				if gpS.gpPoints.size() >= 3 and gpS.gpRadius > 0.0:
					var gpAng: Dictionary = gpS.gpArcAngles()
					gpArcs.append({
						"c": [gpS.gpArcCenter().x, gpS.gpArcCenter().y],
						"r": gpS.gpRadius,
						"a0": gpAng["a0"],
						"a1": gpAng["a1"],
					})
			_:  # GP_LINE and GP_POLYLINE both render as polylines
				# GP_LINE 与 GP_POLYLINE 均以折线方式渲染。
				var gpPts: Array = []
				var gpN: int = gpS.gpPoints.size()
				for gpI in range(gpN):
					if gpI == 0:
						gpPts.append([gpS.gpPoints[0].x, gpS.gpPoints[0].y])
					var gpJ: int = gpI + 1
					if gpJ >= gpN:
						if gpS.gpClosed:
							gpJ = 0
						else:
							break
					# Sample this segment: a curved (handle-pulled) segment becomes several Bézier
					# samples, a straight one stays the two endpoints. The painter needs no Bézier logic.
					# 采样该段：被拉出手柄的曲线段变为若干贝塞尔采样点，直线段仍取两端点。渲染器无需懂贝塞尔。
					if _gpSegmentCurved(gpS, gpI):
						var gpCtrl: PackedVector2Array = gpS.gpSegmentControls(gpI)
						if gpCtrl.size() == 4:
							for gpT in range(1, 9):
								var gpU: float = float(gpT) / 8.0
								var gpBz: Vector2 = _gpCubic(gpCtrl[0], gpCtrl[1], gpCtrl[2], gpCtrl[3], gpU)
								gpPts.append([gpBz.x, gpBz.y])
					else:
						gpPts.append([gpS.gpPoints[gpJ].x, gpS.gpPoints[gpJ].y])
				gpPaths.append({"pts": gpPts, "closed": gpS.gpClosed})
	var gpBox: Array = []
	if gpHas:
		gpBox = [gpMin.x, gpMin.y, gpMax.x - gpMin.x, gpMax.y - gpMin.y]
	return {"paths": gpPaths, "circles": gpCircles, "rects": gpRects, "arcs": gpArcs, "box": gpBox}


# Lossless, *editable* spec: mirrors gpBuild's shape structure but emits raw polyline control
# points + Bézier handles (never flattens curves). It is the exact inverse of gpFromSpec (which
# calls gpRestoreHandles), so gpFromSpec(gpEditSpec(shapes)) reproduces the original editable
# GPShape[] — used by the "edit an existing symbol" dialog seed where curves must stay editable.
# Contrast gpBuild, which flattens curved polylines into sampled points for the painter.
# 无损、可编辑的规格：结构同 gpBuild，但折线输出「原始控制点 + 贝塞尔手柄」（绝不打平曲线）。它是
# gpFromSpec（内部调 gpRestoreHandles）的精确逆操作，故 gpFromSpec(gpEditSpec(shapes)) 能还原原始
# 可编辑的 GPShape[] —— 用于「编辑已有图元」对话框种子，曲线必须保持可编辑。区别于 gpBuild（为
# painter 把曲线折线打平成采样点）。
static func gpEditSpec(gpShapes: Array[GPShape]) -> Dictionary:
	var gpPaths: Array = []
	var gpCircles: Array = []
	var gpRects: Array = []
	var gpArcs: Array = []
	var gpHas: bool = false
	var gpMin := Vector2(INF, INF)
	var gpMax := Vector2(-INF, -INF)
	for gpS in gpShapes:
		var gpB: Rect2 = gpS.gpBBox()
		if gpB.size.x > 0.0 or gpB.size.y > 0.0:
			gpMin = gpMin.min(gpB.position)
			gpMax = gpMax.max(gpB.position + gpB.size)
			gpHas = true
		match gpS.gpKind:
			GPShape.GPKind.GP_CIRCLE:
				if gpS.gpPoints.size() >= 1:
					gpCircles.append({"c": [gpS.gpPoints[0].x, gpS.gpPoints[0].y], "r": gpS.gpRadius})
			GPShape.GPKind.GP_RECT:
				if gpS.gpPoints.size() >= 2:
					var gpA: Vector2 = gpS.gpPoints[0]
					var gpBp: Vector2 = gpS.gpPoints[1]
					var gpPos: Vector2 = Vector2(minf(gpA.x, gpBp.x), minf(gpA.y, gpBp.y))
					var gpSz: Vector2 = Vector2(absf(gpBp.x - gpA.x), absf(gpBp.y - gpA.y))
					gpRects.append({"pos": [gpPos.x, gpPos.y], "size": [gpSz.x, gpSz.y]})
			GPShape.GPKind.GP_ARC:
				if gpS.gpPoints.size() >= 3 and gpS.gpRadius > 0.0:
					var gpAng: Dictionary = gpS.gpArcAngles()
					gpArcs.append({
						"c": [gpS.gpArcCenter().x, gpS.gpArcCenter().y],
						"r": gpS.gpRadius,
						"a0": gpAng["a0"],
						"a1": gpAng["a1"],
					})
			_:  # GP_LINE / GP_POLYLINE: raw control points + handles (lossless, editable)
				# GP_LINE / GP_POLYLINE：原始控制点 + 手柄（无损、可编辑）。
				var gpPts: Array = []
				for gpP in gpS.gpPoints:
					gpPts.append([gpP.x, gpP.y])
				var gpPd: Dictionary = {"pts": gpPts, "closed": gpS.gpClosed}
				# Emit handles whenever any is pulled out (relative offsets, parallel to vertices).
				# 只要拉出任意手柄就输出（相对偏移，与顶点平行）。
				if gpS.gpHasCurve():
					gpPd["handles"] = gpEmitHandles(gpS)
				gpPaths.append(gpPd)
	var gpBox: Array = []
	if gpHas:
		gpBox = [gpMin.x, gpMin.y, gpMax.x - gpMin.x, gpMax.y - gpMin.y]
	return {"paths": gpPaths, "circles": gpCircles, "rects": gpRects, "arcs": gpArcs, "box": gpBox}


# Build GPShape primitives from the legacy {paths,circles,rects} spec.
# 由历史 {paths,circles,rects} 规格构建 GPShape 原语。
# A 2-point open path maps to GP_LINE; longer / closed paths map to GP_POLYLINE, so the
# conversion is lossless against gpBuild (a GP_LINE serializes back to a 2-point open path).
# 两点开放路径映射为 GP_LINE；更长或闭合路径映射为 GP_POLYLINE，故相对 gpBuild 无损
# （GP_LINE 会序列化回两点开放路径）。
static func gpFromSpec(gpSpec: Dictionary) -> Array[GPShape]:
	var gpOut: Array[GPShape] = []
	for gpP in gpSpec.get("paths", []):
		var gpPd: Dictionary = gpP as Dictionary
		var gpPts: Array = gpPd.get("pts", [])
		if gpPts.size() < 2:
			continue
		var gpVecs: Array[Vector2] = []
		for gpPt in gpPts:
			gpVecs.append(Vector2(float(gpPt[0]), float(gpPt[1])))
		var gpNew: GPShape
		if gpVecs.size() == 2 and not bool(gpPd.get("closed", false)):
			gpNew = GPShape.gpLine(gpVecs[0], gpVecs[1])
		else:
			gpNew = GPShape.gpPolyline(gpVecs, bool(gpPd.get("closed", false)))
		# Restore Bézier handles carried in the path dict (relative offsets, parallel to vertices)
		# so a curved spline survives promotion / save without being flattened back to straight ink.
		# 还原路径字典里携带的贝塞尔手柄（相对偏移，与顶点平行），使曲线样条经提升 / 保存后不被展平。
		gpRestoreHandles(gpNew, gpPd.get("handles", []))
		gpOut.append(gpNew)
	for gpC in gpSpec.get("circles", []):
		var gpCd: Dictionary = gpC as Dictionary
		gpOut.append(GPShape.gpCircle(Vector2(float(gpCd["c"][0]), float(gpCd["c"][1])), float(gpCd["r"])))
	for gpRd in gpSpec.get("rects", []):
		var gpRr: Dictionary = gpRd as Dictionary
		var gpPos: Vector2 = Vector2(float(gpRr["pos"][0]), float(gpRr["pos"][1]))
		var gpSz: Vector2 = Vector2(float(gpRr["size"][0]), float(gpRr["size"][1]))
		gpOut.append(GPShape.gpRect(gpPos, gpPos + gpSz))
	for gpAd in gpSpec.get("arcs", []):
		var gpA: Dictionary = gpAd as Dictionary
		var gpC: Vector2 = Vector2(float(gpA["c"][0]), float(gpA["c"][1]))
		var gpR: float = float(gpA["r"])
		var gpA0: float = float(gpA["a0"])
		var gpA1: float = float(gpA["a1"])
		var gpStart: Vector2 = gpC + Vector2(cos(gpA0), sin(gpA0)) * gpR
		var gpEnd: Vector2 = gpC + Vector2(cos(gpA1), sin(gpA1)) * gpR
		gpOut.append(GPShape.gpArc(gpC, gpStart, gpEnd))
	return gpOut


# Build GPShape primitives from an array of GPShape dicts (gpToDict output).
# 由 GPShape 字典数组（gpToDict 输出）构建 GPShape 原语。
static func gpFromDicts(gpArr: Array) -> Array[GPShape]:
	var gpOut: Array[GPShape] = []
	for gpD in gpArr:
		var gpS: GPShape = GPShape.new()
		gpS.gpFromDict(gpD as Dictionary)
		gpOut.append(gpS)
	return gpOut


# Whether the segment leaving vertex gpI is curved (vertex i has a pulled-out out-handle, or the
# next vertex has a pulled-out in-handle). Used to decide straight vs sampled rendering.
# 离开顶点 gpI 的段是否为曲线（顶点 i 出手柄被拉出，或下一顶点入手柄被拉出）。用于判定直线/采样渲染。
# Delegated to GPGeometry so the main canvas, the symbol editor and the symbol painter all share
# ONE Bézier implementation (see GPGeometry.gpSegmentCurved / gpCubic / gpRenderPoints).
# 委托给 GPGeometry，使主画布、符号编辑器与图元渲染器共用同一份贝塞尔实现
# （见 GPGeometry.gpSegmentCurved / gpCubic / gpRenderPoints）。
static func _gpSegmentCurved(gpS: GPShape, gpI: int) -> bool:
	return GPGeometry.gpSegmentCurved(gpS, gpI)


static func _gpCubic(gpP0: Vector2, gpC1: Vector2, gpC2: Vector2, gpP1: Vector2, gpU: float) -> Vector2:
	return GPGeometry.gpCubic(gpP0, gpC1, gpC2, gpP1, gpU)


# Emit the Bézier handle array for a line/polyline into the path-dict `"handles"` format
# `[[in.x, in.y], [out.x, out.y]]` per vertex (zero-offset placeholders included), so it survives
# promotion / save dict boundaries. Handles are RELATIVE offsets from each vertex, so translating
# the points (e.g. by the spec bbox origin) does not alter them and they pass through unchanged.
# 把线/折线的贝塞尔手柄数组输出为路径字典的 `"handles"` 格式 `[[inx,iny],[outx,outy]]`（逐顶点，
# 含零偏移占位），使其经提升 / 保存的字典边界而不丢失。手柄是「相对顶点的偏移」，故平移点
# （如按 spec 包围盒原点）不会改变它们，可原样透传。
static func gpEmitHandles(gpS: GPShape) -> Array:
	var gpOut: Array = []
	for gpI in range(gpS.gpPoints.size()):
		var gpIn: Vector2 = Vector2.ZERO
		var gpOutH: Vector2 = Vector2.ZERO
		if gpI < gpS.gpHandles.size() and gpS.gpHandles[gpI].size() >= 2:
			gpIn = gpS.gpHandles[gpI][0]
			gpOutH = gpS.gpHandles[gpI][1]
		gpOut.append([[gpIn.x, gpIn.y], [gpOutH.x, gpOutH.y]])
	return gpOut


# Restore Bézier handles onto a line/polyline from the path-dict `"handles"` array. Missing key or
# too-short input degrades gracefully to straight (corner) vertices — old files without handles stay
# flat, and a freshly-drawn flat polyline has no handles to restore.
# 从路径字典的 `"handles"` 数组还原线/折线的贝塞尔手柄。key 缺失或长度不足时优雅退化为直线（拐角）
# 顶点——无手柄的旧文件保持平直，新画的平直折线也没有手柄可还原。
static func gpRestoreHandles(gpS: GPShape, gpRaw: Array) -> void:
	if gpRaw.is_empty():
		return
	gpS.gpEnsureHandles()
	var gpN: int = mini(gpRaw.size(), gpS.gpPoints.size())
	for gpI in range(gpN):
		var gpPair: Array = gpRaw[gpI]
		if gpPair.size() < 2:
			continue
		var gpIn: Vector2 = Vector2(float(gpPair[0][0]), float(gpPair[0][1]))
		var gpOut: Vector2 = Vector2(float(gpPair[1][0]), float(gpPair[1][1]))
		gpS.gpHandles[gpI] = PackedVector2Array([gpIn, gpOut])
