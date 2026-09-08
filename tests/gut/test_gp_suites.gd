extends GutTest
# Bridge: run the pre-existing GPGTest suites (tests/gp_test_*.gd) from inside GUT.
# 桥接：在 GUT 内驱动本仓库既有的 GPGTest 套件（tests/gp_test_*.gd）。
#
# Why this exists / 为何存在：
#   G-PID 在引入 GUT 之前已有 21 套自研 GPGTest 套件（443 条断言）。它们 `extends GPGTest`
#   且方法命名为 gpTest*，与 GUT 的 `extends GutTest` + test_* 约定不兼容。
#   全量改写成本高、回归风险大，因此用一个 GUT 测试脚本反射驱动它们：
#   每个 gpTest* 方法折算为一条 GUT 断言（失败数为 0），具体哪条断言失败仍由
#   GPGTest 基类的 push_error / print 输出，可精确定位。
#
# Trade-off / 权衡：
#   报告粒度是「套件方法级」而非「单条断言级」——GUT 侧看到的是 60+ 条方法断言，
#   而非 443 条；换来的是零改动复用既有资产。新写的测试请直接用 GUT 原生写法。

const GP_SUITE_DIR: String = "res://tests"
const GP_SUITE_PREFIX: String = "gp_test_"
const GP_METHOD_PREFIX: String = "gpTest"
# Expected suite count; bump when a new gp_test_*.gd is added.
# 预期套件数量；新增 gp_test_*.gd 时同步 +1。
const GP_EXPECTED_SUITES: int = 21

# Engine errors the legacy suites are *expected* to emit. GUT fails any test that leaves an
# error unhandled, so these are marked handled explicitly (see _gpHandleExpectedErrors).
# 既有套件「预期会」产生的引擎错误。GUT 对未处理的错误一律判定失败，故在此显式标记。
const GP_EXPECTED_ERRORS: Array = [
	# gp_test_project_io.gd 的 malformed JSON 用例：JSON.parse_string 解析失败时引擎会打印该
	# condition 错误；该用例正要覆盖解析失败路径，属预期噪音而非回归。
	'Condition "error != Error::OK" is true. Returning: Variant()',
]


# Guard against a suite silently disappearing (e.g. renamed to a non-matching prefix).
# 防止套件被静默遗漏（例如改名后不再匹配前缀）。
func test_gp_suite_count() -> void:
	var gpSuites: Array[String] = _gpCollectSuites()
	assert_eq(
		gpSuites.size(),
		GP_EXPECTED_SUITES,
		"GPGTest 套件数应为 %d，实际 %d" % [GP_EXPECTED_SUITES, gpSuites.size()]
	)


# Drive every gpTest* method of every GPGTest suite and require zero failed assertions.
# 驱动每个 GPGTest 套件的每个 gpTest* 方法，要求失败断言数为 0。
func test_gp_suites_all_assertions() -> void:
	for gpPath in _gpCollectSuites():
		_gpRunSuite(gpPath)
	# Mark intentionally-triggered engine errors as handled so GUT does not fail on them.
	# 把有意触发的引擎错误标记为已处理，避免 GUT 因此判定失败。
	_gpHandleExpectedErrors()


# Collect res://tests/gp_test_*.gd, excluding the base class gp_test.gd.
# 收集 res://tests/gp_test_*.gd，排除基类 gp_test.gd。
func _gpCollectSuites() -> Array[String]:
	var gpOut: Array[String] = []
	var gpDir: DirAccess = DirAccess.open(GP_SUITE_DIR)
	if gpDir == null:
		return gpOut
	gpDir.list_dir_begin()
	var gpEntry: String = gpDir.get_next()
	while gpEntry != "":
		if (
			gpEntry.begins_with(GP_SUITE_PREFIX)
			and gpEntry.ends_with(".gd")
			and gpEntry != "gp_test.gd"
		):
			gpOut.append(GP_SUITE_DIR + "/" + gpEntry)
		gpEntry = gpDir.get_next()
	gpDir.list_dir_end()
	gpOut.sort()
	return gpOut


# Instantiate one suite into the tree, reflect over its gpTest* methods, and assert on counters.
# 将单个套件实例化入树，反射其 gpTest* 方法并断言计数器。
func _gpRunSuite(gpPath: String) -> void:
	var gpScript: GDScript = load(gpPath) as GDScript
	assert_not_null(gpScript, "套件脚本应可加载: " + gpPath)
	if gpScript == null:
		return
	var gpInst: Node = gpScript.new()
	# Must live in the tree so Node lifecycle (_ready etc.) is valid, same as run_core_tests.gd.
	# 必须入树使 Node 生命周期有效，与 run_core_tests.gd 保持一致。
	add_child_autofree(gpInst)

	var gpMethods: Array[String] = []
	for gpM in gpInst.get_method_list():
		var gpName: String = String(gpM["name"])
		if gpName.begins_with(GP_METHOD_PREFIX):
			gpMethods.append(gpName)
	gpMethods.sort()

	assert_gt(
		gpMethods.size(),
		0,
		"套件应至少包含一个 %s* 方法: %s" % [GP_METHOD_PREFIX, gpPath.get_file()]
	)

	for gpM in gpMethods:
		# Reset per-method so counters are clean, mirroring the built-in runner.
		# 每方法调用前清零，与内置运行器一致。
		gpInst.call("_gpResetCounters")
		gpInst.call(gpM)
		var gpFailed: int = gpInst.call("gpFailed")
		var gpPassed: int = gpInst.call("gpPassed")
		assert_eq(gpFailed, 0, "%s :: %s" % [gpPath.get_file(), gpM])
		assert_gt(gpPassed, 0, "%s :: %s 应至少执行一条断言" % [gpPath.get_file(), gpM])


# Mark known-expected engine errors as handled. Any *other* error still fails the test,
# so a genuine regression inside a legacy suite is not silently swallowed.
# 将已知预期错误标记为已处理。其余错误仍会导致失败，
# 因此既有套件中的真实回归不会被静默吞掉。
func _gpHandleExpectedErrors() -> void:
	for gpErr in get_errors():
		if gpErr.handled:
			continue
		for gpText in GP_EXPECTED_ERRORS:
			if gpErr.contains_text(String(gpText)):
				gpErr.handled = true
				break
