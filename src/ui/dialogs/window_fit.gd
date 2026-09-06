class_name GPWindowFit
extends RefCounted

# Copyright © 2026 Jonson Wang
# Resolution-aware sizing for child Window dialogs (symbol editor, settings, ...).
# 子窗口对话框（图元编辑器、设置等）的分辨率自适应尺寸助手。
#
# Why this exists / 为什么需要它:
# A hard-coded `size = Vector2i(1000, 660)` is only correct on the monitor it was typed on: it
# overflows a small screen (footer buttons unreachable, and a `min_size` larger than the parent
# makes it impossible to shrink) and looks like a postage stamp on a 4K panel.
# 硬编码 `size = Vector2i(1000, 660)` 只在写它的那台显示器上正确：小屏上会溢出（底部按钮点不到，
# 且 `min_size` 大于父区域时根本缩不小），4K 屏上又小得像邮票。
#
# The unit trap that actually bit us / 真正踩到的单位陷阱:
# With `display/window/subwindows/embed_subwindows = true` (the engine default) a child Window is
# NOT an OS window: it is drawn inside the host viewport and its geometry is measured in the
# host's LOGICAL units, i.e. `content_scale_size / content_scale_factor` -- not in the host's
# pixel size. Measured on this project: host window 3024x1890 px with content_scale_factor 2.0
# yields a logical viewport of only 800x500. Sizing a dialog against `host.size` therefore
# overshoots by the whole scale factor, `popup_centered()` then centers a window larger than the
# viewport at a NEGATIVE position, and the user sees the blank middle of a clipped layout.
# 当 `display/window/subwindows/embed_subwindows = true`（引擎默认）时，子窗口并非操作系统窗口：
# 它绘制在宿主视口内部，其几何以宿主的「逻辑单位」度量，即 `content_scale_size /
# content_scale_factor`，而不是宿主的像素尺寸。本项目实测：宿主窗口 3024x1890 像素、
# content_scale_factor 2.0 时，逻辑视口仅 800x500。因此拿 `host.size` 去算对话框尺寸会整整放大
# 一个缩放系数，`popup_centered()` 随后把一个大于视口的窗口居中到「负坐标」，用户看到的就是被裁
# 剪布局的中段空白。
#
# Hence the single rule below: always measure against the same rect the engine itself uses in
# `popup_centered_clamped()` -- the embedder's visible rect when embedded, the screen's usable
# rect otherwise.
# 因此本文件只遵循一条规则：始终以引擎在 `popup_centered_clamped()` 中所用的同一矩形为基准
# ——嵌入时用宿主视口的可见矩形，否则用屏幕可用矩形。
#
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。


# Fraction of the parent area a dialog aims to occupy by default.
# 对话框默认期望占据的父区域比例。
const GP_FRAC: Vector2 = Vector2(0.62, 0.76)

# Hard ceiling: never exceed this share of the parent area, so the dialog always fits whole.
# 硬上限：绝不超过父区域的这一比例，保证对话框始终完整可见。
const GP_MAX_FRAC: float = 0.94

# Fallback parent size for headless / no-display environments.
# headless / 无显示环境下的回退父区域尺寸。
const GP_FALLBACK_SCREEN: Vector2i = Vector2i(1280, 800)


# Resolve the screen the dialog should be measured against: the host window's screen when there
# is one (the dialog pops up over it), otherwise the dialog's own, otherwise the primary screen.
# 解析对话框应参照的屏幕：有宿主窗口时用宿主所在屏（对话框弹在其上），否则用自身所在屏，
# 再否则用主屏。
static func gpScreenOf(gpWin: Window, gpHost: Window) -> int:
	if gpHost != null and gpHost != gpWin:
		return gpHost.current_screen
	if gpWin != null:
		return gpWin.current_screen
	return DisplayServer.get_primary_screen()


