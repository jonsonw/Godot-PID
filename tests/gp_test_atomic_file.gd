extends "res://tests/gp_test.gd"
# Headless tests for crash-safe writing (ADR-4) and the Ctrl+S accelerator (ADR-7).
# 崩溃安全写入（ADR-4）与 Ctrl+S 加速键（ADR-7）的 headless 测试。
# WHY / 为何要这些测试：
# an atomic writer's whole value is in what it does NOT leave behind — no truncated target,
# no orphaned temp file, and a usable previous copy. Those are exactly the properties that
# silently regress when someone "simplifies" the writer back to a direct store_string.
# 原子写入的全部价值在于它**不留下**什么 —— 没有截断的目标、没有孤儿临时文件、
# 且上一份副本可用。当有人把写入器「简化」回直接 store_string 时，最先悄悄退化的
# 正是这几点。

# Scratch archive used by the write cases.
# 写入用例使用的临时存档。
const GP_TMP_PATH: String = "user://gp_test_atomic.pid.json"


# Remove the scratch archive and every sibling artifact (.tmp / .bak).
# 删除临时存档及其所有伴生产物（.tmp / .bak）。
func _gpCleanup() -> void:
	for gpSuffix in ["", ".tmp", ".bak"]:
		var gpAbs: String = ProjectSettings.globalize_path(GP_TMP_PATH + gpSuffix)
		if FileAccess.file_exists(gpAbs):
			DirAccess.remove_absolute(gpAbs)


# A write leaves exactly one parseable file at the target and nothing else.
# 一次写入应在目标处留下恰好一个可解析文件，别无他物。
func gpTestWriteLeavesCleanTarget() -> void:
	_gpCleanup()
	var gpR: GPIOResult = GPAtomicFile.gpWriteAtomic(GP_TMP_PATH, "{\"a\":1}")
	gpCheck(gpR.gpIsOk(), "a plain write should succeed: " + gpR.gpToString())
	gpCheck(FileAccess.file_exists(GP_TMP_PATH), "the target file should exist")
	gpCheck(not GPAtomicFile.gpHasTempRemains(GP_TMP_PATH),
		"no temp file may be left behind after a successful write")
	var gpBack: GPIOResult = GPAtomicFile.gpReadText(GP_TMP_PATH)
	gpCheck(gpBack.gpIsOk() and (gpBack.gpPayload as String) == "{\"a\":1}",
		"the written text should read back unchanged")
	_gpCleanup()


# A second write keeps the previous good copy as .bak instead of destroying it.
# 第二次写入应把上一份完好副本保留为 .bak，而不是销毁它。
func gpTestSecondWriteKeepsBackup() -> void:
	_gpCleanup()
	var gpFirst: GPIOResult = GPAtomicFile.gpWriteAtomic(GP_TMP_PATH, "first")
	gpCheck(gpFirst.gpIsOk(), "the first write should succeed")
	var gpSecond: GPIOResult = GPAtomicFile.gpWriteAtomic(GP_TMP_PATH, "second")
	gpCheck(gpSecond.gpIsOk(), "the second write should succeed")

	var gpNow: GPIOResult = GPAtomicFile.gpReadText(GP_TMP_PATH)
	gpCheck((gpNow.gpPayload as String) == "second", "the target should hold the newest text")
	var gpBakPath: String = GPAtomicFile.gpBackupPath(GP_TMP_PATH)
	gpCheck(FileAccess.file_exists(gpBakPath),
		"the previous good copy should survive as .bak")
	if FileAccess.file_exists(gpBakPath):
		var gpOld: GPIOResult = GPAtomicFile.gpReadText(gpBakPath)
		gpCheck((gpOld.gpPayload as String) == "first", "the backup should hold the old text")
	_gpCleanup()


