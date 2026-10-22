extends "res://tests/gp_test.gd"
# Drawing frame + bilingual title-block tests (v0.1 Phase 2).
# 图框 + 双语标题栏测试（v0.1 Phase 2）。
# The failure modes being guarded against:
# 所防范的失效模式：
# 1. A new sheet silently loses its A3 size / frame, so the drawing has no boundary.
#    新建图纸静默丢失 A3 图幅 / 图框，导致图纸没有边界。
# 2. A saved frame comes back reset — the user fills in a title block, saves, and the
#    drawing reopens empty. That wastes a real deliverable, not just a setting.
#    保存的图框回来后被重置 —— 用户填好标题栏、保存、重开却是空的。损失的可是真实交付物。
# 3. An archive written before the frame existed opens with a HALF block (or crashes).
#    图框功能之前写的旧档打开后只有半个标题栏（或崩溃）。
# 4. The drawing-text language leaks into tag numbers, corrupting identifiers.
#    图纸文字语言串进位号，污染标识。

# Number of standard title-block fields (GPSheet.GP_TB_FIELDS).
# 标准标题栏字段数（GPSheet.GP_TB_FIELDS）。
const GP_FIELD_COUNT: int = 13


# A brand-new sheet is A1 (the 2026-10-16 rebase), framed, bilingual, with the A1 filing margins
# and the complete cell grid. THIS is the new default's own contract — the geometry suites pin the
# A3-era arithmetic on explicitly-sized sheets instead.
# 全新图纸为 A1（2026-10-16 重定基）、带图框、中英对照、带 A1 装订边距与完整格网。
# 这就是新默认**自身**的契约 —— 几何套件改为在显式定尺寸的图纸上钉 A3 时代算术。
func gpTestNewDefaultSheetIsA1() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpEq(gpS.gpWidthMM, 841.0, "默认图幅宽应为 A1 的 841mm")
	gpEq(gpS.gpHeightMM, 594.0, "默认图幅高应为 A1 的 594mm")
	gpCheck(gpS.gpFrameOn, "新图纸默认应显示图框")
	gpEq(gpS.gpLabelMode, GPSheet.GP_LABEL_BOTH, "默认应为中英对照")
	gpEq(gpS.gpTitleBlock.size(), GP_FIELD_COUNT, "标题栏应为 %d 个标准字段" % [GP_FIELD_COUNT])
	# The A1 filing format: 25 mm binding edge on the left, 10 mm on the other three sides.
	# A1 装订幅面：左边 25mm 装订边，其余三边 10mm。
	var gpWant: Array = GPSheet.gpDefaultMarginsFor(841.0, 594.0)
	gpCheck(gpS.gpFrameMarginsAreDefault(), "A1 新图纸的边距应即其纸幅默认（不写键的前提）")
	for gpI in gpWant.size():
		gpApprox(float(gpS.gpFrameMargins[gpI]), float(gpWant[gpI]), 0.0001,
			"A1 默认边距[%d]应为装订幅面值" % [gpI])
	# One-scale rule. ⚠️ ISO 216 ROUNDS its sizes (A1 = 841 x 594 is the rounded A0 half, not an
	# exact 840 x 594), so the long-edge ratio is 841/420 = 2.00238 while the short edge is an
	# exact 594/297 = 2.0 — the scale derives from the LONG edge, hence the 0.24 % offset. The
	# expectation is derived from the same division the implementation uses, so this pins the RULE
	# (long edge / 420), not a hand-picked constant.
	# 一把尺规则。⚠️ ISO 216 对尺寸做了**圆整**（A1 = 841×594 是 A0 对裁后的圆整值，并非精确的
	# 840×594），故长边比为 841/420 = 2.00238，而短边恰为 594/297 = 2.0 —— 比例取自**长边**，
	# 因而带这 0.24% 的偏差。期望值与实现同式推导（长边 / 420），钉住的是**规则**、不是手挑常量。
	gpApprox(gpS.gpFrameScale(), 841.0 / 420.0, 0.0001, "A1 的图幅视觉比例应为长边/420")
	var gpBlk: Vector2 = gpS.gpTbBlockSize()
	gpApprox(gpBlk.x, 135.0 * 841.0 / 420.0, 0.0001, "A1 图签宽应为 135 × 841/420 ≈ 270.32mm（2026-10-16 宽度收窄 1/4）")
	gpApprox(gpBlk.y, 50.0 * 841.0 / 420.0, 0.0001, "A1 图签高应为 50 × 841/420 ≈ 100.12mm")
	var gpEntry: Variant = gpS.gpTitleBlock.get("sheet_size")
	gpCheck(gpEntry != null, "标题栏应含「图幅」字段")
	if gpEntry != null:
		var gpV: Variant = (gpEntry as Dictionary).get("value")
		gpEq(str((gpV as Dictionary).get("zh", "")), "A1", "「图幅」格应自动回填 A1")


