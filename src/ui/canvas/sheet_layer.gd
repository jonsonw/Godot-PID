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
	gpSheet = gpValue
	if gpFrame != null:
		gpFrame.gpSheet = gpValue
		gpFrame.gpRefresh()
	if gpBackground != null:
		gpBackground.gpSheet = gpValue
		gpBackground.gpRefresh()


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
		gpHost.gpViewController.gpFitSheet(gpSheet.gpWidthMM, gpSheet.gpHeightMM)
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
func gpRefreshFrame() -> void:
	if gpFrame != null:
		gpFrame.gpRefresh()
