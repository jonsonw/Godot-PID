class_name GPShape
extends Resource
# Array[GPShape] — Godot's @export only accepts built-in / Resource / Node / enum types.
# Array[GPShape] —— Godot 的 @export 仅接受内建/Resource/Node/枚举类型。

# Copyright © 2026 Jonson Wang
# One annotation primitive drawn directly on the P&ID canvas (line / circle / rectangle /
# polyline). Distinct from symbol glyphs: these are free decorations/annotations that live in
# the sheet's flat shape layer and are NOT symbol instances. They can, however, be selected and
# "promoted" into a real symbol (see canvas_2d.gd -> gpMakeSymbolRequested), which opens the
# isolation editor pre-loaded with the same geometry.
# 主画布上直接绘制的注释图元（直线 / 圆 / 矩形 / 折线）。与图元字形不同：这些是处在图纸
# 扁平「图形层」的自由注释/装饰，不是图元实例。但可被选中并「提升」为真正的图元
# （见 canvas_2d.gd -> gpMakeSymbolRequested），从而打开已预装相同几何的隔离编辑器。
# Coding rule: every variable must declare its type explicitly (including container types).
# 编码规范：所有变量均显式声明类型（含容器类型）。

# Primitive kind: line / circle / rectangle / polyline / arc.
# 图元种类：直线 / 圆 / 矩形 / 折线 / 弧线。
# GP_TEXT (B08) is the annotation entity that carries an open-end note: text is a real drawing
# object with uid / layer / props, so it can be selected, listed and exported on its own.
# GP_TEXT（B08）是承载开口端注记的注释实体：文字是真正的图面对象，带 uid / 图层 / 属性，
# 故可单独选中、进清单、独立导出。
enum GPKind { GP_LINE, GP_CIRCLE, GP_RECT, GP_POLYLINE, GP_ARC, GP_TEXT }

# Primitive kind (see GPKind).
# 图元种类（见 GPKind）。
var gpKind: int = GPKind.GP_LINE

# Polyline vertices / line endpoints / rectangle corners (WORLD coordinates). For the circle
# kind the single point at index 0 is its center; the radius lives in gpRadius below.
# 折线顶点 / 直线端点 / 矩形对角点（世界坐标）。圆种类下 gpPoints[0] 为圆心，半径见 gpRadius。
var gpPoints: PackedVector2Array = PackedVector2Array()

# Radius for the circle kind only (ignored by the others).
# 仅圆种类使用的半径（其余种类忽略）。
var gpRadius: float = 0.0

# Text content for the GP_TEXT kind (ignored by the others). Newlines are preserved; wrapping is
# the renderer's business (B07), not the model's.
# GP_TEXT 种类的文字内容（其余种类忽略）。换行保留；折行是渲染层的事（B07），不是模型的事。
var gpText: String = ""

# Cap height of the text in WORLD units (mm). Drawing practice expresses text size in millimetres,
# so the model does too; the renderer scales it by the view zoom like every other annotation.
# 文字的世界字号（mm）。制图惯例以毫米表达字高，模型照此；渲染按视图缩放换算，与其它注释一致。
var gpTextSize: float = 3.5

# Whether a polyline is closed (last point connects back to the first).
# 折线是否闭合（末点连回首点）。
var gpClosed: bool = false

# Annotation ink color (canvas-space, so it survives zoom). Light, CAD-like default.
# 注释墨色（画布空间，故缩放不变）。默认浅色、CAD 风格墨线。
var gpColor: Color = Color(0.92, 0.94, 0.98)

# Per-vertex Bézier tangent handles, stored as RELATIVE offsets from each vertex. Parallel to
# gpPoints: gpHandles[i] = [in_offset, out_offset]. Both zero => straight (corner) node. Pulling a
# handle out bends the adjacent segment into a curve. Relative storage means a vertex dragged via
# its grip carries its handles along automatically.
# 逐顶点的贝塞尔切线手柄，以「相对顶点的偏移」存储，与 gpPoints 平行：gpHandles[i] = [入偏移, 出偏移]。
# 两者皆零 => 直线（拐角）节点。拉出手柄使相邻段变为曲线。相对存储使顶点经抓取点拖动时手柄自动跟随。
# NOTE: `Array[T]` is NOT valid GDScript 4 — a typed array has no callable constructor and
# parsing it fails with "Cannot call on an expression" (which surfaces as the very confusing
# "Could not parse global class GPShape" cascade everywhere GPShape is referenced).
# 注意：`Array[T]` 在 GDScript 4 中不合法——类型化数组无可调用的构造函数，解析时报
# "Cannot call on an expression"（并级联成所有引用 GPShape 处那句极费解的
# "Could not parse global class GPShape"）。
var gpHandles: Array[PackedVector2Array] = []

