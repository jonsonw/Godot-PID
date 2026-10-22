class_name GPSheet
extends RefCounted

# One drawing sheet (tab) inside a project: an identity plus its own node/edge graph.
# 工程中的一张图纸（标签页）：一个标识 + 它自己的节点/边图。
# WHY A SEPARATE MODEL / 为何单独建模型：
# a multi-sheet P&ID is not one big graph, it is SEVERAL graphs that share a project's
# library and numbering rules. Modelling a sheet as a slice of one graph would force every
# cross-sheet edit to renumber global indices; modelling it as its own graph keeps each tab
# independently editable, which is how a drawing office actually works.
# 多图纸 P&ID 不是一张大图，而是**若干张**共享工程图元库与编号规则的图。
# 把图纸建模为一张图的分片，会迫使每次跨页编辑都重排全局索引；把它建模为各自的图，
# 则每个标签页都能独立编辑 —— 这正是设计院的实际工作方式。
# Project-level data (meta, tag_rules, embedded packs) lives on the CONTAINER, not here:
# one project has one set of numbering rules, however many sheets it has.
# 工程级数据（meta、tag_rules、内嵌图元包）位于**容器**而非此处：
# 一个工程只有一套编号规则，无论它有多少张图纸。
# See 持久化实现方案 §6 (v3 sheets[]) / 见「持久化实现方案」§6。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

# A SHEET-LEVEL field changed (Rev.3 stage 0c). Today only the frame margins can change, but the
# signal is deliberately not named after them: stage 1 adds the title block's anchor / offset, and
# both must reach the canvas through ONE channel so the frame view, the dirty flag and the repaint
# cannot be wired up three different ways.
# **图纸级**字段发生变化（Rev.3 阶段 0c）。今天只有图框边距会变，但信号刻意不以它命名：阶段 1 还要
# 加图签的锚角 / 偏移，而两者都必须经**同一条**通道到达画布，否则图框视图、脏标记与重绘会被接三遍。
#
# ⚠️ EMITTED BY THE COMMAND, NOT BY THE SETTER — and that is load-bearing. gpSetFrameMargins() is also
# the live-preview write during a drag (dozens of writes per second); if IT emitted, every mouse move
# would mark the document dirty and broadcast on the app bus. The command emits exactly once, when the
# drag is committed as one undo step — the same split GPSetLabelOffsetCommand uses for tag drags.
# ⚠️ 由**命令**发射，而不是由 setter 发射 —— 这一点是承重的。gpSetFrameMargins() 同时是拖拽过程中的
# 实时预览写口（每秒数十次）；若由它发射，每一次鼠标移动都会把文档标脏并向应用总线广播。命令只在拖拽
# 被提交为**一个撤销步**时发射一次 —— 与 GPSetLabelOffsetCommand 对位号拖拽所用的同一分工。
signal gpSheetChanged()

# Stable sheet identity. Persisted so a re-open keeps the same id even if tabs are reordered.
# 稳定的图纸标识。持久化保存，使重新打开时即使标签重排也保持同一 id。
var gpId: String = ""

# Human-readable tab title. / 人类可读的标签标题。
var gpName: String = ""

# Position in the tab bar (0-based). Re-derived on load, so a gap never appears.
# 在标签栏中的位置（从 0 起）。载入时重新推导，故永不出现空位。
var gpIndex: int = 0

# The sheet's own geometry. Never null after gpFromDict().
# 本图纸自己的几何。经 gpFromDict() 后绝不为 null。
var gpGraph: GPPIDGraph = null

# Physical sheet size in millimetres. The whole editor adopts "1 world unit == 1 mm"
# from v0.1 (see plan Phase 0), so coordinates, symbol sizes, line weights and fonts are all
# expressed in mm. DEFAULT IS A1 (841 x 594 mm, landscape) since 2026-10-16 — the user rebased
# the default sheet onto the internationally recommended P&ID size, one linear ×2 over the old
# A3 default (see gpFrameScale for the one-scale rule that keeps every frame furnishing in step).
# ⚠️ gpFromDict's missing-key fallback stays 420/297: a pre-A1 archive is by definition an A3-era
# drawing, and reopening it must not silently grow the paper.
# 图纸物理尺寸（毫米）。从 v0.1 起编辑器统一采用「1 世界单位 = 1mm」（见计划 Phase 0），
# 故坐标、图元尺寸、线宽、字号均以 mm 计。自 2026-10-16 起**默认图幅为 A1**（841×594mm，横向）
# —— 用户把默认图纸重定基到国际推荐的 P&ID 图幅，线性恰为旧 A3 默认值的 ×2（框架陈设如何跟上
# 这一步见 gpFrameScale 的一把尺规则）。
# ⚠️ gpFromDict 的缺键回落**保持** 420/297：A1 之前的存档按定义就是 A3 时代的图纸，
# 重新打开不得悄悄放大纸面。
var gpWidthMM: float = 841.0
var gpHeightMM: float = 594.0

# ---------------------------------------------------------------------------
# 图幅视觉比例（A1 重定基，2026-10-16） / Frame visual scale (A1 rebase)
# ---------------------------------------------------------------------------
# WHY ONE SCALE AND NOT A TABLE OF DOUBLED CONSTANTS / 为何是一把尺、不是一张翻倍的常量表：
# every frame furnishing (title block, its cell grid, margins-by-default, line weights, the three
# title-block text tiers) was measured on the A3-era reference. Doubling each constant would change
# what an OLD A3-era archive renders, and a future A0/A2 would need the table again. Instead the
# furnishing constants keep their A3-era values and are multiplied by ONE derived factor:
# 长边/420 —— A1 = 2.0, A3 = 1.0, and a custom size interpolates continuously. A drawing therefore
# looks the same at any size, and a pre-A1 archive (still A3) multiplies by exactly 1.0 — bit-stable.
# 每一项图框陈设（图签、格网、默认边距、线宽、图签三档字高）都是按 A3 时代参照图实测的。逐个翻倍
# 会改变旧 A3 存档的渲染结果，而未来的 A0/A2 又要把表再列一遍。故陈设常量保持 A3 时代的值，统一
# 乘一个推导因子：长边 / 420 —— A1 = 2.0、A3 = 1.0，自定尺寸连续内插。任何图幅观感一致，而 A1 之前
# 的存档（仍是 A3）恰好乘 1.0 —— 逐位不变。
# ⚠️ WHAT DOES NOT SCALE / ⚠️ 什么**不**乘：symbol sizes (they live in DATA — GP_NOMINAL and the
# pack manifests were rebased ×2 instead) and screen-pixel thresholds (GP_MIN_PX etc.). The tag
# text tiers in GPTextRole scale with the SYMBOLS (also rebased), NOT with this factor — only the
# three title-block/frame tiers ride on it.
# 图元尺寸**不**乘（它们活在**数据**里 —— GP_NOMINAL 与包 manifest 已按 ×2 重定基），屏幕像素阈值
# （GP_MIN_PX 等）也不乘。GPTextRole 的图面字高档随**图元**（同样已重定基）、不随本因子 —— 只有
# 图签/图框的三档字高搭这把尺。
func gpFrameScale() -> float:
	return maxf(gpWidthMM, gpHeightMM) / 420.0


# The title-block size for THIS sheet, in mm: the A3-era constants times the sheet's own scale.
# 本图纸的图签尺寸（mm）：A3 时代常量 × 图纸自身的比例。
# ⚠️ DERIVED, NEVER STORED — same discipline as the block's position (stage 1): the raw constants
# stay the single source (tests pin them), and every consumer that holds a sheet asks here instead
# of reading the constants directly.
# ⚠️ 推导、永不存储 —— 与图签的位置（阶段 1）同一纪律：原始常量保持唯一事实源（测试钉住），
# 任何持有图纸的消费方都来此处询问，而不是直接读常量。
func gpTbBlockSize() -> Vector2:
	return Vector2(GP_TB_BLOCK_W, GP_TB_BLOCK_H) * gpFrameScale()


