extends "res://tests/gp_test.gd"
# Whole-sheet translation (Rev.3 stage 0d) — the four coordinate families, the command's undo pair,
# the archive key, and the canvas port. Headless, no scene tree.
# 整图平移（Rev.3 阶段 0d）—— 四族坐标、命令的撤销对、存档键、以及画布端口。headless，不入场景树。
#
# The failure modes being guarded against / 所防范的失效模式：
# 1. ONE FAMILY STAYS BEHIND. An edge, an annotation or a drop-restore record silently keeps its old
#    coordinates while the rest of the sheet travels. Nothing crashes, nothing turns red — the drawing
#    just drifts apart, and by the time anyone notices, the cause is a hundred edits behind.
#    某一族**留在原地**。边、注释图形或落点恢复记录在图纸其余部分移动时静默保留旧坐标。不崩溃、不报错 ——
#    图只是慢慢分家，而等有人发现时，原因已在一百次编辑之前。
# 2. A RELATIVE QUANTITY GETS THE WORLD DELTA ADDED. gpLabelOffset is NORMALISED and gpMountOffset is
#    host-local; adding a world delta to either moves a tag or a nozzle TWICE — once with its host and
#    once by itself.
#    某个**相对量**被加上了世界位移。gpLabelOffset 是**归一化**的、gpMountOffset 是宿主本地的；给任一个
#    加上世界位移，会让位号或管口移动**两倍** —— 一次随宿主、一次靠自己。
# 3. THE UNDO STEP IS NOT SELF-INVERSE — a redo re-captures the baseline, or the delta is applied twice,
#    so Ctrl+Z / Ctrl+Y leave the sheet somewhere the user never was.
#    撤销步不是自逆的 —— 重做重新捕获了基线，或位移被施加两次，于是 Ctrl+Z / Ctrl+Y 把图纸留在用户从未
#    到过的位置。
# 4. A SHEET THAT WAS NEVER MOVED GAINS A KEY IN ITS ARCHIVE, breaking byte-stability for old files
#    (the same rule gpFrameMarginsAreDefault() serves for the margins).
#    从未被移动过的图纸在存档里多出一个键，破坏旧档的字节稳定性（与 gpFrameMarginsAreDefault() 对边距
#    所服务的是同一条规则）。
#
# WHY THE ASSERTIONS ARE EXACT (gpEq) WHERE THE ARITHMETIC ALLOWS IT / 为何在算术允许处断言取**精确**（gpEq）：
# the whole point of the snapshot design is that undo REPLAYS a pristine baseline instead of inverting the
# arithmetic, so it must land on bit-identical values even for a delta whose components have no exact
# binary form (0.1 / 0.2). An approximate assertion there would hide the very drift the design exists to
# prevent. Values whose exactness is incidental (a sum of already-inexact numbers) get gpApprox instead.
# 快照设计的全部要点在于：撤销是**重放**一份原始基线，而不是做逆运算；故即使位移的分量没有精确的二进制
# 表示（0.1 / 0.2），它也必须落到逐位相同的值上。那里若用近似断言，就会把该设计所要防止的那点漂移藏起来。
# 而精确性只是副产品的那些值（本就不精确的数之和）改用 gpApprox。


# ===========================================================================
# Fixture / 夹具
# ===========================================================================

