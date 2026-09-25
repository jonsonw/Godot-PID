class_name GPCanvasText
extends RefCounted
# Copyright © 2026 Jonson Wang
# Canvas text sizing: the single place where a sheet text height in MILLIMETRES becomes the font
# size in PIXELS handed to draw_string.
# 画布文字字号：把「毫米图面字高」换算成「交给 draw_string 的像素字号」的唯一出处。
#
# WHY THIS EXISTS / 为何需要本类：
# Canvas text is drawn inside gpWorldRoot, which the camera magnifies by the zoom (about 2.1x at
# fit-to-sheet). Handing draw_string the sheet height in millimetres — 3.0 mm becoming font_size 3
# — produces a glyph BITMAP 3 px tall which the world transform then magnifies onto the screen. The
# result is a grey smudge for every tag, no matter which font family is selected: the family is not
# what is blurry, the raster size is. Text must be rasterised at the size it actually occupies, so
# callers draw inside a frame whose unit is one DESIGN PIXEL (see gpCounterScale) and ask this class
# for the pixel size to use there.
# 画布文字绘制在 gpWorldRoot 之内，相机以缩放（适配图幅时约 2.1×）放大它。若把毫米图面字高直接
# 交给 draw_string —— 3.0mm 变成 font_size 3 —— 得到的字模只有 3px 高，再由世界变换放大贴到屏幕
# 上。其后果是**每个位号都糊成一团灰**，且换任何字族都一样：发虚的不是字族，是字模分辨率。文字
# 必须按其**实际占用的尺寸**光栅化，故调用方在一个「单位为 1 设计像素」的坐标系内绘制
#（见 gpCounterScale），并向本类索取该坐标系内的字号。
#
# TWO POLICIES, TWO FUNCTIONS / 两种策略，两个函数：
# gpLabelFontFit() is for READING text (tags, labels): the true sheet size, but never below a floor
# expressed in PHYSICAL pixels. gpExactFontFit() is for TRUE-SCALE text (the title block), whose
# authored millimetre layout must stay exact and therefore takes no floor at all.
# gpLabelFontFit() 用于**供阅读**的文字（位号、标签）：取真实图面尺寸，但不得低于以**物理像素**
# 表达的下限。gpExactFontFit() 用于**真实比例**文字（标题栏）：其作者毫米排布必须保持精确，故完全
# 不取下限。
#
# Both return an (integer size, residual) PAIR rather than a bare size — see gpFontFit for why a size
# alone cannot express a sheet height.
# 两者都返回（整数字号, 残差）**成对**值，而非单一个字号 —— 单靠字号无法表达图面字高的原因见 gpFontFit。
#
# WHY THE FLOOR IS IN PHYSICAL PIXELS / 为何下限以物理像素计：
# Design pixels are not what the user sees. On a Retina display one design pixel is about 2.14
# physical pixels, so a floor written in design pixels demands a glyph twice as tall as intended —
# which is how a 3 mm tag ended up drawn larger than the 4x2 mm valve it labels. Measuring the floor
# in physical pixels makes it a no-op on a dense display and the safety net on a plain one.
# 设计像素并非用户所见。Retina 屏上 1 设计像素约等于 2.14 物理像素，故以设计像素书写的下限会要求
# 一个两倍高的字形 —— 3mm 位号正是因此被画得比它所标注的 4×2mm 阀门还大。改用物理像素衡量下限，
# 使它在高密度屏上不生效、在普通屏上才是安全网。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Smallest legible glyph height in PHYSICAL pixels — the display analogue of GPEdgeStyle.GP_MIN_PX,
# which protects line widths the same way.
# 最小可读字高（**物理**像素）—— 即 GPEdgeStyle.GP_MIN_PX 在显示侧的对应物，后者以同样方式保护线宽。
const GP_MIN_DEVICE_PX: float = 10.0

# Largest glyph height ever requested. Guards the glyph cache against an extreme zoom or an extreme
# font-size setting; it is a ceiling, never a target.
# 实际请求过的最大字高。用于防止极端缩放或极端字号设置撑爆字形缓存；它只是上限，从不是目标值。
const GP_MAX_PX: float = 48.0


# Tag / label font: the true sheet height, floored at GP_MIN_DEVICE_PX physical pixels, returned as
# (integer font size, residual factor) — see gpFontFit.
# 位号 / 标签字号：真实图面字高，并以 GP_MIN_DEVICE_PX 物理像素兜底；形如（整数取整字号, 残差系数）
# —— 见 gpFontFit。
# [param gpMM] sheet text height in millimetres / 图面字高（毫米）
# [param gpItem] a canvas item under gpWorldRoot, used to read both scales / gpWorldRoot 之下的画布项，
#   用于读取两种缩放
static func gpLabelFontFit(gpMM: float, gpItem: CanvasItem) -> Vector2:
	return gpFontFit(gpMM, gpScaleOf(gpItem), gpDeviceScaleOf(gpItem))


