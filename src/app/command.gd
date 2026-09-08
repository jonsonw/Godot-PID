class_name GPCommand
extends RefCounted
# Base class for every user-visible edit (M4 of the modularisation plan).
# 所有用户可见编辑的基类（模块化方案 M4）。
#
# Contract / 契约:
#   gpExecute  apply the change; return false to mean "nothing happened", in which case
#              the stack refuses to record it (no phantom undo step).
#              应用改动；返回 false 表示「什么也没发生」，栈将拒绝记录（不产生幽灵撤销步）。
#   gpUndo     restore the exact prior state.
#              恢复到改动前的确切状态。
#   gpRedo     re-apply. Defaults to gpExecute, but commands that allocate an id MUST
#              override it so redo reuses the original object instead of minting a new id.
#              重新应用。默认走 gpExecute，但会分配 id 的命令必须覆写，
#              使 redo 复用原对象而非生成新 id。
#
# State rule / 状态规则:
#   A command is a value object: it captures everything needed to invert itself at
#   execute time (removed objects, previous positions) and never reaches back into a
#   widget to find out what to undo. That is what makes it headless-testable.
#   命令是值对象：在执行时就把撤销所需的全部信息（被删对象、原坐标）捕获下来，
#   撤销时绝不回查控件。这正是它可 headless 测试的原因。

# Human-readable name for undo/redo menus and the status bar.
# 供撤销 / 重做菜单与状态栏显示的人类可读名称。
var gpLabel: String = ""


# Apply the change. Returns false when the command could not do anything, which tells
# GPCommandStack.gpDo() to drop it instead of pushing a no-op undo step.
# 应用改动。无法执行时返回 false，GPCommandStack.gpDo() 据此丢弃它，不压入空撤销步。
func gpExecute(_gpCtx: GPCommandContext) -> bool:
	return false


# Restore the state from before gpExecute ran.
# 恢复到 gpExecute 执行前的状态。
func gpUndo(_gpCtx: GPCommandContext) -> void:
	pass


# Re-apply after an undo. Default simply re-executes; override when re-executing twice
# would not be idempotent (see GPAddNodeCommand).
# 撤销后重新应用。默认直接重执行；若重执行两次不等价则需覆写（见 GPAddNodeCommand）。
func gpRedo(gpCtx: GPCommandContext) -> void:
	gpExecute(gpCtx)
