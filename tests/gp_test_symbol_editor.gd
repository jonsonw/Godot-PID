class_name GPTESTSymbolEditor
extends GPGTest
# Headless tests for the M7 symbol-geometry editor + its undoable command stack.
# M7 符号几何编辑器及其可撤销命令栈的 headless 测试。

func gpTestAddShapeUndoRedo() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	var gpS: GPShape = GPShape.gpLine(Vector2(0.0, 0.0), Vector2(10.0, 10.0))
	var gpIdx: int = gpEd.gpAddShape(gpS)
	gpCheck(gpIdx == 0, "add shape returns index 0")
	gpCheck(gpEd.gpShapes.size() == 1, "one shape after add")
	gpCheck(gpEd.gpCanUndo(), "can undo after add")
	gpEd.gpUndo()
	gpCheck(gpEd.gpShapes.size() == 0, "no shape after undo")
	gpCheck(gpEd.gpCanRedo(), "can redo after undo")
	gpEd.gpRedo()
	gpCheck(gpEd.gpShapes.size() == 1, "shape restored after redo")
	gpCheck(gpEd.gpShapes[0] == gpS, "same shape object restored")


func gpTestAddPortUndoRedo() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	var gpP: GPPort = GPPort.new()
	gpP.gpName = "p1"
	gpP.gpPos = Vector2(0.5, 0.5)
	gpEd.gpAddPort(gpP)
	gpCheck(gpEd.gpPorts.size() == 1, "one port after add")
	gpEd.gpUndo()
	gpCheck(gpEd.gpPorts.size() == 0, "no port after undo")
	gpEd.gpRedo()
	gpCheck(gpEd.gpPorts.size() == 1, "port restored after redo")


func gpTestDeleteSelectedShape() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	var gpS: GPShape = GPShape.gpLine(Vector2(0.0, 0.0), Vector2(10.0, 10.0))
	gpEd.gpAddShape(gpS)
	gpEd.gpSelShape = 0
	gpEd.gpDeleteSelectedShape()
	gpCheck(gpEd.gpShapes.size() == 0, "shape removed")
	gpEd.gpUndo()
	gpCheck(gpEd.gpShapes.size() == 1, "shape restored by undo")
	gpCheck(gpEd.gpShapes[0] == gpS, "same object restored")


func gpTestMoveShapeUndoRedo() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	var gpS: GPShape = GPShape.gpLine(Vector2(0.0, 0.0), Vector2(10.0, 10.0))
	gpEd.gpAddShape(gpS)
	var gpBefore: PackedVector2Array = gpS.gpPoints.duplicate()
	var gpAfter: PackedVector2Array = GPGeometry.gpShiftPoints(gpBefore, Vector2(5.0, 0.0))
	gpEd.gpMoveShape(0, gpBefore, 0.0, gpAfter, 0.0)
	gpCheck(gpS.gpPoints[0].is_equal_approx(Vector2(5.0, 0.0)), "shape moved by +5x")
	gpEd.gpUndo()
	gpCheck(gpS.gpPoints[0].is_equal_approx(Vector2(0.0, 0.0)), "shape moved back by undo")
	gpEd.gpRedo()
	gpCheck(gpS.gpPoints[0].is_equal_approx(Vector2(5.0, 0.0)), "shape moved again by redo")


func gpTestMovePortUndoRedo() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	var gpP: GPPort = GPPort.new()
	gpP.gpName = "p1"
	gpP.gpPos = Vector2(0.2, 0.2)
	gpEd.gpAddPort(gpP)
	gpEd.gpMovePort(0, Vector2(0.2, 0.2), Vector2(0.8, 0.8))
	gpCheck(gpEd.gpPorts[0].gpPos.is_equal_approx(Vector2(0.8, 0.8)), "port moved")
	gpEd.gpUndo()
	gpCheck(gpEd.gpPorts[0].gpPos.is_equal_approx(Vector2(0.2, 0.2)), "port moved back by undo")


