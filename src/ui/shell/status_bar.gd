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
	queue_redraw()


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
