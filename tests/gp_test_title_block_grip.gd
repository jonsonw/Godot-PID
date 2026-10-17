extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
# Title-block docking behaviour (Rev.3 stage 1) — grab / drag / re-anchor / snap / undo — headless.
# 图签停靠行为（Rev.3 阶段 1）—— 抓取 / 拖拽 / 重判锚角 / 吸附 / 撤销 —— headless。
#
# The failure modes being guarded against:
# 所防范的失效模式：
# 1. A drag over the centre line flips the anchor but the OFFSET keeps the old edge's meaning, so the
#    block teleports. The re-anchor -> invert -> snap -> clamp pipeline is pinned via the LIVE sheet.
#    越过中线的拖拽翻转锚角、而偏移仍带着旧边的语义，图签于是瞬移。重判 → 反推 → 吸附 → 钳制的管线
#    经**实时图纸**钉住。
# 2. One gesture records many undo steps, or Ctrl+Z stops at an anchor/offset half-state the user never
#    saw — because the two fields travelled in separate commands.
#    一个手势记下许多撤销步，或 Ctrl+Z 停在用户从未见过的「只有锚角 / 只有偏移」的半态 —— 那是两个字段
#    分乘两条命令的结果。
# 3. On a frame narrower than the block the dragged block VANISHES (the pre-stage-1 renderer's silent
#    return). The clamp must keep a VALID rectangle on screen.
#    在比图签窄的内框上，被拖的图签**凭空消失**（阶段 1 之前渲染器的静默 return）。钳制必须让一个
#    **有效**矩形留在屏幕上。
# 4. The snap tolerance is computed in millimetres instead of pixels-per-zoom, so the feel dies at any
#    zoom other than 100%.
#    吸附容差按毫米而非「像素除以缩放」计算，于是除 100% 外的任何缩放下手感尽失。
#
# The pure docking arithmetic lives in gp_test_frame_geometry.gd; this suite drives the BEHAVIOUR on
# top of it, through the same off-tree canvas fixture the frame-drag suite uses.
# 纯停靠算术钉在 gp_test_frame_geometry.gd；本套件驱动其上的**行为**，夹具与图框拖拽套件相同的
# 树外画布。


# A fresh A3 sheet + an off-tree canvas bound to it + the grip delegate. Off-tree is deliberate: it is
# the cheaper fixture, and it also proves every port this feature needs is null-safe outside the tree.
# 全新 A3 图纸 + 绑定了它的树外画布 + 图签抓取委托。刻意树外：夹更廉价，且顺带证明本功能所需的每个
# 端口在树外都是空安全的。
func _gpFixture() -> Array:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	# ⚠️ A1 REBASE (2026-10-16): gpNew() now starts on A1; every coordinate below was computed
	# against the A3-era paper, so the fixture pins A3 explicitly (inputs, not defaults under test).
	# ⚠️ A1 重定基（2026-10-16）：gpNew() 现以 A1 起步；下方每个坐标都按 A3 时代纸幅算出，故夹具
	# 显式钉回 A3（输入，而非被测的默认值）。
	gpS.gpWidthMM = 420.0
	gpS.gpHeightMM = 297.0
	gpS.gpSetFrameMargins(GPSheet.GP_FRAME_MARGINS_DEFAULT)
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCv.gpSheet = gpS
	# Pin the zoom so the snap tolerance is a known number (GP_SNAP_PX / 1.0).
	# 钉住缩放，使吸附容差是一个已知数（GP_SNAP_PX / 1.0）。
	gpCv.gpViewZoom = 1.0
	var gpGrip: GPTitleBlockGripOps = GPTitleBlockGripOps.new(gpCv)
	var gpOut: Array = [gpCv, gpS, gpGrip]
	return gpOut


# The inner frame rectangle of a sheet. / 图纸的内框矩形。
func _gpFrame(gpS: GPSheet) -> Rect2:
	return GPFrameGeometry.gpFrameRect(gpS)


