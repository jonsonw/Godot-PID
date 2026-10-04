class_name GPRibbonCoordinator
extends RefCounted
# Copyright © 2026 Jonson Wang
# Ribbon and toolbar construction, styling, mode mapping and tool-selection forwarding
# Ribbon 与工具栏的构建、样式、模式映射与工具选中转发
#
# WHY THIS EXISTS / 为何存在：
# GPMainWindow was carrying many unrelated responsibilities in one file; this coordinator
# owns the "Ribbon and toolbar construction, styling, mode mapping and tool-selection forwarding" use case end to end, so the root keeps only assembly and forwarding.
# GPMainWindow 曾把多类互不相关的职责压在同一文件里；本协调者端到端接管「Ribbon 与工具栏的构建、样式、模式映射与工具选中转发」这一用例，
# 使根类只保留装配与转发。
#
# Interaction / 交互方式：
# - the root creates this coordinator and injects itself as gpHost (composition root);
# 根类创建本协调者并把自身注入为 gpHost（组合根装配）；
# - the root forwards menu / toolbar actions here, never the other way round — this class
# does not reach back into menus or the ribbon;
# 根类把菜单/工具栏动作转发到此处，绝不反向 —— 本类不回指菜单或 Ribbon；
# - UI refresh goes through gpHost.gpSetState() / the docks the root owns.
# UI 刷新经由 gpHost.gpSetState() 及根类持有的停靠栏完成。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpHost: GPMainWindow = null



# ============================ symbol editing ============================
# ============================ 图元编辑 ============================
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
	# The Ribbon built the highlight while it existed; since its removal the LEFT
	# PALETTE's tool blocks own the mode highlight, so delegate there.
	# Ribbon 存在时由它承担模式高亮；其移除后改由**左侧图元库**的工具块承担，故委托给它。
	if gpHost.gpLeftDock != null and gpHost.gpLeftDock.has_method("gpSyncMode"):
		var gpCanvas: GPCanvas2D = gpHost.gpActiveCanvas()
		if gpMode < 0:
			gpMode = GPCanvas2D.GPMode.GP_SELECT if gpCanvas == null else gpCanvas.gpMode
		gpHost.gpLeftDock.gpSyncMode(gpMode)

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
			gpHost.gpSetState("status.mode_select")
		"connect":
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_CONNECT)
			gpHost.gpSetState("status.mode_connect")
		"line":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_LINE)
			gpHost.gpSetState("status.mode_line")
		"circle":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_CIRCLE)
			gpHost.gpSetState("status.mode_circle")
		"rect":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_RECT)
			gpHost.gpSetState("status.mode_rect")
		"polyline":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_DRAW_POLYLINE)
			gpHost.gpSetState("status.mode_polyline")
		"pipe":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_PIPE)
			gpHost.gpSetState("status.mode_pipe")
		"signal":
			gpCanvas.gpPendingDef = null
			gpCanvas.gpSetMode(GPCanvas2D.GPMode.GP_SIGNAL)
			gpHost.gpSetState("status.mode_signal")
		"view_zoom_in":
			gpCanvas.gpZoomStep(1.0)
		"view_zoom_out":
			gpCanvas.gpZoomStep(-1.0)
		"view_fit":
			gpCanvas.gpResetView()
			gpHost.gpSetState("status.view_reset")
		"edit_undo":
			gpHost.gpMenuUndo()
		"edit_redo":
			gpHost.gpMenuRedo()
		"edit_delete":
			gpHost.gpDeleteSelected()
		"tool_settings":
			gpHost.gpOpenSettings()
	gpSyncToolBar()


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
 # 未选中 / hover 也带 1px 深色底线，整排 tab 干净统一；内容边距收紧，
 # 使 tab 选择块小巧（参考图右栏顶部的 tab 尺寸）。
		var gpTabBg: StyleBoxFlat = GPChromeStyle.gpStyleFor(GPChromeStyle.GP_DOCK_BG, GPChromeStyle.SIDE_BOTTOM)
		gpTabBg.content_margin_left = 10.0
		gpTabBg.content_margin_right = 10.0
		gpTabBg.content_margin_top = 3.0
		gpTabBg.content_margin_bottom = 3.0
		gpHost.gpTabs.add_theme_stylebox_override("tab_unselected", gpTabBg)
		gpHost.gpTabs.add_theme_stylebox_override("tab_hovered", gpTabBg)
 # 选中态：与参考图菜单「开始」tab 一致的深色底（#212A34，比 chrome 暗）+
 # 1px accent 底线；尺寸与未选中相同，仅颜色不同。
 # Selected: the same dark fill as the reference menu's active tab (#212A34,
 # darker than chrome) plus a 1px accent underline; size identical to unselected,
 # colour only differs.
		var gpTabSel: StyleBoxFlat = gpTabBg.duplicate() as StyleBoxFlat
		gpTabSel.bg_color = Color(0.129, 0.165, 0.204)
		gpTabSel.border_color = GPChromeStyle.GP_ACCENT
		gpTabSel.border_width_bottom = 1
		gpHost.gpTabs.add_theme_stylebox_override("tab_selected", gpTabSel)
 # Tab 行两端不留边距（参考图中 tab 从面板左缘起排）。
 # No side margin on the tab row (reference tabs start at the panel's left edge).
		gpHost.gpTabs.add_theme_constant_override("side_margin", 0)
	if gpHost.gpBodySplit != null:
 # 引擎 grabber 透明：拖拽仍可用，但不再画粗亮块；接缝发丝线 + 悬停高亮
 # 由 GPOverlayChrome（顶层叠加层）绘制，细腻且不双重描边。
		var gpDrag: StyleBoxFlat = StyleBoxFlat.new()
		gpDrag.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		gpHost.gpBodySplit.add_theme_stylebox_override("dragger", gpDrag)
		var gpGrab: StyleBoxFlat = StyleBoxFlat.new()
		gpGrab.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		gpHost.gpBodySplit.add_theme_stylebox_override("grabber", gpGrab)

