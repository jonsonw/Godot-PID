class_name GPCanvasInputRouter
extends RefCounted
# Copyright © 2026 Jonson Wang
# input event routing; tool dispatch
# 输入事件路由与工具分派
#
# WHY THIS EXISTS / 为何存在（架构优化建议 §3.4）：
#   GPCanvas2D was carrying many unrelated responsibilities in one file; this coordinator
#   owns the "input event routing; tool dispatch" use case end to end, so the root keeps only
#   assembly and forwarding.
#   GPCanvas2D 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「输入事件路由与工具
#   分派」这一用例，使根类只保留装配与转发。
#
# Interaction / 交互方式：
#   - the root creates this coordinator and injects itself as gpHost (composition root);
#     根类创建本协调者并把自身注入为 gpHost（组合根装配）；
#   - the root forwards user actions here, never the other way round — this class drives the
#     host only through its public ports (GPCanvas2D.gp*);
#     根类把用户动作转发到此处，绝不反向 —— 本类只经宿主的公开端口（GPCanvas2D.gp*）驱动宿主；
#   - the root keeps every public port it had before: callers outside the canvas are unchanged.
#     根类保留其原有的每一个公开端口：画布外部的调用方零改动。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPCanvas2D = null

# ---- 输入侧委托与状态（架构优化 §3.4：随输入路由一起从画布迁入） ----
# ---- Input-side delegates and state (architecture §3.4: moved in with the input router) ----
# Right-click context-menu delegate: hit-test / menu build / action dispatch.
# 右键上下文菜单委托：命中判定 / 菜单构建 / 动作分发。
var _gpCtx: GPCanvasContextMenu = null
# Keyboard-shortcut delegate: shared shortcuts and the progressive-ESC chain.
# 键盘快捷键委托：共享快捷键与渐进式 ESC 链。
var _gpShortcuts: GPCanvasShortcuts = null
# Tool context + registry + six mode tools (P2/P3 split). CONNECT shares the select tool.
# 工具上下文 + 注册表 + 六个模式工具（P2/P3 拆分）。连线模式复用选择工具。
var _gpToolCtx: GPCanvasToolContext = null
var _gpRegistry: GPCanvasToolRegistry = null
var _gpSelectTool: GPSelectTool = null
var _gpPlaceTool: GPPlaceTool = null
var _gpDrawTool: GPDrawShapeTool = null
var _gpGripTool: GPGripTool = null
# P3 connectivity tools / P3 连线工具。
var _gpPipeTool: GPPipeTool = null
var _gpSignalTool: GPSignalTool = null
# Middle-button pan transient state. / 中键平移瞬态状态。
var _gpPanning: bool = false
var _gpPanStart: Vector2 = Vector2.ZERO
var _gpPanOffsetStart: Vector2 = Vector2.ZERO


# Build the input-side delegates, the tool registry and the six mode tools. Called from the
# canvas's _ready() (架构优化 §3.4): tools are pure input-dispatch implementation details, so
# they live with the router instead of bloating the root.
# 构建输入侧委托、工具注册表与六个模式工具。由画布的 _ready() 调用（架构优化 §3.4）：
# 工具只是输入分派的实现细节，故与路由同居，而不再撑大根类。
func gpBuildTools() -> void:
	_gpCtx = GPCanvasContextMenu.new(gpHost)
	_gpShortcuts = GPCanvasShortcuts.new(gpHost)
	_gpToolCtx = GPCanvasToolContext.new(gpHost)
	_gpRegistry = GPCanvasToolRegistry.new()
	_gpSelectTool = GPSelectTool.new()
	_gpPlaceTool = GPPlaceTool.new()
	_gpDrawTool = GPDrawShapeTool.new()
	_gpGripTool = GPGripTool.new()
	_gpPipeTool = GPPipeTool.new()
	_gpSignalTool = GPSignalTool.new()
	for gpT in [_gpSelectTool, _gpPlaceTool, _gpDrawTool, _gpGripTool, _gpPipeTool, _gpSignalTool]:
		gpT.gpCtx = _gpToolCtx
	_gpRegistry.gpRegister(GPCanvas2D.GPMode.GP_SELECT, _gpSelectTool)
	_gpRegistry.gpRegister(GPCanvas2D.GPMode.GP_CONNECT, _gpSelectTool)
	_gpRegistry.gpRegister(GPCanvas2D.GPMode.GP_DRAW_LINE, _gpDrawTool)
	_gpRegistry.gpRegister(GPCanvas2D.GPMode.GP_DRAW_CIRCLE, _gpDrawTool)
	_gpRegistry.gpRegister(GPCanvas2D.GPMode.GP_DRAW_RECT, _gpDrawTool)
	_gpRegistry.gpRegister(GPCanvas2D.GPMode.GP_DRAW_POLYLINE, _gpDrawTool)
	_gpRegistry.gpRegister(GPCanvas2D.GPMode.GP_DRAW_ARC, _gpDrawTool)
	_gpRegistry.gpRegister(GPCanvas2D.GPMode.GP_PIPE, _gpPipeTool)
	_gpRegistry.gpRegister(GPCanvas2D.GPMode.GP_SIGNAL, _gpSignalTool)


