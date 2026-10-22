class_name GPAddonContract
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Contract v2 validation (B4 / J02): the SHAPE of what an addon may inject, checked once, in one
# place, so a malformed addon fails with a readable reason instead of a later null.
# 契约 v2 校验（B4 / J02）：插件可注入内容的**形状**，只在一处校验，使格式错误的插件得到可读的
# 原因，而不是之后某个 null。
#
# Why validation lives in core and not in the loader / 为何校验在 core 而非加载器：
# the same shapes are consumed by the MCP bridge, the DRC pack and the shell's dock. Validating
# them once, in a module none of those three own, is what keeps one schema instead of three.
# 同样的形状会被 MCP 桥、DRC 规则包与外壳停靠栏消费。在一个三者都不拥有的模块里只校验一次，
# 才能让 schema 只存在一份，而不是三份。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Required keys of one tool definition (MCP-compatible: id / description / args / handler).
# 一条工具定义的必需键（MCP 兼容：id / description / args / handler）。
const GP_TOOL_KEYS: Array[String] = ["id", "description", "args", "handler"]

# Required keys of one validation hook.
# 一条校验钩子的必需键。
const GP_HOOK_KEYS: Array[String] = ["id", "description", "severity", "handler"]

# Severities a hook may declare (a plugin must not invent a fourth level: the panel colours and
# the report grouping are keyed on these three).
# 钩子可声明的严重度（插件不得发明第四级：面板配色与报告分组都以这三者为键）。
const GP_SEVERITIES: Array[String] = ["error", "warning", "info"]


# Validate a list of tool definitions. Returns human-readable error strings, empty when all good.
# 校验工具定义列表。返回人类可读的错误串，全部通过时为空。
static func gpValidateToolDefs(gpDefs: Array) -> Array[String]:
	var gpOut: Array[String] = []
	var gpSeen: Dictionary = {}
	for gpRaw in gpDefs:
		if not (gpRaw is Dictionary):
			gpOut.append("tool definition is not a dictionary")
			continue
		var gpD: Dictionary = gpRaw as Dictionary
		for gpKey in GP_TOOL_KEYS:
			if not gpD.has(gpKey):
				gpOut.append("tool '%s' is missing '%s'" % [str(gpD.get("id", "?")), gpKey])
		var gpId: String = str(gpD.get("id", ""))
		if gpId == "":
			gpOut.append("tool definition has an empty id")
		elif gpSeen.has(gpId):
			gpOut.append("duplicate tool id '%s'" % gpId)
		else:
			gpSeen[gpId] = true
		if gpD.has("args") and not (gpD.get("args") is Dictionary):
			gpOut.append("tool '%s' args must be a dictionary" % gpId)
		if gpD.has("handler") and str(gpD.get("handler", "")) == "":
			gpOut.append("tool '%s' has an empty handler" % gpId)
	return gpOut


# Validate a list of validation hooks.
# 校验校验钩子列表。
static func gpValidateHooks(gpHooks: Array) -> Array[String]:
	var gpOut: Array[String] = []
	var gpSeen: Dictionary = {}
	for gpRaw in gpHooks:
		if not (gpRaw is Dictionary):
			gpOut.append("validation hook is not a dictionary")
			continue
		var gpD: Dictionary = gpRaw as Dictionary
		for gpKey in GP_HOOK_KEYS:
			if not gpD.has(gpKey):
				gpOut.append("hook '%s' is missing '%s'" % [str(gpD.get("id", "?")), gpKey])
		var gpId: String = str(gpD.get("id", ""))
		if gpId == "":
			gpOut.append("hook has an empty id")
		elif gpSeen.has(gpId):
			gpOut.append("duplicate hook id '%s'" % gpId)
		else:
			gpSeen[gpId] = true
		var gpSev: String = str(gpD.get("severity", ""))
		if gpSev != "" and not GP_SEVERITIES.has(gpSev):
			gpOut.append("hook '%s' declares unknown severity '%s'" % [gpId, gpSev])
	return gpOut
