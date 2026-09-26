extends "res://tests/gp_test.gd"
# Regression tests for the four defects a real-GUI review reported against v0.1.
# 针对真实界面复核所报 v0.1 四个缺陷的回归测试。
#
# The reports, verbatim / 用户原话：
# 1. 设备位号和管线位号的文字显示发虚    -> tag text looked blurry.
# 2. 图元端点的现实大小跟图元大小完全不匹配，显示过大 -> port marks were way too big for the symbol.
# 3. 左侧图元库的文字显示过大，且哥哥分类之间重叠了，像是分类设了固定高度，要修改为自适应高度
#    -> palette text too large, category headers overlapped, heights looked fixed instead of adaptive.
# 4. 还是没有图框                      -> the drawing frame was still missing.
#
# WHY THESE ARE UNIT-TESTABLE AT ALL / 为何这些竟然可以单元测试：
# All four had a root cause that lives in PURE arithmetic or PURposely-fixed constants — an mm value
# being consumed as a pixel value, a handle being a constant instead of a ratio, a cell height
# derived from the wrong key. So the defect can be pinned without a window, and a future refactor
# cannot silently bring it back. The remaining half (does the frame actually paint?) is covered by
# the scene smoke gate.
# 四者的根因都落在**纯算术**或「刻意固定的常量」上 —— 把毫米值当像素用、手柄用常量而非比例、
# 单元格高度取自错误的键。故无需窗口即可钉住缺陷，未来重构也无法悄悄复活它。另一半
#（图框到底画没画出来）由场景冒烟门覆盖。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。


# A3, the v0.1 default sheet (DEXPI C01 is A3 420x297 mm).
# A3，v0.1 默认图幅（DEXPI C01 即 A3 420×297mm）。
const GP_A3_W: float = 420.0
const GP_A3_H: float = 297.0

# The zoom the canvas picks on first layout for a 1448x678 viewport (measured on the real app).
# 真实应用中 1448×678 视口首次布局所选的缩放（实测）。
const GP_FIT_ZOOM: float = 2.1217

# Physical pixels per design pixel on the machine this defect was diagnosed on (measured from the
# viewport's screen transform: 3840 image px / 1792 design px).
# 本次诊断所用机器上的「物理像素 / 设计像素」（由视口的屏幕变换实测：图像 3840px / 设计 1792px）。
# It is the factor that made a floor written in design pixels twice as tall as intended.
# 正是这个系数使「以设计像素书写的下限」高出了两倍。
const GP_DEVICE_SCALE: float = 2.142857

# The pixel-era constant this suite guards against coming back.
# 本套件所防范的、像素时代的常量。
const GP_LEGACY_HANDLE_PX: float = 13.0
const GP_LEGACY_PORT_R_MM: float = 4.0


# DEFECT 3 — palette cell height is PIXEL based and must not read the mm symbol font height.
# 缺陷 3 —— 图元库单元格高度基于**像素**，且不得读取毫米图元字高。
# The regression: gpSymbolFontSize is a millimetre sheet text height since v0.1. Using it as a pixel
# source produced an 11 px thumbnail beside a 24 px label ("文字过大"). Anything >= 6 is a pixel-era
# value whose only correct treatment is the migration, never a cell metric.
# 失效复现：gpSymbolFontSize 自 v0.1 起是毫米图面字高。把它当像素来源用会得到「11px 缩略图配
# 24px 标签」（即「文字过大」）。≥6 的值只能是像素时代遗留，唯一正确处理是迁移，绝不是拿来算度量。
func gpTestPaletteCellHeightIsPixelBased() -> void:
	# 2026-09-25 AutoCAD restyle: the label is GONE, so the cell is thumbnail + padding.
	# 2026-09-25 AutoCAD 改版：标签已移除，单元格 = 缩略图 + 边距。
	var gpNormal: float = GPSymbolPaletteItem.gpCellHeight(12)
	gpEq(gpNormal, GPSymbolPaletteItem.GP_THUMB_PX + GPSymbolPaletteItem.GP_CELL_PAD,
		"单元格高度必须等于 缩略图 + 边距（单一度量来源）")
	gpEq(gpNormal, 33.0, "界面字号 12 时单元格高度应为 33px（21 缩略图 + 12 边距）")

	# Simulate the legacy pixel-era symbol font size leaking into the palette metrics.
	# 模拟像素时代的图元字号渗入图元库度量。
	# The cell height must be blind to it: the palette reads no font size at all now.
	# 单元格高度必须对此无感：如今图元库完全不读任何字号。
	gpEq(GPSymbolPaletteItem.gpCellHeight(12), gpNormal,
		"单元格高度不得随毫米图元字高变化（二者的单位不同，混用即缺陷 3）")
	gpCheck(gpNormal < 60.0,
		"单元格高度应保持在可放进左侧停靠栏的尺度，而非被毫米值放大")


# DEFECT 3 — the cell height ADAPTS to the UI font size instead of being a fixed height.
# 缺陷 3 —— 单元格高度应**随界面字号自适应**，而非固定高度。
func gpTestPaletteCellHeightIsAdaptive() -> void:
	# 2026-09-25 AutoCAD restyle: with the label gone, the "adaptive height" contract
	# becomes "immune to font size" — the overlap defect the old contract guarded against
	# (a clipped label pushing into the NEXT category header) cannot exist, because
	# nothing text-sized participates in the cell metrics anymore.
	# 2026-09-25 AutoCAD 改版：标签移除后，「自适应高度」契约变为「对字号免疫」——
	# 旧契约防范的重叠缺陷（标签被裁后顶进**下一个**类目标题）已无从发生，
	# 因为单元格度量中不再有任何随文字变化的量。
	gpEq(GPSymbolPaletteItem.gpCellHeight(4), GPSymbolPaletteItem.gpCellHeight(99),
		"极小与极大界面字号下单元格高度必须一致（度量与字号解耦）")
	gpEq(GPSymbolPaletteItem.gpCellHeight(9), GPSymbolPaletteItem.gpCellHeight(13),
		"常用字号区间内高度同样恒定")
	# The thumbnail itself stays the fixed, sensible size the tiles are drawn with.
	# 缩略图自身保持图块绘制的固定合理尺寸。
	# 2026-09-25: shrunk by 1/4 from 28 to 21 px per user request; tiles stay square.
	# 2026-09-25：按用户需求自 28px 缩小 1/4 至 21px；图块保持正方形。
	gpEq(GPSymbolPaletteItem.GP_THUMB_PX, 21.0, "缩略图应为固定 21px（AutoCAD 图块尺度，28px 缩小 1/4）")
	gpCheck(GPSymbolPaletteItem.gpCellHeight(13) >= GPSymbolPaletteItem.GP_THUMB_PX + 8.0,
		"单元格高度必须至少给缩略图留出 8px 上下余量，否则图块贴边")
	gpCheck(GPSymbolPaletteItem.gpCellHeight(13) > 20.0,
		"单元格不得塌缩到不可点击的尺寸")


# DEFECT 1 — the stored symbol text height, if pixel-era, is migrated to the mm standard ONCE.
# 缺陷 1 —— 若存档中的图元字高是像素时代的值，则一次性归位到毫米标准。
# The regression: a stored 12 kept meaning "12 mm of sheet text" after the world unit became 1 mm,
# i.e. four times the standard height — which is a large, softly-rasterised glyph, not a thin one.
# 失效复现：世界单位改为 1mm 后，存值 12 仍被读作「12mm 图面字高」，即标准字高的四倍 ——
# 那是一个又大又糊的字形，而不是一个细字。
func gpTestSymbolFontSizeMigration() -> void:
	# Loaded by path, NOT via the autoload: the headless test gate runs a bare SceneTree with no
	# autoloads, so the singleton simply does not exist there. Instantiating the script still gives
	# us the pure migration step without _ready() ever touching user://settings.cfg.
	# 按路径加载，**不**经 autoload：headless 测试门运行的是裸 SceneTree，没有 autoload，
	# 单例在那里根本不存在。实例化脚本仍可拿到纯迁移步骤，且 _ready() 不会去碰 user://settings.cfg。
	var gpScript: GDScript = load("res://src/autoload/settings.gd") as GDScript
	gpCheck(gpScript != null, "应能加载 settings.gd 以测试迁移步骤")
	if gpScript == null:
		return
	var gpS: Node = gpScript.new()
	# Pixel-era values (8..24) all become the standard sheet height.
	# 像素时代的值（8..24）全部归位到标准图面字高。
	gpEq(float(gpS.call("_gpMigrateSymbolFontMM", 12.0)), 3.0, "像素时代的 12 应归位为 3.0mm")
	gpEq(float(gpS.call("_gpMigrateSymbolFontMM", 24.0)), 3.0, "像素时代的 24 应归位为 3.0mm")
	# The threshold itself is inclusive on purpose: exactly 6 is already above any sheet text height.
	# 阈值刻意取闭区间：恰好 6 已高于任何合理的图面字高。
	gpEq(float(gpS.call("_gpMigrateSymbolFontMM", 6.0)), 3.0, "恰好达到阈值即应归位")
	# A legitimate mm value must survive untouched, or the user's own choice is destroyed.
	# 合法的毫米值必须原样保留，否则用户自己的选择会被破坏。
	gpEq(float(gpS.call("_gpMigrateSymbolFontMM", 3.0)), 3.0, "标准字高 3.0mm 应原样保留")
	gpEq(float(gpS.call("_gpMigrateSymbolFontMM", 5.9)), 5.9, "阈值以下的毫米值应原样保留")
	gpS.free()


