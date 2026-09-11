class_name GPSplitChrome
extends HSplitContainer

# 三栏分隔条的悬停检测层。
# Hover-detection layer for the three-pane splitter.
#
# 引擎自身的 grabber 已由 _gpStyleChrome 设为透明（视觉交给 GPOverlayChrome），
# 此处只负责"鼠标是否落在某条接缝的抓取带上"，并把悬停态暴露给叠加层绘制高亮。
# The engine grabber is made transparent by _gpStyleChrome (GPOverlayChrome owns the
# visuals); this script only detects whether the pointer is over a seam's grab band and
# exposes the hover state so the overlay can paint the "draggable" highlight.
#
# 关键：悬停检测走 gui_input 信号而非覆写 _gui_input 虚方法，否则会遮蔽
# SplitContainer 自带的拖拽处理。
# Key: hover detection uses the gui_input SIGNAL (not an override of the _gui_input
# virtual), otherwise SplitContainer's own drag handling would be shadowed.
# 编码规范：所有变量均显式声明类型。

# 当前悬停的接缝索引（-1 = 无，0 = 左缝，1 = 右缝）。
# Currently hovered seam index (-1 = none, 0 = left seam, 1 = right seam).
var gpHoverSeam: int = -1

# 顶层叠加层引用（由 GPOverlayChrome.gpRegisterSplit 注入）。
# Reference to the top overlay (injected by GPOverlayChrome.gpRegisterSplit).
var gpOverlay: Control = null


# 叠加层在 _ready 时回调，建立反向引用。
# The overlay calls this in _ready to set up the back-reference.
func gpRegisterOverlay(gpO: Control) -> void:
	gpOverlay = gpO


func _ready() -> void:
	gui_input.connect(_gpOnInput)
	mouse_exited.connect(_gpOnExit)
	resized.connect(_gpRedrawOverlay)
	dragged.connect(func(_gpOffset: int) -> void: _gpRedrawOverlay())


# 鼠标在分隔条抓取带上移动：更新悬停接缝。
# Mouse moving over a grab band: update the hovered seam.
func _gpOnInput(gpEvent: InputEvent) -> void:
	if not (gpEvent is InputEventMouseMotion):
		return
	var gpMx: float = gpEvent.position.x
	var gpSeams: PackedFloat32Array = gpSeamXsLocal()
	var gpHit: int = -1
	for gpI in range(gpSeams.size()):
		if abs(gpMx - gpSeams[gpI]) <= _gpGrabHalf():
			gpHit = gpI
	if gpHit != gpHoverSeam:
		gpHoverSeam = gpHit
		_gpRedrawOverlay()


func _gpOnExit() -> void:
	if gpHoverSeam != -1:
		gpHoverSeam = -1
		_gpRedrawOverlay()


func _gpRedrawOverlay() -> void:
	if gpOverlay != null and is_instance_valid(gpOverlay):
		gpOverlay.queue_redraw()


# 抓取带半宽（与引擎默认 grabber_size=6 的一半对齐）。
# Grab-band half-width (matches the engine default grabber_size = 6).
func _gpGrabHalf() -> float:
	return 3.0


# 各接缝的「分隔条局部 x」（抓取带中心，位于相邻面板之间）。
# Each seam's local-x within the splitter (grab-band centre, between adjacent panes).
func gpSeamXsLocal() -> PackedFloat32Array:
	var gpOut: PackedFloat32Array = []
	var gpKids: Array = get_children()
	var gpOrigin: float = get_global_rect().position.x
	for gpI in range(gpKids.size() - 1):
		var gpA: Control = gpKids[gpI] as Control
		var gpB: Control = gpKids[gpI + 1] as Control
		if gpA == null or gpB == null:
			continue
		var gpAx: float = gpA.get_global_rect().end.x
		var gpBx: float = gpB.get_global_rect().position.x
		gpOut.append((gpAx + gpBx) * 0.5 - gpOrigin)
	return gpOut
