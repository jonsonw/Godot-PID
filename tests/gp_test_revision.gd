extends "res://tests/gp_test.gd"
# Headless regression tests for the content revision hash chain (W14 / ADR-40 D6 / F02).
# 内容修订哈希链的 headless 回归测试（W14 / ADR-40 D6 / F02）。
# Acceptance from Todo F02: same document -> same revision; any byte tampering detectable;
# parent chain complete; stamp/verify work through the real project_io round-trip.
# Todo F02 验收：同文档同修订；任何字节篡改可检；parent 链完整；盖章/校验经真实
# project_io 往返成立。

const GP_TMP_PATH: String = "user://gp_test_revision.pid.json"


# A small container shaped like a real project payload.
# 一个形状贴近真实工程载荷的小容器。
func _gpSampleContainer() -> Dictionary:
	return {
		"container_version": 4,
		"meta": {"title": "demo", "sheets": 1},
		"sheets": [{"id": "s1", "name": "Sheet 1", "nodes": [1, 2, 3]}],
	}


# Remove the scratch archive so repeated runs stay isolated.
# 删除临时存档，使重复运行保持隔离。
func _gpCleanup() -> void:
	var gpAbs: String = ProjectSettings.globalize_path(GP_TMP_PATH)
	if FileAccess.file_exists(gpAbs):
		DirAccess.remove_absolute(gpAbs)


# Same document + same parent -> identical revision (F02 acceptance #1).
# 同文档 + 同 parent -> 相同修订（F02 验收一）。
func gpTestSameDocSameRevision() -> void:
	var gpA: String = GPRevision.gpComputeRevision(_gpSampleContainer(), "")
	var gpB: String = GPRevision.gpComputeRevision(_gpSampleContainer(), "")
	gpEq(gpB, gpA, "the same document and parent must hash identically")
	gpCheck(gpA.length() == 64, "a sha256 hex digest must be 64 chars, got " + str(gpA.length()))


# One change -> a different revision (F02 acceptance #2, positive form).
# 一处改动 -> 不同修订（F02 验收二的正向形式）。
func gpTestChangeChangesRevision() -> void:
	var gpA: Dictionary = _gpSampleContainer()
	var gpB: Dictionary = _gpSampleContainer()
	(gpB["sheets"] as Array)[0] = {"id": "s1", "name": "Sheet 1", "nodes": [1, 2, 3, 4]}
	var gpRevA: String = GPRevision.gpComputeRevision(gpA, "")
	var gpRevB: String = GPRevision.gpComputeRevision(gpB, "")
	gpCheck(gpRevA != gpRevB, "changing one node in the payload must change the revision")


# The canonical form is stable across a JSON round-trip, INCLUDING the int -> float
# coercion Godot applies to every JSON number.
# 规范形在 JSON 往返后保持稳定——包括 Godot 对所有 JSON 数字的 int -> float 强转。
func gpTestCanonicalStableAcrossJsonRoundTrip() -> void:
	var gpDoc: Dictionary = _gpSampleContainer()
	var gpText: String = JSON.stringify(gpDoc, "", true)
	var gpParsed: Variant = JSON.parse_string(gpText)
	gpCheck(gpParsed is Dictionary, "the round-trip payload must parse back to a Dictionary")
	if gpParsed is Dictionary:
		gpEq(GPRevision.gpCanonicalJson(gpParsed), GPRevision.gpCanonicalJson(gpDoc),
			"canonical form must be identical after a JSON round-trip")


# Key order must not matter: two dicts built in different orders hash identically.
# 键序不应影响哈希：不同构建顺序的字典哈希一致。
func gpTestCanonicalKeyOrderIndependent() -> void:
	var gpA: Dictionary = {"alpha": 1, "beta": {"x": 1, "y": 2}}
	var gpB: Dictionary = {"beta": {"y": 2, "x": 1}, "alpha": 1}
	gpEq(GPRevision.gpCanonicalJson(gpB), GPRevision.gpCanonicalJson(gpA),
		"key order must not affect the canonical form")


