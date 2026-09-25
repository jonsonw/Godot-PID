class_name GPGTestEdgeTagOffset
extends GPGTest
# Copyright © 2026 Jonson Wang
# Edge line-number drag: placement gap, the derived leader line, the stored offset, and the
# move command. The number must sit CLOSE to its pipe (GP_GAP shrunk from 8.0 to 2.5), be
# draggable, and grow a leader line only once dragged far enough.
# 边管线号的拖拽：落位净距、推导出的引出线、所存偏移，以及移动命令。编号必须贴近其管线
#（GP_GAP 由 8.0 缩到 2.5）、可拖动，且唯有被拖远后才长出引出线。

# Fixture: N1 -(E1)- N2, plus a fresh id generator, context and stack.
# 夹具：N1 -(E1)- N2，外加全新的 id 生成器、上下文与命令栈。
func _mkFixture() -> Array:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-101", Vector2(10, 10)))
	g.gpAddNode(g.gpNewNode("N2", "valve", "V-201", Vector2(100, 10)))
	g.gpAddEdge(g.gpNewEdge("E1", "N1", "N2"))
	var ctx: GPCommandContext = GPCommandContext.new(g, GPIdGen.new())
	var st: GPCommandStack = GPCommandStack.new()
	return [g, ctx, st]


# The whole point of the request: the number sits close to its pipe, not 8 mm away.
# 本请求的全部意义：编号贴近管线，而非远在 8mm 之外。
func gpTestGapIsCloserThanBefore() -> void:
	gpApprox(GPEdgeTagLayout.GP_GAP, 2.5, 1e-6, "default gap shrunk to 2.5 mm / 默认净距缩到 2.5mm")
	gpCheck(GPEdgeTagLayout.GP_GAP < 8.0, "gap is closer than the old 8.0 mm / 净距比旧的 8.0mm 更近")
	gpApprox(GPEdgeTagLayout.GP_LEADER_MIN, 5.0, 1e-6, "leader threshold is 2x the gap / 引出线阈值 = 净距两倍")


# A near-zero offset must erase the key (no residue in the file); a real one stores mm.
# 近零偏移必须删除该键（文件中不留残留）；真实偏移以 mm 存储。
func gpTestOffsetErasePolicy() -> void:
	var e: GPPIDEdge = GPPIDEdge.new()
	e.gpInstanceId = "E1"
	gpEq(e.gpTagOffset(), Vector2.ZERO, "no offset to begin with / 初始无偏移")
	e.gpSetTagOffset(Vector2(0.0, -18.0))
	gpApprox(e.gpTagOffset().y, -18.0, 1e-6, "non-trivial offset stored / 有效偏移被存储")
	gpCheck(e.gpAttrs.has("tag_offset"), "key written when offset is real / 偏移有效时键被写出")
	e.gpSetTagOffset(Vector2(0.01, 0.01))  # below the 0.05 mm erase epsilon
	gpCheck(not e.gpAttrs.has("tag_offset"), "near-zero offset erases the key / 近零偏移擦除该键")
	gpEq(e.gpTagOffset(), Vector2.ZERO, "erased offset reads back as zero / 擦除后读回为零")


# At the default placement the number is close enough that NO leader line is drawn.
# 在默认落位下编号足够近，故不画引出线。
func gpTestNoLeaderAtDefaultGap() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(200.0, 0.0)])
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 40.0, 16.0, true)
	var gpLeader: PackedVector2Array = GPEdgeTagLayout.gpLeader(gpPts, gpPl, 40.0, 16.0)
	gpEq(gpLeader.size(), 0, "no leader while sitting at the default gap / 处于默认净距时不画引出线")