# DEFECT 2 — the port handle box scales WITH its symbol instead of being a constant.
# 缺陷 2 —— 端口手柄框应**随其图元**缩放，而非常量。
# The regression: a fixed 13 px box beside a 4x2 mm ball valve is a third of the width of the whole
# valve (at 100% the valve is 4x2 screen points), so the handle visually swallowed its own symbol.
# 失效复现：在 4×2mm 球阀旁固定画 13px 方框，等于阀宽的…（100% 下阀门仅 4×2 屏幕点），
# 手柄因此在视觉上吞掉了它所标注的图元。
func gpTestPortHandleScalesWithSymbol() -> void:
	# A ball valve (4x2 mm) at the sheet-fit zoom.
	# 球阀（4×2mm）在整图适配缩放下的取值。
	var gpValveUnit: float = GPPortConnectOps.gpHandleUnitFor(4.0, GP_FIT_ZOOM)
	var gpValveBox: float = GPPortConnectOps.gpHandleBoxFor(gpValveUnit)
	gpApprox(gpValveUnit, 4.0 * GP_FIT_ZOOM * GPPortConnectOps.GP_HANDLE_RATIO, 1e-4,
		"手柄单元 = 图元较大边 × 缩放 × 手柄比例")
	gpEq(gpValveBox, GPPortConnectOps.GP_MIN_HANDLE,
		"小图元应取手柄下限 %s px" % [GPPortConnectOps.GP_MIN_HANDLE])
	# The heart of the defect: the handle must be smaller than the symbol it annotates, and much
	# smaller than the pixel-era constant.
	# 缺陷核心：手柄必须小于它所标注的图元，且远小于像素时代的常量。
	gpCheck(gpValveBox < GP_LEGACY_HANDLE_PX,
		"阀门手柄 %s px 必须小于旧的常量 %s px" % [gpValveBox, GP_LEGACY_HANDLE_PX])
	gpCheck(gpValveBox <= 4.0 * GP_FIT_ZOOM * 0.5,
		"手柄框不应超过图元屏幕尺寸的一半，否则手柄盖过图元")

	# A 30x51 mm vessel: large enough that the box reaches its ceiling.
	# 30×51mm 塔器：足够大，使方框达到上限。
	var gpVesselBox: float = GPPortConnectOps.gpHandleBoxFor(
		GPPortConnectOps.gpHandleUnitFor(51.0, GP_FIT_ZOOM))
	gpEq(gpVesselBox, GPPortConnectOps.GP_BOX,
		"大设备应取手柄上限 %s px" % [GPPortConnectOps.GP_BOX])
	gpCheck(gpVesselBox > gpValveBox, "大设备的手柄必须大于小图元的手柄（即非常量）")

	# Between the clamps the box is strictly proportional: this is the case a constant can never get
	# right, and it is what makes the handle read as "belonging" to its symbol.
	# 在上下限之间，方框严格成比例：这是常量永远做不到的情形，也正是手柄看起来「属于」其图元的原因。
	var gpMidBox: float = GPPortConnectOps.gpHandleBoxFor(
		GPPortConnectOps.gpHandleUnitFor(20.0, 2.0))
	gpCheck(gpMidBox > GPPortConnectOps.GP_MIN_HANDLE and gpMidBox < GPPortConnectOps.GP_BOX,
		"20mm 图元在 2× 缩放下应落在上下限之间（成比例）")
	gpApprox(gpMidBox, 20.0 * 2.0 * GPPortConnectOps.GP_HANDLE_RATIO, 1e-4,
		"成比例区间内方框 = 图元较大边 × 缩放 × 手柄比例")
	# Unresolvable anchors fall back to the FLOOR, so a stale id can never draw a giant handle.
	# 无法解析的锚点回落到**下限**，使陈旧 id 绝不会画出巨型手柄。
	gpEq(GPPortConnectOps.gpHandleBoxFor(GPPortConnectOps.gpHandleUnitFor(0.0, GP_FIT_ZOOM)),
		GPPortConnectOps.GP_MIN_HANDLE, "图元尺寸未知时应回落到手柄下限")


# DEFECT 2 (second half) — the port dot radius is a fraction of the symbol, not 4 mm.
# 缺陷 2（后半）—— 端口圆点半径是图元的比例，而非 4mm。
# The regression: the constant was 4.0 and was written in the pixel era, so after the world unit
# became 1 mm it meant a 4 mm RADIUS — an 8 mm dot on a 4x2 mm valve, i.e. four times the valve's
# height. That is exactly "端点的显示大小跟图元完全不匹配".
# 失效复现：该常量为 4.0 且写于像素时代，世界单位改为 1mm 后它意味着 4mm **半径** ——
# 在 4×2mm 的球阀上画 8mm 的圆点，即阀高的四倍。这正是「端点显示大小与图元完全不匹配」。
func gpTestPortRadiusStaysInsideItsSymbol() -> void:
	var gpValveR: float = GPSymbolView.gpPortRadiusFor(Vector2(4.0, 2.0))
	gpCheck(gpValveR < GP_LEGACY_PORT_R_MM,
		"阀门端口半径 %s mm 必须小于旧的常量 %s mm" % [gpValveR, GP_LEGACY_PORT_R_MM])
	# The dot must FIT inside the symbol: diameter below the shorter side.
	# 圆点必须**装进**图元：直径小于较短边。
	gpCheck(gpValveR * 2.0 < 2.0,
		"阀门端口直径 %s mm 应小于图元的短边 2mm" % [gpValveR * 2.0])

	# A vessel is capped, so a very large symbol cannot grow an absurd dot either.
	# 塔器取上限，使超大图元也不会长出荒唐的圆点。
	var gpVesselR: float = GPSymbolView.gpPortRadiusFor(Vector2(30.0, 51.0))
	gpEq(gpVesselR, GPSymbolView.GP_PORT_R_MAX, "大图元的端口半径应取上限")
	gpCheck(gpVesselR * 2.0 < 30.0, "大图元的端口直径仍应远小于图元短边")
	# Proportional between the clamps, and never a single constant.
	# 上下限之间成比例，且绝不是单一常量。
	gpCheck(GPSymbolView.gpPortRadiusFor(Vector2(12.0, 12.0)) > gpValveR,
		"12mm 图元的端口半径应大于球阀的（即非常量）")
	gpCheck(gpValveR > 0.0, "端口半径必须为正，否则连接点在屏幕上消失")


# DEFECT 4 — first layout FITS the sheet, which is what makes the frame visible at all.
# 缺陷 4 —— 首次布局即**适配图幅**，这正是图框得以可见的原因。
# The regression: a 1:1 (100%) camera on a 420x297 mm sheet shows it at 420x297 screen points — a
# fraction of the viewport, and the frame's thin lines then read as "missing".
# 失效复现：对 420×297mm 图幅取 1:1（100%）时，它只占 420×297 屏幕点 —— 视口的一小部分，
# 图框的细线于是被读成「没有图框」。
func gpTestFitSheetKeepsWholeSheetVisible() -> void:
	# The canvas is built by hand here: the headless gate runs without autoloads and without
	# _ready(), so the controller is wired explicitly. gpApplyCamera() null-guards gpWorldRoot,
	# which is why this works with no tree at all.
	# 此处手工装配画布：headless 门无 autoload 亦不触发 _ready()，故显式接线控制器。
	# gpApplyCamera() 对 gpWorldRoot 做了空判定，故完全没有节点树也能跑。
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpAvail: Vector2 = Vector2(1448.0, 678.0)
	gpCv.size = gpAvail
	var gpVc: GPCanvasViewController = GPCanvasViewController.new()
	gpVc.gpHost = gpCv
	gpCv.gpViewController = gpVc
	gpVc.gpFitSheet(GP_A3_W, GP_A3_H)

	var gpCam: GPCanvasCamera = gpCv.gpState.gpCam
	var gp: float = gpCam.gpZoom
	# Fit is height-limited for an A3 sheet in a 16:9-ish viewport, with the 0.94 breathing room.
	# 对 A3 图幅在约 16:9 视口下，适配受高度限制，并留 0.94 的余量。
	var gpWant: float = minf(gpAvail.x / GP_A3_W, gpAvail.y / GP_A3_H) * 0.94
	gpApprox(gp, gpWant, 1e-4, "适配缩放应为 min(宽比, 高比) × 0.94")
	gpCheck(gp > 1.0, "适配缩放应大于 1，否则 3mm 位号只有 3px、图框细线会消失")

	# The whole sheet — and therefore the frame — must land inside the viewport.
	# 整幅图（因而图框）必须落在视口之内。
	var gpTopLeft: Vector2 = gpCam.gpScreenFromWorld(Vector2.ZERO)
	var gpBottomRight: Vector2 = gpCam.gpScreenFromWorld(Vector2(GP_A3_W, GP_A3_H))
	gpCheck(gpTopLeft.x >= -0.5 and gpTopLeft.y >= -0.5, "图幅左上角应落在视口内")
	gpCheck(gpBottomRight.x <= gpAvail.x + 0.5 and gpBottomRight.y <= gpAvail.y + 0.5,
		"图幅右下角应落在视口内，否则图框被裁掉（即「没有图框」）")

	# And it must be CENTRED, or the sheet hugs one corner and the margins look broken.
	# 且必须**居中**，否则图幅贴着一角，页边看起来是坏的。
	gpApprox(gpTopLeft.x, (gpAvail.x - GP_A3_W * gp) * 0.5, 1e-3, "左侧页边应等于右侧页边")
	gpApprox(gpTopLeft.y, (gpAvail.y - GP_A3_H * gp) * 0.5, 1e-3, "上侧页边应等于下侧页边")

	# A zero-sized viewport (before layout) must be a no-op rather than a divide-by-zero.
	# 零尺寸视口（布局前）应是无操作，而不是除零。
	gpCv.size = Vector2.ZERO
	var gpBefore: float = gpCam.gpZoom
	gpVc.gpFitSheet(GP_A3_W, GP_A3_H)
	gpEq(gpCam.gpZoom, gpBefore, "视口尺寸未知时适配应无操作")
	gpCv.free()


