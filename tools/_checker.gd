extends SceneTree

# Headless validator for the Step 1.2 object-graph refactor (MODEL LAYER ONLY).
# Step 1.2 对象图重构的 headless 校验（仅模型层）。
# The UI/render scripts reference autoload globals (I18n / Settings) that are NOT visible
# at compile time under --script, so they are validated in the editor instead. This checker
# forces the model scripts + test stub to compile and runs the object-graph behavior.
# UI/渲染脚本引用了 autoload 全局（I18n/Settings），在 --script 下编译期不可见，故改在编辑器
# 中验证。本脚本强制模型层与测试桩编译，并运行对象图行为。

# Preload the model scripts so the compiler parses them (no autoload refs inside).
# 预加载模型脚本以强制编译（内部不引用 autoload）。
const GPPIDGraph := preload("res://src/core/model/pid_graph.gd")
const GPPIDNode := preload("res://src/core/model/pid_node.gd")
const GPPIDEdge := preload("res://src/core/model/pid_edge.gd")
const GPTestPIDGraph := preload("res://tests/test_pid_graph.gd")


# Entry point for a headless --script run.
# headless --script 运行的入口。
func _initialize() -> void:
	printerr("STEP0 start")

	# 1) Run the project's own graph unit tests (add / edge / round-trip / remove).
	# 1) 运行工程自带的图单元测试（新增 / 连线 / 往返 / 删除）。
	var gpT: Node = GPTestPIDGraph.new()
	printerr("STEP1 test new")
	gpT.gpTestAddNode()
	printerr("STEP2 test edge")
	gpT.gpTestAddEdge()
	printerr("STEP3 test roundtrip")
	gpT.gpTestRoundTrip()
	printerr("STEP4 test remove")
	gpT.gpTestRemoveWithEdges()
	gpT.free()
	printerr("STEP5 tests done")

	# 2) Backward-compat: the old dictionary-graph *.pid.json shape must still load.
	# 2) 向后兼容：旧字典图形状的 *.pid.json 仍须能载入。
	var gpOld: Dictionary = {
		"meta": {},
		"nodes": [{"id": "V-1", "type": "valve", "label": "x", "pos": [1, 2], "attrs": {"a": 1}}],
		"edges": [{"id": "P-1", "from": "V-1", "to": "V-2", "attrs": {}}],
	}
	var gpG3: GPPIDGraph = GPPIDGraph.gpFromDict(gpOld)
	assert(gpG3.gpGetNode("V-1") != null, "old node V-1 should load")
	assert(gpG3.gpGetNode("V-1").gpSymbolId == "valve", "old type should map")
	assert(gpG3.gpGetEdge("P-1") != null, "old edge P-1 should load")
	assert(gpG3.gpGetEdge("P-1").gpFromRef.get("node_id", "") == "V-1", "old from should map")
	assert(gpG3.gpGetEdge("P-1").gpToRef.get("node_id", "") == "V-2", "old to should map")
	printerr("STEP6 backward-compat ok")

	# 3b) The shipped sample project.pid.json (new object-graph shape) must load.
	# 3b) 随工程分发的 project.pid.json 样例（新对象图形状）必须能载入。
	var gpPath: String = "res://project.pid.json"
	if FileAccess.file_exists(gpPath):
		var gpJ: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
		var gpTxt: String = gpJ.get_as_text()
		gpJ.close()
		var gpJson: Dictionary = JSON.parse_string(gpTxt)
		var gpS: GPPIDGraph = GPPIDGraph.gpFromDict(gpJson)
		assert(gpS.gpNodes.size() == 2, "sample should have 2 nodes")
		assert(gpS.gpGetEdge("P-01") != null, "sample edge P-01 should load")
		assert(gpS.gpGetNode("T-201").gpSymbolId == "tank", "sample node T-201 symbol")
		printerr("STEP7 sample pid.json ok")

	# Emit result to stderr (unbuffered) and a file so it survives a hard quit.
	# 把结果写到 stderr（不缓冲）和文件，避免硬退出时丢失。
	printerr("CHECKER_OK")
	var gpF: FileAccess = FileAccess.open("/tmp/checker_result.txt", FileAccess.WRITE)
	if gpF != null:
		gpF.store_string("CHECKER_OK\n")
		gpF.close()
	quit()
