extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Headless tests for align / distribute (A7) and keyboard nudge (A8).
# 对齐 / 分布（A7）与键盘微调（A8）的 headless 测试。
#
# Four promises are guarded here / 此处守护四条承诺：
#   1. ALIGN MOVES THE RIGHT EDGE ONLY. Left-align changes x and leaves y alone — an align that
#      also nudged the other axis would be indistinguishable from a "move".
#      **对齐只动该动的那条边**。左对齐只改 x、不动 y —— 若顺手挪了另一轴，就与「移动」无异了。
#   2. DISTRIBUTE EQUALISES THE GAPS, NOT THE CENTRES. A wide vessel and a narrow valve must end
#      up with equal whitespace between them (the drafting convention).
#      **分布等化的是间隙，不是中心**。宽设备与窄阀门之间必须是等白，这是制图惯例。
#   3. ONE OBJECT IS A NO-OP. Fewer than two rectangles returns the inputs unchanged, so the menu
#      can be disabled honestly and no phantom undo step is possible.
#      **单个对象是空操作**。少于两个矩形时原样返回，故菜单可被诚实禁用，也不可能产生幽灵撤销步。
#   4. ORDER IS PRESERVED. The result array is parallel to the input even though distribute walks
#      a sorted index list — the caller's node order must not change the layout.
#      **顺序保持**。返回数组与输入平行，尽管分布内部走的是排序下标表 —— 调用方的节点顺序不得
#      改变布局。

const GP_EPS: float = 0.001


# Two 10x10 boxes at x = 0 and x = 100, both at y = 0.
# 两个 10x10 方块，x 分别在 0 与 100，y 均为 0。
func _gpTwo() -> Array[Rect2]:
	var gpOut: Array[Rect2] = []
	gpOut.append(Rect2(0.0, 0.0, 10.0, 10.0))
	gpOut.append(Rect2(100.0, 40.0, 10.0, 10.0))
	return gpOut


# ---------------------------------------------------------------------------
# Align: six modes
# 对齐：六种模式
# ---------------------------------------------------------------------------

func gpTestAlignLeftMovesXOnly() -> void:
	var gpOut: Array[Vector2] = GPAlignOps.gpTargets(_gpTwo(), GPAlignOps.Mode.GP_LEFT)
	gpApprox(gpOut[0].x, 0.0, GP_EPS, "左对齐：首个不动 / left: first unchanged")
	gpApprox(gpOut[1].x, 0.0, GP_EPS, "左对齐：第二个靠左 / left: second moves to the left edge")
	gpApprox(gpOut[1].y, 40.0, GP_EPS, "左对齐不动 y / left leaves y alone")


func gpTestAlignRightMovesRightEdges() -> void:
	var gpOut: Array[Vector2] = GPAlignOps.gpTargets(_gpTwo(), GPAlignOps.Mode.GP_RIGHT)
	gpApprox(gpOut[0].x + 10.0, 110.0, GP_EPS, "右对齐：首个的右边靠到最右 / right edges coincide")
	gpApprox(gpOut[1].x + 10.0, 110.0, GP_EPS, "右对齐：第二个的右边不变 / right: second unchanged")


func gpTestAlignHCenterUsesUnionCentre() -> void:
	var gpOut: Array[Vector2] = GPAlignOps.gpTargets(_gpTwo(), GPAlignOps.Mode.GP_HCENTER)
	# Union spans 0..110, so its centre is 55; both boxes must be centred on it.
	# 并集跨 0..110，中心 55；两个方块都必须以它居中。
	gpApprox(gpOut[0].x + 5.0, 55.0, GP_EPS, "水平居中：首个 / hcenter: first")
	gpApprox(gpOut[1].x + 5.0, 55.0, GP_EPS, "水平居中：第二个 / hcenter: second")


func gpTestAlignTopAndBottom() -> void:
	var gpOut: Array[Vector2] = GPAlignOps.gpTargets(_gpTwo(), GPAlignOps.Mode.GP_TOP)
	gpApprox(gpOut[1].y, 0.0, GP_EPS, "上对齐靠到最上 / top edges coincide")
	gpApprox(gpOut[1].x, 100.0, GP_EPS, "上对齐不动 x / top leaves x alone")
	var gpOut2: Array[Vector2] = GPAlignOps.gpTargets(_gpTwo(), GPAlignOps.Mode.GP_BOTTOM)
	gpApprox(gpOut2[0].y + 10.0, 50.0, GP_EPS, "下对齐靠到最下 / bottom edges coincide")