# Whether the drawing frame + title block is drawn for this sheet (see plan Phase 2).
# 本图纸是否绘制图框 + 标题栏（见计划 Phase 2）。
var gpFrameOn: bool = true

# ---------------------------------------------------------------------------
# 图框边距（数据化，Rev.3 阶段 0a） / Frame margins (data, Rev.3 stage 0a)
# ---------------------------------------------------------------------------
# WHY MARGINS ARE DATA AND NOT RENDERER CONSTANTS / 为何边距是数据而非渲染器常量：
# they used to be two `const`s inside GPFrameView, which made the frame immovable BY DESIGN —
# there simply was no writable position field anywhere. Rev.3 promotes the frame to a movable
# constraint base (draggable, with its margins editable), so the margins must travel with the
# SHEET. Keeping them in the renderer would mean two copies of the same fact as soon as any UI
# could change them.
# 它们原是 GPFrameView 内的两个 `const`，这使图框在**设计上**不可移动 —— 根本没有可写的位置
# 字段。Rev.3 把图框升为可移动的约束基座（可拖动、边距可改），故边距必须随**图纸**走。留在
# 渲染器里意味着一旦有任何界面能改它们，同一事实就有两份。
# The DEFAULTS ARE THE OLD CONSTANTS, so a sheet that never touched its frame renders
# byte-identically to before, and (per ADR-7) writes no new key at all.
# 默认值即原常量，故从未动过图框的图纸渲染结果与从前逐字节一致，且（依 ADR-7）完全不写出新键。
# The binding edge (left) is wider, per GB/T 14689 / ISO 5457.
# 装订边（左）更宽，依 GB/T 14689 / ISO 5457。
#
# ⚠️ A3-ERA BASELINE, NOT THE DEFAULT FOR EVERY SHEET / ⚠️ 这是 A3 时代的**基准**，不是每张图纸的默认：
# since the A1 rebase (2026-10-16) the margins a sheet starts with depend on its PAPER SIZE — see
# gpDefaultMarginsFor(). This constant stays so a pre-A1 archive that never wrote frame_margins
# keeps falling back to exactly the values it was drawn with (byte-stable reopen).
# 自 A1 重定基（2026-10-16）起，图纸的初始边距取决于**纸幅** —— 见 gpDefaultMarginsFor()。本常量
# 保留，使未写出 frame_margins 键的 A1 之前存档仍回落到它被绘制时的那组值（重开逐字节稳定）。
const GP_FRAME_MARGINS_DEFAULT: Array = [25.0, 5.0, 5.0, 5.0]

# The margins a NEW sheet of the given paper size starts with, as [left, top, right, bottom] in mm.
# 给定纸幅的**新**图纸的初始边距，形如 [左, 上, 右, 下]（mm）。
# GB/T 14689 filing format: the two large formats (A0/A1) take a 25 mm filing edge and 10 mm on
# the other three sides; A2/A3/A4 keep 25 mm on the filing edge and 5 mm elsewhere. (ISO 5457
# differs — 20 mm for A0-A3 and 10 mm all round for A4 — this project follows GB/T 14689.)
# The A3-era values remain the fallback for every custom size, so a pre-A1 archive that never
# wrote frame_margins still re-derives exactly what it was drawn with.
# GB/T 14689 装订幅面：A0/A1 两种大幅面取 25mm 装订边、其余三边 10mm；A2/A3/A4 保持装订边
# 25mm、其余 5mm。（ISO 5457 不同 —— A0-A3 为 20mm、A4 四边 10mm —— 本项目采用 GB/T 14689。）
# 自定尺寸仍回落到 A3 时代值，使未写出 frame_margins 的 A1 之前存档仍精确重推它被绘制时的那组数。
static func gpDefaultMarginsFor(gpW: float, gpH: float) -> Array:
	if _gpPaperIs(gpW, gpH, 1189.0, 841.0) or _gpPaperIs(gpW, gpH, 841.0, 594.0):
		return [25.0, 10.0, 10.0, 10.0]
	return GP_FRAME_MARGINS_DEFAULT.duplicate()


# Whether a paper size matches a preset within the printing tolerance.
# 纸幅是否在印刷容差内匹配某预设。
static func _gpPaperIs(gpW: float, gpH: float, gpPW: float, gpPH: float) -> bool:
	return absf(gpW - gpPW) < 0.5 and absf(gpH - gpPH) < 0.5


# Infer the symbol scale from a RAW sheet dictionary (before gpFromDict builds the object).
# 由**原始**图纸字典推断图元尺度（在 gpFromDict 建对象之前）。
#
# Exposed so the project reader can set the shared library's scale BEFORE rebuilding sheets:
# otherwise a user pack would be registered while the PREVIOUS document's scale is still
# active, and legacy packs would be base-scaled twice.
# 公开给工程读取方，使它在重建图纸**之前**设置共享图库尺度：否则用户包会在**上一份**
# 文档的尺度仍生效时注册，旧档用户包会被二次缩放。
static func gpScaleForSheetDict(gpD: Dictionary) -> float:
	var gpSS: Variant = gpD.get("symbol_scale", null)
	if gpSS is float or gpSS is int:
		return clampf(float(gpSS), 0.1, 10.0)
	return _gpScaleFromMeta(gpD.get("meta", {}),
		float(gpD.get("width_mm", 420.0)), float(gpD.get("height_mm", 297.0)))


# Infer the symbol scale for an archive that carries no per-sheet key (P0-5).
# 为没有逐图纸键的存档推断图元尺度（P0-5）。
#
# Precedence / 优先级：
#   1. meta.symbol_scale — the explicit project-era marker written by every new save;
#   2. A1 paper — the rebased default, so treated as full-scale even without a marker;
#   3. anything else — a pre-A1 archive, i.e. 0.5.
#   1. meta.symbol_scale —— 每次新保存都写出的工程世代显式标记；
#   2. A1 纸幅 —— 重定基后的默认图幅，无标记也按全尺度；
#   3. 其余 —— A1 之前存档，即 0.5。
# ⚠️ The only ambiguous window is an A3/A2/A0 archive saved by the 2-day A1-rebase build
# BEFORE this marker existed; it is treated as legacy. A1 archives (the rebased default)
# are not affected.
# ⚠️ 唯一模糊窗口：在本标记出现**之前**、由 A1 重定基那两天的构建保存的 A3/A2/A0 存档；
# 它会被当作旧档。A1 存档（重定基默认）不受影响。
static func _gpScaleFromMeta(gpMetaV: Variant, gpW: float, gpH: float) -> float:
	if gpMetaV is Dictionary:
		var gpMeta: Dictionary = gpMetaV as Dictionary
		var gpV: Variant = gpMeta.get("symbol_scale", null)
		if gpV is float or gpV is int:
			return clampf(float(gpV), 0.1, 10.0)
	if _gpPaperIs(gpW, gpH, 841.0, 594.0):
		return 1.0
	return 0.5