# Once dragged far enough (clearance > GP_LEADER_MIN) a leader appears, tying it back.
# 一旦被拖得足够远（净距 > GP_LEADER_MIN），即出现指回管线的引出线。
# The reference case: the number has been pulled BELOW the pipe, so it needs the full callout —
# a slanted segment from the pipe plus a horizontal shoulder under the text.
# 参照图的情形：编号被拉到管线**下方**，故需要完整标注 —— 自管线而来的斜段，加文字下方的水平肩线。
func gpTestLeaderAppearsWhenDraggedFar() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(200.0, 0.0)])
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 40.0, 16.0, true,
		GPEdgeTagLayout.GP_GAP, Vector2(0.0, 30.0))
	var gpLeader: PackedVector2Array = GPEdgeTagLayout.gpLeader(gpPts, gpPl, 40.0, 16.0)
	gpEq(gpLeader.size(), 3, "leader = slanted segment + shoulder / 引出线 = 斜段 + 肩线")
	gpCheck(gpLeader[0] != gpLeader[1], "leader points are distinct / 引出线各点不同")


# The shape contract: anchor ON the pipe, horizontal shoulder under the text, and a segment that
# is genuinely SLANTED rather than the perpendicular tick the first implementation drew.
# 形状契约：锚点落在管线上、肩线水平位于文字下方、且该段确实**倾斜**，而非初版那条垂直短线。
func gpTestLeaderShapeIsSlantedOverShoulder() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(200.0, 0.0)])
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 40.0, 16.0, true,
		GPEdgeTagLayout.GP_GAP, Vector2(0.0, 30.0))
	var gpLeader: PackedVector2Array = GPEdgeTagLayout.gpLeader(gpPts, gpPl, 40.0, 16.0)
	gpEq(gpLeader.size(), 3, "three points / 三个点")
	var gpAnchor: Vector2 = gpLeader[0]
	var gpElbow: Vector2 = gpLeader[1]
	var gpTail: Vector2 = gpLeader[2]
	# 1. The anchor lands on the pipe (which is the y = 0 axis in this fixture).
	# 1. 锚点落在管线上（本夹具中管线即 y = 0 轴）。
	gpApprox(gpAnchor.y, 0.0, 1e-3, "anchor sits on the pipe / 锚点落在管线上")
	gpCheck(gpAnchor.x >= 0.0 and gpAnchor.x <= 200.0, "anchor is within the pipe span / 锚点在管线跨度内")
	# 2. The shoulder is horizontal, one pad below the text baseline.
	# 2. 肩线水平，位于文字基线下方一个 pad 处。
	var gpPos: Vector2 = gpPl.get("pos", Vector2.ZERO)
	gpApprox(gpElbow.y, gpTail.y, 1e-3, "shoulder is horizontal / 肩线水平")
	gpApprox(gpElbow.y, gpPos.y + GPEdgeTagLayout.GP_LEADER_PAD, 1e-3,
		"shoulder sits one pad under the baseline / 肩线位于基线下方一个 pad 处")
	gpCheck(gpElbow.y > gpPos.y, "shoulder is BELOW the text / 肩线在文字下方")
	# 3. ... and it spans the text width plus the overhang on both sides.
	# 3. 其跨度 = 文字宽度 + 两端外伸。
	gpApprox(absf(gpElbow.x - gpTail.x), 40.0 + 2.0 * GPEdgeTagLayout.GP_LEADER_OVERHANG, 1e-3,
		"shoulder spans the text width + overhang / 肩线跨度为文字宽度加两端外伸")
	# 4. The segment is slanted at the conventional angle — the point of the whole change.
	# 4. 该段按常规夹角倾斜 —— 正是本次改动的要点。
	var gpDx: float = absf(gpAnchor.x - gpElbow.x)
	var gpDy: float = absf(gpAnchor.y - gpElbow.y)
	gpCheck(gpDx > 0.5, "the segment is slanted, not vertical / 该段倾斜而非竖直")
	gpApprox(rad_to_deg(atan2(gpDy, gpDx)), GPEdgeTagLayout.GP_LEADER_ANGLE_DEG, 0.5,
		"slanted at the conventional leader angle / 按常规引出线夹角倾斜")
	# 5. It leaves away from the text, so it never cuts back across the glyphs it annotates.
	# 5. 背离文字出发，故绝不回切穿过其所标注的字形。
	gpCheck(gpAnchor.x > gpElbow.x, "leaves away from the text / 背向文字出发")


