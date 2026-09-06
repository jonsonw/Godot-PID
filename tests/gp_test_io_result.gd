extends "res://tests/gp_test.gd"
# Headless tests for GPIOResult (P1 extraction).
# GPIOResult（P1 抽取）的 headless 测试。

func gpTestSuccessShape() -> void:
	var r: GPIOResult = GPIOResult.gpSuccess()
	gpCheck(r.gpIsOk(), "success is ok")
	gpEq(r.gpCode, "", "success carries no code")
	gpCheck(not r.gpFailedWith("io.write_failed"), "success never matches a failure code")

func gpTestFailureShape() -> void:
	var r: GPIOResult = GPIOResult.gpFailure("io.write_failed", "io.err_write", "/tmp/a.csv")
	gpCheck(not r.gpIsOk(), "failure is not ok")
	gpCheck(r.gpFailedWith("io.write_failed"), "failure matches its own code")
	gpCheck(not r.gpFailedWith("io.other"), "failure does not match another code")
	gpEq(r.gpMessageKey, "io.err_write", "message key preserved")

# The point of the class: the UI must be able to show a localized reason, while core itself
# never touches the I18n autoload. A translator Callable is injected instead.
# 本类的要义：界面能显示本地化原因，而 core 自身绝不触碰 I18n 自动加载——改为注入翻译器 Callable。
func gpTestTextUsesInjectedTranslator() -> void:
	var tr: Callable = func(k: String) -> String:
		return "T:" + k
	var ok: GPIOResult = GPIOResult.gpSuccess("io.saved")
	gpEq(ok.gpText(tr), "T:io.saved", "success text is the translated key")
	var fail: GPIOResult = GPIOResult.gpFailure("conn.self", "conn.err_self")
	gpEq(fail.gpText(tr), "T:conn.err_self", "failure text is the translated key")
	var detailed: GPIOResult = GPIOResult.gpFailure("io.write_failed", "io.err_write", "a.csv")
	gpEq(detailed.gpText(tr), "T:io.err_write: a.csv", "detail is appended after the message")
	# No key at all: fall back to the raw detail rather than translating an empty string.
	# 完全没有键时：回退为原始细节，而非翻译空串。
	var bare: GPIOResult = GPIOResult.gpFailure("io.misc", "", "boom")
	gpEq(bare.gpText(tr), "boom", "keyless result falls back to detail")

func gpTestToString() -> void:
	gpCheck(GPIOResult.gpSuccess().gpToString().begins_with("OK"), "success prints OK")
	gpCheck(GPIOResult.gpFailure("c", "k").gpToString().begins_with("FAIL"), "failure prints FAIL")