# Frame size, label mode and title-block values survive a save / load round trip.
# 图幅、语言模式与标题栏取值在存 / 取往返后保持不变。
func gpTestFrameSurvivesRoundTrip() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpWidthMM = 594.0
	gpS.gpHeightMM = 420.0
	gpS.gpLabelMode = GPSheet.GP_LABEL_EN
	gpS.gpTitleBlock["project"] = {"value": {"zh": "示例项目", "en": "Sample Project"}}
	var gpD: Dictionary = gpS.gpToDict()
	var gpBack: GPSheet = GPSheet.gpFromDict(gpD)
	gpEq(gpBack.gpWidthMM, 594.0, "图幅宽应随存档往返")
	gpEq(gpBack.gpHeightMM, 420.0, "图幅高应随存档往返")
	gpEq(gpBack.gpLabelMode, GPSheet.GP_LABEL_EN, "语言模式应随存档往返")
	var gpEntry: Variant = gpBack.gpTitleBlock.get("project")
	gpCheck(gpEntry != null, "标题栏的 project 字段应回来")
	if gpEntry != null:
		var gpV: Variant = (gpEntry as Dictionary).get("value")
		gpEq(str((gpV as Dictionary).get("en", "")), "Sample Project", "英文值应随存档往返")
		gpEq(str((gpV as Dictionary).get("zh", "")), "示例项目", "中文值应随存档往返")


# An untouched sheet writes NO frame keys, so archives from older builds stay byte-stable.
# 未动过图框的图纸不写出图框键，使旧版本产出的存档保持逐字节稳定。
func gpTestDefaultFrameStaysOutOfTheArchive() -> void:
	var gpD: Dictionary = GPSheet.gpNew("sheet-1", "首页", 0).gpToDict()
	gpCheck(not gpD.has("label_mode"),
		"默认（中英对照）不应写出 label_mode，否则每份旧档都会被改写")
	gpCheck(gpD.has("width_mm"), "图幅宽应始终写出，使非 A3 图纸不会静默变回 A3")


# An archive predating the frame opens with the FULL standard block, not a partial one.
# 图框功能之前写的旧档应以**完整**标准标题栏打开，而非残缺。
func gpTestLegacyArchiveGetsFullBlock() -> void:
	var gpOld: Dictionary = {"id": "sheet-1", "name": "旧图", "index": 0,
		"nodes": [], "edges": [], "shapes": []}
	var gpS: GPSheet = GPSheet.gpFromDict(gpOld)
	gpEq(gpS.gpTitleBlock.size(), GP_FIELD_COUNT, "旧档应补全为 %d 个标准字段" % [GP_FIELD_COUNT])
	gpEq(gpS.gpWidthMM, 420.0, "旧档应回落到 A3 宽")
	gpEq(gpS.gpLabelMode, GPSheet.GP_LABEL_BOTH, "旧档应回落到中英对照")


# The label mode selects which language a title-block VALUE renders in.
# 语言模式决定标题栏**取值**用哪种语言渲染。
func gpTestLabelModeSelectsValueLanguage() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpTitleBlock["drawing_title"] = {"value": {"zh": "工艺流程图", "en": "Process Flow Diagram"}}
	gpS.gpLabelMode = GPSheet.GP_LABEL_ZH
	gpEq(gpS.gpTitleValue("drawing_title"), "工艺流程图", "中文模式应取中文值")
	gpS.gpLabelMode = GPSheet.GP_LABEL_EN
	gpEq(gpS.gpTitleValue("drawing_title"), "Process Flow Diagram", "英文模式应取英文值")


# Tag numbers are identifiers, not prose: they must be reachable regardless of label mode.
# 位号是标识而非文字：无论语言模式如何都必须可取。
func gpTestLabelModeNeverReachesTags() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpLabelMode = GPSheet.GP_LABEL_EN
	var gpN: GPPIDNode = gpS.gpGraph.gpNewNode("n1", "pump", "P-101", Vector2(10.0, 20.0))
	gpS.gpGraph.gpAddNode(gpN)
	gpEq(gpN.gpTag, "P-101", "切到英文模式后位号必须原样为 P-101，不得被翻译")


# Standard sheet presets are the ISO 216 sizes in mm.
# 标准图幅预设即 ISO 216 的毫米尺寸。
func gpTestSheetPresetsAreIsoSizes() -> void:
	var gpA4: Vector2 = GPSheet.GP_SHEET_PRESETS["A4"]
	var gpA3: Vector2 = GPSheet.GP_SHEET_PRESETS["A3"]
	var gpA0: Vector2 = GPSheet.GP_SHEET_PRESETS["A0"]
	gpEq(gpA4.x, 297.0, "A4 宽应为 297mm")
	gpEq(gpA4.y, 210.0, "A4 高应为 210mm")
	gpEq(gpA3.x, 420.0, "A3 宽应为 420mm")
	gpEq(gpA0.x, 1189.0, "A0 宽应为 1189mm")


