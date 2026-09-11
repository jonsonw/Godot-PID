extends "res://tests/gp_test.gd"
# Headless regression tests for the archive migration chain (P1).
# 存档迁移链的 headless 回归测试（P1）。
# The contract under test: EVERY historical shape must converge on the same v3 container,
# and doing it twice must be the same as doing it once (idempotence).
# 受测契约：每种历史形态都必须收敛到同一个 v3 容器，且做两次必须与做一次相同（幂等）。
# See 持久化实现方案 §7 / 见「持久化实现方案」§7。


# A v1 archive: old key names (id/type/label/pos/attr_values) and node-to-node edges.
# 一份 v1 存档：旧键名（id/type/label/pos/attr_values）与节点到节点的边。
static func _gpV1() -> Dictionary:
	return {
		"meta": {"version": "1.0", "title": "旧档"},
		"nodes": [
			{"id": "n1", "type": "pump", "label": "P-1001", "pos": [10.0, 20.0],
			 "attr_values": {"Q": "120"}},
			{"id": "n2", "type": "tank", "label": "磨矿槽", "pos": [50.0, 20.0]},
		],
		"edges": [{"id": "e1", "from": "n1", "to": "n2"}],
	}


# The historic multi-document shape found in docs/samples/pani_detox.pid.json: each
# document wraps its own graph one level deeper. This is the case that used to read back
# as ZERO nodes — the whole reason the migration chain had to be written.
# docs/samples/pani_detox.pid.json 中的历史多文档形态：每个 document 把自己的 graph
# 多包了一层。这正是过去会被读成 **0 节点** 的情形 —— 也是迁移链必须存在的全部理由。
static func _gpHistoricDocuments() -> Dictionary:
	return {
		"meta": {"schema": "pid-1.0", "title": "Pani 金矿解毒系统总图", "docs": 2},
		"documents": [
			{"id": "D1", "title": "解毒槽区", "graph": {
				"meta": {"version": "1.0"},
				"nodes": [
					{"instance_id": "u-1", "symbol_id": "valve", "tag": "FV-101",
					 "position": [120, 80], "attr_values": {"size": "DN80"}},
					{"instance_id": "u-2", "symbol_id": "tank", "tag": "T-101",
					 "position": [220, 80]},
				],
				"edges": [{"instance_id": "e-1",
					"from_ref": {"node_id": "u-1", "port_id": "out"},
					"to_ref": {"node_id": "u-2", "port_id": "in"}}],
			}},
			{"id": "D2", "title": "加药区", "graph": {
				"nodes": [{"instance_id": "u-3", "symbol_id": "pump", "tag": "P-201",
					"position": [120, 80]}],
				"edges": [],
			}},
		],
		"cross_links": [{"from_doc": "D1", "from_node": "u-2", "to_doc": "D2",
			"to_node": "u-3", "tag": "PL-201"}],
	}


# A v1 archive becomes v3 with modern key names.
# v1 存档应变为带现代键名的 v3。
func gpTestV1MigratesToV3() -> void:
	var gpOut: Dictionary = GPSchemaMigrate.gpMigrate(_gpV1())
	gpCheck(str(gpOut.get("format", "")) == "g-pid", "format marker should be written")
	gpCheck(int(gpOut.get("format_version", 0)) == 3, "format_version should be 3")
	var gpSheets: Array = gpOut.get("sheets", []) as Array
	gpCheck(gpSheets.size() == 1, "a single-sheet archive should produce one sheet")
	if gpSheets.is_empty():
		return
	var gpNodes: Array = (gpSheets[0] as Dictionary).get("nodes", []) as Array
	gpCheck(gpNodes.size() == 2, "both nodes should survive")
	if gpNodes.size() < 1:
		return
	var gpN0: Dictionary = gpNodes[0] as Dictionary
	gpCheck(str(gpN0.get("instance_id", "")) == "n1", "id should normalise to instance_id")
	gpCheck(str(gpN0.get("symbol_id", "")) == "pump", "type should normalise to symbol_id")
	gpCheck(str(gpN0.get("tag", "")) == "P-1001", "label should normalise to tag")
	gpCheck(str(gpN0.get("uid", "")) != "", "a uid should be back-filled")
	var gpProps: Dictionary = gpN0.get("props", {}) as Dictionary
	gpCheck(str(gpProps.get("Q", "")) == "120", "attr_values should normalise to props")
	var gpPos: Array = gpN0.get("position", []) as Array
	gpCheck(gpPos.size() == 2 and float(gpPos[0]) == 10.0, "pos should normalise to position")


# A name-shaped v1 label must not be mistaken for a tag (M-v1b).
# 名称形态的 v1 label 不得被误当作位号（M-v1b）。
func gpTestV1NameLabelBecomesNames() -> void:
	var gpOut: Dictionary = GPSchemaMigrate.gpMigrate(_gpV1())
	var gpSheets: Array = gpOut.get("sheets", []) as Array
	var gpNodes: Array = (gpSheets[0] as Dictionary).get("nodes", []) as Array
	var gpN1: Dictionary = gpNodes[1] as Dictionary
	var gpNames: Dictionary = gpN1.get("names", {}) as Dictionary
	gpCheck(str(gpNames.get("zh_CN", "")) == "磨矿槽",
		"a name-shaped label should be preserved under names.zh_CN")


