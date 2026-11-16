class_name GPProjectCard
extends PanelContainer

# One project card in the manager list — Godot-PM-like row, P&ID-adapted (W13 feedback).
# Godot shows engine version + path; we show PROJECT attributes (owner / sheets / members).
# 管理器列表里的单张项目卡 —— Godot 式行卡，P&ID 适配（W13 反馈）。
# Godot 显示引擎版本 + 路径；我们显示**工程属性**（业主 / 图纸 / 成员）。
#
# DESIGN / 设计：
# The DATA side is a pure static projection (gpAssembleData) so headless tests can pin
# the card content without instantiating UI; the VIEW side (gpPopulate) only formats what
# the projection already decided. Cards are rebuilt on refresh, so they translate at build
# time rather than via live rebinding.
# 数据侧是纯静态投影（gpAssembleData），headless 测试无需实例化 UI 即可钉住卡片内容；
# 视图侧（gpPopulate）只格式化投影已决定的东西。卡片随刷新重建，构建期翻译即可。

signal gp_open_requested(gpPath: String)
signal gp_selected(gpPath: String)
# Right-click context menu request: the card is short-lived (rebuilt on every refresh),
# so the POPUP lives on the manager — the card only reports the path and screen position.
# 右键上下文菜单请求：卡片短命（随刷新重建），弹窗住**管理器**层 —— 卡片只上报路径
# 与屏幕位置。
signal gp_context_requested(gpPath: String, gpScreenPos: Vector2)

var gpPath: String = ""
var gpSelected: bool = false
var gpTitleLabel: Label
var gpPathLabel: Label
var gpMetaLabel: Label
var gpTimeLabel: Label
var gpBadge: Label
var gpStyleNormal: StyleBoxFlat
var gpStyleSelected: StyleBoxFlat


# Pure projection: directory entry + peeked meta -> display fields. Hostile-input safe:
# every read goes through str()/int() with defaults, no casts.
# 纯投影：目录条目 + 摘取的元数据 -> 显示字段。敌意输入安全：
# 全部经 str()/int() 带默认值读取，无强转。
static func gpAssembleData(gpEntry: Dictionary, gpMeta: Dictionary) -> Dictionary:
	var gpPathVal: String = str(gpEntry.get("path", ""))
	var gpFileName: String = str(gpEntry.get("file_name", ""))
	var gpTitle: String = str(gpMeta.get("title", ""))
	if gpTitle.is_empty():
		# Fallback: file stem without the .pid.json suffix.
		# 兜底：去掉 .pid.json 后缀的文件名主干。
		gpTitle = gpFileName.trim_suffix(GPProjectLibrary.GP_ARCHIVE_SUFFIX)
	var gpOwner: String = str(gpMeta.get("owner", ""))
	if gpOwner.is_empty():
		gpOwner = "—"
	var gpSize: int = int(gpEntry.get("size_bytes", 0))
	var gpSizeText: String = "—"
	if gpSize > 0:
		gpSizeText = "%d B" % gpSize
	if gpSize >= 1024 * 1024:
		gpSizeText = "%.1f MB" % (float(gpSize) / (1024.0 * 1024.0))
	elif gpSize >= 1024:
		gpSizeText = "%.1f KB" % (float(gpSize) / 1024.0)
	var gpTimeText: String = ""
	var gpMsec: int = int(gpEntry.get("modified_msec", 0))
	if gpMsec > 0:
		var gpDt: Dictionary = Time.get_datetime_dict_from_unix_time(int(gpMsec / 1000.0))
		gpTimeText = "%04d-%02d-%02d %02d:%02d" % [int(gpDt.get("year", 1970)),
			gpDt.get("month", 1), gpDt.get("day", 1),
			gpDt.get("hour", 0), gpDt.get("minute", 0)]
	return {
		"path": gpPathVal,
		"file_name": gpFileName,
		"title": gpTitle,
		"owner": gpOwner,
		"sheet_count": int(gpMeta.get("sheet_count", 0)),
		"member_count": int(gpMeta.get("member_count", 0)),
		"version": int(gpMeta.get("container_version", 0)),
		"size_text": gpSizeText,
		"time_text": gpTimeText,
	}