# Usable rect size of a screen, with a defensive fallback when no screen is reported.
# 某屏幕的可用矩形尺寸；无屏幕可报时给出防御性回退值。
static func gpUsableSize(gpScreen: int) -> Vector2i:
	if DisplayServer.get_screen_count() <= 0:
		return GP_FALLBACK_SCREEN
	var gpRect: Rect2i = DisplayServer.screen_get_usable_rect(gpScreen)
	if gpRect.size.x <= 0 or gpRect.size.y <= 0:
		return GP_FALLBACK_SCREEN
	return gpRect.size


# The area the dialog must fit inside, expressed in the same unit space as `Window.size`.
# Embedded subwindows are laid out in the embedder viewport's logical space; real OS windows are
# laid out in screen space. Getting this wrong is exactly the bug documented at the top.
# 对话框必须容身的区域，单位与 `Window.size` 一致。嵌入式子窗口按宿主视口的逻辑空间布局，
# 真实操作系统窗口按屏幕空间布局。搞错这一点正是文件顶部记录的那个 bug。
static func gpParentSize(gpWin: Window, gpHost: Window) -> Vector2i:
	if gpWin != null and gpWin.is_embedded():
		# The embedder is the nearest ancestor viewport; the host window is that viewport when
		# the dialog was parented to a plain Control inside it.
		# 宿主视口即最近的祖先 Viewport；当对话框被挂在其内部某个普通 Control 下时，宿主窗口
		# 就是该视口。
		var gpVp: Viewport = gpWin.get_parent() as Viewport
		if gpVp == null:
			gpVp = gpHost
		if gpVp != null:
			var gpRect: Rect2 = gpVp.get_visible_rect()
			if gpRect.size.x >= 1.0 and gpRect.size.y >= 1.0:
				return Vector2i(int(gpRect.size.x), int(gpRect.size.y))
	return gpUsableSize(gpScreenOf(gpWin, gpHost))


# Mirror the host window's content scale so the dialog renders at the same density as the main
# UI, and stays crisp after being dragged to another monitor.
# 镜像宿主窗口的内容缩放比，使对话框与主界面密度一致，且拖到另一台显示器后依然清晰。
static func gpSyncScale(gpWin: Window, gpHost: Window) -> void:
	if gpWin == null:
		return
	# An embedded subwindow already draws inside the host's scaled canvas: scaling it again
	# would double-apply the factor.
	# 嵌入式子窗口已经画在宿主已缩放的画布内：再缩放一次会把系数叠加两遍。
	if gpWin.is_embedded():
		return
	var gpScale: float = 0.0
	if gpHost != null and gpHost != gpWin:
		gpScale = gpHost.content_scale_factor
	if gpScale <= 0.0:
		gpScale = DisplayServer.screen_get_scale(gpScreenOf(gpWin, gpHost))
	if gpScale > 0.0 and not is_equal_approx(gpScale, gpWin.content_scale_factor):
		gpWin.content_scale_factor = gpScale


# Logical UI units -> window units for this window.
# 该窗口的「逻辑 UI 单位 -> 窗口单位」换算。
static func gpToWindowUnits(gpWin: Window, gpLogical: Vector2i) -> Vector2i:
	# Embedded geometry is already expressed in the host's logical units: no conversion.
	# 嵌入式几何本就以宿主逻辑单位表达：无需换算。
	if gpWin != null and gpWin.is_embedded():
		return gpLogical
	var gpCs: float = 1.0
	if gpWin != null and gpWin.content_scale_factor > 0.0:
		gpCs = gpWin.content_scale_factor
	return Vector2i(int(round(gpLogical.x * gpCs)), int(round(gpLogical.y * gpCs)))


# Largest size the dialog may take while remaining wholly inside its parent area.
# 对话框在完整留在父区域内的前提下可取的最大尺寸。
static func gpCeilingSize(gpWin: Window, gpHost: Window) -> Vector2i:
	var gpParent: Vector2i = gpParentSize(gpWin, gpHost)
	return Vector2i(int(gpParent.x * GP_MAX_FRAC), int(gpParent.y * GP_MAX_FRAC))


