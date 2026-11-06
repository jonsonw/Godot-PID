extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# B4: addon contract v2 — chat-panel mount, tool definitions (shared with MCP), validation hooks,
# and the compatibility promise that v1 addons keep working unchanged.
# B4：插件契约 v2 —— 对话面板挂载、工具定义（与 MCP 共用）、校验钩子，以及「v1 插件原样可用」的承诺。
#
# The five promises / 五条承诺：
#   1. V1 ADONS STILL LOAD. Every new hook has a default, so the old contract is a subset of the
#      new one — not a migration.
#      **v1 插件照常加载**。新钩子都有默认实现，故旧契约是新契约的子集 —— 不是一次迁移。
#   2. THE THREE MOUNT POINTS ARE COLLECTED, typed and separated by kind.
#      **三个挂载点被收集**，有类型、按类别分开。
#   3. TOOL DEFINITIONS ARE DATA, validated once: id / description / args / handler.
#      **工具定义是数据**，一处校验：id / description / args / handler。
#   4. A HOOK CANNOT INVENT A FOURTH SEVERITY — the panel and the report only know three.
#      **钩子不能发明第四种严重度** —— 面板与报告只认三种。
#   5. THE HOOKS ARE PUBLIC AND THE VERSION IS ACTUALLY READ (S6). Both were prose-only before.
#      **钩子是公开名、版本号真的被读**（S6）。此前两件都只是散文。

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
	gpEq(gpA.gpGetChatPanel(), "", "默认无对话面板 / no chat panel by default")
	gpEq((gpA.gpGetToolDefs() as Array).size(), 0, "默认无工具定义 / no tools by default")
	gpEq((gpA.gpGetValidationHooks() as Array).size(), 0, "默认无校验钩子 / no hooks by default")


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


# ============================================================================
# S6 (2026-11-06): the contract's TWO promises that were only prose.
# S6（2026-11-06）：契约里**只写在散文里**的两条承诺。
#
# (1) EVERY HOOK WAS `_gp*`. The `_` prefix means "private to this class" in this project, while
#     these methods are meant to be overridden in ANOTHER repository. The contract — the one file
#     every Pro implementer reads first — was the one file contradicting the naming rule.
# (1) 每个钩子都叫 `_gp*`。本项目里 `_` 前缀表示「本类私有」，而这些方法就是给**另一个仓库**覆写
#     的。契约（每个 Pro 实现者第一个读的文件）恰恰是唯一违反命名规则的那个文件。
#
# (2) ADR-35 §7 says "GP_CONTRACT_VERSION rides along in the diagnostics". For three weeks the
#     constant was declared and NEVER READ: the promise lived in the ADR only. A declared-but-unread
#     constant is the cheapest kind of lie — it looks like the feature is there.
# (2) ADR-35 §7 说「`GP_CONTRACT_VERSION` 随诊断一起报告」。三周里这个常量声明了却**从未被读**：
#     承诺只活在 ADR 里。一个「声明了但没人读」的常量是最便宜的一种谎 —— 它看起来像功能已经在了。
# ============================================================================

const GP_CONTRACT_PATH: String = "res://src/addons/ipid_addon.gd"

# Every hook the base class publishes. A name missing here is a hook the loader calls and the
# contract no longer declares — which compiles, because GDScript resolves it at call time.
# 基类发布的每个钩子。此处缺失的名字 = 加载器在调、契约却不再声明的钩子 —— 这能编译通过，
# 因为 GDScript 在调用时才解析。
const GP_CONTRACT_HOOKS: Array[String] = [
	"gpGetName", "gpGetTools", "gpGetPanels", "gpOnGraphChanged",
	"gpRegisterExporters", "gpRegisterSymbolPacks",
	"gpGetChatPanel", "gpGetToolDefs", "gpGetValidationHooks",
	"gpOnLoad", "gpOnSync", "gpContractVersion",
]


