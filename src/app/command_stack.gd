class_name GPCommandStack
extends RefCounted
# Undo/redo history (M4 of the modularisation plan).
# 撤销 / 重做历史（模块化方案 M4）。
#
# Scope / 范围:
#   Deliberately a plain RefCounted, NOT a Node and NOT Godot's built-in UndoRedo.
#   Godot's UndoRedo is node-oriented and wants live object references to call methods
#   on; our commands are value objects that invert themselves, which is what makes the
#   whole history testable without booting a scene tree.
#   刻意做成普通 RefCounted，而非 Node，也不用 Godot 内置 UndoRedo。
#   内置 UndoRedo 面向节点、要求持有活对象引用来回调方法；而我们的命令是自我求逆的
#   值对象，这使整条历史无需启动场景树即可测试。
#
# Rule / 规则:
#   Any new gpDo() clears the redo stack — that is the standard "a fresh edit invalidates
#   the redo branch" behaviour users expect from every editor.
#   任何一次 gpDo() 都会清空重做栈——这是用户在所有编辑器里都熟悉的
#   「新编辑使重做分支失效」行为。

# Hard cap on retained undo steps. Keeps a long session from growing without bound;
# the oldest step is dropped first.
# 保留的撤销步上限。避免长时间会话无界增长；最旧的步最先被丢弃。
const GP_DEFAULT_LIMIT: int = 200

# Steps kept before the oldest is dropped. Tunable per sheet if needed.
# 丢弃最旧步之前保留的步数。需要时可按图纸调整。
var gpLimit: int = GP_DEFAULT_LIMIT

# Applied commands, oldest first; the tail is the next candidate for undo.
# 已应用的命令，最旧在前；队尾是下一个撤销候选。
var _gpUndoStack: Array[GPCommand] = []

# Undone commands waiting to be redone; the tail is the next candidate for redo.
# 已撤销、等待重做的命令；队尾是下一个重做候选。
var _gpRedoStack: Array[GPCommand] = []


# Execute and record a command. Returns false (and records nothing) when the command
# reports it did nothing, so no empty undo step ever reaches the user.
# 执行并记录一条命令。命令报告「什么也没做」时返回 false 且不记录，
# 因此空撤销步永远不会到达用户。
func gpDo(gpCmd: GPCommand, gpCtx: GPCommandContext) -> bool:
	if gpCmd == null or gpCtx == null:
		return false
	if not gpCmd.gpExecute(gpCtx):
		return false
	_gpUndoStack.append(gpCmd)
	while _gpUndoStack.size() > gpLimit and not _gpUndoStack.is_empty():
		_gpUndoStack.remove_at(0)
	_gpRedoStack.clear()
	return true


# Undo the most recent command. Returns false when there is nothing to undo.
# 撤销最近一条命令。无可撤销时返回 false。
func gpUndo(gpCtx: GPCommandContext) -> bool:
	if _gpUndoStack.is_empty():
		return false
	var gpCmd: GPCommand = _gpUndoStack.pop_back()
	gpCmd.gpUndo(gpCtx)
	_gpRedoStack.append(gpCmd)
	return true


# Redo the most recently undone command. Returns false when there is nothing to redo.
# 重做最近被撤销的命令。无可重做时返回 false。
func gpRedo(gpCtx: GPCommandContext) -> bool:
	if _gpRedoStack.is_empty():
		return false
	var gpCmd: GPCommand = _gpRedoStack.pop_back()
	gpCmd.gpRedo(gpCtx)
	_gpUndoStack.append(gpCmd)
	return true


# Whether an undo step is available.
# 是否存在可撤销的步骤。
func gpCanUndo() -> bool:
	return not _gpUndoStack.is_empty()


# Whether a redo step is available.
# 是否存在可重做的步骤。
func gpCanRedo() -> bool:
	return not _gpRedoStack.is_empty()


# Number of retained undo steps.
# 保留的撤销步数量。
func gpUndoDepth() -> int:
	return _gpUndoStack.size()


# Number of retained redo steps.
# 保留的重做步数量。
func gpRedoDepth() -> int:
	return _gpRedoStack.size()


# Label of the next undo step, for menus / status ("Undo 删除节点"). Empty when none.
# 下一个撤销步的标签，供菜单 / 状态栏显示（如「撤销 删除节点」）。无则为空。
func gpUndoLabel() -> String:
	if _gpUndoStack.is_empty():
		return ""
	return _gpUndoStack[_gpUndoStack.size() - 1].gpLabel


# Label of the next redo step. Empty when none.
# 下一个重做步的标签。无则为空。
func gpRedoLabel() -> String:
	if _gpRedoStack.is_empty():
		return ""
	return _gpRedoStack[_gpRedoStack.size() - 1].gpLabel


# Drop all history. Call when the sheet is replaced or a document is closed, so undo
# can never reach back into a graph that is no longer displayed.
# 清空全部历史。更换图纸或关闭文档时调用，避免撤销回到已不再显示的图。
func gpClear() -> void:
	_gpUndoStack.clear()
	_gpRedoStack.clear()
