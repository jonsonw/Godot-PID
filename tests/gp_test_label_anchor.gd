class_name GpTestLabelAnchor
extends GPGTest
# Headless tests for the tag-label geometry and the offset command (M10b).
# 位号标签几何与偏移命令（M10b）的 headless 测试。
#
# Pinned behaviour: the canvas draws the TAG (not the type name), an offset is stored
# NORMALISED so it survives zoom / DPI / print, and it can never wander far enough from its
# own symbol to be misread as the neighbour's.
# 被钉住的行为：画布画的是**位号**（而非类型名），偏移以**归一化**方式存储以便
# 在缩放 / DPI / 打印后保持一致，且它绝不会离自己的图元远到被误读成邻居的。


func _gpDef(gpCat: String = "pump") -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "LPUMP003"
	gpD.gpDisplayName = "离心泵"
	gpD.gpCategory = gpCat
	gpD.gpDefaultSize = Vector2(80.0, 56.0)
	return gpD


func _gpNode(gpTag: String = "P-1001") -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "a1"
	gpN.gpSymbolId = "LPUMP003"
	gpN.gpTag = gpTag
	return gpN


# ---------------------------------------------------------------- text

func gpTestCanvasShowsTheTagNotTheTypeName() -> void:
	var gpN: GPPIDNode = _gpNode("P-1001")
	gpN.gpNames = {"zh_CN": "磨矿给料泵"}
	gpEq(GPLabelGripOps.gpLabelText(gpN, _gpDef()), "P-1001",
		"the tag is what the sheet shows, not the name")


func gpTestEmptyTagFallsBackToTheTypeName() -> void:
	var gpN: GPPIDNode = _gpNode("")
	gpEq(GPLabelGripOps.gpLabelText(gpN, _gpDef()), "离心泵",
		"an un-numbered instance falls back to the localized type name")
	var gpNoDef: GPPIDNode = _gpNode("")
	gpEq(GPLabelGripOps.gpLabelText(gpNoDef, null), "", "no def and no tag means no text")


func gpTestLabelFormatCanAddANameLine() -> void:
	var gpD: GPSymbolDef = _gpDef()
	gpD.gpLabelFormat = "{tag}\\n{name}"
	var gpN: GPPIDNode = _gpNode("P-1001")
	gpN.gpNames = {"zh_CN": "磨矿给料泵"}
	gpEq(GPLabelGripOps.gpLabelText(gpN, gpD), "P-1001\\n磨矿给料泵",
		"a project that wants two lines can have them")


# ---------------------------------------------------------------- anchors

func gpTestBelowIsTheDefaultAndMatchesTheHistoricLook() -> void:
	var gpN: GPPIDNode = _gpNode()
	var gpD: GPSymbolDef = _gpDef()
	gpEq(GPLabelGripOps.gpEffectiveAnchor(gpN, gpD), GPLabelAnchor.GPAnchor.GP_BELOW,
		"an unset instance anchor resolves to BELOW")
	# Historic look: half the height plus the gap below the glyph.
	# 历史外观：字形下方半个高度再加间距。
	gpApprox(GPLabelGripOps.gpLocalOffset(gpN, gpD).y, 56.0 * 0.5 + 7.0, 0.001,
		"BELOW sits under the envelope")
	gpApprox(GPLabelGripOps.gpLocalOffset(gpN, gpD).x, 0.0, 0.001, "BELOW is centred")


func gpTestInstanceAnchorBeatsTheTypeDefault() -> void:
	var gpD: GPSymbolDef = _gpDef()
	gpD.gpLabelAnchor = GPLabelAnchor.GPAnchor.GP_BELOW
	var gpN: GPPIDNode = _gpNode()
	gpN.gpLabelAnchor = GPLabelAnchor.GPAnchor.GP_ABOVE
	gpEq(GPLabelGripOps.gpEffectiveAnchor(gpN, gpD), GPLabelAnchor.GPAnchor.GP_ABOVE,
		"the instance wins")
	gpApprox(GPLabelGripOps.gpLocalOffset(gpN, gpD).y, -(56.0 * 0.5 + 7.0), 0.001,
		"ABOVE sits over the envelope")


func gpTestInsideIsCentred() -> void:
	var gpN: GPPIDNode = _gpNode()
	gpN.gpLabelAnchor = GPLabelAnchor.GPAnchor.GP_INSIDE
	gpApprox(GPLabelGripOps.gpLocalOffset(gpN, _gpDef()).length(), 0.0, 0.001,
		"INSIDE with no offset sits at the centre")