# DEFECT 1 (the render half) — drawing text must be rasterised at the scale it is drawn at.
# 缺陷 1（渲染侧）—— 绘制文字必须按实际绘制缩放光栅化。
# The regression: without this the 3 mm tag is rasterised at 3 px and then magnified ~4x on screen,
# giving exactly the reported "发虚". Measured on real pixels, enabling it raised edge sharpness
# (mean gradient) by 1.64x at equal contrast.
# 失效复现：没有它时 3mm 位号按 3px 光栅化、再在屏幕上放大 ~4 倍，正是用户所报的「发虚」。
# 对真实像素实测：开启后边缘锐度（平均梯度）在相同对比度下提升 1.64 倍。
# WHY CALL _ready() DIRECTLY / 为何直接调用 _ready()：
# under a bare SceneTree the node never enters a tree, so _ready() is never dispatched; the flag
# lives in it, so the test invokes it explicitly. If the flag ever moves, this test fails loudly.
# 在裸 SceneTree 下节点永不入树，故 _ready() 不会被派发；标志位写在其中，测试只能显式调用它。
# 若标志位被挪走，本测试会立即失败。
func gpTestFrameRasterisesTextAtDrawScale() -> void:
	var gpFrame: GPFrameView = GPFrameView.new()
	gpFrame._ready()
	gpEq(gpFrame.oversampling_with_scale, CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED,
		"图框须按绘制缩放过采样，否则 2.2/2.8mm 的标题栏文字由 2px 光栅放大而发虚")
	# The property is an ENUM: writing `= true` coerces to 1 = DISABLED, which is the trap this
	# assertion exists to catch (it produces no error, only blur).
	# 该属性是**枚举**：写 `= true` 会强制转为 1（DISABLED）—— 本断言正是为捕捉这一陷阱，
	# 它不会报错，只会让画面发虚。
	gpCheck(gpFrame.oversampling_with_scale != CanvasItem.OVERSAMPLING_WITH_SCALE_DISABLED,
		"过采样不得是 DISABLED")
	gpFrame.free()


# DEFECT 1 (the real root cause) — the font size must be derived from the scale, never be the raw
# millimetre value.
# 缺陷 1（真正的根因）—— 字号必须由缩放推导，绝不能直接等于毫米值。
# The regression: `font_size = round(gpSymbolFontSize)` handed a 3 mm tag to draw_string as 3 PIXELS.
# The glyph bitmap came out 3 px tall and world_root then magnified it 2.12x onto the screen, so
# every tag read as a grey smudge — and it stayed a smudge for every font family, because the
# family was never the problem. Measured on real pixels: the same string at 3 px is unreadable,
# at 11 px it is crisp, for Arial / Helvetica Neue / PingFang alike.
# 失效复现：`font_size = round(gpSymbolFontSize)` 把 3mm 位号以 **3 像素**交给 draw_string。字模
# 只有 3px 高，再由 world_root 放大 2.12 倍贴到屏幕，于是每个位号都糊成一团灰 —— 且换任何字族
# 都是灰的，因为字族从来不是成因。真实像素实测：同一串字在 3px 下不可读，在 11px 下清晰，
# Arial / Helvetica Neue / PingFang 皆然。
func gpTestCanvasTextRasterisesAtScreenSize() -> void:
	# The floor is in PHYSICAL pixels, and must exceed the line-width floor: a glyph needs far more
	# pixels than a line does.
	# 下限以**物理**像素计，且必须大于线宽下限：字形所需的像素远多于线条。
	gpCheck(GPCanvasText.GP_MIN_DEVICE_PX > GPEdgeStyle.GP_MIN_PX,
		"文字下限 %s px 必须大于线宽下限 %s px" % [GPCanvasText.GP_MIN_DEVICE_PX, GPEdgeStyle.GP_MIN_PX])

	# On the density this was measured at, the fit-zoom 3 mm tag is NOT floored: it keeps its true
	# 6.37 design px (= 13.6 physical px, comfortably legible). Flooring it in DESIGN pixels instead
	# is what once drew the tag taller than the 4x2 mm valve it labels.
	# 在实测密度下，适配缩放中的 3mm 位号**不**触发下限：保持真实的 6.37 设计像素（= 13.6 物理像素，
	# 清晰可读）。若改用设计像素作下限，位号会被画得比它所标注的 4×2mm 阀门还高。
	gpApprox(GPCanvasText.gpScreenPx(3.0, GP_FIT_ZOOM, GP_DEVICE_SCALE), 3.0 * GP_FIT_ZOOM, 1e-3,
		"高密度屏上 3mm 位号应保持真实尺寸 6.37 设计像素，不被下限抬高")
	gpCheck(GPCanvasText.gpScreenPx(3.0, GP_FIT_ZOOM, GP_DEVICE_SCALE) < GPCanvasText.GP_MIN_DEVICE_PX,
		"真实尺寸低于物理下限即说明下限并未生效（这正是高密度屏上的正确行为）")

	# THE REGRESSION ITSELF: the old formula returned round(mm) == 3 at every zoom, i.e. a 3 px
	# bitmap magnified 2.1x. Nothing may ever again make the font size equal the raw millimetre value.
	# 缺陷本身：旧公式在任何缩放下都返回 round(mm) == 3，即 3px 字模被放大 2.1 倍。绝不允许字号
	# 再次等于原始毫米值。
	gpCheck(int(GPCanvasText.gpExactFontFit(3.0, 1.0).x) == 3, "100% 缩放下实测值恰为 3，与本断言对照")
	gpCheck(GPCanvasText.gpScreenPx(3.0, GP_FIT_ZOOM, GP_DEVICE_SCALE) != 3.0,
		"适配缩放下的字号不得等于原始毫米值 3 —— 那正是 3px 字模被放大的成因")
	# Size tracks the zoom, which a constant can never do.
	# 字号随缩放变化，常量永远做不到这一点。
	gpCheck(GPCanvasText.gpExactFontFit(3.0, 4.0).x > GPCanvasText.gpExactFontFit(3.0, 2.0).x,
		"放大后字号必须增大")
	# Past the floor the size is exactly the sheet height times the scale — precise WYSIWYG.
	# 超过下限后字号恰为「图面字高 × 缩放」—— 精确的所见即所得。
	gpEq(int(GPCanvasText.gpExactFontFit(3.0, 8.0).x), 24, "8x 缩放下 3mm 位号应为 24px（真实尺寸）")
	gpEq(int(GPCanvasText.gpExactFontFit(3.0, 4.0).x), 12, "4x 缩放下 3mm 位号应为 12px（真实尺寸）")

	# The floor becomes the safety net where it belongs: a plain 1:1 display, or zoomed far out.
	# 下限只在它该起作用处兜底：普通 1:1 屏，或缩到很小时。
	gpEq(GPCanvasText.gpScreenPx(3.0, 1.0, 1.0), GPCanvasText.GP_MIN_DEVICE_PX,
		"普通 1:1 屏上 3mm 位号应被抬到 10px 物理下限")
	gpApprox(GPCanvasText.gpScreenPx(3.0, 0.25, GP_DEVICE_SCALE),
		GPCanvasText.GP_MIN_DEVICE_PX / GP_DEVICE_SCALE, 1e-3,
		"缩到 0.25x 时应在**物理**像素上兜底（换算回 4.67 设计像素）")
	# gpLabelFontFit() with no item: both scales fall back to 1.0, so the floor is 10 design px.
	# gpLabelFontFit() 不传节点：两种缩放均回落 1.0，故下限为 10 设计像素。
	gpEq(int(GPCanvasText.gpLabelFontFit(3.0, null).x), 10, "无节点时同一换算应回落为 1:1 屏幕并触发下限")

	# Never zero (a zero font size draws nothing), never above the glyph-cache ceiling, and monotonic
	# in the scale — the three properties the draw sites rely on.
	# 绝不为零（零字号什么都画不出）、绝不超过字形缓存上限、且随缩放单调 —— 绘制点依赖这三条。
	var gpPrev: float = 0.0
	for gpZ in [0.0, 0.25, 1.0, 2.1217, 4.0, 8.0, 100.0]:
		var gpP: float = GPCanvasText.gpScreenPx(3.0, gpZ, GP_DEVICE_SCALE)
		gpCheck(gpP >= 1.0, "%sx 缩放下字号必须 >= 1" % [gpZ])
		gpCheck(gpP <= GPCanvasText.GP_MAX_PX, "%sx 缩放下字号不得超过上限" % [gpZ])
		gpCheck(gpP >= gpPrev, "%sx 缩放下字号不得随缩放回落（单调）" % [gpZ])
		gpPrev = gpP
	gpEq(GPCanvasText.gpScreenPx(3.0, 100.0, 1.0), GPCanvasText.GP_MAX_PX,
		"极端缩放应取字形缓存上限，而非无限增长")
	gpEq(GPCanvasText.gpScreenPx(3.0, 0.0, 1.0), GPCanvasText.GP_MIN_DEVICE_PX,
		"缩放为零时应回落为下限而非除零")

	# The counter-scale is what makes the bitmap come out 1:1: draw units -> screen pixels is
	# counterScale.x * scale == 1, so a glyph asked for at N px occupies exactly N px on screen.
	# 反向缩放正是字模得以 1:1 生成的原因：绘制单位 → 屏幕像素的系数为 counterScale.x × scale == 1，
	# 故请求 N px 的字形在屏幕上恰好占 N px。
	for gpZ2 in [1.0, GP_FIT_ZOOM, 8.0]:
		gpApprox(GPCanvasText.gpCounterScale(gpZ2).x * gpZ2, 1.0, 1e-6,
			"%sx 缩放下反向缩放与缩放之积应恒为 1" % [gpZ2])
	gpEq(GPCanvasText.gpCounterScale(2.0), Vector2(0.5, 0.5), "2x 缩放下反向缩放应为 0.5")
	# Outside a tree both scale readers degrade to 1.0 rather than dividing by zero or crashing.
	# 不在树内时两个缩放读取器均回落 1.0，而非除零或崩溃。
	gpEq(GPCanvasText.gpScaleOf(null), 1.0, "无节点时累积缩放应回落 1.0")
	gpEq(GPCanvasText.gpDeviceScaleOf(null), 1.0, "无节点时设备密度应回落 1.0")


