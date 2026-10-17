extends "res://tests/gp_test.gd"
# Frame grab / drag / undo channel (Rev.3 stage 0c) — headless.
# 图框抓取 / 拖拽 / 撤销通道（Rev.3 阶段 0c）—— headless。
#
# The failure modes being guarded against:
# 所防范的失效模式：
# 1. Dragging the frame becomes an edit the user CANNOT TAKE BACK. Every graph edit already travels
#    through a command; the sheet's own fields had no such channel at all before this stage.
#    拖动图框变成用户**无法收回**的编辑。图的每一处编辑都已走命令，而图纸自身的字段在本阶段之前
#    完全没有这条通道。
# 2. One drag records MANY undo steps (one per mouse move), so Ctrl+Z has to be pressed dozens of
#    times to undo a single gesture.
#    一次拖拽记下**许多**撤销步（每次鼠标移动一步），于是撤销一个手势要按几十次 Ctrl+Z。
# 3. The frame escapes the paper while being dragged, or the grab band swallows clicks INSIDE the
#    frame (which would make every symbol unpickable).
#    图框在拖动中跑出纸面；或抓取带吞掉**框内**的点击（那会让图元全都拾取不了）。
# 4. The resize gesture is unreachable because the band test runs first — the whole feature then
#    reads as "dragging only ever moves the frame".
#    因先测抓取带而使改尺寸手势永远够不到 —— 整个功能读作「拖来拖去只能挪框」。
# 5. A sheet-level change does not mark the document dirty, so the user closes the drawing and loses
#    the frame they just positioned.
#    图纸级改动不标脏，用户关掉图纸、丢掉刚摆好的图框。
#
# The geometry itself (trim rect, side midpoints, band/handle hit, pan / drag arithmetic) is pinned in
# gp_test_frame_geometry.gd — one module, one test home. This suite drives the BEHAVIOUR on top.
# 几何本身（裁边线、侧中点、带/手柄命中、平移与改单边算术）钉在 gp_test_frame_geometry.gd ——
# 一个模块一个测试的家。本套件驱动其上的**行为**。


# A fresh A3 sheet + an off-tree canvas bound to it + a grip delegate. Off-tree is deliberate: it is
# the cheaper fixture, and it also proves every port this feature needs is null-safe outside the tree
# (the canvas is routinely used that way by headless checkers — see gp_test_canvas_ports.gd).
# 全新 A3 图纸 + 绑定了它的树外画布 + 抓取委托。刻意树外：夹具更廉价，且顺带证明本功能所需的每个端口
# 在树外都是空安全的（headless 检查器惯常这样使用画布 —— 见 gp_test_canvas_ports.gd）。
func _gpFixture() -> Array:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	# ⚠️ A1 REBASE (2026-10-16): gpNew() now starts on A1. Every coordinate in this file (cursor
	# positions, drag deltas, expected margins) was computed against the A3-era paper, so the
	# fixture pins A3 explicitly — sizes here are INPUTS, the new default's contract lives in
	# gp_test_sheet_frame.gd. / ⚠️ A1 重定基（2026-10-16）：gpNew() 现以 A1 起步。本文件每个坐标
	# （光标位置、拖拽位移、期望边距）都按 A3 时代纸幅算出，故夹具显式钉回 A3 —— 尺寸在此是
	# **输入**，新默认的契约在 gp_test_sheet_frame.gd。
	gpS.gpWidthMM = 420.0
	gpS.gpHeightMM = 297.0
	gpS.gpSetFrameMargins(GPSheet.GP_FRAME_MARGINS_DEFAULT)
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCv.gpSheet = gpS
	# Pin the zoom so the grab tolerance is a known number (GP_GRAB_PX / zoom >= GP_GRAB_PX at 1.0).
	# 钉住缩放，使抓取容差是一个已知数（1.0 时 GP_GRAB_PX / zoom = GP_GRAB_PX）。
	gpCv.gpViewZoom = 1.0
	var gpGrip: GPFrameGripOps = GPFrameGripOps.new(gpCv)
	var gpOut: Array = [gpCv, gpS, gpGrip]
	return gpOut


# The frame rectangle of a sheet, as a convenience. / 便捷取图纸的内框矩形。
func _gpFrame(gpS: GPSheet) -> Rect2:
	return GPFrameGeometry.gpFrameRect(gpS)


# Is the frame wholly inside the paper? The one non-negotiable constraint of this feature.
# 图框是否完全落在纸内？本功能唯一不可协商的约束。
func _gpInsidePaper(gpS: GPSheet) -> bool:
	var gpF: Rect2 = _gpFrame(gpS)
	var gpP: Rect2 = GPFrameGeometry.gpPaperRect(gpS)
	return gpF.position.x >= gpP.position.x - 0.0001 \
		and gpF.position.y >= gpP.position.y - 0.0001 \
		and gpF.end.x <= gpP.end.x + 0.0001 \
		and gpF.end.y <= gpP.end.y + 0.0001 \
		and gpF.size.x >= 0.0 and gpF.size.y >= 0.0


# Margin read as a float, for readable assertions. / 以浮点读取边距，便于书写断言。
func _gpM(gpS: GPSheet, gpSide: int) -> float:
	return float(gpS.gpFrameMargins[gpSide])


# ===========================================================================
# 1. Grab probes / 抓取探测
# ===========================================================================

# The grab tolerance is a SCREEN constant divided by zoom, so the band stays reachable when the user
# zooms out to see the whole sheet — which is exactly when they are most likely to move it.
# 抓取容差是**屏幕**常量除以缩放，故用户缩小到整幅视图时抓取带仍可达 —— 而那恰恰是最可能去挪框的时候。
func gpTestGrabToleranceIsAScreenConstant() -> void:
	gpApprox(GPFrameGripOps.gpGrabTol(1.0), GPFrameGripOps.GP_GRAB_PX, 0.0001,
		"100%% 缩放时容差 = 屏幕常量")
	gpApprox(GPFrameGripOps.gpGrabTol(0.5), GPFrameGripOps.GP_GRAB_PX * 2.0, 0.0001,
		"缩小一半时世界容差加倍，屏幕宽度不变")
	gpApprox(GPFrameGripOps.gpGrabTol(4.0), GPFrameGripOps.GP_GRAB_PX * 0.25, 0.0001,
		"放大四倍时世界容差相应缩小")
	# A degenerate zoom must not produce an infinite band that swallows the whole sheet.
	# 退化缩放不得产出一条吞掉整张纸的无限抓取带。
	gpCheck(GPFrameGripOps.gpGrabTol(0.0) < 1.0e7, "缩放为 0 时容差仍有限（受最小缩放约束）")
	gpCheck(GPFrameGripOps.gpGrabTol(-3.0) < 1.0e7, "负缩放时容差仍有限")


# The frame is grabbable only when a sheet exists AND the frame is switched on: with nothing drawn, a
# grab band would be an invisible target the user cannot see and would not understand.
# 只有图纸存在**且**图框打开时图框才可抓：不画东西时，抓取带会成为一个用户看不见、也理解不了的隐形目标。
func gpTestFrameIsGrabbableOnlyWhenItIsDrawn() -> void:
	var gpF: Array = _gpFixture()
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	gpCheck(gpGrip.gpCanGrab(), "有图纸且图框打开时可抓")
	gpS.gpFrameOn = false
	gpEq(gpGrip.gpCanGrab(), false, "图框关闭时不可抓")
	gpEq(gpGrip.gpTryStart(Vector2(25.0, 148.5)), false, "图框关闭时按下不得开始拖拽")
	gpEq(gpGrip.gpUpdateHoverCursor(Vector2(25.0, 148.5)), false, "图框关闭时不得消费悬停")
	gpS.gpFrameOn = true
	gpEq(gpGrip.gpCanGrab(), true, "重新打开图框后恢复可抓")
	var gpNoSheet: GPCanvas2D = GPCanvas2D.new()
	var gpBare: GPFrameGripOps = GPFrameGripOps.new(gpNoSheet)
	gpEq(gpBare.gpCanGrab(), false, "无图纸时不可抓")
	gpNoSheet.free()
	(gpF[0] as GPCanvas2D).free()


