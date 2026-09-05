class_name GPDpiWindow
extends RefCounted
# Window / HiDPI / multi-monitor POLICY helpers (P1-2b).
#
# Pure, headless-testable window-management decisions that main_window delegates to:
#  - content_scale_factor must be pinned to 1.0 (Godot 4 on macOS already reports window geometry
#    in LOGICAL POINTS and renders the backing store at the display's native pixel ratio; setting
#    content_scale_factor = screen scale DOUBLE-COUNTS the Retina scale and clips the UI).
#  - maximize only when the window is not already maximized / fullscreen.
#  - cross-screen change detection given the last screen index.
#
# The module takes a Window purely as a parameter (it never instantiates one), so it stays free of
# scene/UI plumbing. The UI-side side effects (font re-apply, split re-apply, deferred layout,
# last-screen tracking) remain in the caller.
#
# 窗口 / HiDPI / 多显示器「策略」辅助（P1-2b）。
# 纯窗口管理决策、可 headless 单测，由 main_window 委托：csf 须钉 1.0、仅在未最大化/全屏时最大化、
# 给定上一屏幕号判断是否跨屏。模块把 Window 仅作参数接收（不实例化），故不依赖场景/UI 布线；
# 字体重刷、分隔重排、延迟布局、上一屏记录等 UI 副作用仍在调用方。
#
# Coding rule: every variable declares its type explicitly (including container types).
# 编码规范：所有变量均显式声明类型（含容器类型）。


# Pin the window's content_scale_factor to 1.0 if it isn't already. Returns true when it changed
# (so the caller knows the backing store / layout needs refreshing).
# 若窗口 content_scale_factor 非 1.0 则钉回 1.0。返回是否改动（调用方据此判断是否需要刷新背板/布局）。
static func gpPinContentScale(gpWin: Window) -> bool:
	if gpWin == null:
		return false
	if not is_equal_approx(1.0, gpWin.content_scale_factor):
		gpWin.content_scale_factor = 1.0
		return true
	return false


# Whether the window should be maximized (i.e. it is NOT already maximized or fullscreen). Only
# maximize then, so we never fight the OS over a state it restored or the user is toggling.
# 窗口是否应被最大化（即当前未最大化、也未全屏）。仅在这种情况下最大化，避免与操作系统争夺
# 已恢复的状态或用户正在切换的全屏。
static func gpShouldMaximize(gpWin: Window) -> bool:
	if gpWin == null:
		return false
	return gpWin.mode != Window.MODE_MAXIMIZED and gpWin.mode != Window.MODE_FULLSCREEN


# True when the window moved to a different monitor than gpLastScreen (cross-screen drag).
# Returns false when gpLastScreen is negative (no known prior screen yet).
# 窗口是否从 gpLastScreen 移到另一台显示器（跨屏拖拽）。gpLastScreen 为负（尚无已知前屏）时返回 false。
static func gpIsCrossScreenChange(gpWin: Window, gpLastScreen: int) -> bool:
	if gpWin == null or gpLastScreen < 0:
		return false
	return gpWin.current_screen != gpLastScreen


# The current screen index the window is on (>= 0), or -1 when there is no window / no screen.
# 窗口当前所在显示器下标（>=0），无窗口/无屏时返回 -1。
static func gpCurrentScreen(gpWin: Window) -> int:
	if gpWin == null:
		return -1
	return gpWin.current_screen