# Changing the sheet size rewrites the SIZE cell instead of leaving a stale value.
# 改图幅会重写「图幅」格，而非留下过期值。
func gpTestSheetSizeCellTracksSheet() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpWidthMM = 841.0
	gpS.gpHeightMM = 594.0
	gpS.gpSyncSheetSizeField()
	var gpEntry: Variant = gpS.gpTitleBlock.get("sheet_size")
	gpCheck(gpEntry != null, "应存在「图幅」字段")
	if gpEntry != null:
		var gpV: Variant = (gpEntry as Dictionary).get("value")
		gpEq(str((gpV as Dictionary).get("zh", "")), "A1", "图幅改为 A1 后「图幅」格应回填 A1")


# Tracing-underlay path + alpha must round-trip through the archive, and a sheet that never
# touched the underlay must NOT write background keys (ADR-7 byte-stability for old archives).
# 追踪底图的路径与透明度必须随存档往返；从未设置底图的图纸不得写出背景键
# （ADR-7 旧档字节稳定）。
func gpTestBackgroundRoundTrip() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpBackgroundPath = "user://trace_underlay.png"
	gpS.gpBackgroundAlpha = 0.5
	var gpD: Dictionary = gpS.gpToDict()
	gpCheck(gpD.has("background_path"), "设置了底图应写出 background_path")
	gpCheck(gpD.has("background_alpha"), "非默认透明度应写出 background_alpha")
	var gpBack: GPSheet = GPSheet.gpFromDict(gpD)
	gpEq(gpBack.gpBackgroundPath, "user://trace_underlay.png",
		"底图路径应随存档往返")
	gpEq(gpBack.gpBackgroundAlpha, 0.5, "底图透明度应随存档往返")


func gpTestBackgroundStaysOutOfTheArchiveByDefault() -> void:
	var gpD: Dictionary = GPSheet.gpNew("sheet-1", "首页", 0).gpToDict()
	gpCheck(not gpD.has("background_path"),
		"无底图不应写出 background_path，否则旧档会被改写")
	gpCheck(not gpD.has("background_alpha"),
		"默认透明度（0.35）不应写出 background_alpha，保持旧档字节稳定")


# ---------------------------------------------------------------------------
# 图框边距数据化（Rev.3 阶段 0a） / Frame margins as data (Rev.3 stage 0a)
# ---------------------------------------------------------------------------
# WHY THESE EXIST / 为何有这几条：the margins stopped being renderer constants and became sheet
# data. Data that is written to disk needs the same two guards every other sheet key already has —
# it must come back unchanged, and it must NOT appear for a sheet that never touched it (or every
# legacy archive would be rewritten on open).
# 边距不再是渲染器常量，而是图纸数据。凡写入磁盘的数据都需要其它图纸键已有的两道护栏 ——
# 必须原样回来；且从未动过它的图纸**不得**出现该键（否则每份旧档一打开就被改写）。


# Margins must survive a save / load round trip.
# 边距必须随存 / 取往返保持不变。
func gpTestFrameMarginsRoundTrip() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	var gpWant: Array = [30.0, 8.0, 8.0, 8.0]
	gpS.gpSetFrameMargins(gpWant)
	var gpD: Dictionary = gpS.gpToDict()
	gpCheck(gpD.has("frame_margins"), "改过边距应写出 frame_margins")
	var gpBack: GPSheet = GPSheet.gpFromDict(gpD)
	gpEq(gpBack.gpFrameMargins.size(), 4, "边距应恒为 4 项")
	for gpI in 4:
		gpApprox(float(gpBack.gpFrameMargins[gpI]), float(gpWant[gpI]), 0.0001,
			"边距第 %d 项应随存档往返" % [gpI])


# A sheet that never moved its frame must not gain the key (ADR-7 byte-stability).
# 从未动过图框的图纸不得多出该键（ADR-7 字节稳定）。
func gpTestDefaultFrameMarginsStayOutOfTheArchive() -> void:
	var gpD: Dictionary = GPSheet.gpNew("sheet-1", "首页", 0).gpToDict()
	gpCheck(not gpD.has("frame_margins"),
		"默认边距不应写出 frame_margins，否则每份旧档都会被改写")


# An archive written before the key existed opens with the standard margins, and re-saves without
# gaining the key.
# 本键出现之前的存档应以标准边距打开，且重新保存时不因此多出该键。
func gpTestLegacyArchiveGetsDefaultMargins() -> void:
	var gpOld: Dictionary = {"id": "sheet-1", "name": "旧图", "index": 0,
		"nodes": [], "edges": [], "shapes": []}
	var gpS: GPSheet = GPSheet.gpFromDict(gpOld)
	gpEq(gpS.gpFrameMargins.size(), 4, "旧档应回填 4 项边距")
	for gpI in 4:
		gpApprox(float(gpS.gpFrameMargins[gpI]),
			float(GPSheet.GP_FRAME_MARGINS_DEFAULT[gpI]), 0.0001,
			"旧档第 %d 项边距应回落到默认值" % [gpI])
	gpCheck(gpS.gpFrameMarginsAreDefault(), "旧档边距应判定为默认，故重存不写出该键")
	gpCheck(not gpS.gpToDict().has("frame_margins"),
		"旧档重新保存后仍不得写出 frame_margins")


