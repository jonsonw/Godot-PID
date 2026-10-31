class_name GPDRCRepair
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# DRC → repair-plan contract (ADR-39 P4). The AI loop must never guess from prose: every finding
# carries a machine-readable `fix_hint`, and this class turns it into one of a SMALL, stable set
# of actions the repair engine is allowed to perform.
# DRC → 修复计划契约（ADR-39 P4）。AI 回路绝不能从散文里猜：每条发现都带机器可读 `fix_hint`，
# 本类把它收敛为一组**小且稳定**的允许动作，供修复引擎执行。
#
# Why actions are a closed set / 为何动作是封闭集合：
# "AI repairs a drawing" is only safe if the repair vocabulary is small, auditable and undoable.
# The planner proposes; the command layer disposes; DRC re-verifies.
# 只有修复词汇小、可审计、可撤销，「AI 修图」才安全。计划器提议；命令层执行；DRC 再验证。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_ACTION_MOVE: String = "move"
const GP_ACTION_RELINK: String = "relink"
const GP_ACTION_DELETE: String = "delete"
const GP_ACTION_FILL: String = "fill"
const GP_ACTION_RENUMBER: String = "renumber"
const GP_ACTION_REROUTE: String = "reroute"
const GP_ACTION_ADD: String = "add"
const GP_ACTION_TOGGLE: String = "toggle"
const GP_ACTION_RESIZE: String = "resize"
const GP_ACTION_REVIEW: String = "review"


# One plan entry per unique (entity, check) pair. Deterministic order: severity, entity, check.
# 每个（对象、检查号）唯一计划项。确定性顺序：级别、对象、检查号。
static func gpPlan(gpFindings: Array[GPFinding]) -> Array[Dictionary]:
	var gpSeen: Dictionary = {}
	var gpOut: Array[Dictionary] = []
	for gpF in gpFindings:
		if gpF == null:
			continue
		var gpKey: String = gpF.gpEntityUid + "|" + (gpF.gpCheckId if gpF.gpCheckId != ""
			else gpF.gpRuleId)
		if gpSeen.has(gpKey):
			continue
		gpSeen[gpKey] = true
		gpOut.append({
			"entity_uid": gpF.gpEntityUid,
			"sheet_id": gpF.gpSheetId,
			"check": gpF.gpCheckId if gpF.gpCheckId != "" else gpF.gpRuleId,
			"severity": gpF.gpSeverity,
			"action": gpActionFor(gpF.gpFixHint),
			"hint": gpF.gpFixHint,
			"params": gpF.gpParams.duplicate(),
			"waived": gpF.gpWaived,
		})
	gpOut.sort_custom(_gpLess)
	return gpOut


# Map a fix hint to the closed action vocabulary. Unknown hints become `review` — never a
# silent no-op, because an unrecognised suggestion is exactly what a human should see.
# 把 fix hint 映射到封闭动作集。未知提示变成 `review` —— 绝不静默无操作，因为无法识别的建议
# 正是应该给人看的。
static func gpActionFor(gpHint: String) -> String:
	match gpHint:
		"drc.fix.move", "drc.fix.move_label":
			return GP_ACTION_MOVE
		"drc.fix.relink", "drc.fix.reconnect", "drc.fix.remount", "drc.fix.add_junction":
			return GP_ACTION_RELINK
		"drc.fix.delete":
			return GP_ACTION_DELETE
		"drc.fix.fill_prop", "drc.fix.fill_title_block", "drc.fix.fill_loop", "drc.fix.use_code":
			return GP_ACTION_FILL
		"drc.fix.renumber", "drc.fix.renumber_nozzle", "drc.fix.set_number":
			return GP_ACTION_RENUMBER
		"drc.fix.reroute", "drc.fix.change_reducer":
			return GP_ACTION_REROUTE
		"drc.fix.add_signal":
			return GP_ACTION_ADD
		"drc.fix.frame_on", "drc.fix.replace_symbol", "drc.fix.promote_symbol":
			return GP_ACTION_REVIEW
		"drc.fix.resize_sheet":
			return GP_ACTION_RESIZE
		"drc.fix.review_override":
			return GP_ACTION_REVIEW
		_:
			return GP_ACTION_REVIEW


# Counts by action, for the AI gate / status line.
# 按动作计数，供 AI 闸门 / 状态行使用。
static func gpCounts(gpPlan: Array[Dictionary]) -> Dictionary:
	var gpOut: Dictionary = {}
	for gpE in gpPlan:
		var gpAction: String = str(gpE.get("action", GP_ACTION_REVIEW))
		gpOut[gpAction] = int(gpOut.get(gpAction, 0)) + 1
	return gpOut


static func _gpLess(gpA: Dictionary, gpB: Dictionary) -> bool:
	var gpRank: Dictionary = {"error": 0, "warning": 1, "info": 2}
	var gpRa: int = int(gpRank.get(str(gpA.get("severity", "info")), 3))
	var gpRb: int = int(gpRank.get(str(gpB.get("severity", "info")), 3))
	if gpRa != gpRb:
		return gpRa < gpRb
	if str(gpA.get("entity_uid", "")) != str(gpB.get("entity_uid", "")):
		return str(gpA.get("entity_uid", "")) < str(gpB.get("entity_uid", ""))
	return str(gpA.get("check", "")) < str(gpB.get("check", ""))
