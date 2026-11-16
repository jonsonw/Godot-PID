class_name GPProjectSwitchButton
extends Button

# The editor-side entry back into the project manager (W13 T2b -> Godot-style rework):
# a small corner pill. The editor never embeds manager logic — pressing it asks the
# boot root (found via its group) to swap screens; the unsaved-work confirmation lives
# there, so the pill stays a two-line relay.
# 编辑器侧回到项目管理器的入口（W13 T2b -> Godot 式重构）：右下角小胶囊按钮。
# 编辑器不内嵌任何管理器逻辑 —— 按下只是经分组找到 boot root 请求换屏；未保存确认
# 住在 boot root，胶囊保持两行中继。
#
# WHY A NEW FILE + SCENE WIRING / 为何是新文件 + 场景接线：
# main_window.gd and overlay_chrome.gd are budget-frozen (ADR-47, shrink-only), so the
# button hangs off main.tscn as its own node — zero growth in any frozen file.
# main_window.gd 与 overlay_chrome.gd 都受预算冻结（ADR-47，只减不增），因此按钮以
# 独立节点挂进 main.tscn —— 冻结文件零增长。

const GP_BOOT_GROUP: String = "gp_boot_root"


func _ready() -> void:
	# Bottom-right corner, above all regular controls. anchors AND offsets: anchors alone
	# leave a fresh control at 0x0 (same W13 bug as the manager screen); margin 16 = the
	# old "+/-16 nudge", now resize-stable.
	# 右下角，盖在常规控件之上。锚点**和**偏移一起设：只设锚点时新控件仍是 0 尺寸（与
	# 管理器主屏同源的 W13 缺陷）；margin 16 即原来的「±16 硬挪」，且在窗口拉伸下稳定。
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	text = I18n.gpTr("pc.switch_btn")
	tooltip_text = I18n.gpTr("pc.switch_tip")
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_gpOnPressed)
	if I18n.gpLocaleChanged.is_connected(_gpApplyTexts) == false:
		I18n.gpLocaleChanged.connect(_gpApplyTexts)


func _gpApplyTexts(_gpLocale: String) -> void:
	text = I18n.gpTr("pc.switch_btn")
	tooltip_text = I18n.gpTr("pc.switch_tip")


func _gpOnPressed() -> void:
	var gpBoot: GPBootRoot = get_tree().get_first_node_in_group(GP_BOOT_GROUP) as GPBootRoot
	if gpBoot != null:
		gpBoot.gpShowManager()