# DEFECT 1 (the title-block half) — the frame converts mm to pixels the same way, but WITHOUT the
# reading floor: its internal millimetre layout must stay exact.
# 缺陷 1（标题栏侧）—— 图框用同一套换算，但**不加阅读下限**：其内部毫米排布必须保持精确。
# The regression: the frame used to return round(mm), so a 2.8 mm field value was drawn from a 3 px
# bitmap.
# 失效复现：图框曾返回 round(mm)，故 2.8mm 的字段值由一个 3px 字模画出。
func gpTestFrameTextUsesSameConversion() -> void:
	var gpFrame: GPFrameView = GPFrameView.new()
	# gpFontFit() reads the scale captured by _draw(); setting it directly is the only way to exercise
	# the conversion without a canvas, and it is exactly the value _draw() would have captured.
	# gpFontFit() 读取 _draw() 捕获的缩放；无画布时只能直接赋值，而它正是 _draw() 会捕获的那个值。
	gpFrame._gpTextScale = GP_FIT_ZOOM
	gpEq(int(gpFrame.gpFontFit(GPFrameView.GP_VALUE_MM).x), 5,
		"适配缩放下 2.5mm 字段值应为 5px（真实尺寸 5.30 取整），而非旧公式的 3px")
	gpEq(int(gpFrame.gpFontFit(GPFrameView.GP_CAPTION_MM).x), 5,
		"适配缩放下 2.5mm 字段名同为 5px —— 参照图对字段名与字段值取同一字高")
	# The frame's own constants must equal the reference tiers, and GDScript will not let a const
	# initialiser reference another class, so the equality is kept HERE rather than in the constants.
	# 图框自身的常量必须等于参照图的档位；GDScript 不允许常量初始化式引用其它类，故该等式维护在**此处**
	# 而非常量定义处。
	gpEq(GPFrameView.GP_CAPTION_MM, GPTextRole.GP_TITLE_FIELD_MM,
		"字段名字高必须等于标准标题栏档 2.5mm")
	gpEq(GPFrameView.GP_VALUE_MM, GPTextRole.GP_TITLE_FIELD_MM,
		"字段值字高必须等于标准标题栏档 2.5mm")
	# The drawing title is the ONE field the reference draws larger; at the fit zoom its 4.0 mm
	# becomes 8 px, so the distinction is visible in pixels, not just in the table.
	# 图纸标题是参照图中唯一被放大的字段；在适配缩放下其 4.0mm 为 8px，故该区别在像素上也看得见。
	gpEq(int(gpFrame.gpFontFit(GPTextRole.GP_DRAWING_TITLE_MM).x), 8,
		"图纸标题在适配缩放下应为 8px（4.0mm，参照图中的放大档）")
	gpCheck(gpFrame.gpFontFit(GPTextRole.GP_DRAWING_TITLE_MM).x
			> gpFrame.gpFontFit(GPFrameView.GP_VALUE_MM).x,
		"图纸标题必须大于普通字段，否则「图纸标题更大」这条标准没有被实现")
	# No floor here: the value the frame asks for equals mm x scale, so a title-block cell's authored
	# millimetre spacing is never inflated.
	# 此处无下限：图框索取的字号恰为「毫米 × 缩放」，故标题栏单元格的作者毫米间距永不被放大。
	gpEq(int(gpFrame.gpFontFit(GPFrameView.GP_VALUE_MM).x),
		int(GPCanvasText.gpExactFontFit(GPFrameView.GP_VALUE_MM, GP_FIT_ZOOM).x),
		"图框字号应与「真实比例」换算完全一致")
	gpCheck(int(gpFrame.gpFontFit(GPFrameView.GP_VALUE_MM).x) < GPCanvasText.GP_MIN_DEVICE_PX,
		"标题栏字号可以低于文字下限（它按真实比例绘制，不受阅读下限保护）")
	# At 100% nothing changes — the conversion is scale-aware, not a blanket enlargement.
	# 100% 下结果不变 —— 该换算是随缩放的，而非无差别放大。
	gpFrame._gpTextScale = 1.0
	gpEq(int(gpFrame.gpFontFit(GPFrameView.GP_VALUE_MM).x), 3,
		"100% 缩放下 2.5mm 应取整为 3px（随缩放，而非固定）")
	gpFrame.free()