# A graph carrying ALL FOUR coordinate families at once — two nodes, an edge with a bent routing, an
# edge with a dangling end, two annotation shapes — plus a drop-restore record, plus the relative
# quantities that must NOT move.
# 一份同时携带**全部四族**坐标的图 —— 两个节点、一条带折点的边、一条含悬空端的边、两枚注释图形 —— 外加
# 一条落点恢复记录，以及那些**不得**移动的相对量。
#
# WHY EVERY FAMILY IN ONE FIXTURE / 为何四族同处一个夹具：the failure this guards is a family being
# FORGOTTEN, so a per-family fixture would test each in isolation and let a forgotten one pass by simply
# not being present. They must all travel through the same call for "one of them stayed behind" to be
# observable at all.
# 本测试所防范的失效是「某一族被**遗忘**」，故按族拆分的夹具会把它们各自孤立地测，而让被遗忘的那一族仅
# 仅因为「不在场」而蒙混过关。它们必须走同一次调用，「其中一族留在原地」才可能被观察到。
func _gpFixture() -> Array:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("N1", "pump", "P-101", Vector2(50.0, 80.0)))
	gpG.gpAddNode(gpG.gpNewNode("N2", "valve", "V-201", Vector2(200.0, 80.0)))
	var gpE1: GPPIDEdge = gpG.gpNewEdge("E1", "N1", "N2")
	gpE1.gpRouting = [Vector2(120.0, 80.0), Vector2(160.0, 60.0)]
	gpG.gpAddEdge(gpE1)
	# A DANGLING end is stored as a world `point` on the ref — the fourth storage shape, and the one most
	# easily forgotten because it lives inside a Dictionary rather than in a typed field.
	# **悬空**端存为引用上的世界 `point` —— 第四种存储形态，也最容易被遗忘，因为它住在字典里而不是类型化字段里。
	var gpE2: GPPIDEdge = gpG.gpNewEdgeEx("E2", {"node_id": "N2", "port_id": ""},
		{"point": [260.0, 40.0]}, "PROCESS")
	gpG.gpAddEdge(gpE2)
	gpG.gpAddShape(GPShape.gpLine(Vector2(10.0, 20.0), Vector2(40.0, 30.0)))
	gpG.gpAddShape(GPShape.gpCircle(Vector2(300.0, 200.0), 15.0))
	var gpN1: GPPIDNode = gpG.gpGetNode("N1")
	gpN1.gpLabelOffset = Vector2(0.5, -0.25)
	gpN1.gpMountOffset = Vector2(7.0, -3.0)
	gpN1.gpMountAngleDeg = 45.0
	gpN1.gpRotationDeg = 30.0
	gpE1.gpAttrs["tag_offset"] = [5.0, 5.0]
	# A reroute record carries ABSOLUTE routing (this is why it is a coordinate holder at all).
	# 一条 reroute 记录携带**绝对**走线（这正是它属于坐标持有者的原因）。
	gpG.gpRecordDrop("N2", {"kind": "reroute", "edge_id": "E1",
		"orig_routing": [Vector2(120.0, 80.0), Vector2(160.0, 60.0)]})
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new())
	# ⚠️ THE SHEET MUST BIND THE SAME GRAPH, or the fixture would describe a state the editor cannot be in:
	# the canvas binds the sheet and the graph through two different setters, and both normally point at the
	# same objects. Leaving gpS.gpGraph empty makes gpS.gpToDict() write an EMPTY drawing — which is how the
	# archive test below first failed, with content that had never been in the archive at all.
	# ⚠️ 图纸必须绑定**同一**张图，否则夹具描述的是一种编辑器不可能处于的状态：画布经两个不同的 setter 绑定
	# 图纸与图，而两者通常指向同一批对象。让 gpS.gpGraph 空着会使 gpS.gpToDict() 写出一份**空**图纸 ——
	# 下方存档测试最初正是这样失败的：内容根本从未进过存档。
	gpS.gpGraph = gpG
	var gpOut: Array = [gpG, gpS, gpSvc]
	return gpOut


# Read a point sequence as a plain Array of Vector2, so a typed Array[Vector2] and a
# PackedVector2Array can both be compared by the same helper.
# 把点序列读作普通 Vector2 数组，使 Array[Vector2] 与 PackedVector2Array 能被同一个辅助函数比较。
func _gpAsArray(gpSeq: Variant) -> Array:
	var gpOut: Array = []
	for gpP in gpSeq:
		gpOut.append(gpP)
	return gpOut


# Element-wise comparison of two point sequences. Accepts Array[Vector2] and PackedVector2Array alike.
# 逐点比较两个点序列。Array[Vector2] 与 PackedVector2Array 均可传入。
func _gpPts(gpGot: Variant, gpWant: Array, gpMsg: String) -> void:
	var gpA: Array = _gpAsArray(gpGot)
	gpEq(gpA.size(), gpWant.size(), gpMsg + " / 点数")
	for gpI in mini(gpA.size(), gpWant.size()):
		var gpP: Vector2 = gpA[gpI]
		var gpQ: Vector2 = gpWant[gpI]
		gpApprox(gpP.x, gpQ.x, 0.0001, "%s / 第 %d 点 x" % [gpMsg, gpI])
		gpApprox(gpP.y, gpQ.y, 0.0001, "%s / 第 %d 点 y" % [gpMsg, gpI])


# ===========================================================================
# 1. The move itself — every family travels, no relative quantity does / 平移本身 —— 各族同行、相对量不动
# ===========================================================================

