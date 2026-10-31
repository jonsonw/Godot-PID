class_name GPDrcRule
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# One DRC rule descriptor (ADR-39 D2). Data only: what the rule is, how bad its default finding
# is, where it applies, and which pure function implements it.
# 一条 DRC 规则描述符（ADR-39 D2）。纯数据：规则是什么、默认多严重、作用范围、由哪个纯函数实现。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var gpId: String = ""
var gpFamily: String = ""
var gpDefaultSeverity: String = "warning"
var gpScope: String = "sheet"
var gpPhase: int = 1
var gpMessageKeys: Array[String] = []
var gpFixHint: String = ""
var gpRequires: String = ""
var gpLegacy: bool = false
var gpCheck: Callable = Callable()


static func gpMake(gpIdIn: String, gpFamilyIn: String, gpSeverityIn: String, gpPhaseIn: int,
		gpCheckIn: Callable, gpMessageKeyIn: String = "", gpHintIn: String = "",
		gpLegacyIn: bool = false) -> GPDrcRule:
	var gpR: GPDrcRule = GPDrcRule.new()
	gpR.gpId = gpIdIn
	gpR.gpFamily = gpFamilyIn
	gpR.gpDefaultSeverity = gpSeverityIn
	gpR.gpPhase = gpPhaseIn
	gpR.gpCheck = gpCheckIn
	if gpMessageKeyIn != "":
		gpR.gpMessageKeys = [gpMessageKeyIn]
	gpR.gpFixHint = gpHintIn
	gpR.gpLegacy = gpLegacyIn
	return gpR


# Human family label key, e.g. "drc.family.topo".
# 族标签 i18n 键。
func gpFamilyKey() -> String:
	return "drc.family." + gpFamily


# Run this rule. A legacy descriptor has no callable: its findings come from GPRulePack and are
# filtered by the engine.
# 执行本规则。legacy 描述符无 callable：其发现来自 GPRulePack，由引擎过滤。
func gpRun(gpSnap: GPDrcSnapshot, gpCfg: Dictionary) -> Array[GPFinding]:
	if gpLegacy or not gpCheck.is_valid():
		return []
	return gpCheck.call(gpSnap, gpCfg) as Array[GPFinding]
