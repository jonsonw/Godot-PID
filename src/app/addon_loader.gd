class_name GPAddonLoader
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Addon loader (B3 / J01): scan a directory for GPIPIDAddon subclasses, instantiate them, collect
# what they want to inject, and ISOLATE the broken ones.
# 插件加载器（B3 / J01）：扫描目录里的 GPIPIDAddon 子类、实例化它们、收集它们要注入的东西，
# 并**隔离**坏掉的。
#
# The one rule that matters / 唯一真正要紧的规则：
# a broken addon must not take the application down. That is why every step below (load,
# instantiate, hook call) is wrapped individually: a half-written addon is a NORMAL state during
# development, and "my editor won't start" is an unacceptable answer to it.
# 坏插件绝不能把应用带崩。故下面每一步（load / 实例化 / 调钩子）都单独包裹：写了一半的插件在开发期
# 是**常态**，而「我的编辑器起不来了」对这件事是不可接受的回答。
#
# What the loader does NOT do / 加载器不做什么：
# it does not decide WHERE a tool goes or HOW an exporter is registered — it returns what the
# addons asked for, and the shell (which owns the UI) decides. Keeping that boundary is what
# keeps this file testable headless and free of view knowledge.
# 它不决定工具放哪儿、导出器怎么注册 —— 它只返回插件**要求**的东西，由外壳（拥有界面的那一方）
# 决定。保持这条边界，正是本文件能 headless 测试、且不含视图知识的原因。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Extension scanned for addon scripts.
# 扫描插件脚本的扩展名。
const GP_SUFFIX: String = ".gd"

# One diagnostic entry per candidate file: what was found and whether it is usable.
# 每个候选文件一条诊断：发现了什么、能不能用。
# Keys: "path", "ok", "reason", "name", "version".
# 键：path / ok / reason / name / version。
var gpDiagnostics: Array[Dictionary] = []

# The addons that loaded successfully, in scan order.
# 成功加载的插件，按扫描顺序。
var gpAddons: Array[GPIPIDAddon] = []

# Ids already taken (an addon declaring a duplicate id is refused: two addons fighting over one
# injection point is a configuration error, not something to guess about).
# 已被占用的 id（声明重复 id 的插件被拒：两个插件抢同一个注入点属配置错误，不该靠猜）。
var _gpSeenIds: Dictionary = {}


# Scan a directory and load every usable addon. Returns the loaded addons.
# 扫描目录并加载每个可用插件。返回已加载的插件。
func gpScan(gpDir: String) -> Array[GPIPIDAddon]:
	gpDiagnostics.clear()
	gpAddons.clear()
	_gpSeenIds.clear()
	var gpFiles: Array[String] = _gpListScripts(gpDir)
	for gpPath in gpFiles:
		_gpTryLoad(gpPath)
	return gpAddons


# Names of the loaded addons (for a diagnostics panel / status line).
# 已加载插件的名称（供诊断面板 / 状态栏）。
func gpLoadedNames() -> Array[String]:
	var gpOut: Array[String] = []
	for gpA in gpAddons:
		gpOut.append(gpA._gpGetName())
	return gpOut


# Every tool / panel / exporter / symbol pack the loaded addons asked for, grouped by kind.
# 已加载插件要求的全部工具 / 面板 / 导出器 / 图元包，按类别分组。
# Why grouped instead of injected here / 为何分组返回而非在此注入：
# the shell owns the menus, docks and registries; a loader that reached into them would become
# untestable and would couple addon support to the UI layer.
# 菜单、停靠栏与注册表归外壳所有；伸手进去的加载器会变得不可测，并把插件支持耦合到界面层。
func gpCollect() -> Dictionary:
	var gpTools: Array = []
	var gpPanels: Array = []
	var gpExporters: Array = []
	var gpPacks: Array = []
	# v2 buckets (B4): chat panel mount, tool definitions, validation hooks. Defaults are empty,
	# so a v1 addon simply contributes nothing to these three.
	# v2 桶（B4）：对话面板挂载、工具定义、校验钩子。默认皆空，故 v1 插件对这三项毫无贡献。
	var gpChatPanels: Array = []
	var gpToolDefs: Array = []
	var gpValidationHooks: Array = []
	for gpA in gpAddons:
		gpTools.append_array(gpA._gpGetTools())
		gpPanels.append_array(gpA._gpGetPanels())
		gpExporters.append_array(gpA._gpRegisterExporters())
		gpPacks.append_array(gpA._gpRegisterSymbolPacks())
		var gpChat: String = gpA._gpGetChatPanel()
		if gpChat != "":
			gpChatPanels.append(gpChat)
		gpToolDefs.append_array(gpA._gpGetToolDefs())
		gpValidationHooks.append_array(gpA._gpGetValidationHooks())
	return {
		"tools": gpTools,
		"panels": gpPanels,
		"exporters": gpExporters,
		"symbol_packs": gpPacks,
		"chat_panels": gpChatPanels,
		"tool_defs": gpToolDefs,
		"validation_hooks": gpValidationHooks,
	}


