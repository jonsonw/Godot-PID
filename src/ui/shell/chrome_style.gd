class_name GPChromeStyle
extends RefCounted

# 视觉分层色板（AutoCAD 2026 参考图实测值，2026-09-25 第二轮取样校准）。
# Visual layering palette (values sampled from the AutoCAD 2026 reference screenshot,
# second pass 2026-09-25).
#
# 设计原则 / Design intent（对照参考图取样 / against sampled reference values）:
# - 整个 chrome（标题/菜单/工具栏/左右侧栏/状态栏）同为 #394454 蓝灰；画布最暗 #212830。
#   参考图中侧栏与菜单栏**无色差**，只有「画布沉底」这一层明暗对比。
#   The whole chrome (title/menu/toolbars/docks/status) shares one blue-grey #394454;
#   the canvas is the darkest surface #212830 — in the reference the docks and the menu
#   row have NO tint difference, the only contrast is the sunken sheet.
# - 输入井 #4E5A70 **比面板亮**（AutoCAD 的属性值输入是浅色凹井）。
#   Input wells #4E5A70 are LIGHTER than the panel (AutoCAD property value wells).
# - 边界/接缝取更深的 #29323E（参考图中 chrome 与画布之间的深色缝隙），不是亮线。
#   Seams are a DARKER #29323E (the dark groove between chrome and canvas in the
#   reference), not a bright hairline.
# - 颜色均为数据自包含常量，便于统一微调（改这里即改全界面）。
# Colours are self-contained constants so a single edit restyles the whole UI.
# 编码规范：所有变量均显式声明类型。

# 菜单栏 / 工具栏 / 状态栏（chrome 档，#394454）
# Menu bar / toolbars / status bar — chrome tier (#394454).
const GP_CHROME_BG: Color = Color(0.224, 0.267, 0.329)

# 顶部命令工具栏（与 chrome 同色 —— 参考图中第二行图标区与菜单行无色差）
# Top command toolbar — same as chrome (the reference's icon row has no tint step
# against the menu row).
const GP_RIBBON_BG: Color = Color(0.224, 0.267, 0.329)

# 左右侧栏（图元库 / 属性区；参考图中与 chrome 同为 #394454）
# Left / right docks (symbol library / inspector); same #394454 as chrome in the
# reference.
const GP_DOCK_BG: Color = Color(0.224, 0.267, 0.329)

# 中心画布工作区（最暗，模型空间聚焦，#212830）
# Center canvas working area — darkest, model-space focus (#212830).
const GP_CANVAS_BG: Color = Color(0.129, 0.157, 0.188)

# 接缝 / 边界线（比两侧都深的 #29323E 凹缝 —— 参考图中 chrome 与画布之间的深色缝）
# Seam / border — a groove darker than BOTH neighbours (#29323E, the dark gap
# between chrome and canvas in the reference).
const GP_BORDER: Color = Color(0.161, 0.196, 0.243)

# 输入井底色（比面板亮的 #4E5A70 —— AutoCAD 属性值输入井；gp_dark.tres 同步使用）
# Input-well background — LIGHTER than the panel (#4E5A70, AutoCAD property wells);
# kept in sync with gp_dark.tres.
const GP_INPUT_BG: Color = Color(0.306, 0.353, 0.439)

# 分隔条底色（三栏 HSplitContainer 的 dragger）
# Splitter base colour (HSplitContainer dragger between the three panes).
const GP_SPLIT: Color = Color(0.224, 0.267, 0.329)

# 分隔条悬停 / 拖拽手柄（略亮）
# Splitter hover / grab handle — slightly brighter.
const GP_SPLIT_HI: Color = Color(0.306, 0.353, 0.439)

# 强调色（选中 tab 底边、激活态描边；AutoCAD 蓝）
# Accent colour (selected-tab underline, active-state outline; AutoCAD blue).
const GP_ACCENT: Color = Color(0.298, 0.518, 0.769)


# 边界位掩码 / Border bit flags.
const SIDE_LEFT: int = 1
const SIDE_RIGHT: int = 2
const SIDE_TOP: int = 4
const SIDE_BOTTOM: int = 8


# 生成带指定边 1px 边界线 + 纯背景的 StyleBoxFlat。用于 Panel / TabContainer 等
# 能绘制 "panel" 槽的控件。
# Build a StyleBoxFlat with the given sides drawn as a 1px border plus a flat
# background. For controls that paint a "panel" slot (Panel, TabContainer, ...).
static func gpStyleFor(gpBg: Color, gpSides: int = 0) -> StyleBoxFlat:
	var gpSb: StyleBoxFlat = StyleBoxFlat.new()
	gpSb.bg_color = gpBg
	gpSb.border_color = GP_BORDER
	gpSb.border_width_left = 1 if (gpSides & SIDE_LEFT) != 0 else 0
	gpSb.border_width_right = 1 if (gpSides & SIDE_RIGHT) != 0 else 0
	gpSb.border_width_top = 1 if (gpSides & SIDE_TOP) != 0 else 0
	gpSb.border_width_bottom = 1 if (gpSides & SIDE_BOTTOM) != 0 else 0
	return gpSb


# 在控件的 _draw() 内调用：画纯背景矩形 + 指定边 1px 边界线（含 0.5px 偏移使线锐利）。
# 用于无 "panel" 槽的 Container（HBox/VBox），自绘背景与边框，底层透出子控件前景。
# Call inside a Control's _draw(): paints a flat background rect plus 1px borders on
# the requested sides (0.5px offset for crisp lines). For Containers with no "panel"
# slot; the background sits beneath child controls.
static func gpDraw(gpC: Control, gpBg: Color, gpSides: int = 0) -> void:
	var gpSize: Vector2 = gpC.size
	gpC.draw_rect(Rect2(Vector2.ZERO, gpSize), gpBg)
	var gpCol: Color = GP_BORDER
	if (gpSides & SIDE_LEFT) != 0:
		gpC.draw_line(Vector2(0.5, 0.0), Vector2(0.5, gpSize.y), gpCol, 1.0)
	if (gpSides & SIDE_RIGHT) != 0:
		gpC.draw_line(Vector2(gpSize.x - 0.5, 0.0), Vector2(gpSize.x - 0.5, gpSize.y), gpCol, 1.0)
	if (gpSides & SIDE_TOP) != 0:
		gpC.draw_line(Vector2(0.0, 0.5), Vector2(gpSize.x, 0.5), gpCol, 1.0)
	if (gpSides & SIDE_BOTTOM) != 0:
		gpC.draw_line(Vector2(0.0, gpSize.y - 0.5), Vector2(gpSize.x, gpSize.y - 0.5), gpCol, 1.0)
