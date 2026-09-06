class_name GPShapeGripEditor
extends RefCounted

## AutoCAD-style grip (edit-point) logic for a single GPShape. Pure geometry — no Canvas/Control
## state — so the main P&ID canvas and the symbol editor share one implementation instead of each
## re-deriving endpoint / center / radius / corner / vertex handles and their drag mutations.
## 单枚 GPShape 的 AutoCAD 式锚点（编辑点）逻辑。纯几何、无 Canvas/Control 状态，使主 P&ID 画布
## 与符号编辑器共用同一实现，而非各自重推端点 / 圆心 / 半径 / 角点 / 顶点手柄及其拖拽改写。

const GP_GRIP_ENDPOINT: int = 1   # 直线端点 / line endpoint
const GP_GRIP_CENTER: int = 2     # 圆心 / circle center (move)
const GP_GRIP_RADIUS: int = 3     # 圆半径手柄 / circle radius handle
const GP_GRIP_CORNER: int = 4     # 矩形角点 / rectangle corner (resize)
const GP_GRIP_VERTEX: int = 5     # 折线顶点 / polyline vertex
const GP_GRIP_HANDLE_IN: int = 6  # 贝塞尔入手柄 / Bézier in-handle
const GP_GRIP_HANDLE_OUT: int = 7 # 贝塞尔出手柄 / Bézier out-handle


# Compute the grip (handle) list for gpS. Each grip carries its position, role and point index (gi).
# For a rect corner the opposite (fixed) corner is included as "opp" so a drag can rebuild the rect
# without any external state held by the caller.
# 计算 gpS 的锚点（手柄）列表。每个锚点带坐标、角色与点序号（gi）。矩形角点额外携带对顶角
# "opp"，使拖拽无需调用方保留任何外部状态即可重建矩形。
static func gpGrips(gpS: GPShape) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	match gpS.gpKind:
		GPShape.GPKind.GP_LINE, GPShape.GPKind.GP_POLYLINE:
			# A 2-pt GP_LINE is treated as an open 2-vertex polyline so it can carry Bézier handles
			# (double-click to pull them → the straight line bends into a curve). Emit VERTEX grips
			# (not ENDPOINT) so the canvas/editor vertex-hit & handle editing route it correctly.
			# 2 点的 GP_LINE 视为开放的双顶点折线，可携带贝塞尔手柄（双击拉出→直线弯成曲线）。发出
			# VERTEX（而非 ENDPOINT）锚点，使画布/编辑器的顶点命中与手柄编辑正确路由它。
			for gpI in range(gpS.gpPoints.size()):
				gpOut.append({"pos": gpS.gpPoints[gpI], "role": GP_GRIP_VERTEX, "gi": gpI})
				if gpI < gpS.gpHandles.size() and gpS.gpHandles[gpI].size() >= 2:
					var gpIn: Vector2 = gpS.gpHandles[gpI][0]
					var gpOutH: Vector2 = gpS.gpHandles[gpI][1]
					if not gpIn.is_equal_approx(Vector2.ZERO):
						gpOut.append({"pos": gpS.gpPoints[gpI] + gpIn, "role": GP_GRIP_HANDLE_IN, "gi": gpI, "sub": 0})
					if not gpOutH.is_equal_approx(Vector2.ZERO):
						gpOut.append({"pos": gpS.gpPoints[gpI] + gpOutH, "role": GP_GRIP_HANDLE_OUT, "gi": gpI, "sub": 1})
		GPShape.GPKind.GP_CIRCLE:
			if gpS.gpPoints.size() >= 1:
				var gpC: Vector2 = gpS.gpPoints[0]
				gpOut.append({"pos": gpC, "role": GP_GRIP_CENTER, "gi": 0})
				gpOut.append({"pos": gpC + Vector2(gpS.gpRadius, 0.0), "role": GP_GRIP_RADIUS, "gi": 1})
		GPShape.GPKind.GP_RECT:
			var gpCorners: PackedVector2Array = GPGeometry.gpRectCorners(gpS.gpBBox())
			for gpI in range(4):
				var gpOpp: int = (gpI + 2) % 4
				gpOut.append({"pos": gpCorners[gpI], "role": GP_GRIP_CORNER, "gi": gpI, "opp": gpCorners[gpOpp]})
		GPShape.GPKind.GP_ARC:
			# Center (move) + start / end points on the circle (change radius + sweep).
			# 圆心（移动）+ 圆上起点 / 终点（改变半径与扫掠）。
			gpOut.append({"pos": gpS.gpArcCenter(), "role": GP_GRIP_CENTER, "gi": 0})
			gpOut.append({"pos": gpS.gpArcStart(), "role": GP_GRIP_VERTEX, "gi": 1})
			gpOut.append({"pos": gpS.gpArcEnd(), "role": GP_GRIP_VERTEX, "gi": 2})
	return gpOut