# Cross-document technical id, e.g. "a3f9k2m1-s3". Assigned by GPIdGen.gpNextGlobal().
# 跨文档技术号，如 "a3f9k2m1-s3"。由 GPIdGen.gpNextGlobal() 分配。
var gpUid: String = ""

# Human name for the annotation, e.g. "界区线". Shown in the inspector only.
# 注释图形的人类可读名称，如 "界区线"。仅显示在属性面板。
var gpName: String = ""

# Layer bucket: ANNOTATION (default) / BORDER / DIMENSION / HATCH.
# 图层分桶：ANNOTATION（默认）/ BORDER（图框）/ DIMENSION（标注）/ HATCH（填充）。
var gpLayer: String = "ANNOTATION"

# Property values keyed by field key (same "values only" rule as GPPIDNode).
# 按字段键索引的属性值（与 GPPIDNode 相同的「只存值」规则）。
var gpProps: Dictionary = {}


# Build a 2-point line.
# 构造两点直线。
static func gpLine(gpA: Vector2, gpB: Vector2) -> GPShape:
	var gpS: GPShape = GPShape.new()
	gpS.gpKind = GPKind.GP_LINE
	gpS.gpPoints = PackedVector2Array([gpA, gpB])
	return gpS


# Build a circle from center + radius.
# 由圆心 + 半径构造圆。
static func gpCircle(gpC: Vector2, gpR: float) -> GPShape:
	var gpS: GPShape = GPShape.new()
	gpS.gpKind = GPKind.GP_CIRCLE
	gpS.gpPoints = PackedVector2Array([gpC])
	gpS.gpRadius = gpR
	return gpS


# Build an axis-aligned rectangle from two opposite corners (order-independent).
# 由任意对角两点构造轴对齐矩形（顺序无关）。
static func gpRect(gpA: Vector2, gpB: Vector2) -> GPShape:
	var gpS: GPShape = GPShape.new()
	gpS.gpKind = GPKind.GP_RECT
	gpS.gpPoints = PackedVector2Array([gpA, gpB])
	return gpS


# Build a polyline from a list of world points.
# 由一组世界坐标点构造折线。
static func gpPolyline(gpPts: Array[Vector2], gpClosedFlag: bool) -> GPShape:
	var gpS: GPShape = GPShape.new()
	gpS.gpKind = GPKind.GP_POLYLINE
	var gpArr: PackedVector2Array = PackedVector2Array()
	for gpP in gpPts:
		gpArr.append(gpP)
	gpS.gpPoints = gpArr
	gpS.gpClosed = gpClosedFlag
	return gpS


# Build a circular arc from its center and two points on the circle (start / end). The three
# points are stored in gpPoints (center, start, end) so the arc reuses the existing vertex model;
# the radius is derived from center->start and kept in gpRadius for consistency. The drawn arc is
# the minor (counter-clockwise) sweep from start to end.
# 由圆心与圆上两点（起点 / 终点）构造圆弧。三点存入 gpPoints（圆心、起点、终点），复用既有顶点
# 模型；半径由 圆心→起点 推导并存于 gpRadius 以保持一致。绘制弧为从起点到终点的劣弧（逆时针）。
static func gpArc(gpC: Vector2, gpStart: Vector2, gpEnd: Vector2) -> GPShape:
	var gpS: GPShape = GPShape.new()
	gpS.gpKind = GPKind.GP_ARC
	gpS.gpPoints = PackedVector2Array([gpC, gpStart, gpEnd])
	gpS.gpRadius = gpC.distance_to(gpStart)
	return gpS


# Arc center (gpPoints[0]).
# 弧圆心（gpPoints[0]）。
func gpArcCenter() -> Vector2:
	if gpPoints.size() >= 1:
		return gpPoints[0]
	return Vector2.ZERO


# Arc start point on the circle (gpPoints[1]).
# 弧起点（圆上，gpPoints[1]）。
func gpArcStart() -> Vector2:
	if gpPoints.size() >= 2:
		return gpPoints[1]
	return Vector2.ZERO