# Drop `#` comments: the contract's own header EXPLAINS the `_gp` prefix rule, so a naive count
# would fail on the documentation of the very thing it is checking.
# 去掉 `#` 注释：契约自己的头部**解释**了 `_gp` 前缀规则，裸计数会被「正在检查的那件事的说明文字」
# 判成失败。
func _gpStripComments(gpText: String) -> String:
	var gpOut: Array[String] = []
	for gpLine in gpText.split("\n"):
		gpOut.append(gpLine.split("#")[0])
	return "\n".join(gpOut)


func gpTestContractHooksArePubliclyNamed() -> void:
	var gpSrc: String = FileAccess.get_file_as_string(GP_CONTRACT_PATH)
	gpCheck(gpSrc != "",
		"契约源码可读（不可读会让下面每条都白过）/ the contract source is readable")
	var gpCode: String = _gpStripComments(gpSrc)
	for gpName in GP_CONTRACT_HOOKS:
		gpCheck(gpCode.contains("func " + gpName + "("), "公开钩子存在 / public hook exists: " + gpName)
	# The one assertion that catches a NEW hook added with the private prefix — a per-name check
	# cannot, because the name does not exist yet when the check is written.
	# 唯一能抓到「新加的钩子又用了私有前缀」的断言 —— 逐名检查做不到，因为写检查时那个名字还不存在。
	gpEq(gpCode.count("func _gp"), 0,
		"契约里不得有私有命名的方法（钩子不是辅助函数）/ no privately named method in the contract")


func gpTestContractVersionIsCompared() -> void:
	var gpCur: int = GPIPIDAddon.GP_CONTRACT_VERSION
	gpEq(GPAddonContract.gpContractVerdict(gpCur), "ok",
		"同版本 → ok / same version is ok")
	gpEq(GPAddonContract.gpContractVerdict(gpCur - 1), "older",
		"旧插件是安全方向（子集）/ an older addon is the safe direction")
	gpEq(GPAddonContract.gpContractVerdict(gpCur + 1), "newer",
		"新插件可能调用核心没有的钩子 / a newer addon may call hooks this core lacks")
	gpEq(GPAddonContract.gpContractVerdict(0), "unknown",
		"未声明不是「古老」/ unstated is not 'ancient'")
	# The default must be THIS core's version, not 0: an addon written before versions existed
	# never claimed to be old, and must not be reported as such.
	# 默认值必须是**本核心**的版本而非 0：一个在版本号出现之前写好的插件从未主张自己很旧，
	# 也不该被这样报告。
	gpEq(GPIPIDAddon.new().gpContractVersion(), gpCur,
		"默认声明＝本核心版本 / the default declares this core's version")


func gpTestDiagnosticsCarryTheContractVerdict() -> void:
	# Behavioural counterpart of the static check above: the constant is read, the verdict is
	# written, AND the two kinds of diagnostic row stay distinguishable.
	# 上面那条静态检查的行为对侧：常量真的被读、结论真的被写，且两类诊断行仍可区分。
	var gpL: GPAddonLoader = GPAddonLoader.new()
	gpL.gpScan(GP_FIXTURES)
	var gpOkRows: int = 0
	var gpEmptyRows: int = 0
	for gpD in gpL.gpDiagnostics:
		if bool(gpD.get("ok", false)):
			gpOkRows += 1
			gpEq(str(gpD.get("contract", "missing")), "ok",
				"成功行带着版本结论 / a passing row carries the verdict")
		else:
			gpEmptyRows += 1
			# Empty, not "ok": these candidates never produced an instance, so there was no
			# declared version to compare. Stamping "ok" here would claim a comparison that
			# never happened.
			# 空串而非 "ok"：这些候选从未产出实例，没有可比较的声明版本。在此盖上 "ok" 等于
			# 宣称做过一次从未发生的比较。
			gpEq(str(gpD.get("contract", "missing")), "",
				"提前返回的行没有结论 / an early-exit row has no verdict")
	gpCheck(gpOkRows >= 1 and gpEmptyRows >= 1,
		"两类诊断行都出现过（否则本测试只覆盖了一半）/ both kinds of row occurred")
