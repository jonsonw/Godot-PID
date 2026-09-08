# ============================================================================
# GPSymbolEditor — 图元几何编辑器（M7）
# Symbol geometry editor (M7).
#
# 持有工作模型（_gpShapes / _gpPorts）、当前交互工具，以及「生成图元」对话框的撤销 / 重做历史。
# GPMakeSymbolDialog 原先内嵌了独立的几何编辑状态机（GPTool 枚举 + _gpDragKind/_gpDraftShape/
# _gpPolyPts 与 _gpCommit*/_gpHit* 助手），既重复了画布工具机制、又无法接入共享的 GPCommandStack。
# 本类复用同一套工具抽象（GPSymbolEditorTool + GPSymbolEditorContext + 小注册表），并把每次「加 / 删 / 移」
# 都经 GPCommandStack 走，使符号编辑器里的绘制、放置与删除和主画布一样可撤销。
# Owns the working model (_gpShapes / _gpPorts), the active interaction tool, and the undo/redo history
# for the Make-Symbol dialog. GPMakeSymbolDialog previously embedded its OWN geometry-editing state
# machine (enum GPTool + _gpDragKind/_gpDraftShape/_gpPolyPts and the _gpCommit*/_gpHit* helpers) —
# duplicating the canvas tool mechanism and unreachable by the shared GPCommandStack. This class reuses
# the SAME tool abstraction and routes every add / delete / move through GPCommandStack, so drawing,
# placing and deleting in the symbol editor are now undoable exactly like on the main canvas.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolEditor
extends RefCounted

# Emitted on any model / selection change so the host dialog can repaint and re-sync its panels.
# 任意模型 / 选择变更时发出，供宿主对话框重绘并重新同步面板。
signal gpChanged

# Emitted when the active tool changes, so the host can reflect it on its tool-button row.
# 当前工具切换时发出，供宿主在工具按钮行上反映。
signal gpToolChanged(gpKind: int)

# Tool kinds (same order as the dialog's tool-button row). / 工具种类（与对话框工具按钮行同序）。
enum GPSymbolToolKind { GP_SELECT, GP_PORT, GP_LINE, GP_RECT, GP_CIRCLE, GP_POLY }

# Bare enum names are not injected into the class scope in this GDScript version (same reason the
# canvas code aliases GPCanvasInteractState.GPMode); expose them as class constants so the rest of
# this file — and external callers via GPSymbolEditor.GP_* — can reference them unqualified.
# 本版 GDScript 不把枚举成员注入类作用域（同 canvas 别名 GPCanvasInteractState.GPMode 的原因），
# 故以类常量形式暴露，使本文件其余处及外部经 GPSymbolEditor.GP_* 可不加限定地引用。
const GP_SELECT: int = GPSymbolToolKind.GP_SELECT
const GP_PORT: int = GPSymbolToolKind.GP_PORT
const GP_LINE: int = GPSymbolToolKind.GP_LINE
const GP_RECT: int = GPSymbolToolKind.GP_RECT
const GP_CIRCLE: int = GPSymbolToolKind.GP_CIRCLE
const GP_POLY: int = GPSymbolToolKind.GP_POLY

const GP_MIN_LEN: float = 3.0
const GP_PORT_HIT: float = 9.0

# Working geometry model. Mutated IN PLACE (never reassigned) so in-flight commands keep a valid
# array reference. / 工作几何模型。原地变更（绝不重新赋值）以便进行中的命令持有有效数组引用。
var gpShapes: Array[GPShape] = []
var gpPorts: Array[GPPort] = []

var gpSelShape: int = -1
var gpSelPort: int = -1

# Category used to colour the preview (set by the host when the dropdown changes).
# 预览着色所用类别（宿主在下拉变更时设定）。
var gpCategory: String = "general"

# Coordinate transform (pure math, no Control dependency). / 坐标变换（纯数学，无 Control 依赖）。
var _gpXf: GPPreviewTransform = GPPreviewTransform.new()
var _gpViewSize: Vector2 = Vector2.ZERO

