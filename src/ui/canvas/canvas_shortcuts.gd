# ============================================================================
# GPCanvasShortcuts — 画布键盘快捷键
# Canvas keyboard shortcuts .
#
# 承接画布的共享快捷键（Delete / Ctrl+A / ESC / Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z）与渐进式 ESC
# 取消链。原先这段代码内联在 canvas_2d._gpOnKey() / _gpOnEscape 中，与输入分发、相机、绘制混在
# 一起；迁出后画布只剩「把按键交给快捷键委托」一行，与 P2 的其它委托（overlay / 注释编辑 /
# 上下文菜单）保持同一种形状。
# Owns the canvas's shared shortcuts (Delete / Ctrl+A / ESC / Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z)
# canvas_2d._gpOnKey() / _gpOnEscape, mixed in with input dispatch, camera and painting. After
# the move the canvas is left with a single line — "hand the key to the shortcuts delegate" —
# matching the shape of the other P2 delegates (overlay / annotation editor / context menu).
#
# 本委托只经公开端口访问画布（gpRequest* / gpSetSelection() / gpMarq / gpAnno / gpUndo() / gpRedo()），
# 不读任何 _gp* 私有字段。
# This delegate reaches the canvas only through public ports (gpRequest* / gpSetSelection() /
# gpMarq / gpAnno / gpUndo() / gpRedo()) and reads no _gp* private field.
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
 # A selected bump anchor takes priority: Del removes just that anchor, not the whole edge.
 # 选中的鼓包锚点优先：Del 只删该锚点，而非整条边。
			var gpBump: Dictionary = gpCv.gpEdgeGrips.gpSelectedBump()
			if not gpBump.is_empty():
				gpCv.gpEdgeGrips.gpDeleteBump(gpBump.get("eid", ""), int(gpBump.get("ai", -1)))
				return true
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
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			# Arrow keys nudge the selection (A8). Shift = ten steps, so a coarse move needs no
			# menu; a mounted child is skipped by the intent (its position is derived).
			# 方向键微调选择（A8）。Shift = 十步，使粗调不必开菜单；挂载子件由意图排除（位置是推导的）。
			if gpCtrl:
				return false
			var gpStep: float = 10.0 if gpKey.shift_pressed else 1.0
			var gpDelta: Vector2 = Vector2.ZERO
			match gpKey.keycode:
				KEY_LEFT:
					gpDelta = Vector2(-gpStep, 0.0)
				KEY_RIGHT:
					gpDelta = Vector2(gpStep, 0.0)
				KEY_UP:
					gpDelta = Vector2(0.0, -gpStep)
				KEY_DOWN:
					gpDelta = Vector2(0.0, gpStep)
			gpCv.gpRequestNudgeSelection(gpDelta)
			return true
		KEY_C:
			# Ctrl/Cmd+C copies the current selection into the app-wide clipboard, which survives a
			# SHEET SWITCH — that is the entire point of A6.
			# Ctrl/Cmd+C 把当前选择复制进应用级剪贴板，它跨**图纸切换**存活 —— 这正是 A6 的全部意义。
			if gpCtrl:
				gpCv.gpRequestCopySelected()
				return true
		KEY_V:
			# Ctrl/Cmd+V pastes into the ACTIVE sheet as one undo step, then selects the result so
			# the very next drag places it where the user wants.
			# Ctrl/Cmd+V 粘贴到**活动**图纸（一步撤销），随后选中结果，使用户接下来一拖就能摆到位。
			if gpCtrl:
				gpCv.gpRequestPasteClipboard()
				return true
		KEY_R:
			# R rotates clockwise by a quarter turn (the drafting convention); Shift+R turns the
			# other way, so a shape never needs four presses to come back.
			# R 顺时针转四分之一圈（制图惯例）；Shift+R 反向，使图形不必按四次才能转回来。
			if gpCtrl:
				return false
			gpCv.gpRequestRotateSelected(-90.0 if gpKey.shift_pressed else 90.0)
			return true
		KEY_M:
			# M mirrors horizontally; pressing it again is a real (undoable) edit that puts the
			# symbol back, which is why the intent toggles instead of setting.
			# M 水平镜像；再按一次是真实（可撤销）的编辑、把图元放回，故该意图是**开关**而非置位。
			if gpCtrl:
				return false
			gpCv.gpRequestMirrorSelected()
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
	# P3-4: the in-place tag editor is the innermost layer — close it before anything else so a
	# half-typed number is never stranded on screen. / 就地位号编辑器是最内层，先关闭它。
	# Rev.3 stage 1.5: the NODE tag editor is the SAME innermost layer.
	# Rev.3 阶段 1.5：**图元**位号编辑器属同一最内层。
	if gpCv.gpEdgeEditor.gpIsEditing():
		gpCv.gpEdgeEditor.gpClose()
		gpCv.queue_redraw()
		return
	if gpCv.gpNodeEditor != null and gpCv.gpNodeEditor.gpIsEditing():
		gpCv.gpNodeEditor.gpClose()
		gpCv.queue_redraw()
		return
	# P3-4: an in-flight edge grip drag is abandoned next, before the tool/annotation cancels.
	# 边抓取点拖拽进行中，其次放弃，早于工具 / 注释取消。
	if gpCv.gpEdgeGrips.gpIsDragging():
		gpCv.gpEdgeGrips.gpEndDrag()
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
