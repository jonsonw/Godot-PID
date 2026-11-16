extends "res://tests/gp_test.gd"
# Headless tests for the container v4 layer (ADR-41, revised 2026-11-09).
# 容器 v4 层的 headless 测试（ADR-41，2026-11-09 修订版）。
# WHY / 为何要这些测试：
# v4 is the ONLY container form (no v1-v3 tolerance). The three project-level sections
# (project_meta / members / sheet_sets) are the mount points for the project center UI,
# W14 identity and W16 encryption — a shape regression here would surface as broken UI
# weeks later instead of at the source. The write wire (project_io.gd -> gpStampV4) is
# asserted too: a stamp silently dropped from a refactor would leave every new archive
# in a deprecated shape.
# v4 是唯一容器形态（不做 v1–v3 宽容读）。三个工程级段（project_meta / members /
# sheet_sets）是项目中心 UI、W14 身份与 W16 加密的挂点——这里的形状回归会在数周后
# 以「UI 坏了」的形式浮出，而非在源头暴露。写路径接线（project_io.gd -> gpStampV4）
# 也被钉住：重构中悄悄丢掉盖戳会让每个新存档都落回废弃形态。

# Scratch archive for the write-wire cases.
# 写路径用例使用的临时存档。
const GP_TMP_PATH: String = "user://gp_test_container_v4.pid.json"

# Frozen member fixture (ADR-40 D1/D3/D4 field table).
# 冻结的成员样例（ADR-40 D1/D3/D4 字段表）。
func _gpMember(gpUser: String, gpRoles: Array) -> Dictionary:
	return {"user": gpUser, "roles": gpRoles, "enabled": true}

# Frozen sheet-set fixture (ADR-41 D1 grouping-only contract).
# 冻结的图纸集样例（ADR-41 D1 仅分组契约）。
func _gpSet(gpId: String, gpName: String, gpSheetIds: Array) -> Dictionary:
	return {"id": gpId, "name": gpName, "sheet_ids": gpSheetIds}

# A minimal v3-shaped container with two sheets, ready for stamping.
# 一个含两张图纸的最小 v3 形状容器，随时可盖戳。
func _gpBaseContainer() -> Dictionary:
	return {
		"kind": "project",
		"meta": {"title": "demo"},
		"sheets": [
			{"id": "sheet-1", "name": "PFD", "number": "01", "nodes": [{"instance_id": "a"}]},
			{"id": "sheet-2", "name": "P&ID", "number": "02", "nodes": []},
		],
	}


# ==================== stamp / 盖戳 ====================

# A stamped container carries the version key and all three sections.
# 盖戳后的容器应带版本键且三段齐备。
func gpTestStampProducesV4() -> void:
	var gpC: Dictionary = _gpBaseContainer()
	GPProjectContainerV4.gpStampV4(gpC)
	gpEq(int(gpC.get("container_version", 0)), GPProjectContainerV4.GP_CONTAINER_VERSION,
		"container_version must be stamped to 4")
	gpCheck(gpC.get("project_meta") is Dictionary, "project_meta section must exist as a dict")
	gpCheck(gpC.get("members") is Array, "members section must exist as an array")
	gpCheck(gpC.get("sheet_sets") is Array, "sheet_sets section must exist as an array")
	gpEq(gpC.get("members", []).size(), 0, "a fresh stamp fills members empty")
	gpEq(gpC.get("sheets", []).size(), 2, "stamping must not touch the sheet payload")


# Idempotence: stamp(stamp(d)) == stamp(d) — a double save must not drift.
# 幂等：盖两次与盖一次一致 —— 重复保存不得漂移。
func gpTestStampIsIdempotent() -> void:
	var gpA: Dictionary = _gpBaseContainer()
	GPProjectContainerV4.gpStampV4(gpA)
	var gpB: Dictionary = gpA.duplicate(true)
	GPProjectContainerV4.gpStampV4(gpA)
	GPProjectContainerV4.gpStampV4(gpB)
	GPProjectContainerV4.gpStampV4(gpB)
	gpCheck(gpA == gpB, "double stamping must produce the identical container")


