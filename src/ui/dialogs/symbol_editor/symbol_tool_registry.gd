# ============================================================================
# GPSymbolToolRegistry — 工具种类 -> 工具 注册表（M7）
# Tool-kind -> tool registry (M7).
#
# 对应 GPCanvasToolRegistry：编辑器经它取当前工具，新增一种符号交互只需 gpRegister() 一行，
# 编辑器主体一行不改。
# Mirrors GPCanvasToolRegistry: the editor resolves the active tool via this registry; adding a
# new symbol interaction is a single gpRegister() call, the editor body unchanged.
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolToolRegistry
extends RefCounted

var _gpTools: Dictionary = {}  # GPSymbolToolKind int -> GPSymbolEditorTool

func gpRegister(gpKind: int, gpTool: GPSymbolEditorTool) -> void:
	_gpTools[gpKind] = gpTool

func gpHas(gpKind: int) -> bool:
	return _gpTools.has(gpKind)

func gpGet(gpKind: int) -> GPSymbolEditorTool:
	if _gpTools.has(gpKind):
		return _gpTools[gpKind]
	return null