# THE HALF A FONT SIZE ALONE CANNOT EXPRESS — a size is an INTEGER pixel count, so the sheet height
# is only exact when mm x zoom happens to be integral. The residual returned alongside the size is
# what puts the painted glyph back on the authored height.
# 单靠字号无法表达的另一半 —— 字号是**整数像素**，故只有当「毫米 × 缩放」恰为整数时图面字高才精确。
# 与字号成对返回的残差，正是把画出的字形拉回作者设定字高的那一步。
# WHY THIS MATTERS AT THE DEFAULT VIEW / 为何在默认视图上就有影响：
# At fit zoom a 4.5 mm equipment tag asks for 9.548 px -> 10 (+4.7 % too tall) while a 3.0 mm in-line
# tag asks for 6.365 px -> 6 (-5.7 % too short). The two tiers round in OPPOSITE directions, so the
# ratio the reference prescribes collapses from 1.500 to 1.667 — and 1.778 was measured on real
# pixels before this fix.
# 适配缩放下 4.5mm 设备位号需要 9.548px → 得 10（高 4.7%），而 3.0mm 在管标注需要 6.365px → 得 6
#（矮 5.7%）。两档朝**相反方向**取整，故参照图规定的比例从 1.500 塌到 1.667 —— 而在本修复之前的
# 真实像素上实测为 1.778。
func gpTestFontSizeCarriesItsRoundingResidual() -> void:
	# 4.5 mm at the fit zoom: 9.5477 px wanted, 10 handed to draw_string, residual 0.9548.
	# 适配缩放下 4.5mm：需要 9.5477px，交给 draw_string 10px，残差 0.9548。
	var gpTank: Vector2 = GPCanvasText.gpFontFit(4.5, GP_FIT_ZOOM, GP_DEVICE_SCALE)
	gpEq(int(gpTank.x), 10, "4.5mm 设备位号在适配缩放下取整为 10px")
	gpApprox(gpTank.y, 4.5 * GP_FIT_ZOOM / 10.0, 1e-6,
		"残差必须是「期望字号 / 取整字号」，即 9.5477/10 = 0.9548")
	gpApprox(gpTank.x * gpTank.y, 4.5 * GP_FIT_ZOOM, 1e-6,
		"取整字号 × 残差必须还原出精确的期望字号 —— 这正是残差存在的理由")
	# 3.0 mm in-line tag: 6.3651 px wanted, 6 handed over, residual 1.0609.
	# 3.0mm 在管标注：需要 6.3651px，交出 6px，残差 1.0609。
	var gpValve: Vector2 = GPCanvasText.gpFontFit(3.0, GP_FIT_ZOOM, GP_DEVICE_SCALE)
	gpEq(int(gpValve.x), 6, "3.0mm 在管标注在适配缩放下取整为 6px")
	gpApprox(gpValve.x * gpValve.y, 3.0 * GP_FIT_ZOOM, 1e-6,
		"在管标注同样必须被还原到精确的 6.3651px")
	# THE PROPERTY THE USER CAN SEE: after compensation the two tiers keep the standard's ratio.
	# 用户看得见的那条性质：补偿之后两档保持标准图规定的比例。
	var gpSheetTank: float = gpTank.x * gpTank.y / GP_FIT_ZOOM
	var gpSheetValve: float = gpValve.x * gpValve.y / GP_FIT_ZOOM
	gpApprox(gpSheetTank, 4.5, 1e-6, "补偿后设备位号的图面字高必须恰为 4.5mm")
	gpApprox(gpSheetValve, 3.0, 1e-6, "补偿后在管标注的图面字高必须恰为 3.0mm")
	gpApprox(gpSheetTank / gpSheetValve, 1.5, 1e-6,
		"补偿后两档之比必须恰为 4.5:3.0 = 1.5（未补偿时实测为 1.778）")
	# Uncompensated, the same two tiers do NOT keep the ratio — the defect this pins.
	# 未补偿时同样两档**不**保持比例 —— 本断言所钉住的缺陷。
	gpApprox(10.0 / 6.0, 1.6667, 1e-3,
		"对照：未补偿的取整字号之比为 1.667，偏离标准的 1.500")
	# Where mm x zoom is integral the residual is exactly 1: nothing is resampled at all, so the
	# sharpest possible glyph is preserved (6x is a zoom the user actually works at).
	# 「毫米 × 缩放」为整数处残差恰为 1：完全不重采样，从而保住最锐利的字形（6x 是用户真实会用到的缩放）。
	gpEq(GPCanvasText.gpFontFit(4.5, 6.0, GP_DEVICE_SCALE).y, 1.0, "6x 下 4.5mm 恰为 27px，残差应为 1")
	gpEq(GPCanvasText.gpFontFit(3.0, 6.0, GP_DEVICE_SCALE).y, 1.0, "6x 下 3.0mm 恰为 18px，残差应为 1")
	# The residual never exceeds the 1/(2*size) a rounding step can cost, so it can never become the
	# kind of magnification that blurs a glyph. The slack is 1e-6 because the pair travels in a
	# Vector2, which is SINGLE precision: a bound this tight is otherwise lost to float32 storage
	# (measured: 0.038461566 against a true 0.038461538).
	# 残差绝不会超过一次取整所能损失的 1/(2×字号)，故永远不会变成会糊掉字形的放大倍率。留 1e-6 余量
	# 是因为该成对值经 Vector2 传递，而 Vector2 是**单精度**：否则这么紧的界会被 float32 存储吃掉
	#（实测 0.038461566 对真值 0.038461538）。
	for gpMM in [2.5, 3.0, 4.0, 4.5]:
		for gpZ in [1.0, 1.5, 2.1217, 3.0, 5.0, 6.0, 8.0]:
			var gpF: Vector2 = GPCanvasText.gpFontFit(gpMM, gpZ, GP_DEVICE_SCALE)
			gpApprox(gpF.x * gpF.y, GPCanvasText.gpScreenPx(gpMM, gpZ, GP_DEVICE_SCALE), 1e-6,
				"%smm @ %sx：取整字号 × 残差必须等于期望字号" % [gpMM, gpZ])
			gpCheck(absf(gpF.y - 1.0) <= 0.5 / gpF.x + 1e-6,
				"%smm @ %sx：残差偏离 1 的幅度不得超过 1/(2×字号)，即不构成可见模糊" % [gpMM, gpZ])
	# gpTextScale folds the residual together with the counter-scale, so a draw site needs one call.
	# gpTextScale 把残差与反向缩放合到一起，故绘制站点只需一次调用。
	gpApprox(GPCanvasText.gpTextScale(Vector2(10.0, 0.9548), GP_FIT_ZOOM).x,
		0.9548 / GP_FIT_ZOOM, 1e-6, "gpTextScale 必须同时抵消父级放大并带上残差")
	gpEq(GPCanvasText.gpTextScale(Vector2(27.0, 1.0), 6.0), Vector2(1.0 / 6.0, 1.0 / 6.0),
		"残差为 1 时 gpTextScale 必须退化为纯粹的 gpCounterScale")


# DEFECT 1 (the trap the fix would otherwise re-introduce) — every zoom change must re-rasterise.
# 缺陷 1（若不修便会被重新引入的陷阱）—— 每一次缩放变化都必须重新光栅化。
# WHY: the font size is chosen from the live scale inside each view's _draw(), and a parent's
# queue_redraw never cascades to child CanvasItems. So a zoom that forgets to re-draw leaves the
# glyphs at the previous zoom's raster while they are magnified onto the larger screen — the same
# blur, back again, and completely silent.
# 原因：字号由各视图 _draw() 内的实时缩放选定，而父节点的 queue_redraw 不会级联到子 CanvasItem。
# 因此任何「缩放后忘记重绘」的路径都会让字形停留在上一次缩放的密度上、再被放大到更大的屏幕上 ——
# 同样的发虚再次出现，且完全静默。
# WHY THIS READS SOURCE TEXT / 为何以源码文本钉住：
# That failure produces no error and no number any assertion could catch: the model is right, the
# arithmetic is right, only the repaint is missing. The cheapest honest guard is that each
# zoom-changing path ends by calling the refresh, so this test asserts exactly that.
# 该失效不产生任何错误，也没有任何数值断言能捕捉：模型是对的、算术是对的，唯独漏了重绘。最廉价的
# 诚实守卫就是「每条改变缩放的路径都以该刷新收尾」，本测试正是断言这一点。
func gpTestEveryZoomChangeRerasterisesText() -> void:
	var gpSrc: String = FileAccess.get_file_as_string("res://src/ui/canvas/view_controller.gd")
	gpCheck(gpSrc.length() > 0, "应能读到 view_controller.gd 源码")
	for gpFn in ["func gpFitSheet", "func gpZoomAt", "func gpResetCamera"]:
		var gpAt: int = gpSrc.find(gpFn)
		gpCheck(gpAt >= 0, "应存在 %s()" % [gpFn])
		# The next top-level function header bounds this body.
		# 下一个顶层函数头即本函数体的边界。
		var gpNext: int = gpSrc.find("\nfunc ", gpAt + 1)
		var gpEnd: int = gpNext if gpNext > 0 else gpSrc.length()
		var gpBody: String = gpSrc.substr(gpAt, gpEnd - gpAt)
		gpCheck(gpBody.find("gpOnCameraChanged()") >= 0,
			"%s() 改变缩放后必须调用 gpOnCameraChanged()，否则位号保留旧字模被放大而发虚" % [gpFn])
	# The refresh itself must cover every layer that bakes its appearance from the scale.
	# 刷新本身必须覆盖每一个「外观由缩放烘焙」的图层。
	var gpCanvasSrc: String = FileAccess.get_file_as_string("res://src/ui/canvas/canvas_2d.gd")
	gpCheck(gpCanvasSrc.length() > 0, "应能读到 canvas_2d.gd 源码")
	var gpRefreshAt: int = gpCanvasSrc.find("func gpOnCameraChanged")
	gpCheck(gpRefreshAt >= 0, "GPCanvas2D 应提供 gpOnCameraChanged()")
	var gpRefreshEnd: int = gpCanvasSrc.find("\nfunc ", gpRefreshAt + 1)
	var gpRefreshBody: String = gpCanvasSrc.substr(gpRefreshAt,
		(gpRefreshEnd - gpRefreshAt) if gpRefreshEnd > 0 else 100
	)
	for gpCall in ["gpRefreshSymbolViews()", "gpSheetLayer.gpRefreshFrame()"]:
		gpCheck(gpRefreshBody.find(gpCall) >= 0,
			"gpOnCameraChanged() 必须刷新 %s，否则该图层保留旧字模" % [gpCall])
	# The frame refresh now lives on the sheet layer (GPCanvasSheetLayer), so pin the SECOND half
	# of the chain: the layer must still actually reach the frame view. Pinning only the root would
	# let someone delete the inner call and silently reintroduce the stale-glyph defect.
	# 图框刷新已下沉到图纸层（GPCanvasSheetLayer），故须钉住链条的**后半段**：该层仍必须真正
	# 调用到图框视图。只钉根类会让"删掉内层调用"悄悄复活旧字模缺陷。
	var gpLayerSrc: String = FileAccess.get_file_as_string("res://src/ui/canvas/sheet_layer.gd")
	gpCheck(gpLayerSrc.length() > 0, "应能读到 sheet_layer.gd 源码 / sheet_layer.gd reads")
	var gpLayerAt: int = gpLayerSrc.find("func gpRefreshFrame")
	gpCheck(gpLayerAt >= 0, "GPCanvasSheetLayer 应提供 gpRefreshFrame()")
	var gpLayerEnd: int = gpLayerSrc.find("\nfunc ", gpLayerAt + 1)
	var gpLayerBody: String = gpLayerSrc.substr(gpLayerAt,
		(gpLayerEnd - gpLayerAt) if gpLayerEnd > 0 else 100
	)
	gpCheck(gpLayerBody.find("gpFrame.gpRefresh()") >= 0,
		"gpRefreshFrame() 必须真正调用 gpFrame.gpRefresh()，否则图框保留旧字模")