# Header keys are excluded from the hash: stamping onto the same payload twice with the
# same parent yields the same revision, and verify accepts the stamped container.
# 头部键不参与哈希：对同一载荷以同一 parent 盖两次章得到相同修订，
# 且校验接受盖章后的容器。
func gpTestStampExcludesHeaderKeys() -> void:
	var gpDoc: Dictionary = _gpSampleContainer()
	var gpRev1: String = GPRevision.gpStampRevision(gpDoc, "local", "2026-11-16T09:00:00")
	# A second stamp uses the first as parent, so its value differs — but verify must pass.
	# 第二次盖章以第一次为 parent，值必然不同——但校验必须通过。
	var gpRev2: String = GPRevision.gpStampRevision(gpDoc, "local", "2026-11-16T09:05:00")
	gpCheck(gpRev1 != gpRev2, "a second stamp must chain to the first (new parent)")
	var gpErrors: PackedStringArray = GPRevision.gpVerify(gpDoc)
	gpEq(gpErrors.size(), 0,
		"the stamped container must verify clean, got " + str(gpErrors))


# Tamper detection: flip one byte in the payload after stamping -> revision.bad_hash.
# 篡改检测：盖章后翻转载荷中的一个字节 -> revision.bad_hash。
func gpTestTamperDetectable() -> void:
	var gpDoc: Dictionary = _gpSampleContainer()
	GPRevision.gpStampRevision(gpDoc, "local", "2026-11-16T09:00:00")
	(gpDoc["meta"] as Dictionary)["title"] = "tampered"
	var gpErrors: PackedStringArray = GPRevision.gpVerify(gpDoc)
	gpCheck(gpErrors.has(GPRevision.GP_ERR_BAD_HASH),
		"a tampered payload must report revision.bad_hash, got " + str(gpErrors))


# Parent chain integrity: a broken middle link reports revision.bad_chain (F02 acceptance #3).
# parent 链完整性：中间链断裂报 revision.bad_chain（F02 验收三）。
func gpTestChainIntegrity() -> void:
	var gpDoc: Dictionary = _gpSampleContainer()
	var gpR1: String = GPRevision.gpStampRevision(gpDoc, "alice", "2026-11-16T09:00:00", [])
	var gpR2: String = GPRevision.gpStampRevision(gpDoc, "bob", "2026-11-16T09:05:00",
		gpDoc["revisions"] as Array)
	gpCheck(gpR1 != gpR2, "two stamps must produce two distinct revisions")
	var gpList: Array = gpDoc["revisions"] as Array
	gpEq(gpList.size(), 2, "the revision list should carry both entries")
	gpEq(str((gpList[1] as Dictionary).get("parent", "")), gpR1,
		"the second entry must chain to the first revision")
	gpEq(GPRevision.gpVerify(gpDoc).size(), 0, "a two-entry chain must verify clean")
	# Break the middle link.
	# 弄断中间链。
	(gpList[1] as Dictionary)["parent"] = "forged"
	var gpErrors: PackedStringArray = GPRevision.gpVerify(gpDoc)
	gpCheck(gpErrors.has(GPRevision.GP_ERR_BAD_CHAIN),
		"a broken chain must report revision.bad_chain, got " + str(gpErrors))


# The header revision must equal the last entry's revision (the guard against a spliced
# header pointing at content that was never stamped).
# 头部修订必须等于最后条目的修订（防「头部指向从未盖章内容」的拼接伪造）。
func gpTestHeaderMustMatchLastEntry() -> void:
	var gpDoc: Dictionary = _gpSampleContainer()
	GPRevision.gpStampRevision(gpDoc, "local", "2026-11-16T09:00:00")
	gpDoc["revision"] = "0".repeat(64)
	var gpErrors: PackedStringArray = GPRevision.gpVerify(gpDoc)
	gpCheck(gpErrors.has(GPRevision.GP_ERR_BAD_CHAIN),
		"a header that disagrees with the last entry must report bad_chain, got " + str(gpErrors))