# ★ THE CENTRAL ASSERTION OF STAGE 0d: one call moves the paper AND all four families of absolute
# coordinates by exactly the same delta, and NOTHING else.
# ★ 阶段 0d 的中心断言：一次调用把纸面**与全部四族**绝对坐标按**同一个**位移移动，且不碰任何别的东西。
func gpTestOneCallMovesThePaperAndEveryCoordinateFamily() -> void:
	var gpF: Array = _gpFixture()
	var gpG: GPPIDGraph = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpSvc: GPEditService = gpF[2]
	var gpDelta: Vector2 = Vector2(30.0, -12.0)
	gpEq(gpS.gpPaperOriginIsDefault(), true, "起始时纸面在世界原点")
	gpEq(gpSvc.gpTranslateSheet(gpS, gpDelta), true, "整图平移应成功")
	# (0) the paper — the one family that lives on the SHEET, not the graph.
	# （零）纸面 —— 唯一住在**图纸**上、而非图上的那一族。
	gpEq(gpS.gpPaperOriginIsDefault(), false, "移动后纸面已非默认")
	gpEq(gpS.gpPaperOrigin, gpDelta, "纸面原点应恰为位移（精确）")
	# (1) nodes / 图元
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(80.0, 68.0), "图元 N1 应随纸平移（精确）")
	gpEq(gpG.gpGetNode("N2").gpPosition, Vector2(230.0, 68.0), "图元 N2 应随纸平移（精确）")
	# (2a) edge routing / 边走线
	_gpPts(gpG.gpGetEdge("E1").gpRouting, [Vector2(150.0, 68.0), Vector2(190.0, 48.0)], "边 E1 走线应随纸平移")
	# (2b) the dangling `point` — and the BOUND end must not grow one.
	# 悬空端 `point` —— 而**绑定**端不得凭空长出该键。
	#
	# ⚠️ READ AS RAW FLOATS: the stored form is a plain [x, y] pair inside the ref dictionary, not a
	# Vector2 — a distinction that matters because a node's position has a typed field to round-trip
	# through while this one has only the dictionary.
	# ⚠️ 按**裸浮点**读取：存储形态是引用字典里的普通 [x, y] 数对、而非 Vector2 —— 这个区别有意义，因为
	# 图元坐标有一个类型化字段可往返，而这个只有字典。
	var gpToPt: Variant = gpG.gpGetEdge("E2").gpToRef.get("point", null)
	gpCheck(gpToPt is Array, "悬空端应仍有 point 键")
	var gpToArr: Array = gpToPt as Array
	gpEq(gpToArr.size(), 2, "悬空端 point 应仍是两元")
	gpApprox(float(gpToArr[0]), 290.0, 0.0001, "悬空端 point x 应随纸平移")
	gpApprox(float(gpToArr[1]), 28.0, 0.0001, "悬空端 point y 应随纸平移")
	gpEq(gpG.gpGetEdge("E2").gpFromRef.get("point", null), null,
		"绑定端不得凭空长出 point 键（否则它会被读作悬空端）")
	# (3) annotation shapes / 注释图形
	_gpPts(gpG.gpShapes[0].gpPoints, [Vector2(40.0, 8.0), Vector2(70.0, 18.0)], "注释直线应随纸平移")
	_gpPts(gpG.gpShapes[1].gpPoints, [Vector2(330.0, 188.0)], "注释圆心应随纸平移")
	# (4) the drop-restore record / 落点恢复记录
	var gpRec: Dictionary = gpG.gpDropRecords("N2")[0]
	_gpPts(gpRec.get("orig_routing", []), [Vector2(150.0, 68.0), Vector2(190.0, 48.0)],
		"落点恢复记录的走线应随纸平移")
	gpEq(int(gpRec.get("_rid", -1)) > 0, true, "记录 id 不得因平移而丢失或改写")


