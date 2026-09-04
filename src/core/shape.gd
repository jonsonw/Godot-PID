class_name GPShape
extends RefCounted

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

# Primitive kind: line / circle / rectangle / polyline.
# 图元种类：直线 / 圆 / 矩形 / 折线。
enum GPKind { GP_LINE, GP_CIRCLE, GP_RECT, GP_POLYLINE }

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

# Whether a polyline is closed (last point connects back to the first).
# 折线是否闭合（末点连回首点）。
var gpClosed: bool = false

# Annotation ink color (canvas-space, so it survives zoom). Light, CAD-like default.
# 注释墨色（画布空间，故缩放不变）。默认浅色、CAD 风格墨线。
var gpColor: Color = Color(0.92, 0.94, 0.98)


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
		_:
			if gpPoints.size() >= 1:
				var gpMin := Vector2(INF, INF)
				var gpMax := Vector2(-INF, -INF)
				for gpP in gpPoints:
					gpMin = gpMin.min(gpP)
					gpMax = gpMax.max(gpP)
				return Rect2(gpMin, gpMax - gpMin)
	return Rect2(Vector2.ZERO, Vector2.ZERO)


# Serialize to a dictionary (JSON-friendly).
# 序列化为字典（JSON 友好）。
func gpToDict() -> Dictionary:
	var gpPts: Array = []
	for gpP in gpPoints:
		gpPts.append([gpP.x, gpP.y])
	return {
		"kind": gpKind,
		"pts": gpPts,
		"radius": gpRadius,
		"closed": gpClosed,
	}


# Restore from a dictionary (inverse of gpToDict).
# 从字典还原（gpToDict 的逆操作）。
func gpFromDict(gpD: Dictionary) -> void:
	gpKind = int(gpD.get("kind", GPKind.GP_LINE))
	var gpRaw: Array = gpD.get("pts", [])
	var gpArr: PackedVector2Array = PackedVector2Array()
	for gpPair in gpRaw:
		gpArr.append(Vector2(float(gpPair[0]), float(gpPair[1])))
	gpPoints = gpArr
	gpRadius = float(gpD.get("radius", 0.0))
	gpClosed = bool(gpD.get("closed", false))
