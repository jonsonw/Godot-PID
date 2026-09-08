# ============================================================================
# GPSymbolEditorTool — 图元编辑器交互工具基类（M7）
# Symbol-editor interaction tool base (M7).
#
# 照搬主画布的 GPCanvasTool 抽象，使符号编辑器复用与主画布同一套工具派发，取代原先内嵌在
# GPMakeSymbolDialog 里的 GPTool 枚举 + _gpDragKind/_gpDraftShape/_gpPolyPts 与 _gpCommit*/_gpHit*
# 状态机。工具只持有「某一种交互」的按下 / 移动 / 释放 / 按键 / 覆盖层绘制；编辑器持有状态与编排。
# Mirrors the canvas GPCanvasTool abstraction so the symbol editor reuses the SAME tool dispatch
# the main canvas uses, instead of the old bespoke GPTool enum + _gpCommit*/_gpHit* state machine
# that lived inside GPMakeSymbolDialog. A tool owns one interaction's press/move/release/key/overlay;
# the editor owns state + orchestration.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolEditorTool
extends RefCounted

# Shared context injected by the editor (owner + coordinate helpers).
# 由编辑器注入的共享上下文（持有者 + 坐标助手）。
var gpCtx: GPSymbolEditorContext

# Called when the tool becomes / stops being the active one. / 工具激活 / 停用时调用。
func gpOnActivate() -> void: pass
func gpOnDeactivate() -> void: pass

# Input hooks. Return true when the event was consumed (the editor will then repaint + resync).
# 输入钩子。返回 true 表示事件已被消费（编辑器据此重绘 + 重新同步）。
func gpOnPress(gpLocal: Vector2, gpShift: bool, gpDouble: bool) -> bool: return false
func gpOnMove(gpLocal: Vector2) -> bool: return false
func gpOnRelease(gpLocal: Vector2) -> bool: return false
func gpOnKey(gpKey: InputEventKey) -> bool: return false

# Cancel whatever half-finished interaction is in flight (ESC path). Returns true when there was
# something to cancel, so the editor can stop the key from propagating.
# 取消进行中的半个交互（ESC 路径）。确有可取消内容时返回 true，编辑器据此阻止按键继续传播。
func gpCancel() -> bool: return false

# Transient-draw overlay (rubber band, in-progress polyline, draft shape).
# 瞬态绘制覆盖层（橡皮筋、进行中的折线、草稿图形）。
func gpDrawOverlay(gpC: Control) -> void: pass
