class_name GPSignalTool
extends GPPipeTool
# Copyright © 2026 Jonson Wang
# Two-press instrument / electrical signal-line drawing (P3).
# 两段式仪表 / 电气信号线绘制（P3）。
#
# Why inherit instead of copying / 为何继承而非复制：
#   The interaction is identical — anchor, preview, commit, cancel. Only WHAT is connected
#   differs. Copying the state machine would mean every future fix (double-click to dangle,
#   ESC handling, preview fidelity) has to be made twice, and the two copies would drift.
#   交互完全相同 —— 锚定、预览、提交、取消。不同的只是「连什么」。若复制状态机，将来每个修复
#   （双击生成悬空端、ESC 处理、预览保真）都得做两遍，且两份副本必然分家。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


# Signal lines, not pipes. / 是信号线，不是管道。
func _gpKind() -> String:
	return GPPIDEdge.GP_SIGNAL


# A signal runs between transmitters, valve actuators, terminals and field enclosures — never
# into a process nozzle. NOZZLE is deliberately absent.
# 信号线连接变送器、阀门执行机构、端子与现场接线箱 —— 绝不接入工艺管口。刻意不含 NOZZLE。
func _gpWantTypes() -> Array[String]:
	return [GPPort.GP_SIGNAL, GPPort.GP_ACTUATOR, GPPort.GP_TERMINAL]


# Electric by default; the inspector changes it afterwards (and the style table repaints
# immediately because the style is a pure function of kind + signal type).
# 默认电气；事后由属性面板修改（样式表会立即重绘，因为样式是「类型 + 信号类型」的纯函数）。
func _gpDefaultSignalType() -> String:
	return "ELECTRIC"