func gpTestHitShape() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	var gpS: GPShape = GPShape.gpLine(Vector2(0.0, 0.0), Vector2(10.0, 10.0))
	gpEd.gpAddShape(gpS)
	var gpLocal: Vector2 = gpEd.gpAuthorToLocal(Vector2(5.0, 5.0))
	gpCheck(gpEd.gpHitShape(gpLocal) == 0, "hit shape at midpoint")
	gpCheck(gpEd.gpHitShape(gpEd.gpAuthorToLocal(Vector2(100.0, 100.0))) == -1, "miss far away")


func gpTestHitPort() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	var gpP: GPPort = GPPort.new()
	gpP.gpName = "p1"
	gpP.gpPos = Vector2(0.5, 0.5)
	gpEd.gpAddPort(gpP)
	var gpLocal: Vector2 = gpEd.gpPortLocal(Vector2(0.5, 0.5))
	gpCheck(gpEd.gpHitPort(gpLocal) == 0, "hit port at its location")
	gpCheck(gpEd.gpHitPort(gpEd.gpPortLocal(Vector2(0.0, 0.0))) == -1, "miss far port")


func gpTestCoordRoundTrip() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	var gpL: Vector2 = Vector2(123.0, 77.0)
	var gpA: Vector2 = gpEd.gpLocalToAuthor(gpL)
	var gpBack: Vector2 = gpEd.gpAuthorToLocal(gpA)
	gpCheck(gpBack.is_equal_approx(gpL), "local->author->local round trip")
	var gpN: Vector2 = gpEd.gpLocalToNorm(gpL)
	var gpNback: Vector2 = gpEd.gpPortLocal(gpN)
	gpCheck(gpNback.is_equal_approx(gpL), "local->norm->portlocal round trip")


func gpTestToolDispatchPortAndSelect() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	gpEd.gpSetTool(GPSymbolEditor.GP_PORT)
	var gpEvPort: InputEventMouseButton = InputEventMouseButton.new()
	gpEvPort.button_index = MOUSE_BUTTON_LEFT
	gpEvPort.pressed = true
	gpEvPort.position = Vector2(100.0, 100.0)
	gpEd.gpOnInput(gpEvPort)
	gpCheck(gpEd.gpPorts.size() == 1, "port added via tool dispatch")
	gpEd.gpSetTool(GPSymbolEditor.GP_SELECT)
	var gpEvEmpty: InputEventMouseButton = InputEventMouseButton.new()
	gpEvEmpty.button_index = MOUSE_BUTTON_LEFT
	gpEvEmpty.pressed = true
	gpEvEmpty.position = Vector2(10.0, 10.0)
	gpEd.gpOnInput(gpEvEmpty)
	gpCheck(gpEd.gpSelPort == -1, "empty click deselects port")
	gpEd.gpOnInput(gpEvPort)
	gpCheck(gpEd.gpSelPort == 0, "click on port selects it")


func gpTestDrawLineTool() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	gpEd.gpSetTool(GPSymbolEditor.GP_LINE)
	var gpDown: InputEventMouseButton = InputEventMouseButton.new()
	gpDown.button_index = MOUSE_BUTTON_LEFT
	gpDown.pressed = true
	gpDown.position = Vector2(50.0, 50.0)
	gpEd.gpOnInput(gpDown)
	var gpMove: InputEventMouseMotion = InputEventMouseMotion.new()
	gpMove.position = Vector2(150.0, 150.0)
	gpEd.gpOnInput(gpMove)
	var gpUp: InputEventMouseButton = InputEventMouseButton.new()
	gpUp.button_index = MOUSE_BUTTON_LEFT
	gpUp.pressed = false
	gpUp.position = Vector2(150.0, 150.0)
	gpEd.gpOnInput(gpUp)
	gpCheck(gpEd.gpShapes.size() == 1, "line drawn via tool dispatch")
	gpCheck(gpEd.gpSelShape == 0, "auto-selected after draw")


func gpTestAuthorPorts() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpSetViewSize(Vector2(200.0, 200.0))
	var gpP: GPPort = GPPort.new()
	gpP.gpName = "p1"
	gpP.gpPos = Vector2(0.5, 0.5)
	gpEd.gpAddPort(gpP)
	var gpArr: Array = gpEd.gpAuthorPorts("general")
	gpCheck(gpArr.size() == 1, "author ports returns one entry")