# A dictionary round-trips through the JSON writer with its structure intact.
# 字典经 JSON 写入器往返后结构应完好。
func gpTestWriteJsonAtomicRoundTrip() -> void:
	_gpCleanup()
	var gpData: Dictionary = {"meta": {"title": "t"}, "nodes": [{"instance_id": "n1"}]}
	var gpR: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(GP_TMP_PATH, gpData)
	gpCheck(gpR.gpIsOk(), "a JSON write should succeed: " + gpR.gpToString())
	var gpBack: GPIOResult = GPAtomicFile.gpReadJsonDict(GP_TMP_PATH)
	gpCheck(gpBack.gpIsOk(), "the JSON should read back: " + gpBack.gpToString())
	if gpBack.gpIsOk():
		var gpGot: Dictionary = gpBack.gpPayload as Dictionary
		gpEq(gpGot.get("nodes", []).size(), 1, "the nested array should survive")
		gpEq((gpGot.get("meta", {}) as Dictionary).get("title", ""), "t",
			"the nested dictionary should survive")
	_gpCleanup()


# Writing into a non-existent directory fails cleanly and leaves no artifacts.
# 写入不存在的目录应干净失败，且不留下任何产物。
func gpTestWriteToBadPath() -> void:
	var gpR: GPIOResult = GPAtomicFile.gpWriteAtomic(
		"user://gp_no_such_dir_xyz/nested/out", "{}")
	if gpR.gpIsOk():
		# Some platforms create intermediate directories; accept success but demand honesty.
		# 某些平台会自动创建中间目录；接受成功，但要求结果诚实。
		gpCheck(gpR.gpCode == "", "a successful write must not carry a failure code")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
			"user://gp_no_such_dir_xyz/nested/out"))
		return
	gpCheck(gpR.gpFailedWith("io.write_failed"),
		"a failed write should report io.write_failed, got " + gpR.gpToString())


# Reading distinguishes a missing file from a malformed one — the caller must be able to
# tell "wrong path" from "corrupted archive", because the recovery advice differs.
# 读取应区分文件缺失与文件损坏 —— 调用方必须能分辨「路径错了」与「存档坏了」，
# 因为两者的恢复建议不同。
func gpTestReadFailureTaxonomy() -> void:
	var gpMissing: GPIOResult = GPAtomicFile.gpReadJsonDict("user://gp_definitely_absent.json")
	gpCheck(gpMissing.gpFailedWith("io.open_failed"),
		"a missing file should fail with io.open_failed, got " + gpMissing.gpToString())

	_gpCleanup()
	var gpAbs: String = ProjectSettings.globalize_path(GP_TMP_PATH)
	var gpF: FileAccess = FileAccess.open(gpAbs, FileAccess.WRITE)
	gpCheck(gpF != null, "the scratch file should be writable")
	if gpF != null:
		gpF.store_string("{ not json")
		gpF.close()
	var gpBad: GPIOResult = GPAtomicFile.gpReadJsonDict(GP_TMP_PATH)
	gpCheck(gpBad.gpFailedWith("io.parse_failed"),
		"malformed JSON should fail with io.parse_failed, got " + gpBad.gpToString())
	_gpCleanup()


# The project writer must go through the atomic path (this is the wiring, not the writer).
# 工程写入器必须走原子路径（这是接线测试，而非写入器测试）。
# An archive that round-trips is not proof; the proof is that no .tmp survives and a .bak
# appears on the second save.
# 存档能往返并不构成证明；真正的证明是保存后**没有 .tmp 残留**且第二次保存出现 .bak。
func gpTestProjectSaveIsAtomic() -> void:
	_gpCleanup()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "LPUMP003", "P-1001", Vector2(10, 20)))

	var gpFirst: GPIOResult = GPProjectIO.gpWriteProjectResult(gpG, GP_TMP_PATH)
	gpCheck(gpFirst.gpIsOk(), "the first project save should succeed: " + gpFirst.gpToString())
	gpCheck(not GPAtomicFile.gpHasTempRemains(GP_TMP_PATH),
		"a project save must not leave a temp file behind")
	var gpSecond: GPIOResult = GPProjectIO.gpWriteProjectResult(gpG, GP_TMP_PATH)
	gpCheck(gpSecond.gpIsOk(), "the second project save should succeed")
	gpCheck(FileAccess.file_exists(GPAtomicFile.gpBackupPath(GP_TMP_PATH)),
		"a second project save should leave a .bak of the previous version")

	var gpRead: GPIOResult = GPProjectIO.gpReadProjectResult(GP_TMP_PATH)
	gpCheck(gpRead.gpIsOk(), "the saved project should load back")
	if gpRead.gpIsOk():
		var gpG2: GPPIDGraph = gpRead.gpPayload as GPPIDGraph
		gpEq(gpG2.gpNodes.size(), 1, "the node should survive the round-trip")
		if gpG2.gpNodes.size() == 1:
			gpEq(gpG2.gpNodes[0].gpTag, "P-1001", "the tag should survive the round-trip")
	_gpCleanup()


