extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Architecture guard (ADR-10 / ADR-12 / ADR-13): the shape of the codebase, not its behaviour.
# 架构守卫（ADR-10 / ADR-12 / ADR-13）：守的是"代码形状"，不是行为。
#
# WHY THIS FILE WAS REWRITTEN (W12 review, 2026-11-06)
# The previous version was a hardcoded blacklist of 7 render class names scanned only under
# src/core. It could not see the classes that actually leaked (GPLinetypeManager, GPGraphBinder,
# GPLabelGripOps), it never looked at autoload singletons or at FileAccess outside src/io, and
# an empty scan passed silently. Consequence: gate 2 was green (10,386 assertions) while 24
# boundary violations were live. A guard that cannot fail is not a guard.
# 为什么重写：旧版是"7 个 render 类名黑名单 + 只扫 src/core"，抓不到真正越界的类
# （GPLinetypeManager / GPGraphBinder / GPLabelGripOps），也从不检查 autoload 单例和 src/io 之外的
# FileAccess；且扫描为空时静默通过。后果是门 2 全绿（10,386 断言）同时 24 处边界违规在线。
# 一个不可能失败的守卫等于没有守卫。
#
# HOW IT WORKS NOW
# 1. Auto-enumerate: every `class_name` under src/ is indexed with its layer, and the autoload
#    singleton names are parsed from project.godot — nothing is hardcoded, so new files are
#    covered the day they are added.
# 2. Layer matrix: GP_LAYER_ALLOWED is the single source of truth for legal arrows
#    (ui → {app, addons, autoload, core, io, render, ui}; app → {addons, core, io}; addons → core;
#    render → core; io → core; core → core).
# 3. Four detectors: class references, res:// path references, autoload singleton touches,
#    FileAccess/DirAccess outside src/io.
# 4. Known-violation registry: the violations that exist today are pinned by exact key. A NEW
#    violation fails the gate; a FIXED one also fails it until its entry is deleted, so the list
#    can only shrink. GP_KNOWN_VIOLATION_CEILING hard-caps the count.
# 5. Injection self-tests: synthetic code is fed through the same detectors, so the gate proves
#    it can actually turn red.
# 现在的做法：
# 1. 自动枚举：src/ 下每个 class_name 连同所属层建立索引，autoload 单例名从 project.godot 解析，
#    全部不硬编码 —— 新增文件当天即在覆盖范围内。
# 2. 层矩阵：GP_LAYER_ALLOWED 是"合法箭头"的唯一事实源。
# 3. 四个检测器：类引用、res:// 路径引用、autoload 单例触碰、src/io 之外的 FileAccess/DirAccess。
# 4. 已知违规登记：当前存量按精确键登记。**新增**违规直接转红；**修好**的违规也转红，直到删除
#    对应条目 —— 因此清单只能缩短。GP_KNOWN_VIOLATION_CEILING 硬性封顶。
# 5. 注入自测：合成代码走同一批检测器，证明这道门确实能转红。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_SRC_ROOT: String = "res://src"
const GP_PROJECT_FILE: String = "res://project.godot"

# Legal dependency arrows. First element of each list is the layer itself (intra-layer is free).
# 合法依赖箭头。每个列表首元素为自身层（层内自由）。
const GP_LAYER_ALLOWED: Dictionary = {
	"core": ["core"],
	"io": ["core", "io"],
	"addons": ["addons", "core"],
	"app": ["app", "addons", "core", "io"],
	"render": ["core", "render"],
	"autoload": ["autoload", "core", "io"],
	"ui": ["addons", "app", "autoload", "core", "io", "render", "ui"],
}

# Autoload singletons are scene-tree globals: only the ui layer (and autoload itself) may touch them.
# autoload 单例是场景树全局对象：只有 ui 层（及 autoload 自身）可以触碰。
const GP_AUTOLOAD_FREE_LAYERS: Array[String] = ["autoload", "ui"]

# The io layer is the only place allowed to open a file or walk a directory (ADR-2 / ADR-4).
# 只有 io 层可以打开文件或遍历目录（ADR-2 / ADR-4）。
const GP_IO_OWNER_LAYER: String = "io"
const GP_IO_SYMBOLS: Array[String] = ["DirAccess", "FileAccess"]

# EMPTY SINCE 2026-11-06 (phase 1). The W12 review opened with 24 registered leaks; every one is
# now fixed, so this list must stay empty. An entry here is a debt note, not a permit — the
# registry test fails both when a NEW leak appears and when a listed one is fixed but not pruned.
# 自 2026-11-06（阶段 1）起为**空**。W12 审查开局登记 24 条渗漏，现已全部修好，故本表必须保持为空。
# 这里的条目是欠账记录，不是许可证 —— 出现**新**渗漏会失败，修好了却没删条目同样会失败。
# DELETE an entry the moment you fix it — the registry test fails on stale entries on purpose.
# If you are tempted to ADD one here, that is the architecture telling you "no".
# 2026-11-06（W12 审查）时点存在的违规。键 = "<kind>|<相对项目根路径>|<符号>"。
# 修好一条就**立刻删除**对应条目 —— 守卫对"陈旧条目"会故意报错。
# 如果你正想往这里**加**一条，那正是架构在对你说"不行"。
const GP_KNOWN_ARCH_VIOLATIONS: Array[String] = []

# Hard ceiling: this number may only go DOWN. Raising it is a review-level decision, not an edit.
# 硬性上限：该数字只可**下降**。上调属于评审级决定，不是顺手改个数字。
const GP_KNOWN_VIOLATION_CEILING: int = 0

# Floors: if the scanner ever breaks (wrong root, unreadable files) it would report zero violations
# and pass. These floors make an empty scan a failure instead of a green light.
# 下限：若扫描器坏掉（根路径错、文件读不到），它会报 0 违规并通过。下列下限把"空扫描"变成失败。
const GP_MIN_FILES: int = 270
const GP_MIN_CLASSES: int = 260
const GP_MIN_ALLOWED_REFS: int = 5000

const GP_IDENT_PATTERN: String = "(?<![\\w.])([A-Za-z_]\\w*)"
const GP_PATH_PATTERN: String = "res://src/([A-Za-z_]+)/[\\w/]+\\.gd"
const GP_AUTOLOAD_PATTERN: String = "^([A-Za-z_]\\w*)\\s*=\\s*\"\\*res://"

# Cross-object private access: `<SomeClass>._gpMember` where SomeClass is declared in a
# DIFFERENT file. ADR-10 forbids it — a private helper belongs to its owner, and an outside
# caller turns a local rename into a silent breakage that no behaviour test can see.
# The pattern demands a CAPITALISED class prefix on purpose: `gpTool._gpFoo` is a lowercase
# variable and stays somebody else's business.
# 跨对象私有访问：`<别的类>._gp成员`，且该类声明在**另一个文件**里。ADR-10 明令禁止 ——
# 私有辅助属于其所有者，外部调用方会让一次局部改名变成静默破坏，行为测试也看不见。
# 模式**故意**要求大写类名前缀：`gpTool._gpFoo` 是小写变量，不属本检测器管辖。
const GP_PRIVATE_REF_PATTERN: String = "(?<![\\w.])([A-Z][A-Za-z0-9_]*)\\.(_gp[A-Za-z0-9_]*)"

# Instance form: `<lowercase receiver>._gpMember`. Text alone cannot say what the receiver IS,
# so the receiver's declared type is resolved from `var <name>: <GPClass>` in the same file.
# Only GP*-typed receivers are judged: untyped (Variant) and built-in-typed ones are out of
# scope by design — guessing there would produce false positives nobody would maintain.
# 实例形态：`<小写接收者>._gp成员`。光看文本无法知道接收者是什么，故从同文件的
# `var <名字>: <GP类>` 解析其声明类型。只判 `GP*` 类型：未标注类型（Variant）与内建类型
# 的接收者**设计上**不判 —— 靠猜只会产出没人愿意维护的误报。
const GP_PRIVATE_INST_PATTERN: String = "(?<![\\w.])([a-z_][A-Za-z0-9_]*)\\.(_gp[A-Za-z0-9_]*)"
const GP_LOCAL_TYPE_PATTERN: String = "(?<![\\w.])var\\s+([a-z_][A-Za-z0-9_]*)\\s*:\\s*(GP[A-Za-z0-9_]*)"

# class_name is declared within the header; the latest in the tree is line 28 (place_tool.gd),
# so 40 lines is headroom without paying for a full-file scan on every gate run.
# class_name 声明在文件头部；全树最晚出现在第 28 行（place_tool.gd），取 40 行留余量，
# 同时避免每次门禁全文件扫描。
const GP_HEADER_LINES: int = 40


# ============================================================================
# Text preprocessing — line counts MUST be preserved so reported line numbers stay true.
# 文本预处理 —— **必须**保持行数不变，否则报出的行号就是假的（旧版正是在这里出错）。
# ============================================================================

# Remove comments while respecting string literals; keeps every newline.
# 剥离注释并识别字符串字面量；保留全部换行。
# Body of ONE function: from its `func <name>(` line up to the next column-0 `func `.
# 单个函数的函数体：从其 `func <name>(` 行到下一个顶格 `func ` 之前。
func _gpFuncBody(gpText: String, gpName: String) -> String:
	var gpStart: int = gpText.find("\nfunc " + gpName + "(")
	if gpStart < 0:
		return ""
	var gpRest: String = gpText.substr(gpStart + 1)
	var gpNext: int = gpRest.find("\nfunc ", 1)
	if gpNext < 0:
		return gpRest
	return gpRest.substr(0, gpNext)


func _gpStripComments(gpText: String) -> String:
	var gpOut: PackedStringArray = PackedStringArray()
	for gpLine in gpText.split("\n"):
		if not gpLine.contains("#"):
			gpOut.append(gpLine)
			continue
		gpOut.append(_gpStripOneLine(gpLine))
	return "\n".join(gpOut)


# Map every `<name>` declared as `var <name>: GP<Type>` to that type. Scope is NOT modelled:
# a file-wide table is enough, because one name reused with two types in one file is a
# readability problem long before it is a parsing problem.
# 把 `var <名字>: GP<类型>` 的声明映射到类型。**不**建模作用域：文件级的表足够 ——
# 同一文件里一个名字复用两种类型，先是个可读性问题，其次才是解析问题。
func _gpLocalTypes(gpCode: String) -> Dictionary:
	var gpOut: Dictionary = {}
	for gpM in RegEx.create_from_string(GP_LOCAL_TYPE_PATTERN).search_all(gpCode):
		gpOut[gpM.get_string(1)] = gpM.get_string(2)
	return gpOut


func _gpStripOneLine(gpLine: String) -> String:
	var gpOut: String = ""
	var gpQuote: String = ""
	var gpI: int = 0
	var gpN: int = gpLine.length()
	while gpI < gpN:
		var gpCh: String = gpLine[gpI]
		if gpQuote != "":
			gpOut += gpCh
			if gpCh == "\\" and gpI + 1 < gpN:
				gpOut += gpLine[gpI + 1]
				gpI += 2
				continue
			if gpCh == gpQuote:
				gpQuote = ""
			gpI += 1
			continue
		if gpCh == "\"" or gpCh == "'":
			gpQuote = gpCh
			gpOut += gpCh
			gpI += 1
			continue
		if gpCh == "#":
			break
		gpOut += gpCh
		gpI += 1
	return gpOut


# Blank out string-literal contents so text inside a string is not mistaken for code.
# Example: `"settings.title": {"en": "Settings"}` must NOT count as an autoload touch.
# 把字符串字面量内容替换为空格，避免把字符串里的文本误判为代码。
# 例：`"settings.title": {"en": "Settings"}` 不应算作触碰 Settings 单例。
func _gpBlankStrings(gpLine: String) -> String:
	var gpOut: String = ""
	var gpQuote: String = ""
	var gpI: int = 0
	var gpN: int = gpLine.length()
	while gpI < gpN:
		var gpCh: String = gpLine[gpI]
		if gpQuote != "":
			if gpCh == "\\":
				gpI += 2
				continue
			if gpCh == gpQuote:
				gpQuote = ""
				gpOut += " "
			gpI += 1
			continue
		if gpCh == "\"" or gpCh == "'":
			gpQuote = gpCh
			gpI += 1
			continue
		gpOut += gpCh
		gpI += 1
	return gpOut


