class_name GPRibbonCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Ribbon and toolbar construction, styling, mode mapping and tool-selection forwarding
# Ribbon 与工具栏的构建、样式、模式映射与工具选中转发
#
# WHY THIS EXISTS / 为何存在（架构优化建议 §3.2）：
#   GPMainWindow was carrying many unrelated responsibilities in one file; this coordinator
#   owns the "Ribbon and toolbar construction, styling, mode mapping and tool-selection forwarding" use case end to end, so the root keeps only assembly and forwarding.
#   GPMainWindow 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「Ribbon 与工具栏的构建、样式、模式映射与工具选中转发」这一用例，
#   使根类只保留装配与转发。
#
# Interaction / 交互方式：
#   - the root creates this coordinator and injects itself as gpHost (composition root);
#     根类创建本协调者并把自身注入为 gpHost（组合根装配）；
#   - the root forwards menu / toolbar actions here, never the other way round — this class
#     does not reach back into menus or the ribbon;
#     根类把菜单/工具栏动作转发到此处，绝不反向 —— 本类不回指菜单或 Ribbon；
#   - UI refresh goes through gpHost._gpSetState / the docks the root owns.
#     UI 刷新经由 gpHost._gpSetState 及根类持有的停靠栏完成。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPMainWindow = null


# Map a toolbar action to its canvas mode, or -1 for non-mode buttons (e.g. "new").
# 把工具栏动作映射到对应画布模式；非模式按钮（如「新建」）返回 -1。
func gpModeForAction(gpAction: String) -> int:
	match gpAction:
		"select":
			return GPCanvas2D.GPMode.GP_SELECT
		"connect":
			return GPCanvas2D.GPMode.GP_CONNECT
		"line":
			return GPCanvas2D.GPMode.GP_DRAW_LINE
		"circle":
			return GPCanvas2D.GPMode.GP_DRAW_CIRCLE
		"rect":
			return GPCanvas2D.GPMode.GP_DRAW_RECT
		"polyline":
			return GPCanvas2D.GPMode.GP_DRAW_POLYLINE
		"pipe":
			return GPCanvas2D.GPMode.GP_PIPE
		"signal":
			return GPCanvas2D.GPMode.GP_SIGNAL
	return -1


# ============================ in-place symbol editing ============================
# ============================ 就地图元编辑 ============================
# Open the isolation layer for one symbol type directly over the active canvas.
# 为某个图元类型在活动画布正上方打开隔离层。
# Open the "Make Symbol" dialog pre-loaded with the annotation-shape geometry the user promoted
# from the main canvas. On confirm it registers / persists a GPSymbolDef (same display-name ->
# overwrite existing, else new) and refreshes the palette + canvas.
# 打开「生成图元」对话框，预装主画布上被选中的注释图形几何。确定后注册并持久化一个
# GPSymbolDef（显示名相同则覆盖已有图元，否则新建）并刷新图元库与画布。

# Highlight the toggle button matching the active canvas mode (select / connect / draw tools).
# The optional gpMode parameter lets this serve as the gpModeChanged signal callback (1 arg)
# while remaining callable with 0 args elsewhere. When gpMode < 0 the live canvas mode is read.
# 高亮与当前画布模式匹配的开关按钮（选择 / 连线 / 绘图工具）。可选 gpMode 参数使其既能作为
# gpModeChanged 信号的 1 参回调，又能在别处 0 参调用；gpMode < 0 时读取画布实时模式。
func gpSyncToolBar(gpMode: int = -1) -> void:
	# The Ribbon owns the mode highlight now; delegate to it (P0 / ADR-UI-01).
	# 模式高亮现由 Ribbon 负责，委托给它（P0 / ADR-UI-01）。
	if gpHost.gpRibbon != null:
		var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
		if gpMode < 0:
			gpMode = GPCanvas2D.GPMode.GP_SELECT if gpCanvas == null else gpCanvas.gpMode
		gpHost.gpRibbon.gpSyncMode(gpMode)
		return
	if gpHost.gpToolBar == null:
		return
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpMode < 0:
		gpMode = GPCanvas2D.GPMode.GP_SELECT if gpCanvas == null else gpCanvas.gpMode
	for gpAct in gpHost.gpToolBtns.keys():
		var gpBtn: Button = gpHost.gpToolBtns[gpAct]
		var gpM: int = gpModeForAction(gpAct)
		gpBtn.button_pressed = (gpM >= 0 and gpMode == gpM)

