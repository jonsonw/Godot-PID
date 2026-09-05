extends "res://tests/gp_test.gd"
# Headless regression tests for GPCanvasCamera (P1-1a extraction).
# 相机模块（P1-1a 抽取）的 headless 回归测试。

# reset / transform round-trip / zoom-at-point anchor stability / pan.
func gpTestReset() -> void:
	# gpReset() takes the VIEWPORT CENTER (not the full size). For a 1600x900 view the
	# center is (800, 450); the camera centers the world origin there at 100% zoom.
	# gpReset() 接收的是视口「中心」（非全尺寸）。对 1600x900 视口中心为 (800,450)，
	# 相机在 100% 缩放时把世界原点置于该中心。
	var cam: GPCanvasCamera = GPCanvasCamera.new()
	cam.gpReset(Vector2(800, 450))
	gpApprox(cam.gpZoom, 1.0, 1e-6, "reset zoom = 1.0")
	gpApprox(cam.gpOffset.x, 800.0, 1e-4, "reset offset.x centered")
	gpApprox(cam.gpOffset.y, 450.0, 1e-4, "reset offset.y centered")

func gpTestRoundTrip() -> void:
	var cam: GPCanvasCamera = GPCanvasCamera.new()
	cam.gpReset(Vector2(1600, 900))
	cam.gpZoomAt(Vector2(600, 300), 1.5)
	var w: Vector2 = Vector2(123.4, -567.8)
	var s: Vector2 = cam.gpScreenFromWorld(w)
	var w2: Vector2 = cam.gpWorldFromScreen(s)
	gpCheck((w - w2).length() < 1e-4, "world<->screen round-trip within tolerance")

func gpTestZoomAnchor() -> void:
	var cam: GPCanvasCamera = GPCanvasCamera.new()
	cam.gpReset(Vector2(1600, 900))
	var anchor: Vector2 = Vector2(400, 300)
	var wBefore: Vector2 = cam.gpWorldFromScreen(anchor)
	var changed: bool = cam.gpZoomAt(anchor, 1.0)
	gpCheck(changed, "zoom-at returns changed=true when zooming in")
	var wAfter: Vector2 = cam.gpWorldFromScreen(anchor)
	gpCheck((wBefore - wAfter).length() < 1e-4, "zoom-at keeps cursor world stable (no drift)")
	gpCheck(cam.gpZoom > 1.0, "zoom increased after zoom-at +1")

func gpTestZoomClamp() -> void:
	var cam: GPCanvasCamera = GPCanvasCamera.new()
	cam.gpReset(Vector2(1600, 900))
	# Repeatedly zoom out far past the clamp.
	for i in range(60):
		cam.gpZoomAt(Vector2(800, 450), -1.0)
	gpCheck(cam.gpZoom >= 0.25 - 1e-6, "zoom clamped at min 0.25")
	# Repeatedly zoom in far past the clamp.
	for i in range(60):
		cam.gpZoomAt(Vector2(800, 450), 1.0)
	gpCheck(cam.gpZoom <= 4.0 + 1e-6, "zoom clamped at max 4.0")

func gpTestPan() -> void:
	var cam: GPCanvasCamera = GPCanvasCamera.new()
	cam.gpReset(Vector2(1600, 900))
	var offBefore: Vector2 = cam.gpOffset
	cam.gpPanBy(Vector2(50, -30))
	gpApprox(cam.gpOffset.x - offBefore.x, 50.0, 1e-4, "pan dx")
	gpApprox(cam.gpOffset.y - offBefore.y, -30.0, 1e-4, "pan dy")
