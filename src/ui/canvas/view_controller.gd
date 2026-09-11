class_name GPCanvasViewController
extends RefCounted
# Copyright © 2026 Jonson Wang
# camera transform; zoom and pan
# 相机变换与视口缩放平移
#
# WHY THIS EXISTS / 为何存在（架构优化建议 §3.4）：
#   GPCanvas2D was carrying many unrelated responsibilities in one file; this coordinator
#   owns the "camera transform" use case end to end, so the root keeps only assembly and forwarding.
#   GPCanvas2D 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「相机变换与视口缩放平移」这一用例，
#   使根类只保留装配与转发。
#
# Interaction / 交互方式：
#   - the root creates this coordinator and injects itself as gpHost (composition root);
#     根类创建本协调者并把自身注入为 gpHost（组合根装配）；
#   - the root forwards user actions here, never the other way round — this class drives the
#     host only through its public ports (GPCanvas2D.gp*);
#     根类把用户动作转发到此处，绝不反向 —— 本类只经宿主的公开端口（GPCanvas2D.gp*）驱动宿主；
#   - the root keeps every public port it had before: callers outside the canvas are unchanged.
#     根类保留其原有的每一个公开端口：画布外部的调用方零改动。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPCanvas2D = null


# Public: reset view to 100% centered (menu "适应窗口").
# 公开：重置视图为 100% 居中（菜单「适应窗口」）。
func gpResetView() -> void:
	gpResetCamera()
	gpHost.queue_redraw()
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
	gpHost.queue_redraw()
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
