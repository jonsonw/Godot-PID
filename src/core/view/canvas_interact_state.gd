class_name GPCanvasInteractState
extends RefCounted

## The canvas's shared interaction state: mode, pending symbol, camera, selection, marquee and
## the id counter — one object, no Control dependency.
## 画布的共享交互状态：模式、待放置图元、相机、选择集、框选与 id 计数器——一个对象，无 Control 依赖。
##
## Why it exists / 为何存在：
## these six things were separate fields on GPCanvas2D. That is fine for one canvas, but P2
## introduces a tool pattern where every tool receives "the state it acts on" as a single
## argument. Passing six loose fields would either leak the Control into the tools or force a
## throwaway struct per call. This object is that argument — and because it is a RefCounted
## with no UI dependency, a tool can be driven headlessly with a fake state.
## 这六项原是 GPCanvas2D 上的独立字段。对单个画布尚可，但 P2 要引入工具模式：每个工具都以
## 「其所作用的状态」作为唯一入参。传六个松散字段要么把 Control 泄漏进工具，要么每次调用现造一个
## 临时结构。本对象即那个入参——且因它是无 UI 依赖的 RefCounted，工具可用假状态在 headless 下驱动。
##
## Layering / 分层：
## this is a COMPOSITION root for the canvas's state, not a new behaviour layer: every member
## keeps owning its own invariants (camera math, selection mutual exclusion, marquee rule,
## id hygiene). What this class adds is only the cross-member rules (e.g. entering a drawing
## mode clears the node selection) and a single reset point.
## 本类是画布状态的「组合根」，而非新的行为层：每个成员仍各自持有其不变式（相机数学、选择互斥、
## 框选规则、id 规整）。本类仅新增跨成员规则（如进入绘图模式清空节点选择）与统一重置点。

# ---- interaction modes ----
# ---- 交互模式 ----
# Drawing modes are appended last so the legacy SELECT/CONNECT values (0/1) stay unchanged.
# 绘图模式置于末尾，使旧的选择/连线取值（0/1）保持不变。
enum GPMode { GP_SELECT, GP_CONNECT, GP_DRAW_LINE, GP_DRAW_CIRCLE, GP_DRAW_RECT, GP_DRAW_POLYLINE, GP_DRAW_ARC }

# Lowest mode value that is a drawing tool (used for the "entering a draw tool" rule).
# 属于绘图工具的最小模式值（用于「进入绘图工具」规则）。
const GP_FIRST_DRAW_MODE: int = GPMode.GP_DRAW_LINE

# Highest mode value that is a drawing tool (GP_DRAW_ARC terminates the drawing range).
# 属于绘图工具的最大模式值（GP_DRAW_ARC 终止绘图区间）。
const GP_LAST_DRAW_MODE: int = GPMode.GP_DRAW_ARC


# ---- composed state modules ----
# ---- 组合进来的状态模块 ----
# Pan/zoom camera (owns offset + zoom and the world<->screen math).
# 平移 / 缩放相机（拥有 offset + zoom 及世界 <-> 屏幕数学）。
var gpCam: GPCanvasCamera

# Node / annotation-shape selection (owns the mutual-exclusion invariants).
# 节点 / 注释图形选择（持有互斥不变式）。
var gpSel: GPCanvasSelection

# Rubber-band marquee (owns the window/crossing rule).
# 橡皮筋框选（持有窗口 / 交叉规则）。
var gpMarquee: GPCanvasMarquee

# Monotonic id counter for new nodes and edges.
# 新节点与新边的单调递增 id 计数器。
var gpIds: GPIdGen

# Current interaction mode.
# 当前交互模式。
var gpMode: int = GPMode.GP_SELECT

# Symbol definition waiting to be placed by the next left click.
# 等待下一次左键放置的图元定义。
var gpPendingDef: GPSymbolDef = null


func _init() -> void:
	gpCam = GPCanvasCamera.new()
	gpSel = GPCanvasSelection.new()
	gpMarquee = GPCanvasMarquee.new()
	gpIds = GPIdGen.new()


# ---- mode ----
# ---- 模式 ----
# Switch mode. Returns true when it actually changed (so the caller can skip a redraw).
# Entering a drawing tool clears the node selection so a left click draws instead of
# re-selecting a symbol; the shape selection is left intact for marquee-style editing.
# 切换模式。返回是否实际变化（供调用方跳过重绘）。进入绘图工具时清空节点选择，
# 使左键变为绘制而非再次选中图元；图形选择保留以便框选式编辑。
func gpSetMode(gpM: int) -> bool:
	if gpM == gpMode:
		return false
	gpMode = gpM
	if gpM >= GP_FIRST_DRAW_MODE:
		gpSel.gpSetNodes([])
	return true


# Is the current mode one of the annotation-drawing tools?
# 当前模式是否为注释绘图工具之一？
func gpIsDrawMode() -> bool:
	return gpMode >= GP_FIRST_DRAW_MODE and gpMode <= GP_LAST_DRAW_MODE


# ---- reset ----
# ---- 重置 ----
# Clear everything that must not survive a New / Open: the id counter, both selections, the
# pending symbol and any in-flight marquee. The MODE is deliberately left alone — File > New
# never changed it historically, and silently forcing SELECT would surprise the user.
# 清空一切不应在「新建 / 打开」后存续的东西：id 计数器、两个选择集、待放置图元与进行中的框选。
# 模式刻意保持不变——「文件 > 新建」历史上从不改它，静默强制为 SELECT 会让用户意外。
func gpReset() -> void:
	gpIds.gpReset()
	gpSel.gpClearAll()
	gpMarquee.gpCancel()
	gpPendingDef = null


# Convenience for the canvas proxy: the raw id counter.
# 供画布代理使用的便捷访问：原始 id 计数器。
func gpNextIdValue() -> int:
	return gpIds.gpCounter


func gpSetNextIdValue(gpV: int) -> void:
	gpIds.gpCounter = gpV
