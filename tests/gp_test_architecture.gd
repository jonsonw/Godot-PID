extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Architecture guard (B06 / ADR-10): CORE must not name a RENDER class. Godot's global
# class_name registry lets a core file call a render static function even though the dependency
# arrows point the wrong way, so a pure runtime test cannot catch the violation — this static
# scan can.
# 架构守卫（B06 / ADR-10）：CORE 不得出现 RENDER 类名。Godot 的全局 class_name 让 core 文件即使
# 依赖方向相反也能调用 render 静态函数，纯运行时测试抓不住；本静态扫描能。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_CORE_DIR: String = "res://src/core"
const GP_RENDER_CLASSES: Array[String] = [
	"GPSymbolPainter", "GPSymbolView", "GPEdgeView", "GPNodeView",
	"GPFrameView", "GPBackgroundView", "GPCanvas2D",
]


# Return every code occurrence (comments stripped) of a forbidden render class in one text.
# 返回一段文本中（已剥离注释）出现的禁用 render 类；用于真实扫描与注入自测。
func _gpFindForbidden(gpText: String) -> Array[String]:
	var gpOut: Array[String] = []
	var gpLines: PackedStringArray = gpText.split("\n")
	for gpI in range(gpLines.size()):
		var gpCode: String = gpLines[gpI].split("#")[0]
		for gpName in GP_RENDER_CLASSES:
			if gpCode.contains(gpName):
				gpOut.append("line %d: %s" % [gpI + 1, gpName])
	return gpOut


func _gpGdFiles(gpDir: String) -> Array[String]:
	var gpOut: Array[String] = []
	var gpDA: DirAccess = DirAccess.open(gpDir)
	if gpDA == null:
		return gpOut
	gpDA.list_dir_begin()
	var gpName: String = gpDA.get_next()
	while gpName != "":
		if gpName.begins_with("."):
			gpName = gpDA.get_next()
			continue
		var gpPath: String = gpDir.path_join(gpName)
		if gpDA.current_is_dir():
			gpOut.append_array(_gpGdFiles(gpPath))
		elif gpName.ends_with(".gd"):
			gpOut.append(gpPath)
		gpName = gpDA.get_next()
	gpDA.list_dir_end()
	return gpOut


# The promise: zero render-class references anywhere under src/core.
# 承诺：src/core 下没有任何 render 类引用。
func gpTestCoreHasNoRenderReferences() -> void:
	var gpHits: Array[String] = []
	for gpPath in _gpGdFiles(GP_CORE_DIR):
		var gpText: String = FileAccess.get_file_as_string(gpPath)
		for gpHit in _gpFindForbidden(gpText):
			gpHits.append("%s %s" % [gpPath, gpHit])
	gpEq(gpHits.size(), 0, "core→render references: " + ", ".join(gpHits))


# The detector must be able to fail: a deliberately injected reference is caught.
# 扫描器必须**能失败**：注入一条假引用应被抓到。
func gpTestForbiddenReferenceDetectorCatchesInjectedName() -> void:
	gpCheck(_gpFindForbidden("var gpX = GPSymbolPainter.gpUnitBox({})").size() > 0,
		"an injected render reference is detected")
	gpEq(_gpFindForbidden("# GPSymbolPainter in a comment only").size(), 0,
		"a comment-only mention is not treated as code")


# The actual consumer that used to reach up into render now reaches core geometry.
# 原先向上依赖 render 的消费者现在使用 core 几何。
func gpTestPrintModelUsesCoreGeometry() -> void:
	var gpText: String = FileAccess.get_file_as_string("res://src/core/view/print_model.gd")
	gpCheck(gpText.contains("GPSymbolGeometry"), "print_model references GPSymbolGeometry")
	gpCheck(not gpText.contains("GPSymbolPainter"), "print_model no longer names GPSymbolPainter")


# Behaviour is unchanged by the move: same box parsing and same fit-scale arithmetic.
# 搬迁不改变行为：同样的 box 解析与 fit-scale 算法。
func gpTestSymbolGeometryBehaviour() -> void:
	var gpBox: Rect2 = GPSymbolGeometry.gpUnitBox({"box": [10, 20, 30, 40]})
	gpApprox(gpBox.position.x, 10.0, 0.001, "unit box x")
	gpApprox(gpBox.position.y, 20.0, 0.001, "unit box y")
	gpApprox(gpBox.size.x, 30.0, 0.001, "unit box w")
	gpApprox(gpBox.size.y, 40.0, 0.001, "unit box h")
	gpEq(GPSymbolGeometry.gpUnitBox({}), Rect2(Vector2.ZERO, Vector2(100, 100)),
		"no box falls back to 100x100")
	gpApprox(GPSymbolGeometry.gpFitScale(Rect2(Vector2.ZERO, Vector2(10, 5)),
		Vector2(100, 100)), 10.0, 0.001, "fit scale picks the tighter axis")
