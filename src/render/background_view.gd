class_name GPBackgroundView
extends Node2D

# Tracing underlay for 1:1 reproduction of a reference drawing (v0.1 Phase 5).
# 1:1 复刻参考图的追踪底图层（v0.1 Phase 5）。
# WHY A NODE UNDER world_root AT z_index -2: the underlay is part of the drawing, so it
# inherits the camera pan/zoom and aligns 1:1 with geometry at 100% zoom (1 world unit == 1 mm).
# Placing it BELOW the frame (-1) and below every symbol (0) makes it a faint reference the
# user can trace symbols and lines on top of — which is exactly what "reproduce this drawing
# 1:1" needs. It is NOT editable geometry: no node/edge is created for it, it never hit-tests.
# 为何挂在 world_root 下、z_index=-2：底图属于图纸，故继承相机平移缩放，在 100% 缩放下与几何
# 1:1 对齐（1 世界单位 = 1mm）。放在图框（-1）与所有符号（0）之下，使其成为淡参考，用户可在其
# 上描摹符号与连线 —— 这正是「1:1 复刻此图」所需。它不是可编辑几何：不生成节点/边、不参与拾取。
# See plan Phase 5 / 见计划 Phase 5。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

# The sheet this underlay references. Null = nothing drawn.
# 本底图引用的图纸。为 null 时不绘制。
var gpSheet: GPSheet = null

# Cached texture + cache key, so we reload only when the path actually changes.
# 缓存的纹理与缓存键：仅在路径确实变化时重新加载。
var _gpTex: Texture2D = null
var _gpTexPath: String = "<none>"


func _draw() -> void:
	if gpSheet == null:
		return
	if gpSheet.gpBackgroundPath == "":
		return
	var gpTex: Texture2D = _gpLoad()
	if gpTex == null:
		return
	var gpW: float = gpSheet.gpWidthMM
	var gpH: float = gpSheet.gpHeightMM
	if gpW <= 1.0 or gpH <= 1.0:
		return
	# Stretch the reference raster to the physical sheet rectangle so it is 1:1 with the
	# drawing at 100% zoom. The user is expected to pick an image whose aspect matches the
	# sheet (e.g. an A3 render for an A3 sheet), so stretching does not distort.
	# 把参考位图拉伸铺满整张物理图纸矩形，使 100% 缩放下与图纸 1:1。用户应放入与图幅
	# 匹配的图（如 A3 图纸用 A3 渲染图），故拉伸不变形。
	draw_texture_rect(gpTex, Rect2(0.0, 0.0, gpW, gpH), false,
		Color(1.0, 1.0, 1.0, clampf(gpSheet.gpBackgroundAlpha, 0.0, 1.0)))


# Load (and cache) the underlay texture. Returns null when the path is empty or unloadable.
# 加载（并缓存）底图纹理。路径为空或无法加载时返回 null。
func _gpLoad() -> Texture2D:
	var gpPath: String = gpSheet.gpBackgroundPath
	if gpPath == _gpTexPath and _gpTex != null:
		return _gpTex
	# A changed or cleared path invalidates the cache; clearing the stale texture also stops
	# drawing it on the frame where the path was just removed.
	# 路径变更或清空会使缓存失效；清除旧纹理也避免刚移除路径的帧上仍画着旧图。
	if gpPath != _gpTexPath:
		_gpTex = null
		_gpTexPath = gpPath
	if gpPath == "":
		return null
	var gpRes: Resource = load(gpPath)
	if gpRes is Texture2D:
		_gpTex = gpRes as Texture2D
	else:
		_gpTex = null
	return _gpTex


# Re-render after any background-affecting change (path / alpha / sheet size).
# 任何影响底图的改动后重绘（路径 / 透明度 / 图幅）。
func gpRefresh() -> void:
	queue_redraw()