# The block rectangle, straight from the geometry layer. / 图签矩形，直接取自几何层。
func _gpBlock(gpS: GPSheet) -> Rect2:
	return GPFrameGeometry.gpTitleBlockRect(gpS)


# The docking pair as [anchor, offset] for compact assertions. / 以 [锚角, 偏移] 取停靠对，便于书写断言。
func _gpPair(gpS: GPSheet) -> Array:
	return [gpS.gpTbAnchor, gpS.gpTbOffset]


# Press on the CURRENT block's centre, move to [gpWorld], release — one full gesture. Returns the
# commit result so tests can assert on it.
# 在**当前**图签中心按下、移到 [gpWorld]、释放 —— 一个完整手势。返回提交结果供断言。
func _gpDragTo(gpCv: GPCanvas2D, gpGrip: GPTitleBlockGripOps, gpWorld: Vector2) -> bool:
	var gpBlock: Rect2 = _gpBlock(gpCv.gpSheet)
	gpCheck(gpGrip.gpTryStart(gpBlock.get_center()), "探针：按下应落在图签上（夹具自检）")
	gpGrip.gpOnGripMove(gpWorld)
	gpGrip.gpEndGripDrag()
	return true


# ===========================================================================
# 1. Grab gate / 抓取闸门
# ===========================================================================

# The block shares the frame's gate: with the frame switched off nothing is drawn where the block
# would be, and an invisible grab target is worse than none.
# 图签共用图框的闸门：图框关闭时图签所在之处什么都不画，而一个隐形的抓取目标比没有更糟。
func gpTestBlockIsGrabbableOnlyWhenItIsDrawn() -> void:
	var gpF: Array = _gpFixture()
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPTitleBlockGripOps = gpF[2]
	var gpCentre: Vector2 = _gpBlock(gpS).get_center()
	gpCheck(gpGrip.gpCanGrab(), "有图纸且图框打开时可抓")
	gpS.gpFrameOn = false
	gpEq(gpGrip.gpCanGrab(), false, "图框关闭时不可抓")
	gpEq(gpGrip.gpTryStart(gpCentre), false, "图框关闭时按下不得开始拖拽")
	gpEq(gpGrip.gpUpdateHoverCursor(gpCentre), false, "图框关闭时不得消费悬停")
	gpS.gpFrameOn = true
	gpEq(gpGrip.gpCanGrab(), true, "重新打开图框后恢复可抓")
	var gpNoSheet: GPCanvas2D = GPCanvas2D.new()
	var gpBare: GPTitleBlockGripOps = GPTitleBlockGripOps.new(gpNoSheet)
	gpEq(gpBare.gpCanGrab(), false, "无图纸时不可抓")
	gpNoSheet.free()
	(gpF[0] as GPCanvas2D).free()


# A press OUTSIDE the block must never start a drag — the block owns exactly its own extent, no more.
# 图签**之外**的按下绝不得开始拖拽 —— 图签只拥有它自身的范围，一分不多。
func gpTestPressOutsideTheBlockNeverGrabs() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPTitleBlockGripOps = gpF[2]
	var gpB: Rect2 = _gpBlock(gpS)
	# Well clear of the block, but still inside the frame — proving the block does not swallow the
	# drawing area the way a frame BAND would if it were an area target.
	# 远离图签、但仍在内框内 —— 证明图签不会像「面积目标化的图框带」那样吞掉绘图区。
	var gpInsides: Array = [
		gpB.position + Vector2(-60.0, -60.0),
		gpB.position + Vector2(-10.0, -10.0),
		gpB.end + Vector2(10.0, -10.0),
		Vector2(120.0, 60.0),
	]
	for gpP in gpInsides:
		gpEq(gpGrip.gpTryStart(gpP as Vector2), false, "图签外 %s 按下不得抓图签" % str(gpP))
		gpEq(gpGrip.gpIsDragging(), false, "图签外按下后不得处于拖拽态")
	# A press on the outline itself DOES grab — the outline is part of the object. The probe point sits
	# 1 mm INSIDE the right edge, because Rect2.has_point excludes the right / bottom boundary lines.
	# 按在轮廓线上**会**抓到 —— 轮廓是对象的一部分。探针点取右缘**内** 1mm，因 Rect2.has_point 不含
	# 右 / 下两条边界线。
	gpEq(gpGrip.gpTryStart(Vector2(gpB.end.x - 1.0, gpB.get_center().y)), true, "按在图签右缘内应开始拖拽")
	gpGrip.gpCancelDrag()
	gpCv.free()