# Margins are a FREE property of the sheet: any value may be stored, including a negative one (which
# means that frame line lies outside the sheet). The ONE invariant is that the inner rectangle must not
# turn inside out — a collapsed frame is neither drawn nor grabbable.
# 边距是图纸上**自由**的属性：任何取值都可存下，包括负值（意味着该条图框线位于纸面之外）。唯一的**一条**
# 不变量是内框不得内翻 —— 塌缩的图框既不被绘制、也无法抓取。
#
# ⚠️ THIS REPLACED gpTestFrameMarginsAreClampedIntoThePaper (2026-10-16), which asserted that every margin
# was lifted to a 1 mm floor and that each pair stayed inside the paper. Both are false by design now: the
# user asked for free movement with no limits (「自由移动，没有限制」), so the paper stopped being a
# container and only the frame's own consistency remains.
# ⚠️ 本测试替代 gpTestFrameMarginsAreClampedIntoThePaper（2026-10-16）：后者断言每条边距都被抬到 1mm
# 下限、且每对之和都不超过纸面。如今两者都按设计为假：用户要求无限制的自由移动（「自由移动，没有限制」），
# 纸面因此不再是容器，只剩图框自身的自洽。
func gpTestFrameMarginsMayLeaveThePaperButNeverCollapse() -> void:
	var gpCases: Array = [
		[0.0, 0.0, 0.0, 0.0],
		[-50.0, -50.0, -50.0, -50.0],
		[300.0, 300.0, 300.0, 300.0],
		[500.0, 1.0, 1.0, 500.0],
	]
	for gpC in gpCases:
		var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
		gpS.gpSetFrameMargins(gpC)
		var gpW: float = gpS.gpWidthMM - float(gpS.gpFrameMargins[GPSheet.GP_MARGIN_LEFT]) \
			- float(gpS.gpFrameMargins[GPSheet.GP_MARGIN_RIGHT])
		var gpH: float = gpS.gpHeightMM - float(gpS.gpFrameMargins[GPSheet.GP_MARGIN_TOP]) \
			- float(gpS.gpFrameMargins[GPSheet.GP_MARGIN_BOTTOM])
		gpCheck(gpW >= GPSheet.GP_FRAME_MIN_SIZE_MM - 0.0001,
			"边距 %s：内框宽不得小于最小尺寸（实测 %.4f）" % [str(gpC), gpW])
		gpCheck(gpH >= GPSheet.GP_FRAME_MIN_SIZE_MM - 0.0001,
			"边距 %s：内框高不得小于最小尺寸（实测 %.4f）" % [str(gpC), gpH])

	# A negative margin survives the write point UNTOUCHED — that is the whole point of the reversal.
	# 负边距原样穿过写口 —— 这正是本次反转的全部意义。
	var gpNeg: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpNeg.gpSetFrameMargins([-50.0, -50.0, -50.0, -50.0])
	for gpI in 4:
		gpApprox(float(gpNeg.gpFrameMargins[gpI]), -50.0, 0.0001,
			"负边距不得被抬到下限（第 %d 项）" % gpI)
	gpCheck(not gpNeg.gpFrameMarginsAreDefault(),
		"非默认（此处为负）的边距应被判为非默认，从而会被写进存档")

	# An inside-out pair is REPAIRED (proportionally scaled) rather than left collapsed, and the repaired
	# values are stored — so a hand-edited archive cannot poison the geometry layer.
	# 内翻的一对边距会被**修复**（按比例回缩）而不是任由其塌缩，且存下的是修复后的值 —— 故手工改过的存档
	# 无法污染几何层。
	var gpFat: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpFat.gpSetFrameMargins([500.0, 1.0, 1.0, 500.0])
	gpCheck(gpFat.gpWidthMM - float(gpFat.gpFrameMargins[GPSheet.GP_MARGIN_LEFT])
			- float(gpFat.gpFrameMargins[GPSheet.GP_MARGIN_RIGHT])
			>= GPSheet.GP_FRAME_MIN_SIZE_MM - 0.0001,
		"500+1 应被修复到留下最小内框宽")
	gpCheck(gpFat.gpHeightMM - float(gpFat.gpFrameMargins[GPSheet.GP_MARGIN_TOP])
			- float(gpFat.gpFrameMargins[GPSheet.GP_MARGIN_BOTTOM])
			>= GPSheet.GP_FRAME_MIN_SIZE_MM - 0.0001,
		"1+500 应被修复到留下最小内框高")