# ⚠️ THE SAFETY PROPERTY, asserted directly: a press anywhere INSIDE the frame must NOT start a drag.
# That is what makes it impossible for this feature to regress symbol / edge / annotation picking —
# it only ever changes what happens where nothing was selectable before.
# ⚠️ **安全性属性**直接断言：框内任意位置按下都**不得**开始拖拽。这正是本功能不可能回归图元 / 边 /
# 注释图形拾取的原因 —— 它只改变「过去什么也选不中」的地方的行为。
func gpTestPressInsideTheFrameNeverGrabs() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpR: Rect2 = _gpFrame(gpS)
	# Every probe is at least 10 mm clear of every frame line, i.e. well outside the 6 px (mm at 100%
	# zoom) band. A point only 3 mm inside the line WOULD be grabbed — that is the band working.
	# 每个探针点都距每条图框线 10mm 以上，即远在 6px（100% 缩放下即 6mm）的带之外。若只在线内 3mm，
	# 反而**会**被抓到 —— 那正是抓取带在正常工作。
	var gpInsides: Array = [
		Vector2(220.0, 148.5),
		gpR.position + Vector2(30.0, 30.0),
		gpR.end - Vector2(30.0, 30.0),
		gpR.position + Vector2(10.0, 10.0),
	]
	for gpP in gpInsides:
		gpEq(gpGrip.gpTryStart(gpP as Vector2), false, "框内 %s 按下不得抓图框" % str(gpP))
		gpEq(gpGrip.gpIsDragging(), false, "框内 %s 按下后不得处于拖拽态" % str(gpP))
	gpEq(gpGrip.gpTryStart(Vector2(5000.0, 5000.0)), false, "远离图纸的按下不得抓图框")
	# The band does extend a little INSIDE the line — that is the affordance, and it is bounded.
	# 抓取带确实向线**内**延伸一点点 —— 那正是可及性所在，且它有界。
	gpEq(gpGrip.gpTryStart(gpR.position + Vector2(3.0, 3.0)), true,
		"线内 3mm 属抓取带，应可抓（界线以内）")
	gpGrip.gpCancelDrag()
	# And the four LINES do grab, at a point away from the handles. / 而四条线本身可抓（取远离手柄处）。
	gpEq(gpGrip.gpTryStart(Vector2(gpR.position.x, gpR.position.y + 40.0)), true,
		"左边线上按下应开始拖拽")
	gpGrip.gpCancelDrag()
	gpEq(gpGrip.gpTryStart(Vector2(gpR.position.x + 40.0, gpR.position.y)), true,
		"上边线上按下应开始拖拽")
	gpGrip.gpCancelDrag()
	gpEq(gpGrip.gpTryStart(Vector2(gpR.end.x, gpR.end.y - 40.0)), true, "右边线上按下应开始拖拽")
	gpGrip.gpCancelDrag()
	gpEq(gpGrip.gpTryStart(Vector2(gpR.end.x - 40.0, gpR.end.y)), true, "下边线上按下应开始拖拽")
	gpGrip.gpCancelDrag()
	gpCv.free()


# ===========================================================================
# 2. Translate against the margins (⌥Alt + grab the line) / 相对边距平移（⌥Alt + 抓线本身）
# ===========================================================================
#
# ⚠️ THIS SECTION CHANGED CARRIER ON 2026-10-16 (Rev.3 stage 0d), NOT BEHAVIOUR / ⚠️ 本节于 2026-10-16
# （Rev.3 阶段 0d）换的是**载体**，不是行为：the plain band drag now moves the WHOLE SHEET (see section 2b),
# so the gesture these two tests pin — trade all four margins against each other, size unchanged, content
# and paper staying put — survives behind ⌥Alt. The tests below therefore pass gpAlt = true; the property
# asserted in each of them is the one it always asserted.
# 不带修饰键的拖带如今搬动**整张图纸**（见第 2b 节），故这两个测试所钉的手势 —— 四条边距互相对冲、尺寸不变、
# 内容与纸面不动 —— 移到 ⌥Alt 之后继续存在。故下方测试传入 gpAlt = true；每个测试所断言的性质与它一直以来
# 断言的仍是同一个。

# Dragging the LINE with ⌥Alt translates the frame against its margins: all four move against each other,
# so the SIZE is exactly preserved and only the position changes.
# 按住 ⌥Alt 拖动**线本身**即平移图框相对其边距：四条边距互相对冲，故尺寸精确不变、只有位置改变。
func gpTestAltBandDragTranslatesAndKeepsTheSize() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpBefore: Rect2 = _gpFrame(gpS)
	gpCheck(gpGrip.gpTryStart(Vector2(25.0, 100.0), true), "左图框线带上（远离手柄）⌥Alt 按下应开始拖拽")
	gpEq(gpGrip.gpIsDragging(), true, "按下后应处于拖拽态")
	gpGrip.gpOnGripMove(Vector2(45.0, 100.0))
	# ⚠️ THE +20mm DELTA IS NOW APPLIED IN FULL (2026-10-16): the left margin lands on 45 and the right one
	# absorbs the mirror move all the way to −15, which is how "this frame line is off the sheet" is
	# written down. Before the amendment the same drag stopped at +4 (the 5 mm right margin hit its floor),
	# which is exactly why the frame felt stuck. The SIZE is still preserved exactly.
	# ⚠️ +20mm 现在被**完整**施加（2026-10-16）：左边距落到 45，右边距承载镜像位移一路到 −15 —— 这正是
	# 「该条图框线在纸外」的写法。修正之前同一次拖拽在 +4 处停住（5mm 的右边距撞上下限），那正是图框
	# 「挪不动」的原因。尺寸仍精确不变。
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_LEFT), 45.0, 0.0001, "左边距 25 → 45（位移原样施加）")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_RIGHT), -15.0, 0.0001, "右边距 5 → −15（对冲，负值合法）")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_TOP), 5.0, 0.0001, "上边距不受 x 位移影响")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_BOTTOM), 5.0, 0.0001, "下边距不受 x 位移影响")
	gpApprox(_gpFrame(gpS).size.x, gpBefore.size.x, 0.0001, "平移不得改变图框宽")
	gpApprox(_gpFrame(gpS).size.y, gpBefore.size.y, 0.0001, "平移不得改变图框高")
	gpCheck(not _gpInsidePaper(gpS),
		"右边距为 −15 时图框右边界已在纸外 —— 按设计如此，不再是缺陷")
	gpGrip.gpEndGripDrag()
	gpEq(gpGrip.gpIsDragging(), false, "释放后拖拽状态应清除")
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 1, "一次平移 = 一个撤销步")
	gpCv.free()


# A vertical drag with ⌥Alt on a horizontal line moves only the top/bottom pair.
# 按住 ⌥Alt 在水平线上竖直拖动只移动上/下这一对边距。
func gpTestAltBandDragVerticallyKeepsTheHorizontalSize() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	gpCheck(gpGrip.gpTryStart(Vector2(200.0, 5.0), true), "上边线上 ⌥Alt 按下应开始拖拽")
	gpGrip.gpOnGripMove(Vector2(200.0, 25.0))
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_TOP), 25.0, 0.0001, "上边距 5 → 25（位移原样施加）")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_BOTTOM), -15.0, 0.0001, "下边距 5 → −15（对冲，负值合法）")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_LEFT), 25.0, 0.0001, "左边距不受 y 位移影响")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_RIGHT), 5.0, 0.0001, "右边距不受 y 位移影响")
	gpGrip.gpEndGripDrag()
	gpCv.free()


# ===========================================================================
# 2b. Move the WHOLE SHEET (plain grab of the line) / 搬动整张图纸（不带修饰键抓线）
# ===========================================================================

# A fixture that carries CONTENT: a graph with one node and one annotation, bound to the off-tree canvas,
# so the sheet-move drag has something to carry AND a command context to record into.
# 一份**带内容**的夹具：一个图元与一枚注释图形组成的图，绑定到树外画布，使整图拖拽既有东西可搬、也有命令
# 上下文可记录。
#
# The binding matters: GPTranslateSheetCommand reads the graph off the command context, and the context is
# rebuilt by GPCanvas2D._gpSetGraph when the canvas's graph is assigned — so `gpCv.gpGraph = g` is what
# makes gpCv.gpRequestTranslateSheet() work at all.
# 这次绑定是必要的：GPTranslateSheetCommand 自命令上下文取图，而上下文由 GPCanvas2D._gpSetGraph 在画布图
# 被赋值时重建 —— 故正是 `gpCv.gpGraph = g` 使 gpCv.gpRequestTranslateSheet() 能够工作。
func _gpContentFixture() -> Array:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("N1", "pump", "P-101", Vector2(120.0, 120.0)))
	gpG.gpAddShape(GPShape.gpLine(Vector2(200.0, 40.0), Vector2(260.0, 60.0)))
	gpCv.gpGraph = gpG
	var gpOut: Array = [gpCv, gpS, gpGrip, gpG]
	return gpOut