# A plain click (press + release, no motion) must leave NO undo step and NO changed pair — the same
# "clicking is not editing" guarantee the frame drag already gives.
# 单纯点击（按下 + 释放、无移动）不得留下撤销步、也不得改动停靠对 —— 与图框拖拽相同的「点击不是编辑」
# 保证。
func gpTestPlainClickRecordsNothing() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPTitleBlockGripOps = gpF[2]
	var gpBefore: Array = _gpPair(gpS)
	gpCheck(gpGrip.gpTryStart(_gpBlock(gpS).get_center()), "按下应抓到图签")
	gpGrip.gpEndGripDrag()
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "无移动的按下 + 释放不得产生撤销步")
	gpCheck(_gpPair(gpS)[0] == gpBefore[0] and (_gpPair(gpS)[1] as Vector2).is_equal_approx(gpBefore[1]),
		"无移动的点击不得改动停靠对")
	gpEq(gpGrip.gpIsDragging(), false, "释放后不得仍处于拖拽态")
	gpCv.free()


# ===========================================================================
# 2. One gesture, four corners / 一次手势，四个角
# ===========================================================================

# Dragging the block over the frame's centre line hands it to the other side; the flush corner is the
# zero offset. All four corners from the DEFAULT pair, so the re-anchor -> invert -> snap -> clamp
# pipeline is exercised against the live sheet every time.
# 把图签拖过内框中线即交给另一侧；贴角即零偏移。四角全部自**默认**停靠对出发，使重判 → 反推 → 吸附 →
# 钳制管线每次都在实时图纸上有据可查。
func gpTestDragReachesAllFourCorners() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPTitleBlockGripOps = gpF[2]
	var gpFrame: Rect2 = _gpFrame(gpS)
	var gpG: Vector2 = Vector2(GPSheet.GP_TB_BLOCK_W, GPSheet.GP_TB_BLOCK_H) / 2.0
	# Top-left with a NON-zero offset — proving a non-default anchor still measures the offset from
	# ITS OWN corner into the frame. (An earlier draft expected flush everywhere and would never have
	# caught a sign flip that only shows on the left/top anchors.)
	# 左上 + **非零**偏移 —— 证明非默认锚角下偏移仍自**它自己的**角向框内量。（本用例初版处处期望贴角，
	# 那样就永远抓不到只在左 / 上锚角上现形的符号翻转。）
	_gpDragTo(gpCv, gpGrip, gpFrame.position + gpG + Vector2(30.0, 20.0))
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_TOP_LEFT, "拖到左上象限应重判为左上锚角")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2(30.0, 20.0)),
		"左上锚角下偏移应自左上角向框内量 (30, 20)")
	# Top-right, flush. NOTE the target world: the helper always presses the CURRENT block's centre,
	# so grabDelta is constant at (block/2) and the world that lands the block flush at a corner is
	# targetPos + gpG — NOT "the corner point" itself.
	# 右上，贴角。注意目标世界坐标：助手总按**当前**图签的中心，故抓取位移恒为 (图签/2)，把图签送到
	# 某角贴齐的世界坐标是 targetPos + gpG —— 而不是「那个角点」本身。
	_gpDragTo(gpCv, gpGrip,
		Vector2(gpFrame.end.x - GPSheet.GP_TB_BLOCK_W, gpFrame.position.y) + gpG)
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_TOP_RIGHT, "拖回右上象限应重判为右上锚角")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO), "贴右上角时偏移应为零")
	# Bottom-left, flush against the bottom edge. ⚠️ THE OFFSET IS ZERO HERE, NOT "THE LEFTOVER SPAN":
	# the offset measures the distance from the ANCHOR corner INTO the frame, so flush-bottom IS zero —
	# an offset of (0, 237) under BL would place the block flush against the TOP edge instead. The
	# probe run that corrected this draft is exactly the kind of inverted expectation a review must
	# catch: both the code and the test can agree on the WRONG meaning if the test was written from
	# the same misreading.
	# 左下，贴住下缘。⚠️ 此处偏移是**零**、不是「剩余跨度」：偏移量的是自**锚角**向框内的距离，故贴底
	# 就是零 —— 左下锚角下 (0, 237) 的偏移反而会把图签放到贴住**上**缘的位置。纠正本用例初版的那次探针，
	# 正是评审必须抓住的那类「期望值反了」：若测试与实现出自同一误读，两者会在**错误**的语义上达成一致。
	var gpWantY: float = gpFrame.size.y - GPSheet.GP_TB_BLOCK_H
	_gpDragTo(gpCv, gpGrip, Vector2(gpFrame.position.x, gpFrame.end.y) + Vector2(gpG.x, -gpG.y))
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_BOTTOM_LEFT, "拖到左下象限应重判为左下锚角")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO),
		"左下贴底时距锚角的偏移应为零（跨度 %s 是钳制上限、不是贴底的值）" % str(gpWantY))
	# Back to bottom-right: the default pair again — one gesture round-trips the whole frame.
	# 拖回右下：再次得到默认停靠对 —— 一次手势在整个内框上走了个来回。
	_gpDragTo(gpCv, gpGrip, gpFrame.end - gpG)
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, "拖回右下象限应重判为右下锚角")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO), "回到右下贴角时偏移应为零")
	gpCv.free()


