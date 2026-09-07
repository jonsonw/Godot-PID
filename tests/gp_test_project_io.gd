extends "res://tests/gp_test.gd"
# Headless regression tests for the GPIOResult-typed project IO API (M1).
# GPIOResult 类型化工程 IO 接口的 headless 回归测试（M1）。
# Goal: prove that save/load failures now report WHY they failed (a machine-readable
# gpCode plus an i18n key) instead of collapsing into a bare int or a silent null.
# 目标：证明存读失败现在能说明「为何」失败（机器可读 gpCode + i18n 键），
# 而不再退化为裸 int 或静默 null。

# Scratch file used by the round-trip test (already carries the canonical extension).
# 往返测试使用的临时文件（已带规范扩展名）。
const GP_TMP_PATH: String = "user://gp_test_project_io.pid.json"


# Build a two-node / one-edge graph used by several cases below.
# 构造供后续多个用例使用的两节点 / 一边图。
func _gpSampleGraph() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-101", Vector2(10, 20)))
	gpG.gpAddNode(gpG.gpNewNode("n2", "tank", "V-101", Vector2(50, 20)))
	gpG.gpAddEdge(gpG.gpNewEdge("e1", "n1", "n2"))
	return gpG


# Delete the scratch file so repeated runs stay isolated.
# 删除临时文件，使重复运行保持隔离。
func _gpCleanup() -> void:
	var gpAbs: String = ProjectSettings.globalize_path(GP_TMP_PATH)
	if FileAccess.file_exists(gpAbs):
		DirAccess.remove_absolute(gpAbs)


# A save/load round-trip succeeds and the reconstructed graph arrives in gpPayload.
# 存读往返应成功，且重建出的图由 gpPayload 带回。
func gpTestWriteReadRoundTrip() -> void:
	_gpCleanup()
	var gpWrite: GPIOResult = GPProjectIO.gpWriteProjectResult(_gpSampleGraph(), GP_TMP_PATH)
	gpCheck(gpWrite.gpIsOk(), "write should report success: " + gpWrite.gpToString())
	if not gpWrite.gpIsOk():
		_gpCleanup()
		return

	var gpRead: GPIOResult = GPProjectIO.gpReadProjectResult(GP_TMP_PATH)
	gpCheck(gpRead.gpIsOk(), "read should report success: " + gpRead.gpToString())
	if gpRead.gpIsOk():
		var gpG2: GPPIDGraph = gpRead.gpPayload as GPPIDGraph
		gpCheck(gpG2 != null, "payload should carry a GPPIDGraph")
		if gpG2 != null:
			gpCheck(gpG2.gpNodes.size() == 2, "both nodes should survive the round-trip")
			gpCheck(gpG2.gpEdges.size() == 1, "the edge should survive the round-trip")
			if gpG2.gpNodes.size() == 2:
				gpCheck(gpG2.gpNodes[0].gpPosition == Vector2(10, 20),
					"node position should survive the round-trip")
	_gpCleanup()


# Reading a missing file fails with the specific "io.open_failed" code.
# 读取缺失文件应以明确的 "io.open_failed" 码失败。
func gpTestReadMissingFile() -> void:
	var gpR: GPIOResult = GPProjectIO.gpReadProjectResult("user://gp_definitely_missing.pid.json")
	gpCheck(not gpR.gpIsOk(), "reading a missing file should fail")
	gpCheck(gpR.gpFailedWith("io.open_failed"),
		"a missing file should fail with io.open_failed, got " + gpR.gpToString())
	gpCheck(gpR.gpMessageKey != "", "a failure should carry an i18n message key")


# Reading malformed JSON fails with "io.parse_failed" (distinct from a missing file).
# 读取损坏 JSON 应以 "io.parse_failed" 失败（与文件缺失区分开）。
# NOTE: Godot prints "ERROR: Parse JSON failed" from JSON.parse_string itself — that log line
# is EXPECTED in this case and does NOT indicate a test failure.
# 注意：Godot 会由 JSON.parse_string 自身打印 "ERROR: Parse JSON failed"——该日志在本用例中
# 是预期出现的，并不代表测试失败。
func gpTestReadMalformedJson() -> void:
	_gpCleanup()
	var gpAbs: String = ProjectSettings.globalize_path(GP_TMP_PATH)
	var gpF: FileAccess = FileAccess.open(gpAbs, FileAccess.WRITE)
	gpCheck(gpF != null, "scratch file should be writable")
	if gpF != null:
		gpF.store_string("{ this is not valid json")
		gpF.close()

	var gpR: GPIOResult = GPProjectIO.gpReadProjectResult(GP_TMP_PATH)
	gpCheck(not gpR.gpIsOk(), "reading malformed JSON should fail")
	gpCheck(gpR.gpFailedWith("io.parse_failed"),
		"malformed JSON should fail with io.parse_failed, got " + gpR.gpToString())
	_gpCleanup()


# Writing into a non-existent directory fails with "io.write_failed".
# 写入不存在的目录应以 "io.write_failed" 失败。
func gpTestWriteToBadPath() -> void:
	var gpR: GPIOResult = GPProjectIO.gpWriteProjectResult(
		_gpSampleGraph(), "user://gp_no_such_dir_xyz/nested/out")
	if not gpR.gpIsOk():
		gpCheck(gpR.gpFailedWith("io.write_failed"),
			"a failed write should report io.write_failed, got " + gpR.gpToString())
	else:
		# Some platforms create intermediate directories; accept success but require it be honest.
		# 某些平台会自动创建中间目录；接受成功，但要求结果诚实。
		gpCheck(gpR.gpCode == "", "a successful write must not carry a failure code")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
			"user://gp_no_such_dir_xyz/nested/out.pid.json"))


# gpSuccessWith carries the payload; gpSuccess leaves it null.
# gpSuccessWith 携带数据；gpSuccess 的 payload 为 null。
func gpTestPayloadConventions() -> void:
	var gpWith: GPIOResult = GPIOResult.gpSuccessWith(_gpSampleGraph(), "io.loaded")
	gpCheck(gpWith.gpIsOk(), "gpSuccessWith should be a success")
	gpCheck(gpWith.gpPayload != null, "gpSuccessWith should carry the payload")
	gpCheck(gpWith.gpPayload is GPPIDGraph, "the payload should preserve its concrete type")

	var gpPlain: GPIOResult = GPIOResult.gpSuccess("io.saved")
	gpCheck(gpPlain.gpIsOk(), "gpSuccess should be a success")
	gpCheck(gpPlain.gpPayload == null, "gpSuccess should leave the payload null")
