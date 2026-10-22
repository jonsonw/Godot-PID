extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# B08: the open-end note — text annotation entity + edge reference + one-step command.
# B08：开口端注记 —— 文字注释实体 + 边端引用 + 一步命令。
#
# The four promises / 四条承诺：
#   1. THE NOTE IS AN OBJECT. Writing a note CREATES a GP_TEXT annotation carrying its own uid and
#      text; the edge only stores the uid. Deleting the object must make the DRC see "no note".
#      **注记是对象**。写注记会**创建**携带自身 uid 与文字的文字注释；边只存 uid。删掉对象后
#      DRC 必须看到「没有注记」。
#   2. ONE STEP. Create / edit / clear are each a single undo step, and undo removes the object it
#      created (not just the reference).
#      **一步**。创建 / 改写 / 清除各为一步撤销，且撤销要连同它创建的对象一起移除，而不只是去掉引用。
#   3. NO NOTE ON A CONNECTED END. A note describes an open end; attaching one to a fully connected
#      pipe is refused, not silently accepted.
#      **已连接端不许挂注记**。注记说明的是开口端；给两端都接上的管线挂注记要被拒，而不是默默接受。
#   4. THE TEXT LIVES IN EXACTLY ONE PLACE. Editing the annotation changes what the edge resolves;
#      the edge never keeps a stale copy.
#      **文字只有一个来源**。改注释即改边解析出的文字；边绝不保留过期副本。

const GP_EPS: float = 0.001


# A graph with one fully connected pipe and one pipe with a dangling start (the open end).
# 一张图：一条两端都接上的管线，一条起点悬空的管线（那个开口端）。
func _gpGraph() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1001", Vector2(100.0, 100.0)))
	gpG.gpAddNode(gpG.gpNewNode("n2", "DVALVE001", "V-201", Vector2(300.0, 100.0)))
	# The factory only CONSTRUCTS the edge — gpAddEdge() is what puts it in the graph. Looking it
	# up before adding returns null, which then poisons the graph with a null edge.
	# 工厂只**构造**边 —— 把它放进图的是 gpAddEdge()。在加入之前查找会返回 null，
	# 那会把一条 null 边塞进图里。
	var gpE1: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": ""}, {"node_id": "n2", "port_id": ""},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE1)
	# e2: starts in empty space (dangling start), ends on n2.
	# e2：起点在空白处（悬空起点），终点接 n2。
	var gpE2: GPPIDEdge = gpG.gpNewEdgeEx("e2",
		{"node_id": "", "point": [50.0, 200.0]},
		{"node_id": "n2", "port_id": ""}, GPPIDEdge.GP_PROCESS, "", "PL-2")
	gpG.gpAddEdge(gpE2)
	return gpG


func _gpCtx(gpGraph: GPPIDGraph) -> GPCommandContext:
	return GPCommandContext.new(gpGraph, GPIdGen.new(), null)


# Find the annotation referenced by one end (null when none).
# 找某一端引用的注释（无则 null）。
func _gpNoteOf(gpG: GPPIDGraph, gpEid: String, gpIsFrom: bool) -> GPShape:
	var gpE: GPPIDEdge = gpG.gpGetEdge(gpEid)
	if gpE == null:
		return null
	var gpUid: String = gpE.gpEndNoteUid(gpIsFrom)
	if gpUid == "":
		return null
	for gpS in gpG.gpShapes:
		if gpS != null and gpS.gpUid == gpUid:
			return gpS
	return null


# ---------------------------------------------------------------------------
# 1) Creating the note creates an OBJECT
# 1）写注记 = 创建对象
# ---------------------------------------------------------------------------

func gpTestFirstNoteCreatesAnnotation() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPSetEndNoteCommand = GPSetEndNoteCommand.new(gpG, "e2", true, "TO ATM")
	gpCheck(gpCmd.gpExecute(gpCtx), "写入成功 / the note is written")
	gpEq(gpG.gpShapes.size(), 1, "创建了一个注释对象 / one annotation object exists")
	var gpNote: GPShape = _gpNoteOf(gpG, "e2", true)
	gpCheck(gpNote != null, "边端引用了它 / the edge references it")
	if gpNote != null:
		gpEq(gpNote.gpKind, GPShape.GPKind.GP_TEXT, "它是文字注释 / it is a text annotation")
		gpEq(gpNote.gpText, "TO ATM", "文字写进了对象 / the text lives on the object")
		gpCheck(gpNote.gpUid != "", "对象有 uid / the object has a uid")
		# The anchor sits OUTSIDE the end (not exactly on it), so the note does not cover the
		# pipe end it describes.
		# 锚点在端**外**（不与端重合），故注记不会压住它所说明的管端。
		gpCheck(gpNote.gpPoints[0].distance_to(Vector2(50.0, 200.0)) > 0.5,
			"锚点在端外 / the anchor sits outside the end")


func gpTestEditingWritesThroughToOnePlace() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	GPSetEndNoteCommand.new(gpG, "e2", true, "TO ATM").gpExecute(gpCtx)
	var gpNote: GPShape = _gpNoteOf(gpG, "e2", true)
	var gpCmd2: GPSetEndNoteCommand = GPSetEndNoteCommand.new(gpG, "e2", true, "VENT")
	gpCheck(gpCmd2.gpExecute(gpCtx), "改写成功 / editing succeeds")
	gpEq(gpG.gpShapes.size(), 1, "没有多造一个对象 / no second object is created")
	gpEq(gpNote.gpText, "VENT", "同一个对象的文字被改 / the same object's text changed")


# ---------------------------------------------------------------------------
# 2) One step in each direction
# 2）两个方向都是一步
# ---------------------------------------------------------------------------

func gpTestUndoRemovesCreatedAnnotation() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPSetEndNoteCommand = GPSetEndNoteCommand.new(gpG, "e2", true, "DRAIN")
	gpCmd.gpExecute(gpCtx)
	gpCmd.gpUndo(gpCtx)
	gpEq(gpG.gpShapes.size(), 0, "撤销移除了注入的对象 / undo removes the annotation it created")
	gpEq(gpG.gpGetEdge("e2").gpEndNoteUid(true), "", "引用也清掉了 / the reference is cleared")
	gpCmd.gpRedo(gpCtx)
	gpEq(gpG.gpShapes.size(), 1, "重做恢复对象 / redo restores the object")
	gpCheck(_gpNoteOf(gpG, "e2", true) != null, "重做恢复引用 / redo restores the reference")


func gpTestClearTextDetachesWithoutDeletingForeignNote() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	# A note that already existed (not created by the command being undone).
	# 一个**本就不由该命令创建**的注记。
	var gpExisting: GPShape = GPShape.gpTextNote(Vector2(10.0, 10.0), "TO FLARE")
	gpExisting.gpUid = "t-existing"
	gpG.gpAddShape(gpExisting)
	gpG.gpGetEdge("e2").gpSetEndNoteUid(true, "t-existing")
	var gpCmd: GPSetEndNoteCommand = GPSetEndNoteCommand.new(gpG, "e2", true, "")
	gpCheck(gpCmd.gpExecute(gpCtx), "清除成功 / clearing succeeds")
	gpEq(gpG.gpGetEdge("e2").gpEndNoteUid(true), "", "引用被解除 / the reference is dropped")
	gpEq(gpG.gpShapes.size(), 1, "别人的注记对象不被删 / a foreign annotation is not deleted")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpG.gpGetEdge("e2").gpEndNoteUid(true), "t-existing", "撤销恢复引用 / undo restores the ref")