# The save accelerator must stay wired: a shortcut silently lost in a menu rebuild is a
# data-loss risk, because the user's muscle memory then hits a dead key.
# 保存加速键必须保持接线：在菜单重建中被静默丢掉的快捷键就是数据丢失风险，
# 因为用户的肌肉记忆随后会按下一个失效的键。
# Only static members are touched — instantiating GPPIDMenuBar would need the I18n autoload,
# which does not exist under `godot --headless --script`.
# 只触碰静态成员 —— 实例化 GPPIDMenuBar 需要 I18n 自动加载，而它在
# `godot --headless --script` 下并不存在。
func gpTestSaveShortcutIsDeclared() -> void:
	var gpSpecs: Dictionary = GPPIDMenuBar.GP_SHORTCUTS
	gpCheck(gpSpecs.has("file_save"), "Ctrl+S must be bound to the save action")
	gpCheck(gpSpecs.has("file_save_as"), "Ctrl+Shift+S must be bound to save-as")

	var gpSaveSpec: Array = gpSpecs.get("file_save", [])
	gpCheck(gpSaveSpec.size() == 2, "a shortcut spec is [keycode, with_shift]")
	if gpSaveSpec.size() == 2:
		gpEq(int(gpSaveSpec[0]), KEY_S, "save should be bound to the S key")
		gpEq(bool(gpSaveSpec[1]), false, "plain save must not require Shift")
	var gpAsSpec: Array = gpSpecs.get("file_save_as", [])
	if gpAsSpec.size() == 2:
		gpEq(bool(gpAsSpec[1]), true, "save-as must require Shift")


# The accelerator itself must be a real, global-firing InputEvent with the right modifiers.
# 加速键本身必须是真实、可全局触发的 InputEvent，且修饰键正确。
func gpTestSaveShortcutEventShape() -> void:
	var gpSc: Shortcut = GPPIDMenuBar._gpMakeShortcut(KEY_S, false)
	gpCheck(gpSc != null, "a Shortcut resource should be built")
	if gpSc == null:
		return
	var gpEvents: Array = gpSc.events
	gpCheck(gpEvents.size() >= 1, "the shortcut must carry at least one event")
	if gpEvents.size() < 1:
		return
	var gpE: InputEventKey = gpEvents[0] as InputEventKey
	gpCheck(gpE != null, "the event should be an InputEventKey")
	if gpE == null:
		return
	gpEq(gpE.keycode, KEY_S, "the event should target the S key")
	gpCheck(not gpE.shift_pressed, "plain save must not carry Shift")
	# macOS shows Cmd first so the menu label reads ⌘S; elsewhere Ctrl is the accelerator.
	# macOS 把 Cmd 放首位以便菜单标签显示 ⌘S；其他平台以 Ctrl 为加速键。
	if OS.get_name() == "macOS":
		gpCheck(gpE.meta_pressed, "on macOS the primary modifier should be Cmd")
	else:
		gpCheck(gpE.ctrl_pressed, "on Win/Linux the primary modifier should be Ctrl")