# A SHORT pipe: the outward ray misses it, so the mirrored shoulder end must take over rather
# than the leader collapsing into a perpendicular tick.
# **短**管线：外向射线擦肩而过，故须由镜像肩线端接管，而不是让引出线塌缩成垂直短线。
func gpTestLeaderSurvivesShortPipe() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(6.0, 0.0)])
	var gpPl: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 40.0, 16.0, true,
		GPEdgeTagLayout.GP_GAP, Vector2(0.0, 30.0))
	var gpLeader: PackedVector2Array = GPEdgeTagLayout.gpLeader(gpPts, gpPl, 40.0, 16.0)
	gpEq(gpLeader.size(), 3, "still a full leader / 仍是完整引出线")
	gpApprox(gpLeader[0].y, 0.0, 1e-3, "anchor still lands on the pipe / 锚点仍落在管线上")
	gpApprox(gpLeader[1].y, gpLeader[2].y, 1e-3, "shoulder stays horizontal / 肩线保持水平")
	gpCheck(absf(gpLeader[0].x - gpLeader[1].x) > 0.5, "segment stays slanted / 该段仍倾斜")


# The leader must be the THINNEST line on the sheet: one ISO step below the 0.18 mm signal line,
# and under the shared 1.2 px screen floor.
# 引出线必须是图面上**最细**的线：比 0.18mm 信号线低一档 ISO 级，且低于共用的 1.2px 屏幕下限。
func gpTestLeaderIsThinnestLine() -> void:
	gpCheck(GPEdgePainter.GP_LEADER_WIDTH_MM < 0.18,
		"thinner than the 0.18 mm signal line / 比 0.18mm 信号线更细")
	gpCheck(GPEdgePainter.GP_LEADER_MIN_PX < GPEdgeStyle.GP_MIN_PX,
		"screen floor is below the shared 1.2 px floor / 屏幕下限低于共用的 1.2px 下限")


# The manual offset shifts the placement by exactly that vector, in world units.
# 手工偏移按该向量（世界单位）精确平移落位。
func gpTestPlaceAppliesOffset() -> void:
	var gpPts: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(200.0, 0.0)])
	var gpBase: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 40.0, 16.0, true)
	var gpMoved: Dictionary = GPEdgeTagLayout.gpPlace(gpPts, 40.0, 16.0, true,
		GPEdgeTagLayout.GP_GAP, Vector2(12.0, -7.0))
	var gpBasePos: Vector2 = gpBase.get("pos", Vector2.ZERO)
	var gpMovedPos: Vector2 = gpMoved.get("pos", Vector2.ZERO)
	gpApprox(gpMovedPos.x - gpBasePos.x, 12.0, 1e-6, "x shifted by the offset / x 随偏移平移")
	gpApprox(gpMovedPos.y - gpBasePos.y, -7.0, 1e-6, "y shifted by the offset / y 随偏移平移")


# The move command applies the offset, undoes to no-offset, and redoes it — one step each.
# 移动命令应用偏移、撤销回无偏移、再重做 —— 各为一个步。
func gpTestCommandMovesAndUndoes() -> void:
	var f: Array = _mkFixture()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	var e: GPPIDEdge = g.gpGetEdge("E1")
	gpEq(e.gpTagOffset(), Vector2.ZERO, "starts without an offset / 初始无偏移")
	var gpOff: Vector2 = Vector2(0.0, -18.0)
	gpCheck(st.gpDo(GPSetEdgeTagOffsetCommand.new("E1", gpOff), ctx), "move recorded / 移动被记录")
	gpApprox(e.gpTagOffset().y, -18.0, 1e-6, "offset applied / 已应用偏移")
	gpEq(st.gpUndoLabel(), "移动管线号", "undo label is honest / 撤销标签诚实")
	st.gpUndo(ctx)
	gpEq(e.gpTagOffset(), Vector2.ZERO, "undo restores no offset / 撤销恢复无偏移")
	st.gpRedo(ctx)
	gpApprox(e.gpTagOffset().y, -18.0, 1e-6, "redo reapplies the offset / 重做重新应用偏移")