# ---------------------------------------------------------------------------
# 3) A connected end refuses a note
# 3）已连接端拒绝注记
# ---------------------------------------------------------------------------

func gpTestConnectedEndRefusesNote() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPSetEndNoteCommand = GPSetEndNoteCommand.new(gpG, "e1", true, "TO ATM")
	gpCheck(not gpCmd.gpExecute(gpCtx), "两端都接上的边被拒 / a fully connected pipe is refused")
	gpEq(gpG.gpShapes.size(), 0, "拒绝时不创建对象 / nothing is created on refusal")


func gpTestMissingEdgeRefused() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	gpCheck(not GPSetEndNoteCommand.new(gpG, "nope", true, "TO ATM").gpExecute(gpCtx),
		"不存在的边被拒 / a missing edge is refused")


# ---------------------------------------------------------------------------
# 4) Model plumbing: text annotation serde + extent + spec round trip
# 4）模型管线：文字注释序列化 + 外框 + 规格往返
# ---------------------------------------------------------------------------

func gpTestTextAnnotationRoundTripsThroughDict() -> void:
	var gpS: GPShape = GPShape.gpTextNote(Vector2(12.0, 34.0), "TO ATM\n第二行", 5.0)
	gpS.gpUid = "t-1"
	var gpD: Dictionary = gpS.gpToDict()
	var gpBack: GPShape = GPShape.new()
	gpBack.gpFromDict(gpD)
	gpEq(gpBack.gpKind, GPShape.GPKind.GP_TEXT, "种类还原 / the kind survives")
	gpEq(gpBack.gpText, "TO ATM\n第二行", "文字还原（含换行）/ text survives, newline included")
	gpApprox(gpBack.gpTextSize, 5.0, GP_EPS, "字号还原 / the size survives")
	gpApprox(gpBack.gpPoints[0].x, 12.0, GP_EPS, "锚点还原 / the anchor survives")


func gpTestTextExtentIsPositiveAndGrowsWithText() -> void:
	var gpS: GPShape = GPShape.gpTextNote(Vector2.ZERO, "TO ATM", 3.5)
	var gpShort: Vector2 = gpS.gpTextExtent()
	gpS.gpText = "TO ATM AND ALSO THIS"
	var gpLong: Vector2 = gpS.gpTextExtent()
	gpCheck(gpShort.x > 0.0 and gpShort.y > 0.0, "外框为正 / the extent is positive")
	gpCheck(gpLong.x > gpShort.x, "更长的文字更宽 / longer text is wider")


func gpTestTextSurvivesSpecRoundTrip() -> void:
	var gpShapes: Array[GPShape] = [GPShape.gpTextNote(Vector2(5.0, 6.0), "VENT")]
	var gpSpec: Dictionary = GPShapeSpec.gpEditSpec(gpShapes)
	gpEq((gpSpec.get("texts", []) as Array).size(), 1, "规格携带文字 / the spec carries the text")
	var gpBack: Array[GPShape] = GPShapeSpec.gpFromSpec(gpSpec)
	var gpTextCount: int = 0
	for gpS in gpBack:
		if gpS.gpKind == GPShape.GPKind.GP_TEXT and gpS.gpText == "VENT":
			gpTextCount += 1
	gpEq(gpTextCount, 1, "规格往返保留文字 / the text survives the spec round trip")


func gpTestTextIsHittableAsABlock() -> void:
	var gpS: GPShape = GPShape.gpTextNote(Vector2(0.0, 0.0), "TO ATM", 4.0)
	var gpBox: Rect2 = gpS.gpBBox()
	# A point inside the block is a hit even if it is between glyph strokes.
	# 块内的点即命中 —— 即使它落在字缝之间。
	gpCheck(GPGeometry.gpShapeHit(gpBox.get_center(), gpS, 0.0), "块中心可命中 / the centre is a hit")
	gpCheck(not GPGeometry.gpShapeHit(gpBox.end + Vector2(50.0, 50.0), gpS, 0.0),
		"块外不命中 / a far point misses")


# ---------------------------------------------------------------------------
# 5) The open-end sheet in the list export (ADR-34 D6)
# 5）清单导出里的开口端工作表（ADR-34 D6）
# ---------------------------------------------------------------------------
# The deliverable must SAY which ends are open and what they are, not leave it to the drawing.
# 交付物必须**说出**哪些端是开口、它们叫什么，而不是把它留给图纸。

func gpTestOpenEndRowsOnePerDanglingEnd() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	GPSetEndNoteCommand.new(gpG, "e2", true, "TO ATM").gpExecute(gpCtx)
	var gpRows: Array[Dictionary] = GPListBasic.gpOpenEndRows(gpG)
	gpEq(gpRows.size(), 1, "只有一个悬空端 / exactly one dangling end")
	if gpRows.size() == 1:
		gpEq(str(gpRows[0].get("side", "")), "from", "记录的是起点那端 / the start is reported")
		gpEq(str(gpRows[0].get("note", "")), "TO ATM", "带着注记文字 / the note travels with it")
		gpEq(str(gpRows[0].get("tag", "")), "PL-2", "带着管线号 / the line number travels too")


func gpTestUnnotedOpenEndStillListed() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpRows: Array[Dictionary] = GPListBasic.gpOpenEndRows(gpG)
	gpEq(gpRows.size(), 1, "未注明的开口端也出行 / an unnoted open end still gets a row")
	if gpRows.size() == 1:
		gpEq(str(gpRows[0].get("note", "")), "", "注记为空 / its note is empty")


func gpTestOpenEndSheetWritesCsv() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	GPSetEndNoteCommand.new(gpG, "e2", true, "VENT").gpExecute(gpCtx)
	var gpDir: String = "user://b08_open_ends"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(gpDir))
	var gpPath: String = GPListBasic.gpExportOpenEnds(gpG, gpDir)
	gpCheck(gpPath != "", "写出工作表 / the sheet is written")
	gpCheck(FileAccess.file_exists(gpPath), "文件存在 / the file exists")
	var gpText: String = FileAccess.get_file_as_string(gpPath)
	gpCheck(gpText.contains("VENT"), "CSV 含注记文字 / the CSV carries the note text")
	gpCheck(gpText.contains("PL-2"), "CSV 含管线号 / the CSV carries the line number")


# ---------------------------------------------------------------------------
# 6) Finishing a half-drawn line as an open end (the user's own gesture)
# 6）把画到一半的线以开口端结束（用户自己的手势）
# ---------------------------------------------------------------------------
# This exists because the first version only offered the note on an EXISTING edge: while drawing,
# right-click opened the sheet menu (nothing useful) and closing it with ESC dropped the draft —
# the line "vanished". The gesture now is: draw from the port, right-click, pick the open-end note,
# confirm → edge + note in ONE step; cancelling keeps the draft.
# 这段存在的原因：第一版只在**已有边**上提供注记 —— 画线中途右键打开的是全图纸菜单（没有相关项），
# 用 ESC 关掉就丢掉草稿，线就「凭空消失」了。现在的手势是：从端口画出来 → 右键 → 选开口端注记 →
# 确认 → 边 + 注记**一步**完成；取消则草稿保留。

