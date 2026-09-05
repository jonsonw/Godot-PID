extends SceneTree
# Headless core test runner (P2-3 test baseline). No GUT dependency.
# Aggregates every tests/gp_test_*.gd suite, reflects over each gpTest* method, runs it, and
# sums the assertion counters. Quits non-zero if any assertion fails.
#
# Run from project root:
#   Godot --headless --script res://tests/run_core_tests.gd
#
# 核心 headless 测试运行器（P2-3 测试基线）。不依赖 GUT。
# 聚合 tests/gp_test_*.gd 各套件，反射调用每个 gpTest* 方法，累加断言计数。
# 任一断言失败则退出码非 0。
#
# Run / 运行：
#   Godot --headless --script res://tests/run_core_tests.gd


func _initialize() -> void:
	var gpDir: DirAccess = DirAccess.open("res://tests")
	if gpDir == null:
		print("ERROR: cannot open res://tests")
		quit(1)
		return
	# Collect test suite scripts (gp_test_*.gd), excluding this runner + the base class.
	# 收集测试套件脚本（gp_test_*.gd），排除本运行器与基类。
	var gpSuites: Array[String] = []
	gpDir.list_dir_begin()
	var gpEntry: String = gpDir.get_next()
	while gpEntry != "":
		if gpEntry.begins_with("gp_test_") and gpEntry.ends_with(".gd") and gpEntry != "gp_test.gd":
			gpSuites.append("res://tests/" + gpEntry)
		gpEntry = gpDir.get_next()
	gpDir.list_dir_end()
	gpSuites.sort()

	if gpSuites.is_empty():
		print("No gp_test_*.gd suites found. Creating a test suite would help.")
		quit(0)
		return

	var gpTotalPassed: int = 0
	var gpTotalFailed: int = 0
	var gpSuiteFailures: Array[String] = []

	for gpPath in gpSuites:
		var gpScript: GDScript = load(gpPath) as GDScript
		if gpScript == null:
			gpSuiteFailures.append("LOAD_FAIL " + gpPath)
			continue
		var gpInst: Node = gpScript.new()
		# Instance must be in the tree so Node lifecycle (_ready etc.) is valid.
		# 实例需入树，使 Node 生命周期（_ready 等）有效。
		root.add_child(gpInst)
		var gpMethods: Array[String] = []
		for gpM in gpInst.get_method_list():
			var gpN: String = String(gpM["name"])
			if gpN.begins_with("gpTest"):
				gpMethods.append(gpN)
		gpMethods.sort()
		var gpSuitePass: int = 0
		var gpSuiteFail: int = 0
		for gpM in gpMethods:
			# Reset counters before each method so per-method counts stay clean.
			# 调用前清零计数，使单方法计数干净。
			gpInst.call("_gpResetCounters")
			# Suppress push_error spam by capturing; we only tally counters.
			# 仅累加计数；push_error 由基类内部打印。
			gpInst.call(gpM)
			gpSuitePass += gpInst.call("gpPassed")
			var gpFail: int = gpInst.call("gpFailed")
			gpSuiteFail += gpFail
			if gpFail > 0:
				print("  [suite] %s :: %s  -> %d FAILED assertions" % [gpPath.get_file(), gpM, gpFail])
		root.remove_child(gpInst)
		gpInst.queue_free()
		print("[suite] %-28s  passed=%-4d failed=%d" % [gpPath.get_file(), gpSuitePass, gpSuiteFail])
		gpTotalPassed += gpSuitePass
		gpTotalFailed += gpSuiteFail
		if gpSuiteFail > 0:
			gpSuiteFailures.append(gpPath.get_file())

	print("")
	print("============================================")
	print("TOTAL  passed=%d  failed=%d" % [gpTotalPassed, gpTotalFailed])
	if not gpSuiteFailures.is_empty():
		print("SUITES WITH FAILURES: ", gpSuiteFailures)
	print("============================================")
	# Non-zero exit code signals failure (useful for CI).
	# 退出码非 0 表示有失败（便于 CI 接入）。
	if gpTotalFailed > 0 or not gpSuiteFailures.is_empty():
		quit(1)
	else:
		quit(0)