# ★ THE COUNTER-ASSERTION: every RELATIVE quantity must be untouched. This is the half that is easy to get
# wrong by "helpfully" translating everything on the node.
# ★ 反向断言：每一个**相对量**必须原封不动。这是最容易因「顺手把节点上什么都平移一下」而搞错的一半。
func gpTestRelativeQuantitiesAreNeverTranslated() -> void:
	var gpF: Array = _gpFixture()
	var gpG: GPPIDGraph = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpSvc: GPEditService = gpF[2]
	var gpN1: GPPIDNode = gpG.gpGetNode("N1")
	gpSvc.gpTranslateSheet(gpS, Vector2(30.0, -12.0))
	gpEq(gpN1.gpLabelOffset, Vector2(0.5, -0.25),
		"gpLabelOffset 是归一化的、构造上已随行，再加位移会让位号移动两倍")
	gpEq(gpN1.gpMountOffset, Vector2(7.0, -3.0),
		"gpMountOffset 相对宿主锚点，再加世界位移会让管口移动两倍")
	gpApprox(gpN1.gpMountAngleDeg, 45.0, 0.0001, "挂载角度与位置无关，不得改变")
	gpApprox(gpN1.gpRotationDeg, 30.0, 0.0001, "自转角与位置无关，不得改变")
	gpEq(gpN1.gpTag, "P-101", "位号文本不因移动而改变")
	gpEq(gpG.gpShapes[1].gpRadius, 15.0, "圆的半径与圆心在哪儿无关，不得改变")
	var gpTagOff: Array = gpG.gpGetEdge("E1").gpAttrs.get("tag_offset", [])
	gpEq(gpTagOff.size(), 2, "管线号偏移应仍为两元（存储形态是裸 [x, y]，不是 Vector2）")
	gpApprox(float(gpTagOff[0]), 5.0, 0.0001, "管线号偏移 x 相对自动落位处，不得被世界位移污染")
	gpApprox(float(gpTagOff[1]), 5.0, 0.0001, "管线号偏移 y 同上")


# The frame FOLLOWS the paper without a single margin changing — this is the whole reason the origin is
# a separate field from the margins.
# 图框**随**纸而走、而一条边距都不变 —— 这正是把「原点」与「边距」做成两个字段的全部理由。
func gpTestFrameFollowsThePaperAndNoMarginChanges() -> void:
	var gpF: Array = _gpFixture()
	var gpS: GPSheet = gpF[1]
	var gpSvc: GPEditService = gpF[2]
	var gpBefore: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	var gpMarginsBefore: Array = gpS.gpFrameMargins.duplicate()
	var gpDelta: Vector2 = Vector2(30.0, -12.0)
	gpSvc.gpTranslateSheet(gpS, gpDelta)
	var gpNow: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	gpEq(gpNow.position, gpBefore.position + gpDelta, "图框位置应恰随纸位移（精确）")
	gpEq(gpNow.size, gpBefore.size, "图框尺寸必须逐位不变")
	for gpI in 4:
		gpEq(gpS.gpFrameMargins[gpI], gpMarginsBefore[gpI],
			"第 %d 条边距必须逐位不变（移动图纸不是改边距）" % gpI)
	# The trim line and the paper rectangle travel together, which is what the user actually sees.
	# The inset rides the frame visual scale (A1 rebase, 2026-10-16).
	# ⚠️ THE EXPECTATION MUST NOT CALL gpS.gpFrameScale() — an assertion that re-derives its value
	# through the very function under test shares every bug with it and pins nothing (the lesson of
	# the reverse-verify probe: this exact form went GREEN with the mechanism dead). The ratio is
	# therefore written from the ISO numbers directly: 841/420.
	# 裁边线与纸面矩形同行 —— 那才是用户真正看到的东西。内缩量随图幅视觉比例（A1 重定基，
	# 2026-10-16）。
	# ⚠️ 期望值**不得**调用 gpS.gpFrameScale() —— 经被测函数自身再推导的断言与它共享全部缺陷、
	# 什么也钉不住（反向验证探针的教训：正是这种形态在机制被注入弄死后依然全绿）。故比例直接
	# 由 ISO 数值写出：841/420。
	var gpInset: float = GPFrameGeometry.GP_TRIM_INSET_MM * 841.0 / 420.0
	gpEq(GPFrameGeometry.gpPaperRect(gpS).position, gpDelta, "纸面矩形应随原点移动")
	gpEq(GPFrameGeometry.gpTrimRect(gpS).position,
		gpDelta + Vector2(gpInset, gpInset),
		"裁边线应随纸面、并按同一内缩量偏移（它才是屏幕上那条「纸的边界」）")
	gpEq(GPFrameGeometry.gpTrimRect(gpS).size,
		Vector2(gpS.gpWidthMM, gpS.gpHeightMM)
			- Vector2(gpInset, gpInset) * 2.0,
		"裁边线尺寸由纸幅决定，移动不得改变它（只有位置该变）")


# ===========================================================================
# 2. The undo pair / 撤销对
# ===========================================================================

