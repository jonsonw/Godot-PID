class_name GPCanvasCamera
extends RefCounted
# Pure 2D pan/zoom camera used by the P&ID main canvas (P1-1a extraction). Holds the world-space
# offset and uniform zoom factor and exposes the world <-> screen coordinate transforms plus
# zoom-at-point math. It is a REFCOUNTED pure-data module with NO Control/Node dependency, so it
# can be unit-tested headlessly and reused by any future view (a second canvas, a split view, a
# 3D-correlated minimap, etc.).
# P&ID 主画布使用的纯 2D 平移/缩放相机（P1-1a 抽取）。持有世界空间偏移与统一缩放系数，暴露
# 世界 <-> 屏幕坐标变换与「以某点为中心缩放」数学。它是 RefCounted 纯数据模块，无 Control/Node
# 依赖，可 headless 单测，并被任何未来视图（第二个画布、分屏、与 3D 联动的缩略图等）复用。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Zoom clamp (world units per screen point inverse). Kept identical to the canvas constants.
# 缩放夹取范围（与画布原常量保持一致）。
const GP_ZOOM_MIN: float = 0.25
const GP_ZOOM_MAX: float = 4.0

# Step applied per wheel notch toward zoom-in / zoom-out.
# 每格滚轮向放大 / 缩小方向施加的步进系数。
const GP_ZOOM_STEP: float = 0.12


# World-space translation of the camera origin (screen point (0,0) maps to this world point via the
# formula below). Read/written directly by the canvas drawing hot-path for grid / hit-testing.
# 相机原点的世界空间平移（屏幕点 (0,0) 经下述公式映射到该世界点）。
var gpOffset: Vector2 = Vector2.ZERO

# Uniform zoom: number of screen points spanned by one world unit. 1.0 = world unit == 1 screen pt.
# 统一缩放：一个世界单位对应的屏幕点数。1.0 = 世界单位 == 1 屏幕点。
var gpZoom: float = 1.0


# Reset to 100% zoom and center the given viewport center on the world origin.
# 重置为 100% 缩放并把世界原点放到给定的视口中心。
func gpReset(gpViewportCenter: Vector2) -> void:
	gpZoom = 1.0
	gpOffset = gpViewportCenter


# Convert a world coordinate to a screen coordinate.
# 将世界坐标转换为屏幕坐标。
func gpScreenFromWorld(gpW: Vector2) -> Vector2:
	return gpW * gpZoom + gpOffset


# Convert a screen coordinate to a world coordinate.
# 将屏幕坐标转换为世界坐标。
func gpWorldFromScreen(gpS: Vector2) -> Vector2:
	return (gpS - gpOffset) / gpZoom


# Zoom by gpFactor wheel notches (±1 per notch) while keeping the world point under gpScreen stable.
# Returns true if the zoom actually changed (clamped), false if it was already at a clamp limit.
# 以 gpScreen 下的世界点为中心缩放 gpFactor 格（每格 ±1）。返回是否真的发生了缩放（夹取后）。
func gpZoomAt(gpScreen: Vector2, gpFactor: float) -> bool:
	var gpWorldBefore: Vector2 = gpWorldFromScreen(gpScreen)
	var gpNewZoom: float = clampf(gpZoom * (1.0 + GP_ZOOM_STEP * gpFactor), GP_ZOOM_MIN, GP_ZOOM_MAX)
	if is_equal_approx(gpNewZoom, gpZoom):
		return false
	gpZoom = gpNewZoom
	# Re-anchor so the cursor's world point stays fixed on screen.
	# 重新锚定，使光标下的世界点在屏幕上保持不动。
	var gpScreenAfter: Vector2 = gpScreenFromWorld(gpWorldBefore)
	gpOffset += gpScreen - gpScreenAfter
	return true


# Pan the camera by a screen-space delta (drag). World content moves opposite the pointer.
# 按屏幕增量平移相机（拖动）。世界内容相对指针反向移动。
func gpPanBy(gpDelta: Vector2) -> void:
	gpOffset += gpDelta