# Tool dispatch. / 工具派发。
var _gpCtx: GPSymbolEditorContext = null
var _gpRegistry: GPSymbolToolRegistry = GPSymbolToolRegistry.new()
var _gpTool: int = GP_SELECT
var _gpActiveTool: GPSymbolEditorTool = null

# Undo/redo history. / 撤销 / 重做历史。
var _gpStack: GPCommandStack = GPCommandStack.new()
# Dummy context handed to the stack; symbol commands carry their own array references.
# 交给栈的占位上下文；符号命令自带数组引用，不依赖它。
var _gpCtxCmd: GPCommandContext = GPCommandContext.new()


func _init() -> void:
	_gpCtx = GPSymbolEditorContext.new(self)
	_gpRegisterTools()


func _gpRegisterTools() -> void:
	_gpRegistry.gpRegister(GP_SELECT, GPSymbolSelectTool.new())
	var gpPort: GPSymbolPortTool = GPSymbolPortTool.new()
	_gpRegistry.gpRegister(GP_PORT, gpPort)
	var gpLine: GPSymbolDrawTool = GPSymbolDrawTool.new(); gpLine._gpKind = GPShape.GPKind.GP_LINE
	var gpRect: GPSymbolDrawTool = GPSymbolDrawTool.new(); gpRect._gpKind = GPShape.GPKind.GP_RECT
	var gpCircle: GPSymbolDrawTool = GPSymbolDrawTool.new(); gpCircle._gpKind = GPShape.GPKind.GP_CIRCLE
	var gpPoly: GPSymbolDrawTool = GPSymbolDrawTool.new(); gpPoly._gpKind = GPShape.GPKind.GP_POLYLINE
	_gpRegistry.gpRegister(GP_LINE, gpLine)
	_gpRegistry.gpRegister(GP_RECT, gpRect)
	_gpRegistry.gpRegister(GP_CIRCLE, gpCircle)
	_gpRegistry.gpRegister(GP_POLY, gpPoly)


# Replace the working model (used when the dialog opens on a draft). Mutates in place so the command
# stack's captured references stay valid; the history is cleared.
# 替换工作模型（对话框打开草稿时调用）。原地变更使命令栈持有的引用仍有效；历史被清空。
func gpInit(gpShapes: Array[GPShape], gpPorts: Array[GPPort]) -> void:
	self.gpShapes.clear()
	self.gpShapes.append_array(gpShapes)
	self.gpPorts.clear()
	self.gpPorts.append_array(gpPorts)
	gpSelShape = -1
	gpSelPort = -1
	_gpStack.gpClear()
	gpSetTool(GP_SELECT)
	gpChanged.emit()


func gpSetCategory(gpCat: String) -> void:
	gpCategory = gpCat
	gpChanged.emit()


# Set the preview pixel size (the host calls this from its draw, tests call it directly). Keeps the
# transform in sync so clicks map where the glyph is drawn.
# 设定预览像素尺寸（宿主在绘制时调用，测试直接调用）。使变换保持同步，点击方能落于图形绘制处。
func gpSetViewSize(gpSize: Vector2) -> void:
	_gpViewSize = gpSize


# ---- coordinate helpers (delegate to GPPreviewTransform, refreshed every call) ----
# 坐标助手（委托 GPPreviewTransform，每次调用刷新）

func _gpSyncXf() -> void:
	_gpXf.gpViewSize = _gpViewSize
	_gpXf.gpBox = GPPreviewTransform.gpBoxOf(gpShapes)


func gpLocalToAuthor(gpLocal: Vector2) -> Vector2:
	_gpSyncXf()
	return _gpXf.gpLocalToAuthor(gpLocal)


func gpAuthorToLocal(gpAuthor: Vector2) -> Vector2:
	_gpSyncXf()
	return _gpXf.gpAuthorToLocal(gpAuthor)