# ★ THE REQUESTED BEHAVIOUR: dragging the frame line moves the paper AND the drawing with it, and NOT ONE
# MARGIN CHANGES — that is the whole difference between this gesture and the ⌥Alt one.
# ★ 用户所要求的行为：拖图框线把纸面**与图**一起搬走，而**一条边距都不变** —— 这正是本手势与 ⌥Alt
# 手势之间的全部差别。
func gpTestBandDragMovesTheWholeSheetAndNoMargin() -> void:
	var gpF: Array = _gpContentFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpG: GPPIDGraph = gpF[3]
	var gpMarginsBefore: Array = gpS.gpFrameMargins.duplicate()
	gpCheck(gpGrip.gpTryStart(Vector2(25.0, 100.0)), "左图框线上（远离手柄）按下应开始拖拽")
	gpGrip.gpOnGripMove(Vector2(45.0, 100.0))
	# The paper travelled... / 纸面走了……
	gpEq(gpS.gpPaperOrigin, Vector2(20.0, 0.0), "纸面原点应恰为位移（精确）")
	# ...the content travelled with it... / ……内容随之同行……
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(140.0, 120.0), "图元应随纸平移（精确）")
	gpEq(gpG.gpShapes[0].gpPoints, PackedVector2Array([Vector2(220.0, 40.0), Vector2(280.0, 60.0)]),
		"注释图形应随纸平移")
	# ...and the frame line is exactly where the cursor put it, by way of the unchanged margins.
	# ……而图框线恰好落在光标处，其路径正是一条都没变的边距。
	gpEq(_gpFrame(gpS).position, Vector2(45.0, 5.0), "图框左上角 = 未变的左边距/上边距 + 新纸面原点")
	for gpI in 4:
		gpEq(gpS.gpFrameMargins[gpI], gpMarginsBefore[gpI], "第 %d 条边距必须逐位不变" % gpI)
	gpEq(gpS.gpFrameMarginsAreDefault(), true, "整图平移不得改动边距")
	# The frame still sits INSIDE the paper, at its original distance from every edge — which is what
	# "the paper follows the frame" means visually.
	# 图框仍留在纸**内**、且与每条纸边的距离都是原值 —— 那正是「纸随图框走」的视觉含义。
	gpCheck(_gpInsidePaper(gpS), "整图平移后图框仍与纸面保持原有相对位置")
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "拖拽过程中不得产生撤销步")
	gpGrip.gpEndGripDrag()
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 1, "一次整图拖拽 = 一个撤销步")
	gpEq(gpS.gpPaperOrigin, Vector2(20.0, 0.0), "提交后纸面仍在位移处")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(140.0, 120.0), "提交后内容仍在位移处")
	# One Ctrl+Z puts BOTH halves back — the property that makes it a single edit.
	# 一次 Ctrl+Z 把**两半**同时放回去 —— 这正是它是一次编辑的性质。
	gpCv.gpUndo()
	gpEq(gpS.gpPaperOrigin, Vector2.ZERO, "撤销应把纸面放回原点")
	gpEq(gpS.gpPaperOriginIsDefault(), true, "撤销后「从未移动过」应重新成立")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(120.0, 120.0), "撤销应把内容一并放回")
	gpEq(gpG.gpShapes[0].gpPoints, PackedVector2Array([Vector2(200.0, 40.0), Vector2(260.0, 60.0)]),
		"撤销应把注释图形一并放回")
	gpCv.free()


# ⚠️ THE PREVIEW REPLAYS FROM THE BASELINE, so returning the cursor to where the drag began returns the
# sheet EXACTLY to where it began — the property a per-motion accumulate would destroy.
# ⚠️ 预览自**基线**重放，故把光标移回拖拽起点会把图纸**精确**送回起点 —— 逐次累加会毁掉这个性质。
func gpTestSheetMovePreviewReplaysFromTheBaseline() -> void:
	var gpF: Array = _gpContentFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpG: GPPIDGraph = gpF[3]
	var gpStart: Vector2 = Vector2(25.0, 100.0)
	gpCheck(gpGrip.gpTryStart(gpStart), "带上按下应开始拖拽")
	for gpI in 30:
		gpGrip.gpOnGripMove(gpStart + Vector2(float(gpI) * 4.0, float(gpI) * 2.0))
		gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "第 %d 次移动仍不得产生撤销步" % gpI)
	gpEq(gpS.gpPaperOrigin, Vector2(116.0, 58.0), "30 次移动后纸面 = 起始 + 最后一次的**总**位移")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(236.0, 178.0), "内容同样按总位移重放")
	# Back to the grab point: a replayed preview lands EXACTLY on the baseline, not merely near it.
	# 移回抓取点：重放式预览**精确**落回基线，而不仅是接近。
	gpGrip.gpOnGripMove(gpStart)
	gpEq(gpS.gpPaperOriginIsDefault(), true, "移回起点后纸面应精确回到原点（累加式实现会留下残差）")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(120.0, 120.0), "移回起点后内容也应精确回到原值")
	gpGrip.gpEndGripDrag()
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "回到起点后释放：净位移为零，不得记撤销步")
	gpEq(gpS.gpPaperOriginIsDefault(), true, "净位移为零时图纸不得被扰动")
	gpCv.free()


# ESC abandons a sheet move: BOTH halves go back, and no undo step is recorded.
# ESC 放弃整图拖拽：**两半**都回去，且不产生撤销步。
#
# ⚠️ RESTORING ONLY THE PAPER WOULD BE A REAL BUG, and it is the one this test exists for: the drawing
# would be left translated by a drag the user cancelled — the failure that reads as "ESC moved my sheet".
# ⚠️ 只还原纸面是一个**真实**缺陷，也正是本测试存在的理由：图会被一次被用户取消的拖拽平移掉 —— 那种失效
# 读起来就像「ESC 把我的图纸挪了」。
func gpTestCancelSheetMoveRestoresPaperAndContent() -> void:
	var gpF: Array = _gpContentFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpG: GPPIDGraph = gpF[3]
	gpCheck(gpGrip.gpTryStart(Vector2(25.0, 100.0)), "带上按下应开始拖拽")
	gpGrip.gpOnGripMove(Vector2(65.0, 130.0))
	gpEq(gpS.gpPaperOriginIsDefault(), false, "预览应已移动纸面")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(160.0, 150.0), "预览应已移动内容")
	gpGrip.gpCancelDrag()
	gpEq(gpGrip.gpIsDragging(), false, "放弃后拖拽状态应清除")
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "放弃不得产生撤销步")
	gpEq(gpS.gpPaperOriginIsDefault(), true, "放弃后纸面应回到原点")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(120.0, 120.0), "放弃后内容也必须一并回到原值")
	gpEq(gpG.gpShapes[0].gpPoints, PackedVector2Array([Vector2(200.0, 40.0), Vector2(260.0, 60.0)]),
		"放弃后注释图形也必须一并回到原值")
	gpEq(gpS.gpFrameMarginsAreDefault(), true, "放弃后边距应仍是默认")
	gpCv.free()


# The ⌥Alt escape hatch: a band drag with Alt still trades the margins, leaving paper and content put.
# ⌥Alt 逃生口：按住 Alt 的拖带仍对冲边距，纸面与内容原地不动。
#
# WHY THIS IS PINNED AT ALL / 为何要钉住它：with the plain gesture redefined, this is the ONLY way left to
# shift the frame relative to the paper from the UI — neither gesture may silently swallow the other.
# 在不带修饰键的手势被重定义之后，这是 UI 上**唯一**还能把图框相对纸面挪动的途径 —— 两者都不得悄悄吞掉对方。
func gpTestAltBandDragKeepsPaperAndContentPut() -> void:
	var gpF: Array = _gpContentFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpG: GPPIDGraph = gpF[3]
	gpCheck(gpGrip.gpTryStart(Vector2(25.0, 100.0), true), "带上 ⌥Alt 按下应开始拖拽")
	gpGrip.gpOnGripMove(Vector2(45.0, 100.0))
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_LEFT), 45.0, 0.0001, "⌥Alt 路径应改左边距")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_RIGHT), -15.0, 0.0001, "⌥Alt 路径应镜像改右边距")
	gpEq(gpS.gpPaperOriginIsDefault(), true, "⌥Alt 路径不得移动纸面")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(120.0, 120.0), "⌥Alt 路径不得移动内容")
	gpGrip.gpEndGripDrag()
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 1, "⌥Alt 路径同样是一个撤销步")
	gpEq(gpS.gpPaperOriginIsDefault(), true, "提交后纸面仍在原点")
	gpCv.gpUndo()
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_LEFT), 25.0, 0.0001, "撤销应回到原来的左边距")
	gpCv.free()


