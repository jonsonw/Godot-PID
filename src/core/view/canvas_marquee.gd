class_name GPCanvasMarquee
extends RefCounted

## Rubber-band marquee selection state and its CAD window/crossing rule.
## 橡皮筋框选状态及其 CAD 窗口 / 交叉规则。
##
## Why it exists / 为何存在：
## the marquee used to be four loose fields on GPCanvas2D (_gpMarqueeing/_gpMarqueeFrom/
## _gpMarqueeTo/_gpMarqueeAdd) with its window-vs-crossing rule written out twice — once in
## _gpDrawMarquee (to pick a colour) and once in _gpCommitMarquee (to pick a hit rule). Two
## copies of one rule is exactly how "dragging right selects differently than it looks" bugs
## are born. Both now call gpIsWindow().
## 框选原是 GPCanvas2D 上四个松散字段（_gpMarqueeing/_gpMarqueeFrom/_gpMarqueeTo/_gpMarqueeAdd），
## 其「窗口 vs 交叉」规则被写了两遍——一次在 _gpDrawMarquee（选颜色），一次在 _gpCommitMarquee（选命中规则）。
## 同一规则两份实现，正是「向右拖动的实际选中与观感不符」这类缺陷的温床。现二者都调用 gpIsWindow()。
##
## CAD convention / CAD 惯例：
##   drag left -> right : WINDOW   — only fully enclosed shapes are picked (blue)
##   drag right -> left : CROSSING — anything the band touches is picked (green)
##   左→右拖动：窗口模式 —— 仅选中被完全包含的图形（蓝色）
##   右→左拖动：交叉模式 —— 选框碰到即选中（绿色）

# Minimum drag distance (px) before a press is treated as a marquee rather than a click.
# 按下被视为框选（而非单击）前的最小拖动距离（像素）。
const GP_MIN_DRAG: float = 4.0

# Window (enclosing) band colour — blue, per CAD convention.
# 窗口（包含）选框颜色 —— 按 CAD 惯例为蓝色。
const GP_COLOR_WINDOW: Color = Color(0.30, 0.65, 1.0)

# Crossing (touching) band colour — green, per CAD convention.
# 交叉（触碰）选框颜色 —— 按 CAD 惯例为绿色。
const GP_COLOR_CROSSING: Color = Color(0.30, 1.0, 0.50)


# Is a band currently being dragged?
# 当前是否正在拖动选框？
var gpActive: bool = false

# Band anchor, SCREEN space (drawn directly; converted to world only on commit).
# 选框起点，屏幕空间（直接绘制；仅在提交时换算到世界空间）。
var gpFrom: Vector2 = Vector2.ZERO

# Live band corner, SCREEN space.
# 选框实时对角点，屏幕空间。
var gpTo: Vector2 = Vector2.ZERO

# Whether the finished band ADDS to the current selection (Shift was held).
# 完成的选框是否为「追加到当前选择集」（曾按住 Shift）。
var gpAdditive: bool = false


# Start a band at gpAt. gpAdd marks an additive (Shift) selection.
# 在 gpAt 处开始选框。gpAdd 表示追加式（Shift）选择。
func gpBegin(gpAt: Vector2, gpAdd: bool = false) -> void:
	gpActive = true
	gpFrom = gpAt
	gpTo = gpAt
	gpAdditive = gpAdd


# Move the live corner to gpAt.
# 把实时对角点移动到 gpAt。
func gpUpdate(gpAt: Vector2) -> void:
	gpTo = gpAt


# End the band. Returns true when it had actually been dragged far enough to be a marquee
# (so the caller can decide between "commit selection" and "treat as a plain click").
# 结束选框。若确实拖动到足以构成框选则返回 true（供调用方在「提交选择」与「按普通单击处理」间抉择）。
func gpFinish() -> bool:
	var gpWasReal: bool = gpActive and gpMovedEnough()
	gpActive = false
	return gpWasReal


# Abandon the band without committing anything.
# 放弃选框，不提交任何内容。
func gpCancel() -> void:
	gpActive = false


# Has the band moved at least GP_MIN_DRAG from its anchor?
# 选框是否已离起点移动至少 GP_MIN_DRAG？
func gpMovedEnough() -> bool:
	return gpTo.distance_to(gpFrom) > GP_MIN_DRAG


# The band as a normalized Rect2 in SCREEN space (position = top-left, size >= 0).
# 屏幕空间下的选框 Rect2（position 为左上角，size 非负）。
func gpScreenRect() -> Rect2:
	var gpA: Vector2 = gpFrom.min(gpTo)
	var gpB: Vector2 = gpFrom.max(gpTo)
	return Rect2(gpA, gpB - gpA)


# True for a WINDOW (enclosing) band, false for CROSSING (touching).
# The test is on SCREEN x; because the camera applies a uniform positive zoom, the screen
# ordering and the world ordering of the two corners always agree.
# 窗口（包含）选框为 true，交叉（触碰）选框为 false。
# 判据取自屏幕 x；由于相机施加的是均匀正缩放，两角的屏幕序与世界序恒一致。
func gpIsWindow() -> bool:
	return gpTo.x >= gpFrom.x


# Band colour for the current direction (blue window / green crossing).
# 当前方向对应的选框颜色（窗口蓝 / 交叉绿）。
func gpColor() -> Color:
	return GP_COLOR_WINDOW if gpIsWindow() else GP_COLOR_CROSSING


# Does gpTarget satisfy the band rule? gpWindow = true requires full enclosure, false accepts
# any intersection. Shared by node envelopes and annotation-shape bboxes so both layers apply
# one identical rule.
# gpTarget 是否满足选框规则？gpWindow 为 true 要求完全包含，为 false 则相交即算。
# 节点包络与注释图形包围盒共用此函数，使两层应用完全一致的规则。
static func gpPicks(gpWindow: bool, gpBand: Rect2, gpTarget: Rect2) -> bool:
	return gpBand.encloses(gpTarget) if gpWindow else gpBand.intersects(gpTarget)
