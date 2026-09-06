# ============================================================================
# GPCanvasToolRegistry — 模式 → 工具 注册表（P2 拆分）
# Mode -> tool registry (P2 split).
#
# 把 GPMode 映射到工具实例。画布经 _gpActiveTool() 取当前工具，新增交互只需 gpRegister 一行。
# Maps GPMode to a tool instance. The canvas resolves the active tool via _gpActiveTool(); adding an
# interaction is a single gpRegister() call.
# ============================================================================

class_name GPCanvasToolRegistry
extends RefCounted

var _gpTools: Dictionary = {}  # mode int -> GPCanvasTool

func gpRegister(gpMode: int, gpTool: GPCanvasTool) -> void:
	_gpTools[gpMode] = gpTool

func gpHas(gpMode: int) -> bool:
	return _gpTools.has(gpMode)

func gpGet(gpMode: int) -> GPCanvasTool:
	if _gpTools.has(gpMode):
		return _gpTools[gpMode]
	return null

func gpModes() -> Array:
	return _gpTools.keys()
