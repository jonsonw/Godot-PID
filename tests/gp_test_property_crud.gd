extends "res://tests/gp_test.gd"
# Rev.3 stage 1.5 (R2 / D7): instance-level custom property CRUD.
# Rev.3 阶段 1.5（R2 / D7）：实例级自定义属性增删改。
#
# What is pinned here / 此处钉住的行为：
#   * a RENAME moves the value in ONE undo step (never "write new + erase old" two steps);
#     a rename is refused when the old key is missing or the new key already holds a value.
#   * an ADD creates the key even with an EMPTY value (a custom key has no library default to
#     fall back to), refuses an existing key, and is undoable/redoable.
#   * the DELETE rides the existing "empty value erases the key" semantics.
#   * the permission stub gates BOTH service entry points (a gate that cannot fail is not a gate).
#   * a custom entry survives the save/reopen round-trip (data sovereignty).
#   * 「改名」在**一个**撤销步内搬移取值（绝非「写新 + 删旧」两步）；旧键缺失或新键已有取值时拒绝。
#   * 「新增」即使取值为空也创建键（自定义键没有可回落的库默认值）、拒绝已存在的键、可撤销 / 重做。
#   * 「删除」沿用既有「空取值即擦除键」语义。
#   * 权限口子闸控**两个**服务入口（不可能失败的闸门不叫闸门）。
#   * 自定义条目在保存 / 重开往返后存活（数据主权）。

const GP_TMP: String = "user://gp_test_property_crud.pid.json"


func _gpGraph() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = gpG.gpNewNode("N1", "LPUMP003", "P-1001", Vector2(0, 0))
	gpN.gpProps["legacy_kw"] = 7.5
	gpG.gpAddNode(gpN)
	return gpG


func _gpService(gpG: GPPIDGraph) -> GPEditService:
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), GPTagRegistry.new())
	return gpSvc


func _gpCleanup() -> void:
	var gpAbs: String = ProjectSettings.globalize_path(GP_TMP)
	if FileAccess.file_exists(gpAbs):
		DirAccess.remove_absolute(gpAbs)


# ---- rename / 改名 ----

func gpTestRenameMovesValueAsOneUndoStep() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpSvc: GPEditService = _gpService(gpG)
	gpCheck(gpSvc.gpRenameProperty("N1", "legacy_kw", "legacy_k2"),
		"the rename is accepted")
	var gpN: GPPIDNode = gpG.gpGetNode("N1")
	gpCheck(not gpN.gpProps.has("legacy_kw"), "the old key is gone")
	gpEq(float(gpN.gpProps.get("legacy_k2", 0.0)), 7.5, "the value moved verbatim")
	# ONE undo step rewinds BOTH sides of the move — the proof that it was one command.
	# 一个撤销步同时回退搬移的两侧 —— 这正是一条命令的证明。
	gpCheck(gpSvc.gpUndo(), "undo succeeds")
	gpCheck(gpN.gpProps.has("legacy_kw"), "undo restores the old key")
	gpCheck(not gpN.gpProps.has("legacy_k2"), "undo removes the new key")
	gpEq(float(gpN.gpProps.get("legacy_kw", 0.0)), 7.5, "and the value is back verbatim")
	gpCheck(gpSvc.gpRedo(), "redo succeeds")
	gpCheck(not gpN.gpProps.has("legacy_kw"), "redo re-moves the old key away")
	gpEq(float(gpN.gpProps.get("legacy_k2", 0.0)), 7.5, "redo re-applies the value")


func gpTestRenameRefusals() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpSvc: GPEditService = _gpService(gpG)
	gpCheck(not gpSvc.gpRenameProperty("N1", "no_such_key", "anything"),
		"renaming a missing key is refused")
	gpEq(gpSvc.gpLastRefusal, "adhoc.err_missing", "the refusal names the cause")
	gpCheck(not gpSvc.gpRenameProperty("N1", "legacy_kw", "legacy_kw"),
		"renaming onto the same key is refused")
	var gpN: GPPIDNode = gpG.gpGetNode("N1")
	gpN.gpProps["taken"] = 1
	gpCheck(not gpSvc.gpRenameProperty("N1", "legacy_kw", "taken"),
		"renaming onto a key that already holds a value is refused (no silent overwrite)")
	gpEq(gpSvc.gpLastRefusal, "adhoc.err_exists", "the refusal names the collision")
	gpCheck(gpN.gpProps.has("legacy_kw"), "the refused rename left the data untouched")


# ---- add / 新增 ----

