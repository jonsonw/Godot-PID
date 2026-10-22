extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# B3: the addon loader (scan → instantiate → isolate → collect).
# B3：插件加载器（扫描 → 实例化 → 隔离 → 收集）。
#
# The fixtures under tests/fixtures/addons/ are the four states a real addon can be in:
# good / duplicate id / wrong type / broken at CALL time. The broken one is the interesting case:
# GDScript has no try/catch, so the loader's containment is "the error aborts that call, the scan
# continues" — and THIS test is what proves the scan really continues.
# tests/fixtures/addons/ 下的夹具覆盖真实插件的四种状态：好 / id 重复 / 类型不对 / 调用时出错。
# 坏的那个才是重点：GDScript 没有 try/catch，加载器能给的隔离是「错误中止那一次调用、扫描继续」——
# 而本测试正是证明「扫描确实继续」的地方。

const GP_FIXTURES: String = "res://tests/fixtures/addons"


func gpTestGoodAddonLoads() -> void:
	var gpL: GPAddonLoader = GPAddonLoader.new()
	var gpAddons: Array[GPIPIDAddon] = gpL.gpScan(GP_FIXTURES)
	var gpNames: Array[String] = gpL.gpLoadedNames()
	gpCheck(gpNames.has("fixture.good"), "好插件被加载 / the good addon is loaded")
	# Two well-formed fixtures exist (v1 + v2, see gp_test_addon_contract.gd); the refused ones must
	# not add to this count.
	# 目前有两个格式正确的夹具（v1 + v2，见 gp_test_addon_contract.gd）；被拒的那些不得计入。
	gpEq(gpAddons.size(), 2, "两个好插件成功 / the two good addons survive")


func gpTestDuplicateIdRefused() -> void:
	var gpL: GPAddonLoader = GPAddonLoader.new()
	gpL.gpScan(GP_FIXTURES)
	var gpRefused: bool = false
	for gpD in gpL.gpDiagnostics:
		if str(gpD.get("reason", "")) == "duplicate_id":
			gpRefused = true
	gpCheck(gpRefused, "重复 id 被拒 / the duplicate id is refused")


func gpTestWrongTypeRefused() -> void:
	var gpL: GPAddonLoader = GPAddonLoader.new()
	gpL.gpScan(GP_FIXTURES)
	var gpRefused: bool = false
	for gpD in gpL.gpDiagnostics:
		if str(gpD.get("reason", "")) == "not_an_addon":
			gpRefused = true
	gpCheck(gpRefused, "非插件脚本被拒 / a non-addon script is refused")


func gpTestRefusedCandidatesDoNotStopTheScan() -> void:
	var gpL: GPAddonLoader = GPAddonLoader.new()
	var gpAddons: Array[GPIPIDAddon] = gpL.gpScan(GP_FIXTURES)
	# Refused candidates (wrong type / duplicate id) must not abort the loop: the good addon is
	# still found, and every candidate still gets a diagnostic row.
	# 被拒的候选（类型不对 / id 重复）不得中断循环：好插件仍被找到，每个候选仍有诊断行。
	gpCheck(gpAddons.size() >= 1, "扫描继续并找到好插件 / the scan continues and finds the good one")
	gpCheck(gpL.gpDiagnostics.size() >= 3, "每个候选都有诊断 / every candidate gets a diagnostic")


func gpTestCollectGroupsInjections() -> void:
	var gpL: GPAddonLoader = GPAddonLoader.new()
	gpL.gpScan(GP_FIXTURES)
	var gpCollected: Dictionary = gpL.gpCollect()
	gpEq((gpCollected.get("tools", []) as Array).size(), 1, "收集到一个工具 / one tool collected")
	gpEq((gpCollected.get("panels", []) as Array).size(), 1, "收集到一个面板 / one panel collected")
	gpEq((gpCollected.get("exporters", []) as Array).size(), 0, "该插件没声明导出器 / no exporters here")


func gpTestMissingDirectoryIsSafe() -> void:
	var gpL: GPAddonLoader = GPAddonLoader.new()
	gpEq(gpL.gpScan("res://no/such/dir").size(), 0, "目录不存在时返回空 / a missing dir yields nothing")
	gpCheck(not gpL.gpAllFailed(), "空目录不算全失败 / an empty dir is not a failure")


func gpTestAllFailedOnlyWhenSomethingFailed() -> void:
	var gpL: GPAddonLoader = GPAddonLoader.new()
	gpL.gpScan(GP_FIXTURES)
	gpCheck(not gpL.gpAllFailed(), "有好插件时不算全失败 / with a good addon it is not all-failed")