func gpPortLocal(gpN: Vector2) -> Vector2:
	_gpSyncXf()
	return _gpXf.gpPortLocal(gpN)


func gpLocalToNorm(gpLocal: Vector2) -> Vector2:
	_gpSyncXf()
	return _gpXf.gpLocalToNorm(gpLocal)


# ---- hit testing ----
# 命中测试

func gpHitPort(gpLocal: Vector2) -> int:
	for gpI in range(gpPorts.size()):
		if gpPortLocal(gpPorts[gpI].gpPos).distance_to(gpLocal) < GP_PORT_HIT:
			return gpI
	return -1


func gpHitShape(gpLocal: Vector2) -> int:
	var gpA: Vector2 = gpLocalToAuthor(gpLocal)
	var gpTol: float = GP_MIN_LEN
	for gpI in range(gpShapes.size() - 1, -1, -1):
		if GPGeometry.gpShapeHit(gpA, gpShapes[gpI], gpTol):
			return gpI
	return -1


# ---- input dispatch ----
# 输入派发

func gpOnInput(gpEv: InputEvent) -> void:
	if gpEv is InputEventMouseButton:
		var gpMb: InputEventMouseButton = gpEv as InputEventMouseButton
		if gpMb.button_index == MOUSE_BUTTON_LEFT:
			if gpMb.pressed:
				_gpOnPress(gpMb.position, gpMb.shift_pressed, gpMb.double_click)
			else:
				_gpOnRelease(gpMb.position)
	elif gpEv is InputEventMouseMotion:
		_gpOnMotion((gpEv as InputEventMouseMotion).position)
	elif gpEv is InputEventKey:
		var gpK: InputEventKey = gpEv as InputEventKey
		if gpK.pressed:
			_gpOnKey(gpK)


func _gpOnPress(gpLocal: Vector2, gpShift: bool, gpDouble: bool) -> void:
	if _gpActiveTool != null and _gpActiveTool.gpOnPress(gpLocal, gpShift, gpDouble):
		gpChanged.emit()


func _gpOnMotion(gpLocal: Vector2) -> void:
	if _gpActiveTool != null and _gpActiveTool.gpOnMove(gpLocal):
		gpChanged.emit()


func _gpOnRelease(gpLocal: Vector2) -> void:
	if _gpActiveTool != null and _gpActiveTool.gpOnRelease(gpLocal):
		gpChanged.emit()


func _gpOnKey(gpK: InputEventKey) -> void:
	# Delete works in ANY tool when something is selected (matches the old dialog behaviour).
	# 任意工具下，只要选中有内容即删除（与旧对话框行为一致）。
	if gpK.keycode == KEY_DELETE or gpK.keycode == KEY_BACKSPACE:
		gpDeleteSelected()
		gpChanged.emit()
		return
	# ESC cancels a half-finished primitive (polyline / two-point draw), matching the old dialog's
	# ESC-clears-polyline behaviour. Enter for the in-progress polyline is owned by the active tool.
	# ESC 取消进行中的半个图元（折线 / 两点绘制），与旧对话框「ESC 清空折线」行为一致；
	# 进行中折线的 Enter 由当前工具负责。
	if gpK.keycode == KEY_ESCAPE:
		if _gpActiveTool != null and _gpActiveTool.gpCancel():
			gpChanged.emit()
		return
	if _gpActiveTool != null and _gpActiveTool.gpOnKey(gpK):
		gpChanged.emit()


# ---- tool switching ----
# 工具切换

func gpSetTool(gpKind: int) -> void:
	if _gpActiveTool != null:
		_gpActiveTool.gpOnDeactivate()
	_gpTool = gpKind
	_gpActiveTool = _gpRegistry.gpGet(gpKind)
	if _gpActiveTool != null:
		_gpActiveTool.gpCtx = _gpCtx
		_gpActiveTool.gpOnActivate()
	gpToolChanged.emit(gpKind)
	gpChanged.emit()


# ---- mutation (all undoable) ----
# 模型变更（全部可撤销）