# A plain click on the frame line (press + release, no motion) moves nothing and records nothing.
# 在图框线上单纯点一下（按下即释放、没有移动）什么都不搬，也不记任何撤销步。
func gpTestClickOnTheBandMovesNothing() -> void:
	var gpF: Array = _gpContentFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpG: GPPIDGraph = gpF[3]
	gpCheck(gpGrip.gpTryStart(Vector2(25.0, 100.0)), "带上按下应开始拖拽")
	gpGrip.gpEndGripDrag()
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "没有移动就不应有撤销步")
	gpEq(gpS.gpPaperOriginIsDefault(), true, "没有移动就不该移动纸面")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(120.0, 120.0), "没有移动就不该移动内容")
	gpEq(gpS.gpFrameMarginsAreDefault(), true, "没有移动就不该改动边距")
	gpCv.free()


# ===========================================================================
# 3. Resize (grab a side handle) / 改尺寸（抓侧手柄）
# ===========================================================================

# ⚠️ THE HANDLE MUST WIN OVER THE BAND. The handle sits ON the line, i.e. inside the band, so if the
# band were tested first the resize gesture would be unreachable — the feature would read as
# "dragging only ever moves the frame". A pan would have mirrored the move onto the RIGHT margin.
# ⚠️ **手柄必须胜过抓取带**。手柄就在线上、即在带内，若先测带则改尺寸将永远够不到 —— 整个功能读作
# 「拖来拖去只能挪框」。若走了平移，位移会镜像到**右**边距上。
func gpTestHandlePressResizesInsteadOfTranslating() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpMid: Vector2 = GPFrameGeometry.gpSideMidpoints(gpS)[GPSheet.GP_MARGIN_LEFT]
	gpCheck(gpGrip.gpTryStart(gpMid), "侧中点手柄上按下应开始拖拽")
	# Move on BOTH axes: only the side's own axis may be read, so the y value must be ignored.
	# 两条轴都给位移：只允许读该边自身的轴，故 y 必须被忽略。
	gpGrip.gpOnGripMove(Vector2(40.0, 260.0))
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_LEFT), 40.0, 0.0001, "左边距应落到光标 x = 40")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_RIGHT), 5.0, 0.0001,
		"右边距必须不动 —— 若它变成 1，说明走的是平移而非改尺寸")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_TOP), 5.0, 0.0001, "上边距不动")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_BOTTOM), 5.0, 0.0001, "下边距不动")
	gpGrip.gpEndGripDrag()
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 1, "一次改尺寸 = 一个撤销步")
	gpCv.free()


# Each of the four handles resizes exactly its own side, and the vertical ones read the y axis.
# 四个手柄各自改自己那条边，而竖向上的手柄读 y 轴。
#
# ⚠️ THE RIGHT / BOTTOM EXPECTATIONS CHANGED ON 2026-10-16 (Rev.3 stage 0d) / ⚠️ 右 / 下两条期望值已于
# 2026-10-16（Rev.3 阶段 0d）更改：the margin is the DISTANCE FROM THAT SIDE'S PAPER EDGE, so with the
# cursor at x = 380 on a 420 mm sheet the right margin is 40 (= 420 − 380), and with y = 270 on a
# 297 mm sheet the bottom margin is 27 (= 297 − 270). Both expected values are DERIVED here rather
# than transcribed from the implementation — and the two sides whose numbers did NOT change (LEFT/TOP)
# are exactly the two where the margin and the line's own coordinate coincide, which is how the
# earlier mirror stayed invisible. See GPFrameGeometry.gpDragSideMargins for the full account.
# 边距是到**该边纸缘**的距离，故 420mm 的纸上光标 x=380 时右边距为 40（= 420 − 380），297mm 的纸上
# y=270 时下边距为 27（= 297 − 270）。两条期望值在此**推导**得出、而非自实现抄录 —— 而数值**未变**的
# 那两条边（左 / 上）恰是边距与线自身坐标重合的两条，也正是先前的镜像得以不被察觉的原因。
# 完整说明见 GPFrameGeometry.gpDragSideMargins。
func gpTestEveryHandleResizesItsOwnSide() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpSheetW: float = gpS.gpWidthMM
	var gpSheetH: float = gpS.gpHeightMM
	var gpCases: Array = [
		# [side, cursor x, cursor y, the value the dragged margin must land on]
		# [边, 光标 x, 光标 y, 被拖边距必须落到的值]
		[GPSheet.GP_MARGIN_LEFT, 40.0, 260.0, 40.0],
		[GPSheet.GP_MARGIN_TOP, 200.0, 20.0, 20.0],
		[GPSheet.GP_MARGIN_RIGHT, 380.0, 12.0, gpSheetW - 380.0],
		[GPSheet.GP_MARGIN_BOTTOM, 200.0, 270.0, gpSheetH - 270.0],
	]
	for gpC in gpCases:
		var gpSide: int = int(gpC[0])
		var gpMid: Vector2 = GPFrameGeometry.gpSideMidpoints(gpS)[gpSide]
		gpCheck(gpGrip.gpTryStart(gpMid), "第 %d 条边的手柄应可按下" % gpSide)
		gpGrip.gpOnGripMove(Vector2(float(gpC[1]), float(gpC[2])))
		gpApprox(_gpM(gpS, gpSide), float(gpC[3]), 0.0001,
			"第 %d 条边应落到光标在该轴上的坐标" % gpSide)
		for gpOther in 4:
			if gpOther == gpSide:
				continue
			gpApprox(_gpM(gpS, gpOther), float(GPSheet.GP_FRAME_MARGINS_DEFAULT[gpOther]), 0.0001,
				"拖第 %d 条边时第 %d 条边必须不动" % [gpSide, gpOther])
		gpGrip.gpEndGripDrag()
		gpCheck(not gpS.gpFrameMarginsAreDefault(), "拖过之后边距应已非默认")
		# Back to the start for the next case (a direct write, so no extra undo step is recorded).
		# 复位到起始值供下一个用例（直接写入，故不产生额外撤销步）。
		gpS.gpSetFrameMargins(GPSheet.GP_FRAME_MARGINS_DEFAULT)
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 4, "四次改尺寸 = 四个撤销步")
	gpCv.free()


# ===========================================================================
# 4. Commit / cancel semantics / 提交与放弃语义
# ===========================================================================
#
# ⚠️ THE TWO TESTS BELOW DRIVE THE ⌥Alt (MARGIN) PATH SINCE STAGE 0d. They were written when the plain band
# drag traded the margins; that gesture now lives behind ⌥Alt, so they pass gpAlt = true. The commit/cancel
# semantics of the PLAIN band drag — which moves the whole sheet — are pinned in section 2b, because their
# subject is the sheet rather than the margins.
# ⚠️ 下方两个测试自阶段 0d 起驱动的是 ⌥Alt（边距）那条路。它们写就于「不带修饰键的拖带对冲边距」的年代；
# 该手势如今住在 ⌥Alt 之后，故它们传入 gpAlt = true。不带修饰键的拖带（搬动整张图纸）的提交 / 放弃语义
# 钉在第 2b 节 —— 因为它们的对象是图纸、不是边距。