func gpTestAlignVCenterUsesUnionCentre() -> void:
	var gpOut: Array[Vector2] = GPAlignOps.gpTargets(_gpTwo(), GPAlignOps.Mode.GP_VCENTER)
	# Union spans y 0..50 -> centre 25; both boxes centred there.
	# 并集纵跨 0..50，中心 25；两个方块都以它居中。
	gpApprox(gpOut[0].y + 5.0, 25.0, GP_EPS, "垂直居中：首个 / vcenter: first")
	gpApprox(gpOut[1].y + 5.0, 25.0, GP_EPS, "垂直居中：第二个 / vcenter: second")


# ---------------------------------------------------------------------------
# Distribute: gaps, not centres
# 分布：间隙，而非中心
# ---------------------------------------------------------------------------

func gpTestDistributeEqualisesGaps() -> void:
	# Three boxes of widths 10 / 30 / 10, spanning 0..200. Used width = 50, so the two gaps are
	# (200 - 50) / 2 = 75 each: origins at 0, 85, 190.
	# 三个宽度 10 / 30 / 10 的方块，跨 0..200。已用宽 50，故两个间隙各 (200-50)/2 = 75：
	# 原点依次为 0、85、190。
	var gpRects: Array[Rect2] = []
	gpRects.append(Rect2(0.0, 0.0, 10.0, 10.0))
	gpRects.append(Rect2(20.0, 0.0, 30.0, 10.0))
	gpRects.append(Rect2(190.0, 0.0, 10.0, 10.0))
	var gpOut: Array[Vector2] = GPAlignOps.gpTargets(gpRects, GPAlignOps.Mode.GP_DIST_H)
	gpApprox(gpOut[0].x, 0.0, GP_EPS, "首个不动 / first stays")
	gpApprox(gpOut[1].x, 85.0, GP_EPS, "中间项落在 85 / middle lands at 85")
	gpApprox(gpOut[2].x, 190.0, GP_EPS, "末个不动 / last stays")


func gpTestDistributeKeepsInputOrder() -> void:
	# Same three boxes supplied in a SHUFFLED order: the result must still line up with the input
	# array, not with the visual left-to-right order.
	# 同样三个方块以**打乱**的顺序传入：结果必须仍与输入数组对齐，而不是与视觉左右顺序对齐。
	var gpRects: Array[Rect2] = []
	gpRects.append(Rect2(190.0, 0.0, 10.0, 10.0))
	gpRects.append(Rect2(0.0, 0.0, 10.0, 10.0))
	var gpOut: Array[Vector2] = GPAlignOps.gpTargets(gpRects, GPAlignOps.Mode.GP_DIST_H)
	gpApprox(gpOut[0].x, 190.0, GP_EPS, "末尾项保持原位（第一个输入）/ the trailing box stays")
	gpApprox(gpOut[1].x, 0.0, GP_EPS, "首项保持原位（第二个输入）/ the leading box stays")


func gpTestDistributeVertical() -> void:
	var gpRects: Array[Rect2] = []
	gpRects.append(Rect2(0.0, 0.0, 10.0, 10.0))
	gpRects.append(Rect2(0.0, 20.0, 10.0, 10.0))
	gpRects.append(Rect2(0.0, 190.0, 10.0, 10.0))
	var gpOut: Array[Vector2] = GPAlignOps.gpTargets(gpRects, GPAlignOps.Mode.GP_DIST_V)
	gpApprox(gpOut[0].y, 0.0, GP_EPS, "垂直：首个不动 / vertical: first stays")
	# Heights are all 10, so used = 30 and each gap = (200-30)/2 = 85 → the middle origin is
	# 10 + 85 = 95. (The horizontal case above has a WIDE middle box, hence its different value.)
	# 三个高度都是 10，故已用 30、间隙 (200-30)/2 = 85 → 中间原点为 10 + 85 = 95。
	#（上面水平用例的中间块更宽，故数值不同。）
	gpApprox(gpOut[1].y, 95.0, GP_EPS, "垂直：中间落在 95 / vertical: middle at 95")
	gpApprox(gpOut[2].y, 190.0, GP_EPS, "垂直：末个不动 / vertical: last stays")


# ---------------------------------------------------------------------------
# Degenerate inputs
# 退化输入
# ---------------------------------------------------------------------------

