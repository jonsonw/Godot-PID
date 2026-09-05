# GPDpiWindow pure window/DPI policy tests (P1-2b).
# Tests: content_scale pinning, maximize decision, cross-screen change detection.
# 纯窗口/DPI 策略单测（P1-2b）：csf 钉 1.0、最大化决策、跨屏检测。
class_name GPTestDpiWindow
extends "res://tests/gp_test.gd"


func gpTestPinContentScale() -> void:
	# csf != 1.0 -> pinned to 1.0, returns true.
	var gpWin: Window = Window.new()
	gpWin.content_scale_factor = 2.0
	var gpChanged: bool = GPDpiWindow.gpPinContentScale(gpWin)
	gpCheck(gpChanged, "csf pinned should report change")
	gpCheck(is_equal_approx(gpWin.content_scale_factor, 1.0), "csf pinned to 1.0")
	# Already 1.0 -> no change.
	var gpChanged2: bool = GPDpiWindow.gpPinContentScale(gpWin)
	gpCheck(not gpChanged2, "already 1.0 should not report change")
	# null window -> false, no crash.
	gpCheck(not GPDpiWindow.gpPinContentScale(null), "null window -> false")
	gpWin.queue_free()


func gpTestShouldMaximize() -> void:
	var gpWin: Window = Window.new()
	gpWin.mode = Window.MODE_WINDOWED
	gpCheck(GPDpiWindow.gpShouldMaximize(gpWin), "windowed -> should maximize")
	gpWin.mode = Window.MODE_MAXIMIZED
	gpCheck(not GPDpiWindow.gpShouldMaximize(gpWin), "maximized -> should not maximize")
	gpWin.mode = Window.MODE_FULLSCREEN
	gpCheck(not GPDpiWindow.gpShouldMaximize(gpWin), "fullscreen -> should not maximize")
	gpCheck(not GPDpiWindow.gpShouldMaximize(null), "null window -> false")
	gpWin.queue_free()


func gpTestCrossScreenChange() -> void:
	var gpWin: Window = Window.new()
	gpWin.current_screen = 1
	# last screen 0 -> change detected.
	gpCheck(GPDpiWindow.gpIsCrossScreenChange(gpWin, 0), "screen 0->1 is a change")
	# last screen 1 -> no change.
	gpCheck(not GPDpiWindow.gpIsCrossScreenChange(gpWin, 1), "same screen is not a change")
	# last screen -1 (unknown) -> false (no prior screen).
	gpCheck(not GPDpiWindow.gpIsCrossScreenChange(gpWin, -1), "no prior screen -> false")
	gpCheck(GPDpiWindow.gpCurrentScreen(gpWin) == 1, "current screen reported")
	gpCheck(GPDpiWindow.gpCurrentScreen(null) == -1, "null window -> -1")
	gpWin.queue_free()
