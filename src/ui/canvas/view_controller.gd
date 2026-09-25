class_name GPCanvasViewController
extends RefCounted
# Copyright © 2026 Jonson Wang
# camera transform; zoom and pan
# 相机变换与视口缩放平移
#
# WHY THIS EXISTS / 为何存在：
# GPCanvas2D was carrying many unrelated responsibilities in one file; this coordinator
# owns the "camera transform" use case end to end, so the root keeps only assembly and forwarding.
# GPCanvas2D 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「相机变换与视口缩放平移」这一用例，
# 使根类只保留装配与转发。
#
# Interaction / 交互方式：
# - the root creates this coordinator and injects itself as gpHost (composition root);
# 根类创建本协调者并把自身注入为 gpHost（组合根装配）；
# - the root forwards user actions here, never the other way round — this class drives the
# host only through its public ports (GPCanvas2D.gp*);
# 根类把用户动作转发到此处，绝不反向 —— 本类只经宿主的公开端口（GPCanvas2D.gp*）驱动宿主；
# - the root keeps every public port it had before: callers outside the canvas are unchanged.
# 根类保留其原有的每一个公开端口：画布外部的调用方零改动。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPCanvas2D = null


# Public: fit the drawing sheet into the viewport (menu "适应窗口" / first layout).
# 公开：把图纸适配进视口（菜单「适应窗口」/ 首次布局）。
# WHY FIT AND NOT 100%: the world unit is 1 mm (plan Phase 0), so at 100% an A3 sheet
# (420x297 mm) is only 420x297 screen points — a third of the canvas, with 3 mm tag text
# rasterised at 3 px and therefore unreadable. Fitting the sheet on first layout is what makes
# the drawing (and its frame) actually visible without touching the wheel.
# 为何适配而非 100%：世界单位为 1mm（计划 Phase 0），故 100% 时 A3 图幅（420×297mm）仅
# 420×297 屏幕点 —— 只有画布的三分之一，且 3mm 位号文字仅以 3px 光栅化、无法阅读。首次布局即
# 适配图幅，正是让图纸（连同图框）无需滚轮即可看清的原因。
func gpFitSheet(gpW: float, gpH: float, gpFill: float = 0.94) -> void:
	if gpW <= 1.0 or gpH <= 1.0:
		return
	var gpAvail: Vector2 = gpHost.size
	if gpAvail.x <= 1.0 or gpAvail.y <= 1.0:
		return
	var gpZoom: float = minf(gpAvail.x / gpW, gpAvail.y / gpH) * gpFill
	gpZoom = clampf(gpZoom, GPCanvasCamera.GP_ZOOM_MIN, GPCanvasCamera.GP_ZOOM_MAX)
	gpHost.gpState.gpCam.gpZoom = gpZoom
	# Centre the sheet: gpScreenFromWorld(w) = w * zoom + offset, so placing the sheet's own
	# (0,0) at the leftover margin centres the whole rect.
	# 使图幅居中：gpScreenFromWorld(w) = w * zoom + offset，故把图幅自身的 (0,0) 放在剩余边距处
	# 即可让整个矩形居中。
	gpHost.gpState.gpCam.gpOffset = (gpAvail - Vector2(gpW, gpH) * gpZoom) * 0.5
	gpApplyCamera()
	gpHost.gpOnCameraChanged()


# Public: reset view to 100% centered (menu "适应窗口").
# 公开：重置视图为 100% 居中（菜单「适应窗口」）。
func gpResetView() -> void:
	# Prefer fitting the open sheet; fall back to the plain 100% reset when no sheet is bound
	# (e.g. a headless canvas with no document). / 优先适配已打开的图纸；无图纸绑定时（如无文档的
	# headless 画布）回退到纯 100% 重置。
	var gpS: GPSheet = gpHost.gpSheet
	if gpS != null:
		gpFitSheet(gpS.gpWidthMM, gpS.gpHeightMM)
	else:
		gpResetCamera()
	# Both branches already repainted the scale-dependent text (see gpOnCameraChanged).
	# 两个分支都已重绘了依赖缩放的文字（见 gpOnCameraChanged）。
	gpHost.gpEmitStatus()

# Public: zoom by a step centered on the canvas (menu "放大/缩小").
# 公开：以画布中心为锚点缩放一步（菜单「放大/缩小」）。
func gpZoomStep(gpFactor: float) -> void:
	gpZoomAt(gpHost.size / 2.0, gpFactor)

# Zoom in or out while keeping the world point under the cursor stable.
# 以光标下的世界点为中心进行缩放。
func gpZoomAt(gpScreen: Vector2, gpFactor: float) -> void:
	if not gpHost.gpState.gpCam.gpZoomAt(gpScreen, gpFactor):
		return
	gpApplyCamera()
	# The zoom changed, so every on-canvas glyph must be re-rasterised at the new scale — a parent
	# repaint alone would leave the old bitmaps magnified (see GPCanvas2D.gpOnCameraChanged).
	# 缩放已变，故每个画布字形都须按新缩放重新光栅化 —— 仅重绘父节点会让旧字模被放大
	#（见 GPCanvas2D.gpOnCameraChanged）。
	gpHost.gpOnCameraChanged()
	gpHost.gpEmitStatus()

# Convert a screen coordinate to a world coordinate (delegates to GPCanvasCamera).
# 将屏幕坐标转换为世界坐标（委托 GPCanvasCamera）。
func gpWorldFromScreen(gpS: Vector2) -> Vector2:
	return gpHost.gpState.gpCam.gpWorldFromScreen(gpS)

# Convert a world coordinate to a screen coordinate (delegates to GPCanvasCamera).
# 将世界坐标转换为屏幕坐标（委托 GPCanvasCamera）。
func gpScreenFromWorld(w: Vector2) -> Vector2:
	return gpHost.gpState.gpCam.gpScreenFromWorld(w)

# Apply the camera (offset + zoom) to the world root; the transform math lives in GPCanvasCamera.
# 将相机（偏移 + 缩放）应用到世界根节点；变换数学位于 GPCanvasCamera。
func gpApplyCamera() -> void:
	gpHost.gpState.gpCam.gpApplyTo(gpHost.gpWorldRoot)

# ============================ camera / transform ============================
# ============================ 相机 / 坐标变换 ============================
# Reset the camera to 100% zoom and center the world origin.
# 将相机重置为 100% 缩放并把世界原点居中。
func gpResetCamera() -> void:
	gpHost.gpState.gpCam.gpReset(gpHost.size / 2.0)
	gpApplyCamera()
	gpHost.gpOnCameraChanged()
