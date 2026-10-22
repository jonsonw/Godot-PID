extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Tests for the four symbol-editor gaps closed in stage A: port purpose (A12), undo visibility
# (A13), the new-symbol entry (A14) and arc promotion (A15).
# 阶段 A 关闭的四处图元编辑器缺口：端口用途（A12）、撤销可见化（A13）、新建图元入口（A14）、
# 圆弧提升（A15）。
#
# WHY THEY SHARE A SUITE / 为何共用一个套件：
# They are one story: a user opens the (previously unreachable) editor from the new-symbol entry,
# draws an arc, marks a port as SIGNAL, undoes a mistake — and expects all four to be true. Split
# across four files the story would be invisible.
# 它们是一个故事：用户从（此前不可达的）新建入口打开编辑器、画一段圆弧、把某个端口标为信号、
# 撤销一次误操作 —— 并期待这四件事同时成立。拆成四个文件，这个故事就看不见了。

const GP_EPS: float = 0.0001


func _gpCtx() -> GPCommandContext:
	return GPCommandContext.new(GPPIDGraph.new(), GPIdGen.new(), null)


# ---------------------------------------------------------------------------
# A12: port purpose is editable and undoable
# A12：端口用途可编辑、可撤销
# ---------------------------------------------------------------------------

func _gpPorts() -> Array[GPPort]:
	var gpP: GPPort = GPPort.new()
	gpP.gpName = "P1"
	gpP.gpType = GPPort.GP_NOZZLE
	var gpOut: Array[GPPort] = [gpP]
	return gpOut


func gpTestPortTypeCommandWritesAndUndoes() -> void:
	var gpPorts: Array[GPPort] = _gpPorts()
	var gpCtx: GPCommandContext = _gpCtx()
	var gpCmd: GPSymbolSetPortTypeCommand = GPSymbolSetPortTypeCommand.new(gpPorts, 0,
		GPPort.GP_SIGNAL)
	gpCheck(gpCmd.gpExecute(gpCtx), "用途写入 / purpose written")
	gpEq(gpPorts[0].gpType, GPPort.GP_SIGNAL, "端口已变为信号 / the port is now a signal port")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpPorts[0].gpType, GPPort.GP_NOZZLE, "撤销还原工艺管口 / undo restores the nozzle")
	gpCmd.gpRedo(gpCtx)
	gpEq(gpPorts[0].gpType, GPPort.GP_SIGNAL, "重做重放信号 / redo replays the signal purpose")


func gpTestPortTypeCommandNoOpRefused() -> void:
	var gpPorts: Array[GPPort] = _gpPorts()
	gpCheck(not GPSymbolSetPortTypeCommand.new(gpPorts, 0, GPPort.GP_NOZZLE).gpExecute(_gpCtx()),
		"同值被拒 / an identical purpose is refused")


func gpTestPortTypeCommandStaleIndexRefused() -> void:
	var gpPorts: Array[GPPort] = _gpPorts()
	gpCheck(not GPSymbolSetPortTypeCommand.new(gpPorts, 3, GPPort.GP_SIGNAL).gpExecute(_gpCtx()),
		"越界下标被拒 / an out-of-range index is refused")
	gpCheck(not GPSymbolSetPortTypeCommand.new(gpPorts, 0, "").gpExecute(_gpCtx()),
		"空用途被拒 / an empty purpose is refused")


func gpTestPortTypeKeysBilingual() -> void:
	for gpKey in ["make_symbol.port_type", "make_symbol.port_type_nozzle",
			"make_symbol.port_type_actuator", "make_symbol.port_type_signal",
			"make_symbol.port_type_terminal"]:
		var gpPair: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
		gpCheck(not gpPair.is_empty(), "键存在 / key present: " + gpKey)
		gpCheck(str(gpPair.get("en", "")) != "", "英文非空 / en non-empty: " + gpKey)


# ---------------------------------------------------------------------------
# A13: the editor's undo stack is reachable and honest
# A13：编辑器的撤销栈可达且诚实
# ---------------------------------------------------------------------------

func gpTestEditorUndoStackReacts() -> void:
	var gpEd: GPSymbolEditor = GPSymbolEditor.new()
	gpEd.gpInit([], [])
	gpCheck(not gpEd.gpCanUndo(), "初始不可撤销 / nothing to undo at first")
	var gpP: GPPort = GPPort.new()
	gpP.gpName = "P1"
	gpEd.gpAddPort(gpP)
	gpCheck(gpEd.gpCanUndo(), "加端口后可撤销 / a port makes undo available")
	gpCheck(gpEd.gpUndoLabel() != "", "撤销标签非空 / the undo label is non-empty")
	gpCheck(gpEd.gpUndo(), "撤销成功 / undo succeeds")
	gpEq(gpEd.gpPorts.size(), 0, "撤销后端口移除 / the port is gone after undo")
	gpCheck(gpEd.gpCanRedo(), "撤销后可重做 / redo is available afterwards")