func gpTestAddCreatesEntryEvenWhenEmpty() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpSvc: GPEditService = _gpService(gpG)
	gpCheck(gpSvc.gpAddProperty("N1", "custom_1", ""),
		"an explicitly created custom entry may hold an empty value")
	var gpN: GPPIDNode = gpG.gpGetNode("N1")
	gpCheck(gpN.gpProps.has("custom_1"), "the key exists in gpProps")
	gpCheck(gpSvc.gpUndo(), "the add is undoable")
	gpCheck(not gpN.gpProps.has("custom_1"), "undo removes the created key")
	gpCheck(gpSvc.gpRedo(), "and redoable")
	gpCheck(gpN.gpProps.has("custom_1"), "redo re-creates it")
	# The OLD semantics must survive for the default path: setting "" on the entry ERASES it
	# (that is the delete ride-along), while the add path was the only one allowed to store "".
	# 默认路径的旧语义必须原样存活：对该条目写 "" 即擦除（删除正是搭这一语义的车），
	# 而「允许存空」只属于新增路径。
	gpCheck(gpSvc.gpSetProperty("N1", "custom_1", ""), "setting empty erases (delete semantics)")
	gpCheck(not gpN.gpProps.has("custom_1"), "the key is gone after the erase")


func gpTestAddRefusesExistingKey() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpSvc: GPEditService = _gpService(gpG)
	gpCheck(not gpSvc.gpAddProperty("N1", "legacy_kw", 1.0),
		"adding a key that already holds a value is refused")
	gpEq(gpSvc.gpLastRefusal, "adhoc.err_exists", "the refusal names the collision")
	gpEq(float(gpG.gpGetNode("N1").gpProps.get("legacy_kw", 0.0)), 7.5,
		"the refused add left the value untouched")


# ---- permission gate / 权限口子 ----

func gpTestPermissionGateDeniesCrud() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpSvc: GPEditService = _gpService(gpG)
	# The seam is flipped by hand and RESTORED immediately after — a leaked deny would poison
	# every later test in the run.
	# 接缝由测试手工翻转、并在断言后**立即**还原 —— 泄漏的拒绝态会毒化本次运行的所有后续测试。
	GPPermissions.gpForceDeny = true
	gpCheck(not gpSvc.gpAddProperty("N1", "blocked", ""),
		"the gate denies the add")
	gpCheck(not gpSvc.gpRenameProperty("N1", "legacy_kw", "moved"),
		"the gate denies the rename")
	gpEq(gpSvc.gpLastRefusal, "perm.err_props", "both refusals name the permission")
	GPPermissions.gpForceDeny = false
	gpCheck(GPPermissions.gpCanEditProps(), "restoring the seam reopens the gate")
	# and the data is untouched by the denied attempts / 被拒的尝试不动数据
	gpCheck(gpG.gpGetNode("N1").gpProps.has("legacy_kw"), "the deny left the data untouched")
	gpCheck(not gpG.gpGetNode("N1").gpProps.has("blocked"), "and created nothing")


# ---- persistence / 持久化 ----

func gpTestCustomEntrySurvivesSaveReopen() -> void:
	_gpCleanup()
	var gpG: GPPIDGraph = _gpGraph()
	var gpSvc: GPEditService = _gpService(gpG)
	gpCheck(gpSvc.gpAddProperty("N1", "custom_1", "user typed"), "the entry is created")
	gpCheck(gpSvc.gpRenameProperty("N1", "custom_1", "user_note"), "and renamed")
	var gpW: GPIOResult = GPProjectIO.gpWriteProjectResult(gpG, GP_TMP)
	gpCheck(gpW.gpIsOk(), "write should succeed: " + gpW.gpToString())
	if not gpW.gpIsOk():
		_gpCleanup()
		return
	var gpR: GPIOResult = GPProjectIO.gpReadProjectResult(GP_TMP)
	gpCheck(gpR.gpIsOk(), "read should succeed: " + gpR.gpToString())
	if not gpR.gpIsOk():
		_gpCleanup()
		return
	var gpN2: GPPIDNode = (gpR.gpPayload as GPPIDGraph).gpGetNode("N1")
	gpCheck(gpN2 != null, "the node survived the round-trip")
	if gpN2 != null:
		gpEq(str(gpN2.gpProps.get("user_note", "")), "user typed",
			"the renamed custom entry (key AND value) survives save/reopen")
		gpCheck(not gpN2.gpProps.has("custom_1"), "the old key stayed gone")
	_gpCleanup()
