# ============================================================================
# GPSymbolEditorContext — 符号编辑器工具的共享状态持有者（M7）
# Shared state owner for symbol-editor tools (M7).
#
# 对应 GPCanvasToolContext：不持有 GPCanvas2D，而是把持有工作几何模型的 GPSymbolEditor 交给工具。
# 工具经它读写实时状态，不直接耦合 GPMakeSymbolDialog 内部结构。
# Parallels GPCanvasToolContext: instead of a GPCanvas2D, it hands tools the GPSymbolEditor that
# owns the working geometry model, so tools read/write live state through it instead of coupling
# to GPMakeSymbolDialog internals directly.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolEditorContext
extends RefCounted

# The editor that owns all interaction state. Tools read/write live state through it.
# 持有全部交互状态的编辑器。工具经它读写实时状态。
var gpEditor: GPSymbolEditor

func _init(gpOwner: GPSymbolEditor) -> void:
	gpEditor = gpOwner