# A canvas + a pipe tool wired DIRECTLY to it (not through the mode registry): the registry is
# filled by the canvas' _ready(), which a headless harness does not always run — and the promises
# under test (pending state, finish-as-open-end) do not depend on the registry at all.
# 画布 + **直连**它的管道工具（不经模式注册表）：注册表由画布的 _ready() 填装，而 headless 夹具并不
# 总会触发 _ready —— 而被测的承诺（待完成状态、以开口端结束）根本不依赖注册表。
func _gpToolFixture() -> Array:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCv.size = Vector2(800.0, 600.0)
	add_child(gpCv)
	# _ready() is not guaranteed to have run in a headless harness, and the context menu delegate
	# (which this suite also drives) is assembled there. Building the delegates explicitly keeps the
	# test independent of WHO added the canvas to the tree.
	# headless 夹具不保证 _ready() 已跑，而右键委托正是在那里装配的。显式装配一次，使测试不依赖
	# 「是谁把画布加入树的」。
	if gpCv.gpContextMenu == null:
		gpCv._gpBuildDelegates()
		gpCv._gpBuildInputTools()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1", Vector2(100.0, 100.0)))
	gpCv.gpGraph = gpG
	var gpCtx: GPCanvasToolContext = GPCanvasToolContext.new(gpCv)
	var gpTool: GPPipeTool = GPPipeTool.new()
	gpTool.gpCtx = gpCtx
	return [gpCv, gpTool]


func gpTestPendingLineIsDetectable() -> void:
	var gpPair: Array = _gpToolFixture()
	var gpCv: GPCanvas2D = gpPair[0] as GPCanvas2D
	var gpTool: GPPipeTool = gpPair[1] as GPPipeTool
	gpCheck(not gpTool.gpIsPending(), "未起线时无待完成 / nothing pending before the first press")
	gpTool.gpOnPress(Vector2(100.0, 100.0), false, false)
	gpCheck(gpTool.gpIsPending(), "起线后有待完成 / pending after the first press")
	gpCv.queue_free()


func gpTestFinishAsOpenEndCreatesEdgeAndNoteInOneStep() -> void:
	var gpPair: Array = _gpToolFixture()
	var gpCv: GPCanvas2D = gpPair[0] as GPCanvas2D
	var gpTool: GPPipeTool = gpPair[1] as GPPipeTool
	var gpG: GPPIDGraph = gpCv.gpGraph
	gpTool.gpOnPress(Vector2(100.0, 100.0), false, false)
	var gpId: String = gpTool.gpFinishOpenEnd(Vector2(400.0, 300.0), "TO ATM")
	gpCheck(gpId != "", "结束成功 / the line is finished")
	gpEq(gpG.gpEdges.size(), 1, "边已创建 / the edge exists")
	gpEq(gpG.gpShapes.size(), 1, "注记对象已创建 / the note object exists")
	var gpE: GPPIDEdge = gpG.gpEdges[0]
	gpCheck(gpE.gpIsDangling(false), "终点是开口端 / the far end is an open end")
	gpEq(str(gpE.gpEndNoteUid(false)), gpG.gpShapes[0].gpUid, "端点引用了注记 / the end references it")
	gpEq(gpG.gpShapes[0].gpText, "TO ATM", "注记文字正确 / the note text is right")
	# ONE step: a single undo removes the edge AND the note.
	# **一步**：单次撤销同时移除边与注记。
	gpEq(gpCv.gpActions.gpUndo(), true, "可撤销 / undoable")
	gpEq(gpG.gpEdges.size(), 0, "撤销移除边 / undo removes the edge")
	gpEq(gpG.gpShapes.size(), 0, "撤销移除注记 / undo removes the note")
	gpCv.queue_free()


func gpTestFinishRefusedKeepsNothingHalfDone() -> void:
	# A dangling-to-dangling line is not a pipe; the command must refuse AND leave no note behind.
	# 两端皆空的线不是管线；命令必须拒绝且**不留**注记。
	var gpPair: Array = _gpToolFixture()
	var gpCv: GPCanvas2D = gpPair[0] as GPCanvas2D
	var gpTool: GPPipeTool = gpPair[1] as GPPipeTool
	var gpG: GPPIDGraph = gpCv.gpGraph
	# First press in empty space (a dangling start), then finish in empty space.
	# 先在空白处按下（悬空起点），再在空白处结束。
	gpTool.gpOnPress(Vector2(300.0, 300.0), false, false)
	var gpId: String = gpTool.gpFinishOpenEnd(Vector2(400.0, 300.0), "VENT")
	gpEq(gpId, "", "两端皆空被拒 / both ends free is refused")
	gpEq(gpG.gpEdges.size(), 0, "没有边 / no edge")
	gpEq(gpG.gpShapes.size(), 0, "没有注记 / no note")
	gpCv.queue_free()


func gpTestFinishOpenEndCommandIsOneUndoStep() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1", Vector2(100.0, 100.0)))
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG, GPIdGen.new(), null)
	var gpCmd: GPFinishOpenEndCommand = GPFinishOpenEndCommand.new(
		{"node_id": "n1", "port_id": ""}, {"node_id": "", "point": [300.0, 100.0]},
		GPPIDEdge.GP_PROCESS, "", "TO ATM", false)
	gpCheck(gpCmd.gpExecute(gpCtx), "命令执行成功 / the command succeeds")
	gpEq(gpG.gpEdges.size(), 1, "边已建 / the edge exists")
	gpEq(gpG.gpShapes.size(), 1, "注记已建 / the note exists")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpG.gpEdges.size(), 0, "撤销移除边 / undo removes the edge")
	gpEq(gpG.gpShapes.size(), 0, "撤销移除注记 / undo removes the note")
	gpCmd.gpRedo(gpCtx)
	gpEq(gpG.gpEdges.size(), 1, "重做恢复边 / redo restores the edge")
	gpEq(gpG.gpShapes.size(), 1, "重做恢复注记 / redo restores the note")


# ---------------------------------------------------------------------------
# 7) Discoverability: the command must EXIST in the menu for an existing open end
# 7）可发现性：已有开口端时，菜单里必须真的出现这条命令
# ---------------------------------------------------------------------------
# The bug report was "右鍵菜單裡沒有添加注釋文本的命令" — so this pins the menu CONTENT, not just
# the command behind it. A feature nobody can find is not delivered.
# 用户的报告是「右键菜单里没有添加注释文本的命令」—— 故本测试钉的是**菜单内容**，而不只是背后的
# 命令。找不到的功能等于没交付。

