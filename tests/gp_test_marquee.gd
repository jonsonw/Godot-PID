extends "res://tests/gp_test.gd"
# Headless tests for GPCanvasMarquee (P1 extraction from GPCanvas2D).
# GPCanvasMarquee（自 GPCanvas2D 抽取，P1）的 headless 测试。

const GP_EPS: float = 1e-6


func gpTestBeginAndRect() -> void:
	var m: GPCanvasMarquee = GPCanvasMarquee.new()
	gpCheck(not m.gpActive, "inactive before begin")
	m.gpBegin(Vector2(100.0, 100.0), false)
	gpCheck(m.gpActive, "active after begin")
	gpEq(m.gpAdditive, false, "additive flag defaults to false")
	m.gpUpdate(Vector2(200.0, 160.0))
	var r: Rect2 = m.gpScreenRect()
	gpApprox(r.position.x, 100.0, GP_EPS, "rect x is the min corner")
	gpApprox(r.size.x, 100.0, GP_EPS, "rect width is absolute")

# Dragging right-to-left normalizes the same way: Rect2 must never carry a negative size.
# 右→左拖动同样归一化：Rect2 绝不能带负尺寸。
func gpTestRectNormalizesReversedDrag() -> void:
	var m: GPCanvasMarquee = GPCanvasMarquee.new()
	m.gpBegin(Vector2(200.0, 160.0), false)
	m.gpUpdate(Vector2(100.0, 100.0))
	var r: Rect2 = m.gpScreenRect()
	gpApprox(r.position.x, 100.0, GP_EPS, "reversed drag normalizes x")
	gpApprox(r.size.x, 100.0, GP_EPS, "reversed drag keeps a positive width")
	gpCheck(r.size.x >= 0.0 and r.size.y >= 0.0, "size never negative")

# The CAD rule: left->right encloses, right->left crosses. Both the band colour and the commit
# hit test read this one predicate, so they can never disagree.
# CAD 规则：左→右为包含，右→左为交叉。选框颜色与提交命中测试都读这一个判据，故永不会分歧。
func gpTestWindowVersusCrossing() -> void:
	var m: GPCanvasMarquee = GPCanvasMarquee.new()
	m.gpBegin(Vector2(100.0, 100.0), false)
	m.gpUpdate(Vector2(200.0, 160.0))
	gpCheck(m.gpIsWindow(), "left->right is a window (enclosing) band")
	gpEq(m.gpColor(), GPCanvasMarquee.GP_COLOR_WINDOW, "window band is blue")
	m.gpUpdate(Vector2(50.0, 160.0))
	gpCheck(not m.gpIsWindow(), "right->left is a crossing (touching) band")
	gpEq(m.gpColor(), GPCanvasMarquee.GP_COLOR_CROSSING, "crossing band is green")

func gpTestPicksRule() -> void:
	var band: Rect2 = Rect2(0.0, 0.0, 100.0, 100.0)
	var inside: Rect2 = Rect2(10.0, 10.0, 20.0, 20.0)
	var straddling: Rect2 = Rect2(90.0, 90.0, 40.0, 40.0)
	gpCheck(GPCanvasMarquee.gpPicks(true, band, inside), "window picks a fully enclosed box")
	gpCheck(not GPCanvasMarquee.gpPicks(true, band, straddling), "window rejects a straddling box")
	gpCheck(GPCanvasMarquee.gpPicks(false, band, straddling), "crossing picks a straddling box")
	gpCheck(GPCanvasMarquee.gpPicks(false, band, inside), "crossing also picks an enclosed box")

# A press/release without movement is a plain click, not a marquee — gpFinish() must say so.
# 未产生位移的按下/释放只是普通单击而非框选 —— gpFinish() 必须如实报告。
func gpTestFinishReportsRealDrag() -> void:
	var m: GPCanvasMarquee = GPCanvasMarquee.new()
	m.gpBegin(Vector2(100.0, 100.0), false)
	gpCheck(not m.gpMovedEnough(), "no movement yet")
	gpCheck(not m.gpFinish(), "a click-sized band is not a marquee")
	gpCheck(not m.gpActive, "finishing deactivates the band")

	m.gpBegin(Vector2(100.0, 100.0), true)
	m.gpUpdate(Vector2(100.0, 100.0 + GPCanvasMarquee.GP_MIN_DRAG + 1.0))
	gpCheck(m.gpMovedEnough(), "movement past the threshold counts")
	gpCheck(m.gpFinish(), "a dragged band is a real marquee")

func gpTestCancel() -> void:
	var m: GPCanvasMarquee = GPCanvasMarquee.new()
	m.gpBegin(Vector2(100.0, 100.0), false)
	m.gpUpdate(Vector2(300.0, 300.0))
	m.gpCancel()
	gpCheck(not m.gpActive, "cancel deactivates the band")
	gpCheck(not m.gpFinish(), "a cancelled band does not commit")

func gpTestAdditiveFlag() -> void:
	var m: GPCanvasMarquee = GPCanvasMarquee.new()
	m.gpBegin(Vector2(0.0, 0.0), true)
	gpEq(m.gpAdditive, true, "shift start marks the band additive")
	m.gpBegin(Vector2(0.0, 0.0), false)
	gpEq(m.gpAdditive, false, "a new band resets the additive flag")
