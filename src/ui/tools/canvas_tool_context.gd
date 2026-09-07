# ============================================================================
# GPCanvasToolContext — 工具共享上下文（P2 拆分）
# Canvas tool shared context (P2 split).
#
# 由画布在 _ready() 中构造并注入每个工具。集中暴露「状态持有者（GPCanvas2D）」与「跨工具共享
# 交互状态（GPCanvasInteractState）」，工具经它读写，避免直接耦合画布内部结构。
# Built by the canvas in _ready() and injected into every tool. Centralizes the state owner
# (GPCanvas2D) and the shared cross-tool interaction state (GPCanvasInteractState); tools read/write
# through it instead of coupling to canvas internals directly.
# ============================================================================

class_name GPCanvasToolContext
extends RefCounted

# The canvas that owns all interaction state. Tools read/write live state through it.
# 持有全部交互状态的画布。工具经它读写实时状态。
var gpCv: GPCanvas2D

# Shared cross-tool interaction state (mode / selection / camera / pending / id counter).
# 跨工具共享的交互状态（模式 / 选择集 / 相机 / 待放置 / id 计数器）。
var gpState: GPCanvasInteractState

# Annotation-shape editing collaborator (M3). Read lazily from the canvas: the context is built
# during _ready(), so a snapshot taken in _init() would silently freeze if the delegate were ever
# created afterwards. Reaching the collaborator through the context keeps tools off gpCv.* internals.
# 注释图形编辑协作者（M3）。惰性取自画布：上下文在 _ready() 中构造，若委托将来改为之后创建，
# 在 _init() 里取快照会静默冻结。经上下文取协作者可让工具远离 gpCv.* 内部实现。
var gpAnno: GPAnnotationEditor:
	get: return gpCv.gpAnno

func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas
	gpState = gpCanvas.gpState