# ===========================================================================
# Title-block docking persistence (Rev.3 stage 1) / 图签停靠的持久化（Rev.3 阶段 1）
# ===========================================================================

# The docking pair must survive a save / load round trip.
# 停靠对必须随存 / 取往返保持不变。
func gpTestTitleBlockDockingRoundTrip() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpSetTbPlacement(GPSheet.GP_TB_ANCHOR_TOP_LEFT, Vector2(30.0, 20.0))
	var gpD: Dictionary = gpS.gpToDict()
	gpCheck(gpD.has("tb_anchor"), "改过锚角应写出 tb_anchor")
	gpCheck(gpD.has("tb_offset"), "改过偏移应写出 tb_offset")
	gpEq(int(gpD["tb_anchor"]), GPSheet.GP_TB_ANCHOR_TOP_LEFT, "锚角应随存档写出")
	var gpOff: Array = gpD["tb_offset"] as Array
	gpApprox(float(gpOff[0]), 30.0, 0.0001, "偏移 x 应随存档写出")
	gpApprox(float(gpOff[1]), 20.0, 0.0001, "偏移 y 应随存档写出")
	var gpBack: GPSheet = GPSheet.gpFromDict(gpD)
	gpEq(gpBack.gpTbAnchor, GPSheet.GP_TB_ANCHOR_TOP_LEFT, "锚角应随存 / 取往返")
	gpCheck((gpBack.gpTbOffset as Vector2).is_equal_approx(Vector2(30.0, 20.0)), "偏移应随存 / 取往返")


# A sheet whose block was never moved must not gain the keys (ADR-7 byte-stability).
# 图签从未被挪动的图纸不得多出这两个键（ADR-7 字节稳定）。
func gpTestDefaultDockingStaysOutOfTheArchive() -> void:
	var gpD: Dictionary = GPSheet.gpNew("sheet-1", "首页", 0).gpToDict()
	gpCheck(not gpD.has("tb_anchor"), "默认锚角不应写出 tb_anchor，否则每份旧档都会被改写")
	gpCheck(not gpD.has("tb_offset"), "默认偏移不应写出 tb_offset，否则每份旧档都会被改写")


# An archive written before the keys existed opens with the default pair (bottom-right, flush), and
# re-saves without gaining the keys.
# 本二键出现之前的存档应以默认停靠对（右下、贴角）打开，且重新保存时不因此多出这两个键。
func gpTestLegacyArchiveGetsDefaultDocking() -> void:
	var gpOld: Dictionary = {"id": "sheet-1", "name": "旧图", "index": 0,
		"nodes": [], "edges": [], "shapes": []}
	var gpS: GPSheet = GPSheet.gpFromDict(gpOld)
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, "旧档锚角应回落到默认（右下）")
	gpCheck((gpS.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO), "旧档偏移应回落到默认（零）")
	gpCheck(gpS.gpTbPlacementIsDefault(), "旧档停靠对应判定为默认，故重存不写出这两个键")
	gpCheck(not gpS.gpToDict().has("tb_anchor"), "旧档重新保存后仍不得写出 tb_anchor")
	gpCheck(not gpS.gpToDict().has("tb_offset"), "旧档重新保存后仍不得写出 tb_offset")


# Hand-edited / corrupted archive values must not poison the docking model: an out-of-range anchor is
# folded into the four corners by its setter, and a malformed offset is IGNORED (keeps the default)
# rather than half-applied.
# 手工改过 / 损坏的存档值不得污染停靠模型：越界锚角由其 setter 收进四角之内，格式不对的偏移被**忽略**
# （保留默认）、而不是半途生效。
func gpTestMalformedDockingFallsBackSafely() -> void:
	var gpS: GPSheet = GPSheet.gpFromDict({"id": "s", "name": "x", "index": 0,
		"nodes": [], "edges": [], "shapes": [], "tb_anchor": 9})
	gpEq(gpS.gpTbAnchor, GPSheet.GP_TB_ANCHOR_TOP_LEFT, "越界锚角 9 应被收进四角之内（3 = 左上）")
	var gpS2: GPSheet = GPSheet.gpFromDict({"id": "s", "name": "x", "index": 0,
		"nodes": [], "edges": [], "shapes": [], "tb_offset": "nonsense"})
	gpCheck((gpS2.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO), "畸形偏移应被忽略、保留默认")
	var gpS3: GPSheet = GPSheet.gpFromDict({"id": "s", "name": "x", "index": 0,
		"nodes": [], "edges": [], "shapes": [], "tb_anchor": "x", "tb_offset": [1.0]})
	gpEq(gpS3.gpTbAnchor, GPSheet.GP_TB_ANCHOR_BOTTOM_RIGHT, "非数值锚角应被忽略")
	gpCheck((gpS3.gpTbOffset as Vector2).is_equal_approx(Vector2.ZERO), "长度不足的偏移应被忽略")


