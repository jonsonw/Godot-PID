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
# expressed in mm and this is the A3 default (420 x 297 mm, landscape).
# 图纸物理尺寸（毫米）。从 v0.1 起编辑器统一采用「1 世界单位 = 1mm」（见计划 Phase 0），
# 故坐标、图元尺寸、线宽、字号均以 mm 计；此处为 A3 默认值（420×297mm，横向）。
var gpWidthMM: float = 420.0
var gpHeightMM: float = 297.0

# Whether the drawing frame + title block is drawn for this sheet (see plan Phase 2).
# 本图纸是否绘制图框 + 标题栏（见计划 Phase 2）。
var gpFrameOn: bool = true

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
# the block's BOTTOM-LEFT corner; the block is 180 x 50 mm and sits inside the frame's
# bottom-right corner. Keeping the layout here (not in the renderer) makes it the single
# source of truth shared by the renderer and the edit dialog.
# 标题栏单元格布局（见计划 Phase 2）。坐标为相对图块**左下角**的毫米值；图块 180×50mm，
# 位于图框右下角。布局放在此处（而非渲染器）使其成为渲染器与编辑对话框共享的单一事实源。
const GP_TB_BLOCK_W: float = 180.0
const GP_TB_BLOCK_H: float = 50.0
const GP_TB_FIELDS: Array = [
	{"key": "company",        "cap": "frame.fld.company",       "x": 0.0,   "y": 40.0, "w": 180.0, "h": 10.0},
	{"key": "project",        "cap": "frame.fld.project",       "x": 0.0,   "y": 30.0, "w": 90.0,  "h": 10.0},
	{"key": "drawing_no",     "cap": "frame.fld.drawing_no",    "x": 90.0,  "y": 30.0, "w": 90.0,  "h": 10.0},
	{"key": "drawing_title",  "cap": "frame.fld.drawing_title", "x": 0.0,   "y": 20.0, "w": 90.0,  "h": 10.0},
	{"key": "rev",            "cap": "frame.fld.rev",           "x": 90.0,  "y": 20.0, "w": 45.0,  "h": 10.0},
	{"key": "date",           "cap": "frame.fld.date",          "x": 135.0, "y": 20.0, "w": 45.0,  "h": 10.0},
	{"key": "designed",       "cap": "frame.fld.designed",      "x": 0.0,   "y": 10.0, "w": 60.0,  "h": 10.0},
	{"key": "checked",        "cap": "frame.fld.checked",       "x": 60.0,  "y": 10.0, "w": 60.0,  "h": 10.0},
	{"key": "approved",       "cap": "frame.fld.approved",      "x": 120.0, "y": 10.0, "w": 60.0,  "h": 10.0},
	{"key": "scale",          "cap": "frame.fld.scale",         "x": 0.0,   "y": 0.0,  "w": 45.0,  "h": 10.0},
	{"key": "sheet_index",    "cap": "frame.fld.sheet_index",   "x": 45.0,  "y": 0.0,  "w": 45.0,  "h": 10.0},
	{"key": "sheet_size",     "cap": "frame.fld.sheet_size",    "x": 90.0,  "y": 0.0,  "w": 45.0,  "h": 10.0},
	{"key": "drawn",          "cap": "frame.fld.drawn",         "x": 135.0, "y": 0.0,  "w": 45.0,  "h": 10.0},
]

# Drawing-text language mode for this sheet. Default bilingual, which is what Chinese
# engineering offices normally issue. / 本图纸的文字语言模式。默认中英对照。
var gpLabelMode: int = GP_LABEL_BOTH

# Bilingual title-block fields (see plan Phase 2). Each entry:
# { "caption": String, "value": {"zh": String, "en": String} }.
# 双语标题栏字段（见计划 Phase 2）。每项：{ "caption": 字段名, "value": {"zh": 中文值, "en": 英文值} }。
var gpTitleBlock: Dictionary = {}

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
	return gpOut


# Restore one sheet. Tolerates a sheet dict that carries no geometry at all.
# 还原一张图纸。容忍完全不含几何的图纸字典。
static func gpFromDict(gpD: Dictionary) -> GPSheet:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpId = str(gpD.get("id", ""))
	gpS.gpName = str(gpD.get("name", ""))
	gpS.gpIndex = int(gpD.get("index", 0))
	gpS.gpWidthMM = float(gpD.get("width_mm", 420.0))
	gpS.gpHeightMM = float(gpD.get("height_mm", 297.0))
	gpS.gpFrameOn = bool(gpD.get("frame_on", true))
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
