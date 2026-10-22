extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Headless tests for the annotation-shape property panel (A2) and its command.
# 注释图形属性面板（A2）及其命令的 headless 测试。
#
# Three promises are guarded here / 此处守护三条承诺：
#   1. A SHAPE EDIT IS UNDOABLE. Name / layer / ink edits go through one command, so undo puts the
#      previous values back exactly — before this, a layer change was silent and permanent.
#      **图形编辑可撤销**。名称 / 图层 / 墨色经同一条命令，撤销精确还原旧值 —— 在此之前改图层
#      静默且永久。
#   2. A NO-OP RECORDS NOTHING. Re-submitting the same value must not create a phantom undo step.
#      **空操作不记录**。把相同的值再提交一次不得产生幽灵撤销步。
#   3. THE PANEL'S VOCABULARY IS PINNED. Shape kinds and the four layer buckets are mapped in one
#      pure function, so a new kind cannot silently fall back to "Line".
#      **面板词汇被钉住**。图形种类与四个图层桶集中在一个纯函数里，新种类不会静默回落到「直线」。

const GP_EPS: float = 0.0001


func _gpGraph() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddShape(GPShape.gpLine(Vector2(0.0, 0.0), Vector2(10.0, 0.0)))
	return gpG


func _gpCtx(gpGraph: GPPIDGraph) -> GPCommandContext:
	return GPCommandContext.new(gpGraph, GPIdGen.new(), null)


# ---------------------------------------------------------------------------
# The command: apply / undo / redo
# 命令：应用 / 撤销 / 重做
# ---------------------------------------------------------------------------

func gpTestShapePropsApplyUndoRedo() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpS: GPShape = gpG.gpShapes[0]
	gpS.gpName = "界区线"
	gpS.gpLayer = "ANNOTATION"
	var gpCtx: GPCommandContext = _gpCtx(gpG)

	var gpVals: Dictionary = {"gpName": "工艺界区", "gpLayer": "BORDER"}
	var gpCmd: GPSetShapePropsCommand = GPSetShapePropsCommand.new(0, gpVals)
	gpCheck(gpCmd.gpExecute(gpCtx), "首次执行应写入 / first execute writes")
	gpEq(gpS.gpName, "工艺界区", "名称已写入 / name applied")
	gpEq(gpS.gpLayer, "BORDER", "图层已写入 / layer applied")

	gpCmd.gpUndo(gpCtx)
	gpEq(gpS.gpName, "界区线", "撤销还原名称 / undo restores the name")
	gpEq(gpS.gpLayer, "ANNOTATION", "撤销还原图层 / undo restores the layer")

	gpCmd.gpExecute(gpCtx)
	gpEq(gpS.gpName, "工艺界区", "重做重放名称 / redo replays the name")
	gpEq(gpS.gpLayer, "BORDER", "重做重放图层 / redo replays the layer")


func gpTestShapePropsNoOpRecordsNothing() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpShapes[0].gpLayer = "DIMENSION"
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	# Same value as the current one: the command must refuse, or every re-submit of a text field
	# would push a do-nothing undo step.
	# 与当前值相同：命令必须拒绝，否则文本框每提交一次都会压入一步空撤销。
	var gpCmd: GPSetShapePropsCommand = GPSetShapePropsCommand.new(0, {"gpLayer": "DIMENSION"})
	gpCheck(not gpCmd.gpExecute(gpCtx), "同值应被拒绝 / identical value is refused")


func gpTestShapePropsStaleIndexRefused() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	gpCheck(not GPSetShapePropsCommand.new(-1, {"gpName": "x"}).gpExecute(gpCtx),
		"负下标被拒 / negative index refused")
	gpCheck(not GPSetShapePropsCommand.new(7, {"gpName": "x"}).gpExecute(gpCtx),
		"越界下标被拒 / out-of-range index refused")


func gpTestShapePropsUnknownKeyIgnored() -> void:
	# A typo in a field name must not silently create a property nobody reads, and it must not
	# count as a change (so it cannot manufacture an undo step on its own).
	# 字段名拼错不得静默造出一条无人读取的属性，也不得算作变化（否则它自己就能伪造撤销步）。
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPSetShapePropsCommand = GPSetShapePropsCommand.new(0, {"gpNmae": "typo"})
	gpCheck(not gpCmd.gpExecute(gpCtx), "未知键不构成变化 / an unknown key is not a change")
	gpCheck(not gpG.gpShapes[0].gpProps.has("gpNmae"), "未知键不进属性表 / unknown key not stored")


func gpTestShapePropsColorAndProps() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpS: GPShape = gpG.gpShapes[0]
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpInk: Color = Color(1.0, 0.2, 0.2)
	var gpCmd: GPSetShapePropsCommand = GPSetShapePropsCommand.new(0,
		{"gpColor": gpInk, "gpProps": {"note": "x"}})
	gpCheck(gpCmd.gpExecute(gpCtx), "墨色与属性可写 / ink and props are writable")
	gpApprox(gpS.gpColor.r, 1.0, GP_EPS, "墨色已写入 / ink applied")
	gpEq(str(gpS.gpProps.get("note", "")), "x", "属性已写入 / props applied")
	gpCmd.gpUndo(gpCtx)
	gpCheck(not gpS.gpProps.has("note"), "撤销清掉新属性 / undo removes the new prop")


# ---------------------------------------------------------------------------
# The panel's vocabulary
# 面板词汇
# ---------------------------------------------------------------------------

func gpTestShapeKindKeysCoverAllKinds() -> void:
	gpEq(GPInspector.gpShapeKindKey(GPShape.GPKind.GP_LINE), "shape.kind_line", "直线键")
	gpEq(GPInspector.gpShapeKindKey(GPShape.GPKind.GP_CIRCLE), "shape.kind_circle", "圆键")
	gpEq(GPInspector.gpShapeKindKey(GPShape.GPKind.GP_RECT), "shape.kind_rect", "矩形键")
	gpEq(GPInspector.gpShapeKindKey(GPShape.GPKind.GP_POLYLINE), "shape.kind_polyline", "折线键")
	gpEq(GPInspector.gpShapeKindKey(GPShape.GPKind.GP_ARC), "shape.kind_arc", "弧线键")


func gpTestShapeLayerBuckets() -> void:
	gpEq(GPInspector.GP_SHAPE_LAYERS.size(), 4, "四个图层桶 / four layer buckets")
	gpCheck(GPInspector.GP_SHAPE_LAYERS.has("ANNOTATION"), "含默认桶 ANNOTATION")
	for gpLayer in GPInspector.GP_SHAPE_LAYERS:
		var gpKey: String = "shape.layer_" + gpLayer.to_lower()
		var gpPair: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
		gpCheck(not gpPair.is_empty(), "图层键存在 / layer key present: " + gpKey)
		gpCheck(str(gpPair.get("en", "")) != "", "图层键有英文 / layer key has en: " + gpKey)