# ⚠️ ONE GESTURE = ONE UNDO STEP. The live preview writes the sheet on every motion; without rewinding
# to the captured start and committing once, a 30-motion drag would leave 30 undo steps behind.
# ⚠️ **一个手势 = 一个撤销步**。实时预览每次移动都写图纸；若不先回退到捕获的起始值、再一次性提交，
# 一次 30 步的拖拽会留下 30 个撤销步。
func gpTestManyMotionsCommitOneUndoStep() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "起始时撤销栈为空")
	gpCheck(gpGrip.gpTryStart(Vector2(25.0, 100.0), true), "带上 ⌥Alt 按下应开始拖拽")
	for gpI in 30:
		gpGrip.gpOnGripMove(Vector2(25.0 + float(gpI) * 5.0, 100.0))
		gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0,
			"拖拽过程中（第 %d 次移动）不得产生撤销步" % gpI)
	gpGrip.gpEndGripDrag()
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 1, "30 次移动的一次拖拽只应产生 1 个撤销步")
	# The committed value is the LAST preview, not the first. The 30th motion sits at x=170, i.e. a +145 mm
	# delta from the grab point — applied in full since 2026-10-16, so the left margin lands on 170.
	# 提交的是**最后**一次预览值，而非首次。第 30 次移动位于 x=170，即自抓取点起 +145mm 的位移 —— 自
	# 2026-10-16 起原样施加，故左边距落到 170。
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_LEFT), 170.0, 0.0001,
		"提交的应是最后一次预览的左边距（25 + 145）")
	gpCv.gpUndo()
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_LEFT), 25.0, 0.0001, "撤销应回到拖拽前的 25")
	gpCv.gpRedo()
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_LEFT), 170.0, 0.0001, "重做应回到提交后的 170")
	gpCv.free()


# A plain click (press + release with no motion) must not perturb the sheet NOR record an undo step.
# 单纯点击（按下即释放、没有移动）不得扰动图纸，也不得产生撤销步。
func gpTestClickWithoutMotionIsNotAnUndoStep() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	gpCheck(gpGrip.gpTryStart(Vector2(25.0, 100.0)), "带上按下应开始拖拽")
	gpGrip.gpEndGripDrag()
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "没有移动就不应有撤销步")
	gpCheck(gpS.gpFrameMarginsAreDefault(), "没有移动就不应改动图纸")
	gpCv.free()


# ESC abandons the drag: the sheet returns to the captured start and NO undo step is recorded.
# ESC 放弃拖拽：图纸回到捕获的起始值，且**不**产生撤销步。
func gpTestCancelDragRestoresAndCommitsNothing() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	gpCheck(gpGrip.gpTryStart(Vector2(25.0, 100.0), true), "带上 ⌥Alt 按下应开始拖拽")
	gpGrip.gpOnGripMove(Vector2(40.0, 100.0))
	gpCheck(not gpS.gpFrameMarginsAreDefault(), "拖拽预览应已写入边距")
	gpGrip.gpCancelDrag()
	gpEq(gpGrip.gpIsDragging(), false, "放弃后拖拽状态应清除")
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "放弃不得产生撤销步")
	for gpI in 4:
		gpApprox(_gpM(gpS, gpI), float(GPSheet.GP_FRAME_MARGINS_DEFAULT[gpI]), 0.0001,
			"放弃后第 %d 项边距应回到起始值" % gpI)
	gpCv.free()


# ===========================================================================
# 5. The frame may be dragged clean off the paper / 图框可被彻底拖离纸面
# ===========================================================================

# ⚠️ THIS SECTION REVERSED ITSELF ON 2026-10-16. Until then it was "the frame never leaves the paper —
# the one non-negotiable constraint", sweeping both gestures with absurd inputs while asserting
# containment. The user asked for free movement (「自由移动，没有限制」), so containment is gone and the
# non-negotiable constraint is now the frame's OWN consistency — which is what this sweep asserts
# instead: after any gesture with any input, the frame is still a rectangle that can be drawn and grabbed.
# ⚠️ 本节于 2026-10-16 自我反转。在此之前它是「图框永不离开纸面 —— 唯一不可协商的约束」，用两种手势与荒唐
# 取值遍历断言「包含在纸内」。用户要求自由移动（「自由移动，没有限制」），故包含性已删除，而不可协商的约束
# 变成了图框**自身**的自洽 —— 本节改为断言这一点：任何手势、任何取值之后，图框仍是一个可绘制、可抓取的矩形。
#
# ⚠️ STAGE 0d NARROWED WHICH GESTURE CAN DO IT / ⚠️ 阶段 0d 缩小了「哪种手势能做到」：part (a) below now
# runs with ⌥Alt, because with the plain band drag the paper travels WITH the frame and the frame therefore
# cannot leave it. See the note inside part (a).
# 下方 (甲) 部分如今按 ⌥Alt 运行 —— 因为在不带修饰键的拖带下，纸面与图框同行，图框因此不可能离开纸面。
# 详见 (甲) 内部的说明。
func gpTestFrameCanBeDraggedRightOffThePaper() -> void:
	var gpMarginSets: Array = [[25.0, 5.0, 5.0, 5.0], [4.0, 4.0, 4.0, 4.0], [1.0, 1.0, 1.0, 1.0]]
	for gpM in gpMarginSets:
		var gpF: Array = _gpFixture()
		var gpCv: GPCanvas2D = gpF[0]
		var gpS: GPSheet = gpF[1]
		var gpGrip: GPFrameGripOps = gpF[2]
		gpS.gpSetFrameMargins(gpM)
		var gpR: Rect2 = _gpFrame(gpS)
		gpCheck(_gpInsidePaper(gpS), "边距 %s：起始状态图框应在纸内" % [str(gpM)])
		# (a) Translate far in all four directions: the frame ends up OFF the sheet, at its old size —
		# which is exactly what "free movement" means.
		# （甲）向四个方向平移到极远：图框最终落在纸**外**，且尺寸与出发时一模一样 —— 这正是「自由移动」的
		# 含义。
		#
		# ⚠️ ⌥Alt IS REQUIRED HERE SINCE STAGE 0d / ⚠️ 自阶段 0d 起此处**必须**按住 ⌥Alt：the plain band
		# drag now carries the paper WITH the frame, so the frame could never leave it — the property under
		# test ("this frame line may be off the sheet") belongs to the gesture that moves the frame AGAINST
		# its margins, which is the Alt one. Reading the plain gesture here would assert the negation of what
		# the user asked for.
		# 不带修饰键的拖带如今把纸面**连同**图框一起搬，故图框永远不可能离开纸面 —— 而本测试所断言的性质
		#（「该条图框线可以在纸外」）属于那个让图框**相对边距**移动的手势，也就是 ⌥Alt 那个。此处若读不带
		# 修饰键的手势，断言的将是用户所要求之事的反面。
		var gpBandPt: Vector2 = Vector2(gpR.position.x, (gpR.position.y + gpR.end.y) * 0.5 - 30.0)
		gpCheck(gpGrip.gpTryStart(gpBandPt, true), "边距 %s：带上 ⌥Alt 按下应开始拖拽" % [str(gpM)])
		for gpD in [Vector2(10000.0, 0.0), Vector2(-10000.0, 0.0), Vector2(0.0, 10000.0),
				Vector2(0.0, -10000.0)]:
			gpGrip.gpOnGripMove(gpBandPt + (gpD as Vector2))
			var gpNow: Rect2 = _gpFrame(gpS)
			gpApprox(gpNow.size.x, gpR.size.x, 0.0001,
				"边距 %s / 平移 %s：平移不得改尺寸（宽）" % [str(gpM), str(gpD)])
			gpApprox(gpNow.size.y, gpR.size.y, 0.0001,
				"边距 %s / 平移 %s：平移不得改尺寸（高）" % [str(gpM), str(gpD)])
			gpCheck(not _gpInsidePaper(gpS),
				"边距 %s / 平移 %s：10000mm 的平移应把图框带出纸面（这正是自由移动）" % [str(gpM), str(gpD)])
		gpGrip.gpCancelDrag()
		gpCheck(GPFrameGeometry.gpSameMargins(gpS.gpFrameMargins, gpM),
			"边距 %s：放弃拖拽后应回到起始边距" % [str(gpM)])
		# (b) Drag each side handle far past both ends: OUTWARD is unbounded (the frame goes off the
		# sheet), INWARD stops one minimum inner size short of the opposite side.
		# （乙）把四条边的手柄各自拖到两端之外：向**外**无界（图框离开纸面），向**内**在对边之前一个最小内框
		# 尺寸处停下。
		var gpMids: Array = GPFrameGeometry.gpSideMidpoints(gpS)
		for gpI in gpMids.size():
			for gpVal in [-10000.0, 10000.0]:
				var gpA: Vector2 = gpMids[gpI] as Vector2
				var gpTarget: Vector2 = gpA
				match gpI:
					GPSheet.GP_MARGIN_LEFT:
						gpTarget = Vector2(gpVal, gpA.y)
					GPSheet.GP_MARGIN_TOP:
						gpTarget = Vector2(gpA.x, gpVal)
					GPSheet.GP_MARGIN_RIGHT:
						gpTarget = Vector2(gpVal, gpA.y)
					_:
						gpTarget = Vector2(gpA.x, gpVal)
				gpCheck(gpGrip.gpTryStart(gpA), "边距 %s：第 %d 条边手柄应可按下" % [str(gpM), gpI])
				gpGrip.gpOnGripMove(gpTarget)
				var gpResized: Rect2 = _gpFrame(gpS)
				gpCheck(gpResized.size.x >= GPSheet.GP_FRAME_MIN_SIZE_MM - 0.0001
						and gpResized.size.y >= GPSheet.GP_FRAME_MIN_SIZE_MM - 0.0001,
					"边距 %s / 边 %d 拖到 %.0f：内框不得塌缩（实测 %.4f × %.4f）"
						% [str(gpM), gpI, gpVal, gpResized.size.x, gpResized.size.y])
				gpGrip.gpCancelDrag()
				gpCheck(GPFrameGeometry.gpSameMargins(gpS.gpFrameMargins, gpM),
					"边距 %s / 边 %d：放弃后应回到起始边距" % [str(gpM), gpI])
		gpCv.free()