# ============================================================================
# Discovery — layer, class index, autoload names. Nothing hardcoded.
# 发现 —— 层、类索引、autoload 名单。全部不硬编码。
# ============================================================================

func _gpGdFiles(gpDir: String) -> Array[String]:
	var gpOut: Array[String] = []
	var gpDA: DirAccess = DirAccess.open(gpDir)
	if gpDA == null:
		return gpOut
	gpDA.list_dir_begin()
	var gpName: String = gpDA.get_next()
	while gpName != "":
		if gpName.begins_with("."):
			gpName = gpDA.get_next()
			continue
		var gpPath: String = gpDir.path_join(gpName)
		if gpDA.current_is_dir():
			gpOut.append_array(_gpGdFiles(gpPath))
		elif gpName.ends_with(".gd"):
			gpOut.append(gpPath)
		gpName = gpDA.get_next()
	gpDA.list_dir_end()
	gpOut.sort()
	return gpOut


# "res://src/core/model/edge_style.gd" -> "core"; a file sitting directly in src/ -> "root".
# "res://src/core/model/edge_style.gd" -> "core"；直接放在 src/ 下的文件 -> "root"。
func _gpLayerOf(gpPath: String) -> String:
	var gpRel: String = gpPath.trim_prefix(GP_SRC_ROOT + "/")
	var gpParts: PackedStringArray = gpRel.split("/")
	if gpParts.size() < 2:
		return "root"
	return gpParts[0]


# Registry keys use the path WITHOUT the res:// prefix so they read the same in a diff.
# 注册表键使用去掉 res:// 前缀的路径，便于在 diff 中阅读。
func _gpKeyPath(gpPath: String) -> String:
	return gpPath.trim_prefix("res://")


# class_name -> script path, for every script under src/.
# class_name is conventionally declared in the file header, so only the first GP_HEADER_LINES
# lines are inspected — scanning all 78k lines for it would cost seconds per gate run.
# 全 src/ 的 class_name -> 脚本路径映射。
# class_name 惯例声明在文件头部，因此只检查前 GP_HEADER_LINES 行 —— 全量扫描 78k 行会让每次门禁
# 多花几秒。
func _gpClassIndex() -> Dictionary:
	var gpIndex: Dictionary = {}
	for gpPath in _gpGdFiles(GP_SRC_ROOT):
		var gpLines: PackedStringArray = FileAccess.get_file_as_string(gpPath).split("\n")
		var gpLimit: int = mini(gpLines.size(), GP_HEADER_LINES)
		for gpI in range(gpLimit):
			var gpTrim: String = gpLines[gpI].strip_edges()
			if not gpTrim.begins_with("class_name"):
				continue
			var gpName: String = gpTrim.trim_prefix("class_name").strip_edges()
			if gpName.contains(" "):
				gpName = gpName.split(" ")[0]
			if gpName != "":
				gpIndex[gpName] = gpPath
	return gpIndex


# Parse [autoload] entries from project.godot: `Name="*res://src/autoload/settings.gd"`.
# 从 project.godot 的 [autoload] 段解析单例名。
func _gpAutoloadNames() -> Array[String]:
	var gpOut: Array[String] = []
	var gpText: String = FileAccess.get_file_as_string(GP_PROJECT_FILE)
	if gpText == "":
		return gpOut
	var gpRe: RegEx = RegEx.create_from_string(GP_AUTOLOAD_PATTERN)
	var gpInSection: bool = false
	for gpLine in gpText.split("\n"):
		var gpTrim: String = gpLine.strip_edges()
		if gpTrim.begins_with("["):
			gpInSection = gpTrim == "[autoload]"
			continue
		if not gpInSection or gpTrim == "":
			continue
		var gpM: RegExMatch = gpRe.search(gpTrim)
		if gpM != null:
			gpOut.append(gpM.get_string(1))
	gpOut.sort()
	return gpOut


# ============================================================================
# Scanners — pure functions over (path, text) so injection tests exercise the same code.
# 扫描器 —— 对 (路径, 文本) 的纯函数，注入自测走的正是同一份代码。
# ============================================================================

# Scan ONE file's text and return violation keys. Legal references are counted in gpStats["allowed"].
# 扫描单个文件文本并返回违规键；合法引用计入 gpStats["allowed"]。
func _gpScanText(gpPath: String, gpText: String, gpIndex: Dictionary,
		gpAutoload: Array[String], gpStats: Dictionary) -> Array[String]:
	var gpOut: Array[String] = []
	var gpLayer: String = _gpLayerOf(gpPath)
	var gpAllowRaw: Variant = GP_LAYER_ALLOWED.get(gpLayer, [gpLayer])
	var gpAllow: Array = gpAllowRaw if gpAllowRaw is Array else [gpLayer]
	var gpKey: String = _gpKeyPath(gpPath)
	var gpReIdent: RegEx = RegEx.create_from_string(GP_IDENT_PATTERN)
	var gpRePath: RegEx = RegEx.create_from_string(GP_PATH_PATTERN)
	var gpRePriv: RegEx = RegEx.create_from_string(GP_PRIVATE_REF_PATTERN)
	var gpRePrivInst: RegEx = RegEx.create_from_string(GP_PRIVATE_INST_PATTERN)
	var gpCode: String = _gpStripComments(gpText)
	var gpLocalTypes: Dictionary = _gpLocalTypes(gpCode)
	for gpLine in gpCode.split("\n"):
		if gpLine.strip_edges() == "":
			continue
		# --- class references (strings kept: a class name in a string is still coupling) ---
		# --- 类引用（保留字符串：写在字符串里的类名依然是耦合）---
		var gpTokens: Dictionary = {}
		for gpM in gpReIdent.search_all(gpLine):
			gpTokens[gpM.get_string(1)] = true
		for gpTok in gpTokens.keys():
			var gpTarget: String = str(gpIndex.get(gpTok, ""))
			if gpTarget == "" or gpTarget == gpPath:
				continue
			var gpTargetLayer: String = _gpLayerOf(gpTarget)
			if gpAllow.has(gpTargetLayer):
				gpStats["allowed"] = int(gpStats.get("allowed", 0)) + 1
			else:
				gpOut.append("class|%s|%s" % [gpKey, str(gpTok)])
		# --- res:// path references (preload / load by path) ---
		# --- res:// 路径引用（按路径 preload / load）---
		for gpM in gpRePath.search_all(gpLine):
			var gpPathLayer: String = gpM.get_string(1)
			if gpPathLayer == gpLayer or gpAllow.has(gpPathLayer):
				gpStats["allowed"] = int(gpStats.get("allowed", 0)) + 1
			else:
				gpOut.append("path|%s|%s" % [gpKey, gpM.get_string(0)])
		# --- private members of ANOTHER class (ADR-10: zero cross-object private calls) ---
		# --- 别的类的私有成员（ADR-10：零跨对象私有调用）---
		# A class may name its own privates with its own prefix (static factories do this);
		# only a DIFFERENT declaring file makes the access a boundary crossing.
		# 一个类可以用自己的类名访问自己的私有成员（静态工厂正是这么写的）；
		# 只有当声明类在**另一个文件**时，这次访问才算越界。
		for gpM in gpRePriv.search_all(gpLine):
			var gpOwner: String = gpM.get_string(1)
			if str(gpIndex.get(gpOwner, "")) != gpPath:
				gpOut.append("private|%s|%s.%s" % [gpKey, gpOwner, gpM.get_string(2)])
		# --- same rule, instance form: a TYPED receiver pointing at a foreign class ---
		# --- 同一条规则的实例形态：**已标注类型**的接收者指向外来类 ---
		# The key names the class being reached into, not the local variable: variable names
		# churn on every refactor, and a key that churns cannot carry a debt.
		# 键写的是**被伸手的那个类**，不是局部变量名：变量名每次重构都会变，
		# 而一个会变的键承载不了欠账。
		for gpM in gpRePrivInst.search_all(gpLine):
			var gpRecvType: String = str(gpLocalTypes.get(gpM.get_string(1), ""))
			if gpRecvType == "":
				continue
			if str(gpIndex.get(gpRecvType, "")) != gpPath:
				gpOut.append("private|%s|%s.%s" % [gpKey, gpRecvType, gpM.get_string(2)])

	var gpBlank: String = _gpBlankStrings(gpCode)
	var gpBlankTokens: Dictionary = {}
	for gpM in gpReIdent.search_all(gpBlank):
		gpBlankTokens[gpM.get_string(1)] = true

	# --- autoload singletons: direct name, or the scene-tree form "/root/<Name>" ---
	# --- autoload 单例：直接名，或场景树形式 "/root/<Name>" ---
	if not GP_AUTOLOAD_FREE_LAYERS.has(gpLayer):
		for gpName2 in gpAutoload:
			if gpBlankTokens.has(gpName2) or gpCode.contains("/root/" + gpName2):
				gpOut.append("autoload|%s|%s" % [gpKey, gpName2])

	# --- file access outside src/io ---
	# --- src/io 之外的文件访问 ---
	if gpLayer != GP_IO_OWNER_LAYER:
		for gpSym in GP_IO_SYMBOLS:
			if gpBlankTokens.has(gpSym):
				gpOut.append("io|%s|%s" % [gpKey, gpSym])

	var gpUniq: Array[String] = []
	for gpItem in gpOut:
		if not gpUniq.has(gpItem):
			gpUniq.append(gpItem)
	gpUniq.sort()
	return gpUniq


# Whole-tree scan. Returns {violations, files, classes, allowed}.
# 全树扫描。返回 {violations, files, classes, allowed}。
func _gpScanTree() -> Dictionary:
	var gpIndex: Dictionary = _gpClassIndex()
	var gpAutoload: Array[String] = _gpAutoloadNames()
	var gpStats: Dictionary = {"allowed": 0}
	var gpAll: Array[String] = []
	var gpFiles: Array[String] = _gpGdFiles(GP_SRC_ROOT)
	for gpPath in gpFiles:
		var gpText: String = FileAccess.get_file_as_string(gpPath)
		for gpKey in _gpScanText(gpPath, gpText, gpIndex, gpAutoload, gpStats):
			if not gpAll.has(gpKey):
				gpAll.append(gpKey)
	gpAll.sort()
	return {
		"violations": gpAll,
		"files": gpFiles.size(),
		"classes": gpIndex.size(),
		"allowed": int(gpStats.get("allowed", 0)),
	}


# ============================================================================
# THE GATE
# ============================================================================

# 1. No violation outside the registry. A new leak fails here with its exact key.
# 1. 注册表之外不得出现违规。新的渗漏会带着精确键在此转红。
func gpTestNoUnregisteredBoundaryViolation() -> void:
	var gpScan: Dictionary = _gpScanTree()
	var gpKnown: Array = GP_KNOWN_ARCH_VIOLATIONS
	var gpNew: Array[String] = []
	for gpKey in gpScan["violations"]:
		if not gpKnown.has(gpKey):
			gpNew.append(gpKey)
	gpEq(gpNew.size(), 0, "new boundary violations (add no entry — fix the code): "
		+ ", ".join(gpNew))


# 2. Every registry entry must still fire. Fixing code without pruning the registry fails here,
#    which is what makes the list monotonically shrinking instead of a permanent excuse list.
# 2. 每条登记项必须仍然成立。修好代码却没删条目会在此转红 —— 这正是"清单只减不增"的机制，
#    否则它会退化成一张永久免责清单。
func gpTestKnownViolationRegistryHasNoStaleEntry() -> void:
	var gpScan: Dictionary = _gpScanTree()
	var gpActual: Array = gpScan["violations"]
	var gpStale: Array[String] = []
	for gpKey in GP_KNOWN_ARCH_VIOLATIONS:
		if not gpActual.has(gpKey):
			gpStale.append(gpKey)
	gpEq(gpStale.size(), 0, "stale registry entries (the leak is gone — delete these): "
		+ ", ".join(gpStale))


# 3. The registry may only shrink.
# 3. 注册表只可缩短。
func gpTestKnownViolationCeiling() -> void:
	gpCheck(GP_KNOWN_ARCH_VIOLATIONS.size() <= GP_KNOWN_VIOLATION_CEILING,
		"registry size %d exceeds ceiling %d" % [GP_KNOWN_ARCH_VIOLATIONS.size(),
			GP_KNOWN_VIOLATION_CEILING])
	gpCheck(GP_KNOWN_VIOLATION_CEILING <= 0,
		"ceiling may only go down (0 after phase 1, was 24), found %d" % GP_KNOWN_VIOLATION_CEILING)