# Every motion RE-DERIVES the pair from the pointer and an immutable grab delta — so the same pointer
# position always produces the same pair, no matter how wild the path to it was. This is what kills
# accumulation drift by construction.
# 每次移动都**由指针与不可变抓取位移重新推导**停靠对 —— 故同一指针位置恒产出同一停靠对，与到达它的
# 路径多么狂野无关。这正是「从构造上杀死累积漂移」的原因。
func gpTestMotionReplaysFromThePointerSoNoDrift() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPTitleBlockGripOps = gpF[2]
	var gpFrame: Rect2 = _gpFrame(gpS)
	var gpG: Vector2 = Vector2(GPSheet.GP_TB_BLOCK_W, GPSheet.GP_TB_BLOCK_H) / 2.0
	var gpWorld: Vector2 = gpFrame.position + gpG
	gpCheck(gpGrip.gpTryStart(_gpBlock(gpS).get_center()), "按下应抓到图签")
	# A wandering path... / 一条绕远的路径……
	gpGrip.gpOnGripMove(gpFrame.end)
	gpGrip.gpOnGripMove(gpFrame.get_center())
	gpGrip.gpOnGripMove(gpFrame.end - gpG)
	gpGrip.gpOnGripMove(gpWorld)
	var gpFirst: Array = _gpPair(gpS)
	# ...then the SAME position, again and again. / ……再在同一位置反复移动。
	gpGrip.gpOnGripMove(gpWorld)
	gpGrip.gpOnGripMove(gpWorld)
	gpCheck(_gpPair(gpS)[0] == gpFirst[0] and (_gpPair(gpS)[1] as Vector2).is_equal_approx(gpFirst[1]),
		"同一指针位置反复移动必须产出同一停靠对（无累积漂移）")
	# And it equals the DIRECT derivation, proving no history leaks into the result.
	# 且它等于**直接**推导的结果，证明没有历史泄漏进结果。
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_TOP_LEFT, "落点在左上象限应重判为左上")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO), "贴角落点偏移应为零")
	gpGrip.gpCancelDrag()
	gpCv.free()


