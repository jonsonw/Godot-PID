class_name GPGTest
extends Node
# Lightweight headless assertion base (no GUT dependency). Test suites extend this and expose
# methods named gpTest*(). The aggregator runner (tests/run_core_tests.gd) reflects over and calls
# each gpTest* method, summing _gpPassed/_gpFailed to decide the exit code.
# 轻量 headless 断言基类（不依赖 GUT）。测试套件继承本类并实现 gpTest*() 方法；聚合运行器
# (tests/run_core_tests.gd) 反射调用每个 gpTest*，累加 _gpPassed/_gpFailed 决定退出码。

# Passed / failed assertion counters (accumulate across all gpTest* calls).
# 通过 / 失败断言计数（跨所有 gpTest* 调用累加）。
var _gpPassed: int = 0
var _gpFailed: int = 0


# Record a boolean check.
# 记录一个布尔断言。
func gpCheck(gpCond: bool, gpMsg: String) -> void:
	if gpCond:
		_gpPassed += 1
	else:
		_gpFailed += 1
		push_error("FAIL: " + gpMsg)
		print("FAIL: ", gpMsg)


# Record an equality check (Variant == Variant).
# 记录相等断言。
func gpEq(gpGot: Variant, gpWant: Variant, gpMsg: String) -> void:
	if gpGot == gpWant:
		_gpPassed += 1
	else:
		_gpFailed += 1
		push_error("FAIL: %s  (got %s, want %s)" % [gpMsg, gpGot, gpWant])
		print("FAIL: ", gpMsg, "  (got=", gpGot, " want=", gpWant, ")")


# Record an approximate float check within gpEps.
# 记录浮点近似断言（误差 gpEps 内）。
func gpApprox(gpGot: float, gpWant: float, gpEps: float, gpMsg: String) -> void:
	if absf(gpGot - gpWant) <= gpEps:
		_gpPassed += 1
	else:
		_gpFailed += 1
		push_error("FAIL: %s  (got %.6f, want %.6f, eps %.6f)" % [gpMsg, gpGot, gpWant, gpEps])
		print("FAIL: ", gpMsg, "  (got=", gpGot, " want=", gpWant, ")")


# Reset counters (called by the runner before each gpTest* method so per-method deltas are clean).
# 清零计数（运行器在调用每个 gpTest* 前调用，使单方法增减干净）。
func _gpResetCounters() -> void:
	_gpPassed = 0
	_gpFailed = 0


# Accessors for the runner.
# 供运行器读取的访问器。
func gpPassed() -> int:
	return _gpPassed

func gpFailed() -> int:
	return _gpFailed
