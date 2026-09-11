class_name GPLayoutCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Splitter ratios, DPI scaling, window resize handling and maximised start-up
# 分隔条比例、DPI 缩放、窗口尺寸响应与最大化
#
# WHY THIS EXISTS / 为何存在（架构优化建议 §3.2）：
#   GPMainWindow was carrying many unrelated responsibilities in one file; this coordinator
#   owns the "Splitter ratios, DPI scaling, window resize handling and maximised start-up" use case end to end, so the root keeps only assembly and forwarding.
#   GPMainWindow 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「分隔条比例、DPI 缩放、窗口尺寸响应与最大化」这一用例，
#   使根类只保留装配与转发。
#
# Interaction / 交互方式：
#   - the root creates this coordinator and injects itself as gpHost (composition root);
#     根类创建本协调者并把自身注入为 gpHost（组合根装配）；
#   - the root forwards menu / toolbar actions here, never the other way round — this class
#     does not reach back into menus or the ribbon;
#     根类把菜单/工具栏动作转发到此处，绝不反向 —— 本类不回指菜单或 Ribbon；
#   - UI refresh goes through gpHost._gpSetState / the docks the root owns.
#     UI 刷新经由 gpHost._gpSetState 及根类持有的停靠栏完成。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPMainWindow = null


# A splitter in the three-pane body was dragged. Godot 4.7's SplitContainer.dragged
# signal only carries the splitter offset (distance from the body's left edge); it
# does NOT carry a splitter index even with three children. We therefore decide which
# splitter moved by comparing the new offset to the stored left/right splitter
# positions; the closer one wins. This keeps both docks resizable and lets the
# palette grid reflow as the left dock is widened or narrowed.
# 三栏主体中某个分隔条被拖动。Godot 4.7 的 SplitContainer.dragged 信号只带分隔条偏移
#（距主体左缘的距离），即便有三个子节点也**不带索引**。因此通过比较新偏移与当前存
# 储的左/右分隔条位置来判断拖的是哪条；离谁近就是谁。这样左右两栏都可调，左栏变
# 宽/窄时图元网格也能随之重排。
func gpOnBodyDragged(gpOffset: int) -> void:
	var gpBW: float = gpHost.gpBodySplit.size.x
	if gpBW <= 1.0:
		return
	var gpOffsetF: float = float(gpOffset)
	# Determine which splitter is being dragged by proximity to the current positions.
	# 通过离当前位置的远近判断正在拖哪条分隔条。
	var gpLeftPos: float = gpHost.gpLeftWidthPx
	var gpRightPos: float = gpBW - gpHost.gpRightWidthPx
	var gpLeftDist: float = absf(gpOffsetF - gpLeftPos)
	var gpRightDist: float = absf(gpOffsetF - gpRightPos)
	if gpLeftDist < gpRightDist:
		# Left splitter: offset == left-dock width. Feed the new width to the palette
		# grid so it recomputes its column count immediately.
		# 左分隔条：偏移即左栏宽度。把新宽度传给图元网格，使其立即重算列数。
		gpHost.gpLeftWidthPx = clampf(gpOffsetF, GPMainWindow.GP_LEFT_MIN, gpBW - GPMainWindow.GP_RIGHT_MIN - 80.0)
		if gpHost.gpLeftDock != null and gpHost.gpLeftDock.has_method("_gpReflow"):
			gpHost.gpLeftDock._gpReflow(gpHost.gpLeftWidthPx)
	else:
		# Right splitter: offset == left+center span, so right width = body - offset.
		# 右分隔条：偏移即左+中跨度，故右栏宽度 = 主体宽度 - 偏移。
		var gpRightPx: float = gpBW - gpOffsetF
		gpHost.gpRightWidthPx = clampf(gpRightPx, GPMainWindow.GP_RIGHT_MIN, gpBW - GPMainWindow.GP_LEFT_MIN - 80.0)
	# Re-apply the split immediately so the splitter position and the palette reflow
	# match the dragged width on the spot (and a later resize keeps it, since the
	# stored pixel widths now reflect the drag). Idempotent: it just writes the same
	# offsets Godot set during the drag.
	# 立即重应用分隔，使分隔条位置与图元库重排当场贴合拖出宽度（后续缩放也能保留，
	# 因为存储像素宽现已反映本次拖拽）。幂等：写入的即 Godot 拖拽时已设的偏移。
	gpApplySplits()


# ============================ lookups ============================
# ============================ 查找 ============================
# Find a symbol definition by its id.
# 按 id 查找图元定义。