# Smallest inner rectangle the frame may be reduced to, along either axis, in mm — the ONLY
# constraint the margins carry (Rev.3 amendment, 2026-10-16).
# 内框在任一方向上可被缩到的最小值（mm）—— 它是边距身上**唯一**的约束（Rev.3 修正，2026-10-16）。
#
# ⚠️ THE PAPER IS NO LONGER A CONSTRAINT / 纸面不再是约束：before this amendment the rule was "every
# margin >= 1 mm, measured from the paper edge" (the retired GP_FRAME_MARGIN_MIN), which confined the
# frame to the sheet and made a free move impossible. That rule was REVERSED on the user's explicit
# request — 「自由移动，没有限制」: the frame is an ordinary object that may sit wholly off the paper,
# so a margin MAY be negative, which is exactly what "that frame line lies outside the sheet" means.
# ⚠️ 本次修正之前，规则是「每条边距 >= 1mm，自纸边量起」（已退役的 GP_FRAME_MARGIN_MIN），它把图框锁在
# 纸上、使自由移动不可能。该规则已按用户明确要求**作废**（「自由移动，没有限制」）：图框是普通对象，可以
# 整块落在纸外，故边距**可以为负** —— 这恰恰就是「该条图框线位于纸面之外」的意思。
#
# What survives is the frame's OWN consistency: it must not be turned INSIDE OUT, because a
# zero-or-negative-size rectangle is neither drawn nor grabbable (see gpFrameSideAt / gpSideMidpoints,
# which bail on `size <= 0`), so the user would have to undo to get their frame back — the precise
# failure they rejected when choosing this option. The bound therefore speaks about the INNER
# RECTANGLE's dimension, never about a single margin, which is why it cannot be written as a
# per-element minimum.
# 活下来的是图框**自身**的自洽：它不得**内翻**。尺寸为零或负的矩形既不被绘制、也无法抓取（见
# gpFrameSideAt / gpSideMidpoints，二者遇 `size <= 0` 即退回），用户只能靠撤销才能把图框要回来 ——
# 而这正是用户在选定本口径时明确否决的那种失效。故该上下限说的是**内框**的尺寸、绝不是某一条边距，这也
# 正是它无法写成逐元素下限的原因。
const GP_FRAME_MIN_SIZE_MM: float = 1.0

# Index names for gpFrameMargins, so call sites never carry bare 0..3 literals.
# gpFrameMargins 的下标名，使调用点不出现裸 0..3 字面量。
const GP_MARGIN_LEFT: int = 0
const GP_MARGIN_TOP: int = 1
const GP_MARGIN_RIGHT: int = 2
const GP_MARGIN_BOTTOM: int = 3

# Frame margins in mm, ordered [left, top, right, bottom] — FREE REAL NUMBERS, not confined to the
# paper: a negative margin means that frame line lies outside the sheet.
# 图框边距（mm），顺序为 [左, 上, 右, 下] —— **自由实数**，不受纸面约束：边距为负意味着该条图框线落在
# 纸面之外。
# Always 4 entries; the only sanctioned way to change them is gpSetFrameMargins(), which maintains the
# one surviving invariant (see GP_FRAME_MIN_SIZE_MM).
# 恒为 4 项；唯一被认可的修改途径是 gpSetFrameMargins()，它维护唯一剩下的那条不变量（见
# GP_FRAME_MIN_SIZE_MM）。
var gpFrameMargins: Array = GP_FRAME_MARGINS_DEFAULT.duplicate()

# ---------------------------------------------------------------------------
# 图纸原点（纸是**可移动对象**，Rev.3 阶段 0d） / Paper origin (the sheet is a movable object)
# ---------------------------------------------------------------------------
# WHY A STORED ORIGIN AND NOT A RENDERER OFFSET / 为何存原点而不是渲染偏移：
# until this stage the paper WAS the world origin — gpPaperRect() returned Rect2(0, 0, W, H) with that
# zero written into the geometry module, so the trim line, the frame, the title block and the zone ruler
# all hung off a constant, and none of them could move. The user asked for the sheet to travel as ONE
# PIECE (「纸的边界跟着图框一起移动」); that is only expressible once the paper has a position of its
# own. Keeping it HERE gives "where is the paper?" exactly one home, which every rectangle below derives
# from. / 在本阶段之前，纸面**就是**世界原点 —— gpPaperRect() 返回 Rect2(0, 0, W, H)，那个 0 写死在
# 几何模块里，故裁边线、图框、图签与坐标带全都挂在一个常量上、谁也动不了。用户要求图纸**作为整体**移动
#（「纸的边界跟着图框一起移动」）；而这只有让纸面自身拥有位置才可表达。存在此处使「纸在哪」只有一个家，
# 下方每个矩形都由它推导。
#
# ⚠️ MARGINS ARE STILL MEASURED FROM THE PAPER, NEVER FROM THE WORLD / ⚠️ 边距恒自**纸**边量起，绝不从
# 世界原点量起：a margin is the distance between the paper edge and a frame line, so moving the paper
# carries the frame (and the title block and the ruler) along WITHOUT changing a single margin. That is
# what makes "move the whole sheet" a rigid translation of everything the sheet draws — and why it cannot
# be confused with editing the margins.
# 边距是「纸边与图框线之间的距离」，故纸一动，图框（连同图签与坐标带）随之而动，而**一条边距都不变**。
# 这正是「移动整张图纸」能是「图纸所绘一切」的刚性平移的原因，也是它绝不会与「改边距」混为一谈的原因。
#
# ⚠️ IT IS IMPORTED DATA, BUT THE CONTENT IS NOT RE-BASED ON IT / ⚠️ 它是被导入的数据，但**图元坐标并不以
# 它为基准**：node / edge / shape coordinates stay ABSOLUTE world millimetres (that is the whole point of
# the rigid move — every absolute coordinate travels with the paper, so no consumer of world coordinates
# needs to learn about this field). Re-basing the content on the origin would change every renderer, every
# hit-test and the DEXPI exporter at once; see GPTranslateSheetCommand for the one place that keeps them in
# step. / 图元 / 边 / 注释的坐标始终是**绝对**世界毫米（这正是刚性移动的要点 —— 每个绝对坐标随纸同行，
# 故任何世界坐标的消费方都无需认识本字段）。把图元改成以原点为基准会同时改动每个渲染器、每次命中判定与
# DEXPI 导出；「谁负责让它们保持同步」唯一一处在 GPTranslateSheetCommand。
var gpPaperOrigin: Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# 图元尺度兼容（P0-5） / Symbol-scale compatibility
# ---------------------------------------------------------------------------
# 1.0 = the A1-rebased data (GP_NOMINAL + pack manifests are ×2). 0.5 = a pre-A1 archive,
# whose symbols were authored against the A3-era envelopes and which stores no per-node size.
# The value is inferred from the project meta on load (`symbol_scale`, else legacy 0.5) and
# applied to the shared library by GPSheetLayer; it is NOT a per-node field.
# 1.0 = A1 重定基后的数据（GP_NOMINAL 与包 manifest 均为 ×2）。0.5 = A1 之前的存档：其图元
# 按 A3 时代包络绘制，且不存逐节点尺寸。载入时由工程 meta 推断（`symbol_scale`，缺失即
# 旧档 0.5），并由 GPSheetLayer 施加到共享图元库；它**不是**逐节点字段。
# Persisted when != 1.0, and ALSO when == 1.0 on a non-A1 sheet (an explicit "new era" marker,
# because the paper size alone cannot distinguish a new A3 from a legacy A3). A new A1 archive
# gains no key.
# 在 != 1.0 时写出；非 A1 图纸即使 == 1.0 也写出（显式「新世代」标记，因为单凭纸幅无法
# 区分新 A3 与旧 A3）。新 A1 存档不多键。
var gpSymbolScale: float = 1.0

# ---------------------------------------------------------------------------
# 图纸文字语言模式 / Drawing-text language mode (v0.1 Phase 2)
# ---------------------------------------------------------------------------
# WHY A SHEET-LEVEL MODE AND NOT gpLocale: gpLocale drives the software CHROME (menus,
# dialogs). A drawing's own text is a different concern — a Chinese engineer routinely
# issues drawings whose sheet text is bilingual or all-English. Coupling the two would
# force "bilingual drawing" to mean "bilingual UI", so the sheet carries its own mode.
# 为何是图级模式而非 gpLocale：gpLocale 驱动的是**软件界面**（菜单、对话框）。图纸自带文字是
# 另一回事 —— 中文工程师常常出"图面中英对照"或"图面纯英文"的图纸。二者耦合会迫使
# 「图面双语」等于「界面双语」，故由图自己持有该模式。
# Tag numbers (位号 / 管线号) are EXPLICITLY excluded: they are identifiers, not prose,
# and are always rendered monolingual regardless of this mode.
# 位号/管线号被**明确排除**在外：它们是标识而非文字，任何模式下都只显示单语。
const GP_LABEL_ZH: int = 0
const GP_LABEL_EN: int = 1
const GP_LABEL_BOTH: int = 2