# Arc end point on the circle (gpPoints[2]).
# 弧终点（圆上，gpPoints[2]）。
func gpArcEnd() -> Vector2:
	if gpPoints.size() >= 3:
		return gpPoints[2]
	return Vector2.ZERO


# Start / end angles (radians) and the counter-clockwise sweep delta from start to end.
# 起点 / 终点角（弧度）与从起点到终点的逆时针扫掠增量。
func gpArcAngles() -> Dictionary:
	var gpC: Vector2 = gpArcCenter()
	var gpA0: float = (gpArcStart() - gpC).angle()
	var gpA1: float = (gpArcEnd() - gpC).angle()
	var gpDelta: float = fposmod(gpA1 - gpA0, TAU)
	return {"a0": gpA0, "a1": gpA1, "delta": gpDelta}


# Sample gpSteps points along the arc (for bbox / hit / drawing helpers).
# 沿弧采样 gpSteps 个点（供包围盒 / 命中 / 绘制助手使用）。
func gpArcSample(gpSteps: int = 0) -> PackedVector2Array:
	var gpOut: PackedVector2Array = PackedVector2Array()
	if gpPoints.size() < 3 or gpRadius <= 0.0:
		return gpOut
	var gpC: Vector2 = gpArcCenter()
	var gpA: Dictionary = gpArcAngles()
	# Adaptive subdivision: when gpSteps == 0 pick a count that keeps arc points dense enough to
	# look smooth at any radius (≈1 point per 2 world units along the arc). This removes the
	# faceted / angular look on large-radius or long-sweep arcs.
	# 自适应细分：gpSteps==0 时按弧长取点数（沿弧约每 2 个世界单位 1 点），使任意半径 / 长扫掠的
	# 弧都足够顺滑，消除大半径或长扫掠弧上的块状 / 棱角观感。
	if gpSteps <= 0:
		var gpArcLen: float = gpRadius * absf(float(gpA["delta"]))
		gpSteps = int(ceilf(gpArcLen / 2.0))
		gpSteps = clampi(gpSteps, 16, 512)
	for gpI in range(gpSteps + 1):
		var gpT: float = float(gpI) / float(gpSteps)
		var gpAng: float = gpA["a0"] + gpA["delta"] * gpT
		gpOut.append(gpC + Vector2(cos(gpAng), sin(gpAng)) * gpRadius)
	return gpOut


# Ensure gpHandles has one entry per vertex, filling straight (zero) handles for missing ones.
# 确保 gpHandles 与顶点一一对应，缺失处补零（直线）手柄。
func gpEnsureHandles() -> void:
	if gpKind != GPKind.GP_POLYLINE and gpKind != GPKind.GP_LINE:
		return
	while gpHandles.size() < gpPoints.size():
		gpHandles.append(PackedVector2Array([Vector2.ZERO, Vector2.ZERO]))


# Absolute position of vertex gpIdx's handle (gpWhich: 0 = in, 1 = out). Returns the vertex itself
# when the handle is collapsed (zero offset) so a collapsed handle sits on the vertex.
# 顶点 gpIdx 手柄（gpWhich: 0=入, 1=出）的绝对位置。手柄塌缩（零偏移）时返回顶点自身，使塌缩手柄落在顶点上。
func gpHandlePos(gpIdx: int, gpWhich: int) -> Vector2:
	if gpIdx < 0 or gpIdx >= gpPoints.size():
		return Vector2.ZERO
	if gpIdx < gpHandles.size() and gpHandles[gpIdx].size() >= 2:
		return gpPoints[gpIdx] + gpHandles[gpIdx][gpWhich]
	return gpPoints[gpIdx]


# Set vertex gpIdx's handle (gpWhich) to an absolute position; stored as a relative offset.
# 将顶点 gpIdx 的手柄（gpWhich）设为绝对位置；以相对偏移存储。
func gpSetHandle(gpIdx: int, gpWhich: int, gpAbs: Vector2) -> void:
	if gpIdx < 0 or gpIdx >= gpPoints.size():
		return
	gpEnsureHandles()
	while gpHandles[gpIdx].size() < 2:
		gpHandles[gpIdx].append(Vector2.ZERO)
	gpHandles[gpIdx][gpWhich] = gpAbs - gpPoints[gpIdx]