# P0-6: every standard paper size gets the margins its zone ruler needs. A0 used to inherit the
# A3-era 25/5/5/5; at scale 2.83 its 8.07 mm zone text no longer fits a 5 mm band and three of
# the four rulers silently disappeared.
# P0-6：每种标准图幅都得到坐标带放得下的边距。A0 过去继承 A3 的 25/5/5/5；在 2.83 倍尺下
# 8.07mm 的坐标带文字放不进 5mm 带宽，四边标号会静默消失三边。
func gpTestA0DefaultMarginsKeepZoneLabels() -> void:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpWidthMM = 1189.0
	gpS.gpHeightMM = 841.0
	gpS.gpSetFrameMargins(GPSheet.gpDefaultMarginsFor(gpS.gpWidthMM, gpS.gpHeightMM))
	gpEq(gpS.gpFrameMargins, [25.0, 10.0, 10.0, 10.0], "A0 默认边距应为 25/10/10/10")
	var gpMM: float = GPTextRole.GP_FRAME_GRID_MM * gpS.gpFrameScale()
	gpEq(GPFrameGeometry.gpZoneLabels(gpS, gpMM).size(), 40, "A0 四边都应有坐标带标号")


# P0-6: changing the paper size through the command re-derives the margins when they were the
# old size's default, rewrites the SIZE cell, and is one undo step.
# P0-6：经命令改图幅时，边距仍是旧默认则重推、重写「图幅」格，且是一个撤销步。
func gpTestPaperSizeChangeRedrivesMarginsAndUndoes() -> void:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpWidthMM = 420.0
	gpS.gpHeightMM = 297.0
	gpS.gpSetFrameMargins(GPSheet.gpDefaultMarginsFor(420.0, 297.0))
	gpS.gpTitleBlock = GPSheet.gpDefaultTitleBlock()
	gpS.gpSyncSheetSizeField()
	var gpCtx: GPCommandContext = GPCommandContext.new(GPPIDGraph.new(), GPIdGen.new())
	var gpCmd: GPMutateSheetCommand = GPMutateSheetCommand.new(gpS, {
		GPMutateSheetCommand.GP_FIELD_WIDTH: 841.0,
		GPMutateSheetCommand.GP_FIELD_HEIGHT: 594.0,
	})
	gpCheck(gpCmd.gpExecute(gpCtx), "改图幅命令应执行")
	gpEq(gpS.gpWidthMM, 841.0, "宽度应变为 A1")
	gpEq(gpS.gpFrameMargins, [25.0, 10.0, 10.0, 10.0], "A3->A1 应重推为 A1 默认边距")
	gpEq(gpS.gpTitleValue("sheet_size"), "A1", "图幅格应同步为 A1")
	var gpLabels: Array = GPFrameGeometry.gpZoneLabels(gpS,
		GPTextRole.GP_FRAME_GRID_MM * gpS.gpFrameScale())
	gpEq(gpLabels.size(), 40, "A3->A1 后四边坐标带应完整")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpS.gpWidthMM, 420.0, "撤销应恢复 A3 宽度")
	gpEq(gpS.gpFrameMargins, [25.0, 5.0, 5.0, 5.0], "撤销应恢复 A3 边距")
	gpEq(gpS.gpTitleValue("sheet_size"), "A3", "撤销应恢复 A3 图幅格")
	gpCmd.gpRedo(gpCtx)
	gpEq(gpS.gpWidthMM, 841.0, "重做应再次变为 A1")


# P0-4: the title block is one undoable sheet field. A dialog edit must reach the model through
# the command, not a direct dictionary poke the close guard cannot see.
# P0-4：图签是一个可撤销的图纸字段。对话框编辑必须经命令进入模型，而不是关闭护栏看不到的
# 直接字典写入。
func gpTestTitleBlockFieldCommandUndoes() -> void:
	var gpS: GPSheet = GPSheet.gpNew("s", "s", 0)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpS.gpGraph, GPIdGen.new())
	var gpAfter: Dictionary = gpS.gpTitleBlock.duplicate(true)
	gpAfter["project"] = {"value": {"zh": "示例项目", "en": "Sample"}}
	var gpCmd: GPMutateSheetCommand = GPMutateSheetCommand.new(gpS, {
		GPMutateSheetCommand.GP_FIELD_TITLE_BLOCK: gpAfter,
	}, "编辑图签")
	gpCheck(gpCmd.gpExecute(gpCtx), "图签字段命令应执行")
	gpEq(gpS.gpTitleValue("project"), "示例项目", "图签值应写入")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpS.gpTitleValue("project"), "", "撤销应恢复旧图签（默认空值）")
	gpCheck(gpS.gpTitleBlock.has("company"), "撤销后仍应保留完整标准字段")