# Standard sheet sizes in mm (landscape), per ISO 216 / GB-T 14689.
# 标准图幅尺寸（mm，横向），依 ISO 216 / GB-T 14689。
const GP_SHEET_PRESETS: Dictionary = {
	"A4": Vector2(297.0, 210.0),
	"A3": Vector2(420.0, 297.0),
	"A2": Vector2(594.0, 420.0),
	"A1": Vector2(841.0, 594.0),
	"A0": Vector2(1189.0, 841.0),
}

# Title-block cell layout (see plan Phase 2). Coordinates are millimetres relative to
# the block's BOTTOM-LEFT corner; the block is 135 x 50 mm and sits inside the frame's
# bottom-right corner. Width rebased 180 -> 135 (2026-10-16, user request: shrink the
# block's width by a quarter — 43% of the A1 sheet width read as visually dominant);
# the cell grid keeps the original proportions, so every column lands on exact binary
# fractions (67.5 = 135/2, 33.75 = 135/4, 45 = 135/3) and nothing drifts in float.
# Keeping the layout here (not in the renderer) makes it the single source of truth
# shared by the renderer and the edit dialog.
# 标题栏单元格布局（见计划 Phase 2）。坐标为相对图块**左下角**的毫米值；图块 135×50mm，
# 位于图框右下角。宽度重定基 180→135（2026-10-16，用户要求：宽度收窄 1/4 —— 原宽占 A1
# 纸宽 43%，观感过阔）；格网保持原比例，故每列都落在**精确**二进制分数上（67.5=135/2、
# 33.75=135/4、45=135/3），浮点零漂移。布局放在此处（而非渲染器）使其成为渲染器与编辑
# 对话框共享的单一事实源。
const GP_TB_BLOCK_W: float = 135.0
const GP_TB_BLOCK_H: float = 50.0
const GP_TB_FIELDS: Array = [
	{"key": "company",        "cap": "frame.fld.company",       "x": 0.0,    "y": 40.0, "w": 135.0,  "h": 10.0},
	{"key": "project",        "cap": "frame.fld.project",       "x": 0.0,    "y": 30.0, "w": 67.5,   "h": 10.0},
	{"key": "drawing_no",     "cap": "frame.fld.drawing_no",    "x": 67.5,   "y": 30.0, "w": 67.5,   "h": 10.0},
	{"key": "drawing_title",  "cap": "frame.fld.drawing_title", "x": 0.0,    "y": 20.0, "w": 67.5,   "h": 10.0},
	{"key": "rev",            "cap": "frame.fld.rev",           "x": 67.5,   "y": 20.0, "w": 33.75,  "h": 10.0},
	{"key": "date",           "cap": "frame.fld.date",          "x": 101.25, "y": 20.0, "w": 33.75,  "h": 10.0},
	{"key": "designed",       "cap": "frame.fld.designed",      "x": 0.0,    "y": 10.0, "w": 45.0,   "h": 10.0},
	{"key": "checked",        "cap": "frame.fld.checked",       "x": 45.0,   "y": 10.0, "w": 45.0,   "h": 10.0},
	{"key": "approved",       "cap": "frame.fld.approved",      "x": 90.0,   "y": 10.0, "w": 45.0,   "h": 10.0},
	{"key": "scale",          "cap": "frame.fld.scale",         "x": 0.0,    "y": 0.0,  "w": 33.75,  "h": 10.0},
	{"key": "sheet_index",    "cap": "frame.fld.sheet_index",   "x": 33.75,  "y": 0.0,  "w": 33.75,  "h": 10.0},
	{"key": "sheet_size",     "cap": "frame.fld.sheet_size",    "x": 67.5,   "y": 0.0,  "w": 33.75,  "h": 10.0},
	{"key": "drawn",          "cap": "frame.fld.drawn",         "x": 101.25, "y": 0.0,  "w": 33.75,  "h": 10.0},
]

# Drawing-text language mode for this sheet. Default bilingual, which is what Chinese
# engineering offices normally issue. / 本图纸的文字语言模式。默认中英对照。
var gpLabelMode: int = GP_LABEL_BOTH

# Bilingual title-block fields (see plan Phase 2). Each entry:
# { "caption": String, "value": {"zh": String, "en": String} }.
# 双语标题栏字段（见计划 Phase 2）。每项：{ "caption": 字段名, "value": {"zh": 中文值, "en": 英文值} }。
var gpTitleBlock: Dictionary = {}

# ---------------------------------------------------------------------------
# 图签停靠（锚角 + 偏移，Rev.3 阶段 1） / Title-block docking (anchor + offset)
# ---------------------------------------------------------------------------
# WHY THE BLOCK'S POSITION IS NOT A STORED POINT / 为何图签的位置**不**存成坐标点：
# the title block's whole reason to exist is that it TRAVELS WITH THE FRAME. Storing the absolutely
# placed corner (what "instant magnetic snapping" would do) breaks exactly that: drag the block against
# the inner edge, then move the frame, and the block stays put — on screen the block "falls off" the
# frame. The position is therefore DERIVED — f(inner rectangle, anchor, offset) — and what is stored is
# the DOCKING, not the point. Same discipline as mounted symbols, whose world transform is never stored
# either (see GPMountResolver). / 图签存在的全部意义就是**跟着图框走**。把绝对落位后的角存下来（即
# 「瞬时磁吸」会做的事）恰恰破坏了这一点：把图签拖到内边之后再移图框，图签留在原地 —— 屏幕上看就是图签
# 「从框上掉了下去」。故位置是**推导**的 —— f(内框矩形, 锚角, 偏移) —— 存下来的是**停靠关系**、不是那个点。
# 这与挂载图元同一纪律（其世界变换同样永不存储，见 GPMountResolver）。
#
# ⚠️ THE OFFSET IS A RELATIVE QUANTITY, SO THE WHOLE-SHEET MOVE DOES NOT TOUCH IT / ⚠️ 偏移是**相对量**，
# 故整图平移不碰它：Rev.3 stage 0d translates four families of ABSOLUTE world coordinates (paper origin,
# nodes, edges, shapes); the offset measures a distance from the anchor edge, which is unchanged by moving
# the sheet rigidly — exactly like a label offset or a mount offset.
# Rev.3 阶段 0d 平移的是**四族绝对**世界坐标（纸面原点、图元、边、注释图形）；而偏移量的是「到所贴那条内边
# 的距离」，在图纸刚性平移下不变 —— 与位号偏移、挂载偏移同理。
#
# The anchor is a 2-BIT CODE, not an enum with four unrelated values: bit 0 selects LEFT vs RIGHT, bit 1
# selects TOP vs BOTTOM. That is what makes gpReanchor() and the offset arithmetic a pair of sign
# choices rather than four hand-written cases (four cases is how the top-left corner quietly ends up
# with the bottom-right formula in it).
# 锚角是**两位编码**、不是四个互不相干取值的枚举：位 0 选左/右，位 1 选上/下。正是它使 gpReanchor() 与偏移
# 算术成为一对符号选择，而不是四段手写分支（四段手写正是「左上角悄悄用了右下角公式」的成因）。
const GP_TB_ANCHOR_BOTTOM_RIGHT: int = 0
const GP_TB_ANCHOR_BOTTOM_LEFT: int = 1
const GP_TB_ANCHOR_TOP_RIGHT: int = 2
const GP_TB_ANCHOR_TOP_LEFT: int = 3

