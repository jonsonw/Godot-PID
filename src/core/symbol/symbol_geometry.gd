class_name GPSymbolGeometry
extends RefCounted
# Copyright © 2026 Jonson Wang
# Pure symbol-glyph geometry shared by the screen painter (render), the print model (core), DXF
# and PDF. It lives in CORE so a core consumer no longer reaches up into render just to measure a
# glyph; ADR-10's dependency direction stays one-way.
# 屏幕绘制（render）、打印模型（core）、DXF 与 PDF 共用的纯图元几何。放在 CORE 后，core 消费者
# 不必为了量一个字形向上依赖 render，ADR-10 的单向依赖得以保持。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Read the glyph's unit-space bounding box out of a shape dictionary.
# 从形状字典中读取字形的单位空间包围盒。
# Falls back to the full 100x100 unit box when the shape carries no "box" entry.
# 当形状未携带 "box" 时，回退为完整的 100x100 单位框。
static func gpUnitBox(gpShape: Dictionary) -> Rect2:
	if gpShape.has("box"):
		var gpB: Array = gpShape["box"]
		if gpB.size() >= 4:
			var gpW: float = maxf(float(gpB[2]), 0.001)
			var gpH: float = maxf(float(gpB[3]), 0.001)
			return Rect2(Vector2(float(gpB[0]), float(gpB[1])), Vector2(gpW, gpH))
	return Rect2(Vector2.ZERO, Vector2(100.0, 100.0))


# Uniform scale factor that fits a unit-space box into a target size without distortion.
# 将单位空间包围盒无变形地塞入目标尺寸的均匀缩放系数。
static func gpFitScale(gpBox: Rect2, gpTarget: Vector2) -> float:
	var gpBw: float = maxf(gpBox.size.x, 0.001)
	var gpBh: float = maxf(gpBox.size.y, 0.001)
	return minf(gpTarget.x / gpBw, gpTarget.y / gpBh)