# Undo is an EXACT rewind of all four families — asserted with gpEq, because that is the property a
# subtract-the-delta implementation could not hold.
# 撤销把四族**精确**回退 —— 用 gpEq 断言，因为那正是「减去位移」式实现无法保持的性质。
#
# ⚠️ THE DELTA IS DELIBERATELY NOT BINARY-EXACT (0.1 / 0.2). With (30, -12) every value would come back
# exactly even under naive arithmetic, so the test would prove nothing.
# ⚠️ 位移**刻意**取没有精确二进制表示的值（0.1 / 0.2）。若取 (30, −12)，即便用朴素算术每个值也会精确回来，
# 该测试就什么也证明不了。
func gpTestUndoIsAnExactRewindOfEveryFamily() -> void:
	var gpF: Array = _gpFixture()
	var gpG: GPPIDGraph = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpSvc: GPEditService = gpF[2]
	var gpDelta: Vector2 = Vector2(0.1, 0.2)
	gpEq(gpSvc.gpTranslateSheet(gpS, gpDelta), true, "平移应成功")
	gpEq(gpSvc.gpStack.gpUndoDepth(), 1, "一次平移 = 一个撤销步")
	gpCheck(not gpS.gpPaperOriginIsDefault(), "移动后纸面非默认")
	gpEq(gpSvc.gpUndo(), true, "撤销应成功")
	gpEq(gpS.gpPaperOrigin, Vector2.ZERO, "撤销后纸面应回到世界原点（精确）")
	gpEq(gpS.gpPaperOriginIsDefault(), true, "撤销后「从未移动过」应重新成立")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(50.0, 80.0), "图元坐标应逐位回到原值")
	# Element-wise rather than array-vs-array: gpRouting is a typed Array[Vector2] and the literal here is
	# an untyped Array, so comparing them as wholes would lean on Godot's cross-type array equality instead
	# of on the property under test.
	# 逐元素而非整数组比较：gpRouting 是类型化的 Array[Vector2]，而此处的字面量是普通 Array；整数组比较
	# 会把断言押在 Godot 的跨类型数组相等语义上，而不是押在被测属性上。
	var gpRoute: Array[Vector2] = gpG.gpGetEdge("E1").gpRouting
	gpEq(gpRoute.size(), 2, "走线点数不变")
	gpEq(gpRoute[0], Vector2(120.0, 80.0), "走线第 0 点应逐位回到原值")
	gpEq(gpRoute[1], Vector2(160.0, 60.0), "走线第 1 点应逐位回到原值")
	gpEq(gpG.gpGetEdge("E2").gpToRef.get("point", null), [260.0, 40.0], "悬空端应逐位回到原值")
	gpEq(gpG.gpShapes[0].gpPoints, PackedVector2Array([Vector2(10.0, 20.0), Vector2(40.0, 30.0)]),
		"注释图形应逐位回到原值")
	gpEq(gpSvc.gpStack.gpUndoDepth(), 0, "撤销后栈应清空")


# Redo re-applies the ORIGINAL delta from the SAME baseline — never twice, and never a re-capture.
# 重做自**同一**基线重新施加**原始**位移 —— 绝不两次，也绝不重新捕获。
func gpTestRedoIsNotASecondTranslate() -> void:
	var gpF: Array = _gpFixture()
	var gpG: GPPIDGraph = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpSvc: GPEditService = gpF[2]
	var gpDelta: Vector2 = Vector2(30.0, -12.0)
	gpSvc.gpTranslateSheet(gpS, gpDelta)
	var gpAfterMove: Vector2 = gpS.gpPaperOrigin
	var gpNodeAfterMove: Vector2 = gpG.gpGetNode("N1").gpPosition
	gpSvc.gpUndo()
	gpEq(gpSvc.gpRedo(), true, "重做应成功")
	gpEq(gpS.gpPaperOrigin, gpAfterMove, "重做后纸面应与移动后逐位一致（若翻倍则说明施加了两次）")
	gpEq(gpG.gpGetNode("N1").gpPosition, gpNodeAfterMove, "重做后图元应与移动后逐位一致")
	# ⚠️ THE SECOND UNDO IS THE POINT (mirrors the margin command's own test): the default gpRedo()
	# re-runs gpExecute(), which would re-capture the post-move state as the baseline and make the second
	# Ctrl+Z restore the state the user just undid.
	# ⚠️ **第二次撤销才是关键**（与边距命令自身的测试同形）：默认的 gpRedo() 会重跑 gpExecute()，从而把
	# 移动后的状态重新捕获为基线，于是第二次 Ctrl+Z 会恢复用户刚撤销掉的那个状态。
	gpSvc.gpUndo()
	gpEq(gpS.gpPaperOrigin, Vector2.ZERO, "第二次撤销必须回到原点 —— 若回到移动后的值，说明重做重捕了基线")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(50.0, 80.0), "第二次撤销后图元也必须回到原值")