# 4. Anti-tautology: the scanner must actually see the tree. Without this, a broken root or an
#    unreadable file turns the guard into a rubber stamp.
# 4. 反自证：扫描器必须真的看到了整棵树。否则根路径写错或文件读不到，守卫就成了橡皮图章。
func gpTestScannerCoversWholeTree() -> void:
	var gpScan: Dictionary = _gpScanTree()
	gpCheck(int(gpScan["files"]) >= GP_MIN_FILES,
		"scanned %d files, floor %d" % [int(gpScan["files"]), GP_MIN_FILES])
	gpCheck(int(gpScan["classes"]) >= GP_MIN_CLASSES,
		"indexed %d class_name entries, floor %d" % [int(gpScan["classes"]), GP_MIN_CLASSES])
	gpCheck(int(gpScan["allowed"]) >= GP_MIN_ALLOWED_REFS,
		"counted %d legal cross-layer references, floor %d"
			% [int(gpScan["allowed"]), GP_MIN_ALLOWED_REFS])
	var gpAutoload: Array[String] = _gpAutoloadNames()
	gpEq(gpAutoload.size(), 3, "autoload names parsed from project.godot: "
		+ ", ".join(gpAutoload))


# 5. Injection: a synthetic core file naming a render class must be caught by the same scanner.
# 5. 注入：合成的 core 文件引用 render 类，必须被同一台扫描器抓到。
func gpTestDetectorCatchesInjectedLayerViolation() -> void:
	var gpIndex: Dictionary = _gpClassIndex()
	var gpAutoload: Array[String] = _gpAutoloadNames()
	var gpStats: Dictionary = {"allowed": 0}
	var gpBad: Array[String] = _gpScanText("res://src/core/_injected.gd",
		"var gpA: GPCanvas2D = null\nvar gpB: GPPIDGraph = null\n", gpIndex, gpAutoload, gpStats)
	gpCheck(gpBad.has("class|src/core/_injected.gd|GPCanvas2D"),
		"injected core→render reference is detected")
	gpCheck(not gpBad.has("class|src/core/_injected.gd|GPPIDGraph"),
		"a legal intra-layer reference is not flagged")
	gpCheck(int(gpStats["allowed"]) >= 1, "the legal reference is counted, not ignored")


# 6. Injection: autoload and io detectors must fire on code, and stay quiet on strings/comments.
# 6. 注入：autoload 与 io 检测器对代码必须触发，对字符串/注释必须保持沉默。
func gpTestDetectorCatchesInjectedAutoloadAndIo() -> void:
	var gpIndex: Dictionary = _gpClassIndex()
	var gpAutoload: Array[String] = _gpAutoloadNames()
	var gpStats: Dictionary = {"allowed": 0}
	var gpBad: Array[String] = _gpScanText("res://src/core/_injected.gd",
		"var gpT: String = I18n.gpTr(\"x\")\nvar gpF: bool = FileAccess.file_exists(\"p\")\n"
			+ "var gpN: Object = get_node_or_null(\"/root/Settings\")\n",
		gpIndex, gpAutoload, gpStats)
	gpCheck(gpBad.has("autoload|src/core/_injected.gd|I18n"), "injected I18n use is detected")
	gpCheck(gpBad.has("io|src/core/_injected.gd|FileAccess"), "injected FileAccess is detected")
	gpCheck(gpBad.has("autoload|src/core/_injected.gd|Settings"),
		"injected /root/Settings lookup is detected")
	var gpClean: Array[String] = _gpScanText("res://src/core/_injected.gd",
		"# I18n Settings FileAccess GPCanvas2D in a comment\nvar gpS: String = \"Settings\"\n"
			+ "var gpQ: String = \"i18n Settings SnapState\"\n",
		gpIndex, gpAutoload, gpStats)
	gpEq(gpClean.size(), 0, "comments and string literals are not treated as code: "
		+ ", ".join(gpClean))


# 7. Line numbers must stay true: the stripper preserves line count exactly.
# 7. 行号必须真实：剥离器严格保持行数不变（旧版在此出错，报出的行号是偏移的）。
func gpTestCommentStripperPreservesLineNumbers() -> void:
	var gpSrc: String = "a\n# comment\nb # trailing\n\"c # not a comment\"\n"
	gpEq(_gpStripComments(gpSrc).split("\n").size(), gpSrc.split("\n").size(),
		"stripping comments preserves the line count")
	gpCheck(_gpStripComments("\"c # keep\"").contains("#"),
		"a # inside a string literal survives")
	gpCheck(not _gpStripComments("b # drop").contains("drop"),
		"a # outside a string starts a comment")


# 8. The core layer is the innermost ring: it must not gain a NEW leak even though six registered
#    ones still exist (fix stage 1 is clearing them). Scoped to core so the failure message
#    points straight at the ring that matters most.
# 8. core 是内环：尽管仍有已登记渗漏（修复阶段 1 正在清理），它不得**新增**任何渗漏。
#    本测试把范围收窄到 core，让失败信息直指最关键的那一环。
func gpTestCoreLayerHasNoNewLeak() -> void:
	var gpScan: Dictionary = _gpScanTree()
	var gpKnownCore: Array[String] = []
	for gpKey in GP_KNOWN_ARCH_VIOLATIONS:
		if gpKey.contains("|src/core/"):
			gpKnownCore.append(gpKey)
	var gpActualCore: Array[String] = []
	for gpKey in gpScan["violations"]:
		if str(gpKey).contains("|src/core/"):
			gpActualCore.append(str(gpKey))
	var gpNew: Array[String] = []
	for gpKey in gpActualCore:
		if not gpKnownCore.has(gpKey):
			gpNew.append(gpKey)
	gpEq(gpNew.size(), 0, "new core-layer leaks: " + ", ".join(gpNew))
	gpCheck(gpKnownCore.size() <= 0,
		"core must have zero registered leaks (0 after phase 1, was 10), found %d"
			% gpKnownCore.size())


# ============================================================================
# Behavioural companions that used to live in this file — unchanged.
# 本文件原有的行为伴随测试 —— 保持不变。
# ============================================================================

# The actual consumer that used to reach up into render now reaches core geometry.
# 原先向上依赖 render 的消费者现在使用 core 几何。
func gpTestPrintModelUsesCoreGeometry() -> void:
	var gpText: String = FileAccess.get_file_as_string("res://src/core/view/print_model.gd")
	gpCheck(gpText.contains("GPSymbolGeometry"), "print_model references GPSymbolGeometry")
	gpCheck(not gpText.contains("GPSymbolPainter"), "print_model no longer names GPSymbolPainter")


# Behaviour is unchanged by the move: same box parsing and same fit-scale arithmetic.
# 搬迁不改变行为：同样的 box 解析与同样的 fit-scale 算法。
func gpTestSymbolGeometryBehaviour() -> void:
	var gpBox: Rect2 = GPSymbolGeometry.gpUnitBox({"box": [10, 20, 30, 40]})
	gpApprox(gpBox.position.x, 10.0, 0.001, "unit box x")
	gpApprox(gpBox.position.y, 20.0, 0.001, "unit box y")
	gpApprox(gpBox.size.x, 30.0, 0.001, "unit box w")
	gpApprox(gpBox.size.y, 40.0, 0.001, "unit box h")
	gpEq(GPSymbolGeometry.gpUnitBox({}), Rect2(Vector2.ZERO, Vector2(100, 100)),
		"no box falls back to 100x100")
	gpApprox(GPSymbolGeometry.gpFitScale(Rect2(Vector2.ZERO, Vector2(10, 5)),
		Vector2(100, 100)), 10.0, 0.001, "fit scale picks the tighter axis")


# D03: canvas-level UI edits must use the one emit path; the binder must have a revision
# criterion, not only reference equality.
# D03：画布级界面编辑必须走唯一发信号路径；绑定器必须有 revision 判据，而非仅引用相等。
func gpTestCanvasRefreshUsesRevisionPath() -> void:
	for gpPath in [
		"res://src/ui/canvas/annotation_editor.gd",
		"res://src/ui/canvas/edit_facade.gd",
		"res://src/ui/tools/grip_tool.gd",
		"res://src/ui/tools/select_tool.gd",
		"res://src/ui/tools/draw_shape_tool.gd",
	]:
		var gpText: String = FileAccess.get_file_as_string(gpPath)
		gpCheck(not gpText.contains("gpCv.gpGraphChanged.emit()"),
			"canvas edit uses the unified path: " + gpPath)
	var gpBinder: String = FileAccess.get_file_as_string("res://src/ui/canvas/graph_binder.gd")
	gpCheck(gpBinder.contains("gpRevision"), "the binder uses graph revision as a criterion")
	gpCheck(gpBinder.contains("gpRevisionChanged"), "the binder applies the revision change")


# ============================================================================
# Seam installation — a seam that nobody installs disables the feature SILENTLY. The W12 review
# found exactly that shape of bug (a zero-caller gpLoadFile that meant linetype overrides never
# worked), so every seam gets a pin at its composition root.
# 缝装配 —— 没人装配的缝会**静默**关闭功能。W12 审查发现的正是这种形状的缺陷（零调用方的
# gpLoadFile 使线型覆盖从未生效），故每条缝都在其组合根上有一颗钉。
# ============================================================================

# Symbol persistence: core may not open user://, so BOTH roots must install GPSymbolPackStore.
# 图元持久化：core 不可开 user://，故两个组合根都必须装入 GPSymbolPackStore。
func gpTestSymbolPackSeamInstalledAtEveryRoot() -> void:
	for gpPath in ["res://src/ui/shell/main_window.gd", "res://tools/gp_cli.gd"]:
		var gpText: String = FileAccess.get_file_as_string(gpPath)
		gpCheck(gpText.contains("GPSymbolPackStore.gpInstall()"),
			"persistence seam installed at the root: " + gpPath)
	# The library must ASK the seam rather than reach for a file itself.
	# 图元库必须**向缝要数据**，而不是自己去找文件。
	var gpLib: String = FileAccess.get_file_as_string("res://src/core/symbol/symbol_library.gd")
	gpCheck(gpLib.contains("_gpPackReader.is_valid()"), "symbol library reads through the seam")
	gpCheck(not gpLib.contains("FileAccess"), "symbol library no longer opens a file")
	gpCheck(not gpLib.contains("DirAccess"), "symbol library no longer walks a directory")


# UI font: the frame used to query the Settings autoload directly.
# UI 字体：图框原先直接查询 Settings 自动加载。
func gpTestUiFontSeamInstalled() -> void:
	var gpSettings: String = FileAccess.get_file_as_string("res://src/autoload/settings.gd")
	gpCheck(gpSettings.contains("GPFontSeam.gpSetUiFontResolver("),
		"settings installs the UI font seam")
	var gpFrame: String = FileAccess.get_file_as_string("res://src/render/frame_view.gd")
	gpCheck(gpFrame.contains("GPFontSeam.gpUiFont()"), "frame resolves its font through the seam")
	gpCheck(not gpFrame.contains("/root/Settings"), "frame no longer looks the autoload up by path")


# DRC report rendering must stay pure: the disk step lives in GPDRCReportFile (io).
# DRC 报告渲染必须保持纯：写盘一步在 GPDRCReportFile（io）。
func gpTestDrcReportHasNoDiskAccess() -> void:
	var gpText: String = FileAccess.get_file_as_string("res://src/core/validation/drc_report.gd")
	gpCheck(not gpText.contains("FileAccess"), "drc_report does not open a file")
	gpCheck(not gpText.contains("DirAccess"), "drc_report does not create a directory")
	gpCheck(gpText.contains("GPDRCReportFile"), "drc_report points at the io writer instead")