# ===========================================================================
# 6. Hover / cursor semantics / 悬停与光标语义
# ===========================================================================

# The cursor carries the SEMANTICS, not just "something is here": a handle reads as a resize and the
# plain band reads as a move. One shared MOVE cursor would leave two very different gestures looking
# identical.
# 光标承载**语义**而非仅「这里有东西」：手柄读作改尺寸、纯抓取带读作移动。共用一个 MOVE 光标会让两种
# 截然不同的手势看起来一模一样。
func gpTestHoverCursorCarriesTheGestureSemantics() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPFrameGripOps = gpF[2]
	var gpLeftMid: Vector2 = GPFrameGeometry.gpSideMidpoints(gpS)[GPSheet.GP_MARGIN_LEFT]
	gpEq(gpGrip.gpUpdateHoverCursor(gpLeftMid), true, "悬停在左/右手柄上应消费移动事件")
	gpEq(gpGrip.gpHoverSide(), GPSheet.GP_MARGIN_LEFT, "悬停边应为左边")
	gpEq(gpCv.mouse_default_cursor_shape, Control.CURSOR_HSIZE, "左/右边手柄应读作水平改尺寸")
	var gpTopMid: Vector2 = GPFrameGeometry.gpSideMidpoints(gpS)[GPSheet.GP_MARGIN_TOP]
	gpEq(gpGrip.gpUpdateHoverCursor(gpTopMid), true, "悬停在上/下手柄上应消费移动事件")
	gpEq(gpCv.mouse_default_cursor_shape, Control.CURSOR_VSIZE, "上/下边手柄应读作垂直改尺寸")
	gpEq(gpGrip.gpUpdateHoverCursor(Vector2(25.0, 100.0)), true, "悬停在抓取带上应消费移动事件")
	gpEq(gpGrip.gpHoverSide(), GPSheet.GP_MARGIN_LEFT, "带上悬停边仍为左边")
	gpEq(gpCv.mouse_default_cursor_shape, Control.CURSOR_MOVE, "纯抓取带应读作移动")
	gpEq(gpGrip.gpUpdateHoverCursor(Vector2(220.0, 148.5)), false, "框内悬停不得消费移动事件")
	gpEq(gpGrip.gpHoverSide(), GPFrameGeometry.GP_SIDE_NONE, "离开可抓区后悬停边应清空")
	# A drag in flight owns the gesture: hover must not fight it for the cursor.
	# 拖拽进行中时手势已定：悬停不得与它争夺光标。
	gpCheck(gpGrip.gpTryStart(Vector2(25.0, 100.0)), "带上按下应开始拖拽")
	gpEq(gpGrip.gpUpdateHoverCursor(Vector2(25.0, 148.5)), false, "拖拽中悬停不得消费移动事件")
	gpEq(gpGrip.gpHoverSide(), GPFrameGeometry.GP_SIDE_NONE, "拖拽中悬停边应为空")
	gpGrip.gpCancelDrag()
	gpCv.free()


# ===========================================================================
# 7. The undo channel for SHEET-level fields / 图纸级字段的撤销通道
# ===========================================================================

# A fixture: a sheet plus an edit service. No graph is bound — the sheet command captures the sheet
# itself rather than reading it off GPCommandContext (see mutate_sheet_command.gd).
# 夹具：图纸 + 编辑服务。刻意不绑图 —— 图纸命令捕获图纸本身，而不是从 GPCommandContext 取它
# （见 mutate_sheet_command.gd）。
func _gpSvc() -> Array:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	var gpSvc: GPEditService = GPEditService.new()
	var gpOut: Array = [gpS, gpSvc]
	return gpOut


# Margins are written as ONE undo step, and the undo/redo pair must not re-capture its own old value.
# 边距作为**一个**撤销步写入；且撤销 / 重做这一对不得重新捕获自己的旧值。
#
# ⚠️ THE SECOND UNDO IS THE POINT: the default gpRedo() re-runs gpExecute(), which would capture the
# NEW values as "old" — so the second Ctrl+Z would restore the state the user just undid.
# ⚠️ **第二次撤销才是关键**：默认的 gpRedo() 会重跑 gpExecute()，从而把**新**值捕获为「旧值」——
# 于是第二次 Ctrl+Z 会恢复用户刚撤销掉的那个状态。
func gpTestSheetMarginsAreOneUndoStepAndUndoIsRepeatable() -> void:
	var gpF: Array = _gpSvc()
	var gpS: GPSheet = gpF[0]
	var gpSvc: GPEditService = gpF[1]
	gpEq(gpSvc.gpStack.gpUndoDepth(), 0, "起始撤销栈为空")
	gpCheck(gpSvc.gpSetFrameMargins(gpS, [30.0, 8.0, 8.0, 8.0]), "写入边距应成功")
	gpApprox(_gpM(gpS, 0), 30.0, 0.0001, "写入后第 0 项应为 30")
	gpEq(gpSvc.gpStack.gpUndoDepth(), 1, "一次写入 = 一个撤销步")
	gpCheck(gpSvc.gpUndo(), "撤销应成功")
	gpApprox(_gpM(gpS, 0), 25.0, 0.0001, "撤销应回到写入前的 25")
	gpCheck(gpSvc.gpRedo(), "重做应成功")
	gpApprox(_gpM(gpS, 0), 30.0, 0.0001, "重做应回到 30")
	gpCheck(gpSvc.gpUndo(), "再次撤销应成功")
	gpApprox(_gpM(gpS, 0), 25.0, 0.0001,
		"第二次撤销必须回到 25 —— 若回到 30，说明 gpRedo 重新捕获了「旧值」")