# Legacy node-to-node edges must become port refs.
# 旧的节点到节点边必须变成端口引用。
func gpTestV1EdgeLiftedToRefs() -> void:
	var gpOut: Dictionary = GPSchemaMigrate.gpMigrate(_gpV1())
	var gpSheets: Array = gpOut.get("sheets", []) as Array
	var gpEdges: Array = (gpSheets[0] as Dictionary).get("edges", []) as Array
	gpCheck(gpEdges.size() == 1, "the edge should survive")
	if gpEdges.is_empty():
		return
	var gpE: Dictionary = gpEdges[0] as Dictionary
	gpCheck((gpE.get("from_ref", {}) as Dictionary).get("node_id", "") != "",
		"'from' should become from_ref.node_id")
	gpCheck(str((gpE.get("to_ref", {}) as Dictionary).get("node_id", "")) != "",
		"'to' should become to_ref.node_id")


# IDEMPOTENCE: migrating twice equals migrating once. This is the invariant that makes the
# chain safe to run on every read.
# 幂等：迁移两次等于迁移一次。这是使迁移链可以在每次读取时安全运行的不变式。
func gpTestMigrateIsIdempotent() -> void:
	var gpOnce: Dictionary = GPSchemaMigrate.gpMigrate(_gpV1())
	var gpTwice: Dictionary = GPSchemaMigrate.gpMigrate(gpOnce)
	gpCheck(gpOnce == gpTwice, "migrate(migrate(d)) must equal migrate(d)")


# The historic documents[] shape must yield BOTH sheets, not an empty drawing.
# 历史的 documents[] 形态必须产出**两页**图纸，而不是一张空图。
func gpTestHistoricDocumentsBecomeSheets() -> void:
	var gpOut: Dictionary = GPSchemaMigrate.gpMigrate(_gpHistoricDocuments())
	var gpSheets: Array = gpOut.get("sheets", []) as Array
	gpCheck(gpSheets.size() == 2, "two documents should become two sheets, got "
		+ str(gpSheets.size()))
	if gpSheets.size() < 2:
		return
	var gpD1: Dictionary = gpSheets[0] as Dictionary
	gpCheck(str(gpD1.get("id", "")) == "D1", "sheet id should come from the document id")
	gpCheck(str(gpD1.get("name", "")) == "解毒槽区", "sheet name should come from the title")
	gpCheck(((gpD1.get("nodes", []) as Array).size()) == 2, "D1 should keep its two nodes")
	var gpD2: Dictionary = gpSheets[1] as Dictionary
	gpCheck(((gpD2.get("nodes", []) as Array).size()) == 1, "D2 should keep its one node")
	gpCheck(gpOut.has("cross_links"), "cross_links must be preserved, not dropped")


# Every node of a migrated archive carries a usable uid, and they are unique.
# 迁移后存档的每个节点都带有可用 uid，且互不重复。
func gpTestUidsBackFilledAndUnique() -> void:
	var gpOut: Dictionary = GPSchemaMigrate.gpMigrate(_gpHistoricDocuments())
	var gpSeen: Dictionary = {}
	var gpTotal: int = 0
	for gpS in (gpOut.get("sheets", []) as Array):
		for gpN in ((gpS as Dictionary).get("nodes", []) as Array):
			var gpUid: String = str((gpN as Dictionary).get("uid", ""))
			gpCheck(not gpUid.is_empty(), "every node needs a uid")
			gpCheck(not gpSeen.has(gpUid), "uids must be unique: " + gpUid)
			gpSeen[gpUid] = true
			gpTotal += 1
	gpCheck(gpTotal == 3, "three nodes should have been migrated, got " + str(gpTotal))


# user_symbol_packs must move under library.packs.
# user_symbol_packs 必须移到 library.packs 之下。
func gpTestPacksMoveUnderLibrary() -> void:
	var gpIn: Dictionary = {
		"meta": {"version": "1.1"},
		"nodes": [],
		"user_symbol_packs": [{"pack_id": "p1", "name": "我的包", "symbols": []}],
	}
	var gpOut: Dictionary = GPSchemaMigrate.gpMigrate(gpIn)
	gpCheck(not gpOut.has("user_symbol_packs"), "the legacy key should be gone")
	gpCheck(gpOut.get("library") is Dictionary, "library should exist")
	var gpPacks: Array = ((gpOut.get("library", {}) as Dictionary).get("packs", []) as Array)
	gpCheck(gpPacks.size() == 1, "the pack should be carried over")


# A missing config is filled with factory defaults (in memory only).
# 缺失的 config 应填出厂默认（仅内存）。
func gpTestConfigDefaultsFilled() -> void:
	var gpOut: Dictionary = GPSchemaMigrate.gpMigrate(_gpV1())
	var gpConfig: Dictionary = gpOut.get("config", {}) as Dictionary
	gpCheck(not gpConfig.is_empty(), "config should be filled")
	gpCheck(gpConfig.get("sheet") is Dictionary, "config.sheet should exist")
	gpCheck(gpConfig.get("display") is Dictionary, "config.display should exist")


