class_name GPFinding
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# One DRC finding: what rule fired, how bad it is, on which object, and where to look.
# 一条 DRC 发现：哪条规则触发、多严重、落在哪个对象、该往哪儿看。
#
# Why a value object and not a Dictionary / 为何是值对象而非字典：
# Findings are produced by pure rules, sorted, rendered in a panel, exported to text/CSV and
# (later) fed to the AI acceptance gate. A dictionary would let each consumer invent its own key
# names; a class makes "severity" and "rule id" single spellings, and gpToDict() is the one door
# to serialisation.
# 发现由纯规则产生，要被排序、在面板里显示、导出成文本/CSV，并（将来）喂给 AI 验收闸门。
# 用字典会让每个消费者自创键名；用类则让「严重度」与「规则号」各只有一种拼法，
# 而 gpToDict() 是通往序列化的唯一一道门。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Severity levels. Strings (not an enum) because they appear verbatim in exported reports and in
# the panel's colour mapping — one spelling end to end.
# 严重度。用字符串（而非枚举），因为它们会原样出现在导出报告与面板配色里 —— 从头到尾一种拼法。
const GP_ERROR: String = "error"

# A defect the drawing must not ship with.
# 图纸不应带着交付的缺陷。
const GP_WARNING: String = "warning"

# A smell worth a look; shippable.
# 值得看一眼的味道；可交付。
const GP_INFO: String = "info"

# Stable rule id, e.g. "drc.dangling_end".
# 稳定规则号，如 "drc.dangling_end"。
var gpRuleId: String = ""

# Severity (one of the constants above).
# 严重度（上面三个常量之一）。
var gpSeverity: String = GP_INFO

# i18n key of the message (params go through gpParams).
# 消息的 i18n 键（参数经 gpParams 传入）。
var gpMessageKey: String = ""

# Message parameters, in the order the key expects them.
# 消息参数，按键期望的顺序。
var gpParams: Array = []

# Node the finding belongs to ("" when none).
# 所属节点（无则空串）。
var gpNodeId: String = ""

# Edge the finding belongs to ("" when none).
# 所属连线（无则空串）。
var gpEdgeId: String = ""

# Annotation shape index the finding belongs to (-1 when none).
# 所属注释图形下标（无则 -1）。
var gpShapeIdx: int = -1

# World position to centre the view on when the user clicks the row (Vector2.INF = none).
# 用户点击该行时视图要对准的世界坐标（Vector2.INF = 无）。
var gpWorld: Vector2 = Vector2.INF


# Build one finding. Everything after gpSeverity is optional so the common case stays short.
# 构造一条发现。gpSeverity 之后的参数可选，使常见情形保持简短。
static func gpMake(gpRuleId: String, gpSeverity: String, gpMessageKey: String,
		gpParams: Array = []) -> GPFinding:
	var gpF: GPFinding = GPFinding.new()
	gpF.gpRuleId = gpRuleId
	gpF.gpSeverity = gpSeverity
	gpF.gpMessageKey = gpMessageKey
	gpF.gpParams = gpParams.duplicate()
	return gpF


# The same finding attached to a node and a location.
# 把同一条发现挂到某节点与某位置上。
func gpOnNode(gpId: String, gpWorld: Vector2) -> GPFinding:
	gpNodeId = gpId
	gpWorld = gpWorld
	return self


# The same finding attached to an edge and a location.
# 把同一条发现挂到某连线与某位置上。
func gpOnEdge(gpId: String, gpWorld: Vector2) -> GPFinding:
	gpEdgeId = gpId
	gpWorld = gpWorld
	return self


# The same finding attached to an annotation shape.
# 把同一条发现挂到某注释图形上。
func gpOnShape(gpIdx: int, gpWorld: Vector2) -> GPFinding:
	gpShapeIdx = gpIdx
	gpWorld = gpWorld
	return self


# Whether this finding should block a delivery (errors do, warnings and infos do not).
# 该发现是否应拦住交付（error 拦，warning / info 不拦）。
func gpBlocksDelivery() -> bool:
	return gpSeverity == GP_ERROR


# Plain dictionary for the report exporters and for tests.
# 供报告导出器与测试使用的普通字典。
func gpToDict() -> Dictionary:
	return {
		"rule": gpRuleId,
		"severity": gpSeverity,
		"message_key": gpMessageKey,
		"params": gpParams.duplicate(),
		"node_id": gpNodeId,
		"edge_id": gpEdgeId,
		"shape_idx": gpShapeIdx,
		"x": gpWorld.x if gpWorld != Vector2.INF else null,
		"y": gpWorld.y if gpWorld != Vector2.INF else null,
	}


# Human-readable one-liner (localized) for text reports and the panel row.
# 供文本报告与面板行使用的人类可读单行（已本地化）。
func gpText() -> String:
	var gpMsg: String = I18n.gpTr(gpMessageKey)
	if gpParams.is_empty():
		return gpMsg
	return gpMsg % gpParams