func gpTestSingleRectIsNoOp() -> void:
	var gpOne: Array[Rect2] = [Rect2(7.0, 9.0, 10.0, 10.0)]
	for gpMode in [GPAlignOps.Mode.GP_LEFT, GPAlignOps.Mode.GP_HCENTER,
			GPAlignOps.Mode.GP_DIST_H, GPAlignOps.Mode.GP_DIST_V]:
		var gpOut: Array[Vector2] = GPAlignOps.gpTargets(gpOne, gpMode)
		gpApprox(gpOut[0].x, 7.0, GP_EPS, "单对象不动 x / a lone rect keeps x")
		gpApprox(gpOut[0].y, 9.0, GP_EPS, "单对象不动 y / a lone rect keeps y")


func gpTestEmptyIsSafe() -> void:
	var gpNone: Array[Rect2] = []
	var gpOut: Array[Vector2] = GPAlignOps.gpTargets(gpNone, GPAlignOps.Mode.GP_LEFT)
	gpEq(gpOut.size(), 0, "空输入得空输出 / empty in, empty out")


# ---------------------------------------------------------------------------
# i18n: the eight menu entries
# i18n：八条菜单项
# ---------------------------------------------------------------------------

func gpTestAlignKeysBilingual() -> void:
	for gpKey in ["canvas.ctx_align_left", "canvas.ctx_align_hcenter", "canvas.ctx_align_right",
			"canvas.ctx_align_top", "canvas.ctx_align_vcenter", "canvas.ctx_align_bottom",
			"canvas.ctx_dist_h", "canvas.ctx_dist_v"]:
		var gpPair: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
		gpCheck(not gpPair.is_empty(), "键存在 / key present: " + gpKey)
		gpCheck(str(gpPair.get("zh", "")) != "", "中文非空 / zh non-empty: " + gpKey)
		gpCheck(str(gpPair.get("en", "")) != "", "英文非空 / en non-empty: " + gpKey)


# The mode enum and the menu list must stay in lockstep: the context menu maps
# (id - GP_CTX_ALIGN_BASE) straight onto the enum, so a gap in either would misfire.
# 模式枚举与菜单清单必须同步：右键菜单把 (id - GP_CTX_ALIGN_BASE) 直接映射到枚举，
# 任一处有缺口都会错位。
func gpTestAlignModeCountMatchesMenu() -> void:
	gpEq(GPAlignOps.Mode.size(), 8, "八种模式 / eight modes")
	gpEq(GPCanvasContextMenu._gpAlignModes().size(), 8, "菜单列八项 / the menu lists eight")


# ---------------------------------------------------------------------------
# A8: keyboard nudge
# A8：键盘微调
# ---------------------------------------------------------------------------
# The intent lives on the facade because it needs a live canvas (selection + graph + command
# stack); driving it here pins the two behaviours a user can feel: "one step moves by exactly the
# step" and "a mounted child is not silently half-nudged".
# 该意图在门面里，因为它需要一个活画布（选择 + 图 + 命令栈）；在此驱动它，钉住用户能感到的两件事：
# 「一步就移动一个步长」与「挂载子件不会被悄悄挪一半」。

func _gpNudgeCanvas() -> GPCanvas2D:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "n1"
	gpN.gpSymbolId = "sym"
	gpN.gpPosition = Vector2(100.0, 100.0)
	gpG.gpAddNode(gpN)
	# A mounted child: its position is derived from a host, so a nudge must skip it.
	# 挂载子件：位置由宿主推导，故微调必须跳过它。
	var gpC: GPPIDNode = GPPIDNode.new()
	gpC.gpInstanceId = "c1"
	gpC.gpSymbolId = "sym"
	gpC.gpPosition = Vector2(0.0, 0.0)
	gpC.gpParentUid = "n1"
	gpC.gpMountAnchor = "top"
	gpG.gpAddNode(gpC)
	gpCv.gpGraph = gpG
	gpCv.gpSetSelection(["n1", "c1"])
	return gpCv


func gpTestNudgeMovesByExactStep() -> void:
	var gpCv: GPCanvas2D = _gpNudgeCanvas()
	gpCheck(gpCv.gpRequestNudgeSelection(Vector2(1.0, 0.0)), "一步微调生效 / one step moves")
	gpApprox(gpCv.gpGraph.gpGetNode("n1").gpPosition.x, 101.0, GP_EPS, "X 前进一步 / x advanced by one")
	gpApprox(gpCv.gpGraph.gpGetNode("n1").gpPosition.y, 100.0, GP_EPS, "Y 不变 / y untouched")
	gpCv.free()