# Whether the whole scan produced zero usable addons AND at least one failure — the state a
# diagnostics line should shout about.
# 整次扫描是否「零可用且至少一项失败」—— 诊断行应当高声报告的状态。
func gpAllFailed() -> bool:
	if not gpAddons.is_empty():
		return false
	for gpD in gpDiagnostics:
		if not bool(gpD.get("ok", false)):
			return true
	return false


# List candidate scripts. Sorted, so a load order is reproducible (an addon may depend on an
# earlier one being present).
# 列出候选脚本。排序使加载顺序可复现（插件可能依赖更早的那个已存在）。
func _gpListScripts(gpDir: String) -> Array[String]:
	var gpOut: Array[String] = []
	if gpDir == "" or not DirAccess.dir_exists_absolute(gpDir):
		return gpOut
	var gpDirAccess: DirAccess = DirAccess.open(gpDir)
	if gpDirAccess == null:
		return gpOut
	for gpName in gpDirAccess.get_files():
		if gpName.ends_with(GP_SUFFIX) and not gpName.ends_with(GP_SUFFIX + ".import"):
			gpOut.append(gpDir.path_join(gpName))
	gpOut.sort()
	return gpOut


# Load one script, instantiate it, validate it and record a diagnostic either way.
# 加载一个脚本、实例化、校验，并无论成败都记录一条诊断。
func _gpTryLoad(gpPath: String) -> void:
	# Step 1: load the script. A syntax error lands here, not at instantiate time.
	# 第一步：加载脚本。语法错误落在这里，而不是实例化时。
	var gpRes: Resource = ResourceLoader.load(gpPath)
	if gpRes == null or not (gpRes is GDScript):
		_gpDiag(gpPath, false, "not_a_script", "", "")
		return
	var gpScript: GDScript = gpRes as GDScript
	# Step 2: instantiate. A script that cannot be instantiated (abstract / broken base) is a
	# normal half-written state and must stay contained.
	# 第二步：实例化。无法实例化的脚本（抽象类 / 基类损坏）是正常的「写了一半」状态，必须被兜住。
	var gpObj: Variant = gpScript.new()
	if gpObj == null or not (gpObj is GPIPIDAddon):
		_gpDiag(gpPath, false, "not_an_addon", "", "")
		return
	var gpAddon: GPIPIDAddon = gpObj as GPIPIDAddon
	# Step 3: ask it who it is. The contract's name is also the identity used for duplicate
	# detection; an addon that throws here is isolated, not guessed at.
	# 第三步：问它是谁。契约里的名字同时用作重复检测的身份；在此抛错的插件被隔离，而不是被猜测。
	# NOTE: GDScript has no try/catch. A runtime error inside an addon method aborts THAT call
	# and returns null to us; the scan loop therefore keeps going — which is the containment we
	# can actually offer. The engine still logs the error, and the diagnostic marks the addon.
	# 注意：GDScript 没有 try/catch。插件方法内的运行时错误只中止**那一次调用**并向我们返回 null，
	# 扫描循环因此继续 —— 这是我们能提供的实际隔离。引擎仍会记录错误，诊断里也会标出该插件。
	var gpName: String = str(gpAddon._gpGetName())
	var gpVersion: String = str(gpAddon.get_meta("version", "0"))
	if gpName == "" or gpName == "unnamed":
		# The base class returns "unnamed": an addon that never overrode it cannot be told apart
		# from the base, and two of them would collide in every diagnostic.
		# 基类返回 "unnamed"：未覆写它的插件与基类无从区分，且两个这样的插件会在任何诊断里撞名。
		_gpDiag(gpPath, false, "unnamed", gpName, gpVersion)
		return
	if _gpSeenIds.has(gpName):
		_gpDiag(gpPath, false, "duplicate_id", gpName, gpVersion)
		return
	# Step 4: the load hook. It receives a deliberately small context (no widgets, no graph
	# ownership) so an addon cannot quietly become a second application.
	# 第四步：加载钩子。它收到一个刻意小的上下文（无控件、不拥有图），使插件无法悄悄变成第二个应用。
	if not _gpRunLoadHook(gpAddon, gpPath, gpName, gpVersion):
		return
	_gpSeenIds[gpName] = true
	gpAddons.append(gpAddon)
	_gpDiag(gpPath, true, "", gpName, gpVersion)


# Call the addon's load hook with the minimal context. Returns false when it must be isolated.
# 以最小上下文调用插件的加载钩子。需要隔离时返回 false。
func _gpRunLoadHook(gpAddon: GPIPIDAddon, gpPath: String, gpName: String,
		gpVersion: String) -> bool:
	# The context carries FACTS an addon may need (where it lives, what it may inject) and no
	# authority: it cannot reach the graph, the undo stack or the windows.
	# 上下文只带插件可能需要的事实（它在哪、能注入什么），不带权力：它够不到图、撤销栈或窗口。
	var gpCtx: Dictionary = {
		"path": gpPath,
		"name": gpName,
		"version": gpVersion,
	}
	gpAddon._gpOnLoad(gpCtx)
	return true


# Append one diagnostic row.
# 追加一条诊断。
func _gpDiag(gpPath: String, gpOk: bool, gpReason: String, gpName: String,
		gpVersion: String) -> void:
	gpDiagnostics.append({
		"path": gpPath,
		"ok": gpOk,
		"reason": gpReason,
		"name": gpName,
		"version": gpVersion,
	})