func gpTestLeftAndRightSitBesideTheEnvelope() -> void:
	var gpN: GPPIDNode = _gpNode()
	var gpD: GPSymbolDef = _gpDef()
	gpN.gpLabelAnchor = GPLabelAnchor.GPAnchor.GP_LEFT
	gpApprox(GPLabelGripOps.gpLocalOffset(gpN, gpD).x, -(80.0 * 0.5 + 7.0), 0.001,
		"LEFT sits off the left edge")
	gpN.gpLabelAnchor = GPLabelAnchor.GPAnchor.GP_RIGHT
	gpApprox(GPLabelGripOps.gpLocalOffset(gpN, gpD).x, 80.0 * 0.5 + 7.0, 0.001,
		"RIGHT sits off the right edge")


# ---------------------------------------------------------------- clamping

func gpTestOffsetIsClampedToOneAndAHalfHalfEnvelopes() -> void:
	var gpD: GPSymbolDef = _gpDef()
	var gpN: GPPIDNode = _gpNode()
	# 4.0 half-envelopes right / down would land on the neighbour's equipment.
	# 向右 / 向下 4.0 个半包络会落到隔壁设备上。
	gpEq(GPLabelAnchor.gpClamp(GPLabelAnchor.GPAnchor.GP_BELOW, Vector2(4.0, 4.0)),
		Vector2(GPLabelAnchor.GP_RANGE, GPLabelAnchor.GP_RANGE), "clamped to the range")
	gpEq(GPLabelAnchor.gpClamp(GPLabelAnchor.GPAnchor.GP_BELOW, Vector2(-4.0, -4.0)),
		Vector2(-GPLabelAnchor.GP_RANGE, -GPLabelAnchor.GP_RANGE), "clamped on the negative side too")


func gpTestInsideIsClampedTighter() -> void:
	gpEq(GPLabelAnchor.gpClamp(GPLabelAnchor.GPAnchor.GP_INSIDE, Vector2(1.2, 1.2)),
		Vector2(GPLabelAnchor.GP_INSIDE_RANGE, GPLabelAnchor.GP_INSIDE_RANGE),
		"INSIDE gets the tighter 0.9 limit")


func gpTestAWaywardOffsetCannotEscapeTheRange() -> void:
	var gpD: GPSymbolDef = _gpDef()
	var gpN: GPPIDNode = _gpNode()
	gpN.gpLabelOffset = Vector2(9.0, -9.0)
	var gpLocal: Vector2 = GPLabelGripOps.gpLocalOffset(gpN, gpD)
	var gpBase: Vector2 = Vector2(0.0, 56.0 * 0.5 + 7.0)
	gpApprox(gpLocal.x - gpBase.x, GPLabelAnchor.GP_RANGE * 80.0 * 0.5, 0.001,
		"x is capped at 1.5 half-widths")
	gpApprox(gpLocal.y - gpBase.y, -GPLabelAnchor.GP_RANGE * 56.0 * 0.5, 0.001,
		"y is capped at 1.5 half-heights")


func gpTestZeroIsALegalOffset() -> void:
	# Vector2.ZERO means "exactly on the anchor" — which is why "unset" needs its own sentinel.
	# Vector2.ZERO 意为「正好落在锚点上」——这正是「未设置」需要独立哨兵的原因。
	var gpD: GPSymbolDef = _gpDef()
	var gpN: GPPIDNode = _gpNode()
	gpN.gpLabelAnchor = GPLabelAnchor.GPAnchor.GP_INSIDE
	gpN.gpLabelOffset = Vector2.ZERO
	gpEq(GPPropertyResolver.gpIsOverridden({"label_offset": Vector2.ZERO}, "label_offset"), true,
		"an explicitly stored zero counts as an override")
	gpApprox(GPLabelGripOps.gpLocalOffset(gpN, gpD).length(), 0.0, 0.001,
		"a zero offset sits exactly on the anchor")


# ---------------------------------------------------------------- rotation / flip

func gpTestRotationCarriesTheLabelWithIt() -> void:
	var gpD: GPSymbolDef = _gpDef()
	var gpN: GPPIDNode = _gpNode()
	gpN.gpPosition = Vector2(100.0, 100.0)
	var gpBefore: Vector2 = GPLabelGripOps.gpWorldPos(gpN, gpD)
	gpN.gpRotationDeg = 90.0
	var gpAfter: Vector2 = GPLabelGripOps.gpWorldPos(gpN, gpD)
	# The anchor sits below the glyph; a quarter turn moves it to the LEFT of the centre.
	# 锚点在字形下方；转过四分之一圈后它移到中心的**左侧**。
	gpApprox(gpAfter.x, 100.0 - (56.0 * 0.5 + 7.0), 0.001, "a 90 degree turn moves the tag left")
	gpApprox(gpAfter.y, 100.0, 0.001, "and back onto the centre line")
	gpCheck(gpBefore != gpAfter, "the tag moved with its symbol")


