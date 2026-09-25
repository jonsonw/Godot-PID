class_name GPOverlayChrome
extends Control

# 顶层接缝叠加层（Main 的最后一个子节点，mouse_filter=IGNORE，纯视觉、不挡输入）。
# Topmost seam overlay (last child of Main, mouse_filter=IGNORE: visual only, never
# blocks input so the splitter beneath stays draggable).
#
# 在画布/侧栏之上绘制：
# 1) 随时存在的 1px 发丝接缝线（GP_BORDER，已调低对比度）；
# 2) 鼠标悬停到某条接缝时，其两侧亮起 2px accent 高亮，明确"此处可拖拽"。
# Paints above canvas/docks:
# 1) an always-on 1px hairline seam (GP_BORDER, low-contrast);
# 2) when the pointer hovers a seam, a 2px accent highlight flares on both sides —
# an explicit "this is draggable" affordance.
# 编码规范：所有变量均显式声明类型。

# 三栏分隔条引用（由 _ready() 解析）。
# The three-pane splitter reference (resolved in _ready()).
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
	# ONE horizontal hairline right BELOW the command toolbar (at the Body's top
	# edge, drawn inside the toolbar's last pixel row). The docks <-> canvas
	# vertical hairlines are GONE (reference layout has none); the splitters stay
	# fully draggable and only reveal a hover highlight as the drag affordance.
	# 单条水平发丝线画在命令工具栏**正下方**（Body 顶缘、落在工具栏最后一行像素内）。
	# 侧栏 ↔ 画布之间的常驻竖向发丝线已移除（参考布局无此线）；分隔条仍可自由拖拽，
	# 仅保留悬停高亮作为「可拖拽」提示。
	var gpTop: float = make_canvas_position_local(Vector2(0.0, gpSplitRect.position.y)).y
	draw_line(Vector2(0.0, gpTop - 0.5), Vector2(size.x, gpTop - 0.5),
		GPChromeStyle.GP_BORDER, 1.0)

	# Hover-only drag affordance on the two splitter seams.
	# 两条分隔条接缝仅保留悬停高亮（拖拽可供性）。
	var gpSeams: PackedFloat32Array = gpSplit.gpSeamXsLocal()
	var gpOrigin: float = gpSplitRect.position.x
	var gpHover: int = gpSplit.gpHoverSeam
	if gpHover < 0 or gpHover >= gpSeams.size():
		return
	var gpGx: float = gpOrigin + gpSeams[gpHover]
	var gpLx: float = make_canvas_position_local(Vector2(gpGx, 0.0)).x
	var gpTopY: float = maxf(gpTop, 0.0)
	var gpBot: float = make_canvas_position_local(Vector2(0.0, gpSplitRect.end.y)).y
	draw_line(Vector2(gpLx - 0.5, gpTopY), Vector2(gpLx - 0.5, gpBot),
		GPChromeStyle.GP_ACCENT, 2.0)
	draw_line(Vector2(gpLx + 1.5, gpTopY), Vector2(gpLx + 1.5, gpBot),
		GPChromeStyle.GP_ACCENT, 2.0)
