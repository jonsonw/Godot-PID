class_name GPOverlayChrome
extends Control

# 顶层接缝叠加层（Main 的最后一个子节点，mouse_filter=IGNORE，纯视觉、不挡输入）。
# Topmost seam overlay (last child of Main, mouse_filter=IGNORE: visual only, never
# blocks input so the splitter beneath stays draggable).
#
# 在画布/侧栏之上绘制：
#   1) 随时存在的 1px 发丝接缝线（GP_BORDER，已调低对比度）；
#   2) 鼠标悬停到某条接缝时，其两侧亮起 2px accent 高亮，明确"此处可拖拽"。
# Paints above canvas/docks:
#   1) an always-on 1px hairline seam (GP_BORDER, low-contrast);
#   2) when the pointer hovers a seam, a 2px accent highlight flares on both sides —
#      an explicit "this is draggable" affordance.
# 编码规范：所有变量均显式声明类型。

# 三栏分隔条引用（由 _ready 解析）。
# The three-pane splitter reference (resolved in _ready).
var gpSplit: HSplitContainer = null


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	gpSplit = get_node_or_null("../VLayout/Body")
	if gpSplit != null and gpSplit.has_method("gpRegisterOverlay"):
		gpSplit.gpRegisterOverlay(self)
	queue_redraw()


func _draw() -> void:
	if gpSplit == null or not is_instance_valid(gpSplit):
		return
	var gpSplitRect: Rect2 = gpSplit.get_global_rect()
	# 接缝线只在 Body 纵向范围内绘制（不越界到菜单栏 / 状态栏）。
	# Seam lines are clipped to the Body's vertical extent (not bleeding into the
	# menu bar / status bar).
	var gpTop: float = make_canvas_position_local(Vector2(0.0, gpSplitRect.position.y)).y
	var gpBot: float = make_canvas_position_local(Vector2(0.0, gpSplitRect.end.y)).y
	gpTop = max(gpTop, 0.0)

	var gpSeams: PackedFloat32Array = gpSplit.gpSeamXsLocal()
	var gpOrigin: float = gpSplitRect.position.x
	var gpHover: int = gpSplit.gpHoverSeam

	for gpI in range(gpSeams.size()):
		var gpGx: float = gpOrigin + gpSeams[gpI]
		var gpLx: float = make_canvas_position_local(Vector2(gpGx, 0.0)).x
		# 细腻 1px 发丝基线。
		# Delicate 1px hairline baseline.
		draw_line(Vector2(gpLx + 0.5, gpTop), Vector2(gpLx + 0.5, gpBot),
			GPChromeStyle.GP_BORDER, 1.0)
		if gpI == gpHover:
			# 悬停：两侧 2px accent 高亮（细，不粗）。
			# Hover: a thin 2px accent highlight on both sides.
			draw_line(Vector2(gpLx - 0.5, gpTop), Vector2(gpLx - 0.5, gpBot),
				GPChromeStyle.GP_ACCENT, 2.0)
			draw_line(Vector2(gpLx + 1.5, gpTop), Vector2(gpLx + 1.5, gpBot),
				GPChromeStyle.GP_ACCENT, 2.0)