func gpTestPendingMenuOffersTheNoteCommand() -> void:
	# The reported bug was "右键菜单里没有添加注释文本的命令" — in the state the user was in
	# (half-drawn line), so the test drives THAT state and reads the menu it produces.
	# 用户报告的是「右键菜单里没有添加注释文本的命令」—— 且是在**他所在的状态**（线画到一半），
	# 故本测试驱动那个状态并读它产出的菜单。
	var gpPair: Array = _gpToolFixture()
	var gpCv: GPCanvas2D = gpPair[0] as GPCanvas2D
	var gpTool: GPPipeTool = gpPair[1] as GPPipeTool
	gpTool.gpOnPress(Vector2(100.0, 100.0), false, false)
	# The menu is built by the canvas' context menu delegate; the fixture canvas is in-tree, so the
	# delegate exists. (The tool is wired directly, so the delegate's own pending probe would return
	# null — that is why the menu is shown through the explicit entry point here.)
	# 菜单由画布的右键委托构建；夹具画布已入树，故委托存在。（工具是直连的，委托自己的
	# 「是否有半成品」探测会返回 null —— 这正是此处走显式入口显示菜单的原因。）
	gpCv.gpContextMenu.gpShowPendingMenu()
	var gpMenu: PopupMenu = null
	for gpC in gpCv.get_children():
		if gpC is PopupMenu:
			gpMenu = gpC as PopupMenu
	gpCheck(gpMenu != null, "菜单已创建 / the menu is created")
	if gpMenu == null:
		gpCv.queue_free()
		return
	var gpFoundNote: bool = false
	var gpFoundCancel: bool = false
	for gpI in range(gpMenu.item_count):
		var gpText: String = gpMenu.get_item_text(gpI)
		if gpText.contains(I18n.gpTr("open_end.menu")):
			gpFoundNote = true
		if gpText.contains(I18n.gpTr("canvas.ctx_cancel_line")):
			gpFoundCancel = true
	gpCheck(gpFoundNote, "菜单含「开口端注记…」/ the menu carries the open-end note item")
	gpCheck(gpFoundCancel, "菜单含「取消这条线」/ the menu carries the drop-line item")
	gpCv.queue_free()


# ---------------------------------------------------------------------------
# 8) The DWELL trigger (user's proposal: stop moving → the choice appears)
# 8）悬停触发（用户提的方案：停住 → 选项出现）
# ---------------------------------------------------------------------------
# The right-click path was not discoverable enough in practice, and the user proposed the better
# gesture: STOP and the prompt appears, KEEP MOVING and it disappears. That is a pure state machine
# over (pending, cursor, time) — so it is tested as one, without any UI.
# 实机里右键路径不够可发现，用户提出了更好的手势：**停住**出现提示，**继续移动**则消失。
# 这是一个只依赖（待完成, 光标, 时间）的状态机 —— 故按状态机测试，不碰界面。

func gpTestDwellShowsOnlyAfterStillness() -> void:
	var gpD: GPDwellPrompt = GPDwellPrompt.new()
	var gpShown: Array = []
	gpD.gpShow.connect(func(gpW: Vector2) -> void: gpShown.append(gpW))
	# t=0: first sample starts tracking but nothing is shown yet.
	# t=0：首次采样开始跟踪，但还不显示。
	gpD.gpNoticeCursor(Vector2(10.0, 10.0), Vector2(100.0, 100.0), 0)
	gpD.gpTick(true, 100)
	gpEq(gpShown.size(), 0, "刚起线不立即显示 / nothing shows immediately")
	gpD.gpTick(true, GPDwellPrompt.GP_DELAY_MS + 10)
	gpEq(gpShown.size(), 1, "静止够久后显示 / shown after the dwell delay")


func gpTestDwellHidesOnRealMovementAndRearms() -> void:
	var gpD: GPDwellPrompt = GPDwellPrompt.new()
	var gpStates: Array = []
	gpD.gpShow.connect(func(_gpW: Vector2) -> void: gpStates.append("show"))
	gpD.gpHide.connect(func() -> void: gpStates.append("hide"))
	gpD.gpNoticeCursor(Vector2.ZERO, Vector2.ZERO, 0)
	gpD.gpTick(true, 600)
	gpEq(gpStates, ["show"], "先显示 / shown first")
	# Move beyond the hold radius: hides, and a NEW stillness is required before showing again.
	# 移出保持半径：隐藏，且需要**新的**静止才会再次显示。
	gpD.gpNoticeCursor(Vector2(5.0, 5.0), Vector2(200.0, 0.0), 700)
	gpEq(gpStates, ["show", "hide"], "移动后隐藏 / hidden on movement")
	gpD.gpTick(true, 800)
	gpEq(gpStates, ["show", "hide"], "移动后不立刻再显示 / not re-shown immediately")
	gpD.gpTick(true, 700 + GPDwellPrompt.GP_DELAY_MS + 10)
	gpEq(gpStates, ["show", "hide", "show"], "再次静止后再显示 / shown again after new stillness")


func gpTestDwellToleratesSmallMovementWhileShown() -> void:
	var gpD: GPDwellPrompt = GPDwellPrompt.new()
	var gpHides: Array = []
	gpD.gpHide.connect(func() -> void: gpHides.append(1))
	gpD.gpNoticeCursor(Vector2.ZERO, Vector2.ZERO, 0)
	gpD.gpTick(true, 600)
	# A small move (towards the prompt itself) must NOT hide it, or it could never be clicked.
	# 小幅移动（朝提示本身）**不得**隐藏，否则它永远点不到。
	gpD.gpNoticeCursor(Vector2(0.2, 0.2), Vector2(8.0, 8.0), 700)
	gpEq(gpHides.size(), 0, "小幅移动不隐藏 / a small move keeps it")


func gpTestDwellResetsWhenLineIsNoLongerPending() -> void:
	var gpD: GPDwellPrompt = GPDwellPrompt.new()
	var gpStates: Array = []
	gpD.gpShow.connect(func(_gpW: Vector2) -> void: gpStates.append("show"))
	gpD.gpHide.connect(func() -> void: gpStates.append("hide"))
	gpD.gpNoticeCursor(Vector2.ZERO, Vector2.ZERO, 0)
	gpD.gpTick(true, 600)
	gpD.gpTick(false, 700)
	gpEq(gpStates, ["show", "hide"], "连线完成后立即隐藏 / hidden as soon as the line completes")


# ---------------------------------------------------------------------------
# 9) Connecting to an EXISTING end-point note (shared open end)
# 9）接到**已有**末端注记（共用开口端）
# ---------------------------------------------------------------------------
# "连接到 end point 的注释文本": the line ends AT an already-annotated open end, so two lines share
# one note. Undo must remove only the new line — the note belongs to the other one.
# 「连接到 end point 的注释文本」：线结束在**已注明**的开口端，两条线共用一条注记。
# 撤销只能移除新线 —— 注记属于另一条线。

func gpTestFinishAttachesToExistingNote() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1", Vector2(100.0, 100.0)))
	var gpNote: GPShape = GPShape.gpTextNote(Vector2(300.0, 100.0), "TO ATM")
	gpNote.gpUid = "t-shared"
	gpG.gpAddShape(gpNote)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG, GPIdGen.new(), null)
	var gpCmd: GPFinishOpenEndCommand = GPFinishOpenEndCommand.new(
		{"node_id": "n1", "port_id": ""}, {"node_id": "", "point": [300.0, 100.0]},
		GPPIDEdge.GP_PROCESS, "", "", false, true, "t-shared")
	gpCheck(gpCmd.gpExecute(gpCtx), "接上已有注记 / attaching to the existing note succeeds")
	gpEq(gpG.gpShapes.size(), 1, "没有新建注记 / no second note is created")
	var gpE: GPPIDEdge = gpG.gpEdges[0]
	gpEq(str(gpE.gpEndNoteUid(false)), "t-shared", "边端引用的是那条注记 / the end references it")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpG.gpEdges.size(), 0, "撤销移除这条边 / undo removes this line")
	gpEq(gpG.gpShapes.size(), 1, "撤销**不**删共用的注记 / undo does NOT delete the shared note")