# Whether any handle is pulled out (i.e. the polyline contains curves).
# 是否存在被拉出的手柄（即折线含曲线）。
func gpHasCurve() -> bool:
	for gpH in gpHandles:
		if gpH.size() >= 1 and (not gpH[0].is_equal_approx(Vector2.ZERO)):
			return true
		if gpH.size() >= 2 and (not gpH[1].is_equal_approx(Vector2.ZERO)):
			return true
	return false


# Remove the vertex at gpIdx (and its handles), keeping the remaining polyline connected.
# 删除顶点 gpIdx（及其手柄），剩余折线保持连接。
func gpRemoveVertex(gpIdx: int) -> void:
	if gpIdx < 0 or gpIdx >= gpPoints.size():
		return
	gpPoints.remove_at(gpIdx)
	if gpIdx < gpHandles.size():
		gpHandles.remove_at(gpIdx)


# Cubic Bézier control points between vertex gpI and gpI+1 (or wrap when closed). Returns the four
# absolute points; when a handle is collapsed the corresponding control collapses onto its vertex,
# degrading gracefully to a straight segment.
# 顶点 gpI 与 gpI+1（闭合时回绕）之间的三次贝塞尔控制点。手柄塌缩时对应控制点落在顶点上，自然退化为直线。
func gpSegmentControls(gpI: int) -> PackedVector2Array:
	var gpOut: PackedVector2Array = PackedVector2Array()
	var gpN: int = gpPoints.size()
	if gpN < 2:
		return gpOut
	var gpJ: int = gpI + 1
	if gpJ >= gpN:
		if gpClosed:
			gpJ = 0
		else:
			return gpOut
	var gpP0: Vector2 = gpPoints[gpI]
	var gpP1: Vector2 = gpPoints[gpJ]
	var gpC1: Vector2 = gpHandlePos(gpI, 1)   # out of i / 顶点 i 的出手柄
	var gpC2: Vector2 = gpHandlePos(gpJ, 0)   # in of j  / 顶点 j 的入手柄
	gpOut.append(gpP0)
	gpOut.append(gpC1)
	gpOut.append(gpC2)
	gpOut.append(gpP1)
	return gpOut


# Axis-aligned bounding box of this shape (world space), for selection / marquee hit-testing.
# 本图元的轴对齐包围盒（世界空间），用于选中 / 框选命中测试。
func gpBBox() -> Rect2:
	match gpKind:
		GPKind.GP_CIRCLE:
			if gpPoints.size() >= 1:
				var gpC: Vector2 = gpPoints[0]
				return Rect2(gpC - Vector2(gpRadius, gpRadius), Vector2(gpRadius * 2.0, gpRadius * 2.0))
		GPKind.GP_RECT:
			if gpPoints.size() >= 2:
				return Rect2(gpPoints[0], gpPoints[1] - gpPoints[0]).abs()
		GPKind.GP_TEXT:
 # Anchor = gpPoints[0] (top-left of the first line). Width/height come from the same estimator
 # the renderer uses, so the selection box and the drawn text never disagree.
 # 锚点 = gpPoints[0]（首行左上角）。宽高取自渲染器同款估算器，故选框与画出来的文字不会不一致。
			if gpPoints.size() >= 1:
				return Rect2(gpPoints[0], gpTextExtent())
		GPKind.GP_ARC:
 # Sample the arc (the 3 stored points include the center, so a raw point-min/max is wrong).
 # 沿弧采样（三个存储点含圆心，直接取点的包围盒会出错）。
			var gpSamp: PackedVector2Array = gpArcSample(24)
			if gpSamp.size() >= 1:
				var gpMin := Vector2(INF, INF)
				var gpMax := Vector2(-INF, -INF)
				for gpP in gpSamp:
					gpMin = gpMin.min(gpP)
					gpMax = gpMax.max(gpP)
				return Rect2(gpMin, gpMax - gpMin)
		_:
			if gpPoints.size() >= 1:
				var gpMin := Vector2(INF, INF)
				var gpMax := Vector2(-INF, -INF)
				for gpP in gpPoints:
					gpMin = gpMin.min(gpP)
					gpMax = gpMax.max(gpP)
				return Rect2(gpMin, gpMax - gpMin)
	return Rect2(Vector2.ZERO, Vector2.ZERO)