# The corner the block hugs, as a 2-bit code (see above). Default bottom-right: that is where every
# drawing office puts it and where this project has put it since v0.1, so a sheet that never touched the
# block keeps drawing it exactly where it was (and writes no new key — see ADR-7).
# 图签所贴的角，2 位编码（见上）。默认右下：所有设计院都放那儿，本项目自 v0.1 起也放那儿，故从未动过图签的
# 图纸继续把它画在原处（且不写出新键 —— 见 ADR-7）。
var gpTbAnchor: int = GP_TB_ANCHOR_BOTTOM_RIGHT

# Distance in mm from the anchor corner INTO the frame, so (0, 0) means "flush against that corner" =
# the block's historical position. x is the distance from the hugged VERTICAL line, y from the hugged
# HORIZONTAL line — both measured into the frame, so the sign of each component never depends on which
# corner is chosen. / 自锚角**向框内**的距离（mm），故 (0, 0) 即「贴住那个角」= 图签的历史位置。x 是到所贴
# **竖**线的距离、y 是到所贴**横**线的距离 —— 两者都向框内量，故每个分量的符号都与所选之角无关。
#
# ⚠️ NOT HOLDING THE MARGINS' PRECEDENT OF CLAMPING IN ITS OWN SETTER / ⚠️ 此处**不**沿用边距那种「在自身
# setter 内钳制」的做法：a margin's bound follows from the paper size alone, which this class has; the
# offset's bound follows from the INNER RECTANGLE's size, which is a geometry-layer fact. Re-deriving the
# inner rectangle here would put one geometric fact in two homes — the failure GPFrameGeometry exists to
# prevent. The clamp therefore lives in GPFrameGeometry.gpClampTitleBlock(), is applied by every write
# path, and is re-applied on read (idempotent) so a hand-edited archive cannot produce an illegal block.
# 边距的上下限只由纸面尺寸决定（本类就有）；而偏移的界限由**内框**尺寸决定，那是几何层的事实。在此重算内框
# 会把同一个几何事实放进两个家 —— 正是 GPFrameGeometry 存在的意义所在。故钳制住在
# GPFrameGeometry.gpClampTitleBlock()，由每条写入路径施加，并在读取时再折一次（幂等），使手工改过的存档
# 也产不出非法图签。
var gpTbOffset: Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# 追踪底图（背景参照层，v0.1 Phase 5）
# ---------------------------------------------------------------------------
# WHY A TRACING UNDERLAY: reproducing an international reference P&ID 1:1 means drawing
# symbols ON TOP of the reference raster, not guessing coordinates. The underlay sits at
# the BOTTOM of world_root (z_index -2, below frame -1 and below every symbol at 0), so it
# reads as a faint reference the user can trace over. It is NOT editable geometry.
# 为何做追踪底图：1:1 复刻国际参考 P&ID 是把符号**画在**参考位图之上，而非凭空猜坐标。
# 底图位于 world_root 最底层（z_index=-2，低于图框 -1、低于所有符号 0），呈现为可描摹的淡参考。
# 它不是可编辑几何。
# The path is a texture the user drops in (a PNG/JPG/WEBP render of the reference drawing).
# Kept as a PATH (not embedded base64) so the single archive stays small and the image can
# be re-rendered at any DPI; data-sovereignty is preserved because the path is relative to
# the project and travels with it. / 路径是用户放入的参考图位图（PNG/JPG/WEBP）。
# 用路径而非内嵌 base64：单文件体积可控，且位图可任意 DPI 重渲；数据主权仍在（路径随工程走）。
var gpBackgroundPath: String = ""

# Underlay opacity (0..1). Low by default so symbols drawn on top stay legible.
# 底图不透明度（0..1）。默认很淡，使上方描摹的符号清晰可辨。
var gpBackgroundAlpha: float = 0.35


# A fresh title block: every standard field present, both language slots empty.
# WHY pre-populated rather than empty: the renderer can then draw the full cell grid
# even for a brand-new sheet, instead of a block that grows as fields get filled.
# 全新的标题栏：每个标准字段都在，双语值均为空。
# 为何预置而非留空：渲染器即可为全新图纸画出完整格网，而不是边填边长大。
static func gpDefaultTitleBlock() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpF in GP_TB_FIELDS:
		gpOut[str(gpF["key"])] = {"zh": "", "en": ""}
	return gpOut


# The value of one title-block field in the sheet's label mode.
# [param gpKey] field key; [return] "" when the field is absent.
# 某标题栏字段在本图纸标签模式下的取值。[return] 字段不存在时为空串。
func gpTitleValue(gpKey: String) -> String:
	var gpEntry: Variant = gpTitleBlock.get(gpKey)
	if gpEntry == null:
		return ""
	var gpVal: Variant = (gpEntry as Dictionary).get("value")
	if gpVal == null:
		return ""
	var gpV: Dictionary = gpVal as Dictionary
	# BOTH renders as two stacked lines; the renderer asks for each line separately, so
	# here we resolve single-language modes and leave BOTH to the caller.
	# BOTH 是上下双行，渲染器分别取每行，故此处只解析单语模式。
	if gpLabelMode == GP_LABEL_EN:
		return str(gpV.get("en", ""))
	return str(gpV.get("zh", ""))


func gpToDict() -> Dictionary:
	var gpG: Dictionary = {}
	if gpGraph != null:
		gpG = gpGraph.gpToDict()
	var gpOut: Dictionary = {
		"id": gpId,
		"name": gpName,
		"index": gpIndex,
		"nodes": gpG.get("nodes", []),
		"edges": gpG.get("edges", []),
		"shapes": gpG.get("shapes", []),
		"width_mm": gpWidthMM,
		"height_mm": gpHeightMM,
		"frame_on": gpFrameOn,
	}
	# Written only when non-default, so an archive that never touched the frame stays
	# byte-identical to what older builds produced (see ADR-7 write policy).
	# 仅在非默认时写出，使从未动过图框的存档与旧版本产物逐字节一致（见 ADR-7 写出策略）。
	if not gpTitleBlock.is_empty():
		gpOut["title_block"] = gpTitleBlock
	if gpLabelMode != GP_LABEL_BOTH:
		gpOut["label_mode"] = gpLabelMode
	# Tracing underlay: written only when set, so an archive with no background stays
	# byte-identical to what older builds produced. / 追踪底图：仅在设置时写出，
	# 使无底图的存档与旧版本产物逐字节一致。
	if gpBackgroundPath != "":
		gpOut["background_path"] = gpBackgroundPath
	if absf(gpBackgroundAlpha - 0.35) > 0.001:
		gpOut["background_alpha"] = gpBackgroundAlpha
	# Frame margins (Rev.3 stage 0a): written only when moved off the default, so an archive
	# from before this key existed stays byte-identical on re-save.
	# 图框边距（Rev.3 阶段 0a）：仅在偏离默认值时写出，使本键出现之前的存档重新保存后逐字节一致。
	if not gpFrameMarginsAreDefault():
		gpOut["frame_margins"] = gpFrameMargins
	# Paper origin (Rev.3 stage 0d): written only when the sheet has actually been moved, so an archive
	# from before this key existed stays byte-identical on re-save.
	# 图纸原点（Rev.3 阶段 0d）：仅在图纸确实被移动过时写出，使本键出现之前的存档重新保存后逐字节一致。
	if not gpPaperOriginIsDefault():
		gpOut["paper_origin"] = [gpPaperOrigin.x, gpPaperOrigin.y]
	# P0-5: a legacy A3-era sheet carries its 0.5 scale explicitly once saved, so the
	# compatibility decision survives even if the project meta is rewritten later. A NEW
	# non-A1 sheet also writes 1.0 explicitly: its paper size alone cannot distinguish it
	# from a legacy A3 archive, and the key is what keeps it from reopening at 0.5.
	# P0-5：旧 A3 时代图纸一经保存就显式携带 0.5 尺度，使该兼容决定在工程 meta 日后被
	# 重写时也不会丢失。**新建的非 A1** 图纸也显式写 1.0：单凭纸幅无法把它与旧 A3 存档
	# 区分开，而这个键正是它不会以 0.5 重开的保证。
	var gpWriteScale: bool = absf(gpSymbolScale - 1.0) > 0.0001 \
		or not _gpPaperIs(gpWidthMM, gpHeightMM, 841.0, 594.0)
	if gpWriteScale:
		gpOut["symbol_scale"] = gpSymbolScale
	# Title-block docking (Rev.3 stage 1): written only when the block has actually been moved off its
	# historical corner, so an archive from before these two keys existed stays byte-identical on re-save.
	# 图签停靠（Rev.3 阶段 1）：仅在图签确实离开了它的历史角落时写出，使这两个键出现之前的存档重新保存后
	# 逐字节一致。
	if not gpTbPlacementIsDefault():
		gpOut["tb_anchor"] = gpTbAnchor
		gpOut["tb_offset"] = [gpTbOffset.x, gpTbOffset.y]
	return gpOut


