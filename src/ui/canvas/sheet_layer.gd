class_name GPCanvasSheetLayer
extends RefCounted
# Copyright © 2026 Jonson Wang
# sheet / frame / background rendering layer
# 图纸 / 图框 / 背景渲染层
#
# WHY THIS EXISTS / 为何存在：
# GPCanvas2D was carrying the sheet, its frame renderer and its background renderer alongside
# every other collaborator; this coordinator owns the "sheet rendering" use case end to end
# (bind sheet → refresh frame and background → one-shot fit), so the root keeps only assembly
# and forwarding.
# GPCanvas2D 曾把图纸、图框渲染器与背景渲染器与其它协作者一起压在同一文件里；本协调者
# 端到端接管「图纸渲染」这一用例（绑定图纸 → 刷新图框与背景 → 一次性适配），
# 使根类只保留装配与转发。
#
# Interaction / 交互方式：
# - the root creates this coordinator and injects itself as gpHost (composition root);
# 根类创建本协调者并把自身注入为 gpHost（组合根装配）；
# - the root forwards user actions here, never the other way round — this class drives the
# host only through its public ports (GPCanvas2D.gp*);
# 根类把动作转发到此处，绝不反向 —— 本类只经宿主的公开端口（GPCanvas2D.gp*）驱动宿主；
# - the root keeps every public port it had before: callers outside the canvas are unchanged.
# 根类保留其原有的每一个公开端口：画布外部的调用方零改动。
#
# ORDERING CONSTRAINT / 顺序约束：
# the background MUST be added before the frame. Both use z_index 0, so stacking depends
# entirely on child order; a negative z_index would land BELOW the canvas's own opaque
# background fill and be invisible.
# 背景**必须先于**图框加入。二者均用 z_index 0，层叠完全依赖子节点顺序；负 z_index 会落到
# 画布自身不透明底色之下而不可见。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPCanvas2D = null

# The sheet being displayed: supplies frame size, title block and drawing-text language mode.
# Null until the host assigns one.
# 正在显示的图纸：提供图幅、标题栏与图纸文字语言模式。宿主赋值前为 null。
var gpSheet: GPSheet = null

# Frame renderer, a child of world_root placed behind every symbol.
# 图框渲染器，挂在 world_root 下且位于所有图元之下。
var gpFrame: GPFrameView = null

# Tracing underlay (background reference image).
# 追踪底图（背景参考图）。
var gpBackground: GPBackgroundView = null

# True until the sheet has been fitted into the viewport once. Kept as a one-shot so a
# late-arriving control size still fits the drawing, yet the user's own pan/zoom is never
# overridden afterwards.
# 为 true 时表示「尚未把图幅适配进视口一次」。以一次性标志实现，使迟到的控件尺寸仍能触发
# 适配，而此后用户自己的平移/缩放永不被覆盖。
var _gpNeedFit: bool = true


# Create the frame and background views and add them to the world root, background FIRST.
# 创建图框与背景视图并加入世界根，**背景在前**（层叠顺序敏感，见文件头说明）。
func gpBuild(gpWorldRoot: Node2D) -> void:
	gpBackground = GPBackgroundView.new()
	gpBackground.name = "BackgroundView"
	gpBackground.z_index = 0
	gpWorldRoot.add_child(gpBackground)
	gpFrame = GPFrameView.new()
	gpFrame.name = "FrameView"
	gpFrame.z_index = 0
	gpWorldRoot.add_child(gpFrame)