func gpAddShape(gpShape: GPShape) -> int:
	var gpCmd: GPSymbolAddShapeCommand = GPSymbolAddShapeCommand.new(gpShapes, gpShape)
	if _gpStack.gpDo(gpCmd, _gpCtxCmd):
		gpSelShape = gpShapes.find(gpShape)
		gpSelPort = -1
		gpChanged.emit()
		return gpSelShape
	return -1


func gpAddPort(gpPort: GPPort) -> void:
	var gpCmd: GPSymbolAddPortCommand = GPSymbolAddPortCommand.new(gpPorts, gpPort)
	if _gpStack.gpDo(gpCmd, _gpCtxCmd):
		gpSelPort = gpPorts.find(gpPort)
		gpSelShape = -1
		gpChanged.emit()


func gpDeleteSelectedShape() -> void:
	if gpSelShape < 0 or gpSelShape >= gpShapes.size():
		return
	gpDeleteShape(gpSelShape)


func gpDeleteSelectedPort() -> void:
	if gpSelPort < 0 or gpSelPort >= gpPorts.size():
		return
	gpDeletePort(gpSelPort)


# Delete whatever is selected (port takes priority, like the old dialog's key handler).
# 删除当前选中的内容（端口优先，与旧对话框的按键处理一致）。
func gpDeleteSelected() -> void:
	if gpSelPort >= 0:
		gpDeleteSelectedPort()
	elif gpSelShape >= 0:
		gpDeleteSelectedShape()


func gpDeleteShape(gpIdx: int) -> void:
	var gpCmd: GPSymbolDeleteShapesCommand = GPSymbolDeleteShapesCommand.new(gpShapes, [gpIdx])
	if _gpStack.gpDo(gpCmd, _gpCtxCmd):
		gpSelShape = -1
		gpChanged.emit()


func gpDeletePort(gpIdx: int) -> void:
	var gpCmd: GPSymbolDeletePortCommand = GPSymbolDeletePortCommand.new(gpPorts, [gpIdx])
	if _gpStack.gpDo(gpCmd, _gpCtxCmd):
		gpSelPort = -1
		gpChanged.emit()


func gpMoveShape(gpIdx: int, gpBefore: PackedVector2Array, gpBeforeR: float, gpAfter: PackedVector2Array, gpAfterR: float) -> void:
	var gpCmd: GPSymbolMoveShapeCommand = GPSymbolMoveShapeCommand.new(gpShapes, gpIdx, gpBefore, gpBeforeR, gpAfter, gpAfterR)
	_gpStack.gpDo(gpCmd, _gpCtxCmd)
	gpChanged.emit()


func gpMovePort(gpIdx: int, gpBefore: Vector2, gpAfter: Vector2) -> void:
	var gpCmd: GPSymbolMovePortCommand = GPSymbolMovePortCommand.new(gpPorts, gpIdx, gpBefore, gpAfter)
	_gpStack.gpDo(gpCmd, _gpCtxCmd)
	gpChanged.emit()


func gpSetPortName(gpName: String) -> void:
	if gpSelPort >= 0 and gpSelPort < gpPorts.size():
		gpPorts[gpSelPort].gpName = gpName
		gpChanged.emit()


func gpSetPortDir(gpDir: Vector2) -> void:
	if gpSelPort >= 0 and gpSelPort < gpPorts.size():
		gpPorts[gpSelPort].gpDir = gpDir
		gpChanged.emit()


# ---- undo / redo ----
# 撤销 / 重做

func gpUndo() -> bool:
	var gpOk: bool = _gpStack.gpUndo(_gpCtxCmd)
	gpSelShape = -1
	gpSelPort = -1
	gpChanged.emit()
	return gpOk


func gpRedo() -> bool:
	var gpOk: bool = _gpStack.gpRedo(_gpCtxCmd)
	gpSelShape = -1
	gpSelPort = -1
	gpChanged.emit()
	return gpOk


func gpCanUndo() -> bool:
	return _gpStack.gpCanUndo()