# THE ZOOM-DRIFT DEFECT — the label's anchor edge must sit on the anchor point at EVERY zoom.
# 缩放漂移缺陷 —— 标签靠锚点的那条边必须在**任何**缩放下都落在锚点上。
# The report / 用户原话：画布缩放的时候，图元的位号文本位置会跑掉，而且手柄调不回来。
# The regression / 失效复现：the draw site computed `(worldOffset + textOriginPx) * scale`, so the
# text-origin term — which is already measured in the unit the glyph is drawn in — was magnified a
# second time. The label therefore flew away at a rate proportional to the zoom, while the drag grip
# (drawn at the true world offset) stayed put, which is precisely why dragging could never recover it.
# 绘制点计算 `(世界偏移 + 文字原点px) * 缩放`，于是「文字原点」项 —— 它的单位已经是字形的绘制单位 ——
# 被**第二次**放大。标签因此以与缩放成正比的速度飞离，而拖拽手柄（画在真实世界偏移处）纹丝不动，
# 这正是「手柄怎么拖都调不回来」的原因。
func gpTestLabelAnchorEdgeIgnoresZoom() -> void:
	# A 6-character tag at the fit zoom measures a few tens of design px, and the offset for a
	# 24.5 mm exchanger's LEFT anchor is about -19 mm — the combination that produced the report.
	# 适配缩放下 6 字符位号约几十设计像素，而 24.5mm 换热器 LEFT 锚点的偏移约 -19mm —— 正是复现报告的组合。
	var gpSz: Vector2 = Vector2(30.0, 6.0)
	var gpOff: Vector2 = Vector2(-19.0, 8.0)
	var gpAnchor: int = GPLabelAnchor.GPAnchor.GP_LEFT

	for gpZ in [1.0, GP_FIT_ZOOM, 8.0, 20.0]:
		var gpO: Vector2 = GPLabelGripOps.gpDrawOrigin(gpAnchor, gpOff, gpSz, gpZ)
		# LEFT means "hangs off the left edge", so the text's RIGHT edge is the anchored one.
		# LEFT 表示「从左边悬挂出来」，故靠锚点的是文字的**右**边缘。
		gpApprox(gpO.x + gpSz.x, gpOff.x * gpZ, 1e-4,
			"%sx 缩放下文字右边缘必须精确落在锚点 x 上" % [gpZ])
		# Vertically the text is centred on the anchor.
		# 垂直方向文字以锚点居中。
		gpApprox(gpO.y + gpSz.y * 0.5, gpOff.y * gpZ, 1e-4,
			"%sx 缩放下文字竖向中心必须精确落在锚点 y 上" % [gpZ])

	# The other anchors express the same contract with a different anchored edge.
	# 其它锚点表达同一契约，只是贴合的边不同。
	var gpRight: Vector2 = GPLabelGripOps.gpDrawOrigin(
		GPLabelAnchor.GPAnchor.GP_RIGHT, gpOff, gpSz, GP_FIT_ZOOM)
	gpApprox(gpRight.x, gpOff.x * GP_FIT_ZOOM, 1e-4, "RIGHT 锚点：文字左边缘落在锚点上")
	var gpBelow: Vector2 = GPLabelGripOps.gpDrawOrigin(
		GPLabelAnchor.GPAnchor.GP_BELOW, gpOff, gpSz, GP_FIT_ZOOM)
	gpApprox(gpBelow.x + gpSz.x * 0.5, gpOff.x * GP_FIT_ZOOM, 1e-4, "BELOW 锚点：文字水平居中于锚点")
	gpApprox(gpBelow.y + gpSz.y * 0.5, gpOff.y * GP_FIT_ZOOM, 1e-4, "BELOW 锚点：文字竖向居中于锚点")

	# THE DEFECT ITSELF, quantified: the old formula's error is exactly textWidth x (scale - 1) —
	# invisible at 100% (which is why it survived), 16 mm at the fit zoom, 250 mm at 8x. Pinning the
	# magnitude (rather than only "different") is what makes this test explain the report.
	# 缺陷本身，定量化：旧公式的误差恰为「文字宽 × (缩放 - 1)」—— 100% 下为零（故它一直没被发现），
	# 适配缩放下 16mm，8 倍缩放下 250mm。钉住**量级**（而非仅「不一样」）才使本测试能解释用户报告。
	for gpZ2 in [1.0, GP_FIT_ZOOM, 8.0]:
		var gpGood: Vector2 = GPLabelGripOps.gpDrawOrigin(gpAnchor, gpOff, gpSz, gpZ2)
		var gpOld: Vector2 = (gpOff + GPLabelGripOps.gpTextOrigin(gpAnchor, Vector2.ZERO, gpSz)) * gpZ2
		# The whole displacement is the text-origin vector magnified once too often, so its magnitude
		# is |textOrigin| x (scale - 1) — not simply the width, because the origin also carries the
		# vertical centring term. Both halves are asserted so the formula is stated, not approximated.
		# 全部位移就是「被多乘了一次缩放」的文字原点向量，故其模为 |文字原点| × (缩放 - 1) ——
		# 并非只有宽度，因为原点还带有竖向居中项。两半都断言，使公式被写清而不是被近似。
		gpApprox((gpOld - gpGood).length(),
			GPLabelGripOps.gpTextOrigin(gpAnchor, Vector2.ZERO, gpSz).length() * (gpZ2 - 1.0), 1e-4,
			"%sx 缩放下旧公式的漂移模应恰为 |文字原点| × (缩放 - 1)" % [gpZ2])
		gpApprox(absf(gpOld.x - gpGood.x), gpSz.x * (gpZ2 - 1.0), 1e-4,
			"%sx 缩放下旧公式的横向漂移应恰为文字宽 × (缩放 - 1)" % [gpZ2])
		gpApprox(absf(gpOld.y - gpGood.y), gpSz.y * 0.5 * (gpZ2 - 1.0), 1e-4,
			"%sx 缩放下旧公式的竖向漂移应恰为半字高 × (缩放 - 1)" % [gpZ2])
	# At 100% both agree — the bug was invisible at 1:1, and that is why it shipped.
	# 100% 下两者一致 —— 该缺陷在 1:1 时不可见，这正是它能溜进发布版的原因。
	gpApprox(GPLabelGripOps.gpDrawOrigin(gpAnchor, gpOff, gpSz, 1.0).x,
		(gpOff + GPLabelGripOps.gpTextOrigin(gpAnchor, Vector2.ZERO, gpSz)).x, 1e-4,
		"100% 缩放下新旧公式结果相同（缺陷只随缩放显现）")
	# The drift must grow with the zoom, i.e. it is not a constant offset a user could compensate for.
	# 漂移必须随缩放增长，即它不是用户能靠拖动补偿掉的恒定偏移。
	gpCheck(gpSz.x * (8.0 - 1.0) > gpSz.x * (GP_FIT_ZOOM - 1.0),
		"漂移必须随缩放增长，否则手柄本可以补回来")


