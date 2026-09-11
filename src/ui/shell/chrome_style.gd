class_name GPChromeStyle
extends RefCounted

# 视觉分层色板（精致深色梯度）。
# Visual layering palette (refined dark gradient).
#
# 设计原则 / Design intent:
#   - 中心画布最亮（工作区聚焦），向外逐层变暗：画布 > Ribbon > 侧栏 > 菜单/状态栏。
#     The canvas is brightest (working-area focus), darkening outward:
#     canvas > ribbon > dock > menu/status chrome.
#   - 边界线比所有背景亮一档，形成清晰但不刺眼的 1px 分隔，解决五区块"连成一片"。
#     Border lines sit one tier brighter than any background, giving a crisp 1px
#     divider without harshness — fixes the "blocks merge into one" problem.
#   - 颜色均为数据自包含常量，便于统一微调（改这里即改全界面）。
#     Colours are self-contained constants so a single edit restyles the whole UI.
# 编码规范：所有变量均显式声明类型。

# 菜单栏 / 状态栏（最暗一档 chrome）
# Menu bar / status bar — darkest chrome tier.
const GP_CHROME_BG: Color = Color(0.082, 0.090, 0.118)

# Ribbon 命令区（略亮于 chrome，作为命令强调）
# Ribbon command bar — a touch brighter than chrome to emphasise commands.
const GP_RIBBON_BG: Color = Color(0.106, 0.118, 0.149)

# 左右侧栏（图元库 / 属性区，中阶）
# Left / right docks (symbol library / inspector) — mid tier.
const GP_DOCK_BG: Color = Color(0.094, 0.106, 0.133)

# 中心画布工作区（最亮，聚焦）
# Center canvas working area — brightest, focal.
const GP_CANVAS_BG: Color = Color(0.129, 0.141, 0.180)

# 1px 区块边界线（低对比发丝线：介于 dock 与 canvas 之间，清晰但不刺眼）
# 1px block border — a low-contrast hairline sitting between dock and canvas:
# crisp yet never harsh, so every divider reads delicate rather than heavy.
const GP_BORDER: Color = Color(0.150, 0.165, 0.202)

# 分隔条底色（三栏 HSplitContainer 的 dragger）
# Splitter base colour (HSplitContainer dragger between the three panes).
const GP_SPLIT: Color = Color(0.137, 0.149, 0.184)

# 分隔条悬停 / 拖拽手柄（略亮）
# Splitter hover / grab handle — slightly brighter.
const GP_SPLIT_HI: Color = Color(0.192, 0.220, 0.271)

# 强调色（选中 tab 底边、激活态描边）
# Accent colour (selected-tab underline, active-state outline).
const GP_ACCENT: Color = Color(0.290, 0.560, 0.860)


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