# Restore one sheet. Tolerates a sheet dict that carries no geometry at all.
# 还原一张图纸。容忍完全不含几何的图纸字典。
static func gpFromDict(gpD: Dictionary) -> GPSheet:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpId = str(gpD.get("id", ""))
	gpS.gpName = str(gpD.get("name", ""))
	gpS.gpIndex = int(gpD.get("index", 0))
	# ⚠️ Missing-key fallback stays 420/297 (A3-era), NOT the new default: an archive old enough to
	# lack these keys is by definition an A3-era drawing.
	# ⚠️ 缺键回落保持 420/297（A3 时代），**不是**新默认：老到缺这两个键的存档按定义就是 A3 时代的图纸。
	gpS.gpWidthMM = float(gpD.get("width_mm", 420.0))
	gpS.gpHeightMM = float(gpD.get("height_mm", 297.0))
	# P0-5: the sheet's own key wins; otherwise the project meta carries the era marker;
	# otherwise infer from the paper size. A1 is the rebased default, so an A1 archive is
	# treated as full-scale even if it predates the marker (a pre-A1 A1 drawing is rare);
	# every other size without a marker is a pre-A1 archive (A3-era symbols) and gets 0.5.
	# P0-5：图纸自身的键优先；否则看工程 meta 的世代标记；再否则按纸幅推断。A1 是重定基
	# 后的默认图幅，故无标记的 A1 存档按全尺度处理（A1 之前的 A1 图很少）；其余尺寸无标记
	# 即 A1 之前存档（A3 时代图元），取 0.5。
	gpS.gpSymbolScale = gpScaleForSheetDict(gpD)
	gpS.gpFrameOn = bool(gpD.get("frame_on", true))
	# Margins go through the setter, never straight into the field, so the ONE invariant they carry
	# (a non-inside-out inner rectangle) cannot be bypassed by a hand-edited archive.
	# ⚠️ The setter does NOT confine the frame to the paper any more (Rev.3 amendment, 2026-10-16) —
	# an archive carrying a NEGATIVE margin is legal and means "that frame line is off the sheet".
	# A malformed / absent array silently keeps the default (the var initialiser), which is what an
	# archive written before this key existed carries.
	# 边距经 setter 走，绝不直接写字段，使它们承载的唯一不变量（内框不内翻）无法被手工改过的存档绕过。
	# ⚠️ setter 已**不再**把图框限制在纸内（Rev.3 修正，2026-10-16）—— 带负边距的存档合法，意为
	# 「该条图框线在纸外」。数组缺失或格式不对时静默保留默认值（即变量初始值），这正是本键出现之前的
	# 存档所带的。
	var gpFM: Variant = gpD.get("frame_margins", null)
	if gpFM is Array:
		gpS.gpSetFrameMargins(gpFM as Array)
	else:
		# Absent key: fall back to the PAPER SIZE's own default (A1 rebase, 2026-10-16) — an old
		# A3 archive gets exactly the values it was drawn with, an A1 sheet the filing format.
		# 缺键：回落到**纸幅自身**的默认（A1 重定基，2026-10-16）—— 旧 A3 存档得到它被绘制时
		# 的那组值，A1 图纸得到装订幅面。
		# ⚠️ The width/height reads ABOVE must stay before this line, or this default would be
		# derived from the not-yet-restored size. / 上方的宽/高读取必须在本行之前，否则本默认
		# 会从尚未还原的尺寸推导。
		gpS.gpSetFrameMargins(gpDefaultMarginsFor(gpS.gpWidthMM, gpS.gpHeightMM))
	# Paper origin (Rev.3 stage 0d). Absent / malformed keeps the default (the world origin), which is
	# what an archive written before this key existed carries — i.e. a sheet that was never moved.
	# 图纸原点（Rev.3 阶段 0d）。缺失或格式不对时保留默认值（世界原点），这正是本键出现之前的存档所带的
	# —— 即一张从未被移动过的图纸。
	var gpPO: Variant = gpD.get("paper_origin", null)
	if gpPO is Array and (gpPO as Array).size() >= 2:
		var gpPOArr: Array = gpPO as Array
		gpS.gpSetPaperOrigin(Vector2(float(gpPOArr[0]), float(gpPOArr[1])))
	# Title-block docking (Rev.3 stage 1). Absent / malformed keeps the default — bottom-right, no
	# offset — which is what an archive written before these keys existed carries, and what the renderer
	# draws for a block nobody has moved. / 图签停靠（Rev.3 阶段 1）。缺失或格式不对时保留默认 —— 右下、
	# 无偏移 —— 这正是本二键出现之前的存档所带的，也是渲染器为「没被人动过的图签」所画的。
	# The anchor goes through its setter, which folds a hand-edited out-of-range value into the four
	# corners; the offset does NOT (its bound is the inner rectangle's size — see gpTbOffset).
	# 锚角经其 setter，后者把手工改过的越界值收进四个角之内；偏移**不**如此（其界限是内框尺寸 —— 见 gpTbOffset）。
	var gpTA: Variant = gpD.get("tb_anchor", null)
	if gpTA is float or gpTA is int:
		gpS.gpSetTbAnchor(int(gpTA))
	var gpTO: Variant = gpD.get("tb_offset", null)
	if gpTO is Array and (gpTO as Array).size() >= 2:
		var gpTOArr: Array = gpTO as Array
		gpS.gpSetTbOffset(Vector2(float(gpTOArr[0]), float(gpTOArr[1])))
	gpS.gpLabelMode = int(gpD.get("label_mode", GP_LABEL_BOTH))
	gpS.gpBackgroundPath = str(gpD.get("background_path", ""))
	gpS.gpBackgroundAlpha = float(gpD.get("background_alpha", 0.35))
	var gpTB: Variant = gpD.get("title_block", null)
	# An absent title block gets the full standard cell set, so an old archive opens with
	# a complete (empty) block rather than a frame with no title block at all.
	# 缺少标题栏时填入完整标准格网，使旧档打开即是完整（空）标题栏，而不是有框无栏。
	gpS.gpTitleBlock = (gpTB as Dictionary).duplicate(true) if gpTB is Dictionary else gpDefaultTitleBlock()
	# Build the graph from the sheet's own geometry only. tag_rules is added conditionally
	# because GPPIDGraph reads it by presence: passing an empty dict would fabricate a
	# default rule set and, worse, mark the project as "has rules" on the next save.
	# 仅用图纸自己的几何构建图。tag_rules 条件性加入，因为 GPPIDGraph 按**键是否存在**
	# 读取它：传空字典会凭空造出一套默认规则，更糟的是会让工程在下次保存时
	# 被标记为「有规则」。
	var gpGraphDict: Dictionary = {
		"meta": gpD.get("meta", {}),
		"nodes": gpD.get("nodes", []),
		"edges": gpD.get("edges", []),
		"shapes": gpD.get("shapes", []),
		"user_symbol_packs": gpD.get("user_symbol_packs", []),
	}
	if gpD.has("tag_rules"):
		gpGraphDict["tag_rules"] = gpD.get("tag_rules", {})
	gpS.gpGraph = GPPIDGraph.gpFromDict(gpGraphDict)
	return gpS


