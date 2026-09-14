extends "res://tests/gp_test.gd"
# 架构优化 §3 第 3 项：清理 main_window.gd 遗留旧（平铺）工具栏代码后的回归钉。
# Architecture §3 item 3: regression pin after clearing main_window.gd's legacy flat-toolbar code.
#
# 已删除的死代码：
#   - 字段 var gpToolBar: HBoxContainer / var gpToolBtns: Dictionary（从未赋值，仅被 Ribbon==null
#     的死分支引用）
#   - 三个只做转发的包装方法 _gpAddToolBtn / _gpAddSep / _gpModeForAction（无人调用，转给
#     ribbon_coordinator 上同样已删除的死方法）
#   - ribbon_coordinator 中的对称死代码（gpSyncToolBar 的 gpToolBar 回退分支、gpAddSep /
#     gpAddToolBtn / gpModeForAction）
#
# 本测试把「源码表层」钉死：若有人把 _gpAddToolBtn / _gpAddSep / _gpModeForAction 的「定义」
# 重新加回 main_window.gd，测试立即失败。字段（gpToolBar / gpToolBtns）的删除由编译扫描
# （门 4）兜底——任何对 gpHost.gpToolBar 的重新引用都是硬编译错误。
# This suite pins the source surface: re-introducing any of those three method definitions fails
# the test. The field removal (gpToolBar / gpToolBtns) is guarded by the compile scan (gate 4) —
# any re-reference to gpHost.gpToolBar is a hard compile error.

# 直接读文件源码做子串校验，避开「Script.get_method_list() 不暴露用户方法」这一反射陷阱。
# Read the source directly via FileAccess; avoids the reflection pitfall where
# Script.get_method_list() does not surface user-defined methods.
func _gpReadFile(gpPath: String) -> String:
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpF == null:
		return ""
	var gpTxt: String = gpF.get_as_text()
	gpF.close()
	return gpTxt


func gpTestLegacyToolbarWrappersRemoved() -> void:
	var gpSrc: String = _gpReadFile("res://src/ui/shell/main_window.gd")
	gpCheck(gpSrc.length() > 0, "main_window.gd 可读 / main_window.gd reads")
	# 防回退：三个旧工具栏遗留方法的「定义」必须保持已删除。
	# Regression guard: these three legacy toolbar method definitions must stay removed.
	gpCheck(!("_gpAddToolBtn(" in gpSrc), "遗留 _gpAddToolBtn 必须已清理 / _gpAddToolBtn definition must be gone")
	gpCheck(!("_gpAddSep(" in gpSrc), "遗留 _gpAddSep 必须已清理 / _gpAddSep definition must be gone")
	gpCheck(!("_gpModeForAction(" in gpSrc), "遗留 _gpModeForAction 必须已清理 / _gpModeForAction definition must be gone")
	# 正向钉：活的 Ribbon 转发方法必须仍在，证明未误删活动代码。
	# Positive pin: the live Ribbon-forwarding methods must remain.
	gpCheck(("_gpOnToolBarPressed(" in gpSrc), "_gpOnToolBarPressed 仍在 / still present")
	gpCheck(("_gpSyncToolBar(" in gpSrc), "_gpSyncToolBar 仍在 / still present")
	gpCheck(("_gpBuildRibbon(" in gpSrc), "_gpBuildRibbon 仍在 / still present")