func gpTestNotesNearFindsTextOnlyWithinRadius() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	add_child(gpCv)
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpNote: GPShape = GPShape.gpTextNote(Vector2(100.0, 100.0), "VENT")
	gpG.gpAddShape(gpNote)
	gpCv.gpGraph = gpG
	gpEq(gpCv._gpNotesNear(Vector2(100.0, 100.0)).size(), 1, "注记处能找到 / found at the note")
	gpEq(gpCv._gpNotesNear(Vector2(400.0, 400.0)).size(), 0, "远处找不到 / not found far away")
	gpCv.queue_free()


# ---------------------------------------------------------------------------
# 10) Post-commit path: an existing open-ended edge offers the note in its own menu
# 10）提交后的路径：已提交的开口端边，其菜单里也提供注记
# ---------------------------------------------------------------------------
# The first fix only covered "while drawing" and "empty space with the edge selected"; right-click
# ON the edge (the obvious place) had the item suppressed by the bump-anchor design. The user's
# report ("线画出来了，但右键没有那个命令") lands here.
# 第一版只覆盖了「画线中途」与「选中边后右键空白处」；而**在边上**右键（最显然的位置）被锚点设计
# 压掉了。用户报告「线画出来了，但右键没有那个命令」正落在这里。

func gpTestEdgeMenuOffersNoteForDanglingEdge() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	add_child(gpCv)
	if gpCv.gpContextMenu == null:
		gpCv._gpBuildDelegates()
		gpCv._gpBuildInputTools()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1", Vector2(100.0, 100.0)))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": ""}, {"node_id": "", "point": [300.0, 100.0]},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE)
	gpCv.gpGraph = gpG
	var gpMenu: PopupMenu = PopupMenu.new()
	gpCv.add_child(gpMenu)
	gpCv.gpContextMenu._gpCtxEdge = "e1"
	gpCv.gpContextMenu._gpBuildMenuItems(gpMenu, "")
	var gpFound: bool = false
	for gpI in range(gpMenu.item_count):
		if gpMenu.get_item_text(gpI).contains(I18n.gpTr("open_end.menu")):
			gpFound = true
	gpCheck(gpFound, "边上右键也有注记命令 / the edge menu carries the note item")
	gpCv.queue_free()


# ---------------------------------------------------------------------------
# 11) Press-and-drag from an anchor must NOT vanish on release
# 11）从锚点按下并拖动，松手时线**不得**消失
# ---------------------------------------------------------------------------
# This was the real gesture the user performed: press on the nozzle (an endpoint anchor), drag to
# empty space, release. The ops class treated "dropped on no anchor" as a CLICK and toggled the
# pick list — so the line existed only while the button was held.
# 这才是用户真实做的手势：按住管嘴（端点锚点）拖到空白再松手。旧代码把「没落在锚点上」当成
# **单击**去切换拾取列表 —— 于是线只在按住时存在。

func _gpPortOpsCanvas() -> GPCanvas2D:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCv.size = Vector2(800.0, 600.0)
	add_child(gpCv)
	# The port-connect ops object is a _ready() delegate; assemble it explicitly so the fixture does
	# not depend on who added the canvas to the tree.
	# 端点连接 ops 是 _ready() 委托；显式装配一次，使夹具不依赖「是谁把画布加入树的」。
	if gpCv.gpPortOps == null:
		gpCv._gpBuildDelegates()
		gpCv._gpBuildInputTools()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1", Vector2(100.0, 100.0)))
	gpCv.gpGraph = gpG
	return gpCv


# Drive the ops class directly: the drag state is its own, and `_gpFrom`/`_gpCursor`/`_gpMoved` are
# exactly what a real drag would have produced.
# 直接驱动 ops 类：拖拽状态由它自持，而 _gpFrom / _gpCursor / _gpMoved 正是真实拖拽留下的状态。
func _gpSeedDrag(gpCv: GPCanvas2D, gpMoved: bool) -> void:
	var gpOps: GPPortConnectOps = gpCv.gpPortOps
	gpOps._gpFrom = {"node_id": "n1", "port_id": "p1", "type": GPPort.GP_NOZZLE,
		"pos": Vector2(100.0, 100.0)}
	gpOps._gpTarget = {}
	gpOps._gpPressWorld = Vector2(100.0, 100.0)
	gpOps._gpCursor = Vector2(400.0, 300.0)
	gpOps._gpMoved = gpMoved


func gpTestDragToEmptySpaceCreatesOpenEnd() -> void:
	var gpCv: GPCanvas2D = _gpPortOpsCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	_gpSeedDrag(gpCv, true)
	var gpOk: bool = gpCv.gpPortOps.gpFinishDrag()
	gpCheck(gpOk, "松手后创建了线 / release creates the line")
	gpEq(gpG.gpEdges.size(), 1, "线还在（没有消失）/ the line survives")
	if gpG.gpEdges.size() == 1:
		gpCheck(gpG.gpEdges[0].gpIsDangling(false), "远端是开口端 / the far end is an open end")
	gpCv.queue_free()


func gpTestClickWithoutMovementStillTogglesPick() -> void:
	var gpCv: GPCanvas2D = _gpPortOpsCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	_gpSeedDrag(gpCv, false)
	gpCv.gpPortOps.gpFinishDrag()
	gpEq(gpG.gpEdges.size(), 0, "单击不画线 / a click draws nothing")
	gpCv.queue_free()


func gpTestDragFinishWithNoteIsOneStep() -> void:
	var gpCv: GPCanvas2D = _gpPortOpsCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	_gpSeedDrag(gpCv, true)
	var gpId: String = gpCv.gpPortOps.gpFinishDragAsOpenEnd("TO ATM")
	gpCheck(gpId != "", "带注记收尾成功 / finishing with a note works")
	gpEq(gpG.gpEdges.size(), 1, "一条边 / one edge")
	gpEq(gpG.gpShapes.size(), 1, "一条注记 / one note")
	gpEq(gpCv.gpActions.gpUndo(), true, "一步撤销 / one undo step")
	gpEq(gpG.gpEdges.size(), 0, "撤销移除边 / undo removes the edge")
	gpEq(gpG.gpShapes.size(), 0, "撤销移除注记 / undo removes the note")
	gpCv.queue_free()


func gpTestDragKindFollowsPortType() -> void:
	var gpCv: GPCanvas2D = _gpPortOpsCanvas()
	gpEq(gpCv.gpPortOps.gpKindOfSource(GPPort.GP_NOZZLE), GPPIDEdge.GP_PROCESS,
		"管口出工艺线 / a nozzle makes a pipe")
	gpEq(gpCv.gpPortOps.gpKindOfSource(GPPort.GP_SIGNAL), GPPIDEdge.GP_SIGNAL,
		"信号端口出信号线 / a signal port makes a signal line")
	gpEq(gpCv.gpPortOps.gpKindOfSource(GPPort.GP_ACTUATOR), GPPIDEdge.GP_SIGNAL,
		"执行机构出信号线 / an actuator makes a signal line")
	gpCv.queue_free()


# ---------------------------------------------------------------------------
# 12) Note ⟷ connection: drop a note on a nozzle, or drag a nozzle out to a note
# 12）注记 ⟷ 连接：把注记丢到管嘴上，或从管嘴拖出生成注记
# ---------------------------------------------------------------------------
# Dropping the text on a nozzle means "this open end is wired now": the lines that ended at the
# note must end at the PORT, and the note must go. Half of that would leave either a dangling line
# (error) or a note describing nothing.
# 把文字丢到管嘴上意味着「这个开口端现在接上了」：终止于注记的线必须改接**端口**，注记必须消失。
# 只做一半，就会要么留下悬空端（错误），要么留下一条描述不了任何东西的注记。