# ===========================================================================
# 3. Feel: snap + clamp / 手感：吸附与钳制
# ===========================================================================

# An offset that lands within the snap tolerance of an inner edge folds to zero — 「the block has
# arrived at the edge」. The tolerance is GP_SNAP_PX / zoom in world mm (pinned at zoom 1.0 here).
# 落在容差内的偏移收为零 —— 「图签已到达边上」。容差 = GP_SNAP_PX / 缩放（世界毫米；此处钉在缩放 1.0）。
func gpTestSnapArrivesAtTheInnerEdge() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPTitleBlockGripOps = gpF[2]
	var gpFrame: Rect2 = _gpFrame(gpS)
	# Start from the default BR pair; grab the centre (offset from the block corner is (90, 25)).
	# 自默认右下对出发；抓中心（相对图签左上角的抓取位移为 (90, 25)）。
	var gpG: Vector2 = Vector2(GPSheet.GP_TB_BLOCK_W, GPSheet.GP_TB_BLOCK_H) / 2.0
	# Pointer chosen so the un-snapped offset is (3, 0) — inside the 12 mm tolerance on x.
	# 指针位置使未吸附偏移为 (3, 0) —— 落在 x 向 12mm 容差内。
	var gpWorld: Vector2 = Vector2(gpFrame.end.x - GPSheet.GP_TB_BLOCK_W - 3.0, gpFrame.end.y - GPSheet.GP_TB_BLOCK_H) + gpG
	gpCheck(gpGrip.gpTryStart(_gpBlock(gpS).get_center()), "按下应抓到图签")
	gpGrip.gpOnGripMove(gpWorld)
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, "落点仍在右下象限")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO),
		"3mm 的残距应被吸附为零（容差 12mm）")
	# Just beyond the tolerance: the residual stays — snap must not eat real positions.
	# 刚好超出容差：残距保留 —— 吸附不得吞掉真实位置。
	var gpFar: Vector2 = Vector2(gpFrame.end.x - GPSheet.GP_TB_BLOCK_W - 20.0, gpFrame.end.y - GPSheet.GP_TB_BLOCK_H) + gpG
	gpGrip.gpOnGripMove(gpFar)
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2(20.0, 0.0)),
		"超出容差的 20mm 残距不得被吸附改动")
	gpGrip.gpCancelDrag()
	gpCv.free()


