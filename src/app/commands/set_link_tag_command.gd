class_name GPSetLinkTagCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
#
# D09 (user feedback 2026-11-04): the cross-sheet number becomes HAND-EDITABLE, exactly like
# an edge line number. A successful hand edit writes the tag AND attrs["tag_manual"] = true,
# so a later sheet renumber (gpRenumberSheets) skips a deliberate choice and keeps following
# the "<peer sheet number>-<seq>" convention for every other link. One undo step restores the
# exact prior pair (tag + manual flag), like GPSetEdgeTagCommand.
# D09（用户反馈 2026-11-04）：跨图纸编号开放**手工编辑**，与管线号同一待遇。手改成功即写
# 编号**并**置 attrs["tag_manual"] = true，使之后的图纸重编号（gpRenumberSheets）跳过这次
# 刻意的选择、其余 link 继续沿用「<对端图号>-<序号>」惯例。一个撤销步精确还原先前的
# （编号 + 手改标记）对，与 GPSetEdgeTagCommand 一致。
#
# The link lives in the CONTAINER store (ADR-43), not in the graph — the command mutates the
# live object; the store's gpChanged signal (fired by edit_service's gpTouch after gpDo)
# announces the change to every host. Undo/redo participate in the same command stack as the
# graph commands, so the history signal chain covers them too.
# link 存在于**容器** store（ADR-43）而非图内 —— 命令就地改活对象；store 的 gpChanged 信号
#（由 edit_service 在 gpDo 后的 gpTouch 触发）把变更通告给所有宿主。撤销/重做与图命令共用
# 同一条命令栈，历史信号链同样覆盖它们。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpLink: GPOffPageLink = null
var gpNewTag: String = ""

# Prior state, captured at execute time so undo is exact.
# 执行时捕获的原状态，使撤销精确。
var _gpOldTag: String = ""
var _gpHadManual: bool = false


func _init(gpInLink: GPOffPageLink, gpInNewTag: String) -> void:
	gpLink = gpInLink
	gpNewTag = gpInNewTag
	gpLabel = "修改跨图编号"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpLink == null:
		return false
	var gpWant: String = gpNewTag.strip_edges()
	if gpWant == "":
		# An empty tag would fall back to the derived reference text — refuse instead of
		# creating an ambiguous "no number" flag.
		# 空编号会回落到派生引用文字 —— 拒绝而非制造一块「无号」的歧义旗标。
		return false
	if gpWant == gpLink.gpTag:
		return false
	_gpOldTag = gpLink.gpTag
	_gpHadManual = bool(gpLink.gpAttrs.get("tag_manual", false))
	gpLink.gpTag = gpWant
	# A hand-typed number is a deliberate choice: renumbering must leave it alone.
	# 手工输入的号是刻意选择：重编号不得覆盖。
	gpLink.gpAttrs["tag_manual"] = true
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpLink == null:
		return
	gpLink.gpTag = _gpOldTag
	if _gpHadManual:
		gpLink.gpAttrs["tag_manual"] = true
	else:
		gpLink.gpAttrs.erase("tag_manual")


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpLink == null:
		return
	gpLink.gpTag = gpNewTag.strip_edges()
	gpLink.gpAttrs["tag_manual"] = true
