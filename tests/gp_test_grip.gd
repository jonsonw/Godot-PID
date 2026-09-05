extends "res://tests/gp_test.gd"
# Headless regression tests for GPShapeGripEditor (P0/P1 fixes: rect corner grip
# symmetry, GP_LINE Bézier-handle support, handle grip enumeration).
# 抓取点编辑模块（P0/P1 修复：矩形角点缩放对称、GP_LINE 拉手柄、手柄抓取点）回归测试。

# Rect corner grips must resize symmetric (opposite corner fixed) for BOTH top-right
# and bottom-left drag — this was the "flip" bug the user reported and P1 fixed.
func gpTestRectCornerSymmetry() -> void:
	var rect: GPShape = GPShape.gpRect(Vector2(0, 0), Vector2(100, 100))
	var grips: Array[Dictionary] = GPShapeGripEditor.gpGrips(rect)
	var tr: Dictionary = {}
	var bl: Dictionary = {}
	for g in grips:
		if int(g["gi"]) == 1:
			tr = g
		elif int(g["gi"]) == 3:
			bl = g
	gpCheck(not tr.is_empty() and not bl.is_empty(), "rect has TR(gi=1) and BL(gi=3) corner grips")
	# Drag TR to (150,-50): BL stays fixed -> rect never inverts.
	var r1: GPShape = GPShape.gpRect(Vector2(0, 0), Vector2(100, 100))
	GPShapeGripEditor.gpApplyGrip(r1, tr, Vector2(150, -50))
	var b1: Rect2 = r1.gpBBox()
	gpCheck(b1.size.x > 0.0 and b1.size.y > 0.0, "TR drag keeps positive size (no flip)")
	# BL corner must have stayed at its opposite (bottom-right is gi of BL's opposite corner TR area).
	# A flipped rect would have negative size; verify bbox covers the expected span.
	gpCheck(b1.position.y <= 0.0 and b1.end.y >= 100.0 - 1e-6, "TR drag grew upward, kept opposite anchored")
	# Drag BL to (-50,150): TR stays fixed -> also no flip.
	var r2: GPShape = GPShape.gpRect(Vector2(0, 0), Vector2(100, 100))
	GPShapeGripEditor.gpApplyGrip(r2, bl, Vector2(-50, 150))
	var b2: Rect2 = r2.gpBBox()
	gpCheck(b2.size.x > 0.0 and b2.size.y > 0.0, "BL drag keeps positive size (no flip)")

# A GP_LINE (2-pt) with handles must expose vertex + handle grips (P1 fix for issue #2).
func gpTestLineHandles() -> void:
	var line: GPShape = GPShape.gpLine(Vector2(100, 100), Vector2(400, 100))
	line.gpEnsureHandles()
	line.gpSetHandle(0, 1, Vector2(200, 40))
	line.gpSetHandle(1, 0, Vector2(300, 40))
	gpCheck(line.gpHasCurve(), "2-point GP_LINE with pulled handles reports hasCurve")
	var grips: Array[Dictionary] = GPShapeGripEditor.gpGrips(line)
	var vertexGrips: int = 0
	var handleGrips: int = 0
	for g in grips:
		var r: int = int(g["role"])
		if r == GPShapeGripEditor.GP_GRIP_VERTEX:
			vertexGrips += 1
		elif r == GPShapeGripEditor.GP_GRIP_HANDLE_IN or r == GPShapeGripEditor.GP_GRIP_HANDLE_OUT:
			handleGrips += 1
	gpCheck(vertexGrips >= 2, "GP_LINE exposes 2 vertex grips")
	gpCheck(handleGrips >= 2, "GP_LINE exposes 2 handle grips (pulled in/out)")

# Applying a handle grip to a GP_LINE bends it (relative offset stored).
func gpTestLineHandleApply() -> void:
	var line: GPShape = GPShape.gpLine(Vector2(0, 0), Vector2(200, 0))
	line.gpEnsureHandles()
	line.gpSetHandle(0, 1, Vector2(50, -60))
	var grips: Array[Dictionary] = GPShapeGripEditor.gpGrips(line)
	var outGrip: Dictionary = {}
	for g in grips:
		if int(g["role"]) == GPShapeGripEditor.GP_GRIP_HANDLE_OUT and int(g["gi"]) == 0:
			outGrip = g
			break
	gpCheck(not outGrip.is_empty(), "found GP_LINE out-handle grip at vertex 0")
	GPShapeGripEditor.gpApplyGrip(line, outGrip, Vector2(60, -80))
	gpApprox(line.gpHandles[0][1].y, -80.0, 1e-4, "out-handle relative offset updated to abs-y")
	gpCheck(line.gpHasCurve(), "GP_LINE still curves after handle drag")