# Toolbar button handler: select / connect / drawing tools switch the canvas mode; the
# "New Symbol…" button opens the isolation editor for advanced symbol authoring.
# 工具栏按钮处理：选择/连线/绘图工具切换画布模式；「新建图元…」按钮打开隔离编辑器用于高级图元创作。
func gpOnToolBarPressed(gpAction: String) -> void:
	var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCanvas == null:
		return
	match gpAction:
		"select":
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_SELECT)
			gpCanvas.gpConnectFrom = ""
			gpHost._gpSetState("status.mode_select")
		"connect":
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_CONNECT)
			gpHost._gpSetState("status.mode_connect")
		"line":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_LINE)
			gpHost._gpSetState("status.mode_line")
		"circle":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_CIRCLE)
			gpHost._gpSetState("status.mode_circle")
		"rect":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_RECT)
			gpHost._gpSetState("status.mode_rect")
		"polyline":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_POLYLINE)
			gpHost._gpSetState("status.mode_polyline")
		"pipe":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_PIPE)
			gpHost._gpSetState("status.mode_pipe")
		"signal":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_SIGNAL)
			gpHost._gpSetState("status.mode_signal")
		# ---- view / edit commands surfaced on the Ribbon (P0) ----
		# ---- Ribbon 上暴露的视图/编辑命令（P0） ----
		"view_zoom_in":
			gpCanvas.gpZoomStep(1.0)
		"view_zoom_out":
			gpCanvas.gpZoomStep(-1.0)
		"view_fit":
			gpCanvas.gpResetView()
			gpHost._gpSetState("status.view_reset")
		"edit_undo":
			gpHost._gpMenuUndo()
		"edit_redo":
			gpHost._gpMenuRedo()
		"edit_delete":
			gpHost._gpDeleteSelected()
		"tool_settings":
			gpHost._gpOpenSettings()
	gpSyncToolBar()

# Add a thin vertical separator between tool groups.
# 在工具组之间加一条细竖直分隔线。
func gpAddSep() -> void:
	var gpSep: VSeparator = VSeparator.new()
	gpHost.gpToolBar.add_child(gpSep)

# Add one toolbar button. gpToggle buttons keep their pressed highlight and are tracked for sync.
# 添加一个工具栏按钮。gpToggle 按钮保持按下高亮并被记录以便同步。
func gpAddToolBtn(gpAction: String, gpKey: String, gpToggle: bool) -> Button:
	var gpBtn: Button = Button.new()
	gpBtn.text = I18n.gpTr(gpKey)
	gpBtn.tooltip_text = I18n.gpTr(gpKey)
	gpBtn.focus_mode = Control.FOCUS_NONE
	if gpToggle:
		gpBtn.toggle_mode = true
	gpBtn.pressed.connect(gpOnToolBarPressed.bind(gpAction))
	gpHost.gpToolBar.add_child(gpBtn)
	if gpToggle:
		gpHost.gpToolBtns[gpAction] = gpBtn
	return gpBtn

# 视觉分层（精致化）：
# 右栏 TabContainer 背景（左边界交由顶层叠加层画发丝线，避免双线）；tab 按钮统一 DOCK 色，
# 未选中/hover 也带 1px 发丝底线，使选中 accent 成为"高亮"而非孤零零的粗线；
# 整排 tab 统一 1px 发丝底线；选中态靠 accent 颜色 + 略亮背景区分，不发粗线。
# 三栏分隔条引擎 grabber 设为透明（视觉交给 GPOverlayChrome）。
# The whole tab row shares a 1px hairline; the selected tab is told apart by accent
# colour + a slightly lighter fill — no thick line. The splitter grabber is made
# transparent (visuals delegated to GPOverlayChrome).
func gpStyleChrome() -> void:
	if gpHost.gpTabs != null:
		# 右边界接缝由 GPOverlayChrome 统一绘制，这里不再重复画左边框。
		gpHost.gpTabs.add_theme_stylebox_override("panel",
			GPChromeStyle.gpStyleFor(GPChromeStyle.GP_DOCK_BG, 0))
		# 未选中 / hover 也带 1px 发丝底线，整排 tab 干净统一。
		var gpTabBg: StyleBoxFlat = GPChromeStyle.gpStyleFor(GPChromeStyle.GP_DOCK_BG, GPChromeStyle.SIDE_BOTTOM)
		gpHost.gpTabs.add_theme_stylebox_override("tab_unselected", gpTabBg)
		gpHost.gpTabs.add_theme_stylebox_override("tab_hovered", gpTabBg)
		# 选中态：1px accent 底线（与未选中同厚，仅颜色不同）+ 略亮背景，细腻区分。
		# Selected: a 1px accent underline (same thickness as unselected, colour only
		# differs) plus a slightly lighter fill — delicate distinction, no heavy line.
		var gpTabSel: StyleBoxFlat = StyleBoxFlat.new()
		gpTabSel.bg_color = Color(0.118, 0.131, 0.163)
		gpTabSel.border_color = GPChromeStyle.GP_ACCENT
		gpTabSel.border_width_bottom = 1
		gpHost.gpTabs.add_theme_stylebox_override("tab_selected", gpTabSel)
	if gpHost.gpBodySplit != null:
		# 引擎 grabber 透明：拖拽仍可用，但不再画粗亮块；接缝发丝线 + 悬停高亮
		# 由 GPOverlayChrome（顶层叠加层）绘制，细腻且不双重描边。
		var gpDrag: StyleBoxFlat = StyleBoxFlat.new()
		gpDrag.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		gpHost.gpBodySplit.add_theme_stylebox_override("dragger", gpDrag)
		var gpGrab: StyleBoxFlat = StyleBoxFlat.new()
		gpGrab.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		gpHost.gpBodySplit.add_theme_stylebox_override("grabber", gpGrab)

