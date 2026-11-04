extends "res://tests/gp_test.gd"
# Off-page cross-sheet link tests (ADR-43 / S1).
# 跨图纸 Off-Page 连接测试（ADR-43 / S1）。
# The failure modes being guarded against: (1) a saved cross-sheet link silently vanishes
# or drifts on reload; (2) the container key leaks into archives that carry no links
# (byte-stability); (3) a hand-edited or historic cross_links entry crashes the reader.
# 所防范的失效模式：(1) 保存的跨图纸链接在重载时静默消失或漂移；(2) 容器键泄漏进
# 不含链接的存档（字节稳定）；(3) 手改或历史的 cross_links 条目令读取器崩溃。
# See ADR-43 / 见 ADR-43。

const GP_TMP: String = "user://gp_test_offpage.pid.json"
const GP_TMP_HISTORIC: String = "user://gp_test_offpage_historic.pid.json"


func _gpCleanup() -> void:
	for gpPath in [GP_TMP, GP_TMP_HISTORIC]:
		var gpAbs: String = ProjectSettings.globalize_path(gpPath)
		if FileAccess.file_exists(gpAbs):
			DirAccess.remove_absolute(gpAbs)


# A complete two-end link with contract attrs and a manual tag.
# 一条两端齐全、带契约属性与手工编号的 link。
static func _gpFullLink() -> GPOffPageLink:
	var gpL: GPOffPageLink = GPOffPageLink.new()
	gpL.gpInstanceId = "xlink-1"
	gpL.gpKind = GPPIDEdge.GP_SIGNAL
	gpL.gpA = {"sheet_id": "sheet-1", "node_id": "n1", "port_id": "p-out"}
	gpL.gpB = {"sheet_id": "sheet-2", "node_id": "n2", "port_id": "p-in"}
	gpL.gpAttrs = {"dn": "DN80", "medium": "SLURRY"}
	gpL.gpTag = "3-1"
	return gpL


# Two sheets, each carrying one node, so the container write path has real content.
# 两张图纸，各带一个节点，使容器写出路径有真实内容。
static func _gpTwoSheets() -> Array:
	var gpOut: Array = []
	for gpI in 2:
		var gpS: GPSheet = GPSheet.gpNew("sheet-" + str(gpI + 1), "图 " + str(gpI + 1), gpI)
		gpS.gpGraph.gpAddNode(gpS.gpGraph.gpNewNode(
			"n" + str(gpI + 1), "pump", "P-" + str(gpI + 1), Vector2(10.0, 20.0)))
		gpOut.append(gpS)
	return gpOut


# Model round trip: every field survives gpToDict -> gpFromDict unchanged.
# 模型往返：全部字段经 gpToDict -> gpFromDict 后不变。
func gpTestLinkRoundTrip() -> void:
	var gpSrc: GPOffPageLink = _gpFullLink()
	var gpD: Dictionary = gpSrc.gpToDict()
	var gpBack: GPOffPageLink = GPOffPageLink.gpFromDict(gpD)
	gpCheck(gpBack != null, "full link must read back")
	if gpBack == null:
		return
	gpEq(gpBack.gpInstanceId, "xlink-1", "instance id survives round trip")
	gpEq(gpBack.gpKind, GPPIDEdge.GP_SIGNAL, "kind survives round trip")
	gpEq(gpBack.gpTag, "3-1", "tag survives round trip")
	gpEq(gpBack.gpAttrs.get("dn", ""), "DN80", "attr dn survives round trip")
	gpEq(gpBack.gpAttrs.get("medium", ""), "SLURRY", "attr medium survives round trip")
	gpEq(str(gpBack.gpA.get("sheet_id", "")), "sheet-1", "A sheet_id survives")
	gpEq(str(gpBack.gpA.get("node_id", "")), "n1", "A node_id survives")
	gpEq(str(gpBack.gpA.get("port_id", "")), "p-out", "A port_id survives")
	gpEq(str(gpBack.gpB.get("sheet_id", "")), "sheet-2", "B sheet_id survives")
	gpEq(str(gpBack.gpB.get("node_id", "")), "n2", "B node_id survives")
	gpEq(str(gpBack.gpB.get("port_id", "")), "p-in", "B port_id survives")


