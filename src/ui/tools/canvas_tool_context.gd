# ============================================================================
# GPCanvasToolContext — 工具共享上下文
# Canvas tool shared context .
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

# during _ready(), so a snapshot taken in _init() would silently freeze if the delegate were ever
# created afterwards. Reaching the collaborator through the context keeps tools off gpCv.* internals.
# 在 _init() 里取快照会静默冻结。经上下文取协作者可让工具远离 gpCv.* 内部实现。
var gpAnno: GPAnnotationEditor:
	get: return gpCv.gpAnno

# Edge line-number editor collaborator . Lazily reached from the canvas, same as gpAnno.
# 边管线号编辑器协作者。与 gpAnno 一样惰性取自画布。
var gpEdgeEditor: GPEdgeTagEditor:
	get: return gpCv.gpEdgeEditor

# Node tag in-place editor collaborator (Rev.3 stage 1.5, R1). Lazily reached from the canvas,
# same as gpEdgeEditor. / 图元位号就地编辑器协作者（Rev.3 阶段 1.5，R1）。
# 与 gpEdgeEditor 一样惰性取自画布。
var gpNodeEditor: GPNodeTextEditor:
	get: return gpCv.gpNodeEditor

# Edge grip/route editing collaborator . / 边抓取点 / 布线编辑协作者。
var gpEdgeGrips: GPEdgeGripOps:
	get: return gpCv.gpEdgeGrips

# Tag-label grip/drag collaborator . / 位号标签抓取点 / 拖拽协作者。
var gpLabelGrips: GPLabelGripOps:
	get: return gpCv.gpLabelGrips

# Edge line-number grip/drag collaborator . / 边管线号抓取点 / 拖拽协作者。
var gpEdgeTagGrips: GPEdgeTagGripOps:
	get: return gpCv.gpEdgeTagGrips

# Drawing-frame grab-band / side-handle drag collaborator (Rev.3 stage 0c).
# 图框抓取带 / 侧手柄拖拽协作者（Rev.3 阶段 0c）。
# The last rung of GPSelectTool's press chain, and the only one that mutates a SHEET rather than the
# graph — which is why its commit goes through GPMutateSheetCommand instead of a node command.
# GPSelectTool 按下链的最后一环，也是唯一一个改**图纸**而非图的环节 —— 故其提交经
# GPMutateSheetCommand 而非节点命令。
var gpFrameGrips: GPFrameGripOps:
	get: return gpCv.gpFrameGrips

# Title-block (图签) whole-block drag collaborator (Rev.3 stage 1).
# 图签整块拖拽协作者（Rev.3 阶段 1）。
# The second collaborator whose commit writes a SHEET rather than the graph, and it is tested BEFORE the
# frame's grips because the block hugs the frame's bottom-right corner — the two targets overlap there.
# 第二个「提交写的是**图纸**而非图」的协作者，且它在图框抓取**之前**被测试，因为图签贴住图框右下角
# —— 两个目标在那里重叠。
var gpTitleBlockGrips: GPTitleBlockGripOps:
	get: return gpCv.gpTitleBlockGrips

# Grid-table column-boundary drag collaborator (stage 3 S4). Unlike the two above it writes
# the GRAPH (a node's props), so its commit rides the ordinary table command.
# grid 表格列边界拖拽协作者（阶段 3 S4）。与上面两位不同，它写的是**图**（节点的 props），
# 故其提交走普通的表格命令。
var gpTableGrips: GPTableGripOps:
	get: return gpCv.gpTableGrips

func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas
	gpState = gpCanvas.gpState