# A command that changes nothing must not become a phantom undo step.
# 什么都没改的命令不得变成幽灵撤销步。
func gpTestCommandNoopNotRecorded() -> void:
	var f: Array = _mkFixture()
	var g: GPPIDGraph = f[0] as GPPIDGraph
	var ctx: GPCommandContext = f[1] as GPCommandContext
	var st: GPCommandStack = f[2] as GPCommandStack
	gpCheck(not st.gpDo(GPSetEdgeTagOffsetCommand.new("E1", Vector2.ZERO), ctx),
		"zero-offset move is refused / 零偏移移动被拒绝")
	gpEq(st.gpUndoDepth(), 0, "nothing recorded for a no-op / 无操作未记录任何内容")


# Source-shape guard: the painter must stroke the WHOLE polyline.
# 源码形状守卫：绘制器必须描画**整条**折线。
# A revert to `draw_line(leader[0], leader[1], ...)` would silently drop the horizontal shoulder
# and leave only the slant — a regression with no numeric signature at all, so it can only be
# pinned by reading the source text (same technique as the text-rasterisation guard).
# 若退回 `draw_line(leader[0], leader[1], ...)`，会静默丢掉水平肩线、只剩斜段 —— 这种回归完全没有
# 数值特征，只能靠读源码文本来钉住（与文字重光栅化守卫同一手法）。
func gpTestPainterStrokesWholePolyline() -> void:
	var gpSrc: String = FileAccess.get_file_as_string("res://src/render/edge_painter.gd")
	gpCheck(gpSrc.contains("draw_polyline(gpLeader"),
		"leader strokes the whole polyline / 引出线描画整条折线")
	gpCheck(not gpSrc.contains("draw_line(gpLeader"),
		"leader is not a bare 2-point line / 引出线不是两点直线")


# Integration: through the REAL wiring (GPEdgeView.gpTagGeometry -> the record the painter consumes),
# a dragged-away number must yield the full 3-point callout — not just the pure function in isolation.
# 集成：经**真实接线**（GPEdgeView.gpTagGeometry → 绘制器所消费的记录），被拖远的编号必须产出完整的
# 3 点引出标注 —— 而不只是孤立测试的纯函数。
func gpTestGeometryRecordCarriesThreePointLeader() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	var a: GPPIDNode = GPPIDNode.new()
	a.gpInstanceId = "A"; a.gpSymbolId = "PUMP"; a.gpPosition = Vector2(0, 0)
	var b: GPPIDNode = GPPIDNode.new()
	b.gpInstanceId = "B"; b.gpSymbolId = "PUMP"; b.gpPosition = Vector2(300, 0)
	g.gpAddNode(a); g.gpAddNode(b)
	# PROCESS (not SIGNAL), so the number is drawn by default / 工艺管线（非信号线），故默认绘制编号
	var e: GPPIDEdge = g.gpNewEdgeEx("e1", {"node_id": "A", "port_id": "out"},
		{"node_id": "B", "port_id": "in"}, GPPIDEdge.GP_PROCESS, "", "25-LC-10154")
	g.gpAddEdge(e)
	var def: GPSymbolDef = GPSymbolDef.new()
	def.gpId = "PUMP"
	def.gpPorts = [
		GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
	]
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	cv.gpBinder = GPGraphBinder.new()
	cv.gpBinder.gpDefs = [def]
	var ev: GPEdgeView = GPEdgeView.new()
	ev.gpInit(e, g, cv.gpDefLookupCallable())
	ev.gpZoom = 1.0
	# Drag the number far below its pipe, then read the record the painter consumes.
	# 把编号拖到其管线下方远处，再读取绘制器所消费的记录。
	e.gpSetTagOffset(Vector2(0.0, 30.0))
	var gpGeo: Dictionary = ev.gpTagGeometry()
	gpCheck(not gpGeo.is_empty(), "a process edge always has tag geometry / 工艺边恒有编号几何")
	var gpLeader: PackedVector2Array = gpGeo.get("leader", PackedVector2Array())
	gpEq(gpLeader.size(), 3, "record carries the 3-point callout / 记录携带 3 点引出标注")
	var gpBox: Rect2 = gpGeo.get("box", Rect2())
	gpCheck(gpLeader[1].y > gpBox.end.y, "shoulder sits below the tag box / 肩线位于编号包围盒下方")
	gpApprox(gpLeader[1].y, gpLeader[2].y, 1e-3, "shoulder is horizontal / 肩线水平")
	# The anchor must lie ON the routed pipe — checked against the routed polyline itself rather than
	# a hard-coded axis, so a change of routing convention cannot silently pass this.
	# 锚点必须落在**布线后的**管线上 —— 以该折线自身校验而非硬编某条轴，故布线约定改变时不会静默通过。
	gpApprox(GPEdgeTagLayout.gpNearestOnPolyline(ev.gpPolyline(), gpLeader[0]).distance_to(gpLeader[0]),
		0.0, 1e-3, "anchor lies on the routed pipe / 锚点落在布线后的管线上")
	ev.free()
	cv.free()


