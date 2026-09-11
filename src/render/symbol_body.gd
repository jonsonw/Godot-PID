class_name GPSymbolBody
extends Node2D
# Copyright © 2026 Jonson Wang
# The glyph-and-ports layer of a placed symbol. It exists to carry the instance's FLIP and
# ROTATION, which the parent GPSymbolView must NOT carry.
# 已放置图元的「字形 + 端口」层。它的存在是为了承载实例的翻转与旋转 —— 而父节点
# GPSymbolView 必须「不」承载这两个变换。
#
# Why a child node instead of setting rotation/scale on the view itself /
# 为何用子节点，而不是直接在视图节点上设置 rotation/scale：
#   the label is drawn by GPSymbolView._draw(). A node-level scale.x = -1 mirrors EVERYTHING
#   drawn on that node, including text — the tag would come out backwards. Text cannot opt out
#   of the node transform (draw_set_transform composes with it rather than replacing it), so the
#   only clean split is two nodes: this one carries flip + rotation for the glyph and the ports,
#   the parent stays upright for the label.
#   标签由 GPSymbolView._draw() 绘制。节点级 scale.x = -1 会镜像该节点上「所有」绘制内容，
#   包括文字 —— 位号会变成反字。文字无法摆脱节点变换（draw_set_transform 是与之复合而非替换），
#   故唯一干净的做法是拆成两个节点：本节点承载翻转 + 旋转用于字形与端口，父节点保持正向用于标签。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Owner view whose glyph and ports this body paints.
# 本主体所绘制其字形与端口的宿主视图。
var gpView: GPSymbolView = null


func _draw() -> void:
	if gpView != null:
		gpView.gpDrawBody(self)