# True-scale font with NO legibility floor, as (integer font size, residual factor).
# 真实比例字号，**不含**可读性下限；形如（整数取整字号, 残差系数）。
# The title block needs the no-floor policy: its cells are authored in millimetres with a 3 mm
# baseline pitch, so a floor tall enough to help would make two stacked lines overlap.
# 标题栏需要「无下限」这一策略：其单元格以毫米编排、基线间距仅 3mm，任何足够大的下限都会让上下两行重叠。
static func gpExactFontFit(gpMM: float, gpScale: float) -> Vector2:
	return gpFontFit(gpMM, gpScale, 1.0, 0.0)


# THE ONE CONVERSION, RETURNED AS A PAIR / 唯一的换算，成对返回：
#   x = the integer font size handed to draw_string;
#   y = the residual factor (wanted size / integer size), about 1.0.
# A font size is an INTEGER PIXEL COUNT, so a 4.5 mm tag at fit zoom asks for 9.548 px and gets 10 —
# drawn 4.7 % too tall. Two tiers rounding in OPPOSITE directions then wreck the ratio the reference
# drawing prescribes (measured 1.778 instead of 4.5 : 3.0 = 1.500). Multiplying the residual into the
# draw transform — scaled about the text's own origin, so positions never move — restores the sheet
# height exactly. The cost is a resample of at most 1/(2*want) ≈ 6 %, far below the magnification that
# causes the blur this pipeline exists to prevent; at zooms where the product is integral (6x, 8x…)
# the residual is exactly 1.0 and nothing is resampled at all.
# 字号是**整数像素**，故适配缩放下 4.5mm 位号需要 9.548px、却只能给 10px —— 画出来高 4.7%。
# 两个档位若朝**相反方向**取整，还会毁掉参照图规定的比例（实测 1.778，应为 4.5:3.0 = 1.500）。
# 把残差乘进绘制变换（**绕文字自身原点**缩放，位置不受影响）即可严格还原图面字高。代价是至多
# 1/(2*want) ≈ 6% 的重采样，远低于会造成发虚的放大倍率；而在乘积恰为整数的缩放（6x、8x…）下残差
# 正好是 1.0，完全不重采样。
# [param gpMinDevicePx] legibility floor in PHYSICAL pixels; 0 disables it / 可读性下限（物理像素），0 关闭
static func gpFontFit(gpMM: float, gpScale: float, gpDeviceScale: float = 1.0,
		gpMinDevicePx: float = GP_MIN_DEVICE_PX) -> Vector2:
	var gpWant: float = gpScreenPx(gpMM, gpScale, gpDeviceScale, gpMinDevicePx)
	var gpPx: float = maxf(1.0, round(gpWant))
	return Vector2(gpPx, gpWant / gpPx)


# The shared conversion: mm -> design pixels, floored in physical pixels and capped for the cache.
# 共用换算：毫米 → 设计像素，以物理像素兜底，并设字形缓存上限。
# [param gpDeviceScale] physical pixels per design pixel / 每设计像素对应的物理像素
# [param gpMinDevicePx] legibility floor in physical pixels; 0 disables it / 可读性下限（物理像素），
#   0 表示关闭
static func gpScreenPx(gpMM: float, gpScale: float, gpDeviceScale: float = 1.0,
		gpMinDevicePx: float = GP_MIN_DEVICE_PX) -> float:
	var gpDPI: float = maxf(gpDeviceScale, 0.0001)
	var gpFloor: float = maxf(gpMinDevicePx, 0.0) / gpDPI
	return clampf(gpMM * maxf(gpScale, 0.0001), maxf(gpFloor, 0.0001), GP_MAX_PX)


# Draw-transform scale that cancels the parent magnification, making one draw unit equal one design
# pixel. Pair it with the font size from above and with coordinates multiplied by gpScale.
# 抵消父级放大的绘制变换缩放，使 1 绘制单位等于 1 设计像素。需与上述字号配对，坐标则乘以 gpScale。
static func gpCounterScale(gpScale: float) -> Vector2:
	var gpK: float = 1.0 / maxf(gpScale, 0.0001)
	return Vector2(gpK, gpK)