# ADR-4 has to hold for EVERY file the app writes, not only for *.pid.json. Before 2026-11-06 the
# gateway wrote in place, so symbol packs, the project standard, repair plans, both DRC reports and
# the BOM CSVs were silently outside the atomic guarantee — the archives were protected and the
# user's own content was not. This pin makes the single write path a fact rather than a convention.
# ADR-4 必须覆盖应用写出的**每个**文件，而不只是 *.pid.json。2026-11-06 之前网关是原地覆写，故图元包、
# 项目标准、修复计划、两份 DRC 报告与 BOM CSV 都静默落在原子保证之外 —— 存档受保护，用户自己的
# 内容没有。本钉把"唯一写入路径"变成事实而非约定。
func gpTestWritesGoThroughTheAtomicWriter() -> void:
	var gpAllowed: Array[String] = [
		"res://src/io/atomic_file.gd",
		# The one documented exception: gpLoad copies a res:// template into a user:// scratch
		# file that is deleted in the same call. Atomicity would only add artifacts to clean up.
		# 唯一例外：gpLoad 把 res:// 模板复制成 user:// 临时文件，并在同一次调用内删除；
		# 对它做原子写只会多出需要清理的产物。
		"res://src/io/xlsx/gp_xlsx_template.gd",
	]
	var gpOffenders: PackedStringArray = PackedStringArray()
	for gpPath in _gpGdFiles(GP_SRC_ROOT):
		if gpAllowed.has(gpPath):
			continue
		var gpText: String = _gpStripComments(FileAccess.get_file_as_string(gpPath))
		if gpText.contains("FileAccess.WRITE") or gpText.contains("FileAccess.READ_WRITE"):
			gpOffenders.append(_gpKeyPath(gpPath))
	gpCheck(gpOffenders.is_empty(),
		"only GPAtomicFile may open a file for writing; offenders: " + ", ".join(gpOffenders))
	var gpGateway: String = FileAccess.get_file_as_string("res://src/io/file_gateway.gd")
	gpCheck(gpGateway.contains("GPAtomicFile.gpWriteAtomic"),
		"the gateway must write through GPAtomicFile, not in place")


# ============================================================================
# S1 (2026-11-06): the cross-sheet domain left GPMainWindow. The cut was chosen by
# measurement, not by taste: 44 functions / 1,223 lines whose external surface was only
# gpCenter + gpInspector + a definition provider + a status sink, while all 12 pieces of
# private state (_gpRubber*, _gpDrag*, _gpCross*) were referenced ZERO times outside the
# block and no coordinator ever called back into it.
# S1（2026-11-06）：跨图纸域已离开 GPMainWindow。切这里靠**测量**而非偏好：44 函数 /
# 1,223 行，对外只有 gpCenter + gpInspector + 定义表提供者 + 状态栏接收端；12 份私有状态
#（_gpRubber* / _gpDrag* / _gpCross*）在块外被引用**零**次，也没有协调者反向调用它。
#
# WHY THIS PIN EXISTS / 为何需要这颗钉：
# The very move that produced this controller shipped a rename bug (a wrong string slice made
# gpnCrossSheetRequested out of gpOnCrossSheetRequested). Gate 2 stayed GREEN at 10,457/0
# because NO test drives these entry points — they are bound to canvas / inspector signals and
# only fire on a real gesture. Static pins are the only thing that would have caught it.
# 产出本控制器的那次搬迁本身就带出一个改名 bug（切片算错一位，把 gpOnCrossSheetRequested
# 变成 gpnCrossSheetRequested）。门 2 仍以 10,457/0 **全绿**，因为**没有**任何测试驱动这些
# 入口 —— 它们绑在画布 / 面板信号上，只有真实手势才会触发。静态钉是唯一能抓到它的东西。
# ============================================================================

# Entry points the canvas and the inspector bind to. A rename that forgets the wiring is
# silent: the signal simply never fires again.
# 画布与面板绑定的入口。改名却忘了改接线是**静默**的：信号从此不再触发。
const GP_CROSS_SHEET_ENTRY_POINTS: Array[String] = [
	"gpOnCrossSheetRequested", "gpOnJumpToPeer", "gpOnSyncToPeer", "gpOnCrossSheetDelete",
	"gpOnEdgeTagCommitted", "gpOnEdgeAttrsCommitted", "gpOnEdgeCreated",
	"gpOnCrossPaneDragUpdated", "gpOnCrossPaneDropped", "gpOnCrossPaneDragEnded",
	"gpOnPortLinkUpdated", "gpOnPortLinkDropped", "gpOnPortLinkEnded",
	"gpOnInspectorUnlink", "gpOnInspectorLinkDelete", "gpOnInspectorConnectPick",
	"gpEdgeInheritInfo", "gpOnEdgeInheritToggled",
]

# State that belongs to the controller alone; if any of it reappears in the root, the block
# is growing back.
# 只属于控制器的状态；任何一个在根类里重新出现，就说明那块正在长回来。
const GP_CROSS_SHEET_STATE: Array[String] = [
	"_gpOffPageDialog", "_gpCrossPending", "_gpCrossPreselect", "_gpDragHlCanvas",
	"_gpDragHlNode", "_gpFlashToken", "_gpRubber", "_gpRubberActive", "_gpRubberFrom",
	"_gpRubberTo", "_gpDragSrcCanvas", "_gpDragSrcNode",
]


func gpTestCrossSheetDomainStayedExtracted() -> void:
	var gpController: String = FileAccess.get_file_as_string(
		"res://src/ui/shell/cross_sheet_controller.gd")
	var gpHost: String = FileAccess.get_file_as_string("res://src/ui/shell/main_window.gd")
	gpCheck(gpController != "", "the cross-sheet controller exists")

	# 1) Every entry point is DEFINED on the controller and REACHED from a named wiring site.
	# Checked as a pair on purpose: a rename applied to one side only compiles fine and fails
	# silently. NB (S4): the second half used to read "the root binds it". That held only while
	# BOTH halves lived in the root; the per-canvas half now lives in gpWireCanvas(). NB (S5):
	# the panel half left the root too, so there are now THREE named wiring sites and the
	# check had to grow with them. The invariant was never "the root names it" — it was
	# "something actually connects it", and the S5 failure proved the point: the entry-point
	# list stayed right while five handlers were suddenly reached from nowhere this test
	# looked at.
	# 1) 每个入口都在控制器上**定义**、并被某个具名接线点**触达**。刻意成对检查：只改一侧的
	# 改名能通过编译，然后静默失效。注（S4）：后半原先写的是「根类绑定它」。那只在两半都在
	# 根类时成立；逐画布那一半现居 gpWireCanvas()。注（S5）：面板那一半也离开了根类，故具名
	# 接线点现有**三个**，检查必须跟着长大。真正的不变量从来不是「根类提到它」，而是「确实
	# 有东西把它连上了」—— S5 的失败正是证明：入口表仍是对的，而五个处理器突然从本测试
	# 所看的任何地方都触达不到了。
	var gpWire: String = _gpFuncBody(gpController, "gpWireCanvas")
	gpCheck(gpWire != "", "the per-canvas wiring method exists")
	var gpWirePanel: String = _gpFuncBody(gpController, "gpWireInspector")
	gpCheck(gpWirePanel != "", "the panel wiring method exists")
	for gpName in GP_CROSS_SHEET_ENTRY_POINTS:
		gpCheck(gpController.contains("func " + gpName + "("),
			"controller defines " + gpName)
		gpCheck(gpHost.contains("gpCrossSheet." + gpName) or gpWire.contains(gpName)
				or gpWirePanel.contains(gpName),
			"handler is reached from a named wiring site: " + gpName)

	# 2) The logic must NOT be re-declared in the root. This is the anti-backslide half.
	# 2) 逻辑不得在根类里重新声明。这是防回流的另一半。
	for gpName in GP_CROSS_SHEET_ENTRY_POINTS:
		gpCheck(not gpHost.contains("func " + gpName + "("),
			"root no longer defines " + gpName)
	for gpVar in GP_CROSS_SHEET_STATE:
		gpCheck(not gpHost.contains(gpVar),
			"cross-sheet state stays out of the root: " + gpVar)

	# 3) Assembly is a NAMED call, and every dependency is injected. A controller that is
	# built but not injected fails silently — the same shape as an uninstalled seam.
	# 3) 装配是一个**具名**调用，且四项依赖都被注入。建了却不注入是静默失效 ——
	# 与「缝没装」同形。
	gpCheck(gpHost.contains("func _gpAssembleCrossSheet()"),
		"assembly helper exists")
	gpCheck(gpHost.contains("_gpAssembleCrossSheet()"),
		"assembly helper is actually called")
	for gpInject in ["gpCrossSheet.gpCenter =", "gpCrossSheet.gpInspector =",
			"gpCrossSheet.gpDefsProvider =", "gpCrossSheet.gpStateSink ="]:
		gpCheck(gpHost.contains(gpInject), "root injects " + gpInject)

	# 4) The definition table is passed as a Callable, never captured. gpDefs is reassigned
	# six times at runtime (project import / symbol delete); a captured array would go stale
	# and the peer-sheet dropdown would list wrong symbol names with no test turning red.
	# 4) 定义表以 Callable 传入、绝不捕获。gpDefs 在运行期被重新赋值六次（导入工程 / 删图元）；
	# 捕获数组会过期，使对端下拉列出错误图元名，且没有测试会红。
	gpCheck(gpController.contains("gpDefsProvider: Callable"),
		"controller receives the definition table as a Callable")
	gpCheck(gpController.contains("gpDefsProvider.call()"),
		"controller resolves the table on every call instead of caching it")
	gpCheck(not gpController.contains("var gpDefs: Array[GPSymbolDef]"),
		"controller does not keep its own copy of the table")

# ============================================================================
# S2 (2026-11-06): the coordinators got a CONTRACT instead of the whole root.
# S2（2026-11-06）：协调者拿到的是**契约**，不再是整个根类。
#
# WHY THIS PIN EXISTS / 为何需要这颗钉：
# `var gpHost: GPMainWindow` said "you may touch anything", and 44 distinct members were reached
# through it with nothing distinguishing contract from accident. Seven coordinators × one lazy
# reach each is how a 2,472-line root grew: every sibling need added a three-line relay to it.
# The fix is a narrow type — `gpHost: GPShellHost` — which turns an undeclared reach into a
# PARSE ERROR at gate 5 instead of a code-review miss. These pins keep that type narrow:
# (a) nobody may name the root again, (b) the contract may not absorb root-only furniture
# ("just add it here" is always the tempting fix), (c) the root may not take the relays back.
# `var gpHost: GPMainWindow` 等于说「你什么都能碰」，经它触达 44 个不同成员，而没有东西区分契约
# 与顺手拿的。七个协调者各偷懒一次，就是 2,472 行根类的长法：每次兄弟需求都往根类加三行中继。
# 修法是窄类型 `gpHost: GPShellHost` —— 未声明的伸手在门 5 变成**解析错误**，而不是评审疏忽。
# 以下三组钉让那个类型保持窄：(a) 任何人不得再写根类名；(b) 契约不得吞下根类私有陈设
#（「就加在这里」永远是最诱人的修法）；(c) 根类不得把中继收回去。
# ============================================================================

const GP_SHELL_HOST_PATH: String = "res://src/ui/shell/shell_host.gd"
const GP_SHELL_ROOT_PATH: String = "res://src/ui/shell/main_window.gd"

# Furniture that only ONE class touches. A name moving into the contract means the contract is
# turning into a second god-object.
# 只有**某一个**类碰的陈设。谁的名字跑进契约，就说明契约正在变成第二个上帝对象。
#
# NB / 注：the DRC four (gpPanel / gpDialog / gpScheduler / gpOverlay) are NOT listed here and not
# listed by their old names either. They moved into GPDrcPresenter in S3, so their old names
# (gpDrcPanel / gpDrcDialog / gpRuleScheduler / gpRuleOverlay) no longer exist anywhere — keeping
# them would have been four assertions that can never fail. The S3 pin now guards the same four
# furniture pieces under their REAL names, at both ends (contract and root).
# DRC 那四件（gpPanel / gpDialog / gpScheduler / gpOverlay）不在此表，也不按旧名在此表。它们在 S3
# 搬进了 GPDrcPresenter，旧名（gpDrcPanel / gpDrcDialog / gpRuleScheduler / gpRuleOverlay）已不存在
# 于任何文件 —— 留着它们就是四条**永远不会失败**的断言。S3 的钉现按**真名**在同一张表的两头
#（契约与根类）守住这四件陈设。
const GP_SHELL_ROOT_ONLY: Array[String] = [
	"gpRightDock", "gpOutline", "gpBackpack", "gpCrossSheet", "gpRibbonCoord",
	"gpLayoutCoord", "gpDocLabel",
]