# A zero delta is refused, so the drag's plain click records no phantom undo step.
# 零位移被拒绝，故拖拽中的单纯点击不会留下幽灵撤销步。
func gpTestZeroDeltaIsNotAnUndoStep() -> void:
	var gpF: Array = _gpFixture()
	var gpS: GPSheet = gpF[1]
	var gpSvc: GPEditService = gpF[2]
	gpEq(gpSvc.gpTranslateSheet(gpS, Vector2.ZERO), false, "零位移应被拒绝")
	gpEq(gpSvc.gpStack.gpUndoDepth(), 0, "零位移不得留下撤销步")
	gpEq(gpS.gpPaperOriginIsDefault(), true, "零位移不得扰动图纸")


# Null sheet / absent graph / null context are all refused, so a detached canvas cannot half-move a sheet.
# 空图纸 / 缺图 / 空上下文一律拒绝，使脱机的画布无法把图纸移一半。
func gpTestMissingInputsAreRefused() -> void:
	var gpF: Array = _gpFixture()
	var gpS: GPSheet = gpF[1]
	var gpSvc: GPEditService = gpF[2]
	gpEq(gpSvc.gpTranslateSheet(null, Vector2(1.0, 1.0)), false, "空图纸应被拒绝")
	# A command built by hand against a context that carries no graph (an unbound canvas).
	# 手工构造一条命令，其上下文不携带图（未绑定的画布）。
	var gpCmd: GPTranslateSheetCommand = GPTranslateSheetCommand.new(gpS, Vector2(1.0, 1.0))
	gpEq(gpCmd.gpExecute(GPCommandContext.new()), false, "上下文无图时应拒绝执行")
	gpEq(gpCmd.gpExecute(null), false, "空上下文应拒绝执行")
	var gpNullSheetCmd: GPTranslateSheetCommand = GPTranslateSheetCommand.new(null, Vector2(1.0, 1.0))
	gpEq(gpNullSheetCmd.gpExecute(GPCommandContext.new()), false, "无图纸的命令应拒绝执行")
	gpEq(gpS.gpPaperOriginIsDefault(), true, "被拒绝的命令不得扰动图纸")


# Three separate moves are three undo steps — never one, and never nine.
# 三次独立平移即三个撤销步 —— 不是一步，也不是九步。
func gpTestEachMoveIsItsOwnUndoStep() -> void:
	var gpF: Array = _gpFixture()
	var gpS: GPSheet = gpF[1]
	var gpSvc: GPEditService = gpF[2]
	for gpI in 3:
		gpSvc.gpTranslateSheet(gpS, Vector2(10.0, 0.0))
		gpEq(gpSvc.gpStack.gpUndoDepth(), gpI + 1, "第 %d 次平移后撤销深度应为 %d" % [gpI + 1, gpI + 1])
	gpEq(gpS.gpPaperOrigin, Vector2(30.0, 0.0), "三次 10mm 的平移应累积为 30mm")
	gpSvc.gpUndo()
	gpEq(gpS.gpPaperOrigin, Vector2(20.0, 0.0), "第一次撤销应回到 20")
	gpSvc.gpUndo()
	gpEq(gpS.gpPaperOrigin, Vector2(10.0, 0.0), "第二次撤销应回到 10")
	gpSvc.gpUndo()
	gpEq(gpS.gpPaperOrigin, Vector2.ZERO, "第三次撤销应回到原点")


# ===========================================================================
# 3. The snapshot / 快照
# ===========================================================================