# P1-9 (folded into P0-4): the title-block offset clamp must use THIS sheet's block size.
# On A1 the legal max is frame - 270.32, not frame - 135.
# P1-9（并入 P0-4）：图签偏移钳制必须用**本图纸**的块尺寸。A1 的合法上限是内框减 270.32，
# 而不是内框减 135。
func gpTestTitleBlockClampUsesScaledBlock() -> void:
	var gpS: GPSheet = GPSheet.gpNew("s", "s", 0)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpS.gpGraph, GPIdGen.new())
	var gpCmd: GPMutateSheetCommand = GPMutateSheetCommand.new(gpS, {
		GPMutateSheetCommand.GP_FIELD_TB_OFFSET: Vector2(600.0, 0.0),
	})
	gpCheck(gpCmd.gpExecute(gpCtx), "偏移命令应执行")
	var gpFrame: Rect2 = GPFrameGeometry.gpFrameRect(gpS)
	var gpWant: float = gpFrame.size.x - gpS.gpTbBlockSize().x
	gpApprox(gpS.gpTbOffset.x, gpWant, 0.01, "A1 偏移上限应按 270.32mm 块宽钳制")


# P0-6: a user who hand-tuned the margins keeps them across a paper-size change. Only the
# OLD SIZE'S DEFAULT is re-derived; a deliberate 30 mm margin is a decision, not a default.
# P0-6：手工调过边距的用户在改图幅后保留其数值。只有**旧纸幅的默认值**才重推；30mm 是
# 决定、不是默认。
func gpTestSheetSizePreservesCustomMargins() -> void:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpWidthMM = 420.0
	gpS.gpHeightMM = 297.0
	gpS.gpSetFrameMargins([30.0, 6.0, 7.0, 8.0])
	var gpCtx: GPCommandContext = GPCommandContext.new(GPPIDGraph.new(), GPIdGen.new())
	var gpCmd: GPMutateSheetCommand = GPMutateSheetCommand.new(gpS, {
		GPMutateSheetCommand.GP_FIELD_WIDTH: 841.0,
		GPMutateSheetCommand.GP_FIELD_HEIGHT: 594.0,
	})
	gpCheck(gpCmd.gpExecute(gpCtx), "改图幅命令应执行")
	gpEq(gpS.gpFrameMargins, [30.0, 6.0, 7.0, 8.0], "手工边距不得被新图幅默认值覆盖")


# P0-4: the independent sheet fields (frame switch / drawing language / underlay) are one
# undoable command too — the dialog used to write them directly.
# P0-4：独立图纸字段（图框开关 / 图面语言 / 底图）也是一个可撤销命令 —— 对话框过去直接写。
func gpTestIndependentSheetFieldsUndo() -> void:
	var gpS: GPSheet = GPSheet.gpNew("s", "s", 0)
	var gpCtx: GPCommandContext = GPCommandContext.new(gpS.gpGraph, GPIdGen.new())
	var gpCmd: GPMutateSheetCommand = GPMutateSheetCommand.new(gpS, {
		GPMutateSheetCommand.GP_FIELD_FRAME_ON: false,
		GPMutateSheetCommand.GP_FIELD_LABEL_MODE: GPSheet.GP_LABEL_EN,
		GPMutateSheetCommand.GP_FIELD_BG_PATH: "user://trace.png",
		GPMutateSheetCommand.GP_FIELD_BG_ALPHA: 0.55,
	}, "图纸字段")
	gpCheck(gpCmd.gpExecute(gpCtx), "独立图纸字段命令应执行")
	gpCheck(not gpS.gpFrameOn, "图框开关应写入")
	gpEq(gpS.gpLabelMode, GPSheet.GP_LABEL_EN, "图面语言应写入")
	gpEq(gpS.gpBackgroundPath, "user://trace.png", "底图路径应写入")
	gpApprox(gpS.gpBackgroundAlpha, 0.55, 0.0001, "底图透明度应写入")
	gpCmd.gpUndo(gpCtx)
	gpCheck(gpS.gpFrameOn, "撤销应恢复图框显示")
	gpEq(gpS.gpLabelMode, GPSheet.GP_LABEL_BOTH, "撤销应恢复默认语言")
	gpEq(gpS.gpBackgroundPath, "", "撤销应清空底图路径")
	gpApprox(gpS.gpBackgroundAlpha, 0.35, 0.0001, "撤销应恢复默认透明度")