func _init() -> void:
	custom_minimum_size = Vector2(0, 64)
	gpStyleNormal = StyleBoxFlat.new()
	gpStyleNormal.bg_color = Color(0.13, 0.145, 0.17)
	gpStyleSelected = StyleBoxFlat.new()
	gpStyleSelected.bg_color = Color(0.17, 0.20, 0.26)
	gpStyleSelected.border_color = Color(0.29, 0.56, 0.86)
	gpStyleSelected.set_border_width_all(1)
	for gpStyle in [gpStyleNormal, gpStyleSelected]:
		gpStyle.set_corner_radius_all(8)
		gpStyle.content_margin_left = 12.0
		gpStyle.content_margin_right = 12.0
		gpStyle.content_margin_top = 8.0
		gpStyle.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", gpStyleNormal)
	var gpRow: HBoxContainer = HBoxContainer.new()
	gpRow.add_theme_constant_override("separation", 12)
	add_child(gpRow)
	# Badge: the project initial on a rounded plate — identity without an icon pipeline.
	# 徽标：圆角色板上的工程首字母 —— 无需图标管线即可获得辨识度。
	gpBadge = Label.new()
	gpBadge.custom_minimum_size = Vector2(40, 40)
	gpBadge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gpBadge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gpBadge.add_theme_font_size_override("font_size", 18)
	var gpBadgeStyle: StyleBoxFlat = StyleBoxFlat.new()
	gpBadgeStyle.bg_color = Color(0.22, 0.32, 0.48)
	gpBadgeStyle.set_corner_radius_all(10)
	gpBadge.add_theme_stylebox_override("normal", gpBadgeStyle)
	gpRow.add_child(gpBadge)
	var gpMid: VBoxContainer = VBoxContainer.new()
	gpMid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpMid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gpMid.add_theme_constant_override("separation", 2)
	gpRow.add_child(gpMid)
	gpTitleLabel = Label.new()
	gpTitleLabel.add_theme_font_size_override("font_size", 15)
	gpTitleLabel.clip_text = true
	gpMid.add_child(gpTitleLabel)
	gpPathLabel = Label.new()
	gpPathLabel.add_theme_font_size_override("font_size", 11)
	gpPathLabel.modulate = Color(1, 1, 1, 0.5)
	gpPathLabel.clip_text = true
	gpMid.add_child(gpPathLabel)
	var gpRight: VBoxContainer = VBoxContainer.new()
	gpRight.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gpRight.add_theme_constant_override("separation", 2)
	gpRow.add_child(gpRight)
	gpMetaLabel = Label.new()
	gpMetaLabel.add_theme_font_size_override("font_size", 11)
	gpMetaLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gpMetaLabel.modulate = Color(1, 1, 1, 0.75)
	gpRight.add_child(gpMetaLabel)
	gpTimeLabel = Label.new()
	gpTimeLabel.add_theme_font_size_override("font_size", 11)
	gpTimeLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gpTimeLabel.modulate = Color(1, 1, 1, 0.5)
	gpRight.add_child(gpTimeLabel)
	gui_input.connect(_gpOnGuiInput)


# Fill the card from an assembled projection. Version 0 (unrecognized container) is
# flagged honestly instead of being hidden.
# 用组装好的投影填充卡片。版本 0（未识别容器）诚实标出而非隐藏。
func gpPopulate(gpCard: Dictionary) -> void:
	gpPath = str(gpCard.get("path", ""))
	var gpTitle: String = str(gpCard.get("title", "—"))
	gpTitleLabel.text = gpTitle
	# Badge initial: first character, upper-cased for latin, CJK passes through.
	# 徽标首字母：拉丁字母大写化，中日韩字符原样。
	var gpInitial: String = gpTitle.substr(0, 1)
	gpBadge.text = gpInitial.to_upper()
	gpPathLabel.text = gpPath
	var gpVer: int = int(gpCard.get("version", 0))
	var gpVerText: String = "v4"
	if gpVer > 0 and gpVer != 4:
		gpVerText = I18n.gpTr("pc.unknown_version") % gpVer
	elif gpVer <= 0:
		gpVerText = I18n.gpTr("pc.unrecognized")
	gpMetaLabel.text = I18n.gpTr("pc.card_meta") % [
		str(gpCard.get("owner", "—")), int(gpCard.get("sheet_count", 0)),
		int(gpCard.get("member_count", 0)), gpVerText]
	gpTimeLabel.text = "%s   ·   %s" % [str(gpCard.get("time_text", "")), str(gpCard.get("size_text", ""))]
	tooltip_text = gpPath


# Selection chrome: the border plate flips; selection state survives refreshes because
# the manager re-applies it while rebuilding.
# 选中外观：边框色板翻转；刷新时管理器会重新套用，故选中状态可跨刷新保留。
func gpSetSelected(gpOn: bool) -> void:
	gpSelected = gpOn
	add_theme_stylebox_override("panel", gpStyleSelected if gpOn else gpStyleNormal)


# Click selects; double-click opens — the Godot PM interaction contract. Right-click
# selects AND asks the manager for the context menu (screen position = where the mouse is).
# 单击选中；双击打开 —— 与 Godot 管理器一致的交互契约。右键先选中再向管理器请求
# 上下文菜单（屏幕位置 = 鼠标所在处）。
func _gpOnGuiInput(gpEvent: InputEvent) -> void:
	var gpMb := gpEvent as InputEventMouseButton
	if gpMb == null or not gpMb.pressed:
		return
	if gpMb.button_index == MOUSE_BUTTON_RIGHT:
		gp_selected.emit(gpPath)
		if not gpPath.is_empty():
			gp_context_requested.emit(gpPath, gpMb.global_position)
	elif gpMb.double_click:
		if not gpPath.is_empty():
			gp_open_requested.emit(gpPath)
	else:
		gp_selected.emit(gpPath)