func gpTestFlipMirrorsTheLabelSide() -> void:
	var gpD: GPSymbolDef = _gpDef()
	var gpN: GPPIDNode = _gpNode()
	gpN.gpPosition = Vector2(50.0, 50.0)
	gpN.gpLabelOffset = Vector2(1.0, 0.0)
	var gpUnflipped: Vector2 = GPLabelGripOps.gpWorldPos(gpN, gpD)
	gpN.gpFlipped = true
	var gpFlipped: Vector2 = GPLabelGripOps.gpWorldPos(gpN, gpD)
	gpApprox(gpFlipped.x, 100.0 - gpUnflipped.x, 0.001, "flipping mirrors the horizontal offset")


# ---------------------------------------------------------------- drag maths

func gpTestDragDeltaBecomesANormalisedOffset() -> void:
	var gpD: GPSymbolDef = _gpDef()
	var gpN: GPPIDNode = _gpNode()
	gpN.gpLabelOffset = Vector2.ZERO
	# 40px right = one half-width (80/2) = 1.0 normalised.
	# 向右 40px = 一个半宽（80/2）= 归一化 1.0。
	var gpOut: Vector2 = GPLabelGripOps.gpDragToOffset(gpN, gpD, Vector2(40.0, 0.0))
	gpApprox(gpOut.x, 1.0, 0.001, "40px on an 80px envelope is 1.0 normalised")


func gpTestDragIsUnRotatedBeforeScaling() -> void:
	var gpD: GPSymbolDef = _gpDef()
	var gpN: GPPIDNode = _gpNode()
	gpN.gpLabelOffset = Vector2.ZERO
	gpN.gpRotationDeg = 90.0
	# Dragging RIGHT on screen must move the tag right in the WORLD, even though the symbol's
	# own frame is turned a quarter circle. A quarter turn maps screen +x onto local -y, and
	# local y is scaled by the HALF-HEIGHT (56/2 = 28), so 28px right is -1.0 normalised.
	# 在屏幕上向**右**拖必须让标签在世界坐标中向右移动，即便图形自身坐标系已转过四分之一圈。
	# 四分之一圈把屏幕 +x 映射到本地 -y，而本地 y 按**半高**（56/2 = 28）缩放，
	# 故向右 28px 即归一化 -1.0。
	var gpOut: Vector2 = GPLabelGripOps.gpDragToOffset(gpN, gpD, Vector2(28.0, 0.0))
	gpApprox(gpOut.y, -1.0, 0.001, "the screen-right drag became a local -y offset")
	gpApprox(gpOut.x, 0.0, 0.001, "and left the local x alone")


func gpTestDragIsClampedToo() -> void:
	var gpD: GPSymbolDef = _gpDef()
	var gpN: GPPIDNode = _gpNode()
	gpN.gpLabelOffset = Vector2.ZERO
	var gpOut: Vector2 = GPLabelGripOps.gpDragToOffset(gpN, gpD, Vector2(4000.0, 4000.0))
	gpEq(gpOut, Vector2(GPLabelAnchor.GP_RANGE, GPLabelAnchor.GP_RANGE),
		"a wild drag cannot leave the allowed range")


# ---------------------------------------------------------------- alignment / origin

func gpTestAlignmentFollowsTheAnchor() -> void:
	gpEq(GPLabelGripOps.gpAlignFor(GPLabelAnchor.GPAnchor.GP_LEFT),
		HORIZONTAL_ALIGNMENT_RIGHT, "a left-hand tag is right-aligned")
	gpEq(GPLabelGripOps.gpAlignFor(GPLabelAnchor.GPAnchor.GP_RIGHT),
		HORIZONTAL_ALIGNMENT_LEFT, "a right-hand tag is left-aligned")
	gpEq(GPLabelGripOps.gpAlignFor(GPLabelAnchor.GPAnchor.GP_BELOW),
		HORIZONTAL_ALIGNMENT_CENTER, "a tag below the glyph is centred")


func gpTestTextOriginCentresByDefault() -> void:
	var gpO: Vector2 = GPLabelGripOps.gpTextOrigin(
		GPLabelAnchor.GPAnchor.GP_BELOW, Vector2.ZERO, Vector2(40.0, 12.0))
	gpEq(gpO, Vector2(-20.0, -6.0), "centred horizontally and vertically")