# Initial dock widths: wait until the split container has a real laid-out width
# (a few frames after _ready), then· seed the stored widths from the docks' floors
# and pin both docks so the canvas fills the rest.
# 初始停靠栏宽度：等待分隔容器获得已布局的真实宽度（_ready 后若干帧），再用两栏
# 下限初始化存储宽度，并钉死两栏使画布填满剩余空间。
func gpInitSplits() -> void:
	for _gpI in range(10):
		await gpHost.get_tree().process_frame
		if gpHost.gpBodySplit != null and gpHost.gpBodySplit.size.x > 50.0:
			break
	# Seed the stored widths from the declared floors so the first apply pins both
	# docks to their minimum and the canvas gets everything else.
	# 用声明下限初始化存储宽度，使首次应用把两栏钉到最小、画布取得其余空间。
	gpHost.gpLeftWidthPx = GPMainWindow.GP_LEFT_MIN
	gpHost.gpRightWidthPx = GPMainWindow.GP_RIGHT_MIN
	gpApplySplits()
	var gpWin: Window = gpHost.get_window()
	gpHost.gpPrevWidth = int(gpWin.size.x) if gpWin != null else 0

# Pin both docks to their stored pixel widths and let the canvas (center) absorb
# everything else. No window-ratio is involved, so resizing only changes the center
# pane. The stored widths are seeded from the floors at startup and updated by drag.
# Idempotent: given the same dock widths it always yields the same offsets.
# 将左右两栏钉到当前存储的像素宽度，画布（中间）吸收其余全部空间。不涉及窗口比例，
# 故缩放只改变中间栏。存储宽度在启动时以下限初始化、拖拽时更新。幂等：相同停靠栏
# 宽度必得相同偏移。
func gpApplySplits() -> void:
	if gpHost.gpBodySplit == null:
		return
	var gpBW: float = gpHost.gpBodySplit.size.x
	if gpBW <= 1.0:
		return
	# Use the session-only pixel widths. They start at the floors on launch and are
	# overwritten by splitter drags, so the user's layout survives every resize until
	# the next restart (when the script variables reset to the floors again).
	# 使用仅会话有效的像素宽度。启动时为下限，拖拽分隔条后被覆盖，因此用户布局在
	# 每次缩放时都保持，直到下次重启（脚本变量重新回退到下限）。
	var gpL: float = gpHost.gpLeftWidthPx
	var gpR: float = gpHost.gpRightWidthPx
	# Pin the palette grid's minimum width to the target left width FIRST, so the
	# left dock's combined minimum equals gpL and the splitter is never clamped
	# above gpL (otherwise a wide grid min would lock the dock at its old width).
	# 先把图元网格最小宽钉到目标左栏宽，使左停靠栏合并最小宽等于 gpL、分隔条不会被
	# 钳到 gpL 以上（否则网格的旧大最小宽会把停靠栏锁在旧宽度）。
	if gpHost.gpLeftDock != null and gpHost.gpLeftDock.has_method("_gpReflow"):
		gpHost.gpLeftDock._gpReflow(gpL)
	# Split 0 sits at the left dock's right edge; split 1 sits one right-dock
	# width back from the body's right edge, leaving the center to fill the gap.
	# 分隔条 0 位于左栏右缘；分隔条 1 距主体右缘一个右栏宽度，中间栏填满缝隙。
	var gpOffsets: PackedInt32Array = PackedInt32Array()
	gpOffsets.append(int(round(gpL)))
	gpOffsets.append(int(round(gpBW - gpR)))
	gpHost.gpBodySplit.split_offsets = gpOffsets

# Responsive layout: when the window is resized we re-apply the splits so the
# canvas (center) keeps absorbing the new width. The dock widths themselves stay
# fixed (snapped to their floor when auto-scale is on, or kept at the user-dragged
# size when off). Depends only on width, so a pure height change leaves docks
# untouched. The UI font is never scaled (see settings.gd).
# 响应式布局：窗口缩放时重新应用分隔，使画布（中间）持续吸收新增宽度。停靠栏宽度
# 始终使用当前存储的像素值（启动时为下限，拖拽后为用户设定值）。只依赖宽度，
# 故纯高度变化不改变停靠栏。界面字号不随窗口缩放（见 settings.gd）。
func gpOnResized() -> void:
	var gpWin: Window = gpHost.get_window()
	if gpWin == null:
		return
	var gpW: int = int(gpWin.size.x)
	if gpW <= 0:
		return
	if gpHost.gpPrevWidth <= 0:
		gpHost.gpPrevWidth = gpW
		return
	if gpW == gpHost.gpPrevWidth:
		return
	gpHost.gpPrevWidth = gpW
	# Defer the split re-apply so HSplitContainer has finished its own layout pass
	# and gpBodySplit.size.x reflects the new window width. Applying immediately
	# uses the stale body width and makes the docks stick to the old offsets.
	# 延迟重应用分隔，让 HSplitContainer 先完成自身布局，使 gpBodySplit.size.x 反映新窗口宽度。
	# 立即应用会使用旧的主体宽度，导致停靠栏粘在老偏移上。
	call_deferred("gpApplySplits")

