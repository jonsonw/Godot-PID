class_name GPDwellPrompt
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Dwell trigger for the "finish this line at an open end" prompt (B08 follow-up).
# 「把这条线结束于开口端」提示的**悬停触发**（B08 续）。
#
# Why dwell and not right-click / 为何用悬停而非右键：
# a right click while a line is half-drawn competes with the context menu (and with whatever the
# window manager does), and the user's own proposal was the better one: STOP MOVING and the choice
# appears, KEEP MOVING and it disappears. Dwell is unambiguous because it is a property of the
# gesture itself, not of a button.
# 画线中途右键会与上下文菜单（甚至窗口管理器）争夺解释权，而用户自己提的方案更好：
# **停住**就出现选项，**继续移动**就消失。悬停没有歧义，因为它是手势本身的属性，不是某个按键的。
#
# The state machine (this class, UI-free so it is testable) / 状态机（本类，无界面，故可测）：
#   idle  --first movement-->  tracking(anchor = that position)
#   tracking --DELAY ms of stillness-->  shown
#   shown --movement beyond HOLD radius-->  idle (re-armed)
#   any --tool not pending-->  idle
#   idle --笔尖不动--> tracking（等）
# 状态：空闲 → 跟踪（锚点=该位置）→ 静止够久 → 显示 → 移出保持半径 → 空闲（重新武装）。
#
# WHY the shown state tolerates small movement / 为何「显示」态容忍小幅移动：
# the prompt is drawn NEXT to the cursor; clicking it requires moving onto it. A prompt that hides
# on the first pixel of movement can never be clicked — the hold radius is what makes it usable
# without making it sticky.
# 提示画在光标**旁边**；点它必须把鼠标移过去。第一像素就消失的提示永远点不到 ——
# 保持半径正是「能用」与「粘住」之间的那条线。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Stillness required before the prompt appears, in milliseconds.
# 提示出现前需要的静止时长（毫秒）。
const GP_DELAY_MS: int = 450

# Movement smaller than this (screen pixels) does not count as "moving" while tracking.
# 跟踪态下小于此值（屏幕像素）的移动不算「在动」。
const GP_MOVE_EPS: float = 2.0

# Once shown, the prompt survives movement up to this radius (screen pixels) from the anchor.
# 显示后，提示在锚点此半径（屏幕像素）内的移动中保持存在。
const GP_HOLD_RADIUS: float = 26.0

# The prompt should be shown at this world position.
# 应在此世界坐标显示提示。
signal gpShow(gpWorld: Vector2)

# The prompt should be hidden.
# 应隐藏提示。
signal gpHide()

# Anchor of the current still position (world). Vector2.INF when tracking has not started.
# 当前静止位置的锚点（世界）。尚未开始跟踪时为 Vector2.INF。
var _gpAnchor: Vector2 = Vector2.INF

# Screen position of the anchor (used for the movement test — screen pixels are what the user
# actually feels, and they are zoom-independent).
# 锚点的屏幕位置（用于移动判定 —— 屏幕像素才是用户的真实手感，且与缩放无关）。
var _gpAnchorScreen: Vector2 = Vector2.INF

# When the current still stretch began (ticks msec).
# 当前静止段开始的时刻（毫秒）。
var _gpStillSince: int = 0

# Whether the prompt is currently shown.
# 提示当前是否显示。
var _gpShown: bool = false

# Whether a new stillness may trigger a show (re-armed by real movement / by reset).
# 新的静止是否允许再次触发显示（由真实移动 / reset 重新武装）。
var _gpArmed: bool = true


# Reset to idle: hide if shown, forget the anchor.
# 回到空闲：若已显示则隐藏，并忘掉锚点。
func gpReset() -> void:
	if _gpShown:
		_gpShown = false
		gpHide.emit()
	_gpAnchor = Vector2.INF
	_gpAnchorScreen = Vector2.INF
	_gpStillSince = 0
	_gpArmed = true


# Report a cursor position (called on every mouse motion).
# 报告一次光标位置（每次鼠标移动调用）。
func gpNoticeCursor(gpWorld: Vector2, gpScreen: Vector2, gpNowMs: int) -> void:
	if _gpAnchor == Vector2.INF:
		_gpAnchor = gpWorld
		_gpAnchorScreen = gpScreen
		_gpStillSince = gpNowMs
		return
	var gpMoved: float = gpScreen.distance_to(_gpAnchorScreen)
	if gpMoved <= GP_MOVE_EPS:
		# Sub-pixel jitter: still the same still stretch.
		# 亚像素抖动：仍属同一段静止。
		return
	if _gpShown and gpMoved <= GP_HOLD_RADIUS:
		# Moving towards the prompt itself: keep it (and keep the anchor, so the distance is
		# measured from where the user stopped, not from the latest sample).
		# 正朝提示移动：保持显示（并保持锚点，使距离从「用户停下的地方」量起，而非最新采样点）。
		return
	# Real movement: hide (if shown) and re-arm on the new position.
	# 真实移动：隐藏（若在显示）并在新位置重新武装。
	if _gpShown:
		_gpShown = false
		gpHide.emit()
	_gpAnchor = gpWorld
	_gpAnchorScreen = gpScreen
	_gpStillSince = gpNowMs
	_gpArmed = true


# Advance time. Shows the prompt when the line is still pending and the cursor has been still long
# enough; hides it as soon as the tool is no longer pending (committed / cancelled / mode changed).
# 推进时间。当连线仍待完成且光标静止够久时显示提示；一旦工具不再待完成（已提交 / 已取消 / 换模式）
# 立即隐藏。
func gpTick(gpPending: bool, gpNowMs: int) -> void:
	if not gpPending:
		gpReset()
		return
	if _gpAnchor == Vector2.INF or not _gpArmed or _gpShown:
		return
	if gpNowMs - _gpStillSince < GP_DELAY_MS:
		return
	_gpShown = true
	_gpArmed = false
	gpShow.emit(_gpAnchor)


# Whether the prompt is visible (for tests and for the canvas' keyboard shortcut).
# 提示是否可见（供测试与画布快捷键判断）。
func gpIsShown() -> bool:
	return _gpShown


# Anchor the prompt is (or would be) shown at.
# 提示所在（或将要所在）的锚点。
func gpAnchorWorld() -> Vector2:
	return _gpAnchor
