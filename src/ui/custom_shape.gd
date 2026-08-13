class_name GPCustomShape
extends RefCounted

# Custom shape primitives: line / rect / circle / ellipse / arrow / polyline / text.
# Generates is_primitive=true PIDNode (annotation layer, excluded from equipment lists).
# 自定义图元基元：直线/矩形/圆/椭圆/箭头/折线/文字。
# 生成 is_primitive=true 的 PIDNode（标注层，不进设备清单）。
# See Dev Guide §4.4.1.
# 见开发指南 §4.4.1。

# Drawing mode changed
# 绘制模式变化
signal gpModeChanged(shape: String)
# A primitive was drawn
# 基元绘制完成
signal gpShapeDrawn(node)

# TODO: emit shape_drawn with an is_primitive PIDNode
# TODO：发出带 is_primitive 标记的 PIDNode