# On a frame NARROWER than the block the clamp collapses the offset to zero: the block hugs its edge
# and overflows the far side — still a VALID rectangle on screen, never a vanished one (Rev.3 §9-①).
# 在比图签**窄**的内框上，钳制把偏移塌缩为零：图签贴边、向另一侧溢出 —— 屏幕上仍是**有效**矩形，绝不
# 凭空消失（Rev.3 §9-①）。
func gpTestClampKeepsTheBlockVisibleOnANarrowFrame() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPTitleBlockGripOps = gpF[2]
	# A3 is 420 wide: margins 150 + 150 leave a 120 mm frame — 15 mm short of the (2026-10-16
	# narrowed) 135 mm block. / A3 宽 420：左右各 150mm 边距留出 120mm 内框 —— 比收窄后的
	# 135mm 图签还短 15mm。
	gpS.gpSetFrameMargins([150.0, 5.0, 150.0, 5.0])
	gpS.gpSetTbPlacement(GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2.ZERO)
	var gpFrame: Rect2 = _gpFrame(gpS)
	gpCheck(gpFrame.size.x < GPSheet.GP_TB_BLOCK_W, "夹具自检：内框应窄于图签")
	# The drag: pointer shoved hard past the right edge — the raw offset goes negative, the clamp
	# must fold it to zero rather than let the block leave the frame.
	# 拖拽：指针被狠狠推过右缘 —— 原始偏移变负，钳制必须把它收为零、而不是让图签离开图框。
	var gpG: Vector2 = Vector2(GPSheet.GP_TB_BLOCK_W, GPSheet.GP_TB_BLOCK_H) / 2.0
	gpCheck(gpGrip.gpTryStart(_gpBlock(gpS).get_center()), "按下应抓到图签")
	gpGrip.gpOnGripMove(Vector2(gpFrame.end.x + 80.0, gpFrame.end.y - gpG.y))
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, "落点在右下象限")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO), "窄框上的越界偏移应被钳制为零")
	# THE POINT of the whole test: the placed block is still a full-size, on-frame rectangle.
	# 整个用例的**重点**：落位后的图签仍是全尺寸、在框上的矩形。
	var gpPlaced: Rect2 = GPFrameGeometry.gpTitleBlockPlaced(gpFrame, gpS)
	gpCheck(gpPlaced.size == Vector2(GPSheet.GP_TB_BLOCK_W, GPSheet.GP_TB_BLOCK_H),
		"窄框下图签矩形尺寸必须完整（可见，而非消失）")
	gpApprox(gpPlaced.end.x, gpFrame.end.x, 0.0001, "图签右缘应贴住内框右缘（贴锚边而溢出对侧）")
	# Cancel, so the fixture's mutation does not leak into any later assertion.
	# 取消，使夹具的改动不泄漏进后续断言。
	gpGrip.gpCancelDrag()
	gpCv.free()


# ===========================================================================
# 4. Commit, undo, cancel / 提交、撤销、取消
# ===========================================================================

# One gesture = ONE undo step, and Ctrl+Z rewinds BOTH fields together — never the "anchor flipped,
# offset stayed" half-state two separate commands would produce.
# 一个手势 = **一个**撤销步，且 Ctrl+Z 把**两个字段一起**回退 —— 绝不产生「锚角翻了、偏移没跟」的半态
# （那正是分乘两条命令的产物）。
func gpTestReleaseIsOneUndoStepAndUndoRewindsBothFields() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPTitleBlockGripOps = gpF[2]
	var gpFrame: Rect2 = _gpFrame(gpS)
	var gpG: Vector2 = Vector2(GPSheet.GP_TB_BLOCK_W, GPSheet.GP_TB_BLOCK_H) / 2.0
	# Give the start pair a NON-default offset, so undo rewinding it is observable.
	# 给起始对一个**非默认**偏移，使撤销的回退可被观察到。
	gpS.gpSetTbPlacement(GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, Vector2(40.0, 17.0))
	# Many motions, one release. / 多次移动、一次释放。
	gpCheck(gpGrip.gpTryStart(_gpBlock(gpS).get_center()), "按下应抓到图签")
	gpGrip.gpOnGripMove(gpFrame.get_center())
	gpGrip.gpOnGripMove(gpFrame.position + gpG)
	gpGrip.gpEndGripDrag()
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 1, "多次移动 + 一次释放 = 一个撤销步")
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_TOP_LEFT, "提交后锚角应为左上")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO), "提交后偏移应为零")
	# Undo: BOTH fields back, exactly. / 撤销：两个字段精确回退。
	gpCv.gpUndo()
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, "撤销后锚角应回到右下")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2(40.0, 17.0)), "撤销后偏移应精确回到 (40, 17)")
	# Redo: BOTH fields forward again. / 重做：两个字段再次前进。
	gpCv.gpRedo()
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_TOP_LEFT, "重做后锚角应回到左上")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO), "重做后偏移应回到零")
	gpCv.free()


