class_name GPPermissions
extends RefCounted
# Copyright © 2026 Jonson Wang
# The SINGLE permission gate for schema / property editing (Rev.3 stage 1.5, R2 权限口子).
# 模式 / 属性编辑的**唯一**权限闸门（Rev.3 阶段 1.5，R2 权限口子）。
#
# WHY ONE FILE / 为何只有一个文件：
# The user asked for entry-level CRUD "with a permission requirement" but also for the permission
# SYSTEM itself to come later. The contract is therefore: every button's `disabled` state and
# every command-layer pre-check asks HERE, and today the answers are all "yes". When the real
# permission system lands, ONLY this file changes — no call site ever learns what a permission is.
# 用户要求条目级增删改「需一定权限」，同时明确权限系统后续再做。故契约是：所有按钮的
# `disabled` 状态与所有命令层前置校验都问**这里**，而今天答案一律是「允许」。
# 将来真正的权限系统落地时，**只改本文件** —— 任何调用点都不需要知道「权限」为何物。
#
# Layer / 分层：lives in `app` (not `core`) because it is an application policy, and because
# `core` must stay free of UI-adjacent concerns; `ui` may call down into `app`, and the command
# layer pre-checks here too, so both gates share one source.
# 落在 `app` 层（非 `core`）：它是**应用**策略，且 core 不得沾染 UI 邻接的关注点；
# `ui` 可下调调用 `app`，命令层前置校验也走这里，故两道闸共用同一事实源。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Test seam ONLY: when true, every gate denies. Production code never writes it; the reverse-
# verification tests flip it to prove the wiring is live (a gate that cannot fail is not a gate).
# 仅供**测试**的接缝：置真时所有闸门一律拒绝。产品代码绝不写它；反向验证测试翻转它，
# 以证明接线是活的（不可能失败的闸门不叫闸门）。
static var gpForceDeny: bool = false


# May the user edit INSTANCE property entries (add / delete / rename custom entries, set values)?
# 用户可否编辑**实例**属性条目（新增 / 删除 / 改名自定义条目、改取值）？
static func gpCanEditProps() -> bool:
	return not gpForceDeny


# May the user edit SCHEMA-level definitions (library field definitions, symbol templates)?
# Deliberately a SEPARATE gate: instance CRUD and library edits have very different blast
# radii (one instance vs every project using the library), so a future permission system will
# almost certainly want to grant them independently.
# 用户可否编辑 **schema 级**定义（库字段定义、图元模板）？刻意**分开**设闸：实例级 CRUD
# 与库级编辑的影响半径完全不同（一个实例 vs 使用该库的全部项目），故将来的权限系统
# 几乎必然需要分别授权。
static func gpCanEditSchema() -> bool:
	return not gpForceDeny