# ============================ drawing toolbar ============================
# ============================ 绘图工具栏 ============================
# Build the Ribbon command bar and insert it between the menu bar and the body in the
# root VBox (the same slot the old DrawToolBar occupied). The Ribbon emits
# gpActionTriggered, which we route to the existing toolbar handler. To REVERT to the
# previous flat toolbar, rename this back to _gpBuildToolBar and restore that builder.
# 构建 Ribbon 命令栏并插入根 VBox 的菜单栏与主体之间（即原 DrawToolBar 的位置）。
# Ribbon 发射 gpActionTriggered，我们将其路由到既有的工具栏处理器。要回退旧平铺工具栏，
# 把本函数改回 _gpBuildToolBar 并恢复其构建体即可。
func gpBuildRibbon() -> void:
	# NOTE: this coordinator is a RefCounted, not a Node — the $-syntax is unavailable here,
	# so the layout node is resolved through the host.
	# 注意：本协调者是 RefCounted 而非 Node，此处无法使用 $ 语法，故经宿主解析布局节点。
	var gpVLayout: VBoxContainer = gpHost.get_node("VLayout") as VBoxContainer
	gpHost.gpRibbon = GPPIDRibbon.new()
	gpHost.gpRibbon.name = "Ribbon"
	gpHost.gpRibbon.gpActionTriggered.connect(gpOnToolBarPressed)
	gpVLayout.add_child(gpHost.gpRibbon)
	gpVLayout.move_child(gpHost.gpRibbon, 1)
	gpSyncToolBar()

# A tool button was pressed: select / connect / custom.
# 工具按钮被按下：选择 / 连线 / 自定义。
func gpOnToolSelected(gpType: String) -> void:
	if gpType == "select":
		gpHost.gpActiveCanvas().gpSetMode(GPCanvas2D.GPMode.GP_SELECT)
		gpHost.gpActiveCanvas().gpConnectFrom = ""
		gpHost._gpSetState("status.mode_select")
	elif gpType == "connect":
		gpHost.gpActiveCanvas().gpSetMode(GPCanvas2D.GPMode.GP_CONNECT)
		gpHost._gpSetState("status.mode_connect")
	elif gpType == "custom":
		gpHost._gpSetState("status.custom_pending")


# A symbol was requested for deletion from the left library. The symbol may be placed on
# ANY sheet, so scan every canvas: if it is in use, ask for confirmation and cascade-remove
# the placed instances; otherwise delete it from the library directly.
# 左侧图元库请求删除某图元。该图元可能位于任意图纸，故扫描所有画布：若正在使用则确认后
# 级联清理画布实例；否则直接从图元库删除。

# ============================ left palette ============================
# ============================ 左侧图元库 ============================
# A symbol was picked from the left palette: switch to placement mode.
# 从左侧图元库选中图元：切换到放置模式。
func gpOnSymbolPicked(gpTypeId: String) -> void:
	gpHost.gpActiveCanvas().gpPendingDef = gpHost._gpDefFor(gpTypeId)
	gpHost.gpActiveCanvas().gpSetMode(GPCanvas2D.GPMode.GP_SELECT)
	gpHost.gpActiveCanvas().gpConnectFrom = ""
	var gpDef: GPSymbolDef = gpHost._gpDefFor(gpTypeId)
	var gpName: String = gpDef.gpDisplayName if gpDef else gpTypeId
	gpHost._gpSetState("status.symbol_picked", [gpName])