# Mutate gpS in place so that gpGrip (from gpGrips) moves to gpPt.
# 就地改写 gpS，使来自 gpGrips 的 gpGrip 移动到 gpPt。
static func gpApplyGrip(gpS: GPShape, gpGrip: Dictionary, gpPt: Vector2) -> void:
	var gpRole: int = int(gpGrip["role"])
	var gpGi: int = int(gpGrip["gi"])
	match gpRole:
		GP_GRIP_ENDPOINT, GP_GRIP_VERTEX:
			# Arc start (gi=1) / end (gi=2): dragging changes the radius (center->point) and sweep.
			# 弧起点（gi=1）/终点（gi=2）：拖动改变半径（圆心→点）与扫掠角。
			if gpS.gpKind == GPShape.GPKind.GP_ARC and gpS.gpPoints.size() >= 3:
				var gpC: Vector2 = gpS.gpArcCenter()
				if gpGi == 1:
					gpS.gpPoints[1] = gpPt
					gpS.gpRadius = gpC.distance_to(gpPt)
				elif gpGi == 2:
					gpS.gpPoints[2] = gpPt
					gpS.gpRadius = gpC.distance_to(gpPt)
			elif gpGi >= 0 and gpGi < gpS.gpPoints.size():
				gpS.gpPoints[gpGi] = gpPt
		GP_GRIP_CENTER:
			# Arc center (gi=0): rigid-translate the whole arc, keeping radius + sweep.
			# 弧圆心（gi=0）：整体刚性平移，保持半径与扫掠。
			if gpS.gpKind == GPShape.GPKind.GP_ARC and gpGi == 0 and gpS.gpPoints.size() >= 3:
				var gpDelta: Vector2 = gpPt - gpS.gpArcCenter()
				gpS.gpPoints = PackedVector2Array([
					gpS.gpArcCenter() + gpDelta,
					gpS.gpArcStart() + gpDelta,
					gpS.gpArcEnd() + gpDelta,
				])
			elif gpS.gpPoints.size() >= 1:
				gpS.gpPoints[0] = gpPt
		GP_GRIP_RADIUS:
			if gpS.gpPoints.size() >= 1:
				gpS.gpRadius = maxf(1.0, gpPt.distance_to(gpS.gpPoints[0]))
		GP_GRIP_HANDLE_IN:
			# Pull the in-tangent of vertex gi; stored as a relative offset so it travels with the
			# vertex. Dragging the in-handle bends the segment arriving at this vertex into a curve.
			# 拉出入手柄；以相对偏移存储，随顶点移动。拖入手柄使到达该顶点的段变为曲线。
			if gpS.gpKind == GPShape.GPKind.GP_POLYLINE or gpS.gpKind == GPShape.GPKind.GP_LINE:
				gpS.gpSetHandle(gpGi, 0, gpPt)
		GP_GRIP_HANDLE_OUT:
			# Pull the out-tangent of vertex gi; bends the segment leaving this vertex.
			# 拉出手柄；使离开该顶点的段变为曲线。
			if gpS.gpKind == GPShape.GPKind.GP_POLYLINE or gpS.gpKind == GPShape.GPKind.GP_LINE:
				gpS.gpSetHandle(gpGi, 1, gpPt)
		GP_GRIP_CORNER:
			# A corner drag keeps the opposite (fixed) corner anchored. Store the rect as a proper
			# (min, max) pair instead of a raw [opp, pt] so dragging a corner PAST the opposite corner
			# cannot invert/mirror the rectangle (gpBBox().abs() would otherwise flip it). This makes
			# every corner behave like the "stable" one the user expects.
			# 角点拖拽固定对顶角。把矩形存为规范的 (min, max) 对，而非原始 [opp, pt]，从而拖动角点
			# 越过对顶角时不会把矩形反转/镜像（否则 gpBBox().abs() 会翻转它）。这使每个角点都表现得像
			# 用户期望的「稳定」角。
			if gpGrip.has("opp"):
				var gpOpp: Vector2 = gpGrip["opp"] as Vector2
				gpS.gpPoints = PackedVector2Array([
					Vector2(minf(gpOpp.x, gpPt.x), minf(gpOpp.y, gpPt.y)),
					Vector2(maxf(gpOpp.x, gpPt.x), maxf(gpOpp.y, gpPt.y)),
				])
