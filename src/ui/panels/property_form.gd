class_name GPPropertyForm
extends RefCounted
# Copyright © 2026 Jonson Wang
# Pure panel LOGIC for the inspector (M10): which fields exist, in what order, in which
# group, with which effective value — and what several selected instances share.
# 属性面板的**纯逻辑**（M10）：有哪些字段、按什么顺序、属于哪个分组、有效值是多少，
# 以及多选时若干实例共有的取值。
#
# Why this file exists / 本文件为何存在：
#   The inspector used to build widgets straight from an untyped `gpAttrsSchema` Dictionary,
#   so "which fields show" and "what their values are" could only be tested by building a UI.
#   Splitting the descriptor logic out makes both headless-testable and keeps the inspector
#   down to "draw what this descriptor says".
#   属性面板原先直接按无类型的 `gpAttrsSchema` 字典建控件，于是「显示哪些字段」与「取值如何」
#   只能靠搭界面才能验证。把描述逻辑拆出来后两者都可 headless 测试，面板只剩
#   「按描述符画控件」这一件事。
#
# Boundary / 边界:
#   Every read goes through GPPropertyResolver — never `node.gpProps` directly. That is the
#   rule that makes "edit the library, every project follows" true.
#   所有读取都经 GPPropertyResolver —— 绝不直接读 node.gpProps。
#   这正是「改图元库、全项目同步」得以成立的规则。
#
# Coding rule: every variable declares its type explicitly; all functions are static (pure).
# 编码规范：所有变量均显式声明类型；函数全部为静态（纯函数）。

# Group key used when a field declares no group, and its i18n display text.
# 字段未声明分组时所用的分组键及其显示文案。
const GP_UNGROUPED: String = ""

# Separator between a group and its field count in the section header (kept here so the
# panel and its tests agree on the exact text).
# 分组标题中「分组名」与「字段数」的分隔符（放在此处使面板与测试对文案保持一致）。
const GP_HEADER_SEP: String = "  ·  "


# Display label of one field: i18n key first, then the literal label, then the raw key.
# 单个字段的显示名：优先 i18n 键，其次字面标签，最后技术键。
static func gpFieldLabel(gpField: GPPropertyDef) -> String:
	if gpField == null:
		return ""
	if gpField.gpLabelKey != "":
		return I18n.gpTr(gpField.gpLabelKey, gpField.gpLabel)
	if gpField.gpLabel != "":
		return gpField.gpLabel
	return gpField.gpKey


# Panel sections in display order: ascending group, then gpOrder, then declaration order
# (GPPropertySchema.gpOrderedKeys already guarantees that order).
# 按显示顺序返回面板分组：先分组名升序，再 gpOrder，最后声明顺序
#（GPPropertySchema.gpOrderedKeys 已保证该顺序）。
# Each section: {"group": String, "fields": Array of field rows}.
# 每个分组：{"group": 分组名, "fields": 字段行数组}。
# Each field row: {"key","label","kind","value","overridden","required","read_only",
#                  "options","unit","min","max"}.
static func gpSections(gpSchema: GPPropertySchema, gpProps: Dictionary) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpSchema == null:
		return gpOut
	var gpSlotOfGroup: Dictionary = {}
	for gpK in gpSchema.gpOrderedKeys():
		var gpF: GPPropertyDef = gpSchema.gpFieldByKey(gpK)
		if gpF == null:
			continue
		var gpGroup: String = gpF.gpGroup if gpF.gpGroup != "" else GP_UNGROUPED
		if not gpSlotOfGroup.has(gpGroup):
			var gpSec: Dictionary = {}
			gpSec["group"] = gpGroup
			gpSec["fields"] = []
			gpOut.append(gpSec)
			gpSlotOfGroup[gpGroup] = gpOut.size() - 1
		var gpSlot: int = int(gpSlotOfGroup[gpGroup])
		var gpSec: Dictionary = gpOut[gpSlot]
		var gpFields: Array = gpSec["fields"]
		var gpRow: Dictionary = {}
		gpRow["key"] = gpF.gpKey
		gpRow["label"] = gpFieldLabel(gpF)
		gpRow["kind"] = gpF.gpKind
		gpRow["value"] = GPPropertyResolver.gpEffectiveValue(gpSchema, gpProps, gpF.gpKey)
		gpRow["overridden"] = GPPropertyResolver.gpIsOverridden(gpProps, gpF.gpKey)
		gpRow["required"] = gpF.gpRequired
		gpRow["read_only"] = gpF.gpReadOnly
		gpRow["options"] = gpF.gpOptions.duplicate()
		gpRow["unit"] = gpF.gpUnit
		gpRow["min"] = gpF.gpMin
		gpRow["max"] = gpF.gpMax
		gpFields.append(gpRow)
	return gpOut