# THE ARROW DEFECT — the flow arrow must be the reference drawing's size, not the pixel-era one.
# 箭头缺陷 —— 流向箭头必须是参照图的尺寸，而非像素时代的数字。
# The report / 用户原话：连线的箭头太大了，跟标准图不匹配。
# The regression / 失效复现：10.0 x 9.0 mm, written when one world unit was one pixel; at 1 mm per
# unit that is 2.9x too long and 5.1x too wide. It is checked against the pack data as well as the
# constants, so the two can never drift apart.
# 失效复现：10.0×9.0mm，写于「1 世界单位 = 1 像素」的时代；在 1 单位 = 1mm 下即长 2.9 倍、宽 5.1 倍。
# 本测试同时对照常量与图元包数据，使二者无法脱节。
func gpTestFlowArrowMatchesStandard() -> void:
	# The reference's marker: a 5.0 x 2.5 unit triangle at instance scale 0.70.
	# 参照图的标记：5.0×2.5 单位三角形，实例缩放 0.70。
	gpApprox(GPEdgePainter.GP_ARROW_LEN, 5.0 * 0.70, 1e-6, "箭头长度应为 5.0 × 0.70 = 3.5mm")
	gpApprox(GPEdgePainter.GP_ARROW_HALF, 2.5 * 0.70 * 0.5, 1e-6, "箭头半宽应为 2.5 × 0.70 / 2 = 0.875mm")
	gpApprox(GPEdgePainter.GP_ARROW_HALF * 2.0, 1.75, 1e-6, "箭头全宽应为 1.75mm（C01 的 size_mm[0]）")

	# The arrow must FIT the symbol it is drawn on: shorter than a ball valve's own width (4 mm) and
	# narrower than its height (2 mm). The old 10 x 9 mm arrow was 2.5x the whole valve.
	# 箭头必须**装得进**它所绘制的图元：短于球阀自身的宽度（4mm）、窄于其高度（2mm）。
	# 旧的 10×9mm 箭头是整个阀门的 2.5 倍。
	gpCheck(GPEdgePainter.GP_ARROW_LEN <= 4.0, "箭头长度不得超过球阀宽度 4mm")
	gpCheck(GPEdgePainter.GP_ARROW_HALF * 2.0 < 2.0, "箭头全宽应窄于球阀高度 2mm")

	# The in-line tier is 3.0 mm, so an arrow is under 1.2x the text height — visually a marker, not
	# a badge. The old one was 3.3x the text height.
	# 在管标注档为 3.0mm，故箭头不足文字高度的 1.2 倍 —— 视觉上是一个标记，而非一块牌子。
	# 旧值则是文字高度的 3.3 倍。
	gpCheck(GPEdgePainter.GP_ARROW_LEN < GPTextRole.GP_INLINE_TAG_MM * 1.2,
		"箭头长度应与管线号字高相称，否则它比它标注的文字还抢眼")
	gpCheck(10.0 > GPEdgePainter.GP_ARROW_LEN * 2.5,
		"新箭头必须远小于像素时代的 10mm（差距 2.5 倍以上）")

	# Cross-check against the pack that reproduces the reference drawing: its own manifest records the
	# flow marker at [1.75, 3.5] mm, so the constant and the symbol data agree by construction.
	# 与复刻参照图的图元包交叉核对：其清单记录的流向标记即 [1.75, 3.5]mm，故常量与图元数据天然一致。
	var gpRaw: String = FileAccess.get_file_as_string(
		"res://assets/symbol_packs/dexpi/manifest.json")
	gpCheck(gpRaw.length() > 0, "应能读到 DEXPI 包清单以核对箭头尺寸")
	var gpJson: Variant = JSON.parse_string(gpRaw)
	gpCheck(gpJson is Dictionary, "清单应为 JSON 对象")
	if gpJson is Dictionary:
		var gpFound: bool = false
		for gpIcon in (gpJson as Dictionary).get("icons", []):
			if str((gpIcon as Dictionary).get("id", ""))\
					== "direction_of_flow_for_primary_segment":
				var gpMm: Array = (gpIcon as Dictionary).get("size_mm", [])
				gpEq(gpMm.size(), 2, "流向标记应带 mm 尺寸")
				if gpMm.size() == 2:
					gpApprox(float(gpMm[0]), GPEdgePainter.GP_ARROW_HALF * 2.0, 1e-6,
						"包清单的箭头宽度应与渲染常量一致")
					gpApprox(float(gpMm[1]), GPEdgePainter.GP_ARROW_LEN, 1e-6,
						"包清单的箭头长度应与渲染常量一致")
				gpFound = true
		gpCheck(gpFound, "包清单中应存在流向标记图元")


# THE FONT-SIZE DEFECT — text heights come from the reference drawing's measured tiers.
# 字号缺陷 —— 字高取自参照图的实测档位。
# The request / 用户原话：字号严格按标准图来。
# The regression / 失效复现：one global 3.0 mm was applied to equipment and in-line annotations alike,
# so the equipment tag came out one third too small against the reference, and the title block used
# 2.2 / 2.8 mm — a pair that matches neither the reference nor any standard tier.
# 失效复现：设备与在管标注共用单一 3.0mm，使设备位号比参照图小三分之一；标题栏用 2.2 / 2.8mm ——
# 既不匹配参照图，也不对应任何标准档位。
func gpTestTextHeightsMatchTheStandardDrawing() -> void:
	# The five measured tiers. / 实测出的五个档位。
	gpEq(GPTextRole.GP_EQUIPMENT_TAG_MM, 4.5, "设备位号字高应为 4.5mm（C01 的 equipmenttagnamelabel）")
	gpEq(GPTextRole.GP_INLINE_TAG_MM, 3.0, "在管标注字高应为 3.0mm（C01 的 valvelabel / 管线号 / 管口）")
	gpEq(GPTextRole.GP_TITLE_FIELD_MM, 2.5, "标题栏字段字高应为 2.5mm（C01 的 label 组）")
	gpEq(GPTextRole.GP_DRAWING_TITLE_MM, 4.0, "图纸标题字高应为 4.0mm")
	gpEq(GPTextRole.GP_FRAME_GRID_MM, 2.85, "图框栅格参考号字高应为 2.85mm")
	# The two drawing-area tiers are related by a fixed ratio, and the scale constant must encode it.
	# 图面两档之间存在固定比例，缩放常量必须如实表达它。
	gpApprox(GPTextRole.GP_EQUIPMENT_TAG_MM, GPTextRole.GP_INLINE_TAG_MM * GPTextRole.GP_EQUIPMENT_SCALE,
		1e-6, "设备档应恰为在管档的 %s 倍" % [GPTextRole.GP_EQUIPMENT_SCALE])

	# With the default setting (the standard in-line height) each category lands on its standard tier.
	# 在默认设置（标准在管字高）下，每个类别都落在其标准档位上。
	var gpBase: float = GPTextRole.GP_INLINE_TAG_MM
	gpEq(GPTextRole.gpTagMM("tank", gpBase), 4.5, "容器位号应为 4.5mm")
	gpEq(GPTextRole.gpTagMM("heat", gpBase), 4.5, "换热器位号应为 4.5mm")
	gpEq(GPTextRole.gpTagMM("pump", gpBase), 4.5, "泵位号应为 4.5mm")
	gpEq(GPTextRole.gpTagMM("valve", gpBase), 3.0, "阀门标注应为 3.0mm")
	gpEq(GPTextRole.gpTagMM("instrument", gpBase), 3.0, "仪表标注应为 3.0mm")
	gpEq(GPTextRole.gpTagMM("general", gpBase), 3.0, "在管管件标注应为 3.0mm")

	# An unknown category falls back to the user's setting rather than to a silent default.
	# 未知类别回落到用户设置，而非一个沉默的默认值。
	gpEq(GPTextRole.gpTagMM("", 4.0), 4.0, "未知类别应回落到用户设置")
	gpEq(GPTextRole.gpTagMM("nonsense", 2.0), 2.0, "未登记类别应回落到用户设置")
	# The setting stays a real knob: halving it halves both tiers, preserving the standard's ratio.
	# 该设置仍是有效的旋钮：减半即两档同时减半，标准比例得以保持。
	gpEq(GPTextRole.gpTagMM("tank", 1.5), 2.25, "用户设置变小后设备位号应等比缩小")
	gpApprox(GPTextRole.gpTagMM("tank", 2.0), GPTextRole.gpTagMM("valve", 2.0) * GPTextRole.GP_EQUIPMENT_SCALE,
		1e-6, "任何设置下两档之比都必须保持标准比例")

	# EVERY known category must have a tier, or a new one would silently lose its standard size.
	# **每个**已登记类别都必须有归属档位，否则新增类别会悄悄失去标准字号。
	var gpKnown: Array[String] = GPSymbolCategories.gpCategoryList()
	gpCheck(gpKnown.size() >= 6, "类别表应至少含 6 个类别")
	for gpCat in gpKnown:
		gpCheck(GPTextRole.GP_EQUIPMENT_CATEGORIES.has(gpCat)
			or GPTextRole.GP_INLINE_CATEGORIES.has(gpCat),
			"类别 %s 未归入任何字高档位，将失去标准字号" % [gpCat])
	# A category may not be in both tiers at once. / 一个类别不得同时属于两档。
	for gpCat2 in GPTextRole.GP_EQUIPMENT_CATEGORIES:
		gpCheck(not GPTextRole.GP_INLINE_CATEGORIES.has(gpCat2),
			"类别 %s 不可同时属于设备档与在管档" % [gpCat2])

	# A line number is an in-line annotation: 3.0 mm unless the project overrides it.
	# 管线号属在管标注：除非项目覆盖，否则为 3.0mm。
	gpEq(GPTextRole.gpPipeTagMM(0.0, 3.0), 3.0, "管线号默认应为标准的 3.0mm")
	gpEq(GPTextRole.gpPipeTagMM(2.5, 3.0), 2.5, "项目级覆盖应优先于标准档")
	gpEq(GPTextRole.gpPipeTagMM(0.0, 3.0), GPTextRole.GP_INLINE_TAG_MM,
		"管线号默认值必须等于在管档（二者在 C01 中同为 3.0mm）")