# ESC abandons the drag: the start pair is restored, NOTHING enters the undo stack.
# ESC 放弃拖拽：起始对被还原，撤销栈**什么都不会**进。
func gpTestCancelRestoresTheStartPair() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	var gpGrip: GPTitleBlockGripOps = gpF[2]
	var gpBefore: Array = _gpPair(gpS)
	gpCheck(gpGrip.gpTryStart(_gpBlock(gpS).get_center()), "按下应抓到图签")
	gpGrip.gpOnGripMove(_gpFrame(gpS).get_center())
	gpCheck(not (_gpPair(gpS)[1] as Vector2).is_equal_approx(gpBefore[1]), "探针：预览应已写出不同的偏移")
	gpGrip.gpCancelDrag()
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "取消不得产生撤销步")
	gpCheck(_gpPair(gpS)[0] == gpBefore[0] and (_gpPair(gpS)[1] as Vector2).is_equal_approx(gpBefore[1]),
		"取消后停靠对应精确回到起始对")
	gpEq(gpGrip.gpIsDragging(), false, "取消后不得仍处于拖拽态")
	gpCv.free()


# ===========================================================================
# 5. Canvas wiring / 画布接线
# ===========================================================================

# The canvas port commits through the DISPLAYED sheet, one undo step, and refuses to record a no-op —
# the same contract the margins port has.
# 画布端口经**所显示的**图纸提交、一个撤销步、并拒绝为空操作记步 —— 与边距端口同一契约。
func gpTestCanvasPortCommitsThroughTheDisplayedSheet() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	var gpS: GPSheet = gpF[1]
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 0, "起始撤销栈为空")
	gpEq(gpCv.gpRequestSetTitleBlockPlacement(GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(30.0, 20.0)), true,
		"画布端口应提交成功")
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_TOP_LEFT, "所写图纸即所显示图纸（锚角）")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2(30.0, 20.0)), "所写图纸即所显示图纸（偏移）")
	gpEq(gpCv.gpActions.gpStack.gpUndoDepth(), 1, "一个撤销步")
	gpEq(gpCv.gpRequestSetTitleBlockPlacement(GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(30.0, 20.0)), false,
		"同样的对再提交一次应为空操作")
	gpCv.gpUndo()
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, "经画布端口写入的改动可撤销（锚角）")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO), "经画布端口写入的改动可撤销（偏移）")
	gpCv.free()


# The two new ports, pinned by name + arity the way the port snapshot pins the original 41: a deleted
# or re-signatured forwarder is NOT a compile error in GDScript, so it has to be pinned by a test.
# 两个新端口按「名字 + 参数个数」钉住，与端口快照钉住最初 41 个的方式相同：被删掉或改了签名的转发壳
# 在 GDScript 里**不是**编译错误，故必须用测试钉住。
func gpTestTitleBlockPortsArePinned() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpArity: Dictionary = {}
	for gpM in gpCv.get_method_list():
		gpArity[str(gpM["name"])] = (gpM["args"] as Array).size()
	var gpPorts: Array = [
		"gpRequestSetTitleBlockPlacement", 2,
	]
	for gpI in range(0, gpPorts.size(), 2):
		var gpName: String = str(gpPorts[gpI])
		gpCheck(gpArity.has(gpName), "新增端口仍应在画布上 / new port still on the canvas: " + gpName)
		gpEq(gpArity.get(gpName, -1), int(gpPorts[gpI + 1]),
			"参数个数不变 / arity unchanged: " + gpName)
	# The command whitelist must carry BOTH fields — one field travelling alone is the half-state
	# bug this stage exists to prevent.
	# 命令白名单必须**同时**携带两字段 —— 单字段独行正是本阶段要防的半态 bug。
	gpCheck(GPMutateSheetCommand.GP_FIELDS.has(GPMutateSheetCommand.GP_FIELD_TB_ANCHOR),
		"白名单应含 tb_anchor")
	gpCheck(GPMutateSheetCommand.GP_FIELDS.has(GPMutateSheetCommand.GP_FIELD_TB_OFFSET),
		"白名单应含 tb_offset")
	gpCv.free()