# Hooks the ROOT implements. S3 removed the last two stubs (gpRunDrc / gpShowDrcDialog are relays
# now), so exactly one remains — and it has a `pass` default rather than a push_error hole.
# **根类**实现的钩子。S3 移除了最后两个空体（gpRunDrc / gpShowDrcDialog 现在是中继），
# 故只剩一个 —— 且它是默认 `pass` 的钩子，不是 push_error 的洞。
const GP_SHELL_ROOT_PORTS: Array[String] = [
	"gpOnSelectionMirrored",
]

# Relays that used to be three-line copies in the root. If any of them is defined in the root
# again, the copies are growing back.
# 原先在根类里以三行拷贝形式存在的中继。任何一个重新出现在根类，就说明拷贝正在长回来。
const GP_SHELL_RELAYS: Array[String] = [
	"gpSetState", "gpDefFor", "gpNodeFor", "gpActiveCanvas", "gpActiveGraph",
	"gpRefreshSelection", "gpSyncInspectorDefs", "gpReconcileLibraryDrift",
	"gpMenuUndo", "gpMenuRedo", "gpOpenSettings", "gpDeleteSelected",
	"gpRunDrc", "gpShowDrcDialog",
]

# Inherited from Control / Object; not part of the contract and never will be.
# 继承自 Control / Object；不属于契约、也永远不会属于。
const GP_SHELL_INHERITED: Array[String] = [
	"add_child", "get_node_or_null", "get_tree", "get_window",
]


func gpTestCoordinatorsTalkOnlyToTheShellContract() -> void:
	var gpHostText: String = FileAccess.get_file_as_string(GP_SHELL_HOST_PATH)
	var gpRootText: String = FileAccess.get_file_as_string(GP_SHELL_ROOT_PATH)
	gpCheck(gpHostText != "", "the shell contract exists")
	gpCheck(gpRootText.contains("extends GPShellHost"),
		"the scene root extends the shell contract")

	# 1) Declared surface of the contract.
	# 1) 契约声明的成员面。
	var gpDeclared: Dictionary = {}
	var gpDeclRe: RegEx = RegEx.create_from_string("^(?:var|func|const) ([A-Za-z_]\\w*)")
	for gpLine in gpHostText.split("\n"):
		var gpM: RegExMatch = gpDeclRe.search(gpLine)
		if gpM != null:
			gpDeclared[gpM.get_string(1)] = true

	# 2) No coordinator may name the root, and each must declare the narrow type. A single
	# re-typed coordinator is enough to reopen the door, so this is checked per file.
	# 2) 任何协调者都不得写根类名，且都必须声明窄类型。一个协调者改回宽类型就足以重开这扇门，
	# 故逐文件检查。
	var gpUseRe: RegEx = RegEx.create_from_string("gpHost\\.([A-Za-z_]\\w*)")
	var gpOffenders: PackedStringArray = PackedStringArray()
	# NB: selected by CONTENT ("does this file hold a gpHost?"), not by file name — a future
	# *_controller.gd that takes a host must not slip past a name-based filter.
	# 注意：按**内容**选取（「本文件是否持有 gpHost」），不按文件名 —— 将来某个持有宿主的
	# *_controller.gd 不能因为名字不同就溜过去。
	for gpPath in _gpGdFiles("res://src/ui/shell"):
		if gpPath == GP_SHELL_HOST_PATH or gpPath == GP_SHELL_ROOT_PATH:
			continue
		var gpText: String = _gpStripComments(FileAccess.get_file_as_string(gpPath))
		if not gpText.contains("gpHost"):
			continue
		var gpBase: String = gpPath.get_file()
		gpCheck(gpText.contains("var gpHost: GPShellHost = null"),
			gpBase + " types its host as the contract")
		gpCheck(not gpText.contains("GPMainWindow"),
			gpBase + " never names the scene root")
		for gpM in gpUseRe.search_all(gpText):
			var gpName: String = gpM.get_string(1)
			if not gpDeclared.has(gpName) and not GP_SHELL_INHERITED.has(gpName):
				gpOffenders.append(gpBase + ":" + gpName)
	gpCheck(gpOffenders.is_empty(),
		"every gpHost reach is declared by the contract; offenders: " + ", ".join(gpOffenders))

	# 3) Anti-widening: root-only furniture must NOT appear in the contract.
	# 3) 防扩张：根类私有陈设**不得**出现在契约里。
	for gpName in GP_SHELL_ROOT_ONLY:
		gpCheck(not gpDeclared.has(gpName),
			"root-only member stays out of the contract: " + gpName)

	# 4) The root implements the one hook that is left, and the contract holds NO stubs. A stub
	# is only honest while somebody really overrides it; once the last override moves out, the
	# stub is a runtime error waiting for a menu click. S3 removed the last two.
	# 4) 根类实现仅剩的那个钩子，且契约里**没有**任何空体。空体只在确实有人覆写时才诚实；
	# 最后一个覆写搬走之后，空体就是一个等着菜单点击触发的运行期错误。S3 移除了最后两个。
	for gpName in GP_SHELL_ROOT_PORTS:
		gpCheck(gpRootText.contains("func " + gpName + "("),
			"root implements the hook " + gpName)
	gpCheck(gpHostText.count("push_error(\"GPShellHost.") == 0,
		"the contract declares no unimplemented stub")

	# 5) Anti-backslide: the relays did not sneak back into the root.
	# 5) 防回流：中继没有溜回根类。
	for gpName in GP_SHELL_RELAYS:
		gpCheck(not gpRootText.contains("func " + gpName + "("),
			"relay stays in the contract, not the root: " + gpName)


# ============================================================================
# S3 (2026-11-06): the DRC presentation domain left the root.
# S3（2026-11-06）：DRC 呈现域离开根类。
#
# WHY THIS PIN EXISTS / 为何需要这颗钉：
# S3 was a MOVE, and moves break in two silent ways. (a) A renamed entry point: the panel still
# builds, the menu still opens, but the badge never appears — no test drives a finding through
# the overlay. (b) A lost assembly call with a WRONG ORDER: gpCreateRuntime() MUST run before the
# first sheet (its canvas-ready binds the scheduler) and gpCreatePanel() MUST run after both the
# first sheet and the outline (it binds the ACTIVE canvas, and the right dock must keep DRC as
# `count - 2 + 1`). Neither failure turns gate 2 red on its own — the app still starts, just
# quieter than before.
# S3 是一次**搬迁**，而搬迁以两种静默方式出问题。(a) 入口改名：面板照样构建、菜单照样打开，
# 但角标再不出现 —— 没有任何测试把一条发现送过覆盖层。(b) 装配调用丢失或**顺序**错：
# gpCreateRuntime() 必须在首张图纸之前（其 canvas-ready 要绑调度器），gpCreatePanel() 必须在首张
# 图纸**与大纲**之后（它要绑**活动**画布，且右栏必须让 DRC 保持为 `count - 2 + 1`）。
# 两种失效都不会自己让门 2 变红 —— 程序照样启动，只是比以前安静。
# ============================================================================

const GP_DRC_PRESENTER_PATH: String = "res://src/ui/shell/drc_presenter.gd"

# Furniture the presenter owns. In the contract = the shell leaks a panel; in the root = the
# block is growing back.
# 呈现器持有的陈设。出现在契约里＝外壳在漏面板；出现在根类里＝那块正在长回来。
const GP_DRC_FURNITURE: Array[String] = [
	"gpPanel", "gpDialog", "gpScheduler", "gpOverlay",
]

# Public entries the root and the contract call. A rename on ONE side compiles and then does
# nothing — the failure mode S1 shipped with gpnCrossSheetRequested.
# 根类与契约调用的公开入口。只改一侧的改名能编译，然后什么也不做 —— S1 曾以
# gpnCrossSheetRequested 交付过的失效形态。
const GP_DRC_ENTRY_POINTS: Array[String] = [
	"gpCreateRuntime", "gpCreatePanel", "gpOnCanvasReady", "gpOnActiveSheetChanged",
	"gpBindActive", "gpRun", "gpShowDialog", "gpRefreshText",
]


func gpTestDrcPresentationStayedExtracted() -> void:
	var gpPresenter: String = _gpStripComments(
		FileAccess.get_file_as_string(GP_DRC_PRESENTER_PATH))
	var gpRoot: String = _gpStripComments(FileAccess.get_file_as_string(GP_SHELL_ROOT_PATH))
	var gpContract: String = _gpStripComments(FileAccess.get_file_as_string(GP_SHELL_HOST_PATH))
	gpCheck(gpPresenter != "", "the DRC presenter exists")

	# 1) Defined on the presenter, reached from the caller. Paired checks, never one-sided.
	# 1) 在呈现器上**定义**、由调用方**触达**。成对检查，绝不只看一侧。
	for gpName in GP_DRC_ENTRY_POINTS:
		gpCheck(gpPresenter.contains("func " + gpName + "("),
			"presenter defines " + gpName)
	for gpCall in ["gpDrc.gpCreateRuntime()", "gpDrc.gpCreatePanel()", "gpDrc.gpOnCanvasReady(",
			"gpDrc.gpOnActiveSheetChanged()", "gpDrc.gpBindActive()", "gpDrc.gpRefreshText()"]:
		gpCheck(gpRoot.contains(gpCall), "root calls " + gpCall)
	for gpCall in ["gpDrc.gpRun()", "gpDrc.gpShowDialog()"]:
		gpCheck(gpContract.contains(gpCall), "the contract relays " + gpCall)

	# 2) Anti-backslide: no DRC function and no DRC furniture may reappear in the root.
	# 2) 防回流：DRC 函数与陈设都不得在根类里重新出现。
	for gpName in ["gpRunDrc", "gpShowDrcDialog", "_gpBindDrc", "_gpFocusFinding",
			"_gpOnLiveDrc", "_gpIsSheetFurnitureFinding", "_gpActiveSheetId"]:
		gpCheck(not gpRoot.contains("func " + gpName + "("),
			"root no longer defines " + gpName)
	for gpName in GP_DRC_FURNITURE:
		gpCheck(not gpRoot.contains(gpName),
			"DRC furniture stays out of the root: " + gpName)
		gpCheck(not gpContract.contains(gpName),
			"DRC furniture stays out of the contract: " + gpName)

	# 3) The presenter never reaches back into the shell: no host field, no scene root, no
	# coordinator. It is injected with four values and talks to nothing else.
	# 3) 呈现器绝不回指外壳：无 host 字段、无根类名、无协调者。它只被注入四个值，别的都不碰。
	for gpForbidden in ["GPMainWindow", "gpHost", "GPMenuCoordinator", "GPFileCoordinator"]:
		gpCheck(not gpPresenter.contains(gpForbidden),
			"presenter never names " + gpForbidden)

	# 4) Two-phase assembly, checked by POSITION inside the two functions. Both orders compile and
	# both start; one just leaves the panel unbound, or the outline wearing the DRC title.
	# 4) 两步装配，按两个函数内的**相对位置**检查。两种顺序都能编译、都能启动 ——
	# 只是一个会让面板未绑定，或让大纲戴上 DRC 的标题。
	var gpCenterStart: int = gpRoot.find("func _gpAssembleCenter(")
	gpCheck(gpCenterStart >= 0, "the center assembly step exists")
	var gpCenterBody: String = gpRoot.substr(gpCenterStart)
	gpCenterBody = gpCenterBody.substr(0, gpCenterBody.find("func _gpAssemblePalette("))
	gpCheck(gpCenterBody.contains("_gpAssembleDrc()"),
		"the runtime is assembled inside the center step")
	gpCheck(gpCenterBody.find("_gpAssembleDrc()") < gpCenterBody.find("gpAddTab()"),
		"the runtime is assembled BEFORE the first sheet")

	var gpReadyStart: int = gpRoot.find("func _ready(")
	gpCheck(gpReadyStart >= 0, "the ready handler exists")
	var gpReadyBody: String = gpRoot.substr(gpReadyStart)
	gpReadyBody = gpReadyBody.substr(0, gpReadyBody.find("func _gpAssembleCoordinators("))
	gpCheck(gpReadyBody.find("_gpAssembleDrcPanel()") > gpReadyBody.find("_gpAssembleCenter()"),
		"the dock panel is assembled AFTER the first sheet")
	gpCheck(gpReadyBody.find("_gpAssembleDrcPanel()") > gpReadyBody.find("_gpAssembleOutline()"),
		"the dock panel is assembled AFTER the outline tab (it must stay last)")