func gpTestGripHitTest() -> void:
	var gpD: GPSymbolDef = _gpDef()
	var gpN: GPPIDNode = _gpNode()
	gpN.gpPosition = Vector2(200.0, 200.0)
	var gpAt: Vector2 = GPLabelGripOps.gpWorldPos(gpN, gpD)
	gpEq(GPLabelGripOps.gpHitGrip(gpAt, gpN, gpD, 6.0), true, "the grip is hit where it is drawn")
	gpEq(GPLabelGripOps.gpHitGrip(gpAt + Vector2(100.0, 0.0), gpN, gpD, 6.0), false,
		"and missed far away")


# ---------------------------------------------------------------- command

func gpTestSetLabelOffsetIsOneUndoStep() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("a1", "LPUMP003", "P-1001"))
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new())
	gpEq(gpSvc.gpSetLabelOffset("a1", Vector2(0.5, -0.25)), true, "the offset was applied")
	gpEq(gpG.gpGetNode("a1").gpLabelOffset, Vector2(0.5, -0.25), "the node carries it")
	gpEq(gpSvc.gpUndo(), true, "undo is available")
	gpEq(gpG.gpGetNode("a1").gpLabelOffset, GPLabelAnchor.GP_OFFSET_UNSET,
		"undo restores the unset sentinel")
	gpEq(gpSvc.gpRedo(), true, "redo is available")
	gpEq(gpG.gpGetNode("a1").gpLabelOffset, Vector2(0.5, -0.25), "redo re-applies it")


func gpTestApplyingTheSameOffsetTwiceMakesOneUndoStep() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("a1", "LPUMP003", "P-1001"))
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new())
	gpSvc.gpSetLabelOffset("a1", Vector2(0.5, 0.0))
	gpEq(gpSvc.gpSetLabelOffset("a1", Vector2(0.5, 0.0)), false,
		"a no-op edit is refused, so no phantom undo step")
	gpEq(gpSvc.gpUndo(), true, "the single real step is still undoable")


func gpTestResetUsesTheUnsetSentinel() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("a1", "LPUMP003", "P-1001"))
	gpG.gpGetNode("a1").gpLabelOffset = Vector2(1.0, 1.0)
	# Reset means "follow the type layer again": the sentinel must not reach the file.
	# 复位意为「重新跟随类型层」：哨兵绝不能进入文件。
	var gpD: Dictionary = gpG.gpGetNode("a1").gpToDict()
	gpCheck(gpD.has("label_offset"), "a real offset is serialised")
	gpG.gpGetNode("a1").gpLabelOffset = GPLabelAnchor.GP_OFFSET_UNSET
	gpEq(gpG.gpGetNode("a1").gpToDict().has("label_offset"), false,
		"the unset sentinel is NOT serialised (INF has no JSON form)")


func gpTestOffsetSurvivesASaveLoadRoundTrip() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("a1", "LPUMP003", "P-1001"))
	gpG.gpGetNode("a1").gpLabelOffset = Vector2(0.75, -0.5)
	gpG.gpGetNode("a1").gpLabelAnchor = GPLabelAnchor.GPAnchor.GP_ABOVE
	var gpBack: GPPIDGraph = GPPIDGraph.gpFromDict(gpG.gpToDict())
	gpEq(gpBack.gpGetNode("a1").gpLabelOffset, Vector2(0.75, -0.5), "the offset survives")
	gpEq(gpBack.gpGetNode("a1").gpLabelAnchor, GPLabelAnchor.GPAnchor.GP_ABOVE,
		"the anchor survives")


# ---------------------------------------------------------------- quarter turns (P5 follow-up)