func gpCanRedo() -> bool:
	return _gpStack.gpCanRedo()


func gpUndoLabel() -> String:
	return _gpStack.gpUndoLabel()


func gpRedoLabel() -> String:
	return _gpStack.gpRedoLabel()


# ---- drawing ----
# 绘制

func gpDraw(gpC: Control) -> void:
	_gpViewSize = gpC.size
	_gpSyncXf()
	var gpRect: Rect2 = _gpXf.gpViewRect()
	# Pale panel fill + frame. / 淡色面板底 + 边框。
	gpC.draw_rect(gpRect, Color(0.12, 0.13, 0.16, 1.0), true)
	gpC.draw_rect(gpRect, Color(0.35, 0.38, 0.44, 1.0), false, 1.0)
	# Committed glyph shapes. / 已提交图元几何。
	if not gpShapes.is_empty():
		var gpSpec: Dictionary = GPShapeSpec.gpBuild(gpShapes)
		var gpStroke: Color = GPSymbolPainter.gpCategoryColor(gpCategory)
		GPSymbolPainter.gpDrawShape(gpC, gpSpec, gpRect, Color(0.08, 0.09, 0.11, 1.0), gpStroke, 2.0)
	# Selection highlight around the selected primitive. / 选中图形的高亮框。
	if gpSelShape >= 0 and gpSelShape < gpShapes.size():
		var gpB: Rect2 = gpShapes[gpSelShape].gpBBox().grow(GP_MIN_LEN)
		var gpA0: Vector2 = gpAuthorToLocal(gpB.position)
		var gpA1: Vector2 = gpAuthorToLocal(gpB.position + gpB.size)
		gpC.draw_rect(Rect2(gpA0, gpA1 - gpA0).abs(), Color(1.0, 0.85, 0.2), false, 1.5)
	# Ports (connection points). / 连接端点。
	for gpI in range(gpPorts.size()):
		var gpP: GPPort = gpPorts[gpI]
		var gpL: Vector2 = gpPortLocal(gpP.gpPos)
		var gpCol: Color = Color(1.0, 1.0, 1.0) if gpI == gpSelPort else Color(0.4, 0.9, 1.0)
		gpC.draw_circle(gpL, 4.0, gpCol)
		if gpP.gpDir != Vector2.ZERO:
			gpC.draw_line(gpL, gpL + gpP.gpDir * 12.0, gpCol, 1.5)
	# Tool transient overlay (draft shape / in-progress polyline). / 工具瞬态覆盖层（草稿图形 / 进行中折线）。
	if _gpActiveTool != null:
		_gpActiveTool.gpDrawOverlay(gpC)


# ---- serialization ----
# 序列化

# Convert the working ports (normalized 0..1) into author-space pixels for the save dict, using the
# SAME bbox + envelope the normalizer will recompute from the saved shapes, so the round-trip is exact.
# 把工作端口（归一化 0..1）换算为保存字典所需的作者空间像素；用与 GPSymbolNormalizer 从已保存图形
# 重算时「同一 bbox + 包络」，使往返精确无漂移。
func gpAuthorPorts(gpCat: String = "") -> Array:
	if gpCat == "":
		gpCat = gpCategory
	var gpShapesDict: Dictionary = GPShapeSpec.gpEditSpec(gpShapes)
	var gpBBox: Rect2 = GPSymbolNormalizer.gpComputeBBox(gpShapesDict)
	var gpEnv: Vector2 = GPSymbolCategories.gpSizeFor(gpCat)
	var gpPortDicts: Array = GPPortSpec.gpToDicts(gpPorts)
	for gpI in range(gpPortDicts.size()):
		var gpD: Dictionary = gpPortDicts[gpI] as Dictionary
		if str(gpD.get("name", "")) == "":
			gpD["name"] = "p%d" % (gpI + 1)
	return GPSymbolNormalizer.gpDenormalizePorts(gpPortDicts, gpBBox, gpEnv)