# "Did anything change?" must be answered by RE-READING the model, not by comparing the request: the
# write path REPAIRS what it is handed (an inside-out pair is scaled back), so a request that differs
# from the old value can still leave the sheet untouched.
# 「有没有变」必须由**重读模型**回答，而不是拿请求来比较：写入路径会**修复**它收到的值（内翻的一对被
# 回缩），故与旧值不同的请求仍可能什么都没改。
#
# ⚠️ THE CARRIER CHANGED ON 2026-10-16, NOT THE PROPERTY / 2026-10-16 换的是载体、不是性质：this test
# used to demonstrate the point with the paper bound (requests of −3 and −99 mm both "clamped" to the 1 mm
# floor). Negative margins are legal now, so the only thing that can still turn a DIFFERENT request into
# the SAME state is the collapse repair — which is what the two requests below exercise.
# 本测试原先用纸面约束演示这一点（请求 −3 与 −99mm 都被「钳」到 1mm 下限）。如今负边距合法，故还能把一个
# **不同**请求变成**同一**状态的只剩防塌缩修复 —— 下面两个请求正是靠它。
func gpTestRepairedNoChangeIsNotAnUndoStep() -> void:
	var gpF: Array = _gpSvc()
	var gpS: GPSheet = gpF[0]
	var gpSvc: GPEditService = gpF[1]
	# Derived, not hardcoded: the repair splits the admissible span evenly between the two margins — per
	# axis, since the sheet is not square.
	# 由模型推导而非写死：修复会在两条边距之间平分可用的跨度 —— **按轴**分开算，因为纸面不是正方形。
	var gpWantX: float = (gpS.gpWidthMM - GPSheet.GP_FRAME_MIN_SIZE_MM) * 0.5
	var gpWantY: float = (gpS.gpHeightMM - GPSheet.GP_FRAME_MIN_SIZE_MM) * 0.5
	var gpWant: Array = [gpWantX, gpWantY, gpWantX, gpWantY]
	gpCheck(gpSvc.gpSetFrameMargins(gpS, [900.0, 900.0, 900.0, 900.0]), "荒唐请求应被接受并回缩")
	for gpI in 4:
		gpApprox(_gpM(gpS, gpI), float(gpWant[gpI]), 0.0001,
			"第 %d 项应被回缩到 %.4f" % [gpI, float(gpWant[gpI])])
	gpEq(gpSvc.gpStack.gpUndoDepth(), 1, "实际改变了 → 记一步")
	# A DIFFERENT absurd request that repairs to the SAME value changes nothing. The two repairs differ
	# only in the last float bits (~1e-14), so this doubles as the reason gpSameMargins must be tolerant:
	# an exact `==` here would record a phantom undo step for an edit that changed nothing.
	# 另一个**不同**的荒唐请求，修复后落到**同一个**值，故什么都没改。两次修复只差浮点末几位（约 1e-14），
	# 故本断言同时充当「gpSameMargins 必须带容差」的理由：此处若用精确 `==`，就会为一次什么都没改的编辑
	# 记下幽灵撤销步。
	gpEq(gpSvc.gpSetFrameMargins(gpS, [1000.0, 1000.0, 1000.0, 1000.0]), false,
		"回缩到同一值的不同请求应返回 false")
	gpEq(gpSvc.gpStack.gpUndoDepth(), 1, "无变化不得留下幽灵撤销步")
	# And re-requesting the current value is likewise a no-op.
	# 重复请求当前值同样是空操作。
	gpEq(gpSvc.gpSetFrameMargins(gpS, gpS.gpFrameMargins.duplicate()), false,
		"重复请求当前值应返回 false")
	# ⚠️ A NEGATIVE request is now a REAL edit rather than a clamped no-op — pinned so the 2026-10-16
	# reversal cannot be silently undone by a later "tidy-up" that reintroduces a floor.
	# ⚠️ 负值请求如今是一次**真实**编辑，而不是被钳掉的空操作 —— 钉住它，使 2026-10-16 的这次反转不会被
	# 将来某次重新引入下限的「顺手清理」悄悄撤销。
	gpCheck(gpSvc.gpSetFrameMargins(gpS, [-30.0, 5.0, 5.0, 5.0]), "负边距请求应被接受")
	gpApprox(_gpM(gpS, GPSheet.GP_MARGIN_LEFT), -30.0, 0.0001, "负边距应原样存下")
	gpEq(gpSvc.gpStack.gpUndoDepth(), 2, "负边距编辑应记一步")


# An unknown field key REFUSES the whole command rather than silently dropping the write — a dropped
# write is indistinguishable from "the drag did not work", so the person drags harder instead of
# reading an error.
# 未知字段键**拒绝整条命令**，而不是静默丢弃写入 —— 静默丢弃与「拖拽没生效」无法区分，于是用户会更
# 用力地拖，而不是去看错误。
func gpTestUnknownFieldKeyRefusesTheWholeCommand() -> void:
	var gpF: Array = _gpSvc()
	var gpS: GPSheet = gpF[0]
	var gpSvc: GPEditService = gpF[1]
	var gpCmd: GPMutateSheetCommand = GPMutateSheetCommand.new(gpS,
		{GPMutateSheetCommand.GP_FIELD_MARGINS: [30.0, 8.0, 8.0, 8.0], "not_a_field": 1.0})
	gpEq(gpCmd.gpExecute(GPCommandContext.new()), false, "白名单之外的键应拒绝整条命令")
	gpCheck(gpS.gpFrameMarginsAreDefault(), "被拒绝的命令不得改动图纸")
	gpEq(gpSvc.gpStack.gpUndoDepth(), 0, "被拒绝的命令不得留下撤销步")
	# A known key alone still works. / 仅含已知键时仍应正常工作。
	var gpOk: GPMutateSheetCommand = GPMutateSheetCommand.new(gpS,
		{GPMutateSheetCommand.GP_FIELD_MARGINS: [30.0, 8.0, 8.0, 8.0]})
	gpEq(gpOk.gpExecute(GPCommandContext.new()), true, "已知键应执行成功")
	gpApprox(_gpM(gpS, 0), 30.0, 0.0001, "已知键应写入边距")


# A null sheet refuses everything, at both the command and the service layer.
# 空图纸在命令层与服务层都应拒绝一切。
func gpTestNullSheetIsRefused() -> void:
	var gpF: Array = _gpSvc()
	var gpSvc: GPEditService = gpF[1]
	var gpCmd: GPMutateSheetCommand = GPMutateSheetCommand.new(null,
		{GPMutateSheetCommand.GP_FIELD_MARGINS: [1.0, 1.0, 1.0, 1.0]})
	gpEq(gpCmd.gpExecute(GPCommandContext.new()), false, "无图纸时命令不得执行")
	gpEq(gpSvc.gpSetFrameMargins(null, [1.0, 1.0, 1.0, 1.0]), false, "无图纸时服务不得执行")


# ⚠️ THE SHEET SIGNAL IS EMITTED BY THE COMMAND, NEVER BY THE SETTER. gpSetFrameMargins() doubles as
# the drag's LIVE PREVIEW write port; emitting there would mark the document dirty and broadcast on
# every mouse move — dozens of times a second.
# ⚠️ **信号由命令发射、绝不由 setter 发射**。gpSetFrameMargins() 同时是拖拽的**实时预览**写口；
# 在那里发射会使每次鼠标移动都标脏并广播 —— 每秒数十次。
func gpTestSheetSignalComesFromTheCommandNotTheSetter() -> void:
	var gpF: Array = _gpSvc()
	var gpS: GPSheet = gpF[0]
	var gpSvc: GPEditService = gpF[1]
	_gpSheetSignalCount = 0
	gpS.gpSheetChanged.connect(_gpOnSheetChanged)
	# (a) A direct setter write is SILENT — this is the drag's per-motion path.
	# （甲）直接经 setter 写入是**静默**的 —— 这正是拖拽逐次移动所走的路径。
	gpS.gpSetFrameMargins([12.0, 12.0, 12.0, 12.0])
	gpEq(_gpSheetSignalCount, 0, "setter 自身绝不发射信号（它是拖拽的实时预览写口）")
	gpS.gpSetFrameMargins(GPSheet.GP_FRAME_MARGINS_DEFAULT)
	gpEq(_gpSheetSignalCount, 0, "复位同样静默")
	# (b) A command write emits exactly once. / （乙）经命令写入恰发射一次。
	gpSvc.gpSetFrameMargins(gpS, [30.0, 8.0, 8.0, 8.0])
	gpEq(_gpSheetSignalCount, 1, "一次命令写入 = 一次信号")
	# (c) A refused command emits nothing. / （丙）被拒绝的命令不发信号。
	gpSvc.gpSetFrameMargins(gpS, [30.0, 8.0, 8.0, 8.0])
	gpEq(_gpSheetSignalCount, 1, "空操作不得发信号")
	# (d) Undo and redo each emit once, so a Ctrl+Z repaints the frame.
	# （丁）撤销与重做各发一次，使 Ctrl+Z 能重绘图框。
	gpSvc.gpUndo()
	gpEq(_gpSheetSignalCount, 2, "撤销应发一次信号")
	gpSvc.gpRedo()
	gpEq(_gpSheetSignalCount, 3, "重做应发一次信号")
	gpS.gpSheetChanged.disconnect(_gpOnSheetChanged)


# Counter for gpTestSheetSignalComesFromTheCommandNotTheSetter (a member, so connect/disconnect use
# the same Callable).
# gpTestSheetSignalComesFromTheCommandNotTheSetter 的计数器（用成员，使 connect/disconnect 使用同一个 Callable）。
var _gpSheetSignalCount: int = 0


func _gpOnSheetChanged() -> void:
	_gpSheetSignalCount += 1


