extends "res://tests/gp_test.gd"
# Headless tests for GPIdGen (P1 extraction).
# GPIdGen（P1 抽取）的 headless 测试。

func gpTestCounterSharesOneSequence() -> void:
	# Node and edge ids share a single counter (historic behaviour: "n1" then "e2"), which is
	# what keeps ids unique across both kinds without a per-prefix table.
	# 节点与边 id 共用同一计数器（历史行为："n1" 之后是 "e2"），这是无需分前缀表即可
	# 保证两类 id 互不相同的原因。
	var g: GPIdGen = GPIdGen.new()
	gpEq(g.gpNext("n"), "n1", "first node id")
	gpEq(g.gpNext("e"), "e2", "first edge id continues the same counter")
	gpEq(g.gpNext("n"), "n3", "second node id")
	gpEq(g.gpCounter, 4, "counter advanced once per id")

func gpTestReset() -> void:
	var g: GPIdGen = GPIdGen.new()
	g.gpNext("n")
	g.gpReset()
	gpEq(g.gpCounter, 1, "reset returns the counter to 1")
	gpEq(g.gpNext("n"), "n1", "ids restart after reset")

func gpTestSanitizeAscii() -> void:
	gpEq(GPIdGen.gpSanitize("Pump 101"), "Pump_101", "space collapses to underscore")
	gpEq(GPIdGen.gpSanitize("centrifugal-pump"), "centrifugal_pump", "hyphen collapses")
	gpEq(GPIdGen.gpSanitize("a.b/c"), "a_b_c", "punctuation collapses")
	gpEq(GPIdGen.gpSanitize("Ok_9"), "Ok_9", "allowed characters survive untouched")

# CJK must survive: this project's users name symbols in Chinese, and folding them all to "_"
# would make the generated pack filename meaningless.
# 中文必须保留：本项目的用户以中文命名图元，全折叠为 "_" 会让生成的图元包文件名失去意义。
func gpTestSanitizeKeepsCjk() -> void:
	gpEq(GPIdGen.gpSanitize("离心泵"), "离心泵", "CJK is preserved verbatim")
	gpEq(GPIdGen.gpSanitize("泵 2号"), "泵_2号", "CJK kept, space collapsed")
	gpEq(GPIdGen.gpSanitize("离心泵(备用)"), "离心泵_备用_", "full-width brackets collapse")

# The fallback fires ONLY when the result is empty, matching the historic canvas behaviour
# (a bare "_" was a valid id). A name made entirely of characters that collapse to "_"
# yields "___" — a non-empty id, so it does NOT fall back.
# 兜底仅在「结果为空」时触发，与画布历史行为一致（裸 "_" 曾是合法 id）。全由折叠为 "_" 的
# 字符组成的名称会得到 "___" —— 非空 id，故不回退。
func gpTestSanitizeFallback() -> void:
	gpEq(GPIdGen.gpSanitize(""), GPIdGen.GP_FALLBACK, "empty name falls back")
	gpEq(GPIdGen.gpSanitize("！！！"), "___", "all-punctuation collapses to underscores, no fallback")
	gpEq(GPIdGen.gpSanitize("   "), "___", "whitespace collapses to underscores, no fallback")

func gpTestEnsureUniqueCallable() -> void:
	var taken: Array[String] = ["pump", "pump_2"]
	var isTaken: Callable = func(c: String) -> bool:
		return taken.has(c)
	gpEq(GPIdGen.gpEnsureUnique("pump", isTaken), "pump_3", "skips taken and taken_2")
	gpEq(GPIdGen.gpEnsureUnique("valve", isTaken), "valve", "free id returned unchanged")

func gpTestEnsureUniqueInList() -> void:
	var taken: Array[String] = ["a", "a_2", "a_3"]
	gpEq(GPIdGen.gpEnsureUniqueIn("a", taken), "a_4", "list overload dedupes")
	gpEq(GPIdGen.gpEnsureUniqueIn("z", taken), "z", "list overload passes free ids through")

# The whole point of pairing them: an id that is sanitized but not deduped can still collide,
# so the realistic path is sanitize-then-ensure-unique.
# 二者配套使用的意义：只消毒不去重的 id 仍可能冲突，故真实路径是「先消毒、后去重」。
func gpTestSanitizeThenUnique() -> void:
	var taken: Array[String] = ["gate_valve", "gate_valve_2"]
	var isTaken: Callable = func(c: String) -> bool:
		return taken.has(c)
	gpEq(GPIdGen.gpEnsureUnique(GPIdGen.gpSanitize("gate valve"), isTaken), "gate_valve_3", "sanitize + dedupe")