# The tool context exposes the delegate null-safely off-tree, and returns the SAME instance once the
# canvas assembles one — the same seam every other grab target travels.
# 工具上下文在树外空安全地暴露委托，画布装配后返回**同一个**实例 —— 与其它抓取目标相同的接缝。
func gpTestToolContextExposesTheTitleBlockGrips() -> void:
	var gpF: Array = _gpFixture()
	var gpCv: GPCanvas2D = gpF[0]
	# Off-tree the delegate is null (it is built in _ready, like every other delegate).
	# 树外时委托为 null（与其它委托一样在 _ready 中构建）。
	gpCheck(gpCv.gpTitleBlockGrips == null, "探针：树外画布的委托未装配（与其它委托同）")
	var gpCtx: GPCanvasToolContext = GPCanvasToolContext.new(gpCv)
	gpCheck(gpCtx.gpTitleBlockGrips == null, "未装配时 getter 应返回 null 而非崩溃")
	var gpGrip: GPTitleBlockGripOps = GPTitleBlockGripOps.new(gpCv)
	gpCv.gpTitleBlockGrips = gpGrip
	gpCheck(gpCtx.gpTitleBlockGrips == gpGrip, "装配后 getter 应返回画布上的同一个委托")
	gpCv.gpTitleBlockGrips = null
	gpCv.free()


# Double click on the block opens its DIALOG (2026-10-16 user report: "double click does nothing,
# cannot edit"). The block has no in-place editor, so the canvas must raise a dedicated request and
# the press path must raise it BEFORE arming a drag — a double click that only armed a no-motion
# drag felt completely dead. Pinned here at the two ends that are testable headless: the signal
# exists on the canvas, and the select-tool source raises it BEFORE gpTryStart in the same branch.
# **双击**图签打开其**对话框**（2026-10-16 用户报告：「双击也没反应，不能修改」）。图签没有就地
# 编辑器，故画布必须发出专门的请求、且 press 路径必须在**上膛拖拽之前**发出 —— 只会上膛一次零
# 位移拖拽的双击对用户来说完全是死的。headless 下能钉的是两端：画布上存在该信号，且 select_tool
# 源码在同一分支内先发信号、后 gpTryStart。
func gpTestDoubleClickAsksForTheDialog() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpCheck(gpCv.has_signal("gpTitleBlockEditRequested"),
		"画布应声明 gpTitleBlockEditRequested 信号（双击图签 → 宿主开对话框）")
	gpCv.free()
	var gpSrc: String = FileAccess.get_file_as_string("res://src/ui/tools/select_tool.gd")
	gpCheck(gpSrc.length() > 0, "应能读到 select_tool.gd 源码")
	var gpAt: int = gpSrc.find("if gpCtx.gpTitleBlockGrips.gpTryStart(gpWorld):")
	gpCheck(gpAt >= 0, "图签拖拽上膛分支应仍在（源码守卫的锚点）")
	# Compare ABSOLUTE positions: slicing a window before the anchor makes the anchor itself absent
	# from the slice, and a slice-relative compare silently compares against -1.
	# 比较**绝对**位置：在锚点之前切窗口会把锚点自身切掉，窗口内的相对比较会悄悄跟 -1 比。
	var gpAtEmit: int = gpSrc.find("gpTitleBlockEditRequested.emit()")
	gpCheck(gpAtEmit >= 0, "双击分支应发出 gpTitleBlockEditRequested（画布上的专门请求信号）")
	gpCheck(gpAtEmit < gpAt, "双击分支必须在拖拽上膛**之前**发信号（先对话框、后上膛）")
	gpCheck(gpSrc.rfind("if gpDouble and", gpAt) >= 0
			and gpSrc.rfind("if gpDouble and", gpAt) > gpSrc.rfind("gpTryStart", gpAtEmit),
		"信号分支应以 gpDouble 为闸（普通按下仍上膛拖拽）")