func gpTestNoteDropOnPortConvertsToOneConnection() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1", Vector2(100.0, 100.0)))
	gpG.gpAddNode(gpG.gpNewNode("n2", "DVALVE001", "V-2", Vector2(400.0, 100.0)))
	var gpNote: GPShape = GPShape.gpTextNote(Vector2(300.0, 100.0), "TO ATM")
	gpNote.gpUid = "t-open"
	gpG.gpAddShape(gpNote)
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": ""}, {"node_id": "", "point": [300.0, 100.0]},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpE.gpSetEndNoteUid(false, "t-open")
	gpG.gpAddEdge(gpE)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG, GPIdGen.new(), null)
	var gpCmd: GPConvertNoteToPortCommand = GPConvertNoteToPortCommand.new(gpG, "t-open",
		{"node_id": "n2", "port_id": "in"})
	gpCheck(gpCmd.gpExecute(gpCtx), "转换成功 / the conversion succeeds")
	gpEq(gpG.gpShapes.size(), 0, "注记被移除 / the note is removed")
	gpEq(str(gpE.gpToRef.get("node_id", "")), "n2", "端点接到 n2 / the end is now on n2")
	gpEq(str(gpE.gpToRef.get("port_id", "")), "in", "接到指定端口 / on the named port")
	gpEq(gpE.gpEndNoteUid(false), "", "引用被清掉 / the reference is cleared")
	gpCheck(not gpE.gpIsDangling(false), "不再是开口端 / it is no longer an open end")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpG.gpShapes.size(), 1, "撤销放回注记 / undo restores the note")
	gpCheck(gpE.gpIsDangling(false), "撤销恢复开口端 / undo restores the open end")
	gpEq(gpE.gpEndNoteUid(false), "t-open", "撤销恢复引用 / undo restores the reference")


func gpTestSharedNoteConvertsBothLines() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1", Vector2(100.0, 100.0)))
	gpG.gpAddNode(gpG.gpNewNode("n2", "DVALVE001", "V-2", Vector2(400.0, 100.0)))
	var gpNote: GPShape = GPShape.gpTextNote(Vector2(300.0, 100.0), "TO ATM")
	gpNote.gpUid = "t-shared"
	gpG.gpAddShape(gpNote)
	# Two lines sharing one annotated open end (a header and a drain).
	# 两条线共用同一个已注明的开口端（汇管与排凝）。
	for gpI in range(2):
		var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e%d" % gpI,
			{"node_id": "n1", "port_id": ""}, {"node_id": "", "point": [300.0, 100.0]},
			GPPIDEdge.GP_PROCESS, "", "PL-%d" % gpI)
		gpE.gpSetEndNoteUid(false, "t-shared")
		gpG.gpAddEdge(gpE)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG, GPIdGen.new(), null)
	var gpCmd: GPConvertNoteToPortCommand = GPConvertNoteToPortCommand.new(gpG, "t-shared",
		{"node_id": "n2", "port_id": "in"})
	gpCheck(gpCmd.gpExecute(gpCtx), "共用注记也可转换 / a shared note converts too")
	for gpE2 in gpG.gpEdges:
		gpEq(str(gpE2.gpToRef.get("node_id", "")), "n2", "两条线都接到 n2 / both lines now end at n2")
	gpCmd.gpUndo(gpCtx)
	for gpE3 in gpG.gpEdges:
		gpCheck(gpE3.gpIsDangling(false), "撤销后都回到开口端 / both are open ends again")
	gpEq(gpG.gpShapes.size(), 1, "注记回到图上 / the note is back")


func gpTestDropOnNoPortChangesNothing() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1", Vector2(100.0, 100.0)))
	var gpNote: GPShape = GPShape.gpTextNote(Vector2(300.0, 100.0), "VENT")
	gpNote.gpUid = "t-lonely"
	gpG.gpAddShape(gpNote)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG, GPIdGen.new(), null)
	# No edge references this note: dragging it onto a port must NOT delete it.
	# 没有边引用这条注记：把它拖到端口上**不得**删掉它。
	var gpCmd: GPConvertNoteToPortCommand = GPConvertNoteToPortCommand.new(gpG, "t-lonely",
		{"node_id": "n1", "port_id": "p1"})
	gpCheck(not gpCmd.gpExecute(gpCtx), "无引用时不转换 / nothing to convert")
	gpEq(gpG.gpShapes.size(), 1, "注记仍在 / the note is still there")


func gpTestDialogHasExplicitSize() -> void:
	# The dialog once grew until its OK / Cancel row was off screen. A fixed size is the fix, and
	# this pins that it exists (a regression would silently make the dialog unusable again).
	# 对话框曾经撑到确定/取消跑到屏幕外。固定尺寸就是修复，本测试钉住它存在
	#（回归会让对话框悄悄再次不可用）。
	var gpD: GPEndNoteDialog = GPEndNoteDialog.new()
	gpD.gpBuild()
	gpCheck(gpD.min_size.x > 0 and gpD.min_size.y > 0, "有最小尺寸 / it has a minimum size")
	gpCheck(gpD.min_size.y <= 400, "高度受限（不会铺满屏）/ the height is bounded")
	gpD.free()


# ---------------------------------------------------------------------------
# 13) Dragging the note carries its line; dropping on a nozzle converts it
# 13）拖注记时连线跟随；拖到管嘴上则转成连接
# ---------------------------------------------------------------------------
# The text is the VISIBLE half of the open end; if the line stayed behind, the drawing would say
# "TO ATM" at one place and end the pipe at another.
# 文字是开口端的**可见那一半**；线若留在原处，图纸就会在一处写「TO ATM」、而把管子结束在另一处。

func _gpNoteDragCanvas() -> GPCanvas2D:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCv.size = Vector2(800.0, 600.0)
	add_child(gpCv)
	if gpCv.gpAnno == null:
		gpCv._gpBuildDelegates()
		gpCv._gpBuildInputTools()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1", Vector2(100.0, 100.0)))
	var gpNote: GPShape = GPShape.gpTextNote(Vector2(300.0, 100.0), "TO ATM")
	gpNote.gpUid = "t-move"
	gpG.gpAddShape(gpNote)
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": ""}, {"node_id": "", "point": [300.0, 100.0]},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpE.gpSetEndNoteUid(false, "t-move")
	gpG.gpAddEdge(gpE)
	gpCv.gpGraph = gpG
	return gpCv


