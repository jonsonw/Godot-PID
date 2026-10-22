extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# B4: addon contract v2 — chat-panel mount, tool definitions (shared with MCP), validation hooks,
# and the compatibility promise that v1 addons keep working unchanged.
# B4：插件契约 v2 —— 对话面板挂载、工具定义（与 MCP 共用）、校验钩子，以及「v1 插件原样可用」的承诺。
#
# The four promises / 四条承诺：
#   1. V1 ADONS STILL LOAD. Every new hook has a default, so the old contract is a subset of the
#      new one — not a migration.
#      **v1 插件照常加载**。新钩子都有默认实现，故旧契约是新契约的子集 —— 不是一次迁移。
#   2. THE THREE MOUNT POINTS ARE COLLECTED, typed and separated by kind.
#      **三个挂载点被收集**，有类型、按类别分开。
#   3. TOOL DEFINITIONS ARE DATA, validated once: id / description / args / handler.
#      **工具定义是数据**，一处校验：id / description / args / handler。
#   4. A HOOK CANNOT INVENT A FOURTH SEVERITY — the panel and the report only know three.
#      **钩子不能发明第四种严重度** —— 面板与报告只认三种。

const GP_FIXTURES: String = "res://tests/fixtures/addons"


func gpTestV1AddonStillLoads() -> void:
	var gpL: GPAddonLoader = GPAddonLoader.new()
	var gpNames: Array[String] = gpL.gpLoadedNames()
	gpL.gpScan(GP_FIXTURES)
	gpNames = gpL.gpLoadedNames()
	gpCheck(gpNames.has("fixture.good"), "v1 插件仍在 / the v1 addon still loads")
	gpCheck(gpNames.has("fixture.v2"), "v2 插件也加载 / the v2 addon loads too")


func gpTestV2MountPointsCollected() -> void:
	var gpL: GPAddonLoader = GPAddonLoader.new()
	gpL.gpScan(GP_FIXTURES)
	var gpCollected: Dictionary = gpL.gpCollect()
	gpEq((gpCollected.get("chat_panels", []) as Array).size(), 1, "一个对话面板 / one chat panel")
	gpEq((gpCollected.get("tool_defs", []) as Array).size(), 1, "一条工具定义 / one tool definition")
	gpEq((gpCollected.get("validation_hooks", []) as Array).size(), 1, "一条校验钩子 / one hook")


func gpTestV1AddonContributesNoV2Buckets() -> void:
	# The v1 fixture has no overrides; the DEFAULT implementations must contribute nothing rather
	# than a fake empty panel or a placeholder tool.
	# v1 夹具没有覆写；**默认实现**必须什么都不贡献 —— 不能是假空面板或占位工具。
	var gpA: GPIPIDAddon = GPIPIDAddon.new()
	gpEq(gpA._gpGetChatPanel(), "", "默认无对话面板 / no chat panel by default")
	gpEq((gpA._gpGetToolDefs() as Array).size(), 0, "默认无工具定义 / no tools by default")
	gpEq((gpA._gpGetValidationHooks() as Array).size(), 0, "默认无校验钩子 / no hooks by default")


func gpTestToolDefsValidate() -> void:
	var gpGood: Array = [{"id": "t1", "description": "d", "args": {}, "handler": "h"}]
	gpEq(GPAddonContract.gpValidateToolDefs(gpGood).size(), 0, "合法定义通过 / a valid def passes")
	var gpBad: Array = [{"id": "t1", "description": "d", "args": {}}]
	gpCheck(GPAddonContract.gpValidateToolDefs(gpBad).size() > 0,
		"缺 handler 被拒 / a missing handler is refused")


func gpTestDuplicateToolIdRefused() -> void:
	var gpDup: Array = [
		{"id": "t1", "description": "a", "args": {}, "handler": "h"},
		{"id": "t1", "description": "b", "args": {}, "handler": "h"},
	]
	var gpErrs: Array[String] = GPAddonContract.gpValidateToolDefs(gpDup)
	gpCheck(not gpErrs.is_empty(), "重复工具 id 被拒 / a duplicate tool id is refused")


func gpTestHookSeverityIsConstrained() -> void:
	var gpBad: Array = [{"id": "h1", "description": "d", "severity": "fatal", "handler": "h"}]
	gpCheck(GPAddonContract.gpValidateHooks(gpBad).size() > 0,
		"未知严重度被拒 / an unknown severity is refused")
	var gpGood: Array = [{"id": "h1", "description": "d", "severity": "warning", "handler": "h"}]
	gpEq(GPAddonContract.gpValidateHooks(gpGood).size(), 0, "已知严重度通过 / a known severity passes")


func gpTestFixtureToolDefMatchesSchema() -> void:
	var gpL: GPAddonLoader = GPAddonLoader.new()
	gpL.gpScan(GP_FIXTURES)
	var gpDefs: Array = (gpL.gpCollect().get("tool_defs", []) as Array)
	gpEq(GPAddonContract.gpValidateToolDefs(gpDefs).size(), 0,
		"夹具的工具定义合法 / the fixture's tool definition is valid")
	gpEq(str((gpDefs[0] as Dictionary).get("handler", "")), "gpEcho",
		"handler 是方法名（可序列化）/ the handler is a method name (serialisable)")