# Existing section content survives a stamp (the writer may receive a container that
# already carries project-level data from the caller).
# 既有段内容在盖戳后应原样存活（写入方收到的容器可能已带调用方塞入的工程级数据）。
func gpTestStampPreservesExisting() -> void:
	var gpC: Dictionary = _gpBaseContainer()
	gpC["members"] = [_gpMember("alice", ["manager"])]
	gpC["project_meta"] = {"owner": "Merdeka"}
	GPProjectContainerV4.gpStampV4(gpC)
	var gpMembers: Array = gpC.get("members", []) as Array
	gpEq(gpMembers.size(), 1, "an existing members array must be kept verbatim")
	if gpMembers.size() == 1:
		gpEq(str((gpMembers[0] as Dictionary).get("user", "")), "alice",
			"the member entry should survive unchanged")
	gpEq(str((gpC.get("project_meta", {}) as Dictionary).get("owner", "")), "Merdeka",
		"existing project_meta must survive")
	# sheet_sets was absent, so the stamp must have created it.
	# sheet_sets 原本缺失，盖戳应补出它。
	gpCheck(gpC.get("sheet_sets") is Array, "the missing sheet_sets section must be created")


# ==================== wrap / 纯包装 ====================

# gpWrapV4 returns a new dict and overrides the sections with explicit arguments.
# gpWrapV4 应返回新字典，并以显式参数覆盖三段。
func gpTestWrapOverridesSections() -> void:
	var gpBase: Dictionary = _gpBaseContainer()
	var gpSets: Array = [_gpSet("set-a", "工艺包", ["sheet-1", "sheet-2"])]
	var gpOut: Dictionary = GPProjectContainerV4.gpWrapV4(gpBase,
		{"owner": "LEBTC"}, [_gpMember("bob", ["designer", "reviewer"])], gpSets)
	gpEq(str((gpOut.get("project_meta", {}) as Dictionary).get("owner", "")), "LEBTC",
		"explicit project_meta must override")
	gpEq((gpOut.get("members", []) as Array).size(), 1, "explicit members must override")
	gpEq((gpOut.get("sheet_sets", []) as Array).size(), 1, "explicit sheet_sets must override")
	# The input container must stay untouched (pure function contract).
	# 入参容器必须原封不动（纯函数契约）。
	gpCheck(not gpBase.has("container_version"), "the input dict must not be stamped")


# Explicit override wins over pre-existing section content.
# 显式参数优先于容器既有的段内容。
func gpTestWrapBeatsPreexisting() -> void:
	var gpC: Dictionary = _gpBaseContainer()
	gpC["members"] = [_gpMember("old", ["manager"])]
	var gpOut: Dictionary = GPProjectContainerV4.gpWrapV4(gpC, {},
		[_gpMember("new", ["designer"])], [])
	gpEq(str(((gpOut.get("members", []) as Array)[0] as Dictionary).get("user", "")),
		"new", "the explicit member list must replace the pre-existing one")


# ==================== validate / 校验 ====================

# A well-formed wrapped container validates clean.
# 形状良好的包装容器应校验通过。
func gpTestValidateAcceptsWellFormed() -> void:
	var gpC: Dictionary = GPProjectContainerV4.gpWrapV4(_gpBaseContainer(), {"owner": "x"},
		[_gpMember("alice", ["manager"]), _gpMember("dan", ["reviewer"])],
		[_gpSet("set-a", "工艺包", ["sheet-1", "sheet-2"])])
	var gpErrors: PackedStringArray = GPProjectContainerV4.gpValidateV4(gpC)
	gpEq(gpErrors.size(), 0, "a well-formed v4 container must validate clean: %s" % [gpErrors])