# P0-5: a pre-A1 archive carries A3-era symbol data but no per-node size. It must be inferred
# as 0.5 (the A1 rebase doubled the DATA), and that decision must survive a re-save.
# P0-5：A1 之前的存档是 A3 时代图元数据、且无逐节点尺寸。必须推断为 0.5（A1 重定基把
# **数据**翻倍），且该决定必须在重存后存活。
func gpTestLegacyArchiveGetsHalfSymbolScale() -> void:
	var gpOld: Dictionary = {"id": "s", "name": "旧图", "index": 0,
		"width_mm": 420.0, "height_mm": 297.0,
		"meta": {"version": "1.2"}, "nodes": [], "edges": [], "shapes": []}
	var gpS: GPSheet = GPSheet.gpFromDict(gpOld)
	gpApprox(gpS.gpSymbolScale, 0.5, 0.0001, "无 symbol_scale 的非 A1 旧档应推断为 0.5")
	var gpD: Dictionary = gpS.gpToDict()
	gpApprox(float(gpD.get("symbol_scale", 0.0)), 0.5, 0.0001,
		"旧档重存应显式写出 0.5")
	var gpBack: GPSheet = GPSheet.gpFromDict(gpD)
	gpApprox(gpBack.gpSymbolScale, 0.5, 0.0001, "0.5 应随存档往返")


# A1 is the rebased default: an A1 archive without a marker is full-scale, not legacy.
# A1 是重定基后的默认图幅：无标记的 A1 存档按全尺度，而不是旧档。
func gpTestA1ArchiveIsFullScaleWithoutMarker() -> void:
	var gpS: GPSheet = GPSheet.gpFromDict({"id": "s", "name": "x", "index": 0,
		"width_mm": 841.0, "height_mm": 594.0, "meta": {"version": "1.2"},
		"nodes": [], "edges": [], "shapes": []})
	gpApprox(gpS.gpSymbolScale, 1.0, 0.0001, "A1 无标记应按 1.0")
	gpCheck(not gpS.gpToDict().has("symbol_scale"), "1.0 不应写出 symbol_scale")


# A NEW A3 drawing writes meta.symbol_scale=1.0, so it is not mistaken for a legacy A3 on
# reopen. Without this, the round trip would silently shrink it to 0.5.
# 新建 A3 图写出 meta.symbol_scale=1.0，使重开时不会被误判为旧 A3。缺此标记，往返会把它
# 静默缩到 0.5。
func gpTestNewA3StaysFullScale() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpMeta["symbol_scale"] = 1.0
	var gpS: GPSheet = GPSheet.gpFromDict({"id": "s", "name": "x", "index": 0,
		"width_mm": 420.0, "height_mm": 297.0, "meta": gpG.gpMeta,
		"nodes": [], "edges": [], "shapes": []})
	gpApprox(gpS.gpSymbolScale, 1.0, 0.0001, "带 1.0 标记的新 A3 应按全尺度")


# The library applies the active document's scale to the SHARED defs, so every consumer sees
# the legacy footprint without touching 40+ gpDefaultSize call sites. Reset afterwards so the
# global cache does not leak into other suites.
# 图元库把活动文档尺度施加到**共享** def，使每个消费方看到旧档包络，而无需改 40 余处调用点。
# 测试末尾复位，避免全局缓存泄漏到其它套件。
func gpTestLibraryAppliesDocumentScale() -> void:
	var gpDefs: Array[GPSymbolDef] = GPSymbolLibrary.gpDefaultDefs()
	var gpBase: Vector2 = gpDefs[0].gpDefaultSize
	GPSymbolLibrary.gpSetDocSizeScale(0.5)
	var gpHalf: Vector2 = gpDefs[0].gpDefaultSize
	GPSymbolLibrary.gpSetDocSizeScale(1.0)
	var gpFull: Vector2 = gpDefs[0].gpDefaultSize
	gpApprox(gpHalf.x, gpBase.x * 0.5, 0.0001, "0.5 尺度应把包络减半")
	gpApprox(gpHalf.y, gpBase.y * 0.5, 0.0001, "0.5 尺度应把包络减半（y）")
	gpApprox(gpFull.x, gpBase.x, 0.0001, "复位 1.0 应恢复基准包络")
	gpApprox(gpFull.y, gpBase.y, 0.0001, "复位 1.0 应恢复基准包络（y）")


# A NEW non-A1 sheet writes 1.0 explicitly, because paper size alone cannot distinguish it from
# a legacy A3 archive. Without the key, the sheet-only round trip would reopen it at 0.5.
# 新建的非 A1 图纸显式写 1.0，因为单凭纸幅无法把它与旧 A3 区分。缺这个键，图纸级往返会把它
# 以 0.5 重开。
func gpTestNewA3SheetKeyRoundTripsFullScale() -> void:
	var gpS: GPSheet = GPSheet.gpNew("s", "s", 0)
	gpS.gpWidthMM = 420.0
	gpS.gpHeightMM = 297.0
	var gpD: Dictionary = gpS.gpToDict()
	gpApprox(float(gpD.get("symbol_scale", 0.0)), 1.0, 0.0001,
		"新建 A3 图纸应显式写出 1.0")
	var gpBack: GPSheet = GPSheet.gpFromDict(gpD)
	gpApprox(gpBack.gpSymbolScale, 1.0, 0.0001, "A3 图纸往返后仍为 1.0")