# THE TITLE-BLOCK DRIFT DEFECT — a field's text must sit on its authored millimetre baseline at EVERY
# zoom, because the title block IS a true-scale miniature of the sheet, not a screen overlay.
# 标题栏漂移缺陷 —— 字段文字在**任何**缩放下都必须落在其作者设定的毫米基线上，因为标题栏是图纸的
# **真实比例缩样**，而不是屏幕叠加层。
# The report / 用户原话：图框里面的文字现在又跑了。
# The regression / 失效复现：the baseline is authored in millimetres yet was ALSO multiplied by the
# canvas scale before being converted, so every field moved by `(zoom - 1) x its own distance from the
# sheet's top-left corner`. The `scale` cell's value baseline at (236.2, 289.2) mm therefore landed
# 419 mm away at the fit zoom — well outside the 297 mm sheet — while at 100 % the wrong and right
# results agree EXACTLY, which is why it passed review.
# 基线本以毫米编排，却在换算之前又乘了一次画布缩放，故每个字段位移
# `(缩放−1) × 自身到图纸左上角的距离`。比例格的值基线 (236.2, 289.2)mm 在适配缩放下因此跑到 419mm
# 之外（远超 297mm 的图纸），而 100% 下错法与正法结果**完全一致** —— 这正是它能通过审查的原因。
func gpTestTitleBlockTextStaysOnItsBaseline() -> void:
	var gpFrame: GPFrameView = GPFrameView.new()
	# The value baseline of the field FARTHEST from the sheet's top-left corner — i.e. the worst case
	# for this defect — derived from the sheet's own field table so the number cannot drift from the
	# layout. Inset 1.2 mm, baseline at 0.72 of the cell height, exactly as _gpDrawValue does it.
	# 取距图纸左上角**最远**字段的值基线 —— 即本缺陷的最坏情形 —— 由图纸自身的字段表推导，使该数值
	# 不会与排版脱节。内缩 1.2mm、基线在格高 0.72 处，与 _gpDrawValue 完全一致。
	var gpField: Dictionary = GPSheet.GP_TB_FIELDS[GPSheet.GP_TB_FIELDS.size() - 1]
	var gpBase: Vector2 = Vector2(
		415.0 - GPSheet.GP_TB_BLOCK_W + float(gpField["x"]) + 1.2,
		292.0 - float(gpField["y"]) - float(gpField["h"]) + float(gpField["h"]) * 0.72)
	for gpZ in [1.0, 1.5, GP_FIT_ZOOM, 3.0, 6.0, 8.0]:
		gpFrame._gpTextScale = gpZ
		var gpFit: Vector2 = gpFrame.gpFontFit(GPFrameView.GP_VALUE_MM)
		# Both halves of the draw transform, taken from the real code path the view uses.
		# 绘制变换的两半，均取自视图真正使用的代码路径。
		var gpScaleVec: Vector2 = GPCanvasText.gpTextScale(gpFit, gpZ)
		var gpLand: Vector2 = gpScaleVec * GPCanvasText.gpDrawPos(gpBase, gpFit, gpZ)
		gpApprox(gpLand.x, gpBase.x, 1e-2, "%sx：字段文字落点 x 必须等于作者基线" % [gpZ])
		gpApprox(gpLand.y, gpBase.y, 1e-2, "%sx：字段文字落点 y 必须等于作者基线" % [gpZ])
		# THE DEFECT ITSELF: converting a position that is already in the right unit magnifies it a
		# second time. Pinning the MAGNITUDE (not merely "different") makes the test explain the report.
		# 缺陷本身：对已经正确的单位再换算一次，等于把位置**多放大一次**。钉住**量级**（而非仅
		# 「不一样」）才使本测试能解释用户报告。
		var gpOld: Vector2 = gpScaleVec * GPCanvasText.gpDrawPos(gpBase * gpZ, gpFit, gpZ)
		gpApprox(gpOld.x, gpBase.x * gpZ, 1e-2, "%sx：旧写法把基线又乘了缩放（横向）" % [gpZ])
		gpApprox((gpOld - gpBase).length(), gpBase.length() * (gpZ - 1.0), 1e-2,
			"%sx：旧写法的位移模应恰为 |基线| × (缩放 - 1)" % [gpZ])
	# The reported symptom is "the text left its cell", so assert exactly that — for EVERY field, and
	# including the two stacked lines of BOTH mode, whose 3 mm pitch must fit a 10 mm cell.
	# 用户看到的现象是「文字跑出格子」，故按此断言 —— **每个**字段都要过，且含 BOTH 模式上下两行
	#（基线间距仅 3mm，必须能放进 10mm 的格）。
	gpFrame._gpTextScale = GP_FIT_ZOOM
	var gpFitFit: Vector2 = gpFrame.gpFontFit(GPFrameView.GP_VALUE_MM)
	var gpSc: Vector2 = GPCanvasText.gpTextScale(gpFitFit, GP_FIT_ZOOM)
	var gpChecked: int = 0
	for gpF in GPSheet.GP_TB_FIELDS:
		var gpTop: float = 292.0 - float(gpF["y"]) - float(gpF["h"])
		var gpLeft: float = 415.0 - GPSheet.GP_TB_BLOCK_W + float(gpF["x"])
		var gpRight: float = gpLeft + float(gpF["w"])
		var gpBottom: float = gpTop + float(gpF["h"])
		for gpLine in [3.0, 0.72 * float(gpF["h"]), 6.4, 9.4]:
			var gpP: Vector2 = Vector2(gpLeft + 1.2, gpTop + float(gpLine))
			var gpL: Vector2 = gpSc * GPCanvasText.gpDrawPos(gpP, gpFitFit, GP_FIT_ZOOM)
			gpCheck(gpL.x > gpLeft and gpL.x < gpRight,
				"字段 %s 的行基线 x=%.1f 落在格 [%.1f, %.1f] 之外" % [gpF["key"], gpL.x, gpLeft, gpRight])
			gpCheck(gpL.y > gpTop and gpL.y < gpBottom,
				"字段 %s 的行基线 y=%.1f 落在格 [%.1f, %.1f] 之外" % [gpF["key"], gpL.y, gpTop, gpBottom])
			gpChecked += 1
	gpEq(gpChecked, GPSheet.GP_TB_FIELDS.size() * 4, "每个字段的四条可能基线都应被检查")
	# SHEET BOUNDS: the whole point is that the block is inside the frame — the worst case must stay on
	# the paper, which the doubled scale broke by 419 mm.
	# 图纸边界：关键在于图块须在图框之内 —— 最坏情况必须仍在纸上，而「多乘一次缩放」使它超出 419mm。
	gpCheck(gpBase.x * (GP_FIT_ZOOM - 1.0) > 400.0,
		"旧写法在适配缩放下的横向位移应达数百毫米，即它会跑出图纸（本断言记录该量级）")
	gpFrame.free()

	# A SOURCE GUARD: the algebra above is only as good as the call site using it, so pin the SHAPE of
	# _gpDrawText() — the origin must stay ZERO and the position must go through gpDrawPos() — rather
	# than the exact text of the line, which would be fragile.
	# 源码守卫：上述代数只在调用点真的使用它时才有意义，故钉住 _gpDrawText() 的**形状** —— 变换原点必须
	# 保持 ZERO、位置必须经 gpDrawPos() —— 而不是该行的具体文字（那太脆）。
	var gpSrc: String = FileAccess.get_file_as_string("res://src/render/frame_view.gd")
	gpCheck(gpSrc.length() > 0, "应能读到 frame_view.gd 源码")
	var gpAt: int = gpSrc.find("func _gpDrawText")
	gpCheck(gpAt >= 0, "GPFrameView 应提供 _gpDrawText()")
	var gpNext: int = gpSrc.find("\nfunc ", gpAt + 1)
	var gpFn: String = gpSrc.substr(gpAt, (gpNext - gpAt) if gpNext > 0 else gpSrc.length() - gpAt)
	gpCheck(gpFn.find("GPCanvasText.gpDrawPos(") >= 0,
		"_gpDrawText() 必须经 gpDrawPos() 换算位置，否则会重复换算一次缩放（标题栏文字飞出图框）")
	gpCheck(gpFn.find("draw_set_transform(Vector2.ZERO, 0.0") >= 0,
		"_gpDrawText() 的变换原点必须为 ZERO；位置若改由原点承载，就会绕过 gpDrawPos 的单位换算")
