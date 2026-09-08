# ============================================================================
# GPCanvasTool — 画布交互工具基类（P2 拆分）
# Canvas interaction tool base class (P2 split).
#
# 每个交互工具是一个 RefCounted 委托，经 GPCanvasToolContext 读写画布实时状态。画布只持
# 有瞬态拖拽状态与编排逻辑，工具负责「某一种交互」的按下 / 移动 / 释放 / 按键 / 覆盖层绘制。
# 新增交互 = 新增一个文件 + 注册表加一行，画布主体一行不改（见 docs/架构优化方案 §5）。
# Every interaction tool is a RefCounted delegate that reads/writes live canvas state through
# GPCanvasToolContext. The canvas keeps transient drag state + orchestration; each tool owns one
# interaction's press / move / release / key / overlay. Adding an interaction = one file + one
# registry line, the canvas body unchanged (docs/架构优化方案 §5).
# ============================================================================

class_name GPCanvasTool
extends RefCounted

# Shared context injected by the canvas (state owner + shared interact state).
# 由画布注入的共享上下文（状态持有者 + 共享交互状态）。
var gpCtx: GPCanvasToolContext

# Called when the tool becomes / stops being the active one. / 工具激活 / 停用时调用。
func gpOnActivate() -> void: pass
func gpOnDeactivate() -> void: pass

# Input hooks. Return true when consumed (canvas will accept_event()).
# 输入钩子。返回 true 表示事件已被消费（画布将 accept_event()）。
func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool: return false
func gpOnMove(gpWorld: Vector2) -> bool: return false
func gpOnRelease(gpWorld: Vector2) -> bool: return false
func gpOnKey(gpKey: InputEventKey) -> bool: return false

# Cancel whatever half-finished interaction is in flight (ESC path). Returns true when there was
# something to cancel, so the caller can stop the key from propagating. Default: nothing to
# cancel — a tool overrides this only if it holds transient state the user can abandon.
# 取消进行中的半个交互（ESC 路径）。确有可取消内容时返回 true，调用方可据此阻止按键继续
# 传播。默认无可取消内容——只有持有「用户可放弃的瞬态状态」的工具才覆写它。
func gpCancel() -> bool: return false

# Overlay painting (rubber band, grips, preview). / 覆盖层绘制（橡皮筋、抓取点、预览）。
func gpDrawOverlay(gpCv: CanvasItem) -> void: pass
func gpCursor() -> int: return Input.CURSOR_ARROW