# ---------------------------------------------------------------------------
# 整图平移（Rev.3 阶段 0d） / Whole-sheet translation
# ---------------------------------------------------------------------------
# Move every ABSOLUTE world coordinate this shape owns by gpDelta. gpPoints is the complete list — for
# all five kinds the stored points are world positions (a circle stores its CENTRE in points[0], a rect
# its two opposite corners, an arc its centre + two rim points, a line / polyline its vertices).
# 把本图元持有的每个**绝对世界坐标**按 gpDelta 平移。`gpPoints` 就是完整清单 —— 五种图型存的点都是
# 世界位置（圆把**圆心**存在 points[0]、矩形存两个对角点、弧存圆心 + 弧上两点、线 / 折线存顶点）。
#
# ⚠️ gpRadius AND gpHandles ARE NOT TOUCHED / ⚠️ gpRadius 与 gpHandles **不动**：
#   * gpRadius — a circle's size is independent of where it is; translating the centre is the whole move
#     (a world delta added to a radius would grow the circle by the drag distance).
#     gpRadius —— 圆的大小与它在哪儿无关；平移圆心即完成整次移动（把世界位移加到半径上，会让圆按拖拽
#     距离长大）。
#   * gpHandles — Bézier handles stored as offsets relative to their vertex, so they are
#     translation-invariant by construction. Adding the delta would bend every curve by twice the drag.
#     gpHandles —— 贝塞尔手柄以「相对其顶点」的偏移存储，故构造上即与平移无关。加上位移会让每条曲线
#     按两倍拖拽量变形。
func gpTranslate(gpDelta: Vector2) -> void:
	for gpI in range(gpPoints.size()):
		gpPoints[gpI] = gpPoints[gpI] + gpDelta


# Serialize to a dictionary (JSON-friendly).
# 序列化为字典（JSON 友好）。
func gpToDict() -> Dictionary:
	var gpPts: Array = []
	for gpP in gpPoints:
		gpPts.append([gpP.x, gpP.y])
	# Build the dict with key assignment (NOT a multi-line typed-dict literal — that is a parse
	# error in several Godot 4.x versions when the initializer spans multiple lines).
	# 用键赋值构造字典（勿用多行「带类型字典字面量」——在多个 Godot 4.x 版本中跨行初始化会触发解析错误）。
	var gpD: Dictionary = {}
	gpD["kind"] = gpKind
	gpD["pts"] = gpPts
	gpD["radius"] = gpRadius
	gpD["closed"] = gpClosed
	# Only emit handles when the polyline/line actually curves, to keep flat files clean.
	# 仅当折线/直线确实含曲线时才输出手柄，保持扁平文件整洁。
	if (gpKind == GPKind.GP_POLYLINE or gpKind == GPKind.GP_LINE) and gpHasCurve():
		var gpHs: Array = []
		for gpI in range(gpPoints.size()):
			var gpIn: Vector2 = Vector2.ZERO
			var gpOut: Vector2 = Vector2.ZERO
			if gpI < gpHandles.size() and gpHandles[gpI].size() >= 2:
				gpIn = gpHandles[gpI][0]
				gpOut = gpHandles[gpI][1]
			gpHs.append([[gpIn.x, gpIn.y], [gpOut.x, gpOut.y]])
		gpD["handles"] = gpHs
	if gpUid != "":
		gpD["uid"] = gpUid
	if gpName != "":
		gpD["name"] = gpName
	if gpLayer != "ANNOTATION":
		gpD["layer"] = gpLayer
	if not gpProps.is_empty():
		gpD["props"] = gpProps.duplicate(true)
	# Text travels only for the text kind, so every other shape keeps its previous byte shape.
	# 文字仅在文字种类时写出，使其它图形的字节形态保持不变。
	if gpKind == GPKind.GP_TEXT:
		gpD["text"] = gpText
		gpD["text_size"] = gpTextSize
	return gpD