func gpTestNoteDragCarriesItsLine() -> void:
	var gpCv: GPCanvas2D = _gpNoteDragCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	gpCv.gpAnno.gpStartShapeDrag(0, Vector2(300.0, 100.0))
	# The edge VIEW re-syncs on the graph signal; mutating the ref alone is invisible, so the
	# follow must announce itself. This counter is what pins that.
	# 边的**视图**在图的信号上重新同步；只改引用是看不见的，故跟随必须自我通告。本计数器钉住它。
	var gpSignals: Array = []
	gpG.gpGraphChanged.connect(func() -> void: gpSignals.append(1))
	gpCv.gpAnno.gpOnShapeMove(Vector2(340.0, 160.0))
	gpCheck(gpSignals.size() > 0, "跟随过程中发出重绘信号 / the follow announces a repaint")
	var gpNote: GPShape = gpG.gpShapes[0]
	var gpE: GPPIDEdge = gpG.gpEdges[0]
	gpApprox(gpNote.gpPoints[0].x, 340.0, 0.001, "注记被拖到新位置 / the note moved")
	gpApprox(gpE.gpDanglingPoint(false).x, gpNote.gpPoints[0].x, 0.001,
		"线端跟随注记 X / the end follows in x")
	gpApprox(gpE.gpDanglingPoint(false).y, gpNote.gpPoints[0].y, 0.001,
		"线端跟随注记 Y / the end follows in y")
	gpCv.gpAnno.gpEndShapeDrag(Vector2(340.0, 160.0))
	# Released over empty space: the note and its line stay together where they were dropped.
	# 松手在空白处：注记与它的线一起留在落点。
	gpEq(gpG.gpShapes.size(), 1, "注记仍在 / the note stays")
	gpApprox(gpE.gpDanglingPoint(false).x, 340.0, 0.001, "线端留在落点 / the end stays at the drop")
	gpCv.queue_free()


func gpTestNoteDragKeepsReference() -> void:
	var gpCv: GPCanvas2D = _gpNoteDragCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	gpCv.gpAnno.gpStartShapeDrag(0, Vector2(300.0, 100.0))
	gpCv.gpAnno.gpOnShapeMove(Vector2(320.0, 120.0))
	gpCv.gpAnno.gpEndShapeDrag(Vector2(320.0, 120.0))
	# Dragging must not quietly DETACH the note: the end still references it, so the DRC still sees
	# a noted open end rather than an unnoted one.
	# 拖动不得悄悄**解除**注记：端点仍引用它，故 DRC 看到的仍是「已注明的开口端」而非未注明。
	gpEq((gpG.gpEdges[0] as GPPIDEdge).gpEndNoteUid(false), "t-move", "引用未丢 / the reference survives")
	gpCv.queue_free()


# ---------------------------------------------------------------------------
# 14) Dropping the note ON a nozzle converts it (hit test must look at the GLYPH, not just the cursor)
# 14）把注记丢在管嘴上就转成连接（命中判定必须看**字形**，不能只看光标）
# ---------------------------------------------------------------------------
# The user drops the word; the cursor usually sits mid-word while the nozzle is at its corner.
# A cursor-only hit test made that visually-correct drop silently do nothing.
# 用户丢的是**这个词**；光标常停在词中间，而管嘴在它的角上。只测光标会让一次「看起来对」的放下
# 静默什么都不做。

func _gpDefWithPort() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "SYM"
	gpD.gpCategory = "equipment"
	gpD.gpDefaultSize = Vector2(40.0, 40.0)
	var gpP: GPPort = GPPort.new()
	gpP.gpName = "p1"
	gpP.gpPos = Vector2(0.5, 0.5)
	gpP.gpType = GPPort.GP_NOZZLE
	gpD.gpPorts = [gpP]
	return gpD


func _gpConvertCanvas() -> GPCanvas2D:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCv.size = Vector2(800.0, 600.0)
	add_child(gpCv)
	if gpCv.gpAnno == null:
		gpCv._gpBuildDelegates()
		gpCv._gpBuildInputTools()
	# Anchors resolve through the BINDER (created in _ready, which a headless harness does not run).
	# 锚点经**绑定器**解析（它在 _ready 里创建，而 headless 夹具不会跑到那里）。
	if gpCv.gpBinder == null:
		gpCv._gpBuildBinder()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "SYM", "P-1", Vector2(100.0, 100.0)))
	gpG.gpAddNode(gpG.gpNewNode("n2", "SYM", "V-2", Vector2(400.0, 100.0)))
	var gpNote: GPShape = GPShape.gpTextNote(Vector2(380.0, 95.0), "TO ATM")
	gpNote.gpUid = "t-drop"
	gpG.gpAddShape(gpNote)
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": ""}, {"node_id": "", "point": [380.0, 95.0]},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpE.gpSetEndNoteUid(false, "t-drop")
	gpG.gpAddEdge(gpE)
	gpCv.gpGraph = gpG
	gpCv.gpDefs = [_gpDefWithPort()]
	if gpCv.gpBinder != null:
		gpCv.gpBinder.gpDefs = gpCv.gpDefs
	return gpCv


func gpTestDropNoteOnNozzleConverts() -> void:
	var gpCv: GPCanvas2D = _gpConvertCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	gpCv.gpAnno.gpStartShapeDrag(0, Vector2(380.0, 95.0))
	gpCv.gpAnno.gpOnShapeMove(Vector2(400.0, 100.0))
	# Release a few units away from the nozzle centre — the note glyph is what was dropped.
	# 松手点离管嘴中心几个单位 —— 被丢下的是**注记字形**。
	gpCv.gpAnno.gpEndShapeDrag(Vector2(402.0, 104.0))
	gpEq(gpG.gpShapes.size(), 0, "注记被移除 / the note is removed")
	if gpG.gpEdges.size() == 1:
		var gpE: GPPIDEdge = gpG.gpEdges[0]
		gpEq(str(gpE.gpToRef.get("node_id", "")), "n2", "线接到管嘴所在图元 / the line ends on the nozzle's symbol")
		gpEq(gpE.gpEndNoteUid(false), "", "引用被清掉 / the reference is cleared")
	gpCv.queue_free()


func gpTestDropFarFromNozzleKeepsNote() -> void:
	var gpCv: GPCanvas2D = _gpConvertCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	gpCv.gpAnno.gpStartShapeDrag(0, Vector2(380.0, 95.0))
	gpCv.gpAnno.gpOnShapeMove(Vector2(250.0, 300.0))
	gpCv.gpAnno.gpEndShapeDrag(Vector2(250.0, 300.0))
	gpEq(gpG.gpShapes.size(), 1, "远处松手注记留下 / a far drop keeps the note")
	gpCv.queue_free()


# ---------------------------------------------------------------------------
# 15) Hovering a port while dragging the note highlights it (visible before release)
# 15）拖注记压到端口上时高亮它（松手前就能看见）
# ---------------------------------------------------------------------------
# "It will connect HERE" must be visible BEFORE the mouse button goes up — otherwise the conversion
# feels like a surprise rather than a choice.
# 「松手就会接到**这里**」必须在抬起之前可见 —— 否则转换像意外，而不是一次选择。

func gpTestNoteDragHighlightsPortUnderIt() -> void:
	var gpCv: GPCanvas2D = _gpConvertCanvas()
	gpCv.gpAnno.gpStartShapeDrag(0, Vector2(380.0, 95.0))
	gpCv.gpAnno.gpOnShapeMove(Vector2(400.0, 100.0))
	gpCheck(not gpCv.gpHoverPort.is_empty(), "拖动时高亮了端口 / a port is highlighted while dragging")
	if not gpCv.gpHoverPort.is_empty():
		gpEq(str(gpCv.gpHoverPort.get("node_id", "")), "n2", "高亮的是目标管嘴 / the target nozzle is lit")
	gpCv.gpAnno.gpEndShapeDrag(Vector2(402.0, 104.0))
	gpCheck(gpCv.gpHoverPort.is_empty(), "松手后高亮清除 / the highlight is cleared on release")
	gpCv.queue_free()