# Write policy: tag/attrs only when non-default; empty ref keys never leak into the file.
# 写出策略：tag/attrs 仅非默认时写出；空引用键绝不泄漏进文件。
func gpTestLinkWritePolicy() -> void:
	var gpBare: GPOffPageLink = GPOffPageLink.new()
	gpBare.gpInstanceId = "xlink-2"
	var gpD: Dictionary = gpBare.gpToDict()
	gpCheck(not gpD.has("tag"), "empty tag must NOT be written")
	gpCheck(not gpD.has("attrs"), "empty attrs must NOT be written")
	gpEq((gpD.get("a", {}) as Dictionary).size(), 0, "empty A ref writes no keys")
	gpEq((gpD.get("b", {}) as Dictionary).size(), 0, "empty B ref writes no keys")
	var gpFull: GPOffPageLink = _gpFullLink()
	var gpDFull: Dictionary = gpFull.gpToDict()
	gpCheck(gpDFull.has("tag"), "non-empty tag must be written")
	gpCheck(gpDFull.has("attrs"), "non-empty attrs must be written")
	gpEq((gpDFull.get("a", {}) as Dictionary).size(), 3, "complete A ref writes all 3 keys")


# Tolerant reader: junk, historic shape and partial records are skipped, a hand-edited
# kind falls back instead of drifting out of the vocabulary.
# 容忍读取：垃圾、历史形状与残缺记录一律跳过；手改的 kind 回落而不漂移出词表。
func gpTestLinkTolerantReader() -> void:
	gpCheck(GPOffPageLink.gpFromDict({}) == null, "empty dict must be skipped")
	gpCheck(GPOffPageLink.gpFromDict(
		{"from_doc": "D1", "from_node": "u-2", "to_doc": "D2", "to_node": "u-3"}
	) == null, "historic shape must be skipped (ADR-43 D2)")
	gpCheck(GPOffPageLink.gpFromDict({"id": "xlink-9"}) == null,
		"id without any dict endpoint must be skipped")
	var gpFall: GPOffPageLink = GPOffPageLink.gpFromDict(
		{"id": "xlink-3", "kind": "MYSTERY", "a": {"node_id": "n1"},
		 "b": {"node_id": "n2"}})
	gpCheck(gpFall != null, "record with dict endpoints must read")
	if gpFall != null:
		gpEq(gpFall.gpKind, GPPIDEdge.GP_PROCESS, "unknown kind must fall back to PROCESS")


# Container sort: array order is pinned by id regardless of insertion order.
# 容器排序：无论插入顺序如何，数组顺序由 id 钉住。
func gpTestLinkSortStable() -> void:
	var gpC: GPOffPageLink = GPOffPageLink.new()
	gpC.gpInstanceId = "xlink-3"
	var gpA2: GPOffPageLink = GPOffPageLink.new()
	gpA2.gpInstanceId = "xlink-1"
	var gpB2: GPOffPageLink = GPOffPageLink.new()
	gpB2.gpInstanceId = "xlink-2"
	var gpArr: Array = [gpC, gpA2, gpB2]
	gpArr.sort_custom(GPOffPageLink.gpCompareId)
	gpEq((gpArr[0] as GPOffPageLink).gpInstanceId, "xlink-1", "sort places xlink-1 first")
	gpEq((gpArr[1] as GPOffPageLink).gpInstanceId, "xlink-2", "sort places xlink-2 second")
	gpEq((gpArr[2] as GPOffPageLink).gpInstanceId, "xlink-3", "sort places xlink-3 third")


