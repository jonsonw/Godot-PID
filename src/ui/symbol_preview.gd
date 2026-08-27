class_name GPSymbolPreview
extends Control

# Copyright © 2026 Jonson Wang
# Live preview of a normalized GPSymbolDef, exactly as the canvas will render it.
# 归一化后的 GPSymbolDef 实时预览，与画布最终渲染保持一致。
# Shows the symbol at 1:1 nominal size and at 2x, plus the envelope outline and the ports, so
# the author can verify "same family, same size" and "ports on the envelope edge" before export.
# 以 1:1 标称尺寸与 2 倍尺寸展示图元，并叠加包络轮廓与端口，使作者在导出前即可确认
# 「同族等大」与「端口贴合包络边」。
# It reuses GPSymbolPainter, so what you see here is what the canvas draws.
# 它复用 GPSymbolPainter，因此此处所见即画布所绘。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Definition under preview (null renders an empty placeholder).
# 正在预览的定义（为 null 时渲染空占位）。
var gpDef: GPSymbolDef = null

# Optional reference definitions from the same category, drawn small underneath so the author
# can eyeball that the new symbol matches the family size.
# 同类别的可选参考定义，以小尺寸绘制在下方，便于作者目测新图元是否与同族等大。
var gpPeers: Array[GPSymbolDef] = []


# Bind the definition to preview and redraw.
# 绑定待预览的定义并重绘。
func gpSetDef(gpD: GPSymbolDef) -> void:
	gpDef = gpD
	queue_redraw()


# Bind the family reference definitions and redraw.
# 绑定同族参考定义并重绘。
func gpSetPeers(gpP: Array[GPSymbolDef]) -> void:
	gpPeers = gpP
	queue_redraw()


# Render the 1:1 and 2x previews plus the family strip.
# 绘制 1:1 与 2 倍预览以及同族对照条。
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.11, 0.13), true)
	if gpDef == null:
		return

	var gpEnvCol: Color = Color(0.45, 0.75, 1.0, 0.45)
	var gpFill: Color = GPSymbolPainter.gpCategoryColor(gpDef.gpCategory)
	var gpStroke: Color = gpFill.lightened(0.25)
	var gpPortCol: Color = Color(0.35, 1.0, 0.55)

	# --- 1:1 nominal size, upper area ---
	# --- 1:1 标称尺寸，上部区域 ---
	var gpSz1: Vector2 = gpDef.gpDefaultSize
	var gpCtr1: Vector2 = Vector2(size.x * 0.28, size.y * 0.32)
	_gpDrawOne(gpCtr1, gpSz1, 1.0, gpFill, gpStroke, gpEnvCol, gpPortCol)

	# --- 2x, to check crispness of the vector shape ---
	# --- 2 倍尺寸，用于检查矢量形状的清晰度 ---
	var gpCtr2: Vector2 = Vector2(size.x * 0.72, size.y * 0.32)
	_gpDrawOne(gpCtr2, gpSz1 * 2.0, 2.0, gpFill, gpStroke, gpEnvCol, gpPortCol)

	# --- family strip: peers at 1:1, so unequal sizes are immediately visible ---
	# --- 同族对照条：同族图元以 1:1 绘制，尺寸不一致会立刻显现 ---
	if gpPeers.is_empty():
		return
	var gpRowY: float = size.y * 0.78
	var gpX: float = 12.0
	for gpP in gpPeers:
		var gpPs: Vector2 = gpP.gpDefaultSize
		if gpX + gpPs.x + 8.0 > size.x:
			break
		var gpC: Vector2 = Vector2(gpX + gpPs.x * 0.5, gpRowY)
		var gpPf: Color = GPSymbolPainter.gpCategoryColor(gpP.gpCategory).darkened(0.15)
		_gpDrawPeer(gpP, gpC, gpPs, gpPf, gpPf.lightened(0.3))
		gpX += gpPs.x + 12.0


# Draw one preview instance: envelope outline, vector shape and ports.
# 绘制一个预览实例：包络轮廓、矢量形状与端口。
func _gpDrawOne(
	gpCtr: Vector2,
	gpSz: Vector2,
	gpScale: float,
	gpFill: Color,
	gpStroke: Color,
	gpEnvCol: Color,
	gpPortCol: Color
) -> void:
	var gpRect: Rect2 = Rect2(gpCtr - gpSz * 0.5, gpSz)
	draw_rect(gpRect, gpEnvCol, false, 1.0)
	if gpDef.gpShape.is_empty():
		draw_rect(gpRect, gpFill, true)
		draw_rect(gpRect, gpStroke, false, 2.0 * gpScale)
	else:
		GPSymbolPainter.gpDrawShape(self, gpDef.gpShape, gpRect, gpFill, gpStroke, 2.0 * gpScale)
	for gpP in gpDef.gpPorts:
		draw_circle(gpCtr + gpDef.gpPortLocal(gpP), 3.0 * gpScale, gpPortCol)


# Draw one family reference symbol (no envelope outline, dimmer colors).
# 绘制一个同族参考图元（不画包络轮廓，配色更暗）。
func _gpDrawPeer(gpP: GPSymbolDef, gpCtr: Vector2, gpSz: Vector2, gpFill: Color, gpStroke: Color) -> void:
	var gpRect: Rect2 = Rect2(gpCtr - gpSz * 0.5, gpSz)
	if gpP.gpShape.is_empty():
		draw_rect(gpRect, gpFill, true)
		draw_rect(gpRect, gpStroke, false, 1.0)
	else:
		GPSymbolPainter.gpDrawShape(self, gpP.gpShape, gpRect, gpFill, gpStroke, 1.5)