# The snapshot must be plain DATA, not a view onto the live model — otherwise a restore would be a no-op
# that silently leaves the drawing wherever the last edit put it.
# 快照必须是**普通数据**，而不是活模型上的一个视图 —— 否则「还原」会是一次空操作，静默地把图留在最后一次
# 编辑所处的位置。
func gpTestSnapshotIsNotAliasedToTheLiveModel() -> void:
	var gpF: Array = _gpFixture()
	var gpG: GPPIDGraph = gpF[0]
	var gpSnap: Dictionary = gpG.gpCaptureGeometry()
	gpEq((gpSnap.get("nodes", {}) as Dictionary).size(), 2, "捕获应枚举全部图元（两份）")
	gpEq((gpSnap.get("edges", {}) as Dictionary).size(), 2, "捕获应枚举全部边（两条）")
	gpEq((gpSnap.get("shapes", []) as Array).size(), 2, "捕获应枚举全部注释图形（两枚）")
	# Mutate every family after the capture. / 捕获之后改写每一族。
	gpG.gpGetNode("N1").gpPosition = Vector2(999.0, 999.0)
	gpG.gpGetEdge("E1").gpRouting = [Vector2(1.0, 1.0)]
	gpG.gpGetEdge("E2").gpToRef["point"] = [2.0, 2.0]
	gpG.gpShapes[0].gpPoints = PackedVector2Array([Vector2(3.0, 3.0)])
	gpG.gpRestoreGeometry(gpSnap)
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(50.0, 80.0), "还原应回到捕获时的图元坐标")
	gpEq(gpG.gpGetEdge("E1").gpRouting.size(), 2, "还原应恢复走线的点数")
	gpEq(gpG.gpGetEdge("E1").gpRouting[0], Vector2(120.0, 80.0), "还原应回到捕获时的走线")
	gpEq(gpG.gpGetEdge("E2").gpToRef.get("point", null), [260.0, 40.0], "还原应回到捕获时的悬空端")
	gpEq(gpG.gpShapes[0].gpPoints, PackedVector2Array([Vector2(10.0, 20.0), Vector2(40.0, 30.0)]),
		"还原应回到捕获时的注释图形")


# Restoring is tolerant: an empty snapshot is a no-op, and an object created AFTER the capture is left
# exactly where it is rather than guessed at.
# 还原是容错的：空快照为空操作；捕获**之后**新建的对象原样保留，绝不臆测。
func gpTestRestoreIsTolerant() -> void:
	var gpF: Array = _gpFixture()
	var gpG: GPPIDGraph = gpF[0]
	gpG.gpRestoreGeometry({})
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(50.0, 80.0), "空快照应为空操作")
	var gpSnap: Dictionary = gpG.gpCaptureGeometry()
	gpG.gpAddNode(gpG.gpNewNode("N3", "tank", "T-301", Vector2(400.0, 300.0)))
	gpG.gpRestoreGeometry(gpSnap, Vector2(10.0, 10.0))
	gpEq(gpG.gpGetNode("N3").gpPosition, Vector2(400.0, 300.0),
		"捕获之后新建的图元不在快照里，应原样保留而非被猜一个值")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(60.0, 90.0), "快照内的图元仍应按位移还原")


# ===========================================================================
# 4. Archive / 存档
# ===========================================================================

# Byte-stability: a sheet that was never moved carries NO key, and one that was moved round-trips.
# 字节稳定性：从未移动过的图纸**不带**该键，移动过的则完整往返。
func gpTestPaperOriginIsWrittenOnlyAfterAMoveAndRoundTrips() -> void:
	var gpF: Array = _gpFixture()
	var gpS: GPSheet = gpF[1]
	var gpSvc: GPEditService = gpF[2]
	gpEq(gpS.gpToDict().has("paper_origin"), false,
		"从未移动过的图纸不得写出 paper_origin（否则旧档重新保存后字节会变）")
	gpSvc.gpTranslateSheet(gpS, Vector2(30.0, -12.0))
	var gpD: Dictionary = gpS.gpToDict()
	gpCheck(gpD.has("paper_origin"), "移动过的图纸应写出 paper_origin")
	# Read as raw floats: the archive form is a plain [x, y] pair, NOT a Vector2 (that is the whole reason
	# a translation has a serde shape to get right).
	# 按裸浮点读：存档形态是普通 [x, y] 数对、而非 Vector2（这正是平移需要处理序列化形态的全部原因）。
	var gpWritten: Array = gpD.get("paper_origin", [])
	gpEq(gpWritten.size(), 2, "写出的原点应有两元")
	gpApprox(float(gpWritten[0]), 30.0, 0.0001, "写出的原点 x 应等于位移")
	gpApprox(float(gpWritten[1]), -12.0, 0.0001, "写出的原点 y 应等于位移")
	var gpBack: GPSheet = GPSheet.gpFromDict(gpD)
	gpEq(gpBack.gpPaperOrigin, Vector2(30.0, -12.0), "读回的原点应与写出的一致")
	gpEq(gpBack.gpPaperOriginIsDefault(), false, "读回后「已移动过」应成立")
	# The content travels in the same document, so the two halves stay in step across a save/load.
	# 内容随同一份文档往返，故两半在一次存/读之后仍保持一致。
	gpEq(gpBack.gpGraph.gpGetNode("N1").gpPosition, Vector2(80.0, 68.0), "图元坐标应随存档往返")