# The command owns its snapshots: a caller that mutates its own request array afterwards must not be
# able to poison the recorded undo step.
# 命令持有自己的快照：调用方事后改写自己那份请求数组，不得污染已记录的撤销步。
func gpTestCallerMutationCannotPoisonTheUndoStep() -> void:
	var gpF: Array = _gpSvc()
	var gpS: GPSheet = gpF[0]
	var gpSvc: GPEditService = gpF[1]
	var gpReq: Array = [30.0, 8.0, 8.0, 8.0]
	gpCheck(gpSvc.gpSetFrameMargins(gpS, gpReq), "写入应成功")
	# ⚠️ A1 REBASE: the sheet's own starting margins come from gpDefaultMarginsFor (A1 → 25/10/10/10),
	# so the undo target is DERIVED, not the A3-era literal 5.
	# ⚠️ A1 重定基：图纸的起始边距来自 gpDefaultMarginsFor（A1 → 25/10/10/10），故撤销目标按
	# **推导**取得，而非 A3 时代的字面值 5。
	var gpDefM: Array = GPSheet.gpDefaultMarginsFor(gpS.gpWidthMM, gpS.gpHeightMM)
	gpReq[0] = 99.0
	gpReq[3] = 99.0
	gpSvc.gpUndo()
	gpApprox(_gpM(gpS, 0), float(gpDefM[0]), 0.0001, "撤销必须回到该档默认左边距，而不是调用方事后改写的 99")
	gpApprox(_gpM(gpS, 3), float(gpDefM[3]), 0.0001, "第 3 项同样必须回到该档默认值")
	gpSvc.gpRedo()
	gpApprox(_gpM(gpS, 0), 30.0, 0.0001, "重做必须回到 30，而不是调用方的 99")


# ===========================================================================
# 8. Canvas wiring / 画布接线
# ===========================================================================

# ⚠️ THE CANVAS SUPPLIES THE SHEET, so the caller never has to hold one — and the sheet written is by
# construction the one on screen, which is what makes "the frame you dragged" and "the frame that gets
# undone" the same object.
# ⚠️ 图纸由**画布**提供，故调用方无需持有它 —— 而所写的图纸按构造就是屏幕上那张，这正是「你拖的那个
# 图框」与「被撤销的那个图框」是同一对象的原因。
func gpTestCanvasCommitsMarginsThroughTheDisplayedSheet() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "起始撤销栈为空")
	gpEq(gpCv.gpRequestSetFrameMargins([30.0, 8.0, 8.0, 8.0]), true, "画布端口应提交成功")
	gpApprox(_gpM(gpS, 0), 30.0, 0.0001, "所写图纸即所显示图纸")
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 1, "一个撤销步")
	gpEq(gpCv.gpRequestSetFrameMargins([30.0, 8.0, 8.0, 8.0]), false, "同样的值再提交一次应为空操作")
	gpCv.gpUndo()
	gpApprox(_gpM(gpS, 0), 25.0, 0.0001, "经画布端口写入的改动可撤销")
	gpCv.free()


# A sheet-level change travels the DOCUMENT-CHANGED channel, because to the user "I moved the frame"
# and "I moved a valve" are the same fact: the drawing has unsaved work.
# 图纸级改动走**文档已变**这条通道：对用户而言「我挪了图框」与「我挪了阀门」是同一件事 —— 图纸有未保存的改动。
func gpTestSheetChangeReachesTheDocumentChannel() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpCount: Array = [0]
	var gpCb: Callable = func() -> void: gpCount[0] = int(gpCount[0]) + 1
	gpCv.gpGraphChanged.connect(gpCb)
	gpEq(gpCv.gpRequestSetFrameMargins([30.0, 8.0, 8.0, 8.0]), true, "提交应成功")
	gpEq(int(gpCount[0]), 1, "图纸级改动应走文档已变通道（与「挪了个阀门」同一件事）")
	gpCv.gpUndo()
	gpEq(int(gpCount[0]), 2, "撤销同样应走该通道（否则脏标记与重绘会分家）")
	gpCv.gpGraphChanged.disconnect(gpCb)
	gpCv.free()


# ⚠️ THE SUBSCRIPTION IS PER-SHEET: rebinding must detach the old sheet, or a background tab's undo
# would repaint the frame of the tab in front — the classic "one signal, two owners" bug.
# ⚠️ 订阅是**按图纸**的：重绑必须解绑旧图纸，否则后台标签页的撤销会重绘前台标签页的图框 ——
# 典型的「一个信号两个属主」。
func gpTestSheetSubscriptionFollowsTheBoundSheet() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpOld: GPSheet = gpF[1]
	var gpNew: GPSheet = GPSheet.gpNew("sheet-2", "次页", 1)
	var gpCount: Array = [0]
	var gpCb: Callable = func() -> void: gpCount[0] = int(gpCount[0]) + 1
	gpCv.gpGraphChanged.connect(gpCb)
	gpOld.gpSheetChanged.emit()
	gpEq(int(gpCount[0]), 1, "绑定的图纸发信号应被转发")
	gpCv.gpSheet = gpNew
	gpNew.gpSheetChanged.emit()
	gpEq(int(gpCount[0]), 2, "重绑后的新图纸发信号应被转发")
	gpOld.gpSheetChanged.emit()
	gpEq(int(gpCount[0]), 2, "已解绑的旧图纸再发信号不得重绘（一个信号两个属主）")
	gpCv.gpGraphChanged.disconnect(gpCb)
	gpCv.free()


# The three ports this stage adds to the canvas facade, pinned (name + arity) the way the post-split
# port snapshot pins the original 41. A deleted or re-signatured forwarder is NOT a compile error in
# GDScript, so it has to be pinned by a test.
# 本阶段为画布门面新增的三个端口，按「拆分后端口快照」钉住最初 41 个的同样方式钉住（名字 + 参数个数）。
# 在 GDScript 里被删掉或改了签名的转发壳**不是**编译错误，故必须用测试钉住。
func gpTestSheetFramePortsArePinned() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpArity: Dictionary = {}
	for gpM in gpCv.get_method_list():
		gpArity[str(gpM["name"])] = (gpM["args"] as Array).size()
	var gpPorts: Array = [
		"gpRequestSetFrameMargins", 1,
		"gpRefreshSheetFrame", 0,
		"gpOnSheetDataChanged", 0,
	]
	for gpI in range(0, gpPorts.size(), 2):
		var gpName: String = str(gpPorts[gpI])
		gpCheck(gpArity.has(gpName), "新增端口仍应在画布上 / new port still on the canvas: " + gpName)
		gpEq(gpArity.get(gpName, -1), int(gpPorts[gpI + 1]),
			"参数个数不变 / arity unchanged: " + gpName)
	# The drag's cheap repaint port must be safe to call when nothing is drawn (no sheet, no frame
	# renderer) — it is called on every mouse move, so a null dereference there would break dragging.
	# This port returns void, so the assertion is on its SIDE EFFECT (it must run, not crash).
	# 拖拽所用的廉价重绘端口在什么都没画时（无图纸、无图框渲染器）也必须可安全调用 ——
	# 它每次鼠标移动都会被调用，此处的空引用会直接让拖拽崩掉。该端口无返回值，故断言落在其**副作用**上。
	gpCv.gpRefreshSheetFrame()
	var gpCount: Array = [0]
	var gpCb: Callable = func() -> void: gpCount[0] = int(gpCount[0]) + 1
	gpCv.gpGraphChanged.connect(gpCb)
	gpCv.gpOnSheetDataChanged()
	gpEq(int(gpCount[0]), 1, "gpOnSheetDataChanged 在无图纸画布上仍应走完文档已变通道")
	gpCv.gpGraphChanged.disconnect(gpCb)
	gpCv.free()


# The tool context exposes the grip delegate the same way it exposes the edge one, so the select tool
# reaches the frame through the same seam as every other grab target.
# 工具上下文以暴露边抓取委托的同一方式暴露图框抓取委托，使选择工具经与其它抓取目标相同的接缝触达图框。
func gpTestToolContextExposesTheFrameGrips() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	# Off-tree the delegate is null (it is built in _ready, like every other delegate) — the getter
	# must therefore be null-safe rather than crash.
	# 树外时委托为 null（与其它委托一样在 _ready 中构建）—— 故该 getter 必须空安全，而不是崩溃。
	gpCheck(gpCv.gpFrameGrips == null, "探针：树外画布的委托未装配（与其它委托同）")
	var gpCtx: GPCanvasToolContext = GPCanvasToolContext.new(gpCv)
	gpCheck(gpCtx.gpFrameGrips == null, "未装配时 getter 应返回 null 而非崩溃")
	var gpGrip: GPFrameGripOps = GPFrameGripOps.new(gpCv)
	gpCv.gpFrameGrips = gpGrip
	gpCheck(gpCtx.gpFrameGrips == gpGrip, "装配后 getter 应返回画布上的同一个委托")
	gpCv.gpFrameGrips = null
	gpCv.free()