# A tool button was pressed: select / connect / custom.
# 工具按钮被按下：选择 / 连线 / 自定义。
func gpOnToolSelected(gpType: String) -> void:
	if gpType == "select":
		gpHost.gpActiveCanvas().gpSetMode(GPCanvas2D.GPMode.GP_SELECT)
		gpHost.gpActiveCanvas().gpConnectFrom = ""
		gpHost.gpSetState("status.mode_select")
	elif gpType == "connect":
		gpHost.gpActiveCanvas().gpSetMode(GPCanvas2D.GPMode.GP_CONNECT)
		gpHost.gpSetState("status.mode_connect")
	elif gpType == "custom":
		gpHost.gpSetState("status.custom_pending")


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
	gpHost.gpActiveCanvas().gpPendingDef = gpHost.gpDefFor(gpTypeId)
	gpHost.gpActiveCanvas().gpSetMode(GPCanvas2D.GPMode.GP_SELECT)
	gpHost.gpActiveCanvas().gpConnectFrom = ""
	var gpDef: GPSymbolDef = gpHost.gpDefFor(gpTypeId)
	var gpName: String = gpDef.gpDisplayName if gpDef else gpTypeId
	gpHost.gpSetState("status.symbol_picked", [gpName])


# A library tile was DRAGGED onto the canvas: arm the attachment gesture instead of the placement
# mode (规划 §15, interaction mode 1).
# 某图元库图块被**拖到**画布上：给附件手势上膛，而非进入放置模式（规划 §15 交互模式一）。
#
# WHY IT IS A SEPARATE ENTRY POINT AND NOT A FLAG ON gpOnSymbolPicked / 为何是独立入口而非
# gpOnSymbolPicked 的一个开关：
# the two gestures leave the canvas in INCOMPATIBLE states. A pick sets gpPendingDef, so the next
# click drops a free-floating node at the cursor; a drag arms gpPendingAttach, so the next click
# must land on a host anchor. Sharing one function would need a mode flag threaded through every
# branch, and the failure mode of getting it wrong is silent (a stray node on the sheet).
# 两个手势会让画布处于**互不兼容**的状态。点选设置 gpPendingDef，于是下一次点击在光标处丢下
# 一个自由悬浮节点；拖动给 gpPendingAttach 上膛，于是下一次点击必须落在宿主锚点上。共用一个函数
# 就得让一个模式开关穿过每个分支，而搞错的失败方式是静默的（图纸上多出一个游离节点）。
#
# A PRIMARY symbol can never be mounted, so gpArmAttach() refuses it here rather than letting the
# user carry a gesture that is guaranteed to fail. NOTE: the palette already classifies a drag on a
# primary symbol as a pick, so in practice this branch only fires for a stale/unknown definition.
# 主图元永远无法挂载，故 gpArmAttach() 在此拒绝它，而不是让用户带着一个注定失败的手势。
# 注意：图元库已把主图元上的拖动归类为点选，故实际上本分支只在定义过期 / 未知时触发。
func gpOnSymbolDragStarted(gpTypeId: String) -> void:
	var gpCv: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCv == null:
		return
	var gpDef: GPSymbolDef = gpHost.gpDefFor(gpTypeId)
	var gpName: String = gpDef.gpDisplayName if gpDef != null else gpTypeId
	if not gpCv.gpArmAttach(gpTypeId):
		gpHost.gpSetState("status.attach_not_mountable", [gpName])
		return
	gpHost.gpSetState("status.attach_armed", [gpName])