func gpTestHoverClearedWhenDraggedAway() -> void:
	var gpCv: GPCanvas2D = _gpConvertCanvas()
	gpCv.gpAnno.gpStartShapeDrag(0, Vector2(380.0, 95.0))
	gpCv.gpAnno.gpOnShapeMove(Vector2(400.0, 100.0))
	gpCheck(not gpCv.gpHoverPort.is_empty(), "先高亮 / lit first")
	gpCv.gpAnno.gpOnShapeMove(Vector2(200.0, 300.0))
	gpCheck(gpCv.gpHoverPort.is_empty(), "拖离后不再高亮 / unlit when dragged away")
	gpCv.gpAnno.gpEndShapeDrag(Vector2(200.0, 300.0))
	gpCv.queue_free()


# ---------------------------------------------------------------------------
# 16) A dragged bend refreshes the stroke THIS frame (not on release)
# 16）拖动折点必须**本帧**刷新笔迹（不是松手才刷新）
# ---------------------------------------------------------------------------
# Dragging a bend mutated `gpE.gpRouting` and only asked the CANVAS to repaint; the edge view paints
# itself, so the stroke kept its old shape until release triggered a full sync — the reported
# "the line catches up when I let go".
# 拖折点只改了 `gpE.gpRouting` 并请求**画布**重绘；而边视图是自己画的，故笔迹保持旧形状直到松手触发
# 全量同步 —— 即被报告的「松手后线才跟过来」。

func _gpEdgeViewCanvas() -> GPCanvas2D:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCv.size = Vector2(800.0, 600.0)
	add_child(gpCv)
	# The binder needs a world root to parent its views; both are _ready() furniture, so a headless
	# fixture must assemble them explicitly (and in this order).
	# 绑定器需要 world root 来挂视图；两者都是 _ready() 的家具，故 headless 夹具要按此顺序显式装配。
	if gpCv.gpBinder == null or gpCv.gpBinder.gpWorldRoot == null:
		gpCv._gpBuildWorldRoot()
		gpCv._gpBuildBinder()
	if gpCv.gpAnno == null:
		gpCv._gpBuildDelegates()
		gpCv._gpBuildInputTools()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("n1", "DPUMP001", "P-1", Vector2(100.0, 100.0)))
	gpG.gpAddNode(gpG.gpNewNode("n2", "DVALVE001", "V-2", Vector2(400.0, 100.0)))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "n1", "port_id": ""}, {"node_id": "n2", "port_id": ""},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE)
	gpCv.gpGraph = gpG
	# Sync the binder directly: the signal path needs a wired world root, and this test only cares
	# about the view refresh primitive.
	# 直接同步绑定器：信号路径需要已接线的 world root，而本测试只关心「视图刷新」这一原语。
	gpCv.gpBinder.gpSync(gpG, gpCv.gpDefs, [], "", gpCv.gpViewZoom)
	return gpCv


func gpTestBendDragRefreshesStrokeImmediately() -> void:
	var gpCv: GPCanvas2D = _gpEdgeViewCanvas()
	var gpG: GPPIDGraph = gpCv.gpGraph
	var gpV: GPEdgeView = gpCv.gpBinder.gpGetEdgeView("e1")
	gpCheck(gpV != null, "边视图已建 / the edge view exists")
	if gpV == null:
		gpCv.queue_free()
		return
	# Give the edge a bend well away from the straight line, then refresh in place.
	# 给边一个偏离直线的折点，然后就地刷新。
	var gpE: GPPIDEdge = gpG.gpGetEdge("e1")
	gpE.gpRouting = [Vector2(250.0, 250.0)] as Array[Vector2]
	var gpBefore: PackedVector2Array = gpV.gpInkLine.points
	gpCheck(gpCv.gpRedrawEdge("e1"), "就地刷新成功 / the in-place refresh succeeds")
	var gpAfter: PackedVector2Array = gpV.gpInkLine.points
	gpCheck(gpAfter.size() >= 2, "笔迹有端点 / the stroke has points")
	# The stroke must now pass through the new bend, i.e. it differs from the straight-line points.
	# 笔迹现在必须经过新折点，即与直线点集不同。
	var gpDiffers: bool = gpAfter.size() != gpBefore.size()
	if not gpDiffers:
		for gpI in range(mini(gpAfter.size(), gpBefore.size())):
			if gpAfter[gpI] != gpBefore[gpI]:
				gpDiffers = true
				break
	gpCheck(gpDiffers, "折点改变了笔迹 / the bend changed the stroke")
	gpCv.queue_free()


# ---------------------------------------------------------------------------
# 17) Pipes hang on NOZZLES (child nodes), so a vessel drag must refresh the SUBTREE
# 17）管线挂的是**管口**（子件），故拖动设备必须刷新**子树**
# ---------------------------------------------------------------------------
# A nozzle's world position is DERIVED from its parent, so dragging the vessel changes the nozzle
# without touching its own gpPosition. Refreshing only the dragged id therefore left every
# nozzle-connected pipe behind until release. This pins the primitive's semantics; the tool then
# expands the dragged ids with gpSubtree() before calling it.
# 管口的世界位置由父链**推导**，故拖动设备会改变管口、却不动作它自己的 gpPosition。
# 只刷新被拖 id 时，所有接管口的线都被留在原处直到松手。本测试钉住原语的语义；工具在调用前
# 用 gpSubtree() 把被拖 id 展开。

func gpTestEdgeRefreshFollowsChildNozzles() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	add_child(gpCv)
	if gpCv.gpBinder == null or gpCv.gpBinder.gpWorldRoot == null:
		gpCv._gpBuildWorldRoot()
		gpCv._gpBuildBinder()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("host", "DVESSEL001", "V-1", Vector2(100.0, 100.0)))
	var gpChild: GPPIDNode = gpG.gpNewNode("nozzle", "DNOZZLE001", "", Vector2(130.0, 100.0))
	gpChild.gpParentUid = "host"
	gpChild.gpMountAnchor = "top"
	gpG.gpAddNode(gpChild)
	gpG.gpAddNode(gpG.gpNewNode("tank", "DVESSEL001", "T-2", Vector2(400.0, 100.0)))
	var gpE: GPPIDEdge = gpG.gpNewEdgeEx("e1",
		{"node_id": "nozzle", "port_id": ""}, {"node_id": "tank", "port_id": ""},
		GPPIDEdge.GP_PROCESS, "", "PL-1")
	gpG.gpAddEdge(gpE)
	gpCv.gpGraph = gpG
	gpCv.gpBinder.gpSync(gpG, gpCv.gpDefs, [], "", gpCv.gpViewZoom)
	# The primitive matches by the ids it is GIVEN: the child id finds the pipe, the host id alone
	# does not — that is why the tool must expand with gpSubtree().
	# 原语按**传入的** id 匹配：子件 id 能找到管线，只给宿主 id 找不到 —— 这正是工具必须用
	# gpSubtree() 展开的原因。
	gpEq(gpCv.gpBinder.gpRedrawEdgesForNodes(["nozzle"]).size(), 1,
		"子件 id 能找到管线 / the child id finds the pipe")
	gpEq(gpCv.gpBinder.gpRedrawEdgesForNodes(["host"]).size(), 0,
		"宿主 id 单独找不到 / the host id alone does not")
	gpCv.queue_free()
