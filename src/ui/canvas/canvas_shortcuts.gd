# ============================================================================
# GPCanvasShortcuts — 画布键盘快捷键（M4 续 · 自 canvas_2d 迁出）
# Canvas keyboard shortcuts (M4 cont · moved out of canvas_2d).
#
# 承接画布的共享快捷键（Delete / Ctrl+A / ESC / Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z）与渐进式 ESC
# 取消链。原先这段代码内联在 canvas_2d._gpOnKey / _gpOnEscape 中，与输入分发、相机、绘制混在
# 一起；迁出后画布只剩「把按键交给快捷键委托」一行，与 P2 的其它委托（overlay / 注释编辑 /
# 上下文菜单）保持同一种形状。
# Owns the canvas's shared shortcuts (Delete / Ctrl+A / ESC / Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z)
# and the progressive-ESC cancellation chain. This code used to be inline in
# canvas_2d._gpOnKey / _gpOnEscape, mixed in with input dispatch, camera and painting. After
# the move the canvas is left with a single line — "hand the key to the shortcuts delegate" —
# matching the shape of the other P2 delegates (overlay / annotation editor / context menu).
#
# 本委托只经公开端口访问画布（gpRequest* / gpSetSelection / gpMarq / gpAnno / gpUndo / gpRedo），
# 不读任何 _gp* 私有字段。
# This delegate reaches the canvas only through public ports (gpRequest* / gpSetSelection /
# gpMarq / gpAnno / gpUndo / gpRedo) and reads no _gp* private field.
# ============================================================================

class_name GPCanvasShortcuts
extends RefCounted

const GPMode = GPCanvasInteractState.GPMode

# The canvas that owns interaction state. / 持有交互状态的画布。
var gpCv: GPCanvas2D


# Build the delegate around its owner canvas.
# 围绕宿主画布构造本委托。
func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# Handle a shared canvas shortcut. Returns true when the event was consumed.
# 处理共享画布快捷键。事件被消费时返回 true。
# [param gpKey] the key event / 按键事件
func gpHandleKey(gpKey: InputEventKey) -> bool:
	# Cmd on macOS, Ctrl elsewhere: one predicate for both, so the same muscle memory works.
	# macOS 上的 Cmd 与其它平台的 Ctrl：统一为一个判据，使同一套肌肉记忆都成立。
	var gpCtrl: bool = gpKey.ctrl_pressed or gpKey.meta_pressed
	match gpKey.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			gpCv.gpRequestDeleteSelected()
			return true
		KEY_A:
			if gpCtrl:
				gpCv.gpRequestSelectAll()
				return true
		KEY_Z:
			if gpCtrl:
				# Ctrl+Z undoes; Ctrl+Shift+Z redoes — the spelling every other editor uses,
				# so it needs no discoverability effort from the user.
				# Ctrl+Z 撤销；Ctrl+Shift+Z 重做 —— 所有编辑器通用的写法，无需用户额外学习。
				if gpKey.shift_pressed:
					gpCv.gpRedo()
				else:
					gpCv.gpUndo()
				return true
		KEY_Y:
			if gpCtrl:
				# Windows/Linux muscle memory for redo. / Windows / Linux 上重做的习惯键。
				gpCv.gpRedo()
				return true
		KEY_ESCAPE:
			gpOnEscape()
			return true
	return false


# Progressive ESC: cancel the innermost pending action first, and only clear the selection
# when nothing else is pending. Returning early is what keeps a half-drawn state recoverable.
# 渐进式 ESC：先取消最内层的待处理动作，只有在别无待处理项时才清空选择。提前返回正是
# 让半完成状态可回退的原因。
func gpOnEscape() -> void:
	if gpCv.gpPendingDef != null:
		gpCv.gpPendingDef = null
		gpCv.queue_redraw()
		return
	# One generic port instead of the canvas knowing which tool is which: the select tool
	# abandons its group drag here, the draw tool drops its half-finished primitive.
	# 一个通用端口取代「画布认识每个工具」：选择工具在此放弃整组拖拽，
	# 绘图工具在此丢弃半成品图元。
	if gpCv.gpCancelActiveTool():
		gpCv.queue_redraw()
		return
	if gpCv.gpAnno.gpIsDragging():
		gpCv.gpAnno.gpEndDrag()
		gpCv.queue_redraw()
		return
	if gpCv.gpMarq.gpActive:
		gpCv.gpMarq.gpCancel()
		gpCv.queue_redraw()
		return
	if gpCv.gpConnectFrom != "":
		gpCv.gpConnectFrom = ""
		gpCv.queue_redraw()
		return
	if not gpCv.gpSelection.is_empty() or not gpCv.gpShapeSel.is_empty():
		gpCv.gpSetSelection([])
		gpCv.gpShapeSel.clear()