# Convenience: an empty sheet with the given identity.
# 便利方法：带给定标识的空图纸。
static func gpNew(gpId: String, gpName: String, gpIndex: int) -> GPSheet:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpId = gpId
	gpS.gpName = gpName
	gpS.gpIndex = gpIndex
	gpS.gpGraph = GPPIDGraph.new()
	gpS.gpTitleBlock = gpDefaultTitleBlock()
	# Margins start from the paper size's own default (A1 → 25/10/10/10, else the A3-era values),
	# through THE ONE WRITE POINT like every other margin change.
	# 边距以纸幅自身的默认值起步（A1 → 25/10/10/10，其余为 A3 时代值），并经**唯一写口** ——
	# 与其它一切边距修改相同。
	gpS.gpSetFrameMargins(gpDefaultMarginsFor(gpS.gpWidthMM, gpS.gpHeightMM))
	# 图幅自动回填标题栏的「图幅」格（如 A3），省去用户手填且与真实图幅脱节的风险。
	gpS.gpSyncSheetSizeField()
	return gpS


# Write the sheet's own size into the title block's SIZE cell (e.g. "A3").
# 把本图纸的图幅写进标题栏的「图幅」格（如 A3）。
func gpSyncSheetSizeField() -> void:
	var gpBest: String = ""
	for gpK in GP_SHEET_PRESETS:
		var gpV: Vector2 = GP_SHEET_PRESETS[gpK]
		if absf(gpV.x - gpWidthMM) < 0.5 and absf(gpV.y - gpHeightMM) < 0.5:
			gpBest = str(gpK)
			break
	if gpBest == "":
		gpBest = "%g x %g" % [gpWidthMM, gpHeightMM]
	var gpEntry: Variant = gpTitleBlock.get("sheet_size")
	if gpEntry == null:
		gpEntry = {"value": {"zh": "", "en": ""}}
		gpTitleBlock["sheet_size"] = gpEntry
	(gpEntry as Dictionary)["value"] = {"zh": gpBest, "en": gpBest}


# ---------------------------------------------------------------------------
# 图框边距的读写口（Rev.3 阶段 0a） / Frame-margin read / write (Rev.3 stage 0a)
# ---------------------------------------------------------------------------
# THE ONE WRITE POINT. Both the title-block dialog (numeric fields) and the future frame drag
# call THIS, so the two entry points cannot drift apart — the recurring failure mode of this
# project (two copies of one decision always diverge). Callers own the repaint: this class
# holds no view and must not reach for one.
# **唯一写口**。标题栏对话框（数值输入）与将来的图框拖动都调**它**，使两个入口不会分家 ——
# 这正是本项目反复出现的失效模式（同一判断写两遍必然分家）。重绘由调用方负责：本类不含视图，
# 也不得去取视图。
# [param gpMargins] desired [left, top, right, bottom] in mm; MAY be negative (meaning that frame
#                   line lies outside the sheet) and is projected into the legal set on the way in —
#                   see gpClampMargins for the single invariant that projection still enforces
#                   期望的 [左, 上, 右, 下]（mm）；**可以**为负（即该条图框线位于纸面之外），写入前会
#                   被收进合法域 —— 该投影仍强制的那一条不变量见 gpClampMargins
func gpSetFrameMargins(gpMargins: Array) -> void:
	gpFrameMargins = gpClampMargins(gpMargins, gpWidthMM, gpHeightMM)


# True when the margins still equal the standard default. Drives the WRITE POLICY: a sheet that
# never touched its frame must not gain the key (ADR-7 byte-stability for old archives).
# ⚠️ Since the A1 rebase the comparison base is the PAPER SIZE's own default (gpDefaultMarginsFor):
# an A1 sheet carrying 25/10/10/10 is "untouched" and writes no key; an A3-era sheet carrying
# 25/5/5/5 likewise. A sheet whose size changed after margins were set re-evaluates against its
# NEW size — the one case where a previously-default margin becomes non-default on resave, which
# is the honest outcome of resizing the paper.
# 边距仍等于标准默认值时返回真。它是**写出策略**的依据：从未动过图框的图纸不得多出该键
# （ADR-7 旧档字节稳定）。
# ⚠️ 自 A1 重定基起，比较基准是**纸幅自身**的默认（gpDefaultMarginsFor）：带 25/10/10/10 的 A1
# 图纸即「未动过」、不写键；带 25/5/5/5 的 A3 时代图纸亦然。设完边距后又改了纸幅的图纸会按
# **新**尺寸重评 —— 这是「先前的默认边距在重存时变为非默认」的唯一情形，也是改纸幅后的诚实结果。
func gpFrameMarginsAreDefault() -> bool:
	var gpDef: Array = gpDefaultMarginsFor(gpWidthMM, gpHeightMM)
	if gpFrameMargins.size() != gpDef.size():
		return false
	for gpI in gpDef.size():
		if absf(float(gpFrameMargins[gpI]) - float(gpDef[gpI])) > 0.0001:
			return false
	return true


# ---------------------------------------------------------------------------
# 图纸原点的读写口（Rev.3 阶段 0d） / Paper-origin read / write
# ---------------------------------------------------------------------------
# THE ONE WRITE POINT for the paper position. The whole-sheet drag preview and
# GPTranslateSheetCommand both call THIS, so the two entry points cannot drift apart.
# **唯一写口**。整图拖拽的实时预览与 GPTranslateSheetCommand 都调**它**，使两个入口不会分家。
#
# ⚠️ NO CLAMP, ON PURPOSE / ⚠️ 刻意**不**做钳制：there is nothing to protect. The origin is where the
# paper was dragged, in world millimetres, and every admissible value is a legal position on an infinite
# canvas — unlike the margins, which carry the frame's own consistency (GP_FRAME_MIN_SIZE_MM). A "clamp"
# here would have to invent a bound nobody asked for and would silently refuse the drag's own arithmetic.
# 没有什么需要保护：原点就是纸被拖到的地方（世界毫米），在无限画布上每个取值都是合法位置 —— 与承载图框
# 自洽性的边距（GP_FRAME_MIN_SIZE_MM）不同。此处若「钳制」，就得凭空造出一个没人要求的边界，并静默
# 拒绝拖拽自身的算术。
# Callers own the repaint: this class holds no view and must not reach for one.
# 重绘由调用方负责：本类不含视图，也不得去取视图。
func gpSetPaperOrigin(gpValue: Vector2) -> void:
	gpPaperOrigin = gpValue


# True while the paper still sits at the world origin, i.e. the sheet has never been moved.
# Drives the WRITE POLICY: a sheet that was never moved must not gain the key (ADR-7 byte-stability for
# old archives — the same rule gpFrameMarginsAreDefault() serves for the margins).
# 纸面仍位于世界原点（即这张图纸从未被移动过）时返回真。它是**写出策略**的依据：从未移动过的图纸不得
# 多出该键（ADR-7 旧档字节稳定 —— 与 gpFrameMarginsAreDefault() 对边距所服务的是同一条规则）。
func gpPaperOriginIsDefault() -> bool:
	return gpPaperOrigin == Vector2.ZERO