# The retained list is trimmed to GP_MAX_REVISIONS without breaking the surviving chain.
# 保留清单按 GP_MAX_REVISIONS 截断，且幸存链不破。
func gpTestListTrimmed() -> void:
	var gpDoc: Dictionary = _gpSampleContainer()
	var gpPrior: Array = []
	var gpNew: String = ""
	for gpI in range(GPRevision.GP_MAX_REVISIONS + 5):
		gpNew = GPRevision.gpStampRevision(gpDoc, "u" + str(gpI), "t" + str(gpI), gpPrior)
		gpPrior = (gpDoc["revisions"] as Array).duplicate(true)
	var gpList: Array = gpDoc["revisions"] as Array
	gpEq(gpList.size(), GPRevision.GP_MAX_REVISIONS, "the list must be capped at GP_MAX_REVISIONS")
	gpEq(GPRevision.gpVerify(gpDoc).size(), 0, "a trimmed chain must still verify clean")
	gpEq(GPRevision.gpHeaderRevision(gpDoc), gpNew,
		"the header must hold the newest revision after trimming")


# A legacy archive without any header keys verifies clean (progressive compatibility, D-C).
# 无任何头部键的旧档校验通过（渐进兼容，D-C）。
func gpTestLegacyArchiveVerifiesClean() -> void:
	var gpErrors: PackedStringArray = GPRevision.gpVerify(_gpSampleContainer())
	gpEq(gpErrors.size(), 0, "a container without a revision header must verify clean")


# The full project_io round-trip: a saved multi-sheet archive carries a header that
# verifies clean, and gpReadHeader reports the same revision the stamp produced.
# 完整 project_io 往返：保存出的多图纸存档携带可校验干净的头部，
# 且 gpReadHeader 报告的修订与盖章产出一致。
func gpTestProjectIoRoundTrip() -> void:
	_gpCleanup()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "pump", "P-101", Vector2(10, 20)))
	var gpSheet: GPSheet = GPSheet.new()
	gpSheet.gpGraph = gpG
	var gpWrite: int = GPProjectIO.gpWriteSheets([gpSheet], GP_TMP_PATH, [],
		"alice", "2026-11-16T09:00:00")
	gpEq(gpWrite, OK, "the stamped multi-sheet save must succeed")
	# Verify the on-disk container directly.
	# 直接校验磁盘上的容器。
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(GP_TMP_PATH)
	gpCheck(gpRead.gpIsOk(), "the saved archive must parse")
	if gpRead.gpIsOk():
		var gpContainer: Dictionary = gpRead.gpPayload as Dictionary
		gpEq(GPRevision.gpVerify(gpContainer).size(), 0,
			"the on-disk container must verify clean after a stamped save")
		gpEq(str(gpContainer.get("last_saved_by", "")), "alice",
			"last_saved_by must carry the stamp author")
		# And gpReadHeader must report the same state the shell would see.
		# 且 gpReadHeader 必须报告外壳将看到的同一状态。
		var gpHeader: GPIOResult = GPProjectIO.gpReadHeader(GP_TMP_PATH)
		gpCheck(gpHeader.gpIsOk(), "gpReadHeader must succeed on a real archive")
		if gpHeader.gpIsOk():
			var gpHeaderDict: Dictionary = gpHeader.gpPayload as Dictionary
			gpEq(str(gpHeaderDict.get("revision", "")),
				str(gpContainer.get("revision", "")),
				"gpReadHeader must report the same revision as the container")
			# sheets[].gpToDict carries no header keys, so the load-side payload also
			# surfaces them for the shell session capture.
			# sheets[].gpToDict 不携带头部键，故载入侧载荷同样把它们交给外壳会话捕获。
		var gpSheetsRead: GPIOResult = GPProjectIO.gpReadSheetsWithLinks(GP_TMP_PATH)
		gpCheck(gpSheetsRead.gpIsOk(), "the sheets read must succeed")
		if gpSheetsRead.gpIsOk():
			var gpPayload: Dictionary = gpSheetsRead.gpPayload as Dictionary
			gpEq(str(gpPayload.get("revision", "")),
				str(gpContainer.get("revision", "")),
				"gpReadSheetsWithLinks must carry the header revision out to the shell")
	_gpCleanup()
