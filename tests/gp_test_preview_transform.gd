extends "res://tests/gp_test.gd"
# Headless tests for GPPreviewTransform (P1 extraction from GPMakeSymbolDialog).
# GPPreviewTransform（自 GPMakeSymbolDialog 抽取，P1）的 headless 测试。

const GP_EPS: float = 1e-3

# A 260x200 preview with the canonical 100x100 unit box: the view rect is inset by 4px on
# every side, so it is 252x192 and its centre is (130, 100).
# 260x200 预览配规范 100x100 单位框：视图矩形四周内缩 4px，故为 252x192，中心 (130,100)。
func _gpMake(gpBox: Rect2) -> GPPreviewTransform:
	var t: GPPreviewTransform = GPPreviewTransform.new()
	t.gpViewSize = Vector2(260.0, 200.0)
	t.gpBox = gpBox
	return t


func gpTestViewRectInset() -> void:
	var t: GPPreviewTransform = _gpMake(Rect2(0.0, 0.0, 100.0, 100.0))
	var r: Rect2 = t.gpViewRect()
	gpApprox(r.position.x, 4.0, GP_EPS, "view inset x")
	gpApprox(r.size.x, 252.0, GP_EPS, "view width after inset")
	gpApprox(r.get_center().x, 130.0, GP_EPS, "view centre x")
	gpApprox(r.get_center().y, 100.0, GP_EPS, "view centre y")

# Uniform fit: the scale is the MIN of both axis ratios, so a wide box is not stretched.
# 均匀适配：缩放取两轴比例的较小者，故宽框不会被拉伸。
func gpTestUniformScale() -> void:
	var t: GPPreviewTransform = _gpMake(Rect2(0.0, 0.0, 100.0, 100.0))
	gpApprox(t.gpScale(), 1.92, GP_EPS, "square box scales by the limiting axis (192/100)")
	var wide: GPPreviewTransform = _gpMake(Rect2(0.0, 0.0, 200.0, 100.0))
	gpApprox(wide.gpScale(), 1.26, GP_EPS, "wide box limited by width (252/200)")

# Box centre must land exactly on the view centre — that is the "centring" half of the fit.
# 包围盒中心必须精确落在视图中心 —— 这是适配中「居中」的一半。
func gpTestBoxCenterMapsToViewCenter() -> void:
	var t: GPPreviewTransform = _gpMake(Rect2(10.0, 20.0, 60.0, 40.0))
	var local: Vector2 = t.gpAuthorToLocal(t.gpBox.get_center())
	var centre: Vector2 = t.gpViewRect().get_center()
	gpCheck(local.distance_to(centre) < GP_EPS, "box centre maps to view centre")

# The round trip is the invariant that actually matters: a click mapped to author space and
# back must land on the same pixel, otherwise the glyph and the hit test disagree.
# 真正要紧的不变式是往返：点击映射到作者空间再回来必须落在同一像素，否则字形与命中测试会分歧。
func gpTestLocalAuthorRoundTrip() -> void:
	var t: GPPreviewTransform = _gpMake(Rect2(10.0, 20.0, 60.0, 40.0))
	for p in [Vector2(4.0, 4.0), Vector2(130.0, 100.0), Vector2(255.0, 195.0), Vector2(17.0, 188.0)]:
		var back: Vector2 = t.gpAuthorToLocal(t.gpLocalToAuthor(p))
		gpCheck(back.distance_to(p) < GP_EPS, "local->author->local round trip at %s" % str(p))

func gpTestAuthorLocalRoundTrip() -> void:
	var t: GPPreviewTransform = _gpMake(Rect2(10.0, 20.0, 60.0, 40.0))
	for a in [Vector2(10.0, 20.0), Vector2(40.0, 40.0), Vector2(70.0, 60.0)]:
		var back: Vector2 = t.gpLocalToAuthor(t.gpAuthorToLocal(a))
		gpCheck(back.distance_to(a) < GP_EPS, "author->local->author round trip at %s" % str(a))

func gpTestPortNormRoundTrip() -> void:
	var t: GPPreviewTransform = _gpMake(Rect2(0.0, 0.0, 100.0, 100.0))
	for n in [Vector2(0.0, 0.0), Vector2(0.5, 0.5), Vector2(1.0, 1.0), Vector2(0.25, 0.75)]:
		var back: Vector2 = t.gpLocalToNorm(t.gpPortLocal(n))
		gpCheck(back.distance_to(n) < GP_EPS, "port norm->local->norm round trip at %s" % str(n))

# Ports use the FULL view rect as their envelope (not the fitted glyph box), and an out-of-range
# pixel must clamp into 0..1 rather than escaping the envelope.
# 端口以整幅视图矩形为包络（而非适配后的字形框），且越界像素必须夹取到 0..1 而非溢出包络。
func gpTestNormClamps() -> void:
	var t: GPPreviewTransform = _gpMake(Rect2(0.0, 0.0, 100.0, 100.0))
	var low: Vector2 = t.gpLocalToNorm(Vector2(-500.0, -500.0))
	gpApprox(low.x, 0.0, GP_EPS, "below-range clamps to 0")
	gpApprox(low.y, 0.0, GP_EPS, "below-range clamps to 0 (y)")
	var high: Vector2 = t.gpLocalToNorm(Vector2(9999.0, 9999.0))
	gpApprox(high.x, 1.0, GP_EPS, "above-range clamps to 1")
	gpApprox(high.y, 1.0, GP_EPS, "above-range clamps to 1 (y)")

# No geometry yet -> the canonical 100x100 unit box, so clicks still map instead of dividing by
# a zero-sized box.
# 尚无几何时回退为规范 100x100 单位框，使点击仍可映射，而非除以零尺寸包围盒。
func gpTestEmptyShapesFallback() -> void:
	var box: Rect2 = GPPreviewTransform.gpBoxOf([])
	gpApprox(box.size.x, GPPreviewTransform.GP_UNIT_BOX, GP_EPS, "empty shape list falls back to unit box")
	var t: GPPreviewTransform = GPPreviewTransform.gpForShapes([], Vector2(260.0, 200.0))
	gpCheck(is_finite(t.gpScale()) and t.gpScale() > 0.0, "scale stays finite for an empty glyph")

# A zero-sized preview would previously give inf/nan and silently break every hit test.
# 零尺寸预览此前会给出 inf/nan 并静默破坏全部命中测试。
func gpTestDegenerateViewIsGuarded() -> void:
	var t: GPPreviewTransform = GPPreviewTransform.new()
	t.gpViewSize = Vector2.ZERO
	t.gpBox = Rect2(0.0, 0.0, 100.0, 100.0)
	gpApprox(t.gpScale(), 1.0, GP_EPS, "zero-sized preview falls back to scale 1")