# Integration on a VERTICAL run — the case the two states have to be told apart in: while the
# number is attached it keeps the rotated column, and the moment it is dragged clear it is laid
# flat with the full callout. Checked through the REAL wiring (GPEdgeView.gpTagGeometry), because
# that is where a placement and a leader could drift apart again.
# **竖管**上的集成用例 —— 两种形态必须被区分开的正是这种情形：编号附着时保持竖排字列，一旦被
# 拖离即放平并带完整标注。经**真实接线**（GPEdgeView.gpTagGeometry）校验，因为那正是落位与引出线
# 可能再次脱节的地方。
func gpTestVerticalRunLaysFlatOnceDraggedClear() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	var a: GPPIDNode = GPPIDNode.new()
	a.gpInstanceId = "A"; a.gpSymbolId = "PUMP"; a.gpPosition = Vector2(0, 0)
	var b: GPPIDNode = GPPIDNode.new()
	b.gpInstanceId = "B"; b.gpSymbolId = "PUMP"; b.gpPosition = Vector2(0, 300)
	g.gpAddNode(a); g.gpAddNode(b)
	# Ports face down / up, so the routed run is vertical and the number is the rotated column.
	# 端口朝下 / 朝上，故布线为竖管，编号即竖排字列。
	var e: GPPIDEdge = g.gpNewEdgeEx("e1", {"node_id": "A", "port_id": "down"},
		{"node_id": "B", "port_id": "up"}, GPPIDEdge.GP_PROCESS, "", "25-LC-10154")
	g.gpAddEdge(e)
	var def: GPSymbolDef = GPSymbolDef.new()
	def.gpId = "PUMP"
	def.gpPorts = [
		GPPort.gpMake("down", Vector2(0.5, 1.0), Vector2(0.0, 1.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("up", Vector2(0.5, 0.0), Vector2(0.0, -1.0), GPPort.GP_NOZZLE),
	]
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	cv.gpBinder = GPGraphBinder.new()
	cv.gpBinder.gpDefs = [def]
	var ev: GPEdgeView = GPEdgeView.new()
	ev.gpInit(e, g, cv.gpDefLookupCallable())
	ev.gpZoom = 1.0
	# Attached: the column stands and needs no leader. / 附着：字列成立，无需引出线。
	var gpAttached: Dictionary = ev.gpTagGeometry()
	gpApprox(float(gpAttached.get("rot", 9.0)), -PI * 0.5, 0.001,
		"an attached number stays a column / 附着时保持竖排字列")
	gpCheck(not bool(gpAttached.get("flipped", false)), "and reports no flip / 且未翻转")
	gpEq((gpAttached.get("leader", PackedVector2Array()) as PackedVector2Array).size(), 0,
		"and no leader / 且无引出线")
	# Dragged clear, sideways off the pipe: laid flat, with the full 3-point callout.
	# 侧向拖离管线：放平，并带完整 3 点标注。
	e.gpSetTagOffset(Vector2(-30.0, 0.0))
	var gpFar: Dictionary = ev.gpTagGeometry()
	gpApprox(float(gpFar.get("rot", 9.0)), 0.0, 0.001, "it is laid flat / 已放平")
	gpCheck(bool(gpFar.get("flipped", false)), "the flip is reported / 已翻转被记录")
	var gpLeader: PackedVector2Array = gpFar.get("leader", PackedVector2Array())
	gpEq(gpLeader.size(), 3, "the 3-point callout is carried / 携带 3 点标注")
	gpApprox(gpLeader[1].y, gpLeader[2].y, 1e-3, "shelf is horizontal / 托线水平")
	gpApprox(GPEdgeTagLayout.gpNearestOnPolyline(ev.gpPolyline(), gpLeader[0]).distance_to(gpLeader[0]),
		0.0, 1e-3, "anchor lies on the routed pipe / 锚点落在布线后的管线上")
	ev.free()
	cv.free()


# Helper: drag the number to a target box centre the way a real drag does — nudge by the shortfall
# and re-read. One step is not enough: the move can change WHICH LEG is under the number, and that
# changes the standoff the box is laid at.
# 辅助：像真实拖拽那样把编号拖到目标包围盒中心 —— 按欠量微调并重读。一步不够：移动本身可能改变编号
# 底下是**哪一段**，而那会改变包围盒的落位净距。
func _gpDragTagTo(ev: GPEdgeView, gpTarget: Vector2) -> Dictionary:
	var gpGeo: Dictionary = ev.gpTagGeometry()
	for gpI in range(6):
		var gpC: Vector2 = (gpGeo.get("box", Rect2()) as Rect2).get_center()
		if gpC.distance_to(gpTarget) < 1e-4:
			break
		ev.gpEdge.gpSetTagOffset(ev.gpEdge.gpTagOffset() + (gpTarget - gpC))
		gpGeo = ev.gpTagGeometry()
	return gpGeo


# Integration through the REAL wiring on a pipe that TURNS A CORNER — the case the rule exists for.
# 拐角管线上经**真实接线**的集成用例 —— 规则存在的理由正在于此。
# A routed pipe carries one leg of each orientation, so "the number is still a column" can be right
# (it is over the vertical leg) or wrong (it was dragged onto the horizontal one). Which one it is
# can only be answered by the real GPEdgeView.gpTagGeometry — the pure function in isolation cannot
# tell us that the live call site passes the right switch.
# 布线后的管线同时带有一条竖直段与一条水平段，故「编号仍是字列」可能是对的（它压在竖直段上），也可能
# 是错的（它已被拖到水平段上）。孰是孰非，唯有真实的 GPEdgeView.gpTagGeometry 能回答 —— 孤立测试
# 那个纯函数，无法证明线上调用点传对了开关。
func gpTestTagFollowsTheLegThroughTheRealWiring() -> void:
	var g: GPPIDGraph = GPPIDGraph.new()
	var a: GPPIDNode = GPPIDNode.new()
	a.gpInstanceId = "A"; a.gpSymbolId = "PUMP"; a.gpPosition = Vector2(0, 0)
	# Offset diagonally AND far enough down that the VERTICAL leg — not the horizontal jog — is the
	# longest leg, so the number starts out as a column (which is where the report starts from).
	# 斜向错位，且下移足够远，使**竖直段**（而非水平段）成为最长段，于是编号初始为字列
	#（正是用户反馈的起点）。
	var b: GPPIDNode = GPPIDNode.new()
	b.gpInstanceId = "B"; b.gpSymbolId = "PUMP"; b.gpPosition = Vector2(100, 400)
	g.gpAddNode(a); g.gpAddNode(b)
	var e: GPPIDEdge = g.gpNewEdgeEx("e1", {"node_id": "A", "port_id": "out"},
		{"node_id": "B", "port_id": "in"}, GPPIDEdge.GP_PROCESS, "", "25-LC-10154")
	g.gpAddEdge(e)
	var def: GPSymbolDef = GPSymbolDef.new()
	def.gpId = "PUMP"
	def.gpPorts = [
		GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0), GPPort.GP_NOZZLE),
		GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE),
	]
	var cv: GPCanvas2D = GPCanvas2D.new()
	cv.gpGraph = g
	cv.gpBinder = GPGraphBinder.new()
	cv.gpBinder.gpDefs = [def]
	var ev: GPEdgeView = GPEdgeView.new()
	ev.gpInit(e, g, cv.gpDefLookupCallable())
	ev.gpZoom = 1.0
	var gpPts: PackedVector2Array = ev.gpPolyline()
	# Take the two legs from the routing ITSELF rather than assuming a routing convention.
	# 两条段取自**布线结果本身**，而非假定某种布线约定。
	var gpHoriz: int = -1
	var gpVert: int = -1
	var gpHorizLen: float = -1.0
	var gpVertLen: float = -1.0
	for gpI in range(gpPts.size() - 1):
		var gpD: Vector2 = gpPts[gpI + 1] - gpPts[gpI]
		if absf(gpD.x) >= absf(gpD.y):
			if gpD.length() > gpHorizLen:
				gpHorizLen = gpD.length()
				gpHoriz = gpI
		else:
			if gpD.length() > gpVertLen:
				gpVertLen = gpD.length()
				gpVert = gpI
	gpCheck(gpHoriz >= 0 and gpVert >= 0,
		"the routed run carries both a horizontal and a vertical leg / 布线同时含水平段与竖直段")
	gpEq(GPEdgeTagLayout.gpLongestSegment(gpPts), gpVert,
		"and the vertical leg is the longest one / 且最长段为竖直段")
	# As it comes: a column on that vertical leg. / 初始：该竖直段上的字列。
	var gpHome: Dictionary = ev.gpTagGeometry()
	gpCheck(not gpHome.is_empty(), "a process edge always has tag geometry / 工艺边恒有编号几何")
	gpApprox(float(gpHome.get("rot", 9.0)), -PI * 0.5, 0.001, "it starts as a column / 初始为字列")
	# Dragged onto the HORIZONTAL leg: it must read left-to-right.
	# 拖到**水平**段上：必须自左向右阅读。
	var gpH: float = (gpHome.get("size", Vector2.ZERO) as Vector2).y
	var gpLegMid: Vector2 = (gpPts[gpHoriz] + gpPts[gpHoriz + 1]) * 0.5
	var gpTarget: Vector2 = gpLegMid + Vector2(0.0, -(GPEdgeTagLayout.GP_GAP + gpH * 0.5))
	var gpOn: Dictionary = _gpDragTagTo(ev, gpTarget)
	gpApprox(float(gpOn.get("rot", 9.0)), 0.0, 0.001,
		"on the horizontal leg it reads left-to-right / 在水平段上自左向右阅读")
	gpApprox((gpOn.get("box", Rect2()) as Rect2).get_center().distance_to(gpTarget), 0.0, 1e-3,
		"the drag is honoured / 拖拽落点被尊重")
	gpCheck(not bool(gpOn.get("detached", true)), "it sits against that leg / 贴在该段上")
	gpEq((gpOn.get("leader", PackedVector2Array()) as PackedVector2Array).size(), 0,
		"so no leader is drawn / 故不画引出线")
	# The invariant still holds through the live wiring: a leader implies a flat number.
	# 该不变量在真实接线中同样成立：有引出线即横排。
	gpCheck(not (float(gpOn.get("rot", 0.0)) != 0.0
		and (gpOn.get("leader", PackedVector2Array()) as PackedVector2Array).size() > 0),
		"a number with a leader is never a column / 有引出线的编号绝不是字列")
	ev.free()
	cv.free()