func gpTestNudgeSkipsMountedChild() -> void:
	var gpCv: GPCanvas2D = _gpNudgeCanvas()
	gpCv.gpRequestNudgeSelection(Vector2(5.0, 5.0))
	gpApprox(gpCv.gpGraph.gpGetNode("c1").gpPosition.x, 0.0, GP_EPS,
		"挂载子件不被微调 / a mounted child is not nudged")
	gpCv.free()


func gpTestNudgeRefusesZeroAndEmpty() -> void:
	var gpCv: GPCanvas2D = _gpNudgeCanvas()
	gpCheck(not gpCv.gpRequestNudgeSelection(Vector2.ZERO), "零位移被拒 / zero delta refused")
	gpCv.gpSetSelection([])
	gpCheck(not gpCv.gpRequestNudgeSelection(Vector2(1.0, 0.0)), "空选择被拒 / empty selection refused")
	gpCv.free()


# ---------------------------------------------------------------------------
# A9: canvas appearance — grid flag + background presets
# A9：画布外观 —— 网格开关 + 底色预设
# ---------------------------------------------------------------------------
# The two settings are plain persisted booleans/strings, but their RESOLVERS are pure and are
# what a corrupt settings file would break — a colour string of "" makes Color("") an ENGINE
# ERROR on every paint, so the parse must degrade instead of shouting.
# 这两项设置本身只是持久化的布尔/字符串，但它们的**解析器**是纯函数，也正是损坏的设置文件会弄坏的
# 地方 —— 空色串会让 Color("") 在每一帧都成为**引擎错误**，故解析必须降级而不是叫喊。

func gpTestParseBgAcceptsHexWithAndWithoutHash() -> void:
	var gpFallback: Color = Color(0.5, 0.5, 0.5)
	var gpA: Color = GPCanvasOverlay.gpParseBg("212830", gpFallback)
	gpApprox(gpA.r, float(0x21) / 255.0, GP_EPS, "无 # 前缀可解析 / parses without a hash")
	var gpB: Color = GPCanvasOverlay.gpParseBg("#212830", gpFallback)
	gpApprox(gpB.b, gpA.b, GP_EPS, "带 # 前缀等价 / the hash is optional")


func gpTestParseBgFallsBackOnGarbage() -> void:
	var gpFallback: Color = Color(0.5, 0.5, 0.5)
	gpApprox(GPCanvasOverlay.gpParseBg("", gpFallback).r, 0.5, GP_EPS, "空串回落 / empty falls back")
	gpApprox(GPCanvasOverlay.gpParseBg("zzz", gpFallback).r, 0.5, GP_EPS, "非十六进制回落 / garbage falls back")
	gpApprox(GPCanvasOverlay.gpParseBg("12345", gpFallback).r, 0.5, GP_EPS, "长度不符回落 / wrong length falls back")


func gpTestBgPresetCycleWraps() -> void:
	var gpFirst: String = GPCanvas2D.GP_BG_PRESETS[0]
	var gpSecond: String = GPCanvas2D.GP_BG_PRESETS[1]
	var gpLast: String = GPCanvas2D.GP_BG_PRESETS[GPCanvas2D.GP_BG_PRESETS.size() - 1]
	gpEq(GPCanvas2D.gpNextBgPreset(gpFirst), gpSecond, "首个 → 第二个 / first moves to second")
	gpEq(GPCanvas2D.gpNextBgPreset(gpLast), gpFirst, "末个 → 首个（循环）/ last wraps to first")
	gpEq(GPCanvas2D.gpNextBgPreset("nonsense"), gpFirst, "未知值回到首个 / unknown resets to first")


func gpTestSettingsDefaultsForCanvasAppearance() -> void:
	# Defaults must be the historical behaviour: grid ON, the same dark background the overlay
	# used to hardcode — otherwise a first launch would look different from every screenshot.
	# 默认值必须是历史行为：网格开、与覆盖层此前硬编码的同一深色 —— 否则首次启动的样子会与所有截图不同。
	gpCheck(Settings.gpShowGrid, "网格默认开 / the grid defaults to on")
	gpEq(Settings.gpCanvasBg, GPCanvas2D.GP_BG_PRESETS[0], "底色默认取首个预设 / the background defaults to preset 0")
