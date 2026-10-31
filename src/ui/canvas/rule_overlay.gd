class_name GPRuleOverlay
extends Control
# Copyright © 2026 Jonson Wang
#
# Screen-space DRC badges (ADR-39 E03): a small, constant-size marker at every finding's world
# position, drawn ABOVE the canvas and independent of zoom. The badge is deliberately not a
# canvas primitive: a canvas-space circle would grow/shrink with zoom and become unreadable.
# 屏幕空间 DRC 角标（ADR-39 E03）：在每条发现的世界位置画一个**固定尺寸**的标记，画在画布之上，
# 与缩放无关。它刻意不是画布图元：画布空间的圆会随缩放变大/变小，直至不可读。
#
# The overlay never eats input: it is a pure indicator. Clicking still belongs to the canvas and
# the DRC panel / dialog rows (which have the precise finding).
# 覆盖层从不吃输入：它只是指示器。点击仍归画布与 DRC 面板 / 弹窗行（它们持有精确发现）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_RADIUS: float = 5.0
const GP_RING: float = 2.0

var gpCanvas: GPCanvas2D = null
var gpFindings: Array[GPFinding] = []
var gpSheetId: String = ""

# Optional transient highlight for a sheet-level finding (title block / frame), which has no
# graph node to select. ``has`` is separate from an empty Rect2 because Rect2() is a valid value.
# 可选的瞬时高亮，用于图签 / 图框这类没有图节点可选的图纸级发现。用独立布尔量区分空矩形。
var gpFocusRect: Rect2 = Rect2()
var gpHasFocusRect: bool = false

var _gpRedrawClock: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	set_process(true)


# Attach to the active canvas (reparenting keeps ONE overlay for the whole window).
# 绑定到活动画布（重挂父节点，使整个窗口只有一个覆盖层）。
func gpAttach(gpCanvasIn: GPCanvas2D) -> void:
	if gpCanvasIn == null:
		return
	if get_parent() != gpCanvasIn:
		if get_parent() != null:
			get_parent().remove_child(self)
		gpCanvasIn.add_child(self)
	gpCanvas = gpCanvasIn
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


# Replace the badge set. Findings with no world position or belonging to another sheet are skipped.
# 替换角标集合。无世界坐标或属于其它图纸的发现被跳过。
func gpShow(gpFindingsIn: Array[GPFinding], gpSheetIdIn: String = "") -> void:
	gpFindings = gpFindingsIn.duplicate()
	gpSheetId = gpSheetIdIn
	gpHasFocusRect = false
	queue_redraw()


# Show a transient world-rect outline (title block / frame) until the next gpShow / clear.
# 显示瞬时世界矩形轮廓（图签 / 图框），直到下一次 gpShow / clear。
func gpShowFocusRect(gpRect: Rect2) -> void:
	gpFocusRect = gpRect
	gpHasFocusRect = gpRect.size.x > 0.0 and gpRect.size.y > 0.0
	queue_redraw()


func _process(gpDelta: float) -> void:
	# The camera is a pure value proxy with no change signal, so poll at ~10 Hz. Badges must
	# follow pan/zoom; 10 Hz is invisible to the eye and far cheaper than a per-frame redraw.
	# 相机是纯值代理、无变化信号，故以 ~10Hz 轮询。角标须跟随平移/缩放；10Hz 肉眼不可见，
	# 且远比重绘每帧便宜。
	if gpCanvas == null or gpFindings.is_empty():
		return
	_gpRedrawClock += gpDelta
	if _gpRedrawClock >= 0.1:
		_gpRedrawClock = 0.0
		queue_redraw()


func _draw() -> void:
	if gpCanvas == null:
		return
	if gpHasFocusRect:
		var gpA: Vector2 = gpCanvas.gpScreenFromWorld(gpFocusRect.position)
		var gpB: Vector2 = gpCanvas.gpScreenFromWorld(gpFocusRect.end)
		draw_rect(Rect2(gpA, gpB - gpA), Color(0.35, 0.8, 1.0, 0.95), false, 2.0)
	for gpF in gpFindings:
		if gpF == null or gpF.gpWorld == Vector2.INF:
			continue
		if gpSheetId != "" and gpF.gpSheetId != "" and gpF.gpSheetId != gpSheetId:
			continue
		var gpP: Vector2 = gpCanvas.gpScreenFromWorld(gpF.gpWorld)
		var gpColor: Color = _gpColor(gpF.gpSeverity)
		draw_circle(gpP, GP_RADIUS + GP_RING, Color(0.08, 0.10, 0.13, 0.85))
		draw_circle(gpP, GP_RADIUS, gpColor)


static func _gpColor(gpSev: String) -> Color:
	match gpSev:
		GPFinding.GP_ERROR:
			return Color(0.95, 0.35, 0.35)
		GPFinding.GP_WARNING:
			return Color(0.95, 0.72, 0.25)
		_:
			return Color(0.38, 0.72, 0.88)