# Values the instance still holds although the library no longer declares them (orphans).
# They are NEVER dropped — data sovereignty means a typed-in value outlives its field.
# 实例仍持有、但库中已不再声明的取值（孤儿）。它们**绝不**被丢弃 ——
# 数据主权意味着「手工录入的值」活得比它的字段更久。
# Each row: {"key": String, "value": Variant}.
static func gpOrphanRows(gpSchema: GPPropertySchema, gpProps: Dictionary) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	for gpK in GPPropertyResolver.gpOrphanKeys(gpSchema, gpProps):
		var gpRow: Dictionary = {}
		gpRow["key"] = gpK
		gpRow["value"] = gpProps.get(gpK, "")
		gpOut.append(gpRow)
	return gpOut


# Multi-select support: what every selected instance shares for one field.
# 多选支持：若干选中实例在某字段上共有的取值。
# Returns {"same": bool, "value": Variant}. "same" is false when the instances disagree,
# which is the panel's cue to show a blank / "multiple values" control instead of a value
# that would silently overwrite them all.
# 返回 {"same": 是否一致, "value": 取值}。实例取值不一致时 same 为 false，
# 面板据此显示空白 / 「多个取值」控件，而非一个会静默覆盖全部的值。
static func gpSharedValue(gpSchema: GPPropertySchema, gpPropsList: Array, gpKey: String) -> Dictionary:
	var gpOut: Dictionary = {}
	gpOut["same"] = false
	gpOut["value"] = null
	if gpPropsList.is_empty():
		return gpOut
	var gpFirst: Dictionary = gpPropsList[0] as Dictionary
	var gpFirstVal: Variant = GPPropertyResolver.gpEffectiveValue(gpSchema, gpFirst, gpKey)
	for gpI in range(1, gpPropsList.size()):
		var gpOther: Dictionary = gpPropsList[gpI] as Dictionary
		var gpVal: Variant = GPPropertyResolver.gpEffectiveValue(gpSchema, gpOther, gpKey)
		if gpVal != gpFirstVal:
			gpOut["value"] = gpFirstVal
			return gpOut
	gpOut["same"] = true
	gpOut["value"] = gpFirstVal
	return gpOut


# Whether every props dictionary in the list carries its own value for gpKey.
# A batch edit must mark ALL targets as overridden, so a later library change cannot
# quietly win over what the user just typed into six instances at once.
# 列表中每个 props 字典是否都为 gpKey 自带取值。批量编辑必须把**全部**目标标记为已覆盖，
# 否则日后库变更会悄悄盖掉用户刚一次录入到六个实例里的内容。
static func gpAllOverridden(gpPropsList: Array, gpKey: String) -> bool:
	if gpPropsList.is_empty():
		return false
	for gpP in gpPropsList:
		var gpD: Dictionary = gpP as Dictionary
		if not GPPropertyResolver.gpIsOverridden(gpD, gpKey):
			return false
	return true


# Section header text: the localized group name (or the "general" bucket for ungrouped
# fields), followed by the field count.
# 分组标题文案：本地化的分组名（未分组字段归入「通用」），后接字段数。
static func gpSectionTitle(gpGroup: String, gpFieldCount: int) -> String:
	var gpName: String = I18n.gpTr("inspector.group_general") if gpGroup == GP_UNGROUPED else I18n.gpTr(gpGroup, gpGroup)
	return "%s%s%d" % [gpName, GP_HEADER_SEP, gpFieldCount]