func gpTestUndoButtonKeysBilingual() -> void:
	for gpKey in ["make_symbol.undo", "make_symbol.redo"]:
		var gpPair: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
		gpCheck(not gpPair.is_empty(), "键存在 / key present: " + gpKey)
		gpCheck(str(gpPair.get("zh", "")) != "", "中文非空 / zh non-empty: " + gpKey)


# ---------------------------------------------------------------------------
# A14: the new-symbol entry exists and dispatches
# A14：新建图元入口存在且可分派
# ---------------------------------------------------------------------------

func gpTestMenuCarriesNewSymbol() -> void:
	var gpFound: bool = false
	for gpEntry in (GPPIDMenuBar.GP_MENUS["menu.insert"] as Array):
		if gpEntry == null:
			continue
		var gpPair: Array = gpEntry as Array
		if gpPair.size() >= 2 and str(gpPair[1]) == "insert_symbol":
			gpFound = true
	gpCheck(gpFound, "插入菜单含新建图元 / the Insert menu carries New Symbol")
	var gpPair2: Dictionary = I18n.GP_STRINGS.get("menu.insert_symbol", {})
	gpCheck(not gpPair2.is_empty(), "菜单词条存在 / the menu key exists")
	gpCheck(str(gpPair2.get("en", "")) != "", "菜单词条有英文 / the menu key has en")


func gpTestDeadCustomEntryIsGone() -> void:
	# The "custom symbol editor: TODO" status key and the toolbar's custom tool must be gone from
	# the table — a dead word is how the old UI lied, and A14 deletes rather than wires the ones
	# that have no feature behind them.
	# 「自定义图元编辑器：待接入」状态词条与工具条的 custom 工具必须从表中消失 —— 死词条正是旧界面
	# 撒谎的方式，而对背后没有功能的那些，A14 选择删除而不是接线。
	gpCheck(not I18n.GP_STRINGS.has("status.custom_pending"), "死状态词条已删 / the dead status key is gone")
	gpCheck(not I18n.GP_STRINGS.has("symbol_lib.tool_custom"), "死工具词条已删 / the dead tool key is gone")


# ---------------------------------------------------------------------------
# A15: arcs survive promotion into a symbol
# A15：圆弧经提升后仍在
# ---------------------------------------------------------------------------

func gpTestArcSurvivesPromotion() -> void:
	var gpShapes: Array[GPShape] = []
	gpShapes.append(GPShape.gpLine(Vector2(0.0, 0.0), Vector2(40.0, 0.0)))
	gpShapes.append(GPShape.gpCircle(Vector2(20.0, 20.0), 5.0))
	# Center (10,30), radius 20 -> start/end on the circle; a quarter sweep.
	# 圆心 (10,30)、半径 20：起止点在圆上，扫掠四分之一圈。
	gpShapes.append(GPShape.gpArc(Vector2(10.0, 30.0), Vector2(30.0, 30.0), Vector2(10.0, 50.0)))
	# The annotation editor is constructed AROUND its canvas (its _init takes it), and
	# gpShapesToDraft() is a pure projection that never touches the canvas — so one bare canvas
	# is enough to exercise the projection.
	# 注释编辑器是**围绕**其画布构造的（_init 接收画布），而 gpShapesToDraft() 是不碰画布的纯投影 ——
	# 故一个裸画布足以驱动该投影。
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpEd: GPAnnotationEditor = GPAnnotationEditor.new(gpCv)
	var gpDraft: Dictionary = gpEd.gpShapesToDraft(gpShapes)
	gpCheck(gpDraft.has("arcs"), "草稿含 arcs 键 / the draft carries an arcs array")
	gpEq((gpDraft.get("arcs", []) as Array).size(), 1, "圆弧未被丢弃 / the arc is not dropped")
	gpEq((gpDraft.get("paths", []) as Array).size(), 1, "直线仍在 / the line is still there")
	gpEq((gpDraft.get("circles", []) as Array).size(), 1, "圆仍在 / the circle is still there")

	# Round-trip through the dialog's own rehydration path.
	# 经对话框自身的还原路径往返一次。
	var gpBack: Array[GPShape] = GPShapeSpec.gpFromSpec(gpDraft)
	var gpArcCount: int = 0
	for gpS in gpBack:
		if gpS.gpKind == GPShape.GPKind.GP_ARC:
			gpArcCount += 1
	gpEq(gpArcCount, 1, "还原后仍有一段圆弧 / one arc survives the round-trip")
	gpCv.free()