# Member shape violations: empty user, duplicate user, empty roles, unknown role.
# 成员形状违规：空用户名、重名、空角色、未知角色。
func gpTestValidateRejectsBadMembers() -> void:
	var gpCases: Array = [
		{"why": "empty user", "members": [{"user": "", "roles": ["manager"]}]},
		{"why": "duplicate user",
			"members": [_gpMember("a", ["manager"]), _gpMember("a", ["designer"])]},
		{"why": "empty roles", "members": [{"user": "a", "roles": []}]},
		{"why": "unknown role", "members": [{"user": "a", "roles": ["boss"]}]},
		{"why": "roles as bare string", "members": [{"user": "a", "roles": "manager"}]},
		{"why": "non-dict entry", "members": ["alice"]},
	]
	for gpCase in gpCases:
		var gpC: Dictionary = _gpBaseContainer()
		GPProjectContainerV4.gpStampV4(gpC)
		gpC["members"] = gpCase.get("members", []) as Array
		var gpErrors: PackedStringArray = GPProjectContainerV4.gpValidateV4(gpC)
		gpCheck(gpErrors.has(GPProjectContainerV4.GP_ERR_BAD_MEMBERS),
			"members violation (%s) must surface as container.bad_members" % [gpCase.get("why", "?")])


# Sheet-set violations: duplicate id, unknown sheet reference, missing name.
# 图纸集违规：id 重复、引用不存在的图纸、缺显示名。
func gpTestValidateRejectsBadSheetSets() -> void:
	var gpCases: Array = [
		{"why": "duplicate set id",
			"sets": [_gpSet("s", "A", ["sheet-1"]), _gpSet("s", "B", ["sheet-2"])]},
		{"why": "unknown sheet ref", "sets": [_gpSet("s", "A", ["sheet-99"])]},
		{"why": "empty name", "sets": [{"id": "s", "name": "", "sheet_ids": []}]},
	]
	for gpCase in gpCases:
		var gpC: Dictionary = _gpBaseContainer()
		GPProjectContainerV4.gpStampV4(gpC)
		gpC["sheet_sets"] = gpCase.get("sets", []) as Array
		var gpErrors: PackedStringArray = GPProjectContainerV4.gpValidateV4(gpC)
		gpCheck(gpErrors.has(GPProjectContainerV4.GP_ERR_BAD_SHEET_SETS),
			"sheet_sets violation (%s) must surface as container.bad_sheet_sets"
				% [gpCase.get("why", "?")])


# Version and meta-shape findings carry their own codes.
# 版本与元信息形状违规各带独立错误码。
func gpTestValidateRejectsBadVersionAndMeta() -> void:
	var gpC: Dictionary = _gpBaseContainer()
	var gpErrors: PackedStringArray = GPProjectContainerV4.gpValidateV4(gpC)
	gpCheck(gpErrors.has(GPProjectContainerV4.GP_ERR_BAD_VERSION),
		"a container without the v4 stamp must fail the version check")
	gpCheck(gpErrors.has(GPProjectContainerV4.GP_ERR_BAD_META),
		"a container without project_meta must fail the meta check")

	var gpBadMeta: Dictionary = _gpBaseContainer()
	GPProjectContainerV4.gpStampV4(gpBadMeta)
	gpBadMeta["project_meta"] = "oops"
	gpCheck(GPProjectContainerV4.gpValidateV4(gpBadMeta).has(
		GPProjectContainerV4.GP_ERR_BAD_META),
		"a non-dict project_meta must fail the meta check")


# ==================== sheet summaries / 图纸摘要 ====================

