class_name GPStatusBar
extends HBoxContainer

# 底部状态栏（视觉分层）。
# Bottom status bar (visual layering).
#
# 在深色 chrome 上绘制：最暗一档背景 + 顶部 1px 边界线（与上方画布区分隔）；
# 标签之间留白，首位留左内边距，由粗犷转为精致。背景自绘于底层，子标签前景在上。
# Paints the darkest chrome background + a 1px top border (separating it from the
# canvas above); generous spacing and a left inset refine the look. The background
# is drawn beneath the label children.
# 编码规范：所有变量均显式声明类型。

# Build the status-bar look: spacing + left inset + a one-shot redraw so the
# custom background paints after the first layout pass.
# 构建状态栏外观：间距 + 左内边距 + 首帧重绘，使自绘背景在首次布局后绘制。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	add_theme_constant_override("separation", 10)
	var gpInset: Control = Control.new()
	gpInset.custom_minimum_size = Vector2(8.0, 0.0)
	gpInset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gpInset)
	move_child(gpInset, 0)
	_gpBuildToggles()
	_gpPinLabelWidths()
	queue_redraw()


# Pin the three live-text labels to fixed widths and make the state label clip its text.
# Their texts change width while zooming / saving (zoom %, world coords, saved-path
# messages), and unpinned widths made the bottom row — including the snap/ortho toggle
# icons — drift horizontally on EVERY change (the reported "icons drift while zooming").
# Worse: the state label's full-text minimum width inflated the CENTER pane's minimum,
# which clamped the right splitter after a save printed a long path (part of the
# reported "can't drag the panels after save/open").
# 把三个动态文字标签钉到固定宽，并让状态标签裁剪长文本。缩放/保存时这些文字的宽度会变
#（缩放百分比、世界坐标、保存路径提示），未钉宽时底行 —— 包括捕捉/正交开关图标 —— 每次
# 都会横移（即用户报告的「缩放时图标轻微漂移」）。更糟的是：状态标签的**全文最小宽**会
# 撑爆中心列最小宽，保存后打印长路径时把右分隔条钳死（「保存/打开后无法拖动」的一部分）。
func _gpPinLabelWidths() -> void:
	var gpPins: Dictionary = {"SelLabel": 180.0, "CoordLabel": 150.0, "ZoomLabel": 96.0}
	for gpK in gpPins:
		var gpLbl: Label = get_node_or_null(NodePath(str(gpK))) as Label
		if gpLbl != null:
			gpLbl.custom_minimum_size = Vector2(float(gpPins[gpK]), 0.0)
	var gpState: Label = get_node_or_null(NodePath("StateLabel")) as Label
	if gpState != null:
		# clip_text drops the label's text-based minimum width, so a long path can no
		# longer inflate the layout; ellipsis keeps the truncation readable.
		# clip_text 使标签不再以全文计算最小宽，长路径无法再撑爆布局；省略号保持可读。
		gpState.clip_text = true
		gpState.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


# Right-aligned CAD toggles: snap / ortho + a snap-type menu. Bound to the SnapState
# singleton (the single source of truth) so enabling the UI regresses no existing tool.
# 右对齐的 CAD 开关：捕捉 / 正交 + 捕捉类型菜单。绑定 SnapState 单例（唯一事实源），
# 故启用该 UI 不回归任何既有工具。
func _gpBuildToggles() -> void:
	var gpSpacer: Control = Control.new()
	gpSpacer.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(gpSpacer)

	var gpSnap: CheckBox = CheckBox.new()
	gpSnap.text = I18n.gpTr("status.snap")
	gpSnap.button_pressed = SnapState.gpSnapEnabled
	gpSnap.toggled.connect(func(gpV: bool) -> void: SnapState.gpSetSnap(gpV))
	add_child(gpSnap)

	var gpOrtho: CheckBox = CheckBox.new()
	gpOrtho.text = I18n.gpTr("status.ortho")
	gpOrtho.button_pressed = SnapState.gpOrthoEnabled
	gpOrtho.toggled.connect(func(gpV: bool) -> void: SnapState.gpSetOrtho(gpV))
	add_child(gpOrtho)

	var gpType: MenuButton = MenuButton.new()
	gpType.text = I18n.gpTr("status.snap_type")
	var gpPop: PopupMenu = gpType.get_popup()
	gpPop.add_item(I18n.gpTr("snap.endpoint"), SnapState.GP_SNAP_TYPE.ENDPOINT)
	gpPop.add_item(I18n.gpTr("snap.midpoint"), SnapState.GP_SNAP_TYPE.MIDPOINT)
	gpPop.add_item(I18n.gpTr("snap.intersection"), SnapState.GP_SNAP_TYPE.INTERSECTION)
	gpPop.add_item(I18n.gpTr("snap.perpendicular"), SnapState.GP_SNAP_TYPE.PERPENDICULAR)
	gpPop.id_pressed.connect(func(gpId: int) -> void: SnapState.gpSetSnapType(gpId))
	add_child(gpType)


# Paint the chrome background + top border.
# 自绘 chrome 背景 + 顶部边界线。
func _draw() -> void:
	GPChromeStyle.gpDraw(self, GPChromeStyle.GP_CHROME_BG, GPChromeStyle.SIDE_TOP)