# Restore from a dictionary (inverse of gpToDict()).
# 从字典还原（gpToDict() 的逆操作）。
func gpFromDict(gpD: Dictionary) -> void:
	gpKind = int(gpD.get("kind", GPKind.GP_LINE))
	var gpRaw: Array = gpD.get("pts", [])
	var gpArr: PackedVector2Array = PackedVector2Array()
	for gpPair in gpRaw:
		gpArr.append(Vector2(float(gpPair[0]), float(gpPair[1])))
	gpPoints = gpArr
	gpRadius = float(gpD.get("radius", 0.0))
	# Arc radius is derived from center->start when not stored explicitly (keeps the model consistent).
	# 弧半径在字典未显式存储时由 圆心→起点 推导（保持模型一致）。
	if gpKind == GPKind.GP_ARC and gpRadius <= 0.0 and gpPoints.size() >= 2:
		gpRadius = gpPoints[0].distance_to(gpPoints[1])
	gpClosed = bool(gpD.get("closed", false))
	gpText = str(gpD.get("text", ""))
	gpTextSize = float(gpD.get("text_size", 3.5))
	# Restore Bézier handles for polylines / lines (relative offsets, parallel to vertices).
	# 还原折线 / 直线的贝塞尔手柄（相对偏移，与顶点平行）。
	# Clear (not re-assign) so the declared typed-array type is preserved.
	# 用清空（而非重新赋值），以保留已声明的类型化数组类型。
	gpHandles.clear()
	if gpKind == GPKind.GP_POLYLINE or gpKind == GPKind.GP_LINE:
		var gpRawH: Array = gpD.get("handles", [])
		for gpI in range(gpPoints.size()):
			var gpIn := Vector2.ZERO
			var gpOut := Vector2.ZERO
			if gpI < gpRawH.size():
				var gpPair: Array = gpRawH[gpI]
				if gpPair.size() >= 1:
					gpIn = Vector2(float(gpPair[0][0]), float(gpPair[0][1]))
				if gpPair.size() >= 2:
					gpOut = Vector2(float(gpPair[1][0]), float(gpPair[1][1]))
			gpHandles.append(PackedVector2Array([gpIn, gpOut]))
	gpUid = gpD.get("uid", "")
	gpName = gpD.get("name", "")
	gpLayer = gpD.get("layer", "ANNOTATION")
	var gpPropsIn: Variant = gpD.get("props", {})
	gpProps = (gpPropsIn as Dictionary).duplicate(true) if gpPropsIn is Dictionary else {}


# Build a text annotation anchored at gpPos (top-left of the first line).
# 以 gpPos（首行左上角）为锚点构造一个文字注释。
static func gpTextNote(gpPos: Vector2, gpBody: String, gpSize: float = 3.5) -> GPShape:
	var gpS: GPShape = GPShape.new()
	gpS.gpKind = GPKind.GP_TEXT
	gpS.gpPoints = PackedVector2Array([gpPos])
	gpS.gpText = gpBody
	gpS.gpTextSize = gpSize
	return gpS

# Rendered extent of the text in world units, from the SAME per-character rule the renderer uses.
# 文字在世界坐标下的渲染外框，规则与渲染器同源（逐字符宽度）。
# WHY an estimator and not a font query / 为何用估算而非查字体：
# the model layer may not touch Godot fonts (core is render-free), and a wrapped multi-line block
# needs a stable width BEFORE it is drawn — an estimator that both sides share keeps the hit box,
# the selection box and the paint in agreement.
# 模型层不得触碰 Godot 字体（core 无渲染依赖），而多行块在绘制**之前**就需要稳定宽度 ——
# 两侧共用同一个估算器，使命中框、选框与笔迹保持一致。
static func gpTextWidthOf(gpBody: String, gpSize: float) -> float:
	var gpMax: float = 0.0
	for gpLine in gpBody.split("\n"):
		var gpW: float = 0.0
		for gpI in range(gpLine.length()):
			gpW += gpCharWidth(gpLine.unicode_at(gpI), gpSize)
		gpMax = maxf(gpMax, gpW)
	return gpMax

# Per-character advance: CJK and full-width punctuation take one em, ASCII takes ~0.6 em. Crude
# on purpose — a proportional-metrics query would need the font in core.
# 逐字符步进：CJK 与全角标点占一个 em，ASCII 约 0.6 em。刻意粗糙 —— 精确字宽需要字体进 core。
static func gpCharWidth(gpCode: int, gpSize: float) -> float:
	if gpCode >= 0x2E80:
		return gpSize
	return gpSize * 0.6

# Text extent (width, height) in world units: wrapped lines at 1.4 em leading.
# 文字外框（宽, 高）：按 1.4 em 行距排列已折行文本。
func gpTextExtent() -> Vector2:
	var gpLines: PackedStringArray = gpText.split("\n")
	var gpH: float = maxf(1.0, float(gpLines.size())) * gpTextSize * 1.4
	return Vector2(gpTextWidthOf(gpText, gpTextSize), gpH)