# A malformed / absent key keeps the default — an archive from before this key existed must open as a
# sheet that was never moved, not crash and not land somewhere arbitrary.
# 键缺失或格式不对时保留默认值 —— 本键出现之前的存档必须打开为「从未移动过的图纸」，既不崩也不落到任意处。
func gpTestMalformedPaperOriginKeepsTheDefault() -> void:
	for gpBad in [null, "nope", [1.0], {}, [1.0, 2.0, 3.0, 4.0]]:
		var gpD: Dictionary = {"id": "s", "name": "n", "index": 0, "paper_origin": gpBad}
		var gpS: GPSheet = GPSheet.gpFromDict(gpD)
		if gpBad is Array and (gpBad as Array).size() >= 2:
			gpEq(gpS.gpPaperOrigin, Vector2(1.0, 2.0), "合法数组（含超长）应被读入：%s" % str(gpBad))
		else:
			gpEq(gpS.gpPaperOriginIsDefault(), true, "畸形值 %s 应保留默认原点" % str(gpBad))


# ===========================================================================
# 5. Canvas port / 画布端口
# ===========================================================================

# The canvas supplies the sheet AND the graph, so the tool never has to hold either — and the sheet moved
# is by construction the one on screen.
# 图纸与图**都**由画布提供，故工具无需持有任何一个 —— 而所移动的图纸按构造就是屏幕上那一张。
func gpTestCanvasPortUsesTheDisplayedSheetAndGraph() -> void:
	var gpF: Array = _gpFixture()
	var gpG: GPPIDGraph = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpEq(gpCv.gpRequestTranslateSheet(Vector2(5.0, 5.0)), false, "未绑图纸时应拒绝")
	gpCv.gpSheet = gpS
	gpCv.gpGraph = gpG
	gpEq(gpCv.gpRequestTranslateSheet(Vector2(5.0, 5.0)), true, "绑好之后应成功")
	gpEq(gpS.gpPaperOrigin, Vector2(5.0, 5.0), "所移动的图纸即所显示图纸")
	gpEq(gpG.gpGetNode("N1").gpPosition, Vector2(55.0, 85.0), "所移动的内容取自画布上的图")
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 1, "一个撤销步")
	gpCv.gpUndo()
	gpEq(gpS.gpPaperOrigin, Vector2.ZERO, "经画布端口提交的移动可撤销")
	gpCv.free()


# The two canvas ports this stage adds, pinned by name + arity — a deleted or re-signatured forwarder is
# NOT a compile error in GDScript, so it has to be pinned by a test.
# 本阶段新增的两个画布端口，按「名字 + 参数个数」钉住 —— 在 GDScript 里被删掉或改了签名的转发壳**不是**
# 编译错误，故必须用测试钉住。
func gpTestCanvasPortsArePinned() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpArity: Dictionary = {}
	for gpM in gpCv.get_method_list():
		gpArity[str(gpM["name"])] = (gpM["args"] as Array).size()
	var gpPorts: Array = [
		"gpRequestTranslateSheet", 1,
		"gpRefreshEdges", 0,
	]
	for gpI in range(0, gpPorts.size(), 2):
		var gpName: String = str(gpPorts[gpI])
		gpCheck(gpArity.has(gpName), "新增端口仍应在画布上 / new port still on the canvas: " + gpName)
		gpEq(gpArity.get(gpName, -1), int(gpPorts[gpI + 1]),
			"参数个数不变 / arity unchanged: " + gpName)
	# Both must be safe on a canvas with nothing bound — the drag calls them on every mouse move.
	# 两者在什么都没绑的画布上都必须安全 —— 拖拽每次鼠标移动都会调用它们。
	gpCv.gpRefreshEdges()
	gpEq(gpCv.gpRequestTranslateSheet(Vector2(1.0, 1.0)), false, "无图纸的画布应安全地拒绝")
	gpCv.free()