# Version detection. / 版本识别。
func gpTestVersionDetection() -> void:
	gpCheck(GPSchemaMigrate.gpDetectVersion(_gpV1()) == 1, "v1 archive should be detected as 1")
	var gpV2: Dictionary = {"meta": {"version": "1.1"}, "nodes": [{"uid": "x"}], "edges": []}
	gpCheck(GPSchemaMigrate.gpDetectVersion(gpV2) == 2, "a uid-bearing archive is v2")
	gpCheck(GPSchemaMigrate.gpDetectVersion(GPSchemaMigrate.gpMigrate(_gpV1())) == 3,
		"a migrated archive is v3")


# Foreign JSON must be recognised as NOT a G-PID archive (E7).
# 外来 JSON 必须被识别为「不是 G-PID 存档」（E7）。
func gpTestForeignJsonRejected() -> void:
	gpCheck(not GPSchemaMigrate.gpIsGPidArchive({"hello": "world"}),
		"an unrelated JSON object is not a G-PID archive")
	gpCheck(GPSchemaMigrate.gpIsGPidArchive(_gpV1()), "a v1 archive is a G-PID archive")


# Sanitize: NaN/Infinity have no JSON representation and would destroy the file.
# 净化：NaN/Infinity 没有 JSON 表示，会毁掉整个文件。
func gpTestSanitizeRemovesNonFinite() -> void:
	var gpIn: Dictionary = {"a": NAN, "b": INF, "c": -INF, "d": 1.5, "e": [NAN, 2.0]}
	var gpOut: Dictionary = GPSchemaMigrate.gpSanitizeJson(gpIn) as Dictionary
	gpCheck(float(gpOut.get("a", 1.0)) == 0.0, "NaN should become 0.0")
	gpCheck(is_finite(float(gpOut.get("b", NAN))), "+Inf should be clamped to a finite value")
	gpCheck(is_finite(float(gpOut.get("c", NAN))), "-Inf should be clamped to a finite value")
	gpCheck(float(gpOut.get("d", 0.0)) == 1.5, "ordinary floats must pass through")
	gpCheck(is_finite(float((gpOut.get("e", []) as Array)[0])),
		"NaN inside an array should also be clamped")


# Sanitize must not choke on deep or odd payloads.
# 净化不得在深层或异常载荷上卡住。
func gpTestSanitizeHandlesOddShapes() -> void:
	var gpV: Vector2 = Vector2(NAN, 12.0)
	var gpOut: Array = GPSchemaMigrate.gpSanitizeJson(gpV) as Array
	gpCheck(gpOut.size() == 2, "a Vector2 should become a 2-element array")
	gpCheck(is_finite(float(gpOut[0])), "the NaN component should be clamped")
	var gpDeep: Dictionary = {"x": {}}
	gpCheck(GPSchemaMigrate.gpSanitizeJson(gpDeep, 40) == null,
		"over-deep nesting should be truncated, not crash")


# Tag heuristic. / 位号启发式。
func gpTestTagHeuristic() -> void:
	gpCheck(GPSchemaMigrate.gpLooksLikeTag("P-1001"), "P-1001 looks like a tag")
	gpCheck(GPSchemaMigrate.gpLooksLikeTag("FV-101"), "FV-101 looks like a tag")
	gpCheck(not GPSchemaMigrate.gpLooksLikeTag("磨矿槽"), "a Chinese name is not a tag")
	gpCheck(not GPSchemaMigrate.gpLooksLikeTag("给料泵"), "a Chinese name is not a tag")
	gpCheck(not GPSchemaMigrate.gpLooksLikeTag(""), "an empty string is not a tag")


# A single-sheet flattening must hand gpFromDict exactly what it expects.
# 单图纸展平必须交给 gpFromDict 它期望的形状。
func gpTestToGraphDictFlattens() -> void:
	var gpOut: Dictionary = GPSchemaMigrate.gpToGraphDict(_gpV1())
	gpCheck((gpOut.get("nodes", []) as Array).size() == 2,
		"nodes should be lifted to the top level")
	gpCheck((gpOut.get("edges", []) as Array).size() == 1,
		"edges should be lifted to the top level")
	gpCheck(gpOut.has("meta"), "meta should be preserved")
	gpCheck(gpOut.has("sheets"), "the full sheet list should ride along for P2")


# Choosing a non-default sheet index must pick that sheet.
# 选择非默认图纸序号时必须取到那一页。
func gpTestToGraphDictPicksSheet() -> void:
	var gpOut: Dictionary = GPSchemaMigrate.gpToGraphDict(_gpHistoricDocuments(), 1)
	var gpNodes: Array = gpOut.get("nodes", []) as Array
	gpCheck(gpNodes.size() == 1, "sheet 2 has one node, got " + str(gpNodes.size()))
	if gpNodes.size() >= 1:
		gpCheck(str((gpNodes[0] as Dictionary).get("tag", "")) == "P-201",
			"sheet 2's node should be P-201")
