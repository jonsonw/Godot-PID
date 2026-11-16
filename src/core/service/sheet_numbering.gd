# Copyright 2026 G-PID Contributors. MIT License. See LICENSE.
class_name GPSheetNumbering
extends RefCounted

# Sheet-number authority for CREATION time (W13 user feedback 2026-11-11): a fresh sheet must
# carry a number IMMEDIATELY — before this, gpRenumberSheets only ran from the 编号设置 dialog,
# so every new sheet showed NO number anywhere (tab caption, manager list, preview header)
# until the user re-applied the numbering rules.
# 图纸编号的**创建时**权威（W13 用户反馈 2026-11-11）：新图纸必须**立即**带编号 —— 此前
# gpRenumberSheets 只在「编号设置」对话框里触发，于是每张新图纸在重套编号规则之前，
# 标签标题、管理列表、预览页眉全都没有编号。
#
# WHY A PURE CORE FILE / 为何是纯 core 文件：
# the decision "std template when a standard lives, bare zero-padded sequence otherwise" is
# ONE judgment and must not fork between the editor's tab bar and the manager's panel. Pure
# statics stay headless-testable. Hand-edit survival stays with gpAssignNumber (ADR-38) —
# this file only mints the FIRST number of a sheet's life.
# 「有标准走标准模板、无标准走裸三位序号」是**一个**判断，不得在编辑器标签栏与管理面板
# 之间分家。纯静态保持 headless 可测。手改存活的语义仍归 gpAssignNumber（ADR-38）——
# 本文件只铸造一张图纸**人生的第一枚**编号。
#
# Coding rule: every variable declares its type explicitly. / 编码规范：所有变量均显式声明类型。

# Mint a sheet number for the 1-based tab sequence: the live standard's template when one is
# adopted, a bare zero-padded sequence otherwise (still a valid, honest number).
# 为 1 起的标签序号铸一枚图纸编号：已采纳标准则走其模板，否则裸三位序号（同样是有效、
# 诚实的编号）。
static func gpNumberFor(gpSeq: int, gpStd: GPProjectStandard) -> String:
	if gpStd != null:
		return gpStd.gpSheetNumberFor(gpSeq)
	return "%03d" % maxi(gpSeq, 1)
