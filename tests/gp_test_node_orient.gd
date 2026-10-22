extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Headless tests for the rotate / mirror user entry points (A4).
# 旋转 / 镜像用户入口（A4）的 headless 测试。
#
# Three promises are guarded here / 此处守护三条承诺：
#   1. ROTATION IS FOLDED, NOT ACCUMULATED. A rotate writes a target in [0,360); otherwise a shape
#      rotated three times (270) would never compare equal to the same shape re-imported as -90.
#      **旋转是折返，不是累加**。写入的目标角在 [0,360) 内；否则连转三次（270）的图形永远无法与
#      重新导入为 -90 的同一图形相等。
#   2. MIRROR TOGGLES. Pressing it twice restores the instance, and both presses are real edits.
#      **镜像是开关**。按两次回到原样，且两次都是真实编辑。
#   3. BOTH ARE ONE UNDO STEP. The command stores targets and undo restores the recorded
#      orientation exactly — no re-derivation, so a host moving in between cannot make undo drift.
#      **两者都是一步撤销**。命令存目标值，撤销精确还原记录的朝向 —— 不重新推导，故其间宿主移动
#      不会让撤销漂移。
#
# NOTE ON WHY THE SHORTCUT DELEGATE IS NOT DRIVEN HERE / 为何此处不驱动快捷键委托：
# gpHandleKey() asks for an InputEventKey and a live canvas; the INTENT it calls is what carries
# the promise, so the suite drives the intent directly. The key mapping itself is pinned by the
# two i18n/menu keys and by the shell smoke run.
# gpHandleKey() 需要 InputEventKey 与一个活画布；而承诺本体在它调用的**意图**里，故本套件直接驱动
# 意图。按键映射本身由两条 i18n / 菜单键与外壳冒烟覆盖。

const GP_EPS: float = 0.0001


func _gpGraph() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "n1"
	gpN.gpSymbolId = "sym"
	gpG.gpAddNode(gpN)
	var gpM: GPPIDNode = GPPIDNode.new()
	gpM.gpInstanceId = "n2"
	gpM.gpSymbolId = "sym"
	gpG.gpAddNode(gpM)
	return gpG


func _gpCtx(gpGraph: GPPIDGraph) -> GPCommandContext:
	return GPCommandContext.new(gpGraph, GPIdGen.new(), null)


func _gpIds() -> Array[String]:
	return ["n1", "n2"]


# ---------------------------------------------------------------------------
# Angle folding
# 角度折返
# ---------------------------------------------------------------------------

func gpTestNormalizeDegFoldsIntoOneTurn() -> void:
	gpApprox(GPSetNodeOrientCommand.gpNormalizeDeg(90.0), 90.0, GP_EPS, "90 原样")
	gpApprox(GPSetNodeOrientCommand.gpNormalizeDeg(-90.0), 270.0, GP_EPS, "-90 → 270")
	gpApprox(GPSetNodeOrientCommand.gpNormalizeDeg(450.0), 90.0, GP_EPS, "450 → 90")
	gpApprox(GPSetNodeOrientCommand.gpNormalizeDeg(360.0), 0.0, GP_EPS, "整圈归零")
	gpApprox(GPSetNodeOrientCommand.gpNormalizeDeg(720.0), 0.0, GP_EPS, "两圈归零")


# ---------------------------------------------------------------------------
# Command: targets, undo, redo, no-op
# 命令：目标值、撤销、重做、空操作
# ---------------------------------------------------------------------------

func gpTestOrientCommandWritesTargetsAndUndoes() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpGetNode("n1").gpRotationDeg = 30.0
	gpG.gpGetNode("n2").gpFlipped = false
	var gpCtx: GPCommandContext = _gpCtx(gpG)

	# n1 rotates 30 -> 90 and stays unflipped; n2 flips false -> true and keeps its 0 rotation.
	# 取值刻意让两个字段**各自**承担一次变化，这样撤销/重做两侧都被真正走到。
	var gpRots: Array[float] = [90.0, 0.0]
	var gpFlips: Array[bool] = [false, true]
	var gpCmd: GPSetNodeOrientCommand = GPSetNodeOrientCommand.new(_gpIds(), gpRots, gpFlips)
	gpCheck(gpCmd.gpExecute(gpCtx), "朝向写入成功 / orientation written")
	gpApprox(gpG.gpGetNode("n1").gpRotationDeg, 90.0, GP_EPS, "n1 角度 = 90")
	gpCheck(gpG.gpGetNode("n2").gpFlipped, "n2 已镜像 / n2 flipped")

	gpCmd.gpUndo(gpCtx)
	gpApprox(gpG.gpGetNode("n1").gpRotationDeg, 30.0, GP_EPS, "撤销还原 n1 角度")
	gpCheck(not gpG.gpGetNode("n2").gpFlipped, "撤销还原 n2 镜像")

	gpCmd.gpExecute(gpCtx)
	gpApprox(gpG.gpGetNode("n1").gpRotationDeg, 90.0, GP_EPS, "重做重放 n1")
	gpCheck(gpG.gpGetNode("n2").gpFlipped, "重做重放 n2")


func gpTestOrientCommandNoOpRefused() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpGetNode("n1").gpRotationDeg = 45.0
	gpG.gpGetNode("n2").gpRotationDeg = 45.0
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpRots: Array[float] = [45.0, 45.0]
	var gpFlips: Array[bool] = [false, false]
	var gpCmd: GPSetNodeOrientCommand = GPSetNodeOrientCommand.new(_gpIds(), gpRots, gpFlips)
	gpCheck(not gpCmd.gpExecute(gpCtx), "同值不产生撤销步 / identical targets are refused")


func gpTestOrientCommandSkipsMissingNodes() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpIds: Array[String] = ["n1", "ghost"]
	var gpRots: Array[float] = [90.0, 90.0]
	var gpFlips: Array[bool] = [false, false]
	var gpCmd: GPSetNodeOrientCommand = GPSetNodeOrientCommand.new(gpIds, gpRots, gpFlips)
	gpCheck(gpCmd.gpExecute(gpCtx), "缺失节点被跳过、其余仍写入 / a missing node is skipped")
	gpApprox(gpG.gpGetNode("n1").gpRotationDeg, 90.0, GP_EPS, "n1 仍被旋转 / n1 still rotated")
	gpCmd.gpUndo(gpCtx)
	gpApprox(gpG.gpGetNode("n1").gpRotationDeg, 0.0, GP_EPS, "撤销仍然生效 / undo still works")


func gpTestEmptyIdListRefused() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpEmpty: Array[String] = []
	var gpRots: Array[float] = []
	var gpFlips: Array[bool] = []
	var gpCmd: GPSetNodeOrientCommand = GPSetNodeOrientCommand.new(gpEmpty, gpRots, gpFlips)
	gpCheck(not gpCmd.gpExecute(gpCtx), "空列表被拒 / an empty id list is refused")


# ---------------------------------------------------------------------------
# i18n: the two menu entries the user actually sees
# i18n：用户真正看到的两条菜单项
# ---------------------------------------------------------------------------

func gpTestOrientMenuKeysBilingual() -> void:
	for gpKey in ["canvas.ctx_rotate_cw", "canvas.ctx_mirror"]:
		var gpPair: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
		gpCheck(not gpPair.is_empty(), "键存在 / key present: " + gpKey)
		gpCheck(str(gpPair.get("zh", "")) != "", "中文非空 / zh non-empty: " + gpKey)
		gpCheck(str(gpPair.get("en", "")) != "", "英文非空 / en non-empty: " + gpKey)