# Public: drop the selection set (used before swapping in another graph).
# 公开：清空选择集（用于换入另一张图之前）。
func gpClearSelection() -> void:
	gpHost.gpMarq.gpCancel()
	if _gpSelectTool != null:
		_gpSelectTool.gpCancelDrag()
	gpHost.gpShapeSel.clear()
	gpHost.gpSetSelection([])


# Ask the active interaction tool to abandon its half-finished state (ESC path). One
# generic port, so the canvas never needs to know which tool is currently mounted.
# 请求活动交互工具放弃其半成品状态（ESC 路径）。一个通用端口，使画布无需知道当前挂的是哪个工具。
func gpCancelActiveTool() -> bool:
	# Tag (位号) label drag: ESC must abandon it like every other drag.
	# 位号标签拖拽：ESC 必须像其它拖拽一样能放弃它。
	if gpHost.gpLabelGrips != null and gpHost.gpLabelGrips.gpIsDragging():
		gpHost.gpLabelGrips.gpCancelDrag()
		return true
	if gpHost.gpPortOps != null and gpHost.gpPortOps.gpIsDragging():
		gpHost.gpPortOps.gpCancelDrag()
		return true
	return gpActiveTool().gpCancel()


func gpOnLeftUp(gpScreen: Vector2) -> void:
	var gpWorld: Vector2 = gpHost.gpViewController.gpWorldFromScreen(gpScreen)
	# Finish an endpoint-anchor drag (connect) or turn it into a pick.
	# 结束端点锚点拖拽（连线），或把它转成一次拾取。
	if gpHost.gpPortOps != null and gpHost.gpPortOps.gpIsDragging():
		gpHost.gpPortOps.gpFinishDrag()
		return
	# Grip / whole-shape drag belongs to GPGripTool (P2 split).
	# 锚点 / 整图形拖拽由 GPGripTool 负责（P2 拆分）。
	if gpHost.gpAnno.gpIsDragging():
		_gpGripTool.gpOnRelease(gpWorld)
		return
	# Edge grip / route drag belongs to GPGripTool too (P3-4).
	# 边抓取点 / 布线拖拽同样由 GPGripTool 负责（P3-4）。
	if gpHost.gpEdgeGrips.gpIsDragging():
		_gpGripTool.gpOnRelease(gpWorld)
		return
	# Tag (位号) label grip release (M10b): commit as ONE undo step. Without this branch the
	# release fell through to the select tool and the drag was never recorded at all.
	# 位号标签抓取点释放（M10b）：提交为**一个**撤销步。缺此分支，释放会落到选择工具上，
	# 这次拖拽从未被记录。
	if gpHost.gpLabelGrips != null and gpHost.gpLabelGrips.gpIsDragging():
		gpHost.gpLabelGrips.gpEndGripDrag()
		gpHost.accept_event()
		return
	# Everything else (draw commit / marquee / group drag) is dispatched to the active tool.
	# 其余（提交绘图 / 框选 / 整组拖拽）分派给活动工具。
	gpActiveTool().gpOnRelease(gpWorld)


# Return the interaction tool for the current dispatch target: a pending palette placement wins
# over the mode; otherwise the registry maps GPMode -> tool (CONNECT shares the select tool). The
# canvas exposes only public ports now that transient drag state lives in each tool.
# 返回当前分派目标的交互工具：调色板待放置优先于模式；否则注册表按 GPMode 映射（CONNECT 复用
# 选择工具）。瞬态拖拽状态现由各工具自持，画布仅经 gpCtx.gpCv 暴露公开端口。
func gpActiveTool() -> GPCanvasTool:
	if gpHost.gpPendingDef != null:
		return _gpPlaceTool
	return _gpRegistry.gpGet(gpHost.gpMode)