# ============================================================================
# S4 (2026-11-06): the cross-sheet WIRING moved next to its handlers.
# S4（2026-11-06）：跨图纸**接线**搬到了它的处理器旁边。
#
# WHY THIS PIN EXISTS / 为何需要这颗钉：
# S1 extracted the cross-sheet domain out of the root but left the 63 lines of per-canvas
# wiring behind. It compiled, it passed, and it was wrong in a way nothing could see: a new
# gesture had to be registered in the one function that already held 22 connects for six
# unrelated owners, and forgetting one produces no error at all — the gesture simply stops
# answering on sheet 2 and every sheet after it. The fix is a named method, and this pin keeps
# the two halves honest: every signal wired exactly there, and the view-level signal names
# never creeping back into the root.
# S1 把跨图纸域抽出了根类，却把 63 行逐画布接线留在了原处。它能编译、能通过，错得没人看得见：
# 新加一个手势必须登记在**那一个**已经为六个不相干主人持有 22 条连接的函数里，而漏掉一条
# 完全不报错 —— 手势在第二张及之后的图纸上单纯不再响应。修法是具名方法；这颗钉让两半都老实：
# 每个信号只在那里接，而视图级信号名不得溜回根类。
# ============================================================================

const GP_CROSS_SHEET_CONTROLLER_PATH: String = "res://src/ui/shell/cross_sheet_controller.gd"
const GP_CANVAS_PATH: String = "res://src/ui/canvas/canvas_2d.gd"
const GP_EDIT_SERVICE_PATH: String = "res://src/app/edit_service.gd"

# Signals wired by gpWireCanvas(). Split by DECLARING FILE, because that is what makes the
# "did you rename a signal" check possible: 11 live on the canvas, 3 on the per-canvas edit
# service. A name here that no longer exists is a pin that can never fail.
# gpWireCanvas() 接的信号。按**声明文件**分组，因为正是它让「信号是否改名」可查：
# 11 个在画布上，3 个在逐画布的编辑服务上。表里出现一个已不存在的名字＝一颗永不失败的钉。
const GP_CROSS_SHEET_CANVAS_SIGNALS: Array[String] = [
	"gpCrossSheetRequested", "gpJumpToPeerRequested", "gpSyncToPeerRequested",
	"gpCrossSheetHistoryChanged", "gpCrossSheetDeleteRequested",
	"gpCrossPaneDragUpdated", "gpCrossPaneDropped", "gpCrossPaneDragEnded",
	"gpPortLinkUpdated", "gpPortLinkDropped", "gpPortLinkEnded",
]

const GP_CROSS_SHEET_ACTION_SIGNALS: Array[String] = [
	"gpEdgeTagCommitted", "gpEdgeAttrsCommitted", "gpEdgeCreated",
]


func gpTestCrossSheetWiringLivesWithTheHandlers() -> void:
	var gpController: String = _gpStripComments(
		FileAccess.get_file_as_string(GP_CROSS_SHEET_CONTROLLER_PATH))
	var gpRoot: String = _gpStripComments(FileAccess.get_file_as_string(GP_SHELL_ROOT_PATH))
	var gpCanvasSrc: String = FileAccess.get_file_as_string(GP_CANVAS_PATH)
	var gpEditSrc: String = FileAccess.get_file_as_string(GP_EDIT_SERVICE_PATH)
	var gpWire: String = _gpFuncBody(gpController, "gpWireCanvas")
	gpCheck(gpWire != "", "the per-canvas wiring method exists")
	gpCheck(gpCanvasSrc != "" and gpEditSrc != "",
		"both signal sources are readable (an unreadable file would silently pass every check below)")

	# 1) Every declared signal is CONNECTED inside gpWireCanvas — and it still exists. The
	# existence half is the S3 lesson applied forward: a renamed signal leaves a wire that
	# matches nothing, and a list of stale names can never fail.
	# 1) 每个声明的信号都在 gpWireCanvas 内**被连接** —— 且它仍然存在。存在性那一半是 S3 教训的
	# 正向应用：信号改名会留下一条匹配不到任何东西的线，而一串过期名字永远不会失败。
	# Per-signal, deliberately: an aggregated "14 of 14" hides WHICH wire is gone, and on a
	# 63-line method that is the only thing the reader needs.
	# 逐信号断言，刻意为之：一句「14 条全在」藏起了**哪一条**不在了，而在一个 63 行的方法里，
	# 那恰恰是读者唯一需要的信息。
	for gpName in GP_CROSS_SHEET_CANVAS_SIGNALS:
		gpCheck(gpWire.contains("." + gpName + ".connect("), "wired in gpWireCanvas: " + gpName)
		gpCheck(gpCanvasSrc.contains("signal " + gpName + "("),
			"still declared on the canvas: " + gpName)
	for gpName in GP_CROSS_SHEET_ACTION_SIGNALS:
		gpCheck(gpWire.contains("." + gpName + ".connect("), "wired in gpWireCanvas: " + gpName)
		gpCheck(gpEditSrc.contains("signal " + gpName + "("),
			"still declared on the edit service: " + gpName)

	# 2) The container link store is injected here too. Without it every cross-sheet command
	# still mutates the graph, but the store never fires gpTouch(), so the panels go stale —
	# a silent failure the user reads as "the link list is wrong".
	# 2) 容器 link store 也在这里注入。少了它，跨图纸命令仍会改图，但 store 永不发 gpTouch()，
	# 面板因此长期陈旧 —— 一个被用户读成「连接列表不对」的静默失效。
	gpCheck(gpWire.contains("gpLinkStore"), "the container link store is injected per canvas")
	gpCheck(gpEditSrc.contains("var gpLinkStore"),
		"the link-store slot still exists on the edit service")

	# 3) Anti-backslide: the root must not WIRE these signals off a canvas any more. The check is
	# `gpCanvas.<signal>`, NOT the bare name — and that precision is the point: the inspector
	# declares its own `gpJumpToPeerRequested` (wired by gpWireInspector, see the next test),
	# so a bare-name check would flag a legitimate line and demand a wrong edit. That is exactly
	# how a guard gets weakened by "the test is annoying" rather than by evidence.
	# 3) 防回流：根类不得再从画布上**接**这些信号。判据是 `gpCanvas.<信号>`，**不是**裸名字 ——
	# 这份精确正是重点：inspector 自己声明了一个 `gpJumpToPeerRequested`（由 gpWireInspector
	# 接，见下一个测试），裸名检查会命中一条合法代码并要求**错的**改动。守卫正是这样被
	#「测试真烦」而不是被证据削弱的。
	for gpName in GP_CROSS_SHEET_CANVAS_SIGNALS:
		gpCheck(not gpRoot.contains("gpCanvas." + gpName),
			"the root does not wire it off a canvas: " + gpName)
	for gpName in GP_CROSS_SHEET_ACTION_SIGNALS:
		gpCheck(not gpRoot.contains("gpCanvas.gpActions." + gpName),
			"the root does not wire it off a canvas: " + gpName)

	# 4) The root reaches the wiring through exactly one named call.
	# 4) 根类经**唯一**一个具名调用触达该接线。
	gpCheck(gpRoot.contains("gpCrossSheet.gpWireCanvas(gpCanvas)"),
		"the root wires a canvas with one named call")
	gpCheck(gpRoot.count("gpWireCanvas(") == 1,
		"the root calls it exactly once (a second call site would mean a second wiring path)")


# ============================================================================
# S5 (2026-11-06): the INSPECTOR's cross-sheet wiring moved to the controller too.
# S5（2026-11-06）：**属性面板**的跨图纸接线也搬到了控制器。
#
# WHY THIS PIN EXISTS / 为何需要这颗钉：
# S4 fixed the canvas half of one seam and left the panel half behind. Eight wires
# (off-page links, peer jump / unlink / delete, the peer-sheet dropdown, the inherit
# checkbox) stayed in GPMainWindow._gpAssembleInspector(), which made the seam only
# half-closed: a reader adding a ninth cross-sheet control to the panel would find the
# previous eight in the shell and conclude that is where they belong. Here the failure
# is not silent — the control simply never answers — but the WRONG PLACE is.
# S4 修好了同一个接缝的画布那一半，把面板那一半留在了原处。八条接线（跨页连接、对端跳转 /
# 断开 / 删除、对端图纸下拉、继承勾选框）仍住在 GPMainWindow._gpAssembleInspector()，
# 使接缝只关了一半：想给面板加第九个跨图纸控件的人会在外壳里看到前八个，从而认定那里才是家。
# 这里的失效并不静默 —— 控件就是不响应 —— 而是**位置**错了。
#
# The panel is ONE instance shared by every sheet, so this wiring is not per-sheet and
# must never be bound to a canvas: binding would pin the panel to the sheet it was wired
# with, and every later tab switch would show the previous sheet's peers.
# 面板为所有图纸**共用**的单一实例，故这层接线不逐图纸，且绝不可 bind 到某张画布：
# bind 会把面板钉死在当时那张图纸上，此后每次切页都显示上一张图纸的对端。
# ============================================================================

const GP_INSPECTOR_PATH: String = "res://src/ui/panels/inspector.gd"

# Signals wired by gpWireInspector(). All five are declared by the inspector itself; a name
# that no longer exists would be a pin that can never fail, so existence is checked too.
# gpWireInspector() 接的信号。五个都由 inspector 自己声明；已不存在的名字是一颗永不失败的
# 钉，故存在性一并检查。
const GP_INSPECTOR_CROSS_SHEET_SIGNALS: Array[String] = [
	"gpJumpToPeerRequested", "gpUnlinkRequested", "gpLinkDeleteRequested",
	"gpConnectPickRequested", "gpEdgeInheritToggled",
]

# Provider slots filled there. Not signals: missing one raises NO error and leaves no stale
# flag — the dropdown just renders empty, or the code pickers degrade to text boxes.
# 在那里填的 provider 槽。它们不是信号：漏掉一个**不**报错也不留陈旧标志 ——
# 下拉单纯渲染为空，或者代号选择器退化成文本框。
const GP_INSPECTOR_PROVIDER_SLOTS: Array[String] = [
	"gpLinksProvider", "gpSheetsProvider", "gpEdgeInheritProvider",
]


func gpTestInspectorCrossSheetWiringLivesWithTheController() -> void:
	var gpController: String = _gpStripComments(
		FileAccess.get_file_as_string(GP_CROSS_SHEET_CONTROLLER_PATH))
	var gpRoot: String = _gpStripComments(FileAccess.get_file_as_string(GP_SHELL_ROOT_PATH))
	var gpPanelSrc: String = FileAccess.get_file_as_string(GP_INSPECTOR_PATH)
	var gpWire: String = _gpFuncBody(gpController, "gpWireInspector")
	gpCheck(gpWire != "", "the panel wiring method exists")
	gpCheck(gpPanelSrc != "",
		"the panel source is readable (an unreadable file would silently pass every check below)")
	# The wiring is useless without its call site — a named method nobody invokes is the
	# cleanest possible way to break the panel while every string check still passes.
	# 没有调用点，接线等于不存在 —— 一个没人调用的具名方法，是「所有字符串检查都过、面板
	# 却全坏」的最干净做法。
	gpCheck(gpRoot.contains("gpCrossSheet.gpWireInspector()"),
		"the root calls the panel wiring")
	gpCheck(gpRoot.count("gpWireInspector(") == 1,
		"the root calls it exactly once (a second call site would mean a second wiring path)")

	# 1) Every signal is connected THERE, and still exists on the panel.
	# 1) 每个信号都在**那里**被连接，且仍存在于面板上。
	for gpName in GP_INSPECTOR_CROSS_SHEET_SIGNALS:
		gpCheck(gpWire.contains("." + gpName + ".connect("),
			"wired in gpWireInspector: " + gpName)
		gpCheck(gpPanelSrc.contains("signal " + gpName + "("),
			"still declared on the inspector: " + gpName)

	# 2) Every provider slot is filled THERE, and still exists on the panel.
	# 2) 每个 provider 槽都在**那里**被填，且仍存在于面板上。
	for gpName in GP_INSPECTOR_PROVIDER_SLOTS:
		gpCheck(gpWire.contains("." + gpName + " = "), "filled in gpWireInspector: " + gpName)
		gpCheck(gpPanelSrc.contains("var " + gpName + ":"),
			"still declared on the inspector: " + gpName)

	# 3) Anti-backslide: none of it may reappear in the root. Judged by `gpInspector.<member>`,
	# NOT by the bare name — the same precision lesson as above: `gpStandardProvider` and
	# `gpDefs` legitimately stay in the root, and a bare-name check would demand their removal
	# for a reason that does not exist.
	# 3) 防回流：一条都不得在根类重现。判据是 `gpInspector.<成员>`，**不是**裸名字 ——
	# 与上面同一条精确性教训：`gpStandardProvider` 与 `gpDefs` 合法地留在根类，裸名检查会
	# 为一条不存在的理由要求删掉它们。
	for gpName in GP_INSPECTOR_CROSS_SHEET_SIGNALS:
		gpCheck(not gpRoot.contains("gpInspector." + gpName),
			"the root does not wire it on the panel: " + gpName)
	for gpName in GP_INSPECTOR_PROVIDER_SLOTS:
		gpCheck(not gpRoot.contains("gpInspector." + gpName + " ="),
			"the root does not fill it on the panel: " + gpName)

	# 4) No per-sheet binding. The panel is shared by every sheet, so a bind() here would
	# wedge it onto whichever sheet happened to be active during assembly.
	# 4) 不得逐图纸绑定。面板为所有图纸共用，此处一个 bind() 就会把它楔死在装配时恰好活动
	# 的那张图纸上。
	gpCheck(not gpWire.contains(".bind("),
		"no signal here is bound to a sheet or canvas (the panel is shared)")

	# 5) The peer-sheet dropdown is a CLOSURE, not a captured table. Sheets are added,
	# renamed and deleted at runtime; a snapshot would list the peers as of assembly, and
	# nothing on screen would say so.
	# 5) 对端图纸下拉是**闭包**而非捕获住的表。图纸在运行期增删改名；快照会列出装配时刻的对端，
	# 而屏幕上没有任何东西会说出来。
	gpCheck(gpWire.contains("func() -> Dictionary"),
		"the sheet list is provided lazily, not snapshotted")
	gpCheck(gpWire.contains("gpCenter.gpToSheets()"),
		"the closure reads the live sheet table from the container it already holds")