# Bind the sheet and refresh both renderers. Idempotent on purpose: the host binds the sheet
# through gpSetSheet() BEFORE this Control is added to the tree (center_area builds the canvas,
# binds the sheet, then adds the canvas), so on that first call gpFrame is still null and the
# assignment would be swallowed — replaying it after gpBuild() covers every ordering.
# 绑定图纸并刷新两个渲染器。刻意做成幂等：宿主经 gpSetSheet() 绑定图纸的时机早于本控件入树
#（center_area 先建画布、绑图纸、再把画布入树），首次调用时 gpFrame 仍为 null，赋值会被吞 ——
# 在 gpBuild() 之后重放一次即可覆盖任何装配顺序。
func gpSetSheet(gpValue: GPSheet) -> void:
	# Re-point the sheet's change signal (Rev.3 stage 0c). The subscription is per-SHEET, so the old
	# sheet must be detached first: leaving it connected would let a background tab's undo repaint the
	# frame of the tab in front — the classic "one signal, two owners" bug, made visible only by the
	# disappearing repaint. is_connected() guards each side so this stays idempotent.
	# 重新指向图纸的变化信号（Rev.3 阶段 0c）。订阅是**按图纸**的，故必须先解绑旧图纸：留着它连着，
	# 后台标签的撤销就会重绘前台标签的图框 —— 典型的「一个信号两个属主」，且只在重绘消失时才显形。
	# 每侧都加 is_connected() 守卫，使其保持幂等。
	if gpSheet != null and gpSheet.gpSheetChanged.is_connected(_gpOnSheetChanged):
		gpSheet.gpSheetChanged.disconnect(_gpOnSheetChanged)
	gpSheet = gpValue
	# P0-5: the active sheet supplies the document-wide symbol scale (1.0 = A1-rebased data,
	# 0.5 = a pre-A1 archive). Applying it here means every consumer of the shared library —
	# renderer, hit-test, mount resolver, print model, exporters — sees the right envelope.
	# P0-5：活动图纸给出全文档图元尺度（1.0 = A1 重定基数据，0.5 = A1 之前存档）。在此施加
	# 使共享图元库的每个消费方 —— 渲染、命中、挂载、打印、导出 —— 看到正确包络。
	GPSymbolLibrary.gpSetDocSizeScale(gpValue.gpSymbolScale if gpValue != null else 1.0)
	if gpSheet != null and not gpSheet.gpSheetChanged.is_connected(_gpOnSheetChanged):
		gpSheet.gpSheetChanged.connect(_gpOnSheetChanged)
	if gpFrame != null:
		gpFrame.gpSheet = gpValue
		gpFrame.gpRefresh()
	if gpBackground != null:
		gpBackground.gpSheet = gpValue
		gpBackground.gpRefresh()


# A sheet-level field changed: repaint the frame and tell the host the DOCUMENT changed.
# 图纸级字段发生变化：重绘图框，并告知宿主**文档**已变。
#
# The sheet model knows nothing about views, so this is where its signal becomes a repaint plus a dirty
# mark. The host half is a single call, so the dirty flag, the app-bus broadcast and the repaint stay
# one decision (GPCanvas2D.gpOnSheetDataChanged) instead of three that could drift.
# 图纸模型对视图一无所知，故此处正是其信号变成「一次重绘 + 一次标脏」的地方。宿主那一半只有一次调用，
# 使脏标记、应用总线广播与重绘保持为**一个**判断（GPCanvas2D.gpOnSheetDataChanged），
# 而不是三个可能分家的判断。
func _gpOnSheetChanged() -> void:
	if gpHost != null:
		gpHost.gpOnSheetDataChanged()
	else:
		gpRefreshFrame()


# One-shot fit of the sheet into the viewport, run as soon as a usable size exists.
# The size is passed in because this coordinator is a RefCounted and cannot read Control.size.
# 图幅一次性适配进视口，在尺寸首次可用时执行。
# 尺寸由参数传入 —— 本协调者是 RefCounted，无法读取 Control.size。
func gpFitIfReady(gpSize: Vector2) -> void:
	if not _gpNeedFit:
		return
	if gpSize.x <= 1.0 or gpSize.y <= 1.0:
		return
	if gpSheet != null:
		gpHost.gpViewController.gpFitSheet(gpSheet.gpWidthMM, gpSheet.gpHeightMM, 0.94,
			gpSheet.gpPaperOrigin)
	else:
		gpHost.gpViewController.gpResetCamera()
	_gpNeedFit = false
	# The camera moved, so the on-canvas text must be rasterised at the new scale (gpFitSheet /
	# gpResetCamera already did that) and the status bar must show the resulting zoom.
	# 相机已移动，故画布文字须按新缩放重新光栅化（gpFitSheet / gpResetCamera 已完成），
	# 状态栏也须显示新的缩放值。
	gpHost.gpEmitStatus()


# Repaint the frame after a camera change (text inside the title block is rasterised per scale).
# 相机变化后重绘图框（标题栏内的文字按缩放光栅化）。
#
# ⚠️ IT ALSO REPAINTS THE TRACING UNDERLAY (Rev.3 stage 0d) / ⚠️ 它同时重绘追踪底图（Rev.3 阶段 0d）：
# the underlay is stretched over the PAPER, so it is one more thing the sheet PLACES — and since stage
# 0d the paper itself can move. Refreshing only the frame would leave the reference image behind on a
# moved sheet, which is exactly the failure this call prevents. It is one queue_redraw on a Node2D, so
# the per-mouse-move margin drag pays nothing noticeable for it.
# 底图铺在**纸面**上，故它同样是**由图纸摆放**之物 —— 而自阶段 0d 起纸面本身可以移动。只刷新图框会让
# 参考图被留在被移动过的图纸原处，而这正是本次调用所防止的失效。它只是一次 Node2D 的 queue_redraw，
# 故逐次鼠标移动的边距拖拽为之付出的代价可忽略。
func gpRefreshFrame() -> void:
	if gpFrame != null:
		gpFrame.gpRefresh()
	if gpBackground != null:
		gpBackground.gpRefresh()