# ---------------------------------------------------------------------------
# 图签停靠的读写口（Rev.3 阶段 1） / Title-block docking read / write
# ---------------------------------------------------------------------------
# WHY THREE SETTERS AND NOT ONE / 为何是三个 setter 而不是一个：both callers exist. The dialog moves the
# block to another CORNER and has no opinion about the offset (it must survive, or "move it to the top
# left" would silently also reset how far it sat from the edge); the drag produces BOTH at once and must
# write them as ONE undo step. gpSetTbPlacement() is the pair entry that the drag and the command use, and
# it delegates to the two single-field setters so there is still exactly one place each field is written.
# 两个调用方都存在。对话框把图签挪到**另一个角**、对偏移没有意见（它必须被保留，否则「移到左上角」会连带
# 静默复位「离边多远」）；而拖拽同时产出两者、且必须作为**一个**撤销步写入。gpSetTbPlacement() 就是拖拽与
# 命令所用的成对入口，它转调两个单字段 setter，故每个字段仍恰有一处被写。
# [param gpAnchor] the corner to hug; an out-of-range value is clamped into the four corners
#                  所贴之角；越界值被收进四个角之内
func gpSetTbAnchor(gpAnchor: int) -> void:
	gpTbAnchor = clampi(gpAnchor, GP_TB_ANCHOR_BOTTOM_RIGHT, GP_TB_ANCHOR_TOP_LEFT)


# [param gpOffset] distance in mm from the anchor corner INTO the frame (see the field's note for why
#                  this setter deliberately does not clamp)
#                  自锚角**向框内**的距离（mm）（该 setter 为何刻意不钳制，见字段说明）
func gpSetTbOffset(gpOffset: Vector2) -> void:
	gpTbOffset = gpOffset


# Set the anchor and the offset together — the form a drag produces, and the reason a dragged block is
# ONE undo step rather than two.
# 同时设置锚角与偏移 —— 拖拽产出的正是这一形式，也是被拖的图签是**一个**撤销步而不是两个的原因。
func gpSetTbPlacement(gpAnchor: int, gpOffset: Vector2) -> void:
	gpSetTbAnchor(gpAnchor)
	gpSetTbOffset(gpOffset)


# True while the block still hugs the bottom-right corner with no offset, i.e. it has never been moved.
# Drives the WRITE POLICY, so an archive written by an older build gains neither key (ADR-7) — and, just
# as importantly, the RENDERER's default case stays bit-identical to what every existing drawing expects.
# 图签仍贴右下角且无偏移（即从未被移动过）时返回真。它是**写出策略**的依据，使旧版本写出的存档两个键都不多
# —— 同样重要的是，渲染器的默认情形与每一张既有图纸所预期的结果保持逐位一致。
func gpTbPlacementIsDefault() -> bool:
	return gpTbAnchor == GP_TB_ANCHOR_BOTTOM_RIGHT and gpTbOffset == Vector2.ZERO


# Bring any incoming margin array into the legal set, for a paper of the given size.
# 把任意输入边距数组收进合法域（针对给定纸面尺寸）。
#
# ⚠️ "LEGAL" IS MUCH WEAKER THAN IT USED TO BE (Rev.3 amendment, 2026-10-16). The old rule had TWO
# invariants — every margin >= 1 mm AND a non-degenerate inner rectangle — and the first one is
# exactly what pinned the frame inside the paper. It is GONE: the user asked for free movement with no
# limits, so a margin may be negative, or larger than the whole paper. ONE invariant survives, and it
# speaks about the inner RECTANGLE rather than about any single margin:
# ⚠️ 「合法」比从前弱得多（Rev.3 修正，2026-10-16）。旧规则有**两**条不变量 —— 每条边距 >= 1mm、内框
# 非退化 —— 而**第一条**正是把图框钉在纸内的原因。它已被删除：用户要求无限制的自由移动，故边距可以为负、
# 也可以大于整张纸。只剩**一条**不变量，且它说的是内框、不是任何单条边距：
#
#   left + right (and top + bottom) leave an inner rectangle at least GP_FRAME_MIN_SIZE_MM across.
#   左+右（上+下）为内框留下至少 GP_FRAME_MIN_SIZE_MM 的跨度。
#
# WHY THE PAIR RULE CANNOT BE A PER-ELEMENT FLOOR / 为何成对规则不能写成逐元素下限：a pair can both
# be legal individually and still leave nothing (300 + 300 on a 420 sheet). The pair is therefore
# scaled back proportionally instead. / 一对边距各自都「合法」，却仍可能什么都不剩（420 纸上
# 300+300）。故改为按比例回缩该对边距。
#
# ⚠️ THE OLD "LIFT THE ELEMENTS SCALED BELOW THE MINIMUM" STEP WENT WITH THE PER-ELEMENT FLOOR. It
# existed only to repair values the scaling had pushed under 1 mm; with no floor left to violate it is
# dead code. The proportional scaling now lands on the limit exactly (sum == limit), so there is no
# surplus left to take off the larger side either.
# ⚠️ 旧的「把被缩到最小值以下的元素抬回来」这一步随逐元素下限一并删除。它原本只用来修补被回缩压到 1mm
# 以下的值；没有下限可违反，它就是死代码。按比例回缩如今恰好落在上限上（和 == 上限），故也不会留下需要从
# 较大一侧扣除的盈余。
#
# Idempotent: feeding the result back in changes nothing, so callers may clamp defensively.
# 幂等：把结果再喂进来不会改变任何值，故调用方可以放心地上再钳一次。
# [param gpW] / [param gpH] paper size in mm / 纸面尺寸（mm）
static func gpClampMargins(gpIn: Array, gpW: float, gpH: float) -> Array:
	var gpOut: Array = []
	for gpI in GP_FRAME_MARGINS_DEFAULT.size():
		var gpV: float = float(GP_FRAME_MARGINS_DEFAULT[gpI])
		if gpI < gpIn.size():
			gpV = float(gpIn[gpI])
		# ⚠️ NO per-element floor: a margin is a distance measured from the paper edge, and the frame
		# is allowed to be on the OTHER side of that edge.
		# ⚠️ **不设**逐元素下限：边距是「到纸边的距离」，而图框允许位于那条边的**另一侧**。
		gpOut.append(gpV)
	_gpCapPair(gpOut, GP_MARGIN_LEFT, GP_MARGIN_RIGHT, gpW)
	_gpCapPair(gpOut, GP_MARGIN_TOP, GP_MARGIN_BOTTOM, gpH)
	return gpOut


# Shrink one opposing pair so it leaves at least GP_FRAME_MIN_SIZE_MM of inner rectangle.
# 回缩一对相互对置的边距，使内框至少留下 GP_FRAME_MIN_SIZE_MM。
# [param gpSpan] the paper dimension the pair consumes (width for L/R, height for T/B)
#                该对边距所消耗的纸面尺寸（L/R 用宽，T/B 用高）
static func _gpCapPair(gpArr: Array, gpIA: int, gpIB: int, gpSpan: float) -> void:
	var gpA: float = float(gpArr[gpIA])
	var gpB: float = float(gpArr[gpIB])
	var gpLimit: float = gpSpan - GP_FRAME_MIN_SIZE_MM
	if gpA + gpB <= gpLimit:
		return
	# A paper smaller than the minimum itself: there is nothing to preserve, so both margins go to
	# zero and the frame spans the whole sheet — the largest rectangle that paper can host.
	# 纸面本身比最小值还小：没有可保的东西，故两条边距都归零，图框横跨整张纸 —— 那是该纸面能容纳的最大矩形。
	if gpLimit <= 0.0:
		gpArr[gpIA] = 0.0
		gpArr[gpIB] = 0.0
		return
	# ⚠️ A non-positive sum cannot reach here: the early return above already covers `sum <= limit`
	# for every limit >= 0, and `limit <= 0` is handled on its own. So the divisor is positive.
	# ⚠️ 非正的和到不了这里：上面那条提前返回已覆盖所有 limit >= 0 时的 `sum <= limit`，而 `limit <= 0`
	# 已单独处理。故除数恒为正。
	var gpK: float = gpLimit / (gpA + gpB)
	gpArr[gpIA] = gpA * gpK
	gpArr[gpIB] = gpB * gpK