# ============================================================================
# S8 (2026-11-06): "zero cross-object private calls" was a RULE WITHOUT A GUARD.
# S8（2026-11-06）：「零跨对象私有调用」是**一条没有守卫的规则**。
#
# ADR-10 has said it since day one, the W12 review counted the offenders by hand, and yet
# nothing in the gate would have stopped the next one. A rule that is only checked by a
# human reading a document is a rule that decays at the speed of the next deadline.
# ADR-10 从第一天就这么写，W12 审查还手工数过违规条数，但门禁里没有任何东西能拦住下一条。
# 一条只靠人读文档来检查的规则，会以「下一个截止日期」的速度腐坏。
#
# The scan below covers src/ only. Tests are deliberately out of scope: probing a private
# helper from a test is a narrow, reviewable exception, while production code reaching across
# a class boundary is the thing this rule is actually about.
# 下面的扫描只覆盖 src/。测试**故意**不在范围内：从测试里探一个私有辅助是范围窄、可评审的
# 例外；而生产代码跨类边界伸手，才是这条规则真正针对的事情。
# ============================================================================

# 1) The real tree: no cross-class private access anywhere in src/.
# 1) 真实全树：src/ 内不得有任何跨类私有访问。
func gpTestNoCrossClassPrivateAccess() -> void:
	var gpScan: Dictionary = _gpScanTree()
	var gpHits: Array[String] = []
	for gpKey in gpScan["violations"]:
		if str(gpKey).begins_with("private|"):
			gpHits.append(str(gpKey))
	gpEq(gpHits.size(), 0,
		"cross-object private access (ADR-10 — give the member a public entry point instead): "
			+ ", ".join(gpHits))


# 2) The detector itself: catches a foreign private, stays quiet on a class's own privates,
#    on public members, and inside comments.
# 2) 检测器自身：抓得到外来私有成员，对一个类访问自己的私有成员、公开成员、注释内的字样均沉默。
# The sample is a REAL private that must stay private (`_gpStepV3Header` is one link of the
# migration chain — calling it from outside would skip the rest of the chain). The check is
# textual, so it keeps working even if that helper is renamed.
# 样本是一个**必须保持私有**的真实成员（`_gpStepV3Header` 是迁移链上的一环 —— 从外部直接调用
# 会跳过链条其余部分）。检查是文本性的，故该辅助函数改名后本条仍然成立。
func gpTestPrivateAccessDetectorCatchesAndExempts() -> void:
	var gpIndex: Dictionary = _gpClassIndex()
	var gpAutoload: Array[String] = _gpAutoloadNames()
	var gpStats: Dictionary = {"allowed": 0}
	var gpBad: Array[String] = _gpScanText("res://src/core/_injected.gd",
		"GPSchemaMigrate._gpStepV3Header(gpOut, gpSheets)\n",
		gpIndex, gpAutoload, gpStats)
	gpCheck(gpBad.has("private|src/core/_injected.gd|GPSchemaMigrate._gpStepV3Header"),
		"a foreign class's private helper is detected")
	var gpOwn: Array[String] = _gpScanText("res://src/io/schema_migrate.gd",
		"GPSchemaMigrate._gpStepV3Header(gpOut, gpSheets)\n",
		gpIndex, gpAutoload, gpStats)
	gpEq(gpOwn.size(), 0,
		"a class may name its own private helper with its own prefix: " + ", ".join(gpOwn))
	var gpPublic: Array[String] = _gpScanText("res://src/core/_injected.gd",
		"var gpB: Variant = GPSchemaMigrate.gpMigrate(gpD)\n"
			+ "# GPSchemaMigrate._gpStepV3Header in a comment\n",
		gpIndex, gpAutoload, gpStats)
	# Filter to the `private|` kind: this synthetic core file also commits a LAYER violation by
	# naming an io class at all, and that one is correct — asserting size()==0 here would be
	# asserting that the layer detector is broken.
	# 只筛 `private|` 一类：这个合成 core 文件本来就同时犯了层违规（它终究命名了一个 io 类），
	# 那条是**对的** —— 在这里断言 size()==0，等于断言层检测器坏掉了。
	var gpPriv: Array[String] = []
	for gpKey in gpPublic:
		if str(gpKey).begins_with("private|"):
			gpPriv.append(str(gpKey))
	gpEq(gpPriv.size(), 0,
		"public members and comments are not flagged: " + ", ".join(gpPriv))
	# Lowercase receivers are variables (tools, canvases, providers), not class names. They are
	# filtered by the CAPITALISED prefix rule — asserting it keeps the next refactor from
	# "helpfully" relaxing the pattern into false-positive noise nobody will maintain.
	# 小写接收者是变量（工具、画布、provider），不是类名，由上大写前缀规则滤掉。断言这一点，
	# 是为了防止下一次重构"顺手"把模式放宽成没人愿意维护的误报噪音。
	var gpVar: Array[String] = _gpScanText("res://src/core/_injected.gd",
		"var gpC: bool = gpTool._gpBusy\n", gpIndex, gpAutoload, gpStats)
	gpEq(gpVar.size(), 0, "a lowercase receiver is not treated as a class: " + ", ".join(gpVar))

	# Instance form: the receiver's DECLARED type decides. A typed foreign receiver is caught;
	# a receiver typed as the file's OWN class is the static-factory case and stays legal; an
	# untyped receiver is not judged at all (text cannot tell what it holds).
	# 实例形态：由接收者的**声明类型**判定。已标注类型的外来接收者被抓；类型为本文件**自身**类
	# 的接收者属于静态工厂情形，合法；未标注类型的接收者完全不判（文本无法知道它装的是什么）。
	var gpInstBad: Array[String] = _gpScanText("res://src/ui/_injected.gd",
		"var gpT: GPSymbolDrawTool = GPSymbolDrawTool.new()\ngpT._gpKind = 1\n",
		gpIndex, gpAutoload, gpStats)
	gpCheck(gpInstBad.has("private|src/ui/_injected.gd|GPSymbolDrawTool._gpKind"),
		"a typed foreign receiver reaching into a private field is detected")
	var gpInstOwn: Array[String] = _gpScanText("res://src/io/schema_migrate.gd",
		"var gpM: GPSchemaMigrate = GPSchemaMigrate.new()\ngpM._gpStepV3Header(gpD, [])\n",
		gpIndex, gpAutoload, gpStats)
	gpEq(gpInstOwn.size(), 0,
		"the static factory's own fresh instance may use its own privates: " + ", ".join(gpInstOwn))
	var gpInstAny: Array[String] = _gpScanText("res://src/ui/_injected.gd",
		"var gpAny = GPSymbolDrawTool.new()\ngpAny._gpKind = 1\n",
		gpIndex, gpAutoload, gpStats)
	gpEq(gpInstAny.size(), 0,
		"an untyped receiver is not guessed at (no type, no verdict): " + ", ".join(gpInstAny))


# ============================================================================
# ADR-47 (2026-11-06): 模块化与新增功能落位 —— 预算只减不增
# Modularisation and where new features land — budgets only go down.
#
# THE POINT / 要点：新增功能默认写进**新文件**；下面这些大文件只允许变短。
# 表里的数字是 2026-11-06 的实测值，不是目标值 —— 它们存在的唯一理由，是"今天不能再长"。
# New features land in a NEW file by default. The files below may only shrink: the numbers
# are measurements taken on 2026-11-06, not goals — they only say "not one more line".
#
# 为什么用"预算"而不是"规范"：规范只能劝人，预算会拦人。S8 的教训是，一条只写在文档里的
# 规则，会以"下一个截止日期"的速度腐坏。
# Why a budget and not a style guide: a guide persuades, a budget blocks. S8's lesson was that
# a rule living only in a document decays at the speed of the next deadline.
# ============================================================================

# A file at or below this may grow freely; above it, growth needs a budget row — and a row can
# only be granted on a day the file is already that big, never retroactively.
# 不超过此值的文件可自由增长；超过后必须有预算行，且只能"当天就这么大"才可登记，不能事后补票。
const GP_FILE_SOFT_MAX: int = 500

# Same idea one level down: a 350-line function is a file hiding inside a file.
# 同一条规则下沉一级：一个 350 行的函数，就是藏在文件里的文件。
const GP_FUNC_SOFT_MAX: int = 200

# Ceilings on the registries: they may only go down. A new row means a new big file.
# 登记表自身的上限：只可下调。多出一行，就多了一个大文件。
const GP_FILE_BUDGET_CEILING: int = 35
const GP_FUNC_BUDGET_CEILING: int = 4

# ACTIVE budget — the only table a working session needs to look at.
# 使用中的预算 —— 日常干活只需要看这一张表。
const GP_FILE_BUDGET: Dictionary = {
	"src/ui/canvas/canvas_2d.gd": 2024,
	"src/ui/panels/center_area.gd": 1931,
	"src/ui/panels/inspector.gd": 1474,
	"src/ui/shell/cross_sheet_controller.gd": 1454,
	"src/app/edit_service.gd": 1220,
	"src/io/dexpi_exporter.gd": 1208,
	"src/ui/dialogs/project_standard_dialog.gd": 1113,
	"src/autoload/i18n.gd": 1086,
	"src/core/view/frame_geometry.gd": 1027,
	"src/core/model/sheet.gd": 997,
	"src/io/deliverable/gp_deliverable_model.gd": 979,
	"src/core/geometry/mount_resolver.gd": 974,
	"src/ui/canvas/canvas_context_menu.gd": 945,
	"src/core/model/pid_graph.gd": 892,
	"src/core/validation/drc_rules.gd": 888,
	"src/ui/tools/select_tool.gd": 877,
	"src/ui/panels/toolbar.gd": 827,
	"src/render/symbol_view.gd": 816,
	"src/ui/dialogs/title_block_dialog.gd": 783,
	"src/core/symbol/generators/generator_registry.gd": 762,
	"src/ui/shell/main_window.gd": 757,
	"src/core/model/project_standard.gd": 754,
	"src/ui/dialogs/make_symbol_dialog.gd": 726,
	"src/ui/shell/file_coordinator.gd": 726,
	"src/ui/canvas/edit_facade.gd": 709,
	"src/ui/tools/edge_grip_ops.gd": 638,
	"src/io/schema_migrate.gd": 624,
	"src/app/commands/cross_sheet_create_command.gd": 603,
	"src/ui/dialogs/export_lists_dialog.gd": 591,
	"src/core/validation/rule_pack.gd": 588,
	"src/ui/canvas/annotation_editor.gd": 572,
	"src/core/view/print_model.gd": 558,
	"src/core/geometry/edge_tag_layout.gd": 554,
	"src/ui/canvas/port_connect_ops.gd": 550,
	"src/ui/tools/frame_grip_ops.gd": 545,
}