# IO round trip: links written into the container come back field-identical, alongside
# the sheets they reference.
# IO 往返：写进容器的 link 连同其引用的图纸一起逐字段返回。
func gpTestIoRoundTrip() -> void:
	var gpSheets: Array = _gpTwoSheets()
	var gpL1: GPOffPageLink = _gpFullLink()
	var gpL2: GPOffPageLink = GPOffPageLink.new()
	gpL2.gpInstanceId = "xlink-2"
	gpL2.gpKind = GPPIDEdge.GP_PROCESS
	gpL2.gpA = {"sheet_id": "sheet-2", "node_id": "n2", "port_id": "p-out"}
	gpL2.gpB = {"sheet_id": "sheet-1", "node_id": "n1", "port_id": "p-in"}
	# Inserted OUT of id order on purpose: the sorted-read assertion below would pass even
	# with a broken sort if the fixtures went in already sorted.
	# 刻意**乱序**插入：若按 id 有序插入，下面「读回有序」的断言在排序失效时也会假绿。
	var gpWrite: GPIOResult = GPProjectIO.gpWriteSheetsResult(gpSheets, GP_TMP,
		[gpL2, gpL1])
	gpCheck(gpWrite.gpIsOk(), "container write with links must succeed")
	var gpRead: GPIOResult = GPProjectIO.gpReadSheetsWithLinks(GP_TMP)
	gpCheck(gpRead.gpIsOk(), "container read with links must succeed")
	if not gpRead.gpIsOk():
		return
	var gpPayload: Dictionary = gpRead.gpPayload as Dictionary
	var gpSheetsBack: Array = gpPayload.get("sheets", []) as Array
	gpEq(gpSheetsBack.size(), 2, "both sheets must come back")
	var gpLinks: Array = gpPayload.get("links", []) as Array
	gpEq(gpLinks.size(), 2, "both links must come back")
	if gpLinks.size() != 2:
		return
	# Sorted by id: xlink-1 first regardless of insertion order. / 按 id 排序：xlink-1 在前。
	var gpFirst: GPOffPageLink = gpLinks[0] as GPOffPageLink
	gpEq(gpFirst.gpInstanceId, "xlink-1", "links must be stored id-sorted")
	gpEq(gpFirst.gpKind, GPPIDEdge.GP_SIGNAL, "link kind survives the file")
	gpEq(str((gpFirst.gpA as Dictionary).get("port_id", "")), "p-out",
		"link A port survives the file")
	gpEq(gpFirst.gpAttrs.get("medium", ""), "SLURRY", "link contract attrs survive the file")


# Byte stability: the key must be ABSENT when no links exist, PRESENT when they do.
# 字节稳定：无连接时键必须缺席，有连接时必须在场。
func gpTestKeyPresenceFollowsLinks() -> void:
	var gpWrite: GPIOResult = GPProjectIO.gpWriteSheetsResult(_gpTwoSheets(), GP_TMP, [])
	gpCheck(gpWrite.gpIsOk(), "container write without links must succeed")
	var gpText: String = FileAccess.get_file_as_string(GP_TMP)
	gpCheck(not gpText.contains("cross_links"),
		"archive without links must NOT contain the cross_links key")
	var gpL: GPOffPageLink = _gpFullLink()
	var gpWrite2: GPIOResult = GPProjectIO.gpWriteSheetsResult(_gpTwoSheets(), GP_TMP, [gpL])
	gpCheck(gpWrite2.gpIsOk(), "container write with links must succeed")
	var gpText2: String = FileAccess.get_file_as_string(GP_TMP)
	gpCheck(gpText2.contains("cross_links"),
		"archive with links must contain the cross_links key")


# Historic shape: preserved by the migration chain on disk (pinned by persist_migrate),
# but the model reader skips it — v3 has no documents[] entity to resolve it against.
# 历史形状：磁盘上被迁移链保全（persist_migrate 已钉住），但模型读取器跳过它 ——
# v3 里没有 documents[] 实体可供其解析。
func gpTestHistoricShapeSkippedByReader() -> void:
	var gpFixture: Dictionary = {
		"meta": {"schema": "pid-1.0", "title": "Historic off-page sample", "docs": 2},
		"documents": [
			{"id": "D1", "title": "Sheet A", "graph": {
				"nodes": [{"instance_id": "u-2", "symbol_id": "tank", "tag": "T-001",
					"position": [220, 80]}],
				"edges": [],
			}},
			{"id": "D2", "title": "Sheet B", "graph": {
				"nodes": [{"instance_id": "u-3", "symbol_id": "pump", "tag": "P-001",
					"position": [120, 80]}],
				"edges": [],
			}},
		],
		"cross_links": [{"from_doc": "D1", "from_node": "u-2", "to_doc": "D2",
			"to_node": "u-3", "tag": "PL-001"}],
	}
	var gpAbs: String = ProjectSettings.globalize_path(GP_TMP_HISTORIC)
	DirAccess.remove_absolute(gpAbs)
	gpCheck(GPAtomicFile.gpWriteJsonAtomic(GP_TMP_HISTORIC, gpFixture).gpIsOk(),
		"historic fixture must write")
	var gpRead: GPIOResult = GPProjectIO.gpReadSheetsWithLinks(GP_TMP_HISTORIC)
	gpCheck(gpRead.gpIsOk(), "historic archive must still load")
	if not gpRead.gpIsOk():
		return
	var gpPayload: Dictionary = gpRead.gpPayload as Dictionary
	gpEq((gpPayload.get("sheets", []) as Array).size(), 2,
		"historic documents must still come back as sheets")
	gpEq((gpPayload.get("links", []) as Array).size(), 0,
		"historic cross_links shape must be skipped, not crash")