# Summaries project every sheet in container order with the fields the sheet manager
# list (图纸管理) needs — no graph rebuild, no UI types.
# 摘要应按容器顺序投影每张图纸，并带图纸管理列表所需的字段——不重建图、不碰 UI 类型。
func gpTestSheetSummariesFieldsAndOrder() -> void:
	var gpC: Dictionary = _gpBaseContainer()
	var gpOut: Array = GPProjectContainerV4.gpSheetSummaries(gpC)
	gpEq(gpOut.size(), 2, "one summary per sheet, in container order")
	if gpOut.size() == 2:
		var gpFirst: Dictionary = gpOut[0] as Dictionary
		gpEq(str(gpFirst.get("id", "")), "sheet-1", "the first summary must be sheet-1")
		gpEq(str(gpFirst.get("number", "")), "01", "the sheet number must be projected")
		gpEq(int(gpFirst.get("index", -1)), 0, "the index must be re-derived in order")
		gpEq(int(gpFirst.get("node_count", -1)), 1, "node_count must reflect the payload")
		var gpSecond: Dictionary = gpOut[1] as Dictionary
		gpEq(str(gpSecond.get("name", "")), "P&ID", "the sheet name must be projected")


# An empty container yields an empty summary list (the project center shows the
# "no sheets" state from data, not from a special case).
# 空容器应产出空摘要列表（项目中心的「无图纸」态由数据得出，而非特例分支）。
func gpTestSheetSummariesEmpty() -> void:
	gpEq(GPProjectContainerV4.gpSheetSummaries({}).size(), 0,
		"a container without sheets must summarise to an empty list")


# ==================== write wire / 写路径接线 ====================

# The multi-sheet writer must stamp v4 — this is the WIRING assertion, not the writer's.
# 多图纸写入器必须盖 v4 戳 —— 这是**接线**断言，而非写入器本身的断言。
func gpTestWriteSheetsProducesV4() -> void:
	var gpSheet1: GPSheet = GPSheet.gpNew("sheet-1", "PFD", 0)
	var gpSheet2: GPSheet = GPSheet.gpNew("sheet-2", "P&ID", 1)
	var gpR: GPIOResult = GPProjectIO.gpWriteSheetsResult([gpSheet1, gpSheet2], GP_TMP_PATH)
	gpCheck(gpR.gpIsOk(), "the multi-sheet save should succeed: " + gpR.gpToString())
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(GP_TMP_PATH)
	gpCheck(gpRead.gpIsOk(), "the written archive should parse back")
	if gpRead.gpIsOk():
		var gpDict: Dictionary = gpRead.gpPayload as Dictionary
		gpEq(int(gpDict.get("container_version", 0)), 4,
			"the archive on disk must carry container_version=4")
		gpCheck(gpDict.get("members") is Array, "the archive must carry the members section")
		gpCheck(gpDict.get("project_meta") is Dictionary,
			"the archive must carry the project_meta section")
		gpCheck(gpDict.get("sheet_sets") is Array,
			"the archive must carry the sheet_sets section")
	# Cleanup: remove the archive so later runs start clean.
	# 清理：删除存档，让后续用例从干净状态开始。
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GP_TMP_PATH))


# The v4 sections must NOT break the existing reader: a stamped archive loads back
# through gpReadSheetsWithLinks with its sheets intact.
# v4 各段不得破坏既有读取器：盖戳后的存档应能经 gpReadSheetsWithLinks 完整读回。
func gpTestReaderSurvivesV4Sections() -> void:
	var gpSheet1: GPSheet = GPSheet.gpNew("sheet-1", "PFD", 0)
	var gpSheet2: GPSheet = GPSheet.gpNew("sheet-2", "P&ID", 1)
	var gpWrite: GPIOResult = GPProjectIO.gpWriteSheetsResult([gpSheet1, gpSheet2], GP_TMP_PATH)
	gpCheck(gpWrite.gpIsOk(), "setup save should succeed: " + gpWrite.gpToString())
	var gpRead: GPIOResult = GPProjectIO.gpReadSheetsWithLinks(GP_TMP_PATH)
	gpCheck(gpRead.gpIsOk(), "the v4 archive must still load: " + gpRead.gpToString())
	if gpRead.gpIsOk():
		var gpPayload: Dictionary = gpRead.gpPayload as Dictionary
		gpEq((gpPayload.get("sheets", []) as Array).size(), 2,
			"both sheets must survive the v4 round-trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GP_TMP_PATH))