# Sync the content scale, then re-derive `min_size` (and optionally `size`) from the parent area.
# `gpMinLogical` / `gpMaxLogical` describe the layout's comfortable range in logical UI units.
# When `gpResize` is false the current size is only clamped down if it no longer fits, so a
# user-resized window is never fought over.
# 同步内容缩放，然后依据父区域重新推导 `min_size`（可选连 `size` 一起）。`gpMinLogical` /
# `gpMaxLogical` 以逻辑 UI 单位描述布局的舒适区间。`gpResize` 为 false 时只在放不下时把当前尺寸
# 向下钳制，绝不与用户手动调整的尺寸对抗。
static func gpApply(
	gpWin: Window,
	gpHost: Window,
	gpMinLogical: Vector2i,
	gpMaxLogical: Vector2i,
	gpResize: bool,
	gpFrac: Vector2 = GP_FRAC
) -> void:
	if gpWin == null:
		return
	gpSyncScale(gpWin, gpHost)

	var gpParent: Vector2i = gpParentSize(gpWin, gpHost)
	var gpCeil: Vector2i = Vector2i(int(gpParent.x * GP_MAX_FRAC), int(gpParent.y * GP_MAX_FRAC))
	var gpFloor: Vector2i = gpToWindowUnits(gpWin, gpMinLogical)
	var gpTop: Vector2i = gpToWindowUnits(gpWin, gpMaxLogical)

	# A `min_size` larger than the parent area would lock the window at an unusable size (and
	# make `popup_centered*` place it at a negative position), so the design minimum yields.
	# `min_size` 大于父区域会把窗口锁死在无法使用的尺寸（并让 `popup_centered*` 把它放到负坐标），
	# 因此设计下限必须让位。
	gpFloor = Vector2i(mini(gpFloor.x, gpCeil.x), mini(gpFloor.y, gpCeil.y))
	gpTop = Vector2i(maxi(gpTop.x, gpFloor.x), maxi(gpTop.y, gpFloor.y))
	gpWin.min_size = gpFloor

	if gpResize:
		var gpWant: Vector2i = Vector2i(
			int(gpParent.x * gpFrac.x),
			int(gpParent.y * gpFrac.y)
		)
		gpWin.size = Vector2i(
			clampi(gpWant.x, gpFloor.x, mini(gpTop.x, gpCeil.x)),
			clampi(gpWant.y, gpFloor.y, mini(gpTop.y, gpCeil.y))
		)
		return

	# Keep the user's size, only shrink it when the parent area cannot hold it.
	# 保留用户尺寸，仅当父区域装不下时才收缩。
	var gpCur: Vector2i = gpWin.size
	var gpFit: Vector2i = Vector2i(mini(gpCur.x, gpCeil.x), mini(gpCur.y, gpCeil.y))
	if gpFit != gpCur:
		gpWin.size = gpFit


# Fit the dialog to its parent area and show it centered over the host. The centering is handed
# to `popup_centered_clamped()` so the engine's own parent-rect logic decides the position --
# with `size` already clamped to `GP_MAX_FRAC` the result can never be a negative position.
# 将对话框适配到父区域并居中显示在宿主之上。居中交给 `popup_centered_clamped()`，由引擎自己的
# 父矩形逻辑决定位置——由于 `size` 已被钳制在 `GP_MAX_FRAC` 内，结果绝不可能是负坐标。
static func gpPopupFitted(
	gpWin: Window,
	gpHost: Window,
	gpMinLogical: Vector2i,
	gpMaxLogical: Vector2i,
	gpFrac: Vector2 = GP_FRAC
) -> void:
	if gpWin == null:
		return
	gpApply(gpWin, gpHost, gpMinLogical, gpMaxLogical, true, gpFrac)
	gpWin.popup_centered_clamped(gpWin.size, GP_MAX_FRAC)