# Handle a left mouse button press.
# 处理鼠标左键按下。
# [param gpShift] Shift held -> additive selection instead of a fresh one.
# [param gpShift] 按住 Shift → 追加选择而非重新选择。
# [param gpDouble] second click of a double click -> open the in-place block editor.
# [param gpDouble] 双击的第二次点击 → 打开就地块编辑器。
func gpOnLeftDown(gpScreen: Vector2, gpShift: bool, gpDouble: bool) -> void:
	var gpWorld: Vector2 = gpHost.gpViewController.gpWorldFromScreen(gpScreen)
	# An endpoint anchor is the smallest, most precise target on the sheet, so it wins over the
	# node, the edge and the marquee — but only when a symbol is selected (that is when anchors
	# are shown at all).
	# 端点锚点是图纸上最小、最需精确点中的目标，故它优先于节点、连线与框选 ——
	# 但仅在有图元被选中时（只有那时锚点才会显示）。
	if gpHost.gpPortOps != null and gpHost.gpPortOps.gpTryStartDrag(gpWorld):
		gpHost.queue_redraw()
		return
	gpActiveTool().gpOnPress(gpWorld, gpShift, gpDouble)


# ============================ input ============================
# ============================ 输入 ============================
# Handle all mouse and keyboard input for the canvas. Godot calls GPCanvas2D._gui_input, which
# forwards here — the virtual itself must stay on the Control.
# 处理画布的全部鼠标与键盘输入。Godot 调用 GPCanvas2D._gui_input 并转发到此处 ——
# 虚方法本身必须留在 Control 上。
func gpOnGuiInput(gpEvent: InputEvent) -> void:
	if gpEvent is InputEventMouseButton:
		var gpMouseEvent: InputEventMouseButton = gpEvent as InputEventMouseButton
		# Mouse wheel zooms in/out at the cursor position.
		# 鼠标滚轮在光标位置缩放。
		if gpMouseEvent.button_index == MOUSE_BUTTON_WHEEL_UP or gpMouseEvent.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# P3-4: while the in-place tag editor is open, pan/zoom must stay frozen so the
			# field cannot drift off the pipe it labels. / 边位号编辑器打开期间冻结缩放。
			if gpHost.gpEdgeEditor != null and gpHost.gpEdgeEditor.gpIsEditing():
				return
			if gpMouseEvent.pressed:
				var gpFactor: float = 1.0 if gpMouseEvent.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				gpHost.gpViewController.gpZoomAt(gpMouseEvent.position, gpFactor)
			gpHost.accept_event()
			return
		# Middle button starts/ends panning.
		# 中键开始/结束平移。
		if gpMouseEvent.button_index == MOUSE_BUTTON_MIDDLE:
			# P3-4: freeze panning while editing the tag too. / 编辑位号时同样冻结平移。
			if gpHost.gpEdgeEditor != null and gpHost.gpEdgeEditor.gpIsEditing():
				return
			if gpMouseEvent.pressed:
				_gpPanning = true
				_gpPanStart = gpMouseEvent.position
				_gpPanOffsetStart = gpHost.gpViewOffset
			else:
				_gpPanning = false
			gpHost.accept_event()
			return
		# Left button places, selects or connects symbols.
		# 左键放置、选择或连接图元。
		if gpMouseEvent.button_index == MOUSE_BUTTON_LEFT:
			if gpMouseEvent.pressed:
				gpOnLeftDown(gpMouseEvent.position, gpMouseEvent.shift_pressed, gpMouseEvent.double_click)
			else:
				gpOnLeftUp(gpMouseEvent.position)
			gpHost.accept_event()
			return
		# Right button opens the context menu.
		# 右键打开上下文菜单。
		if gpMouseEvent.button_index == MOUSE_BUTTON_RIGHT:
			if gpMouseEvent.pressed:
				_gpCtx.gpOnRightDown(gpMouseEvent.position)
			gpHost.accept_event()
			return

	# Keyboard shortcuts (Delete / Ctrl+A / ESC).
	# 键盘快捷键（Delete / Ctrl+A / ESC）。
	if gpEvent is InputEventKey:
		var gpKey: InputEventKey = gpEvent as InputEventKey
		if gpKey.pressed and not gpKey.echo:
			# The active tool gets first crack (e.g. Enter confirms a polyline); the canvas then
			# handles the shared shortcuts (Delete / Ctrl+A / ESC).
			# 活动工具优先处理（如 Enter 确认折线）；随后画布处理共享快捷键（Delete / Ctrl+A / ESC）。
			if gpActiveTool().gpOnKey(gpKey):
				gpHost.accept_event()
				return
			if _gpShortcuts.gpHandleKey(gpKey):
				gpHost.accept_event()
				return

	if gpEvent is InputEventMouseMotion:
		var gpMotion: InputEventMouseMotion = gpEvent as InputEventMouseMotion
		gpHost._gpLastMouseWorld = gpHost.gpViewController.gpWorldFromScreen(gpMotion.position)
		# Panning in progress.
		# 正在平移。
		if _gpPanning:
			gpHost.gpViewOffset = _gpPanOffsetStart + (gpMotion.position - _gpPanStart)
			gpHost.gpViewController.gpApplyCamera()
			gpHost.queue_redraw()
			gpHost.gpEmitStatus()
			gpHost.accept_event()
			return
		# Marquee in progress: track the rubber band.
		# 正在框选：跟踪橡皮筋。
		if gpHost.gpMarq.gpActive:
			gpHost.gpMarq.gpUpdate(gpMotion.position)
			gpHost.queue_redraw()
			gpHost.accept_event()
			return
		# Grip / whole-shape drag is owned by GPGripTool (P2 split).
		# 锚点 / 整图形拖拽由 GPGripTool 负责（P2 拆分）。
		if gpHost.gpAnno.gpIsDragging():
			_gpGripTool.gpOnMove(gpHost.gpViewController.gpWorldFromScreen(gpMotion.position))
			gpHost.accept_event()
			return
		# Edge grip / route drag is also owned by GPGripTool (P3-4). It is checked AFTER the
		# annotation drag so the two never fight over the same motion event.
		# 边抓取点 / 布线拖拽同样由 GPGripTool 负责（P3-4）。它在注释拖拽之后检查，
		# 使两者不会争抢同一移动事件。
		if gpHost.gpEdgeGrips.gpIsDragging():
			_gpGripTool.gpOnMove(gpHost.gpViewController.gpWorldFromScreen(gpMotion.position))
			gpHost.accept_event()
			return
		# Tag (位号) label grip drag (M10b). Checked before the port anchors so the two never
		# fight over the same motion event; without this branch the label never followed.
		# 位号标签抓取点拖拽（M10b）。在端点锚点之前检查，使两者不争抢同一移动事件；
		# 缺这个分支，标签根本不会跟随。
		if gpHost.gpLabelGrips != null and gpHost.gpLabelGrips.gpIsDragging():
			gpHost.gpLabelGrips.gpOnGripMove(gpHost.gpViewController.gpWorldFromScreen(gpMotion.position))
			gpHost.accept_event()
			return
		# Endpoint-anchor drag (port-to-port connect). / 端点锚点拖拽（端对端连线）。
		if gpHost.gpPortOps != null and gpHost.gpPortOps.gpIsDragging():
			gpHost.gpPortOps.gpUpdateDrag(gpHost.gpViewController.gpWorldFromScreen(gpMotion.position))
			gpHost.queue_redraw()
			gpHost.accept_event()
			return
		# M10b: a move cursor over the tag grip. The handle is 9 px wide and sits OUTSIDE the
		# glyph, so without feedback nobody ever finds it to drag it.
		# M10b：抓取点上方显示移动光标。手柄仅 9 px 宽且位于字形**之外**，
		# 没有反馈没人找得到它、更别说拖它。
		if gpHost.gpLabelGrips != null and gpHost.gpLabelGrips.gpUpdateHoverCursor(gpHost.gpViewController.gpWorldFromScreen(gpMotion.position)):
			gpHost.accept_event()
			return
		# Hover highlight for the anchor under the cursor (outside any drag).
		# 光标下锚点的悬停高亮（拖拽之外）。
		if gpHost.gpPortOps != null:
			gpHost.gpPortOps.gpUpdateHover(gpHost.gpViewController.gpWorldFromScreen(gpMotion.position))
		# Tool-specific rubber band / connect preview (select = connect preview, draw = rubber band).
		# The tool returns true when it consumed the motion (e.g. rubber band) so we accept it.
		# 工具专属橡皮筋 / 连接预览（select=连接预览，draw=橡皮筋）。工具消费了移动事件时返回
		# true，画布据此 accept_event()。
		if gpActiveTool().gpOnMove(gpHost.gpViewController.gpWorldFromScreen(gpMotion.position)):
			gpHost.accept_event()
			return