# FROZEN snapshot from the day the budget was written. Its whole job is to catch a RAISE:
# lowering a budget is free, raising it above the snapshot fails the gate.
# 写入当天的冻结快照。它只干一件事：抓"上调"。下调自由，超过快照即转红。
const GP_FILE_BUDGET_FROZEN: Dictionary = {
	"src/ui/canvas/canvas_2d.gd": 2024,
	"src/ui/panels/center_area.gd": 1931,
	"src/ui/panels/inspector.gd": 1474,
	"src/ui/shell/cross_sheet_controller.gd": 1454,
	"src/app/edit_service.gd": 1220,
	"src/io/dexpi_exporter.gd": 1208,
	"src/ui/dialogs/project_standard_dialog.gd": 1113,
	"src/autoload/i18n.gd": 1086,
	"src/core/view/frame_geometry.gd": 1027,
	"src/core/model/sheet.gd": 997,
	"src/io/deliverable/gp_deliverable_model.gd": 979,
	"src/core/geometry/mount_resolver.gd": 974,
	"src/ui/canvas/canvas_context_menu.gd": 945,
	"src/core/model/pid_graph.gd": 892,
	"src/core/validation/drc_rules.gd": 888,
	"src/ui/tools/select_tool.gd": 877,
	"src/ui/panels/toolbar.gd": 827,
	"src/render/symbol_view.gd": 816,
	"src/ui/dialogs/title_block_dialog.gd": 783,
	"src/core/symbol/generators/generator_registry.gd": 762,
	"src/ui/shell/main_window.gd": 757,
	"src/core/model/project_standard.gd": 754,
	"src/ui/dialogs/make_symbol_dialog.gd": 726,
	"src/ui/shell/file_coordinator.gd": 726,
	"src/ui/canvas/edit_facade.gd": 709,
	"src/ui/tools/edge_grip_ops.gd": 638,
	"src/io/schema_migrate.gd": 624,
	"src/app/commands/cross_sheet_create_command.gd": 603,
	"src/ui/dialogs/export_lists_dialog.gd": 591,
	"src/core/validation/rule_pack.gd": 588,
	"src/ui/canvas/annotation_editor.gd": 572,
	"src/core/view/print_model.gd": 558,
	"src/core/geometry/edge_tag_layout.gd": 554,
	"src/ui/canvas/port_connect_ops.gd": 550,
	"src/ui/tools/frame_grip_ops.gd": 545,
}

const GP_FUNC_BUDGET: Dictionary = {
	"src/ui/tools/select_tool.gd::gpOnPress": 352,
	"src/ui/canvas/canvas_2d.gd::gpApplyStandard": 336,
	"src/core/model/sheet.gd::_gpScaleFromMeta": 252,
	"src/io/dexpi_reader.gd::gpReadXml": 234,
}
const GP_FUNC_BUDGET_FROZEN: Dictionary = {
	"src/ui/tools/select_tool.gd::gpOnPress": 352,
	"src/ui/canvas/canvas_2d.gd::gpApplyStandard": 336,
	"src/core/model/sheet.gd::_gpScaleFromMeta": 252,
	"src/io/dexpi_reader.gd::gpReadXml": 234,
}


# Lines as a programmer counts them: a trailing newline does not create a phantom last line.
# 按人眼口径数行：结尾换行不产生一行幽灵。
func _gpLineCount(gpText: String) -> int:
	var gpParts: PackedStringArray = gpText.split("\n")
	if gpParts.size() > 0 and gpParts[gpParts.size() - 1] == "":
		return gpParts.size() - 1
	return gpParts.size()


# Longest top-level function in a file: from a column-0 `func ` line to the next one.
# 文件中最长的顶格函数：从一条顶格 `func ` 到**下一条**顶格 `func `。
# Column-0 only: a lambda inside an expression is indented and must not count as a member.
# 只认顶格：表达式里的 lambda 带缩进，不算成员函数。
func _gpLongestFunc(gpText: String) -> Dictionary:
	var gpLines: PackedStringArray = gpText.split("\n")
	var gpStarts: Array[int] = []
	for gpI in range(gpLines.size()):
		var gpL: String = gpLines[gpI]
		if gpL.begins_with("func ") or gpL.begins_with("static func "):
			gpStarts.append(gpI)
	var gpBest: Dictionary = {"lines": 0, "name": ""}
	for gpK in range(gpStarts.size()):
		var gpEnd: int = gpStarts[gpK + 1] if gpK + 1 < gpStarts.size() else gpLines.size()
		var gpLast: int = gpEnd
		while gpLast > gpStarts[gpK] and gpLines[gpLast - 1].strip_edges() == "":
			gpLast -= 1
		var gpLen: int = gpLast - gpStarts[gpK]
		if gpLen > int(gpBest["lines"]):
			var gpSig: String = gpLines[gpStarts[gpK]].split("(")[0]
			gpBest = {"lines": gpLen,
				"name": gpSig.trim_prefix("static ").trim_prefix("func ")}
	return gpBest


# 1) No file over its budget; no unregistered file over the soft max.
# 1) 没有文件超预算；也没有"未登记"的文件越过软上限。
func gpTestFileBudgetsOnlyShrink() -> void:
	var gpFiles: Array[String] = _gpGdFiles(GP_SRC_ROOT)
	gpCheck(gpFiles.size() >= 290,
		"scanned %d src files (a broken scan must not pass)" % gpFiles.size())
	var gpOver: Array[String] = []
	for gpPath in gpFiles:
		var gpKey: String = _gpKeyPath(gpPath)
		var gpLines: int = _gpLineCount(FileAccess.get_file_as_string(gpPath))
		var gpCap: int = int(GP_FILE_BUDGET.get(gpKey, GP_FILE_SOFT_MAX))
		if gpLines > gpCap:
			gpOver.append("%s %d>%d" % [gpKey, gpLines, gpCap])
	gpEq(gpOver.size(), 0,
		"file budget exceeded — extract a module, do not raise the cap: " + ", ".join(gpOver))


# 2) Budgets only go down, and the two tables must stay key-for-key identical (prune both).
# 2) 预算只下不上；两张表必须逐键一致（要删就一起删）。
func gpTestFileBudgetCanOnlyShrink() -> void:
	var gpRaised: Array[String] = []
	for gpKey in GP_FILE_BUDGET:
		if not GP_FILE_BUDGET_FROZEN.has(gpKey):
			gpRaised.append("%s (new row — no retroactive grandfathering)" % gpKey)
		elif int(GP_FILE_BUDGET[gpKey]) > int(GP_FILE_BUDGET_FROZEN[gpKey]):
			gpRaised.append("%s %d>frozen %d" % [gpKey, int(GP_FILE_BUDGET[gpKey]),
				int(GP_FILE_BUDGET_FROZEN[gpKey])])
	for gpKey in GP_FILE_BUDGET_FROZEN:
		if not GP_FILE_BUDGET.has(gpKey):
			gpRaised.append("%s (dropped from budget but still frozen — prune both)" % gpKey)
	gpEq(gpRaised.size(), 0, "file budgets may only go down: " + ", ".join(gpRaised))
	gpCheck(GP_FILE_BUDGET.size() <= GP_FILE_BUDGET_CEILING,
		"budget rows %d exceed ceiling %d" % [GP_FILE_BUDGET.size(), GP_FILE_BUDGET_CEILING])
	# Stale rows: once a file is back under the soft max its row is an excuse, not a record.
	# 陈旧行：文件回到软上限以下后，那一行就是借口而不是记录。
	var gpStale: Array[String] = []
	for gpKey in GP_FILE_BUDGET:
		if _gpLineCount(FileAccess.get_file_as_string("res://" + str(gpKey))) <= GP_FILE_SOFT_MAX:
			gpStale.append(str(gpKey))
	gpEq(gpStale.size(), 0,
		"stale budget rows (under the soft max again — delete the row from BOTH tables): "
			+ ", ".join(gpStale))


# 3) Same rule one level down: no function over its budget, none unregistered over the soft max.
# 3) 同一条规则下沉一级：没有函数超预算，也没有未登记的越过软上限。
func gpTestFunctionBudgetsOnlyShrink() -> void:
	var gpOver: Array[String] = []
	for gpPath in _gpGdFiles(GP_SRC_ROOT):
		var gpKey: String = _gpKeyPath(gpPath)
		var gpLines: PackedStringArray = FileAccess.get_file_as_string(gpPath).split("\n")
		var gpStarts: Array[int] = []
		for gpI in range(gpLines.size()):
			var gpL: String = gpLines[gpI]
			if gpL.begins_with("func ") or gpL.begins_with("static func "):
				gpStarts.append(gpI)
		for gpK in range(gpStarts.size()):
			var gpEnd: int = gpStarts[gpK + 1] if gpK + 1 < gpStarts.size() else gpLines.size()
			var gpLast: int = gpEnd
			while gpLast > gpStarts[gpK] and gpLines[gpLast - 1].strip_edges() == "":
				gpLast -= 1
			var gpLen: int = gpLast - gpStarts[gpK]
			var gpSig: String = gpLines[gpStarts[gpK]].split("(")[0]
			var gpName: String = gpSig.trim_prefix("static ").trim_prefix("func ")
			var gpFnKey: String = gpKey + "::" + gpName
			var gpCap: int = int(GP_FUNC_BUDGET.get(gpFnKey, GP_FUNC_SOFT_MAX))
			if gpLen > gpCap:
				gpOver.append("%s %d>%d" % [gpFnKey, gpLen, gpCap])
	gpEq(gpOver.size(), 0,
		"function budget exceeded — split the function: " + ", ".join(gpOver))
	var gpRaised: Array[String] = []
	for gpKey in GP_FUNC_BUDGET:
		if not GP_FUNC_BUDGET_FROZEN.has(gpKey):
			gpRaised.append("%s (new row)" % gpKey)
		elif int(GP_FUNC_BUDGET[gpKey]) > int(GP_FUNC_BUDGET_FROZEN[gpKey]):
			gpRaised.append("%s %d>frozen %d" % [gpKey, int(GP_FUNC_BUDGET[gpKey]),
				int(GP_FUNC_BUDGET_FROZEN[gpKey])])
	gpEq(gpRaised.size(), 0, "function budgets may only go down: " + ", ".join(gpRaised))
	gpCheck(GP_FUNC_BUDGET.size() <= GP_FUNC_BUDGET_CEILING,
		"function budget rows %d exceed ceiling %d"
			% [GP_FUNC_BUDGET.size(), GP_FUNC_BUDGET_CEILING])


# 4) The measurers themselves: line count must not invent a phantom line, and the longest-func
#    finder must ignore an indented lambda (otherwise every callback looks like a 300-line
#    function and the gate degenerates into noise nobody reads).
# 4) 量尺自身：行数不得凭空多一行；最长函数探测器必须忽略带缩进的 lambda —— 否则每个回调
#    都会被算成 300 行，门禁退化成没人看的噪音。
func gpTestBudgetMeasurersAreHonest() -> void:
	gpEq(_gpLineCount("a\nb\n"), 2, "trailing newline is not a phantom line")
	gpEq(_gpLineCount("a\nb"), 2, "a file without a trailing newline still has 2 lines")
	gpEq(_gpLineCount(""), 0, "an empty file has 0 lines")
	# Trailing blank lines belong to nobody — gpA is 2 lines (signature + body), gpB is 4.
	# 行尾空行不属于任何函数 —— gpA 是 2 行（签名 + 函数体），gpB 是 4 行。
	var gpSrc: String = "func gpA() -> void:\n\tpass\n\n\nfunc gpB() -> void:\n"
	gpSrc += "\tvar gpX: int = 0\n\tvar gpY: int = 0\n\tpass\n"
	gpEq(int(_gpLongestFunc(gpSrc)["lines"]), 4,
		"a function is measured to its last body line, blanks trimmed")
	gpEq(str(_gpLongestFunc(gpSrc)["name"]), "gpB", "the longer function is the one reported")
	var gpLambda: String = "func gpC() -> void:\n\tvar gpF: Callable = func() -> void:\n\t\tpass\n"
	gpEq(int(_gpLongestFunc(gpLambda)["lines"]), 3,
		"an indented lambda is not a member function")