# A nozzle standing on a vessel top must lay its two texts SIDE BY SIDE while the same nozzle on a
# vessel side stacks them. Turning the ANCHOR (never the text) is how the text stays upright while
# moving to the correct side, so the four sides are pinned in both directions here.
# 立在罐顶的管嘴要让两段文字**左右并排**，而同一管嘴装在罐侧则上下堆叠。旋转**锚点**（绝不旋
# 转文字）正是「文字保持正立、位置却落到正确一侧」的做法，故此处双向钉住四个侧面。
func gpTestRotateAnchorTurnsTheSidesClockwiseAndIsReversible() -> void:
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_ABOVE, 1),
		GPLabelAnchor.GPAnchor.GP_RIGHT, "one turn sends ABOVE to RIGHT")
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_RIGHT, 1),
		GPLabelAnchor.GPAnchor.GP_BELOW, "RIGHT becomes BELOW")
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_BELOW, 1),
		GPLabelAnchor.GPAnchor.GP_LEFT, "BELOW becomes LEFT")
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_LEFT, 1),
		GPLabelAnchor.GPAnchor.GP_ABOVE, "LEFT becomes ABOVE")
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_ABOVE, -1),
		GPLabelAnchor.GPAnchor.GP_LEFT,
		"one turn the other way sends ABOVE to LEFT — the direction a riser needs")
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_BELOW, -1),
		GPLabelAnchor.GPAnchor.GP_RIGHT, "and BELOW to RIGHT")
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_ABOVE, 4),
		GPLabelAnchor.GPAnchor.GP_ABOVE, "four turns are the identity")
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_ABOVE, -3),
		GPLabelAnchor.GPAnchor.GP_RIGHT, "a negative count wraps")
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_ABOVE, 0),
		GPLabelAnchor.GPAnchor.GP_ABOVE, "no turn changes nothing")
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_INSIDE, -1),
		GPLabelAnchor.GPAnchor.GP_INSIDE, "INSIDE has no side to turn to, so it passes through")
	gpEq(GPLabelAnchor.gpRotateAnchor(GPLabelAnchor.GPAnchor.GP_AUTO, 3),
		GPLabelAnchor.GPAnchor.GP_AUTO, "AUTO has no side to turn to either")


# The gap is an UPPER BOUND: a full-size symbol keeps the historic 7 mm exactly, while a 4x2 nozzle
# takes half its shorter side. 7 mm on a 4 mm-long part put the number four nozzle lengths away —
# the reported "the text sits far too far".
# 间距是**上限**：满尺寸图元精确保持历史的 7mm，而 4x2 的管嘴取短边的一半。7mm 加在 4mm 长的
# 部件上会把编号推到一个管嘴长度的四倍之外 —— 即用户报告的「文字离得太远」。
func gpTestTheGapNeverDominatesATinySymbolButNeverGrows() -> void:
	gpApprox(GPLabelGripOps.gpGapFor(Vector2(80.0, 56.0)), GPLabelGripOps.GP_GAP, 0.0001,
		"a full-size symbol keeps the historic 7 mm gap")
	gpApprox(GPLabelGripOps.gpGapFor(Vector2(10.5, 10.5)), GPLabelGripOps.GP_GAP, 0.0001,
		"a 10.5 mm pump still gets 7 mm, so nothing already drawn moves")
	gpApprox(GPLabelGripOps.gpGapFor(Vector2(4.0, 2.0)), 1.0, 0.0001,
		"a 4x2 nozzle takes half its shorter side (1 mm) rather than 7 mm")
	gpApprox(GPLabelGripOps.gpGapFor(Vector2(1.0, 1.0)), GPLabelGripOps.GP_MIN_GAP, 0.0001,
		"the clamp has a floor, so the text never lands on the glyph itself")
	# The historic look for a full-size symbol is unchanged — pinned against the gap function, not
	# against a copy of its formula, so the two cannot drift together.
	# 满尺寸图元的历史外观不变 —— 该钉子比对的是间距函数本身而非其公式副本，故两者无法一起漂移。
	gpApprox(GPLabelGripOps.gpLocalOffset(_gpNode(), _gpDef()).y,
		56.0 * 0.5 + GPLabelGripOps.gpGapFor(Vector2(80.0, 56.0)), 0.001,
		"BELOW still sits half the height plus the (unchanged) gap under the envelope")


# The slot text height never exceeds the symbol's SHORTER side: a 4x2 mm nozzle annotated at the
# 3 mm in-line tier carried text 1.5x its own height (the reported "the text is too big").
# 槽位字高绝不高于图元**较短边**：4x2mm 的管嘴按 3mm 在管档标注时字高是自身的 1.5 倍
#（即用户报告的「文字偏大」）。
func gpTestASlotTextIsNeverTallerThanItsSymbol() -> void:
	gpApprox(GPTextRole.gpSlotMM("", 3.0, Vector2(4.0, 2.0)), 2.0, 0.0001,
		"a 4x2 nozzle clamps the 3 mm tier down to its 2 mm height")
	gpApprox(GPTextRole.gpSlotMM("", 3.0, Vector2(10.5, 10.5)), 3.0, 0.0001,
		"a full-size symbol keeps the tier untouched")
	gpApprox(GPTextRole.gpSlotMM("equipment", 3.0, Vector2(10.5, 10.5)), 4.5, 0.0001,
		"the equipment tier still scales up on a big symbol")