# Detect when the window is dragged to another monitor.
# 检测窗口被拖到另一台显示器时。
func gpOnWindowChanged() -> void:
	var gpWin: Window = gpHost.get_window()
	if gpWin == null:
		return
	var gpScreen: int = gpWin.current_screen
	if gpScreen == gpHost.gpLastScreen:
		return
	gpHost.gpLastScreen = gpScreen
	gpApplyDpiScale()
	# After the window lands on a new monitor, re-maximize so it keeps filling that screen and the
	# canvas_items stretch re-scales the design to the new monitor's size / DPI.
	# 窗口落到新显示器后再次最大化，使其继续铺满该屏，canvas_items 拉伸随之按新屏尺寸 / DPI 重缩放。
	gpOpenMaximized(gpWin)

# Open the main window maximized so the 1600x900 design canvas (stretch mode "canvas_items")
# is scaled by the engine to fill the real window. Maximize rather than a hand-computed size so
# the OS owns the geometry on every monitor / DPI combination: the window always fills the usable
# screen and the UI scale therefore tracks the monitor. Re-maximizing after a cross-monitor drag
# keeps it filling the newly-entered screen too.
# 将主窗口最大化，使 1600x900 的设计画布（stretch 模式 canvas_items）由引擎缩放铺满真实窗口。
# 用「最大化」而非手算尺寸，让操作系统在每台显示器 / 每种 DPI 组合下决定几何：窗口始终铺满
# 可用屏幕，UI 缩放比随之跟随显示器。跨屏拖拽后再次最大化，也能让窗口继续铺满新进入的屏幕。
func gpOpenMaximized(gpWin: Window) -> void:
	if gpWin == null:
		return
	# Only maximize when the window isn't already maximized / fullscreen (e.g. the OS restored a
	# prior maximized state or the user is toggling fullscreen), to avoid fighting the OS. The
	# decision is the pure predicate in GPDpiWindow.
	# 仅在窗口尚未最大化 / 全屏时才最大化（例如 OS 已恢复上次最大化状态、或用户正切换全屏），
	# 以免与操作系统争夺状态。判定收敛到 GPDpiWindow 的纯谓词。
	if not GPDpiWindow.gpShouldMaximize(gpWin):
		return
	gpWin.mode = Window.MODE_MAXIMIZED

# ============================ HiDPI / multi-monitor ============================
# ============================ HiDPI / 多显示器 ============================
# Apply the OS screen scale to Godot's content scale factor and refresh fonts.
# 将窗口内容缩放比固定为 1.0（正确适配 Retina/多显示器）并刷新字体。
func gpApplyDpiScale() -> void:
	# KEEP content_scale_factor at 1.0. Godot 4 on macOS ALREADY reports window geometry in
	# LOGICAL POINTS and renders the backing store at the display's native pixel ratio (2x on
	# Retina). Forcing content_scale_factor = screen_get_scale() (=2.0 here) DOUBLE-COUNTS that
	# Retina scale: Godot then treats the visible logical viewport as design/csf = 1600/2 = 800
	# wide, so the whole 1600-wide UI is drawn 2x too large and clipped (measured: host window
	# 3024x1890 px @ csf 2.0 yields a logical viewport of only ~800x500). With csf pinned to 1.0
	# and stretch mode "canvas_items", the 1600x900 design canvas maps 1:1 in logical points and
	# the engine scales it to fill the maximized window, so menu / docks / property / status bar
	# keep correct proportions on ANY monitor / DPI. Text crispness is handled by the fonts'
	# oversampling (4.0) in their .import settings, not by content_scale_factor.
	# 把 content_scale_factor 固定为 1.0。Godot 4 在 macOS 上已用「逻辑点」报告窗口几何，并以显示器的
	# 原生像素比（Retina 为 2x）渲染背板。若再把 content_scale_factor 设成 screen_get_scale()（此处
	# =2.0），就会把 Retina 缩放算两遍：Godot 会把可见逻辑视口当作 design/csf = 1600/2 = 800 宽，
	# 整幅 1600 宽的界面被放大 2 倍并裁切（实测：宿主窗 3024x1890px、csf 2.0 时逻辑视口仅约 800x500）。
	# 把 csf 钉在 1.0 并配合 stretch 模式 canvas_items，1600x900 设计画布以 1:1 逻辑点映射，由引擎缩放到
	# 铺满的最大化窗口，从而在任何显示器 / DPI 下菜单 / 停靠栏 / 属性 / 状态栏比例都正确。文字清晰由
	# 字体的 oversampling(4.0)（见 .import）保证，而非 content_scale_factor。
	var gpWin: Window = gpHost.get_window()
	if gpWin == null:
		return
	# Pin content_scale_factor to 1.0 (pure decision in GPDpiWindow — see that module for the
	# Retina double-scale rationale). 把 content_scale_factor 钉回 1.0（纯决策在 GPDpiWindow，
	# Retina 双重缩放原因见该模块注释）。
	GPDpiWindow.gpPinContentScale(gpWin)
	# Re-apply the UI theme so controls relayout at the new monitor's density.
	# 重新应用界面主题，使控件按新显示器密度重排。
	Settings.gpApplyFontSize()