# Draw-transform scale for text drawn inside a frame whose unit is one design pixel: it cancels the
# parent magnification AND carries the residual of gpFontFit, so one draw unit is one design pixel and
# the glyph lands at exactly the requested sheet height. Every TEXT draw site uses this one;
# gpCounterScale() itself stays for anything that must be one design pixel at true size.
# 供「单位为 1 设计像素」的绘制坐标系使用的缩放：既抵消父级放大，也带上 gpFontFit 的残差，使
# 1 绘制单位 == 1 设计像素，且字形恰好落在所要求的图面字高上。所有**文字**绘制点统一用它；
# gpCounterScale() 本身保留给「必须严格等于 1 设计像素」的绘制。
static func gpTextScale(gpFit: Vector2, gpScale: float) -> Vector2:
	return gpCounterScale(gpScale) * gpFit.y


# The coordinate to hand draw_string so that a text authored at gpLocalPos in the ITEM'S OWN UNIT
# (millimetres on the sheet) is painted exactly there, when the draw transform is
# gpTextScale(gpFit, gpScale).
# 在绘制变换为 gpTextScale(gpFit, gpScale) 时，为「以**本项自身单位（图纸毫米）**编排于
# gpLocalPos 的文字」求应交给 draw_string 的坐标，使文字恰好落在该处。
#
# WHY THIS FUNCTION EXISTS — a transform maps a drawn point `p` to `origin + scale * p`, so the SCALE
# applies to drawn coordinates while the ORIGIN passes through untouched. A caller holding a
# millimetre position therefore has two valid shapes and one trap:
#   1. put the millimetre value straight in the transform's ORIGIN (nothing to convert — see
#      GPEdgePainter.gpDrawTag, which needs the origin anyway to carry the rotation); or
#   2. keep the origin at ZERO and pass this function's result as the coordinate.
# The trap is a THIRD shape: passing the millimetre value through this function AND then putting it in
# the origin, i.e. converting a position that was already in the right unit. That multiplies it by the
# zoom a second time and displaces the text by `(zoom - 1) x its own distance from the sheet corner` —
# 0 at 100 %, which is why it passes review, and ~1.1x off at the fit zoom, which threw the whole title
# block out of its frame. Both shapes are pinned by tests; the third is asserted to differ.
# 为何需要本函数 —— 变换把绘制点 p 映射为 `origin + scale * p`：**缩放作用于绘制坐标，原点原样通过**。
# 故持有毫米坐标的调用方有两种正确写法与一个陷阱：
#   1. 直接把毫米值放进变换的**原点**（无需换算 —— 见 GPEdgePainter.gpDrawTag，它本就需要原点承载旋转）；
#   2. 让原点保持 ZERO，把本函数的返回值作为坐标传入。
# 陷阱是**第三种**写法：先经本函数换算、又把结果放进原点 —— 也就是对已经正确的单位再换算一次。这会使
# 坐标被缩放乘第二次，令文字位移 `(缩放−1) × 自身到图纸角点的距离` —— 100% 下恰为 0（故能通过审查），
# 而在适配缩放下偏移约 1.1 倍，足以把整个标题栏甩出图框。前两种写法均有测试钉住，第三种则被断言为不等。
# [param gpLocalPos] position in the item's own unit, e.g. millimetres / 本项自身单位下的位置，如毫米
# [param gpFit] (integer font size, residual) from gpFontFit / 来自 gpFontFit 的（整数号, 残差）
# [param gpScale] the item's accumulated scale / 本项的累积缩放
static func gpDrawPos(gpLocalPos: Vector2, gpFit: Vector2, gpScale: float) -> Vector2:
	return gpLocalPos * maxf(gpScale, 0.0001) / maxf(gpFit.y, 0.0001)


# The accumulated scale of a canvas item under gpWorldRoot: the camera zoom times any nested scale.
# Reading it from the transform rather than plumbing it through keeps one source of truth.
# gpWorldRoot 之下某个画布项的累积缩放：相机缩放与任何嵌套缩放的乘积。从变换读取而非层层传递，
# 保持单一来源。
static func gpScaleOf(gpItem: CanvasItem) -> float:
	if gpItem == null or not gpItem.is_inside_tree():
		return 1.0
	return maxf(absf(gpItem.get_global_transform().get_scale().x), 0.0001)


# Physical pixels per design pixel, as the viewport is actually presenting the canvas (1.0 on a
# plain display, about 2.14 on a Retina one). Read from the item so callers need no viewport
# plumbing, and defaulted to 1.0 outside a tree so pure arithmetic stays testable.
# 视口当前呈现画布时的「物理像素 / 设计像素」（普通屏为 1.0，Retina 约 2.14）。从画布项读取，使
# 调用方无需接线视口；不在树内时回落 1.0，使纯算术仍可测试。
static func gpDeviceScaleOf(gpItem: CanvasItem) -> float:
	if gpItem == null or not gpItem.is_inside_tree():
		return 1.0
	return maxf(gpItem.get_viewport().get_screen_transform().get_scale().y, 0.0001)
